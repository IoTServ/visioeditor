/// Unified entry: turn EMF / WMF / OLE bytes into a [MetafileDrawing].
library;

import 'dart:typed_data';

import 'emf_embedded_bitmap.dart';
import 'emf_vector_parser.dart';
import 'metafile_drawing.dart';
import 'ole_preview.dart';
import 'wmf_parser.dart';

export 'metafile_drawing.dart';
export 'wmf_parser.dart';
export 'emf_vector_parser.dart';
export 'ole_preview.dart';

/// Best-effort vector parse for canvas paint. Returns `null` when the bytes
/// are not a recognised metafile or contain no drawable records.
///
/// Callers that already tried [extractEmfEmbeddedBitmap] should still call
/// this for pure-vector EMF/WMF and OLE presentations.
MetafileDrawing? parseMetafileDrawing(
  Uint8List bytes, {
  String mimeType = '',
  String partName = '',
}) {
  final m = mimeType.toLowerCase();
  final p = partName.toLowerCase();
  final isOle = m.contains('ole') || m.startsWith('object/');
  final isWmf = m.contains('wmf') || p.endsWith('.wmf');
  final isEmf = m.contains('emf') || p.endsWith('.emf');

  Uint8List payload = bytes;
  if (isOle) {
    final extracted = extractOlePresentationMetafile(bytes);
    if (extracted == null) return null;
    payload = extracted;
  }

  // Match LibreOffice's WMF reader: Office may carry the authoritative EMF
  // in one or more META_ESCAPE/MFCOMMENT `WMFC` chunks, followed by a lower
  // fidelity WMF fallback. Prefer the validated enhanced metafile when it is
  // present; private escapes such as MathType remain on the WMF path.
  final embeddedEmf = extractWmfEmbeddedEmf(payload);
  if (embeddedEmf != null) {
    final d = parseEmfDrawing(embeddedEmf);
    if (d != null && !d.isEmpty) return d;
  }

  // An explicit WMF media type/extension is authoritative. Scanning the
  // entire byte stream for an EMF header before trying WMF can match ordinary
  // WMF record payload by accident and return a plausible but truncated EMF
  // drawing. This happens in the upstream Visio 5 plan thumbnail: the false
  // positive contains only 12 of its 80 drawing operations. Keep a genuine
  // leading EMF signature authoritative for mislabelled parts, otherwise
  // route known WMF data through its parser first.
  if ((isWmf || looksLikeWmf(payload)) && !looksLikeEmf(payload)) {
    final d = parseWmfDrawing(payload);
    if (d != null && !d.isEmpty) return d;
    // A validated WMF container must not fall through to the loose embedded
    // EMF signature scan: a malformed WMFC first chunk can contain a complete
    // EMF header plus partial drawing records.
    return null;
  }

  // Prefer EMF when signature matches (OLE presentations, .emf parts).
  if (looksLikeEmf(payload) || findEmfOffset(payload) != null || isEmf) {
    final d = parseEmfDrawing(payload);
    if (d != null && !d.isEmpty) return d;
  }
  // OLE CF_METAFILEPICT previews commonly contain a standard (non-placeable)
  // WMF. Once the presentation stream has been extracted, let the WMF parser
  // validate it instead of routing OLE payloads back to EMF only.
  if (isOle) {
    final d = parseWmfDrawing(payload);
    if (d != null && !d.isEmpty) return d;
  }
  if (isWmf ||
      (payload.length > 4 &&
          payload[0] == 0xd7 &&
          payload[1] == 0xcd &&
          payload[2] == 0xc6 &&
          payload[3] == 0x9a) ||
      (!isEmf && !isOle)) {
    final d = parseWmfDrawing(payload);
    if (d != null && !d.isEmpty) return d;
  }
  // Last chance: EMF again for mislabelled parts.
  return parseEmfDrawing(payload);
}

/// Raster-friendly bytes if the metafile is really a wrapped bitmap.
Uint8List? extractMetafileRaster(Uint8List bytes, {String mimeType = ''}) {
  var payload = bytes;
  if (mimeType.toLowerCase().contains('ole') ||
      mimeType.toLowerCase().startsWith('object/')) {
    final extracted = extractOlePresentationMetafile(bytes);
    if (extracted == null) return null;
    payload = extracted;
  }
  payload = extractWmfEmbeddedEmf(payload) ?? payload;
  return extractEmfEmbeddedBitmap(payload);
}
