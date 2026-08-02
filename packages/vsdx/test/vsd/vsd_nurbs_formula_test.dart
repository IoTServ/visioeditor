import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/src/parser/vsd/vsd_byte_reader.dart';
import 'package:vsdx/src/parser/vsd/vsd_parser.dart';

void main() {
  test('ShapeData master sentinel resolves the matching master row id', () {
    final local = <int, String>{1: 'local'};
    final master = <int, String>{7: 'master'};

    expect(
      vsdResolveShapeDataReference(
        dataId: 1,
        localData: local,
        masterData: master,
        masterDataId: 7,
      ),
      'local',
    );
    expect(
      vsdResolveShapeDataReference(
        dataId: 0xfffffffe,
        localData: local,
        masterData: master,
        masterDataId: 7,
      ),
      'master',
    );
    expect(
      vsdResolveShapeDataReference(
        dataId: 0xfffffffe,
        localData: local,
      ),
      isNull,
    );
  });

  test('ShapeData NURBS combines row endpoints like libvisio', () {
    final result = vsdAssembleNurbsShapeData(
      dataKnots: [1, 2],
      dataWeights: [1.25, 1.5],
      firstKnot: 0,
      secondLastKnot: 3,
      lastKnot: 4,
      firstWeight: 0.75,
      lastWeight: 2,
    );

    expect(result.knots, [0, 1, 2, 3, 4]);
    expect(result.weights, [0.75, 1.25, 1.5, 2]);
  });

  test('typed NURBS formula parameters match libvisio decoding', () {
    final bytes = BytesBuilder();

    void u8(int value) => bytes.add([value]);
    void u16(int value) {
      final data = ByteData(2)..setUint16(0, value, Endian.little);
      bytes.add(data.buffer.asUint8List());
    }

    void f64(double value) {
      final data = ByteData(8)..setFloat64(0, value, Endian.little);
      bytes.add(data.buffer.asUint8List());
    }

    // paramType 0x20 was consumed by the caller; the payload starts here.
    f64(5.5); // last knot
    u8(0x62);
    u16(4); // degree
    u8(0x62);
    u16(0); // relative X control points
    u8(0x62);
    u16(1); // local-inch Y control points
    u8(0x20);
    f64(1.25);
    u8(0x62);
    u16(2);
    u8(0x62);
    u16(3);
    u8(0x20);
    f64(0.75);
    u8(0x81);

    final data = bytes.takeBytes();
    final result = vsdReadDynamicNurbsFormula(
      VsdByteReader(data),
      firstValueType: 0x20,
      blockLength: data.length + 6,
      payloadStart: 0,
    );

    expect(result.lastKnot, 5.5);
    expect(result.degree, 4);
    expect(result.xRelative, isTrue);
    expect(result.yRelative, isFalse);
    expect(result.controlPoints.single.x, 1.25);
    expect(result.controlPoints.single.y, 2);
    expect(result.knots, [3]);
    expect(result.weights, [0.75]);
  });
}
