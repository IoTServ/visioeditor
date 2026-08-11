import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/render/metafile_rasterizer.dart';
import 'package:vsdx/vsdx.dart';

Uint8List _checkerBmp() {
  final info = ByteData(40)
    ..setUint32(0, 40, Endian.little)
    ..setInt32(4, 2, Endian.little)
    ..setInt32(8, 2, Endian.little)
    ..setUint16(12, 1, Endian.little)
    ..setUint16(14, 24, Endian.little)
    ..setUint32(20, 16, Endian.little);
  return packDibAsBmp(
    info.buffer.asUint8List(),
    Uint8List.fromList(<int>[
      0,
      0,
      0,
      255,
      255,
      255,
      0,
      0,
      255,
      255,
      255,
      0,
      0,
      0,
      0,
      0,
    ]),
  )!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Canvas distinguishes nearest and linear EMF bitmap sampling', () async {
    final bmp = _checkerBmp();
    final drawing = MetafileDrawing(
      minX: 0,
      minY: 0,
      maxX: 20,
      maxY: 10,
      ops: <Object>[
        MetafileBitmapOp(
          bmpBytes: bmp,
          pixelWidth: 2,
          pixelHeight: 2,
          destination: const MetafileRect(0, 0, 10, 10),
          filter: MetafileBitmapFilter.nearest,
        ),
        MetafileBitmapOp(
          bmpBytes: bmp,
          pixelWidth: 2,
          pixelHeight: 2,
          destination: const MetafileRect(10, 0, 20, 10),
          filter: MetafileBitmapFilter.linear,
        ),
      ],
    );
    final image = await rasterizeMetafileDrawing(drawing, maxEdge: 20);
    final bytes = await image!.toByteData(format: ui.ImageByteFormat.rawRgba);

    int intermediatePixels(int left, int right) {
      var count = 0;
      for (var y = 1; y < image.height - 1; y++) {
        for (var x = left; x < right; x++) {
          final offset = (y * image.width + x) * 4;
          for (var channel = 0; channel < 3; channel++) {
            final value = bytes!.getUint8(offset + channel);
            if (value > 0 && value < 255) {
              count++;
              break;
            }
          }
        }
      }
      return count;
    }

    expect(intermediatePixels(0, 10), 0);
    expect(intermediatePixels(10, 20), greaterThan(0));
    image.dispose();
  });
}
