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

  test('Canvas moves the clip without moving later EMF drawing', () async {
    const rectangle = <MetafilePoint>[
      MetafilePoint(0, 0),
      MetafilePoint(100, 0),
      MetafilePoint(100, 100),
      MetafilePoint(0, 100),
    ];
    const drawing = MetafileDrawing(
      minX: 0,
      minY: 0,
      maxX: 100,
      maxY: 100,
      ops: <Object>[
        MetafileClipRectOp(
          rect: MetafileRect(0, 0, 40, 100),
          mode: MetafileClipCombineMode.intersect,
        ),
        MetafileOffsetClipOp(dx: 50, dy: 0),
        MetafileTransformOp(
          m11: 1,
          m12: 0,
          m21: 0,
          m22: 1,
          dx: 10,
          dy: 0,
        ),
        MetafilePathOp(
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
    final image = await rasterizeMetafileDrawing(drawing, maxEdge: 100);
    final bytes = await image!.toByteData(format: ui.ImageByteFormat.rawRgba);

    int alphaAt(int x, int y) => bytes!.getUint8((y * image.width + x) * 4 + 3);

    expect(alphaAt(20, 50), 0, reason: 'the old clip must no longer apply');
    expect(
      alphaAt(55, 50),
      255,
      reason: 'the shifted clip stays fixed across later DC transforms',
    );
    expect(
      alphaAt(95, 50),
      0,
      reason: 'drawing outside the shifted clip stays clear',
    );
    image.dispose();
  });
}
