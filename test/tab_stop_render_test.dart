import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vsdx/vsdx.dart';

import 'package:visioeditor/render/vsdx_painter.dart';

void main() {
  test('canvas uses parsed Visio tab-stop positions', () async {
    VsdxShape tabbed(double position) => VsdxShapeFactory.rectangle(
          id: 1,
          pinX: 2,
          pinY: 0.6,
          width: 4,
          height: 1,
        ).copyWith(
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(pattern: 0),
          richText: VsdxRichText(
            runs: const <VsdxTextRun>[
              VsdxTextRun(
                text: 'A\tB',
                tabIndices: <int>[2],
                charStyle: VsdxCharStyle(fontSizeInches: 0.3),
              ),
            ],
            textBlock: const VsdxTextBlock(
              verticalAlign: VsdxVertAlign.top,
              marginLeftInches: 0,
              marginRightInches: 0,
              marginTopInches: 0,
              marginBottomInches: 0,
            ),
            tabSets: <VsdxTabSet>[
              VsdxTabSet(
                ix: 2,
                stops: <VsdxTabStop>[
                  VsdxTabStop(positionInches: position),
                ],
              ),
            ],
          ),
        );

    Future<List<int>> raster(VsdxShape shape) async {
      final page = VsdxPage(
        id: 0,
        name: 'Tabs',
        widthInches: 4,
        heightInches: 1.2,
        shapes: <VsdxShape>[shape],
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      VsdxPainter(page: page, pxPerInch: 100)
          .paint(canvas, const Size(400, 120));
      final picture = recorder.endRecording();
      final image = await picture.toImage(400, 120);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final bytes = data!.buffer.asUint8List().toList(growable: false);
      image.dispose();
      picture.dispose();
      return bytes;
    }

    final near = await raster(tabbed(0.7));
    final far = await raster(tabbed(2.5));
    expect(far, isNot(equals(near)),
        reason: 'changing PositionN must move the field after the tab');
  });

  test('canvas wraps a tab field that overflows its text band', () async {
    final shape = VsdxShapeFactory.rectangle(
      id: 1,
      pinX: 1.2,
      pinY: 0.5,
      width: 2.4,
      height: 1,
    ).copyWith(
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
      richText: const VsdxRichText(
        runs: <VsdxTextRun>[
          VsdxTextRun(
            text: 'Prefix\tValue',
            tabIndices: <int>[2],
            charStyle: VsdxCharStyle(fontSizeInches: 0.2),
            paraStyle: VsdxParaStyle(
              horizontalAlign: VsdxHorzAlign.center,
            ),
          ),
        ],
        textBlock: VsdxTextBlock(
          verticalAlign: VsdxVertAlign.top,
          marginLeftInches: 0,
          marginRightInches: 0,
          marginTopInches: 0,
          marginBottomInches: 0,
        ),
        tabSets: <VsdxTabSet>[
          VsdxTabSet(
            ix: 2,
            stops: <VsdxTabStop>[
              VsdxTabStop(positionInches: 2.2),
            ],
          ),
        ],
      ),
    );
    final page = VsdxPage(
      id: 0,
      name: 'Wrapped tab',
      widthInches: 2.4,
      heightInches: 1,
      shapes: <VsdxShape>[shape],
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    VsdxPainter(page: page, pxPerInch: 100)
        .paint(canvas, const Size(240, 100));
    final picture = recorder.endRecording();
    final image = await picture.toImage(240, 100);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = data!.buffer.asUint8List();

    var continuationInk = 0;
    for (var y = 25; y < 50; y++) {
      for (var x = 0; x < 240; x++) {
        final offset = (y * 240 + x) * 4;
        if (bytes[offset] < 100 && bytes[offset + 1] < 100 &&
            bytes[offset + 2] < 100) {
          continuationInk++;
        }
      }
    }
    expect(continuationInk, greaterThan(20),
        reason: 'Value must be painted on the continuation line');

    image.dispose();
    picture.dispose();
  });
}
