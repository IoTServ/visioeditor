/// Page-level [CustomPainter] for the Visio viewer.
///
/// As of M3+M6-snapshot the painter:
///  * Draws real shape geometry when available (`VsdxShape.geometries`
///    non-empty). Geometry-less 2-D shapes (common Edraw text labels) paint
///    text only — matching libvisio, which skips fill/line when there is no
///    path. Missing foreign images still get a bounding-box placeholder.
///  * Honours [VsdxFill] / [VsdxLine] (incl. gradients, dashes, themes).
///  * Applies drop-shadow effects when the shape has `Shadow*` cells.
///  * Decorates 1-D shapes' line endings with [arrowDescriptor] heads.
///  * Filters shapes by Layer visibility.
///  * Renders rich text via the per-run [VsdxCharStyle] / [VsdxParaStyle].
library;

import 'dart:math' as math;
import 'dart:ui' as ui show FontFeature, Gradient, ImageFilter;

import 'package:flutter/material.dart';

import 'package:vsdx/vsdx.dart'
    hide
        kDefaultLineJumpRadiusInches,
        lineJumpsEnabledForCode,
        polylineCrossings,
        polylineSvg,
        polylineWithJumpsSvg,
        segmentIntersection;
import 'arrow_library.dart';
import 'connector_router.dart';
import 'dash_path.dart';
import 'font_fallback.dart';
import 'image_cache.dart';
import 'line_jumps.dart';
import 'path_builder.dart';
import 'pattern_fill.dart';
import 'shape_bounds.dart' as bounds;

class VsdxPainter extends CustomPainter {
  VsdxPainter({
    required this.page,
    this.underlayPage,
    this.theme = VsdxTheme.empty,
    this.images = ImageRegistry.empty,
    this.imageCache,
    this.patternBuilder = PatternFillBuilder.empty,
    this.pxPerInch = 96.0,
    this.backgroundColor = Colors.white,
    this.placeholderAccent = const Color(0x331F6FEB),
    this.placeholderStroke = const Color(0xFF1F6FEB),
    this.fallbackFill = Colors.white,
    this.fallbackStroke = Colors.black,
    this.respectLayerVisibility = true,
    this.visibleLayerIdsOverride,
    this.underlayVisibleLayerIdsOverride,
    this.router = const ConnectorRouter(),
    this.fontFallback = VsdxFontFallback.defaults,
    this.noPageLoadedMessage = 'No page loaded',
    this.noShapesOnPageMessage = 'No shapes parsed yet',
    this.drawLineJumps = true,
    this.lineJumpRadiusInches = 0.07,
  }) : super(repaint: imageCache);

  final VsdxPage? page;

  /// Optional Visio / draw.io background page drawn underneath [page]'s shapes
  /// (read-only composite). Hit-testing / editing still target [page] only.
  final VsdxPage? underlayPage;
  final VsdxTheme theme;

  /// Embedded raster images (`/visio/media/*`). Optional — when missing
  /// `imagePartName` references render as a labelled placeholder.
  final ImageRegistry images;

  /// Async decode cache. The painter listens to it (`super.repaint`) so a
  /// late-arriving decode automatically triggers a rebuild.
  final VsdxImageCache? imageCache;

  /// Pre-rendered hatching tiles. Use [PatternFillBuilder.warmUp] at app
  /// startup; the default empty builder falls back to solid fills.
  final PatternFillBuilder patternBuilder;

  /// Pre-computed shape bounding boxes (page-inch coords). Allows the
  /// painter to skip shapes outside the viewport — a 10× win on dense
  /// drawings. Populated lazily on first paint.
  static final Expando<Map<int, Rect>> _bboxCache =
      Expando<Map<int, Rect>>('vsdx_bbox');

  final double pxPerInch;
  final Color backgroundColor;
  final Color placeholderAccent;
  final Color placeholderStroke;
  final Color fallbackFill;
  final Color fallbackStroke;

  /// When `true` shapes whose only layer(s) have `Visible == false` are
  /// skipped. Set to `false` for export/diagnostic flows where everything
  /// should be drawn.
  final bool respectLayerVisibility;

  /// When non-null, overrides [VsdxPage.visibleLayerIds] — used by the
  /// layer panel to toggle visibility without mutating the parsed model.
  /// Applies only to [page], never to [underlayPage] (layer ids differ).
  final Set<int>? visibleLayerIdsOverride;

  /// Layer filter for [underlayPage] only (e.g. printable layers on PNG export).
  /// When null, the underlay uses its own [VsdxPage.visibleLayerIds].
  final Set<int>? underlayVisibleLayerIdsOverride;

  /// Auto-router for 1-D connectors that lack a Geometry section. The
  /// default router emits orthogonal Manhattan paths.
  final ConnectorRouter router;

  /// Maps Visio's Windows-centric font names to a per-platform
  /// fallback chain, so text remains readable on Linux/macOS/Web where
  /// e.g. `Calibri` is not installed. See [VsdxFontFallback].
  final VsdxFontFallback fontFallback;
  final String noPageLoadedMessage;
  final String noShapesOnPageMessage;

  /// Line jumps (drawio's "Line jumps"): arc a connector over the lower-z
  /// connectors it crosses, so overlaps read as hops rather than "+" junctions.
  final bool drawLineJumps;

  /// Jump arc radius, in page inches.
  final double lineJumpRadiusInches;

  // Per-paint cache (filled at the top of [paint]): every connector's
  // page-space polyline in z-order, plus a shape-id → z-index lookup. Used so a
  // connector can hop over the connectors drawn beneath it.
  List<List<Offset>> _connRoutesPage = const <List<Offset>>[];
  Map<int, int> _connZ = const <int, int>{};

  /// Whether line jumps are active for the page being painted — combines the
  /// [drawLineJumps] switch with the page's `LineJumpCode` (0 = None disables
  /// jumps, so crossing connectors draw straight through).
  bool _lineJumpsActive = false;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final p = page;
    final pageBg = p?.backgroundColor;
    canvas.drawRect(
      rect,
      Paint()
        ..color = pageBg == null ? backgroundColor : Color(pageBg.value),
    );

    if (p == null) {
      _drawPlaceholderText(canvas, size, noPageLoadedMessage);
      return;
    }

    canvas.drawRect(
      rect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black26,
    );

    final underlay = underlayPage;
    final hasUnderlay = underlay != null && underlay.shapes.isNotEmpty;
    if (p.shapes.isEmpty && !hasUnderlay) {
      _drawPlaceholderText(
        canvas,
        size,
        '${p.name}\n'
        '${p.widthInches.toStringAsFixed(2)} × '
        '${p.heightInches.toStringAsFixed(2)} in\n'
        '$noShapesOnPageMessage',
      );
      return;
    }

    canvas.save();
    canvas.translate(0, p.heightInches * pxPerInch);
    canvas.scale(pxPerInch, -pxPerInch);

