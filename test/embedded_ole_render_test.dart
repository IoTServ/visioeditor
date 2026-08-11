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
    },
  );
}
