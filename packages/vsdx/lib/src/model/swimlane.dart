/// Draw.io-style multi-lane pool / swimlane helpers.
///
/// A **pool** (`User.vePool`) is a structural container whose direct
/// **lane** children (`User.veLane`) tile its interior. Horizontal pools
/// stack lanes bottom→top; vertical pools place them left→right.
///
/// Lane title strips: horizontal → left strip; vertical → top strip.
library;

import 'dart:math' as math;

import '../utils/color.dart';
import 'fill.dart';
import 'geometry.dart';
import 'line.dart';
import 'page.dart';
import 'shape.dart';
import 'shape_kind.dart';
import 'user_property.dart';

/// Pure helpers for assembling and editing multi-lane pools.
abstract final class SwimlaneOps {
  SwimlaneOps._();

  static const double minLaneSize = 0.25;

  static const String userPool = 'vePool';
  static const String userLane = 'veLane';

  /// `'1'` = horizontal (lanes stacked vertically, left title strip).
  /// `'0'` = vertical (lanes side-by-side, top title strip).
  static const String userLaneHorizontal = 'veLaneHorizontal';

  static const VsdxFill _laneFill = VsdxFill(foreground: VsdxColor.white);
  static const VsdxLine _laneLine = VsdxLine(color: VsdxColor.black);
  static const VsdxFill _poolFill = VsdxFill(
    pattern: 1,
    foreground: VsdxColor(0xFFF5F5F5),
  );

  static bool isPool(VsdxShape s) {
    for (final c in s.userCells) {
      if (c.name == userPool && c.value == '1') return true;
    }
    return false;
  }

  static bool isLane(VsdxShape s) {
    for (final c in s.userCells) {
      if (c.name == userLane && c.value == '1') return true;
    }
    // Legacy single bpmnPool stencil (swimlane, no user cells).
    return s.shapeKind == VsdxShapeKind.swimlane && !isPool(s);
  }

  /// Whether [s] uses a left title strip (horizontal swimlane). Defaults to
  /// `true` when the marker is absent.
  static bool isHorizontal(VsdxShape s) {
    for (final c in s.userCells) {
      if (c.name == userLaneHorizontal) return c.value != '0';
    }
    return true;
  }

  static List<VsdxUserCell> poolCells() => const <VsdxUserCell>[
        VsdxUserCell(name: userPool, value: '1'),
      ];

  static List<VsdxUserCell> laneCells({required bool horizontal}) =>
      <VsdxUserCell>[
        const VsdxUserCell(name: userLane, value: '1'),
        VsdxUserCell(
          name: userLaneHorizontal,
          value: horizontal ? '1' : '0',
        ),
      ];

  /// Geometry for a lane: left strip ([horizontal] true) or top strip.
  static List<VsdxGeometry> laneGeometry({
    required double width,
    required double height,
    required bool horizontal,
  }) {
    final w = width.abs();
    final h = height.abs();
    final outer = VsdxGeometry(commands: <VsdxPathCommand>[
      const MoveTo(0, 0),
      LineTo(w, 0),
      LineTo(w, h),
      LineTo(0, h),
      const LineTo(0, 0),
    ]);
    if (horizontal) {
      final strip = w * 0.12;
      return <VsdxGeometry>[
        outer,
        VsdxGeometry(
          noFill: true,
          commands: <VsdxPathCommand>[
            MoveTo(strip, 0),
            LineTo(strip, h),
          ],
        ),
      ];
    }
    final band = h * 0.12;
    return <VsdxGeometry>[
      outer,
      VsdxGeometry(
        noFill: true,
        commands: <VsdxPathCommand>[
          MoveTo(0, h - band),
          LineTo(w, h - band),
        ],
      ),
    ];
  }

  /// A single lane shape (may be placed alone or as a pool child).
  static VsdxShape lane({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    bool horizontal = true,
    String? name,
    String? text,
    VsdxFill fill = _laneFill,
    VsdxLine line = _laneLine,
  }) {
    final w = width.abs();
    final h = height.abs();
    final label = text ?? name ?? 'Lane';
    return VsdxShape(
      id: id,
      name: name ?? 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      shapeKind: VsdxShapeKind.swimlane,
      text: label,
      geometries: laneGeometry(
        width: w,
        height: h,
        horizontal: horizontal,
      ),
      fill: fill,
      line: line,
      userCells: laneCells(horizontal: horizontal),
    );
  }

