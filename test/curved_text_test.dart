import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  group('VsdxShape.curvedText', () {
    test('withCurvedText round-trips via User.veCurvedText', () {
      final box = VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 2,
        pinY: 2,
        width: 2,
        height: 1,
      );
      expect(box.curvedText, isFalse);
      final curved = box.withCurvedText(true);
      expect(curved.curvedText, isTrue);
      expect(
        curved.userCells.any((c) => c.name == VsdxShape.userCurvedText),
        isTrue,
      );
      expect(curved.withCurvedText(false).curvedText, isFalse);
    });

    test('User.veCurvedText survives writer round-trip', () {
      const writer = VsdxWriter();
      const parser = DocumentParser();
      final blank = writer.emptyDocument();
      var doc = parser.parse(blank);
      var page = doc.pages.first;
      final id = page.nextFreeShapeId();
      page = page.addShape(
        VsdxShapeFactory.rectangle(
              id: id,
              pinX: 2,
              pinY: 2,
              width: 2,
              height: 1,
              name: 'Arc',
            )
            .withCurvedText(true)
            .copyWith(
              richText: const VsdxRichText(
                runs: <VsdxTextRun>[VsdxTextRun(text: 'Hello')],
              ),
            ),
      );
      doc = doc.replacePage(0, page);
      final after = parser.parse(
        writer.write(originalBytes: blank, edited: doc),
      );
      final shape = after.pages.first.findShapeById(id)!;
      expect(shape.curvedText, isFalse);
      expect(shape.richText.textBlock.hideText, isTrue);
      expect(shape.richText.plainText, 'Hello');
      final plates = after.pages.first.shapes
          .where(isLibvisioCurvedTextPlate)
          .toList(growable: false);
      expect(plates, hasLength(5));
      expect(plates.map((s) => s.richText.plainText).join(), 'Hello');
    });
  });

  group('EditorController Curved Text', () {
    test('setCurvedText toggles selection and undoes', () {
      final c = EditorController()..newDocument();
      final id = c.currentPage!.nextFreeShapeId();
      c.updateCurrentPage(
        (p) => p.addShape(
          VsdxShapeFactory.rectangle(
            id: id,
            pinX: 2,
            pinY: 2,
            width: 2,
            height: 1,
          ),
        ),
      );
      c.selectOnly(id);
      expect(c.selectedCurvedText, isFalse);
      c.setCurvedText(true);
      expect(c.selectedCurvedText, isTrue);
      expect(c.currentPage!.findShapeById(id)!.curvedText, isTrue);
      c.undo();
      expect(c.currentPage!.findShapeById(id)!.curvedText, isFalse);
    });
  });
}
