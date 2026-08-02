/// Differential tests: our parser vs **libvisio** (the reference C++ importer)
/// used as an oracle over `dart:ffi` (see `native/` and `support/`).
///
/// Test plan
/// ---------
/// For every bundled fixture we render it with libvisio and assert our parser
/// agrees on the properties that earlier regressions got wrong — the classes of
/// bug that recurred because we only ever reasoned about libvisio instead of
/// running it:
///
///  1. Page count.
///  2. Per-page size in inches (guards the "V is internal units" fix — page
///     dimensions used to come out ~25x too small).
///  3. The set of text font sizes in points (guards the same units fix for the
///     Character `Size` cell — text used to be ~72x too small).
///  4. The multiset of visible (non-whitespace) text characters extracted
///     (guards text parsing incl. the trailing-whitespace trim). Compared as a
///     character multiset so line-wrapping differences between the two
///     renderers don't matter.
///
/// The whole group skips cleanly when the libvisio shim hasn't been built
/// (`native/build.sh`, needs `brew install libvisio`).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

import 'support/libvisio_oracle.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

// Remaining known differences from libvisio, each tracked explicitly so the
// suite stays green *and* the backlog is visible — any NEW divergence (or a
// fixture leaving these sets) still fails loudly.
//
//  * test5_master: Lucidchart `com.lucidchart.Line` shapes (Line 1/2/3 @ 8pt)
//    are present in the VSDX and in our model, but libvisio's SVG exporter
//    omits them entirely (no path, no tspan). Not a StyleSheet bug.
const Set<String> _fontSizeGaps = <String>{
  'test5_master.vsdx',
};
const Set<String> _textContentGaps = <String>{
  'test5_master.vsdx',
};

List<String> _fixtureNames() => Directory('test/fixtures')
    .listSync()
    .whereType<File>()
    .map((f) => f.uri.pathSegments.last)
    .where((n) => n.endsWith('.vsdx'))
    .toList()
  ..sort();

// --- libvisio (SVG) feature extraction -------------------------------------

({double w, double h})? _svgSizeInches(String svg) {
  final m =
      RegExp(r'width="([0-9.]+)in"\s+height="([0-9.]+)in"').firstMatch(svg);
  if (m == null) return null;
  return (w: double.parse(m.group(1)!), h: double.parse(m.group(2)!));
}

Set<double> _svgFontSizesPt(String svg) => RegExp(r'font-size="([0-9.]+)"')
    .allMatches(svg)
    .map((m) => _round05(double.parse(m.group(1)!)))
    .toSet();

String _svgTextChars(String svg) {
  final sb = StringBuffer();
  for (final m
      in RegExp(r'<(?:\w+:)?tspan\b[^>]*>(.*?)</(?:\w+:)?tspan>', dotAll: true)
          .allMatches(svg)) {
    sb.write(_unescapeXml(m.group(1)!));
  }
  return _sortedNonWhitespace(sb.toString());
}

// --- our model feature extraction ------------------------------------------

void _walk(VsdxDocument doc, void Function(VsdxShape) visit) {
  void rec(VsdxShape s) {
    visit(s);
    for (final c in s.children) {
      rec(c);
    }
  }

  for (final p in doc.pages) {
    for (final s in p.shapes) {
      rec(s);
    }
  }
}

String _shapeText(VsdxShape s) =>
    s.richText.runs.isNotEmpty ? s.richText.plainText : (s.text ?? '');

Set<double> _modelFontSizesPt(VsdxDocument doc) {
  final out = <double>{};
  _walk(doc, (s) {
    if (s.richText.textBlock.hideText) return;
    for (final r in s.richText.runs) {
      if (r.text.trim().isEmpty) continue;
      out.add(_round05(r.charStyle.fontSizeInches * 72));
    }
  });
  return out;
}

String _modelTextChars(VsdxDocument doc) {
  final sb = StringBuffer();
  _walk(doc, (s) {
    if (s.richText.textBlock.hideText) return;
    sb.write(_shapeText(s));
  });
  return _sortedNonWhitespace(sb.toString());
}

// --- helpers ---------------------------------------------------------------

double _round05(double v) => (v * 2).round() / 2;

String _sortedNonWhitespace(String s) {
  final chars = s.replaceAll(RegExp(r'\s+'), '').split('')..sort();
  return chars.join();
}

