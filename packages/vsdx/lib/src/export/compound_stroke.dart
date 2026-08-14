/// Visio `CompoundType` rail layout + polyline offset helpers.
///
/// Used by the Flutter painter and SVG exporter so thick-thin / thin-thick
/// render as two parallel rails (not a centered double-line mask).
library;

import 'dart:math' as math;

import '../model/geometry.dart';
import '../model/spline.dart';

/// One rail of a compound stroke, measured from the path centreline.
class CompoundRail {
  const CompoundRail({required this.width, required this.offset});

  /// Stroke width of this rail.
  final double width;

  /// Signed offset from the centreline along the left normal (path direction).
  final double offset;
}

/// Rails for Visio `CompoundType` within total stroke [width].
///
/// - `0` / unknown → empty (caller draws a single stroke)
/// - `1` double — two equal rails with a transparent gap (~38% of width)
/// - `2` thick-thin — thick on the left normal, thin on the right
/// - `3` thin-thick — reverse of `2`
/// - `4` triple — thin / thick / thin
List<CompoundRail> compoundRails(int compoundType, double width) {
  final w = width;
  if (compoundType <= 0 || w < 1e-9) return const <CompoundRail>[];

  switch (compoundType) {
    case 1:
      final gap = w * 0.38;
      final rail = (w - gap) / 2;
      final off = gap / 2 + rail / 2;
      return <CompoundRail>[
        CompoundRail(width: rail, offset: off),
        CompoundRail(width: rail, offset: -off),
      ];
    case 2:
      // thick-thin
      final thick = w * 0.55;
      final thin = w * 0.25;
      final gap = w - thick - thin;
      return <CompoundRail>[
        CompoundRail(width: thick, offset: gap / 2 + thick / 2),
        CompoundRail(width: thin, offset: -(gap / 2 + thin / 2)),
      ];
    case 3:
      // thin-thick
      final thin = w * 0.25;
      final thick = w * 0.55;
      final gap = w - thick - thin;
      return <CompoundRail>[
        CompoundRail(width: thin, offset: gap / 2 + thin / 2),
        CompoundRail(width: thick, offset: -(gap / 2 + thick / 2)),
      ];
    case 4:
      // triple — thin / thick / thin, total width conserved
      final outer = w * 0.18;
      final mid = w * 0.28;
      final gap = (w - mid - 2 * outer) / 2;
      final outerOff = mid / 2 + gap + outer / 2;
      return <CompoundRail>[
        CompoundRail(width: outer, offset: outerOff),
        CompoundRail(width: mid, offset: 0),
        CompoundRail(width: outer, offset: -outerOff),
      ];
    default:
      // Unknown — fall back to double proportions.
      final gap = w * 0.38;
      final rail = (w - gap) / 2;
      final off = gap / 2 + rail / 2;
      return <CompoundRail>[
        CompoundRail(width: rail, offset: off),
        CompoundRail(width: rail, offset: -off),
      ];
  }
}

/// Offset an open or closed polyline by [distance] along the left normal.
///
/// Sharp corners use a simple miter (clamped). Returns an empty list when the
/// input is too short.
List<Offset2D> offsetPolyline(
  List<Offset2D> pts,
  double distance, {
  bool closed = false,
}) {
  if (pts.length < 2 || distance.abs() < 1e-12) {
    return distance.abs() < 1e-12 ? List<Offset2D>.from(pts) : const <Offset2D>[];
  }

  // Drop consecutive duplicates.
  final clean = <Offset2D>[pts.first];
  for (var i = 1; i < pts.length; i++) {
    final p = pts[i];
    final prev = clean.last;
    if ((p.x - prev.x).abs() > 1e-12 || (p.y - prev.y).abs() > 1e-12) {
      clean.add(p);
    }
  }
  if (closed && clean.length >= 2) {
    final a = clean.first;
    final b = clean.last;
    if ((a.x - b.x).abs() < 1e-12 && (a.y - b.y).abs() < 1e-12) {
      clean.removeLast();
    }
  }
  if (clean.length < 2) return const <Offset2D>[];

  Offset2D unit(Offset2D a, Offset2D b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-12) return const Offset2D(0, 0);
    return Offset2D(dx / len, dy / len);
  }

  Offset2D leftNormal(Offset2D dir) => Offset2D(-dir.y, dir.x);

  final n = clean.length;
  final out = <Offset2D>[];
  final maxMiter = distance.abs() * 4;

  for (var i = 0; i < n; i++) {
    final prev = clean[(i - 1 + n) % n];
    final cur = clean[i];
    final next = clean[(i + 1) % n];

    Offset2D normal;
    if (!closed && i == 0) {
      normal = leftNormal(unit(cur, next));
    } else if (!closed && i == n - 1) {
      normal = leftNormal(unit(prev, cur));
    } else {
      final d0 = unit(prev, cur);
      final d1 = unit(cur, next);
      final n0 = leftNormal(d0);
      final n1 = leftNormal(d1);
      // Average normals; fall back to either if opposite.
      var nx = n0.x + n1.x;
      var ny = n0.y + n1.y;
      var len = math.sqrt(nx * nx + ny * ny);
      if (len < 1e-9) {
        normal = n0;
      } else {
        // Miter scale from cos(half-angle) ≈ dot of unit dirs.
        final dot = (d0.x * d1.x + d0.y * d1.y).clamp(-1.0, 1.0);
        final miter = 1.0 / math.max(1e-6, math.sqrt((1 + dot) / 2));
        final scale = math.min(miter, 4.0);
        nx = nx / len * scale;
        ny = ny / len * scale;
        normal = Offset2D(nx, ny);
        // Clamp extreme miters.
        final mag = math.sqrt(normal.x * normal.x + normal.y * normal.y);
        if (mag * distance.abs() > maxMiter && mag > 1e-9) {
          final t = maxMiter / (mag * distance.abs());
          normal = Offset2D(normal.x * t, normal.y * t);
        }
      }
    }
    out.add(Offset2D(cur.x + normal.x * distance, cur.y + normal.y * distance));
  }
  return out;
}

