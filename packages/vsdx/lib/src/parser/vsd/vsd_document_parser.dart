/// Public entry for legacy Visio binary (`.vsd`) → [VsdxDocument].
library;

import 'dart:typed_data';

import '../../core/exceptions.dart';
import '../../model/document.dart';
import '../../model/master.dart';
import '../../model/page.dart';
import '../../model/shape.dart';
import '../../model/user_property.dart';
import '../../writer/vsdx_writer.dart';
import 'cfb/compound_file.dart';
import 'vsd_metadata.dart';
import 'vsd_parser.dart';

/// libvisio's `checkVisioMagic` signature, including the terminator.
const _visioMagic = 'Visio (TM) Drawing\r\n\u0000';

/// Detects a legacy binary Visio document.
///
/// Mirrors libvisio's `isBinaryVisioDocument`, which LibreOffice's Visio import
/// filter reaches through `VisioDocument::isSupported`: take the `VisioDocument`
/// substream when the input is an OLE2 compound file, otherwise treat the input
/// itself as that stream, then require the Visio magic and a version byte the
/// binary parsers understand.
bool looksLikeVisioBinary(Uint8List bytes) {
  return _visioDocumentStream(bytes) != null;
}

/// The record stream libvisio hands to its binary parsers, or `null` when
/// [bytes] is not a legacy binary Visio document.
Uint8List? _visioDocumentStream(Uint8List bytes) {
  try {
    Uint8List? stream;
    if (looksLikeCfb(bytes)) {
      stream = CompoundFile.open(bytes).readStream('VisioDocument');
    }
    // A bare `VisioDocument` stream (an OLE2 export, or a Visio 1–5 file that
    // was never wrapped) is what libvisio falls back to when the input has no
    // such substream. Its parsers read the identical record layout either way.
    stream ??= bytes;
    if (stream.length < 0x20) return null;
    if (String.fromCharCodes(stream.sublist(0, _visioMagic.length)) !=
        _visioMagic) {
      return null;
    }
    final version = stream[0x1A];
    if ((version < 1 || version > 6) && version != 11) return null;
    return stream;
  } catch (_) {
    return null;
  }
}

/// Parses a `.vsd` (OLE2) package into the editable model.
class VsdDocumentParser {
  const VsdDocumentParser();

  /// Parse [bytes] (full `.vsd`/`.vss`/`.vst` file) → [VsdxDocument].
  ///
  /// Supports legacy Visio versions 1–5 through the shared VSD5-family
  /// layout, Visio 2000 (version 6), and Visio 2002–2010 (version 11),
  /// matching libvisio's binary parser dispatch.
  /// Set [extractStencils] for a standalone `.vss`. This mirrors libvisio's
  /// `VisioDocument::parseStencils` entry point, which exposes every master
  /// page as a drawable page instead of returning the stencil's placeholder
  /// drawing page.
  VsdxDocument parse(Uint8List bytes, {bool extractStencils = false}) {
    if (!looksLikeCfb(bytes)) {
      // libvisio parses a bare `VisioDocument` record stream too, falling back
      // to the input itself whenever there is no OLE2 substream to open. Such
      // a stream carries none of the OLE metadata read below.
      final flat = _visioDocumentStream(bytes);
      if (flat == null) {
        throw const VsdxFormatException(
          'Not a Visio binary (.vsd) compound file',
        );
      }
      return VsdBinaryParser(flat).parse(extractStencils: extractStencils);
    }
    final cfb = CompoundFile.open(bytes);
    final stream = cfb.readStream('VisioDocument');
    if (stream == null) {
      throw const VsdxFormatException('Missing VisioDocument stream');
    }
    final doc =
        VsdBinaryParser(stream).parse(extractStencils: extractStencils);
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
  final synthetic = _prepareForOpcSynthesis(doc);
  final pages = synthetic.pages;
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
    title: synthetic.title,
    creator: synthetic.creator ?? 'Editor for Visio Diagrams',
    subject: synthetic.subject,
    keywords: synthetic.keywords,
    description: synthetic.description,
    lastModifiedBy: synthetic.lastModifiedBy,
    created: synthetic.created,
    modified: synthetic.modified,
    language: synthetic.language,
    category: synthetic.category,
    company: synthetic.company,
    template: synthetic.template,
  );
  final remapped = <VsdxPage>[
    first.copyWith(id: 0),
    for (var i = 1; i < pages.length; i++) pages[i],
  ];
  final edited = synthetic.copyWith(pages: remapped);
  const writer = VsdxWriter(preserveTextBlockCoordinates: true);
  final pagesAndMedia = writer.write(originalBytes: empty, edited: edited);
  return writer.attachSyntheticMasters(
    originalBytes: pagesAndMedia,
    document: edited,
  );
}

VsdxDocument _prepareForOpcSynthesis(VsdxDocument document) {
  final masters = document.masters.all.toList(growable: false);

  // DiagramML permits Master ID=0, while VSDX consumers including
  // libvisio/LibreOffice use zero as the no-master sentinel.
  final used = <int>{
    for (final master in masters)
      if (master.id > 0) master.id,
  };
  final idMap = <int, int>{};
  var nextId = 1;
  for (final master in masters) {
    if (master.id > 0) {
      idMap[master.id] = master.id;
      continue;
    }
    while (used.contains(nextId)) {
      nextId++;
    }
    idMap[master.id] = nextId;
    used.add(nextId);
    nextId++;
  }

  VsdxShape rewriteShape(VsdxShape shape) {
    final exactArrowCells = <VsdxUserCell>[
      for (final cell in shape.userCells)
        if (cell.name != VsdxShape.userVsdBeginArrowSize &&
            cell.name != VsdxShape.userVsdEndArrowSize)
          cell,
      if (shape.line.hasBeginArrow)
        VsdxUserCell(
          name: VsdxShape.userVsdBeginArrowSize,
          value: '${shape.line.beginArrowSizeInches}',
        ),
      if (shape.line.hasEndArrow)
        VsdxUserCell(
          name: VsdxShape.userVsdEndArrowSize,
          value: '${shape.line.endArrowSizeInches}',
        ),
    ];
    return shape.copyWith(
      masterId: shape.masterId == null
          ? null
          : (idMap[shape.masterId!] ?? shape.masterId),
      children: <VsdxShape>[
        for (final child in shape.children) rewriteShape(child),
      ],
      userCells: List<VsdxUserCell>.unmodifiable(exactArrowCells),
    );
  }

  final rewrittenMasters = <int, VsdxMaster>{};
  for (final master in masters) {
    final id = idMap[master.id] ?? master.id;
    rewrittenMasters[id] = VsdxMaster(
      id: id,
      name: master.name,
      prototype: rewriteShape(master.prototype),
      additionalPrototypes: <VsdxShape>[
        for (final shape in master.additionalPrototypes) rewriteShape(shape),
      ],
      pageWidthInches: master.pageWidthInches,
      pageHeightInches: master.pageHeightInches,
      pageSheet: master.pageSheet,
    );
  }
  return document.copyWith(
    pages: <VsdxPage>[
      for (final page in document.pages)
        page.copyWith(shapes: <VsdxShape>[
          for (final shape in page.shapes) rewriteShape(shape),
        ]),
    ],
    masters: MasterRegistry(Map<int, VsdxMaster>.unmodifiable(
      rewrittenMasters,
    )),
  );
}
