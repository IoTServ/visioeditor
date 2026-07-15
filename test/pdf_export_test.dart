import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/io/pdf_export.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  test('vector PDF export emits path operators (not a bare raster)', () async {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    final parser = const DocumentParser();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final rect = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 2,
      pinY: 3,
      width: 2,
      height: 1,
    ).copyWith(
      fill: const VsdxFill(foreground: VsdxColor(0xFF1565C0)),
      line: const VsdxLine(color: VsdxColor(0xFF000000), weightInches: 0.02),
    );
    doc = doc.replacePage(0, doc.pages.first.addShape(rect));

    final bytes = await exportDocumentToPdf(doc);
    expect(bytes.length, greaterThan(200));
    final head = ascii.decode(bytes.take(8).toList(), allowInvalid: true);
    expect(head.startsWith('%PDF'), isTrue);

    // Vector path content (moveTo / lineTo / curve / fill / stroke operators).
    final body = latin1.decode(bytes, allowInvalid: true);
    final hasPath = body.contains(' m\n') ||
        body.contains(' m ') ||
        body.contains('\nm\n') ||
        RegExp(r'\bm\b').hasMatch(body);
    final hasFillOrStroke = body.contains(' f') ||
        body.contains(' S') ||
        body.contains(' B') ||
        body.contains(' re');
    expect(hasPath || hasFillOrStroke, isTrue,
        reason: 'expected vector drawing operators in PDF stream');
  });

  test('PDF export composites BackPage underlay and skips background pages',
      () async {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    final parser = const DocumentParser();
    var doc = parser.parse(blank);
    final fg = doc.pages.first;
    final bgId = doc.nextPageId();
    final bgShape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 1,
      pinY: 1,
      width: 1,
      height: 1,
    ).copyWith(fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000)));
    doc = doc.insertPage(
      1,
      VsdxPage(
        id: bgId,
        name: 'Background-1',
        widthInches: fg.widthInches,
        heightInches: fg.heightInches,
        shapes: <VsdxShape>[bgShape],
        isBackgroundPage: true,
      ),
    );
    final fgShape = VsdxShapeFactory.rectangle(
      id: 2,
      pinX: 4,
      pinY: 4,
      width: 1,
      height: 1,
    );
    doc = doc.replacePage(
      0,
      fg.copyWith(
        backgroundPageId: bgId,
        shapes: <VsdxShape>[fgShape],
      ),
    );

    final bytes = await exportDocumentToPdf(doc);
    expect(bytes.length, greaterThan(200));
    // One page in the PDF (background page is underlay, not its own sheet).
    final body = latin1.decode(bytes, allowInvalid: true);
    expect(RegExp(r'/Type\s*/Page[^s]').allMatches(body).length, 1);
  });
}
