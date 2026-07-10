import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:vsdx/vsdx.dart';

import 'image_export.dart';

/// Export every page of [doc] to a PDF, one page per drawing page. Pages are
/// rasterised with the on-screen painter at [pxPerInch] and placed at their
/// true inch size (72pt per inch).
Future<Uint8List> exportDocumentToPdf(
  VsdxDocument doc, {
  double pxPerInch = 150.0,
}) async {
  final pdf = pw.Document();
  for (final page in doc.pages) {
    final png = await renderPageToPng(
      page,
      theme: doc.theme,
      images: doc.images,
      pxPerInch: pxPerInch,
    );
    if (png == null) continue;
    final image = pw.MemoryImage(png);
    final wPt = (page.widthInches <= 0 ? 8.5 : page.widthInches) * 72.0;
    final hPt = (page.heightInches <= 0 ? 11.0 : page.heightInches) * 72.0;
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(wPt, hPt),
        build: (context) => pw.Image(image, fit: pw.BoxFit.contain),
      ),
    );
  }
  return pdf.save();
}
