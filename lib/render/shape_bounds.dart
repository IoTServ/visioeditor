/// Compute axis-aligned bounding boxes for shapes.
///
/// Used by:
///   * `VsdxPainter` for viewport culling.
///   * Hit-testing fast path (broad-phase before the precise XForm test).
///   * Outline / search panels highlighting which shapes are on screen.
library;

import 'dart:math' as math;
import 'dart:ui' show Rect, Offset;

import 'package:vsdx/vsdx.dart';

const double _screenPixelsPerInch = 96;

/// Page-inch bounding box of [shape] in its **parent local frame**, ignoring
/// any ancestor XForms. Useful for purely local computations (e.g. an
/// inspector panel showing a shape's intrinsic size). For viewport culling,
/// use [buildShapeBounds] which composes transforms back to page coords.
Rect shapeBoundingBox(VsdxShape shape) {
  final cosA = math.cos(shape.angleRad).abs();
  final sinA = math.sin(shape.angleRad).abs();
  final w = shape.width * cosA + shape.height * sinA;
  final h = shape.width * sinA + shape.height * cosA;
  final pad = math.max(shape.width, shape.height) * 0.05;
  return Rect.fromCenter(
    center: Offset(shape.pinX, shape.pinY),
    width: w + pad,
    height: h + pad,
  );
}

/// Build `{shapeId → page-coord bbox}` for every shape on [page].
///
/// Children inherit their parent's local frame (M4-06) so their bbox is the
/// composition of the parent transforms back to page coordinates.
Map<int, Rect> buildShapeBounds(VsdxPage page) {
  final out = <int, Rect>{};
  for (final s in page.shapes) {
    _walk(s, _Affine2D.identity, out, page);
  }
  return out;
}

