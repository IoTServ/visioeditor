import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

const _mainContentTypes = <String, String>{
  'vsdx': 'application/vnd.ms-visio.drawing.main+xml',
  'vsdm': 'application/vnd.ms-visio.drawing.macroEnabled.main+xml',
  'vstx': 'application/vnd.ms-visio.template.main+xml',
  'vstm': 'application/vnd.ms-visio.template.macroEnabled.main+xml',
  'vssx': 'application/vnd.ms-visio.stencil.main+xml',
  'vssm': 'application/vnd.ms-visio.stencil.macroEnabled.main+xml',
};

void main() {
  group('OPC Visio family content types', () {
    late Uint8List drawing;

    setUpAll(() async {
      drawing = await File('test/fixtures/test1.vsdx').readAsBytes();
    });

    for (final entry in _mainContentTypes.entries) {
      test('${entry.key} main content type survives edited round-trip', () {
        final variant = _withMainContentType(drawing, entry.value);
        final document = const DocumentParser().parse(variant);
        final page = document.pages.first;
        final shape = page.shapes.first;
        final moved = shape.copyWith(pinX: shape.pinX + 0.125);
        final edited = document.replacePage(
          0,
          page.updateShapeById(shape.id, (_) => moved),
        );

        final unchanged = const VsdxWriter(preserveUnchangedPackage: true)
            .write(originalBytes: variant, edited: document);
        expect(unchanged, variant);

        final saved = const VsdxWriter(preserveUnchangedPackage: true)
            .write(originalBytes: variant, edited: edited);
        final reopened = const DocumentParser().parse(saved);
        expect(
          reopened.pages.first.findShapeById(shape.id)!.pinX,
          closeTo(moved.pinX, 1e-6),
        );
        expect(_contentTypesXml(saved), contains(entry.value));
      });
    }
  });
}

Uint8List _withMainContentType(Uint8List bytes, String contentType) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final output = Archive();
  for (final file in archive.files) {
    if (!file.isFile) continue;
    final content = file.name == '[Content_Types].xml'
        ? utf8.encode(
            utf8.decode(file.content as List<int>).replaceFirst(
                  'application/vnd.ms-visio.drawing.main+xml',
                  contentType,
                ),
          )
        : file.content as List<int>;
    output.addFile(ArchiveFile(file.name, content.length, content));
  }
  return Uint8List.fromList(ZipEncoder().encode(output)!);
}

String _contentTypesXml(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final file = archive.files.singleWhere(
    (candidate) => candidate.name == '[Content_Types].xml',
  );
  return utf8.decode(file.content as List<int>);
}
