/// Fill, line and Rounding types must paint here, and a save must emit the
/// cells / rows LibreOffice's libvisio importer still collects.
///
/// `VSDXParser` has no FillGradient token, no shape-level Rounding, no
/// CompoundType token, no LineGradient token, and no LineColorTrans token
/// (`xmlStringToColour` also forces Colour.a = 0). A modern gradient with
/// FillPattern=1 (or omitted FillPattern / 0, libvisio's shape default), a polyline with only a Rounding cell, a CompoundType>0
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
/// built-in 2–23 table `_lineProperties` actually dashes; draw.io
/// `User.veDashPattern` arrays that are not those ids bake as MoveTo/LineTo
/// dashes with LinePattern=1. Built-in LinePattern 2–23 that also need a
/// LineColorTrans / LineGradient ribbon flatten the same way first, so the
/// filled silhouette keeps the gaps `_lineProperties` would have dashed.
/// `LineCap` 0/1/2 is a token libvisio *does* collect. Character Highlight is skipped by
/// `readCharIX` but a uniform marker with no authored TextBkgnd is written
/// there — `VSDContentCollector` paints it as span `fo:background-color`
/// and Draw shows the plate. `RVNGSVGDrawingGenerator` drops that property,
/// so the oracle SVG is the wrong place to look; `vsd2raw` still has it.
/// `TextBkgndTrans` and layer `ColorTrans` have no VSDX collector case, so
/// a save premultiplies those into RGB toward white. Overline still paints
/// here even though `readCharIX` skips it; a save inserts U+0305 combining
/// marks so Draw paints the line too. Glow* is not a token: unfilled
/// 1-D strokes with resolved RGB bake a Gaussian PNG plate, unfilled 2-D
/// with resolved RGB bakes a Gaussian PNG ring, and filled NoLine shapes
/// bake a Gaussian PNG sibling when RGB is resolved (theme-only NoLine
/// still uses a LineWeight halo; theme-only 1-D still uses a
/// FillForegndTrans ribbon). Character ColorTrans and ShdwForegndTrans
/// cannot carry alpha through `xmlStringToColour`, so a save premultiplies
/// those into RGB toward white and writes Trans=0 (theme-bound RGB-less
/// cells keep THEMEVAL). Filled-shape LineColorTrans / LineGradient bake a
/// locked sibling ribbon whose FillForegndTrans Draw collects, then drop
/// the source line. CompoundType 1–4 rails, LinePattern 2–23 dashes, and
/// open-path Begin/EndArrow join that sibling so Draw does not keep an
/// opaque stroke (or hang markers on a dropped line) on top of the wash.
/// `AsianFont` / `ComplexScriptFont` / `ComplexScriptSize` are not tokens,
/// so an Asian-only (Hangul/Kana/Han) or complex-script-only run whose
/// Visio `Font` is Arial is rewritten to the face and size Draw will
/// actually load. Mixed Latin+CJK runs keep `Font`. Character `Letterspace`
/// is not a token; canvas / SVG already fold FontScale into tracking at
/// 0.55×Size, so a save adds Letterspace into FontScale and writes
/// Letterspace 0. Picture `SoftEdgesSize` is not a token; a 2-D Foreign
/// bitmap bakes the same SourceAlpha feather canvas / SVG use into PNG
/// alpha (cropped frames composite into the box first so ImgOffset still
/// matches Draw), then SoftEdgesSize is written 0. Marker ids whose
/// `_linePropertiesMarkerPath` is still a TODO stub bake as Geometry so
/// Draw does not reuse a sibling silhouette. Unknown
/// `FillPattern` ids above 40 snap to solid `1`.
/// Explicit round joins on a square/flat cap bake RelQuadBezTo —
/// `_lineProperties` would otherwise emit miter from LineCap. Bevel joins
/// bake LineTo chamfers; a `User.veMiterLimit` tighter than Draw's default
/// 4 bakes the same chamfers, then the User row is dropped. Limits above 4
/// expand an unfilled solid polyline to a filled ribbon so Draw keeps the
/// canvas spike (`_lineProperties` never emits `svg:stroke-miterlimit`).
/// Filled 2-D uses a locked sibling ribbon so FillPattern stays the body.
/// A round cap with an explicit miter join flattens LineCap to extended so
/// Draw does not round-join from LineCap. Straight edges keep the round cap.
/// Arcs joins bake the same fillets as round (canvas `canvasStrokeJoin`).
/// `Reflection*` cells are not tokens, so a
/// filled 2-D shape bakes a locked sibling plate whose FillForegndTrans
/// Draw collects, then `ReflectionSize` is written 0. An unfilled 2-D
/// stroke bakes a locked PNG band of the mirrored stroke, an unfilled
/// 1-D stroke bakes the same PNG from its stroke ribbon, and a Foreign
/// picture bakes a locked Gaussian PNG sibling of the same mirrored bitmap
/// canvas / SVG already paint (cropped pictures composite the Img*
/// window into the frame first). Glow on a filled
/// shape that already paints a stroke, a filled NoLine 2-D, or an unfilled
/// 2-D stroke, bakes a locked Gaussian PNG sibling when RGB is resolved,
/// then `GlowSize` is written 0. A Foreign picture with resolved RGB
/// bakes the same Gaussian PNG ring around the image frame. Theme-only
/// glow still uses a LineWeight halo so THEMEVAL()
/// survives. Page `PageColor` is not a token, so
/// a save prepends a locked full-page plate Draw can fill. draw.io Sketch
/// is User rows libvisio never reads, so a save maps the hatch onto
/// FillPattern 2–24 and bakes the two jiggle strokes as locked siblings,
/// then writes `veSketch=0`. draw.io Glass is also a User row, so a save
/// bakes a locked white top-light sibling (`FillForegndTrans`) and writes
/// `veGlass=0`. draw.io Shape Opacity is a User row, so a save folds it
/// into FillForegndTrans / line transparency and drops `veOpacity`.
/// draw.io Label Border is also a User row, so a save bakes a locked
/// NoFill sibling whose LineColor Draw collects, then drops
/// `veLabelBorderColor`. draw.io Label Padding is also a User row, so a
/// save adds the pixel inset into Left/Right/Top/BottomMargin and drops
/// `veLabelPadding`. draw.io Word Wrap is also a User row, so a save
/// expands TxtWidth to the unwrapped line and drops `veWordWrap`.
/// Geometry `SoftEdgesSize` is not a token, so a save bakes a feathered
/// PNG sibling and drops the source fill. Resolved-RGB FillGradient,
/// classic 25–40 washes and FillPattern 2–24 hatches go into that PNG
/// so Draw does not keep a hard fill. An unfilled 2-D stroke with
/// SoftEdges bakes the stroke ring the same way and drops the source
/// line. Dashed LinePattern 2–23 / custom arrays become per-dash ribbons
/// in that PNG so Draw keeps the gaps. A filled 2-D shape that also paints a
/// solid or dashed stroke bakes both into one padded plate and drops fill
/// and line. Gradient / hatch fills with a stroke join that plate.
/// CompoundType 1–4 rails join that plate too. LineGradient strokes
/// with resolved RGB join that plate so Draw does not keep a hard
/// opaque outline. Rounding fillets join that plate so Draw does not
/// keep square corners after the fill is dropped.
/// `ShadowBlur` is not a token,
/// so a save bakes a Gaussian PNG sibling and clears ShdwPattern. A Foreign
/// picture with blur bakes the same filled image-frame silhouette. PageSheet
/// `ShdwType` / `ShdwObliqueAngle` / `ShdwScaleFactor` are not tokens, so a
/// hard-edged shadow bakes a sheared vector sibling and a blurred shadow
/// bakes a sheared Gaussian PNG.
/// draw.io Curved Text is also a User row, so a save bakes locked
/// per-glyph siblings along the canvas quadratic arc, hides the source
/// and drops `veCurvedText`. FlipX / FlipY extra text mirrors about TxtPin
/// are baked so Draw keeps the upright arc. draw.io Shape Inside is also a
/// User row, so a save bakes locked per-line siblings in the outline bands,
/// hides the source and drops `veShapeInside`. FlipX / FlipY use the same
/// TxtPin extra-mirror. Sketch jiggle with open arrows bakes arrow Geometry
/// on the source and drops markers from the jiggle plates. draw.io Rotate with Edge is also a
/// User row, so a save writes `TxtAngle` and drops `veAutoRotateLabel`.
/// draw.io Flow Animation is also a User row, so a save flattens the
/// synthesised 8 CSS-px dash and writes `veFlowAnimation=0`. Arrowed
/// connectors that also flatten those dashes (or `veDashPattern`) bake
/// Begin/EndArrow as Geometry first so Draw does not hang a marker on
/// every open dash.
library;

