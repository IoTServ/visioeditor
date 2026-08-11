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

  test('Canvas tiles EMF DIB pattern brushes inside path bounds', () async {
    const left = <MetafilePoint>[
      MetafilePoint(0, 0),
      MetafilePoint(10, 0),
      MetafilePoint(10, 20),
      MetafilePoint(0, 20),
    ];
    const right = <MetafilePoint>[
      MetafilePoint(10, 0),
      MetafilePoint(20, 0),
      MetafilePoint(20, 20),
      MetafilePoint(10, 20),
    ];
    final drawing = MetafileDrawing(
      minX: 0,
      minY: 0,
      maxX: 20,
      maxY: 20,
      ops: <Object>[
        MetafilePathOp(
          points: left,
          closed: true,
          fill: true,
          stroke: false,
          fillArgb: 0,
          strokeArgb: 0,
          strokeWidth: 0,
          fillPatternBmpBytes: _checkerBmp(),
        ),
        MetafilePathOp(
          points: right,
          closed: true,
          fill: true,
          stroke: false,
          fillArgb: 0,
          strokeArgb: 0,
          strokeWidth: 0,
          fillPatternBmpBytes: _checkerBmp(),
          fillOriginX: 1,
        ),
      ],
    );
    final image = await rasterizeMetafileDrawing(drawing, maxEdge: 20);
    final bytes = await image!.toByteData(format: ui.ImageByteFormat.rawRgba);

    int rgbAt(int x, int y) {
      final offset = (y * image.width + x) * 4;
      return (bytes!.getUint8(offset) << 16) |
          (bytes.getUint8(offset + 1) << 8) |
          bytes.getUint8(offset + 2);
    }

    expect(rgbAt(2, 2), isNot(rgbAt(3, 2)));
    expect(rgbAt(2, 2), rgbAt(4, 2));
    expect(rgbAt(3, 2), rgbAt(5, 2));
    expect(rgbAt(2, 2), isNot(rgbAt(12, 2)));
    image.dispose();
  });
}
