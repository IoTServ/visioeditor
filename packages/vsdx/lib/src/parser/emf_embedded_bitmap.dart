/// Best-effort extraction of an embedded DIB/BMP from an EMF (MS-EMF).
///
/// Many Visio `EnhMetaFile` payloads are a thin EMF wrapper around a single
/// `EMR_STRETCHDIBITS` / `EMR_BITBLT` record. Flutter cannot paint EMF
/// natively, but those embedded bitmaps decode fine via `instantiateImageCodec`.
///
/// Returns a BMP (with file header) or `null` when no usable DIB is found.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Record types that may carry a source DIB (MS-EMF 2.1.1).
const int _emrBitBlt = 0x4c;
const int _emrStretchBlt = 0x4d;
const int _emrStretchDiBits = 0x51;
const int _emrAlphaBlend = 0x72;
const int _emrTransparentBlt = 0x74;

/// Extract the largest embedded device-independent bitmap from [emf] bytes.
Uint8List? extractEmfEmbeddedBitmap(Uint8List emf) {
  if (!_looksLikeEmf(emf)) return null;
  Uint8List? best;
  var bestPixels = 0;
  var offset = 0;
  while (offset + 8 <= emf.length) {
    final type = _u32(emf, offset);
    final size = _u32(emf, offset + 4);
    if (size < 8 || offset + size > emf.length) break;
    if (type == _emrStretchDiBits ||
        type == _emrBitBlt ||
        type == _emrStretchBlt ||
        type == _emrAlphaBlend ||
        type == _emrTransparentBlt) {
      final bmp = _dibFromBlits(emf, offset, size, type);
      if (bmp != null) {
        final pixels = _approxPixelCount(bmp);
        if (pixels >= bestPixels) {
          bestPixels = pixels;
          best = bmp;
        }
      }
    }
    offset += size;
  }
  return best;
}

bool _looksLikeEmf(Uint8List b) =>
    b.length > 0x2B &&
    b[0x28] == 0x20 &&
    b[0x29] == 0x45 &&
    b[0x2A] == 0x4D &&
    b[0x2B] == 0x46;

