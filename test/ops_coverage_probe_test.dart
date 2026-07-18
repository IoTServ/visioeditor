import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:visioeditor/editor/shape_clipboard.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  EditorController ctrl() {
    final c = EditorController()
      ..newDocument(widthInches: 11, heightInches: 8.5);
    addTearDown(c.dispose);
    return c;
  }

  int addRect(EditorController c, double x, double y) {
    c.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id, pinX: cx, pinY: cy, width: 1.0, height: 0.6),
        x,
        y);
    return c.singleSelectedId!;
  }

  void assertUniqueIds(VsdxPage page) {
    final allIds = <int>{};
    void walk(VsdxShape s) {
      expect(allIds.add(s.id), isTrue, reason: 'duplicate id ${s.id}');
      for (final ch in s.children) {
        walk(ch);
      }
    }

    for (final s in page.shapes) {
      walk(s);
    }
  }

  test('duplicate group assigns unique ids to children', () {
    final c = ctrl();
    final a = addRect(c, 2, 4);
    final b = addRect(c, 4, 4);
    c.setSelection([a, b]);
    c.groupSelection();
    final gid = c.singleSelectedId!;
    final childIdsBefore =
        c.currentPage!.findShapeById(gid)!.children.map((s) => s.id).toSet();

    c.duplicateSelection();
    final page = c.currentPage!;
    expect(page.shapes.length, 2);
    assertUniqueIds(page);
    final orig = page.findShapeById(gid)!;
    expect(orig.children.map((s) => s.id).toSet(), childIdsBefore);
  });

  test('paste group after copy keeps unique nested ids', () {
    final c = ctrl();
    final a = addRect(c, 2, 4);
    final b = addRect(c, 4, 4);
    c.setSelection([a, b]);
    c.groupSelection();
    c.copySelection();
    c.paste();
    expect(c.currentPage!.shapes.length, 2);
    assertUniqueIds(c.currentPage!);
  });

  test('ShapeClipboardCodec remaps nested ids in group envelopes', () {
    final c = ctrl();
    final a = addRect(c, 2, 4);
    final b = addRect(c, 4, 4);
    c.setSelection([a, b]);
    c.groupSelection();
    final group = c.currentPage!.findShapeById(c.singleSelectedId!)!;
    final envelope = ShapeClipboardCodec.encode([group]);
    final decoded = ShapeClipboardCodec.decode(envelope)!;
    expect(decoded, hasLength(1));
    assertUniqueIds(VsdxPage(
      id: 0,
      name: 'p',
      widthInches: 8.5,
      heightInches: 11,
      shapes: decoded,
    ));
  });

  test('ungroup undo restores the group shape', () {
    final c = ctrl();
    final a = addRect(c, 2, 4);
    final b = addRect(c, 4, 4);
    c.setSelection([a, b]);
    c.groupSelection();
    final gid = c.singleSelectedId!;
    c.ungroupSelection();
    expect(c.currentPage!.findShapeById(gid), isNull);
    c.undo();
    expect(c.currentPage!.findShapeById(gid), isNotNull);
  });

  test('cut then paste restores a shape on an empty page', () {
    final c = ctrl();
    addRect(c, 2, 4);
    c.cut();
    expect(c.currentPage!.shapes, isEmpty);
    c.paste();
    expect(c.currentPage!.shapes, hasLength(1));
  });

  test('connectDirectional cloning a group remints nested ids', () {
    final c = ctrl();
    final a = addRect(c, 2, 4);
    final b = addRect(c, 3.5, 4);
    c.setSelection([a, b]);
    c.groupSelection();
    final gid = c.singleSelectedId!;
    c.connectDirectional(gid, 1, cloneX: 6, cloneY: 4);
    assertUniqueIds(c.currentPage!);
  });

  test('replaceFind undo returns to the page the user was viewing', () {
    final c = ctrl();
    addRect(c, 2, 4);
    c.setShapeText(c.singleSelectedId!, 'alpha');
    c.addPage();
    addRect(c, 3, 4);
    c.setShapeText(c.singleSelectedId!, 'zzzz');
    expect(c.currentPageIndex, 1);
    c.updateFind('alpha');
    expect(c.findCurrentPageIndex, 0);
    // User navigates away; Replace should still edit the current hit,
    // and Undo should bring them back to this page.
    c.selectPage(1);
    expect(c.findMatchCount, greaterThan(0));
    c.replaceFind('ALPHA');
    final page0Text = c.document!.pages[0].shapes.first.richText.plainText;
    expect(page0Text, 'ALPHA');
    c.undo();
    expect(c.currentPageIndex, 1);
    expect(c.document!.pages[0].shapes.first.richText.plainText, 'alpha');
  });

  test('duplicateCurrentPage undo returns to the source page', () {
    final c = ctrl();
    addRect(c, 2, 4);
    expect(c.currentPageIndex, 0);
    c.duplicateCurrentPage();
    expect(c.pageCount, 2);
    expect(c.currentPageIndex, 1);
    c.undo();
    expect(c.pageCount, 1);
    expect(c.currentPageIndex, 0);
  });

  test('successive pastes offset instead of stacking', () {
    final c = ctrl();
    addRect(c, 2, 4);
    c.copySelection();
    c.paste();
    c.paste();
    final pins = c.currentPage!.shapes.map((s) => s.pinX).toList()..sort();
    expect(pins.toSet().length, 3);
    expect(pins[1] - pins[0], closeTo(0.25, 1e-9));
    expect(pins[2] - pins[1], closeTo(0.25, 1e-9));
  });

  test('paste remaps connector formulas and glue rows', () {
    final c = ctrl();
    final a = addRect(c, 2, 4);
    final b = addRect(c, 5, 4);
    c.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = c.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    final connectsBefore = c.currentPage!.connects.length;
    c.setSelection([a, b, conn]);
    c.copySelection();
    c.paste();
    expect(c.currentPage!.connects.length, greaterThan(connectsBefore));
    final pastedConn = c.currentPage!.shapes.lastWhere(
      (s) => s.is1D && s.id != conn,
    );
    expect(
      pastedConn.formulas.values
          .any((f) => f.contains('Sheet.$a') || f.contains('Sheet.$b')),
      isFalse,
      reason: 'pasted connector still references original sheets',
    );
    expect(
      pastedConn.formulas.values.any((f) => f.contains('Sheet.')),
      isTrue,
    );
  });

  test('locked layer blocks style edits but unlock still works', () {
    final c = ctrl();
    final id = addRect(c, 2, 4);
    c.addLayer(name: 'L', assignSelection: true);
    c.toggleLayerLocked(0);
    final before = c.currentPage!.findShapeById(id)!.fill.foreground?.value;
    c.setFillColor(const VsdxColor(0xFFFF0000));
    expect(
      c.currentPage!.findShapeById(id)!.fill.foreground?.value,
      before,
    );
    c.toggleLayerLocked(0);
    c.setFillColor(const VsdxColor(0xFFFF0000));
    expect(
      c.currentPage!.findShapeById(id)!.fill.foreground?.value,
      0xFFFF0000,
    );
  });

  test('selectPage keeps find matches across sheets', () {
    final c = ctrl();
    addRect(c, 2, 4);
    c.setShapeText(c.singleSelectedId!, 'alpha');
    c.addPage();
    addRect(c, 3, 4);
    c.setShapeText(c.singleSelectedId!, 'alpha2');
    c.selectPage(0);
    c.updateFind('alpha');
    expect(c.findMatchCount, 2);
    c.selectPage(1);
    expect(c.findMatchCount, 2);
    c.findNext();
    expect(c.selection, isNotEmpty);
  });
}
