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

  int rect(EditorController e, double x, double y, {String? text}) {
    e.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 1.5,
        height: 1,
      ),
      x,
      y,
    );
    final id = e.singleSelectedId!;
    if (text != null) e.setShapeText(id, text);
    return id;
  }

  test('deleteSelection can include incident connectors and undo', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final connector = e.singleSelectedId!;

    e.setSelection([a]);
    e.deleteSelection(includeConnected: true);

    expect(e.currentPage!.findShapeById(a), isNull);
    expect(e.currentPage!.findShapeById(b), isNotNull);
    expect(e.currentPage!.findShapeById(connector), isNull);
    expect(e.currentPage!.connects, isEmpty);

    e.undo();
    expect(e.currentPage!.findShapeById(a), isNotNull);
    expect(e.currentPage!.findShapeById(connector), isNotNull);
    expect(e.currentPage!.connects, hasLength(2));
  });

  test('plain delete still keeps an incident connector floating', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final connector = e.singleSelectedId!;

    e.setSelection([a]);
    e.deleteSelection();

    expect(e.currentPage!.findShapeById(a), isNull);
    expect(e.currentPage!.findShapeById(connector), isNotNull);
    expect(e.currentPage!.connects.any((row) => row.toSheetId == a), isFalse);
  });

  test('whole-label size adjustment preserves relative rich-text sizes', () {
    final e = ctrl();
    final id = rect(e, 2, 4);
    e.updateCurrentPage(
      (page) => page.updateShapeById(
        id,
        (shape) => shape.copyWith(
          text: 'Big small',
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'Big ',
                charStyle: VsdxCharStyle(fontSizeInches: 20 / 72),
              ),
              VsdxTextRun(
                text: 'small',
                charStyle: VsdxCharStyle(fontSizeInches: 10 / 72),
              ),
            ],
          ),
        ),
      ),
    );

    e.setTextEditSession(shapeId: id, start: 0, end: 3);
    e.adjustWholeLabelTextSizePoints(1);

    final runs = e.currentPage!.findShapeById(id)!.richText.runs;
    expect(runs[0].charStyle.fontSizeInches * 72, closeTo(21, 1e-9));
    expect(runs[1].charStyle.fontSizeInches * 72, closeTo(11, 1e-9));
    e.undo();
    final restored = e.currentPage!.findShapeById(id)!.richText.runs;
    expect(restored[0].charStyle.fontSizeInches * 72, closeTo(20, 1e-9));
    expect(restored[1].charStyle.fontSizeInches * 72, closeTo(10, 1e-9));
  });

  test('set and clear default creation style do not dirty the document', () {
    final e = ctrl();
    final source = rect(e, 2, 4);
    e.updateCurrentPage(
      (page) => page.updateShapeById(
        source,
        (shape) => shape.copyWith(
          fill: const VsdxFill(foreground: VsdxColor(0xFF2266CC)),
          line: shape.line.copyWith(weightInches: 3 / 72),
        ),
      ),
    );

    e.setSelection([source]);
    final dirtyBeforeSet = e.isDirty;
    e.setSelectionAsDefaultStyle();
    expect(e.isDirty, dirtyBeforeSet);
    final styled = rect(e, 5, 4);
    expect(
      e.currentPage!.findShapeById(styled)!.fill.foreground,
      const VsdxColor(0xFF2266CC),
    );
    expect(
      e.currentPage!.findShapeById(styled)!.line.weightInches,
      closeTo(3 / 72, 1e-9),
    );

    e.clearSelection();
    final dirtyBeforeClear = e.isDirty;
    e.clearDefaultStyle();
    expect(e.isDirty, dirtyBeforeClear);
    final reset = rect(e, 8, 4);
    expect(
      e.currentPage!.findShapeById(reset)!.fill.foreground,
      VsdxColor.white,
    );
    expect(
      e.currentPage!.findShapeById(reset)!.line.weightInches,
      closeTo(0.01, 1e-9),
    );
  });
}
