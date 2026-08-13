import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/metafile/$name').readAsBytesSync();

Uint8List _emfWithPositionedText() {
  final bytes = Uint8List(192);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, 1, Endian.little); // EMR_HEADER
  data.setUint32(4, 88, Endian.little);
  data.setInt32(8, 0, Endian.little);
  data.setInt32(12, 0, Endian.little);
  data.setInt32(16, 100, Endian.little);
  data.setInt32(20, 100, Endian.little);
  data.setUint32(40, 0x464D4520, Endian.little); // " EMF"

  const record = 88;
  data.setUint32(record, 84, Endian.little); // EMR_EXTTEXTOUTW
  data.setUint32(record + 4, 96, Endian.little);
  const text = record + 36;
  data.setInt32(text, 10, Endian.little);
  data.setInt32(text + 4, 30, Endian.little);
  data.setUint32(text + 8, 2, Endian.little);
  data.setUint32(text + 12, 76, Endian.little); // offString
  data.setUint32(text + 16, 0x2000, Endian.little); // ETO_PDY
  data.setUint32(text + 36, 80, Endian.little); // offDx
  data.setUint16(record + 76, 0x41, Endian.little);
  data.setUint16(record + 78, 0x42, Endian.little);
  data.setInt32(record + 80, 13, Endian.little);
  data.setInt32(record + 84, 3, Endian.little);
  data.setInt32(record + 88, 21, Endian.little);
  data.setInt32(record + 92, -2, Endian.little);

  data.setUint32(record + 96, 14, Endian.little); // EMR_EOF
  data.setUint32(record + 100, 8, Endian.little);
  return bytes;
}

Uint8List _emfWithTextBounds({bool empty = false}) {
  final bytes = Uint8List(192);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, 1, Endian.little); // EMR_HEADER
  data.setUint32(4, 88, Endian.little);
  data.setInt32(16, 100, Endian.little);
  data.setInt32(20, 100, Endian.little);
  data.setUint32(40, 0x464D4520, Endian.little); // " EMF"

  const record = 88;
  data.setUint32(record, 84, Endian.little); // EMR_EXTTEXTOUTW
  data.setUint32(record + 4, 96, Endian.little);
  const text = record + 36;
  data.setInt32(text, 4, Endian.little);
  data.setInt32(text + 4, 5, Endian.little);
  data.setUint32(text + 8, empty ? 0 : 1, Endian.little);
  data.setUint32(text + 12, empty ? 0 : 76, Endian.little);
  data.setUint32(text + 16, 0x0006, Endian.little); // OPAQUE | CLIPPED
  data.setInt32(text + 20, 2, Endian.little);
  data.setInt32(text + 24, 3, Endian.little);
  data.setInt32(text + 28, 11, Endian.little);
  data.setInt32(text + 32, 13, Endian.little);
  if (!empty) data.setUint16(record + 76, 0x41, Endian.little);

  data.setUint32(record + 96, 14, Endian.little); // EMR_EOF
  data.setUint32(record + 100, 8, Endian.little);
  return bytes;
}

Uint8List _emfWithStyledText() {
  final bytes = Uint8List(308);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, 1, Endian.little); // EMR_HEADER
  data.setUint32(4, 88, Endian.little);
  data.setInt32(8, 0, Endian.little);
  data.setInt32(12, 0, Endian.little);
  data.setInt32(16, 100, Endian.little);
  data.setInt32(20, 100, Endian.little);
  data.setUint32(40, 0x464D4520, Endian.little); // " EMF"

  const font = 88;
  data.setUint32(font, 82, Endian.little); // EMR_EXTCREATEFONTINDIRECTW
  data.setUint32(font + 4, 104, Endian.little);
  data.setUint32(font + 8, 1, Endian.little); // object handle
  const logFont = font + 12;
  data.setInt32(logFont, 20, Endian.little); // lfHeight
  data.setInt32(logFont + 8, 900, Endian.little); // lfEscapement
  data.setInt32(logFont + 16, 700, Endian.little); // lfWeight
  data.setUint8(logFont + 20, 1); // lfItalic
  data.setUint8(logFont + 21, 1); // lfUnderline
  data.setUint8(logFont + 22, 1); // lfStrikeOut
  for (var i = 0; i < 'Arial'.length; i++) {
    data.setUint16(logFont + 28 + i * 2, 'Arial'.codeUnitAt(i), Endian.little);
  }

  const select = 192;
  data.setUint32(select, 37, Endian.little); // EMR_SELECTOBJECT
  data.setUint32(select + 4, 12, Endian.little);
  data.setUint32(select + 8, 1, Endian.little);

  const record = 204;
  data.setUint32(record, 84, Endian.little); // EMR_EXTTEXTOUTW
  data.setUint32(record + 4, 96, Endian.little);
  const text = record + 36;
  data.setInt32(text, 10, Endian.little);
  data.setInt32(text + 4, 30, Endian.little);
  data.setUint32(text + 8, 2, Endian.little);
  data.setUint32(text + 12, 76, Endian.little); // offString
  data.setUint32(text + 36, 80, Endian.little); // offDx
  data.setUint16(record + 76, 0x41, Endian.little);
  data.setUint16(record + 78, 0x42, Endian.little);
  data.setInt32(record + 80, 13, Endian.little);
  data.setInt32(record + 84, 21, Endian.little);

  data.setUint32(300, 14, Endian.little); // EMR_EOF
  data.setUint32(304, 8, Endian.little);
  return bytes;
}

Uint8List _wmfWithEncodedText({
  required List<int> textBytes,
  required int charset,
  required List<int> advances,
  String face = 'Arial',
}) {
  final textPadding = textBytes.length.isOdd ? 1 : 0;
  final textRecordBytes =
      6 + 8 + textBytes.length + textPadding + advances.length * 2;
  const fontRecordBytes = 56;
  const selectRecordBytes = 8;
  const eofRecordBytes = 6;
  final totalBytes = 18 +
      fontRecordBytes +
      selectRecordBytes +
      textRecordBytes +
      eofRecordBytes;
  final bytes = Uint8List(totalBytes);
  final data = ByteData.sublistView(bytes);
  data.setUint16(0, 1, Endian.little); // MEMORYMETAFILE
  data.setUint16(2, 9, Endian.little); // header words
  data.setUint16(4, 0x0300, Endian.little);
  data.setUint32(6, totalBytes ~/ 2, Endian.little);
  data.setUint16(10, 1, Endian.little); // object count
  data.setUint32(12, 28, Endian.little); // largest record words

  const font = 18;
  data.setUint32(font, fontRecordBytes ~/ 2, Endian.little);
  data.setUint16(font + 4, 0x02fb, Endian.little); // CREATEFONTINDIRECT
  const logFont = font + 6;
  data.setInt16(logFont, 20, Endian.little);
  data.setUint8(logFont + 13, charset);
  for (var i = 0; i < face.length && i < 31; i++) {
    data.setUint8(logFont + 18 + i, face.codeUnitAt(i));
  }

  const select = font + fontRecordBytes;
  data.setUint32(select, selectRecordBytes ~/ 2, Endian.little);
  data.setUint16(select + 4, 0x012d, Endian.little); // SELECTOBJECT
  data.setUint16(select + 6, 0, Endian.little);

  const text = select + selectRecordBytes;
  data.setUint32(text, textRecordBytes ~/ 2, Endian.little);
  data.setUint16(text + 4, 0x0a32, Endian.little); // EXTTEXTOUT
  const textParams = text + 6;
  data.setInt16(textParams, 30, Endian.little);
  data.setInt16(textParams + 2, 10, Endian.little);
  data.setUint16(textParams + 4, textBytes.length, Endian.little);
  data.setUint16(textParams + 6, 0, Endian.little);
  bytes.setRange(textParams + 8, textParams + 8 + textBytes.length, textBytes);
  var advanceOffset = textParams + 8 + textBytes.length + textPadding;
  for (final advance in advances) {
    data.setInt16(advanceOffset, advance, Endian.little);
    advanceOffset += 2;
  }

  final eof = text + textRecordBytes;
  data.setUint32(eof, eofRecordBytes ~/ 2, Endian.little);
  return bytes;
}

