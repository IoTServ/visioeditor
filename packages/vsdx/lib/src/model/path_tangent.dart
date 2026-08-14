/// Endpoint and tangent recovery for open Visio geometry paths.
library;

import 'elliptical_arc.dart';
import 'geometry.dart';
import 'nurbs.dart';
import 'spline.dart';

/// The first and last drawable points in a Geometry section, together with
/// forward traversal vectors at those points.
typedef VsdxPathEndpointTangents = ({
  Offset2D start,
  Offset2D end,
  Offset2D startForward,
  Offset2D endForward,
});

/// Resolves a Visio `InfiniteLine`'s two defining local points to the visible
/// page-clipped endpoints, returned in the same local coordinate system.
typedef VsdxInfiniteLineEndpointResolver = List<Offset2D>? Function(
  Offset2D p,
  Offset2D q,
);

/// Recover marker positions and orientations for every open drawable subpath
/// without reducing curves to coarse chords. This matches libvisio's single
/// multi-`M` line path: LibreOffice applies start/end markers to each subpath.
List<VsdxPathEndpointTangents> geometrySubpathEndpointTangents(
  VsdxGeometry geometry, {
  required double widthInches,
  required double heightInches,
  VsdxInfiniteLineEndpointResolver? infiniteLineResolver,
}) {
  Offset2D cursor = const Offset2D(0, 0);
  final subpaths = <VsdxPathEndpointTangents>[];
  Offset2D? firstPoint;
  Offset2D? firstForward;
  Offset2D? lastPoint;
  Offset2D? lastForward;

  Offset2D delta(Offset2D a, Offset2D b) => Offset2D(b.x - a.x, b.y - a.y);

  Offset2D? firstNonZero(Iterable<Offset2D> candidates) {
    for (final candidate in candidates) {
      final lengthSquared =
          candidate.x * candidate.x + candidate.y * candidate.y;
      if (lengthSquared > 1e-24 &&
          candidate.x.isFinite &&
          candidate.y.isFinite) {
        return candidate;
      }
    }
    return null;
  }

  void addSegment(
    Offset2D start,
    Offset2D end, {
    Iterable<Offset2D> startCandidates = const <Offset2D>[],
    Iterable<Offset2D> endCandidates = const <Offset2D>[],
  }) {
    final chord = delta(start, end);
    final startTangent = firstNonZero(<Offset2D>[...startCandidates, chord]);
    final endTangent = firstNonZero(<Offset2D>[...endCandidates, chord]);
    if (startTangent == null || endTangent == null) return;
    firstPoint ??= start;
    firstForward ??= startTangent;
    lastPoint = end;
    lastForward = endTangent;
  }

  void addPolyline(Offset2D start, Iterable<Offset2D> points) {
    var previous = start;
    for (final point in points) {
      addSegment(previous, point);
      previous = point;
    }
  }

  void flushSubpath() {
    final start = firstPoint;
    final end = lastPoint;
    final startVector = firstForward;
    final endVector = lastForward;
    // VSDContentCollector closes line subpaths whose final coordinates return
    // to their MoveTo coordinates, using VSD_EPSILON (1E-6). LibreOffice does
    // not paint start/end markers on the resulting Z-closed subpath.
    final isClosed = start != null &&
        end != null &&
        (start.x - end.x).abs() <= 1e-6 &&
        (start.y - end.y).abs() <= 1e-6;
    if (start != null &&
        end != null &&
        startVector != null &&
        endVector != null &&
        !isClosed) {
      subpaths.add((
        start: start,
        end: end,
        startForward: startVector,
        endForward: endVector,
      ));
    }
    firstPoint = null;
    firstForward = null;
    lastPoint = null;
    lastForward = null;
  }

  final commands = geometry.commands;
  for (var i = 0; i < commands.length; i++) {
    final command = commands[i];
    switch (command) {
      case MoveTo(:final x, :final y):
        flushSubpath();
        cursor = Offset2D(x, y);
      case RelMoveTo(:final fx, :final fy):
        flushSubpath();
        cursor = Offset2D(fx * widthInches, fy * heightInches);
      case LineTo(:final x, :final y):
        final end = Offset2D(x, y);
        addSegment(cursor, end);
        cursor = end;
      case RelLineTo(:final fx, :final fy):
        final end = Offset2D(fx * widthInches, fy * heightInches);
        addSegment(cursor, end);
        cursor = end;
      case CubBezTo(
          :final x,
          :final y,
          :final x1,
          :final y1,
          :final x2,
          :final y2,
        ):
        final c1 = Offset2D(x1, y1);
        final c2 = Offset2D(x2, y2);
        final end = Offset2D(x, y);
        addSegment(
          cursor,
          end,
          startCandidates: <Offset2D>[delta(cursor, c1), delta(cursor, c2)],
          endCandidates: <Offset2D>[delta(c2, end), delta(c1, end)],
        );
        cursor = end;
      case RelCubBezTo(
          :final fx,
          :final fy,
          :final fx1,
          :final fy1,
          :final fx2,
          :final fy2,
        ):
        final c1 = Offset2D(fx1 * widthInches, fy1 * heightInches);
        final c2 = Offset2D(fx2 * widthInches, fy2 * heightInches);
        final end = Offset2D(fx * widthInches, fy * heightInches);
        addSegment(
          cursor,
          end,
          startCandidates: <Offset2D>[delta(cursor, c1), delta(cursor, c2)],
          endCandidates: <Offset2D>[delta(c2, end), delta(c1, end)],
        );
        cursor = end;
      case QuadBezTo(:final x, :final y, :final x1, :final y1):
        final control = Offset2D(x1, y1);
        final end = Offset2D(x, y);
        addSegment(
          cursor,
          end,
          startCandidates: <Offset2D>[delta(cursor, control)],
          endCandidates: <Offset2D>[delta(control, end)],
        );
        cursor = end;
      case RelQuadBezTo(:final fx, :final fy, :final fx1, :final fy1):
        final control = Offset2D(fx1 * widthInches, fy1 * heightInches);
        final end = Offset2D(fx * widthInches, fy * heightInches);
        addSegment(
          cursor,
          end,
          startCandidates: <Offset2D>[delta(cursor, control)],
          endCandidates: <Offset2D>[delta(control, end)],
        );
        cursor = end;
      case ArcTo(:final x, :final y, :final bow):
        final end = Offset2D(x, y);
        final tangents = arcByBowEndpointTangents(
          start: cursor,
          end: end,
          bow: bow,
        );
        addSegment(
          cursor,
          end,
          startCandidates: <Offset2D>[if (tangents != null) tangents.start],
          endCandidates: <Offset2D>[if (tangents != null) tangents.end],
        );
        cursor = end;
      case RelArcTo(:final fx, :final fy, :final fbow):
        final end = Offset2D(fx * widthInches, fy * heightInches);
        final bow = fbow * (widthInches + heightInches) / 2;
        final tangents = arcByBowEndpointTangents(
          start: cursor,
          end: end,
          bow: bow,
        );
        addSegment(
          cursor,
          end,
          startCandidates: <Offset2D>[if (tangents != null) tangents.start],
          endCandidates: <Offset2D>[if (tangents != null) tangents.end],
        );
        cursor = end;
      case EllipticalArcTo(
          :final x,
          :final y,
          :final controlX,
          :final controlY,
          :final angle,
          :final eccentricity,
        ):
        final end = Offset2D(x, y);
        final tangents = ellipticalArcEndpointTangents(
          start: cursor,
          end: end,
          control: Offset2D(controlX, controlY),
          angle: angle,
          eccentricity: eccentricity,
        );
        addSegment(
          cursor,
          end,
          startCandidates: <Offset2D>[if (tangents != null) tangents.start],
          endCandidates: <Offset2D>[if (tangents != null) tangents.end],
        );
        cursor = end;
      case RelEllipticalArcTo(
          :final fx,
          :final fy,
          :final fcx,
          :final fcy,
          :final angle,
          :final eccentricity,
        ):
        final end = Offset2D(fx * widthInches, fy * heightInches);
        final tangents = ellipticalArcEndpointTangents(
          start: cursor,
          end: end,
          control: Offset2D(fcx * widthInches, fcy * heightInches),
          angle: angle,
          eccentricity: eccentricity,
        );
        addSegment(
          cursor,
          end,
          startCandidates: <Offset2D>[if (tangents != null) tangents.start],
          endCandidates: <Offset2D>[if (tangents != null) tangents.end],
        );
        cursor = end;
      case final PolylineTo polyline:
        final points = <Offset2D>[
          for (final vertex in polyline.vertices)
            Offset2D(
              vertex.x * (polyline.vertsRelative ? widthInches : 1.0),
              vertex.y * (polyline.vertsYRelative ? heightInches : 1.0),
            ),
          Offset2D(
            polyline.x * (polyline.relative ? widthInches : 1.0),
            polyline.y * (polyline.relative ? heightInches : 1.0),
          ),
        ];
        addPolyline(cursor, points);
        cursor = points.last;
      case SplineStart():
        final spline = consumeSplineSequence(
          commands,
          i,
          pen: cursor,
          width: widthInches,
          height: heightInches,
        );
        addPolyline(cursor, spline.samples);
        cursor = spline.end;
        i = spline.nextIndex - 1;
      case SplineKnot():
        break;
      case NurbsTo(
          :final x,
          :final y,
          :final controlPoints,
          :final weights,
          :final knots,
          :final degree,
          :final relative,
          :final cpRelative,
          :final cpYRelative,
        ):
        final end = Offset2D(
          x * (relative ? widthInches : 1.0),
          y * (relative ? heightInches : 1.0),
        );
        final samples = sampleNurbs(
          start: cursor,
          end: end,
          controlPoints: <Offset2D>[
            for (final point in controlPoints)
              Offset2D(
                point.x * (cpRelative ? widthInches : 1.0),
                point.y * (cpYRelative ? heightInches : 1.0),
              ),
          ],
          weights: weights,
          knots: knots,
          degree: degree,
        );
        addPolyline(cursor, samples);
        cursor = end;
      case InfiniteLineCmd(
          :final x,
          :final y,
          :final a,
          :final b,
          :final relative,
        ):
        // libvisio emits InfiniteLine as an explicit M/L pair, so it starts a
        // fresh marker-bearing subpath even without an authored MoveTo row.
        flushSubpath();
        final sx = relative ? widthInches : 1.0;
        final sy = relative ? heightInches : 1.0;
        final clipped = infiniteLineResolver?.call(
          Offset2D(x * sx, y * sy),
          Offset2D(a * sx, b * sy),
        );
        if (clipped != null && clipped.length >= 2) {
          addSegment(clipped.first, clipped.last);
          cursor = clipped.last;
        }
      case EllipseCmd():
        // collectEllipse emits M/A/A/Z. LibreOffice suppresses line endings
        // on that closed subpath even when the surrounding path style carries
        // marker properties, so only flush the preceding open subpath.
        flushSubpath();
    }
  }
  flushSubpath();
  return subpaths;
}

/// Recover the aggregate first/last marker endpoints for compatibility with
/// callers that treat a Geometry section as one path. New renderers should use
/// [geometrySubpathEndpointTangents] so multi-`M` paths retain every marker.
VsdxPathEndpointTangents? geometryEndpointTangents(
  VsdxGeometry geometry, {
  required double widthInches,
  required double heightInches,
  VsdxInfiniteLineEndpointResolver? infiniteLineResolver,
}) {
  final subpaths = geometrySubpathEndpointTangents(
    geometry,
    widthInches: widthInches,
    heightInches: heightInches,
    infiniteLineResolver: infiniteLineResolver,
  );
  if (subpaths.isEmpty) return null;
  final first = subpaths.first;
  final last = subpaths.last;
  return (
    start: first.start,
    end: last.end,
    startForward: first.startForward,
    endForward: last.endForward,
  );
}