/// Dense sample of an SVG path `d` into polyline vertices (M/L/C/Q/A/Z).
///
/// Curves are flattened; returns `closed: true` when the path ends with `Z`
/// or the first/last points coincide.
({List<Offset2D> points, bool closed}) samplePathD(
  String d, {
  double curveStep = 0.08,
}) {
  final tokens = _lexPath(d);
  final pts = <Offset2D>[];
  var closed = false;
  var i = 0;
  var cx = 0.0;
  var cy = 0.0;
  var startX = 0.0;
  var startY = 0.0;
  var cmd = 'L';

  double num() {
    if (i >= tokens.length) return 0;
    return double.tryParse(tokens[i++]) ?? 0;
  }

  void lineTo(double x, double y) {
    if (pts.isEmpty ||
        (pts.last.x - x).abs() > 1e-12 ||
        (pts.last.y - y).abs() > 1e-12) {
      pts.add(Offset2D(x, y));
    }
    cx = x;
    cy = y;
  }

  void cubic(double x1, double y1, double x2, double y2, double x, double y) {
    final steps = math.max(2, (curveStep > 0 ? (1 / curveStep).ceil() : 8));
    for (var s = 1; s <= steps; s++) {
      final t = s / steps;
      final u = 1 - t;
      final px = u * u * u * cx +
          3 * u * u * t * x1 +
          3 * u * t * t * x2 +
          t * t * t * x;
      final py = u * u * u * cy +
          3 * u * u * t * y1 +
          3 * u * t * t * y2 +
          t * t * t * y;
      lineTo(px, py);
    }
  }

  void quad(double x1, double y1, double x, double y) {
    final steps = math.max(2, (curveStep > 0 ? (1 / curveStep).ceil() : 8));
    for (var s = 1; s <= steps; s++) {
      final t = s / steps;
      final u = 1 - t;
      lineTo(
        u * u * cx + 2 * u * t * x1 + t * t * x,
        u * u * cy + 2 * u * t * y1 + t * t * y,
      );
    }
  }

  while (i < tokens.length) {
    final t = tokens[i];
    if (t.length == 1 && RegExp(r'[a-zA-Z]').hasMatch(t)) {
      cmd = t;
      i++;
    }
    final rel = cmd == cmd.toLowerCase();
    final c = cmd.toUpperCase();
    switch (c) {
      case 'M':
        var x = num();
        var y = num();
        if (rel) {
          x += cx;
          y += cy;
        }
        cx = x;
        cy = y;
        startX = x;
        startY = y;
        pts.add(Offset2D(x, y));
        cmd = rel ? 'l' : 'L';
        break;
      case 'L':
        var x = num();
        var y = num();
        if (rel) {
          x += cx;
          y += cy;
        }
        lineTo(x, y);
        break;
      case 'H':
        var x = num();
        if (rel) x += cx;
        lineTo(x, cy);
        break;
      case 'V':
        var y = num();
        if (rel) y += cy;
        lineTo(cx, y);
        break;
      case 'C':
        var x1 = num();
        var y1 = num();
        var x2 = num();
        var y2 = num();
        var x = num();
        var y = num();
        if (rel) {
          x1 += cx;
          y1 += cy;
          x2 += cx;
          y2 += cy;
          x += cx;
          y += cy;
        }
        cubic(x1, y1, x2, y2, x, y);
        break;
      case 'Q':
        var x1 = num();
        var y1 = num();
        var x = num();
        var y = num();
        if (rel) {
          x1 += cx;
          y1 += cy;
          x += cx;
          y += cy;
        }
        quad(x1, y1, x, y);
        break;
      case 'A':
        final rx = num().abs();
        final ry = num().abs();
        num(); // x-axis rotation (Visio emits axis-aligned)
        final largeArc = num() != 0;
        final sweep = num() != 0;
        var x = num();
        var y = num();
        if (rel) {
          x += cx;
          y += cy;
        }
        final steps =
            math.max(8, ((rx + ry) / math.max(curveStep, 0.02)).ceil());
        final start = Offset2D(cx, cy);
        final end = Offset2D(x, y);
        for (final p in sampleSvgArc(
          start,
          end,
          rx: rx,
          ry: ry,
          largeArc: largeArc,
          sweep: sweep,
          steps: steps,
        )) {
          lineTo(p.x, p.y);
        }
        break;
      case 'Z':
        closed = true;
        if (pts.isNotEmpty) lineTo(startX, startY);
        break;
      default:
        // Unknown / stray number — skip one token to avoid infinite loop.
        if (i < tokens.length) i++;
    }
  }

  if (!closed && pts.length >= 2) {
    final a = pts.first;
    final b = pts.last;
    if ((a.x - b.x).abs() < 1e-9 && (a.y - b.y).abs() < 1e-9) closed = true;
  }
  return (points: pts, closed: closed);
}

