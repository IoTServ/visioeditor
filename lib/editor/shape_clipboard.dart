import 'dart:convert';

import 'package:vsdx/vsdx.dart';

/// Codec for the system clipboard: a tiny one-page `.vsdx` payload carrying
/// the copied shapes (draw.io-style cross-instance paste within this app).
///
/// Envelope: `visioeditor-shapes-v1:` + base64(OPC bytes). Plain text without
/// the prefix is treated as a text-box paste by [EditorController].
abstract final class ShapeClipboardCodec {
  static const prefix = 'visioeditor-shapes-v1:';

  static final DocumentParser _parser = DocumentParser();
  static final VsdxWriter _writer = VsdxWriter();

  /// Pack [shapes] into a clipboard envelope string.
  static String encode(List<VsdxShape> shapes) {
    if (shapes.isEmpty) return '';
    final blank = _writer.emptyDocument();
    var doc = _parser.parse(blank);
    var page = doc.pages.first;
    for (final s in shapes) {
      // Image media parts are session-local — skip them for the system clip
      // (in-memory clipboard still holds the original with the image).
      if (s.hasImage) continue;
      var nextId = page.nextFreeShapeId();
      page = page.addShape(s.withRemappedIds(() => nextId++));
    }
    if (page.shapes.isEmpty) return '';
    doc = doc.replacePage(0, page);
    final bytes = _writer.write(originalBytes: blank, edited: doc);
    return prefix + base64Encode(bytes);
  }

  /// Decode an envelope into shapes, or `null` if [text] is not ours.
  static List<VsdxShape>? decode(String text) {
    final trimmed = text.trim();
    if (!trimmed.startsWith(prefix)) return null;
    try {
      final bytes = base64Decode(trimmed.substring(prefix.length));
      final doc = _parser.parse(bytes);
      if (doc.pages.isEmpty) return const <VsdxShape>[];
      return doc.pages.first.shapes;
    } catch (_) {
      return null;
    }
  }

  static bool looksLikeEnvelope(String text) =>
      text.trim().startsWith(prefix);
}
