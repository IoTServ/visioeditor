import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/render/vsdx_painter.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Canvas bullet uses label field, body colour, and alphabetic baseline',
    () async {
      const pxPerInch = 100.0;
      final shape =
          VsdxShapeFactory.rectangle(
            id: 1,
            pinX: 2,
            pinY: 1.5,
            width: 3,
            height: 1.5,
          ).copyWith(
            fill: const VsdxFill(pattern: 0),
            line: const VsdxLine(pattern: 0),
            richText: VsdxRichText(
              runs: <VsdxTextRun>[
                VsdxTextRun(
                  text: 'Alpha Alpha Alpha Alpha Alpha',
                  charStyle: VsdxCharStyle.defaults.copyWith(
                    fontSizeInches: 0.2,
                    color: const VsdxColor(0xFF1565C0),
                  ),
                  paraStyle: const VsdxParaStyle(
                    horizontalAlign: VsdxHorzAlign.left,
                    bullet: 1,
                    bulletStr: 'W',
                    bulletFontSizeInches: -0.5,
                    textPosAfterBulletInches: 1.0,
                  ),
                ),
              ],
              textBlock: const VsdxTextBlock(verticalAlign: VsdxVertAlign.top),
            ),
          );
      final rgba = await _rasterPage(
        VsdxPage(
          id: 0,
          name: 'Bullet',
          widthInches: 4,
          heightInches: 3,
          shapes: <VsdxShape>[shape],
        ),
        pxPerInch: pxPerInch,
      );

      bool isBlue(int x, int y) {
        final offset = (y * 400 + x) * 4;
        final red = rgba[offset];
        final green = rgba[offset + 1];
        final blue = rgba[offset + 2];
        return blue > red + 40 && blue > green + 40;
      }

      List<List<int>> rowBands(int minX, int maxX) {
        final rows = <int>[];
        for (var y = 0; y < 300; y++) {
          if ([for (var x = minX; x < maxX; x++) x].any((x) => isBlue(x, y))) {
            rows.add(y);
          }
        }
        final bands = <List<int>>[];
        for (final row in rows) {
          if (bands.isEmpty || row > bands.last.last + 1) {
            bands.add(<int>[row]);
          } else {
            bands.last.add(row);
          }
        }
        return bands;
      }

      int minBlueX(int minX, int maxX, List<int> rows) {
        var result = maxX;
        for (final y in rows) {
          for (var x = minX; x < maxX; x++) {
            if (isBlue(x, y) && x < result) result = x;
          }
        }
        return result;
      }

      final bulletBands = rowBands(45, 120);
      final bodyBands = rowBands(140, 350);
      expect(bulletBands, hasLength(1));
      expect(bodyBands.length, greaterThanOrEqualTo(2));
      final bulletX = minBlueX(45, 120, bulletBands.first);
      final firstBodyX = minBlueX(140, 350, bodyBands.first);
      final secondBodyX = minBlueX(140, 350, bodyBands[1]);
      expect(firstBodyX - bulletX, closeTo(100, 3));
      expect(secondBodyX, closeTo(firstBodyX, 2));
      expect(
        bulletBands.first.last,
        closeTo(bodyBands.first.last, 4),
        reason: 'small bullet and body capitals should share a baseline',
      );
    },
  );
}

Future<Uint8List> _rasterPage(
  VsdxPage page, {
  required double pxPerInch,
}) async {
  final width = (page.widthInches * pxPerInch).round();
  final height = (page.heightInches * pxPerInch).round();
  final recorder = ui.PictureRecorder();
  VsdxPainter(
    page: page,
    pxPerInch: pxPerInch,
    drawEditorChrome: false,
    drawPageBorder: false,
    drawPlaceholders: false,
    drawNameFallback: false,
  ).paint(Canvas(recorder), Size(width.toDouble(), height.toDouble()));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}