void _walk(VsdxShape s, _Affine2D parent, Map<int, Rect> out, VsdxPage page) {
  // shape-local → parent-local: translate(pinX,pinY) · rotate · flip ·
  // translate(-LocPin)
  final local = parent
      .translate(s.pinX, s.pinY)
      .rotate(s.angleRad)
      .scale(s.flipX ? -1 : 1, s.flipY ? -1 : 1)
      .translate(-s.effectiveLocPinX, -s.effectiveLocPinY);
  final pad = math.max(s.width.abs(), s.height.abs()) * 0.05;
  final corners = <Offset>[];
  if (s.is1D) {
    // Elbow / curve bends often sit outside the Begin→End Width×Height box.
    for (final g in s.geometries) {
      if (g.noShow) continue;
      final verts = g.polylineVertices(
        widthInches: s.width,
        heightInches: s.height,
      );
      if (verts != null && verts.length >= 2) {
        corners.addAll(<Offset>[
          for (final p in verts) local.apply(p.x, p.y),
        ]);
        break;
      }
    }
    if (corners.isEmpty) {
      // NURBS / Arc / Spline connectors: sample the drawn stroke.
      final sampled = ShapePerimeter.sampledPathVertices(s);
      if (sampled != null && sampled.length >= 2) {
        corners.addAll(<Offset>[
          for (final p in sampled) local.apply(p.x, p.y),
        ]);
      }
    }
    if (corners.isEmpty) {
      // Begin/End/waypoints live in the parent frame for 1-D shapes.
      final ax = s.beginX ?? s.pinX, ay = s.beginY ?? s.pinY;
      final bx = s.endX ?? s.pinX, by = s.endY ?? s.pinY;
      corners.add(parent.apply(ax, ay));
      for (final w in s.waypoints) {
        corners.add(parent.apply(w.x, w.y));
      }
      corners.add(parent.apply(bx, by));
    }
  } else {
    corners.addAll(<Offset>[
      local.apply(-pad / 2, -pad / 2),
      local.apply(s.width + pad / 2, -pad / 2),
      local.apply(s.width + pad / 2, s.height + pad / 2),
      local.apply(-pad / 2, s.height + pad / 2),
    ]);
  }

  var minX = corners.first.dx, maxX = corners.first.dx;
  var minY = corners.first.dy, maxY = corners.first.dy;
  for (final c in corners.skip(1)) {
    if (c.dx < minX) minX = c.dx;
    if (c.dx > maxX) maxX = c.dx;
    if (c.dy < minY) minY = c.dy;
    if (c.dy > maxY) maxY = c.dy;
  }
  if (s.is1D && pad > 0) {
    minX -= pad / 2;
    maxX += pad / 2;
    minY -= pad / 2;
    maxY += pad / 2;
  }

  // Stroke decorations and effects are painted outside the geometry. These
  // bounds also drive selection-only export, so omitting the overflow clips
  // large draw.io-style effects at the crop edge.
  final strokeOverflow = s.line.hasLine
      ? math.max(0.0, s.line.weightInches) / 2
      : 0.0;
  var desiredLeft = strokeOverflow;
  var desiredRight = strokeOverflow;
  var desiredBottom = strokeOverflow;
  var desiredTop = strokeOverflow;

  void includeSymmetric(double amount) {
    desiredLeft = math.max(desiredLeft, amount);
    desiredRight = math.max(desiredRight, amount);
    desiredBottom = math.max(desiredBottom, amount);
    desiredTop = math.max(desiredTop, amount);
  }

  if (s.line.hasBeginArrow) {
    includeSymmetric(math.max(0.0, s.line.beginArrowSizeInches) * 2);
  }
  if (s.line.hasEndArrow) {
    includeSymmetric(math.max(0.0, s.line.endArrowSizeInches) * 2);
  }
  if (s.line.softEdgesInches > 0) {
    includeSymmetric(s.line.softEdgesInches * 3);
  }
  if (s.shadow.enabled && s.shadow.transparency < 1) {
    final offset = local.applyVector(
      s.shadow.offsetXInches,
      s.shadow.offsetYInches,
    );
    final sheet = page.pageSheet;
    final warp =
        math.max(s.width.abs(), s.height.abs()) *
        ((sheet.shadowScaleFactor - 1).abs() +
            math.tan(sheet.shadowObliqueAngle).abs());
    final blur = s.shadow.blurInches.abs() * 3 + warp;
    desiredLeft = math.max(desiredLeft, blur + math.max(0.0, -offset.dx));
    desiredRight = math.max(desiredRight, blur + math.max(0.0, offset.dx));
    desiredBottom = math.max(desiredBottom, blur + math.max(0.0, -offset.dy));
    desiredTop = math.max(desiredTop, blur + math.max(0.0, offset.dy));
  }
  if (s.glow.enabled && s.glow.sizeInches > 0 && s.glow.transparency < 1) {
    // Stroke half-width is GlowSize and Gaussian extent is about 3 sigma.
    includeSymmetric(s.glow.sizeInches * 4);
  }
  if (s.reflection.enabled &&
      s.reflection.sizeInches > 0 &&
      s.reflection.transparency < 1) {
    final sourceHeight = math.max(
      s.height.abs(),
      s.line.hasLine ? s.line.weightInches.abs() : 0.01,
    );
    final distance =
        sourceHeight * s.reflection.sizeInches.clamp(0.01, 1.0) +
        math.max(0.0, s.reflection.distanceInches);
    final direction = local.applyVector(0, -distance);
    final blur = s.reflection.blurInches.abs() * 3;
    desiredLeft = math.max(desiredLeft, blur + math.max(0.0, -direction.dx));
    desiredRight = math.max(desiredRight, blur + math.max(0.0, direction.dx));
    desiredBottom = math.max(
      desiredBottom,
      blur + math.max(0.0, -direction.dy),
    );
    desiredTop = math.max(desiredTop, blur + math.max(0.0, direction.dy));
  }
  // The original geometry box already carries [pad / 2] on every side.
  final baseOverflow = pad / 2;
  minX -= math.max(0.0, desiredLeft - baseOverflow);
  maxX += math.max(0.0, desiredRight - baseOverflow);
  minY -= math.max(0.0, desiredBottom - baseOverflow);
  maxY += math.max(0.0, desiredTop - baseOverflow);

  // Labels do not inherit geometry effects, so union them only after effect
  // expansion. This keeps external captions complete without adding shadow or
  // reflection whitespace around the caption itself.
  final labelCorners = <Offset>[];
  _addLabelBounds(s, page, local, labelCorners);
  for (final c in labelCorners) {
    minX = math.min(minX, c.dx);
    maxX = math.max(maxX, c.dx);
    minY = math.min(minY, c.dy);
    maxY = math.max(maxY, c.dy);
  }
  out[s.id] = Rect.fromLTRB(minX, minY, maxX, maxY);
  for (final c in s.children) {
    if (TableOps.isCovered(c)) continue;
    _walk(c, local, out, page);
  }
}

