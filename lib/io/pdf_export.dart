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
/// does not promote to PDF annotations). In-document jumps (`#Page-N` /
/// page names) become [pw.Link] → named destinations registered via
/// [pw.Anchor] on each exported sheet. Underlay (BackPage) hyperlinks are
/// included. Degenerate 1D AABBs are inflated to a minimum hit thickness.
/// Overlays honour the same print-layer, collapsed-host, and covered-cell
/// filters as [VsdxToSvgSerializer].
///
/// Falls back to an empty document when there are no pages to export.
///
/// When a Unicode system font is available it is registered for SVG text so
/// CJK / non-Latin labels do not hit Helvetica's Latin-1 encoder.
Future<Uint8List> exportDocumentToPdf(
  VsdxDocument doc, {
  bool drawLineJumps = true,
  double lineJumpRadiusInches = kDefaultLineJumpRadiusInches,
  bool colorByLayer = false,
}) async {
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
    drawLineJumps: drawLineJumps,
    lineJumpRadiusInches: lineJumpRadiusInches,
    colorByLayer: colorByLayer,
    // package:pdf SvgImage ignores markers/filters/patterns/textPath/baseline.
    pdfCompat: true,
  );

  final pages = <VsdxPage>[
    for (final p in doc.pages)
      if (!p.isBackgroundPage) p,
  ];
  final exportPages = pages.isEmpty ? doc.pages : pages;
  final destNames = _pdfPageDestNames(exportPages);

  pw.Font? fontLookup(String family, String style, String weight) => unicode;

  for (final page in exportPages) {
    final wIn = page.widthInches <= 0 ? 8.5 : page.widthInches;
    final hIn = page.heightInches <= 0 ? 11.0 : page.heightInches;
    final wPt = wIn * PdfPageFormat.inch;
    final hPt = hIn * PdfPageFormat.inch;
    final underlay = doc.backgroundFor(page);
    final svg = serializer.serializePage(
      page,
      theme: doc.theme,
      images: doc.images,
      underlayPage: underlay,
    );
    final links = <pw.Widget>[
      ..._pdfHyperlinkOverlays(page, destNames: destNames),
      if (underlay != null)
        ..._pdfHyperlinkOverlays(
          underlay,
          destNames: destNames,
          // Clip underlay hits to the foreground page box.
          clipWidthInches: wIn,
          clipHeightInches: hIn,
        ),
    ];
    final anchors = <pw.Widget>[
      for (final name in destNames[page] ?? const <String>[])
        pw.Positioned(
          left: 0,
          top: 0,
          child: pw.Anchor(
            name: name,
            child: pw.SizedBox(width: 1, height: 1),
          ),
        ),
    ];
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
              ...anchors,
              ...links,
            ],
          ),
        ),
      ),
    );
  }
  return pdf.save();
}

/// Named destinations for each exported page (`Page-2`, `#Page-2`, …).
Map<VsdxPage, List<String>> _pdfPageDestNames(List<VsdxPage> pages) {
  final out = <VsdxPage, List<String>>{};
  for (var i = 0; i < pages.length; i++) {
    final page = pages[i];
    final names = <String>{};
    void add(String? raw) {
      final t = raw?.trim();
      if (t == null || t.isEmpty) return;
      names.add(t);
      if (t.startsWith('#')) {
        names.add(t.substring(1));
      } else {
        names.add('#$t');
      }
    }

    add(page.name);
    add('Page-${i + 1}');
    out[page] = names.toList(growable: false);
  }
  return out;
}

/// Minimum PDF hit-box thickness for flat 1D AABBs (~8 pt).
const double _kMinPdfLinkThicknessPt = 8.0;

/// Transparent link boxes over shapes that have a clickable primary hyperlink.
/// Visio/PDF share a bottom-left, Y-up page frame in inches/points.
List<pw.Widget> _pdfHyperlinkOverlays(
  VsdxPage page, {
  required Map<VsdxPage, List<String>> destNames,
  double? clipWidthInches,
  double? clipHeightInches,
}) {
  final printable =
      page.layers.isEmpty ? null : page.printableLayerIds;
  final namedDests = <String>{
    for (final names in destNames.values) ...names,
  };
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
      if (target != null && target.isNotEmpty) {
        final aabb = page.shapePageAabb(shape.id);
        if (aabb != null) {
          var left = aabb.left * PdfPageFormat.inch;
          var bottom = aabb.bottom * PdfPageFormat.inch;
          var width = (aabb.right - aabb.left) * PdfPageFormat.inch;
          var height = (aabb.top - aabb.bottom) * PdfPageFormat.inch;
          // 1D / flat AABBs: expand to a clickable stroke thickness.
          final weightPt = (shape.line.weightInches > 0
                  ? shape.line.weightInches
                  : 0.04) *
              PdfPageFormat.inch;
          final minT = weightPt > _kMinPdfLinkThicknessPt
              ? weightPt
              : _kMinPdfLinkThicknessPt;
          if (width < minT) {
            final pad = (minT - width) * 0.5;
            left -= pad;
            width = minT;
          }
          if (height < minT) {
            final pad = (minT - height) * 0.5;
            bottom -= pad;
            height = minT;
          }
          var clippedOut = false;
          if (clipWidthInches != null && clipHeightInches != null) {
            final maxW = clipWidthInches * PdfPageFormat.inch;
            final maxH = clipHeightInches * PdfPageFormat.inch;
            if (left + width <= 0 ||
                bottom + height <= 0 ||
                left >= maxW ||
                bottom >= maxH) {
              clippedOut = true;
            } else {
              final r = left + width;
              final t = bottom + height;
              left = left.clamp(0.0, maxW);
              bottom = bottom.clamp(0.0, maxH);
              width = r.clamp(0.0, maxW) - left;
              height = t.clamp(0.0, maxH) - bottom;
            }
          }
          if (!clippedOut && width > 0.5 && height > 0.5) {
            final child = pw.SizedBox(width: width, height: height);
            final pw.Widget? widget;
            if (_isExternalPdfUrl(target)) {
              widget = pw.UrlLink(destination: target, child: child);
            } else {
              final dest = _resolveInternalPdfDest(target, namedDests);
              widget = dest == null
                  ? null
                  : pw.Link(destination: dest, child: child);
            }
            if (widget != null) {
              out.add(
                pw.Positioned(
                  left: left,
                  bottom: bottom,
                  child: widget,
                ),
              );
            }
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

/// Map Visio `#Page-2` / `Page-2` onto a registered named destination.
String? _resolveInternalPdfDest(String target, Set<String> namedDests) {
  if (_isExternalPdfUrl(target)) return null;
  final t = target.trim();
  if (t.isEmpty) return null;
  if (namedDests.contains(t)) return t;
  if (t.startsWith('#') && namedDests.contains(t.substring(1))) {
    return t.substring(1);
  }
  if (!t.startsWith('#') && namedDests.contains('#$t')) return t;
  return null;
}
