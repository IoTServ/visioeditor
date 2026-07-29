import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:visioeditor/editor/link_opener.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  EditorController controllerWithShape() {
    final controller = EditorController()..newDocument();
    addTearDown(controller.dispose);
    controller
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 3, 2);
    return controller;
  }

  test('internal hyperlink switches to its page without external launch',
      () async {
    final controller = controllerWithShape();
    final shapeId = controller.singleSelectedId!;
    controller.duplicateCurrentPage();
    controller.renamePageAt(1, 'Page-2');
    controller.selectPage(0);
    controller.setSelection(<int>{shapeId});
    controller.setShapeHyperlinks(shapeId, const <VsdxHyperlink>[
      VsdxHyperlink(id: 0, subAddress: '#Page-2', isDefault: true),
    ]);
    var externalLaunches = 0;

    final result = await openPrimaryHyperlink(
      controller,
      launcher: (uri) async {
        externalLaunches++;
        return true;
      },
    );

    expect(result, HyperlinkOpenResult.openedInternal);
    expect(controller.currentPageIndex, 1);
    expect(controller.selection, isEmpty);
    expect(externalLaunches, 0);
  });

  test('internal page resolver accepts names, suffixes, and page ids', () {
    const document = VsdxDocument(pages: <VsdxPage>[
      VsdxPage(
        id: 7,
        name: 'Overview',
        widthInches: 8.5,
        heightInches: 11,
        shapes: <VsdxShape>[],
      ),
      VsdxPage(
        id: 12,
        name: 'Details',
        widthInches: 8.5,
        heightInches: 11,
        shapes: <VsdxShape>[],
      ),
    ]);

    expect(resolveInternalPageIndex(document, '#details/Shape-4'), 1);
    expect(resolveInternalPageIndex(document, '#Overview!Bookmark'), 0);
    expect(resolveInternalPageIndex(document, '#Page-12'), 1);
    expect(resolveInternalPageIndex(document, 'missing'), isNull);
  });

  test('external hyperlink uses the injected platform launcher', () async {
    final controller = controllerWithShape();
    final shapeId = controller.singleSelectedId!;
    controller.setShapeHyperlinks(shapeId, const <VsdxHyperlink>[
      VsdxHyperlink(id: 0, address: 'www.example.com/docs', isDefault: true),
    ]);
    Uri? launched;

    final result = await openPrimaryHyperlink(
      controller,
      launcher: (uri) async {
        launched = uri;
        return true;
      },
    );

    expect(result, HyperlinkOpenResult.openedExternal);
    expect(launched, Uri.parse('https://www.example.com/docs'));
  });

  test('unsafe targets and failed launches report without throwing', () async {
    final controller = controllerWithShape();
    final shapeId = controller.singleSelectedId!;
    controller.setShapeHyperlinks(shapeId, const <VsdxHyperlink>[
      VsdxHyperlink(id: 0, address: 'javascript:alert(1)'),
    ]);
    expect(
      await openPrimaryHyperlink(controller, launcher: (_) async => true),
      HyperlinkOpenResult.invalidTarget,
    );

    controller.setShapeHyperlinks(shapeId, const <VsdxHyperlink>[
      VsdxHyperlink(id: 0, address: 'https://example.com'),
    ]);
    expect(
      await openPrimaryHyperlink(controller, launcher: (_) async => false),
      HyperlinkOpenResult.launchFailed,
    );
  });
}
