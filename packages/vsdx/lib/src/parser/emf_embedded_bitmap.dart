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
const int _emrMaskBlt = 0x4e;
const int _emrPlgBlt = 0x4f;
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
        type == _emrMaskBlt ||
        type == _emrPlgBlt ||
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
  final minNeed = type == _emrStretchDiBits
      ? 80
      : type == _emrMaskBlt
          ? 128
          : type == _emrPlgBlt
              ? 140
              : 72;
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
  } else if (type == _emrPlgBlt && recSize >= 140) {
    offBmi = _u32(emf, recOff + 96);
    cbBmi = _u32(emf, recOff + 100);
    offBits = _u32(emf, recOff + 104);
    cbBits = _u32(emf, recOff + 108);
  } else if (recSize >= 100) {
    // EMR_BITBLT: Type+Size(8)+Bounds(16)+xDest,yDest,cxDest,cyDest,rop(20)
    // +xSrc,ySrc(8)+Xform(24)+BkColor(4)+Usage(4) → offBmi at +84.
    // Fall through to header scan below when offsets look wrong. The final
    // fixed field is at +96, so a short/malformed record must not be read as
    // though bytes from the following EMF record belonged to this BITBLT.
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
      return packDibAsBmp(bmi, bits);
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
    return wrapDibAsBmp(dib);
  }
  return null;
}

/// Build a BMP from the independently stored BMI and pixel buffers used by
/// EMF bitmap records.
///
/// [preserveAlpha] promotes an uncompressed 32-bpp source to a V5 header with
/// an explicit alpha mask, matching LibreOffice's ALPHABLEND path.
/// [transparentArgb] expands common uncompressed 24/32-bpp sources and clears
/// alpha for pixels matching the EMR_TRANSPARENTBLT color key.
/// [maskBmi]/[maskBits] apply the monochrome MASKBLT/PLGBLT mask when its
/// common uncompressed 1-bpp representation can be decoded.
Uint8List? packDibAsBmp(
  Uint8List bmi,
  Uint8List bits, {
  bool preserveAlpha = false,
  int? transparentArgb,
  Uint8List? maskBmi,
  Uint8List? maskBits,
  int sourceX = 0,
  int sourceY = 0,
  int maskX = 0,
  int maskY = 0,
}) {
  if (preserveAlpha || transparentArgb != null || maskBmi != null) {
    final v5 = _packV5Bmp(
      bmi,
      bits,
      preserveAlpha: preserveAlpha,
      transparentArgb: transparentArgb,
      maskBmi: maskBmi,
      maskBits: maskBits,
      sourceX: sourceX,
      sourceY: sourceY,
      maskX: maskX,
      maskY: maskY,
    );
    if (v5 != null) return v5;
  }
  final dib = Uint8List(bmi.length + bits.length);
  dib.setRange(0, bmi.length, bmi);
  dib.setRange(bmi.length, dib.length, bits);
  return wrapDibAsBmp(dib);
}

Uint8List? _packV5Bmp(
  Uint8List bmi,
  Uint8List bits, {
  required bool preserveAlpha,
  required int? transparentArgb,
  required Uint8List? maskBmi,
  required Uint8List? maskBits,
  required int sourceX,
  required int sourceY,
  required int maskX,
  required int maskY,
}) {
  if (bmi.length < 40 || _u32(bmi, 0) < 40) return null;
  final signedWidth = _i32(bmi, 4);
  final signedHeight = _i32(bmi, 8);
  final width = signedWidth.abs();
  final height = signedHeight.abs();
  final planes = bmi[12] | (bmi[13] << 8);
  final bpp = bmi[14] | (bmi[15] << 8);
  final compression = _u32(bmi, 16);
  if (width == 0 ||
      height == 0 ||
      width > 100000 ||
      height > 100000 ||
      planes != 1 ||
      compression != 0 ||
      (bpp != 24 && bpp != 32) ||
      (preserveAlpha && bpp != 32)) {
    return null;
  }
  final sourceStride = ((width * bpp + 31) ~/ 32) * 4;
  if (sourceStride > bits.length || height > bits.length ~/ sourceStride) {
    return null;
  }
  final targetStride = width * 4;
  final pixelBytes = targetStride * height;
  final mask = _MonochromeMask.tryDecode(maskBmi, maskBits);
  final out = Uint8List(14 + 124 + pixelBytes);
  final data = ByteData.sublistView(out)
    ..setUint8(0, 0x42)
    ..setUint8(1, 0x4d)
    ..setUint32(2, out.length, Endian.little)
    ..setUint32(10, 138, Endian.little)
    ..setUint32(14, 124, Endian.little)
    ..setInt32(18, signedWidth, Endian.little)
    ..setInt32(22, signedHeight, Endian.little)
    ..setUint16(26, 1, Endian.little)
    ..setUint16(28, 32, Endian.little)
    ..setUint32(30, 3, Endian.little) // BI_BITFIELDS
    ..setUint32(34, pixelBytes, Endian.little)
    ..setUint32(54, 0x00ff0000, Endian.little)
    ..setUint32(58, 0x0000ff00, Endian.little)
    ..setUint32(62, 0x000000ff, Endian.little)
    ..setUint32(66, 0xff000000, Endian.little)
    ..setUint32(70, 0x73524742, Endian.little); // LCS_sRGB
  if (bmi.length >= 32) {
    data.setInt32(38, _i32(bmi, 24), Endian.little);
    data.setInt32(42, _i32(bmi, 28), Endian.little);
  }
  final keyR = transparentArgb == null ? -1 : (transparentArgb >> 16) & 0xff;
  final keyG = transparentArgb == null ? -1 : (transparentArgb >> 8) & 0xff;
  final keyB = transparentArgb == null ? -1 : transparentArgb & 0xff;
  for (var y = 0; y < height; y++) {
    final sourceRow = y * sourceStride;
    final targetRow = 138 + y * targetStride;
    for (var x = 0; x < width; x++) {
      final source = sourceRow + x * (bpp ~/ 8);
      final target = targetRow + x * 4;
      final blue = bits[source];
      final green = bits[source + 1];
      final red = bits[source + 2];
      final keyed = transparentArgb != null &&
          red == keyR &&
          green == keyG &&
          blue == keyB;
      final logicalY = signedHeight > 0 ? height - 1 - y : y;
      final maskedOut = mask != null &&
          !mask.copyPixel(
            maskX + x - sourceX,
            maskY + logicalY - sourceY,
          );
      out[target] = blue;
      out[target + 1] = green;
      out[target + 2] = red;
      out[target + 3] = keyed || maskedOut
          ? 0
          : preserveAlpha
              ? bits[source + 3]
              : 0xff;
    }
  }
  return out;
}

