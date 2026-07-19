import 'dart:convert';

import 'package:vsdx/vsdx.dart';

/// Decoded system-clipboard payload (shapes + optional Connect rows + media).
class ShapeClipboardPayload {
  const ShapeClipboardPayload({
    required this.shapes,
    this.connects = const <VsdxConnect>[],
    this.images = ImageRegistry.empty,
  });

  final List<VsdxShape> shapes;
  final List<VsdxConnect> connects;

  /// Embedded picture bytes referenced by [shapes] (may be empty).
  final ImageRegistry images;
}

/// Codec for the system clipboard: a tiny one-page `.vsdx` payload carrying
/// the copied shapes (draw.io-style cross-instance paste within this app).
///
/// Envelope: `visioeditor-shapes-v1:` + base64(OPC bytes). Plain text without
/// the prefix is treated as a text-box paste by [EditorController].
abstract final class ShapeClipboardCodec {
  static const prefix = 'visioeditor-shapes-v1:';

  static final DocumentParser _parser = DocumentParser();
  static final VsdxWriter _writer = VsdxWriter();

  /// Pack [shapes] (and optional [connects] / [images]) into a clipboard
  /// envelope string. Picture media referenced by the shape tree is embedded
  /// so cross-instance paste does not leave dangling `imagePartName`s.
  static String encode(
    List<VsdxShape> shapes, {
    List<VsdxConnect> connects = const <VsdxConnect>[],
    ImageRegistry images = ImageRegistry.empty,
  }) {
    if (shapes.isEmpty) return '';
    final blank = _writer.emptyDocument();
    var doc = _parser.parse(blank);
    var page = doc.pages.first;
    final idMap = <int, int>{};
    var registry = ImageRegistry.empty;

    void collectMedia(VsdxShape s) {
      final part = s.imagePartName;
      if (part != null) {
        final img = images.findByPart(part);
        if (img != null) registry = registry.withImage(img);
      }
      for (final c in s.children) {
        collectMedia(c);
      }
    }

    for (final s in shapes) {
      collectMedia(s);
      var nextId = page.nextFreeShapeId();
      page = page.addShape(
        s.withRemappedIds(() => nextId++, idMap: idMap),
      );
    }
    if (page.shapes.isEmpty) return '';
    if (connects.isNotEmpty) {
      final remapped = <VsdxConnect>[
        for (final c in connects)
          if (idMap.containsKey(c.fromSheetId) &&
              idMap.containsKey(c.toSheetId))
            VsdxConnect(
              fromSheetId: idMap[c.fromSheetId]!,
              fromCell: c.fromCell,
              fromPart: c.fromPart,
              toSheetId: idMap[c.toSheetId]!,
              toCell: c.toCell,
              toPart: c.toPart,
            ),
      ];
      if (remapped.isNotEmpty) {
        page = page.copyWith(connects: remapped);
      }
    }
    doc = doc.copyWith(images: registry).replacePage(0, page);
    final bytes = _writer.write(originalBytes: blank, edited: doc);
    return prefix + base64Encode(bytes);
  }

  /// Decode an envelope into shapes, or `null` if [text] is not ours.
  static List<VsdxShape>? decode(String text) => decodeEnvelope(text)?.shapes;

  /// Decode an envelope into shapes + Connect rows + media, or `null` if not
  /// ours.
  static ShapeClipboardPayload? decodeEnvelope(String text) {
    final trimmed = text.trim();
    if (!trimmed.startsWith(prefix)) return null;
    try {
      final bytes = base64Decode(trimmed.substring(prefix.length));
      final doc = _parser.parse(bytes);
      if (doc.pages.isEmpty) {
        return const ShapeClipboardPayload(shapes: <VsdxShape>[]);
      }
      final page = doc.pages.first;
      return ShapeClipboardPayload(
        shapes: page.shapes,
        connects: page.connects,
        images: doc.images,
      );
    } catch (_) {
      return null;
    }
  }

  static bool looksLikeEnvelope(String text) =>
      text.trim().startsWith(prefix);
}
