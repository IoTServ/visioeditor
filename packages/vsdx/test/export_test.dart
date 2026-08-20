import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

Uint8List _wmfTextWithAlign(int align) {
  final bytes = Uint8List(48);
  final data = ByteData.sublistView(bytes);
  data.setUint16(0, 1, Endian.little); // MEMORYMETAFILE
  data.setUint16(2, 9, Endian.little); // header words
  data.setUint16(4, 0x0300, Endian.little);
  data.setUint32(6, bytes.length ~/ 2, Endian.little);
  data.setUint32(12, 8, Endian.little); // largest record words

  const setAlign = 18;
  data.setUint32(setAlign, 4, Endian.little);
  data.setUint16(setAlign + 4, 0x012e, Endian.little);
  data.setUint16(setAlign + 6, align, Endian.little);

  const text = 26;
  data.setUint32(text, 8, Endian.little);
  data.setUint16(text + 4, 0x0a32, Endian.little); // EXTTEXTOUT
  data.setInt16(text + 6, 20, Endian.little);
  data.setInt16(text + 8, 20, Endian.little);
  data.setUint16(text + 10, 1, Endian.little);
  data.setUint8(text + 14, 0x41); // A

  const eof = 42;
  data.setUint32(eof, 3, Endian.little);
  return bytes;
}

Uint8List _wmfTextWithBounds() {
  final bytes = Uint8List(48);
  final data = ByteData.sublistView(bytes);
  data.setUint16(0, 1, Endian.little);
  data.setUint16(2, 9, Endian.little);
  data.setUint16(4, 0x0300, Endian.little);
  data.setUint32(6, bytes.length ~/ 2, Endian.little);
  data.setUint32(12, 12, Endian.little);

  const record = 18;
  data.setUint32(record, 12, Endian.little);
  data.setUint16(record + 4, 0x0a32, Endian.little); // EXTTEXTOUT
  const text = record + 6;
  data.setInt16(text, 5, Endian.little);
  data.setInt16(text + 2, 4, Endian.little);
  data.setUint16(text + 4, 1, Endian.little);
  data.setUint16(text + 6, 0x0006, Endian.little); // OPAQUE | CLIPPED
  data.setInt16(text + 8, 2, Endian.little);
  data.setInt16(text + 10, 3, Endian.little);
  data.setInt16(text + 12, 11, Endian.little);
  data.setInt16(text + 14, 13, Endian.little);
  data.setUint8(text + 16, 0x41);
  data.setUint32(42, 3, Endian.little); // EOF
  return bytes;
}

Uint8List _wmfDashedLine() {
  final bytes = Uint8List(68);
  final data = ByteData.sublistView(bytes);
  data.setUint16(0, 1, Endian.little);
  data.setUint16(2, 9, Endian.little);
  data.setUint16(4, 0x0300, Endian.little);
  data.setUint32(6, bytes.length ~/ 2, Endian.little);
  data.setUint16(10, 1, Endian.little);
  data.setUint32(12, 8, Endian.little);

  const pen = 18;
  data.setUint32(pen, 8, Endian.little);
  data.setUint16(pen + 4, 0x02fa, Endian.little); // CREATEPENINDIRECT
  data.setUint16(pen + 6, 3, Endian.little); // PS_DASHDOT
  data.setInt16(pen + 8, 2, Endian.little);

  const select = 34;
  data.setUint32(select, 4, Endian.little);
  data.setUint16(select + 4, 0x012d, Endian.little);

  const move = 42;
  data.setUint32(move, 5, Endian.little);
  data.setUint16(move + 4, 0x0214, Endian.little);
  data.setInt16(move + 6, 10, Endian.little);
  data.setInt16(move + 8, 2, Endian.little);

  const line = 52;
  data.setUint32(line, 5, Endian.little);
  data.setUint16(line + 4, 0x0213, Endian.little);
  data.setInt16(line + 6, 10, Endian.little);
  data.setInt16(line + 8, 30, Endian.little);
  data.setUint32(62, 3, Endian.little); // EOF
  return bytes;
}

Uint8List _wmfRoundedRect() {
  final bytes = Uint8List(42);
  final data = ByteData.sublistView(bytes);
  data.setUint16(0, 1, Endian.little);
  data.setUint16(2, 9, Endian.little);
  data.setUint16(4, 0x0300, Endian.little);
  data.setUint32(6, bytes.length ~/ 2, Endian.little);
  data.setUint32(12, 9, Endian.little);

  const roundRect = 18;
  data.setUint32(roundRect, 9, Endian.little);
  data.setUint16(roundRect + 4, 0x061c, Endian.little);
  data.setInt16(roundRect + 6, 8, Endian.little);
  data.setInt16(roundRect + 8, 12, Endian.little);
  data.setInt16(roundRect + 10, 50, Endian.little);
  data.setInt16(roundRect + 12, 80, Endian.little);
  data.setInt16(roundRect + 14, 10, Endian.little);
  data.setInt16(roundRect + 16, 20, Endian.little);
  data.setUint32(36, 3, Endian.little);
  return bytes;
}

Uint8List _emfStockGrayBrush() {
  final bytes = Uint8List(132);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, 1, Endian.little); // EMR_HEADER
  data.setUint32(4, 88, Endian.little);
  data.setInt32(16, 100, Endian.little);
  data.setInt32(20, 100, Endian.little);
  data.setUint32(40, 0x464D4520, Endian.little); // " EMF"

  const select = 88;
  data.setUint32(select, 37, Endian.little); // EMR_SELECTOBJECT
  data.setUint32(select + 4, 12, Endian.little);
  data.setUint32(select + 8, 0x80000002, Endian.little); // GRAY_BRUSH

  const rectangle = 100;
  data.setUint32(rectangle, 43, Endian.little); // EMR_RECTANGLE
  data.setUint32(rectangle + 4, 24, Endian.little);
  data.setInt32(rectangle + 8, 10, Endian.little);
  data.setInt32(rectangle + 12, 10, Endian.little);
  data.setInt32(rectangle + 16, 50, Endian.little);
  data.setInt32(rectangle + 20, 50, Endian.little);
  data.setUint32(124, 14, Endian.little); // EMR_EOF
  data.setUint32(128, 8, Endian.little);
  return bytes;
}

