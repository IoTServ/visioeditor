import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  test('replacing an image keeps same-id media used on another page', () {
    final controller = EditorController()..newDocument();
    addTearDown(controller.dispose);
    final oldBytes = Uint8List.fromList(
      <int>[0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4],
    );
    final newBytes = Uint8List.fromList(
      <int>[0xFF, 0xD8, 0xFF, 0xE0, 9, 8, 7, 6],
    );

    controller.insertImage(
      oldBytes,
      fileExtension: 'png',
      widthInches: 2,
      heightInches: 1,
    );
    final imageId = controller.singleSelectedId!;
    final oldPart = controller.singleSelected!.imagePartName!;

    controller.duplicateCurrentPage();
    expect(controller.document!.pages, hasLength(2));
    expect(
      controller.document!.pages.map((page) => page.shapes.single.id),
      everyElement(imageId),
    );

    controller.selectOnly(imageId);
    controller.replaceImage(imageId, newBytes, fileExtension: 'jpg');

    final edited = controller.document!;
    final newPart = edited.pages.last.shapes.single.imagePartName!;
    expect(newPart, isNot(oldPart));
    expect(edited.pages.first.shapes.single.imagePartName, oldPart);
    expect(edited.images.findByPart(oldPart)?.bytes, oldBytes);
    expect(edited.images.findByPart(newPart)?.bytes, newBytes);

    final svg = VsdxToSvgSerializer().serializePage(
      edited.pages.first,
      theme: edited.theme,
      images: edited.images,
    );
    expect(svg, contains(base64Encode(oldBytes)));

    final reopened = const DocumentParser().parse(controller.exportToBytes());
    expect(reopened.images.findByPart(oldPart)?.bytes, oldBytes);
    expect(reopened.images.findByPart(newPart)?.bytes, newBytes);
  });
}
