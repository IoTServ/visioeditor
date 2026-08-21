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
  String get foreignType =>
      foreignTypeFor(mimeType: mimeType, partName: partName);

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
  String toString() => 'VsdxImage($partName, ${bytes.length} bytes, $mimeType)';
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

/// `true` when Image Properties or picture SoftEdges would change Draw.
///
/// `tokens.txt` has no Transparency / Brightness / Contrast / Blur, and no
/// SoftEdgesSize. [softEdgesInches] is the size this picture should bake
/// (0 for 1-D — those cannot feather the PNG). Cropped frames composite
/// into the shape box first so ImgOffset still matches canvas / SVG.
bool visioImageAdjustmentsNeedBake({
  required double transparency,
  required double blur,
  required double brightness,
  required double contrast,
  double softEdgesInches = 0,
}) {
  return transparency > 1e-6 ||
      blur > 1e-6 ||
      (brightness - 0.5).abs() > 1e-3 ||
      (contrast - 0.5).abs() > 1e-3 ||
      softEdgesInches > 1e-6;
}

/// `true` when ImgOffset / ImgWidth / ImgHeight do not fill the Foreign frame.
///
/// libvisio collects those cells, so an uncropped SoftEdges bake can feather
/// the PNG in place. A cropped frame has to be composited first or Draw
/// would crop a halo that lives on the wrong edges.
bool visioPictureFrameIsCropped({
  required double frameWidthInches,
  required double frameHeightInches,
  required double imgOffsetXInches,
  required double imgOffsetYInches,
  double? imgWidthInches,
  double? imgHeightInches,
}) {
  if (imgOffsetXInches.abs() > 1e-6) return true;
  if (imgOffsetYInches.abs() > 1e-6) return true;
  if (imgWidthInches != null &&
      (imgWidthInches - frameWidthInches).abs() > 1e-6) {
    return true;
  }
  if (imgHeightInches != null &&
      (imgHeightInches - frameHeightInches).abs() > 1e-6) {
    return true;
  }
  return false;
}

