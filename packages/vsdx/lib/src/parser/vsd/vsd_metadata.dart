/// OLE Property Set metadata from `\x05SummaryInformation` (MS-OLEPS).
///
/// Algorithm reference: libvisio `VSDMetaData` — enough to recover
/// `dc:title` / `dc:creator` for `.vsd` → `.vsdx` export.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'vsd_byte_reader.dart';

/// Parsed document properties from a SummaryInformation stream.
class VsdOleMetaData {
  const VsdOleMetaData({this.title, this.creator, this.subject});

  final String? title;
  final String? creator;
  final String? subject;
}

/// FMTID for the SummaryInformation property set.
const String _kSummaryFmtId = 'f29f85e0-4ff9-1068-ab91-08002b27b3d9';

const int _pidCodepage = 0x00000001;
const int _pidTitle = 0x00000002;
const int _pidSubject = 0x00000003;
const int _pidAuthor = 0x00000004;

const int _vtI2 = 0x0002;
const int _vtLpstr = 0x001E;

/// Parse a `\x05SummaryInformation` (or DocumentSummaryInformation) stream.
VsdOleMetaData? parseOleSummaryInformation(Uint8List bytes) {
  if (bytes.length < 48) return null;
  try {
    final input = VsdByteReader(bytes);
    // BYTEORDER, VERSION, SystemIdentifier, CLSID, NumPropertySets
    input.skip(2 + 2 + 4 + 16 + 4);
    final data1 = input.readU32();
    final data2 = input.readU16();
    final data3 = input.readU16();
    final data4 = input.readBytes(8);
    final fmtId = '${data1.toRadixString(16).padLeft(8, '0')}-'
        '${data2.toRadixString(16).padLeft(4, '0')}-'
        '${data3.toRadixString(16).padLeft(4, '0')}-'
        '${data4[0].toRadixString(16).padLeft(2, '0')}'
        '${data4[1].toRadixString(16).padLeft(2, '0')}-'
        '${data4.sublist(2).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
    final offset0 = input.readU32();
    if (fmtId.toLowerCase() != _kSummaryFmtId) {
      // DocumentSummaryInformation uses a different FMTID; skip for now.
      return null;
    }
    return _readPropertySet(input, offset0);
  } catch (_) {
    return null;
  }
}

VsdOleMetaData _readPropertySet(VsdByteReader input, int offset) {
  input.seek(offset);
  input.skip(4); // Size
  var numProperties = input.readU32();
  final max = input.remaining ~/ 8;
  if (numProperties > max) numProperties = max;

  final idsAndOffsets = <({int id, int off})>[];
  for (var i = 0; i < numProperties; i++) {
    final id = input.readU32();
    final off = input.readU32();
    idsAndOffsets.add((id: id, off: off));
  }

  // First pass: code page (VT_I2 on PID 1).
  var codePage = 1252;
  final typedI2 = <int, int>{};
  for (var i = 0; i < idsAndOffsets.length; i++) {
    final entry = idsAndOffsets[i];
    final abs = offset + entry.off;
    if (abs + 4 > input.length) continue;
    input.seek(abs);
    final type = input.readU16();
    input.skip(2); // padding
    if (type == _vtI2) {
      typedI2[i] = input.readU16();
      if (entry.id == _pidCodepage) codePage = typedI2[i]!;
    }
  }

  String? title;
  String? creator;
  String? subject;
  for (var i = 0; i < idsAndOffsets.length; i++) {
    final entry = idsAndOffsets[i];
    final abs = offset + entry.off;
    if (abs + 4 > input.length) continue;
    input.seek(abs);
    final type = input.readU16();
    input.skip(2);
    if (type != _vtLpstr) continue;
    final s = _readCodePageString(input, codePage);
    if (s == null || s.isEmpty) continue;
    switch (entry.id) {
      case _pidTitle:
        title = s;
      case _pidSubject:
        subject = s;
      case _pidAuthor:
        creator = s;
    }
  }
  return VsdOleMetaData(title: title, creator: creator, subject: subject);
}

String? _readCodePageString(VsdByteReader input, int codePage) {
  if (input.remaining < 4) return null;
  var size = input.readU32();
  if (size > input.remaining) size = input.remaining;
  if (size == 0) return '';
  final raw = input.readBytes(size);
  // Trim trailing NULs included in the byte count.
  var end = raw.length;
  while (end > 0 && raw[end - 1] == 0) {
    end--;
  }
  final data = end == raw.length ? raw : raw.sublist(0, end);
  if (data.isEmpty) return '';
  try {
    if (codePage == 65001) {
      return utf8.decode(data, allowMalformed: true);
    }
    // windows-1252 ≈ latin1 for Western European Visio samples (é/á).
    return latin1.decode(data, allowInvalid: true);
  } catch (_) {
    return String.fromCharCodes(data.where((b) => b != 0));
  }
}
