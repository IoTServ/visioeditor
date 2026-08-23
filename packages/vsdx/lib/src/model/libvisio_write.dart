/// Rewrite shape line appearance into cells / rows libvisio still collects.
///
/// LibreOffice Draw never reads Visio XML itself — `VisioImportFilter.cxx`
/// only calls `VisioDocument::isSupported` + `parse`. The VSDX token map has
/// no `CompoundType` and no `LineGradient`, no `FillGradient` /
/// `FillGradientEnabled`, `LineColorTrans` is absent and
/// `xmlStringToColour` forces Colour.a = 0, and unknown `LinePattern` ids
/// (custom draw.io arrays, 0xFE, …) fall through `_lineProperties` to a solid
/// stroke. A save therefore has to emit parallel Geometry rails, a built-in
/// pattern 2–23, or — when `User.veDashPattern` is not one of those ids —
/// MoveTo/LineTo dashes with LinePattern=1. A modern FillGradient whose
/// FillPattern was omitted (libvisio default 0) becomes classic FillPattern
/// 25–40 plus FillForegnd/FillBkgnd from the stops (resolved RGB or the
/// stop's theme slot) — otherwise Draw stays
/// hollow and an unfilled LineGradient ribbon would steal the body. For an
/// unfilled stroke with a line gradient or LineColorTrans, a filled ribbon
/// whose FillPattern 25–40 / FillForegndTrans libvisio *does* collect. That ribbon cannot dash: built-in LinePattern
/// 2–23 (which `_lineProperties` *does* collect on a stroke) are flattened
/// to MoveTo/LineTo first, the same way custom `User.veDashPattern` already
/// is, so Draw keeps the gaps. Geometry-less Edraw labels that still carry
/// FillPattern=1 (no path for `m_currentFillGeometry`) write FillPattern=0
/// so Edraw does not fill the text box and hide white glyphs. Unfilled CompoundType 2–4 keep thick/thin contrast
/// the same way: each rail becomes a filled ribbon of that rail's width,
/// because LineWeight is shape-level and stroked rails would share the
/// thinnest width. Arrowed 1-D connectors that also need those
/// rewrites bake Begin/EndArrow as Geometry so Draw does not hang a
/// marker on every open rail. A plain stroke whose authored
/// BeginArrowSize disagrees with `_lineProperties`' line-weight formula
/// bakes the same way (`tokens.txt` has no BeginArrowSize). Marker ids
/// whose `_linePropertiesMarkerPath` is still a TODO stub (26, 31–34,
/// 36–38, 40, 43–45) bake at any size so Draw does not reuse a sibling
/// silhouette. Open arrow ids become filled ribbons of the original
/// weight so they survive a CompoundType rail rewrite. Character Highlight
/// is skipped by
/// `readCharIX` but `TextBkgnd` is collected and painted as
/// `fo:background-color`, so a uniform highlight with no authored
/// text-block fill is written there. Mixed run colours cannot share
/// one TextBkgnd, so a save inserts locked FillForegnd siblings that
/// carry each highlighted run (same advance as nowrap / curved-text),
/// hides the source label, and leaves the Highlight cells for Visio.
/// `TextBkgndTrans` and layer
/// `ColorTrans` have no VSDX collector case (`xmlStringToColour` also
/// zeros alpha), so a save premultiplies those into RGB toward white.
/// `AsianFont` / `ComplexScriptFont` / `ComplexScriptSize` are not tokens —
/// `readCharIX` only stores `Font` and `Size` — so an Asian-only (or
/// complex-script-only) run whose Latin `Font` would tofu in Draw is
/// rewritten to the Asian / complex face, and a complex-only run writes
/// `ComplexScriptSize` into `Size`. Character `LangID` is likewise absent
/// (`readCharIX` has no case; `tokens.txt` has no LangID), so a digit or
/// punctuation run that canvas / SVG already treat as RTL from LangID
/// prefixes U+200F. Strong Arabic / Hebrew letters already set Unicode
/// bidi, so those runs stay untouched. `_lineProperties` derives `stroke-linejoin`
/// from `LineCap` only (round cap → round join, otherwise miter), so an
/// explicit round / arcs join on a square/flat cap is baked with the same
/// RelQuadBezTo fillets as shape-level Rounding, and a bevel join becomes a
/// LineTo chamfer (including when the cap is round: Draw would otherwise
/// round the elbow, so the written LineCap is flattened to extended).
/// The same flatten applies to an explicit miter / miter-clip join on a
/// round cap: Draw would round-join from LineCap, while canvas / SVG keep
/// the sharp elbow. Straight edges have no join to fix and stay round-capped.
/// `User.veMiterLimit` is not a token and `_lineProperties` never emits
/// `svg:stroke-miterlimit` (ODF defaults to 4), so a save chamfers corners
/// whose miter ratio exceeds a tighter limit and drops the User row.
/// Limits above 4 keep the canvas spike: a save expands the unfilled stroke
/// into a filled ribbon whose outline uses that limit (Draw would otherwise
/// bevel every ratio>4 elbow) and drops the User row.
/// The Rounding cell stays 0 so Visio does not restroke. Character ColorTrans,
/// filled-shape LineColorTrans that cannot become a sibling ribbon, and
/// ShdwForegndTrans are not tokens —
/// `xmlStringToColour` also forces Colour.a = 0 — so a save premultiplies
/// those into RGB toward white and writes Trans=0. Theme-only Character
/// Color (canvas `_colourOrTheme`) is resolved through the document
/// theme, then Office, into that same blend — `ColorTrans` is not a
/// token, so leaving THEMEVAL() would paint the slot fully opaque.
/// Theme-bound colours with no transparency still keep THEMEVAL().
/// Theme-only FillForegnd / FillBkgnd with FillForegndTrans /
/// FillBkgndTrans freeze into RGB and *keep* Trans — those cells *are*
/// tokens, so Draw still composites the wash, while THEMEVAL() plus
/// `QuickStyleFillColor` 9 paints faded black (`getThemeColour` stops
/// at 8, and `VSDFillStyle::override` applies explicit FillForegnd
/// after the theme).
/// Theme-only hard-edged ShdwForegndTrans bakes the same way —
/// `ShadowBlur` leftovers keep THEMEVAL() after the Gaussian PNG path.
/// A filled 2-D shape that
/// still paints a stroke bakes LineColorTrans / LineGradient / CompoundType
/// 1–4 rails / LinePattern 2–23 and `veDashPattern` dash ribbons / open-path
/// arrow Geometry / a long `veMiterLimit` spike as a locked sibling ribbon
/// whose FillForegndTrans Draw collects, then drops the source line so Draw
/// does not paint an opaque (or short-miter) stroke on top. Theme-only
/// LineColor freezes into that ribbon FillForegnd (document theme, then
/// Office) — a black fallback plus THEMEVAL painted grey, while canvas
/// already strokes `_colourOrTheme`. Page
/// `ConLineJump*` cells are not tokens either, so a save bakes hops as
/// ArcTo / MoveTo / LineTo and writes `ConLineJumpCode=1`. Image
/// Transparency / Brightness / Contrast / Blur are likewise missing;
/// a save bakes them into a PNG and zeros the cells. Picture `SoftEdgesSize`
/// is not a token either: a 2-D Foreign bitmap bakes the same SourceAlpha
/// feather canvas / SVG use, then SoftEdgesSize is written 0. A cropped
/// picture is composited into the Foreign frame first so the halo sits on
/// the visible window, then ImgOffset / ImgWidth / ImgHeight fill that
/// frame and Draw does not crop the halo off. Geometry `SoftEdgesSize` is the
/// same missing token: a filled 2-D shape bakes a locked Foreign sibling
/// whose PNG alpha uses the same SourceAlpha feather canvas / SVG use
/// (resolved-RGB and theme-only FillGradient / classic 25–40 washes and
/// FillPattern 2–24 hatches are painted into that PNG so Draw does not
/// keep a hard fill, including an RGB hatch whose FillBkgnd is
/// theme-only). Theme-only FillForegnd / LineColor / gradient
/// stops resolve through the document theme, then Office, into that PNG
/// so Draw keeps the feather. Then
/// SoftEdgesSize is written 0 and the source fill is dropped so the
/// plate is the body Draw paints. An unfilled 2-D stroke with SoftEdges
/// bakes the same way from the stroke ring (padded so the outer half of
/// LineWeight and the blur halo are not clipped) and drops the source
/// line. Built-in LinePattern 2–23 and custom `veDashPattern` dashes are
/// painted into that PNG as per-dash ribbons so Draw keeps the gaps
/// (a solid ring would hide them). A filled 2-D shape that also paints a
/// solid stroke bakes fill and stroke into one padded plate and drops both,
/// so Draw does not keep a hard outline. Dashed strokes on a filled body
/// go into the same padded plate so Draw does not keep hard LinePattern
/// dashes on a feathered fill. Gradient / hatch fills with a solid or
/// dashed stroke join that plate so Draw does not keep a hard outline on
/// a feathered wash. CompoundType 1–4 rails join the same plate — they
/// are not a token either, so Draw would otherwise keep a single hard
/// stroke (or hard parallel rails) on a feathered fill. LineGradient is
/// likewise missing from `tokens.txt`, so a 2-D SoftEdges stroke with
/// resolved-RGB or theme-only stops samples that wash into the same
/// padded PNG and drops the source line — Draw would otherwise keep a
/// hard opaque outline (or a hard filled ribbon) on a feathered body.
/// Rounding is a
/// token Draw *does* collect, but the PNG silhouette used to stay a
/// sharp box, so a save dropped the fill and left square corners. The
/// same `filletPolyline` canvas / SVG / libvisio use is sampled into
/// that PNG (and into dash / compound ribbons) so Draw keeps the
/// fillets. `ShadowBlur` is likewise missing —
/// libvisio only emits a hard `draw:shadow` — so a filled 2-D shape with
/// blur bakes a locked Foreign sibling whose PNG is the Gaussian silhouette
/// canvas / SVG already paint, then ShdwPattern and ShadowBlur go to 0 so
/// Draw does not add a second hard copy. Theme-only colour
/// (canvas `_colourOrTheme`) resolves through the document theme, then
/// Office, into that same PNG so Draw keeps the blur. A Foreign picture
/// with blur bakes the same way from the image-frame silhouette canvas uses.
/// PageSheet `ShdwType` / `ShdwObliqueAngle` / `ShdwScaleFactor` are not
/// tokens at all — `readPageSheetProperties` only collects ShdwOffset* — so
/// a hard-edged shadow on an oblique page bakes the sheared, scaled
/// silhouette canvas `_applyPageShadowXform` paints into a locked NoLine
/// sibling whose FillForegndTrans Draw collects, then ShdwPattern goes to 0.
/// Theme-only colour resolves through the document theme, then Office,
/// into that sibling's FillForegnd so Draw keeps both the shear and the
/// slot. A blurred shadow on the same page rasterizes that sheared
/// silhouette into its Gaussian PNG instead, sized to the transformed
/// bounding box.
/// Character Overline is a token whose `readCharIX` case is empty, so a
/// save inserts U+0305 combining overlines and clears the cell. Glow*
/// cells are not tokens; an unfilled 1-D stroke bakes a
/// Gaussian PNG plate sized to the glow ribbon (a Foreign picture cannot
/// hang on a zero-height 1-D XForm, and a FillForegndTrans ribbon would
/// stay hard-edged), an unfilled 2-D stroke bakes a
/// Gaussian PNG ring, and a filled NoLine shape bakes a Gaussian PNG
/// sibling, then GlowSize is written 0. Theme-only colour
/// (canvas `_colourOrTheme`) resolves through the document theme, then
/// Office, into that same PNG so Draw keeps the blur. Filled shapes that
/// already paint a stroke keep their outline — stealing Line would drop
/// CompoundType / dashes that Draw *does* collect. That case bakes a
/// locked Gaussian PNG sibling (canvas `_drawGlow`). An unfilled 2-D
/// CompoundType stroke uses the
/// same PNG ring — canvas `_drawGlow` blurs the path, not the rails, so
/// skipping the bake would drop the halo (CompoundType is not a token).
/// A Foreign picture bakes the same Gaussian PNG ring
/// canvas `_drawGlow` paints around the image frame. Then `GlowSize` is
/// written 0.
/// `Letterspace` is not a token; canvas / SVG already fold FontScale into
/// tracking at 0.55×Size, and `readCharIX` *does* collect FontScale as
/// `style:text-scale`, so a save adds Letterspace into FontScale and
/// writes Letterspace 0. Page `PageColor` is not a token either
/// (`readPageSheetProperties` only stores size, scale, and ShdwOffset*) —
/// a save prepends a locked full-page plate so Draw paints the sheet.
/// `Reflection*` cells are likewise missing from `tokens.txt`, so a filled
/// 2-D shape bakes a locked sibling plate whose FillForegndTrans Draw
/// collects, an unfilled 2-D stroke bakes a locked PNG band of the mirrored
/// stroke (filling the mirror would paint an interior Draw leaves empty;
/// built-in LinePattern 2–23, `veDashPattern`, and CompoundType 1–4 rails
/// go into that band as ribbons so Draw does not keep a solid ring or
/// drop the mirror; a resolved-RGB or theme-only LineGradient is sampled
/// into the same band so Draw does not keep a solid LineColor ring;
/// theme-only LineColor resolves into that PNG so Draw keeps the
/// mirror), an unfilled 1-D
/// stroke bakes the same PNG band from its stroke ribbon (a Foreign plate
/// cannot use a zero-height 1-D XForm, and canvas `_drawReflection`
/// already inflates that degenerate bounds by half LineWeight),
/// and a Foreign picture bakes a locked Gaussian PNG sibling of
/// the same mirrored bitmap canvas / SVG already paint (cropped
/// pictures composite the Img* window into the frame first; FlipY
/// flips the bitmap before the mirror so the visual bottom is nearest,
/// and the plate LocPin follows `_reflectFillRing` without copying FlipY),
/// then
/// `ReflectionSize` is written 0. draw.io Sketch lives in
/// `User.veSketch*` rows libvisio never reads, so a save maps hachure /
/// cross-hatch / dots onto FillPattern 2–24 (`draw:fill=hatch`) and bakes
/// the two jiggle strokes as locked siblings, then writes `veSketch=0`.
/// draw.io Glass is likewise `User.veGlass` (not a token), so a save inserts
/// a locked white top-light sibling whose FillForegndTrans Draw collects,
/// then writes `veGlass=0`. draw.io Shape Opacity is `User.veOpacity`
/// (not a token), so a save folds it into FillForegndTrans / line
/// transparency / image Transparency Draw actually collects, then drops
/// the User row. draw.io Label Border is `User.veLabelBorderColor`
/// (not a token), so a save inserts a locked NoFill sibling whose LineColor
/// Draw collects, then drops the User row. draw.io Label Padding is
/// `User.veLabelPadding` (not a token), so a save adds the pixel inset
/// into Left/Right/Top/BottomMargin (`fo:padding-*`) Draw collects, then
/// drops the User row. draw.io Curved Text is `User.veCurvedText`
/// (not a token), so a save inserts locked per-glyph siblings along the
/// same quadratic arc canvas / SVG already paint, hides the source
/// (`HideText` is a token) and drops the User row. FlipX / FlipY extra
/// text mirrors (canvas `_textFlip*`) are applied about TxtPin before
/// the shape XForm so Draw keeps the upright arc. draw.io Shape Inside is
/// `User.veShapeInside` (not a token), so a save inserts locked per-line
/// siblings in the same outline bands canvas / SVG already paint, hides
/// the source and drops the User row. FlipX / FlipY use the same TxtPin
/// extra-mirror. Open arrowheads no longer block Sketch jiggle: plates
/// drop Begin/EndArrow and the source keeps filled arrow Geometry. Glueable
/// 1-D labels with no `TxtPin` sit on the drawn-route midpoint on canvas /
/// SVG; Draw uses the 1-D XForm box (`m_txtxform` falls back to `m_xform`),
/// so a save writes that midpoint into `TxtPin` / a tight `TxtWidth`.
/// draw.io Rotate with Edge is
/// `User.veAutoRotateLabel` (not a token), so a save writes the route
/// tangent into `TxtAngle` Draw collects and drops the User row. draw.io
/// Word Wrap is `User.veWordWrap` (not a token), so a save expands TxtWidth
/// to the unwrapped line plus margins (`svg:width` Draw wraps against) and
/// drops the User row. draw.io Flow Animation is `User.veFlowAnimation*`
/// (not a token), so a save flattens the same 8 CSS-px dash canvas / SVG
/// synthesise into MoveTo/LineTo and writes `veFlowAnimation=0`. Arrowed
/// connectors that also flatten those dashes (or `veDashPattern`) bake
/// Begin/EndArrow as Geometry first so Draw does not hang a marker on
/// every open dash. draw.io collapsed containers are `User.veCollapsed`
/// (not a token), so a save writes Geometry `NoShow`, `HideText`,
/// `FillPattern=0` / `LinePattern=0`, and zero `ImgWidth` / `ImgHeight`
/// on every descendant — tokens Draw collects — and stores a restore
/// payload so Unfold can show them again. Merged-table `User.veCovered`
/// cells are the same missing token: canvas skips them while Draw would
/// paint the 0.01" park box, so a save applies those hide cells and
/// stores `veCoveredHidden` for Unmerge.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../export/compound_stroke.dart';
import '../export/line_jumps.dart';
import '../utils/color.dart';
import '../utils/gradient_math.dart';
import 'dash_pattern.dart';
import 'document.dart';
import 'effects.dart';
import 'fill.dart';
import 'geometry.dart';
import 'image.dart';
import 'layer.dart';
import 'line.dart';
import 'page.dart';
import 'path_tangent.dart';
import 'perimeter.dart';
import 'rich_text.dart';
import 'rounding.dart';
import 'shape.dart';
import 'shape_factory.dart';
import 'shape_inside.dart';
import 'sketch_style.dart';
import 'table.dart';
import 'theme.dart';
import 'user_property.dart';

/// Rewrite hops and image adjustments the VSDX token map cannot collect.
VsdxDocument documentForLibvisioWrite(VsdxDocument document) {
  var pagesChanged = false;
  final pages = <VsdxPage>[];
  for (final page in document.pages) {
    final next = bakeLineJumpsForLibvisioWrite(page);
    pagesChanged |= !identical(next, page);
    pages.add(next);
  }
  final hopped = pagesChanged ? document.copyWith(pages: pages) : document;
  return bakePageColorForLibvisioWrite(
    bakeCoveredForLibvisioWrite(
      bakeCollapsedForLibvisioWrite(
        bakeShapeInsideForLibvisioWrite(
          bakeWordWrapForLibvisioWrite(
            bakeLabelBorderForLibvisioWrite(
              bakeLabelPaddingForLibvisioWrite(
                bakeFilledStrokeRibbonForLibvisioWrite(
                  bakeGeometrySoftEdgesForLibvisioWrite(
                    bakeReflectionForLibvisioWrite(
                      bakeImageAdjustmentsForLibvisioWrite(
                        bakeGlowPlateForLibvisioWrite(
                          bakeGlassForLibvisioWrite(
                            bakeSketchForLibvisioWrite(
                              bakePageShadowForLibvisioWrite(
                                bakeShadowForLibvisioWrite(
                                  bakeCurvedTextForLibvisioWrite(
                                    bakeShapeOpacityForLibvisioWrite(
                                      bakeLangIdRtlForLibvisioWrite(
                                        bakeOverlineForLibvisioWrite(
                                          bakeMixedHighlightForLibvisioWrite(
                                            bakeLooseEdgeLabelForLibvisioWrite(
                                              bakeAutoRotateLabelForLibvisioWrite(
                                                hopped,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Shape name of the full-page plate `PageColor` becomes for Draw.
const kLibvisioPageColorShapeName = 'LibvisioPageColor';

bool _pageColorShouldPaint(VsdxPage page) {
  final color = page.backgroundColor;
  if (color == null || color.alpha == 0) return false;
  if (color.value == VsdxColor.white.value) return false;
  return page.widthInches > 1e-9 && page.heightInches > 1e-9;
}

VsdxShape _pageColorPlateForLibvisioWrite(VsdxPage page) {
  final w = page.widthInches;
  final h = page.heightInches;
  final color = page.backgroundColor!;
  final existingId = page.shapes
      .where((s) => s.name == kLibvisioPageColorShapeName)
      .firstOrNull
      ?.id;
  return VsdxShapeFactory.rectangle(
    id: existingId ?? page.nextFreeShapeId(),
    pinX: w / 2,
    pinY: h / 2,
    width: w,
    height: h,
    name: kLibvisioPageColorShapeName,
    fill: VsdxFill(
      foreground: VsdxColor.argb(255, color.red, color.green, color.blue),
      pattern: 1,
      foregroundTransparency: (1 - color.alpha / 255).clamp(0.0, 1.0),
    ),
    line: const VsdxLine(pattern: 0),
  ).copyWith(
    locPinXInches: w / 2,
    locPinYInches: h / 2,
    locked: true,
  );
}

bool _pageColorPlateMatches(VsdxShape plate, VsdxShape expected) =>
    (plate.width - expected.width).abs() < 1e-9 &&
    (plate.height - expected.height).abs() < 1e-9 &&
    (plate.pinX - expected.pinX).abs() < 1e-9 &&
    (plate.pinY - expected.pinY).abs() < 1e-9 &&
    plate.fill.foreground?.value == expected.fill.foreground?.value &&
    (plate.fill.foregroundTransparency - expected.fill.foregroundTransparency)
            .abs() <
        1e-9 &&
    plate.line.pattern == 0;

/// `true` when [page] needs a full-page `PageColor` plate, or a stale plate
/// stripped, so Draw paints the sheet colour `readPageSheetProperties` skips.
bool pageNeedsLibvisioPageColorBake(VsdxPage page) {
  final existing =
      page.shapes.where((s) => s.name == kLibvisioPageColorShapeName).toList();
  if (!_pageColorShouldPaint(page)) return existing.isNotEmpty;
  if (existing.length != 1) return true;
  if (page.shapes.first.id != existing.single.id) return true;
  return !_pageColorPlateMatches(
    existing.single,
    _pageColorPlateForLibvisioWrite(page),
  );
}

VsdxPage bakePageColorPageForLibvisioWrite(VsdxPage page) {
  if (!pageNeedsLibvisioPageColorBake(page)) return page;
  final others = <VsdxShape>[
    for (final shape in page.shapes)
      if (shape.name != kLibvisioPageColorShapeName) shape,
  ];
  if (!_pageColorShouldPaint(page)) {
    return page.copyWith(shapes: others);
  }
  return page.copyWith(
    shapes: <VsdxShape>[_pageColorPlateForLibvisioWrite(page), ...others],
  );
}

/// Prepend (or strip) the full-page plate Draw uses in place of `PageColor`.
VsdxDocument bakePageColorForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var changed = false;
  for (final page in document.pages) {
    final next = bakePageColorPageForLibvisioWrite(page);
    changed |= !identical(next, page);
    pages.add(next);
  }
  return changed ? document.copyWith(pages: pages) : document;
}

/// Name prefix of the sibling plate `Reflection*` becomes for Draw.
const kLibvisioReflectionShapeNamePrefix = 'LibvisioReflection.';

bool isLibvisioReflectionPlate(VsdxShape shape) =>
    shape.name.startsWith(kLibvisioReflectionShapeNamePrefix);

int? libvisioReflectionSourceId(VsdxShape plate) {
  if (!isLibvisioReflectionPlate(plate)) return null;
  return int.tryParse(
    plate.name.substring(kLibvisioReflectionShapeNamePrefix.length),
  );
}

double _combinedTransparency(double a, double b) =>
    1 - (1 - a.clamp(0.0, 1.0)) * (1 - b.clamp(0.0, 1.0));

double _paintY(VsdxShape shape, double localY) {
  final sy = shape.flipY ? -1.0 : 1.0;
  return sy * (localY - shape.effectiveLocPinY);
}

double _localYFromPaint(VsdxShape shape, double paintY) {
  final sy = shape.flipY ? -1.0 : 1.0;
  return shape.effectiveLocPinY + sy * paintY;
}

bool _ptsNear(Offset2D a, Offset2D b) =>
    (a.x - b.x).abs() < 1e-9 && (a.y - b.y).abs() < 1e-9;

Offset2D _intersectAtY(Offset2D a, Offset2D b, double y) {
  final dy = b.y - a.y;
  if (dy.abs() < 1e-15) return Offset2D(a.x, y);
  final t = (y - a.y) / dy;
  return Offset2D(a.x + t * (b.x - a.x), y);
}

/// Sutherland–Hodgman against `y >= ymin` (paint-space Y-up).
List<Offset2D> _clipKeepYAtLeast(
  List<Offset2D> pts,
  double ymin, {
  required bool closed,
}) {
  if (pts.length < 2) return const <Offset2D>[];
  var ring = pts;
  if (closed && ring.length >= 2 && _ptsNear(ring.first, ring.last)) {
    ring = ring.sublist(0, ring.length - 1);
  }
  if (ring.length < 2) return const <Offset2D>[];
  final out = <Offset2D>[];
  final n = closed ? ring.length : ring.length - 1;
  for (var i = 0; i < n; i++) {
    final start = ring[i];
    final end = closed ? ring[(i + 1) % ring.length] : ring[i + 1];
    final startIn = start.y >= ymin - 1e-12;
    final endIn = end.y >= ymin - 1e-12;
    if (closed) {
      if (endIn) {
        if (!startIn) out.add(_intersectAtY(start, end, ymin));
        out.add(end);
      } else if (startIn) {
        out.add(_intersectAtY(start, end, ymin));
      }
    } else {
      if (i == 0 && startIn) out.add(start);
      if (startIn && endIn) {
        out.add(end);
      } else if (startIn && !endIn) {
        out.add(_intersectAtY(start, end, ymin));
      } else if (!startIn && endIn) {
        out.add(_intersectAtY(start, end, ymin));
        out.add(end);
      }
    }
  }
  if (closed && out.length >= 2 && !_ptsNear(out.first, out.last)) {
    out.add(out.first);
  }
  return out.length >= 2 ? out : const <Offset2D>[];
}

List<VsdxPathCommand> _closedCommandsForRing(List<Offset2D> pts) {
  if (pts.length < 2) return const <VsdxPathCommand>[];
  var ring = pts;
  if (_ptsNear(ring.first, ring.last)) {
    ring = ring.sublist(0, ring.length - 1);
  }
  if (ring.length < 2) return const <VsdxPathCommand>[];
  return <VsdxPathCommand>[
    MoveTo(ring.first.x, ring.first.y),
    for (var i = 1; i < ring.length; i++) LineTo(ring[i].x, ring[i].y),
    LineTo(ring.first.x, ring.first.y),
  ];
}

List<Offset2D> _aabbRing(VsdxShape shape) => <Offset2D>[
      const Offset2D(0, 0),
      Offset2D(shape.width, 0),
      Offset2D(shape.width, shape.height),
      Offset2D(0, shape.height),
      const Offset2D(0, 0),
    ];

/// Stroke-inflated AABB for 1-D reflection plates; 2-D keeps the XForm box.
List<Offset2D> _reflectionSourceAabbRing(VsdxShape shape) {
  if (!shape.is1D) return _aabbRing(shape);
  final aabb = _polygonsAabb(_libvisioStrokeSilhouettePolygons(shape));
  if (aabb == null) return _aabbRing(shape);
  return <Offset2D>[
    Offset2D(aabb.minX, aabb.minY),
    Offset2D(aabb.maxX, aabb.minY),
    Offset2D(aabb.maxX, aabb.maxY),
    Offset2D(aabb.minX, aabb.maxY),
    Offset2D(aabb.minX, aabb.minY),
  ];
}

List<Offset2D> _reflectFillRing(
  List<Offset2D> local,
  VsdxShape shape, {
  required double dist,
  required double clipHeight,
}) {
  if (local.length < 2) return const <Offset2D>[];
  final paint = <Offset2D>[
    for (final p in local) Offset2D(p.x, _paintY(shape, p.y)),
  ];
  var bottom = paint.first.y;
  var top = paint.first.y;
  for (final p in paint) {
    if (p.y < bottom) bottom = p.y;
    if (p.y > top) top = p.y;
  }
  final span = top - bottom;
  final reflected = <Offset2D>[
    for (final p in paint) Offset2D(p.x, 2 * bottom - p.y - dist),
  ];
  final clipped = span <= 1e-9 || clipHeight >= span - 1e-9
      ? reflected
      : _clipKeepYAtLeast(
          reflected,
          bottom - dist - clipHeight,
          closed: true,
        );
  return <Offset2D>[
    for (final p in clipped) Offset2D(p.x, _localYFromPaint(shape, p.y)),
  ];
}

List<VsdxGeometry> _reflectionGeometriesForLibvisioWrite(VsdxShape shape) {
  final dist = math.max(shape.reflection.distanceInches, 0.0);
  final frac = shape.reflection.sizeInches.clamp(0.01, 1.0);
  final out = <VsdxGeometry>[];
  for (final geometry in shape.geometries) {
    if (geometry.noShow || geometry.noFill) continue;
    final pts = _strokedVertices(geometry, shape);
    if (pts == null || pts.length < 2) continue;
    var bottom = _paintY(shape, pts.first.y);
    var top = bottom;
    for (final p in pts) {
      final y = _paintY(shape, p.y);
      if (y < bottom) bottom = y;
      if (y > top) top = y;
    }
    final clipH = (top - bottom) * frac;
    final ring = _reflectFillRing(pts, shape, dist: dist, clipHeight: clipH);
    final commands = _closedCommandsForRing(ring);
    if (commands.length < 3) continue;
    out.add(
      VsdxGeometry(
        noFill: false,
        noLine: true,
        commands: commands,
      ),
    );
  }
  if (out.isNotEmpty) return out;
  final fallback = _aabbRing(shape);
  var bottom = _paintY(shape, fallback.first.y);
  var top = bottom;
  for (final p in fallback) {
    final y = _paintY(shape, p.y);
    if (y < bottom) bottom = y;
    if (y > top) top = y;
  }
  final ring = _reflectFillRing(
    fallback,
    shape,
    dist: dist,
    clipHeight: (top - bottom) * frac,
  );
  final commands = _closedCommandsForRing(ring);
  if (commands.length < 3) return const <VsdxGeometry>[];
  return <VsdxGeometry>[
    VsdxGeometry(noFill: false, noLine: true, commands: commands),
  ];
}

/// `true` when Reflection* must become a sibling plate Draw actually fills.
///
/// `tokens.txt` has no ReflectionSize. Canvas / SVG already paint the mirror;
/// LibreOffice only sees Fill / Line / Geometry / ForeignData, so a filled
/// 2-D leaf bakes a NoLine sibling (FillForegndTrans is a token), an
/// unfilled 2-D or 1-D stroke bakes a mirrored PNG band, and a Foreign
/// picture bakes a Gaussian PNG sibling, then the live cells go to 0.
/// Filled 1-D stays native — its FillPattern is already the body and a
/// zero-height plate cannot carry a fill mirror.
bool shapeNeedsLibvisioReflectionBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  final reflection = shape.reflection;
  if (!reflection.enabled || reflection.sizeInches <= 1e-12) return false;
  if (reflection.transparency >= 1 - 1e-9) return false;
  if (shape.is1D) {
    if (shape.width.abs() <= 1e-9 && shape.height.abs() <= 1e-9) {
      return false;
    }
  } else if (shape.width.abs() <= 1e-9 || shape.height.abs() <= 1e-9) {
    return false;
  }
  if (!shape.is1D && _shapePaintsFill(shape, shape.geometries)) return true;
  if (_shapeCanLibvisioStrokeReflectionPng(shape)) return true;
  return _shapeCanLibvisioPictureReflectionPng(shape);
}

/// Unfilled 2-D and 1-D strokes: canvas `_drawReflection` strokes the
/// flipped path, so filling the mirror geometry would paint an interior
/// Draw leaves empty. A locked PNG band carries the mirrored stroke
/// instead. 1-D uses a 2-D plate sized to the stroke ribbon (canvas
/// inflates zero-area bounds by half LineWeight; a Foreign picture cannot
/// hang on a zero-height 1-D XForm). Built-in LinePattern 2–23, custom
/// `veDashPattern`, and CompoundType 1–4 rails are painted as ribbons so
/// Draw keeps the gaps / thick-thin contrast (a solid ring would hide
/// them; CompoundType is not a token, so skipping the bake would drop the
/// mirror). A resolved-RGB or theme-only LineGradient is sampled into
/// the same band (`tokens.txt` has no LineGradient; a solid LineColor
/// ring would hide the wash). Theme-only LineColor / gradient stops
/// resolve into that PNG the same way canvas `_colourOrTheme` does.
/// FlipY is applied when placing the plate (`_reflectFillRing`)
/// — copying FlipY onto the PNG would mirror the already-placed band
/// twice.
bool _shapeCanLibvisioStrokeReflectionPng(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  if (shape.children.isNotEmpty) return false;
  if (_shapePaintsFill(shape, shape.geometries)) return false;
  if (!shape.line.hasLine) return false;
  if (shape.line.hasGradient) {
    if (_softEdgesLineColorAt(shape) == null) return false;
  }
  final reflection = shape.reflection;
  if (!reflection.enabled || reflection.sizeInches <= 1e-12) return false;
  if (reflection.transparency >= 1 - 1e-9) return false;
  if (shape.is1D) {
    if (shape.width.abs() <= 1e-9 && shape.height.abs() <= 1e-9) {
      return false;
    }
  } else if (shape.width.abs() <= 1e-9 || shape.height.abs() <= 1e-9) {
    return false;
  }
  if (shape.line.compoundType != 0) {
    return _softEdgesCompoundRibbonPolygons(shape).isNotEmpty;
  }
  if (_shapeHasSoftEdgesDashes(shape)) {
    return _softEdgesDashRibbonPolygons(shape).isNotEmpty;
  }
  if (shape.is1D) return _solidStrokeRibbonPolygons(shape).isNotEmpty;
  return _softEdgesStrokeSilhouetteKind(shape) != null;
}

/// Foreign pictures: canvas `_drawReflection` mirrors the bitmap even when
/// Fill and Line are off. Theme-bound pictures still bake — the pixels are
/// already in ForeignData.
bool _shapeCanLibvisioPictureReflectionPng(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  if (!shape.hasImage || shape.is1D) return false;
  if (shape.children.isNotEmpty) return false;
  if (shape.line.hasLine) return false;
  if (_shapePaintsFill(shape, shape.geometries)) return false;
  final reflection = shape.reflection;
  if (!reflection.enabled || reflection.sizeInches <= 1e-12) return false;
  if (reflection.transparency >= 1 - 1e-9) return false;
  if (shape.width.abs() <= 1e-9 || shape.height.abs() <= 1e-9) return false;
  return true;
}

VsdxShape _reflectionPlateForLibvisioWrite(VsdxShape source,
    {required int id}) {
  final trans = source.reflection.transparency;
  return VsdxShape(
    id: id,
    name: '$kLibvisioReflectionShapeNamePrefix${source.id}',
    pinX: source.pinX,
    pinY: source.pinY,
    width: source.width,
    height: source.height,
    locPinXInches: source.locPinXInches,
    locPinYInches: source.locPinYInches,
    angleRad: source.angleRad,
    flipX: source.flipX,
    flipY: source.flipY,
    geometries: _reflectionGeometriesForLibvisioWrite(source),
    fill: source.fill.copyWith(
      foregroundTransparency: _combinedTransparency(
        source.fill.foregroundTransparency,
        trans,
      ),
      backgroundTransparency: _combinedTransparency(
        source.fill.backgroundTransparency,
        trans,
      ),
    ),
    line: const VsdxLine(pattern: 0),
    layerMemberIds: source.layerMemberIds,
    locked: true,
    richText: const VsdxRichText(
      runs: <VsdxTextRun>[],
      textBlock: VsdxTextBlock(hideText: true),
    ),
    text: '',
  );
}

VsdxImage? _imageForLibvisioWrite(ImageRegistry images, String? part) {
  if (part == null || part.isEmpty) return null;
  return images.findByPart(part) ??
      images.findByPart(part.startsWith('/') ? part.substring(1) : '/$part');
}

/// Local box of a Reflection PNG plate: the mirrored, `ReflectionSize`-clipped
/// band shifted down by `ReflectionDist`, grown by [padInches] on every side
/// so the blur halo and the outer stroke half are not clipped.
({double width, double height, double locPinX, double locPinY, double pad})
    _reflectionPlateLocalBox(VsdxShape shape, [double? padInches]) {
  final dist = math.max(shape.reflection.distanceInches, 0.0);
  final frac = shape.reflection.sizeInches.clamp(0.01, 1.0);
  final blur = math.max(shape.reflection.blurInches, 0.0);
  final pad = padInches ?? (blur > 1e-6 ? blur * 3 : 0.0);
  final sourceRing = _reflectionSourceAabbRing(shape);
  var bottom = _paintY(shape, sourceRing.first.y);
  var top = bottom;
  for (final p in sourceRing) {
    final y = _paintY(shape, p.y);
    if (y < bottom) bottom = y;
    if (y > top) top = y;
  }
  final clipH = math.max(top - bottom, 1e-6) * frac;
  final ring = _reflectFillRing(
    sourceRing,
    shape,
    dist: dist,
    clipHeight: clipH,
  );
  var minX = 0.0;
  var maxX = shape.width.abs();
  var minY = -dist - clipH;
  var maxY = -dist;
  if (ring.length >= 2) {
    minX = ring.first.x;
    maxX = minX;
    minY = ring.first.y;
    maxY = minY;
    for (final p in ring) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
  }
  final width = math.max(maxX - minX, 1e-6) + 2 * pad;
  final height = math.max(maxY - minY, 1e-6) + 2 * pad;
  return (
    width: width,
    height: height,
    locPinX: shape.effectiveLocPinX - (minX - pad),
    locPinY: shape.effectiveLocPinY - (minY - pad),
    pad: pad,
  );
}

({Uint8List png, double padInches})? _pictureReflectionPngForLibvisioWrite(
  VsdxShape shape,
  VsdxImage image,
) {
  final box = _reflectionPlateLocalBox(shape);
  final trans = _combinedTransparency(
    shape.imageTransparency,
    shape.reflection.transparency,
  );
  final png = bakePictureReflectionPng(
    image: image,
    sizeFraction: shape.reflection.sizeInches.clamp(0.01, 1.0),
    transparency: trans,
    blurSigmaPx: shape.reflection.blurInches * kLibvisioSoftEdgesPxPerInch,
    padInches: box.pad,
    displayWidthInches: shape.width.abs(),
    frameWidthInches: shape.width,
    frameHeightInches: shape.height,
    imgOffsetXInches: shape.imgOffsetXInches,
    imgOffsetYInches: shape.imgOffsetYInches,
    imgWidthInches: shape.imgWidthInches,
    imgHeightInches: shape.imgHeightInches,
    flipY: shape.flipY,
  );
  if (png == null) return null;
  return (png: png, padInches: box.pad);
}

({Uint8List png, double padInches})? _strokeReflectionPngForLibvisioWrite(
  VsdxShape shape,
  VsdxTheme theme,
) {
  var ribbons = _softEdgesStrokeRibbonPolygons(shape);
  if (ribbons.isEmpty && shape.is1D) {
    ribbons = _solidStrokeRibbonPolygons(shape);
  }
  final kind = shape.is1D ? null : _softEdgesStrokeSilhouetteKind(shape);
  if (kind == null && ribbons.isEmpty) return null;
  final trans = _combinedTransparency(
    shape.line.transparency,
    shape.reflection.transparency,
  );
  final lineColorAt = shape.line.hasGradient
      ? _softEdgesGradientSampler(
          shape.line.gradient!,
          trans,
          shape.width.abs(),
          math.max(shape.height.abs(), 1e-6),
          theme,
        )
      : null;
  if (shape.line.hasGradient && lineColorAt == null) return null;
  final color = _lineRgbForLibvisioWrite(shape.line, theme);
  final alpha = lineColorAt != null
      ? 255
      : (color.alpha * (1 - trans)).round().clamp(0, 255);
  if (lineColorAt == null && alpha <= 0) return null;
  var originX = 0.0;
  var originY = 0.0;
  var w = shape.width.abs();
  var h = shape.height.abs();
  if (shape.is1D) {
    final aabb = _polygonsAabb(ribbons);
    if (aabb == null) return null;
    originX = aabb.minX;
    originY = aabb.minY;
    w = math.max(aabb.maxX - aabb.minX, 1e-6);
    h = math.max(aabb.maxY - aabb.minY, 1e-6);
  }
  if (w <= 1e-9 || h <= 1e-9) return null;
  final minPx = shape.is1D ? 16 : 8;
  var innerWidthPx = math.max(minPx, (w * kLibvisioSoftEdgesPxPerInch).round());
  var innerHeightPx =
      math.max(minPx, (h * kLibvisioSoftEdgesPxPerInch).round());
  const maxPx = 1024;
  final longest = math.max(innerWidthPx, innerHeightPx);
  if (longest > maxPx) {
    final scale = maxPx / longest;
    innerWidthPx = math.max(minPx, (innerWidthPx * scale).round());
    innerHeightPx = math.max(minPx, (innerHeightPx * scale).round());
  }
  final weight =
      shape.line.weightInches > 1e-9 ? shape.line.weightInches : 0.01;
  final blurInches = math.max(shape.reflection.blurInches, 0.0);
  final padInches = _softEdgesStrokeExtentInches(shape) + blurInches * 3;
  final padPx = math.max(1, (padInches / w * innerWidthPx).ceil());
  final strokeWidthPx = weight / w * innerWidthPx;
  final frac = shape.reflection.sizeInches.clamp(0.01, 1.0);
  final bandHeightPx = math.max(1, (innerHeightPx * frac).round());
  var outer = const <({double x, double y})>[];
  var inner = const <({double x, double y})>[];
  var ribbonPx = const <List<({double x, double y})>>[];
  ({double x, double y}) toPx(Offset2D p) => (
        x: padPx + (p.x - originX) / w * (innerWidthPx - 1),
        y: padPx + (1 - (p.y - originY) / h) * (innerHeightPx - 1),
      );
  if (ribbons.isNotEmpty) {
    ribbonPx = <List<({double x, double y})>>[
      for (final ribbon in ribbons)
        if (ribbon.length >= 3)
          <({double x, double y})>[
            for (final p in ribbon) toPx(p),
          ],
    ];
    if (ribbonPx.isEmpty) return null;
  } else if (kind == SoftEdgesSilhouetteKind.polygon) {
    final geom = _softEdgesStrokeGeometry(shape);
    final inches = geom == null ? null : _softEdgesPolygonInches(shape, geom);
    if (inches == null || inches.length < 3) return null;
    final half = weight / 2;
    final left = offsetPolyline(inches, half, closed: true);
    final right = offsetPolyline(inches, -half, closed: true);
    if (left.length < 3 || right.length < 3) return null;
    outer = <({double x, double y})>[for (final p in left) toPx(p)];
    inner = <({double x, double y})>[for (final p in right) toPx(p)];
  }
  final strokeColorAt = lineColorAt == null
      ? null
      : (double innerX, double innerY) =>
          lineColorAt(innerX, innerY, innerWidthPx, innerHeightPx);
  final png = bakeStrokedReflectionPng(
    innerWidthPx: innerWidthPx,
    innerHeightPx: innerHeightPx,
    bandHeightPx: bandHeightPx,
    padPx: padPx,
    red: color.red,
    green: color.green,
    blue: color.blue,
    alpha: alpha,
    strokeWidthPx: strokeWidthPx,
    blurSigmaPx: blurInches / w * innerWidthPx,
    kind: kind ?? SoftEdgesSilhouetteKind.rectangle,
    outer: outer,
    inner: inner,
    ribbons: ribbonPx,
    flipVertical: shape.flipY,
    strokeColorAt: strokeColorAt,
  );
  if (png == null) return null;
  return (png: png, padInches: padPx / innerWidthPx * w);
}

VsdxShape _reflectionPngPlateForLibvisioWrite(
  VsdxShape source, {
  required int id,
  required String imagePartName,
  required double padInches,
  bool flipY = false,
}) {
  final box = _reflectionPlateLocalBox(source, padInches);
  return VsdxShapeFactory.picture(
    id: id,
    pinX: source.pinX,
    pinY: source.pinY,
    width: box.width,
    height: box.height,
    imagePartName: imagePartName,
    name: '$kLibvisioReflectionShapeNamePrefix${source.id}',
  ).copyWith(
    locPinXInches: box.locPinX,
    locPinYInches: box.locPinY,
    angleRad: source.angleRad,
    flipX: source.flipX,
    flipY: flipY,
    locked: true,
    layerMemberIds: source.layerMemberIds,
    richText: const VsdxRichText(
      runs: <VsdxTextRun>[],
      textBlock: VsdxTextBlock(hideText: true),
    ),
    text: '',
  );
}

int _maxShapeId(List<VsdxShape> shapes) {
  var maxId = 0;
  void walk(VsdxShape shape) {
    if (shape.id > maxId) maxId = shape.id;
    for (final child in shape.children) {
      walk(child);
    }
  }

  for (final shape in shapes) {
    walk(shape);
  }
  return maxId;
}

void _collectReflectionPlateIds(List<VsdxShape> shapes, Map<int, int> into) {
  for (final shape in shapes) {
    final sourceId = libvisioReflectionSourceId(shape);
    if (sourceId != null) into[sourceId] = shape.id;
    _collectReflectionPlateIds(shape.children, into);
  }
}

bool pageNeedsLibvisioReflectionBake(VsdxPage page) {
  var hasPlate = false;
  var needs = false;
  void walk(VsdxShape shape) {
    if (isLibvisioReflectionPlate(shape)) {
      hasPlate = true;
    } else if (shapeNeedsLibvisioReflectionBake(shape)) {
      needs = true;
    }
    for (final child in shape.children) {
      walk(child);
    }
  }

  for (final shape in page.shapes) {
    walk(shape);
  }
  return hasPlate || needs;
}

List<VsdxShape> _bakeReflectionTree(
  List<VsdxShape> shapes, {
  required Map<int, int> plateIds,
  required int Function() nextId,
  required ImageRegistry images,
  required String Function(int shapeId) allocatePart,
  required void Function(VsdxImage image) addImage,
  required VsdxTheme theme,
}) {
  final out = <VsdxShape>[];
  var changed = false;
  for (final shape in shapes) {
    if (isLibvisioReflectionPlate(shape)) {
      changed = true;
      continue;
    }
    var next = shape;
    if (shape.children.isNotEmpty) {
      final children = _bakeReflectionTree(
        shape.children,
        plateIds: plateIds,
        nextId: nextId,
        images: images,
        allocatePart: allocatePart,
        addImage: addImage,
        theme: theme,
      );
      if (!identical(children, shape.children)) {
        next = shape.copyWith(children: children);
        changed = true;
      }
    }
    if (shapeNeedsLibvisioReflectionBake(next)) {
      VsdxShape? plate;
      ({Uint8List png, double padInches})? payload;
      var pngPlateFlipY = false;
      if (_shapeCanLibvisioStrokeReflectionPng(next)) {
        payload = _strokeReflectionPngForLibvisioWrite(next, theme);
        // LocPin already follows FlipY via `_reflectFillRing`. Copying
        // FlipY onto the bitmap would mirror the band twice.
        pngPlateFlipY = false;
      } else if (_shapeCanLibvisioPictureReflectionPng(next)) {
        final sourceImage = _imageForLibvisioWrite(images, next.imagePartName);
        if (sourceImage != null) {
          payload = _pictureReflectionPngForLibvisioWrite(next, sourceImage);
          // LocPin already follows FlipY. Copying FlipY onto the bitmap
          // would mirror the band twice.
          pngPlateFlipY = false;
        }
      } else {
        plate = _reflectionPlateForLibvisioWrite(
          next,
          id: plateIds[next.id] ?? nextId(),
        );
        if (plate.geometries.isEmpty) plate = null;
      }
      if (payload != null) {
        final part = allocatePart(next.id);
        addImage(
          VsdxImage(
            partName: part,
            bytes: payload.png,
            mimeType: 'image/png',
          ),
        );
        plate = _reflectionPngPlateForLibvisioWrite(
          next,
          id: plateIds[next.id] ?? nextId(),
          imagePartName: part,
          padInches: payload.padInches,
          flipY: pngPlateFlipY,
        );
      }
      if (plate != null) {
        out.add(plate);
        changed = true;
      }
    } else {
      final existingId = plateIds[next.id];
      if (existingId != null) {
        VsdxShape? kept;
        for (final candidate in shapes) {
          if (candidate.id == existingId) {
            kept = candidate;
            break;
          }
        }
        if (kept != null) {
          out.add(kept);
        }
      }
    }
    out.add(next);
    if (!identical(next, shape)) changed = true;
  }
  return changed ? out : shapes;
}

/// Insert (or strip) the sibling plates Draw uses in place of `Reflection*`.
VsdxDocument bakeReflectionForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  var registry = document.images;
  final used = <String>{
    for (final image in document.images.all) image.partName,
  };
  String allocatePart(int shapeId) {
    var name = '/visio/media/image_lo_reflection_$shapeId.png';
    var n = 0;
    while (used.contains(name) || registry.findByPart(name) != null) {
      n++;
      name = '/visio/media/image_lo_reflection_${shapeId}_$n.png';
    }
    used.add(name);
    return name;
  }

  final pages = <VsdxPage>[];
  var changed = false;
  for (final page in document.pages) {
    if (!pageNeedsLibvisioReflectionBake(page)) {
      pages.add(page);
      continue;
    }
    final plateIds = <int, int>{};
    _collectReflectionPlateIds(page.shapes, plateIds);
    var nextId = _maxShapeId(page.shapes) + 1;
    final shapes = _bakeReflectionTree(
      page.shapes,
      plateIds: plateIds,
      nextId: () => nextId++,
      images: registry,
      allocatePart: allocatePart,
      addImage: (image) {
        registry = registry.withImage(image);
        changed = true;
      },
      theme: document.theme,
    );
    if (identical(shapes, page.shapes)) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      changed = true;
    }
  }
  if (!changed) return document;
  return document.copyWith(pages: pages, images: registry);
}

/// Cells Draw will collect. Size is 0 after a sibling-plate bake.
VsdxReflection reflectionForLibvisioWrite(VsdxShape shape) {
  if (!shapeNeedsLibvisioReflectionBake(shape)) return shape.reflection;
  return shape.reflection.copyWith(enabled: false, sizeInches: 0);
}

/// Name prefix of the sibling halo `Glow*` becomes when Line is already painted.
const kLibvisioGlowShapeNamePrefix = 'LibvisioGlow.';

bool isLibvisioGlowPlate(VsdxShape shape) =>
    shape.name.startsWith(kLibvisioGlowShapeNamePrefix);

int? libvisioGlowSourceId(VsdxShape plate) {
  if (!isLibvisioGlowPlate(plate)) return null;
  return int.tryParse(
    plate.name.substring(kLibvisioGlowShapeNamePrefix.length),
  );
}

bool _libvisioGlowEffectOn(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  final glow = shape.glow;
  if (!glow.enabled || glow.sizeInches <= 1e-12) return false;
  if (glow.transparency >= 1 - 1e-9) return false;
  if (shape.is1D) {
    return shape.width.abs() > 1e-9 || shape.height.abs() > 1e-9;
  }
  return shape.width.abs() > 1e-9 && shape.height.abs() > 1e-9;
}

/// `true` when Glow* must become a sibling halo because Line is already in use
/// or because a filled NoLine 2-D / unfilled 2-D stroke can carry the blur
/// as a Gaussian PNG.
///
/// Same-shape `bakeGlowForLibvisio` steals Fill or Line when a PNG plate
/// cannot hang. A default rectangle has both, so Draw would lose the
/// outline if we reused Line. A locked sibling carries the halo as a
/// Gaussian PNG (canvas `_drawGlow`), including theme-only colour
/// resolved through the document theme then Office. Filled NoLine 2-D
/// uses the PNG so Draw does not keep a hard LineWeight outline.
/// Unfilled 2-D uses a PNG ring so Draw does not keep a hard
/// FillForegndTrans ribbon. An unfilled 1-D stroke uses a 2-D PNG plate
/// sized to the glow ribbon (Foreign cannot hang on a zero-height 1-D
/// XForm). A Foreign picture uses the same ring around the image frame.
bool shapeNeedsLibvisioGlowPlateBake(VsdxShape shape) {
  if (!_libvisioGlowEffectOn(shape)) return false;
  if (shape.is1D) return _shapeCanLibvisioGlowStrokePng(shape);
  if (_shapeCanLibvisioGlowPng(shape)) return true;
  if (_shapeCanLibvisioGlowStrokePng(shape)) return true;
  if (_shapeCanLibvisioGlowPicturePng(shape)) return true;
  final paintsFill = _shapePaintsFill(shape, shape.geometries);
  if (!paintsFill && !shape.hasImage) return false;
  return shape.line.hasLine;
}

bool _shapeCanLibvisioGlowPng(VsdxShape shape) {
  if (!_libvisioGlowEffectOn(shape)) return false;
  if (shape.is1D || shape.hasImage) return false;
  if (!_shapePaintsFill(shape, shape.geometries)) return false;
  return _softEdgesSilhouetteKind(shape) != null;
}

/// Unfilled 2-D and 1-D with a stroke: canvas `_drawGlow` blurs a path
/// stroke, not a filled silhouette (that would paint the interior).
/// CompoundType rails are not a token, but the halo is still the path —
/// skipping the bake would drop the glow. 1-D uses a 2-D plate sized to
/// the glow ribbon (canvas inflates zero-area bounds by the glow stroke;
/// a Foreign picture cannot hang on a zero-height 1-D XForm). Theme-only
/// colour resolves into the PNG the same way canvas `_colourOrTheme` does.
bool _shapeCanLibvisioGlowStrokePng(VsdxShape shape) {
  if (!_libvisioGlowEffectOn(shape)) return false;
  if (shape.hasImage) return false;
  if (_shapePaintsFill(shape, shape.geometries)) return false;
  if (!shape.line.hasLine) return false;
  if (shape.is1D) return _glowStrokeRibbonPolygons(shape).isNotEmpty;
  return _softEdgesStrokeSilhouetteKind(shape) != null;
}

/// Foreign pictures: canvas `_drawGlow` blurs the image-frame path even
/// when Fill and Line are off. The plate is 2-D, so a Gaussian PNG ring
/// can hang beside the bitmap. Theme-only colour resolves into that PNG.
bool _shapeCanLibvisioGlowPicturePng(VsdxShape shape) {
  if (!_libvisioGlowEffectOn(shape)) return false;
  if (!shape.hasImage || shape.is1D) return false;
  if (shape.children.isNotEmpty) return false;
  return _foreignFrameSilhouetteKind(shape) != null;
}

bool _shapeNeedsLibvisioGlowPngBake(VsdxShape shape) =>
    _shapeCanLibvisioGlowPng(shape) ||
    _shapeCanLibvisioGlowStrokePng(shape) ||
    _shapeCanLibvisioGlowPicturePng(shape);

/// RGB canvas `_colourOrTheme` would paint. Theme-only Glow* is not a
/// token, so Draw never sees THEMEVAL() here — resolve the slot through
/// [theme], then Office, then the same amber fallback `_drawGlow` uses.
VsdxColor _glowRgbForLibvisioWrite(VsdxGlow glow, VsdxTheme theme) {
  if (glow.color != null) return glow.color!;
  final slot = glow.themeColorIndex;
  if (slot == null) return _kLibvisioGlowFallback;
  return theme.resolve(slot) ??
      VsdxTheme.office.resolve(slot) ??
      _kLibvisioGlowFallback;
}

/// RGB canvas `_colourOrTheme` would stroke. Theme-only LineColor still
/// has to freeze into a Reflection / SoftEdges PNG because those cells
/// are not tokens.
VsdxColor _lineRgbForLibvisioWrite(
  VsdxLine line, [
  VsdxTheme theme = VsdxTheme.empty,
]) {
  if (line.color != null) return line.color!;
  final slot = line.themeColorIndex;
  if (slot == null) return const VsdxColor(0xFF000000);
  return theme.resolve(slot) ??
      VsdxTheme.office.resolve(slot) ??
      const VsdxColor(0xFF000000);
}

/// RGB canvas `_fillColour` would paint. Theme-only FillForegnd still
/// has to freeze into a SoftEdges PNG because `SoftEdgesSize` is not a
/// token.
VsdxColor _fillRgbForLibvisioWrite(
  VsdxFill fill,
  VsdxTheme theme, {
  int? fillMatrix,
}) {
  if (fill.foreground != null) return fill.foreground!;
  final slot = fill.themeForegroundIndex;
  if (slot == null) return const VsdxColor(0xFFFFFFFF);
  return theme.resolveFill(slot, fillMatrix: fillMatrix) ??
      VsdxTheme.office.resolveFill(slot, fillMatrix: fillMatrix) ??
      VsdxTheme.office.resolve(slot) ??
      const VsdxColor(0xFFFFFFFF);
}

/// Hatch `FillBkgnd` canvas would sample. Theme-only background still
/// has to freeze into a SoftEdges PNG with the hatch foreground.
VsdxColor? _fillBackgroundRgbForLibvisioWrite(VsdxFill fill, VsdxTheme theme) {
  if (fill.background != null) return fill.background;
  final slot = fill.themeBackgroundIndex;
  if (slot == null) return null;
  return theme.resolve(slot) ?? VsdxTheme.office.resolve(slot);
}

/// RGB canvas `_colourOrTheme` would sample at a gradient stop. Theme-only
/// GradientStopColor is not a token (`FillGradient` / `LineGradient` never
/// reach `VSDContentCollector`), so SoftEdges / Reflection PNGs freeze the
/// slot through [theme], then Office.
VsdxColor? _gradientStopRgbForLibvisioWrite(
  VsdxGradientStop stop,
  VsdxTheme theme,
) {
  if (stop.color != null) return stop.color;
  final slot = stop.themeColorIndex;
  if (slot == null) return null;
  return theme.resolve(slot) ?? VsdxTheme.office.resolve(slot);
}

({Uint8List png, double padInches})? _glowPngForLibvisioWrite(
  VsdxShape shape,
  VsdxTheme theme,
) {
  final kind = _softEdgesSilhouetteKind(shape);
  if (kind == null) return null;
  final color = _glowRgbForLibvisioWrite(shape.glow, theme);
  final trans = _glowHaloTransparency(shape.glow).clamp(0.0, 1.0);
  final alpha = (color.alpha * (1 - trans)).round().clamp(0, 255);
  final w = shape.width.abs();
  final h = shape.height.abs();
  var innerWidthPx = math.max(8, (w * kLibvisioSoftEdgesPxPerInch).round());
  var innerHeightPx = math.max(8, (h * kLibvisioSoftEdgesPxPerInch).round());
  const maxPx = 1024;
  final longest = math.max(innerWidthPx, innerHeightPx);
  if (longest > maxPx) {
    final scale = maxPx / longest;
    innerWidthPx = math.max(8, (innerWidthPx * scale).round());
    innerHeightPx = math.max(8, (innerHeightPx * scale).round());
  }
  final sigmaPx = shape.glow.sizeInches / w * innerWidthPx;
  final padPx = math.max(1, (sigmaPx * 1.5).round()) * 2;
  final polygon = <({double x, double y})>[];
  if (kind == SoftEdgesSilhouetteKind.polygon) {
    VsdxGeometry? geom;
    for (final candidate in shape.geometries) {
      if (candidate.noShow || candidate.noFill) continue;
      geom = candidate;
      break;
    }
    final inches = geom == null ? null : _softEdgesPolygonInches(shape, geom);
    if (inches == null) return null;
    for (final p in inches) {
      polygon.add((
        x: p.x / w * (innerWidthPx - 1),
        y: (1 - p.y / h) * (innerHeightPx - 1),
      ));
    }
  }
  final png = bakeSilhouetteDropShadowPng(
    innerWidthPx: innerWidthPx,
    innerHeightPx: innerHeightPx,
    padPx: padPx,
    red: color.red,
    green: color.green,
    blue: color.blue,
    alpha: alpha,
    blurSigmaPx: sigmaPx,
    kind: kind,
    polygon: polygon,
  );
  if (png == null) return null;
  return (png: png, padInches: padPx / innerWidthPx * w);
}

List<List<Offset2D>> _glowStrokeRibbonPolygons(VsdxShape shape) {
  return _solidStrokeRibbonPolygons(
    shape,
    halfWidth: math.max(shape.glow.sizeInches, 0.01),
  );
}

({double width, double height, double locPinX, double locPinY})
    _glowStrokePlateLocalBox(VsdxShape shape, double padInches) {
  final pad = padInches < 0 ? 0.0 : padInches;
  final aabb = _polygonsAabb(_glowStrokeRibbonPolygons(shape));
  if (aabb == null) {
    return (
      width: math.max(shape.width.abs(), 1e-6) + 2 * pad,
      height:
          math.max(2 * math.max(shape.glow.sizeInches, 0.01), 1e-6) + 2 * pad,
      locPinX: shape.effectiveLocPinX + pad,
      locPinY: shape.effectiveLocPinY + pad,
    );
  }
  return (
    width: math.max(aabb.maxX - aabb.minX, 1e-6) + 2 * pad,
    height: math.max(aabb.maxY - aabb.minY, 1e-6) + 2 * pad,
    locPinX: shape.effectiveLocPinX - (aabb.minX - pad),
    locPinY: shape.effectiveLocPinY - (aabb.minY - pad),
  );
}

({Uint8List png, double padInches})? _glow1dStrokePngForLibvisioWrite(
  VsdxShape shape,
  VsdxTheme theme,
) {
  final ribbons = _glowStrokeRibbonPolygons(shape);
  final aabb = _polygonsAabb(ribbons);
  if (aabb == null) return null;
  final color = _glowRgbForLibvisioWrite(shape.glow, theme);
  final trans = _glowHaloTransparency(shape.glow).clamp(0.0, 1.0);
  final alpha = (color.alpha * (1 - trans)).round().clamp(0, 255);
  if (alpha <= 0) return null;
  final originX = aabb.minX;
  final originY = aabb.minY;
  final w = math.max(aabb.maxX - aabb.minX, 1e-6);
  final h = math.max(aabb.maxY - aabb.minY, 1e-6);
  const minPx = 16;
  var innerWidthPx = math.max(minPx, (w * kLibvisioSoftEdgesPxPerInch).round());
  var innerHeightPx =
      math.max(minPx, (h * kLibvisioSoftEdgesPxPerInch).round());
  const maxPx = 1024;
  final longest = math.max(innerWidthPx, innerHeightPx);
  if (longest > maxPx) {
    final scale = maxPx / longest;
    innerWidthPx = math.max(minPx, (innerWidthPx * scale).round());
    innerHeightPx = math.max(minPx, (innerHeightPx * scale).round());
  }
  final padInches = shape.glow.sizeInches * 3;
  final padPx = math.max(1, (padInches / w * innerWidthPx).ceil());
  final sigmaPx = shape.glow.sizeInches / w * innerWidthPx;
  final strokeWidthPx =
      math.max(shape.glow.sizeInches * 2, 0.02) / w * innerWidthPx;
  ({double x, double y}) toPx(Offset2D p) => (
        x: padPx + (p.x - originX) / w * (innerWidthPx - 1),
        y: padPx + (1 - (p.y - originY) / h) * (innerHeightPx - 1),
      );
  final ribbonPx = <List<({double x, double y})>>[
    for (final ribbon in ribbons)
      if (ribbon.length >= 3)
        <({double x, double y})>[for (final p in ribbon) toPx(p)],
  ];
  if (ribbonPx.isEmpty) return null;
  final png = bakeStrokedSilhouetteSoftEdgesPng(
    innerWidthPx: innerWidthPx,
    innerHeightPx: innerHeightPx,
    padPx: padPx,
    red: color.red,
    green: color.green,
    blue: color.blue,
    alpha: alpha,
    softSigmaPx: sigmaPx,
    strokeWidthPx: strokeWidthPx,
    ribbons: ribbonPx,
    gaussianBlur: true,
  );
  if (png == null) return null;
  return (png: png, padInches: padInches);
}

({Uint8List png, double padInches})? _glowStrokePngForLibvisioWrite(
  VsdxShape shape,
  VsdxTheme theme,
) {
  if (shape.is1D) return _glow1dStrokePngForLibvisioWrite(shape, theme);
  final kind = _softEdgesStrokeSilhouetteKind(shape) ??
      _foreignFrameSilhouetteKind(shape);
  if (kind == null) return null;
  final color = _glowRgbForLibvisioWrite(shape.glow, theme);
  final trans = _glowHaloTransparency(shape.glow).clamp(0.0, 1.0);
  final alpha = (color.alpha * (1 - trans)).round().clamp(0, 255);
  final w = shape.width.abs();
  final h = shape.height.abs();
  var innerWidthPx = math.max(8, (w * kLibvisioSoftEdgesPxPerInch).round());
  var innerHeightPx = math.max(8, (h * kLibvisioSoftEdgesPxPerInch).round());
  const maxPx = 1024;
  final longest = math.max(innerWidthPx, innerHeightPx);
  if (longest > maxPx) {
    final scale = maxPx / longest;
    innerWidthPx = math.max(8, (innerWidthPx * scale).round());
    innerHeightPx = math.max(8, (innerHeightPx * scale).round());
  }
  final strokeInches = math.max(shape.glow.sizeInches * 2, 0.02);
  final sigmaPx = shape.glow.sizeInches / w * innerWidthPx;
  final padInches = strokeInches / 2 + shape.glow.sizeInches * 3;
  final padPx = math.max(1, (padInches / w * innerWidthPx).ceil());
  final strokeWidthPx = strokeInches / w * innerWidthPx;
  var outer = const <({double x, double y})>[];
  var inner = const <({double x, double y})>[];
  if (kind == SoftEdgesSilhouetteKind.polygon) {
    final geom = _softEdgesStrokeGeometry(shape);
    final inches = geom == null ? null : _softEdgesPolygonInches(shape, geom);
    if (inches == null || inches.length < 3) return null;
    final half = strokeInches / 2;
    final left = offsetPolyline(inches, half, closed: true);
    final right = offsetPolyline(inches, -half, closed: true);
    if (left.length < 3 || right.length < 3) return null;
    ({double x, double y}) toPx(Offset2D p) => (
          x: padPx + p.x / w * (innerWidthPx - 1),
          y: padPx + (1 - p.y / h) * (innerHeightPx - 1),
        );
    outer = <({double x, double y})>[for (final p in left) toPx(p)];
    inner = <({double x, double y})>[for (final p in right) toPx(p)];
  }
  final png = bakeStrokedSilhouetteSoftEdgesPng(
    innerWidthPx: innerWidthPx,
    innerHeightPx: innerHeightPx,
    padPx: padPx,
    red: color.red,
    green: color.green,
    blue: color.blue,
    alpha: alpha,
    softSigmaPx: sigmaPx,
    strokeWidthPx: strokeWidthPx,
    kind: kind,
    outer: outer,
    inner: inner,
    gaussianBlur: true,
  );
  if (png == null) return null;
  return (png: png, padInches: padPx / innerWidthPx * w);
}

List<VsdxGeometry> _glowPlateGeometriesForLibvisioWrite(VsdxShape shape) {
  final out = <VsdxGeometry>[
    for (final geometry in shape.geometries)
      if (!geometry.noShow && !geometry.noFill)
        geometry.copyWith(noFill: true, noLine: false),
  ];
  if (out.isNotEmpty) return out;
  return <VsdxGeometry>[
    VsdxGeometry(
      noFill: true,
      noLine: false,
      commands: <VsdxPathCommand>[
        const MoveTo(0, 0),
        LineTo(shape.width, 0),
        LineTo(shape.width, shape.height),
        LineTo(0, shape.height),
        const LineTo(0, 0),
      ],
    ),
  ];
}

VsdxShape _glowPlateForLibvisioWrite(
  VsdxShape source, {
  required int id,
  required VsdxTheme theme,
}) {
  return VsdxShape(
    id: id,
    name: '$kLibvisioGlowShapeNamePrefix${source.id}',
    pinX: source.pinX,
    pinY: source.pinY,
    width: source.width,
    height: source.height,
    locPinXInches: source.locPinXInches,
    locPinYInches: source.locPinYInches,
    angleRad: source.angleRad,
    flipX: source.flipX,
    flipY: source.flipY,
    geometries: _glowPlateGeometriesForLibvisioWrite(source),
    fill: const VsdxFill(pattern: 0),
    line: _glowLineForLibvisio(
      source.line.copyWith(
        compoundType: 0,
        beginArrow: 0,
        endArrow: 0,
        pattern: 1,
      ),
      source.glow,
      theme,
    ),
    layerMemberIds: source.layerMemberIds,
    locked: true,
    richText: const VsdxRichText(
      runs: <VsdxTextRun>[],
      textBlock: VsdxTextBlock(hideText: true),
    ),
    text: '',
  );
}

VsdxShape _glowPngPlateForLibvisioWrite(
  VsdxShape source, {
  required int id,
  required String imagePartName,
  required double padInches,
}) {
  final pad = padInches < 0 ? 0.0 : padInches;
  final box = source.is1D
      ? _glowStrokePlateLocalBox(source, pad)
      : (
          width: source.width.abs() + pad * 2,
          height: source.height.abs() + pad * 2,
          locPinX: pad > 1e-12
              ? source.effectiveLocPinX + pad
              : source.locPinXInches,
          locPinY: pad > 1e-12
              ? source.effectiveLocPinY + pad
              : source.locPinYInches,
        );
  return VsdxShapeFactory.picture(
    id: id,
    pinX: source.pinX,
    pinY: source.pinY,
    width: box.width,
    height: box.height,
    imagePartName: imagePartName,
    name: '$kLibvisioGlowShapeNamePrefix${source.id}',
  ).copyWith(
    locPinXInches: box.locPinX,
    locPinYInches: box.locPinY,
    angleRad: source.angleRad,
    flipX: source.flipX,
    flipY: source.flipY,
    locked: true,
    layerMemberIds: source.layerMemberIds,
    richText: const VsdxRichText(
      runs: <VsdxTextRun>[],
      textBlock: VsdxTextBlock(hideText: true),
    ),
    text: '',
  );
}

void _collectGlowPlateIds(List<VsdxShape> shapes, Map<int, int> into) {
  for (final shape in shapes) {
    final sourceId = libvisioGlowSourceId(shape);
    if (sourceId != null) into[sourceId] = shape.id;
    _collectGlowPlateIds(shape.children, into);
  }
}

bool pageNeedsLibvisioGlowPlateBake(VsdxPage page) {
  var hasPlate = false;
  var needs = false;
  void walk(VsdxShape shape) {
    if (isLibvisioGlowPlate(shape)) {
      hasPlate = true;
    } else if (shapeNeedsLibvisioGlowPlateBake(shape)) {
      needs = true;
    }
    for (final child in shape.children) {
      walk(child);
    }
  }

  for (final shape in page.shapes) {
    walk(shape);
  }
  return hasPlate || needs;
}

List<VsdxShape> _bakeGlowPlateTree(
  List<VsdxShape> shapes, {
  required Map<int, int> plateIds,
  required int Function() nextId,
  required String Function(int shapeId) allocatePart,
  required void Function(VsdxImage image) addImage,
  required VsdxTheme theme,
}) {
  final out = <VsdxShape>[];
  var changed = false;
  for (final shape in shapes) {
    if (isLibvisioGlowPlate(shape)) {
      changed = true;
      continue;
    }
    var next = shape;
    if (shape.children.isNotEmpty) {
      final children = _bakeGlowPlateTree(
        shape.children,
        plateIds: plateIds,
        nextId: nextId,
        allocatePart: allocatePart,
        addImage: addImage,
        theme: theme,
      );
      if (!identical(children, shape.children)) {
        next = shape.copyWith(children: children);
        changed = true;
      }
    }
    if (shapeNeedsLibvisioGlowPlateBake(next)) {
      VsdxShape? plate;
      if (_shapeNeedsLibvisioGlowPngBake(next)) {
        final payload = _shapeCanLibvisioGlowPng(next)
            ? _glowPngForLibvisioWrite(next, theme)
            : _glowStrokePngForLibvisioWrite(next, theme);
        if (payload != null) {
          final part = allocatePart(next.id);
          addImage(
            VsdxImage(
              partName: part,
              bytes: payload.png,
              mimeType: 'image/png',
            ),
          );
          plate = _glowPngPlateForLibvisioWrite(
            next,
            id: plateIds[next.id] ?? nextId(),
            imagePartName: part,
            padInches: payload.padInches,
          );
        }
      }
      if (plate == null && !_shapeNeedsLibvisioGlowPngBake(next)) {
        plate = _glowPlateForLibvisioWrite(
          next,
          id: plateIds[next.id] ?? nextId(),
          theme: theme,
        );
      }
      if (plate != null && (plate.geometries.isNotEmpty || plate.hasImage)) {
        out.add(plate);
        changed = true;
      }
    } else {
      final existingId = plateIds[next.id];
      if (existingId != null) {
        VsdxShape? kept;
        for (final candidate in shapes) {
          if (candidate.id == existingId) {
            kept = candidate;
            break;
          }
        }
        if (kept != null) {
          out.add(kept);
        }
      }
    }
    out.add(next);
    if (!identical(next, shape)) changed = true;
  }
  return changed ? out : shapes;
}

/// Insert (or keep) the sibling halos Draw uses when Glow cannot steal Line,
/// including the Gaussian PNG a filled NoLine 2-D, unfilled 2-D stroke,
/// or unfilled 1-D stroke uses.
VsdxDocument bakeGlowPlateForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  var registry = document.images;
  final used = <String>{
    for (final image in document.images.all) image.partName,
  };
  String allocatePart(int shapeId) {
    var name = '/visio/media/image_lo_glow_$shapeId.png';
    var n = 0;
    while (used.contains(name) || registry.findByPart(name) != null) {
      n++;
      name = '/visio/media/image_lo_glow_${shapeId}_$n.png';
    }
    used.add(name);
    return name;
  }

  final pages = <VsdxPage>[];
  var changed = false;
  for (final page in document.pages) {
    if (!pageNeedsLibvisioGlowPlateBake(page)) {
      pages.add(page);
      continue;
    }
    final plateIds = <int, int>{};
    _collectGlowPlateIds(page.shapes, plateIds);
    var nextId = _maxShapeId(page.shapes) + 1;
    final shapes = _bakeGlowPlateTree(
      page.shapes,
      plateIds: plateIds,
      nextId: () => nextId++,
      allocatePart: allocatePart,
      addImage: (image) {
        registry = registry.withImage(image);
        changed = true;
      },
      theme: document.theme,
    );
    if (identical(shapes, page.shapes)) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      changed = true;
    }
  }
  if (!changed) return document;
  return document.copyWith(pages: pages, images: registry);
}

/// Name prefix of the jiggle strokes `User.veSketch` becomes for Draw.
const kLibvisioSketchShapeNamePrefix = 'LibvisioSketch.';

/// Pixel density canvas / SVG use for draw.io jiggle, so the baked offsets
/// match the editor's two-pass Sketch treatment.
const kLibvisioSketchPxPerInch = 96.0;

bool isLibvisioSketchPlate(VsdxShape shape) =>
    shape.name.startsWith(kLibvisioSketchShapeNamePrefix);

int? libvisioSketchSourceId(VsdxShape plate) {
  if (!isLibvisioSketchPlate(plate)) return null;
  return int.tryParse(plate.name.split('.').last);
}

/// Name prefix of the top-light sibling `User.veGlass` becomes for Draw.
const kLibvisioGlassShapeNamePrefix = 'LibvisioGlass.';

bool isLibvisioGlassPlate(VsdxShape shape) =>
    shape.name.startsWith(kLibvisioGlassShapeNamePrefix);

int? libvisioGlassSourceId(VsdxShape plate) {
  if (!isLibvisioGlassPlate(plate)) return null;
  return int.tryParse(
    plate.name.substring(kLibvisioGlassShapeNamePrefix.length),
  );
}

/// Name prefix of the text-frame stroke `User.veLabelBorderColor` becomes.
const kLibvisioLabelBorderShapeNamePrefix = 'LibvisioLabelBorder.';

/// Name prefix of the filled-shape stroke ribbon Draw uses for LineColorTrans.
const kLibvisioStrokeRibbonShapeNamePrefix = 'LibvisioStrokeRibbon.';

/// Pixel density canvas / SVG use for the 1px label-border hairline.
const kLibvisioLabelBorderPxPerInch = 96.0;

/// Pixel density canvas / SVG use for draw.io `labelPadding`.
const kLibvisioLabelPaddingPxPerInch = 96.0;

/// Name prefix of the feathered PNG sibling geometry SoftEdges becomes.
const kLibvisioSoftEdgesShapeNamePrefix = 'LibvisioSoftEdges.';

/// Pixel density of the SourceAlpha PNG geometry SoftEdges bakes for Draw.
const kLibvisioSoftEdgesPxPerInch = 96.0;

/// Name prefix of the Gaussian PNG sibling ShadowBlur becomes.
const kLibvisioShadowShapeNamePrefix = 'LibvisioShadow.';

bool isLibvisioSoftEdgesPlate(VsdxShape shape) =>
    shape.name.startsWith(kLibvisioSoftEdgesShapeNamePrefix);

int? libvisioSoftEdgesSourceId(VsdxShape plate) {
  if (!isLibvisioSoftEdgesPlate(plate)) return null;
  return int.tryParse(
    plate.name.substring(kLibvisioSoftEdgesShapeNamePrefix.length),
  );
}

/// Name prefix of the per-run siblings mixed Character Highlight becomes.
const kLibvisioHighlightShapeNamePrefix = 'LibvisioHighlight.';

bool isLibvisioHighlightPlate(VsdxShape shape) =>
    shape.name.startsWith(kLibvisioHighlightShapeNamePrefix);

int? libvisioHighlightSourceId(VsdxShape plate) {
  if (!isLibvisioHighlightPlate(plate)) return null;
  return int.tryParse(plate.name.split('.').last);
}

/// `true` when a save already inserted Highlight siblings for [sourceId].
bool pageHasLibvisioHighlightPlate(VsdxPage page, int sourceId) {
  bool walk(VsdxShape shape) {
    if (libvisioHighlightSourceId(shape) == sourceId) return true;
    for (final child in shape.children) {
      if (walk(child)) return true;
    }
    return false;
  }

  for (final shape in page.shapes) {
    if (walk(shape)) return true;
  }
  return false;
}

/// Name prefix of the per-glyph siblings `User.veCurvedText` becomes.
const kLibvisioCurvedTextShapeNamePrefix = 'LibvisioCurved.';

bool isLibvisioCurvedTextPlate(VsdxShape shape) =>
    shape.name.startsWith(kLibvisioCurvedTextShapeNamePrefix);

int? libvisioCurvedTextSourceId(VsdxShape plate) {
  if (!isLibvisioCurvedTextPlate(plate)) return null;
  return int.tryParse(plate.name.split('.').last);
}

/// Name prefix of the per-line siblings `User.veShapeInside` becomes.
const kLibvisioShapeInsideShapeNamePrefix = 'LibvisioShapeInside.';

/// Pixel density canvas / SVG use for draw.io `shapeInside` padding.
const kLibvisioShapeInsidePxPerInch = 96.0;

bool isLibvisioShapeInsidePlate(VsdxShape shape) =>
    shape.name.startsWith(kLibvisioShapeInsideShapeNamePrefix);

int? libvisioShapeInsideSourceId(VsdxShape plate) {
  if (!isLibvisioShapeInsidePlate(plate)) return null;
  return int.tryParse(plate.name.split('.').last);
}

bool isLibvisioShadowPlate(VsdxShape shape) =>
    shape.name.startsWith(kLibvisioShadowShapeNamePrefix);

int? libvisioShadowSourceId(VsdxShape plate) {
  if (!isLibvisioShadowPlate(plate)) return null;
  return int.tryParse(
    plate.name.substring(kLibvisioShadowShapeNamePrefix.length),
  );
}

bool isLibvisioLabelBorderPlate(VsdxShape shape) =>
    shape.name.startsWith(kLibvisioLabelBorderShapeNamePrefix);

int? libvisioLabelBorderSourceId(VsdxShape plate) {
  if (!isLibvisioLabelBorderPlate(plate)) return null;
  return int.tryParse(
    plate.name.substring(kLibvisioLabelBorderShapeNamePrefix.length),
  );
}

bool isLibvisioStrokeRibbonPlate(VsdxShape shape) =>
    shape.name.startsWith(kLibvisioStrokeRibbonShapeNamePrefix);

int? libvisioStrokeRibbonSourceId(VsdxShape plate) {
  if (!isLibvisioStrokeRibbonPlate(plate)) return null;
  return int.tryParse(
    plate.name.substring(kLibvisioStrokeRibbonShapeNamePrefix.length),
  );
}

/// `true` when [shape] is a render-only sibling a save added for Draw.
///
/// These plates carry an effect `tokens.txt` cannot express, so they appear
/// in the saved package (and therefore after a reopen) even though the
/// authoring model only had the effect cell. Round-trip checks should skip
/// them; a second save recognises and reuses them instead of stacking.
bool isLibvisioBakePlate(VsdxShape shape) =>
    isLibvisioSketchPlate(shape) ||
    isLibvisioGlowPlate(shape) ||
    isLibvisioReflectionPlate(shape) ||
    isLibvisioGlassPlate(shape) ||
    isLibvisioLabelBorderPlate(shape) ||
    isLibvisioStrokeRibbonPlate(shape) ||
    isLibvisioSoftEdgesPlate(shape) ||
    isLibvisioShadowPlate(shape) ||
    isLibvisioPageShadowPlate(shape) ||
    isLibvisioCurvedTextPlate(shape) ||
    isLibvisioShapeInsidePlate(shape) ||
    isLibvisioHighlightPlate(shape) ||
    shape.name == kLibvisioPageColorShapeName;

bool _isLibvisioBakePlate(VsdxShape shape) => isLibvisioBakePlate(shape);

bool shapeNeedsLibvisioSketchStrokeBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  if (!shape.sketchEffect) return false;
  if (!shape.line.hasLine) return false;
  return shape.width.abs() > 1e-12 || shape.height.abs() > 1e-12;
}

bool shapeNeedsLibvisioSketchFillBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  return shape.usesSketchPatternFill;
}

bool shapeNeedsLibvisioSketchBake(VsdxShape shape) =>
    shapeNeedsLibvisioSketchStrokeBake(shape) ||
    shapeNeedsLibvisioSketchFillBake(shape);

double _hatchAngleDelta(double a, double b) {
  var d = (a - b) % 180.0;
  if (d < 0) d += 180.0;
  if (d > 90.0) d = 180.0 - d;
  return d;
}

/// Classic FillPattern 2–24 whose hatch is closest to the sketch fill.
int? sketchFillPatternForLibvisioWrite(VsdxShape shape) {
  if (!shape.usesSketchPatternFill) return null;
  final dense = shape.sketchHachureGapPx / kLibvisioSketchPxPerInch < 0.075;
  final style = switch (shape.effectiveSketchFillStyle) {
    VsdxSketchFillStyle.crossHatch => VsdxHatchStyle.double,
    VsdxSketchFillStyle.dots => VsdxHatchStyle.triple,
    VsdxSketchFillStyle.hachure ||
    VsdxSketchFillStyle.auto ||
    VsdxSketchFillStyle.solid =>
      VsdxHatchStyle.single,
  };
  final angle = shape.sketchHachureAngleDegrees;
  var bestId = dense ? 13 : 6;
  var bestDelta = 1e9;
  for (var id = 2; id <= 24; id++) {
    final spec = libvisioHatchSpec(id);
    if (spec == null || spec.style != style) continue;
    if ((spec.distanceInches < 0.075) != dense) continue;
    final delta = _hatchAngleDelta(angle, spec.angleDegrees.toDouble());
    if (delta < bestDelta) {
      bestDelta = delta;
      bestId = id;
    }
  }
  return bestId;
}

VsdxPathCommand _translateSketchCommand(
  VsdxPathCommand command, {
  required double dx,
  required double dy,
  required double width,
  required double height,
}) {
  Offset2D shift(double x, double y, {bool relX = false, bool relY = false}) {
    final ox = relX ? (width.abs() < 1e-12 ? 0.0 : dx / width) : dx;
    final oy = relY ? (height.abs() < 1e-12 ? 0.0 : dy / height) : dy;
    return Offset2D(x + ox, y + oy);
  }

  return switch (command) {
    MoveTo(:final x, :final y) => MoveTo(shift(x, y).x, shift(x, y).y),
    LineTo(:final x, :final y) => LineTo(shift(x, y).x, shift(x, y).y),
    RelMoveTo(:final fx, :final fy) => RelMoveTo(
        shift(fx, fy, relX: true, relY: true).x,
        shift(fx, fy, relX: true, relY: true).y,
      ),
    RelLineTo(:final fx, :final fy) => RelLineTo(
        shift(fx, fy, relX: true, relY: true).x,
        shift(fx, fy, relX: true, relY: true).y,
      ),
    CubBezTo(:final x, :final y, :final x1, :final y1, :final x2, :final y2) =>
      CubBezTo(
        x: shift(x, y).x,
        y: shift(x, y).y,
        x1: shift(x1, y1).x,
        y1: shift(x1, y1).y,
        x2: shift(x2, y2).x,
        y2: shift(x2, y2).y,
      ),
    RelCubBezTo(
      :final fx,
      :final fy,
      :final fx1,
      :final fy1,
      :final fx2,
      :final fy2,
    ) =>
      RelCubBezTo(
        fx: shift(fx, fy, relX: true, relY: true).x,
        fy: shift(fx, fy, relX: true, relY: true).y,
        fx1: shift(fx1, fy1, relX: true, relY: true).x,
        fy1: shift(fx1, fy1, relX: true, relY: true).y,
        fx2: shift(fx2, fy2, relX: true, relY: true).x,
        fy2: shift(fx2, fy2, relX: true, relY: true).y,
      ),
    QuadBezTo(:final x, :final y, :final x1, :final y1) => QuadBezTo(
        x: shift(x, y).x,
        y: shift(x, y).y,
        x1: shift(x1, y1).x,
        y1: shift(x1, y1).y,
      ),
    RelQuadBezTo(:final fx, :final fy, :final fx1, :final fy1) => RelQuadBezTo(
        fx: shift(fx, fy, relX: true, relY: true).x,
        fy: shift(fx, fy, relX: true, relY: true).y,
        fx1: shift(fx1, fy1, relX: true, relY: true).x,
        fy1: shift(fx1, fy1, relX: true, relY: true).y,
      ),
    ArcTo(:final x, :final y, :final bow) =>
      ArcTo(x: shift(x, y).x, y: shift(x, y).y, bow: bow),
    RelArcTo(:final fx, :final fy, :final fbow) => RelArcTo(
        fx: shift(fx, fy, relX: true, relY: true).x,
        fy: shift(fx, fy, relX: true, relY: true).y,
        fbow: fbow,
      ),
    EllipticalArcTo(
      :final x,
      :final y,
      :final controlX,
      :final controlY,
      :final angle,
      :final eccentricity,
    ) =>
      EllipticalArcTo(
        x: shift(x, y).x,
        y: shift(x, y).y,
        controlX: shift(controlX, controlY).x,
        controlY: shift(controlX, controlY).y,
        angle: angle,
        eccentricity: eccentricity,
      ),
    RelEllipticalArcTo(
      :final fx,
      :final fy,
      :final fcx,
      :final fcy,
      :final angle,
      :final eccentricity,
    ) =>
      RelEllipticalArcTo(
        fx: shift(fx, fy, relX: true, relY: true).x,
        fy: shift(fx, fy, relX: true, relY: true).y,
        fcx: shift(fcx, fcy, relX: true, relY: true).x,
        fcy: shift(fcx, fcy, relX: true, relY: true).y,
        angle: angle,
        eccentricity: eccentricity,
      ),
    EllipseCmd(
      :final cx,
      :final cy,
      :final aX,
      :final aY,
      :final bX,
      :final bY
    ) =>
      EllipseCmd(
        cx: shift(cx, cy).x,
        cy: shift(cx, cy).y,
        aX: shift(aX, aY).x,
        aY: shift(aX, aY).y,
        bX: shift(bX, bY).x,
        bY: shift(bX, bY).y,
      ),
    PolylineTo(
      :final x,
      :final y,
      :final vertices,
      :final relative,
      :final vertsRelative,
      :final vertsYRelative,
    ) =>
      PolylineTo(
        x: shift(x, y, relX: relative, relY: relative).x,
        y: shift(x, y, relX: relative, relY: relative).y,
        vertices: <Offset2D>[
          for (final v in vertices)
            shift(v.x, v.y, relX: vertsRelative, relY: vertsYRelative),
        ],
        relative: relative,
        vertsRelative: vertsRelative,
        vertsYRelative: vertsYRelative,
      ),
    InfiniteLineCmd(:final x, :final y, :final a, :final b, :final relative) =>
      InfiniteLineCmd(
        x: shift(x, y, relX: relative, relY: relative).x,
        y: shift(x, y, relX: relative, relY: relative).y,
        a: shift(a, b, relX: relative, relY: relative).x,
        b: shift(a, b, relX: relative, relY: relative).y,
        relative: relative,
      ),
    SplineStart(
      :final x,
      :final y,
      :final a,
      :final b,
      :final c,
      :final degree,
      :final relative,
    ) =>
      SplineStart(
        x: shift(x, y, relX: relative, relY: relative).x,
        y: shift(x, y, relX: relative, relY: relative).y,
        a: a,
        b: b,
        c: c,
        degree: degree,
        relative: relative,
      ),
    SplineKnot(:final x, :final y, :final knot, :final relative) => SplineKnot(
        x: shift(x, y, relX: relative, relY: relative).x,
        y: shift(x, y, relX: relative, relY: relative).y,
        knot: knot,
        relative: relative,
      ),
    NurbsTo(
      :final x,
      :final y,
      :final controlPoints,
      :final weights,
      :final knots,
      :final degree,
      :final relative,
      :final cpRelative,
      :final cpYRelative,
    ) =>
      NurbsTo(
        x: shift(x, y, relX: relative, relY: relative).x,
        y: shift(x, y, relX: relative, relY: relative).y,
        controlPoints: <Offset2D>[
          for (final p in controlPoints)
            shift(p.x, p.y, relX: cpRelative, relY: cpYRelative),
        ],
        weights: weights,
        knots: knots,
        degree: degree,
        relative: relative,
        cpRelative: cpRelative,
        cpYRelative: cpYRelative,
      ),
  };
}

VsdxGeometry _translateSketchGeometry(
  VsdxGeometry geometry,
  Offset2D offset,
  VsdxShape shape,
) {
  return geometry.copyWith(
    noFill: true,
    noLine: false,
    commandFormulas: const <Map<String, String>>[],
    commands: <VsdxPathCommand>[
      for (final command in geometry.commands)
        _translateSketchCommand(
          command,
          dx: offset.x,
          dy: offset.y,
          width: shape.width,
          height: shape.height,
        ),
    ],
  );
}

List<VsdxGeometry> _sketchStrokeGeometriesForLibvisioWrite(
  VsdxShape shape,
  Offset2D offset,
) {
  final fromLine = <VsdxGeometry>[
    for (final geometry in shape.geometries)
      if (!geometry.noShow && !geometry.noLine && !geometry.hitBox)
        _translateSketchGeometry(geometry, offset, shape),
  ];
  if (fromLine.isNotEmpty) return fromLine;
  return <VsdxGeometry>[
    for (final geometry in shape.geometries)
      if (!geometry.noShow && !geometry.noFill)
        _translateSketchGeometry(geometry, offset, shape),
  ];
}

VsdxShape _sketchPlateForLibvisioWrite(
  VsdxShape source, {
  required int id,
  required int pass,
  required Offset2D offset,
}) {
  return VsdxShape(
    id: id,
    name: '$kLibvisioSketchShapeNamePrefix$pass.${source.id}',
    pinX: source.pinX,
    pinY: source.pinY,
    width: source.width,
    height: source.height,
    locPinXInches: source.locPinXInches,
    locPinYInches: source.locPinYInches,
    angleRad: source.angleRad,
    flipX: source.flipX,
    flipY: source.flipY,
    geometries: _sketchStrokeGeometriesForLibvisioWrite(source, offset),
    fill: const VsdxFill(pattern: 0),
    line: source.line.copyWith(beginArrow: 0, endArrow: 0),
    layerMemberIds: source.layerMemberIds,
    locked: true,
    richText: const VsdxRichText(
      runs: <VsdxTextRun>[],
      textBlock: VsdxTextBlock(hideText: true),
    ),
    text: '',
  );
}

VsdxShape _sourceForLibvisioSketchWrite(VsdxShape shape) {
  var next = shape;
  if (shapeNeedsLibvisioSketchStrokeBake(shape)) {
    var geoms = <VsdxGeometry>[
      for (final geometry in shape.geometries)
        geometry.noLine ? geometry : geometry.copyWith(noLine: true),
    ];
    var line = shape.line;
    if (_hasArrowheads(shape.line) && _shapeHasOpenLineEndings(shape)) {
      final arrows = bakeArrowGeometriesForLibvisio(shape);
      if (arrows.isNotEmpty) {
        geoms = <VsdxGeometry>[...geoms, ...arrows];
        line = line.copyWith(beginArrow: 0, endArrow: 0);
        if (!next.fill.hasFill) {
          next = next.copyWith(
            fill: VsdxFill(
              foreground: _lineRgbForLibvisioWrite(line),
              pattern: 1,
              foregroundTransparency: line.transparency.clamp(0.0, 1.0),
            ),
          );
        }
      }
    }
    next = next.copyWith(geometries: geoms, line: line);
  }
  final pattern = sketchFillPatternForLibvisioWrite(shape);
  if (pattern != null) {
    next = next.copyWith(
      fill: next.fill.copyWith(
        pattern: pattern,
        backgroundTransparency: 1,
        gradient: null,
      ),
    );
  }
  final others = <VsdxUserCell>[
    for (final cell in next.userCells)
      if (cell.name != VsdxShape.userSketchEffect) cell,
  ];
  return next.copyWith(
    userCells: <VsdxUserCell>[
      ...others,
      const VsdxUserCell(name: VsdxShape.userSketchEffect, value: '0'),
    ],
  );
}

void _collectSketchPlateIds(List<VsdxShape> shapes, Map<String, int> into) {
  for (final shape in shapes) {
    if (isLibvisioSketchPlate(shape)) into[shape.name] = shape.id;
    _collectSketchPlateIds(shape.children, into);
  }
}

bool pageNeedsLibvisioSketchBake(VsdxPage page) {
  var hasPlate = false;
  var needs = false;
  void walk(VsdxShape shape) {
    if (isLibvisioSketchPlate(shape)) {
      hasPlate = true;
    } else if (shapeNeedsLibvisioSketchBake(shape)) {
      needs = true;
    }
    for (final child in shape.children) {
      walk(child);
    }
  }

  for (final shape in page.shapes) {
    walk(shape);
  }
  return hasPlate || needs;
}

List<VsdxShape> _bakeSketchTree(
  List<VsdxShape> shapes, {
  required Map<String, int> plateIds,
  required int Function() nextId,
}) {
  final out = <VsdxShape>[];
  var changed = false;
  for (final shape in shapes) {
    if (isLibvisioSketchPlate(shape)) {
      changed = true;
      continue;
    }
    var next = shape;
    if (shape.children.isNotEmpty) {
      final children = _bakeSketchTree(
        shape.children,
        plateIds: plateIds,
        nextId: nextId,
      );
      if (!identical(children, shape.children)) {
        next = shape.copyWith(children: children);
        changed = true;
      }
    }
    if (shapeNeedsLibvisioSketchBake(next)) {
      final source = _sourceForLibvisioSketchWrite(next);
      out.add(source);
      if (shapeNeedsLibvisioSketchStrokeBake(next)) {
        final offsets = drawioSketchStrokeOffsets(
          next.id,
          next.sketchJiggle,
          pxPerInch: kLibvisioSketchPxPerInch,
        );
        for (var pass = 0; pass < offsets.length; pass++) {
          final name = '$kLibvisioSketchShapeNamePrefix$pass.${next.id}';
          final plate = _sketchPlateForLibvisioWrite(
            next,
            id: plateIds[name] ?? nextId(),
            pass: pass,
            offset: offsets[pass],
          );
          if (plate.geometries.isNotEmpty) {
            out.add(plate);
            changed = true;
          }
        }
      }
      changed = true;
      continue;
    }
    final kept = <VsdxShape>[];
    for (var pass = 0; pass < 2; pass++) {
      final name = '$kLibvisioSketchShapeNamePrefix$pass.${next.id}';
      final existingId = plateIds[name];
      if (existingId == null) continue;
      for (final candidate in shapes) {
        if (candidate.id == existingId) {
          kept.add(candidate);
          break;
        }
      }
    }
    out.add(next);
    out.addAll(kept);
    if (kept.isNotEmpty || !identical(next, shape)) changed = true;
  }
  return changed ? out : shapes;
}

VsdxPage bakeSketchPageForLibvisioWrite(VsdxPage page) {
  if (!pageNeedsLibvisioSketchBake(page)) return page;
  final plateIds = <String, int>{};
  _collectSketchPlateIds(page.shapes, plateIds);
  var nextId = _maxShapeId(page.shapes) + 1;
  return page.copyWith(
    shapes: _bakeSketchTree(
      page.shapes,
      plateIds: plateIds,
      nextId: () => nextId++,
    ),
  );
}

/// Insert (or keep) the Sketch strokes / hatch Draw can actually collect.
VsdxDocument bakeSketchForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var changed = false;
  for (final page in document.pages) {
    final next = bakeSketchPageForLibvisioWrite(page);
    changed |= !identical(next, page);
    pages.add(next);
  }
  return changed ? document.copyWith(pages: pages) : document;
}

/// Canvas / SVG glass highlight uses `(1 - FillForegndTrans) * colour.alpha`.
double _glassFillOpacity(VsdxShape shape) {
  var alpha = 1 - shape.fill.foregroundTransparency.clamp(0.0, 1.0);
  final color = shape.fill.foreground;
  if (color != null) alpha *= color.alpha / 255.0;
  return alpha.clamp(0.0, 1.0);
}

/// `true` when `User.veGlass` must become a sibling Draw can actually fill.
///
/// libvisio never reads User rows. Fill is shape-level, so the white wave
/// cannot share the source; a locked NoLine sibling carries a white
/// FillForegndTrans sheen matching the canvas 0.9→0.1 top-light average,
/// then `veGlass` is written 0. A classic FillPattern 25–40 would move
/// those trans values onto gradient stops at parse, and a second save
/// would write opaque white.
bool shapeNeedsLibvisioGlassBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  if (!shape.glassEffect) return false;
  if (!shape.supportsGlassEffect) return false;
  if (shape.width.abs() <= 1e-9 || shape.height.abs() <= 1e-9) return false;
  return _glassFillOpacity(shape) > 1e-9;
}

List<VsdxPathCommand> _glassHighlightCommands(VsdxShape shape) {
  final w = shape.width.abs() < 1e-12 ? 1.0 : shape.width;
  final h = shape.height.abs() < 1e-12 ? 1.0 : shape.height;
  final sw = math.max(0.0, shape.line.weightInches / 2);
  final x0 = -sw / w;
  final x1 = (w + sw) / w;
  final yTop = (h + sw) / h;
  return <VsdxPathCommand>[
    RelMoveTo(x0, yTop),
    RelLineTo(x0, 0.6),
    RelQuadBezTo(fx: x1, fy: 0.6, fx1: 0.5, fy1: 0.3),
    RelLineTo(x1, yTop),
    RelLineTo(x0, yTop),
  ];
}

VsdxFill _glassHighlightFill(VsdxShape source) {
  final alpha = _glassFillOpacity(source);
  return VsdxFill(
    foreground: VsdxColor.white,
    pattern: 1,
    foregroundTransparency: (1 - 0.55 * alpha).clamp(0.0, 1.0),
  );
}

VsdxShape _glassPlateForLibvisioWrite(VsdxShape source, {required int id}) {
  return VsdxShape(
    id: id,
    name: '$kLibvisioGlassShapeNamePrefix${source.id}',
    pinX: source.pinX,
    pinY: source.pinY,
    width: source.width,
    height: source.height,
    locPinXInches: source.locPinXInches,
    locPinYInches: source.locPinYInches,
    angleRad: source.angleRad,
    flipX: source.flipX,
    flipY: source.flipY,
    geometries: <VsdxGeometry>[
      VsdxGeometry(
        noFill: false,
        noLine: true,
        commands: _glassHighlightCommands(source),
      ),
    ],
    fill: _glassHighlightFill(source),
    line: const VsdxLine(pattern: 0),
    layerMemberIds: source.layerMemberIds,
    locked: true,
    richText: const VsdxRichText(
      runs: <VsdxTextRun>[],
      textBlock: VsdxTextBlock(hideText: true),
    ),
    text: '',
  );
}

VsdxShape _sourceForLibvisioGlassWrite(VsdxShape shape) {
  final others = <VsdxUserCell>[
    for (final cell in shape.userCells)
      if (cell.name != VsdxShape.userGlassEffect) cell,
  ];
  return shape.copyWith(
    userCells: <VsdxUserCell>[
      ...others,
      const VsdxUserCell(name: VsdxShape.userGlassEffect, value: '0'),
    ],
  );
}

void _collectGlassPlateIds(List<VsdxShape> shapes, Map<int, int> into) {
  for (final shape in shapes) {
    final sourceId = libvisioGlassSourceId(shape);
    if (sourceId != null) into[sourceId] = shape.id;
    _collectGlassPlateIds(shape.children, into);
  }
}

bool pageNeedsLibvisioGlassBake(VsdxPage page) {
  var hasPlate = false;
  var needs = false;
  void walk(VsdxShape shape) {
    if (isLibvisioGlassPlate(shape)) {
      hasPlate = true;
    } else if (shapeNeedsLibvisioGlassBake(shape)) {
      needs = true;
    }
    for (final child in shape.children) {
      walk(child);
    }
  }

  for (final shape in page.shapes) {
    walk(shape);
  }
  return hasPlate || needs;
}

List<VsdxShape> _bakeGlassTree(
  List<VsdxShape> shapes, {
  required Map<int, int> plateIds,
  required int Function() nextId,
}) {
  final out = <VsdxShape>[];
  var changed = false;
  for (final shape in shapes) {
    if (isLibvisioGlassPlate(shape)) {
      changed = true;
      continue;
    }
    var next = shape;
    if (shape.children.isNotEmpty) {
      final children = _bakeGlassTree(
        shape.children,
        plateIds: plateIds,
        nextId: nextId,
      );
      if (!identical(children, shape.children)) {
        next = shape.copyWith(children: children);
        changed = true;
      }
    }
    if (shapeNeedsLibvisioGlassBake(next)) {
      out.add(_sourceForLibvisioGlassWrite(next));
      final plate = _glassPlateForLibvisioWrite(
        next,
        id: plateIds[next.id] ?? nextId(),
      );
      out.add(plate);
      changed = true;
      continue;
    }
    out.add(next);
    final existingId = plateIds[next.id];
    if (existingId != null) {
      VsdxShape? kept;
      for (final candidate in shapes) {
        if (candidate.id == existingId) {
          kept = candidate;
          break;
        }
      }
      if (kept != null) {
        out.add(kept);
        changed = true;
      }
    }
    if (!identical(next, shape)) changed = true;
  }
  return changed ? out : shapes;
}

VsdxPage bakeGlassPageForLibvisioWrite(VsdxPage page) {
  if (!pageNeedsLibvisioGlassBake(page)) return page;
  final plateIds = <int, int>{};
  _collectGlassPlateIds(page.shapes, plateIds);
  var nextId = _maxShapeId(page.shapes) + 1;
  return page.copyWith(
    shapes: _bakeGlassTree(
      page.shapes,
      plateIds: plateIds,
      nextId: () => nextId++,
    ),
  );
}

/// Insert (or keep) the white top-light siblings Draw uses for `veGlass`.
VsdxDocument bakeGlassForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var changed = false;
  for (final page in document.pages) {
    final next = bakeGlassPageForLibvisioWrite(page);
    changed |= !identical(next, page);
    pages.add(next);
  }
  return changed ? document.copyWith(pages: pages) : document;
}

/// `true` when a filled 2-D stroke must become a sibling ribbon Draw paints.
///
/// FillPattern is already the body, so LineColorTrans / LineGradient cannot
/// steal it the way an unfilled ribbon does. `_lineProperties` also never
/// emits `svg:stroke-miterlimit`. CompoundType is not a token either, so
/// skipping the bake would drop the wash onto hard parallel rails. Built-in
/// LinePattern 2–23 and custom `veDashPattern` become per-dash filled
/// ribbons so Draw keeps the gaps — a native dashed stroke would be
/// opaque. Open-path Begin/EndArrow become filled Geometry on that sibling
/// so Draw does not hang markers on a dropped line; the plate fill is the
/// stroke colour, so heads stay LineColor not FillPattern. A locked
/// NoLine sibling carries the stroke silhouette (FillForegndTrans /
/// FillGradient / CompoundType 1–4 rails / the long miter outline), then
/// the source line is dropped.
bool shapeNeedsLibvisioFilledStrokeRibbonBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  if (!shape.line.hasLine) return false;
  if (shape.line.softEdgesInches > 1e-6) return false;
  if (!_shapePaintsFill(shape, shape.geometries)) return false;
  if (!shape.line.hasGradient &&
      shape.line.transparency <= 1e-9 &&
      !_shapeHasLibvisioMiterSpikeCorners(shape)) {
    return false;
  }
  return _filledStrokeRibbonGeometries(shape).isNotEmpty;
}

List<VsdxGeometry> _geometriesFromRibbonPolygons(
  List<List<Offset2D>> polygons,
) {
  final out = <VsdxGeometry>[];
  for (final poly in polygons) {
    if (poly.length < 3) continue;
    final commands = polylineCommands(poly, closed: true);
    if (commands.length < 3) continue;
    out.add(VsdxGeometry(noFill: false, noLine: true, commands: commands));
  }
  return out;
}

List<VsdxGeometry> _filledStrokeRibbonGeometries(VsdxShape shape) {
  late final List<VsdxGeometry> out;
  if (shape.line.compoundType != 0) {
    out = _geometriesFromRibbonPolygons(
      _softEdgesCompoundRibbonPolygons(shape),
    );
  } else if (_shapeHasSoftEdgesDashes(shape)) {
    out = _geometriesFromRibbonPolygons(_softEdgesDashRibbonPolygons(shape));
  } else {
    out = <VsdxGeometry>[];
    final weight =
        shape.line.weightInches > 1e-9 ? shape.line.weightInches : 0.01;
    final half = weight / 2;
    final limit = _lineUsesMiterJoin(shape.line) ? shape.line.miterLimit : 4.0;
    for (final geometry in shape.geometries) {
      if (geometry.noShow || geometry.noLine) continue;
      final points = _strokedVertices(geometry, shape);
      if (points == null || points.length < 2) continue;
      final closed = polylineLooksClosed(points, noFill: geometry.noFill);
      final commands = strokeRibbonCommands(
        points,
        halfWidth: half,
        closed: closed,
        miterLimit: limit,
      );
      if (commands.length < 3) continue;
      out.add(VsdxGeometry(noFill: false, noLine: true, commands: commands));
    }
  }
  if (_openArrowheadsBlockStrokeBake(shape)) {
    out.addAll(bakeArrowGeometriesForLibvisio(shape));
  }
  return out;
}

({double minX, double minY, double maxX, double maxY})? _polygonsAabb(
  List<List<Offset2D>> polygons,
) {
  double? minX;
  double? minY;
  double? maxX;
  double? maxY;
  for (final poly in polygons) {
    for (final p in poly) {
      minX = minX == null ? p.x : math.min(minX, p.x);
      minY = minY == null ? p.y : math.min(minY, p.y);
      maxX = maxX == null ? p.x : math.max(maxX, p.x);
      maxY = maxY == null ? p.y : math.max(maxY, p.y);
    }
  }
  if (minX == null || minY == null || maxX == null || maxY == null) {
    return null;
  }
  return (minX: minX, minY: minY, maxX: maxX, maxY: maxY);
}

/// Closed outline of a solid stroke, used when dash/compound ribbons are empty.
List<List<Offset2D>> _solidStrokeRibbonPolygons(
  VsdxShape shape, {
  double? halfWidth,
}) {
  final weight =
      shape.line.weightInches > 1e-9 ? shape.line.weightInches : 0.01;
  final half = halfWidth ?? weight / 2;
  final limit = _lineUsesMiterJoin(shape.line) ? shape.line.miterLimit : 4.0;
  final out = <List<Offset2D>>[];
  for (final geometry in shape.geometries) {
    if (geometry.noShow || geometry.noLine) continue;
    final points = _strokedVertices(geometry, shape);
    if (points == null || points.length < 2) continue;
    final closed = polylineLooksClosed(points, noFill: geometry.noFill);
    final body = _filletSoftEdgesStrokePoints(points, shape, closed: closed);
    final left = offsetPolyline(
      body,
      half,
      closed: closed,
      miterLimit: limit,
    );
    final right = offsetPolyline(
      body,
      -half,
      closed: closed,
      miterLimit: limit,
    );
    if (left.length < 2 || right.length < 2) continue;
    out.add(<Offset2D>[...left, ...right.reversed]);
  }
  return out;
}

List<List<Offset2D>> _libvisioStrokeSilhouettePolygons(VsdxShape shape) {
  if (shape.line.compoundType > 0) {
    return _softEdgesCompoundRibbonPolygons(shape);
  }
  if (_shapeHasSoftEdgesDashes(shape)) {
    return _softEdgesDashRibbonPolygons(shape);
  }
  return _solidStrokeRibbonPolygons(shape);
}

VsdxShape _strokeRibbonPlateForLibvisioWrite(
  VsdxShape source, {
  required int id,
  VsdxTheme theme = VsdxTheme.empty,
}) {
  final fill = _fillFromLineStroke(source.line, theme) ??
      _opaqueFillFromLine(source.line);
  return VsdxShape(
    id: id,
    name: '$kLibvisioStrokeRibbonShapeNamePrefix${source.id}',
    pinX: source.pinX,
    pinY: source.pinY,
    width: source.width,
    height: source.height,
    locPinXInches: source.locPinXInches,
    locPinYInches: source.locPinYInches,
    angleRad: source.angleRad,
    flipX: source.flipX,
    flipY: source.flipY,
    geometries: _filledStrokeRibbonGeometries(source),
    fill: fill,
    line: const VsdxLine(pattern: 0),
    layerMemberIds: source.layerMemberIds,
    locked: true,
    richText: const VsdxRichText(
      runs: <VsdxTextRun>[],
      textBlock: VsdxTextBlock(hideText: true),
    ),
    text: '',
  );
}

VsdxShape _sourceForLibvisioFilledStrokeRibbonWrite(VsdxShape shape) {
  var line = shape.line.copyWith(
    pattern: 0,
    gradient: null,
    transparency: 0,
    compoundType: 0,
    beginArrow: 0,
    endArrow: 0,
  );
  var cells = <VsdxUserCell>[
    for (final cell in shape.userCells)
      if (cell.name != VsdxShape.userDashPattern &&
          cell.name != VsdxShape.userFixedDash)
        cell,
  ];
  if (_shapeHasLibvisioMiterSpikeCorners(shape)) {
    line = line.copyWith(miterLimit: 4.0);
    cells = <VsdxUserCell>[
      for (final cell in cells)
        if (cell.name != VsdxShape.userMiterLimit) cell,
    ];
  }
  return shape.copyWith(line: line, userCells: cells);
}

void _collectStrokeRibbonPlateIds(List<VsdxShape> shapes, Map<int, int> into) {
  for (final shape in shapes) {
    final sourceId = libvisioStrokeRibbonSourceId(shape);
    if (sourceId != null) into[sourceId] = shape.id;
    _collectStrokeRibbonPlateIds(shape.children, into);
  }
}

bool pageNeedsLibvisioFilledStrokeRibbonBake(VsdxPage page) {
  var hasPlate = false;
  var needs = false;
  void walk(VsdxShape shape) {
    if (isLibvisioStrokeRibbonPlate(shape)) {
      hasPlate = true;
    } else if (shapeNeedsLibvisioFilledStrokeRibbonBake(shape)) {
      needs = true;
    }
    for (final child in shape.children) {
      walk(child);
    }
  }

  for (final shape in page.shapes) {
    walk(shape);
  }
  return hasPlate || needs;
}

List<VsdxShape> _bakeFilledStrokeRibbonTree(
  List<VsdxShape> shapes, {
  required VsdxTheme theme,
  required Map<int, int> plateIds,
  required int Function() nextId,
}) {
  final out = <VsdxShape>[];
  var changed = false;
  for (final shape in shapes) {
    if (isLibvisioStrokeRibbonPlate(shape)) {
      changed = true;
      continue;
    }
    var next = shape;
    if (shape.children.isNotEmpty) {
      final children = _bakeFilledStrokeRibbonTree(
        shape.children,
        theme: theme,
        plateIds: plateIds,
        nextId: nextId,
      );
      if (!identical(children, shape.children)) {
        next = shape.copyWith(children: children);
        changed = true;
      }
    }
    if (shapeNeedsLibvisioFilledStrokeRibbonBake(next)) {
      final plate = _strokeRibbonPlateForLibvisioWrite(
        next,
        id: plateIds[next.id] ?? nextId(),
        theme: theme,
      );
      if (plate.geometries.isEmpty) {
        out.add(next);
        continue;
      }
      out.add(_sourceForLibvisioFilledStrokeRibbonWrite(next));
      out.add(plate);
      changed = true;
      continue;
    }
    out.add(next);
    final existingId = plateIds[next.id];
    if (existingId != null) {
      VsdxShape? kept;
      for (final candidate in shapes) {
        if (candidate.id == existingId) {
          kept = candidate;
          break;
        }
      }
      if (kept != null) {
        out.add(kept);
        changed = true;
      }
    }
    if (!identical(next, shape)) changed = true;
  }
  return changed ? out : shapes;
}

VsdxPage bakeFilledStrokeRibbonPageForLibvisioWrite(
  VsdxPage page, {
  VsdxTheme theme = VsdxTheme.empty,
}) {
  if (!pageNeedsLibvisioFilledStrokeRibbonBake(page)) return page;
  final plateIds = <int, int>{};
  _collectStrokeRibbonPlateIds(page.shapes, plateIds);
  var nextId = _maxShapeId(page.shapes) + 1;
  return page.copyWith(
    shapes: _bakeFilledStrokeRibbonTree(
      page.shapes,
      theme: theme,
      plateIds: plateIds,
      nextId: () => nextId++,
    ),
  );
}

/// Insert (or keep) the stroke-silhouette siblings Draw uses when Fill is
/// already the body.
VsdxDocument bakeFilledStrokeRibbonForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var changed = false;
  for (final page in document.pages) {
    final next = bakeFilledStrokeRibbonPageForLibvisioWrite(
      page,
      theme: document.theme,
    );
    changed |= !identical(next, page);
    pages.add(next);
  }
  return changed ? document.copyWith(pages: pages) : document;
}

/// libvisio never reads User rows. The 1px text-frame stroke canvas / SVG
/// paint from `User.veLabelBorderColor` is therefore a locked NoFill sibling
/// whose LineColor Draw collects, then the User row is dropped. Glueable
/// 1-D labels stay native — their loose plate depends on layout.
bool shapeNeedsLibvisioLabelBorderBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  if (shape.is1D || shape.isGlueableConnector) return false;
  final color = shape.labelBorderColor;
  if (color == null || color.alpha == 0) return false;
  if (shape.richText.textBlock.hideText) return false;
  final hasText =
      !shape.richText.isEmpty || (shape.text != null && shape.text!.isNotEmpty);
  if (!hasText) return false;
  final block = shape.richText.textBlock;
  final tw = (block.widthInches ?? shape.width).abs();
  final th = (block.heightInches ?? shape.height).abs();
  return tw > 1e-9 && th > 1e-9;
}

Offset2D _parentFromLocal(VsdxShape shape, Offset2D local) {
  var dx = local.x - shape.effectiveLocPinX;
  var dy = local.y - shape.effectiveLocPinY;
  if (shape.flipX) dx = -dx;
  if (shape.flipY) dy = -dy;
  if (shape.angleRad != 0) {
    final cosA = math.cos(shape.angleRad);
    final sinA = math.sin(shape.angleRad);
    final rx = dx * cosA - dy * sinA;
    final ry = dx * sinA + dy * cosA;
    dx = rx;
    dy = ry;
  }
  return Offset2D(shape.pinX + dx, shape.pinY + dy);
}

/// Extra text FlipX / FlipY about TxtPin (canvas `_textFlip*`).
///
/// Shape XForm already Flip's geometry about LocPin. Canvas then mirrors
/// the text block again about TxtPin so labels stay upright. Apply this
/// before [_parentFromLocal] so glyph / band plates land on that upright
/// arc. When TxtPin coincides with LocPin the two mirrors cancel.
Offset2D _textFlipAboutPin(VsdxShape shape, Offset2D local) {
  if (!shape.flipX && !shape.flipY) return local;
  final block = shape.richText.textBlock;
  final pinX = block.pinXInches ?? shape.width / 2;
  final pinY = block.pinYInches ?? shape.height / 2;
  var dx = local.x - pinX;
  var dy = local.y - pinY;
  if (shape.flipX) dx = -dx;
  if (shape.flipY) dy = -dy;
  return Offset2D(pinX + dx, pinY + dy);
}

VsdxShape _labelBorderPlateForLibvisioWrite(
  VsdxShape source, {
  required int id,
}) {
  final block = source.richText.textBlock;
  final tw = (block.widthInches ?? source.width).abs();
  final th = (block.heightInches ?? source.height).abs();
  final defaultFrame = block.pinXInches == null &&
      block.pinYInches == null &&
      block.widthInches == null &&
      block.heightInches == null &&
      block.angleRad.abs() < 1e-12;
  late final Offset2D pin;
  late final double? locPinX;
  late final double? locPinY;
  late final double angle;
  if (defaultFrame) {
    pin = Offset2D(source.pinX, source.pinY);
    locPinX = source.locPinXInches;
    locPinY = source.locPinYInches;
    angle = source.angleRad;
  } else {
    pin = _parentFromLocal(
      source,
      Offset2D(
        block.pinXInches ?? source.width / 2,
        block.pinYInches ?? source.height / 2,
      ),
    );
    locPinX = block.locPinXInches;
    locPinY = block.locPinYInches;
    angle = source.angleRad + block.angleRad;
  }
  return VsdxShape(
    id: id,
    name: '$kLibvisioLabelBorderShapeNamePrefix${source.id}',
    pinX: pin.x,
    pinY: pin.y,
    width: tw,
    height: th,
    locPinXInches: locPinX,
    locPinYInches: locPinY,
    angleRad: angle,
    flipX: source.flipX,
    flipY: source.flipY,
    geometries: const <VsdxGeometry>[
      VsdxGeometry(
        noFill: true,
        commands: <VsdxPathCommand>[
          RelMoveTo(0, 0),
          RelLineTo(1, 0),
          RelLineTo(1, 1),
          RelLineTo(0, 1),
          RelLineTo(0, 0),
        ],
      ),
    ],
    fill: const VsdxFill(pattern: 0),
    line: VsdxLine(
      color: source.labelBorderColor,
      pattern: 1,
      weightInches: 1 / kLibvisioLabelBorderPxPerInch,
      cap: LineCap.extended,
    ),
    layerMemberIds: source.layerMemberIds,
    locked: true,
    richText: const VsdxRichText(
      runs: <VsdxTextRun>[],
      textBlock: VsdxTextBlock(hideText: true),
    ),
    text: '',
  );
}

VsdxShape _sourceForLibvisioLabelBorderWrite(VsdxShape shape) =>
    shape.withLabelBorderColor(null);

void _collectLabelBorderPlateIds(List<VsdxShape> shapes, Map<int, int> into) {
  for (final shape in shapes) {
    final sourceId = libvisioLabelBorderSourceId(shape);
    if (sourceId != null) into[sourceId] = shape.id;
    _collectLabelBorderPlateIds(shape.children, into);
  }
}

bool pageNeedsLibvisioLabelBorderBake(VsdxPage page) {
  var hasPlate = false;
  var needs = false;
  void walk(VsdxShape shape) {
    if (isLibvisioLabelBorderPlate(shape)) {
      hasPlate = true;
    } else if (shapeNeedsLibvisioLabelBorderBake(shape)) {
      needs = true;
    }
    for (final child in shape.children) {
      walk(child);
    }
  }

  for (final shape in page.shapes) {
    walk(shape);
  }
  return hasPlate || needs;
}

List<VsdxShape> _bakeLabelBorderTree(
  List<VsdxShape> shapes, {
  required Map<int, int> plateIds,
  required int Function() nextId,
}) {
  final out = <VsdxShape>[];
  var changed = false;
  for (final shape in shapes) {
    if (isLibvisioLabelBorderPlate(shape)) {
      changed = true;
      continue;
    }
    var next = shape;
    if (shape.children.isNotEmpty) {
      final children = _bakeLabelBorderTree(
        shape.children,
        plateIds: plateIds,
        nextId: nextId,
      );
      if (!identical(children, shape.children)) {
        next = shape.copyWith(children: children);
        changed = true;
      }
    }
    if (shapeNeedsLibvisioLabelBorderBake(next)) {
      out.add(_sourceForLibvisioLabelBorderWrite(next));
      final plate = _labelBorderPlateForLibvisioWrite(
        next,
        id: plateIds[next.id] ?? nextId(),
      );
      out.add(plate);
      changed = true;
      continue;
    }
    out.add(next);
    final existingId = plateIds[next.id];
    if (existingId != null) {
      VsdxShape? kept;
      for (final candidate in shapes) {
        if (candidate.id == existingId) {
          kept = candidate;
          break;
        }
      }
      if (kept != null) {
        out.add(kept);
        changed = true;
      }
    }
    if (!identical(next, shape)) changed = true;
  }
  return changed ? out : shapes;
}

VsdxPage bakeLabelBorderPageForLibvisioWrite(VsdxPage page) {
  if (!pageNeedsLibvisioLabelBorderBake(page)) return page;
  final plateIds = <int, int>{};
  _collectLabelBorderPlateIds(page.shapes, plateIds);
  var nextId = _maxShapeId(page.shapes) + 1;
  return page.copyWith(
    shapes: _bakeLabelBorderTree(
      page.shapes,
      plateIds: plateIds,
      nextId: () => nextId++,
    ),
  );
}

/// Insert (or keep) the text-frame stroke siblings Draw uses for Label Border.
VsdxDocument bakeLabelBorderForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var changed = false;
  for (final page in document.pages) {
    final next = bakeLabelBorderPageForLibvisioWrite(page);
    changed |= !identical(next, page);
    pages.add(next);
  }
  return changed ? document.copyWith(pages: pages) : document;
}

/// `true` when `User.veLabelPadding` must fold into Margin cells Draw paints.
///
/// LibreOffice only calls `VisioDocument::parse`. `tokens.txt` has no User
/// rows, so `veLabelPadding` never becomes ODF padding. Left/Right/Top/
/// BottomMargin *are* collected (`VSDContentCollector` maps them to
/// `fo:padding-*`), so a save adds the pixel inset at 96 dpi and drops
/// the User row. Glueable 1-D labels stay native — their loose plate
/// depends on layout.
bool shapeNeedsLibvisioLabelPaddingBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  if (shape.is1D || shape.isGlueableConnector) return false;
  if (shape.labelPadding.isZero) return false;
  if (shape.richText.textBlock.hideText) return false;
  final hasText =
      !shape.richText.isEmpty || (shape.text != null && shape.text!.isNotEmpty);
  return hasText;
}

VsdxShape bakeLabelPaddingShapeForLibvisioWrite(VsdxShape shape) {
  final children = <VsdxShape>[
    for (final child in shape.children)
      bakeLabelPaddingShapeForLibvisioWrite(child),
  ];
  var childrenChanged = children.length != shape.children.length;
  if (!childrenChanged) {
    for (var i = 0; i < children.length; i++) {
      if (!identical(children[i], shape.children[i])) {
        childrenChanged = true;
        break;
      }
    }
  }
  var next = shape;
  if (shapeNeedsLibvisioLabelPaddingBake(shape)) {
    final pad = shape.labelPadding;
    final block = shape.richText.textBlock;
    final px = kLibvisioLabelPaddingPxPerInch;
    next = shape
        .copyWith(
          richText: shape.richText.copyWith(
            textBlock: block.copyWith(
              marginLeftInches: block.marginLeftInches + pad.left / px,
              marginRightInches: block.marginRightInches + pad.right / px,
              marginTopInches: block.marginTopInches + pad.top / px,
              marginBottomInches: block.marginBottomInches + pad.bottom / px,
            ),
          ),
        )
        .withLabelPadding(VsdxLabelPadding.zero);
  }
  if (childrenChanged) next = next.copyWith(children: children);
  return next;
}

/// Fold `User.veLabelPadding` into Left/Right/Top/BottomMargin Draw collects.
VsdxDocument bakeLabelPaddingForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var pagesChanged = false;
  for (final page in document.pages) {
    final shapes = <VsdxShape>[
      for (final shape in page.shapes)
        bakeLabelPaddingShapeForLibvisioWrite(shape),
    ];
    var same = shapes.length == page.shapes.length;
    if (same) {
      for (var i = 0; i < shapes.length; i++) {
        if (!identical(shapes[i], page.shapes[i])) {
          same = false;
          break;
        }
      }
    }
    if (same) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      pagesChanged = true;
    }
  }
  if (!pagesChanged) return document;
  return document.copyWith(pages: pages);
}

/// Conservative unwrapped advance so Draw's wrap-at-`svg:width` stays one
/// line. Latin uses 0.72 em (wider than the canvas 0.55 mean and DejaVu's
/// ~0.70 bold) so a slightly tight estimate cannot re-wrap in Draw.
double nowrapTextAdvanceInches(String text, VsdxCharStyle style) {
  if (text.isEmpty) return 0;
  var fs = math.max(style.effectiveFontSizeInchesForText(text), 0.04);
  if (style.position != VsdxTextPosition.normal) fs *= 0.7;
  final scale = fontScaleForLibvisioWrite(style, text);
  final runes = text.runes.toList(growable: false);
  var w = 0.0;
  for (var i = 0; i < runes.length; i++) {
    final r = runes[i];
    final chFs = isVisioComplexScriptRune(r) || isVisioAsianScriptRune(r)
        ? fs
        : fs * 0.72;
    w += chFs;
    if (i + 1 < runes.length) {
      w += fs * (scale - 1.0) * kLibvisioMeanLatinAdvance;
    }
  }
  return w;
}

double nowrapLabelAdvanceInches(VsdxShape shape) {
  var widest = 0.0;
  var current = 0.0;
  void addRun(String text, VsdxCharStyle style) {
    final parts = text.split(RegExp(r'\r\n|\n|\r'));
    for (var i = 0; i < parts.length; i++) {
      current += nowrapTextAdvanceInches(parts[i], style);
      if (i < parts.length - 1) {
        if (current > widest) widest = current;
        current = 0;
      }
    }
  }

  if (!shape.richText.isEmpty) {
    for (final run in shape.richText.runs) {
      addRun(run.text, run.charStyle);
    }
  } else if (shape.text != null && shape.text!.isNotEmpty) {
    addRun(shape.text!, VsdxCharStyle.defaults);
  }
  if (current > widest) widest = current;
  return widest;
}

/// Extra TxtWidth Draw needs so an unwrapped label stays one line.
double nowrapTxtWidthForLibvisioWrite(VsdxShape shape) {
  final block = shape.richText.textBlock;
  return nowrapLabelAdvanceInches(shape) +
      block.marginLeftInches +
      block.marginRightInches +
      0.06;
}

/// `true` when `User.veWordWrap=0` must expand TxtWidth so Draw does not wrap.
///
/// LibreOffice only calls `VisioDocument::parse`. `tokens.txt` has no User
/// rows, so `veWordWrap` never becomes ODF `fo:wrap-option`. TxtWidth *is*
/// collected (`svg:width` of the text object), and Draw wraps to that box,
/// so a save widens the frame to the unwrapped line and drops the User row.
/// Glueable 1-D labels, vertical text, curved text, and tabbed labels stay
/// native — their layout is not a single horizontal measure.
bool shapeNeedsLibvisioWordWrapBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  if (shape.is1D || shape.isGlueableConnector) return false;
  if (shape.wordWrap) return false;
  if (shape.curvedText) return false;
  if (shape.richText.textBlock.hideText) return false;
  if (shape.richText.textBlock.textDirection == 1) return false;
  for (final cell in shape.userCells) {
    if (cell.name == VsdxShape.userShapeInside && cell.value == '1') {
      return false;
    }
  }
  final hasText =
      !shape.richText.isEmpty || (shape.text != null && shape.text!.isNotEmpty);
  if (!hasText) return false;
  final plain =
      shape.richText.isEmpty ? (shape.text ?? '') : shape.richText.plainText;
  if (plain.contains('\t')) return false;
  return nowrapTxtWidthForLibvisioWrite(shape) > 1e-9;
}

VsdxHorzAlign _nowrapAlign(VsdxShape shape) {
  if (shape.richText.runs.isEmpty) return VsdxHorzAlign.left;
  return shape.richText.runs.first.paraStyle.effectiveHorizontalAlign;
}

VsdxShape _sourceForLibvisioWordWrapWrite(VsdxShape shape) {
  final others = <VsdxUserCell>[
    for (final cell in shape.userCells)
      if (cell.name != VsdxShape.userWordWrap) cell,
  ];
  final block = shape.richText.textBlock;
  final tw = (block.widthInches ?? shape.width).abs();
  final needed = nowrapTxtWidthForLibvisioWrite(shape);
  var nextBlock = block;
  var formulas = shape.formulas;
  if (needed > tw + 1e-9) {
    final pinX = block.pinXInches ?? shape.width / 2;
    final locX = block.locPinXInches ?? tw / 2;
    final left = pinX - locX;
    final right = left + tw;
    final align = _nowrapAlign(shape);
    late final double newLeft;
    switch (align) {
      case VsdxHorzAlign.right:
        newLeft = right - needed;
      case VsdxHorzAlign.center:
        newLeft = left - (needed - tw) / 2;
      case VsdxHorzAlign.left:
      case VsdxHorzAlign.justify:
      case VsdxHorzAlign.full:
        newLeft = left;
    }
    nextBlock = block.copyWith(
      widthInches: needed,
      locPinXInches: pinX - newLeft,
    );
    formulas = Map<String, String>.of(shape.formulas)
      ..remove('TxtWidth')
      ..remove('TxtLocPinX');
  }
  return shape.copyWith(
    userCells: others,
    richText: shape.richText.copyWith(textBlock: nextBlock),
    formulas: formulas,
  );
}

VsdxShape bakeWordWrapShapeForLibvisioWrite(VsdxShape shape) {
  final children = <VsdxShape>[
    for (final child in shape.children)
      bakeWordWrapShapeForLibvisioWrite(child),
  ];
  var childrenChanged = children.length != shape.children.length;
  if (!childrenChanged) {
    for (var i = 0; i < children.length; i++) {
      if (!identical(children[i], shape.children[i])) {
        childrenChanged = true;
        break;
      }
    }
  }
  var next = shape;
  if (shapeNeedsLibvisioWordWrapBake(shape)) {
    next = _sourceForLibvisioWordWrapWrite(shape);
  }
  if (childrenChanged) next = next.copyWith(children: children);
  return next;
}

/// Expand TxtWidth so Draw keeps an unwrapped draw.io label on one line.
VsdxDocument bakeWordWrapForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var pagesChanged = false;
  for (final page in document.pages) {
    final shapes = <VsdxShape>[
      for (final shape in page.shapes) bakeWordWrapShapeForLibvisioWrite(shape),
    ];
    var same = shapes.length == page.shapes.length;
    if (same) {
      for (var i = 0; i < shapes.length; i++) {
        if (!identical(shapes[i], page.shapes[i])) {
          same = false;
          break;
        }
      }
    }
    if (same) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      pagesChanged = true;
    }
  }
  if (!pagesChanged) return document;
  return document.copyWith(pages: pages);
}

/// `true` when a folded host still has descendants Draw would paint.
///
/// LibreOffice only calls `VisioDocument::parse`. `tokens.txt` has no User
/// rows, so `veCollapsed` never hides children. Geometry `NoShow`, `HideText`,
/// `FillPattern=0` / `LinePattern=0`, and zero-size Foreign images *are*
/// collected, so a save applies those and stores
/// [VsdxShape.userCollapsedHidden] for Unfold.
bool shapeNeedsLibvisioCollapsedHideBake(VsdxShape shape) {
  if (!shape.collapsed) {
    for (final child in shape.children) {
      if (shapeNeedsLibvisioCollapsedHideBake(child)) return true;
    }
    return false;
  }
  return _collapsedDescendantNeedsHide(shape);
}

bool _collapsedDescendantNeedsHide(VsdxShape shape) {
  for (final child in shape.children) {
    if (!child.libvisioCollapsedHidden) return true;
    if (_collapsedDescendantNeedsHide(child)) return true;
  }
  return false;
}

VsdxShape bakeCollapsedShapeForLibvisioWrite(VsdxShape shape) {
  final children = <VsdxShape>[
    for (final child in shape.children)
      bakeCollapsedShapeForLibvisioWrite(child),
  ];
  var next = shape;
  var changed = false;
  if (children.length != shape.children.length) {
    changed = true;
  } else {
    for (var i = 0; i < children.length; i++) {
      if (!identical(children[i], shape.children[i])) {
        changed = true;
        break;
      }
    }
  }
  if (changed) next = shape.copyWith(children: children);
  if (!next.collapsed || !_collapsedDescendantNeedsHide(next)) {
    return changed ? next : shape;
  }
  final hidden = <VsdxShape>[
    for (final child in next.children) child.hideSubtreeForLibvisioCollapsed(),
  ];
  return next.copyWith(children: hidden);
}

/// Hide folded-container descendants so Draw does not paint them.
VsdxDocument bakeCollapsedForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var pagesChanged = false;
  for (final page in document.pages) {
    var needs = false;
    for (final shape in page.shapes) {
      if (shapeNeedsLibvisioCollapsedHideBake(shape)) {
        needs = true;
        break;
      }
    }
    if (!needs) {
      pages.add(page);
      continue;
    }
    pages.add(
      page.copyWith(
        shapes: <VsdxShape>[
          for (final shape in page.shapes)
            bakeCollapsedShapeForLibvisioWrite(shape),
        ],
      ),
    );
    pagesChanged = true;
  }
  if (!pagesChanged) return document;
  return document.copyWith(pages: pages);
}

/// `true` when a covered (merged-away) table cell is still drawable in Draw.
///
/// LibreOffice only calls `VisioDocument::parse`. `tokens.txt` has no User
/// rows, so `veCovered` never hides the 0.01" park rectangle. Geometry
/// `NoShow`, `HideText`, `FillPattern=0` / `LinePattern=0`, and zero-size
/// Foreign images *are* collected, so a save applies those and stores
/// [VsdxShape.userCoveredHidden] for Unmerge.
bool shapeNeedsLibvisioCoveredHideBake(VsdxShape shape) {
  if (TableOps.isCovered(shape) && !shape.libvisioCoveredHidden) return true;
  for (final child in shape.children) {
    if (shapeNeedsLibvisioCoveredHideBake(child)) return true;
  }
  return false;
}

VsdxShape bakeCoveredShapeForLibvisioWrite(VsdxShape shape) {
  final children = <VsdxShape>[
    for (final child in shape.children) bakeCoveredShapeForLibvisioWrite(child),
  ];
  var next = shape;
  var changed = false;
  if (children.length != shape.children.length) {
    changed = true;
  } else {
    for (var i = 0; i < children.length; i++) {
      if (!identical(children[i], shape.children[i])) {
        changed = true;
        break;
      }
    }
  }
  if (changed) next = shape.copyWith(children: children);
  if (!TableOps.isCovered(next) || next.libvisioCoveredHidden) {
    return changed ? next : shape;
  }
  return next.hideForLibvisioCovered();
}

/// Hide merged-away table cells so Draw does not paint their park boxes.
VsdxDocument bakeCoveredForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var pagesChanged = false;
  for (final page in document.pages) {
    var needs = false;
    for (final shape in page.shapes) {
      if (shapeNeedsLibvisioCoveredHideBake(shape)) {
        needs = true;
        break;
      }
    }
    if (!needs) {
      pages.add(page);
      continue;
    }
    pages.add(
      page.copyWith(
        shapes: <VsdxShape>[
          for (final shape in page.shapes)
            bakeCoveredShapeForLibvisioWrite(shape),
        ],
      ),
    );
    pagesChanged = true;
  }
  if (!pagesChanged) return document;
  return document.copyWith(pages: pages);
}

/// Combining overline `readCharIX` skips (`case XML_OVERLINE: break`).
const kLibvisioCombiningOverline = '\u0305';

bool _isCombiningMarkRune(int rune) =>
    (rune >= 0x0300 && rune <= 0x036F) ||
    (rune >= 0x1AB0 && rune <= 0x1AFF) ||
    (rune >= 0x1DC0 && rune <= 0x1DFF) ||
    (rune >= 0x20D0 && rune <= 0x20FF) ||
    (rune >= 0xFE20 && rune <= 0xFE2F);

bool _runeTakesCombiningOverline(int rune) {
  if (rune == 0x0305) return false;
  if (rune == 0x09 || rune == 0x0A || rune == 0x0D) return false;
  if (rune == 0x20 || rune == 0xA0) return false;
  if (_isCombiningMarkRune(rune)) return false;
  return true;
}

/// Insert U+0305 after each visible glyph so Draw paints an overline.
String textWithCombiningOverline(String text) {
  if (text.contains(kLibvisioCombiningOverline)) return text;
  final buf = StringBuffer();
  for (final rune in text.runes) {
    buf.writeCharCode(rune);
    if (_runeTakesCombiningOverline(rune)) {
      buf.write(kLibvisioCombiningOverline);
    }
  }
  return buf.toString();
}

bool _runNeedsLibvisioOverlineBake(VsdxTextRun run) {
  if (!run.charStyle.overline) return false;
  if (run.text.isEmpty) return false;
  if (run.fieldSpans.isNotEmpty || run.tabIndices.isNotEmpty) return false;
  if (run.text.contains(kLibvisioCombiningOverline)) return false;
  for (final rune in run.text.runes) {
    if (_runeTakesCombiningOverline(rune)) return true;
  }
  return false;
}

/// `true` when Character Overline must become combining marks for Draw.
bool shapeNeedsLibvisioOverlineBake(VsdxShape shape) {
  if (shape.richText.textBlock.hideText) return false;
  if (shape.fields.isNotEmpty) return false;
  for (final run in shape.richText.runs) {
    if (_runNeedsLibvisioOverlineBake(run)) return true;
  }
  return false;
}

VsdxShape bakeOverlineShapeForLibvisioWrite(VsdxShape shape) {
  final children = <VsdxShape>[
    for (final child in shape.children)
      bakeOverlineShapeForLibvisioWrite(child),
  ];
  var childrenChanged = children.length != shape.children.length;
  if (!childrenChanged) {
    for (var i = 0; i < children.length; i++) {
      if (!identical(children[i], shape.children[i])) {
        childrenChanged = true;
        break;
      }
    }
  }
  var next = shape;
  if (shapeNeedsLibvisioOverlineBake(shape)) {
    final runs = <VsdxTextRun>[
      for (final run in shape.richText.runs)
        if (_runNeedsLibvisioOverlineBake(run))
          run.copyWith(
            text: textWithCombiningOverline(run.text),
            charStyle: run.charStyle.copyWith(overline: false),
          )
        else
          run,
    ];
    next = shape.copyWith(
      text: VsdxRichText(runs: runs, textBlock: shape.richText.textBlock)
          .plainText,
      richText: shape.richText.copyWith(runs: runs),
    );
  }
  if (childrenChanged) {
    next = next.copyWith(children: children);
  }
  return next;
}

/// Rewrite Overline into combining marks the text engine in Draw will paint.
VsdxDocument bakeOverlineForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var pagesChanged = false;
  for (final page in document.pages) {
    final shapes = <VsdxShape>[
      for (final shape in page.shapes) bakeOverlineShapeForLibvisioWrite(shape),
    ];
    var same = shapes.length == page.shapes.length;
    if (same) {
      for (var i = 0; i < shapes.length; i++) {
        if (!identical(shapes[i], page.shapes[i])) {
          same = false;
          break;
        }
      }
    }
    if (same) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      pagesChanged = true;
    }
  }
  if (!pagesChanged) return document;
  return document.copyWith(pages: pages);
}

/// `true` when mixed Character Highlight must become per-run plates for Draw.
///
/// `readCharIX` has `case XML_HIGHLIGHT: break;`. A uniform marker already
/// becomes TextBkgnd. Mixed colours cannot share that cell, so a save
/// inserts locked FillForegnd siblings that carry each highlighted run
/// using the same nowrap advance curved-text uses, then hides the source
/// label so Draw paints those glyphs above the body fill. Single-line
/// 2-D labels only — tabs, wraps, vertical text, 1-D and authored
/// TextBkgnd stay native.
bool shapeNeedsLibvisioMixedHighlightBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  if (shape.is1D || shape.isGlueableConnector) return false;
  if (shape.curvedText || shape.shapeInside) return false;
  final block = shape.richText.textBlock;
  if (block.hideText) return false;
  if (block.textDirection == 1) return false;
  if (block.backgroundColor != null) return false;
  if (uniformCharacterHighlight(shape) != null) return false;
  var sawHighlight = false;
  for (final run in shape.richText.runs) {
    if (run.text.contains('\t') ||
        run.text.contains('\n') ||
        run.text.contains('\r')) {
      return false;
    }
    if (run.text.trim().isEmpty) continue;
    if (run.charStyle.highlight != null) sawHighlight = true;
  }
  return sawHighlight;
}

List<({VsdxTextRun run, double width, double height})>
    _mixedHighlightRunMetrics(VsdxShape shape) {
  final out = <({VsdxTextRun run, double width, double height})>[];
  for (final run in shape.richText.runs) {
    if (run.text.isEmpty) continue;
    final width = nowrapTextAdvanceInches(run.text, run.charStyle);
    final height = math.max(
      run.charStyle.effectiveFontSizeInchesForText(run.text),
      0.04,
    );
    out.add((run: run, width: width, height: height));
  }
  return out;
}

List<VsdxShape> _mixedHighlightPlatesForLibvisioWrite(
  VsdxShape source, {
  required List<int> plateIds,
  required int Function() nextId,
}) {
  final metrics = _mixedHighlightRunMetrics(source);
  if (metrics.isEmpty) return const <VsdxShape>[];
  final block = source.richText.textBlock;
  final tw = (block.widthInches ?? source.width).abs();
  final th = (block.heightInches ?? source.height).abs();
  final pinX = block.pinXInches ?? source.width / 2;
  final pinY = block.pinYInches ?? source.height / 2;
  final locX = block.locPinXInches ?? tw / 2;
  final locY = block.locPinYInches ?? th / 2;
  final originX = pinX - locX;
  final originY = pinY - locY;
  var totalW = 0.0;
  var lineH = 0.04;
  for (final m in metrics) {
    totalW += m.width;
    if (m.height > lineH) lineH = m.height;
  }
  final align = metrics.first.run.paraStyle.effectiveHorizontalAlign;
  final contentW =
      math.max(0.0, tw - block.marginLeftInches - block.marginRightInches);
  var cursor = originX + block.marginLeftInches;
  switch (align) {
    case VsdxHorzAlign.center:
      cursor += math.max(0.0, (contentW - totalW) / 2);
    case VsdxHorzAlign.right:
      cursor += math.max(0.0, contentW - totalW);
    case VsdxHorzAlign.left:
    case VsdxHorzAlign.justify:
    case VsdxHorzAlign.full:
      break;
  }
  final midY = switch (block.verticalAlign) {
    VsdxVertAlign.top => originY + th - block.marginTopInches - lineH / 2,
    VsdxVertAlign.bottom => originY + block.marginBottomInches + lineH / 2,
    VsdxVertAlign.middle => originY + th / 2,
  };
  final out = <VsdxShape>[];
  var plate = 0;
  for (final m in metrics) {
    final color = m.run.charStyle.highlight;
    if (color != null && m.width > 1e-9) {
      final local = _textFlipAboutPin(
        source,
        Offset2D(cursor + m.width / 2, midY),
      );
      final page = _parentFromLocal(source, local);
      final id = plate < plateIds.length ? plateIds[plate] : nextId();
      final pw = math.max(m.width, lineH) * 1.2;
      final ph = lineH * 1.5;
      final style = m.run.charStyle.copyWith(clearHighlight: true);
      out.add(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: page.x,
          pinY: page.y,
          width: pw,
          height: ph,
          name: '$kLibvisioHighlightShapeNamePrefix$plate.${source.id}',
          fill: VsdxFill(foreground: color, pattern: 1),
          line: const VsdxLine(pattern: 0),
        ).copyWith(
          locPinXInches: pw / 2,
          locPinYInches: ph / 2,
          angleRad: source.angleRad + block.angleRad,
          locked: true,
          layerMemberIds: source.layerMemberIds,
          text: m.run.text,
          richText: VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: m.run.text,
                charStyle: style,
                paraStyle: const VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.center,
                ),
              ),
            ],
            textBlock: VsdxTextBlock(
              widthInches: pw,
              heightInches: ph,
              locPinXInches: pw / 2,
              locPinYInches: ph / 2,
              verticalAlign: VsdxVertAlign.middle,
              marginLeftInches: 0,
              marginRightInches: 0,
              marginTopInches: 0,
              marginBottomInches: 0,
            ),
          ),
        ),
      );
      plate++;
    }
    cursor += m.width;
  }
  return out;
}

void _collectHighlightPlateIds(
  List<VsdxShape> shapes,
  Map<int, List<int>> into,
) {
  for (final shape in shapes) {
    final sourceId = libvisioHighlightSourceId(shape);
    if (sourceId != null) {
      (into[sourceId] ??= <int>[]).add(shape.id);
    }
    _collectHighlightPlateIds(shape.children, into);
  }
}

bool pageNeedsLibvisioMixedHighlightBake(VsdxPage page) {
  var hasPlate = false;
  var needs = false;
  void walk(VsdxShape shape) {
    if (isLibvisioHighlightPlate(shape)) {
      hasPlate = true;
    } else if (shapeNeedsLibvisioMixedHighlightBake(shape)) {
      needs = true;
    }
    for (final child in shape.children) {
      walk(child);
    }
  }

  for (final shape in page.shapes) {
    walk(shape);
  }
  return hasPlate || needs;
}

VsdxShape _sourceForLibvisioMixedHighlightWrite(VsdxShape shape) {
  if (shape.richText.textBlock.hideText) return shape;
  return shape.copyWith(
    richText: shape.richText.copyWith(
      textBlock: shape.richText.textBlock.copyWith(hideText: true),
    ),
  );
}

List<VsdxShape> _bakeMixedHighlightTree(
  List<VsdxShape> shapes, {
  required Map<int, List<int>> plateIds,
  required int Function() nextId,
}) {
  final out = <VsdxShape>[];
  var changed = false;
  for (final shape in shapes) {
    if (isLibvisioHighlightPlate(shape)) {
      changed = true;
      continue;
    }
    var next = shape;
    if (shape.children.isNotEmpty) {
      final children = _bakeMixedHighlightTree(
        shape.children,
        plateIds: plateIds,
        nextId: nextId,
      );
      if (!identical(children, shape.children)) {
        next = shape.copyWith(children: children);
        changed = true;
      }
    }
    if (shapeNeedsLibvisioMixedHighlightBake(next) ||
        plateIds.containsKey(next.id)) {
      final plates = _mixedHighlightPlatesForLibvisioWrite(
        next,
        plateIds: plateIds[next.id] ?? const <int>[],
        nextId: nextId,
      );
      if (plates.isEmpty) {
        out.add(next);
        continue;
      }
      // Body fill first, then glyph plates so Draw does not cover the
      // markers. Hide the source label — Highlight is not a token.
      out.add(_sourceForLibvisioMixedHighlightWrite(next));
      out.addAll(plates);
      changed = true;
      continue;
    }
    out.add(next);
    if (!identical(next, shape)) changed = true;
  }
  return changed ? out : shapes;
}

/// Insert (or keep) the per-run Highlight siblings Draw can fill.
VsdxDocument bakeMixedHighlightForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var changed = false;
  for (final page in document.pages) {
    if (!pageNeedsLibvisioMixedHighlightBake(page)) {
      pages.add(page);
      continue;
    }
    final plateIds = <int, List<int>>{};
    _collectHighlightPlateIds(page.shapes, plateIds);
    var nextId = _maxShapeId(page.shapes) + 1;
    final shapes = _bakeMixedHighlightTree(
      page.shapes,
      plateIds: plateIds,
      nextId: () => nextId++,
    );
    if (identical(shapes, page.shapes)) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      changed = true;
    }
  }
  if (!changed) return document;
  return document.copyWith(pages: pages);
}

/// RIGHT-TO-LEFT MARK. Draw never reads Character `LangID`, so a save
/// prefixes this when canvas / SVG already treat a digit/punctuation run
/// as RTL from that cell.
const kLibvisioRtlMark = '\u200F';

bool _textHasStrongRightToLeft(String text) {
  for (final rune in text.runes) {
    if (isVisioRightToLeftRune(rune)) return true;
  }
  return false;
}

/// Prefix U+200F so Draw's Unicode bidi matches canvas LangID RTL.
String textWithLibvisioRtlMark(String text) {
  if (text.startsWith(kLibvisioRtlMark)) return text;
  return '$kLibvisioRtlMark$text';
}

bool _runNeedsLibvisioLangIdRtlBake(VsdxTextRun run) {
  final text = run.text;
  if (text.trim().isEmpty) return false;
  if (text.startsWith(kLibvisioRtlMark)) return false;
  if (run.fieldSpans.isNotEmpty || run.tabIndices.isNotEmpty) return false;
  if (_textHasStrongRightToLeft(text)) return false;
  return isVisioRightToLeftText(text, langId: run.charStyle.langId);
}

/// `true` when Character LangID must become a leading U+200F for Draw.
///
/// LibreOffice only calls `VisioDocument::parse`. `tokens.txt` has no
/// LangID and `readCharIX` never stores it, so Draw lays out digit-only
/// Arabic / Hebrew runs LTR. Canvas / SVG already use
/// [isVisioRightToLeftText]. Strong RTL letters do not need the mark.
bool shapeNeedsLibvisioLangIdRtlBake(VsdxShape shape) {
  if (shape.richText.textBlock.hideText) return false;
  for (final run in shape.richText.runs) {
    if (_runNeedsLibvisioLangIdRtlBake(run)) return true;
  }
  return false;
}

VsdxShape bakeLangIdRtlShapeForLibvisioWrite(VsdxShape shape) {
  final children = <VsdxShape>[
    for (final child in shape.children)
      bakeLangIdRtlShapeForLibvisioWrite(child),
  ];
  var childrenChanged = children.length != shape.children.length;
  if (!childrenChanged) {
    for (var i = 0; i < children.length; i++) {
      if (!identical(children[i], shape.children[i])) {
        childrenChanged = true;
        break;
      }
    }
  }
  var next = shape;
  if (shapeNeedsLibvisioLangIdRtlBake(shape)) {
    final runs = <VsdxTextRun>[
      for (final run in shape.richText.runs)
        if (_runNeedsLibvisioLangIdRtlBake(run))
          run.copyWith(text: textWithLibvisioRtlMark(run.text))
        else
          run,
    ];
    next = shape.copyWith(
      text: VsdxRichText(runs: runs, textBlock: shape.richText.textBlock)
          .plainText,
      richText: shape.richText.copyWith(runs: runs),
    );
  }
  if (childrenChanged) {
    next = next.copyWith(children: children);
  }
  return next;
}

/// Prefix LangID-only RTL runs with U+200F so Draw matches canvas bidi.
VsdxDocument bakeLangIdRtlForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var pagesChanged = false;
  for (final page in document.pages) {
    final shapes = <VsdxShape>[
      for (final shape in page.shapes)
        bakeLangIdRtlShapeForLibvisioWrite(shape),
    ];
    var same = shapes.length == page.shapes.length;
    if (same) {
      for (var i = 0; i < shapes.length; i++) {
        if (!identical(shapes[i], page.shapes[i])) {
          same = false;
          break;
        }
      }
    }
    if (same) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      pagesChanged = true;
    }
  }
  if (!pagesChanged) return document;
  return document.copyWith(pages: pages);
}

const _kLibvisioCurvedTextMaxGlyphs = 64;

/// `true` when `User.veCurvedText` must become per-glyph siblings for Draw.
///
/// LibreOffice only calls `VisioDocument::parse`. `tokens.txt` has no User
/// rows, so the arc never becomes ODF text-on-path. Pin / Angle / Font /
/// HideText *are* collected, so a save places one locked character shape
/// per glyph on the same quadratic arc canvas / SVG already paint, then
/// hides the source and drops the User row. Glueable 1-D labels, vertical
/// text, tabbed labels and TxtAngle stay native. FlipX / FlipY extra
/// text mirrors about TxtPin are baked so Draw keeps the upright arc.
bool shapeNeedsLibvisioCurvedTextBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  if (shape.is1D || shape.isGlueableConnector) return false;
  if (!shape.curvedText) return false;
  if (shape.richText.textBlock.hideText) return false;
  if (shape.richText.textBlock.textDirection == 1) return false;
  if (shape.richText.textBlock.angleRad.abs() > 1e-12) return false;
  final plain = _curvedTextPlain(shape);
  if (plain.isEmpty) return false;
  if (plain.contains('\t')) return false;
  var n = 0;
  for (final r in plain.runes) {
    if (r == 0x20) continue;
    n++;
    if (n > _kLibvisioCurvedTextMaxGlyphs) return false;
  }
  return n > 0;
}

String _libvisioInitialCaps(String text) {
  final buf = StringBuffer();
  var start = true;
  for (final r in text.runes) {
    final ch = String.fromCharCode(r);
    if (ch == ' ' || ch == '\n' || ch == '\t') {
      buf.write(ch);
      start = true;
      continue;
    }
    buf.write(start ? ch.toUpperCase() : ch);
    start = false;
  }
  return buf.toString();
}

String _curvedTextPlain(VsdxShape shape) {
  final raw =
      shape.richText.isEmpty ? (shape.text ?? '') : shape.richText.plainText;
  var text = raw.replaceAll('\n', ' ').replaceAll('\r', ' ').trim();
  final style = shape.richText.runs.isNotEmpty
      ? shape.richText.runs.first.charStyle
      : VsdxCharStyle.defaults;
  return switch (style.textCase) {
    VsdxTextCase.allCaps => text.toUpperCase(),
    VsdxTextCase.initialCaps => _libvisioInitialCaps(text),
    VsdxTextCase.normal => text,
  };
}

VsdxCharStyle _curvedTextStyle(VsdxShape shape) {
  final style = shape.richText.runs.isNotEmpty
      ? shape.richText.runs.first.charStyle
      : VsdxCharStyle.defaults;
  return style.copyWith(textCase: VsdxTextCase.normal);
}

Offset2D _quadBezPoint(Offset2D p0, Offset2D p1, Offset2D p2, double t) {
  final u = 1 - t;
  return Offset2D(
    u * u * p0.x + 2 * u * t * p1.x + t * t * p2.x,
    u * u * p0.y + 2 * u * t * p1.y + t * t * p2.y,
  );
}

Offset2D _quadBezTangent(Offset2D p0, Offset2D p1, Offset2D p2, double t) {
  return Offset2D(
    2 * (1 - t) * (p1.x - p0.x) + 2 * t * (p2.x - p1.x),
    2 * (1 - t) * (p1.y - p0.y) + 2 * t * (p2.y - p1.y),
  );
}

double _arcTForDistance(List<double> cum, double dist) {
  final n = cum.length - 1;
  if (n <= 0) return 0;
  if (dist <= 0) return 0;
  if (dist >= cum.last) return 1;
  var lo = 0;
  var hi = n;
  while (lo + 1 < hi) {
    final mid = (lo + hi) >> 1;
    if (cum[mid] <= dist) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  final seg = cum[hi] - cum[lo];
  final local = seg <= 1e-12 ? 0.0 : (dist - cum[lo]) / seg;
  return (lo + local) / n;
}

List<VsdxShape> _curvedTextPlatesForLibvisioWrite(
  VsdxShape source, {
  required List<int> plateIds,
  required int Function() nextId,
}) {
  final style = _curvedTextStyle(source);
  final plain = _curvedTextPlain(source);
  final block = source.richText.textBlock;
  final tw = (block.widthInches ?? source.width).abs();
  final th = (block.heightInches ?? source.height).abs();
  final ml = block.marginLeftInches;
  final mr = block.marginRightInches;
  final pinX = block.pinXInches ?? source.width / 2;
  final pinY = block.pinYInches ?? source.height / 2;
  final locX = block.locPinXInches ?? tw / 2;
  final locY = block.locPinYInches ?? th / 2;
  final originX = pinX - locX;
  final originY = pinY - locY;
  final midY = th * 0.58;
  final bulge = math.min(th * 0.32, th * 0.45);
  final p0 = Offset2D(ml, midY);
  final p1 = Offset2D(tw / 2, midY - bulge);
  final p2 = Offset2D(tw - mr, midY);
  const samples = 48;
  final cum = <double>[0.0];
  var prev = p0;
  for (var i = 1; i <= samples; i++) {
    final o = _quadBezPoint(p0, p1, p2, i / samples);
    final dx = o.x - prev.x;
    final dy = o.y - prev.y;
    cum.add(cum.last + math.sqrt(dx * dx + dy * dy));
    prev = o;
  }
  final arcLen = cum.last;
  if (arcLen <= 1e-9) return const <VsdxShape>[];
  final runes = plain.runes.toList(growable: false);
  final widths = <double>[
    for (final r in runes)
      nowrapTextAdvanceInches(String.fromCharCode(r), style),
  ];
  var totalW = 0.0;
  for (final w in widths) {
    totalW += w;
  }
  final pad = math.max(0.0, (arcLen - totalW) / 2);
  final out = <VsdxShape>[];
  var cursor = pad;
  var glyph = 0;
  for (var i = 0; i < runes.length; i++) {
    final w = widths[i];
    final ch = String.fromCharCode(runes[i]);
    if (runes[i] != 0x20 && ch.trim().isNotEmpty) {
      final centerDist = (cursor + w / 2).clamp(0.0, arcLen);
      final t = _arcTForDistance(cum, centerDist);
      final pos = _quadBezPoint(p0, p1, p2, t);
      final tan = _quadBezTangent(p0, p1, p2, t);
      final localAngle = -math.atan2(tan.y, tan.x);
      final local = _textFlipAboutPin(
        source,
        Offset2D(originX + pos.x, originY + th - pos.y),
      );
      final page = _parentFromLocal(source, local);
      final fs = math.max(style.effectiveFontSizeInchesForText(ch), 0.04);
      // Wider / taller than the advance so Draw's wrap-at-svg:width and
      // baseline padding cannot clip a single rotated glyph.
      final gw = math.max(w, fs) * 1.2;
      final gh = fs * 1.6;
      final id = glyph < plateIds.length ? plateIds[glyph] : nextId();
      out.add(
        VsdxShapeFactory.rectangle(
          id: id,
          pinX: page.x,
          pinY: page.y,
          width: gw,
          height: gh,
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(pattern: 0),
          name: '$kLibvisioCurvedTextShapeNamePrefix$glyph.${source.id}',
        ).copyWith(
          locPinXInches: gw / 2,
          locPinYInches: gh / 2,
          angleRad: source.angleRad + localAngle,
          locked: true,
          layerMemberIds: source.layerMemberIds,
          text: ch,
          richText: VsdxRichText(
            runs: <VsdxTextRun>[
              VsdxTextRun(
                text: ch,
                charStyle: style,
                paraStyle: const VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.center,
                ),
              ),
            ],
            textBlock: VsdxTextBlock(
              widthInches: gw,
              heightInches: gh,
              locPinXInches: gw / 2,
              locPinYInches: gh / 2,
              verticalAlign: VsdxVertAlign.middle,
            ),
          ),
        ),
      );
      glyph++;
    }
    cursor += w;
  }
  return out;
}

VsdxShape _sourceForLibvisioCurvedTextWrite(VsdxShape shape) {
  return shape.withCurvedText(false).copyWith(
        richText: shape.richText.copyWith(
          textBlock: shape.richText.textBlock.copyWith(hideText: true),
        ),
      );
}

void _collectCurvedTextPlateIds(
  List<VsdxShape> shapes,
  Map<int, List<int>> into,
) {
  for (final shape in shapes) {
    final sourceId = libvisioCurvedTextSourceId(shape);
    if (sourceId != null) {
      (into[sourceId] ??= <int>[]).add(shape.id);
    }
    _collectCurvedTextPlateIds(shape.children, into);
  }
}

bool pageNeedsLibvisioCurvedTextBake(VsdxPage page) {
  var hasPlate = false;
  var needs = false;
  void walk(VsdxShape shape) {
    if (isLibvisioCurvedTextPlate(shape)) {
      hasPlate = true;
    } else if (shapeNeedsLibvisioCurvedTextBake(shape)) {
      needs = true;
    }
    for (final child in shape.children) {
      walk(child);
    }
  }

  for (final shape in page.shapes) {
    walk(shape);
  }
  return hasPlate || needs;
}

VsdxShape? _findShapeById(List<VsdxShape> shapes, int id) {
  for (final shape in shapes) {
    if (shape.id == id) return shape;
    final nested = _findShapeById(shape.children, id);
    if (nested != null) return nested;
  }
  return null;
}

List<VsdxShape> _bakeCurvedTextTree(
  List<VsdxShape> shapes, {
  required Map<int, List<int>> plateIds,
  required int Function() nextId,
}) {
  final out = <VsdxShape>[];
  var changed = false;
  for (final shape in shapes) {
    if (isLibvisioCurvedTextPlate(shape)) {
      changed = true;
      continue;
    }
    var next = shape;
    if (shape.children.isNotEmpty) {
      final children = _bakeCurvedTextTree(
        shape.children,
        plateIds: plateIds,
        nextId: nextId,
      );
      if (!identical(children, shape.children)) {
        next = shape.copyWith(children: children);
        changed = true;
      }
    }
    if (shapeNeedsLibvisioCurvedTextBake(next)) {
      final plates = _curvedTextPlatesForLibvisioWrite(
        next,
        plateIds: plateIds[next.id] ?? const <int>[],
        nextId: nextId,
      );
      if (plates.isNotEmpty) {
        // Body first, then glyphs: later Draw z-order paints text on top,
        // and later Shadow/Sketch bakes keep that order when they rewrite
        // the source in place.
        out.add(_sourceForLibvisioCurvedTextWrite(next));
        out.addAll(plates);
        changed = true;
        continue;
      }
    } else {
      final existing = plateIds[next.id];
      if (existing != null) {
        out.add(next);
        for (final id in existing) {
          final kept = _findShapeById(shapes, id);
          if (kept != null) {
            out.add(kept);
          }
        }
        changed = true;
        continue;
      }
    }
    out.add(next);
    if (!identical(next, shape)) changed = true;
  }
  return changed ? out : shapes;
}

/// Insert (or keep) the per-glyph siblings Draw uses for Curved Text.
VsdxDocument bakeCurvedTextForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var changed = false;
  for (final page in document.pages) {
    if (!pageNeedsLibvisioCurvedTextBake(page)) {
      pages.add(page);
      continue;
    }
    final plateIds = <int, List<int>>{};
    _collectCurvedTextPlateIds(page.shapes, plateIds);
    var nextId = _maxShapeId(page.shapes) + 1;
    final shapes = _bakeCurvedTextTree(
      page.shapes,
      plateIds: plateIds,
      nextId: () => nextId++,
    );
    if (identical(shapes, page.shapes)) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      changed = true;
    }
  }
  if (!changed) return document;
  return document.copyWith(pages: pages);
}

const _kLibvisioShapeInsideMaxLines = 24;

bool _shapeInsideDefaultTextBlock(VsdxShape shape) {
  final block = shape.richText.textBlock;
  final tw = (block.widthInches ?? shape.width).abs();
  final th = (block.heightInches ?? shape.height).abs();
  return (block.widthInches == null || (tw - shape.width).abs() < 1e-6) &&
      (block.heightInches == null || (th - shape.height).abs() < 1e-6) &&
      (block.pinXInches == null ||
          (block.pinXInches! - shape.width / 2).abs() < 1e-6) &&
      (block.pinYInches == null ||
          (block.pinYInches! - shape.height / 2).abs() < 1e-6);
}

/// `true` when `User.veShapeInside` must become per-line siblings for Draw.
///
/// LibreOffice only calls `VisioDocument::parse`. `tokens.txt` has no User
/// rows, so outline text-flow never becomes ODF. TxtWidth / HideText /
/// HorzAlign *are* collected, so a save places one locked line shape per
/// wrapped band canvas / SVG already paint, then hides the source and
/// drops the User row. Glueable 1-D labels, vertical text, curved text,
/// tabbed labels and TxtAngle stay native. FlipX / FlipY extra text
/// mirrors about TxtPin are baked so Draw keeps the upright bands.
bool shapeNeedsLibvisioShapeInsideBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  if (shape.is1D || shape.isGlueableConnector) return false;
  if (!shape.shapeInside || !shape.supportsShapeInside) return false;
  if (!shape.wordWrap) return false;
  if (shape.curvedText) return false;
  if (shape.richText.textBlock.hideText) return false;
  if (shape.richText.textBlock.textDirection == 1) return false;
  if (shape.richText.textBlock.angleRad.abs() > 1e-12) return false;
  if (shape.fields.isNotEmpty) return false;
  if (!_shapeInsideDefaultTextBlock(shape)) return false;
  final plain = _shapeInsidePlain(shape);
  if (plain.trim().isEmpty) return false;
  if (plain.contains('\t')) return false;
  for (final run in shape.richText.runs) {
    if (run.paraStyle.bullet != 0) return false;
    if (run.paraStyle.indentFirstInches.abs() > 1e-9) return false;
    if (run.paraStyle.indentLeftInches.abs() > 1e-9) return false;
    if (run.paraStyle.indentRightInches.abs() > 1e-9) return false;
  }
  return true;
}

String _shapeInsidePlain(VsdxShape shape) {
  final raw =
      shape.richText.isEmpty ? (shape.text ?? '') : shape.richText.plainText;
  final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final style = shape.richText.runs.isNotEmpty
      ? shape.richText.runs.first.charStyle
      : VsdxCharStyle.defaults;
  return switch (style.textCase) {
    VsdxTextCase.allCaps => text.toUpperCase(),
    VsdxTextCase.initialCaps => _libvisioInitialCaps(text),
    VsdxTextCase.normal => text,
  };
}

VsdxCharStyle _shapeInsideStyle(VsdxShape shape) {
  final style = shape.richText.runs.isNotEmpty
      ? shape.richText.runs.first.charStyle
      : VsdxCharStyle.defaults;
  return style.copyWith(textCase: VsdxTextCase.normal);
}

VsdxParaStyle _shapeInsidePara(VsdxShape shape) =>
    shape.richText.runs.isNotEmpty
        ? shape.richText.runs.first.paraStyle
        : const VsdxParaStyle();

double _shapeInsideLineHeight(VsdxShape shape) {
  final style = _shapeInsideStyle(shape);
  final para = _shapeInsidePara(shape);
  final plain = _shapeInsidePlain(shape);
  var fs = math.max(style.effectiveFontSizeInchesForText(plain), 0.04);
  if (para.lineSpacingAbsoluteInches > 1e-9) {
    return para.lineSpacingAbsoluteInches;
  }
  final mult = para.lineSpacingSolid ? 1.0 : para.lineSpacing;
  return fs *
      (mult <= 0
          ? 1.0
          : mult *
              (para.lineSpacingSolid
                  ? 1.0
                  : kLibreOfficeFontCellLineHeightFactor));
}

List<String> _libvisioWrapUnits(String text) {
  final out = <String>[];
  final buf = StringBuffer();
  bool? inSpace;
  void flush() {
    if (buf.isEmpty) return;
    out.add(buf.toString());
    buf.clear();
  }

  for (final r in text.runes) {
    final ch = String.fromCharCode(r);
    final sp = ch == ' ' || ch == '\t';
    if (inSpace != null && inSpace != sp) flush();
    inSpace = sp;
    buf.write(ch);
  }
  flush();
  return out;
}

List<String> _wrapShapeInsideParagraph(
  String para,
  VsdxCharStyle style,
  double Function(int lineIndex) widthFor,
) {
  if (para.isEmpty) return <String>[''];
  final units = _libvisioWrapUnits(para);
  final lines = <String>[];
  var cur = StringBuffer();
  var curW = 0.0;
  var lineMax = widthFor(0);

  void flush() {
    lines.add(cur.toString());
    cur = StringBuffer();
    curW = 0.0;
    lineMax = widthFor(lines.length);
  }

  for (final unit in units) {
    final uw = nowrapTextAdvanceInches(unit, style);
    final isBlank = unit.trim().isEmpty;
    if (curW > 1e-9 && curW + uw > lineMax && !isBlank) {
      flush();
    }
    if (cur.isEmpty && isBlank) continue;
    if (uw > lineMax && unit.length > 1 && !isBlank) {
      for (final r in unit.runes) {
        final ch = String.fromCharCode(r);
        final cw = nowrapTextAdvanceInches(ch, style);
        if (curW > 1e-9 && curW + cw > lineMax) flush();
        cur.write(ch);
        curW += cw;
      }
      continue;
    }
    cur.write(unit);
    curW += uw;
  }
  if (cur.isNotEmpty || lines.isEmpty) flush();
  return lines;
}

({double left, double right}) _shapeInsideBandInches(
  VsdxShape shape, {
  required double y0,
  required double y1,
  required double tw,
  required double th,
  required double ml,
  required double mr,
  required double padding,
}) {
  final band = shape.shapeInsideBand(y0 / th, y1 / th);
  final left = math.max(ml, (band?.left ?? 0) * tw + padding);
  final right = math.min(tw - mr, (band?.right ?? 1) * tw - padding);
  return (left: left, right: math.max(left + 0.01, right));
}

List<VsdxShape> _shapeInsidePlatesForLibvisioWrite(
  VsdxShape source, {
  required List<int> plateIds,
  required int Function() nextId,
}) {
  final style = _shapeInsideStyle(source);
  final para = _shapeInsidePara(source);
  final plain = _shapeInsidePlain(source);
  final block = source.richText.textBlock;
  final tw = (block.widthInches ?? source.width).abs();
  final th = (block.heightInches ?? source.height).abs();
  final ml = block.marginLeftInches;
  final mr = block.marginRightInches;
  final mt = block.marginTopInches;
  final mb = block.marginBottomInches;
  final padding = source.shapeInsidePaddingPx / kLibvisioShapeInsidePxPerInch;
  final lineHeight = _shapeInsideLineHeight(source);
  if (tw <= 1e-9 || th <= 1e-9 || lineHeight <= 1e-9) {
    return const <VsdxShape>[];
  }
  final paragraphs = plain.split('\n');
  var top = mt;
  var lines = <String>[];
  for (var pass = 0; pass < 3; pass++) {
    lines = <String>[];
    var index = 0;
    for (final paraText in paragraphs) {
      final wrapped = _wrapShapeInsideParagraph(
        paraText,
        style,
        (i) {
          final y0 = top + (index + i) * lineHeight;
          return _shapeInsideBandInches(
                source,
                y0: y0,
                y1: y0 + lineHeight,
                tw: tw,
                th: th,
                ml: ml,
                mr: mr,
                padding: padding,
              ).right -
              _shapeInsideBandInches(
                source,
                y0: y0,
                y1: y0 + lineHeight,
                tw: tw,
                th: th,
                ml: ml,
                mr: mr,
                padding: padding,
              ).left;
        },
      );
      lines.addAll(wrapped);
      index += wrapped.length;
    }
    final total = lines.length * lineHeight;
    top = switch (block.verticalAlign) {
      VsdxVertAlign.top => mt,
      VsdxVertAlign.bottom => th - mb - total,
      VsdxVertAlign.middle => mt + (th - mt - mb - total) / 2,
    };
  }
  var visible = 0;
  for (final line in lines) {
    if (line.trim().isNotEmpty) visible++;
  }
  if (visible == 0 || visible > _kLibvisioShapeInsideMaxLines) {
    return const <VsdxShape>[];
  }

  final pinX = block.pinXInches ?? source.width / 2;
  final pinY = block.pinYInches ?? source.height / 2;
  final locX = block.locPinXInches ?? tw / 2;
  final locY = block.locPinYInches ?? th / 2;
  final originX = pinX - locX;
  final originY = pinY - locY;
  final out = <VsdxShape>[];
  var glyph = 0;
  for (var i = 0; i < lines.length; i++) {
    final text = lines[i].trim();
    if (text.isEmpty) continue;
    final y0 = top + i * lineHeight;
    final band = _shapeInsideBandInches(
      source,
      y0: y0,
      y1: y0 + lineHeight,
      tw: tw,
      th: th,
      ml: ml,
      mr: mr,
      padding: padding,
    );
    final bw = band.right - band.left;
    final midX = (band.left + band.right) / 2;
    final midYDown = y0 + lineHeight / 2;
    final local = _textFlipAboutPin(
      source,
      Offset2D(originX + midX, originY + th - midYDown),
    );
    final page = _parentFromLocal(source, local);
    final id = glyph < plateIds.length ? plateIds[glyph] : nextId();
    out.add(
      VsdxShapeFactory.rectangle(
        id: id,
        pinX: page.x,
        pinY: page.y,
        width: bw,
        height: lineHeight,
        fill: const VsdxFill(pattern: 0),
        line: const VsdxLine(pattern: 0),
        name: '$kLibvisioShapeInsideShapeNamePrefix$glyph.${source.id}',
      ).copyWith(
        locPinXInches: bw / 2,
        locPinYInches: lineHeight / 2,
        angleRad: source.angleRad,
        locked: true,
        layerMemberIds: source.layerMemberIds,
        text: text,
        richText: VsdxRichText(
          runs: <VsdxTextRun>[
            VsdxTextRun(
              text: text,
              charStyle: style,
              paraStyle: VsdxParaStyle(
                horizontalAlign: para.effectiveHorizontalAlign,
              ),
            ),
          ],
          textBlock: VsdxTextBlock(
            widthInches: bw,
            heightInches: lineHeight,
            locPinXInches: bw / 2,
            locPinYInches: lineHeight / 2,
            verticalAlign: VsdxVertAlign.middle,
          ),
        ),
      ),
    );
    glyph++;
  }
  return out;
}

VsdxShape _sourceForLibvisioShapeInsideWrite(VsdxShape shape) {
  final others = <VsdxUserCell>[
    for (final cell in shape.userCells)
      if (cell.name != VsdxShape.userShapeInside &&
          cell.name != VsdxShape.userShapeInsidePadding)
        cell,
  ];
  return shape.copyWith(
    userCells: others,
    richText: shape.richText.copyWith(
      textBlock: shape.richText.textBlock.copyWith(hideText: true),
    ),
  );
}

void _collectShapeInsidePlateIds(
  List<VsdxShape> shapes,
  Map<int, List<int>> into,
) {
  for (final shape in shapes) {
    final sourceId = libvisioShapeInsideSourceId(shape);
    if (sourceId != null) {
      (into[sourceId] ??= <int>[]).add(shape.id);
    }
    _collectShapeInsidePlateIds(shape.children, into);
  }
}

bool pageNeedsLibvisioShapeInsideBake(VsdxPage page) {
  var hasPlate = false;
  var needs = false;
  void walk(VsdxShape shape) {
    if (isLibvisioShapeInsidePlate(shape)) {
      hasPlate = true;
    } else if (shapeNeedsLibvisioShapeInsideBake(shape)) {
      needs = true;
    }
    for (final child in shape.children) {
      walk(child);
    }
  }

  for (final shape in page.shapes) {
    walk(shape);
  }
  return hasPlate || needs;
}

List<VsdxShape> _bakeShapeInsideTree(
  List<VsdxShape> shapes, {
  required Map<int, List<int>> plateIds,
  required int Function() nextId,
}) {
  final out = <VsdxShape>[];
  var changed = false;
  for (final shape in shapes) {
    if (isLibvisioShapeInsidePlate(shape)) {
      changed = true;
      continue;
    }
    var next = shape;
    if (shape.children.isNotEmpty) {
      final children = _bakeShapeInsideTree(
        shape.children,
        plateIds: plateIds,
        nextId: nextId,
      );
      if (!identical(children, shape.children)) {
        next = shape.copyWith(children: children);
        changed = true;
      }
    }
    if (shapeNeedsLibvisioShapeInsideBake(next)) {
      final plates = _shapeInsidePlatesForLibvisioWrite(
        next,
        plateIds: plateIds[next.id] ?? const <int>[],
        nextId: nextId,
      );
      if (plates.isNotEmpty) {
        out.add(_sourceForLibvisioShapeInsideWrite(next));
        out.addAll(plates);
        changed = true;
        continue;
      }
    } else {
      final existing = plateIds[next.id];
      if (existing != null) {
        out.add(next);
        for (final id in existing) {
          final kept = _findShapeById(shapes, id);
          if (kept != null) {
            out.add(kept);
          }
        }
        changed = true;
        continue;
      }
    }
    out.add(next);
    if (!identical(next, shape)) changed = true;
  }
  return changed ? out : shapes;
}

/// Insert (or keep) the per-line siblings Draw uses for Shape Inside.
VsdxDocument bakeShapeInsideForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var changed = false;
  for (final page in document.pages) {
    if (!pageNeedsLibvisioShapeInsideBake(page)) {
      pages.add(page);
      continue;
    }
    final plateIds = <int, List<int>>{};
    _collectShapeInsidePlateIds(page.shapes, plateIds);
    var nextId = _maxShapeId(page.shapes) + 1;
    final shapes = _bakeShapeInsideTree(
      page.shapes,
      plateIds: plateIds,
      nextId: () => nextId++,
    );
    if (identical(shapes, page.shapes)) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      changed = true;
    }
  }
  if (!changed) return document;
  return document.copyWith(pages: pages);
}

/// `true` when `User.veAutoRotateLabel` must become a `TxtAngle` Draw paints.
///
/// LibreOffice only calls `VisioDocument::parse`. `tokens.txt` has no User
/// rows, so `labelAutoRotate` never becomes ODF rotation. `TxtAngle` *is*
/// collected (`m_txtxform->angle` → `transformAngle`), so a save writes the
/// same upright route tangent canvas / SVG already paint and drops the
/// User row. Vertices stay native.
bool shapeNeedsLibvisioAutoRotateLabelBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  if (!shape.isGlueableConnector) return false;
  if (!shape.autoRotateLabel) return false;
  if (shape.richText.textBlock.hideText) return false;
  if (shape.richText.textBlock.textDirection == 1) return false;
  return !shape.richText.isEmpty ||
      (shape.text != null && shape.text!.isNotEmpty);
}

Offset2D _libvisioRouteMidpoint(List<Offset2D> route) {
  if (route.isEmpty) return const Offset2D(0, 0);
  if (route.length == 1) return route.first;
  var total = 0.0;
  for (var i = 1; i < route.length; i++) {
    final dx = route[i].x - route[i - 1].x;
    final dy = route[i].y - route[i - 1].y;
    total += math.sqrt(dx * dx + dy * dy);
  }
  if (total <= 1e-18) return route.first;
  var remaining = total / 2;
  for (var i = 1; i < route.length; i++) {
    final a = route[i - 1];
    final b = route[i];
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length >= remaining) {
      final t = length <= 1e-18 ? 0.0 : remaining / length;
      return Offset2D(a.x + dx * t, a.y + dy * t);
    }
    remaining -= length;
  }
  return route.last;
}

bool _autoRotateLabelDefaultFrame(VsdxShape shape) {
  final block = shape.richText.textBlock;
  return block.pinXInches == null &&
      block.pinYInches == null &&
      block.widthInches == null &&
      block.heightInches == null;
}

bool _hasLooseEdgeLabelText(VsdxShape shape) {
  if (shape.richText.textBlock.hideText) return false;
  final plain =
      shape.richText.isEmpty ? (shape.text ?? '') : shape.richText.plainText;
  return plain.trim().isNotEmpty;
}

/// Pin a tight text box on the drawn-route midpoint canvas / SVG already use.
///
/// LibreOffice's collector falls back to the 1-D XForm (`m_xform.width/2`)
/// when `m_txtxform` is missing, which is the Begin–End box — not the
/// polyline. TxtPin / TxtWidth *are* collected.
VsdxShape _applyLooseEdgeLabelFrame(VsdxShape shape, VsdxPage page) {
  if (!_autoRotateLabelDefaultFrame(shape)) return shape;
  final previous = shape.richText.textBlock;
  final style = shape.richText.runs.isNotEmpty
      ? shape.richText.runs.first.charStyle
      : VsdxCharStyle.defaults;
  final plain =
      shape.richText.isEmpty ? (shape.text ?? '') : shape.richText.plainText;
  final lines =
      plain.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  var fs = math.max(style.effectiveFontSizeInchesForText(plain), 0.04);
  if (style.position != VsdxTextPosition.normal) fs *= 0.7;
  final lineHeight = fs * kLibreOfficeFontCellLineHeightFactor;
  final tw = math.max(
    nowrapLabelAdvanceInches(shape) +
        previous.marginLeftInches +
        previous.marginRightInches +
        0.06,
    0.2,
  );
  final th = math.max(
    lines.length * lineHeight +
        previous.marginTopInches +
        previous.marginBottomInches,
    0.2,
  );
  final route = page.drawnConnectorPagePolyline(shape);
  final mid = route.length >= 2
      ? _libvisioRouteMidpoint(route)
      : VsdxPage.connectorMidpoint(shape);
  final local = page.pageToLocalDeep(shape.id, mid);
  return shape.copyWith(
    richText: shape.richText.copyWith(
      textBlock: VsdxTextBlock(
        pinXInches: local.x,
        pinYInches: local.y,
        locPinXInches: tw / 2,
        locPinYInches: th / 2,
        widthInches: tw,
        heightInches: th,
        angleRad: previous.angleRad,
        verticalAlign: previous.verticalAlign,
        marginLeftInches: previous.marginLeftInches,
        marginRightInches: previous.marginRightInches,
        marginTopInches: previous.marginTopInches,
        marginBottomInches: previous.marginBottomInches,
        hideText: previous.hideText,
        backgroundColor: previous.backgroundColor,
        backgroundTransparency: previous.backgroundTransparency,
        textDirection: previous.textDirection,
        defaultTabStopInches: previous.defaultTabStopInches,
      ),
    ),
  );
}

VsdxShape _sourceForLibvisioAutoRotateLabelWrite(
  VsdxShape shape,
  VsdxPage page,
) {
  final others = <VsdxUserCell>[
    for (final cell in shape.userCells)
      if (cell.name != VsdxShape.userAutoRotateLabel) cell,
  ];
  final framed = _applyLooseEdgeLabelFrame(shape, page);
  final previous = framed.richText.textBlock;
  final angle = page.effectiveConnectorLabelAngle(shape);
  // `copyWith(angleRad: 0)` cannot clear a previous TxtAngle because `??`
  // treats 0 as absent. Reconstruct so a horizontal route still writes 0.
  final block = VsdxTextBlock(
    pinXInches: previous.pinXInches,
    pinYInches: previous.pinYInches,
    locPinXInches: previous.locPinXInches,
    locPinYInches: previous.locPinYInches,
    widthInches: previous.widthInches,
    heightInches: previous.heightInches,
    angleRad: angle,
    verticalAlign: previous.verticalAlign,
    marginLeftInches: previous.marginLeftInches,
    marginRightInches: previous.marginRightInches,
    marginTopInches: previous.marginTopInches,
    marginBottomInches: previous.marginBottomInches,
    hideText: previous.hideText,
    backgroundColor: previous.backgroundColor,
    backgroundTransparency: previous.backgroundTransparency,
    textDirection: previous.textDirection,
    defaultTabStopInches: previous.defaultTabStopInches,
  );
  return framed.copyWith(
    userCells: others,
    richText: framed.richText.copyWith(textBlock: block),
  );
}

VsdxShape bakeAutoRotateLabelShapeForLibvisioWrite(
  VsdxShape shape,
  VsdxPage page,
) {
  final children = <VsdxShape>[
    for (final child in shape.children)
      bakeAutoRotateLabelShapeForLibvisioWrite(child, page),
  ];
  var childrenChanged = children.length != shape.children.length;
  if (!childrenChanged) {
    for (var i = 0; i < children.length; i++) {
      if (!identical(children[i], shape.children[i])) {
        childrenChanged = true;
        break;
      }
    }
  }
  var next = shapeNeedsLibvisioAutoRotateLabelBake(shape)
      ? _sourceForLibvisioAutoRotateLabelWrite(shape, page)
      : shape;
  if (childrenChanged) next = next.copyWith(children: children);
  return next;
}

/// Write `TxtAngle` Draw collects for Rotate with Edge, then drop the User row.
VsdxDocument bakeAutoRotateLabelForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var pagesChanged = false;
  for (final page in document.pages) {
    final shapes = <VsdxShape>[
      for (final shape in page.shapes)
        bakeAutoRotateLabelShapeForLibvisioWrite(shape, page),
    ];
    var same = shapes.length == page.shapes.length;
    if (same) {
      for (var i = 0; i < shapes.length; i++) {
        if (!identical(shapes[i], page.shapes[i])) {
          same = false;
          break;
        }
      }
    }
    if (same) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      pagesChanged = true;
    }
  }
  if (!pagesChanged) return document;
  return document.copyWith(pages: pages);
}

/// `true` when a glueable connector label with no `TxtPin` must become a
/// tight `TxtPin` / `TxtWidth` box Draw will collect.
///
/// LibreOffice only calls `VisioDocument::parse`. Missing `m_txtxform`
/// falls back to the 1-D XForm centre (Begin–End box). Canvas / SVG pin
/// a tight plate on the drawn-route midpoint. Rotate-with-Edge already
/// writes that frame; this covers labels that are not auto-rotated.
bool shapeNeedsLibvisioLooseEdgeLabelBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  if (!shape.isGlueableConnector) return false;
  if (!_autoRotateLabelDefaultFrame(shape)) return false;
  return _hasLooseEdgeLabelText(shape);
}

VsdxShape bakeLooseEdgeLabelShapeForLibvisioWrite(
  VsdxShape shape,
  VsdxPage page,
) {
  final children = <VsdxShape>[
    for (final child in shape.children)
      bakeLooseEdgeLabelShapeForLibvisioWrite(child, page),
  ];
  var childrenChanged = children.length != shape.children.length;
  if (!childrenChanged) {
    for (var i = 0; i < children.length; i++) {
      if (!identical(children[i], shape.children[i])) {
        childrenChanged = true;
        break;
      }
    }
  }
  var next = shapeNeedsLibvisioLooseEdgeLabelBake(shape)
      ? _applyLooseEdgeLabelFrame(shape, page)
      : shape;
  if (childrenChanged) next = next.copyWith(children: children);
  return next;
}

/// Write TxtPin on the route midpoint so Draw matches canvas edge labels.
VsdxDocument bakeLooseEdgeLabelForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var pagesChanged = false;
  for (final page in document.pages) {
    final shapes = <VsdxShape>[
      for (final shape in page.shapes)
        bakeLooseEdgeLabelShapeForLibvisioWrite(shape, page),
    ];
    var same = shapes.length == page.shapes.length;
    if (same) {
      for (var i = 0; i < shapes.length; i++) {
        if (!identical(shapes[i], page.shapes[i])) {
          same = false;
          break;
        }
      }
    }
    if (same) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      pagesChanged = true;
    }
  }
  if (!pagesChanged) return document;
  return document.copyWith(pages: pages);
}

/// `true` when `User.veOpacity` must fold into cells Draw actually paints.
///
/// LibreOffice only calls `VisioDocument::parse`. `tokens.txt` has no User
/// rows, so `veOpacity` never becomes ODF `draw:opacity`. FillForegndTrans
/// *is* collected (`VSDContentCollector` maps it to `draw:opacity`), and
/// unfilled LineColorTrans already bakes a FillForegndTrans ribbon, so a
/// save multiplies the extra transparency into Fill / Line / Glow /
/// Reflection / Shadow / image / text, then drops the User row.
bool shapeNeedsLibvisioOpacityBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  return shape.shapeOpacity < 1 - 1e-9;
}

VsdxGradient? _gradientWithExtraTransparency(
  VsdxGradient? gradient,
  double extra,
) {
  if (gradient == null || extra <= 1e-9) return gradient;
  return VsdxGradient(
    stops: <VsdxGradientStop>[
      for (final stop in gradient.stops)
        VsdxGradientStop(
          position: stop.position,
          color: stop.color,
          themeColorIndex: stop.themeColorIndex,
          transparency: _combinedTransparency(stop.transparency, extra),
        ),
    ],
    type: gradient.type,
    angleRad: gradient.angleRad,
    dir: gradient.dir,
  );
}

VsdxFill _fillWithExtraTransparency(VsdxFill fill, double extra) {
  return fill.copyWith(
    foregroundTransparency:
        _combinedTransparency(fill.foregroundTransparency, extra),
    backgroundTransparency:
        _combinedTransparency(fill.backgroundTransparency, extra),
    gradient: _gradientWithExtraTransparency(fill.gradient, extra),
  );
}

VsdxLine _lineWithExtraTransparency(VsdxLine line, double extra) {
  var next = line.copyWith(
    transparency: _combinedTransparency(line.transparency, extra),
  );
  final gradient = _gradientWithExtraTransparency(line.gradient, extra);
  if (!identical(gradient, line.gradient)) {
    next = next.copyWith(gradient: gradient);
  }
  return next;
}

VsdxRichText _richTextWithExtraTransparency(VsdxRichText rich, double extra) {
  return rich.copyWith(
    runs: <VsdxTextRun>[
      for (final run in rich.runs)
        run.copyWith(
          charStyle: run.charStyle.copyWith(
            transparency: _combinedTransparency(
              run.charStyle.transparency,
              extra,
            ),
          ),
        ),
    ],
    textBlock: rich.textBlock.copyWith(
      backgroundTransparency: _combinedTransparency(
        rich.textBlock.backgroundTransparency,
        extra,
      ),
    ),
  );
}

VsdxShape _applyOpacityForLibvisioWrite(VsdxShape shape, double extra) {
  var next = shape.withShapeOpacity(1);
  if (extra <= 1e-9) return next;
  if (next.fill.hasFill) {
    next = next.copyWith(fill: _fillWithExtraTransparency(next.fill, extra));
  }
  if (next.line.hasLine) {
    next = next.copyWith(line: _lineWithExtraTransparency(next.line, extra));
  }
  if (next.glow.enabled) {
    next = next.copyWith(
      glow: next.glow.copyWith(
        transparency: _combinedTransparency(next.glow.transparency, extra),
      ),
    );
  }
  if (next.reflection.enabled) {
    next = next.copyWith(
      reflection: next.reflection.copyWith(
        transparency:
            _combinedTransparency(next.reflection.transparency, extra),
      ),
    );
  }
  if (next.shadow.enabled) {
    next = next.copyWith(
      shadow: next.shadow.copyWith(
        transparency: _combinedTransparency(next.shadow.transparency, extra),
      ),
    );
  }
  if (next.hasImage) {
    next = next.copyWith(
      imageTransparency: _combinedTransparency(next.imageTransparency, extra),
    );
  }
  if (next.richText.runs.isNotEmpty ||
      next.richText.textBlock.backgroundColor != null) {
    next = next.copyWith(
      richText: _richTextWithExtraTransparency(next.richText, extra),
    );
  }
  return next;
}

VsdxShape bakeShapeOpacityShapeForLibvisioWrite(
  VsdxShape shape, {
  double inheritedExtra = 0,
}) {
  final extra = _combinedTransparency(1 - shape.shapeOpacity, inheritedExtra);
  final children = <VsdxShape>[
    for (final child in shape.children)
      bakeShapeOpacityShapeForLibvisioWrite(child, inheritedExtra: extra),
  ];
  var next = extra > 1e-9 || shapeNeedsLibvisioOpacityBake(shape)
      ? _applyOpacityForLibvisioWrite(shape, extra)
      : shape;
  var childrenChanged = children.length != shape.children.length;
  if (!childrenChanged) {
    for (var i = 0; i < children.length; i++) {
      if (!identical(children[i], shape.children[i])) {
        childrenChanged = true;
        break;
      }
    }
  }
  if (childrenChanged) next = next.copyWith(children: children);
  return next;
}

/// Fold `User.veOpacity` into FillForegndTrans / LineColorTrans cells Draw
/// collects, including inherited fade on grouped children.
VsdxDocument bakeShapeOpacityForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var pagesChanged = false;
  for (final page in document.pages) {
    final shapes = <VsdxShape>[
      for (final shape in page.shapes)
        bakeShapeOpacityShapeForLibvisioWrite(shape),
    ];
    var same = shapes.length == page.shapes.length;
    if (same) {
      for (var i = 0; i < shapes.length; i++) {
        if (!identical(shapes[i], page.shapes[i])) {
          same = false;
          break;
        }
      }
    }
    if (same) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      pagesChanged = true;
    }
  }
  if (!pagesChanged) return document;
  return document.copyWith(pages: pages);
}

/// SoftEdgesSize Draw will collect for this picture (0 = do not bake).
///
/// Canvas / SVG feather the visible Img* window, clipped to the Foreign
/// frame. `tokens.txt` has no SoftEdgesSize, so a 2-D bitmap bakes that
/// halo into PNG alpha. Cropped frames composite into the box first;
/// uncropped frames feather the bitmap in place.
double imageSoftEdgesInchesForLibvisioWrite(VsdxShape shape) {
  if (!shape.hasImage || shape.is1D) return 0;
  if (shape.width.abs() <= 1e-9 || shape.height.abs() <= 1e-9) return 0;
  return shape.line.softEdgesInches;
}

/// `true` when SoftEdges must composite Img* crop into the Foreign frame.
bool shapeNeedsLibvisioCroppedSoftEdgesBake(VsdxShape shape) {
  if (imageSoftEdgesInchesForLibvisioWrite(shape) <= 1e-6) return false;
  return visioPictureFrameIsCropped(
    frameWidthInches: shape.width,
    frameHeightInches: shape.height,
    imgOffsetXInches: shape.imgOffsetXInches,
    imgOffsetYInches: shape.imgOffsetYInches,
    imgWidthInches: shape.imgWidthInches,
    imgHeightInches: shape.imgHeightInches,
  );
}

/// Bake Image Properties into PNG pixels and reset the cells Draw ignores.
VsdxDocument bakeImageAdjustmentsForLibvisioWrite(VsdxDocument document) {
  var registry = document.images;
  final used = <String>{
    for (final image in document.images.all) image.partName,
  };
  final cache = <String, String>{};
  var changed = false;

  String allocatePart(int shapeId) {
    var name = '/visio/media/image_lo_tone_$shapeId.png';
    var n = 0;
    while (used.contains(name) || registry.findByPart(name) != null) {
      n++;
      name = '/visio/media/image_lo_tone_${shapeId}_$n.png';
    }
    used.add(name);
    return name;
  }

  VsdxShape rewrite(VsdxShape shape) {
    final children = <VsdxShape>[
      for (final child in shape.children) rewrite(child),
    ];
    var next = shape;
    final soft = imageSoftEdgesInchesForLibvisioWrite(shape);
    final cropSoft = shapeNeedsLibvisioCroppedSoftEdgesBake(shape);
    if (shape.hasImage &&
        visioImageAdjustmentsNeedBake(
          transparency: shape.imageTransparency,
          blur: shape.imageBlur,
          brightness: shape.imageBrightness,
          contrast: shape.imageContrast,
          softEdgesInches: soft,
        )) {
      final part = shape.imagePartName;
      final source = part == null
          ? null
          : (document.images.findByPart(part) ??
              document.images.findByPart(
                part.startsWith('/') ? part.substring(1) : '/$part',
              ));
      if (source != null) {
        final key = '$part|${shape.imageTransparency}|${shape.imageBlur}|'
            '${shape.imageBrightness}|${shape.imageContrast}|$soft|'
            '${shape.effectiveImgWidth}|${shape.effectiveImgHeight}|'
            '${shape.imgOffsetXInches}|${shape.imgOffsetYInches}|'
            '${shape.width}|${shape.height}|$cropSoft';
        var bakedPart = cache[key];
        if (bakedPart == null) {
          final png = bakeVisioImageAdjustmentsPng(
            image: source,
            transparency: shape.imageTransparency,
            blur: shape.imageBlur,
            brightness: shape.imageBrightness,
            contrast: shape.imageContrast,
            displayWidthInches:
                cropSoft ? shape.width.abs() : shape.effectiveImgWidth,
            softEdgesInches: soft,
            frameWidthInches: cropSoft ? shape.width : 0,
            frameHeightInches: cropSoft ? shape.height : 0,
            imgOffsetXInches: shape.imgOffsetXInches,
            imgOffsetYInches: shape.imgOffsetYInches,
            imgWidthInches: shape.imgWidthInches,
            imgHeightInches: shape.imgHeightInches,
          );
          if (png != null) {
            bakedPart = allocatePart(shape.id);
            cache[key] = bakedPart;
            registry = registry.withImage(
              VsdxImage(
                partName: bakedPart,
                bytes: png,
                mimeType: 'image/png',
              ),
            );
          }
        }
        if (bakedPart != null) {
          next = shape.copyWith(
            imagePartName: bakedPart,
            foreignType: VsdxImage.foreignTypeFor(
              mimeType: 'image/png',
              partName: bakedPart,
            ),
            foreignCompressionType: VsdxImage.compressionTypeFor(
              mimeType: 'image/png',
              partName: bakedPart,
            ),
            imageTransparency: 0,
            imageBlur: 0,
            imageBrightness: 0.5,
            imageContrast: 0.5,
            line: soft > 1e-6
                ? shape.line.copyWith(softEdgesInches: 0)
                : shape.line,
            imgOffsetXInches: cropSoft ? 0 : shape.imgOffsetXInches,
            imgOffsetYInches: cropSoft ? 0 : shape.imgOffsetYInches,
            imgWidthInches: cropSoft ? shape.width : shape.imgWidthInches,
            imgHeightInches: cropSoft ? shape.height : shape.imgHeightInches,
          );
          changed = true;
        }
      }
    }
    var childrenChanged = children.length != shape.children.length;
    if (!childrenChanged) {
      for (var i = 0; i < children.length; i++) {
        if (!identical(children[i], shape.children[i])) {
          childrenChanged = true;
          break;
        }
      }
    }
    if (childrenChanged) {
      next = next.copyWith(children: children);
      changed = true;
    }
    return next;
  }

  if (document.pages.isEmpty && document.images.length == 0) {
    return document;
  }
  final pages = <VsdxPage>[];
  var pagesChanged = false;
  for (final page in document.pages) {
    final shapes = <VsdxShape>[
      for (final shape in page.shapes) rewrite(shape),
    ];
    var same = shapes.length == page.shapes.length;
    if (same) {
      for (var i = 0; i < shapes.length; i++) {
        if (!identical(shapes[i], page.shapes[i])) {
          same = false;
          break;
        }
      }
    }
    if (same) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      pagesChanged = true;
    }
  }
  if (!changed && !pagesChanged) return document;
  return document.copyWith(
    pages: pagesChanged ? pages : document.pages,
    images: registry,
  );
}

/// `true` when geometry `SoftEdgesSize` must become a feathered PNG for Draw.
///
/// LibreOffice only calls `VisioDocument::parse`. `tokens.txt` has no
/// SoftEdgesSize, so Draw paints a hard fill or a hard stroke. Picture
/// SoftEdges already feathers PNG alpha; a filled 2-D vector bakes the
/// same SourceAlpha treatment into a locked Foreign sibling, then the
/// source fill is dropped so the plate is the body. An unfilled 2-D
/// stroke bakes the stroke ring the same way and drops the source line.
/// A filled 2-D shape that also paints a solid or dashed stroke bakes both into
/// one padded plate and drops fill and line, so Draw does not keep a
/// hard outline. Gradient / hatch fills with a stroke join that plate.
/// CompoundType 1–4 rails join that plate too. LineGradient strokes
/// with resolved-RGB or theme-only stops join that plate so Draw does
/// not keep a hard opaque outline. Rounding fillets join that plate so
/// Draw does not keep square corners after the fill is dropped.
/// Theme-only FillForegnd / LineColor / gradient stops (canvas
/// `_colourOrTheme` / `_fillColour`) resolve through the document theme,
/// then Office, into that PNG so Draw keeps the feather. 1-D, pictures,
/// open-path arrows, and unrecognised geometry stay native. Closed 2-D
/// arrow cells do not block the bake — libvisio suppresses markers on
/// Z-closed subpaths, same as canvas.
bool shapeNeedsLibvisioGeometrySoftEdgesBake(VsdxShape shape) =>
    _shapeNeedsLibvisioFillSoftEdgesBake(shape) ||
    _shapeNeedsLibvisioStrokeSoftEdgesBake(shape);

bool _softEdgesCommonOk(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  if (shape.is1D || shape.hasImage) return false;
  if (shape.children.isNotEmpty) return false;
  if (shape.line.softEdgesInches <= 1e-6) return false;
  if (shape.width.abs() <= 1e-9 || shape.height.abs() <= 1e-9) return false;
  if (shape.sketchEffect) return false;
  return true;
}

bool _shapeNeedsLibvisioFillSoftEdgesBake(VsdxShape shape) {
  if (!_softEdgesCommonOk(shape)) return false;
  if (!shape.fill.hasFill) return false;
  final paintGradient = shape.fill.paintGradient;
  if (paintGradient != null) {
    if (_gradientBakeStops(paintGradient, shape.fill.foregroundTransparency)
        .isEmpty) {
      return false;
    }
  } else if (libvisioHatchSpec(shape.fill.pattern) != null) {
    // Theme-only FillForegnd still skips: a bake drops the hatch cells
    // (audit_probe keeps theme FG/BG + SoftEdgesSize). RGB FG + theme
    // FillBkgnd is safe — the PNG sampler already freezes that slot.
    if (shape.fill.foreground == null) return false;
  } else {
    if (shape.fill.pattern != 1) return false;
    if (shape.fill.foreground == null &&
        shape.fill.themeForegroundIndex == null) {
      return false;
    }
  }
  return _softEdgesSilhouetteKind(shape) != null;
}

bool _shapeHasSoftEdgesDashes(VsdxShape shape) {
  final dashes = effectiveDashPatternForLine(shape.line);
  return dashes != null && dashes.isNotEmpty;
}

bool _shapeHasBakeableSoftEdgesStroke(VsdxShape shape) {
  if (!shape.line.hasLine) return false;
  final dashed = _shapeHasSoftEdgesDashes(shape);
  if (shape.line.pattern != 1 && !dashed) return false;
  if (shape.line.hasGradient && _softEdgesLineColorAt(shape) == null) {
    return false;
  }
  if (_openArrowheadsBlockStrokeBake(shape)) return false;
  if (shape.line.compoundType != 0) {
    return _softEdgesCompoundRibbonPolygons(shape).isNotEmpty;
  }
  if (dashed) {
    return _softEdgesDashRibbonPolygons(shape).isNotEmpty;
  }
  return _softEdgesStrokeSilhouetteKind(shape) != null;
}

bool _shapeNeedsLibvisioStrokeSoftEdgesBake(VsdxShape shape) {
  if (!_softEdgesCommonOk(shape)) return false;
  if (_shapeNeedsLibvisioFillSoftEdgesBake(shape)) return false;
  return _shapeHasBakeableSoftEdgesStroke(shape);
}

bool _shapeNeedsLibvisioFillStrokeSoftEdgesBake(VsdxShape shape) =>
    _shapeNeedsLibvisioFillSoftEdgesBake(shape) &&
    _shapeHasBakeableSoftEdgesStroke(shape);

SoftEdgesSilhouetteKind? _softEdgesSilhouetteKind(VsdxShape shape) {
  VsdxGeometry? geom;
  for (final candidate in shape.geometries) {
    if (candidate.noShow || candidate.noFill) continue;
    geom = candidate;
    break;
  }
  if (geom == null) return null;
  if (geom.commands.length == 1 && geom.commands.first is EllipseCmd) {
    return SoftEdgesSilhouetteKind.ellipse;
  }
  final points = _softEdgesPolygonInches(shape, geom);
  if (points == null || points.length < 3) return null;
  if (shape.line.roundingInches > 1e-12) {
    return SoftEdgesSilhouetteKind.polygon;
  }
  if (_softEdgesIsShapeBox(points, shape.width, shape.height)) {
    return SoftEdgesSilhouetteKind.rectangle;
  }
  return SoftEdgesSilhouetteKind.polygon;
}

SoftEdgesSilhouetteKind? _softEdgesStrokeSilhouetteKind(VsdxShape shape) {
  VsdxGeometry? geom;
  for (final candidate in shape.geometries) {
    if (candidate.noShow || candidate.noLine) continue;
    geom = candidate;
    break;
  }
  if (geom == null) return null;
  if (geom.commands.length == 1 && geom.commands.first is EllipseCmd) {
    return SoftEdgesSilhouetteKind.ellipse;
  }
  final points = _softEdgesPolygonInches(shape, geom);
  if (points == null || points.length < 3) return null;
  if (shape.line.roundingInches > 1e-12) {
    return SoftEdgesSilhouetteKind.polygon;
  }
  if (_softEdgesIsShapeBox(points, shape.width, shape.height)) {
    return SoftEdgesSilhouetteKind.rectangle;
  }
  return SoftEdgesSilhouetteKind.polygon;
}

VsdxGeometry? _softEdgesStrokeGeometry(VsdxShape shape) {
  for (final candidate in shape.geometries) {
    if (candidate.noShow || candidate.noLine) continue;
    return candidate;
  }
  return null;
}

VsdxGeometry? _anyVisibleGeometry(VsdxShape shape) {
  for (final candidate in shape.geometries) {
    if (candidate.noShow) continue;
    return candidate;
  }
  return null;
}

/// Image-frame silhouette canvas uses for Foreign pictures (NoFill/NoLine).
SoftEdgesSilhouetteKind? _foreignFrameSilhouetteKind(VsdxShape shape) {
  if (!shape.hasImage || shape.is1D) return null;
  if (shape.width.abs() <= 1e-9 || shape.height.abs() <= 1e-9) return null;
  final geom = _anyVisibleGeometry(shape);
  if (geom == null) return SoftEdgesSilhouetteKind.rectangle;
  if (geom.commands.length == 1 && geom.commands.first is EllipseCmd) {
    return SoftEdgesSilhouetteKind.ellipse;
  }
  final points = _softEdgesPolygonInches(shape, geom);
  if (points == null || points.length < 3) {
    return SoftEdgesSilhouetteKind.rectangle;
  }
  if (shape.line.roundingInches > 1e-12) {
    return SoftEdgesSilhouetteKind.polygon;
  }
  if (_softEdgesIsShapeBox(points, shape.width, shape.height)) {
    return SoftEdgesSilhouetteKind.rectangle;
  }
  return SoftEdgesSilhouetteKind.polygon;
}

List<Offset2D>? _softEdgesPolygonInches(VsdxShape shape, VsdxGeometry geom) {
  final w = shape.width.abs();
  final h = shape.height.abs();
  final points = <Offset2D>[];
  for (final cmd in geom.commands) {
    switch (cmd) {
      case MoveTo(:final x, :final y):
        if (points.isNotEmpty) return null;
        points.add(Offset2D(x, y));
      case LineTo(:final x, :final y):
        points.add(Offset2D(x, y));
      case RelMoveTo(:final fx, :final fy):
        if (points.isNotEmpty) return null;
        points.add(Offset2D(fx * w, fy * h));
      case RelLineTo(:final fx, :final fy):
        points.add(Offset2D(fx * w, fy * h));
      case QuadBezTo(:final x, :final y):
        points.add(Offset2D(x, y));
      case RelQuadBezTo(:final fx, :final fy):
        points.add(Offset2D(fx * w, fy * h));
      case CubBezTo(:final x, :final y):
        points.add(Offset2D(x, y));
      case RelCubBezTo(:final fx, :final fy):
        points.add(Offset2D(fx * w, fy * h));
      case ArcTo(:final x, :final y):
        points.add(Offset2D(x, y));
      case RelArcTo(:final fx, :final fy):
        points.add(Offset2D(fx * w, fy * h));
      case EllipticalArcTo(:final x, :final y):
        points.add(Offset2D(x, y));
      default:
        return null;
    }
  }
  if (points.length >= 2) {
    final a = points.first;
    final b = points.last;
    if ((a.x - b.x).abs() < 1e-9 && (a.y - b.y).abs() < 1e-9) {
      points.removeLast();
    }
  }
  if (points.length < 3) return points;
  final radius = shape.line.roundingInches;
  if (radius <= 1e-12) return points;
  return filletPolyline(
    points,
    radius,
    closed: polylineLooksClosed(points, noFill: geom.noFill),
  );
}

bool _softEdgesIsShapeBox(List<Offset2D> points, double w, double h) {
  if (points.length < 4) return false;
  var minX = points.first.x;
  var minY = points.first.y;
  var maxX = minX;
  var maxY = minY;
  for (final p in points) {
    if (p.x < minX) minX = p.x;
    if (p.y < minY) minY = p.y;
    if (p.x > maxX) maxX = p.x;
    if (p.y > maxY) maxY = p.y;
  }
  return minX.abs() <= 1e-6 &&
      minY.abs() <= 1e-6 &&
      (maxX - w.abs()).abs() <= 1e-6 &&
      (maxY - h.abs()).abs() <= 1e-6;
}

Uint8List? _softEdgesPngForLibvisioWrite(VsdxShape shape, VsdxTheme theme) {
  final kind = _softEdgesSilhouetteKind(shape);
  if (kind == null) return null;
  final paintGradient = shape.fill.paintGradient;
  final colorAt = _softEdgesFillColorAt(shape, theme);
  if (paintGradient != null && colorAt == null) return null;
  final color = _fillRgbForLibvisioWrite(
    shape.fill,
    theme,
    fillMatrix: shape.quickStyleFillMatrix,
  );
  final trans = shape.fill.foregroundTransparency.clamp(0.0, 1.0);
  final alpha = (color.alpha * (1 - trans)).round().clamp(0, 255);
  final w = shape.width.abs();
  final h = shape.height.abs();
  var widthPx = math.max(8, (w * kLibvisioSoftEdgesPxPerInch).round());
  var heightPx = math.max(8, (h * kLibvisioSoftEdgesPxPerInch).round());
  const maxPx = 1024;
  final longest = math.max(widthPx, heightPx);
  if (longest > maxPx) {
    final scale = maxPx / longest;
    widthPx = math.max(8, (widthPx * scale).round());
    heightPx = math.max(8, (heightPx * scale).round());
  }
  final polygon = <({double x, double y})>[];
  if (kind == SoftEdgesSilhouetteKind.polygon) {
    VsdxGeometry? geom;
    for (final candidate in shape.geometries) {
      if (candidate.noShow || candidate.noFill) continue;
      geom = candidate;
      break;
    }
    final inches = geom == null ? null : _softEdgesPolygonInches(shape, geom);
    if (inches == null) return null;
    for (final p in inches) {
      polygon.add((
        x: p.x / w * (widthPx - 1),
        y: (1 - p.y / h) * (heightPx - 1),
      ));
    }
  }
  return bakeSilhouetteSoftEdgesPng(
    widthPx: widthPx,
    heightPx: heightPx,
    red: color.red,
    green: color.green,
    blue: color.blue,
    alpha: colorAt != null ? 255 : alpha,
    softSigmaPx: shape.line.softEdgesInches / w * widthPx,
    kind: kind,
    polygon: polygon,
    roundingPx: 0,
    colorAt: colorAt == null
        ? null
        : (xPx, yPx) => colorAt(xPx, yPx, widthPx, heightPx),
  );
}

({int r, int g, int b, int a}) Function(
        double xPx, double yPx, int widthPx, int heightPx)?
    _softEdgesFillColorAt(VsdxShape shape, VsdxTheme theme) {
  final w = shape.width.abs();
  final h = shape.height.abs();
  final paintGradient = shape.fill.paintGradient;
  if (paintGradient != null) {
    return _softEdgesGradientSampler(
      paintGradient,
      shape.fill.foregroundTransparency,
      w,
      h,
      theme,
    );
  }
  final hatch = libvisioHatchSpec(shape.fill.pattern);
  if (hatch == null) return null;
  final fg = _fillCellRgba(
    _fillRgbForLibvisioWrite(
      shape.fill,
      theme,
      fillMatrix: shape.quickStyleFillMatrix,
    ),
    shape.fill.foregroundTransparency,
  );
  final bgColor = _fillBackgroundRgbForLibvisioWrite(shape.fill, theme);
  final bg = bgColor == null
      ? (r: 0, g: 0, b: 0, a: 0)
      : _fillCellRgba(bgColor, shape.fill.backgroundTransparency);
  return (xPx, yPx, widthPx, heightPx) {
    final ix = widthPx <= 1 ? 0.0 : xPx / (widthPx - 1) * w;
    final iy = heightPx <= 1 ? h : (1 - yPx / (heightPx - 1)) * h;
    return sampleVisioHatchRgba(
      spec: hatch,
      x: ix,
      y: iy,
      foreground: fg,
      background: bg,
    );
  };
}

({int r, int g, int b, int a}) Function(
    double xPx, double yPx, int widthPx, int heightPx)? _softEdgesLineColorAt(
  VsdxShape shape, [
  VsdxTheme theme = VsdxTheme.empty,
]) {
  final gradient = shape.line.gradient;
  if (gradient == null || gradient.stops.isEmpty) return null;
  return _softEdgesGradientSampler(
    gradient,
    shape.line.transparency,
    shape.width.abs(),
    shape.height.abs(),
    theme,
  );
}

({int r, int g, int b, int a}) Function(
        double xPx, double yPx, int widthPx, int heightPx)?
    _softEdgesGradientSampler(
  VsdxGradient gradient,
  double transparency,
  double w,
  double h, [
  VsdxTheme theme = VsdxTheme.empty,
]) {
  final stops = _gradientBakeStops(gradient, transparency, theme);
  if (stops.isEmpty) return null;
  final linear = gradient.type == VsdxGradientType.linear;
  final angle = gradient.angleRad;
  final dir = gradient.dir;
  return (xPx, yPx, widthPx, heightPx) {
    final ix = widthPx <= 1 ? 0.0 : xPx / (widthPx - 1) * w;
    final iy = heightPx <= 1 ? h : (1 - yPx / (heightPx - 1)) * h;
    return sampleVisioGradientRgba(
      x: ix,
      y: iy,
      minX: 0,
      minY: 0,
      width: w,
      height: h,
      linear: linear,
      angleRad: angle,
      dir: dir,
      stops: stops,
    );
  };
}

List<({double position, int r, int g, int b, int a})> _gradientBakeStops(
  VsdxGradient gradient,
  double fillTransparency, [
  VsdxTheme theme = VsdxTheme.empty,
]) {
  final fillAlpha = 1 - fillTransparency.clamp(0.0, 1.0);
  final out = <({double position, int r, int g, int b, int a})>[];
  for (final stop in gradient.stops) {
    final color = _gradientStopRgbForLibvisioWrite(stop, theme);
    if (color == null) return const [];
    final a =
        (color.alpha * (1 - stop.transparency.clamp(0.0, 1.0)) * fillAlpha)
            .round()
            .clamp(0, 255);
    out.add((
      position: stop.position,
      r: color.red,
      g: color.green,
      b: color.blue,
      a: a,
    ));
  }
  if (out.isEmpty || out.every((stop) => stop.a <= 0)) {
    return const [];
  }
  return out;
}

({int r, int g, int b, int a}) _fillCellRgba(
  VsdxColor? color,
  double transparency,
) {
  final c = color ?? const VsdxColor(0x00000000);
  final a =
      (c.alpha * (1 - transparency.clamp(0.0, 1.0))).round().clamp(0, 255);
  return (r: c.red, g: c.green, b: c.blue, a: a);
}

List<Offset2D> _filletSoftEdgesStrokePoints(
  List<Offset2D> points,
  VsdxShape shape, {
  required bool closed,
}) {
  final radius = shape.line.roundingInches;
  if (radius <= 1e-12 || points.length < 3) return points;
  return filletPolyline(points, radius, closed: closed);
}

List<List<Offset2D>> _softEdgesDashRibbonPolygons(VsdxShape shape) {
  final inches = effectiveDashPatternForLine(shape.line);
  if (inches == null || inches.isEmpty) {
    return const <List<Offset2D>>[];
  }
  final weight =
      shape.line.weightInches > 1e-9 ? shape.line.weightInches : 0.01;
  final half = weight / 2;
  final out = <List<Offset2D>>[];
  for (final geometry in shape.geometries) {
    if (geometry.noShow || geometry.noLine) continue;
    final points = _strokedVertices(geometry, shape);
    if (points == null || points.length < 2) continue;
    final closed = polylineLooksClosed(points, noFill: geometry.noFill);
    final body = _filletSoftEdgesStrokePoints(points, shape, closed: closed);
    for (final segment in _dashPolyline(body, inches, closed: closed)) {
      if (segment.length < 2) continue;
      final left = offsetPolyline(segment, half, closed: false);
      final right = offsetPolyline(segment, -half, closed: false);
      if (left.length < 2 || right.length < 2) continue;
      out.add(<Offset2D>[...left, ...right.reversed]);
    }
  }
  return out;
}

List<List<Offset2D>> _softEdgesCompoundRibbonPolygons(VsdxShape shape) {
  if (shape.line.compoundType <= 0) {
    return const <List<Offset2D>>[];
  }
  final weight =
      shape.line.weightInches > 1e-9 ? shape.line.weightInches : 0.01;
  final rails = compoundRails(shape.line.compoundType, weight);
  if (rails.isEmpty) return const <List<Offset2D>>[];
  final dashes = effectiveDashPatternForLine(shape.line);
  final dashed = dashes != null && dashes.isNotEmpty;
  final out = <List<Offset2D>>[];
  for (final geometry in shape.geometries) {
    if (geometry.noShow || geometry.noLine) continue;
    final points = _strokedVertices(geometry, shape);
    if (points == null || points.length < 2) continue;
    final closed = polylineLooksClosed(points, noFill: geometry.noFill);
    final body = _filletSoftEdgesStrokePoints(points, shape, closed: closed);
    final polylines = dashes != null && dashes.isNotEmpty
        ? _dashPolyline(body, dashes, closed: closed)
        : <List<Offset2D>>[body];
    for (final poly in polylines) {
      if (poly.length < 2) continue;
      // Closed rails become an open loop (repeat the start) so the ribbon
      // is one `[...left, ...right.reversed]` strip `_paintFilledPolygons`
      // can fill. `closed: true` offsets would need even-odd hole pairs.
      final loop = dashed || !closed ? poly : <Offset2D>[...poly, poly.first];
      for (final rail in rails) {
        final centre = offsetPolyline(loop, rail.offset, closed: false);
        if (centre.length < 2) continue;
        final half = rail.width / 2;
        if (half <= 1e-9) continue;
        final left = offsetPolyline(centre, half, closed: false);
        final right = offsetPolyline(centre, -half, closed: false);
        if (left.length < 2 || right.length < 2) continue;
        out.add(<Offset2D>[...left, ...right.reversed]);
      }
    }
  }
  return out;
}

double _softEdgesStrokeExtentInches(VsdxShape shape) {
  final weight =
      shape.line.weightInches > 1e-9 ? shape.line.weightInches : 0.01;
  var extent = weight / 2;
  if (shape.line.compoundType <= 0) return extent;
  for (final rail in compoundRails(shape.line.compoundType, weight)) {
    extent = math.max(extent, rail.offset.abs() + rail.width / 2);
  }
  return extent;
}

List<List<Offset2D>> _softEdgesStrokeRibbonPolygons(VsdxShape shape) {
  if (shape.line.compoundType > 0) {
    return _softEdgesCompoundRibbonPolygons(shape);
  }
  return _softEdgesDashRibbonPolygons(shape);
}

({Uint8List png, double padInches})? _softEdgesStrokePngForLibvisioWrite(
  VsdxShape shape, {
  required VsdxTheme theme,
  int? holeRed,
  int? holeGreen,
  int? holeBlue,
  int? holeAlpha,
  bool holeFromFill = false,
}) {
  final ribbons = _softEdgesStrokeRibbonPolygons(shape);
  final kind = _softEdgesStrokeSilhouetteKind(shape);
  if (kind == null && ribbons.isEmpty) return null;
  final color = _lineRgbForLibvisioWrite(shape.line, theme);
  final trans = shape.line.transparency.clamp(0.0, 1.0);
  final alpha = (color.alpha * (1 - trans)).round().clamp(0, 255);
  final w = shape.width.abs();
  final h = shape.height.abs();
  var innerWidthPx = math.max(8, (w * kLibvisioSoftEdgesPxPerInch).round());
  var innerHeightPx = math.max(8, (h * kLibvisioSoftEdgesPxPerInch).round());
  const maxPx = 1024;
  final longest = math.max(innerWidthPx, innerHeightPx);
  if (longest > maxPx) {
    final scale = maxPx / longest;
    innerWidthPx = math.max(8, (innerWidthPx * scale).round());
    innerHeightPx = math.max(8, (innerHeightPx * scale).round());
  }
  final weight =
      shape.line.weightInches > 1e-9 ? shape.line.weightInches : 0.01;
  final soft = shape.line.softEdgesInches;
  final padInches = _softEdgesStrokeExtentInches(shape) + soft * 3;
  final padPx = math.max(1, (padInches / w * innerWidthPx).ceil());
  final sigmaPx = soft / w * innerWidthPx;
  final strokeWidthPx = weight / w * innerWidthPx;
  final fillColorAt = holeFromFill ? _softEdgesFillColorAt(shape, theme) : null;
  if (holeFromFill && fillColorAt == null) return null;
  final holeColorAt = fillColorAt == null
      ? null
      : (double innerX, double innerY) =>
          fillColorAt(innerX, innerY, innerWidthPx, innerHeightPx);
  final lineColorAt = _softEdgesLineColorAt(shape, theme);
  final strokeColorAt = lineColorAt == null
      ? null
      : (double innerX, double innerY) =>
          lineColorAt(innerX, innerY, innerWidthPx, innerHeightPx);
  var outer = const <({double x, double y})>[];
  var inner = const <({double x, double y})>[];
  var ribbonPx = const <List<({double x, double y})>>[];
  ({double x, double y}) toPx(Offset2D p) => (
        x: padPx + p.x / w * (innerWidthPx - 1),
        y: padPx + (1 - p.y / h) * (innerHeightPx - 1),
      );
  final needsHole = (holeAlpha != null && holeAlpha > 0) || holeColorAt != null;
  if (ribbons.isNotEmpty) {
    ribbonPx = <List<({double x, double y})>>[
      for (final ribbon in ribbons)
        if (ribbon.length >= 3)
          <({double x, double y})>[
            for (final p in ribbon) toPx(p),
          ],
    ];
    if (ribbonPx.isEmpty) return null;
    if (needsHole &&
        _softEdgesSilhouetteKind(shape) == SoftEdgesSilhouetteKind.polygon) {
      VsdxGeometry? geom;
      for (final candidate in shape.geometries) {
        if (candidate.noShow || candidate.noFill) continue;
        geom = candidate;
        break;
      }
      final inches = geom == null ? null : _softEdgesPolygonInches(shape, geom);
      if (inches != null && inches.length >= 3) {
        inner = <({double x, double y})>[for (final p in inches) toPx(p)];
      }
    }
  } else if (kind == SoftEdgesSilhouetteKind.polygon) {
    final geom = _softEdgesStrokeGeometry(shape);
    final inches = geom == null ? null : _softEdgesPolygonInches(shape, geom);
    if (inches == null || inches.length < 3) return null;
    final half = weight / 2;
    final left = offsetPolyline(inches, half, closed: true);
    final right = offsetPolyline(inches, -half, closed: true);
    if (left.length < 3 || right.length < 3) return null;
    outer = <({double x, double y})>[for (final p in left) toPx(p)];
    inner = <({double x, double y})>[for (final p in right) toPx(p)];
  }
  final png = bakeStrokedSilhouetteSoftEdgesPng(
    innerWidthPx: innerWidthPx,
    innerHeightPx: innerHeightPx,
    padPx: padPx,
    red: color.red,
    green: color.green,
    blue: color.blue,
    alpha: alpha,
    softSigmaPx: sigmaPx,
    strokeWidthPx: strokeWidthPx,
    kind: kind ?? SoftEdgesSilhouetteKind.rectangle,
    outer: outer,
    inner: inner,
    ribbons: ribbonPx,
    holeRed: holeRed,
    holeGreen: holeGreen,
    holeBlue: holeBlue,
    holeAlpha: holeAlpha,
    holeColorAt: holeColorAt,
    strokeColorAt: strokeColorAt,
  );
  if (png == null) return null;
  return (png: png, padInches: padPx / innerWidthPx * w);
}

({Uint8List png, double padInches})? _softEdgesFillStrokePngForLibvisioWrite(
  VsdxShape shape,
  VsdxTheme theme,
) {
  if (shape.fill.paintGradient != null ||
      libvisioHatchSpec(shape.fill.pattern) != null) {
    return _softEdgesStrokePngForLibvisioWrite(
      shape,
      theme: theme,
      holeFromFill: true,
    );
  }
  final fillColor = _fillRgbForLibvisioWrite(
    shape.fill,
    theme,
    fillMatrix: shape.quickStyleFillMatrix,
  );
  final fillTrans = shape.fill.foregroundTransparency.clamp(0.0, 1.0);
  final fillAlpha = (fillColor.alpha * (1 - fillTrans)).round().clamp(0, 255);
  return _softEdgesStrokePngForLibvisioWrite(
    shape,
    theme: theme,
    holeRed: fillColor.red,
    holeGreen: fillColor.green,
    holeBlue: fillColor.blue,
    holeAlpha: fillAlpha,
  );
}

({Uint8List png, double padInches})? _softEdgesBakePayload(
  VsdxShape shape,
  VsdxTheme theme,
) {
  if (_shapeNeedsLibvisioFillStrokeSoftEdgesBake(shape)) {
    return _softEdgesFillStrokePngForLibvisioWrite(shape, theme);
  }
  if (_shapeNeedsLibvisioFillSoftEdgesBake(shape)) {
    final png = _softEdgesPngForLibvisioWrite(shape, theme);
    if (png == null) return null;
    return (png: png, padInches: 0);
  }
  return _softEdgesStrokePngForLibvisioWrite(shape, theme: theme);
}

VsdxShape _sourceForLibvisioGeometrySoftEdgesWrite(VsdxShape shape) {
  var fill = shape.fill;
  var line = shape.line.copyWith(softEdgesInches: 0);
  if (_shapeNeedsLibvisioFillSoftEdgesBake(shape)) {
    fill = const VsdxFill(pattern: 0);
  }
  if (_shapeNeedsLibvisioFillStrokeSoftEdgesBake(shape) ||
      _shapeNeedsLibvisioStrokeSoftEdgesBake(shape)) {
    line = line.copyWith(pattern: 0, compoundType: 0, gradient: null);
  }
  return shape.copyWith(fill: fill, line: line);
}

VsdxShape _softEdgesPlateForLibvisioWrite(
  VsdxShape source, {
  required int id,
  required String imagePartName,
  double padInches = 0,
}) {
  final pad = padInches < 0 ? 0.0 : padInches;
  return VsdxShapeFactory.picture(
    id: id,
    pinX: source.pinX,
    pinY: source.pinY,
    width: source.width.abs() + pad * 2,
    height: source.height.abs() + pad * 2,
    imagePartName: imagePartName,
    name: '$kLibvisioSoftEdgesShapeNamePrefix${source.id}',
  ).copyWith(
    locPinXInches:
        pad > 1e-12 ? source.effectiveLocPinX + pad : source.locPinXInches,
    locPinYInches:
        pad > 1e-12 ? source.effectiveLocPinY + pad : source.locPinYInches,
    angleRad: source.angleRad,
    flipX: source.flipX,
    flipY: source.flipY,
    locked: true,
    layerMemberIds: source.layerMemberIds,
    richText: const VsdxRichText(
      runs: <VsdxTextRun>[],
      textBlock: VsdxTextBlock(hideText: true),
    ),
    text: '',
  );
}

void _collectSoftEdgesPlateIds(List<VsdxShape> shapes, Map<int, int> into) {
  for (final shape in shapes) {
    final sourceId = libvisioSoftEdgesSourceId(shape);
    if (sourceId != null) into[sourceId] = shape.id;
    _collectSoftEdgesPlateIds(shape.children, into);
  }
}

bool pageNeedsLibvisioGeometrySoftEdgesBake(VsdxPage page) {
  var hasPlate = false;
  var needs = false;
  void walk(VsdxShape shape) {
    if (isLibvisioSoftEdgesPlate(shape)) {
      hasPlate = true;
    } else if (shapeNeedsLibvisioGeometrySoftEdgesBake(shape)) {
      needs = true;
    }
    for (final child in shape.children) {
      walk(child);
    }
  }

  for (final shape in page.shapes) {
    walk(shape);
  }
  return hasPlate || needs;
}

typedef _SoftEdgesImageSink = void Function(VsdxImage image);

List<VsdxShape> _bakeGeometrySoftEdgesTree(
  List<VsdxShape> shapes, {
  required VsdxTheme theme,
  required Map<int, int> plateIds,
  required int Function() nextId,
  required String Function(int shapeId) allocatePart,
  required _SoftEdgesImageSink addImage,
}) {
  final out = <VsdxShape>[];
  var changed = false;
  for (final shape in shapes) {
    if (isLibvisioSoftEdgesPlate(shape)) {
      changed = true;
      continue;
    }
    var next = shape;
    if (shape.children.isNotEmpty) {
      final children = _bakeGeometrySoftEdgesTree(
        shape.children,
        theme: theme,
        plateIds: plateIds,
        nextId: nextId,
        allocatePart: allocatePart,
        addImage: addImage,
      );
      if (!identical(children, shape.children)) {
        next = shape.copyWith(children: children);
        changed = true;
      }
    }
    if (shapeNeedsLibvisioGeometrySoftEdgesBake(next)) {
      final payload = _softEdgesBakePayload(next, theme);
      if (payload != null) {
        final part = allocatePart(next.id);
        addImage(
          VsdxImage(
            partName: part,
            bytes: payload.png,
            mimeType: 'image/png',
          ),
        );
        final plate = _softEdgesPlateForLibvisioWrite(
          next,
          id: plateIds[next.id] ?? nextId(),
          imagePartName: part,
          padInches: payload.padInches,
        );
        out.add(plate);
        out.add(_sourceForLibvisioGeometrySoftEdgesWrite(next));
        changed = true;
        continue;
      }
    } else {
      final existingId = plateIds[next.id];
      if (existingId != null) {
        VsdxShape? kept;
        for (final candidate in shapes) {
          if (candidate.id == existingId) {
            kept = candidate;
            break;
          }
        }
        if (kept != null) {
          out.add(kept);
          changed = true;
        }
      }
    }
    out.add(next);
    if (!identical(next, shape)) changed = true;
  }
  return changed ? out : shapes;
}

/// Insert (or keep) the feathered PNG siblings Draw uses for geometry SoftEdges.
VsdxDocument bakeGeometrySoftEdgesForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  var registry = document.images;
  final used = <String>{
    for (final image in document.images.all) image.partName,
  };
  String allocatePart(int shapeId) {
    var name = '/visio/media/image_lo_soft_$shapeId.png';
    var n = 0;
    while (used.contains(name) || registry.findByPart(name) != null) {
      n++;
      name = '/visio/media/image_lo_soft_${shapeId}_$n.png';
    }
    used.add(name);
    return name;
  }

  final pages = <VsdxPage>[];
  var changed = false;
  for (final page in document.pages) {
    if (!pageNeedsLibvisioGeometrySoftEdgesBake(page)) {
      pages.add(page);
      continue;
    }
    final plateIds = <int, int>{};
    _collectSoftEdgesPlateIds(page.shapes, plateIds);
    var nextId = _maxShapeId(page.shapes) + 1;
    final shapes = _bakeGeometrySoftEdgesTree(
      page.shapes,
      theme: document.theme,
      plateIds: plateIds,
      nextId: () => nextId++,
      allocatePart: allocatePart,
      addImage: (image) {
        registry = registry.withImage(image);
        changed = true;
      },
    );
    if (identical(shapes, page.shapes)) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      changed = true;
    }
  }
  if (!changed) return document;
  return document.copyWith(pages: pages, images: registry);
}

/// Canvas fallback when ShadowForegnd is unset (`_drawShadow`).
const _kLibvisioShadowFallback = VsdxColor(0x99000000);

/// `true` when ShadowBlur must become a Gaussian PNG sibling for Draw.
///
/// LibreOffice only calls `VisioDocument::parse`. `tokens.txt` has
/// ShdwPattern / ShdwOffset* / ShdwForegnd but no ShadowBlur, so Draw
/// paints a hard `draw:shadow`. A filled 2-D vector bakes the same
/// Gaussian silhouette canvas and SVG already paint into a locked
/// Foreign sibling, then ShdwPattern and ShadowBlur go to 0 so Draw
/// does not add a second copy. Theme-only colour resolves through the
/// document theme then Office into that PNG — Draw never sees
/// THEMEVAL() on ShadowBlur. A Foreign picture with blur bakes the
/// same filled image-frame silhouette canvas `_drawShadow` uses. 1-D,
/// groups, and unrecognised geometry stay native.
bool shapeNeedsLibvisioShadowBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  if (shape.is1D) return false;
  if (shape.children.isNotEmpty) return false;
  if (!shape.shadow.enabled) return false;
  if (shape.shadow.blurInches <= 1e-6) return false;
  if (shape.width.abs() <= 1e-9 || shape.height.abs() <= 1e-9) return false;
  if (shape.hasImage) return _foreignFrameSilhouetteKind(shape) != null;
  if (!_shapePaintsFill(shape, shape.geometries)) return false;
  return _softEdgesSilhouetteKind(shape) != null;
}

/// RGB canvas `_colourOrTheme` would paint. Theme-only ShdwForegnd still
/// has to freeze into a ShadowBlur PNG because `ShadowBlur` is not a token.
VsdxColor _shadowRgbForLibvisioWrite(VsdxShadow shadow, VsdxTheme theme) {
  if (shadow.color != null) return shadow.color!;
  final slot = shadow.themeColorIndex;
  if (slot == null) return _kLibvisioShadowFallback;
  return theme.resolve(slot) ??
      VsdxTheme.office.resolve(slot) ??
      _kLibvisioShadowFallback;
}

({Uint8List png, double padInches})? _shadowPngForLibvisioWrite(
  VsdxShape shape,
  VsdxTheme theme,
) {
  final kind =
      _softEdgesSilhouetteKind(shape) ?? _foreignFrameSilhouetteKind(shape);
  if (kind == null) return null;
  final color = _shadowRgbForLibvisioWrite(shape.shadow, theme);
  final trans = shape.shadow.transparency.clamp(0.0, 1.0);
  final fillTrans = shape.fill.foregroundTransparency.clamp(0.0, 1.0);
  final alpha =
      (color.alpha * (1 - trans) * (1 - fillTrans)).round().clamp(0, 255);
  final w = shape.width.abs();
  final h = shape.height.abs();
  var innerWidthPx = math.max(8, (w * kLibvisioSoftEdgesPxPerInch).round());
  var innerHeightPx = math.max(8, (h * kLibvisioSoftEdgesPxPerInch).round());
  const maxPx = 1024;
  final longest = math.max(innerWidthPx, innerHeightPx);
  if (longest > maxPx) {
    final scale = maxPx / longest;
    innerWidthPx = math.max(8, (innerWidthPx * scale).round());
    innerHeightPx = math.max(8, (innerHeightPx * scale).round());
  }
  final sigmaPx = shape.shadow.blurInches / w * innerWidthPx;
  final padPx = math.max(1, (sigmaPx * 1.5).round()) * 2;
  final polygon = <({double x, double y})>[];
  if (kind == SoftEdgesSilhouetteKind.polygon) {
    VsdxGeometry? geom;
    for (final candidate in shape.geometries) {
      if (candidate.noShow || candidate.noFill) continue;
      geom = candidate;
      break;
    }
    final inches = geom == null ? null : _softEdgesPolygonInches(shape, geom);
    if (inches == null) return null;
    for (final p in inches) {
      polygon.add((
        x: p.x / w * (innerWidthPx - 1),
        y: (1 - p.y / h) * (innerHeightPx - 1),
      ));
    }
  }
  final png = bakeSilhouetteDropShadowPng(
    innerWidthPx: innerWidthPx,
    innerHeightPx: innerHeightPx,
    padPx: padPx,
    red: color.red,
    green: color.green,
    blue: color.blue,
    alpha: alpha,
    blurSigmaPx: sigmaPx,
    kind: kind,
    polygon: polygon,
  );
  if (png == null) return null;
  return (png: png, padInches: padPx / innerWidthPx * w);
}

/// Gaussian PNG of the scaled, sheared silhouette an oblique page needs.
///
/// The plain path rasterizes the shape's own box, which cannot hold a sheared
/// silhouette. Here the inner box is the transformed ring's bounding box, so
/// the plate has to carry that box back to the source's local frame. Pictures
/// use the same NoFill frame ring canvas `_drawShadow` shears.
({
  Uint8List png,
  double minX,
  double minY,
  double width,
  double height,
  double padInches,
})? _shearedShadowPngForLibvisioWrite(
  VsdxShape shape,
  VsdxPage page,
  VsdxTheme theme,
) {
  final rings = _pageShadowRingsForLibvisioWrite(shape, page);
  if (rings.isEmpty) return null;
  final ring = rings.first;
  if (ring.length < 3) return null;
  var minX = ring.first.x;
  var maxX = minX;
  var minY = ring.first.y;
  var maxY = minY;
  for (final p in ring) {
    if (p.x < minX) minX = p.x;
    if (p.x > maxX) maxX = p.x;
    if (p.y < minY) minY = p.y;
    if (p.y > maxY) maxY = p.y;
  }
  final w = maxX - minX;
  final h = maxY - minY;
  if (w <= 1e-9 || h <= 1e-9) return null;
  final color = _shadowRgbForLibvisioWrite(shape.shadow, theme);
  final trans = shape.shadow.transparency.clamp(0.0, 1.0);
  final fillTrans = shape.fill.foregroundTransparency.clamp(0.0, 1.0);
  final alpha =
      (color.alpha * (1 - trans) * (1 - fillTrans)).round().clamp(0, 255);
  var innerWidthPx = math.max(8, (w * kLibvisioSoftEdgesPxPerInch).round());
  var innerHeightPx = math.max(8, (h * kLibvisioSoftEdgesPxPerInch).round());
  const maxPx = 1024;
  final longest = math.max(innerWidthPx, innerHeightPx);
  if (longest > maxPx) {
    final scale = maxPx / longest;
    innerWidthPx = math.max(8, (innerWidthPx * scale).round());
    innerHeightPx = math.max(8, (innerHeightPx * scale).round());
  }
  final sigmaPx = shape.shadow.blurInches / w * innerWidthPx;
  final padPx = math.max(1, (sigmaPx * 1.5).round()) * 2;
  final polygon = <({double x, double y})>[
    for (final p in ring)
      (
        x: (p.x - minX) / w * (innerWidthPx - 1),
        y: (1 - (p.y - minY) / h) * (innerHeightPx - 1),
      ),
  ];
  final png = bakeSilhouetteDropShadowPng(
    innerWidthPx: innerWidthPx,
    innerHeightPx: innerHeightPx,
    padPx: padPx,
    red: color.red,
    green: color.green,
    blue: color.blue,
    alpha: alpha,
    blurSigmaPx: sigmaPx,
    kind: SoftEdgesSilhouetteKind.polygon,
    polygon: polygon,
  );
  if (png == null) return null;
  return (
    png: png,
    minX: minX,
    minY: minY,
    width: w,
    height: h,
    padInches: padPx / innerWidthPx * w,
  );
}

/// Plate for a shadow PNG whose inner box is not the shape's own box.
VsdxShape _shadowBoxPlateForLibvisioWrite(
  VsdxShape source, {
  required int id,
  required String imagePartName,
  required double minX,
  required double minY,
  required double boxWidth,
  required double boxHeight,
  required double padInches,
  required double offsetXInches,
  required double offsetYInches,
}) {
  final pad = padInches < 0 ? 0.0 : padInches;
  return VsdxShapeFactory.picture(
    id: id,
    pinX: source.pinX + offsetXInches,
    pinY: source.pinY + offsetYInches,
    width: boxWidth + pad * 2,
    height: boxHeight + pad * 2,
    imagePartName: imagePartName,
    name: '$kLibvisioShadowShapeNamePrefix${source.id}',
  ).copyWith(
    locPinXInches: source.effectiveLocPinX - (minX - pad),
    locPinYInches: source.effectiveLocPinY - (minY - pad),
    angleRad: source.angleRad,
    flipX: source.flipX,
    flipY: source.flipY,
    locked: true,
    layerMemberIds: source.layerMemberIds,
    richText: const VsdxRichText(
      runs: <VsdxTextRun>[],
      textBlock: VsdxTextBlock(hideText: true),
    ),
    text: '',
  );
}

VsdxShape _sourceForLibvisioShadowWrite(VsdxShape shape) {
  return shape.copyWith(
    shadow: shape.shadow.copyWith(enabled: false, blurInches: 0),
  );
}

VsdxShape _shadowPlateForLibvisioWrite(
  VsdxShape source, {
  required int id,
  required String imagePartName,
  required double padInches,
  required double offsetXInches,
  required double offsetYInches,
}) {
  return VsdxShapeFactory.picture(
    id: id,
    pinX: source.pinX + offsetXInches,
    pinY: source.pinY + offsetYInches,
    width: source.width.abs() + padInches * 2,
    height: source.height.abs() + padInches * 2,
    imagePartName: imagePartName,
    name: '$kLibvisioShadowShapeNamePrefix${source.id}',
  ).copyWith(
    locPinXInches: source.effectiveLocPinX + padInches,
    locPinYInches: source.effectiveLocPinY + padInches,
    angleRad: source.angleRad,
    flipX: source.flipX,
    flipY: source.flipY,
    locked: true,
    layerMemberIds: source.layerMemberIds,
    richText: const VsdxRichText(
      runs: <VsdxTextRun>[],
      textBlock: VsdxTextBlock(hideText: true),
    ),
    text: '',
  );
}

void _collectShadowPlateIds(List<VsdxShape> shapes, Map<int, int> into) {
  for (final shape in shapes) {
    final sourceId = libvisioShadowSourceId(shape);
    if (sourceId != null) into[sourceId] = shape.id;
    _collectShadowPlateIds(shape.children, into);
  }
}

bool pageNeedsLibvisioShadowBake(VsdxPage page) {
  var hasPlate = false;
  var needs = false;
  void walk(VsdxShape shape) {
    if (isLibvisioShadowPlate(shape)) {
      hasPlate = true;
    } else if (shapeNeedsLibvisioShadowBake(shape)) {
      needs = true;
    }
    for (final child in shape.children) {
      walk(child);
    }
  }

  for (final shape in page.shapes) {
    walk(shape);
  }
  return hasPlate || needs;
}

typedef _ShadowImageSink = void Function(VsdxImage image);

List<VsdxShape> _bakeShadowTree(
  List<VsdxShape> shapes, {
  required VsdxPage page,
  required VsdxTheme theme,
  required Map<int, int> plateIds,
  required int Function() nextId,
  required String Function(int shapeId) allocatePart,
  required _ShadowImageSink addImage,
}) {
  final out = <VsdxShape>[];
  var changed = false;
  for (final shape in shapes) {
    if (isLibvisioShadowPlate(shape)) {
      changed = true;
      continue;
    }
    var next = shape;
    if (shape.children.isNotEmpty) {
      final children = _bakeShadowTree(
        shape.children,
        page: page,
        theme: theme,
        plateIds: plateIds,
        nextId: nextId,
        allocatePart: allocatePart,
        addImage: addImage,
      );
      if (!identical(children, shape.children)) {
        next = shape.copyWith(children: children);
        changed = true;
      }
    }
    if (shapeNeedsLibvisioShadowBake(next)) {
      final dx = libvisioEffectiveShadowOffset(
        next.shadow.offsetXInches,
        page.pageSheet.shadowOffsetXInches,
      );
      final dy = libvisioEffectiveShadowOffset(
        next.shadow.offsetYInches,
        page.pageSheet.shadowOffsetYInches,
      );
      // An oblique page also skews the blur, and the sheared silhouette no
      // longer fits the shape's own box.
      final sheared = pageSheetShearsLibvisioShadows(page.pageSheet)
          ? _shearedShadowPngForLibvisioWrite(next, page, theme)
          : null;
      if (sheared != null) {
        final part = allocatePart(next.id);
        addImage(
          VsdxImage(
            partName: part,
            bytes: sheared.png,
            mimeType: 'image/png',
          ),
        );
        out.add(
          _shadowBoxPlateForLibvisioWrite(
            next,
            id: plateIds[next.id] ?? nextId(),
            imagePartName: part,
            minX: sheared.minX,
            minY: sheared.minY,
            boxWidth: sheared.width,
            boxHeight: sheared.height,
            padInches: sheared.padInches,
            offsetXInches: dx,
            offsetYInches: dy,
          ),
        );
        out.add(_sourceForLibvisioShadowWrite(next));
        changed = true;
        continue;
      }
      final raster = _shadowPngForLibvisioWrite(next, theme);
      if (raster != null) {
        final part = allocatePart(next.id);
        addImage(
          VsdxImage(
            partName: part,
            bytes: raster.png,
            mimeType: 'image/png',
          ),
        );
        final plate = _shadowPlateForLibvisioWrite(
          next,
          id: plateIds[next.id] ?? nextId(),
          imagePartName: part,
          padInches: raster.padInches,
          offsetXInches: dx,
          offsetYInches: dy,
        );
        out.add(plate);
        out.add(_sourceForLibvisioShadowWrite(next));
        changed = true;
        continue;
      }
    } else {
      final existingId = plateIds[next.id];
      if (existingId != null) {
        VsdxShape? kept;
        for (final candidate in shapes) {
          if (candidate.id == existingId) {
            kept = candidate;
            break;
          }
        }
        if (kept != null) {
          out.add(kept);
          changed = true;
        }
      }
    }
    out.add(next);
    if (!identical(next, shape)) changed = true;
  }
  return changed ? out : shapes;
}

/// Insert (or keep) the Gaussian PNG siblings Draw uses for ShadowBlur.
VsdxDocument bakeShadowForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  var registry = document.images;
  final used = <String>{
    for (final image in document.images.all) image.partName,
  };
  String allocatePart(int shapeId) {
    var name = '/visio/media/image_lo_shdw_$shapeId.png';
    var n = 0;
    while (used.contains(name) || registry.findByPart(name) != null) {
      n++;
      name = '/visio/media/image_lo_shdw_${shapeId}_$n.png';
    }
    used.add(name);
    return name;
  }

  final pages = <VsdxPage>[];
  var changed = false;
  for (final page in document.pages) {
    if (!pageNeedsLibvisioShadowBake(page)) {
      pages.add(page);
      continue;
    }
    final plateIds = <int, int>{};
    _collectShadowPlateIds(page.shapes, plateIds);
    var nextId = _maxShapeId(page.shapes) + 1;
    final shapes = _bakeShadowTree(
      page.shapes,
      page: page,
      theme: document.theme,
      plateIds: plateIds,
      nextId: () => nextId++,
      allocatePart: allocatePart,
      addImage: (image) {
        registry = registry.withImage(image);
        changed = true;
      },
    );
    if (identical(shapes, page.shapes)) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      changed = true;
    }
  }
  if (!changed) return document;
  return document.copyWith(pages: pages, images: registry);
}

/// Name prefix of the sheared sibling a page oblique shadow becomes for Draw.
const kLibvisioPageShadowShapeNamePrefix = 'LibvisioPageShadow.';

bool isLibvisioPageShadowPlate(VsdxShape shape) =>
    shape.name.startsWith(kLibvisioPageShadowShapeNamePrefix);

int? libvisioPageShadowSourceId(VsdxShape plate) {
  if (!isLibvisioPageShadowPlate(plate)) return null;
  return int.tryParse(
    plate.name.substring(kLibvisioPageShadowShapeNamePrefix.length),
  );
}

/// `true` when the PageSheet skews or scales drop shadows.
///
/// `readPageSheetProperties` only collects `ShdwOffsetX` / `ShdwOffsetY`;
/// `ShdwType`, `ShdwObliqueAngle` and `ShdwScaleFactor` are not even in
/// `tokens.txt`, so Draw always paints a plain offset copy.
bool pageSheetShearsLibvisioShadows(VsdxPageSheet sheet) =>
    sheet.shadowType != 0 ||
    sheet.shadowObliqueAngle.abs() > 1e-9 ||
    (sheet.shadowScaleFactor - 1.0).abs() > 1e-9;

/// `true` when a page oblique shadow must become a sheared sibling for Draw.
///
/// Canvas `_applyPageShadowXform` scales and shears the silhouette about the
/// shape LocPin before offsetting it. Blurred shadows already bake a Gaussian
/// PNG, so this covers the hard-edged ones Draw would otherwise draw
/// unsheared. Theme-only colour resolves through the document theme then
/// Office into the plate FillForegnd — Draw never sees THEMEVAL() on
/// `ShdwType`. 1-D and groups stay native.
bool shapeNeedsLibvisioPageShadowBake(VsdxShape shape, VsdxPage page) {
  if (!pageSheetShearsLibvisioShadows(page.pageSheet)) return false;
  if (_isLibvisioBakePlate(shape)) return false;
  if (shape.is1D) return false;
  if (shape.children.isNotEmpty) return false;
  if (!shape.shadow.enabled) return false;
  // Blur takes the Gaussian PNG path instead.
  if (shape.shadow.blurInches > 1e-6) return false;
  if (shape.width.abs() <= 1e-9 || shape.height.abs() <= 1e-9) return false;
  if (!_shapePaintsFill(shape, shape.geometries) && !shape.hasImage) {
    return false;
  }
  return _pageShadowGeometriesForLibvisioWrite(shape, page).isNotEmpty;
}

/// The shape silhouette scaled and sheared about LocPin, matching canvas.
///
/// The page-space shadow offset rides on the plate pin (like the Gaussian PNG
/// plate) so a rotated shape does not rotate its offset.
List<List<Offset2D>> _pageShadowRingsForLibvisioWrite(
  VsdxShape shape,
  VsdxPage page,
) {
  final sheet = page.pageSheet;
  final scale = sheet.shadowScaleFactor;
  final shear = math.tan(sheet.shadowObliqueAngle);
  final cx = shape.effectiveLocPinX;
  final cy = shape.effectiveLocPinY;
  Offset2D map(Offset2D p) {
    final qy = (p.y - cy) * scale;
    final qx = (p.x - cx) * scale + shear * qy;
    return Offset2D(qx + cx, qy + cy);
  }

  final out = <List<Offset2D>>[];
  for (final geometry in shape.geometries) {
    if (geometry.noShow) continue;
    // A Foreign frame is NoFill but still supplies the image silhouette.
    if (geometry.noFill && !shape.hasImage) continue;
    final points = _strokedVertices(geometry, shape);
    if (points == null || points.length < 3) continue;
    out.add(<Offset2D>[for (final p in points) map(p)]);
  }
  return out;
}

List<VsdxGeometry> _pageShadowGeometriesForLibvisioWrite(
  VsdxShape shape,
  VsdxPage page,
) {
  final out = <VsdxGeometry>[];
  for (final ring in _pageShadowRingsForLibvisioWrite(shape, page)) {
    final commands = _closedCommandsForRing(ring);
    if (commands.length < 3) continue;
    out.add(VsdxGeometry(noFill: false, noLine: true, commands: commands));
  }
  return out;
}

VsdxShape _pageShadowPlateForLibvisioWrite(
  VsdxShape source,
  VsdxPage page, {
  required int id,
  required VsdxTheme theme,
}) {
  final sheet = page.pageSheet;
  final dx = libvisioEffectiveShadowOffset(
    source.shadow.offsetXInches,
    sheet.shadowOffsetXInches,
  );
  final dy = libvisioEffectiveShadowOffset(
    source.shadow.offsetYInches,
    sheet.shadowOffsetYInches,
  );
  final colour = _shadowRgbForLibvisioWrite(source.shadow, theme);
  // Canvas opacity is colourAlpha × (1 - ShdwForegndTrans) × (1 - FillTrans);
  // FillForegndTrans is a token, so carry all three there.
  final opacity = colour.alpha /
      255 *
      (1 - source.shadow.transparency.clamp(0.0, 1.0)) *
      (1 - source.fill.foregroundTransparency.clamp(0.0, 1.0));
  return VsdxShape(
    id: id,
    name: '$kLibvisioPageShadowShapeNamePrefix${source.id}',
    pinX: source.pinX + dx,
    pinY: source.pinY + dy,
    width: source.width,
    height: source.height,
    locPinXInches: source.locPinXInches,
    locPinYInches: source.locPinYInches,
    angleRad: source.angleRad,
    flipX: source.flipX,
    flipY: source.flipY,
    geometries: _pageShadowGeometriesForLibvisioWrite(source, page),
    fill: VsdxFill(
      foreground: VsdxColor.argb(255, colour.red, colour.green, colour.blue),
      pattern: 1,
      foregroundTransparency: (1 - opacity).clamp(0.0, 1.0),
    ),
    line: const VsdxLine(pattern: 0),
    layerMemberIds: source.layerMemberIds,
    locked: true,
    richText: const VsdxRichText(
      runs: <VsdxTextRun>[],
      textBlock: VsdxTextBlock(hideText: true),
    ),
    text: '',
  );
}

/// `ShdwPattern` 0 so Draw does not add its own unsheared copy.
VsdxShape _sourceForLibvisioPageShadowWrite(VsdxShape shape) =>
    shape.copyWith(shadow: shape.shadow.copyWith(enabled: false));

void _collectPageShadowPlateIds(List<VsdxShape> shapes, Map<int, int> into) {
  for (final shape in shapes) {
    final sourceId = libvisioPageShadowSourceId(shape);
    if (sourceId != null) into[sourceId] = shape.id;
    _collectPageShadowPlateIds(shape.children, into);
  }
}

bool pageNeedsLibvisioPageShadowBake(VsdxPage page) {
  var hasPlate = false;
  var needs = false;
  void walk(VsdxShape shape) {
    if (isLibvisioPageShadowPlate(shape)) {
      hasPlate = true;
    } else if (shapeNeedsLibvisioPageShadowBake(shape, page)) {
      needs = true;
    }
    for (final child in shape.children) {
      walk(child);
    }
  }

  for (final shape in page.shapes) {
    walk(shape);
  }
  return hasPlate || needs;
}

List<VsdxShape> _bakePageShadowTree(
  List<VsdxShape> shapes, {
  required VsdxPage page,
  required VsdxTheme theme,
  required Map<int, int> plateIds,
  required int Function() nextId,
}) {
  final out = <VsdxShape>[];
  var changed = false;
  for (final shape in shapes) {
    if (isLibvisioPageShadowPlate(shape)) {
      changed = true;
      continue;
    }
    var next = shape;
    if (shape.children.isNotEmpty) {
      final children = _bakePageShadowTree(
        shape.children,
        page: page,
        theme: theme,
        plateIds: plateIds,
        nextId: nextId,
      );
      if (!identical(children, shape.children)) {
        next = shape.copyWith(children: children);
        changed = true;
      }
    }
    if (shapeNeedsLibvisioPageShadowBake(next, page)) {
      final plate = _pageShadowPlateForLibvisioWrite(
        next,
        page,
        id: plateIds[next.id] ?? nextId(),
        theme: theme,
      );
      if (plate.geometries.isNotEmpty) {
        out.add(plate);
        out.add(_sourceForLibvisioPageShadowWrite(next));
        changed = true;
        continue;
      }
    } else {
      final existingId = plateIds[next.id];
      if (existingId != null) {
        VsdxShape? kept;
        for (final candidate in shapes) {
          if (candidate.id == existingId) {
            kept = candidate;
            break;
          }
        }
        if (kept != null) {
          out.add(kept);
          changed = true;
        }
      }
    }
    out.add(next);
    if (!identical(next, shape)) changed = true;
  }
  return changed ? out : shapes;
}

/// Insert (or keep) the sheared siblings Draw uses for a page oblique shadow.
VsdxDocument bakePageShadowForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var changed = false;
  for (final page in document.pages) {
    if (!pageNeedsLibvisioPageShadowBake(page)) {
      pages.add(page);
      continue;
    }
    final plateIds = <int, int>{};
    _collectPageShadowPlateIds(page.shapes, plateIds);
    var nextId = _maxShapeId(page.shapes) + 1;
    final shapes = _bakePageShadowTree(
      page.shapes,
      page: page,
      theme: document.theme,
      plateIds: plateIds,
      nextId: () => nextId++,
    );
    if (identical(shapes, page.shapes)) {
      pages.add(page);
    } else {
      pages.add(page.copyWith(shapes: shapes));
      changed = true;
    }
  }
  return changed ? document.copyWith(pages: pages) : document;
}

/// Cells and Geometry the writer should emit so Draw paints this shape.
class LibvisioShapeWrite {
  const LibvisioShapeWrite({
    required this.geometries,
    required this.line,
    required this.fill,
    required this.geometryRewritten,
  });

  final List<VsdxGeometry> geometries;
  final VsdxLine line;
  final VsdxFill fill;
  final bool geometryRewritten;
}

/// Map [shape] onto the Fill / Line / Geometry libvisio will actually draw.
LibvisioShapeWrite libvisioShapeWrite(
  VsdxShape shape, {
  VsdxTheme theme = VsdxTheme.empty,
}) {
  if (shape.libvisioCollapsedHidden || shape.libvisioCoveredHidden) {
    return LibvisioShapeWrite(
      geometries: <VsdxGeometry>[
        for (final geometry in shape.geometries)
          geometry.noShow ? geometry : geometry.copyWith(noShow: true),
      ],
      line: shape.line.copyWith(pattern: 0),
      fill: shape.fill.copyWith(pattern: 0, gradient: null),
      geometryRewritten: true,
    );
  }
  var geometries = shape.geometries;
  var line = shape.line;
  var fill = fillForLibvisioWrite(shape.fill);
  var geometryRewritten = false;

  var working = shape;
  List<VsdxGeometry> arrowGeoms = const <VsdxGeometry>[];
  if (shapeNeedsLibvisioArrowedStrokeBake(shape)) {
    arrowGeoms = bakeArrowGeometriesForLibvisio(shape);
    working = shape.copyWith(
      line: shape.line.copyWith(beginArrow: 0, endArrow: 0),
    );
    geometries = working.geometries;
    line = working.line;
    if (arrowGeoms.isNotEmpty) geometryRewritten = true;
  }

  final baked = bakeCompoundTypeForLibvisio(working);
  if (baked != null) {
    geometries = baked.geometries;
    line = baked.line;
    if (baked.fill != null) fill = baked.fill!;
    geometryRewritten = true;
    working = working.copyWith(
      geometries: geometries,
      line: line,
      fill: fill,
    );
  }

  final dashed = bakeCustomDashForLibvisio(
    working,
    geometries: geometries,
    line: line,
  );
  if (dashed != null) {
    geometries = dashed.geometries;
    line = dashed.line;
    geometryRewritten = true;
    working = working.copyWith(
      geometries: geometries,
      line: line,
    );
  }

  final flowed = bakeFlowDashForLibvisio(
    working,
    geometries: geometries,
    line: line,
  );
  if (flowed != null) {
    geometries = flowed.geometries;
    line = flowed.line;
    geometryRewritten = true;
    working = working.copyWith(
      geometries: geometries,
      line: line,
    );
  }

  final patterned = bakeLinePatternDashForLibvisio(
    working,
    geometries: geometries,
    line: line,
  );
  if (patterned != null) {
    geometries = patterned.geometries;
    line = patterned.line;
    geometryRewritten = true;
    working = working.copyWith(
      geometries: geometries,
      line: line,
    );
  }

  final pattern = linePatternForLibvisioWrite(line);
  if (pattern != line.pattern) {
    line = line.copyWith(pattern: pattern);
  }

  final color = lineColorForLibvisioWrite(line);
  if (color != null && line.color == null && line.themeColorIndex == null) {
    line = line.copyWith(color: color);
  }

  final ribbon = bakeStrokeRibbonForLibvisio(
    shape: working,
    geometries: geometries,
    line: line,
    theme: theme,
  );
  if (ribbon != null) {
    geometries = ribbon.geometries;
    line = ribbon.line;
    fill = ribbon.fill;
    geometryRewritten = true;
  }

  if (arrowGeoms.isNotEmpty) {
    geometries = <VsdxGeometry>[...geometries, ...arrowGeoms];
    if (!fill.hasFill) {
      fill = VsdxFill(
        foreground: _lineRgbForLibvisioWrite(line, theme),
        pattern: 1,
        foregroundTransparency: line.transparency.clamp(0.0, 1.0),
      );
    }
    line = line.copyWith(beginArrow: 0, endArrow: 0);
  }

  final sourceLine = shape.line;
  if (roundingForLibvisioWrite(sourceLine) > 1e-12) {
    line = line.copyWith(roundingInches: 0);
  }
  if ((chamferForLibvisioWrite(sourceLine) ||
          shapeNeedsLibvisioRoundCapMiterFlatten(shape)) &&
      sourceLine.cap == LineCap.round) {
    line = line.copyWith(cap: LineCap.extended);
  }
  if (miterLimitForLibvisioChamfer(sourceLine) != null ||
      shapeNeedsLibvisioMiterSpikeBake(shape)) {
    line = line.copyWith(miterLimit: 4.0);
  }
  if (line.transparency > 1e-9 &&
      !shapeNeedsLibvisioFilledStrokeRibbonBake(shape)) {
    line = line.copyWith(
      color: colourForLibvisioAlpha(
        _lineRgbForLibvisioWrite(line, theme),
        line.transparency,
      ),
      transparency: 0,
      clearThemeColorIndex: true,
    );
  }

  final glow = bakeGlowForLibvisio(
    shape: shape,
    geometries: geometries,
    line: line,
    fill: fill,
    theme: theme,
  );
  if (glow != null) {
    geometries = glow.geometries;
    line = glow.line;
    fill = glow.fill;
    geometryRewritten = true;
  }

  fill = _fillWithoutStaleLibvisioPattern(fill, geometries);
  fill = fillThemeTransForLibvisioWrite(fill, theme);

  return LibvisioShapeWrite(
    geometries: geometries,
    line: line,
    fill: fill,
    geometryRewritten: geometryRewritten,
  );
}

List<Offset2D>? _strokedVertices(VsdxGeometry geometry, VsdxShape shape) {
  return geometry.polylineVertices(
        widthInches: shape.width,
        heightInches: shape.height,
      ) ??
      ShapePerimeter.sampledGeometryVertices(
        geometry,
        width: shape.width,
        height: shape.height,
      );
}

bool _shapePaintsFill(VsdxShape shape, List<VsdxGeometry> geometries) {
  if (!shape.fill.hasFill) return false;
  for (final geometry in geometries) {
    if (!geometry.noShow && !geometry.noFill) return true;
  }
  return false;
}

bool _geometriesPaintFill(VsdxFill fill, List<VsdxGeometry> geometries) {
  if (!fill.hasFill) return false;
  for (final geometry in geometries) {
    if (!geometry.noShow && !geometry.noFill) return true;
  }
  return false;
}

/// Drop a leftover FillPattern when libvisio will never collect a path.
///
/// Edraw text labels (「专业知识」, 「70% 隐性」, …) store FillPattern=1 and
/// FillForegnd but omit Geometry. Visio / libvisio then paint text only.
/// A save that keeps FillPattern=1 lets Edraw fill the Width×Height box —
/// a white plate that hides white glyphs on the header wash.
VsdxFill _fillWithoutStaleLibvisioPattern(
  VsdxFill fill,
  List<VsdxGeometry> geometries,
) {
  if (fill.pattern == 0 || fill.hasGradient) return fill;
  if (_geometriesPaintFill(fill, geometries)) return fill;
  return fill.copyWith(pattern: 0);
}

bool _geometriesPaintLine(VsdxLine line, List<VsdxGeometry> geometries) {
  if (!line.hasLine) return false;
  for (final geometry in geometries) {
    if (!geometry.noShow && !geometry.noLine) return true;
  }
  return false;
}

/// Canvas `_drawGlow` uses `(1 - trans) * 0.6` fill-opacity; invert for Trans.
double _glowHaloTransparency(VsdxGlow glow) =>
    0.4 + 0.6 * glow.transparency.clamp(0.0, 1.0);

const _kLibvisioGlowFallback = VsdxColor(0xFFFFC107);

/// Glow ribbon fill Draw collects. `FillForegndTrans` *is* a token, so only
/// the RGB has to freeze: `QuickStyleFillColor` would go through the same
/// `getThemeColour` table that stops at 8, so a THEMEVAL() ribbon lost the
/// slot canvas `_drawGlow` paints.
VsdxFill _glowFillForLibvisio(
  VsdxGlow glow, [
  VsdxTheme theme = VsdxTheme.empty,
]) {
  return VsdxFill(
    foreground: _glowRgbForLibvisioWrite(glow, theme),
    pattern: 1,
    foregroundTransparency: _glowHaloTransparency(glow),
  );
}

/// LineWeight halo Draw collects when Glow cannot become a Gaussian PNG.
///
/// Theme-only colour has to freeze into RGB here. `Glow*` is not a token,
/// so the slot would have to survive as `QuickStyleLineColor`, but
/// `VSDXTheme::getThemeColour` maps 0–8 onto dk1/lt1/accent1–6/bkgnd and
/// returns nothing above that, and `VSDLineStyle::override` applies the
/// explicit `LineColor` *after* the theme. A THEMEVAL() halo therefore
/// painted opaque black instead of the faded slot canvas `_drawGlow`
/// blends. LineColorTrans is not a token either, so the halo alpha is
/// premultiplied toward white the same way the resolved-RGB path does.
VsdxLine _glowLineForLibvisio(
  VsdxLine line,
  VsdxGlow glow, [
  VsdxTheme theme = VsdxTheme.empty,
]) {
  final weight = math.max(glow.sizeInches * 2, 0.02);
  return line.copyWith(
    color: colourForLibvisioAlpha(
      _glowRgbForLibvisioWrite(glow, theme),
      _glowHaloTransparency(glow),
    ),
    weightInches: weight,
    pattern: 1,
    transparency: 0,
    cap: LineCap.round,
    clearThemeColorIndex: true,
  );
}

/// `true` when Glow* must become Line / Fill Draw actually collects.
///
/// `tokens.txt` has no GlowSize. Filled 2-D that already paints a stroke
/// keeps that outline — Line is shape-level, so a halo would replace
/// CompoundType / dashes; that case bakes a Gaussian PNG sibling.
/// Unfilled 1-D strokes bake a Gaussian PNG plate. Unfilled 2-D bakes a
/// Gaussian PNG ring. Filled NoLine bakes the same Gaussian PNG sibling.
/// Pictures bake a Gaussian PNG ring around the image frame. Theme-only
/// colour resolves into those PNGs (document theme, then Office) so Draw
/// keeps the blur canvas `_colourOrTheme` already paints. Remaining
/// theme-only NoLine that cannot PNG still becomes a LineWeight halo
/// (`xmlStringToColour` zeros LineColorTrans, so RGB is premultiplied
/// toward white).
bool shapeNeedsLibvisioGlowBake(VsdxShape shape) {
  if (_shapeCanLibvisioGlowPng(shape)) return false;
  if (_shapeCanLibvisioGlowStrokePng(shape)) return false;
  if (_shapeCanLibvisioGlowPicturePng(shape)) return false;
  final glow = shape.glow;
  if (!glow.enabled || glow.sizeInches <= 1e-12) return false;
  if (glow.transparency >= 1 - 1e-9) return false;
  final paintsFill = _shapePaintsFill(shape, shape.geometries);
  if (!paintsFill && !shape.line.hasLine && !shape.hasImage) return false;
  if (!paintsFill && shapeNeedsLibvisioArrowedStrokeBake(shape)) {
    return false;
  }
  if (paintsFill || shape.hasImage) return !shape.line.hasLine;
  return true;
}

/// Glow cells Draw will collect. Size is 0 after a Line / Fill bake.
VsdxGlow glowForLibvisioWrite(VsdxShape shape) {
  if (!shapeNeedsLibvisioGlowBake(shape) &&
      !shapeNeedsLibvisioGlowPlateBake(shape)) {
    return shape.glow;
  }
  return shape.glow.copyWith(enabled: false, sizeInches: 0);
}

({List<VsdxGeometry> geometries, VsdxLine line, VsdxFill fill})?
    bakeGlowForLibvisio({
  required VsdxShape shape,
  required List<VsdxGeometry> geometries,
  required VsdxLine line,
  required VsdxFill fill,
  VsdxTheme theme = VsdxTheme.empty,
}) {
  if (!shapeNeedsLibvisioGlowBake(shape)) return null;
  final glow = shape.glow;
  final paintsFill = _geometriesPaintFill(fill, geometries);
  final paintsLine = _geometriesPaintLine(line, geometries);
  if (!paintsFill) {
    final out = <VsdxGeometry>[...geometries];
    var added = false;
    for (final geometry in geometries) {
      if (geometry.noShow || geometry.noLine) continue;
      final points = _strokedVertices(geometry, shape);
      if (points == null || points.length < 2) continue;
      final closed = polylineLooksClosed(points, noFill: geometry.noFill);
      final commands = strokeRibbonCommands(
        points,
        halfWidth: math.max(glow.sizeInches, 0.01),
        closed: closed,
      );
      if (commands.length < 3) continue;
      out.add(
        VsdxGeometry(
          noFill: false,
          noLine: true,
          commands: commands,
        ),
      );
      added = true;
    }
    if (added) {
      return (
        geometries: out,
        line: line,
        fill: _glowFillForLibvisio(glow, theme),
      );
    }
    if (!paintsLine) {
      return (
        geometries: geometries,
        line: _glowLineForLibvisio(line, glow, theme),
        fill: fill,
      );
    }
    return null;
  }
  if (!paintsLine) {
    return (
      geometries: geometries,
      line: _glowLineForLibvisio(line, glow, theme),
      fill: fill,
    );
  }
  return null;
}

bool _hasArrowheads(VsdxLine line) =>
    line.beginArrow != 0 || line.endArrow != 0;

/// libvisio / LibreOffice suppress `draw:marker-*` on Z-closed subpaths
/// (`VSD_EPSILON` 1E-6), matching canvas `_paintLineEndings`. Arrow cells
/// on a closed 2-D box therefore must not block a stroke bake.
bool _shapeHasOpenLineEndings(VsdxShape shape) {
  final w = shape.width.abs();
  final h = shape.height.abs();
  for (final geometry in shape.geometries) {
    if (geometry.noShow || geometry.noLine || geometry.commands.isEmpty) {
      continue;
    }
    if (geometrySubpathEndpointTangents(
      geometry,
      widthInches: w,
      heightInches: h,
    ).isNotEmpty) {
      return true;
    }
  }
  return false;
}

bool _openArrowheadsBlockStrokeBake(VsdxShape shape) =>
    _hasArrowheads(shape.line) && _shapeHasOpenLineEndings(shape);

VsdxShape _withoutArrowheads(VsdxShape shape) => shape.copyWith(
      line: shape.line.copyWith(beginArrow: 0, endArrow: 0),
    );

/// Marker width `VSDContentCollector::_lineProperties` actually emits.
///
/// `tokens.txt` has no BeginArrowSize / EndArrowSize. Draw uses
/// `markerScale * (0.1/(width²+1) + 2.54*width) * pageScale` (inches),
/// matching `_linePropertiesMarkerScale` for ids 10–11 / 14–18 / 22.
double libvisioMarkerSizeInches({
  required int marker,
  required double strokeWidthInches,
  double pageScale = 1.0,
}) {
  final markerScale = switch (marker) {
    10 || 11 => 0.7,
    14 || 15 || 16 || 17 || 18 || 22 => 1.2,
    _ => 1.0,
  };
  final width = strokeWidthInches.isFinite ? strokeWidthInches : 0.0;
  final scale = pageScale.isFinite ? pageScale : 1.0;
  return scale * markerScale * (0.1 / (width * width + 1.0) + 2.54 * width);
}

bool _hasVsdImportedArrowSize(VsdxShape shape) => shape.userCells.any(
      (cell) =>
          cell.name == VsdxShape.userVsdBeginArrowSize ||
          cell.name == VsdxShape.userVsdEndArrowSize,
    );

bool _arrowSizeMismatchesLibvisio({
  required int arrowId,
  required double authoredInches,
  required double weightInches,
}) {
  if (arrowId == 0) return false;
  final expected = libvisioMarkerSizeInches(
    marker: arrowId,
    strokeWidthInches: weightInches,
  );
  final authored = authoredInches <= 0 ? 0.125 : authoredInches;
  // Visio bucket 2 is 0.125" for every marker id. Draw then scales ids
  // 10–11 / 14–18 / 22 by 0.7 / 1.2 from LineWeight, so an untouched
  // default arrow already "mismatches" that formula. Baking those would
  // drop native BeginArrow on every save (export of ids 1–45, VDX
  // inherited arrows). Only a non-default bucket is worth a Geometry bake.
  const defaultBucketInches = 0.125;
  if ((authored - defaultBucketInches).abs() <= 0.02) return false;
  final span = math.max(authored, expected);
  if (span < 1e-9) return false;
  return (authored - expected).abs() > math.max(0.02, 0.15 * span);
}

/// Arrowed 1-D that also needs rails / a ribbon, or whose size Draw would
/// take from LineWeight instead of BeginArrowSize: bake markers as Geometry.
///
/// libvisio hangs `draw:marker-*` on every open path, so CompoundType rails
/// would duplicate arrowheads, and a closed LineGradient / LineColorTrans
/// ribbon cannot carry shape-level markers. Dash bakes multiply open
/// subpaths the same way — a flattened `veDashPattern` or Flow Animation
/// route puts one marker on *every* dash — so those bake markers too.
/// `tokens.txt` also has no
/// BeginArrowSize cell — marker width follows line weight — so baking the
/// polygon at [VsdxLine.beginArrowSizeInches] is the size Draw will paint.
bool shapeNeedsLibvisioArrowedStrokeBake(VsdxShape shape) {
  if (!_hasArrowheads(shape.line)) return false;
  if (!_shapeHasOpenLineEndings(shape)) return false;
  if (_shapePaintsFill(shape, shape.geometries)) return false;
  if (_strokeTips(shape) == null) return false;
  if (!_hasVsdImportedArrowSize(shape) &&
      (libvisioMarkerPathIsIncomplete(shape.line.beginArrow) ||
          libvisioMarkerPathIsIncomplete(shape.line.endArrow))) {
    return true;
  }
  if (!_hasVsdImportedArrowSize(shape) &&
      (_arrowSizeMismatchesLibvisio(
            arrowId: shape.line.beginArrow,
            authoredInches: shape.line.beginArrowSizeInches,
            weightInches: shape.line.weightInches,
          ) ||
          _arrowSizeMismatchesLibvisio(
            arrowId: shape.line.endArrow,
            authoredInches: shape.line.endArrowSizeInches,
            weightInches: shape.line.weightInches,
          ))) {
    return true;
  }
  final stripped = _withoutArrowheads(shape);
  if (_customDashCanBake(stripped, stripped.line, stripped.geometries)) {
    return true;
  }
  if (_flowDashCanBake(stripped, stripped.geometries)) return true;
  return shapeNeedsLibvisioCompoundBake(stripped) ||
      shapeNeedsLibvisioStrokeRibbon(stripped);
}

/// `true` when CompoundType would otherwise vanish in Draw.
///
/// 1-D connectors with arrowheads are left alone unless
/// [shapeNeedsLibvisioArrowedStrokeBake] will turn the markers into Geometry
/// first: libvisio hangs a marker on every open path, so splitting a
/// connector into rails would otherwise duplicate the arrow.
bool shapeNeedsLibvisioCompoundBake(VsdxShape shape) {
  if (shape.is1D && _hasArrowheads(shape.line)) return false;
  if (shape.line.compoundType <= 0 || !shape.line.hasLine) return false;
  final weight =
      shape.line.weightInches > 1e-9 ? shape.line.weightInches : 0.01;
  if (compoundRails(shape.line.compoundType, weight).isEmpty) return false;
  for (final geometry in shape.geometries) {
    if (geometry.noShow || geometry.noLine) continue;
    final points = _strokedVertices(geometry, shape);
    if (points != null && points.length >= 2) return true;
  }
  return false;
}

/// Whether an unfilled CompoundType 2–4 can keep thick/thin contrast in Draw.
///
/// LineWeight is shape-level, so stroked rails must share one width (the
/// thinnest, or they blob). Unfilled solid / gradient / transparent strokes
/// can instead become filled ribbons of each rail's own width — FillPattern
/// and FillForegndTrans are tokens. Dashes 2–23 stay stroked so
/// `_lineProperties` still paints them. Filled 2-D keeps stroked rails
/// because the shape's Fill is already the body colour.
bool _useVariableWidthCompoundRibbons(VsdxShape shape) {
  if (shape.line.compoundType < 2) return false;
  if (_shapePaintsFill(shape, shape.geometries)) return false;
  final pattern = linePatternForLibvisioWrite(shape.line);
  if (pattern >= 2 &&
      pattern <= 23 &&
      !shape.line.hasGradient &&
      shape.line.transparency <= 1e-9) {
    return false;
  }
  return true;
}

/// Offset each stroked polyline into rails libvisio can stroke (or fill).
///
/// CompoundType 1 (equal double) stays two strokes. Unfilled 2–4 become
/// per-rail ribbons so Draw keeps thick-thin / triple contrast; filled 2-D
/// and dashed unfilled strokes keep parallel strokes at the thinnest rail
/// width so they do not blob into one fat line.
({List<VsdxGeometry> geometries, VsdxLine line, VsdxFill? fill})?
    bakeCompoundTypeForLibvisio(
  VsdxShape shape,
) {
  if (!shapeNeedsLibvisioCompoundBake(shape)) return null;
  final weight =
      shape.line.weightInches > 1e-9 ? shape.line.weightInches : 0.01;
  final rails = compoundRails(shape.line.compoundType, weight);
  if (rails.isEmpty) return null;
  final useRibbons = _useVariableWidthCompoundRibbons(shape);

  final out = <VsdxGeometry>[];
  var addedRails = false;
  for (final geometry in shape.geometries) {
    if (geometry.noShow) {
      out.add(geometry);
      continue;
    }
    if (geometry.noLine) {
      out.add(geometry);
      continue;
    }
    final points = _strokedVertices(geometry, shape);
    if (points == null || points.length < 2) {
      out.add(geometry);
      continue;
    }
    final closed = polylineLooksClosed(points, noFill: geometry.noFill);
    if (!geometry.noFill) {
      out.add(geometry.copyWith(noLine: true));
    }
    for (final rail in rails) {
      final offset = offsetPolyline(points, rail.offset, closed: closed);
      if (offset.length < 2) continue;
      if (useRibbons) {
        final commands = strokeRibbonCommands(
          offset,
          halfWidth: rail.width / 2,
          closed: closed,
          miterLimit: shape.line.miterLimit,
        );
        if (commands.length < 3) continue;
        out.add(
          VsdxGeometry(
            noFill: false,
            noLine: true,
            commands: commands,
          ),
        );
      } else {
        out.add(
          VsdxGeometry(
            noFill: true,
            noLine: false,
            commands: polylineCommands(offset, closed: closed),
          ),
        );
      }
      addedRails = true;
    }
  }
  if (!addedRails) return null;

  if (useRibbons) {
    final fill =
        _fillFromLineStroke(shape.line) ?? _opaqueFillFromLine(shape.line);
    return (
      geometries: out,
      line: shape.line.copyWith(
        compoundType: 0,
        pattern: 0,
        gradient: null,
        transparency: 0,
      ),
      fill: fill,
    );
  }

  var railWeight = rails.first.width;
  for (final rail in rails) {
    if (rail.width < railWeight) railWeight = rail.width;
  }
  return (
    geometries: out,
    line: shape.line.copyWith(
      compoundType: 0,
      weightInches: railWeight,
    ),
    fill: null,
  );
}

/// `true` when a round cap would make Draw round-join an explicit miter elbow.
///
/// `_lineProperties` maps join from LineCap only. Canvas / SVG honour
/// `User.veLineJoin` miter / miter-clip even on a round cap, so a 90°
/// corner is sharp here and a round join in Draw. Flattening LineCap to
/// extended makes Draw miter, matching the bevel-on-round-cap bake.
/// Straight edges have no join and keep the round endpoints.
bool shapeNeedsLibvisioRoundCapMiterFlatten(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  if (!shape.line.hasLine) return false;
  if (shape.line.cap != LineCap.round) return false;
  if (shape.line.join != VsdxLineJoin.miter &&
      shape.line.join != VsdxLineJoin.miterClip) {
    return false;
  }
  if (shape.line.roundingInches > 1e-12) return false;
  for (final geometry in shape.geometries) {
    if (geometry.noShow || geometry.noLine) continue;
    final points = _strokedVertices(geometry, shape);
    if (points == null || points.length < 3) continue;
    final closed = polylineLooksClosed(points, noFill: geometry.noFill);
    if (polylineHasElbow(points, closed: closed)) return true;
  }
  return false;
}

bool _shapeHasLibvisioMiterSpikeCorners(VsdxShape shape) {
  if (shape.line.cap == LineCap.round &&
      !shapeNeedsLibvisioRoundCapMiterFlatten(shape)) {
    return false;
  }
  if (shape.line.roundingInches > 1e-12) return false;
  if (!_lineUsesMiterJoin(shape.line)) return false;
  if (shape.line.miterLimit <= 4.0 + 1e-6) return false;
  for (final geometry in shape.geometries) {
    if (geometry.noShow || geometry.noLine) continue;
    final points = _strokedVertices(geometry, shape);
    if (points == null || points.length < 3) continue;
    final closed = polylineLooksClosed(points, noFill: geometry.noFill);
    if (polylineHasDrawClippedMiter(points, closed: closed)) return true;
  }
  return false;
}

/// `true` when a miter spike longer than Draw's default 4 must become a ribbon.
///
/// `_lineProperties` never emits `svg:stroke-miterlimit`; ODF/Draw default
/// to 4. Canvas / SVG honour `User.veMiterLimit` above that, so a sharp
/// elbow (ratio>4) is a long spike here and a bevel in Draw. Unfilled
/// solid polylines expand to a filled ribbon whose outline uses that
/// limit. Filled 2-D keeps FillPattern for the body and bakes a sibling
/// instead ([shapeNeedsLibvisioFilledStrokeRibbonBake]). Dashed strokes keep
/// LinePattern. A round cap with an implicit join stays native; an explicit
/// miter join flattens the cap first so Draw does not round the elbow.
bool shapeNeedsLibvisioMiterSpikeBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  if (_openArrowheadsBlockStrokeBake(shape)) return false;
  if (!shape.line.hasLine) return false;
  if (shape.line.pattern != 1) return false;
  final custom = shape.line.customDashPattern;
  if (custom != null && custom.isNotEmpty) return false;
  if (_shapePaintsFill(shape, shape.geometries)) return false;
  return _shapeHasLibvisioMiterSpikeCorners(shape);
}

VsdxFill _opaqueFillFromLine(
  VsdxLine line, [
  VsdxTheme theme = VsdxTheme.empty,
]) =>
    VsdxFill(
      foreground: _lineRgbForLibvisioWrite(line, theme),
      background: _lineRgbForLibvisioWrite(line, theme),
      pattern: 1,
    );

/// `true` when an unfilled LineGradient / LineColorTrans stroke vanishes in Draw.
///
/// `tokens.txt` has no LineGradient or LineColorTrans cell, and
/// `xmlStringToColour` always stores Colour.a = 0, so `VSDContentCollector`
/// paints every VSDX stroke opaque. Arrowheads stay shape-level markers and
/// cannot follow a filled ribbon, so connectors with arrows keep LineColor
/// unless [shapeNeedsLibvisioArrowedStrokeBake] turns the markers into
/// Geometry first. Arrow-less 1-D strokes bake the same ribbon as 2-D:
/// XForm1D / glue cells are untouched, matching CompoundType. Filled
/// shapes already occupy FillPattern, so they keep LineColor (Draw will
/// show an opaque stroke). A `veMiterLimit` above 4 on an unfilled solid
/// polyline uses the same ribbon so Draw does not bevel ratio>4 elbows.
bool shapeNeedsLibvisioStrokeRibbon(VsdxShape shape) {
  if (_openArrowheadsBlockStrokeBake(shape)) return false;
  if (!shape.line.hasLine) return false;
  if (!shape.line.hasGradient &&
      shape.line.transparency <= 1e-9 &&
      !shapeNeedsLibvisioMiterSpikeBake(shape)) {
    return false;
  }
  if (_shapePaintsFill(shape, shape.geometries)) return false;
  for (final geometry in shape.geometries) {
    if (geometry.noShow || geometry.noLine) continue;
    final points = _strokedVertices(geometry, shape);
    if (points != null && points.length >= 2) return true;
  }
  return false;
}

/// Back-compat name for the LineGradient half of [shapeNeedsLibvisioStrokeRibbon].
bool shapeNeedsLibvisioLineGradientRibbon(VsdxShape shape) =>
    shape.line.hasGradient && shapeNeedsLibvisioStrokeRibbon(shape);

({Offset2D begin, Offset2D beginFrom, Offset2D end, Offset2D endFrom})?
    _strokeTips(VsdxShape shape) {
  for (final geometry in shape.geometries) {
    if (geometry.noShow || geometry.noLine) continue;
    final points = _strokedVertices(geometry, shape);
    if (points == null || points.length < 2) continue;
    var beginFrom = points[1];
    var endFrom = points[points.length - 2];
    if ((beginFrom.x - points.first.x).abs() < 1e-12 &&
        (beginFrom.y - points.first.y).abs() < 1e-12 &&
        points.length > 2) {
      beginFrom = points[2];
    }
    if ((endFrom.x - points.last.x).abs() < 1e-12 &&
        (endFrom.y - points.last.y).abs() < 1e-12 &&
        points.length > 2) {
      endFrom = points[points.length - 3];
    }
    return (
      begin: points.first,
      beginFrom: beginFrom,
      end: points.last,
      endFrom: endFrom,
    );
  }
  return null;
}

/// Marker ids whose LibreOffice path is a TODO stub in
/// `VSDContentCollector::_linePropertiesMarkerPath` (copies a sibling).
bool libvisioMarkerPathIsIncomplete(int arrowId) {
  switch (arrowId) {
    case 26:
    case 31:
    case 32:
    case 33:
    case 34:
    case 36:
    case 37:
    case 38:
    case 40:
    case 43:
    case 44:
    case 45:
      return true;
    default:
      return false;
  }
}

/// Local-space arrow bake: tip at the origin, body along −X, unit size.
///
/// Matches `lib/render/arrow_library.dart` so Visio (native markers gone)
/// and Draw (Geometry only) see the same silhouette. Open ids are later
/// expanded to filled ribbons because LineWeight is shape-level.
class _ArrowBakeSpec {
  const _ArrowBakeSpec({
    required this.polylines,
    required this.closed,
    required this.filled,
    this.centered = false,
  });

  final List<List<Offset2D>> polylines;
  final bool closed;
  final bool filled;
  final bool centered;
}

List<Offset2D> _regularPolygon({
  required double cx,
  required double cy,
  required double radius,
  int sides = 16,
}) =>
    [
      for (var i = 0; i < sides; i++)
        Offset2D(
          cx + radius * math.cos(i * 2 * math.pi / sides),
          cy + radius * math.sin(i * 2 * math.pi / sides),
        ),
    ];

_ArrowBakeSpec _arrowBakeSpec(int arrowId) {
  switch (arrowId) {
    case 1:
    case 3:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(-1, -0.4), Offset2D(0, 0), Offset2D(-1, 0.4)],
        ],
        closed: false,
        filled: false,
      );
    case 43:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(-0.5, -0.4), Offset2D(0, 0), Offset2D(-0.5, 0.4)],
          [Offset2D(-1.0, -0.4), Offset2D(-0.5, 0), Offset2D(-1.0, 0.4)],
        ],
        closed: false,
        filled: false,
      );
    case 44:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(-1, -0.4), Offset2D(0, 0), Offset2D(-1, 0.4)],
          [Offset2D(-1.2, -0.5), Offset2D(-1.2, 0.5)],
        ],
        closed: false,
        filled: false,
      );
    case 45:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(-0.5, -0.4), Offset2D(0, 0), Offset2D(-0.5, 0.4)],
          [Offset2D(-1.0, -0.4), Offset2D(-0.5, 0), Offset2D(-1.0, 0.4)],
          [Offset2D(-1.2, -0.5), Offset2D(-1.2, 0.5)],
        ],
        closed: false,
        filled: false,
      );
    case 2:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(0, 0), Offset2D(-1, -0.25), Offset2D(-1, 0.25)],
        ],
        closed: true,
        filled: true,
      );
    case 5:
      return const _ArrowBakeSpec(
        polylines: [
          [
            Offset2D(0, 0),
            Offset2D(-1, -0.4),
            Offset2D(-0.7, 0),
            Offset2D(-1, 0.4),
          ],
        ],
        closed: true,
        filled: true,
      );
    case 6:
    case 8:
      return const _ArrowBakeSpec(
        polylines: [
          [
            Offset2D(0, 0),
            Offset2D(-1.1, -0.45),
            Offset2D(-0.85, 0),
            Offset2D(-1.1, 0.45),
          ],
        ],
        closed: true,
        filled: true,
      );
    case 7:
    case 19:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(-0.55, -0.5), Offset2D(0, 0), Offset2D(-0.55, 0.5)],
        ],
        closed: false,
        filled: false,
      );
    case 9:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(-1, -1.1), Offset2D(0, 1.1)],
          [Offset2D(-0.5, -1.1), Offset2D(-0.5, 1.1)],
        ],
        closed: false,
        filled: false,
        centered: true,
      );
    case 10:
      return _ArrowBakeSpec(
        polylines: [_regularPolygon(cx: -0.5, cy: 0, radius: 0.5)],
        closed: true,
        filled: true,
        centered: true,
      );
    case 11:
      return const _ArrowBakeSpec(
        polylines: [
          [
            Offset2D(-0.85, -0.4),
            Offset2D(0, -0.4),
            Offset2D(0, 0.4),
            Offset2D(-0.85, 0.4),
          ],
        ],
        closed: true,
        filled: true,
        centered: true,
      );
    case 12:
    case 18:
      return const _ArrowBakeSpec(
        polylines: [
          [
            Offset2D(0, 0),
            Offset2D(-1.1, -0.45),
            Offset2D(-0.85, 0),
            Offset2D(-1.1, 0.45),
          ],
        ],
        closed: true,
        filled: false,
      );
    case 13:
      return const _ArrowBakeSpec(
        polylines: [
          [
            Offset2D(0, 0),
            Offset2D(-1.4, -1.4 / 3),
            Offset2D(-1.4, 1.4 / 3),
          ],
        ],
        closed: true,
        filled: true,
      );
    case 14:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(0, 0), Offset2D(-0.85, -0.55), Offset2D(-0.85, 0.55)],
        ],
        closed: true,
        filled: false,
      );
    case 15:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(0, 0), Offset2D(-1, -0.25), Offset2D(-1, 0.25)],
        ],
        closed: true,
        filled: false,
      );
    case 16:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(0, 0), Offset2D(-1, -0.4), Offset2D(-1, 0.4)],
        ],
        closed: true,
        filled: false,
      );
    case 17:
      return const _ArrowBakeSpec(
        polylines: [
          [
            Offset2D(0, 0),
            Offset2D(-1, -0.4),
            Offset2D(-0.7, 0),
            Offset2D(-1, 0.4),
          ],
        ],
        closed: true,
        filled: false,
      );
    case 20:
      return _ArrowBakeSpec(
        polylines: [_regularPolygon(cx: -0.5, cy: 0, radius: 0.4)],
        closed: true,
        filled: false,
        centered: true,
      );
    case 21:
      return const _ArrowBakeSpec(
        polylines: [
          [
            Offset2D(-0.85, -0.4),
            Offset2D(0, -0.4),
            Offset2D(0, 0.4),
            Offset2D(-0.85, 0.4),
          ],
        ],
        closed: true,
        filled: false,
        centered: true,
      );
    case 22:
      return const _ArrowBakeSpec(
        polylines: [
          [
            Offset2D(0, 0),
            Offset2D(-0.5, -0.35),
            Offset2D(-1, 0),
            Offset2D(-0.5, 0.35),
          ],
        ],
        closed: true,
        filled: false,
      );
    case 23:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(-1, 0.5), Offset2D(0, -0.5)],
          [Offset2D(-0.5, -0.5), Offset2D(-0.5, 0.5)],
        ],
        closed: false,
        filled: false,
      );
    case 24:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(-0.3, -0.5), Offset2D(-0.3, 0.5)],
        ],
        closed: false,
        filled: false,
      );
    case 25:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(-0.3, -0.5), Offset2D(-0.3, 0.5)],
          [Offset2D(-0.55, -0.5), Offset2D(-0.55, 0.5)],
        ],
        closed: false,
        filled: false,
      );
    case 26:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(-0.2, -0.5), Offset2D(-0.2, 0.5)],
          [Offset2D(-0.4, -0.5), Offset2D(-0.4, 0.5)],
          [Offset2D(-0.6, -0.5), Offset2D(-0.6, 0.5)],
        ],
        closed: false,
        filled: false,
      );
    case 27:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(0, 0), Offset2D(0.85, -0.5)],
          [Offset2D(0, 0), Offset2D(0.85, 0)],
          [Offset2D(0, 0), Offset2D(0.85, 0.5)],
        ],
        closed: false,
        filled: false,
      );
    case 28:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(0, 0), Offset2D(0.72, -0.5)],
          [Offset2D(0, 0), Offset2D(0.72, 0)],
          [Offset2D(0, 0), Offset2D(0.72, 0.5)],
          [Offset2D(0.88, -0.5), Offset2D(0.88, 0.5)],
        ],
        closed: false,
        filled: false,
      );
    case 29:
      return _ArrowBakeSpec(
        polylines: [
          _regularPolygon(cx: 0.4, cy: 0, radius: 0.18),
          const [Offset2D(0.6, -0.05), Offset2D(1.1, -0.5)],
          const [Offset2D(0.6, 0), Offset2D(1.1, 0)],
          const [Offset2D(0.6, 0.05), Offset2D(1.1, 0.5)],
        ],
        closed: false,
        filled: false,
      );
    case 30:
      return _ArrowBakeSpec(
        polylines: [
          _regularPolygon(cx: 0.6, cy: 0, radius: 0.18),
          const [Offset2D(0.3, -0.5), Offset2D(0.3, 0.5)],
        ],
        closed: false,
        filled: false,
      );
    case 31:
      return _ArrowBakeSpec(
        polylines: [
          _regularPolygon(cx: -0.4, cy: 0, radius: 0.4),
          const [Offset2D(-1.0, -0.5), Offset2D(-1.0, 0.5)],
        ],
        closed: true,
        filled: false,
      );
    case 32:
      return _ArrowBakeSpec(
        polylines: [
          _regularPolygon(cx: -0.4, cy: 0, radius: 0.4),
          const [Offset2D(-0.95, -0.5), Offset2D(-0.95, 0.5)],
          const [Offset2D(-1.2, -0.5), Offset2D(-1.2, 0.5)],
        ],
        closed: true,
        filled: false,
      );
    case 33:
      return _ArrowBakeSpec(
        polylines: [
          _regularPolygon(cx: -0.4, cy: 0, radius: 0.4),
          const [Offset2D(-0.9, -0.5), Offset2D(-0.9, 0.5)],
          const [Offset2D(-1.15, -0.5), Offset2D(-1.15, 0.5)],
          const [Offset2D(-1.4, -0.5), Offset2D(-1.4, 0.5)],
        ],
        closed: true,
        filled: false,
      );
    case 34:
      return _ArrowBakeSpec(
        polylines: [
          _regularPolygon(cx: -0.35, cy: 0, radius: 0.35),
          const [
            Offset2D(-0.8, 0),
            Offset2D(-1.15, -0.35),
            Offset2D(-1.5, 0),
            Offset2D(-1.15, 0.35),
          ],
        ],
        closed: true,
        filled: false,
      );
    case 41:
      return _ArrowBakeSpec(
        polylines: [_regularPolygon(cx: -0.5, cy: 0, radius: 0.5)],
        closed: true,
        filled: false,
      );
    case 35:
      return _ArrowBakeSpec(
        polylines: [
          _regularPolygon(cx: -0.4, cy: 0, radius: 0.4),
          const [
            Offset2D(-1.0, -0.5),
            Offset2D(-0.8, -0.5),
            Offset2D(-0.8, 0.5),
            Offset2D(-1.0, 0.5),
          ],
        ],
        closed: true,
        filled: true,
      );
    case 36:
      return _ArrowBakeSpec(
        polylines: [
          _regularPolygon(cx: -0.4, cy: 0, radius: 0.4),
          const [
            Offset2D(-1.0, -0.5),
            Offset2D(-0.8, -0.5),
            Offset2D(-0.8, 0.5),
            Offset2D(-1.0, 0.5),
          ],
          const [
            Offset2D(-1.25, -0.5),
            Offset2D(-1.05, -0.5),
            Offset2D(-1.05, 0.5),
            Offset2D(-1.25, 0.5),
          ],
        ],
        closed: true,
        filled: true,
      );
    case 37:
      return _ArrowBakeSpec(
        polylines: [
          _regularPolygon(cx: -0.4, cy: 0, radius: 0.4),
          const [
            Offset2D(-1.0, -0.5),
            Offset2D(-0.8, -0.5),
            Offset2D(-0.8, 0.5),
            Offset2D(-1.0, 0.5),
          ],
          const [
            Offset2D(-1.25, -0.5),
            Offset2D(-1.05, -0.5),
            Offset2D(-1.05, 0.5),
            Offset2D(-1.25, 0.5),
          ],
          const [
            Offset2D(-1.5, -0.5),
            Offset2D(-1.3, -0.5),
            Offset2D(-1.3, 0.5),
            Offset2D(-1.5, 0.5),
          ],
        ],
        closed: true,
        filled: true,
      );
    case 38:
      return _ArrowBakeSpec(
        polylines: [
          _regularPolygon(cx: -0.35, cy: 0, radius: 0.35),
          const [
            Offset2D(-0.8, 0),
            Offset2D(-1.15, -0.35),
            Offset2D(-1.5, 0),
            Offset2D(-1.15, 0.35),
          ],
        ],
        closed: true,
        filled: true,
      );
    case 42:
      return _ArrowBakeSpec(
        polylines: [_regularPolygon(cx: -0.5, cy: 0, radius: 0.5)],
        closed: true,
        filled: true,
      );
    case 39:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(0, 0), Offset2D(-0.6, -0.35), Offset2D(-0.6, 0.35)],
          [Offset2D(-0.6, 0), Offset2D(-1.2, -0.35), Offset2D(-1.2, 0.35)],
        ],
        closed: true,
        filled: true,
      );
    case 40:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(0, 0), Offset2D(-0.6, -0.35), Offset2D(-0.6, 0.35)],
          [Offset2D(-0.6, 0), Offset2D(-1.2, -0.35), Offset2D(-1.2, 0.35)],
        ],
        closed: true,
        filled: false,
      );
    default:
      return const _ArrowBakeSpec(
        polylines: [
          [Offset2D(0, 0), Offset2D(-1, -0.4), Offset2D(-1, 0.4)],
        ],
        closed: true,
        filled: true,
      );
  }
}

/// Shape-local filled polygons / ribbons for BeginArrow / EndArrow.
List<VsdxGeometry> bakeArrowGeometriesForLibvisio(VsdxShape shape) {
  final tips = _strokeTips(shape);
  if (tips == null) return const <VsdxGeometry>[];
  final out = <VsdxGeometry>[];
  final halfWeight =
      (shape.line.weightInches > 1e-9 ? shape.line.weightInches : 0.01) / 2;
  void add(int id, double size, Offset2D tip, Offset2D from) {
    if (id == 0) return;
    final dx = tip.x - from.x;
    final dy = tip.y - from.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-12) return;
    final ux = dx / len;
    final uy = dy / len;
    final mw = size <= 0 ? 0.125 : size;
    final spec = _arrowBakeSpec(id);
    var localPolys = spec.polylines;
    if (spec.centered) {
      var minX = double.infinity;
      var maxX = -double.infinity;
      for (final poly in localPolys) {
        for (final p in poly) {
          if (p.x < minX) minX = p.x;
          if (p.x > maxX) maxX = p.x;
        }
      }
      if (minX.isFinite) {
        final shift = (minX + maxX) / 2;
        localPolys = [
          for (final poly in localPolys)
            [for (final p in poly) Offset2D(p.x - shift, p.y)],
        ];
      }
    }
    for (final local in localPolys) {
      final world = <Offset2D>[
        for (final p in local)
          Offset2D(
            tip.x + p.x * mw * ux - p.y * mw * uy,
            tip.y + p.x * mw * uy + p.y * mw * ux,
          ),
      ];
      if (spec.filled) {
        if (world.length < 3) continue;
        out.add(
          VsdxGeometry(
            noFill: false,
            noLine: true,
            commands: polylineCommands(world, closed: spec.closed),
          ),
        );
        continue;
      }
      if (world.length < 2) continue;
      final closed = (spec.closed && world.length >= 3) || world.length >= 8;
      final commands = strokeRibbonCommands(
        world,
        halfWidth: halfWeight,
        closed: closed,
      );
      if (commands.length < 3) continue;
      out.add(
        VsdxGeometry(
          noFill: false,
          noLine: true,
          commands: commands,
        ),
      );
    }
  }

  add(
    shape.line.beginArrow,
    shape.line.beginArrowSizeInches,
    tips.begin,
    tips.beginFrom,
  );
  add(
    shape.line.endArrow,
    shape.line.endArrowSizeInches,
    tips.end,
    tips.endFrom,
  );
  return out;
}

/// Expand an unfilled gradient, transparent, or high-miter stroke into a
/// closed ribbon FillPattern 25–40 / FillForegndTrans can paint. Compound
/// rails, when present, are expanded one by one. Dash gaps must already live
/// in Geometry (custom arrays or LinePattern 2–23); a single ribbon of the
/// whole polyline would be solid. A `veMiterLimit` above Draw's default 4
/// uses that limit on the outline so sharp elbows keep the canvas spike.
({List<VsdxGeometry> geometries, VsdxLine line, VsdxFill fill})?
    bakeStrokeRibbonForLibvisio({
  required VsdxShape shape,
  required List<VsdxGeometry> geometries,
  required VsdxLine line,
  VsdxTheme theme = VsdxTheme.empty,
}) {
  if (!shapeNeedsLibvisioStrokeRibbon(shape)) return null;
  if (!line.hasLine) return null;
  var fill = _fillFromLineStroke(line, theme);
  if (fill == null) {
    if (!shapeNeedsLibvisioMiterSpikeBake(
      shape.copyWith(geometries: geometries, line: line),
    )) {
      return null;
    }
    fill = _opaqueFillFromLine(line, theme);
  }

  final weight = line.weightInches > 1e-9 ? line.weightInches : 0.01;
  final half = weight / 2;
  final out = <VsdxGeometry>[];
  var added = false;
  for (final geometry in geometries) {
    if (geometry.noShow || geometry.noLine) {
      out.add(geometry);
      continue;
    }
    final points = _strokedVertices(geometry, shape);
    if (points == null || points.length < 2) {
      out.add(geometry);
      continue;
    }
    final closed = polylineLooksClosed(points, noFill: geometry.noFill);
    final commands = strokeRibbonCommands(
      points,
      halfWidth: half,
      closed: closed,
      miterLimit: line.miterLimit,
    );
    if (commands.length < 3) {
      out.add(geometry);
      continue;
    }
    out.add(
      VsdxGeometry(
        noFill: false,
        noLine: true,
        commands: commands,
      ),
    );
    added = true;
  }
  if (!added) return null;

  return (
    geometries: out,
    line: line.copyWith(pattern: 0, gradient: null, transparency: 0),
    fill: fill,
  );
}

VsdxFill? _fillFromLineStroke(
  VsdxLine line, [
  VsdxTheme theme = VsdxTheme.empty,
]) {
  final transparency = line.transparency.clamp(0.0, 1.0);
  if (line.hasGradient) {
    final gradient = line.gradient!;
    VsdxColor? firstColor;
    VsdxColor? lastColor;
    var saw = false;
    for (final stop in gradient.stops) {
      final color = _gradientStopRgbForLibvisioWrite(stop, theme);
      if (color == null) continue;
      if (!saw) {
        firstColor = color;
        saw = true;
      }
      lastColor = color;
    }
    if (!saw) {
      firstColor = line.color ??
          _gradientStopRgbForLibvisioWrite(
            VsdxGradientStop(
              position: 0,
              themeColorIndex: line.themeColorIndex,
            ),
            theme,
          ) ??
          const VsdxColor(0xFF000000);
      lastColor = firstColor;
    }
    return VsdxFill(
      foreground: firstColor,
      background: lastColor,
      pattern: 1,
      gradient: gradient,
      foregroundTransparency: transparency,
      backgroundTransparency: transparency,
    );
  }
  if (transparency <= 1e-9) return null;
  // Freeze theme LineColor: writer emits hex whenever foreground is set, and
  // the previous black fallback plus THEMEVAL painted a grey wash. FillForegndTrans
  // is a token, so Draw still composites this RGB over the page / body.
  final color = _lineRgbForLibvisioWrite(line, theme);
  return VsdxFill(
    foreground: color,
    background: color,
    pattern: 1,
    foregroundTransparency: transparency,
    backgroundTransparency: transparency,
  );
}

/// Closed polygon covering a stroked polyline, used as a filled ribbon.
List<VsdxPathCommand> strokeRibbonCommands(
  List<Offset2D> points, {
  required double halfWidth,
  required bool closed,
  double miterLimit = 4,
}) {
  final left = offsetPolyline(
    points,
    halfWidth,
    closed: closed,
    miterLimit: miterLimit,
  );
  final right = offsetPolyline(
    points,
    -halfWidth,
    closed: closed,
    miterLimit: miterLimit,
  );
  if (left.length < 2 || right.length < 2) {
    return const <VsdxPathCommand>[];
  }
  if (closed) {
    return <VsdxPathCommand>[
      ...polylineCommands(left, closed: true),
      ...polylineCommands(List<Offset2D>.of(right.reversed), closed: true),
    ];
  }
  return polylineCommands(
    <Offset2D>[...left, ...right.reversed],
    closed: true,
  );
}

/// `true` when `User.veDashPattern` must become Geometry Draw can stroke.
///
/// `_lineProperties` only dashes ids 2–23. Custom draw.io arrays snap onto
/// that table as a fallback, but a sequence that is not one of those ids
/// (and every `veFixedDash` array, which is CSS-px rather than weight-
/// scaled) has to be MoveTo/LineTo dashes with LinePattern=1. Filled 2-D
/// keeps the original ring as NoLine so FillPattern is untouched.
bool shapeNeedsLibvisioCustomDashBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  return _customDashCanBake(shape, shape.line, shape.geometries);
}

bool _customDashCanBake(
  VsdxShape shape,
  VsdxLine line,
  List<VsdxGeometry> geometries,
) {
  if (!line.hasLine) return false;
  final custom = line.customDashPattern;
  if (custom == null || custom.isEmpty) return false;
  final inches = effectiveDashPatternForLine(line);
  if (inches == null || inches.isEmpty) return false;
  return _dashBakeHasStrokableGeometry(shape, geometries);
}

bool _dashBakeHasStrokableGeometry(
  VsdxShape shape,
  List<VsdxGeometry> geometries,
) {
  for (final geometry in geometries) {
    if (geometry.noShow || geometry.noLine) continue;
    final points = _strokedVertices(geometry, shape);
    if (points != null && points.length >= 2) return true;
  }
  return false;
}

/// Dash canvas / SVG paint for draw.io Flow Animation, in inches.
///
/// `User.veFlowAnimation*` rows are not tokens, and an animated connector
/// carries no dash cell of its own — canvas `_effectiveStrokeDashes` and the
/// SVG `_flowStrokePaint` both synthesise 8 CSS px of ink and gap. Draw
/// would otherwise stroke the route solid. Connectors that already dash
/// (`LinePattern` or `veDashPattern`) keep that authored pattern.
List<double>? flowAnimationDashInchesForLibvisioWrite(VsdxShape shape) {
  if (!shape.flowAnimation || !shape.supportsFlowAnimation) return null;
  if (!shape.line.hasLine) return null;
  final authored = effectiveDashPatternForLine(shape.line);
  if (authored != null && authored.isNotEmpty) return null;
  const dash = 8 * drawioDashUnitInches;
  return const <double>[dash, dash];
}

/// `true` when Flow Animation's synthetic dash must become Geometry.
bool shapeNeedsLibvisioFlowDashBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  return _flowDashCanBake(shape, shape.geometries);
}

/// `true` when `veFlowAnimation` must go to 0 so a reopen does not dash
/// already-flattened segments a second time.
///
/// Flattening either the synthesised 8 CSS-px flow dash or an authored
/// `veDashPattern` turns the route into solid MoveTo/LineTo pieces. The
/// canvas would then synthesise another 8 CSS-px array on top if the User
/// row stayed 1.
bool shapeNeedsLibvisioFlowAnimationClear(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  if (!shape.flowAnimation || !shape.supportsFlowAnimation) return false;
  return shapeNeedsLibvisioFlowDashBake(shape) ||
      shapeNeedsLibvisioCustomDashBake(shape);
}

bool _flowDashCanBake(VsdxShape shape, List<VsdxGeometry> geometries) {
  if (flowAnimationDashInchesForLibvisioWrite(shape) == null) return false;
  return _dashBakeHasStrokableGeometry(shape, geometries);
}

/// Flatten the Flow Animation dash into MoveTo/LineTo subpaths.
({List<VsdxGeometry> geometries, VsdxLine line})? bakeFlowDashForLibvisio(
  VsdxShape shape, {
  List<VsdxGeometry>? geometries,
  VsdxLine? line,
}) {
  final sourceLine = line ?? shape.line;
  final sourceGeoms = geometries ?? shape.geometries;
  if (!_flowDashCanBake(shape, sourceGeoms)) return null;
  final inches = flowAnimationDashInchesForLibvisioWrite(shape);
  if (inches == null) return null;
  final flattened = _flattenDashGeometries(shape, sourceGeoms, inches);
  if (flattened == null) return null;
  return (geometries: flattened, line: sourceLine.copyWith(pattern: 1));
}

/// Drop `User.veDashPattern` / `veFixedDash` once dashes live in Geometry,
/// write `veFlowAnimation=0` once the flow dash does, and drop
/// `User.veMiterLimit` once a tighter clip is baked as chamfers or a
/// longer spike is baked as a ribbon.
List<VsdxUserCell> userCellsForLibvisioWrite(VsdxShape shape) {
  final dropDash = shapeNeedsLibvisioCustomDashBake(shape);
  final zeroFlow = shapeNeedsLibvisioFlowAnimationClear(shape);
  final dropMiter = miterLimitForLibvisioChamfer(shape.line) != null ||
      shapeNeedsLibvisioMiterSpikeBake(shape) ||
      (shapeNeedsLibvisioFilledStrokeRibbonBake(shape) &&
          _shapeHasLibvisioMiterSpikeCorners(shape));
  if (!dropDash && !zeroFlow && !dropMiter) return shape.userCells;
  final kept = <VsdxUserCell>[
    for (final cell in shape.userCells)
      if (!(dropDash &&
              (cell.name == VsdxShape.userDashPattern ||
                  cell.name == VsdxShape.userFixedDash)) &&
          !(dropMiter && cell.name == VsdxShape.userMiterLimit) &&
          !(zeroFlow && cell.name == VsdxShape.userFlowAnimation))
        cell,
  ];
  if (!zeroFlow) return kept;
  // Re-opening must not dash the already-dashed segments a second time.
  return <VsdxUserCell>[
    ...kept,
    const VsdxUserCell(name: VsdxShape.userFlowAnimation, value: '0'),
  ];
}

/// Flatten [line]'s custom dash array into MoveTo/LineTo subpaths.
({List<VsdxGeometry> geometries, VsdxLine line})? bakeCustomDashForLibvisio(
  VsdxShape shape, {
  List<VsdxGeometry>? geometries,
  VsdxLine? line,
}) {
  final sourceLine = line ?? shape.line;
  final sourceGeoms = geometries ?? shape.geometries;
  if (!_customDashCanBake(shape, sourceLine, sourceGeoms)) return null;
  final inches = effectiveDashPatternForLine(sourceLine);
  if (inches == null || inches.isEmpty) return null;
  final flattened = _flattenDashGeometries(shape, sourceGeoms, inches);
  if (flattened == null) return null;
  return (
    geometries: flattened,
    line: sourceLine.copyWith(
      pattern: 1,
      customDashPattern: null,
      fixedDash: false,
    ),
  );
}

/// `true` when built-in LinePattern 2–23 must flatten before a stroke ribbon.
///
/// `_lineProperties` dashes those ids, but a FillForegndTrans / classic
/// gradient ribbon is a filled silhouette and cannot. Opaque dashed
/// strokes stay native.
bool shapeNeedsLibvisioLinePatternDashBake(VsdxShape shape) {
  if (_isLibvisioBakePlate(shape)) return false;
  if (!shapeNeedsLibvisioStrokeRibbon(shape)) return false;
  return _linePatternDashCanBake(shape, shape.line, shape.geometries);
}

bool _linePatternDashCanBake(
  VsdxShape shape,
  VsdxLine line,
  List<VsdxGeometry> geometries,
) {
  if (!line.hasLine) return false;
  final custom = line.customDashPattern;
  if (custom != null && custom.isNotEmpty) return false;
  if (line.pattern < 2 || line.pattern > 23) return false;
  final inches = dashPatternFor(
    line.pattern,
    weightInches: line.weightInches,
  );
  if (inches == null || inches.isEmpty) return false;
  for (final geometry in geometries) {
    if (geometry.noShow || geometry.noLine) continue;
    final points = _strokedVertices(geometry, shape);
    if (points != null && points.length >= 2) return true;
  }
  return false;
}

/// Flatten LinePattern 2–23 into MoveTo/LineTo so a later ribbon keeps gaps.
({List<VsdxGeometry> geometries, VsdxLine line})?
    bakeLinePatternDashForLibvisio(
  VsdxShape shape, {
  List<VsdxGeometry>? geometries,
  VsdxLine? line,
}) {
  final sourceLine = line ?? shape.line;
  final sourceGeoms = geometries ?? shape.geometries;
  final probe = shape.copyWith(line: sourceLine, geometries: sourceGeoms);
  if (!shapeNeedsLibvisioStrokeRibbon(probe)) return null;
  if (!_linePatternDashCanBake(shape, sourceLine, sourceGeoms)) return null;
  final inches = dashPatternFor(
    sourceLine.pattern,
    weightInches: sourceLine.weightInches,
  );
  if (inches == null || inches.isEmpty) return null;
  final flattened = _flattenDashGeometries(shape, sourceGeoms, inches);
  if (flattened == null) return null;
  return (
    geometries: flattened,
    line: sourceLine.copyWith(pattern: 1),
  );
}

List<VsdxGeometry>? _flattenDashGeometries(
  VsdxShape shape,
  List<VsdxGeometry> sourceGeoms,
  List<double> inches,
) {
  final out = <VsdxGeometry>[];
  var added = false;
  for (final geometry in sourceGeoms) {
    if (geometry.noShow || geometry.noLine) {
      out.add(geometry);
      continue;
    }
    final points = _strokedVertices(geometry, shape);
    if (points == null || points.length < 2) {
      out.add(geometry);
      continue;
    }
    final closed = polylineLooksClosed(points, noFill: geometry.noFill);
    final segments = _dashPolyline(points, inches, closed: closed);
    if (segments.isEmpty) {
      out.add(geometry);
      continue;
    }
    final dashGeoms = <VsdxGeometry>[];
    for (final segment in segments) {
      final commands = polylineCommands(segment, closed: false);
      if (commands.length < 2) continue;
      dashGeoms.add(
        VsdxGeometry(
          noFill: true,
          noLine: false,
          commands: commands,
        ),
      );
    }
    if (dashGeoms.isEmpty) {
      out.add(geometry);
      continue;
    }
    if (!geometry.noFill) {
      out.add(geometry.copyWith(noLine: true));
    }
    out.addAll(dashGeoms);
    added = true;
  }
  if (!added) return null;
  return out;
}

/// Resample [points] into dash/gap strokes. Even [pattern] slots are ink.
List<List<Offset2D>> _dashPolyline(
  List<Offset2D> points,
  List<double> pattern, {
  required bool closed,
}) {
  if (points.length < 2) return const <List<Offset2D>>[];
  var dashes = pattern;
  if (dashes.isEmpty) return <List<Offset2D>>[points];
  if (dashes.length.isOdd) {
    dashes = <double>[...dashes, ...dashes];
  }
  final cycle = dashes.fold<double>(0, (sum, value) => sum + value);
  if (cycle <= 1e-12) return <List<Offset2D>>[List<Offset2D>.of(points)];

  final ring = List<Offset2D>.of(points);
  if (closed && ring.length >= 2) {
    final a = ring.first;
    final b = ring.last;
    if ((a.x - b.x).abs() > 1e-9 || (a.y - b.y).abs() > 1e-9) {
      ring.add(a);
    }
  }

  final out = <List<Offset2D>>[];
  var patternIdx = 0;
  var draw = true;
  var remaining = dashes[0];
  List<Offset2D>? current;

  void emit() {
    if (current != null && current!.length >= 2) {
      out.add(current!);
    }
    current = null;
  }

  for (var i = 0; i < ring.length - 1; i++) {
    var ax = ring[i].x;
    var ay = ring[i].y;
    final bx = ring[i + 1].x;
    final by = ring[i + 1].y;
    final dx = bx - ax;
    final dy = by - ay;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len <= 1e-12) continue;
    final ux = dx / len;
    final uy = dy / len;
    var pos = 0.0;
    while (pos < len - 1e-12) {
      if (remaining <= 1e-12) {
        if (draw) emit();
        patternIdx = (patternIdx + 1) % dashes.length;
        draw = patternIdx.isEven;
        remaining = dashes[patternIdx];
        continue;
      }
      final take = math.min(remaining, len - pos);
      final nx = ax + ux * take;
      final ny = ay + uy * take;
      if (draw) {
        current ??= <Offset2D>[Offset2D(ax, ay)];
        current!.add(Offset2D(nx, ny));
      }
      ax = nx;
      ay = ny;
      pos += take;
      remaining -= take;
    }
  }
  if (draw) emit();
  return out;
}

/// Built-in `LinePattern` 0–23 that libvisio's `_lineProperties` switch
/// actually dashes. Custom draw.io arrays that [bakeCustomDashForLibvisio]
/// could not flatten still snap onto this table; unknown ids become solid.
int linePatternForLibvisioWrite(VsdxLine line) {
  if (line.pattern == 0) return 0;
  final custom = line.customDashPattern;
  if (custom != null && custom.isNotEmpty) {
    return nearestLibvisioLinePattern(custom);
  }
  if (line.pattern >= 1 && line.pattern <= 23) return line.pattern;
  return 1;
}

/// Fillet / chamfer radius Draw will actually paint.
///
/// Shape-level `Rounding` is not in `readShapeProperties` (only stylesheet
/// `readLine`). Explicit draw.io joins are also dropped: `_lineProperties`
/// maps join from `LineCap`, so a square/flat cap becomes a miter. Bake
/// round / arcs as RelQuadBezTo and bevel as a LineTo chamfer, at half the
/// line weight, without writing a Rounding cell Visio would apply a second
/// time on top of the geometry. An already-authored Rounding cell wins over
/// a bevel chamfer so Visio's round corners stay round.
double roundingForLibvisioWrite(VsdxLine line) {
  var radius = line.roundingInches;
  final joinRadius = (line.weightInches > 1e-9 ? line.weightInches : 0.01) / 2;
  if (line.cap == LineCap.round) {
    // Draw already round-joins a round cap. Bevel still has to be baked
    // (and the cap flattened) or Draw paints a round elbow.
    if (line.join == VsdxLineJoin.bevel && radius <= 1e-12) return joinRadius;
    if (miterLimitForLibvisioChamfer(line) != null && radius <= 1e-12) {
      return joinRadius;
    }
    return radius;
  }
  switch (line.join) {
    case VsdxLineJoin.round:
    case VsdxLineJoin.arcs:
      if (joinRadius > radius) radius = joinRadius;
    case VsdxLineJoin.bevel:
      if (radius <= 1e-12) radius = joinRadius;
    case VsdxLineJoin.miter:
    case VsdxLineJoin.miterClip:
    case null:
      if (miterLimitForLibvisioChamfer(line) != null && radius <= 1e-12) {
        radius = joinRadius;
      }
  }
  return radius;
}

/// `true` when the baked corner must be a LineTo chamfer, not RelQuadBezTo.
///
/// Bevel joins, and miter joins whose `veMiterLimit` is tighter than Draw's
/// default 4, when there is no shape-level Rounding (that cell still means
/// a Visio fillet). Round / arcs keep the quadratic. A round cap is
/// flattened to LineCap.extended on write so Draw does not round the
/// chamfer (`_lineProperties` join comes from LineCap only).
bool chamferForLibvisioWrite(VsdxLine line) =>
    line.roundingInches <= 1e-12 &&
    (line.join == VsdxLineJoin.bevel ||
        miterLimitForLibvisioChamfer(line) != null);

bool _lineUsesMiterJoin(VsdxLine line) {
  if (line.join == VsdxLineJoin.round ||
      line.join == VsdxLineJoin.arcs ||
      line.join == VsdxLineJoin.bevel) {
    return false;
  }
  if (line.cap == LineCap.round && line.join == null) return false;
  final join = line.effectiveJoin;
  return join == VsdxLineJoin.miter || join == VsdxLineJoin.miterClip;
}

/// Tighter-than-Draw miter clip that must become LineTo chamfers.
///
/// `_lineProperties` never emits `svg:stroke-miterlimit`; ODF/Draw default
/// to 4. Limits at or above 4 match that default and stay native. `null`
/// means leave the polyline's corners alone.
double? miterLimitForLibvisioChamfer(VsdxLine line) {
  if (!line.hasLine) return null;
  if (line.roundingInches > 1e-12) return null;
  if (!_lineUsesMiterJoin(line)) return null;
  if (line.miterLimit >= 4.0 - 1e-6) return null;
  return line.miterLimit.clamp(1.0, 4.0);
}

/// Closest of libvisio's dash ids 2–23 for a draw.io / custom array.
int nearestLibvisioLinePattern(List<double> custom) {
  var best = 2;
  var bestScore = double.infinity;
  for (var id = 2; id <= 23; id++) {
    final built = dashPatternFor(id, weightInches: 1);
    if (built == null) continue;
    final score = _dashDistance(custom, built);
    if (score < bestScore) {
      bestScore = score;
      best = id;
    }
  }
  return best;
}

/// First authored stop colour, used when Draw cannot collect LineGradient.
VsdxColor? lineColorForLibvisioWrite(VsdxLine line) {
  if (line.color != null) return line.color;
  if (line.themeColorIndex != null) return null;
  final gradient = line.gradient;
  if (gradient == null) return null;
  for (final stop in gradient.stops) {
    if (stop.color != null) return stop.color;
  }
  return null;
}

List<VsdxPathCommand> polylineCommands(
  List<Offset2D> points, {
  required bool closed,
}) {
  if (points.isEmpty) return const <VsdxPathCommand>[];
  var ring = List<Offset2D>.of(points);
  if (closed && ring.length >= 2) {
    final a = ring.first;
    final b = ring.last;
    if ((a.x - b.x).abs() < 1e-9 && (a.y - b.y).abs() < 1e-9) {
      ring = ring.sublist(0, ring.length - 1);
    }
  }
  if (ring.isEmpty) return const <VsdxPathCommand>[];
  final commands = <VsdxPathCommand>[
    MoveTo(ring.first.x, ring.first.y),
    for (var i = 1; i < ring.length; i++) LineTo(ring[i].x, ring[i].y),
  ];
  if (closed) {
    commands.add(LineTo(ring.first.x, ring.first.y));
  }
  return commands;
}

double _dashDistance(List<double> a, List<double> b) {
  if (a.length == b.length) {
    var sum = 0.0;
    for (var i = 0; i < a.length; i++) {
      final d = a[i] - b[i];
      sum += d * d;
    }
    return sum;
  }
  final na = _normalizedDash(a);
  final nb = _normalizedDash(b);
  final n = na.length < nb.length ? na.length : nb.length;
  var sum = (na.length - nb.length).abs() * 4.0;
  for (var i = 0; i < n; i++) {
    final d = na[i] - nb[i];
    sum += d * d;
  }
  return sum;
}

List<double> _normalizedDash(List<double> values) {
  var max = 0.0;
  for (final value in values) {
    if (value > max) max = value;
  }
  if (max < 1e-12) return values;
  return <double>[for (final value in values) value / max];
}

/// Shared Character Highlight of every non-empty run, or `null` if mixed / absent.
VsdxColor? uniformCharacterHighlight(VsdxShape shape) {
  VsdxColor? highlight;
  var sawText = false;
  for (final run in shape.richText.runs) {
    if (run.text.trim().isEmpty) continue;
    sawText = true;
    final color = run.charStyle.highlight;
    if (color == null) return null;
    if (highlight == null) {
      highlight = color;
    } else if (highlight.value != color.value) {
      return null;
    }
  }
  if (sawText) return highlight;
  final plain = shape.text?.trim() ?? '';
  if (plain.isEmpty || shape.richText.runs.isEmpty) return null;
  return shape.richText.runs.first.charStyle.highlight;
}

/// `true` when Character Highlight must be written as TextBkgnd for Draw.
///
/// `readCharIX` has `case XML_HIGHLIGHT: break;`. `TextBkgnd` is a token
/// `VSDContentCollector` paints as span `fo:background-color`. Skip when the
/// block already has a fill — that cell is the user's text-block colour.
bool shapeNeedsLibvisioTextBkgndBake(VsdxShape shape) {
  final block = shape.richText.textBlock;
  if (block.hideText) return false;
  if (block.backgroundColor != null) return false;
  return uniformCharacterHighlight(shape) != null;
}

/// `true` when TextBkgnd / Highlight cells must be rewritten for Draw.
///
/// `TextBkgndTrans` is in `tokens.txt` but `readShapeProperties` has no
/// case for it, and `xmlStringToColour` stores Colour.a = 0, so a
/// semi-transparent plate becomes opaque in Draw unless the RGB is
/// premultiplied and Trans is written 0.
bool shapeNeedsLibvisioTextBlockBake(VsdxShape shape) {
  if (shapeNeedsLibvisioTextBkgndBake(shape)) return true;
  final block = shape.richText.textBlock;
  if (block.hideText) return false;
  return block.backgroundColor != null && block.backgroundTransparency > 1e-9;
}

/// Text block cells the writer should emit so Draw paints Highlight / Trans.
VsdxTextBlock textBlockForLibvisioWrite(VsdxShape shape) {
  var block = shape.richText.textBlock;
  if (shapeNeedsLibvisioTextBkgndBake(shape)) {
    block = block.copyWith(backgroundColor: uniformCharacterHighlight(shape));
  }
  if (block.backgroundColor != null && block.backgroundTransparency > 1e-9) {
    block = block.copyWith(
      backgroundColor: colourForLibvisioAlpha(
        block.backgroundColor!,
        block.backgroundTransparency,
      ),
      backgroundTransparency: 0,
    );
  }
  return block;
}

/// Character Highlight to paint here. `null` when a save already inserted
/// per-run FillForegnd siblings, so canvas / SVG do not stack a second halo.
VsdxColor? characterHighlightForPaint(
  VsdxTextRun run, {
  VsdxShape? shape,
  VsdxPage? page,
}) {
  final highlight = run.charStyle.highlight;
  if (highlight == null) return null;
  if (shape != null &&
      page != null &&
      pageHasLibvisioHighlightPlate(page, shape.id)) {
    return null;
  }
  return highlight;
}

/// TextBkgnd to paint here. `null` when it is only the LibreOffice stand-in
/// for Character Highlight, so canvas / SVG keep the tighter highlight halo.
VsdxColor? textBlockBackgroundForPaint(VsdxShape shape) {
  final background = shape.richText.textBlock.backgroundColor;
  if (background == null) return null;
  final highlight = uniformCharacterHighlight(shape);
  if (highlight != null && highlight.value == background.value) return null;
  return background;
}

/// [VsdxShape.richText] text block with a Highlight-stand-in TextBkgnd cleared.
VsdxTextBlock textBlockForPaint(VsdxShape shape) {
  final block = shape.richText.textBlock;
  if (textBlockBackgroundForPaint(shape) != null ||
      block.backgroundColor == null) {
    return block;
  }
  return block.withoutBackgroundColor();
}

/// Fill cells Draw will collect. `FillForegndTrans` / `FillBkgndTrans`
/// *are* tokens, so transparency stays. Theme-only FillForegnd /
/// FillBkgnd still have to freeze into RGB because
/// `VSDXTheme::getThemeColour` only maps 0–8 (dk1/lt1/accent1–6/bkgnd)
/// and `VSDFillStyle::override` applies explicit FillForegnd after the
/// theme — THEMEVAL() plus `QuickStyleFillColor=9` paints faded black,
/// while canvas already multiplies `_colourOrTheme` by
/// (1 − FillForegndTrans). Theme-bound colours with no transparency
/// still keep THEMEVAL().
VsdxFill fillThemeTransForLibvisioWrite(
  VsdxFill fill, [
  VsdxTheme theme = VsdxTheme.empty,
]) {
  final fgTrans = fill.foregroundTransparency > 1e-9;
  final bgTrans = fill.backgroundTransparency > 1e-9;
  if (!fgTrans && !bgTrans) return fill;

  var foreground = fill.foreground;
  var background = fill.background;
  var clearFg = false;
  var clearBg = false;
  if (fgTrans && foreground == null && fill.themeForegroundIndex != null) {
    foreground = _fillRgbForLibvisioWrite(fill, theme);
    clearFg = true;
  }
  if (bgTrans && background == null && fill.themeBackgroundIndex != null) {
    final resolved = _fillBackgroundRgbForLibvisioWrite(fill, theme);
    if (resolved != null) {
      background = resolved;
      clearBg = true;
    }
  }
  if (!clearFg && !clearBg) return fill;
  return fill.copyWith(
    foreground: foreground,
    background: background,
    clearThemeForegroundIndex: clearFg,
    clearThemeBackgroundIndex: clearBg,
  );
}

/// RGB Draw will paint when libvisio strips alpha (`xmlStringToColour`
/// always stores Colour.a = 0, and ColorTrans / LineColorTrans /
/// ShdwForegndTrans are not tokens). Blends [foreground] toward white.
VsdxColor colourForLibvisioAlpha(VsdxColor foreground, double transparency) {
  final t = transparency.clamp(0.0, 1.0);
  if (t <= 1e-9) return foreground;
  int mix(int channel) => (channel * (1 - t) + 255 * t).round().clamp(0, 255);
  return VsdxColor.argb(
    0xFF,
    mix(foreground.red),
    mix(foreground.green),
    mix(foreground.blue),
  );
}

/// RGB canvas `_colourOrTheme` would paint for a character run.
VsdxColor? _charRgbForLibvisioWrite(
  VsdxCharStyle style, [
  VsdxTheme theme = VsdxTheme.empty,
]) {
  if (style.color != null) return style.color;
  final slot = style.themeColorIndex;
  if (slot == null) return null;
  return theme.resolve(slot) ?? VsdxTheme.office.resolve(slot);
}

/// `Color` cell Draw will collect. Character ColorTrans is not a token.
///
/// Theme-only Color still has to freeze into this RGB blend because
/// `readCharIX` never stores ColorTrans — Draw would otherwise paint
/// THEMEVAL() fully opaque, while canvas already multiplies
/// `_colourOrTheme` by (1 − ColorTrans).
VsdxColor? charColorForLibvisioWrite(
  VsdxCharStyle style, [
  VsdxTheme theme = VsdxTheme.empty,
]) {
  if (style.transparency <= 1e-9) return style.color;
  final color = _charRgbForLibvisioWrite(style, theme);
  if (color == null && style.themeColorIndex != null) return style.color;
  return colourForLibvisioAlpha(
    color ?? const VsdxColor(0xFF000000),
    style.transparency,
  );
}

/// `ColorTrans` cell. Zeroed when [charColorForLibvisioWrite] baked alpha
/// into RGB so Visio does not fade the already-blended colour a second time.
double charTransparencyForLibvisioWrite(
  VsdxCharStyle style, [
  VsdxTheme theme = VsdxTheme.empty,
]) {
  if (style.transparency <= 1e-9) return style.transparency;
  if (charColorForLibvisioWrite(style, theme) == null) {
    return style.transparency;
  }
  return 0;
}

/// Theme slot still written as THEMEVAL() after [charColorForLibvisioWrite].
///
/// A ColorTrans bake emits hex Color, so the slot must not survive as
/// THEMEVAL() or Draw would ignore the faded RGB.
int? charThemeColorIndexForLibvisioWrite(
  VsdxCharStyle style, [
  VsdxTheme theme = VsdxTheme.empty,
]) {
  if (charColorForLibvisioWrite(style, theme) != null) return null;
  return style.themeColorIndex;
}

/// `ShdwForegnd` / `ShdwForegndTrans` Draw will collect. Shadow alpha is
/// `shadowFgColour.a`, which VSDX `xmlStringToColour` forces to 0.
///
/// Theme-only Color still has to freeze into this RGB blend when the
/// edge is hard: `ShdwForegndTrans` is not a token, so Draw would
/// paint THEMEVAL() fully opaque, while canvas already multiplies
/// `_colourOrTheme` by (1 − ShdwForegndTrans). Soft theme shadows keep
/// THEMEVAL() on the leftover after the Gaussian PNG bake.
VsdxShadow shadowForLibvisioWrite(
  VsdxShadow shadow, [
  VsdxTheme theme = VsdxTheme.empty,
]) {
  if (!shadow.enabled || shadow.transparency <= 1e-9) {
    return shadow;
  }
  if (shadow.color == null && shadow.themeColorIndex != null) {
    if (shadow.blurInches > 1e-6) return shadow;
    return shadow.copyWith(
      color: colourForLibvisioAlpha(
        _shadowRgbForLibvisioWrite(shadow, theme),
        shadow.transparency,
      ),
      transparency: 0,
      clearThemeColorIndex: true,
    );
  }
  return shadow.copyWith(
    color: colourForLibvisioAlpha(
      shadow.color ?? const VsdxColor(0xFF000000),
      shadow.transparency,
    ),
    transparency: 0,
    clearThemeColorIndex: true,
  );
}

/// Every shadow cell Draw will collect for [shape].
///
/// Adds the shape-level half [shadowForLibvisioWrite] cannot see: `ShdwPattern`
/// and `ShadowBlur` go to 0 once a Gaussian PNG sibling carries the blur, so
/// Draw does not add a second hard copy. Mirrors
/// [reflectionForLibvisioWrite].
VsdxShadow shadowCellsForLibvisioWrite(VsdxShape shape) {
  final shadow = shadowForLibvisioWrite(shape.shadow);
  if (!shapeNeedsLibvisioShadowBake(shape)) return shadow;
  return shadow.copyWith(enabled: false, blurInches: 0);
}

/// Layer `Color` / `ColorTrans` Draw will collect.
///
/// `readLayerIX` stores `Color` and skips `ColorTrans` (not a token).
/// `xmlStringToColour` also forces Colour.a = 0. A tint with no RGB is
/// left alone.
VsdxLayer layerForLibvisioWrite(VsdxLayer layer) {
  if (layer.color == null || layer.colorTrans <= 1e-9) return layer;
  return layer.copyWith(
    color: colourForLibvisioAlpha(layer.color!, layer.colorTrans),
    colorTrans: 0,
  );
}

/// Face libvisio's `readCharIX` will actually load (`tokens.txt` has `Font`,
/// not `AsianFont` / `ComplexScriptFont`).
const kLibvisioDefaultAsianFont = 'Microsoft YaHei';

bool _isLatinLetterRune(int rune) =>
    (rune >= 0x41 && rune <= 0x5A) || (rune >= 0x61 && rune <= 0x7A);

/// Han / Kana / Hangul / Bopomofo with no Latin or complex-script letters.
bool _isAsianOnly(String text) {
  var hasAsian = false;
  for (final rune in text.runes) {
    if (isVisioAsianScriptRune(rune)) {
      hasAsian = true;
      continue;
    }
    if (isVisioComplexScriptRune(rune) || _isLatinLetterRune(rune)) {
      return false;
    }
  }
  return hasAsian;
}

/// Arabic / Hebrew / Indic / … with no Latin or East-Asian letters.
bool _isComplexScriptOnly(String text) {
  var hasComplex = false;
  for (final rune in text.runes) {
    if (isVisioComplexScriptRune(rune)) {
      hasComplex = true;
      continue;
    }
    if (isVisioAsianScriptRune(rune) || _isLatinLetterRune(rune)) {
      return false;
    }
  }
  return hasComplex;
}

bool _isLatinUiFace(String? face) {
  if (face == null || face.isEmpty) return true;
  switch (face.toLowerCase()) {
    case 'arial':
    case 'calibri':
    case 'cambria':
    case 'candara':
    case 'consolas':
    case 'constantia':
    case 'corbel':
    case 'courier new':
    case 'georgia':
    case 'helvetica':
    case 'segoe ui':
    case 'tahoma':
    case 'times':
    case 'times new roman':
    case 'trebuchet ms':
    case 'verdana':
      return true;
    default:
      return false;
  }
}

/// `Font` cell Draw will collect. Asian-only runs whose Visio `Font` is a
/// Latin UI face are rewritten to `AsianFont` (or YaHei); complex-script-only
/// runs use `ComplexScriptFont`. Mixed Latin+CJK / Latin+Arabic keep `Font`
/// so Visio's Latin glyphs do not change face.
String? fontFamilyForLibvisioWrite(VsdxCharStyle style, String text) {
  final current = style.fontFamily;
  if (_isAsianOnly(text)) {
    final asian = style.asianFont?.trim();
    if (asian != null && asian.isNotEmpty) return asian;
    if (_isLatinUiFace(current)) return kLibvisioDefaultAsianFont;
    return current;
  }
  if (_isComplexScriptOnly(text)) {
    final complex = style.complexScriptFont?.trim();
    if (complex != null && complex.isNotEmpty) return complex;
  }
  return current;
}

/// `Size` cell Draw will collect. `ComplexScriptSize` is not a token, so a
/// complex-script-only run writes that size into `Size`. Mixed runs keep
/// `Size` so Latin glyphs do not jump.
double fontSizeForLibvisioWrite(VsdxCharStyle style, String text) {
  final complex = style.complexScriptSizeInches;
  if (complex != null &&
      _isComplexScriptOnly(text) &&
      (complex - style.fontSizeInches).abs() > 1e-12) {
    return complex;
  }
  return style.fontSizeInches;
}

/// Mean Latin advance used by canvas / SVG to fold FontScale into tracking.
///
/// `_drawText` and `svg_serializer` add `Size * (FontScale-1) * 0.55` to
/// letter-spacing. Baking the inverse into FontScale keeps that appearance
/// here after reopen; Draw collects FontScale (`style:text-scale`) and
/// ignores Letterspace.
const kLibvisioMeanLatinAdvance = 0.55;

/// `FontScale` Draw will collect. Letterspace is not a token, so extra
/// tracking is folded into this scale with [kLibvisioMeanLatinAdvance].
/// Super/subscript use the same 0.7× Size canvas and SVG apply before
/// adding FontScale tracking.
double fontScaleForLibvisioWrite(VsdxCharStyle style, [String text = '']) {
  var fs = fontSizeForLibvisioWrite(style, text);
  switch (style.position) {
    case VsdxTextPosition.superscript:
    case VsdxTextPosition.subscript:
      fs *= 0.7;
    case VsdxTextPosition.normal:
      break;
  }
  var scale = style.fontScale;
  if (style.letterSpacingInches.abs() > 1e-12 && fs > 1e-9) {
    scale += style.letterSpacingInches / (fs * kLibvisioMeanLatinAdvance);
  }
  return scale;
}

/// `Letterspace` cell. Zeroed when [fontScaleForLibvisioWrite] absorbed it.
double letterSpacingForLibvisioWrite(VsdxCharStyle style, [String text = '']) {
  if ((fontScaleForLibvisioWrite(style, text) - style.fontScale).abs() >
      1e-12) {
    return 0;
  }
  return style.letterSpacingInches;
}

bool shapeNeedsLibvisioFontBake(VsdxShape shape) {
  if (shape.richText.textBlock.hideText) return false;
  for (final run in shape.richText.runs) {
    if (run.text.trim().isEmpty) continue;
    final baked = fontFamilyForLibvisioWrite(run.charStyle, run.text);
    final current = run.charStyle.fontFamily;
    if ((baked ?? '') != (current ?? '')) return true;
    if ((fontSizeForLibvisioWrite(run.charStyle, run.text) -
                run.charStyle.fontSizeInches)
            .abs() >
        1e-12) {
      return true;
    }
    if (charTransparencyForLibvisioWrite(run.charStyle) !=
        run.charStyle.transparency) {
      return true;
    }
    if ((fontScaleForLibvisioWrite(run.charStyle, run.text) -
                run.charStyle.fontScale)
            .abs() >
        1e-12) {
      return true;
    }
    if ((letterSpacingForLibvisioWrite(run.charStyle, run.text) -
                run.charStyle.letterSpacingInches)
            .abs() >
        1e-12) {
      return true;
    }
  }
  return false;
}