String _unescapeXml(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

void main() {
  final oracle = LibvisioOracle.tryLoad();
  final skipReason = oracle == null
      ? 'libvisio shim not built — run packages/vsdx/native/build.sh '
          '(needs `brew install libvisio`)'
      : null;

  const parser = DocumentParser();

  group('differential parse vs libvisio', () {
    test('oracle is available (build native/libvisio_shim.dylib to enable)',
        () {
      expect(oracle, isNotNull, reason: skipReason);
    }, skip: skipReason);

    for (final name in _fixtureNames()) {
      group(name, () {
        late List<String> pages;
        late VsdxDocument doc;

        setUp(() {
          final bytes = _fixture(name);
          final p = oracle!.svgPages(bytes);
          if (p == null) {
            markTestSkipped('libvisio could not parse $name');
            pages = const <String>[];
            doc = parser.parse(bytes);
            return;
          }
          pages = p;
          doc = parser.parse(bytes);
        });

        test('page count matches libvisio', () {
          if (pages.isEmpty) return;
          expect(doc.pages.length, pages.length);
        }, skip: skipReason);

        test('per-page size (inches) matches libvisio', () {
          if (pages.isEmpty) return;
          final n =
              doc.pages.length < pages.length ? doc.pages.length : pages.length;
          for (var i = 0; i < n; i++) {
            final ref = _svgSizeInches(pages[i]);
            if (ref == null) continue;
            expect(doc.pages[i].widthInches, closeTo(ref.w, 0.02),
                reason: '$name page $i width');
            expect(doc.pages[i].heightInches, closeTo(ref.h, 0.02),
                reason: '$name page $i height');
          }
        }, skip: skipReason);

        test('text font sizes (pt) match libvisio', () {
          if (pages.isEmpty) return;
          final ref = <double>{};
          for (final svg in pages) {
            ref.addAll(_svgFontSizesPt(svg));
          }
          if (ref.isEmpty) return; // no text on the page
          expect(_modelFontSizesPt(doc), ref, reason: '$name font sizes');
        },
            skip: skipReason ??
                (_fontSizeGaps.contains(name)
                    ? 'known gap: libvisio SVG omits Lucidchart Line labels '
                        '(test5) — model retains them'
                    : null));

        test('visible text characters match libvisio', () {
          if (pages.isEmpty) return;
          final ref = StringBuffer();
          for (final svg in pages) {
            ref.write(_svgTextChars(svg));
          }
          final refChars = _sortedNonWhitespace(ref.toString());
          if (refChars.isEmpty) return;
          expect(_modelTextChars(doc), refChars, reason: '$name text content');
        },
            skip: skipReason ??
                (_textContentGaps.contains(name)
                    ? 'known gap: libvisio SVG omits Lucidchart Line labels '
                        '(test5) — model retains them'
                    : null));
      });
    }
  });

  test('direct StyleSheet cells and THEMEGUARD cached colours are parsed', () {
    final styled = parser.parse(_fixture('test1.vsdx'));
    final weights = <double>{};
    final lineColors = <int>{};
    final fillColors = <int>{};
    _walk(styled, (shape) {
      weights.add(shape.line.weightInches);
      if (shape.line.color != null) lineColors.add(shape.line.color!.value);
      if (shape.fill.foreground != null) {
        fillColors.add(shape.fill.foreground!.value);
      }
    });
    expect(weights, contains(closeTo(0.01041666666666667, 1e-12)));
    expect(lineColors, contains(VsdxColor.black.value));
    expect(fillColors, contains(VsdxColor.white.value));

    final guarded = parser.parse(_fixture('test12_colors.vsdx'));
    final guardedLines = <int>{};
    final guardedFills = <int>{};
    _walk(guarded, (shape) {
      if (shape.line.color != null) guardedLines.add(shape.line.color!.value);
      if (shape.fill.foreground != null) {
        guardedFills.add(shape.fill.foreground!.value);
      }
    });
    expect(guardedLines, containsAll(<int>[0xFFFF0000, 0xFF00FF00]));
    expect(guardedFills, containsAll(<int>[0xFFFF0000, 0xFF00FF00]));
  });

  group('identity write → libvisio oracle', () {
    for (final name in _fixtureNames()) {
      if (_fontSizeGaps.contains(name) || _textContentGaps.contains(name)) {
        continue; // known SVG omissions (e.g. test5 Lucidchart Lines)
      }
      test('$name noop save keeps fonts + text vs libvisio', () {
        if (oracle == null) return;
        const writer = VsdxWriter();
        final bytes = _fixture(name);
        final doc = parser.parse(bytes);
        final saved = writer.write(originalBytes: bytes, edited: doc);
        final pages = oracle.svgPages(saved);
        expect(pages, isNotNull, reason: 'libvisio must open saved $name');
        final reparsed = parser.parse(saved);

        final refFonts = <double>{};
        final refChars = StringBuffer();
        for (final svg in pages!) {
          refFonts.addAll(_svgFontSizesPt(svg));
          refChars.write(_svgTextChars(svg));
        }
        if (refFonts.isNotEmpty) {
          expect(_modelFontSizesPt(reparsed), refFonts,
              reason: '$name fonts after identity write');
        }
        final refSorted = _sortedNonWhitespace(refChars.toString());
        if (refSorted.isNotEmpty) {
          expect(_modelTextChars(reparsed), refSorted,
              reason: '$name text after identity write');
        }
      }, skip: skipReason);
    }
  });
}
