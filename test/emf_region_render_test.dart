import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/render/metafile_rasterizer.dart';
import 'package:vsdx/vsdx.dart';

void _record(BytesBuilder output, int type, Uint8List payload) {
  final size = (payload.length + 11) & ~3;
  final header = ByteData(8)
    ..setUint32(0, type, Endian.little)
    ..setUint32(4, size, Endian.little);
  output.add(header.buffer.asUint8List());
  output.add(payload);
  for (var i = payload.length + 8; i < size; i++) {
    output.addByte(0);
  }
}

Uint8List _regionEmf() {
  final output = BytesBuilder();
  final header = ByteData(88)
    ..setUint32(0, 1, Endian.little)
    ..setUint32(4, 88, Endian.little)
    ..setInt32(16, 100, Endian.little)
    ..setInt32(20, 100, Endian.little)
    ..setUint32(40, 0x464d4520, Endian.little);
  output.add(header.buffer.asUint8List());

  final brush = ByteData(16)
    ..setInt32(0, 1, Endian.little)
    ..setUint32(4, 0, Endian.little)
    ..setUint32(8, 0x000000ff, Endian.little); // COLORREF red
  _record(output, 39, brush.buffer.asUint8List());
  final select = ByteData(4)..setUint32(0, 1, Endian.little);
  _record(output, 37, select.buffer.asUint8List());

  final region = ByteData(48)
    ..setUint32(0, 32, Endian.little)
    ..setUint32(4, 1, Endian.little)
    ..setUint32(8, 1, Endian.little)
    ..setUint32(12, 16, Endian.little)
    ..setInt32(16, 10, Endian.little)
    ..setInt32(20, 10, Endian.little)
    ..setInt32(24, 50, Endian.little)
    ..setInt32(28, 50, Endian.little)
    ..setInt32(32, 10, Endian.little)
    ..setInt32(36, 10, Endian.little)
    ..setInt32(40, 50, Endian.little)
    ..setInt32(44, 50, Endian.little);
  final paint = ByteData(20 + region.lengthInBytes)
    ..setInt32(0, 10, Endian.little)
    ..setInt32(4, 10, Endian.little)
    ..setInt32(8, 50, Endian.little)
    ..setInt32(12, 50, Endian.little)
    ..setUint32(16, region.lengthInBytes, Endian.little);
  paint.buffer.asUint8List().setRange(
    20,
    paint.lengthInBytes,
    region.buffer.asUint8List(),
  );
  _record(output, 74, paint.buffer.asUint8List()); // EMR_PAINTRGN
  _record(output, 14, Uint8List(0));
  return Uint8List.fromList(output.toBytes());
}

Uint8List _singleRegion(int left, int top, int right, int bottom) {
  final region = ByteData(48)
    ..setUint32(0, 32, Endian.little)
    ..setUint32(4, 1, Endian.little)
    ..setUint32(8, 1, Endian.little)
    ..setUint32(12, 16, Endian.little)
    ..setInt32(16, left, Endian.little)
    ..setInt32(20, top, Endian.little)
    ..setInt32(24, right, Endian.little)
    ..setInt32(28, bottom, Endian.little)
    ..setInt32(32, left, Endian.little)
    ..setInt32(36, top, Endian.little)
    ..setInt32(40, right, Endian.little)
    ..setInt32(44, bottom, Endian.little);
  return region.buffer.asUint8List();
}

