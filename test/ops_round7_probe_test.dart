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

  int rect(EditorController e, double x, double y,
      {double w = 1, double h = 0.6}) {
    e.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id, pinX: cx, pinY: cy, width: w, height: h),
        x,
        y);
    return e.singleSelectedId!;
  }

  test('setCornerRadius no-op when shape locked', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setSelectionLocked(true);
    e.setCornerRadius(0.2);
    final s = e.currentPage!.findShapeById(a)!;
    expect(s.geometries.first.commands.any((c) => c is EllipticalArcTo), isFalse);
  });

  test('setCornerRadius no-op on locked layer', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.addLayer(name: 'L', assignSelection: true);
    e.toggleLayerLocked(e.currentPage!.layers.last.id);
    e.setCornerRadius(0.2);
    final s = e.currentPage!.findShapeById(a)!;
    expect(s.geometries.first.commands.any((c) => c is EllipticalArcTo), isFalse);
  });

  test('cut of locked shape does not leave clipboard orphan', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setSelectionLocked(true);
    e.cut();
    expect(e.currentPage!.findShapeById(a), isNotNull);
    expect(e.hasClipboard, isFalse);
  });

  test('cut mixed selection only copies unlocked shapes', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 4, 4);
    e.setSelection([a]);
    e.setSelectionLocked(true);
    e.setSelection([a, b]);
    e.cut();
    expect(e.currentPage!.findShapeById(a), isNotNull);
    expect(e.currentPage!.findShapeById(b), isNull);
    expect(e.selection, equals({a}));
    e.paste();
    // Only one unlocked copy should appear (not a duplicate of locked a).
    expect(e.currentPage!.shapes.length, 2);
    expect(e.currentPage!.shapes.where((s) => s.locked), hasLength(1));
  });

  test('clearSelectedConnectorWaypoints skips locked connector', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.singleSelectedId!;
    e.setConnectorWaypoints(conn, const [
      Offset2D(3.5, 5),
    ]);
    expect(e.currentPage!.findShapeById(conn)!.waypoints, isNotEmpty);
    e.setSelectionLocked(true);
    e.clearSelectedConnectorWaypoints();
    expect(e.currentPage!.findShapeById(conn)!.waypoints, isNotEmpty);
  });

  test('pasteStyle does not restyle locked shapes', () {
    final e = ctrl();
    rect(e, 2, 4);
    e.setFillColor(const VsdxColor(0xFFFF0000));
    e.copyStyle();
    final b = rect(e, 4, 4);
    e.setFillColor(const VsdxColor(0xFF0000FF));
    e.setSelectionLocked(true);
    e.pasteStyle();
    expect(
      e.currentPage!.findShapeById(b)!.fill.foreground,
      const VsdxColor(0xFF0000FF),
    );
    e.setSelectionLocked(false);
    e.pasteStyle();
    expect(
      e.currentPage!.findShapeById(b)!.fill.foreground,
      const VsdxColor(0xFFFF0000),
    );
  });

  test('toggleCollapsed rejects locked container', () {
    final e = ctrl();
    e.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.container(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 3,
        height: 2,
      ),
      4,
      4,
    );
    final id = e.singleSelectedId!;
    final child = rect(e, 4, 3.5);
    e.setSelection([child]);
    e.applyDropContainmentAt(4, 3.5, transient: false);
    e.setSelection([id]);
    e.setSelectionLocked(true);
    expect(e.isCollapsed(id), isFalse);
    e.toggleCollapsed(id);
    expect(e.isCollapsed(id), isFalse);
  });

  test('cut then switch page then paste works on new page', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.cut();
    e.addPage();
    e.paste();
    expect(e.currentPageIndex, 1);
    expect(e.currentPage!.shapes, hasLength(1));
    expect(e.document!.pages[0].findShapeById(a), isNull);
  });

  test('selectConnectors and selectVertices are complementary', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    e.selectConnectors();
    expect(e.selection.length, 1);
    expect(e.currentPage!.findShapeById(e.selection.first)!.is1D, isTrue);
    e.selectVertices();
    expect(e.selection, equals({a, b}));
  });

  test('cut undo restores prior multi-selection including locked', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 4, 4);
    e.setSelection([a]);
    e.setSelectionLocked(true);
    e.setSelection([a, b]);
    e.cut();
    e.undo();
    expect(e.currentPage!.findShapeById(b), isNotNull);
    expect(e.selection, equals({a, b}));
  });
}
