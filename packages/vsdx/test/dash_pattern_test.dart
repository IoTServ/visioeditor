import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  test('draw.io custom dash patterns parse and format', () {
    expect(parseDrawioDashPattern('8 4, 2 4'), <double>[8, 4, 2, 4]);
    expect(parseDrawioDashPattern('8 0'), isNull);
    expect(parseDrawioDashPattern('bad'), isNull);
    expect(formatDrawioDashPattern(const <double>[8, 4.5, 2]), '8 4.5 2');
  });

  test('draw.io fixed dash is independent of line weight', () {
    const a = VsdxLine(
      weightInches: 0.01,
      pattern: 2,
      customDashPattern: <double>[6, 3],
      fixedDash: true,
    );
    const b = VsdxLine(
      weightInches: 0.08,
      pattern: 2,
      customDashPattern: <double>[6, 3],
      fixedDash: true,
    );
    expect(effectiveDashPatternForLine(a), effectiveDashPatternForLine(b));
  });

  test('dashPatternFor is null for solid / no-line', () {
    expect(dashPatternFor(0), isNull);
    expect(dashPatternFor(1), isNull);
  });

  test('dashPatternFor scales with line weight', () {
    expect(
      dashPatternFor(2, weightInches: 0.01),
      closeToList(const [0.10, 0.05]),
    );
    expect(
      dashPatternFor(2, weightInches: 0.04),
      closeToList(const [0.40, 0.20]),
    );
  });

  test('dashArrayAttr formats weight-scaled SVG values', () {
    expect(dashArrayAttr(2, weightInches: 0.01), '0.1 0.05');
    expect(dashArrayAttr(1), isEmpty);
  });
}

Matcher closeToList(List<double> expected, [double eps = 1e-9]) =>
    predicate<List<double>>((actual) {
      if (actual.length != expected.length) return false;
      for (var i = 0; i < actual.length; i++) {
        if ((actual[i] - expected[i]).abs() > eps) return false;
      }
      return true;
    }, 'list ≈ $expected');
