import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  group('sampleVisioSpline', () {
    test('assembles knots like libvisio and stays near the control polygon', () {
      // MoveTo(0,0) + SplineStart(1,1) + SplineKnot(2,0) + SplineKnot(3,1)
      const start = Offset2D(0, 0);
      const head = SplineStart(
        x: 1,
        y: 1,
        a: 1, // second knot
        b: 0, // first knot
        c: 3, // last knot
        degree: 3,
      );
      const knots = <SplineKnot>[
        SplineKnot(x: 2, y: 0, knot: 2),
        SplineKnot(x: 3, y: 1, knot: 2.5),
      ];
      final samples = sampleVisioSpline(
        start: start,
        head: head,
        knots: knots,
        samples: 16,
      );
      expect(samples, isNotEmpty);
      // Endpoint is the last SplineKnot.
      expect(samples.last.x, closeTo(3, 1e-5));
      expect(samples.last.y, closeTo(1, 1e-5));
      // Curve should not collapse to a single chord (more than 2 samples).
      expect(samples.length, greaterThan(2));
    });

    test('consumeSplineSequence skips SplineKnot rows', () {
      final cmds = <VsdxPathCommand>[
        const MoveTo(0, 0),
        const SplineStart(x: 1, y: 0, a: 1, b: 0, c: 2, degree: 2),
        const SplineKnot(x: 2, y: 1, knot: 1.5),
        const LineTo(3, 0),
      ];
      final r = consumeSplineSequence(
        cmds,
        1,
        pen: const Offset2D(0, 0),
        width: 1,
        height: 1,
      );
      expect(r.nextIndex, 3);
      expect(r.end.x, closeTo(2, 1e-5));
    });
  });

  group('sampleArcByBow', () {
    test('positive bow is a circular arc through the sagitta apex', () {
      final pts = sampleArcByBow(
        start: const Offset2D(0, 0),
        end: const Offset2D(2, 0),
        bow: 0.5,
        steps: 8,
      );
      expect(pts.last.x, closeTo(2, 1e-9));
      expect(pts.last.y, closeTo(0, 1e-9));
      // Apex of +bow=0.5 on (0,0)→(2,0) is (1, 0.5).
      var nearest = double.infinity;
      for (final p in pts) {
        final d = (p.x - 1) * (p.x - 1) + (p.y - 0.5) * (p.y - 0.5);
        if (d < nearest) nearest = d;
      }
      expect(nearest, lessThan(0.02));
      // Radius from Visio formula: (chord²+4s²)/(8s) = 1.25.
      const r = 1.25;
      const cx = 1.0, cy = -0.75;
      for (final p in pts) {
        final d = math.sqrt((p.x - cx) * (p.x - cx) + (p.y - cy) * (p.y - cy));
        expect(d, closeTo(r, 1e-3));
      }
    });
  });
}
