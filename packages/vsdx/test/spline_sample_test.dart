import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  group('sampleVisioSpline', () {
    test('preserves libvisio-supported degree 8', () {
      const start = Offset2D(0, 0);
      const head = SplineStart(
        x: 1,
        y: 1,
        a: 0,
        b: 0,
        c: 1,
        degree: 8,
      );
      final knots = <SplineKnot>[
        for (var i = 0; i < 8; i++)
          SplineKnot(
            x: i + 2,
            y: i.isEven ? -1 : 1,
            knot: (i + 1) / 9,
          ),
      ];
      final knotVector = <double>[
        head.b,
        head.a,
        for (final knot in knots) knot.knot,
        head.c,
      ];
      final controlPoints = <Offset2D>[
        Offset2D(head.x, head.y),
        for (final knot in knots.take(knots.length - 1))
          Offset2D(knot.x, knot.y),
      ];
      final expected = sampleNurbs(
        start: start,
        end: Offset2D(knots.last.x, knots.last.y),
        controlPoints: controlPoints,
        weights: List<double>.filled(controlPoints.length + 2, 1),
        knots: knotVector,
        degree: 8,
        samples: 16,
      );

      expect(
        sampleVisioSpline(
          start: start,
          head: head,
          knots: knots,
          samples: 16,
        ),
        expected,
      );
    });

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
      expect(r.end.y, closeTo(1, 1e-5));
    });
  });

  group('sampleNurbs', () {
    test('caps degree at libvisio maximum 8', () {
      const start = Offset2D(0, 0);
      const end = Offset2D(9, 0);
      const controls = <Offset2D>[
        Offset2D(1, 1),
        Offset2D(2, -1),
        Offset2D(3, 1),
        Offset2D(4, -1),
        Offset2D(5, 1),
        Offset2D(6, -1),
        Offset2D(7, 1),
        Offset2D(8, -1),
      ];
      final degree8 = sampleNurbs(
        start: start,
        end: end,
        controlPoints: controls,
        degree: 8,
        samples: 16,
      );

      expect(
        sampleNurbs(
          start: start,
          end: end,
          controlPoints: controls,
          degree: 9,
          samples: 16,
        ),
        degree8,
      );
      expect(
        sampleNurbs(
          start: start,
          end: end,
          controlPoints: controls,
          degree: 0,
        ),
        const <Offset2D>[end],
      );
    });

    test('last sample snaps to the authored endpoint', () {
      final pts = sampleNurbs(
        start: const Offset2D(0, 0),
        end: const Offset2D(3, 0),
        controlPoints: const <Offset2D>[
          Offset2D(1, 1),
          Offset2D(2, 1),
        ],
        weights: const <double>[1, 1, 1, 1],
        knots: const <double>[0, 0, 0, 0, 1, 1, 1, 1],
        degree: 3,
        samples: 16,
      );
      expect(pts, isNotEmpty);
      expect(pts.last.x, closeTo(3, 1e-12));
      expect(pts.last.y, closeTo(0, 1e-12));
    });
  });

  group('sampleArcByBow', () {
    test('large-arc threshold matches libvisio bow > radius', () {
      expect(visioArcByBowIsLarge(2, 0.6), isFalse);
      expect(visioArcByBowIsLarge(2, 1), isFalse);
      expect(visioArcByBowIsLarge(2, 1.01), isTrue);
      expect(visioArcByBowIsLarge(2, -1.01), isTrue);
    });

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
