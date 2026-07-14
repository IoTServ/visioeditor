/// Page-level [CustomPainter] for the Visio viewer.
///
/// As of M3+M6-snapshot the painter:
///  * Draws real shape geometry when available (`VsdxShape.geometries`
///    non-empty), falling back to a bounding-box placeholder otherwise.
///  * Honours [VsdxFill] / [VsdxLine] (incl. gradients, dashes, themes).
///  * Applies drop-shadow effects when the shape has `Shadow*` cells.
///  * Decorates 1-D shapes' line endings with [arrowDescriptor] heads.
///  * Filters shapes by Layer visibility.
///  * Renders rich text via the per-run [VsdxCharStyle] / [VsdxParaStyle].
library;

import 'dart:math' as math;
import 'dart:ui' as ui show FontFeature, Gradient;

import 'package:flutter/material.dart';

import 'package:vsdx/vsdx.dart';
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
    this.router = const ConnectorRouter(),
    this.fontFallback = VsdxFontFallback.defaults,
    this.noPageLoadedMessage = 'No page loaded',
    this.noShapesOnPageMessage = 'No shapes parsed yet',
    this.drawLineJumps = true,
    this.lineJumpRadiusInches = 0.07,
  }) : super(repaint: imageCache);

  final VsdxPage? page;
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
  final Set<int>? visibleLayerIdsOverride;

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

    if (p.shapes.isEmpty) {
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

    final visibleLayers = respectLayerVisibility
        ? (visibleLayerIdsOverride ?? p.visibleLayerIds)
        : null;
    final bboxes = _bboxesFor(p);
    // Viewport in page-inch coords. The painter is currently scaled so
    // that 1 unit = 1 inch; the visible inch-rect equals the entire page
    // (we're inside a SizedBox of the page's pixel dimensions). When the
    // caller embeds the painter inside an InteractiveViewer the parent
    // already clips, so we still draw the full page — but the bbox check
    // remains cheap when many shapes overlap.
    final viewportInches = Rect.fromLTWH(0, 0, p.widthInches, p.heightInches);

    if (drawLineJumps) {
      _computeConnectorRoutes(p);
    } else {
      _connRoutesPage = const <List<Offset>>[];
      _connZ = const <int, int>{};
    }

    for (final shape in p.shapes) {
      _paintShape(canvas, shape, visibleLayers, bboxes, viewportInches);
    }
    canvas.restore();
  }

  Map<int, Rect> _bboxesFor(VsdxPage p) {
    final cached = _bboxCache[p];
    if (cached != null) return cached;
    final out = bounds.buildShapeBounds(p);
    _bboxCache[p] = out;
    return out;
  }

  /// Cache every top-level connector's page-space polyline (z-ordered) so a
  /// connector can hop over the ones drawn beneath it (line jumps).
  void _computeConnectorRoutes(VsdxPage p) {
    final routes = <List<Offset>>[];
    final z = <int, int>{};
    for (final s in p.shapes) {
      if (!s.is1D || !s.hasGeometry) continue;
      final pts = _connectorPagePolyline(s);
      if (pts.length < 2) continue;
      z[s.id] = routes.length;
      routes.add(pts);
    }
    _connRoutesPage = routes;
    _connZ = z;
  }

  /// The connector [s]'s drawn polyline in page inches (its first pure
  /// MoveTo/LineTo geometry, mapped through the shape's XForm), or empty.
  List<Offset> _connectorPagePolyline(VsdxShape s) {
    for (final g in s.geometries) {
      if (g.noShow) continue;
      final local = _polylineLocalPoints(g);
      if (local.length >= 2) {
        return <Offset>[for (final pt in local) _localToPageOffset(s, pt)];
      }
    }
    return const <Offset>[];
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
    final localPinX = w / 2;
    final localPinY = h / 2;

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
    } else if (shape.is1D) {
      _paint1DFallback(canvas, shape);
    } else if (shape.children.isEmpty) {
      // Pure container groups have no own geometry — don't paint a
      // placeholder rectangle that would obscure their children.
      _paintPlaceholderBox(canvas, w, h);
    }

    if (shape.shapeKind.isStructural || shape.shapeKind.isAnnotative) {
      _paintKindHint(canvas, shape, w, h);
    }

    _paintLineEndings(canvas, shape);
    _paintRichText(canvas, shape, Rect.fromLTWH(0, 0, w, h));

    // Children inherit the parent's local frame: their PinX/PinY are
    // interpreted in the (0..parentWidth, 0..parentHeight) box, so we paint
    // them BEFORE restoring the canvas. (M4-06.)
    for (final child in shape.children) {
      _paintShape(canvas, child, visibleLayers, bboxes, viewport);
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
      );
      _drawShadow(canvas, shape, path);
      _drawGlow(canvas, shape, path);
      _drawReflection(canvas, shape, path);
      if (!geom.noFill && shape.fill.hasFill) {
        _drawFill(canvas, shape, path);
      }
      if (!geom.noLine && shape.line.hasLine) {
        final strokePaint = _resolveStrokePaint(shape);
        if (strokePaint != null) {
          var strokeSrc = path;
          if (shape.is1D && drawLineJumps) {
            final jumped = _lineJumpsPath(shape, geom);
            if (jumped != null) strokeSrc = jumped;
          }
          final strokeP =
              dashes == null ? strokeSrc : dashedPath(strokeSrc, dashes);
          canvas.drawPath(strokeP, strokePaint);
        }
      }
    }
  }

  /// Stroke path for connector [shape]'s polyline [geom] with a small arc over
  /// every crossing with a lower-z connector (line jumps), or `null` when it
  /// crosses nothing (draw the plain path).
  Path? _lineJumpsPath(VsdxShape shape, VsdxGeometry geom) {
    final k = _connZ[shape.id];
    if (k == null || k == 0) return null; // nothing drawn beneath it
    final route = _polylineLocalPoints(geom);
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
    final routed = router.route(shape, page: page);
    if (routed == null) return;

    final path = Path();
    final pts = routed.points.toList(growable: false);
    for (var i = 0; i < pts.length; i++) {
      final local = _pageToLocal(shape, pts[i]);
      if (i == 0) {
        path.moveTo(local.dx, local.dy);
      } else {
        path.lineTo(local.dx, local.dy);
      }
    }
    final dashes = dashPatternFor(shape.line.pattern);
    canvas.drawPath(dashes == null ? path : dashedPath(path, dashes), stroke);
  }

  /// Inverse of the XForm we apply in [_paintShape], i.e. map a page-inch
  /// point back into the shape's local frame
  /// (`(0..width) × (0..height)`).
  ///
  /// Forward transform: `T(pinX,pinY) · R(angleRad) · S(±1,±1) · T(-w/2,-h/2)`.
  /// Inverse:           `T(w/2,h/2) · S(±1,±1) · R(-angleRad) · T(-pinX,-pinY)`.
  Offset _pageToLocal(VsdxShape shape, Offset pagePoint) {
    var x = pagePoint.dx - shape.pinX;
    var y = pagePoint.dy - shape.pinY;
    if (shape.angleRad != 0) {
      final c = math.cos(-shape.angleRad);
      final s = math.sin(-shape.angleRad);
      final nx = c * x - s * y;
      final ny = s * x + c * y;
      x = nx;
      y = ny;
    }
    if (shape.flipX) x = -x;
    if (shape.flipY) y = -y;
    return Offset(x + shape.width / 2, y + shape.height / 2);
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
      final fg = _colourOrTheme(
              fill.foreground, fill.themeForegroundIndex) ??
          fallbackFill;
      final hatch = patternBuilder.paintFor(
        fill.pattern,
        foreground: fg,
      );
      if (hatch != null) {
        // Draw background colour first (the hatch tiles are mostly
        // transparent) — Visio's bkgnd cell fills the gaps.
        final bg = _colourOrTheme(
            fill.background, fill.themeBackgroundIndex);
        if (bg != null) {
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

  void _drawShadow(Canvas canvas, VsdxShape shape, Path path) {
    final shadow = shape.shadow;
    if (!shadow.enabled) return;
    final base = _colourOrTheme(shadow.color, shadow.themeColorIndex) ??
        const Color(0x99000000);
    final alpha = (1 - shadow.transparency).clamp(0.0, 1.0);
    if (alpha <= 0) return;
    final paint = Paint()
      ..color = base.withValues(alpha: base.a * alpha)
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        math.max(shadow.blurInches, 0.001),
      );
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
    final paint = _resolveStrokePaint(shape) ?? Paint()
      ..style = PaintingStyle.stroke
      ..color = fallbackStroke;

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
    // Prefer the routed connector — gives the correct tangent at the tip
    // even when the route bends.
    if (shape.is1D && shape.beginX != null && shape.endX != null) {
      final routed = router.route(shape, page: page);
      if (routed != null) {
        final pts = routed.points
            .map((p) => _pageToLocal(shape, p))
            .toList(growable: false);
        if (pts.length >= 2) {
          final tipBegin = pts.first;
          final tipEnd = pts.last;
          // Tangent direction at each tip — based on the *adjacent* segment
          // so the arrow head stays parallel to the last leg of the path.
          final beginNeighbour = pts[1];
          final endNeighbour = pts[pts.length - 2];
          return _LineEndpoints(
            tipBegin,
            tipEnd,
            beginTangent: beginNeighbour,
            endTangent: endNeighbour,
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

      for (final cmd in geom.commands) {
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
          case ArcTo(:final x, :final y):
            if (!penDown) {
              addVertex(cursor);
              penDown = true;
            }
            addVertex(Offset(x, y));
          case CubBezTo(:final x, :final y):
            if (!penDown) {
              addVertex(cursor);
              penDown = true;
            }
            addVertex(Offset(x, y));
          case RelCubBezTo(:final fx, :final fy):
            if (!penDown) {
              addVertex(cursor);
              penDown = true;
            }
            addVertex(Offset(fx * w, fy * h));
          case QuadBezTo(:final x, :final y):
            if (!penDown) {
              addVertex(cursor);
              penDown = true;
            }
            addVertex(Offset(x, y));
          case RelQuadBezTo(:final fx, :final fy):
            if (!penDown) {
              addVertex(cursor);
              penDown = true;
            }
            addVertex(Offset(fx * w, fy * h));
          case EllipticalArcTo(:final x, :final y):
            if (!penDown) {
              addVertex(cursor);
              penDown = true;
            }
            addVertex(Offset(x, y));
          case RelEllipticalArcTo(:final fx, :final fy):
            if (!penDown) {
              addVertex(cursor);
              penDown = true;
            }
            addVertex(Offset(fx * w, fy * h));
          case final PolylineTo poly:
            if (!penDown) {
              addVertex(cursor);
              penDown = true;
            }
            for (final v in poly.vertices) {
              addVertex(Offset(v.x, v.y));
            }
            addVertex(Offset(poly.x, poly.y));
          case SplineStart(:final x, :final y):
            if (!penDown) {
              addVertex(cursor);
              penDown = true;
            }
            addVertex(Offset(x, y));
          case SplineKnot(:final x, :final y):
            if (!penDown) {
              addVertex(cursor);
              penDown = true;
            }
            addVertex(Offset(x, y));
          case NurbsTo(:final x, :final y):
            if (!penDown) {
              addVertex(cursor);
              penDown = true;
            }
            addVertex(Offset(x, y));
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
      ..strokeCap = _flutterCap(shape);
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
    final label = src.isFlutterDecodable ? 'Image…' : 'Image (EMF/WMF)';
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

    // Connectors (1-D) show their label as an edge label centred on the drawn
    // route's midpoint, not the bounding-box centre (drawio-style).
    final isEdgeLabel = shape.is1D;

    final block = rich.textBlock;
    final tw = block.widthInches ?? shape.width;
    final th = block.heightInches ?? shape.height;
    var tpx = block.pinXInches ?? shape.width / 2;
    var tpy = block.pinYInches ?? shape.height / 2;
    if (isEdgeLabel && block.pinXInches == null && block.pinYInches == null) {
      final mid = VsdxPage.connectorMidpoint(shape);
      final local = _pageToLocal(shape, Offset(mid.x, mid.y));
      tpx = local.dx;
      tpy = local.dy;
    }

    canvas.save();
    canvas.translate(tpx, tpy);
    if (block.angleRad != 0) canvas.rotate(block.angleRad);
    canvas.scale(1, -1);

    final spans = <TextSpan>[];
    if (hasRich) {
      for (final run in rich.runs) {
        spans.add(_runToSpan(run));
      }
    } else {
      final fs = isEdgeLabel ? 0.14 : math.min(th, tw) * 0.18;
      spans.add(TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.black87,
          fontSize: fs,
          fontWeight: FontWeight.w500,
        ),
      ));
    }

    final align = hasRich
        ? _flutterAlign(rich.runs.first.paraStyle.horizontalAlign)
        : TextAlign.center;

    // Lay out within the block's content area (inside the margins). The
    // canvas origin is already the text-block centre, so dx/dy are relative
    // to that anchor. Edge labels aren't clipped to a box, so they lay out at
    // their natural width and centre on the route midpoint.
    final innerWidth = isEdgeLabel
        ? double.infinity
        : math.max(0.0, tw - block.marginLeftInches - block.marginRightInches);
    final tp = TextPainter(
      text: TextSpan(children: spans),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: innerWidth);

    final dx = isEdgeLabel
        ? -tp.width / 2
        : switch (align) {
            TextAlign.center => -tp.width / 2,
            TextAlign.right => tw / 2 - tp.width - block.marginRightInches,
            // left / justify / start / end
            _ => -tw / 2 + block.marginLeftInches,
          };
    final dy = isEdgeLabel
        ? -tp.height / 2
        : switch (block.verticalAlign) {
            VsdxVertAlign.top => -th / 2 + block.marginTopInches,
            VsdxVertAlign.bottom =>
              th / 2 - tp.height - block.marginBottomInches,
            VsdxVertAlign.middle => -tp.height / 2,
          };

    // Edge labels sit on top of the connector line, so back them with the
    // page colour for legibility (drawio does the same).
    if (isEdgeLabel && tp.width > 0) {
      const pad = 0.03;
      final halo = Rect.fromLTWH(
        dx - pad,
        dy - pad,
        tp.width + pad * 2,
        tp.height + pad * 2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(halo, const Radius.circular(0.02)),
        Paint()..color = _edgeLabelBackground(),
      );
    }
    tp.paint(canvas, Offset(dx, dy));
    canvas.restore();
  }

  /// Opaque backing colour for an edge label — the page background when set,
  /// otherwise white.
  Color _edgeLabelBackground() {
    final bg = page?.backgroundColor;
    return bg == null ? const Color(0xFFFFFFFF) : Color(bg.value);
  }

  TextSpan _runToSpan(VsdxTextRun run) {
    final base = _colourOrTheme(run.charStyle.color, run.charStyle.themeColorIndex) ??
        Colors.black87;
    final alpha = (1 - run.charStyle.transparency).clamp(0.0, 1.0);
    final c = base.withValues(alpha: base.a * alpha);
    final pos = run.charStyle.position;
    final baseSize = math.max(run.charStyle.fontSizeInches, 0.04);
    final scaledSize =
        pos == VsdxTextPosition.normal ? baseSize : baseSize * 0.65;
    final features = <ui.FontFeature>[
      if (pos == VsdxTextPosition.superscript)
        const ui.FontFeature.enable('sups'),
      if (pos == VsdxTextPosition.subscript)
        const ui.FontFeature.enable('subs'),
    ];
    final font = fontFallback.resolve(run.charStyle.fontFamily);
    return TextSpan(
      text: run.text,
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
          if (run.charStyle.underline) TextDecoration.underline,
          if (run.charStyle.strikethrough) TextDecoration.lineThrough,
        ]),
        letterSpacing: run.charStyle.letterSpacingInches == 0
            ? null
            : run.charStyle.letterSpacingInches,
        height: run.paraStyle.lineSpacing,
        fontFeatures: features.isEmpty ? null : features,
      ),
    );
  }

  TextAlign _flutterAlign(VsdxHorzAlign a) => switch (a) {
        VsdxHorzAlign.left => TextAlign.left,
        VsdxHorzAlign.center => TextAlign.center,
        VsdxHorzAlign.right => TextAlign.right,
        VsdxHorzAlign.justify => TextAlign.justify,
      };

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
      old.fontFallback != fontFallback;
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