Uint8List _wmfWithTextBounds({bool empty = false}) {
  final bytes = Uint8List(48);
  final data = ByteData.sublistView(bytes);
  data.setUint16(0, 1, Endian.little);
  data.setUint16(2, 9, Endian.little);
  data.setUint16(4, 0x0300, Endian.little);
  data.setUint32(6, bytes.length ~/ 2, Endian.little);
  data.setUint32(12, 12, Endian.little);

  const record = 18;
  data.setUint32(record, 12, Endian.little);
  data.setUint16(record + 4, 0x0a32, Endian.little); // EXTTEXTOUT
  const text = record + 6;
  data.setInt16(text, 5, Endian.little);
  data.setInt16(text + 2, 4, Endian.little);
  data.setUint16(text + 4, empty ? 0 : 1, Endian.little);
  data.setUint16(text + 6, 0x0006, Endian.little); // OPAQUE | CLIPPED
  data.setInt16(text + 8, 2, Endian.little);
  data.setInt16(text + 10, 3, Endian.little);
  data.setInt16(text + 12, 11, Endian.little);
  data.setInt16(text + 14, 13, Endian.little);
  if (!empty) data.setUint8(text + 16, 0x41);

  data.setUint32(42, 3, Endian.little); // EOF
  return bytes;
}

Uint8List _wmfWithPenStyle(int style) {
  final bytes = Uint8List(68);
  final data = ByteData.sublistView(bytes);
  data.setUint16(0, 1, Endian.little);
  data.setUint16(2, 9, Endian.little);
  data.setUint16(4, 0x0300, Endian.little);
  data.setUint32(6, bytes.length ~/ 2, Endian.little);
  data.setUint16(10, 1, Endian.little);
  data.setUint32(12, 8, Endian.little);

  const pen = 18;
  data.setUint32(pen, 8, Endian.little);
  data.setUint16(pen + 4, 0x02fa, Endian.little); // CREATEPENINDIRECT
  data.setUint16(pen + 6, style, Endian.little);
  data.setInt16(pen + 8, 2, Endian.little);

  const select = 34;
  data.setUint32(select, 4, Endian.little);
  data.setUint16(select + 4, 0x012d, Endian.little);

  const move = 42;
  data.setUint32(move, 5, Endian.little);
  data.setUint16(move + 4, 0x0214, Endian.little);
  data.setInt16(move + 6, 10, Endian.little);
  data.setInt16(move + 8, 2, Endian.little);

  const line = 52;
  data.setUint32(line, 5, Endian.little);
  data.setUint16(line + 4, 0x0213, Endian.little);
  data.setInt16(line + 6, 10, Endian.little);
  data.setInt16(line + 8, 30, Endian.little);
  data.setUint32(62, 3, Endian.little); // EOF
  return bytes;
}

Uint8List _wmfWithRoundRect() {
  final bytes = Uint8List(42);
  final data = ByteData.sublistView(bytes);
  data.setUint16(0, 1, Endian.little);
  data.setUint16(2, 9, Endian.little);
  data.setUint16(4, 0x0300, Endian.little);
  data.setUint32(6, bytes.length ~/ 2, Endian.little);
  data.setUint32(12, 9, Endian.little);

  const roundRect = 18;
  data.setUint32(roundRect, 9, Endian.little);
  data.setUint16(roundRect + 4, 0x061c, Endian.little); // ROUNDRECT
  data.setInt16(roundRect + 6, 8, Endian.little); // ellipse height
  data.setInt16(roundRect + 8, 12, Endian.little); // ellipse width
  data.setInt16(roundRect + 10, 50, Endian.little); // bottom
  data.setInt16(roundRect + 12, 80, Endian.little); // right
  data.setInt16(roundRect + 14, 10, Endian.little); // top
  data.setInt16(roundRect + 16, 20, Endian.little); // left
  data.setUint32(36, 3, Endian.little); // EOF
  return bytes;
}

Uint8List _emfWithExtendedPen(int style) {
  final bytes = Uint8List(192);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, 1, Endian.little); // EMR_HEADER
  data.setUint32(4, 88, Endian.little);
  data.setInt32(16, 40, Endian.little);
  data.setInt32(20, 20, Endian.little);
  data.setUint32(40, 0x464D4520, Endian.little); // " EMF"

  const pen = 88;
  data.setUint32(pen, 95, Endian.little); // EMR_EXTCREATEPEN
  data.setUint32(pen + 4, 52, Endian.little);
  const params = pen + 8;
  data.setUint32(params, 1, Endian.little); // handle
  data.setUint32(params + 20, style, Endian.little);
  data.setUint32(params + 24, 2, Endian.little);

  const select = 140;
  data.setUint32(select, 37, Endian.little);
  data.setUint32(select + 4, 12, Endian.little);
  data.setUint32(select + 8, 1, Endian.little);

  const move = 152;
  data.setUint32(move, 27, Endian.little);
  data.setUint32(move + 4, 16, Endian.little);
  data.setInt32(move + 8, 2, Endian.little);
  data.setInt32(move + 12, 10, Endian.little);

  const line = 168;
  data.setUint32(line, 54, Endian.little);
  data.setUint32(line + 4, 16, Endian.little);
  data.setInt32(line + 8, 30, Endian.little);
  data.setInt32(line + 12, 10, Endian.little);
  data.setUint32(184, 14, Endian.little); // EMR_EOF
  data.setUint32(188, 8, Endian.little);
  return bytes;
}

