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

import 'dart:typed_data';

import 'package:meta/meta.dart';

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
}
