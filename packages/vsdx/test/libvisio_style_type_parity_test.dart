/// Fill, line and Rounding types must paint here, and a save must emit the
/// cells / rows LibreOffice's libvisio importer still collects.
///
/// `VSDXParser` has no FillGradient token, no shape-level Rounding, no
/// CompoundType token, no LineGradient token, and no LineColorTrans token
/// (`xmlStringToColour` also forces Colour.a = 0). A modern gradient with
/// FillPattern=1 (or omitted FillPattern / 0, libvisio's shape default), a polyline with only a Rounding cell, a CompoundType>0
/// stroke, an unfilled LineGradient, or a semi-transparent stroke
/// disappears or goes fully opaque in Draw. The writer rewrites those to
/// classic FillPattern 25–40 (a FillGradient with more than two unique
/// opaque colours, or per-stop / Fill*Trans alpha Draw would paint
/// opaque — including a fully transparent stop 25–40 would replace
/// with the next opaque colour — bakes a PNG plate instead; EllipticalArcTo silhouettes
/// are sampled so a pie is not a triangle and a rounded rectangle is not
/// the Width×Height box; multiple NoFill=0 Geometry sections punch
/// even-odd holes so a frame is not a solid plate), baked RelQuadBezTo corners, parallel Geometry
/// rails (including 1-D), and a filled ribbon for line gradients and
/// LineColorTrans (2-D and 1-D) whose FillForegndTrans libvisio *does*
/// collect. A LineGradient with more than two unique opaque colours
/// bakes a PNG plate instead. Arrowed 1-D connectors that also need rails or a ribbon bake
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
/// Sketch jiggle copies those dash cells onto the locked siblings, so the
/// same flatten applies there; leftover Geometry is already NoLine.
/// `LineCap` 0/1/2 is a token libvisio *does* collect. Character Highlight is skipped by
/// `readCharIX` but a uniform marker with no authored TextBkgnd is written
/// there — `VSDContentCollector` paints it as span `fo:background-color`
/// and Draw shows the plate. Mixed run colours cannot share that cell, so
/// a save inserts locked FillForegnd siblings of each highlighted run,
/// including explicit newlines stacked like canvas / SVG, Word Wrap
/// lines broken at TxtWidth, and tab fields pinned with
/// `visioTabFieldStart`. `TextDirection` is stored
/// but `_flushText` never emits writing-mode, so a save folds the
/// canvas −90° into `TxtAngle` and swaps TxtWidth/TxtHeight. Glueable
/// labels pin TxtPin first, then swap that tight plate. Mixed
/// Highlight on that rotated frame follows TxtPin. Connector labels
/// use the same plates after TxtPin is pinned to the route.
/// `RVNGSVGDrawingGenerator` drops that property,
/// so the oracle SVG is the wrong place to look; `vsd2raw` still has it.
/// `TextBkgndTrans` and layer `ColorTrans` have no VSDX collector case, so
/// a save premultiplies those into RGB toward white. Overline still paints
/// here even though `readCharIX` skips it; a save inserts U+0305 combining
/// marks, including tabbed runs whose `tabIndices` still name the stop
/// and field runs whose `<fld>` UTF-16 spans grow around each mark.
/// Glow* is not a token: unfilled
/// 1-D strokes with resolved RGB bake a Gaussian PNG plate, unfilled 2-D
/// with resolved RGB bakes a Gaussian PNG ring, and filled NoLine shapes
/// bake a Gaussian PNG sibling. Sketch jiggle copies Glow / Reflection
/// onto those plates so leftover NoLine Geometry does not drop the
/// effect. Theme-only Glow resolves the slot
/// (document theme, then Office) into that same PNG so Draw keeps the
/// blur canvas `_colourOrTheme` already paints. Character ColorTrans and ShdwForegndTrans
/// cannot carry alpha through `xmlStringToColour`, so a save premultiplies
/// those into RGB toward white and writes Trans=0. Theme-only Character
/// Color and hard-edged ShdwForegnd resolve through the document theme
/// then Office into that same blend (`ColorTrans` / `ShdwForegndTrans`
/// are not tokens, so THEMEVAL() would stay opaque). Soft theme shadows
/// keep THEMEVAL() after the Gaussian PNG bake.
/// Theme-bound colours with no transparency still keep THEMEVAL.
/// Theme-only FillForegnd / FillBkgnd with FillForegndTrans /
/// FillBkgndTrans freeze into RGB and keep Trans — those cells *are*
/// tokens, so Draw still composites the wash, while THEMEVAL() plus
/// QuickStyle 9 paints faded black (`getThemeColour` stops at 8).
/// Filled-shape LineColorTrans / LineGradient bake a
/// locked sibling ribbon whose FillForegndTrans Draw collects, then drop
/// the source line. Theme-only LineColor freezes into that ribbon
/// FillForegnd (document theme, then Office) so Draw does not paint the
/// black fallback. CompoundType 1–4 rails, LinePattern 2–23 dashes, and
/// open-path Begin/EndArrow join that sibling so Draw does not keep an
/// opaque stroke (or hang markers on a dropped line) on top of the wash.
/// `AsianFont` / `ComplexScriptFont` / `ComplexScriptSize` are not tokens,
/// so an Asian-only (Hangul/Kana/Han) or complex-script-only run whose
/// Visio `Font` is Arial is rewritten to the face and size Draw will
/// actually load. Mixed Latin+CJK / Latin+Arabic runs split so each
/// script collects that face; a single `Font` would keep Arial on 世界.
/// Paragraph `HorzAlign=4` emits illegal ODF `fo:text-align="full"`;
/// Draw falls back to left, so a save writes `justify` (canvas / SVG
/// already map `full` that way). Text-block `DefaultTabStop` emits
/// `style:tab-stop-distance`, but Draw ignores it and jumps 0.5", so
/// a save writes explicit Tabs stops on that interval (canvas / SVG
/// already use `visioTabFieldStart`). Character `LangID` is
/// not a token; digit-only Arabic / Hebrew runs prefix U+200F so Draw's
/// Unicode bidi matches canvas / SVG. Character `Letterspace`
/// is not a token; canvas / SVG already fold FontScale into tracking at
/// 0.55×Size, so a save adds Letterspace into FontScale and writes
/// Letterspace 0. Picture `SoftEdgesSize` is not a token; a 2-D Foreign
/// bitmap bakes the same SourceAlpha feather canvas / SVG use into PNG
/// alpha (cropped frames composite into the box first so ImgOffset still
/// matches Draw), then SoftEdgesSize is written 0. Foreign
/// `EnhMetaFile` / `MetaFile` DIB wrappers are not a bitmap Draw paints
/// — libvisio emits a metafile — so a save extracts that DIB as PNG
/// `ForeignType=Bitmap`. A thin DIB wrapper extracts that BMP; a
/// pure-vector metafile replays the same display list canvas / SVG
/// already paint onto an opaque PNG, including ExtTextOut glyphs, GDI
/// hatch / pattern brushes and clips. Foreign
/// `Object` OLE packages are the same missing paint: Draw fills Blue 2
/// for `object/ole`, so a save unwraps `\x02OlePres000` as `MetaFile` /
/// `EnhMetaFile` and the metafile bake writes PNG. Bitmap payloads with
/// no libvisio `CompressionType` (WebP, ICO, headerless DIB) become
/// `image/bmp` and vanish; a save re-encodes those as PNG. A second
/// save does not stack another PNG. Marker ids whose
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
/// Sketch jiggle copies that cap / join and `veMiterLimit` onto the
/// locked siblings, so the same flatten and high-miter ribbon apply
/// there; leftover Geometry is already NoLine.
/// Arcs joins bake the same fillets as round (canvas `canvasStrokeJoin`).
/// `Reflection*` cells are not tokens, so a
/// filled 2-D shape bakes a locked sibling plate whose FillForegndTrans
/// Draw collects, then `ReflectionSize` is written 0. An unfilled 2-D
/// stroke bakes a locked PNG band of the mirrored stroke, an unfilled
/// 1-D stroke bakes the same PNG from its stroke ribbon, and a Foreign
/// picture bakes a locked Gaussian PNG sibling of the same mirrored bitmap
/// canvas / SVG already paint (cropped pictures composite the Img*
/// window into the frame first). Theme-only LineColor on an unfilled
/// stroke resolves into that PNG so Draw keeps the mirror. Glow on a filled
/// shape that already paints a stroke, a filled NoLine 2-D, or an unfilled
/// 2-D stroke, bakes a locked Gaussian PNG sibling when RGB is resolved,
/// then `GlowSize` is written 0. A Foreign picture
/// bakes the same Gaussian PNG ring around the image frame. Theme-only
/// glow resolves the slot into that PNG so Draw keeps the blur. Page `PageColor` is not a token, so
/// a save prepends a locked full-page plate Draw can fill. draw.io Sketch
/// is User rows libvisio never reads, so a save maps the hatch onto
/// FillPattern 2–24 and bakes the two jiggle strokes as locked siblings,
/// then writes `veSketch=0`. draw.io Glass is also a User row, so a save
/// bakes a locked white top-light sibling (`FillForegndTrans`) and writes
/// `veGlass=0`. draw.io Shape Opacity is a User row, so a save folds it
/// into FillForegndTrans / line transparency and drops `veOpacity`.
/// draw.io Label Border is also a User row, so a save bakes a locked
/// NoFill sibling whose LineColor Draw collects, then drops
/// `veLabelBorderColor`. Glueable labels pin TxtPin first so that
/// stroke sits on the route plate. draw.io Label Padding is also a User
/// row, so a save adds the pixel inset into Left/Right/Top/BottomMargin
/// and drops `veLabelPadding`. Glueable labels also grow the tight
/// route plate. draw.io Word Wrap is also a User row, so a save
/// expands TxtWidth to the unwrapped line — including tab fields
/// pinned with `visioTabFieldStart` — and drops `veWordWrap`.
/// Glueable labels pin TxtPin first so that wider plate stays on the
/// route.
/// Geometry `SoftEdgesSize` is not a token, so a save bakes a feathered
/// PNG sibling and drops the source fill. Resolved-RGB FillGradient,
/// theme-only gradient stops, classic 25–40 washes and FillPattern 2–24
/// hatches go into that PNG so Draw does not keep a hard fill.
/// A FillGradient whose opaque stops use more than two unique colours
/// uses that same plate at sigma 0 so Draw keeps the middle colour.
/// Per-stop alpha and FillForegndTrans on a two-colour wash join that
/// plate — FillPattern 25–40 drop `draw:opacity` and Draw ignores
/// `librevenge:*-opacity`. Opaque two-colour washes stay 25–40.
/// FillPattern 2–24 FillForegndTrans freezes into FillForegnd /
/// FillBkgnd: `_fillAndShadowProperties` drops hatch `draw:opacity`
/// when FillBkgndTrans is 1 and otherwise fades the whole box from
/// `max(fg,bg)`. Opaque hatches stay native.
/// Theme-only FillForegnd / LineColor / gradient stops resolve through
/// the document theme then Office into that PNG. An
/// unfilled 2-D stroke with
/// SoftEdges bakes the stroke ring the same way and drops the source
/// line. Sketch jiggle copies SoftEdgesSize onto those plates so leftover
/// NoLine Geometry does not keep a hard stroke. Dashed LinePattern 2–23 / custom arrays become per-dash ribbons
/// in that PNG so Draw keeps the gaps. A filled 2-D shape that also paints a
/// solid or dashed stroke bakes both into one padded plate and drops fill
/// and line. Gradient / hatch fills with a stroke join that plate.
/// CompoundType 1–4 rails join that plate too. LineGradient strokes
/// with resolved-RGB or theme-only stops join that plate so Draw does
/// not keep a hard opaque outline. Rounding fillets join that plate so Draw does not
/// keep square corners after the fill is dropped.
/// `ShadowBlur` is not a token,
/// so a save bakes a Gaussian PNG sibling and clears ShdwPattern. Theme-only
/// colour resolves through the document theme then Office into that PNG.
/// A Foreign picture with blur bakes the same filled image-frame silhouette.
/// PageSheet
/// `ShdwType` / `ShdwObliqueAngle` / `ShdwScaleFactor` are not tokens, so a
/// hard-edged shadow bakes a sheared vector sibling and a blurred shadow
/// bakes a sheared Gaussian PNG. Theme-only colour resolves through the
/// document theme then Office into that sibling.
/// draw.io Curved Text is also a User row, so a save bakes locked
/// per-glyph siblings along the canvas quadratic arc, hides the source
/// and drops `veCurvedText`. FlipX / FlipY extra text mirrors about TxtPin
/// are baked so Draw keeps the upright arc. draw.io Shape Inside is also a
/// User row, so a save bakes locked per-line siblings in the outline bands,
/// hides the source and drops `veShapeInside`. FlipX / FlipY use the same
/// TxtPin extra-mirror. Sketch jiggle with open arrows bakes arrow Geometry
/// on the source and drops markers from the jiggle plates. draw.io Rotate with Edge is also a
/// User row, so a save writes `TxtAngle` and drops `veAutoRotateLabel`.
/// Glueable 1-D labels with no `TxtPin` also write that route midpoint
/// into `TxtPin` / a tight `TxtWidth` so Draw does not use the Begin–End
/// box or a TxtWidth-only `m_txtxform` whose pin defaults to 0. Geometry-less
/// glueable connectors have no path for libvisio, so a save writes the
/// same `autoRoutedConnectorPolyline` canvas / SVG already paint.
/// draw.io Flow Animation is also a User row, so a save flattens the
/// synthesised 8 CSS-px dash and writes `veFlowAnimation=0`. Sketch
/// jiggle copies that row onto the plates so the same flatten keeps the
/// gaps. Arrowed
/// connectors that also flatten those dashes (or `veDashPattern`) bake
/// Begin/EndArrow as Geometry first so Draw does not hang a marker on
/// every open dash. draw.io collapsed containers also use a User row, so
/// a save writes `NoShow` / `HideText` / hollow fill and line on
/// descendants and Unfold restores
/// them from `veCollapsedHidden`. Merged-table `veCovered` cells are
/// the same missing token, so a save hides the 0.01" park box and
/// Unmerge restores them from `veCoveredHidden`.
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

  test('Character Overline bakes combining marks past tab fields', () {
    const tabs = <VsdxTabSet>[
      VsdxTabSet(
        ix: 0,
        stops: <VsdxTabStop>[VsdxTabStop(positionInches: 2)],
      ),
    ];
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4.25,
      pinY: 5.5,
      width: 3.2,
      height: 0.8,
      name: 'OverlineTab',
      fill: const VsdxFill(foreground: VsdxColor.white, pattern: 1),
      line: const VsdxLine(pattern: 0),
    ).copyWith(
      richText: const VsdxRichText(
        tabSets: tabs,
        textBlock: VsdxTextBlock(
          marginLeftInches: 0,
          marginRightInches: 0,
          marginTopInches: 0,
          marginBottomInches: 0,
          verticalAlign: VsdxVertAlign.middle,
        ),
        runs: <VsdxTextRun>[
          VsdxTextRun(
            text: 'A\tB',
            tabIndices: <int>[0],
            charStyle: VsdxCharStyle(
              fontFamily: 'Arial',
              fontSizeInches: 0.4,
              overline: true,
              color: VsdxColor(0xFF000000),
            ),
            paraStyle: VsdxParaStyle(
              horizontalAlign: VsdxHorzAlign.left,
            ),
          ),
        ],
      ),
    );
    expect(shapeNeedsLibvisioOverlineBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    final run = source.richText.runs.single;
    expect(run.charStyle.overline, isFalse);
    expect(run.text, contains('\t'));
    expect(run.tabIndices, <int>[0]);
    expect(
      run.text
          .split('\t')
          .every((part) => part.contains(kLibvisioCombiningOverline)),
      isTrue,
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .findShapeById(1)!
          .richText
          .runs
          .single
          .text,
      run.text,
      reason: 'a second save must not stack another overline',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final after = parser.parse(saved).pages.first.findShapeById(1)!;
    expect(after.richText.runs.single.charStyle.overline, isFalse);
    expect(
      after.richText.runs.single.text.split('\t').every(
            (part) => part.contains(kLibvisioCombiningOverline),
          ),
      isTrue,
    );
  });

  test('Character Overline bakes combining marks past field spans', () {
    const para = VsdxParaStyle();
    const body = VsdxCharStyle(
      fontFamily: 'Arial',
      fontSizeInches: 0.3,
      overline: true,
      color: VsdxColor(0xFF000000),
    );
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4.25,
      pinY: 5.5,
      width: 3,
      height: 1,
      name: 'OverlineFieldBox',
      fill: const VsdxFill(foreground: VsdxColor.white, pattern: 1),
      line: const VsdxLine(pattern: 0),
    ).copyWith(
      text: 'X42',
      fields: const <VsdxFieldRow>[
        VsdxFieldRow(
          ix: 0,
          value: '42',
          valueFormula: 'PAGENUMBER()',
        ),
      ],
      richText: const VsdxRichText(
        runs: <VsdxTextRun>[
          VsdxTextRun(
            text: 'X42',
            charStyle: body,
            paraStyle: para,
            fieldSpans: <VsdxFieldSpan>[
              VsdxFieldSpan(start: 1, length: 2, ix: 0),
            ],
          ),
        ],
      ),
    );
    expect(shapeNeedsLibvisioOverlineBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    final run = source.richText.runs.single;
    expect(run.charStyle.overline, isFalse);
    expect(run.text,
        'X${kLibvisioCombiningOverline}4${kLibvisioCombiningOverline}2${kLibvisioCombiningOverline}');
    expect(
      run.fieldSpans.single,
      const VsdxFieldSpan(start: 2, length: 4, ix: 0),
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .findShapeById(1)!
          .richText
          .runs
          .single
          .text,
      run.text,
      reason: 'a second save must not stack another overline',
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .findShapeById(1)!
          .richText
          .runs
          .single
          .fieldSpans,
      run.fieldSpans,
      reason: 'a second save must not grow <fld> again',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final after = parser.parse(saved).pages.first.findShapeById(1)!;
    expect(after.richText.runs.first.charStyle.overline, isFalse);
    expect(
      after.richText.runs.first.text,
      contains(kLibvisioCombiningOverline),
    );
    expect(
      after.richText.runs.first.fieldSpans.single,
      const VsdxFieldSpan(start: 2, length: 4, ix: 0),
    );

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    expect(
      oracle.svgPages(saved)?.join() ?? '',
      contains(kLibvisioCombiningOverline),
    );
  });

  test('Character DoubleStrikethrough bakes combining U+0336 for LibreOffice',
      () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.4,
      height: 0.7,
      name: 'DStrike',
    ).copyWith(
      text: 'AB',
      richText: const VsdxRichText(
        runs: [
          VsdxTextRun(
            text: 'AB',
            charStyle: VsdxCharStyle(doubleStrikethrough: true),
          ),
        ],
      ),
    );
    expect(shapeNeedsLibvisioDoubleStrikethroughBake(shape), isTrue);
    final baked = bakeDoubleStrikethroughShapeForLibvisioWrite(shape);
    expect(baked.richText.runs.single.charStyle.doubleStrikethrough, isFalse);
    expect(baked.richText.runs.single.charStyle.strikethrough, isTrue);
    expect(
      baked.richText.runs.single.text,
      contains(kLibvisioCombiningLongStroke),
    );
    expect(baked.text, contains(kLibvisioCombiningLongStroke));
  });

  test('Paragraph SpLine=0 bakes the run Size so LibreOffice keeps leading',
      () {
    const size = 0.4;
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 3,
      height: 2,
      name: 'SolidSpLine',
    ).copyWith(
      text: 'AAA\nBBB\nCCC',
      richText: const VsdxRichText(
        runs: [
          VsdxTextRun(
            text: 'AAA\nBBB\nCCC',
            charStyle: VsdxCharStyle(
              fontFamily: 'Arial',
              fontSizeInches: size,
            ),
            paraStyle: VsdxParaStyle(lineSpacingSolid: true),
          ),
        ],
      ),
    );
    expect(shapeNeedsLibvisioSolidLineSpacingBake(shape), isTrue);
    final baked = bakeSolidLineSpacingShapeForLibvisioWrite(shape);
    expect(baked.richText.runs.single.paraStyle.lineSpacingSolid, isFalse);
    expect(
      baked.richText.runs.single.paraStyle.lineSpacingAbsoluteInches,
      closeTo(size, 1e-12),
    );
    expect(
      shapeNeedsLibvisioSolidLineSpacingBake(baked),
      isFalse,
      reason: 'a second save must not rewrite the absolute SpLine again',
    );

    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final once = documentForLibvisioWrite(doc);
    final twice = documentForLibvisioWrite(once);
    expect(
      twice.pages.first.shapes.single.richText.runs.single.paraStyle
          .lineSpacingAbsoluteInches,
      closeTo(size, 1e-12),
    );
    expect(
      twice.pages.first.shapes.single.richText.runs.single.paraStyle
          .lineSpacingSolid,
      isFalse,
    );
  });

  test('Paragraph HorzAlign=full bakes justify so LibreOffice keeps wrap', () {
    const wrap = 'AA BB CC DD EE FF GG HH';
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4.25,
      pinY: 5.5,
      width: 2.6,
      height: 2.4,
      name: 'HorzAlignFull',
    ).copyWith(
      text: wrap,
      richText: const VsdxRichText(
        runs: [
          VsdxTextRun(
            text: wrap,
            charStyle: VsdxCharStyle(
              fontFamily: 'Arial',
              fontSizeInches: 0.55,
            ),
            paraStyle: VsdxParaStyle(horizontalAlign: VsdxHorzAlign.full),
          ),
        ],
      ),
    );
    expect(shapeNeedsLibvisioHorzAlignFullBake(shape), isTrue);
    final baked = bakeHorzAlignFullShapeForLibvisioWrite(shape);
    expect(
      baked.richText.runs.single.paraStyle.horizontalAlign,
      VsdxHorzAlign.justify,
    );
    expect(
      shapeNeedsLibvisioHorzAlignFullBake(baked),
      isFalse,
      reason: 'a second save must not rewrite HorzAlign=3 again',
    );

    final left = bakeHorzAlignFullShapeForLibvisioWrite(
      shape.copyWith(
        richText: shape.richText.copyWith(
          runs: [
            shape.richText.runs.single.copyWith(
              paraStyle: const VsdxParaStyle(
                horizontalAlign: VsdxHorzAlign.left,
              ),
            ),
          ],
        ),
      ),
    );
    expect(
      left.richText.runs.single.paraStyle.horizontalAlign,
      VsdxHorzAlign.left,
    );

    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final once = documentForLibvisioWrite(doc);
    final twice = documentForLibvisioWrite(once);
    expect(
      twice.pages.first.shapes.single.richText.runs.single.paraStyle
          .horizontalAlign,
      VsdxHorzAlign.justify,
    );
  });

  test('Text-block DefaultTabStop bakes Tabs so LibreOffice keeps interval',
      () {
    const body = 'A\tB';
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4.25,
      pinY: 5.5,
      width: 6.0,
      height: 1.4,
      name: 'DefaultTabStop',
    ).copyWith(
      text: body,
      richText: const VsdxRichText(
        runs: [
          VsdxTextRun(
            text: body,
            charStyle: VsdxCharStyle(
              fontFamily: 'Arial',
              fontSizeInches: 0.4,
            ),
          ),
        ],
        textBlock: VsdxTextBlock(defaultTabStopInches: 2.0),
      ),
    );
    expect(shapeNeedsLibvisioDefaultTabStopBake(shape), isTrue);
    final baked = bakeDefaultTabStopShapeForLibvisioWrite(shape);
    expect(baked.richText.runs.single.text, contains('\t'));
    expect(baked.richText.tabSets, isNotEmpty);
    final positions = baked.richText.tabSets.single.stops
        .map((s) => s.positionInches)
        .toList();
    expect(positions, contains(closeTo(2.0, 1e-9)));
    expect(positions, contains(closeTo(4.0, 1e-9)));
    expect(
      shapeNeedsLibvisioDefaultTabStopBake(baked),
      isFalse,
      reason: 'a second save must not stack another DefaultTabStop grid',
    );

    final half = bakeDefaultTabStopShapeForLibvisioWrite(
      shape.copyWith(
        richText: shape.richText.copyWith(
          textBlock: const VsdxTextBlock(defaultTabStopInches: 0.5),
        ),
      ),
    );
    expect(half.richText.tabSets, isEmpty);

    final noTab = bakeDefaultTabStopShapeForLibvisioWrite(
      shape.copyWith(
        text: 'AB',
        richText: shape.richText.copyWith(
          runs: [
            shape.richText.runs.single.copyWith(text: 'AB'),
          ],
        ),
      ),
    );
    expect(noTab.richText.tabSets, isEmpty);

    final authored = bakeDefaultTabStopShapeForLibvisioWrite(
      shape.copyWith(
        richText: shape.richText.copyWith(
          tabSets: const [
            VsdxTabSet(
              ix: 0,
              stops: [VsdxTabStop(positionInches: 3.0)],
            ),
          ],
        ),
      ),
    );
    final authoredPos = authored.richText.tabSets.single.stops
        .map((s) => s.positionInches)
        .toList();
    expect(authoredPos, contains(closeTo(3.0, 1e-9)));
    expect(
      authoredPos.any((p) => (p - 2.0).abs() < 1e-6),
      isFalse,
      reason: 'an off-grid 3" stop must not be stolen by a 2" grid point',
    );
    expect(authoredPos, contains(closeTo(4.0, 1e-9)));

    final writer = VsdxWriter();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final once = documentForLibvisioWrite(doc);
    final twice = documentForLibvisioWrite(once);
    expect(
      twice.pages.first.shapes.single.richText.tabSets.single.stops.length,
      once.pages.first.shapes.single.richText.tabSets.single.stops.length,
    );
    expect(
      twice.pages.first.shapes.single.richText.runs.single.text,
      contains('\t'),
    );
  });

  test('Character DoubleStrikethrough bakes combining marks past field spans',
      () {
    const para = VsdxParaStyle();
    const body = VsdxCharStyle(
      fontFamily: 'Arial',
      fontSizeInches: 0.3,
      doubleStrikethrough: true,
      color: VsdxColor(0xFF000000),
    );
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4.25,
      pinY: 5.5,
      width: 3,
      height: 1,
      name: 'DStrikeFieldBox',
      fill: const VsdxFill(foreground: VsdxColor.white, pattern: 1),
      line: const VsdxLine(pattern: 0),
    ).copyWith(
      text: 'X42',
      fields: const <VsdxFieldRow>[
        VsdxFieldRow(
          ix: 0,
          value: '42',
          valueFormula: 'PAGENUMBER()',
        ),
      ],
      richText: const VsdxRichText(
        runs: <VsdxTextRun>[
          VsdxTextRun(
            text: 'X42',
            charStyle: body,
            paraStyle: para,
            fieldSpans: <VsdxFieldSpan>[
              VsdxFieldSpan(start: 1, length: 2, ix: 0),
            ],
          ),
        ],
      ),
    );
    expect(shapeNeedsLibvisioDoubleStrikethroughBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    final run = source.richText.runs.single;
    expect(run.charStyle.doubleStrikethrough, isFalse);
    expect(run.charStyle.strikethrough, isTrue);
    expect(
      run.text,
      'X${kLibvisioCombiningLongStroke}4${kLibvisioCombiningLongStroke}2${kLibvisioCombiningLongStroke}',
    );
    expect(
      run.fieldSpans.single,
      const VsdxFieldSpan(start: 2, length: 4, ix: 0),
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .findShapeById(1)!
          .richText
          .runs
          .single
          .text,
      run.text,
      reason: 'a second save must not stack another long-stroke overlay',
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .findShapeById(1)!
          .richText
          .runs
          .single
          .fieldSpans,
      run.fieldSpans,
      reason: 'a second save must not grow <fld> again',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final after = parser.parse(saved).pages.first.findShapeById(1)!;
    expect(after.richText.runs.first.charStyle.doubleStrikethrough, isFalse);
    expect(after.richText.runs.first.charStyle.strikethrough, isTrue);
    expect(
      after.richText.runs.first.text,
      contains(kLibvisioCombiningLongStroke),
    );
    expect(
      after.richText.runs.first.fieldSpans.single,
      const VsdxFieldSpan(start: 2, length: 4, ix: 0),
    );

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    expect(
      oracle.svgPages(saved)?.join() ?? '',
      contains(kLibvisioCombiningLongStroke),
    );
  });

  test('Character LangID RTL bakes a leading U+200F for LibreOffice', () {
    VsdxShape box(String name, String text, {String? langId}) =>
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
              VsdxTextRun(
                text: text,
                charStyle: VsdxCharStyle(langId: langId),
              ),
            ],
          ),
        );

    final arabicDigits = box('ArDigits', '123', langId: 'ar-SA');
    expect(shapeNeedsLibvisioLangIdRtlBake(arabicDigits), isTrue);
    final bakedArabic = bakeLangIdRtlShapeForLibvisioWrite(arabicDigits);
    expect(
      bakedArabic.richText.runs.single.text,
      '$kLibvisioRtlMark'
      '123',
    );
    expect(bakedArabic.text, startsWith(kLibvisioRtlMark));
    expect(
      bakeLangIdRtlShapeForLibvisioWrite(bakedArabic).richText.runs.single.text,
      bakedArabic.richText.runs.single.text,
      reason: 'a second save must not stack another U+200F',
    );

    final hebrewDigits = box('HeDigits', '123-456', langId: 'he-IL');
    expect(shapeNeedsLibvisioLangIdRtlBake(hebrewDigits), isTrue);
    expect(
      bakeLangIdRtlShapeForLibvisioWrite(hebrewDigits)
          .richText
          .runs
          .single
          .text,
      startsWith(kLibvisioRtlMark),
    );

    expect(
      shapeNeedsLibvisioLangIdRtlBake(box('EnDigits', '123', langId: 'en-US')),
      isFalse,
    );
    expect(
      shapeNeedsLibvisioLangIdRtlBake(box('Arabic', 'سلام', langId: 'ar-SA')),
      isFalse,
      reason: 'strong RTL letters already set Unicode bidi in Draw',
    );
    expect(
      shapeNeedsLibvisioLangIdRtlBake(box('Latin', 'Hi', langId: 'ar-SA')),
      isFalse,
    );
    expect(shapeNeedsLibvisioLangIdRtlBake(box('Plain', '123')), isFalse);
  });

  test('Character LangID RTL bakes a leading U+200F past tab fields', () {
    const tabs = <VsdxTabSet>[
      VsdxTabSet(
        ix: 0,
        stops: <VsdxTabStop>[VsdxTabStop(positionInches: 2)],
      ),
    ];
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4.25,
      pinY: 5.5,
      width: 3.2,
      height: 0.8,
      name: 'LangIdRtlTab',
      fill: const VsdxFill(foreground: VsdxColor.white, pattern: 1),
      line: const VsdxLine(pattern: 0),
    ).copyWith(
      richText: const VsdxRichText(
        tabSets: tabs,
        textBlock: VsdxTextBlock(
          marginLeftInches: 0,
          marginRightInches: 0,
          marginTopInches: 0,
          marginBottomInches: 0,
          verticalAlign: VsdxVertAlign.middle,
        ),
        runs: <VsdxTextRun>[
          VsdxTextRun(
            text: '12\t34',
            tabIndices: <int>[0],
            charStyle: VsdxCharStyle(langId: 'ar-SA'),
          ),
        ],
      ),
    );
    expect(shapeNeedsLibvisioLangIdRtlBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final run = baked.pages.first.findShapeById(1)!.richText.runs.single;
    expect(run.text, startsWith(kLibvisioRtlMark));
    expect(run.text, contains('\t'));
    expect(run.tabIndices, <int>[0]);
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .findShapeById(1)!
          .richText
          .runs
          .single
          .text,
      run.text,
      reason: 'a second save must not stack another U+200F',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final after = parser.parse(saved).pages.first.findShapeById(1)!;
    expect(after.richText.runs.single.text, startsWith(kLibvisioRtlMark));
    expect(after.richText.runs.single.text, contains('\t'));
  });

  test('Character LangID RTL bakes a leading U+200F past field spans', () {
    const body = VsdxCharStyle(
      fontFamily: 'Arial',
      fontSizeInches: 0.3,
      color: VsdxColor(0xFF000000),
      langId: 'ar-SA',
    );
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4.25,
      pinY: 5.5,
      width: 3,
      height: 1,
      name: 'LangIdRtlFieldBox',
      fill: const VsdxFill(foreground: VsdxColor.white, pattern: 1),
      line: const VsdxLine(pattern: 0),
    ).copyWith(
      text: '42',
      fields: const <VsdxFieldRow>[
        VsdxFieldRow(
          ix: 0,
          value: '42',
          valueFormula: 'PAGENUMBER()',
        ),
      ],
      richText: const VsdxRichText(
        runs: <VsdxTextRun>[
          VsdxTextRun(
            text: '42',
            charStyle: body,
            fieldSpans: <VsdxFieldSpan>[
              VsdxFieldSpan(start: 0, length: 2, ix: 0),
            ],
          ),
        ],
      ),
    );
    expect(shapeNeedsLibvisioLangIdRtlBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    final run = source.richText.runs.single;
    expect(
        run.text,
        '$kLibvisioRtlMark'
        '42');
    expect(
      run.fieldSpans.single,
      const VsdxFieldSpan(start: 1, length: 2, ix: 0),
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .findShapeById(1)!
          .richText
          .runs
          .single
          .text,
      run.text,
      reason: 'a second save must not stack another U+200F',
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .findShapeById(1)!
          .richText
          .runs
          .single
          .fieldSpans,
      run.fieldSpans,
      reason: 'a second save must not shift <fld> again',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final after = parser.parse(saved).pages.first.findShapeById(1)!;
    expect(after.richText.runs.first.text, startsWith(kLibvisioRtlMark));
    expect(
      after.richText.runs.first.fieldSpans.single,
      const VsdxFieldSpan(start: 1, length: 2, ix: 0),
    );
    expect(after.fields.first.valueFormula, 'PAGENUMBER()');

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    expect(oracle.svgPages(saved)?.join() ?? '', contains('42'));
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
    expect(shapeNeedsLibvisioGlowBake(themeFilled), isFalse,
        reason: 'theme-only NoLine bakes a Gaussian PNG like RGB');
    expect(shapeNeedsLibvisioGlowPlateBake(themeFilled), isTrue);
    final themeWrite = libvisioShapeWrite(themeFilled);
    expect(themeWrite.line.hasLine, isFalse,
        reason: 'Line stays unused; the halo is the PNG plate');
    expect(glowForLibvisioWrite(themeFilled).enabled, isFalse);

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
        reason:
            'the 1-D glow PNG must carry magenta halo ink, not an empty plate');

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

  test('theme-only Glow bakes a Gaussian PNG for LibreOffice', () {
    const slot = ThemeSlot.accent2;
    final expected = VsdxTheme.office.resolve(slot)!;
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.5,
      height: 0.8,
      name: 'GlowTheme',
      fill: const VsdxFill(foreground: VsdxColor(0xFFEEEEEE), pattern: 1),
      line: const VsdxLine(pattern: 0),
    ).copyWith(
      glow: const VsdxGlow(
        themeColorIndex: slot,
        sizeInches: 0.12,
        transparency: 0.2,
      ),
    );
    expect(shapeNeedsLibvisioGlowBake(shape), isFalse);
    expect(shapeNeedsLibvisioGlowPlateBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var filledDoc = parser.parse(blank).copyWith(theme: VsdxTheme.office);
    filledDoc = filledDoc.replacePage(0, filledDoc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(filledDoc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.line.pattern, 0);
    expect(source.fill.pattern, 1);
    expect(source.glow.themeColorIndex, slot);
    final plate = baked.pages.first.shapes.where(isLibvisioGlowPlate).single;
    expect(plate.hasImage, isTrue);
    expect(plate.locked, isTrue);
    expect(plate.width, greaterThan(source.width));
    final decoded = raster.decodePng(
      baked.images.findByPart(plate.imagePartName!)!.bytes,
    )!;
    var ink = 0;
    for (var y = 0; y < decoded.height; y++) {
      for (var x = 0; x < decoded.width; x++) {
        final pixel = decoded.getPixel(x, y);
        if (pixel.a > 20 && pixel.r > pixel.b + 20 && pixel.r > pixel.g + 10) {
          ink++;
        }
      }
    }
    expect(ink, greaterThan(8),
        reason: 'theme slot $slot (${expected.value.toRadixString(16)}) '
            'must freeze into the Gaussian PNG, not a LineWeight halo');
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioGlowPlate),
      hasLength(1),
      reason: 'a second save must not stack another Glow plate',
    );

    final stroke = VsdxShapeFactory.line(
      id: 2,
      ax: 2,
      ay: 5.5,
      bx: 6.5,
      by: 5.5,
      name: 'GlowTheme1d',
      line: const VsdxLine(
        color: VsdxColor.black,
        weightInches: 0.06,
      ),
    ).copyWith(
      glow: const VsdxGlow(
        themeColorIndex: slot,
        sizeInches: 0.12,
        transparency: 0.2,
      ),
    );
    expect(shapeNeedsLibvisioGlowBake(stroke), isFalse,
        reason: 'theme-only 1-D bakes a Gaussian PNG, not a Fill ribbon');
    expect(shapeNeedsLibvisioGlowPlateBake(stroke), isTrue);
    var doc = parser.parse(blank).copyWith(theme: VsdxTheme.office);
    doc = doc.replacePage(0, doc.pages.first.addShape(stroke));
    final bakedStroke = documentForLibvisioWrite(doc);
    final strokePlate =
        bakedStroke.pages.first.shapes.where(isLibvisioGlowPlate).single;
    expect(strokePlate.hasImage, isTrue);
    expect(strokePlate.is1D, isFalse);
    final strokePng = raster.decodePng(
      bakedStroke.images.findByPart(strokePlate.imagePartName!)!.bytes,
    )!;
    var strokeInk = 0;
    for (var y = 0; y < strokePng.height; y++) {
      for (var x = 0; x < strokePng.width; x++) {
        final pixel = strokePng.getPixel(x, y);
        if (pixel.a > 20 && pixel.r > pixel.b + 20 && pixel.r > pixel.g + 10) {
          strokeInk++;
        }
      }
    }
    expect(strokeInk, greaterThan(8),
        reason: 'theme-only 1-D must freeze Office accent2 into the PNG plate');

    final savedFilled = writer.write(originalBytes: blank, edited: filledDoc);
    final savedFilledDoc = parser.parse(savedFilled);
    expect(savedFilledDoc.pages.first.findShapeById(1)!.glow.enabled, isFalse);
    expect(
      savedFilledDoc.pages.first.shapes
          .where(isLibvisioGlowPlate)
          .single
          .hasImage,
      isTrue,
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(savedDoc.pages.first.findShapeById(2)!.glow.enabled, isFalse);
    expect(
      savedDoc.pages.first.shapes.where(isLibvisioGlowPlate),
      hasLength(1),
    );
  });

  test('theme-only Glow on a spline bakes a Gaussian PNG for LibreOffice', () {
    const slot = ThemeSlot.accent6;
    const glow = VsdxGlow(
      themeColorIndex: slot,
      sizeInches: 0.28,
      transparency: 0.15,
    );
    final expected = VsdxTheme.office.resolve(slot)!;

    VsdxShape splineBody(int id, String name, {required bool stroked}) =>
        VsdxShape(
          id: id,
          name: name,
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          geometries: const <VsdxGeometry>[
            VsdxGeometry(
              commands: <VsdxPathCommand>[
                MoveTo(0, 0),
                SplineStart(x: 0.75, y: 1.6, a: 0, b: 0, c: 3),
                SplineKnot(x: 2.25, y: 1.6, knot: 1),
                LineTo(3, 0),
                LineTo(0, 0),
              ],
            ),
          ],
          fill: const VsdxFill(foreground: VsdxColor(0xFFEEEEEE), pattern: 1),
          line: stroked
              ? const VsdxLine(color: VsdxColor.black, weightInches: 0.04)
              : const VsdxLine(pattern: 0),
        ).copyWith(glow: glow);

    int greenInk(raster.Image decoded) {
      var ink = 0;
      for (final pixel in decoded) {
        if (pixel.a > 20 && pixel.g > pixel.r + 10 && pixel.g > pixel.b + 10) {
          ink++;
        }
      }
      return ink;
    }

    final stolen = splineBody(1, 'GlowSplineTheme', stroked: false);
    expect(shapeNeedsLibvisioGlowBake(stolen), isFalse);
    expect(shapeNeedsLibvisioGlowPlateBake(stolen), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank).copyWith(theme: VsdxTheme.office);
    doc = doc.replacePage(0, doc.pages.first.addShape(stolen));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.line.pattern, 0);
    final plate = baked.pages.first.shapes.where(isLibvisioGlowPlate).single;
    expect(plate.hasImage, isTrue);
    expect(plate.locked, isTrue);
    expect(plate.width, greaterThan(source.width));
    expect(
      greenInk(raster.decodePng(
        baked.images.findByPart(plate.imagePartName!)!.bytes,
      )!),
      greaterThan(8),
      reason: 'theme slot $slot (${expected.value.toRadixString(16)}) '
          'must freeze into the sampled-spline Gaussian PNG',
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioGlowPlate),
      hasLength(1),
      reason: 'a second save must not stack another Glow plate',
    );

    final plated = splineBody(2, 'GlowSplinePlate', stroked: true);
    expect(shapeNeedsLibvisioGlowPlateBake(plated), isTrue);
    var platedDoc = parser.parse(blank).copyWith(theme: VsdxTheme.office);
    platedDoc =
        platedDoc.replacePage(0, platedDoc.pages.first.addShape(plated));
    final platedBaked = documentForLibvisioWrite(platedDoc);
    final strokedPlate =
        platedBaked.pages.first.shapes.where(isLibvisioGlowPlate).single;
    expect(strokedPlate.hasImage, isTrue);
    expect(strokedPlate.locked, isTrue);
    expect(
      platedBaked.pages.first.findShapeById(2)!.line.pattern,
      1,
      reason: 'the source outline must stay on the source',
    );
    expect(
      greenInk(raster.decodePng(
        platedBaked.images.findByPart(strokedPlate.imagePartName!)!.bytes,
      )!),
      greaterThan(8),
      reason: 'filled+stroked spline Glow must bake a Gaussian PNG',
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

  test(
    'Sketch LineGradient washes with more than two colours bake PNG for LibreOffice',
    () {
      const wash = VsdxGradient(
        stops: <VsdxGradientStop>[
          VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF00FF)),
          VsdxGradientStop(position: 0.5, color: VsdxColor(0xFF00FF00)),
          VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
        ],
      );
      const twoStop = VsdxGradient(
        stops: <VsdxGradientStop>[
          VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF00FF)),
          VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
        ],
      );
      final shape = VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 4.25,
        pinY: 6.2,
        width: 3.0,
        height: 1.4,
        name: 'LineGrad3Sketch',
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(pattern: 1, weightInches: 0.18, gradient: wash),
      ).withSketchEffect(true).withSketchJiggle(3.5);
      expect(shapeNeedsLibvisioSketchStrokeBake(shape), isTrue);

      final blank = writer.emptyDocument();
      var doc = parser.parse(blank);
      doc = doc.replacePage(0, doc.pages.first.addShape(shape));
      final baked = documentForLibvisioWrite(doc);
      expect(
        baked.pages.first.shapes.where(isLibvisioSketchPlate),
        hasLength(2),
      );
      expect(
        baked.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
        hasLength(2),
        reason: 'each Sketch jiggle must become a LineGradient PNG',
      );
      expect(
        baked.pages.first.shapes.where(isLibvisioSketchPlate).every(
              (s) => !s.line.hasLine && !s.line.hasGradient,
            ),
        isTrue,
      );
      var green = 0;
      for (final plate
          in baked.pages.first.shapes.where(isLibvisioSoftEdgesPlate)) {
        final png = raster.decodePng(
          baked.images.findByPart(plate.imagePartName!)!.bytes,
        )!;
        for (final pixel in png) {
          if (pixel.g > 160 && pixel.r < 100 && pixel.b < 100) green++;
        }
      }
      expect(
        green,
        greaterThan(40),
        reason: 'Sketch LineGradient PNG must keep the middle green stop; '
            'green=$green',
      );
      expect(
        documentForLibvisioWrite(baked)
            .pages
            .first
            .shapes
            .where(isLibvisioSoftEdgesPlate),
        hasLength(2),
        reason: 'a second save must not stack another Sketch LineGradient PNG',
      );

      final two = VsdxShapeFactory.rectangle(
        id: 2,
        pinX: 4.25,
        pinY: 4.0,
        width: 3.0,
        height: 1.4,
        name: 'LineGrad2Sketch',
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(
          pattern: 1,
          weightInches: 0.18,
          gradient: twoStop,
        ),
      ).withSketchEffect(true).withSketchJiggle(3.5);
      var twoDoc = parser.parse(blank);
      twoDoc = twoDoc.replacePage(0, twoDoc.pages.first.addShape(two));
      final twoBaked = documentForLibvisioWrite(twoDoc);
      expect(
        twoBaked.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
        isEmpty,
        reason: 'two-colour Sketch LineGradient stays a filled ribbon',
      );
      expect(
        twoBaked.pages.first.shapes.where(isLibvisioSketchPlate),
        hasLength(2),
      );
      expect(
        twoBaked.pages.first.shapes
            .where(isLibvisioSketchPlate)
            .every((s) => s.line.hasLine),
        isTrue,
      );

      final connector = VsdxShapeFactory.line(
        id: 3,
        ax: 1.5,
        ay: 6.2,
        bx: 6.5,
        by: 6.2,
        name: 'LineGrad3Sketch_1D',
        line: const VsdxLine(pattern: 1, weightInches: 0.18, gradient: wash),
      ).withSketchEffect(true).withSketchJiggle(3.5);
      var oneDoc = parser.parse(blank);
      oneDoc = oneDoc.replacePage(0, oneDoc.pages.first.addShape(connector));
      final oneBaked = documentForLibvisioWrite(oneDoc);
      expect(
        oneBaked.pages.first.shapes.where(isLibvisioSketchPlate),
        hasLength(2),
      );
      final oneSoft =
          oneBaked.pages.first.shapes.where(isLibvisioSoftEdgesPlate);
      expect(oneSoft, hasLength(2));
      expect(oneSoft.every((s) => !s.is1D && s.height.abs() > 0.1), isTrue);
    },
  );

  test('Sketch jiggle strokes keep Glow for LibreOffice', () {
    const colour = VsdxColor(0xFFFF00FF);
    const glow = VsdxGlow(
      color: colour,
      sizeInches: 0.12,
      transparency: 0.25,
    );
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4.25,
      pinY: 6.2,
      width: 3.0,
      height: 1.4,
      name: 'SketchGlow',
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(
        color: VsdxColor.black,
        pattern: 1,
        weightInches: 0.04,
      ),
    ).withSketchEffect(true).withSketchJiggle(3.5).copyWith(glow: glow);
    expect(shapeNeedsLibvisioSketchStrokeBake(shape), isTrue);
    expect(shapeNeedsLibvisioGlowPlateBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    expect(
      baked.pages.first.shapes.where(isLibvisioSketchPlate),
      hasLength(2),
    );
    expect(
      baked.pages.first.shapes.where(isLibvisioGlowPlate),
      hasLength(2),
      reason: 'each Sketch jiggle must become a Glow PNG',
    );
    final glowNames =
        baked.pages.first.shapes.map((s) => s.name).toList(growable: false);
    expect(
      glowNames
          .lastIndexWhere((n) => n.startsWith(kLibvisioGlowShapeNamePrefix)),
      lessThan(
        glowNames
            .indexWhere((n) => n.startsWith(kLibvisioSketchShapeNamePrefix)),
      ),
      reason: 'opaque Glow PNGs must sit under both jiggle strokes',
    );
    expect(
      baked.pages.first.findShapeById(1)!.glow.enabled,
      isFalse,
      reason: 'hollow leftover Geometry is NoLine; Glow lives on the jiggle',
    );
    expect(
      baked.pages.first.shapes.where(isLibvisioSketchPlate).every(
            (s) => s.line.hasLine && s.fill.pattern == 0,
          ),
      isTrue,
    );
    var magenta = 0;
    for (final plate in baked.pages.first.shapes.where(isLibvisioGlowPlate)) {
      expect(plate.hasImage, isTrue);
      expect(plate.is1D, isFalse);
      expect(plate.height, greaterThan(0.1));
      final png = raster.decodePng(
        baked.images.findByPart(plate.imagePartName!)!.bytes,
      )!;
      for (final pixel in png) {
        if (pixel.r > pixel.g + 15 && pixel.b > pixel.g + 15 && pixel.a > 20) {
          magenta++;
        }
      }
    }
    expect(
      magenta,
      greaterThan(40),
      reason: 'Sketch Glow PNG must carry magenta halo ink; magenta=$magenta',
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioGlowPlate),
      hasLength(2),
      reason: 'a second save must not stack another Sketch Glow PNG',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(savedDoc.pages.first.findShapeById(1)!.glow.enabled, isFalse);
    expect(
      savedDoc.pages.first.shapes.where(isLibvisioSketchPlate),
      hasLength(2),
    );
    expect(
      savedDoc.pages.first.shapes.where(isLibvisioGlowPlate),
      hasLength(2),
    );

    final connector = VsdxShapeFactory.line(
      id: 3,
      ax: 1.5,
      ay: 6.2,
      bx: 6.5,
      by: 6.2,
      name: 'SketchGlow_1D',
      line: const VsdxLine(
        color: VsdxColor.black,
        pattern: 1,
        weightInches: 0.06,
      ),
    ).withSketchEffect(true).withSketchJiggle(3.5).copyWith(glow: glow);
    var oneDoc = parser.parse(blank);
    oneDoc = oneDoc.replacePage(0, oneDoc.pages.first.addShape(connector));
    final oneBaked = documentForLibvisioWrite(oneDoc);
    expect(
      oneBaked.pages.first.shapes.where(isLibvisioSketchPlate),
      hasLength(2),
    );
    final oneGlow = oneBaked.pages.first.shapes.where(isLibvisioGlowPlate);
    expect(oneGlow, hasLength(2));
    expect(oneGlow.every((s) => !s.is1D && s.height.abs() > 0.1), isTrue);
  });

  test('Sketch jiggle strokes keep Reflection for LibreOffice', () {
    const colour = VsdxColor(0xFF1565C0);
    const reflection = VsdxReflection(
      enabled: true,
      sizeInches: 0.6,
      distanceInches: 0.08,
      transparency: 0.2,
      blurInches: 0,
    );
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4.25,
      pinY: 6.2,
      width: 3.0,
      height: 1.4,
      name: 'SketchReflection',
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(
        color: colour,
        pattern: 1,
        weightInches: 0.06,
      ),
    )
        .withSketchEffect(true)
        .withSketchJiggle(3.5)
        .copyWith(reflection: reflection);
    expect(shapeNeedsLibvisioSketchStrokeBake(shape), isTrue);
    expect(shapeNeedsLibvisioReflectionBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    expect(
      baked.pages.first.shapes.where(isLibvisioSketchPlate),
      hasLength(2),
    );
    expect(
      baked.pages.first.shapes.where(isLibvisioReflectionPlate),
      hasLength(2),
      reason: 'each Sketch jiggle must become a Reflection PNG',
    );
    final reflectionNames =
        baked.pages.first.shapes.map((s) => s.name).toList(growable: false);
    expect(
      reflectionNames.lastIndexWhere(
        (n) => n.startsWith(kLibvisioReflectionShapeNamePrefix),
      ),
      lessThan(
        reflectionNames.indexWhere(
          (n) => n.startsWith(kLibvisioSketchShapeNamePrefix),
        ),
      ),
      reason: 'opaque Reflection PNGs must sit under both jiggle strokes',
    );
    expect(
      baked.pages.first.findShapeById(1)!.reflection.enabled,
      isFalse,
      reason: 'hollow leftover Geometry is NoLine; Reflection lives on the '
          'jiggle',
    );
    var ink = 0;
    for (final plate
        in baked.pages.first.shapes.where(isLibvisioReflectionPlate)) {
      expect(plate.hasImage, isTrue);
      expect(plate.is1D, isFalse);
      expect(plate.height, greaterThan(0.05));
      final png = raster.decodePng(
        baked.images.findByPart(plate.imagePartName!)!.bytes,
      )!;
      for (final pixel in png) {
        if (pixel.b > pixel.r + 15 && pixel.a > 20) ink++;
      }
    }
    expect(
      ink,
      greaterThan(8),
      reason: 'Sketch Reflection PNG must carry stroke ink; ink=$ink',
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioReflectionPlate),
      hasLength(2),
      reason: 'a second save must not stack another Sketch Reflection PNG',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(savedDoc.pages.first.findShapeById(1)!.reflection.enabled, isFalse);
    expect(
      savedDoc.pages.first.shapes.where(isLibvisioSketchPlate),
      hasLength(2),
    );
    expect(
      savedDoc.pages.first.shapes.where(isLibvisioReflectionPlate),
      hasLength(2),
    );

    final connector = VsdxShapeFactory.line(
      id: 3,
      ax: 1.5,
      ay: 6.2,
      bx: 6.5,
      by: 6.2,
      name: 'SketchReflection_1D',
      line: const VsdxLine(
        color: colour,
        pattern: 1,
        weightInches: 0.12,
      ),
    )
        .withSketchEffect(true)
        .withSketchJiggle(3.5)
        .copyWith(reflection: reflection);
    var oneDoc = parser.parse(blank);
    oneDoc = oneDoc.replacePage(0, oneDoc.pages.first.addShape(connector));
    final oneBaked = documentForLibvisioWrite(oneDoc);
    expect(
      oneBaked.pages.first.shapes.where(isLibvisioSketchPlate),
      hasLength(2),
    );
    final onePlate =
        oneBaked.pages.first.shapes.where(isLibvisioReflectionPlate);
    expect(onePlate, hasLength(2));
    expect(onePlate.every((s) => !s.is1D && s.height.abs() > 0.05), isTrue);
  });

  test('Sketch jiggle strokes keep SoftEdges for LibreOffice', () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4.25,
      pinY: 6.2,
      width: 3.0,
      height: 1.4,
      name: 'SketchSoft',
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(
        color: VsdxColor.black,
        pattern: 1,
        weightInches: 0.1,
        softEdgesInches: 0.08,
      ),
    ).withSketchEffect(true).withSketchJiggle(3.5);
    expect(shapeNeedsLibvisioSketchStrokeBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    expect(
      baked.pages.first.shapes.where(isLibvisioSketchPlate),
      hasLength(2),
    );
    expect(
      baked.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
      hasLength(2),
      reason: 'each Sketch jiggle must become a SoftEdges PNG',
    );
    final names =
        baked.pages.first.shapes.map((s) => s.name).toList(growable: false);
    expect(
      names.lastIndexWhere(
        (n) => n.startsWith(kLibvisioSoftEdgesShapeNamePrefix),
      ),
      lessThan(
        names.indexWhere((n) => n.startsWith(kLibvisioSketchShapeNamePrefix)),
      ),
      reason: 'opaque SoftEdges PNGs must sit under both jiggle leftovers',
    );
    expect(
      baked.pages.first.shapes.where(isLibvisioSketchPlate).every(
            (s) => !s.line.hasLine && s.line.softEdgesInches <= 1e-9,
          ),
      isTrue,
    );
    var dark = 0;
    for (final plate
        in baked.pages.first.shapes.where(isLibvisioSoftEdgesPlate)) {
      expect(plate.hasImage, isTrue);
      expect(plate.is1D, isFalse);
      expect(plate.height, greaterThan(shape.height));
      final png = raster.decodePng(
        baked.images.findByPart(plate.imagePartName!)!.bytes,
      )!;
      expect(
        png.getPixel(png.width ~/ 2, png.height ~/ 2).r,
        greaterThan(200),
        reason: 'Sketch SoftEdges PNG must keep the hollow interior empty',
      );
      for (final pixel in png) {
        final luma = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
        if (luma < 180) dark++;
      }
    }
    expect(
      dark,
      greaterThan(40),
      reason: 'Sketch SoftEdges PNG must paint a feathered ring; dark=$dark',
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioSoftEdgesPlate),
      hasLength(2),
      reason: 'a second save must not stack another Sketch SoftEdges PNG',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(
      savedDoc.pages.first.shapes.where(isLibvisioSketchPlate),
      hasLength(2),
    );
    expect(
      savedDoc.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
      hasLength(2),
    );

    final connector = VsdxShapeFactory.line(
      id: 3,
      ax: 1.5,
      ay: 6.2,
      bx: 6.5,
      by: 6.2,
      name: 'SketchSoft_1D',
      line: const VsdxLine(
        color: VsdxColor.black,
        pattern: 1,
        weightInches: 0.1,
        softEdgesInches: 0.08,
      ),
    ).withSketchEffect(true).withSketchJiggle(3.5);
    var oneDoc = parser.parse(blank);
    oneDoc = oneDoc.replacePage(0, oneDoc.pages.first.addShape(connector));
    final oneBaked = documentForLibvisioWrite(oneDoc);
    expect(
      oneBaked.pages.first.shapes.where(isLibvisioSketchPlate),
      hasLength(2),
    );
    expect(
      oneBaked.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
      isEmpty,
      reason: '1-D SoftEdges stay skipped, matching canvas',
    );
  });

  test('Sketch jiggle strokes keep miter spikes for LibreOffice', () {
    final shape = VsdxShape(
      id: 1,
      name: 'SketchLongMiter',
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
    ).withDrawioMiterLimit(12).withSketchEffect(true).withSketchJiggle(3.5);
    expect(shapeNeedsLibvisioSketchStrokeBake(shape), isTrue);
    expect(shapeNeedsLibvisioMiterSpikeBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    expect(
      baked.pages.first.shapes.where(isLibvisioSketchPlate),
      hasLength(2),
    );
    expect(
      baked.pages.first.shapes
          .where(isLibvisioSketchPlate)
          .every(shapeNeedsLibvisioMiterSpikeBake),
      isTrue,
      reason: 'jiggle leftovers must keep the high miter Draw would bevel',
    );
    for (final plate in baked.pages.first.shapes.where(isLibvisioSketchPlate)) {
      final write = libvisioShapeWrite(plate);
      expect(write.line.pattern, 0);
      expect(write.fill.hasFill, isTrue);
      var maxX = 0.0;
      for (final geometry in write.geometries) {
        for (final command in geometry.commands) {
          if (command is MoveTo && command.x > maxX) maxX = command.x;
          if (command is LineTo && command.x > maxX) maxX = command.x;
        }
      }
      expect(
        maxX,
        greaterThan(3.2),
        reason: 'Sketch ribbon must keep the canvas miter spike past x=2.5',
      );
    }

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(
      savedDoc.pages.first.shapes.where(isLibvisioSketchPlate),
      hasLength(2),
    );
    expect(
      savedDoc.pages.first.shapes.where(isLibvisioSketchPlate).every(
            (s) => s.fill.hasFill && !s.line.hasLine,
          ),
      isTrue,
    );
    expect(
      parser
          .parse(writer.write(originalBytes: saved, edited: savedDoc))
          .pages
          .first
          .shapes
          .where(isLibvisioSketchPlate),
      hasLength(2),
      reason: 'a second save must not stack another Sketch miter ribbon',
    );

    final connector = VsdxShapeFactory.line(
      id: 3,
      ax: 1.5,
      ay: 6.2,
      bx: 6.5,
      by: 6.2,
      name: 'SketchLongMiter_1D',
      line: const VsdxLine(
        color: VsdxColor.black,
        weightInches: 0.24,
        cap: LineCap.square,
        miterLimit: 12,
      ),
    ).withDrawioMiterLimit(12).withSketchEffect(true).withSketchJiggle(3.5);
    var oneDoc = parser.parse(blank);
    oneDoc = oneDoc.replacePage(0, oneDoc.pages.first.addShape(connector));
    final oneBaked = documentForLibvisioWrite(oneDoc);
    expect(
      oneBaked.pages.first.shapes.where(isLibvisioSketchPlate),
      hasLength(2),
    );
    expect(
      oneBaked.pages.first.shapes
          .where(isLibvisioSketchPlate)
          .every((s) => !shapeNeedsLibvisioMiterSpikeBake(s)),
      isTrue,
      reason: 'a straight 1-D Sketch copy has no elbow to ribbon',
    );
  });

  test('Sketch jiggle strokes keep round-cap miters for LibreOffice', () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4.25,
      pinY: 5.5,
      width: 2,
      height: 1.2,
      name: 'SketchRoundCapMiter',
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(
        color: VsdxColor.black,
        weightInches: 0.24,
        cap: LineCap.round,
        join: VsdxLineJoin.miter,
      ),
    )
        .withDrawioLineJoin(VsdxLineJoin.miter)
        .withSketchEffect(true)
        .withSketchJiggle(3.5);
    expect(shapeNeedsLibvisioSketchStrokeBake(shape), isTrue);
    expect(shapeNeedsLibvisioRoundCapMiterFlatten(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    expect(
      baked.pages.first.shapes.where(isLibvisioSketchPlate),
      hasLength(2),
    );
    expect(
      baked.pages.first.shapes
          .where(isLibvisioSketchPlate)
          .every(shapeNeedsLibvisioRoundCapMiterFlatten),
      isTrue,
      reason:
          'jiggle leftovers must flatten LineCap so Draw does not round-join',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(
      savedDoc.pages.first.shapes.where(isLibvisioSketchPlate),
      hasLength(2),
    );
    expect(
      savedDoc.pages.first.shapes.where(isLibvisioSketchPlate).every(
            (s) => s.line.cap == LineCap.extended && s.line.pattern == 1,
          ),
      isTrue,
    );
    expect(
      parser
          .parse(writer.write(originalBytes: saved, edited: savedDoc))
          .pages
          .first
          .shapes
          .where(isLibvisioSketchPlate)
          .every((s) => s.line.cap == LineCap.extended),
      isTrue,
      reason: 'a second save must not restroke the already-flattened jiggle',
    );

    final connector = VsdxShapeFactory.line(
      id: 3,
      ax: 1.5,
      ay: 6.2,
      bx: 6.5,
      by: 6.2,
      name: 'SketchRoundCapMiter_1D',
      line: const VsdxLine(
        color: VsdxColor.black,
        weightInches: 0.24,
        cap: LineCap.round,
        join: VsdxLineJoin.miter,
      ),
    )
        .withDrawioLineJoin(VsdxLineJoin.miter)
        .withSketchEffect(true)
        .withSketchJiggle(3.5);
    var oneDoc = parser.parse(blank);
    oneDoc = oneDoc.replacePage(0, oneDoc.pages.first.addShape(connector));
    final oneBaked = documentForLibvisioWrite(oneDoc);
    expect(
      oneBaked.pages.first.shapes.where(isLibvisioSketchPlate),
      hasLength(2),
    );
    expect(
      oneBaked.pages.first.shapes
          .where(isLibvisioSketchPlate)
          .every((s) => !shapeNeedsLibvisioRoundCapMiterFlatten(s)),
      isTrue,
      reason: 'a straight 1-D Sketch copy has no join; keep the round cap',
    );
  });

  test('Sketch jiggle strokes keep custom dashes for LibreOffice', () {
    final shape = VsdxShapeFactory.line(
      id: 1,
      ax: 1,
      ay: 5.5,
      bx: 7,
      by: 5.5,
      name: 'SketchCustomDash',
      line: const VsdxLine(
        color: VsdxColor.black,
        weightInches: 0.15,
        pattern: 2,
      ),
    )
        .withDrawioDashPattern(const <double>[8, 4])
        .withSketchEffect(true)
        .withSketchJiggle(3.5);
    expect(shapeNeedsLibvisioSketchStrokeBake(shape), isTrue);
    expect(shapeNeedsLibvisioCustomDashBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    expect(
      baked.pages.first.shapes.where(isLibvisioSketchPlate),
      hasLength(2),
    );
    expect(
      baked.pages.first.shapes
          .where(isLibvisioSketchPlate)
          .every(shapeNeedsLibvisioCustomDashBake),
      isTrue,
      reason: 'jiggle leftovers must flatten veDashPattern Draw would snap',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    final plates = savedDoc.pages.first.shapes.where(isLibvisioSketchPlate);
    expect(plates, hasLength(2));
    expect(
      plates.every(
          (s) => s.line.pattern == 1 && s.line.customDashPattern == null),
      isTrue,
    );
    var moves = 0;
    for (final plate in plates) {
      for (final geometry in plate.geometries) {
        moves += geometry.commands.whereType<MoveTo>().length;
      }
    }
    expect(
      moves,
      greaterThan(2),
      reason:
          'each jiggle must become multiple dash subpaths, not LinePattern 2',
    );
    expect(
      parser
          .parse(writer.write(originalBytes: saved, edited: savedDoc))
          .pages
          .first
          .shapes
          .where(isLibvisioSketchPlate)
          .every((s) => s.line.pattern == 1),
      isTrue,
      reason: 'a second save must not restroke the already-dashed jiggle',
    );
  });

  test('Sketch jiggle strokes keep Flow Animation dashes for LibreOffice', () {
    final shape = VsdxShapeFactory.line(
      id: 1,
      ax: 1,
      ay: 5.5,
      bx: 7,
      by: 5.5,
      name: 'SketchFlowDash',
      line: const VsdxLine(
        color: VsdxColor.black,
        weightInches: 0.04,
        pattern: 1,
      ),
    ).withFlowAnimation(true).withSketchEffect(true).withSketchJiggle(3.5);
    expect(shapeNeedsLibvisioSketchStrokeBake(shape), isTrue);
    expect(shapeNeedsLibvisioFlowDashBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    expect(
      baked.pages.first.shapes.where(isLibvisioSketchPlate),
      hasLength(2),
    );
    expect(
      baked.pages.first.shapes
          .where(isLibvisioSketchPlate)
          .every(shapeNeedsLibvisioFlowDashBake),
      isTrue,
      reason:
          'jiggle leftovers must flatten Flow Animation Draw would stroke solid',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    final plates = savedDoc.pages.first.shapes.where(isLibvisioSketchPlate);
    expect(plates, hasLength(2));
    expect(
        plates.every((s) => !s.flowAnimation && s.line.pattern == 1), isTrue);
    var moves = 0;
    for (final plate in plates) {
      for (final geometry in plate.geometries) {
        moves += geometry.commands.whereType<MoveTo>().length;
      }
    }
    expect(
      moves,
      greaterThan(2),
      reason: 'each jiggle must become multiple 8 CSS-px dash subpaths',
    );
  });

  test(
      'Sketch jiggle strokes keep LinePattern gaps on a ribbon for LibreOffice',
      () {
    final shape = VsdxShapeFactory.line(
      id: 1,
      ax: 1,
      ay: 5.5,
      bx: 7,
      by: 5.5,
      name: 'SketchPatternDashTrans',
      line: const VsdxLine(
        color: VsdxColor.black,
        weightInches: 0.15,
        pattern: 2,
        transparency: 0.5,
      ),
    ).withSketchEffect(true).withSketchJiggle(3.5);
    expect(shapeNeedsLibvisioSketchStrokeBake(shape), isTrue);
    expect(shapeNeedsLibvisioLinePatternDashBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    expect(
      baked.pages.first.shapes.where(isLibvisioSketchPlate),
      hasLength(2),
    );
    expect(
      baked.pages.first.shapes
          .where(isLibvisioSketchPlate)
          .every(shapeNeedsLibvisioLinePatternDashBake),
      isTrue,
      reason: 'jiggle leftovers must flatten LinePattern before the ribbon',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    final plates = savedDoc.pages.first.shapes.where(isLibvisioSketchPlate);
    expect(plates, hasLength(2));
    expect(
      plates.every(
        (s) => !s.line.hasLine && s.fill.foregroundTransparency > 0.4,
      ),
      isTrue,
    );
    var filled = 0;
    for (final plate in plates) {
      filled += plate.geometries.where((g) => !g.noFill).length;
    }
    expect(
      filled,
      greaterThan(2),
      reason: 'each jiggle must ribbon each dash, not one solid band',
    );
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

  test('Label Border bakes a stroke sibling on connector labels', () {
    const label = VsdxRichText(
      runs: <VsdxTextRun>[
        VsdxTextRun(
          text: 'MMMM',
          charStyle: VsdxCharStyle(
            fontFamily: 'Arial',
            fontSizeInches: 0.5,
            color: VsdxColor(0xFF000000),
          ),
          paraStyle: VsdxParaStyle(
            horizontalAlign: VsdxHorzAlign.center,
          ),
        ),
      ],
    );
    final elbow = VsdxShapeFactory.line(
      id: 1,
      ax: 1,
      ay: 7,
      bx: 7,
      by: 1,
      name: 'LabelBorderEdge',
    ).copyWith(
      geometries: const <VsdxGeometry>[
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(0, 0),
            LineTo(6, 0),
            LineTo(6, -6),
          ],
        ),
      ],
      richText: label,
    ).withLabelBorderColor(const VsdxColor(0xFF1565C0));
    expect(shapeNeedsLibvisioLabelBorderBake(elbow), isFalse);
    expect(
      shapeNeedsLibvisioLabelBorderBake(
        VsdxShapeFactory.rectangle(
          id: 9,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
        )
            .copyWith(richText: label)
            .withLabelBorderColor(const VsdxColor(0xFF1565C0)),
      ),
      isTrue,
    );

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(elbow));
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
    expect(source.richText.textBlock.pinXInches, isNotNull);
    final plate =
        baked.pages.first.shapes.firstWhere(isLibvisioLabelBorderPlate);
    expect(plate.line.color?.value, 0xFF1565C0);
    expect(plate.fill.pattern, 0);
    expect(plate.locked, isTrue);
    expect(plate.width, lessThan(3));
    expect(plate.height, lessThan(1.2));
    expect(plate.pinX, closeTo(7, 0.35));
    expect(plate.pinY, closeTo(7, 0.35));

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(savedDoc.pages.first.findShapeById(1)!.labelBorderColor, isNull);
    expect(
      savedDoc.pages.first.shapes.where(isLibvisioLabelBorderPlate),
      hasLength(1),
    );
    final savedPlate =
        savedDoc.pages.first.shapes.firstWhere(isLibvisioLabelBorderPlate);
    expect(savedPlate.pinX, closeTo(7, 0.35));
    expect(savedPlate.pinY, closeTo(7, 0.35));
    expect(savedPlate.line.color?.value, 0xFF1565C0);
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

  test('Label Padding grows a connector-label plate for LibreOffice', () {
    const pad = VsdxLabelPadding.all(48);
    const label = VsdxRichText(
      textBlock: VsdxTextBlock(
        marginLeftInches: 0,
        marginRightInches: 0,
        marginTopInches: 0,
        marginBottomInches: 0,
        verticalAlign: VsdxVertAlign.middle,
        backgroundColor: VsdxColor(0xFFFF00FF),
      ),
      runs: <VsdxTextRun>[
        VsdxTextRun(
          text: 'M',
          charStyle: VsdxCharStyle(
            fontFamily: 'Arial',
            fontSizeInches: 0.5,
            color: VsdxColor(0xFF000000),
          ),
          paraStyle: VsdxParaStyle(
            horizontalAlign: VsdxHorzAlign.center,
          ),
        ),
      ],
    );
    final elbow = VsdxShapeFactory.line(
      id: 1,
      ax: 1,
      ay: 7,
      bx: 7,
      by: 1,
      name: 'LabelPaddingEdge',
    )
        .copyWith(
          geometries: const <VsdxGeometry>[
            VsdxGeometry(
              noFill: true,
              commands: <VsdxPathCommand>[
                MoveTo(0, 0),
                LineTo(6, 0),
                LineTo(6, -6),
              ],
            ),
          ],
          richText: label,
        )
        .withLabelPadding(pad)
        .withLabelBorderColor(const VsdxColor(0xFF1565C0));
    expect(shapeNeedsLibvisioLabelPaddingBake(elbow), isFalse);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(elbow));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.labelPadding.isZero, isTrue);
    expect(
      source.richText.textBlock.marginLeftInches,
      closeTo(48 / kLibvisioLabelPaddingPxPerInch, 1e-12),
    );
    expect(
      source.richText.textBlock.marginTopInches,
      closeTo(48 / kLibvisioLabelPaddingPxPerInch, 1e-12),
    );
    expect(source.richText.textBlock.pinXInches, isNotNull);
    expect(
      source.richText.textBlock.widthInches,
      greaterThan(1.0),
    );
    expect(
      source.richText.textBlock.heightInches,
      greaterThan(1.0),
    );
    final pagePin = baked.pages.first.localToPageDeep(
      source.id,
      Offset2D(
        source.richText.textBlock.pinXInches!,
        source.richText.textBlock.pinYInches!,
      ),
    );
    expect(pagePin.x, closeTo(7, 0.2));
    expect(pagePin.y, closeTo(7, 0.2));
    final plate =
        baked.pages.first.shapes.firstWhere(isLibvisioLabelBorderPlate);
    expect(plate.width, greaterThan(1.0));
    expect(plate.pinX, closeTo(7, 0.35));
    expect(plate.pinY, closeTo(7, 0.35));
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
    final after = parser.parse(saved).pages.first.findShapeById(1)!;
    expect(after.labelPadding.isZero, isTrue);
    expect(
      after.richText.textBlock.marginLeftInches,
      closeTo(0.5, 1e-9),
    );
    expect(after.richText.textBlock.widthInches, greaterThan(1.0));
  });

  test('Bullet lists bake the glyph LibreOffice never paints', () {
    const para = VsdxParaStyle(
      bullet: 3,
      textPosAfterBulletInches: 0.25,
      indentLeftInches: 0.1,
    );
    const body = VsdxCharStyle(
      fontFamily: 'Arial',
      fontSizeInches: 0.3,
      color: VsdxColor(0xFF000000),
    );
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4.25,
      pinY: 5.5,
      width: 3,
      height: 2,
      name: 'BulletBox',
      fill: const VsdxFill(foreground: VsdxColor.white, pattern: 1),
      line: const VsdxLine(pattern: 0),
    ).copyWith(
      text: 'AAA\nBBB',
      richText: const VsdxRichText(
        runs: <VsdxTextRun>[
          VsdxTextRun(text: 'AAA\nBBB', charStyle: body, paraStyle: para),
        ],
      ),
    );
    expect(shapeNeedsLibvisioBulletGlyphBake(shape), isTrue);
    expect(
      shapeNeedsLibvisioBulletGlyphBake(
        shape.copyWith(
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[VsdxTextRun(text: 'AAA', charStyle: body)],
          ),
        ),
      ),
      isFalse,
    );
    // TextPosAfterBullet is the minimum field; a wide glyph expands it.
    expect(libvisioBulletLabelWidth(para, body), closeTo(0.25, 1e-9));
    expect(
      libvisioBulletLabelWidth(
        para.copyWith(bulletStr: 'LONG'),
        body,
      ),
      greaterThan(0.5),
    );

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    final run = source.richText.runs.single;
    expect(run.text, '\u25a0 AAA\n\u25a0 BBB');
    expect(source.text, '\u25a0 AAA\n\u25a0 BBB');
    expect(run.paraStyle.bullet, 0);
    expect(run.paraStyle.bulletStr, isNull);
    expect(run.paraStyle.textPosAfterBulletInches, 0);
    // Hanging indent: the glyph sits back at the old IndLeft, wrapped body
    // lines hang at IndLeft + the label field.
    expect(run.paraStyle.indentLeftInches, closeTo(0.35, 1e-9));
    expect(run.paraStyle.indentFirstInches, closeTo(-0.25, 1e-9));
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .findShapeById(1)!
          .richText
          .runs
          .single
          .text,
      '\u25a0 AAA\n\u25a0 BBB',
      reason: 'a second save must not stack another glyph',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final after = parser.parse(saved).pages.first.findShapeById(1)!;
    final savedRun = after.richText.runs.first;
    expect(savedRun.paraStyle.bullet, 0);
    expect(after.richText.plainText, startsWith('\u25a0 AAA'));
    expect(savedRun.paraStyle.indentLeftInches, closeTo(0.35, 1e-6));
    expect(savedRun.paraStyle.indentFirstInches, closeTo(-0.25, 1e-6));

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    expect(oracle.svgPages(saved)?.join() ?? '', isNotEmpty);
  });

  test('Bullet lists bake the glyph past field spans LibreOffice never paints',
      () {
    const para = VsdxParaStyle(
      bullet: 3,
      textPosAfterBulletInches: 0.25,
      indentLeftInches: 0.1,
    );
    const body = VsdxCharStyle(
      fontFamily: 'Arial',
      fontSizeInches: 0.3,
      color: VsdxColor(0xFF000000),
    );
    const prefix = '\u25a0 ';
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4.25,
      pinY: 5.5,
      width: 3,
      height: 2,
      name: 'BulletFieldBox',
      fill: const VsdxFill(foreground: VsdxColor.white, pattern: 1),
      line: const VsdxLine(pattern: 0),
    ).copyWith(
      text: '42\n99',
      fields: const <VsdxFieldRow>[
        VsdxFieldRow(
          ix: 0,
          value: '42',
          valueFormula: 'PAGENUMBER()',
        ),
        VsdxFieldRow(
          ix: 1,
          value: '99',
          valueFormula: 'PAGECOUNT()',
        ),
      ],
      richText: const VsdxRichText(
        runs: <VsdxTextRun>[
          VsdxTextRun(
            text: '42\n99',
            charStyle: body,
            paraStyle: para,
            fieldSpans: <VsdxFieldSpan>[
              VsdxFieldSpan(start: 0, length: 2, ix: 0),
              VsdxFieldSpan(start: 3, length: 2, ix: 1),
            ],
          ),
        ],
      ),
    );
    expect(shapeNeedsLibvisioBulletGlyphBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    final run = source.richText.runs.single;
    expect(run.text, '${prefix}42\n${prefix}99');
    expect(source.text, '${prefix}42\n${prefix}99');
    expect(run.paraStyle.bullet, 0);
    expect(
      run.fieldSpans,
      <VsdxFieldSpan>[
        VsdxFieldSpan(start: prefix.length, length: 2, ix: 0),
        VsdxFieldSpan(start: 3 + 2 * prefix.length, length: 2, ix: 1),
      ],
    );
    expect(source.fields, hasLength(2));
    expect(source.fields.first.valueFormula, 'PAGENUMBER()');
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .findShapeById(1)!
          .richText
          .runs
          .single
          .text,
      '${prefix}42\n${prefix}99',
      reason: 'a second save must not stack another glyph',
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .findShapeById(1)!
          .richText
          .runs
          .single
          .fieldSpans,
      run.fieldSpans,
      reason: 'a second save must not shift <fld> again',
    );

    final wide = shape.copyWith(
      richText: VsdxRichText(
        runs: <VsdxTextRun>[
          VsdxTextRun(
            text: '42',
            charStyle: body,
            paraStyle: para.copyWith(bulletStr: '>>'),
            fieldSpans: const <VsdxFieldSpan>[
              VsdxFieldSpan(start: 0, length: 2, ix: 0),
            ],
          ),
        ],
      ),
    );
    final wideBaked = documentForLibvisioWrite(
      parser.parse(blank).replacePage(
            0,
            parser.parse(blank).pages.first.addShape(wide),
          ),
    );
    final wideRun =
        wideBaked.pages.first.findShapeById(1)!.richText.runs.single;
    expect(wideRun.text, '>> 42');
    expect(
      wideRun.fieldSpans.single,
      const VsdxFieldSpan(start: 3, length: 2, ix: 0),
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final after = parser.parse(saved).pages.first.findShapeById(1)!;
    expect(after.richText.runs.first.paraStyle.bullet, 0);
    expect(after.richText.plainText, '${prefix}42\n${prefix}99');
    expect(
      after.richText.runs.first.fieldSpans,
      <VsdxFieldSpan>[
        VsdxFieldSpan(start: prefix.length, length: 2, ix: 0),
        VsdxFieldSpan(start: 3 + 2 * prefix.length, length: 2, ix: 1),
      ],
    );
    expect(after.fields.map((f) => f.valueFormula).toList(),
        <String?>['PAGENUMBER()', 'PAGECOUNT()']);

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    expect(oracle.svgPages(saved)?.join() ?? '', contains('\u25a0'));
    expect(oracle.svgPages(saved)?.join() ?? '', contains('42'));
  });

  test('BulletFontSize and BulletFont bake onto their own Character run', () {
    const prefix = '\u25a0 ';
    const para = VsdxParaStyle(
      bullet: 3,
      bulletFont: 'Times New Roman',
      bulletFontSizeInches: 0.7,
      textPosAfterBulletInches: 0.25,
      indentLeftInches: 0.1,
    );
    const body = VsdxCharStyle(
      fontFamily: 'Arial',
      fontSizeInches: 0.28,
      color: VsdxColor(0xFF000000),
    );
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4.25,
      pinY: 5.5,
      width: 3,
      height: 2,
      name: 'BulletFontBox',
      fill: const VsdxFill(foreground: VsdxColor.white, pattern: 1),
      line: const VsdxLine(pattern: 0),
    ).copyWith(
      text: 'AAA\nBBB',
      richText: const VsdxRichText(
        runs: <VsdxTextRun>[
          VsdxTextRun(text: 'AAA\nBBB', charStyle: body, paraStyle: para),
        ],
      ),
    );
    expect(shapeNeedsLibvisioBulletGlyphBake(shape), isTrue);
    final label = libvisioBulletLabelWidth(para, body);
    expect(label, greaterThan(0.25));

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    final runs = source.richText.runs;
    expect(runs, hasLength(4));
    expect(runs[0].text, prefix);
    expect(runs[0].charStyle.fontSizeInches, closeTo(0.7, 1e-9));
    expect(runs[0].charStyle.fontFamily, 'Times New Roman');
    expect(runs[1].text, 'AAA\n');
    expect(runs[1].charStyle.fontSizeInches, closeTo(0.28, 1e-9));
    expect(runs[1].charStyle.fontFamily, 'Arial');
    expect(runs[2].text, prefix);
    expect(runs[2].charStyle.fontSizeInches, closeTo(0.7, 1e-9));
    expect(runs[3].text, 'BBB');
    expect(runs[3].charStyle.fontSizeInches, closeTo(0.28, 1e-9));
    expect(source.richText.plainText, '${prefix}AAA\n${prefix}BBB');
    expect(source.text, '${prefix}AAA\n${prefix}BBB');
    expect(
      runs.every((run) => run.paraStyle.bullet == 0),
      isTrue,
    );
    expect(runs.first.paraStyle.bulletFont, isNull);
    expect(runs.first.paraStyle.bulletFontSizeInches, isNull);
    expect(runs.first.paraStyle.indentLeftInches, closeTo(0.1 + label, 1e-9));
    expect(runs.first.paraStyle.indentFirstInches, closeTo(-label, 1e-9));
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .findShapeById(1)!
          .richText
          .runs,
      hasLength(4),
      reason: 'a second save must not stack another glyph run',
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .findShapeById(1)!
          .richText
          .plainText,
      '${prefix}AAA\n${prefix}BBB',
      reason: 'a second save must not stack another glyph',
    );

    final fieldShape = shape.copyWith(
      text: '42\n99',
      fields: const <VsdxFieldRow>[
        VsdxFieldRow(
          ix: 0,
          value: '42',
          valueFormula: 'PAGENUMBER()',
        ),
        VsdxFieldRow(
          ix: 1,
          value: '99',
          valueFormula: 'PAGECOUNT()',
        ),
      ],
      richText: const VsdxRichText(
        runs: <VsdxTextRun>[
          VsdxTextRun(
            text: '42\n99',
            charStyle: body,
            paraStyle: para,
            fieldSpans: <VsdxFieldSpan>[
              VsdxFieldSpan(start: 0, length: 2, ix: 0),
              VsdxFieldSpan(start: 3, length: 2, ix: 1),
            ],
          ),
        ],
      ),
    );
    final fieldBaked = documentForLibvisioWrite(
      parser.parse(blank).replacePage(
            0,
            parser.parse(blank).pages.first.addShape(fieldShape),
          ),
    );
    final fieldRuns = fieldBaked.pages.first.findShapeById(1)!.richText.runs;
    expect(fieldRuns, hasLength(4));
    expect(fieldRuns[1].text, '42\n');
    expect(fieldRuns[1].fieldSpans.single,
        const VsdxFieldSpan(start: 0, length: 2, ix: 0));
    expect(fieldRuns[3].text, '99');
    expect(fieldRuns[3].fieldSpans.single,
        const VsdxFieldSpan(start: 0, length: 2, ix: 1));
    expect(fieldRuns[0].fieldSpans, isEmpty);
    expect(fieldRuns[2].fieldSpans, isEmpty);

    final saved = writer.write(originalBytes: blank, edited: doc);
    final after = parser.parse(saved).pages.first.findShapeById(1)!;
    expect(after.richText.runs.length, greaterThanOrEqualTo(4));
    expect(
        after.richText.runs.first.charStyle.fontSizeInches, closeTo(0.7, 1e-6));
    expect(after.richText.runs.first.charStyle.fontFamily, 'Times New Roman');
    expect(
      after.richText.runs.any(
        (run) =>
            run.text.contains('AAA') &&
            (run.charStyle.fontSizeInches - 0.28).abs() < 1e-6,
      ),
      isTrue,
    );
    expect(after.richText.plainText, '${prefix}AAA\n${prefix}BBB');
    expect(after.richText.runs.first.paraStyle.bullet, 0);

    final sameSize = shape.copyWith(
      richText: const VsdxRichText(
        runs: <VsdxTextRun>[
          VsdxTextRun(
            text: 'AAA\nBBB',
            charStyle: body,
            paraStyle: VsdxParaStyle(
              bullet: 3,
              textPosAfterBulletInches: 0.25,
              indentLeftInches: 0.1,
            ),
          ),
        ],
      ),
    );
    final sameBaked = documentForLibvisioWrite(
      parser.parse(blank).replacePage(
            0,
            parser.parse(blank).pages.first.addShape(sameSize),
          ),
    );
    expect(
      sameBaked.pages.first.findShapeById(1)!.richText.runs,
      hasLength(1),
      reason: 'matching Size / Font must keep a single Character run',
    );

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    expect(oracle.svgPages(saved)?.join() ?? '', contains('\u25a0'));
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

  test('Word Wrap off expands a connector-label TxtWidth for LibreOffice', () {
    final stub = VsdxShapeFactory.line(
      id: 1,
      ax: 1,
      ay: 7,
      bx: 7,
      by: 1,
      name: 'WordWrapEdge',
    ).copyWith(
      geometries: const <VsdxGeometry>[
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(0, 0),
            LineTo(6, 0),
            LineTo(6, -6),
          ],
        ),
      ],
    );
    final blank = writer.emptyDocument();
    var probe = parser.parse(blank);
    probe = probe.replacePage(0, probe.pages.first.addShape(stub));
    final local = probe.pages.first.pageToLocalDeep(1, const Offset2D(7, 7));
    const label = VsdxRichText(
      runs: <VsdxTextRun>[
        VsdxTextRun(
          text: 'MMMM',
          charStyle: VsdxCharStyle(
            fontFamily: 'Arial',
            fontSizeInches: 0.35,
            color: VsdxColor(0xFFFF0000),
          ),
          paraStyle: VsdxParaStyle(
            horizontalAlign: VsdxHorzAlign.left,
          ),
        ),
        VsdxTextRun(
          text: 'MMMM',
          charStyle: VsdxCharStyle(
            fontFamily: 'Arial',
            fontSizeInches: 0.35,
            color: VsdxColor(0xFF00FF00),
          ),
          paraStyle: VsdxParaStyle(
            horizontalAlign: VsdxHorzAlign.left,
          ),
        ),
      ],
    );
    final elbow = stub
        .copyWith(
          richText: label.copyWith(
            textBlock: VsdxTextBlock(
              pinXInches: local.x,
              pinYInches: local.y,
              locPinXInches: 0.4,
              locPinYInches: 0.8,
              widthInches: 0.8,
              heightInches: 1.6,
              marginLeftInches: 0,
              marginRightInches: 0,
              marginTopInches: 0,
              marginBottomInches: 0,
              verticalAlign: VsdxVertAlign.middle,
            ),
          ),
        )
        .withWordWrap(false);
    expect(shapeNeedsLibvisioWordWrapBake(elbow), isTrue);
    expect(
      shapeNeedsLibvisioWordWrapBake(
        stub.copyWith(richText: label).withWordWrap(false),
      ),
      isFalse,
      reason: 'a missing TxtPin must wait for the loose-label bake',
    );
    final needed = nowrapTxtWidthForLibvisioWrite(elbow);
    expect(needed, greaterThan(1.4));

    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(elbow));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.wordWrap, isTrue);
    expect(source.richText.textBlock.widthInches, closeTo(needed, 1e-9));
    expect(source.richText.textBlock.locPinXInches, closeTo(0.4, 1e-9));
    final pagePin = baked.pages.first.localToPageDeep(
      source.id,
      Offset2D(
        source.richText.textBlock.pinXInches!,
        source.richText.textBlock.pinYInches!,
      ),
    );
    expect(pagePin.x, closeTo(7, 0.2));
    expect(pagePin.y, closeTo(7, 0.2));
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

    final saved = writer.write(originalBytes: blank, edited: doc);
    final after = parser.parse(saved).pages.first.findShapeById(1)!;
    expect(after.wordWrap, isTrue);
    expect(after.richText.textBlock.widthInches, closeTo(needed, 1e-6));
  });

  test('Word Wrap off bakes TxtWidth past tab fields for LibreOffice', () {
    const tabs = <VsdxTabSet>[
      VsdxTabSet(
        ix: 0,
        stops: <VsdxTabStop>[VsdxTabStop(positionInches: 2)],
      ),
    ];
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4.25,
      pinY: 5.5,
      width: 1.2,
      height: 0.8,
      name: 'WordWrapTab',
      fill: const VsdxFill(foreground: VsdxColor.white, pattern: 1),
      line: const VsdxLine(pattern: 0),
    )
        .copyWith(
          richText: const VsdxRichText(
            tabSets: tabs,
            textBlock: VsdxTextBlock(
              marginLeftInches: 0,
              marginRightInches: 0,
              marginTopInches: 0,
              marginBottomInches: 0,
              verticalAlign: VsdxVertAlign.middle,
            ),
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'A\t',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 0.35,
                  color: VsdxColor(0xFFFF0000),
                ),
                paraStyle: VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.left,
                ),
              ),
              VsdxTextRun(
                text: 'B',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 0.35,
                  color: VsdxColor(0xFF00FF00),
                ),
                paraStyle: VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.left,
                ),
              ),
            ],
          ),
        )
        .withWordWrap(false);
    expect(shapeNeedsLibvisioWordWrapBake(shape), isTrue);
    final needed = nowrapTxtWidthForLibvisioWrite(shape);
    expect(needed, greaterThan(2));

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.wordWrap, isTrue);
    expect(source.richText.textBlock.widthInches, closeTo(needed, 1e-9));
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

    final saved = writer.write(originalBytes: blank, edited: doc);
    final after = parser.parse(saved).pages.first.findShapeById(1)!;
    expect(after.wordWrap, isTrue);
    expect(after.richText.textBlock.widthInches, closeTo(needed, 1e-6));
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

  test('theme-only SoftEdges bakes a feathered PNG for LibreOffice', () {
    const slot = ThemeSlot.accent2;
    final expected = VsdxTheme.office.resolve(slot)!;
    final fill = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.2,
      height: 0.8,
      name: 'SoftThemeFill',
      fill: const VsdxFill(themeForegroundIndex: slot, pattern: 1),
      line: const VsdxLine(pattern: 0, softEdgesInches: 0.08),
    );
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(fill), isTrue);
    expect(fill.fill.foreground, isNull);

    final blank = writer.emptyDocument();
    var filledDoc = parser.parse(blank).copyWith(theme: VsdxTheme.office);
    filledDoc = filledDoc.replacePage(0, filledDoc.pages.first.addShape(fill));
    final baked = documentForLibvisioWrite(filledDoc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.fill.pattern, 0);
    expect(source.line.softEdgesInches, closeTo(0, 1e-9));
    final plate =
        baked.pages.first.shapes.where(isLibvisioSoftEdgesPlate).single;
    expect(plate.hasImage, isTrue);
    expect(plate.locked, isTrue);
    final decoded = raster.decodePng(
      baked.images.findByPart(plate.imagePartName!)!.bytes,
    )!;
    var ink = 0;
    for (var y = 0; y < decoded.height; y++) {
      for (var x = 0; x < decoded.width; x++) {
        final pixel = decoded.getPixel(x, y);
        if (pixel.a > 20 && pixel.r > pixel.b + 20 && pixel.r > pixel.g + 10) {
          ink++;
        }
      }
    }
    expect(ink, greaterThan(8),
        reason: 'theme slot $slot (${expected.value.toRadixString(16)}) '
            'must freeze into the feathered PNG, not a hard THEMEVAL fill');
    expect(
      decoded.getPixel(0, 0).a,
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

    final stroke = VsdxShapeFactory.rectangle(
      id: 2,
      pinX: 2,
      pinY: 2,
      width: 1.4,
      height: 0.7,
      name: 'SoftThemeStroke',
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(
        themeColorIndex: slot,
        weightInches: 0.08,
        softEdgesInches: 0.08,
      ),
    );
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(stroke), isTrue);
    var strokeDoc = parser.parse(blank).copyWith(theme: VsdxTheme.office);
    strokeDoc =
        strokeDoc.replacePage(0, strokeDoc.pages.first.addShape(stroke));
    final strokeBaked = documentForLibvisioWrite(strokeDoc);
    final strokeSource = strokeBaked.pages.first.findShapeById(2)!;
    expect(strokeSource.fill.pattern, 0);
    expect(strokeSource.line.pattern, 0);
    expect(strokeSource.line.themeColorIndex, slot);
    final strokePlate =
        strokeBaked.pages.first.shapes.where(isLibvisioSoftEdgesPlate).single;
    expect(strokePlate.hasImage, isTrue);
    final strokeDecoded = raster.decodePng(
      strokeBaked.images.findByPart(strokePlate.imagePartName!)!.bytes,
    )!;
    var ring = 0;
    for (var y = 0; y < strokeDecoded.height; y++) {
      for (var x = 0; x < strokeDecoded.width; x++) {
        final pixel = strokeDecoded.getPixel(x, y);
        if (pixel.a > 20 && pixel.r > pixel.b + 20 && pixel.r > pixel.g + 10) {
          ring++;
        }
      }
    }
    expect(ring, greaterThan(8),
        reason: 'theme-only LineColor must freeze into the feathered ring');
    expect(
      strokeDecoded
          .getPixel(strokeDecoded.width ~/ 2, strokeDecoded.height ~/ 2)
          .r,
      greaterThan(200),
      reason: 'theme stroke SoftEdges PNG must keep the hollow interior',
    );
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

  test('multi-stop FillGradient bakes a PNG plate for LibreOffice', () {
    const wash = VsdxGradient(
      stops: <VsdxGradientStop>[
        VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF00FF)),
        VsdxGradientStop(position: 0.5, color: VsdxColor(0xFF00FF00)),
        VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
      ],
    );
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.2,
      height: 0.8,
      name: 'Grad3',
      fill: const VsdxFill(pattern: 1, gradient: wash),
      line: const VsdxLine(pattern: 0),
    );
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.fill.pattern, 0);
    expect(source.fill.hasGradient, isFalse);
    final plate =
        baked.pages.first.shapes.where(isLibvisioSoftEdgesPlate).single;
    final png = baked.images.findByPart(plate.imagePartName!);
    expect(png, isNotNull);
    final decoded = raster.decodePng(png!.bytes)!;
    final y = decoded.height ~/ 2;
    final left = decoded.getPixel(1, y);
    final mid = decoded.getPixel(decoded.width ~/ 2, y);
    final right = decoded.getPixel(decoded.width - 2, y);
    expect(
      left.r,
      greaterThan(mid.r + 80),
      reason: 'left stop must stay magenta; left=$left mid=$mid right=$right',
    );
    expect(
      left.b,
      greaterThan(mid.b + 80),
      reason: 'left stop must stay magenta; left=$left mid=$mid right=$right',
    );
    expect(
      mid.g,
      greaterThan(left.g + 80),
      reason: 'middle stop must stay green; left=$left mid=$mid right=$right',
    );
    expect(
      mid.g,
      greaterThan(right.g + 80),
      reason: 'middle stop must stay green; left=$left mid=$mid right=$right',
    );
    expect(
      right.b,
      greaterThan(mid.b + 80),
      reason: 'right stop must stay blue; left=$left mid=$mid right=$right',
    );
    expect(
      right.r,
      lessThan(40),
      reason: 'right stop must stay blue; left=$left mid=$mid right=$right',
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioSoftEdgesPlate),
      hasLength(1),
      reason: 'a second save must not stack another FillGradient plate',
    );

    const twoStop = VsdxGradient(
      stops: <VsdxGradientStop>[
        VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
        VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
      ],
    );
    final two = VsdxShapeFactory.rectangle(
      id: 2,
      pinX: 5,
      pinY: 2,
      width: 1.2,
      height: 0.8,
      name: 'Grad2',
      fill: const VsdxFill(pattern: 1, gradient: twoStop),
      line: const VsdxLine(pattern: 0),
    );
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(two), isFalse);
    var twoDoc = parser.parse(blank);
    twoDoc = twoDoc.replacePage(0, twoDoc.pages.first.addShape(two));
    expect(
      documentForLibvisioWrite(twoDoc)
          .pages
          .first
          .shapes
          .where(isLibvisioSoftEdgesPlate),
      isEmpty,
      reason: 'two-colour FillGradient must stay classic FillPattern 25–40',
    );
    final twoSaved =
        parser.parse(writer.write(originalBytes: blank, edited: twoDoc));
    expect(
      twoSaved.pages.first.findShapeById(2)!.fill.pattern,
      inInclusiveRange(25, 40),
    );

    const fadedStops = VsdxGradient(
      stops: <VsdxGradientStop>[
        VsdxGradientStop(
          position: 0,
          color: VsdxColor(0xFFFF00FF),
          transparency: 0.65,
        ),
        VsdxGradientStop(
          position: 1,
          color: VsdxColor(0xFF0000FF),
          transparency: 0.65,
        ),
      ],
    );
    final faded = VsdxShapeFactory.rectangle(
      id: 4,
      pinX: 2,
      pinY: 5,
      width: 1.2,
      height: 0.8,
      name: 'Grad2Fade',
      fill: const VsdxFill(pattern: 1, gradient: fadedStops),
      line: const VsdxLine(pattern: 0),
    );
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(faded), isTrue);
    var fadedDoc = parser.parse(blank);
    fadedDoc = fadedDoc.replacePage(0, fadedDoc.pages.first.addShape(faded));
    final fadedBaked = documentForLibvisioWrite(fadedDoc);
    expect(fadedBaked.pages.first.findShapeById(4)!.fill.pattern, 0);
    final fadedPlate =
        fadedBaked.pages.first.shapes.where(isLibvisioSoftEdgesPlate).single;
    final fadedPng = raster.decodePng(
      fadedBaked.images.findByPart(fadedPlate.imagePartName!)!.bytes,
    )!;
    final fadedMid =
        fadedPng.getPixel(fadedPng.width ~/ 2, fadedPng.height ~/ 2);
    final fadedLuma =
        0.299 * fadedMid.r + 0.587 * fadedMid.g + 0.114 * fadedMid.b;
    expect(
      fadedLuma,
      greaterThan(150),
      reason: 'Draw composites FillPattern 25–40 opacity onto opaque; '
          'the PNG must wash toward white; luma=$fadedLuma $fadedMid',
    );
    expect(
      documentForLibvisioWrite(fadedBaked)
          .pages
          .first
          .shapes
          .where(isLibvisioSoftEdgesPlate),
      hasLength(1),
      reason: 'a second save must not stack another faded FillGradient plate',
    );

    final cellFade = VsdxShapeFactory.rectangle(
      id: 5,
      pinX: 5,
      pinY: 5,
      width: 1.2,
      height: 0.8,
      name: 'Grad2CellFade',
      fill: const VsdxFill(
        pattern: 1,
        foregroundTransparency: 0.65,
        gradient: twoStop,
      ),
      line: const VsdxLine(pattern: 0),
    );
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(cellFade), isTrue);
    var cellDoc = parser.parse(blank);
    cellDoc = cellDoc.replacePage(0, cellDoc.pages.first.addShape(cellFade));
    final cellBaked = documentForLibvisioWrite(cellDoc);
    expect(cellBaked.pages.first.findShapeById(5)!.fill.pattern, 0);
    expect(
      cellBaked.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
      hasLength(1),
    );

    const skipped = VsdxFill(
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
    expect(
      shapeNeedsLibvisioGeometrySoftEdgesBake(
        VsdxShapeFactory.rectangle(
          id: 3,
          pinX: 2,
          pinY: 5,
          width: 1.2,
          height: 0.8,
          fill: skipped,
          line: const VsdxLine(pattern: 0),
        ),
      ),
      isTrue,
      reason: 'a fully transparent stop is not two opaque 25–40 colours',
    );
    var skippedDoc = parser.parse(blank);
    skippedDoc = skippedDoc.replacePage(
      0,
      skippedDoc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: 3,
          pinX: 2,
          pinY: 5,
          width: 1.2,
          height: 0.8,
          name: 'GradClearStop',
          fill: skipped,
          line: const VsdxLine(pattern: 0),
        ),
      ),
    );
    final skippedBaked = documentForLibvisioWrite(skippedDoc);
    expect(skippedBaked.pages.first.findShapeById(3)!.fill.pattern, 0);
    final skippedPlate =
        skippedBaked.pages.first.shapes.where(isLibvisioSoftEdgesPlate).single;
    final skippedPng = raster.decodePng(
      skippedBaked.images.findByPart(skippedPlate.imagePartName!)!.bytes,
    )!;
    var skippedMax = 0.0;
    var skippedMin = 255.0;
    for (final pixel in skippedPng) {
      if (pixel.a < 200) continue;
      final luma = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
      if (luma > skippedMax) skippedMax = luma;
      if (luma < skippedMin) skippedMin = luma;
    }
    expect(
      skippedMax,
      greaterThan(240),
      reason: 'fully transparent stop must composite onto white; '
          'max=$skippedMax min=$skippedMin',
    );
    expect(
      skippedMin,
      lessThan(180),
      reason: 'opaque blue stop must remain; max=$skippedMax min=$skippedMin',
    );
    expect(
      documentForLibvisioWrite(skippedBaked)
          .pages
          .first
          .shapes
          .where(isLibvisioSoftEdgesPlate),
      hasLength(1),
      reason: 'a second save must not stack another clear-stop plate',
    );
  });

  test(
    'multi-stop FillGradient keeps a hard shadow on the PNG for LibreOffice',
    () {
      const wash = VsdxGradient(
        stops: <VsdxGradientStop>[
          VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF00FF)),
          VsdxGradientStop(position: 0.5, color: VsdxColor(0xFF00FF00)),
          VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
        ],
      );
      const hardShadow = VsdxShadow(
        enabled: true,
        color: VsdxColor(0xFF000000),
        offsetXInches: 0.45,
        offsetYInches: -0.45,
        blurInches: 0,
        transparency: 0.2,
        pattern: 1,
      );
      final shape = VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 4.25,
        pinY: 6.2,
        width: 3.0,
        height: 1.4,
        name: 'Grad3HardShadow',
        fill: const VsdxFill(pattern: 1, gradient: wash),
        line: const VsdxLine(pattern: 0),
      ).copyWith(shadow: hardShadow);
      expect(shapeNeedsLibvisioGeometrySoftEdgesBake(shape), isTrue);
      expect(shapeNeedsLibvisioShadowBake(shape), isTrue);

      final blank = writer.emptyDocument();
      var doc = parser.parse(blank);
      doc = doc.replacePage(0, doc.pages.first.addShape(shape));
      final baked = documentForLibvisioWrite(doc);
      final source = baked.pages.first.findShapeById(1)!;
      expect(source.fill.pattern, 0);
      expect(source.shadow.enabled, isFalse,
          reason: 'Foreign fill PNG cannot collect draw:shadow');
      expect(
        baked.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
        hasLength(1),
      );
      final shadowPlate =
          baked.pages.first.shapes.where(isLibvisioShadowPlate).single;
      expect(shadowPlate.hasImage, isTrue);
      expect(shadowPlate.pinX, closeTo(4.7, 1e-9));
      expect(shadowPlate.pinY, closeTo(5.75, 1e-9));
      expect(
        documentForLibvisioWrite(baked)
            .pages
            .first
            .shapes
            .where(isLibvisioShadowPlate),
        hasLength(1),
        reason: 'a second save must not stack another hard-shadow plate',
      );

      final saved = writer.write(originalBytes: blank, edited: doc);
      final savedDoc = parser.parse(saved);
      expect(savedDoc.pages.first.findShapeById(1)!.shadow.enabled, isFalse);
      expect(
        savedDoc.pages.first.shapes.where(isLibvisioShadowPlate),
        hasLength(1),
      );
      expect(
        savedDoc.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
        hasLength(1),
      );

      const twoStop = VsdxGradient(
        stops: <VsdxGradientStop>[
          VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF00FF)),
          VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
        ],
      );
      final two = VsdxShapeFactory.rectangle(
        id: 2,
        pinX: 4.25,
        pinY: 6.2,
        width: 3.0,
        height: 1.4,
        name: 'Grad2HardShadow',
        fill: const VsdxFill(pattern: 1, gradient: twoStop),
        line: const VsdxLine(pattern: 0),
      ).copyWith(shadow: hardShadow);
      var twoDoc = parser.parse(blank);
      twoDoc = twoDoc.replacePage(0, twoDoc.pages.first.addShape(two));
      final twoBaked = documentForLibvisioWrite(twoDoc);
      expect(
        twoBaked.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
        isEmpty,
      );
      expect(twoBaked.pages.first.findShapeById(2)!.shadow.enabled, isTrue,
          reason: 'two-colour FillGradient keeps native draw:shadow');
    },
  );

  test(
    'multi-stop LineGradient keeps a hard shadow on the PNG for LibreOffice',
    () {
      const wash = VsdxGradient(
        stops: <VsdxGradientStop>[
          VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF00FF)),
          VsdxGradientStop(position: 0.5, color: VsdxColor(0xFF00FF00)),
          VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
        ],
      );
      const hardShadow = VsdxShadow(
        enabled: true,
        color: VsdxColor(0xFF000000),
        offsetXInches: 0.45,
        offsetYInches: -0.45,
        blurInches: 0,
        transparency: 0.2,
        pattern: 1,
      );
      final shape = VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 4.25,
        pinY: 6.2,
        width: 3.0,
        height: 1.4,
        name: 'LineGrad3HardShadow',
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(pattern: 1, weightInches: 0.18, gradient: wash),
      ).copyWith(shadow: hardShadow);
      expect(shapeNeedsLibvisioGeometrySoftEdgesBake(shape), isTrue);
      expect(shapeNeedsLibvisioShadowBake(shape), isTrue);

      final blank = writer.emptyDocument();
      var doc = parser.parse(blank);
      doc = doc.replacePage(0, doc.pages.first.addShape(shape));
      final baked = documentForLibvisioWrite(doc);
      final source = baked.pages.first.findShapeById(1)!;
      expect(source.line.pattern, 0);
      expect(source.shadow.enabled, isFalse,
          reason: 'Foreign stroke PNG cannot collect draw:shadow');
      expect(
        baked.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
        hasLength(1),
      );
      final shadowPlate =
          baked.pages.first.shapes.where(isLibvisioShadowPlate).single;
      expect(shadowPlate.hasImage, isTrue);
      expect(shadowPlate.pinX, closeTo(4.7, 1e-9));
      expect(shadowPlate.pinY, closeTo(5.75, 1e-9));
      final shadowPng = raster.decodePng(
        baked.images.findByPart(shadowPlate.imagePartName!)!.bytes,
      )!;
      final mid = shadowPng.getPixel(
        shadowPng.width ~/ 2,
        shadowPng.height ~/ 2,
      );
      expect(
        mid.a,
        lessThan(20),
        reason: 'stroke shadow must stay a ring, not a filled box; $mid',
      );
      var ink = 0;
      for (final pixel in shadowPng) {
        if (pixel.a > 100) ink++;
      }
      expect(
        ink,
        greaterThan(50),
        reason: 'stroke-ring shadow must have ink; ink=$ink',
      );
      expect(
        documentForLibvisioWrite(baked)
            .pages
            .first
            .shapes
            .where(isLibvisioShadowPlate),
        hasLength(1),
        reason: 'a second save must not stack another hard-shadow plate',
      );

      final saved = writer.write(originalBytes: blank, edited: doc);
      final savedDoc = parser.parse(saved);
      expect(savedDoc.pages.first.findShapeById(1)!.shadow.enabled, isFalse);
      expect(
        savedDoc.pages.first.shapes.where(isLibvisioShadowPlate),
        hasLength(1),
      );
      expect(
        savedDoc.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
        hasLength(1),
      );

      const twoStop = VsdxGradient(
        stops: <VsdxGradientStop>[
          VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF00FF)),
          VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
        ],
      );
      final two = VsdxShapeFactory.rectangle(
        id: 2,
        pinX: 4.25,
        pinY: 6.2,
        width: 3.0,
        height: 1.4,
        name: 'LineGrad2HardShadow',
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(
          pattern: 1,
          weightInches: 0.18,
          gradient: twoStop,
        ),
      ).copyWith(shadow: hardShadow);
      expect(shapeNeedsLibvisioShadowBake(two), isFalse);
      var twoDoc = parser.parse(blank);
      twoDoc = twoDoc.replacePage(0, twoDoc.pages.first.addShape(two));
      final twoBaked = documentForLibvisioWrite(twoDoc);
      expect(
        twoBaked.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
        isEmpty,
      );
      expect(
        twoBaked.pages.first.shapes.where(isLibvisioShadowPlate),
        isEmpty,
      );
      expect(twoBaked.pages.first.findShapeById(2)!.shadow.enabled, isTrue,
          reason: 'two-colour LineGradient keeps native draw:shadow');

      final connector = VsdxShapeFactory.line(
        id: 3,
        ax: 1.5,
        ay: 6.2,
        bx: 6.5,
        by: 6.2,
        name: 'LineGrad3HardShadow_1D',
        line: const VsdxLine(pattern: 1, weightInches: 0.18, gradient: wash),
      ).copyWith(shadow: hardShadow);
      expect(shapeNeedsLibvisioGeometrySoftEdgesBake(connector), isTrue);
      expect(shapeNeedsLibvisioShadowBake(connector), isTrue,
          reason: '1-D three-colour wash becomes a Foreign PNG');
      var oneDoc = parser.parse(blank);
      oneDoc = oneDoc.replacePage(0, oneDoc.pages.first.addShape(connector));
      final oneBaked = documentForLibvisioWrite(oneDoc);
      expect(oneBaked.pages.first.findShapeById(3)!.shadow.enabled, isFalse);
      expect(
        oneBaked.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
        hasLength(1),
      );
      final oneShadow =
          oneBaked.pages.first.shapes.where(isLibvisioShadowPlate).single;
      expect(oneShadow.is1D, isFalse);
      expect(oneShadow.height.abs(), greaterThan(0.1));
      expect(oneShadow.pinX, closeTo(4.45, 1e-9));
      expect(oneShadow.pinY, closeTo(5.75, 1e-9));
      final oneShadowPng = raster.decodePng(
        oneBaked.images.findByPart(oneShadow.imagePartName!)!.bytes,
      )!;
      var oneInk = 0;
      for (final pixel in oneShadowPng) {
        if (pixel.a > 100) oneInk++;
      }
      expect(
        oneInk,
        greaterThan(50),
        reason: '1-D stroke-ring shadow must have ink; ink=$oneInk',
      );
      expect(
        documentForLibvisioWrite(oneBaked)
            .pages
            .first
            .shapes
            .where(isLibvisioShadowPlate),
        hasLength(1),
        reason: 'a second save must not stack another 1-D hard-shadow plate',
      );

      final two1d = VsdxShapeFactory.line(
        id: 4,
        ax: 1.5,
        ay: 5.0,
        bx: 6.5,
        by: 5.0,
        name: 'LineGrad2HardShadow_1D',
        line: const VsdxLine(
          pattern: 1,
          weightInches: 0.18,
          gradient: twoStop,
        ),
      ).copyWith(shadow: hardShadow);
      expect(shapeNeedsLibvisioShadowBake(two1d), isFalse,
          reason: 'two-colour 1-D LineGradient keeps a filled ribbon');
    },
  );

  test(
    'multi-stop LineGradient hard shadow shears on an oblique page',
    () {
      const wash = VsdxGradient(
        stops: <VsdxGradientStop>[
          VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF00FF)),
          VsdxGradientStop(position: 0.5, color: VsdxColor(0xFF00FF00)),
          VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
        ],
      );
      const hardShadow = VsdxShadow(
        enabled: true,
        color: VsdxColor(0xFF000000),
        offsetXInches: 0.45,
        offsetYInches: -0.45,
        blurInches: 0,
        transparency: 0.2,
        pattern: 1,
      );
      final shape = VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 4.25,
        pinY: 6.2,
        width: 3.0,
        height: 1.4,
        name: 'LineGrad3ObliqueShadow',
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(pattern: 1, weightInches: 0.18, gradient: wash),
      ).copyWith(shadow: hardShadow);

      final blank = writer.emptyDocument();
      final base = parser.parse(blank);
      final upright = base.pages.first.addShape(shape);

      ({double width, raster.Image png, int midAlpha}) bake(VsdxPage page) {
        final doc = base.replacePage(0, page);
        final baked = documentForLibvisioWrite(doc);
        expect(
          baked.pages.first.shapes.where(isLibvisioPageShadowPlate),
          isEmpty,
        );
        final plate =
            baked.pages.first.shapes.where(isLibvisioShadowPlate).single;
        final png = raster.decodePng(
          baked.images.findByPart(plate.imagePartName!)!.bytes,
        )!;
        final mid = png.getPixel(png.width ~/ 2, png.height ~/ 2);
        return (width: plate.width, png: png, midAlpha: mid.a.toInt());
      }

      final plain = bake(upright);
      expect(plain.midAlpha, lessThan(20),
          reason: 'upright LineGradient shadow must stay a ring');
      final oblique = bake(
        upright.copyWith(
          pageSheet: upright.pageSheet.copyWith(
            shadowType: 1,
            shadowObliqueAngle: 0.6,
          ),
        ),
      );
      expect(oblique.midAlpha, lessThan(20),
          reason: 'sheared LineGradient shadow must stay a ring, not a box');
      expect(
        oblique.width,
        greaterThan(plain.width + 0.1),
        reason: 'the sheared stroke ring needs a wider box than the shape',
      );

      int firstOpaqueX(raster.Image png, int y) {
        for (var x = 0; x < png.width; x++) {
          if (png.getPixel(x, y).a > 40) return x;
        }
        return -1;
      }

      final near =
          firstOpaqueX(oblique.png, (oblique.png.height * 0.25).round());
      final far =
          firstOpaqueX(oblique.png, (oblique.png.height * 0.75).round());
      expect(near, greaterThanOrEqualTo(0));
      expect(far, greaterThanOrEqualTo(0));
      expect(
        near,
        greaterThan(far + 2),
        reason: 'positive ShdwObliqueAngle leans the top edge right; '
            'near=$near far=$far',
      );

      final connector = VsdxShapeFactory.line(
        id: 2,
        ax: 1.5,
        ay: 6.2,
        bx: 6.5,
        by: 6.2,
        name: 'LineGrad3ObliqueShadow_1D',
        line: const VsdxLine(pattern: 1, weightInches: 0.18, gradient: wash),
      ).copyWith(shadow: hardShadow);
      final oneBase = parser.parse(blank);
      final oneUpright = oneBase.pages.first.addShape(connector);
      ({double width, raster.Image png}) bake1d(VsdxPage page) {
        final doc = oneBase.replacePage(0, page);
        final baked = documentForLibvisioWrite(doc);
        final plate =
            baked.pages.first.shapes.where(isLibvisioShadowPlate).single;
        expect(plate.is1D, isFalse);
        return (
          width: plate.width,
          png: raster.decodePng(
            baked.images.findByPart(plate.imagePartName!)!.bytes,
          )!,
        );
      }

      final onePlain = bake1d(oneUpright);
      final oneOblique = bake1d(
        oneUpright.copyWith(
          pageSheet: oneUpright.pageSheet.copyWith(
            shadowType: 1,
            shadowObliqueAngle: 0.6,
          ),
        ),
      );
      expect(oneOblique.width, greaterThan(onePlain.width + 0.05));
      final oneNear = firstOpaqueX(
        oneOblique.png,
        (oneOblique.png.height * 0.25).round(),
      );
      final oneFar = firstOpaqueX(
        oneOblique.png,
        (oneOblique.png.height * 0.75).round(),
      );
      expect(oneNear, greaterThan(oneFar + 2),
          reason: '1-D sheared stroke must lean top-right; '
              'near=$oneNear far=$oneFar');
    },
  );

  test(
    'multi-stop FillGradient on EllipticalArcTo follows the sampled silhouette',
    () {
      const wash = VsdxGradient(
        stops: <VsdxGradientStop>[
          VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF00FF)),
          VsdxGradientStop(position: 0.5, color: VsdxColor(0xFF00FF00)),
          VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
        ],
      );
      raster.Pixel pxAt(
        raster.Image img, {
        required double x,
        required double y,
        required double width,
        required double height,
      }) {
        final ix =
            (x / width * (img.width - 1)).round().clamp(0, img.width - 1);
        final iy = ((1 - y / height) * (img.height - 1))
            .round()
            .clamp(0, img.height - 1);
        return img.getPixel(ix, iy);
      }

      final pie = VsdxShapeFactory.pie(
        id: 1,
        pinX: 2,
        pinY: 2,
        width: 2,
        height: 2,
        name: 'Pie3',
        fill: const VsdxFill(pattern: 1, gradient: wash),
        line: const VsdxLine(pattern: 0),
      );
      expect(shapeNeedsLibvisioGeometrySoftEdgesBake(pie), isTrue);

      final blank = writer.emptyDocument();
      var doc = parser.parse(blank);
      doc = doc.replacePage(0, doc.pages.first.addShape(pie));
      final baked = documentForLibvisioWrite(doc);
      expect(baked.pages.first.findShapeById(1)!.fill.pattern, 0);
      final plate =
          baked.pages.first.shapes.where(isLibvisioSoftEdgesPlate).single;
      final png = baked.images.findByPart(plate.imagePartName!);
      final decoded = raster.decodePng(png!.bytes)!;
      final bow = pxAt(decoded, x: 1.7, y: 1.7, width: 2, height: 2);
      final empty = pxAt(decoded, x: 0.25, y: 0.25, width: 2, height: 2);
      expect(
        bow.a,
        greaterThan(200),
        reason: 'pie arc bow must stay inside the PNG, not a chord triangle; '
            'bow=$bow',
      );
      expect(
        bow.r,
        lessThan(200),
        reason: 'pie arc bow must keep the wash, not the white plate; bow=$bow',
      );
      expect(
        empty.r,
        greaterThan(240),
        reason: 'Draw paints Blue 2 through transparent PNG; empty=$empty',
      );
      expect(
        empty.g,
        greaterThan(240),
        reason: 'Draw paints Blue 2 through transparent PNG; empty=$empty',
      );
      expect(
        empty.b,
        greaterThan(240),
        reason: 'Draw paints Blue 2 through transparent PNG; empty=$empty',
      );
      expect(
        documentForLibvisioWrite(baked)
            .pages
            .first
            .shapes
            .where(isLibvisioSoftEdgesPlate),
        hasLength(1),
        reason: 'a second save must not stack another pie FillGradient plate',
      );

      final rounded = VsdxShapeFactory.roundedRectangle(
        id: 2,
        pinX: 5,
        pinY: 2,
        width: 2,
        height: 2,
        radius: 0.6,
        name: 'Round3',
        fill: const VsdxFill(pattern: 1, gradient: wash),
        line: const VsdxLine(pattern: 0),
      );
      var roundDoc = parser.parse(blank);
      roundDoc =
          roundDoc.replacePage(0, roundDoc.pages.first.addShape(rounded));
      final roundBaked = documentForLibvisioWrite(roundDoc);
      final roundPlate =
          roundBaked.pages.first.shapes.where(isLibvisioSoftEdgesPlate).single;
      final roundPng = roundBaked.images.findByPart(roundPlate.imagePartName!);
      final roundDecoded = raster.decodePng(roundPng!.bytes)!;
      final cut = pxAt(roundDecoded, x: 0.04, y: 0.04, width: 2, height: 2);
      final roundBow =
          pxAt(roundDecoded, x: 0.22, y: 0.22, width: 2, height: 2);
      expect(
        cut.r,
        greaterThan(240),
        reason:
            'rounded-rect corner must stay empty, not the Width×Height box; '
            'cut=$cut',
      );
      expect(
        cut.g,
        greaterThan(240),
        reason:
            'rounded-rect corner must stay empty, not the Width×Height box; '
            'cut=$cut',
      );
      expect(
        roundBow.a,
        greaterThan(200),
        reason: 'rounded-rect arc must fill past the chamfer octagon; '
            'bow=$roundBow',
      );
      expect(
        roundBow.g,
        lessThan(200),
        reason: 'rounded-rect arc must not be the white plate; bow=$roundBow',
      );

      final relPie = VsdxShape(
        id: 3,
        name: 'RelPie3',
        pinX: 2,
        pinY: 6,
        width: 2,
        height: 2,
        fill: const VsdxFill(pattern: 1, gradient: wash),
        line: const VsdxLine(pattern: 0),
        geometries: const <VsdxGeometry>[
          VsdxGeometry(
            commands: <VsdxPathCommand>[
              RelMoveTo(0.5, 0.5),
              RelLineTo(1, 0.5),
              RelEllipticalArcTo(fx: 0.5, fy: 1, fcx: 0.85, fcy: 0.85),
              RelLineTo(0.5, 0.5),
            ],
          ),
        ],
      );
      expect(shapeNeedsLibvisioGeometrySoftEdgesBake(relPie), isTrue);
      var relDoc = parser.parse(blank);
      relDoc = relDoc.replacePage(0, relDoc.pages.first.addShape(relPie));
      final relBaked = documentForLibvisioWrite(relDoc);
      final relPlate =
          relBaked.pages.first.shapes.where(isLibvisioSoftEdgesPlate).single;
      final relPng = relBaked.images.findByPart(relPlate.imagePartName!);
      final relDecoded = raster.decodePng(relPng!.bytes)!;
      final relBow = pxAt(relDecoded, x: 1.7, y: 1.7, width: 2, height: 2);
      expect(
        relBow.a,
        greaterThan(200),
        reason: 'RelEllipticalArcTo pie bow must bake, not skip the plate; '
            'bow=$relBow',
      );
      expect(
        relBow.r,
        lessThan(200),
        reason: 'RelEllipticalArcTo pie bow must keep the wash; bow=$relBow',
      );

      const twoStop = VsdxGradient(
        stops: <VsdxGradientStop>[
          VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
          VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
        ],
      );
      final two = VsdxShapeFactory.pie(
        id: 4,
        pinX: 5,
        pinY: 6,
        width: 2,
        height: 2,
        fill: const VsdxFill(pattern: 1, gradient: twoStop),
        line: const VsdxLine(pattern: 0),
      );
      expect(shapeNeedsLibvisioGeometrySoftEdgesBake(two), isFalse);
      var twoDoc = parser.parse(blank);
      twoDoc = twoDoc.replacePage(0, twoDoc.pages.first.addShape(two));
      expect(
        documentForLibvisioWrite(twoDoc)
            .pages
            .first
            .shapes
            .where(isLibvisioSoftEdgesPlate),
        isEmpty,
        reason:
            'two-colour pie FillGradient must stay classic FillPattern 25–40',
      );
    },
  );

  test(
    'multi-stop FillGradient even-odd compound keeps the hole for LibreOffice',
    () {
      const wash = VsdxGradient(
        stops: <VsdxGradientStop>[
          VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF00FF)),
          VsdxGradientStop(position: 0.5, color: VsdxColor(0xFF00FF00)),
          VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
        ],
      );
      raster.Pixel pxAt(
        raster.Image img, {
        required double x,
        required double y,
        required double width,
        required double height,
      }) {
        final ix =
            (x / width * (img.width - 1)).round().clamp(0, img.width - 1);
        final iy = ((1 - y / height) * (img.height - 1))
            .round()
            .clamp(0, img.height - 1);
        return img.getPixel(ix, iy);
      }

      VsdxShape frame(
        int id,
        VsdxFill fill, {
        VsdxLine line = const VsdxLine(pattern: 0),
      }) =>
          VsdxShape(
            id: id,
            name: 'EvenOdd',
            pinX: 4,
            pinY: 4,
            width: 3.2,
            height: 3.2,
            fill: fill,
            line: line,
            geometries: const <VsdxGeometry>[
              VsdxGeometry(
                commands: <VsdxPathCommand>[
                  MoveTo(0, 0),
                  LineTo(3.2, 0),
                  LineTo(3.2, 3.2),
                  LineTo(0, 3.2),
                  LineTo(0, 0),
                ],
              ),
              VsdxGeometry(
                commands: <VsdxPathCommand>[
                  MoveTo(0.7, 0.7),
                  LineTo(2.5, 0.7),
                  LineTo(2.5, 2.5),
                  LineTo(0.7, 2.5),
                  LineTo(0.7, 0.7),
                ],
              ),
            ],
          );

      final shape = frame(1, const VsdxFill(pattern: 1, gradient: wash));
      expect(shapeNeedsLibvisioGeometrySoftEdgesBake(shape), isTrue);

      final blank = writer.emptyDocument();
      var doc = parser.parse(blank);
      doc = doc.replacePage(0, doc.pages.first.addShape(shape));
      final baked = documentForLibvisioWrite(doc);
      expect(baked.pages.first.findShapeById(1)!.fill.pattern, 0);
      final plate =
          baked.pages.first.shapes.where(isLibvisioSoftEdgesPlate).single;
      final png = baked.images.findByPart(plate.imagePartName!);
      final decoded = raster.decodePng(png!.bytes)!;
      final hole = pxAt(decoded, x: 1.6, y: 1.6, width: 3.2, height: 3.2);
      final left = pxAt(decoded, x: 0.2, y: 1.6, width: 3.2, height: 3.2);
      final right = pxAt(decoded, x: 3.0, y: 1.6, width: 3.2, height: 3.2);
      final top = pxAt(decoded, x: 1.6, y: 3.0, width: 3.2, height: 3.2);
      expect(
        hole.r,
        greaterThan(240),
        reason: 'even-odd hole must stay white, not the outer wash; hole=$hole',
      );
      expect(
        hole.g,
        greaterThan(240),
        reason: 'even-odd hole must stay white, not the outer wash; hole=$hole',
      );
      expect(
        hole.b,
        greaterThan(240),
        reason: 'even-odd hole must stay white, not the outer wash; hole=$hole',
      );
      expect(
        left.r,
        greaterThan(left.g + 80),
        reason: 'left frame must keep magenta; left=$left',
      );
      expect(
        left.b,
        greaterThan(left.g + 80),
        reason: 'left frame must keep magenta; left=$left',
      );
      expect(
        right.b,
        greaterThan(right.r + 80),
        reason: 'right frame must keep blue; right=$right',
      );
      expect(
        top.g,
        greaterThan(top.r + 80),
        reason: 'top frame mid-stop must stay green; top=$top',
      );
      expect(
        documentForLibvisioWrite(baked)
            .pages
            .first
            .shapes
            .where(isLibvisioSoftEdgesPlate),
        hasLength(1),
        reason:
            'a second save must not stack another even-odd FillGradient plate',
      );

      const twoStop = VsdxGradient(
        stops: <VsdxGradientStop>[
          VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
          VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
        ],
      );
      final two = frame(2, const VsdxFill(pattern: 1, gradient: twoStop));
      expect(shapeNeedsLibvisioGeometrySoftEdgesBake(two), isFalse);
      var twoDoc = parser.parse(blank);
      twoDoc = twoDoc.replacePage(0, twoDoc.pages.first.addShape(two));
      expect(
        documentForLibvisioWrite(twoDoc)
            .pages
            .first
            .shapes
            .where(isLibvisioSoftEdgesPlate),
        isEmpty,
        reason:
            'two-colour even-odd FillGradient must stay classic FillPattern 25–40',
      );

      final both = frame(
        3,
        const VsdxFill(pattern: 1, gradient: wash),
        line: const VsdxLine(pattern: 1, weightInches: 0.12, gradient: wash),
      );
      expect(shapeNeedsLibvisioGeometrySoftEdgesBake(both), isTrue);
      var bothDoc = parser.parse(blank);
      bothDoc = bothDoc.replacePage(0, bothDoc.pages.first.addShape(both));
      final bothBaked = documentForLibvisioWrite(bothDoc);
      expect(bothBaked.pages.first.findShapeById(3)!.fill.pattern, 0);
      expect(bothBaked.pages.first.findShapeById(3)!.line.pattern, 0);
      final bothPlate =
          bothBaked.pages.first.shapes.where(isLibvisioSoftEdgesPlate).single;
      final bothPng = bothBaked.images.findByPart(bothPlate.imagePartName!);
      final bothDecoded = raster.decodePng(bothPng!.bytes)!;
      final bothHole = bothDecoded.getPixel(
        bothDecoded.width ~/ 2,
        bothDecoded.height ~/ 2,
      );
      expect(
        bothHole.r,
        greaterThan(240),
        reason: 'even-odd FillGradient+LineGradient PNG must keep the hole; '
            'hole=$bothHole',
      );
      expect(
        bothHole.g,
        greaterThan(240),
        reason: 'even-odd FillGradient+LineGradient PNG must keep the hole; '
            'hole=$bothHole',
      );
      expect(
        documentForLibvisioWrite(bothBaked)
            .pages
            .first
            .shapes
            .where(isLibvisioSoftEdgesPlate),
        hasLength(1),
        reason:
            'a second save must not stack another even-odd fill+stroke plate',
      );
    },
  );

  test(
    'multi-stop FillGradient CompoundType 2 keeps the fill for LibreOffice',
    () {
      const wash = VsdxGradient(
        stops: <VsdxGradientStop>[
          VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF00FF)),
          VsdxGradientStop(position: 0.5, color: VsdxColor(0xFF00FF00)),
          VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
        ],
      );
      final shape = VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 4.25,
        pinY: 5.5,
        width: 3.2,
        height: 1.8,
        name: 'Grad3Compound2',
        fill: const VsdxFill(pattern: 1, gradient: wash),
        line: const VsdxLine(
          color: VsdxColor.black,
          pattern: 1,
          weightInches: 0.2,
          compoundType: 2,
        ),
      );
      expect(shapeNeedsLibvisioGeometrySoftEdgesBake(shape), isTrue);

      final blank = writer.emptyDocument();
      var doc = parser.parse(blank);
      doc = doc.replacePage(0, doc.pages.first.addShape(shape));
      final baked = documentForLibvisioWrite(doc);
      final source = baked.pages.first.findShapeById(1)!;
      expect(source.fill.pattern, 0);
      expect(source.fill.hasGradient, isFalse);
      expect(
        source.geometries.every((g) => g.noFill),
        isTrue,
        reason: 'leftover NoFill=0 would let CompoundType 2 fill LineColor '
            'over the PNG plate',
      );
      final plate =
          baked.pages.first.shapes.where(isLibvisioSoftEdgesPlate).single;
      final png = baked.images.findByPart(plate.imagePartName!);
      expect(png, isNotNull);
      final decoded = raster.decodePng(png!.bytes)!;
      final mid = decoded.getPixel(decoded.width ~/ 2, decoded.height ~/ 2);
      expect(
        mid.g,
        greaterThan(mid.r + 80),
        reason: 'FillGradient middle stop must stay green; mid=$mid',
      );
      expect(
        mid.g,
        greaterThan(mid.b + 80),
        reason: 'FillGradient middle stop must stay green; mid=$mid',
      );

      final write = libvisioShapeWrite(source, theme: baked.theme);
      final fillable =
          write.geometries.where((g) => !g.noShow && !g.noFill).toList();
      expect(
        fillable,
        isNotEmpty,
        reason: 'CompoundType 2 must become filled thick-thin ribbons',
      );
      for (final geometry in fillable) {
        final pts = geometry.polylineVertices(
          widthInches: source.width,
          heightInches: source.height,
        );
        expect(pts, isNotNull);
        expect(
          pts!.length,
          greaterThan(6),
          reason: 'LineColor must not refill the Width×Height body; pts=$pts',
        );
      }

      expect(
        documentForLibvisioWrite(baked)
            .pages
            .first
            .shapes
            .where(isLibvisioSoftEdgesPlate),
        hasLength(1),
        reason: 'a second save must not stack another FillGradient plate',
      );

      const twoStop = VsdxGradient(
        stops: <VsdxGradientStop>[
          VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
          VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
        ],
      );
      final two = VsdxShapeFactory.rectangle(
        id: 2,
        pinX: 4.25,
        pinY: 5.5,
        width: 3.2,
        height: 1.8,
        name: 'Grad2Compound2',
        fill: const VsdxFill(pattern: 1, gradient: twoStop),
        line: const VsdxLine(
          color: VsdxColor.black,
          pattern: 1,
          weightInches: 0.2,
          compoundType: 2,
        ),
      );
      expect(shapeNeedsLibvisioGeometrySoftEdgesBake(two), isFalse);
      var twoDoc = parser.parse(blank);
      twoDoc = twoDoc.replacePage(0, twoDoc.pages.first.addShape(two));
      expect(
        documentForLibvisioWrite(twoDoc)
            .pages
            .first
            .shapes
            .where(isLibvisioSoftEdgesPlate),
        isEmpty,
        reason:
            'two-colour FillGradient CompoundType 2 must stay classic FillPattern 25–40',
      );
    },
  );

  test('multi-stop LineGradient bakes a PNG plate for LibreOffice', () {
    const wash = VsdxGradient(
      stops: <VsdxGradientStop>[
        VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF00FF)),
        VsdxGradientStop(position: 0.5, color: VsdxColor(0xFF00FF00)),
        VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
      ],
    );
    const line = VsdxLine(pattern: 1, weightInches: 0.16, gradient: wash);
    ({int mag, int green, int blue}) counts(raster.Image decoded) {
      var mag = 0, green = 0, blue = 0;
      for (final pixel in decoded) {
        if (pixel.a < 200) continue;
        if (pixel.r > 160 && pixel.g < 100 && pixel.b > 160) mag++;
        if (pixel.g > 160 && pixel.r < 100 && pixel.b < 100) green++;
        if (pixel.b > 160 && pixel.r < 100 && pixel.g < 100) blue++;
      }
      return (mag: mag, green: green, blue: blue);
    }

    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 1.2,
      name: 'LineGrad3',
      fill: const VsdxFill(pattern: 0),
      line: line,
    );
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.line.pattern, 0);
    expect(source.line.hasGradient, isFalse);
    final plate =
        baked.pages.first.shapes.where(isLibvisioSoftEdgesPlate).single;
    final png = baked.images.findByPart(plate.imagePartName!);
    expect(png, isNotNull);
    final ink = counts(raster.decodePng(png!.bytes)!);
    expect(ink.mag, greaterThan(20),
        reason: 'left stop must stay magenta; $ink');
    expect(ink.green, greaterThan(20),
        reason: 'middle stop must stay green; $ink');
    expect(ink.blue, greaterThan(20),
        reason: 'right stop must stay blue; $ink');
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioSoftEdgesPlate),
      hasLength(1),
      reason: 'a second save must not stack another LineGradient plate',
    );

    const twoStop = VsdxGradient(
      stops: <VsdxGradientStop>[
        VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
        VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
      ],
    );
    final two = VsdxShapeFactory.rectangle(
      id: 2,
      pinX: 5,
      pinY: 2,
      width: 2,
      height: 1.2,
      name: 'LineGrad2',
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 1, weightInches: 0.16, gradient: twoStop),
    );
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(two), isFalse);
    var twoDoc = parser.parse(blank);
    twoDoc = twoDoc.replacePage(0, twoDoc.pages.first.addShape(two));
    expect(
      documentForLibvisioWrite(twoDoc)
          .pages
          .first
          .shapes
          .where(isLibvisioSoftEdgesPlate),
      isEmpty,
      reason: 'two-colour LineGradient must stay a FillPattern 25–40 ribbon',
    );
    final twoSaved =
        parser.parse(writer.write(originalBytes: blank, edited: twoDoc));
    final twoShape = twoSaved.pages.first.findShapeById(2)!;
    expect(twoShape.line.hasGradient, isFalse);
    expect(
      twoShape.fill.hasGradient ||
          (twoShape.fill.pattern >= 25 && twoShape.fill.pattern <= 40),
      isTrue,
    );

    const fadedLineStops = VsdxGradient(
      stops: <VsdxGradientStop>[
        VsdxGradientStop(
          position: 0,
          color: VsdxColor(0xFFFF00FF),
          transparency: 0.65,
        ),
        VsdxGradientStop(
          position: 1,
          color: VsdxColor(0xFF0000FF),
          transparency: 0.65,
        ),
      ],
    );
    final fadedLine = VsdxShapeFactory.rectangle(
      id: 6,
      pinX: 2,
      pinY: 5,
      width: 2,
      height: 1.2,
      name: 'LineGrad2Fade',
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(
        pattern: 1,
        weightInches: 0.16,
        gradient: fadedLineStops,
      ),
    );
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(fadedLine), isTrue);
    var fadedLineDoc = parser.parse(blank);
    fadedLineDoc = fadedLineDoc.replacePage(
        0, fadedLineDoc.pages.first.addShape(fadedLine));
    final fadedLineBaked = documentForLibvisioWrite(fadedLineDoc);
    expect(fadedLineBaked.pages.first.findShapeById(6)!.line.pattern, 0);
    expect(
      fadedLineBaked.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
      hasLength(1),
    );
    expect(
      documentForLibvisioWrite(fadedLineBaked)
          .pages
          .first
          .shapes
          .where(isLibvisioSoftEdgesPlate),
      hasLength(1),
      reason: 'a second save must not stack another faded LineGradient plate',
    );

    const clearLineStops = VsdxGradient(
      stops: <VsdxGradientStop>[
        VsdxGradientStop(
          position: 0,
          color: VsdxColor(0xFFFF00FF),
          transparency: 1,
        ),
        VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
      ],
    );
    final clearLine = VsdxShapeFactory.rectangle(
      id: 7,
      pinX: 5,
      pinY: 5,
      width: 2,
      height: 1.2,
      name: 'LineGradClearStop',
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(
        pattern: 1,
        weightInches: 0.16,
        gradient: clearLineStops,
      ),
    );
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(clearLine), isTrue,
        reason:
            'a fully transparent LineGradient stop is not two 25–40 colours');
    var clearLineDoc = parser.parse(blank);
    clearLineDoc = clearLineDoc.replacePage(
      0,
      clearLineDoc.pages.first.addShape(clearLine),
    );
    final clearLineBaked = documentForLibvisioWrite(clearLineDoc);
    expect(clearLineBaked.pages.first.findShapeById(7)!.line.pattern, 0);
    expect(
      clearLineBaked.pages.first.shapes.where(isLibvisioSoftEdgesPlate),
      hasLength(1),
    );
    expect(
      documentForLibvisioWrite(clearLineBaked)
          .pages
          .first
          .shapes
          .where(isLibvisioSoftEdgesPlate),
      hasLength(1),
      reason:
          'a second save must not stack another clear-stop LineGradient plate',
    );

    final connector = VsdxShapeFactory.line(
      id: 3,
      ax: 1,
      ay: 1,
      bx: 4,
      by: 1,
      name: 'LineGrad3_1D',
      line: line,
    );
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(connector), isTrue);
    var oneDoc = parser.parse(blank);
    oneDoc = oneDoc.replacePage(0, oneDoc.pages.first.addShape(connector));
    final oneBaked = documentForLibvisioWrite(oneDoc);
    final oneSource = oneBaked.pages.first.findShapeById(3)!;
    expect(oneSource.is1D, isTrue);
    expect(oneSource.line.pattern, 0);
    expect(oneSource.line.hasGradient, isFalse);
    final onePlate =
        oneBaked.pages.first.shapes.where(isLibvisioSoftEdgesPlate).single;
    expect(onePlate.is1D, isFalse);
    expect(onePlate.height, greaterThan(0.1));
    final oneInk = counts(
      raster.decodePng(
        oneBaked.images.findByPart(onePlate.imagePartName!)!.bytes,
      )!,
    );
    expect(oneInk.green, greaterThan(8),
        reason: '1-D middle stop must stay green; $oneInk');

    final arrowed = VsdxShapeFactory.line(
      id: 4,
      ax: 1,
      ay: 2,
      bx: 4,
      by: 2,
      name: 'LineGrad3_Arrow',
      line: const VsdxLine(
        pattern: 1,
        weightInches: 0.12,
        beginArrow: 4,
        endArrow: 13,
        beginArrowSizeInches: 0.35,
        endArrowSizeInches: 0.35,
        gradient: wash,
      ),
    );
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(arrowed), isTrue);
    var arrowDoc = parser.parse(blank);
    arrowDoc = arrowDoc.replacePage(0, arrowDoc.pages.first.addShape(arrowed));
    final arrowBaked = documentForLibvisioWrite(arrowDoc);
    final arrowSource = arrowBaked.pages.first.findShapeById(4)!;
    expect(arrowSource.line.pattern, 0);
    expect(arrowSource.line.hasGradient, isFalse);
    expect(arrowSource.line.beginArrow, 0);
    expect(arrowSource.line.endArrow, 0);
    expect(
      arrowSource.geometries.where((g) => !g.noFill).length,
      0,
      reason: 'arrowed 3-stop LineGradient must not keep a 25–40 ribbon',
    );
    final arrowPlate =
        arrowBaked.pages.first.shapes.where(isLibvisioSoftEdgesPlate).single;
    expect(arrowPlate.is1D, isFalse);
    final arrowInk = counts(
      raster.decodePng(
        arrowBaked.images.findByPart(arrowPlate.imagePartName!)!.bytes,
      )!,
    );
    expect(arrowInk.mag, greaterThan(8),
        reason: 'arrowed 1-D left stop must stay magenta; $arrowInk');
    expect(arrowInk.green, greaterThan(8),
        reason: 'arrowed 1-D middle stop must stay green; $arrowInk');
    expect(arrowInk.blue, greaterThan(8),
        reason: 'arrowed 1-D right stop must stay blue; $arrowInk');
    expect(
      documentForLibvisioWrite(arrowBaked)
          .pages
          .first
          .shapes
          .where(isLibvisioSoftEdgesPlate),
      hasLength(1),
      reason: 'a second save must not stack another arrowed LineGradient plate',
    );

    final infinite = VsdxShape(
      id: 5,
      name: 'LineGrad3_Infinite',
      pinX: 4,
      pinY: 2,
      width: 4,
      height: 2,
      fill: const VsdxFill(pattern: 0),
      line: line,
      geometries: const <VsdxGeometry>[
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            InfiniteLineCmd(x: 0, y: 1, a: 4, b: 1),
          ],
        ),
      ],
    );
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(infinite), isTrue);
    var infDoc = parser.parse(blank);
    infDoc = infDoc.replacePage(0, infDoc.pages.first.addShape(infinite));
    final infBaked = documentForLibvisioWrite(infDoc);
    final infSource = infBaked.pages.first.findShapeById(5)!;
    expect(infSource.line.pattern, 0);
    expect(infSource.line.hasGradient, isFalse);
    final infPlate =
        infBaked.pages.first.shapes.where(isLibvisioSoftEdgesPlate).single;
    expect(infPlate.width, lessThan(6),
        reason:
            'InfiniteLine PNG must clip to the shape box, not a 900" sample');
    final infInk = counts(
      raster.decodePng(
        infBaked.images.findByPart(infPlate.imagePartName!)!.bytes,
      )!,
    );
    expect(infInk.mag, greaterThan(8),
        reason: 'InfiniteLine left stop must stay magenta; $infInk');
    expect(infInk.green, greaterThan(8),
        reason: 'InfiniteLine middle stop must stay green; $infInk');
    expect(infInk.blue, greaterThan(8),
        reason: 'InfiniteLine right stop must stay blue; $infInk');
    expect(
      documentForLibvisioWrite(infBaked)
          .pages
          .first
          .shapes
          .where(isLibvisioSoftEdgesPlate),
      hasLength(1),
      reason: 'a second save must not stack another InfiniteLine plate',
    );
  });

  test(
      'theme-only FillGradient SoftEdges bakes a feathered PNG for LibreOffice',
      () {
    const slot0 = ThemeSlot.accent6;
    const slot1 = ThemeSlot.accent1;
    final expected0 = VsdxTheme.office.resolve(slot0)!;
    final expected1 = VsdxTheme.office.resolve(slot1)!;
    const wash = VsdxGradient(
      stops: <VsdxGradientStop>[
        VsdxGradientStop(position: 0, themeColorIndex: slot0),
        VsdxGradientStop(position: 1, themeColorIndex: slot1),
      ],
    );
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.2,
      height: 0.8,
      name: 'GradientSoftTheme',
      fill: const VsdxFill(pattern: 1, gradient: wash),
      line: const VsdxLine(pattern: 0, softEdgesInches: 0.08),
    );
    expect(shape.fill.gradient!.stops.first.color, isNull);
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank).copyWith(theme: VsdxTheme.office);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.fill.pattern, 0);
    expect(source.fill.hasGradient, isFalse);
    expect(source.line.softEdgesInches, closeTo(0, 1e-9));
    final plate =
        baked.pages.first.shapes.where(isLibvisioSoftEdgesPlate).single;
    expect(plate.hasImage, isTrue);
    final decoded = raster.decodePng(
      baked.images.findByPart(plate.imagePartName!)!.bytes,
    )!;
    final left = decoded.getPixel(decoded.width ~/ 4, decoded.height ~/ 2);
    final right = decoded.getPixel(decoded.width * 3 ~/ 4, decoded.height ~/ 2);
    expect(
      left.g,
      greaterThan(left.r + 15),
      reason: 'theme slot $slot0 (${expected0.value.toRadixString(16)}) '
          'must freeze into the left of the feathered PNG; '
          'left=$left right=$right',
    );
    expect(
      right.b,
      greaterThan(right.r + 15),
      reason: 'theme slot $slot1 (${expected1.value.toRadixString(16)}) '
          'must freeze into the right of the feathered PNG; '
          'left=$left right=$right',
    );
    expect(
      decoded.getPixel(0, 0).a,
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

  test('hatch SoftEdges freezes theme-only FillBkgnd for LibreOffice', () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.2,
      height: 0.8,
      name: 'HatchSoftThemeBg',
      fill: const VsdxFill(
        foreground: VsdxColor(0xFFFF0000),
        themeBackgroundIndex: ThemeSlot.accent6,
        pattern: 6,
      ),
      line: const VsdxLine(pattern: 0, softEdgesInches: 0.08),
    );
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank).copyWith(theme: VsdxTheme.office);
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
    final expected = VsdxTheme.office.resolve(ThemeSlot.accent6)!;
    var redInk = 0;
    var themeInk = 0;
    final x = decoded.width ~/ 2;
    for (var y = decoded.height ~/ 4; y < decoded.height * 3 ~/ 4; y++) {
      final p = decoded.getPixel(x, y);
      if (p.a < 80) continue;
      if (p.r > p.g + 40) redInk++;
      if (p.g > p.r + 8 &&
          (p.g - expected.green).abs() < 40 &&
          (p.b - expected.blue).abs() < 40) {
        themeInk++;
      }
    }
    expect(
      redInk,
      greaterThan(2),
      reason: 'SoftEdges PNG must keep FillPattern 6 red strokes; '
          'redInk=$redInk themeInk=$themeInk',
    );
    expect(
      themeInk,
      greaterThan(redInk),
      reason: 'theme FillBkgnd must freeze into the hatch PNG, not stay '
          'transparent; redInk=$redInk themeInk=$themeInk',
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
  });

  test('hatch SoftEdges freezes theme-only FillForegnd for LibreOffice', () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.2,
      height: 0.8,
      name: 'HatchSoftThemeFg',
      fill: const VsdxFill(
        themeForegroundIndex: ThemeSlot.accent2,
        background: VsdxColor(0xFF0000FF),
        pattern: 6,
      ),
      line: const VsdxLine(pattern: 0, softEdgesInches: 0.08),
    );
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(shape), isTrue);
    expect(shape.fill.foreground, isNull);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank).copyWith(theme: VsdxTheme.office);
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
    final expected = VsdxTheme.office.resolve(ThemeSlot.accent2)!;
    var themeInk = 0;
    var blueInk = 0;
    final x = decoded.width ~/ 2;
    for (var y = decoded.height ~/ 4; y < decoded.height * 3 ~/ 4; y++) {
      final p = decoded.getPixel(x, y);
      if (p.a < 80) continue;
      if (p.b > p.r + 40) blueInk++;
      if (p.r > p.b + 20 &&
          (p.r - expected.red).abs() < 40 &&
          (p.g - expected.green).abs() < 40) {
        themeInk++;
      }
    }
    expect(
      themeInk,
      greaterThan(2),
      reason: 'SoftEdges PNG must freeze theme FillForegnd strokes; '
          'themeInk=$themeInk blueInk=$blueInk',
    );
    expect(
      blueInk,
      greaterThan(themeInk),
      reason: 'SoftEdges PNG must keep the blue hatch background; '
          'themeInk=$themeInk blueInk=$blueInk',
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
  });

  test('hatch FillForegndTrans freezes RGB LibreOffice can collect', () {
    const mag = VsdxColor(0xFFFF00FF);
    const white = VsdxColor.white;
    const blue = VsdxColor(0xFF0000FF);
    const faded = VsdxFill(
      foreground: mag,
      background: white,
      pattern: 6,
      foregroundTransparency: 0.5,
    );
    expect(fillNeedsLibvisioHatchTransBake(faded), isTrue);
    expect(
      shapeNeedsLibvisioGeometrySoftEdgesBake(
        VsdxShapeFactory.rectangle(
          id: 1,
          pinX: 2,
          pinY: 2,
          width: 1.2,
          height: 0.8,
          fill: faded,
          line: const VsdxLine(pattern: 0),
        ),
      ),
      isFalse,
      reason: 'hatch line trans is a cell freeze, not a SoftEdges PNG',
    );

    final overWhite = fillHatchTransForLibvisioWrite(faded);
    expect(overWhite.pattern, 6);
    expect(overWhite.foregroundTransparency, closeTo(0, 1e-9));
    expect(overWhite.backgroundTransparency, closeTo(0, 1e-9));
    expect(
      overWhite.foreground?.value,
      colourForLibvisioAlpha(mag, 0.5).value,
    );
    expect(overWhite.background?.value, white.value);
    expect(fillNeedsLibvisioHatchTransBake(overWhite), isFalse);

    final hollow = fillHatchTransForLibvisioWrite(
      const VsdxFill(
        foreground: mag,
        pattern: 6,
        foregroundTransparency: 0.5,
        backgroundTransparency: 1,
      ),
    );
    expect(hollow.pattern, 6);
    expect(hollow.foregroundTransparency, closeTo(0, 1e-9));
    expect(hollow.backgroundTransparency, closeTo(1, 1e-9));
    expect(hollow.foreground?.value, colourForLibvisioAlpha(mag, 0.5).value);

    final overBlue = fillHatchTransForLibvisioWrite(
      const VsdxFill(
        foreground: mag,
        background: blue,
        pattern: 6,
        foregroundTransparency: 0.5,
      ),
    );
    expect(overBlue.background?.value, blue.value);
    expect(overBlue.foreground?.red, 128);
    expect(overBlue.foreground?.green, 0);
    expect(overBlue.foreground?.blue, 255);

    expect(
      fillNeedsLibvisioHatchTransBake(
        const VsdxFill(foreground: mag, background: white, pattern: 6),
      ),
      isFalse,
      reason: 'opaque hatch stays native draw:fill=hatch',
    );
    expect(
      fillNeedsLibvisioHatchTransBake(
        const VsdxFill(
          foreground: mag,
          pattern: 6,
          backgroundTransparency: 1,
        ),
      ),
      isFalse,
      reason: 'hollow opaque strokes already map to hatch-solid=false',
    );

    const slot = ThemeSlot.accent2;
    final themeFg = fillHatchTransForLibvisioWrite(
      const VsdxFill(
        themeForegroundIndex: slot,
        background: white,
        pattern: 6,
        foregroundTransparency: 0.5,
      ),
      VsdxTheme.office,
    );
    expect(themeFg.themeForegroundIndex, isNull);
    expect(
      themeFg.foreground?.value,
      colourForLibvisioAlpha(VsdxTheme.office.resolve(slot)!, 0.5).value,
    );

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.rectangle(
          id: 1,
          pinX: 4.25,
          pinY: 5.5,
          width: 3,
          height: 2,
          name: 'HatchFade',
          fill: faded,
          line: const VsdxLine(pattern: 0),
        ),
      ),
    );
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.fill.pattern, 6);
    expect(source.fill.foregroundTransparency, closeTo(0, 1e-9));
    expect(
      source.fill.foreground?.value,
      colourForLibvisioAlpha(mag, 0.5).value,
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .findShapeById(1)!
          .fill
          .foreground
          ?.value,
      source.fill.foreground?.value,
      reason: 'a second save must not restack hatch FillForegndTrans',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    final after = savedDoc.pages.first.findShapeById(1)!;
    expect(after.fill.pattern, 6);
    expect(after.fill.foregroundTransparency, closeTo(0, 1e-9));
    expect(
      after.fill.foreground?.value,
      colourForLibvisioAlpha(mag, 0.5).value,
    );
    final savedAgain = writer.write(originalBytes: saved, edited: savedDoc);
    expect(
      parser
          .parse(savedAgain)
          .pages
          .first
          .findShapeById(1)!
          .fill
          .foreground
          ?.value,
      after.fill.foreground?.value,
      reason: 'a second save must not restack hatch FillForegndTrans',
    );
  });

  test('theme-only LineColorTrans freezes when a ribbon cannot bake', () {
    final shape = VsdxShape(
      id: 1,
      name: 'ThemeLineTrans',
      pinX: 1,
      pinY: 1,
      width: 1,
      height: 1,
      fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
      line: const VsdxLine(
        themeColorIndex: ThemeSlot.accent6,
        transparency: 0.7,
        weightInches: 0.08,
      ),
    );
    expect(shapeNeedsLibvisioFilledStrokeRibbonBake(shape), isFalse);
    final write = libvisioShapeWrite(shape, theme: VsdxTheme.office);
    expect(write.line.themeColorIndex, isNull);
    expect(write.line.transparency, closeTo(0, 1e-9));
    expect(
      write.line.color,
      colourForLibvisioAlpha(
        VsdxTheme.office.resolve(ThemeSlot.accent6)!,
        0.7,
      ),
    );
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

  test('theme-only LineGradient SoftEdges bakes the wash into the plate', () {
    const slot0 = ThemeSlot.accent6;
    const slot1 = ThemeSlot.accent1;
    const wash = VsdxGradient(
      stops: <VsdxGradientStop>[
        VsdxGradientStop(position: 0, themeColorIndex: slot0),
        VsdxGradientStop(position: 1, themeColorIndex: slot1),
      ],
    );
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 1.2,
      name: 'LineGradSoftTheme',
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(
        weightInches: 0.16,
        softEdgesInches: 0.12,
        gradient: wash,
      ),
    );
    expect(shape.line.color, isNull);
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank).copyWith(theme: VsdxTheme.office);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.line.pattern, 0);
    expect(source.line.hasGradient, isFalse);
    expect(source.line.softEdgesInches, closeTo(0, 1e-9));
    final plate =
        baked.pages.first.shapes.where(isLibvisioSoftEdgesPlate).single;
    final decoded = raster.decodePng(
      baked.images.findByPart(plate.imagePartName!)!.bytes,
    )!;
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
    expect(
      left.g,
      greaterThan(left.r + 15),
      reason: 'theme-only LineGradient SoftEdges PNG must keep the green '
          'start of the wash; left=$left right=$right',
    );
    expect(
      right.b,
      greaterThan(right.r + 15),
      reason: 'theme-only LineGradient SoftEdges PNG must keep the blue '
          'end of the wash; left=$left right=$right',
    );
  });

  test('theme-only LineGradient bakes a themed ribbon for LibreOffice', () {
    const slot0 = ThemeSlot.accent6;
    const slot1 = ThemeSlot.accent1;
    final shape = VsdxShape(
      id: 1,
      name: 'LineGradTheme',
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 0.2,
      geometries: const <VsdxGeometry>[
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[MoveTo(0, 0.1), LineTo(2, 0.1)],
        ),
      ],
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(
        pattern: 1,
        weightInches: 0.06,
        gradient: VsdxGradient(
          stops: <VsdxGradientStop>[
            VsdxGradientStop(position: 0, themeColorIndex: slot0),
            VsdxGradientStop(position: 1, themeColorIndex: slot1),
          ],
        ),
      ),
    );
    expect(shape.line.color, isNull);
    expect(shapeNeedsLibvisioStrokeRibbon(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank).copyWith(theme: VsdxTheme.office);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final saved = writer.write(originalBytes: blank, edited: doc);
    final after = parser.parse(saved).pages.first.findShapeById(1)!;
    expect(after.line.hasGradient, isFalse);
    expect(after.line.pattern, 0);
    expect(
      after.fill.themeForegroundIndex == slot0 ||
          after.fill.foreground?.value ==
              VsdxTheme.office.resolve(slot0)!.value,
      isTrue,
      reason: 'theme-only LineGradient must not bake a black ribbon; '
          'fill=${after.fill.foreground} theme=${after.fill.themeForegroundIndex}',
    );
    expect(
      after.fill.themeBackgroundIndex == slot1 ||
          after.fill.background?.value ==
              VsdxTheme.office.resolve(slot1)!.value,
      isTrue,
      reason: 'the ribbon FillBkgnd must keep the last stop slot',
    );
    expect(
      after.fill.hasGradient ||
          (after.fill.pattern >= 25 && after.fill.pattern <= 40),
      isTrue,
      reason: 'LineGradient ribbon must become a classic FillPattern',
    );
    expect(after.geometries.any((g) => !g.noFill), isTrue);

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
        reason:
            'open-path arrows stay native so crisp heads are not in the PNG');
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

  test('theme-only ShadowBlur bakes a Gaussian PNG for LibreOffice', () {
    const slot = ThemeSlot.accent2;
    final expected = VsdxTheme.office.resolve(slot)!;
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.2,
      height: 0.8,
      name: 'ShadowTheme',
      fill: const VsdxFill(foreground: VsdxColor(0xFFEEEEEE), pattern: 1),
      line: const VsdxLine(pattern: 0),
    ).copyWith(
      shadow: const VsdxShadow(
        enabled: true,
        themeColorIndex: slot,
        offsetXInches: 0.2,
        offsetYInches: -0.15,
        blurInches: 0.08,
        transparency: 0.2,
      ),
    );
    expect(shapeNeedsLibvisioShadowBake(shape), isTrue);
    expect(
      shapeNeedsLibvisioShadowBake(
        shape.copyWith(shadow: shape.shadow.copyWith(blurInches: 0)),
      ),
      isFalse,
      reason: 'hard theme-only shadows stay native; opaque ones keep THEMEVAL',
    );

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank).copyWith(theme: VsdxTheme.office);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.shadow.enabled, isFalse);
    expect(source.shadow.blurInches, closeTo(0, 1e-9));
    expect(source.shadow.themeColorIndex, slot);
    expect(source.fill.pattern, 1, reason: 'shadow bake keeps the source fill');
    final plates = baked.pages.first.shapes.where(isLibvisioShadowPlate);
    expect(plates, hasLength(1));
    final plate = plates.single;
    expect(plate.locked, isTrue);
    expect(plate.hasImage, isTrue);
    final png = baked.images.findByPart(plate.imagePartName!);
    expect(png, isNotNull);
    final decoded = raster.decodePng(png!.bytes);
    expect(decoded, isNotNull);
    var ink = 0;
    for (var y = 0; y < decoded!.height; y++) {
      for (var x = 0; x < decoded.width; x++) {
        final pixel = decoded.getPixel(x, y);
        if (pixel.a > 20 && pixel.r > pixel.b + 20 && pixel.r > pixel.g + 10) {
          ink++;
        }
      }
    }
    expect(ink, greaterThan(8),
        reason: 'theme slot $slot (${expected.value.toRadixString(16)}) '
            'must freeze into the Gaussian PNG, not a hard draw:shadow');
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioShadowPlate),
      hasLength(1),
      reason: 'a second save must not stack another Shadow plate',
    );
  });

  test('theme-only hard ShdwForegndTrans bakes RGB for LibreOffice', () {
    const slot = ThemeSlot.accent6;
    const trans = 0.7;
    final expected = colourForLibvisioAlpha(
      VsdxTheme.office.resolve(slot)!,
      trans,
    );
    const shadow = VsdxShadow(
      enabled: true,
      themeColorIndex: slot,
      offsetXInches: 0.4,
      offsetYInches: -0.35,
      blurInches: 0,
      transparency: trans,
    );
    expect(shadow.color, isNull);
    expect(shadowForLibvisioWrite(shadow).color?.value, expected.value);
    expect(shadowForLibvisioWrite(shadow).transparency, 0);
    expect(shadowForLibvisioWrite(shadow).themeColorIndex, isNull);
    expect(
      shadowForLibvisioWrite(
        shadow.copyWith(transparency: 0),
      ).themeColorIndex,
      slot,
      reason: 'opaque theme ShdwForegnd still keeps THEMEVAL',
    );
    expect(
      shadowForLibvisioWrite(
        shadow.copyWith(blurInches: 0.08),
      ).themeColorIndex,
      slot,
      reason: 'soft theme leftovers keep THEMEVAL after the PNG bake',
    );

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank).copyWith(theme: VsdxTheme.office);
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4.25,
      pinY: 5.5,
      width: 3,
      height: 2,
      name: 'ShadowTransTheme',
      fill: const VsdxFill(foreground: VsdxColor(0xFFEEEEEE), pattern: 1),
      line: const VsdxLine(pattern: 0),
    ).copyWith(shadow: shadow);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final saved = writer.write(originalBytes: blank, edited: doc);
    final xml = VsdxPackage.open(saved)
        .readPartXml('/visio/pages/page1.xml')!
        .toXmlString();
    expect(xml.contains('N="ShdwForegndTrans" V="0.7"'), isFalse);
    final hex = (expected.value & 0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0')
        .toUpperCase();
    expect(
      xml.contains('N="ShdwForegnd" V="#$hex"'),
      isTrue,
      reason: 'theme ShdwForegndTrans must freeze into hex, not THEMEVAL; '
          'expected=#$hex',
    );
    final after = parser.parse(saved).pages.first.findShapeById(1)!;
    expect(after.shadow.enabled, isTrue);
    expect(after.shadow.color?.value, expected.value);
    expect(after.shadow.themeColorIndex, isNull);
    expect(after.shadow.transparency, closeTo(0, 1e-9));
    expect(after.shadow.blurInches, closeTo(0, 1e-9));
    expect(
      parser.parse(saved).pages.first.shapes.where(isLibvisioShadowPlate),
      isEmpty,
    );
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

  test('theme-only page oblique shadow bakes a sheared sibling for LibreOffice',
      () {
    const slot = ThemeSlot.accent2;
    final expected = VsdxTheme.office.resolve(slot)!;
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 3,
      pinY: 3,
      width: 1.4,
      height: 0.8,
      name: 'ObliqueShadowTheme',
      fill: const VsdxFill(foreground: VsdxColor(0xFFEEEEEE), pattern: 1),
      line: const VsdxLine(pattern: 0),
    ).copyWith(
      shadow: const VsdxShadow(
        enabled: true,
        themeColorIndex: slot,
        offsetXInches: 0.2,
        offsetYInches: -0.15,
        blurInches: 0,
        transparency: 0.4,
      ),
    );
    expect(shape.shadow.color, isNull);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank).copyWith(theme: VsdxTheme.office);
    final obliquePage = doc.pages.first.addShape(shape).copyWith(
          pageSheet: doc.pages.first.pageSheet.copyWith(
            shadowType: 1,
            shadowObliqueAngle: 0.5,
            shadowScaleFactor: 1.2,
          ),
        );
    expect(shapeNeedsLibvisioPageShadowBake(shape, obliquePage), isTrue);
    expect(
      shapeNeedsLibvisioPageShadowBake(
        shape.copyWith(shadow: shape.shadow.copyWith(blurInches: 0.08)),
        obliquePage,
      ),
      isFalse,
      reason: 'a blurred theme shadow keeps the Gaussian PNG path',
    );

    doc = doc.replacePage(0, obliquePage);
    final baked = documentForLibvisioWrite(doc);
    final plate =
        baked.pages.first.shapes.where(isLibvisioPageShadowPlate).single;
    expect(plate.locked, isTrue);
    expect(plate.fill.pattern, 1);
    expect(plate.fill.foreground?.value, expected.value,
        reason: 'theme slot $slot must freeze into FillForegnd');
    expect(plate.fill.foregroundTransparency, closeTo(0.4, 1e-9));
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.shadow.enabled, isFalse);
    expect(source.shadow.themeColorIndex, slot);
    expect(
      baked.pages.first.shapes.indexOf(plate),
      lessThan(baked.pages.first.shapes.indexOf(source)),
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

  test('picture hard shadow bakes a silhouette PNG sibling for LibreOffice',
      () {
    const part = '/visio/media/hard_shadow.png';
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
      name: 'HardShadowPicture',
    ).copyWith(
      shadow: const VsdxShadow(
        enabled: true,
        color: VsdxColor(0xFF000000),
        offsetXInches: 0.2,
        offsetYInches: -0.15,
        blurInches: 0,
        transparency: 0.4,
        pattern: 1,
      ),
    );
    expect(shapeNeedsLibvisioShadowBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.copyWith(images: doc.images.withImage(sourceImage));
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.shadow.enabled, isFalse,
        reason: 'Foreign pictures cannot collect draw:shadow');
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
    final png = baked.images.findByPart(plate.imagePartName!);
    expect(png, isNotNull);
    final decoded = raster.decodePng(png!.bytes);
    expect(decoded, isNotNull);
    final cx = decoded!.width ~/ 2;
    final cy = decoded.height ~/ 2;
    expect(decoded.getPixel(cx, cy).a, greaterThan(80));
    expect(
      decoded.getPixel(0, cy).a,
      lessThan(10),
      reason: 'hard picture shadow must not Gaussian-spread into the pad',
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

  test('Curved Text bakes per-glyph siblings past tab fields', () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4,
      pinY: 5,
      width: 1.0,
      height: 3.0,
      name: 'ArcTab',
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
    ).withCurvedText(true).copyWith(
          richText: const VsdxRichText(
            tabSets: <VsdxTabSet>[
              VsdxTabSet(
                ix: 0,
                stops: <VsdxTabStop>[VsdxTabStop(positionInches: 2)],
              ),
            ],
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'A\tC',
                tabIndices: <int>[0],
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
    expect(shapeNeedsLibvisioCurvedTextBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final plates =
        baked.pages.first.shapes.where(isLibvisioCurvedTextPlate).toList()
          ..sort(
            (a, b) => int.parse(a.name.split('.')[1])
                .compareTo(int.parse(b.name.split('.')[1])),
          );
    expect(plates, hasLength(2));
    expect(plates.map((p) => p.richText.plainText).join(), 'AC');
    expect(plates.every((p) => !p.richText.plainText.contains('\t')), isTrue);
    expect(baked.pages.first.findShapeById(1)!.curvedText, isFalse);
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioCurvedTextPlate),
      hasLength(2),
      reason: 'a second save must not stack another Curved Text plate',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    expect(
      parser.parse(saved).pages.first.shapes.where(isLibvisioCurvedTextPlate),
      hasLength(2),
    );
  });

  test('Curved Text keeps Overline combining marks on each glyph', () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4,
      pinY: 5,
      width: 1.0,
      height: 3.0,
      name: 'ArcOverline',
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
    ).withCurvedText(true).copyWith(
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'ARC',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 0.4,
                  overline: true,
                  color: VsdxColor(0xFF000000),
                ),
                paraStyle: VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.center,
                ),
              ),
            ],
          ),
        );
    expect(shapeNeedsLibvisioOverlineBake(shape), isTrue);
    expect(shapeNeedsLibvisioCurvedTextBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final plates =
        baked.pages.first.shapes.where(isLibvisioCurvedTextPlate).toList()
          ..sort(
            (a, b) => int.parse(a.name.split('.')[1])
                .compareTo(int.parse(b.name.split('.')[1])),
          );
    expect(plates, hasLength(3),
        reason: 'U+0305 must ride on A/R/C, not become orphan plates');
    expect(
      plates
          .map((p) =>
              p.richText.plainText.replaceAll(kLibvisioCombiningOverline, ''))
          .join(),
      'ARC',
    );
    expect(
      plates.every(
          (p) => p.richText.plainText.contains(kLibvisioCombiningOverline)),
      isTrue,
    );
    expect(
      plates.every((p) => !p.richText.runs.single.charStyle.overline),
      isTrue,
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    expect(
      parser.parse(saved).pages.first.shapes.where(isLibvisioCurvedTextPlate),
      hasLength(3),
    );
  });

  test('Curved Text keeps a leading U+200F on the first glyph', () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4,
      pinY: 5,
      width: 1.0,
      height: 3.0,
      name: 'ArcRtl',
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
    ).withCurvedText(true).copyWith(
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: '123',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 0.4,
                  langId: 'ar-SA',
                  color: VsdxColor(0xFF000000),
                ),
                paraStyle: VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.center,
                ),
              ),
            ],
          ),
        );
    expect(shapeNeedsLibvisioLangIdRtlBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final plates =
        baked.pages.first.shapes.where(isLibvisioCurvedTextPlate).toList()
          ..sort(
            (a, b) => int.parse(a.name.split('.')[1])
                .compareTo(int.parse(b.name.split('.')[1])),
          );
    expect(plates, hasLength(3),
        reason: 'U+200F must ride on the first digit, not become a plate');
    expect(plates.first.richText.plainText, startsWith(kLibvisioRtlMark));
    expect(
      plates
          .map((p) => p.richText.plainText.replaceAll(kLibvisioRtlMark, ''))
          .join(),
      '123',
    );
  });

  test('Curved Text bakes mixed Character Highlight onto glyph plates', () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4,
      pinY: 5,
      width: 1.0,
      height: 3.0,
      name: 'ArcHighlight',
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
    ).withCurvedText(true).copyWith(
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'A',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 0.4,
                  color: VsdxColor(0xFF000000),
                  highlight: VsdxColor(0xFFFF00FF),
                ),
                paraStyle: VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.center,
                ),
              ),
              VsdxTextRun(
                text: 'RC',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 0.4,
                  color: VsdxColor(0xFF000000),
                  highlight: VsdxColor(0xFF00FF00),
                ),
                paraStyle: VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.center,
                ),
              ),
            ],
          ),
        );
    expect(shapeNeedsLibvisioCurvedTextBake(shape), isTrue);
    expect(shapeNeedsLibvisioMixedHighlightBake(shape), isFalse);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.curvedText, isFalse);
    expect(source.richText.textBlock.hideText, isTrue);
    expect(baked.pages.first.shapes.where(isLibvisioHighlightPlate), isEmpty);
    final plates =
        baked.pages.first.shapes.where(isLibvisioCurvedTextPlate).toList()
          ..sort(
            (a, b) => int.parse(a.name.split('.')[1])
                .compareTo(int.parse(b.name.split('.')[1])),
          );
    expect(plates, hasLength(3));
    expect(plates.map((p) => p.richText.plainText).join(), 'ARC');
    expect(plates[0].fill.pattern, 1);
    expect(plates[0].fill.foreground?.value, 0xFFFF00FF);
    expect(plates[1].fill.pattern, 1);
    expect(plates[1].fill.foreground?.value, 0xFF00FF00);
    expect(plates[2].fill.foreground?.value, 0xFF00FF00);
    expect(
      plates.every((p) => p.richText.runs.single.charStyle.highlight == null),
      isTrue,
    );
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
    expect(
      parser.parse(saved).pages.first.shapes.where(isLibvisioCurvedTextPlate),
      hasLength(3),
    );
  });

  test('Curved Text bakes bullet glyphs onto glyph plates', () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4,
      pinY: 5,
      width: 1.0,
      height: 3.0,
      name: 'ArcBullet',
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
    ).withCurvedText(true).copyWith(
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
                  bullet: 3,
                ),
              ),
            ],
          ),
        );
    expect(shapeNeedsLibvisioBulletGlyphBake(shape), isTrue);
    expect(shapeNeedsLibvisioCurvedTextBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.curvedText, isFalse);
    expect(source.richText.textBlock.hideText, isTrue);
    expect(source.richText.runs.single.paraStyle.bullet, 0);
    expect(source.richText.runs.single.paraStyle.indentFirstInches, 0);
    expect(source.richText.runs.single.paraStyle.indentLeftInches, 0);
    final plates =
        baked.pages.first.shapes.where(isLibvisioCurvedTextPlate).toList()
          ..sort(
            (a, b) => int.parse(a.name.split('.')[1])
                .compareTo(int.parse(b.name.split('.')[1])),
          );
    expect(
      plates.map((p) => p.richText.plainText).join(),
      '\u25a0ARC',
      reason: 'Draw never paints text:bullet-char; the glyph rides the arc',
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioCurvedTextPlate)
          .length,
      plates.length,
      reason: 'a second save must not stack another Curved Text plate',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    expect(
      parser
          .parse(saved)
          .pages
          .first
          .shapes
          .where(isLibvisioCurvedTextPlate)
          .map((p) => p.richText.plainText)
          .join(),
      '\u25a0ARC',
    );
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

  test('Shape Inside bakes per-line siblings past tab fields', () {
    final shape = VsdxShapeFactory.ellipse(
      id: 1,
      pinX: 4,
      pinY: 5,
      width: 3,
      height: 4,
      name: 'OvalTab',
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
    ).withShapeInside(true).copyWith(
          richText: const VsdxRichText(
            tabSets: <VsdxTabSet>[
              VsdxTabSet(
                ix: 0,
                stops: <VsdxTabStop>[VsdxTabStop(positionInches: 2)],
              ),
            ],
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'SHAPE\tINSIDE FLOW ALONG THE ELLIPSE',
                tabIndices: <int>[0],
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
    expect(shape.supportsShapeInside, isTrue);
    expect(shapeNeedsLibvisioShapeInsideBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final plates =
        baked.pages.first.shapes.where(isLibvisioShapeInsidePlate).toList();
    expect(plates, isNotEmpty);
    expect(
      plates.every((p) => !p.richText.plainText.contains('\t')),
      isTrue,
    );
    expect(baked.pages.first.findShapeById(1)!.shapeInside, isFalse);
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioShapeInsidePlate)
          .length,
      plates.length,
      reason: 'a second save must not stack another Shape Inside plate',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    expect(
        parser.parse(saved).pages.first.findShapeById(1)!.shapeInside, isFalse);
    expect(
      parser.parse(saved).pages.first.shapes.where(isLibvisioShapeInsidePlate),
      hasLength(plates.length),
    );
  });

  test('Shape Inside bakes per-line siblings past field spans', () {
    final shape = VsdxShapeFactory.ellipse(
      id: 1,
      pinX: 4,
      pinY: 5,
      width: 3,
      height: 4,
      name: 'OvalField',
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
    ).withShapeInside(true).copyWith(
          text: '42 SHAPE INSIDE FLOW ALONG THE ELLIPSE',
          fields: const <VsdxFieldRow>[
            VsdxFieldRow(
              ix: 0,
              value: '42',
              valueFormula: 'PAGENUMBER()',
            ),
          ],
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: '42 SHAPE INSIDE FLOW ALONG THE ELLIPSE',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 0.22,
                  color: VsdxColor(0xFF000000),
                ),
                paraStyle: VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.center,
                ),
                fieldSpans: <VsdxFieldSpan>[
                  VsdxFieldSpan(start: 0, length: 2, ix: 0),
                ],
              ),
            ],
            textBlock: VsdxTextBlock(
              verticalAlign: VsdxVertAlign.top,
            ),
          ),
        );
    expect(shape.supportsShapeInside, isTrue);
    expect(shapeNeedsLibvisioShapeInsideBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.shapeInside, isFalse);
    expect(source.richText.textBlock.hideText, isTrue);
    final plates =
        baked.pages.first.shapes.where(isLibvisioShapeInsidePlate).toList();
    expect(plates, isNotEmpty);
    expect(
      plates.map((p) => p.richText.plainText).join(),
      contains('42'),
      reason:
          'Draw never paints a rectangular <fld>; the Value is on the plate',
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioShapeInsidePlate)
          .length,
      plates.length,
      reason: 'a second save must not stack another Shape Inside plate',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final after = parser.parse(saved).pages.first;
    expect(after.findShapeById(1)!.shapeInside, isFalse);
    expect(after.findShapeById(1)!.richText.textBlock.hideText, isTrue);
    expect(
      after.shapes
          .where(isLibvisioShapeInsidePlate)
          .map((p) => p.richText.plainText)
          .join(),
      contains('42'),
    );
  });

  test('Shape Inside bakes bullet glyphs onto line plates', () {
    final shape = VsdxShapeFactory.ellipse(
      id: 1,
      pinX: 4,
      pinY: 5,
      width: 3,
      height: 4,
      name: 'OvalBullet',
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
    ).withShapeInside(true).copyWith(
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
                  bullet: 3,
                ),
              ),
            ],
            textBlock: VsdxTextBlock(
              verticalAlign: VsdxVertAlign.top,
            ),
          ),
        );
    expect(shapeNeedsLibvisioBulletGlyphBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.shapeInside, isFalse);
    expect(source.richText.textBlock.hideText, isTrue);
    expect(source.richText.runs.single.paraStyle.bullet, 0);
    expect(source.richText.runs.single.paraStyle.indentFirstInches, 0);
    expect(source.richText.runs.single.paraStyle.indentLeftInches, 0);
    final plates =
        baked.pages.first.shapes.where(isLibvisioShapeInsidePlate).toList();
    expect(plates, isNotEmpty);
    expect(
      plates.map((p) => p.richText.plainText).join(),
      contains('\u25a0'),
      reason: 'Draw never paints text:bullet-char; the glyph is on the plate',
    );
    expect(
      plates.map((p) => p.richText.plainText).join().replaceAll(' ', ''),
      contains('SHAPEINSIDEFLOW'),
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioShapeInsidePlate)
          .length,
      plates.length,
      reason: 'a second save must not stack another Shape Inside plate',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final after = parser.parse(saved).pages.first;
    expect(after.findShapeById(1)!.shapeInside, isFalse);
    expect(
      after.shapes
          .where(isLibvisioShapeInsidePlate)
          .map((p) => p.richText.plainText)
          .join(),
      contains('\u25a0'),
    );
  });

  test('Shape Inside bakes mixed Character Highlight onto line plates', () {
    final shape = VsdxShapeFactory.ellipse(
      id: 1,
      pinX: 4,
      pinY: 5,
      width: 3,
      height: 4,
      name: 'OvalHighlight',
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
    ).withShapeInside(true).copyWith(
          richText: const VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'HI ',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 0.22,
                  color: VsdxColor(0xFF000000),
                  highlight: VsdxColor(0xFFFF00FF),
                ),
                paraStyle: VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.center,
                ),
              ),
              VsdxTextRun(
                text: 'SHAPE INSIDE FLOW ALONG THE ELLIPSE',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 0.22,
                  color: VsdxColor(0xFF000000),
                  highlight: VsdxColor(0xFF00FF00),
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
    expect(shape.supportsShapeInside, isTrue);
    expect(shapeNeedsLibvisioShapeInsideBake(shape), isTrue);
    expect(shapeNeedsLibvisioMixedHighlightBake(shape), isFalse);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.shapeInside, isFalse);
    expect(source.richText.textBlock.hideText, isTrue);
    expect(baked.pages.first.shapes.where(isLibvisioHighlightPlate), isEmpty);
    final plates =
        baked.pages.first.shapes.where(isLibvisioShapeInsidePlate).toList();
    expect(plates, isNotEmpty);
    expect(
      plates.any((p) => p.fill.foreground?.value == 0xFFFF00FF),
      isTrue,
    );
    expect(
      plates.any((p) => p.fill.foreground?.value == 0xFF00FF00),
      isTrue,
    );
    expect(
      plates.map((p) => p.richText.plainText).join().replaceAll(' ', ''),
      'HISHAPEINSIDEFLOWALONGTHEELLIPSE',
    );
    expect(
      plates.every((p) => p.richText.runs.single.charStyle.highlight == null),
      isTrue,
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioShapeInsidePlate)
          .length,
      plates.length,
      reason: 'a second save must not stack another Shape Inside plate',
    );
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

  test('loose connector labels bake TxtPin on the route midpoint', () {
    const label = VsdxRichText(
      runs: <VsdxTextRun>[
        VsdxTextRun(
          text: 'MMM',
          charStyle: VsdxCharStyle(
            fontFamily: 'Arial',
            fontSizeInches: 0.4,
            color: VsdxColor(0xFF000000),
          ),
        ),
      ],
    );
    final elbow = VsdxShapeFactory.line(
      id: 1,
      ax: 1,
      ay: 7,
      bx: 7,
      by: 1,
      name: 'EdgeLabel',
    ).copyWith(
      geometries: const <VsdxGeometry>[
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(0, 0),
            LineTo(6, 0),
            LineTo(6, -6),
          ],
        ),
      ],
      richText: label,
    );
    expect(shapeNeedsLibvisioLooseEdgeLabelBake(elbow), isTrue);
    expect(
      shapeNeedsLibvisioLooseEdgeLabelBake(
        VsdxShapeFactory.rectangle(
          id: 9,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
        ).copyWith(richText: label),
      ),
      isFalse,
    );
    expect(
      shapeNeedsLibvisioLooseEdgeLabelBake(
        elbow.copyWith(
          richText: label.copyWith(
            textBlock: const VsdxTextBlock(pinXInches: 1, pinYInches: 1),
          ),
        ),
      ),
      isFalse,
      reason: 'an authored TxtPin must stay native',
    );
    final wide = elbow.copyWith(
      richText: label.copyWith(
        textBlock: const VsdxTextBlock(
          widthInches: 6,
          heightInches: 1.2,
        ),
      ),
    );
    expect(
      shapeNeedsLibvisioLooseEdgeLabelBake(wide),
      isTrue,
      reason: 'TxtWidth without TxtPin still builds m_txtxform at pin 0',
    );

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(elbow));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    final route = baked.pages.first.drawnConnectorPagePolyline(source);
    expect(route.length, greaterThanOrEqualTo(3));
    expect(source.richText.textBlock.pinXInches, isNotNull);
    expect(source.richText.textBlock.pinYInches, isNotNull);
    final pagePin = baked.pages.first.localToPageDeep(
      source.id,
      Offset2D(
        source.richText.textBlock.pinXInches!,
        source.richText.textBlock.pinYInches!,
      ),
    );
    // Route midpoint is the elbow (7, 7), not the Begin–End centre (4, 4).
    expect(pagePin.x, closeTo(7, 0.2));
    expect(pagePin.y, closeTo(7, 0.2));
    expect(source.richText.textBlock.widthInches, greaterThan(0.5));
    expect(source.richText.textBlock.heightInches, greaterThan(0.2));
    expect(source.richText.textBlock.angleRad, closeTo(0, 1e-9));
    expect(
      shapeNeedsLibvisioLooseEdgeLabelBake(
        documentForLibvisioWrite(baked).pages.first.findShapeById(1)!,
      ),
      isFalse,
      reason: 'a second save must not move TxtPin again',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    final after = savedDoc.pages.first.findShapeById(1)!;
    expect(after.richText.textBlock.pinXInches, isNotNull);
    final savedPin = savedDoc.pages.first.localToPageDeep(
      after.id,
      Offset2D(
        after.richText.textBlock.pinXInches!,
        after.richText.textBlock.pinYInches!,
      ),
    );
    expect(savedPin.x, closeTo(7, 0.2));
    expect(savedPin.y, closeTo(7, 0.2));

    var wideDoc = parser.parse(blank);
    wideDoc = wideDoc.replacePage(0, wideDoc.pages.first.addShape(wide));
    final wideBaked = documentForLibvisioWrite(wideDoc);
    final wideSource = wideBaked.pages.first.findShapeById(1)!;
    expect(wideSource.richText.textBlock.pinXInches, isNotNull);
    expect(wideSource.richText.textBlock.widthInches, lessThan(2.5));
    expect(wideSource.richText.textBlock.widthInches, greaterThan(0.5));
    final widePin = wideBaked.pages.first.localToPageDeep(
      wideSource.id,
      Offset2D(
        wideSource.richText.textBlock.pinXInches!,
        wideSource.richText.textBlock.pinYInches!,
      ),
    );
    expect(widePin.x, closeTo(7, 0.2));
    expect(widePin.y, closeTo(7, 0.2));

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

  test('EnhMetaFile DIB bakes to PNG Bitmap for LibreOffice', () {
    const part = '/visio/media/probe.emf';
    final emf = _rgbDibEmf(width: 32, height: 16);
    final source = VsdxImage(
      partName: part,
      bytes: emf,
      mimeType: 'image/x-emf',
    );
    expect(source.foreignType, 'EnhMetaFile');
    expect(source.rasterForRendering(), isNotNull);
    final pic = VsdxShapeFactory.picture(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 1,
      imagePartName: part,
    );
    expect(shapeNeedsLibvisioMetafileBitmapBake(pic), isTrue);

    var doc = parser.parse(writer.emptyDocument());
    doc = doc
        .copyWith(images: doc.images.withImage(source))
        .replacePage(0, doc.pages.first.addShape(pic));
    final baked = documentForLibvisioWrite(doc);
    final bakedShape = baked.pages.first.findShapeById(1)!;
    expect(shapeNeedsLibvisioMetafileBitmapBake(bakedShape), isFalse);
    expect(bakedShape.foreignType, 'Bitmap');
    expect(bakedShape.foreignCompressionType, 'PNG');
    expect(bakedShape.imagePartName, isNot(part));
    final png = baked.images.findByPart(bakedShape.imagePartName!);
    expect(png, isNotNull);
    final decoded = raster.decodePng(png!.bytes);
    expect(decoded, isNotNull);
    expect(decoded!.width, 32);
    expect(decoded.height, 16);
    final left = decoded.getPixel(4, 8);
    final right = decoded.getPixel(28, 8);
    expect(left.r, greaterThan(200));
    expect(left.b, lessThan(40));
    expect(right.b, greaterThan(200));
    expect(right.r, lessThan(40));

    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .findShapeById(1)!
          .imagePartName,
      bakedShape.imagePartName,
      reason: 'a second save must not stack another metafile PNG',
    );

    final saved = writer.write(
      originalBytes: writer.emptyDocument(),
      edited: doc,
    );
    final after = parser.parse(saved).pages.first.findShapeById(1)!;
    expect(after.foreignType, 'Bitmap');
    expect(after.foreignCompressionType, 'PNG');
    expect(after.imagePartName, isNot(part));
    final savedPng =
        parser.parse(saved).images.findByPart(after.imagePartName!);
    expect(savedPng, isNotNull);
    expect(raster.decodePng(savedPng!.bytes), isNotNull);
  });

  test('EnhMetaFile vector replay bakes to PNG Bitmap for LibreOffice', () {
    const part = '/visio/media/probe_vector.emf';
    final emf = _vectorMagentaEmf();
    final source = VsdxImage(
      partName: part,
      bytes: emf,
      mimeType: 'image/x-emf',
    );
    expect(source.foreignType, 'EnhMetaFile');
    expect(source.rasterForRendering(), isNull);
    expect(extractEmfEmbeddedBitmap(emf), isNull);
    final pngBytes = rasterizeVectorMetafileToPng(
      emf,
      mimeType: 'image/x-emf',
      partName: part,
    );
    expect(pngBytes, isNotNull);
    final decodedVector = raster.decodePng(pngBytes!);
    expect(decodedVector, isNotNull);
    var magenta = 0;
    var transparent = 0;
    for (final pixel in decodedVector!) {
      if (pixel.a < 250) transparent++;
      if (pixel.r > 160 && pixel.g < 100 && pixel.b > 160) magenta++;
    }
    expect(transparent, 0, reason: 'Draw shows Blue 2 through transparent PNG');
    expect(
      magenta,
      greaterThan((decodedVector.width * decodedVector.height * 0.55).round()),
      reason: 'vector EMF rectangle must fill the baked PNG, not a left strip',
    );

    final pic = VsdxShapeFactory.picture(
      id: 1,
      pinX: 4.25,
      pinY: 5.5,
      width: 3,
      height: 1.5,
      imagePartName: part,
    );
    expect(shapeNeedsLibvisioMetafileBitmapBake(pic), isTrue);

    var doc = parser.parse(writer.emptyDocument());
    doc = doc
        .copyWith(images: doc.images.withImage(source))
        .replacePage(0, doc.pages.first.addShape(pic));
    final baked = documentForLibvisioWrite(doc);
    final bakedShape = baked.pages.first.findShapeById(1)!;
    expect(shapeNeedsLibvisioMetafileBitmapBake(bakedShape), isFalse);
    expect(bakedShape.foreignType, 'Bitmap');
    expect(bakedShape.foreignCompressionType, 'PNG');
    expect(bakedShape.imagePartName, isNot(part));
    final png = baked.images.findByPart(bakedShape.imagePartName!);
    expect(png, isNotNull);
    final decoded = raster.decodePng(png!.bytes);
    expect(decoded, isNotNull);
    var bakedMagenta = 0;
    var bakedTransparent = 0;
    for (final pixel in decoded!) {
      if (pixel.a < 250) bakedTransparent++;
      if (pixel.r > 160 && pixel.g < 100 && pixel.b > 160) bakedMagenta++;
    }
    expect(bakedTransparent, 0);
    expect(
      bakedMagenta,
      greaterThan((decoded.width * decoded.height * 0.55).round()),
    );

    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .findShapeById(1)!
          .imagePartName,
      bakedShape.imagePartName,
      reason: 'a second save must not stack another metafile PNG',
    );

    final saved = writer.write(
      originalBytes: writer.emptyDocument(),
      edited: doc,
    );
    final after = parser.parse(saved).pages.first.findShapeById(1)!;
    expect(after.foreignType, 'Bitmap');
    expect(after.foreignCompressionType, 'PNG');
  });

  test('EnhMetaFile ExtTextOut glyphs bake to PNG Bitmap for LibreOffice', () {
    const part = '/visio/media/probe_text.emf';
    final emf = _magentaTextEmf();
    final source = VsdxImage(
      partName: part,
      bytes: emf,
      mimeType: 'image/x-emf',
    );
    expect(source.foreignType, 'EnhMetaFile');
    expect(source.rasterForRendering(), isNull);
    expect(extractEmfEmbeddedBitmap(emf), isNull);
    expect(
      parseEmfDrawing(emf)!.ops.whereType<MetafileTextOp>().single.text,
      'HI',
    );
    final pngBytes = rasterizeVectorMetafileToPng(
      emf,
      mimeType: 'image/x-emf',
      partName: part,
    );
    expect(pngBytes, isNotNull);
    final decodedText = raster.decodePng(pngBytes!);
    expect(decodedText, isNotNull);
    var magenta = 0;
    var transparent = 0;
    for (final pixel in decodedText!) {
      if (pixel.a < 250) transparent++;
      if (pixel.r > 160 && pixel.g < 100 && pixel.b > 160) magenta++;
    }
    expect(transparent, 0, reason: 'Draw shows Blue 2 through transparent PNG');
    expect(magenta, greaterThan(200), reason: 'ExtTextOut HI must ink the PNG');

    final pic = VsdxShapeFactory.picture(
      id: 1,
      pinX: 4.25,
      pinY: 5.5,
      width: 3,
      height: 1.5,
      imagePartName: part,
    );
    expect(shapeNeedsLibvisioMetafileBitmapBake(pic), isTrue);

    var doc = parser.parse(writer.emptyDocument());
    doc = doc
        .copyWith(images: doc.images.withImage(source))
        .replacePage(0, doc.pages.first.addShape(pic));
    final baked = documentForLibvisioWrite(doc);
    final bakedShape = baked.pages.first.findShapeById(1)!;
    expect(shapeNeedsLibvisioMetafileBitmapBake(bakedShape), isFalse);
    expect(bakedShape.foreignType, 'Bitmap');
    expect(bakedShape.foreignCompressionType, 'PNG');
    expect(bakedShape.imagePartName, isNot(part));
    final png = baked.images.findByPart(bakedShape.imagePartName!);
    expect(png, isNotNull);
    var bakedMagenta = 0;
    var bakedTransparent = 0;
    for (final pixel in raster.decodePng(png!.bytes)!) {
      if (pixel.a < 250) bakedTransparent++;
      if (pixel.r > 160 && pixel.g < 100 && pixel.b > 160) bakedMagenta++;
    }
    expect(bakedTransparent, 0);
    expect(bakedMagenta, greaterThan(200));

    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .findShapeById(1)!
          .imagePartName,
      bakedShape.imagePartName,
      reason: 'a second save must not stack another metafile PNG',
    );

    final saved = writer.write(
      originalBytes: writer.emptyDocument(),
      edited: doc,
    );
    final after = parser.parse(saved).pages.first.findShapeById(1)!;
    expect(after.foreignType, 'Bitmap');
    expect(after.foreignCompressionType, 'PNG');
  });

  test('MetaFile dimension labels bake into PNG for LibreOffice', () {
    final wmf = File('test/fixtures/metafile/Visio6PlanWithDimensions.wmf')
        .readAsBytesSync();
    expect(parseWmfDrawing(wmf)!.ops.whereType<MetafileTextOp>(), isNotEmpty);
    final png = rasterizeVectorMetafileToPng(
      wmf,
      mimeType: 'image/x-wmf',
      partName: '/visio/media/plan.wmf',
    )!;
    final decoded = raster.decodePng(png)!;
    var dark = 0;
    var transparent = 0;
    for (final pixel in decoded) {
      if (pixel.a < 250) transparent++;
      if (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b < 80) dark++;
    }
    expect(transparent, 0);
    expect(dark, greaterThan(70000), reason: 'WMF labels must add ink');
  });

  test('Metafile hatch strokes bake into PNG for LibreOffice', () {
    const drawing = MetafileDrawing(
      minX: 0,
      minY: 0,
      maxX: 32,
      maxY: 32,
      ops: <Object>[
        MetafilePathOp(
          points: <MetafilePoint>[
            MetafilePoint(0, 0),
            MetafilePoint(32, 0),
            MetafilePoint(32, 32),
            MetafilePoint(0, 32),
          ],
          closed: true,
          fill: true,
          stroke: false,
          fillArgb: 0xFF008000,
          strokeArgb: 0,
          strokeWidth: 1,
          fillHatch: 4,
          fillBackgroundArgb: 0xFFFFFFFF,
        ),
      ],
    );
    final png = rasterizeMetafileDrawingToPng(drawing, maxEdge: 64)!;
    final decoded = raster.decodePng(png)!;
    var green = 0;
    var white = 0;
    var transparent = 0;
    for (final pixel in decoded) {
      if (pixel.a < 250) transparent++;
      if (pixel.g > pixel.r + 20 && pixel.g > pixel.b + 20) green++;
      if (pixel.r > 240 && pixel.g > 240 && pixel.b > 240) white++;
    }
    expect(transparent, 0);
    expect(green, greaterThan(50), reason: 'HS_CROSS hatch must ink green');
    expect(white, greaterThan(500), reason: 'hatch background must stay white');
  });

  test('EnhMetaFile hatch bakes to PNG Bitmap for LibreOffice', () {
    const part = '/visio/media/probe_hatch.emf';
    final emf = _hatchGreenEmf();
    expect(extractEmfEmbeddedBitmap(emf), isNull);
    expect(
      parseEmfDrawing(emf)!
          .ops
          .whereType<MetafilePathOp>()
          .any((op) => op.fillHatch == 4),
      isTrue,
    );
    final pic = VsdxShapeFactory.picture(
      id: 1,
      pinX: 4.25,
      pinY: 5.5,
      width: 3,
      height: 1.5,
      imagePartName: part,
    );
    var doc = parser.parse(writer.emptyDocument());
    doc = doc
        .copyWith(
          images: doc.images.withImage(
            VsdxImage(partName: part, bytes: emf, mimeType: 'image/x-emf'),
          ),
        )
        .replacePage(0, doc.pages.first.addShape(pic));
    final baked = documentForLibvisioWrite(doc);
    final bakedShape = baked.pages.first.findShapeById(1)!;
    expect(bakedShape.foreignType, 'Bitmap');
    expect(bakedShape.foreignCompressionType, 'PNG');
    final png = baked.images.findByPart(bakedShape.imagePartName!)!;
    var green = 0;
    var transparent = 0;
    for (final pixel in raster.decodePng(png.bytes)!) {
      if (pixel.a < 250) transparent++;
      if (pixel.g > pixel.r + 20 && pixel.g > pixel.b + 20) green++;
    }
    expect(transparent, 0);
    expect(green, greaterThan(50),
        reason: 'baked hatch PNG must keep green strokes');
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .findShapeById(1)!
          .imagePartName,
      bakedShape.imagePartName,
    );
  });

  test('WebP Bitmap bakes to PNG for LibreOffice', () {
    const part = '/visio/media/probe.webp';
    final webp = _magentaWebp();
    expect(raster.decodeWebP(webp), isNotNull);
    final source = VsdxImage(
      partName: part,
      bytes: webp,
      mimeType: 'image/webp',
    );
    expect(source.foreignType, 'Bitmap');
    expect(source.compressionType, isNull);
    expect(source.looksLikeBmpFile, isFalse);
    final pic = VsdxShapeFactory.picture(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 2,
      imagePartName: part,
    );
    expect(shapeNeedsLibvisioUnsupportedBitmapBake(pic, source), isTrue);

    var doc = parser.parse(writer.emptyDocument());
    doc = doc
        .copyWith(images: doc.images.withImage(source))
        .replacePage(0, doc.pages.first.addShape(pic));
    final baked = documentForLibvisioWrite(doc);
    final bakedShape = baked.pages.first.findShapeById(1)!;
    expect(shapeNeedsLibvisioUnsupportedBitmapBake(bakedShape), isFalse);
    expect(bakedShape.foreignType, 'Bitmap');
    expect(bakedShape.foreignCompressionType, 'PNG');
    expect(bakedShape.imagePartName, isNot(part));
    final png = baked.images.findByPart(bakedShape.imagePartName!);
    expect(png, isNotNull);
    var magenta = 0;
    var transparent = 0;
    for (final pixel in raster.decodePng(png!.bytes)!) {
      if (pixel.a < 250) transparent++;
      if (pixel.r > 160 && pixel.g < 100 && pixel.b > 160) magenta++;
    }
    expect(transparent, 0);
    expect(magenta, greaterThan(50),
        reason: 'WebP magenta must survive PNG bake');
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .findShapeById(1)!
          .imagePartName,
      bakedShape.imagePartName,
      reason: 'a second save must not stack another WebP PNG',
    );
  });

  test('BMP Bitmap stays native for LibreOffice', () {
    const part = '/visio/media/probe.bmp';
    final rasterImage = raster.Image(width: 8, height: 8);
    for (final pixel in rasterImage) {
      rasterImage.setPixelRgba(pixel.x, pixel.y, 255, 0, 0, 255);
    }
    final bmp = Uint8List.fromList(raster.encodeBmp(rasterImage));
    final source = VsdxImage(
      partName: part,
      bytes: bmp,
      mimeType: 'image/bmp',
    );
    expect(source.looksLikeBmpFile, isTrue);
    final pic = VsdxShapeFactory.picture(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1,
      height: 1,
      imagePartName: part,
    );
    expect(shapeNeedsLibvisioUnsupportedBitmapBake(pic, source), isFalse);
    var doc = parser.parse(writer.emptyDocument());
    doc = doc
        .copyWith(images: doc.images.withImage(source))
        .replacePage(0, doc.pages.first.addShape(pic));
    final baked = documentForLibvisioWrite(doc);
    expect(baked.pages.first.findShapeById(1)!.imagePartName, part);
  });

  test('headerless DIB Bitmap bakes to PNG for LibreOffice', () {
    const part = '/visio/media/probe.dib';
    final dib = _magentaDib();
    expect(raster.decodeImage(dib), isNull);
    final source = VsdxImage(
      partName: part,
      bytes: dib,
      mimeType: 'image/bmp',
    );
    expect(source.looksLikeBmpFile, isFalse);
    expect(source.looksLikeHeaderlessDib, isTrue);
    expect(source.compressionType, isNull);
    expect(source.rasterForRendering(), isNotNull);
    final pic = VsdxShapeFactory.picture(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 2,
      imagePartName: part,
    );
    expect(shapeNeedsLibvisioUnsupportedBitmapBake(pic, source), isTrue);

    var doc = parser.parse(writer.emptyDocument());
    doc = doc
        .copyWith(images: doc.images.withImage(source))
        .replacePage(0, doc.pages.first.addShape(pic));
    final baked = documentForLibvisioWrite(doc);
    final bakedShape = baked.pages.first.findShapeById(1)!;
    expect(shapeNeedsLibvisioUnsupportedBitmapBake(bakedShape), isFalse);
    expect(bakedShape.foreignType, 'Bitmap');
    expect(bakedShape.foreignCompressionType, 'PNG');
    expect(bakedShape.imagePartName, isNot(part));
    final png = baked.images.findByPart(bakedShape.imagePartName!);
    expect(png, isNotNull);
    var magenta = 0;
    var transparent = 0;
    for (final pixel in raster.decodePng(png!.bytes)!) {
      if (pixel.a < 250) transparent++;
      if (pixel.r > 160 && pixel.g < 100 && pixel.b > 160) magenta++;
    }
    expect(transparent, 0);
    expect(magenta, greaterThan(50),
        reason: 'DIB magenta must survive PNG bake');
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .findShapeById(1)!
          .imagePartName,
      bakedShape.imagePartName,
      reason: 'a second save must not stack another DIB PNG',
    );
  });

  test('ICO Bitmap bakes to PNG for LibreOffice', () {
    const part = '/visio/media/probe.ico';
    final ico = _magentaIco();
    expect(raster.decodeIco(ico), isNotNull);
    final source = VsdxImage(
      partName: part,
      bytes: ico,
      mimeType: 'image/x-icon',
    );
    expect(source.looksLikeBmpFile, isFalse);
    expect(source.looksLikeIco, isTrue);
    expect(source.compressionType, isNull);
    expect(source.rasterForRendering(), isNotNull);
    final pic = VsdxShapeFactory.picture(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 2,
      imagePartName: part,
    );
    expect(shapeNeedsLibvisioUnsupportedBitmapBake(pic, source), isTrue);

    var doc = parser.parse(writer.emptyDocument());
    doc = doc
        .copyWith(images: doc.images.withImage(source))
        .replacePage(0, doc.pages.first.addShape(pic));
    final baked = documentForLibvisioWrite(doc);
    final bakedShape = baked.pages.first.findShapeById(1)!;
    expect(shapeNeedsLibvisioUnsupportedBitmapBake(bakedShape), isFalse);
    expect(bakedShape.foreignType, 'Bitmap');
    expect(bakedShape.foreignCompressionType, 'PNG');
    expect(bakedShape.imagePartName, isNot(part));
    final png = baked.images.findByPart(bakedShape.imagePartName!);
    expect(png, isNotNull);
    var magenta = 0;
    var transparent = 0;
    for (final pixel in raster.decodePng(png!.bytes)!) {
      if (pixel.a < 250) transparent++;
      if (pixel.r > 160 && pixel.g < 100 && pixel.b > 160) magenta++;
    }
    expect(transparent, 0);
    expect(magenta, greaterThan(50),
        reason: 'ICO magenta must survive PNG bake');
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .findShapeById(1)!
          .imagePartName,
      bakedShape.imagePartName,
      reason: 'a second save must not stack another ICO PNG',
    );
  });

  test('MetaFile floor-plan hatch bakes into PNG for LibreOffice', () {
    final wmf = File('test/fixtures/metafile/Visio5PlanWithDimensions.wmf')
        .readAsBytesSync();
    expect(
      parseWmfDrawing(wmf)!
          .ops
          .whereType<MetafilePathOp>()
          .where((op) => op.fillHatch != null),
      isNotEmpty,
    );
    final png = rasterizeVectorMetafileToPng(
      wmf,
      mimeType: 'image/x-wmf',
      partName: '/visio/media/plan.wmf',
    )!;
    final decoded = raster.decodePng(png)!;
    var green = 0;
    var transparent = 0;
    for (final pixel in decoded) {
      if (pixel.a < 250) transparent++;
      if (pixel.g > pixel.r + 20 && pixel.g > pixel.b + 20 && pixel.g > 80) {
        green++;
      }
    }
    expect(transparent, 0);
    expect(green, greaterThan(200),
        reason: 'Visio5 hatch rooms must stay green');
  });

  test('Metafile pattern brush tiles bake into PNG for LibreOffice', () {
    final tile = raster.Image(width: 2, height: 2);
    tile.setPixelRgba(0, 0, 0, 0, 0, 255);
    tile.setPixelRgba(1, 0, 255, 255, 255, 255);
    tile.setPixelRgba(0, 1, 255, 255, 255, 255);
    tile.setPixelRgba(1, 1, 0, 0, 0, 255);
    final bmp = Uint8List.fromList(raster.encodeBmp(tile));
    final png = rasterizeMetafileDrawingToPng(
      MetafileDrawing(
        minX: 0,
        minY: 0,
        maxX: 16,
        maxY: 16,
        ops: <Object>[
          MetafilePathOp(
            points: const <MetafilePoint>[
              MetafilePoint(0, 0),
              MetafilePoint(16, 0),
              MetafilePoint(16, 16),
              MetafilePoint(0, 16),
            ],
            closed: true,
            fill: true,
            stroke: false,
            fillArgb: 0xFF000000,
            strokeArgb: 0,
            strokeWidth: 1,
            fillPatternBmpBytes: bmp,
          ),
        ],
      ),
      maxEdge: 32,
    )!;
    final decoded = raster.decodePng(png)!;
    var black = 0;
    var white = 0;
    for (final pixel in decoded) {
      if (pixel.r < 20 && pixel.g < 20 && pixel.b < 20) black++;
      if (pixel.r > 240 && pixel.g > 240 && pixel.b > 240) white++;
    }
    expect(black, greaterThan(50),
        reason: 'checker pattern must keep black tiles');
    expect(white, greaterThan(50),
        reason: 'checker pattern must keep white tiles');
  });

  test('Metafile clip keeps later fills inside the GDI region', () {
    final png = rasterizeMetafileDrawingToPng(
      const MetafileDrawing(
        minX: 0,
        minY: 0,
        maxX: 32,
        maxY: 32,
        ops: <Object>[
          MetafileClipRectOp(
            rect: MetafileRect(0, 0, 16, 32),
            mode: MetafileClipCombineMode.intersect,
          ),
          MetafilePathOp(
            points: <MetafilePoint>[
              MetafilePoint(0, 0),
              MetafilePoint(32, 0),
              MetafilePoint(32, 32),
              MetafilePoint(0, 32),
            ],
            closed: true,
            fill: true,
            stroke: false,
            fillArgb: 0xFFFF00FF,
            strokeArgb: 0,
            strokeWidth: 1,
          ),
        ],
      ),
      maxEdge: 32,
    )!;
    final decoded = raster.decodePng(png)!;
    var leftMagenta = 0;
    var rightMagenta = 0;
    for (final pixel in decoded) {
      final magenta = pixel.r > 160 && pixel.g < 100 && pixel.b > 160;
      if (!magenta) continue;
      if (pixel.x < decoded.width * 0.4) {
        leftMagenta++;
      } else if (pixel.x > decoded.width * 0.6) {
        rightMagenta++;
      }
    }
    expect(leftMagenta, greaterThan(50));
    expect(rightMagenta, 0, reason: 'intersect clip must drop the right half');
  });

  test('Object OLE preview bakes to MetaFile for LibreOffice', () {
    const part = '/visio/media/probe.bin';
    final wmf = _rgbDibWmf(width: 32, height: 16);
    expect(looksLikeWmf(wmf), isTrue);
    expect(extractOlePresentationMetafile(wrapOlePresentation(wmf)), wmf);
    final source = VsdxImage(
      partName: part,
      bytes: wrapOlePresentation(wmf),
      mimeType: 'object/ole',
    );
    expect(source.foreignType, 'Object');
    final pic = VsdxShapeFactory.picture(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 1,
      imagePartName: part,
    ).copyWith(foreignType: 'Object');
    expect(shapeNeedsLibvisioOlePreviewBake(pic), isTrue);

    var doc = parser.parse(writer.emptyDocument());
    doc = doc
        .copyWith(images: doc.images.withImage(source))
        .replacePage(0, doc.pages.first.addShape(pic));
    final baked = documentForLibvisioWrite(doc);
    final bakedShape = baked.pages.first.findShapeById(1)!;
    expect(shapeNeedsLibvisioOlePreviewBake(bakedShape), isFalse);
    expect(bakedShape.foreignType, 'MetaFile');
    expect(bakedShape.imagePartName, isNot(part));
    final preview = baked.images.findByPart(bakedShape.imagePartName!);
    expect(preview, isNotNull);
    expect(looksLikeWmf(preview!.bytes), isTrue);
    expect(extractOlePresentationMetafile(preview.bytes), isNull);

    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .findShapeById(1)!
          .imagePartName,
      bakedShape.imagePartName,
      reason: 'a second save must not stack another OLE preview',
    );

    final saved = writer.write(
      originalBytes: writer.emptyDocument(),
      edited: doc,
    );
    final after = parser.parse(saved).pages.first.findShapeById(1)!;
    expect(after.foreignType, 'MetaFile');
    expect(after.imagePartName, isNot(part));
    final savedWmf =
        parser.parse(saved).images.findByPart(after.imagePartName!);
    expect(savedWmf, isNotNull);
    expect(looksLikeWmf(savedWmf!.bytes), isTrue);
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

  test('cropped picture composites into the frame for LibreOffice', () {
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
    const part = '/visio/media/crop.png';
    final source =
        VsdxImage(partName: part, bytes: bytes, mimeType: 'image/png');
    final pic = VsdxShapeFactory.picture(
      id: 1,
      pinX: 3,
      pinY: 3,
      width: 1.2,
      height: 0.8,
      imagePartName: part,
      name: 'Crop',
    ).copyWith(
      imgOffsetXInches: -1.2,
      imgOffsetYInches: 0,
      imgWidthInches: 2.4,
      imgHeightInches: 0.8,
    );
    expect(shapeNeedsLibvisioImageCropBake(pic), isTrue);
    expect(shapeNeedsLibvisioCroppedSoftEdgesBake(pic), isFalse);
    final baked = bakeVisioImageAdjustmentsPng(
      image: source,
      transparency: 0,
      blur: 0,
      brightness: 0.5,
      contrast: 0.5,
      displayWidthInches: 1.2,
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

    var doc = parser.parse(writer.emptyDocument());
    doc = doc
        .copyWith(images: doc.images.withImage(source))
        .replacePage(0, doc.pages.first.addShape(pic));
    expect(
        shapeNeedsLibvisioImageCropBake(
            documentForLibvisioWrite(doc).pages.first.findShapeById(1)!),
        isFalse);
    final saved = writer.write(
      originalBytes: writer.emptyDocument(),
      edited: doc,
    );
    final savedDoc = parser.parse(saved);
    final after = savedDoc.pages.first.findShapeById(1)!;
    expect(after.imgOffsetXInches, closeTo(0, 1e-9));
    expect(after.imgOffsetYInches, closeTo(0, 1e-9));
    expect(after.effectiveImgWidth, closeTo(after.width, 1e-6));
    expect(after.effectiveImgHeight, closeTo(after.height, 1e-6));
    expect(after.imagePartName, isNot(part));
    expect(
      shapeNeedsLibvisioImageCropBake(after),
      isFalse,
      reason: 'a second save must not stack another crop PNG',
    );
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
        shape.copyWith(line: shape.line.withThemeColor(ThemeSlot.accent2)),
      ),
      isTrue,
      reason: 'theme-only LineColor bakes a PNG so Draw keeps the mirror',
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

  test('theme-only stroke Reflection bakes a PNG band for LibreOffice', () {
    const slot = ThemeSlot.accent2;
    final expected = VsdxTheme.office.resolve(slot)!;
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.4,
      height: 0.7,
      name: 'ThemeStrokeMirror',
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(
        weightInches: 0.04,
        themeColorIndex: slot,
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
    expect(shape.line.color, isNull);
    expect(shape.line.themeColorIndex, slot);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank).copyWith(theme: VsdxTheme.office);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final plate =
        baked.pages.first.shapes.where(isLibvisioReflectionPlate).single;
    expect(plate.hasImage, isTrue);
    expect(plate.locked, isTrue);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.fill.pattern, 0);
    expect(source.line.themeColorIndex, slot);
    final decoded = raster.decodePng(
      baked.images.findByPart(plate.imagePartName!)!.bytes,
    )!;
    var ink = 0;
    for (var y = 0; y < decoded.height; y++) {
      for (var x = 0; x < decoded.width; x++) {
        final pixel = decoded.getPixel(x, y);
        if (pixel.a > 20 && pixel.r > pixel.b + 20 && pixel.r > pixel.g + 10) {
          ink++;
        }
      }
    }
    expect(ink, greaterThan(8),
        reason: 'theme slot $slot (${expected.value.toRadixString(16)}) '
            'must freeze into the mirrored stroke PNG');
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioReflectionPlate),
      hasLength(1),
      reason: 'a second save must not stack another Reflection plate',
    );

    final stroke = VsdxShapeFactory.line(
      id: 2,
      ax: 2,
      ay: 5.5,
      bx: 6.5,
      by: 5.5,
      name: 'ThemeStrokeMirror1d',
      line: const VsdxLine(
        weightInches: 0.08,
        themeColorIndex: slot,
      ),
    ).copyWith(
      reflection: const VsdxReflection(
        enabled: true,
        sizeInches: 1,
        distanceInches: 0.1,
        transparency: 0.2,
        blurInches: 0,
      ),
    );
    expect(shapeNeedsLibvisioReflectionBake(stroke), isTrue);
    var strokeDoc = parser.parse(blank).copyWith(theme: VsdxTheme.office);
    strokeDoc =
        strokeDoc.replacePage(0, strokeDoc.pages.first.addShape(stroke));
    final bakedStroke = documentForLibvisioWrite(strokeDoc);
    final strokePlate =
        bakedStroke.pages.first.shapes.where(isLibvisioReflectionPlate).single;
    expect(strokePlate.hasImage, isTrue);
    expect(strokePlate.is1D, isFalse);
    final strokePng = raster.decodePng(
      bakedStroke.images.findByPart(strokePlate.imagePartName!)!.bytes,
    )!;
    var strokeInk = 0;
    for (var y = 0; y < strokePng.height; y++) {
      for (var x = 0; x < strokePng.width; x++) {
        final pixel = strokePng.getPixel(x, y);
        if (pixel.a > 20 && pixel.r > pixel.b + 20 && pixel.r > pixel.g + 10) {
          strokeInk++;
        }
      }
    }
    expect(strokeInk, greaterThan(8),
        reason: 'theme-only 1-D must freeze Office accent2 into the PNG band');

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(savedDoc.pages.first.findShapeById(1)!.reflection.enabled, isFalse);
    expect(
      savedDoc.pages.first.shapes
          .where(isLibvisioReflectionPlate)
          .single
          .hasImage,
      isTrue,
    );
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

  test(
    'multi-stop FillGradient Reflection keeps the middle stop for LibreOffice',
    () {
      const wash = VsdxGradient(
        stops: <VsdxGradientStop>[
          VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF00FF)),
          VsdxGradientStop(position: 0.5, color: VsdxColor(0xFF00FF00)),
          VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
        ],
      );
      final shape = VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 4.25,
        pinY: 6.2,
        width: 3.2,
        height: 1.5,
        name: 'Grad3Mirror',
        fill: const VsdxFill(pattern: 1, gradient: wash),
        line: const VsdxLine(pattern: 0),
      ).copyWith(
        reflection: const VsdxReflection(
          enabled: true,
          sizeInches: 0.55,
          distanceInches: 0.12,
          transparency: 0.25,
          blurInches: 0,
        ),
      );
      expect(shapeNeedsLibvisioReflectionBake(shape), isTrue);
      expect(shapeNeedsLibvisioGeometrySoftEdgesBake(shape), isTrue);

      final blank = writer.emptyDocument();
      var doc = parser.parse(blank);
      doc = doc.replacePage(0, doc.pages.first.addShape(shape));
      final baked = documentForLibvisioWrite(doc);
      final plate =
          baked.pages.first.shapes.where(isLibvisioReflectionPlate).single;
      expect(plate.hasImage, isTrue,
          reason: 'FillPattern 25–40 would drop the green stop on the mirror');
      expect(plate.fill.hasGradient, isFalse);
      expect(
        baked.pages.first.findShapeById(1)!.reflection.enabled,
        isFalse,
        reason: 'SoftEdges then hollows the source; Size must already be 0',
      );
      final png = baked.images.findByPart(plate.imagePartName!);
      expect(png, isNotNull);
      final decoded = raster.decodePng(png!.bytes)!;
      var mag = 0, green = 0, blue = 0;
      for (final pixel in decoded) {
        if (pixel.a < 80) continue;
        if (pixel.r > 140 && pixel.g < 140 && pixel.b > 140) mag++;
        if (pixel.g > 140 && pixel.r < 120 && pixel.b < 120) green++;
        if (pixel.b > 140 && pixel.r < 120 && pixel.g < 140) blue++;
      }
      expect(green, greaterThan(40),
          reason: 'FillPattern 26 would drop the green stop; '
              'mag=$mag green=$green blue=$blue');
      expect(mag + blue, greaterThan(10),
          reason: 'mirrored endpoints must stay; mag=$mag blue=$blue');
      expect(
        documentForLibvisioWrite(baked)
            .pages
            .first
            .shapes
            .where(isLibvisioReflectionPlate),
        hasLength(1),
        reason: 'a second save must not stack another fill-mirror plate',
      );

      const twoStop = VsdxGradient(
        stops: <VsdxGradientStop>[
          VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF00FF)),
          VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
        ],
      );
      final two = VsdxShapeFactory.rectangle(
        id: 2,
        pinX: 4.25,
        pinY: 6.2,
        width: 3.2,
        height: 1.5,
        name: 'Grad2Mirror',
        fill: const VsdxFill(pattern: 1, gradient: twoStop),
        line: const VsdxLine(pattern: 0),
      ).copyWith(
        reflection: const VsdxReflection(
          enabled: true,
          sizeInches: 0.55,
          distanceInches: 0.12,
          transparency: 0.25,
          blurInches: 0,
        ),
      );
      var twoDoc = parser.parse(blank);
      twoDoc = twoDoc.replacePage(0, twoDoc.pages.first.addShape(two));
      final twoPlate = documentForLibvisioWrite(twoDoc)
          .pages
          .first
          .shapes
          .where(isLibvisioReflectionPlate)
          .single;
      expect(twoPlate.hasImage, isFalse,
          reason:
              'two-colour FillGradient reflection must stay FillPattern 25–40');
    },
  );

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
    expect(source.imgOffsetXInches, closeTo(0, 1e-9));
    expect(source.effectiveImgWidth, closeTo(source.width, 1e-6));
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

  test('mixed Character Highlight bakes per-run plates for LibreOffice', () {
    VsdxShape mixed({
      VsdxColor? blockBackground,
      bool hideText = false,
    }) =>
        VsdxShapeFactory.rectangle(
          id: 1,
          pinX: 4,
          pinY: 5,
          width: 4,
          height: 2,
          name: 'HighlightMixed',
          fill: const VsdxFill(foreground: VsdxColor(0xFFFFFFFF), pattern: 1),
          line: const VsdxLine(pattern: 0),
        ).copyWith(
          text: 'MM',
          richText: VsdxRichText(
            textBlock: VsdxTextBlock(
              marginLeftInches: 0,
              marginRightInches: 0,
              marginTopInches: 0,
              marginBottomInches: 0,
              verticalAlign: VsdxVertAlign.middle,
              hideText: hideText,
              backgroundColor: blockBackground,
            ),
            runs: const [
              VsdxTextRun(
                text: 'M',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 1,
                  highlight: VsdxColor(0xFFFF00FF),
                ),
                paraStyle: VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.center,
                ),
              ),
              VsdxTextRun(
                text: 'M',
                charStyle: VsdxCharStyle(
                  fontFamily: 'Arial',
                  fontSizeInches: 1,
                  highlight: VsdxColor(0xFF00FF00),
                ),
                paraStyle: VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.center,
                ),
              ),
            ],
          ),
        );

    final shape = mixed();
    expect(uniformCharacterHighlight(shape), isNull);
    expect(shapeNeedsLibvisioMixedHighlightBake(shape), isTrue);
    expect(shapeNeedsLibvisioTextBkgndBake(shape), isFalse);
    expect(
      shapeNeedsLibvisioMixedHighlightBake(
        mixed(blockBackground: const VsdxColor(0xFFFFFF00)),
      ),
      isFalse,
    );
    expect(
        shapeNeedsLibvisioMixedHighlightBake(mixed(hideText: true)), isFalse);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final plates =
        baked.pages.first.shapes.where(isLibvisioHighlightPlate).toList()
          ..sort(
            (a, b) => int.parse(a.name.split('.')[1])
                .compareTo(int.parse(b.name.split('.')[1])),
          );
    expect(plates, hasLength(2));
    expect(plates.every((p) => p.locked), isTrue);
    expect(plates.every((p) => p.line.pattern == 0), isTrue);
    expect(plates.every((p) => p.fill.pattern == 1), isTrue);
    expect(plates[0].fill.foreground?.value, 0xFFFF00FF);
    expect(plates[1].fill.foreground?.value, 0xFF00FF00);
    expect(libvisioHighlightSourceId(plates[0]), 1);
    expect(plates.map((p) => p.richText.plainText).join(), 'MM');
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.richText.textBlock.hideText, isTrue);
    expect(source.richText.runs[0].charStyle.highlight?.value, 0xFFFF00FF);
    expect(source.richText.runs[1].charStyle.highlight?.value, 0xFF00FF00);
    expect(source.richText.textBlock.backgroundColor, isNull);
    expect(pageHasLibvisioHighlightPlate(baked.pages.first, 1), isTrue);
    expect(
      characterHighlightForPaint(
        source.richText.runs.first,
        shape: source,
        page: baked.pages.first,
      ),
      isNull,
    );
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioHighlightPlate),
      hasLength(2),
      reason: 'a second save must not stack another Highlight plate',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(
      savedDoc.pages.first.shapes.where(isLibvisioHighlightPlate),
      hasLength(2),
    );
    final savedSource = savedDoc.pages.first.findShapeById(1)!;
    expect(savedSource.richText.textBlock.hideText, isTrue);
    expect(
      savedSource.richText.runs[0].charStyle.highlight?.value,
      0xFFFF00FF,
    );
    expect(
      savedSource.richText.runs[1].charStyle.highlight?.value,
      0xFF00FF00,
    );
    expect(savedSource.richText.textBlock.backgroundColor, isNull);
  });

  test('mixed Character Highlight newlines bake stacked plates', () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4.25,
      pinY: 5.5,
      width: 4,
      height: 2.4,
      name: 'HighlightMixedNl',
      fill: const VsdxFill(foreground: VsdxColor(0xFFFFFFFF), pattern: 1),
      line: const VsdxLine(pattern: 0),
    ).copyWith(
      text: 'M\nM',
      richText: const VsdxRichText(
        textBlock: VsdxTextBlock(
          marginLeftInches: 0,
          marginRightInches: 0,
          marginTopInches: 0,
          marginBottomInches: 0,
          verticalAlign: VsdxVertAlign.middle,
        ),
        runs: [
          VsdxTextRun(
            text: 'M\n',
            charStyle: VsdxCharStyle(
              fontFamily: 'Arial',
              fontSizeInches: 1,
              highlight: VsdxColor(0xFFFF00FF),
            ),
            paraStyle: VsdxParaStyle(
              horizontalAlign: VsdxHorzAlign.center,
            ),
          ),
          VsdxTextRun(
            text: 'M',
            charStyle: VsdxCharStyle(
              fontFamily: 'Arial',
              fontSizeInches: 1,
              highlight: VsdxColor(0xFF00FF00),
            ),
            paraStyle: VsdxParaStyle(
              horizontalAlign: VsdxHorzAlign.center,
            ),
          ),
        ],
      ),
    );
    expect(shapeNeedsLibvisioMixedHighlightBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final plates =
        baked.pages.first.shapes.where(isLibvisioHighlightPlate).toList()
          ..sort(
            (a, b) => int.parse(a.name.split('.')[1])
                .compareTo(int.parse(b.name.split('.')[1])),
          );
    expect(plates, hasLength(2));
    expect(plates[0].fill.foreground?.value, 0xFFFF00FF);
    expect(plates[1].fill.foreground?.value, 0xFF00FF00);
    expect(plates[0].richText.plainText, 'M');
    expect(plates[1].richText.plainText, 'M');
    expect(
      plates[0].pinY,
      greaterThan(plates[1].pinY + 0.4),
      reason: 'Visio Y-up: first line sits above the second',
    );
    expect(plates[0].pinX, closeTo(plates[1].pinX, 0.2));
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioHighlightPlate),
      hasLength(2),
      reason: 'a second save must not stack another Highlight plate',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(
      savedDoc.pages.first.shapes.where(isLibvisioHighlightPlate),
      hasLength(2),
    );
    expect(savedDoc.pages.first.findShapeById(1)!.richText.textBlock.hideText,
        isTrue);
  });

  test('mixed Character Highlight wraps to TxtWidth for LibreOffice', () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4.25,
      pinY: 5.5,
      width: 1.5,
      height: 2.4,
      name: 'HighlightMixedWrap',
      fill: const VsdxFill(foreground: VsdxColor(0xFFFFFFFF), pattern: 1),
      line: const VsdxLine(pattern: 0),
    ).copyWith(
      text: 'MMMM MMMM',
      richText: const VsdxRichText(
        textBlock: VsdxTextBlock(
          marginLeftInches: 0,
          marginRightInches: 0,
          marginTopInches: 0,
          marginBottomInches: 0,
          verticalAlign: VsdxVertAlign.middle,
        ),
        runs: [
          VsdxTextRun(
            text: 'MMMM ',
            charStyle: VsdxCharStyle(
              fontFamily: 'Arial',
              fontSizeInches: 0.4,
              highlight: VsdxColor(0xFFFF00FF),
            ),
            paraStyle: VsdxParaStyle(
              horizontalAlign: VsdxHorzAlign.center,
            ),
          ),
          VsdxTextRun(
            text: 'MMMM',
            charStyle: VsdxCharStyle(
              fontFamily: 'Arial',
              fontSizeInches: 0.4,
              highlight: VsdxColor(0xFF00FF00),
            ),
            paraStyle: VsdxParaStyle(
              horizontalAlign: VsdxHorzAlign.center,
            ),
          ),
        ],
      ),
    );
    expect(shapeNeedsLibvisioMixedHighlightBake(shape), isTrue);
    expect(shape.wordWrap, isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final plates =
        baked.pages.first.shapes.where(isLibvisioHighlightPlate).toList()
          ..sort(
            (a, b) => int.parse(a.name.split('.')[1])
                .compareTo(int.parse(b.name.split('.')[1])),
          );
    expect(plates, hasLength(2));
    expect(plates[0].fill.foreground?.value, 0xFFFF00FF);
    expect(plates[1].fill.foreground?.value, 0xFF00FF00);
    expect(plates[0].richText.plainText.trim(), 'MMMM');
    expect(plates[1].richText.plainText.trim(), 'MMMM');
    expect(
      plates[0].pinY,
      greaterThan(plates[1].pinY + 0.15),
      reason: 'Visio Y-up: the wrapped second word sits below the first',
    );
    expect(plates[0].pinX, closeTo(plates[1].pinX, 0.45));
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioHighlightPlate),
      hasLength(2),
      reason: 'a second save must not stack another Highlight plate',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(
      savedDoc.pages.first.shapes.where(isLibvisioHighlightPlate),
      hasLength(2),
    );
    expect(
      savedDoc.pages.first.findShapeById(1)!.richText.textBlock.hideText,
      isTrue,
    );
  });

  test('mixed Character Highlight tabs bake pinned plates', () {
    const tabs = <VsdxTabSet>[
      VsdxTabSet(
        ix: 0,
        stops: <VsdxTabStop>[VsdxTabStop(positionInches: 2)],
      ),
    ];
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4.25,
      pinY: 5.5,
      width: 4,
      height: 2,
      name: 'HighlightMixedTab',
      fill: const VsdxFill(foreground: VsdxColor(0xFFFFFFFF), pattern: 1),
      line: const VsdxLine(pattern: 0),
    ).copyWith(
      text: 'M\tM',
      richText: const VsdxRichText(
        tabSets: tabs,
        textBlock: VsdxTextBlock(
          marginLeftInches: 0,
          marginRightInches: 0,
          marginTopInches: 0,
          marginBottomInches: 0,
          verticalAlign: VsdxVertAlign.middle,
        ),
        runs: [
          VsdxTextRun(
            text: 'M\t',
            charStyle: VsdxCharStyle(
              fontFamily: 'Arial',
              fontSizeInches: 1,
              highlight: VsdxColor(0xFFFF00FF),
            ),
            paraStyle: VsdxParaStyle(
              horizontalAlign: VsdxHorzAlign.left,
            ),
          ),
          VsdxTextRun(
            text: 'M',
            charStyle: VsdxCharStyle(
              fontFamily: 'Arial',
              fontSizeInches: 1,
              highlight: VsdxColor(0xFF00FF00),
            ),
            paraStyle: VsdxParaStyle(
              horizontalAlign: VsdxHorzAlign.left,
            ),
          ),
        ],
      ),
    );
    expect(shapeNeedsLibvisioMixedHighlightBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final plates =
        baked.pages.first.shapes.where(isLibvisioHighlightPlate).toList()
          ..sort(
            (a, b) => int.parse(a.name.split('.')[1])
                .compareTo(int.parse(b.name.split('.')[1])),
          );
    expect(plates, hasLength(2));
    expect(plates[0].fill.foreground?.value, 0xFFFF00FF);
    expect(plates[1].fill.foreground?.value, 0xFF00FF00);
    expect(plates[1].pinX - plates[0].pinX, greaterThan(1.2));
    expect(plates[0].pinY, closeTo(plates[1].pinY, 0.2));
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioHighlightPlate),
      hasLength(2),
      reason: 'a second save must not stack another Highlight plate',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    expect(
      parser.parse(saved).pages.first.shapes.where(isLibvisioHighlightPlate),
      hasLength(2),
    );
  });

  test('TextDirection=1 bakes TxtAngle LibreOffice rotates', () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4.25,
      pinY: 5.5,
      width: 3,
      height: 0.8,
      name: 'TextDirection',
      fill: const VsdxFill(foreground: VsdxColor(0xFFFFFFFF), pattern: 1),
      line: const VsdxLine(pattern: 0),
    ).copyWith(
      text: 'MMMM',
      richText: const VsdxRichText(
        textBlock: VsdxTextBlock(
          marginLeftInches: 0,
          marginRightInches: 0,
          marginTopInches: 0,
          marginBottomInches: 0,
          verticalAlign: VsdxVertAlign.middle,
          textDirection: 1,
        ),
        runs: [
          VsdxTextRun(
            text: 'MMMM',
            charStyle: VsdxCharStyle(
              fontFamily: 'Arial',
              fontSizeInches: 0.5,
            ),
            paraStyle: VsdxParaStyle(
              horizontalAlign: VsdxHorzAlign.center,
            ),
          ),
        ],
      ),
    );
    expect(shapeNeedsLibvisioTextDirectionBake(shape), isTrue);
    expect(
      shapeNeedsLibvisioTextDirectionBake(
        shape.copyWith(
          richText: shape.richText.copyWith(
            textBlock: const VsdxTextBlock(textDirection: 0),
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
    final block = source.richText.textBlock;
    expect(block.textDirection, 0);
    expect(block.angleRad, closeTo(-math.pi / 2, 1e-9));
    expect(block.widthInches, closeTo(0.8, 1e-9));
    expect(block.heightInches, closeTo(3, 1e-9));
    expect(block.locPinXInches, closeTo(0.4, 1e-9));
    expect(block.locPinYInches, closeTo(1.5, 1e-9));
    expect(block.pinXInches, closeTo(1.5, 1e-9));
    expect(block.pinYInches, closeTo(0.4, 1e-9));
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .findShapeById(1)!
          .richText
          .textBlock
          .angleRad,
      closeTo(-math.pi / 2, 1e-9),
      reason: 'a second save must not rotate another −90°',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final after = parser.parse(saved).pages.first.findShapeById(1)!;
    expect(after.richText.textBlock.textDirection, 0);
    expect(after.richText.textBlock.angleRad, closeTo(-math.pi / 2, 1e-9));
    expect(after.richText.textBlock.widthInches, closeTo(0.8, 1e-9));
    expect(after.richText.textBlock.heightInches, closeTo(3, 1e-9));
  });

  test('TextDirection=1 on a connector label bakes TxtAngle at the elbow', () {
    const label = VsdxRichText(
      textBlock: VsdxTextBlock(
        marginLeftInches: 0,
        marginRightInches: 0,
        marginTopInches: 0,
        marginBottomInches: 0,
        verticalAlign: VsdxVertAlign.middle,
        textDirection: 1,
        backgroundColor: VsdxColor(0xFFFF00FF),
      ),
      runs: <VsdxTextRun>[
        VsdxTextRun(
          text: 'MMMM',
          charStyle: VsdxCharStyle(
            fontFamily: 'Arial',
            fontSizeInches: 0.5,
            color: VsdxColor(0xFF000000),
          ),
          paraStyle: VsdxParaStyle(
            horizontalAlign: VsdxHorzAlign.center,
          ),
        ),
      ],
    );
    final elbow = VsdxShapeFactory.line(
      id: 1,
      ax: 1,
      ay: 7,
      bx: 7,
      by: 1,
      name: 'TextDirectionEdge',
    ).copyWith(
      geometries: const <VsdxGeometry>[
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(0, 0),
            LineTo(6, 0),
            LineTo(6, -6),
          ],
        ),
      ],
      richText: label,
    );
    expect(shapeNeedsLibvisioTextDirectionBake(elbow), isTrue);
    expect(
      shapeNeedsLibvisioTextDirectionBake(
        VsdxShapeFactory.line(id: 9, ax: 0, ay: 0, bx: 2, by: 0).copyWith(
          richText: label.copyWith(
            textBlock: const VsdxTextBlock(textDirection: 0),
          ),
        ),
      ),
      isFalse,
    );

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(elbow));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    final block = source.richText.textBlock;
    expect(block.textDirection, 0);
    expect(block.angleRad, closeTo(0, 1e-9));
    expect(block.pinXInches, isNotNull);
    expect(block.heightInches, greaterThan(block.widthInches! + 0.3));
    expect(block.widthInches, lessThan(1.0));
    final pagePin = baked.pages.first.localToPageDeep(
      source.id,
      Offset2D(block.pinXInches!, block.pinYInches!),
    );
    expect(pagePin.x, closeTo(7, 0.2));
    expect(pagePin.y, closeTo(7, 0.2));
    expect(source.autoRotateLabel, isFalse);
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .findShapeById(1)!
          .richText
          .textBlock
          .angleRad,
      closeTo(0, 1e-9),
      reason: 'a second save must not rotate another −90°',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    final after = savedDoc.pages.first.findShapeById(1)!;
    expect(after.richText.textBlock.textDirection, 0);
    expect(after.richText.textBlock.angleRad, closeTo(0, 1e-9));
    final savedPin = savedDoc.pages.first.localToPageDeep(
      after.id,
      Offset2D(
        after.richText.textBlock.pinXInches!,
        after.richText.textBlock.pinYInches!,
      ),
    );
    expect(savedPin.x, closeTo(7, 0.2));
    expect(savedPin.y, closeTo(7, 0.2));
  });

  test('TextDirection=1 keeps Rotate with Edge TxtAngle for LibreOffice', () {
    final shape = VsdxShapeFactory.line(
      id: 1,
      ax: 2,
      ay: 3,
      bx: 6.5,
      by: 7.5,
      name: 'TextDirectionAutoRotate',
      line: const VsdxLine(pattern: 0),
    ).withAutoRotateLabel(true).copyWith(
          richText: const VsdxRichText(
            textBlock: VsdxTextBlock(
              marginLeftInches: 0,
              marginRightInches: 0,
              marginTopInches: 0,
              marginBottomInches: 0,
              verticalAlign: VsdxVertAlign.middle,
              textDirection: 1,
              backgroundColor: VsdxColor(0xFFFF00FF),
            ),
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: 'MMMM',
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
    expect(shapeNeedsLibvisioTextDirectionBake(shape), isTrue);
    expect(shape.autoRotateLabel, isTrue);
    // Isolated AutoRotate still skips vertical text; document write
    // folds TextDirection first so the tangent bake sees TD=0.
    expect(shapeNeedsLibvisioAutoRotateLabelBake(shape), isFalse);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    final block = source.richText.textBlock;
    expect(block.textDirection, 0);
    expect(source.autoRotateLabel, isFalse);
    expect(block.angleRad, closeTo(math.pi / 4, 1e-6));
    expect(block.heightInches, greaterThan(block.widthInches! + 0.15));
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .findShapeById(1)!
          .richText
          .textBlock
          .angleRad,
      closeTo(math.pi / 4, 1e-6),
      reason: 'a second save must not stack another tangent',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final after = parser.parse(saved).pages.first.findShapeById(1)!;
    expect(after.autoRotateLabel, isFalse);
    expect(after.richText.textBlock.textDirection, 0);
    expect(after.richText.textBlock.angleRad, closeTo(math.pi / 4, 1e-6));
    expect(
      after.richText.textBlock.heightInches,
      greaterThan(after.richText.textBlock.widthInches! + 0.15),
    );
  });

  test('mixed Character Highlight follows baked TextDirection', () {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4.25,
      pinY: 5.5,
      width: 4,
      height: 2,
      name: 'HighlightMixedVert',
      fill: const VsdxFill(foreground: VsdxColor(0xFFFFFFFF), pattern: 1),
      line: const VsdxLine(pattern: 0),
    ).copyWith(
      text: 'MM',
      richText: const VsdxRichText(
        textBlock: VsdxTextBlock(
          marginLeftInches: 0,
          marginRightInches: 0,
          marginTopInches: 0,
          marginBottomInches: 0,
          verticalAlign: VsdxVertAlign.middle,
          textDirection: 1,
        ),
        runs: [
          VsdxTextRun(
            text: 'M',
            charStyle: VsdxCharStyle(
              fontFamily: 'Arial',
              fontSizeInches: 1,
              highlight: VsdxColor(0xFFFF00FF),
            ),
            paraStyle: VsdxParaStyle(
              horizontalAlign: VsdxHorzAlign.center,
            ),
          ),
          VsdxTextRun(
            text: 'M',
            charStyle: VsdxCharStyle(
              fontFamily: 'Arial',
              fontSizeInches: 1,
              highlight: VsdxColor(0xFF00FF00),
            ),
            paraStyle: VsdxParaStyle(
              horizontalAlign: VsdxHorzAlign.center,
            ),
          ),
        ],
      ),
    );
    expect(shapeNeedsLibvisioTextDirectionBake(shape), isTrue);
    expect(
      shapeNeedsLibvisioMixedHighlightBake(shape),
      isFalse,
      reason: 'plates wait until TextDirection has become TxtAngle',
    );

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.richText.textBlock.textDirection, 0);
    expect(source.richText.textBlock.angleRad, closeTo(-math.pi / 2, 1e-9));
    expect(source.richText.textBlock.hideText, isTrue);
    final plates =
        baked.pages.first.shapes.where(isLibvisioHighlightPlate).toList()
          ..sort(
            (a, b) => int.parse(a.name.split('.')[1])
                .compareTo(int.parse(b.name.split('.')[1])),
          );
    expect(plates, hasLength(2));
    expect(plates[0].fill.foreground?.value, 0xFFFF00FF);
    expect(plates[1].fill.foreground?.value, 0xFF00FF00);
    expect(plates[0].pinY, greaterThan(plates[1].pinY + 0.2));
    expect(plates[0].pinX, closeTo(plates[1].pinX, 0.35));
    expect(plates[0].angleRad, closeTo(-math.pi / 2, 1e-6));
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioHighlightPlate),
      hasLength(2),
      reason: 'a second save must not stack another Highlight plate',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(
      savedDoc.pages.first.shapes.where(isLibvisioHighlightPlate),
      hasLength(2),
    );
    expect(
      savedDoc.pages.first.findShapeById(1)!.richText.textBlock.textDirection,
      0,
    );
  });

  test('mixed Character Highlight bakes connector-label plates', () {
    const label = VsdxRichText(
      runs: <VsdxTextRun>[
        VsdxTextRun(
          text: 'M',
          charStyle: VsdxCharStyle(
            fontFamily: 'Arial',
            fontSizeInches: 0.4,
            highlight: VsdxColor(0xFFFF00FF),
          ),
          paraStyle: VsdxParaStyle(
            horizontalAlign: VsdxHorzAlign.center,
          ),
        ),
        VsdxTextRun(
          text: 'M',
          charStyle: VsdxCharStyle(
            fontFamily: 'Arial',
            fontSizeInches: 0.4,
            highlight: VsdxColor(0xFF00FF00),
          ),
          paraStyle: VsdxParaStyle(
            horizontalAlign: VsdxHorzAlign.center,
          ),
        ),
      ],
    );
    final elbow = VsdxShapeFactory.line(
      id: 1,
      ax: 1,
      ay: 7,
      bx: 7,
      by: 1,
      name: 'HighlightMixedEdge',
    ).copyWith(
      geometries: const <VsdxGeometry>[
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(0, 0),
            LineTo(6, 0),
            LineTo(6, -6),
          ],
        ),
      ],
      richText: label,
    );
    expect(shapeNeedsLibvisioLooseEdgeLabelBake(elbow), isTrue);
    expect(shapeNeedsLibvisioMixedHighlightBake(elbow), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(elbow));
    final baked = documentForLibvisioWrite(doc);
    final source = baked.pages.first.findShapeById(1)!;
    expect(source.richText.textBlock.hideText, isTrue);
    expect(source.richText.textBlock.pinXInches, isNotNull);
    final plates =
        baked.pages.first.shapes.where(isLibvisioHighlightPlate).toList()
          ..sort(
            (a, b) => int.parse(a.name.split('.')[1])
                .compareTo(int.parse(b.name.split('.')[1])),
          );
    expect(plates, hasLength(2));
    expect(plates[0].fill.foreground?.value, 0xFFFF00FF);
    expect(plates[1].fill.foreground?.value, 0xFF00FF00);
    expect(plates[0].pinX, closeTo(7, 0.6));
    expect(plates[0].pinY, closeTo(7, 0.6));
    expect(plates[1].pinX, closeTo(7, 0.6));
    expect(plates[1].pinY, closeTo(7, 0.6));
    expect(plates[1].pinX, greaterThan(plates[0].pinX + 0.15));
    expect(plates[0].pinY, closeTo(plates[1].pinY, 0.25));
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .shapes
          .where(isLibvisioHighlightPlate),
      hasLength(2),
      reason: 'a second save must not stack another Highlight plate',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final savedDoc = parser.parse(saved);
    expect(
      savedDoc.pages.first.shapes.where(isLibvisioHighlightPlate),
      hasLength(2),
    );
    expect(
      savedDoc.pages.first.findShapeById(1)!.richText.textBlock.hideText,
      isTrue,
    );
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

  test('theme-only Character ColorTrans bakes RGB for LibreOffice', () {
    const slot = ThemeSlot.accent6;
    const trans = 0.7;
    final expected = colourForLibvisioAlpha(
      VsdxTheme.office.resolve(slot)!,
      trans,
    );
    const style = VsdxCharStyle(
      themeColorIndex: slot,
      transparency: trans,
      fontSizeInches: 0.5,
    );
    expect(style.color, isNull);
    expect(charColorForLibvisioWrite(style)?.value, expected.value);
    expect(charTransparencyForLibvisioWrite(style), 0);
    expect(charThemeColorIndexForLibvisioWrite(style), isNull);
    expect(
      charColorForLibvisioWrite(
        const VsdxCharStyle(themeColorIndex: slot),
      ),
      isNull,
      reason: 'opaque theme Color still keeps THEMEVAL',
    );
    expect(
      charThemeColorIndexForLibvisioWrite(
        const VsdxCharStyle(themeColorIndex: slot),
      ),
      slot,
    );

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank).copyWith(theme: VsdxTheme.office);
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4.25,
      pinY: 5.5,
      width: 3,
      height: 2,
      name: 'CharTransTheme',
      fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
      line: const VsdxLine(pattern: 0),
    ).copyWith(
      text: 'H',
      richText: const VsdxRichText(
        runs: <VsdxTextRun>[
          VsdxTextRun(text: 'H', charStyle: style),
        ],
      ),
    );
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final saved = writer.write(originalBytes: blank, edited: doc);
    final xml = VsdxPackage.open(saved)
        .readPartXml('/visio/pages/page1.xml')!
        .toXmlString();
    expect(xml.contains('N="ColorTrans" V="0.7"'), isFalse);
    final hex = (expected.value & 0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0')
        .toUpperCase();
    expect(
      xml.contains('N="Color" V="#$hex"'),
      isTrue,
      reason: 'theme ColorTrans must freeze into hex Color, not THEMEVAL; '
          'expected=#$hex',
    );
    final after = parser.parse(saved).pages.first.findShapeById(1)!;
    expect(after.richText.runs.single.charStyle.color?.value, expected.value);
    expect(after.richText.runs.single.charStyle.themeColorIndex, isNull);
    expect(after.richText.runs.single.charStyle.transparency, closeTo(0, 1e-9));
  });

  test('theme-only FillForegndTrans freezes RGB for LibreOffice', () {
    const slot = ThemeSlot.accent6;
    const trans = 0.7;
    final expected = VsdxTheme.office.resolve(slot)!;
    const fill = VsdxFill(
      themeForegroundIndex: slot,
      foregroundTransparency: trans,
      pattern: 1,
    );
    expect(fill.foreground, isNull);
    final frozen = fillThemeTransForLibvisioWrite(fill, VsdxTheme.office);
    expect(frozen.foreground?.value, expected.value);
    expect(frozen.themeForegroundIndex, isNull);
    expect(frozen.foregroundTransparency, closeTo(trans, 1e-9));
    expect(
      fillThemeTransForLibvisioWrite(
        const VsdxFill(themeForegroundIndex: slot, pattern: 1),
        VsdxTheme.office,
      ).themeForegroundIndex,
      slot,
      reason: 'opaque theme FillForegnd still keeps THEMEVAL',
    );
    expect(
      fillThemeTransForLibvisioWrite(
        const VsdxFill(themeForegroundIndex: slot, pattern: 1),
        VsdxTheme.office,
      ).foreground?.value,
      expected.value,
      reason: 'opaque theme FillForegnd caches RGB in V= so Draw is not black',
    );

    const hatch = VsdxFill(
      foreground: VsdxColor(0xFFFF0000),
      themeBackgroundIndex: slot,
      backgroundTransparency: trans,
      pattern: 6,
    );
    final hatchFrozen = fillThemeTransForLibvisioWrite(hatch, VsdxTheme.office);
    expect(hatchFrozen.background?.value, expected.value);
    expect(hatchFrozen.themeBackgroundIndex, isNull);
    expect(hatchFrozen.backgroundTransparency, closeTo(trans, 1e-9));
    expect(hatchFrozen.foreground?.value, 0xFFFF0000);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank).copyWith(theme: VsdxTheme.office);
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4.25,
      pinY: 5.5,
      width: 3,
      height: 2,
      name: 'FillTransTheme',
      fill: fill,
      line: const VsdxLine(pattern: 0),
    );
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final write = libvisioShapeWrite(shape, theme: VsdxTheme.office);
    expect(write.fill.foreground?.value, expected.value);
    expect(write.fill.themeForegroundIndex, isNull);
    expect(write.fill.foregroundTransparency, closeTo(trans, 1e-9));

    final saved = writer.write(originalBytes: blank, edited: doc);
    final xml = VsdxPackage.open(saved)
        .readPartXml('/visio/pages/page1.xml')!
        .toXmlString();
    expect(xml.contains('N="FillForegnd" F="THEMEVAL()'), isFalse);
    final hex = (expected.value & 0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0')
        .toUpperCase();
    expect(
      xml.contains('N="FillForegnd" V="#$hex"'),
      isTrue,
      reason: 'theme FillForegndTrans must freeze into hex FillForegnd, not '
          'THEMEVAL; expected=#$hex',
    );
    expect(
      xml.contains('N="FillForegndTrans"'),
      isTrue,
      reason: 'FillForegndTrans is a token; keep it so Draw composites',
    );
    final after = parser.parse(saved).pages.first.findShapeById(1)!;
    expect(after.fill.foreground?.value, expected.value);
    expect(after.fill.themeForegroundIndex, isNull);
    expect(after.fill.foregroundTransparency, closeTo(trans, 1e-9));
  });

  test('opaque theme FillForegnd caches RGB in V= for LibreOffice', () {
    const slot = ThemeSlot.accent6;
    final expected = VsdxTheme.office.resolve(slot)!;
    const fill = VsdxFill(
      themeForegroundIndex: slot,
      pattern: 1,
    );
    final cached = fillThemeTransForLibvisioWrite(fill, VsdxTheme.office);
    expect(cached.themeForegroundIndex, slot);
    expect(cached.foreground?.value, expected.value);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank).copyWith(theme: VsdxTheme.office);
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4.25,
      pinY: 5.5,
      width: 3,
      height: 2,
      name: 'FillThemeOpaque',
      fill: fill,
      line: const VsdxLine(pattern: 0),
    );
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final saved = writer.write(originalBytes: blank, edited: doc);
    final xml = VsdxPackage.open(saved)
        .readPartXml('/visio/pages/page1.xml')!
        .toXmlString();
    final hex = (expected.value & 0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0')
        .toUpperCase();
    expect(
      RegExp('N="FillForegnd"[^>]*V="#$hex"').hasMatch(xml) ||
          RegExp('V="#$hex"[^>]*N="FillForegnd"').hasMatch(xml),
      isTrue,
      reason: 'opaque theme FillForegnd must cache RGB in V=; expected=#$hex',
    );
    expect(
      xml.contains('F="THEMEVAL()"'),
      isTrue,
      reason: 'opaque theme FillForegnd must keep THEMEVAL for round-trip',
    );
    expect(
      xml.contains('N="QuickStyleFillColor" V="$slot"'),
      isTrue,
    );
    final after = parser.parse(saved).pages.first.findShapeById(1)!;
    expect(after.fill.themeForegroundIndex, slot);
    expect(after.fill.foreground, isNull);

    final saved2 = writer.write(
      originalBytes: saved,
      edited: parser.parse(saved),
    );
    final xml2 = VsdxPackage.open(saved2)
        .readPartXml('/visio/pages/page1.xml')!
        .toXmlString();
    expect(
      RegExp('N="FillForegnd"[^>]*V="#$hex"').hasMatch(xml2) ||
          RegExp('V="#$hex"[^>]*N="FillForegnd"').hasMatch(xml2),
      isTrue,
      reason: 'second save must keep the same RGB cache, not stack',
    );
    expect(xml2.contains('F="THEMEVAL()"'), isTrue);
    final after2 = parser.parse(saved2).pages.first.findShapeById(1)!;
    expect(after2.fill.themeForegroundIndex, slot);
    expect(after2.fill.foreground, isNull);
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

    final mixed = box('MixedCJK', 'Hi世界', latinUi);
    expect(shapeNeedsLibvisioMixedScriptFontBake(mixed), isTrue);
    expect(shapeNeedsLibvisioMixedScriptFontBake(han), isFalse);
    final mixedBlank = writer.emptyDocument();
    var mixedDoc = parser.parse(mixedBlank);
    mixedDoc = mixedDoc.replacePage(0, mixedDoc.pages.first.addShape(mixed));
    final mixedBaked = documentForLibvisioWrite(mixedDoc);
    final mixedRuns = mixedBaked.pages.first.findShapeById(1)!.richText.runs;
    expect(mixedRuns, hasLength(2));
    expect(mixedRuns[0].text, 'Hi');
    expect(mixedRuns[0].charStyle.fontFamily, 'Arial');
    expect(mixedRuns[1].text, '世界');
    expect(mixedRuns[1].charStyle.fontFamily, 'Microsoft YaHei');
    final mixedSaved =
        writer.write(originalBytes: mixedBlank, edited: mixedDoc);
    final mixedAfter = parser.parse(mixedSaved).pages.first.findShapeById(1)!;
    expect(mixedAfter.richText.runs, hasLength(2));
    expect(mixedAfter.richText.runs[0].charStyle.fontFamily, 'Arial');
    expect(mixedAfter.richText.runs[1].charStyle.fontFamily, 'Microsoft YaHei');
    expect(
      documentForLibvisioWrite(mixedBaked)
          .pages
          .first
          .findShapeById(1)!
          .richText
          .runs,
      hasLength(2),
      reason: 'a second save must not split the script runs again',
    );

    final mixedArabic = box('MixedArabic', 'Hiسلام', latinUi);
    expect(shapeNeedsLibvisioMixedScriptFontBake(mixedArabic), isTrue);
    mixedDoc = parser.parse(mixedBlank).replacePage(
          0,
          parser.parse(mixedBlank).pages.first.addShape(mixedArabic),
        );
    final arabicRuns = documentForLibvisioWrite(mixedDoc)
        .pages
        .first
        .findShapeById(1)!
        .richText
        .runs;
    expect(arabicRuns, hasLength(2));
    expect(arabicRuns[0].text, 'Hi');
    expect(arabicRuns[0].charStyle.fontFamily, 'Arial');
    expect(arabicRuns[0].charStyle.fontSizeInches, closeTo(12 / 72, 1e-12));
    expect(arabicRuns[1].text, 'سلام');
    expect(arabicRuns[1].charStyle.fontFamily, 'Times New Roman');
    expect(arabicRuns[1].charStyle.fontSizeInches, closeTo(18 / 72, 1e-12));

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

  test('collapsed container hides descendants for LibreOffice', () {
    final host = VsdxShapeFactory.container(
      id: 1,
      pinX: 4.25,
      pinY: 8,
      width: 4,
      height: 3,
      name: 'FoldedBox',
      fill: const VsdxFill(foreground: VsdxColor(0xFF1565C0), pattern: 1),
    );
    final child = VsdxShapeFactory.rectangle(
      id: 2,
      pinX: 4.25,
      pinY: 7,
      width: 2,
      height: 1,
      name: 'HiddenChild',
      fill: const VsdxFill(foreground: VsdxColor(0xFFFF00FF), pattern: 1),
    ).copyWith(
      richText: const VsdxRichText(
        runs: <VsdxTextRun>[VsdxTextRun(text: 'kid')],
      ),
    );
    expect(shapeNeedsLibvisioCollapsedHideBake(host), isFalse);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first.addShape(host).addShape(child);
    page = page.reparentShape(2, 1).updateShapeById(1, (s) => s.fold());
    doc = doc.replacePage(0, page);
    expect(
        shapeNeedsLibvisioCollapsedHideBake(doc.pages.first.findShapeById(1)!),
        isTrue);

    final baked = documentForLibvisioWrite(doc);
    final bakedHost = baked.pages.first.findShapeById(1)!;
    expect(bakedHost.collapsed, isTrue);
    expect(bakedHost.fill.pattern, 1);
    expect(bakedHost.children, hasLength(1));
    final bakedChild = bakedHost.children.single;
    expect(bakedChild.libvisioCollapsedHidden, isTrue);
    expect(bakedChild.geometries.every((g) => g.noShow), isTrue);
    expect(bakedChild.fill.pattern, 0);
    expect(bakedChild.line.pattern, 0);
    expect(bakedChild.richText.textBlock.hideText, isTrue);
    expect(
      documentForLibvisioWrite(baked)
          .pages
          .first
          .findShapeById(1)!
          .children
          .single
          .libvisioCollapsedHidden,
      isTrue,
      reason: 'a second save must not stack another hide payload',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final after = parser.parse(saved).pages.first.findShapeById(1)!;
    expect(after.collapsed, isTrue);
    expect(after.children.single.geometries.every((g) => g.noShow), isTrue);
    expect(after.children.single.richText.textBlock.hideText, isTrue);
    expect(after.children.single.libvisioCollapsedHidden, isTrue);

    final opened = after.unfold();
    expect(opened.collapsed, isFalse);
    expect(opened.children.single.libvisioCollapsedHidden, isFalse);
    expect(opened.children.single.geometries.every((g) => g.noShow), isFalse);
    expect(opened.children.single.fill.pattern, 1);
    expect(opened.children.single.line.pattern, 1);
    expect(opened.children.single.richText.textBlock.hideText, isFalse);
    expect(opened.children.single.richText.plainText, 'kid');

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    expect(oracle.svgPages(saved)?.join() ?? '', isNotEmpty);
  });

  test('covered table cells hide the park box for LibreOffice', () {
    var table = TableOps.assembleTable(
      tableId: 1,
      pinX: 4.25,
      pinY: 8,
      width: 4,
      height: 3,
      rows: 2,
      cols: 2,
      name: 'MergeTable',
    );
    table = table.copyWith(
      children: <VsdxShape>[
        for (final cell in table.children)
          TableOps.cellRow(cell) == 0 && TableOps.cellCol(cell) == 1
              ? cell.copyWith(
                  fill: const VsdxFill(
                    foreground: VsdxColor(0xFFFF00FF),
                    pattern: 1,
                  ),
                  richText: const VsdxRichText(
                    runs: <VsdxTextRun>[VsdxTextRun(text: 'hid')],
                  ),
                )
              : cell,
      ],
    );
    table = TableOps.mergeCells(table, row: 0, col: 0, rowSpan: 1, colSpan: 2);
    expect(shapeNeedsLibvisioCoveredHideBake(table), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    doc = doc.replacePage(0, doc.pages.first.addShape(table));

    final baked = documentForLibvisioWrite(doc);
    final bakedTable = baked.pages.first.findShapeById(1)!;
    final covered = TableOps.cellsOf(bakedTable).where(TableOps.isCovered);
    expect(covered, hasLength(1));
    final bakedCell = covered.single;
    expect(bakedCell.libvisioCoveredHidden, isTrue);
    expect(bakedCell.geometries.every((g) => g.noShow), isTrue);
    expect(bakedCell.fill.pattern, 0);
    expect(bakedCell.line.pattern, 0);
    expect(bakedCell.richText.textBlock.hideText, isTrue);
    expect(
      shapeNeedsLibvisioCoveredHideBake(
        documentForLibvisioWrite(baked).pages.first.findShapeById(1)!,
      ),
      isFalse,
      reason: 'a second save must not stack another hide payload',
    );

    final saved = writer.write(originalBytes: blank, edited: doc);
    final after = parser.parse(saved).pages.first.findShapeById(1)!;
    expect(TableOps.isTable(after), isTrue);
    final afterCovered =
        TableOps.cellsOf(after).where(TableOps.isCovered).single;
    expect(afterCovered.libvisioCoveredHidden, isTrue);
    expect(afterCovered.geometries.every((g) => g.noShow), isTrue);
    expect(afterCovered.fill.pattern, 0);

    final opened = TableOps.unmergeCells(after, row: 0, col: 0);
    expect(TableOps.cellsOf(opened).where(TableOps.isCovered), isEmpty);
    final restored = TableOps.cellsOf(opened).firstWhere(
      (c) => TableOps.cellRow(c) == 0 && TableOps.cellCol(c) == 1,
    );
    expect(restored.libvisioCoveredHidden, isFalse);
    expect(restored.geometries.every((g) => g.noShow), isFalse);
    expect(restored.fill.pattern, 1);
    expect(restored.line.pattern, 1);
    expect(restored.richText.textBlock.hideText, isFalse);
    expect(restored.width, greaterThan(1));

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
        reason:
            'closed 2-D arrow cells must not skip the LineColorTrans ribbon');
  });

  test('theme-only LineColorTrans bakes RGB on the sibling ribbon', () {
    const slot = ThemeSlot.accent6;
    const trans = 0.7;
    final expected = VsdxTheme.office.resolve(slot)!;
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 4.25,
      pinY: 5.5,
      width: 3,
      height: 2,
      name: 'LineTransTheme',
      fill: const VsdxFill(foreground: VsdxColor(0xFFFF0000), pattern: 1),
      line: const VsdxLine(
        themeColorIndex: slot,
        weightInches: 0.28,
        transparency: trans,
      ),
    );
    expect(shape.line.color, isNull);
    expect(shapeNeedsLibvisioFilledStrokeRibbonBake(shape), isTrue);

    final blank = writer.emptyDocument();
    var doc = parser.parse(blank).copyWith(theme: VsdxTheme.office);
    doc = doc.replacePage(0, doc.pages.first.addShape(shape));
    final saved = writer.write(originalBytes: blank, edited: doc);
    final page = parser.parse(saved).pages.first;
    final after = page.findShapeById(1)!;
    expect(after.fill.foreground?.value, 0xFFFF0000);
    expect(after.line.pattern, 0);
    final plate = page.shapes.where(isLibvisioStrokeRibbonPlate).single;
    expect(plate.fill.foreground?.value, expected.value,
        reason: 'theme LineColor must freeze into FillForegnd, not black');
    expect(plate.fill.themeForegroundIndex, isNull);
    expect(plate.fill.foregroundTransparency, closeTo(trans, 1e-9));

    final xml = VsdxPackage.open(saved)
        .readPartXml('/visio/pages/page1.xml')!
        .toXmlString();
    final hex = (expected.value & 0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0')
        .toUpperCase();
    expect(xml.contains('N="FillForegnd" V="#$hex"'), isTrue);
    expect(
      xml.contains('N="FillForegnd" V="#000000"'),
      isFalse,
      reason: 'theme LineColorTrans must not keep the black fallback',
    );
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
      savedPage.shapes
          .where(isLibvisioStrokeRibbonPlate)
          .single
          .geometries
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
      savedPage.shapes
          .where(isLibvisioStrokeRibbonPlate)
          .single
          .geometries
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
      <int>[0, 0, 0, 0, 0, 0, 0],
      reason: 'Draw never paints text:bullet-char; the glyph is in the text',
    );
    for (var bullet = 1; bullet <= 7; bullet++) {
      expect(
        savedDoc.pages.first.shapes
            .firstWhere((s) => s.name == 'Bullet$bullet')
            .richText
            .plainText,
        contains(libvisioBulletGlyph(bullet)),
      );
    }
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
    // RVNGSVGDrawingGenerator drops list markers. After the glyph bake
    // the characters live in the paragraph text Draw actually paints.
    for (var bullet = 1; bullet <= 7; bullet++) {
      expect(
        after,
        contains(libvisioBulletGlyph(bullet)),
        reason: 'libvisio must keep baked Bullet $bullet in the text',
      );
    }
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
    expect(xml.contains('N="Bullet" V="1"'), isFalse,
        reason: 'Draw never paints text:bullet-char; the glyph is in the text');
    expect(
      savedDoc.pages.first.shapes
          .firstWhere((s) => s.name == 'CollectedChar')
          .richText
          .plainText,
      contains(libvisioBulletGlyph(1)),
    );
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
    expect(gradientNoPattern.fill.pattern, 0,
        reason: 'a fully transparent stop bakes a PNG, not 25–40');
    expect(gradientNoPattern.fill.hasGradient, isFalse);
    expect(gradientNoPattern.fill.hasFill, isFalse,
        reason: 'the leftover must drop fill so the PNG plate is the body');
    expect(
      savedDoc.pages.first.shapes.where(
        (s) =>
            isLibvisioSoftEdgesPlate(s) &&
            libvisioSoftEdgesSourceId(s) == gradientNoPattern.id,
      ),
      hasLength(1),
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
    expect(collected.paraStyle.bullet, 0,
        reason: 'Draw never paints text:bullet-char; the glyph is in the text');
    expect(collected.text, contains(libvisioBulletGlyph(1)));
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
      reason:
          'must not steal the chevron body as an unfilled LineGradient ribbon',
    );
    expect(shapeNeedsLibvisioGeometrySoftEdgesBake(arrow), isTrue,
        reason: 'a fully transparent stop is not two opaque 25–40 colours');
    expect(fillPatternForLibvisioWrite(arrow.fill), inInclusiveRange(25, 40));
    final write = libvisioShapeWrite(arrow);
    expect(write.fill.pattern, inInclusiveRange(25, 40));
    expect(write.fill.foreground, isNotNull);
    expect(write.fill.background, isNotNull);

    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('linearGradient'));

    final saved = writer.write(originalBytes: bytes, edited: doc);
    final savedDoc = parser.parse(saved);
    final after = savedDoc.pages.first.findShapeById(147)!;
    expect(after.fill.pattern, 0);
    expect(after.fill.hasGradient, isFalse);
    expect(after.fill.hasFill, isFalse,
        reason: 'the leftover must drop fill so the PNG plate is the body');
    expect(
      savedDoc.pages.first.shapes.where(
        (s) =>
            isLibvisioSoftEdgesPlate(s) &&
            libvisioSoftEdgesSourceId(s) == after.id,
      ),
      hasLength(1),
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

/// Minimal EMF whose STRETCHDIBITS record wraps a 24bpp DIB (left red, right blue).
Uint8List _rgbDibEmf({required int width, required int height}) {
  final row = ((width * 3 + 3) ~/ 4) * 4;
  final dib = Uint8List(40 + row * height);
  dib[0] = 40;
  dib[4] = width & 0xff;
  dib[5] = (width >> 8) & 0xff;
  dib[8] = height & 0xff;
  dib[9] = (height >> 8) & 0xff;
  dib[12] = 1;
  dib[14] = 24;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final o = 40 + y * row + x * 3;
      if (x < width ~/ 2) {
        dib[o] = 0x00;
        dib[o + 1] = 0x00;
        dib[o + 2] = 0xff;
      } else {
        dib[o] = 0xff;
        dib[o + 1] = 0x00;
        dib[o + 2] = 0x00;
      }
    }
  }
  final stretchBody = BytesBuilder()
    ..add(Uint8List(40))
    ..add(dib);
  final stretchPayload = stretchBody.toBytes();
  final stretchSize = 8 + stretchPayload.length;
  final stretchPad = (4 - (stretchSize % 4)) % 4;
  final out = BytesBuilder();
  final header = Uint8List(88);
  header[0] = 1;
  header[4] = 88;
  header[0x28] = 0x20;
  header[0x29] = 0x45;
  header[0x2A] = 0x4D;
  header[0x2B] = 0x46;
  out.add(header);
  final stretch = Uint8List(stretchSize + stretchPad);
  stretch[0] = 0x51;
  stretch[4] = stretch.length & 0xff;
  stretch[5] = (stretch.length >> 8) & 0xff;
  stretch.setRange(8, 8 + stretchPayload.length, stretchPayload);
  out.add(stretch);
  final eof = Uint8List(20);
  eof[0] = 0x0e;
  eof[4] = 20;
  out.add(eof);
  return out.toBytes();
}

/// Minimal vector EMF: solid magenta rectangle, no embedded DIB.
Uint8List _vectorMagentaEmf() {
  final out = BytesBuilder();
  void u32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    out.add(data.buffer.asUint8List());
  }

  void i32(int value) {
    final data = ByteData(4)..setInt32(0, value, Endian.little);
    out.add(data.buffer.asUint8List());
  }

  u32(1);
  u32(88);
  i32(0);
  i32(0);
  i32(100);
  i32(100);
  i32(0);
  i32(0);
  i32(100);
  i32(100);
  out.add(const <int>[0x20, 0x45, 0x4D, 0x46]);
  while (out.length < 88) {
    out.addByte(0);
  }
  u32(39); // EMR_CREATEBRUSHINDIRECT
  u32(24);
  u32(1);
  u32(0);
  u32(0x00FF00FF);
  u32(0);
  u32(37); // EMR_SELECTOBJECT
  u32(12);
  u32(1);
  u32(43); // EMR_RECTANGLE
  u32(24);
  i32(5);
  i32(5);
  i32(95);
  i32(95);
  u32(14); // EMR_EOF
  u32(20);
  u32(0);
  u32(0);
  u32(0);
  return out.toBytes();
}

