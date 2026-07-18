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

  int rect(EditorController e, double x, double y,
      {double w = 1, double h = 0.6, String? text}) {
    e.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id, pinX: cx, pinY: cy, width: w, height: h),
        x,
        y);
    final id = e.singleSelectedId!;
    if (text != null) e.setShapeText(id, text);
    return id;
  }

  test('paste of locked clipboard shapes arrives unlocked', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setSelectionLocked(true);
    e.copySelection();
    e.paste();
    final pasted = e.currentPage!.shapes.last;
    expect(pasted.id, isNot(a));
    // Copies should be editable (draw.io unlocks pasted clones).
    expect(pasted.locked, isFalse);
  });

  test('deleteCurrentPage undo restores page index and selection', () {
    final e = ctrl();
    rect(e, 2, 4);
    e.addPage();
    final b = rect(e, 3, 3);
    expect(e.currentPageIndex, 1);
    e.setSelection([b]);
    e.deleteCurrentPage();
    expect(e.currentPageIndex, 0);
    e.undo();
    expect(e.currentPageIndex, 1);
    expect(e.selection, contains(b));
  });

  test('replaceImage focuses the picture and restores prior sel on undo', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.insertImage(
      Uint8List.fromList([1, 2, 3, 4]),
      fileExtension: 'png',
      widthInches: 1,
      heightInches: 1,
      cx: 3,
      cy: 3,
    );
    final pic = e.singleSelectedId!;
    e.setSelection([a, pic]);
    e.replaceImage(
      pic,
      Uint8List.fromList([9, 9, 9, 9]),
      fileExtension: 'png',
    );
    expect(e.selection, equals({pic}));
    e.undo();
    expect(e.selection, equals({a, pic}));
  });

  test('setLineOpacity seeds memo for new shapes', () {
    final e = ctrl();
    rect(e, 2, 4);
    e.setLineOpacity(0.25);
    final b = rect(e, 5, 4);
    expect(
      e.currentPage!.findShapeById(b)!.line.transparency,
      closeTo(0.75, 1e-9),
    );
  });

  test('selectedHasShadow ignores 1D-first mixed selection', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setShadow(true);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setSelection([conn, a]);
    // Getter should reflect that a 2-D selected shape has shadow.
    expect(e.selectedHasShadow, isTrue);
  });

  test('moving group moves locked children with it', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 4, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    e.setSelection([a]);
    e.setSelectionLocked(true);
    e.setSelection([g]);
    final before = e.currentPage!.shapePinPage(a).x;
    e.moveSelectionBy(1, 0);
    final after = e.currentPage!.shapePinPage(a).x;
    // Group translate is a parent move — children follow in page space.
    expect(after - before, closeTo(1, 1e-9));
  });

  test('setShapeProperties on locked is no-op and no orphan undo', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setSelectionLocked(true);
    e.setShapeProperties(a, [
      const VsdxUserProperty(name: 'Cost', value: '10'),
    ]);
    expect(e.currentPage!.findShapeById(a)!.userProperties, isEmpty);
    e.undo(); // unlock
    expect(e.currentPage!.findShapeById(a)!.locked, isFalse);
  });

  test('flip mixed locked flips unlocked only', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.setSelection([a]);
    e.setSelectionLocked(true);
    e.setSelection([a, b]);
    e.flipHorizontal();
    expect(e.currentPage!.findShapeById(a)!.flipX, isFalse);
    expect(e.currentPage!.findShapeById(b)!.flipX, isTrue);
  });

  test('bringSelectionToFront locked-only creates no undo beyond lock', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    rect(e, 5, 4);
    e.setSelection([a]);
    e.setSelectionLocked(true);
    e.bringSelectionToFront();
    e.undo(); // unlock
    expect(e.currentPage!.findShapeById(a)!.locked, isFalse);
  });

  test('setCompoundType on 1D is allowed', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setSelection([conn]);
    e.setCompoundType(2);
    expect(e.currentPage!.findShapeById(conn)!.line.compoundType, 2);
  });

  test('matchSelectionSize ignores 1D-first reference', () {
    final e = ctrl();
    final a = rect(e, 2, 4, w: 2, h: 1);
    final b = rect(e, 5, 4, w: 1, h: 0.5);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setSelection([conn, a, b]);
    e.matchSelectionSize();
    expect(e.currentPage!.findShapeById(b)!.width, closeTo(2, 1e-9));
    expect(e.currentPage!.findShapeById(b)!.height, closeTo(1, 1e-9));
  });

  test('clearSelectedConnectorWaypoints skips locked', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setSelection([conn]);
    e.setConnectorWaypoints(conn, [
      const Offset2D(3.5, 5),
    ]);
    expect(e.currentPage!.findShapeById(conn)!.waypoints, isNotEmpty);
    e.setSelectionLocked(true);
    e.clearSelectedConnectorWaypoints();
    expect(e.currentPage!.findShapeById(conn)!.waypoints, isNotEmpty);
  });

  test('selectAll then delete keeps locked', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.setSelection([a]);
    e.setSelectionLocked(true);
    e.selectAll();
    e.deleteSelection();
    expect(e.currentPage!.findShapeById(a), isNotNull);
    expect(e.currentPage!.findShapeById(b), isNull);
  });

  test('setPageLandscape undo restores size', () {
    final e = ctrl();
    expect(e.pageIsLandscape, isTrue);
    e.setPageLandscape(false);
    expect(e.pageIsLandscape, isFalse);
    e.undo();
    expect(e.pageIsLandscape, isTrue);
  });

  test('duplicateSelection remaps internal connector glue', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    e.setSelection([a, b, e.currentPage!.shapes.lastWhere((s) => s.is1D).id]);
    final beforeConnects = e.currentPage!.connects.length;
    e.duplicateSelection();
    expect(e.currentPage!.connects.length, greaterThan(beforeConnects));
    // New connects must not point at original ids only.
    final sel = e.selection;
    final glued = e.currentPage!.connects
        .where((c) => sel.contains(c.fromSheetId))
        .map((c) => c.toSheetId)
        .toSet();
    expect(glued.every(sel.contains), isTrue);
  });
}
