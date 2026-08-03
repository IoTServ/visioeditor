import 'dart:io';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

import 'support/libvisio_oracle.dart';

void main() {
  final oracle = LibvisioOracle.tryLoad();
  final skipReason = oracle == null
      ? 'libvisio oracle unavailable; run packages/vsdx/native/build.sh'
      : false;

  for (final fixture in _fixtures()) {
    test('${fixture.path} identity write preserves libvisio rendering', () {
      final bytes = fixture.readAsBytesSync();
      final before = oracle!.svgPages(bytes);
      if (before == null) return;

      final document = const DocumentParser().parse(bytes);
      final written = const VsdxWriter(preserveUnchangedPackage: true).write(
        originalBytes: bytes,
        edited: document,
      );

      expect(written, bytes,
          reason: '${fixture.path} no-op write must preserve package bytes');
      expect(oracle.svgPages(written), before,
          reason: '${fixture.path} libvisio SVG after no-op write');
    }, skip: skipReason);
  }

  test('identity preservation still writes a geometry flag edit', () {
    final fixture = File('test/fixtures/test9_rect_and_line.vsdx');
    final bytes = fixture.readAsBytesSync();
    final document = const DocumentParser().parse(bytes);
    final page = document.pages.first;
    final shape = page.shapes.firstWhere((s) => s.geometries.isNotEmpty);
    final geometry = shape.geometries.first;
    final editedShape = shape.copyWith(
      geometries: <VsdxGeometry>[
        geometry.copyWith(noShow: !geometry.noShow),
        ...shape.geometries.skip(1),
      ],
    );
    final edited = document.replacePage(
      0,
      page.updateShapeById(shape.id, (_) => editedShape),
    );

    final written = const VsdxWriter(preserveUnchangedPackage: true).write(
      originalBytes: bytes,
      edited: edited,
    );
    final reopened = const DocumentParser().parse(written);

    expect(written, isNot(bytes));
    expect(
      reopened.pages.first.findShapeById(shape.id)!.geometries.first.noShow,
      !geometry.noShow,
    );
  });
}

List<File> _fixtures() {
  final byPath = <String, File>{};
  for (final directory in <Directory>[
    Directory('../../third_party/libvisio/src/test/data'),
    Directory('test/fixtures'),
    Directory('../../assets/examples'),
  ]) {
    if (!directory.existsSync()) continue;
    for (final file in directory
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()) {
      if (file.path.toLowerCase().endsWith('.vsdx')) {
        byPath[file.absolute.path] = file;
      }
    }
  }
  return byPath.values.toList()..sort((a, b) => a.path.compareTo(b.path));
}
