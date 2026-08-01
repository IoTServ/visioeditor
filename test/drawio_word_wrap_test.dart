import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  EditorController controller() {
    final value = EditorController()..newDocument();
    addTearDown(value.dispose);
    return value;
  }

  int rectangle(
    EditorController value,
    double x,
    double y, {
    double width = 1.2,
  }) {
    value.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: cx,
        pinY: cy,
        width: width,
        height: 0.8,
      ),
      x,
      y,
    );
    return value.singleSelectedId!;
  }

  int line(EditorController value, double y) {
    value
      ..setTool(EditorTool.line)
      ..createShapeByDrag(1, y, 4, y);
    return value.singleSelectedId!;
  }

  test(
    'Word Wrap User row preserves metadata and survives VSDX round-trip',
    () {
      final value = controller();
      final id = rectangle(value, 2, 5);
      value.updateCurrentPage(
        (page) => page.updateShapeById(
          id,
          (shape) => shape.copyWith(
            userCells: const <VsdxUserCell>[
              VsdxUserCell(name: 'foreignMeta', value: 'keep'),
            ],
          ),
        ),
      );
      value.setWordWrap(false);

      final changed = value.currentPage!.findShapeById(id)!;
      expect(changed.wordWrap, isFalse);
      expect(
        changed.userCells
            .firstWhere((cell) => cell.name == 'foreignMeta')
            .value,
        'keep',
      );

      final reopened = const DocumentParser()
          .parse(value.exportToBytes())
          .pages
          .single;
      final shape = reopened.findShapeById(id)!;
      expect(shape.wordWrap, isFalse);
      expect(
        shape.userCells.firstWhere((cell) => cell.name == 'foreignMeta').value,
        'keep',
      );
    },
  );

  test('controller changes vertices only and undo restores wrapping', () {
    final value = controller();
    final vertex = rectangle(value, 2, 5);
    final edge = line(value, 3);
    value.setSelection([vertex, edge]);

    expect(value.canSetWordWrap, isTrue);
    expect(value.selectedWordWrap, isTrue);
    value.setWordWrap(false);
    expect(value.currentPage!.findShapeById(vertex)!.wordWrap, isFalse);
    expect(value.currentPage!.findShapeById(edge)!.wordWrap, isTrue);
    expect(value.selectedWordWrap, isFalse);

    value.undo();
    expect(value.currentPage!.findShapeById(vertex)!.wordWrap, isTrue);
    value.setSelection([edge]);
    expect(value.canSetWordWrap, isFalse);
  });

  test('vertex default style carries Word Wrap independently from edges', () {
    final value = controller();
    rectangle(value, 2, 5);
    value
      ..setWordWrap(false)
      ..setSelectionAsDefaultStyle();

    final inherited = rectangle(value, 5, 5);
    expect(value.currentPage!.findShapeById(inherited)!.wordWrap, isFalse);

    final edge = line(value, 3);
    expect(value.currentPage!.findShapeById(edge)!.wordWrap, isTrue);
    value.clearDefaultStyle();
    final reset = rectangle(value, 8, 5);
    expect(value.currentPage!.findShapeById(reset)!.wordWrap, isTrue);
  });

  test('Copy and Paste Style transfer Word Wrap between vertices', () {
    final value = controller();
    final source = rectangle(value, 2, 5);
    value
      ..setWordWrap(false)
      ..clearDefaultStyle()
      ..setSelection([source])
      ..copyStyle();
    final target = rectangle(value, 5, 5);
    expect(value.currentPage!.findShapeById(target)!.wordWrap, isTrue);

    value.pasteStyle();
    expect(value.currentPage!.findShapeById(target)!.wordWrap, isFalse);
  });

  test('SVG emits one natural-width line when Word Wrap is disabled', () {
    final value = controller();
    final id = rectangle(value, 2, 5, width: 0.7);
    value.setShapeText(id, 'one two three four five six seven');
    final wrapped = VsdxToSvgSerializer().serializePage(value.currentPage!);
    final wrappedLines = RegExp(r'<text\s').allMatches(wrapped).length;
    expect(wrappedLines, greaterThan(1));

    value.setWordWrap(false);
    final natural = VsdxToSvgSerializer().serializePage(value.currentPage!);
    expect(RegExp(r'<text\s').allMatches(natural).length, 1);
    expect(natural, contains('one two three four five six seven'));
  });
}