/// Sample an SVG elliptical `A` arc (excludes [start], includes [end]).
///
/// Circular arcs reuse [sampleArcByBow]; general ellipses use the W3C
/// endpoint→centre parameterisation (same as the SVG serializer).
List<Offset2D> sampleSvgArc(
  Offset2D start,
  Offset2D end, {
  required double rx,
  required double ry,
  required bool largeArc,
  required bool sweep,
  int steps = 8,
}) {
  if (rx < 1e-12 || ry < 1e-12) return <Offset2D>[end];
  final dx = end.x - start.x;
  final dy = end.y - start.y;
  final chord = math.sqrt(dx * dx + dy * dy);
  if (chord < 1e-12) return <Offset2D>[end];

  // Circular ArcTo path: recover Visio bow and sample like canvas.
  if ((rx - ry).abs() <= 1e-9 * math.max(rx, ry)) {
    final r = rx;
    final half = chord * 0.5;
    if (half > r + 1e-9) {
      return <Offset2D>[end];
    }
    final h = math.sqrt(math.max(0.0, r * r - half * half));
    final s = largeArc ? r + h : r - h;
    if (s < 1e-12) return <Offset2D>[end];
    // Visio: sweep=1 ⇔ bow < 0.
    final bow = (sweep ? -1.0 : 1.0) * s;
    return sampleArcByBow(
      start: start,
      end: end,
      bow: bow,
      steps: steps,
    );
  }

  // Elliptical: endpoint-to-centre (SVG / PDF).
  var rax = rx.abs();
  var ray = ry.abs();
  final x1 = start.x;
  final y1 = start.y;
  final x2 = end.x;
  final y2 = end.y;
  const phi = 0.0;
  final cosPhi = math.cos(phi);
  final sinPhi = math.sin(phi);
  final dx2 = (x1 - x2) / 2;
  final dy2 = (y1 - y2) / 2;
  final x1p = cosPhi * dx2 + sinPhi * dy2;
  final y1p = -sinPhi * dx2 + cosPhi * dy2;
  var lam = (x1p * x1p) / (rax * rax) + (y1p * y1p) / (ray * ray);
  if (lam > 1) {
    final s = math.sqrt(lam);
    rax *= s;
    ray *= s;
  }
  final rxSq = rax * rax;
  final rySq = ray * ray;
  final x1pSq = x1p * x1p;
  final y1pSq = y1p * y1p;
  var num = rxSq * rySq - rxSq * y1pSq - rySq * x1pSq;
  var den = rxSq * y1pSq + rySq * x1pSq;
  if (den <= 0) return <Offset2D>[end];
  num = math.max(0.0, num);
  var coef = math.sqrt(num / den);
  if (largeArc == sweep) coef = -coef;
  final cxp = coef * (rax * y1p) / ray;
  final cyp = coef * -(ray * x1p) / rax;
  final cx = cosPhi * cxp - sinPhi * cyp + (x1 + x2) / 2;
  final cy = sinPhi * cxp + cosPhi * cyp + (y1 + y2) / 2;

  double angle(double ux, double uy, double vx, double vy) {
    final dot = ux * vx + uy * vy;
    final len = math.sqrt(ux * ux + uy * uy) * math.sqrt(vx * vx + vy * vy);
    if (len < 1e-18) return 0.0;
    var ang = math.acos((dot / len).clamp(-1.0, 1.0));
    if (ux * vy - uy * vx < 0) ang = -ang;
    return ang;
  }

  final theta1 = angle(1, 0, (x1p - cxp) / rax, (y1p - cyp) / ray);
  var dTheta = angle(
    (x1p - cxp) / rax,
    (y1p - cyp) / ray,
    (-x1p - cxp) / rax,
    (-y1p - cyp) / ray,
  );
  if (!sweep && dTheta > 0) dTheta -= 2 * math.pi;
  if (sweep && dTheta < 0) dTheta += 2 * math.pi;

  final out = <Offset2D>[];
  for (var i = 1; i <= steps; i++) {
    final t = i / steps;
    final a = theta1 + dTheta * t;
    final cosA = math.cos(a);
    final sinA = math.sin(a);
    final x = cosPhi * rax * cosA - sinPhi * ray * sinA + cx;
    final y = sinPhi * rax * cosA + cosPhi * ray * sinA + cy;
    out.add(Offset2D(x, y));
  }
  if (out.isNotEmpty) out[out.length - 1] = end;
  return out;
}

