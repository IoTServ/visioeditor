import 'dart:math' as math;

/// Axis-aligned bounding box in **page inches** with Y pointing up (Visio
/// convention): [l]eft ≤ [r]ight and [b]ottom ≤ [t]op.
class SnapBox {
  const SnapBox(this.l, this.b, this.r, this.t);

  final double l;
  final double b;
  final double r;
  final double t;

  double get cx => (l + r) / 2;
  double get cy => (b + t) / 2;

  SnapBox shifted(double dx, double dy) => SnapBox(l + dx, b + dy, r + dx, t + dy);
}

/// A single alignment guide line (in page inches). When [vertical] the line has
/// constant x = [pos] and spans y ∈ [start, end]; otherwise constant y = [pos]
/// spanning x ∈ [start, end].
class SnapGuide {
  const SnapGuide({
    required this.vertical,
    required this.pos,
    required this.start,
    required this.end,
  });

  final bool vertical;
  final double pos;
  final double start;
  final double end;

  @override
  bool operator ==(Object other) =>
      other is SnapGuide &&
      other.vertical == vertical &&
      other.pos == pos &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(vertical, pos, start, end);
}

/// The nudge (in inches) to align a moving box to its neighbours, plus the
/// guide lines to draw.
class SnapResult {
  const SnapResult(this.dx, this.dy, this.guides);

  static const SnapResult none = SnapResult(0, 0, <SnapGuide>[]);

  final double dx;
  final double dy;
  final List<SnapGuide> guides;

  bool get isEmpty => dx == 0 && dy == 0 && guides.isEmpty;
}

/// drawio-style alignment snapping: given a [moving] box and the [others] on the
/// page, find the closest edge/centre alignment within [threshold] on each axis
/// and return the adjustment that snaps to it, together with the guide lines
/// connecting the moving box to the shape it aligned with.
///
/// Pure and Flutter-free so it can be unit-tested directly.
SnapResult computeSnap({
  required SnapBox moving,
  required List<SnapBox> others,
  required double threshold,
}) {
  if (others.isEmpty || threshold <= 0) return SnapResult.none;

  // Candidate alignment values on each axis: near edge, centre, far edge.
  List<double> xs(SnapBox b) => <double>[b.l, b.cx, b.r];
  List<double> ys(SnapBox b) => <double>[b.b, b.cy, b.t];

  var bestDx = 0.0;
  var bestXDiff = threshold;
  SnapBox? xMatch;
  var xLinePos = 0.0;

  var bestDy = 0.0;
  var bestYDiff = threshold;
  SnapBox? yMatch;
  var yLinePos = 0.0;

  final mxs = xs(moving);
  final mys = ys(moving);

  for (final o in others) {
    for (final ox in xs(o)) {
      for (final mx in mxs) {
        final diff = ox - mx;
        if (diff.abs() < bestXDiff) {
          bestXDiff = diff.abs();
          bestDx = diff;
          xMatch = o;
          xLinePos = ox;
        }
      }
    }
    for (final oy in ys(o)) {
      for (final my in mys) {
        final diff = oy - my;
        if (diff.abs() < bestYDiff) {
          bestYDiff = diff.abs();
          bestDy = diff;
          yMatch = o;
          yLinePos = oy;
        }
      }
    }
  }

  final guides = <SnapGuide>[];
  final snapped = moving.shifted(bestDx, bestDy);
  if (xMatch != null) {
    guides.add(SnapGuide(
      vertical: true,
      pos: xLinePos,
      start: math.min(snapped.b, xMatch.b),
      end: math.max(snapped.t, xMatch.t),
    ));
  }
  if (yMatch != null) {
    guides.add(SnapGuide(
      vertical: false,
      pos: yLinePos,
      start: math.min(snapped.l, yMatch.l),
      end: math.max(snapped.r, yMatch.r),
    ));
  }
  return SnapResult(bestDx, bestDy, guides);
}
