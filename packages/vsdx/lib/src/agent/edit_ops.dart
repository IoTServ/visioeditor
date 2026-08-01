/// Imperative **Edit Ops** (v0): apply structured edits to an existing document.
///
/// Two entry points share one implementation:
///   * [applyOps] mutates an in-memory [VsdxDocument] — used by the app
///     live-preview bridge (no disk write, instant repaint).
///   * [applyOpsBytes] re-parses `.vsdx` bytes, applies ops, and writes them
///     back through [VsdxWriter] (load-preserve-patch) — used by the CLI /
///     file-mode MCP tools.
///
/// Supported ops include page-tab edits (`add_page`, `duplicate_page`,
/// `rename_page`, `delete_page`, `move_page`, `set_page`), layer edits
/// (`add_layer`, `set_layer`, `delete_layer`, `assign_layer`), plus shape
/// edits: `add_shape`, `add_connector`, `set_style`, `set_text`, `move_shape`,
/// `resize_shape`, `duplicate_shape`, `group`, `ungroup`, `z_order`, `align`,
/// `distribute`, `set_data`, `set_links`, `set_connector`,
/// `reconnect_connector`, `set_connection_points`, `reparent_shapes`,
/// `set_collapsed`, `delete_shape`.
/// Schema: `skills/visioeditor-skill/references/spec-schema.md`.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vsdx/vsdx.dart';

import 'agent_style.dart';
import 'stencil_catalog.dart';

/// Outcome of applying a batch of ops.
class ApplyResult {
  ApplyResult(
    this.document,
    this.createdIds,
    this.log, {
    this.pageIndex = 0,
    this.createdPageIds = const <int>[],
    this.createdLayerIds = const <int>[],
    this.activatePage = false,
  });

  /// The edited document.
  final VsdxDocument document;

  /// Root shape ids created by add / duplicate / group ops, in op order.
  final List<int> createdIds;

  /// Page ids created by add / duplicate page ops, in op order.
  final List<int> createdPageIds;

  /// Layer ids created by add-layer ops, in op order.
  final List<int> createdLayerIds;

  /// Page context after the batch. Later shape ops in the same batch use it.
  final int pageIndex;

  /// Whether a successful page op asks the live editor to show [pageIndex].
  final bool activatePage;

  /// Human-readable notes (skipped ops, unresolved ids, …).
  final List<String> log;
}

/// File-mode outcome, including the effective page and skipped-op diagnostics
/// needed by CLI/MCP callers to report the actual result truthfully.
class ApplyBytesResult {
  ApplyBytesResult({
    required this.bytes,
    required this.pageIndex,
    required this.changed,
    required this.createdIds,
    this.createdPageIds = const <int>[],
    this.createdLayerIds = const <int>[],
    required this.log,
  });

  final Uint8List bytes;
  final int pageIndex;
  final bool changed;
  final List<int> createdIds;
  final List<int> createdPageIds;
  final List<int> createdLayerIds;
  final List<String> log;
}

