import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vsdx/vsdx.dart';

import 'package:visioeditor/render/vsdx_painter.dart';

void main() {
  test('canvas skips one invalid geometry and paints later shapes', () async {
    final broken = VsdxShape(
      id: 1,
      name: 'Broken',
      pinX: 1,
      pinY: 1,
      width: 1,
      height: 1,
      geometries: const <VsdxGeometry>[
        VsdxGeometry(
          commands: <VsdxPathCommand>[
            MoveTo(0, 0),
            NurbsTo(x: 1, y: 1, controlPoints: <Offset2D>[], degree: -1),
          ],
        ),
      ],
    );
    final valid =
        VsdxShapeFactory.rectangle(
          id: 2,
          pinX: 3,
          pinY: 1,
          width: 1,
          height: 1,
        ).copyWith(
          fill: const VsdxFill(foreground: VsdxColor(0xFF00FF00)),
          line: const VsdxLine(pattern: 0),
        );
    final page = VsdxPage(
      id: 0,
      name: 'Recovery',
      widthInches: 4,
      heightInches: 2,
      shapes: <VsdxShape>[broken, valid],
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    VsdxPainter(page: page, pxPerInch: 40).paint(canvas, const Size(160, 80));
    final picture = recorder.endRecording();
    final image = await picture.toImage(160, 80);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final offset = (40 * 160 + 120) * 4;

    expect(bytes, isNotNull);
    expect(bytes!.getUint8(offset), lessThan(10));
    expect(bytes.getUint8(offset + 1), greaterThan(245));
    expect(bytes.getUint8(offset + 2), lessThan(10));

    image.dispose();
    picture.dispose();
  });
}
