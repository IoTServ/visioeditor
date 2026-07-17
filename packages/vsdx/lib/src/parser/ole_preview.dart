/// Extract a canvas-ready preview from an OLE Compound File (`object/ole`).
///
/// Visio embeds Excel / Equation / … objects as CFB blobs with an
/// `\x02OlePres000` presentation stream. That stream commonly wraps an EMF
/// (CF_ENHMETAFILE) — we return the EMF bytes (or a nested WMF) so the
/// metafile pipeline can rasterise them.
library;

import 'dart:typed_data';

import 'emf_vector_parser.dart';
import 'vsd/cfb/compound_file.dart';

/// Pull EMF/WMF presentation bytes out of an OLE2 package, or `null`.
Uint8List? extractOlePresentationMetafile(Uint8List oleBytes) {
  if (!looksLikeCfb(oleBytes)) return null;
  try {
    final cfb = CompoundFile.open(oleBytes);
    for (final name in cfb.entryNames) {
      // Stream names are often prefixed with \x01 / \x02 control chars.
      if (!name.contains('OlePres') && !name.contains('CONTENTS')) {
        continue;
      }
      final data = cfb.readStream(name);
      if (data == null || data.length < 40) continue;
      final emfOff = findEmfOffset(data);
      if (emfOff != null) {
        return data.sublist(emfOff);
      }
      // Placeable WMF
      if (data.length > 22 &&
          data[0] == 0xd7 &&
          data[1] == 0xcd &&
          data[2] == 0xc6 &&
          data[3] == 0x9a) {
        return data;
      }
      // CF_METAFILEPICT (3): presentation header then WMF without placeable.
      if (data.length > 40) {
        final bd = ByteData.sublistView(data);
        final cf = bd.getUint32(4, Endian.little);
        if (cf == 3 /* CF_METAFILEPICT */ || cf == 14 /* CF_ENHMETAFILE */) {
          // Skip ~40 byte OLE presentation header used by POI samples.
          final body = data.sublist(40);
          final nested = findEmfOffset(body);
          if (nested != null) return body.sublist(nested);
          if (body.length > 18 &&
              (body[0] == 1 || body[0] == 2) &&
              body[1] == 0) {
            return body;
          }
        }
      }
    }
  } catch (_) {
    return null;
  }
  return null;
}
