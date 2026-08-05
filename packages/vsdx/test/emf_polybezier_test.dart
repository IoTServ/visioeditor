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

  // EMR_POLYLINE16 draws independently and does not update the current point.
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

  // EMR_MOVETOEX seeds the current point used by POLYBEZIERTO16.
  u32(27);
  u32(16);
  i32(0);
  i32(50);

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

Uint8List _emfWithPolyLineFamilies() {
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

  // EMR_MOVETOEX, then the 32-bit EMR_POLYLINETO (record type 6).
  u32(27);
  u32(16);
  i32(10);
  i32(20);
  // BEGINPATH is record type 59 and must not be mistaken for POLYLINETO.
  u32(59);
  u32(8);
  // Close the deliberately empty path bracket so the following records are
  // ordinary drawing operations now that path brackets are supported.
  u32(68); // EMR_ABORTPATH
  u32(8);
  u32(6);
  u32(44);
  i32(0);
  i32(0);
  i32(100);
  i32(100);
  u32(2);
  i32(30);
  i32(30);
  i32(50);
  i32(10);

  // EMR_POLYPOLYLINE16: bounds + polygon count + total point count + counts.
  u32(90);
  u32(56);
  i32(0);
  i32(0);
  i32(100);
  i32(100);
  u32(2);
  u32(4);
  u32(2);
  u32(2);
  i16(0);
  i16(0);
  i16(20);
  i16(0);
  i16(0);
  i16(20);
  i16(20);
  i16(20);

  // EMR_POLYPOLYGON16 with two triangles.
  u32(91);
  u32(64);
  i32(0);
  i32(0);
  i32(100);
  i32(100);
  u32(2);
  u32(6);
  u32(3);
  u32(3);
  i16(30);
  i16(40);
  i16(40);
  i16(20);
  i16(50);
  i16(40);
  i16(60);
  i16(40);
  i16(70);
  i16(20);
  i16(80);
  i16(40);

  u32(14);
  u32(20);
  u32(0);
  u32(16);
  u32(20);
  return Uint8List.fromList(out.toBytes());
}