  /// Direct lane children of [pool] (non-lane nested content is ignored).
  static List<VsdxShape> lanesOf(VsdxShape pool) => <VsdxShape>[
        for (final c in pool.children)
          if (isLane(c)) c,
      ];

  /// Non-lane children of [pool] (kept as-is during lane layout).
  static List<VsdxShape> nonLaneChildren(VsdxShape pool) => <VsdxShape>[
        for (final c in pool.children)
          if (!isLane(c)) c,
      ];

  /// Evenly tile [pool]'s lane children to fill its bounds.
  static VsdxShape layoutLanes(VsdxShape pool) {
    final lanes = lanesOf(pool);
    if (lanes.isEmpty) return pool;
    final horizontal = isHorizontal(lanes.first);
    final w = pool.width.abs();
    final h = pool.height.abs();
    final n = lanes.length;
    final laidOut = <VsdxShape>[];
    if (horizontal) {
      final laneH = h / n;
      for (var i = 0; i < n; i++) {
        final lane = lanes[i];
        laidOut.add(
          _laneWithFrame(
            lane,
            pinX: w / 2,
            pinY: i * laneH + laneH / 2,
            width: w,
            height: laneH,
            horizontal: true,
          ),
        );
      }
    } else {
      final laneW = w / n;
      for (var i = 0; i < n; i++) {
        final lane = lanes[i];
        laidOut.add(
          _laneWithFrame(
            lane,
            pinX: i * laneW + laneW / 2,
            pinY: h / 2,
            width: laneW,
            height: h,
            horizontal: false,
          ),
        );
      }
    }
    // Lanes first (fill), then pool-level content on top — same draw order as
    // drop-into-pool so shapes sitting on the pool are not covered by lanes.
    return pool.copyWith(
      children: <VsdxShape>[...laidOut, ...nonLaneChildren(pool)],
      userCells: _ensurePoolCell(pool.userCells),
      shapeKind: VsdxShapeKind.container,
    );
  }

  /// Reflow [pool] using each lane's current size (after a lane resize),
  /// growing/shrinking the pool so lanes tile without overlap. Keeps the
  /// pool's top (horizontal) or left (vertical) edge fixed.
  static VsdxShape layoutLanesPreservingSizes(VsdxShape pool) {
    final lanes = lanesOf(pool);
    if (lanes.isEmpty) return pool;
    final horizontal = isHorizontal(lanes.first);
    final laidOut = <VsdxShape>[];
    if (horizontal) {
      final w = pool.width.abs();
      final heights = <double>[
        for (final l in lanes) math.max(l.height.abs(), minLaneSize),
      ];
      final totalH = heights.fold<double>(0, (sum, h) => sum + h);
      var y = 0.0;
      for (var i = 0; i < lanes.length; i++) {
        final lane = lanes[i];
        final lh = heights[i];
        laidOut.add(
          _laneWithFrame(
            lane,
            pinX: w / 2,
            pinY: y + lh / 2,
            width: w,
            height: lh,
            horizontal: true,
          ),
        );
        y += lh;
      }
      final top = pool.pinY + pool.height / 2;
      return pool.copyWith(
        width: w,
        height: totalH <= 0 ? pool.height : totalH,
        pinY: top - (totalH <= 0 ? pool.height : totalH) / 2,
        children: <VsdxShape>[...laidOut, ...nonLaneChildren(pool)],
        userCells: _ensurePoolCell(pool.userCells),
        shapeKind: VsdxShapeKind.container,
      );
    }
    final h = pool.height.abs();
    final widths = <double>[
      for (final l in lanes) math.max(l.width.abs(), minLaneSize),
    ];
    final totalW = widths.fold<double>(0, (sum, w) => sum + w);
    var x = 0.0;
    for (var i = 0; i < lanes.length; i++) {
      final lane = lanes[i];
      final lw = widths[i];
      laidOut.add(
        _laneWithFrame(
          lane,
          pinX: x + lw / 2,
          pinY: h / 2,
          width: lw,
          height: h,
          horizontal: false,
        ),
      );
      x += lw;
    }
    final left = pool.pinX - pool.width / 2;
    return pool.copyWith(
      width: totalW <= 0 ? pool.width : totalW,
      height: h,
      pinX: left + (totalW <= 0 ? pool.width : totalW) / 2,
      children: <VsdxShape>[...laidOut, ...nonLaneChildren(pool)],
      userCells: _ensurePoolCell(pool.userCells),
      shapeKind: VsdxShapeKind.container,
    );
  }

