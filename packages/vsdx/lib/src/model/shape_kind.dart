/// High-level Visio shape classification for UI + tooling.
///
/// Visio itself tracks dozens of shape-type bits; we collapse them into a
/// small enum that is good enough for outline icons, search filters, and
/// lightweight container rendering hints.
library;

/// Semantic kind of a [VsdxShape].
enum VsdxShapeKind {
  /// Regular 2-D shape (rectangle, ellipse, path, text box, …).
  normal,

  /// Group container (`Type="Group"` or nested `<Shapes>`).
  group,

  /// Structured container (list, container stencil, BPMN pool, …).
  container,

  /// Swimlane band or lane header from cross-functional flowcharts.
  swimlane,

  /// Callout / annotation bubble.
  callout,

  /// 1-D connector / line shape.
  connector,

  /// Picture / foreign-data raster shape.
  picture,
}

extension VsdxShapeKindX on VsdxShapeKind {
  bool get isStructural =>
      this == VsdxShapeKind.group ||
      this == VsdxShapeKind.container ||
      this == VsdxShapeKind.swimlane;

  bool get isAnnotative => this == VsdxShapeKind.callout;
}
