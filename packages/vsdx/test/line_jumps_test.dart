import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  test('segmentIntersection finds a proper interior crossing', () {
    final p = segmentIntersection(
      const Offset2D(0, 0),
      const Offset2D(2, 2),
      const Offset2D(0, 2),
      const Offset2D(2, 0),
    );
    expect(p, isNotNull);
    expect(p!.x, closeTo(1, 1e-9));
    expect(p.y, closeTo(1, 1e-9));
  });

  test('lineJumpsEnabledForCode turns jumps off only for code 0', () {
    expect(lineJumpsEnabledForCode(0), isFalse);
    expect(lineJumpsEnabledForCode(null), isTrue);
    expect(lineJumpsEnabledForCode(4), isTrue);
  });

  test('polylineWithJumpsSvg inserts an arc at a crossing', () {
    final route = <Offset2D>[const Offset2D(0, 1), const Offset2D(4, 1)];
    final unders = <List<Offset2D>>[
      <Offset2D>[const Offset2D(2, 0), const Offset2D(2, 2)],
    ];
    final plain = polylineSvg(route);
    final jumped = polylineWithJumpsSvg(route, unders, 0.2);
    expect(plain.contains(' A '), isFalse);
    expect(jumped.contains(' A '), isTrue);
    expect(jumped.length, greaterThan(plain.length));
  });

  test('SVG export emits arc jumps for crossing connectors', () {
    final h = VsdxShapeFactory.line(id: 1, ax: 1, ay: 3, bx: 5, by: 3);
    final v = VsdxShapeFactory.line(id: 2, ax: 3, ay: 5, bx: 3, by: 1);
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 8,
      heightInches: 11,
      shapes: <VsdxShape>[h, v],
      pageSheet: const VsdxPageSheet(lineJumpCode: 4),
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(RegExp(r'\sA\s').hasMatch(svg), isTrue);
  });

  test('SVG export omits jumps when LineJumpCode is None', () {
    final h = VsdxShapeFactory.line(id: 1, ax: 1, ay: 3, bx: 5, by: 3);
    final v = VsdxShapeFactory.line(id: 2, ax: 3, ay: 5, bx: 3, by: 1);
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 8,
      heightInches: 11,
      shapes: <VsdxShape>[h, v],
      pageSheet: const VsdxPageSheet(lineJumpCode: 0),
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(RegExp(r'\sA\s').hasMatch(svg), isFalse);
  });
}