/// Apply [ops] to [doc]'s page [pageIndex]. Returns the edited document plus a
/// log; unknown ops or bad references are recorded, not thrown.
ApplyResult applyOps(
  VsdxDocument doc,
  List<Map<String, dynamic>> ops, {
  int pageIndex = 0,
}) {
  final created = <int>[];
  final createdPages = <int>[];
  final createdLayers = <int>[];
  final log = <String>[];
  if (doc.pages.isEmpty) {
    return ApplyResult(
      doc,
      created,
      <String>['document has no pages'],
      pageIndex: 0,
    );
  }
  var workingDoc = doc;
  var idx = pageIndex.clamp(0, doc.pages.length - 1);
  var page = workingDoc.pages[idx];
  var activatePage = false;
  // Only re-route connectors glued to these shapes (never the whole page —
  // that scrambles unrelated authored routes).
  final movedForReroute = <int>{};

  void flushPage() {
    if (movedForReroute.isNotEmpty) {
      // Match the editor: refresh Sheet.n! / Width* caches before glue
      // re-route. A page-context change must flush these against the page
      // where the shape edits happened.
      page = page
          .recalculateFormulas(changedShapeIds: movedForReroute)
          .rerouteConnectors(movedShapeIds: movedForReroute);
      movedForReroute.clear();
    }
    if (!identical(page, workingDoc.pages[idx])) {
      workingDoc = workingDoc.replacePage(idx, page);
    }
  }

  void loadPage(int index) {
    idx = index;
    page = workingDoc.pages[idx];
  }

  for (final op in ops) {
    final kind = (op['op'] ?? op['type'] ?? '').toString();

    // Page operations are handled before the shape switch because they mutate
    // the document's page list and may change the context for later ops in the
    // same batch (for example add_page followed by add_shape).
    if (const <String>{
      'add_page',
      'duplicate_page',
      'rename_page',
      'delete_page',
      'move_page',
      'set_page',
    }.contains(kind)) {
      flushPage();
      switch (kind) {
        case 'add_page':
          final rawAt = _i(op['index']);
          final at = rawAt ?? idx + 1;
          if (at < 0 || at > workingDoc.pages.length) {
            log.add('add_page: index $at out of range');
            break;
          }
          final width = _d(op['w'] ?? op['width']) ?? page.widthInches;
          final height = _d(op['h'] ?? op['height']) ?? page.heightInches;
          if (width <= 0 || height <= 0) {
            log.add('add_page: width and height must be positive');
            break;
          }
          final colorRaw = op['background']?.toString();
          final color = colorRaw == null ? null : parseColorOrNull(colorRaw);
          if (colorRaw != null &&
              colorRaw.trim().toLowerCase() != 'none' &&
              color == null) {
            log.add('add_page: invalid background color "$colorRaw"');
            break;
          }
          final pageId = workingDoc.nextPageId();
          final name = _uniquePageName(
            workingDoc,
            (op['name'] ?? 'Page-${workingDoc.pages.length + 1}')
                .toString()
                .trim(),
          );
          final added = VsdxPage(
            id: pageId,
            name: name,
            widthInches: width,
            heightInches: height,
            shapes: const <VsdxShape>[],
            backgroundColor: color,
            isBackgroundPage: _b(op['isBackground']) ?? false,
          );
          workingDoc = workingDoc.insertPage(at, added);
          createdPages.add(pageId);
          loadPage(at);
          activatePage = true;
        case 'duplicate_page':
          final source = _i(op['index']) ?? idx;
          if (source < 0 || source >= workingDoc.pages.length) {
            log.add('duplicate_page: index $source out of range');
            break;
          }
          final original = workingDoc.pages[source];
          final pageId = workingDoc.nextPageId();
          final requestedName =
              (op['name'] ?? '${original.name} copy').toString().trim();
          final copy = original.copyWith(
            id: pageId,
            name: _uniquePageName(workingDoc, requestedName),
          );
          final at = source + 1;
          workingDoc = workingDoc.insertPage(at, copy);
          createdPages.add(pageId);
          loadPage(at);
          activatePage = true;
        case 'rename_page':
          final target = _i(op['index']) ?? idx;
          final name = op['name']?.toString().trim() ?? '';
          if (target < 0 || target >= workingDoc.pages.length) {
            log.add('rename_page: index $target out of range');
            break;
          }
          if (name.isEmpty) {
            log.add('rename_page: name must not be empty');
            break;
          }
          final unique =
              _uniquePageName(workingDoc, name, excludeIndex: target);
          if (workingDoc.pages[target].name != unique) {
            workingDoc = workingDoc.replacePage(
              target,
              workingDoc.pages[target].copyWith(name: unique),
            );
          }
          loadPage(target);
          activatePage = true;
        case 'delete_page':
          final target = _i(op['index']) ?? idx;
          if (target < 0 || target >= workingDoc.pages.length) {
            log.add('delete_page: index $target out of range');
            break;
          }
          if (workingDoc.pages.length <= 1) {
            log.add('delete_page: cannot delete the only page');
            break;
          }
          final activeId = workingDoc.pages[idx].id;
          final deletingActive = target == idx;
          workingDoc = workingDoc.removePageAt(target);
          final next = deletingActive
              ? target.clamp(0, workingDoc.pages.length - 1)
              : workingDoc.pages.indexWhere((p) => p.id == activeId);
          loadPage(next < 0 ? 0 : next);
          activatePage = true;
        case 'move_page':
          final from = _i(op['from']) ?? idx;
          final to = _i(op['to']);
          if (to == null) {
            log.add('move_page: needs to');
            break;
          }
          if (from < 0 ||
              from >= workingDoc.pages.length ||
              to < 0 ||
              to >= workingDoc.pages.length) {
            log.add('move_page: from=$from to=$to out of range');
            break;
          }
          final activeId = workingDoc.pages[idx].id;
          workingDoc = workingDoc.movePage(from, to);
          final next = workingDoc.pages.indexWhere((p) => p.id == activeId);
          loadPage(next < 0 ? 0 : next);
          activatePage = true;
        case 'set_page':
          final target = _i(op['index']) ?? idx;
          if (target < 0 || target >= workingDoc.pages.length) {
            log.add('set_page: index $target out of range');
            break;
          }
          var next = workingDoc.pages[target];
          final width = _d(op['w'] ?? op['width']);
          final height = _d(op['h'] ?? op['height']);
          if ((width != null && width <= 0) ||
              (height != null && height <= 0)) {
            log.add('set_page: width and height must be positive');
            break;
          }
          if (width != null || height != null) {
            next = next.copyWith(
              widthInches: width ?? next.widthInches,
              heightInches: height ?? next.heightInches,
            );
          }
          final landscape = _b(op['landscape']);
          if (landscape != null &&
              landscape != (next.widthInches > next.heightInches)) {
            next = next.copyWith(
              widthInches: next.heightInches,
              heightInches: next.widthInches,
            );
          }
          if (op.containsKey('background')) {
            final raw = op['background']?.toString() ?? 'none';
            if (raw.trim().toLowerCase() == 'none') {
              next = next.withoutBackgroundColor();
            } else {
              final color = parseColorOrNull(raw);
              if (color == null) {
                log.add('set_page: invalid background color "$raw"');
                break;
              }
              next = next.copyWith(backgroundColor: color);
            }
          }
          final isBackground = _b(op['isBackground']);
          if (isBackground != null) {
            next = next.copyWith(
              isBackgroundPage: isBackground,
              backgroundPageId:
                  isBackground ? null : VsdxPage.keepBackgroundPageId,
            );
          }
          if (op.containsKey('backgroundPageId')) {
            final raw = op['backgroundPageId'];
            final clear = raw == null ||
                raw == false ||
                raw.toString().trim().toLowerCase() == 'none';
            final backgroundId = clear ? null : _i(raw);
            final background = workingDoc.pageById(backgroundId);
            if (!clear &&
                (backgroundId == null ||
                    background == null ||
                    backgroundId == next.id)) {
              log.add('set_page: invalid backgroundPageId=$raw');
              break;
            }
            next = next.copyWith(
              isBackgroundPage: false,
              backgroundPageId: backgroundId,
            );
            if (background != null) {
              final backgroundIndex =
                  workingDoc.pages.indexWhere((p) => p.id == backgroundId);
              workingDoc = workingDoc.replacePage(
                backgroundIndex,
                background.copyWith(
                  isBackgroundPage: true,
                  backgroundPageId: null,
                ),
              );
            }
          }
          if (!identical(next, workingDoc.pages[target])) {
            workingDoc = workingDoc.replacePage(target, next);
          }
          loadPage(target);
          activatePage = true;
      }
      continue;
    }

    switch (kind) {
      case 'add_layer':
        final id = _nextLayerId(page);
        final rawName = (op['name'] ?? 'Layer $id').toString().trim();
        final colorRaw = op['color']?.toString();
        final color = colorRaw == null ? null : parseColorOrNull(colorRaw);
        if (rawName.isEmpty) {
          log.add('add_layer: name must not be empty');
          break;
        }
        if (colorRaw != null &&
            colorRaw.trim().toLowerCase() != 'none' &&
            color == null) {
          log.add('add_layer: invalid color "$colorRaw"');
          break;
        }
        final colorTrans = _d(op['colorTransparency'] ?? op['colorTrans']);
        final layer = VsdxLayer(
          id: id,
          name: rawName,
          visible: _b(op['visible']) ?? true,
          print: _b(op['print']) ?? true,
          active: _b(op['active']) ?? false,
          locked: _b(op['locked']) ?? false,
          snap: _b(op['snap']) ?? true,
          glue: _b(op['glue']) ?? true,
          color: color,
          colorTrans: colorTrans?.clamp(0.0, 1.0) ?? 0,
          nameUniv: op['nameUniv']?.toString(),
          status: _i(op['status']) ?? 0,
        );
        final editable = <int>{
          for (final shapeId in _resolveIds(op['ids']))
            if (page.findShapeById(shapeId) case final shape?
                when !_isProtected(page, shape))
              shapeId,
        };
        page = page.copyWith(
          layers: <VsdxLayer>[
            for (final existing in page.layers)
              if (layer.active && existing.active)
                existing.copyWith(active: false)
              else
                existing,
            layer,
          ],
        );
        for (final shapeId in editable) {
          page = page.updateShapeById(
            shapeId,
            (shape) => shape.copyWith(layerMemberIds: <int>[id]),
          );
        }
        createdLayers.add(id);
      case 'set_layer':
        final id = _resolveLayerId(op);
        final at = id == null ? -1 : page.layers.indexWhere((l) => l.id == id);
        if (id == null || at < 0) {
          log.add(
              'set_layer: missing or unknown layer id=${op['id'] ?? op['layerId']}');
          break;
        }
        final name =
            op.containsKey('name') ? op['name']?.toString().trim() : null;
        if (name != null && name.isEmpty) {
          log.add('set_layer: name must not be empty');
          break;
        }
        final colorRaw =
            op.containsKey('color') ? op['color']?.toString() : null;
        final clearColor =
            colorRaw != null && colorRaw.trim().toLowerCase() == 'none';
        final color =
            colorRaw == null || clearColor ? null : parseColorOrNull(colorRaw);
        if (colorRaw != null && !clearColor && color == null) {
          log.add('set_layer: invalid color "$colorRaw"');
          break;
        }
        final nameUnivRaw =
            op.containsKey('nameUniv') ? op['nameUniv']?.toString() : null;
        final clearNameUniv =
            nameUnivRaw != null && nameUnivRaw.trim().toLowerCase() == 'none';
        final colorTrans = _d(op['colorTransparency'] ?? op['colorTrans']);
        final current = page.layers[at];
        final next = current.copyWith(
          name: name,
          visible: _b(op['visible']),
          print: _b(op['print']),
          active: _b(op['active']),
          locked: _b(op['locked']),
          snap: _b(op['snap']),
          glue: _b(op['glue']),
          color: color,
          colorTrans: colorTrans?.clamp(0.0, 1.0),
          nameUniv: clearNameUniv ? null : nameUnivRaw,
          status: _i(op['status']),
          clearColor: clearColor,
          clearNameUniv: clearNameUniv,
        );
        final activate = _b(op['active']) == true;
        page = page.copyWith(
          layers: <VsdxLayer>[
            for (var i = 0; i < page.layers.length; i++)
              if (i == at)
                next
              else if (activate && page.layers[i].active)
                page.layers[i].copyWith(active: false)
              else
                page.layers[i],
          ],
        );
      case 'delete_layer':
        final id = _resolveLayerId(op);
        if (id == null || page.layers.every((layer) => layer.id != id)) {
          log.add(
              'delete_layer: missing or unknown layer id=${op['id'] ?? op['layerId']}');
          break;
        }
        page = page.copyWith(
          layers: <VsdxLayer>[
            for (final layer in page.layers)
              if (layer.id != id) layer,
          ],
          shapes: <VsdxShape>[
            for (final shape in page.shapes) _withoutLayerMembership(shape, id),
          ],
        );
      case 'assign_layer':
        final mode = (op['mode'] ?? 'replace').toString().trim().toLowerCase();
        if (!const <String>{'replace', 'add', 'remove', 'clear'}
            .contains(mode)) {
          log.add('assign_layer: unknown mode="$mode"');
          break;
        }
        final id = _resolveLayerId(op);
        if (mode != 'clear' &&
            (id == null || page.layers.every((layer) => layer.id != id))) {
          log.add(
              'assign_layer: missing or unknown layer id=${op['id'] ?? op['layerId']}');
          break;
        }
        final ids = _resolveIds(op['ids'] ?? op['shapeIds']);
        if (ids.isEmpty) {
          log.add('assign_layer: no shape ids');
          break;
        }
        for (final shapeId in ids.toSet()) {
          final shape = page.findShapeById(shapeId);
          if (shape == null) {
            log.add('assign_layer: shape $shapeId not found');
            continue;
          }
          if (_isProtected(page, shape)) {
            log.add('assign_layer: shape $shapeId is locked');
            continue;
          }
          page = page.updateShapeById(shapeId, (current) {
            final memberships = switch (mode) {
              'add' => <int>{...current.layerMemberIds, id!}.toList(),
              'remove' => <int>[
                  for (final layerId in current.layerMemberIds)
                    if (layerId != id) layerId,
                ],
              'clear' => const <int>[],
              _ => <int>[id!],
            };
            return current.copyWith(layerMemberIds: memberships);
          });
        }
      case 'add_shape':
        final id = page.nextFreeShapeId();
        final w = _d(op['w'] ?? op['width']) ?? 1.7;
        final h = _d(op['h'] ?? op['height']) ?? 0.9;
        if (w <= 0 || h <= 0) {
          log.add('add_shape: w and h must be positive');
          break;
        }
        var s = resolveStencilShape(
          stencil: (op['stencil'] ?? op['shape'] ?? 'rectangle').toString(),
          id: id,
          cx: _d(op['x']) ?? page.widthInches / 2,
          cy: _d(op['y']) ?? page.heightInches / 2,
          w: w,
          h: h,
          fillHex: op['fill']?.toString(),
          lineHex: (op['line'] ?? op['stroke'])?.toString(),
        );
        final text = (op['text'] ?? op['label'] ?? '').toString();
        if (text.isNotEmpty) {
          s = withLabel(s, text,
              bold: op['bold'] == true,
              colorHex: (op['textColor'] ?? op['fontColor'])?.toString());
        }
        final explicitLayerId =
            op.containsKey('layerId') ? _i(op['layerId']) : null;
        final activeLayerId = _activeLayerId(page);
        final layerId = explicitLayerId ?? activeLayerId;
        if (op.containsKey('layerId') &&
            (explicitLayerId == null ||
                page.layers.every((layer) => layer.id != explicitLayerId))) {
          log.add('add_shape: unknown layerId=${op['layerId']}');
          break;
        }
        if (layerId != null) {
          s = s.copyWith(layerMemberIds: <int>[layerId]);
        }
        page = page.addShape(s);
        created.add(id);
      case 'add_connector':
      case 'connect':
        final aId = _resolveId(op['from'] ?? op['source']);
        final bId = _resolveId(op['to'] ?? op['target']);
        final a = aId == null ? null : page.findShapeById(aId);
        final b = bId == null ? null : page.findShapeById(bId);
        if (a == null || b == null) {
          log.add(
              'add_connector: unresolved from=${op['from']} to=${op['to']}');
          break;
        }
        if (a.is1D || b.is1D) {
          log.add(
            'add_connector: from/to must be 2-D shapes '
            '(got 1-D from=${a.id} to=${b.id})',
          );
          break;
        }
        final id = page.nextFreeShapeId();
        final explicitLayerId =
            op.containsKey('layerId') ? _i(op['layerId']) : null;
        final activeLayerId = _activeLayerId(page);
        final layerId = explicitLayerId ?? activeLayerId;
        if (op.containsKey('layerId') &&
            (explicitLayerId == null ||
                page.layers.every((layer) => layer.id != explicitLayerId))) {
          log.add('add_connector: unknown layerId=${op['layerId']}');
          break;
        }
        var connector = buildConnector(
          id: id,
          page: page,
          a: a,
          b: b,
          label: op['label']?.toString(),
          lineHex: (op['line'] ?? op['stroke'])?.toString(),
          arrow: op['arrow'] == null
              ? true
              : (op['arrow'].toString().toLowerCase() != 'none' &&
                  op['arrow'] != false),
        );
        if (layerId != null) {
          connector = (
            connector:
                connector.connector.copyWith(layerMemberIds: <int>[layerId]),
            connects: connector.connects,
          );
        }
        page = page.addShape(connector.connector).copyWith(
            connects: <VsdxConnect>[...page.connects, ...connector.connects]);
        created.add(id);
        movedForReroute.add(id);
      case 'set_style':
        final ids = _resolveIds(op['ids'] ?? op['id']);
        if (ids.isEmpty) {
          log.add('set_style: missing or invalid id=${op['ids'] ?? op['id']}');
          break;
        }
        final fillHex = op['fill']?.toString();
        final lineHex = (op['line'] ?? op['stroke'])?.toString();
        final flipX = op.containsKey('flipX') ? _b(op['flipX']) : null;
        final flipY = op.containsKey('flipY') ? _b(op['flipY']) : null;
        // angle / rotateDeg = degrees; angleRad = radians.
        final angleRad = _d(op['angleRad']);
        final angleDeg = _d(op['angle'] ?? op['rotateDeg'] ?? op['rotate']);
        final literalAngle = angleRad ??
            (angleDeg == null ? null : angleDeg * (3.141592653589793 / 180.0));
        for (final id in ids) {
          final target = page.findShapeById(id);
          if (target == null) {
            log.add('set_style: shape $id not found');
            continue;
          }
          if (_isProtected(page, target)) {
            // Allow unlock via locked:false when only the shape lock is set
            // (layer locks still block). Other style keys apply after unlock.
            final unlock =
                op.containsKey('locked') && _b(op['locked']) == false;
            if (!(unlock &&
                target.locked &&
                !page.isShapeTreeOnLockedLayer(target.id))) {
              log.add('set_style: shape $id is locked');
              continue;
            }
          }
          page = page.updateShapeById(id, (s) {
            var next = s;
            if (op.containsKey('locked')) {
              final locked = _b(op['locked']);
              if (locked != null) {
                next = next.copyWith(locked: locked);
              }
            }
            if (flipX != null || flipY != null) {
              next = next
                  .copyWith(
                    flipX: flipX ?? next.flipX,
                    flipY: flipY ?? next.flipY,
                  )
                  .syncInkEndpoints();
            }
            if (literalAngle != null) {
              next = _withLiteralAngle(next, literalAngle);
            }
            if (op.containsKey('layerMember') || op.containsKey('layers')) {
              final layers = _parseLayerMembers(op.containsKey('layerMember')
                  ? op['layerMember']
                  : op['layers']);
              if (layers != null) {
                next = next.copyWith(layerMemberIds: layers);
              }
            }
            final themeIndex = _i(op['themeIndex']);
            if (themeIndex != null) {
              next = next.copyWith(themeIndex: themeIndex);
            }
            final qsFill = _i(op['quickStyleFillMatrix']);
            final qsLine = _i(op['quickStyleLineMatrix']);
            final qsEffects = _i(op['quickStyleEffectsMatrix']);
            final qsFont = _i(op['quickStyleFontMatrix']);
            if (qsFill != null ||
                qsLine != null ||
                qsEffects != null ||
                qsFont != null) {
              next = next.copyWith(
                quickStyleFillMatrix: qsFill ?? next.quickStyleFillMatrix,
                quickStyleLineMatrix: qsLine ?? next.quickStyleLineMatrix,
                quickStyleEffectsMatrix:
                    qsEffects ?? next.quickStyleEffectsMatrix,
                quickStyleFontMatrix: qsFont ?? next.quickStyleFontMatrix,
              );
            }
            final textAngleRad = _d(op['textAngleRad'] ?? op['txtAngleRad']);
            final textAngleDeg =
                _d(op['textAngle'] ?? op['txtAngle'] ?? op['textAngleDeg']);
            if (textAngleRad != null || textAngleDeg != null) {
              final rad =
                  textAngleRad ?? textAngleDeg! * (3.141592653589793 / 180.0);
              next = next.copyWith(
                richText: next.richText.copyWith(
                  textBlock: next.richText.textBlock.copyWith(angleRad: rad),
                ),
              );
            }
            // Match UI setFillColor: 1-D strokes never take a fill.
            if (fillHex != null && !s.is1D) {
              if (fillHex.trim().toLowerCase() == 'none') {
                // Match UI setNoFill: keep colours/transparency, clear
                // gradient + theme slots so they cannot revive later.
                next = next.copyWith(
                  fill: next.fill.copyWith(
                    pattern: 0,
                    gradient: null,
                    clearThemeForegroundIndex: true,
                    clearThemeBackgroundIndex: true,
                  ),
                  geometries: syncGeometryNoFill(next.geometries, hollow: true),
                );
              } else {
                final c = parseColorOrNull(fillHex);
                if (c != null) {
                  next = next.copyWith(
                    fill: next.fill.withSolidForeground(c),
                    geometries:
                        syncGeometryNoFill(next.geometries, hollow: false),
                  );
                } else {
                  log.add(
                    'set_style: invalid fill color "$fillHex" on shape $id',
                  );
                }
              }
            }
            final fillTheme = _i(op['fillTheme'] ??
                op['themeForegroundIndex'] ??
                op['fillThemeIndex']);
            if (fillTheme != null && !next.is1D) {
              next = next.copyWith(
                fill: next.fill.withThemeForeground(fillTheme),
                geometries: syncGeometryNoFill(next.geometries, hollow: false),
              );
            }
            final fillBkgndTheme = _i(op['fillBackgroundTheme'] ??
                op['themeBackgroundIndex'] ??
                op['fillBkgndTheme']);
            if (fillBkgndTheme != null && !next.is1D) {
              next = next.copyWith(
                fill: next.fill.withThemeBackground(fillBkgndTheme),
              );
            }
            if (lineHex != null) {
              if (lineHex.trim().toLowerCase() == 'none') {
                // Match UI setNoLine: clear dash, gradient, and line theme.
                next = next.copyWith(
                  line: next.line.copyWith(
                    pattern: 0,
                    gradient: null,
                    clearThemeColorIndex: true,
                  ),
                  geometries: syncGeometryNoLine(next.geometries, hollow: true),
                );
              } else {
                final c = parseColorOrNull(lineHex);
                if (c != null) {
                  next = next.copyWith(
                    line: next.line.withSolidColor(c),
                    geometries:
                        syncGeometryNoLine(next.geometries, hollow: false),
                  );
                } else {
                  log.add(
                    'set_style: invalid line color "$lineHex" on shape $id',
                  );
                }
              }
            }
            final lineTheme = _i(op['lineTheme'] ??
                op['lineThemeIndex'] ??
                op['themeLineIndex']);
            if (lineTheme != null) {
              next = next.copyWith(
                line: next.line.withThemeColor(lineTheme),
                geometries: syncGeometryNoLine(next.geometries, hollow: false),
              );
            }
            final fillPattern = _i(op['fillPattern'] ?? op['pattern']);
            if (fillPattern != null && !next.is1D) {
              next = next.copyWith(
                fill: next.fill.copyWith(
                  pattern: fillPattern,
                  gradient: fillPattern == 0 || fillPattern > 1
                      ? null
                      : VsdxFill.keepGradient,
                  clearThemeBackgroundIndex: fillPattern <= 1,
                  clearThemeForegroundIndex: fillPattern == 0,
                ),
                geometries: syncGeometryNoFill(
                  next.geometries,
                  hollow: fillPattern == 0,
                ),
              );
            }
            final fillBg =
                (op['fillBackground'] ?? op['fillBkgnd'] ?? op['background'])
                    ?.toString();
            if (fillBg != null && !next.is1D) {
              final c = parseColorOrNull(fillBg);
              if (c != null) {
                next = next.copyWith(
                  fill: next.fill.withSolidBackground(c),
                  geometries:
                      syncGeometryNoFill(next.geometries, hollow: false),
                );
              } else {
                log.add(
                  'set_style: invalid fillBackground "$fillBg" on shape $id',
                );
              }
            }
            if (op.containsKey('fillGradient') && !next.is1D) {
              final raw = op['fillGradient'];
              if (raw == false ||
                  (raw is String && raw.trim().toLowerCase() == 'none')) {
                next = next.copyWith(fill: next.fill.withGradient(null));
              } else if (raw == true) {
                next = next.copyWith(
                  fill: next.fill.withGradient(_defaultTwoStopGradient(
                    next.fill.foreground,
                    next.fill.background,
                  )),
                );
              } else {
                final g = _parseGradientOp(raw);
                if (g == null) {
                  log.add('set_style: invalid fillGradient on shape $id');
                } else {
                  next = next.copyWith(fill: next.fill.withGradient(g));
                }
              }
            }
            if (op.containsKey('lineGradient')) {
              final raw = op['lineGradient'];
              if (raw == false ||
                  (raw is String && raw.trim().toLowerCase() == 'none')) {
                next = next.copyWith(line: next.line.withGradient(null));
              } else if (raw == true) {
                next = next.copyWith(
                  line: next.line.withGradient(_defaultTwoStopGradient(
                    next.line.color,
                    next.fill.background,
                  )),
                );
              } else {
                final g = _parseGradientOp(raw);
                if (g == null) {
                  log.add('set_style: invalid lineGradient on shape $id');
                } else {
                  next = next.copyWith(line: next.line.withGradient(g));
                }
              }
            }
            final weight = _d(op['weight'] ?? op['lineWeight']);
            if (weight != null && weight > 0) {
              next = next.copyWith(
                line: next.line.copyWith(weightInches: weight),
              );
            }
            final beginArrow = _i(op['beginArrow']);
            if (beginArrow != null) {
              next = next.copyWith(
                line: next.line.copyWith(beginArrow: beginArrow),
              );
            }
            final endArrow = _i(op['endArrow']);
            if (endArrow != null) {
              next = next.copyWith(
                line: next.line.copyWith(endArrow: endArrow),
              );
            }
            final beginArrowSize =
                _d(op['beginArrowSize'] ?? op['beginArrowSizeInches']);
            if (beginArrowSize != null && beginArrowSize > 0) {
              next = next.copyWith(
                line: next.line.copyWith(beginArrowSizeInches: beginArrowSize),
              );
            }
            final endArrowSize =
                _d(op['endArrowSize'] ?? op['endArrowSizeInches']);
            if (endArrowSize != null && endArrowSize > 0) {
              next = next.copyWith(
                line: next.line.copyWith(endArrowSizeInches: endArrowSize),
              );
            }
            final linePattern = _i(op['linePattern'] ?? op['dash']);
            if (linePattern != null) {
              next = next
                  .copyWith(
                    line: next.line.copyWith(pattern: linePattern),
                    geometries: syncGeometryNoLine(
                      next.geometries,
                      hollow: linePattern == 0,
                    ),
                  )
                  .withDrawioDashPattern(null);
            }
            if (op.containsKey('dashPattern')) {
              final raw = op['dashPattern'];
              final clear = raw == null ||
                  raw == false ||
                  (raw is String &&
                      (raw.trim().isEmpty ||
                          raw.trim().toLowerCase() == 'none'));
              final custom = clear ? null : _parseDashPatternOp(raw);
              if (!clear && custom == null) {
                log.add('set_style: invalid dashPattern on shape $id');
              } else if (custom == null) {
                next = next.withDrawioDashPattern(null);
              } else {
                next = next.copyWith(
                  line: next.line.copyWith(
                    pattern: next.line.pattern <= 1 ? 2 : next.line.pattern,
                  ),
                  geometries: syncGeometryNoLine(
                    next.geometries,
                    hollow: false,
                  ),
                );
                next = next.withDrawioDashPattern(
                  custom,
                  fixed: _b(op['fixedDash']) ?? next.line.fixedDash,
                );
              }
            } else if (op.containsKey('fixedDash')) {
              final fixed = _b(op['fixedDash']);
              final custom = next.line.customDashPattern;
              if (fixed != null && custom != null && custom.isNotEmpty) {
                next = next.withDrawioDashPattern(custom, fixed: fixed);
              }
            }
            final lineTrans = _d(op['lineTransparency']);
            if (lineTrans != null) {
              next = next.copyWith(
                line: next.line.copyWith(
                  transparency: lineTrans.clamp(0.0, 1.0),
                ),
              );
            }
            final rounding = _d(op['rounding'] ?? op['roundingInches']);
            if (rounding != null) {
              next = next.copyWith(
                line: next.line.copyWith(roundingInches: rounding),
              );
            }
            final softEdges = _d(op['softEdges'] ?? op['softEdgesInches']);
            if (softEdges != null) {
              next = next.copyWith(
                line: next.line.copyWith(softEdgesInches: softEdges),
              );
            }
            final compoundType = _i(op['compoundType']);
            if (compoundType != null) {
              next = next.copyWith(
                line: next.line.copyWith(compoundType: compoundType),
              );
            }
            // Glow: glow:true|false|"none", or glowSize / glowColor / glowTransparency.
            // Disable keeps size so re-enable restores it; enable falls back to
            // Visio default 0.05" when size is still 0 (disabled sentinel).
            if (op.containsKey('glow')) {
              final g = op['glow'];
              if (g == false ||
                  (g is String && g.trim().toLowerCase() == 'none')) {
                next = next.copyWith(
                  glow: next.glow.copyWith(enabled: false),
                );
              } else if (g == true) {
                next = next.copyWith(glow: _enableGlow(next.glow));
              } else if (g is num) {
                final size = g.toDouble();
                next = next.copyWith(
                  glow: size <= 0
                      ? next.glow.copyWith(enabled: false)
                      : next.glow.copyWith(enabled: true, sizeInches: size),
                );
              }
            }
            final glowSize = _d(op['glowSize']);
            if (glowSize != null) {
              next = next.copyWith(
                glow: glowSize <= 0
                    ? next.glow.copyWith(enabled: false)
                    : next.glow.copyWith(
                        enabled: true,
                        sizeInches: glowSize,
                      ),
              );
            }
            final glowColor = parseColorOrNull(op['glowColor']?.toString());
            if (glowColor != null) {
              next = next.copyWith(
                glow: _enableGlow(next.glow).withSolidColor(glowColor),
              );
            }
            final glowTrans = _d(op['glowTransparency']);
            if (glowTrans != null) {
              next = next.copyWith(
                glow: next.glow.copyWith(
                  transparency: glowTrans.clamp(0.0, 1.0),
                ),
              );
            }
            // Shadow: shadow:true|false|"none", plus offset/blur/color helpers.
            // Disable via copyWith so pattern / colour / offsets survive toggle.
            if (op.containsKey('shadow')) {
              final sh = op['shadow'];
              if (sh == false ||
                  (sh is String && sh.trim().toLowerCase() == 'none')) {
                next = next.copyWith(
                  shadow: next.shadow.copyWith(enabled: false),
                );
              } else if (sh == true) {
                next = next.copyWith(
                  shadow: next.shadow.copyWith(enabled: true),
                );
              }
            }
            final shadowColor = parseColorOrNull(op['shadowColor']?.toString());
            if (shadowColor != null) {
              next = next.copyWith(
                shadow: next.shadow
                    .copyWith(enabled: true)
                    .withSolidColor(shadowColor),
              );
            }
            final shadowBlur = _d(op['shadowBlur']);
            if (shadowBlur != null) {
              next = next.copyWith(
                shadow: next.shadow.copyWith(
                  enabled: true,
                  blurInches: shadowBlur,
                ),
              );
            }
            final shadowOffX = _d(op['shadowOffsetX']);
            final shadowOffY = _d(op['shadowOffsetY']);
            if (shadowOffX != null || shadowOffY != null) {
              next = next.copyWith(
                shadow: next.shadow.copyWith(
                  enabled: true,
                  offsetXInches: shadowOffX ?? next.shadow.offsetXInches,
                  offsetYInches: shadowOffY ?? next.shadow.offsetYInches,
                ),
              );
            }
            final shadowTrans = _d(op['shadowTransparency']);
            if (shadowTrans != null) {
              next = next.copyWith(
                shadow: next.shadow.copyWith(
                  transparency: shadowTrans.clamp(0.0, 1.0),
                ),
              );
            }
            if (op.containsKey('shadowPattern')) {
              final raw = op['shadowPattern'];
              final pat = raw is num
                  ? raw.toInt()
                  : int.tryParse(raw?.toString() ?? '');
              if (pat != null) {
                next = next.copyWith(
                  shadow: pat <= 0
                      ? next.shadow.copyWith(enabled: false)
                      : next.shadow.copyWith(enabled: true, pattern: pat),
                );
              }
            }
            // Reflection: reflection:true|false|"none", plus size/dist/blur.
            if (op.containsKey('reflection')) {
              final r = op['reflection'];
              if (r == false ||
                  (r is String && r.trim().toLowerCase() == 'none')) {
                next = next.copyWith(
                  reflection: next.reflection.copyWith(enabled: false),
                );
              } else if (r == true) {
                next = next.copyWith(
                  reflection: _enableReflection(next.reflection),
                );
              } else if (r is num) {
                final size = r.toDouble();
                next = next.copyWith(
                  reflection: size <= 0
                      ? next.reflection.copyWith(enabled: false)
                      : next.reflection
                          .copyWith(enabled: true, sizeInches: size),
                );
              }
            }
            final reflSize = _d(op['reflectionSize']);
            if (reflSize != null) {
              next = next.copyWith(
                reflection: reflSize <= 0
                    ? next.reflection.copyWith(enabled: false)
                    : next.reflection.copyWith(
                        enabled: true,
                        sizeInches: reflSize,
                      ),
              );
            }
            final reflDist =
                _d(op['reflectionDist'] ?? op['reflectionDistance']);
            if (reflDist != null) {
              next = next.copyWith(
                reflection: _enableReflection(next.reflection).copyWith(
                  distanceInches: reflDist,
                ),
              );
            }
            final reflBlur = _d(op['reflectionBlur']);
            if (reflBlur != null) {
              next = next.copyWith(
                reflection: _enableReflection(next.reflection).copyWith(
                  blurInches: reflBlur,
                ),
              );
            }
            final reflTrans = _d(op['reflectionTransparency']);
            if (reflTrans != null) {
              next = next.copyWith(
                reflection: next.reflection.copyWith(
                  transparency: reflTrans.clamp(0.0, 1.0),
                ),
              );
            }
            final fillTrans = _d(op['fillTransparency'] ?? op['transparency']);
            final opacity = _d(op['opacity']);
            if (fillTrans != null && !next.is1D) {
              next = next.copyWith(
                fill: next.fill.copyWith(
                  foregroundTransparency: fillTrans.clamp(0.0, 1.0),
                ),
              );
            } else if (opacity != null && !next.is1D) {
              next = next.copyWith(
                fill: next.fill.copyWith(
                  foregroundTransparency: (1.0 - opacity).clamp(0.0, 1.0),
                ),
              );
            }
            final fillBkgndTrans = _d(op['fillBackgroundTransparency'] ??
                op['fillBkgndTrans'] ??
                op['backgroundTransparency']);
            if (fillBkgndTrans != null && !next.is1D) {
              next = next.copyWith(
                fill: next.fill.copyWith(
                  backgroundTransparency: fillBkgndTrans.clamp(0.0, 1.0),
                ),
              );
            }
            final textColor = (op['textColor'] ?? op['fontColor'])?.toString();
            final bold = op.containsKey('bold') ? _b(op['bold']) : null;
            final italic = op.containsKey('italic') ? _b(op['italic']) : null;
            final underline =
                op.containsKey('underline') ? _b(op['underline']) : null;
            final strikethrough = op.containsKey('strikethrough')
                ? _b(op['strikethrough'])
                : null;
            final doubleUnderline = op.containsKey('doubleUnderline')
                ? _b(op['doubleUnderline'])
                : null;
            final doubleStrikethrough = op.containsKey('doubleStrikethrough')
                ? _b(op['doubleStrikethrough'])
                : null;
            final overline =
                op.containsKey('overline') ? _b(op['overline']) : null;
            final smallCaps =
                op.containsKey('smallCaps') ? _b(op['smallCaps']) : null;
            final fontFamily =
                op['fontFamily']?.toString() ?? op['font']?.toString();
            final pt = _d(op['pt'] ?? op['fontSize']);
            final letterSpacingPt = _d(op['letterSpacingPt']);
            final letterSpacing = letterSpacingPt != null
                ? letterSpacingPt / 72.0
                : _d(op['letterSpacing']);
            final textTransparency =
                _d(op['textTransparency'] ?? op['charTransparency']);
            final fontScale = _d(op['fontScale']);
            final complexScriptSizePt = _d(op['complexScriptSizePt']);
            final complexScriptSizeInches = complexScriptSizePt != null
                ? complexScriptSizePt / 72.0
                : _d(op['complexScriptSizeInches'] ?? op['complexScriptSize']);
            final langId = op['langId']?.toString() ?? op['langID']?.toString();
            final asianFont = op['asianFont']?.toString();
            final complexScriptFont = op['complexScriptFont']?.toString();
            VsdxTextCase? textCase;
            if (op.containsKey('textCase')) {
              final raw = op['textCase'];
              if (raw is num) {
                textCase = switch (raw.toInt()) {
                  0 => VsdxTextCase.normal,
                  1 => VsdxTextCase.allCaps,
                  2 => VsdxTextCase.initialCaps,
                  _ => null,
                };
              } else if (raw != null) {
                final s = raw.toString().trim().toLowerCase();
                textCase = switch (s) {
                  'normal' || '0' => VsdxTextCase.normal,
                  'allcaps' ||
                  'all_caps' ||
                  'caps' ||
                  '1' =>
                    VsdxTextCase.allCaps,
                  'initialcaps' ||
                  'initial_caps' ||
                  'title' ||
                  '2' =>
                    VsdxTextCase.initialCaps,
                  _ => null,
                };
              }
            }
            VsdxTextPosition? textPosition;
            if (op.containsKey('textPosition') || op.containsKey('position')) {
              final raw = op['textPosition'] ?? op['position'];
              if (raw is num) {
                textPosition = switch (raw.toInt()) {
                  0 => VsdxTextPosition.normal,
                  1 => VsdxTextPosition.superscript,
                  2 => VsdxTextPosition.subscript,
                  _ => null,
                };
              } else if (raw != null) {
                final s = raw.toString().trim().toLowerCase();
                textPosition = switch (s) {
                  'normal' || '0' => VsdxTextPosition.normal,
                  'superscript' ||
                  'super' ||
                  '1' =>
                    VsdxTextPosition.superscript,
                  'subscript' || 'sub' || '2' => VsdxTextPosition.subscript,
                  _ => null,
                };
              }
            }
            if (textColor != null ||
                bold != null ||
                italic != null ||
                underline != null ||
                strikethrough != null ||
                doubleUnderline != null ||
                doubleStrikethrough != null ||
                overline != null ||
                smallCaps != null ||
                fontFamily != null ||
                pt != null ||
                letterSpacing != null ||
                textTransparency != null ||
                textCase != null ||
                textPosition != null ||
                fontScale != null ||
                langId != null ||
                asianFont != null ||
                complexScriptFont != null ||
                complexScriptSizeInches != null) {
              next = applyCharStyle(
                next,
                bold: bold,
                italic: italic,
                underline: underline,
                strikethrough: strikethrough,
                doubleUnderline: doubleUnderline,
                doubleStrikethrough: doubleStrikethrough,
                overline: overline,
                smallCaps: smallCaps,
                colorHex: textColor,
                pt: pt,
                fontFamily: fontFamily,
                letterSpacingInches: letterSpacing,
                textTransparency: textTransparency,
                textCase: textCase,
                textPosition: textPosition,
                fontScale: fontScale,
                langId: langId,
                asianFont: asianFont,
                complexScriptFont: complexScriptFont,
                complexScriptSizeInches: complexScriptSizeInches,
              );
            }
            if (op.containsKey('hideText')) {
              final hide = _b(op['hideText']);
              if (hide != null) {
                next = next.copyWith(
                  richText: next.richText.copyWith(
                    textBlock: next.richText.textBlock.copyWith(
                      hideText: hide,
                    ),
                  ),
                );
              }
            }
            final lineCapRaw = op['lineCap'] ?? op['cap'];
            if (lineCapRaw != null) {
              LineCap? cap;
              if (lineCapRaw is num) {
                cap = switch (lineCapRaw.toInt()) {
                  0 => LineCap.round,
                  1 => LineCap.square,
                  2 => LineCap.extended,
                  _ => null,
                };
              } else {
                final s = lineCapRaw.toString().trim().toLowerCase();
                cap = switch (s) {
                  'round' || '0' => LineCap.round,
                  'square' || '1' => LineCap.square,
                  'extended' || 'flat' || '2' => LineCap.extended,
                  _ => null,
                };
              }
              if (cap != null) {
                next = next.copyWith(line: next.line.copyWith(cap: cap));
              }
            }
            final lineJoin = VsdxLineJoin.parse(op['lineJoin']?.toString());
            if (lineJoin != null) {
              next = next.withDrawioLineJoin(lineJoin);
            }
            final miterLimit = _d(op['miterLimit']);
            if (miterLimit != null && miterLimit >= 1) {
              next = next.withDrawioMiterLimit(miterLimit);
            }
            final glass = _b(op['glass']);
            if (glass == false || (glass == true && next.supportsGlassEffect)) {
              next = next.withGlassEffect(glass!);
            }
            final flow = _b(op['flowAnimation']);
            if (flow == false || (flow == true && next.supportsFlowAnimation)) {
              next = next.withFlowAnimation(flow!);
            }
            final flowDuration = _i(op['flowDurationMs']);
            if (next.supportsFlowAnimation &&
                flowDuration != null &&
                flowDuration > 0) {
              next = next.withFlowAnimationDurationMs(flowDuration);
            }
            final flowTiming = VsdxFlowAnimationTiming.parse(
              op['flowTiming']?.toString(),
            );
            if (next.supportsFlowAnimation && flowTiming != null) {
              next = next.withFlowAnimationTiming(flowTiming);
            }
            final flowDirection = VsdxFlowAnimationDirection.parse(
              op['flowDirection']?.toString(),
            );
            if (next.supportsFlowAnimation && flowDirection != null) {
              next = next.withFlowAnimationDirection(flowDirection);
            }
            final valign = op['verticalAlign']?.toString().toLowerCase();
            if (valign != null && valign.isNotEmpty) {
              final align = switch (valign) {
                'top' => VsdxVertAlign.top,
                'bottom' => VsdxVertAlign.bottom,
                'middle' || 'center' || 'centre' => VsdxVertAlign.middle,
                _ => null,
              };
              if (align != null) {
                next = next.copyWith(
                  richText: next.richText.copyWith(
                    textBlock:
                        next.richText.textBlock.copyWith(verticalAlign: align),
                  ),
                );
              }
            }
            final halign =
                (op['align'] ?? op['horizontalAlign'] ?? op['horzAlign'])
                    ?.toString()
                    .toLowerCase();
            if (halign != null && halign.isNotEmpty) {
              final align = switch (halign) {
                'left' => VsdxHorzAlign.left,
                'center' || 'centre' || 'middle' => VsdxHorzAlign.center,
                'right' => VsdxHorzAlign.right,
                'justify' => VsdxHorzAlign.justify,
                _ => null,
              };
              if (align != null) {
                var runs = next.richText.runs;
                if (runs.isEmpty) {
                  // Do not call withLabel("") — that clears Character.
                  final plain = next.text;
                  if (plain != null && plain.isNotEmpty) {
                    next = withLabel(next, plain);
                    runs = next.richText.runs;
                  } else {
                    next = next.copyWith(
                      richText: next.richText.copyWith(
                        runs: [
                          VsdxTextRun(
                            text: '',
                            paraStyle: VsdxParaStyle.defaults
                                .copyWith(horizontalAlign: align),
                          ),
                        ],
                      ),
                    );
                    runs = next.richText.runs;
                  }
                }
                if (runs.isNotEmpty) {
                  next = next.copyWith(
                    richText: next.richText.copyWith(
                      runs: [
                        for (final r in next.richText.runs)
                          r.copyWith(
                            paraStyle:
                                r.paraStyle.copyWith(horizontalAlign: align),
                          ),
                      ],
                    ),
                  );
                }
              }
            }
            // Text block background / margins.
            final textBkgnd =
                (op['textBackground'] ?? op['textBkgnd'])?.toString();
            if (textBkgnd != null) {
              if (textBkgnd.trim().toLowerCase() == 'none') {
                next = next.copyWith(
                  richText: next.richText.copyWith(
                    textBlock: next.richText.textBlock.withoutBackgroundColor(),
                  ),
                );
              } else {
                final c = parseColorOrNull(textBkgnd);
                if (c != null) {
                  next = next.copyWith(
                    richText: next.richText.copyWith(
                      textBlock:
                          next.richText.textBlock.copyWith(backgroundColor: c),
                    ),
                  );
                }
              }
            }
            final textBkgndTrans =
                _d(op['textBackgroundTransparency'] ?? op['textBkgndTrans']);
            if (textBkgndTrans != null) {
              next = next.copyWith(
                richText: next.richText.copyWith(
                  textBlock: next.richText.textBlock.copyWith(
                    backgroundTransparency: textBkgndTrans.clamp(0.0, 1.0),
                  ),
                ),
              );
            }
            if (op.containsKey('textDirection')) {
              final raw = op['textDirection'];
              int? dir;
              if (raw is num) {
                dir = raw.toInt();
              } else if (raw != null) {
                final s = raw.toString().trim().toLowerCase();
                dir = switch (s) {
                  'horizontal' || '0' || 'ltr' => 0,
                  'vertical' || '1' => 1,
                  _ => int.tryParse(s),
                };
              }
              if (dir != null) {
                next = next.copyWith(
                  richText: next.richText.copyWith(
                    textBlock:
                        next.richText.textBlock.copyWith(textDirection: dir),
                  ),
                );
              }
            }
            final defaultTabStop =
                _d(op['defaultTabStop'] ?? op['defaultTabStopInches']);
            if (defaultTabStop != null) {
              next = next.copyWith(
                richText: next.richText.copyWith(
                  textBlock: next.richText.textBlock
                      .copyWith(defaultTabStopInches: defaultTabStop),
                ),
              );
            }
            final marginL = _d(op['marginLeft'] ?? op['leftMargin']);
            final marginR = _d(op['marginRight'] ?? op['rightMargin']);
            final marginT = _d(op['marginTop'] ?? op['topMargin']);
            final marginB = _d(op['marginBottom'] ?? op['bottomMargin']);
            if (marginL != null ||
                marginR != null ||
                marginT != null ||
                marginB != null) {
              next = next.copyWith(
                richText: next.richText.copyWith(
                  textBlock: next.richText.textBlock.copyWith(
                    marginLeftInches:
                        marginL ?? next.richText.textBlock.marginLeftInches,
                    marginRightInches:
                        marginR ?? next.richText.textBlock.marginRightInches,
                    marginTopInches:
                        marginT ?? next.richText.textBlock.marginTopInches,
                    marginBottomInches:
                        marginB ?? next.richText.textBlock.marginBottomInches,
                  ),
                ),
              );
            }
            // Paragraph indent / spacing / bullet.
            final indentFirst = _d(op['indentFirst'] ?? op['firstIndent']);
            final indentLeft = _d(op['indentLeft'] ?? op['leftIndent']);
            final indentRight = _d(op['indentRight'] ?? op['rightIndent']);
            final spaceBefore = _d(op['spaceBefore']);
            final spaceAfter = _d(op['spaceAfter']);
            final textPosAfterBullet =
                _d(op['textPosAfterBullet'] ?? op['textPosAfterBulletInches']);
            // Relative multiplier (lineSpacing) vs absolute inches / Visio SpLine.
            double? lineSpacingMult;
            double? lineSpacingAbs;
            var clearAbsolute = false;
            if (op.containsKey('lineSpacingAbsolute') ||
                op.containsKey('lineSpacingAbsoluteInches') ||
                op.containsKey('lineSpacingAbsolutePt')) {
              final pt = _d(op['lineSpacingAbsolutePt']);
              lineSpacingAbs = pt != null
                  ? pt / 72.0
                  : _d(op['lineSpacingAbsolute'] ??
                      op['lineSpacingAbsoluteInches']);
            }
            if (op.containsKey('spLine')) {
              final sp = _d(op['spLine']);
              if (sp != null) {
                if (sp < 0) {
                  lineSpacingMult = -sp;
                  clearAbsolute = true;
                } else if (sp > 0) {
                  lineSpacingAbs = sp;
                } else {
                  // SpLine=0 → solid.
                  lineSpacingAbs = 0;
                  clearAbsolute = false;
                }
              }
            }
            if (op.containsKey('lineSpacing')) {
              final mult = _d(op['lineSpacing']);
              if (mult != null) {
                lineSpacingMult = mult;
                clearAbsolute = true;
              }
            }
            final bullet = op.containsKey('bullet')
                ? (op['bullet'] is num
                    ? (op['bullet'] as num).toInt()
                    : int.tryParse(op['bullet'].toString()))
                : null;
            final bulletStr = op['bulletStr']?.toString();
            final bulletFont = op['bulletFont']?.toString();
            final bulletFontSizePt = _d(op['bulletFontSizePt']);
            final bulletFontSize = bulletFontSizePt != null
                ? bulletFontSizePt / 72.0
                : _d(op['bulletFontSize'] ?? op['bulletFontSizeInches']);
            final solidLine = op.containsKey('spLine') && _d(op['spLine']) == 0;
            if (indentFirst != null ||
                indentLeft != null ||
                indentRight != null ||
                spaceBefore != null ||
                spaceAfter != null ||
                lineSpacingMult != null ||
                lineSpacingAbs != null ||
                solidLine ||
                textPosAfterBullet != null ||
                bullet != null ||
                bulletStr != null ||
                bulletFont != null ||
                bulletFontSize != null) {
              VsdxParaStyle mapPara(VsdxParaStyle p) {
                var next = p.copyWith(
                  indentFirstInches: indentFirst ?? p.indentFirstInches,
                  indentLeftInches: indentLeft ?? p.indentLeftInches,
                  indentRightInches: indentRight ?? p.indentRightInches,
                  spaceBeforeInches: spaceBefore ?? p.spaceBeforeInches,
                  spaceAfterInches: spaceAfter ?? p.spaceAfterInches,
                  bullet: bullet ?? p.bullet,
                  bulletStr: bulletStr ?? p.bulletStr,
                  bulletFont: bulletFont ?? p.bulletFont,
                  bulletFontSizeInches:
                      bulletFontSize ?? p.bulletFontSizeInches,
                  textPosAfterBulletInches:
                      textPosAfterBullet ?? p.textPosAfterBulletInches,
                );
                // Relative lineSpacing / clearAbsolute wins over absolute so a
                // single op that sets both does not leave stale SpLine inches.
                if (solidLine) {
                  next = next.copyWith(
                    lineSpacingSolid: true,
                    lineSpacingAbsoluteInches: 0,
                    lineSpacing: 1.0,
                  );
                } else if (lineSpacingMult != null || clearAbsolute) {
                  next = next.copyWith(
                    lineSpacing: lineSpacingMult ?? p.lineSpacing,
                    lineSpacingAbsoluteInches: 0,
                    lineSpacingSolid: false,
                  );
                } else if (lineSpacingAbs != null) {
                  next = next.copyWith(
                    lineSpacingAbsoluteInches: lineSpacingAbs,
                    lineSpacingSolid: false,
                  );
                }
                return next;
              }

              var runs = next.richText.runs;
              if (runs.isEmpty) {
                final plain = next.text;
                if (plain != null && plain.isNotEmpty) {
                  next = withLabel(next, plain);
                  runs = next.richText.runs;
                } else {
                  next = next.copyWith(
                    richText: next.richText.copyWith(
                      runs: [
                        VsdxTextRun(
                          text: '',
                          paraStyle: mapPara(VsdxParaStyle.defaults),
                        ),
                      ],
                    ),
                  );
                  runs = next.richText.runs;
                }
              }
              if (runs.isNotEmpty) {
                next = next.copyWith(
                  richText: next.richText.copyWith(
                    runs: [
                      for (final r in next.richText.runs)
                        r.copyWith(paraStyle: mapPara(r.paraStyle)),
                    ],
                  ),
                );
              }
            }
            // Image tone (foreign data shapes only).
            final imgTrans = _d(op['imageTransparency']);
            final imgBlur = _d(op['imageBlur']);
            final imgBright = _d(op['imageBrightness']);
            final imgContrast = _d(op['imageContrast']);
            if (next.hasImage &&
                (imgTrans != null ||
                    imgBlur != null ||
                    imgBright != null ||
                    imgContrast != null)) {
              next = next.copyWith(
                imageTransparency:
                    imgTrans?.clamp(0.0, 1.0) ?? next.imageTransparency,
                imageBlur: imgBlur ?? next.imageBlur,
                imageBrightness:
                    imgBright?.clamp(0.0, 1.0) ?? next.imageBrightness,
                imageContrast:
                    imgContrast?.clamp(0.0, 1.0) ?? next.imageContrast,
              );
            }
            // Connector dynamics (1-D only).
            if (next.is1D) {
              final glueType = _i(op['glueType']);
              final conFixedCode = _i(op['conFixedCode']);
              final dynFeedback = _i(op['dynFeedback']);
              final shapeRouteStyle = _i(op['shapeRouteStyle']);
              final shapePlaceFlip = _i(op['shapePlaceFlip']);
              final conLineJumpCode = _i(op['conLineJumpCode']);
              final conLineRouteExt = _i(op['conLineRouteExt']);
              final conLineJumpStyle = _i(op['conLineJumpStyle']);
              final conLineJumpDirX = _i(op['conLineJumpDirX']);
              final conLineJumpDirY = _i(op['conLineJumpDirY']);
              final noLiveDynamics = op.containsKey('noLiveDynamics')
                  ? _b(op['noLiveDynamics'])
                  : null;
              if (glueType != null ||
                  conFixedCode != null ||
                  dynFeedback != null ||
                  shapeRouteStyle != null ||
                  shapePlaceFlip != null ||
                  conLineJumpCode != null ||
                  conLineRouteExt != null ||
                  conLineJumpStyle != null ||
                  conLineJumpDirX != null ||
                  conLineJumpDirY != null ||
                  noLiveDynamics != null) {
                final props = next.connectorProps ?? const VsdxConnectorProps();
                next = next.copyWith(
                  connectorProps: props.copyWith(
                    glueType: glueType ?? props.glueType,
                    conFixedCode: conFixedCode ?? props.conFixedCode,
                    dynFeedback: dynFeedback ?? props.dynFeedback,
                    shapeRouteStyle: shapeRouteStyle ?? props.shapeRouteStyle,
                    shapePlaceFlip: shapePlaceFlip ?? props.shapePlaceFlip,
                    conLineJumpCode: conLineJumpCode ?? props.conLineJumpCode,
                    conLineRouteExt: conLineRouteExt ?? props.conLineRouteExt,
                    conLineJumpStyle:
                        conLineJumpStyle ?? props.conLineJumpStyle,
                    conLineJumpDirX: conLineJumpDirX ?? props.conLineJumpDirX,
                    conLineJumpDirY: conLineJumpDirY ?? props.conLineJumpDirY,
                    noLiveDynamics: noLiveDynamics ?? props.noLiveDynamics,
                  ),
                );
              }
            }
            final noAlignBox =
                op.containsKey('noAlignBox') ? _b(op['noAlignBox']) : null;
            final shapeSplittable = op.containsKey('shapeSplittable')
                ? _b(op['shapeSplittable'])
                : null;
            if (noAlignBox != null || shapeSplittable != null) {
              next = next.copyWith(
                noAlignBox: noAlignBox ?? next.noAlignBox,
                shapeSplittable: shapeSplittable ?? next.shapeSplittable,
              );
            }
            final selectMode = _i(op['selectMode']);
            final displayMode = _i(op['displayMode']);
            if (selectMode != null || displayMode != null) {
              next = next.copyWith(
                selectMode: selectMode ?? next.selectMode,
                displayMode: displayMode ?? next.displayMode,
              );
            }
            final isTextEditTarget = op.containsKey('isTextEditTarget')
                ? _b(op['isTextEditTarget'])
                : null;
            final dontMoveChildren = op.containsKey('dontMoveChildren')
                ? _b(op['dontMoveChildren'])
                : null;
            if (isTextEditTarget != null || dontMoveChildren != null) {
              next = next.copyWith(
                isTextEditTarget: isTextEditTarget ?? next.isTextEditTarget,
                dontMoveChildren: dontMoveChildren ?? next.dontMoveChildren,
              );
            }
            final objType = _i(op['objType']);
            final resizeMode = _i(op['resizeMode']);
            if (objType != null || resizeMode != null) {
              next = next.copyWith(
                objType: objType ?? next.objType,
                resizeMode: resizeMode ?? next.resizeMode,
              );
            }
            if (op.containsKey('eventDblClick')) {
              final raw = op['eventDblClick']?.toString();
              if (raw != null && raw.isNotEmpty) {
                next = next.copyWith(eventDblClick: raw);
              }
            }
            return next;
          });
          // Rotation / reflection moves connection points on 2-D shapes.
          // Match the canvas commands by refreshing formula caches and glued
          // connector endpoints after the whole batch has been applied.
          if ((flipX != null || flipY != null || literalAngle != null) &&
              !target.is1D) {
            _addSubtreeIds(page, id, movedForReroute);
          }
        }
      case 'set_text':
        final id = _resolveId(op['id']);
        if (id == null) {
          log.add('set_text: missing or invalid id=${op['id']}');
          break;
        }
        final textTarget = page.findShapeById(id);
        if (textTarget == null) {
          log.add('set_text: shape $id not found');
          break;
        }
        if (_isProtected(page, textTarget)) {
          log.add('set_text: shape $id is locked');
          break;
        }
        page = page.updateShapeById(
            id,
            (s) => withLabel(
                  s,
                  (op['text'] ?? '').toString(),
                  bold: op.containsKey('bold') ? op['bold'] == true : null,
                  colorHex: (op['textColor'] ?? op['fontColor'])?.toString(),
                ));
      case 'set_data':
      case 'set_shape_data':
        final id = _resolveId(op['id']);
        if (id == null) {
          log.add('set_data: missing or invalid id=${op['id']}');
          break;
        }
        final target = page.findShapeById(id);
        if (target == null) {
          log.add('set_data: shape $id not found');
          break;
        }
        if (_isProtected(page, target)) {
          log.add('set_data: shape $id is locked');
          break;
        }
        final properties =
            _parseUserProperties(op['properties'] ?? op['data'], log);
        if (properties == null) break;
        page = page.updateShapeById(
          id,
          (shape) => shape.copyWith(userProperties: properties),
        );
      case 'set_links':
      case 'set_shape_links':
        final id = _resolveId(op['id']);
        if (id == null) {
          log.add('set_links: missing or invalid id=${op['id']}');
          break;
        }
        final target = page.findShapeById(id);
        if (target == null) {
          log.add('set_links: shape $id not found');
          break;
        }
        if (_isProtected(page, target)) {
          log.add('set_links: shape $id is locked');
          break;
        }
        final links = _parseHyperlinks(op['links'], log);
        if (links == null) break;
        page = page.updateShapeById(
          id,
          (shape) => shape.copyWith(hyperlinks: links),
        );
      case 'set_connection_points':
        final id = _resolveId(op['id']);
        if (id == null) {
          log.add(
            'set_connection_points: missing or invalid id=${op['id']}',
          );
          break;
        }
        final target = page.findShapeById(id);
        if (target == null || target.is1D) {
          log.add('set_connection_points: shape $id is not a 2-D shape');
          break;
        }
        if (_isProtected(page, target) || !page.isShapeTreeVisible(id)) {
          log.add('set_connection_points: shape $id is not editable');
          break;
        }
        final coordinateSpace =
            (op['coordinateSpace'] ?? 'local').toString().trim().toLowerCase();
        if (!const <String>{'local', 'page'}.contains(coordinateSpace)) {
          log.add(
            'set_connection_points: coordinateSpace must be local or page',
          );
          break;
        }
        final points = _parseConnectionPoints(
          op['points'] ?? op['connectionPoints'],
          page: page,
          target: target,
          pageCoordinates: coordinateSpace == 'page',
          log: log,
        );
        if (points == null) break;
        final nextConnects = <VsdxConnect>[
          for (final connect in page.connects)
            _remapConnectionPointConnect(connect, id, points.length),
        ];
        page = page
            .updateShapeById(
              id,
              (shape) => shape.copyWith(connectionPoints: points),
            )
            .copyWith(connects: nextConnects)
            .rerouteConnectors(movedShapeIds: <int>{id});
      case 'set_connector':
        final id = _resolveId(op['id']);
        if (id == null) {
          log.add('set_connector: missing or invalid id=${op['id']}');
          break;
        }
        final connector = page.findShapeById(id);
        if (connector == null || !connector.isGlueableConnector) {
          log.add('set_connector: shape $id is not a connector');
          break;
        }
        if (_isProtected(page, connector)) {
          log.add('set_connector: connector $id is locked');
          break;
        }
        final hasRoute = op.containsKey('route');
        final route =
            hasRoute ? op['route']?.toString().trim().toLowerCase() : null;
        if (hasRoute &&
            !const <String>{'straight', 'orthogonal', 'elbow', 'curved'}
                .contains(route)) {
          log.add('set_connector: unknown route="${op['route']}"');
          break;
        }
        final hasRounded = op.containsKey('rounded');
        final rounded = hasRounded ? _b(op['rounded']) : null;
        if (hasRounded && rounded == null) {
          log.add('set_connector: rounded must be boolean');
          break;
        }
        final hasWaypoints = op.containsKey('waypoints');
        final waypoints = hasWaypoints
            ? _parseWaypoints(op['waypoints'], log, opName: 'set_connector')
            : null;
        if (hasWaypoints && waypoints == null) break;
        if (!hasRoute && !hasRounded && !hasWaypoints) {
          log.add('set_connector: needs route, rounded, or waypoints');
          break;
        }
        if (route != null) {
          page = page.setConnectorStyle(
            <int>{id},
            straight: route == 'straight',
            curved: route == 'curved',
          );
        }
        if (rounded != null) {
          page = page.setConnectorRounded(<int>{id}, rounded);
        }
        if (waypoints != null) {
          final parentId = page.findParentId(id);
          page = page.setConnectorWaypoints(
            id,
            <Offset2D>[
              for (final point in waypoints)
                parentId == null
                    ? point
                    : page.pageToLocalDeep(parentId, point),
            ],
          );
        }
      case 'reconnect_connector':
        final id = _resolveId(op['id']);
        if (id == null) {
          log.add('reconnect_connector: missing or invalid id=${op['id']}');
          break;
        }
        final connector = page.findShapeById(id);
        if (connector == null || !connector.isGlueableConnector) {
          log.add('reconnect_connector: shape $id is not a connector');
          break;
        }
        if (_isProtected(page, connector)) {
          log.add('reconnect_connector: connector $id is locked');
          break;
        }
        final end = op['end']?.toString().trim().toLowerCase();
        final begin = switch (end) {
          'begin' || 'start' || 'source' => true,
          'end' || 'target' => false,
          _ => null,
        };
        if (begin == null) {
          log.add('reconnect_connector: end must be begin or end');
          break;
        }
        final targetRaw = op['target'] ?? op['targetId'];
        final detach = targetRaw == null ||
            targetRaw.toString().trim().toLowerCase() == 'none';
        final targetId = detach ? null : _resolveId(targetRaw);
        final target = targetId == null ? null : page.findShapeById(targetId);
        if (!detach &&
            (targetId == null ||
                target == null ||
                target.is1D ||
                !page.isShapeTreeVisible(targetId))) {
          log.add('reconnect_connector: invalid target=$targetRaw');
          break;
        }
        final connectionPoint = _i(
          op['connectionPoint'] ?? op['connectionPointIndex'],
        );
        if (connectionPoint != null &&
            (target == null ||
                connectionPoint < 0 ||
                connectionPoint >=
                    VsdxPage.effectiveConnectionPoints(target).length)) {
          log.add(
            'reconnect_connector: invalid connectionPoint=$connectionPoint',
          );
          break;
        }
        var x = _d(op['x']);
        var y = _d(op['y']);
        if (targetId != null && (x == null || y == null)) {
          final pin = page.shapePinPage(targetId);
          x ??= pin.x;
          y ??= pin.y;
        }
        if (x == null || y == null) {
          log.add('reconnect_connector: detached endpoint needs x and y');
          break;
        }
        final parentId = page.findParentId(id);
        final point = parentId == null
            ? Offset2D(x, y)
            : page.pageToLocalDeep(parentId, Offset2D(x, y));
        page = page.setConnectorEndpoint(
          id,
          begin: begin,
          targetShapeId: targetId,
          connectionPointIndex: connectionPoint,
          x: point.x,
          y: point.y,
        );
      case 'move_shape':
      case 'move':
        final id = _resolveId(op['id']);
        final x = _d(op['x']);
        final y = _d(op['y']);
        if (id == null || x == null || y == null) {
          log.add('move_shape: needs id,x,y');
          break;
        }
        final moving = page.findShapeById(id);
        if (moving == null) {
          log.add('move_shape: shape $id not found');
          break;
        }
        if (_isProtected(page, moving)) {
          log.add('move_shape: shape $id is locked');
          break;
        }
        // [x],[y] are page inches (same space as listShapes / shapePinPage).
        page = _moveShapeToPagePin(page, id, x, y);
        // Include descendants so glue on group children re-routes (editor
        // nudge uses the same subtree set).
        _addSubtreeIds(page, id, movedForReroute);
      case 'resize_shape':
      case 'resize':
        final id = _resolveId(op['id']);
        final w = _d(op['w'] ?? op['width']);
        final h = _d(op['h'] ?? op['height']);
        if (id == null || w == null || h == null) {
          log.add('resize_shape: needs id,w,h');
          break;
        }
        final resizing = page.findShapeById(id);
        if (resizing == null) {
          log.add('resize_shape: shape $id not found');
          break;
        }
        if (_isProtected(page, resizing)) {
          log.add('resize_shape: shape $id is locked');
          break;
        }
        if (!resizing.isGlueableConnector && (w <= 0 || h <= 0)) {
          log.add('resize_shape: w and h must be positive');
          break;
        }
        if (resizing.isGlueableConnector &&
            resizing.beginX != null &&
            resizing.beginY != null &&
            resizing.endX != null &&
            resizing.endY != null) {
          // Scale Begin→End by |w|/|h| so a positive length never flips a
          // right-to-left connector (Visio Width = EndX-BeginX may be negative).
          // Do not mark reroute — glue re-bake would undo an unglued resize.
          final ax = resizing.beginX!;
          final ay = resizing.beginY!;
          final bx = resizing.endX!;
          final by = resizing.endY!;
          final sx = resizing.width.abs() < 1e-12
              ? 1.0
              : w.abs() / resizing.width.abs();
          final sy = resizing.height.abs() < 1e-12
              ? 1.0
              : h.abs() / resizing.height.abs();
          final newEx = ax + (bx - ax) * sx;
          final newEy = ay + (by - ay) * sy;
          final newWps = <Offset2D>[
            for (final p in resizing.waypoints)
              Offset2D(ax + (p.x - ax) * sx, ay + (p.y - ay) * sy),
          ];
          final poly = <Offset2D>[
            Offset2D(ax, ay),
            ...newWps,
            Offset2D(newEx, newEy),
          ];
          page = page.updateShapeById(
            id,
            (s) => s
                .copyWith(
                  beginX: ax,
                  beginY: ay,
                  endX: newEx,
                  endY: newEy,
                  pinX: (ax + newEx) / 2,
                  pinY: (ay + newEy) / 2,
                  width: newEx - ax,
                  height: newEy - ay,
                  waypoints: newWps,
                )
                .reshapeAsPolyline(poly),
          );
          // Glued connectors must re-attach; unglued keep the scaled ends.
          if (page.connects.any((c) => c.fromSheetId == id)) {
            movedForReroute.add(id);
          }
        } else {
          page = page.updateShapeById(id, (s) {
            final sx = s.width == 0 ? 1.0 : w / s.width;
            final sy = s.height == 0 ? 1.0 : h / s.height;
            final resized = s.resizeTo(
              pinX: s.pinX,
              pinY: s.pinY,
              width: w,
              height: h,
            );
            if (SwimlaneOps.isPool(s)) {
              // Match editor resizeShape: scale pool-level content, then tile.
              var host = resized;
              if ((sx - 1).abs() > 1e-12 || (sy - 1).abs() > 1e-12) {
                host = resized.copyWith(
                  children: <VsdxShape>[
                    ...SwimlaneOps.lanesOf(s),
                    for (final c in SwimlaneOps.nonLaneChildren(s))
                      VsdxPage.scaleChildInFrame(
                        c,
                        sx,
                        sy,
                        s.effectiveLocPinX,
                        s.effectiveLocPinY,
                        resized.effectiveLocPinX,
                        resized.effectiveLocPinY,
                      ),
                  ],
                );
              }
              return SwimlaneOps.layoutLanes(host);
            }
            if (TableOps.isTable(s)) {
              return TableOps.layoutCells(resized);
            }
            if (s.children.isEmpty ||
                ((sx - 1).abs() < 1e-12 && (sy - 1).abs() < 1e-12)) {
              return resized;
            }
            // Match the editor: scale group children with the box.
            return resized.copyWith(
              children: <VsdxShape>[
                for (final c in s.children)
                  VsdxPage.scaleChildInFrame(
                    c,
                    sx,
                    sy,
                    s.effectiveLocPinX,
                    s.effectiveLocPinY,
                    resized.effectiveLocPinX,
                    resized.effectiveLocPinY,
                  ),
              ],
            );
          });
          _addSubtreeIds(page, id, movedForReroute);
        }
      case 'duplicate_shape':
      case 'duplicate':
        final requested = _resolveIds(op['ids'] ?? op['id']);
        final roots = _selectionRoots(page, requested).where((id) {
          final s = page.findShapeById(id);
          return s != null && !_isProtected(page, s);
        }).toList();
        if (roots.isEmpty) {
          log.add('duplicate_shape: no editable shapes in ids=$requested');
          break;
        }
        final sourceIds = <int>{};
        for (final id in roots) {
          _addSubtreeIds(page, id, sourceIds);
        }
        final sourceConnects = <VsdxConnect>[
          for (final c in page.connects)
            if (sourceIds.contains(c.fromSheetId) &&
                sourceIds.contains(c.toSheetId))
              c,
        ];
        final dx = _d(op['dx']) ?? 0.25;
        final dy = _d(op['dy']) ?? -0.25;
        final idMap = <int, int>{};
        final newRootIds = <int>[];
        var nextId = page.nextFreeShapeId();
        for (final id in roots) {
          final source = page.findShapeById(id)!;
          final clone = _withTreeUnlocked(
            VsdxPage.translateShape(
              source.withRemappedIds(
                () => nextId++,
                idMap: idMap,
              ),
              dx,
              dy,
              honourDontMoveChildren: false,
            ),
          );
          page = page.addShape(clone);
          created.add(clone.id);
          newRootIds.add(clone.id);
        }
        // A clone encountered before another selected root could not rewrite a
        // cross-root Sheet.n! reference until the complete id map existed.
        for (final id in newRootIds) {
          page = page.updateShapeById(
            id,
            (s) => VsdxShape.rewriteSheetRefsInTree(s, idMap),
          );
        }
        final remappedConnects = <VsdxConnect>[
          for (final c in sourceConnects)
            if (idMap.containsKey(c.fromSheetId) &&
                idMap.containsKey(c.toSheetId))
              VsdxConnect(
                fromSheetId: idMap[c.fromSheetId]!,
                fromCell: c.fromCell,
                fromPart: c.fromPart,
                toSheetId: idMap[c.toSheetId]!,
                toCell: c.toCell,
                toPart: c.toPart,
              ),
        ];
        if (remappedConnects.isNotEmpty) {
          page = page.copyWith(
            connects: <VsdxConnect>[...page.connects, ...remappedConnects],
          );
        }
        final clonedIds = idMap.values.toSet();
        page = page.syncGlueTriggers(connectorIds: clonedIds);
        movedForReroute.addAll(clonedIds);
      case 'reparent':
      case 'reparent_shapes':
        final hasParent = op.containsKey('parent') ||
            op.containsKey('parentId') ||
            op.containsKey('containerId');
        if (!hasParent) {
          log.add('reparent_shapes: parent is required (use none for page)');
          break;
        }
        final parentRaw = op['parent'] ?? op['parentId'] ?? op['containerId'];
        final parentName = parentRaw?.toString().trim().toLowerCase();
        final eject = parentRaw == null ||
            const <String>{'none', 'page', 'root', 'top'}.contains(parentName);
        final parentId = eject ? null : _resolveId(parentRaw);
        final parent = parentId == null ? null : page.findShapeById(parentId);
        if (!eject &&
            (parentId == null ||
                parent == null ||
                !VsdxPage.isDropContainer(parent) ||
                _isProtected(page, parent) ||
                !page.isShapeTreeVisible(parentId))) {
          log.add('reparent_shapes: invalid container=$parentRaw');
          break;
        }
        final requested = _selectionRoots(
          page,
          _resolveIds(op['ids'] ?? op['id']),
        );
        final movable = <int>[
          for (final id in requested)
            if (id != parentId)
              if (page.findShapeById(id) case final shape?
                  when !_isProtected(page, shape) &&
                      page.isShapeTreeVisible(id))
                id,
        ];
        if (movable.isEmpty) {
          log.add('reparent_shapes: no editable shapes');
          break;
        }
        var changed = false;
        var rejected = false;
        for (final id in movable) {
          if (parentId != null && _isAncestorOf(page, id, parentId)) {
            log.add(
              'reparent_shapes: shape $id cannot contain itself',
            );
            rejected = true;
            continue;
          }
          if (page.findParentId(id) == parentId) continue;
          final affected = <int>{};
          _addSubtreeIds(page, id, affected);
          if (parentId != null) {
            _addSubtreeIds(page, parentId, affected);
          }
          final next = page.reparentShape(id, parentId);
          if (!identical(next, page)) {
            page = next;
            movedForReroute.addAll(affected);
            changed = true;
          }
        }
        if (!changed && !rejected) {
          log.add('reparent_shapes: hierarchy unchanged');
        }
      case 'set_collapsed':
      case 'set_container_collapsed':
        final collapsed = _b(op['collapsed']);
        if (!op.containsKey('collapsed') || collapsed == null) {
          log.add('set_collapsed: collapsed must be true or false');
          break;
        }
        final ids = _resolveIds(op['ids'] ?? op['id']);
        if (ids.isEmpty) {
          log.add('set_collapsed: id or ids is required');
          break;
        }
        var changed = false;
        var rejected = false;
        for (final id in ids.toSet()) {
          final host = page.findShapeById(id);
          if (host == null) {
            log.add('set_collapsed: shape $id not found');
            rejected = true;
            continue;
          }
          if (collapsed && !host.collapsible) {
            log.add('set_collapsed: shape $id is not a foldable container');
            rejected = true;
            continue;
          }
          if (_isProtected(page, host) || !page.isShapeTreeVisible(id)) {
            log.add('set_collapsed: shape $id is locked or hidden');
            rejected = true;
            continue;
          }
          if (host.collapsed == collapsed) continue;
          final next = page.setCollapsed(id, collapsed);
          if (!identical(next, page)) {
            page = next;
            changed = true;
          }
        }
        if (!changed && !rejected) {
          log.add('set_collapsed: state unchanged');
        }
      case 'group':
      case 'group_shapes':
        final requested = _resolveIds(op['ids'] ?? op['id']);
        final ids = <int>{
          for (final id in requested)
            if (page.findParentId(id) == null)
              if (page.findShapeById(id) case final s?
                  when !_isProtected(page, s))
                id,
        };
        if (ids.length < 2) {
          log.add('group: needs at least two editable top-level shapes');
          break;
        }
        final groupId = page.nextFreeShapeId();
        final affected = <int>{groupId};
        for (final id in ids) {
          _addSubtreeIds(page, id, affected);
        }
        final next = page.group(
          ids,
          groupId: groupId,
          name: (op['name'] ?? '').toString(),
        );
        if (identical(next, page)) {
          log.add('group: could not group ids=$ids');
          break;
        }
        page = next;
        created.add(groupId);
        movedForReroute.addAll(affected);
      case 'ungroup':
      case 'ungroup_shapes':
        final requested = _resolveIds(op['ids'] ?? op['id']);
        final groups = <VsdxShape>[
          for (final id in requested)
            if (page.findShapeById(id) case final s?
                when s.children.isNotEmpty &&
                    s.shapeKind == VsdxShapeKind.group &&
                    !_isProtected(page, s))
              s,
        ];
        if (groups.isEmpty) {
          log.add('ungroup: no editable ordinary groups in ids=$requested');
          break;
        }
        int depth(int id) {
          var value = 0;
          var parent = page.findParentId(id);
          while (parent != null) {
            value++;
            parent = page.findParentId(parent);
          }
          return value;
        }

        groups.sort((a, b) => depth(b.id).compareTo(depth(a.id)));
        for (final group in groups) {
          _addSubtreeIds(page, group.id, movedForReroute);
          page = page.ungroup(group.id);
        }
      case 'z_order':
      case 'arrange':
        final id = _resolveId(op['id']);
        final target = id == null ? null : page.findShapeById(id);
        if (id == null || target == null) {
          log.add('z_order: missing or unknown id=${op['id']}');
          break;
        }
        if (_isProtected(page, target)) {
          log.add('z_order: shape $id is locked');
          break;
        }
        final action =
            (op['action'] ?? op['order'] ?? '').toString().toLowerCase();
        final next = switch (action) {
          'front' ||
          'bring_to_front' ||
          'bringtofront' =>
            page.bringToFront(id),
          'forward' ||
          'bring_forward' ||
          'bringforward' =>
            page.bringForward(id),
          'back' || 'send_to_back' || 'sendtoback' => page.sendToBack(id),
          'backward' ||
          'send_backward' ||
          'sendbackward' =>
            page.sendBackward(id),
          _ => page,
        };
        if (identical(next, page)) {
          if (!const <String>{
            'front',
            'bring_to_front',
            'bringtofront',
            'forward',
            'bring_forward',
            'bringforward',
            'back',
            'send_to_back',
            'sendtoback',
            'backward',
            'send_backward',
            'sendbackward',
          }.contains(action)) {
            log.add('z_order: unknown action="$action"');
          }
          break;
        }
        page = next;
      case 'align':
      case 'align_shapes':
        final requested = _selectionRoots(
          page,
          _resolveIds(op['ids'] ?? op['id']),
        );
        final ids = <int>[
          for (final id in requested)
            if (page.findShapeById(id)?.isGlueableConnector != true &&
                page.shapePageAabb(id) != null)
              id,
        ];
        if (ids.isEmpty) {
          log.add('align: no alignable shapes');
          break;
        }
        final mode = (op['mode'] ?? op['align'] ?? '').toString().toLowerCase();
        final deltas = _alignmentDeltas(page, ids, mode);
        if (deltas == null) {
          log.add('align: unknown mode="$mode"');
          break;
        }
        for (final e in deltas.entries) {
          final s = page.findShapeById(e.key);
          if (s == null || _isProtected(page, s)) continue;
          final d = e.value;
          if (d.x.abs() < 1e-12 && d.y.abs() < 1e-12) continue;
          final pin = page.shapePinPage(e.key);
          page = _moveShapeToPagePin(
            page,
            e.key,
            pin.x + d.x,
            pin.y + d.y,
          );
          _addSubtreeIds(page, e.key, movedForReroute);
        }
      case 'distribute':
      case 'distribute_shapes':
        final requested = _selectionRoots(
          page,
          _resolveIds(op['ids'] ?? op['id']),
        );
        final ids = <int>[
          for (final id in requested)
            if (page.findShapeById(id)?.isGlueableConnector != true &&
                page.shapePageAabb(id) != null)
              id,
        ];
        if (ids.length < 3) {
          log.add('distribute: needs at least three alignable shapes');
          break;
        }
        final axis =
            (op['axis'] ?? op['direction'] ?? '').toString().toLowerCase();
        final deltas = _distributionDeltas(page, ids, axis);
        if (deltas == null) {
          log.add('distribute: unknown axis="$axis"');
          break;
        }
        for (final e in deltas.entries) {
          final s = page.findShapeById(e.key);
          if (s == null || _isProtected(page, s)) continue;
          final d = e.value;
          if (d.x.abs() < 1e-12 && d.y.abs() < 1e-12) continue;
          final pin = page.shapePinPage(e.key);
          page = _moveShapeToPagePin(
            page,
            e.key,
            pin.x + d.x,
            pin.y + d.y,
          );
          _addSubtreeIds(page, e.key, movedForReroute);
        }
      case 'delete_shape':
      case 'delete':
        final id = _resolveId(op['id']);
        if (id == null) {
          log.add('delete_shape: missing or invalid id=${op['id']}');
          break;
        }
        final deleting = page.findShapeById(id);
        if (deleting == null) {
          log.add('delete_shape: shape $id not found');
          break;
        }
        if (_isProtected(page, deleting)) {
          log.add('delete_shape: shape $id is locked');
          break;
        }
        // removeShapeById prunes Connect rows; no selective re-route needed.
        page = page.removeShapeById(id);
      default:
        log.add('unknown op: "$kind"');
    }
  }

  flushPage();
  return ApplyResult(
    workingDoc,
    created,
    log,
    pageIndex: idx,
    createdPageIds: createdPages,
    createdLayerIds: createdLayers,
    activatePage: activatePage,
  );
}

