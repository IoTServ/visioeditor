import 'dart:math' as math;

import 'geometry.dart';

typedef FilletPathSegment = ({Offset2D end, Offset2D? control});
typedef FilletPath = ({
  Offset2D start,
  List<FilletPathSegment> segments,
  bool closed,
});

/// Whether a Move/Line polyline should be treated as a closed ring for Rounding.
///
/// Explicit first≈last is always closed. Filled outlines (`!noFill`) that omit
/// the closing LineTo (common Visio rectangles) are also treated as closed so
/// all corners fillet; open 1-D / NoFill elbows stay open.
bool polylineLooksClosed(
  List<Offset2D> pts, {
  required bool noFill,
}) {
  if (pts.length < 3) return false;
  final a = pts.first, b = pts.last;
  if ((a.x - b.x).abs() < 1e-9 && (a.y - b.y).abs() < 1e-9) return true;
  return !noFill;
}

/// Fillet sharp corners of a polyline using Visio/libvisio `Rounding`.
///
/// libvisio trims each adjacent segment and inserts a quadratic Bézier whose
/// control point is the original sharp corner. The Bézier is sampled into line
/// segments here so Flutter and SVG callers share the same geometry.
/// Returns [points] unchanged when [radius] ≤ 0 or fewer than three vertices.
List<Offset2D> filletPolyline(
  List<Offset2D> points,
  double radius, {
  bool closed = false,
  int arcSegments = 6,
}) {
  if (radius <= 1e-12 || points.length < 3) return points;

  final n = points.length;
  final out = <Offset2D>[];
  if (!closed) out.add(points.first);

  for (var i = 0; i < n; i++) {
    if (!closed && (i == 0 || i == n - 1)) continue;
    final prev = points[(i - 1 + n) % n];
    final cur = points[i];
    final next = points[(i + 1) % n];
    final corner = _filletCorner(
      prev,
      cur,
      next,
      radius,
    );
    if (corner == null) {
      out.add(cur);
      continue;
    }
    final samples = <Offset2D>[corner.start];
    final segs = math.max(2, arcSegments);
    for (var s = 1; s < segs; s++) {
      final t = s / segs;
      final u = 1.0 - t;
      samples.add(Offset2D(
        u * u * corner.start.x +
            2.0 * u * t * corner.control.x +
            t * t * corner.end.x,
        u * u * corner.start.y +
            2.0 * u * t * corner.control.y +
            t * t * corner.end.y,
      ));
    }
    samples.add(corner.end);
    out.addAll(samples);
  }

  if (!closed) out.add(points.last);
  return out;
}

/// Exact libvisio-style path: lines between trimmed corners and one quadratic
/// Bézier per corner, with the original sharp vertex as its control point.
FilletPath? filletPolylinePath(
  List<Offset2D> points,
  double radius, {
  bool closed = false,
  bool chamfer = false,
}) {
  if (radius <= 1e-12 || points.length < 3) return null;
  final n = points.length;
  final corners = <_FilletCorner?>[
    for (var i = 0; i < n; i++)
      (!closed && (i == 0 || i == n - 1))
          ? null
          : _filletCorner(
              points[(i - 1 + n) % n],
              points[i],
              points[(i + 1) % n],
              radius,
            ),
  ];
  FilletPathSegment cornerEdge(_FilletCorner corner) => (
        end: corner.end,
        control: chamfer ? null : corner.control,
      );
  final segments = <FilletPathSegment>[];
  if (!closed) {
    for (var i = 1; i < n - 1; i++) {
      final corner = corners[i];
      if (corner == null) {
        segments.add((end: points[i], control: null));
      } else {
        segments
          ..add((end: corner.start, control: null))
          ..add(cornerEdge(corner));
      }
    }
    segments.add((end: points.last, control: null));
    return (start: points.first, segments: segments, closed: false);
  }

  final firstCorner = corners.first;
  final start = firstCorner?.end ?? points.first;
  for (var step = 1; step <= n; step++) {
    final i = step % n;
    final corner = corners[i];
    if (corner == null) {
      segments.add((end: points[i], control: null));
    } else {
      segments
        ..add((end: corner.start, control: null))
        ..add(cornerEdge(corner));
    }
  }
  return (start: start, segments: segments, closed: true);
}

