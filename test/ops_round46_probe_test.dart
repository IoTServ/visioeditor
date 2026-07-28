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

  VsdxShape rectangle(int id, double x, double y) => VsdxShapeFactory.rectangle(
    id: id,
    pinX: x,
    pinY: y,
    width: 1.5,
    height: 1,
  );

  VsdxShape ellipse(int id, double x, double y) =>
      VsdxShapeFactory.ellipse(id: id, pinX: x, pinY: y, width: 1, height: 1);

  int addRect(EditorController e, double x, double y) {
    e.addShapeFromBuilderAt(rectangle, x, y);
    return e.singleSelectedId!;
  }

  test('palette click attaches a shape to selected connector free end', () {
    final e = ctrl();
    final source = addRect(e, 2, 4);
    e.createConnector(2, 4, 7, 4, beginTarget: source);
    final connector = e.singleSelectedId!;

    expect(e.canAttachShapeToSelectionConnector, isTrue);
    expect(e.attachShapeToSelectionConnector(ellipse), isTrue);

    final attached = e.singleSelectedId!;
    expect(e.currentPage!.findShapeById(attached)!.is1D, isFalse);
    final gluedTargets = e.currentPage!.connects
        .where((row) => row.fromSheetId == connector)
        .map((row) => row.toSheetId)
        .toSet();
    expect(gluedTargets, equals(<int>{source, attached}));
    expect(e.canAttachShapeToSelectionConnector, isFalse);

    e.undo();
    expect(e.currentPage!.findShapeById(attached), isNull);
    expect(e.singleSelectedId, connector);
    expect(e.canAttachShapeToSelectionConnector, isTrue);
  });

  test('palette attachment rejects a 1-D stencil without editing', () {
    final e = ctrl();
    final source = addRect(e, 2, 4);
    e.createConnector(2, 4, 7, 4, beginTarget: source);
    final before = e.currentPage!;

    final attached = e.attachShapeToSelectionConnector(
      (id, x, y) =>
          VsdxShapeFactory.line(id: id, ax: x, ay: y, bx: x + 1, by: y),
    );

    expect(attached, isFalse);
    expect(e.currentPage, same(before));
  });

  test('palette drop replaces the hit shape and selects it', () {
    final e = ctrl();
    final target = addRect(e, 3, 4);
    e.setShapeText(target, 'Preserved');
    final other = addRect(e, 7, 4);
    expect(e.singleSelectedId, other);

    expect(e.canReplaceShape(target), isTrue);
    expect(e.replaceShapeWithBuilder(target, ellipse), isTrue);

    final replaced = e.currentPage!.findShapeById(target)!;
    expect(replaced.richText.plainText, 'Preserved');
    expect(
      replaced.geometries.first.commands.whereType<EllipseCmd>(),
      isNotEmpty,
    );
    expect(e.singleSelectedId, target);

    e.undo();
    expect(
      e.currentPage!
          .findShapeById(target)!
          .geometries
          .first
          .commands
          .whereType<EllipseCmd>(),
      isEmpty,
    );
    expect(e.singleSelectedId, other);
  });

  test('drop on one selected shape replaces the compatible selection', () {
    final e = ctrl();
    final first = addRect(e, 3, 4);
    final second = addRect(e, 7, 4);
    e.setSelection(<int>[first, second]);

    expect(e.replaceShapeWithBuilder(first, ellipse), isTrue);

    for (final id in <int>[first, second]) {
      expect(
        e.currentPage!
            .findShapeById(id)!
            .geometries
            .first
            .commands
            .whereType<EllipseCmd>(),
        isNotEmpty,
      );
    }
    expect(e.selection, equals(<int>{first, second}));
  });
}
