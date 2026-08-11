import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/render/metafile_rasterizer.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Canvas applies compound EMF path clips in paint order', () async {
    const rectangle = <MetafilePoint>[
      MetafilePoint(0, 0),
      MetafilePoint(20, 0),
      MetafilePoint(20, 20),
      MetafilePoint(0, 20),
    ];
    final drawing = MetafileDrawing(
      minX: 0,
      minY: 0,
      maxX: 20,
      maxY: 20,
      ops: <Object>[
        const MetafileClipPathOp(
          points: <MetafilePoint>[
            MetafilePoint(0, 0),
            MetafilePoint(20, 0),
            MetafilePoint(0, 20),
          ],
          mode: MetafileClipCombineMode.intersect,
        ),
        const MetafileClipPathOp(
          points: <MetafilePoint>[
            MetafilePoint(2, 2),
            MetafilePoint(8, 2),
            MetafilePoint(8, 8),
            MetafilePoint(2, 8),
          ],
          mode: MetafileClipCombineMode.exclude,
        ),
        const MetafilePathOp(
          points: rectangle,
          closed: true,
          fill: true,
          stroke: false,
          fillArgb: 0xffff0000,
          strokeArgb: 0,
          strokeWidth: 0,
        ),
      ],
    );
    final image = await rasterizeMetafileDrawing(drawing, maxEdge: 20);
    final bytes = await image!.toByteData(format: ui.ImageByteFormat.rawRgba);

    int alphaAt(int x, int y) => bytes!.getUint8((y * image.width + x) * 4 + 3);

    expect(alphaAt(1, 1), 255); // Inside the triangle.
    expect(alphaAt(4, 4), 0); // Excluded by the inner region.
    expect(alphaAt(18, 18), 0); // Outside the triangle.
    image.dispose();
  });
}
