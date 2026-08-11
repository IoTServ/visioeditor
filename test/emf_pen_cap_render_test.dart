import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/render/metafile_rasterizer.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Canvas distinguishes EMF square and flat geometric pen caps', () async {
    final drawing = MetafileDrawing(
      minX: 0,
      minY: 0,
      maxX: 20,
      maxY: 20,
      ops: const <Object>[
        MetafilePathOp(
          points: <MetafilePoint>[MetafilePoint(5, 6), MetafilePoint(15, 6)],
          closed: false,
          fill: false,
          stroke: true,
          fillArgb: 0,
          strokeArgb: 0xff000000,
          strokeWidth: 4,
          strokeCap: MetafileStrokeCap.square,
        ),
        MetafilePathOp(
          points: <MetafilePoint>[MetafilePoint(5, 14), MetafilePoint(15, 14)],
          closed: false,
          fill: false,
          stroke: true,
          fillArgb: 0,
          strokeArgb: 0xff000000,
          strokeWidth: 4,
          strokeCap: MetafileStrokeCap.flat,
        ),
      ],
    );
    final image = await rasterizeMetafileDrawing(drawing, maxEdge: 20);
    final bytes = await image!.toByteData(format: ui.ImageByteFormat.rawRgba);

    int alphaAt(int x, int y) => bytes!.getUint8((y * image.width + x) * 4 + 3);

    expect(alphaAt(3, 6), greaterThan(alphaAt(3, 14)));
    expect(alphaAt(3, 14), 0);
    image.dispose();
  });
}
