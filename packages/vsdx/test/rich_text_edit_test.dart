import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  VsdxRichText multi() => const VsdxRichText(
        runs: <VsdxTextRun>[
          VsdxTextRun(
            text: 'Hello',
            charStyle: VsdxCharStyle(
              style: VsdxFontStyle.boldStyle,
              fontSizeInches: 0.2,
            ),
          ),
          VsdxTextRun(
            text: ' World',
            charStyle: VsdxCharStyle(fontSizeInches: 0.2),
          ),
        ],
      );

  group('applyCharStyleToRange', () {
    test('bolds only the selected substring and splits runs', () {
      const rich = VsdxRichText(
        runs: <VsdxTextRun>[
          VsdxTextRun(text: 'Hello World'),
        ],
      );
      final next = applyCharStyleToRange(
        rich,
        start: 0,
        end: 5,
        update: (c) => c.copyWith(style: c.style.copyWith(bold: true)),
      );
      expect(next.plainText, 'Hello World');
      expect(next.runs, hasLength(2));
      expect(next.runs[0].text, 'Hello');
      expect(next.runs[0].charStyle.style.bold, isTrue);
      expect(next.runs[1].text, ' World');
      expect(next.runs[1].charStyle.style.bold, isFalse);
    });

    test('merges adjacent runs when styles become identical', () {
      final rich = multi();
      // Un-bold the first run so both match.
      final next = applyCharStyleToRange(
        rich,
        start: 0,
        end: 5,
        update: (c) => c.copyWith(style: c.style.copyWith(bold: false)),
      );
      expect(next.runs, hasLength(1));
      expect(next.runs.single.text, 'Hello World');
      expect(next.runs.single.charStyle.style.bold, isFalse);
    });
  });

  group('replacePlainText', () {
    test('preserves styles on the common prefix and suffix', () {
      final rich = multi();
      final next = replacePlainText(rich, 'Hello there World');
      expect(next.plainText, 'Hello there World');
      // "Hello" stays bold.
      expect(next.runs.first.text.startsWith('Hello'), isTrue);
      expect(next.runs.first.charStyle.style.bold, isTrue);
      // Trailing " World" stays non-bold (suffix).
      expect(next.runs.last.text.endsWith('World'), isTrue);
      expect(next.runs.last.charStyle.style.bold, isFalse);
    });

    test('does not flatten mixed styles when text is unchanged', () {
      final rich = multi();
      final next = replacePlainText(rich, 'Hello World');
      expect(next.runs, hasLength(2));
      expect(next.runs[0].charStyle.style.bold, isTrue);
      expect(next.runs[1].charStyle.style.bold, isFalse);
    });

    test('inserts in the middle inherit the caret style', () {
      final rich = multi();
      // Insert after "Hello" (bold) → "HelloX World"
      final next = replacePlainText(rich, 'HelloX World');
      expect(next.plainText, 'HelloX World');
      final atX = charStyleAt(next, 5)!; // 'X'
      expect(atX.style.bold, isTrue);
    });
  });

  group('charStyleAt', () {
    test('returns the run style covering the index', () {
      final rich = multi();
      expect(charStyleAt(rich, 0)!.style.bold, isTrue);
      expect(charStyleAt(rich, 6)!.style.bold, isFalse);
    });
  });
}
