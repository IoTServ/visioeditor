import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:vsdx/vsdx.dart';

Uint8List _withLegacyVisioVersion(Uint8List source, int version) {
  final bytes = Uint8List.fromList(source);
  const magic = 'Visio (TM) Drawing\r\n\x00';
  for (var i = 0; i + magic.length <= bytes.length; i++) {
    var match = true;
    for (var j = 0; j < magic.length; j++) {
      if (bytes[i + j] != magic.codeUnitAt(j)) {
        match = false;
        break;
      }
    }
    if (match) {
      bytes[i + 0x1a] = version;
      return bytes;
    }
  }
  throw StateError('VisioDocument header not found in CFB');
}

void main() {
  group('associated document family round-trips', () {
    for (final extension in const <String>[
      'vsdx',
      'vsdm',
      'vstx',
      'vstm',
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

    for (final extension in const <String>['vssx', 'vssm']) {
      test('.$extension imports every stencil master into editable pages',
          () async {
        final source = File(
          'packages/vsdx/test/fixtures/test_master.vsdx',
        ).readAsBytesSync();
        final controller = EditorController();
        addTearDown(controller.dispose);

        await controller.openBytes(source, name: 'sampler.$extension');

        expect(controller.error, isNull);
        expect(controller.importedFromVsd, isTrue);
        expect(controller.fileName, 'sampler.vsdx');
        expect(
          controller.document!.pages.map((page) => page.name),
          ['Test Master', 'Test Master 2'],
        );
        expect(
          controller.document!.pages.every((page) => page.shapes.isNotEmpty),
          isTrue,
        );
        final reopened = const DocumentParser().parse(
          controller.exportToBytes(),
        );
        expect(reopened.pages, hasLength(2));
        expect(reopened.pages.every((page) => page.shapes.isNotEmpty), isTrue);
      });
    }

    for (final extension in const <String>['vdx', 'vsx', 'vtx']) {
      test('.$extension imports DiagramML and saves as editable VSDX',
          () async {
        final source = File(
          'packages/vsdx/test/fixtures/vdx_all_types.vdx',
        ).readAsBytesSync();
        final controller = EditorController();
        addTearDown(controller.dispose);

        await controller.openBytes(source, name: 'legacy.$extension');

        expect(controller.error, isNull);
        expect(controller.importedFromVsd, isTrue);
        expect(controller.fileName, 'legacy.vsdx');
        expect(controller.document!.pages, isNotEmpty);
        expect(
          controller.document!.pages.every((page) => page.shapes.isNotEmpty),
          isTrue,
        );
        final reopened = const DocumentParser().parse(
          controller.exportToBytes(),
        );
        expect(reopened.pages, hasLength(controller.document!.pages.length));
        expect(reopened.pages.every((page) => page.shapes.isNotEmpty), isTrue);
      });
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

    test('.vss imports stencil masters into an editable VSDX', () async {
      final encoded = File(
        'packages/vsdx/test/fixtures/vsd/external/'
        'Nortel-vpn-gateway-3050-front.vss.b64',
      ).readAsStringSync();
      final source = base64.decode(encoded.replaceAll(RegExp(r'\s'), ''));
      final controller = EditorController();
      addTearDown(controller.dispose);

      await controller.openBytes(source, name: 'device.vss');

      expect(controller.error, isNull);
      expect(controller.importedFromVsd, isTrue);
      expect(controller.fileName, 'device.vsdx');
      expect(controller.document!.pages.single.name, 'VG 3050');
      expect(controller.document!.pages.single.shapes, hasLength(1));
      expect(
        controller.document!.pages.single.shapes.single.imagePartName,
        isNotNull,
      );
      final reopened = const DocumentParser().parse(controller.exportToBytes());
      expect(reopened.pages.single.name, 'VG 3050');
      expect(reopened.pages.single.shapes, hasLength(1));
    });

    test('Visio binary versions 1–4 reach the editor and save as VSDX',
        () async {
      final fixture = File(
        'third_party/libvisio/src/test/data/Visio5PlanWithDimensions.vsd',
      );
      if (!fixture.existsSync()) return;
      final source = fixture.readAsBytesSync();

      for (var version = 1; version <= 4; version++) {
        final controller = EditorController();
        try {
          await controller.openBytes(
            _withLegacyVisioVersion(source, version),
            name: 'legacy-$version.vsd',
          );
          expect(controller.error, isNull, reason: 'version $version open');
          expect(controller.importedFromVsd, isTrue);
          expect(controller.currentPage?.shapes, isNotEmpty);

          final reopened = const DocumentParser().parse(
            controller.exportToBytes(),
          );
          expect(reopened.pages, isNotEmpty);
          expect(reopened.pages.first.shapes, isNotEmpty);
        } finally {
          controller.dispose();
        }
      }
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