    // Background page first (Visio BackPage / drawio background), clipped to
    // the foreground page's box so an oversized underlay doesn't spill.
    if (hasUnderlay) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, p.widthInches, p.heightInches));
      _paintPageShapes(canvas, underlay);
      canvas.restore();
    }

    if (p.shapes.isNotEmpty) {
      _paintPageShapes(canvas, p);
    }
    canvas.restore();
  }

  /// Page whose shapes are currently being painted (foreground or underlay).
  /// Used by [_pageToLocal] so nested inverse XForms resolve against the
  /// correct shape tree.
  VsdxPage? _paintTarget;

  /// Paint [target]'s top-level shapes in the current (page-inch, Y-up) canvas.
  void _paintPageShapes(Canvas canvas, VsdxPage target) {
    _paintTarget = target;
    final isUnderlay =
        underlayPage != null && identical(target, underlayPage);
    final visibleLayers = !respectLayerVisibility
        ? null
        : isUnderlay
            ? (underlayVisibleLayerIdsOverride ??
                (target.layers.isEmpty ? null : target.visibleLayerIds))
            : (visibleLayerIdsOverride ??
                (target.layers.isEmpty ? null : target.visibleLayerIds));
    final bboxes = _bboxesFor(target);
    final viewportInches =
        Rect.fromLTWH(0, 0, target.widthInches, target.heightInches);

    _lineJumpsActive = drawLineJumps &&
        lineJumpsEnabledForCode(target.pageSheet.lineJumpCode);
    if (_lineJumpsActive) {
      _computeConnectorRoutes(target);
    } else {
      _connRoutesPage = const <List<Offset>>[];
      _connZ = const <int, int>{};
    }

    for (final shape in target.shapes) {
      _paintShape(canvas, shape, visibleLayers, bboxes, viewportInches);
    }
  }

  Map<int, Rect> _bboxesFor(VsdxPage p) {
    final cached = _bboxCache[p];
    if (cached != null) return cached;
    final out = bounds.buildShapeBounds(p);
    _bboxCache[p] = out;
    return out;
  }

  /// Cache every connector's page-space polyline (z-ordered, including nested
  /// and geometry-less) so a connector can hop over ones drawn beneath it.
  void _computeConnectorRoutes(VsdxPage p) {
    final routes = <List<Offset>>[];
    final z = <int, int>{};
    void walk(List<VsdxShape> list) {
      for (final s in list) {
        if (s.isGlueableConnector) {
          final pts = p.drawnConnectorPagePolyline(s);
          if (pts.length >= 2) {
            z[s.id] = routes.length;
            routes.add(<Offset>[for (final pt in pts) Offset(pt.x, pt.y)]);
          }
        }
        if (!s.collapsed) walk(s.children);
      }
    }

    walk(p.shapes);
    _connRoutesPage = routes;
    _connZ = z;
  }

  /// Local MoveTo/LineTo vertices of [g], or empty if it holds any other
  /// command (i.e. it isn't a plain polyline).
  List<Offset> _polylineLocalPoints(VsdxGeometry g) {
    final pts = <Offset>[];
    for (final c in g.commands) {
      switch (c) {
        case MoveTo(:final x, :final y):
          pts.add(Offset(x, y));
        case LineTo(:final x, :final y):
          pts.add(Offset(x, y));
        default:
          return const <Offset>[];
      }
    }
    return pts;
  }

  /// Map a shape-local point (origin bottom-left, Y-up) to page inches.
  Offset _localToPageOffset(VsdxShape s, Offset local) {
    final p = VsdxPage.localToPage(s, Offset2D(local.dx, local.dy));
    return Offset(p.x, p.y);
  }

  void _paintShape(
    Canvas canvas,
    VsdxShape shape,
    Set<int>? visibleLayers,
    Map<int, Rect> bboxes,
    Rect viewport,
  ) {
    if (visibleLayers != null && shape.layerMemberIds.isNotEmpty) {
      if (!shape.isOnAnyLayer(visibleLayers)) return;
    }
    // Cheap reject: if the shape's bbox doesn't intersect the viewport,
    // and it has no children, skip it entirely.
    final bbox = bboxes[shape.id];
    if (bbox != null &&
        shape.children.isEmpty &&
        !bbox.overlaps(viewport)) {
      return;
    }

    final w = shape.width;
    final h = shape.height;
    final localPinX = shape.effectiveLocPinX;
    final localPinY = shape.effectiveLocPinY;

    canvas.save();
    canvas.translate(shape.pinX, shape.pinY);
    if (shape.angleRad != 0) canvas.rotate(shape.angleRad);
    if (shape.flipX || shape.flipY) {
      canvas.scale(shape.flipX ? -1.0 : 1.0, shape.flipY ? -1.0 : 1.0);
    }
    canvas.translate(-localPinX, -localPinY);

    if (shape.hasImage) {
      _paintImage(canvas, shape, Rect.fromLTWH(0, 0, w, h));
    } else if (shape.hasGeometry) {
      _paintGeometries(canvas, shape);
    } else if (shape.isGlueableConnector) {
      _paint1DFallback(canvas, shape);
    }
    // Geometry-less 2-D leaves (e.g. Edraw "70% 隐性" text boxes that store
    // FillPattern/LinePattern but no `<Section N="Geometry">`) must not get a
    // synthetic rect. libvisio only emits fill/line when path geometry exists
    // (`m_fillStyle.pattern && !m_currentFillGeometry.empty()`). Groups with
    // children already skip any placeholder; text is painted below.

    // Editor chrome (dashed kind hint / fold chevron) is only for foldable
    // containers & callouts — never for plain Visio/Edraw groups.
    if (shape.shapeKind.isFoldable || shape.shapeKind.isAnnotative) {
      _paintKindHint(canvas, shape, w, h);
    }

    _paintLineEndings(canvas, shape);
    _paintRichText(canvas, shape, Rect.fromLTWH(0, 0, w, h));

    // Children inherit the parent's local frame: their PinX/PinY are
    // interpreted in the (0..parentWidth, 0..parentHeight) box, so we paint
    // them BEFORE restoring the canvas. (M4-06.) Collapsed containers keep
    // their children in the model but hide them (draw.io fold).
    if (!shape.collapsed) {
      for (final child in shape.children) {
        if (TableOps.isCovered(child)) continue;
        _paintShape(canvas, child, visibleLayers, bboxes, viewport);
      }
    }

    if (shape.shapeKind.isFoldable) {
      _paintCollapseChevron(canvas, shape, w, h);
    }

    canvas.restore();
  }

  void _paintGeometries(Canvas canvas, VsdxShape shape) {
    final dashes = dashPatternFor(shape.line.pattern);

    for (final geom in shape.geometries) {
      if (geom.noShow) continue;
      final path = buildPath(
        geom,
        widthInches: shape.width,
        heightInches: shape.height,
        roundingInches: shape.line.roundingInches,
      );
      _drawShadow(canvas, shape, path, geom: geom);
      _drawGlow(canvas, shape, path);
      _drawReflection(canvas, shape, path);
      // Soft Edges (Visio SoftEdgesSize): feather fill/stroke via a blurred
      // offscreen layer. Skip 1D connectors — jumps / arrows stay crisp.
      final soft = shape.line.softEdgesInches;
      final useSoft = soft > 0 && !shape.is1D;
      if (useSoft) {
        final bounds = path.getBounds().inflate(soft * 3);
        canvas.saveLayer(
          bounds,
          Paint()
            ..imageFilter = ui.ImageFilter.blur(
              sigmaX: soft,
              sigmaY: soft,
              tileMode: TileMode.decal,
            ),
        );
      }
      if (!geom.noFill && shape.fill.hasFill) {
        _drawFill(canvas, shape, path);
      }
      if (!geom.noLine && shape.line.hasLine) {
        final strokePaint = _resolveStrokePaint(shape);
        if (strokePaint != null) {
          // A line gradient (LineGradientEnabled) paints the stroke with a
          // shader; without this the colour resolves to the black fallback.
          if (shape.line.hasGradient) {
            final shader =
                _buildGradientShader(shape.line.gradient!, path.getBounds());
            if (shader != null) strokePaint.shader = shader;
          }
          var strokeSrc = path;
          if (shape.isGlueableConnector && _lineJumpsActive) {
            final jumped = _lineJumpsPath(shape, geom);
            if (jumped != null) strokeSrc = jumped;
          }
          final strokeP =
              dashes == null ? strokeSrc : dashedPath(strokeSrc, dashes);
          _drawCompoundStroke(
            canvas,
            strokeP,
            strokePaint,
            shape.line.compoundType,
            shape.line.weightInches,
          );
        }
      }
      if (useSoft) canvas.restore();
    }
  }

  /// Draw a stroke honouring Visio `CompoundType`
  /// (0=single, 1=double, 2=thick-thin, 3=thin-thick).
  ///
  /// Every compound type is approximated as a clean double line: a full-width
  /// stroke with a concentric transparent gap, preserving the stored total
  /// width. A faithful thick-thin / thin-thick would require offsetting
  /// arbitrary geometry, so we render the same double rail for 1–3 (the model
  /// value still round-trips through the writer).
  void _drawCompoundStroke(
    Canvas canvas,
    Path path,
    Paint paint,
    int compoundType,
    double weightInches,
  ) {
    final w = math.max(paint.strokeWidth, weightInches);
    if (compoundType <= 0 || w < 1e-6) {
      canvas.drawPath(path, paint);
      return;
    }
    final bounds = path.getBounds().inflate(w * 2);
    canvas.saveLayer(bounds, Paint());
    canvas.drawPath(path, paint..strokeWidth = w);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = paint.strokeCap
        ..strokeJoin = paint.strokeJoin
        ..strokeWidth = w * 0.38
        ..blendMode = BlendMode.clear,
    );
    canvas.restore();
  }

  /// Stroke path for connector [shape]'s polyline [geom] with a small arc over
  /// every crossing with a lower-z connector (line jumps), or `null` when it
  /// crosses nothing (draw the plain path).
  Path? _lineJumpsPath(VsdxShape shape, VsdxGeometry geom) {
    final k = _connZ[shape.id];
    if (k == null || k == 0) return null; // nothing drawn beneath it
    // Prefer the shared page-space route (includes geometry-less / nested).
    final pageRoute = _connRoutesPage[k];
    final route = pageRoute.isNotEmpty
        ? <Offset>[for (final pg in pageRoute) _pageToLocal(shape, pg)]
        : _polylineLocalPoints(geom);
    if (route.length < 2) return null;
    final unders = <List<Offset>>[
      for (var i = 0; i < k; i++)
        <Offset>[for (final pg in _connRoutesPage[i]) _pageToLocal(shape, pg)],
    ];
    if (polylineCrossings(route, unders).isEmpty) return null;
    return polylineWithJumps(route, unders, lineJumpRadiusInches);
  }

  /// 1-D shape with no explicit Geometry section — route an orthogonal
  /// path between BeginX/Y and EndX/Y (snapping to glued shape centres
  /// when the page exposes connect records).
  void _paint1DFallback(Canvas canvas, VsdxShape shape) {
    final stroke = _resolveStrokePaint(shape);
    if (stroke == null) return;
    final ctx = _paintTarget ?? page;
    final routed = router.route(shape, page: ctx);
    if (routed == null) return;

    final pts = routed.points.toList(growable: false);
    final localPts = <Offset>[
      for (final p in pts) _pageToLocal(shape, p),
    ];
    Path path;
    final k = _connZ[shape.id];
    if (_lineJumpsActive && k != null && k > 0) {
      final unders = <List<Offset>>[
        for (var i = 0; i < k; i++)
          <Offset>[
            for (final pg in _connRoutesPage[i]) _pageToLocal(shape, pg),
          ],
      ];
      path = polylineCrossings(localPts, unders).isEmpty
          ? _polylinePath(localPts)
          : polylineWithJumps(localPts, unders, lineJumpRadiusInches);
    } else {
      path = _polylinePath(localPts);
    }
    // Match [_paintGeometries]: LineGradient + CompoundType on connectors
    // that only carry BeginX/EndX (no Geometry section).
    if (shape.line.hasGradient) {
      final shader =
          _buildGradientShader(shape.line.gradient!, path.getBounds());
      if (shader != null) stroke.shader = shader;
    }
    final dashes = dashPatternFor(shape.line.pattern);
    final strokeP = dashes == null ? path : dashedPath(path, dashes);
    _drawCompoundStroke(
      canvas,
      strokeP,
      stroke,
      shape.line.compoundType,
      shape.line.weightInches,
    );
  }

  Path _polylinePath(List<Offset> pts) {
    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      if (i == 0) {
        path.moveTo(pts[i].dx, pts[i].dy);
      } else {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
    }
    return path;
  }

  /// Map a page-inch point into [shape]'s local frame, composing ancestor
  /// XForms when the shape is nested (matches SVG `pageToLocalDeep`).
  Offset _pageToLocal(VsdxShape shape, Offset pagePoint) {
    final ctx = _paintTarget ?? page;
    if (ctx == null) {
      return Offset(
        pagePoint.dx - shape.pinX + shape.effectiveLocPinX,
        pagePoint.dy - shape.pinY + shape.effectiveLocPinY,
      );
    }
    final local = ctx.pageToLocalDeep(
      shape.id,
      Offset2D(pagePoint.dx, pagePoint.dy),
    );
    return Offset(local.x, local.y);
  }

  static Offset2D _polylineMidpoint(List<Offset2D> route) {
    if (route.isEmpty) return const Offset2D(0, 0);
    if (route.length == 1) return route.first;
    var total = 0.0;
    for (var i = 0; i < route.length - 1; i++) {
      final dx = route[i + 1].x - route[i].x;
      final dy = route[i + 1].y - route[i].y;
      total += math.sqrt(dx * dx + dy * dy);
    }
    if (total <= 0) return route.first;
    var remaining = total / 2;
    for (var i = 0; i < route.length - 1; i++) {
      final dx = route[i + 1].x - route[i].x;
      final dy = route[i + 1].y - route[i].y;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len >= remaining) {
        final t = len == 0 ? 0.0 : remaining / len;
        return Offset2D(route[i].x + dx * t, route[i].y + dy * t);
      }
      remaining -= len;
    }
    return route.last;
  }

  void _drawFill(Canvas canvas, VsdxShape shape, Path path) {
    final fill = shape.fill;
    if (fill.hasGradient) {
      final bounds = path.getBounds();
      if (bounds.isEmpty) return;
      final shader = _buildGradientShader(fill.gradient!, bounds);
      if (shader != null) {
        canvas.drawPath(path, Paint()..shader = shader);
        return;
      }
    }
    if (fill.pattern > 1) {
      final fgRaw = _colourOrTheme(
              fill.foreground, fill.themeForegroundIndex) ??
          fallbackFill;
      final fgT = fill.foregroundTransparency.clamp(0.0, 1.0);
      final fg = fgRaw.withValues(alpha: fgRaw.a * (1.0 - fgT));
      final hatch = patternBuilder.paintFor(
        fill.pattern,
        foreground: fg,
      );
      if (hatch != null) {
        // Draw background colour first (the hatch tiles are mostly
        // transparent) — Visio's FillBkgnd / FillBkgndTrans fill the gaps.
        final bgRaw = _colourOrTheme(
            fill.background, fill.themeBackgroundIndex);
        if (bgRaw != null) {
          final bgT = fill.backgroundTransparency.clamp(0.0, 1.0);
          final bg = bgRaw.withValues(alpha: bgRaw.a * (1.0 - bgT));
          canvas.drawPath(path, Paint()..color = bg);
        }
        canvas.drawPath(path, hatch);
        return;
      }
    }
    final solid = _resolveFillPaint(shape);
    if (solid != null) canvas.drawPath(path, solid);
  }

  Shader? _buildGradientShader(VsdxGradient gradient, Rect bounds) {
    if (gradient.stops.isEmpty) return null;
    final colors = <Color>[];
    final stops = <double>[];
    for (final s in gradient.stops) {
      final base = _colourOrTheme(s.color, s.themeColorIndex) ?? fallbackFill;
      colors.add(base.withValues(alpha: (1 - s.transparency).clamp(0.0, 1.0)));
      stops.add(s.position);
    }
    if (colors.length == 1) {
      colors.add(colors.first);
      stops.add(1.0);
    }
    switch (gradient.type) {
      case VsdxGradientType.linear:
        final c = bounds.center;
        final r = math.max(bounds.width, bounds.height) * 0.6;
        final dx = math.cos(gradient.angleRad) * r;
        final dy = math.sin(gradient.angleRad) * r;
        return ui.Gradient.linear(
          Offset(c.dx - dx, c.dy - dy),
          Offset(c.dx + dx, c.dy + dy),
          colors,
          stops,
        );
      case VsdxGradientType.radial:
      case VsdxGradientType.path:
      case VsdxGradientType.rectangular:
        return ui.Gradient.radial(
          bounds.center,
          math.max(bounds.width, bounds.height) * 0.6,
          colors,
          stops,
        );
    }
  }

  void _drawReflection(Canvas canvas, VsdxShape shape, Path path) {
    final refl = shape.reflection;
    if (!refl.enabled || refl.sizeInches <= 0) return;
    final alpha = (1 - refl.transparency).clamp(0.0, 1.0);
    if (alpha <= 0) return;

    final bounds = path.getBounds();
    if (bounds.isEmpty) return;

    final clipHeight = bounds.height * refl.sizeInches.clamp(0.01, 1.0);
    final pivotY = bounds.bottom + refl.distanceInches;
    final clip = Rect.fromLTWH(
      bounds.left - bounds.width,
      pivotY,
      bounds.width * 3,
      clipHeight + refl.blurInches,
    );

    canvas.save();
    canvas.clipRect(clip);
    canvas.translate(0, pivotY);
    canvas.scale(1, -1);
    canvas.translate(0, -pivotY);

    canvas.saveLayer(bounds.inflate(refl.blurInches * 2), Paint());

    final fill = _resolveFillPaint(shape);
    if (fill != null) {
      canvas.drawPath(
        path,
        fill..color = fill.color.withValues(alpha: fill.color.a * alpha),
      );
    }
    final stroke = _resolveStrokePaint(shape);
    if (stroke != null && shape.line.hasLine) {
      canvas.drawPath(
        path,
        stroke..color = stroke.color.withValues(alpha: stroke.color.a * alpha),
      );
    }

    canvas.drawRect(
      Rect.fromLTWH(bounds.left, pivotY, bounds.width, clipHeight),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(bounds.left, pivotY),
          Offset(bounds.left, pivotY + clipHeight),
          const [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
        )
        ..blendMode = BlendMode.dstIn,
    );
    canvas.restore();
    canvas.restore();
  }

  void _drawGlow(Canvas canvas, VsdxShape shape, Path path) {
    final glow = shape.glow;
    if (!glow.enabled || glow.sizeInches <= 0) return;
    final base = _colourOrTheme(glow.color, glow.themeColorIndex) ??
        const Color(0xFFFFC107);
    final alpha = (1 - glow.transparency).clamp(0.0, 1.0);
    if (alpha <= 0) return;
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = glow.sizeInches * 2
        ..color = base.withValues(alpha: base.a * alpha * 0.6)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          math.max(glow.sizeInches, 0.001),
        ),
    );
  }

  void _drawShadow(
    Canvas canvas,
    VsdxShape shape,
    Path path, {
    VsdxGeometry? geom,
  }) {
    final shadow = shape.shadow;
    if (!shadow.enabled) return;
    final base = _colourOrTheme(shadow.color, shadow.themeColorIndex) ??
        const Color(0x99000000);
    final alpha = (1 - shadow.transparency).clamp(0.0, 1.0);
    if (alpha <= 0) return;
    // Connectors / line-only geometry: stroke the shadow (Visio ShadowPattern
    // on open paths). Filled shapes keep a filled drop shadow.
    final lineOnly = shape.is1D ||
        (geom?.noFill ?? false) ||
        !shape.fill.hasFill;
    final paint = Paint()
      ..color = base.withValues(alpha: base.a * alpha)
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        math.max(shadow.blurInches, 0.001),
      )
      ..style = lineOnly ? PaintingStyle.stroke : PaintingStyle.fill;
    if (lineOnly) {
      paint
        ..strokeWidth = math.max(shape.line.weightInches, 0.01)
        ..strokeCap = _flutterCap(shape)
        ..strokeJoin = shape.line.roundingInches > 0
            ? StrokeJoin.round
            : StrokeJoin.miter;
    }
    canvas.save();
    // Visio Y increases up; we're already in inverted Y when this runs.
    canvas.translate(shadow.offsetXInches, -shadow.offsetYInches);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  void _paintLineEndings(Canvas canvas, VsdxShape shape) {
    if (!shape.line.hasLine) return;
    if (!shape.line.hasBeginArrow && !shape.line.hasEndArrow) return;
    final endPoints = _lineEndPoints(shape);
    if (endPoints == null) return;
    // NB: the fallback Paint is parenthesised so the cascade only applies to
    // it — writing `_resolveStrokePaint(shape) ?? Paint()..color = …` binds the
    // cascade to the whole `??` result and clobbers the real line colour with
    // the fallback (that bug painted every arrow head black).
    final paint = _resolveStrokePaint(shape) ??
        (Paint()
          ..style = PaintingStyle.stroke
          ..color = fallbackStroke);

    if (shape.line.hasBeginArrow) {
      _drawArrowAt(
        canvas,
        endPoints.start,
        math.atan2(
          endPoints.start.dy - endPoints.beginTangent.dy,
          endPoints.start.dx - endPoints.beginTangent.dx,
        ),
        shape.line.beginArrow,
        shape.line.beginArrowSizeInches,
        paint,
      );
    }
    if (shape.line.hasEndArrow) {
      _drawArrowAt(
        canvas,
        endPoints.end,
        math.atan2(
          endPoints.end.dy - endPoints.endTangent.dy,
          endPoints.end.dx - endPoints.endTangent.dx,
        ),
        shape.line.endArrow,
        shape.line.endArrowSizeInches,
        paint,
      );
    }
  }

  _LineEndpoints? _lineEndPoints(VsdxShape shape) {
    // The arrow tip must sit exactly where the *drawn* line ends. When the
    // connector carries a Geometry section (the common case — Visio bakes the
    // route already clipped to the target shape's perimeter, and so does our
    // editor via rerouteConnectors) use those endpoints. Using the auto-router
    // here instead snapped the tip to the target shape's centre, so arrow heads
    // ended up *inside* the rectangles / diamonds they point at.
    if (shape.hasGeometry) {
      final geo = _geometryEndpoints(shape);
      if (geo != null) return geo;
    }
    // Geometry-less connector: fall back to the auto-router (which now attaches
    // on the target's perimeter, see ConnectorRouter).
    if (shape.isGlueableConnector &&
        shape.beginX != null &&
        shape.endX != null) {
      final routed = router.route(shape, page: _paintTarget ?? page);
      if (routed != null) {
        final pts = routed.points
            .map((p) => _pageToLocal(shape, p))
            .toList(growable: false);
        if (pts.length >= 2) {
          return _LineEndpoints(
            pts.first,
            pts.last,
            // Tangent direction at each tip — based on the *adjacent* segment
            // so the arrow head stays parallel to the last leg of the path.
            beginTangent: pts[1],
            endTangent: pts[pts.length - 2],
          );
        }
      }
    }
    return _geometryEndpoints(shape);
  }

  /// Walk the shape's first non-empty Geometry section and recover the
  /// begin / end vertices (plus their tangent neighbours) so [_paintLineEndings]
  /// can render arrow heads on path-defined connectors and polylines.
  _LineEndpoints? _geometryEndpoints(VsdxShape shape) {
    if (shape.geometries.isEmpty) return null;
    final w = shape.width;
    final h = shape.height;
    for (final geom in shape.geometries) {
      if (geom.commands.isEmpty) continue;
      final vertices = <Offset>[];
      Offset cursor = Offset.zero;
      var penDown = false;
      void addVertex(Offset p) {
        if (vertices.isEmpty || p != vertices.last) {
          vertices.add(p);
        }
        cursor = p;
      }

      final cmds = geom.commands;
      for (var i = 0; i < cmds.length; i++) {
        final cmd = cmds[i];
        switch (cmd) {
          case MoveTo(:final x, :final y):
            cursor = Offset(x, y);
            penDown = false;
          case RelMoveTo(:final fx, :final fy):
            cursor = Offset(fx * w, fy * h);
            penDown = false;
          case LineTo(:final x, :final y):
            if (!penDown) {
              addVertex(cursor);
              penDown = true;
            }
            addVertex(Offset(x, y));
          case RelLineTo(:final fx, :final fy):
            if (!penDown) {
              addVertex(cursor);
              penDown = true;
            }
            addVertex(Offset(fx * w, fy * h));
          case ArcTo(:final x, :final y, :final bow):
            if (!penDown) {
              addVertex(cursor);
              penDown = true;
            }
            for (final p in sampleArcByBow(
              start: Offset2D(cursor.dx, cursor.dy),
              end: Offset2D(x, y),
              bow: bow,
              steps: 8,
            )) {
              addVertex(Offset(p.x, p.y));
            }
          case RelArcTo(:final fx, :final fy, :final fbow):
            if (!penDown) {
              addVertex(cursor);
              penDown = true;
            }
            final ex = fx * w, ey = fy * h;
            final bow = fbow * (w + h) / 2;
            for (final p in sampleArcByBow(
              start: Offset2D(cursor.dx, cursor.dy),
              end: Offset2D(ex, ey),
              bow: bow,
              steps: 8,
            )) {
              addVertex(Offset(p.x, p.y));
            }
          case CubBezTo(:final x, :final y, :final x1, :final y1, :final x2, :final y2):
            if (!penDown) {
              addVertex(cursor);
              penDown = true;
            }
            // Near-end control gives a better end-arrow tangent than the chord.
            addVertex(Offset(x1, y1));
            addVertex(Offset(x2, y2));
            addVertex(Offset(x, y));
          case RelCubBezTo(
              :final fx,
              :final fy,
              :final fx1,
              :final fy1,
              :final fx2,
              :final fy2,
            ):
            if (!penDown) {
              addVertex(cursor);
              penDown = true;
            }
            addVertex(Offset(fx1 * w, fy1 * h));
            addVertex(Offset(fx2 * w, fy2 * h));
            addVertex(Offset(fx * w, fy * h));
          case QuadBezTo(:final x, :final y, :final x1, :final y1):
            if (!penDown) {
              addVertex(cursor);
              penDown = true;
            }
            addVertex(Offset(x1, y1));
            addVertex(Offset(x, y));
          case RelQuadBezTo(:final fx, :final fy, :final fx1, :final fy1):
            if (!penDown) {
              addVertex(cursor);
              penDown = true;
            }
            addVertex(Offset(fx1 * w, fy1 * h));
            addVertex(Offset(fx * w, fy * h));
          case EllipticalArcTo(
              :final x,
              :final y,
              :final controlX,
              :final controlY,
              :final angle,
              :final eccentricity,
            ):
            if (!penDown) {
              addVertex(cursor);
              penDown = true;
            }
            final arc = sampleEllipticalArc(
              start: Offset2D(cursor.dx, cursor.dy),
              end: Offset2D(x, y),
              control: Offset2D(controlX, controlY),
              angle: angle,
              eccentricity: eccentricity,
              steps: 8,
            );
            for (final p in arc) {
              addVertex(Offset(p.x, p.y));
            }
          case RelEllipticalArcTo(
              :final fx,
              :final fy,
              :final fcx,
              :final fcy,
              :final angle,
              :final eccentricity,
            ):
            if (!penDown) {
              addVertex(cursor);
              penDown = true;
            }
            final arc = sampleEllipticalArc(
              start: Offset2D(cursor.dx, cursor.dy),
              end: Offset2D(fx * w, fy * h),
              control: Offset2D(fcx * w, fcy * h),
              angle: angle,
              eccentricity: eccentricity,
              steps: 8,
            );
            for (final p in arc) {
              addVertex(Offset(p.x, p.y));
            }
          case final PolylineTo poly:
            if (!penDown) {
              addVertex(cursor);
              penDown = true;
            }
            final vsx = poly.vertsRelative ? w : 1.0;
            final vsy = poly.vertsYRelative ? h : 1.0;
            final esx = poly.relative ? w : 1.0;
            final esy = poly.relative ? h : 1.0;
            for (final v in poly.vertices) {
              addVertex(Offset(v.x * vsx, v.y * vsy));
            }
            addVertex(Offset(poly.x * esx, poly.y * esy));
          case SplineStart():
            if (!penDown) {
              addVertex(cursor);
              penDown = true;
            }
            final spline = consumeSplineSequence(
              cmds,
              i,
              pen: Offset2D(cursor.dx, cursor.dy),
              width: w,
              height: h,
              samples: 8,
            );
            for (final p in spline.samples) {
              addVertex(Offset(p.x, p.y));
            }
            cursor = Offset(spline.end.x, spline.end.y);
            i = spline.nextIndex - 1;
          case SplineKnot():
            break;
          case NurbsTo(
              :final x,
              :final y,
              :final controlPoints,
              :final weights,
              :final knots,
              :final degree,
              :final relative,
              :final cpRelative,
              :final cpYRelative,
            ):
            if (!penDown) {
              addVertex(cursor);
              penDown = true;
            }
            final csx = cpRelative ? w : 1.0;
            final csy = cpYRelative ? h : 1.0;
            final esx = relative ? w : 1.0;
            final esy = relative ? h : 1.0;
            final end = Offset(x * esx, y * esy);
            final samples = sampleNurbs(
              start: Offset2D(cursor.dx, cursor.dy),
              end: Offset2D(end.dx, end.dy),
              controlPoints: <Offset2D>[
                for (final p in controlPoints) Offset2D(p.x * csx, p.y * csy),
              ],
              weights: weights,
              knots: knots,
              degree: degree,
              samples: 8,
            );
            for (final p in samples) {
              addVertex(Offset(p.x, p.y));
            }
            // Exact NurbsTo endpoint (samples are dense approximations).
            addVertex(end);
          case EllipseCmd():
          // Closed primitive — no meaningful "tip" for arrows; skip it
          // and let the next geometry contribute endpoints.
          case InfiniteLineCmd():
          // Conceptually unbounded; tangent direction is undefined.
        }
      }
      if (vertices.length >= 2) {
        return _LineEndpoints(
          vertices.first,
          vertices.last,
          beginTangent: vertices[1],
          endTangent: vertices[vertices.length - 2],
        );
      }
    }
    return null;
  }

  void _drawArrowAt(
    Canvas canvas,
    Offset tip,
    double angle,
    int arrowId,
    double sizeInches,
    Paint linePaint,
  ) {
    final desc = arrowDescriptor(arrowId);
    if (desc == null) return;
    canvas.save();
    canvas.translate(tip.dx, tip.dy);
    canvas.rotate(angle);
    canvas.scale(sizeInches, sizeInches);
    final paint = Paint()
      ..color = linePaint.color
      ..style = desc.filled ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = math.max(linePaint.strokeWidth / sizeInches, 0.05);
    canvas.drawPath(desc.path, paint);
    canvas.restore();
  }

  Paint? _resolveFillPaint(VsdxShape shape) {
    if (!shape.fill.hasFill) return null;
    final color = _colourOrTheme(
            shape.fill.foreground, shape.fill.themeForegroundIndex) ??
        fallbackFill;
    final transparency = shape.fill.foregroundTransparency.clamp(0.0, 1.0);
    final out = color.withValues(alpha: color.a * (1.0 - transparency));
    return Paint()
      ..color = out
      ..style = PaintingStyle.fill;
  }

  Paint? _resolveStrokePaint(VsdxShape shape) {
    if (!shape.line.hasLine) return null;
    final color =
        _colourOrTheme(shape.line.color, shape.line.themeColorIndex) ??
            fallbackStroke;
    final transparency = shape.line.transparency.clamp(0.0, 1.0);
    final out = color.withValues(alpha: color.a * (1.0 - transparency));
    return Paint()
      ..color = out
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(shape.line.weightInches, 1 / pxPerInch)
      ..strokeCap = _flutterCap(shape)
      ..strokeJoin = shape.line.roundingInches > 0
          ? StrokeJoin.round
          : StrokeJoin.miter;
  }

  Color? _colourOrTheme(VsdxColor? raw, int? themeIndex) {
    if (raw != null) return Color(raw.value);
    if (themeIndex == null) return null;
    final c = theme.resolve(themeIndex);
    return c == null ? null : Color(c.value);
  }

  StrokeCap _flutterCap(VsdxShape shape) =>
      switch (shape.line.cap) {
        LineCap.round => StrokeCap.round,
        LineCap.square => StrokeCap.square,
        LineCap.extended => StrokeCap.butt,
      };

  void _paintImage(Canvas canvas, VsdxShape shape, Rect bounds) {
    final src = images.findByPart(shape.imagePartName!);
    if (src == null) {
      _paintPlaceholderBox(canvas, bounds.width, bounds.height);
      return;
    }
    final image = imageCache?.lookup(src);
    if (image == null) {
      _paintImagePlaceholder(canvas, bounds, src);
      return;
    }
    // We're drawing inside an inverted-Y page-local coordinate frame.
    // Flip Y again so the picture appears upright.
    canvas.save();
    canvas.translate(bounds.center.dx, bounds.center.dy);
    canvas.scale(1, -1);
    final dst = Rect.fromCenter(
      center: Offset.zero,
      width: bounds.width,
      height: bounds.height,
    );
    final srcRect = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    canvas.drawImageRect(
      image,
      srcRect,
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
  }

  void _paintImagePlaceholder(Canvas canvas, Rect bounds, VsdxImage src) {
    canvas.drawRect(
      bounds,
      Paint()..color = const Color(0xFFF2F2F2),
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 / pxPerInch
        ..color = const Color(0xFFB0B0B0),
    );
    // Diagonal cross — Visio-style missing-picture cue.
    final cross = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 / pxPerInch
      ..color = const Color(0xFFC0C0C0);
    canvas.drawLine(bounds.topLeft, bounds.bottomRight, cross);
    canvas.drawLine(bounds.topRight, bounds.bottomLeft, cross);

    final label = _foreignPlaceholderLabel(src);
    canvas.save();
    canvas.translate(bounds.center.dx, bounds.center.dy);
    canvas.scale(1, -1);
    final fs = math.min(bounds.width, bounds.height) * 0.18;
    if (fs <= 0) {
      canvas.restore();
      return;
    }
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(color: const Color(0xFF707070), fontSize: fs),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: bounds.width * 0.9);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  String _foreignPlaceholderLabel(VsdxImage src) {
    final m = src.mimeType.toLowerCase();
    final p = src.partName.toLowerCase();
    if (m == 'object/ole' || m.startsWith('object/')) return 'OLE Object';
    if (m.contains('emf') || p.endsWith('.emf')) return 'EMF';
    if (m.contains('wmf') || p.endsWith('.wmf')) return 'WMF';
    if (src.isFlutterDecodable) return 'Image…';
    return 'Image';
  }

  void _paintPlaceholderBox(Canvas canvas, double w, double h) {
    final rect = Rect.fromLTWH(0, 0, w, h);
    canvas.drawRect(rect, Paint()..color = placeholderAccent);
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 / pxPerInch
        ..color = placeholderStroke,
    );
  }

  /// Subtle dashed frame for containers / swimlanes / callouts so they
  /// remain discoverable even when they carry no explicit geometry.
  void _paintKindHint(Canvas canvas, VsdxShape shape, double w, double h) {
    final rect = Rect.fromLTWH(0, 0, w, h);
    final color = switch (shape.shapeKind) {
      VsdxShapeKind.swimlane => const Color(0x664477AA),
      VsdxShapeKind.container => const Color(0x6644AA77),
      VsdxShapeKind.callout => const Color(0x66AA7744),
      VsdxShapeKind.group => const Color(0x33999999),
      _ => const Color(0x33999999),
    };
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1 / pxPerInch, 0.01)
      ..color = color;
    if (shape.shapeKind == VsdxShapeKind.callout) {
      canvas.drawRect(rect, paint);
      return;
    }
    final path = Path()..addRect(rect);
    canvas.drawPath(
      dashedPath(path, const [0.08, 0.06]),
      paint,
    );
  }

  /// Draw.io-style fold chevron in the container header / lane strip.
  void _paintCollapseChevron(Canvas canvas, VsdxShape shape, double w, double h) {
    final local = collapseChevronLocalCenter(shape);
    final r = math.min(0.08, math.min(w, h) * 0.08);
    final fill = Paint()..color = const Color(0xCC333333);
    final cx = local.dx, cy = local.dy;
    final path = Path();
    if (shape.collapsed) {
      // ▶ pointing right
      path
        ..moveTo(cx - r * 0.5, cy - r)
        ..lineTo(cx + r * 0.7, cy)
        ..lineTo(cx - r * 0.5, cy + r)
        ..close();
    } else {
      // ▼ pointing down (in Y-up local space: smaller y is down on screen after
      // the page flip, so we point toward -Y in local inches).
      path
        ..moveTo(cx - r, cy + r * 0.5)
        ..lineTo(cx + r, cy + r * 0.5)
        ..lineTo(cx, cy - r * 0.7)
        ..close();
    }
    canvas.drawPath(path, fill);
  }

  /// Local-inch centre of the collapse chevron for [shape] (origin bottom-left).
  static Offset collapseChevronLocalCenter(VsdxShape shape) {
    final w = shape.width, h = shape.height;
    if (shape.shapeKind == VsdxShapeKind.swimlane) {
      if (SwimlaneOps.isHorizontal(shape)) {
        final strip = w * 0.12;
        return Offset(strip * 0.5, h - math.min(0.22, h * 0.12));
      }
      final band = h * 0.12;
      return Offset(math.min(0.18, w * 0.08), h - band * 0.5);
    }
    // Container / group: top title band.
    final band = h * 0.18;
    return Offset(math.min(0.18, w * 0.08), h - band * 0.5);
  }

  /// Page-inch hit radius for the collapse chevron.
  static double collapseChevronHitRadius(VsdxShape shape) =>
      math.max(0.14, math.min(shape.width, shape.height) * 0.06);

  /// Auto-generated shape names (`Sheet.5`) are internal ids, never content —
  /// unlike Visio's viewer heritage we don't paint them as a label fallback.
  static final RegExp _autoName = RegExp(r'^Sheet\.\d+$');

  void _paintRichText(Canvas canvas, VsdxShape shape, Rect bounds) {
    final rich = shape.richText;
    final hasRich = !rich.isEmpty;
    // Fall back to the shape's own name only for 2-D shapes with a meaningful
    // (non-auto) name — connectors and `Sheet.N` placeholders stay blank.
    String? nameFallback;
    if (!shape.is1D && shape.name.isNotEmpty && !_autoName.hasMatch(shape.name)) {
      nameFallback = shape.name;
    }
    final label =
        hasRich ? null : (shape.text?.isNotEmpty == true ? shape.text! : nameFallback);
    if (!hasRich && (label == null || label.isEmpty)) return;

    // Glueable connectors show their label as an edge label centred on the
    // drawn route's midpoint, not the bounding-box centre (drawio-style).
    // Freehand ink keeps ordinary AABB text placement.
    final isEdgeLabel = shape.isGlueableConnector;

    final block = rich.textBlock;
    // Match Visio / libvisio: HideText suppresses the painted label.
    if (block.hideText) return;
    final s = pxPerInch;
    final tw = block.widthInches ?? shape.width;
    final th = block.heightInches ?? shape.height;

    // Build the text spans. Font sizes are scaled to pixels because Flutter's
    // TextPainter is not transform-aware: at the canvas's inches-scale a 10pt
    // font becomes ~0.14 logical px and the shaper quantises glyph advances to
    // ~0 (garbled / mis-wrapped text). So we shape in pixel space, like the
    // visiovsdxviewer reference.
    final spans = <TextSpan>[];
    if (hasRich) {
      for (final run in rich.runs) {
        spans.add(_runToSpan(run, s));
      }
    } else {
      final fsPx = (isEdgeLabel ? 0.14 : math.min(th, tw) * 0.18) * s;
      spans.add(TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.black87,
          fontSize: fsPx,
          fontWeight: FontWeight.w500,
        ),
      ));
    }
    final align = hasRich
        ? _flutterAlign(rich.runs.first.paraStyle.horizontalAlign)
        : TextAlign.center;

    // Connector edge label with no explicit text pin: centre it on the drawn
    // route midpoint (no text box). Prefer page-space drawn polyline so
    // geometry-less / nested connectors match SVG export.
    if (isEdgeLabel && block.pinXInches == null && block.pinYInches == null) {
      final ctx = _paintTarget ?? page;
      final Offset2D mid;
      if (ctx != null) {
        final route = ctx.drawnConnectorPagePolyline(shape);
        mid = route.length >= 2
            ? _polylineMidpoint(route)
            : VsdxPage.connectorMidpoint(shape);
      } else {
        mid = VsdxPage.connectorMidpoint(shape);
      }
      final local = _pageToLocal(shape, Offset(mid.x, mid.y));
      canvas.save();
      canvas.translate(local.dx, local.dy);
      if (block.angleRad != 0) canvas.rotate(block.angleRad);
      canvas.scale(1 / s, -1 / s);
      final tp = TextPainter(
        text: TextSpan(children: spans),
        textAlign: align,
        textDirection: TextDirection.ltr,
        maxLines: null,
      )..layout();
      final ox = -tp.width / 2;
      final oy = -tp.height / 2;
      if (tp.width > 0) {
        final pad = 0.03 * s;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
                ox - pad, oy - pad, tp.width + pad * 2, tp.height + pad * 2),
            Radius.circular(0.02 * s),
          ),
          Paint()..color = _edgeLabelBackground(),
        );
      }
      tp.paint(canvas, Offset(ox, oy));
      canvas.restore();
      return;
    }

    // Regular text block. Visio places the block's local pin (TxtLocPin) on its
    // pin (TxtPin) and rotates the whole block about that pin by TxtAngle, then
    // flows the text inside the TxtWidth × TxtHeight rectangle. Rotating about
    // the pin — not the block centre — is what keeps a rotated / vertical label
    // anchored at its start instead of sliding its tail onto the start point.
    final pinX = block.pinXInches ?? shape.width / 2;
    final pinY = block.pinYInches ?? shape.height / 2;
    final locPinX = block.locPinXInches ?? tw / 2;
    final locPinY = block.locPinYInches ?? th / 2;

    canvas.save();
    canvas.translate(pinX, pinY); // to TxtPin (shape-local, Y-up)
    if (block.angleRad != 0) canvas.rotate(block.angleRad);
    canvas.translate(-locPinX, -locPinY); // to the block's lower-left corner
    // TextBkgnd — solid fill behind the text block (libvisio fo:background-color).
    if (block.backgroundColor != null) {
      final bg = Color(block.backgroundColor!.value);
      final t = block.backgroundTransparency.clamp(0.0, 1.0);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, tw, th),
        Paint()..color = bg.withValues(alpha: bg.a * (1.0 - t)),
      );
    }
    canvas.translate(0, th); // to the block's upper-left corner (Y still up)
    canvas.scale(1 / s, -1 / s); // → pixel space, Y-down upright text frame

    var twPx = tw * s;
    var thPx = th * s;
    var mlPx = block.marginLeftInches * s;
    var mrPx = block.marginRightInches * s;
    var mtPx = block.marginTopInches * s;
    var mbPx = block.marginBottomInches * s;
    // TextDirection=1 (libvisio vertical): rotate so lines flow top→bottom.
    if (block.textDirection == 1) {
      canvas.translate(twPx / 2, thPx / 2);
      canvas.rotate(-math.pi / 2);
      canvas.translate(-thPx / 2, -twPx / 2);
      final swapW = twPx;
      twPx = thPx;
      thPx = swapW;
      final oldMl = mlPx, oldMr = mrPx, oldMt = mtPx, oldMb = mbPx;
      mlPx = oldMt;
      mrPx = oldMb;
      mtPx = oldMr;
      mbPx = oldMl;
    }
    final maxW = math.max(0.0, twPx - mlPx - mrPx);

    // Curved Text: place glyphs along a quadratic arc inside the text block.
    // Falls back to the rectangular layout when the shape is a 1-D edge label.
    if (shape.curvedText && !isEdgeLabel) {
      _paintCurvedText(
        canvas,
        spans: spans,
        plain: hasRich ? rich.plainText : label!,
        twPx: twPx,
        thPx: thPx,
        mlPx: mlPx,
        mrPx: mrPx,
      );
      canvas.restore();
      return;
    }

    // Paragraph layout when spacing / indents / bullets / multi-line need it.
    // Ordinary single-run labels keep the fast path below.
    final needsParaLayout = hasRich &&
        (rich.runs.any((r) =>
                r.paraStyle.spaceBeforeInches != 0 ||
                r.paraStyle.spaceAfterInches != 0 ||
                r.paraStyle.indentLeftInches != 0 ||
                r.paraStyle.indentFirstInches != 0 ||
                r.paraStyle.indentRightInches != 0 ||
                r.paraStyle.bullet != 0 ||
                r.text.contains('\n')));
    if (needsParaLayout) {
      _paintParagraphBlock(
        canvas,
        runs: rich.runs,
        twPx: twPx,
        thPx: thPx,
        mlPx: mlPx,
        mrPx: mrPx,
        mtPx: mtPx,
        mbPx: mbPx,
        maxW: maxW,
        verticalAlign: block.verticalAlign,
        scale: s,
      );
      canvas.restore();
      return;
    }

    final tp = TextPainter(
      text: TextSpan(children: spans),
      textAlign: align,
      textDirection: TextDirection.ltr,
      maxLines: null,
    )..layout(maxWidth: maxW);

    // Offsets measured from the block's upper-left corner (px).
    final ox = switch (align) {
      TextAlign.center => (twPx - tp.width) / 2,
      TextAlign.right => twPx - mrPx - tp.width,
      _ => mlPx, // left / justify / start
    };
    var oy = switch (block.verticalAlign) {
      VsdxVertAlign.top => mtPx,
      VsdxVertAlign.bottom => thPx - mbPx - tp.height,
      VsdxVertAlign.middle => (thPx - tp.height) / 2,
    };
    // Text taller than the box grows downward from the top (Visio / drawio).
    if (block.verticalAlign == VsdxVertAlign.middle && oy < mtPx) oy = mtPx;

    tp.paint(canvas, Offset(ox, oy));
    canvas.restore();
  }

  /// Lay out rich-text paragraphs with SpBefore/After, IndLeft/First, and
  /// Visio bullets (`Bullet` / `BulletStr` / `TextPosAfterBullet`).
  void _paintParagraphBlock(
    Canvas canvas, {
    required List<VsdxTextRun> runs,
    required double twPx,
    required double thPx,
    required double mlPx,
    required double mrPx,
    required double mtPx,
    required double mbPx,
    required double maxW,
    required VsdxVertAlign verticalAlign,
    required double scale,
  }) {
    final paras = _splitParagraphs(runs);
    final painters = <TextPainter>[];
    final beforePx = <double>[];
    final afterPx = <double>[];
    final textOriginsX = <double>[];
    final bulletPainters = <TextPainter?>[];
    final bulletOriginsX = <double>[];
    var totalH = 0.0;

    for (final para in paras) {
      final style = para.style;
      final pAlign = _flutterAlign(style.horizontalAlign);
      final indentL = style.indentLeftInches * scale;
      final indentF = style.indentFirstInches * scale;
      final indentR = style.indentRightInches * scale;
      final hasBullet = style.bullet != 0;
      final afterBullet = style.textPosAfterBulletInches > 0
          ? style.textPosAfterBulletInches * scale
          : (hasBullet ? 0.18 * scale : 0.0);

      TextPainter? bulletTp;
      var bulletX = mlPx + indentL + indentF;
      var textX = mlPx + indentL;
      if (hasBullet) {
        final glyph = _bulletGlyph(style);
        final fontPx = () {
          if (style.bulletFontSizeInches != null &&
              style.bulletFontSizeInches! > 0) {
            return style.bulletFontSizeInches! * scale;
          }
          // Match the first run's size when available.
          for (final r in para.runs) {
            if (r.text.isNotEmpty) {
              return (r.charStyle.fontSizeInches > 0
                      ? r.charStyle.fontSizeInches
                      : 0.14) *
                  scale;
            }
          }
          return 0.14 * scale;
        }();
        bulletTp = TextPainter(
          text: TextSpan(
            text: glyph,
            style: TextStyle(
              color: Colors.black87,
              fontSize: fontPx,
              fontFamily: style.bulletFont,
              height: 1.0,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        // Hanging indent: bullet sits on the first-line indent; body text
        // starts at IndLeft + TextPosAfterBullet (or a default gap).
        textX = mlPx + indentL + afterBullet;
        if (bulletX > textX - bulletTp.width) {
          bulletX = textX - bulletTp.width - 0.04 * scale;
        }
      } else {
        // Without a bullet, IndFirst shifts the whole paragraph (good enough
        // for single-line shape labels; multi-line first-line-only indent is
        // a follow-up).
        textX = mlPx + indentL + indentF;
      }

      final avail = math.max(
        0.0,
        maxW - (textX - mlPx) - indentR,
      );
      final tp = TextPainter(
        text: TextSpan(
          children: <TextSpan>[
            for (final r in para.runs) _runToSpan(r, scale),
          ],
        ),
        textAlign: pAlign,
        textDirection: TextDirection.ltr,
        maxLines: null,
      )..layout(maxWidth: avail);

      painters.add(tp);
      bulletPainters.add(bulletTp);
      bulletOriginsX.add(bulletX);
      // Horizontal align still applies within the remaining text band.
      final alignedX = switch (pAlign) {
        TextAlign.center => textX + (avail - tp.width) / 2,
        TextAlign.right => textX + avail - tp.width,
        _ => textX,
      };
      textOriginsX.add(alignedX);

      final b = style.spaceBeforeInches * scale;
      final a = style.spaceAfterInches * scale;
      beforePx.add(b);
      afterPx.add(a);
      final rowH = math.max(tp.height, bulletTp?.height ?? 0);
      totalH += b + rowH + a;
    }

    var oy = switch (verticalAlign) {
      VsdxVertAlign.top => mtPx,
      VsdxVertAlign.bottom => thPx - mbPx - totalH,
      VsdxVertAlign.middle => (thPx - totalH) / 2,
    };
    if (verticalAlign == VsdxVertAlign.middle && oy < mtPx) oy = mtPx;

    var y = oy;
    for (var i = 0; i < painters.length; i++) {
      final tp = painters[i];
      final bulletTp = bulletPainters[i];
      y += beforePx[i];
      final rowH = math.max(tp.height, bulletTp?.height ?? 0);
      if (bulletTp != null) {
        final by = y + (rowH - bulletTp.height) / 2;
        bulletTp.paint(canvas, Offset(bulletOriginsX[i], by));
      }
      final ty = y + (rowH - tp.height) / 2;
      tp.paint(canvas, Offset(textOriginsX[i], ty));
      y += rowH + afterPx[i];
    }
  }

  /// Default Visio-style bullet glyph for [VsdxParaStyle.bullet] (1…).
  static String _bulletGlyph(VsdxParaStyle style) {
    final custom = style.bulletStr;
    if (custom != null && custom.isNotEmpty) return custom;
    return switch (style.bullet) {
      2 => '○',
      3 => '■',
      4 => '□',
      5 => '◆',
      6 => '–',
      7 => '✓',
      _ => '•',
    };
  }

  /// Split rich-text runs into paragraphs at `\n` (Visio paragraph breaks).
  List<({List<VsdxTextRun> runs, VsdxParaStyle style})> _splitParagraphs(
    List<VsdxTextRun> runs,
  ) {
    final out = <({List<VsdxTextRun> runs, VsdxParaStyle style})>[];
    var cur = <VsdxTextRun>[];
    var style = VsdxParaStyle.defaults;
    void flush() {
      out.add((runs: cur, style: style));
      cur = <VsdxTextRun>[];
    }

    for (final run in runs) {
      final parts = run.text.split('\n');
      for (var i = 0; i < parts.length; i++) {
        if (i > 0) flush();
        style = run.paraStyle;
        // Keep empty segments so consecutive `\n\n` yield blank paragraphs.
        cur.add(run.copyWith(text: parts[i]));
      }
    }
    if (cur.isNotEmpty || out.isEmpty) flush();
    return out;
  }

  /// Opaque backing colour for an edge label — the page background when set,
  /// otherwise white.
  Color _edgeLabelBackground() {
    final bg = page?.backgroundColor;
    return bg == null ? const Color(0xFFFFFFFF) : Color(bg.value);
  }

  /// Build a [TextSpan] for [run]. [scale] converts the run's inch-based sizes
  /// to the pixel units the caller lays the text out in (see [_paintRichText] —
  /// text must be shaped at real pixel sizes, not the canvas's inches-scale, or
  /// glyph advances quantise to zero and wrapping breaks).
  TextSpan _runToSpan(VsdxTextRun run, double scale) {
    final base = _colourOrTheme(run.charStyle.color, run.charStyle.themeColorIndex) ??
        Colors.black87;
    final alpha = (1 - run.charStyle.transparency).clamp(0.0, 1.0);
    final c = base.withValues(alpha: base.a * alpha);
    final pos = run.charStyle.position;
    final baseSize = math.max(run.charStyle.fontSizeInches, 0.04) * scale;
    final scaledSize =
        pos == VsdxTextPosition.normal ? baseSize : baseSize * 0.65;
    // Flutter's TextStyle.height is a multiple of the font size and must be
    // positive — a non-positive value collapses the line advance so wrapped
    // lines overlap or stack upward (the bug this guards against). Visio's
    // absolute line spacing (SpLine > 0, inches) is converted to a multiple
    // via the run's pixel font size; the relative multiple (SpLine < 0) is
    // applied directly. Anything non-finite/≤0 falls back to the font's
    // natural line height.
    final para = run.paraStyle;
    double? lineHeight;
    if (para.lineSpacingAbsoluteInches > 0 && scaledSize > 0) {
      lineHeight = para.lineSpacingAbsoluteInches * scale / scaledSize;
    } else if (para.lineSpacing > 0) {
      lineHeight = para.lineSpacing;
    }
    if (lineHeight != null && (!lineHeight.isFinite || lineHeight <= 0)) {
      lineHeight = null;
    }
    final features = <ui.FontFeature>[
      if (pos == VsdxTextPosition.superscript)
        const ui.FontFeature.enable('sups'),
      if (pos == VsdxTextPosition.subscript)
        const ui.FontFeature.enable('subs'),
      if (run.charStyle.style.smallCaps) const ui.FontFeature.enable('smcp'),
    ];
    final font = fontFallback.resolve(
      run.charStyle.fontFamily,
      asianFont: run.charStyle.asianFont,
    );
    final rawText = switch (run.charStyle.textCase) {
      VsdxTextCase.allCaps => run.text.toUpperCase(),
      VsdxTextCase.initialCaps => _initialCaps(run.text),
      VsdxTextCase.normal => run.text,
    };
    final widthScale = run.charStyle.fontScale <= 0 ? 1.0 : run.charStyle.fontScale;
    return TextSpan(
      text: rawText,
      style: TextStyle(
        color: c,
        fontFamily: font.family,
        fontFamilyFallback:
            font.familyFallback.isEmpty ? null : font.familyFallback,
        fontSize: scaledSize,
        fontStyle: run.charStyle.style.italic ? FontStyle.italic : FontStyle.normal,
        fontWeight:
            run.charStyle.style.bold ? FontWeight.bold : FontWeight.normal,
        decoration: TextDecoration.combine([
          if (run.charStyle.underline || run.charStyle.doubleUnderline)
            TextDecoration.underline,
          if (run.charStyle.strikethrough || run.charStyle.doubleStrikethrough)
            TextDecoration.lineThrough,
          if (run.charStyle.overline) TextDecoration.overline,
        ]),
        decorationStyle: run.charStyle.doubleUnderline ||
                run.charStyle.doubleStrikethrough
            ? TextDecorationStyle.double
            : TextDecorationStyle.solid,
        letterSpacing: () {
          final base = run.charStyle.letterSpacingInches == 0
              ? 0.0
              : run.charStyle.letterSpacingInches * scale;
          // Approximate FontScale as extra tracking (true glyph width scale
          // isn't available on TextStyle without a transform).
          if ((widthScale - 1.0).abs() < 1e-6) {
            return base == 0 ? null : base;
          }
          return base + scaledSize * (widthScale - 1.0) * 0.15;
        }(),
        height: lineHeight,
        fontFeatures: features.isEmpty ? null : features,
      ),
    );
  }

  /// Place [plain] glyphs along a quadratic arc bowing upward inside the text
  /// block (draw.io Curved Text). Uses the style from the first [spans] entry.
  void _paintCurvedText(
    Canvas canvas, {
    required List<TextSpan> spans,
    required String plain,
    required double twPx,
    required double thPx,
    required double mlPx,
    required double mrPx,
  }) {
    final text = plain.replaceAll('\n', ' ').trim();
    if (text.isEmpty) return;

    final availW = math.max(0.0, twPx - mlPx - mrPx);
    if (availW <= 1) return;

    final baseStyle = spans.isNotEmpty && spans.first.style != null
        ? spans.first.style!
        : const TextStyle(color: Colors.black87, fontSize: 14);

    // Measure each character for arc-length placement.
    final chars = <String>[];
    final widths = <double>[];
    var totalW = 0.0;
    for (final r in text.runes) {
      final ch = String.fromCharCode(r);
      final tp = TextPainter(
        text: TextSpan(text: ch, style: baseStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      chars.add(ch);
      widths.add(tp.width);
      totalW += tp.width;
    }
    if (totalW <= 0) return;

    // Quadratic arc: left → right along the text block, bowing upward (Y-down).
    final midY = thPx * 0.58;
    final bulge = math.min(thPx * 0.32, thPx * 0.45);
    final p0 = Offset(mlPx, midY);
    final p2 = Offset(twPx - mrPx, midY);
    final p1 = Offset(twPx / 2, midY - bulge);

    // Approximate arc length via polyline samples.
    const samples = 48;
    final pts = <Offset>[];
    final cum = <double>[0.0];
    Offset prev = p0;
    pts.add(p0);
    for (var i = 1; i <= samples; i++) {
      final t = i / samples;
      final o = _quadBezierPoint(p0, p1, p2, t);
      pts.add(o);
      cum.add(cum.last + (o - prev).distance);
      prev = o;
    }
    final arcLen = cum.last;
    if (arcLen <= 0) return;

    // Centre the string along the arc when shorter than the arc.
    final pad = math.max(0.0, (arcLen - totalW) / 2);
    var cursor = pad;
    for (var i = 0; i < chars.length; i++) {
      final w = widths[i];
      final centerDist = cursor + w / 2;
      final t = _arcTForDistance(cum, centerDist.clamp(0.0, arcLen));
      final pos = _quadBezierPoint(p0, p1, p2, t);
      final tangent = _quadBezierTangent(p0, p1, p2, t);
      final angle = math.atan2(tangent.dy, tangent.dx);

      final tp = TextPainter(
        text: TextSpan(text: chars[i], style: baseStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();

      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(angle);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height * 0.75));
      canvas.restore();

      cursor += w;
    }
  }

  static Offset _quadBezierPoint(Offset p0, Offset p1, Offset p2, double t) {
    final u = 1 - t;
    return Offset(
      u * u * p0.dx + 2 * u * t * p1.dx + t * t * p2.dx,
      u * u * p0.dy + 2 * u * t * p1.dy + t * t * p2.dy,
    );
  }

  static Offset _quadBezierTangent(Offset p0, Offset p1, Offset p2, double t) {
    // B'(t) = 2(1-t)(P1-P0) + 2t(P2-P1)
    final d = Offset(
      2 * (1 - t) * (p1.dx - p0.dx) + 2 * t * (p2.dx - p1.dx),
      2 * (1 - t) * (p1.dy - p0.dy) + 2 * t * (p2.dy - p1.dy),
    );
    final len = d.distance;
    if (len < 1e-9) return const Offset(1, 0);
    return Offset(d.dx / len, d.dy / len);
  }

  /// Map a distance along the sampled polyline [cum] to a Bezier [t] in 0..1.
  static double _arcTForDistance(List<double> cum, double dist) {
    final n = cum.length - 1;
    if (n <= 0) return 0;
    if (dist <= 0) return 0;
    if (dist >= cum.last) return 1;
    var lo = 0;
    var hi = n;
    while (lo + 1 < hi) {
      final mid = (lo + hi) >> 1;
      if (cum[mid] <= dist) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final seg = cum[hi] - cum[lo];
    final local = seg <= 1e-12 ? 0.0 : (dist - cum[lo]) / seg;
    return (lo + local) / n;
  }

  TextAlign _flutterAlign(VsdxHorzAlign a) => switch (a) {
        VsdxHorzAlign.left => TextAlign.left,
        VsdxHorzAlign.center => TextAlign.center,
        VsdxHorzAlign.right => TextAlign.right,
        VsdxHorzAlign.justify => TextAlign.justify,
      };

  /// Visio `Case=2` (initial caps) — uppercase the first letter of each word.
  static String _initialCaps(String text) {
    final buf = StringBuffer();
    var start = true;
    for (final r in text.runes) {
      final ch = String.fromCharCode(r);
      if (ch == ' ' || ch == '\n' || ch == '\t') {
        buf.write(ch);
        start = true;
      } else if (start) {
        buf.write(ch.toUpperCase());
        start = false;
      } else {
        buf.write(ch);
      }
    }
    return buf.toString();
  }

  void _drawPlaceholderText(Canvas canvas, Size size, String text) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
            color: Colors.black54, fontSize: 14, height: 1.4),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width - 32);
    tp.paint(
      canvas,
      Offset(
        (size.width - tp.width) / 2,
        (size.height - tp.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant VsdxPainter old) =>
      old.page != page ||
      old.underlayPage != underlayPage ||
      old.theme != theme ||
      old.images != images ||
      old.imageCache != imageCache ||
      old.patternBuilder != patternBuilder ||
      old.pxPerInch != pxPerInch ||
      old.backgroundColor != backgroundColor ||
      old.placeholderAccent != placeholderAccent ||
      old.placeholderStroke != placeholderStroke ||
      old.fallbackFill != fallbackFill ||
      old.fallbackStroke != fallbackStroke ||
      old.respectLayerVisibility != respectLayerVisibility ||
      old.visibleLayerIdsOverride != visibleLayerIdsOverride ||
      old.underlayVisibleLayerIdsOverride != underlayVisibleLayerIdsOverride ||
      old.fontFallback != fontFallback ||
      old.drawLineJumps != drawLineJumps ||
      old.lineJumpRadiusInches != lineJumpRadiusInches;
}

class _LineEndpoints {
  const _LineEndpoints(
    this.start,
    this.end, {
    Offset? beginTangent,
    Offset? endTangent,
  })  : beginTangent = beginTangent ?? end,
        endTangent = endTangent ?? start;
  final Offset start;
  final Offset end;

  /// Adjacent vertex used to compute the begin-arrow tangent (so arrows
  /// align with the last leg of an orthogonal route, not the chord).
  final Offset beginTangent;
  final Offset endTangent;
}

double pageWidthPx(VsdxPage p, {double dpi = 96}) =>
    inchesToPx(p.widthInches, dpi: dpi);
double pageHeightPx(VsdxPage p, {double dpi = 96}) =>
    inchesToPx(p.heightInches, dpi: dpi);
