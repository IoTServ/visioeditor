import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:vsdx/src/parser/style_parser.dart';
import 'package:vsdx/vsdx.dart';
import 'package:xml/xml.dart';

void main() {
  test('libvisio hatch map covers every FillPattern 2-24', () {
    for (var pattern = 2; pattern <= 24; pattern++) {
      expect(libvisioHatchSpec(pattern), isNotNull, reason: 'pattern $pattern');
    }
    expect(libvisioHatchSpec(1), isNull);
    expect(libvisioHatchSpec(25), isNull);

    expect(libvisioHatchSpec(2)!.angleDegrees, 45);
    expect(libvisioHatchSpec(3)!.style, VsdxHatchStyle.double);
    expect(libvisioHatchSpec(4)!.angleDegrees, 45);
    expect(libvisioHatchSpec(7)!.angleDegrees, 90);
    expect(libvisioHatchSpec(8)!.style, VsdxHatchStyle.triple);
    expect(libvisioHatchSpec(8)!.distanceInches, 0.05);
    expect(libvisioHatchSpec(23)!.style, VsdxHatchStyle.double);
  });

  test('sampleVisioHatchRgba matches horizontal FillPattern 6', () {
    final spec = libvisioHatchSpec(6)!;
    const fg = (r: 255, g: 0, b: 0, a: 255);
    const bg = (r: 0, g: 0, b: 255, a: 255);
    final onLine = sampleVisioHatchRgba(
      spec: spec,
      x: 0.2,
      y: 0.05,
      foreground: fg,
      background: bg,
    );
    final inGap = sampleVisioHatchRgba(
      spec: spec,
      x: 0.2,
      y: 0.0,
      foreground: fg,
      background: bg,
    );
    expect(onLine.r, greaterThan(onLine.b + 80));
    expect(inGap.b, greaterThan(inGap.r + 80));
  });

  test('VSDX classic gradient pattern is materialised without stop section',
      () {
    final shape = XmlDocument.parse(
      '<Shape>'
      '<Cell N="FillForegnd" V="#f4f9ff"/>'
      '<Cell N="FillBkgnd" V="#dff4d5"/>'
      '<Cell N="FillPattern" V="40"/>'
      '<Cell N="FillGradientEnabled" V="0"/>'
      '</Shape>',
    ).rootElement;
    final fill = const StyleParser().parseFill(shape);
    expect(fill.pattern, 40);
    expect(fill.gradient, isNotNull);
    expect(fill.gradient!.type, VsdxGradientType.radial);
    expect(fill.gradient!.dir, 3);
    expect(fill.gradient!.stops.first.color, const VsdxColor(0xFFF4F9FF));
    expect(fill.gradient!.stops.last.color, const VsdxColor(0xFFDFF4D5));
  });

  test('paintGradient materialises classic FillPattern 25–40 without parse',
      () {
    const fill = VsdxFill(
      foreground: VsdxColor(0xFFFF0000),
      background: VsdxColor(0xFF0000FF),
      pattern: 40,
    );
    expect(fill.hasGradient, isFalse);
    expect(fill.paintGradient, isNotNull);
    expect(fill.paintGradient!.type, VsdxGradientType.radial);
    expect(fill.paintGradient!.dir, 3);

    final page = const DocumentParser()
        .parse(const VsdxWriter().emptyDocument())
        .pages
        .first;
    final svg = VsdxToSvgSerializer().serializePage(
      page.addShape(
        VsdxShapeFactory.rectangle(
          id: page.nextFreeShapeId(),
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 2,
          fill: fill,
        ),
      ),
    );
    expect(svg, contains('radialGradient'));
  });

  test('FillGradient with FillPattern=1 maps to a classic id libvisio paints',
      () {
    for (var pattern = 25; pattern <= 40; pattern++) {
      final classic = withLibvisioClassicGradient(
        VsdxFill(
          foreground: const VsdxColor(0xFFFF0000),
          background: const VsdxColor(0xFF0000FF),
          pattern: pattern,
        ),
      );
      final modern = classic.copyWith(pattern: 1);
      expect(
        fillPatternForLibvisioWrite(modern),
        pattern,
        reason: 'FillPattern $pattern',
      );
    }
    expect(fillPatternForLibvisioWrite(const VsdxFill(pattern: 0)), 0);
    expect(
      fillPatternForLibvisioWrite(
        const VsdxFill(
          pattern: 0,
          gradient: VsdxGradient(
            stops: [
              VsdxGradientStop(position: 0, color: VsdxColor(0xFF8DC0FF)),
              VsdxGradientStop(position: 1, color: VsdxColor(0xFF467DFE)),
            ],
          ),
        ),
      ),
      inInclusiveRange(25, 40),
      reason: 'omitted FillPattern still maps FillGradient to classic 25–40',
    );
    expect(fillPatternForLibvisioWrite(const VsdxFill(pattern: 2)), 2);
    expect(
      fillPatternForLibvisioWrite(const VsdxFill(pattern: 41)),
      1,
      reason: 'ids above 40 become solid foreground, not Draw\'s bg fallback',
    );
  });

  test('FillPattern=0 FillGradient still paints and writes classic ids', () {
    const fill = VsdxFill(
      pattern: 0,
      gradient: VsdxGradient(
        angleRad: 3.92699,
        stops: [
          VsdxGradientStop(
            position: 0,
            color: VsdxColor(0xFF8DC0FF),
            transparency: 1,
          ),
          VsdxGradientStop(position: 0.2, color: VsdxColor(0xFFACCFFF)),
          VsdxGradientStop(position: 1, color: VsdxColor(0xFF467DFE)),
        ],
      ),
    );
    expect(fill.hasFill, isTrue);
    expect(fill.paintGradient, isNotNull);
    final write = fillForLibvisioWrite(fill);
    expect(write.pattern, inInclusiveRange(25, 40));
    expect(write.foreground, const VsdxColor(0xFFACCFFF),
        reason: 'skip the fully-transparent first stop for FillForegnd');
    expect(write.background, const VsdxColor(0xFF467DFE));

    final page = const DocumentParser()
        .parse(const VsdxWriter().emptyDocument())
        .pages
        .first;
    final svg = VsdxToSvgSerializer().serializePage(
      page.addShape(
        VsdxShapeFactory.rectangle(
          id: 1,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
          fill: fill,
        ),
      ),
    );
    expect(svg, contains('linearGradient'));
    expect(svg, contains('url(#grad-'));
  });

  test(
      'axial FillGradient writes FillPattern 26 with the centre as FillForegnd',
      () {
    const mag = VsdxColor(0xFFFF00FF);
    const fill = VsdxFill(
      pattern: 1,
      gradient: VsdxGradient(
        stops: [
          VsdxGradientStop(position: 0, color: VsdxColor.white),
          VsdxGradientStop(position: 0.5, color: mag),
          VsdxGradientStop(position: 1, color: VsdxColor.white),
        ],
      ),
    );
    expect(libvisioGradientIsAxialWash(fill.gradient), isTrue);
    expect(fillPatternForLibvisioWrite(fill), 26);
    final write = fillForLibvisioWrite(fill);
    expect(write.pattern, 26);
    expect(write.foreground, mag,
        reason: 'ODF axial start-color is the centre, not the first stop');
    expect(write.background, VsdxColor.white);
    expect(
        shapeNeedsLibvisioGeometrySoftEdgesBake(
          VsdxShapeFactory.rectangle(
            id: 1,
            pinX: 2,
            pinY: 2,
            width: 4,
            height: 1,
            fill: fill,
            line: const VsdxLine(pattern: 0),
          ),
        ),
        isFalse);

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: 1,
          pinX: 4.25,
          pinY: 5.5,
          width: 4,
          height: 1,
          fill: fill,
          line: const VsdxLine(pattern: 0),
        ),
      ),
    );
    final after = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(1)!;
    expect(after.fill.pattern, 26);
    expect(after.fill.foreground, mag);
    expect(after.fill.background, VsdxColor.white);
  });

  test('axial LineGradient ribbon writes FillPattern 26 with the centre colour',
      () {
    const mag = VsdxColor(0xFFFF00FF);
    const wash = VsdxGradient(
      stops: [
        VsdxGradientStop(position: 0, color: VsdxColor.white),
        VsdxGradientStop(position: 0.5, color: mag),
        VsdxGradientStop(position: 1, color: VsdxColor.white),
      ],
    );
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4.25,
      pinY: 5.5,
      width: 4,
      height: 1,
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(
        pattern: 1,
        weightInches: 0.18,
        gradient: wash,
      ),
    );
    expect(libvisioGradientIsAxialWash(shape.line.gradient), isTrue);
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(shape), isFalse);
    expect(shapeNeedsLibvisioStrokeRibbon(shape), isTrue);
    final write = libvisioShapeWrite(shape);
    expect(write.fill.pattern, 26);
    expect(write.fill.foreground, mag,
        reason: 'ODF axial start-color is the centre, not the first stop');
    expect(write.fill.background, VsdxColor.white);
    expect(write.line.pattern, 0);

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final after = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(1)!;
    expect(after.fill.pattern, 26);
    expect(after.fill.foreground, mag);
    expect(after.fill.background, VsdxColor.white);
    expect(after.line.pattern, 0);
  });

  test('three-stop linear whose ends differ bakes instead of FillPattern 26',
      () {
    const fill = VsdxFill(
      pattern: 1,
      gradient: VsdxGradient(
        stops: [
          VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
          VsdxGradientStop(position: 0.5, color: VsdxColor(0xFFFF0000)),
          VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
        ],
      ),
    );
    expect(libvisioGradientIsAxialWash(fill.gradient), isFalse);
    expect(
      shapeNeedsLibvisioGeometrySoftEdgesBake(
        VsdxShapeFactory.rectangle(
          id: 1,
          pinX: 2,
          pinY: 2,
          width: 4,
          height: 1,
          fill: fill,
          line: const VsdxLine(pattern: 0),
        ),
      ),
      isTrue,
    );
  });

  test('diagonal axial FillGradient bakes a PNG for LibreOffice', () {
    const mag = VsdxColor(0xFFFF00FF);
    const fill = VsdxFill(
      pattern: 1,
      gradient: VsdxGradient(
        angleRad: math.pi / 4,
        stops: [
          VsdxGradientStop(position: 0, color: VsdxColor.white),
          VsdxGradientStop(position: 0.5, color: mag),
          VsdxGradientStop(position: 1, color: VsdxColor.white),
        ],
      ),
    );
    expect(libvisioGradientIsAxialWash(fill.gradient), isTrue);
    expect(libvisioGradientAngleFitsClassic(fill.gradient), isFalse,
        reason: 'ODF axial is only draw:angle 0 / 90');
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4.25,
      pinY: 5.5,
      width: 2.4,
      height: 2.4,
      fill: fill,
      line: const VsdxLine(pattern: 0),
    );
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(shape), isTrue);

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    expect(baked.pages.first.findShapeById(1)!.fill.hasFill, isFalse);
    expect(
      baked.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
      hasLength(1),
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioSoftEdgesPlate),
      hasLength(1),
      reason: 'a second save must not stack another off-axis axial plate',
    );
  });

  test('vertical and 180° axial FillGradient stay FillPattern 29 / 26', () {
    const mag = VsdxColor(0xFFFF00FF);
    const stops = <VsdxGradientStop>[
      VsdxGradientStop(position: 0, color: VsdxColor.white),
      VsdxGradientStop(position: 0.5, color: mag),
      VsdxGradientStop(position: 1, color: VsdxColor.white),
    ];
    final vertical = VsdxFill(
      pattern: 1,
      gradient: VsdxGradient(angleRad: math.pi / 2, stops: stops),
    );
    expect(libvisioGradientAngleFitsClassic(vertical.gradient), isTrue);
    expect(fillPatternForLibvisioWrite(vertical), 29);
    expect(
      shapeNeedsLibvisioGeometrySoftEdgesBake(
        VsdxShapeFactory.rectangle(
          id: 1,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 2,
          fill: vertical,
          line: const VsdxLine(pattern: 0),
        ),
      ),
      isFalse,
    );

    final flipped = VsdxFill(
      pattern: 1,
      gradient: VsdxGradient(angleRad: math.pi, stops: stops),
    );
    expect(libvisioGradientAngleFitsClassic(flipped.gradient), isTrue,
        reason: 'axial 180° is the same wash as 0°');
    expect(fillPatternForLibvisioWrite(flipped), 26);
  });

  test('off-cardinal two-stop FillGradient bakes; 45° stays FillPattern 34',
      () {
    const mag = VsdxColor(0xFFFF00FF);
    const diagonal = VsdxFill(
      pattern: 1,
      gradient: VsdxGradient(
        angleRad: math.pi / 4,
        stops: [
          VsdxGradientStop(position: 0, color: mag),
          VsdxGradientStop(position: 1, color: VsdxColor.white),
        ],
      ),
    );
    expect(libvisioGradientAngleFitsClassic(diagonal.gradient), isTrue);
    expect(fillPatternForLibvisioWrite(diagonal), 34);
    expect(
      shapeNeedsLibvisioGeometrySoftEdgesBake(
        VsdxShapeFactory.rectangle(
          id: 1,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 2,
          fill: diagonal,
          line: const VsdxLine(pattern: 0),
        ),
      ),
      isFalse,
    );

    const tilted = VsdxFill(
      pattern: 1,
      gradient: VsdxGradient(
        angleRad: 15 * math.pi / 180,
        stops: [
          VsdxGradientStop(position: 0, color: mag),
          VsdxGradientStop(position: 1, color: VsdxColor.white),
        ],
      ),
    );
    expect(libvisioGradientAngleFitsClassic(tilted.gradient), isFalse);
    expect(
      shapeNeedsLibvisioGeometrySoftEdgesBake(
        VsdxShapeFactory.rectangle(
          id: 1,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 2,
          fill: tilted,
          line: const VsdxLine(pattern: 0),
        ),
      ),
      isTrue,
    );
  });

  test('diagonal axial LineGradient bakes a PNG for LibreOffice', () {
    const mag = VsdxColor(0xFFFF00FF);
    const wash = VsdxGradient(
      angleRad: math.pi / 4,
      stops: [
        VsdxGradientStop(position: 0, color: VsdxColor.white),
        VsdxGradientStop(position: 0.5, color: mag),
        VsdxGradientStop(position: 1, color: VsdxColor.white),
      ],
    );
    final shape = VsdxShape(
      id: 1,
      name: 'LineAxial45',
      pinX: 4.25,
      pinY: 5.5,
      width: 4,
      height: 0.4,
      fill: const VsdxFill(pattern: 0),
      geometries: const <VsdxGeometry>[
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[MoveTo(0, 0.2), LineTo(4, 0.2)],
        ),
      ],
      line: const VsdxLine(
        pattern: 1,
        weightInches: 0.18,
        gradient: wash,
      ),
    );
    expect(libvisioGradientIsAxialWash(shape.line.gradient), isTrue);
    expect(libvisioGradientAngleFitsClassic(shape.line.gradient), isFalse);
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(shape), isTrue);

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    expect(baked.pages.first.findShapeById(1)!.line.pattern, 0);
    expect(baked.pages.first.findShapeById(1)!.line.hasGradient, isFalse);
    expect(
      baked.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
      hasLength(1),
    );
  });

  test('inset two-stop FillGradient bakes; 0→1 stays FillPattern 25–34', () {
    const mag = VsdxColor(0xFFFF00FF);
    const full = VsdxFill(
      pattern: 1,
      gradient: VsdxGradient(
        stops: [
          VsdxGradientStop(position: 0, color: mag),
          VsdxGradientStop(position: 1, color: VsdxColor.white),
        ],
      ),
    );
    expect(libvisioGradientStopsFitClassic(full.gradient), isTrue);
    expect(
      shapeNeedsLibvisioGeometrySoftEdgesBake(
        VsdxShapeFactory.rectangle(
          id: 1,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 2,
          fill: full,
          line: const VsdxLine(pattern: 0),
        ),
      ),
      isFalse,
    );

    const inset = VsdxFill(
      pattern: 1,
      gradient: VsdxGradient(
        stops: [
          VsdxGradientStop(position: 0.25, color: mag),
          VsdxGradientStop(position: 0.75, color: VsdxColor.white),
        ],
      ),
    );
    expect(libvisioGradientStopsFitClassic(inset.gradient), isFalse);
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 4.8,
      height: 1.2,
      fill: inset,
      line: const VsdxLine(pattern: 0),
    );
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(shape), isTrue);

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    expect(baked.pages.first.findShapeById(1)!.fill.pattern, 0);
    expect(
      baked.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
      hasLength(1),
    );
    final again = documentForLibvisioWrite(baked);
    expect(
      again.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
      hasLength(1),
      reason: 'a second save must not stack another inset-stop plate',
    );
  });

  test('off-centre axial FillGradient bakes; peak at 0.5 stays FillPattern 26',
      () {
    const mag = VsdxColor(0xFFFF00FF);
    const centred = VsdxFill(
      pattern: 1,
      gradient: VsdxGradient(
        stops: [
          VsdxGradientStop(position: 0, color: VsdxColor.white),
          VsdxGradientStop(position: 0.5, color: mag),
          VsdxGradientStop(position: 1, color: VsdxColor.white),
        ],
      ),
    );
    expect(libvisioGradientIsAxialWash(centred.gradient), isTrue);
    expect(libvisioGradientStopsFitClassic(centred.gradient), isTrue);
    expect(fillPatternForLibvisioWrite(centred), 26);
    expect(
      shapeNeedsLibvisioGeometrySoftEdgesBake(
        VsdxShapeFactory.rectangle(
          id: 1,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 2,
          fill: centred,
          line: const VsdxLine(pattern: 0),
        ),
      ),
      isFalse,
    );

    const shifted = VsdxFill(
      pattern: 1,
      gradient: VsdxGradient(
        stops: [
          VsdxGradientStop(position: 0, color: VsdxColor.white),
          VsdxGradientStop(position: 0.2, color: mag),
          VsdxGradientStop(position: 1, color: VsdxColor.white),
        ],
      ),
    );
    expect(libvisioGradientIsAxialWash(shifted.gradient), isTrue);
    expect(libvisioGradientStopsFitClassic(shifted.gradient), isFalse);
    expect(
      shapeNeedsLibvisioGeometrySoftEdgesBake(
        VsdxShapeFactory.rectangle(
          id: 1,
          pinX: 2,
          pinY: 2,
          width: 4.8,
          height: 1.2,
          fill: shifted,
          line: const VsdxLine(pattern: 0),
        ),
      ),
      isTrue,
    );
  });

  test('inset two-stop LineGradient bakes a PNG for LibreOffice', () {
    const mag = VsdxColor(0xFFFF00FF);
    const wash = VsdxGradient(
      stops: [
        VsdxGradientStop(position: 0.25, color: mag),
        VsdxGradientStop(position: 0.75, color: VsdxColor.white),
      ],
    );
    final shape = VsdxShape(
      id: 1,
      name: 'LineInset',
      pinX: 4.25,
      pinY: 5.5,
      width: 4,
      height: 0.4,
      fill: const VsdxFill(pattern: 0),
      geometries: const <VsdxGeometry>[
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[MoveTo(0, 0.2), LineTo(4, 0.2)],
        ),
      ],
      line: const VsdxLine(
        pattern: 1,
        weightInches: 0.18,
        gradient: wash,
      ),
    );
    expect(libvisioGradientStopsFitClassic(shape.line.gradient), isFalse);
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(shape), isTrue);

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    expect(baked.pages.first.findShapeById(1)!.line.pattern, 0);
    expect(baked.pages.first.findShapeById(1)!.line.hasGradient, isFalse);
    expect(
      baked.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
      hasLength(1),
    );
  });

  test('geometry-less FillPattern=1 writes 0 so Edraw cannot fill the text box',
      () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 1,
      pinY: 1,
      width: 1,
      height: 0.3,
      fill: const VsdxFill(
        pattern: 1,
        foreground: VsdxColor(0xFFFFFFFF),
      ),
    ).copyWith(geometries: const <VsdxGeometry>[]);
    expect(shape.fill.pattern, 1);
    expect(libvisioShapeWrite(shape).fill.pattern, 0);
  });
}
