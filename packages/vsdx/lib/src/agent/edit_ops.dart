/// Imperative **Edit Ops** (v0): apply structured edits to an existing document.
///
/// Two entry points share one implementation:
///   * [applyOps] mutates an in-memory [VsdxDocument] — used by the app
///     live-preview bridge (no disk write, instant repaint).
///   * [applyOpsBytes] re-parses `.vsdx` bytes, applies ops, and writes them
///     back through [VsdxWriter] (load-preserve-patch) — used by the CLI /
///     file-mode MCP tools.
///
/// Supported ops: `add_shape`, `add_connector`, `set_style`, `set_text`,
/// `move_shape`, `resize_shape`, `delete_shape`.
/// Schema: `skills/visioeditor-skill/references/spec-schema.md`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:vsdx/vsdx.dart';

import 'agent_style.dart';
import 'stencil_catalog.dart';

/// Outcome of applying a batch of ops.
class ApplyResult {
  ApplyResult(this.document, this.createdIds, this.log);

  /// The edited document.
  final VsdxDocument document;

  /// Shape ids created by `add_shape` / `add_connector`, in op order.
  final List<int> createdIds;

  /// Human-readable notes (skipped ops, unresolved ids, …).
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
  final log = <String>[];
  if (doc.pages.isEmpty) {
    return ApplyResult(doc, created, <String>['document has no pages']);
  }
  final idx = pageIndex.clamp(0, doc.pages.length - 1);
  var page = doc.pages[idx];
  // Only re-route connectors glued to these shapes (never the whole page —
  // that scrambles unrelated authored routes).
  final movedForReroute = <int>{};

