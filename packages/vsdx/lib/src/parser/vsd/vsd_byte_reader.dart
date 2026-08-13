/// Binary helpers for Visio document streams.
library;

import 'dart:typed_data';

import '../../core/exceptions.dart';

class VsdPointer {
  const VsdPointer({
    required this.type,
    required this.offset,
    required this.length,
    required this.format,
  });

  final int type;
  final int offset;
  final int length;
  final int format;

  bool get compressed => (format & 2) == 2;
}

class VsdChunkHeader {
  VsdChunkHeader({
    this.chunkType = 0,
    this.id = 0,
    this.list = 0,
    this.dataLength = 0,
    this.level = 0,
    this.unknown = 0,
    this.trailer = 0,
  });

  int chunkType;
  int id;
  int list;
  int dataLength;
  int level;
  int unknown;
  int trailer;
}

/// Cursor over a byte buffer with little-endian Visio reads.
class VsdByteReader {
  VsdByteReader(this.data) : _bd = ByteData.sublistView(data);

  final Uint8List data;
  final ByteData _bd;
  int offset = 0;

  int get length => data.length;
  int get remaining => data.length - offset;
  bool get isEnd => offset >= data.length;

  void seek(int pos) {
    if (pos < 0 || pos > data.length) {
      throw VsdxParseException('Seek out of range: $pos / ${data.length}');
    }
    offset = pos;
  }

  void skip(int n) {
    seek(offset + n);
  }

  int readU8() {
    if (remaining < 1) throw const VsdxParseException('Unexpected EOF (u8)');
    return data[offset++];
  }

  int readU16() {
    if (remaining < 2) throw const VsdxParseException('Unexpected EOF (u16)');
    final v = _bd.getUint16(offset, Endian.little);
    offset += 2;
    return v;
  }

  int readS16() {
    if (remaining < 2) throw const VsdxParseException('Unexpected EOF (s16)');
    final v = _bd.getInt16(offset, Endian.little);
    offset += 2;
    return v;
  }

  int readU32() {
    if (remaining < 4) throw const VsdxParseException('Unexpected EOF (u32)');
    final v = _bd.getUint32(offset, Endian.little);
    offset += 4;
    return v;
  }

  int readS32() {
    if (remaining < 4) throw const VsdxParseException('Unexpected EOF (s32)');
    final v = _bd.getInt32(offset, Endian.little);
    offset += 4;
    return v;
  }

  double readF64() {
    if (remaining < 8) throw const VsdxParseException('Unexpected EOF (f64)');
    final v = _bd.getFloat64(offset, Endian.little);
    offset += 8;
    return v;
  }

  Uint8List readBytes(int n) {
    if (n < 0 || remaining < n) {
      throw const VsdxParseException('Unexpected EOF (bytes)');
    }
    final out = data.sublist(offset, offset + n);
    offset += n;
    return out;
  }

  /// VSD6/11 pointer (18 bytes). The VSD1–5 family uses [readPointerVsd5].
  VsdPointer readPointer() {
    final type = readU32();
    skip(4);
    final off = readU32();
    final length = readU32();
    final format = readU16();
    return VsdPointer(type: type, offset: off, length: length, format: format);
  }

  /// Visio 1–5 pointer layout (algorithm reference: libvisio
  /// `VSD5Parser::readPointer`).
  VsdPointer readPointerVsd5() {
    final type = readU16() & 0xff;
    final format = readU16() & 0xff;
    skip(4);
    final off = readU32();
    final length = readU32();
    return VsdPointer(type: type, offset: off, length: length, format: format);
  }
}