/// True when the shape or its layer tree is locked (matches EditorController).
bool _isProtected(VsdxPage page, VsdxShape s) =>
    s.locked || page.isShapeTreeOnLockedLayer(s.id);

/// Set a literal angle like the canvas rotate commands: inherited/formula
/// Angle must not overwrite the visible edit after save + reopen.
VsdxShape _withLiteralAngle(VsdxShape s, double angleRad) {
  if (!s.formulas.containsKey('Angle')) {
    return s.copyWith(angleRad: angleRad).syncInkEndpoints();
  }
  final formulas = Map<String, String>.from(s.formulas)..remove('Angle');
  return s.copyWith(angleRad: angleRad, formulas: formulas).syncInkEndpoints();
}

/// Add [id] and every descendant shape id into [out] (group move / resize).
void _addSubtreeIds(VsdxPage page, int id, Set<int> out) {
  void walk(VsdxShape s) {
    out.add(s.id);
    for (final c in s.children) {
      walk(c);
    }
  }

  final s = page.findShapeById(id);
  if (s != null) {
    walk(s);
  } else {
    out.add(id);
  }
}

/// Move [id] so its page pin lands at ([pageX],[pageY]). Nested shapes convert
/// through the parent frame (matches editor [_nudgeShapeOnPage]).
VsdxPage _moveShapeToPagePin(
  VsdxPage page,
  int id,
  double pageX,
  double pageY,
) {
  final s = page.findShapeById(id);
  if (s == null) return page;
  final parentId = page.findParentId(id);
  if (parentId == null) {
    return page.updateShapeById(
      id,
      (sh) => VsdxPage.translateShape(sh, pageX - sh.pinX, pageY - sh.pinY),
    );
  }
  final local = page.pageToLocalDeep(parentId, Offset2D(pageX, pageY));
  return page.updateShapeById(
    id,
    (sh) => VsdxPage.translateShape(
      sh,
      local.x - sh.pinX,
      local.y - sh.pinY,
    ),
  );
}