import 'dart:io';
import 'dart:math' as math;
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
    expect(shapeNeedsLibvisioGlowBake(stroke), isFalse,
        reason: '1-D RGB bakes a Gaussian PNG plate, not a hard ribbon');
    expect(shapeNeedsLibvisioGlowPlateBake(stroke), isTrue);
    final strokeWrite = libvisioShapeWrite(stroke);
    expect(strokeWrite.fill.hasFill, isFalse);
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
    expect(shapeNeedsLibvisioGlowBake(filled), isFalse,
        reason: 'filled NoLine RGB bakes a Gaussian PNG sibling');
    expect(shapeNeedsLibvisioGlowPlateBake(filled), isTrue);
    final filledWrite = libvisioShapeWrite(filled);
    expect(filledWrite.line.hasLine, isFalse);
    expect(filledWrite.fill.pattern, 1);
    expect(glowForLibvisioWrite(filled).enabled, isFalse);

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
    expect(shapeNeedsLibvisioGlowPlateBake(outlined), isTrue,
        reason: 'filled 2-D with a stroke bakes a sibling Gaussian PNG');
    expect(glowForLibvisioWrite(outlined).enabled, isFalse);

    final themeFilled = VsdxShapeFactory.rectangle(
      id: 4,
      pinX: 1,
      pinY: 1,
      width: 1.5,
      height: 0.8,
      fill: const VsdxFill(foreground: VsdxColor(0xFFEEEEEE), pattern: 1),
      line: const VsdxLine(pattern: 0),
    ).copyWith(
      glow: const VsdxGlow(
        themeColorIndex: 2,
        sizeInches: 0.08,
      ),
    );
    expect(shapeNeedsLibvisioGlowBake(themeFilled), isTrue,
        reason: 'theme-only NoLine still steals Line so THEMEVAL() survives');
    expect(shapeNeedsLibvisioGlowPlateBake(themeFilled), isFalse);
    final themeWrite = libvisioShapeWrite(themeFilled);
    expect(themeWrite.line.hasLine, isTrue);
    expect(themeWrite.line.weightInches, closeTo(0.16, 1e-9));

    final unfilled = VsdxShapeFactory.rectangle(
      id: 5,
      pinX: 1,
      pinY: 1,
      width: 1.5,
      height: 0.8,
      fill: const VsdxFill(pattern: 0),
    ).copyWith(
      glow: const VsdxGlow(
        color: VsdxColor(0xFF00CC66),
        sizeInches: 0.08,
      ),
    );
    expect(shapeNeedsLibvisioGlowBake(unfilled), isFalse,
        reason: 'unfilled 2-D RGB bakes a Gaussian PNG ring');
    expect(shapeNeedsLibvisioGlowPlateBake(unfilled), isTrue);
    final unfilledWrite = libvisioShapeWrite(unfilled);
    expect(unfilledWrite.line.hasLine, isTrue);
    expect(unfilledWrite.fill.hasFill, isFalse);
    expect(glowForLibvisioWrite(unfilled).enabled, isFalse);
  });

  test('1-D stroke Glow bakes a Gaussian PNG plate for LibreOffice', () {
    const colour = VsdxColor(0xFFFF00FF);
    final shape = VsdxShapeFactory.line(
      id: 1,
      ax: 2,
      ay: 5.5,
      bx: 6.5,
      by: 5.5,
      name: 'GlowStroke1d',
      line: const VsdxLine(
        color: VsdxColor.black,
        weightInches: 0.06,
      ),
    ).copyWith(
      glow: const VsdxGlow(
        color: colour,
        sizeInches: 0.12,
        transparency: 0.25,
      ),
    );
    expect(shape.is1D, isTrue);
    expect(shape.height.abs(), closeTo(0, 1e-12));
    expect(shapeNeedsLibvisioGlowBake(shape), isFalse);
    expect(shapeNeedsLibvisioGlowPlateBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.is1D, isTrue);
    expect(source.line.pattern, 1);
    expect(source.fill.pattern, 0);
    final plate = baked.pages.first.shapes.where(isLibvisioGlowPlate).single;
    expect(plate.hasImage, isTrue);
    expect(plate.is1D, isFalse);
    expect(plate.height, greaterThan(0.2));
    final decoded = raster.decodePng(
      baked.images.findByPart(plate.imagePartName!)!.bytes,
    )!;
    var ink = 0;
    for (var y = 0; y < decoded.height; y++) {
      for (var x = 0; x < decoded.width; x++) {
        final pixel = decoded.getPixel(x, y);
        if (pixel.r > pixel.g + 15 && pixel.b > pixel.g + 15 && pixel.a > 20) {
          ink++;
        }
      }
    }
    expect(ink, greaterThan(8),
        reason: 'the 1-D glow PNG must carry magenta halo ink, not an empty plate');

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(savedDoc.pages.first.findShapeById(1)!.glow.enabled, isFalse);
    expect(
      savedDoc.pages.first.shapes.where(isLibvisioGlowPlate),
      hasLength(1),
    );
    expect(
      savedDoc.pages.first.findShapeById(1)!.fill.hasFill,
      isFalse,
      reason: 'source must keep an unfilled stroke; the halo is the PNG plate',
    );
  });

  test('Glow on a filled stroke bakes a sibling halo LibreOffice can collect',
      () {
    const colour = VsdxColor(0xFF00CC66);
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.4,
      height: 0.7,
      name: 'GlowBox',
      fill: const VsdxFill(foreground: VsdxColor(0xFFEEEEEE), pattern: 1),
      line: const VsdxLine(
          color: VsdxColor.black, pattern: 1, weightInches: 0.02),
    ).copyWith(
      glow: const VsdxGlow(
        color: colour,
        sizeInches: 0.08,
        transparency: 0.4,
      ),
    );
    expect(shapeNeedsLibvisioGlowPlateBake(shape), isTrue);
    expect(shapeNeedsLibvisioGlowBake(shape), isFalse);
    expect(glowForLibvisioWrite(shape).enabled, isFalse);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    expect(
      baked.pages.first.shapes.where(isLibvisioGlowPlate),
      hasLength(1),
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioGlowPlate),
      hasLength(1),
      reason: 'a second save must not stack another halo',
    );
    final plate = baked.pages.first.shapes.first;
    expect(plate.name, '${kLibvisioGlowShapeNamePrefix}1');
    expect(plate.locked, isTrue);
    expect(plate.hasImage, isTrue);
    expect(plate.width, greaterThan(shape.width));
    expect(plate.line.hasLine, isFalse);
    expect(baked.pages.first.findShapeById(1)!.line.pattern, 1,
        reason: 'the source outline must stay on the source');
    expect(baked.pages.first.findShapeById(1)!.glow.enabled, isTrue,
        reason: 'the in-memory source keeps the live effect; XML Size is 0');
    final png = baked.images.findByPart(plate.imagePartName!);
    expect(png, isNotNull);
    final decoded = raster.decodePng(png!.bytes)!;
    var glowGreen = 0;
    for (var x = 0; x < decoded.width ~/ 4; x++) {
      final pixel = decoded.getPixel(x, decoded.height ~/ 2);
      if (pixel.g > glowGreen) glowGreen = pixel.g.toInt();
    }
    expect(glowGreen, greaterThan(80),
        reason: 'Glow PNG must paint the green halo outside the body');

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(savedDoc.pages.first.findShapeById(1)!.glow.enabled, isFalse);
    expect(savedDoc.pages.first.findShapeById(1)!.line.pattern, 1);
    final savedPlate = savedDoc.pages.first.shapes
        .firstWhere((s) => s.name == '${kLibvisioGlowShapeNamePrefix}1');
    expect(savedPlate.hasImage, isTrue);
    expect(savedPlate.width, greaterThan(shape.width));

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    final after = oracle.svgPages(saved)?.join() ?? '';
    expect(after, isNotEmpty);
  });

  test(
      'Glow on a filled NoLine bakes a sibling Gaussian PNG LibreOffice can collect',
      () {
    const colour = VsdxColor(0xFFFF00FF);
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.4,
      height: 0.7,
      name: 'GlowNoLine',
      fill: const VsdxFill(foreground: VsdxColor(0xFFEEEEEE), pattern: 1),
      line: const VsdxLine(pattern: 0),
    ).copyWith(
      glow: const VsdxGlow(
        color: colour,
        sizeInches: 0.08,
        transparency: 0.5,
      ),
    );
    expect(shapeNeedsLibvisioGlowPlateBake(shape), isTrue);
    expect(shapeNeedsLibvisioGlowBake(shape), isFalse);
    expect(glowForLibvisioWrite(shape).enabled, isFalse);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    expect(
      baked.pages.first.shapes.where(isLibvisioGlowPlate),
      hasLength(1),
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioGlowPlate),
      hasLength(1),
      reason: 'a second save must not stack another halo',
    );
    final plate = baked.pages.first.shapes.first;
    expect(plate.name, '${kLibvisioGlowShapeNamePrefix}1');
    expect(plate.locked, isTrue);
    expect(plate.hasImage, isTrue);
    expect(plate.width, greaterThan(shape.width));
    expect(plate.line.hasLine, isFalse);
    expect(baked.pages.first.findShapeById(1)!.line.pattern, 0,
        reason: 'the source must stay NoLine');
    expect(baked.pages.first.findShapeById(1)!.glow.enabled, isTrue,
        reason: 'the in-memory source keeps the live effect; XML Size is 0');
    final png = baked.images.findByPart(plate.imagePartName!);
    expect(png, isNotNull);
    final decoded = raster.decodePng(png!.bytes)!;
    var glowRed = 0;
    for (var x = 0; x < decoded.width ~/ 4; x++) {
      final pixel = decoded.getPixel(x, decoded.height ~/ 2);
      if (pixel.r > glowRed) glowRed = pixel.r.toInt();
    }
    expect(glowRed, greaterThan(80),
        reason: 'Glow PNG must paint the magenta halo outside the body');

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(savedDoc.pages.first.findShapeById(1)!.glow.enabled, isFalse);
    expect(savedDoc.pages.first.findShapeById(1)!.line.pattern, 0);
    final savedPlate = savedDoc.pages.first.shapes
        .firstWhere((s) => s.name == '${kLibvisioGlowShapeNamePrefix}1');
    expect(savedPlate.hasImage, isTrue);
    expect(savedPlate.width, greaterThan(shape.width));

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    final after = oracle.svgPages(saved)?.join() ?? '';
    expect(after, isNotEmpty);
  });

  test(
      'Glow on an unfilled 2-D stroke bakes a Gaussian PNG ring LibreOffice can collect',
      () {
    const colour = VsdxColor(0xFF00CC66);
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.4,
      height: 0.7,
      name: 'GlowNoFill',
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(
        color: VsdxColor.black,
        pattern: 1,
        weightInches: 0.04,
      ),
    ).copyWith(
      glow: const VsdxGlow(
        color: colour,
        sizeInches: 0.08,
        transparency: 0.4,
      ),
    );
    expect(shapeNeedsLibvisioGlowPlateBake(shape), isTrue);
    expect(shapeNeedsLibvisioGlowBake(shape), isFalse);
    expect(glowForLibvisioWrite(shape).enabled, isFalse);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    expect(
      baked.pages.first.shapes.where(isLibvisioGlowPlate),
      hasLength(1),
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioGlowPlate),
      hasLength(1),
      reason: 'a second save must not stack another halo',
    );
    final plate = baked.pages.first.shapes.first;
    expect(plate.name, '${kLibvisioGlowShapeNamePrefix}1');
    expect(plate.locked, isTrue);
    expect(plate.hasImage, isTrue);
    expect(plate.width, greaterThan(shape.width));
    expect(baked.pages.first.findShapeById(1)!.line.pattern, 1,
        reason: 'the source outline must stay on the source');
    expect(baked.pages.first.findShapeById(1)!.fill.hasFill, isFalse);
    expect(baked.pages.first.findShapeById(1)!.glow.enabled, isTrue,
        reason: 'the in-memory source keeps the live effect; XML Size is 0');
    final png = baked.images.findByPart(plate.imagePartName!);
    expect(png, isNotNull);
    final decoded = raster.decodePng(png!.bytes)!;
    final centre = decoded.getPixel(decoded.width ~/ 2, decoded.height ~/ 2);
    expect(centre.r, greaterThan(200),
        reason: 'unfilled Glow PNG must keep a hollow interior');
    var bestDelta = -1.0;
    for (var x = 0; x < decoded.width ~/ 2; x++) {
      final pixel = decoded.getPixel(x, decoded.height ~/ 2);
      final delta = (pixel.g - pixel.r).toDouble();
      if (delta > bestDelta) bestDelta = delta;
    }
    expect(bestDelta, greaterThan(8),
        reason: 'Glow PNG must paint the green ring outside the body');

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(savedDoc.pages.first.findShapeById(1)!.glow.enabled, isFalse);
    expect(savedDoc.pages.first.findShapeById(1)!.line.pattern, 1);
    expect(savedDoc.pages.first.findShapeById(1)!.fill.hasFill, isFalse);
    final savedPlate = savedDoc.pages.first.shapes
        .firstWhere((s) => s.name == '${kLibvisioGlowShapeNamePrefix}1');
    expect(savedPlate.hasImage, isTrue);
    expect(savedPlate.width, greaterThan(shape.width));

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    final after = oracle.svgPages(saved)?.join() ?? '';
    expect(after, isNotEmpty);
  });

  test('Glow on an unfilled CompoundType stroke bakes a Gaussian PNG ring', () {
    const colour = VsdxColor(0xFF00CC66);
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.4,
      height: 0.7,
      name: 'GlowCompound',
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(
        color: VsdxColor.black,
        pattern: 1,
        weightInches: 0.12,
        compoundType: 1,
      ),
    ).copyWith(
      glow: const VsdxGlow(
        color: colour,
        sizeInches: 0.08,
        transparency: 0.4,
      ),
    );
    expect(shapeNeedsLibvisioGlowPlateBake(shape), isTrue,
        reason: 'CompoundType must not drop the unfilled Glow PNG');
    expect(shapeNeedsLibvisioGlowBake(shape), isFalse);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    expect(
      baked.pages.first.shapes.where(isLibvisioGlowPlate),
      hasLength(1),
    );
    final plate = baked.pages.first.shapes.where(isLibvisioGlowPlate).single;
    expect(plate.hasImage, isTrue);
    expect(baked.pages.first.findShapeById(1)!.line.compoundType, 1,
        reason: 'the source keeps CompoundType; the PNG carries the halo');
    expect(baked.pages.first.findShapeById(1)!.fill.hasFill, isFalse);
    final decoded = raster.decodePng(
      baked.images.findByPart(plate.imagePartName!)!.bytes,
    )!;
    expect(
      decoded.getPixel(decoded.width ~/ 2, decoded.height ~/ 2).r,
      greaterThan(200),
      reason: 'compound Glow PNG must keep a hollow interior',
    );
    var bestDelta = -1.0;
    for (var x = 0; x < decoded.width ~/ 2; x++) {
      final pixel = decoded.getPixel(x, decoded.height ~/ 2);
      final delta = (pixel.g - pixel.r).toDouble();
      if (delta > bestDelta) bestDelta = delta;
    }
    expect(bestDelta, greaterThan(8),
        reason: 'compound Glow PNG must paint the green ring outside the body');

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(savedDoc.pages.first.findShapeById(1)!.glow.enabled, isFalse);
    expect(savedDoc.pages.first.findShapeById(1)!.fill.hasFill, isFalse);
    expect(
      savedDoc.pages.first.shapes.where(isLibvisioGlowPlate),
      hasLength(1),
    );
  });

  test(
      'Glow on a Foreign picture bakes a Gaussian PNG ring LibreOffice can collect',
      () {
    const part = '/visio/media/glow.png';
    final rasterImage = raster.Image(width: 16, height: 16);
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 16; x++) {
        rasterImage.setPixelRgba(x, y, 0, 0, 255, 255);
      }
    }
    final sourceImage = VsdxImage(
      partName: part,
      bytes: Uint8List.fromList(raster.encodePng(rasterImage)),
      mimeType: 'image/png',
    );
    const colour = VsdxColor(0xFF00CC66);
    final shape = VsdxShapeFactory.picture(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.4,
      height: 0.7,
      imagePartName: part,
      name: 'GlowPicture',
    ).copyWith(
      glow: const VsdxGlow(
        color: colour,
        sizeInches: 0.08,
        transparency: 0.4,
      ),
    );
    expect(shapeNeedsLibvisioGlowPlateBake(shape), isTrue);
    expect(shapeNeedsLibvisioGlowBake(shape), isFalse);
    expect(glowForLibvisioWrite(shape).enabled, isFalse);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.copyWith(images: doc.images.withImage(sourceImage));
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    expect(
      baked.pages.first.shapes.where(isLibvisioGlowPlate),
      hasLength(1),
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioGlowPlate),
      hasLength(1),
      reason: 'a second save must not stack another halo',
    );
    final plate = baked.pages.first.shapes.first;
    expect(plate.name, '${kLibvisioGlowShapeNamePrefix}1');
    expect(plate.locked, isTrue);
    expect(plate.hasImage, isTrue);
    expect(plate.width, greaterThan(shape.width));
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.hasImage, isTrue);
    expect(source.imagePartName, part);
    expect(source.line.pattern, 0,
        reason: 'picture Glow must not steal Line as a hard halo');
    expect(source.glow.enabled, isTrue,
        reason: 'the in-memory source keeps the live effect; XML Size is 0');
    final png = baked.images.findByPart(plate.imagePartName!);
    expect(png, isNotNull);
    final decoded = raster.decodePng(png!.bytes)!;
    final centre = decoded.getPixel(decoded.width ~/ 2, decoded.height ~/ 2);
    expect(centre.r, greaterThan(200),
        reason: 'picture Glow PNG must keep a hollow interior');
    var bestDelta = -1.0;
    for (var x = 0; x < decoded.width ~/ 2; x++) {
      final pixel = decoded.getPixel(x, decoded.height ~/ 2);
      final delta = (pixel.g - pixel.r).toDouble();
      if (delta > bestDelta) bestDelta = delta;
    }
    expect(bestDelta, greaterThan(8),
        reason: 'picture Glow PNG must paint the green ring outside the body');

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(savedDoc.pages.first.findShapeById(1)!.glow.enabled, isFalse);
    expect(savedDoc.pages.first.findShapeById(1)!.line.pattern, 0);
    expect(savedDoc.pages.first.findShapeById(1)!.hasImage, isTrue);
    final savedPlate = savedDoc.pages.first.shapes
        .firstWhere((s) => s.name == '${kLibvisioGlowShapeNamePrefix}1');
    expect(savedPlate.hasImage, isTrue);
    expect(savedPlate.width, greaterThan(shape.width));

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    final after = oracle.svgPages(saved)?.join() ?? '';
    expect(after, isNotEmpty);
  });

  test('Sketch bakes hatch and jiggle strokes LibreOffice can collect', () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.6,
      height: 0.8,
      name: 'SketchBox',
      fill: const VsdxFill(foreground: VsdxColor(0xFF2244AA), pattern: 1),
      line: const VsdxLine(
        color: VsdxColor.black,
        pattern: 1,
        weightInches: 0.02,
      ),
    )
        .withSketchEffect(true)
        .withSketchJiggle(3.5)
        .withSketchFillStyle(VsdxSketchFillStyle.hachure);
    expect(shapeNeedsLibvisioSketchBake(shape), isTrue);
    expect(shapeNeedsLibvisioSketchStrokeBake(shape), isTrue);
    expect(shapeNeedsLibvisioSketchFillBake(shape), isTrue);
    expect(sketchFillPatternForLibvisioWrite(shape), 15);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    expect(
      baked.pages.first.shapes.where(isLibvisioSketchPlate),
      hasLength(2),
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioSketchPlate),
      hasLength(2),
      reason: 'a second save must not stack another pair of Sketch strokes',
    );
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.sketchEffect, isFalse);
    expect(source.sketchJiggle, closeTo(3.5, 1e-9));
    expect(source.fill.pattern, 15);
    expect(source.fill.backgroundTransparency, closeTo(1, 1e-9));
    expect(source.geometries.every((g) => g.noLine), isTrue);
    expect(
      baked.pages.first.shapes.where(isLibvisioSketchPlate).every(
            (s) => s.locked && s.line.hasLine && s.fill.pattern == 0,
          ),
      isTrue,
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(savedDoc.pages.first.findShapeById(1)!.sketchEffect, isFalse);
    expect(savedDoc.pages.first.findShapeById(1)!.fill.pattern, 15);
    expect(
      savedDoc.pages.first.shapes.where(isLibvisioSketchPlate),
      hasLength(2),
    );

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    final after = oracle.svgPages(saved)?.join() ?? '';
    expect(after, isNotEmpty);
    _expectVsd2rawCollected(saved, const <String>[
      'draw:fill: hatch',
      'draw:rotation: 315',
    ]);
  });

  test('Sketch jiggle with open arrows bakes arrow Geometry', () {
    final shape = VsdxShapeFactory.line(
      id: 1,
      ax: 1,
      ay: 2,
      bx: 4,
      by: 2,
      name: 'SketchArrow',
      line: const VsdxLine(
        color: VsdxColor(0xFF000000),
        pattern: 1,
        weightInches: 0.04,
        beginArrow: 0,
        endArrow: 4,
        endArrowSizeInches: 0.2,
      ),
    ).withSketchEffect(true).withSketchJiggle(3.5);
    expect(shapeNeedsLibvisioSketchStrokeBake(shape), isTrue);
    expect(shape.line.endArrow, 4);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final plates =
        baked.pages.first.shapes.where(isLibvisioSketchPlate).toList();
    expect(plates, hasLength(2));
    expect(plates.every((p) => p.line.endArrow == 0), isTrue);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.line.endArrow, 0);
    expect(source.fill.hasFill, isTrue);
    expect(
      source.geometries.where((g) => !g.noFill).length,
      greaterThanOrEqualTo(1),
      reason: 'open arrowheads become filled Geometry on the source',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(
      savedDoc.pages.first.shapes.where(isLibvisioSketchPlate),
      hasLength(2),
    );
    expect(savedDoc.pages.first.findShapeById(1)!.line.endArrow, 0);
  });

  test('Glass bakes a top-light sibling LibreOffice can collect', () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.6,
      height: 0.8,
      name: 'GlassBox',
      fill: const VsdxFill(foreground: VsdxColor(0xFF1565C0), pattern: 1),
      line: const VsdxLine(
        color: VsdxColor.black,
        pattern: 1,
        weightInches: 0.02,
      ),
    ).withGlassEffect(true);
    expect(shapeNeedsLibvisioGlassBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    expect(
      baked.pages.first.shapes.where(isLibvisioGlassPlate),
      hasLength(1),
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioGlassPlate),
      hasLength(1),
      reason: 'a second save must not stack another Glass highlight',
    );
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.glassEffect, isFalse);
    expect(source.fill.foreground?.value, 0xFF1565C0);
    final plate = baked.pages.first.shapes.firstWhere(isLibvisioGlassPlate);
    expect(plate.name, '${kLibvisioGlassShapeNamePrefix}1');
    expect(plate.locked, isTrue);
    expect(plate.line.pattern, 0);
    expect(plate.fill.pattern, 1);
    expect(plate.fill.foreground?.value, VsdxColor.white.value);
    expect(plate.fill.foregroundTransparency, closeTo(0.45, 1e-9));
    expect(
      plate.geometries.single.commands.whereType<RelQuadBezTo>(),
      isNotEmpty,
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(savedDoc.pages.first.findShapeById(1)!.glassEffect, isFalse);
    expect(
      savedDoc.pages.first.shapes.where(isLibvisioGlassPlate),
      hasLength(1),
    );
    final savedPlate =
        savedDoc.pages.first.shapes.firstWhere(isLibvisioGlassPlate);
    expect(savedPlate.fill.pattern, 1);
    expect(savedPlate.fill.foregroundTransparency, closeTo(0.45, 1e-9));
    expect(
      savedPlate.geometries.single.commands.whereType<RelQuadBezTo>(),
      isNotEmpty,
    );
    expect(
        savedPlate.geometries.single.commands.whereType<QuadBezTo>(), isEmpty);

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    final after = oracle.svgPages(saved)?.join() ?? '';
    expect(after, isNotEmpty);
    _expectVsd2rawCollected(saved, const <String>[
      'draw:fill-color: #ffffff',
    ]);
  });

  test('Shape Opacity bakes FillForegndTrans LibreOffice can collect', () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.6,
      height: 0.8,
      name: 'OpacityBox',
      fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
      line: const VsdxLine(pattern: 0),
    ).withShapeOpacity(0.4);
    expect(shapeNeedsLibvisioOpacityBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.shapeOpacity, 1);
    expect(source.fill.foregroundTransparency, closeTo(0.6, 1e-9));
    expect(source.fill.foreground?.value, 0xFFFF0000);
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .findShapeById(1)!
          .fill
          .foregroundTransparency,
      closeTo(0.6, 1e-9),
      reason: 'a second save must not stack another fade',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    final after = savedDoc.pages.first.findShapeById(1)!;
    expect(after.shapeOpacity, 1);
    expect(after.fill.foregroundTransparency, closeTo(0.6, 1e-9));

    final stroke = VsdxShapeFactory.line(
      id: 2,
      ax: 0,
      ay: 0,
      bx: 3,
      by: 0,
      line: const VsdxLine(
        color: VsdxColor(0xFF0000FF),
        pattern: 1,
        weightInches: 0.08,
      ),
    ).withShapeOpacity(0.5);
    var strokeDoc = parser.parse(blank);
    strokeDoc =
        strokeDoc.replacePage(0, strokeDoc.pages.first.addShape(stroke));
    final savedStroke = parser.parse(
      writer.write(originalBytes: blank, edited: strokeDoc),
    );
    final strokeAfter = savedStroke.pages.first.findShapeById(2)!;
    expect(strokeAfter.shapeOpacity, 1);
    expect(strokeAfter.fill.hasFill, isTrue);
    expect(strokeAfter.fill.foregroundTransparency, closeTo(0.5, 1e-9));

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    expect(oracle.svgPages(saved)?.join() ?? '', isNotEmpty);
    _expectVsd2rawCollected(saved, const <String>[
      'draw:opacity',
    ]);
  });

  test('Label Border bakes a stroke sibling LibreOffice can collect', () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.6,
      height: 0.8,
      name: 'LabelBorderBox',
      fill: const VsdxFill(foreground: VsdxColor.white, pattern: 1),
      line: const VsdxLine(pattern: 0),
    )
        .copyWith(
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[VsdxTextRun(text: 'Hi')],
          ),
        )
        .withLabelBorderColor(const VsdxColor(0xFF1565C0));
    expect(shapeNeedsLibvisioLabelBorderBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    expect(
      baked.pages.first.shapes.where(isLibvisioLabelBorderPlate),
      hasLength(1),
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioLabelBorderPlate),
      hasLength(1),
      reason: 'a second save must not stack another Label Border stroke',
    );
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.labelBorderColor, isNull);
    expect(source.fill.foreground?.value, VsdxColor.white.value);
    final plate =
        baked.pages.first.shapes.firstWhere(isLibvisioLabelBorderPlate);
    expect(plate.name, '${kLibvisioLabelBorderShapeNamePrefix}1');
    expect(plate.locked, isTrue);
    expect(plate.fill.pattern, 0);
    expect(plate.line.pattern, 1);
    expect(plate.line.color?.value, 0xFF1565C0);
    expect(
      plate.line.weightInches,
      closeTo(1 / kLibvisioLabelBorderPxPerInch, 1e-12),
    );
    expect(plate.pinX, closeTo(2, 1e-9));
    expect(plate.pinY, closeTo(2, 1e-9));
    expect(plate.width, closeTo(1.6, 1e-9));
    expect(plate.height, closeTo(0.8, 1e-9));
    expect(
      plate.geometries.single.commands.whereType<RelLineTo>(),
      hasLength(4),
    );

    final custom = VsdxShapeFactory.rectangle(
      id: 2,
      pinX: 5,
      pinY: 3,
      width: 1.6,
      height: 0.8,
      fill: const VsdxFill(foreground: VsdxColor.white, pattern: 1),
      line: const VsdxLine(pattern: 0),
    )
        .copyWith(
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[VsdxTextRun(text: 'Hi')],
            textBlock: VsdxTextBlock(
              pinXInches: 0.2,
              pinYInches: 0.1,
              widthInches: 0.8,
              heightInches: 0.4,
            ),
          ),
        )
        .withLabelBorderColor(const VsdxColor(0xFFE53935));
    var customDoc = parser.parse(blank);
    customDoc =
        customDoc.replacePage(0, customDoc.pages.first.addShape(custom));
    final customPlate = documentForLibvisioWrite(customDoc)
        .pages
        .first
        .shapes
        .firstWhere(isLibvisioLabelBorderPlate);
    expect(customPlate.width, closeTo(0.8, 1e-9));
    expect(customPlate.height, closeTo(0.4, 1e-9));
    expect(customPlate.pinX, closeTo(4.4, 1e-9));
    expect(customPlate.pinY, closeTo(2.7, 1e-9));
    expect(customPlate.line.color?.value, 0xFFE53935);

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(savedDoc.pages.first.findShapeById(1)!.labelBorderColor, isNull);
    expect(
      savedDoc.pages.first.shapes.where(isLibvisioLabelBorderPlate),
      hasLength(1),
    );
    final savedPlate =
        savedDoc.pages.first.shapes.firstWhere(isLibvisioLabelBorderPlate);
    expect(savedPlate.line.color?.value, 0xFF1565C0);
    expect(savedPlate.fill.pattern, 0);
    expect(savedPlate.geometries.single.commands.whereType<RelLineTo>(),
        hasLength(4));

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    final after = oracle.svgPages(saved)?.join() ?? '';
    expect(after, isNotEmpty);
    _expectVsd2rawCollected(saved, const <String>[
      'svg:stroke-color: #1565c0',
    ]);
  });

  test('Label Padding bakes into Margin cells LibreOffice can collect', () {
    const pad = VsdxLabelPadding(top: 12, right: 24, bottom: 36, left: 48);
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.6,
      height: 0.8,
      name: 'LabelPaddingBox',
      fill: const VsdxFill(foreground: VsdxColor.white, pattern: 1),
      line: const VsdxLine(pattern: 0),
    )
        .copyWith(
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[VsdxTextRun(text: 'Hi')],
            textBlock: VsdxTextBlock(
              marginLeftInches: 0,
              marginRightInches: 0,
              marginTopInches: 0,
              marginBottomInches: 0,
            ),
          ),
        )
        .withLabelPadding(pad);
    expect(shapeNeedsLibvisioLabelPaddingBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.labelPadding.isZero, isTrue);
    expect(
      source.richText.textBlock.marginLeftInches,
      closeTo(48 / kLibvisioLabelPaddingPxPerInch, 1e-12),
    );
    expect(
      source.richText.textBlock.marginRightInches,
      closeTo(24 / kLibvisioLabelPaddingPxPerInch, 1e-12),
    );
    expect(
      source.richText.textBlock.marginTopInches,
      closeTo(12 / kLibvisioLabelPaddingPxPerInch, 1e-12),
    );
    expect(
      source.richText.textBlock.marginBottomInches,
      closeTo(36 / kLibvisioLabelPaddingPxPerInch, 1e-12),
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .findShapeById(1)!
          .richText
          .textBlock
          .marginLeftInches,
      closeTo(48 / kLibvisioLabelPaddingPxPerInch, 1e-12),
      reason: 'a second save must not stack another inset',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    final after = savedDoc.pages.first.findShapeById(1)!;
    expect(after.labelPadding.isZero, isTrue);
    expect(
      after.richText.textBlock.marginLeftInches,
      closeTo(0.5, 1e-9),
    );
    expect(
      after.richText.textBlock.marginRightInches,
      closeTo(0.25, 1e-9),
    );

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    final svg = oracle.svgPages(saved)?.join() ?? '';
    expect(svg, isNotEmpty);
    _expectVsd2rawCollected(saved, const <String>[
      'fo:padding-left',
    ]);
  });

  test('Word Wrap off bakes TxtWidth LibreOffice wraps against', () {
    const label = 'NO WRAP NO WRAP NO WRAP';
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 0.8,
      height: 0.6,
      name: 'WordWrapBox',
      fill: const VsdxFill(foreground: VsdxColor.white, pattern: 1),
      line: const VsdxLine(pattern: 0),
    ).copyWith(
      formulas: const <String, String>{
        'TxtWidth': 'Width*1',
        'TxtLocPinX': 'TxtWidth*0.5',
      },
      richText: const VsdxRichText(
        runs: <VsdxTextRun>[VsdxTextRun(text: label)],
      ),
    ).withWordWrap(false);
    expect(shapeNeedsLibvisioWordWrapBake(shape), isTrue);
    final needed = nowrapTxtWidthForLibvisioWrite(shape);
    expect(needed, greaterThan(0.8));

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.wordWrap, isTrue);
    expect(source.formulas['TxtWidth'], isNull);
    expect(source.formulas['TxtLocPinX'], isNull);
    expect(source.richText.textBlock.widthInches, closeTo(needed, 1e-9));
    expect(
      source.richText.textBlock.locPinXInches,
      closeTo(0.4, 1e-9),
      reason: 'left-aligned overflow must keep the original left edge',
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .findShapeById(1)!
          .richText
          .textBlock
          .widthInches,
      closeTo(needed, 1e-9),
      reason: 'a second save must not stack another TxtWidth',
    );

    final centered = VsdxShapeFactory.rectangle(
      id: 2,
      pinX: 5,
      pinY: 2,
      width: 0.8,
      height: 0.6,
      fill: const VsdxFill(foreground: VsdxColor.white, pattern: 1),
      line: const VsdxLine(pattern: 0),
    )
        .copyWith(
          richText: VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: label,
                paraStyle: const VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.center,
                ),
              ),
            ],
          ),
        )
        .withWordWrap(false);
    var centerDoc = parser.parse(blank);
    centerDoc =
        centerDoc.replacePage(0, centerDoc.pages.first.addShape(centered));
    final centerBlock = documentForLibvisioWrite(centerDoc)
        .pages
        .first
        .findShapeById(2)!
        .richText
        .textBlock;
    expect(
      centerBlock.widthInches,
      closeTo(nowrapTxtWidthForLibvisioWrite(centered), 1e-9),
    );
    expect(
      centerBlock.locPinXInches,
      closeTo(centerBlock.widthInches! / 2, 1e-9),
      reason: 'centered overflow must grow equally on both sides',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    final after = savedDoc.pages.first.findShapeById(1)!;
    expect(after.wordWrap, isTrue);
    expect(after.richText.textBlock.widthInches, closeTo(needed, 1e-6));

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    expect(oracle.svgPages(saved)?.join() ?? '', isNotEmpty);
  });

  test('geometry SoftEdges bakes a feathered PNG sibling for LibreOffice', () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.2,
      height: 0.8,
      name: 'GeometrySoft',
      fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
      line: const VsdxLine(pattern: 0, softEdgesInches: 0.08),
    );
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.fill.pattern, 0);
    expect(source.line.softEdgesInches, closeTo(0, 1e-9));
    final plates = baked.pages.first.shapes.where(isLibvisioSoftEdgesPlate);
    expect(plates, hasLength(1));
    final plate = plates.single;
    expect(plate.locked, isTrue);
    expect(plate.hasImage, isTrue);
    expect(plate.pinX, closeTo(2, 1e-9));
    final png = baked.images.findByPart(plate.imagePartName!);
    expect(png, isNotNull);
    final decoded = raster.decodePng(png!.bytes);
    expect(decoded, isNotNull);
    expect(
      decoded!.getPixel(0, 0).a,
      lessThan(decoded.getPixel(decoded.width ~/ 2, decoded.height ~/ 2).a),
      reason: 'SourceAlpha feather must fade the silhouette edge',
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioSoftEdgesPlate),
      hasLength(1),
      reason: 'a second save must not stack another SoftEdges plate',
    );

    final oval = VsdxShapeFactory.ellipse(
      id: 2,
      pinX: 5,
      pinY: 2,
      width: 1.2,
      height: 0.8,
      fill: const VsdxFill(foreground: VsdxColor(0xFF1565C0), pattern: 1),
      line: const VsdxLine(pattern: 0, softEdgesInches: 0.08),
    );
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(oval), isTrue);
    var ovalDoc = parser.parse(blank);
    ovalDoc = ovalDoc.replacePage(0, ovalDoc.pages.first.addShape(oval));
    final ovalBaked = documentForLibvisioWrite(ovalDoc);
    final ovalPlate =
        ovalBaked.pages.first.shapes.where(isLibvisioSoftEdgesPlate).single;
    final ovalPng = ovalBaked.images.findByPart(ovalPlate.imagePartName!);
    final ovalDecoded = raster.decodePng(ovalPng!.bytes)!;
    expect(
      ovalDecoded.getPixel(0, 0).a,
      lessThan(20),
      reason: 'ellipse SoftEdges PNG must keep corners empty',
    );
    expect(
      ovalDecoded.getPixel(ovalDecoded.width ~/ 2, ovalDecoded.height ~/ 2).a,
      greaterThan(200),
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(savedDoc.pages.first.findShapeById(1)!.fill.pattern, 0);
    expect(
      savedDoc.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
      hasLength(1),
    );

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    expect(oracle.svgPages(saved)?.join() ?? '', isNotEmpty);
  });

  test('gradient fill SoftEdges bakes a feathered wash PNG for LibreOffice',
      () {
    const wash = VsdxGradient(
      stops: <VsdxGradientStop>[
        VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
        VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
      ],
    );
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.2,
      height: 0.8,
      name: 'GradientSoft',
      fill: const VsdxFill(pattern: 1, gradient: wash),
      line: const VsdxLine(pattern: 0, softEdgesInches: 0.08),
    );
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.fill.pattern, 0);
    expect(source.fill.hasGradient, isFalse);
    expect(source.line.softEdgesInches, closeTo(0, 1e-9));
    final plate =
        baked.pages.first.shapes.where(isLibvisioSoftEdgesPlate).single;
    final png = baked.images.findByPart(plate.imagePartName!);
    expect(png, isNotNull);
    final decoded = raster.decodePng(png!.bytes)!;
    final left = decoded.getPixel(decoded.width ~/ 4, decoded.height ~/ 2);
    final right = decoded.getPixel(decoded.width * 3 ~/ 4, decoded.height ~/ 2);
    expect(
      left.r,
      greaterThan(right.r + 40),
      reason: 'SoftEdges PNG must keep the left-red right-blue wash, '
          'not a solid classic FillPattern; left=$left right=$right',
    );
    expect(
      right.b,
      greaterThan(left.b + 40),
      reason: 'SoftEdges PNG must keep the left-red right-blue wash; '
          'left=$left right=$right',
    );
    expect(
      decoded.getPixel(0, 0).a,
      lessThan(decoded.getPixel(decoded.width ~/ 2, decoded.height ~/ 2).a),
      reason: 'SourceAlpha feather must fade the silhouette edge',
    );

    final classic = VsdxShapeFactory.rectangle(
      id: 2,
      pinX: 5,
      pinY: 2,
      width: 1.2,
      height: 0.8,
      fill: const VsdxFill(
        foreground: VsdxColor(0xFFFF0000),
        background: VsdxColor(0xFF0000FF),
        pattern: 27,
      ),
      line: const VsdxLine(pattern: 0, softEdgesInches: 0.08),
    );
    expect(classic.fill.paintGradient, isNotNull);
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(classic), isTrue);
    var classicDoc = parser.parse(blank);
    classicDoc =
        classicDoc.replacePage(0, classicDoc.pages.first.addShape(classic));
    expect(
      documentForLibvisioWrite(classicDoc)
          .pages
          .first
          .findShapeById(2)!
          .fill
          .pattern,
      0,
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(savedDoc.pages.first.findShapeById(1)!.fill.pattern, 0);
    expect(
      savedDoc.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
      hasLength(1),
    );

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    expect(oracle.svgPages(saved)?.join() ?? '', isNotEmpty);
  });

  test('hatch fill SoftEdges bakes a feathered hatch PNG for LibreOffice', () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.2,
      height: 0.8,
      name: 'HatchSoft',
      fill: const VsdxFill(
        foreground: VsdxColor(0xFFFF0000),
        background: VsdxColor(0xFF0000FF),
        pattern: 6,
      ),
      line: const VsdxLine(pattern: 0, softEdgesInches: 0.08),
    );
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.fill.pattern, 0);
    expect(source.line.softEdgesInches, closeTo(0, 1e-9));
    final plate =
        baked.pages.first.shapes.where(isLibvisioSoftEdgesPlate).single;
    final png = baked.images.findByPart(plate.imagePartName!);
    expect(png, isNotNull);
    final decoded = raster.decodePng(png!.bytes)!;
    var redInk = 0;
    var blueInk = 0;
    final x = decoded.width ~/ 2;
    for (var y = decoded.height ~/ 4; y < decoded.height * 3 ~/ 4; y++) {
      final p = decoded.getPixel(x, y);
      if (p.a < 80) continue;
      if (p.r > p.b + 40) redInk++;
      if (p.b > p.r + 40) blueInk++;
    }
    expect(
      redInk,
      greaterThan(2),
      reason: 'SoftEdges PNG must keep FillPattern 6 red strokes; '
          'redInk=$redInk blueInk=$blueInk',
    );
    expect(
      blueInk,
      greaterThan(redInk),
      reason: 'SoftEdges PNG must keep the blue hatch background; '
          'redInk=$redInk blueInk=$blueInk',
    );
    expect(
      decoded.getPixel(0, 0).a,
      lessThan(decoded.getPixel(decoded.width ~/ 2, decoded.height ~/ 2).a),
      reason: 'SourceAlpha feather must fade the silhouette edge',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(savedDoc.pages.first.findShapeById(1)!.fill.pattern, 0);
    expect(
      savedDoc.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
      hasLength(1),
    );

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    expect(oracle.svgPages(saved)?.join() ?? '', isNotEmpty);
  });

  test('gradient and hatch SoftEdges strokes join the feathered plate', () {
    const wash = VsdxGradient(
      stops: <VsdxGradientStop>[
        VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
        VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
      ],
    );
    final gradient = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 1.2,
      name: 'GradStrokeSoft',
      fill: const VsdxFill(pattern: 1, gradient: wash),
      line: const VsdxLine(
        color: VsdxColor(0xFF000000),
        weightInches: 0.16,
        softEdgesInches: 0.12,
      ),
    );
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(gradient), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(gradient));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.fill.pattern, 0);
    expect(source.fill.hasGradient, isFalse);
    expect(source.line.pattern, 0);
    expect(source.line.softEdgesInches, closeTo(0, 1e-9));
    final plate =
        baked.pages.first.shapes.where(isLibvisioSoftEdgesPlate).single;
    expect(plate.width, greaterThan(2.0));
    final png = baked.images.findByPart(plate.imagePartName!);
    expect(png, isNotNull);
    final decoded = raster.decodePng(png!.bytes)!;
    const padInches = 0.16 / 2 + 0.12 * 3;
    const plateW = 2 + 2 * padInches;
    const plateH = 1.2 + 2 * padInches;
    ({int r, int g, int b}) sample(double visioX, double visioY) {
      final x = ((padInches + visioX) / plateW * decoded.width)
          .round()
          .clamp(1, decoded.width - 2);
      final y = ((padInches + (1.2 - visioY)) / plateH * decoded.height)
          .round()
          .clamp(1, decoded.height - 2);
      final pixel = decoded.getPixel(x, y);
      return (r: pixel.r.toInt(), g: pixel.g.toInt(), b: pixel.b.toInt());
    }

    final left = sample(0.35, 0.6);
    final right = sample(1.65, 0.6);
    expect(
      left.r,
      greaterThan(right.r + 40),
      reason: 'gradient+stroke SoftEdges PNG must keep the wash; '
          'left=$left right=$right',
    );
    expect(
      right.b,
      greaterThan(left.b + 40),
      reason: 'gradient+stroke SoftEdges PNG must keep the wash; '
          'left=$left right=$right',
    );
    var ringLuma = 255.0;
    final midY = ((padInches + 0.6) / plateH * decoded.height)
        .round()
        .clamp(1, decoded.height - 2);
    final x0 = ((padInches - 0.04) / plateW * decoded.width).round();
    final x1 = ((padInches + 0.12) / plateW * decoded.width).round();
    for (var x = x0; x < x1; x++) {
      final pixel = decoded.getPixel(x.clamp(0, decoded.width - 1), midY);
      final luma = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
      if (luma < ringLuma) ringLuma = luma;
    }
    expect(
      ringLuma,
      lessThan(80),
      reason: 'gradient SoftEdges PNG must paint the black stroke; '
          'ring=$ringLuma',
    );

    final hatch = VsdxShapeFactory.rectangle(
      id: 2,
      pinX: 5,
      pinY: 2,
      width: 2,
      height: 1.2,
      fill: const VsdxFill(
        foreground: VsdxColor(0xFFFF0000),
        background: VsdxColor(0xFF0000FF),
        pattern: 6,
      ),
      line: const VsdxLine(
        color: VsdxColor(0xFF000000),
        weightInches: 0.16,
        pattern: 2,
        softEdgesInches: 0.12,
      ),
    );
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(hatch), isTrue);
    var hatchDoc = parser.parse(blank);
    hatchDoc = hatchDoc.replacePage(0, hatchDoc.pages.first.addShape(hatch));
    final hatchBaked = documentForLibvisioWrite(hatchDoc);
    expect(hatchBaked.pages.first.findShapeById(2)!.fill.pattern, 0);
    expect(hatchBaked.pages.first.findShapeById(2)!.line.pattern, 0,
        reason: 'hatch dashed SoftEdges bakes dashes into the fill plate');
    final hatchPlate =
        hatchBaked.pages.first.shapes.where(isLibvisioSoftEdgesPlate).single;
    final hatchPng = hatchBaked.images.findByPart(hatchPlate.imagePartName!);
    expect(hatchPng, isNotNull);
    final hatchDecoded = raster.decodePng(hatchPng!.bytes)!;
    var dashInk = 0;
    var dashGap = 0;
    final row = ((padInches + 1.15) / plateH * hatchDecoded.height)
        .round()
        .clamp(1, hatchDecoded.height - 2);
    final hx0 = (padInches / plateW * hatchDecoded.width).round();
    final hx1 = ((padInches + 2) / plateW * hatchDecoded.width).round();
    for (var x = hx0; x < hx1; x++) {
      final pixel = hatchDecoded.getPixel(x, row);
      final luma = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
      if (luma < 80) dashInk++;
      if (luma > 80 && (pixel.r > 120 || pixel.b > 120)) dashGap++;
    }
    expect(dashInk, greaterThan(4),
        reason: 'must paint black dashes over the hatch; ink=$dashInk');
    expect(dashGap, greaterThan(4),
        reason: 'gaps must show the hatch, not a solid ring; gap=$dashGap');

    final saved = writer.write(originalBytes: blank, edited: doc);
    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    expect(oracle.svgPages(saved)?.join() ?? '', isNotEmpty);
  });

  test('compound SoftEdges bakes feathered rails for LibreOffice', () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 1.2,
      name: 'CompoundSoft',
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(
        color: VsdxColor(0xFF000000),
        weightInches: 0.24,
        compoundType: 1,
        softEdgesInches: 0.1,
      ),
    );
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(shape), isTrue);
    expect(shapeNeedsLibvisioCompoundBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.line.pattern, 0);
    expect(source.line.compoundType, 0);
    expect(source.line.softEdgesInches, closeTo(0, 1e-9));
    final plate =
        baked.pages.first.shapes.where(isLibvisioSoftEdgesPlate).single;
    expect(plate.width, greaterThan(2.0));
    final png = baked.images.findByPart(plate.imagePartName!);
    expect(png, isNotNull);
    final decoded = raster.decodePng(png!.bytes)!;
    expect(
      decoded.getPixel(decoded.width ~/ 2, decoded.height ~/ 2).r,
      greaterThan(200),
      reason: 'compound SoftEdges PNG must keep the hollow interior empty',
    );
    const weight = 0.24;
    const soft = 0.1;
    const padInches = weight / 2 + soft * 3;
    const plateW = 2 + 2 * padInches;
    const plateH = 1.2 + 2 * padInches;
    final midY = ((padInches + 0.6) / plateH * decoded.height)
        .round()
        .clamp(1, decoded.height - 2);
    var darkBands = 0;
    var inDark = false;
    final x0 = ((padInches - weight) / plateW * decoded.width)
        .round()
        .clamp(0, decoded.width - 1);
    final x1 = ((padInches + weight) / plateW * decoded.width)
        .round()
        .clamp(0, decoded.width - 1);
    for (var x = x0; x <= x1; x++) {
      final pixel = decoded.getPixel(x, midY);
      final luma = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
      final dark = luma < 180;
      if (dark && !inDark) {
        darkBands++;
        inDark = true;
      } else if (!dark) {
        inDark = false;
      }
    }
    expect(
      darkBands,
      greaterThanOrEqualTo(2),
      reason: 'compound type 1 must paint two feathered rails, not a solid '
          'ring; bands=$darkBands',
    );

    final filled = VsdxShapeFactory.rectangle(
      id: 2,
      pinX: 5,
      pinY: 2,
      width: 2,
      height: 1.2,
      fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
      line: const VsdxLine(
        color: VsdxColor(0xFF000000),
        weightInches: 0.24,
        compoundType: 1,
        softEdgesInches: 0.1,
      ),
    );
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(filled), isTrue);
    var filledDoc = parser.parse(blank);
    filledDoc =
        filledDoc.replacePage(0, filledDoc.pages.first.addShape(filled));
    final filledBaked = documentForLibvisioWrite(filledDoc);
    expect(filledBaked.pages.first.findShapeById(2)!.fill.pattern, 0);
    expect(filledBaked.pages.first.findShapeById(2)!.line.pattern, 0);
    expect(filledBaked.pages.first.findShapeById(2)!.line.compoundType, 0);
    final filledPlate =
        filledBaked.pages.first.shapes.where(isLibvisioSoftEdgesPlate).single;
    final filledPng = filledBaked.images.findByPart(filledPlate.imagePartName!);
    final filledDecoded = raster.decodePng(filledPng!.bytes)!;
    final centre = filledDecoded.getPixel(
      filledDecoded.width ~/ 2,
      filledDecoded.height ~/ 2,
    );
    expect(centre.r, greaterThan(180),
        reason: 'filled compound SoftEdges PNG must keep the red interior');
    expect(centre.g, lessThan(80));

    final saved = writer.write(originalBytes: blank, edited: doc);
    final writerBaked = parser.parse(saved);
    expect(writerBaked.pages.first.findShapeById(1)!.line.compoundType, 0);
    expect(
      writerBaked.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
      hasLength(1),
      reason: 'compound SoftEdges must not also emit Geometry rails',
    );
    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    expect(oracle.svgPages(saved)?.join() ?? '', isNotEmpty);
  });

  test('LineGradient SoftEdges bakes the wash into the feathered plate', () {
    const wash = VsdxGradient(
      stops: <VsdxGradientStop>[
        VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
        VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
      ],
    );
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 1.2,
      name: 'LineGradSoft',
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(
        color: VsdxColor(0xFF000000),
        weightInches: 0.16,
        softEdgesInches: 0.12,
        gradient: wash,
      ),
    );
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(shape), isTrue);
    expect(shapeNeedsLibvisioStrokeRibbon(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.line.pattern, 0);
    expect(source.line.hasGradient, isFalse);
    expect(source.line.softEdgesInches, closeTo(0, 1e-9));
    final plate =
        baked.pages.first.shapes.where(isLibvisioSoftEdgesPlate).single;
    expect(plate.width, greaterThan(2.0));
    final png = baked.images.findByPart(plate.imagePartName!);
    expect(png, isNotNull);
    final decoded = raster.decodePng(png!.bytes)!;
    const padInches = 0.16 / 2 + 0.12 * 3;
    const plateW = 2 + 2 * padInches;
    const plateH = 1.2 + 2 * padInches;
    ({int r, int g, int b}) sample(double visioX, double visioY) {
      final x = ((padInches + visioX) / plateW * decoded.width)
          .round()
          .clamp(1, decoded.width - 2);
      final y = ((padInches + (1.2 - visioY)) / plateH * decoded.height)
          .round()
          .clamp(1, decoded.height - 2);
      final pixel = decoded.getPixel(x, y);
      return (r: pixel.r.toInt(), g: pixel.g.toInt(), b: pixel.b.toInt());
    }

    final left = sample(0, 0.6);
    final right = sample(2, 0.6);
    final centre = sample(1, 0.6);
    expect(
      left.r,
      greaterThan(right.r + 30),
      reason: 'LineGradient SoftEdges PNG must keep the red-to-blue wash; '
          'left=$left right=$right',
    );
    expect(
      right.b,
      greaterThan(left.b + 30),
      reason: 'LineGradient SoftEdges PNG must keep the red-to-blue wash; '
          'left=$left right=$right',
    );
    expect(
      centre.r,
      greaterThan(200),
      reason: 'unfilled LineGradient SoftEdges must keep the hollow interior; '
          'centre=$centre',
    );

    final filled = VsdxShapeFactory.rectangle(
      id: 2,
      pinX: 5,
      pinY: 2,
      width: 2,
      height: 1.2,
      fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
      line: const VsdxLine(
        color: VsdxColor(0xFF000000),
        weightInches: 0.16,
        softEdgesInches: 0.12,
        gradient: wash,
      ),
    );
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(filled), isTrue);
    var filledDoc = parser.parse(blank);
    filledDoc =
        filledDoc.replacePage(0, filledDoc.pages.first.addShape(filled));
    final filledBaked = documentForLibvisioWrite(filledDoc);
    expect(filledBaked.pages.first.findShapeById(2)!.fill.pattern, 0);
    expect(filledBaked.pages.first.findShapeById(2)!.line.pattern, 0);
    expect(filledBaked.pages.first.findShapeById(2)!.line.hasGradient, isFalse);
    final filledPlate =
        filledBaked.pages.first.shapes.where(isLibvisioSoftEdgesPlate).single;
    final filledPng = filledBaked.images.findByPart(filledPlate.imagePartName!);
    final filledDecoded = raster.decodePng(filledPng!.bytes)!;
    ({int r, int g, int b}) filledSample(double visioX, double visioY) {
      final x = ((padInches + visioX) / plateW * filledDecoded.width)
          .round()
          .clamp(1, filledDecoded.width - 2);
      final y = ((padInches + (1.2 - visioY)) / plateH * filledDecoded.height)
          .round()
          .clamp(1, filledDecoded.height - 2);
      final pixel = filledDecoded.getPixel(x, y);
      return (r: pixel.r.toInt(), g: pixel.g.toInt(), b: pixel.b.toInt());
    }

    final filledCentre = filledSample(1, 0.6);
    final filledRight = filledSample(2, 0.6);
    expect(filledCentre.r, greaterThan(180),
        reason: 'filled LineGradient SoftEdges must keep the red body; '
            'centre=$filledCentre');
    expect(filledCentre.b, lessThan(80),
        reason: 'filled interior must stay red, not the stroke wash; '
            'centre=$filledCentre');
    expect(
      filledRight.b,
      greaterThan(filledCentre.b + 30),
      reason: 'filled LineGradient SoftEdges must paint the blue end of the '
          'stroke wash; centre=$filledCentre right=$filledRight',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final writerBaked = parser.parse(saved);
    expect(writerBaked.pages.first.findShapeById(1)!.line.hasGradient, isFalse);
    expect(
      writerBaked.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
      hasLength(1),
    );
    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    expect(oracle.svgPages(saved)?.join() ?? '', isNotEmpty);
  });

  test('Rounding SoftEdges bakes filleted corners for LibreOffice', () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 1.2,
      name: 'RoundSoft',
      fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
      line: const VsdxLine(
        pattern: 0,
        roundingInches: 0.45,
        softEdgesInches: 0.04,
      ),
    );
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.fill.pattern, 0);
    expect(source.line.softEdgesInches, closeTo(0, 1e-9));
    final plate =
        baked.pages.first.shapes.where(isLibvisioSoftEdgesPlate).single;
    final png = baked.images.findByPart(plate.imagePartName!);
    expect(png, isNotNull);
    final decoded = raster.decodePng(png!.bytes)!;
    final corner = decoded.getPixel(0, 0);
    final centre = decoded.getPixel(decoded.width ~/ 2, decoded.height ~/ 2);
    expect(
      corner.a,
      lessThan(40),
      reason: 'Rounding SoftEdges PNG must keep the filleted corner empty; '
          'cornerA=${corner.a} centreA=${centre.a}',
    );
    expect(
      centre.r,
      greaterThan(180),
      reason: 'Rounding SoftEdges PNG must keep the red body; '
          'centre=$centre',
    );
    expect(
      centre.a,
      greaterThan(200),
      reason: 'Rounding SoftEdges PNG must keep the interior opaque; '
          'centreA=${centre.a}',
    );
    final midTop = decoded.getPixel(decoded.width ~/ 2, 1);
    expect(
      midTop.a,
      greaterThan(corner.a + 40),
      reason: 'mid-edge must still paint; midTopA=${midTop.a} '
          'cornerA=${corner.a}',
    );

    final stroked = VsdxShapeFactory.rectangle(
      id: 2,
      pinX: 5,
      pinY: 2,
      width: 2,
      height: 1.2,
      fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
      line: const VsdxLine(
        color: VsdxColor(0xFF000000),
        weightInches: 0.12,
        roundingInches: 0.45,
        softEdgesInches: 0.04,
      ),
    );
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(stroked), isTrue);
    var strokedDoc = parser.parse(blank);
    strokedDoc =
        strokedDoc.replacePage(0, strokedDoc.pages.first.addShape(stroked));
    final strokedBaked = documentForLibvisioWrite(strokedDoc);
    expect(strokedBaked.pages.first.findShapeById(2)!.fill.pattern, 0);
    expect(strokedBaked.pages.first.findShapeById(2)!.line.pattern, 0);
    final strokedPlate =
        strokedBaked.pages.first.shapes.where(isLibvisioSoftEdgesPlate).single;
    expect(strokedPlate.width, greaterThan(2.0));
    final strokedPng =
        strokedBaked.images.findByPart(strokedPlate.imagePartName!);
    final strokedDecoded = raster.decodePng(strokedPng!.bytes)!;
    final strokedCorner = strokedDecoded.getPixel(0, 0);
    final strokedCentre = strokedDecoded.getPixel(
      strokedDecoded.width ~/ 2,
      strokedDecoded.height ~/ 2,
    );
    expect(
      strokedCorner.r,
      greaterThan(200),
      reason: 'padded rounded SoftEdges must keep the bbox corner empty; '
          'corner=$strokedCorner',
    );
    expect(
      strokedCentre.r,
      greaterThan(180),
      reason: 'padded rounded SoftEdges must keep the red body; '
          'centre=$strokedCentre',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final writerBaked = parser.parse(saved);
    expect(writerBaked.pages.first.findShapeById(1)!.fill.pattern, 0);
    expect(
      writerBaked.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
      hasLength(1),
    );
    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    expect(oracle.svgPages(saved)?.join() ?? '', isNotEmpty);
  });

  test('unfilled stroke SoftEdges bakes a feathered PNG ring for LibreOffice',
      () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.2,
      height: 0.8,
      name: 'StrokeSoft',
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(
        color: VsdxColor(0xFF000000),
        weightInches: 0.1,
        softEdgesInches: 0.08,
      ),
    );
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(shape), isTrue);
    expect(
      shapeNeedsLibvisioGeometrySoftEdgesBake(
        VsdxShapeFactory.rectangle(
          id: 9,
          pinX: 2,
          pinY: 2,
          width: 1.2,
          height: 0.8,
          fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
          line: const VsdxLine(
            color: VsdxColor(0xFF000000),
            weightInches: 0.04,
            pattern: 2,
            softEdgesInches: 0.08,
          ),
        ),
      ),
      isTrue,
      reason: 'filled SoftEdges still bakes; dashed stroke joins the plate',
    );

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.fill.pattern, 0);
    expect(source.line.pattern, 0);
    expect(source.line.softEdgesInches, closeTo(0, 1e-9));
    final plates = baked.pages.first.shapes.where(isLibvisioSoftEdgesPlate);
    expect(plates, hasLength(1));
    final plate = plates.single;
    expect(plate.locked, isTrue);
    expect(plate.hasImage, isTrue);
    expect(plate.width, greaterThan(source.width + 0.05));
    final png = baked.images.findByPart(plate.imagePartName!);
    expect(png, isNotNull);
    final decoded = raster.decodePng(png!.bytes)!;
    expect(
      decoded.getPixel(decoded.width ~/ 2, decoded.height ~/ 2).r,
      greaterThan(200),
      reason: 'stroke SoftEdges PNG must keep the hollow interior empty',
    );
    var ringLuma = 255.0;
    final midY = decoded.height ~/ 2;
    for (var x = 0; x < decoded.width ~/ 3; x++) {
      final pixel = decoded.getPixel(x, midY);
      final luma = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
      if (luma < ringLuma) ringLuma = luma;
    }
    expect(
      ringLuma,
      lessThan(180),
      reason: 'stroke SoftEdges PNG must paint the feathered ring',
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioSoftEdgesPlate),
      hasLength(1),
      reason: 'a second save must not stack another SoftEdges plate',
    );

    final oval = VsdxShapeFactory.ellipse(
      id: 2,
      pinX: 5,
      pinY: 2,
      width: 1.2,
      height: 0.8,
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(
        color: VsdxColor(0xFF1565C0),
        weightInches: 0.1,
        softEdgesInches: 0.08,
      ),
    );
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(oval), isTrue);
    var ovalDoc = parser.parse(blank);
    ovalDoc = ovalDoc.replacePage(0, ovalDoc.pages.first.addShape(oval));
    final ovalBaked = documentForLibvisioWrite(ovalDoc);
    final ovalPlate =
        ovalBaked.pages.first.shapes.where(isLibvisioSoftEdgesPlate).single;
    final ovalPng = ovalBaked.images.findByPart(ovalPlate.imagePartName!);
    final ovalDecoded = raster.decodePng(ovalPng!.bytes)!;
    expect(
      ovalDecoded.getPixel(ovalDecoded.width ~/ 2, ovalDecoded.height ~/ 2).r,
      greaterThan(200),
      reason: 'ellipse stroke SoftEdges PNG must stay hollow',
    );
    expect(
      ovalDecoded.getPixel(0, 0).r,
      greaterThan(200),
      reason: 'ellipse stroke SoftEdges PNG must keep corners empty',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(savedDoc.pages.first.findShapeById(1)!.line.pattern, 0);
    expect(
      savedDoc.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
      hasLength(1),
    );

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    expect(oracle.svgPages(saved)?.join() ?? '', isNotEmpty);
  });

  test('unfilled dashed SoftEdges bakes per-dash ribbons for LibreOffice', () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 1.2,
      name: 'DashSoft',
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(
        color: VsdxColor(0xFF000000),
        weightInches: 0.16,
        pattern: 2,
        softEdgesInches: 0.12,
      ),
    );
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.line.pattern, 0);
    expect(source.line.softEdgesInches, closeTo(0, 1e-9));
    final plates = baked.pages.first.shapes.where(isLibvisioSoftEdgesPlate);
    expect(plates, hasLength(1));
    final png = baked.images.findByPart(plates.single.imagePartName!);
    expect(png, isNotNull);
    final decoded = raster.decodePng(png!.bytes)!;
    expect(
      decoded.getPixel(decoded.width ~/ 2, decoded.height ~/ 2).r,
      greaterThan(200),
      reason: 'dashed SoftEdges PNG must keep the hollow interior empty',
    );
    var dark = 0;
    var light = 0;
    const padInches = 0.16 / 2 + 0.12 * 3;
    const plateW = 2 + 2 * padInches;
    const plateH = 1.2 + 2 * padInches;
    final row = ((padInches + 1.2) / plateH * decoded.height)
        .round()
        .clamp(1, decoded.height - 2);
    final x0 = (padInches / plateW * decoded.width).round();
    final x1 = ((padInches + 2) / plateW * decoded.width).round();
    for (var x = x0; x < x1; x++) {
      final pixel = decoded.getPixel(x, row);
      final luma = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
      if (luma < 180) dark++;
      if (luma > 220) light++;
    }
    expect(dark, greaterThan(4), reason: 'must paint dash ink; dark=$dark');
    expect(light, greaterThan(4),
        reason: 'must keep dash gaps empty; light=$light dark=$dark');
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioSoftEdgesPlate),
      hasLength(1),
      reason: 'a second save must not stack another SoftEdges plate',
    );
  });

  test('filled+stroked SoftEdges bakes one feathered PNG for LibreOffice', () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.2,
      height: 0.8,
      name: 'FillStrokeSoft',
      fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
      line: const VsdxLine(
        color: VsdxColor(0xFF000000),
        weightInches: 0.08,
        softEdgesInches: 0.08,
      ),
    );
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(shape), isTrue);

    final dashed = VsdxShapeFactory.rectangle(
      id: 9,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 1.2,
      fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
      line: const VsdxLine(
        color: VsdxColor(0xFF000000),
        weightInches: 0.16,
        pattern: 2,
        softEdgesInches: 0.12,
      ),
    );
    final blank = writer.emptyDocument();
    var dashedDoc = parser.parse(blank);
    dashedDoc =
        dashedDoc.replacePage(0, dashedDoc.pages.first.addShape(dashed));
    final dashedBaked = documentForLibvisioWrite(dashedDoc);
    expect(dashedBaked.pages.first.findShapeById(9)!.fill.pattern, 0);
    expect(dashedBaked.pages.first.findShapeById(9)!.line.pattern, 0,
        reason: 'filled dashed SoftEdges bakes dashes into the fill plate');
    expect(
      dashedBaked.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
      hasLength(1),
    );
    expect(
      dashedBaked.pages.first.shapes.firstWhere(isLibvisioSoftEdgesPlate).width,
      greaterThan(2.0),
    );
    final dashedPng = dashedBaked.images.findByPart(
      dashedBaked.pages.first.shapes
          .firstWhere(isLibvisioSoftEdgesPlate)
          .imagePartName!,
    );
    expect(dashedPng, isNotNull);
    final dashedDecoded = raster.decodePng(dashedPng!.bytes)!;
    final dashedCentre = dashedDecoded.getPixel(
      dashedDecoded.width ~/ 2,
      dashedDecoded.height ~/ 2,
    );
    expect(dashedCentre.r, greaterThan(180),
        reason: 'filled dashed SoftEdges PNG must keep the red interior');
    expect(dashedCentre.g, lessThan(80));
    var dashInk = 0;
    var dashGap = 0;
    const padInches = 0.16 / 2 + 0.12 * 3;
    const plateW = 2 + 2 * padInches;
    const plateH = 1.2 + 2 * padInches;
    // Inner half of the 0.16" stroke, 0.05" above visio y=0, so dash
    // gaps show the red fill instead of the feathered outer halo.
    final row = ((padInches + 1.15) / plateH * dashedDecoded.height)
        .round()
        .clamp(1, dashedDecoded.height - 2);
    final x0 = (padInches / plateW * dashedDecoded.width).round();
    final x1 = ((padInches + 2) / plateW * dashedDecoded.width).round();
    for (var x = x0; x < x1; x++) {
      final pixel = dashedDecoded.getPixel(x, row);
      final luma = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
      if (luma < 80) dashInk++;
      if (pixel.r > 150 && pixel.g < 100) dashGap++;
    }
    expect(dashInk, greaterThan(4),
        reason: 'must paint black dashes over the fill; ink=$dashInk');
    expect(dashGap, greaterThan(4),
        reason: 'gaps must show the red fill, not a solid ring; gap=$dashGap');

    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.fill.pattern, 0);
    expect(source.line.pattern, 0);
    expect(source.line.softEdgesInches, closeTo(0, 1e-9));
    final plates = baked.pages.first.shapes.where(isLibvisioSoftEdgesPlate);
    expect(plates, hasLength(1));
    final plate = plates.single;
    expect(plate.locked, isTrue);
    expect(plate.hasImage, isTrue);
    expect(plate.width, greaterThan(source.width + 0.05));
    final png = baked.images.findByPart(plate.imagePartName!);
    expect(png, isNotNull);
    final decoded = raster.decodePng(png!.bytes)!;
    final centre = decoded.getPixel(decoded.width ~/ 2, decoded.height ~/ 2);
    expect(centre.r, greaterThan(180),
        reason: 'filled+stroked SoftEdges PNG must keep the red interior');
    expect(centre.g, lessThan(80));
    var ringLuma = 255.0;
    final midY = decoded.height ~/ 2;
    for (var x = 0; x < decoded.width ~/ 3; x++) {
      final pixel = decoded.getPixel(x, midY);
      final luma = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
      if (luma < ringLuma) ringLuma = luma;
    }
    expect(
      ringLuma,
      lessThan(180),
      reason: 'filled+stroked SoftEdges PNG must paint the feathered ring',
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioSoftEdgesPlate),
      hasLength(1),
      reason: 'a second save must not stack another SoftEdges plate',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(savedDoc.pages.first.findShapeById(1)!.fill.pattern, 0);
    expect(savedDoc.pages.first.findShapeById(1)!.line.pattern, 0);
    expect(
      savedDoc.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
      hasLength(1),
    );

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    expect(oracle.svgPages(saved)?.join() ?? '', isNotEmpty);
  });

  test('closed 2-D arrow cells do not block SoftEdges stroke bake', () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.2,
      height: 0.8,
      name: 'ArrowedFillStrokeSoft',
      fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
      line: const VsdxLine(
        color: VsdxColor(0xFF000000),
        weightInches: 0.08,
        softEdgesInches: 0.08,
        beginArrow: 4,
        endArrow: 13,
      ),
    );
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(shape), isTrue);
    expect(shapeNeedsLibvisioArrowedStrokeBake(shape), isFalse,
        reason: 'libvisio suppresses markers on a Z-closed rectangle');

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.fill.pattern, 0);
    expect(source.line.pattern, 0,
        reason: 'closed arrow cells must not leave a hard native stroke');
    expect(source.line.softEdgesInches, closeTo(0, 1e-9));
    final plate =
        baked.pages.first.shapes.where(isLibvisioSoftEdgesPlate).single;
    expect(plate.hasImage, isTrue);
    expect(plate.width, greaterThan(source.width + 0.05));
    final png = baked.images.findByPart(plate.imagePartName!);
    final decoded = raster.decodePng(png!.bytes)!;
    final centre = decoded.getPixel(decoded.width ~/ 2, decoded.height ~/ 2);
    expect(centre.r, greaterThan(180),
        reason: 'arrowed closed SoftEdges PNG must keep the red interior');
    expect(centre.g, lessThan(80));
    var ringLuma = 255.0;
    final midY = decoded.height ~/ 2;
    for (var x = 0; x < decoded.width ~/ 3; x++) {
      final pixel = decoded.getPixel(x, midY);
      final luma = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
      if (luma < ringLuma) ringLuma = luma;
    }
    expect(
      ringLuma,
      lessThan(180),
      reason: 'arrowed closed SoftEdges PNG must paint the feathered ring',
    );

    final open = VsdxShape(
      id: 2,
      name: 'OpenSoftArrows',
      pinX: 2,
      pinY: 2,
      width: 1.2,
      height: 0.8,
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(
        color: VsdxColor(0xFF000000),
        weightInches: 0.08,
        softEdgesInches: 0.08,
        beginArrow: 4,
        endArrow: 13,
      ),
      geometries: const <VsdxGeometry>[
        VsdxGeometry(
          commands: <VsdxPathCommand>[
            MoveTo(0, 0.2),
            LineTo(0.6, 0.6),
            LineTo(1.2, 0.2),
          ],
        ),
      ],
    );
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(open), isFalse,
        reason: 'open-path arrows stay native so crisp heads are not in the PNG');
  });

  test('ShadowBlur bakes a Gaussian PNG sibling for LibreOffice', () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.2,
      height: 0.8,
      name: 'ShadowBlur',
      fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
      line: const VsdxLine(pattern: 0),
    ).copyWith(
      shadow: const VsdxShadow(
        enabled: true,
        color: VsdxColor(0xFF000000),
        offsetXInches: 0.2,
        offsetYInches: -0.15,
        blurInches: 0.08,
        transparency: 0.4,
      ),
    );
    expect(shapeNeedsLibvisioShadowBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.shadow.enabled, isFalse);
    expect(source.shadow.blurInches, closeTo(0, 1e-9));
    expect(source.fill.pattern, 1, reason: 'shadow bake keeps the source fill');
    final plates = baked.pages.first.shapes.where(isLibvisioShadowPlate);
    expect(plates, hasLength(1));
    final plate = plates.single;
    expect(plate.locked, isTrue);
    expect(plate.hasImage, isTrue);
    expect(plate.pinX, closeTo(2.2, 1e-9));
    expect(plate.pinY, closeTo(1.85, 1e-9));
    expect(plate.width, greaterThan(1.2));
    final png = baked.images.findByPart(plate.imagePartName!);
    expect(png, isNotNull);
    final decoded = raster.decodePng(png!.bytes);
    expect(decoded, isNotNull);
    final cx = decoded!.width ~/ 2;
    final cy = decoded.height ~/ 2;
    expect(decoded.getPixel(cx, cy).a, greaterThan(80));
    expect(
      decoded.getPixel(decoded.width ~/ 8, cy).a,
      greaterThan(0),
      reason: 'Gaussian ShadowBlur must spread alpha into the pad',
    );
    expect(
      decoded.getPixel(decoded.width ~/ 8, cy).a,
      lessThan(decoded.getPixel(cx, cy).a),
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioShadowPlate),
      hasLength(1),
      reason: 'a second save must not stack another Shadow plate',
    );

    final oval = VsdxShapeFactory.ellipse(
      id: 2,
      pinX: 5,
      pinY: 2,
      width: 1.2,
      height: 0.8,
      fill: const VsdxFill(foreground: VsdxColor(0xFF1565C0), pattern: 1),
      line: const VsdxLine(pattern: 0),
    ).copyWith(
      shadow: const VsdxShadow(
        enabled: true,
        color: VsdxColor(0xFF000000),
        blurInches: 0.08,
        transparency: 0.4,
      ),
    );
    expect(shapeNeedsLibvisioShadowBake(oval), isTrue);

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(savedDoc.pages.first.findShapeById(1)!.shadow.enabled, isFalse);
    expect(
      savedDoc.pages.first.shapes.where(isLibvisioShadowPlate),
      hasLength(1),
    );

    final oracleSoft = LibvisioOracle.tryLoad();
    if (oracleSoft == null) return;
    expect(oracleSoft.svgPages(saved)?.join() ?? '', isNotEmpty);
  });

  test('page oblique shadow bakes a sheared sibling for LibreOffice', () {
    const colour = VsdxColor(0xFF000000);
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 3,
      pinY: 3,
      width: 1.4,
      height: 0.8,
      name: 'ObliqueShadow',
      fill: const VsdxFill(foreground: VsdxColor(0xFF1565C0), pattern: 1),
      line: const VsdxLine(pattern: 0),
    ).copyWith(
      shadow: const VsdxShadow(
        enabled: true,
        color: colour,
        offsetXInches: 0.2,
        offsetYInches: -0.15,
        blurInches: 0,
        transparency: 0.4,
      ),
    );

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final upright = doc.pages.first.addShape(shape);
    expect(
      shapeNeedsLibvisioPageShadowBake(shape, upright),
      isFalse,
      reason: 'a plain page keeps the native ShdwOffset* Draw collects',
    );

    final obliquePage = upright.copyWith(
      pageSheet: upright.pageSheet.copyWith(
        shadowType: 1,
        shadowObliqueAngle: 0.5,
        shadowScaleFactor: 1.2,
      ),
    );
    expect(pageSheetShearsLibvisioShadows(obliquePage.pageSheet), isTrue);
    expect(shapeNeedsLibvisioPageShadowBake(shape, obliquePage), isTrue);
    expect(
      shapeNeedsLibvisioPageShadowBake(
        shape.copyWith(shadow: shape.shadow.copyWith(blurInches: 0.08)),
        obliquePage,
      ),
      isFalse,
      reason: 'a blurred shadow keeps the Gaussian PNG path',
    );

    doc = doc.replacePage(0, obliquePage);
    expect(pageNeedsLibvisioPageShadowBake(doc.pages.first), isTrue);
    final baked = documentForLibvisioWrite(doc);
    final plates =
        baked.pages.first.shapes.where(isLibvisioPageShadowPlate).toList();
    expect(plates, hasLength(1));
    final plate = plates.single;
    expect(plate.name, '${kLibvisioPageShadowShapeNamePrefix}1');
    expect(plate.locked, isTrue);
    expect(plate.line.pattern, 0);
    expect(plate.fill.pattern, 1);
    expect(plate.fill.foreground?.value, 0xFF000000);
    // colourAlpha 1.0 × (1 - 0.4) opacity → FillForegndTrans 0.4.
    expect(plate.fill.foregroundTransparency, closeTo(0.4, 1e-9));
    // The page-space offset rides on the pin, like the Gaussian PNG plate.
    expect(plate.pinX, closeTo(3.2, 1e-9));
    expect(plate.pinY, closeTo(2.85, 1e-9));

    final source = baked.pages.first.findShapeById(1)!;
    expect(source.shadow.enabled, isFalse,
        reason: 'ShdwPattern 0 so Draw adds no unsheared copy');
    expect(source.fill.foreground?.value, 0xFF1565C0);
    expect(
      baked.pages.first.shapes.indexOf(plate),
      lessThan(baked.pages.first.shapes.indexOf(source)),
      reason: 'the shadow paints behind its shape',
    );

    // The silhouette must be sheared: a rectangle becomes a parallelogram,
    // so top and bottom edges no longer share an X range.
    final xs = <double>[
      for (final c in plate.geometries.single.commands)
        switch (c) {
          MoveTo(:final x) => x,
          LineTo(:final x) => x,
          _ => double.nan,
        },
    ]..removeWhere((v) => v.isNaN);
    final ys = <double>[
      for (final c in plate.geometries.single.commands)
        switch (c) {
          MoveTo(:final y) => y,
          LineTo(:final y) => y,
          _ => double.nan,
        },
    ]..removeWhere((v) => v.isNaN);
    expect(xs, isNotEmpty);
    final topXs = <double>[
      for (var i = 0; i < xs.length; i++)
        if (ys[i] > shape.height / 2) xs[i],
    ];
    final bottomXs = <double>[
      for (var i = 0; i < xs.length; i++)
        if (ys[i] <= shape.height / 2) xs[i],
    ];
    expect(topXs, isNotEmpty);
    expect(bottomXs, isNotEmpty);
    expect(
      topXs.reduce(math.min),
      greaterThan(bottomXs.reduce(math.min) + 1e-6),
      reason: 'positive oblique angle must lean the top edge right',
    );
    expect(
      ys.reduce(math.max) - ys.reduce(math.min),
      greaterThan(shape.height + 1e-6),
      reason: 'ShdwScaleFactor 1.2 must grow the silhouette',
    );

    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioPageShadowPlate),
      hasLength(1),
      reason: 'a second save must not stack another sheared plate',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(savedDoc.pages.first.pageSheet.shadowType, 1);
    expect(
      savedDoc.pages.first.pageSheet.shadowObliqueAngle,
      closeTo(0.5, 1e-9),
    );
    expect(
      savedDoc.pages.first.pageSheet.shadowScaleFactor,
      closeTo(1.2, 1e-9),
    );
    expect(savedDoc.pages.first.findShapeById(1)!.shadow.enabled, isFalse);
    final savedPlate = savedDoc.pages.first.shapes
        .firstWhere((s) => s.name == '${kLibvisioPageShadowShapeNamePrefix}1');
    expect(savedPlate.fill.foreground?.value, 0xFF000000);
    expect(
        savedPlate.geometries.single.commands.whereType<LineTo>(), isNotEmpty);

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    final after = oracle.svgPages(saved)?.join() ?? '';
    expect(after, isNotEmpty);
    _expectVsd2rawCollected(saved, const <String>['draw:fill-color: #000000']);
  });

  test('blurred shadow on an oblique page shears its Gaussian PNG', () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 3,
      pinY: 3,
      width: 1.4,
      height: 0.8,
      name: 'ObliqueBlur',
      fill: const VsdxFill(foreground: VsdxColor(0xFF1565C0), pattern: 1),
      line: const VsdxLine(pattern: 0),
    ).copyWith(
      shadow: const VsdxShadow(
        enabled: true,
        color: VsdxColor(0xFF000000),
        offsetXInches: 0.2,
        offsetYInches: -0.15,
        blurInches: 0.08,
        transparency: 0.4,
      ),
    );

    final blank = writer.emptyDocument();
    final base = parser.parse(blank);
    final upright = base.pages.first.addShape(shape);

    ({double width, double height, raster.Image png}) bake(VsdxPage page) {
      final doc = base.replacePage(0, page);
      final baked = documentForLibvisioWrite(doc);
      // A blurred shadow stays on the Gaussian PNG path, never the vector one.
      expect(
          baked.pages.first.shapes.where(isLibvisioPageShadowPlate), isEmpty);
      final plate =
          baked.pages.first.shapes.where(isLibvisioShadowPlate).single;
      expect(plate.hasImage, isTrue);
      final bytes = baked.images.findByPart(plate.imagePartName!)!.bytes;
      return (
        width: plate.width,
        height: plate.height,
        png: raster.decodePng(bytes)!,
      );
    }

    final plain = bake(upright);
    final oblique = bake(
      upright.copyWith(
        pageSheet: upright.pageSheet.copyWith(
          shadowType: 1,
          shadowObliqueAngle: 0.6,
        ),
      ),
    );
    expect(
      oblique.width,
      greaterThan(plain.width + 0.1),
      reason: 'the sheared silhouette needs a wider box than the shape',
    );
    expect(
      oblique.height,
      closeTo(plain.height, 0.06),
      reason: 'an X shear must not change the height beyond blur-pad rounding',
    );

    // Shear leans the top right: the topmost opaque row starts further right
    // than the bottom-most one.
    int firstOpaqueX(raster.Image png, int y) {
      for (var x = 0; x < png.width; x++) {
        if (png.getPixel(x, y).a > 40) return x;
      }
      return -1;
    }

    final near = firstOpaqueX(oblique.png, (oblique.png.height * 0.25).round());
    final far = firstOpaqueX(oblique.png, (oblique.png.height * 0.75).round());
    expect(near, greaterThanOrEqualTo(0));
    expect(far, greaterThanOrEqualTo(0));
    expect(
      near,
      greaterThan(far + 2),
      reason: 'positive ShdwObliqueAngle leans the top edge right; '
          'near=$near far=$far',
    );

    final plainNear =
        firstOpaqueX(plain.png, (plain.png.height * 0.25).round());
    final plainFar = firstOpaqueX(plain.png, (plain.png.height * 0.75).round());
    expect(
      (plainNear - plainFar).abs(),
      lessThanOrEqualTo(2),
      reason: 'a plain page keeps the silhouette axis-aligned',
    );

    final doc = base.replacePage(
      0,
      upright.copyWith(
        pageSheet: upright.pageSheet.copyWith(
          shadowType: 1,
          shadowObliqueAngle: 0.6,
        ),
      ),
    );
    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(savedDoc.pages.first.findShapeById(1)!.shadow.enabled, isFalse);
    expect(savedDoc.pages.first.findShapeById(1)!.shadow.blurInches, 0);
    expect(
      savedDoc.pages.first.shapes.where(isLibvisioShadowPlate),
      hasLength(1),
    );
    expect(
      documentForLibvisioWrite(savedDoc)
          .pages
          .first
          .shapes
          .where(isLibvisioShadowPlate),
      hasLength(1),
      reason: 'a second save must not stack another Shadow plate',
    );

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    expect(oracle.svgPages(saved)?.join() ?? '', isNotEmpty);
  });

  test('picture ShadowBlur on an oblique page shears its Gaussian PNG', () {
    const part = '/visio/media/oblique_shadow.png';
    final rasterImage = raster.Image(width: 16, height: 16);
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 16; x++) {
        rasterImage.setPixelRgba(x, y, 255, 0, 0, 255);
      }
    }
    final sourceImage = VsdxImage(
      partName: part,
      bytes: Uint8List.fromList(raster.encodePng(rasterImage)),
      mimeType: 'image/png',
    );
    final shape = VsdxShapeFactory.picture(
      id: 1,
      pinX: 3,
      pinY: 3,
      width: 1.4,
      height: 0.8,
      imagePartName: part,
      name: 'ObliqueBlurPicture',
    ).copyWith(
      shadow: const VsdxShadow(
        enabled: true,
        color: VsdxColor(0xFF000000),
        offsetXInches: 0.2,
        offsetYInches: -0.15,
        blurInches: 0.08,
        transparency: 0.4,
      ),
    );

    final blank = writer.emptyDocument();
    var base = parser.parse(blank);
    base = base.copyWith(images: base.images.withImage(sourceImage));
    final upright = base.pages.first.addShape(shape);

    ({double width, raster.Image png}) bake(VsdxPage page) {
      final doc = base.replacePage(0, page);
      final baked = documentForLibvisioWrite(doc);
      expect(
          baked.pages.first.shapes.where(isLibvisioPageShadowPlate), isEmpty);
      final plate =
          baked.pages.first.shapes.where(isLibvisioShadowPlate).single;
      return (
        width: plate.width,
        png: raster.decodePng(
          baked.images.findByPart(plate.imagePartName!)!.bytes,
        )!,
      );
    }

    final plain = bake(upright);
    final oblique = bake(
      upright.copyWith(
        pageSheet: upright.pageSheet.copyWith(
          shadowType: 1,
          shadowObliqueAngle: 0.6,
        ),
      ),
    );
    expect(oblique.width, greaterThan(plain.width + 0.1));

    int firstOpaqueX(raster.Image png, int y) {
      for (var x = 0; x < png.width; x++) {
        if (png.getPixel(x, y).a > 40) return x;
      }
      return -1;
    }

    final near = firstOpaqueX(oblique.png, (oblique.png.height * 0.25).round());
    final far = firstOpaqueX(oblique.png, (oblique.png.height * 0.75).round());
    expect(near, greaterThan(far + 2));
  });

  test('picture ShadowBlur bakes a Gaussian PNG sibling for LibreOffice', () {
    const part = '/visio/media/shadow.png';
    final rasterImage = raster.Image(width: 16, height: 16);
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 16; x++) {
        rasterImage.setPixelRgba(x, y, 255, 0, 0, 255);
      }
    }
    final sourceImage = VsdxImage(
      partName: part,
      bytes: Uint8List.fromList(raster.encodePng(rasterImage)),
      mimeType: 'image/png',
    );
    final shape = VsdxShapeFactory.picture(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.2,
      height: 0.8,
      imagePartName: part,
      name: 'ShadowPicture',
    ).copyWith(
      shadow: const VsdxShadow(
        enabled: true,
        color: VsdxColor(0xFF000000),
        offsetXInches: 0.2,
        offsetYInches: -0.15,
        blurInches: 0.08,
        transparency: 0.4,
      ),
    );
    expect(shapeNeedsLibvisioShadowBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.copyWith(images: doc.images.withImage(sourceImage));
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.shadow.enabled, isFalse);
    expect(source.shadow.blurInches, closeTo(0, 1e-9));
    expect(source.hasImage, isTrue);
    expect(source.imagePartName, part);
    final plates = baked.pages.first.shapes.where(isLibvisioShadowPlate);
    expect(plates, hasLength(1));
    final plate = plates.single;
    expect(plate.locked, isTrue);
    expect(plate.hasImage, isTrue);
    expect(plate.pinX, closeTo(2.2, 1e-9));
    expect(plate.pinY, closeTo(1.85, 1e-9));
    expect(plate.width, greaterThan(1.2));
    final png = baked.images.findByPart(plate.imagePartName!);
    expect(png, isNotNull);
    final decoded = raster.decodePng(png!.bytes);
    expect(decoded, isNotNull);
    final cx = decoded!.width ~/ 2;
    final cy = decoded.height ~/ 2;
    expect(decoded.getPixel(cx, cy).a, greaterThan(80));
    expect(
      decoded.getPixel(decoded.width ~/ 8, cy).a,
      greaterThan(0),
      reason: 'Gaussian picture ShadowBlur must spread alpha into the pad',
    );
    expect(
      decoded.getPixel(decoded.width ~/ 8, cy).a,
      lessThan(decoded.getPixel(cx, cy).a),
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioShadowPlate),
      hasLength(1),
      reason: 'a second save must not stack another Shadow plate',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(savedDoc.pages.first.findShapeById(1)!.shadow.enabled, isFalse);
    expect(
      savedDoc.pages.first.shapes.where(isLibvisioShadowPlate),
      hasLength(1),
    );

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    expect(oracle.svgPages(saved)?.join() ?? '', isNotEmpty);
  });

  test('Curved Text bakes per-glyph siblings for LibreOffice', () {
    VsdxShape arcBox({
      required int id,
      bool curved = true,
      bool flipX = false,
    }) =>
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: 4,
          pinY: 5,
          width: 1.0,
          height: 3.0,
          name: 'Arc',
        ).copyWith(flipX: flipX).withCurvedText(curved).copyWith(
              richText: const VsdxRichText(
                runs: <VsdxTextRun>[
                  VsdxTextRun(
                    text: 'ARC',
                    charStyle: VsdxCharStyle(
                      fontFamily: 'Arial',
                      fontSizeInches: 0.4,
                      color: VsdxColor(0xFF000000),
                    ),
                    paraStyle: VsdxParaStyle(
                      horizontalAlign: VsdxHorzAlign.center,
                    ),
                  ),
                ],
              ),
            );

    final shape = arcBox(id: 1);
    expect(shapeNeedsLibvisioCurvedTextBake(shape), isTrue);
    expect(
      shapeNeedsLibvisioCurvedTextBake(arcBox(id: 8, flipX: true)),
      isTrue,
    );
    expect(
      shapeNeedsLibvisioCurvedTextBake(arcBox(id: 8).copyWith(flipY: true)),
      isTrue,
    );
    expect(
      shapeNeedsLibvisioCurvedTextBake(
        VsdxShapeFactory.line(
          id: 9,
          ax: 1,
          ay: 1,
          bx: 4,
          by: 2,
        ).withCurvedText(true).copyWith(
              richText: const VsdxRichText(
                runs: <VsdxTextRun>[VsdxTextRun(text: 'ARC')],
              ),
            ),
      ),
      isFalse,
    );

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.curvedText, isFalse);
    expect(source.richText.textBlock.hideText, isTrue);
    final plates =
        baked.pages.first.shapes.where(isLibvisioCurvedTextPlate).toList()
          ..sort(
            (a, b) => int.parse(a.name.split('.')[1])
                .compareTo(int.parse(b.name.split('.')[1])),
          );
    expect(plates, hasLength(3));
    expect(plates.every((p) => p.locked), isTrue);
    expect(plates.every((p) => p.fill.pattern == 0), isTrue);
    expect(plates.every((p) => p.line.pattern == 0), isTrue);
    expect(plates.map((p) => p.richText.plainText).join(), 'ARC');
    expect(libvisioCurvedTextSourceId(plates[0]), 1);
    expect(plates[1].pinY, greaterThan(plates[0].pinY + 0.08));
    expect(plates[1].pinY, greaterThan(plates[2].pinY + 0.08));

    var flipDoc = parser.parse(blank);
    flipDoc = flipDoc.replacePage(
      0,
      flipDoc.pages.first.addShape(arcBox(id: 1).copyWith(flipY: true)),
    );
    final flipPlates = documentForLibvisioWrite(flipDoc)
        .pages
        .first
        .shapes
        .where(isLibvisioCurvedTextPlate)
        .toList()
      ..sort(
        (a, b) => int.parse(a.name.split('.')[1])
            .compareTo(int.parse(b.name.split('.')[1])),
      );
    expect(flipPlates, hasLength(3));
    for (var i = 0; i < 3; i++) {
      expect(flipPlates[i].pinX, closeTo(plates[i].pinX, 1e-6),
          reason: 'FlipY extra text mirror about TxtPin cancels LocPin FlipY');
      expect(flipPlates[i].pinY, closeTo(plates[i].pinY, 1e-6),
          reason: 'FlipY extra text mirror about TxtPin cancels LocPin FlipY');
    }

    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioCurvedTextPlate),
      hasLength(3),
      reason: 'a second save must not stack another Curved Text plate',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(savedDoc.pages.first.findShapeById(1)!.curvedText, isFalse);
    expect(
      savedDoc.pages.first.shapes.where(isLibvisioCurvedTextPlate),
      hasLength(3),
    );

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    expect(oracle.svgPages(saved)?.join() ?? '', isNotEmpty);
  });

  test('Shape Inside bakes per-line siblings for LibreOffice', () {
    VsdxShape oval({
      required int id,
      bool inside = true,
      bool flipX = false,
    }) =>
        VsdxShapeFactory.ellipse(
          id: id,
          pinX: 4,
          pinY: 5,
          width: 3,
          height: 4,
          name: 'Oval',
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(pattern: 0),
        ).copyWith(flipX: flipX).withShapeInside(inside).copyWith(
              richText: const VsdxRichText(
                runs: <VsdxTextRun>[
                  VsdxTextRun(
                    text: 'SHAPE INSIDE FLOW ALONG THE ELLIPSE',
                    charStyle: VsdxCharStyle(
                      fontFamily: 'Arial',
                      fontSizeInches: 0.22,
                      color: VsdxColor(0xFF000000),
                    ),
                    paraStyle: VsdxParaStyle(
                      horizontalAlign: VsdxHorzAlign.center,
                    ),
                  ),
                ],
                textBlock: VsdxTextBlock(
                  verticalAlign: VsdxVertAlign.top,
                ),
              ),
            );

    final shape = oval(id: 1);
    expect(shape.supportsShapeInside, isTrue);
    expect(shapeNeedsLibvisioShapeInsideBake(shape), isTrue);
    expect(
      shapeNeedsLibvisioShapeInsideBake(oval(id: 8, flipX: true)),
      isTrue,
    );
    expect(
      shapeNeedsLibvisioShapeInsideBake(
        VsdxShapeFactory.rectangle(
          id: 9,
          pinX: 2,
          pinY: 2,
          width: 3,
          height: 2,
        ).withShapeInside(true).copyWith(
              richText: const VsdxRichText(
                runs: <VsdxTextRun>[VsdxTextRun(text: 'NO')],
              ),
            ),
      ),
      isFalse,
    );

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.shapeInside, isFalse);
    expect(source.richText.textBlock.hideText, isTrue);
    final plates =
        baked.pages.first.shapes.where(isLibvisioShapeInsidePlate).toList()
          ..sort(
            (a, b) => int.parse(a.name.split('.')[1])
                .compareTo(int.parse(b.name.split('.')[1])),
          );
    expect(plates.length, greaterThanOrEqualTo(2));
    expect(plates.every((p) => p.locked), isTrue);
    expect(plates.first.width, lessThan(plates.last.width - 0.2));
    expect(libvisioShapeInsideSourceId(plates.first), 1);

    var flipInsideDoc = parser.parse(blank);
    flipInsideDoc = flipInsideDoc.replacePage(
      0,
      flipInsideDoc.pages.first.addShape(oval(id: 1).copyWith(flipY: true)),
    );
    final flipInsidePlates = documentForLibvisioWrite(flipInsideDoc)
        .pages
        .first
        .shapes
        .where(isLibvisioShapeInsidePlate)
        .toList()
      ..sort(
        (a, b) => int.parse(a.name.split('.')[1])
            .compareTo(int.parse(b.name.split('.')[1])),
      );
    expect(flipInsidePlates, hasLength(plates.length));
    for (var i = 0; i < plates.length; i++) {
      expect(flipInsidePlates[i].pinX, closeTo(plates[i].pinX, 1e-6));
      expect(flipInsidePlates[i].pinY, closeTo(plates[i].pinY, 1e-6));
      expect(flipInsidePlates[i].width, closeTo(plates[i].width, 1e-6));
    }

    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioShapeInsidePlate),
      hasLength(plates.length),
      reason: 'a second save must not stack another Shape Inside plate',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(savedDoc.pages.first.findShapeById(1)!.shapeInside, isFalse);
    expect(
      savedDoc.pages.first.shapes.where(isLibvisioShapeInsidePlate).length,
      plates.length,
    );

    final oracleInside = LibvisioOracle.tryLoad();
    if (oracleInside == null) return;
    expect(oracleInside.svgPages(saved)?.join() ?? '', isNotEmpty);
  });

  test('Rotate with Edge bakes TxtAngle for LibreOffice', () {
    final shape = VsdxShapeFactory.line(
      id: 1,
      ax: 2,
      ay: 3,
      bx: 6.5,
      by: 7.5,
      name: 'Edge',
    ).withAutoRotateLabel(true).copyWith(
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'ROTATE',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 0.35,
                  color: VsdxColor(0xFF000000),
                ),
                paraStyle: VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.center,
                ),
              ),
            ],
          ),
        );
    expect(shapeNeedsLibvisioAutoRotateLabelBake(shape), isTrue);
    expect(
      shapeNeedsLibvisioAutoRotateLabelBake(
        VsdxShapeFactory.rectangle(
          id: 9,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
        ).withAutoRotateLabel(true).copyWith(
              richText: const VsdxRichText(
                runs: <VsdxTextRun>[VsdxTextRun(text: 'NO')],
              ),
            ),
      ),
      isFalse,
    );

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.autoRotateLabel, isFalse);
    expect(source.richText.textBlock.angleRad, closeTo(math.pi / 4, 1e-6));
    expect(source.richText.textBlock.widthInches, greaterThan(0.5));
    expect(source.richText.textBlock.heightInches, greaterThan(0.2));
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .findShapeById(1)!
          .richText
          .textBlock
          .angleRad,
      closeTo(math.pi / 4, 1e-6),
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(savedDoc.pages.first.findShapeById(1)!.autoRotateLabel, isFalse);
    expect(
      savedDoc.pages.first.findShapeById(1)!.richText.textBlock.angleRad,
      closeTo(math.pi / 4, 1e-6),
    );

    final horiz = VsdxShapeFactory.line(
      id: 2,
      ax: 1,
      ay: 2,
      bx: 5,
      by: 2,
      name: 'Horiz',
    ).withAutoRotateLabel(true).copyWith(
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'FLAT',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 0.2,
                ),
              ),
            ],
            textBlock: VsdxTextBlock(angleRad: 0.4),
          ),
        );
    doc = doc.replacePage(0, doc.pages.first.addShape(horiz));
    final bakedHoriz =
        documentForLibvisioWrite(doc).pages.first.findShapeById(2)!;
    expect(bakedHoriz.autoRotateLabel, isFalse);
    expect(bakedHoriz.richText.textBlock.angleRad, closeTo(0, 1e-6));

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    expect(oracle.svgPages(saved)?.join() ?? '', isNotEmpty);
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

  test('cropped picture SoftEdges composites into the frame for LibreOffice',
      () {
    final rasterImage = raster.Image(width: 32, height: 16);
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 32; x++) {
        if (x < 16) {
          rasterImage.setPixelRgba(x, y, 255, 0, 0, 255);
        } else {
          rasterImage.setPixelRgba(x, y, 0, 0, 255, 255);
        }
      }
    }
    final bytes = Uint8List.fromList(raster.encodePng(rasterImage));
    const part = '/visio/media/crop_soft.png';
    final source =
        VsdxImage(partName: part, bytes: bytes, mimeType: 'image/png');
    final pic = VsdxShapeFactory.picture(
      id: 1,
      pinX: 3,
      pinY: 3,
      width: 1.2,
      height: 0.8,
      imagePartName: part,
      name: 'CropSoft',
    ).copyWith(
      line: const VsdxLine(pattern: 0, softEdgesInches: 0.1),
      imgOffsetXInches: -1.2,
      imgOffsetYInches: 0,
      imgWidthInches: 2.4,
      imgHeightInches: 0.8,
    );
    expect(shapeNeedsLibvisioCroppedSoftEdgesBake(pic), isTrue);
    expect(imageSoftEdgesInchesForLibvisioWrite(pic), closeTo(0.1, 1e-12));
    final baked = bakeVisioImageAdjustmentsPng(
      image: source,
      transparency: 0,
      blur: 0,
      brightness: 0.5,
      contrast: 0.5,
      displayWidthInches: 1.2,
      softEdgesInches: 0.1,
      frameWidthInches: 1.2,
      frameHeightInches: 0.8,
      imgOffsetXInches: -1.2,
      imgOffsetYInches: 0,
      imgWidthInches: 2.4,
      imgHeightInches: 0.8,
    );
    expect(baked, isNotNull);
    final decoded = raster.decodePng(baked!)!;
    final center = decoded.getPixel(decoded.width ~/ 2, decoded.height ~/ 2);
    expect(center.b, greaterThan(center.r + 40),
        reason: 'the visible window is the right (blue) half');
    expect(center.a, greaterThan(200));
    expect(
      decoded.getPixel(0, decoded.height ~/ 2).a,
      lessThan(center.a),
      reason: 'SoftEdges must feather the cropped frame, not the bitmap edge',
    );

    var doc = parser.parse(writer.emptyDocument());
    doc = doc
        .copyWith(images: doc.images.withImage(source))
        .replacePage(0, doc.pages.first.addShape(pic));
    final saved = writer.write(
      originalBytes: writer.emptyDocument(),
      edited: doc,
    );
    final savedDoc = parser.parse(saved);
    final after = savedDoc.pages.first.findShapeById(1)!;
    expect(after.line.softEdgesInches, closeTo(0, 1e-9));
    expect(after.imgOffsetXInches, closeTo(0, 1e-9));
    expect(after.imgOffsetYInches, closeTo(0, 1e-9));
    expect(after.effectiveImgWidth, closeTo(after.width, 1e-6));
    expect(after.effectiveImgHeight, closeTo(after.height, 1e-6));
    expect(after.imagePartName, isNot(part));
    final frame = raster.decodePng(
      savedDoc.images.findByPart(after.imagePartName!)!.bytes,
    )!;
    final savedCenter = frame.getPixel(frame.width ~/ 2, frame.height ~/ 2);
    expect(savedCenter.b, greaterThan(savedCenter.r + 40));
  });

  test('PageColor bakes a full-page plate LibreOffice can collect', () {
    const colour = VsdxColor(0xFF336699);
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(
      0,
      doc.pages.first.copyWith(backgroundColor: colour),
    );
    expect(pageNeedsLibvisioPageColorBake(doc.pages.first), isTrue);
    final baked = documentForLibvisioWrite(doc);
    expect(pageNeedsLibvisioPageColorBake(baked.pages.first), isFalse);
    expect(
      baked.pages.first.shapes
          .where((s) => s.name == kLibvisioPageColorShapeName),
      hasLength(1),
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where((s) => s.name == kLibvisioPageColorShapeName),
      hasLength(1),
      reason: 'a second save must not stack another plate',
    );
    final plate = baked.pages.first.shapes.first;
    expect(plate.name, kLibvisioPageColorShapeName);
    expect(plate.fill.foreground?.value, colour.value);
    expect(plate.line.pattern, 0);
    expect(plate.locked, isTrue);

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(savedDoc.pages.first.backgroundColor?.value, colour.value);
    expect(savedDoc.pages.first.shapes.first.name, kLibvisioPageColorShapeName);
    expect(
      savedDoc.pages.first.shapes.first.fill.foreground?.value,
      colour.value,
    );

    final cleared = documentForLibvisioWrite(
      savedDoc.replacePage(0, savedDoc.pages.first.withoutBackgroundColor()),
    );
    expect(
      cleared.pages.first.shapes
          .where((s) => s.name == kLibvisioPageColorShapeName),
      isEmpty,
      reason: 'clearing PageColor must drop the Draw plate',
    );

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    final after = oracle.svgPages(saved)?.join() ?? '';
    expect(after, isNotEmpty);
    expect(
      after.toLowerCase(),
      contains('336699'),
      reason: 'libvisio must fill the PageColor plate',
    );
    _expectVsd2rawCollected(saved, const <String>['draw:fill-color: #336699']);
  });

  test('Reflection bakes a sibling plate LibreOffice can collect', () {
    const colour = VsdxColor(0xFFCC5533);
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.4,
      height: 0.7,
      name: 'Mirror',
      fill: const VsdxFill(foreground: colour, pattern: 1),
      line: const VsdxLine(pattern: 0),
    ).copyWith(
      reflection: const VsdxReflection(
        enabled: true,
        sizeInches: 0.5,
        distanceInches: 0.08,
        transparency: 0.4,
      ),
    );
    expect(shapeNeedsLibvisioReflectionBake(shape), isTrue);
    expect(reflectionForLibvisioWrite(shape).enabled, isFalse);
    expect(reflectionForLibvisioWrite(shape).sizeInches, 0);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    expect(pageNeedsLibvisioReflectionBake(doc.pages.first), isTrue);
    final baked = documentForLibvisioWrite(doc);
    expect(
      baked.pages.first.shapes.where(isLibvisioReflectionPlate),
      hasLength(1),
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioReflectionPlate),
      hasLength(1),
      reason: 'a second save must not stack another plate',
    );
    final plate = baked.pages.first.shapes.first;
    expect(plate.name, '${kLibvisioReflectionShapeNamePrefix}1');
    expect(plate.locked, isTrue);
    expect(plate.fill.foreground?.value, colour.value);
    expect(plate.fill.foregroundTransparency, closeTo(0.4, 1e-9));
    expect(plate.line.pattern, 0);
    expect(
      plate.geometries.single.commands.any((c) => switch (c) {
            MoveTo(:final y) => y < -1e-6,
            LineTo(:final y) => y < -1e-6,
            _ => false,
          }),
      isTrue,
      reason: 'mirror geometry sits below the source in local Y',
    );
    expect(baked.pages.first.findShapeById(1)!.reflection.enabled, isTrue,
        reason: 'the in-memory source keeps the live effect; XML Size is 0');

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    final savedSource = savedDoc.pages.first.findShapeById(1)!;
    expect(savedSource.reflection.enabled, isFalse);
    expect(savedSource.reflection.distanceInches, closeTo(0.08, 1e-9));
    final savedPlate = savedDoc.pages.first.shapes
        .firstWhere((s) => s.name == '${kLibvisioReflectionShapeNamePrefix}1');
    expect(savedPlate.fill.foreground?.value, colour.value);
    expect(savedPlate.fill.foregroundTransparency, closeTo(0.4, 1e-9));

    final flipped = shape.copyWith(id: 2, name: 'FlipMirror', flipY: true);
    expect(shapeNeedsLibvisioReflectionBake(flipped), isTrue);
    var flipDoc = parser.parse(blank);
    flipDoc = flipDoc.replacePage(0, flipDoc.pages.first.addShape(flipped));
    final flippedPlate = documentForLibvisioWrite(flipDoc)
        .pages
        .first
        .shapes
        .firstWhere(isLibvisioReflectionPlate);
    expect(
      flippedPlate.geometries.single.commands.any((c) => switch (c) {
            MoveTo(:final y) => y > flipped.height + 1e-6,
            LineTo(:final y) => y > flipped.height + 1e-6,
            _ => false,
          }),
      isTrue,
      reason: 'FlipY mirror continues past local max Y (visual bottom)',
    );

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    final after = oracle.svgPages(saved)?.join() ?? '';
    expect(after, isNotEmpty);
    expect(
      after.toLowerCase(),
      contains('cc5533'),
      reason: 'libvisio must fill the Reflection plate',
    );
    _expectVsd2rawCollected(saved, const <String>['draw:fill-color: #cc5533']);
  });

  test('unfilled stroke Reflection bakes a mirrored PNG band for LibreOffice',
      () {
    const colour = VsdxColor(0xFF1565C0);
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.4,
      height: 0.7,
      name: 'StrokeMirror',
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(
        color: colour,
        weightInches: 0.04,
      ),
    ).copyWith(
      reflection: const VsdxReflection(
        enabled: true,
        sizeInches: 0.5,
        distanceInches: 0.08,
        transparency: 0.3,
        blurInches: 0,
      ),
    );
    expect(shapeNeedsLibvisioReflectionBake(shape), isTrue);
    expect(reflectionForLibvisioWrite(shape).enabled, isFalse);
    expect(reflectionForLibvisioWrite(shape).sizeInches, 0);
    expect(
      shapeNeedsLibvisioReflectionBake(
        shape.copyWith(line: shape.line.withThemeColor(1)),
      ),
      isFalse,
      reason: 'a theme-only stroke keeps the cell so THEMEVAL() survives',
    );
    expect(
      shapeNeedsLibvisioReflectionBake(shape.copyWith(flipY: true)),
      isTrue,
      reason: 'FlipY places the plate via `_reflectFillRing`; the PNG is '
          'not FlipY-copied',
    );

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final plates = baked.pages.first.shapes.where(isLibvisioReflectionPlate);
    expect(plates, hasLength(1));
    final plate = plates.single;
    expect(plate.locked, isTrue);
    expect(plate.hasImage, isTrue,
        reason: 'an unfilled stroke must not bake a filled mirror');
    expect(
      plate.pinY - plate.effectiveLocPinY,
      lessThan(shape.pinY - shape.effectiveLocPinY),
      reason: 'the band sits below the source in page Y',
    );
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.fill.pattern, 0,
        reason: 'the source stays unfilled; only the band is baked');
    expect(source.line.pattern, 1);
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioReflectionPlate),
      hasLength(1),
      reason: 'a second save must not stack another Reflection plate',
    );

    final png = baked.images.findByPart(plate.imagePartName!);
    expect(png, isNotNull);
    final decoded = raster.decodePng(png!.bytes);
    expect(decoded, isNotNull);
    final cx = decoded!.width ~/ 2;
    final mid = decoded.height ~/ 2;
    final rail = decoded.getPixel(2, mid);
    expect(
      rail.b,
      greaterThan(rail.r + 20),
      reason: 'the mirrored band must keep the blue side rails',
    );
    expect(
      decoded.getPixel(cx, mid).r,
      greaterThan(200),
      reason: 'the band interior must stay hollow, not a filled mirror',
    );
    final near = decoded.getPixel(2, 3);
    final far = decoded.getPixel(2, decoded.height - 3);
    expect(
      near.b - near.r,
      greaterThan(far.b - far.r),
      reason: 'the band must fade toward the far edge',
    );

    final flipped = shape.copyWith(
      id: 3,
      name: 'StrokeMirrorFlipY',
      flipY: true,
    );
    expect(shapeNeedsLibvisioReflectionBake(flipped), isTrue);
    var flipDoc = parser.parse(blank);
    flipDoc = flipDoc.replacePage(0, flipDoc.pages.first.addShape(flipped));
    final flippedBaked = documentForLibvisioWrite(flipDoc);
    final flippedPlate =
        flippedBaked.pages.first.shapes.where(isLibvisioReflectionPlate).single;
    expect(flippedPlate.flipY, isFalse,
        reason: 'copying FlipY onto the PNG would mirror the band twice');
    expect(flippedPlate.hasImage, isTrue);
    expect(
      flippedPlate.pinY - flippedPlate.effectiveLocPinY,
      greaterThan(flipped.pinY - flipped.effectiveLocPinY),
      reason: 'FlipY band sits past local max Y so Draw keeps it on the '
          'visual-bottom side after the source FlipY',
    );
    final flippedPng = raster.decodePng(
      flippedBaked.images.findByPart(flippedPlate.imagePartName!)!.bytes,
    )!;
    final nearFlip = flippedPng.getPixel(2, flippedPng.height - 3);
    final farFlip = flippedPng.getPixel(2, 3);
    expect(
      nearFlip.b - nearFlip.r,
      greaterThan(farFlip.b - farFlip.r),
      reason: 'FlipY PNG near-axis rows must land on min Y (image bottom)',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(savedDoc.pages.first.findShapeById(1)!.reflection.enabled, isFalse);
    expect(savedDoc.pages.first.findShapeById(1)!.fill.pattern, 0);
    final savedPlate = savedDoc.pages.first.shapes
        .firstWhere((s) => s.name == '${kLibvisioReflectionShapeNamePrefix}1');
    expect(savedPlate.hasImage, isTrue);

    final ellipse = VsdxShapeFactory.ellipse(
      id: 2,
      pinX: 5,
      pinY: 2,
      width: 1.2,
      height: 0.8,
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(color: colour, weightInches: 0.04),
    ).copyWith(reflection: shape.reflection);
    expect(shapeNeedsLibvisioReflectionBake(ellipse), isTrue);
    var ellipseDoc = parser.parse(blank);
    ellipseDoc = ellipseDoc.replacePage(
      0,
      ellipseDoc.pages.first.addShape(ellipse),
    );
    final ellipseBaked = documentForLibvisioWrite(ellipseDoc);
    final ellipsePlate =
        ellipseBaked.pages.first.shapes.where(isLibvisioReflectionPlate).single;
    expect(ellipsePlate.hasImage, isTrue);
    final ellipsePng = raster.decodePng(ellipseBaked.images
        .findByPart(
          ellipsePlate.imagePartName!,
        )!
        .bytes)!;
    final ellipseCentre = ellipsePng.getPixel(
      ellipsePng.width ~/ 2,
      ellipsePng.height ~/ 2,
    );
    expect(
      ellipseCentre.r,
      greaterThan(200),
      reason: 'ellipse stroke band must keep a hollow interior',
    );

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    expect(oracle.svgPages(saved)?.join() ?? '', isNotEmpty);
  });

  test('dashed unfilled stroke Reflection bakes dash gaps for LibreOffice', () {
    const colour = VsdxColor(0xFF1565C0);
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 1.2,
      name: 'DashMirror',
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(
        color: colour,
        weightInches: 0.08,
        pattern: 2,
      ),
    ).copyWith(
      reflection: const VsdxReflection(
        enabled: true,
        sizeInches: 0.5,
        distanceInches: 0.08,
        transparency: 0.2,
        blurInches: 0,
      ),
    );
    expect(shapeNeedsLibvisioReflectionBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.line.pattern, 2,
        reason: 'the source keeps LinePattern so Draw still dashes the body');
    expect(source.fill.pattern, 0);
    final plate =
        baked.pages.first.shapes.where(isLibvisioReflectionPlate).single;
    expect(plate.hasImage, isTrue);
    final decoded = raster.decodePng(
      baked.images.findByPart(plate.imagePartName!)!.bytes,
    )!;
    expect(
      decoded.getPixel(decoded.width ~/ 2, decoded.height ~/ 2).r,
      greaterThan(200),
      reason: 'the dashed mirror must stay hollow, not a filled band',
    );
    var ink = 0;
    var gap = 0;
    final row = 3;
    for (var x = 4; x < decoded.width - 4; x++) {
      final pixel = decoded.getPixel(x, row);
      final luma = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
      if (pixel.b > pixel.r + 15 && luma < 200) ink++;
      if (luma > 220) gap++;
    }
    expect(ink, greaterThan(4),
        reason: 'the mirrored band must keep dash ink; ink=$ink gap=$gap');
    expect(gap, greaterThan(4),
        reason: 'the mirrored band must keep dash gaps, not a solid ring; '
            'ink=$ink gap=$gap');
  });

  test('compound unfilled stroke Reflection bakes rails for LibreOffice', () {
    const colour = VsdxColor(0xFF1565C0);
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.4,
      height: 0.7,
      name: 'CompoundMirror',
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(
        color: colour,
        weightInches: 0.12,
        compoundType: 1,
      ),
    ).copyWith(
      reflection: const VsdxReflection(
        enabled: true,
        sizeInches: 0.5,
        distanceInches: 0.08,
        transparency: 0.2,
        blurInches: 0,
      ),
    );
    expect(shapeNeedsLibvisioReflectionBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.line.compoundType, 1,
        reason: 'the source keeps CompoundType; the PNG carries the rails');
    expect(source.fill.pattern, 0);
    final plate =
        baked.pages.first.shapes.where(isLibvisioReflectionPlate).single;
    expect(plate.hasImage, isTrue);
    final decoded = raster.decodePng(
      baked.images.findByPart(plate.imagePartName!)!.bytes,
    )!;
    expect(
      decoded.getPixel(decoded.width ~/ 2, decoded.height ~/ 2).r,
      greaterThan(200),
      reason: 'compound mirror interior must stay hollow',
    );
    final cx = decoded.width ~/ 2;
    var rails = 0;
    var inRail = false;
    for (var y = 0; y < decoded.height ~/ 2; y++) {
      final pixel = decoded.getPixel(cx, y);
      final on = pixel.b > pixel.r + 15;
      if (on && !inRail) {
        rails++;
        inRail = true;
      } else if (!on) {
        inRail = false;
      }
    }
    expect(rails, greaterThanOrEqualTo(2),
        reason: 'CompoundType 1 must paint two mirrored rails, not one ring; '
            'rails=$rails');
  });

  test('LineGradient unfilled stroke Reflection bakes the wash for LibreOffice',
      () {
    const wash = VsdxGradient(
      stops: <VsdxGradientStop>[
        VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
        VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
      ],
    );
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 1.2,
      name: 'LineGradMirror',
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(
        color: VsdxColor(0xFF000000),
        weightInches: 0.16,
        gradient: wash,
      ),
    ).copyWith(
      reflection: const VsdxReflection(
        enabled: true,
        sizeInches: 0.5,
        distanceInches: 0.08,
        transparency: 0.2,
        blurInches: 0,
      ),
    );
    expect(shapeNeedsLibvisioReflectionBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.line.hasGradient, isTrue,
        reason: 'the source keeps LineGradient; the PNG carries the wash');
    expect(source.fill.pattern, 0);
    final plate =
        baked.pages.first.shapes.where(isLibvisioReflectionPlate).single;
    expect(plate.hasImage, isTrue);
    final decoded = raster.decodePng(
      baked.images.findByPart(plate.imagePartName!)!.bytes,
    )!;
    expect(
      decoded.getPixel(decoded.width ~/ 2, decoded.height ~/ 2).r,
      greaterThan(200),
      reason: 'the LineGradient mirror interior must stay hollow',
    );
    ({int r, int g, int b}) sample(int x) {
      final pixel = decoded.getPixel(x, 3);
      return (r: pixel.r.toInt(), g: pixel.g.toInt(), b: pixel.b.toInt());
    }

    final left = sample((decoded.width * 0.12).round());
    final right = sample((decoded.width * 0.88).round());
    expect(
      left.r,
      greaterThan(right.r + 30),
      reason: 'LineGradient reflection PNG must keep the red-to-blue wash; '
          'left=$left right=$right',
    );
    expect(
      right.b,
      greaterThan(left.b + 30),
      reason: 'LineGradient reflection PNG must keep the red-to-blue wash; '
          'left=$left right=$right',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(savedDoc.pages.first.findShapeById(1)!.reflection.enabled, isFalse);
    expect(savedDoc.pages.first.findShapeById(1)!.line.hasGradient, isFalse);
    final savedPlate = savedDoc.pages.first.shapes
        .firstWhere((s) => s.name == '${kLibvisioReflectionShapeNamePrefix}1');
    expect(savedPlate.hasImage, isTrue);
  });

  test('picture Reflection bakes a Gaussian PNG sibling for LibreOffice', () {
    const part = '/visio/media/reflection.png';
    final rasterImage = raster.Image(width: 16, height: 16);
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 16; x++) {
        if (y < 8) {
          rasterImage.setPixelRgba(x, y, 255, 0, 0, 255);
        } else {
          rasterImage.setPixelRgba(x, y, 0, 0, 255, 255);
        }
      }
    }
    final sourceImage = VsdxImage(
      partName: part,
      bytes: Uint8List.fromList(raster.encodePng(rasterImage)),
      mimeType: 'image/png',
    );
    final shape = VsdxShapeFactory.picture(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.2,
      height: 0.8,
      imagePartName: part,
      name: 'MirrorPicture',
    ).copyWith(
      reflection: const VsdxReflection(
        enabled: true,
        sizeInches: 0.5,
        distanceInches: 0.08,
        transparency: 0.4,
        blurInches: 0,
      ),
    );
    expect(shapeNeedsLibvisioReflectionBake(shape), isTrue);
    expect(reflectionForLibvisioWrite(shape).enabled, isFalse);
    expect(reflectionForLibvisioWrite(shape).sizeInches, 0);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.copyWith(images: doc.images.withImage(sourceImage));
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.hasImage, isTrue);
    expect(source.imagePartName, part);
    expect(source.reflection.enabled, isTrue,
        reason: 'the in-memory source keeps the live effect; XML Size is 0');
    final plates = baked.pages.first.shapes.where(isLibvisioReflectionPlate);
    expect(plates, hasLength(1));
    final plate = plates.single;
    expect(plate.locked, isTrue);
    expect(plate.hasImage, isTrue);
    expect(plate.pinX, closeTo(shape.pinX, 1e-9));
    expect(plate.pinY, closeTo(shape.pinY, 1e-9));
    expect(
      plate.pinY - plate.effectiveLocPinY,
      lessThan(source.pinY - source.effectiveLocPinY),
      reason: 'mirror plate sits below the source in page Y',
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioReflectionPlate),
      hasLength(1),
      reason: 'a second save must not stack another Reflection plate',
    );
    final png = baked.images.findByPart(plate.imagePartName!);
    expect(png, isNotNull);
    final decoded = raster.decodePng(png!.bytes);
    expect(decoded, isNotNull);
    final cx = decoded!.width ~/ 2;
    final near = decoded.getPixel(cx, 1);
    final far = decoded.getPixel(cx, decoded.height - 2);
    expect(near.b, greaterThan(near.r + 8),
        reason: 'picture Reflection PNG must show the original bottom (blue) '
            'nearest the source');
    expect(near.a, greaterThan(far.a),
        reason: 'picture Reflection PNG must fade toward the far edge');

    final flipped = shape.copyWith(
      id: 2,
      name: 'MirrorPictureFlipY',
      flipY: true,
    );
    expect(shapeNeedsLibvisioReflectionBake(flipped), isTrue);
    var flipDoc = parser.parse(blank);
    flipDoc = flipDoc.copyWith(images: flipDoc.images.withImage(sourceImage));
    flipDoc = flipDoc.replacePage(0, flipDoc.pages.first.addShape(flipped));
    final flippedBaked = documentForLibvisioWrite(flipDoc);
    final flippedPlate =
        flippedBaked.pages.first.shapes.where(isLibvisioReflectionPlate).single;
    expect(flippedPlate.flipY, isFalse,
        reason: 'copying FlipY onto the PNG would mirror the band twice');
    expect(
      flippedPlate.pinY - flippedPlate.effectiveLocPinY,
      greaterThan(flipped.pinY - flipped.effectiveLocPinY),
      reason: 'FlipY band sits past local max Y so Draw keeps it on the '
          'visual-bottom side after the source FlipY',
    );
    final flippedPng = raster.decodePng(
      flippedBaked.images.findByPart(flippedPlate.imagePartName!)!.bytes,
    )!;
    final flippedCx = flippedPng.width ~/ 2;
    final nearFlip = flippedPng.getPixel(flippedCx, flippedPng.height - 2);
    final farFlip = flippedPng.getPixel(flippedCx, 1);
    expect(
      nearFlip.r,
      greaterThan(nearFlip.b + 8),
      reason: 'FlipY picture Reflection nearest the source must be the '
          'original top (red), matching canvas FlipY then mirror',
    );
    expect(
      nearFlip.a,
      greaterThan(farFlip.a),
      reason: 'FlipY PNG near-axis rows must land on min Y (image bottom)',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(savedDoc.pages.first.findShapeById(1)!.reflection.enabled, isFalse);
    expect(savedDoc.pages.first.findShapeById(1)!.hasImage, isTrue);
    final savedPlate = savedDoc.pages.first.shapes
        .firstWhere((s) => s.name == '${kLibvisioReflectionShapeNamePrefix}1');
    expect(savedPlate.hasImage, isTrue);

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    expect(oracle.svgPages(saved)?.join() ?? '', isNotEmpty);
  });

  test('cropped picture Reflection composites the Img window for LibreOffice',
      () {
    const part = '/visio/media/crop_reflection.png';
    final rasterImage = raster.Image(width: 32, height: 16);
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 32; x++) {
        if (x < 16) {
          rasterImage.setPixelRgba(x, y, 255, 0, 0, 255);
        } else {
          rasterImage.setPixelRgba(x, y, 0, 0, 255, 255);
        }
      }
    }
    final sourceImage = VsdxImage(
      partName: part,
      bytes: Uint8List.fromList(raster.encodePng(rasterImage)),
      mimeType: 'image/png',
    );
    final shape = VsdxShapeFactory.picture(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.2,
      height: 0.8,
      imagePartName: part,
      name: 'CropMirrorPicture',
    ).copyWith(
      reflection: const VsdxReflection(
        enabled: true,
        sizeInches: 0.5,
        distanceInches: 0.08,
        transparency: 0.4,
        blurInches: 0,
      ),
      imgOffsetXInches: -1.2,
      imgOffsetYInches: 0,
      imgWidthInches: 2.4,
      imgHeightInches: 0.8,
    );
    expect(shapeNeedsLibvisioReflectionBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.copyWith(images: doc.images.withImage(sourceImage));
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final plates = baked.pages.first.shapes.where(isLibvisioReflectionPlate);
    expect(plates, hasLength(1));
    final png = baked.images.findByPart(plates.single.imagePartName!);
    expect(png, isNotNull);
    final decoded = raster.decodePng(png!.bytes);
    expect(decoded, isNotNull);
    final leftX = (decoded!.width * 0.25).round().clamp(0, decoded.width - 1);
    final near = decoded.getPixel(leftX, 1);
    expect(near.a, greaterThan(8),
        reason: 'cropped picture Reflection PNG must have pixels nearest '
            'the source');
    expect(near.b, greaterThan(near.r + 8),
        reason: 'cropped picture Reflection must mirror the visible right '
            '(blue) half, not the hidden left (red) half');

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    final source = savedDoc.pages.first.findShapeById(1)!;
    expect(source.reflection.enabled, isFalse);
    expect(source.imgOffsetXInches, closeTo(-1.2, 1e-9));
    expect(source.effectiveImgWidth, closeTo(2.4, 1e-9));
    final savedPlate = savedDoc.pages.first.shapes
        .firstWhere((s) => s.name == '${kLibvisioReflectionShapeNamePrefix}1');
    expect(savedPlate.hasImage, isTrue);
    expect(savedPlate.imgOffsetXInches, closeTo(0, 1e-9));

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    expect(oracle.svgPages(saved)?.join() ?? '', isNotEmpty);
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
      miterLimitForLibvisioChamfer(const VsdxLine(
        cap: LineCap.square,
        miterLimit: 1,
        weightInches: 0.08,
      )),
      1,
    );
    expect(
      chamferForLibvisioWrite(const VsdxLine(
        cap: LineCap.square,
        miterLimit: 1,
        weightInches: 0.08,
      )),
      isTrue,
    );
    expect(
      roundingForLibvisioWrite(const VsdxLine(
        cap: LineCap.square,
        miterLimit: 1,
        weightInches: 0.08,
      )),
      closeTo(0.04, 1e-12),
    );
    expect(
      miterLimitForLibvisioChamfer(const VsdxLine(
        cap: LineCap.square,
        miterLimit: 8,
        weightInches: 0.08,
      )),
      isNull,
    );
    expect(
      shapeNeedsLibvisioMiterSpikeBake(
        VsdxShapeFactory.line(
          id: 1,
          ax: 1,
          ay: 3,
          bx: 5,
          by: 3,
          line: const VsdxLine(
            cap: LineCap.square,
            miterLimit: 9,
            weightInches: 0.08,
          ),
        ).withDrawioMiterLimit(9),
      ),
      isFalse,
      reason: 'a straight edge has no Draw-clipped elbow to ribbon',
    );
    expect(
      shapeNeedsLibvisioRoundCapMiterFlatten(
        VsdxShapeFactory.rectangle(
          id: 1,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(
            color: VsdxColor.black,
            cap: LineCap.round,
            join: VsdxLineJoin.miter,
            weightInches: 0.08,
          ),
        ),
      ),
      isTrue,
      reason: 'Draw would round-join from LineCap; canvas keeps the miter',
    );
    expect(
      shapeNeedsLibvisioRoundCapMiterFlatten(
        VsdxShapeFactory.line(
          id: 1,
          ax: 1,
          ay: 3,
          bx: 5,
          by: 3,
          line: const VsdxLine(
            cap: LineCap.round,
            join: VsdxLineJoin.miterClip,
            miterLimit: 9,
            weightInches: 0.08,
          ),
        ).withDrawioLineJoin(VsdxLineJoin.miterClip).withDrawioMiterLimit(9),
      ),
      isFalse,
      reason: 'a straight edge has no join; keep the round cap',
    );
    expect(
      shapeNeedsLibvisioFilledStrokeRibbonBake(
        VsdxShapeFactory.rectangle(
          id: 1,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
          fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
          line: const VsdxLine(
            color: VsdxColor.black,
            weightInches: 0.08,
            transparency: 0.5,
          ),
        ),
      ),
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

  test('custom Dash Pattern bakes MoveTo dashes for LibreOffice', () {
    final shape = VsdxShapeFactory.line(
      id: 1,
      ax: 1,
      ay: 3,
      bx: 7,
      by: 3,
      name: 'CustomDash',
      line: const VsdxLine(
        color: VsdxColor(0xFF000000),
        weightInches: 0.15,
        pattern: 2,
      ),
    ).withDrawioDashPattern(const <double>[8, 4]);
    expect(shapeNeedsLibvisioCustomDashBake(shape), isTrue);
    expect(shape.line.customDashPattern, <double>[8, 4]);

    final write = libvisioShapeWrite(shape);
    expect(write.line.pattern, 1);
    expect(write.line.customDashPattern, isNull);
    expect(write.geometryRewritten, isTrue);
    var moves = 0;
    for (final geometry in write.geometries) {
      for (final command in geometry.commands) {
        if (command is MoveTo) moves++;
      }
    }
    expect(moves, greaterThan(1),
        reason: 'custom [8, 4] must become multiple dash subpaths, not a '
            'single LinePattern-2 stroke');
    expect(userCellsForLibvisioWrite(shape), isEmpty);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final saved = writer.write(originalBytes: blank, edited: doc);
    final after = parser.parse(saved).pages.first.findShapeById(1)!;
    expect(after.line.pattern, 1);
    expect(after.line.customDashPattern, isNull);
    expect(
      after.userCells.any((cell) => cell.name == VsdxShape.userDashPattern),
      isFalse,
    );
    var savedMoves = 0;
    for (final geometry in after.geometries) {
      for (final command in geometry.commands) {
        if (command is MoveTo) savedMoves++;
      }
    }
    expect(savedMoves, greaterThan(1));

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    expect(oracle.svgPages(saved)?.join() ?? '', isNotEmpty);
  });

  test('Flow Animation bakes the synthesised 8 CSS-px dash for LibreOffice',
      () {
    final shape = VsdxShapeFactory.line(
      id: 1,
      ax: 1,
      ay: 3,
      bx: 7,
      by: 3,
      name: 'FlowDash',
      line: const VsdxLine(
        color: VsdxColor(0xFF000000),
        weightInches: 0.04,
        pattern: 1,
      ),
    ).withFlowAnimation(true);
    expect(shape.flowAnimation, isTrue);
    expect(shape.line.customDashPattern, isNull);
    expect(shapeNeedsLibvisioFlowDashBake(shape), isTrue);
    expect(
      flowAnimationDashInchesForLibvisioWrite(shape),
      <double>[8 * drawioDashUnitInches, 8 * drawioDashUnitInches],
    );

    final write = libvisioShapeWrite(shape);
    expect(write.line.pattern, 1);
    expect(write.geometryRewritten, isTrue);
    var moves = 0;
    for (final geometry in write.geometries) {
      for (final command in geometry.commands) {
        if (command is MoveTo) moves++;
      }
    }
    expect(moves, greaterThan(1),
        reason: 'Flow Animation must become multiple dash subpaths, not a '
            'solid LinePattern-1 stroke Draw would paint');
    expect(write.line.beginArrow, 0);
    expect(write.line.endArrow, 0);
    expect(
      userCellsForLibvisioWrite(shape).any(
        (cell) =>
            cell.name == VsdxShape.userFlowAnimation &&
            (double.tryParse(cell.value ?? '') ?? 1) == 0,
      ),
      isTrue,
    );
    expect(
      userCellsForLibvisioWrite(shape).any(
        (cell) => cell.name == VsdxShape.userDashPattern,
      ),
      isFalse,
    );

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final saved = writer.write(originalBytes: blank, edited: doc);
    final after = parser.parse(saved).pages.first.findShapeById(1)!;
    expect(after.flowAnimation, isFalse);
    expect(after.line.pattern, 1);
    expect(after.line.customDashPattern, isNull);
    var savedMoves = 0;
    for (final geometry in after.geometries) {
      for (final command in geometry.commands) {
        if (command is MoveTo) savedMoves++;
      }
    }
    expect(savedMoves, greaterThan(1));
    expect(after.line.pattern, 1);

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    expect(oracle.svgPages(saved)?.join() ?? '', isNotEmpty);
  });

  test('arrowed Flow Animation / custom dash bake markers then dashes', () {
    VsdxShape arrowed({
      required int id,
      required String name,
      required VsdxShape Function(VsdxShape) decorate,
    }) {
      return decorate(
        VsdxShapeFactory.line(
          id: id,
          ax: 1,
          ay: 3,
          bx: 7,
          by: 3,
          name: name,
          line: const VsdxLine(
            color: VsdxColor(0xFF000000),
            weightInches: 0.04,
            pattern: 1,
            beginArrow: 0,
            endArrow: 4,
            endArrowSizeInches: 0.125,
          ),
        ),
      );
    }

    final flow = arrowed(
      id: 1,
      name: 'FlowDashArrow',
      decorate: (shape) => shape.withFlowAnimation(true),
    );
    final custom = arrowed(
      id: 2,
      name: 'CustomDashArrow',
      decorate: (shape) => shape.withDrawioDashPattern(const <double>[8, 8]),
    );
    expect(shapeNeedsLibvisioFlowDashBake(flow), isTrue);
    expect(shapeNeedsLibvisioCustomDashBake(custom), isTrue);
    expect(shapeNeedsLibvisioArrowedStrokeBake(flow), isTrue);
    expect(shapeNeedsLibvisioArrowedStrokeBake(custom), isTrue);

    for (final shape in <VsdxShape>[flow, custom]) {
      final write = libvisioShapeWrite(shape);
      expect(write.line.beginArrow, 0);
      expect(write.line.endArrow, 0);
      expect(
        write.geometries.where((geometry) => !geometry.noFill).length,
        1,
        reason: '${shape.name} must keep one filled arrow Geometry so Draw '
            'does not hang a marker on every open dash',
      );
      var moves = 0;
      for (final geometry in write.geometries) {
        if (!geometry.noFill) continue;
        for (final command in geometry.commands) {
          if (command is MoveTo) moves++;
        }
      }
      expect(moves, greaterThan(1),
          reason: '${shape.name} must still flatten dashes after baking the '
              'arrow');
    }

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(flow).addShape(custom),
    );
    final saved = writer.write(originalBytes: blank, edited: doc);
    final page = parser.parse(saved).pages.first;
    for (final name in <String>['FlowDashArrow', 'CustomDashArrow']) {
      final after = page.shapes.firstWhere((s) => s.name == name);
      expect(after.line.endArrow, 0);
      expect(after.flowAnimation, isFalse);
      expect(
        after.geometries.where((geometry) => !geometry.noFill).length,
        1,
      );
    }

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    expect(oracle.svgPages(saved)?.join() ?? '', isNotEmpty);
  });

  test('built-in LinePattern keeps dash gaps in a LineColorTrans ribbon', () {
    final shape = VsdxShapeFactory.line(
      id: 1,
      ax: 1,
      ay: 3,
      bx: 7,
      by: 3,
      name: 'PatternDashTrans',
      line: const VsdxLine(
        color: VsdxColor(0xFF000000),
        weightInches: 0.15,
        pattern: 2,
        transparency: 0.5,
      ),
    );
    expect(shapeNeedsLibvisioLinePatternDashBake(shape), isTrue);

    final write = libvisioShapeWrite(shape);
    expect(write.line.pattern, 0);
    expect(write.line.transparency, closeTo(0, 1e-9));
    expect(
      write.geometries.where((geometry) => !geometry.noFill).length,
      greaterThan(1),
    );

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final saved = writer.write(originalBytes: blank, edited: doc);
    final after = parser.parse(saved).pages.first.findShapeById(1)!;
    expect(after.line.pattern, 0);
    expect(
      after.geometries.where((geometry) => !geometry.noFill).length,
      greaterThan(1),
    );

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    expect(oracle.svgPages(saved)?.join() ?? '', isNotEmpty);
  });

  test('tight miterLimit bakes LineTo chamfers for LibreOffice', () {
    final shape = VsdxShape(
      id: 1,
      name: 'TightMiter',
      pinX: 4.25,
      pinY: 5.5,
      width: 2,
      height: 2,
      geometries: const <VsdxGeometry>[
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(0, 0),
            LineTo(2, 0),
            LineTo(2, 2),
          ],
        ),
      ],
      line: const VsdxLine(
        color: VsdxColor.black,
        weightInches: 0.2,
        cap: LineCap.square,
        miterLimit: 1,
      ),
    ).withDrawioMiterLimit(1);
    expect(miterLimitForLibvisioChamfer(shape.line), 1);

    final write = libvisioShapeWrite(shape);
    expect(write.line.miterLimit, closeTo(4, 1e-12));
    expect(
      userCellsForLibvisioWrite(shape).any(
        (cell) => cell.name == VsdxShape.userMiterLimit,
      ),
      isFalse,
    );

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final saved = writer.write(originalBytes: blank, edited: doc);
    final after = parser.parse(saved).pages.first.findShapeById(1)!;
    expect(after.line.roundingInches, closeTo(0, 1e-12));
    expect(after.line.miterLimit, closeTo(4, 1e-12));
    expect(
      after.userCells.any((cell) => cell.name == VsdxShape.userMiterLimit),
      isFalse,
    );
    expect(after.geometries.single.commands.whereType<RelQuadBezTo>(), isEmpty);
    expect(
      after.geometries.single.commands.whereType<LineTo>().length,
      greaterThan(2),
    );
    expect(
      after.geometries.single.commands.whereType<LineTo>().any(
            (command) =>
                (command.x - 2).abs() < 1e-9 && (command.y - 0).abs() < 1e-9,
          ),
      isFalse,
      reason: '90° elbow must be chamfered so Draw cannot grow a default miter',
    );
  });

  test('high miterLimit bakes a filled ribbon spike for LibreOffice', () {
    final shape = VsdxShape(
      id: 1,
      name: 'LongMiter',
      pinX: 4.25,
      pinY: 5.5,
      width: 4.5,
      height: 2,
      geometries: const <VsdxGeometry>[
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(0.2, 1.0),
            LineTo(2.5, 1.0),
            LineTo(0.2, 1.45),
          ],
        ),
      ],
      line: const VsdxLine(
        color: VsdxColor.black,
        weightInches: 0.24,
        cap: LineCap.square,
        miterLimit: 12,
      ),
    ).withDrawioMiterLimit(12);
    expect(shapeNeedsLibvisioMiterSpikeBake(shape), isTrue);
    expect(miterLimitForLibvisioChamfer(shape.line), isNull);

    final write = libvisioShapeWrite(shape);
    expect(write.line.pattern, 0);
    expect(write.line.miterLimit, closeTo(4, 1e-12));
    expect(write.fill.hasFill, isTrue);
    expect(
      userCellsForLibvisioWrite(shape).any(
        (cell) => cell.name == VsdxShape.userMiterLimit,
      ),
      isFalse,
    );

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final saved = writer.write(originalBytes: blank, edited: doc);
    final after = parser.parse(saved).pages.first.findShapeById(1)!;
    expect(after.line.pattern, 0);
    expect(after.fill.hasFill, isTrue);
    expect(after.line.miterLimit, closeTo(4, 1e-12));
    expect(
      after.userCells.any((cell) => cell.name == VsdxShape.userMiterLimit),
      isFalse,
    );
    expect(after.geometries.single.noLine, isTrue);
    expect(
      after.geometries.single.commands.whereType<LineTo>().length,
      greaterThan(3),
    );
    var maxX = 0.0;
    for (final command in after.geometries.single.commands) {
      if (command is MoveTo && command.x > maxX) maxX = command.x;
      if (command is LineTo && command.x > maxX) maxX = command.x;
    }
    expect(
      maxX,
      greaterThan(3.2),
      reason: 'ribbon outline must include the canvas miter spike past x=2.5',
    );
  });

  test('round cap plus explicit miter flattens LineCap for LibreOffice', () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4.25,
      pinY: 5.5,
      width: 2,
      height: 1.2,
      name: 'RoundCapMiter',
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(
        color: VsdxColor.black,
        weightInches: 0.24,
        cap: LineCap.round,
        join: VsdxLineJoin.miter,
      ),
    ).withDrawioLineJoin(VsdxLineJoin.miter);
    expect(shapeNeedsLibvisioRoundCapMiterFlatten(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final saved = writer.write(originalBytes: blank, edited: doc);
    final after = parser.parse(saved).pages.first.findShapeById(1)!;
    expect(after.line.cap, LineCap.extended);
    expect(after.line.join, VsdxLineJoin.miter);
    expect(after.line.pattern, 1);
  });

  test('filled LineColorTrans bakes a sibling ribbon for LibreOffice', () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4.25,
      pinY: 5.5,
      width: 2,
      height: 1.2,
      name: 'FilledLineTrans',
      fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
      line: const VsdxLine(
        color: VsdxColor.black,
        weightInches: 0.2,
        transparency: 0.5,
      ),
    );
    expect(shapeNeedsLibvisioFilledStrokeRibbonBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final saved = writer.write(originalBytes: blank, edited: doc);
    final page = parser.parse(saved).pages.first;
    final after = page.findShapeById(1)!;
    expect(after.fill.foreground?.value, 0xFFFF0000);
    expect(after.line.pattern, 0);
    expect(after.line.transparency, closeTo(0, 1e-12));
    final plate = page.shapes.firstWhere(isLibvisioStrokeRibbonPlate);
    expect(plate.locked, isTrue);
    expect(plate.line.pattern, 0);
    expect(plate.fill.foregroundTransparency, closeTo(0.5, 1e-9));
    expect(plate.geometries.any((g) => !g.noFill), isTrue);

    final arrowed = VsdxShapeFactory.rectangle(
      id: 3,
      pinX: 4.25,
      pinY: 5.5,
      width: 2,
      height: 1.2,
      name: 'FilledLineTransArrows',
      fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
      line: const VsdxLine(
        color: VsdxColor.black,
        weightInches: 0.2,
        transparency: 0.5,
        beginArrow: 4,
        endArrow: 13,
      ),
    );
    expect(shapeNeedsLibvisioFilledStrokeRibbonBake(arrowed), isTrue,
        reason: 'closed 2-D arrow cells must not skip the LineColorTrans ribbon');
  });

  test('filled CompoundType LineColorTrans bakes rails on the sibling ribbon',
      () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4.25,
      pinY: 5.5,
      width: 2,
      height: 1.2,
      name: 'FilledCompoundTrans',
      fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
      line: const VsdxLine(
        color: VsdxColor.black,
        weightInches: 0.24,
        transparency: 0.5,
        compoundType: 1,
      ),
    );
    expect(shapeNeedsLibvisioFilledStrokeRibbonBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.fill.foreground?.value, 0xFFFF0000);
    expect(source.line.pattern, 0);
    expect(source.line.compoundType, 0);
    expect(source.line.transparency, closeTo(0, 1e-12));
    final plate =
        baked.pages.first.shapes.where(isLibvisioStrokeRibbonPlate).single;
    expect(plate.locked, isTrue);
    expect(plate.line.pattern, 0);
    expect(plate.fill.foregroundTransparency, closeTo(0.5, 1e-9));
    expect(
      plate.geometries.where((g) => !g.noFill).length,
      greaterThanOrEqualTo(2),
      reason: 'CompoundType 1 must become two filled rails on the sibling',
    );
    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedPage = parser.parse(saved).pages.first;
    expect(savedPage.findShapeById(1)!.line.compoundType, 0);
    expect(savedPage.findShapeById(1)!.fill.foreground?.value, 0xFFFF0000);
    expect(
      savedPage.shapes.where(isLibvisioStrokeRibbonPlate).single.geometries
          .where((g) => !g.noFill)
          .length,
      greaterThanOrEqualTo(2),
    );

    const wash = VsdxGradient(
      stops: <VsdxGradientStop>[
        VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
        VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
      ],
    );
    final gradient = VsdxShapeFactory.rectangle(
      id: 2,
      pinX: 4.25,
      pinY: 5.5,
      width: 2,
      height: 1.2,
      name: 'FilledCompoundGrad',
      fill: const VsdxFill(foreground: VsdxColor(0xFFFFFF00), pattern: 1),
      line: const VsdxLine(
        color: VsdxColor.black,
        weightInches: 0.24,
        compoundType: 1,
        gradient: wash,
      ),
    );
    expect(shapeNeedsLibvisioFilledStrokeRibbonBake(gradient), isTrue);
    var gradDoc = parser.parse(blank);
    gradDoc = gradDoc.replacePage(0, gradDoc.pages.first.addShape(gradient));
    final gradSaved = writer.write(originalBytes: blank, edited: gradDoc);
    final gradPage = parser.parse(gradSaved).pages.first;
    final gradSource = gradPage.findShapeById(2)!;
    expect(gradSource.fill.foreground?.value, 0xFFFFFF00);
    expect(gradSource.line.hasGradient, isFalse);
    expect(gradSource.line.compoundType, 0);
    final gradPlate = gradPage.shapes.where(isLibvisioStrokeRibbonPlate).single;
    expect(
      gradPlate.fill.hasGradient ||
          (gradPlate.fill.pattern >= 25 && gradPlate.fill.pattern <= 40),
      isTrue,
      reason: 'filled CompoundType LineGradient must ride the sibling fill',
    );
    expect(
      gradPlate.geometries.where((g) => !g.noFill).length,
      greaterThanOrEqualTo(2),
    );
  });

  test('filled high miterLimit bakes a sibling ribbon spike for LibreOffice',
      () {
    final shape = VsdxShape(
      id: 1,
      name: 'FilledLongMiter',
      pinX: 4.25,
      pinY: 5.5,
      width: 4.5,
      height: 2,
      geometries: const <VsdxGeometry>[
        VsdxGeometry(
          commands: <VsdxPathCommand>[
            MoveTo(0.2, 1.0),
            LineTo(2.5, 1.0),
            LineTo(0.2, 1.45),
            LineTo(0.2, 1.0),
          ],
        ),
      ],
      fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
      line: const VsdxLine(
        color: VsdxColor.black,
        weightInches: 0.24,
        cap: LineCap.square,
        miterLimit: 12,
      ),
    ).withDrawioMiterLimit(12);
    expect(shapeNeedsLibvisioFilledStrokeRibbonBake(shape), isTrue);
    expect(shapeNeedsLibvisioMiterSpikeBake(shape), isFalse);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final saved = writer.write(originalBytes: blank, edited: doc);
    final page = parser.parse(saved).pages.first;
    final after = page.findShapeById(1)!;
    expect(after.fill.foreground?.value, 0xFFFF0000);
    expect(after.line.pattern, 0);
    expect(
      after.userCells.any((cell) => cell.name == VsdxShape.userMiterLimit),
      isFalse,
    );
    final plate = page.shapes.firstWhere(isLibvisioStrokeRibbonPlate);
    var maxX = 0.0;
    for (final geometry in plate.geometries) {
      for (final command in geometry.commands) {
        if (command is MoveTo && command.x > maxX) maxX = command.x;
        if (command is LineTo && command.x > maxX) maxX = command.x;
      }
    }
    expect(maxX, greaterThan(3.2));
  });

  test('filled dashed LineColorTrans bakes dash ribbons for LibreOffice', () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4.25,
      pinY: 5.5,
      width: 2,
      height: 1.2,
      name: 'FilledDashTrans',
      fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
      line: const VsdxLine(
        color: VsdxColor.black,
        weightInches: 0.2,
        transparency: 0.5,
        pattern: 2,
      ),
    );
    expect(shapeNeedsLibvisioFilledStrokeRibbonBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final saved = writer.write(originalBytes: blank, edited: doc);
    final page = parser.parse(saved).pages.first;
    final after = page.findShapeById(1)!;
    expect(after.fill.foreground?.value, 0xFFFF0000);
    expect(after.line.pattern, 0);
    final plate = page.shapes.firstWhere(isLibvisioStrokeRibbonPlate);
    expect(plate.locked, isTrue);
    expect(plate.fill.foregroundTransparency, closeTo(0.5, 1e-9));
    expect(
      plate.geometries.where((g) => !g.noFill).length,
      greaterThan(1),
      reason: 'each dash must be its own filled ribbon, not a solid ring',
    );
  });

  test('filled open-path LineColorTrans bakes arrow Geometry on the ribbon',
      () {
    final shape = VsdxShape(
      id: 1,
      name: 'FilledOpenArrows',
      pinX: 4.25,
      pinY: 5.5,
      width: 3,
      height: 1.2,
      geometries: const <VsdxGeometry>[
        VsdxGeometry(
          commands: <VsdxPathCommand>[
            MoveTo(0.1, 0.2),
            LineTo(2.9, 0.2),
            LineTo(2.9, 1.0),
          ],
        ),
      ],
      fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
      line: const VsdxLine(
        color: VsdxColor.black,
        weightInches: 0.16,
        transparency: 0.5,
        beginArrow: 4,
        endArrow: 13,
        beginArrowSizeInches: 0.25,
        endArrowSizeInches: 0.25,
      ),
    );
    expect(shapeNeedsLibvisioFilledStrokeRibbonBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.fill.foreground?.value, 0xFFFF0000);
    expect(source.line.pattern, 0);
    expect(source.line.beginArrow, 0);
    expect(source.line.endArrow, 0);
    final plate =
        baked.pages.first.shapes.where(isLibvisioStrokeRibbonPlate).single;
    expect(plate.line.beginArrow, 0);
    expect(plate.line.endArrow, 0);
    expect(
      plate.geometries.where((g) => !g.noFill).length,
      greaterThan(1),
      reason: 'arrow polygons ride the sibling whose fill is the stroke',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedPage = parser.parse(saved).pages.first;
    expect(savedPage.findShapeById(1)!.line.endArrow, 0);
    expect(
      savedPage.shapes.where(isLibvisioStrokeRibbonPlate).single.geometries
          .where((g) => !g.noFill)
          .length,
      greaterThan(1),
    );
  });

  test('1-D stroke Reflection bakes a PNG band for LibreOffice', () {
    const colour = VsdxColor(0xFF1565C0);
    final shape = VsdxShapeFactory.line(
      id: 1,
      ax: 2,
      ay: 5.5,
      bx: 6.5,
      by: 5.5,
      name: 'ReflectionStroke1d',
      line: const VsdxLine(
        color: colour,
        weightInches: 0.12,
      ),
    ).copyWith(
      reflection: const VsdxReflection(
        enabled: true,
        sizeInches: 1,
        distanceInches: 0.08,
        transparency: 0.2,
        blurInches: 0,
      ),
    );
    expect(shape.is1D, isTrue);
    expect(shape.height.abs(), closeTo(0, 1e-12));
    expect(shapeNeedsLibvisioReflectionBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.is1D, isTrue);
    expect(source.line.pattern, 1);
    expect(source.fill.pattern, 0);
    final plate =
        baked.pages.first.shapes.where(isLibvisioReflectionPlate).single;
    expect(plate.hasImage, isTrue);
    expect(plate.is1D, isFalse);
    expect(plate.height, greaterThan(0.05));
    final decoded = raster.decodePng(
      baked.images.findByPart(plate.imagePartName!)!.bytes,
    )!;
    var ink = 0;
    for (var y = 0; y < decoded.height; y++) {
      for (var x = 0; x < decoded.width; x++) {
        final pixel = decoded.getPixel(x, y);
        if (pixel.b > pixel.r + 15 && pixel.a > 20) ink++;
      }
    }
    expect(ink, greaterThan(8),
        reason: 'the 1-D mirror PNG must carry stroke ink, not an empty plate');

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(savedDoc.pages.first.findShapeById(1)!.reflection.enabled, isFalse);
    expect(
      savedDoc.pages.first.shapes.where(isLibvisioReflectionPlate),
      hasLength(1),
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
        'FillGradientNoPattern',
        const VsdxFill(
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
        pinX: 6.8,
        pinY: 1.2,
        width: 1.4,
        height: 0.7,
        name: 'GlowNoFill',
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(
          color: VsdxColor.black,
          pattern: 1,
          weightInches: 0.04,
        ),
      ).copyWith(
        glow: const VsdxGlow(
          color: VsdxColor(0xFF00CC66),
          sizeInches: 0.08,
          transparency: 0.4,
        ),
      ),
    );
    built = built.addShape(
      VsdxShapeFactory.rectangle(
        id: nextId++,
        pinX: 5,
        pinY: 2.8,
        width: 1.4,
        height: 0.7,
        name: 'GlowFillStroke',
        fill: const VsdxFill(foreground: VsdxColor(0xFFEEEEEE), pattern: 1),
        line: const VsdxLine(
          color: VsdxColor.black,
          pattern: 1,
          weightInches: 0.02,
        ),
      ).copyWith(
        glow: const VsdxGlow(
          color: VsdxColor(0xFF00CC66),
          sizeInches: 0.08,
          transparency: 0.4,
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
          blurInches: 0,
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
    expect(filledLineTrans.line.pattern, 0,
        reason: 'filled 2-D LineColorTrans drops the source stroke');
    expect(filledLineTrans.line.transparency, closeTo(0, 1e-12));
    final filledLineTransPlate = savedDoc.pages.first.shapes.firstWhere(
      (s) =>
          s.name ==
          '$kLibvisioStrokeRibbonShapeNamePrefix${filledLineTrans.id}',
    );
    expect(
        filledLineTransPlate.fill.foregroundTransparency, closeTo(0.4, 1e-9));
    expect(filledLineTransPlate.line.pattern, 0);
    expect(filledLineTransPlate.geometries.any((g) => !g.noFill), isTrue);
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
        reason: 'GlowSize is not a token; filled NoLine RGB bakes a PNG');
    expect(glowNoLine.line.pattern, 0);
    final glowNoLinePlate = savedDoc.pages.first.shapes.firstWhere(
      (s) => s.name == '$kLibvisioGlowShapeNamePrefix${glowNoLine.id}',
    );
    expect(glowNoLinePlate.hasImage, isTrue);
    expect(glowNoLinePlate.width, greaterThan(glowNoLine.width));
    final glowStroke =
        savedDoc.pages.first.shapes.firstWhere((s) => s.name == 'GlowStroke');
    expect(glowStroke.glow.enabled, isFalse);
    expect(glowStroke.fill.hasFill, isFalse);
    expect(glowStroke.line.hasLine, isTrue);
    final glowStrokePlate = savedDoc.pages.first.shapes.firstWhere(
      (s) => s.name == '$kLibvisioGlowShapeNamePrefix${glowStroke.id}',
    );
    expect(glowStrokePlate.hasImage, isTrue);
    expect(glowStrokePlate.is1D, isFalse);
    expect(glowStrokePlate.height, greaterThan(0.1));
    final glowNoFill =
        savedDoc.pages.first.shapes.firstWhere((s) => s.name == 'GlowNoFill');
    expect(glowNoFill.glow.enabled, isFalse,
        reason: 'unfilled 2-D RGB bakes a Gaussian PNG ring');
    expect(glowNoFill.fill.hasFill, isFalse);
    expect(glowNoFill.line.pattern, 1);
    final glowNoFillPlate = savedDoc.pages.first.shapes.firstWhere(
      (s) => s.name == '$kLibvisioGlowShapeNamePrefix${glowNoFill.id}',
    );
    expect(glowNoFillPlate.hasImage, isTrue);
    expect(glowNoFillPlate.width, greaterThan(glowNoFill.width));
    final glowFillStroke = savedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'GlowFillStroke');
    expect(glowFillStroke.glow.enabled, isFalse,
        reason: 'filled stroke Glow bakes a sibling Gaussian PNG');
    expect(glowFillStroke.line.pattern, 1);
    final glowFillPlate = savedDoc.pages.first.shapes.firstWhere(
      (s) => s.name == '$kLibvisioGlowShapeNamePrefix${glowFillStroke.id}',
    );
    expect(glowFillPlate.hasImage, isTrue);
    expect(glowFillPlate.width, greaterThan(glowFillStroke.width));
    expect(
      savedDoc.pages.first.shapes
          .firstWhere((s) => s.name == 'FillUnknown')
          .fill
          .pattern,
      1,
      reason: 'FillPattern 41 is not a hatch/gradient id Draw paints',
    );
    final gradientNoPattern = savedDoc.pages.first.shapes
        .firstWhere((s) => s.name == 'FillGradientNoPattern');
    expect(gradientNoPattern.fill.hasFill, isTrue);
    expect(gradientNoPattern.fill.pattern, inInclusiveRange(25, 40),
        reason: 'omitted FillPattern must bake classic 25–40 for Draw');
    expect(gradientNoPattern.fill.paintGradient, isNotNull);
    expect(gradientNoPattern.fill.foreground, isNotNull);
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

  test('数据治理 chevron FillGradient paints despite omitted FillPattern', () {
    final bytes = File('test/fixtures/数据治理.vsdx').readAsBytesSync();
    final doc = parser.parse(bytes);
    final arrow = doc.pages.first.findShapeById(147)!;
    expect(arrow.fill.pattern, 0);
    expect(arrow.fill.hasGradient, isTrue);
    expect(arrow.fill.hasFill, isTrue);
    expect(
      shapeNeedsLibvisioStrokeRibbon(arrow),
      isFalse,
      reason: 'must not steal the chevron body as an unfilled LineGradient ribbon',
    );
    expect(fillPatternForLibvisioWrite(arrow.fill), inInclusiveRange(25, 40));
    final write = libvisioShapeWrite(arrow);
    expect(write.fill.pattern, inInclusiveRange(25, 40));
    expect(write.fill.foreground, isNotNull);
    expect(write.fill.background, isNotNull);

    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('linearGradient'));

    final saved = writer.write(originalBytes: bytes, edited: doc);
    final after = parser.parse(saved).pages.first.findShapeById(147)!;
    expect(after.fill.hasFill, isTrue);
    expect(after.fill.paintGradient, isNotNull);
    expect(after.fill.pattern, isNot(0));
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