String polylineToPathD(List<Offset2D> pts, {bool closed = false}) {
  if (pts.isEmpty) return '';
  final buf = StringBuffer('M ${_fmt(pts.first.x)} ${_fmt(pts.first.y)}');
  for (var i = 1; i < pts.length; i++) {
    buf.write(' L ${_fmt(pts[i].x)} ${_fmt(pts[i].y)}');
  }
  if (closed) buf.write(' Z');
  return buf.toString();
}

/// Trim measured distances from an open polyline without changing its middle
/// vertices. This ends connector strokes at arrow-marker bases while leaving
/// the separate marker carrier anchored at the authored endpoints.
List<Offset2D> trimPolylineEnds(
  List<Offset2D> points, {
  double begin = 0,
  double end = 0,
}) {
  if (points.length < 2 || (begin <= 1e-12 && end <= 1e-12)) {
    return List<Offset2D>.of(points);
  }
  final lengths = <double>[];
  var total = 0.0;
  for (var i = 1; i < points.length; i++) {
    final dx = points[i].x - points[i - 1].x;
    final dy = points[i].y - points[i - 1].y;
    total += math.sqrt(dx * dx + dy * dy);
    lengths.add(total);
  }
  if (total <= 1e-12) return <Offset2D>[points.first];
  final from = begin.clamp(0.0, total);
  final to = (total - end).clamp(from, total);

  Offset2D at(double distance) {
    if (distance <= 0) return points.first;
    if (distance >= total) return points.last;
    var previousLength = 0.0;
    for (var i = 0; i < lengths.length; i++) {
      final nextLength = lengths[i];
      if (distance <= nextLength) {
        final segmentLength = nextLength - previousLength;
        if (segmentLength <= 1e-12) return points[i + 1];
        final t = (distance - previousLength) / segmentLength;
        return Offset2D(
          points[i].x + (points[i + 1].x - points[i].x) * t,
          points[i].y + (points[i + 1].y - points[i].y) * t,
        );
      }
      previousLength = nextLength;
    }
    return points.last;
  }

  final out = <Offset2D>[at(from)];
  for (var i = 1; i < points.length - 1; i++) {
    final distance = lengths[i - 1];
    if (distance > from + 1e-12 && distance < to - 1e-12) {
      out.add(points[i]);
    }
  }
  final last = at(to);
  if ((out.last.x - last.x).abs() > 1e-12 ||
      (out.last.y - last.y).abs() > 1e-12) {
    out.add(last);
  }
  return out;
}

String _fmt(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '').replaceFirst(
        RegExp(r'\.$'),
        '',
      );
}

List<String> _lexPath(String d) {
  final out = <String>[];
  final re = RegExp(r'[a-zA-Z]|[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?');
  for (final m in re.allMatches(d)) {
    out.add(m.group(0)!);
  }
  return out;
}
