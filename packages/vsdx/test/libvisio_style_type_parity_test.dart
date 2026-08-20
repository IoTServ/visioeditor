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
/// Begin/EndArrow as Geometry so Draw does not hang a marker on
/// every open rail, and so BeginArrowSize (not a token) still has a size.
/// A plain stroke whose size disagrees with `_lineProperties`' line-weight
/// formula bakes the same way. Open arrow ids become filled ribbons of
/// the original weight. Classic FillPattern 25–40 also paint here even when
/// the model has no stop section yet. Unknown LinePattern ids snap to the
/// built-in 2–23 table `_lineProperties` actually dashes. `LineCap` 0/1/2 is a
/// token libvisio *does* collect. Character Highlight is skipped by
/// `readCharIX` but a uniform marker with no authored TextBkgnd is written
/// there — `VSDContentCollector` paints it as span `fo:background-color`
/// and Draw shows the plate. `RVNGSVGDrawingGenerator` drops that property,
/// so the oracle SVG is the wrong place to look; `vsd2raw` still has it.
/// `TextBkgndTrans` and layer `ColorTrans` have no VSDX collector case, so
/// a save premultiplies those into RGB toward white. Overline still paints
/// here even though `readCharIX` skips it; a save inserts U+0305 combining
/// marks so Draw paints the line too. Glow* is not a token: unfilled
/// strokes bake a FillForegndTrans ribbon and filled NoLine shapes bake a
/// LineWeight halo. Character ColorTrans, filled-shape
/// LineColorTrans, and ShdwForegndTrans cannot carry alpha through
/// `xmlStringToColour`, so a save premultiplies those into RGB toward white
/// and writes Trans=0 (theme-bound RGB-less cells keep THEMEVAL).
/// `AsianFont` / `ComplexScriptFont` / `ComplexScriptSize` are not tokens,
/// so an Asian-only (Hangul/Kana/Han) or complex-script-only run whose
/// Visio `Font` is Arial is rewritten to the face and size Draw will
/// actually load. Mixed Latin+CJK runs keep `Font`. Character `Letterspace`
/// is not a token; canvas / SVG already fold FontScale into tracking at
/// 0.55×Size, so a save adds Letterspace into FontScale and writes
/// Letterspace 0. Picture `SoftEdgesSize` is not a token; an uncropped
/// 2-D Foreign bitmap bakes the same SourceAlpha feather canvas / SVG
/// use into PNG alpha, then SoftEdgesSize is written 0. Marker ids whose
/// `_linePropertiesMarkerPath` is still a TODO stub bake as Geometry so
/// Draw does not reuse a sibling silhouette. Unknown
/// `FillPattern` ids above 40 snap to solid `1`.
/// Explicit round joins on a square/flat cap bake RelQuadBezTo —
/// `_lineProperties` would otherwise emit miter from LineCap. Bevel joins
/// bake LineTo chamfers; arcs joins bake the same fillets as round
/// (canvas `canvasStrokeJoin`).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as raster;
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
      line: arrowed().copyWith(
        weightInches: 0.01,
        beginArrowSizeInches: 0.125,
        endArrowSizeInches: 0.125,
      ),
    );
    expect(shapeNeedsLibvisioArrowedStrokeBake(plain), isFalse);
    expect(libvisioShapeWrite(plain).line.beginArrow, 4);

    for (final scaledId in <int>[10, 11, 14, 22]) {
      final scaled = VsdxShapeFactory.line(
        id: 40 + scaledId,
        ax: 0,
        ay: 0,
        bx: 3,
        by: 0,
        line: VsdxLine(
          color: VsdxColor.black,
          weightInches: 0.01,
          beginArrow: scaledId,
          endArrow: scaledId,
          beginArrowSizeInches: 0.125,
          endArrowSizeInches: 0.125,
        ),
      );
      expect(
        shapeNeedsLibvisioArrowedStrokeBake(scaled),
        isFalse,
        reason: 'default bucket 2 must keep native marker $scaledId',
      );
    }

    final oversized = VsdxShapeFactory.line(
      id: 5,
      ax: 0,
      ay: 0,
      bx: 3,
      by: 0,
      line: const VsdxLine(
        color: VsdxColor.black,
        weightInches: 0.01,
        beginArrow: 4,
        endArrow: 4,
        beginArrowSizeInches: 0.35,
        endArrowSizeInches: 0.35,
      ),
    );
    expect(shapeNeedsLibvisioArrowedStrokeBake(oversized), isTrue);
    final oversizedWrite = libvisioShapeWrite(oversized);
    expect(oversizedWrite.line.beginArrow, 0);
    expect(oversizedWrite.line.endArrow, 0);
    expect(oversizedWrite.geometries.any((g) => !g.noFill), isTrue);

    VsdxShape filledCompound(int type) => VsdxShapeFactory.rectangle(
          id: type,
          pinX: 1,
          pinY: 1,
          width: 1,
          height: 0.6,
          fill: const VsdxFill(foreground: VsdxColor(0xFFCCCCCC), pattern: 1),
          line: VsdxLine(
            color: const VsdxColor(0xFF000000),
            weightInches: 0.08,
            compoundType: type,
          ),
        );
    for (final type in <int>[3, 4]) {
      final baked = bakeCompoundTypeForLibvisio(filledCompound(type));
      expect(baked, isNotNull, reason: 'CompoundType $type must bake rails');
      expect(baked!.line.compoundType, 0);
      expect(baked.fill, isNull, reason: 'filled 2-D keeps stroked rails');
      expect(
        baked.geometries.where((g) => !g.noLine).length,
        type == 4 ? 3 : 2,
      );
    }

    VsdxShape unfilledCompound1d(int type) => VsdxShapeFactory.line(
          id: 20 + type,
          ax: 0,
          ay: 0,
          bx: 3,
          by: 0,
          line: VsdxLine(
            color: const VsdxColor(0xFF000000),
            weightInches: 0.08,
            compoundType: type,
          ),
        );
    for (final type in <int>[3, 4]) {
      final baked = bakeCompoundTypeForLibvisio(unfilledCompound1d(type));
      expect(
        baked,
        isNotNull,
        reason: 'unfilled CompoundType $type must bake width-true ribbons',
      );
      expect(baked!.line.compoundType, 0);
      expect(baked.line.pattern, 0);
      expect(baked.fill, isNotNull);
      expect(baked.fill!.pattern, 1);
      expect(
        baked.geometries.where((g) => !g.noFill).length,
        type == 4 ? 3 : 2,
      );
      expect(baked.geometries.where((g) => !g.noLine), isEmpty);
    }

    // VSDContentCollector::_linePropertiesMarkerPath filled ids that used to
    // fall through to a generic triangle when compound/ribbon bakes arrows.
    for (final id in <int>[
      1,
      3,
      6,
      7,
      9,
      10,
      12,
      14,
      15,
      16,
      17,
      18,
      20,
      21,
      22,
      27,
      35,
      38,
      42,
    ]) {
      final arrows = bakeArrowGeometriesForLibvisio(
        VsdxShapeFactory.line(
          id: id,
          ax: 0,
          ay: 0,
          bx: 3,
          by: 0,
          line: VsdxLine(
            color: const VsdxColor(0xFF000000),
            weightInches: 0.08,
            compoundType: 1,
            beginArrow: id,
            beginArrowSizeInches: 0.25,
          ),
        ),
      );
      expect(arrows, isNotEmpty, reason: 'arrow id $id must bake a polygon');
    }
    expect(
      bakeArrowGeometriesForLibvisio(
        VsdxShapeFactory.line(
          id: 39,
          ax: 0,
          ay: 0,
          bx: 3,
          by: 0,
          line: const VsdxLine(
            color: VsdxColor.black,
            weightInches: 0.08,
            compoundType: 1,
            beginArrow: 39,
            beginArrowSizeInches: 0.25,
          ),
        ),
      ).length,
      2,
      reason: 'libvisio marker 39/40 is two triangles',
    );
  });

  test('Character Overline bakes combining U+0305 for LibreOffice', () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.4,
      height: 0.7,
      name: 'Over',
    ).copyWith(
      text: 'AB',
      richText: const VsdxRichText(
        runs: [
          VsdxTextRun(
            text: 'AB',
            charStyle: VsdxCharStyle(overline: true),
          ),
        ],
      ),
    );
    expect(shapeNeedsLibvisioOverlineBake(shape), isTrue);
    final baked = bakeOverlineShapeForLibvisioWrite(shape);
    expect(baked.richText.runs.single.charStyle.overline, isFalse);
    expect(
        baked.richText.runs.single.text, contains(kLibvisioCombiningOverline));
    expect(baked.text, contains(kLibvisioCombiningOverline));
  });

  test('Glow bakes a halo Draw can collect', () {
    final stroke = VsdxShapeFactory.line(
      id: 1,
      ax: 0,
      ay: 0,
      bx: 3,
      by: 0,
      line: const VsdxLine(
        color: VsdxColor(0xFF000000),
        weightInches: 0.04,
      ),
    ).copyWith(
      glow: const VsdxGlow(
        color: VsdxColor(0xFFFF00FF),
        sizeInches: 0.08,
        transparency: 0.5,
      ),
    );
    expect(shapeNeedsLibvisioGlowBake(stroke), isTrue);
    final strokeWrite = libvisioShapeWrite(stroke);
    expect(strokeWrite.fill.hasFill, isTrue);
    expect(strokeWrite.fill.foregroundTransparency, greaterThan(0));
    expect(strokeWrite.geometries.any((g) => !g.noFill), isTrue);
    expect(strokeWrite.line.hasLine, isTrue);
    expect(strokeWrite.line.weightInches, closeTo(0.04, 1e-9));
    expect(glowForLibvisioWrite(stroke).enabled, isFalse);

    final filled = VsdxShapeFactory.rectangle(
      id: 2,
      pinX: 1,
      pinY: 1,
      width: 1.5,
      height: 0.8,
      fill: const VsdxFill(foreground: VsdxColor(0xFFEEEEEE), pattern: 1),
      line: const VsdxLine(pattern: 0),
    ).copyWith(
      glow: const VsdxGlow(
        color: VsdxColor(0xFFFF00FF),
        sizeInches: 0.08,
        transparency: 0.5,
      ),
    );
    expect(shapeNeedsLibvisioGlowBake(filled), isTrue);
    final filledWrite = libvisioShapeWrite(filled);
    expect(filledWrite.line.hasLine, isTrue);
    expect(filledWrite.line.weightInches, closeTo(0.16, 1e-9));
    expect(filledWrite.fill.pattern, 1);

    final outlined = VsdxShapeFactory.rectangle(
      id: 3,
      pinX: 1,
      pinY: 1,
      width: 1.5,
      height: 0.8,
    ).copyWith(
      glow: const VsdxGlow(
        color: VsdxColor(0xFFFF00FF),
        sizeInches: 0.08,
      ),
    );
    expect(shapeNeedsLibvisioGlowBake(outlined), isFalse,
        reason: 'a painted outline must not be stolen for the halo');
  });

  test('incomplete libvisio marker ids bake as Geometry for LibreOffice', () {
    for (final id in <int>[26, 31, 32, 33, 34, 36, 37, 38, 40, 43, 44, 45]) {
      expect(libvisioMarkerPathIsIncomplete(id), isTrue, reason: 'id $id');
      final shape = VsdxShapeFactory.line(
        id: id,
        ax: 0,
        ay: 0,
        bx: 3,
        by: 0,
        line: VsdxLine(
          color: const VsdxColor(0xFF000000),
          weightInches: 0.04,
          endArrow: id,
        ),
      );
      expect(shapeNeedsLibvisioArrowedStrokeBake(shape), isTrue,
          reason: 'TODO stub $id must bake at the default size');
      expect(bakeArrowGeometriesForLibvisio(shape), isNotEmpty,
          reason: 'TODO stub $id must emit a polygon');
    }
    expect(libvisioMarkerPathIsIncomplete(4), isFalse);
    expect(libvisioMarkerPathIsIncomplete(25), isFalse);
    expect(libvisioMarkerPathIsIncomplete(35), isFalse);
    expect(libvisioMarkerPathIsIncomplete(39), isFalse);

    var doc = parser.parse(writer.emptyDocument());
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.line(
          id: 1,
          ax: 1,
          ay: 1,
          bx: 3,
          by: 1,
          line: const VsdxLine(
            color: VsdxColor.black,
            weightInches: 0.04,
            endArrow: 40,
          ),
        ),
      ),
    );
    final after = parser
        .parse(
          writer.write(originalBytes: writer.emptyDocument(), edited: doc),
        )
        .pages
        .first
        .findShapeById(1)!;
    expect(after.line.endArrow, 0);
    expect(after.geometries.any((g) => !g.noFill), isTrue);
  });

  test('picture SoftEdges bakes into PNG for LibreOffice', () {
    final rasterImage = raster.Image(width: 32, height: 32);
    for (var y = 0; y < 32; y++) {
      for (var x = 0; x < 32; x++) {
        rasterImage.setPixelRgba(x, y, 255, 0, 0, 255);
      }
    }
    final bytes = Uint8List.fromList(raster.encodePng(rasterImage));
    const part = '/visio/media/soft.png';
    final source =
        VsdxImage(partName: part, bytes: bytes, mimeType: 'image/png');
    final pic = VsdxShapeFactory.picture(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.2,
      height: 0.8,
      imagePartName: part,
    ).copyWith(
      line: const VsdxLine(pattern: 0, softEdgesInches: 0.08),
    );
    expect(imageSoftEdgesInchesForLibvisioWrite(pic), closeTo(0.08, 1e-12));
    expect(
      visioImageAdjustmentsNeedBake(
        transparency: 0,
        blur: 0,
        brightness: 0.5,
        contrast: 0.5,
        softEdgesInches: 0.08,
      ),
      isTrue,
    );
    final baked = bakeVisioImageAdjustmentsPng(
      image: source,
      transparency: 0,
      blur: 0,
      brightness: 0.5,
      contrast: 0.5,
      displayWidthInches: 1.2,
      softEdgesInches: 0.08,
    );
    expect(baked, isNotNull);
    final decoded = raster.decodePng(baked!);
    expect(decoded, isNotNull);
    expect(decoded!.getPixel(0, 0).a, lessThan(decoded.getPixel(16, 16).a));
    expect(decoded.getPixel(16, 16).a, greaterThan(200));

    final cropped = pic.copyWith(imgOffsetXInches: 0.1);
    expect(imageSoftEdgesInchesForLibvisioWrite(cropped), 0);

    var doc = parser.parse(writer.emptyDocument());
    doc = doc
        .copyWith(images: doc.images.withImage(source))
        .replacePage(0, doc.pages.first.addShape(pic));
    final saved = writer.write(
      originalBytes: writer.emptyDocument(),
      edited: doc,
    );
    final after = parser.parse(saved).pages.first.findShapeById(1)!;
    expect(after.line.softEdgesInches, closeTo(0, 1e-9));
    expect(after.imagePartName, isNot(part));
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

  test('TextBkgndTrans premultiplies into TextBkgnd for LibreOffice', () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.4,
      height: 0.7,
      name: 'Plate',
    ).copyWith(
      text: 'Hi',
      richText: const VsdxRichText(
        textBlock: VsdxTextBlock(
          backgroundColor: VsdxColor(0xFF0000FF),
          backgroundTransparency: 0.5,
        ),
        runs: [VsdxTextRun(text: 'Hi')],
      ),
    );
    expect(shapeNeedsLibvisioTextBlockBake(shape), isTrue);
    final baked = textBlockForLibvisioWrite(shape);
    expect(baked.backgroundTransparency, 0);
    expect(
      baked.backgroundColor,
      colourForLibvisioAlpha(const VsdxColor(0xFF0000FF), 0.5),
    );
  });

  test('layer ColorTrans premultiplies into Color for LibreOffice', () {
    const layer = VsdxLayer(
      id: 0,
      name: 'Tint',
      color: VsdxColor(0xFF0000FF),
      colorTrans: 0.5,
    );
    final baked = layerForLibvisioWrite(layer);
    expect(baked.colorTrans, 0);
    expect(
      baked.color,
      colourForLibvisioAlpha(const VsdxColor(0xFF0000FF), 0.5),
    );
    expect(
      layerForLibvisioWrite(
        const VsdxLayer(id: 1, name: 'NoColor', colorTrans: 0.5),
      ).colorTrans,
      0.5,
      reason: 'ColorTrans without Color stays; Draw never tints those rows',
    );
  });

  test('Asian/complex Character Font and Size bake for LibreOffice', () {
    VsdxShape box(String name, String text, VsdxCharStyle style) =>
        VsdxShapeFactory.rectangle(
          id: 1,
          pinX: 2,
          pinY: 2,
          width: 1.4,
          height: 0.7,
          name: name,
        ).copyWith(
          text: text,
          richText: VsdxRichText(
            runs: [
              VsdxTextRun(text: text, charStyle: style),
            ],
          ),
        );

    const latinUi = VsdxCharStyle(
      fontFamily: 'Arial',
      asianFont: 'Microsoft YaHei',
      complexScriptFont: 'Times New Roman',
      complexScriptSizeInches: 18 / 72,
    );
    final han = box('CJK', '你好', latinUi);
    expect(shapeNeedsLibvisioFontBake(han), isTrue);
    expect(fontFamilyForLibvisioWrite(latinUi, '你好'), 'Microsoft YaHei');
    final hangul = box('Hangul', '안녕', latinUi);
    expect(shapeNeedsLibvisioFontBake(hangul), isTrue);
    expect(fontFamilyForLibvisioWrite(latinUi, '안녕'), 'Microsoft YaHei');
    final kana = box('Kana', 'こんにちは', latinUi);
    expect(shapeNeedsLibvisioFontBake(kana), isTrue);
    expect(fontFamilyForLibvisioWrite(latinUi, 'こんにちは'), 'Microsoft YaHei');
    final arabic = box('Arabic', 'سلام', latinUi);
    expect(shapeNeedsLibvisioFontBake(arabic), isTrue);
    expect(fontFamilyForLibvisioWrite(latinUi, 'سلام'), 'Times New Roman');
    expect(fontSizeForLibvisioWrite(latinUi, 'سلام'), closeTo(18 / 72, 1e-12));
    expect(fontSizeForLibvisioWrite(latinUi, '你好'), closeTo(12 / 72, 1e-12));
    const spacedStyle = VsdxCharStyle(letterSpacingInches: 0.02);
    final spaced = box('Letterspace', 'Hi', spacedStyle);
    expect(shapeNeedsLibvisioFontBake(spaced), isTrue);
    expect(letterSpacingForLibvisioWrite(spacedStyle, 'Hi'), 0);
    expect(
      fontScaleForLibvisioWrite(spacedStyle, 'Hi'),
      closeTo(
        1 + 0.02 / ((12 / 72) * kLibvisioMeanLatinAdvance),
        1e-12,
      ),
    );
    final latin = box('Hi', 'Hi', latinUi);
    expect(shapeNeedsLibvisioFontBake(latin), isFalse);
    expect(fontFamilyForLibvisioWrite(latinUi, 'Hi'), 'Arial');
    expect(fontFamilyForLibvisioWrite(latinUi, 'Hello世界'), 'Arial');
    expect(fillPatternForLibvisioWrite(const VsdxFill(pattern: 41)), 1);
    expect(
      roundingForLibvisioWrite(const VsdxLine(
        cap: LineCap.square,
        join: VsdxLineJoin.round,
        weightInches: 0.08,
      )),
      closeTo(0.04, 1e-12),
    );
    expect(
      roundingForLibvisioWrite(const VsdxLine(
        cap: LineCap.round,
        join: VsdxLineJoin.round,
        weightInches: 0.08,
      )),
      0,
    );
    expect(
      roundingForLibvisioWrite(const VsdxLine(
        cap: LineCap.square,
        join: VsdxLineJoin.bevel,
        weightInches: 0.08,
      )),
      closeTo(0.04, 1e-12),
    );
    expect(
      roundingForLibvisioWrite(const VsdxLine(
        cap: LineCap.square,
        join: VsdxLineJoin.arcs,
        weightInches: 0.08,
      )),
      closeTo(0.04, 1e-12),
    );
    expect(
      chamferForLibvisioWrite(const VsdxLine(
        cap: LineCap.square,
        join: VsdxLineJoin.bevel,
        weightInches: 0.08,
      )),
      isTrue,
    );
    expect(
      chamferForLibvisioWrite(const VsdxLine(
        cap: LineCap.square,
        join: VsdxLineJoin.round,
        weightInches: 0.08,
      )),
      isFalse,
    );
    expect(
      chamferForLibvisioWrite(const VsdxLine(
        cap: LineCap.round,
        join: VsdxLineJoin.bevel,
        weightInches: 0.08,
      )),
      isTrue,
    );
    expect(
      roundingForLibvisioWrite(const VsdxLine(
        cap: LineCap.round,
        join: VsdxLineJoin.bevel,
        weightInches: 0.08,
      )),
      closeTo(0.04, 1e-12),
    );
    expect(
      colourForLibvisioAlpha(VsdxColor.black, 0.4).value,
      0xFF666666,
    );
    expect(
      charTransparencyForLibvisioWrite(
        const VsdxCharStyle(transparency: 0.4),
      ),
      0,
    );
    expect(
      charColorForLibvisioWrite(
        const VsdxCharStyle(transparency: 0.4),
      )?.value,
      0xFF666666,
    );
    expect(
      shadowForLibvisioWrite(
        const VsdxShadow(
          color: VsdxColor(0xFF00AA00),
          transparency: 0.4,
        ),
      ).transparency,
      0,
    );
    expect(
      shadowForLibvisioWrite(
        const VsdxShadow(
          themeColorIndex: 0,
          transparency: 0.4,
        ),
      ).transparency,
      closeTo(0.4, 1e-12),
    );
    final fadedLatin = box(
      'Fade',
      'Hi',
      const VsdxCharStyle(transparency: 0.4),
    );
    expect(shapeNeedsLibvisioFontBake(fadedLatin), isTrue);
    expect(
      roundingForLibvisioWrite(const VsdxLine(
        cap: LineCap.square,
        join: VsdxLineJoin.bevel,
        roundingInches: 0.15,
        weightInches: 0.08,
      )),
      closeTo(0.15, 1e-12),
    );
    expect(
      chamferForLibvisioWrite(const VsdxLine(
        cap: LineCap.square,
        join: VsdxLineJoin.bevel,
        roundingInches: 0.15,
        weightInches: 0.08,
      )),
      isFalse,
    );
  });

  test('every FillPattern 2–40, LinePattern 2–23, and Bullet 1–7 paints', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    var nextId = page.nextFreeShapeId();

    for (var pattern = 2; pattern <= 40; pattern++) {
      page = page.addShape(
        VsdxShapeFactory.rectangle(
          id: nextId++,
          pinX: 2,
          pinY: 4,
          width: 1,
          height: 0.5,
          name: 'Fill$pattern',
          fill: VsdxFill(
            foreground: const VsdxColor(0xFFFF0000),
            background: const VsdxColor(0xFF0000FF),
            pattern: pattern,
          ),
          line: const VsdxLine(pattern: 0),
        ),
      );
    }
    for (var pattern = 2; pattern <= 23; pattern++) {
      page = page.addShape(
        VsdxShape(
          id: nextId++,
          name: 'Dash$pattern',
          pinX: 4,
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
          ),
        ),
      );
    }
    for (var bullet = 1; bullet <= 7; bullet++) {
      page = page.addShape(
        VsdxShapeFactory.rectangle(
          id: nextId++,
          pinX: 6,
          pinY: 4,
          width: 1.4,
          height: 0.4,
          name: 'Bullet$bullet',
          fill: const VsdxFill(foreground: VsdxColor(0xFFFFFFFF), pattern: 1),
          line: const VsdxLine(pattern: 0),
        ).copyWith(
          text: 'x',
          richText: VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'x',
                paraStyle: VsdxParaStyle(bullet: bullet),
              ),
            ],
          ),
        ),
      );
    }

    doc = doc.replacePage(0, page);
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(
      RegExp(r'<pattern\b').allMatches(svg).length,
      greaterThanOrEqualTo(23),
      reason: 'each hatch FillPattern 2–24 must emit a <pattern>',
    );
    expect(svg, contains('linearGradient'),
        reason: 'classic FillPattern 25–34 are linear');
    expect(svg, contains('radialGradient'),
        reason: 'classic FillPattern 35–40 are radial');
    expect(
      RegExp(r'stroke-dasharray="').allMatches(svg).length,
      greaterThanOrEqualTo(22),
      reason: 'each LinePattern 2–23 must dash',
    );
    for (var bullet = 1; bullet <= 7; bullet++) {
      expect(
        svg,
        contains(libvisioBulletGlyph(bullet)),
        reason: 'Bullet $bullet must paint the libvisio default glyph',
      );
    }

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(
      savedDoc.pages.first.shapes
          .where((s) => s.name.startsWith('Bullet'))
          .map((s) => s.richText.runs.single.paraStyle.bullet)
          .toList(),
      <int>[1, 2, 3, 4, 5, 6, 7],
      reason: 'Bullet 1–7 cells must round-trip for Draw to collect',
    );
    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    final afterPages = oracle.svgPages(saved);
    expect(afterPages, isNotNull);
    final after = afterPages!.join();
    expect(after, contains('svg:path'), reason: 'hatches and dashes collect');
    expect(
      RegExp(r'stroke-dasharray:').allMatches(after).length,
      greaterThanOrEqualTo(22),
      reason: 'libvisio must dash LinePattern 2–23',
    );
    // RVNGSVGDrawingGenerator drops list markers (and span fo:background-color).
    // vsd2raw still records the bullet-char Draw paints.
    _expectVsd2rawCollected(saved, const <String>['text:bullet-char']);
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
      VsdxShape(
        id: nextId++,
        name: 'RoundJoin',
        pinX: 8,
        pinY: 1.6,
        width: 1.4,
        height: 1.4,
        geometries: const <VsdxGeometry>[
          VsdxGeometry(
            noFill: true,
            commands: <VsdxPathCommand>[
              MoveTo(0, 0),
              LineTo(1.4, 0),
              LineTo(1.4, 1.4),
            ],
          ),
        ],
        line: const VsdxLine(
          color: VsdxColor.black,
          weightInches: 0.08,
          cap: LineCap.square,
          join: VsdxLineJoin.round,
        ),
      ),
    );
    built = built.addShape(
      VsdxShape(
        id: nextId++,
        name: 'BevelJoin',
        pinX: 8,
        pinY: 3.2,
        width: 1.4,
        height: 1.4,
        geometries: const <VsdxGeometry>[
          VsdxGeometry(
            noFill: true,
            commands: <VsdxPathCommand>[
              MoveTo(0, 0),
              LineTo(1.4, 0),
              LineTo(1.4, 1.4),
            ],
          ),
        ],
        line: const VsdxLine(
          color: VsdxColor.black,
          weightInches: 0.08,
          cap: LineCap.square,
          join: VsdxLineJoin.bevel,
        ),
      ),
    );
    built = built.addShape(
      VsdxShape(
        id: nextId++,
        name: 'BevelRoundCap',
        pinX: 8,
        pinY: 4.8,
        width: 1.4,
        height: 1.4,
        geometries: const <VsdxGeometry>[
          VsdxGeometry(
            noFill: true,
            commands: <VsdxPathCommand>[
              MoveTo(0, 0),
              LineTo(1.4, 0),
              LineTo(1.4, 1.4),
            ],
          ),
        ],
        line: const VsdxLine(
          color: VsdxColor.black,
          weightInches: 0.08,
          cap: LineCap.round,
          join: VsdxLineJoin.bevel,
        ),
      ),
    );
    built = built.addShape(
      VsdxShape(
        id: nextId++,
        name: 'ArcsJoin',
        pinX: 6.4,
        pinY: 1.6,
        width: 1.4,
        height: 1.4,
        geometries: const <VsdxGeometry>[
          VsdxGeometry(
            noFill: true,
            commands: <VsdxPathCommand>[
              MoveTo(0, 0),
              LineTo(1.4, 0),
              LineTo(1.4, 1.4),
            ],
          ),
        ],
        line: const VsdxLine(
          color: VsdxColor.black,
          weightInches: 0.08,
          cap: LineCap.square,
          join: VsdxLineJoin.arcs,
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
      VsdxShapeFactory.line(
        id: nextId++,
        ax: 5,
        ay: 0.6,
        bx: 8,
        by: 0.6,
        name: 'CompoundThinThick1D',
        line: const VsdxLine(
          color: VsdxColor.black,
          weightInches: 0.08,
          compoundType: 3,
        ),
      ),
    );
    built = built.addShape(
      VsdxShapeFactory.line(
        id: nextId++,
        ax: 1,
        ay: 0.3,
        bx: 4,
        by: 0.3,
        name: 'CompoundTriple1D',
        line: const VsdxLine(
          color: VsdxColor.black,
          weightInches: 0.08,
          compoundType: 4,
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
      box(
        'CompoundThinThick',
        const VsdxFill(foreground: VsdxColor(0xFFCCCCCC), pattern: 1),
        line: const VsdxLine(
          color: VsdxColor.black,
          weightInches: 0.08,
          compoundType: 3,
        ),
      ),
    );
    built = built.addShape(
      box(
        'CompoundTriple',
        const VsdxFill(foreground: VsdxColor(0xFFCCCCCC), pattern: 1),
        line: const VsdxLine(
          color: VsdxColor.black,
          weightInches: 0.08,
          compoundType: 4,
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
      VsdxShapeFactory.rectangle(
        id: nextId++,
        pinX: 5,
        pinY: 2.2,
        width: 2,
        height: 0.7,
        name: 'FilledLineTrans',
        fill: const VsdxFill(foreground: VsdxColor(0xFFFFFFFF), pattern: 1),
        line: const VsdxLine(
          color: VsdxColor.black,
          pattern: 1,
          weightInches: 0.04,
          transparency: 0.4,
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
    built = built.addShape(
      VsdxShapeFactory.rectangle(
        id: nextId++,
        pinX: 5,
        pinY: 3,
        width: 1.4,
        height: 0.7,
        name: 'Hangul',
        fill: const VsdxFill(foreground: VsdxColor(0xFFFFFFFF), pattern: 1),
        line: const VsdxLine(color: VsdxColor.black, pattern: 0),
      ).copyWith(
        text: '안녕',
        richText: const VsdxRichText(
          runs: [
            VsdxTextRun(
              text: '안녕',
              charStyle: VsdxCharStyle(
                fontFamily: 'Arial',
                asianFont: 'Microsoft YaHei',
              ),
            ),
          ],
        ),
      ),
    );
    built = built.addShape(
      VsdxShapeFactory.rectangle(
        id: nextId++,
        pinX: 3,
        pinY: 3,
        width: 1.4,
        height: 0.7,
        name: 'Arabic',
        fill: const VsdxFill(foreground: VsdxColor(0xFFFFFFFF), pattern: 1),
        line: const VsdxLine(color: VsdxColor.black, pattern: 0),
      ).copyWith(
        text: 'سلام',
        richText: const VsdxRichText(
          runs: [
            VsdxTextRun(
              text: 'سلام',
              charStyle: VsdxCharStyle(
                fontFamily: 'Arial',
                complexScriptFont: 'Times New Roman',
                complexScriptSizeInches: 18 / 72,
              ),
            ),
          ],
        ),
      ),
    );
    built = built.addShape(
      VsdxShapeFactory.rectangle(
        id: nextId++,
        pinX: 3,
        pinY: 2,
        width: 1.4,
        height: 0.7,
        name: 'GlowNoLine',
        fill: const VsdxFill(foreground: VsdxColor(0xFFEEEEEE), pattern: 1),
        line: const VsdxLine(pattern: 0),
      ).copyWith(
        glow: const VsdxGlow(
          color: VsdxColor(0xFFFF00FF),
          sizeInches: 0.08,
          transparency: 0.5,
        ),
      ),
    );
    built = built.addShape(
      VsdxShapeFactory.line(
        id: nextId++,
        ax: 5,
        ay: 2,
        bx: 7.5,
        by: 2,
        name: 'GlowStroke',
        line: const VsdxLine(
          color: VsdxColor(0xFF000000),
          weightInches: 0.04,
        ),
      ).copyWith(
        glow: const VsdxGlow(
          color: VsdxColor(0xFFFF00FF),
          sizeInches: 0.08,
          transparency: 0.5,
        ),
      ),
    );
    built = built.addShape(
      VsdxShapeFactory.rectangle(
        id: nextId++,
        pinX: 1,
        pinY: 5,
        width: 1.8,
        height: 0.8,
        name: 'CollectedChar',
        fill: const VsdxFill(foreground: VsdxColor(0xFFFFFFFF), pattern: 1),
        line: const VsdxLine(color: VsdxColor.black, pattern: 0),
      ).copyWith(
        text: 'Ab',
        shadow: const VsdxShadow(
          color: VsdxColor(0xFF00AA00),
          offsetXInches: 0.08,
          offsetYInches: 0.08,
          transparency: 0,
        ),
        richText: const VsdxRichText(
          runs: [
            VsdxTextRun(
              text: 'Ab',
              charStyle: VsdxCharStyle(
                fontScale: 0.9,
                textCase: VsdxTextCase.allCaps,
                position: VsdxTextPosition.superscript,
                doubleUnderline: true,
              ),
              paraStyle: VsdxParaStyle(bullet: 1),
            ),
          ],
        ),
      ),
    );
    built = built.addShape(
      VsdxShapeFactory.rectangle(
        id: nextId++,
        pinX: 3,
        pinY: 5,
        width: 1.8,
        height: 0.8,
        name: 'Letterspace',
        fill: const VsdxFill(foreground: VsdxColor(0xFFFFFFFF), pattern: 1),
        line: const VsdxLine(color: VsdxColor.black, pattern: 0),
      ).copyWith(
        text: 'Hi',
        richText: const VsdxRichText(
          runs: [
            VsdxTextRun(
              text: 'Hi',
              charStyle: VsdxCharStyle(letterSpacingInches: 0.02),
            ),
          ],
        ),
      ),
    );
    built = built.addShape(
      box(
        'FillUnknown',
        const VsdxFill(
          foreground: VsdxColor(0xFFFF0000),
          background: VsdxColor(0xFF0000FF),
          pattern: 41,
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
    expect(svg, contains('letter-spacing="'),
        reason:
            'Character Letterspace still paints here; FontScale bake is for Draw');
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
    expect(xml, contains('T="RelQuadBezTo"'),
        reason: 'Rounding and round-join bakes for LO');
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
    expect(xml.contains('N="Overline" V="1"'), isFalse,
        reason:
            'readCharIX skips Overline; combining U+0305 is what Draw paints');
    expect(xml, contains(kLibvisioCombiningOverline),
        reason: 'Overline bakes U+0305 so LibreOffice still shows the line');
    expect(xml, contains('N="Color" V="#666666"'),
        reason:
            'Character ColorTrans bakes RGB toward white; xmlStringToColour zeros alpha');
    expect(xml.contains('N="ColorTrans" V="0.4"'), isFalse,
        reason:
            'baked ColorTrans must be 0 so Visio does not fade the blended RGB twice');
    expect(xml.contains('N="Rounding" V="0.15"'), isFalse,
        reason: 'Rounding is baked into RelQuadBezTo; the cell must stay 0');
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
    final filledLineTrans = savedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'FilledLineTrans');
    expect(filledLineTrans.fill.pattern, 1);
    expect(filledLineTrans.fill.foreground?.value, 0xFFFFFFFF);
    expect(filledLineTrans.line.transparency, closeTo(0, 1e-12));
    expect(filledLineTrans.line.color?.value, 0xFF666666,
        reason:
            'filled 2-D LineColorTrans premultiplies; Draw has no stroke alpha');
    expect(filledLineTrans.geometries.where((g) => !g.noFill).length, 1,
        reason: 'body Fill is occupied so the stroke cannot become a ribbon');
    final rounding =
        savedDoc.pages.first.shapes.firstWhere((s) => s.name == 'Rounding');
    expect(rounding.line.roundingInches, closeTo(0, 1e-12),
        reason: 'Rounding cell is zeroed after the RelQuadBezTo bake');
    expect(
      rounding.geometries.single.commands.whereType<RelQuadBezTo>(),
      isNotEmpty,
    );
    final compound1d =
        savedDoc.pages.first.shapes.firstWhere((s) => s.name == 'Compound1D');
    expect(compound1d.line.compoundType, 0);
    expect(
      compound1d.geometries.where((g) => !g.noLine).length,
      greaterThan(1),
    );
    final thinThick1d = savedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'CompoundThinThick1D');
    expect(thinThick1d.is1D, isTrue);
    expect(thinThick1d.line.compoundType, 0);
    expect(thinThick1d.line.pattern, 0);
    expect(thinThick1d.fill.pattern, 1);
    expect(
      thinThick1d.geometries.where((g) => !g.noFill).length,
      2,
      reason: 'unfilled CompoundType 3 bakes two width-true ribbons',
    );
    final triple1d = savedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'CompoundTriple1D');
    expect(triple1d.line.compoundType, 0);
    expect(
      triple1d.geometries.where((g) => !g.noFill).length,
      3,
      reason: 'unfilled CompoundType 4 bakes three width-true ribbons',
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
          .firstWhere((s) => s.name == 'CompoundThinThick')
          .geometries
          .where((g) => !g.noLine)
          .length,
      2,
    );
    expect(
      savedDoc.pages.first.shapes
          .firstWhere((s) => s.name == 'CompoundTriple')
          .geometries
          .where((g) => !g.noLine)
          .length,
      3,
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
    expect(highlightStyle.overline, isFalse);
    expect(
      savedDoc.pages.first.shapes
          .firstWhere((s) => s.name == 'Highlight')
          .richText
          .runs
          .single
          .text,
      contains(kLibvisioCombiningOverline),
    );
    expect(highlightStyle.transparency, closeTo(0, 1e-9));
    expect(highlightStyle.color?.value, 0xFF666666);
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
    expect(
      savedDoc.pages.first.shapes
          .firstWhere((s) => s.name == 'Hangul')
          .richText
          .runs
          .single
          .charStyle
          .fontFamily,
      'Microsoft YaHei',
    );
    final arabicStyle = savedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'Arabic')
        .richText
        .runs
        .single
        .charStyle;
    expect(arabicStyle.fontFamily, 'Times New Roman');
    expect(arabicStyle.fontSizeInches, closeTo(18 / 72, 1e-12));
    expect(arabicStyle.complexScriptSizeInches, closeTo(18 / 72, 1e-12));
    expect(xml, contains('N="Font" V="Times New Roman"'));
    expect(xml, contains('N="Size" V="0.25"'),
        reason: 'ComplexScriptSize bakes into Size so Draw can collect it');
    expect(xml, contains('N="FontScale" V="0.9"'));
    expect(xml, contains('N="Case" V="1"'));
    expect(xml, contains('N="Pos" V="1"'));
    expect(xml, contains('N="DblUnderline" V="1"'));
    expect(xml, contains('N="Bullet" V="1"'));
    final glowNoLine =
        savedDoc.pages.first.shapes.firstWhere((s) => s.name == 'GlowNoLine');
    expect(glowNoLine.glow.enabled, isFalse,
        reason: 'GlowSize is not a token; the halo is a LineWeight bake');
    expect(glowNoLine.line.hasLine, isTrue);
    expect(glowNoLine.line.weightInches, closeTo(0.16, 1e-9));
    final glowStroke =
        savedDoc.pages.first.shapes.firstWhere((s) => s.name == 'GlowStroke');
    expect(glowStroke.glow.enabled, isFalse);
    expect(glowStroke.fill.hasFill, isTrue);
    expect(glowStroke.geometries.any((g) => !g.noFill), isTrue);
    expect(glowStroke.line.hasLine, isTrue);
    expect(
      savedDoc.pages.first.shapes
          .firstWhere((s) => s.name == 'FillUnknown')
          .fill
          .pattern,
      1,
      reason: 'FillPattern 41 is not a hatch/gradient id Draw paints',
    );
    final roundJoin =
        savedDoc.pages.first.shapes.firstWhere((s) => s.name == 'RoundJoin');
    expect(roundJoin.line.roundingInches, closeTo(0, 1e-12),
        reason:
            'round join must not write a Rounding cell Visio would restroke');
    expect(roundJoin.line.cap, LineCap.square);
    expect(
      roundJoin.geometries.single.commands.whereType<RelQuadBezTo>(),
      isNotEmpty,
      reason: '_lineProperties would miter a square cap; fillets are collected',
    );
    final bevelJoin =
        savedDoc.pages.first.shapes.firstWhere((s) => s.name == 'BevelJoin');
    expect(bevelJoin.line.roundingInches, closeTo(0, 1e-12),
        reason:
            'bevel join must not write a Rounding cell Visio would restroke');
    expect(bevelJoin.line.cap, LineCap.square);
    expect(
      bevelJoin.geometries.single.commands.whereType<RelQuadBezTo>(),
      isEmpty,
      reason: 'bevel corners bake as LineTo chamfers, not RelQuadBezTo',
    );
    expect(
      bevelJoin.geometries.single.commands.whereType<LineTo>().length,
      greaterThan(2),
    );
    final bevelRoundCap = savedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'BevelRoundCap');
    expect(bevelRoundCap.line.roundingInches, closeTo(0, 1e-12));
    expect(bevelRoundCap.line.cap, LineCap.extended,
        reason:
            'Draw derives round join from LineCap 0; flatten so chamfers stay sharp');
    expect(
      bevelRoundCap.geometries.single.commands.whereType<RelQuadBezTo>(),
      isEmpty,
    );
    expect(
      bevelRoundCap.geometries.single.commands.whereType<LineTo>().length,
      greaterThan(2),
    );
    final arcsJoin =
        savedDoc.pages.first.shapes.firstWhere((s) => s.name == 'ArcsJoin');
    expect(arcsJoin.line.roundingInches, closeTo(0, 1e-12));
    expect(
      arcsJoin.geometries.single.commands.whereType<RelQuadBezTo>(),
      isNotEmpty,
      reason: 'canvas treats arcs join as round; Draw would otherwise miter',
    );
    final collected = savedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'CollectedChar')
        .richText
        .runs
        .single;
    expect(collected.charStyle.fontScale, closeTo(0.9, 1e-9));
    expect(collected.charStyle.textCase, VsdxTextCase.allCaps);
    expect(collected.charStyle.position, VsdxTextPosition.superscript);
    expect(collected.charStyle.doubleUnderline, isTrue);
    expect(collected.paraStyle.bullet, 1);
    expect(
      savedDoc.pages.first.shapes
          .firstWhere((s) => s.name == 'CollectedChar')
          .shadow
          .enabled,
      isTrue,
    );
    final letterspace = savedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'Letterspace')
        .richText
        .runs
        .single
        .charStyle;
    expect(letterspace.letterSpacingInches, closeTo(0, 1e-9),
        reason: 'Letterspace is not a token; tracking bakes into FontScale');
    expect(
      letterspace.fontScale,
      closeTo(
        fontScaleForLibvisioWrite(
          const VsdxCharStyle(letterSpacingInches: 0.02),
          'Hi',
        ),
        1e-9,
      ),
    );
    expect(xml.contains('N="Letterspace" V="0.02"'), isFalse);
    // RVNGSVGDrawingGenerator never emits span fo:background-color (vsd2xhtml
    // tspans are fill-only). vsd2raw still records the property Draw uses.
    _expectVsd2rawCollected(saved, <String>[
      'fo:background-color: #ff00ff',
      'style:font-name: Microsoft YaHei',
      'style:font-name: Times New Roman',
      'fo:text-transform: uppercase',
      'style:text-position: super',
      'style:text-underline-type: double',
      'style:text-scale',
      'text:bullet-char',
      'draw:shadow',
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
