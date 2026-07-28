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

  VsdxShape rectangle(int id, double x, double y) =>
      VsdxShapeFactory.rectangle(
        id: id,
        pinX: x,
        pinY: y,
        width: 1.5,
        height: 1,
      );

  test('palette drop attaches to a free end of an unselected connector', () {
    final e = ctrl();
    e.addShapeFromBuilderAt(rectangle, 2, 4);
    final source = e.singleSelectedId!;
    e.createConnector(2, 4, 7, 4, beginTarget: source);
    final connector = e.singleSelectedId!;
    e.selectOnly(source);

    expect(
      e.attachShapeToConnectorEnd(
        connector,
        begin: false,
        build: rectangle,
      ),
      isTrue,
    );

    final attached = e.singleSelectedId!;
    expect(attached, isNot(anyOf(source, connector)));
    expect(
      e.currentPage!.connects
          .where((row) => row.fromSheetId == connector)
          .map((row) => row.toSheetId)
          .toSet(),
      equals(<int>{source, attached}),
    );

    e.undo();
    expect(e.currentPage!.findShapeById(attached), isNull);
    expect(e.singleSelectedId, source);
    expect(
      e.currentPage!.connects
          .where((row) => row.fromSheetId == connector && row.isEnd),
      isEmpty,
    );
  });

  test('palette drop refuses an already glued connector end', () {
    final e = ctrl();
    e.addShapeFromBuilderAt(rectangle, 2, 4);
    final source = e.singleSelectedId!;
    e.addShapeFromBuilderAt(rectangle, 7, 4);
    final target = e.singleSelectedId!;
    e.createConnector(
      2,
      4,
      7,
      4,
      beginTarget: source,
      endTarget: target,
    );
    final connector = e.singleSelectedId!;
    final before = e.currentPage!;

    expect(
      e.attachShapeToConnectorEnd(
        connector,
        begin: false,
        build: rectangle,
      ),
      isFalse,
    );
    expect(e.currentPage, same(before));
  });
}
