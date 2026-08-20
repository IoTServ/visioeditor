/// Rewrite shape line appearance into cells / rows libvisio still collects.
///
/// LibreOffice Draw never reads Visio XML itself — `VisioImportFilter.cxx`
/// only calls `VisioDocument::isSupported` + `parse`. The VSDX token map has
/// no `CompoundType` and no `LineGradient`, `LineColorTrans` is absent and
/// `xmlStringToColour` forces Colour.a = 0, and unknown `LinePattern` ids
/// (custom draw.io arrays, 0xFE, …) fall through `_lineProperties` to a solid
/// stroke. A save therefore has to emit parallel Geometry rails, a built-in
/// pattern 2–23, and — for an unfilled stroke with a line gradient or
/// LineColorTrans — a filled ribbon whose FillPattern 25–40 / FillForegndTrans
/// libvisio *does* collect. Unfilled CompoundType 2–4 keep thick/thin contrast
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
/// text-block fill is written there. `TextBkgndTrans` and layer
/// `ColorTrans` have no VSDX collector case (`xmlStringToColour` also
/// zeros alpha), so a save premultiplies those into RGB toward white.
/// `AsianFont` / `ComplexScriptFont` / `ComplexScriptSize` are not tokens —
/// `readCharIX` only stores `Font` and `Size` — so an Asian-only (or
/// complex-script-only) run whose Latin `Font` would tofu in Draw is
/// rewritten to the Asian / complex face, and a complex-only run writes
/// `ComplexScriptSize` into `Size`. `_lineProperties` derives `stroke-linejoin`
/// from `LineCap` only (round cap → round join, otherwise miter), so an
/// explicit round / arcs join on a square/flat cap is baked with the same
/// RelQuadBezTo fillets as shape-level Rounding, and a bevel join becomes a
/// LineTo chamfer (including when the cap is round: Draw would otherwise
/// round the elbow, so the written LineCap is flattened to extended). The
/// Rounding cell stays 0 so Visio does not restroke. Character ColorTrans,
/// filled-shape LineColorTrans, and ShdwForegndTrans are not tokens —
/// `xmlStringToColour` also forces Colour.a = 0 — so a save premultiplies
/// those into RGB toward white and writes Trans=0. Theme-bound colours
/// with no resolved RGB are left alone so THEMEVAL() survives. Page
/// `ConLineJump*` cells are not tokens either, so a save bakes hops as
/// ArcTo / MoveTo / LineTo and writes `ConLineJumpCode=1`. Image
/// Transparency / Brightness / Contrast / Blur are likewise missing;
/// a save bakes them into a PNG and zeros the cells. Picture `SoftEdgesSize`
/// is not a token either: an uncropped 2-D Foreign bitmap bakes the same
/// SourceAlpha feather canvas / SVG use, then SoftEdgesSize is written 0.
/// Cropped pictures keep the cell — feathering the PNG would miss the
/// ImgOffset frame Draw still collects. Character Overline
/// is a token whose `readCharIX` case is empty, so a save inserts U+0305
/// combining overlines and clears the cell. Glow* cells are not tokens;
/// an unfilled stroke bakes a FillForegndTrans ribbon and a filled
/// NoLine shape bakes a LineWeight halo, then GlowSize is written 0.
/// Filled shapes that already paint a stroke keep their outline — stealing
/// Line would drop CompoundType / dashes that Draw *does* collect.
/// `Letterspace` is not a token; canvas / SVG already fold FontScale into
/// tracking at 0.55×Size, and `readCharIX` *does* collect FontScale as
/// `style:text-scale`, so a save adds Letterspace into FontScale and
/// writes Letterspace 0. Page `PageColor` is not a token either
/// (`readPageSheetProperties` only stores size, scale, and ShdwOffset*) —
/// a save prepends a locked full-page plate so Draw paints the sheet.
/// `Reflection*` cells are likewise missing from `tokens.txt`, so a filled
/// 2-D shape bakes a locked sibling plate whose FillForegndTrans Draw
/// collects, then `ReflectionSize` is written 0.
library;

import 'dart:math' as math;

