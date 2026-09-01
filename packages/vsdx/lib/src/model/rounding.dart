import 'dart:math' as math;

import 'geometry.dart';

typedef FilletPathSegment = ({Offset2D end, Offset2D? control});
typedef FilletPath = ({
  Offset2D start,
  List<FilletPathSegment> segments,
  bool closed,
});

/// Whether a Move/Line polyline is closed for stroking.
///
/// Canvas `stroke()` / SVG without `Z` follow the authored vertices.
/// [polylineLooksClosed] also treats filled open rings as closed so Rounding
/// fillets every corner; that invented close is a 180° hairpin when the last
/// point lies on the first edge (Android Spinner caret), so leftover miter
/// ribbons must not use it.
bool polylineStrokeLooksClosed(List<Offset2D> pts) {
  if (pts.length < 3) return false;
  final a = pts.first, b = pts.last;
  return (a.x - b.x).abs() < 1e-9 && (a.y - b.y).abs() < 1e-9;
}

/// Whether a Move/Line polyline should be treated as a closed ring for Rounding.
///
/// Explicit first≈last is always closed. Filled outlines (`!noFill`) that omit
/// the closing LineTo (common Visio rectangles) are also treated as closed so
/// all corners fillet; open 1-D / NoFill elbows stay open. Stroke / miter
/// leftover uses [polylineStrokeLooksClosed] instead.
bool polylineLooksClosed(
  List<Offset2D> pts, {
  required bool noFill,
}) {
  if (pts.length < 3) return false;
  if (polylineStrokeLooksClosed(pts)) return true;
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
///
/// When [chamfer] is set, each filleted corner is a LineTo cut. [miterLimit]
/// (SVG / canvas `stroke-miterlimit`) further restricts that to corners whose
/// miter ratio exceeds the limit, so a low draw.io `veMiterLimit` can bake
/// only the spikes LibreOffice would keep (it never emits the attribute).
FilletPath? filletPolylinePath(
  List<Offset2D> points,
  double radius, {
  bool closed = false,
  bool chamfer = false,
  double? miterLimit,
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
  if (chamfer && miterLimit != null) {
    for (var i = 0; i < n; i++) {
      if (corners[i] == null) continue;
      if (strokeMiterRatio(
            points[(i - 1 + n) % n],
            points[i],
            points[(i + 1) % n],
          ) <=
          miterLimit) {
        corners[i] = null;
      }
    }
  }
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

/// Bake Visio `Rounding` / leftover joins into Geometry Draw will stroke.
///
/// libvisio applies `computeRounding` while importing VDX/VSD, but its VSDX
/// parser does not consume the `Rounding` cell. `_lineProperties` also maps
/// join from `LineCap` only (`tokens.txt` has no LineJoin), so leftover
/// round / arcs / bevel joins become RelQuadBezTo / LineTo chamfers.
/// `VSDContentCollector` fillets only L→L (and L→Z after M→L) corners and
/// leaves CubBezTo rails native; leftover does the same for mixed
/// LineTo+curve paths (Jump-in Arrow 1). NURBS / ellipse-only sections
/// stay unchanged.
VsdxGeometry bakePolylineRounding(
  VsdxGeometry geometry, {
  required double width,
  required double height,
  required double radius,
  bool chamfer = false,
  double? miterLimit,
}) {
  if (radius <= 1e-12 || width.abs() <= 1e-12 || height.abs() <= 1e-12) {
    return geometry;
  }
  final points = <Offset2D>[];
  var started = false;
  for (final command in geometry.commands) {
    switch (command) {
      case MoveTo(:final x, :final y):
        if (started && points.isNotEmpty) {
          return _bakeMixedPathRounding(
            geometry,
            width: width,
            height: height,
            radius: radius,
            chamfer: chamfer,
            miterLimit: miterLimit,
          );
        }
        points
          ..clear()
          ..add(Offset2D(x, y));
        started = true;
      case RelMoveTo(:final fx, :final fy):
        if (started && points.isNotEmpty) {
          return _bakeMixedPathRounding(
            geometry,
            width: width,
            height: height,
            radius: radius,
            chamfer: chamfer,
            miterLimit: miterLimit,
          );
        }
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
        return _bakeMixedPathRounding(
          geometry,
          width: width,
          height: height,
          radius: radius,
          chamfer: chamfer,
          miterLimit: miterLimit,
        );
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
    miterLimit: miterLimit,
  );
  if (fillet == null) return geometry;
  return geometry.copyWith(
    commands: _commandsFromFilletPath(
      fillet,
      width: width,
      height: height,
    ),
    commandFormulas: const <Map<String, String>>[],
    rowIndices: const <int>[],
    deletedRowIndices: const <int>{},
  );
}

List<VsdxPathCommand> _commandsFromFilletPath(
  FilletPath fillet, {
  required double width,
  required double height,
}) =>
    <VsdxPathCommand>[
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
    ];

VsdxPathCommand _filletCornerCommand(
  _FilletCorner corner, {
  required double width,
  required double height,
  required bool chamfer,
}) {
  if (chamfer) return LineTo(corner.end.x, corner.end.y);
  return RelQuadBezTo(
    fx: corner.end.x / width,
    fy: corner.end.y / height,
    fx1: corner.control.x / width,
    fy1: corner.control.y / height,
  );
}

/// `computeRounding` only fillets L→L. CubBezTo / RelCubBezTo stay native.
VsdxGeometry _bakeMixedPathRounding(
  VsdxGeometry geometry, {
  required double width,
  required double height,
  required double radius,
  required bool chamfer,
  double? miterLimit,
}) {
  final subpaths = _mixedSubpathsForRounding(
    geometry,
    width: width,
    height: height,
  );
  if (subpaths == null || subpaths.isEmpty) return geometry;
  final out = <VsdxPathCommand>[];
  var changed = false;
  for (final subpath in subpaths) {
    final baked = _filletMixedSubpath(
      subpath,
      geometry: geometry,
      width: width,
      height: height,
      radius: radius,
      chamfer: chamfer,
      miterLimit: miterLimit,
    );
    if (!identical(baked, subpath.original)) changed = true;
    out.addAll(baked);
  }
  if (!changed) return geometry;
  return geometry.copyWith(
    commands: out,
    commandFormulas: const <Map<String, String>>[],
    rowIndices: const <int>[],
    deletedRowIndices: const <int>{},
  );
}

List<_MixedSubpath>? _mixedSubpathsForRounding(
  VsdxGeometry geometry, {
  required double width,
  required double height,
}) {
  final subpaths = <_MixedSubpath>[];
  Offset2D? start;
  var segs = <_MixedSeg>[];
  var original = <VsdxPathCommand>[];

  void flush() {
    if (start != null && segs.isNotEmpty) {
      subpaths.add(
        _MixedSubpath(start: start!, segs: segs, original: original),
      );
    }
    start = null;
    segs = <_MixedSeg>[];
    original = <VsdxPathCommand>[];
  }

  void ensureStart() {
    if (start != null) return;
    start = const Offset2D(0, 0);
    original.add(const MoveTo(0, 0));
  }

  for (final command in geometry.commands) {
    switch (command) {
      case MoveTo(:final x, :final y):
        flush();
        start = Offset2D(x, y);
        original.add(command);
      case RelMoveTo(:final fx, :final fy):
        flush();
        start = Offset2D(fx * width, fy * height);
        original.add(command);
      case LineTo(:final x, :final y):
        ensureStart();
        segs.add(_MixedSeg(end: Offset2D(x, y), linear: true));
        original.add(command);
      case RelLineTo(:final fx, :final fy):
        ensureStart();
        segs.add(
          _MixedSeg(end: Offset2D(fx * width, fy * height), linear: true),
        );
        original.add(command);
      case PolylineTo(
          :final x,
          :final y,
          :final vertices,
          :final relative,
          :final vertsRelative,
          :final vertsYRelative,
        ):
        ensureStart();
        original.add(command);
        final vertexScaleX = vertsRelative ? width : 1.0;
        final vertexScaleY = vertsYRelative ? height : 1.0;
        for (final vertex in vertices) {
          segs.add(
            _MixedSeg(
              end: Offset2D(
                vertex.x * vertexScaleX,
                vertex.y * vertexScaleY,
              ),
              linear: true,
            ),
          );
        }
        segs.add(
          _MixedSeg(
            end: Offset2D(
              x * (relative ? width : 1.0),
              y * (relative ? height : 1.0),
            ),
            linear: true,
          ),
        );
      case CubBezTo() ||
            RelCubBezTo() ||
            QuadBezTo() ||
            RelQuadBezTo() ||
            ArcTo() ||
            RelArcTo() ||
            EllipticalArcTo() ||
            RelEllipticalArcTo():
        final end = _roundingCommandEnd(
          command,
          width: width,
          height: height,
        );
        if (end == null) return null;
        ensureStart();
        segs.add(_MixedSeg(end: end, linear: false, command: command));
        original.add(command);
      default:
        return null;
    }
  }
  flush();
  return subpaths;
}

Offset2D? _roundingCommandEnd(
  VsdxPathCommand command, {
  required double width,
  required double height,
}) {
  switch (command) {
    case MoveTo(:final x, :final y) ||
          LineTo(:final x, :final y) ||
          ArcTo(:final x, :final y) ||
          CubBezTo(:final x, :final y) ||
          QuadBezTo(:final x, :final y) ||
          EllipticalArcTo(:final x, :final y):
      return Offset2D(x, y);
    case RelMoveTo(:final fx, :final fy) ||
          RelLineTo(:final fx, :final fy) ||
          RelArcTo(:final fx, :final fy) ||
          RelCubBezTo(:final fx, :final fy) ||
          RelQuadBezTo(:final fx, :final fy) ||
          RelEllipticalArcTo(:final fx, :final fy):
      return Offset2D(fx * width, fy * height);
    case PolylineTo(:final x, :final y, :final relative):
      return Offset2D(
        x * (relative ? width : 1.0),
        y * (relative ? height : 1.0),
      );
    default:
      return null;
  }
}

List<VsdxPathCommand> _filletMixedSubpath(
  _MixedSubpath subpath, {
  required VsdxGeometry geometry,
  required double width,
  required double height,
  required double radius,
  required bool chamfer,
  double? miterLimit,
}) {
  final hasCurve = subpath.segs.any((seg) => !seg.linear);
  if (!hasCurve) {
    final points = <Offset2D>[
      subpath.start,
      for (final seg in subpath.segs) seg.end,
    ];
    if (points.length < 3) return subpath.original;
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
      miterLimit: miterLimit,
    );
    if (fillet == null) return subpath.original;
    return _commandsFromFilletPath(
      fillet,
      width: width,
      height: height,
    );
  }

  final segs = List<_MixedSeg>.from(subpath.segs);
  final points = <Offset2D>[subpath.start, for (final seg in segs) seg.end];
  if (points.length < 3) return subpath.original;
  var closed = false;
  var didPop = false;
  var poppedLinear = false;
  VsdxPathCommand? poppedCurve;
  final first = points.first;
  final last = points.last;
  if ((first.x - last.x).abs() < 1e-9 && (first.y - last.y).abs() < 1e-9) {
    closed = true;
    didPop = true;
    poppedLinear = segs.last.linear;
    poppedCurve = segs.last.command;
    segs.removeLast();
    points.removeLast();
  }
  final n = points.length;
  if (n < 3) return subpath.original;

  bool incomingLinear(int i) {
    if (i == 0) return closed && poppedLinear;
    return segs[i - 1].linear;
  }

  bool outgoingLinear(int i) {
    if (i >= segs.length) return closed && poppedLinear;
    return segs[i].linear;
  }

  final corners = <_FilletCorner?>[
    for (var i = 0; i < n; i++)
      (!closed && (i == 0 || i == n - 1)) ||
              !incomingLinear(i) ||
              !outgoingLinear(i)
          ? null
          : _filletCorner(
              points[(i - 1 + n) % n],
              points[i],
              points[(i + 1) % n],
              radius,
            ),
  ];
  if (chamfer && miterLimit != null) {
    for (var i = 0; i < n; i++) {
      if (corners[i] == null) continue;
      if (strokeMiterRatio(
            points[(i - 1 + n) % n],
            points[i],
            points[(i + 1) % n],
          ) <=
          miterLimit) {
        corners[i] = null;
      }
    }
  }
  if (corners.every((corner) => corner == null)) return subpath.original;

  VsdxPathCommand arrivalAt(int i) {
    if (i == 0) {
      if (didPop && !poppedLinear && poppedCurve != null) {
        return poppedCurve;
      }
      return LineTo(points.first.x, points.first.y);
    }
    final seg = segs[i - 1];
    if (!seg.linear && seg.command != null) return seg.command!;
    return LineTo(points[i].x, points[i].y);
  }

  void emitVertex(List<VsdxPathCommand> out, int i) {
    final corner = corners[i];
    if (corner == null) {
      out.add(arrivalAt(i));
      return;
    }
    out
      ..add(LineTo(corner.start.x, corner.start.y))
      ..add(
        _filletCornerCommand(
          corner,
          width: width,
          height: height,
          chamfer: chamfer,
        ),
      );
  }

  final out = <VsdxPathCommand>[];
  if (!closed) {
    out.add(MoveTo(points.first.x, points.first.y));
    for (var i = 1; i < n - 1; i++) {
      emitVertex(out, i);
    }
    out.add(arrivalAt(n - 1));
    return out;
  }
  final start = corners.first?.end ?? points.first;
  out.add(MoveTo(start.x, start.y));
  for (var step = 1; step <= n; step++) {
    emitVertex(out, step % n);
  }
  return out;
}

class _MixedSeg {
  const _MixedSeg({
    required this.end,
    required this.linear,
    this.command,
  });
  final Offset2D end;
  final bool linear;
  final VsdxPathCommand? command;
}

class _MixedSubpath {
  const _MixedSubpath({
    required this.start,
    required this.segs,
    required this.original,
  });
  final Offset2D start;
  final List<_MixedSeg> segs;
  final List<VsdxPathCommand> original;
}

/// SVG / canvas miter length ÷ stroke width at [cur].
///
/// `1 / sin(θ/2)` where θ is the interior angle. A 90° elbow is √2; a
/// hairpin approaches infinity. Values at or below 1 mean a bevel for
/// `stroke-miterlimit="1"`.
double strokeMiterRatio(Offset2D prev, Offset2D cur, Offset2D next) {
  final inDx = cur.x - prev.x;
  final inDy = cur.y - prev.y;
  final outDx = next.x - cur.x;
  final outDy = next.y - cur.y;
  final inLen = math.sqrt(inDx * inDx + inDy * inDy);
  final outLen = math.sqrt(outDx * outDx + outDy * outDy);
  if (inLen < 1e-12 || outLen < 1e-12) return 1;
  final inUx = inDx / inLen;
  final inUy = inDy / inLen;
  final outUx = outDx / outLen;
  final outUy = outDy / outLen;
  final dot = (inUx * outUx + inUy * outUy).clamp(-1.0, 1.0);
  final theta = math.pi - math.acos(dot);
  final s = math.sin(theta / 2);
  if (s.abs() < 1e-12) return 1e6;
  return 1 / s.abs();
}

/// `true` when any corner's miter ratio exceeds Draw's ODF default of 4.
///
/// `_lineProperties` never emits `svg:stroke-miterlimit`, so those elbows
/// bevel in LibreOffice while canvas / SVG still honour a higher
/// `veMiterLimit`. Open polylines skip endpoints.
bool polylineHasDrawClippedMiter(
  List<Offset2D> points, {
  required bool closed,
}) {
  final n = points.length;
  if (n < 3) return false;
  final first = closed ? 0 : 1;
  final last = closed ? n : n - 1;
  for (var i = first; i < last; i++) {
    if (strokeMiterRatio(
          points[(i - 1 + n) % n],
          points[i],
          points[(i + 1) % n],
        ) >
        4.0 + 1e-6) {
      return true;
    }
  }
  return false;
}

/// `true` when the polyline turns at an interior vertex.
///
/// Open paths skip endpoints. A collinear continuation has miter ratio 1;
/// any real elbow (90°, hairpin, …) is greater.
bool polylineHasElbow(
  List<Offset2D> points, {
  required bool closed,
}) {
  final n = points.length;
  if (n < 3) return false;
  final first = closed ? 0 : 1;
  final last = closed ? n : n - 1;
  for (var i = first; i < last; i++) {
    if (strokeMiterRatio(
          points[(i - 1 + n) % n],
          points[i],
          points[(i + 1) % n],
        ) >
        1.05) {
      return true;
    }
  }
  return false;
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
