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
      hasLength(1),
      reason: 'ArcTo must survive the VSDX writer round-trip',
    );
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
    final tiffImage = raster.Image(width: 8, height: 8);
    for (var y = 0; y < tiffImage.height; y++) {
      for (var x = 0; x < tiffImage.width; x++) {
        final red = x < 4 ? 255 : 0;
        final blue = x < 4 ? 0 : 255;
        tiffImage.setPixelRgba(x, y, red, 0, blue, 255);
      }
    }
    final tiffBytes = raster.encodeTiff(tiffImage, singleFrame: true);
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
    final inputs = <String, Uint8List>{
      'generated': generated,
      'tiff_foreign_data': writer.write(
        originalBytes: blank,
        edited: tiffDocument,
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
        // Still parseable after our write (independent of LibreOffice).
        expect(parser.parse(entry.value).pages, isNotEmpty);
      }
    } finally {
      await dir.delete(recursive: true);
    }
  },
      skip: (!require && soffice == null)
          ? 'LibreOffice soffice not installed'
          : false);
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
