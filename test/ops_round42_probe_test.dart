import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  EditorController ctrl() {
    final c = EditorController()
      ..newDocument(widthInches: 11, heightInches: 8.5);
    addTearDown(c.dispose);
    return c;
  }

  int rect(EditorController e, double x, double y) {
    e.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 2,
        height: 1,
      ),
      x,
      y,
    );
    final id = e.singleSelectedId!;
    e.setShapeText(id, 'Label');
    return id;
  }

  test('label positions use edge-pinned Visio text blocks and undo', () {
    final e = ctrl();
    final id = rect(e, 3, 4);

    e.setTextLabelPosition(TextLabelPosition.top);
    var shape = e.currentPage!.findShapeById(id)!;
    var block = shape.richText.textBlock;
    expect(e.selectedTextLabelPosition, TextLabelPosition.top);
    expect(block.pinXInches, closeTo(1, 1e-9));
    expect(block.pinYInches, closeTo(1, 1e-9));
    expect(block.locPinXInches, closeTo(1, 1e-9));
    expect(block.locPinYInches, closeTo(0, 1e-9));
    expect(block.verticalAlign, VsdxVertAlign.bottom);
    expect(
      shape.richText.runs.first.paraStyle.horizontalAlign,
      VsdxHorzAlign.center,
    );

    e.setTextLabelPosition(TextLabelPosition.right);
    shape = e.currentPage!.findShapeById(id)!;
    block = shape.richText.textBlock;
    expect(e.selectedTextLabelPosition, TextLabelPosition.right);
    expect(block.pinXInches, closeTo(2, 1e-9));
    expect(block.locPinXInches, closeTo(0, 1e-9));
    expect(
      shape.richText.runs.first.paraStyle.horizontalAlign,
      VsdxHorzAlign.left,
    );

    e.undo();
    expect(e.selectedTextLabelPosition, TextLabelPosition.top);
  });

  test('label position and vertical text round-trip through vsdx', () {
    const writer = VsdxWriter();
    const parser = DocumentParser();
    final e = ctrl();
    final id = rect(e, 3, 4);
    e
      ..setTextLabelPosition(TextLabelPosition.bottom)
      ..setVerticalText(true);

    final blank = writer.emptyDocument(widthInches: 11, heightInches: 8.5);
    final reopened = parser.parse(
      writer.write(originalBytes: blank, edited: e.document!),
    );
    final block = reopened.pages.first.findShapeById(id)!.richText.textBlock;
    expect(block.pinXInches, closeTo(1, 1e-6));
    expect(block.pinYInches, closeTo(0, 1e-6));
    expect(block.locPinXInches, closeTo(1, 1e-6));
    expect(block.locPinYInches, closeTo(1, 1e-6));
    expect(block.verticalAlign, VsdxVertAlign.top);
    expect(block.textDirection, 1);
  });

  test('label position applies to multiple shapes as one undo step', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 6, 4);
    e.setSelection(<int>[a, b]);

    e.setTextLabelPosition(TextLabelPosition.left);
    for (final id in <int>[a, b]) {
      final shape = e.currentPage!.findShapeById(id)!;
      expect(shape.richText.textBlock.pinXInches, closeTo(0, 1e-9));
      expect(shape.richText.textBlock.locPinXInches, closeTo(2, 1e-9));
    }

    e.undo();
    for (final id in <int>[a, b]) {
      expect(
        e.currentPage!.findShapeById(id)!.richText.textBlock.pinXInches,
        isNull,
      );
    }
  });

  test('label position seeds alignment before the shape has text', () {
    final e = ctrl();
    e.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 2,
        height: 1,
      ),
      3,
      4,
    );
    final id = e.singleSelectedId!;

    e
      ..setTextLabelPosition(TextLabelPosition.left)
      ..setShapeText(id, 'Later');

    final run = e.currentPage!.findShapeById(id)!.richText.runs.first;
    expect(run.text, 'Later');
    expect(run.paraStyle.horizontalAlign, VsdxHorzAlign.right);
  });
}