/// Bake Visio Image Properties into PNG pixels so Draw paints the same
/// picture. libvisio never collects those cells; it draws the raw Foreign
/// bitmap. Returns `null` when the blob cannot be decoded or nothing
/// changes.
///
/// Pass the Foreign frame size together with Img* crop cells when SoftEdges
/// has to survive a crop: the PNG is then the clipped, feathered frame and
/// the caller must reset ImgOffset / ImgWidth / ImgHeight so Draw does not
/// crop it a second time.
Uint8List? bakeVisioImageAdjustmentsPng({
  required VsdxImage image,
  required double transparency,
  required double blur,
  required double brightness,
  required double contrast,
  required double displayWidthInches,
  double softEdgesInches = 0,
  double frameWidthInches = 0,
  double frameHeightInches = 0,
  double imgOffsetXInches = 0,
  double imgOffsetYInches = 0,
  double? imgWidthInches,
  double? imgHeightInches,
}) {
  if (!visioImageAdjustmentsNeedBake(
    transparency: transparency,
    blur: blur,
    brightness: brightness,
    contrast: contrast,
    softEdgesInches: softEdgesInches,
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
  final softClamped = softEdgesInches.clamp(0.0, 4.0);
  try {
    var displayed = math.max(displayWidthInches.abs(), 1e-6);
    var featherLeft = 0;
    var featherTop = 0;
    var featherRight = work.width - 1;
    var featherBottom = work.height - 1;
    final cropIntoFrame = frameWidthInches.abs() > 1e-6 &&
        frameHeightInches.abs() > 1e-6 &&
        visioPictureFrameIsCropped(
          frameWidthInches: frameWidthInches,
          frameHeightInches: frameHeightInches,
          imgOffsetXInches: imgOffsetXInches,
          imgOffsetYInches: imgOffsetYInches,
          imgWidthInches: imgWidthInches,
          imgHeightInches: imgHeightInches,
        );
    if (cropIntoFrame) {
      final composited = _compositeVisioPictureIntoFrame(
        source: work,
        frameWidthInches: frameWidthInches.abs(),
        frameHeightInches: frameHeightInches.abs(),
        imgOffsetXInches: imgOffsetXInches,
        imgOffsetYInches: imgOffsetYInches,
        imgWidthInches: imgWidthInches ?? frameWidthInches.abs(),
        imgHeightInches: imgHeightInches ?? frameHeightInches.abs(),
      );
      if (composited == null) return null;
      work = composited.image;
      featherLeft = composited.left;
      featherTop = composited.top;
      featherRight = composited.right;
      featherBottom = composited.bottom;
      displayed = math.max(frameWidthInches.abs(), 1e-6);
    }
    if (blurClamped > 1e-6) {
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
    if (softClamped > 1e-6) {
      // Canvas / SVG feather an opaque Img* rect, clipped to the Foreign
      // frame, against empty surroundings. A full-bitmap blur would clamp
      // and leave the visible crop window hard-edged.
      _featherOpaqueRect(
        work,
        softClamped / displayed * work.width,
        left: featherLeft,
        top: featherTop,
        right: featherRight,
        bottom: featherBottom,
      );
    }
    return raster.encodePng(work);
  } catch (_) {
    return null;
  }
}

/// Place a Visio Foreign bitmap into the shape-local frame (Y-up Img* cells,
/// Y-down PNG). Returns the clipped dest rect used as the SoftEdges mask.
({raster.Image image, int left, int top, int right, int bottom})?
    _compositeVisioPictureIntoFrame({
  required raster.Image source,
  required double frameWidthInches,
  required double frameHeightInches,
  required double imgOffsetXInches,
  required double imgOffsetYInches,
  required double imgWidthInches,
  required double imgHeightInches,
}) {
  if (frameWidthInches <= 1e-9 || frameHeightInches <= 1e-9) return null;
  if (imgWidthInches.abs() <= 1e-9 || imgHeightInches.abs() <= 1e-9) {
    return null;
  }
  var widthPx = math.max(8, (frameWidthInches * 96.0).round());
  var heightPx = math.max(8, (frameHeightInches * 96.0).round());
  final mappedW =
      (source.width * frameWidthInches / imgWidthInches.abs()).round();
  final mappedH =
      (source.height * frameHeightInches / imgHeightInches.abs()).round();
  widthPx = math.max(widthPx, math.max(8, mappedW));
  heightPx = math.max(heightPx, math.max(8, mappedH));
  const maxPx = 1024;
  final longest = math.max(widthPx, heightPx);
  if (longest > maxPx) {
    final scale = maxPx / longest;
    widthPx = math.max(8, (widthPx * scale).round());
    heightPx = math.max(8, (heightPx * scale).round());
  }
  final left = imgOffsetXInches / frameWidthInches * widthPx;
  final right =
      (imgOffsetXInches + imgWidthInches) / frameWidthInches * widthPx;
  // Shape-local Y is up; PNG Y is down. ImgOffsetY is the visual bottom.
  final top =
      (1 - (imgOffsetYInches + imgHeightInches) / frameHeightInches) * heightPx;
  final bottom = (1 - imgOffsetYInches / frameHeightInches) * heightPx;
  final dstLeft = math.min(left, right);
  final dstRight = math.max(left, right);
  final dstTop = math.min(top, bottom);
  final dstBottom = math.max(top, bottom);
  final destW = dstRight - dstLeft;
  final destH = dstBottom - dstTop;
  if (destW < 1e-6 || destH < 1e-6) return null;
  final clipLeft = math.max(0, dstLeft.floor());
  final clipTop = math.max(0, dstTop.floor());
  final clipRight = math.min(widthPx - 1, dstRight.ceil() - 1);
  final clipBottom = math.min(heightPx - 1, dstBottom.ceil() - 1);
  if (clipRight < clipLeft || clipBottom < clipTop) return null;
  final work = raster.Image(
    width: widthPx,
    height: heightPx,
    numChannels: 4,
  );
  final srcW = math.max(1, source.width);
  final srcH = math.max(1, source.height);
  for (var y = clipTop; y <= clipBottom; y++) {
    for (var x = clipLeft; x <= clipRight; x++) {
      final u = ((x + 0.5) - dstLeft) / destW;
      final v = ((y + 0.5) - dstTop) / destH;
      if (u < 0 || u > 1 || v < 0 || v > 1) continue;
      final sx = (u * (srcW - 1)).round().clamp(0, srcW - 1);
      final sy = (v * (srcH - 1)).round().clamp(0, srcH - 1);
      final pixel = source.getPixel(sx, sy);
      work.setPixelRgba(
        x,
        y,
        pixel.r.toInt(),
        pixel.g.toInt(),
        pixel.b.toInt(),
        pixel.a.toInt(),
      );
    }
  }
  return (
    image: work,
    left: clipLeft,
    top: clipTop,
    right: clipRight,
    bottom: clipBottom,
  );
}

void _featherOpaqueRect(
  raster.Image work,
  double softSigmaPx, {
  required int left,
  required int top,
  required int right,
  required int bottom,
}) {
  final sigma = softSigmaPx.clamp(0.0, 256.0);
  if (sigma <= 1e-6) return;
  if (right < left || bottom < top) return;
  final radius = math.max(1, (sigma * 1.5).round());
  final pad = radius * 2;
  var mask = raster.Image(
    width: work.width + pad * 2,
    height: work.height + pad * 2,
    numChannels: 4,
  );
  final x0 = left.clamp(0, work.width - 1);
  final y0 = top.clamp(0, work.height - 1);
  final x1 = right.clamp(0, work.width - 1);
  final y1 = bottom.clamp(0, work.height - 1);
  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      mask.setPixelRgba(x + pad, y + pad, 255, 255, 255, 255);
    }
  }
  mask = raster.gaussianBlur(mask, radius: radius);
  for (var y = 0; y < work.height; y++) {
    for (var x = 0; x < work.width; x++) {
      final pixel = work.getPixel(x, y);
      final m = mask.getPixel(x + pad, y + pad);
      pixel.aNormalized = (pixel.aNormalized * m.aNormalized).clamp(0.0, 1.0);
    }
  }
}

/// Silhouette kinds [bakeSilhouetteSoftEdgesPng] can fill before feathering.
enum SoftEdgesSilhouetteKind {
  /// Axis-aligned box filling the bitmap (optional [roundingPx]).
  rectangle,

  /// Ellipse inscribed in the bitmap.
  ellipse,

  /// Closed [polygon] in pixel coordinates, y-down.
  polygon,
}

/// Rasterize a solid silhouette and feather SourceAlpha like canvas SoftEdges.
///
/// Picture SoftEdges feathers a full-frame bitmap. Geometry SoftEdges must
/// feather the painted alpha (ellipse / polygon), then Draw can show the PNG
/// because `SoftEdgesSize` is not a token.
Uint8List? bakeSilhouetteSoftEdgesPng({
  required int widthPx,
  required int heightPx,
  required int red,
  required int green,
  required int blue,
  required int alpha,
  required double softSigmaPx,
  SoftEdgesSilhouetteKind kind = SoftEdgesSilhouetteKind.rectangle,
  List<({double x, double y})> polygon = const <({double x, double y})>[],
  double roundingPx = 0,
  ({int r, int g, int b, int a}) Function(double xPx, double yPx)? colorAt,
}) {
  if (widthPx < 2 || heightPx < 2) return null;
  if (alpha <= 0 && colorAt == null) return null;
  try {
    var work = raster.Image(
      width: widthPx,
      height: heightPx,
      numChannels: 4,
    );
    final color = colorAt == null
        ? raster.ColorRgba8(
            red.clamp(0, 255),
            green.clamp(0, 255),
            blue.clamp(0, 255),
            alpha.clamp(0, 255),
          )
        : raster.ColorRgba8(255, 255, 255, 255);
    switch (kind) {
      case SoftEdgesSilhouetteKind.rectangle:
        raster.fillRect(
          work,
          x1: 0,
          y1: 0,
          x2: widthPx - 1,
          y2: heightPx - 1,
          color: color,
          radius: roundingPx.clamp(0, math.min(widthPx, heightPx) / 2),
          alphaBlend: false,
        );
      case SoftEdgesSilhouetteKind.ellipse:
        final cx = (widthPx - 1) / 2;
        final cy = (heightPx - 1) / 2;
        final rx = math.max((widthPx - 1) / 2, 0.5);
        final ry = math.max((heightPx - 1) / 2, 0.5);
        for (var y = 0; y < heightPx; y++) {
          for (var x = 0; x < widthPx; x++) {
            final nx = (x + 0.5 - cx) / rx;
            final ny = (y + 0.5 - cy) / ry;
            if (nx * nx + ny * ny <= 1) {
              work.setPixelRgba(x, y, color.r.toInt(), color.g.toInt(),
                  color.b.toInt(), color.a.toInt());
            }
          }
        }
      case SoftEdgesSilhouetteKind.polygon:
        if (polygon.length < 3) return null;
        raster.fillPolygon(
          work,
          vertices: <raster.Point>[
            for (final p in polygon) raster.Point(p.x, p.y),
          ],
          color: color,
        );
    }
    if (colorAt != null) {
      for (var y = 0; y < heightPx; y++) {
        for (var x = 0; x < widthPx; x++) {
          final pixel = work.getPixel(x, y);
          if (pixel.a <= 0) continue;
          final sampled = colorAt(x + 0.5, y + 0.5);
          work.setPixelRgba(
            x,
            y,
            sampled.r,
            sampled.g,
            sampled.b,
            (sampled.a * pixel.aNormalized).round().clamp(0, 255),
          );
        }
      }
    }
    final sigma = softSigmaPx.clamp(0.0, 256.0);
    if (sigma > 1e-6) {
      final radius = math.max(1, (sigma * 1.5).round());
      final pad = radius * 2;
      var mask = raster.Image(
        width: work.width + pad * 2,
        height: work.height + pad * 2,
        numChannels: 4,
      );
      for (var y = 0; y < work.height; y++) {
        for (var x = 0; x < work.width; x++) {
          final pixel = work.getPixel(x, y);
          final a = (pixel.aNormalized * 255).round();
          if (a <= 0) continue;
          mask.setPixelRgba(x + pad, y + pad, 255, 255, 255, a);
        }
      }
      mask = raster.gaussianBlur(mask, radius: radius);
      for (var y = 0; y < work.height; y++) {
        for (var x = 0; x < work.width; x++) {
          final pixel = work.getPixel(x, y);
          final m = mask.getPixel(x + pad, y + pad);
          pixel.aNormalized =
              (pixel.aNormalized * m.aNormalized).clamp(0.0, 1.0);
        }
      }
    }
    return raster.encodePng(work);
  } catch (_) {
    return null;
  }
}

bool _softEdgesPointInPolygon(
  List<({double x, double y})> polygon,
  double x,
  double y,
) {
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final yi = polygon[i].y;
    final yj = polygon[j].y;
    final xi = polygon[i].x;
    final xj = polygon[j].x;
    final crosses = (yi > y) != (yj > y);
    if (!crosses) continue;
    final denom = (yj - yi).abs() < 1e-18 ? 1e-18 : (yj - yi);
    if (x < (xj - xi) * (y - yi) / denom + xi) inside = !inside;
  }
  return inside;
}

