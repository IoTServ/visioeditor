import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/io/image_export.dart';
import 'package:visioeditor/render/pattern_fill.dart';
import 'package:visioeditor/render/vsdx_painter.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('warmUpShared enables hatch when painter has empty builder', () async {
    await PatternFillBuilder.warmUpShared();
    expect(PatternFillBuilder.shared.hasTiles, isTrue);
    for (var pattern = 2; pattern <= 24; pattern++) {
      expect(PatternFillBuilder.shared.tileFor(pattern), isNotNull,
          reason: 'libvisio FillPattern $pattern must have a canvas tile');
    }
    expect(
      PatternFillBuilder.shared.overlayPaintFor(
        8,
        foreground: const ui.Color(0xFF000000),
      ),
      isNotNull,
      reason: 'triple hatch needs an independently spaced diagonal layer',
    );
    expect(
      PatternFillBuilder.shared.overlayPaintFor(
        2,
        foreground: const ui.Color(0xFF000000),
      ),
      isNull,
    );
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 2,
    ).copyWith(
      fill: const VsdxFill(
        pattern: 2,
        foreground: VsdxColor(0xFF000000),
        background: VsdxColor(0xFFFFFFFF),
      ),
      line: const VsdxLine(pattern: 0),
    );
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 4,
      heightInches: 4,
      shapes: <VsdxShape>[shape],
    );
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    // Explicit empty builder — must still resolve via PatternFillBuilder.shared.
    VsdxPainter(
      page: page,
      patternBuilder: PatternFillBuilder.empty,
      pxPerInch: 40,
      backgroundColor: const ui.Color(0xFFFFFFFF),
    ).paint(canvas, const ui.Size(160, 160));
    final picture = recorder.endRecording();
    final image = await picture.toImage(160, 160);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    expect(bytes, isNotNull);
    // 45-degree hatch (libvisio pattern 2): scan the AABB for black ink.
    final rgba = bytes!.buffer.asUint8List();
    var dark = 0;
    for (var y = 40; y < 120; y++) {
      for (var x = 40; x < 120; x++) {
        final i = (y * 160 + x) * 4;
        if (rgba[i] < 180 && rgba[i + 1] < 180 && rgba[i + 2] < 180) dark++;
      }
    }
    expect(dark, greaterThan(50),
        reason: 'shared hatch tiles must paint FillPattern=2 on canvas');
  });

  test('pattern fill respects FillBkgndTrans on canvas', () async {
    final patterns = await PatternFillBuilder.warmUp();
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 2,
    ).copyWith(
      fill: const VsdxFill(
        pattern: 2,
        foreground: VsdxColor(0xFF000000),
        background: VsdxColor(0xFFFF0000),
        backgroundTransparency: 1.0, // fully transparent bkgnd
        foregroundTransparency: 0.0,
      ),
      line: const VsdxLine(pattern: 0),
    );
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 4,
      heightInches: 4,
      shapes: <VsdxShape>[shape],
    );

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    VsdxPainter(
      page: page,
      patternBuilder: patterns,
      pxPerInch: 40,
      backgroundColor: const ui.Color(0xFFFFFFFF),
    ).paint(canvas, const ui.Size(160, 160));
    final picture = recorder.endRecording();
    final image = await picture.toImage(160, 160);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    expect(bytes, isNotNull);

    // Sample centre pixel: must not be opaque red (bkgnd fully transparent).
    final rgba = bytes!.buffer.asUint8List();
    final i = (80 * 160 + 80) * 4;
    final r = rgba[i];
    final g = rgba[i + 1];
    final b = rgba[i + 2];
    expect(r > 200 && g < 40 && b < 40, isFalse,
        reason: 'centre was opaque red ($r,$g,$b) despite FillBkgndTrans=1');
  });

  test('geometryless 1D connector applies LineGradient on canvas', () async {
    final shape = VsdxShapeFactory.line(
      id: 1,
      ax: 0.5,
      ay: 2,
      bx: 3.5,
      by: 2,
      line: VsdxLine(
        weightInches: 0.08,
        color: const VsdxColor(0xFF000000),
        gradient: VsdxGradient(
          type: VsdxGradientType.linear,
          angleRad: 0,
          stops: const <VsdxGradientStop>[
            VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
            VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
          ],
        ),
      ),
    ).copyWith(geometries: const <VsdxGeometry>[]);
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 4,
      heightInches: 4,
      shapes: <VsdxShape>[shape],
    );
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    VsdxPainter(
      page: page,
      patternBuilder: PatternFillBuilder.empty,
      pxPerInch: 40,
      backgroundColor: const ui.Color(0xFFFFFFFF),
    ).paint(canvas, const ui.Size(160, 160));
    final picture = recorder.endRecording();
    final image = await picture.toImage(160, 160);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    expect(bytes, isNotNull);
    final rgba = bytes!.buffer.asUint8List();
    // Sample near begin (left) and end (right) of the horizontal connector.
    int at(int x, int y) => (y * 160 + x) * 4;
    final leftR = rgba[at(30, 80)];
    final rightB = rgba[at(130, 80) + 2];
    expect(leftR, greaterThan(80), reason: 'left should pick up red stop');
    expect(rightB, greaterThan(80), reason: 'right should pick up blue stop');
  });

  test('theme shadow colour resolves on paint', () async {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.5,
      height: 1.5,
    ).copyWith(
      fill: const VsdxFill(foreground: VsdxColor(0xFFFFFFFF)),
      shadow: const VsdxShadow(
        themeColorIndex: ThemeSlot.accent1,
        offsetXInches: 0.15,
        offsetYInches: -0.15,
        blurInches: 0.02,
        transparency: 0.0,
      ),
    );
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 4,
      heightInches: 4,
      shapes: <VsdxShape>[shape],
    );
    final png = await renderPageToPng(
      page,
      theme: VsdxTheme.office,
      pxPerInch: 50,
    );
    expect(png, isNotNull);
    expect(png!.length, greaterThan(200));
  });
}
