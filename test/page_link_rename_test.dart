import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:visioeditor/editor/link_opener.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  test('renaming a page retargets internal links and exported anchors', () async {
    final controller = EditorController()..newDocument();
    addTearDown(controller.dispose);
    controller
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 3, 2);
    final shapeId = controller.singleSelectedId!;

    controller.duplicateCurrentPage();
    controller.renamePageAt(1, 'Page-2');
    controller.selectPage(0);
    controller.selectOnly(shapeId);
    controller.setShapeHyperlinks(shapeId, const <VsdxHyperlink>[
      VsdxHyperlink(
        id: 0,
        subAddress: '#Page-2',
        isDefault: true,
      ),
      VsdxHyperlink(
        id: 1,
        subAddress: '#Page-2/Shape-9',
      ),
      VsdxHyperlink(
        id: 2,
        address: 'https://example.com',
        subAddress: '#Page-2',
      ),
    ]);

    controller.renamePageAt(1, 'Details');
    var links = controller.currentPage!.findShapeById(shapeId)!.hyperlinks;
    expect(links.first.subAddress, '#Details');
    expect(links[1].subAddress, '#Details/Shape-9');
    expect(links.last.subAddress, '#Page-2');

    expect(
      await openPrimaryHyperlink(controller, launcher: (_) async => false),
      HyperlinkOpenResult.openedInternal,
    );
    expect(controller.currentPageIndex, 1);

    controller.undo();
    expect(controller.document!.pages[1].name, 'Page-2');
    links = controller.document!.pages.first.findShapeById(shapeId)!.hyperlinks;
    expect(links.first.subAddress, '#Page-2');
    expect(links[1].subAddress, '#Page-2/Shape-9');

    controller.redo();
    expect(controller.document!.pages[1].name, 'Details');
    links = controller.document!.pages.first.findShapeById(shapeId)!.hyperlinks;
    expect(links.first.subAddress, '#Details');
    expect(links[1].subAddress, '#Details/Shape-9');

    final reopened = const DocumentParser().parse(controller.exportToBytes());
    expect(
      reopened.pages.first
          .findShapeById(shapeId)!
          .hyperlinks
          .first
          .subAddress,
      '#Details',
    );
    final svg = VsdxToSvgSerializer().serializeDocument(reopened);
    expect(svg, contains('href="#Details"'));
    expect(svg, contains('id="Details"'));
    expect(svg, isNot(contains('href="#Page-2"')));
  });
}
