/// OLE Property Set metadata from `\x05SummaryInformation` (MS-OLEPS).
///
/// Algorithm reference: libvisio `VSDMetaData`. Both SummaryInformation and
/// DocumentSummaryInformation are decoded so `.vsd` imports retain the same
/// metadata surface as libvisio.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'vsd_byte_reader.dart';

/// Parsed document properties from a SummaryInformation stream.
class VsdOleMetaData {
  const VsdOleMetaData({
    this.title,
    this.creator,
    this.subject,
    this.keywords,
    this.description,
    this.category,
    this.company,
    this.language,
    this.template,
  });

  final String? title;
  final String? creator;
  final String? subject;
  final String? keywords;
  final String? description;
  final String? category;
  final String? company;
  final String? language;
  final String? template;

  VsdOleMetaData merge(VsdOleMetaData? other) {
    if (other == null) return this;
    return VsdOleMetaData(
      title: other.title ?? title,
      creator: other.creator ?? creator,
      subject: other.subject ?? subject,
      keywords: other.keywords ?? keywords,
      description: other.description ?? description,
      category: other.category ?? category,
      company: other.company ?? company,
      language: other.language ?? language,
      template: other.template ?? template,
    );
  }
}

/// FMTID for the SummaryInformation property set.
const String _kSummaryFmtId = 'f29f85e0-4ff9-1068-ab91-08002b27b3d9';
const String _kDocumentSummaryFmtId = 'd5cdd502-2e9c-101b-9397-08002b2cf9ae';

const int _pidCodepage = 0x00000001;
const int _pidTitle = 0x00000002;
const int _pidSubject = 0x00000003;
const int _pidAuthor = 0x00000004;
const int _pidKeywords = 0x00000005;
const int _pidComments = 0x00000006;
const int _pidTemplate = 0x00000007;

const int _pidCategory = 0x00000002;
// libvisio intentionally reads Company from PID 5 because that is how legacy
// Visio files commonly map the field. Also accept the standard PID 15.
const int _pidLegacyCompany = 0x00000005;
const int _pidCompany = 0x0000000f;
const int _pidLanguage = 0x0000001c;

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
    final normalized = fmtId.toLowerCase();
    if (normalized != _kSummaryFmtId && normalized != _kDocumentSummaryFmtId) {
      return null;
    }
    return _readPropertySet(input, offset0, normalized);
  } catch (_) {
    return null;
  }
}

VsdOleMetaData _readPropertySet(VsdByteReader input, int offset, String fmtId) {
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
  String? keywords;
  String? description;
  String? category;
  String? company;
  String? language;
  String? template;
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
    if (fmtId == _kSummaryFmtId) {
      switch (entry.id) {
        case _pidTitle:
          title = s;
        case _pidSubject:
          subject = s;
        case _pidAuthor:
          creator = s;
        case _pidKeywords:
          keywords = s;
        case _pidComments:
          description = s;
        case _pidTemplate:
          template = _basename(s);
      }
    } else {
      switch (entry.id) {
        case _pidCategory:
          category = s;
        case _pidLegacyCompany:
        case _pidCompany:
          company = s;
        case _pidLanguage:
          language = s;
      }
    }
  }
  return VsdOleMetaData(
    title: title,
    creator: creator,
    subject: subject,
    keywords: keywords,
    description: description,
    category: category,
    company: company,
    language: language,
    template: template,
  );
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
    if (codePage == 1252) return _decodeWindows1252(data);
    return latin1.decode(data, allowInvalid: true);
  } catch (_) {
    return String.fromCharCodes(data.where((b) => b != 0));
  }
}

String _basename(String path) {
  final parts = path.split(RegExp(r'[/\\]'));
  return parts.isEmpty ? path : parts.last;
}

String _decodeWindows1252(Uint8List data) {
  const replacements = <int, int>{
    0x80: 0x20ac,
    0x82: 0x201a,
    0x83: 0x0192,
    0x84: 0x201e,
    0x85: 0x2026,
    0x86: 0x2020,
    0x87: 0x2021,
    0x88: 0x02c6,
    0x89: 0x2030,
    0x8a: 0x0160,
    0x8b: 0x2039,
    0x8c: 0x0152,
    0x8e: 0x017d,
    0x91: 0x2018,
    0x92: 0x2019,
    0x93: 0x201c,
    0x94: 0x201d,
    0x95: 0x2022,
    0x96: 0x2013,
    0x97: 0x2014,
    0x98: 0x02dc,
    0x99: 0x2122,
    0x9a: 0x0161,
    0x9b: 0x203a,
    0x9c: 0x0153,
    0x9e: 0x017e,
    0x9f: 0x0178,
  };
  return String.fromCharCodes(
    data.map((byte) => replacements[byte] ?? byte),
  );
}
