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
  const SnapResult(
    this.dx,
    this.dy,
    this.guides, {
    this.snappedX = false,
    this.snappedY = false,
  });

  static const SnapResult none = SnapResult(0, 0, <SnapGuide>[]);

  final double dx;
  final double dy;
  final List<SnapGuide> guides;

  /// True when an X-axis neighbour / magnet / page guide claimed this frame
  /// (even if [dx] is already 0 because the box sits on the guide).
  final bool snappedX;

  /// True when a Y-axis neighbour / magnet / page guide claimed this frame
  /// (even if [dy] is already 0 because the box sits on the guide).
  final bool snappedY;

  bool get isEmpty =>
      dx == 0 && dy == 0 && guides.isEmpty && !snappedX && !snappedY;
}

/// A permanent page guide (drawio guide): a full-span vertical or horizontal
/// line at [pos] page-inches. Session-level (not written to `.vsdx`).
class PageGuide {
  const PageGuide({required this.vertical, required this.pos});

  /// `true` → vertical line at x = [pos]; `false` → horizontal at y = [pos].
  final bool vertical;
  final double pos;

  PageGuide copyWith({double? pos}) =>
      PageGuide(vertical: vertical, pos: pos ?? this.pos);

  @override
  bool operator ==(Object other) =>
      other is PageGuide && other.vertical == vertical && other.pos == pos;

  @override
  int get hashCode => Object.hash(vertical, pos);
}

/// A point magnet in page inches (typically a neighbour's connection point).
class SnapMagnet {
  const SnapMagnet(this.x, this.y);
  final double x;
  final double y;
}

/// drawio-style alignment snapping: given a [moving] box and the [others] on the
/// page, find the closest edge/centre alignment within [threshold] on each axis
/// and return the adjustment that snaps to it, together with the guide lines
/// connecting the moving box to the shape it aligned with.
///
/// Optional [pageGuides] (permanent ruler guides) and [magnets] (connection
/// points / other hotspots) compete with neighbour alignments on the same axes.
///
/// Pure and Flutter-free so it can be unit-tested directly.
SnapResult computeSnap({
  required SnapBox moving,
  required List<SnapBox> others,
  required double threshold,
  List<PageGuide> pageGuides = const <PageGuide>[],
  List<SnapMagnet> magnets = const <SnapMagnet>[],
}) {
  if (threshold <= 0) return SnapResult.none;
  if (others.isEmpty && pageGuides.isEmpty && magnets.isEmpty) {
    return SnapResult.none;
  }

  // Candidate alignment values on each axis: near edge, centre, far edge.
  List<double> xs(SnapBox b) => <double>[b.l, b.cx, b.r];
  List<double> ys(SnapBox b) => <double>[b.b, b.cy, b.t];

  var bestDx = 0.0;
  var bestXDiff = threshold;
  SnapBox? xMatch;
  var xLinePos = 0.0;
  var xFromPageGuide = false;

  var bestDy = 0.0;
  var bestYDiff = threshold;
  SnapBox? yMatch;
  var yLinePos = 0.0;
  var yFromPageGuide = false;

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
          xFromPageGuide = false;
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
          yFromPageGuide = false;
        }
      }
    }
  }

  // Connection-point magnets (draw.io): snap moving edges/centres to the
  // magnet's x or y. Represented as a degenerate box for guide span.
  for (final m in magnets) {
    final magnetBox = SnapBox(m.x, m.y, m.x, m.y);
    for (final mx in mxs) {
      final diff = m.x - mx;
      if (diff.abs() < bestXDiff) {
        bestXDiff = diff.abs();
        bestDx = diff;
        xMatch = magnetBox;
        xLinePos = m.x;
        xFromPageGuide = false;
      }
    }
    for (final my in mys) {
      final diff = m.y - my;
      if (diff.abs() < bestYDiff) {
        bestYDiff = diff.abs();
        bestDy = diff;
        yMatch = magnetBox;
        yLinePos = m.y;
        yFromPageGuide = false;
      }
    }
  }

  for (final g in pageGuides) {
    if (g.vertical) {
      for (final mx in mxs) {
        final diff = g.pos - mx;
        if (diff.abs() < bestXDiff) {
          bestXDiff = diff.abs();
          bestDx = diff;
          xMatch = null;
          xLinePos = g.pos;
          xFromPageGuide = true;
        }
      }
    } else {
      for (final my in mys) {
        final diff = g.pos - my;
        if (diff.abs() < bestYDiff) {
          bestYDiff = diff.abs();
          bestDy = diff;
          yMatch = null;
          yLinePos = g.pos;
          yFromPageGuide = true;
        }
      }
    }
  }

  final guides = <SnapGuide>[];
  final snapped = moving.shifted(bestDx, bestDy);
  final snappedX = xFromPageGuide || xMatch != null;
  final snappedY = yFromPageGuide || yMatch != null;
  if (snappedX) {
    guides.add(SnapGuide(
      vertical: true,
      pos: xLinePos,
      start: xMatch == null
          ? snapped.b
          : math.min(snapped.b, xMatch.b),
      end: xMatch == null
          ? snapped.t
          : math.max(snapped.t, xMatch.t),
    ));
  }
  if (snappedY) {
    guides.add(SnapGuide(
      vertical: false,
      pos: yLinePos,
      start: yMatch == null
          ? snapped.l
          : math.min(snapped.l, yMatch.l),
      end: yMatch == null
          ? snapped.r
          : math.max(snapped.r, yMatch.r),
    ));
  }
  return SnapResult(
    bestDx,
    bestDy,
    guides,
    snappedX: snappedX,
    snappedY: snappedY,
  );
}
