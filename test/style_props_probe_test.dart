import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const writer = VsdxWriter();
  const parser = DocumentParser();

  test('theme FillBkgnd round-trips QuickStyleFillColor', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final shape = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 1,
      fill: const VsdxFill(
        pattern: 2,
        foreground: VsdxColor(0xFF000000),
        themeBackgroundIndex: ThemeSlot.accent1,
      ),
    );
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final out = writer.write(originalBytes: blank, edited: doc);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.fill.themeBackgroundIndex, ThemeSlot.accent1);
    expect(after.fill.pattern, 2);
  });

  test('dual theme FillForegnd+FillBkgnd round-trips distinct slots', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank).copyWith(theme: VsdxTheme.office);
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
          fill: const VsdxFill(
            pattern: 2,
            themeForegroundIndex: ThemeSlot.accent1,
            themeBackgroundIndex: ThemeSlot.accent2,
          ),
        ),
      ),
    );
    final out = writer.write(originalBytes: blank, edited: doc);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.fill.themeForegroundIndex, ThemeSlot.accent1);
    expect(after.fill.themeBackgroundIndex, ThemeSlot.accent2,
        reason: 'FillBkgnd must keep AccentColor2 via named THEMEVAL');
    expect(after.fill.pattern, 2);
  });

  test('patch ThemeIndex / QuickStyle matrices on existing shape', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ),
      ),
    );
    // First save so the shape exists in the OPC package (patch path).
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    final edited = doc.pages.first.findShapeById(id)!.copyWith(
          themeIndex: 0,
          quickStyleFillMatrix: 100,
          quickStyleFontMatrix: 100,
        );
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(id, (_) => edited),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final pageXml = utf8.decode(
      ZipDecoder()
          .decodeBytes(out)
          .firstWhere((f) => f.name.contains('pages/page1.xml'))
          .content as List<int>,
    );
    expect(pageXml.contains('N="ThemeIndex"'), isTrue);
    expect(pageXml.contains('N="QuickStyleFillMatrix"'), isTrue);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.themeIndex, 0);
    expect(after.quickStyleFillMatrix, 100);
  });

  test('SVG export emits stroke-linejoin round when Rounding set', () {
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 8.5,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.line(
          id: 1,
          ax: 1,
          ay: 4,
          bx: 4,
          by: 4,
          line: const VsdxLine(
            endArrow: 4,
            roundingInches: 0.1,
            weightInches: 0.02,
            color: VsdxColor.black,
          ),
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg.contains('stroke-linejoin="round"'), isTrue);
    expect(svg.contains('marker-end="url(#arrow-end-p0-1-0)"'), isTrue);
    expect(svg.contains('id="arrow-end-p0-1-0"'), isTrue);
  });

  test('SVG fillets rectangle corners when Rounding set', () {
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 8.5,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 9,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
          line: const VsdxLine(roundingInches: 0.15),
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    // Sharp rect is 4 LineTos; fillet inserts sampled arc segments.
    // Skip marker paths in <defs>; the shape path carries stroke-linejoin.
    final pathMatch = RegExp(
      r'<path d="([^"]+)"[^>]*stroke-linejoin="round"',
    ).firstMatch(svg);
    expect(pathMatch, isNotNull);
    final d = pathMatch!.group(1)!;
    expect('L'.allMatches(d).length, greaterThan(4));
  });

  test('TextDirection=1 is stored on text block for paint', () {
    final e = EditorController()..newDocument();
    addTearDown(e.dispose);
    e.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 1,
        height: 2,
      ),
      3,
      3,
    );
    final id = e.singleSelectedId!;
    e.setShapeText(id, 'V');
    e.updateCurrentPage(
      (p) => p.updateShapeById(
        id,
        (s) => s.copyWith(
          richText: s.richText.copyWith(
            textBlock: s.richText.textBlock.copyWith(textDirection: 1),
          ),
        ),
      ),
    );
    expect(
      e.currentPage!.findShapeById(id)!.richText.textBlock.textDirection,
      1,
    );
  });

  test('SVG exports geometry-less 1D connector as Begin→End path', () {
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 8.5,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.line(
          id: 1,
          ax: 1,
          ay: 2,
          bx: 4,
          by: 5,
        ).copyWith(geometries: const <VsdxGeometry>[]),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg.contains('<path d='), isTrue);
    expect(svg.contains('stroke='), isTrue);
  });

  test('SVG emits linearGradient for FillGradient', () {
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 8.5,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 1,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
          fill: VsdxFill(
            pattern: 1,
            foreground: const VsdxColor(0xFFFF0000),
            gradient: VsdxGradient(
              type: VsdxGradientType.linear,
              angleRad: 0,
              stops: const <VsdxGradientStop>[
                VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
                VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
              ],
            ),
          ),
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg.contains('linearGradient'), isTrue);
    expect(svg.contains('fill="url(#grad-p0-1-0)"'), isTrue);
  });

  test('SVG emits pattern fill for FillPattern>1', () {
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 8.5,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 2,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
          fill: const VsdxFill(
            pattern: 4,
            foreground: VsdxColor(0xFF000000),
            background: VsdxColor(0xFFFFFFFF),
          ),
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg.contains('<pattern id="pat-p0-2-0"'), isTrue);
    expect(svg.contains('fill="url(#pat-p0-2-0)"'), isTrue);
  });

  test('SVG emits shadow filter and vertical TextDirection', () {
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 8.5,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 3,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
        ).copyWith(
          shadow: const VsdxShadow(
            enabled: true,
            offsetXInches: 0.1,
            offsetYInches: 0.1,
            blurInches: 0.05,
            transparency: 0.3,
          ),
          richText: VsdxRichText(
            runs: const <VsdxTextRun>[VsdxTextRun(text: 'V')],
            textBlock: const VsdxTextBlock(textDirection: 1),
          ),
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    // Fill-only blurred shadow path (canvas [_drawShadow]), not feDropShadow
    // on the sharp fill+stroke graphic.
    expect(svg.contains('filter="url(#shadow-'), isTrue);
    expect(svg.contains('translate(0.1 0.1)'), isTrue);
    expect(svg.contains('rotate(-90)'), isTrue);
    // Swapped layout frame (canvas parity): rotate about centre then
    // translate into the height×width band — not a bare rotate(-90).
    expect(
      svg.contains('translate(1 0.5) rotate(-90) translate(-0.5 -1)'),
      isTrue,
      reason: 'TextDirection=1 must swap layout box like canvas/curved text',
    );
  });

  test('SVG edge-label TextBkgnd uses tight plate not connector box', () {
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 8,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.line(id: 9, ax: 1, ay: 2, bx: 5, by: 2).copyWith(
          text: 'Go',
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'Go',
                charStyle: VsdxCharStyle(fontSizeInches: 0.14),
              ),
            ],
            textBlock: VsdxTextBlock(
              backgroundColor: VsdxColor(0xFFFFFF00),
            ),
          ),
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    // Tight plate (~chars × font), not the 4"-wide connector Width box.
    expect(svg.contains('width="4"'), isFalse);
    expect(svg.toLowerCase().contains('fill="#ffff00"'), isTrue);
    expect(RegExp(r'rx="0\.02"[^>]*width="0\.\d+"|width="0\.\d+"[^>]*rx="0\.02"')
        .hasMatch(svg), isTrue);
  });

  test('SVG loose edge label paints page/white plate without TextBkgnd', () {
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 8,
      heightInches: 11,
      backgroundColor: const VsdxColor(0xFFEEEEEE),
      shapes: <VsdxShape>[
        VsdxShapeFactory.line(id: 9, ax: 1, ay: 2, bx: 5, by: 2).copyWith(
          text: 'Go',
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'Go',
                charStyle: VsdxCharStyle(fontSizeInches: 0.14),
              ),
            ],
          ),
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg.contains('width="4"'), isFalse);
    expect(svg.toLowerCase().contains('fill="#eeeeee"'), isTrue);
    expect(
      RegExp(r'rx="0\.02"[^>]*width="0\.\d+"|width="0\.\d+"[^>]*rx="0\.02"')
          .hasMatch(svg),
      isTrue,
    );
  });

  test('SVG default glow colour matches canvas amber fallback', () {
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 8,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 1,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
        ).copyWith(
          glow: const VsdxGlow(enabled: true, sizeInches: 0.06),
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg.toLowerCase().contains('flood-color="#ffc107"'), isTrue);
    expect(svg.toLowerCase().contains('flood-color="#3399ff"'), isFalse);
  });

  test('SVG glow applies opacity once via flood-opacity', () {
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 8,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 1,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
        ).copyWith(
          glow: const VsdxGlow(
            enabled: true,
            sizeInches: 0.06,
            transparency: 0.5,
          ),
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    // canvas: alpha * 0.6 = 0.5 * 0.6 = 0.3 on the glow paint once.
    expect(svg, contains('flood-opacity="0.3"'));
    expect(
      svg,
      contains('stroke-opacity="1" filter="url(#glow-'),
      reason: 'stroke must stay opaque so flood-opacity is not squared',
    );
  });

  test('TextBkgndTrans round-trips and exports with opacity', () {
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
            runs: const <VsdxTextRun>[VsdxTextRun(text: 'Hi')],
            textBlock: const VsdxTextBlock(
              backgroundColor: VsdxColor(0xFFFF0000),
              backgroundTransparency: 0.5,
            ),
          ),
        ),
      ),
    );
    final out = writer.write(originalBytes: blank, edited: doc);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.richText.textBlock.backgroundTransparency, closeTo(0.5, 1e-6));
    final svg = VsdxToSvgSerializer().serializePage(
      parser.parse(out).pages.first,
    );
    expect(svg.contains('fill-opacity="0.5"'), isTrue);
  });

  test('SVG exports SoftEdgesSize blur filter', () {
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 8.5,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 4,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
          line: const VsdxLine(softEdgesInches: 0.08),
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg.contains('feGaussianBlur'), isTrue);
    expect(svg.contains('filter="url(#fx-p0-4-0)"'), isTrue);
  });

  test('SVG exports CompoundType as parallel offset rails', () {
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 8.5,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.line(
          id: 5,
          ax: 1,
          ay: 3,
          bx: 4,
          by: 3,
          line: const VsdxLine(
            compoundType: 1,
            weightInches: 0.06,
            color: VsdxColor.black,
          ),
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    // Dual rails (not a concentric mask) — two stroked paths with rail widths.
    expect(svg.contains('mask="url(#cmp-'), isFalse);
    // rail = (0.06 - 0.38*0.06)/2 = 0.0186 → _n rounds to 0.019
    expect(svg.contains('stroke-width="0.019"'), isTrue);
    expect(RegExp(r'stroke-width="0\.019"').allMatches(svg).length, 2);
    expect(svg.contains('stroke="#ffffff"'), isFalse);
  });

  test('SVG thick-thin CompoundType uses unequal rail widths', () {
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 8.5,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.line(
          id: 6,
          ax: 1,
          ay: 2,
          bx: 4,
          by: 2,
          line: const VsdxLine(
            compoundType: 2,
            weightInches: 0.10,
            color: VsdxColor.black,
          ),
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg.contains('stroke-width="0.055"'), isTrue); // thick 55%
    expect(svg.contains('stroke-width="0.025"'), isTrue); // thin 25%
  });

  test('SVG reflection stroke honours CompoundType rail widths', () {
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 8.5,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.line(
          id: 8,
          ax: 1,
          ay: 3,
          bx: 4,
          by: 3,
          line: const VsdxLine(
            compoundType: 2,
            weightInches: 0.10,
            color: VsdxColor.black,
          ),
        ).copyWith(
          reflection: const VsdxReflection(
            enabled: true,
            sizeInches: 0.4,
            transparency: 0.3,
          ),
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    // Body + reflection each emit thick/thin rails (not a full-width mirror).
    expect(RegExp(r'stroke-width="0\.055"').allMatches(svg).length,
        greaterThanOrEqualTo(2));
    expect(RegExp(r'stroke-width="0\.025"').allMatches(svg).length,
        greaterThanOrEqualTo(2));
    expect(
      RegExp(r'scale\(1 -1\)[\s\S]*?stroke-width="0\.1"').hasMatch(svg),
      isFalse,
      reason: 'reflection must not stroke full compound weight',
    );
  });

  test('SVG compound+shadow applies filter once on wrapper', () {
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 8.5,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 7,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
          line: const VsdxLine(
            compoundType: 1,
            weightInches: 0.06,
            color: VsdxColor.black,
          ),
        ).copyWith(
          shadow: const VsdxShadow(
            enabled: true,
            offsetXInches: 0.1,
            offsetYInches: 0.1,
          ),
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    // Parallel rails (no concentric mask) under a single SoftEdges/shadow wrapper.
    expect(svg.contains('mask="url(#cmp-'), isFalse);
    // Shadow is a single fill-only path (not feDropShadow on fill+stroke).
    expect(svg.contains('filter="url(#shadow-'), isTrue);
    expect(
      RegExp(r'filter="url\(#shadow-').allMatches(svg).length,
      1,
      reason: 'compound must not duplicate the shadow filter on fill and stroke',
    );
  });

  test('SVG reflection includes stroke matching canvas', () {
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 8.5,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 8,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
          line: const VsdxLine(
            color: VsdxColor(0xFFC00000),
            weightInches: 0.04,
          ),
        ).copyWith(
          reflection: const VsdxReflection(
            enabled: true,
            sizeInches: 0.4,
            transparency: 0.5,
          ),
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg.contains('scale(1 -1)'), isTrue);
    expect(
      RegExp(r'scale\(1 -1\)[^>]*>[\s\S]*?stroke="#c00000"', caseSensitive: false)
          .hasMatch(svg),
      isTrue,
    );
  });

  test('SVG reflection on horizontal 1D uses stroke-weight clip height', () {
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 8.5,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.line(id: 9, ax: 1, ay: 2, bx: 4, by: 2).copyWith(
          line: const VsdxLine(
            color: VsdxColor(0xFF1565C0),
            weightInches: 0.05,
          ),
          reflection: const VsdxReflection(
            enabled: true,
            sizeInches: 0.5,
            distanceInches: 0.02,
            blurInches: 0,
          ),
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg, contains('scale(1 -1)'));
    expect(svg, contains('refl-'));
    // Path height ≈ 0; fallback clip uses weight 0.05 × size 0.5 = 0.025
    expect(svg, contains('height="0.025"'));
  });

  test('SVG reflection reuses hatch pattern fill', () {
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 8.5,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 11,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
          fill: const VsdxFill(
            pattern: 2,
            foreground: VsdxColor(0xFF000000),
            background: VsdxColor(0xFFFFFF00),
          ),
        ).copyWith(
          reflection: const VsdxReflection(
            enabled: true,
            sizeInches: 0.4,
            transparency: 0.5,
          ),
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg.contains('id="pat-'), isTrue);
    expect(
      RegExp(r'scale\(1 -1\)[\s\S]*?fill="url\(#pat-').hasMatch(svg),
      isTrue,
      reason: 'mirrored fill must reuse hatch, not solid foreground',
    );
  });

  test('reflection disable then enable round-trips ReflectionSize', () {
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
          reflection: const VsdxReflection(
            enabled: true,
            sizeInches: 0.4,
            distanceInches: 0.12,
            blurInches: 0.07,
            transparency: 0.5,
          ),
        ),
      ),
    );
    var bytes = writer.write(originalBytes: blank, edited: doc);
    // Off → Size=0 in XML.
    doc = parser.parse(bytes);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(reflection: VsdxReflection.disabled),
      ),
    );
    bytes = writer.write(originalBytes: bytes, edited: doc);
    doc = parser.parse(bytes);
    expect(doc.pages.first.findShapeById(id)!.reflection.enabled, isFalse);

    // On again with defaults — must rewrite Size/Dist/Blur so reopen does not
    // resurrect the previous custom Dist/Blur over model defaults.
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(
          reflection: const VsdxReflection(enabled: true, transparency: 0.6),
        ),
      ),
    );
    bytes = writer.write(originalBytes: bytes, edited: doc);
    doc = parser.parse(bytes);
    final refl = doc.pages.first.findShapeById(id)!.reflection;
    expect(refl.enabled, isTrue);
    expect(refl.sizeInches, greaterThan(0));
    expect(refl.distanceInches, closeTo(0.0, 1e-6));
    expect(refl.blurInches, closeTo(0.02, 1e-6));
    expect(refl.transparency, closeTo(0.6, 1e-6));
  });

  test('glow disable then enable does not resurrect stale colour', () {
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
          glow: const VsdxGlow(
            enabled: true,
            sizeInches: 0.08,
            color: VsdxColor(0xFFFF0000),
            transparency: 0.3,
          ),
        ),
      ),
    );
    var bytes = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(bytes);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(glow: VsdxGlow.disabled),
      ),
    );
    bytes = writer.write(originalBytes: bytes, edited: doc);
    doc = parser.parse(bytes);
    expect(doc.pages.first.findShapeById(id)!.glow.enabled, isFalse);

    // Re-enable with default (null colour) — stale red must not resurrect.
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(
          glow: const VsdxGlow(enabled: true, transparency: 0.6),
        ),
      ),
    );
    bytes = writer.write(originalBytes: bytes, edited: doc);
    doc = parser.parse(bytes);
    final g = doc.pages.first.findShapeById(id)!.glow;
    expect(g.enabled, isTrue);
    expect(g.sizeInches, closeTo(0.05, 1e-6));
    expect(g.transparency, closeTo(0.6, 1e-6));
    expect(g.color, isNull);
  });

  test('SVG soft edges with fully transparent shadow omits shadow merge', () {
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 8.5,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 13,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
          line: const VsdxLine(softEdgesInches: 0.08),
        ).copyWith(
          shadow: const VsdxShadow(
            enabled: true,
            transparency: 1.0,
          ),
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg.contains('feGaussianBlur'), isTrue);
    expect(svg.contains('filter="url(#shadow-'), isFalse,
        reason: 'fully transparent shadow must not emit a shadow path');
    expect(svg.contains('feDropShadow'), isFalse);
  });

  test('shadow disable then enable does not resurrect stale offset/colour', () {
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
          shadow: const VsdxShadow(
            enabled: true,
            offsetXInches: 0.2,
            offsetYInches: 0.15,
            blurInches: 0.08,
            color: VsdxColor(0xFF0000FF),
            transparency: 0.25,
          ),
        ),
      ),
    );
    var bytes = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(bytes);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(shadow: VsdxShadow.disabled),
      ),
    );
    bytes = writer.write(originalBytes: bytes, edited: doc);
    doc = parser.parse(bytes);
    expect(doc.pages.first.findShapeById(id)!.shadow.enabled, isFalse);

    // Re-enable with model defaults (ox=0.05, no colour).
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(
          shadow: const VsdxShadow(enabled: true, transparency: 0.4),
        ),
      ),
    );
    bytes = writer.write(originalBytes: bytes, edited: doc);
    doc = parser.parse(bytes);
    final sh = doc.pages.first.findShapeById(id)!.shadow;
    expect(sh.enabled, isTrue);
    expect(sh.offsetXInches, closeTo(0.05, 1e-6));
    expect(sh.offsetYInches, closeTo(0.05, 1e-6));
    expect(sh.blurInches, closeTo(0.04, 1e-6));
    expect(sh.transparency, closeTo(0.4, 1e-6));
    expect(sh.color, isNull);
  });

  test('SVG skips glow when NoFill and LinePattern=0', () {
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 8.5,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 22,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
        ).copyWith(
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(pattern: 0),
          glow: const VsdxGlow(
            enabled: true,
            sizeInches: 0.08,
            transparency: 0.3,
          ),
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg.contains('glow-'), isFalse,
        reason: 'hollow shapes must not paint a ghost glow halo');
  });

  test('SVG skips SoftEdges filter when NoFill and LinePattern=0', () {
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 8.5,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 23,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
        ).copyWith(
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(pattern: 0, softEdgesInches: 0.08),
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg.contains('fx-'), isFalse,
        reason: 'hollow shapes must not hang SoftEdges blur filters');
  });

  test('SVG skips SoftEdges on NoFill+NoLine geometry even if shape has fill', () {
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 8.5,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 24,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
        ).copyWith(
          fill: const VsdxFill(
            pattern: 1,
            foreground: VsdxColor(0xFFFF0000),
          ),
          line: const VsdxLine(softEdgesInches: 0.08),
          geometries: const [
            VsdxGeometry(
              noFill: true,
              noLine: true,
              commands: [
                MoveTo(0, 0),
                LineTo(2, 0),
                LineTo(2, 1),
                LineTo(0, 1),
                LineTo(0, 0),
              ],
            ),
          ],
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg.contains('fx-'), isFalse,
        reason: 'geom hollow SoftEdges must match canvas / glowHollow');
  });

  test('SVG skips stroke shadow when NoFill and LinePattern=0', () {
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 8.5,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 21,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
        ).copyWith(
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(pattern: 0),
          shadow: const VsdxShadow(
            enabled: true,
            offsetXInches: 0.1,
            offsetYInches: 0.1,
          ),
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg.contains('filter="url(#shadow-'), isFalse,
        reason: 'canvas skips stroke shadow when LinePattern=0');
  });

  test('SVG skips reflection fill on NoFill geometry', () {
    final geom = VsdxShapeFactory.rectangle(
      id: 14,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 1,
    ).geometries.first.copyWith(noFill: true);
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 8.5,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 14,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
        ).copyWith(
          geometries: <VsdxGeometry>[geom],
          reflection: const VsdxReflection(
            enabled: true,
            sizeInches: 0.4,
            transparency: 0.5,
          ),
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    // Stroke-only mirror may still exist; filled mirror fill="#…" without
    // stroke-only path should not invent a filled reflection plate.
    expect(svg.contains('scale(1 -1)'), isTrue);
    expect(
      RegExp(r'scale\(1 -1\)[\s\S]*?fill="none"').hasMatch(svg),
      isTrue,
      reason: 'NoFill geometry reflection must not paint a solid fill',
    );
  });

  test('SVG reflection emits fade mask matching canvas', () {
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 8.5,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 12,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
        ).copyWith(
          reflection: const VsdxReflection(
            enabled: true,
            sizeInches: 0.4,
            transparency: 0.5,
          ),
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg.contains('refl-fade-'), isTrue);
    expect(svg.contains('mask="url(#refl-mask-'), isTrue);
  });

  test('SVG VerticalAlign middle honours unequal top/bottom margins', () {
    VsdxShape labeled(VsdxVertAlign v, double mt, double mb) =>
        VsdxShapeFactory.rectangle(
          id: 1,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 2,
        ).copyWith(
          richText: VsdxRichText(
            runs: const <VsdxTextRun>[VsdxTextRun(text: 'T')],
            textBlock: VsdxTextBlock(
              verticalAlign: v,
              marginTopInches: mt,
              marginBottomInches: mb,
            ),
          ),
        );
    String anchorY(VsdxShape s) {
      final svg = VsdxToSvgSerializer().serializePage(
        VsdxPage(
          id: 0,
          name: 'P',
          widthInches: 8,
          heightInches: 11,
          shapes: <VsdxShape>[s],
        ),
      );
      final re = RegExp(r'translate\(([^ ]+) ([^)]+)\) scale\(1 -1\)');
      return re.firstMatch(svg)!.group(2)!;
    }

    final equal = anchorY(labeled(VsdxVertAlign.middle, 0.1, 0.1));
    final heavyTop = anchorY(labeled(VsdxVertAlign.middle, 0.4, 0.1));
    // Larger top margin shifts the content-band centre downward (smaller Y).
    expect(double.parse(heavyTop), lessThan(double.parse(equal)));
  });

  test('SVG honours VerticalAlign top vs bottom', () {
    VsdxShape labeled(int id, VsdxVertAlign v) =>
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 2,
        ).copyWith(
          richText: VsdxRichText(
            runs: const <VsdxTextRun>[VsdxTextRun(text: 'T')],
            textBlock: VsdxTextBlock(
              verticalAlign: v,
              marginTopInches: 0.1,
              marginBottomInches: 0.1,
            ),
          ),
        );
    final topSvg = VsdxToSvgSerializer().serializePage(
      VsdxPage(
        id: 0,
        name: 'P',
        widthInches: 8,
        heightInches: 11,
        shapes: <VsdxShape>[labeled(1, VsdxVertAlign.top)],
      ),
    );
    final botSvg = VsdxToSvgSerializer().serializePage(
      VsdxPage(
        id: 0,
        name: 'P',
        widthInches: 8,
        heightInches: 11,
        shapes: <VsdxShape>[labeled(1, VsdxVertAlign.bottom)],
      ),
    );
    // Last translate before scale(1 -1) is the content anchor (y differs).
    final re = RegExp(r'translate\(([^ ]+) ([^)]+)\) scale\(1 -1\)');
    final topY = re.firstMatch(topSvg)!.group(2);
    final botY = re.firstMatch(botSvg)!.group(2);
    expect(topY, isNot(botY));
  });

  test('SVG arrow marker size follows EndArrowSize', () {
    final small = VsdxToSvgSerializer().serializePage(
      VsdxPage(
        id: 0,
        name: 'P',
        widthInches: 8,
        heightInches: 11,
        shapes: <VsdxShape>[
          VsdxShapeFactory.line(
            id: 1,
            ax: 1,
            ay: 1,
            bx: 3,
            by: 1,
            line: const VsdxLine(
              endArrow: 4,
              endArrowSizeInches: 0.125,
            ),
          ),
        ],
      ),
    );
    final large = VsdxToSvgSerializer().serializePage(
      VsdxPage(
        id: 0,
        name: 'P',
        widthInches: 8,
        heightInches: 11,
        shapes: <VsdxShape>[
          VsdxShapeFactory.line(
            id: 1,
            ax: 1,
            ay: 1,
            bx: 3,
            by: 1,
            line: const VsdxLine(
              endArrow: 4,
              endArrowSizeInches: 0.25,
            ),
          ),
        ],
      ),
    );
    expect(small.contains('markerUnits="userSpaceOnUse"'), isTrue);
    expect(small.contains('markerWidth="0.125"'), isTrue);
    expect(large.contains('markerWidth="0.25"'), isTrue,
        reason: 'arrow size is absolute inches, not strokeWidth-scaled');
  });

  test('patch clears DblUnderline when reset to false', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'X',
                charStyle: VsdxCharStyle(doubleUnderline: true),
              ),
            ],
          ),
        ),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    final cleared = doc.pages.first.findShapeById(id)!.copyWith(
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'X',
                charStyle: VsdxCharStyle(doubleUnderline: false),
              ),
            ],
          ),
        );
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(id, (_) => cleared),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.richText.runs.first.charStyle.doubleUnderline, isFalse);
  });

  test('SVG preserves per-run character styles and decorations', () {
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 8,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 7,
          pinX: 2,
          pinY: 2,
          width: 3,
          height: 1,
        ).copyWith(
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'Red',
                charStyle: VsdxCharStyle(
                  color: VsdxColor(0xFFFF0000),
                  underline: true,
                ),
              ),
              VsdxTextRun(
                text: 'Blue',
                charStyle: VsdxCharStyle(
                  color: VsdxColor(0xFF0000FF),
                  strikethrough: true,
                  fontScale: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg.contains('#ff0000'), isTrue);
    expect(svg.contains('#0000ff'), isTrue);
    expect(svg.contains('text-decoration="underline"'), isTrue);
    expect(svg.contains('text-decoration="line-through"'), isTrue);
  });

  test('SVG line gradient keeps LineColorTrans stroke-opacity', () {
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 8,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.line(
          id: 8,
          ax: 1,
          ay: 1,
          bx: 4,
          by: 1,
          line: VsdxLine(
            transparency: 0.4,
            weightInches: 0.05,
            gradient: VsdxGradient(
              stops: const <VsdxGradientStop>[
                VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
                VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
              ],
            ),
          ),
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg.contains('stroke="url(#lg-p0-8-0)"'), isTrue);
    expect(svg.contains('stroke-opacity="0.6"'), isTrue);
  });

  test('SVG pattern 8 emits dots not diagonal fallback', () {
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 8,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 9,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
          fill: const VsdxFill(
            pattern: 8,
            foreground: VsdxColor(0xFF000000),
            background: VsdxColor(0xFFFFFFFF),
          ),
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg.contains('<circle '), isTrue);
    expect(svg.contains('id="pat-p0-9-0"'), isTrue);
  });

  test('SVG arrow marker respects open-triangle id', () {
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 8,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.line(
          id: 10,
          ax: 1,
          ay: 2,
          bx: 4,
          by: 2,
          line: const VsdxLine(endArrow: 1, endArrowSizeInches: 0.125),
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    // Open triangle: stroked, not filled (explicit colour carries LineColorTrans).
    expect(svg.contains('fill="none" stroke="#000000"'), isTrue);
    expect(svg.contains('M 0 1 L 10 5 L 0 9 Z'), isTrue);
  });

  test('SVG TxtAngle rotates about TxtPin not text centroid', () {
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 8,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 11,
          pinX: 3,
          pinY: 3,
          width: 2,
          height: 2,
        ).copyWith(
          richText: VsdxRichText(
            runs: const <VsdxTextRun>[VsdxTextRun(text: 'A')],
            textBlock: const VsdxTextBlock(
              pinXInches: 0.2,
              pinYInches: 0.2,
              locPinXInches: 0,
              locPinYInches: 0,
              widthInches: 1,
              heightInches: 1,
              angleRad: 0.5,
            ),
          ),
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    // Canvas-style: translate(TxtPin) rotate(...) translate(-TxtLocPin)
    final xf = RegExp(r'transform="([^"]*rotate[^"]*)"').firstMatch(svg);
    expect(xf, isNotNull, reason: 'expected rotated text transform in $svg');
    final t = xf!.group(1)!;
    expect(t.contains('rotate('), isTrue);
    // Pin comes before rotate; LocPin offset follows rotate.
    expect(t.indexOf('translate(0.2'), lessThan(t.indexOf('rotate(')));
    expect(t.indexOf('rotate('), lessThan(t.lastIndexOf('translate(')));
  });

  test('SVG exports reflection clip + optional blur', () {
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 8.5,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 6,
          pinX: 2,
          pinY: 3,
          width: 2,
          height: 1,
        ).copyWith(
          reflection: const VsdxReflection(
            enabled: true,
            sizeInches: 0.5,
            distanceInches: 0.1,
            blurInches: 0.04,
            transparency: 0.3,
          ),
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg.contains('refl-clip-p0-6-0'), isTrue);
    expect(svg.contains('scale(1 -1)'), isTrue);
    // Reflection lives below the shape (negative Y in shape-local Y-up).
    expect(svg.contains('y="-0.6"'), isTrue);
  });

  test('SVG fill gradient multiplies FillForegndTrans into stop-opacity', () {
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 8,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 7,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
        ).copyWith(
          fill: VsdxFill(
            foregroundTransparency: 0.5,
            gradient: VsdxGradient(
              stops: const <VsdxGradientStop>[
                VsdxGradientStop(
                  position: 0,
                  color: VsdxColor(0xFFFF0000),
                ),
                VsdxGradientStop(
                  position: 1,
                  color: VsdxColor(0xFF0000FF),
                ),
              ],
            ),
          ),
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg.contains('linearGradient'), isTrue);
    // Opaque stops × (1 - 0.5) → stop-opacity 0.5.
    expect(svg.contains('stop-opacity="0.5"'), isTrue);
  });

  test('SVG shadow dy keeps Visio +Y up (matches canvas)', () {
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 8,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 8,
          pinX: 2,
          pinY: 2,
          width: 1,
          height: 1,
        ).copyWith(
          shadow: const VsdxShadow(
            enabled: true,
            offsetXInches: 0.1,
            offsetYInches: 0.2,
          ),
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    // +ShadowOffsetY is up in Visio Y-up; shadow path uses translate(dx dy).
    expect(svg.contains('translate(0.1 0.2)'), isTrue);
    expect(svg.contains('translate(0.1 -0.2)'), isFalse);
  });

  test('SVG uses meaningful shape name as label fallback', () {
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 8,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 12,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
          name: 'Process',
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg.contains('Process'), isTrue);
    // Auto Sheet.N names must stay blank.
    final auto = VsdxToSvgSerializer().serializePage(
      VsdxPage(
        id: 0,
        name: 'P',
        widthInches: 8,
        heightInches: 11,
        shapes: <VsdxShape>[
          VsdxShapeFactory.rectangle(
            id: 13,
            pinX: 2,
            pinY: 2,
            width: 1,
            height: 1,
          ),
        ],
      ),
    );
    expect(auto.contains('Sheet.13'), isFalse);
  });

  test('SVG exports bullet glyph and mixed paragraph alignment', () {
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 8,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 14,
          pinX: 3,
          pinY: 3,
          width: 3,
          height: 2,
        ).copyWith(
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'Left\n',
                paraStyle: VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.left,
                  bullet: 1,
                  indentLeftInches: 0.15,
                  spaceBeforeInches: 0.05,
                ),
              ),
              VsdxTextRun(
                text: 'Right',
                paraStyle: VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.right,
                  spaceBeforeInches: 0.1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg.contains('•'), isTrue);
    expect(svg.contains('text-anchor="start"'), isTrue);
    expect(svg.contains('text-anchor="end"'), isTrue);
  });

  test('patch clears Paragraph Bullet/SpBefore when reset to defaults', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 1,
          pinY: 1,
          width: 2,
          height: 1,
        ).copyWith(
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'Item',
                paraStyle: VsdxParaStyle(
                  bullet: 1,
                  spaceBeforeInches: 0.2,
                  indentLeftInches: 0.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    expect(doc.pages.first.findShapeById(id)!.richText.runs.first.paraStyle.bullet,
        1);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'Item',
                paraStyle: VsdxParaStyle(),
              ),
            ],
          ),
        ),
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final after = parser.parse(out).pages.first.findShapeById(id)!;
    expect(after.richText.runs.first.paraStyle.bullet, 0);
    expect(after.richText.runs.first.paraStyle.spaceBeforeInches, 0);
    expect(after.richText.runs.first.paraStyle.indentLeftInches, 0);
  });

  test('patch removes deleted layer rows', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(
      0,
      doc.pages.first.copyWith(
        layers: const <VsdxLayer>[
          VsdxLayer(id: 0, name: 'A'),
          VsdxLayer(id: 1, name: 'B'),
        ],
      ),
    );
    final mid = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(mid);
    expect(doc.pages.first.layers.length, 2);
    doc = doc.replacePage(
      0,
      doc.pages.first.copyWith(
        layers: const <VsdxLayer>[VsdxLayer(id: 0, name: 'A')],
      ),
    );
    final out = writer.write(originalBytes: mid, edited: doc);
    final after = parser.parse(out).pages.first;
    expect(after.layers.map((l) => l.id).toList(), <int>[0]);
    expect(after.layers.single.name, 'A');
  });

  test('setShadow toggles restore colour/offset; setLinePattern(0) clears gradient',
      () {
    final e = EditorController()..newDocument();
    addTearDown(e.dispose);
    e.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 2,
        height: 1,
      ).copyWith(
        shadow: const VsdxShadow(
          enabled: true,
          color: VsdxColor(0xFF1565C0),
          offsetXInches: 0.2,
          offsetYInches: 0.15,
          blurInches: 0.08,
          transparency: 0.3,
        ),
        line: const VsdxLine(
          color: VsdxColor.black,
          weightInches: 0.02,
          gradient: VsdxGradient(
            stops: <VsdxGradientStop>[
              VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
              VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
            ],
          ),
        ),
      ),
      3,
      3,
    );
    final id = e.singleSelectedId!;
    e.setShadow(false);
    expect(e.currentPage!.findShapeById(id)!.shadow.enabled, isFalse);
    expect(
      e.currentPage!.findShapeById(id)!.shadow.color?.value,
      0xFF1565C0,
    );
    e.setShadow(true);
    final sh = e.currentPage!.findShapeById(id)!.shadow;
    expect(sh.enabled, isTrue);
    expect(sh.color?.value, 0xFF1565C0);
    expect(sh.offsetXInches, closeTo(0.2, 1e-6));

    e.setLinePattern(0);
    final line = e.currentPage!.findShapeById(id)!.line;
    expect(line.pattern, 0);
    expect(line.gradient, isNull);
  });

  test('disabled glow colour survives save → reopen for re-enable', () {
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
          glow: const VsdxGlow(
            enabled: true,
            color: VsdxColor(0xFF00AA00),
            sizeInches: 0.08,
            transparency: 0.4,
          ),
        ),
      ),
    );
    var bytes = writer.write(originalBytes: blank, edited: doc);
    doc = parser.parse(bytes);
    doc = doc.replacePage(
      0,
      doc.pages.first.updateShapeById(
        id,
        (s) => s.copyWith(glow: s.glow.copyWith(enabled: false)),
      ),
    );
    bytes = writer.write(originalBytes: bytes, edited: doc);
    final after = parser.parse(bytes).pages.first.findShapeById(id)!;
    expect(after.glow.enabled, isFalse);
    expect(after.glow.color?.value, 0xFF00AA00,
        reason: 'GlowColor cell must survive Size=0 for toggle restore');
  });

  test('SVG FontScale uses letter-spacing not font-size scale', () {
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 8,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 1,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
        ).copyWith(
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'Wide',
                charStyle: VsdxCharStyle(
                  fontSizeInches: 0.2,
                  fontScale: 2.0,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg.contains('font-size="0.4"'), isFalse,
        reason: 'FontScale must not inflate glyph height');
    expect(svg.contains('font-size="0.2"'), isTrue);
    expect(svg.contains('letter-spacing='), isTrue);
  });

  test('SVG FontScale merges with Letterspace (no duplicate override)', () {
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 8,
      heightInches: 11,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 1,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
        ).copyWith(
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'Wide',
                charStyle: VsdxCharStyle(
                  fontSizeInches: 0.2,
                  fontScale: 2.0,
                  letterSpacingInches: 0.05,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    // Combined ≈ 0.05 + 0.2*(2-1)*0.15 = 0.08
    expect(svg, contains('letter-spacing="0.08"'));
    expect(
      RegExp(r'letter-spacing="').allMatches(svg).length,
      1,
      reason: 'raw Letterspace must not overwrite FontScale-merged spacing',
    );
    expect(svg.contains('letter-spacing="0.05"'), isFalse);
  });

  test('setGlow toggles restore theme slot; setFillPattern(0) clears gradient',
      () {
    final e = EditorController()..newDocument();
    addTearDown(e.dispose);
    e.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 2,
        height: 1,
        fill: VsdxFill(
          pattern: 1,
          foreground: const VsdxColor(0xFFFF0000),
          gradient: VsdxGradient(
            stops: const <VsdxGradientStop>[
              VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
              VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
            ],
          ),
        ),
      ).copyWith(
        glow: const VsdxGlow(
          enabled: true,
          themeColorIndex: ThemeSlot.accent1,
          sizeInches: 0.08,
          transparency: 0.4,
        ),
      ),
      3,
      3,
    );
    final id = e.singleSelectedId!;
    e.setGlow(false);
    expect(e.currentPage!.findShapeById(id)!.glow.enabled, isFalse);
    expect(
      e.currentPage!.findShapeById(id)!.glow.themeColorIndex,
      ThemeSlot.accent1,
    );
    e.setGlow(true);
    final glow = e.currentPage!.findShapeById(id)!.glow;
    expect(glow.enabled, isTrue);
    expect(glow.themeColorIndex, ThemeSlot.accent1);
    expect(glow.sizeInches, closeTo(0.08, 1e-6));
    expect(glow.color, isNull);

    e.setFillPattern(0);
    final fill = e.currentPage!.findShapeById(id)!.fill;
    expect(fill.pattern, 0);
    expect(fill.gradient, isNull);
  });

  test('glued connector jetty round-trips through export → reopen', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final src = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4,
      pinY: 8,
      width: 1.5,
      height: 1,
    );
    final oval = VsdxShapeFactory.ellipse(
      id: 2,
      pinX: 4,
      pinY: 3,
      width: 3,
      height: 2,
    );
    final conn = VsdxShapeFactory.line(id: 3, ax: 4, ay: 8, bx: 4, by: 3);
    doc = doc.replacePage(
      0,
      doc.pages.first
          .copyWith(
            shapes: <VsdxShape>[src, oval, conn],
            connects: const <VsdxConnect>[
              VsdxConnect(
                fromSheetId: 3,
                fromCell: 'BeginX',
                fromPart: 9,
                toSheetId: 1,
                toCell: 'PinX',
                toPart: 3,
              ),
              VsdxConnect(
                fromSheetId: 3,
                fromCell: 'EndX',
                fromPart: 12,
                toSheetId: 2,
                toCell: 'PinX',
                toPart: 3,
              ),
            ],
          )
          .rerouteConnectors(),
    );
    final before = VsdxPage.connectorRoute(doc.pages.first.findShapeById(3)!);
    final tip = before.last;
    final prev = before[before.length - 2];
    expect(prev.x, closeTo(tip.x, 1e-6));
    expect(prev.y, greaterThan(tip.y + 1e-3));

    final out = writer.write(originalBytes: blank, edited: doc);
    final afterDoc = parser.parse(out);
    final afterRoute =
        VsdxPage.connectorRoute(afterDoc.pages.first.findShapeById(3)!);
    final aTip = afterRoute.last;
    final aPrev = afterRoute[afterRoute.length - 2];
    expect(aPrev.x, closeTo(aTip.x, 1e-6));
    expect(aPrev.y, greaterThan(aTip.y + 1e-3));
    expect(afterDoc.pages.first.connects, hasLength(2));
  });
}
