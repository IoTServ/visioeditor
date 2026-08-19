import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as raster;
import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

/// Optional LibreOffice headless cross-check.
///
/// Skips when `soffice` / `libreoffice` is not on PATH and `SOFFICE` is unset,
/// unless `REQUIRE_SOFFICE=1` (CI) — then missing soffice fails the test.
///
/// When available, writes a round-tripped `.vsdx` and asks soffice to convert
/// it to PDF (proves LibreOffice can open the package).
void main() {
  final soffice = _resolveSoffice();
  final pdftoppm = _resolveExecutable('pdftoppm');
  final require = Platform.environment['REQUIRE_SOFFICE'] == '1';

  test('LibreOffice soffice opens a writer round-trip .vsdx', () async {
    if (soffice == null) {
      if (require) {
        fail('REQUIRE_SOFFICE=1 but LibreOffice soffice was not found '
            '(set SOFFICE or install LibreOffice)');
      }
      // ignore: avoid_print
      print('skip: LibreOffice soffice not installed '
          '(set SOFFICE or install LibreOffice)');
      return;
    }

    const writer = VsdxWriter();
    const parser = DocumentParser();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final pageWithBox = doc.pages.first.addShape(
      VsdxShapeFactory.rectangle(
        id: id,
        pinX: 2,
        pinY: 3,
        width: 2,
        height: 1,
        name: 'Box',
      ).copyWith(
        richText: const VsdxRichText(
          runs: <VsdxTextRun>[VsdxTextRun(text: 'Hello LO')],
        ),
      ),
    );
    final pageWithInfinite = pageWithBox.addShape(
      VsdxShape(
        id: id + 1,
        name: 'InfiniteLine',
        pinX: 5,
        pinY: 3,
        width: 0.01,
        height: 0.01,
        geometries: const <VsdxGeometry>[
          VsdxGeometry(
            noFill: true,
            commands: <VsdxPathCommand>[
              InfiniteLineCmd(x: 0, y: 0.005, a: 0.01, b: 0.005),
            ],
          ),
        ],
      ),
    );
    final pageWithArc = pageWithInfinite.addShape(
      VsdxShape(
        id: id + 2,
        name: 'ArcTo',
        pinX: 5,
        pinY: 1.5,
        width: 2,
        height: 1,
        geometries: const <VsdxGeometry>[
          VsdxGeometry(
            noFill: true,
            commands: <VsdxPathCommand>[
              MoveTo(0, 0),
              ArcTo(x: 2, y: 0, bow: 0.6),
            ],
          ),
        ],
      ),
    );
    final pageWithDegenerateArc = pageWithArc.addShape(
      VsdxShape(
        id: id + 3,
        name: 'DegenerateEllipticalArcTo',
        pinX: 2,
        pinY: 1.5,
        width: 2,
        height: 1,
        geometries: const <VsdxGeometry>[
          VsdxGeometry(
            noFill: true,
            commands: <VsdxPathCommand>[
              MoveTo(0, 0),
              EllipticalArcTo(
                x: 2,
                y: 0,
                controlX: 1,
                controlY: 1,
                angle: 0,
                eccentricity: 0,
              ),
            ],
          ),
        ],
      ),
    );
    final pageWithDegenerateEllipse = pageWithDegenerateArc.addShape(
      VsdxShape(
        id: id + 4,
        name: 'DegenerateEllipse',
        pinX: 4,
        pinY: 4,
        width: 2,
        height: 2,
        geometries: const <VsdxGeometry>[
          VsdxGeometry(
            noFill: true,
            commands: <VsdxPathCommand>[
              EllipseCmd(
                cx: 1,
                cy: 1,
                aX: 1,
                aY: 1,
                bX: 1,
                bY: 2,
              ),
            ],
          ),
        ],
      ),
    );
    doc = doc.replacePage(
      0,
      pageWithDegenerateEllipse.addShape(
        VsdxShape(
          id: id + 5,
          name: 'HighDegreeNURBS',
          pinX: 5.5,
          pinY: 6.5,
          width: 9,
          height: 1,
          geometries: const <VsdxGeometry>[
            VsdxGeometry(
              noFill: true,
              commands: <VsdxPathCommand>[
                MoveTo(0, 0.5),
                NurbsTo(
                  x: 9,
                  y: 0.5,
                  controlPoints: <Offset2D>[
                    Offset2D(1, 1),
                    Offset2D(2, 0),
                    Offset2D(3, 1),
                    Offset2D(4, 0),
                    Offset2D(5, 1),
                    Offset2D(6, 0),
                    Offset2D(7, 1),
                    Offset2D(8, 0),
                  ],
                  weights: <double>[1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
                  knots: <double>[
                    0, 0, 0, 0, 0, 0, 0, 0, 0,
                    0.5,
                    1, 1, 1, 1, 1, 1, 1, 1, 1,
                  ],
                  degree: 9,
                ),
              ],
            ),
          ],
        ),
      ).addShape(
        VsdxShape(
          id: id + 6,
          name: 'CubBezTo',
          pinX: 2,
          pinY: 6,
          width: 2,
          height: 1,
          geometries: const <VsdxGeometry>[
            VsdxGeometry(
              noFill: true,
              commands: <VsdxPathCommand>[
                MoveTo(0, 0),
                CubBezTo(x: 2, y: 0, x1: 0.5, y1: 1, x2: 1.5, y2: 1),
              ],
            ),
          ],
        ),
      ).addShape(
        VsdxShape(
          id: id + 7,
          name: 'QuadBezTo',
          pinX: 4.5,
          pinY: 6,
          width: 2,
          height: 1,
          geometries: const <VsdxGeometry>[
            VsdxGeometry(
              noFill: true,
              commands: <VsdxPathCommand>[
                MoveTo(0, 0),
                QuadBezTo(x: 2, y: 0, x1: 1, y1: 1),
              ],
            ),
          ],
        ),
      ).addShape(
        VsdxShape(
          id: id + 8,
          name: 'RelArcTo',
          pinX: 7,
          pinY: 5,
          width: 2,
          height: 1,
          geometries: const <VsdxGeometry>[
            VsdxGeometry(
              noFill: true,
              commands: <VsdxPathCommand>[
                RelMoveTo(0, 0),
                RelArcTo(fx: 1, fy: 0, fbow: 0.2),
              ],
            ),
          ],
        ),
      ).addShape(
        VsdxShapeFactory.rectangle(
          id: id + 9,
          pinX: 2,
          pinY: 7.5,
          width: 1.5,
          height: 0.8,
          name: 'HatchFill',
          fill: const VsdxFill(
            foreground: VsdxColor(0xFFFF0000),
            background: VsdxColor(0xFF0000FF),
            pattern: 2,
          ),
        ),
      ).addShape(
        VsdxShapeFactory.rectangle(
          id: id + 10,
          pinX: 4,
          pinY: 7.5,
          width: 1.5,
          height: 0.8,
          name: 'ClassicRadialFill',
          fill: const VsdxFill(
            foreground: VsdxColor(0xFFFF0000),
            background: VsdxColor(0xFF0000FF),
            pattern: 40,
          ),
        ),
      ).addShape(
        VsdxShapeFactory.rectangle(
          id: id + 11,
          pinX: 6,
          pinY: 7.5,
          width: 1.5,
          height: 0.8,
          name: 'FillGradient',
          fill: const VsdxFill(
            foreground: VsdxColor(0xFFFF0000),
            background: VsdxColor(0xFF0000FF),
            pattern: 1,
            gradient: VsdxGradient(
              stops: [
                VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
                VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
              ],
            ),
          ),
        ),
      ).addShape(
        VsdxShapeFactory.rectangle(
          id: id + 12,
          pinX: 8,
          pinY: 7.5,
          width: 1.5,
          height: 0.8,
          name: 'Rounding',
          fill: const VsdxFill(foreground: VsdxColor(0xFFFFFF00), pattern: 1),
          line: const VsdxLine(
            color: VsdxColor.black,
            roundingInches: 0.15,
            pattern: 2,
            endArrow: 4,
          ),
        ),
      ),
    );
    final generated = writer.write(originalBytes: blank, edited: doc);
    final reopenedCommands = parser
        .parse(generated)
        .pages
        .first
        .shapes
        .expand((shape) => shape.geometries)
        .expand((geometry) => geometry.commands);
    expect(
      reopenedCommands.whereType<InfiniteLineCmd>(),
      hasLength(1),
      reason: 'InfiniteLine must survive the VSDX writer round-trip',
    );
    expect(
      reopenedCommands.whereType<ArcTo>(),
      hasLength(2),
      reason: 'ArcTo and rewritten RelArcTo must survive the VSDX writer',
    );
    expect(
      reopenedCommands.whereType<RelCubBezTo>(),
      isNotEmpty,
      reason: 'CubBezTo is rewritten to RelCubBezTo for LibreOffice',
    );
    expect(reopenedCommands.whereType<CubBezTo>(), isEmpty);
    expect(
      reopenedCommands.whereType<RelQuadBezTo>(),
      isNotEmpty,
      reason: 'QuadBezTo is rewritten to RelQuadBezTo for LibreOffice',
    );
    expect(reopenedCommands.whereType<QuadBezTo>(), isEmpty);
    expect(reopenedCommands.whereType<RelArcTo>(), isEmpty);
    expect(
      reopenedCommands.whereType<EllipticalArcTo>(),
      hasLength(1),
      reason: 'EllipticalArcTo must survive the VSDX writer round-trip',
    );
    expect(
      reopenedCommands.whereType<EllipseCmd>(),
      hasLength(1),
      reason: 'Ellipse must survive the VSDX writer round-trip',
    );
    expect(
      reopenedCommands.whereType<NurbsTo>().single.degree,
      9,
      reason: 'NURBSTo degree must survive the VSDX writer round-trip',
    );
    var tiffDocument = parser.parse(blank);
    final tiffPage = tiffDocument.pages.first;
    const tiffPart = '/visio/media/libreoffice-crosscheck.tiff';
    final tiffBytes = _uncompressedRgbTiff(width: 32, height: 16);
    expect(
      VsdxImage(
        partName: tiffPart,
        bytes: tiffBytes,
        mimeType: 'image/tiff',
      ).rasterForRendering(),
      isNotNull,
    );
    tiffDocument = tiffDocument
        .copyWith(
          images: tiffDocument.images.withImage(
            VsdxImage(
              partName: tiffPart,
              bytes: tiffBytes,
              mimeType: 'image/tiff',
            ),
          ),
        )
        .replacePage(
          0,
          tiffPage.addShape(
            VsdxShapeFactory.picture(
              id: tiffPage.nextFreeShapeId(),
              pinX: 2,
              pinY: 2,
              width: 2,
              height: 2,
              imagePartName: tiffPart,
            ),
          ),
        );
    var gifDocument = parser.parse(blank);
    final gifPage = gifDocument.pages.first;
    const gifPart = '/visio/media/libreoffice-crosscheck.gif';
    final gifImage = raster.Image(width: 32, height: 16);
    for (var y = 0; y < gifImage.height; y++) {
      for (var x = 0; x < gifImage.width; x++) {
        gifImage.setPixelRgba(
          x,
          y,
          x < gifImage.width ~/ 2 ? 255 : 0,
          0,
          x < gifImage.width ~/ 2 ? 0 : 255,
          255,
        );
      }
    }
    final gifBytes = raster.encodeGif(gifImage, singleFrame: true);
    gifDocument = gifDocument
        .copyWith(
          images: gifDocument.images.withImage(
            VsdxImage(
              partName: gifPart,
              bytes: gifBytes,
              mimeType: 'image/gif',
            ),
          ),
        )
        .replacePage(
          0,
          gifPage.addShape(
            VsdxShapeFactory.picture(
              id: gifPage.nextFreeShapeId(),
              pinX: 2,
              pinY: 2,
              width: 2,
              height: 2,
              imagePartName: gifPart,
            ),
          ),
        );
    var flipDocument = parser.parse(blank);
    final flipPage = flipDocument.pages.first;
    const flipPart = '/visio/media/libreoffice-flipy.png';
    final flipImage = raster.Image(width: 32, height: 32);
    for (var y = 0; y < flipImage.height; y++) {
      for (var x = 0; x < flipImage.width; x++) {
        flipImage.setPixelRgba(
          x,
          y,
          y < flipImage.height ~/ 2 ? 255 : 0,
          0,
          y < flipImage.height ~/ 2 ? 0 : 255,
          255,
        );
      }
    }
    flipDocument = flipDocument
        .copyWith(
          images: flipDocument.images.withImage(
            VsdxImage(
              partName: flipPart,
              bytes: raster.encodePng(flipImage),
              mimeType: 'image/png',
            ),
          ),
        )
        .replacePage(
          0,
          flipPage.addShape(
            VsdxShapeFactory.picture(
              id: flipPage.nextFreeShapeId(),
              pinX: 2,
              pinY: 2,
              width: 2,
              height: 2,
              imagePartName: flipPart,
            ).copyWith(flipY: true),
          ),
        );
    var geometryImageDocument = parser.parse(blank);
    final geometryImagePage = geometryImageDocument.pages.first;
    const geometryImagePart = '/visio/media/libreoffice-geometry-image.png';
    final geometryImage = raster.Image(width: 32, height: 32);
    for (var y = 0; y < geometryImage.height; y++) {
      for (var x = 0; x < geometryImage.width; x++) {
        geometryImage.setPixelRgba(
          x,
          y,
          x < geometryImage.width ~/ 2 ? 255 : 0,
          0,
          x < geometryImage.width ~/ 2 ? 0 : 255,
          255,
        );
      }
    }
    geometryImageDocument = geometryImageDocument
        .copyWith(
          images: geometryImageDocument.images.withImage(
            VsdxImage(
              partName: geometryImagePart,
              bytes: raster.encodePng(geometryImage),
              mimeType: 'image/png',
            ),
          ),
        )
        .replacePage(
          0,
          geometryImagePage.addShape(
            VsdxShapeFactory.picture(
              id: geometryImagePage.nextFreeShapeId(),
              pinX: 2,
              pinY: 2,
              width: 2,
              height: 2,
              imagePartName: geometryImagePart,
            ).copyWith(
              geometries: const <VsdxGeometry>[
                VsdxGeometry(
                  noFill: true,
                  noLine: true,
                  commands: <VsdxPathCommand>[
                    MoveTo(0, 0),
                    LineTo(2, 0),
                    LineTo(1, 2),
                    LineTo(0, 0),
                  ],
                ),
              ],
            ),
          ),
        );
    var textFlipDocument = parser.parse(blank);
    final textFlipPage = textFlipDocument.pages.first;
    VsdxRichText flipText(String text) => VsdxRichText(
          runs: <VsdxTextRun>[
            VsdxTextRun(
              text: text,
              charStyle: const VsdxCharStyle(
                fontFamily: 'Arial',
                fontSizeInches: 0.5,
                color: VsdxColor(0xFF000000),
              ),
              paraStyle: const VsdxParaStyle(
                horizontalAlign: VsdxHorzAlign.left,
              ),
            ),
          ],
          textBlock: const VsdxTextBlock(
            verticalAlign: VsdxVertAlign.top,
            marginLeftInches: 0.1,
            marginRightInches: 0.1,
            marginTopInches: 0.1,
            marginBottomInches: 0.1,
          ),
        );
    final flipXText = VsdxShapeFactory.rectangle(
      id: textFlipPage.nextFreeShapeId(),
      pinX: 2,
      pinY: 6,
      width: 3,
      height: 1.5,
    ).copyWith(
      flipX: true,
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
      richText: flipText('LEFT'),
    );
    final flipYText = VsdxShapeFactory.rectangle(
      id: flipXText.id + 1,
      pinX: 2,
      pinY: 3,
      width: 3,
      height: 1.5,
    ).copyWith(
      flipY: true,
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
      richText: flipText('TOP'),
    );
    final nestedText = VsdxShapeFactory.rectangle(
      id: flipYText.id + 2,
      pinX: 1.5,
      pinY: 0.75,
      width: 3,
      height: 1.5,
    ).copyWith(
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
      richText: flipText('LEFT'),
    );
    final flipXGroup = VsdxShapeFactory.rectangle(
      id: flipYText.id + 1,
      pinX: 6,
      pinY: 6,
      width: 3,
      height: 1.5,
    ).copyWith(
      flipX: true,
      shapeKind: VsdxShapeKind.group,
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
      children: <VsdxShape>[nestedText],
    );
    textFlipDocument = textFlipDocument.replacePage(
      0,
      textFlipPage.copyWith(
        shapes: <VsdxShape>[flipXText, flipYText, flipXGroup],
      ),
    );
    final inputs = <String, Uint8List>{
      'generated': generated,
      'tiff_foreign_data': writer.write(
        originalBytes: blank,
        edited: tiffDocument,
      ),
      'gif_foreign_data': writer.write(
        originalBytes: blank,
        edited: gifDocument,
      ),
      'flipy_foreign_data': writer.write(
        originalBytes: blank,
        edited: flipDocument,
      ),
      'geometry_foreign_data': writer.write(
        originalBytes: blank,
        edited: geometryImageDocument,
      ),
      'text_flip': writer.write(
        originalBytes: blank,
        edited: textFlipDocument,
      ),
    };
    for (final entry in const <(String, String)>[
      ('connectors', 'test/fixtures/test4_connectors.vsdx'),
      ('zh_data', 'test/fixtures/数据治理.vsdx'),
    ]) {
      final raw = await File(entry.$2).readAsBytes();
      inputs[entry.$1] =
          writer.write(originalBytes: raw, edited: parser.parse(raw));
    }

    final dir = await Directory.systemTemp.createTemp('vsdx_lo_');
    final profile = Directory('${dir.path}/lo_profile')..createSync();
    try {
      final paths = <String>[];
      for (final entry in inputs.entries) {
        final input = File('${dir.path}/${entry.key}.vsdx');
        await input.writeAsBytes(entry.value);
        paths.add(input.path);
      }
      final result = await Process.run(
        soffice,
        <String>[
          '--headless',
          '--norestore',
          '--nofirststartwizard',
          '-env:UserInstallation=file://${profile.path}',
          '--convert-to',
          'pdf',
          '--outdir',
          dir.path,
          ...paths,
        ],
        workingDirectory: dir.path,
        environment: <String, String>{
          ...Platform.environment,
          // Prefer headless VCL on Linux CI runners.
          'SAL_USE_VCLPLUGIN': 'svp',
        },
      );
      expect(result.exitCode, 0,
          reason: 'soffice stderr: ${result.stderr}\nstdout: ${result.stdout}');

      for (final entry in inputs.entries) {
        final pdf = File('${dir.path}/${entry.key}.pdf');
        expect(pdf.existsSync(), isTrue,
            reason: 'expected ${entry.key}.pdf from soffice; '
                'dir=${dir.listSync().map((e) => e.path).toList()}');
        expect(pdf.lengthSync(), greaterThan(100));
        if (entry.key == 'tiff_foreign_data' ||
            entry.key == 'gif_foreign_data' ||
            entry.key == 'flipy_foreign_data' ||
            entry.key == 'geometry_foreign_data') {
          if (pdftoppm == null) {
            if (require) {
              fail('pdftoppm is required for raster render checking');
            }
          } else {
            final prefix = '${dir.path}/${entry.key}-render';
            final rasterized = await Process.run(pdftoppm, <String>[
              '-png',
              '-singlefile',
              '-r',
              '72',
              pdf.path,
              prefix,
            ]);
            expect(rasterized.exitCode, 0,
                reason: 'pdftoppm stderr: ${rasterized.stderr}');
            final rendered = raster.decodePng(
              await File('$prefix.png').readAsBytes(),
            );
            expect(rendered, isNotNull);
            var redPixels = 0;
            var bluePixels = 0;
            for (final pixel in rendered!) {
              if (pixel.r > 180 && pixel.g < 80 && pixel.b < 80) redPixels++;
              if (pixel.b > 180 && pixel.r < 80 && pixel.g < 80) bluePixels++;
            }
            expect(redPixels, greaterThan(100),
                reason: 'red=$redPixels blue=$bluePixels');
            expect(bluePixels, greaterThan(100),
                reason: 'red=$redPixels blue=$bluePixels');
            if (entry.key == 'flipy_foreign_data') {
              final reopened = parser.parse(entry.value);
              final page = reopened.pages.first;
              final x = (2 / page.widthInches * rendered.width).round();
              final topY = ((page.heightInches - 2.5) /
                      page.heightInches *
                      rendered.height)
                  .round();
              final bottomY = ((page.heightInches - 1.5) /
                      page.heightInches *
                      rendered.height)
                  .round();
              final top = rendered.getPixel(x, topY);
              final bottom = rendered.getPixel(x, bottomY);
              expect(top.b, greaterThan(180),
                  reason: 'LibreOffice FlipY top must be source bottom');
              expect(top.r, lessThan(80));
              expect(bottom.r, greaterThan(180),
                  reason: 'LibreOffice FlipY bottom must be source top');
              expect(bottom.b, lessThan(80));
            }
            if (entry.key == 'geometry_foreign_data') {
              final reopened = parser.parse(entry.value);
              final page = reopened.pages.first;
              // This point is inside the ForeignData rectangle but outside
              // the triangular Geometry. libvisio emits the two as sibling
              // objects, so LibreOffice must still show the bitmap here.
              final x = (1.2 / page.widthInches * rendered.width).round();
              final y = ((page.heightInches - 2.7) /
                      page.heightInches *
                      rendered.height)
                  .round();
              final corner = rendered.getPixel(x, y);
              expect(corner.r, greaterThan(180),
                  reason: 'ForeignData must not be clipped by Geometry');
              expect(corner.g, lessThan(80));
              expect(corner.b, lessThan(80));
            }
          }
        }
        if (entry.key == 'text_flip' && pdftoppm != null) {
          final prefix = '${dir.path}/${entry.key}-render';
          final rasterized = await Process.run(pdftoppm, <String>[
            '-png',
            '-singlefile',
            '-r',
            '72',
            pdf.path,
            prefix,
          ]);
          expect(rasterized.exitCode, 0,
              reason: 'pdftoppm stderr: ${rasterized.stderr}');
          final rendered = raster.decodePng(
            await File('$prefix.png').readAsBytes(),
          )!;
          final reopened = parser.parse(entry.value);
          final page = reopened.pages.first;
          int darkPixels(double x0, double y0, double x1, double y1) {
            final left = (x0 / page.widthInches * rendered.width).round();
            final right = (x1 / page.widthInches * rendered.width).round();
            final top = ((page.heightInches - y1) /
                    page.heightInches *
                    rendered.height)
                .round();
            final bottom = ((page.heightInches - y0) /
                    page.heightInches *
                    rendered.height)
                .round();
            var count = 0;
            for (var y = top; y < bottom; y++) {
              for (var x = left; x < right; x++) {
                final pixel = rendered.getPixel(x, y);
                if (pixel.r < 120 && pixel.g < 120 && pixel.b < 120) count++;
              }
            }
            return count;
          }

          final flipXLeft = darkPixels(0.55, 5.35, 2.0, 6.65);
          final flipXRight = darkPixels(2.0, 5.35, 3.45, 6.65);
          expect(flipXLeft, greaterThan(50));
          expect(flipXLeft, greaterThan(flipXRight * 2),
              reason: 'LibreOffice keeps FlipX text left-aligned and upright');
          final flipYTop = darkPixels(0.55, 3.0, 3.45, 3.7);
          final flipYBottom = darkPixels(0.55, 2.3, 3.45, 3.0);
          expect(flipYTop, greaterThan(50));
          expect(flipYTop, greaterThan(flipYBottom * 2),
              reason: 'LibreOffice keeps FlipY text top-aligned and upright');
          final nestedLeft = darkPixels(4.55, 5.35, 6.0, 6.65);
          final nestedRight = darkPixels(6.0, 5.35, 7.45, 6.65);
          expect(nestedLeft, greaterThan(50));
          expect(nestedLeft, greaterThan(nestedRight * 2),
              reason: 'LibreOffice cancels ancestor-group FlipX for text');
        }
        // Still parseable after our write (independent of LibreOffice).
        expect(parser.parse(entry.value).pages, isNotEmpty);
      }
    } finally {
      await dir.delete(recursive: true);
    }
  },
      // A headless soffice conversion alone takes most of the 30 second
      // default on a cold profile, and this case converts eight packages.
      timeout: const Timeout(Duration(minutes: 5)),
      skip: (!require && soffice == null)
          ? 'LibreOffice soffice not installed'
          : false);
}

String? _resolveExecutable(String name) {
  final which = Process.runSync('which', <String>[name]);
  if (which.exitCode != 0) return null;
  final path = (which.stdout as String).trim();
  return path.isEmpty ? null : path;
}

/// Baseline little-endian, single-strip RGB TIFF understood by libtiff,
/// LibreOffice and the pure-Dart decoder. Keeping this fixture uncompressed
/// avoids coupling the interop assertion to any particular TIFF compressor.
Uint8List _uncompressedRgbTiff({required int width, required int height}) {
  final out = BytesBuilder(copy: false);
  void u16(int value) {
    out.add(<int>[value & 0xff, (value >> 8) & 0xff]);
  }

  void u32(int value) {
    out.add(<int>[
      value & 0xff,
      (value >> 8) & 0xff,
      (value >> 16) & 0xff,
      (value >> 24) & 0xff,
    ]);
  }

  void entry(int tag, int type, int count, int value, {bool short = false}) {
    u16(tag);
    u16(type);
    u32(count);
    if (short) {
      u16(value);
      u16(0);
    } else {
      u32(value);
    }
  }

  const entryCount = 10;
  const ifdOffset = 8;
  const ifdBytes = 2 + entryCount * 12 + 4;
  const bitsOffset = ifdOffset + ifdBytes;
  const pixelOffset = bitsOffset + 6;
  final pixelBytes = width * height * 3;

  u16(0x4949); // II (little endian)
  u16(42);
  u32(ifdOffset);
  u16(entryCount);
  entry(256, 4, 1, width); // ImageWidth
  entry(257, 4, 1, height); // ImageLength
  entry(258, 3, 3, bitsOffset); // BitsPerSample
  entry(259, 3, 1, 1, short: true); // Compression = none
  entry(262, 3, 1, 2, short: true); // Photometric = RGB
  entry(273, 4, 1, pixelOffset); // StripOffsets
  entry(277, 3, 1, 3, short: true); // SamplesPerPixel
  entry(278, 4, 1, height); // RowsPerStrip
  entry(279, 4, 1, pixelBytes); // StripByteCounts
  entry(284, 3, 1, 1, short: true); // PlanarConfiguration = chunky
  u32(0); // next IFD
  u16(8);
  u16(8);
  u16(8);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      out.add(x < width ~/ 2 ? <int>[255, 0, 0] : <int>[0, 0, 255]);
    }
  }
  return out.takeBytes();
}

String? _resolveSoffice() {
  final env = Platform.environment['SOFFICE'];
  if (env != null && env.isNotEmpty && File(env).existsSync()) return env;
  for (final name in <String>['soffice', 'libreoffice']) {
    final which = Process.runSync('which', <String>[name]);
    if (which.exitCode == 0) {
      final path = (which.stdout as String).trim();
      if (path.isNotEmpty) return path;
    }
  }
  const mac =
      '/Applications/LibreOffice.app/Contents/MacOS/soffice';
  if (File(mac).existsSync()) return mac;
  return null;
}
