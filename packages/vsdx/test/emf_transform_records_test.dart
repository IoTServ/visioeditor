import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';
import 'package:xml/xml.dart';

Uint8List _record(int type, int parameterBytes) {
  final out = Uint8List(8 + parameterBytes);
  ByteData.sublistView(out)
    ..setUint32(0, type, Endian.little)
    ..setUint32(4, out.length, Endian.little);
  return out;
}

Uint8List _sizeRecord(int type, int x, int y) {
  final out = _record(type, 8);
  ByteData.sublistView(out)
    ..setInt32(8, x, Endian.little)
    ..setInt32(12, y, Endian.little);
  return out;
}

Uint8List _modeRecord(int mode) {
  final out = _record(17, 4);
  ByteData.sublistView(out).setInt32(8, mode, Endian.little);
  return out;
}

Uint8List _scaleRecord(int type, int xNum, int xDen, int yNum, int yDen) {
  final out = _record(type, 16);
  ByteData.sublistView(out)
    ..setInt32(8, xNum, Endian.little)
    ..setInt32(12, xDen, Endian.little)
    ..setInt32(16, yNum, Endian.little)
    ..setInt32(20, yDen, Endian.little);
  return out;
}

Uint8List _pointRecord(int type, int x, int y) {
  final out = _record(type, 8);
  ByteData.sublistView(out)
    ..setInt32(8, x, Endian.little)
    ..setInt32(12, y, Endian.little);
  return out;
}

Uint8List _worldRecord(int type, List<double> matrix, {int? mode}) {
  final out = _record(type, mode == null ? 24 : 28);
  final data = ByteData.sublistView(out);
  for (var i = 0; i < matrix.length; i++) {
    data.setFloat32(8 + i * 4, matrix[i], Endian.little);
  }
  if (mode != null) data.setUint32(32, mode, Endian.little);
  return out;
}

Uint8List _emf(List<Uint8List> records) {
  final total = 88 + records.fold<int>(0, (sum, item) => sum + item.length) + 8;
  final out = Uint8List(total);
  final data = ByteData.sublistView(out)
    ..setUint32(0, 1, Endian.little)
    ..setUint32(4, 88, Endian.little)
    ..setInt32(8, -500, Endian.little)
    ..setInt32(12, -500, Endian.little)
    ..setInt32(16, 500, Endian.little)
    ..setInt32(20, 500, Endian.little)
    ..setUint32(40, 0x464d4520, Endian.little)
    ..setUint32(44, 0x00010000, Endian.little)
    ..setUint32(48, total, Endian.little)
    ..setUint32(52, records.length + 2, Endian.little)
    ..setUint16(56, 1, Endian.little)
    ..setInt32(72, 960, Endian.little)
    ..setInt32(76, 960, Endian.little)
    ..setInt32(80, 254, Endian.little)
    ..setInt32(84, 254, Endian.little);
  var offset = 88;
  for (final record in records) {
    out.setRange(offset, offset + record.length, record);
    offset += record.length;
  }
  data.setUint32(offset, 14, Endian.little);
  data.setUint32(offset + 4, 8, Endian.little);
  return out;
}

class _Matrix {
  const _Matrix(this.a, this.b, this.c, this.d, this.e, this.f);
  const _Matrix.identity() : this(1, 0, 0, 1, 0, 0);

  final double a;
  final double b;
  final double c;
  final double d;
  final double e;
  final double f;

  _Matrix multiply(_Matrix other) => _Matrix(
        a * other.a + c * other.b,
        b * other.a + d * other.b,
        a * other.c + c * other.d,
        b * other.c + d * other.d,
        a * other.e + c * other.f + e,
        b * other.e + d * other.f + f,
      );

  List<double> point(MetafilePoint point) => <double>[
        a * point.x + c * point.y + e,
        b * point.x + d * point.y + f,
      ];
}

List<List<List<double>>> _devicePaths(MetafileDrawing drawing) {
  var matrix = const _Matrix.identity();
  final stack = <_Matrix>[];
  final paths = <List<List<double>>>[];
  for (final op in drawing.ops) {
    if (op is MetafileSaveDcOp) {
      stack.add(matrix);
    } else if (op is MetafileRestoreDcOp) {
      for (var i = 0; i < op.count && stack.isNotEmpty; i++) {
        matrix = stack.removeLast();
      }
    } else if (op is MetafileTransformOp) {
      matrix = matrix.multiply(_Matrix(
        op.m11,
        op.m12,
        op.m21,
        op.m22,
        op.dx,
        op.dy,
      ));
    } else if (op is MetafilePathOp) {
      paths.add(<List<double>>[
        for (final point in op.points) matrix.point(point),
      ]);
    }
  }
  return paths;
}

VsdxPage _imagePage(String part) => VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 2,
      heightInches: 2,
      shapes: <VsdxShape>[
        VsdxShapeFactory.picture(
          id: 1,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 2,
          imagePartName: part,
        ),
      ],
    );

