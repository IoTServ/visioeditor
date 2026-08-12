import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  group('associated document family round-trips', () {
    for (final extension in const <String>[
      'vsdx',
      'vsdm',
      'vstx',
      'vstm',
      'vssx',
      'vssm',
    ]) {
      test(
        '.$extension opens, preserves an unchanged package, and reopens after edit',
        () async {
          final original = await File(
            'packages/vsdx/test/fixtures/test1.vsdx',
          ).readAsBytes();
          final controller = EditorController();
          addTearDown(controller.dispose);

          await controller.openBytes(
            original,
            path: '/documents/family.$extension',
            name: 'family.$extension',
          );

          expect(controller.error, isNull);
          expect(controller.documentFormat, EditorDocumentFormat.visio);
          expect(controller.exportToBytes(), original);
          final shape = controller.currentPage!.shapes.first;
          controller.setShapeText(shape.id, 'Edited .$extension');
          final edited = controller.exportToBytes();
          final reopened = const DocumentParser().parse(edited);
          expect(
            reopened.pages.first.findShapeById(shape.id)!.text,
            'Edited .$extension',
          );
        },
      );
    }

    test('.vsd imports into an editable VSDX and reopens', () async {
      final source = await File('assets/examples/sample.vsd').readAsBytes();
      final controller = EditorController();
      addTearDown(controller.dispose);

      await controller.openBytes(source, name: 'legacy.vsd');

      expect(controller.error, isNull);
      expect(controller.importedFromVsd, isTrue);
      expect(controller.fileName, 'legacy.vsdx');
      expect(
        () => const DocumentParser().parse(controller.exportToBytes()),
        returnsNormally,
      );
    });

    test('.drawio opens, saves as XML, and reopens', () async {
      final source = Uint8List.fromList(
        utf8.encode('''
<mxfile compressed="false"><diagram name="Page-1"><mxGraphModel pageWidth="816" pageHeight="1056"><root><mxCell id="0"/><mxCell id="1" parent="0"/><mxCell id="box" value="Round trip" vertex="1" parent="1"><mxGeometry x="96" y="96" width="192" height="96" as="geometry"/></mxCell></root></mxGraphModel></diagram></mxfile>
'''),
      );
      final controller = EditorController();
      addTearDown(controller.dispose);
      await controller.openBytes(source, name: 'family.drawio');

      expect(controller.error, isNull);
      expect(controller.documentFormat, EditorDocumentFormat.drawio);
      final saved = controller.exportToBytes();
      expect(
        const DrawioCodec().decode(saved).pages.single.shapes.single.text,
        'Round trip',
      );
    });
  });
}