void _featherSourceAlpha(raster.Image work, double softSigmaPx) {
  final sigma = softSigmaPx.clamp(0.0, 256.0);
  if (sigma <= 1e-6) return;
  final radius = math.max(1, (sigma * 1.5).round());
  final pad = radius * 2;
  var mask = raster.Image(
    width: work.width + pad * 2,
    height: work.height + pad * 2,
    numChannels: 4,
  );
  for (var y = 0; y < work.height; y++) {
    for (var x = 0; x < work.width; x++) {
      final pixel = work.getPixel(x, y);
      final a = (pixel.aNormalized * 255).round();
      if (a <= 0) continue;
      mask.setPixelRgba(x + pad, y + pad, 255, 255, 255, a);
    }
  }
  mask = raster.gaussianBlur(mask, radius: radius);
  for (var y = 0; y < work.height; y++) {
    for (var x = 0; x < work.width; x++) {
      final pixel = work.getPixel(x, y);
      final m = mask.getPixel(x + pad, y + pad);
      pixel.aNormalized = (pixel.aNormalized * m.aNormalized).clamp(0.0, 1.0);
    }
  }
}

/// Rasterize a stroked silhouette and feather SourceAlpha like canvas SoftEdges.
///
/// Geometry SoftEdges on an unfilled 2-D stroke has no fill plate to steal.
/// The PNG is padded so the outer half of [strokeWidthPx] and the blur halo
/// are not clipped; Draw then shows the plate because `SoftEdgesSize` is
/// not a token. A filled body ([holeRed] etc., or [holeColorAt] for a
/// gradient / hatch wash) paints the interior before the same SourceAlpha
/// feather. [strokeColorAt] samples LineGradient along that ring so Draw
/// does not keep a hard opaque outline. Draw / PDF flatten Foreign alpha
/// against black, so the result composites onto opaque white — the
/// interior colour stays, and a hollow ring does not become a filled
/// black plate.
/// [gaussianBlur] uses the same Gaussian as canvas `_drawGlow` instead of
/// SourceAlpha feather, so an unfilled Glow ring spreads instead of eroding.
Uint8List? bakeStrokedSilhouetteSoftEdgesPng({
  required int innerWidthPx,
  required int innerHeightPx,
  required int padPx,
  required int red,
  required int green,
  required int blue,
  required int alpha,
  required double softSigmaPx,
  required double strokeWidthPx,
  SoftEdgesSilhouetteKind kind = SoftEdgesSilhouetteKind.rectangle,
  List<({double x, double y})> outer = const <({double x, double y})>[],
  List<({double x, double y})> inner = const <({double x, double y})>[],
  List<List<({double x, double y})>> ribbons =
      const <List<({double x, double y})>>[],
  int? holeRed,
  int? holeGreen,
  int? holeBlue,
  int? holeAlpha,
  ({int r, int g, int b, int a}) Function(double innerX, double innerY)?
      holeColorAt,
  ({int r, int g, int b, int a}) Function(double innerX, double innerY)?
      strokeColorAt,
  bool gaussianBlur = false,
}) {
  if (innerWidthPx < 2 || innerHeightPx < 2) return null;
  if (padPx < 0) return null;
  if (alpha <= 0 && strokeColorAt == null) return null;
  if (strokeWidthPx <= 1e-6) return null;
  final widthPx = innerWidthPx + padPx * 2;
  final heightPx = innerHeightPx + padPx * 2;
  try {
    var work = raster.Image(
      width: widthPx,
      height: heightPx,
      numChannels: 4,
    );
    var painted = false;
    final hole = holeAlpha != null && holeAlpha > 0
        ? raster.ColorRgba8(
            (holeRed ?? 0).clamp(0, 255),
            (holeGreen ?? 0).clamp(0, 255),
            (holeBlue ?? 0).clamp(0, 255),
            holeAlpha.clamp(0, 255),
          )
        : null;
    final hasHole = hole != null || holeColorAt != null;
    if (ribbons.isNotEmpty) {
      if (hasHole) {
        painted = _paintInnerFill(
          work,
          innerWidthPx: innerWidthPx,
          innerHeightPx: innerHeightPx,
          padPx: padPx,
          kind: kind,
          fill: inner,
          color: hole ?? raster.ColorRgba8(0, 0, 0, 0),
          colorAt: holeColorAt,
        );
      }
      painted = _paintFilledPolygons(
            work,
            ribbons,
            raster.ColorRgba8(
              red.clamp(0, 255),
              green.clamp(0, 255),
              blue.clamp(0, 255),
              alpha.clamp(0, 255),
            ),
            padPx: padPx,
            colorAt: strokeColorAt,
          ) ||
          painted;
    } else {
      painted = _paintStrokedRing(
        work,
        innerWidthPx: innerWidthPx,
        innerHeightPx: innerHeightPx,
        padPx: padPx,
        color: raster.ColorRgba8(
          red.clamp(0, 255),
          green.clamp(0, 255),
          blue.clamp(0, 255),
          alpha.clamp(0, 255),
        ),
        strokeWidthPx: strokeWidthPx,
        kind: kind,
        outer: outer,
        inner: inner,
        holeColor: hole,
        holeColorAt: holeColorAt,
        strokeColorAt: strokeColorAt,
      );
    }
    if (!painted) return null;
    if (gaussianBlur) {
      final blur = softSigmaPx.clamp(0.0, 256.0);
      if (blur > 1e-6) {
        final radius = math.max(1, (blur * 1.5).round());
        work = raster.gaussianBlur(work, radius: radius);
      }
    } else {
      _featherSourceAlpha(work, softSigmaPx);
    }
    _compositeOntoWhite(work);
    return raster.encodePng(work);
  } catch (_) {
    return null;
  }
}

