/// Public entry for legacy Visio binary (`.vsd`) → [VsdxDocument].
library;

import 'dart:typed_data';

import '../../core/exceptions.dart';
import '../../model/document.dart';
import '../../model/page.dart';
import '../../writer/vsdx_writer.dart';
import 'cfb/compound_file.dart';
import 'vsd_metadata.dart';
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
    final doc = VsdBinaryParser(stream).parse();
    final meta = _readOleMeta(cfb);
    final modified = _isoSecond(cfb.rootModifiedDateTime);
    if (meta == null && modified == null) return doc;
    return doc.copyWith(
      title: meta?.title ?? doc.title,
      creator: meta?.creator ?? doc.creator,
      subject: meta?.subject ?? doc.subject,
      keywords: meta?.keywords ?? doc.keywords,
      description: meta?.description ?? doc.description,
      created: modified ?? doc.created,
      modified: modified ?? doc.modified,
      language: meta?.language ?? doc.language,
      category: meta?.category ?? doc.category,
      company: meta?.company ?? doc.company,
      template: meta?.template ?? doc.template,
    );
  }
}

VsdOleMetaData? _readOleMeta(CompoundFile cfb) {
  try {
    final summary = cfb.readStream('\x05SummaryInformation');
    final documentSummary = cfb.readStream('\x05DocumentSummaryInformation');
    final primary = summary == null || summary.isEmpty
        ? null
        : parseOleSummaryInformation(summary);
    final extended = documentSummary == null || documentSummary.isEmpty
        ? null
        : parseOleSummaryInformation(documentSummary);
    return primary?.merge(extended) ?? extended;
  } catch (_) {
    return null;
  }
}

String? _isoSecond(DateTime? value) {
  if (value == null) return null;
  final utc = value.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${two(utc.month)}-${two(utc.day)}T'
      '${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}Z';
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
  final empty = VsdxWriter().emptyDocument(
    widthInches: first.widthInches,
    heightInches: first.heightInches,
    title: doc.title,
    creator: doc.creator ?? 'Editor for Visio Diagrams',
    subject: doc.subject,
    keywords: doc.keywords,
    description: doc.description,
    lastModifiedBy: doc.lastModifiedBy,
    created: doc.created,
    modified: doc.modified,
    language: doc.language,
    category: doc.category,
    company: doc.company,
    template: doc.template,
  );
  final remapped = <VsdxPage>[
    first.copyWith(id: 0),
    for (var i = 1; i < pages.length; i++) pages[i],
  ];
  final edited = doc.copyWith(pages: remapped);
  return const VsdxWriter(preserveTextBlockCoordinates: true)
      .write(originalBytes: empty, edited: edited);
}