Uint8List _emfWithRoundRect() {
  final bytes = Uint8List(128);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, 1, Endian.little); // EMR_HEADER
  data.setUint32(4, 88, Endian.little);
  data.setInt32(16, 100, Endian.little);
  data.setInt32(20, 100, Endian.little);
  data.setUint32(40, 0x464D4520, Endian.little); // " EMF"

  const roundRect = 88;
  data.setUint32(roundRect, 44, Endian.little); // EMR_ROUNDRECT
  data.setUint32(roundRect + 4, 32, Endian.little);
  data.setInt32(roundRect + 8, 20, Endian.little);
  data.setInt32(roundRect + 12, 10, Endian.little);
  data.setInt32(roundRect + 16, 80, Endian.little);
  data.setInt32(roundRect + 20, 50, Endian.little);
  data.setUint32(roundRect + 24, 12, Endian.little); // ellipse width
  data.setUint32(roundRect + 28, 8, Endian.little); // ellipse height
  data.setUint32(120, 14, Endian.little); // EMR_EOF
  data.setUint32(124, 8, Endian.little);
  return bytes;
}

Uint8List _emfWithStockBrush(int stock) {
  final bytes = Uint8List(132);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, 1, Endian.little); // EMR_HEADER
  data.setUint32(4, 88, Endian.little);
  data.setInt32(16, 100, Endian.little);
  data.setInt32(20, 100, Endian.little);
  data.setUint32(40, 0x464D4520, Endian.little); // " EMF"

  const select = 88;
  data.setUint32(select, 37, Endian.little); // EMR_SELECTOBJECT
  data.setUint32(select + 4, 12, Endian.little);
  data.setUint32(select + 8, 0x80000000 | stock, Endian.little);

  const rectangle = 100;
  data.setUint32(rectangle, 43, Endian.little); // EMR_RECTANGLE
  data.setUint32(rectangle + 4, 24, Endian.little);
  data.setInt32(rectangle + 8, 10, Endian.little);
  data.setInt32(rectangle + 12, 10, Endian.little);
  data.setInt32(rectangle + 16, 50, Endian.little);
  data.setInt32(rectangle + 20, 50, Endian.little);
  data.setUint32(124, 14, Endian.little); // EMR_EOF
  data.setUint32(128, 8, Endian.little);
  return bytes;
}

Uint8List _wmfWithNestedDcRestore() {
  final bytes = Uint8List(146);
  final data = ByteData.sublistView(bytes);
  data.setUint16(0, 1, Endian.little);
  data.setUint16(2, 9, Endian.little);
  data.setUint16(4, 0x0300, Endian.little);
  data.setUint32(6, bytes.length ~/ 2, Endian.little);
  data.setUint16(10, 3, Endian.little);
  data.setUint32(12, 8, Endian.little);

  var offset = 18;
  void pen(int colorRef) {
    data.setUint32(offset, 8, Endian.little);
    data.setUint16(offset + 4, 0x02fa, Endian.little);
    data.setUint16(offset + 6, 0, Endian.little);
    data.setInt16(offset + 8, 1, Endian.little);
    data.setUint32(offset + 12, colorRef, Endian.little);
    offset += 16;
  }

  void select(int handle) {
    data.setUint32(offset, 4, Endian.little);
    data.setUint16(offset + 4, 0x012d, Endian.little);
    data.setUint16(offset + 6, handle, Endian.little);
    offset += 8;
  }

  void save() {
    data.setUint32(offset, 3, Endian.little);
    data.setUint16(offset + 4, 0x001e, Endian.little);
    offset += 6;
  }

  void lineTo(int x) {
    data.setUint32(offset, 5, Endian.little);
    data.setUint16(offset + 4, 0x0213, Endian.little);
    data.setInt16(offset + 6, 10, Endian.little);
    data.setInt16(offset + 8, x, Endian.little);
    offset += 10;
  }

  pen(0x00000000); // black
  pen(0x000000ff); // red
  pen(0x00ff0000); // blue
  select(0);
  data.setUint32(offset, 5, Endian.little);
  data.setUint16(offset + 4, 0x0214, Endian.little); // MOVETO
  data.setInt16(offset + 6, 10, Endian.little);
  data.setInt16(offset + 8, 0, Endian.little);
  offset += 10;
  save();
  select(1);
  save();
  select(2);
  lineTo(10);
  data.setUint32(offset, 4, Endian.little);
  data.setUint16(offset + 4, 0x0127, Endian.little); // RESTOREDC
  data.setInt16(offset + 6, -2, Endian.little);
  offset += 8;
  lineTo(20);
  data.setUint32(offset, 3, Endian.little); // EOF
  return bytes;
}

Uint8List _emfWithNestedDcRestore() {
  final bytes = Uint8List(252);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, 1, Endian.little); // EMR_HEADER
  data.setUint32(4, 88, Endian.little);
  data.setInt32(16, 40, Endian.little);
  data.setInt32(20, 20, Endian.little);
  data.setUint32(40, 0x464D4520, Endian.little); // " EMF"

  var offset = 88;
  void pen(int handle, int colorRef) {
    data.setUint32(offset, 38, Endian.little); // EMR_CREATEPEN
    data.setUint32(offset + 4, 28, Endian.little);
    data.setUint32(offset + 8, handle, Endian.little);
    data.setUint32(offset + 12, 0, Endian.little);
    data.setInt32(offset + 16, 1, Endian.little);
    data.setUint32(offset + 24, colorRef, Endian.little);
    offset += 28;
  }

  void select(int handle) {
    data.setUint32(offset, 37, Endian.little);
    data.setUint32(offset + 4, 12, Endian.little);
    data.setUint32(offset + 8, handle, Endian.little);
    offset += 12;
  }

  void save() {
    data.setUint32(offset, 33, Endian.little);
    data.setUint32(offset + 4, 8, Endian.little);
    offset += 8;
  }

  void lineTo(int x) {
    data.setUint32(offset, 54, Endian.little);
    data.setUint32(offset + 4, 16, Endian.little);
    data.setInt32(offset + 8, x, Endian.little);
    data.setInt32(offset + 12, 10, Endian.little);
    offset += 16;
  }

  pen(1, 0x000000ff); // red
  pen(2, 0x00ff0000); // blue
  data.setUint32(offset, 27, Endian.little); // EMR_MOVETOEX
  data.setUint32(offset + 4, 16, Endian.little);
  data.setInt32(offset + 8, 0, Endian.little);
  data.setInt32(offset + 12, 10, Endian.little);
  offset += 16;
  save();
  select(1);
  save();
  select(2);
  lineTo(10);
  data.setUint32(offset, 34, Endian.little); // EMR_RESTOREDC
  data.setUint32(offset + 4, 12, Endian.little);
  data.setInt32(offset + 8, -2, Endian.little);
  offset += 12;
  lineTo(20);
  data.setUint32(offset, 14, Endian.little); // EMR_EOF
  data.setUint32(offset + 4, 8, Endian.little);
  return bytes;
}