/// Remove duplicate ids and descendants whose ancestor is also selected.
///
/// This mirrors draw.io's selection-root semantics: moving/duplicating both a
/// group and one of its children must transform the child exactly once.
List<int> _selectionRoots(VsdxPage page, Iterable<int> ids) {
  final selected = <int>{
    for (final id in ids)
      if (page.findShapeById(id) != null) id,
  };
  return <int>[
    for (final id in selected)
      if (!_hasSelectedAncestor(page, id, selected)) id,
  ];
}

bool _hasSelectedAncestor(VsdxPage page, int id, Set<int> selected) {
  var parent = page.findParentId(id);
  while (parent != null) {
    if (selected.contains(parent)) return true;
    parent = page.findParentId(parent);
  }
  return false;
}

bool _isAncestorOf(VsdxPage page, int ancestorId, int id) {
  var parent = page.findParentId(id);
  while (parent != null) {
    if (parent == ancestorId) return true;
    parent = page.findParentId(parent);
  }
  return false;
}

/// Copies are always editable, matching the app's draw.io-style Duplicate.
VsdxShape _withTreeUnlocked(VsdxShape shape) => shape.copyWith(
      locked: false,
      children: <VsdxShape>[
        for (final child in shape.children) _withTreeUnlocked(child),
      ],
    );

