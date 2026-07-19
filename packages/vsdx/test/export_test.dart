import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

void main() {
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
    doc = doc.replacePage(
      0,
      page.addShape(left).addShape(center),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('text-anchor="start"'));
    expect(svg, contains('text-anchor="middle"'));
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
    // Closed square → 4 corners; fillet inserts multiple samples per corner.
    expect('L'.allMatches(d!).length, greaterThan(8));
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
    // All four corners filleted → more than an open-path's two interior bends.
    expect('L'.allMatches(d!).length, greaterThan(8));
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
    expect(svg.contains('fill="#f2f2f2"'), isFalse);
  });

  test('SVG vector metafile FlipY cancels GDI Y-flip like bitmaps', () {
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
    expect(flippedMeta!.group(1), '',
        reason: 'FlipY metafile must not apply a second Y flip');
    expect(flipped, contains('scale(1 -1)')); // parent XForm FlipY
    // FlipY must not translate(0, height) with positive sy (would land in [h,2h]).
    expect(flipped, contains('translate(0 0)'));
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

  test('SVG stroke-linecap follows LineCap', () {
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
                endArrow: 28,
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

  test('SVG font-family includes AsianFont after Latin face', () {
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
                text: '订单',
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
                endArrow: 8,
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
            line: const VsdxLine(endArrow: 11, weightInches: 0.03),
          ),
    );
    page = page.addShape(
      VsdxShapeFactory.line(id: nextId++, ax: 1, ay: 2, bx: 3, by: 2).copyWith(
            line: const VsdxLine(endArrow: 15, weightInches: 0.03),
          ),
    );
    doc = doc.replacePage(0, page);
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('M 0 5 L 5 1.5 L 10 5 L 5 8.5 Z'));
    expect(svg, contains('M 0 1 H 10 V 9 H 0 Z'));
  });

  test('SVG hatch tile matches canvas 1.28 inch period', () {
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
    expect(svg, contains('width="1.28" height="1.28"'));
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

  test('SVG open-stealth arrow (id 8) is stroked not filled', () {
    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.line(id: id, ax: 1, ay: 1, bx: 3, by: 1).copyWith(
              line: const VsdxLine(endArrow: 8, weightInches: 0.04),
            ),
      ),
    );
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('marker-end='));
    expect(
      svg,
      contains('fill="none" stroke="#000000"'),
      reason: 'arrow 8 is open stealth on canvas; SVG must not fill it',
    );
  });

  test('SVG arrows 21/22/34 match canvas ER / small-circle styles', () {
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
      contains(
        'd="M 4 5 m -1.8,0 a 1.8,1.8 0 1,0 3.6,0 a 1.8,1.8 0 1,0 -3.6,0 '
        'M 7 1 V 9" fill="none"',
      ),
      reason: 'arrow 21 is open circle + hash, not a filled triangle',
    );
    expect(
      svg,
      contains(
        'd="M 6 5 m -1.8,0 a 1.8,1.8 0 1,0 3.6,0 a 1.8,1.8 0 1,0 -3.6,0 '
        'M 4 5 L 0 1 M 4 5 L 0 5 M 4 5 L 0 9" fill="none"',
      ),
      reason: 'arrow 22 is optional-many crow foot',
    );
    expect(
      svg,
      contains(
        'd="M 7.5 5 m -2,0 a 2,2 0 1,0 4,0 a 2,2 0 1,0 -4,0" '
        'fill="none" stroke="#000000"',
      ),
      reason: 'arrow 34 is a small open circle on canvas',
    );
  });

  test('SVG arrows 27/28/29/33 match canvas filled/open styles', () {
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

    // 27 hatched triangle is open (stroke-only) on canvas.
    expect(
      svg,
      contains(
        'd="M 0 1 L 10 5 L 0 9 Z M 3 3 L 7 7" '
        'fill="none" stroke="#000000"',
      ),
      reason: 'arrow 27 must be open hatched triangle',
    );
    // 33 trident is open three-prong.
    expect(
      svg,
      contains(
        'd="M 10 5 L 2 1 M 10 5 L 0 5 M 10 5 L 2 9" '
        'fill="none" stroke="#000000"',
      ),
      reason: 'arrow 33 must be open trident, not a filled dart',
    );
    // 29 is a double triangle — two closed tips, not a single dart.
    expect(svg, contains('M 4 1 L 10 5 L 4 9 Z M 0 1 L 6 5 L 0 9 Z'));
    // 28 spear is a filled thin triangle (not an open polyline).
    expect(svg, contains('M 0 3.2 L 10 5 L 0 6.8 Z'));
    expect(
      svg.contains('M 0 5 L 8 5 M 8 2 L 12 5 L 8 8'),
      isFalse,
      reason: 'old open-spear path must not be used for arrow 28',
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
    // pad = 0.08*3 = 0.24; height 0.2 → filter height 0.68
    expect(svg, contains('height="0.68"'));
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

  test('SVG arrow 31 is filled chevron not stealth', () {
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
      contains('d="M 0 -4.091 L 10 5 L 0 14.091 L 2.727 5 Z" fill="#000000"'),
    );
    expect(svg.contains('L 2 5 Z'), isFalse,
        reason: 'must not reuse stealth template for chevron 31');
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

  test('SVG attaches EndArrow once across multi-geometry shapes', () {
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
    expect(RegExp(r'marker-end=').allMatches(svg).length, 1);
  });

  test('SVG ball arrow 10 is larger than circle-dot 13', () {
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
    expect(svg, contains('m -4,0 a 4,4 0 1,0 8,0'));
  });

  test('SVG FillPattern > 16 falls back to solid like canvas', () {
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
    expect(svg.contains('url(#pat-'), isFalse,
        reason: 'unsupported hatch ids must not invent a pattern tile');
    expect(svg, contains('fill="#1565c0"'));
  });

  test('SVG compound-line mask honours LineCap', () {
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
    expect(svg, contains('<mask '));
    expect(svg, contains('stroke-linecap="butt"'));
  });

  test('SVG compound line keeps EndArrow outside the mask', () {
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
    expect(svg, contains('<mask '));
    expect(svg, contains('marker-end='));
    // Masked rail must not carry markers; overlay path has stroke-opacity="0".
    expect(
      RegExp(r'mask="url\(#cmp-[^"]+\)"[^>]*marker-').hasMatch(svg),
      isFalse,
      reason: 'compound mask would clip arrowheads outside the stroke pipe',
    );
    expect(svg, contains('stroke-opacity="0"'));
    expect(svg, contains('marker-end='));
  });

  test('SVG arrows 25/26 are wide triangles with 0.85 reach', () {
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
      svg,
      contains('d="M 1.5 -0.5 L 10 5 L 1.5 10.5 Z" fill="#000000"'),
      reason: 'arrow 25 is filled wide triangle',
    );
    expect(
      svg,
      contains(
        'd="M 1.5 -0.5 L 10 5 L 1.5 10.5 Z" fill="none" stroke="#000000"',
      ),
      reason: 'arrow 26 is open wide triangle',
    );
    // markerWidth = size * reach = 0.2 * 0.85 = 0.17
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
    expect(svg, contains('font-size="0.2"'));
    expect(svg.contains('font-size="0.333'), isFalse);
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
    expect(svg, contains('x="0.39"'));
    // Subsequent lines: margin + IndLeft only = 0.14
    expect(svg, contains('x="0.14"'));
  });

  test('SVG 1D shadow honours LinePattern dash', () {
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
    expect(svg, contains('stroke-dasharray="0.10 0.05"'));
    // Shadow path also dashed (not only the main stroke).
    expect(
      RegExp(r'stroke-dasharray="0\.10 0\.05"').allMatches(svg).length,
      greaterThanOrEqualTo(2),
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
    // Default TextBkgnd margin 0.04": bullet at IndLeft+IndFirst = 0.14
    expect(svg, contains('x="0.14"'));
    // Body hanging band: IndLeft + TextPosAfterBullet → centre of remainder.
    // textBandX=0.59; xBody=0.59+(3-0.04-0.59)/2=1.775
    expect(svg, contains('x="1.775"'));
  });

  test('SVG relative SpLine line height does not multiply by extra 1.2', () {
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
    // Two paras at 0.2 * 1.5 = 0.3 each → second line centre offset uses 0.3
    // (not 0.2*1.2*1.5=0.36). Cluster height 0.6; centres at ±0.15 from mid.
    expect(svg, contains('y="-0.15"'));
    expect(svg, contains('y="0.15"'));
  });

  test('SVG arrows 5/6 are narrow triangles', () {
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
      contains('d="M 0 2.5 L 10 5 L 0 7.5 Z" fill="#000000"'),
      reason: 'arrow 5 is filled narrow triangle',
    );
    expect(
      svg,
      contains(
        'd="M 0 2.5 L 10 5 L 0 7.5 Z" fill="none" stroke="#000000"',
      ),
      reason: 'arrow 6 is open narrow triangle',
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
  });

  test('SVG FlipY bitmap uses centre flip (stays in shape box)', () {
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
        'transform="translate(1 0.5) scale(1 1) translate(-1 -0.5)"',
      ),
      reason: 'FlipY bitmap must centre-scale, not translate(0,h)+scale(1,1)',
    );
    expect(svg.contains('translate(0 1) scale(1 1)'), isFalse);
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
}