  for (final op in ops) {
    final kind = (op['op'] ?? op['type'] ?? '').toString();
    switch (kind) {
      case 'add_shape':
        final id = page.nextFreeShapeId();
        final w = _d(op['w'] ?? op['width']) ?? 1.7;
        final h = _d(op['h'] ?? op['height']) ?? 0.9;
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
        page = page.addShape(s);
        created.add(id);
      case 'add_connector':
      case 'connect':
        final aId = _resolveId(op['from'] ?? op['source']);
        final bId = _resolveId(op['to'] ?? op['target']);
        final a = aId == null ? null : page.findShapeById(aId);
        final b = bId == null ? null : page.findShapeById(bId);
        if (a == null || b == null) {
          log.add('add_connector: unresolved from=${op['from']} to=${op['to']}');
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
        final link = buildConnector(
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
        page = page
            .addShape(link.connector)
            .copyWith(connects: <VsdxConnect>[...page.connects, ...link.connects]);
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
        for (final id in ids) {
          final target = page.findShapeById(id);
          if (target == null) {
            log.add('set_style: shape $id not found');
            continue;
          }
          if (_isProtected(page, target)) {
            log.add('set_style: shape $id is locked');
            continue;
          }
          page = page.updateShapeById(id, (s) {
            var next = s;
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
              next = next.copyWith(
                line: next.line.copyWith(pattern: linePattern),
                geometries: syncGeometryNoLine(
                  next.geometries,
                  hollow: linePattern == 0,
                ),
              );
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
            if (op.containsKey('glow')) {
              final g = op['glow'];
              if (g == false ||
                  (g is String && g.trim().toLowerCase() == 'none')) {
                next = next.copyWith(glow: VsdxGlow.disabled);
              } else if (g == true) {
                next = next.copyWith(
                  glow: next.glow.enabled
                      ? next.glow
                      : const VsdxGlow(enabled: true),
                );
              } else if (g is num) {
                final size = g.toDouble();
                next = next.copyWith(
                  glow: size <= 0
                      ? VsdxGlow.disabled
                      : next.glow.copyWith(enabled: true, sizeInches: size),
                );
              }
            }
            final glowSize = _d(op['glowSize']);
            if (glowSize != null) {
              next = next.copyWith(
                glow: glowSize <= 0
                    ? VsdxGlow.disabled
                    : next.glow.copyWith(
                        enabled: true,
                        sizeInches: glowSize,
                      ),
              );
            }
            final glowColor = parseColorOrNull(op['glowColor']?.toString());
            if (glowColor != null) {
              next = next.copyWith(
                glow: next.glow
                    .copyWith(enabled: true)
                    .withSolidColor(glowColor),
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
            if (op.containsKey('shadow')) {
              final sh = op['shadow'];
              if (sh == false ||
                  (sh is String && sh.trim().toLowerCase() == 'none')) {
                next = next.copyWith(shadow: VsdxShadow.disabled);
              } else if (sh == true) {
                next = next.copyWith(
                  shadow: next.shadow.enabled
                      ? next.shadow
                      : const VsdxShadow(enabled: true),
                );
              }
            }
            final shadowColor =
                parseColorOrNull(op['shadowColor']?.toString());
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
            // Reflection: reflection:true|false|"none", plus size/dist/blur.
            if (op.containsKey('reflection')) {
              final r = op['reflection'];
              if (r == false ||
                  (r is String && r.trim().toLowerCase() == 'none')) {
                next = next.copyWith(reflection: VsdxReflection.disabled);
              } else if (r == true) {
                next = next.copyWith(
                  reflection: next.reflection.enabled
                      ? next.reflection
                      : const VsdxReflection(enabled: true),
                );
              } else if (r is num) {
                final size = r.toDouble();
                next = next.copyWith(
                  reflection: size <= 0
                      ? VsdxReflection.disabled
                      : next.reflection
                          .copyWith(enabled: true, sizeInches: size),
                );
              }
            }
            final reflSize = _d(op['reflectionSize']);
            if (reflSize != null) {
              next = next.copyWith(
                reflection: reflSize <= 0
                    ? VsdxReflection.disabled
                    : next.reflection.copyWith(
                        enabled: true,
                        sizeInches: reflSize,
                      ),
              );
            }
            final reflDist = _d(op['reflectionDist'] ?? op['reflectionDistance']);
            if (reflDist != null) {
              next = next.copyWith(
                reflection: next.reflection.copyWith(
                  enabled: true,
                  distanceInches: reflDist,
                ),
              );
            }
            final reflBlur = _d(op['reflectionBlur']);
            if (reflBlur != null) {
              next = next.copyWith(
                reflection: next.reflection.copyWith(
                  enabled: true,
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
            final textColor =
                (op['textColor'] ?? op['fontColor'])?.toString();
            final bold =
                op.containsKey('bold') ? op['bold'] == true : null;
            final italic =
                op.containsKey('italic') ? op['italic'] == true : null;
            final underline =
                op.containsKey('underline') ? op['underline'] == true : null;
            final strikethrough = op.containsKey('strikethrough')
                ? op['strikethrough'] == true
                : null;
            final doubleUnderline = op.containsKey('doubleUnderline')
                ? op['doubleUnderline'] == true
                : null;
            final doubleStrikethrough = op.containsKey('doubleStrikethrough')
                ? op['doubleStrikethrough'] == true
                : null;
            final overline =
                op.containsKey('overline') ? op['overline'] == true : null;
            final smallCaps =
                op.containsKey('smallCaps') ? op['smallCaps'] == true : null;
            final fontFamily = op['fontFamily']?.toString() ??
                op['font']?.toString();
            final pt = _d(op['pt'] ?? op['fontSize']);
            final letterSpacingPt = _d(op['letterSpacingPt']);
            final letterSpacing = letterSpacingPt != null
                ? letterSpacingPt / 72.0
                : _d(op['letterSpacing']);
            final textTransparency = _d(
                op['textTransparency'] ?? op['charTransparency']);
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
                  'allcaps' || 'all_caps' || 'caps' || '1' =>
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
                  'superscript' || 'super' || '1' =>
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
              next = next.copyWith(
                richText: next.richText.copyWith(
                  textBlock: next.richText.textBlock.copyWith(
                    hideText: op['hideText'] == true,
                  ),
                ),
              );
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
                    textBlock: next.richText.textBlock
                        .copyWith(verticalAlign: align),
                  ),
                );
              }
            }
            final halign = (op['align'] ??
                    op['horizontalAlign'] ??
                    op['horzAlign'])
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
                            paraStyle: r.paraStyle
                                .copyWith(horizontalAlign: align),
                          ),
                      ],
                    ),
                  );
                }
              }
            }
            // Text block background / margins.
            final textBkgnd = (op['textBackground'] ?? op['textBkgnd'])
                ?.toString();
            if (textBkgnd != null) {
              if (textBkgnd.trim().toLowerCase() == 'none') {
                next = next.copyWith(
                  richText: next.richText.copyWith(
                    textBlock:
                        next.richText.textBlock.withoutBackgroundColor(),
                  ),
                );
              } else {
                final c = parseColorOrNull(textBkgnd);
                if (c != null) {
                  next = next.copyWith(
                    richText: next.richText.copyWith(
                      textBlock: next.richText.textBlock
                          .copyWith(backgroundColor: c),
                    ),
                  );
                }
              }
            }
            final textBkgndTrans = _d(op['textBackgroundTransparency'] ??
                op['textBkgndTrans']);
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
                    textBlock: next.richText.textBlock
                        .copyWith(textDirection: dir),
                  ),
                );
              }
            }
            final defaultTabStop = _d(
                op['defaultTabStop'] ?? op['defaultTabStopInches']);
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
                    marginBottomInches: marginB ??
                        next.richText.textBlock.marginBottomInches,
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
            final textPosAfterBullet = _d(
                op['textPosAfterBullet'] ?? op['textPosAfterBulletInches']);
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
              lineSpacingMult = _d(op['lineSpacing']);
              clearAbsolute = true;
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
                  textPosAfterBulletInches: textPosAfterBullet ??
                      p.textPosAfterBulletInches,
                );
                if (solidLine) {
                  next = next.copyWith(
                    lineSpacingSolid: true,
                    lineSpacingAbsoluteInches: 0,
                    lineSpacing: 1.0,
                  );
                } else if (lineSpacingAbs != null) {
                  next = next.copyWith(
                    lineSpacingAbsoluteInches: lineSpacingAbs,
                    lineSpacingSolid: false,
                  );
                } else if (lineSpacingMult != null || clearAbsolute) {
                  next = next.copyWith(
                    lineSpacing: lineSpacingMult ?? p.lineSpacing,
                    lineSpacingAbsoluteInches: 0,
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
            return next;
          });
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

  if (movedForReroute.isNotEmpty) {
    // Match the editor: refresh Sheet.n! / Width* caches before glue re-route.
    page = page
        .recalculateFormulas(changedShapeIds: movedForReroute)
        .rerouteConnectors(movedShapeIds: movedForReroute);
  }
  return ApplyResult(doc.replacePage(idx, page), created, log);
}

