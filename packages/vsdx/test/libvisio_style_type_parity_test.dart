/// Fill, line and Rounding types must paint here, and a save must emit the
/// cells / rows LibreOffice's libvisio importer still collects.
///
/// `VSDXParser` has no FillGradient token, no shape-level Rounding, no
/// CompoundType token, no LineGradient token, and no LineColorTrans token
/// (`xmlStringToColour` also forces Colour.a = 0). A modern gradient with
/// FillPattern=1, a polyline with only a Rounding cell, a CompoundType>0
/// stroke, an unfilled LineGradient, or a semi-transparent stroke
/// disappears or goes fully opaque in Draw. The writer rewrites those to
/// classic FillPattern 25–40, baked RelQuadBezTo corners, parallel Geometry
/// rails (including 1-D), and a filled ribbon for line gradients and
/// LineColorTrans (2-D and 1-D) whose FillForegndTrans libvisio *does*
/// collect. Arrowed 1-D connectors that also need rails or a ribbon bake
/// Begin/EndArrow as filled Geometry so Draw does not hang a marker on
/// every open rail, and so BeginArrowSize (not a token) still has a size.
/// Classic FillPattern 25–40 also paint here even when the model has no
/// stop section yet. Unknown LinePattern ids snap to the built-in 2–23
/// table `_lineProperties` actually dashes. `LineCap` 0/1/2 is a token
/// libvisio *does* collect. Character Highlight is skipped by `readCharIX`
/// but a uniform marker with no authored TextBkgnd is written there —
/// `VSDContentCollector` paints it as span `fo:background-color` and Draw
/// shows the plate. `RVNGSVGDrawingGenerator` drops that property, so the
/// oracle SVG is the wrong place to look; `vsd2raw` still has it. Overline
/// / ColorTrans still paint here even though `readCharIX` skips Overline
/// and `xmlStringToColour` zeros alpha. `AsianFont` is not a token, so a
/// CJK-only run whose Visio `Font` is Arial is rewritten to the Asian face
/// Draw will actually load.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

import 'support/libvisio_oracle.dart';

