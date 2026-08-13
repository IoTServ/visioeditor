import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/io/image_export.dart';
import 'package:vsdx/vsdx.dart';

const _expectedTexts = <String>[
  'Text with [cm] units 1.0 cm',
  'Text without any units 1.0',
  'Text with [cm] units hidden 1.0',
  'Number 1 formatted as rad 1.0000 rad',
  '1 rad 1 rad',
  'Number 1 formatted as degree 57 deg',
  '1 elapsed minute 1 em.',
  '1 picas 1.0 p',
  '1 picapoints 0.1667',
  '1 ciceros and didots 0.177',
  '1000.1 feet and inch 12001.200',
  'Example testing text',
];

Future<List<int>> _inkByShape(
  Uint8List png,
  VsdxPage page,
  List<VsdxShape> shapes,
) async {
  final codec = await ui.instantiateImageCodec(png);
  try {
    final frame = await codec.getNextFrame();
    try {
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      final pixels = data!.buffer.asUint8List();
      final scaleX = frame.image.width / page.widthInches;
      final scaleY = frame.image.height / page.heightInches;
      return <int>[
        for (final shape in shapes)
          _countInkInShape(
            pixels,
            imageWidth: frame.image.width,
            imageHeight: frame.image.height,
            pageHeight: page.heightInches,
            shape: shape,
            scaleX: scaleX,
            scaleY: scaleY,
          ),
      ];
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

int _countInkInShape(
  Uint8List pixels, {
  required int imageWidth,
  required int imageHeight,
  required double pageHeight,
  required VsdxShape shape,
  required double scaleX,
  required double scaleY,
}) {
  final left = ((shape.pinX - shape.effectiveLocPinX) * scaleX).floor().clamp(
    0,
    imageWidth - 1,
  );
  final right = ((shape.pinX - shape.effectiveLocPinX + shape.width) * scaleX)
      .ceil()
      .clamp(left + 1, imageWidth);
  final top =
      ((pageHeight - (shape.pinY - shape.effectiveLocPinY + shape.height)) *
              scaleY)
          .floor()
          .clamp(0, imageHeight - 1);
  final bottom = ((pageHeight - (shape.pinY - shape.effectiveLocPinY)) * scaleY)
      .ceil()
      .clamp(top + 1, imageHeight);
  var ink = 0;
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      final offset = (y * imageWidth + x) * 4;
      if (pixels[offset + 3] > 32 &&
          (pixels[offset] < 230 ||
              pixels[offset + 1] < 230 ||
              pixels[offset + 2] < 230)) {
        ink++;
      }
    }
  }
  return ink;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('legacy VSD unit fields all reach the Canvas renderer', () async {
    for (final version in const <int>[5, 6]) {
      final source = File(
        'third_party/libvisio/src/test/data/'
        'Visio${version}TextFieldsWithUnits.vsd',
      );
      expect(source.existsSync(), isTrue);
      final document = parseVisio(source.readAsBytesSync()).document;
      final page = document.pages.first;
      final textShapes = page.shapes
          .where((shape) => shape.richText.plainText.trim().isNotEmpty)
          .toList();
      expect(
        textShapes.map((shape) => shape.richText.plainText),
        _expectedTexts,
      );

      final png = await renderPageToPng(
        page,
        theme: document.theme,
        images: document.images,
        pxPerInch: 144,
      );
      expect(png, isNotNull);
      final ink = await _inkByShape(png!, page, textShapes);
      expect(ink, hasLength(_expectedTexts.length));
      for (var i = 0; i < ink.length; i++) {
        expect(
          ink[i],
          greaterThan(20),
          reason:
              'Visio $version shape ${textShapes[i].id} did not paint '
              '"${_expectedTexts[i]}"',
        );
      }
    }
  });
}
