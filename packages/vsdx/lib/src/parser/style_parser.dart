/// Parses the fill / line cells of a shape into immutable [VsdxFill] /
/// [VsdxLine] value objects.
///
/// M3 scope is **only the literal `V=` values that Visio pre-computes**.
/// Master / StyleSheet inheritance and `THEMEVAL` resolution land in M3-06.
library;

import 'package:xml/xml.dart';

import '../model/effects.dart';
import '../model/fill.dart';
import '../model/line.dart';
import '../model/theme.dart';
import '../utils/color.dart';
import 'cell_helpers.dart' show findCell, readLengthInches;

class StyleParser {
  const StyleParser();

  /// Parse fill cells, falling back to [defaults] for any cell that's
  /// absent on the shape (this is the Master-inheritance hook).
  ///
  /// When a colour cell uses `THEMEVAL()` / `THEMEGUARD()`, we record the
  /// corresponding `QuickStyle*Color` index instead — the renderer resolves
  /// it against the document's [VsdxTheme].
  VsdxFill parseFill(XmlElement shape,
      {VsdxFill defaults = VsdxFill.defaultFill}) {
    final fgRes = _resolveColor(shape, 'FillForegnd', 'QuickStyleFillColor');
    final bgRes = _resolveColor(shape, 'FillBkgnd', 'QuickStyleFillColor');

    final fgT = _double(shape, 'FillForegndTrans') ??
        defaults.foregroundTransparency;
    final bgT = _double(shape, 'FillBkgndTrans') ??
        defaults.backgroundTransparency;
    final pat = _int(shape, 'FillPattern') ?? defaults.pattern;

    final gradient = _parseGradient(shape) ?? defaults.gradient;

    return VsdxFill(
      foreground: fgRes.color ?? defaults.foreground,
      background: bgRes.color ?? defaults.background,
      foregroundTransparency: fgT.clamp(0.0, 1.0),
      backgroundTransparency: bgT.clamp(0.0, 1.0),
      pattern: pat,
      themeForegroundIndex:
          fgRes.themeIndex ?? defaults.themeForegroundIndex,
      themeBackgroundIndex:
          bgRes.themeIndex ?? defaults.themeBackgroundIndex,
      gradient: gradient,
    );
  }

  /// Look at `FillGradientEnabled` + `<Section N="FillGradient">`. Returns
  /// `null` when there's no gradient defined.
  VsdxGradient? _parseGradient(XmlElement shape) {
    final enabled = _int(shape, 'FillGradientEnabled') ?? 0;
    if (enabled == 0) return null;
    final dir = _int(shape, 'FillGradientDir') ?? 0;
    final angle = _double(shape, 'FillGradientAngle') ?? 0;
    final stops = <VsdxGradientStop>[];
    for (final section in shape.childElements) {
      if (section.name.local != 'Section') continue;
      if (section.getAttribute('N') != 'FillGradient') continue;
      for (final row in section.childElements) {
        if (row.name.local != 'Row') continue;
        final pos = _doubleIn(row, 'GradientStopPosition') ?? 0;
        final res =
            _resolveRowColor(row, 'GradientStopColor', 'QuickStyleFillColor');
        final t = _doubleIn(row, 'GradientStopColorTrans') ?? 0;
        stops.add(VsdxGradientStop(
          position: pos.clamp(0.0, 1.0),
          color: res.color,
          themeColorIndex: res.themeIndex,
          transparency: t.clamp(0.0, 1.0),
        ));
      }
    }
    if (stops.isEmpty) return null;
    stops.sort((a, b) => a.position.compareTo(b.position));
    return VsdxGradient(
      stops: List.unmodifiable(stops),
      type: _gradientTypeFromDir(dir),
      angleRad: angle,
    );
  }

  VsdxGradientType _gradientTypeFromDir(int dir) => switch (dir) {
        // Visio's `FillGradientDir` codes are messy in the spec; map the
        // common buckets to our four categories. 0..30 = linear at
        // different angles, 31..34 = rectangular, 35..38 = radial,
        // 39..42 = path.
        >= 31 && < 35 => VsdxGradientType.rectangular,
        >= 35 && < 39 => VsdxGradientType.radial,
        >= 39 && < 43 => VsdxGradientType.path,
        _ => VsdxGradientType.linear,
      };

