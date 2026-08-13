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
import 'wmf_parser.dart';

/// LibreOffice renders embedded OLE objects on its classic "Blue 2"
/// presentation surface. When an Excel chart/sheet has a transparent WMF/EMF
/// preview the surface is composited behind it; when an object has no usable
/// presentation stream the same colour remains as the visible fallback.
const int libreOfficeOleWorkbookBackgroundArgb = 0xff729fcf;

/// Whether [oleBytes] is an embedded Excel workbook package.
bool isOleWorkbook(Uint8List oleBytes) {
  if (!looksLikeCfb(oleBytes)) return false;
  try {
    final cfb = CompoundFile.open(oleBytes);
    return cfb.hasEntry('Workbook') || cfb.hasEntry('Book');
  } catch (_) {
    return false;
  }
}

/// Pull EMF/WMF presentation bytes out of an OLE2 package, or `null`.
Uint8List? extractOlePresentationMetafile(Uint8List oleBytes) {
  if (!looksLikeCfb(oleBytes)) return null;
  try {
    final cfb = CompoundFile.open(oleBytes);
    for (final name in cfb.entryNames) {
      // Stream names are often prefixed with \x01 / \x02 control chars.
      final normalizedName = name.toUpperCase();
      if (!normalizedName.contains('OLEPRES') &&
          !normalizedName.contains('CONTENTS')) {
        continue;
      }
      final data = cfb.readStream(name);
      if (data == null || data.length < 40) continue;
      final emfOff = findEmfOffset(data);
      if (emfOff != null) {
        return data.sublist(emfOff);
      }
      // OLE presentation headers vary between Office and Equation versions.
      // Validate each plausible even-aligned prefix instead of assuming that
      // a WMF payload always begins at byte 0 or byte 40.
      final scanEnd = data.length < 512 ? data.length : 512;
      for (var offset = 0; offset + 18 <= scanEnd; offset += 2) {
        final candidate = Uint8List.sublistView(data, offset);
        if (looksLikeWmf(candidate)) return candidate;
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
