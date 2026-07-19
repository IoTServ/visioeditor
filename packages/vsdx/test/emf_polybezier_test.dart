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

Uint8List _emfWithPolyBezier32() {
  final out = BytesBuilder();
  void u32(int v) {
    final b = ByteData(4)..setUint32(0, v, Endian.little);
    out.add(b.buffer.asUint8List());
  }

  void i32(int v) {
    final b = ByteData(4)..setInt32(0, v, Endian.little);
    out.add(b.buffer.asUint8List());
  }

  u32(1);
  u32(88);
  i32(0);
  i32(0);
  i32(100);
  i32(100);
  i32(0);
  i32(0);
  i32(100);
  i32(100);
  out.add([0x20, 0x45, 0x4D, 0x46]);
  while (out.length < 88) {
    out.addByte(0);
  }

  // EMR_POLYBEZIER: type=2, size=8+16+4+4*8=60
  u32(2);
  u32(60);
  i32(0);
  i32(0);
  i32(100);
  i32(100);
  u32(4);
  i32(0);
  i32(50);
  i32(25);
  i32(0);
  i32(75);
  i32(100);
  i32(100);
  i32(50);

  u32(14);
  u32(20);
  u32(0);
  u32(16);
  u32(20);
  return Uint8List.fromList(out.toBytes());
}

Uint8List _emfWithPolyBezierTo16() {
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

  u32(1);
  u32(88);
  i32(0);
  i32(0);
  i32(100);
  i32(100);
  i32(0);
  i32(0);
  i32(100);
  i32(100);
  out.add([0x20, 0x45, 0x4D, 0x46]);
  while (out.length < 88) {
    out.addByte(0);
  }

  // EMR_POLYLINE16 to seed current point at (0,50).
  u32(87);
  u32(36);
  i32(0);
  i32(0);
  i32(100);
  i32(100);
  u32(2);
  i16(0);
  i16(50);
  i16(0);
  i16(50);

  // EMR_POLYBEZIERTO16: type=88, count=3 → (c1,c2,end)
  u32(88);
  u32(40);
  i32(0);
  i32(0);
  i32(100);
  i32(100);
  u32(3);
  i16(25);
  i16(0);
  i16(75);
  i16(100);
  i16(100);
  i16(50);

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

  test('EMF POLYBEZIER (32-bit) densifies like POLYBEZIER16', () {
    final drawing = parseMetafileDrawing(
      _emfWithPolyBezier32(),
      mimeType: 'image/x-emf',
    );
    expect(drawing, isNotNull);
    final path = drawing!.ops.whereType<MetafilePathOp>().first;
    expect(path.points.length, greaterThan(4));
  });

  test('EMF POLYBEZIERTO16 continues from current point', () {
    final drawing = parseMetafileDrawing(
      _emfWithPolyBezierTo16(),
      mimeType: 'image/x-emf',
    );
    expect(drawing, isNotNull);
    final paths = drawing!.ops.whereType<MetafilePathOp>().toList();
    expect(paths.length, greaterThanOrEqualTo(2));
    expect(paths.last.points.length, greaterThan(3));
  });

  test('EMF POLYLINE (32-bit) and POLYLINETO16 continue from MoveTo', () {
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

    u32(1);
    u32(88);
    i32(0);
    i32(0);
    i32(100);
    i32(100);
    i32(0);
    i32(0);
    i32(100);
    i32(100);
    out.add([0x20, 0x45, 0x4D, 0x46]);
    while (out.length < 88) {
      out.addByte(0);
    }

    // EMR_POLYLINE = 4, count=2 → size 8+16+4+2*8 = 44
    u32(4);
    u32(44);
    i32(0);
    i32(0);
    i32(100);
    i32(100);
    u32(2);
    i32(0);
    i32(0);
    i32(50);
    i32(50);

    // EMR_MOVETOEX then POLYLINETO16 → size 8+16+4+2*4 = 36
    u32(27);
    u32(16);
    i32(50);
    i32(50);
    u32(89);
    u32(36);
    i32(0);
    i32(0);
    i32(100);
    i32(100);
    u32(2);
    i16(75);
    i16(25);
    i16(100);
    i16(0);

    u32(14);
    u32(20);
    u32(0);
    u32(16);
    u32(20);

    final drawing = parseMetafileDrawing(
      Uint8List.fromList(out.toBytes()),
      mimeType: 'image/x-emf',
    );
    expect(drawing, isNotNull);
    final paths = drawing!.ops.whereType<MetafilePathOp>().toList();
    expect(paths.length, greaterThanOrEqualTo(2));
    expect(paths.first.points.length, 2);
    expect(paths.last.points.first.x, 50);
    expect(paths.last.points.length, 3);
  });

  test('EMF MOVETOEX + LINETO emit a stroked segment', () {
    final out = BytesBuilder();
    void u32(int v) {
      final b = ByteData(4)..setUint32(0, v, Endian.little);
      out.add(b.buffer.asUint8List());
    }

    void i32(int v) {
      final b = ByteData(4)..setInt32(0, v, Endian.little);
      out.add(b.buffer.asUint8List());
    }

    u32(1);
    u32(88);
    i32(0);
    i32(0);
    i32(100);
    i32(100);
    i32(0);
    i32(0);
    i32(100);
    i32(100);
    out.add([0x20, 0x45, 0x4D, 0x46]);
    while (out.length < 88) {
      out.addByte(0);
    }

    // EMR_MOVETOEX = 27, size=16
    u32(27);
    u32(16);
    i32(10);
    i32(20);
    // EMR_LINETO = 54, size=16
    u32(54);
    u32(16);
    i32(90);
    i32(80);

    u32(14);
    u32(20);
    u32(0);
    u32(16);
    u32(20);

    final drawing = parseMetafileDrawing(
      Uint8List.fromList(out.toBytes()),
      mimeType: 'image/x-emf',
    );
    expect(drawing, isNotNull);
    final path = drawing!.ops.whereType<MetafilePathOp>().single;
    expect(path.points.length, 2);
    expect(path.points.first.x, 10);
    expect(path.points.first.y, 20);
    expect(path.points.last.x, 90);
    expect(path.points.last.y, 80);
    expect(path.stroke, isTrue);
  });
}
