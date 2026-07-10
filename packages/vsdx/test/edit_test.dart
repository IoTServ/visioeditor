import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

void main() {
  const parser = DocumentParser();

  test('shape copyWith updates only the requested field', () {
    final doc = parser.parse(_fixture('test9_rect_and_line.vsdx'));
    final shape = doc.pages.first.shapes.first;
    final moved = shape.copyWith(pinX: shape.pinX + 1.5);

    expect(moved.pinX, closeTo(shape.pinX + 1.5, 1e-9));
    expect(moved.pinY, shape.pinY);
    expect(moved.width, shape.width);
    expect(moved.id, shape.id);
    expect(moved.name, shape.name);
    // Original is untouched (immutability).
    expect(shape.pinX, isNot(moved.pinX));
  });

  test('updateShapeById moves one shape and shares the rest', () {
    final doc = parser.parse(_fixture('test9_rect_and_line.vsdx'));
    final page = doc.pages.first;
    final target = page.shapes.first;

    final newPage = page.updateShapeById(
      target.id,
      (s) => s.copyWith(pinX: s.pinX + 2, pinY: s.pinY + 3),
    );

    expect(identical(newPage, page), isFalse);
    final movedTarget = newPage.findShapeById(target.id)!;
    expect(movedTarget.pinX, closeTo(target.pinX + 2, 1e-9));
    expect(movedTarget.pinY, closeTo(target.pinY + 3, 1e-9));

    // Untouched siblings keep their identity (structural sharing).
    if (page.shapes.length > 1) {
      expect(identical(newPage.shapes.last, page.shapes.last), isTrue);
    }
    // Original page still reports the old position.
    expect(page.findShapeById(target.id)!.pinX, target.pinX);
  });

  test('updateShapeById with an unknown id returns the same page', () {
    final doc = parser.parse(_fixture('test9_rect_and_line.vsdx'));
    final page = doc.pages.first;
    final same = page.updateShapeById(-999, (s) => s.copyWith(pinX: 0));
    expect(identical(same, page), isTrue);
  });

  test('resizeTo scales a rectangle geometry with its box', () {
    final rect = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 0,
      pinY: 0,
      width: 2,
      height: 1,
    );
    final bigger = rect.resizeTo(pinX: 0, pinY: 0, width: 4, height: 2);
    expect(bigger.width, closeTo(4, 1e-9));
    expect(bigger.height, closeTo(2, 1e-9));
    // The far corner LineTo(2,·) should now reach x = 4 (doubled).
    final reachesFarX = bigger.geometries.first.commands
        .any((c) => c is LineTo && (c.x - 4).abs() < 1e-9);
    expect(reachesFarX, isTrue);
  });

  test('rerouteConnectors keeps a glued connector attached to moved shapes', () {
    // Build a page: two rectangles + a connector glued between them.
    final r1 = VsdxShapeFactory.rectangle(
        id: 1, pinX: 1, pinY: 1, width: 1, height: 1);
    final r2 = VsdxShapeFactory.rectangle(
        id: 2, pinX: 5, pinY: 5, width: 1, height: 1);
    final conn = VsdxShapeFactory.line(id: 3, ax: 1, ay: 1, bx: 5, by: 5);
    var page = VsdxPage(
      id: 0,
      name: 'P1',
      widthInches: 8.5,
      heightInches: 11,
      shapes: [r1, r2, conn],
      connects: const [
        VsdxConnect(
            fromSheetId: 3, fromCell: 'BeginX', toSheetId: 1, toCell: 'PinX'),
        VsdxConnect(
            fromSheetId: 3, fromCell: 'EndX', toSheetId: 2, toCell: 'PinX'),
      ],
    );

    // Move r2 to a new centre; the connector's end must follow.
    page = page
        .updateShapeById(2, (s) => s.copyWith(pinX: 7, pinY: 3))
        .rerouteConnectors();

    final connector = page.findShapeById(3)!;
    expect(connector.beginX, closeTo(1, 1e-9));
    expect(connector.beginY, closeTo(1, 1e-9));
    expect(connector.endX, closeTo(7, 1e-9));
    expect(connector.endY, closeTo(3, 1e-9));
  });

  test('document.replacePage swaps a single page immutably', () {
    final doc = parser.parse(_fixture('test1.vsdx'));
    final page0 = doc.pages.first;
    final edited = page0.updateShapeById(
      page0.shapes.first.id,
      (s) => s.copyWith(pinX: s.pinX + 1),
    );
    final newDoc = doc.replacePage(0, edited);

    expect(identical(newDoc, doc), isFalse);
    expect(newDoc.pages.first.shapes.first.pinX,
        closeTo(page0.shapes.first.pinX + 1, 1e-9));
    // Original document unchanged.
    expect(doc.pages.first.shapes.first.pinX, page0.shapes.first.pinX);
  });
}
