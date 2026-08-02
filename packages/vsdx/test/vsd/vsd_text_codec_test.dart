import 'package:test/test.dart';
import 'package:vsdx/src/parser/vsd/vsd_text_codec.dart';

void main() {
  group('legacy VSD FontIX text codecs', () {
    test('maps every libvisio FontIX code-page selector', () {
      expect(vsdLegacyEncodingForCodePage(0x02), VsdLegacyTextEncoding.symbol);
      expect(vsdLegacyEncodingForCodePage(0xa1), VsdLegacyTextEncoding.greek);
      expect(vsdLegacyEncodingForCodePage(0xa2), VsdLegacyTextEncoding.turkish);
      expect(
          vsdLegacyEncodingForCodePage(0xa3), VsdLegacyTextEncoding.vietnamese);
      expect(vsdLegacyEncodingForCodePage(0xb1), VsdLegacyTextEncoding.hebrew);
      expect(vsdLegacyEncodingForCodePage(0xb2), VsdLegacyTextEncoding.arabic);
      expect(vsdLegacyEncodingForCodePage(0xba), VsdLegacyTextEncoding.baltic);
      expect(vsdLegacyEncodingForCodePage(0xcc), VsdLegacyTextEncoding.russian);
      expect(vsdLegacyEncodingForCodePage(0xde), VsdLegacyTextEncoding.thai);
      expect(vsdLegacyEncodingForCodePage(0xee),
          VsdLegacyTextEncoding.centralEurope);
      expect(
          vsdLegacyEncodingForCodePage(0x80), VsdLegacyTextEncoding.japanese);
      expect(vsdLegacyEncodingForCodePage(0x81), VsdLegacyTextEncoding.korean);
      expect(vsdLegacyEncodingForCodePage(0x86),
          VsdLegacyTextEncoding.simplifiedChinese);
      expect(vsdLegacyEncodingForCodePage(0x88),
          VsdLegacyTextEncoding.traditionalChinese);
      expect(vsdLegacyEncodingForCodePage(0), VsdLegacyTextEncoding.ansi);
    });

    test('decodes Windows and Symbol spans like libvisio', () {
      expect(
        decodeVsdLegacyText(
          [0x80, 0x20, 0x93, 0x41, 0x94],
          VsdLegacyTextEncoding.ansi,
        ),
        '€ “A”',
      );
      expect(
        decodeVsdLegacyText(
          [0x41, 0x61, 0xa3, 0xb3],
          VsdLegacyTextEncoding.symbol,
        ),
        'Αα≤≥',
      );
      expect(
        decodeVsdLegacyText(
          List<int>.generate(0xdf, (index) => index + 0x20),
          VsdLegacyTextEncoding.symbol,
        ).runes,
        hasLength(0xdf),
      );
      expect(
        decodeVsdLegacyText(
          [0xcf, 0xf0, 0xe8, 0xe2, 0xe5, 0xf2],
          VsdLegacyTextEncoding.russian,
        ),
        'Привет',
      );
      expect(
        decodeVsdLegacyText(
          [0x50, 0xf8, 0xed, 0x6c, 0x69, 0x9a],
          VsdLegacyTextEncoding.centralEurope,
        ),
        'Příliš',
      );
      expect(decodeVsdLegacyText([0xc1], VsdLegacyTextEncoding.greek), 'Α');
      expect(decodeVsdLegacyText([0xd0], VsdLegacyTextEncoding.turkish), 'Ğ');
      expect(
          decodeVsdLegacyText([0xd5], VsdLegacyTextEncoding.vietnamese), 'Ơ');
      expect(
        decodeVsdLegacyText(
          [0xf9, 0xec, 0xe5, 0xed],
          VsdLegacyTextEncoding.hebrew,
        ),
        'שלום',
      );
      expect(
        decodeVsdLegacyText(
          [0xe3, 0xd1, 0xcd, 0xc8, 0xc7],
          VsdLegacyTextEncoding.arabic,
        ),
        'مرحبا',
      );
      expect(decodeVsdLegacyText([0xc0], VsdLegacyTextEncoding.baltic), 'Ą');
      expect(
        decodeVsdLegacyText(
          [0xca, 0xc7, 0xd1, 0xca, 0xb4, 0xd5],
          VsdLegacyTextEncoding.thai,
        ),
        'สวัสดี',
      );
    });

    test('decodes all legacy CJK selectors', () {
      expect(
        decodeVsdLegacyText(
          [0x83, 0x65, 0x83, 0x58, 0x83, 0x67],
          VsdLegacyTextEncoding.japanese,
        ),
        'テスト',
      );
      expect(
        decodeVsdLegacyText(
          [0xc5, 0xd7, 0xbd, 0xba, 0xc6, 0xae],
          VsdLegacyTextEncoding.korean,
        ),
        '테스트',
      );
      expect(
        decodeVsdLegacyText(
          [0xd6, 0xd0, 0xce, 0xc4],
          VsdLegacyTextEncoding.simplifiedChinese,
        ),
        '中文',
      );
      expect(
        decodeVsdLegacyText(
          [0xa4, 0xa4, 0xa4, 0xe5],
          VsdLegacyTextEncoding.traditionalChinese,
        ),
        '中文',
      );
    });

    test('handles Visio breaks and fields before Symbol conversion', () {
      expect(
        decodeVsdLegacyText(
          [0x41, 0x0d, 0x42, 0x0e, 0x1e],
          VsdLegacyTextEncoding.symbol,
        ),
        'Α\nΒ\n\u001e',
      );
    });
  });
}