Map<int, Offset2D>? _alignmentDeltas(
  VsdxPage page,
  List<int> ids,
  String mode,
) {
  final bounds =
      <int, ({double left, double bottom, double right, double top})>{
    for (final id in ids)
      if (page.shapePageAabb(id) case final b?) id: b,
  };
  if (bounds.isEmpty) return const <int, Offset2D>{};
  final single = bounds.length == 1;
  final left = bounds.values.map((b) => b.left).reduce(math.min);
  final right = bounds.values.map((b) => b.right).reduce(math.max);
  final bottom = bounds.values.map((b) => b.bottom).reduce(math.min);
  final top = bounds.values.map((b) => b.top).reduce(math.max);
  final normalized = mode.replaceAll('-', '_').replaceAll(' ', '_');
  return switch (normalized) {
    'left' => <int, Offset2D>{
        for (final e in bounds.entries)
          e.key: Offset2D((single ? 0.0 : left) - e.value.left, 0),
      },
    'right' => <int, Offset2D>{
        for (final e in bounds.entries)
          e.key: Offset2D(
            (single ? page.widthInches : right) - e.value.right,
            0,
          ),
      },
    'center' ||
    'center_h' ||
    'horizontal' ||
    'horizontal_center' =>
      <int, Offset2D>{
        for (final e in bounds.entries)
          e.key: Offset2D(
            (single ? page.widthInches / 2 : (left + right) / 2) -
                (e.value.left + e.value.right) / 2,
            0,
          ),
      },
    'top' => <int, Offset2D>{
        for (final e in bounds.entries)
          e.key: Offset2D(
            0,
            (single ? page.heightInches : top) - e.value.top,
          ),
      },
    'bottom' => <int, Offset2D>{
        for (final e in bounds.entries)
          e.key: Offset2D(0, (single ? 0.0 : bottom) - e.value.bottom),
      },
    'middle' ||
    'center_v' ||
    'vertical' ||
    'vertical_center' =>
      <int, Offset2D>{
        for (final e in bounds.entries)
          e.key: Offset2D(
            0,
            (single ? page.heightInches / 2 : (bottom + top) / 2) -
                (e.value.bottom + e.value.top) / 2,
          ),
      },
    _ => null,
  };
}

