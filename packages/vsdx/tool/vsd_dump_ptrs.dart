import 'dart:io';

import 'package:vsdx/src/parser/vsd/cfb/compound_file.dart';
import 'package:vsdx/src/parser/vsd/vsd_byte_reader.dart';
import 'package:vsdx/src/parser/vsd/vsd_internal_stream.dart';

void dump(String name) {
  final bytes = File('test/fixtures/vsd/$name').readAsBytesSync();
  final cfb = CompoundFile.open(bytes);
  final stream = cfb.readStream('VisioDocument')!;
  print('=== $name ver=${stream[0x1A]} ===');
  final input = VsdByteReader(stream);
  input.seek(0x24);
  final trailer = input.readPointer();
  input.seek(trailer.offset);
  final raw = input.readBytes(trailer.length);
  final tbytes = vsdInflate(raw, compressed: trailer.compressed);
  final t = VsdByteReader(tbytes);
  final shift = trailer.compressed ? 4 : 0;
  t.seek(shift);
  final offset = t.readU32();
  t.seek(offset + shift - 4);
  final listSize = t.readU32();
  final pointerCount = t.readS32();
  t.skip(4);
  print('listSize=$listSize pointerCount=$pointerCount');
  for (var i = 0; i < pointerCount; i++) {
    final p = t.readPointer();
    if (p.type == 0) continue;
    print(
      '  ptr[$i] type=0x${p.type.toRadixString(16)} '
      'fmt=0x${p.format.toRadixString(16)} off=${p.offset} len=${p.length}',
    );
  }
}

void main() {
  dump('no-bgcolor.vsd');
  dump('Visio11FormatLine.vsd');
}
