import 'dart:math' as math;

import 'package:vsdx/vsdx.dart';

import '../render/shape_bounds.dart';

/// Builds a cropped, standalone page containing only [selectedShapeIds].
///
/// Selection roots are materialised in page coordinates, so exporting a child
/// of a rotated/nested group keeps its on-canvas appearance. Co-selected
/// descendants are emitted only once, paint order is preserved, and Connect
/// rows are retained when both endpoints are inside the exported selection.
/// A small [marginInches] keeps strokes, arrowheads, shadows, and labels away
/// from the output edge (draw.io's "Selection only" export behaviour).
VsdxPage? buildSelectionExportPage(
  VsdxPage page,
  Iterable<int> selectedShapeIds, {
  double marginInches = 0.125,
}) {
  final selected = <int>{
    for (final id in selectedShapeIds)
      if (page.findShapeById(id) != null) id,
  };
  if (selected.isEmpty) return null;

  bool hasSelectedAncestor(int id) {
    var parentId = page.findParentId(id);
    while (parentId != null) {
      if (selected.contains(parentId)) return true;
      parentId = page.findParentId(parentId);
    }
    return false;
  }

  final rootIds = <int>[];
  void collectRoots(VsdxShape shape) {
    if (selected.contains(shape.id) && !hasSelectedAncestor(shape.id)) {
      rootIds.add(shape.id);
      return;
    }
    for (final child in shape.children) {
      collectRoots(child);
    }
  }

  for (final shape in page.shapes) {
    collectRoots(shape);
  }
  if (rootIds.isEmpty) return null;

  final includedIds = <int>{};
  final boundsIds = <int>[];
  void includeSubtree(VsdxShape shape, {required bool includeBounds}) {
    includedIds.add(shape.id);
    if (includeBounds) boundsIds.add(shape.id);
    for (final child in shape.children) {
      includeSubtree(child, includeBounds: includeBounds && !shape.collapsed);
    }
  }

  for (final id in rootIds) {
    includeSubtree(page.findShapeById(id)!, includeBounds: true);
  }

  var left = double.infinity;
  var bottom = double.infinity;
  var right = -double.infinity;
  var top = -double.infinity;
  final visualBounds = buildShapeBounds(page);
  for (final id in boundsIds) {
    final visual = visualBounds[id];
    if (visual != null) {
      left = math.min(left, visual.left);
      bottom = math.min(bottom, visual.top);
      right = math.max(right, visual.right);
      top = math.max(top, visual.bottom);
      continue;
    }
    final geometry = page.shapePageAabb(id);
    if (geometry == null) continue;
    left = math.min(left, geometry.left);
    bottom = math.min(bottom, geometry.bottom);
    right = math.max(right, geometry.right);
    top = math.max(top, geometry.top);
  }
  if (!left.isFinite || !bottom.isFinite || !right.isFinite || !top.isFinite) {
    return null;
  }

  final margin = math.max(0.0, marginInches);
  final dx = margin - left;
  final dy = margin - bottom;
  final width = math.max(2 * margin, right - left + 2 * margin);
  final height = math.max(2 * margin, top - bottom + 2 * margin);
  final shapes = <VsdxShape>[
    for (final id in rootIds)
      VsdxPage.translateShape(
        page.shapeAsPageRoot(id),
        dx,
        dy,
        honourDontMoveChildren: false,
      ),
  ];
  final connects = <VsdxConnect>[
    for (final connect in page.connects)
      if (includedIds.contains(connect.fromSheetId) &&
          includedIds.contains(connect.toSheetId))
        connect,
  ];

  return page.copyWith(
    name: '${page.name} Selection',
    widthInches: width,
    heightInches: height,
    shapes: shapes,
    connects: connects,
    isBackgroundPage: false,
    backgroundPageId: null,
  );
}