Map<int, Offset2D>? _distributionDeltas(
  VsdxPage page,
  List<int> ids,
  String axis,
) {
  final bounds =
      <int, ({double left, double bottom, double right, double top})>{
    for (final id in ids)
      if (page.shapePageAabb(id) case final b?) id: b,
  };
  if (bounds.length < 3) return const <int, Offset2D>{};
  final normalized = axis.replaceAll('-', '_').replaceAll(' ', '_');
  if (const <String>{'horizontal', 'h', 'x'}.contains(normalized)) {
    final sorted = bounds.keys.toList()
      ..sort((a, b) => bounds[a]!.left.compareTo(bounds[b]!.left));
    final first = bounds[sorted.first]!;
    final last = bounds[sorted.last]!;
    final totalWidth = sorted.fold<double>(
      0,
      (sum, id) => sum + bounds[id]!.right - bounds[id]!.left,
    );
    final gap = (last.right - first.left - totalWidth) / (sorted.length - 1);
    var cursor = first.left;
    final out = <int, Offset2D>{};
    for (final id in sorted) {
      final b = bounds[id]!;
      out[id] = Offset2D(cursor - b.left, 0);
      cursor += b.right - b.left + gap;
    }
    return out;
  }
  if (const <String>{'vertical', 'v', 'y'}.contains(normalized)) {
    final sorted = bounds.keys.toList()
      ..sort((a, b) => bounds[a]!.bottom.compareTo(bounds[b]!.bottom));
    final first = bounds[sorted.first]!;
    final last = bounds[sorted.last]!;
    final totalHeight = sorted.fold<double>(
      0,
      (sum, id) => sum + bounds[id]!.top - bounds[id]!.bottom,
    );
    final gap = (last.top - first.bottom - totalHeight) / (sorted.length - 1);
    var cursor = first.bottom;
    final out = <int, Offset2D>{};
    for (final id in sorted) {
      final b = bounds[id]!;
      out[id] = Offset2D(0, cursor - b.bottom);
      cursor += b.top - b.bottom + gap;
    }
    return out;
  }
  return null;
}

