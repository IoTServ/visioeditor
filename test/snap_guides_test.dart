import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/snap_guides.dart';

void main() {
  group('computeSnap', () {
    test('returns nothing when there are no neighbours', () {
      final r = computeSnap(
        moving: const SnapBox(0, 0, 1, 1),
        others: const <SnapBox>[],
        threshold: 0.1,
      );
      expect(r.isEmpty, isTrue);
    });

    test('snaps left edges together and emits a vertical guide', () {
      // Only the left edges align within threshold (width chosen so the
      // centre/right don't coincidentally line up with the neighbour).
      final r = computeSnap(
        moving: const SnapBox(1.95, 0, 2.65, 1),
        others: const <SnapBox>[SnapBox(2, 5, 3, 6)],
        threshold: 0.1,
      );
      expect(r.dx, closeTo(0.05, 1e-9)); // shift right so left edges (x=2) meet
      expect(r.dy, 0);
      final v = r.guides.singleWhere((g) => g.vertical);
      expect(v.pos, closeTo(2.0, 1e-9));
      // Guide spans the union of the (snapped) moving box and the match.
      expect(v.start, closeTo(0.0, 1e-9));
      expect(v.end, closeTo(6.0, 1e-9));
    });

    test('snaps horizontal centres and emits a horizontal guide', () {
      // Different heights so only the centres (cy=2.0) align within threshold.
      final r = computeSnap(
        moving: const SnapBox(0, 1.52, 1, 2.52),
        others: const <SnapBox>[SnapBox(4, 1.0, 5, 3.0)],
        threshold: 0.1,
      );
      expect(r.dy, closeTo(-0.02, 1e-9));
      expect(r.dx, 0);
      final h = r.guides.singleWhere((g) => !g.vertical);
      expect(h.pos, closeTo(2.0, 1e-9));
    });

    test('ignores alignments beyond the threshold', () {
      final r = computeSnap(
        moving: const SnapBox(0, 0, 1, 1),
        others: const <SnapBox>[SnapBox(2, 2, 3, 3)],
        threshold: 0.1,
      );
      expect(r.isEmpty, isTrue);
    });

    test('prefers the closest candidate on each axis', () {
      // Two neighbours; moving right edge (x=1) is 0.03 from one left edge
      // (x=1.03) and 0.5 from another — the closer one wins.
      final r = computeSnap(
        moving: const SnapBox(0, 0, 1, 1),
        others: const <SnapBox>[
          SnapBox(1.03, 0, 2, 1),
          SnapBox(1.5, 0, 2.5, 1),
        ],
        threshold: 0.1,
      );
      expect(r.dx, closeTo(0.03, 1e-9));
    });
  });
}