  /// Glow* cells → [VsdxGlow].
  ///
  /// When `GlowSize` is 0/missing the glow is disabled, but companion cells
  /// (`GlowColor` / theme / transparency) are still loaded so toggle-off →
  /// save → reopen → toggle-on can restore them (writer only zeros Size).
  VsdxGlow parseGlow(
    XmlElement shape, {
    VsdxGlow defaults = VsdxGlow.disabled,
  }) {
    final sizeCell = readLengthInches(shape, 'GlowSize');
    final size = sizeCell ?? (defaults.enabled ? defaults.sizeInches : null);
    final col = _resolveColor(shape, 'GlowColor', 'QuickStyleEffectColor');
    final transparency =
        (_double(shape, 'GlowColorTrans') ?? defaults.transparency)
            .clamp(0.0, 1.0);
    final enabled = size != null && size > 0;
    if (!enabled) {
      final hasCompanion = col.color != null ||
          col.themeIndex != null ||
          _double(shape, 'GlowColorTrans') != null;
      if (!hasCompanion && !defaults.enabled) return VsdxGlow.disabled;
      return VsdxGlow(
        enabled: false,
        color: col.color ?? defaults.color,
        themeColorIndex: col.themeIndex ?? defaults.themeColorIndex,
        sizeInches: 0,
        transparency: transparency,
      );
    }
    return VsdxGlow(
      enabled: true,
      color: col.color ?? defaults.color,
      themeColorIndex: col.themeIndex ?? defaults.themeColorIndex,
      sizeInches: size,
      transparency: transparency,
    );
  }

  /// Reflection* cells → [VsdxReflection].
  ///
  /// Size ≤ 0 disables the effect, but Dist/Blur/Transparency companions are
  /// retained for re-enable after a save round-trip.
  VsdxReflection parseReflection(
    XmlElement shape, {
    VsdxReflection defaults = VsdxReflection.disabled,
  }) {
    final sizeCell = readLengthInches(shape, 'ReflectionSize');
    final size = sizeCell ?? (defaults.enabled ? defaults.sizeInches : null);
    final dist = readLengthInches(shape, 'ReflectionDist');
    final blur = readLengthInches(shape, 'ReflectionBlur');
    final transparency =
        (_double(shape, 'ReflectionTransparency') ?? defaults.transparency)
            .clamp(0.0, 1.0);
    final enabled = size != null && size > 0;
    if (!enabled) {
      final hasCompanion = dist != null ||
          blur != null ||
          _double(shape, 'ReflectionTransparency') != null;
      if (!hasCompanion && !defaults.enabled) return VsdxReflection.disabled;
      return VsdxReflection(
        enabled: false,
        sizeInches: 0,
        distanceInches: dist ?? defaults.distanceInches,
        blurInches: blur ?? defaults.blurInches,
        transparency: transparency,
      );
    }
    return VsdxReflection(
      enabled: true,
      sizeInches: size,
      distanceInches: dist ?? defaults.distanceInches,
      transparency: transparency,
      blurInches: blur ?? defaults.blurInches,
    );
  }

  /// Shadow* cells → [VsdxShadow].
  ///
  /// Pattern 0 disables the shadow, but colour / offset / blur companions are
  /// retained for re-enable after a save round-trip.
  VsdxShadow parseShadow(
    XmlElement shape, {
    VsdxShadow defaults = VsdxShadow.disabled,
  }) {
    final pat = _int(shape, 'ShadowPattern') ?? _int(shape, 'ShdwPattern');
    if (pat == null && !defaults.enabled) return defaults;
    final enabled = (pat ?? (defaults.enabled ? 1 : 0)) != 0;
    final col = _resolveColor(shape, 'ShadowForegnd', 'QuickStyleShadowColor');
    final ox = readLengthInches(shape, 'ShadowOffsetX');
    final oy = readLengthInches(shape, 'ShadowOffsetY');
    final blur = readLengthInches(shape, 'ShadowBlur');
    final transparency =
        (_double(shape, 'ShadowForegndTrans') ?? defaults.transparency)
            .clamp(0.0, 1.0);
    if (!enabled) {
      final hasCompanion = col.color != null ||
          col.themeIndex != null ||
          ox != null ||
          oy != null ||
          blur != null ||
          _double(shape, 'ShadowForegndTrans') != null;
      if (!hasCompanion) return VsdxShadow.disabled;
      return VsdxShadow(
        enabled: false,
        color: col.color ?? defaults.color,
        themeColorIndex: col.themeIndex ?? defaults.themeColorIndex,
        offsetXInches: ox ?? defaults.offsetXInches,
        offsetYInches: oy ?? defaults.offsetYInches,
        blurInches: blur ?? defaults.blurInches,
        transparency: transparency,
      );
    }

    return VsdxShadow(
      enabled: true,
      color: col.color ?? defaults.color,
      themeColorIndex: col.themeIndex ?? defaults.themeColorIndex,
      offsetXInches: ox ?? defaults.offsetXInches,
      offsetYInches: oy ?? defaults.offsetYInches,
      blurInches: blur ?? defaults.blurInches,
      transparency: transparency,
    );
  }