void _putSoftEdgesHolePixel(
  raster.Image work,
  int x,
  int y, {
  raster.ColorRgba8? hole,
  ({int r, int g, int b, int a}) Function(double innerX, double innerY)?
      holeColorAt,
  required int padPx,
}) {
  if (holeColorAt != null) {
    final sampled = holeColorAt(x + 0.5 - padPx, y + 0.5 - padPx);
    work.setPixelRgba(x, y, sampled.r, sampled.g, sampled.b, sampled.a);
    return;
  }
  if (hole == null) return;
  work.setPixelRgba(
    x,
    y,
    hole.r.toInt(),
    hole.g.toInt(),
    hole.b.toInt(),
    hole.a.toInt(),
  );
}

void _putSoftEdgesStrokePixel(
  raster.Image work,
  int x,
  int y, {
  required raster.ColorRgba8 color,
  ({int r, int g, int b, int a}) Function(double innerX, double innerY)?
      strokeColorAt,
  required int padPx,
}) {
  if (strokeColorAt != null) {
    final sampled = strokeColorAt(x + 0.5 - padPx, y + 0.5 - padPx);
    work.setPixelRgba(x, y, sampled.r, sampled.g, sampled.b, sampled.a);
    return;
  }
  work.setPixelRgba(
    x,
    y,
    color.r.toInt(),
    color.g.toInt(),
    color.b.toInt(),
    color.a.toInt(),
  );
}

