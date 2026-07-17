/// Public entry for legacy Visio binary (`.vsd`) → [VsdxDocument].
library;

import 'dart:typed_data';

import '../../core/exceptions.dart';
import '../../model/document.dart';
import '../../model/page.dart';
import '../../writer/vsdx_writer.dart';
import 'cfb/compound_file.dart';
import 'vsd_parser.dart';

/// Detects OLE2 compound files that contain a VisioDocument stream.
bool looksLikeVisioBinary(Uint8List bytes) {
  if (!looksLikeCfb(bytes)) return false;
  try {
    final cfb = CompoundFile.open(bytes);
    final stream = cfb.readStream('VisioDocument');
    if (stream == null || stream.length < 0x20) return false;
    final magic = String.fromCharCodes(stream.sublist(0, 18));
    return magic == 'Visio (TM) Drawing';
  } catch (_) {
    return false;
  }
}

/// Parses a `.vsd` (OLE2) package into the editable model.
class VsdDocumentParser {
  const VsdDocumentParser();

  /// Parse [bytes] (full `.vsd` file) → [VsdxDocument].
  ///
  /// Currently supports Visio 5 (version 5), Visio 2000 (version 6), and
  /// Visio 2002–2010 (version 11).
  VsdxDocument parse(Uint8List bytes) {
    if (!looksLikeCfb(bytes)) {
      throw const VsdxFormatException(
        'Not a Visio binary (.vsd) compound file',
      );
    }
    final cfb = CompoundFile.open(bytes);
    final stream = cfb.readStream('VisioDocument');
    if (stream == null) {
      throw const VsdxFormatException('Missing VisioDocument stream');
    }
    return VsdBinaryParser(stream).parse();
  }
}

/// Build a minimal `.vsdx` from an already-parsed [doc] (used after `.vsd` import).
///
/// The result is a fresh OPC package suitable as `_originalBytes` for
/// [VsdxWriter.write] — not a fidelity-preserving OLE round-trip.
Uint8List synthesizeVsdx(VsdxDocument doc) {
  final pages = doc.pages;
  final first = pages.isEmpty
      ? const VsdxPage(
          id: 0,
          name: 'Page-1',
          widthInches: 8.5,
          heightInches: 11.0,
          shapes: [],
        )
      : pages.first;
  final empty = const VsdxWriter().emptyDocument(
    widthInches: first.widthInches,
    heightInches: first.heightInches,
  );
  final remapped = <VsdxPage>[
    first.copyWith(id: 0),
    for (var i = 1; i < pages.length; i++) pages[i],
  ];
  final edited = doc.copyWith(pages: remapped);
  return const VsdxWriter().write(originalBytes: empty, edited: edited);
}
