import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:vsdx/vsdx.dart';

/// Export every foreground page of [doc] to a **vector** PDF (SVG paths →
/// PDF operators via [pw.SvgImage]). Background pages (`Background="1"`) are
/// composited as underlays through [VsdxDocument.backgroundFor]; non-printable
/// layers are omitted.
///
/// Falls back to an empty document when there are no pages to export.
Future<Uint8List> exportDocumentToPdf(VsdxDocument doc) async {
  final pdf = pw.Document(
    title: doc.title,
    creator: doc.creator ?? 'Editor for Visio Diagrams',
  );
  final serializer = VsdxToSvgSerializer(
    // 72 px/in matches PDF's point unit so 1 SVG user unit = 1 pt.
    pxPerInch: 72.0,
    layerFilter: SvgLayerFilter.print,
    skipBackgroundPages: true,
  );

  final pages = <VsdxPage>[
    for (final p in doc.pages)
      if (!p.isBackgroundPage) p,
  ];
  final exportPages = pages.isEmpty ? doc.pages : pages;

  for (final page in exportPages) {
    final wIn = page.widthInches <= 0 ? 8.5 : page.widthInches;
    final hIn = page.heightInches <= 0 ? 11.0 : page.heightInches;
    final wPt = wIn * PdfPageFormat.inch;
    final hPt = hIn * PdfPageFormat.inch;
    final svg = serializer.serializePage(
      page,
      theme: doc.theme,
      images: doc.images,
      underlayPage: doc.backgroundFor(page),
    );
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(wPt, hPt),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.SizedBox(
          width: wPt,
          height: hPt,
          child: pw.SvgImage(
            svg: svg,
            fit: pw.BoxFit.fill,
            width: wPt,
            height: hPt,
          ),
        ),
      ),
    );
  }
  return pdf.save();
}
