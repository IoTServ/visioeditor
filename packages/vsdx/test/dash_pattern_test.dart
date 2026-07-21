import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void main() {
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
