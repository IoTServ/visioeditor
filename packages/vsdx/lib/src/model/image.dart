/// Embedded image / image-shape references.
///
/// Visio stores embedded raster images inside `visio/media/imageN.png`
/// (or `.jpg` / `.emf` / `.wmf`). Shapes reference them through a
/// `<ForeignData>` element whose relationship id points at the media part.
///
/// We split the image data from the shape pointer so multiple shapes can
/// share one decoded blob (Visio frequently reuses the same picture across
/// master / page instances).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as raster;
import 'package:meta/meta.dart';

/// A bitmap payload that common Flutter and browser codecs can display.
@immutable
class VsdxRenderableRaster {
  const VsdxRenderableRaster({
    required this.bytes,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String mimeType;
}

/// A single piece of embedded media. Bytes are kept as `Uint8List`; the
/// renderer hands them to `ui.instantiateImageCodec` lazily so model-side
/// parsing remains synchronous.
@immutable
class VsdxImage {
  const VsdxImage({
    required this.partName,
    required this.bytes,
    required this.mimeType,
  });

  /// OPC part name (e.g. `/visio/media/image1.png`). Acts as a stable key.
  final String partName;

  /// Raw image bytes. PNG / JPEG / GIF / BMP / WEBP are decodable by
  /// Flutter directly. EMF / WMF are kept as-is so callers can choose
  /// their own fallback (placeholder image, external rasteriser, etc).
  final Uint8List bytes;

  /// e.g. `image/png`, `image/jpeg`, `image/x-emf`. May be empty when the
  /// content-types table is sparse — callers should fall back to the
  /// extension on [partName] in that case.
  final String mimeType;

  /// Best-effort MIME type for a file [extension] (with or without the dot).
  /// Returns an empty string for unknown extensions.
  static String mimeForExtension(String extension) {
    switch (extension.toLowerCase().replaceAll('.', '')) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'bmp':
        return 'image/bmp';
      case 'webp':
        return 'image/webp';
      case 'tif':
      case 'tiff':
        return 'image/tiff';
      case 'emf':
        return 'image/x-emf';
      case 'wmf':
        return 'image/x-wmf';
      default:
        return '';
    }
  }

  /// `true` when Flutter's built-in codec can decode the blob.
  bool get isFlutterDecodable {
    final m = mimeType.toLowerCase();
    if (m.startsWith('image/png') ||
        m.startsWith('image/jpeg') ||
        m.startsWith('image/jpg') ||
        m.startsWith('image/gif') ||
        m.startsWith('image/bmp') ||
        m.startsWith('image/webp')) {
      return true;
    }
    final lower = partName.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.webp');
  }

  /// Return a cross-platform bitmap payload for painting or SVG embedding.
  ///
  /// libvisio exposes TIFF ForeignData as a regular binary image to
  /// librevenge/LibreOffice. Flutter and browsers do not consistently decode
  /// TIFF, so convert its first page to PNG in pure Dart while retaining the
  /// original TIFF bytes in the document model for lossless round-tripping.
  /// Malformed or unsupported input is reported as `null`; callers can keep
  /// their normal placeholder fallback instead of failing the whole page.
  VsdxRenderableRaster? rasterForRendering() {
    if (isFlutterDecodable) {
      return VsdxRenderableRaster(
        bytes: bytes,
        mimeType: _effectiveRasterMimeType,
      );
    }
    if (!_isTiff) return null;
    try {
      final decoded = raster.decodeTiff(bytes, frame: 0);
      if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
        return null;
      }
      return VsdxRenderableRaster(
        bytes: raster.encodePng(decoded),
        mimeType: 'image/png',
      );
    } catch (_) {
      return null;
    }
  }

  bool get _isTiff {
    final m = mimeType.toLowerCase();
    final p = partName.toLowerCase();
    return m.startsWith('image/tiff') ||
        m.startsWith('image/tif') ||
        p.endsWith('.tif') ||
        p.endsWith('.tiff');
  }

  String get _effectiveRasterMimeType {
    final m = mimeType.toLowerCase();
    if (m.startsWith('image/')) return mimeType;
    final dot = partName.lastIndexOf('.');
    if (dot >= 0) {
      final inferred = mimeForExtension(partName.substring(dot + 1));
      if (inferred.isNotEmpty) return inferred;
    }
    return 'image/png';
  }

  /// Visio `<ForeignData ForeignType>` for this media (MS-VSDX / libvisio).
  /// `EnhMetaFile` for EMF, `MetaFile` for WMF, otherwise `Bitmap`.
  String get foreignType => foreignTypeFor(mimeType: mimeType, partName: partName);

  /// Optional Visio `CompressionType` for bitmap payloads.
  String? get compressionType =>
      compressionTypeFor(mimeType: mimeType, partName: partName);

  /// Map MIME / part extension → Visio `ForeignType` attribute value.
  static String foreignTypeFor({
    required String mimeType,
    required String partName,
  }) {
    final m = mimeType.toLowerCase();
    final p = partName.toLowerCase();
    if (m.contains('emf') || p.endsWith('.emf')) return 'EnhMetaFile';
    if (m.contains('wmf') || p.endsWith('.wmf')) return 'MetaFile';
    if (m == 'object/ole' || m.startsWith('object/')) return 'Object';
    return 'Bitmap';
  }