/// Paint a stroke ring of [strokeWidthPx] around the box inset by [padPx].
///
/// Shared by the SoftEdges / Glow ring and the Reflection band so all three
/// use the same silhouette maths. Returns `false` for unusable polygons.
bool _paintStrokedRing(
  raster.Image work, {
  required int innerWidthPx,
  required int innerHeightPx,
  required int padPx,
  required raster.ColorRgba8 color,
  required double strokeWidthPx,
  required SoftEdgesSilhouetteKind kind,
  required List<({double x, double y})> outer,
  required List<({double x, double y})> inner,
  raster.ColorRgba8? holeColor,
  ({int r, int g, int b, int a}) Function(double innerX, double innerY)?
      holeColorAt,
  ({int r, int g, int b, int a}) Function(double innerX, double innerY)?
      strokeColorAt,
}) {
  final widthPx = work.width;
  final heightPx = work.height;
  final hasHoleFill = holeColor != null || holeColorAt != null;
  final hole = holeColor ?? raster.ColorRgba8(0, 0, 0, 0);
  final half = math.max(strokeWidthPx / 2, 0.5);
  switch (kind) {
    case SoftEdgesSilhouetteKind.rectangle:
      final x1 = padPx.toDouble();
      final y1 = padPx.toDouble();
      final x2 = (padPx + innerWidthPx - 1).toDouble();
      final y2 = (padPx + innerHeightPx - 1).toDouble();
      final ox1 = (x1 - half).floor().clamp(0, widthPx - 1);
      final oy1 = (y1 - half).floor().clamp(0, heightPx - 1);
      final ox2 = (x2 + half).ceil().clamp(0, widthPx - 1);
      final oy2 = (y2 + half).ceil().clamp(0, heightPx - 1);
      final ix1 = (x1 + half).ceil();
      final iy1 = (y1 + half).ceil();
      final ix2 = (x2 - half).floor();
      final iy2 = (y2 - half).floor();
      if (strokeColorAt != null) {
        for (var y = oy1; y <= oy2; y++) {
          for (var x = ox1; x <= ox2; x++) {
            final inHole = ix1 < ix2 &&
                iy1 < iy2 &&
                x >= ix1 &&
                x <= ix2 &&
                y >= iy1 &&
                y <= iy2;
            if (inHole) {
              if (hasHoleFill) {
                _putSoftEdgesHolePixel(
                  work,
                  x,
                  y,
                  hole: holeColor,
                  holeColorAt: holeColorAt,
                  padPx: padPx,
                );
              }
              continue;
            }
            _putSoftEdgesStrokePixel(
              work,
              x,
              y,
              color: color,
              strokeColorAt: strokeColorAt,
              padPx: padPx,
            );
          }
        }
      } else {
        raster.fillRect(
          work,
          x1: ox1,
          y1: oy1,
          x2: ox2,
          y2: oy2,
          color: color,
          alphaBlend: false,
        );
        if (ix1 < ix2 && iy1 < iy2) {
          if (holeColorAt != null) {
            for (var y = iy1; y <= iy2; y++) {
              for (var x = ix1; x <= ix2; x++) {
                if (x < 0 || y < 0 || x >= widthPx || y >= heightPx) continue;
                _putSoftEdgesHolePixel(
                  work,
                  x,
                  y,
                  holeColorAt: holeColorAt,
                  padPx: padPx,
                );
              }
            }
          } else {
            raster.fillRect(
              work,
              x1: ix1.clamp(0, widthPx - 1),
              y1: iy1.clamp(0, heightPx - 1),
              x2: ix2.clamp(0, widthPx - 1),
              y2: iy2.clamp(0, heightPx - 1),
              color: hole,
              alphaBlend: false,
            );
          }
        }
      }
    case SoftEdgesSilhouetteKind.ellipse:
      final cx = padPx + (innerWidthPx - 1) / 2;
      final cy = padPx + (innerHeightPx - 1) / 2;
      final rx = math.max((innerWidthPx - 1) / 2, 0.5);
      final ry = math.max((innerHeightPx - 1) / 2, 0.5);
      final rxOut = math.max(rx + half, 0.5);
      final ryOut = math.max(ry + half, 0.5);
      final rxIn = math.max(rx - half, 0.0);
      final ryIn = math.max(ry - half, 0.0);
      for (var y = 0; y < heightPx; y++) {
        for (var x = 0; x < widthPx; x++) {
          final nx = (x + 0.5 - cx) / rxOut;
          final ny = (y + 0.5 - cy) / ryOut;
          if (nx * nx + ny * ny > 1) continue;
          if (rxIn > 1e-6 && ryIn > 1e-6) {
            final ix = (x + 0.5 - cx) / rxIn;
            final iy = (y + 0.5 - cy) / ryIn;
            if (ix * ix + iy * iy <= 1) {
              if (hasHoleFill) {
                _putSoftEdgesHolePixel(
                  work,
                  x,
                  y,
                  hole: holeColor,
                  holeColorAt: holeColorAt,
                  padPx: padPx,
                );
              }
              continue;
            }
          }
          _putSoftEdgesStrokePixel(
            work,
            x,
            y,
            color: color,
            strokeColorAt: strokeColorAt,
            padPx: padPx,
          );
        }
      }
    case SoftEdgesSilhouetteKind.polygon:
      if (outer.length < 3) return false;
      for (var y = 0; y < heightPx; y++) {
        for (var x = 0; x < widthPx; x++) {
          final px = x + 0.5;
          final py = y + 0.5;
          if (inner.length >= 3 && _softEdgesPointInPolygon(inner, px, py)) {
            if (hasHoleFill) {
              _putSoftEdgesHolePixel(
                work,
                x,
                y,
                hole: holeColor,
                holeColorAt: holeColorAt,
                padPx: padPx,
              );
            }
            continue;
          }
          if (!_softEdgesPointInPolygon(outer, px, py)) continue;
          _putSoftEdgesStrokePixel(
            work,
            x,
            y,
            color: color,
            strokeColorAt: strokeColorAt,
            padPx: padPx,
          );
        }
      }
  }
  return true;
}

