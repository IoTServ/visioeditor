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
}
