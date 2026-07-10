/// One Visio "drawing page". Page size is stored in **inches** (see
/// `lib/utils/units.dart` for the normalisation policy).
library;

import 'package:meta/meta.dart';

import '../utils/color.dart';
import 'connect.dart';
import 'geometry.dart';
import 'layer.dart';
import 'shape.dart';

@immutable
class VsdxPage {
  const VsdxPage({
    required this.id,
    required this.name,
    required this.widthInches,
    required this.heightInches,
    required this.shapes,
    this.layers = const <VsdxLayer>[],
    this.connects = const <VsdxConnect>[],
    this.backgroundColor,
    this.isBackgroundPage = false,
    this.backgroundPageId,
  });

  /// Visio internal page id; unique within the document.
  final int id;

  /// User-facing name (e.g. "Page-1", "Floor 2").
  final String name;

  final double widthInches;
  final double heightInches;

  /// Top-level shapes. Groups are nested via `VsdxShape.children`.
  final List<VsdxShape> shapes;

  /// Page-scoped layers. Empty list ⇒ no layer section on this page (every
  /// shape is drawn unconditionally).
  final List<VsdxLayer> layers;

  /// Page-level `<Connect>` rows. Mostly used by the connector router.
  final List<VsdxConnect> connects;

  /// `PageColor` cell — `null` ⇒ inherit document default (white).
  final VsdxColor? backgroundColor;

  /// `Background="1"` attribute on the Page element.
  final bool isBackgroundPage;

  /// `BackPage="N"` attribute — id of the background page rendered
  /// underneath this one (`null` when no background).
  final int? backgroundPageId;

  /// O(1) by-connector lookup. Lazily built each access — cheap because
  /// the list is usually tiny.
  ConnectIndex get connectIndex =>
      connects.isEmpty ? ConnectIndex.empty : ConnectIndex(connects);

  /// Convenience: the set of layer ids whose `visible == true`. Used by the
  /// renderer when filtering shapes.
  Set<int> get visibleLayerIds => {
        for (final l in layers)
          if (l.visible) l.id,
      };

  /// Walk the shape tree (DFS) and return the shape with [id], or `null`.
  VsdxShape? findShapeById(int id) {
    for (final s in shapes) {
      final hit = _walk(s, id);
      if (hit != null) return hit;
    }
    return null;
  }

  static VsdxShape? _walk(VsdxShape s, int id) {
    if (s.id == id) return s;
    for (final c in s.children) {
      final hit = _walk(c, id);
      if (hit != null) return hit;
    }
    return null;
  }

  VsdxPage copyWith({
    int? id,
    String? name,
    double? widthInches,
    double? heightInches,
    List<VsdxShape>? shapes,
    List<VsdxLayer>? layers,
    List<VsdxConnect>? connects,
    VsdxColor? backgroundColor,
    bool? isBackgroundPage,
    int? backgroundPageId,
  }) {
    return VsdxPage(
      id: id ?? this.id,
      name: name ?? this.name,
      widthInches: widthInches ?? this.widthInches,
      heightInches: heightInches ?? this.heightInches,
      shapes: shapes ?? this.shapes,
      layers: layers ?? this.layers,
      connects: connects ?? this.connects,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      isBackgroundPage: isBackgroundPage ?? this.isBackgroundPage,
      backgroundPageId: backgroundPageId ?? this.backgroundPageId,
    );
  }

  /// Returns a copy of this page with the shape identified by [id] replaced by
  /// `update(oldShape)`. Recurses into groups. Returns `this` (identical) when
  /// no shape matches, so callers can cheaply detect no-ops.
  VsdxPage updateShapeById(int id, VsdxShape Function(VsdxShape) update) {
    final (newShapes, changed) = _updateInList(shapes, id, update);
    return changed ? copyWith(shapes: newShapes) : this;
  }

