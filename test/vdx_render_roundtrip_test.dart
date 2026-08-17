import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/io/image_export.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'VDX all-types content renders identically after VSDX synthesis',
    () async {
      final source = File(
        'packages/vsdx/test/fixtures/vdx_all_types.vdx',
      ).readAsBytesSync();
      final imported = parseVisio(source, sourceName: 'vdx_all_types.vdx');
      final reopened = parseVisio(
        imported.originalBytes,
        sourceName: 'vdx_all_types.vsdx',
      );

      // Render the real PNG and DIB/BMP payloads too. The all-types fixture is
      // our end-to-end VDX contract, so placeholder-only parity would miss a
      // changed image relationship, decoder, crop, or ForeignData transform.
      final before = await renderPageToPng(
        imported.document.pages.single,
        theme: imported.document.theme,
        images: imported.document.images,
        pxPerInch: 72,
      );
      final after = await renderPageToPng(
        reopened.document.pages.single,
        theme: reopened.document.theme,
        images: reopened.document.images,
        pxPerInch: 72,
      );

      expect(before, isNotNull);
      expect(after, isNotNull);
      expect(await _rgba(after!), orderedEquals(await _rgba(before!)));
    },
  );
}

Future<Uint8List> _rgba(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  try {
    final frame = await codec.getNextFrame();
    try {
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      return data!.buffer.asUint8List();
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}