bool _paintInnerFill(
  raster.Image work, {
  required int innerWidthPx,
  required int innerHeightPx,
  required int padPx,
  required SoftEdgesSilhouetteKind kind,
  required List<({double x, double y})> fill,
  required raster.ColorRgba8 color,
  ({int r, int g, int b, int a}) Function(double innerX, double innerY)?
      colorAt,
}) {
  final widthPx = work.width;
  final heightPx = work.height;
  if (colorAt == null && kind == SoftEdgesSilhouetteKind.rectangle) {
    raster.fillRect(
      work,
      x1: padPx.clamp(0, widthPx - 1),
      y1: padPx.clamp(0, heightPx - 1),
      x2: (padPx + innerWidthPx - 1).clamp(0, widthPx - 1),
      y2: (padPx + innerHeightPx - 1).clamp(0, heightPx - 1),
      color: color,
      alphaBlend: false,
    );
    return true;
  }
  if (kind == SoftEdgesSilhouetteKind.polygon && fill.length < 3) {
    return false;
  }
  var painted = false;
  for (var y = 0; y < heightPx; y++) {
    for (var x = 0; x < widthPx; x++) {
      final px = x + 0.5;
      final py = y + 0.5;
      final inside = switch (kind) {
        SoftEdgesSilhouetteKind.rectangle => px >= padPx &&
            py >= padPx &&
            px < padPx + innerWidthPx &&
            py < padPx + innerHeightPx,
        SoftEdgesSilhouetteKind.ellipse => () {
            final cx = padPx + (innerWidthPx - 1) / 2;
            final cy = padPx + (innerHeightPx - 1) / 2;
            final rx = math.max((innerWidthPx - 1) / 2, 0.5);
            final ry = math.max((innerHeightPx - 1) / 2, 0.5);
            final nx = (px - cx) / rx;
            final ny = (py - cy) / ry;
            return nx * nx + ny * ny <= 1;
          }(),
        SoftEdgesSilhouetteKind.polygon =>
          _softEdgesPointInPolygon(fill, px, py),
      };
      if (!inside) continue;
      if (colorAt != null) {
        final sampled = colorAt(px - padPx, py - padPx);
        work.setPixelRgba(x, y, sampled.r, sampled.g, sampled.b, sampled.a);
      } else {
        work.setPixelRgba(x, y, color.r.toInt(), color.g.toInt(),
            color.b.toInt(), color.a.toInt());
      }
      painted = true;
    }
  }
  return painted;
}

bool _paintFilledPolygons(
  raster.Image work,
  List<List<({double x, double y})>> polygons,
  raster.ColorRgba8 color, {
  int padPx = 0,
  ({int r, int g, int b, int a}) Function(double innerX, double innerY)?
      colorAt,
}) {
  var painted = false;
  for (var y = 0; y < work.height; y++) {
    for (var x = 0; x < work.width; x++) {
      final px = x + 0.5;
      final py = y + 0.5;
      for (final polygon in polygons) {
        if (polygon.length < 3) continue;
        if (!_softEdgesPointInPolygon(polygon, px, py)) continue;
        if (colorAt != null) {
          final sampled = colorAt(px - padPx, py - padPx);
          work.setPixelRgba(x, y, sampled.r, sampled.g, sampled.b, sampled.a);
        } else {
          work.setPixelRgba(
            x,
            y,
            color.r.toInt(),
            color.g.toInt(),
            color.b.toInt(),
            color.a.toInt(),
          );
        }
        painted = true;
        break;
      }
    }
  }
  return painted;
}

/// Draw / PDF flatten transparent Foreign bitmaps against black, so a hollow
/// ring or a padded halo would become a filled black plate. Composite onto
/// opaque white — the same page colour canvas already assumes for an
/// unfilled stroke. An opaque hole fill stays that colour; a hollow
/// interior stays empty.
void _compositeOntoWhite(raster.Image work) {
  for (var y = 0; y < work.height; y++) {
    for (var x = 0; x < work.width; x++) {
      final pixel = work.getPixel(x, y);
      final a = pixel.aNormalized;
      pixel.r = (pixel.r * a + 255 * (1 - a)).round().clamp(0, 255);
      pixel.g = (pixel.g * a + 255 * (1 - a)).round().clamp(0, 255);
      pixel.b = (pixel.b * a + 255 * (1 - a)).round().clamp(0, 255);
      pixel.a = 255;
    }
  }
}

raster.Image _flipImageVertical(raster.Image source) {
  final flipped = raster.Image(
    width: source.width,
    height: source.height,
    numChannels: 4,
  );
  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      flipped.setPixel(x, source.height - 1 - y, source.getPixel(x, y));
    }
  }
  return flipped;
}

