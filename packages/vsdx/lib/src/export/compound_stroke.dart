/// Visio `CompoundType` rail layout + polyline offset helpers.
///
/// Used by the Flutter painter and SVG exporter so thick-thin / thin-thick
/// render as two parallel rails (not a centered double-line mask).
library;

import 'dart:math' as math;

import '../model/geometry.dart';

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
    default:
      // Triple / unknown — fall back to double proportions.
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
        // Flatten elliptical arc via chord samples (enough for rail offset).
        final rx = num().abs();
        final ry = num().abs();
        num(); // x-axis rotation
        num(); // large-arc
        num(); // sweep
        var x = num();
        var y = num();
        if (rel) {
          x += cx;
          y += cy;
        }
        final steps =
            math.max(4, ((rx + ry) / math.max(curveStep, 0.02)).ceil());
        for (var s = 1; s <= steps; s++) {
          final t = s / steps;
          lineTo(cx + (x - cx) * t, cy + (y - cy) * t);
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

String polylineToPathD(List<Offset2D> pts, {bool closed = false}) {
  if (pts.isEmpty) return '';
  final buf = StringBuffer('M ${_fmt(pts.first.x)} ${_fmt(pts.first.y)}');
  for (var i = 1; i < pts.length; i++) {
    buf.write(' L ${_fmt(pts[i].x)} ${_fmt(pts[i].y)}');
  }
  if (closed) buf.write(' Z');
  return buf.toString();
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
