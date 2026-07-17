/// Unified Visio open entry: `.vsdx` (OPC) or `.vsd` (OLE2 binary).
library;

import 'dart:typed_data';

import '../core/exceptions.dart';
import '../model/document.dart';
import 'document_parser.dart';
import 'package_reader.dart';
import 'vsd/cfb/compound_file.dart';
import 'vsd/vsd_document_parser.dart';

/// Result of [parseVisio] including a synthetic `.vsdx` baseline when the
/// source was binary `.vsd`.
class VisioParseResult {
  const VisioParseResult({
    required this.document,
    required this.originalBytes,
    required this.importedFromVsd,
  });

  final VsdxDocument document;

  /// Bytes suitable as [VsdxWriter.write] baseline (always OPC `.vsdx`).
  final Uint8List originalBytes;

  /// `true` when the input was a legacy `.vsd` (caller should prompt Save As).
  final bool importedFromVsd;
}

bool looksLikeZipOpc(Uint8List bytes) {
  if (bytes.length < 4) return false;
  // ZIP local file header / empty archive / EOCD.
  return bytes[0] == 0x50 && bytes[1] == 0x4B;
}

/// Parse Visio drawing bytes (`.vsdx` family or `.vsd`) into an editable model.
///
/// For `.vsd`, synthesises a `.vsdx` package so subsequent saves use the
/// existing load-preserve-patch writer.
VisioParseResult parseVisio(Uint8List bytes) {
  if (looksLikeZipOpc(bytes)) {
    // Confirm it is a Visio OPC package (not a random ZIP).
    try {
      final doc = const DocumentParser().parse(bytes);
      return VisioParseResult(
        document: doc,
        originalBytes: bytes,
        importedFromVsd: false,
      );
    } on VsdxException {
      rethrow;
    }
  }
  if (looksLikeCfb(bytes) || looksLikeVisioBinary(bytes)) {
    final doc = const VsdDocumentParser().parse(bytes);
    // Synthesise OPC baseline for VsdxWriter; keep the binary-parsed model for
    // editing so ForeignData frames / field text / advanced geometry are not
    // lost by a write→reparse fidelity gap.
    final synth = synthesizeVsdx(doc);
    return VisioParseResult(
      document: doc,
      originalBytes: synth,
      importedFromVsd: true,
    );
  }
  throw const VsdxFormatException(
    'Unsupported file: expected .vsdx (OPC ZIP) or .vsd (OLE2)',
  );
}

/// Convenience: open OPC package bytes (existing API wrapper).
VsdxPackage? tryOpenOpc(Uint8List bytes) {
  if (!looksLikeZipOpc(bytes)) return null;
  try {
    return VsdxPackage.open(bytes);
  } catch (_) {
    return null;
  }
}
