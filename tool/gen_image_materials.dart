// Generates small clipart PNGs for the image-materials palette.
//
// Flat, diagram-friendly icons at 64×64 so they stay tiny in the app bundle
// and insert at a sensible default size (~0.67" at 96 dpi).
//
// Run from the project root:
//   dart run tool/gen_image_materials.dart
//
// Output: assets/materials/*.png
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const int kSize = 64;
const String kOutDir = 'assets/materials';

/// Soft diagram palette (avoid neon / purple defaults).
const int kBlue = 0xFF2F6FED;
const int kBlueDark = 0xFF1E4BB8;
const int kBlueLight = 0xFF6FA0F5;
const int kTeal = 0xFF0F8A7A;
const int kTealDark = 0xFF0A6B5E;
const int kTealLight = 0xFF3BB8A6;
const int kOrange = 0xFFE07A2F;
const int kOrangeLight = 0xFFF0A35A;
const int kRed = 0xFFD64545;
const int kGreen = 0xFF2F9E5C;
const int kGray = 0xFF5A6570;
const int kGrayLight = 0xFFE8ECF1;
const int kWhite = 0xFFFFFFFF;
const int kInk = 0xFF243040;

typedef _Drawer = void Function(img.Image dst);

void main() {
  Directory(kOutDir).createSync(recursive: true);
  final drawers = <String, _Drawer>{
    // People
    'person': _drawPerson,
    'users': _drawUsers,
    'manager': _drawManager,
    'handshake': _drawHandshake,
    // IT
    'server': _drawServer,
    'database': _drawDatabase,
    'cloud': _drawCloud,
    'laptop': _drawLaptop,
    'phone': _drawPhone,
    'globe': _drawGlobe,
    'monitor': _drawMonitor,
    'hard_drive': _drawHardDrive,
    'code': _drawCode,
    // Office
    'document': _drawDocument,
    'folder': _drawFolder,
    'email': _drawEmail,
    'building': _drawBuilding,
    'calendar': _drawCalendar,
    'printer': _drawPrinter,
    'clipboard': _drawClipboard,
    'briefcase': _drawBriefcase,
    'sticky_note': _drawStickyNote,
    // Status
    'lock': _drawLock,
    'warning': _drawWarning,
    'check': _drawCheck,
    'settings': _drawSettings,
    'chart': _drawChart,
    'camera': _drawCamera,
    'info': _drawInfo,
    'cross': _drawCross,
    'star': _drawStar,
    'bell': _drawBell,
    // Network
    'wifi': _drawWifi,
    'router': _drawRouter,
    'firewall': _drawFirewall,
    'api': _drawApi,
    // Business / process
    'lightbulb': _drawLightbulb,
    'target': _drawTarget,
    'flag': _drawFlag,
    'rocket': _drawRocket,
    'clock': _drawClock,
    'package': _drawPackage,
    'map_pin': _drawMapPin,
    'wallet': _drawWallet,
  };

  for (final entry in drawers.entries) {
    final image = img.Image(width: kSize, height: kSize, numChannels: 4);
    img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));
    entry.value(image);
    final path = '$kOutDir/${entry.key}.png';
    File(path).writeAsBytesSync(img.encodePng(image, level: 9));
    final kb = (File(path).lengthSync() / 1024).toStringAsFixed(1);
    stdout.writeln('wrote $path ($kb KB)');
  }
}

img.ColorRgba8 _c(int argb) => img.ColorRgba8(
      (argb >> 16) & 0xFF,
      (argb >> 8) & 0xFF,
      argb & 0xFF,
      (argb >> 24) & 0xFF,
    );

void _circle(img.Image dst, int cx, int cy, int r, int color) {
  img.fillCircle(dst, x: cx, y: cy, radius: r, color: _c(color));
}

/// Axis-aligned fill. Avoid rounded-rect radius: it paints nothing on
/// transparent backgrounds in package:image 4.x.
void _rect(img.Image dst, int x0, int y0, int x1, int y1, int color) {
  img.fillRect(
    dst,
    x1: x0,
    y1: y0,
    x2: x1,
    y2: y1,
    color: _c(color),
    alphaBlend: false,
  );
}

