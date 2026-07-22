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

    test('snaps to a permanent vertical page guide', () {
      final r = computeSnap(
        moving: const SnapBox(1.97, 0, 2.97, 1),
        others: const <SnapBox>[],
        threshold: 0.1,
        pageGuides: const <PageGuide>[
          PageGuide(vertical: true, pos: 2.0),
        ],
      );
      expect(r.dx, closeTo(0.03, 1e-9)); // left edge → x=2
      expect(r.guides.single.vertical, isTrue);
      expect(r.guides.single.pos, closeTo(2.0, 1e-9));
    });

    test('page guide can beat a farther neighbour alignment', () {
      // Neighbour left edge at 3.0 (far); page guide at 2.0 (near left=1.98).
      // Neighbour Y is offset so it doesn't also emit a horizontal guide.
      final r = computeSnap(
        moving: const SnapBox(1.98, 0, 2.5, 1),
        others: const <SnapBox>[SnapBox(3.0, 5, 4.0, 6)],
        threshold: 0.1,
        pageGuides: const <PageGuide>[
          PageGuide(vertical: true, pos: 2.0),
        ],
      );
      expect(r.dx, closeTo(0.02, 1e-9));
      final v = r.guides.singleWhere((g) => g.vertical);
      expect(v.pos, closeTo(2.0, 1e-9));
    });

    test('snaps moving edge to a connection-point magnet', () {
      // Moving right edge at 1.97; magnet at x=2.0 → snap dx=0.03.
      final r = computeSnap(
        moving: const SnapBox(0.97, 0, 1.97, 1),
        others: const <SnapBox>[],
        threshold: 0.1,
        magnets: const <SnapMagnet>[SnapMagnet(2.0, 3.5)],
      );
      expect(r.dx, closeTo(0.03, 1e-9));
      expect(r.guides.singleWhere((g) => g.vertical).pos, closeTo(2.0, 1e-9));
    });

    test('magnet can beat a farther neighbour edge', () {
      final r = computeSnap(
        moving: const SnapBox(0, 0, 1.98, 1),
        others: const <SnapBox>[SnapBox(3.0, 0, 4.0, 1)],
        threshold: 0.1,
        magnets: const <SnapMagnet>[SnapMagnet(2.0, 0.5)],
      );
      expect(r.dx, closeTo(0.02, 1e-9)); // right edge → magnet x=2
    });

    test('already-aligned axis still reports snappedX so grid must not override',
        () {
      // Left edges already coincide (dx=0) but still within threshold — the
      // guide claim must stick so callers do not grid-yank the box off.
      final r = computeSnap(
        moving: const SnapBox(2.0, 0, 2.7, 1),
        others: const <SnapBox>[SnapBox(2.0, 5, 3.0, 6)],
        threshold: 0.1,
      );
      expect(r.dx, 0);
      expect(r.snappedX, isTrue);
      expect(r.snappedY, isFalse);
      expect(r.guides.singleWhere((g) => g.vertical).pos, closeTo(2.0, 1e-9));
    });

    test('already-aligned horizontal centre reports snappedY', () {
      final r = computeSnap(
        moving: const SnapBox(0, 1.0, 1, 3.0), // cy = 2
        others: const <SnapBox>[SnapBox(4, 1.0, 5, 3.0)], // cy = 2
        threshold: 0.1,
      );
      expect(r.dy, 0);
      expect(r.snappedY, isTrue);
      expect(r.snappedX, isFalse);
    });
  });
}