void main() {
  const writer = VsdxWriter();
  const parser = DocumentParser();

  test('arrowed 1-D compound/gradient/trans bake markers then rails/ribbon',
      () {
    VsdxLine arrowed({
      int compoundType = 0,
      double transparency = 0,
      VsdxGradient? gradient,
    }) =>
        VsdxLine(
          color: const VsdxColor(0xFF000000),
          weightInches: 0.08,
          pattern: 1,
          compoundType: compoundType,
          transparency: transparency,
          gradient: gradient,
          beginArrow: 4,
          endArrow: 13,
          beginArrowSizeInches: 0.25,
          endArrowSizeInches: 0.25,
        );

    final compound = VsdxShapeFactory.line(
      id: 1,
      ax: 0,
      ay: 0,
      bx: 3,
      by: 0,
      line: arrowed(compoundType: 1),
    );
    expect(shapeNeedsLibvisioArrowedStrokeBake(compound), isTrue);
    final compoundWrite = libvisioShapeWrite(compound);
    expect(compoundWrite.line.beginArrow, 0);
    expect(compoundWrite.line.endArrow, 0);
    expect(compoundWrite.line.compoundType, 0);
    expect(
      compoundWrite.geometries.where((g) => !g.noLine).length,
      greaterThan(1),
    );
    expect(
      compoundWrite.geometries.where((g) => !g.noFill).length,
      greaterThanOrEqualTo(2),
    );
    expect(compoundWrite.fill.pattern, isNot(0));

    final gradient = VsdxShapeFactory.line(
      id: 2,
      ax: 0,
      ay: 0,
      bx: 3,
      by: 0,
      line: arrowed(
        gradient: const VsdxGradient(
          stops: [
            VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
            VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
          ],
        ),
      ),
    );
    expect(shapeNeedsLibvisioArrowedStrokeBake(gradient), isTrue);
    final gradientWrite = libvisioShapeWrite(gradient);
    expect(gradientWrite.line.beginArrow, 0);
    expect(gradientWrite.line.hasGradient, isFalse);
    expect(gradientWrite.fill.hasFill, isTrue);
    expect(gradientWrite.geometries.any((g) => !g.noFill), isTrue);

    final trans = VsdxShapeFactory.line(
      id: 3,
      ax: 0,
      ay: 0,
      bx: 3,
      by: 0,
      line: arrowed(transparency: 0.5),
    );
    expect(shapeNeedsLibvisioArrowedStrokeBake(trans), isTrue);
    final transWrite = libvisioShapeWrite(trans);
    expect(transWrite.line.beginArrow, 0);
    expect(transWrite.fill.foregroundTransparency, closeTo(0.5, 1e-9));

    final plain = VsdxShapeFactory.line(
      id: 4,
      ax: 0,
      ay: 0,
      bx: 3,
      by: 0,
      line: arrowed(),
    );
    expect(shapeNeedsLibvisioArrowedStrokeBake(plain), isFalse);
    expect(libvisioShapeWrite(plain).line.beginArrow, 4);
  });

  test('uniform Character Highlight bakes to TextBkgnd for LibreOffice', () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.4,
      height: 0.7,
      name: 'Hi',
    ).copyWith(
      text: 'Hi',
      richText: const VsdxRichText(
        runs: [
          VsdxTextRun(
            text: 'Hi',
            charStyle: VsdxCharStyle(highlight: VsdxColor(0xFFFF00FF)),
          ),
        ],
      ),
    );
    expect(shapeNeedsLibvisioTextBkgndBake(shape), isTrue);
    expect(
      textBlockForLibvisioWrite(shape).backgroundColor?.value,
      0xFFFF00FF,
    );
    expect(textBlockForPaint(shape).backgroundColor, isNull);
    final withBlock = shape.copyWith(
      richText: shape.richText.copyWith(
        textBlock: shape.richText.textBlock.copyWith(
          backgroundColor: const VsdxColor(0xFF00FF00),
        ),
      ),
    );
    expect(shapeNeedsLibvisioTextBkgndBake(withBlock), isFalse);
  });

  test('CJK-only Character Font bakes AsianFont for LibreOffice', () {
    final cjk = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.4,
      height: 0.7,
      name: 'CJK',
    ).copyWith(
      text: '你好',
      richText: const VsdxRichText(
        runs: [
          VsdxTextRun(
            text: '你好',
            charStyle: VsdxCharStyle(
              fontFamily: 'Arial',
              asianFont: 'Microsoft YaHei',
            ),
          ),
        ],
      ),
    );
    expect(shapeNeedsLibvisioFontBake(cjk), isTrue);
    expect(
      fontFamilyForLibvisioWrite(cjk.richText.runs.single.charStyle, '你好'),
      'Microsoft YaHei',
    );
    final latin = cjk.copyWith(
      text: 'Hi',
      richText: const VsdxRichText(
        runs: [
          VsdxTextRun(
            text: 'Hi',
            charStyle: VsdxCharStyle(
              fontFamily: 'Arial',
              asianFont: 'Microsoft YaHei',
            ),
          ),
        ],
      ),
    );
    expect(shapeNeedsLibvisioFontBake(latin), isFalse);
    expect(
      fontFamilyForLibvisioWrite(latin.richText.runs.single.charStyle, 'Hi'),
      'Arial',
    );
  });

  test('classic FillPattern 2–40 and modern FillGradient paint and save', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final page = doc.pages.first;
    var nextId = page.nextFreeShapeId();
    var built = page;

    VsdxShape box(String name, VsdxFill fill, {VsdxLine? line}) {
      return VsdxShapeFactory.rectangle(
        id: nextId++,
        pinX: 2,
        pinY: 4,
        width: 1.4,
        height: 0.7,
        name: name,
        fill: fill,
        line: line ?? const VsdxLine(color: VsdxColor.black, pattern: 0),
      );
    }

    for (final pattern in <int>[2, 8, 24, 25, 27, 35, 40]) {
      built = built.addShape(
        box(
          'Fill$pattern',
          VsdxFill(
            foreground: const VsdxColor(0xFFFF0000),
            background: const VsdxColor(0xFF0000FF),
            pattern: pattern,
          ),
        ),
      );
    }
    built = built.addShape(
      box(
        'FillGradient',
        const VsdxFill(
          foreground: VsdxColor(0xFFFF0000),
          background: VsdxColor(0xFF0000FF),
          pattern: 1,
          gradient: VsdxGradient(
            stops: [
              VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
              VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
            ],
          ),
        ),
      ),
    );
    built = built.addShape(
      box(
        'Rounding',
        const VsdxFill(foreground: VsdxColor(0xFFFFFF00), pattern: 1),
        line: const VsdxLine(
          color: VsdxColor.black,
          roundingInches: 0.15,
        ),
      ),
    );
    built = built.addShape(
      box(
        'CompoundDouble',
        const VsdxFill(foreground: VsdxColor(0xFFCCCCCC), pattern: 1),
        line: const VsdxLine(
          color: VsdxColor.black,
          weightInches: 0.08,
          compoundType: 1,
        ),
      ),
    );
    built = built.addShape(
      VsdxShapeFactory.line(
        id: nextId++,
        ax: 1,
        ay: 0.6,
        bx: 4,
        by: 0.6,
        name: 'Compound1D',
        line: const VsdxLine(
          color: VsdxColor.black,
          weightInches: 0.08,
          compoundType: 1,
        ),
      ),
    );
    built = built.addShape(
      box(
        'CompoundThickThin',
        const VsdxFill(foreground: VsdxColor(0xFFCCCCCC), pattern: 1),
        line: const VsdxLine(
          color: VsdxColor.black,
          weightInches: 0.08,
          compoundType: 2,
        ),
      ),
    );
    built = built.addShape(
      VsdxShape(
        id: nextId++,
        name: 'LineGradient',
        pinX: 5,
        pinY: 2,
        width: 2,
        height: 0.2,
        geometries: const <VsdxGeometry>[
          VsdxGeometry(
            noFill: true,
            commands: <VsdxPathCommand>[MoveTo(0, 0.1), LineTo(2, 0.1)],
          ),
        ],
        line: const VsdxLine(
          pattern: 1,
          weightInches: 0.06,
          gradient: VsdxGradient(
            stops: [
              VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
              VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
            ],
          ),
        ),
      ),
    );
    built = built.addShape(
      VsdxShapeFactory.line(
        id: nextId++,
        ax: 1,
        ay: 1.2,
        bx: 4,
        by: 1.2,
        name: 'LineGradient1D',
        line: const VsdxLine(
          pattern: 1,
          weightInches: 0.06,
          gradient: VsdxGradient(
            stops: [
              VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
              VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
            ],
          ),
        ),
      ),
    );
    built = built.addShape(
      VsdxShape(
        id: nextId++,
        name: 'LineColorTrans',
        pinX: 5,
        pinY: 1.6,
        width: 2,
        height: 0.2,
        geometries: const <VsdxGeometry>[
          VsdxGeometry(
            noFill: true,
            commands: <VsdxPathCommand>[MoveTo(0, 0.1), LineTo(2, 0.1)],
          ),
        ],
        line: const VsdxLine(
          color: VsdxColor.black,
          pattern: 1,
          weightInches: 0.08,
          transparency: 0.5,
        ),
      ),
    );
    built = built.addShape(
      VsdxShapeFactory.line(
        id: nextId++,
        ax: 1,
        ay: 1.8,
        bx: 4,
        by: 1.8,
        name: 'LineColorTrans1D',
        line: const VsdxLine(
          color: VsdxColor.black,
          pattern: 1,
          weightInches: 0.08,
          transparency: 0.5,
        ),
      ),
    );
    built = built.addShape(
      VsdxShapeFactory.line(
        id: nextId++,
        ax: 1,
        ay: 2.4,
        bx: 4,
        by: 2.4,
        name: 'ArrowedCompound1D',
        line: const VsdxLine(
          color: VsdxColor.black,
          weightInches: 0.08,
          compoundType: 1,
          beginArrow: 4,
          endArrow: 13,
          beginArrowSizeInches: 0.25,
          endArrowSizeInches: 0.25,
        ),
      ),
    );
    built = built.addShape(
      VsdxShapeFactory.line(
        id: nextId++,
        ax: 1,
        ay: 3.0,
        bx: 4,
        by: 3.0,
        name: 'ArrowedLineGradient1D',
        line: const VsdxLine(
          pattern: 1,
          weightInches: 0.06,
          beginArrow: 4,
          endArrow: 13,
          beginArrowSizeInches: 0.25,
          endArrowSizeInches: 0.25,
          gradient: VsdxGradient(
            stops: [
              VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
              VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
            ],
          ),
        ),
      ),
    );
    built = built.addShape(
      VsdxShapeFactory.line(
        id: nextId++,
        ax: 1,
        ay: 3.6,
        bx: 4,
        by: 3.6,
        name: 'ArrowedLineColorTrans1D',
        line: const VsdxLine(
          color: VsdxColor.black,
          pattern: 1,
          weightInches: 0.08,
          transparency: 0.5,
          beginArrow: 4,
          endArrow: 13,
          beginArrowSizeInches: 0.25,
          endArrowSizeInches: 0.25,
        ),
      ),
    );
    for (final entry in <(String, LineCap)>[
      ('CapRound', LineCap.round),
      ('CapSquare', LineCap.square),
      ('CapFlat', LineCap.extended),
    ]) {
      built = built.addShape(
        VsdxShapeFactory.line(
          id: nextId++,
          ax: 5,
          ay: 0.3,
          bx: 8,
          by: 0.3,
          name: entry.$1,
          line: VsdxLine(
            color: const VsdxColor(0xFF000000),
            weightInches: 0.08,
            cap: entry.$2,
          ),
        ),
      );
    }
    built = built.addShape(
      VsdxShapeFactory.rectangle(
        id: nextId++,
        pinX: 7,
        pinY: 4,
        width: 1.4,
        height: 0.7,
        name: 'Highlight',
        fill: const VsdxFill(foreground: VsdxColor(0xFFFFFFFF), pattern: 1),
        line: const VsdxLine(color: VsdxColor.black, pattern: 0),
      ).copyWith(
        text: 'Hi',
        richText: const VsdxRichText(
          runs: [
            VsdxTextRun(
              text: 'Hi',
              charStyle: VsdxCharStyle(
                highlight: VsdxColor(0xFFFF00FF),
                overline: true,
                transparency: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
    built = built.addShape(
      VsdxShapeFactory.rectangle(
        id: nextId++,
        pinX: 7,
        pinY: 3,
        width: 1.4,
        height: 0.7,
        name: 'CJK',
        fill: const VsdxFill(foreground: VsdxColor(0xFFFFFFFF), pattern: 1),
        line: const VsdxLine(color: VsdxColor.black, pattern: 0),
      ).copyWith(
        text: '你好',
        richText: const VsdxRichText(
          runs: [
            VsdxTextRun(
              text: '你好',
              charStyle: VsdxCharStyle(
                fontFamily: 'Arial',
                asianFont: 'Microsoft YaHei',
              ),
            ),
          ],
        ),
      ),
    );
    for (final pattern in <int>[2, 10, 23]) {
      built = built.addShape(
        VsdxShape(
          id: nextId++,
          name: 'Dash$pattern',
          pinX: 5,
          pinY: 4,
          width: 2,
          height: 0.2,
          geometries: const <VsdxGeometry>[
            VsdxGeometry(
              noFill: true,
              commands: <VsdxPathCommand>[MoveTo(0, 0.1), LineTo(2, 0.1)],
            ),
          ],
          line: VsdxLine(
            color: const VsdxColor(0xFF000000),
            pattern: pattern,
            beginArrow: pattern == 2 ? 4 : 0,
            endArrow: pattern == 2 ? 13 : 0,
          ),
        ),
      );
    }

    doc = doc.replacePage(0, built);
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('<pattern'), reason: 'hatch FillPattern 2–24');
    expect(svg, contains('linearGradient'),
        reason: 'linear classic / FillGradient');
    expect(svg, contains('radialGradient'), reason: 'FillPattern 35–40');
    expect(svg, contains('stroke-dasharray="'), reason: 'LinePattern 2–23');
    expect(svg, contains('<marker'), reason: 'BeginArrow / EndArrow');
    expect(RegExp(r'\bQ ').hasMatch(svg), isTrue, reason: 'Rounding fillets');
    expect(svg, contains('paint-order="stroke fill"'),
        reason: 'Character Highlight marker halo');
    expect(svg.toLowerCase(), contains('#ff00ff'),
        reason: 'Character Highlight colour');
    expect(svg, contains('text-decoration="overline"'),
        reason: 'Character Overline is skipped by readCharIX but still paints');
    expect(svg, contains('stroke-linecap="round"'));
    expect(svg, contains('stroke-linecap="square"'));
    expect(svg, contains('stroke-linecap="butt"'),
        reason: 'Visio LineCap=1 / libvisio cap 1 maps to SVG butt');
    expect(svg, contains('stroke-opacity="0.5"'),
        reason:
            'LineColorTrans must paint here even though tokens.txt omits it');
    expect(svg, contains('fill-opacity="0.6"'),
        reason: 'Character ColorTrans 0.4 paints as fill-opacity 0.6; '
            'xmlStringToColour zeros alpha');

    final saved = writer.write(originalBytes: blank, edited: doc);
    final xml = VsdxPackage.open(saved)
        .readPartXml('/visio/pages/page1.xml')!
        .toXmlString();
    expect(xml, contains('T="RelQuadBezTo"'), reason: 'Rounding bakes for LO');
    expect(xml, contains('N="CompoundType" V="0"'),
        reason: 'CompoundType 1 bakes to rails; cell must be 0 so Visio '
            'does not restroke the original path');
    expect(
      xml.contains('N="LineGradientEnabled" V="1"'),
      isFalse,
      reason: 'Unfilled LineGradient (2-D and arrow-less 1-D) bakes to a '
          'FillPattern ribbon; tokens.txt has no LineGradient cell',
    );
    expect(xml, contains('N="LineColor" V="#FF0000"'),
        reason:
            'LineGradient without LineColor must emit a stop colour for LO');
    expect(xml, contains('N="Highlight" V="#FF00FF"'),
        reason:
            'Character Highlight must round-trip even though libvisio skips it');
    expect(xml, contains('N="Overline" V="1"'),
        reason:
            'Character Overline must round-trip even though libvisio skips it');
    expect(xml, contains('N="ColorTrans" V="0.4"'),
        reason:
            'Character ColorTrans must round-trip even though libvisio zeros alpha');
    expect(xml, contains('N="Font" V="Microsoft YaHei"'),
        reason:
            'readCharIX only stores Font; CJK-only Arial bakes to AsianFont');
    expect(xml, contains('N="FillForegndTrans" V="0.5"'),
        reason:
            'LineColorTrans bakes to FillForegndTrans which readShapeProperties collects');
    expect(xml, contains('N="LineCap" V="1"'),
        reason:
            'Visio LineCap 1 (extended/flat) is what libvisio maps to butt');
    expect(xml, contains('N="LineCap" V="2"'),
        reason: 'Visio LineCap 2 (square) is what libvisio maps to SVG square');
    expect(
      xml.contains('N="FillPattern" V="1"') &&
          xml.contains('N="FillGradientEnabled" V="1"'),
      isTrue,
    );
    // Modern FillGradient must also carry a classic id libvisio collects.
    expect(
      RegExp(r'N="FillPattern" V="(2[5-9]|3[0-9]|40)"').hasMatch(xml),
      isTrue,
      reason: 'FillGradient fallback must be FillPattern 25–40',
    );

    final savedDoc = parser.parse(saved);
    final lineGradient =
        savedDoc.pages.first.shapes.firstWhere((s) => s.name == 'LineGradient');
    expect(lineGradient.line.hasGradient, isFalse);
    expect(lineGradient.line.pattern, 0);
    expect(
      lineGradient.fill.hasGradient ||
          (lineGradient.fill.pattern >= 25 && lineGradient.fill.pattern <= 40),
      isTrue,
      reason: 'LineGradient ribbon must become a classic FillPattern',
    );
    expect(lineGradient.geometries.any((g) => !g.noFill), isTrue);
    final lineGradient1d = savedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'LineGradient1D');
    expect(lineGradient1d.is1D, isTrue);
    expect(lineGradient1d.line.hasGradient, isFalse);
    expect(lineGradient1d.line.pattern, 0);
    expect(
      lineGradient1d.fill.hasGradient ||
          (lineGradient1d.fill.pattern >= 25 &&
              lineGradient1d.fill.pattern <= 40),
      isTrue,
      reason: 'Arrow-less 1-D LineGradient bakes the same ribbon as 2-D',
    );
    expect(lineGradient1d.geometries.any((g) => !g.noFill), isTrue);
    final lineColorTrans = savedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'LineColorTrans');
    expect(lineColorTrans.line.pattern, 0);
    expect(lineColorTrans.fill.foregroundTransparency, closeTo(0.5, 1e-9));
    expect(lineColorTrans.geometries.any((g) => !g.noFill), isTrue);
    final lineColorTrans1d = savedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'LineColorTrans1D');
    expect(lineColorTrans1d.is1D, isTrue);
    expect(lineColorTrans1d.line.pattern, 0);
    expect(lineColorTrans1d.fill.foregroundTransparency, closeTo(0.5, 1e-9));
    expect(lineColorTrans1d.geometries.any((g) => !g.noFill), isTrue);
    final compound1d =
        savedDoc.pages.first.shapes.firstWhere((s) => s.name == 'Compound1D');
    expect(compound1d.line.compoundType, 0);
    expect(
      compound1d.geometries.where((g) => !g.noLine).length,
      greaterThan(1),
    );
    final arrowedCompound = savedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'ArrowedCompound1D');
    expect(arrowedCompound.is1D, isTrue);
    expect(arrowedCompound.line.beginArrow, 0);
    expect(arrowedCompound.line.endArrow, 0);
    expect(arrowedCompound.line.compoundType, 0);
    expect(
      arrowedCompound.geometries.where((g) => !g.noLine).length,
      greaterThan(1),
      reason: 'Arrowed CompoundType 1-D still bakes parallel rails',
    );
    expect(
      arrowedCompound.geometries.where((g) => !g.noFill).length,
      greaterThanOrEqualTo(2),
      reason: 'Begin/EndArrow bake to filled Geometry so Draw can paint them',
    );
    final arrowedGradient = savedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'ArrowedLineGradient1D');
    expect(arrowedGradient.is1D, isTrue);
    expect(arrowedGradient.line.beginArrow, 0);
    expect(arrowedGradient.line.hasGradient, isFalse);
    expect(
      arrowedGradient.fill.hasGradient ||
          (arrowedGradient.fill.pattern >= 25 &&
              arrowedGradient.fill.pattern <= 40),
      isTrue,
      reason: 'Arrowed 1-D LineGradient bakes the same ribbon as arrow-less',
    );
    expect(
      arrowedGradient.geometries.where((g) => !g.noFill).length,
      greaterThanOrEqualTo(2),
    );
    final arrowedTrans = savedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'ArrowedLineColorTrans1D');
    expect(arrowedTrans.is1D, isTrue);
    expect(arrowedTrans.line.beginArrow, 0);
    expect(arrowedTrans.line.pattern, 0);
    expect(arrowedTrans.fill.foregroundTransparency, closeTo(0.5, 1e-9));
    expect(
      arrowedTrans.geometries.where((g) => !g.noFill).length,
      greaterThanOrEqualTo(2),
    );
    final thickThin = savedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'CompoundThickThin');
    expect(thickThin.line.compoundType, 0);
    expect(
      thickThin.geometries.where((g) => !g.noLine).length,
      greaterThan(1),
    );
    expect(
      savedDoc.pages.first.shapes
          .firstWhere((s) => s.name == 'CapFlat')
          .line
          .cap,
      LineCap.extended,
    );
    expect(
      savedDoc.pages.first.shapes
          .firstWhere((s) => s.name == 'CapSquare')
          .line
          .cap,
      LineCap.square,
    );
    final highlightStyle = savedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'Highlight')
        .richText
        .runs
        .single
        .charStyle;
    expect(highlightStyle.highlight?.value, 0xFFFF00FF);
    expect(highlightStyle.overline, isTrue);
    expect(highlightStyle.transparency, closeTo(0.4, 1e-9));
    final highlightBlock = savedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'Highlight')
        .richText
        .textBlock;
    expect(highlightBlock.backgroundColor?.value, 0xFFFF00FF,
        reason: 'Highlight bakes to TextBkgnd so Draw can paint it');
    expect(xml, contains('N="TextBkgnd" V="#FF00FF"'),
        reason: 'readCharIX skips Highlight; TextBkgnd is collected');
    expect(
      savedDoc.pages.first.shapes
          .firstWhere((s) => s.name == 'CJK')
          .richText
          .runs
          .single
          .charStyle
          .fontFamily,
      'Microsoft YaHei',
    );
    // RVNGSVGDrawingGenerator never emits span fo:background-color (vsd2xhtml
    // tspans are fill-only). vsd2raw still records the property Draw uses.
    _expectVsd2rawCollected(saved, <String>[
      'fo:background-color: #ff00ff',
      'style:font-name: Microsoft YaHei',
    ]);

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    final after = oracle.svgPages(saved)?.join() ?? '';
    expect(after, isNotEmpty);
    expect(
      after.contains('linearGradient') || after.contains('radialGradient'),
      isTrue,
      reason: 'libvisio must paint classic / rewritten gradients',
    );
    expect(RegExp(r'\nQ').hasMatch(after), isTrue,
        reason: 'libvisio must collect baked Rounding corners');
    expect(
      after.contains('stroke-dasharray') || after.contains('draw:stroke'),
      isTrue,
    );
    expect(
      RegExp(r'fill-opacity(?:=|:)\s*"?0\.5').hasMatch(after),
      isTrue,
      reason: 'libvisio must paint LineColorTrans via baked FillForegndTrans',
    );
  });
}

String? _which(String name) {
  final result = Process.runSync('which', <String>[name]);
  if (result.exitCode != 0) return null;
  final path = (result.stdout as String).trim();
  return path.isEmpty ? null : path;
}

void _expectVsd2rawCollected(Uint8List saved, List<String> snippets) {
  final vsd2raw = _which('vsd2raw');
  if (vsd2raw == null) return;
  final tmp = File(
    '${Directory.systemTemp.path}/vsdx_libvisio_collected.vsdx',
  );
  tmp.writeAsBytesSync(saved);
  final raw = Process.runSync(vsd2raw, <String>[tmp.path]);
  expect(raw.exitCode, 0, reason: 'vsd2raw stderr: ${raw.stderr}');
  final out = raw.stdout.toString();
  for (final snippet in snippets) {
    expect(
      out,
      contains(snippet),
      reason: 'libvisio must collect $snippet for Draw',
    );
  }
}
