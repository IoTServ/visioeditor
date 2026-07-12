import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/ruler.dart';

void main() {
  group('niceRulerStepInches', () {
    test('picks a 1in step at 100% zoom (96 px/in)', () {
      expect(niceRulerStepInches(96), 1.0);
    });
    test('picks a finer step when zoomed in', () {
      expect(niceRulerStepInches(400), 0.25);
    });
    test('picks a coarser step when zoomed out', () {
      expect(niceRulerStepInches(20), 5.0);
    });
    test('degenerate scale falls back to 1in', () {
      expect(niceRulerStepInches(0), 1.0);
    });
  });

  group('rulerTicksInches', () {
    test('aligns ticks to the origin within the range', () {
      expect(rulerTicksInches(0.3, 2.7, 1), <double>[0, 1, 2]);
    });
    test('handles negative starts and fractional steps', () {
      final ticks = rulerTicksInches(-0.4, 1.2, 0.5);
      expect(ticks.first, closeTo(-0.5, 1e-9));
      expect(ticks.last, closeTo(1.0, 1e-9));
      expect(ticks.length, 4);
    });
    test('is empty for a non-positive step or inverted range', () {
      expect(rulerTicksInches(0, 5, 0), isEmpty);
      expect(rulerTicksInches(5, 0, 1), isEmpty);
    });
  });
}
