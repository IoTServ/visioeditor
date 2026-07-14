import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/render/line_jumps.dart';

void main() {
  test('segmentIntersection finds a proper interior crossing', () {
    final p = segmentIntersection(
      const Offset(0, 0),
      const Offset(2, 2),
      const Offset(0, 2),
      const Offset(2, 0),
    );
    expect(p, isNotNull);
    expect(p!.dx, closeTo(1, 1e-9));
    expect(p.dy, closeTo(1, 1e-9));
  });

  test('segmentIntersection rejects parallel and endpoint-only touches', () {
    expect(
      segmentIntersection(const Offset(0, 0), const Offset(2, 0),
          const Offset(0, 1), const Offset(2, 1)),
      isNull, // parallel
    );
    expect(
      segmentIntersection(const Offset(0, 0), const Offset(2, 0),
          const Offset(2, 0), const Offset(2, 2)),
      isNull, // meet only at an endpoint
    );
  });

  test('polylineCrossings counts only proper crossings', () {
    final route = <Offset>[const Offset(0, 1), const Offset(4, 1)];
    final unders = <List<Offset>>[
      <Offset>[const Offset(1, 0), const Offset(1, 2)], // crosses at (1,1)
      <Offset>[const Offset(3, 0), const Offset(3, 2)], // crosses at (3,1)
      <Offset>[const Offset(0, 3), const Offset(4, 3)], // parallel, no cross
    ];
    expect(polylineCrossings(route, unders).length, 2);
  });

  test('polylineWithJumps inserts an arc that lengthens the contour', () {
    final route = <Offset>[const Offset(0, 1), const Offset(4, 1)];
    final unders = <List<Offset>>[
      <Offset>[const Offset(2, 0), const Offset(2, 2)],
    ];
    double len(Path p) =>
        p.computeMetrics().fold<double>(0, (s, m) => s + m.length);
    final plain = polylineWithJumps(route, const <List<Offset>>[], 0.2);
    final jumped = polylineWithJumps(route, unders, 0.2);
    expect(len(plain), closeTo(4.0, 1e-6));
    expect(len(jumped), greaterThan(len(plain)));
  });
}