  VsdxLine parseLine(XmlElement shape,
      {VsdxLine defaults = VsdxLine.defaultLine}) {
    final colorRes = _resolveColor(shape, 'LineColor', 'QuickStyleLineColor');
    final weight =
        readLengthInches(shape, 'LineWeight') ?? defaults.weightInches;
    final pat = _int(shape, 'LinePattern') ?? defaults.pattern;
    final capInt = _int(shape, 'LineCap');
    final cap = capInt == null ? defaults.cap : _capFromInt(capInt);
    final transparency =
        _double(shape, 'LineColorTrans') ?? defaults.transparency;
    final beginArrow = _int(shape, 'BeginArrow') ?? defaults.beginArrow;
    final endArrow = _int(shape, 'EndArrow') ?? defaults.endArrow;
    final beginSize = _int(shape, 'BeginArrowSize');
    final endSize = _int(shape, 'EndArrowSize');
    final rounding =
        readLengthInches(shape, 'Rounding') ?? defaults.roundingInches;
    final softEdges =
        readLengthInches(shape, 'SoftEdgesSize') ?? defaults.softEdgesInches;
    final compoundType = _int(shape, 'CompoundType') ?? defaults.compoundType;
    final gradient = _parseLineGradient(shape) ?? defaults.gradient;

    return VsdxLine(
      color: colorRes.color ?? defaults.color,
      weightInches: weight,
      pattern: pat,
      cap: cap,
      transparency: transparency.clamp(0.0, 1.0),
      themeColorIndex: colorRes.themeIndex ?? defaults.themeColorIndex,
      beginArrow: beginArrow,
      endArrow: endArrow,
      beginArrowSizeInches: beginSize == null
          ? defaults.beginArrowSizeInches
          : _arrowSizeFromBucket(beginSize),
      endArrowSizeInches: endSize == null
          ? defaults.endArrowSizeInches
          : _arrowSizeFromBucket(endSize),
      roundingInches: rounding,
      softEdgesInches: softEdges,
      compoundType: compoundType,
      gradient: gradient,
    );
  }

  /// `LineGradientEnabled` + `<Section N="LineGradient">` (mirrors fill).
  VsdxGradient? _parseLineGradient(XmlElement shape) {
    final enabled = _int(shape, 'LineGradientEnabled') ?? 0;
    if (enabled == 0) return null;
    final dir = _int(shape, 'LineGradientDir') ?? 0;
    final angle = _double(shape, 'LineGradientAngle') ?? 0;
    final stops = <VsdxGradientStop>[];
    for (final section in shape.childElements) {
      if (section.name.local != 'Section') continue;
      if (section.getAttribute('N') != 'LineGradient') continue;
      for (final row in section.childElements) {
        if (row.name.local != 'Row') continue;
        final pos = _doubleIn(row, 'GradientStopPosition') ?? 0;
        final res =
            _resolveRowColor(row, 'GradientStopColor', 'QuickStyleLineColor');
        final t = _doubleIn(row, 'GradientStopColorTrans') ?? 0;
        stops.add(VsdxGradientStop(
          position: pos.clamp(0.0, 1.0),
          color: res.color,
          themeColorIndex: res.themeIndex,
          transparency: t.clamp(0.0, 1.0),
        ));
      }
    }
    if (stops.isEmpty) return null;
    stops.sort((a, b) => a.position.compareTo(b.position));
    return VsdxGradient(
      stops: List.unmodifiable(stops),
      type: _gradientTypeFromDir(dir),
      angleRad: angle,
    );
  }

  /// MS-VSDX §"BeginArrowSize Cell" — buckets 0..6 map to fixed inch values.
  /// Numbers here come from Visio's own tooltips.
  double _arrowSizeFromBucket(int bucket) => switch (bucket) {
        0 => 0.0625,
        1 => 0.0875,
        2 => 0.125,
        3 => 0.175,
        4 => 0.225,
        5 => 0.30,
        6 => 0.375,
        _ => 0.125,
      };