/// Rasterize the mirrored, faded stroke band an unfilled 2-D Reflection needs.
///
/// `tokens.txt` has no Reflection*, and an unfilled stroke has no fill plate
/// to mirror — filling the mirror geometry would paint the interior Draw
/// leaves empty. Canvas `_drawReflection` strokes the flipped path instead,
/// clipped to [bandHeightPx] below the shape and faded toward the far edge.
/// [padPx] keeps the outer stroke half and the blur halo from clipping; the
/// band starts [padPx] rows in, so rows above it hold the stroke that spills
/// past the mirror axis. [ribbons] are per-dash / CompoundType strips so
/// Draw keeps the gaps and thick/thin rails; a solid ring would hide them.
/// [flipVertical] is for a FlipY source: the plate
/// sits above the shape in local Y (`_reflectFillRing`), and Visio maps
/// PNG row 0 to local max Y, so the near-axis rows must land on min Y.
Uint8List? bakeStrokedReflectionPng({
  required int innerWidthPx,
  required int innerHeightPx,
  required int bandHeightPx,
  required int padPx,
  required int red,
  required int green,
  required int blue,
  required int alpha,
  required double strokeWidthPx,
  required double blurSigmaPx,
  SoftEdgesSilhouetteKind kind = SoftEdgesSilhouetteKind.rectangle,
  List<({double x, double y})> outer = const <({double x, double y})>[],
  List<({double x, double y})> inner = const <({double x, double y})>[],
  List<List<({double x, double y})>> ribbons =
      const <List<({double x, double y})>>[],
  bool flipVertical = false,
}) {
  if (innerWidthPx < 2 || innerHeightPx < 2) return null;
  if (bandHeightPx < 1 || padPx < 0) return null;
  if (alpha <= 0) return null;
  if (strokeWidthPx <= 1e-6) return null;
  try {
    final ring = raster.Image(
      width: innerWidthPx + padPx * 2,
      height: innerHeightPx + padPx * 2,
      numChannels: 4,
    );
    final color = raster.ColorRgba8(
      red.clamp(0, 255),
      green.clamp(0, 255),
      blue.clamp(0, 255),
      alpha.clamp(0, 255),
    );
    final painted = ribbons.isNotEmpty
        ? _paintFilledPolygons(ring, ribbons, color)
        : _paintStrokedRing(
            ring,
            innerWidthPx: innerWidthPx,
            innerHeightPx: innerHeightPx,
            padPx: padPx,
            color: color,
            strokeWidthPx: strokeWidthPx,
            kind: kind,
            outer: outer,
            inner: inner,
          );
    if (!painted) return null;
    var work = raster.Image(
      width: ring.width,
      height: bandHeightPx + padPx * 2,
      numChannels: 4,
    );
    // Mirror about the shape's bottom edge (largest y in this y-down image).
    final axis = padPx + innerHeightPx - 1;
    final denom = math.max(bandHeightPx - 1, 1);
    for (var y = 0; y < work.height; y++) {
      final srcY = axis - (y - padPx);
      if (srcY < 0 || srcY >= ring.height) continue;
      final fade = 1.0 - (math.max(y - padPx, 0) / denom).clamp(0.0, 1.0);
      if (fade <= 0) continue;
      for (var x = 0; x < work.width; x++) {
        final pixel = ring.getPixel(x, srcY);
        if (pixel.a <= 0) continue;
        work.setPixelRgba(
          x,
          y,
          pixel.r.toInt(),
          pixel.g.toInt(),
          pixel.b.toInt(),
          (pixel.aNormalized * fade * 255).round().clamp(0, 255),
        );
      }
    }
    final blur = blurSigmaPx.clamp(0.0, 256.0);
    if (blur > 1e-6) {
      final radius = math.max(1, (blur * 1.5).round());
      work = raster.gaussianBlur(work, radius: radius);
    }
    _compositeOntoWhite(work);
    if (flipVertical) {
      work = _flipImageVertical(work);
    }
    return raster.encodePng(work);
  } catch (_) {
    return null;
  }
}

/// Rasterize a solid silhouette and Gaussian-blur it for a drop-shadow PNG.
///
/// SoftEdges feathers SourceAlpha *inside* the box. ShadowBlur must spread
/// alpha into [padPx] around the silhouette so Draw can show the halo —
/// `tokens.txt` has no ShadowBlur, and libvisio only emits a hard
/// `draw:shadow`.
Uint8List? bakeSilhouetteDropShadowPng({
  required int innerWidthPx,
  required int innerHeightPx,
  required int padPx,
  required int red,
  required int green,
  required int blue,
  required int alpha,
  required double blurSigmaPx,
  SoftEdgesSilhouetteKind kind = SoftEdgesSilhouetteKind.rectangle,
  List<({double x, double y})> polygon = const <({double x, double y})>[],
}) {
  if (innerWidthPx < 2 || innerHeightPx < 2) return null;
  if (padPx < 0) return null;
  if (alpha <= 0) return null;
  final widthPx = innerWidthPx + padPx * 2;
  final heightPx = innerHeightPx + padPx * 2;
  try {
    var work = raster.Image(
      width: widthPx,
      height: heightPx,
      numChannels: 4,
    );
    final color = raster.ColorRgba8(
      red.clamp(0, 255),
      green.clamp(0, 255),
      blue.clamp(0, 255),
      alpha.clamp(0, 255),
    );
    switch (kind) {
      case SoftEdgesSilhouetteKind.rectangle:
        raster.fillRect(
          work,
          x1: padPx,
          y1: padPx,
          x2: padPx + innerWidthPx - 1,
          y2: padPx + innerHeightPx - 1,
          color: color,
          radius: 0,
          alphaBlend: false,
        );
      case SoftEdgesSilhouetteKind.ellipse:
        final cx = padPx + (innerWidthPx - 1) / 2;
        final cy = padPx + (innerHeightPx - 1) / 2;
        final rx = math.max((innerWidthPx - 1) / 2, 0.5);
        final ry = math.max((innerHeightPx - 1) / 2, 0.5);
        for (var y = padPx; y < padPx + innerHeightPx; y++) {
          for (var x = padPx; x < padPx + innerWidthPx; x++) {
            final nx = (x + 0.5 - cx) / rx;
            final ny = (y + 0.5 - cy) / ry;
            if (nx * nx + ny * ny <= 1) {
              work.setPixelRgba(x, y, color.r.toInt(), color.g.toInt(),
                  color.b.toInt(), color.a.toInt());
            }
          }
        }
      case SoftEdgesSilhouetteKind.polygon:
        if (polygon.length < 3) return null;
        raster.fillPolygon(
          work,
          vertices: <raster.Point>[
            for (final p in polygon) raster.Point(p.x + padPx, p.y + padPx),
          ],
          color: color,
        );
    }
    final blur = blurSigmaPx.clamp(0.0, 256.0);
    if (blur > 1e-6) {
      final radius = math.max(1, (blur * 1.5).round());
      work = raster.gaussianBlur(work, radius: radius);
    }
    return raster.encodePng(work);
  } catch (_) {
    return null;
  }
}

