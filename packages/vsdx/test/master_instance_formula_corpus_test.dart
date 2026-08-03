import 'dart:io';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  test('office_varient4 master geometry expands to instance Width/Height', () {
    final fixture = File(
      '../../third_party/libvisio/src/test/data/office_varient4.vsdx',
    );
    expect(fixture.existsSync(), isTrue);
    final document = const DocumentParser().parse(fixture.readAsBytesSync());
    final shape = document.pages.single.shapes.single;

    expect(shape.width, closeTo(3.051181102362205, 1e-9));
    expect(shape.height, closeTo(1.830708661417323, 1e-9));
    expect(shape.effectiveLocPinX, closeTo(shape.width / 2, 1e-9));
    expect(shape.effectiveLocPinY, closeTo(shape.height / 2, 1e-9));

    final commands = shape.geometries.single.commands;
    final linePoints = commands.whereType<LineTo>().toList();
    expect(linePoints.map((point) => point.x).reduce((a, b) => a > b ? a : b),
        closeTo(shape.width, 1e-9));
    expect(linePoints.map((point) => point.y).reduce((a, b) => a > b ? a : b),
        closeTo(shape.height, 1e-9));
  });

  test('testfile1 nested MasterShape caches expand the event group', () {
    final fixture = File(
      '../../third_party/libvisio/src/test/data/testfile1.vsdx',
    );
    expect(fixture.existsSync(), isTrue);
    final document = const DocumentParser().parse(fixture.readAsBytesSync());
    final group = document.pages.single.shapes.single;
    final outer = group.children.first;

    expect(group.width, closeTo(2.165354330708662, 1e-9));
    expect(group.height, closeTo(2.165354330708662, 1e-9));
    expect(outer.width, closeTo(group.width, 1e-9));
    expect(outer.height, closeTo(group.height, 1e-9));
    expect(outer.pinX, closeTo(group.width / 2, 1e-9));
    expect(outer.pinY, closeTo(group.height / 2, 1e-9));
  });

  test('testfile5 QuickStyle matrix selects variation white fill', () {
    final fixture = File(
      '../../third_party/libvisio/src/test/data/testfile5.vsdx',
    );
    final document = const DocumentParser().parse(fixture.readAsBytesSync());
    final page = document.pages.single;
    final shape = page.shapes.single;

    expect(document.theme.fillStyleColors, hasLength(6));
    expect(document.theme.variationFillStyleIndices, hasLength(4));
    expect(page.pageSheet.variationColorIndex, 1);
    expect(page.pageSheet.variationStyleIndex, 1);
    expect(shape.fill.themeForegroundIndex, 100);
    expect(shape.quickStyleFillMatrix, 100);
    expect(
      document.theme.resolveFill(
        shape.fill.themeForegroundIndex!,
        variationColorIndex: page.pageSheet.variationColorIndex!,
        variationStyleIndex: page.pageSheet.variationStyleIndex!,
        fillMatrix: shape.quickStyleFillMatrix,
      ),
      const VsdxColor(0xFFFFFFFF),
    );
  });
}
