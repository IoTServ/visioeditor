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
      {double w = 1, double h = 0.6}) {
    e.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id, pinX: cx, pinY: cy, width: w, height: h),
        x,
        y);
    return e.singleSelectedId!;
  }

  test('softEdges on 1D does not pollute memo for new 2D shapes', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setSelection([conn]);
    e.setSoftEdges(true);
    final c = rect(e, 3, 2);
    expect(e.currentPage!.findShapeById(c)!.line.softEdgesInches, 0);
  });

  test('setFillColor on 1D is ignored', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    final before = e.currentPage!.findShapeById(conn)!.fill.pattern;
    e.setSelection([conn]);
    e.setFillColor(const VsdxColor(0xFFFF0000));
    expect(e.currentPage!.findShapeById(conn)!.fill.pattern, before);
  });

  test('page background undo restores color and dirty', () {
    final e = ctrl();
    final bytes = e.exportToBytes();
    e.markSaved(bytes);
    e.setBackgroundColor(const VsdxColor(0xFFFF0000));
    expect(e.pageBackgroundColor?.value, 0xFFFF0000);
    e.undo();
    expect(e.pageBackgroundColor, isNull);
    expect(e.isDirty, isFalse);
  });

  test('setPageSize undo works', () {
    final e = ctrl();
    e.setPageSize(10, 7);
    expect(e.pageSize!.width, 10);
    e.undo();
    expect(e.pageSize!.width, 11);
  });

  test('multi-select bold applies to all with text', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.setShapeText(a, 'A');
    e.setShapeText(b, 'B');
    e.setSelection([a, b]);
    e.setBold(true);
    expect(
      e.currentPage!.findShapeById(a)!.richText.runs.first.charStyle.style.bold,
      isTrue,
    );
    expect(
      e.currentPage!.findShapeById(b)!.richText.runs.first.charStyle.style.bold,
      isTrue,
    );
  });

  test('find wholeWord with punctuation boundaries', () {
    final out = EditorController.replaceAllMatch(
      'foo, foo.',
      'foo',
      'X',
      matchCase: true,
      wholeWord: true,
    );
    expect(out, 'X, X.');
  });

  test('replaceAll when replacement contains query does not loop', () {
    final out = EditorController.replaceAllMatch(
      'aa',
      'a',
      'aa',
      matchCase: true,
    );
    expect(out, 'aaaa');
  });
}
