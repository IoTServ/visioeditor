import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  EditorController controllerWithTwoShapes() {
    final controller = EditorController()..newDocument();
    addTearDown(controller.dispose);
    controller
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 3, 2);
    controller
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(4, 1, 6, 2);
    return controller;
  }

  test('Paste Text Style preserves shape appearance, label, and text geometry',
      () {
    final controller = controllerWithTwoShapes();
    final source = controller.currentPage!.shapes.first.id;
    final target = controller.currentPage!.shapes.last.id;

    controller
      ..selectOnly(source)
      ..setShapeText(source, 'Source')
      ..setFontFamily('Courier New')
      ..setTextSizeInches(18 / 72)
      ..setBold(true)
      ..setItalic(true)
      ..setUnderline(true)
      ..setTextColor(const VsdxColor(0xFF123456))
      ..setTextAlign(VsdxHorzAlign.right)
      ..setTextVerticalAlign(VsdxVertAlign.bottom)
      ..setVerticalText(true);
    controller.updateCurrentPage(
      (page) => page.updateShapeById(
        source,
        (shape) => shape.copyWith(
          richText: shape.richText.copyWith(
            textBlock: shape.richText.textBlock.copyWith(
              marginLeftInches: 0.11,
              marginRightInches: 0.12,
              marginTopInches: 0.13,
              marginBottomInches: 0.14,
              backgroundColor: const VsdxColor(0xFFFFFF00),
              backgroundTransparency: 0.25,
            ),
          ),
        ),
      ),
    );
    controller.copyTextStyle();
    expect(controller.hasTextStyleClipboard, isTrue);

    controller
      ..selectOnly(target)
      ..setShapeText(target, 'Target')
      ..setFillColor(const VsdxColor(0xFF00AA00))
      ..setLineColor(const VsdxColor(0xFFAA0000));
    controller.updateCurrentPage(
      (page) => page.updateShapeById(
        target,
        (shape) => shape.copyWith(
          richText: shape.richText.copyWith(
            textBlock: shape.richText.textBlock.copyWith(
              pinXInches: 0.7,
              pinYInches: 0.4,
              angleRad: 0.3,
            ),
          ),
        ),
      ),
    );
    final before = controller.currentPage!.findShapeById(target)!;

    controller.pasteTextStyle();
    final pasted = controller.currentPage!.findShapeById(target)!;

    expect(pasted.richText.plainText, 'Target');
    expect(pasted.fill.foreground?.value, before.fill.foreground?.value);
    expect(pasted.line.color?.value, before.line.color?.value);
    expect(pasted.richText.textBlock.pinXInches, 0.7);
    expect(pasted.richText.textBlock.pinYInches, 0.4);
    expect(pasted.richText.textBlock.angleRad, 0.3);
    expect(pasted.richText.textBlock.marginLeftInches, 0.11);
    expect(pasted.richText.textBlock.marginRightInches, 0.12);
    expect(pasted.richText.textBlock.marginTopInches, 0.13);
    expect(pasted.richText.textBlock.marginBottomInches, 0.14);
    expect(pasted.richText.textBlock.verticalAlign, VsdxVertAlign.bottom);
    expect(pasted.richText.textBlock.textDirection, 1);
    expect(pasted.richText.textBlock.backgroundColor?.value, 0xFFFFFF00);
    expect(pasted.richText.textBlock.backgroundTransparency, 0.25);
    final style = pasted.richText.runs.first;
    expect(style.charStyle.fontFamily, 'Courier New');
    expect(style.charStyle.fontSizeInches, closeTo(18 / 72, 1e-9));
    expect(style.charStyle.style.bold, isTrue);
    expect(style.charStyle.style.italic, isTrue);
    expect(style.charStyle.underline, isTrue);
    expect(style.charStyle.color?.value, 0xFF123456);
    expect(style.paraStyle.horizontalAlign, VsdxHorzAlign.right);

    controller.undo();
    final restored = controller.currentPage!.findShapeById(target)!;
    expect(restored.richText.plainText, 'Target');
    expect(restored.richText.textBlock.marginLeftInches,
        before.richText.textBlock.marginLeftInches);
    expect(restored.richText.runs.first.charStyle.fontFamily,
        before.richText.runs.first.charStyle.fontFamily);
  });

  test('Paste Text Style reaches group descendants and skips locked parts', () {
    final controller = controllerWithTwoShapes();
    final ids = controller.currentPage!.shapes.map((shape) => shape.id).toList();
    controller
      ..selectOnly(ids.first)
      ..setShapeText(ids.first, 'Source')
      ..setBold(true)
      ..copyTextStyle();

    controller.selectOnly(ids.last);
    controller
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(7, 1, 9, 2);
    final third = controller.singleSelectedId!;
    controller.setSelection(<int>{ids.last, third});
    controller.groupSelection();
    final group = controller.singleSelectedId!;
    final children = controller.currentPage!.findShapeById(group)!.children;
    final lockedChild = children.first.id;
    final editableChild = children.last.id;
    controller.updateCurrentPage(
      (page) => page.updateShapeById(
        lockedChild,
        (shape) => shape.copyWith(locked: true),
      ),
    );

    controller.pasteTextStyle();

    final pastedGroup = controller.currentPage!.findShapeById(group)!;
    expect(pastedGroup.richText.runs.first.charStyle.style.bold, isTrue);
    expect(
      controller
          .currentPage!
          .findShapeById(editableChild)!
          .richText
          .runs
          .first
          .charStyle
          .style
          .bold,
      isTrue,
    );
    expect(
      controller.currentPage!.findShapeById(lockedChild)!.richText.runs,
      isEmpty,
    );
  });

  test('Copy Text Style requires one selected shape', () {
    final controller = controllerWithTwoShapes();
    controller.selectAll();

    expect(controller.canCopyTextStyle, isFalse);
    controller.copyTextStyle();
    expect(controller.hasTextStyleClipboard, isFalse);
  });
}