void main() {
  test('SVG composites group text after filled children like libvisio', () {
    final child = VsdxShapeFactory.rectangle(
      id: 2,
      pinX: 1,
      pinY: 0.5,
      width: 2,
      height: 1,
    ).copyWith(
      fill: const VsdxFill(
        pattern: 1,
        foreground: VsdxColor(0xFF0000FF),
      ),
    );
    final group = VsdxShape(
      id: 1,
      name: 'Group',
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 1,
      children: <VsdxShape>[child],
      richText: const VsdxRichText(
        runs: <VsdxTextRun>[
          VsdxTextRun(text: 'PARENT OVERLAY'),
        ],
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(
      VsdxPage(
        id: 1,
        name: 'Page',
        widthInches: 4,
        heightInches: 4,
        shapes: <VsdxShape>[group],
      ),
    );

    expect(svg, contains('fill="#0000ff"'));
    expect(svg, contains('PARENT OVERLAY'));
    expect(
      svg.indexOf('fill="#0000ff"'),
      lessThan(svg.indexOf('PARENT OVERLAY')),
    );
  });

  const parser = DocumentParser();

  test('serializes a document to SVG', () {
    final doc = parser.parse(_fixture('test9_rect_and_line.vsdx'));
    final svg = VsdxToSvgSerializer().serializeDocument(doc);
    expect(svg, contains('<svg'));
    expect(svg, contains('</svg>'));
    expect(svg.length, greaterThan(100));
  });

  test('multi-page SVG paint ids are page-scoped (no def collisions)', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final p0 = doc.pages.first;
    const fill = VsdxFill(
      foreground: VsdxColor(0xFF1565C0),
      gradient: VsdxGradient(
        stops: <VsdxGradientStop>[
          VsdxGradientStop(position: 0, color: VsdxColor(0xFF1565C0)),
          VsdxGradientStop(position: 1, color: VsdxColor(0xFF90CAF9)),
        ],
      ),
    );
    final a = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 1,
    ).copyWith(fill: fill);
    doc = doc.replacePage(0, p0.addShape(a));
    final p1Id = doc.nextPageId();
    final p1 = VsdxPage(
      id: p1Id,
      name: 'Page-2',
      widthInches: p0.widthInches,
      heightInches: p0.heightInches,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 1,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
        ).copyWith(fill: fill),
      ],
    );
    doc = doc.copyWith(pages: <VsdxPage>[...doc.pages, p1]);
    final svg = VsdxToSvgSerializer().serializeDocument(doc);
    expect(svg, contains('id="grad-p${p0.id}-1-0"'));
    expect(svg, contains('id="grad-p$p1Id-1-0"'));
    expect(
      RegExp(r'id="grad-1-0"').hasMatch(svg),
      isFalse,
      reason: 'unscoped grad ids must not appear in multi-page SVG',
    );
  });

  test('serializes a single page to SVG', () {
    final doc = parser.parse(_fixture('test1.vsdx'));
    final svg = VsdxToSvgSerializer().serializePage(
      doc.pages.first,
      theme: doc.theme,
      images: doc.images,
    );
    expect(svg, contains('<svg'));
  });

  test('SVG export wraps shapes with primary hyperlinks', () {
    final blank = const VsdxWriter().emptyDocument();
    var doc = parser.parse(blank);
    final page = doc.pages.first;
    final linked = VsdxShapeFactory.rectangle(
      id: page.nextFreeShapeId(),
      pinX: 2,
      pinY: 3,
      width: 2,
      height: 1,
    ).copyWith(
      hyperlinks: const <VsdxHyperlink>[
        VsdxHyperlink(
          id: 0,
          description: 'Docs',
          address: 'https://example.com/x',
          newWindow: true,
          isDefault: true,
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(
      page.addShape(linked),
      theme: doc.theme,
    );
    expect(svg, contains('href="https://example.com/x"'));
    expect(svg, contains('target="_blank"'));
    expect(svg, contains('title="Docs"'));
    expect(svg, contains('</a>'));
  });

  test('SVG text-anchor follows Paragraph HorzAlign', () {
    final blank = const VsdxWriter().emptyDocument();
    var doc = parser.parse(blank);
    final page = doc.pages.first;
    final left = VsdxShapeFactory.rectangle(
      id: page.nextFreeShapeId(),
      pinX: 2,
      pinY: 5,
      width: 2,
      height: 0.6,
    ).copyWith(
      richText: VsdxRichText(runs: [
        VsdxTextRun(
          text: 'Left',
          paraStyle: const VsdxParaStyle(horizontalAlign: VsdxHorzAlign.left),
        ),
      ]),
    );
    final center = VsdxShapeFactory.rectangle(
      id: page.nextFreeShapeId() + 1,
      pinX: 5,
      pinY: 5,
      width: 2,
      height: 0.6,
    ).copyWith(
      richText: VsdxRichText(runs: [
        VsdxTextRun(
          text: 'Center',
          paraStyle: const VsdxParaStyle(horizontalAlign: VsdxHorzAlign.center),
        ),
      ]),
    );
    const rtlLeft = VsdxParaStyle(
      horizontalAlign: VsdxHorzAlign.left,
      flags: 1,
    );
    final flagged = VsdxShapeFactory.rectangle(
      id: page.nextFreeShapeId() + 2,
      pinX: 2,
      pinY: 4,
      width: 2,
      height: 0.6,
    ).copyWith(
      richText: const VsdxRichText(runs: [
        VsdxTextRun(text: 'RTL left', paraStyle: rtlLeft),
      ]),
    );
    doc = doc.replacePage(
      0,
      page.addShape(left).addShape(center).addShape(flagged),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('text-anchor="start"'));
    expect(svg, contains('text-anchor="middle"'));
    expect(svg, contains('text-anchor="end"'));
    expect(rtlLeft.effectiveHorizontalAlign, VsdxHorzAlign.right);
    expect(
      const VsdxParaStyle(
        horizontalAlign: VsdxHorzAlign.right,
        flags: 1,
      ).effectiveHorizontalAlign,
      VsdxHorzAlign.left,
    );
  });

  test('SVG wraps long labels to TxtWidth and preserves spaces', () {
    final blank = const VsdxWriter().emptyDocument();
    var doc = parser.parse(blank);
    final page = doc.pages.first;
    final shape = VsdxShapeFactory.rectangle(
      id: page.nextFreeShapeId(),
      pinX: 2,
      pinY: 5,
      width: 1.2,
      height: 1.5,
    ).copyWith(
      richText: VsdxRichText(runs: [
        VsdxTextRun(
          text: 'word1 word2 word3 word4 word5',
          charStyle: const VsdxCharStyle(fontSizeInches: 0.18),
          paraStyle: const VsdxParaStyle(horizontalAlign: VsdxHorzAlign.left),
        ),
      ]),
    );
    final spaced = VsdxShapeFactory.rectangle(
      id: page.nextFreeShapeId() + 1,
      pinX: 5,
      pinY: 5,
      width: 2,
      height: 0.6,
    ).copyWith(
      richText: VsdxRichText(runs: [
        const VsdxTextRun(text: 'a    b'),
      ]),
    );
    doc = doc.replacePage(0, page.addShape(shape).addShape(spaced));
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('xml:space="preserve"'));
    expect(svg, contains('a    b'));
    // Narrow box + long label → more than one <text> for the wrapped shape.
    final textTags = RegExp(r'<text\b').allMatches(svg).length;
    expect(textTags, greaterThanOrEqualTo(3));
  });

  test('SVG uses glyph advances before wrapping Visio angle fields', () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 3,
      pinY: 6,
      width: 4.192,
      height: 0.984,
    ).copyWith(
      richText: const VsdxRichText(
        runs: <VsdxTextRun>[
          VsdxTextRun(
            text: 'TextField GeometryAngleRadians -0.5236 rad',
            charStyle: VsdxCharStyle(fontSizeInches: 0.194),
          ),
        ],
        textBlock: VsdxTextBlock(
          widthInches: 4.192,
          heightInches: 0.984,
          marginLeftInches: 0.098,
          marginRightInches: 0.098,
        ),
      ),
    );
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 8.27,
      heightInches: 11.69,
      shapes: <VsdxShape>[shape],
    );

    final svg = VsdxToSvgSerializer().serializePage(page);

    expect(RegExp(r'<text\b').allMatches(svg), hasLength(1));
    expect(svg, contains('GeometryAngleRadians -0.5236 rad'));
  });

  test('SVG FontScale wrap estimate matches emitted letter-spacing', () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 0.82,
      height: 1,
    ).copyWith(
      richText: const VsdxRichText(
        runs: <VsdxTextRun>[
          VsdxTextRun(
            text: 'MMMM',
            charStyle: VsdxCharStyle(
              fontSizeInches: 0.2,
              fontScale: 2,
            ),
          ),
        ],
        textBlock: VsdxTextBlock(
          widthInches: 0.82,
          marginLeftInches: 0,
          marginRightInches: 0,
          marginTopInches: 0,
          marginBottomInches: 0,
        ),
      ),
    );
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 8,
      heightInches: 11,
      shapes: <VsdxShape>[shape],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg, contains('letter-spacing="110"'));
    expect(RegExp(r'<text\b').allMatches(svg), hasLength(1));
  });

  test('SVG horizontal line gradient centres on path not shape height', () {
    final blank = const VsdxWriter().emptyDocument();
    var doc = parser.parse(blank);
    final page = doc.pages.first;
    // 1D line: local path is along X at y≈locPin; shape.height is the span.
    final line = VsdxShapeFactory.line(
      id: page.nextFreeShapeId(),
      ax: 1,
      ay: 2,
      bx: 5,
      by: 2,
    ).copyWith(
      line: const VsdxLine(
        weightInches: 0.04,
        gradient: VsdxGradient(
          stops: <VsdxGradientStop>[
            VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
            VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
          ],
        ),
      ),
    );
    doc = doc.replacePage(0, page.addShape(line));
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    // Degenerate height must not place gradient centre at shape.height/2.
    final y1 = RegExp(r'linearGradient[^>]*y1="([^"]+)"').firstMatch(svg);
    final y2 = RegExp(r'linearGradient[^>]*y2="([^"]+)"').firstMatch(svg);
    expect(y1, isNotNull);
    expect(y2, isNotNull);
    final midY =
        (double.parse(y1!.group(1)!) + double.parse(y2!.group(1)!)) / 2;
    // Path is near local mid-Y of the stroke; allow tiny inflate (±0.025).
    expect(midY.abs(), lessThan(0.05));
  });

  test('SVG line gradient stroke-opacity ignores LineColor alpha', () {
    final blank = const VsdxWriter().emptyDocument();
    var doc = parser.parse(blank);
    final page = doc.pages.first;
    final line = VsdxShapeFactory.line(
      id: page.nextFreeShapeId(),
      ax: 1,
      ay: 1,
      bx: 4,
      by: 1,
    ).copyWith(
      line: const VsdxLine(
        color: VsdxColor(0x80FF0000),
        transparency: 0.4,
        weightInches: 0.05,
        gradient: VsdxGradient(
          stops: <VsdxGradientStop>[
            VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
            VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
          ],
        ),
      ),
    );
    doc = doc.replacePage(0, page.addShape(line));
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg.contains('stroke-opacity="0.6"'), isTrue);
    expect(svg.contains('stroke-opacity="0.3"'), isFalse);
  });

  test('SVG gradient stroke arrows use tip stop colour (not context-stroke)', () {
    final blank = const VsdxWriter().emptyDocument();
    var doc = parser.parse(blank);
    final page = doc.pages.first;
    final line = VsdxShapeFactory.line(
      id: page.nextFreeShapeId(),
      ax: 1,
      ay: 1,
      bx: 4,
      by: 1,
    ).copyWith(
      line: const VsdxLine(
        weightInches: 0.03,
        beginArrow: 4,
        endArrow: 4,
        gradient: VsdxGradient(
          stops: <VsdxGradientStop>[
            VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
            VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
          ],
        ),
      ),
    );
    doc = doc.replacePage(0, page.addShape(line));
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, isNot(contains('context-stroke')));
    expect(svg, contains('#ff0000'));
    expect(svg, contains('#0000ff'));
  });

  test('SVG composites BackPage underlay and skips background pages', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final fg = doc.pages.first;
    final bgId = doc.nextPageId();
    final bgRect = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 1,
      pinY: 1,
      width: 2,
      height: 1,
    ).copyWith(fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000)));
    doc = doc.insertPage(
      1,
      VsdxPage(
        id: bgId,
        name: 'Background-1',
        widthInches: fg.widthInches,
        heightInches: fg.heightInches,
        shapes: <VsdxShape>[bgRect],
        isBackgroundPage: true,
      ),
    );
    final fgRect = VsdxShapeFactory.rectangle(
      id: 2,
      pinX: 4,
      pinY: 4,
      width: 1,
      height: 1,
    );
    doc = doc.replacePage(
      0,
      fg.copyWith(backgroundPageId: bgId, shapes: <VsdxShape>[fgRect]),
    );

    final svg = VsdxToSvgSerializer().serializeDocument(doc);
    expect(svg, contains('class="underlay"'));
    expect(svg, contains('#ff0000'));
    // Background page is not emitted as its own sheet.
    expect(svg, isNot(contains('page-2')));
  });

  test('shared BackPage underlay paint ids are foreground-scoped', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final p0 = doc.pages.first;
    const fill = VsdxFill(
      foreground: VsdxColor(0xFF1565C0),
      gradient: VsdxGradient(
        stops: <VsdxGradientStop>[
          VsdxGradientStop(position: 0, color: VsdxColor(0xFF1565C0)),
          VsdxGradientStop(position: 1, color: VsdxColor(0xFF90CAF9)),
        ],
      ),
    );
    final bgId = doc.nextPageId();
    final bgShape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 1,
      pinY: 1,
      width: 2,
      height: 1,
    ).copyWith(fill: fill);
    doc = doc.insertPage(
      1,
      VsdxPage(
        id: bgId,
        name: 'Background-1',
        widthInches: p0.widthInches,
        heightInches: p0.heightInches,
        shapes: <VsdxShape>[bgShape],
        isBackgroundPage: true,
      ),
    );
    final p1Id = doc.nextPageId();
    doc = doc
        .replacePage(
          0,
          p0.copyWith(backgroundPageId: bgId, shapes: const <VsdxShape>[]),
        )
        .insertPage(
          2,
          VsdxPage(
            id: p1Id,
            name: 'Page-2',
            widthInches: p0.widthInches,
            heightInches: p0.heightInches,
            backgroundPageId: bgId,
            shapes: const <VsdxShape>[],
          ),
        );
    final svg = VsdxToSvgSerializer().serializeDocument(doc);
    expect(svg, contains('id="grad-p${p0.id}-u$bgId-1-0"'));
    expect(svg, contains('id="grad-p$p1Id-u$bgId-1-0"'));
    expect(
      RegExp('id="grad-p$bgId-1-0"').hasMatch(svg),
      isFalse,
      reason: 'underlay must not use bare background page paint scope',
    );
  });

  test('SVG Rounding fillets PolylineTo outlines like the canvas', () {
    // Without PolylineTo support in SVG _polylineVertices, Rounding fell back
    // to a sharp path (only stroke-linejoin=round). Filleting densifies corners.
    final shape = VsdxShape(
      id: 1,
      name: 'Poly',
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 2,
      line: const VsdxLine(roundingInches: 0.25),
      geometries: const <VsdxGeometry>[
        VsdxGeometry(
          commands: <VsdxPathCommand>[
            MoveTo(0, 0),
            PolylineTo(
              x: 0,
              y: 0,
              vertices: <Offset2D>[
                Offset2D(2, 0),
                Offset2D(2, 2),
                Offset2D(0, 2),
              ],
            ),
          ],
        ),
      ],
    );
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 8.5,
      heightInches: 11,
      shapes: <VsdxShape>[shape],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    final d = RegExp(r'<path d="([^"]+)"').firstMatch(svg)?.group(1);
    expect(d, isNotNull);
    // Match libvisio: one exact quadratic Bézier per rounded corner.
    expect('Q'.allMatches(d!).length, 4);
  });

  test('SVG Rounding fillets filled rects that omit closing LineTo', () {
    final shape = VsdxShape(
      id: 1,
      name: 'OpenRect',
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 2,
      line: const VsdxLine(roundingInches: 0.25),
      geometries: const <VsdxGeometry>[
        VsdxGeometry(
          commands: <VsdxPathCommand>[
            MoveTo(0, 0),
            LineTo(2, 0),
            LineTo(2, 2),
            LineTo(0, 2),
            // No LineTo(0,0) — Visio rectangles often omit it.
          ],
        ),
      ],
    );
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 8.5,
      heightInches: 11,
      shapes: <VsdxShape>[shape],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    final d = RegExp(r'<path d="([^"]+)"').firstMatch(svg)?.group(1);
    expect(d, isNotNull);
    // Filled open outlines close before rounding, so all corners get a Q.
    expect('Q'.allMatches(d!).length, 4);
  });

  test('SVG geometry-less 1D uses elbow/obstacle route not a chord', () {
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 8.5,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 10,
          pinX: 2.5,
          pinY: 3.5,
          width: 1,
          height: 1,
        ),
        VsdxShapeFactory.line(
          id: 1,
          ax: 1,
          ay: 2,
          bx: 4,
          by: 5,
        ).copyWith(geometries: const <VsdxGeometry>[]),
      ],
    );
    final route = page.autoRoutedConnectorPolyline(page.findShapeById(1)!);
    expect(route.length, greaterThan(2), reason: 'expect elbow/avoidance');
    final svg = VsdxToSvgSerializer().serializePage(page);
    // Chord would be a single L; routed path has multiple L segments.
    expect(RegExp(r'<path d="M[^"]* L[^"]* L').hasMatch(svg), isTrue);
  });

  test('SVG embeds vector WMF as paths not only a placeholder', () {
    final wmf = File('test/fixtures/metafile/Visio5PlanWithDimensions.wmf')
        .readAsBytesSync();
    const part = '/visio/media/thumb.wmf';
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 4,
      heightInches: 3,
      shapes: <VsdxShape>[
        VsdxShapeFactory.picture(
          id: 1,
          pinX: 2,
          pinY: 1.5,
          width: 3,
          height: 2,
          imagePartName: part,
        ),
      ],
    );
    final doc = VsdxDocument(
      pages: <VsdxPage>[page],
      images: ImageRegistry.empty.withImage(
        VsdxImage(partName: part, bytes: wmf, mimeType: 'image/x-wmf'),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(
      page,
      images: doc.images,
    );
    expect(svg.contains('<path '), isTrue);
    expect(svg.contains('<pattern id="wmf-hatch-'), isTrue);
    expect(svg.contains('stroke="#008000"'), isTrue);
    expect(svg.contains('fill="#ffffff"'), isTrue);
    expect(svg.contains('font-weight="400"'), isTrue);
    expect(svg.contains('rotate(-90)'), isTrue);
    expect(
      svg.contains(
        '<tspan x="0" y="0">8</tspan><tspan x="9" y="0">0</tspan>',
      ),
      isTrue,
    );
    expect(svg.contains('fill="#f2f2f2"'), isFalse);
  });

  test('SVG preserves vector metafile dash-dot pen style', () {
    const part = '/visio/media/dashed.wmf';
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 2,
      heightInches: 2,
      shapes: <VsdxShape>[
        VsdxShapeFactory.picture(
          id: 1,
          pinX: 1,
          pinY: 1,
          width: 1,
          height: 1,
          imagePartName: part,
        ),
      ],
    );
    final images = ImageRegistry.empty.withImage(VsdxImage(
      partName: part,
      bytes: _wmfDashedLine(),
      mimeType: 'image/x-wmf',
    ));
    final svg = VsdxToSvgSerializer().serializePage(page, images: images);
    expect(svg, contains('stroke-dasharray="9 3 3 3"'));
  });

  test('SVG preserves vector metafile rounded rectangle radii', () {
    const part = '/visio/media/rounded.wmf';
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 2,
      heightInches: 2,
      shapes: <VsdxShape>[
        VsdxShapeFactory.picture(
          id: 1,
          pinX: 1,
          pinY: 1,
          width: 1,
          height: 1,
          imagePartName: part,
        ),
      ],
    );
    final images = ImageRegistry.empty.withImage(VsdxImage(
      partName: part,
      bytes: _wmfRoundedRect(),
      mimeType: 'image/x-wmf',
    ));
    final svg = VsdxToSvgSerializer().serializePage(page, images: images);
    expect(svg, contains('<rect x="20" y="10" width="60" height="40"'));
    expect(svg, contains('rx="6" ry="4"'));
  });

  test('SVG preserves EMF stock gray brush fill', () {
    const part = '/visio/media/gray.emf';
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 2,
      heightInches: 2,
      shapes: <VsdxShape>[
        VsdxShapeFactory.picture(
          id: 1,
          pinX: 1,
          pinY: 1,
          width: 1,
          height: 1,
          imagePartName: part,
        ),
      ],
    );
    final images = ImageRegistry.empty.withImage(VsdxImage(
      partName: part,
      bytes: _emfStockGrayBrush(),
      mimeType: 'image/x-emf',
    ));
    final svg = VsdxToSvgSerializer().serializePage(page, images: images);
    expect(svg, contains('fill="#808080"'));
  });

  test('SVG metafile text honours GDI vertical and UPDATECP alignment', () {
    String svgFor(int align) {
      const part = '/visio/media/aligned.wmf';
      final page = VsdxPage(
        id: 0,
        name: 'P',
        widthInches: 2,
        heightInches: 2,
        shapes: <VsdxShape>[
          VsdxShapeFactory.picture(
            id: 1,
            pinX: 1,
            pinY: 1,
            width: 1,
            height: 1,
            imagePartName: part,
          ),
        ],
      );
      final images = ImageRegistry.empty.withImage(VsdxImage(
        partName: part,
        bytes: _wmfTextWithAlign(align),
        mimeType: 'image/x-wmf',
      ));
      return VsdxToSvgSerializer().serializePage(page, images: images);
    }

    expect(svgFor(0x00), contains('y="10.2" text-anchor="start"'));
    expect(svgFor(0x08), contains('y="-1.8" text-anchor="start"'));
    expect(svgFor(0x18), contains('y="0" text-anchor="start"'));
    expect(svgFor(0x1b), contains('y="0" text-anchor="end"'));
  });

  test('SVG metafile text honours ExtTextOut opaque and clip rectangles', () {
    const part = '/visio/media/bounded.wmf';
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 2,
      heightInches: 2,
      shapes: <VsdxShape>[
        VsdxShapeFactory.picture(
          id: 1,
          pinX: 1,
          pinY: 1,
          width: 1,
          height: 1,
          imagePartName: part,
        ),
      ],
    );
    final images = ImageRegistry.empty.withImage(VsdxImage(
      partName: part,
      bytes: _wmfTextWithBounds(),
      mimeType: 'image/x-wmf',
    ));
    final svg = VsdxToSvgSerializer().serializePage(page, images: images);
    expect(
      svg,
      contains('<rect x="2" y="3" width="9" height="10" fill="#ffffff"/>'),
    );
    expect(svg, contains('clipPathUnits="userSpaceOnUse"'));
    expect(
      svg,
      contains('<rect x="2" y="3" width="9" height="10"/></clipPath>'),
    );
    expect(svg, contains('clip-path="url(#wmf-text-clip-'));
  });

  test('SVG vector metafile FlipY mirrors after GDI normalisation', () {
    final wmf = File('test/fixtures/metafile/Visio5PlanWithDimensions.wmf')
        .readAsBytesSync();
    const part = '/visio/media/thumb.wmf';
    VsdxPage pageFor({required bool flipY}) => VsdxPage(
          id: 0,
          name: 'P',
          widthInches: 4,
          heightInches: 3,
          shapes: <VsdxShape>[
            VsdxShapeFactory.picture(
              id: 1,
              pinX: 2,
              pinY: 1.5,
              width: 3,
              height: 2,
              imagePartName: part,
            ).copyWith(flipY: flipY),
          ],
        );
    final images = ImageRegistry.empty.withImage(
      VsdxImage(partName: part, bytes: wmf, mimeType: 'image/x-wmf'),
    );
    final upright = VsdxToSvgSerializer().serializePage(
      pageFor(flipY: false),
      images: images,
    );
    final flipped = VsdxToSvgSerializer().serializePage(
      pageFor(flipY: true),
      images: images,
    );
    // Metafile group uses width/height ÷ drawing size (not page 96 / FlipY 1).
    final metaScale = RegExp(r'scale\(0\.[0-9]+ (-?)0\.[0-9]+\)');
    final uprightMeta = metaScale.firstMatch(upright);
    final flippedMeta = metaScale.firstMatch(flipped);
    expect(uprightMeta, isNotNull);
    expect(uprightMeta!.group(1), '-',
        reason: 'default metafile must flip GDI Y-down into page Y-up');
    expect(flippedMeta, isNotNull);
    expect(flippedMeta!.group(1), '-',
        reason: 'GDI normalisation remains inside the parent FlipY XForm');
    expect(flipped, contains('scale(1 -1)')); // parent XForm FlipY
    expect(flipped, contains('translate(0 2)'));
    expect(upright, contains('translate(0 2)'));
  });

  test('SVG print filter omits non-printable layers', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final page = doc.pages.first;
    final layers = <VsdxLayer>[
      const VsdxLayer(id: 0, name: 'PrintMe', visible: true, print: true),
      const VsdxLayer(id: 1, name: 'NoPrint', visible: true, print: false),
    ];
    final a = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 1,
      pinY: 1,
      width: 1,
      height: 1,
    ).copyWith(
      layerMemberIds: const <int>[0],
      fill: const VsdxFill(foreground: VsdxColor(0xFF00FF00)),
    );
    final b = VsdxShapeFactory.rectangle(
      id: 2,
      pinX: 3,
      pinY: 1,
      width: 1,
      height: 1,
    ).copyWith(
      layerMemberIds: const <int>[1],
      fill: const VsdxFill(foreground: VsdxColor(0xFFFF00FF)),
    );
    doc = doc.replacePage(
      0,
      page.copyWith(layers: layers, shapes: <VsdxShape>[a, b]),
    );

    final svg = VsdxToSvgSerializer(layerFilter: SvgLayerFilter.print)
        .serializePage(doc.pages.first);
    expect(svg, contains('#00ff00'));
    expect(svg, isNot(contains('#ff00ff')));
  });

  test('SVG stroke cap and default join follow libvisio LineCap mapping', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.line(id: id, ax: 1, ay: 1, bx: 3, by: 1).copyWith(
              line: const VsdxLine(cap: LineCap.square, weightInches: 0.05),
            ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('stroke-linecap="square"'));
    expect(svg, contains('stroke-linejoin="miter"'));

    final roundPage = doc.pages.first.copyWith(
      shapes: <VsdxShape>[
        VsdxShapeFactory.line(id: id + 1, ax: 1, ay: 2, bx: 3, by: 2),
      ],
    );
    final roundSvg = VsdxToSvgSerializer().serializePage(roundPage);
    expect(roundSvg, contains('stroke-linecap="round"'));
    expect(roundSvg, contains('stroke-linejoin="round"'));
  });

  test('SVG open arrow markers use stroke-linecap round', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.line(id: id, ax: 1, ay: 1, bx: 3, by: 1).copyWith(
              line: const VsdxLine(
                endArrow: 3,
                weightInches: 0.03,
              ),
            ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('stroke-linejoin="round"'));
    expect(svg, contains('stroke-linecap="round"'));
  });

  test('SVG arrow markers use userSpaceOnUse absolute inches', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.line(id: id, ax: 1, ay: 1, bx: 3, by: 1).copyWith(
              line: const VsdxLine(
                endArrow: 4,
                endArrowSizeInches: 0.125,
                weightInches: 0.05,
              ),
            ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('markerUnits="userSpaceOnUse"'));
    expect(svg, contains('overflow="visible"'));
    expect(svg, contains('markerWidth="0.125"'));
    expect(svg.contains('markerWidth="6"'), isFalse,
        reason: 'legacy strokeWidth-scaled marker sizes must not return');
  });

  test('SVG spear arrow markerWidth scales by canvas reach', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.line(id: id, ax: 1, ay: 1, bx: 3, by: 1).copyWith(
              line: const VsdxLine(
                endArrow: 13,
                endArrowSizeInches: 0.125,
                weightInches: 0.01,
              ),
            ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    // canvas spear reach ≈ 1.4 → markerWidth = 0.125 * 1.4 = 0.175
    expect(svg, contains('markerWidth="0.175"'));
  });

  test('SVG applies AsianFont to CJK glyphs instead of fallback only', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
        ).copyWith(
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'Order订单',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  asianFont: 'Microsoft YaHei',
                  fontSizeInches: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(
      svg,
      contains("font-family=\"Arial, 'Microsoft YaHei', sans-serif\""),
    );
    expect(
      svg,
      contains(
        "font-family=\"'Microsoft YaHei', sans-serif\" font-size=\"200\"",
      ),
    );
    expect(svg, contains('>订单</tspan>'));
  });

  test('SVG applies ComplexScriptFont and ComplexScriptSize by script', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 3,
          height: 1,
        ).copyWith(
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'Latin订单سلام',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  asianFont: 'Microsoft YaHei',
                  complexScriptFont: 'Times New Roman',
                  fontSizeInches: 0.2,
                  complexScriptSizeInches: 0.35,
                  langId: 'ar-SA',
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(
      svg,
      contains(
        "font-family=\"Arial, 'Microsoft YaHei', 'Times New Roman', sans-serif\" "
        'font-size="200"',
      ),
    );
    expect(
      svg,
      contains(
        "font-family=\"'Microsoft YaHei', 'Times New Roman', sans-serif\" "
        'font-size="200"',
      ),
    );
    expect(
      svg,
      contains(
        "font-family=\"'Times New Roman', 'Microsoft YaHei', sans-serif\" "
        'font-size="350"',
      ),
    );
    expect(svg, contains('>سلام</tspan>'));
    expect(svg, contains('xml:lang="ar-SA"'));
    expect(svg, contains('direction="rtl" unicode-bidi="isolate"'));
  });

  test('SVG curved text keeps complex-script font and size', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 2,
      pinY: 2,
      width: 3,
      height: 1,
    ).copyWith(
      richText: const VsdxRichText(
        runs: <VsdxTextRun>[
          VsdxTextRun(
            text: '订单سلام',
            charStyle: VsdxCharStyle(
              fontFamily: 'Arial',
              asianFont: 'Microsoft YaHei',
              complexScriptFont: 'Times New Roman',
              fontSizeInches: 0.12,
              complexScriptSizeInches: 0.4,
            ),
          ),
        ],
      ),
    ).withCurvedText(true);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));

    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('<textPath'));
    expect(
      svg,
      contains(
        "font-family=\"'Microsoft YaHei', 'Times New Roman', sans-serif\" "
        'font-size="120"',
      ),
    );
    expect(
      svg,
      contains(
        "font-family=\"'Times New Roman', 'Microsoft YaHei', sans-serif\" "
        'font-size="400"',
      ),
    );
    expect(svg, contains('>سلام</tspan></textPath>'));
    expect(svg, contains('scale(0.001 0.001)'));
    expect(svg.contains('dominant-baseline'), isFalse);
  });

  test('SVG unbound text uses libvisio Arial and opaque black defaults', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
        ).copyWith(
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[VsdxTextRun(text: 'Unbound')],
          ),
        ),
      ),
    );

    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('font-family="Arial, sans-serif"'));
    expect(svg, contains('fill="#000000" fill-opacity="1"'));
  });

  test('SVG open-arrow stroke scales with thick LineWeight', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.line(id: id, ax: 1, ay: 1, bx: 3, by: 1).copyWith(
              line: const VsdxLine(
                endArrow: 3,
                weightInches: 0.1,
                endArrowSizeInches: 0.125,
              ),
            ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    // viewBox stroke = 10 * 0.1 / markerWidth; markerWidth = 0.125 * reach(1)
    // → 10*0.1/0.125 = 8 (must not be clamped to 4).
    expect(svg, contains('stroke-width="8"'));
  });

  test('SVG diamond/square arrow tips sit at the line end', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    var nextId = page.nextFreeShapeId();
    page = page.addShape(
      VsdxShapeFactory.line(id: nextId++, ax: 1, ay: 1, bx: 3, by: 1).copyWith(
            line: const VsdxLine(endArrow: 22, weightInches: 0.03),
          ),
    );
    page = page.addShape(
      VsdxShapeFactory.line(id: nextId++, ax: 1, ay: 2, bx: 3, by: 2).copyWith(
            line: const VsdxLine(endArrow: 11, weightInches: 0.03),
          ),
    );
    doc = doc.replacePage(0, page);
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('M 0 5 L 5 1.5 L 10 5 L 5 8.5 Z'));
    expect(svg, contains('M 0 1 H 10 V 9 H 0 Z'));
  });

  test('SVG diagonal hatch keeps libvisio 0.1 inch normal spacing', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
        ).copyWith(
          fill: const VsdxFill(
            pattern: 2,
            foreground: VsdxColor(0xFF000000),
            background: VsdxColor(0xFFFFFFFF),
          ),
        ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    // A 45-degree hatch needs a d*sqrt(2) square repeat for normal spacing d.
    expect(svg, contains('width="0.141" height="0.141"'));
  });

  test('SVG Justify uses textLength spacing on short lines', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 3,
          height: 0.8,
        ).copyWith(
          richText: VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'A B',
                charStyle: VsdxCharStyle.defaults.copyWith(
                  fontSizeInches: 0.14,
                ),
                paraStyle: const VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.justify,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('lengthAdjust="spacing"'));
    expect(svg, contains('textLength="'));
  });

  test('SVG Full alignment distributes text like libvisio', () {
    final page = VsdxPage(
      id: 0,
      name: 'Full alignment',
      widthInches: 4,
      heightInches: 3,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 1,
          pinX: 2,
          pinY: 1.5,
          width: 3,
          height: 0.8,
        ).copyWith(
          richText: const VsdxRichText(runs: <VsdxTextRun>[
            VsdxTextRun(
              text: 'A B',
              paraStyle: VsdxParaStyle(
                horizontalAlign: VsdxHorzAlign.full,
              ),
            ),
          ]),
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg, contains('text-anchor="start"'));
    expect(svg, contains('lengthAdjust="spacing"'));
    expect(svg, contains('textLength="'));
  });

  test('SVG positions literal tabs at the active libvisio tab stop', () {
    final page = VsdxPage(
      id: 0,
      name: 'Tabs',
      widthInches: 4,
      heightInches: 3,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 1,
          pinX: 2,
          pinY: 1.5,
          width: 3,
          height: 0.8,
        ).copyWith(
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(text: 'A\tB', tabIndices: <int>[4]),
            ],
            tabSets: <VsdxTabSet>[
              VsdxTabSet(
                ix: 4,
                stops: <VsdxTabStop>[
                  VsdxTabStop(positionInches: 1),
                ],
              ),
            ],
          ),
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    final a = RegExp(r'<tspan x="([0-9.]+)"[^>]*>A</tspan>')
        .firstMatch(svg);
    final b = RegExp(r'<tspan x="([0-9.]+)"[^>]*>B</tspan>')
        .firstMatch(svg);
    expect(a, isNotNull);
    expect(b, isNotNull);
    expect(
      double.parse(b!.group(1)!) - double.parse(a!.group(1)!),
      closeTo(1000, 0.001),
    );
    expect(svg, isNot(contains('\t')),
        reason: 'tab control characters must become positioned tspans');
  });

  test('SVG wraps an overflowing tab field like LibreOffice', () {
    final page = VsdxPage(
      id: 0,
      name: 'Wrapped tab',
      widthInches: 3,
      heightInches: 2,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 1,
          pinX: 1.5,
          pinY: 1,
          width: 3,
          height: 1,
        ).copyWith(
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'Seco',
                charStyle: VsdxCharStyle(
                  fontFamily: 'DejaVu Sans',
                  fontSizeInches: 12 / 72,
                ),
                paraStyle: VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.center,
                ),
              ),
              VsdxTextRun(
                text: 'nd line and tab:\tvalue',
                tabIndices: <int>[0],
                charStyle: VsdxCharStyle(
                  fontFamily: 'DejaVu Sans',
                  fontSizeInches: 14 / 72,
                  style: VsdxFontStyle(bold: true),
                ),
                paraStyle: VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.center,
                ),
              ),
            ],
            textBlock: VsdxTextBlock(
              marginLeftInches: 0.05,
              marginRightInches: 0.05,
              marginTopInches: 0,
              marginBottomInches: 0,
              defaultTabStopInches: 0.4,
            ),
          ),
        ),
      ],
    );

    final svg = VsdxToSvgSerializer().serializePage(page);
    final prefix = svg.indexOf('Seco');
    final value = svg.indexOf('value');
    expect(prefix, greaterThanOrEqualTo(0));
    expect(value, greaterThan(prefix));
    expect(svg.indexOf('</text>', prefix), lessThan(value),
        reason: 'the overflowing tab field must start in a new SVG text row');
  });

  test('SVG alphabetic baseline matches LibreOffice text-frame descent', () {
    final page = VsdxPage(
      id: 0,
      name: 'Baseline',
      widthInches: 2.5,
      heightInches: 2,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 1,
          pinX: 1.25,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'Grouped child A',
                charStyle: VsdxCharStyle(fontSizeInches: 10 / 72),
              ),
            ],
          ),
        ),
      ],
    );

    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg, contains('y="58.611"'));
  });

  test('SVG open-concave arrow (id 17) is stroked not filled', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.line(id: id, ax: 1, ay: 1, bx: 3, by: 1).copyWith(
              line: const VsdxLine(endArrow: 17, weightInches: 0.04),
            ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('marker-end='));
    expect(
      svg,
      contains('fill="none" stroke="#000000"'),
      reason: 'arrow 17 is open concave in libvisio; SVG must not fill it',
    );
  });

  test('SVG arrows 7/19 share the exact libvisio open-chevron marker', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    var nextId = page.nextFreeShapeId();
    for (final (index, arrowId) in <int>[7, 19].indexed) {
      page = page.addShape(
        VsdxShapeFactory.line(
          id: nextId++,
          ax: 1,
          ay: index + 1.0,
          bx: 3,
          by: index + 1.0,
        ).copyWith(
          line: VsdxLine(endArrow: arrowId, weightInches: 0.01),
        ),
      );
    }
    doc = doc.replacePage(0, page);
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    const path = 'd="M 0 -4.091 L 10 5 L 0 14.091" fill="none"';
    expect(svg.split(path).length - 1, 2);
    expect(svg.split('markerWidth="0.069"').length - 1, 2);
  });

  test('SVG arrows 21/22/34 match square, diamond, and circle-plus-diamond', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    var nextId = page.nextFreeShapeId();
    for (final arrowId in <int>[21, 22, 34]) {
      page = page.addShape(
        VsdxShapeFactory.line(
          id: nextId++,
          ax: 1,
          ay: arrowId * 0.15,
          bx: 3,
          by: arrowId * 0.15,
        ).copyWith(
          line: VsdxLine(endArrow: arrowId, weightInches: 0.04),
        ),
      );
    }
    doc = doc.replacePage(0, page);
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(
      svg,
      contains('d="M 0 1 H 10 V 9 H 0 Z" fill="none"'),
      reason: 'arrow 21 is the centred unfilled square',
    );
    expect(
      svg,
      contains('d="M 0 5 L 5 1.5 L 10 5 L 5 8.5 Z" fill="none"'),
      reason: 'arrow 22 is the unfilled diamond',
    );
    expect(
      svg,
      contains(
        'd="M 6 5 m -3.5,0 a 3.5,3.5 0 1,0 7,0 a 3.5,3.5 0 1,0 -7,0 '
        'M 0 5 L 2 1.5 L 4 5 L 2 8.5 Z" fill="none"',
      ),
      reason: 'arrow 34 is an open circle with a diamond, not the id-20 stub',
    );
  });

  test('SVG arrow 23 keeps libvisio oblique stroke and centred stem', () {
    final writer = VsdxWriter();
    var doc = parser.parse(writer.emptyDocument());
    final page = doc.pages.first;
    doc = doc.replacePage(
      0,
      page.addShape(
        VsdxShapeFactory.line(
          id: page.nextFreeShapeId(),
          ax: 1,
          ay: 1,
          bx: 3,
          by: 1,
        ).copyWith(line: const VsdxLine(endArrow: 23)),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('d="M 0 9 L 10 1 M 5 0 V 10" fill="none"'));
  });

  test('SVG marker anchoring follows libvisio marker-center ids', () {
    String svgFor(int arrowId, {bool baked = false}) {
      final writer = VsdxWriter();
      var doc = parser.parse(writer.emptyDocument());
      final page = doc.pages.first;
      doc = doc.replacePage(
        0,
        page.addShape(
          VsdxShapeFactory.line(
            id: page.nextFreeShapeId(),
            ax: 1,
            ay: 1,
            bx: 3,
            by: 1,
          ).copyWith(line: VsdxLine(endArrow: arrowId)),
        ),
      );
      return VsdxToSvgSerializer(bakeArrowMarkers: baked)
          .serializePage(doc.pages.first);
    }

    expect(svgFor(10), contains('refX="5" refY="5"'));
    expect(svgFor(20), contains('refX="5" refY="5"'));
    expect(svgFor(42), contains('refX="10" refY="5"'));
    expect(svgFor(10, baked: true), contains('translate(-5 -5)'));
    expect(svgFor(42, baked: true), contains('translate(-10 -5)'));
  });

  test('SVG arrows 27/28/29/33 match ER crow-foot and circle-plus-bars', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    var nextId = page.nextFreeShapeId();
    for (final arrowId in <int>[27, 28, 29, 33]) {
      page = page.addShape(
        VsdxShapeFactory.line(
          id: nextId++,
          ax: 1,
          ay: arrowId * 0.2,
          bx: 3,
          by: arrowId * 0.2,
        ).copyWith(
          line: VsdxLine(endArrow: arrowId, weightInches: 0.04),
        ),
      );
    }
    doc = doc.replacePage(0, page);
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);

    expect(
      svg,
      contains(
        'd="M 0 5 L 8 1 M 0 5 L 8 5 M 0 5 L 8 9" '
        'fill="none" stroke="#000000"',
      ),
      reason: 'arrow 27 is the outward crow-foot many marker',
    );
    expect(
      svg,
      contains(
        'd="M 6 5 m -4,0 a 4,4 0 1,0 8,0 a 4,4 0 1,0 -8,0 '
        'M 0 1 V 9 M 1.5 1 V 9 M 3 1 V 9" fill="none"',
      ),
      reason: 'arrow 33 is an open circle with three bars, not the id-20 stub',
    );
    expect(
      svg,
      contains('M 0 5 L 7 1 M 0 5 L 7 5 M 0 5 L 7 9 M 9 1 V 9'),
      reason: 'arrow 28 adds the one-bar to the crow foot',
    );
    expect(
      svg,
      contains('M 4 5 m -1.8,0 a 1.8,1.8 0 1,0 3.6,0'),
      reason: 'arrow 29 combines an open circle with a crow foot',
    );
  });

  test('SVG radial LineGradient emits radialGradient', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.line(id: id, ax: 1, ay: 1, bx: 3, by: 1).copyWith(
              line: const VsdxLine(
                weightInches: 0.08,
                gradient: VsdxGradient(
                  type: VsdxGradientType.radial,
                  stops: <VsdxGradientStop>[
                    VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
                    VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
                  ],
                ),
              ),
            ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('<radialGradient id="lg-'));
    expect(svg.contains('<linearGradient id="lg-'), isFalse,
        reason: 'radial LineGradient must not fall back to linear');
    expect(svg, contains('gradientUnits="userSpaceOnUse"'));
  });

  test('SVG ellipse gradient bounds use absolute arcs (not relative a)', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.ellipse(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
        ).copyWith(
          fill: const VsdxFill(
            gradient: VsdxGradient(
              type: VsdxGradientType.linear,
              angleRad: 0,
              stops: <VsdxGradientStop>[
                VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
                VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
              ],
            ),
          ),
        ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('A 1 0.5 0 1 0 2 0.5'));
    expect(svg.contains(' a 1 '), isFalse);
    // Centre (1, 0.5), r=max(2,1)*0.6=1.2 → x1=-0.2 x2=2.2
    expect(svg, contains('x1="-0.2"'));
    expect(svg, contains('x2="2.2"'));
  });

  test('SVG SoftEdges filter uses userSpaceOnUse region not ±50% OBB', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 2,
          pinY: 1,
          width: 3,
          height: 0.2,
        ).copyWith(
          line: const VsdxLine(softEdgesInches: 0.08),
        ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('filterUnits="userSpaceOnUse"'));
    expect(svg.contains('x="-50%"'), isFalse);
    // pad = soft*3 + weight/2 = 0.08*3 + 0.01/2 = 0.245; height 0.2 → 0.69
    expect(svg, contains('height="0.69"'));
    expect(svg, contains('feGaussianBlur in="SourceAlpha"'));
    expect(svg, contains('feComposite'));
  });

  test('SVG SoftEdges filter pad includes line weight so thick strokes are not clipped',
      () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 2,
          pinY: 1,
          width: 3,
          height: 0.2,
        ).copyWith(
          line: const VsdxLine(softEdgesInches: 0.08, weightInches: 0.2),
        ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    // pad = 0.24 + 0.1 = 0.34; height 0.2 → 0.88
    expect(svg, contains('height="0.88"'));
  });

  test('SVG shadow filter region includes offset so large offsets are not clipped',
      () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    // |offset| 0.25 > blur*3 (0.12) — old pad alone would clip the shadow.
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 2,
      pinY: 2,
      width: 1,
      height: 1,
    ).copyWith(
      shadow: const VsdxShadow(
        enabled: true,
        offsetXInches: 0.25,
        offsetYInches: -0.25,
        blurInches: 0.04,
        color: VsdxColor(0xFF000000),
        transparency: 0.4,
      ),
    );
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('feGaussianBlur'));
    // pad = 0.04*3 + 0.25 = 0.37; 1×1 box → width/height 1.74
    expect(svg, contains('width="1.74"'));
    expect(svg, contains('height="1.74"'));
    expect(svg, contains('translate(0.25 -0.25)'));
  });

  test('SVG classic zero-blur shadow stays hard like libvisio', () {
    final page = VsdxPage(
      id: 0,
      name: 'Classic shadow',
      widthInches: 4,
      heightInches: 3,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 1,
          pinX: 2,
          pinY: 1.5,
          width: 1,
          height: 1,
        ).copyWith(
          shadow: const VsdxShadow(
            enabled: true,
            pattern: 1,
            color: VsdxColor(0xFF44546A),
            offsetXInches: 0.2,
            offsetYInches: -0.15,
            blurInches: 0,
          ),
        ),
      ],
    );

    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg, contains('fill="#44546a"'));
    expect(svg, contains('translate(0.2 -0.15)'));
    expect(svg, isNot(contains('id="shadow-p0-1-0"')));
    expect(svg, isNot(contains('<feGaussianBlur')));
  });

  test('SVG Foreign Blur/Brightness/Contrast emit tone filter', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final png = Uint8List.fromList(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    ));
    const part = 'media/image_tone.png';
    final images = ImageRegistry.empty.withImage(
      VsdxImage(partName: part, bytes: png, mimeType: 'image/png'),
    );
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 1,
      pinY: 1,
      width: 2,
      height: 2,
    ).copyWith(
      imagePartName: part,
      imageBlur: 0.25,
      imageBrightness: 0.6,
      imageContrast: 0.4,
    );
    doc = doc
        .copyWith(images: images)
        .replacePage(0, doc.pages.first.addShape(shape));
    final svg = VsdxToSvgSerializer().serializePage(
      doc.pages.first,
      images: doc.images,
    );
    expect(svg, contains('id="img-tone-$id"'));
    expect(svg, contains('feGaussianBlur'));
    expect(svg, contains('feColorMatrix'));
    expect(svg, contains('filterUnits="userSpaceOnUse"'),
        reason: 'tone blur must use padded userSpace region like SoftEdges');
  });

  test('SVG vector metafile Blur/Brightness emit tone filter', () {
    final wmf = File('test/fixtures/metafile/Visio5PlanWithDimensions.wmf')
        .readAsBytesSync();
    const part = '/visio/media/tone.wmf';
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 4,
      heightInches: 3,
      shapes: <VsdxShape>[
        VsdxShapeFactory.picture(
          id: 7,
          pinX: 2,
          pinY: 1.5,
          width: 3,
          height: 2,
          imagePartName: part,
        ).copyWith(
          imageBlur: 0.3,
          imageBrightness: 0.65,
          imageContrast: 0.35,
        ),
      ],
    );
    final images = ImageRegistry.empty.withImage(
      VsdxImage(partName: part, bytes: wmf, mimeType: 'image/x-wmf'),
    );
    final svg = VsdxToSvgSerializer().serializePage(page, images: images);
    expect(svg, contains('id="img-tone-7"'));
    expect(svg, contains('feGaussianBlur'));
    expect(svg, contains('feColorMatrix'));
  });

  test('SVG Foreign image reflection embeds the bitmap not a gray plate', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final png = Uint8List.fromList(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    ));
    const part = 'media/image_refl.png';
    final images = ImageRegistry.empty.withImage(
      VsdxImage(partName: part, bytes: png, mimeType: 'image/png'),
    );
    final shape = VsdxShapeFactory.picture(
      id: id,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 1.5,
      imagePartName: part,
    ).copyWith(
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
      reflection: const VsdxReflection(
        enabled: true,
        sizeInches: 0.5,
        transparency: 0.3,
      ),
    );
    doc = doc
        .copyWith(images: images)
        .replacePage(0, doc.pages.first.addShape(shape));
    final svg = VsdxToSvgSerializer().serializePage(
      doc.pages.first,
      images: doc.images,
    );
    expect(svg, contains('href="data:image/png;base64,'));
    // Reflection + body each embed the bitmap (not a gray #666 silhouette).
    expect(
      'href="data:image/png;base64,'.allMatches(svg).length,
      greaterThanOrEqualTo(2),
    );
    expect(svg.contains('fill="#666666"'), isFalse);
  });

  test('SVG Foreign ImgOffset/ImgWidth crop and Transparency', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final png = Uint8List.fromList(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    ));
    const part = 'media/image_crop.png';
    final images = ImageRegistry.empty.withImage(
      VsdxImage(partName: part, bytes: png, mimeType: 'image/png'),
    );
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 1,
      pinY: 1,
      width: 2,
      height: 2,
    ).copyWith(
      imagePartName: part,
      imgOffsetXInches: 0.25,
      imgOffsetYInches: 0.5,
      imgWidthInches: 1.0,
      imgHeightInches: 1.5,
      imageTransparency: 0.4,
    );
    doc = doc
        .copyWith(images: images)
        .replacePage(0, doc.pages.first.addShape(shape));
    final svg = VsdxToSvgSerializer().serializePage(
      doc.pages.first,
      images: doc.images,
    );
    expect(svg, contains('x="0.25"'));
    expect(svg, contains('y="0.5"'));
    expect(svg, contains('width="1"'));
    expect(svg, contains('height="1.5"'));
    expect(svg, contains('opacity="0.6"'));
    expect(svg, contains('img-box-$id'));
  });

  test('SVG SoftEdges also feathers Foreign bitmaps', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final png = Uint8List.fromList(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    ));
    const part = 'media/image1.png';
    final images = ImageRegistry.empty.withImage(
      VsdxImage(partName: part, bytes: png, mimeType: 'image/png'),
    );
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 1,
      pinY: 1,
      width: 2,
      height: 1.5,
    ).copyWith(
      imagePartName: part,
      line: const VsdxLine(softEdgesInches: 0.05),
    );
    doc = doc
        .copyWith(images: images)
        .replacePage(0, doc.pages.first.addShape(shape));
    final svg = VsdxToSvgSerializer().serializePage(
      doc.pages.first,
      images: doc.images,
    );
    expect(svg, contains('id="fx-img-$id"'));
    expect(svg, contains('filter="url(#fx-img-$id)"'));
    expect(svg, contains('<image'));
  });

  test('SVG pdfCompat flattens pattern, baseline, and glow for package:pdf', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    var nextId = page.nextFreeShapeId();
    page = page.addShape(
      VsdxShapeFactory.rectangle(
        id: nextId++,
        pinX: 2,
        pinY: 2,
        width: 2,
        height: 1,
      ).copyWith(
        fill: const VsdxFill(
          foreground: VsdxColor(0xFF1565C0),
          pattern: 4,
        ),
        glow: const VsdxGlow(
          enabled: true,
          sizeInches: 0.1,
          transparency: 0.2,
        ),
        richText: const VsdxRichText(
          runs: <VsdxTextRun>[VsdxTextRun(text: 'Hi')],
        ),
      ),
    );
    page = page.addShape(
      VsdxShapeFactory.line(id: nextId++, ax: 1, ay: 4, bx: 3, by: 4).copyWith(
            line: const VsdxLine(endArrow: 2, weightInches: 0.04),
          ),
    );
    doc = doc.replacePage(0, page);
    final svg =
        VsdxToSvgSerializer(pdfCompat: true).serializePage(doc.pages.first);
    expect(svg.contains('<pattern '), isFalse);
    expect(svg, contains('fill="#1565c0"'));
    expect(svg.contains('feGaussianBlur'), isFalse);
    expect(svg.contains('dominant-baseline'), isFalse);
    expect(svg.contains('<marker '), isFalse);
    expect(svg, contains('translate(2 0)')); // baked end arrow in local coords
  });

  test('SVG bakeArrowMarkers emits path geometry without <marker>', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.line(id: id, ax: 1, ay: 1, bx: 3, by: 1).copyWith(
              line: const VsdxLine(
                endArrow: 2,
                weightInches: 0.04,
                transparency: 0.5,
              ),
            ),
      ),
    );
    final svg = VsdxToSvgSerializer(bakeArrowMarkers: true)
        .serializePage(doc.pages.first);
    expect(svg.contains('<marker '), isFalse);
    expect(svg.contains('marker-end='), isFalse);
    expect(svg, contains('translate(2 0)'));
    expect(svg, contains('fill-opacity="0.5"'));
  });

  test('SVG marker arrows honour LineColorTrans opacity', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.line(id: id, ax: 1, ay: 1, bx: 3, by: 1).copyWith(
              line: const VsdxLine(
                endArrow: 2,
                weightInches: 0.04,
                transparency: 0.4,
                color: VsdxColor(0xFF1565C0),
              ),
            ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('fill="#1565c0" fill-opacity="0.6"'));
    expect(svg.contains('fill="context-stroke"'), isFalse);
  });

  test('SVG fill gradient uses userSpaceOnUse like canvas inches', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    // Wide flat rect: OBB would squash a vertical angle; userSpace keeps it.
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 3,
          pinY: 2,
          width: 4,
          height: 1,
        ).copyWith(
          fill: const VsdxFill(
            gradient: VsdxGradient(
              type: VsdxGradientType.linear,
              angleRad: 1.5707963267948966, // π/2
              stops: <VsdxGradientStop>[
                VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
                VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
              ],
            ),
          ),
        ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('gradientUnits="userSpaceOnUse"'));
    // max(w,h)*0.6 = 2.4; centre (2, 0.5) → y1=-1.9 y2=2.9
    expect(svg, contains('y1="-1.9"'));
    expect(svg, contains('y2="2.9"'));
    expect(svg.contains('objectBoundingBox'), isFalse);
  });

  test('SVG arrow 31 is an open circle with one bar', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.line(id: id, ax: 1, ay: 1, bx: 3, by: 1).copyWith(
              line: const VsdxLine(endArrow: 31, weightInches: 0.04),
            ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(
      svg,
      contains(
        'd="M 6 5 m -4,0 a 4,4 0 1,0 8,0 a 4,4 0 1,0 -8,0 M 0 1 V 9" '
        'fill="none" stroke="#000000"',
      ),
    );
    expect(svg, contains('d="M 0 0 L 1.895 0"'));
    expect(
      svg,
      contains('L 1.999 0 L 2 0" fill="none"'),
      reason: 'the marker carrier must retain the authored endpoint',
    );
  });

  test('SVG crow-foot extends outward without trimming the carrier', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.line(id: id, ax: 1, ay: 1, bx: 3, by: 1).copyWith(
              line: const VsdxLine(endArrow: 27, weightInches: 0.04),
            ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('d="M 0 0 L 2 0"'));
    expect(svg, contains('viewBox="0 0 10 10" refX="0" refY="5"'));
  });

  test('SVG arrows 35–37 put the bar before the filled circle', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.line(id: id, ax: 1, ay: 1, bx: 3, by: 1).copyWith(
              line: const VsdxLine(endArrow: 35, weightInches: 0.04),
            ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(
      svg,
      contains(
        'd="M 6 5 m -4,0 a 4,4 0 1,0 8,0 a 4,4 0 1,0 -8,0 '
        'M 0 0 V 10 H 2 V 0 Z" fill="#000000"',
      ),
    );
    expect(svg, contains('d="M 0 0 L 1.895 0"'));
  });

  test('all Visio arrow ids survive write, reopen and SVG export', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    var id = page.nextFreeShapeId();
    for (var arrowId = 1; arrowId <= 45; arrowId++) {
      page = page.addShape(
        VsdxShapeFactory.line(
          id: id++,
          ax: 1,
          ay: arrowId / 10,
          bx: 3,
          by: arrowId / 10,
          line: VsdxLine(beginArrow: arrowId, endArrow: arrowId),
        ),
      );
    }
    doc = doc.replacePage(0, page);
    final reopened = parser.parse(
      writer.write(originalBytes: blank, edited: doc),
    );
    final lines = reopened.pages.first.shapes.where((shape) => shape.is1D);
    expect(lines.map((shape) => shape.line.beginArrow), <int>[
      for (var arrowId = 1; arrowId <= 45; arrowId++)
        libvisioMarkerPathIsIncomplete(arrowId) ? 0 : arrowId,
    ]);
    expect(lines.map((shape) => shape.line.endArrow), <int>[
      for (var arrowId = 1; arrowId <= 45; arrowId++)
        libvisioMarkerPathIsIncomplete(arrowId) ? 0 : arrowId,
    ]);
    final svg = VsdxToSvgSerializer().serializePage(reopened.pages.first);
    final nativeCount = [
      for (var arrowId = 1; arrowId <= 45; arrowId++)
        if (!libvisioMarkerPathIsIncomplete(arrowId)) arrowId
    ].length;
    expect(RegExp(r'marker-start=').allMatches(svg), hasLength(nativeCount));
    expect(RegExp(r'marker-end=').allMatches(svg), hasLength(nativeCount));
    expect(
      svg,
      contains('d="M 0 -6 L 10 16 M 5 -6 V 16"'),
      reason: 'marker 9 keeps libvisio dimension-tick viewBox overflow',
    );
    expect(
      svg,
      matches(RegExp(
        r'<marker id="arrow-start-[^"]+"[^>]*refX="10"[^>]*>'
        r'<path d="M 10 5 L 2 1 M 10 5 L 2 5 M 10 5 L 2 9"',
      )),
      reason: 'start crow-foot uses the reversed libvisio anchor',
    );
    expect(
      svg,
      matches(RegExp(
        r'<marker id="arrow-end-[^"]+"[^>]*refX="0"[^>]*>'
        r'<path d="M 0 5 L 7 1 M 0 5 L 7 5 M 0 5 L 7 9 M 9 1 V 9"',
      )),
      reason: 'end crow-foot-plus-one uses the reversed libvisio anchor',
    );
  });

  test('SVG marker carrier path has single stroke-opacity=0', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.line(id: id, ax: 1, ay: 1, bx: 3, by: 1).copyWith(
              line: const VsdxLine(
                endArrow: 4,
                weightInches: 0.04,
                transparency: 0.25,
              ),
            ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    final carrier = RegExp(
      r'<path d="[^"]+" fill="none" [^>]*marker-end=',
    ).firstMatch(svg);
    expect(carrier, isNotNull);
    final attrs = carrier!.group(0)!;
    expect(attrs, contains('stroke-opacity="0"'));
    expect(
      RegExp(r'stroke-opacity=').allMatches(attrs).length,
      1,
      reason: 'duplicate stroke-opacity makes HTML keep the opaque first value',
    );
  });

  test('SVG attaches EndArrow to every open Geometry section', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final shape = VsdxShapeFactory.line(id: id, ax: 1, ay: 1, bx: 4, by: 1)
        .copyWith(
      line: const VsdxLine(endArrow: 4, weightInches: 0.03),
      geometries: <VsdxGeometry>[
        const VsdxGeometry(
          commands: <VsdxPathCommand>[MoveTo(0, 0), LineTo(3, 0)],
          noFill: true,
        ),
        const VsdxGeometry(
          commands: <VsdxPathCommand>[MoveTo(0, 0.2), LineTo(3, 0.2)],
          noFill: true,
        ),
      ],
    );
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(RegExp(r'marker-end=').allMatches(svg).length, 2);
    final carriers = RegExp(
      r'<path d="([^"]+)" fill="none" [^>]*marker-end=',
    ).allMatches(svg).map((match) => match.group(1)).toList();
    expect(carriers, hasLength(2));
    expect(carriers.first, startsWith('M 0 0 '));
    expect(carriers.first, endsWith('L 3 0'));
    expect(carriers.last, startsWith('M 0 0.2 '));
    expect(carriers.last, endsWith('L 3 0.2'));
  });

  test('SVG marker carrier retains open multi-M but skips closed paths', () {
    const shape = VsdxShape(
      id: 1,
      name: 'Multi subpath markers',
      pinX: 3,
      pinY: 1,
      width: 6,
      height: 2,
      line: VsdxLine(beginArrow: 4, endArrow: 13),
      geometries: <VsdxGeometry>[
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(0, 0),
            LineTo(1, 0),
            EllipseCmd(cx: 2, cy: 1, aX: 3, aY: 1, bX: 2, bY: 2),
            MoveTo(4, 0),
            LineTo(5, 0),
            MoveTo(0, 1),
            LineTo(1, 1),
            LineTo(1, 2),
            LineTo(0, 1),
          ],
        ),
      ],
    );
    const page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 6,
      heightInches: 2,
      shapes: <VsdxShape>[shape],
    );

    final svg = VsdxToSvgSerializer().serializePage(page);
    final carrier = RegExp(
      r'<path d="([^"]+)" fill="none" [^>]*stroke-opacity="0"[^>]*marker-start=',
    ).firstMatch(svg)!.group(1)!;

    expect(RegExp(r'\bM ').allMatches(carrier), hasLength(2));
    expect(carrier, isNot(contains('M 3 1')));
    expect(carrier, isNot(contains('M 0 1')));
  });

  test('SVG keeps rotated affine Ellipse continuous like libvisio arcs', () {
    const page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 6,
      heightInches: 4,
      shapes: <VsdxShape>[
        VsdxShape(
          id: 1,
          name: 'Affine ellipse',
          pinX: 3,
          pinY: 2,
          width: 6,
          height: 4,
          geometries: <VsdxGeometry>[
            VsdxGeometry(
              commands: <VsdxPathCommand>[
                EllipseCmd(cx: 3, cy: 2, aX: 4.2, aY: 2.7,
                    bX: 2.55, bY: 2.9),
              ],
            ),
          ],
        ),
      ],
    );

    final svg = VsdxToSvgSerializer().serializePage(page);
    final pathData = RegExp(r'<path d="([^"]+)" fill=')
        .firstMatch(svg)!
        .group(1)!;

    expect(RegExp(r'\bC ').allMatches(pathData), hasLength(4));
    expect(pathData, isNot(contains(' L ')));
    expect(pathData, endsWith('Z'));
  });

  test('SVG arrow 10 is a ball and arrow 13 a long filled triangle', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    var nextId = page.nextFreeShapeId();
    page = page.addShape(
      VsdxShapeFactory.line(id: nextId++, ax: 1, ay: 1, bx: 3, by: 1).copyWith(
            line: const VsdxLine(endArrow: 10, weightInches: 0.04),
          ),
    );
    page = page.addShape(
      VsdxShapeFactory.line(id: nextId++, ax: 1, ay: 2, bx: 3, by: 2).copyWith(
            line: const VsdxLine(endArrow: 13, weightInches: 0.04),
          ),
    );
    doc = doc.replacePage(0, page);
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('m -5,0 a 5,5 0 1,0 10,0'));
    expect(svg, contains('M 0 1.667 L 10 5 L 0 8.333 Z'));
  });

  test('SVG FillPattern 17 is hatch and unsupported 41 is solid', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
        ).copyWith(
          fill: const VsdxFill(
            foreground: VsdxColor(0xFF1565C0),
            pattern: 17,
          ),
        ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('url(#pat-'));
    expect(svg, contains('width="0.05" height="0.05"'));

    final unsupported = doc.replacePage(
      0,
      doc.pages.first.copyWith(
        shapes: [
          doc.pages.first.shapes.single.copyWith(
            fill: const VsdxFill(
              foreground: VsdxColor(0xFF1565C0),
              pattern: 41,
            ),
          ),
        ],
      ),
    );
    final fallback =
        VsdxToSvgSerializer().serializePage(unsupported.pages.first);
    expect(fallback.contains('url(#pat-'), isFalse,
        reason: 'unsupported hatch ids must not invent a pattern tile');
    expect(fallback, contains('fill="#1565c0"'));
  });

  test('SVG compound-line rails honour LineCap', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.line(id: id, ax: 1, ay: 1, bx: 3, by: 1).copyWith(
              line: const VsdxLine(
                cap: LineCap.extended,
                weightInches: 0.08,
                compoundType: 1,
              ),
            ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    // Parallel rails (no concentric mask) still honour LineCap=extended → butt.
    expect(svg, isNot(contains('<mask ')));
    expect(svg, contains('stroke-linecap="butt"'));
  });

  test('SVG compound line keeps EndArrow on a separate marker carrier', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.line(id: id, ax: 1, ay: 1, bx: 3, by: 1).copyWith(
              line: const VsdxLine(
                weightInches: 0.08,
                compoundType: 1,
                endArrow: 2,
              ),
            ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, isNot(contains('<mask ')));
    expect(svg, contains('marker-end='));
    // Rail strokes must not carry markers; overlay path has stroke-opacity="0".
    expect(
      RegExp(r'stroke-width="0\.025"[^>]*marker-').hasMatch(svg),
      isFalse,
      reason: 'compound rails must not host arrow markers',
    );
    expect(svg, contains('stroke-opacity="0"'));
    expect(svg, contains('marker-end='));
  });

  test('SVG arrows 25/26 distinguish two-bar and three-bar CF marks', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    var nextId = page.nextFreeShapeId();
    for (final arrowId in <int>[25, 26]) {
      page = page.addShape(
        VsdxShapeFactory.line(
          id: nextId++,
          ax: 1,
          ay: arrowId * 0.1,
          bx: 3,
          by: arrowId * 0.1,
        ).copyWith(
          line: VsdxLine(
            endArrow: arrowId,
            endArrowSizeInches: 0.2,
            weightInches: 0.04,
          ),
        ),
      );
    }
    doc = doc.replacePage(0, page);
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(
      RegExp(
        r'd="M 8 1 V 9 M 5\.5 1 V 9 M 3 1 V 9" fill="none"',
      ).allMatches(svg).length,
      1,
      reason: 'id 26 is three hash strokes; 25 stays two',
    );
    expect(
      RegExp(
        r'd="M 7 1 V 9 M 4\.5 1 V 9" fill="none"',
      ).allMatches(svg).length,
      1,
      reason: 'id 25 keeps two hash strokes',
    );
    // markerWidth = size * reach = 0.2 * 0.85 = 0.17.
    expect(svg, contains('markerWidth="0.17"'));
  });

  test('SVG bullet default size follows first run not SpLine', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 3,
          height: 1.5,
        ).copyWith(
          richText: VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'Item',
                charStyle: VsdxCharStyle.defaults.copyWith(
                  fontSizeInches: 0.2,
                ),
                paraStyle: const VsdxParaStyle(
                  bullet: 1,
                  // SpLine 2.0 would make lineH/1.2 ≈ 0.333 if wrongly used.
                  lineSpacing: 2.0,
                  indentLeftInches: 0.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('font-size="200"'));
    expect(svg.contains('font-size="333'), isFalse);
  });

  test('SVG negative BulletFontSize follows libvisio percentage semantics', () {
    final page = VsdxPage(
      id: 0,
      name: 'Bullet percentage',
      widthInches: 4,
      heightInches: 3,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 1,
          pinX: 2,
          pinY: 1.5,
          width: 3,
          height: 1,
        ).copyWith(
          richText: VsdxRichText(runs: <VsdxTextRun>[
            VsdxTextRun(
              text: 'Half-size bullet',
              charStyle: VsdxCharStyle.defaults.copyWith(
                fontSizeInches: 0.2,
              ),
              paraStyle: const VsdxParaStyle(
                bullet: 1,
                bulletFontSizeInches: -0.5,
              ),
            ),
          ]),
        ),
      ],
    );
    final style = page.shapes.single.richText.runs.single.paraStyle;
    expect(style.effectiveBulletFontSizeInches(0.2), closeTo(0.1, 1e-12));
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg, contains('font-size="100"'));
    expect(svg, contains('font-size="200"'));
  });

  test('SVG bullet inherits body paint and aligns its alphabetic baseline', () {
    final page = VsdxPage(
      id: 0,
      name: 'Bullet paint',
      widthInches: 4,
      heightInches: 3,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 1,
          pinX: 2,
          pinY: 1.5,
          width: 3,
          height: 1,
        ).copyWith(
          richText: VsdxRichText(runs: <VsdxTextRun>[
            VsdxTextRun(
              text: 'Item',
              charStyle: VsdxCharStyle.defaults.copyWith(
                fontFamily: 'Arial',
                fontSizeInches: 0.2,
                color: const VsdxColor(0xFF1565C0),
                transparency: 0.25,
              ),
              paraStyle: const VsdxParaStyle(
                bullet: 1,
                bulletFontSizeInches: -0.5,
              ),
            ),
          ]),
        ),
      ],
    );

    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg, contains('font-family="Arial" fill="#1565c0" '));
    expect(svg, contains('fill-opacity="0.75">•</tspan>'));
    final textNodes = RegExp(
      r'<text[^>]*y="([-0-9.]+)">(<tspan.*?</tspan>)</text>',
    ).allMatches(svg);
    final bullet = textNodes.firstWhere((m) => m.group(2)!.contains('>•<'));
    final body = textNodes.firstWhere((m) => m.group(2)!.contains('>Item<'));
    final bulletY = double.parse(bullet.group(1)!);
    final bodyY = double.parse(body.group(1)!);
    expect(bulletY - bodyY, closeTo(-35, 0.001));
  });

  test('SVG IndFirst applies only to the first wrapped line', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 1.4,
          height: 2,
        ).copyWith(
          richText: VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'alpha beta gamma delta',
                charStyle: VsdxCharStyle.defaults.copyWith(
                  fontSizeInches: 0.16,
                ),
                paraStyle: const VsdxParaStyle(
                  indentLeftInches: 0.1,
                  indentFirstInches: 0.25,
                  horizontalAlign: VsdxHorzAlign.left,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    // margin 0.04 + IndLeft 0.1 + IndFirst 0.25 = 0.39 on first line
    expect(svg, contains('x="390"'));
    // Subsequent lines: margin + IndLeft only = 0.14
    expect(svg, contains('x="140"'));
  });

  test('SVG 1D line does not manufacture a libvisio fill shadow', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.line(id: id, ax: 1, ay: 1, bx: 4, by: 1).copyWith(
              line: const VsdxLine(pattern: 2, weightInches: 0.04),
              shadow: const VsdxShadow(
                enabled: true,
                offsetXInches: 0.05,
                offsetYInches: 0.05,
              ),
            ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('stroke-dasharray="0.24 0.12"'));
    // The dash belongs only to the main stroke. LibreOffice does not turn the
    // fill shadow attached by libvisio into a second stroked line.
    expect(
      RegExp(r'stroke-dasharray="0\.24 0\.12"').allMatches(svg).length,
      1,
    );
  });

  test('SVG bullet hanging indent matches canvas TextPosAfterBullet', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 3,
          height: 1.5,
        ).copyWith(
          richText: VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'Item',
                charStyle: VsdxCharStyle.defaults.copyWith(
                  fontSizeInches: 0.15,
                ),
                paraStyle: const VsdxParaStyle(
                  bullet: 1,
                  bulletStr: '•',
                  indentLeftInches: 0.25,
                  indentFirstInches: -0.15,
                  textPosAfterBulletInches: 0.3,
                  horizontalAlign: VsdxHorzAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    // Bullet still drawn when centred (previously skipped for center).
    expect(svg, contains('•'));
    // Bullet origin is margin + IndLeft; IndFirst belongs to body line one.
    expect(svg, contains('x="290"'));
    // Resting body band starts at margin + IndLeft + label field = 0.59.
    // First line additionally applies -0.15 IndFirst, so centred x = 1.7.
    expect(svg, contains('x="1700"'));
  });

  test('SVG absolute SpLine uses inches not max(fontSize)', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 2,
        ).copyWith(
          richText: VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'A\nB',
                charStyle: VsdxCharStyle.defaults.copyWith(
                  fontSizeInches: 0.16,
                ),
                paraStyle: const VsdxParaStyle(
                  lineSpacingAbsoluteInches: 0.08,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    // Two lines with 0.08" advance → y delta 0.08 (not 0.16 from max(abs,fs)).
    final ys = RegExp(r'<text[^>]*\sy="([-0-9.]+)"')
        .allMatches(svg)
        .map((m) => double.parse(m.group(1)!))
        .toList();
    expect(ys.length, greaterThanOrEqualTo(2));
    expect((ys[1] - ys[0]).abs(), closeTo(80, 1e-6));
  });

  test('SVG pdfCompat reflection uses solid fill not missing pat url', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
        ).copyWith(
          fill: const VsdxFill(
            pattern: 4,
            foreground: VsdxColor(0xFF1565C0),
          ),
          reflection: const VsdxReflection(
            enabled: true,
            sizeInches: 0.4,
            distanceInches: 0.05,
          ),
        ),
      ),
    );
    final svg = VsdxToSvgSerializer(pdfCompat: true)
        .serializePage(doc.pages.first);
    expect(svg.contains('url(#pat-'), isFalse);
    expect(svg, contains('fill="#1565c0"'));
  });

  test('SVG image shape still paints Geometry stroke/fill', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    // Minimal 1×1 PNG.
    final png = Uint8List.fromList(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    ));
    final part = 'media/image1.png';
    final images = ImageRegistry.empty.withImage(
      VsdxImage(partName: part, bytes: png, mimeType: 'image/png'),
    );
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 2,
      pinY: 2,
      width: 1.5,
      height: 1,
    ).copyWith(
      imagePartName: part,
      fill: const VsdxFill(foreground: VsdxColor(0xFFFFFF00)),
      line: const VsdxLine(
        color: VsdxColor(0xFFFF0000),
        weightInches: 0.04,
      ),
    );
    doc = doc
        .copyWith(images: images)
        .replacePage(0, doc.pages.first.addShape(shape));
    final svg = VsdxToSvgSerializer().serializePage(
      doc.pages.first,
      images: doc.images,
    );
    expect(svg, contains('<image'));
    expect(
      svg,
      contains('fill="#729fcf"'),
      reason: 'LibreOffice standard GraphicObject style must remain visible '
          'behind transparent ForeignData pixels',
    );
    expect(svg, contains('fill="#ffff00"'));
    expect(svg, contains('stroke="#ff0000"'));
  });

  test('SVG relative SpLine uses LibreOffice typographic font cell', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 3,
          height: 2,
        ).copyWith(
          richText: VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'A\nB',
                charStyle: VsdxCharStyle.defaults.copyWith(
                  fontSizeInches: 0.2,
                ),
                paraStyle: const VsdxParaStyle(lineSpacing: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    // LibreOffice percentage spacing applies to a 1.12× typographic cell:
    // 0.2 * 1.5 * 1.12 = 0.336. The explicit alphabetic baseline adds 0.08
    // inch including Draw's 0.01in descent, then importer-safe SVG text units
    // scale values by 1000.
    expect(svg, contains('y="-88"'));
    expect(svg, contains('y="248"'));
  });

  test('SVG relative SpLine uses ComplexScriptSize for line metrics', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 3,
          height: 2,
        ).copyWith(
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'سلام\nسلام',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  complexScriptFont: 'Times New Roman',
                  fontSizeInches: 0.1,
                  complexScriptSizeInches: 0.4,
                ),
                paraStyle: VsdxParaStyle(lineSpacing: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    // Two 0.4" complex-script lines at 150% use the 1.12× font cell.
    final ys = RegExp(r'<text[^>]*\sy="([-0-9.]+)"')
        .allMatches(svg)
        .map((m) => double.parse(m.group(1)!))
        .toList();
    expect(ys.length, greaterThanOrEqualTo(2));
    expect((ys[1] - ys[0]).abs(), closeTo(672, 1e-6));
  });

  test('SVG arrows 5/6 are filled concave/convex markers', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    var nextId = page.nextFreeShapeId();
    for (final arrowId in <int>[5, 6]) {
      page = page.addShape(
        VsdxShapeFactory.line(
          id: nextId++,
          ax: 1,
          ay: arrowId * 0.1,
          bx: 3,
          by: arrowId * 0.1,
        ).copyWith(
          line: VsdxLine(endArrow: arrowId, weightInches: 0.04),
        ),
      );
    }
    doc = doc.replacePage(0, page);
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(
      svg,
      contains('d="M 0 1 L 10 5 L 0 9 L 3 5 Z" fill="#000000"'),
      reason: 'arrow 5 is the filled concave marker',
    );
    expect(
      svg,
      contains(
        'd="M 0 1 L 10 5 L 0 9 Q 7 5 0 1 Z" fill="#000000"',
      ),
      reason: 'arrow 6 is the filled convex marker',
    );
  });

  test('SVG EndArrow markers stay outside SoftEdges filter', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
        ).copyWith(
          line: const VsdxLine(
            softEdgesInches: 0.06,
            endArrow: 2,
            weightInches: 0.04,
          ),
          geometries: const <VsdxGeometry>[
            VsdxGeometry(
              commands: <VsdxPathCommand>[
                MoveTo(0, 0),
                LineTo(2, 0),
                LineTo(2, 1),
                LineTo(0, 1),
              ],
            ),
          ],
        ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('marker-end='));
    expect(svg, contains('filter="url(#fx-'));
    // Soft-filtered path must not carry markers (would blur arrowheads).
    expect(
      RegExp(r'filter="url\(#fx-[^"]+\)"[^>]*marker-').hasMatch(svg),
      isFalse,
    );
    expect(svg, contains('stroke-opacity="0"'));
  });

  test('SVG filled shape shadow is fill-only (no stroke in shadow source)', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
          line: const VsdxLine(
            color: VsdxColor(0xFF0000FF),
            weightInches: 0.05,
          ),
        ).copyWith(
          fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000)),
          shadow: const VsdxShadow(
            enabled: true,
            offsetXInches: 0.12,
            offsetYInches: 0.08,
            blurInches: 0.04,
          ),
        ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('filter="url(#shadow-'));
    expect(svg, contains('translate(0.12 0.08)'));
    expect(svg.contains('feDropShadow'), isFalse);
    // Shadow path is fill + stroke="none" (canvas filled drop shadow).
    expect(
      RegExp(
        r'filter="url\(#shadow-[^"]+\)"[^>]*stroke="none"|'
        r'stroke="none"[^>]*filter="url\(#shadow-',
      ).hasMatch(svg),
      isTrue,
    );
  });

  test('SVG page oblique shadow scales and shears about LocPin', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final page = doc.pages.first.addShape(
      VsdxShapeFactory.rectangle(
        id: id,
        pinX: 2,
        pinY: 2,
        width: 2,
        height: 1,
      ).copyWith(
        shadow: const VsdxShadow(
          enabled: true,
          offsetXInches: 0.1,
          offsetYInches: 0.05,
          blurInches: 0.02,
        ),
      ),
    );
    doc = doc.replacePage(
      0,
      page.copyWith(
        pageSheet: page.pageSheet.copyWith(
          shadowType: 1,
          shadowObliqueAngle: math.pi / 6,
          shadowScaleFactor: 0.85,
        ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('translate(0.1 0.05)'));
    expect(svg, contains('scale(0.85)'));
    // tan(π/6) ≈ 0.57735…
    expect(RegExp(r'matrix\(1 0 0\.577').hasMatch(svg), isTrue);
  });

  test('SVG reflection mirrors about path min-Y not always y=0', () {
    // Triangle sitting above y=0: minY > 0 → mirror axis is that minY.
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 4,
      heightInches: 3,
      shapes: <VsdxShape>[
        VsdxShape(
          id: 1,
          name: 'Sheet.1',
          pinX: 2,
          pinY: 1.5,
          width: 2,
          height: 2,
          fill: const VsdxFill(foreground: VsdxColor(0xFF1565C0)),
          line: const VsdxLine(pattern: 0),
          reflection: const VsdxReflection(
            enabled: true,
            sizeInches: 0.4,
            distanceInches: 0.05,
            blurInches: 0,
          ),
          geometries: const <VsdxGeometry>[
            VsdxGeometry(
              commands: <VsdxPathCommand>[
                MoveTo(0.2, 0.3),
                LineTo(1.8, 0.3),
                LineTo(1.0, 1.5),
                LineTo(0.2, 0.3),
              ],
            ),
          ],
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(
      svg,
      contains(
        'translate(0 -0.05) translate(0 0.3) scale(1 -1) translate(0 -0.3)',
      ),
      reason: 'reflection axis must be path minY (0.3), not shape y=0',
    );
    // Path height 1.2 × size 0.4 = 0.48; clip must add Distance 0.05 (canvas).
    expect(
      svg,
      contains('height="0.53"'),
      reason: 'reflection clip height = size band + Distance',
    );
  });

  test('SVG Foreign image is not clipped to Geometry path', () {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    );
    const part = '/visio/media/image1.png';
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 4,
      heightInches: 3,
      shapes: <VsdxShape>[
        VsdxShapeFactory.picture(
          id: 1,
          pinX: 2,
          pinY: 1.5,
          width: 2,
          height: 1.5,
          imagePartName: part,
        ).copyWith(
          shadow: const VsdxShadow(
            enabled: true,
            offsetXInches: 0.05,
            offsetYInches: 0.05,
          ),
          geometries: const <VsdxGeometry>[
            VsdxGeometry(
              noFill: true,
              noLine: true,
              commands: <VsdxPathCommand>[
                MoveTo(0, 0),
                LineTo(2, 0),
                LineTo(1, 1.5),
                LineTo(0, 0),
              ],
            ),
          ],
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(
      page,
      images: ImageRegistry.empty.withImage(
        VsdxImage(partName: part, bytes: png, mimeType: 'image/png'),
      ),
    );
    expect(svg, isNot(contains('img-clip-1')));
    expect(svg, contains('clipPath id="img-box-1"'));
    expect(svg, contains('clip-path="url(#img-box-1)"'));
    // NoFill+NoLine picture still gets a filled silhouette shadow.
    expect(svg, contains('fill-opacity='));
    expect(svg, contains('translate(0.05 0.05)'));
  });

  test('SVG cancels ancestor FlipX/FlipY for nested text glyphs', () {
    final child = VsdxShapeFactory.rectangle(
      id: 2,
      pinX: 1.5,
      pinY: 0.75,
      width: 3,
      height: 1.5,
    ).copyWith(
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
      richText: const VsdxRichText(
        runs: <VsdxTextRun>[
          VsdxTextRun(
            text: 'LEFT',
            paraStyle: VsdxParaStyle(
              horizontalAlign: VsdxHorzAlign.left,
            ),
          ),
        ],
      ),
    );
    final group = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 3,
      height: 1.5,
    ).copyWith(
      flipX: true,
      shapeKind: VsdxShapeKind.group,
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
      children: <VsdxShape>[child],
    );
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 4,
      heightInches: 3,
      shapes: <VsdxShape>[group],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(
      RegExp(r'scale\(-1 1\)').allMatches(svg),
      hasLength(2),
      reason: 'one mirror belongs to the group and one cancels it for text',
    );
    final flipYSvg = VsdxToSvgSerializer().serializePage(
      page.copyWith(
        shapes: <VsdxShape>[
          group.copyWith(flipX: false, flipY: true),
        ],
      ),
    );
    expect(
      RegExp(r'scale\(1 -1\)').allMatches(flipYSvg),
      hasLength(2),
      reason: 'one group mirror and one text compensation',
    );
    expect(flipYSvg, contains('scale(0.001 -0.001)'));
  });

  test('SVG FlipY bitmap normalises rows before parent mirror', () {
    // 1×1 PNG
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    );
    const part = '/visio/media/image1.png';
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 4,
      heightInches: 3,
      shapes: <VsdxShape>[
        VsdxShapeFactory.picture(
          id: 1,
          pinX: 2,
          pinY: 1.5,
          width: 2,
          height: 1,
          imagePartName: part,
        ).copyWith(flipY: true),
      ],
    );
    final images = ImageRegistry.empty.withImage(
      VsdxImage(partName: part, bytes: png, mimeType: 'image/png'),
    );
    final svg = VsdxToSvgSerializer().serializePage(page, images: images);
    expect(
      svg,
      contains(
        'transform="translate(1 0.5) scale(1 -1) translate(-1 -0.5)"',
      ),
      reason: 'bitmap Y-down normalisation must remain inside FlipY XForm',
    );
    expect('scale(1 -1)'.allMatches(svg).length, greaterThanOrEqualTo(2),
        reason: 'outer shape mirror and inner bitmap normalisation both apply');
    expect(svg, isNot(contains('scale(1 1)')));
  });

  test('SVG Initial Caps capitalises each word', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
        ).copyWith(
          richText: VsdxRichText(
            runs: [
              VsdxTextRun(
                text: 'hello world',
                charStyle: VsdxCharStyle.defaults
                    .copyWith(textCase: VsdxTextCase.initialCaps),
              ),
            ],
          ),
        ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('Hello World'));
  });

  test('SVG emits small-caps and double text-decoration', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
        ).copyWith(
          richText: VsdxRichText(
            runs: [
              VsdxTextRun(
                text: 'Aa',
                charStyle: VsdxCharStyle.defaults.copyWith(
                  style: const VsdxFontStyle(smallCaps: true),
                  doubleUnderline: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    // Synthetic small-caps (canvas parity): 'a' → smaller 'A', not CSS variant.
    expect(svg.contains('font-variant="small-caps"'), isFalse);
    expect(svg, contains('>A</tspan>'));
    expect(svg, contains('font-size="')); // full + 0.78× sizes present
    expect(svg, contains('text-decoration-style:double'));
  });

  test('SVG CurvedText uses textPath', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
        ).withCurvedText(true).copyWith(
              richText: const VsdxRichText(
                runs: [VsdxTextRun(text: 'Arc')],
              ),
            ),
      ),
    );
    final page = doc.pages.first;
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg, contains('textPath'));
    expect(svg, contains('curved-p${page.id}-$id'));
    expect(svg, contains('Arc'));
  });

  test('SVG CurvedText honours TextDirection vertical like canvas', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 1,
          height: 2,
        ).withCurvedText(true).copyWith(
              richText: VsdxRichText(
                textBlock: const VsdxTextBlock(textDirection: 1),
                runs: const [VsdxTextRun(text: 'Vert')],
              ),
            ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('textPath'));
    expect(svg, contains('rotate(-90)'));
    expect(svg, contains('Vert'));
  });

  test('SVG fill-opacity multiplies colour ARGB alpha', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 1,
          height: 1,
        ).copyWith(
          fill: const VsdxFill(
            foreground: VsdxColor(0x8000FF00), // 50% green
            foregroundTransparency: 0.0,
          ),
        ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('fill-opacity="0.502"'));
  });

  test('SVG omits children of collapsed containers', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final hostId = doc.pages.first.nextFreeShapeId();
    final childId = hostId + 1;
    final child = VsdxShapeFactory.rectangle(
      id: childId,
      pinX: 1,
      pinY: 1,
      width: 1,
      height: 0.5,
    ).copyWith(
      fill: const VsdxFill(foreground: VsdxColor(0xFF00ABCD)),
      richText: const VsdxRichText(runs: [VsdxTextRun(text: 'SecretChild')]),
    );
    final host = VsdxShapeFactory.container(
      id: hostId,
      pinX: 3,
      pinY: 3,
      width: 3,
      height: 2,
    ).copyWith(children: <VsdxShape>[child]).fold();
    doc = doc.replacePage(0, doc.pages.first.addShape(host));
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, isNot(contains('SecretChild')));
    expect(svg, isNot(contains('#00abcd')));
  });

  test('SVG ArcTo samples polyline so gradient bounds stay on the minor arc',
      () {
    // Shallow ArcTo: chord 2", bow 0.15". Old A-bounds used mid±r (~r≈3.4)
    // and pushed linear-gradient far outside the stroke.
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 6,
      heightInches: 4,
      shapes: <VsdxShape>[
        VsdxShape(
          id: 1,
          name: 'Sheet.1',
          pinX: 3,
          pinY: 2,
          width: 2,
          height: 1,
          line: const VsdxLine(pattern: 0),
          fill: const VsdxFill(
            gradient: VsdxGradient(
              type: VsdxGradientType.linear,
              angleRad: 1.57079632679, // vertical → y1/y2 from path bounds
              stops: <VsdxGradientStop>[
                VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
                VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
              ],
            ),
          ),
          geometries: const <VsdxGeometry>[
            VsdxGeometry(
              commands: <VsdxPathCommand>[
                MoveTo(0, 0.35),
                ArcTo(x: 2, y: 0.35, bow: 0.15),
                LineTo(2, 0.2),
                LineTo(0, 0.2),
                LineTo(0, 0.35),
              ],
            ),
          ],
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg.contains(RegExp(r'[\s"]A\s')), isFalse,
        reason: 'ArcTo should be sampled to L like canvas');
    expect(svg, contains('L '));
    // Path samples must stay near the chord+bow (not mid±r ≈ ±3).
    final d = RegExp(r'\bd="([^"]+)"').firstMatch(svg)?.group(1) ?? '';
    final ys = RegExp(r'(?:M|L)\s+[-\d.]+(?:e[-+]?\d+)?\s+([-\d.]+)')
        .allMatches(d)
        .map((m) => double.parse(m.group(1)!))
        .toList();
    expect(ys, isNotEmpty);
    expect(ys.reduce((a, b) => a < b ? a : b), greaterThan(0.15));
    expect(ys.reduce((a, b) => a > b ? a : b), lessThan(0.6));
  });

  test('SVG arc marker carrier preserves exact endpoint tangents', () {
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 4,
      heightInches: 3,
      shapes: <VsdxShape>[
        VsdxShape(
          id: 1,
          name: 'Arc connector',
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(beginArrow: 4, endArrow: 4),
          geometries: const <VsdxGeometry>[
            VsdxGeometry(
              noFill: true,
              commands: <VsdxPathCommand>[
                MoveTo(0, 0),
                ArcTo(x: 2, y: 0, bow: 0.6),
              ],
            ),
          ],
        ),
      ],
    );

    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(
      svg,
      contains(
        'd="M 0 0 L 0.000471 -0.000882 '
        'L 1.999529 -0.000882 L 2 0" fill="none"',
      ),
    );
  });

  test('SVG long bullet expands the physical label field', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 3,
          height: 1,
        ).copyWith(
          richText: VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'Item',
                charStyle: VsdxCharStyle.defaults.copyWith(
                  fontSizeInches: 0.2,
                ),
                paraStyle: const VsdxParaStyle(
                  bullet: 1,
                  bulletStr: 'WWW',
                  indentLeftInches: 0.1,
                  indentFirstInches: 0.0,
                  // Small gap → wide bullet overlaps body band start.
                  textPosAfterBulletInches: 0.08,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    // Label stays at margin + IndLeft; the body moves right when WWW is wider
    // than the authored 0.08" minimum field.
    expect(svg, contains('x="140"'));
    expect(svg, contains('WWW'));
    final xs = RegExp(r'x="([0-9.]+)"')
        .allMatches(svg)
        .map((m) => double.parse(m.group(1)!))
        .toList();
    expect(xs.any((x) => x > 400), isTrue,
        reason: 'long label must expand the body field instead of moving left');
  });

  test('SVG loose edge label centres glyphs on the route midpoint', () {
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 8,
      heightInches: 4,
      shapes: <VsdxShape>[
        VsdxShapeFactory.line(id: 1, ax: 1, ay: 2, bx: 5, by: 2).copyWith(
              richText: VsdxRichText(
                runs: <VsdxTextRun>[
                  VsdxTextRun(
                    text: 'Label',
                    charStyle: VsdxCharStyle.defaults.copyWith(
                      fontSizeInches: 0.16,
                    ),
                    paraStyle: const VsdxParaStyle(
                      horizontalAlign: VsdxHorzAlign.left,
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    // Midpoint of 1→5 at x=3 in page space → local pin on the 1D shape.
    expect(svg, contains('text-anchor="middle"'));
    expect(svg, contains('Label'));
    // Must not flow left-aligned into the long connector Width box.
    expect(svg.contains('text-anchor="start"'), isFalse);
  });

  test('SVG VertAlign middle preserves centred overflow like canvas', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 0.5,
        ).copyWith(
          richText: VsdxRichText(
            textBlock: const VsdxTextBlock(
              verticalAlign: VsdxVertAlign.middle,
              marginTopInches: 0.04,
              marginBottomInches: 0.04,
            ),
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'A\nB\nC\nD',
                charStyle: VsdxCharStyle.defaults.copyWith(
                  fontSizeInches: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('translate(0'));
    final m = RegExp(r'translate\(0 ([-\d.]+)\) scale\(0\.001 -0\.001\)')
        .firstMatch(svg);
    expect(m, isNotNull);
    final yc = double.parse(m!.group(1)!);
    expect(yc, closeTo(0.25, 1e-9),
        reason: 'overflowing text must remain centred on the content band');
  });

  test('SVG pdfCompat uses dy for super/sub not baseline-shift', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
        ).copyWith(
          richText: VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'x',
                charStyle: VsdxCharStyle.defaults.copyWith(
                  fontSizeInches: 0.2,
                  position: VsdxTextPosition.superscript,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final svg =
        VsdxToSvgSerializer(pdfCompat: true).serializePage(doc.pages.first);
    expect(svg.contains('baseline-shift'), isFalse);
    expect(svg, contains('dy="-70"')); // 0.2 * 0.35 * 1000
  });

  test('SVG CurvedText stays rectangular on glueable connectors', () {
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 8,
      heightInches: 4,
      shapes: <VsdxShape>[
        VsdxShapeFactory.line(id: 1, ax: 1, ay: 1, bx: 4, by: 3)
            .withCurvedText(true)
            .copyWith(
              richText: VsdxRichText(
                textBlock: const VsdxTextBlock(
                  pinXInches: 0.5,
                  pinYInches: 0.1,
                  widthInches: 1.2,
                  heightInches: 0.4,
                ),
                runs: const <VsdxTextRun>[VsdxTextRun(text: 'Arc')],
              ),
            ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg.contains('<textPath'), isFalse);
    expect(svg, contains('Arc'));
  });

  test('multi-page SVG exposes fragment ids for in-document hyperlinks', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final p0 = doc.pages.first;
    final p1Id = doc.nextPageId();
    doc = doc.insertPage(
      1,
      VsdxPage(
        id: p1Id,
        name: 'Page-2',
        widthInches: p0.widthInches,
        heightInches: p0.heightInches,
        shapes: const <VsdxShape>[],
      ),
    );
    final linked = VsdxShapeFactory.rectangle(
      id: p0.nextFreeShapeId(),
      pinX: 2,
      pinY: 2,
      width: 1.5,
      height: 0.8,
    ).copyWith(
      hyperlinks: const <VsdxHyperlink>[
        VsdxHyperlink(
          id: 0,
          subAddress: '#Page-2',
          isDefault: true,
        ),
      ],
    );
    doc = doc.replacePage(0, doc.pages.first.addShape(linked));
    final svg = VsdxToSvgSerializer().serializeDocument(doc);
    expect(svg, contains('href="#Page-2"'));
    expect(svg, contains('id="Page-2"'));
  });

  test('SVG Gap jumps do not put markers on broken subpaths', () {
    final h = VsdxShapeFactory.line(id: 1, ax: 1, ay: 3, bx: 5, by: 3).copyWith(
          line: const VsdxLine(endArrow: 2, weightInches: 0.04),
        );
    final v = VsdxShapeFactory.line(id: 2, ax: 3, ay: 5, bx: 3, by: 1);
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 8,
      heightInches: 11,
      shapes: <VsdxShape>[h, v],
      pageSheet: const VsdxPageSheet(lineJumpCode: 4, lineJumpStyle: 2),
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg, contains('marker-end='));
    // Stroke may Gap-break with mid-path M; marker carrier must stay continuous.
    final carrier = RegExp(
      r'<path d="([^"]+)" fill="none"[^>]*marker-end=',
    ).firstMatch(svg);
    expect(carrier, isNotNull);
    expect(
      RegExp(r'L [^"]* M ').hasMatch(carrier!.group(1)!),
      isFalse,
      reason: 'marker carrier must not include Gap M breaks',
    );
  });

  test('SVG Justify with bullet still stretches body via textLength', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 3,
          height: 0.8,
        ).copyWith(
          richText: VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'A B',
                charStyle: VsdxCharStyle.defaults.copyWith(
                  fontSizeInches: 0.14,
                ),
                paraStyle: const VsdxParaStyle(
                  bullet: 1,
                  bulletStr: '•',
                  horizontalAlign: VsdxHorzAlign.justify,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('lengthAdjust="spacing"'));
    expect(svg, contains('textLength="'));
    expect(svg, contains('•'));
  });
}