Uint8List _wmfWithArcFamily() {
  final bytes = Uint8List(134);
  final data = ByteData.sublistView(bytes);
  data.setUint16(0, 1, Endian.little);
  data.setUint16(2, 9, Endian.little);
  data.setUint16(4, 0x0300, Endian.little);
  data.setUint32(6, bytes.length ~/ 2, Endian.little);
  data.setUint16(10, 1, Endian.little);
  data.setUint32(12, 11, Endian.little);

  var offset = 18;
  data.setUint32(offset, 7, Endian.little);
  data.setUint16(offset + 4, 0x02fc, Endian.little); // CREATEBRUSHINDIRECT
  data.setUint16(offset + 6, 0, Endian.little); // BS_SOLID
  data.setUint32(offset + 8, 0x000000ff, Endian.little); // red
  offset += 14;
  data.setUint32(offset, 4, Endian.little);
  data.setUint16(offset + 4, 0x012d, Endian.little); // SELECTOBJECT
  offset += 8;

  void arcRecord(int function, int left, {bool sameEndpoints = false}) {
    data.setUint32(offset, 11, Endian.little);
    data.setUint16(offset + 4, function, Endian.little);
    data.setInt16(
      offset + 6,
      sameEndpoints ? 50 : 0,
      Endian.little,
    ); // end y
    data.setInt16(
      offset + 8,
      sameEndpoints ? left + 100 : left + 50,
      Endian.little,
    );
    data.setInt16(offset + 10, 50, Endian.little); // start y
    data.setInt16(offset + 12, left + 100, Endian.little);
    data.setInt16(offset + 14, 100, Endian.little); // bottom
    data.setInt16(offset + 16, left + 100, Endian.little); // right
    data.setInt16(offset + 18, 0, Endian.little); // top
    data.setInt16(offset + 20, left, Endian.little);
    offset += 22;
  }

  arcRecord(0x0817, 0); // ARC
  arcRecord(0x081a, 120); // PIE
  arcRecord(0x0830, 240); // CHORD
  arcRecord(0x081a, 360, sameEndpoints: true); // full PIE => ellipse
  data.setUint32(offset, 3, Endian.little); // EOF
  return bytes;
}

Uint8List _emfWithArcFamily() {
  final bytes = Uint8List(364);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, 1, Endian.little); // EMR_HEADER
  data.setUint32(4, 88, Endian.little);
  data.setInt32(16, 540, Endian.little);
  data.setInt32(20, 120, Endian.little);
  data.setUint32(40, 0x464D4520, Endian.little); // " EMF"

  var offset = 88;
  data.setUint32(offset, 39, Endian.little); // EMR_CREATEBRUSHINDIRECT
  data.setUint32(offset + 4, 24, Endian.little);
  data.setUint32(offset + 8, 1, Endian.little);
  data.setUint32(offset + 12, 0, Endian.little); // BS_SOLID
  data.setUint32(offset + 16, 0x000000ff, Endian.little); // red
  offset += 24;
  data.setUint32(offset, 37, Endian.little); // EMR_SELECTOBJECT
  data.setUint32(offset + 4, 12, Endian.little);
  data.setUint32(offset + 8, 1, Endian.little);
  offset += 12;
  data.setUint32(offset, 57, Endian.little); // EMR_SETARCDIRECTION
  data.setUint32(offset + 4, 12, Endian.little);
  data.setUint32(offset + 8, 2, Endian.little); // AD_CLOCKWISE
  offset += 12;
  data.setUint32(offset, 27, Endian.little); // EMR_MOVETOEX
  data.setUint32(offset + 4, 16, Endian.little);
  data.setInt32(offset + 8, -10, Endian.little);
  data.setInt32(offset + 12, 50, Endian.little);
  offset += 16;

  void arcRecord(int type, int left) {
    data.setUint32(offset, type, Endian.little);
    data.setUint32(offset + 4, 40, Endian.little);
    data.setInt32(offset + 8, left, Endian.little);
    data.setInt32(offset + 12, 0, Endian.little);
    data.setInt32(offset + 16, left + 100, Endian.little);
    data.setInt32(offset + 20, 100, Endian.little);
    data.setInt32(offset + 24, left + 100, Endian.little); // start x
    data.setInt32(offset + 28, 50, Endian.little); // start y
    data.setInt32(offset + 32, left + 50, Endian.little); // end x
    data.setInt32(offset + 36, 0, Endian.little); // end y
    offset += 40;
  }

  arcRecord(45, 0); // EMR_ARC
  arcRecord(55, 110); // EMR_ARCTO
  arcRecord(46, 220); // EMR_CHORD
  arcRecord(47, 330); // EMR_PIE

  data.setUint32(offset, 41, Endian.little); // EMR_ANGLEARC
  data.setUint32(offset + 4, 28, Endian.little);
  data.setInt32(offset + 8, 480, Endian.little);
  data.setInt32(offset + 12, 50, Endian.little);
  data.setUint32(offset + 16, 40, Endian.little);
  data.setFloat32(offset + 20, 0, Endian.little);
  data.setFloat32(offset + 24, 90, Endian.little);
  offset += 28;

  data.setUint32(offset, 54, Endian.little); // EMR_LINETO
  data.setUint32(offset + 4, 16, Endian.little);
  data.setInt32(offset + 8, 530, Endian.little);
  data.setInt32(offset + 12, 60, Endian.little);
  offset += 16;
  data.setUint32(offset, 14, Endian.little); // EMR_EOF
  data.setUint32(offset + 4, 8, Endian.little);
  return bytes;
}

Uint8List _emfWithRestoredArcDirection() {
  final bytes = Uint8List(168);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, 1, Endian.little); // EMR_HEADER
  data.setUint32(4, 88, Endian.little);
  data.setInt32(16, 100, Endian.little);
  data.setInt32(20, 100, Endian.little);
  data.setUint32(40, 0x464D4520, Endian.little); // " EMF"
  var offset = 88;
  data.setUint32(offset, 33, Endian.little); // EMR_SAVEDC
  data.setUint32(offset + 4, 8, Endian.little);
  offset += 8;
  data.setUint32(offset, 57, Endian.little); // EMR_SETARCDIRECTION
  data.setUint32(offset + 4, 12, Endian.little);
  data.setUint32(offset + 8, 2, Endian.little);
  offset += 12;
  data.setUint32(offset, 34, Endian.little); // EMR_RESTOREDC
  data.setUint32(offset + 4, 12, Endian.little);
  data.setInt32(offset + 8, -1, Endian.little);
  offset += 12;
  data.setUint32(offset, 45, Endian.little); // EMR_ARC
  data.setUint32(offset + 4, 40, Endian.little);
  data.setInt32(offset + 16, 100, Endian.little);
  data.setInt32(offset + 20, 100, Endian.little);
  data.setInt32(offset + 24, 100, Endian.little);
  data.setInt32(offset + 28, 50, Endian.little);
  data.setInt32(offset + 32, 50, Endian.little);
  data.setInt32(offset + 36, 0, Endian.little);
  offset += 40;
  data.setUint32(offset, 14, Endian.little); // EMR_EOF
  data.setUint32(offset + 4, 8, Endian.little);
  return bytes;
}

