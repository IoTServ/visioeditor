/// Auto-routing for 1-D connector shapes that lack an explicit Geometry
/// section.
///
/// Visio draws connectors with a built-in autorouting engine that produces
/// orthogonal "Manhattan" paths between the connector's begin/end shapes.
/// We don't reimplement the full algorithm (which considers other shapes
/// and the page layout grid); instead we compute a sensible right-angle
/// route between the two anchor points based on:
///
///   1. The connector's `BeginX/BeginY` and `EndX/EndY` cells (page coords).
///   2. The page-level `<Connect>` records — when an endpoint is glued to a
///      target shape we attach it on that shape's **perimeter** (aimed at the
///      opposite end), matching Visio / libvisio. (An earlier version snapped
///      to the shape *centre*, which pushed arrow heads inside the target.)
///
/// Output is a [Path] in **page-inch coordinates** (Y up), ready to feed
/// the [VsdxPainter] under its existing canvas transform.
library;

import 'dart:ui';

import 'package:vsdx/vsdx.dart';

/// One routed segment for a connector — used by tests and by the painter.
class RoutedConnector {
  RoutedConnector({
    required this.begin,
    required this.end,
    required this.waypoints,
  });

  /// Start anchor, in page-inch coords.
  final Offset begin;

  /// End anchor, in page-inch coords.
  final Offset end;

  /// Intermediate waypoints (orthogonal corners). Always at least zero,
  /// at most two for the strategies below.
  final List<Offset> waypoints;

  /// Convenience: every vertex in source order.
  Iterable<Offset> get points sync* {
    yield begin;
    yield* waypoints;
    yield end;
  }

  /// Build a [Path] representing this route in the **page-inch**
  /// coordinate system (Y up — caller is responsible for any axis flip).
  Path toPath() {
    final p = Path()..moveTo(begin.dx, begin.dy);
    for (final w in waypoints) {
      p.lineTo(w.dx, w.dy);
    }
    p.lineTo(end.dx, end.dy);
    return p;
  }
}

class ConnectorRouter {
  const ConnectorRouter();

  /// Compute a routed path for [connector]. Returns `null` when the shape
  /// is not a 1-D connector or is missing endpoints.
  ///
  /// [page] is consulted for `<Connect>` glue records (so we can snap onto
  /// glued target shapes). When [page] is `null` we fall back to the raw
  /// `BeginX/EndX` cells.
  RoutedConnector? route(VsdxShape connector, {VsdxPage? page}) {
    if (!connector.is1D) return null;
    final bx = connector.beginX;
    final by = connector.beginY;
    final ex = connector.endX;
    final ey = connector.endY;
    if (bx == null || by == null || ex == null || ey == null) return null;

    var begin = Offset(bx, by);
    var end = Offset(ex, ey);

    // Attach glued endpoints on the target's perimeter (aimed at the opposite
    // end), so a connector stops at the shape's edge instead of driving into
    // its centre.
    if (page != null) {
      final rawBegin = Offset(bx, by);
      final rawEnd = Offset(ex, ey);
      for (final c in page.connectIndex.forConnector(connector.id)) {
        final target = page.findShapeById(c.toSheetId);
        if (target == null) continue;
        final lc = c.fromCell.toLowerCase();
        final isBegin = c.fromPart == 9 || lc.contains('beginx');
        final isEnd = c.fromPart == 12 || lc.contains('endx');
        if (isBegin) begin = _perimeterAttach(target, rawEnd);
        if (isEnd) end = _perimeterAttach(target, rawBegin);
      }
    }

    final waypoints = _orthogonalRoute(begin, end);
    return RoutedConnector(begin: begin, end: end, waypoints: waypoints);
  }

  /// The point on [target]'s axis-aligned box boundary along the ray from its
  /// centre toward [aim] — i.e. where a line coming from [aim] first meets the
  /// shape. Falls back to the centre for a degenerate box / coincident aim.
  static Offset _perimeterAttach(VsdxShape target, Offset aim) {
    final cx = target.pinX, cy = target.pinY;
    final hw = target.width / 2, hh = target.height / 2;
    if (hw <= 0 || hh <= 0) return Offset(cx, cy);
    final dx = aim.dx - cx, dy = aim.dy - cy;
    if (dx == 0 && dy == 0) return Offset(cx, cy);
    final tx = dx != 0 ? hw / dx.abs() : double.infinity;
    final ty = dy != 0 ? hh / dy.abs() : double.infinity;
    final t = tx < ty ? tx : ty; // first edge the ray crosses
    return Offset(cx + dx * t, cy + dy * t);
  }

  /// Two-corner orthogonal path. We pick the longer axis as the
  /// "primary" leg so short labels read naturally; degenerate axes are
  /// handled with single-segment routes.
  List<Offset> _orthogonalRoute(Offset a, Offset b) {
    final dx = (b.dx - a.dx).abs();
    final dy = (b.dy - a.dy).abs();
    const epsilon = 1e-6;
    if (dx < epsilon || dy < epsilon) {
      return const <Offset>[];
    }
    if (dx >= dy) {
      // Horizontal-first: (a) → (mid, a.y) → (mid, b.y) → (b)
      final midX = a.dx + (b.dx - a.dx) / 2;
      return <Offset>[
        Offset(midX, a.dy),
        Offset(midX, b.dy),
      ];
    }
    final midY = a.dy + (b.dy - a.dy) / 2;
    return <Offset>[
      Offset(a.dx, midY),
      Offset(b.dx, midY),
    ];
  }
}
