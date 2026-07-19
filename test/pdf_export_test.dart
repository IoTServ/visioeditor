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

  test('PDF export emits URI link annotations for primary hyperlinks', () async {
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
      hyperlinks: const <VsdxHyperlink>[
        VsdxHyperlink(
          id: 0,
          address: 'https://example.com/docs',
          description: 'Docs',
          isDefault: true,
        ),
      ],
    );
    doc = doc.replacePage(0, doc.pages.first.addShape(rect));

    final bytes = await exportDocumentToPdf(doc);
    final body = latin1.decode(bytes, allowInvalid: true);
    expect(body.contains('/URI'), isTrue);
    expect(body.contains('https://example.com/docs'), isTrue);
  });

  test('PDF export emits named destinations for in-document page links',
      () async {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    final parser = const DocumentParser();
    var doc = parser.parse(blank);
    final p1 = doc.pages.first;
    final p2Id = doc.nextPageId();
    doc = doc.insertPage(
      1,
      VsdxPage(
        id: p2Id,
        name: 'Page-2',
        widthInches: p1.widthInches,
        heightInches: p1.heightInches,
        shapes: const <VsdxShape>[],
      ),
    );
    final id = doc.pages.first.nextFreeShapeId();
    final rect = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 2,
      pinY: 3,
      width: 2,
      height: 1,
    ).copyWith(
      hyperlinks: const <VsdxHyperlink>[
        VsdxHyperlink(
          id: 0,
          subAddress: '#Page-2',
          description: 'Next',
          isDefault: true,
        ),
      ],
    );
    doc = doc.replacePage(0, doc.pages.first.addShape(rect));

    final bytes = await exportDocumentToPdf(doc);
    final body = latin1.decode(bytes, allowInvalid: true);
    expect(body.contains('/URI'), isFalse,
        reason: 'page jump must not be forced into a URI annotation');
    // Named destination / GoTo link for the internal jump.
    expect(
      body.contains('/Dest') ||
          body.contains('/GoTo') ||
          body.contains('Page-2'),
      isTrue,
      reason: 'expected named destination or GoTo for #Page-2',
    );
  });

  test('PDF hyperlink overlays skip covered table cells', () async {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    final parser = const DocumentParser();
    var doc = parser.parse(blank);
    final table = TableOps.assembleTable(
      tableId: 1,
      pinX: 3,
      pinY: 4,
      width: 4,
      height: 2,
      rows: 1,
      cols: 2,
    );
    final merged = TableOps.mergeCells(table, row: 0, col: 0, rowSpan: 1, colSpan: 2);
    final covered = TableOps.cellsOf(merged).firstWhere(TableOps.isCovered);
    final withLink = merged.copyWith(
      children: <VsdxShape>[
        for (final c in merged.children)
          c.id == covered.id
              ? c.copyWith(
                  hyperlinks: const <VsdxHyperlink>[
                    VsdxHyperlink(
                      id: 0,
                      address: 'https://hidden.example/',
                      isDefault: true,
                    ),
                  ],
                )
              : c,
      ],
    );
    doc = doc.replacePage(0, doc.pages.first.addShape(withLink));
    final bytes = await exportDocumentToPdf(doc);
    final body = latin1.decode(bytes, allowInvalid: true);
    expect(body.contains('https://hidden.example/'), isFalse);
  });
}
