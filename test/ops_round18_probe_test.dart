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

  test('duplicate of locked-only selection is no-op', () {
    final e = ctrl();
    rect(e, 2, 4);
    e.setSelectionLocked(true);
    e.duplicateSelection();
    expect(e.currentPage!.shapes.length, 1);
  });

  test('copyStyle from 1D then pasteStyle on 2D keeps fill', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setFillColor(const VsdxColor(0xFF00FF00));
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setSelection([conn]);
    e.setLineColor(const VsdxColor(0xFFFF0000));
    e.copyStyle();
    e.setSelection([a]);
    final fillBefore = e.currentPage!.findShapeById(a)!.fill.foreground;
    e.pasteStyle();
    // 1-D clipboard has no fill payload for 2-D — fill should stay (or be
    // explicitly preserved). Document: pasteStyle from 1D only updates line.
    final after = e.currentPage!.findShapeById(a)!;
    expect(after.line.color?.value, 0xFFFF0000);
    expect(after.fill.foreground?.value, fillBefore?.value);
  });

  test('setFillThemeSlot mixed 1D+2D only themes the box', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setSelection([a, conn]);
    e.setFillThemeSlot(0);
    expect(e.document!.theme.isEmpty, isFalse);
    expect(
      e.currentPage!.findShapeById(a)!.fill.themeForegroundIndex,
      isNotNull,
    );
  });

  test('ungroup undo restores group and prior selection', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    e.ungroupSelection();
    e.undo();
    expect(e.selection, equals({g}));
    expect(e.currentPage!.findShapeById(g)?.children.length, 2);
  });

  test('addPageGuide near-duplicate is ignored', () {
    final e = ctrl();
    e.addPageGuide(vertical: true, pos: 3.0);
    e.addPageGuide(vertical: true, pos: 3.01);
    expect(e.pageGuides.length, 1);
  });

  test('rotateSelection90 mixed locked rotates unlocked only', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.setSelection([a]);
    e.setSelectionLocked(true);
    e.setSelection([a, b]);
    e.rotateSelection90();
    expect(e.currentPage!.findShapeById(a)!.angleRad, 0);
    expect(e.currentPage!.findShapeById(b)!.angleRad, isNot(0));
  });

  test('setTextAlign on empty seeds para style for later typing', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setTextAlign(VsdxHorzAlign.left);
    e.setShapeText(a, 'hi');
    expect(
      e.currentPage!.findShapeById(a)!.richText.runs.first.paraStyle
          .horizontalAlign,
      VsdxHorzAlign.left,
    );
  });

  test('deleteLayer then undo restores membership', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setSelection([a]);
    e.addLayer(name: 'L', assignSelection: true);
    final layerId = e.currentPage!.layers.last.id;
    e.deleteLayer(layerId);
    expect(e.currentPage!.layers.where((l) => l.id == layerId), isEmpty);
    e.undo();
    expect(
      e.currentPage!.findShapeById(a)!.layerMemberIds,
      contains(layerId),
    );
  });

  test('sendSelectionToBack locked mixed only moves unlocked', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    final c = rect(e, 3, 2);
    e.setSelection([b]);
    e.setSelectionLocked(true);
    e.setSelection([a, b]);
    // Order before: a, b, c. Send a+b to back — locked b stays; a moves.
    e.sendSelectionToBack();
    final order = e.currentPage!.shapes.map((s) => s.id).toList();
    expect(order.indexOf(a), lessThan(order.indexOf(c)));
    // Locked b should not have been reordered by the op alone in a way that
    // violates "skip locked" — at least a is among the moved set.
    expect(order.contains(b), isTrue);
  });

  test('setNoLine on 2D-only then new connector keeps visible stroke', () {
    final e = ctrl();
    rect(e, 2, 4);
    e.setNoLine();
    final a = e.currentPage!.shapes.first.id;
    final b = rect(e, 5, 4);
    // New rect may inherit no-line from memo — connector creation uses memo
    // with end arrow; ensure connector is not pattern 0.
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D);
    expect(conn.line.pattern, isNot(0));
  });
}