  /// Resolve a `<Cell N="$colorCell">` to either a concrete colour or a
  /// theme index. Returns both `null` when the cell is absent.
  _ColorResolution _resolveColor(
    XmlElement shape,
    String colorCell,
    String quickStyleCell,
  ) {
    final cell = findCell(shape, colorCell);
    if (cell == null) return const _ColorResolution(null, null);
    final v = cell.getAttribute('V') ?? '';
    final f = cell.getAttribute('F') ?? '';
    if (_isThemeFormula(v) || _isThemeFormula(f)) {
      // Prefer an explicit THEMEVAL("AccentColor2") / THEMEVAL(3) argument so
      // FillBkgnd can differ from FillForegnd's QuickStyleFillColor slot.
      final named = _themeValArgSlot(f.isNotEmpty ? f : v);
      if (named != null) return _ColorResolution(null, named);
      // Visio defaults QuickStyle*Color to 1 (lt1) when the cell is absent.
      final idx = _int(shape, quickStyleCell) ?? ThemeSlot.lt1;
      return _ColorResolution(null, idx);
    }
    return _ColorResolution(VsdxColor.tryParse(v), null);
  }

  /// Extract a theme slot from `THEMEVAL("AccentColor2")` / `THEMEVAL(3)`.
  /// Bare `THEMEVAL()` returns `null` (caller uses QuickStyle*Color).
  static int? _themeValArgSlot(String formula) {
    final m = RegExp(
      r'THEMEVAL\s*\(\s*([^),]+)\s*[,)]',
      caseSensitive: false,
    ).firstMatch(formula);
    if (m == null) return null;
    return ThemeSlot.fromThemeValArg(m.group(1)!);
  }

  /// Like [_resolveColor] but reads cells directly from a `<Row>` element
  /// (used for FillGradient stops).
  _ColorResolution _resolveRowColor(
    XmlElement row,
    String colorCell,
    String quickStyleCell,
  ) {
    final cell = findCell(row, colorCell);
    if (cell == null) return const _ColorResolution(null, null);
    final v = cell.getAttribute('V') ?? '';
    final f = cell.getAttribute('F') ?? '';
    if (_isThemeFormula(v) || _isThemeFormula(f)) {
      final idx = _intIn(row, quickStyleCell) ?? ThemeSlot.lt1;
      return _ColorResolution(null, idx);
    }
    // Visio GradientStopColor often stores a theme palette index as a bare
    // integer (`V="1"`). Do NOT route that through [VsdxColor.tryParse], which
    // maps small ints onto the document colour palette.
    if (!v.startsWith('#') && !v.contains('(')) {
      final idx = int.tryParse(v.trim());
      if (idx != null) return _ColorResolution(null, idx);
    }
    return _ColorResolution(VsdxColor.tryParse(v), null);
  }

  double? _doubleIn(XmlElement parent, String name) {
    final cell = findCell(parent, name);
    if (cell == null) return null;
    return double.tryParse(cell.getAttribute('V') ?? '');
  }

  int? _intIn(XmlElement parent, String name) {
    final cell = findCell(parent, name);
    if (cell == null) return null;
    final s = cell.getAttribute('V');
    if (s == null) return null;
    return int.tryParse(s) ?? double.tryParse(s)?.toInt();
  }

  bool _isThemeFormula(String s) {
    final u = s.toUpperCase();
    return u.contains('THEMEVAL') || u.contains('THEMEGUARD');
  }

  double? _double(XmlElement shape, String name) {
    final cell = findCell(shape, name);
    if (cell == null) return null;
    return double.tryParse(cell.getAttribute('V') ?? '');
  }

  int? _int(XmlElement shape, String name) {
    final cell = findCell(shape, name);
    if (cell == null) return null;
    final s = cell.getAttribute('V');
    if (s == null) return null;
    return int.tryParse(s) ?? double.tryParse(s)?.toInt();
  }

  LineCap _capFromInt(int v) => switch (v) {
        0 => LineCap.round,
        1 => LineCap.square,
        2 => LineCap.extended,
        _ => LineCap.round,
      };
}

class _ColorResolution {
  const _ColorResolution(this.color, this.themeIndex);
  final VsdxColor? color;
  final int? themeIndex;
}
