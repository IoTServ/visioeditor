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
    this.color,
  });

  /// Row IX as defined inside `<Section N="Layer">`. Stable within a page.
  final int id;

  /// Display name (`Name` cell).
  final String name;

  final bool visible;
  final bool print;
  final bool active;
  final bool locked;
  final VsdxColor? color;

  VsdxLayer copyWith({bool? visible, bool? print, bool? locked}) => VsdxLayer(
        id: id,
        name: name,
        visible: visible ?? this.visible,
        print: print ?? this.print,
        active: active,
        locked: locked ?? this.locked,
        color: color,
      );

  @override
  String toString() =>
      'VsdxLayer(#$id $name, visible=$visible print=$print)';
}
