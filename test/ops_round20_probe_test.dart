import 'dart:typed_data';

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

  test('insertImage undo removes picture and media', () {
    final e = ctrl();
    e.insertImage(
      Uint8List.fromList([1, 2, 3, 4]),
      fileExtension: 'png',
      widthInches: 1,
      heightInches: 1,
      cx: 3,
      cy: 3,
    );
    expect(e.currentPage!.shapes.where((s) => s.hasImage), isNotEmpty);
    e.undo();
    expect(e.currentPage!.shapes.where((s) => s.hasImage), isEmpty);
  });

  test('selectConnectors then delete only removes 1D', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    e.selectConnectors();
    expect(e.selection.every((id) {
      return e.currentPage!.findShapeById(id)!.is1D;
    }), isTrue);
    e.deleteSelection();
    expect(e.currentPage!.shapes.where((s) => s.is1D), isEmpty);
    expect(e.currentPage!.findShapeById(a), isNotNull);
  });

  test('selectVertices selects only 2D', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    e.selectVertices();
    expect(e.selection, equals({a, b}));
  });

  test('replaceAllFind skips locked and locked-layer', () {
    final e = ctrl();
    final a = rect(e, 2, 4, text: 'foo');
    final b = rect(e, 5, 4, text: 'foo');
    e.setSelection([a]);
    e.setSelectionLocked(true);
    e.updateFind('foo');
    e.replaceAllFind('bar');
    expect(e.currentPage!.findShapeById(a)!.text, 'foo');
    expect(e.currentPage!.findShapeById(b)!.richText.plainText, 'bar');
  });

  test('replaceFind advances past locked match without jumping away', () {
    final e = ctrl();
    final a = rect(e, 2, 4, text: 'foo');
    e.setSelectionLocked(true);
    e.addPage();
    final b = rect(e, 3, 3, text: 'keep');
    e.updateFind('foo');
    e.selectPage(1);
    e.setSelection([b]);
    e.replaceFind('bar');
    expect(e.currentPageIndex, 1);
    expect(e.selection, equals({b}));
    expect(e.document!.pages[0].findShapeById(a)!.text, 'foo');
  });

  test('createFreehand undo restores selection', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setSelection([a]);
    e.createFreehand(const [
      Offset2D(1, 1),
      Offset2D(1.2, 1.1),
      Offset2D(1.5, 1.3),
      Offset2D(2, 1.5),
    ]);
    expect(e.selection.single, isNot(a));
    e.undo();
    expect(e.selection, equals({a}));
  });

  test('setDocumentTheme undo restores empty theme', () {
    final e = ctrl();
    expect(e.document!.theme.isEmpty, isTrue);
    e.setDocumentTheme(VsdxTheme.office);
    expect(e.document!.theme.isEmpty, isFalse);
    e.undo();
    expect(e.document!.theme.isEmpty, isTrue);
  });

  test('discardAbandonedShape collapses create undo', () {
    final e = ctrl();
    e.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.textBox(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 1.5,
        height: 0.5,
      ),
      3,
      3,
    );
    final id = e.singleSelectedId!;
    expect(e.isBlankTextBox(id), isTrue);
    e.discardAbandonedShape(id);
    expect(e.currentPage!.findShapeById(id), isNull);
    expect(e.canUndo, isFalse);
  });

  test('setPageIsBackground undo', () {
    final e = ctrl();
    e.setPageIsBackground(true);
    expect(e.currentPage!.isBackgroundPage, isTrue);
    e.undo();
    expect(e.currentPage!.isBackgroundPage, isFalse);
  });

  test('addLaneToSelectedPool undo restores pool', () {
    final e = ctrl();
    final pool = SwimlaneOps.assemblePool(
      poolId: e.currentPage!.nextFreeShapeId(),
      pinX: 5,
      pinY: 4,
      width: 4,
      height: 3,
      laneCount: 2,
    );
    e.updateCurrentPage((p) => p.addShape(pool));
    e.setSelection([pool.id]);
    final lanesBefore = SwimlaneOps.lanesOf(e.currentPage!.findShapeById(pool.id)!).length;
    e.addLaneToSelectedPool();
    expect(
      SwimlaneOps.lanesOf(e.currentPage!.findShapeById(pool.id)!).length,
      lanesBefore + 1,
    );
    e.undo();
    expect(
      SwimlaneOps.lanesOf(e.currentPage!.findShapeById(pool.id)!).length,
      lanesBefore,
    );
  });

  test('reparentSelectionInto null ejects from container', () {
    final e = ctrl();
    final box = VsdxShapeFactory.container(
      id: e.currentPage!.nextFreeShapeId(),
      pinX: 4,
      pinY: 4,
      width: 4,
      height: 3,
    );
    e.updateCurrentPage((p) => p.addShape(box));
    final child = rect(e, 4, 4);
    e.setSelection([child]);
    e.reparentSelectionInto(box.id);
    expect(e.currentPage!.findParentId(child), box.id);
    e.reparentSelectionInto(null);
    expect(e.currentPage!.findParentId(child), isNull);
  });

  test('bringSelectionForward then undo restores z-order', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.setSelection([a]);
    final before = e.currentPage!.shapes.map((s) => s.id).toList();
    e.bringSelectionForward();
    e.undo();
    expect(e.currentPage!.shapes.map((s) => s.id).toList(), before);
    expect(b, isNotNull);
  });

  test('setLineGradient on 1D is accepted', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setSelection([conn]);
    e.setLineGradient(const VsdxGradient(
      stops: [
        VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
        VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
      ],
    ));
    expect(e.currentPage!.findShapeById(conn)!.line.hasGradient, isTrue);
  });

  test('setFillGradient on 1D is ignored', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setSelection([conn]);
    e.setFillGradient(const VsdxGradient(
      stops: [
        VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
        VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
      ],
    ));
    expect(e.currentPage!.findShapeById(conn)!.fill.hasGradient, isFalse);
  });

  test('duplicate group remints child ids uniquely', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    e.duplicateSelection();
    final g2 = e.singleSelectedId!;
    expect(g2, isNot(g));
    final ids = <int>{};
    void walk(VsdxShape s) {
      expect(ids.add(s.id), isTrue, reason: 'duplicate id ${s.id}');
      for (final c in s.children) {
        walk(c);
      }
    }

    for (final s in e.currentPage!.shapes) {
      walk(s);
    }
  });

  test('movePage undo restores tab order and selection', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.addPage();
    e.selectPage(0);
    e.setSelection([a]);
    final id0 = e.document!.pages[0].id;
    final id1 = e.document!.pages[1].id;
    e.movePage(0, 1);
    expect(e.document!.pages[0].id, id1);
    expect(e.document!.pages[1].id, id0);
    e.undo();
    expect(e.document!.pages[0].id, id0);
    expect(e.selection, contains(a));
  });
}
