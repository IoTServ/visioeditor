import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

/// Regression guard: editing one part of an imported drawing must not disturb
/// the authored routes of connectors elsewhere. Historically any edit that
/// triggered [VsdxPage.rerouteConnectors] re-routed *every* glued connector,
/// scrambling hand-drawn / multi-bend lines in complex Visio files.
Uint8List _fixture(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

String _sig(VsdxShape s) {
  final g = s.geometries.isNotEmpty ? s.geometries.first : null;
  final cmds = g?.commands ?? const <VsdxPathCommand>[];
  final b = StringBuffer('id=${s.id} pin=(${s.pinX.toStringAsFixed(3)},'
      '${s.pinY.toStringAsFixed(3)}) wh=(${s.width.toStringAsFixed(3)},'
      '${s.height.toStringAsFixed(3)}) begin=(${s.beginX},${s.beginY}) '
      'end=(${s.endX},${s.endY}) cmds=');
  for (final c in cmds) {
    if (c is MoveTo) {
      b.write('M${c.x.toStringAsFixed(3)},${c.y.toStringAsFixed(3)} ');
    }
    if (c is LineTo) {
      b.write('L${c.x.toStringAsFixed(3)},${c.y.toStringAsFixed(3)} ');
    }
  }
  return b.toString();
}

Map<int, String> _connectorSigs(VsdxPage page) {
  final out = <int, String>{};
  void walk(VsdxShape s) {
    if (s.is1D) out[s.id] = _sig(s);
    for (final c in s.children) {
      walk(c);
    }
  }

  for (final s in page.shapes) {
    walk(s);
  }
  return out;
}

void main() {
  final parser = DocumentParser();
  final writer = VsdxWriter();

  for (final name in <String>[
    'workflow.vsdx',
    'test4_connectors.vsdx',
    '数据治理.vsdx',
    '人才招聘冰山模型.vsdx',
  ]) {
    test('adding a shape keeps existing connectors unchanged: $name', () {
      final bytes = _fixture(name);
      final doc = parser.parse(bytes);
      final page = doc.pages.first;
      final before = _connectorSigs(page);

      // Simulate the app adding a rectangle to the page, then saving.
      final id = page.nextFreeShapeId();
      final rect = VsdxShapeFactory.rectangle(
        id: id,
        pinX: 1.0,
        pinY: 1.0,
        width: 1.0,
        height: 0.6,
      );
      final edited = doc.replacePage(0, page.addShape(rect));

      final out = writer.write(originalBytes: bytes, edited: edited);
      final reparsed = parser.parse(out).pages.first;
      final after = _connectorSigs(reparsed);

      expect(reparsed.findShapeById(id), isNotNull,
          reason: 'added rectangle missing after round-trip');

      final drifted = <String>[];
      for (final e in before.entries) {
        final a = after[e.key];
        if (a == null) {
          drifted.add('connector ${e.key} DISAPPEARED');
        } else if (a != e.value) {
          drifted.add('connector ${e.key}:\n  BEFORE ${e.value}\n  AFTER  $a');
        }
      }
      expect(drifted, isEmpty,
          reason: '${drifted.length} connector(s) changed after adding a '
              'shape:\n${drifted.take(6).join('\n')}');
    });

    test('moving one shape leaves unrelated connectors untouched: $name', () {
      final bytes = _fixture(name);
      final doc = parser.parse(bytes);
      final page = doc.pages.first;
      final before = _connectorSigs(page);

      // Nudge a leaf shape that is neither a connector nor glued to one; only
      // connectors touching it are allowed to change.
      final connected = <int>{
        for (final c in page.connects) c.fromSheetId,
        for (final c in page.connects) c.toSheetId,
      };
      int? victim;
      void findVictim(List<VsdxShape> list) {
        for (final s in list) {
          if (s.children.isNotEmpty) {
            findVictim(s.children);
          } else if (!s.is1D && !connected.contains(s.id) && victim == null) {
            victim = s.id;
          }
        }
      }

      findVictim(page.shapes);
      if (victim == null) return; // nothing safe to move; skip

      final moved = page
          .updateShapeById(victim!, (s) => s.copyWith(pinX: s.pinX + 2))
          .rerouteConnectors(movedShapeIds: <int>{victim!});
      final after = _connectorSigs(moved);
      final drifted = <int>[
        for (final e in before.entries)
          if (after[e.key] != e.value) e.key,
      ];
      expect(drifted, isEmpty,
          reason: 'moving unrelated shape $victim changed connectors $drifted');
    });
  }
}
