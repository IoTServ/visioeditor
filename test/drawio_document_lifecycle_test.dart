import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:visioeditor/io/document_save.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  Uint8List sample() => Uint8List.fromList(
    utf8.encode('''
<mxfile compressed="false"><diagram name="Page One"><mxGraphModel pageWidth="816" pageHeight="1056"><root>
<mxCell id="0"/><mxCell id="1" parent="0"/>
<mxCell id="box" value="Before" style="rounded=1;fillColor=#dae8fc;" vertex="1" parent="1"><mxGeometry x="96" y="96" width="192" height="96" as="geometry"/></mxCell>
</root></mxGraphModel></diagram></mxfile>
'''),
  );

  test(
    'controller opens, edits, and exports draw.io in the same format',
    () async {
      final controller = EditorController();
      addTearDown(controller.dispose);

      await controller.openBytes(
        sample(),
        path: '/documents/flow.drawio',
        name: 'flow.drawio',
      );

      expect(controller.error, isNull);
      expect(controller.documentFormat, EditorDocumentFormat.drawio);
      expect(controller.filePath, '/documents/flow.drawio');
      final shape = controller.currentPage!.shapes.single;
      controller.setShapeText(shape.id, 'After');

      final saved = controller.exportToBytes();
      expect(utf8.decode(saved), contains('<mxfile'));
      expect(
        const DrawioCodec().decode(saved).pages.single.shapes.single.text,
        'After',
      );
    },
  );

  test('normal draw.io save overwrites its path and remains draw.io', () async {
    final controller = EditorController();
    addTearDown(controller.dispose);
    await controller.openBytes(
      sample(),
      path: '/documents/flow.drawio',
      name: 'flow.drawio',
    );
    controller.setShapeText(controller.currentPage!.shapes.single.id, 'Saved');
    Uint8List? written;

    final result = await saveEditorDocument(
      controller,
      saveAs: false,
      directFileSave: true,
      writer: (path, bytes) async {
        expect(path, '/documents/flow.drawio');
        written = bytes;
      },
    );

    expect(result?.path, '/documents/flow.drawio');
    expect(controller.documentFormat, EditorDocumentFormat.drawio);
    expect(controller.isDirty, isFalse);
    expect(
      const DrawioCodec().decode(written!).pages.single.shapes.single.text,
      'Saved',
    );
  });

  test('saving directly to .drawio converts a new VSDX document', () async {
    final controller = EditorController()..newDocument();
    addTearDown(controller.dispose);
    controller
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 3, 2);
    Uint8List? written;

    await saveEditorDocumentToPath(
      controller,
      '/documents/converted.drawio',
      writer: (_, bytes) async => written = bytes,
    );

    expect(controller.documentFormat, EditorDocumentFormat.drawio);
    expect(
      const DrawioCodec().decode(written!).pages.single.shapes,
      hasLength(1),
    );
  });
}