/// Bake Visio `Rounding` into a pure Move/Line/Polyline geometry.
///
/// libvisio applies `computeRounding` while importing VDX/VSD, but its VSDX
/// parser does not consume the `Rounding` cell. Legacy imports therefore need
/// explicit `RelQuadBezTo` rows in their synthesised VSDX or LibreOffice
/// reopens the same outline with sharp corners. Curved and multi-contour
/// geometries are returned unchanged.
VsdxGeometry bakePolylineRounding(
  VsdxGeometry geometry, {
  required double width,
  required double height,
  required double radius,
  bool chamfer = false,
}) {
  if (radius <= 1e-12 || width.abs() <= 1e-12 || height.abs() <= 1e-12) {
    return geometry;
  }
  final points = <Offset2D>[];
  var started = false;
  for (final command in geometry.commands) {
    switch (command) {
      case MoveTo(:final x, :final y):
        if (started && points.isNotEmpty) return geometry;
        points
          ..clear()
          ..add(Offset2D(x, y));
        started = true;
      case RelMoveTo(:final fx, :final fy):
        if (started && points.isNotEmpty) return geometry;
        points
          ..clear()
          ..add(Offset2D(fx * width, fy * height));
        started = true;
      case LineTo(:final x, :final y):
        if (!started) {
          points.add(const Offset2D(0, 0));
          started = true;
        }
        points.add(Offset2D(x, y));
      case RelLineTo(:final fx, :final fy):
        if (!started) {
          points.add(const Offset2D(0, 0));
          started = true;
        }
        points.add(Offset2D(fx * width, fy * height));
      case PolylineTo(
          :final x,
          :final y,
          :final vertices,
          :final relative,
          :final vertsRelative,
          :final vertsYRelative,
        ):
        if (!started) {
          points.add(const Offset2D(0, 0));
          started = true;
        }
        final vertexScaleX = vertsRelative ? width : 1.0;
        final vertexScaleY = vertsYRelative ? height : 1.0;
        for (final vertex in vertices) {
          points.add(Offset2D(
            vertex.x * vertexScaleX,
            vertex.y * vertexScaleY,
          ));
        }
        points.add(Offset2D(
          x * (relative ? width : 1.0),
          y * (relative ? height : 1.0),
        ));
      default:
        return geometry;
    }
  }
  if (points.length < 3) return geometry;

  var closed = false;
  final first = points.first;
  final last = points.last;
  if ((first.x - last.x).abs() < 1e-9 && (first.y - last.y).abs() < 1e-9) {
    closed = true;
    points.removeLast();
  } else {
    closed = polylineLooksClosed(points, noFill: geometry.noFill);
  }
  final fillet = filletPolylinePath(
    points,
    radius,
    closed: closed,
    chamfer: chamfer,
  );
  if (fillet == null) return geometry;

  return geometry.copyWith(
    commands: <VsdxPathCommand>[
      MoveTo(fillet.start.x, fillet.start.y),
      for (final segment in fillet.segments)
        if (segment.control case final control?)
          RelQuadBezTo(
            fx: segment.end.x / width,
            fy: segment.end.y / height,
            fx1: control.x / width,
            fy1: control.y / height,
          )
        else
          LineTo(segment.end.x, segment.end.y),
    ],
    commandFormulas: const <Map<String, String>>[],
    rowIndices: const <int>[],
    deletedRowIndices: const <int>{},
  );
}

_FilletCorner? _filletCorner(
  Offset2D prev,
  Offset2D cur,
  Offset2D next,
  double radius,
) {
  final inDx = cur.x - prev.x;
  final inDy = cur.y - prev.y;
  final outDx = next.x - cur.x;
  final outDy = next.y - cur.y;
  final inLen = math.sqrt(inDx * inDx + inDy * inDy);
  final outLen = math.sqrt(outDx * outDx + outDy * outDy);
  if (inLen < 1e-12 || outLen < 1e-12) return null;

  final inUx = inDx / inLen;
  final inUy = inDy / inLen;
  final outUx = outDx / outLen;
  final outUy = outDy / outLen;

  final cross = inUx * outUy - inUy * outUx;
  final dot = (inUx * outUx + inUy * outUy).clamp(-1.0, 1.0);
  final turn = math.atan2(cross, dot);
  if (turn.abs() < 1e-6 || (turn.abs() - math.pi).abs() < 1e-6) {
    return null;
  }

  final half = turn.abs() / 2;
  var trim = radius * math.tan(half);
  final maxTrim = math.min(inLen, outLen) * 0.5;
  if (trim > maxTrim) trim = maxTrim;
  if (trim < 1e-12) return null;

  final p1 = Offset2D(cur.x - inUx * trim, cur.y - inUy * trim);
  final p2 = Offset2D(cur.x + outUx * trim, cur.y + outUy * trim);

  return _FilletCorner(start: p1, control: cur, end: p2);
}

class _FilletCorner {
  const _FilletCorner({
    required this.start,
    required this.control,
    required this.end,
  });

  final Offset2D start;
  final Offset2D control;
  final Offset2D end;
}