void _drawPerson(img.Image dst) {
  _circle(dst, 32, 18, 10, kBlue);
  // Torso as circle + rect (avoids large rounded-rect radius bugs).
  _circle(dst, 32, 42, 16, kBlue);
  _rect(dst, 16, 42, 48, 58, kBlue);
  _rect(dst, 16, 52, 48, 58, kBlueDark);
}

void _drawUsers(img.Image dst) {
  _circle(dst, 22, 18, 8, kGray);
  _circle(dst, 22, 40, 12, kGray);
  _rect(dst, 10, 40, 34, 52, kGray);
  _circle(dst, 42, 16, 9, kBlue);
  _circle(dst, 42, 40, 14, kBlue);
  _rect(dst, 28, 40, 56, 54, kBlue);
}

void _drawServer(img.Image dst) {
  _rect(dst, 14, 10, 50, 54, kGray);
  for (final y in [16, 28, 40]) {
    _rect(dst, 18, y, 46, y + 8, kGrayLight);
    _circle(dst, 42, y + 4, 2, kGreen);
  }
}

void _drawDatabase(img.Image dst) {
  _rect(dst, 16, 20, 48, 46, kTeal);
  _circle(dst, 32, 20, 16, kTealLight);
  _circle(dst, 32, 46, 16, kTealDark);
  _rect(dst, 16, 20, 48, 46, kTeal);
  _circle(dst, 32, 20, 14, kTealLight);
}

void _drawCloud(img.Image dst) {
  _circle(dst, 22, 34, 12, kBlue);
  _circle(dst, 36, 28, 15, kBlue);
  _circle(dst, 48, 36, 11, kBlue);
  _rect(dst, 12, 34, 56, 48, kBlue);
}

void _drawDocument(img.Image dst) {
  _rect(dst, 16, 8, 48, 56, kWhite);
  img.drawRect(dst, x1: 16, y1: 8, x2: 48, y2: 56, color: _c(kBlueDark));
  // Folded corner.
  for (var i = 0; i < 12; i++) {
    for (var j = 0; j <= i; j++) {
      dst.setPixelRgba(48 - i, 8 + j, 0xE8, 0xEC, 0xF1, 0xFF);
    }
  }
  for (final y in [22, 30, 38, 46]) {
    _rect(dst, 22, y, 40, y + 3, kGrayLight);
  }
}

void _drawFolder(img.Image dst) {
  _rect(dst, 10, 18, 32, 28, kOrangeLight);
  _rect(dst, 10, 24, 54, 52, kOrange);
  _rect(dst, 10, 28, 54, 52, kOrangeLight);
}

void _drawLaptop(img.Image dst) {
  _rect(dst, 14, 14, 50, 40, kInk);
  _rect(dst, 17, 17, 47, 36, kBlue);
  _rect(dst, 10, 40, 54, 48, kGray);
  _rect(dst, 26, 42, 38, 45, kGrayLight);
}

void _drawPhone(img.Image dst) {
  _rect(dst, 22, 8, 42, 56, kInk);
  _rect(dst, 25, 14, 39, 46, kBlue);
  _circle(dst, 32, 51, 2, kGrayLight);
}

void _drawEmail(img.Image dst) {
  _rect(dst, 8, 18, 56, 48, kBlue);
  for (var t = 0; t <= 24; t++) {
    final y = 18 + (t * 14 / 24).round();
    dst.setPixelRgba(8 + t, y, 0xFF, 0xFF, 0xFF, 0xFF);
    dst.setPixelRgba(56 - t, y, 0xFF, 0xFF, 0xFF, 0xFF);
    if (y + 1 < kSize) {
      dst.setPixelRgba(8 + t, y + 1, 0xFF, 0xFF, 0xFF, 0xFF);
      dst.setPixelRgba(56 - t, y + 1, 0xFF, 0xFF, 0xFF, 0xFF);
    }
  }
}

void _drawBuilding(img.Image dst) {
  _rect(dst, 14, 12, 50, 54, kGray);
  for (var row = 0; row < 3; row++) {
    for (var col = 0; col < 3; col++) {
      _rect(
        dst,
        20 + col * 10,
        18 + row * 10,
        26 + col * 10,
        24 + row * 10,
        kGrayLight,
      );
    }
  }
  _rect(dst, 28, 42, 36, 54, kInk);
}

