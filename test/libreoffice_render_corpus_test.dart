// The corpus audit deliberately reports per-page diagnostics.
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/io/image_export.dart';
import 'package:vsdx/vsdx.dart';

const _runEnvironment = 'RUN_LIBREOFFICE_RENDER_CORPUS';
const _auditDirectoryEnvironment = 'VISIO_RENDER_AUDIT_DIR';
const _filterEnvironment = 'VISIO_RENDER_AUDIT_FILTER';
const _latinFontEnvironment = 'VISIO_RENDER_AUDIT_LATIN_FONT';
const _cjkFontEnvironment = 'VISIO_RENDER_AUDIT_CJK_FONT';

const _upstreamDirectory = 'third_party/libvisio/src/test/data';
const _appExampleDirectory = 'assets/examples';
const _packageExternalDirectory = 'packages/vsdx/test/fixtures/vsd/external';
const _packageFixtureDirectory = 'packages/vsdx/test/fixtures';

const _legacyUnitFieldTexts = <String>[
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

const _vdxCoverageTexts = <String>[
  'All rich text retained',
  'Second line and tab:',
  'Bezier, arcs, ellipse',
  'Grouped child A',
  'Grouped child B',
  '1-D connector',
  'Relative and polyline rows',
  'Spline, NURBS, infinite line',
];

const _corpus = <_CorpusEntry>[
  _CorpusEntry('Visio11FormatLine.vsd'),
  _CorpusEntry('Visio11PlanWithDimensions.vsd'),
  _CorpusEntry('Visio11TextFieldsWithAngle.vsd'),
  _CorpusEntry('Visio11TextFieldsWithCurrency.vsd'),
  _CorpusEntry('Visio11TextFieldsWithUnits.vsd'),
  _CorpusEntry('Visio5PlanWithDimensions.vsd'),
  // Current LibreOffice/libvisio renders only the final plain-text label from
  // this VSD5 source. The Dart parser intentionally recovers all field labels,
  // so validate their semantics independently of the incomplete oracle image.
  _CorpusEntry(
    'Visio5TextFieldsWithUnits.vsd',
    expectedTextFragments: _legacyUnitFieldTexts,
  ),
  _CorpusEntry('Visio6PlanWithDimensions.vsd'),
  _CorpusEntry(
    'Visio6TextFieldsWithUnits.vsd',
    expectedTextFragments: _legacyUnitFieldTexts,
  ),
  _CorpusEntry('bgcolor.vsdx'),
  _CorpusEntry('bitmaps.vsd'),
  _CorpusEntry('bitmaps2.vsd'),
  _CorpusEntry('blue-box.vsdx'),
  _CorpusEntry('color-boxes.vsdx'),
  _CorpusEntry('dwg.vsd'),
  _CorpusEntry('dwg.vsdx'),
  _CorpusEntry('fdo86664.vsdx'),
  _CorpusEntry('fdo86729-ms1252.vsd'),
  _CorpusEntry('fdo86729-utf8.vsd'),
  _CorpusEntry('no-bgcolor.vsd'),
  _CorpusEntry('office_varient4.vsdx'),
  _CorpusEntry('qs-box.vsdx'),
  _CorpusEntry('recursion-cycle.vsdx', ignoreLibreOfficePageCount: true),
  _CorpusEntry('tab-short-prefix.vsdx'),
  _CorpusEntry('tdf136564-WhiteTextBackground.vsdx'),
  _CorpusEntry('tdf154379-DrawingUnits-type.vsd'),
  _CorpusEntry('tdf154379-QuickStyleFillMatrix.vsdx'),
  _CorpusEntry('tdf76829-datetime-format.vsd'),
  _CorpusEntry('tdf76829-numeric-format.vsd'),
  _CorpusEntry('testfile1.vsdx'),
  _CorpusEntry('testfile3.vsdx'),
  _CorpusEntry('testfile4.vsdx'),
  _CorpusEntry('testfile5.vsdx'),
  _CorpusEntry('testfile6.vsdx'),
  _CorpusEntry('visio_with_embeded.vsd', packageExternal: true),
  _CorpusEntry('test1.vsdx', packageFixture: true),
  _CorpusEntry('test2.vsdx', packageFixture: true),
  _CorpusEntry('test3_house.vsdx', packageFixture: true),
  _CorpusEntry('test4_connectors.vsdx', packageFixture: true),
  _CorpusEntry('test5_master.vsdx', packageFixture: true),
  _CorpusEntry('test6_shape_properties.vsdx', packageFixture: true),
  _CorpusEntry('test7_with_connector.vsdx', packageFixture: true),
  _CorpusEntry('test8_simple_connector.vsdx', packageFixture: true),
  _CorpusEntry('test9_rect_and_line.vsdx', packageFixture: true),
  _CorpusEntry('test10_nested_shapes.vsdx', packageFixture: true),
  // LibreOffice Draw exports every page at page 1's size, although pages.xml
  // gives pages 2/3 their own A4 height. Keep comparing their content, but do
  // not treat that LibreOffice PDF limitation as an application regression.
  _CorpusEntry(
    'test11_rotate.vsdx',
    packageFixture: true,
    ignoreLibreOfficeCanvasSize: true,
  ),
  _CorpusEntry('test12_colors.vsdx', packageFixture: true),
  _CorpusEntry('test_master.vsdx', packageFixture: true),
  _CorpusEntry('test_master_multiple_child_shapes.vsdx', packageFixture: true),
  _CorpusEntry('test_jinja.vsdx', packageFixture: true),
  _CorpusEntry('test_jinja_inner_loop.vsdx', packageFixture: true),
  _CorpusEntry('test_jinja_loop.vsdx', packageFixture: true),
  _CorpusEntry('test_jinja_loop_showif.vsdx', packageFixture: true),
  _CorpusEntry('test_jinja_page_showif.vsdx', packageFixture: true),
  _CorpusEntry('test_jinja_self_refs.vsdx', packageFixture: true),
  _CorpusEntry(
    'vdx_all_types.vdx',
    packageFixture: true,
    expectedTextFragments: _vdxCoverageTexts,
  ),
  _CorpusEntry('sample.vsd', applicationExample: true),
  _CorpusEntry('workflow.vsdx', applicationExample: true),
  _CorpusEntry('人才招聘冰山模型.vsdx', applicationExample: true),
  _CorpusEntry('数据治理.vsdx', applicationExample: true),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final enabled = Platform.environment[_runEnvironment] == '1';
  test(
    '56 Visio fixtures and 4 app examples render like LibreOffice',
    () async {
      await _loadAuditFonts();
      expect(
        _corpus.where((entry) => !entry.applicationExample),
        hasLength(56),
      );
      expect(_corpus.where((entry) => entry.applicationExample), hasLength(4));
      final filter = Platform.environment[_filterEnvironment];
      final selected = filter == null || filter.isEmpty
          ? _corpus
          : _corpus.where((entry) => entry.name.contains(filter)).toList();
      expect(selected, isNotEmpty, reason: 'no corpus entry matches $filter');

      final soffice = _resolveExecutable(
        environmentName: 'SOFFICE',
        names: const ['soffice', 'libreoffice'],
        macFallback: '/Applications/LibreOffice.app/Contents/MacOS/soffice',
      );
      final pdftoppm = _resolveExecutable(
        environmentName: 'PDFTOPPM',
        names: const ['pdftoppm'],
      );
      expect(soffice, isNotNull, reason: 'LibreOffice soffice is required');
      expect(pdftoppm, isNotNull, reason: 'Poppler pdftoppm is required');

      final requestedAudit = Platform.environment[_auditDirectoryEnvironment];
      final auditRoot =
          requestedAudit == null || requestedAudit.isEmpty
                ? await Directory.systemTemp.createTemp('visio_render_corpus_')
                : Directory(requestedAudit)
            ..createSync(recursive: true);
      final retainAudit = requestedAudit != null && requestedAudit.isNotEmpty;
      final failures = <String>[];
      var renderedPages = 0;

      try {
        for (
          var corpusIndex = 0;
          corpusIndex < selected.length;
          corpusIndex++
        ) {
          final entry = selected[corpusIndex];
          final source = File(entry.path);
          expect(source.existsSync(), isTrue, reason: 'missing ${entry.path}');

          final result = parseVisio(source.readAsBytesSync());
          final document = result.document;
          final pages = document.pages;
          if (entry.expectedTextFragments.isNotEmpty) {
            final visibleTexts = _visibleTexts(document);
            for (final expected in entry.expectedTextFragments) {
              if (!visibleTexts.any((text) => text.contains(expected))) {
                failures.add(
                  '${entry.name}: parsed model lost text "$expected"',
                );
              }
            }
          }

          final caseDirectory = Directory(
            '${auditRoot.path}/${corpusIndex.toString().padLeft(2, '0')}_${_safeName(entry.name)}',
          )..createSync(recursive: true);
          final libreOfficePages = await _renderWithLibreOffice(
            soffice: soffice!,
            pdftoppm: pdftoppm!,
            source: source,
            outputDirectory: caseDirectory,
          );
          if (!entry.ignoreLibreOfficePageCount &&
              libreOfficePages.length != pages.length) {
            failures.add(
              '${entry.name}: page count app=${pages.length} '
              'LibreOffice=${libreOfficePages.length}',
            );
          }

          final comparablePages = math.min(
            pages.length,
            libreOfficePages.length,
          );
          for (var pageIndex = 0; pageIndex < comparablePages; pageIndex++) {
            final page = pages[pageIndex];
            final appPng = await renderPageToPng(
              page,
              theme: document.theme,
              images: document.images,
              underlayPage: document.backgroundFor(page),
              pxPerInch: 72,
            );
            if (appPng == null || appPng.isEmpty) {
              failures.add(
                '${entry.name} page ${pageIndex + 1}: empty app PNG',
              );
              continue;
            }
            final appFile = File(
              '${caseDirectory.path}/app-${pageIndex + 1}.png',
            );
            appFile.writeAsBytesSync(appPng);
            final appSvg = VsdxToSvgSerializer().serializePage(
              page,
              theme: document.theme,
              images: document.images,
            );
            File(
              '${caseDirectory.path}/app-${pageIndex + 1}.svg',
            ).writeAsStringSync(appSvg);
            if (pageIndex == 0) {
              for (final expected in entry.expectedTextFragments) {
                if (!appSvg.contains(expected)) {
                  failures.add('${entry.name}: SVG lost text "$expected"');
                }
              }
            }

            final appImage = await _decodePng(appPng);
            final referenceImage = await _decodePng(
              libreOfficePages[pageIndex].readAsBytesSync(),
            );
            final appMetrics = _measure(appImage);
            final referenceMetrics = _measure(referenceImage);
            final comparison = _compare(appImage, referenceImage);
            appImage.dispose();
            referenceImage.dispose();
            renderedPages++;

            final label = '${entry.name}#${pageIndex + 1}';
            print(
              'RENDER $label '
              'size=${appMetrics.width}x${appMetrics.height}/'
              '${referenceMetrics.width}x${referenceMetrics.height} '
              'ink=${appMetrics.inkFraction.toStringAsFixed(4)}/'
              '${referenceMetrics.inkFraction.toStringAsFixed(4)} '
              'color=${appMetrics.colorFraction.toStringAsFixed(4)}/'
              '${referenceMetrics.colorFraction.toStringAsFixed(4)} '
              'bbox=${appMetrics.bboxFraction.toStringAsFixed(4)}/'
              '${referenceMetrics.bboxFraction.toStringAsFixed(4)} '
              'mae=${comparison.meanAbsoluteError.toStringAsFixed(4)} '
              'iou=${comparison.inkIntersectionOverUnion.toStringAsFixed(4)}',
            );

            if (!entry.ignoreLibreOfficeCanvasSize &&
                ((appMetrics.width - referenceMetrics.width).abs() > 2 ||
                    (appMetrics.height - referenceMetrics.height).abs() > 2)) {
              failures.add(
                '$label: canvas app=${appMetrics.width}x${appMetrics.height}, '
                'LibreOffice=${referenceMetrics.width}x${referenceMetrics.height}',
              );
            }
            if (referenceMetrics.inkFraction >= 0.0001 &&
                appMetrics.inkFraction < 0.0001) {
              failures.add(
                '$label: app render is blank while LibreOffice is not',
              );
            }
            if (referenceMetrics.colorFraction >= 0.001 &&
                appMetrics.colorFraction < 0.0001) {
              failures.add(
                '$label: app lost colored content '
                '(app=${appMetrics.colorFraction}, '
                'LibreOffice=${referenceMetrics.colorFraction})',
              );
            }
          }
        }

        expect(renderedPages, greaterThanOrEqualTo(selected.length));
        expect(
          failures,
          isEmpty,
          reason: 'render corpus mismatches:\n${failures.join('\n')}',
        );
        print(
          'RENDER SUMMARY files=${selected.length} pages=$renderedPages '
          'audit=${auditRoot.path}',
        );
      } finally {
        if (!retainAudit && auditRoot.existsSync()) {
          auditRoot.deleteSync(recursive: true);
        }
      }
    },
    skip: enabled ? false : 'set $_runEnvironment=1 for the full render audit',
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

/// Flutter's test binding otherwise substitutes the square-glyph Ahem font,
/// which makes a visual comparison with LibreOffice actively misleading.
/// This audit is opt-in and already depends on host executables, so loading a
/// host font here is appropriate. Environment overrides keep it portable to
/// CI hosts whose fonts live elsewhere.
Future<void> _loadAuditFonts() async {
  final latin = _firstExistingFile(<String?>[
    Platform.environment[_latinFontEnvironment],
    '/System/Library/Fonts/Supplemental/Arial.ttf',
    '/Library/Fonts/Arial.ttf',
    '/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf',
    '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  ]);
  if (latin == null) {
    throw TestFailure(
      'A real Latin font is required; set $_latinFontEnvironment',
    );
  }
  await _loadFontAliases(latin, const <String>[
    'Arial',
    'Arial Black',
    'Calibri',
    'Calibri Light',
    'Cambria',
    'Courier New',
    'DejaVu Sans',
    'Helvetica',
    'Liberation Sans',
    'Liberation Serif',
    'Segoe UI',
    'Tahoma',
    'Times New Roman',
    'Trebuchet MS',
    'Verdana',
  ]);

  final cjk = _firstExistingFile(<String?>[
    Platform.environment[_cjkFontEnvironment],
    '/Library/Fonts/Arial Unicode.ttf',
    '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
    '/System/Library/Fonts/PingFang.ttc',
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
    '/usr/share/fonts/opentype/noto/NotoSansCJKsc-Regular.otf',
  ]);
  if (cjk != null) {
    await _loadFontAliases(cjk, const <String>[
      'Arial Unicode MS',
      'Microsoft YaHei',
      'Microsoft YaHei UI',
      'PingFang SC',
      'Hiragino Sans GB',
      'SimHei',
      'SimSun',
      '宋体',
      '微软雅黑',
      '黑体',
    ]);
  }
}

File? _firstExistingFile(Iterable<String?> paths) {
  for (final path in paths) {
    if (path == null || path.isEmpty) continue;
    final file = File(path);
    if (file.existsSync()) return file;
  }
  return null;
}

Future<void> _loadFontAliases(File file, List<String> families) async {
  final bytes = ByteData.sublistView(file.readAsBytesSync());
  for (final family in families) {
    final loader = FontLoader(family)..addFont(Future<ByteData>.value(bytes));
    await loader.load();
  }
}

class _CorpusEntry {
  const _CorpusEntry(
    this.name, {
    this.applicationExample = false,
    this.packageExternal = false,
    this.packageFixture = false,
    this.ignoreLibreOfficePageCount = false,
    this.ignoreLibreOfficeCanvasSize = false,
    this.expectedTextFragments = const <String>[],
  });

  final String name;
  final bool applicationExample;
  final bool packageExternal;
  final bool packageFixture;
  final bool ignoreLibreOfficePageCount;
  final bool ignoreLibreOfficeCanvasSize;
  final List<String> expectedTextFragments;

  String get path => applicationExample
      ? '$_appExampleDirectory/$name'
      : packageExternal
      ? '$_packageExternalDirectory/$name'
      : packageFixture
      ? '$_packageFixtureDirectory/$name'
      : '$_upstreamDirectory/$name';
}

Set<String> _visibleTexts(VsdxDocument document) {
  final out = <String>{};
  void walk(VsdxShape shape) {
    if (!shape.richText.textBlock.hideText &&
        shape.richText.plainText.trim().isNotEmpty) {
      out.add(shape.richText.plainText);
    }
    for (final child in shape.children) {
      walk(child);
    }
  }

  for (final page in document.pages) {
    for (final shape in page.shapes) {
      walk(shape);
    }
  }
  return out;
}

Future<List<File>> _renderWithLibreOffice({
  required String soffice,
  required String pdftoppm,
  required File source,
  required Directory outputDirectory,
}) async {
  final profile = Directory('${outputDirectory.path}/lo-profile')
    ..createSync(recursive: true);
  final converted = await Process.run(
    soffice,
    <String>[
      '--headless',
      '--norestore',
      '--nofirststartwizard',
      '-env:UserInstallation=file://${profile.path}',
      '--convert-to',
      'pdf',
      '--outdir',
      outputDirectory.path,
      source.absolute.path,
    ],
    environment: <String, String>{
      ...Platform.environment,
      'SAL_USE_VCLPLUGIN': 'svp',
    },
  );
  if (converted.exitCode != 0) {
    throw TestFailure(
      'LibreOffice failed for ${source.path}: ${converted.stderr}\n'
      '${converted.stdout}',
    );
  }
  final stem = source.uri.pathSegments.last.replaceFirst(
    RegExp(r'\.[^.]+$'),
    '',
  );
  final pdf = File('${outputDirectory.path}/$stem.pdf');
  if (!pdf.existsSync() || pdf.lengthSync() <= 100) {
    throw TestFailure(
      'LibreOffice produced no usable PDF for ${source.path}: '
      '${converted.stderr}\n${converted.stdout}',
    );
  }

  final prefix = '${outputDirectory.path}/libreoffice';
  final rasterized = await Process.run(pdftoppm, <String>[
    '-png',
    '-r',
    '72',
    pdf.path,
    prefix,
  ]);
  if (rasterized.exitCode != 0) {
    throw TestFailure(
      'pdftoppm failed for ${source.path}: ${rasterized.stderr}',
    );
  }
  final pages =
      outputDirectory
          .listSync()
          .whereType<File>()
          .where((file) => RegExp(r'libreoffice-\d+\.png$').hasMatch(file.path))
          .toList()
        ..sort((a, b) => _pageNumber(a.path).compareTo(_pageNumber(b.path)));
  if (pages.isEmpty) {
    throw TestFailure('pdftoppm produced no pages for ${source.path}');
  }
  return pages;
}

int _pageNumber(String path) =>
    int.parse(RegExp(r'-(\d+)\.png$').firstMatch(path)!.group(1)!);

String _safeName(String name) =>
    name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

Future<_DecodedImage> _decodePng(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (data == null) {
      frame.image.dispose();
      throw TestFailure('could not decode PNG pixels');
    }
    return _DecodedImage(
      frame.image.width,
      frame.image.height,
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      frame.image,
    );
  } finally {
    codec.dispose();
  }
}

class _DecodedImage {
  const _DecodedImage(this.width, this.height, this.rgba, this.image);

  final int width;
  final int height;
  final Uint8List rgba;
  final ui.Image image;

  void dispose() => image.dispose();
}

class _ImageMetrics {
  const _ImageMetrics({
    required this.width,
    required this.height,
    required this.inkFraction,
    required this.colorFraction,
    required this.bboxFraction,
  });

  final int width;
  final int height;
  final double inkFraction;
  final double colorFraction;
  final double bboxFraction;
}

_ImageMetrics _measure(_DecodedImage image) {
  var ink = 0;
  var color = 0;
  var minX = image.width;
  var minY = image.height;
  var maxX = -1;
  var maxY = -1;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final offset = (y * image.width + x) * 4;
      final r = image.rgba[offset];
      final g = image.rgba[offset + 1];
      final b = image.rgba[offset + 2];
      final a = image.rgba[offset + 3];
      final isInk = a >= 16 && (r < 248 || g < 248 || b < 248);
      if (!isInk) continue;
      ink++;
      minX = math.min(minX, x);
      minY = math.min(minY, y);
      maxX = math.max(maxX, x);
      maxY = math.max(maxY, y);
      if (math.max(r, math.max(g, b)) - math.min(r, math.min(g, b)) >= 16) {
        color++;
      }
    }
  }
  final pixels = image.width * image.height;
  final bboxPixels = ink == 0 ? 0 : (maxX - minX + 1) * (maxY - minY + 1);
  return _ImageMetrics(
    width: image.width,
    height: image.height,
    inkFraction: ink / pixels,
    colorFraction: color / pixels,
    bboxFraction: bboxPixels / pixels,
  );
}

class _ImageComparison {
  const _ImageComparison({
    required this.meanAbsoluteError,
    required this.inkIntersectionOverUnion,
  });

  final double meanAbsoluteError;
  final double inkIntersectionOverUnion;
}

_ImageComparison _compare(_DecodedImage app, _DecodedImage reference) {
  const sampleWidth = 128;
  const sampleHeight = 128;
  var absoluteError = 0.0;
  var intersection = 0;
  var union = 0;
  for (var y = 0; y < sampleHeight; y++) {
    final appY = math.min(app.height - 1, y * app.height ~/ sampleHeight);
    final refY = math.min(
      reference.height - 1,
      y * reference.height ~/ sampleHeight,
    );
    for (var x = 0; x < sampleWidth; x++) {
      final appX = math.min(app.width - 1, x * app.width ~/ sampleWidth);
      final refX = math.min(
        reference.width - 1,
        x * reference.width ~/ sampleWidth,
      );
      final appOffset = (appY * app.width + appX) * 4;
      final refOffset = (refY * reference.width + refX) * 4;
      final appLuma = _luma(app.rgba, appOffset);
      final refLuma = _luma(reference.rgba, refOffset);
      absoluteError += (appLuma - refLuma).abs() / 255;
      final appInk = appLuma < 248;
      final refInk = refLuma < 248;
      if (appInk && refInk) intersection++;
      if (appInk || refInk) union++;
    }
  }
  return _ImageComparison(
    meanAbsoluteError: absoluteError / (sampleWidth * sampleHeight),
    inkIntersectionOverUnion: union == 0 ? 1 : intersection / union,
  );
}

double _luma(Uint8List rgba, int offset) =>
    rgba[offset] * 0.2126 +
    rgba[offset + 1] * 0.7152 +
    rgba[offset + 2] * 0.0722;

String? _resolveExecutable({
  required String environmentName,
  required List<String> names,
  String? macFallback,
}) {
  final environmentPath = Platform.environment[environmentName];
  if (environmentPath != null &&
      environmentPath.isNotEmpty &&
      File(environmentPath).existsSync()) {
    return environmentPath;
  }
  for (final name in names) {
    final which = Process.runSync('which', <String>[name]);
    if (which.exitCode == 0) {
      final path = (which.stdout as String).trim();
      if (path.isNotEmpty) return path;
    }
  }
  if (macFallback != null && File(macFallback).existsSync()) {
    return macFallback;
  }
  return null;
}
