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
  double get width => r - l;
  double get height => t - b;

  SnapBox shifted(double dx, double dy) =>
      SnapBox(l + dx, b + dy, r + dx, t + dy);
}

/// Visual meaning of a dynamic guide.
enum SnapGuideKind {
  /// Shape edge / centre, connection-point or permanent-guide alignment.
  alignment,

  /// Equal gap between three neighbouring shapes.
  spacing,

  /// Horizontal or vertical centre of the page.
  pageCenter,
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
    this.kind = SnapGuideKind.alignment,
  });

  final bool vertical;
  final double pos;
  final double start;
  final double end;
  final SnapGuideKind kind;

  @override
  bool operator ==(Object other) =>
      other is SnapGuide &&
      other.vertical == vertical &&
      other.pos == pos &&
      other.start == start &&
      other.end == end &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(vertical, pos, start, end, kind);
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
/// When [pageBounds] is supplied, the moving box also snaps its centre to the
/// page centre. Equal gaps between three shapes are detected automatically.
///
/// Pure and Flutter-free so it can be unit-tested directly.
SnapResult computeSnap({
  required SnapBox moving,
  required List<SnapBox> others,
  required double threshold,
  List<PageGuide> pageGuides = const <PageGuide>[],
  List<SnapMagnet> magnets = const <SnapMagnet>[],
  SnapBox? pageBounds,
}) {
  if (threshold <= 0) return SnapResult.none;
  if (others.isEmpty &&
      pageGuides.isEmpty &&
      magnets.isEmpty &&
      pageBounds == null) {
    return SnapResult.none;
  }

  List<double> xs(SnapBox b) => <double>[b.l, b.cx, b.r];
  List<double> ys(SnapBox b) => <double>[b.b, b.cy, b.t];

  var bestDx = 0.0;
  var bestXDiff = threshold;
  SnapBox? xMatch;
  var xLinePos = 0.0;
  var xFromPageGuide = false;
  var xFromPageCenter = false;
  List<SnapGuide>? xSpacingGuides;

  var bestDy = 0.0;
  var bestYDiff = threshold;
  SnapBox? yMatch;
  var yLinePos = 0.0;
  var yFromPageGuide = false;
  var yFromPageCenter = false;
  List<SnapGuide>? ySpacingGuides;

  final mxs = xs(moving);
  final mys = ys(moving);

  void chooseXAlignment(
    double diff,
    double pos,
    SnapBox? match, {
    bool pageGuide = false,
    bool pageCenter = false,
  }) {
    if (diff.abs() >= bestXDiff) return;
    bestXDiff = diff.abs();
    bestDx = diff;
    xMatch = match;
    xLinePos = pos;
    xFromPageGuide = pageGuide;
    xFromPageCenter = pageCenter;
    xSpacingGuides = null;
  }

  void chooseYAlignment(
    double diff,
    double pos,
    SnapBox? match, {
    bool pageGuide = false,
    bool pageCenter = false,
  }) {
    if (diff.abs() >= bestYDiff) return;
    bestYDiff = diff.abs();
    bestDy = diff;
    yMatch = match;
    yLinePos = pos;
    yFromPageGuide = pageGuide;
    yFromPageCenter = pageCenter;
    ySpacingGuides = null;
  }

  for (final o in others) {
    for (final ox in xs(o)) {
      for (final mx in mxs) {
        chooseXAlignment(ox - mx, ox, o);
      }
    }
    for (final oy in ys(o)) {
      for (final my in mys) {
        chooseYAlignment(oy - my, oy, o);
      }
    }
  }

  // Connection-point magnets (draw.io): snap moving edges/centres to the
  // magnet's x or y. Represented as a degenerate box for guide span.
  for (final m in magnets) {
    final magnetBox = SnapBox(m.x, m.y, m.x, m.y);
    for (final mx in mxs) {
      chooseXAlignment(m.x - mx, m.x, magnetBox);
    }
    for (final my in mys) {
      chooseYAlignment(m.y - my, m.y, magnetBox);
    }
  }

  for (final g in pageGuides) {
    if (g.vertical) {
      for (final mx in mxs) {
        chooseXAlignment(g.pos - mx, g.pos, null, pageGuide: true);
      }
    } else {
      for (final my in mys) {
        chooseYAlignment(g.pos - my, g.pos, null, pageGuide: true);
      }
    }
  }

  // The page centre is a dedicated orange guide in draw.io. Only the moving
  // centre participates; edges do not stick to the page centre.
  if (pageBounds != null) {
    chooseXAlignment(
      pageBounds.cx - moving.cx,
      pageBounds.cx,
      null,
      pageCenter: true,
    );
    chooseYAlignment(
      pageBounds.cy - moving.cy,
      pageBounds.cy,
      null,
      pageCenter: true,
    );
  }

  void chooseXSpacing(double dx, List<SnapGuide> spacingGuides) {
    if (dx.abs() >= bestXDiff) return;
    bestXDiff = dx.abs();
    bestDx = dx;
    xMatch = null;
    xFromPageGuide = false;
    xFromPageCenter = false;
    xSpacingGuides = spacingGuides;
  }

  void chooseYSpacing(double dy, List<SnapGuide> spacingGuides) {
    if (dy.abs() >= bestYDiff) return;
    bestYDiff = dy.abs();
    bestDy = dy;
    yMatch = null;
    yFromPageGuide = false;
    yFromPageCenter = false;
    ySpacingGuides = spacingGuides;
  }

  // Equal-spacing guides. Handle both common arrangements:
  //   A [gap] moving [gap] B
  //   A [gap] B [same gap] moving
  // and their vertical equivalents.
  for (var i = 0; i < others.length; i++) {
    for (var j = i + 1; j < others.length; j++) {
      final first = others[i];
      final second = others[j];
      final firstIsLeft = first.l <= second.l;
      final left = firstIsLeft ? first : second;
      final right = firstIsLeft ? second : first;
      final sharesRow =
          math.min(left.t, right.t) >= math.max(left.b, right.b) - threshold &&
          math.min(moving.t, left.t) >=
              math.max(moving.b, left.b) - threshold &&
          math.min(moving.t, right.t) >=
              math.max(moving.b, right.b) - threshold;
      if (left.r <= right.l && sharesRow) {
        final available = right.l - left.r - moving.width;
        if (available >= 0) {
          final targetLeft = left.r + available / 2;
          final dx = targetLeft - moving.l;
          final snapped = moving.shifted(dx, 0);
          chooseXSpacing(dx, <SnapGuide>[
            SnapGuide(
              vertical: false,
              pos: snapped.cy,
              start: left.r,
              end: snapped.l,
              kind: SnapGuideKind.spacing,
            ),
            SnapGuide(
              vertical: false,
              pos: snapped.cy,
              start: snapped.r,
              end: right.l,
              kind: SnapGuideKind.spacing,
            ),
          ]);
        }
        final existingGap = right.l - left.r;
        if (moving.l >= right.r - threshold) {
          final dx = right.r + existingGap - moving.l;
          final snapped = moving.shifted(dx, 0);
          chooseXSpacing(dx, <SnapGuide>[
            SnapGuide(
              vertical: false,
              pos: snapped.cy,
              start: left.r,
              end: right.l,
              kind: SnapGuideKind.spacing,
            ),
            SnapGuide(
              vertical: false,
              pos: snapped.cy,
              start: right.r,
              end: snapped.l,
              kind: SnapGuideKind.spacing,
            ),
          ]);
        }
        if (moving.r <= left.l + threshold) {
          final dx = left.l - existingGap - moving.r;
          final snapped = moving.shifted(dx, 0);
          chooseXSpacing(dx, <SnapGuide>[
            SnapGuide(
              vertical: false,
              pos: snapped.cy,
              start: snapped.r,
              end: left.l,
              kind: SnapGuideKind.spacing,
            ),
            SnapGuide(
              vertical: false,
              pos: snapped.cy,
              start: left.r,
              end: right.l,
              kind: SnapGuideKind.spacing,
            ),
          ]);
        }
      }

      final firstIsBelow = first.b <= second.b;
      final below = firstIsBelow ? first : second;
      final above = firstIsBelow ? second : first;
      final sharesColumn =
          math.min(below.r, above.r) >=
              math.max(below.l, above.l) - threshold &&
          math.min(moving.r, below.r) >=
              math.max(moving.l, below.l) - threshold &&
          math.min(moving.r, above.r) >=
              math.max(moving.l, above.l) - threshold;
      if (below.t <= above.b && sharesColumn) {
        final available = above.b - below.t - moving.height;
        if (available >= 0) {
          final targetBottom = below.t + available / 2;
          final dy = targetBottom - moving.b;
          final snapped = moving.shifted(0, dy);
          chooseYSpacing(dy, <SnapGuide>[
            SnapGuide(
              vertical: true,
              pos: snapped.cx,
              start: below.t,
              end: snapped.b,
              kind: SnapGuideKind.spacing,
            ),
            SnapGuide(
              vertical: true,
              pos: snapped.cx,
              start: snapped.t,
              end: above.b,
              kind: SnapGuideKind.spacing,
            ),
          ]);
        }
        final existingGap = above.b - below.t;
        if (moving.b >= above.t - threshold) {
          final dy = above.t + existingGap - moving.b;
          final snapped = moving.shifted(0, dy);
          chooseYSpacing(dy, <SnapGuide>[
            SnapGuide(
              vertical: true,
              pos: snapped.cx,
              start: below.t,
              end: above.b,
              kind: SnapGuideKind.spacing,
            ),
            SnapGuide(
              vertical: true,
              pos: snapped.cx,
              start: above.t,
              end: snapped.b,
              kind: SnapGuideKind.spacing,
            ),
          ]);
        }
        if (moving.t <= below.b + threshold) {
          final dy = below.b - existingGap - moving.t;
          final snapped = moving.shifted(0, dy);
          chooseYSpacing(dy, <SnapGuide>[
            SnapGuide(
              vertical: true,
              pos: snapped.cx,
              start: snapped.t,
              end: below.b,
              kind: SnapGuideKind.spacing,
            ),
            SnapGuide(
              vertical: true,
              pos: snapped.cx,
              start: below.t,
              end: above.b,
              kind: SnapGuideKind.spacing,
            ),
          ]);
        }
      }
    }
  }

  final guides = <SnapGuide>[];
  final snapped = moving.shifted(bestDx, bestDy);
  final snappedX =
      xFromPageGuide ||
      xFromPageCenter ||
      xMatch != null ||
      xSpacingGuides != null;
  final snappedY =
      yFromPageGuide ||
      yFromPageCenter ||
      yMatch != null ||
      ySpacingGuides != null;
  if (snappedX) {
    final spacing = xSpacingGuides;
    final match = xMatch;
    if (spacing != null) {
      guides.addAll(spacing);
    } else {
      guides.add(
        SnapGuide(
          vertical: true,
          pos: xLinePos,
          start: xFromPageCenter
              ? pageBounds!.b
              : match == null
              ? snapped.b
              : math.min(snapped.b, match.b),
          end: xFromPageCenter
              ? pageBounds!.t
              : match == null
              ? snapped.t
              : math.max(snapped.t, match.t),
          kind: xFromPageCenter
              ? SnapGuideKind.pageCenter
              : SnapGuideKind.alignment,
        ),
      );
    }
  }
  if (snappedY) {
    final spacing = ySpacingGuides;
    final match = yMatch;
    if (spacing != null) {
      guides.addAll(spacing);
    } else {
      guides.add(
        SnapGuide(
          vertical: false,
          pos: yLinePos,
          start: yFromPageCenter
              ? pageBounds!.l
              : match == null
              ? snapped.l
              : math.min(snapped.l, match.l),
          end: yFromPageCenter
              ? pageBounds!.r
              : match == null
              ? snapped.r
              : math.max(snapped.r, match.r),
          kind: yFromPageCenter
              ? SnapGuideKind.pageCenter
              : SnapGuideKind.alignment,
        ),
      );
    }
  }
  return SnapResult(
    bestDx,
    bestDy,
    guides,
    snappedX: snappedX,
    snappedY: snappedY,
  );
}
