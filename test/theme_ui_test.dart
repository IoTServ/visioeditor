import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  test('setFillThemeSlot binds theme index and installs Office theme', () {
    final c = EditorController()..newDocument();
    expect(c.documentTheme.isEmpty, isTrue);

    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 2, 2);
    final id = c.selection.single;
    c.setFillThemeSlot(ThemeSlot.accent1);

    expect(c.documentTheme.isEmpty, isFalse);
    expect(c.documentTheme.resolve(ThemeSlot.accent1), isNotNull);
    final fill = c.currentPage!.findShapeById(id)!.fill;
    expect(fill.foreground, isNull);
    expect(fill.themeForegroundIndex, ThemeSlot.accent1);
    expect(fill.pattern, isNot(0));
  });

  test('setLineThemeSlot clears solid colour', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 2, 2)
      ..setLineColor(const VsdxColor(0xFFFF0000))
      ..setLineThemeSlot(ThemeSlot.accent2);
    final line = c.currentPage!.shapes.single.line;
    expect(line.color, isNull);
    expect(line.themeColorIndex, ThemeSlot.accent2);
  });

  test('setDocumentTheme switches builtin palettes', () {
    final c = EditorController()..newDocument();
    c.setDocumentTheme(VsdxTheme.green);
    expect(
      c.documentTheme.resolve(ThemeSlot.accent1)?.value,
      VsdxTheme.green.resolve(ThemeSlot.accent1)!.value,
    );
    c.setDocumentTheme(VsdxTheme.blue);
    expect(
      c.documentTheme.resolve(ThemeSlot.accent1)?.value,
      VsdxTheme.blue.resolve(ThemeSlot.accent1)!.value,
    );
  });

  test('solid fill clears a previous theme binding', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 2, 2)
      ..setFillThemeSlot(ThemeSlot.accent1)
      ..setFillColor(const VsdxColor(0xFF00FF00));
    final fill = c.currentPage!.shapes.single.fill;
    expect(fill.foreground?.value, 0xFF00FF00);
    expect(fill.themeForegroundIndex, isNull);
  });

  test('solid fill clears stale hatch FillBkgnd theme', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 2, 2)
      ..setFillPattern(2)
      ..setFillBackgroundThemeSlot(ThemeSlot.accent2)
      ..setFillPattern(1)
      ..setFillColor(const VsdxColor(0xFF112233));
    final fill = c.currentPage!.shapes.single.fill;
    expect(fill.themeBackgroundIndex, isNull);
    expect(fill.pattern, 1);
  });

  test('setFillOpacity mirrors FillBkgndTrans on hatch', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 2, 2)
      ..setFillPattern(2)
      ..setFillOpacity(0.4);
    final fill = c.currentPage!.shapes.single.fill;
    expect(fill.foregroundTransparency, closeTo(0.6, 1e-9));
    expect(fill.backgroundTransparency, closeTo(0.6, 1e-9));
  });

  test('setFillBackground enables hatch and clears bg theme', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 2, 2)
      ..setFillBackgroundThemeSlot(ThemeSlot.accent3)
      ..setFillBackground(const VsdxColor(0xFFFFCC00));
    final fill = c.currentPage!.shapes.single.fill;
    expect(fill.pattern, greaterThan(1));
    expect(fill.background?.value, 0xFFFFCC00);
    expect(fill.themeBackgroundIndex, isNull);
  });

  test('setNoFill clears hatch FillBkgnd theme so it cannot revive', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 2, 2)
      ..setFillPattern(2)
      ..setFillBackgroundThemeSlot(ThemeSlot.accent2)
      ..setNoFill()
      ..setFillPattern(2);
    final fill = c.currentPage!.shapes.single.fill;
    expect(fill.pattern, 2);
    expect(fill.themeBackgroundIndex, isNull);
    expect(fill.themeForegroundIndex, isNull);
  });

  test('setNoFill / setNoLine sync Geometry NoFill / NoLine', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 2, 2)
      ..setNoFill()
      ..setNoLine();
    final s = c.currentPage!.shapes.single;
    expect(s.fill.pattern, 0);
    expect(s.line.pattern, 0);
    expect(s.geometries, isNotEmpty);
    expect(s.geometries.every((g) => g.noFill), isTrue);
    expect(s.geometries.every((g) => g.noLine), isTrue);
    c
      ..setFillColor(const VsdxColor(0xFFFF0000))
      ..setLineColor(const VsdxColor(0xFF0000FF));
    final restored = c.currentPage!.shapes.single;
    expect(restored.geometries.every((g) => !g.noFill), isTrue);
    expect(restored.geometries.every((g) => !g.noLine), isTrue);
  });

  test('setFillThemeSlot after setNoFill clears Geometry noFill', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 2, 2)
      ..setNoFill()
      ..setFillThemeSlot(ThemeSlot.accent1);
    final s = c.currentPage!.shapes.single;
    expect(s.fill.themeForegroundIndex, ThemeSlot.accent1);
    expect(s.fill.pattern, isNonZero);
    expect(s.geometries.every((g) => !g.noFill), isTrue);
  });

  test('setFillPattern(0) clears foreground theme like setNoFill', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 2, 2)
      ..setFillThemeSlot(ThemeSlot.accent1)
      ..setFillPattern(0)
      ..setFillPattern(2);
    final fill = c.currentPage!.shapes.single.fill;
    expect(fill.pattern, 2);
    expect(fill.themeForegroundIndex, isNull);
  });

  test('setNoLine clears line theme so it cannot revive', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 2, 2)
      ..setLineThemeSlot(ThemeSlot.accent2)
      ..setNoLine()
      ..setLinePattern(1);
    final line = c.currentPage!.shapes.single.line;
    expect(line.pattern, 1);
    expect(line.themeColorIndex, isNull);
  });
}
