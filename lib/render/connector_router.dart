/// Auto-routing for 1-D connector shapes that lack an explicit Geometry
/// section.
///
/// Visio / draw.io draw connectors with an autorouting engine that produces
/// orthogonal "Manhattan" paths between the connector's begin/end shapes,
/// skirting other shapes on the page. When a [VsdxPage] is supplied we reuse
/// [ObstacleRouter] so paint-time fallback matches the editor's baked routes.
/// Without a page we fall back to a simple two-corner elbow.
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

  /// Intermediate waypoints (orthogonal corners). Always at least zero.
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
  /// [page] is consulted for `<Connect>` glue records and for other shapes as
  /// obstacles. When [page] is `null` we fall back to the raw `BeginX/EndX`
  /// cells and a plain elbow.
  RoutedConnector? route(VsdxShape connector, {VsdxPage? page}) {
    if (!connector.is1D) return null;
    final bx = connector.beginX;
    final by = connector.beginY;
    final ex = connector.endX;
    final ey = connector.endY;
    if (bx == null || by == null || ex == null || ey == null) return null;

    var begin = Offset(bx, by);
    var end = Offset(ex, ey);
    final exclude = <int>{connector.id};

    // Attach glued endpoints on the target's perimeter (aimed at the opposite
    // end), so a connector stops at the shape's edge instead of driving into
    // its centre.
    if (page != null) {
      final rawBegin = Offset(bx, by);
      final rawEnd = Offset(ex, ey);
      for (final c in page.connectIndex.forConnector(connector.id)) {
        final target = page.findShapeById(c.toSheetId);
        if (target == null) continue;
        exclude.add(target.id);
        final lc = c.fromCell.toLowerCase();
        final isBegin = c.fromPart == 9 || lc.contains('beginx');
        final isEnd = c.fromPart == 12 || lc.contains('endx');
        if (isBegin) begin = _perimeterAttach(target, rawEnd);
        if (isEnd) end = _perimeterAttach(target, rawBegin);
      }
    }

    final List<Offset> waypoints;
    if (page != null) {
      final obstacles = <RouteAabb>[];
      void walk(List<VsdxShape> list) {
        for (final s in list) {
          if (s.children.isNotEmpty) {
            walk(s.children);
            continue;
          }
          if (exclude.contains(s.id) || s.is1D) continue;
          if (s.width < 0.05 || s.height < 0.05) continue;
          obstacles.add(RouteAabb.fromCenter(
            pinX: s.pinX,
            pinY: s.pinY,
            width: s.width,
            height: s.height,
            pad: ObstacleRouter.defaultClearance,
          ));
        }
      }

      walk(page.shapes);
      final poly = const ObstacleRouter().route(
        begin.dx,
        begin.dy,
        end.dx,
        end.dy,
        obstacles: obstacles,
      );
      waypoints = <Offset>[
        for (final p in poly.skip(1).take(poly.length - 2)) Offset(p.x, p.y),
      ];
    } else {
      waypoints = _orthogonalRoute(begin, end);
    }
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

  /// Two-corner orthogonal path used when no page/obstacles are available.
  List<Offset> _orthogonalRoute(Offset a, Offset b) {
    final dx = (b.dx - a.dx).abs();
    final dy = (b.dy - a.dy).abs();
    const epsilon = 1e-6;
    if (dx < epsilon || dy < epsilon) {
      return const <Offset>[];
    }
    if (dx >= dy) {
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
