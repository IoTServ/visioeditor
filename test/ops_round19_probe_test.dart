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
      {double w = 1, double h = 0.6, String? text}) {
    e.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id, pinX: cx, pinY: cy, width: w, height: h),
        x,
        y);
    final id = e.singleSelectedId!;
    if (text != null) e.setShapeText(id, text);
    return id;
  }

  test('setItalic on empty seeds style for later typing', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setItalic(true);
    e.setShapeText(a, 'later');
    expect(
      e.currentPage!.findShapeById(a)!.richText.runs.first.charStyle.style.italic,
      isTrue,
    );
  });

  test('setUnderline on empty seeds style for later typing', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setUnderline(true);
    e.setShapeText(a, 'later');
    expect(
      e.currentPage!
          .findShapeById(a)!
          .richText
          .runs
          .first
          .charStyle
          .underline,
      isTrue,
    );
  });

  test('setTextColor on empty seeds color for later typing', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setTextColor(const VsdxColor(0xFFFF0000));
    e.setShapeText(a, 'later');
    expect(
      e.currentPage!.findShapeById(a)!.richText.runs.first.charStyle.color?.value,
      0xFFFF0000,
    );
  });

  test('setBullet on empty seeds para for later typing', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setBullet(true);
    e.setShapeText(a, 'later');
    expect(
      e.currentPage!.findShapeById(a)!.richText.runs.first.paraStyle.bullet,
      isNot(0),
    );
  });

  test('distributeHorizontally skips locked', () {
    final e = ctrl();
    final a = rect(e, 1, 4);
    final b = rect(e, 3, 4);
    final c = rect(e, 7, 4);
    e.setSelection([b]);
    e.setSelectionLocked(true);
    e.setSelection([a, b, c]);
    final bx = e.currentPage!.findShapeById(b)!.pinX;
    e.distributeHorizontally();
    expect(e.currentPage!.findShapeById(b)!.pinX, bx);
  });

  test('alignCenterH with one unlocked + one locked moves unlocked', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 6, 4);
    e.setSelection([a]);
    e.setSelectionLocked(true);
    e.setSelection([a, b]);
    final ax = e.currentPage!.findShapeById(a)!.pinX;
    e.alignCenterH();
    expect(e.currentPage!.findShapeById(a)!.pinX, ax);
    expect(e.currentPage!.findShapeById(b)!.pinX, isNot(6));
  });

  test('cut locked-only leaves clipboard empty', () {
    final e = ctrl();
    rect(e, 2, 4);
    e.setSelectionLocked(true);
    e.cut();
    expect(e.hasClipboard, isFalse);
    expect(e.currentPage!.shapes, hasLength(1));
  });

  test('pasteAt with empty clipboard is no-op', () {
    final e = ctrl();
    final before = e.currentPage!.shapes.length;
    e.pasteAt(cx: 4, cy: 4);
    expect(e.currentPage!.shapes.length, before);
  });

  test('setConnectorRouteStyle curved then undo', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setSelection([conn]);
    e.setConnectorRouteStyle(ConnectorRouteStyle.curved);
    expect(e.currentPage!.findShapeById(conn)!.curved, isTrue);
    e.undo();
    expect(e.currentPage!.findShapeById(conn)!.curved, isFalse);
  });

  test('setConnectorRouteStyle on locked connector is no-op', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setSelection([conn]);
    e.setSelectionLocked(true);
    e.setConnectorRouteStyle(ConnectorRouteStyle.straight);
    expect(e.currentPage!.findShapeById(conn)!.straightRoute, isFalse);
  });

  test('addWaypoint on locked connector is no-op', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setSelection([conn]);
    e.setSelectionLocked(true);
    e.addWaypoint(conn, 0, const Offset2D(3.5, 5));
    expect(e.currentPage!.findShapeById(conn)!.waypoints, isEmpty);
  });

  test('toggleCollapsed undo restores height and glue', () {
    final e = ctrl();
    final page0 = e.currentPage!;
    final box = VsdxShapeFactory.container(
      id: page0.nextFreeShapeId(),
      pinX: 4,
      pinY: 4,
      width: 4,
      height: 3,
    );
    e.updateCurrentPage((p) => p.addShape(box));
    final h0 = e.currentPage!.findShapeById(box.id)!.height;
    e.toggleCollapsed(box.id);
    expect(e.isCollapsed(box.id), isTrue);
    e.undo();
    expect(e.isCollapsed(box.id), isFalse);
    expect(e.currentPage!.findShapeById(box.id)!.height, closeTo(h0, 1e-9));
  });

  test('renamePageAt empty / whitespace is no-op', () {
    final e = ctrl();
    final name = e.document!.pages[0].name;
    e.renamePageAt(0, '   ');
    expect(e.document!.pages[0].name, name);
  });

  test('setBackgroundColor then redo restores', () {
    final e = ctrl();
    e.setBackgroundColor(const VsdxColor(0xFF112233));
    e.undo();
    expect(e.pageBackgroundColor, isNull);
    e.redo();
    expect(e.pageBackgroundColor?.value, 0xFF112233);
  });

  test('groupSelection undo restores prior multi-selection', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    e.undo();
    expect(e.selection, equals({a, b}));
    expect(e.currentPage!.findParentId(a), isNull);
  });

  test('setSelectedWidth on locked is no-op', () {
    final e = ctrl();
    final a = rect(e, 2, 4, w: 1);
    e.setSelectionLocked(true);
    e.setSelectedWidth(3);
    expect(e.currentPage!.findShapeById(a)!.width, closeTo(1, 1e-9));
  });

  test('flipVertical undo restores', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.flipVertical();
    expect(e.currentPage!.findShapeById(a)!.flipY, isTrue);
    e.undo();
    expect(e.currentPage!.findShapeById(a)!.flipY, isFalse);
  });

  test('selectNextShape cycles among top-level', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.setSelection([a]);
    e.selectNextShape();
    expect(e.selection, equals({b}));
    e.selectNextShape();
    expect(e.selection, equals({a}));
  });
}
