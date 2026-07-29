import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  EditorController controller() {
    final c = EditorController()
      ..newDocument(widthInches: 11, heightInches: 8.5);
    addTearDown(c.dispose);
    return c;
  }

  int addRect(EditorController c, double x, double y) {
    c.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 1,
        height: 0.6,
      ),
      x,
      y,
    );
    return c.singleSelectedId!;
  }

  void connect(EditorController c, int source, int target) {
    final page = c.currentPage!;
    final a = page.findShapeById(source)!;
    final b = page.findShapeById(target)!;
    c.createConnector(
      a.pinX,
      a.pinY,
      b.pinX,
      b.pinY,
      beginTarget: source,
      endTarget: target,
    );
  }

  test('tree selection follows directed connectors and handles cycles', () {
    final c = controller();
    final root = addRect(c, 2, 6);
    final left = addRect(c, 1, 4);
    final right = addRect(c, 3, 4);
    final leaf = addRect(c, 1, 2);
    connect(c, root, left);
    connect(c, root, right);
    connect(c, left, leaf);
    connect(c, leaf, root);

    c.selectOnly(root);
    expect(c.canSelectChildren, isTrue);
    c.selectChildren();
    expect(c.selection, <int>{left, right});

    c.selectOnly(root);
    c.selectDescendants();
    expect(c.selection, <int>{left, right, leaf});

    c.selectOnly(root);
    c.selectSubtree();
    final connectors = c.currentPage!.shapes
        .where((shape) => shape.isGlueableConnector)
        .map((shape) => shape.id);
    expect(c.selection, <int>{root, left, right, leaf, ...connectors});

    c.selectOnly(left);
    expect(c.canSelectRelatedParent, isTrue);
    c.selectRelatedParent();
    expect(c.singleSelectedId, root);

    c.selectOnly(left);
    expect(c.canSelectSiblings, isTrue);
    c.selectSiblings();
    expect(c.selection, <int>{left, right});
  });

  test(
    'tree selection falls back to nested groups and skips collapsed trees',
    () {
      final c = controller();
      final page = c.currentPage!;
      final leafA = VsdxShapeFactory.rectangle(
        id: 4,
        pinX: 0.7,
        pinY: 0.5,
        width: 0.5,
        height: 0.3,
      );
      final leafB = VsdxShapeFactory.rectangle(
        id: 5,
        pinX: 1.3,
        pinY: 0.5,
        width: 0.5,
        height: 0.3,
      );
      final nested = VsdxShapeFactory.rectangle(
        id: 2,
        pinX: 1,
        pinY: 1,
        width: 1.8,
        height: 1.2,
      ).copyWith(children: <VsdxShape>[leafA, leafB]);
      final peer = VsdxShapeFactory.ellipse(
        id: 3,
        pinX: 3,
        pinY: 1,
        width: 1,
        height: 1,
      );
      final root = VsdxShapeFactory.container(
        id: 1,
        pinX: 4,
        pinY: 4,
        width: 5,
        height: 3,
      ).copyWith(children: <VsdxShape>[nested, peer]);
      c.updateCurrentPage((p) => p.copyWith(shapes: <VsdxShape>[root]));

      c.selectOnly(root.id);
      c.selectChildren();
      expect(c.selection, <int>{nested.id, peer.id});

      c.selectOnly(root.id);
      c.selectDescendants();
      expect(c.selection, <int>{nested.id, leafA.id, leafB.id, peer.id});

      c.selectOnly(root.id);
      c.selectSubtree();
      expect(
        c.selection,
        <int>{root.id, nested.id, leafA.id, leafB.id, peer.id},
      );

      c.selectOnly(leafA.id);
      c.selectSiblings();
      expect(c.selection, <int>{leafA.id, leafB.id});
      c.selectOnly(leafA.id);
      c.selectRelatedParent();
      expect(c.singleSelectedId, nested.id);

      c.selectOnly(root.id);
      c.toggleCollapsed(root.id);
      expect(c.canSelectChildren, isFalse);
      expect(c.canSelectDescendants, isFalse);
      expect(c.currentPage!.id, page.id);
    },
  );

  test(
    'page keyboard helpers navigate, reorder, and undo without wrapping',
    () {
      final c = controller();
      c.addPage();
      c.addPage();
      final originalOrder = c.document!.pages.map((page) => page.id).toList();

      c.selectBoundaryPage(last: false);
      expect(c.currentPageIndex, 0);
      c.selectRelativePage(-1);
      expect(c.currentPageIndex, 0);
      c.selectRelativePage(1);
      expect(c.currentPageIndex, 1);
      c.selectBoundaryPage(last: true);
      expect(c.currentPageIndex, 2);

      c.moveCurrentPageToBoundary(last: false);
      expect(c.currentPageIndex, 0);
      expect(c.document!.pages.first.id, originalOrder.last);
      c.undo();
      expect(c.document!.pages.map((page) => page.id), originalOrder);
      expect(c.currentPageIndex, 2);

      c.moveCurrentPageBy(-1);
      expect(c.currentPageIndex, 1);
      c.moveCurrentPageBy(-10);
      expect(c.currentPageIndex, 0);
      c.moveCurrentPageBy(-1);
      expect(c.currentPageIndex, 0);
    },
  );
}