Uint8List _emfAngleArcWithoutMoveTo() {
  final bytes = Uint8List(124);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, 1, Endian.little); // EMR_HEADER
  data.setUint32(4, 88, Endian.little);
  data.setInt32(16, 100, Endian.little);
  data.setInt32(20, 100, Endian.little);
  data.setUint32(40, 0x464D4520, Endian.little); // " EMF"
  const record = 88;
  data.setUint32(record, 41, Endian.little); // EMR_ANGLEARC
  data.setUint32(record + 4, 28, Endian.little);
  data.setInt32(record + 8, 50, Endian.little);
  data.setInt32(record + 12, 50, Endian.little);
  data.setUint32(record + 16, 40, Endian.little);
  data.setFloat32(record + 20, 0, Endian.little);
  data.setFloat32(record + 24, 90, Endian.little);
  data.setUint32(116, 14, Endian.little); // EMR_EOF
  data.setUint32(120, 8, Endian.little);
  return bytes;
}

Uint8List _wmfWithUpdateCpText() {
  final bytes = Uint8List(78);
  final data = ByteData.sublistView(bytes);
  data.setUint16(0, 1, Endian.little);
  data.setUint16(2, 9, Endian.little);
  data.setUint16(4, 0x0300, Endian.little);
  data.setUint32(6, bytes.length ~/ 2, Endian.little);
  data.setUint32(12, 9, Endian.little);

  const align = 18;
  data.setUint32(align, 4, Endian.little);
  data.setUint16(align + 4, 0x012e, Endian.little); // SETTEXTALIGN
  data.setUint16(align + 6, 0x0001, Endian.little); // TA_UPDATECP

  const move = 26;
  data.setUint32(move, 5, Endian.little);
  data.setUint16(move + 4, 0x0214, Endian.little); // MOVETO
  data.setInt16(move + 6, 20, Endian.little);
  data.setInt16(move + 8, 10, Endian.little);

  void writeText(int offset, int character, int advance) {
    data.setUint32(offset, 9, Endian.little);
    data.setUint16(offset + 4, 0x0a32, Endian.little); // EXTTEXTOUT
    data.setInt16(offset + 6, 999, Endian.little);
    data.setInt16(offset + 8, 999, Endian.little);
    data.setUint16(offset + 10, 1, Endian.little);
    data.setUint8(offset + 14, character);
    data.setInt16(offset + 16, advance, Endian.little);
  }

  writeText(36, 0x41, 6);
  writeText(54, 0x42, 7);
  data.setUint32(72, 3, Endian.little); // EOF
  return bytes;
}

Uint8List _emfWithUpdateCpText() {
  final bytes = Uint8List(316);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, 1, Endian.little); // EMR_HEADER
  data.setUint32(4, 88, Endian.little);
  data.setInt32(8, 0, Endian.little);
  data.setInt32(12, 0, Endian.little);
  data.setInt32(16, 100, Endian.little);
  data.setInt32(20, 100, Endian.little);
  data.setUint32(40, 0x464D4520, Endian.little); // " EMF"

  const align = 88;
  data.setUint32(align, 22, Endian.little); // EMR_SETTEXTALIGN
  data.setUint32(align + 4, 12, Endian.little);
  data.setUint32(align + 8, 1, Endian.little); // TA_UPDATECP

  const move = 100;
  data.setUint32(move, 27, Endian.little); // EMR_MOVETOEX
  data.setUint32(move + 4, 16, Endian.little);
  data.setInt32(move + 8, 10, Endian.little);
  data.setInt32(move + 12, 20, Endian.little);

  void writeText(int offset, int character, int advance) {
    data.setUint32(offset, 84, Endian.little); // EMR_EXTTEXTOUTW
    data.setUint32(offset + 4, 96, Endian.little);
    final text = offset + 36;
    data.setInt32(text, 999, Endian.little);
    data.setInt32(text + 4, 999, Endian.little);
    data.setUint32(text + 8, 1, Endian.little);
    data.setUint32(text + 12, 76, Endian.little);
    data.setUint32(text + 36, 80, Endian.little);
    data.setUint16(offset + 76, character, Endian.little);
    data.setInt32(offset + 80, advance, Endian.little);
  }

  writeText(116, 0x41, 6);
  writeText(212, 0x42, 7);
  data.setUint32(308, 14, Endian.little); // EMR_EOF
  data.setUint32(312, 8, Endian.little);
  return bytes;
}

