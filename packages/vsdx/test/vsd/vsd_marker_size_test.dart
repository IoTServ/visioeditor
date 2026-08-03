import 'package:test/test.dart';
import 'package:vsdx/src/parser/vsd/vsd_parser.dart'
    show vsdLibvisioMarkerSizeInches;

void main() {
  group('vsdLibvisioMarkerSizeInches', () {
    test('matches libvisio marker type scales', () {
      expect(
        vsdLibvisioMarkerSizeInches(
          marker: 1,
          strokeWidthInches: 0,
        ),
        closeTo(0.1, 1e-12),
      );
      expect(
        vsdLibvisioMarkerSizeInches(
          marker: 10,
          strokeWidthInches: 0,
        ),
        closeTo(0.07, 1e-12),
      );
      expect(
        vsdLibvisioMarkerSizeInches(
          marker: 14,
          strokeWidthInches: 0,
        ),
        closeTo(0.12, 1e-12),
      );
    });

    test('uses line width, drawing scale and the physical floor', () {
      expect(
        vsdLibvisioMarkerSizeInches(
          marker: 1,
          strokeWidthInches: 0.5,
        ),
        closeTo(1.35, 1e-12),
      );
      expect(
        vsdLibvisioMarkerSizeInches(
          marker: 1,
          strokeWidthInches: 0,
          pageScale: 2,
        ),
        closeTo(0.2, 1e-12),
      );
      expect(
        vsdLibvisioMarkerSizeInches(
          marker: 10,
          strokeWidthInches: 0,
          pageScale: 0.25,
        ),
        closeTo(0.05, 1e-12),
      );
    });
  });
}
