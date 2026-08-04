import 'dart:convert';

import 'package:charset/charset.dart' as charset;
import 'package:cp949_codec/cp949_codec.dart' as korean;
import 'package:enough_convert/enough_convert.dart' as enough;

/// FontIX text formats used by legacy VSD5/VSD6 character runs.
enum VsdLegacyTextEncoding {
  ansi,
  symbol,
  greek,
  turkish,
  vietnamese,
  hebrew,
  arabic,
  baltic,
  russian,
  thai,
  centralEurope,
  japanese,
  korean,
  simplifiedChinese,
  traditionalChinese,
}

VsdLegacyTextEncoding vsdLegacyEncodingForCodePage(int codePage) =>
    switch (codePage & 0xff) {
      0x02 => VsdLegacyTextEncoding.symbol,
      0xa1 => VsdLegacyTextEncoding.greek,
      0xa2 => VsdLegacyTextEncoding.turkish,
      0xa3 => VsdLegacyTextEncoding.vietnamese,
      0xb1 => VsdLegacyTextEncoding.hebrew,
      0xb2 => VsdLegacyTextEncoding.arabic,
      0xba => VsdLegacyTextEncoding.baltic,
      0xcc => VsdLegacyTextEncoding.russian,
      0xde => VsdLegacyTextEncoding.thai,
      0xee => VsdLegacyTextEncoding.centralEurope,
      0x80 => VsdLegacyTextEncoding.japanese,
      0x81 => VsdLegacyTextEncoding.korean,
      0x86 => VsdLegacyTextEncoding.simplifiedChinese,
      0x88 => VsdLegacyTextEncoding.traditionalChinese,
      _ => VsdLegacyTextEncoding.ansi,
    };

/// Decode one legacy VSD character-style span using libvisio's FontIX
/// code-page mapping. Invalid byte sequences become U+FFFD so a damaged span
/// cannot abort the rest of the shape.
String decodeVsdLegacyText(
  List<int> bytes,
  VsdLegacyTextEncoding encoding,
) {
  if (bytes.isEmpty) return '';
  final out = StringBuffer();
  final pending = <int>[];

  void flush() {
    if (pending.isEmpty) return;
    out.write(_decodeVsdLegacyBytes(pending, encoding));
    pending.clear();
  }

  // libvisio handles these Visio controls before invoking a code-page
  // converter, including when the current font is Symbol.
  for (final byte in bytes) {
    if (byte == 0x0d || byte == 0x0e) {
      flush();
      out.write('\n');
    } else if (byte == 0x1e) {
      flush();
      out.writeCharCode(0x1e);
    } else {
      pending.add(byte);
    }
  }
  flush();
  return out.toString();
}

/// Decode raw Windows text bytes without applying Visio's text-stream control
/// character rules. WMF `TextOut` / `ExtTextOut` records use the same Windows
/// code pages as legacy VSD FontIX spans, but their bytes are GDI glyph data
/// rather than Visio's paragraph stream.
String decodeWindowsLegacyText(
  List<int> bytes,
  VsdLegacyTextEncoding encoding,
) =>
    bytes.isEmpty ? '' : _decodeVsdLegacyBytes(bytes, encoding);

/// Number of source bytes consumed by each decoded Windows character.
///
/// GDI `ExtTextOut` stores one advance per input byte. For double-byte CJK
/// code pages the two advances belonging to a single character must be
/// combined before replaying the Unicode string in Canvas or SVG.
List<int> windowsLegacyCharacterByteLengths(
  List<int> bytes,
  VsdLegacyTextEncoding encoding,
) {
  final isDoubleByte = switch (encoding) {
    VsdLegacyTextEncoding.japanese ||
    VsdLegacyTextEncoding.korean ||
    VsdLegacyTextEncoding.simplifiedChinese ||
    VsdLegacyTextEncoding.traditionalChinese =>
      true,
    _ => false,
  };
  if (!isDoubleByte) return List<int>.filled(bytes.length, 1);

  bool isLeadByte(int byte) => switch (encoding) {
        VsdLegacyTextEncoding.japanese =>
          (byte >= 0x81 && byte <= 0x9f) || (byte >= 0xe0 && byte <= 0xfc),
        _ => byte >= 0x81 && byte <= 0xfe,
      };

  bool isTrailByte(int byte) => switch (encoding) {
        VsdLegacyTextEncoding.japanese =>
          (byte >= 0x40 && byte <= 0x7e) || (byte >= 0x80 && byte <= 0xfc),
        VsdLegacyTextEncoding.korean => (byte >= 0x41 && byte <= 0x5a) ||
            (byte >= 0x61 && byte <= 0x7a) ||
            (byte >= 0x81 && byte <= 0xfe),
        VsdLegacyTextEncoding.traditionalChinese =>
          (byte >= 0x40 && byte <= 0x7e) || (byte >= 0xa1 && byte <= 0xfe),
        _ => byte >= 0x40 && byte <= 0xfe && byte != 0x7f,
      };

  final lengths = <int>[];
  for (var i = 0; i < bytes.length;) {
    final length = isLeadByte(bytes[i]) &&
            i + 1 < bytes.length &&
            isTrailByte(bytes[i + 1])
        ? 2
        : 1;
    lengths.add(length);
    i += length;
  }
  return lengths;
}

