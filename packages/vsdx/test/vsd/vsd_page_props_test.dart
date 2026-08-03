import 'package:test/test.dart';
import 'package:vsdx/src/parser/vsd/vsd_parser.dart';

void main() {
  group('binary VSD PageProps libvisio parity', () {
    test('clamps only negative page dimensions', () {
      final props = vsdNormalizePageProps(
        pageWidth: -8.5,
        pageHeight: 0,
        pageScale: 1,
        drawingScale: 1,
      );

      expect(props.pageWidth, 0);
      expect(props.pageHeight, 0);
      expect(props.scale, 1);
    });

    test('normalizes DrawingScale through the inclusive VSD epsilon', () {
      for (final drawingScale in [0.0, 1e-7, -1e-7, 1e-6, -1e-6]) {
        final props = vsdNormalizePageProps(
          pageWidth: 8.5,
          pageHeight: 11,
          pageScale: 2,
          drawingScale: drawingScale,
        );

        expect(props.drawingScale, 1);
        expect(props.scale, 2);
      }
    });

    test('preserves a zero PageScale and takes absolute nonzero ratios', () {
      final zero = vsdNormalizePageProps(
        pageWidth: 8.5,
        pageHeight: 11,
        pageScale: 0,
        drawingScale: 2,
      );
      final negative = vsdNormalizePageProps(
        pageWidth: 8.5,
        pageHeight: 11,
        pageScale: -3,
        drawingScale: 2,
      );

      expect(zero.scale, 0);
      expect(negative.scale, 1.5);
      expect(negative.drawingScale, 2);
    });

    test('does not normalize values just outside the VSD epsilon', () {
      final props = vsdNormalizePageProps(
        pageWidth: 8.5,
        pageHeight: 11,
        pageScale: 2,
        drawingScale: -1.000001e-6,
      );

      expect(props.drawingScale, -1.000001e-6);
      expect(props.scale, closeTo(1999998.000002, 1e-6));
    });
  });
}
