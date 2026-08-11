import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/render/metafile_rasterizer.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Canvas expands EMF break characters by the justified width', () async {
    final drawing = MetafileDrawing(
      minX: 0,
      minY: 0,
      maxX: 100,
      maxY: 50,
      ops: <Object>[
        const MetafileTextOp(
          text: 'A A',
          x: 0,
          y: 0,
          fontHeight: 20,
          argb: 0xff000000,
          backgroundArgb: 0xffff0000,
        ),
        const MetafileTextOp(
          text: 'A A',
          x: 0,
          y: 25,
          fontHeight: 20,
          argb: 0xff000000,
          backgroundArgb: 0xffff0000,
          justificationExtra: 20,
          justificationBreakCount: 1,
        ),
      ],
    );
    final image = await rasterizeMetafileDrawing(drawing, maxEdge: 100);
    final bytes = await image!.toByteData(format: ui.ImageByteFormat.rawRgba);

    int redWidthAt(int y) {
      var width = 0;
      for (var x = 0; x < image.width; x++) {
        final offset = (y * image.width + x) * 4;
        if (bytes!.getUint8(offset) == 255 &&
            bytes.getUint8(offset + 1) == 0 &&
            bytes.getUint8(offset + 2) == 0 &&
            bytes.getUint8(offset + 3) == 255) {
          width++;
        }
      }
      return width;
    }

    final plainWidth = redWidthAt(18);
    final justifiedWidth = redWidthAt(43);
    expect(plainWidth, greaterThan(0));
    expect(justifiedWidth - plainWidth, inInclusiveRange(18, 21));
    image.dispose();
  });
}
