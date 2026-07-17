import 'dart:io';

import 'package:vsdx/vsdx.dart';

void main() {
  for (final name in [
    'Visio11PlanWithDimensions.vsd',
    'Visio11FormatLine.vsd',
    'no-bgcolor.vsd',
    'Visio6PlanWithDimensions.vsd',
  ]) {
    final path = '../../third_party/libvisio/src/test/data/$name';
    if (!File(path).existsSync()) {
      print('SKIP $name (missing)');
      continue;
    }
    final bytes = File(path).readAsBytesSync();
    print('=== $name cfb=${looksLikeCfb(bytes)} binary=${looksLikeVisioBinary(bytes)} ===');
    try {
      final r = parseVisio(bytes);
      print(
        '  imported=${r.importedFromVsd} pages=${r.document.pages.length} '
        'vsdx=${r.originalBytes.length}',
      );
      for (final p in r.document.pages) {
        print(
          '  page ${p.id} ${p.widthInches.toStringAsFixed(2)}x${p.heightInches.toStringAsFixed(2)} '
          'shapes=${p.shapes.length}',
        );
        for (final sh in p.shapes.take(6)) {
          final cmds = sh.geometries.fold<int>(0, (n, g) => n + g.commands.length);
          print(
            '    id=${sh.id} pin=(${sh.pinX.toStringAsFixed(2)},${sh.pinY.toStringAsFixed(2)}) '
            'sz=${sh.width.toStringAsFixed(2)}x${sh.height.toStringAsFixed(2)} '
            'geoms=${sh.geometries.length} cmds=$cmds text=${sh.text == null ? "-" : sh.text!.length}',
          );
        }
      }
    } catch (e) {
      print('  ERROR: $e');
    }
  }
}