void _drawGlobe(img.Image dst) {
  _circle(dst, 32, 32, 20, kBlue);
  _circle(dst, 32, 32, 16, kBlueLight);
  img.drawCircle(dst, x: 32, y: 32, radius: 20, color: _c(kBlueDark));
  img.drawCircle(dst, x: 32, y: 32, radius: 12, color: _c(kWhite));
  for (var x = 12; x <= 52; x++) {
    dst.setPixelRgba(x, 32, 0xFF, 0xFF, 0xFF, 0xCC);
  }
  for (var y = 12; y <= 52; y++) {
    dst.setPixelRgba(32, y, 0xFF, 0xFF, 0xFF, 0xCC);
  }
}

void _drawLock(img.Image dst) {
  for (var a = 0; a <= 180; a++) {
    final rad = a * math.pi / 180;
    final x = 32 + (11 * math.cos(rad)).round();
    final y = 24 - (11 * math.sin(rad)).round();
    _circle(dst, x, y, 2, kGray);
  }
  _rect(dst, 16, 26, 48, 54, kOrange);
  _circle(dst, 32, 38, 4, kWhite);
  _rect(dst, 30, 38, 34, 48, kWhite);
}

void _drawWarning(img.Image dst) {
  for (var y = 10; y <= 52; y++) {
    final t = (y - 10) / 42;
    final half = (t * 22).round();
    for (var x = 32 - half; x <= 32 + half; x++) {
      dst.setPixelRgba(x, y, 0xE0, 0x7A, 0x2F, 0xFF);
    }
  }
  _rect(dst, 30, 22, 34, 38, kWhite);
  _circle(dst, 32, 44, 2, kWhite);
}

void _drawCheck(img.Image dst) {
  _circle(dst, 32, 32, 22, kGreen);
  for (var i = 0; i < 12; i++) {
    final x = 18 + i;
    final y = 34 + (i * 0.6).round();
    _circle(dst, x, y, 2, kWhite);
  }
  for (var i = 0; i < 18; i++) {
    final x = 28 + i;
    final y = 42 - i;
    _circle(dst, x, y, 2, kWhite);
  }
}

void _drawSettings(img.Image dst) {
  _circle(dst, 32, 32, 14, kGray);
  for (var i = 0; i < 8; i++) {
    final a = i * math.pi / 4;
    final x = 32 + (20 * math.cos(a)).round();
    final y = 32 + (20 * math.sin(a)).round();
    _rect(dst, x - 3, y - 3, x + 3, y + 3, kGray);
  }
  _circle(dst, 32, 32, 7, kGrayLight);
  _circle(dst, 32, 32, 4, kInk);
}

void _drawCalendar(img.Image dst) {
  _rect(dst, 12, 14, 52, 52, kWhite);
  _rect(dst, 12, 14, 52, 26, kRed);
  _rect(dst, 12, 22, 52, 26, kRed);
  for (final x in [22, 32, 42]) {
    _rect(dst, x - 1, 10, x + 1, 18, kGray);
  }
  for (var row = 0; row < 3; row++) {
    for (var col = 0; col < 3; col++) {
      _rect(
        dst,
        18 + col * 11,
        30 + row * 7,
        24 + col * 11,
        34 + row * 7,
        kGrayLight,
      );
    }
  }
}

void _drawChart(img.Image dst) {
  _rect(dst, 10, 10, 54, 54, kGrayLight);
  _rect(dst, 16, 36, 24, 48, kBlue);
  _rect(dst, 28, 24, 36, 48, kTeal);
  _rect(dst, 40, 16, 48, 48, kOrange);
}

void _drawPrinter(img.Image dst) {
  _rect(dst, 20, 8, 44, 20, kGrayLight);
  _rect(dst, 12, 20, 52, 42, kGray);
  _rect(dst, 18, 38, 46, 54, kWhite);
  _circle(dst, 44, 28, 2, kGreen);
  for (final y in [44, 48]) {
    _rect(dst, 22, y, 42, y + 2, kGrayLight);
  }
}

void _drawCamera(img.Image dst) {
  _rect(dst, 10, 22, 54, 50, kInk);
  _rect(dst, 24, 14, 40, 24, kInk);
  _circle(dst, 32, 36, 10, kBlue);
  _circle(dst, 32, 36, 5, kBlueDark);
  _circle(dst, 46, 28, 2, kRed);
}

