import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/render/vsdx_painter.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('embedded pictures use LibreOffice-quality sampling', () {
    expect(VsdxPainter.imageFilterQuality, FilterQuality.high);
  });

  test('classic zero-blur shadows keep a hard libvisio edge', () async {
    const pxPerInch = 1000.0;
    VsdxPage page(double blurInches) => VsdxPage(
          id: 0,
          name: 'Classic shadow',
          widthInches: 1,
          heightInches: 1,
          shapes: <VsdxShape>[
            VsdxShapeFactory.rectangle(
              id: 1,
              pinX: 0.4,
              pinY: 0.5,
              width: 0.4,
              height: 0.4,
            ).copyWith(
              fill: const VsdxFill(
                foreground: VsdxColor(0xFF0000FF),
              ),
              line: const VsdxLine(pattern: 0),
              shadow: VsdxShadow(
                enabled: true,
                color: const VsdxColor(0xFFFF0000),
                offsetXInches: 0.2,
                blurInches: blurInches,
              ),
            ),
          ],
        );

    final hard = await _rasterPage(page(0), pxPerInch: pxPerInch);
    final softlyFiltered =
        await _rasterPage(page(0.001), pxPerInch: pxPerInch);
    const outsideShadow = (500 * 1000 + 802) * 4;
    expect(hard.sublist(outsideShadow, outsideShadow + 4),
        orderedEquals(<int>[255, 255, 255, 255]));
    expect(softlyFiltered[outsideShadow + 1], lessThan(255),
        reason: 'a real non-zero blur must still produce a soft fringe');
  });

  test('sub-pixel Visio strokes render as crisp device hairlines', () async {
    const pxPerInch = 144.0;
    final shape = VsdxShape(
      id: 1,
      name: 'Hairline',
      pinX: 2,
      pinY: 2,
      width: 3,
      height: 1,
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(color: VsdxColor(0xFFC0C0C0), weightInches: 0.0035),
      geometries: const <VsdxGeometry>[
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[MoveTo(0, 0.503), LineTo(3, 0.503)],
        ),
      ],
    );
    final rgba = await _rasterPage(
      VsdxPage(
        id: 0,
        name: 'Hairline',
        widthInches: 4,
        heightInches: 4,
        shapes: <VsdxShape>[shape],
      ),
      pxPerInch: pxPerInch,
    );

    var exactSourcePixels = 0;
    for (var y = 284; y <= 292; y++) {
      for (var x = 70; x < 506; x++) {
        final offset = (y * 576 + x) * 4;
        if (rgba[offset] == 0xC0 &&
            rgba[offset + 1] == 0xC0 &&
            rgba[offset + 2] == 0xC0 &&
            rgba[offset + 3] == 0xFF) {
          exactSourcePixels++;
        }
      }
    }
    expect(exactSourcePixels, greaterThan(400));
  });

  test('sub-pixel crow-foot markers retain crisp outward strokes', () async {
    const pxPerInch = 144.0;
    final shape = VsdxShapeFactory.line(
      id: 1,
      ax: 1,
      ay: 2,
      bx: 3,
      by: 2,
    ).copyWith(
      line: const VsdxLine(
        color: VsdxColor(0xFF000000),
        weightInches: 0.0035,
        endArrow: 27,
      ),
    );
    final rgba = await _rasterPage(
      VsdxPage(
        id: 0,
        name: 'Hairline crow-foot',
        widthInches: 4,
        heightInches: 4,
        shapes: <VsdxShape>[shape],
      ),
      pxPerInch: pxPerInch,
    );

    // The authored endpoint is x=3in (432px). libvisio markers 27–30 are
    // reverse markers, so their ink must remain crisp beyond that endpoint.
    var exactBlackOutsideEndpoint = 0;
    for (var y = 270; y <= 306; y++) {
      for (var x = 433; x <= 456; x++) {
        final offset = (y * 576 + x) * 4;
        if (rgba[offset] == 0 &&
            rgba[offset + 1] == 0 &&
            rgba[offset + 2] == 0 &&
            rgba[offset + 3] == 0xFF) {
          exactBlackOutsideEndpoint++;
        }
      }
    }
    expect(exactBlackOutsideEndpoint, greaterThan(10));
  });

  test(
    'paragraph layout keeps TextBkgnd and centred vertical overflow',
    () async {
      const pxPerInch = 144.0;
      final shape =
          VsdxShapeFactory.rectangle(
            id: 1,
            pinX: 2,
            pinY: 2,
            width: 2,
            height: 0.8,
          ).copyWith(
            fill: const VsdxFill(pattern: 0),
            line: const VsdxLine(pattern: 0),
            richText: const VsdxRichText(
              runs: <VsdxTextRun>[
                VsdxTextRun(
                  text: 'MMMM\nMMMM\nMMMM\nMMMM\nMMMM',
                  charStyle: VsdxCharStyle(
                    fontFamily: 'Arial',
                    fontSizeInches: 12 / 72,
                  ),
                  paraStyle: VsdxParaStyle(lineSpacing: 1.2),
                ),
              ],
              textBlock: VsdxTextBlock(
                verticalAlign: VsdxVertAlign.middle,
                marginLeftInches: 0.05,
                marginRightInches: 0.05,
                marginTopInches: 0.05,
                marginBottomInches: 0.05,
                backgroundColor: VsdxColor(0xFFC5BED8),
              ),
            ),
          );
      final rgba = await _rasterPage(
        VsdxPage(
          id: 0,
          name: 'Text overflow',
          widthInches: 4,
          heightInches: 4,
          shapes: <VsdxShape>[shape],
        ),
        pxPerInch: pxPerInch,
      );

      final highlightedRows = <int>[];
      for (var y = 180; y < 360; y++) {
        var purplePixels = 0;
        for (var x = 140; x < 430; x++) {
          final offset = (y * 576 + x) * 4;
          final red = rgba[offset];
          final green = rgba[offset + 1];
          final blue = rgba[offset + 2];
          if (blue > red + 5 && blue > green + 5 && red > 120) {
            purplePixels++;
          }
        }
        if (purplePixels > 5) highlightedRows.add(y);
      }
      final bands = <List<int>>[];
      for (final row in highlightedRows) {
        if (bands.isEmpty || row > bands.last.last + 1) {
          bands.add(<int>[row]);
        } else {
          bands.last.add(row);
        }
      }

      expect(bands, hasLength(5));
      final centres = bands
          .map((band) => (band.first + band.last) / 2)
          .toList(growable: false);
      for (var i = 1; i < centres.length; i++) {
        expect(centres[i] - centres[i - 1], closeTo(32, 1));
      }
      const shapeTopPx = (4 - (2 + 0.8 / 2)) * pxPerInch;
      expect(
        bands.first.first,
        lessThan(shapeTopPx),
        reason: 'centred overflow should extend above the text box',
      );
    },
  );

  test('group text is composited above filled children like libvisio', () async {
    const pxPerInch = 144.0;
    final child = VsdxShapeFactory.rectangle(
      id: 2,
      pinX: 1,
      pinY: 0.5,
      width: 2,
      height: 1,
    ).copyWith(
      fill: const VsdxFill(
        pattern: 1,
        foreground: VsdxColor(0xFF000000),
      ),
      line: const VsdxLine(pattern: 0),
    );
    final group = VsdxShape(
      id: 1,
      name: 'Group',
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 1,
      children: <VsdxShape>[child],
      richText: const VsdxRichText(
        runs: <VsdxTextRun>[
          VsdxTextRun(
            text: 'GROUP LABEL',
            charStyle: VsdxCharStyle(
              color: VsdxColor(0xFFFF0000),
              fontFamily: 'Arial',
              fontSizeInches: 18 / 72,
            ),
          ),
        ],
        textBlock: VsdxTextBlock(
          marginLeftInches: 0,
          marginRightInches: 0,
          marginTopInches: 0,
          marginBottomInches: 0,
        ),
      ),
    );
    final rgba = await _rasterPage(
      VsdxPage(
        id: 0,
        name: 'Group text order',
        widthInches: 4,
        heightInches: 4,
        shapes: <VsdxShape>[group],
      ),
      pxPerInch: pxPerInch,
    );

    var redPixels = 0;
    for (var offset = 0; offset < rgba.length; offset += 4) {
      if (rgba[offset] > 180 &&
          rgba[offset + 1] < 80 &&
          rgba[offset + 2] < 80 &&
          rgba[offset + 3] > 200) {
        redPixels++;
      }
    }
    expect(redPixels, greaterThan(100));
  });
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