  /// Append [newLane] under [pool] and reflow.
  static VsdxShape addLane(VsdxShape pool, VsdxShape newLane) {
    return layoutLanes(
      pool.copyWith(
        children: <VsdxShape>[...pool.children, newLane],
      ),
    );
  }

  /// Remove lane [laneId] from [pool] and reflow. Refuses to remove the last
  /// lane. Nested content of the removed lane is discarded (undo restores it).
  static VsdxShape removeLane(VsdxShape pool, int laneId) {
    final lanes = lanesOf(pool);
    if (lanes.length <= 1) return pool;
    if (!lanes.any((l) => l.id == laneId)) return pool;
    return layoutLanes(
      pool.copyWith(
        children: <VsdxShape>[
          for (final c in pool.children)
            if (c.id != laneId) c,
        ],
      ),
    );
  }

  /// Build a pool with [laneCount] evenly sized lanes.
  ///
  /// Pool id is [poolId]; lane ids are `[poolId+1, …, poolId+laneCount]`.
  static VsdxShape assemblePool({
    required int poolId,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    int laneCount = 2,
    bool horizontal = true,
    String? name,
  }) {
    final n = laneCount < 1 ? 1 : laneCount;
    final w = width.abs();
    final h = height.abs();
    final lanes = <VsdxShape>[
      for (var i = 0; i < n; i++)
        lane(
          id: poolId + 1 + i,
          pinX: w / 2,
          pinY: h / 2,
          width: w,
          height: h / n,
          horizontal: horizontal,
          name: 'Lane ${i + 1}',
          text: 'Lane ${i + 1}',
        ),
    ];
    final pool = VsdxShape(
      id: poolId,
      name: name ?? 'Pool',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      shapeKind: VsdxShapeKind.container,
      text: name ?? 'Pool',
      geometries: <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          const MoveTo(0, 0),
          LineTo(w, 0),
          LineTo(w, h),
          LineTo(0, h),
          const LineTo(0, 0),
        ]),
      ],
      fill: _poolFill,
      line: _laneLine,
      userCells: poolCells(),
      children: lanes,
    );
    return layoutLanes(pool);
  }

  /// Resize a lane frame and proportionally map nested content.
  static VsdxShape _laneWithFrame(
    VsdxShape lane, {
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    required bool horizontal,
  }) {
    final oldW = lane.width.abs() <= 1e-12 ? width : lane.width.abs();
    final oldH = lane.height.abs() <= 1e-12 ? height : lane.height.abs();
    final sx = width / oldW;
    final sy = height / oldH;
    final oldOx = lane.effectiveLocPinX;
    final oldOy = lane.effectiveLocPinY;
    final framed = lane.copyWith(
      pinX: pinX,
      pinY: pinY,
      width: width,
      height: height,
      geometries: laneGeometry(
        width: width,
        height: height,
        horizontal: horizontal,
      ),
      userCells: _mergeLaneCells(lane.userCells, horizontal: horizontal),
      shapeKind: VsdxShapeKind.swimlane,
    );
    if (lane.children.isEmpty ||
        ((sx - 1).abs() < 1e-12 && (sy - 1).abs() < 1e-12)) {
      return framed;
    }
    return framed.copyWith(
      children: <VsdxShape>[
        for (final c in lane.children)
          VsdxPage.scaleChildInFrame(
            c,
            sx,
            sy,
            oldOx,
            oldOy,
            framed.effectiveLocPinX,
            framed.effectiveLocPinY,
          ),
      ],
    );
  }

  static List<VsdxUserCell> _ensurePoolCell(List<VsdxUserCell> cells) {
    if (cells.any((c) => c.name == userPool)) return cells;
    return <VsdxUserCell>[...cells, ...poolCells()];
  }

  static List<VsdxUserCell> _mergeLaneCells(
    List<VsdxUserCell> existing, {
    required bool horizontal,
  }) {
    final others = <VsdxUserCell>[
      for (final c in existing)
        if (c.name != userLane && c.name != userLaneHorizontal) c,
    ];
    return <VsdxUserCell>[
      ...others,
      ...laneCells(horizontal: horizontal),
    ];
  }
}
