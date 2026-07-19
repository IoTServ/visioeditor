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
          if (page.findShapeById(id) == null) {
            log.add('set_style: shape $id not found');
            continue;
          }
          page = page.updateShapeById(id, (s) {
            var next = s;
            if (fillHex != null) {
              if (fillHex.trim().toLowerCase() == 'none') {
                next = next.copyWith(fill: const VsdxFill(pattern: 0));
              } else {
                final c = parseColorOrNull(fillHex);
                if (c != null) {
                  next = next.copyWith(fill: next.fill.withSolidForeground(c));
                }
              }
            }
            if (lineHex != null) {
              if (lineHex.trim().toLowerCase() == 'none') {
                next = next.copyWith(line: next.line.copyWith(pattern: 0));
              } else {
                final c = parseColorOrNull(lineHex);
                if (c != null) {
                  next = next.copyWith(line: next.line.withSolidColor(c));
                }
              }
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
        if (page.findShapeById(id) == null) {
          log.add('set_text: shape $id not found');
          break;
        }
        page = page.updateShapeById(
            id,
            (s) => withLabel(s, (op['text'] ?? '').toString(),
                bold: op['bold'] == true,
                colorHex: (op['textColor'] ?? op['fontColor'])?.toString()));
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
        if (resizing.is1D &&
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
        } else {
          page = page.updateShapeById(
            id,
            (s) => s.resizeTo(
              pinX: s.pinX,
              pinY: s.pinY,
              width: w,
              height: h,
            ),
          );
          _addSubtreeIds(page, id, movedForReroute);
        }
      case 'delete_shape':
      case 'delete':
        final id = _resolveId(op['id']);
        if (id == null) {
          log.add('delete_shape: missing or invalid id=${op['id']}');
          break;
        }
        if (page.findShapeById(id) == null) {
          log.add('delete_shape: shape $id not found');
          break;
        }
        // removeShapeById prunes Connect rows; no selective re-route needed.
        page = page.removeShapeById(id);
      default:
        log.add('unknown op: "$kind"');
    }
  }

  if (movedForReroute.isNotEmpty) {
    page = page.rerouteConnectors(movedShapeIds: movedForReroute);
  }
  return ApplyResult(doc.replacePage(idx, page), created, log);
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
