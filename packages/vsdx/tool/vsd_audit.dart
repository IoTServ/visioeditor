// ignore_for_file: avoid_print

import 'dart:io';

import 'package:vsdx/vsdx.dart';

void main() {
  final dir = Directory('../../third_party/libvisio/src/test/data');
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.vsd'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    final name = f.uri.pathSegments.last;
    try {
      final r = parseVisio(f.readAsBytesSync());
      final doc = r.document;
      final shapes = <VsdxShape>[];
      void walk(VsdxShape s) {
        shapes.add(s);
        for (final c in s.children) {
          walk(c);
        }
      }

      for (final p in doc.pages) {
        for (final s in p.shapes) {
          walk(s);
        }
      }
      final withGeom = shapes.where((s) => s.geometries.isNotEmpty).length;
      final withText = shapes.where((s) => s.richText.plainText.trim().isNotEmpty).length;
      final withFont = shapes.expand((s) => s.richText.runs)
          .where((r) => (r.charStyle.fontFamily ?? '').trim().isNotEmpty).length;
      final withImg = shapes.where((s) => s.imagePartName != null).length;
      final withTabs = shapes.where((s) => s.richText.tabSets.isNotEmpty).length;
      final multiRun = shapes.where((s) => s.richText.runs.length > 1).length;
      final serialish = shapes.where((s) {
        final t = s.richText.plainText;
        return RegExp(r'\b3[7-9]\d{3}(?:\.\d+)?\b').hasMatch(t) ||
            RegExp(r'\b4[0-4]\d{3}(?:\.\d+)?\b').hasMatch(t);
      }).length;
      final synth = const DocumentParser().parse(r.originalBytes);
      final synthShapes = <VsdxShape>[];
      void walk2(VsdxShape s) {
        synthShapes.add(s);
        for (final c in s.children) {
          walk2(c);
        }
      }

      for (final p in synth.pages) {
        for (final s in p.shapes) {
          walk2(s);
        }
      }
      final lostG = withGeom - synthShapes.where((s) => s.geometries.isNotEmpty).length;
      final lostI = withImg - synthShapes.where((s) => s.imagePartName != null).length;
      final lostT = withText - synthShapes.where((s) => s.richText.plainText.trim().isNotEmpty).length;
      print('$name sh=${shapes.length} g=$withGeom t=$withText f=$withFont img=$withImg '
          'tabs=$withTabs multi=$multiRun serial=$serialish '
          'lostG=$lostG lostI=$lostI lostT=$lostT');
    } catch (e) {
      print('$name FAIL $e');
    }
  }
}
