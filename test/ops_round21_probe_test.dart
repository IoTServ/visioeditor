import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/edit_link_dialog.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  EditorController ctrl() {
    final c = EditorController()
      ..newDocument(widthInches: 11, heightInches: 8.5);
    addTearDown(c.dispose);
    return c;
  }

  int rect(EditorController e, double x, double y, {String? text}) {
    e.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id, pinX: cx, pinY: cy, width: 1, height: 0.6),
        x,
        y);
    final id = e.singleSelectedId!;
    if (text != null) e.setShapeText(id, text);
    return id;
  }

  test('mergeEditedPrimaryLink keeps secondary hyperlinks', () {
    const existing = [
      VsdxHyperlink(
        id: 0,
        address: 'https://a.example',
        description: 'A',
        isDefault: true,
      ),
      VsdxHyperlink(id: 1, address: 'https://b.example', description: 'B'),
    ];
    final merged = mergeEditedPrimaryLink(
      existing: existing,
      editedPrimary: const VsdxHyperlink(
        id: 0,
        address: 'https://c.example',
        description: 'C',
      ),
    );
    expect(merged, hasLength(2));
    expect(merged.first.address, 'https://c.example');
    expect(merged.last.address, 'https://b.example');
  });

  test('setShapeHyperlinks empty clears links', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setShapeHyperlinks(a, [
      const VsdxHyperlink(id: 0, address: 'https://x'),
    ]);
    expect(e.currentPage!.findShapeById(a)!.hyperlinks, isNotEmpty);
    e.setShapeHyperlinks(a, const []);
    expect(e.currentPage!.findShapeById(a)!.hyperlinks, isEmpty);
  });

  test('reconnectEndpoint on locked connector is no-op', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setSelection([conn]);
    e.setSelectionLocked(true);
    final before = e.currentPage!.connects
        .where((c) => c.fromSheetId == conn)
        .map((c) => c.toSheetId)
        .toSet();
    e.reconnectEndpoint(conn, begin: true, targetShapeId: null, x: 0, y: 0);
    final after = e.currentPage!.connects
        .where((c) => c.fromSheetId == conn)
        .map((c) => c.toSheetId)
        .toSet();
    expect(after, before);
  });

  test('setFontFamily on empty seeds for later typing', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setFontFamily('Georgia');
    e.setShapeText(a, 'hi');
    expect(
      e.currentPage!.findShapeById(a)!.richText.runs.first.charStyle.fontFamily,
      'Georgia',
    );
  });

  test('setTextSizeInches on empty seeds for later typing', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setTextSizeInches(0.25);
    e.setShapeText(a, 'hi');
    expect(
      e.currentPage!
          .findShapeById(a)!
          .richText
          .runs
          .first
          .charStyle
          .fontSizeInches,
      closeTo(0.25, 1e-9),
    );
  });

  test('toggleLayerVisibility does not create shape edit undo junk', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setSelection([a]);
    e.addLayer(name: 'L', assignSelection: true);
    final layerId = e.currentPage!.layers.last.id;
    e.toggleLayerVisibility(layerId);
    expect(e.currentPage!.layers.last.visible, isFalse);
    e.undo();
    expect(e.currentPage!.layers.last.visible, isTrue);
  });

  test('assignSelectionToLayer on empty selection is no-op', () {
    final e = ctrl();
    e.addLayer(name: 'L');
    final layerId = e.currentPage!.layers.last.id;
    e.setSelection([]);
    e.assignSelectionToLayer(layerId);
    expect(e.canUndo, isTrue); // layer add only
    e.undo();
    expect(e.currentPage!.layers.where((l) => l.id == layerId), isEmpty);
  });

  test('setCornerRadius on locked is no-op', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setSelectionLocked(true);
    e.setCornerRadius(0.2);
    final g = e.currentPage!.findShapeById(a)!.geometries.first;
    expect(g.commands.any((c) => c is EllipticalArcTo), isFalse);
  });

  test('setSelectedAngleDegrees on locked is no-op', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setSelectionLocked(true);
    e.setSelectedAngleDegrees(45);
    expect(e.currentPage!.findShapeById(a)!.angleRad, 0);
  });

  test('pasteStyle rememberStyle updates memo for new shapes', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setFillColor(const VsdxColor(0xFF00AA00));
    e.copyStyle();
    final b = rect(e, 5, 4);
    e.setSelection([b]);
    e.pasteStyle();
    final c = rect(e, 3, 2);
    expect(
      e.currentPage!.findShapeById(c)!.fill.foreground?.value,
      0xFF00AA00,
    );
    expect(a, isNotNull);
  });

  test('ungroup nested group one level only', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 3, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    final inner = e.singleSelectedId!;
    final c = rect(e, 6, 4);
    e.setSelection([inner, c]);
    e.groupSelection();
    final outer = e.singleSelectedId!;
    e.ungroupSelection();
    expect(e.currentPage!.findShapeById(outer), isNull);
    expect(e.currentPage!.findShapeById(inner), isNotNull);
    expect(e.currentPage!.findParentId(a), inner);
  });

  test('deleteCurrentPage when only one page is no-op', () {
    final e = ctrl();
    expect(e.document!.pages, hasLength(1));
    e.deleteCurrentPage();
    expect(e.document!.pages, hasLength(1));
  });

  test('setLinePattern 0 equals setNoLine for stroke visibility', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setLinePattern(0);
    expect(e.currentPage!.findShapeById(a)!.line.pattern, 0);
    expect(e.currentPage!.findShapeById(a)!.line.hasLine, isFalse);
  });

  test('beginEditConnectionPoints on locked is no-op', () {
    final e = ctrl();
    rect(e, 2, 4);
    e.setSelectionLocked(true);
    e.beginEditConnectionPoints();
    expect(e.editingConnectionPoints, isFalse);
  });

  test('setGlow false clears on selection', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setGlow(true);
    expect(e.currentPage!.findShapeById(a)!.glow.enabled, isTrue);
    e.setGlow(false);
    expect(e.currentPage!.findShapeById(a)!.glow.enabled, isFalse);
  });
}