void main() {
  group('WMF vector parse', () {
    test('Visio5 plan thumbnail has polygons and text', () {
      final d = parseWmfDrawing(_fixture('Visio5PlanWithDimensions.wmf'));
      expect(d, isNotNull);
      expect(d!.ops.whereType<MetafilePathOp>().length, greaterThan(5));
      expect(d.ops.whereType<MetafileTextOp>(), isNotEmpty);
      final areaLabel = d.ops
          .whereType<MetafileTextOp>()
          .firstWhere((op) => op.text == '80,00 sq. ft.');
      expect(
        areaLabel.advancesX,
        <double>[9, 9, 4, 9, 9, 5, 8, 9, 4, 5, 4, 4, 4],
      );
      expect(areaLabel.advancesY, isNull);
      expect(
        d.ops
            .whereType<MetafileTextOp>()
            .any((op) => op.escapementDegrees == 90),
        isTrue,
      );
      final hatch = d.ops
          .whereType<MetafilePathOp>()
          .where((op) => op.fillHatch != null)
          .toList();
      expect(hatch, isNotEmpty);
      expect(hatch.any((op) => op.fillHatch == 3), isTrue);
      expect(hatch.any((op) => op.fillArgb == 0xFF008000), isTrue);
      expect(
        hatch.any((op) => op.fillBackgroundArgb == 0xFFFFFFFF),
        isTrue,
      );
      expect(d.width, greaterThan(10));
      expect(d.height, greaterThan(10));
    });

    test('Visio6 plan thumbnail parses', () {
      final d = parseWmfDrawing(_fixture('Visio6PlanWithDimensions.wmf'));
      expect(d, isNotNull);
      expect(d!.ops, isNotEmpty);
      final bold = d.ops
          .whereType<MetafileTextOp>()
          .firstWhere((op) => op.text == 'Bold Custom Color ');
      expect(bold.fontWeight, 700);
      expect(bold.italic, isTrue);
      final vertical = d.ops
          .whereType<MetafileTextOp>()
          .firstWhere((op) => op.text == '6\'-0"');
      expect(vertical.escapementDegrees, 90);
      expect(
        d.ops.whereType<MetafileTextOp>().where((op) => op.advancesX != null),
        isNotEmpty,
      );
    });

    test('LOGFONT charset decodes Cyrillic ExtTextOut bytes', () {
      final drawing = parseWmfDrawing(_wmfWithEncodedText(
        textBytes: const <int>[0xcf, 0xf0, 0xe8, 0xe2, 0xe5, 0xf2],
        charset: 0xcc, // RUSSIAN_CHARSET / Windows-1251
        advances: const <int>[5, 5, 5, 5, 5, 5],
      ));
      final text = drawing!.ops.whereType<MetafileTextOp>().single;
      expect(text.text, 'Привет');
      expect(text.advancesX, const <double>[5, 5, 5, 5, 5, 5]);
    });

    test('LOGFONT charset combines Shift-JIS byte advances per glyph', () {
      final drawing = parseWmfDrawing(_wmfWithEncodedText(
        textBytes: const <int>[0x93, 0xfa, 0x96, 0x7b],
        charset: 0x80, // SHIFTJIS_CHARSET
        advances: const <int>[3, 4, 5, 6],
      ));
      final text = drawing!.ops.whereType<MetafileTextOp>().single;
      expect(text.text, '日本');
      expect(text.advancesX, const <double>[7, 11]);
    });

    test('Symbol face selects the Microsoft Symbol byte mapping', () {
      final drawing = parseWmfDrawing(_wmfWithEncodedText(
        textBytes: const <int>[0x41, 0x61],
        charset: 0,
        advances: const <int>[5, 5],
        face: 'Symbol',
      ));
      final text = drawing!.ops.whereType<MetafileTextOp>().single;
      expect(text.text, 'Αα');
      expect(text.advancesX, const <double>[5, 5]);
    });

    test('TA_UPDATECP uses MoveTo and advances consecutive WMF text', () {
      final drawing = parseWmfDrawing(_wmfWithUpdateCpText());
      final text = drawing!.ops.whereType<MetafileTextOp>().toList();
      expect(text, hasLength(2));
      expect((text[0].x, text[0].y), (10, 20));
      expect((text[1].x, text[1].y), (16, 20));
    });

    test('ExtTextOut retains opaque and clipping rectangles without text', () {
      for (final empty in <bool>[false, true]) {
        final drawing = parseWmfDrawing(_wmfWithTextBounds(empty: empty));
        final text = drawing!.ops.whereType<MetafileTextOp>().single;
        expect(text.text, empty ? '' : 'A');
        expect(text.backgroundArgb, 0xFFFFFFFF);
        expect(
          (
            text.opaqueRect!.left,
            text.opaqueRect!.top,
            text.opaqueRect!.right,
            text.opaqueRect!.bottom,
          ),
          (2, 3, 11, 13),
        );
        expect(text.clipRect, isNotNull);
      }
    });

    test('CREATEPENINDIRECT retains all cosmetic dash styles', () {
      const expected = <int, List<double>>{
        1: <double>[9, 3],
        2: <double>[3, 3],
        3: <double>[9, 3, 3, 3],
        4: <double>[9, 3, 3, 3, 3, 3],
      };
      for (final entry in expected.entries) {
        final drawing = parseWmfDrawing(_wmfWithPenStyle(entry.key));
        final path = drawing!.ops.whereType<MetafilePathOp>().single;
        expect(path.strokeDashPattern, entry.value);
      }
    });

    test('ROUNDRECT retains half ellipse width and height as radii', () {
      final drawing = parseWmfDrawing(_wmfWithRoundRect());
      final path = drawing!.ops.whereType<MetafilePathOp>().single;
      expect(path.points.first.x, 20);
      expect(path.points.first.y, 10);
      expect(path.cornerRadiusX, 6);
      expect(path.cornerRadiusY, 4);
    });

    test('ARC, PIE and CHORD retain projected curves and closure', () {
      final bytes = _wmfWithArcFamily();
      final drawing = parseWmfDrawing(bytes);
      final paths = drawing!.ops.whereType<MetafilePathOp>().toList();
      expect(paths, hasLength(4));

      expect(paths[0].closed, isFalse);
      expect(paths[0].fill, isFalse);
      expect(paths[0].points.first.x, closeTo(100, 1e-9));
      expect(paths[0].points.first.y, closeTo(50, 1e-9));
      expect(paths[0].points.last.x, closeTo(50, 1e-9));
      expect(paths[0].points.last.y, closeTo(0, 1e-9));
      expect(paths[0].points.every((p) => p.x >= 50 && p.y <= 50), isTrue);

      expect(paths[1].closed, isTrue);
      expect(paths[1].fill, isTrue);
      expect(paths[1].fillArgb, 0xFFFF0000);
      expect(paths[1].points.first.x, 170);
      expect(paths[1].points.first.y, 50);
      expect(paths[2].closed, isTrue);
      expect(paths[2].fill, isTrue);
      expect(paths[2].points.first.x, closeTo(340, 1e-9));
      expect(paths[3].isEllipse, isTrue,
          reason: 'WMF equal-endpoint PIE is a complete ellipse');

      const part = '/visio/media/arc-family.wmf';
      final page = VsdxPage(
        id: 0,
        name: 'P',
        widthInches: 5,
        heightInches: 2,
        shapes: <VsdxShape>[
          VsdxShapeFactory.picture(
            id: 1,
            pinX: 2.5,
            pinY: 1,
            width: 5,
            height: 1,
            imagePartName: part,
          ),
        ],
      );
      final images = ImageRegistry.empty.withImage(VsdxImage(
        partName: part,
        bytes: bytes,
        mimeType: 'image/x-wmf',
      ));
      final svg = VsdxToSvgSerializer().serializePage(page, images: images);
      expect(svg, contains('fill="#ff0000"'));
      expect(svg, contains('<ellipse cx="410" cy="50"'));
    });

    test('nested SaveDC/RestoreDC restores pen and current position', () {
      final bytes = _wmfWithNestedDcRestore();
      final drawing = parseWmfDrawing(bytes);
      final paths = drawing!.ops.whereType<MetafilePathOp>().toList();
      expect(paths, hasLength(2));
      expect(paths[0].strokeArgb, 0xFF0000FF);
      expect(paths[0].points.map((p) => p.x), <double>[0, 10]);
      expect(paths[1].strokeArgb, 0xFF000000);
      expect(paths[1].points.map((p) => p.x), <double>[0, 20]);

      const part = '/visio/media/dc-state.wmf';
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
        mimeType: 'image/x-wmf',
      ));
      final svg = VsdxToSvgSerializer().serializePage(page, images: images);
      expect(svg, contains('d="M 0 10 L 10 10"'));
      expect(svg, contains('stroke="#0000ff"'));
      expect(svg, contains('d="M 0 10 L 20 10"'));
      expect(svg, contains('stroke="#000000"'));
    });

    test('rejects random bytes', () {
      expect(parseWmfDrawing(Uint8List.fromList([1, 2, 3, 4])), isNull);
    });
  });

  group('EMF / OLE presentation', () {
    test('ExtTextOutW retains 32-bit ETO_PDY per-glyph advances', () {
      final drawing = parseEmfDrawing(_emfWithPositionedText());
      expect(drawing, isNotNull);
      final text = drawing!.ops.whereType<MetafileTextOp>().single;
      expect(text.text, 'AB');
      expect(text.advancesX, <double>[13, 21]);
      expect(text.advancesY, <double>[3, -2]);
    });

    test('ExtTextOutW retains opaque and clipping rectangles without text', () {
      for (final empty in <bool>[false, true]) {
        final drawing = parseEmfDrawing(_emfWithTextBounds(empty: empty));
        final text = drawing!.ops.whereType<MetafileTextOp>().single;
        expect(text.text, empty ? '' : 'A');
        expect(text.backgroundArgb, 0xFFFFFFFF);
        expect(
          (
            text.clipRect!.left,
            text.clipRect!.top,
            text.clipRect!.right,
            text.clipRect!.bottom,
          ),
          (2, 3, 11, 13),
        );
        expect(text.opaqueRect, isNotNull);
      }
    });

    test('ExtCreatePen retains geometric dash-dot style', () {
      final drawing = parseEmfDrawing(_emfWithExtendedPen(0x10003));
      final path = drawing!.ops.whereType<MetafilePathOp>().single;
      expect(path.strokeWidth, 2);
      expect(path.strokeDashPattern, <double>[9, 3, 3, 3]);
    });

    test('RoundRect retains half ellipse width and height as radii', () {
      final drawing = parseEmfDrawing(_emfWithRoundRect());
      final path = drawing!.ops.whereType<MetafilePathOp>().single;
      expect(path.points.first.x, 20);
      expect(path.points.first.y, 10);
      expect(path.cornerRadiusX, 6);
      expect(path.cornerRadiusY, 4);
    });

    test('arc family honours direction, closure and current position', () {
      final bytes = _emfWithArcFamily();
      final drawing = parseEmfDrawing(bytes);
      final paths = drawing!.ops.whereType<MetafilePathOp>().toList();
      expect(paths, hasLength(6));

      expect(paths[0].closed, isFalse);
      expect(paths[0].points.first.x, closeTo(100, 1e-9));
      expect(paths[0].points.first.y, closeTo(50, 1e-9));
      expect(paths[0].points.last.x, closeTo(50, 1e-9));
      expect(paths[0].points.last.y, closeTo(0, 1e-9));
      expect(paths[0].points.any((p) => p.x < 50 && p.y > 50), isTrue,
          reason: 'clockwise right-to-top arc traverses the long side');

      expect(paths[1].points.first.x, -10,
          reason: 'ARCTO connects from the current position');
      expect(paths[1].points.first.y, 50);
      expect(paths[1].points.last.x, closeTo(160, 1e-9));
      expect(paths[1].points.last.y, closeTo(0, 1e-9));
      expect(paths[2].closed, isTrue);
      expect(paths[2].fill, isTrue);
      expect(paths[2].fillArgb, 0xFFFF0000);
      expect(paths[3].closed, isTrue);
      expect(paths[3].fill, isTrue);
      expect(paths[3].points.first.x, 380,
          reason: 'PIE begins at the ellipse centre');

      expect(paths[4].points.first.x, closeTo(160, 1e-9));
      expect(paths[4].points.first.y, closeTo(0, 1e-9));
      expect(paths[4].points[1].x, closeTo(480, 1e-9));
      expect(paths[4].points[1].y, closeTo(10, 1e-9));
      expect(paths[4].points.last.x, closeTo(520, 1e-9));
      expect(paths[4].points.last.y, closeTo(50, 1e-9));
      expect(paths[5].points.first.x, closeTo(520, 1e-9),
          reason: 'ANGLEARC updates the current position');
      expect(paths[5].points.first.y, closeTo(50, 1e-9));

      const part = '/visio/media/arc-family.emf';
      final page = VsdxPage(
        id: 0,
        name: 'P',
        widthInches: 6,
        heightInches: 2,
        shapes: <VsdxShape>[
          VsdxShapeFactory.picture(
            id: 1,
            pinX: 3,
            pinY: 1,
            width: 6,
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
      expect(svg, contains('fill="#ff0000"'));
      expect(svg, contains('d="M -10 50 L 210 50'));
    });

    test('RestoreDC restores the authored arc direction', () {
      final drawing = parseEmfDrawing(_emfWithRestoredArcDirection());
      final path = drawing!.ops.whereType<MetafilePathOp>().single;
      expect(path.points.first.x, closeTo(100, 1e-9));
      expect(path.points.last.x, closeTo(50, 1e-9));
      expect(path.points.every((p) => p.x >= 50 && p.y <= 50), isTrue,
          reason: 'restored default direction uses the short upper quadrant');
    });

    test('ANGLEARC connects from the default GDI current position', () {
      final drawing = parseEmfDrawing(_emfAngleArcWithoutMoveTo());
      final path = drawing!.ops.whereType<MetafilePathOp>().single;
      expect(path.points.first.x, 0);
      expect(path.points.first.y, 0);
      expect(path.points[1].x, closeTo(90, 1e-9));
      expect(path.points[1].y, closeTo(50, 1e-9));
      expect(path.points.last.x, closeTo(50, 1e-9));
      expect(path.points.last.y, closeTo(10, 1e-9));
    });

    test('stock brushes select all LibreOffice fill colours and null', () {
      const colors = <int>[
        0xFFFFFFFF,
        0xFFC0C0C0,
        0xFF808080,
        0xFF666666,
        0xFF000000,
      ];
      for (var stock = 0; stock <= 5; stock++) {
        final drawing = parseEmfDrawing(_emfWithStockBrush(stock));
        final path = drawing!.ops.whereType<MetafilePathOp>().single;
        expect(path.fill, stock < colors.length, reason: 'stock $stock');
        if (stock < colors.length) {
          expect(path.fillArgb, colors[stock], reason: 'stock $stock');
        }
      }
    });

    test('nested SaveDC/RestoreDC restores pen and current position', () {
      final drawing = parseEmfDrawing(_emfWithNestedDcRestore());
      final paths = drawing!.ops.whereType<MetafilePathOp>().toList();
      expect(paths, hasLength(2));
      expect(paths[0].strokeArgb, 0xFF0000FF);
      expect(paths[0].points.map((p) => p.x), <double>[0, 10]);
      expect(paths[1].strokeArgb, 0xFF000000);
      expect(paths[1].points.map((p) => p.x), <double>[0, 20]);
      expect(drawing.ops.whereType<MetafileSaveDcOp>(), hasLength(2));
      expect(drawing.ops.whereType<MetafileRestoreDcOp>().single.count, 2);
    });

    test('ExtCreateFontIndirectW retains LOGFONT style and escapement', () {
      final drawing = parseEmfDrawing(_emfWithStyledText());
      expect(drawing, isNotNull);
      final text = drawing!.ops.whereType<MetafileTextOp>().single;
      expect(text.face, 'Arial');
      expect(text.fontHeight, 20);
      expect(text.fontWeight, 700);
      expect(text.italic, isTrue);
      expect(text.underline, isTrue);
      expect(text.strikeThrough, isTrue);
      expect(text.escapementDegrees, 90);
    });

    test('TA_UPDATECP uses MoveToEx and advances consecutive EMF text', () {
      final drawing = parseEmfDrawing(_emfWithUpdateCpText());
      final text = drawing!.ops.whereType<MetafileTextOp>().toList();
      expect(text, hasLength(2));
      expect((text[0].x, text[0].y), (10, 20));
      expect((text[1].x, text[1].y), (16, 20));
    });

    test('TA_UPDATECP rotates the next point with LOGFONT escapement', () {
      const op = MetafileTextOp(
        text: 'A',
        x: 10,
        y: 20,
        fontHeight: 12,
        argb: 0xFF000000,
        align: 1,
        advancesX: <double>[6],
        escapementDegrees: 90,
      );
      final next = metafileTextUpdatedCurrentPoint(op);
      expect(next.x, closeTo(10, 1e-9));
      expect(next.y, closeTo(14, 1e-9));
    });

    test('OLE OlePres EMF vector-parses from visio_with_embeded', () {
      final vsd = File('test/fixtures/vsd/external/visio_with_embeded.vsd')
          .readAsBytesSync();
      final doc = parseVisio(vsd).document;
      MetafileDrawing? drawing;
      for (final img in doc.images.all) {
        if (!img.mimeType.contains('ole')) continue;
        drawing = parseMetafileDrawing(
          img.bytes,
          mimeType: img.mimeType,
          partName: img.partName,
        );
        if (drawing != null && !drawing.isEmpty) break;
      }
      expect(drawing, isNotNull);
      expect(drawing!.ops.whereType<MetafilePathOp>(), isNotEmpty);
    });

    test('OLE workbook detection matches embedded Excel chart and sheet', () {
      final vsd = File('test/fixtures/vsd/external/visio_with_embeded.vsd')
          .readAsBytesSync();
      final doc = parseVisio(vsd).document;
      final workbookParts = doc.images.all
          .where((image) => isOleWorkbook(image.bytes))
          .map((image) => image.partName)
          .toSet();
      expect(
        workbookParts,
        containsAll(<String>[
          '/visio/media/image2.bin',
          '/visio/media/image6.bin',
        ]),
      );
    });

    test('OLE backgrounds render in SVG and survive VSDX round-trip', () {
      final vsd = File('test/fixtures/vsd/external/visio_with_embeded.vsd')
          .readAsBytesSync();
      final imported = parseVisio(vsd);
      final synthesized = const DocumentParser().parse(imported.originalBytes);
      final written = const VsdxWriter().write(
        originalBytes: imported.originalBytes,
        edited: synthesized,
      );
      final reopened = const DocumentParser().parse(written);

      expect(reopened.images.length, 6);
      expect(
        reopened.images.findByPart('/visio/media/image5.bin')?.bytes,
        synthesized.images.findByPart('/visio/media/image5.bin')?.bytes,
        reason: 'OLE payload without a presentation preview must round-trip',
      );

      final svg = VsdxToSvgSerializer().serializePage(
        reopened.pages.first,
        theme: reopened.theme,
        images: reopened.images,
      );
      expect(
        RegExp(r'fill="#729fcf"').allMatches(svg),
        hasLength(greaterThanOrEqualTo(5)),
        reason: 'two Excel previews and three preview-less OLE objects use '
            'LibreOffice Blue 2 surfaces',
      );
    });

    test('OLE Excel preview retains source-less PATCOPY fill bands', () {
      final vsd = File('test/fixtures/vsd/external/visio_with_embeded.vsd')
          .readAsBytesSync();
      final doc = parseVisio(vsd).document;
      final excelPreview = doc.images.findByPart('/visio/media/image6.bin');
      expect(excelPreview, isNotNull);
      final drawing = parseMetafileDrawing(
        excelPreview!.bytes,
        mimeType: excelPreview.mimeType,
        partName: excelPreview.partName,
      );
      expect(drawing, isNotNull);
      final fills = drawing!.ops
          .whereType<MetafilePathOp>()
          .where((path) => path.fill && !path.stroke)
          .toList();
      expect(fills, hasLength(greaterThanOrEqualTo(20)));
      expect(
        drawing.ops.whereType<MetafileClipRectOp>().any(
              (clip) => clip.mode == MetafileClipCombineMode.intersect,
            ),
        isTrue,
        reason: 'Excel preview uses an EMR_INTERSECTCLIPRECT region',
      );
      expect(
        fills.any((path) => path.fillArgb == 0xffc0c0c0),
        isTrue,
        reason: 'PATCOPY grid bands use the active light-gray GDI brush',
      );
    });

    test('OLE chart preview retains intersect and exclude clip records', () {
      final vsd = File('test/fixtures/vsd/external/visio_with_embeded.vsd')
          .readAsBytesSync();
      final doc = parseVisio(vsd).document;
      final chartPreview = doc.images.findByPart('/visio/media/image2.bin');
      expect(chartPreview, isNotNull);
      final drawing = parseMetafileDrawing(
        chartPreview!.bytes,
        mimeType: chartPreview.mimeType,
        partName: chartPreview.partName,
      );
      expect(drawing, isNotNull);
      expect(
        drawing!.ops.whereType<MetafileClipRectOp>().map((clip) => clip.mode),
        containsAll(<MetafileClipCombineMode>[
          MetafileClipCombineMode.intersect,
          MetafileClipCombineMode.exclude,
        ]),
      );
    });

    test('extractOlePresentationMetafile finds EMF', () {
      final vsd = File('test/fixtures/vsd/external/visio_with_embeded.vsd')
          .readAsBytesSync();
      final doc = parseVisio(vsd).document;
      var found = false;
      for (final img in doc.images.all) {
        if (!img.mimeType.contains('ole')) continue;
        final cfb = CompoundFile.open(img.bytes);
        for (final name in cfb.entryNames) {
          if (!name.contains('Pres')) continue;
          final data = cfb.readStream(name);
          if (data == null) continue;
          final emf = extractOlePresentationMetafile(img.bytes);
          if (emf != null && looksLikeEmf(emf)) {
            found = true;
            final d = parseEmfDrawing(emf);
            // Truncated dual-mode streams may still yield some polygons.
            expect(d == null || d.ops.isNotEmpty, isTrue);
          }
        }
      }
      expect(found, isTrue);
    });
  });

  group('parseMetafileDrawing facade', () {
    test('routes .wmf and prefers its authoritative WMFC EMF', () {
      final bytes = _fixture('Visio5PlanWithDimensions.wmf');
      final direct = parseWmfDrawing(bytes)!;
      final d = parseMetafileDrawing(
        bytes,
        mimeType: 'image/x-wmf',
        partName: '/visio/media/x.wmf',
      );
      expect(d, isNotNull);
      expect(
        d!.ops.length,
        greaterThan(direct.ops.length),
        reason: 'the embedded EMF carries more drawing operations than the '
            'lower-fidelity WMF fallback',
      );
      expect(
        d.ops.whereType<MetafileTextOp>().map((op) => op.text),
        direct.ops.whereType<MetafileTextOp>().map((op) => op.text),
      );
      expect(
        d.ops
            .whereType<MetafileTextOp>()
            .any((op) => op.escapementDegrees == 90),
        isTrue,
      );
    });
  });
}
