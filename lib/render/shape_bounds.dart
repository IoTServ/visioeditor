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
    _walk(s, _Affine2D.identity, out);
  }
  return out;
}

void _walk(VsdxShape s, _Affine2D parent, Map<int, Rect> out) {
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
      final pts = <Offset>[];
      var ok = true;
      for (final c in g.commands) {
        if (c is MoveTo) {
          pts.add(local.apply(c.x, c.y));
        } else if (c is LineTo) {
          pts.add(local.apply(c.x, c.y));
        } else {
          ok = false;
          break;
        }
      }
      if (ok && pts.length >= 2) {
        corners.addAll(pts);
        break;
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
  out[s.id] = Rect.fromLTRB(minX, minY, maxX, maxY);
  for (final c in s.children) {
    if (TableOps.isCovered(c)) continue;
    _walk(c, local, out);
  }
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