void _addLabelBounds(
  VsdxShape shape,
  VsdxPage page,
  _Affine2D local,
  List<Offset> corners,
) {
  final block = shape.richText.textBlock;
  if (block.hideText) return;
  var text = shape.richText.plainText.isNotEmpty
      ? shape.richText.plainText
      : shape.text ?? '';
  if (text.isEmpty &&
      !shape.is1D &&
      shape.name.isNotEmpty &&
      !_autoShapeName.hasMatch(shape.name)) {
    text = shape.name;
  }
  if (text.trim().isEmpty) return;

  final looseEdge =
      shape.isGlueableConnector &&
      block.pinXInches == null &&
      block.pinYInches == null;
  if (looseEdge) {
    final route = page.drawnConnectorPagePolyline(shape);
    final midpoint = route.length >= 2
        ? _polylineMidpoint(route)
        : VsdxPage.connectorMidpoint(shape);
    final localMidpoint = page.pageToLocalDeep(shape.id, midpoint);
    final size = _estimateLooseLabelSize(shape, text);
    final padding = shape.labelPadding;
    final top = (padding.isZero ? 3.0 : padding.top) / _screenPixelsPerInch;
    final right = (padding.isZero ? 3.0 : padding.right) /
        _screenPixelsPerInch;
    final bottom = (padding.isZero ? 3.0 : padding.bottom) /
        _screenPixelsPerInch;
    final left = (padding.isZero ? 3.0 : padding.left) / _screenPixelsPerInch;
    var labelTransform = local
        .translate(localMidpoint.x, localMidpoint.y)
        .rotate(page.effectiveConnectorLabelAngle(shape));
    if (block.textDirection == 1) {
      labelTransform = labelTransform.rotate(-math.pi / 2);
    }
    corners.addAll(<Offset>[
      labelTransform.apply(-size.width / 2 - left, -size.height / 2 - bottom),
      labelTransform.apply(size.width / 2 + right, -size.height / 2 - bottom),
      labelTransform.apply(size.width / 2 + right, size.height / 2 + top),
      labelTransform.apply(-size.width / 2 - left, size.height / 2 + top),
    ]);
    return;
  }

  // Caption / label blocks may sit outside the picture box (for example icon
  // text below a symbol). Honour TxtAngle and labelPadding as the renderers do.
  final tw = block.widthInches ?? shape.width;
  final th = block.heightInches ?? shape.height;
  final pinX = block.pinXInches ?? shape.width / 2;
  final pinY = block.pinYInches ?? shape.height / 2;
  final locX = block.locPinXInches ?? tw / 2;
  final locY = block.locPinYInches ?? th / 2;
  final padding = shape.labelPadding;
  final includePadding =
      !padding.isZero &&
      (block.backgroundColor != null || shape.labelBorderColor != null);
  final top = includePadding ? padding.top / _screenPixelsPerInch : 0.0;
  final right = includePadding ? padding.right / _screenPixelsPerInch : 0.0;
  final bottom = includePadding ? padding.bottom / _screenPixelsPerInch : 0.0;
  final left = includePadding ? padding.left / _screenPixelsPerInch : 0.0;
  final labelTransform = local
      .translate(pinX, pinY)
      .rotate(block.angleRad)
      .translate(-locX, -locY);
  corners.addAll(<Offset>[
    labelTransform.apply(-left, -bottom),
    labelTransform.apply(tw + right, -bottom),
    labelTransform.apply(tw + right, th + top),
    labelTransform.apply(-left, th + top),
  ]);
}

