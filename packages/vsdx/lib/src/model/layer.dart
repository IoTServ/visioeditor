/// Visio Layer system (`<Section N="Layer">` on the PageSheet).
///
/// Each layer row carries display flags (`Visible`, `Print`, `Active`,
/// `Lock`) plus a colour and a human-readable name. Shapes reference
/// layers via the `LayerMember` cell — a semicolon-separated list of
/// row indices ("0;3" ⇒ this shape sits on layers 0 and 3).
library;

import 'package:meta/meta.dart';

import '../utils/color.dart';

@immutable
class VsdxLayer {
  const VsdxLayer({
    required this.id,
    required this.name,
    this.visible = true,
    this.print = true,
    this.active = false,
    this.locked = false,
    this.snap = true,
    this.glue = true,
    this.color,
    this.colorTrans = 0,
    this.nameUniv,
    this.status = 0,
  });

  /// Row IX as defined inside `<Section N="Layer">`. Stable within a page.
  final int id;

  /// Display name (`Name` cell).
  final String name;

  final bool visible;
  final bool print;
  final bool active;
  final bool locked;

  /// `Snap` / `Glue` — whether shapes on this layer participate in snap/glue.
  final bool snap;
  final bool glue;

  final VsdxColor? color;

  /// `ColorTrans` — 0..1 transparency for the layer colour tint.
  final double colorTrans;

  /// `NameUniv` — locale-independent layer name (often equals [name]).
  final String? nameUniv;

  /// `Status` cell (Visio layer status flags).
  final int status;

  VsdxLayer copyWith({
    String? name,
    bool? visible,
    bool? print,
    bool? active,
    bool? locked,
    bool? snap,
    bool? glue,
    VsdxColor? color,
    double? colorTrans,
    String? nameUniv,
    int? status,
    bool clearColor = false,
    bool clearNameUniv = false,
  }) =>
      VsdxLayer(
        id: id,
        name: name ?? this.name,
        visible: visible ?? this.visible,
        print: print ?? this.print,
        active: active ?? this.active,
        locked: locked ?? this.locked,
        snap: snap ?? this.snap,
        glue: glue ?? this.glue,
        color: clearColor ? null : (color ?? this.color),
        colorTrans: colorTrans ?? this.colorTrans,
        nameUniv: clearNameUniv ? null : (nameUniv ?? this.nameUniv),
        status: status ?? this.status,
      );

  @override
  bool operator ==(Object other) =>
      other is VsdxLayer &&
      other.id == id &&
      other.name == name &&
      other.visible == visible &&
      other.print == print &&
      other.active == active &&
      other.locked == locked &&
      other.snap == snap &&
      other.glue == glue &&
      other.color == color &&
      other.colorTrans == colorTrans &&
      other.nameUniv == nameUniv &&
      other.status == status;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        visible,
        print,
        active,
        locked,
        snap,
        glue,
        color,
        colorTrans,
        nameUniv,
        status,
      );

  @override
  String toString() =>
      'VsdxLayer(#$id $name, visible=$visible print=$print)';
}

/// First layer with a non-null [VsdxLayer.color] among [layerMemberIds]
/// (membership order). Used by Visio "Color by Layer" display mode.
VsdxLayer? layerColorSource(
  Iterable<VsdxLayer> layers,
  List<int> layerMemberIds,
) {
  if (layerMemberIds.isEmpty) return null;
  final byId = <int, VsdxLayer>{
    for (final layer in layers) layer.id: layer,
  };
  for (final id in layerMemberIds) {
    final layer = byId[id];
    if (layer?.color != null) return layer;
  }
  return null;
}

