// Generates the branded app icon for every Flutter platform.
//
// The icon is a rounded blue tile carrying a white flow-diagram motif (two
// nodes joined by an orthogonal connector with an arrowhead) — a nod to the
// Visio diagrams the app edits. It is rendered at high resolution with simple
// boolean fills, then box-downsampled to every required size so the edges come
// out anti-aliased without hand-rolling coverage maths.
//
// macOS keeps the rounded tile with a transparent margin (desktop dock).
// Android / iOS / Web / Windows / Linux use a full-bleed square so the OS
// (or adaptive-icon mask) can apply its own shape.
//
// Run from the project root:
//   dart run tool/gen_app_icon.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// Supersampled master resolution; downsampling from here yields the AA.
const int kMaster = 2048;

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

img.Image _resize(img.Image src, int size) => img.copyResize(
      src,
      width: size,
      height: size,
      interpolation: img.Interpolation.average,
    );

void _writePng(String path, img.Image image) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(img.encodePng(image));
  stdout.writeln('wrote $path');
}

void main() {
  final rounded = _renderMaster(roundedTile: true);
  final square = _renderMaster(roundedTile: false);

  _writeMacos(rounded);
  _writeAndroid(square);
  _writeIos(square);
  _writeWeb(square);
  _writeWindows(square);
  _writeLinux(square);
}

void _writeMacos(img.Image master) {
  const outDir = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';
  if (!Directory(outDir).existsSync()) {
    stderr.writeln('Missing $outDir — run from the project root.');
    exitCode = 1;
    return;
  }
  for (final size in <int>[16, 32, 64, 128, 256, 512, 1024]) {
    _writePng('$outDir/app_icon_$size.png', _resize(master, size));
  }
}

void _writeAndroid(img.Image master) {
  // Classic density mipmaps (full-bleed; the launcher applies its own mask).
  const densities = <(String, int)>[
    ('mipmap-mdpi', 48),
    ('mipmap-hdpi', 72),
    ('mipmap-xhdpi', 96),
    ('mipmap-xxhdpi', 144),
    ('mipmap-xxxhdpi', 192),
  ];
  for (final (dir, size) in densities) {
    _writePng(
      'android/app/src/main/res/$dir/ic_launcher.png',
      _resize(master, size),
    );
  }

  // Adaptive icon layers (API 26+): solid brand blue + full-bleed artwork.
  // Foreground is inset slightly so the motif stays inside the safe zone.
  const fgSizes = <(String, int)>[
    ('drawable-mdpi', 108),
    ('drawable-hdpi', 162),
    ('drawable-xhdpi', 216),
    ('drawable-xxhdpi', 324),
    ('drawable-xxxhdpi', 432),
  ];
  for (final (dir, size) in fgSizes) {
    final inset = (size * 0.12).round();
    final fg = img.Image(width: size, height: size, numChannels: 4);
    final scaled = _resize(master, size - inset * 2);
    img.compositeImage(fg, scaled, dstX: inset, dstY: inset);
    _writePng(
      'android/app/src/main/res/$dir/ic_launcher_foreground.png',
      fg,
    );
  }

  File('android/app/src/main/res/values/ic_launcher_background.xml')
    ..createSync(recursive: true)
    ..writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#3B82F6</color>
</resources>
''');
  stdout.writeln(
      'wrote android/app/src/main/res/values/ic_launcher_background.xml');

  File('android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml')
    ..createSync(recursive: true)
    ..writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>
</adaptive-icon>
''');
  stdout.writeln(
      'wrote android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml');
}

void _writeIos(img.Image master) {
  const outDir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
  if (!Directory(outDir).existsSync()) {
    stderr.writeln('Missing $outDir');
    exitCode = 1;
    return;
  }
  // (filename, pixel size) — matches Contents.json.
  const entries = <(String, int)>[
    ('Icon-App-20x20@1x.png', 20),
    ('Icon-App-20x20@2x.png', 40),
    ('Icon-App-20x20@3x.png', 60),
    ('Icon-App-29x29@1x.png', 29),
    ('Icon-App-29x29@2x.png', 58),
    ('Icon-App-29x29@3x.png', 87),
    ('Icon-App-40x40@1x.png', 40),
    ('Icon-App-40x40@2x.png', 80),
    ('Icon-App-40x40@3x.png', 120),
    ('Icon-App-60x60@2x.png', 120),
    ('Icon-App-60x60@3x.png', 180),
    ('Icon-App-76x76@1x.png', 76),
    ('Icon-App-76x76@2x.png', 152),
    ('Icon-App-83.5x83.5@2x.png', 167),
    ('Icon-App-1024x1024@1x.png', 1024),
  ];
  for (final (name, size) in entries) {
    _writePng('$outDir/$name', _resize(master, size));
  }
}

void _writeWeb(img.Image master) {
  _writePng('web/favicon.png', _resize(master, 32));
  _writePng('web/icons/Icon-192.png', _resize(master, 192));
  _writePng('web/icons/Icon-512.png', _resize(master, 512));

  // Maskable icons: keep content inside the center ~80% safe zone.
  for (final size in <int>[192, 512]) {
    final pad = (size * 0.1).round();
    final canvas = img.Image(width: size, height: size, numChannels: 4);
    // Fill with brand blue so the maskable safe-zone background is solid.
    img.fill(canvas, color: img.ColorRgba8(59, 130, 246, 255));
    final scaled = _resize(master, size - pad * 2);
    img.compositeImage(canvas, scaled, dstX: pad, dstY: pad);
    _writePng('web/icons/Icon-maskable-$size.png', canvas);
  }
}

void _writeWindows(img.Image master) {
  final sizes = <int>[16, 32, 48, 64, 128, 256];
  final ico = _resize(master, sizes.first);
  for (final size in sizes.skip(1)) {
    ico.addFrame(_resize(master, size));
  }
  const path = 'windows/runner/resources/app_icon.ico';
  File(path).writeAsBytesSync(img.encodeIco(ico));
  stdout.writeln('wrote $path');
}

void _writeLinux(img.Image master) {
  // Desktop entry Icon=visioeditor → install as visioeditor.png / .svg into
  // hicolor; ship a 512px PNG next to the packaging files.
  _writePng('linux/packaging/visioeditor.png', _resize(master, 512));
}

/// [roundedTile]: macOS-style continuous corner with a transparent margin.
/// Otherwise fills the whole square (Android / iOS / Web / Windows / Linux).
img.Image _renderMaster({required bool roundedTile}) {
  final n = kMaster;
  final im = img.Image(width: n, height: n, numChannels: 4);

  final margin = roundedTile ? n * 0.055 : 0.0;
  final tileHalf = n / 2 - margin;
  final cx = n / 2, cy = n / 2;
  final tileRadius = roundedTile ? n * 0.2237 : 0.0;

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
      if (roundedTile &&
          !_insideRoundRect(px, py, cx, cy, tileHalf, tileHalf, tileRadius)) {
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