/// EMR_STRETCHDIBITS / BITBLT layout (after Type+Size): Bounds(16) then
/// xDest.. and offBmiSrc/cbBmiSrc/offBitsSrc/cbBitsSrc at fixed offsets.
Uint8List? _dibFromBlits(Uint8List emf, int recOff, int recSize, int type) {
  // Common header after Type+Size (8): RECTL bounds (16) = 24 bytes into record.
  // Then for STRETCHDIBITS (MS-EMF 2.3.1.7):
  //   xDest,yDest,xSrc,ySrc,cxSrc,cySrc (6*4)
  //   offBmiSrc, cbBmiSrc, offBitsSrc, cbBitsSrc (4*4)
  //   UsageSrc, BitBltRasterOperation, cxDest, cyDest
  // BITBLT (2.3.1.2) is similar but without cxDest/cyDest stretch fields in the
  // same place — offBmiSrc still sits at a documented offset.
  //
  // off* fields are offsets from the *start of the record*.
  final minNeed = type == _emrStretchDiBits ? 80 : 72;
  if (recSize < minNeed) return null;

  // Prefer STRETCHDIBITS layout; fall back to scanning for BITMAPINFOHEADER.
  int? offBmi;
  int? cbBmi;
  int? offBits;
  int? cbBits;
  if (type == _emrStretchDiBits && recSize >= 80) {
    // Type+Size(8) + Bounds(16) + 6*LONG(24) = 48 → offBmiSrc at +48
    offBmi = _u32(emf, recOff + 48);
    cbBmi = _u32(emf, recOff + 52);
    offBits = _u32(emf, recOff + 56);
    cbBits = _u32(emf, recOff + 60);
  } else if (recSize >= 72) {
    // EMR_BITBLT: Type+Size(8)+Bounds(16)+xDest,yDest,cxDest,cyDest,rop(20)
    // +xSrc,ySrc(8)+Xform(24)+BkColor(4)+Usage(4) → offBmi at +84? Variable.
    // Fall through to header scan below when offsets look wrong.
    offBmi = _u32(emf, recOff + 84);
    cbBmi = _u32(emf, recOff + 88);
    offBits = _u32(emf, recOff + 92);
    cbBits = _u32(emf, recOff + 96);
  }

  if (offBmi != null &&
      cbBmi != null &&
      offBits != null &&
      cbBits != null &&
      offBmi > 0 &&
      cbBmi >= 40 &&
      offBits > 0 &&
      cbBits > 0 &&
      recOff + offBmi + cbBmi <= emf.length &&
      recOff + offBits + cbBits <= emf.length &&
      offBmi < recSize &&
      offBits < recSize) {
    final bmi = emf.sublist(recOff + offBmi, recOff + offBmi + cbBmi);
    final bits = emf.sublist(recOff + offBits, recOff + offBits + cbBits);
    final headerSize = _u32(bmi, 0);
    if (headerSize == 40 || headerSize == 108 || headerSize == 124) {
      return _packBmp(bmi, bits);
    }
  }

  // Fallback: find BITMAPINFOHEADER (biSize=40) inside the record.
  for (var i = recOff + 8; i + 40 < recOff + recSize; i++) {
    final headerSize = _u32(emf, i);
    if (headerSize != 40 && headerSize != 108 && headerSize != 124) continue;
    final width = _i32(emf, i + 4).abs();
    final height = _i32(emf, i + 8).abs();
    final planes = emf[i + 12] | (emf[i + 13] << 8);
    final bitCount = emf[i + 14] | (emf[i + 15] << 8);
    if (planes != 1) continue;
    if (width <= 0 || height <= 0 || width > 10000 || height > 10000) continue;
    if (!(bitCount == 1 ||
        bitCount == 4 ||
        bitCount == 8 ||
        bitCount == 16 ||
        bitCount == 24 ||
        bitCount == 32)) {
      continue;
    }
    final dibEnd = recOff + recSize;
    final dib = emf.sublist(i, dibEnd);
    return _dibToBmp(dib);
  }
  return null;
}

Uint8List _packBmp(Uint8List bmi, Uint8List bits) {
  final dib = Uint8List(bmi.length + bits.length);
  dib.setRange(0, bmi.length, bmi);
  dib.setRange(bmi.length, dib.length, bits);
  return _dibToBmp(dib);
}

Uint8List _dibToBmp(Uint8List dib) {
  final dataOff = _bmpDataOffset(dib);
  final total = dib.length + 14;
  final out = Uint8List(total);
  out[0] = 0x42;
  out[1] = 0x4D;
  out[2] = total & 0xff;
  out[3] = (total >> 8) & 0xff;
  out[4] = (total >> 16) & 0xff;
  out[5] = (total >> 24) & 0xff;
  out[10] = dataOff & 0xff;
  out[11] = (dataOff >> 8) & 0xff;
  out[12] = (dataOff >> 16) & 0xff;
  out[13] = (dataOff >> 24) & 0xff;
  out.setRange(14, total, dib);
  return out;
}

int _bmpDataOffset(Uint8List dib) {
  if (dib.length < 4) return 14 + 40;
  var headerSize = _u32(dib, 0);
  if (headerSize > dib.length) headerSize = 40;
  var off = headerSize;
  var bpp = 0;
  if (dib.length >= 16) {
    bpp = dib[14] | (dib[15] << 8);
  }
  if (bpp > 32) bpp = 32;
  if (bpp <= 8 && dib.length >= 36) {
    var clrUsed = _u32(dib, 32);
    if (clrUsed == 0) clrUsed = 1 << bpp;
    off += clrUsed * 4;
  }
  return 14 + off;
}

int _approxPixelCount(Uint8List bmp) {
  if (bmp.length < 26) return bmp.length;
  final w = _i32(bmp, 18).abs();
  final h = _i32(bmp, 22).abs();
  return math.max(1, w * h);
}

int _u32(Uint8List b, int i) =>
    b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24);

int _i32(Uint8List b, int i) {
  final v = _u32(b, i);
  return v > 0x7fffffff ? v - 0x100000000 : v;
}
