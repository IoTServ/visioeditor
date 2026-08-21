/// Does a saved document still *look* the same to LibreOffice?
///
/// Every other round-trip check compares structure: our model with itself, or
/// what libvisio reads back. This one renders the original and our saved
/// package through `soffice` and diffs the pixels, which is the only way to
/// catch a save that keeps every shape but moves, resizes or recolours it.
///
/// Both sides go through the same converter, so the comparison is insensitive
/// to how faithful LibreOffice is to Visio — it measures only what our writer
/// changed. Legacy `.vsd` / `.vdx` sources go through the synthesised `.vsdx`
/// baseline, so this is also the import-then-save path.
///
/// Opt in with `RUN_LIBREOFFICE_ROUNDTRIP=1` (CI's LibreOffice job sets it);
/// each file costs two headless conversions.
@Timeout(Duration(minutes: 30))
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as raster;
import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

import 'support/visio_corpus.dart';

const _runEnvironment = 'RUN_LIBREOFFICE_ROUNDTRIP';

/// Substring filter over file names, to re-check one document quickly.
const _filterEnvironment = 'VISIO_ROUNDTRIP_FILTER';

/// Worst observed mean absolute error over the full corpus is 0.0200
/// (`人才招聘冰山模型.vsdx`), with everything else at or below 0.0147. This
/// leaves room for renderer noise while still failing on a real shift.
const _maxMeanAbsoluteError = 0.03;

/// Sources LibreOffice barely renders, where the saved package legitimately
/// shows *more*. libvisio's field formatter has no case for units, currency
/// or percentages, so opening the legacy binary drops those values; our
/// synthesised VSDX carries them as text and LibreOffice then draws them.
/// `vdx_all_types.vdx` is the geometry counterpart: DiagramML CubBezTo /
/// QuadBezTo / RelArcTo are absent from libvisio's VDX switch, so Draw
/// skips those curves in the source and paints them once we rewrite the
/// rows as RelCubBezTo / RelQuadBezTo / ArcTo. Pixel equality is the wrong
/// expectation for these — the structural round-trip suite covers them.
const _recoversFieldText = <String>{
  'Visio5TextFieldsWithUnits.vsd',
  'Visio6TextFieldsWithUnits.vsd',
  'Visio11TextFieldsWithUnits.vsd',
  'Visio11TextFieldsWithCurrency.vsd',
  'vdx_all_types.vdx',
};

/// Sources whose original Draw view is hollow because libvisio has no
/// FillGradient token (FillPattern omitted / 0). A save writes classic
/// FillPattern 25–40, so the saved PDF is *supposed* to look different.
const _recoversOmittedFillGradient = <String>{
  '人才招聘冰山模型.vsdx',
  '数据治理.vsdx',
};

