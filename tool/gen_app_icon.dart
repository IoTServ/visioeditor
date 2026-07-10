// Generates the macOS app icon PNGs for `Editor for Visio Diagrams`.
//
// The icon is a rounded blue tile carrying a white flow-diagram motif (two
// nodes joined by an orthogonal connector with an arrowhead) — a nod to the
// Visio diagrams the app edits. It is rendered at high resolution with simple
// boolean fills, then box-downsampled to every required size so the edges come
// out anti-aliased without hand-rolling coverage maths.
//
// Run from the project root:
//   dart run tool/gen_app_icon.dart
//
// Output: macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_<n>.png
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// Supersampled master resolution; downsampling from here yields the AA.
const int kMaster = 2048;

/// Icon sizes referenced by the asset catalog's Contents.json.
const List<int> kSizes = <int>[16, 32, 64, 128, 256, 512, 1024];

const String kOutDir =
    'macos/Runner/Assets.xcassets/AppIcon.appiconset';

class _Rgb {
  const _Rgb(this.r, this.g, this.b);
  final double r, g, b;
}

_Rgb _lerp(_Rgb a, _Rgb b, double t) => _Rgb(
      a.r + (b.r - a.r) * t,
      a.g + (b.g - a.g) * t,
      a.b + (b.b - a.b) * t,
    );

bool _insideRoundRect(
  double px,
  double py,
  double cx,
  double cy,
  double halfW,
  double halfH,
  double r,
) {
  final dx = (px - cx).abs() - (halfW - r);
  final dy = (py - cy).abs() - (halfH - r);
  if (dx <= 0 || dy <= 0) {
    return (px - cx).abs() <= halfW && (py - cy).abs() <= halfH;
  }
  return dx * dx + dy * dy <= r * r;
}

double _segDist(
  double px,
  double py,
  double ax,
  double ay,
  double bx,
  double by,
) {
  final vx = bx - ax, vy = by - ay;
  final wx = px - ax, wy = py - ay;
  final len2 = vx * vx + vy * vy;
  var t = len2 <= 0 ? 0.0 : (wx * vx + wy * vy) / len2;
  t = t.clamp(0.0, 1.0);
  final dx = px - (ax + t * vx);
  final dy = py - (ay + t * vy);
  return math.sqrt(dx * dx + dy * dy);
}

/// Point-in-convex-polygon test (vertices in CCW order).
bool _insidePoly(double px, double py, List<List<double>> verts) {
  for (var i = 0; i < verts.length; i++) {
    final a = verts[i];
    final b = verts[(i + 1) % verts.length];
    final cross = (b[0] - a[0]) * (py - a[1]) - (b[1] - a[1]) * (px - a[0]);
    if (cross < 0) return false;
  }
  return true;
}

void main() {
  final master = _renderMaster();

  final dir = Directory(kOutDir);
  if (!dir.existsSync()) {
    stderr.writeln('Output directory not found: $kOutDir\n'
        'Run this from the project root.');
    exitCode = 1;
    return;
  }

  for (final size in kSizes) {
    final resized = img.copyResize(
      master,
      width: size,
      height: size,
      interpolation: img.Interpolation.average,
    );
    final path = '$kOutDir/app_icon_$size.png';
    File(path).writeAsBytesSync(img.encodePng(resized));
    stdout.writeln('wrote $path');
  }
}

img.Image _renderMaster() {
  final n = kMaster;
  final im = img.Image(width: n, height: n, numChannels: 4);

  // Tile geometry (a rounded square with a small transparent margin).
  final margin = n * 0.055;
  final tileHalf = n / 2 - margin;
  final cx = n / 2, cy = n / 2;
  final tileRadius = n * 0.2237; // Apple-ish continuous-corner radius.

  // Diagonal brand gradient (top-left bright blue -> bottom-right deep indigo).
  const top = _Rgb(59, 130, 246); // #3B82F6
  const bot = _Rgb(26, 58, 140); // #1A3A8C

  // Diagram motif, expressed in master-pixel coordinates.
  final s = n / 1024.0; // scale factor from a 1024 design grid
  // Node A (upper-left) and node B (lower-right).
  final aCx = 340.0 * s, aCy = 360.0 * s, aHW = 150.0 * s, aHH = 96.0 * s;
  final bCx = 690.0 * s, bCy = 690.0 * s, bHW = 150.0 * s, bHH = 96.0 * s;
  final nodeR = 34.0 * s;
  final connHalf = 15.0 * s;
  // Elbow: A bottom-center -> down -> right -> B top-center.
  final aBotX = aCx, aBotY = aCy + aHH;
  final bTopX = bCx, bTopY = bCy - bHH;
  final midY = (aBotY + bTopY) / 2;
  // Arrowhead pointing down into node B's top edge.
  final headH = 58.0 * s, headW = 78.0 * s;
  final tipX = bTopX, tipY = bTopY + 2.0 * s;
  final head = <List<double>>[
    <double>[tipX - headW / 2, tipY - headH], // left base
    <double>[tipX, tipY], // tip (bottom)
    <double>[tipX + headW / 2, tipY - headH], // right base
  ];

  for (var y = 0; y < n; y++) {
    final py = y + 0.5;
    for (var x = 0; x < n; x++) {
      final px = x + 0.5;
      if (!_insideRoundRect(px, py, cx, cy, tileHalf, tileHalf, tileRadius)) {
        continue; // transparent outside the tile
      }
      // White motif on top of the gradient?
      final onNode = _insideRoundRect(px, py, aCx, aCy, aHW, aHH, nodeR) ||
          _insideRoundRect(px, py, bCx, bCy, bHW, bHH, nodeR);
      final onConn =
          _segDist(px, py, aBotX, aBotY, aBotX, midY) <= connHalf ||
              _segDist(px, py, aBotX, midY, bTopX, midY) <= connHalf ||
              _segDist(px, py, bTopX, midY, bTopX, tipY - headH * 0.5) <=
                  connHalf;
      final onHead = _insidePoly(px, py, head);
      if (onNode || onConn || onHead) {
        im.setPixelRgba(x, y, 255, 255, 255, 255);
      } else {
        final t = ((px + py) / (2 * n)).clamp(0.0, 1.0);
        final c = _lerp(top, bot, t);
        im.setPixelRgba(x, y, c.r.round(), c.g.round(), c.b.round(), 255);
      }
    }
  }
  return im;
}
