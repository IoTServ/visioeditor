import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  group('SwimlaneOps.assemblePool', () {
    test('builds a horizontal pool with evenly stacked lanes', () {
      final pool = SwimlaneOps.assemblePool(
        poolId: 10,
        pinX: 4,
        pinY: 4,
        width: 4,
        height: 3,
        laneCount: 3,
        horizontal: true,
      );
      expect(SwimlaneOps.isPool(pool), isTrue);
      expect(pool.shapeKind, VsdxShapeKind.container);
      final lanes = SwimlaneOps.lanesOf(pool);
      expect(lanes, hasLength(3));
      expect(lanes.map((l) => l.id).toList(), <int>[11, 12, 13]);
      for (final lane in lanes) {
        expect(SwimlaneOps.isLane(lane), isTrue);
        expect(SwimlaneOps.isHorizontal(lane), isTrue);
        expect(lane.width, closeTo(4, 1e-9));
        expect(lane.height, closeTo(1, 1e-9));
      }
      // Bottom → top in Y-up local space.
      expect(lanes[0].pinY, closeTo(0.5, 1e-9));
      expect(lanes[1].pinY, closeTo(1.5, 1e-9));
      expect(lanes[2].pinY, closeTo(2.5, 1e-9));
    });

    test('builds a vertical pool with side-by-side lanes', () {
      final pool = SwimlaneOps.assemblePool(
        poolId: 1,
        pinX: 2,
        pinY: 2,
        width: 3,
        height: 4,
        laneCount: 2,
        horizontal: false,
      );
      final lanes = SwimlaneOps.lanesOf(pool);
      expect(lanes, hasLength(2));
      expect(SwimlaneOps.isHorizontal(lanes.first), isFalse);
      expect(lanes[0].width, closeTo(1.5, 1e-9));
      expect(lanes[0].height, closeTo(4, 1e-9));
      expect(lanes[0].pinX, closeTo(0.75, 1e-9));
      expect(lanes[1].pinX, closeTo(2.25, 1e-9));
    });
  });

  group('addLane / removeLane', () {
    test('addLane reflows to equal heights', () {
      var pool = SwimlaneOps.assemblePool(
        poolId: 1,
        pinX: 0,
        pinY: 0,
        width: 4,
        height: 2,
        laneCount: 2,
      );
      final extra = SwimlaneOps.lane(
        id: 99,
        pinX: 0,
        pinY: 0,
        width: 1,
        height: 1,
        horizontal: true,
        text: 'Lane 3',
      );
      pool = SwimlaneOps.addLane(pool, extra);
      final lanes = SwimlaneOps.lanesOf(pool);
      expect(lanes, hasLength(3));
      for (final l in lanes) {
        expect(l.height, closeTo(2 / 3, 1e-9));
      }
      expect(lanes.any((l) => l.id == 99), isTrue);
    });

    test('removeLane keeps at least one lane', () {
      var pool = SwimlaneOps.assemblePool(
        poolId: 1,
        pinX: 0,
        pinY: 0,
        width: 4,
        height: 2,
        laneCount: 2,
      );
      final first = SwimlaneOps.lanesOf(pool).first.id;
      pool = SwimlaneOps.removeLane(pool, first);
      expect(SwimlaneOps.lanesOf(pool), hasLength(1));
      final only = SwimlaneOps.lanesOf(pool).single;
      // Refuses to remove the last lane.
      final same = SwimlaneOps.removeLane(pool, only.id);
      expect(identical(same, pool) || SwimlaneOps.lanesOf(same).length == 1,
          isTrue);
      expect(SwimlaneOps.lanesOf(same), hasLength(1));
    });
  });

  test('drop a rectangle into a lane via reparentShape', () {
    final pool = SwimlaneOps.assemblePool(
      poolId: 1,
      pinX: 4,
      pinY: 4,
      width: 4,
      height: 3,
      laneCount: 2,
    );
    final lane = SwimlaneOps.lanesOf(pool).last;
    final box = VsdxShapeFactory.rectangle(
      id: 50,
      pinX: 4,
      pinY: 4.5,
      width: 0.8,
      height: 0.5,
    );
    var page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 10,
      heightInches: 10,
      shapes: <VsdxShape>[pool, box],
    );
    final before = page.shapePinPage(50);
    page = page.reparentShape(50, lane.id);
    expect(page.findParentId(50), lane.id);
    final nested = page.findShapeById(50)!;
    expect(nested.id, 50);
    final after = page.shapePinPage(50);
    expect(after.x, closeTo(before.x, 1e-6));
    expect(after.y, closeTo(before.y, 1e-6));
  });

  test('layoutLanesPreservingSizes scales pool-level non-lane children', () {
    var pool = SwimlaneOps.assemblePool(
      poolId: 1,
      pinX: 4,
      pinY: 4,
      width: 4,
      height: 2,
      laneCount: 2,
      horizontal: true,
    );
    final badge = VsdxShapeFactory.rectangle(
      id: 99,
      pinX: 2,
      pinY: 1,
      width: 0.5,
      height: 0.4,
    );
    pool = pool.copyWith(children: <VsdxShape>[...pool.children, badge]);
    // Grow the bottom lane so the pool height doubles.
    final lanes = SwimlaneOps.lanesOf(pool);
    pool = pool.copyWith(
      children: <VsdxShape>[
        lanes.first.copyWith(height: 3),
        lanes.last,
        badge,
      ],
    );
    final laid = SwimlaneOps.layoutLanesPreservingSizes(pool);
    expect(laid.height, closeTo(4.0, 1e-6)); // 3 + 1
    final scaled = SwimlaneOps.nonLaneChildren(laid).single;
    expect(scaled.pinY, closeTo(1 * (4 / 2), 0.15));
    expect(scaled.height, closeTo(0.4 * (4 / 2), 0.15));
  });

  test('lane layout preserves NoFill/NoLine on regenerated geometry', () {
    var pool = SwimlaneOps.assemblePool(
      poolId: 1,
      pinX: 3,
      pinY: 3,
      width: 4,
      height: 2,
      laneCount: 2,
      horizontal: true,
    );
    final lanes = SwimlaneOps.lanesOf(pool);
    final hollow = lanes.first.copyWith(
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
      geometries: syncGeometryNoLine(
        syncGeometryNoFill(lanes.first.geometries, hollow: true),
        hollow: true,
      ),
    );
    pool = pool.copyWith(
      children: <VsdxShape>[
        hollow.copyWith(height: 2.5),
        lanes.last,
      ],
    );
    final laid = SwimlaneOps.layoutLanesPreservingSizes(pool);
    final lane = SwimlaneOps.lanesOf(laid).first;
    expect(lane.geometries.first.noFill, isTrue);
    expect(lane.geometries.first.noLine, isTrue);
  });
}