import '../export/compound_stroke.dart';
import '../export/line_jumps.dart';
import '../utils/color.dart';
import 'dash_pattern.dart';
import 'document.dart';
import 'effects.dart';
import 'fill.dart';
import 'geometry.dart';
import 'image.dart';
import 'layer.dart';
import 'line.dart';
import 'page.dart';
import 'perimeter.dart';
import 'rich_text.dart';
import 'rounding.dart';
import 'shape.dart';
import 'shape_factory.dart';

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
    bakeImageAdjustmentsForLibvisioWrite(
      bakeReflectionForLibvisioWrite(
        bakeOverlineForLibvisioWrite(hopped),
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
  final existing = page.shapes
      .where((s) => s.name == kLibvisioPageColorShapeName)
      .toList();
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
/// LibreOffice only sees Fill / Line / Geometry, so a filled 2-D leaf bakes a
/// NoLine sibling (FillForegndTrans is a token) and the live cells go to 0.
bool shapeNeedsLibvisioReflectionBake(VsdxShape shape) {
  if (isLibvisioReflectionPlate(shape)) return false;
  if (shape.is1D) return false;
  final reflection = shape.reflection;
  if (!reflection.enabled || reflection.sizeInches <= 1e-12) return false;
  if (reflection.transparency >= 1 - 1e-9) return false;
  if (shape.width.abs() <= 1e-9 || shape.height.abs() <= 1e-9) return false;
  return _shapePaintsFill(shape, shape.geometries);
}

VsdxShape _reflectionPlateForLibvisioWrite(VsdxShape source, {required int id}) {
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
      );
      if (!identical(children, shape.children)) {
        next = shape.copyWith(children: children);
        changed = true;
      }
    }
    if (shapeNeedsLibvisioReflectionBake(next)) {
      final plate = _reflectionPlateForLibvisioWrite(
        next,
        id: plateIds[next.id] ?? nextId(),
      );
      if (plate.geometries.isNotEmpty) {
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

VsdxPage bakeReflectionPageForLibvisioWrite(VsdxPage page) {
  if (!pageNeedsLibvisioReflectionBake(page)) return page;
  final plateIds = <int, int>{};
  _collectReflectionPlateIds(page.shapes, plateIds);
  var nextId = _maxShapeId(page.shapes) + 1;
  return page.copyWith(
    shapes: _bakeReflectionTree(
      page.shapes,
      plateIds: plateIds,
      nextId: () => nextId++,
    ),
  );
}

/// Insert (or strip) the sibling plates Draw uses in place of `Reflection*`.
VsdxDocument bakeReflectionForLibvisioWrite(VsdxDocument document) {
  if (document.pages.isEmpty) return document;
  final pages = <VsdxPage>[];
  var changed = false;
  for (final page in document.pages) {
    final next = bakeReflectionPageForLibvisioWrite(page);
    changed |= !identical(next, page);
    pages.add(next);
  }
  return changed ? document.copyWith(pages: pages) : document;
}

/// Cells Draw will collect. Size is 0 after a sibling-plate bake.
VsdxReflection reflectionForLibvisioWrite(VsdxShape shape) {
  if (!shapeNeedsLibvisioReflectionBake(shape)) return shape.reflection;
  return shape.reflection.copyWith(enabled: false, sizeInches: 0);
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

/// SoftEdgesSize Draw will collect for this picture (0 = do not bake).
///
/// Canvas / SVG feather the Foreign frame. Img* crop cells *are* tokens, so
/// a cropped bitmap must keep its pixels; only an uncropped 2-D picture can
/// bake the halo into PNG alpha.
double imageSoftEdgesInchesForLibvisioWrite(VsdxShape shape) {
  if (!shape.hasImage || shape.is1D) return 0;
  if (shape.imgOffsetXInches.abs() > 1e-6) return 0;
  if (shape.imgOffsetYInches.abs() > 1e-6) return 0;
  if (shape.imgWidthInches != null &&
      (shape.imgWidthInches! - shape.width).abs() > 1e-6) {
    return 0;
  }
  if (shape.imgHeightInches != null &&
      (shape.imgHeightInches! - shape.height).abs() > 1e-6) {
    return 0;
  }
  return shape.line.softEdgesInches;
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
            '${shape.effectiveImgWidth}';
        var bakedPart = cache[key];
        if (bakedPart == null) {
          final png = bakeVisioImageAdjustmentsPng(
            image: source,
            transparency: shape.imageTransparency,
            blur: shape.imageBlur,
            brightness: shape.imageBrightness,
            contrast: shape.imageContrast,
            displayWidthInches: shape.effectiveImgWidth,
            softEdgesInches: soft,
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
LibvisioShapeWrite libvisioShapeWrite(VsdxShape shape) {
  var geometries = shape.geometries;
  var line = shape.line;
  var fill = shape.fill;
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
        foreground: line.color ?? const VsdxColor(0xFF000000),
        pattern: 1,
        themeForegroundIndex: line.color == null ? line.themeColorIndex : null,
        foregroundTransparency: line.transparency.clamp(0.0, 1.0),
      );
    }
    line = line.copyWith(beginArrow: 0, endArrow: 0);
  }

  final sourceLine = shape.line;
  if (roundingForLibvisioWrite(sourceLine) > 1e-12) {
    line = line.copyWith(roundingInches: 0);
  }
  if (chamferForLibvisioWrite(sourceLine) && sourceLine.cap == LineCap.round) {
    line = line.copyWith(cap: LineCap.extended);
  }
  if (line.transparency > 1e-9 &&
      (line.color != null || line.themeColorIndex == null)) {
    line = line.copyWith(
      color: colourForLibvisioAlpha(
        line.color ?? const VsdxColor(0xFF000000),
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
  );
  if (glow != null) {
    geometries = glow.geometries;
    line = glow.line;
    fill = glow.fill;
    geometryRewritten = true;
  }

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

VsdxFill _glowFillForLibvisio(VsdxGlow glow) {
  final trans = _glowHaloTransparency(glow);
  return VsdxFill(
    foreground: glow.color ??
        (glow.themeColorIndex == null ? _kLibvisioGlowFallback : null),
    pattern: 1,
    themeForegroundIndex: glow.color == null ? glow.themeColorIndex : null,
    foregroundTransparency: trans,
  );
}

VsdxLine _glowLineForLibvisio(VsdxLine line, VsdxGlow glow) {
  final weight = math.max(glow.sizeInches * 2, 0.02);
  if (glow.color == null && glow.themeColorIndex != null) {
    return line.withThemeColor(glow.themeColorIndex!).copyWith(
          weightInches: weight,
          pattern: 1,
          transparency: 0,
          cap: LineCap.round,
        );
  }
  return line.copyWith(
    color: colourForLibvisioAlpha(
      glow.color ?? _kLibvisioGlowFallback,
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
/// CompoundType / dashes. Unfilled strokes become a FillForegndTrans
/// ribbon (FillTrans is a token); filled NoLine / pictures become a
/// LineWeight halo (`xmlStringToColour` zeros LineColorTrans, so RGB is
/// premultiplied toward white).
bool shapeNeedsLibvisioGlowBake(VsdxShape shape) {
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
  if (!shapeNeedsLibvisioGlowBake(shape)) return shape.glow;
  return shape.glow.copyWith(enabled: false, sizeInches: 0);
}

({List<VsdxGeometry> geometries, VsdxLine line, VsdxFill fill})?
    bakeGlowForLibvisio({
  required VsdxShape shape,
  required List<VsdxGeometry> geometries,
  required VsdxLine line,
  required VsdxFill fill,
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
      return (geometries: out, line: line, fill: _glowFillForLibvisio(glow));
    }
    if (!paintsLine) {
      return (
        geometries: geometries,
        line: _glowLineForLibvisio(line, glow),
        fill: fill,
      );
    }
    return null;
  }
  if (!paintsLine) {
    return (
      geometries: geometries,
      line: _glowLineForLibvisio(line, glow),
      fill: fill,
    );
  }
  return null;
}

bool _hasArrowheads(VsdxLine line) =>
    line.beginArrow != 0 || line.endArrow != 0;

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
/// ribbon cannot carry shape-level markers. `tokens.txt` also has no
/// BeginArrowSize cell — marker width follows line weight — so baking the
/// polygon at [VsdxLine.beginArrowSizeInches] is the size Draw will paint.
bool shapeNeedsLibvisioArrowedStrokeBake(VsdxShape shape) {
  if (!_hasArrowheads(shape.line)) return false;
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
    final fill = _fillFromLineStroke(shape.line) ??
        VsdxFill(
          foreground: shape.line.color ?? const VsdxColor(0xFF000000),
          background: shape.line.color ?? const VsdxColor(0xFF000000),
          pattern: 1,
          themeForegroundIndex:
              shape.line.color == null ? shape.line.themeColorIndex : null,
        );
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
/// show an opaque stroke).
bool shapeNeedsLibvisioStrokeRibbon(VsdxShape shape) {
  if (_hasArrowheads(shape.line)) return false;
  if (!shape.line.hasLine) return false;
  if (!shape.line.hasGradient && shape.line.transparency <= 1e-9) {
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

/// Expand an unfilled gradient or transparent stroke into a closed ribbon
/// FillPattern 25–40 / FillForegndTrans can paint. Compound rails, when
/// present, are expanded one by one.
({List<VsdxGeometry> geometries, VsdxLine line, VsdxFill fill})?
    bakeStrokeRibbonForLibvisio({
  required VsdxShape shape,
  required List<VsdxGeometry> geometries,
  required VsdxLine line,
}) {
  if (!shapeNeedsLibvisioStrokeRibbon(shape)) return null;
  if (!line.hasLine) return null;
  final fill = _fillFromLineStroke(line);
  if (fill == null) return null;

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

VsdxFill? _fillFromLineStroke(VsdxLine line) {
  final transparency = line.transparency.clamp(0.0, 1.0);
  if (line.hasGradient) {
    final gradient = line.gradient!;
    VsdxColor? first;
    VsdxColor? last;
    for (final stop in gradient.stops) {
      if (stop.color != null) {
        first ??= stop.color;
        last = stop.color;
      }
    }
    first ??= line.color ?? const VsdxColor(0xFF000000);
    last ??= first;
    return VsdxFill(
      foreground: first,
      background: last,
      pattern: 1,
      gradient: gradient,
      foregroundTransparency: transparency,
      backgroundTransparency: transparency,
    );
  }
  if (transparency <= 1e-9) return null;
  return VsdxFill(
    foreground: line.color ?? const VsdxColor(0xFF000000),
    background: line.color ?? const VsdxColor(0xFF000000),
    pattern: 1,
    themeForegroundIndex: line.color == null ? line.themeColorIndex : null,
    foregroundTransparency: transparency,
    backgroundTransparency: transparency,
  );
}

/// Closed polygon covering a stroked polyline, used as a filled ribbon.
List<VsdxPathCommand> strokeRibbonCommands(
  List<Offset2D> points, {
  required double halfWidth,
  required bool closed,
}) {
  final left = offsetPolyline(points, halfWidth, closed: closed);
  final right = offsetPolyline(points, -halfWidth, closed: closed);
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

/// Built-in `LinePattern` 0–23 that libvisio's `_lineProperties` switch
/// actually dashes. Custom draw.io arrays and unknown ids become solid in
/// Draw unless they snap to this table.
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
      break;
  }
  return radius;
}

/// `true` when the baked corner must be a LineTo chamfer, not RelQuadBezTo.
///
/// Only bevel, and only when there is no shape-level Rounding (that cell
/// still means a Visio fillet). Round / arcs keep the quadratic. A round
/// cap is flattened to LineCap.extended on write so Draw does not round
/// the chamfer (`_lineProperties` join comes from LineCap only).
bool chamferForLibvisioWrite(VsdxLine line) =>
    line.roundingInches <= 1e-12 && line.join == VsdxLineJoin.bevel;

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

/// `Color` cell Draw will collect. Character ColorTrans is not a token.
VsdxColor? charColorForLibvisioWrite(VsdxCharStyle style) {
  if (style.transparency <= 1e-9) return style.color;
  if (style.color == null && style.themeColorIndex != null) return style.color;
  return colourForLibvisioAlpha(
    style.color ?? const VsdxColor(0xFF000000),
    style.transparency,
  );
}

/// `ColorTrans` cell. Zeroed when [charColorForLibvisioWrite] baked alpha
/// into RGB so Visio does not fade the already-blended colour a second time.
double charTransparencyForLibvisioWrite(VsdxCharStyle style) {
  if (style.transparency <= 1e-9) return style.transparency;
  if (style.color == null && style.themeColorIndex != null) {
    return style.transparency;
  }
  return 0;
}

/// `ShdwForegnd` / `ShdwForegndTrans` Draw will collect. Shadow alpha is
/// `shadowFgColour.a`, which VSDX `xmlStringToColour` forces to 0.
VsdxShadow shadowForLibvisioWrite(VsdxShadow shadow) {
  if (!shadow.enabled ||
      shadow.transparency <= 1e-9 ||
      (shadow.color == null && shadow.themeColorIndex != null)) {
    return shadow;
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
