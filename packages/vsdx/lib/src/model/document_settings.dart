/// Top-level [VsdxDocument] settings.
///
/// We surface just the bits that affect rendering or export today —
/// `package:visiovsdxviewer` is a viewer, not an editor, so things like
/// `SaveFormat` or `EditModeOptions` aren't modelled. Future work can
/// extend this class without breaking callers.
library;

import 'package:meta/meta.dart';

import '../utils/color.dart';

@immutable
class VsdxDocumentSettings {
  const VsdxDocumentSettings({
    this.defaultPageBackgroundColor,
    this.glueType = 0,
    this.snapEnabled = true,
    this.gridDensityX = 4,
    this.gridDensityY = 4,
    this.defaultTextStyleId,
    this.defaultLineStyleId,
    this.defaultFillStyleId,
  });

  /// Whole-document fallback for the page background — populated from
  /// `<DocumentSettings><Cell N="PageColor"/></DocumentSettings>` (when
  /// present) or the more common StyleSheet machinery.
  final VsdxColor? defaultPageBackgroundColor;

  /// `GlueType` cell (0 = no glue, 1 = grid, 9 = guide). Captured for
  /// completeness; the viewer doesn't act on it yet.
  final int glueType;

  /// `SnapEnabled` cell — true by default in Visio.
  final bool snapEnabled;

  /// `GridDensityX` / `GridDensityY` cells. Matters for hypothetical
  /// editing support; currently informational.
  final int gridDensityX;
  final int gridDensityY;

  /// `DocumentSettings/@DefaultTextStyle` — StyleSheet id used when a shape
  /// has no `TextStyle` attribute. libvisio resolves Character.Size through
  /// this chain.
  final int? defaultTextStyleId;
  final int? defaultLineStyleId;
  final int? defaultFillStyleId;

  static const VsdxDocumentSettings defaults = VsdxDocumentSettings();
}
