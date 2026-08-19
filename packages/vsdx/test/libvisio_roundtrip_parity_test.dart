/// Round-trip differential test: saving a document must not change what the
/// reference importer reads back out of it.
///
/// The other round-trip suites compare our model with itself, which cannot see
/// a writer that emits something only *we* understand. This one parses the
/// source, saves it, and asks libvisio — the importer LibreOffice drives — to
/// read both. Page count, page size, rendered letters, drawing features and
/// the number of painted objects all have to survive.
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

  test('a save preserves everything libvisio reads back', () {
    if (oracle == null) {
      markTestSkipped(
        'libvisio shim not built — run native/build.sh '
        '(needs `brew install libvisio`)',
      );
      return;
    }

    final files = collectVisioCorpus();
    expect(files, isNotEmpty, reason: 'no Visio fixtures found');

    final problems = <String>[];
    var compared = 0;

    for (final file in files) {
      final label = corpusLabel(file);
      final bytes = Uint8List.fromList(file.readAsBytesSync());
      final beforePages = oracle.svgPages(bytes);
      if (beforePages == null) continue; // libvisio declines this source

      final VisioParseResult parsed;
      try {
        parsed = parseVisio(bytes, sourceName: file.path);
      } catch (error) {
        problems.add('$label: parse failed: $error');
        continue;
      }
      final Uint8List saved;
      try {
        saved = const VsdxWriter().write(
          originalBytes: parsed.originalBytes,
          edited: parsed.document,
        );
      } catch (error) {
        problems.add('$label: write failed: $error');
        continue;
      }
      final afterPages = oracle.svgPages(saved);
      if (afterPages == null) {
        problems.add('$label: libvisio cannot reopen the saved package');
        continue;
      }

      final before = LibvisioObservation.of(beforePages);
      final after = LibvisioObservation.of(afterPages);
      compared++;

      // Compare the saved page count with our own model rather than with
      // libvisio's reading of the source. `recursion-cycle.vsdx` points its
      // page relationship back at `pages.xml`; libvisio follows the loop into
      // a phantom extra page and LibreOffice reports three. The writer's job
      // is to emit the one page we parsed.
      if (after.pages != parsed.document.pages.length) {
        problems.add(
          '$label: saved ${after.pages} pages, model has '
          '${parsed.document.pages.length}',
        );
      }
      if (!before.hasDegenerateSize &&
          before.sizes.join(',') != after.sizes.join(',')) {
        problems.add(
          '$label: page size ${before.sizes.join(",")} → '
          '${after.sizes.join(",")}',
        );
      }
      final lost = missingLetters(before.letters, after.letters);
      if (lost.isNotEmpty) {
        problems.add('$label: text lost "$lost"');
      }
      final lostFeatures = before.features.difference(after.features);
      if (lostFeatures.isNotEmpty) {
        problems.add('$label: lost ${lostFeatures.join(", ")}');
      }
      // Fewer painted objects means dropped geometry. More is normal: the
      // writer expands a master reference into the shapes it stands for.
      if (before.drawn > 0 && after.drawn < before.drawn * 0.95) {
        problems.add(
          '$label: painted objects ${before.drawn} → ${after.drawn}',
        );
      }
    }

    expect(compared, greaterThan(10), reason: 'too few fixtures compared');
    expect(
      problems,
      isEmpty,
      reason: 'round-trip parity gaps:\n${problems.join('\n')}',
    );
  });
}
