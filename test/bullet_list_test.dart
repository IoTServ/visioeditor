import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  group('EditorController bullets', () {
    test('setBullet enables hanging indent defaults and undoes', () {
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
          ).copyWith(
            richText: const VsdxRichText(
              runs: <VsdxTextRun>[
                VsdxTextRun(text: 'Item one'),
              ],
            ),
          ),
        ),
      );
      c.selectOnly(id);
      expect(c.selectedHasBullet, isFalse);

      c.setBullet(true);
      final style = c.selectedParaStyle!;
      expect(style.bullet, 1);
      expect(style.bulletStr, '•');
      expect(style.indentLeftInches, greaterThan(0));
      expect(style.textPosAfterBulletInches, greaterThan(0));
      expect(c.selectedHasBullet, isTrue);

      c.setBullet(false);
      expect(c.selectedParaStyle!.bullet, 0);
      expect(c.selectedHasBullet, isFalse);

      c.undo(); // back to bullets on
      expect(c.selectedParaStyle!.bullet, 1);
    });
  });

  test('Bullet / IndLeft survive writer round-trip after setBullet', () {
    final c = EditorController()..newDocument();
    final id = c.currentPage!.nextFreeShapeId();
    c.updateCurrentPage(
      (p) => p.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 2.5,
          height: 1.2,
        ).copyWith(
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(text: 'Alpha\nBeta'),
            ],
          ),
        ),
      ),
    );
    c.selectOnly(id);
    c.setBullet(true);

    final bytes = c.exportToBytes();
    final reopened = const DocumentParser().parse(bytes);
    final style = reopened.pages.first.findShapeById(id)!.richText.runs.first.paraStyle;
    expect(style.bullet, 1);
    expect(style.bulletStr, '•');
    expect(style.indentLeftInches, closeTo(0.2, 1e-6));
  });
}
