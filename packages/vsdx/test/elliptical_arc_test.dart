import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  group('sampleEllipticalArc', () {
    test('zero eccentricity falls back to LineTo like libvisio', () {
      const end = Offset2D(2, 0);
      final samples = sampleEllipticalArc(
        start: const Offset2D(0, 0),
        end: end,
        control: const Offset2D(1, 1),
        angle: 0,
        eccentricity: 0,
      );

      expect(samples, const <Offset2D>[end]);
    });

    test('near-collinear points use libvisio LineTo epsilon', () {
      const end = Offset2D(2, 0);
      final samples = sampleEllipticalArc(
        start: const Offset2D(0, 0),
        end: end,
        control: const Offset2D(1, 1e-11),
        angle: 0,
        eccentricity: 1,
      );

      expect(samples, const <Offset2D>[end]);
    });

    test('quarter circle (ecc=1) passes near the control point', () {
      const start = Offset2D(1, 0);
      const end = Offset2D(0, 1);
      const control = Offset2D(math.sqrt1_2, math.sqrt1_2);
      final samples = sampleEllipticalArc(
        start: start,
        end: end,
        control: control,
        angle: 0,
        eccentricity: 1,
        steps: 24,
      );
      expect(samples.last.x, closeTo(0, 1e-9));
      expect(samples.last.y, closeTo(1, 1e-9));
      // Some sample should land near the 45° control.
      final near = samples.any(
        (p) =>
            (p.x - control.x).abs() < 0.05 && (p.y - control.y).abs() < 0.05,
      );
      expect(near, isTrue);
    });

    test('flat ellipse (ecc≠1) bows differently than a circular arc', () {
      const start = Offset2D(2, 0);
      const end = Offset2D(0, 1);
      const control = Offset2D(1.2, 0.7);
      final round = sampleEllipticalArc(
        start: start,
        end: end,
        control: control,
        angle: 0,
        eccentricity: 1,
        steps: 20,
      );
      final flat = sampleEllipticalArc(
        start: start,
        end: end,
        control: control,
        angle: 0,
        eccentricity: 2,
        steps: 20,
      );
      // Mid samples diverge once eccentricity stretches the circle space.
      final midR = round[round.length ~/ 2];
      final midF = flat[flat.length ~/ 2];
      final dist = math.sqrt(
        math.pow(midR.x - midF.x, 2) + math.pow(midR.y - midF.y, 2),
      );
      expect(dist, greaterThan(0.05));
    });
  });
}
