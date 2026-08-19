/// Feature-level differential test: for every fixture we can find, whatever
/// drawing feature libvisio paints has to be painted here too.
///
/// The pixel corpus in the application package measures how close a page looks
/// to LibreOffice; this measures something the pixel metrics are bad at. A
/// whole feature can stop rendering — every gradient flattens to solid, every
/// dash goes solid, every arrowhead disappears — and still move the mean error
/// by less than the tolerance on a busy page. Comparing feature presence per
/// document catches that class of regression directly.
///
/// Skips cleanly when the libvisio shim has not been built (`native/build.sh`,
/// needs `brew install libvisio`).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

import 'support/libvisio_features.dart';
import 'support/libvisio_oracle.dart';

/// Bundled fixtures first, then the upstream libvisio corpus when the optional
/// `third_party` clone is present (see `third_party/README.md`).
const _searchDirectories = <String>[
  'test/fixtures',
  'test/fixtures/vsd',
  'test/fixtures/vsd/external',
  '../../third_party/libvisio/src/test/data',
];

const _visioExtensions = <String>{
  '.vsd', '.vss', '.vst',
  '.vdx', '.vsx', '.vtx',
  '.vsdx', '.vsdm', '.vstx', '.vstm', '.vssx', '.vssm',
};

void main() {
  final oracle = LibvisioOracle.tryLoad();

  test('every drawing feature libvisio paints is painted here too', () {
    if (oracle == null) {
      markTestSkipped(
        'libvisio shim not built — run native/build.sh '
        '(needs `brew install libvisio`)',
      );
      return;
    }

    final files = _collectFixtures();
    expect(files, isNotEmpty, reason: 'no Visio fixtures found');

    final gaps = <String>[];
    var compared = 0;

    for (final file in files) {
      final bytes = Uint8List.fromList(file.readAsBytesSync());
      final referencePages = oracle.svgPages(bytes);
      if (referencePages == null) continue; // libvisio declines this fixture

      final VsdxDocument document;
      try {
        document = parseVisio(bytes, sourceName: file.path).document;
      } catch (error) {
        gaps.add('${_label(file)}: parse failed: $error');
        continue;
      }

      // Compare whole documents. libvisio composites a background page into
      // each page that references one, so pairing pages index by index would
      // report phantom differences on every drawing that uses a background.
      final ours = StringBuffer();
      for (final page in document.pages) {
        ours.write(
          VsdxToSvgSerializer().serializePage(
            page,
            theme: document.theme,
            images: document.images,
            underlayPage: document.backgroundFor(page),
          ),
        );
      }
      final reference = referencePages.join();
      compared++;

      for (final feature in libvisioFeaturePatterns.keys) {
        final expected =
            paintsLibvisioFeature(feature, reference, libvisio: true);
        if (!expected) continue;
        final actual =
            paintsLibvisioFeature(feature, ours.toString(), libvisio: false);
        if (!actual) {
          gaps.add('${_label(file)}: libvisio paints "$feature", we do not');
        }
      }
    }

    expect(compared, greaterThan(10), reason: 'too few fixtures compared');
    expect(gaps, isEmpty, reason: 'feature parity gaps:\n${gaps.join('\n')}');
  });
}

List<File> _collectFixtures() {
  final out = <File>[];
  for (final path in _searchDirectories) {
    final directory = Directory(path);
    if (!directory.existsSync()) continue;
    for (final entity in directory.listSync()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final dot = name.lastIndexOf('.');
      if (dot < 0) continue;
      if (!_visioExtensions.contains(name.substring(dot).toLowerCase())) {
        continue;
      }
      out.add(entity);
    }
  }
  out.sort((a, b) => a.path.compareTo(b.path));
  return out;
}

String _label(File file) {
  final segments = file.uri.pathSegments;
  final parent =
      segments.length > 1 ? segments[segments.length - 2] : '';
  return '$parent/${segments.last}';
}