/// Minimal vector EMF: green HS_CROSS hatch, no embedded DIB.
Uint8List _hatchGreenEmf() {
  final out = BytesBuilder();
  void u32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    out.add(data.buffer.asUint8List());
  }

  void i32(int value) {
    final data = ByteData(4)..setInt32(0, value, Endian.little);
    out.add(data.buffer.asUint8List());
  }

  u32(1);
  u32(88);
  i32(0);
  i32(0);
  i32(100);
  i32(100);
  i32(0);
  i32(0);
  i32(100);
  i32(100);
  out.add(const <int>[0x20, 0x45, 0x4D, 0x46]);
  while (out.length < 88) {
    out.addByte(0);
  }
  u32(18);
  u32(12);
  u32(2);
  u32(25);
  u32(12);
  u32(0x00FFFFFF);
  u32(37);
  u32(12);
  u32(0x80000008);
  u32(39);
  u32(24);
  u32(1);
  u32(2);
  u32(0x00008000);
  u32(4);
  u32(37);
  u32(12);
  u32(1);
  u32(43);
  u32(24);
  i32(5);
  i32(5);
  i32(95);
  i32(95);
  u32(14);
  u32(20);
  u32(0);
  u32(0);
  u32(0);
  return out.toBytes();
}

/// 16×16 magenta VP8 WebP (`package:image` 4.3's VP8L decoder throws).
Uint8List _magentaWebp() => Uint8List.fromList(const <int>[
      82,
      73,
      70,
      70,
      62,
      0,
      0,
      0,
      87,
      69,
      66,
      80,
      86,
      80,
      56,
      32,
      50,
      0,
      0,
      0,
      208,
      1,
      0,
      157,
      1,
      42,
      16,
      0,
      16,
      0,
      1,
      64,
      38,
      37,
      160,
      2,
      116,
      186,
      1,
      248,
      0,
      3,
      176,
      0,
      254,
      235,
      222,
      47,
      253,
      227,
      63,
      220,
      103,
      251,
      140,
      255,
      229,
      247,
      255,
      201,
      178,
      249,
      1,
      255,
      32,
      63,
      254,
      73,
      192,
      0,
    ]);

