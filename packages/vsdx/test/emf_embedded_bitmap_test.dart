import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  group('extractEmfEmbeddedBitmap', () {
    test('pulls DIB out of a minimal STRETCHDIBITS EMF', () {
      final emf = _minimalEmfWithDib();
      expect(_looksLikeEmfSig(emf), isTrue);
      final bmp = extractEmfEmbeddedBitmap(emf);
      expect(bmp, isNotNull);
      expect(bmp![0], 0x42); // 'B'
      expect(bmp[1], 0x4D); // 'M'
      // BITMAPINFOHEADER width/height at file offset 18/22
      final w = bmp[18] | (bmp[19] << 8) | (bmp[20] << 16) | (bmp[21] << 24);
      final h = (bmp[22] | (bmp[23] << 8) | (bmp[24] << 16) | (bmp[25] << 24));
      expect(w.abs(), 2);
      expect(h.abs(), 2);
    });

    test('returns null for non-EMF bytes', () {
      expect(
        extractEmfEmbeddedBitmap(Uint8List.fromList([1, 2, 3, 4])),
        isNull,
      );
    });

    test('short BITBLT does not read fields from the following record', () {
      final emf = Uint8List(88 + 72 + 8);
      _setU32(emf, 0, 1);
      _setU32(emf, 4, 88);
      emf[0x28] = 0x20;
      emf[0x29] = 0x45;
      emf[0x2a] = 0x4d;
      emf[0x2b] = 0x46;
      _setU32(emf, 88, 0x4c);
      _setU32(emf, 92, 72);
      _setU32(emf, 160, 0x0e);
      _setU32(emf, 164, 8);
      expect(extractEmfEmbeddedBitmap(emf), isNull);
    });
  });

  group('VsdxImage.foreignTypeFor', () {
    test('maps object/ole to Object', () {
      expect(
        VsdxImage.foreignTypeFor(
          mimeType: 'object/ole',
          partName: '/visio/media/image1.bin',
        ),
        'Object',
      );
    });
  });
}

bool _looksLikeEmfSig(Uint8List b) =>
    b.length > 0x2B &&
    b[0x28] == 0x20 &&
    b[0x29] == 0x45 &&
    b[0x2A] == 0x4D &&
    b[0x2B] == 0x46;

/// Build a tiny EMF: HEADER + STRETCHDIBITS(with 2×2 DIB) + EOF.
Uint8List _minimalEmfWithDib() {
  final dib = _tinyRgbDib(2, 2);
  // STRETCHDIBITS record: Type+Size + padding so fallback scan finds biSize=40.
  final stretchBody = BytesBuilder();
  // After Type(4)+Size(4) the walker scans from +8 for BITMAPINFOHEADER.
  stretchBody.add(Uint8List(40)); // padding / fake bounds+fields
  stretchBody.add(dib);
  final stretchPayload = stretchBody.toBytes();
  final stretchSize = 8 + stretchPayload.length;
  // Align size to 4 bytes
  final stretchPad = (4 - (stretchSize % 4)) % 4;

  final out = BytesBuilder();
  // EMR_HEADER size 88 — signature at absolute 0x28.
  final header = Uint8List(88);
  _setU32(header, 0, 1); // EMR_HEADER
  _setU32(header, 4, 88);
  header[0x28] = 0x20;
  header[0x29] = 0x45;
  header[0x2A] = 0x4D;
  header[0x2B] = 0x46;
  out.add(header);

  final stretch = Uint8List(stretchSize + stretchPad);
  _setU32(stretch, 0, 0x51); // EMR_STRETCHDIBITS
  _setU32(stretch, 4, stretch.length);
  stretch.setRange(8, 8 + stretchPayload.length, stretchPayload);
  out.add(stretch);

  // EMR_EOF
  final eof = Uint8List(20);
  _setU32(eof, 0, 0x0e);
  _setU32(eof, 4, 20);
  out.add(eof);

  return out.toBytes();
}

Uint8List _tinyRgbDib(int w, int h) {
  // BITMAPINFOHEADER (40) + 24bpp pixels, rows padded to 4 bytes.
  final row = ((w * 3 + 3) ~/ 4) * 4;
  final bits = row * h;
  final dib = Uint8List(40 + bits);
  _setU32(dib, 0, 40);
  _setI32(dib, 4, w);
  _setI32(dib, 8, h);
  dib[12] = 1; // planes
  dib[14] = 24; // bitCount
  // Blue pixel pattern
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final o = 40 + y * row + x * 3;
      dib[o] = 0xff;
      dib[o + 1] = 0x00;
      dib[o + 2] = 0x00;
    }
  }
  return dib;
}

void _setU32(Uint8List b, int i, int v) {
  b[i] = v & 0xff;
  b[i + 1] = (v >> 8) & 0xff;
  b[i + 2] = (v >> 16) & 0xff;
  b[i + 3] = (v >> 24) & 0xff;
}

void _setI32(Uint8List b, int i, int v) => _setU32(b, i, v);