/// Parse [opsJson] (an array, or an object with `ops:[...]`), apply to
/// [original] `.vsdx` bytes, and write the result back (round-trip faithful).
Uint8List applyOpsBytes(Uint8List original, String opsJson,
        {int pageIndex = 0}) =>
    applyOpsBytesResult(original, opsJson, pageIndex: pageIndex).bytes;

/// Detailed file-mode variant used by protocol frontends. Unlike the
/// byte-only wrapper, this preserves skipped-op logs and the clamped page.
ApplyBytesResult applyOpsBytesResult(Uint8List original, String opsJson,
    {int pageIndex = 0}) {
  final decoded = jsonDecode(opsJson);
  final rawOps = decoded is List
      ? decoded
      : (decoded is Map ? (decoded['ops'] as List? ?? const []) : const []);
  final ops = <Map<String, dynamic>>[
    for (final o in rawOps) (o as Map).cast<String, dynamic>(),
  ];
  final doc = const DocumentParser().parse(original);
  final effectivePage =
      doc.pages.isEmpty ? 0 : pageIndex.clamp(0, doc.pages.length - 1);
  final result = applyOps(doc, ops, pageIndex: effectivePage);
  final changed = !identical(result.document, doc);
  return ApplyBytesResult(
    bytes: changed
        ? const VsdxWriter().write(
            originalBytes: original,
            edited: result.document,
          )
        : original,
    pageIndex: result.pageIndex,
    changed: changed,
    createdIds: result.createdIds,
    createdPageIds: result.createdPageIds,
    createdLayerIds: result.createdLayerIds,
    log: result.log,
  );
}

