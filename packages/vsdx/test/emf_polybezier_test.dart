import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

/// Minimal EMF: header + POLYBEZIER16 (start + one cubic) + EOF.
Uint8List _emfWithPolyBezier16() {
  // EMR_HEADER size 88, bounds 0,0,100,100, " EMF" signature at 0x28.
  final out = BytesBuilder();
  void u32(int v) {
    final b = ByteData(4)..setUint32(0, v, Endian.little);
    out.add(b.buffer.asUint8List());
  }

  void i32(int v) {
    final b = ByteData(4)..setInt32(0, v, Endian.little);
    out.add(b.buffer.asUint8List());
  }

  void i16(int v) {
    final b = ByteData(2)..setInt16(0, v, Endian.little);
    out.add(b.buffer.asUint8List());
  }

  // Header
  u32(1); // type
  u32(88); // size
  i32(0);
  i32(0);
  i32(100);
  i32(100); // bounds
  i32(0);
  i32(0);
  i32(100);
  i32(100); // frame
  out.add([0x20, 0x45, 0x4D, 0x46]); // " EMF"
  // Pad header to 88 bytes.
  while (out.length < 88) {
    out.addByte(0);
  }

  // EMR_POLYBEZIER16: type=85, size=8+16+4+4*4=44
  // bounds + count=4 + points (0,50),(25,0),(75,100),(100,50)
  u32(85);
  u32(44);
  i32(0);
  i32(0);
  i32(100);
  i32(100);
  u32(4);
  i16(0);
  i16(50);
  i16(25);
  i16(0);
  i16(75);
  i16(100);
  i16(100);
  i16(50);

  // EMR_EOF
  u32(14);
  u32(20);
  u32(0);
  u32(16);
  u32(20);

  return Uint8List.fromList(out.toBytes());
}

void main() {
  test('EMF POLYBEZIER16 densifies into a stroked polyline', () {
    final drawing = parseMetafileDrawing(
      _emfWithPolyBezier16(),
      mimeType: 'image/x-emf',
    );
    expect(drawing, isNotNull);
    expect(drawing!.ops, isNotEmpty);
    final path = drawing.ops.whereType<MetafilePathOp>().first;
    expect(path.points.length, greaterThan(4),
        reason: 'cubic samples densify beyond the 4 control points');
    expect(path.stroke, isTrue);
  });
}
