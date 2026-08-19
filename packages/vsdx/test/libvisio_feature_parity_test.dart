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

import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

import 'support/libvisio_features.dart';
import 'support/libvisio_oracle.dart';
import 'support/visio_corpus.dart';

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

    final files = collectVisioCorpus();
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
        gaps.add('${corpusLabel(file)}: parse failed: $error');
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
          gaps.add(
            '${corpusLabel(file)}: libvisio paints "$feature", we do not',
          );
        }
      }
    }

    expect(compared, greaterThan(10), reason: 'too few fixtures compared');
    expect(gaps, isEmpty, reason: 'feature parity gaps:\n${gaps.join('\n')}');
  });
}
