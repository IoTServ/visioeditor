import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:vsdx/vsdx.dart';

import 'pdf_font_loader_stub.dart'
    if (dart.library.io) 'pdf_font_loader_io.dart';

/// Export every foreground page of [doc] to a **vector** PDF (SVG paths →
/// PDF operators via [pw.SvgImage]). Background pages (`Background="1"`) are
/// composited as underlays through [VsdxDocument.backgroundFor]; non-printable
/// layers are omitted.
///
/// Shapes with a primary external hyperlink get a [pw.UrlLink] annotation over
/// their page AABB so the link survives beyond SVG `<a>` (which `SvgImage`
/// does not promote to PDF annotations). Overlays honour the same print-layer,
/// collapsed-host, and covered-cell filters as [VsdxToSvgSerializer].
///
/// Falls back to an empty document when there are no pages to export.
///
/// When a Unicode system font is available it is registered for SVG text so
/// CJK / non-Latin labels do not hit Helvetica's Latin-1 encoder.
Future<Uint8List> exportDocumentToPdf(VsdxDocument doc) async {
  final unicode = await loadPdfUnicodeFont();
  final theme = unicode == null
      ? null
      : pw.ThemeData.withFont(base: unicode, bold: unicode, italic: unicode);
  final pdf = pw.Document(
    title: doc.title,
    creator: doc.creator ?? 'Editor for Visio Diagrams',
    theme: theme,
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

  pw.Font? fontLookup(String family, String style, String weight) => unicode;

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
    final links = _pdfHyperlinkOverlays(page);
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(wPt, hPt),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.SizedBox(
          width: wPt,
          height: hPt,
          child: pw.Stack(
            children: <pw.Widget>[
              pw.SvgImage(
                svg: svg,
                fit: pw.BoxFit.fill,
                width: wPt,
                height: hPt,
                customFontLookup: unicode == null ? null : fontLookup,
              ),
              ...links,
            ],
          ),
        ),
      ),
    );
  }
  return pdf.save();
}

/// Transparent [pw.UrlLink] boxes over shapes that have a clickable primary
/// hyperlink. Visio/PDF share a bottom-left, Y-up page frame in inches/points.
List<pw.Widget> _pdfHyperlinkOverlays(VsdxPage page) {
  final printable =
      page.layers.isEmpty ? null : page.printableLayerIds;
  final out = <pw.Widget>[];

  void walk(VsdxShape shape) {
    if (printable != null &&
        shape.layerMemberIds.isNotEmpty &&
        !shape.isOnAnyLayer(printable)) {
      return;
    }
    if (TableOps.isCovered(shape)) return;

    final h = shape.primaryHyperlink;
    if (h != null && !h.invisible) {
      final target = h.effectiveTarget?.trim();
      if (target != null && target.isNotEmpty && _isExternalPdfUrl(target)) {
        final aabb = page.shapePageAabb(shape.id);
        if (aabb != null) {
          final left = aabb.left * PdfPageFormat.inch;
          final bottom = aabb.bottom * PdfPageFormat.inch;
          final width = (aabb.right - aabb.left) * PdfPageFormat.inch;
          final height = (aabb.top - aabb.bottom) * PdfPageFormat.inch;
          if (width > 0.5 && height > 0.5) {
            out.add(
              pw.Positioned(
                left: left,
                bottom: bottom,
                child: pw.UrlLink(
                  destination: target,
                  child: pw.SizedBox(width: width, height: height),
                ),
              ),
            );
          }
        }
      }
    }

    if (!shape.collapsed) {
      for (final c in shape.children) {
        walk(c);
      }
    }
  }

  for (final s in page.shapes) {
    walk(s);
  }
  return out;
}

bool _isExternalPdfUrl(String target) {
  final t = target.toLowerCase();
  return t.startsWith('http://') ||
      t.startsWith('https://') ||
      t.startsWith('mailto:') ||
      t.startsWith('file:');
}
