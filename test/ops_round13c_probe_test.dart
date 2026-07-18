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

  int rect(EditorController e, double x, double y) {
    e.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id, pinX: cx, pinY: cy, width: 1, height: 0.6),
        x,
        y);
    return e.singleSelectedId!;
  }

  test('reparent connector preserves glue and page geometry', () {
    final e = ctrl();
    final box = VsdxShapeFactory.container(
      id: e.currentPage!.nextFreeShapeId(),
      pinX: 4,
      pinY: 4,
      width: 4,
      height: 3,
    );
    e.updateCurrentPage((p) => p.addShape(box));
    final a = rect(e, 2, 4);
    final b = rect(e, 6, 4);
    e.createConnector(2, 4, 6, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setSelection([conn]);
    e.reparentSelectionInto(box.id);
    final pin = e.currentPage!.shapePinPage(conn);
    expect(e.currentPage!.findParentId(conn), box.id);
    expect(pin.x, closeTo(4, 0.5));
    expect(pin.y, closeTo(4, 0.5));
  });

  test('reparentSelectionInto skips locked-layer shapes', () {
    final e = ctrl();
    final box = VsdxShapeFactory.container(
      id: e.currentPage!.nextFreeShapeId(),
      pinX: 4,
      pinY: 4,
      width: 4,
      height: 3,
    );
    e.updateCurrentPage((p) => p.addShape(box));
    final child = rect(e, 1, 1);
    e.updateCurrentPage((p) {
      final layers = <VsdxLayer>[
        ...p.layers,
        const VsdxLayer(id: 99, name: 'L', locked: true),
      ];
      return p.copyWith(layers: layers).updateShapeById(
            child,
            (s) => s.copyWith(layerMemberIds: const <int>[99]),
          );
    });
    e.setSelection([child]);
    expect(e.isOnLockedLayer(child), isTrue);
    e.reparentSelectionInto(box.id);
    expect(e.currentPage!.findParentId(child), isNull);
  });

  test('effects skip 1D in mixed selection', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setSelection([a, conn]);
    e.setShadow(true);
    e.setGlow(true);
    e.setReflection(true);
    final c = e.currentPage!.findShapeById(conn)!;
    expect(c.shadow.enabled, isFalse);
    expect(c.glow.enabled, isFalse);
    expect(c.reflection.enabled, isFalse);
    expect(e.currentPage!.findShapeById(a)!.shadow.enabled, isTrue);
  });
}