void main() {
  test('EMF mapping/world transforms affect drawing and survive round-trip',
      () {
    final payload = _emf(<Uint8List>[
      _modeRecord(8), // MM_ANISOTROPIC
      _sizeRecord(10, 10, 20), // window origin
      _sizeRecord(9, 100, 50), // window extent
      _sizeRecord(12, 5, 7), // viewport origin
      _sizeRecord(11, 200, -100), // viewport extent
      _pointRecord(27, 10, 20),
      _pointRecord(54, 110, 70),
      _record(33, 0), // SaveDC
      _worldRecord(35, <double>[1, 0, 0, 1, 10, 10]),
      _pointRecord(27, 10, 20),
      _pointRecord(54, 20, 30),
      _worldRecord(36, <double>[2, 0, 0, 1, 0, 0], mode: 3),
      _pointRecord(27, 10, 20),
      _pointRecord(54, 20, 30),
      (() {
        final out = _record(34, 4);
        ByteData.sublistView(out).setInt32(8, -1, Endian.little);
        return out;
      })(),
      _pointRecord(27, 10, 20),
      _pointRecord(54, 20, 30),
      _scaleRecord(31, 1, 2, 1, 2),
      _pointRecord(27, 10, 20),
      _pointRecord(54, 20, 30),
      _scaleRecord(32, 2, 1, 2, 1),
      _pointRecord(27, 10, 20),
      _pointRecord(54, 20, 30),
    ]);

    final drawing = parseEmfDrawing(payload)!;
    expect(drawing.ops.whereType<MetafileTransformOp>().length, greaterThan(6));
    final paths = _devicePaths(drawing);
    expect(paths, hasLength(6));
    expect(paths[0], <List<double>>[
      <double>[5, 7],
      <double>[205, -93],
    ]);
    expect(paths[1], <List<double>>[
      <double>[25, -13],
      <double>[45, -33],
    ]);
    expect(paths[2], <List<double>>[
      <double>[45, -13],
      <double>[85, -33],
    ]);
    expect(paths[3], <List<double>>[
      <double>[5, 7],
      <double>[25, -13],
    ]);
    expect(paths[4], <List<double>>[
      <double>[5, 7],
      <double>[15, -3],
    ]);
    expect(paths[5], <List<double>>[
      <double>[5, 7],
      <double>[10, 2],
    ]);

    const part = '/visio/media/transforms.emf';
    final images = ImageRegistry.empty.withImage(VsdxImage(
      partName: part,
      bytes: payload,
      mimeType: 'image/x-emf',
    ));
    final svg = VsdxToSvgSerializer().serializePage(
      _imagePage(part),
      images: images,
    );
    // SVG replay now coalesces consecutive DC transforms and freezes the
    // resulting device matrix per painted object. This avoids transforming an
    // already-selected clip when later mapping records change the DC.
    expect(RegExp('<g transform="matrix\\(').allMatches(svg), hasLength(6));
    expect(() => XmlDocument.parse(svg), returnsNormally);

    const parser = DocumentParser();
    const writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var document = parser.parse(blank);
    document =
        document.copyWith(images: images).replacePage(0, _imagePage(part));
    final reopened = parser.parse(writer.write(
      originalBytes: blank,
      edited: document,
    ));
    final roundTripped = reopened.images.findByPart(part)!.bytes;
    expect(roundTripped, payload);
    expect(parseEmfDrawing(roundTripped)!.ops.whereType<MetafilePathOp>(),
        hasLength(6));
  });

  test('EMF fixed map modes use header device resolution and invert Y', () {
    final payload = _emf(<Uint8List>[
      _modeRecord(6), // MM_TWIPS, 1440 units per inch
      _pointRecord(27, 0, 0),
      _pointRecord(54, 1440, 1440),
    ]);
    final paths = _devicePaths(parseEmfDrawing(payload)!);
    expect(paths.single.last[0], closeTo(96, 1e-9));
    expect(paths.single.last[1], closeTo(-96, 1e-9));
  });

  test('EMF supports every ModifyWorldTransform multiplication mode', () {
    final payload = _emf(<Uint8List>[
      _worldRecord(35, <double>[1, 0, 0, 1, 10, 0]),
      _worldRecord(36, <double>[2, 0, 0, 2, 0, 0], mode: 2),
      _pointRecord(27, 0, 0),
      _pointRecord(54, 1, 0),
      _worldRecord(36, <double>[9, 0, 0, 9, 9, 9], mode: 1),
      _pointRecord(27, 0, 0),
      _pointRecord(54, 1, 0),
      _worldRecord(36, <double>[1, 0, 0, 1, 3, 0], mode: 4),
      _pointRecord(27, 0, 0),
      _pointRecord(54, 1, 0),
      _worldRecord(36, <double>[2, 0, 0, 2, 0, 0], mode: 3),
      _pointRecord(27, 0, 0),
      _pointRecord(54, 1, 0),
    ]);
    final paths = _devicePaths(parseEmfDrawing(payload)!);
    expect(paths[0], <List<double>>[
      <double>[20, 0],
      <double>[22, 0],
    ]);
    expect(paths[1], <List<double>>[
      <double>[0, 0],
      <double>[1, 0],
    ]);
    expect(paths[2], <List<double>>[
      <double>[3, 0],
      <double>[4, 0],
    ]);
    expect(paths[3], <List<double>>[
      <double>[3, 0],
      <double>[5, 0],
    ]);
  });
}
