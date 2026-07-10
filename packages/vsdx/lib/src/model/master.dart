/// A reusable Visio Master (a.k.a. "stencil shape" / "stamp").
///
/// Page-level `<Shape Master="N">` instances *inherit* every cell they
/// don't carry themselves from this prototype. In particular, the bulk of
/// real-world `.vsdx` files leave Geometry + Fill + Line on the Master and
/// only put XForm (PinX/PinY/Width/Height/Angle) on the instance.
///
/// The prototype is itself a [VsdxShape], so the existing render path can
/// be reused to draw it standalone (e.g. for a future "stencil preview"
/// panel in M5).
library;

import 'package:meta/meta.dart';

import 'shape.dart';

@immutable
class VsdxMaster {
  const VsdxMaster({
    required this.id,
    required this.name,
    required this.prototype,
  });

  /// Stable Visio Master id, referenced by `<Shape Master="ID">`.
  final int id;

  /// `NameU` / `Name`. Surface-facing — handy for stencil pickers.
  final String name;

  /// The "stamp" shape. Coordinates are stored relative to the Master's
  /// own local space (Visio convention) — the renderer ignores them on the
  /// Master itself and only forwards geometry/fill/line to instances.
  final VsdxShape prototype;

  @override
  String toString() => 'VsdxMaster(#$id $name)';
}

/// Lookup table for `Master="N"` references.
///
/// Immutable — pages share a single registry built once at document load.
@immutable
class MasterRegistry {
  const MasterRegistry(this._byId);

  final Map<int, VsdxMaster> _byId;

  static const MasterRegistry empty = MasterRegistry(<int, VsdxMaster>{});

  VsdxMaster? find(int id) => _byId[id];

  Iterable<VsdxMaster> get all => _byId.values;

  int get length => _byId.length;
}