String _decodeVsdLegacyBytes(
  List<int> bytes,
  VsdLegacyTextEncoding encoding,
) {
  if (encoding == VsdLegacyTextEncoding.symbol) {
    return String.fromCharCodes(bytes.map(_decodeSymbolByte));
  }

  final Encoding codec = switch (encoding) {
    VsdLegacyTextEncoding.ansi => charset.windows1252,
    VsdLegacyTextEncoding.greek => charset.windows1253,
    VsdLegacyTextEncoding.turkish => charset.windows1254,
    VsdLegacyTextEncoding.vietnamese => charset.windows1258,
    VsdLegacyTextEncoding.hebrew => charset.windows1255,
    VsdLegacyTextEncoding.arabic => charset.windows1256,
    VsdLegacyTextEncoding.baltic => charset.windows1257,
    VsdLegacyTextEncoding.russian => charset.windows1251,
    VsdLegacyTextEncoding.thai => charset.windows874,
    VsdLegacyTextEncoding.centralEurope => charset.windows1250,
    VsdLegacyTextEncoding.japanese =>
      const charset.ShiftJISCodec(allowMalformed: true),
    VsdLegacyTextEncoding.korean => const korean.CP949Codec(allowInvalid: true),
    VsdLegacyTextEncoding.simplifiedChinese =>
      const charset.GbkCodec(allowMalformed: true),
    VsdLegacyTextEncoding.traditionalChinese =>
      const enough.Big5Codec(allowInvalid: true),
    VsdLegacyTextEncoding.symbol => charset.windows1252,
  };
  if (codec is charset.CodePage) {
    return codec.decode(bytes, allowInvalid: true);
  }
  return codec.decode(bytes);
}

int _decodeSymbolByte(int byte) {
  if (byte < 0x20) return 0x20;
  if (byte > 0xfe) return 0xfffd;
  return _symbolCodePoints[byte - 0x20];
}

// Microsoft Symbol font byte mapping used by Visio/libvisio.
const _symbolCodePoints = <int>[
  0x0020,
  0x0021,
  0x2200,
  0x0023,
  0x2203,
  0x0025,
  0x0026,
  0x220d,
  0x0028,
  0x0029,
  0x2217,
  0x002b,
  0x002c,
  0x2212,
  0x002e,
  0x002f,
  0x0030,
  0x0031,
  0x0032,
  0x0033,
  0x0034,
  0x0035,
  0x0036,
  0x0037,
  0x0038,
  0x0039,
  0x003a,
  0x003b,
  0x003c,
  0x003d,
  0x003e,
  0x003f,
  0x2245,
  0x0391,
  0x0392,
  0x03a7,
  0x0394,
  0x0395,
  0x03a6,
  0x0393,
  0x0397,
  0x0399,
  0x03d1,
  0x039a,
  0x039b,
  0x039c,
  0x039d,
  0x039f,
  0x03a0,
  0x0398,
  0x03a1,
  0x03a3,
  0x03a4,
  0x03a5,
  0x03c2,
  0x03a9,
  0x039e,
  0x03a8,
  0x0396,
  0x005b,
  0x2234,
  0x005d,
  0x22a5,
  0x005f,
  0xf8e5,
  0x03b1,
  0x03b2,
  0x03c7,
  0x03b4,
  0x03b5,
  0x03c6,
  0x03b3,
  0x03b7,
  0x03b9,
  0x03d5,
  0x03ba,
  0x03bb,
  0x03bc,
  0x03bd,
  0x03bf,
  0x03c0,
  0x03b8,
  0x03c1,
  0x03c3,
  0x03c4,
  0x03c5,
  0x03d6,
  0x03c9,
  0x03be,
  0x03c8,
  0x03b6,
  0x007b,
  0x007c,
  0x007d,
  0x223c,
  0x0020,
  0x0080,
  0x0081,
  0x0082,
  0x0083,
  0x0084,
  0x0085,
  0x0086,
  0x0087,
  0x0088,
  0x0089,
  0x008a,
  0x008b,
  0x008c,
  0x008d,
  0x008e,
  0x008f,
  0x0090,
  0x0091,
  0x0092,
  0x0093,
  0x0094,
  0x0095,
  0x0096,
  0x0097,
  0x0098,
  0x0099,
  0x009a,
  0x009b,
  0x009c,
  0x009d,
  0x009e,
  0x009f,
  0x20ac,
  0x03d2,
  0x2032,
  0x2264,
  0x2044,
  0x221e,
  0x0192,
  0x2663,
  0x2666,
  0x2665,
  0x2660,
  0x2194,
  0x2190,
  0x2191,
  0x2192,
  0x2193,
  0x00b0,
  0x00b1,
  0x2033,
  0x2265,
  0x00d7,
  0x221d,
  0x2202,
  0x2022,
  0x00f7,
  0x2260,
  0x2261,
  0x2248,
  0x2026,
  0x23d0,
  0x23af,
  0x21b5,
  0x2135,
  0x2111,
  0x211c,
  0x2118,
  0x2297,
  0x2295,
  0x2205,
  0x2229,
  0x222a,
  0x2283,
  0x2287,
  0x2284,
  0x2282,
  0x2286,
  0x2208,
  0x2209,
  0x2220,
  0x2207,
  0x00ae,
  0x00a9,
  0x2122,
  0x220f,
  0x221a,
  0x22c5,
  0x00ac,
  0x2227,
  0x2228,
  0x21d4,
  0x21d0,
  0x21d1,
  0x21d2,
  0x21d3,
  0x25ca,
  0x3008,
  0x00ae,
  0x00a9,
  0x2122,
  0x2211,
  0x239b,
  0x239c,
  0x239d,
  0x23a1,
  0x23a2,
  0x23a3,
  0x23a7,
  0x23a8,
  0x23a9,
  0x23aa,
  0xf8ff,
  0x3009,
  0x222b,
  0x2320,
  0x23ae,
  0x2321,
  0x239e,
  0x239f,
  0x23a0,
  0x23a4,
  0x23a5,
  0x23a6,
  0x23ab,
  0x23ac,
  0x23ad,
  0x0020,
];