int _nextLayerId(VsdxPage page) {
  var maxId = -1;
  for (final layer in page.layers) {
    if (layer.id > maxId) maxId = layer.id;
  }
  return maxId + 1;
}

int? _activeLayerId(VsdxPage page) {
  for (var i = page.layers.length - 1; i >= 0; i--) {
    if (page.layers[i].active) return page.layers[i].id;
  }
  return null;
}

int? _resolveLayerId(Map<String, dynamic> op) => _i(op['layerId'] ?? op['id']);

VsdxShape _withoutLayerMembership(VsdxShape shape, int layerId) {
  var next = shape.layerMemberIds.contains(layerId)
      ? shape.copyWith(
          layerMemberIds: <int>[
            for (final id in shape.layerMemberIds)
              if (id != layerId) id,
          ],
        )
      : shape;
  if (next.children.isNotEmpty) {
    next = next.copyWith(
      children: <VsdxShape>[
        for (final child in next.children)
          _withoutLayerMembership(child, layerId),
      ],
    );
  }
  return next;
}

List<VsdxUserProperty>? _parseUserProperties(
  Object? raw,
  List<String> log,
) {
  if (raw is! List) {
    log.add('set_data: properties/data must be an array');
    return null;
  }
  final properties = <VsdxUserProperty>[];
  final seen = <String>{};
  for (var i = 0; i < raw.length; i++) {
    final item = raw[i];
    if (item is! Map) {
      log.add('set_data: property $i must be an object');
      continue;
    }
    final property = item.cast<Object?, Object?>();
    final name = property['name']?.toString().trim() ?? '';
    if (name.isEmpty) {
      log.add('set_data: property $i needs a non-empty name');
      continue;
    }
    if (!seen.add(name)) {
      log.add('set_data: duplicate property name "$name" skipped');
      continue;
    }
    properties.add(
      VsdxUserProperty(
        name: name,
        label: property['label']?.toString(),
        value: property['value']?.toString(),
        valueFormula: property['valueFormula']?.toString(),
        prompt: property['prompt']?.toString(),
        format: property['format']?.toString(),
        formatFormula: property['formatFormula']?.toString(),
        type: _i(property['type']) ?? 0,
        sortKey: property['sortKey']?.toString(),
        invisible: _b(property['invisible']) ?? false,
        verify: _b(property['verify']) ?? false,
        ask: _b(property['ask']) ?? false,
        dataLinked: _b(property['dataLinked']) ?? false,
        langId: property['langId']?.toString(),
        calendar: _i(property['calendar']),
      ),
    );
  }
  if (raw.isNotEmpty && properties.isEmpty) return null;
  return properties;
}

List<VsdxHyperlink>? _parseHyperlinks(Object? raw, List<String> log) {
  if (raw is! List) {
    log.add('set_links: links must be an array');
    return null;
  }
  final links = <VsdxHyperlink>[];
  final usedIds = <int>{};
  var nextId = 0;
  var hasDefault = false;
  for (var i = 0; i < raw.length; i++) {
    final item = raw[i];
    if (item is! Map) {
      log.add('set_links: link $i must be an object');
      continue;
    }
    final link = item.cast<Object?, Object?>();
    final address = link['address']?.toString().trim();
    final addressFormula = link['addressFormula']?.toString().trim();
    final subAddress = link['subAddress']?.toString().trim();
    if ((address == null || address.isEmpty) &&
        (addressFormula == null || addressFormula.isEmpty) &&
        (subAddress == null || subAddress.isEmpty)) {
      log.add(
          'set_links: link $i needs address, addressFormula, or subAddress');
      continue;
    }
    final requestedId = _i(link['id']);
    var id = requestedId;
    if (id == null || id < 0 || usedIds.contains(id)) {
      while (usedIds.contains(nextId)) {
        nextId++;
      }
      id = nextId++;
      if (requestedId != null) {
        log.add(
            'set_links: duplicate/invalid id $requestedId reassigned to $id');
      }
    }
    usedIds.add(id);
    final requestedDefault = _b(link['default'] ?? link['isDefault']) ?? false;
    final isDefault = requestedDefault && !hasDefault;
    hasDefault = hasDefault || isDefault;
    links.add(
      VsdxHyperlink(
        id: id,
        description: link['description']?.toString(),
        address: address?.isEmpty == true ? null : address,
        addressFormula: addressFormula?.isEmpty == true ? null : addressFormula,
        subAddress: subAddress?.isEmpty == true ? null : subAddress,
        extraInfo: link['extraInfo']?.toString(),
        frame: link['frame']?.toString(),
        newWindow: _b(link['newWindow']) ?? false,
        isDefault: isDefault,
        invisible: _b(link['invisible']) ?? false,
        sortKey: link['sortKey']?.toString(),
      ),
    );
  }
  if (raw.isNotEmpty && links.isEmpty) return null;
  if (links.isNotEmpty && !hasDefault) {
    links[0] = links[0].copyWith(isDefault: true);
  }
  return links;
}

List<VsdxConnectionPoint>? _parseConnectionPoints(
  Object? raw, {
  required VsdxPage page,
  required VsdxShape target,
  required bool pageCoordinates,
  required List<String> log,
}) {
  if (raw is! List) {
    log.add('set_connection_points: points must be an array');
    return null;
  }
  final points = <VsdxConnectionPoint>[];
  for (var i = 0; i < raw.length; i++) {
    final item = raw[i];
    if (item is! Map) {
      log.add('set_connection_points: point $i must be an object');
      return null;
    }
    final point = item.cast<Object?, Object?>();
    final x = _d(point['x']);
    final y = _d(point['y']);
    if (x == null || y == null) {
      log.add('set_connection_points: point $i needs finite x and y');
      return null;
    }
    final local = pageCoordinates
        ? page.pageToLocalDeep(target.id, Offset2D(x, y))
        : Offset2D(x, y);
    final inferred = VsdxPage.connectionPointAt(
      local.x,
      local.y,
      target.width,
      target.height,
    );
    final dirX = point.containsKey('dirX') ? _d(point['dirX']) : inferred.dirX;
    final dirY = point.containsKey('dirY') ? _d(point['dirY']) : inferred.dirY;
    final type = point.containsKey('type') ? _i(point['type']) : 0;
    final autoGen = point.containsKey('autoGen') ? _b(point['autoGen']) : false;
    if (dirX == null || dirY == null || type == null || autoGen == null) {
      log.add('set_connection_points: point $i has invalid metadata');
      return null;
    }
    points.add(
      VsdxConnectionPoint(
        local.x,
        local.y,
        dirX: dirX,
        dirY: dirY,
        type: type,
        autoGen: autoGen,
        prompt: point['prompt']?.toString(),
        xFormula: inferred.xFormula,
        yFormula: inferred.yFormula,
      ),
    );
  }
  return points;
}

VsdxConnect _remapConnectionPointConnect(
  VsdxConnect connect,
  int targetId,
  int pointCount,
) {
  final index = VsdxPage.fixedConnectionIndex(connect);
  if (connect.toSheetId != targetId || index == null || index < pointCount) {
    return connect;
  }
  return VsdxConnect(
    fromSheetId: connect.fromSheetId,
    fromCell: connect.fromCell,
    fromPart: connect.fromPart,
    toSheetId: connect.toSheetId,
    toCell: 'PinX',
    toPart: 3,
  );
}

List<Offset2D>? _parseWaypoints(
  Object? raw,
  List<String> log, {
  required String opName,
}) {
  if (raw is! List) {
    log.add('$opName: waypoints must be an array');
    return null;
  }
  final points = <Offset2D>[];
  for (var i = 0; i < raw.length; i++) {
    final item = raw[i];
    double? x;
    double? y;
    if (item is Map) {
      x = _d(item['x']);
      y = _d(item['y']);
    } else if (item is List && item.length >= 2) {
      x = _d(item[0]);
      y = _d(item[1]);
    }
    if (x == null || y == null) {
      log.add('$opName: waypoint $i needs finite x and y');
      return null;
    }
    points.add(Offset2D(x, y));
  }
  return points;
}

String _uniquePageName(
  VsdxDocument doc,
  String requested, {
  int? excludeIndex,
}) {
  final base = requested.isEmpty ? 'Page-${doc.pages.length + 1}' : requested;
  final names = <String>{
    for (var i = 0; i < doc.pages.length; i++)
      if (i != excludeIndex) doc.pages[i].name,
  };
  if (!names.contains(base)) return base;
  var suffix = 2;
  while (names.contains('$base $suffix')) {
    suffix++;
  }
  return '$base $suffix';
}

double? _d(Object? v) {
  if (v == null) return null;
  final value = v is num ? v.toDouble() : double.tryParse('$v');
  return value != null && value.isFinite ? value : null;
}

List<double>? _parseDashPatternOp(Object? raw) {
  if (raw is String) return parseDrawioDashPattern(raw);
  if (raw is! List || raw.isEmpty) return null;
  final values = <double>[];
  for (final item in raw) {
    final value = _d(item);
    if (value == null || value <= 0) return null;
    values.add(value);
  }
  return values;
}

int? _i(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.isFinite ? v.toInt() : null;
  return int.tryParse('$v');
}

bool? _b(Object? v) {
  if (v == null) return null;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = '$v'.trim().toLowerCase();
  if (s == 'true' || s == '1' || s == 'yes') return true;
  if (s == 'false' || s == '0' || s == 'no') return false;
  return null;
}

/// Enable glow, restoring Visio default size when still at the disabled 0.
VsdxGlow _enableGlow(VsdxGlow g) => g.copyWith(
      enabled: true,
      sizeInches: g.sizeInches > 1e-12 ? g.sizeInches : 0.05,
    );

/// Enable reflection, restoring Visio default size when still at 0.
VsdxReflection _enableReflection(VsdxReflection r) => r.copyWith(
      enabled: true,
      sizeInches: r.sizeInches > 1e-12 ? r.sizeInches : 0.3,
    );

/// Parse set_style layerMember / layers as int list (null = absent key value).
List<int>? _parseLayerMembers(Object? raw) {
  if (raw == null) return const <int>[];
  if (raw is List) {
    return <int>[
      for (final e in raw)
        if (_i(e) case final int id) id,
    ];
  }
  final s = '$raw'.trim();
  if (s.isEmpty) return const <int>[];
  return <int>[
    for (final t in s.split(RegExp(r'[;,\s]+')))
      if (t.isNotEmpty)
        if (int.tryParse(t) case final int id) id,
  ];
}

VsdxGradient _defaultTwoStopGradient(VsdxColor? a, VsdxColor? b) {
  final c0 = a ?? const VsdxColor(0xFFFFFFFF);
  final c1 = b ?? a ?? const VsdxColor(0xFF000000);
  return VsdxGradient(
    type: VsdxGradientType.linear,
    stops: [
      VsdxGradientStop(position: 0, color: c0),
      VsdxGradientStop(position: 1, color: c1),
    ],
  );
}

/// Parse a set_style fillGradient / lineGradient object.
///
/// Accepts `{stops:[{pos|position, color},…], dir?, angle|angleRad?, type?}`.
VsdxGradient? _parseGradientOp(Object? raw) {
  if (raw is! Map) return null;
  final map =
      raw is Map<String, dynamic> ? raw : Map<String, dynamic>.from(raw);
  final stopsRaw = map['stops'];
  if (stopsRaw is! List || stopsRaw.length < 2) return null;
  final stops = <VsdxGradientStop>[];
  for (final s in stopsRaw) {
    if (s is! Map) return null;
    final sm = s is Map<String, dynamic> ? s : Map<String, dynamic>.from(s);
    final pos = _d(sm['pos'] ?? sm['position']);
    final color = parseColorOrNull(sm['color']?.toString());
    if (pos == null || color == null) return null;
    stops.add(VsdxGradientStop(
      position: pos.clamp(0.0, 1.0),
      color: color,
      transparency: (_d(sm['transparency']) ?? 0).clamp(0.0, 1.0),
    ));
  }
  stops.sort((a, b) => a.position.compareTo(b.position));
  final typeStr = map['type']?.toString().toLowerCase();
  final type = switch (typeStr) {
    'radial' => VsdxGradientType.radial,
    'rectangular' || 'rect' => VsdxGradientType.rectangular,
    'path' => VsdxGradientType.path,
    _ => VsdxGradientType.linear,
  };
  final dir = _i(map['dir']);
  // angle = degrees (same as set_style shape angle); angleRad = radians.
  final angleRad = _d(map['angleRad']);
  final angleDeg = _d(map['angle']);
  final angle = angleRad ??
      (angleDeg != null ? angleDeg * (3.141592653589793 / 180.0) : 0.0);
  return VsdxGradient(
    stops: List.unmodifiable(stops),
    type: type,
    angleRad: angle,
    dir: dir,
  );
}

/// Resolve a shape id from an op field.
///
/// Accepts integers, numeric strings (`"12"`), and explicit prefixes
/// (`shape:12`, `Sheet.12`). Rejects bare labels with trailing digits
/// (`"db1"`, `"cache2"`) so Diagram Spec node ids are never mistaken for
/// Visio shape ids.
int? _resolveId(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.isFinite ? v.toInt() : null;
  final s = '$v'.trim();
  if (s.isEmpty) return null;
  final asInt = int.tryParse(s);
  if (asInt != null) return asInt;
  final prefixed =
      RegExp(r'^(?:shape:|Sheet\.)(\d+)$', caseSensitive: false).firstMatch(s);
  if (prefixed != null) return int.parse(prefixed.group(1)!);
  return null;
}

List<int> _resolveIds(Object? v) {
  if (v is List) {
    return <int>[
      for (final e in v)
        if (_resolveId(e) case final int id) id
    ];
  }
  final id = _resolveId(v);
  return id == null ? const <int>[] : <int>[id];
}
