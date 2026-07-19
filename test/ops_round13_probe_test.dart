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

  test('undo to saved baseline clears dirty', () {
    final e = ctrl();
    final bytes = e.exportToBytes();
    e.markSaved(bytes);
    expect(e.isDirty, isFalse);
    final a = rect(e, 2, 4);
    expect(e.isDirty, isTrue);
    e.undo();
    expect(e.currentPage!.findShapeById(a), isNull);
    expect(e.isDirty, isFalse);
  });

  test('renamePageAt disambiguates duplicate page names', () {
    final e = ctrl();
    e.addPage();
    e.renamePageAt(1, 'Page-1');
    final names = e.document!.pages.map((p) => p.name).toList();
    expect(names.toSet().length, names.length);
  });

  test('setBold on empty-text shape seeds style for later typing', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setBold(true);
    e.setShapeText(a, 'later');
    final run = e.currentPage!.findShapeById(a)!.richText.runs.first;
    expect(run.charStyle.style.bold, isTrue);
  });

  test('selectedCharStyle exposes defaults when shape has no Character runs',
      () {
    final e = ctrl();
    // Fresh stencil shape: painted via empty label / plain text, no rich runs.
    rect(e, 2, 4);
    expect(e.currentPage!.shapes.first.richText.runs, isEmpty);
    expect(e.selectedCharStyle, isNotNull);
    expect(e.selectedParaStyle, isNotNull);
    expect(e.selectedAlign, VsdxHorzAlign.left);

    // textBox keeps label in `text` without seeding Character runs — Format
    // Text must still appear (draw.io always shows the Text panel).
    e.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.textBox(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 2,
        height: 0.5,
        text: 'hello',
      ),
      4,
      4,
    );
    final box = e.singleSelectedId!;
    expect(e.currentPage!.findShapeById(box)!.richText.runs, isEmpty);
    expect(e.selectedCharStyle, isNotNull);
    e.setBold(true);
    expect(
      e.currentPage!.findShapeById(box)!.richText.runs.first.charStyle.style.bold,
      isTrue,
    );
  });

  test('setTextThemeSlot is one undo when theme missing', () {
    final e = ctrl();
    final a = rect(e, 2, 4, text: 'hi');
    expect(e.document!.theme.isEmpty, isTrue);
    e.setTextThemeSlot(0);
    e.undo();
    expect(e.document!.theme.isEmpty, isTrue);
    final textSlot = e.currentPage!
        .findShapeById(a)!
        .richText
        .runs
        .first
        .charStyle
        .themeColorIndex;
    expect(textSlot, isNull);
  });

  test('setNoFill on mixed 1D+2D skips connector fill', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    final connFillBefore = e.currentPage!.findShapeById(conn)!.fill.pattern;
    e.setSelection([a, conn]);
    e.setFillColor(const VsdxColor(0xFFFF0000));
    e.setNoFill();
    expect(e.currentPage!.findShapeById(a)!.fill.pattern, 0);
    expect(e.currentPage!.findShapeById(conn)!.fill.pattern, connFillBefore);
  });

  test('setShadow skips 1D connectors', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setSelection([conn]);
    e.setShadow(true);
    expect(e.currentPage!.findShapeById(conn)!.shadow.enabled, isFalse);
  });

  test('setSoftEdges skips 1D', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setSelection([conn]);
    e.setSoftEdges(true);
    expect(e.currentPage!.findShapeById(conn)!.line.softEdgesInches, 0);
  });

  test('toggleCollapsed detaches glue to hidden children', () {
    final e = ctrl();
    final page0 = e.currentPage!;
    final box = VsdxShapeFactory.container(
      id: page0.nextFreeShapeId(),
      pinX: 4,
      pinY: 4,
      width: 4,
      height: 3,
    );
    e.updateCurrentPage((p) => p.addShape(box));
    final childId = e.currentPage!.nextFreeShapeId();
    final child = VsdxShapeFactory.rectangle(
      id: childId,
      pinX: 4,
      pinY: 3.5,
      width: 1,
      height: 0.8,
    );
    e.updateCurrentPage((p) => p.addShape(child).reparentShape(childId, box.id));
    final other = rect(e, 8, 4);
    e.createConnector(4, 3.5, 8, 4, beginTarget: childId, endTarget: other);
    final connBefore = e.currentPage!.shapes.lastWhere((s) => s.is1D);
    e.toggleCollapsed(box.id);
    final gluedAfter = e.currentPage!.connects
        .where((c) => c.fromSheetId == connBefore.id)
        .map((c) => c.toSheetId)
        .toSet();
    expect(e.isCollapsed(box.id), isTrue);
    expect(gluedAfter.contains(childId), isFalse);
    final folded = e.currentPage!.findShapeById(connBefore.id)!;
    expect(folded.formulas.containsKey('BegTrigger'), isFalse);
    expect(folded.formulas['EndTrigger'], contains('Sheet.$other!'));
    e.toggleCollapsed(box.id); // unfold
    final unfolded = e.currentPage!.findShapeById(connBefore.id)!;
    expect(unfolded.formulas['BegTrigger'], contains('Sheet.$childId!'));
  });

  test('reparentSelectionInto into self-descendant is no-op', () {
    final e = ctrl();
    final page0 = e.currentPage!;
    final outer = VsdxShapeFactory.container(
      id: page0.nextFreeShapeId(),
      pinX: 4,
      pinY: 4,
      width: 4,
      height: 3,
    );
    e.updateCurrentPage((p) => p.addShape(outer));
    final innerId = e.currentPage!.nextFreeShapeId();
    final inner = VsdxShapeFactory.container(
      id: innerId,
      pinX: 4,
      pinY: 3.5,
      width: 2,
      height: 1.5,
    );
    e.updateCurrentPage((p) => p.addShape(inner).reparentShape(innerId, outer.id));
    e.setSelection([outer.id]);
    e.reparentSelectionInto(innerId);
    expect(e.currentPage!.findParentId(outer.id), isNull);
  });

  test('reparentSelectionInto skips locked shapes', () {
    final e = ctrl();
    final page0 = e.currentPage!;
    final box = VsdxShapeFactory.container(
      id: page0.nextFreeShapeId(),
      pinX: 4,
      pinY: 4,
      width: 4,
      height: 3,
    );
    e.updateCurrentPage((p) => p.addShape(box));
    final child = rect(e, 1, 1);
    e.setSelectionLocked(true);
    e.setSelection([child]);
    e.reparentSelectionInto(box.id);
    expect(e.currentPage!.findParentId(child), isNull);
  });

  test('replaceFirstMatch index with Turkish İ length change', () {
    const source = 'İstanbul';
    const query = 'İ';
    final out = EditorController.replaceFirstMatch(
      source,
      query,
      'X',
      matchCase: false,
    );
    expect(out.startsWith('X'), isTrue);
  });

  test('wholeWord replace does not match inside larger token', () {
    final out = EditorController.replaceAllMatch(
      'foobar foo',
      'foo',
      'X',
      matchCase: true,
      wholeWord: true,
    );
    expect(out, 'foobar X');
  });

  test('nudge locked-only selection creates no extra undo', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setSelectionLocked(true);
    final pin = e.currentPage!.findShapeById(a)!.pinX;
    e.moveSelectionBy(0.5, 0);
    expect(e.currentPage!.findShapeById(a)!.pinX, pin);
    // Top undo is lock, not a phantom nudge — shape stays after one undo.
    e.undo();
    expect(e.currentPage!.findShapeById(a), isNotNull);
    expect(e.currentPage!.findShapeById(a)!.locked, isFalse);
  });

  test('nudge mixed locked moves unlocked only', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.setSelection([a]);
    e.setSelectionLocked(true);
    e.setSelection([a, b]);
    final ax = e.currentPage!.findShapeById(a)!.pinX;
    final bx = e.currentPage!.findShapeById(b)!.pinX;
    e.moveSelectionBy(0.5, 0);
    expect(e.currentPage!.findShapeById(a)!.pinX, ax);
    expect(e.currentPage!.findShapeById(b)!.pinX, closeTo(bx + 0.5, 1e-9));
  });
}
