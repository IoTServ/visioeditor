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

import 'page.dart';
import 'shape.dart';

@immutable
class VsdxMaster {
  const VsdxMaster({
    required this.id,
    required this.name,
    required this.prototype,
    this.additionalPrototypes = const <VsdxShape>[],
    this.pageWidthInches = 0,
    this.pageHeightInches = 0,
    this.pageSheet = VsdxPageSheet.defaults,
  });

  /// Stable Visio Master id, referenced by `<Shape Master="ID">`.
  final int id;

  /// `NameU` / `Name`. Surface-facing — handy for stencil pickers.
  final String name;

  /// The "stamp" shape. Coordinates are stored relative to the Master's
  /// own local space (Visio convention) — the renderer ignores them on the
  /// Master itself and only forwards geometry/fill/line to instances.
  final VsdxShape prototype;

  /// Additional top-level shapes stored in the same master part.
  ///
  /// libvisio registers every top-level stencil shape by id while keeping the
  /// first one as the implicit prototype for `Master="N"`. `MasterShape="M"`
  /// may therefore resolve to a later top-level shape as well as to a child of
  /// the first prototype.
  final List<VsdxShape> additionalPrototypes;

  /// Master PageSheet canvas used by libvisio `parseStencils`.
  final double pageWidthInches;
  final double pageHeightInches;
  final VsdxPageSheet pageSheet;

  /// Find the master sub-shape with [shapeId] anywhere in the [prototype]
  /// tree. Page sub-shapes reference these via `MasterShape="N"` and inherit
  /// their geometry / text / style from them (Visio, like libvisio, resolves
  /// each instance sub-shape against the matching master sub-shape).
  VsdxShape? findShape(int shapeId) {
    final first = _find(prototype, shapeId);
    if (first != null) return first;
    for (final shape in additionalPrototypes) {
      final hit = _find(shape, shapeId);
      if (hit != null) return hit;
    }
    return null;
  }

  static VsdxShape? _find(VsdxShape s, int shapeId) {
    if (s.id == shapeId) return s;
    for (final c in s.children) {
      final hit = _find(c, shapeId);
      if (hit != null) return hit;
    }
    return null;
  }

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
