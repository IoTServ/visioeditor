import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/render/metafile_rasterizer.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Canvas distinguishes EMF miter and bevel geometric pen joins',
    () async {
      final drawing = MetafileDrawing(
        minX: 0,
        minY: -4,
        maxX: 40,
        maxY: 20,
        ops: const <Object>[
          MetafilePathOp(
            points: <MetafilePoint>[
              MetafilePoint(2, 15),
              MetafilePoint(10, 2),
              MetafilePoint(18, 15),
            ],
            closed: false,
            fill: false,
            stroke: true,
            fillArgb: 0,
            strokeArgb: 0xff000000,
            strokeWidth: 6,
            strokeJoin: MetafileStrokeJoin.miter,
            strokeMiterLimit: 10,
          ),
          MetafilePathOp(
            points: <MetafilePoint>[
              MetafilePoint(22, 15),
              MetafilePoint(30, 2),
              MetafilePoint(38, 15),
            ],
            closed: false,
            fill: false,
            stroke: true,
            fillArgb: 0,
            strokeArgb: 0xff000000,
            strokeWidth: 6,
            strokeJoin: MetafileStrokeJoin.bevel,
          ),
        ],
      );
      final image = await rasterizeMetafileDrawing(drawing, maxEdge: 40);
      final bytes = await image!.toByteData(format: ui.ImageByteFormat.rawRgba);

      int alphaAt(int x, int y) =>
          bytes!.getUint8((y * image.width + x) * 4 + 3);

      expect(alphaAt(10, 2), greaterThan(alphaAt(30, 2)));
      image.dispose();
    },
  );
}
