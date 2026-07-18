import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  EditorController ctrl() {
    final c = EditorController()
      ..newDocument(widthInches: 11, heightInches: 8.5);
    addTearDown(c.dispose);
    return c;
  }

  int addRect(EditorController c, double x, double y,
      {double w = 1.0, double h = 0.6}) {
    c.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id, pinX: cx, pinY: cy, width: w, height: h),
        x,
        y);
    return c.singleSelectedId!;
  }

  test('bringToFront multi-selection preserves relative order of selected', () {
    final c = ctrl();
    final a = addRect(c, 1, 4);
    final b = addRect(c, 3, 4);
    final d = addRect(c, 5, 4);
    expect(c.currentPage!.shapes.map((s) => s.id).toList(), [a, b, d]);
    c.setSelection([a, b]);
    c.bringSelectionToFront();
    final order = c.currentPage!.shapes.map((s) => s.id).toList();
    expect(order.last, b);
    expect(order[order.length - 2], a);
    expect(order.first, d);
  });

  test('sendToBack multi-selection preserves relative order', () {
    final c = ctrl();
    final a = addRect(c, 1, 4);
    final b = addRect(c, 3, 4);
    final d = addRect(c, 5, 4);
    c.setSelection([b, d]);
    c.sendSelectionToBack();
    final order = c.currentPage!.shapes.map((s) => s.id).toList();
    expect(order.take(2).toSet(), {b, d});
    expect(order.indexOf(b) < order.indexOf(d), isTrue);
    expect(order.last, a);
  });

  test('align skips locked members in mixed selection', () {
    final c = ctrl();
    final a = addRect(c, 1, 4);
    final b = addRect(c, 5, 4);
    c.setSelection([a]);
    c.setSelectionLocked(true);
    c.setSelection([a, b]);
    final pinA0 = c.currentPage!.findShapeById(a)!.pinX;
    final pinB0 = c.currentPage!.findShapeById(b)!.pinX;
    c.alignLeft();
    expect(c.currentPage!.findShapeById(a)!.pinX, pinA0);
    // Unlocked b should move; locked a is the align anchor if included.
    expect(c.currentPage!.findShapeById(b)!.pinX, isNot(pinB0));
  });

  test('rotateSelection90 skips locked', () {
    final c = ctrl();
    final a = addRect(c, 2, 4);
    c.setSelectionLocked(true);
    c.rotateSelection90();
    expect(c.currentPage!.findShapeById(a)!.angleRad, 0);
  });

  test('deleteSelection with mixed lock deletes only unlocked', () {
    final c = ctrl();
    final a = addRect(c, 1, 4);
    final b = addRect(c, 3, 4);
    c.setSelection([a]);
    c.setSelectionLocked(true);
    c.setSelection([a, b]);
    c.deleteSelection();
    expect(c.currentPage!.findShapeById(a), isNotNull);
    expect(c.currentPage!.findShapeById(b), isNull);
  });

  test('undo after delete restores selection of deleted shapes', () {
    final c = ctrl();
    final a = addRect(c, 1, 4);
    c.deleteSelection();
    expect(c.selection, isEmpty);
    c.undo();
    expect(c.currentPage!.findShapeById(a), isNotNull);
    expect(c.selection, contains(a));
  });

  test('matchSelectionWidth skips locked', () {
    final c = ctrl();
    final a = addRect(c, 1, 4, w: 2.0);
    final b = addRect(c, 4, 4, w: 0.5);
    c.setSelection([b]);
    c.setSelectionLocked(true);
    c.setSelection([a, b]);
    c.matchSelectionWidth();
    expect(c.currentPage!.findShapeById(b)!.width, closeTo(0.5, 1e-9));
  });

  test('paste image from in-memory clipboard mints a new part name', () {
    final c = ctrl();
    final bytes = Uint8List.fromList(<int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      0, 0, 0, 0,
    ]);
    c.insertImage(bytes, fileExtension: 'png', cx: 3, cy: 4);
    final id = c.singleSelectedId!;
    expect(c.currentPage!.findShapeById(id)!.hasImage, isTrue);
    final part0 = c.currentPage!.findShapeById(id)!.imagePartName!;
    c.copySelection();
    c.paste();
    final images = c.currentPage!.shapes.where((s) => s.hasImage).toList();
    expect(images, hasLength(2));
    expect(images.map((s) => s.imagePartName).toSet(), hasLength(2));
    expect(images.any((s) => s.imagePartName == part0), isTrue);
  });

  test('group then move reroutes external connector', () {
    final c = ctrl();
    final a = addRect(c, 2, 4);
    final b = addRect(c, 6, 4);
    c.createConnector(2, 4, 6, 4, beginTarget: a, endTarget: b);
    final conn = c.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    c.setSelection([a, b]);
    c.groupSelection();
    c.moveSelectionBy(1, 0);
    final connector = c.currentPage!.findShapeById(conn)!;
    final pinA = c.currentPage!.shapePinPage(a);
    final pinB = c.currentPage!.shapePinPage(b);
    // Perimeter glue may sit on the shape edge (± half-width), not the pin.
    expect((connector.beginX! - pinA.x).abs(), lessThanOrEqualTo(0.55));
    expect((connector.endX! - pinB.x).abs(), lessThanOrEqualTo(0.55));
  });

  test('duplicateSelection of glued pair remaps both ends', () {
    final c = ctrl();
    final a = addRect(c, 2, 4);
    final b = addRect(c, 5, 4);
    c.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = c.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    c.setSelection([a, b, conn]);
    c.duplicateSelection();
    final page = c.currentPage!;
    expect(page.shapes.length, 6);
    final newConn = page.shapes.lastWhere((s) => s.is1D && s.id != conn);
    expect(
      newConn.formulas.values
          .any((f) => f.contains('Sheet.$a!') || f.contains('Sheet.$b!')),
      isFalse,
    );
  });

  test('flipHorizontal is undoable single step', () {
    final c = ctrl();
    final a = addRect(c, 2, 4);
    c.flipHorizontal();
    expect(c.currentPage!.findShapeById(a)!.flipX, isTrue);
    c.undo();
    expect(c.currentPage!.findShapeById(a)!.flipX, isFalse);
  });

  test('setNoFill on connector does not throw', () {
    final c = ctrl();
    final a = addRect(c, 2, 4);
    final b = addRect(c, 5, 4);
    c.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    c.setNoFill();
    expect(c.currentPage!.shapes.lastWhere((s) => s.is1D).fill.pattern, 0);
  });
}