void main() {
  final enabled = Platform.environment[_runEnvironment] == '1';
  final soffice = _resolveExecutable(const <String>['soffice', 'libreoffice'],
      macFallback: '/Applications/LibreOffice.app/Contents/MacOS/soffice');
  final pdftoppm = _resolveExecutable(const <String>['pdftoppm']);

  test('LibreOffice renders a saved document like the original', () async {
    expect(soffice, isNotNull, reason: 'LibreOffice soffice is required');
    expect(pdftoppm, isNotNull, reason: 'Poppler pdftoppm is required');

    final filter = Platform.environment[_filterEnvironment] ?? '';
    final files = <File>[
      for (final file in collectVisioCorpus())
        if (filter.isEmpty || file.path.contains(filter)) file,
    ];
    expect(files, isNotEmpty, reason: 'no Visio fixtures match "$filter"');
    final minimumCompared = filter.isEmpty ? 10 : 0;

    final root = await Directory.systemTemp.createTemp('vsdx_lo_roundtrip_');
    final failures = <String>[];
    var compared = 0;

    try {
      for (final file in files) {
        final label = corpusLabel(file);
        final bytes = Uint8List.fromList(file.readAsBytesSync());
        final VisioParseResult parsed;
        try {
          parsed = parseVisio(bytes, sourceName: file.path);
        } catch (error) {
          failures.add('$label: parse failed: $error');
          continue;
        }
        final saved = const VsdxWriter().write(
          originalBytes: parsed.originalBytes,
          edited: parsed.document,
        );

        final caseDirectory = Directory('${root.path}/${_safeName(label)}')
          ..createSync(recursive: true);
        final originalFile =
            File('${caseDirectory.path}/original${_extension(file.path)}')
              ..writeAsBytesSync(bytes);
        final savedFile = File('${caseDirectory.path}/saved.vsdx')
          ..writeAsBytesSync(saved);

        final before = await _render(
            soffice!, pdftoppm!, originalFile, caseDirectory, 'before');
        final after = await _render(
            soffice, pdftoppm, savedFile, caseDirectory, 'after');
        if (before == null) continue; // LibreOffice declines this source
        if (after == null) {
          failures.add('$label: LibreOffice cannot open the saved package');
          continue;
        }
        compared++;

        // Compare the saved page count with our model, not with LibreOffice's
        // reading of the source: `recursion-cycle.vsdx` loops its page
        // relationship back to `pages.xml` and LibreOffice follows it into two
        // phantom pages. The writer's job is to emit what we parsed.
        if (after.length != parsed.document.pages.length) {
          failures.add(
            '$label: LibreOffice shows ${after.length} saved pages, '
            'model has ${parsed.document.pages.length}',
          );
          continue;
        }

        final pages = math.min(before.length, after.length);
        for (var index = 0; index < pages; index++) {
          final a = before[index];
          final b = after[index];
          if ((a.width - b.width).abs() > 2 ||
              (a.height - b.height).abs() > 2) {
            failures.add(
              '$label page ${index + 1}: canvas ${a.width}x${a.height} → '
              '${b.width}x${b.height}',
            );
            continue;
          }
          if (_recoversFieldText.contains(file.uri.pathSegments.last)) continue;
          if (_recoversOmittedFillGradient.contains(file.uri.pathSegments.last)) {
            continue;
          }
          final error = _meanAbsoluteError(a, b);
          if (error > _maxMeanAbsoluteError) {
            failures.add(
              '$label page ${index + 1}: mean absolute error '
              '${error.toStringAsFixed(4)} > $_maxMeanAbsoluteError',
            );
          }
        }
      }

      expect(
        compared,
        greaterThanOrEqualTo(minimumCompared),
        reason: 'too few documents compared',
      );
      expect(
        failures,
        isEmpty,
        reason: 'LibreOffice round-trip differences:\n${failures.join('\n')}',
      );
    } finally {
      await root.delete(recursive: true);
    }
  }, skip: enabled ? false : 'set $_runEnvironment=1 to run this comparison');
}

String _extension(String path) {
  final dot = path.lastIndexOf('.');
  return dot < 0 ? '' : path.substring(dot);
}

String _safeName(String name) =>
    name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

Future<List<raster.Image>?> _render(
  String soffice,
  String pdftoppm,
  File source,
  Directory caseDirectory,
  String tag,
) async {
  final output = Directory('${caseDirectory.path}/$tag')
    ..createSync(recursive: true);
  final profile = Directory('${output.path}/profile')..createSync();
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
      output.path,
      source.absolute.path,
    ],
    environment: <String, String>{
      ...Platform.environment,
      'SAL_USE_VCLPLUGIN': 'svp',
    },
  );
  if (converted.exitCode != 0) return null;
  final stem =
      source.uri.pathSegments.last.replaceFirst(RegExp(r'\.[^.]+$'), '');
  final pdf = File('${output.path}/$stem.pdf');
  if (!pdf.existsSync() || pdf.lengthSync() <= 100) return null;

  final rasterized = await Process.run(
    pdftoppm,
    <String>['-png', '-r', '72', pdf.path, '${output.path}/page'],
  );
  if (rasterized.exitCode != 0) return null;
  final pages = output
      .listSync()
      .whereType<File>()
      .where((file) => RegExp(r'page-\d+\.png$').hasMatch(file.path))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  if (pages.isEmpty) return null;
  return <raster.Image>[
    for (final page in pages) raster.decodePng(page.readAsBytesSync())!,
  ];
}

/// Luma difference over a fixed sampling grid, so pages of different pixel
/// sizes still compare at the same cost.
double _meanAbsoluteError(raster.Image a, raster.Image b) {
  const samples = 160;
  var total = 0.0;
  for (var y = 0; y < samples; y++) {
    for (var x = 0; x < samples; x++) {
      final pa = a.getPixel(
        math.min(a.width - 1, x * a.width ~/ samples),
        math.min(a.height - 1, y * a.height ~/ samples),
      );
      final pb = b.getPixel(
        math.min(b.width - 1, x * b.width ~/ samples),
        math.min(b.height - 1, y * b.height ~/ samples),
      );
      total += (_luma(pa) - _luma(pb)).abs() / 255;
    }
  }
  return total / (samples * samples);
}

double _luma(raster.Pixel pixel) =>
    pixel.r * 0.2126 + pixel.g * 0.7152 + pixel.b * 0.0722;

String? _resolveExecutable(List<String> names, {String? macFallback}) {
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
