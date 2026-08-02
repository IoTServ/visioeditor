import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/src/parser/vsd/vsd_metadata.dart';

void main() {
  test('SummaryInformation matches libvisio metadata fields and cp1252', () {
    final meta = parseOleSummaryInformation(_propertySet(
      summary: true,
      strings: <int, List<int>>{
        2: <int>[0x80, ...ascii.encode(' title')],
        3: ascii.encode('subject'),
        4: ascii.encode('author'),
        5: ascii.encode('one;two'),
        6: ascii.encode('description'),
        7: ascii.encode(r'C:\Templates\Flow.vst'),
      },
    ));

    expect(meta, isNotNull);
    expect(meta!.title, '€ title');
    expect(meta.subject, 'subject');
    expect(meta.creator, 'author');
    expect(meta.keywords, 'one;two');
    expect(meta.description, 'description');
    expect(meta.template, 'Flow.vst');
  });

  test('DocumentSummaryInformation matches libvisio extended metadata', () {
    final meta = parseOleSummaryInformation(_propertySet(
      summary: false,
      strings: <int, List<int>>{
        2: ascii.encode('category'),
        5: ascii.encode('company'),
        28: ascii.encode('zh-CN'),
      },
    ));

    expect(meta, isNotNull);
    expect(meta!.category, 'category');
    expect(meta.company, 'company');
    expect(meta.language, 'zh-CN');
  });
}

Uint8List _propertySet({
  required bool summary,
  required Map<int, List<int>> strings,
}) {
  final values = <int, Uint8List>{
    1: _typedI2(1252),
    for (final entry in strings.entries) entry.key: _typedString(entry.value),
  };
  final ids = values.keys.toList()..sort();
  final headerLength = 8 + ids.length * 8;
  var valueOffset = headerLength;
  final offsets = <int, int>{};
  for (final id in ids) {
    offsets[id] = valueOffset;
    valueOffset += values[id]!.length;
  }

  final set = BytesBuilder(copy: false)
    ..add(_u32(valueOffset))
    ..add(_u32(ids.length));
  for (final id in ids) {
    set
      ..add(_u32(id))
      ..add(_u32(offsets[id]!));
  }
  for (final id in ids) {
    set.add(values[id]!);
  }

  final out = BytesBuilder(copy: false)
    ..add(_u16(0xfffe))
    ..add(_u16(0))
    ..add(_u32(0))
    ..add(Uint8List(16))
    ..add(_u32(1));
  if (summary) {
    out
      ..add(_u32(0xf29f85e0))
      ..add(_u16(0x4ff9))
      ..add(_u16(0x1068))
      ..add(<int>[0xab, 0x91, 0x08, 0x00, 0x2b, 0x27, 0xb3, 0xd9]);
  } else {
    out
      ..add(_u32(0xd5cdd502))
      ..add(_u16(0x2e9c))
      ..add(_u16(0x101b))
      ..add(<int>[0x93, 0x97, 0x08, 0x00, 0x2b, 0x2c, 0xf9, 0xae]);
  }
  out
    ..add(_u32(48))
    ..add(set.takeBytes());
  return out.takeBytes();
}

Uint8List _typedI2(int value) => Uint8List.fromList(<int>[
      0x02,
      0x00,
      0x00,
      0x00,
      value & 0xff,
      (value >> 8) & 0xff,
      0x00,
      0x00,
    ]);

Uint8List _typedString(List<int> bytes) {
  final data = <int>[...bytes, 0];
  while ((8 + data.length) % 4 != 0) {
    data.add(0);
  }
  return Uint8List.fromList(<int>[
    0x1e,
    0x00,
    0x00,
    0x00,
    ..._u32(bytes.length + 1),
    ...data,
  ]);
}

Uint8List _u16(int value) {
  final out = ByteData(2)..setUint16(0, value, Endian.little);
  return out.buffer.asUint8List();
}

Uint8List _u32(int value) {
  final out = ByteData(4)..setUint32(0, value, Endian.little);
  return out.buffer.asUint8List();
}
