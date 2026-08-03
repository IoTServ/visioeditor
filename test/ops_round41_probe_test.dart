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

  int rect(
    EditorController e,
    double x,
    double y, {
    double w = 1,
    double h = 0.6,
  }) {
    e.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: cx,
        pinY: cy,
        width: w,
        height: h,
      ),
      x,
      y,
    );
    return e.singleSelectedId!;
  }

  test('autosize fits wrapped text height and anchors page top-left', () {
    final e = ctrl();
    final id = rect(e, 4, 4, w: 2, h: 2);
    e.setShapeText(id, 'First line\nSecond line\nThird line');
    final before = e.currentPage!.shapePageAabb(id)!;

    expect(e.canAutosizeSelection, isTrue);
    e.autosizeSelection();

    final shape = e.currentPage!.findShapeById(id)!;
    final after = e.currentPage!.shapePageAabb(id)!;
    expect(shape.width, closeTo(2, 1e-9));
    expect(shape.height, greaterThan(2));
    expect(after.left, closeTo(before.left, 1e-6));
    expect(after.top, closeTo(before.top, 1e-6));

    e.undo();
    expect(e.currentPage!.findShapeById(id)!.height, closeTo(2, 1e-9));
  });

  test('autosize multiple shapes commits one undo step', () {
    final e = ctrl();
    final a = rect(e, 2, 4, w: 1.5, h: 1.5);
    e.setShapeText(a, 'Short');
    final b = rect(e, 6, 4, w: 1.5, h: 2);
    e.setShapeText(b, 'Line one\nLine two');
    e.setSelection(<int>[a, b]);

    e.autosizeSelection();
    expect(e.currentPage!.findShapeById(a)!.height, isNot(closeTo(1.5, 1e-9)));
    expect(e.currentPage!.findShapeById(b)!.height, isNot(closeTo(2, 1e-9)));

    e.undo();
    expect(e.currentPage!.findShapeById(a)!.height, closeTo(1.5, 1e-9));
    expect(e.currentPage!.findShapeById(b)!.height, closeTo(2, 1e-9));
  });

  test('autosize preserves relative libvisio bullet font size', () {
    final e = ctrl();
    final id = rect(e, 4, 4, w: 2, h: 1);
    final page = e.currentPage!;
    final shape = page.findShapeById(id)!;
    e.applyEdit(
      e.document!.replacePage(
        0,
        page.updateShapeById(
          id,
          (_) => shape.copyWith(
            text: 'Relative bullet',
            richText: const VsdxRichText(runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'Relative bullet',
                charStyle: VsdxCharStyle(fontSizeInches: 0.2),
                paraStyle: VsdxParaStyle(
                  bullet: 1,
                  bulletFontSizeInches: -0.5,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
    e.setSelection(<int>[id]);

    e.setAutosizeText(true);

    final para = e.currentPage!
        .findShapeById(id)!
        .richText
        .runs
        .single
        .paraStyle;
    expect(para.bulletFontSizeInches, -0.5);
  });

  test('replace shape preserves identity content style and connector glue', () {
    final e = ctrl();
    final source = rect(e, 2, 4, w: 2, h: 1);
    e.setShapeText(source, 'Keep me');
    e.setFillColor(const VsdxColor(0xFFE53935));
    e.rotateShape(source, 0.25);
    final target = rect(e, 7, 4);
    e.createConnector(2, 4, 7, 4, beginTarget: source, endTarget: target);
    final connector = e.singleSelectedId!;
    e.setSelection(<int>[source]);
    final before = e.currentPage!.findShapeById(source)!;

    expect(e.canReplaceSelectionShapes, isTrue);
    e.replaceSelectionWithBuilder(
      (id, cx, cy) => VsdxShapeFactory.ellipse(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 1,
        height: 1,
      ),
    );

    final page = e.currentPage!;
    final replaced = page.findShapeById(source)!;
    expect(replaced.id, source);
    expect(replaced.width, closeTo(before.width, 1e-9));
    expect(replaced.height, closeTo(before.height, 1e-9));
    expect(replaced.angleRad, closeTo(before.angleRad, 1e-9));
    expect(replaced.richText.plainText, 'Keep me');
    expect(replaced.fill.foreground, const VsdxColor(0xFFE53935));
    expect(
      replaced.geometries.first.commands.whereType<EllipseCmd>(),
      isNotEmpty,
    );
    expect(
      page.connects.any(
        (c) => c.fromSheetId == connector && c.toSheetId == source,
      ),
      isTrue,
    );

    e.undo();
    final restored = e.currentPage!.findShapeById(source)!;
    expect(restored.geometries.first.commands.whereType<EllipseCmd>(), isEmpty);
  });

  test('non-recursive group resize leaves children unchanged', () {
    final e = ctrl();
    final a = rect(e, 2, 4, w: 1.5, h: 0.8);
    final b = rect(e, 5, 4, w: 1, h: 1.2);
    e.setSelection(<int>[a, b]);
    e.groupSelection();
    final groupId = e.singleSelectedId!;
    final before = e.currentPage!.findShapeById(groupId)!;
    final beforeChildren = <int, (double, double, double, double)>{
      for (final child in before.children)
        child.id: (child.pinX, child.pinY, child.width, child.height),
    };

    e.resizeShape(
      groupId,
      pinX: before.pinX,
      pinY: before.pinY,
      width: before.width * 1.5,
      height: before.height * 1.5,
      resizeChildren: false,
    );

    final after = e.currentPage!.findShapeById(groupId)!;
    expect(after.width, closeTo(before.width * 1.5, 1e-9));
    expect(after.height, closeTo(before.height * 1.5, 1e-9));
    for (final child in after.children) {
      final original = beforeChildren[child.id]!;
      expect(child.pinX, closeTo(original.$1, 1e-9));
      expect(child.pinY, closeTo(original.$2, 1e-9));
      expect(child.width, closeTo(original.$3, 1e-9));
      expect(child.height, closeTo(original.$4, 1e-9));
    }

    e.undo();
    expect(
      e.currentPage!.findShapeById(groupId)!.width,
      closeTo(before.width, 1e-9),
    );
  });
}
