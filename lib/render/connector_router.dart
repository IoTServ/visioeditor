/// Auto-routing for 1-D connector shapes that lack an explicit Geometry
/// section.
///
/// When a [VsdxPage] is supplied, delegates to
/// [VsdxPage.autoRoutedConnectorPolyline] so paint-time fallback matches
/// SVG/PDF export (nested Begin/End lift, fixed glue points, ObstacleRouter).
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
  RoutedConnector? route(VsdxShape connector, {VsdxPage? page}) {
    if (!connector.isGlueableConnector) return null;
    final bx = connector.beginX;
    final by = connector.beginY;
    final ex = connector.endX;
    final ey = connector.endY;
    if (bx == null || by == null || ex == null || ey == null) return null;

    if (page != null) {
      final poly = page.autoRoutedConnectorPolyline(connector);
      if (poly.length >= 2) {
        return RoutedConnector(
          begin: Offset(poly.first.x, poly.first.y),
          end: Offset(poly.last.x, poly.last.y),
          waypoints: <Offset>[
            for (final p in poly.skip(1).take(poly.length - 2))
              Offset(p.x, p.y),
          ],
        );
      }
    }

    // No page context: plain elbow between raw Begin/End cells.
    final begin = Offset(bx, by);
    final end = Offset(ex, ey);
    final waypoints = _orthogonalRoute(begin, end);
    return RoutedConnector(begin: begin, end: end, waypoints: waypoints);
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
      final mx = (a.dx + b.dx) / 2;
      return <Offset>[Offset(mx, a.dy), Offset(mx, b.dy)];
    }
    final my = (a.dy + b.dy) / 2;
    return <Offset>[Offset(a.dx, my), Offset(b.dx, my)];
  }
}