final RegExp _autoShapeName = RegExp(r'^Sheet\.\d+$');

({double width, double height}) _estimateLooseLabelSize(
  VsdxShape shape,
  String fallback,
) {
  final runs = shape.richText.runs.isEmpty
      ? <VsdxTextRun>[
          VsdxTextRun(
            text: fallback,
            charStyle: const VsdxCharStyle(fontSizeInches: 0.14),
          ),
        ]
      : shape.richText.runs;
  var lineWidth = 0.0;
  var lineHeight = 0.0;
  var width = 0.0;
  var height = 0.0;
  void finishLine() {
    width = math.max(width, lineWidth);
    height += math.max(lineHeight, 0.04);
    lineWidth = 0.0;
    lineHeight = 0.0;
  }

  for (final run in runs) {
    final fontSize = math.max(run.charStyle.fontSizeInches, 0.01);
    final fontScale = math.max(run.charStyle.fontScale, 0.1);
    for (final rune in run.text.runes) {
      if (rune == 0x0D) continue;
      if (rune == 0x0A) {
        finishLine();
        continue;
      }
      final double factor;
      if (rune == 0x09) {
        factor = 2.4;
      } else if (rune == 0x20) {
        factor = 0.4;
      } else if (rune > 0xFF) {
        factor = 1.05;
      } else {
        factor = 0.72;
      }
      lineWidth +=
          fontSize * factor * fontScale +
          math.max(0.0, run.charStyle.letterSpacingInches);
      lineHeight = math.max(lineHeight, fontSize * 1.25);
    }
  }
  finishLine();
  return (width: math.max(width, 0.04), height: math.max(height, 0.04));
}

Offset2D _polylineMidpoint(List<Offset2D> route) {
  if (route.isEmpty) return const Offset2D(0, 0);
  if (route.length == 1) return route.first;
  var total = 0.0;
  for (var i = 0; i < route.length - 1; i++) {
    final dx = route[i + 1].x - route[i].x;
    final dy = route[i + 1].y - route[i].y;
    total += math.sqrt(dx * dx + dy * dy);
  }
  if (total <= 0) return route.first;
  var remaining = total / 2;
  for (var i = 0; i < route.length - 1; i++) {
    final dx = route[i + 1].x - route[i].x;
    final dy = route[i + 1].y - route[i].y;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length >= remaining) {
      final t = length == 0 ? 0.0 : remaining / length;
      return Offset2D(route[i].x + dx * t, route[i].y + dy * t);
    }
    remaining -= length;
  }
  return route.last;
}

/// Minimal 2-D affine transform (`a b tx / c d ty`) used to compose XForm
/// chains during bbox accumulation. We avoid pulling in `vector_math`'s
/// 4×4 `Matrix4` for clarity — bbox math is hot-path and 2×2 is sufficient.
class _Affine2D {
  const _Affine2D(this.a, this.b, this.c, this.d, this.tx, this.ty);
  static const _Affine2D identity = _Affine2D(1, 0, 0, 1, 0, 0);

  final double a, b, c, d, tx, ty;

  Offset apply(double x, double y) =>
      Offset(a * x + b * y + tx, c * x + d * y + ty);

  Offset applyVector(double x, double y) =>
      Offset(a * x + b * y, c * x + d * y);

  _Affine2D multiply(_Affine2D o) => _Affine2D(
        a * o.a + b * o.c,
        a * o.b + b * o.d,
        c * o.a + d * o.c,
        c * o.b + d * o.d,
        a * o.tx + b * o.ty + tx,
        c * o.tx + d * o.ty + ty,
      );

  _Affine2D translate(double x, double y) =>
      multiply(_Affine2D(1, 0, 0, 1, x, y));

  _Affine2D rotate(double rad) {
    if (rad == 0) return this;
    final cosA = math.cos(rad);
    final sinA = math.sin(rad);
    return multiply(_Affine2D(cosA, -sinA, sinA, cosA, 0, 0));
  }

  _Affine2D scale(double sx, double sy) {
    if (sx == 1 && sy == 1) return this;
    return multiply(_Affine2D(sx, 0, 0, sy, 0, 0));
  }
}