  /// Map MIME / part extension → Visio `CompressionType`, or null.
  static String? compressionTypeFor({
    required String mimeType,
    required String partName,
  }) {
    // Keep every libvisio bitmap enum explicit. Its VSDX reader maps a missing
    // CompressionType to the legacy DIB/BMP format, so omitting GIF or TIFF
    // makes otherwise valid bytes disappear when LibreOffice imports them.
    final m = mimeType.toLowerCase();
    final p = partName.toLowerCase();
    if (m.contains('jpeg') ||
        m.contains('jpg') ||
        p.endsWith('.jpg') ||
        p.endsWith('.jpeg')) {
      return 'JPEG';
    }
    if (m.contains('gif') || p.endsWith('.gif')) return 'GIF';
    if (m.contains('tiff') ||
        m == 'image/tif' ||
        p.endsWith('.tif') ||
        p.endsWith('.tiff')) {
      return 'TIFF';
    }
    if (m.contains('png') || p.endsWith('.png')) return 'PNG';
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is VsdxImage && other.partName == partName;
  @override
  int get hashCode => partName.hashCode;

  @override
  String toString() =>
      'VsdxImage($partName, ${bytes.length} bytes, $mimeType)';
}

/// Lookup table for `Master="N"`-style indirection — the parser populates
/// it from `visio/media/*` and exposes it on [VsdxDocument].
@immutable
class ImageRegistry {
  const ImageRegistry(this._byPartName);

  final Map<String, VsdxImage> _byPartName;

  static const ImageRegistry empty = ImageRegistry(<String, VsdxImage>{});

  VsdxImage? findByPart(String partName) => _byPartName[partName];

  Iterable<VsdxImage> get all => _byPartName.values;

  int get length => _byPartName.length;

  /// Return a copy of this registry with [image] added (replacing any entry
  /// that shares its part name). The editor calls this when a new picture is
  /// inserted so the renderer can resolve the bytes before the next save and
  /// the writer can embed them as a new media part.
  ImageRegistry withImage(VsdxImage image) => ImageRegistry(
        Map<String, VsdxImage>.unmodifiable(<String, VsdxImage>{
          ..._byPartName,
          image.partName: image,
        }),
      );

  /// Return a copy without [partName] (no-op when absent).
  ImageRegistry withoutImage(String partName) {
    if (!_byPartName.containsKey(partName)) return this;
    final next = Map<String, VsdxImage>.of(_byPartName)..remove(partName);
    return ImageRegistry(Map<String, VsdxImage>.unmodifiable(next));
  }
}

/// `true` when Image Properties cells would change LibreOffice's paint
/// (`tokens.txt` has no Transparency / Brightness / Contrast / Blur).
bool visioImageAdjustmentsNeedBake({
  required double transparency,
  required double blur,
  required double brightness,
  required double contrast,
}) {
  return transparency > 1e-6 ||
      blur > 1e-6 ||
      (brightness - 0.5).abs() > 1e-3 ||
      (contrast - 0.5).abs() > 1e-3;
}

/// Bake Visio Image Properties into PNG pixels so Draw paints the same
/// picture. libvisio never collects those cells; it draws the raw Foreign
/// bitmap. Returns `null` when the blob cannot be decoded or nothing
/// changes.
Uint8List? bakeVisioImageAdjustmentsPng({
  required VsdxImage image,
  required double transparency,
  required double blur,
  required double brightness,
  required double contrast,
  required double displayWidthInches,
}) {
  if (!visioImageAdjustmentsNeedBake(
    transparency: transparency,
    blur: blur,
    brightness: brightness,
    contrast: contrast,
  )) {
    return null;
  }
  final payload = image.rasterForRendering();
  if (payload == null) return null;
  raster.Image? decoded;
  try {
    decoded = raster.decodeImage(payload.bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
    return null;
  }
  raster.Image work;
  try {
    work = decoded.clone();
    if (work.numChannels < 4) {
      work = work.convert(numChannels: 4);
    }
  } catch (_) {
    return null;
  }
  final trans = transparency.clamp(0.0, 1.0);
  final blurClamped = blur.clamp(0.0, 1.0);
  final bright = brightness.clamp(0.0, 1.0);
  final contrastClamped = contrast.clamp(0.0, 1.0);
  try {
    if (blurClamped > 1e-6) {
      final displayed = math.max(displayWidthInches.abs(), 1e-6);
      final sigmaPx = 0.08 * blurClamped / displayed * work.width;
      final radius = math.max(1, (sigmaPx * 1.5).round());
      work = raster.gaussianBlur(work, radius: radius);
    }
    final c = 1.0 + (contrastClamped - 0.5) * 2.0;
    final b = (bright - 0.5) * 2.0;
    final t = (1.0 - c) * 0.5 + b;
    final tone = (bright - 0.5).abs() > 1e-3 ||
        (contrastClamped - 0.5).abs() > 1e-3 ||
        trans > 1e-6;
    if (tone) {
      for (final pixel in work) {
        if ((bright - 0.5).abs() > 1e-3 ||
            (contrastClamped - 0.5).abs() > 1e-3) {
          pixel.rNormalized = (c * pixel.rNormalized + t).clamp(0.0, 1.0);
          pixel.gNormalized = (c * pixel.gNormalized + t).clamp(0.0, 1.0);
          pixel.bNormalized = (c * pixel.bNormalized + t).clamp(0.0, 1.0);
        }
        if (trans > 1e-6) {
          pixel.aNormalized =
              (pixel.aNormalized * (1.0 - trans)).clamp(0.0, 1.0);
        }
      }
    }
    return raster.encodePng(work);
  } catch (_) {
    return null;
  }
}
