import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as raster;
import 'package:visioeditor/render/image_cache.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('image cache decodes TIFF ForeignData through PNG fallback', () async {
    final sourceImage = raster.Image(width: 2, height: 1)
      ..setPixelRgba(0, 0, 255, 0, 0, 255)
      ..setPixelRgba(1, 0, 0, 0, 255, 255);
    final source = VsdxImage(
      partName: '/visio/media/foreign.tif',
      bytes: Uint8List.fromList(
        raster.encodeTiff(sourceImage, singleFrame: true),
      ),
      mimeType: 'image/tiff',
    );
    final cache = VsdxImageCache();
    addTearDown(cache.dispose);

    final decoded = await cache.decode(source);

    expect(decoded, isNotNull);
    expect(decoded!.width, 2);
    expect(decoded.height, 1);
    expect(cache.lookup(source), same(decoded));
  });
}