void _drawManager(img.Image dst) {
  _circle(dst, 32, 16, 9, kInk);
  _circle(dst, 32, 40, 15, kBlue);
  _rect(dst, 17, 40, 47, 56, kBlue);
  // Tie.
  for (var y = 28; y <= 48; y++) {
    final half = y < 36 ? 2 : 3;
    _rect(dst, 32 - half, y, 32 + half, y + 1, kOrange);
  }
}

void _drawHandshake(img.Image dst) {
  _rect(dst, 8, 28, 30, 42, kBlue);
  _rect(dst, 34, 28, 56, 42, kTeal);
  _rect(dst, 22, 24, 42, 46, kGrayLight);
  _rect(dst, 18, 30, 46, 40, kOrange);
}

void _drawMonitor(img.Image dst) {
  _rect(dst, 10, 10, 54, 42, kInk);
  _rect(dst, 14, 14, 50, 36, kBlue);
  _rect(dst, 28, 42, 36, 50, kGray);
  _rect(dst, 20, 50, 44, 54, kGray);
}

void _drawHardDrive(img.Image dst) {
  _rect(dst, 10, 18, 54, 48, kGray);
  _rect(dst, 14, 24, 50, 30, kGrayLight);
  _circle(dst, 44, 38, 3, kGreen);
  _circle(dst, 34, 38, 3, kGrayLight);
}

void _drawCode(img.Image dst) {
  _rect(dst, 10, 10, 54, 54, kInk);
  // </ >
  for (var i = 0; i < 10; i++) {
    _circle(dst, 20 + i, 22 + i, 2, kTealLight);
    _circle(dst, 20 + i, 42 - i, 2, kTealLight);
    _circle(dst, 44 - i, 22 + i, 2, kOrange);
    _circle(dst, 44 - i, 42 - i, 2, kOrange);
  }
  _rect(dst, 30, 18, 34, 46, kBlueLight);
}

void _drawClipboard(img.Image dst) {
  _rect(dst, 16, 12, 48, 56, kGrayLight);
  img.drawRect(dst, x1: 16, y1: 12, x2: 48, y2: 56, color: _c(kGray));
  _rect(dst, 24, 8, 40, 18, kOrange);
  for (final y in [26, 34, 42, 50]) {
    _rect(dst, 22, y, 42, y + 3, kBlue);
  }
}

void _drawBriefcase(img.Image dst) {
  _rect(dst, 24, 12, 40, 22, kGray);
  _rect(dst, 10, 20, 54, 50, kOrange);
  _rect(dst, 10, 32, 54, 38, kOrangeLight);
  _rect(dst, 28, 30, 36, 40, kInk);
}

void _drawStickyNote(img.Image dst) {
  _rect(dst, 14, 12, 52, 52, 0xFFFFE08A);
  _rect(dst, 14, 12, 52, 20, 0xFFFFD24A);
  for (final y in [28, 36, 44]) {
    _rect(dst, 22, y, 44, y + 3, 0xFFE0B84A);
  }
}

void _drawInfo(img.Image dst) {
  _circle(dst, 32, 32, 22, kBlue);
  _circle(dst, 32, 18, 3, kWhite);
  _rect(dst, 29, 26, 35, 48, kWhite);
}

void _drawCross(img.Image dst) {
  _circle(dst, 32, 32, 22, kRed);
  for (var i = 0; i < 18; i++) {
    _circle(dst, 22 + i, 22 + i, 2, kWhite);
    _circle(dst, 42 - i, 22 + i, 2, kWhite);
  }
}

void _drawStar(img.Image dst) {
  // Simple 5-point approximation via overlapping triangles / diamonds.
  final pts = <List<int>>[
    [32, 8],
    [38, 24],
    [54, 24],
    [42, 36],
    [46, 52],
    [32, 42],
    [18, 52],
    [22, 36],
    [10, 24],
    [26, 24],
  ];
  for (final p in pts) {
    _circle(dst, p[0], p[1], 5, 0xFFF5C518);
  }
  _circle(dst, 32, 30, 10, 0xFFF5C518);
}

void _drawBell(img.Image dst) {
  _circle(dst, 32, 20, 8, kOrange);
  _rect(dst, 18, 20, 46, 40, kOrange);
  _circle(dst, 32, 40, 14, kOrange);
  _rect(dst, 14, 40, 50, 46, kOrangeLight);
  _circle(dst, 32, 50, 3, kInk);
}