  static (List<VsdxShape>, bool) _updateInList(
    List<VsdxShape> list,
    int id,
    VsdxShape Function(VsdxShape) update,
  ) {
    var changed = false;
    final result = <VsdxShape>[];
    for (final s in list) {
      if (s.id == id) {
        result.add(update(s));
        changed = true;
      } else if (s.children.isNotEmpty) {
        final (newChildren, childChanged) = _updateInList(s.children, id, update);
        if (childChanged) {
          result.add(s.copyWith(children: newChildren));
          changed = true;
        } else {
          result.add(s);
        }
      } else {
        result.add(s);
      }
    }
    return (result, changed);
  }

  /// A new page with [shape] appended to the top-level shape list.
  VsdxPage addShape(VsdxShape shape) =>
      copyWith(shapes: <VsdxShape>[...shapes, shape]);

  /// A new page with the shape [id] removed (recursing into groups). Returns
  /// `this` (identical) when nothing matched.
  VsdxPage removeShapeById(int id) {
    final (newShapes, changed) = _removeInList(shapes, id);
    return changed ? copyWith(shapes: newShapes) : this;
  }

  static (List<VsdxShape>, bool) _removeInList(List<VsdxShape> list, int id) {
    var changed = false;
    final result = <VsdxShape>[];
    for (final s in list) {
      if (s.id == id) {
        changed = true;
        continue;
      }
      if (s.children.isNotEmpty) {
        final (nc, cc) = _removeInList(s.children, id);
        if (cc) {
          result.add(s.copyWith(children: nc));
          changed = true;
          continue;
        }
      }
      result.add(s);
    }
    return (result, changed);
  }

  /// Re-route every glued connector so its endpoints follow the current
  /// centres of the shapes they are connected to (via [connects]). Returns
  /// `this` unchanged when there are no connects.
  VsdxPage rerouteConnectors() {
    if (connects.isEmpty) return this;
    final index = connectIndex;
    final connectorIds = <int>{for (final c in connects) c.fromSheetId};
    var next = this;
    for (final cid in connectorIds) {
      final connector = next.findShapeById(cid);
      if (connector == null) continue;
      var ax = connector.beginX ?? connector.pinX;
      var ay = connector.beginY ?? connector.pinY;
      var bx = connector.endX ?? connector.pinX;
      var by = connector.endY ?? connector.pinY;
      for (final e in index.forConnector(cid)) {
        final target = next.findShapeById(e.toSheetId);
        if (target == null) continue;
        if (e.isBegin) {
          ax = target.pinX;
          ay = target.pinY;
        } else if (e.isEnd) {
          bx = target.pinX;
          by = target.pinY;
        }
      }
      next = next.updateShapeById(
        cid,
        (s) => s.reshapeAsPolyline(_elbowRoute(ax, ay, bx, by)),
      );
    }
    return next;
  }

  /// Orthogonal (elbow / Z) route between two page points. Falls back to a
  /// straight line when the points already share an axis.
  static List<Offset2D> _elbowRoute(
    double ax,
    double ay,
    double bx,
    double by,
  ) {
    if (ax == bx || ay == by) {
      return <Offset2D>[Offset2D(ax, ay), Offset2D(bx, by)];
    }
    if ((bx - ax).abs() >= (by - ay).abs()) {
      final mx = (ax + bx) / 2;
      return <Offset2D>[
        Offset2D(ax, ay),
        Offset2D(mx, ay),
        Offset2D(mx, by),
        Offset2D(bx, by),
      ];
    }
    final my = (ay + by) / 2;
    return <Offset2D>[
      Offset2D(ax, ay),
      Offset2D(ax, my),
      Offset2D(bx, my),
      Offset2D(bx, by),
    ];
  }

  /// The smallest shape id greater than every id currently used on the page
  /// (including nested group children) — used when creating new shapes.
  int nextFreeShapeId() {
    var maxId = 0;
    void walk(VsdxShape s) {
      if (s.id > maxId) maxId = s.id;
      for (final c in s.children) {
        walk(c);
      }
    }

    for (final s in shapes) {
      walk(s);
    }
    return maxId + 1;
  }

  @override
  String toString() =>
      'VsdxPage(id: $id, name: $name, ${widthInches}x$heightInches in, '
      '${shapes.length} shapes, ${layers.length} layers)';
}
