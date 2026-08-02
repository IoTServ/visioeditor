import 'package:test/test.dart';
import 'package:vsdx/src/parser/vsd/vsd_parser.dart';

void main() {
  group('VSD5/VSD6 inherited shadow offsets', () {
    test('uses the drawing PageProps outside a stencil', () {
      final offsets = vsdResolveLegacyShadowOffsets(
        isStencil: false,
        stencilX: 0.25,
        stencilY: 0.25,
        pageX: 0.05,
        pageY: -0.05,
      );

      expect(offsets, (x: 0.05, y: -0.05));
    });

    test('uses the stencil PageProps while parsing a master', () {
      final offsets = vsdResolveLegacyShadowOffsets(
        isStencil: true,
        stencilX: 0.11811023622047244,
        stencilY: 0.11811023622047244,
        pageX: 0.05,
        pageY: -0.05,
      );

      expect(
        offsets,
        (x: 0.11811023622047244, y: 0.11811023622047244),
      );
    });
  });
}