/// True when the shape or its layer tree is locked (matches EditorController).
bool _isProtected(VsdxPage page, VsdxShape s) =>
    s.locked || page.isShapeTreeOnLockedLayer(s.id);

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

/// Parse [opsJson] (an array, or an object with `ops:[...]`), apply to
/// [original] `.vsdx` bytes, and write the result back (round-trip faithful).
Uint8List applyOpsBytes(Uint8List original, String opsJson, {int pageIndex = 0}) {
  final decoded = jsonDecode(opsJson);
  final rawOps = decoded is List
      ? decoded
      : (decoded is Map ? (decoded['ops'] as List? ?? const []) : const []);
  final ops = <Map<String, dynamic>>[
    for (final o in rawOps) (o as Map).cast<String, dynamic>(),
  ];
  final doc = const DocumentParser().parse(original);
  final result = applyOps(doc, ops, pageIndex: pageIndex);
  return const VsdxWriter().write(originalBytes: original, edited: result.document);
}

double? _d(Object? v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

int? _i(Object? v) =>
    v == null ? null : (v is int ? v : (v is num ? v.toInt() : int.tryParse('$v')));

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
  final map = raw is Map<String, dynamic>
      ? raw
      : Map<String, dynamic>.from(raw);
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
  final angle = _d(map['angle'] ?? map['angleRad']) ?? 0.0;
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
  if (v is num) return v.toInt();
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
    return <int>[for (final e in v) if (_resolveId(e) case final int id) id];
  }
  final id = _resolveId(v);
  return id == null ? const <int>[] : <int>[id];
}
