import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/render/metafile_rasterizer.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Canvas replays opaque GDI hatched brush foreground and background',
      () async {
    const drawing = MetafileDrawing(
      minX: 0,
      minY: 0,
      maxX: 32,
      maxY: 32,
      ops: <Object>[
        MetafilePathOp(
          points: <MetafilePoint>[
            MetafilePoint(0, 0),
            MetafilePoint(32, 0),
            MetafilePoint(32, 32),
            MetafilePoint(0, 32),
          ],
          closed: true,
          fill: true,
          stroke: false,
          fillArgb: 0xFF008000,
          strokeArgb: 0,
          strokeWidth: 1,
          fillHatch: 4,
          fillBackgroundArgb: 0xFFFFFFFF,
        ),
      ],
    );

    final image = await rasterizeMetafileDrawing(drawing, maxEdge: 64);
    expect(image, isNotNull);
    final data = await image!.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(data, isNotNull);
    final bytes = data!.buffer.asUint8List();
    var green = 0;
    var white = 0;
    for (var i = 0; i + 3 < bytes.length; i += 4) {
      if (bytes[i + 1] > bytes[i] + 20 &&
          bytes[i + 1] > bytes[i + 2] + 20 &&
          bytes[i + 3] == 255) {
        green++;
      }
      if (bytes[i] == 255 &&
          bytes[i + 1] == 255 &&
          bytes[i + 2] == 255 &&
          bytes[i + 3] == 255) {
        white++;
      }
    }
    expect(green, greaterThan(50));
    expect(white, greaterThan(500));
    image.dispose();
  });
}
