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
  var reroute = false;

  for (final op in ops) {
    final kind = (op['op'] ?? op['type'] ?? '').toString();
    switch (kind) {
      case 'add_shape':
        final id = page.nextFreeShapeId();
        final w = _d(op['w'] ?? op['width']) ?? 1.7;
        final h = _d(op['h'] ?? op['height']) ?? 0.9;
        var s = buildStencilShape(
          stencil: (op['stencil'] ?? op['shape'] ?? 'rectangle').toString(),
          id: id,
          cx: _d(op['x']) ?? page.widthInches / 2,
          cy: _d(op['y']) ?? page.heightInches / 2,
          w: w,
          h: h,
          fill: fillFromHex(op['fill']?.toString()),
          line: lineFromHex((op['line'] ?? op['stroke'])?.toString()),
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
        reroute = true;
      case 'set_style':
        final ids = _resolveIds(op['ids'] ?? op['id']);
        final fillHex = op['fill']?.toString();
        final lineHex = (op['line'] ?? op['stroke'])?.toString();
        for (final id in ids) {
          page = page.updateShapeById(id, (s) {
            var next = s;
            if (fillHex != null) next = next.copyWith(fill: fillFromHex(fillHex));
            if (lineHex != null) {
              next = next.copyWith(
                  line: lineFromHex(lineHex,
                      endArrow: s.is1D ? s.line.endArrow : 0));
            }
            return next;
          });
        }
      case 'set_text':
        final id = _resolveId(op['id']);
        if (id == null) {
          log.add('set_text: missing id');
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
        page = page.updateShapeById(id, (s) => s.copyWith(pinX: x, pinY: y));
        reroute = true;
      case 'resize_shape':
      case 'resize':
        final id = _resolveId(op['id']);
        final w = _d(op['w'] ?? op['width']);
        final h = _d(op['h'] ?? op['height']);
        if (id == null || w == null || h == null) {
          log.add('resize_shape: needs id,w,h');
          break;
        }
        page = page.updateShapeById(
            id, (s) => s.resizeTo(pinX: s.pinX, pinY: s.pinY, width: w, height: h));
        reroute = true;
      case 'delete_shape':
      case 'delete':
        final id = _resolveId(op['id']);
        if (id == null) {
          log.add('delete_shape: missing id');
          break;
        }
        page = page.removeShapeById(id);
        reroute = true;
      default:
        log.add('unknown op: "$kind"');
    }
  }

  if (reroute) page = page.rerouteConnectors();
  return ApplyResult(doc.replacePage(idx, page), created, log);
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

int? _resolveId(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  final m = RegExp(r'(\d+)\s*$').firstMatch('$v');
  return m == null ? null : int.parse(m.group(1)!);
}

List<int> _resolveIds(Object? v) {
  if (v is List) {
    return <int>[for (final e in v) if (_resolveId(e) case final int id) id];
  }
  final id = _resolveId(v);
  return id == null ? const <int>[] : <int>[id];
}