Uint8List _magentaRaster({required bool bmp}) {
  final image = raster.Image(width: 16, height: 16);
  for (final pixel in image) {
    image.setPixelRgba(pixel.x, pixel.y, 255, 0, 255, 255);
  }
  return Uint8List.fromList(
    bmp ? raster.encodeBmp(image) : raster.encodePng(image),
  );
}

/// BITMAPINFOHEADER + pixels, no `BM` file header (libvisio format 0).
Uint8List _magentaDib() {
  final bmp = _magentaRaster(bmp: true);
  expect(bmp.length, greaterThan(14));
  expect(bmp[0], 0x42);
  expect(bmp[1], 0x4d);
  return Uint8List.fromList(bmp.sublist(14));
}

Uint8List _magentaIco() {
  final image = raster.Image(width: 16, height: 16);
  for (final pixel in image) {
    image.setPixelRgba(pixel.x, pixel.y, 255, 0, 255, 255);
  }
  return Uint8List.fromList(raster.encodeIco(image, singleFrame: true));
}

/// Minimal vector EMF: magenta ExtTextOutW "HI", no embedded DIB.
Uint8List _magentaTextEmf() {
  int aligned4(int value) => (value + 3) & ~3;
  final out = BytesBuilder();
  void addRecord(int type, Uint8List payload) {
    final size = aligned4(payload.length + 8);
    final header = ByteData(8)
      ..setUint32(0, type, Endian.little)
      ..setUint32(4, size, Endian.little);
    out.add(header.buffer.asUint8List());
    out.add(payload);
    for (var i = payload.length + 8; i < size; i++) {
      out.addByte(0);
    }
  }

  final header = ByteData(88)
    ..setUint32(0, 1, Endian.little)
    ..setUint32(4, 88, Endian.little)
    ..setInt32(16, 160, Endian.little)
    ..setInt32(20, 100, Endian.little)
    ..setUint32(40, 0x464D4520, Endian.little);
  out.add(header.buffer.asUint8List());

  final font = ByteData(96)..setUint32(0, 1, Endian.little);
  const logFont = 4;
  font
    ..setInt32(logFont, 40, Endian.little)
    ..setInt32(logFont + 16, 700, Endian.little);
  for (var i = 0; i < 'Arial'.length; i++) {
    font.setUint16(logFont + 28 + i * 2, 'Arial'.codeUnitAt(i), Endian.little);
  }
  addRecord(82, font.buffer.asUint8List());
  addRecord(
    37,
    (ByteData(4)..setUint32(0, 1, Endian.little)).buffer.asUint8List(),
  );
  addRecord(
    24,
    (ByteData(4)..setUint32(0, 0x00FF00FF, Endian.little)).buffer.asUint8List(),
  );

  const text = 'HI';
  final source = Uint8List(text.length * 2);
  final sourceData = ByteData.sublistView(source);
  for (var i = 0; i < text.length; i++) {
    sourceData.setUint16(i * 2, text.codeUnitAt(i), Endian.little);
  }
  const stringOffset = 76;
  final recordSize = aligned4(stringOffset + source.length);
  final payload = ByteData(recordSize - 8);
  payload
    ..setInt32(28, 20, Endian.little)
    ..setInt32(32, 30, Endian.little)
    ..setUint32(36, text.length, Endian.little)
    ..setUint32(40, stringOffset, Endian.little);
  payload.buffer.asUint8List().setRange(
        stringOffset - 8,
        stringOffset - 8 + source.length,
        source,
      );
  addRecord(84, payload.buffer.asUint8List());
  addRecord(14, Uint8List(0));
  return Uint8List.fromList(out.toBytes());
}