class _MonochromeMask {
  const _MonochromeMask(this.bits, this.width, this.height, this.bottomUp);

  final Uint8List bits;
  final int width;
  final int height;
  final bool bottomUp;

  static _MonochromeMask? tryDecode(Uint8List? bmi, Uint8List? bits) {
    if (bmi == null || bits == null || bmi.length < 40 || _u32(bmi, 0) < 40) {
      return null;
    }
    final signedWidth = _i32(bmi, 4);
    final signedHeight = _i32(bmi, 8);
    final width = signedWidth.abs();
    final height = signedHeight.abs();
    final planes = bmi[12] | (bmi[13] << 8);
    final bpp = bmi[14] | (bmi[15] << 8);
    if (width == 0 ||
        height == 0 ||
        planes != 1 ||
        bpp != 1 ||
        _u32(bmi, 16) != 0) {
      return null;
    }
    final stride = ((width + 31) ~/ 32) * 4;
    if (stride > bits.length || height > bits.length ~/ stride) return null;
    return _MonochromeMask(bits, width, height, signedHeight > 0);
  }

  bool copyPixel(int x, int y) {
    final normalizedX = ((x % width) + width) % width;
    final normalizedY = ((y % height) + height) % height;
    final storageY = bottomUp ? height - 1 - normalizedY : normalizedY;
    final stride = ((width + 31) ~/ 32) * 4;
    return (bits[storageY * stride + normalizedX ~/ 8] &
            (0x80 >> (normalizedX & 7))) !=
        0;
  }
}

/// Wrap a standalone device-independent bitmap in a BMP file header.
///
/// WMF bitmap records store a DIB directly after their fixed parameters,
/// while Flutter and SVG image decoders expect a complete BMP stream. The
/// returned bytes retain the original DIB exactly (including compressed pixel
/// data); only the 14-byte file header is added.
Uint8List? wrapDibAsBmp(Uint8List dib) {
  if (dib.length < 12) return null;
  final headerSize = _u32(dib, 0);
  if (headerSize != 12 &&
      headerSize != 40 &&
      headerSize != 52 &&
      headerSize != 56 &&
      headerSize != 64 &&
      headerSize != 108 &&
      headerSize != 124) {
    return null;
  }
  if (headerSize > dib.length) return null;
  final dimensions = dibDimensions(dib);
  if (dimensions == null || dimensions.$1 <= 0 || dimensions.$2 <= 0) {
    return null;
  }
  final dataOff = _bmpDataOffset(dib);
  if (dataOff < 14 || dataOff > dib.length + 14) return null;
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

/// Pixel dimensions declared by a DIB header, or `null` when it is truncated.
(int, int)? dibDimensions(Uint8List dib) {
  if (dib.length < 12) return null;
  final headerSize = _u32(dib, 0);
  if (headerSize == 12) {
    final width = dib[4] | (dib[5] << 8);
    final height = dib[6] | (dib[7] << 8);
    return (width, height);
  }
  if (headerSize < 40 || dib.length < 16) return null;
  return (_i32(dib, 4).abs(), _i32(dib, 8).abs());
}

int _bmpDataOffset(Uint8List dib) {
  if (dib.length < 4) return 14 + 40;
  var headerSize = _u32(dib, 0);
  if (headerSize > dib.length) headerSize = 40;
  var off = headerSize;
  var bpp = 0;
  if (headerSize == 12 && dib.length >= 12) {
    bpp = dib[10] | (dib[11] << 8);
    if (bpp > 0 && bpp <= 8) off += (1 << bpp) * 3;
    return 14 + off;
  }
  if (dib.length >= 16) {
    bpp = dib[14] | (dib[15] << 8);
  }
  if (bpp > 32) bpp = 32;
  if (bpp > 0 && bpp <= 8 && dib.length >= 36) {
    var clrUsed = _u32(dib, 32);
    if (clrUsed == 0) clrUsed = 1 << bpp;
    off += clrUsed * 4;
  }
  // BITMAPINFOHEADER stores BI_BITFIELDS masks between the 40-byte header and
  // the pixel array. V2/V3/V4/V5 headers already include those masks.
  if (headerSize == 40 && dib.length >= 20) {
    final compression = _u32(dib, 16);
    if (compression == 3) off += 12; // BI_BITFIELDS
    if (compression == 6) off += 16; // BI_ALPHABITFIELDS
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
