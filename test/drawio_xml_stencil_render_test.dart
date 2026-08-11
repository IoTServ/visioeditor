import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/render/path_builder.dart';
import 'package:vsdx/stencils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'all migrated draw.io XML shapes reach the Canvas path renderer',
    () async {
      final stencils = <Stencil>[
        for (final group in kStencilGroups)
          if (group.name.startsWith('Draw.io / ')) ...group.stencils,
      ];
      expect(stencils, hasLength(8964));

      const columns = 100;
      const cell = 20.0;
      final rows = (stencils.length + columns - 1) ~/ columns;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final fill = ui.Paint()
        ..style = ui.PaintingStyle.fill
        ..color = const ui.Color(0xffdae8fc);
      final stroke = ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 0.04
        ..color = const ui.Color(0xff6c8ebf);

      var commandCount = 0;
      for (var index = 0; index < stencils.length; index++) {
        final shape = stencils[index].build(index + 1, 0, 0);
        final scale = 16 / math.max(shape.width, shape.height);
        final column = index % columns;
        final row = index ~/ columns;
        canvas.save();
        canvas.translate(
          column * cell + (cell - shape.width * scale) / 2,
          row * cell + (cell + shape.height * scale) / 2,
        );
        canvas.scale(scale, -scale);
        for (final geometry in shape.geometries) {
          commandCount += geometry.commands.length;
          final path = buildPath(
            geometry,
            widthInches: shape.width,
            heightInches: shape.height,
          );
          final bounds = path.getBounds();
          if (!bounds.left.isFinite ||
              !bounds.top.isFinite ||
              !bounds.right.isFinite ||
              !bounds.bottom.isFinite) {
            fail(
              '${stencils[index].group} / ${stencils[index].name} '
              'produced non-finite Canvas bounds',
            );
          }
          if (!geometry.noFill) canvas.drawPath(path, fill);
          if (!geometry.noLine) canvas.drawPath(path, stroke);
        }
        canvas.restore();
      }
      expect(commandCount, greaterThan(500000));

      final picture = recorder.endRecording();
      final image = await picture.toImage(
        (columns * cell).round(),
        (rows * cell).round(),
      );
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(rgba, isNotNull);
      var paintedSamples = 0;
      for (var offset = 3; offset < rgba!.lengthInBytes; offset += 64) {
        if (rgba.getUint8(offset) != 0) paintedSamples++;
      }
      expect(paintedSamples, greaterThan(10000));
      image.dispose();
      picture.dispose();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