/// Placeable WMF whose STRETCHDIB record wraps a 24bpp DIB (left red, right blue).
Uint8List _rgbDibWmf({required int width, required int height}) {
  final row = ((width * 3 + 3) ~/ 4) * 4;
  final dib = Uint8List(40 + row * height);
  ByteData.sublistView(dib)
    ..setUint32(0, 40, Endian.little)
    ..setInt32(4, width, Endian.little)
    ..setInt32(8, height, Endian.little)
    ..setUint16(12, 1, Endian.little)
    ..setUint16(14, 24, Endian.little);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final o = 40 + y * row + x * 3;
      if (x < width ~/ 2) {
        dib[o] = 0x00;
        dib[o + 1] = 0x00;
        dib[o + 2] = 0xff;
      } else {
        dib[o] = 0xff;
        dib[o + 1] = 0x00;
        dib[o + 2] = 0x00;
      }
    }
  }

  Uint8List rec(int func, List<int> words) {
    final sizeWords = 3 + words.length;
    final out = Uint8List(sizeWords * 2);
    final data = ByteData.sublistView(out)
      ..setUint32(0, sizeWords, Endian.little)
      ..setUint16(4, func, Endian.little);
    for (var i = 0; i < words.length; i++) {
      data.setInt16(6 + i * 2, words[i], Endian.little);
    }
    return out;
  }

  final stretchBytes = 6 + 22 + dib.length;
  final stretchPadded = (stretchBytes + 1) & ~1;
  final stretch = Uint8List(stretchPadded);
  ByteData.sublistView(stretch)
    ..setUint32(0, stretchPadded ~/ 2, Endian.little)
    ..setUint16(4, 0x0F43, Endian.little)
    ..setUint32(6, 0x00CC0020, Endian.little)
    ..setUint16(10, 0, Endian.little)
    ..setInt16(12, height, Endian.little)
    ..setInt16(14, width, Endian.little)
    ..setInt16(16, 0, Endian.little)
    ..setInt16(18, 0, Endian.little)
    ..setInt16(20, height, Endian.little)
    ..setInt16(22, width, Endian.little)
    ..setInt16(24, 0, Endian.little)
    ..setInt16(26, 0, Endian.little);
  stretch.setRange(28, 28 + dib.length, dib);

  final records = <Uint8List>[
    rec(0x020B, <int>[0, 0]),
    rec(0x020C, <int>[height, width]),
    stretch,
  ];
  final size =
      18 + records.fold<int>(0, (sum, record) => sum + record.length) + 6;
  final wmf = Uint8List(size);
  ByteData.sublistView(wmf)
    ..setUint16(0, 1, Endian.little)
    ..setUint16(2, 9, Endian.little)
    ..setUint16(4, 0x0300, Endian.little)
    ..setUint32(6, size ~/ 2, Endian.little)
    ..setUint16(10, 1, Endian.little)
    ..setUint32(12, stretchPadded ~/ 2, Endian.little);
  var offset = 18;
  for (final record in records) {
    wmf.setRange(offset, offset + record.length, record);
    offset += record.length;
  }
  ByteData.sublistView(wmf)
    ..setUint32(offset, 3, Endian.little)
    ..setUint16(offset + 4, 0, Endian.little);

  final out = Uint8List(22 + wmf.length);
  final placeable = ByteData.sublistView(out)
    ..setUint32(0, 0x9AC6CDD7, Endian.little)
    ..setUint16(4, 0, Endian.little)
    ..setInt16(6, 0, Endian.little)
    ..setInt16(8, 0, Endian.little)
    ..setInt16(10, width, Endian.little)
    ..setInt16(12, height, Endian.little)
    ..setUint16(14, 1440, Endian.little)
    ..setUint32(16, 0, Endian.little);
  var checksum = 0;
  for (var i = 0; i < 10; i++) {
    checksum ^= placeable.getUint16(i * 2, Endian.little);
  }
  placeable.setUint16(20, checksum, Endian.little);
  out.setRange(22, out.length, wmf);
  return out;
}
