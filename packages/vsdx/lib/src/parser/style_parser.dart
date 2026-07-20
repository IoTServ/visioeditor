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
    final pat = _int(shape, 'FillPattern', inheritFrom: defaults.pattern) ??
        defaults.pattern;

    // Explicit FillGradientEnabled=0 must clear the gradient — do not fall
    // back to Master defaults (writer emits V=0 on clear / group rebuild).
    final fillGradEnabledCell = findCell(shape, 'FillGradientEnabled');
    final parsedFillGrad = _parseGradient(shape);
    final gradient = fillGradEnabledCell != null
        ? parsedFillGrad
        : (parsedFillGrad ?? defaults.gradient);

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
      dir: dir,
    );
  }

  /// Map Visio `FillGradientDir` / `LineGradientDir` to our type enum.
  ///
  /// MS docs: 0 = linear, 1–7 = radial, 8–12 = rectangular, 13 = path.
  /// Also recognise legacy buckets (31–42) that older builds of this writer
  /// incorrectly emitted so those files still open with the right type.
  VsdxGradientType _gradientTypeFromDir(int dir) {
    if (dir >= 1 && dir <= 7) return VsdxGradientType.radial;
    if (dir >= 8 && dir <= 12) return VsdxGradientType.rectangular;
    if (dir == 13) return VsdxGradientType.path;
    // Legacy incorrect buckets (pre MS-enum fix).
    if (dir >= 31 && dir < 35) return VsdxGradientType.rectangular;
    if (dir >= 35 && dir < 39) return VsdxGradientType.radial;
    if (dir >= 39 && dir < 43) return VsdxGradientType.path;
    return VsdxGradientType.linear;
  }

  /// Glow* cells → [VsdxGlow].
  ///
  /// When `GlowSize` is 0/missing the glow is disabled, but companion cells
  /// (`GlowColor` / theme / transparency) are still loaded so toggle-off →
  /// save → reopen → toggle-on can restore them (writer only zeros Size).
  VsdxGlow parseGlow(
    XmlElement shape, {
    VsdxGlow defaults = VsdxGlow.disabled,
  }) {
    final sizeCell = readLengthInches(
      shape,
      'GlowSize',
      inheritFrom: defaults.enabled ? defaults.sizeInches : 0,
    );
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
    final sizeCell = readLengthInches(
      shape,
      'ReflectionSize',
      inheritFrom: defaults.enabled ? defaults.sizeInches : 0,
    );
    final size = sizeCell ?? (defaults.enabled ? defaults.sizeInches : null);
    final dist = readLengthInches(
      shape,
      'ReflectionDist',
      // Only inherit Dist from an enabled master; otherwise keep cached V so
      // F=Inh does not wipe a local distance when Size still enables reflection.
      inheritFrom: defaults.enabled ? defaults.distanceInches : null,
    );
    final blur = readLengthInches(
      shape,
      'ReflectionBlur',
      inheritFrom: defaults.enabled ? defaults.blurInches : null,
    );
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
    double? pageOffsetXInches,
    double? pageOffsetYInches,
  }) {
    final pat = _int(shape, 'ShadowPattern') ?? _int(shape, 'ShdwPattern');
    if (pat == null && !defaults.enabled) return defaults;
    final enabled = (pat ?? (defaults.enabled ? 1 : 0)) != 0;
    final col = _resolveColor(shape, 'ShadowForegnd', 'QuickStyleShadowColor');
    // F=Inh → master defaults when enabled; otherwise page Sheet ShdwOffset*.
    // Missing cell → page Sheet (Visio behaviour for pattern-only shadows).
    final ox = readLengthInches(shape, 'ShadowOffsetX',
        inheritFrom: defaults.enabled
            ? defaults.offsetXInches
            : (pageOffsetXInches ?? defaults.offsetXInches));
    final oy = readLengthInches(shape, 'ShadowOffsetY',
        inheritFrom: defaults.enabled
            ? defaults.offsetYInches
            : (pageOffsetYInches ?? defaults.offsetYInches));
    final blur = readLengthInches(shape, 'ShadowBlur',
        // Blur has no page-sheet fallback; only inherit from an enabled master
        // so F=Inh keeps the cached V instead of the disabled default 0.04".
        inheritFrom: defaults.enabled ? defaults.blurInches : null);
    final transparency =
        (_double(shape, 'ShadowForegndTrans') ?? defaults.transparency)
            .clamp(0.0, 1.0);
    final fallbackOx = pageOffsetXInches ?? defaults.offsetXInches;
    final fallbackOy = pageOffsetYInches ?? defaults.offsetYInches;
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
        pattern: defaults.pattern <= 0 ? 1 : defaults.pattern,
        color: col.color ?? defaults.color,
        themeColorIndex: col.themeIndex ?? defaults.themeColorIndex,
        offsetXInches: ox ?? fallbackOx,
        offsetYInches: oy ?? fallbackOy,
        blurInches: blur ?? defaults.blurInches,
        transparency: transparency,
      );
    }

    final patternId = pat ?? (defaults.pattern <= 0 ? 1 : defaults.pattern);
    return VsdxShadow(
      enabled: true,
      pattern: patternId <= 0 ? 1 : patternId,
      color: col.color ?? defaults.color,
      themeColorIndex: col.themeIndex ?? defaults.themeColorIndex,
      offsetXInches: ox ?? fallbackOx,
      offsetYInches: oy ?? fallbackOy,
      blurInches: blur ?? defaults.blurInches,
      transparency: transparency,
    );
  }

  VsdxLine parseLine(XmlElement shape,
      {VsdxLine defaults = VsdxLine.defaultLine}) {
    final colorRes = _resolveColor(shape, 'LineColor', 'QuickStyleLineColor');
    final weight = readLengthInches(
          shape,
          'LineWeight',
          inheritFrom: defaults.weightInches,
        ) ??
        defaults.weightInches;
    final pat =
        _int(shape, 'LinePattern', inheritFrom: defaults.pattern) ??
            defaults.pattern;
    final capInt = _int(
      shape,
      'LineCap',
      inheritFrom: switch (defaults.cap) {
        LineCap.square => 1,
        LineCap.extended => 2,
        LineCap.round => 0,
      },
    );
    final cap = capInt == null ? defaults.cap : _capFromInt(capInt);
    final transparency =
        _double(shape, 'LineColorTrans') ?? defaults.transparency;
    final beginArrow = _int(shape, 'BeginArrow') ?? defaults.beginArrow;
    final endArrow = _int(shape, 'EndArrow') ?? defaults.endArrow;
    final beginSize = _int(shape, 'BeginArrowSize');
    final endSize = _int(shape, 'EndArrowSize');
    final rounding = readLengthInches(
          shape,
          'Rounding',
          // Stylesheets do not yet resolve Rounding; avoid Inh→0 wiping the
          // cached V when defaults are the zero defaultLine.
          inheritFrom:
              defaults.roundingInches > 1e-12 ? defaults.roundingInches : null,
        ) ??
        defaults.roundingInches;
    final softEdges = readLengthInches(
          shape, 'SoftEdgesSize', inheritFrom: defaults.softEdgesInches) ??
        defaults.softEdgesInches;
    final compoundType =
        _int(shape, 'CompoundType', inheritFrom: defaults.compoundType) ??
            defaults.compoundType;
    // Explicit LineGradientEnabled=0 must clear — do not inherit Master.
    final lineGradEnabledCell = findCell(shape, 'LineGradientEnabled');
    final parsedLineGrad = _parseLineGradient(shape);
    final gradient = lineGradEnabledCell != null
        ? parsedLineGrad
        : (parsedLineGrad ?? defaults.gradient);

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
      dir: dir,
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
      // Prefer cached slot in V (writer emits V=slot + F=THEMEVAL()), then
      // named THEMEVAL arg, then row QuickStyle*, then Light1 fallback.
      final fromV = int.tryParse(v.trim());
      if (fromV != null && fromV >= 0 && fromV < 100 && !_isThemeFormula(v)) {
        return _ColorResolution(null, fromV);
      }
      final named = _themeValArgSlot(f.isNotEmpty ? f : v);
      if (named != null) return _ColorResolution(null, named);
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

  int? _int(XmlElement shape, String name, {int? inheritFrom}) {
    final cell = findCell(shape, name);
    if (cell == null) return null;
    final f = (cell.getAttribute('F') ?? '').trim().toUpperCase();
    if ((f == 'INH' || f.startsWith('INH(')) && inheritFrom != null) {
      return inheritFrom;
    }
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
