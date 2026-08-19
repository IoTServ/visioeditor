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
    expect(dashPatternFor(24), isNull);
    expect(dashPatternFor(0xfe), isNull);
  });

  test('dashPatternFor matches every libvisio built-in pattern', () {
    const expected = <int, List<double>>{
      2: [6, 3],
      3: [1, 3],
      4: [6, 3, 1, 3],
      5: [6, 3, 1, 3, 1, 3],
      6: [6, 3, 6, 3, 1, 3],
      7: [14, 2, 6, 2],
      8: [14, 2, 6, 2, 6, 2],
      9: [3, 2],
      10: [1, 2],
      11: [3, 2, 1, 2],
      12: [3, 2, 1, 2, 1, 2],
      13: [3, 2, 3, 2, 1, 2],
      14: [7, 2, 3, 2],
      15: [7, 2, 3, 2, 3, 2],
      16: [11, 5],
      17: [1, 5],
      18: [11, 5, 1, 5],
      19: [11, 5, 1, 5, 1, 5],
      20: [11, 5, 11, 5, 1, 5],
      21: [27, 5, 11, 5],
      22: [27, 5, 11, 5, 11, 5],
      23: [2, 2],
    };
    for (final entry in expected.entries) {
      expect(
        dashPatternFor(entry.key, weightInches: 1),
        closeToList(entry.value),
        reason: 'LinePattern ${entry.key}',
      );
    }
    expect(
      dashPatternFor(2, weightInches: 0.04),
      closeToList(const [0.24, 0.12]),
    );
  });

  test('dashArrayAttr formats weight-scaled SVG values', () {
    expect(dashArrayAttr(2, weightInches: 0.01), '0.06 0.03');
    expect(dashArrayAttr(1), isEmpty);
  });

  test('linePatternForLibvisioWrite snaps custom arrays onto 2–23', () {
    expect(
      linePatternForLibvisioWrite(
        const VsdxLine(pattern: 2, customDashPattern: <double>[6, 3]),
      ),
      2,
    );
    expect(
      linePatternForLibvisioWrite(
        const VsdxLine(pattern: 254, customDashPattern: <double>[1, 3]),
      ),
      3,
    );
    expect(linePatternForLibvisioWrite(const VsdxLine(pattern: 23)), 23);
    expect(linePatternForLibvisioWrite(const VsdxLine(pattern: 254)), 1);
    expect(linePatternForLibvisioWrite(const VsdxLine(pattern: 0)), 0);
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