Uint8List _regionEffectsEmf() {
  final output = BytesBuilder();
  final header = ByteData(88)
    ..setUint32(0, 1, Endian.little)
    ..setUint32(4, 88, Endian.little)
    ..setInt32(16, 100, Endian.little)
    ..setInt32(20, 100, Endian.little)
    ..setUint32(40, 0x464d4520, Endian.little);
  output.add(header.buffer.asUint8List());

  void brush(int handle, int colorRef, {bool select = false}) {
    final payload = ByteData(16)
      ..setInt32(0, handle, Endian.little)
      ..setUint32(4, 0, Endian.little)
      ..setUint32(8, colorRef, Endian.little);
    _record(output, 39, payload.buffer.asUint8List());
    if (select) {
      final selected = ByteData(4)..setUint32(0, handle, Endian.little);
      _record(output, 37, selected.buffer.asUint8List());
    }
  }

  brush(1, 0x000000ff, select: true); // red
  brush(2, 0x0000ff00); // green
  final baseRegion = _singleRegion(10, 10, 60, 60);
  final paint = ByteData(20 + baseRegion.length)
    ..setUint32(16, baseRegion.length, Endian.little);
  paint.buffer.asUint8List().setRange(20, paint.lengthInBytes, baseRegion);
  _record(output, 74, paint.buffer.asUint8List());

  final frame = ByteData(32 + baseRegion.length)
    ..setUint32(16, baseRegion.length, Endian.little)
    ..setUint32(20, 2, Endian.little)
    ..setInt32(24, 5, Endian.little)
    ..setInt32(28, 5, Endian.little);
  frame.buffer.asUint8List().setRange(32, frame.lengthInBytes, baseRegion);
  _record(output, 72, frame.buffer.asUint8List());

  final invertRegion = _singleRegion(20, 20, 40, 40);
  final invert = ByteData(20 + invertRegion.length)
    ..setUint32(16, invertRegion.length, Endian.little);
  invert.buffer.asUint8List().setRange(20, invert.lengthInBytes, invertRegion);
  _record(output, 73, invert.buffer.asUint8List());
  _record(output, 14, Uint8List(0));
  return Uint8List.fromList(output.toBytes());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Canvas rasterizer paints EMF rectangle regions', () async {
    final drawing = parseEmfDrawing(_regionEmf());
    expect(drawing, isNotNull);
    final image = await rasterizeMetafileDrawing(drawing!, maxEdge: 100);
    expect(image, isNotNull);
    final bytes = await image!.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(bytes, isNotNull);

    int argbAt(int x, int y) {
      final offset = (y * image.width + x) * 4;
      final red = bytes!.getUint8(offset);
      final green = bytes.getUint8(offset + 1);
      final blue = bytes.getUint8(offset + 2);
      final alpha = bytes.getUint8(offset + 3);
      return (alpha << 24) | (red << 16) | (green << 8) | blue;
    }

    expect(argbAt(25, 25), 0xffff0000);
    expect(argbAt(75, 75), 0x00000000);
    image.dispose();
  });

  test('Canvas rasterizer applies ROP2 invert to later paths', () async {
    const points = <MetafilePoint>[
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
        const MetafilePathOp(
          points: points,
          closed: true,
          fill: true,
          stroke: false,
          fillArgb: 0xffff0000,
          strokeArgb: 0,
          strokeWidth: 0,
        ),
        const MetafilePathOp(
          points: points,
          closed: true,
          fill: true,
          stroke: false,
          fillArgb: 0xffffffff,
          strokeArgb: 0,
          strokeWidth: 0,
          rasterOperation: MetafileRasterOperation.invert,
        ),
      ],
    );
    final image = await rasterizeMetafileDrawing(drawing, maxEdge: 20);
    final bytes = await image!.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(bytes!.getUint8(10 * 4), 0); // red channel after inversion
    expect(bytes.getUint8(10 * 4 + 1), 255);
    expect(bytes.getUint8(10 * 4 + 2), 255);
    image.dispose();
  });

  test('Canvas rasterizer paints framed and inverted EMF regions', () async {
    final drawing = parseEmfDrawing(_regionEffectsEmf())!;
    final image = await rasterizeMetafileDrawing(drawing, maxEdge: 100);
    final bytes = await image!.toByteData(format: ui.ImageByteFormat.rawRgba);

    int argbAt(int x, int y) {
      final offset = (y * image.width + x) * 4;
      return (bytes!.getUint8(offset + 3) << 24) |
          (bytes.getUint8(offset) << 16) |
          (bytes.getUint8(offset + 1) << 8) |
          bytes.getUint8(offset + 2);
    }

    expect(argbAt(5, 5), 0x00000000);
    expect(argbAt(12, 12), 0xff00ff00);
    expect(argbAt(17, 17), 0xffff0000);
    expect(argbAt(30, 30), 0xff00ffff);
    image.dispose();
  });
}