Uint8List _emfWithPolyDraw({
  required bool shortPoints,
  bool oversizedCount = false,
}) {
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

  u32(shortPoints ? 92 : 56); // EMR_POLYDRAW16 / EMR_POLYDRAW
  if (oversizedCount) {
    u32(28);
    i32(0);
    i32(0);
    i32(100);
    i32(100);
    u32(0xFFFFFFFF);

    // A valid following record must still parse after the damaged POLYDRAW.
    u32(4); // EMR_POLYLINE
    u32(44);
    i32(0);
    i32(0);
    i32(100);
    i32(100);
    u32(2);
    i32(10);
    i32(10);
    i32(90);
    i32(90);
  } else {
    u32(shortPoints ? 64 : 92);
    i32(0);
    i32(0);
    i32(100);
    i32(100);
    u32(7);
    const points = <(int, int)>[
      (10, 50),
      (30, 20),
      (50, 50),
      (60, 50),
      (70, 10),
      (90, 90),
      (100, 50),
    ];
    for (final point in points) {
      if (shortPoints) {
        i16(point.$1);
        i16(point.$2);
      } else {
        i32(point.$1);
        i32(point.$2);
      }
    }
    // Move, line, close-line; move, cubic controls/end with close on endpoint.
    out.add(<int>[0x06, 0x02, 0x03, 0x06, 0x04, 0x04, 0x05]);
    out.addByte(0); // DWORD record padding.

    // POLYDRAW updates the current point to the cubic endpoint.
    u32(54); // EMR_LINETO
    u32(16);
    i32(90);
    i32(100);
  }

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

  test('EMF POLYLINE preserves and POLYLINETO16 uses current point', () {
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

    // POLYLINE must not replace this current point.
    u32(27); // EMR_MOVETOEX
    u32(16);
    i32(5);
    i32(5);

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

    u32(54); // EMR_LINETO must still begin at (5, 5).
    u32(16);
    i32(10);
    i32(5);

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
    expect(paths.length, greaterThanOrEqualTo(3));
    expect(paths.first.points.length, 2);
    expect((paths[1].points.first.x, paths[1].points.first.y), (5, 5));
    expect(paths.last.points.first.x, 50);
    expect(paths.last.points.length, 3);
  });

  test('EMF POLYLINETO and 16-bit poly families use official layouts', () {
    final bytes = _emfWithPolyLineFamilies();
    final drawing = parseMetafileDrawing(
      bytes,
      mimeType: 'image/x-emf',
    );
    expect(drawing, isNotNull);
    final paths = drawing!.ops.whereType<MetafilePathOp>().toList();
    expect(paths, hasLength(5));

    expect(paths[0].points, hasLength(3));
    expect((paths[0].points.first.x, paths[0].points.first.y), (10, 20));
    expect((paths[0].points.last.x, paths[0].points.last.y), (50, 10));

    expect(paths[1].closed, isFalse);
    expect(paths[2].closed, isFalse);
    expect(paths[1].points.map((point) => point.x), <double>[0, 20]);
    expect(paths[2].points.map((point) => point.y), <double>[20, 20]);

    expect(paths[3].closed, isTrue);
    expect(paths[4].closed, isTrue);
    expect(paths[3].points, hasLength(3));
    expect(paths[4].points, hasLength(3));

    const part = '/visio/media/poly-families.emf';
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 2,
      heightInches: 2,
      shapes: <VsdxShape>[
        VsdxShapeFactory.picture(
          id: 1,
          pinX: 1,
          pinY: 1,
          width: 1,
          height: 1,
          imagePartName: part,
        ),
      ],
    );
    final images = ImageRegistry.empty.withImage(VsdxImage(
      partName: part,
      bytes: bytes,
      mimeType: 'image/x-emf',
    ));
    final svg = VsdxToSvgSerializer().serializePage(page, images: images);
    expect(
      RegExp(r'<path d=').allMatches(svg),
      hasLength(paths.length + 1),
      reason: 'five metafile paths plus the picture shape outline',
    );
    expect(
      RegExp(r' Z"').allMatches(svg),
      hasLength(2),
      reason: 'the two EMR_POLYPOLYGON16 paths remain closed',
    );
  });

  test('EMF POLYDRAW variants replay line, cubic, close and current point', () {
    for (final shortPoints in <bool>[false, true]) {
      final bytes = _emfWithPolyDraw(shortPoints: shortPoints);
      final drawing = parseMetafileDrawing(
        bytes,
        mimeType: 'image/x-emf',
      );
      expect(drawing, isNotNull);
      final paths = drawing!.ops.whereType<MetafilePathOp>().toList();
      expect(paths, hasLength(3));

      expect(paths[0].points, hasLength(3));
      expect(paths[0].closed, isTrue);
      expect(paths[0].fill, isFalse,
          reason: 'LibreOffice POLYDRAW uses StrokeAndFillPath(true, false)');
      expect(paths[0].stroke, isTrue);

      expect(paths[1].points.length, greaterThan(4));
      expect(paths[1].closed, isTrue);
      expect(paths[1].fill, isFalse);
      expect((paths[1].points.last.x, paths[1].points.last.y), (100, 50));

      expect(paths[2].closed, isFalse);
      expect((paths[2].points.first.x, paths[2].points.first.y), (100, 50));
      expect((paths[2].points.last.x, paths[2].points.last.y), (90, 100));
    }
  });

  test('EMF POLYDRAW reaches SVG and ignores an oversized damaged count', () {
    final bytes = _emfWithPolyDraw(shortPoints: false);
    const part = '/visio/media/polydraw.emf';
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 2,
      heightInches: 2,
      shapes: <VsdxShape>[
        VsdxShapeFactory.picture(
          id: 1,
          pinX: 1,
          pinY: 1,
          width: 1,
          height: 1,
          imagePartName: part,
        ),
      ],
    );
    final images = ImageRegistry.empty.withImage(VsdxImage(
      partName: part,
      bytes: bytes,
      mimeType: 'image/x-emf',
    ));
    final svg = VsdxToSvgSerializer().serializePage(page, images: images);
    expect(RegExp(r'<path d=').allMatches(svg), hasLength(4));
    expect(RegExp(r' Z"').allMatches(svg), hasLength(2));
    expect(
      RegExp(r'fill="none" stroke="#000000"').allMatches(svg).length,
      greaterThanOrEqualTo(3),
    );

    final damaged = parseMetafileDrawing(
      _emfWithPolyDraw(shortPoints: false, oversizedCount: true),
      mimeType: 'image/x-emf',
    );
    expect(damaged, isNotNull);
    final surviving = damaged!.ops.whereType<MetafilePathOp>().single;
    expect((surviving.points.first.x, surviving.points.first.y), (10, 10));
    expect((surviving.points.last.x, surviving.points.last.y), (90, 90));
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