/// Rasterize a Foreign picture's reflection for Draw.
///
/// `tokens.txt` has no Reflection*. Canvas / SVG mirror the bitmap about
/// the visual bottom, clip by [sizeFraction], fade toward the far edge,
/// and optionally blur. LibreOffice only collects ForeignData, so a save
/// bakes that treatment into a PNG sibling. Pass the Foreign frame and
/// Img* crop when the visible window is not the whole bitmap — otherwise
/// the sibling would mirror pixels Draw (and canvas / SVG) already clip.
/// [flipY] matches a FlipY source: canvas FlipY's the bitmap first, so
/// the visual bottom (original top) is nearest, then the plate sits
/// above in local Y and PNG row 0 maps to max Y — the band is flipped
/// so the near-axis rows land on min Y.
Uint8List? bakePictureReflectionPng({
  required VsdxImage image,
  required double sizeFraction,
  required double transparency,
  required double blurSigmaPx,
  required double padInches,
  required double displayWidthInches,
  double frameWidthInches = 0,
  double frameHeightInches = 0,
  double imgOffsetXInches = 0,
  double imgOffsetYInches = 0,
  double? imgWidthInches,
  double? imgHeightInches,
  bool flipY = false,
}) {
  if (padInches < 0) return null;
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
  final trans = transparency.clamp(0.0, 1.0);
  final alphaScale = (1.0 - trans).clamp(0.0, 1.0);
  if (alphaScale <= 1e-9) return null;
  try {
    var src = decoded;
    if (src.numChannels < 4) {
      src = src.convert(numChannels: 4);
    }
    if (frameWidthInches > 1e-9 &&
        visioPictureFrameIsCropped(
          frameWidthInches: frameWidthInches,
          frameHeightInches: frameHeightInches,
          imgOffsetXInches: imgOffsetXInches,
          imgOffsetYInches: imgOffsetYInches,
          imgWidthInches: imgWidthInches,
          imgHeightInches: imgHeightInches,
        )) {
      final composited = _compositeVisioPictureIntoFrame(
        source: src,
        frameWidthInches: frameWidthInches,
        frameHeightInches: frameHeightInches,
        imgOffsetXInches: imgOffsetXInches,
        imgOffsetYInches: imgOffsetYInches,
        imgWidthInches: imgWidthInches ?? frameWidthInches,
        imgHeightInches: imgHeightInches ?? frameHeightInches,
      );
      if (composited == null) return null;
      src = composited.image;
    }
    if (flipY) {
      src = _flipImageVertical(src);
    }
    final frac = sizeFraction.clamp(0.01, 1.0);
    final cropH = math.max(1, (src.height * frac).round());
    final displayW = math.max(displayWidthInches.abs(), 1e-6);
    final padPx = padInches > 1e-9
        ? math.max(1, (padInches / displayW * src.width).round())
        : 0;
    final innerW = src.width;
    final innerH = cropH;
    final widthPx = innerW + padPx * 2;
    final heightPx = innerH + padPx * 2;
    var work = raster.Image(
      width: widthPx,
      height: heightPx,
      numChannels: 4,
    );
    final denom = math.max(innerH - 1, 1);
    for (var y = 0; y < innerH; y++) {
      // Flipped source: original bottom is row 0. Fade toward the far edge.
      final fade = 1.0 - y / denom;
      final srcY = src.height - 1 - y;
      for (var x = 0; x < innerW; x++) {
        final pixel = src.getPixel(x, srcY);
        final a = (pixel.aNormalized * alphaScale * fade).clamp(0.0, 1.0);
        work.setPixelRgba(
          x + padPx,
          y + padPx,
          pixel.r.toInt(),
          pixel.g.toInt(),
          pixel.b.toInt(),
          (a * 255).round().clamp(0, 255),
        );
      }
    }
    final blur = blurSigmaPx.clamp(0.0, 256.0);
    if (blur > 1e-6) {
      final radius = math.max(1, (blur * 1.5).round());
      work = raster.gaussianBlur(work, radius: radius);
    }
    if (flipY) {
      work = _flipImageVertical(work);
    }
    return raster.encodePng(work);
  } catch (_) {
    return null;
  }
}
