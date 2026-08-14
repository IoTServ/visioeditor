/// Unified Visio open entry: OPC or legacy OLE2 Visio files.
library;

import 'dart:typed_data';

import '../core/exceptions.dart';
import '../model/document.dart';
import 'document_parser.dart';
import 'package_reader.dart';
import 'vsd/cfb/compound_file.dart';
import 'vsd/vsd_document_parser.dart';
import 'vdx/vdx_document_parser.dart';

/// Result of [parseVisio], including a synthetic `.vsdx` baseline for
/// import-only binary/XML files and standalone stencil packages.
class VisioParseResult {
  const VisioParseResult({
    required this.document,
    required this.originalBytes,
    required this.importedFromVsd,
  });

  final VsdxDocument document;

  /// Bytes suitable as [VsdxWriter.write] baseline (always OPC `.vsdx`).
  final Uint8List originalBytes;

  /// `true` for legacy binary/XML or standalone stencil input (prompt Save As).
  final bool importedFromVsd;
}

bool looksLikeZipOpc(Uint8List bytes) {
  if (bytes.length < 4) return false;
  // ZIP local file header / empty archive / EOCD.
  return bytes[0] == 0x50 && bytes[1] == 0x4B;
}

/// Parse Visio bytes into an editable model.
///
/// For legacy binary/XML files, synthesises a `.vsdx` package so subsequent
/// saves use the existing load-preserve-patch writer.
VisioParseResult parseVisio(Uint8List bytes, {String? sourceName}) {
  final lowerName = sourceName?.toLowerCase() ?? '';
  if (looksLikeZipOpc(bytes)) {
    // Confirm it is a Visio OPC package (not a random ZIP).
    try {
      final extractStencils =
          lowerName.endsWith('.vssx') || lowerName.endsWith('.vssm');
      final doc = const DocumentParser().parse(
        bytes,
        extractStencils: extractStencils,
      );
      if (extractStencils) {
        return VisioParseResult(
          document: doc,
          originalBytes: synthesizeVsdx(doc),
          importedFromVsd: true,
        );
      }
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
    final extractStencils = lowerName.endsWith('.vss');
    final doc = const VsdDocumentParser().parse(
      bytes,
      extractStencils: extractStencils,
    );
    // Synthesise OPC baseline for VsdxWriter; keep the binary-parsed model for
    // editing so ForeignData frames / field text / advanced geometry are not
    // lost by a write→reparse fidelity gap. This also normalises legacy VSD5
    // TextField records: libvisio/LibreOffice can drop every field-bearing
    // label when opening that binary sample directly, but consumes all labels
    // once the same editable rows and <fld> markers are represented in VSDX.
    final synth = synthesizeVsdx(doc);
    return VisioParseResult(
      document: doc,
      originalBytes: synth,
      importedFromVsd: true,
    );
  }
  if (looksLikeVdx(bytes)) {
    final extractStencils = lowerName.endsWith('.vsx');
    final doc = const VdxDocumentParser().parse(
      bytes,
      extractStencils: extractStencils,
    );
    return VisioParseResult(
      document: doc,
      originalBytes: synthesizeVsdx(doc),
      importedFromVsd: true,
    );
  }
  throw const VsdxFormatException(
    'Unsupported file: expected Visio OPC ZIP, OLE2 binary, or DiagramML XML',
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
