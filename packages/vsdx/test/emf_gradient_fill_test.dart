import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';
import 'package:xml/xml.dart';

typedef _Vertex = ({int x, int y, int red, int green, int blue, int alpha});

Uint8List _pixel(int x, int y, int colorRef) {
  final out = Uint8List(20);
  ByteData.sublistView(out)
    ..setUint32(0, 15, Endian.little)
    ..setUint32(4, out.length, Endian.little)
    ..setInt32(8, x, Endian.little)
    ..setInt32(12, y, Endian.little)
    ..setUint32(16, colorRef, Endian.little);
  return out;
}

Uint8List _gradient(
  int mode,
  List<_Vertex> vertices,
  List<List<int>> meshes,
) {
  final indexStride = mode == 2 ? 12 : 8;
  final out =
      Uint8List(36 + vertices.length * 16 + meshes.length * indexStride);
  final data = ByteData.sublistView(out)
    ..setUint32(0, 118, Endian.little)
    ..setUint32(4, out.length, Endian.little)
    ..setInt32(
        8,
        vertices.map((vertex) => vertex.x).reduce((a, b) => a < b ? a : b),
        Endian.little)
    ..setInt32(
        12,
        vertices.map((vertex) => vertex.y).reduce((a, b) => a < b ? a : b),
        Endian.little)
    ..setInt32(
        16,
        vertices.map((vertex) => vertex.x).reduce((a, b) => a > b ? a : b),
        Endian.little)
    ..setInt32(
        20,
        vertices.map((vertex) => vertex.y).reduce((a, b) => a > b ? a : b),
        Endian.little)
    ..setUint32(24, vertices.length, Endian.little)
    ..setUint32(28, meshes.length, Endian.little)
    ..setUint32(32, mode, Endian.little);
  var offset = 36;
  for (final vertex in vertices) {
    data
      ..setInt32(offset, vertex.x, Endian.little)
      ..setInt32(offset + 4, vertex.y, Endian.little)
      ..setUint16(offset + 8, vertex.red, Endian.little)
      ..setUint16(offset + 10, vertex.green, Endian.little)
      ..setUint16(offset + 12, vertex.blue, Endian.little)
      ..setUint16(offset + 14, vertex.alpha, Endian.little);
    offset += 16;
  }
  for (final mesh in meshes) {
    for (var i = 0; i < mesh.length; i++) {
      data.setUint32(offset + i * 4, mesh[i], Endian.little);
    }
    offset += indexStride;
  }
  return out;
}

Uint8List _emf(List<Uint8List> records) {
  final total = 88 + records.fold<int>(0, (sum, item) => sum + item.length) + 8;
  final out = Uint8List(total);
  final data = ByteData.sublistView(out)
    ..setUint32(0, 1, Endian.little)
    ..setUint32(4, 88, Endian.little)
    ..setInt32(16, 120, Endian.little)
    ..setInt32(20, 80, Endian.little)
    ..setUint32(40, 0x464d4520, Endian.little)
    ..setUint32(44, 0x00010000, Endian.little)
    ..setUint32(48, total, Endian.little)
    ..setUint32(52, records.length + 2, Endian.little)
    ..setUint16(56, 1, Endian.little);
  var offset = 88;
  for (final record in records) {
    out.setRange(offset, offset + record.length, record);
    offset += record.length;
  }
  data.setUint32(offset, 14, Endian.little);
  data.setUint32(offset + 4, 8, Endian.little);
  return out;
}

VsdxPage _imagePage(String part) => VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 2,
      heightInches: 1,
      shapes: <VsdxShape>[
        VsdxShapeFactory.picture(
          id: 1,
          pinX: 1,
          pinY: 0.5,
          width: 2,
          height: 1,
          imagePartName: part,
        ),
      ],
    );

void main() {
  test('EMF gradient rectangles/triangles render in order and round-trip', () {
    const red = (x: 10, y: 10, red: 0xffff, green: 0, blue: 0, alpha: 0);
    const blue = (x: 50, y: 30, red: 0, green: 0, blue: 0xffff, alpha: 0x1234);
    const green = (x: 60, y: 10, red: 0, green: 0xffff, blue: 0, alpha: 0);
    const yellow =
        (x: 100, y: 30, red: 0xffff, green: 0xffff, blue: 0, alpha: 0);
    final payload = _emf(<Uint8List>[
      _pixel(1, 1, 0x000000ff),
      _gradient(0, const <_Vertex>[
        red,
        blue
      ], const <List<int>>[
        <int>[0, 1],
      ]),
      _gradient(1, const <_Vertex>[
        green,
        yellow
      ], const <List<int>>[
        <int>[0, 1],
      ]),
      _gradient(
        2,
        const <_Vertex>[
          (x: 10, y: 40, red: 0xffff, green: 0, blue: 0, alpha: 0),
          (x: 50, y: 40, red: 0, green: 0xffff, blue: 0, alpha: 0xffff),
          (x: 30, y: 70, red: 0, green: 0, blue: 0xffff, alpha: 0x8000),
        ],
        const <List<int>>[
          <int>[0, 1, 2],
        ],
      ),
      _pixel(119, 79, 0x00ff0000),
    ]);

    final drawing = parseEmfDrawing(payload)!;
    expect(drawing.ops.map((op) => op.runtimeType), <Type>[
      MetafilePixelOp,
      MetafileGradientRectOp,
      MetafileGradientRectOp,
      MetafileGradientTriangleOp,
      MetafilePixelOp,
    ]);
    final rectangles = drawing.ops.whereType<MetafileGradientRectOp>().toList();
    expect(rectangles.first.horizontal, isTrue);
    expect(rectangles.last.horizontal, isFalse);
    expect(rectangles.first.upperLeft.argb, 0xffff0000);
    expect(rectangles.first.lowerRight.argb, 0xff0000ff);
    final triangle = drawing.ops.whereType<MetafileGradientTriangleOp>().single;
    expect(triangle.second.argb, 0xff00ff00);
    expect(triangle.third.argb, 0xff0000ff);

    const part = '/visio/media/gradients.emf';
    final images = ImageRegistry.empty.withImage(VsdxImage(
      partName: part,
      bytes: payload,
      mimeType: 'image/x-emf',
    ));
    final svg = VsdxToSvgSerializer().serializePage(
      _imagePage(part),
      images: images,
    );
    expect(RegExp('<linearGradient ').allMatches(svg), hasLength(2));
    expect(
        RegExp('stroke-width="0.08"').allMatches(svg).length, greaterThan(200));
    expect(svg.indexOf('fill="#ff0000"'),
        lessThan(svg.indexOf('<linearGradient ')));
    expect(svg.lastIndexOf('fill="#0000ff"'),
        greaterThan(svg.lastIndexOf('stroke-width="0.08"')));
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
    expect(
        parseEmfDrawing(roundTripped)!
            .ops
            .whereType<MetafileGradientTriangleOp>(),
        hasLength(1));
  });
}
