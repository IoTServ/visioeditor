import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/io/image_export.dart';
import 'package:vsdx/vsdx.dart';

Future<int> _countExactArgb(Uint8List png, int argb) async {
  final codec = await ui.instantiateImageCodec(png);
  try {
    final frame = await codec.getNextFrame();
    try {
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      final bytes = data!.buffer.asUint8List();
      final a = (argb >> 24) & 0xff;
      final r = (argb >> 16) & 0xff;
      final g = (argb >> 8) & 0xff;
      final b = argb & 0xff;
      var count = 0;
      for (var i = 0; i + 3 < bytes.length; i += 4) {
        if (bytes[i] == r &&
            bytes[i + 1] == g &&
            bytes[i + 2] == b &&
            bytes[i + 3] == a) {
          count++;
        }
      }
      return count;
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

Future<int> _argbAtPagePoint(
  Uint8List png, {
  required double pageX,
  required double pageY,
  required double pageWidth,
  required double pageHeight,
}) async {
  final codec = await ui.instantiateImageCodec(png);
  try {
    final frame = await codec.getNextFrame();
    try {
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      final bytes = data!.buffer.asUint8List();
      final x = (pageX / pageWidth * frame.image.width).round().clamp(
            0,
            frame.image.width - 1,
          );
      final y = ((pageHeight - pageY) / pageHeight * frame.image.height)
          .round()
          .clamp(0, frame.image.height - 1);
      final offset = (y * frame.image.width + x) * 4;
      return bytes[offset + 3] << 24 |
          bytes[offset] << 16 |
          bytes[offset + 1] << 8 |
          bytes[offset + 2];
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'embedded Excel OLE previews retain LibreOffice blue surfaces',
    () async {
      final source = File(
        'packages/vsdx/test/fixtures/vsd/external/visio_with_embeded.vsd',
      );
      expect(source.existsSync(), isTrue);
      final document = parseVisio(source.readAsBytesSync()).document;
      expect(document.images.all, hasLength(6));
      expect(
        document.images.all.where((image) => isOleWorkbook(image.bytes)),
        hasLength(2),
      );

      final png = await renderPageToPng(
        document.pages.first,
        theme: document.theme,
        images: document.images,
        pxPerInch: 144,
      );
      expect(png, isNotNull);
      expect(
        await _countExactArgb(png!, libreOfficeOleWorkbookBackgroundArgb),
        greaterThanOrEqualTo(200000),
      );
      final page = document.pages.first;
      final previewlessOle = page.shapes.firstWhere(
        (shape) => shape.imagePartName == '/visio/media/image5.bin',
      );
      expect(
        await _argbAtPagePoint(
          png,
          pageX: previewlessOle.pinX,
          pageY: previewlessOle.pinY,
          pageWidth: page.widthInches,
          pageHeight: page.heightInches,
        ),
        libreOfficeOleWorkbookBackgroundArgb,
        reason: 'OLE without a usable presentation stream must use the same '
            'Blue 2 fallback surface as LibreOffice',
      );
    },
  );
}