void _drawWifi(img.Image dst) {
  // Thick upper arcs + hotspot.
  for (final r in [10, 16, 22]) {
    for (var t = 0; t <= 180; t++) {
      final rad = t * math.pi / 180;
      final x = 32 + (r * math.cos(rad)).round();
      final y = 44 - (r * math.sin(rad)).round();
      _circle(dst, x, y, 2, kBlue);
    }
  }
  _circle(dst, 32, 46, 4, kBlue);
}

void _drawRouter(img.Image dst) {
  _rect(dst, 10, 28, 54, 50, kGray);
  _circle(dst, 20, 39, 3, kGreen);
  _circle(dst, 30, 39, 3, kGrayLight);
  _rect(dst, 18, 10, 22, 30, kInk);
  _rect(dst, 42, 10, 46, 30, kInk);
  _circle(dst, 20, 10, 3, kInk);
  _circle(dst, 44, 10, 3, kInk);
}

void _drawFirewall(img.Image dst) {
  _rect(dst, 12, 12, 52, 52, kRed);
  for (final y in [20, 30, 40]) {
    _rect(dst, 12, y, 52, y + 4, kOrange);
  }
  _rect(dst, 28, 22, 36, 48, kInk);
}

void _drawApi(img.Image dst) {
  _circle(dst, 18, 32, 8, kTeal);
  _circle(dst, 46, 32, 8, kBlue);
  _rect(dst, 24, 28, 40, 36, kGrayLight);
  _rect(dst, 30, 18, 34, 46, kOrange);
}

void _drawLightbulb(img.Image dst) {
  _circle(dst, 32, 26, 16, 0xFFF5C518);
  _rect(dst, 24, 36, 40, 44, 0xFFF5C518);
  _rect(dst, 26, 44, 38, 54, kGray);
  _rect(dst, 28, 50, 36, 56, kGrayLight);
}

void _drawTarget(img.Image dst) {
  _circle(dst, 32, 32, 22, kRed);
  _circle(dst, 32, 32, 15, kWhite);
  _circle(dst, 32, 32, 9, kRed);
  _circle(dst, 32, 32, 4, kInk);
}

void _drawFlag(img.Image dst) {
  _rect(dst, 16, 8, 20, 56, kGray);
  _rect(dst, 20, 10, 50, 30, kBlue);
  _rect(dst, 20, 30, 50, 34, kBlueDark);
}

void _drawRocket(img.Image dst) {
  _circle(dst, 32, 16, 8, kBlue);
  _rect(dst, 24, 16, 40, 42, kBlue);
  _rect(dst, 18, 36, 26, 48, kOrange);
  _rect(dst, 38, 36, 46, 48, kOrange);
  _rect(dst, 28, 42, 36, 56, kRed);
}

void _drawClock(img.Image dst) {
  _circle(dst, 32, 32, 22, kGrayLight);
  img.drawCircle(dst, x: 32, y: 32, radius: 22, color: _c(kGray));
  _rect(dst, 30, 18, 34, 34, kInk);
  _rect(dst, 30, 30, 46, 34, kInk);
  _circle(dst, 32, 32, 3, kOrange);
}

void _drawPackage(img.Image dst) {
  _rect(dst, 12, 22, 52, 52, kOrange);
  _rect(dst, 12, 22, 52, 34, kOrangeLight);
  _rect(dst, 30, 22, 34, 52, kInk);
  _rect(dst, 12, 32, 52, 36, kInk);
}

void _drawMapPin(img.Image dst) {
  _circle(dst, 32, 24, 14, kRed);
  _circle(dst, 32, 24, 6, kWhite);
  for (var y = 32; y <= 54; y++) {
    final t = (y - 32) / 22;
    final half = ((1 - t) * 10).round().clamp(1, 10);
    _rect(dst, 32 - half, y, 32 + half, y + 1, kRed);
  }
}

void _drawWallet(img.Image dst) {
  _rect(dst, 10, 18, 54, 50, kTeal);
  _rect(dst, 10, 18, 54, 28, kTealDark);
  _rect(dst, 36, 30, 52, 42, kTealLight);
  _circle(dst, 44, 36, 3, kOrange);
}
