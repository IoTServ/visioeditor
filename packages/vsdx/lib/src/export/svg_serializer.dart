/// Pure-Dart `.vsdx` → SVG serializer (M7-01).
///
/// The serializer is intentionally Flutter-free so it can run on the
/// command line, in a server, or inside a Dart isolate. The output is a
/// self-contained `<svg>` document per page (or one merged document) — no
/// JavaScript, no external font references, just inline geometry and text.
///
/// Coordinate system: SVG's Y axis points *down*, just like Flutter's.
/// Visio's Y axis points up, so we apply a top-of-page flip per page.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../model/document.dart';
import '../model/effects.dart';
import '../model/elliptical_arc.dart';
import '../model/fill.dart';
import '../model/geometry.dart';
import '../model/image.dart';
import '../model/line.dart';
import '../model/nurbs.dart';
import '../model/page.dart';
import '../model/spline.dart';
import '../model/rich_text.dart';
import '../model/rounding.dart';
import '../model/shape.dart';
import '../model/table.dart';
import '../model/theme.dart';
import '../parser/metafile.dart';
import '../parser/metafile_drawing.dart';
import '../utils/color.dart';
import 'line_jumps.dart';

/// Which layer flags the SVG serializer honours when filtering shapes.
enum SvgLayerFilter {
  /// Honour `Visible` (on-screen / interactive export).
  visible,

  /// Honour `Print` (PDF / print export).
  print,

  /// Draw every layer membership (no filter).
  all,
}

class VsdxToSvgSerializer {
  VsdxToSvgSerializer({
    this.pxPerInch = 96.0,
    this.includeXmlHeader = true,
    this.embedImages = true,
    this.layerFilter = SvgLayerFilter.visible,
    this.skipBackgroundPages = true,
  });

  final double pxPerInch;
  final bool includeXmlHeader;

  /// When `true` (default) the serializer emits `<image>` tags with
  /// `data:` URIs for every supported raster. Set to `false` to skip
  /// images entirely (e.g. for diff-friendly outputs).
  final bool embedImages;

  /// Layer visibility vs print filtering. Defaults to [SvgLayerFilter.visible].
  final SvgLayerFilter layerFilter;

  /// When serialising a whole document, omit pages marked `Background="1"`
  /// (they are composited via [VsdxDocument.backgroundFor] instead).
  final bool skipBackgroundPages;

  /// Current image registry, swapped in by [serializePage] / [serializeDocument].
  ImageRegistry _images = ImageRegistry.empty;

  /// Line-jump state for the page currently being serialised.
  bool _jumpsEnabled = false;
  List<List<Offset2D>> _jumpRoutes = const <List<Offset2D>>[];
  Map<int, int> _jumpZ = const <int, int>{};

  /// Serialize the entire document into a single multi-page SVG with each
  /// page wrapped in a `<g class="page-N">` translated downward. Use
  /// [serializePage] when only one page is needed.
  String serializeDocument(VsdxDocument doc) {
    _images = doc.images;
    final pages = <VsdxPage>[
      for (final p in doc.pages)
        if (!skipBackgroundPages || !p.isBackgroundPage) p,
    ];
    final exportPages = pages.isEmpty ? doc.pages : pages;
    final buf = StringBuffer();
    if (includeXmlHeader) buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    final totalH = exportPages.fold<double>(
      0,
      (acc, p) => acc + p.heightInches * pxPerInch + 24,
    );
    final maxW = exportPages.fold<double>(
      0,
      (acc, p) => math.max(acc, p.widthInches * pxPerInch),
    );
    buf.writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" '
      'version="1.1" '
      'width="${_n(maxW)}" '
      'height="${_n(totalH)}" '
      'viewBox="0 0 ${_n(maxW)} ${_n(totalH)}">',
    );
    buf.writeln('  <title>${_esc(doc.title ?? 'Visio document')}</title>');
    var offsetY = 0.0;
    for (var i = 0; i < exportPages.length; i++) {
      final p = exportPages[i];
      buf.writeln(
          '  <g class="page page-${i + 1}" transform="translate(0,${_n(offsetY)})">');
      _writePageBody(
        buf,
        p,
        doc.theme,
        underlayPage: doc.backgroundFor(p),
        indent: '    ',
      );
      buf.writeln('  </g>');
      offsetY += p.heightInches * pxPerInch + 24;
    }
    buf.writeln('</svg>');
    return buf.toString();
  }

  /// Serialize a single page.
  String serializePage(
    VsdxPage page, {
    VsdxTheme theme = VsdxTheme.empty,
    ImageRegistry images = ImageRegistry.empty,
    VsdxPage? underlayPage,
  }) {
    _images = images;
    final buf = StringBuffer();
    if (includeXmlHeader) buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    final w = page.widthInches * pxPerInch;
    final h = page.heightInches * pxPerInch;
    buf.writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" '
      'version="1.1" '
      'width="${_n(w)}" '
      'height="${_n(h)}" '
      'viewBox="0 0 ${_n(w)} ${_n(h)}">',
    );
    _writePageBody(
      buf,
      page,
      theme,
      underlayPage: underlayPage,
      indent: '  ',
    );
    buf.writeln('</svg>');
    return buf.toString();
  }

  void _writePageBody(
    StringBuffer buf,
    VsdxPage page,
    VsdxTheme theme, {
    VsdxPage? underlayPage,
    required String indent,
  }) {
    final h = page.heightInches * pxPerInch;
    final w = page.widthInches * pxPerInch;
    final bg = page.backgroundColor;
    final fill = bg == null ? '#ffffff' : _hex(bg);
    // page background
    buf.writeln('$indent<rect x="0" y="0" '
        'width="${_n(w)}" '
        'height="${_n(h)}" fill="$fill"/>');
    // Arrow markers are emitted per-path so BeginArrowSize / EndArrowSize
    // can scale markerWidth (shared fixed markers ignored size).
    // Visio→SVG: translate(0, height) then scale(px, -px)
    buf.writeln(
      '$indent<g transform="translate(0 ${_n(h)}) '
      'scale(${_n(pxPerInch)} ${_n(-pxPerInch)})">',
    );
    final underlay = underlayPage;
    if (underlay != null && underlay.shapes.isNotEmpty) {
      // Jump state is per painted page — prepare underlay routes before drawing
      // so bare shape ids do not collide with the foreground sheet.
      _prepareLineJumps(underlay);
      final clipId = 'underlay-clip-${page.id}';
      buf.writeln('$indent  <g class="underlay">');
      // Clip to the foreground page box (page inches, Y-up after transform).
      buf.writeln(
        '$indent    <clipPath id="$clipId">'
        '<rect x="0" y="0" width="${_n(page.widthInches)}" '
        'height="${_n(page.heightInches)}"/>'
        '</clipPath>',
      );
      buf.writeln('$indent    <g clip-path="url(#$clipId)">');
      final underLayers = _layerIds(underlay);
      // Scope underlay paint ids by foreground page so a shared BackPage
      // composited into multiple sheets does not collide SVG defs.
      final underPaintScope = 'p${page.id}-u${underlay.id}';
      for (final shape in underlay.shapes) {
        _writeShape(
          buf,
          shape,
          theme,
          underlay,
          underLayers,
          paintIdScope: underPaintScope,
          indent: '$indent      ',
        );
      }
      buf.writeln('$indent    </g>');
      buf.writeln('$indent  </g>');
    }
    _prepareLineJumps(page);
    final layers = _layerIds(page);
    final paintScope = 'p${page.id}';
    for (final shape in page.shapes) {
      _writeShape(
        buf,
        shape,
        theme,
        page,
        layers,
        paintIdScope: paintScope,
        indent: '$indent  ',
      );
    }
    buf.writeln('$indent</g>');
  }

  Set<int>? _layerIds(VsdxPage page) {
    if (page.layers.isEmpty || layerFilter == SvgLayerFilter.all) return null;
    return layerFilter == SvgLayerFilter.print
        ? page.printableLayerIds
        : page.visibleLayerIds;
  }

  void _prepareLineJumps(VsdxPage page) {
    _jumpsEnabled = lineJumpsEnabledForCode(page.pageSheet.lineJumpCode);
    if (!_jumpsEnabled) {
      _jumpRoutes = const <List<Offset2D>>[];
      _jumpZ = const <int, int>{};
      return;
    }
    final routes = <List<Offset2D>>[];
    final z = <int, int>{};
    void walk(List<VsdxShape> list) {
      for (final s in list) {
        if (s.isGlueableConnector) {
          final route = page.drawnConnectorPagePolyline(s);
          if (route.length >= 2) {
            z[s.id] = routes.length;
            routes.add(route);
          }
        }
        if (!s.collapsed) walk(s.children);
      }
    }

    walk(page.shapes);
    _jumpRoutes = routes;
    _jumpZ = z;
  }

  /// Shape-local stroke `d` with line jumps when this 1-D shape crosses
  /// connectors drawn beneath it. Returns `null` when jumps do not apply so
  /// authored / curved geometry from [_geometryToD] is kept.
  String? _connectorJumpD(VsdxPage page, VsdxShape shape) {
    if (!_jumpsEnabled || !shape.isGlueableConnector) return null;
    final z = _jumpZ[shape.id];
    if (z == null || z == 0) return null;
    final pageRoute = _jumpRoutes[z];
    final localRoute = <Offset2D>[
      for (final p in pageRoute) page.pageToLocalDeep(shape.id, p),
    ];
    if (localRoute.length < 2) return null;
    final unders = <List<Offset2D>>[
      for (var i = 0; i < z; i++)
        <Offset2D>[
          for (final p in _jumpRoutes[i]) page.pageToLocalDeep(shape.id, p),
        ],
    ];
    if (polylineCrossings(localRoute, unders).isEmpty) return null;
    return polylineWithJumpsSvg(
      localRoute,
      unders,
      kDefaultLineJumpRadiusInches,
      format: _n,
    );
  }

  void _writeShape(
    StringBuffer buf,
    VsdxShape shape,
    VsdxTheme theme,
    VsdxPage page,
    Set<int>? visibleLayers, {
    required String paintIdScope,
    required String indent,
  }) {
    if (visibleLayers != null &&
        page.layers.isNotEmpty &&
        shape.layerMemberIds.isNotEmpty &&
        !shape.isOnAnyLayer(visibleLayers)) {
      return;
    }
    final transforms = <String>[];
    transforms.add('translate(${_n(shape.pinX)} ${_n(shape.pinY)})');
    if (shape.angleRad != 0) {
      transforms.add('rotate(${_n(shape.angleRad * 180 / math.pi)})');
    }
    if (shape.flipX || shape.flipY) {
      transforms.add(
        'scale(${shape.flipX ? -1 : 1} ${shape.flipY ? -1 : 1})',
      );
    }
    transforms.add(
      'translate(${_n(-shape.effectiveLocPinX)} '
      '${_n(-shape.effectiveLocPinY)})',
    );
    final link = _svgHyperlinkAttrs(shape);
    if (link != null) {
      buf.writeln('$indent<a $link>');
    }
    buf.writeln('$indent<g transform="${transforms.join(' ')}">');

    if (shape.hasImage) {
      _writeImage(buf, shape, indent: '$indent  ');
    } else {
      var wroteGeom = false;
      var geomIndex = 0;
      final jumpD = _connectorJumpD(page, shape);
      for (final geom in shape.geometries) {
        if (geom.noShow) continue;
        var d = _geometryToD(
          geom,
          shape.width,
          shape.height,
          roundingInches: shape.line.roundingInches,
        );
        if (d.isEmpty) continue;
        // Prefer jump-aware stroke for 1-D connectors (first stroked geom).
        if (jumpD != null && !geom.noLine) {
          d = jumpD;
        }
        wroteGeom = true;
        _writePath(
          buf,
          shape,
          theme,
          d: d,
          noFill: geom.noFill,
          noLine: geom.noLine,
          // paintIdScope is page- (and underlay-) scoped so multi-page SVG
          // and shared BackPage composites do not collide defs ids.
          paintId: '$paintIdScope-${shape.id}-$geomIndex',
          indent: '$indent  ',
        );
        geomIndex++;
        if (jumpD != null && !geom.noLine) break;
      }
      // Canvas paints geometry-less 1-D connectors via orthogonal routing
      // (perimeter glue + ObstacleRouter). Match that for SVG/PDF export.
      if (!wroteGeom &&
          shape.isGlueableConnector &&
          shape.beginX != null &&
          shape.beginY != null &&
          shape.endX != null &&
          shape.endY != null) {
        final d = jumpD ?? () {
          final route = page.autoRoutedConnectorPolyline(shape);
          if (route.length < 2) return '';
          final buf = StringBuffer();
          for (var i = 0; i < route.length; i++) {
            final local = page.pageToLocalDeep(shape.id, route[i]);
            buf.write(i == 0
                ? 'M ${_n(local.x)} ${_n(local.y)}'
                : ' L ${_n(local.x)} ${_n(local.y)}');
          }
          return buf.toString();
        }();
        if (d.isNotEmpty) {
          _writePath(
            buf,
            shape,
            theme,
            d: d,
            noFill: true,
            noLine: false,
            paintId: '$paintIdScope-${shape.id}-0',
            indent: '$indent  ',
          );
        }
      }
    }

    // Match canvas name-fallback: 2-D shapes with a meaningful (non Sheet.N)
    // name paint that label when richText/text are empty.
    final hasLabel = !shape.richText.isEmpty ||
        (shape.text?.isNotEmpty ?? false) ||
        _meaningfulNameLabel(shape) != null;
    if (hasLabel) {
      _writeText(buf, shape, theme, page, indent: '$indent  ');
    }

    // Match canvas: collapsed hosts hide children; covered table cells skip.
    if (!shape.collapsed) {
      for (final child in shape.children) {
        if (TableOps.isCovered(child)) continue;
        _writeShape(
          buf,
          child,
          theme,
          page,
          visibleLayers,
          paintIdScope: paintIdScope,
          indent: '$indent  ',
        );
      }
    }
    buf.writeln('$indent</g>');
    if (link != null) {
      buf.writeln('$indent</a>');
    }
  }

  /// SVG `<a>` attribute string for [shape]'s primary hyperlink, or `null`.
  String? _svgHyperlinkAttrs(VsdxShape shape) {
    final h = shape.primaryHyperlink;
    if (h == null || h.invisible) return null;
    final target = h.effectiveTarget?.trim();
    if (target == null || target.isEmpty) return null;
    final attrs = StringBuffer('href="${_esc(target)}"');
    if (h.newWindow || h.frame == '_blank') {
      attrs.write(' target="_blank"');
    } else if (h.frame != null && h.frame!.trim().isNotEmpty) {
      attrs.write(' target="${_esc(h.frame!.trim())}"');
    }
    final desc = h.description?.trim();
    if (desc != null && desc.isNotEmpty) {
      attrs.write(' title="${_esc(desc)}"');
    }
    return attrs.toString();
  }

  void _writePath(
    StringBuffer buf,
    VsdxShape shape,
    VsdxTheme theme, {
    required String d,
    required bool noFill,
    required bool noLine,
    required String paintId,
    required String indent,
  }) {
    final defs = StringBuffer();
    final fillAttr = !noFill
        ? _fillAttr(shape.fill, theme, paintId, defs)
        : 'fill="none"';
    final strokeAttr = !noLine
        ? _strokeAttr(shape.line, theme, paintId, defs)
        : 'stroke="none"';
    final filterAttr = _effectsFilterAttr(shape, theme, paintId, defs);
    if (defs.isNotEmpty) {
      buf.writeln('$indent<defs>$defs</defs>');
    }
    _writeReflection(buf, shape, theme, d: d, noFill: noFill, paintId: paintId, indent: indent);
    // Soft outer glow (canvas strokes a blurred path before fill).
    final glow = shape.glow;
    if (glow.enabled && glow.sizeInches > 0) {
      final gc = _resolveColor(glow.color, glow.themeColorIndex, theme) ??
          const VsdxColor(0xFF3399FF);
      final ga = _combinedOpacity(gc, glow.transparency);
      if (ga > 0) {
        final gid = 'glow-$paintId';
        buf.writeln(
          '$indent<defs><filter id="$gid" x="-50%" y="-50%" '
          'width="200%" height="200%">'
          '<feGaussianBlur stdDeviation="${_n(glow.sizeInches)}" '
          'result="blur"/>'
          '<feFlood flood-color="${_hex(gc)}" flood-opacity="${_n(ga)}" '
          'result="color"/>'
          '<feComposite in="color" in2="blur" operator="in" result="glow"/>'
          '<feMerge><feMergeNode in="glow"/></feMerge>'
          '</filter></defs>',
        );
        buf.writeln(
          '$indent<path d="$d" fill="none" stroke="${_hex(gc)}" '
          'stroke-width="${_n(math.max(glow.sizeInches * 2, 0.02))}" '
          'stroke-opacity="${_n(ga)}" filter="url(#$gid)"/>',
        );
      }
    }
    final filter = filterAttr == null ? '' : ' filter="$filterAttr"';
    final compound = !noLine && shape.line.compoundType > 0;
    if (compound) {
      // Match canvas BlendMode.clear double-rail: mask punches a transparent
      // gap so fill / page background shows through (not a hard-coded white).
      final weight =
          shape.line.weightInches > 0 ? shape.line.weightInches : 0.01;
      final gap = weight * 0.38;
      final mid = 'cmp-$paintId';
      buf.writeln(
        '$indent<defs><mask id="$mid" maskUnits="userSpaceOnUse">'
        '<path d="$d" fill="none" stroke="white" '
        'stroke-width="${_n(weight)}" stroke-linecap="round" '
        'stroke-linejoin="round"/>'
        '<path d="$d" fill="none" stroke="black" '
        'stroke-width="${_n(gap)}" stroke-linecap="round" '
        'stroke-linejoin="round"/>'
        '</mask></defs>',
      );
      if (!noFill && fillAttr != 'fill="none"') {
        buf.writeln('$indent<path d="$d" $fillAttr stroke="none"$filter/>');
      }
      buf.writeln(
        '$indent<path d="$d" fill="none" $strokeAttr '
        'mask="url(#$mid)"$filter/>',
      );
    } else {
      buf.writeln('$indent<path d="$d" $fillAttr $strokeAttr$filter/>');
    }
  }

  void _writeReflection(
    StringBuffer buf,
    VsdxShape shape,
    VsdxTheme theme, {
    required String d,
    required bool noFill,
    required String paintId,
    required String indent,
  }) {
    final refl = shape.reflection;
    if (!refl.enabled || refl.sizeInches <= 0 || noFill) return;
    if (!shape.fill.hasFill) return;
    final alpha = (1 - refl.transparency).clamp(0.0, 1.0);
    if (alpha <= 0) return;
    // Approximate canvas reflection: mirror below the shape box, clipped by
    // ReflectionSize, optional blur. Uses shape height as bounds proxy.
    final h = shape.height.abs() < 1e-9 ? 1.0 : shape.height.abs();
    final clipH = h * refl.sizeInches.clamp(0.01, 1.0);
    final dist = refl.distanceInches;
    final fid = 'refl-$paintId';
    final cid = 'refl-clip-$paintId';
    final c = _resolveColor(
            shape.fill.foreground, shape.fill.themeForegroundIndex, theme) ??
        const VsdxColor(0xFF888888);
    final a =
        _combinedOpacity(c, shape.fill.foregroundTransparency) * alpha;
    buf.writeln(
      '$indent<defs>'
      '<clipPath id="$cid">'
      '<rect x="${_n(-shape.width)}" y="${_n(-dist - clipH)}" '
      'width="${_n(shape.width * 3)}" height="${_n(clipH + refl.blurInches)}"/>'
      '</clipPath>'
      '${refl.blurInches > 0 ? '<filter id="$fid" x="-20%" y="-20%" '
          'width="140%" height="140%">'
          '<feGaussianBlur stdDeviation="${_n(math.max(refl.blurInches, 0.001))}"/>'
          '</filter>' : ''}'
      '</defs>',
    );
    final filter = refl.blurInches > 0 ? ' filter="url(#$fid)"' : '';
    buf.writeln(
      '$indent<g clip-path="url(#$cid)" '
      'transform="translate(0 ${_n(-dist)}) scale(1 -1)">'
      '<path d="$d" fill="${_hex(c)}" fill-opacity="${_n(a)}" '
      'stroke="none"$filter/>'
      '</g>',
    );
  }

  /// Page-inch → shape-local (inverse of the XForm written in [_writeShape]).
  Offset2D _pageToLocal(VsdxShape shape, double pageX, double pageY) {
    var x = pageX - shape.pinX;
    var y = pageY - shape.pinY;
    if (shape.angleRad != 0) {
      final cosA = math.cos(-shape.angleRad);
      final sinA = math.sin(-shape.angleRad);
      final rx = x * cosA - y * sinA;
      final ry = x * sinA + y * cosA;
      x = rx;
      y = ry;
    }
    if (shape.flipX) x = -x;
    if (shape.flipY) y = -y;
    return Offset2D(x + shape.effectiveLocPinX, y + shape.effectiveLocPinY);
  }

  String? _effectsFilterAttr(
    VsdxShape shape,
    VsdxTheme theme,
    String paintId,
    StringBuffer defs,
  ) {
    final shadow = shape.shadow;
    final soft =
        (!shape.is1D && shape.line.softEdgesInches > 0) ? shape.line.softEdgesInches : 0.0;
    final shadowOn = shadow.enabled;
    if (!shadowOn && soft <= 0) return null;

    final id = 'fx-$paintId';
    final parts = StringBuffer();
    if (shadowOn) {
      final base = _resolveColor(shadow.color, shadow.themeColorIndex, theme) ??
          const VsdxColor(0x99000000);
      final alpha = _combinedOpacity(base, shadow.transparency);
      if (alpha > 0) {
        // User space is Visio Y-up (after the page scale), so +offsetY is up.
        parts.write(
          '<feDropShadow dx="${_n(shadow.offsetXInches)}" '
          'dy="${_n(shadow.offsetYInches)}" '
          'stdDeviation="${_n(math.max(shadow.blurInches, 0.001))}" '
          'flood-color="${_hex(base)}" flood-opacity="${_n(alpha)}" '
          'result="shadow"/>',
        );
      }
    }
    if (soft > 0) {
      parts.write(
        '<feGaussianBlur in="SourceGraphic" '
        'stdDeviation="${_n(soft)}" result="soft"/>',
      );
    }
    if (parts.isEmpty) return null;
    // Merge shadow (if any) under the (possibly softened) graphic.
    if (shadowOn && soft > 0) {
      parts.write(
        '<feMerge>'
        '<feMergeNode in="shadow"/>'
        '<feMergeNode in="soft"/>'
        '</feMerge>',
      );
    } else if (shadowOn) {
      parts.write(
        '<feMerge>'
        '<feMergeNode in="shadow"/>'
        '<feMergeNode in="SourceGraphic"/>'
        '</feMerge>',
      );
    }
    defs.write(
      '<filter id="$id" x="-50%" y="-50%" width="200%" height="200%">'
      '$parts</filter>',
    );
    return 'url(#$id)';
  }

  String _geometryToD(
    VsdxGeometry g,
    double w,
    double h, {
    double roundingInches = 0,
  }) {
    if (roundingInches > 1e-12) {
      final poly = _polylineVertices(g, w, h);
      if (poly != null && poly.points.length >= 3) {
        final filleted = filletPolyline(
          poly.points,
          roundingInches,
          closed: poly.closed,
        );
        if (filleted.isNotEmpty) {
          final out = StringBuffer('M ${_n(filleted.first.x)} ${_n(filleted.first.y)} ');
          for (var i = 1; i < filleted.length; i++) {
            out.write('L ${_n(filleted[i].x)} ${_n(filleted[i].y)} ');
          }
          if (poly.closed) out.write('Z');
          return out.toString().trim();
        }
      }
    }

    final out = StringBuffer();
    double cx = 0, cy = 0;
    var started = false;
    void m(double x, double y) {
      out.write('M ${_n(x)} ${_n(y)} ');
      cx = x;
      cy = y;
      started = true;
    }

    void l(double x, double y) {
      if (!started) m(0, 0);
      out.write('L ${_n(x)} ${_n(y)} ');
      cx = x;
      cy = y;
    }

    final cmds = g.commands;
    for (var i = 0; i < cmds.length; i++) {
      final cmd = cmds[i];
      switch (cmd) {
        case MoveTo(:final x, :final y):
          m(x, y);
        case RelMoveTo(:final fx, :final fy):
          m(fx * w, fy * h);
        case LineTo(:final x, :final y):
          l(x, y);
        case RelLineTo(:final fx, :final fy):
          l(fx * w, fy * h);
        case CubBezTo(
            :final x,
            :final y,
            :final x1,
            :final y1,
            :final x2,
            :final y2,
          ):
          if (!started) m(0, 0);
          out.write('C ${_n(x1)} ${_n(y1)} ${_n(x2)} ${_n(y2)} '
              '${_n(x)} ${_n(y)} ');
          cx = x;
          cy = y;
        case RelCubBezTo(
            :final fx,
            :final fy,
            :final fx1,
            :final fy1,
            :final fx2,
            :final fy2,
          ):
          if (!started) m(0, 0);
          out.write('C ${_n(fx1 * w)} ${_n(fy1 * h)} '
              '${_n(fx2 * w)} ${_n(fy2 * h)} ${_n(fx * w)} ${_n(fy * h)} ');
          cx = fx * w;
          cy = fy * h;
        case QuadBezTo(:final x, :final y, :final x1, :final y1):
          if (!started) m(0, 0);
          out.write('Q ${_n(x1)} ${_n(y1)} ${_n(x)} ${_n(y)} ');
          cx = x;
          cy = y;
        case RelQuadBezTo(:final fx, :final fy, :final fx1, :final fy1):
          if (!started) m(0, 0);
          out.write('Q ${_n(fx1 * w)} ${_n(fy1 * h)} '
              '${_n(fx * w)} ${_n(fy * h)} ');
          cx = fx * w;
          cy = fy * h;
        case ArcTo(:final x, :final y, :final bow):
          if (!started) m(0, 0);
          if (bow == 0) {
            l(x, y);
          } else {
            final dx = x - cx;
            final dy = y - cy;
            final chord = math.sqrt(dx * dx + dy * dy);
            final r = (chord * chord + 4 * bow * bow) / (8 * bow.abs());
            final large = (4 * bow.abs() > chord) ? 1 : 0;
            final sweep = bow < 0 ? 1 : 0;
            out.write(
                'A ${_n(r)} ${_n(r)} 0 $large $sweep ${_n(x)} ${_n(y)} ');
            cx = x;
            cy = y;
          }
        case RelArcTo(:final fx, :final fy, :final fbow):
          if (!started) m(0, 0);
          final x = fx * w;
          final y = fy * h;
          final bow = fbow * (w + h) / 2;
          if (bow == 0) {
            l(x, y);
          } else {
            final dx = x - cx;
            final dy = y - cy;
            final chord = math.sqrt(dx * dx + dy * dy);
            final r = (chord * chord + 4 * bow * bow) / (8 * bow.abs());
            final large = (4 * bow.abs() > chord) ? 1 : 0;
            final sweep = bow < 0 ? 1 : 0;
            out.write(
                'A ${_n(r)} ${_n(r)} 0 $large $sweep ${_n(x)} ${_n(y)} ');
            cx = x;
            cy = y;
          }
        case EllipticalArcTo(
            :final x,
            :final y,
            :final controlX,
            :final controlY,
            :final angle,
            :final eccentricity,
          ):
          final samples = sampleEllipticalArc(
            start: Offset2D(cx, cy),
            end: Offset2D(x, y),
            control: Offset2D(controlX, controlY),
            angle: angle,
            eccentricity: eccentricity,
          );
          for (final p in samples) {
            l(p.x, p.y);
          }
        case RelEllipticalArcTo(
            :final fx,
            :final fy,
            :final fcx,
            :final fcy,
            :final angle,
            :final eccentricity,
          ):
          final ex = fx * w;
          final ey = fy * h;
          final samples = sampleEllipticalArc(
            start: Offset2D(cx, cy),
            end: Offset2D(ex, ey),
            control: Offset2D(fcx * w, fcy * h),
            angle: angle,
            eccentricity: eccentricity,
          );
          for (final p in samples) {
            l(p.x, p.y);
          }
        case EllipseCmd(
            :final cx,
            :final cy,
            :final aX,
            :final aY,
            :final bX,
            :final bY,
          ):
          final ax = aX - cx, ay = aY - cy;
          final bx = bX - cx, by = bY - cy;
          final rx = math.sqrt(ax * ax + ay * ay);
          final ry = math.sqrt(bx * bx + by * by);
          if (rx > 0 && ry > 0) {
            if (ay.abs() < 1e-9 && bx.abs() < 1e-9) {
              // Keep path cursor / started in sync with other commands.
              m(cx - rx, cy);
              out
                ..write('a ${_n(rx)} ${_n(ry)} 0 1 0 ${_n(rx * 2)} 0 ')
                ..write('a ${_n(rx)} ${_n(ry)} 0 1 0 ${_n(-rx * 2)} 0 ');
            } else {
              // Rotated ellipse: dense polyline.
              const steps = 64;
              for (var i = 0; i <= steps; i++) {
                final t = 2 * math.pi * i / steps;
                final cosT = math.cos(t), sinT = math.sin(t);
                final x = cx + ax * cosT + bx * sinT;
                final y = cy + ay * cosT + by * sinT;
                if (i == 0) {
                  m(x, y);
                } else {
                  l(x, y);
                }
              }
            }
          }
        case PolylineTo(
            :final x,
            :final y,
            :final vertices,
            :final relative,
            :final vertsRelative,
            :final vertsYRelative,
          ):
          final vsx = vertsRelative ? w : 1.0;
          final vsy = vertsYRelative ? h : 1.0;
          final esx = relative ? w : 1.0;
          final esy = relative ? h : 1.0;
          for (final v in vertices) {
            l(v.x * vsx, v.y * vsy);
          }
          l(x * esx, y * esy);
        case InfiniteLineCmd(:final x, :final y, :final a, :final b, :final relative):
          final sx = relative ? w : 1.0;
          final sy = relative ? h : 1.0;
          final px = x * sx, py = y * sy, qx = a * sx, qy = b * sy;
          final dx = qx - px;
          final dy = qy - py;
          final len = math.sqrt(dx * dx + dy * dy);
          if (len == 0) continue;
          final ux = dx / len, uy = dy / len;
          final reach = 100 * math.sqrt(w * w + h * h);
          m(px - ux * reach, py - uy * reach);
          l(px + ux * reach, py + uy * reach);
        case SplineStart():
          if (!started) m(0, 0);
          final spline = consumeSplineSequence(
            cmds,
            i,
            pen: Offset2D(cx, cy),
            width: w,
            height: h,
          );
          for (final p in spline.samples) {
            l(p.x, p.y);
          }
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
          final csx = cpRelative ? w : 1.0;
          final csy = cpYRelative ? h : 1.0;
          final esx = relative ? w : 1.0;
          final esy = relative ? h : 1.0;
          final samples = sampleNurbs(
            start: Offset2D(cx, cy),
            end: Offset2D(x * esx, y * esy),
            controlPoints: <Offset2D>[
              for (final p in controlPoints) Offset2D(p.x * csx, p.y * csy),
            ],
            weights: weights,
            knots: knots,
            degree: degree,
          );
          for (final p in samples) {
            l(p.x, p.y);
          }
      }
    }
    return out.toString().trim();
  }

  /// Pure Move/Line polyline vertices, or `null` when curves / multi-contour.
  ({List<Offset2D> points, bool closed})? _polylineVertices(
    VsdxGeometry geometry,
    double w,
    double h,
  ) {
    final pts = <Offset2D>[];
    var started = false;
    for (final cmd in geometry.commands) {
      switch (cmd) {
        case MoveTo(:final x, :final y):
          if (started && pts.isNotEmpty) return null;
          pts
            ..clear()
            ..add(Offset2D(x, y));
          started = true;
        case RelMoveTo(:final fx, :final fy):
          if (started && pts.isNotEmpty) return null;
          pts
            ..clear()
            ..add(Offset2D(fx * w, fy * h));
          started = true;
        case LineTo(:final x, :final y):
          if (!started) {
            pts.add(const Offset2D(0, 0));
            started = true;
          }
          pts.add(Offset2D(x, y));
        case RelLineTo(:final fx, :final fy):
          if (!started) {
            pts.add(const Offset2D(0, 0));
            started = true;
          }
          pts.add(Offset2D(fx * w, fy * h));
        case PolylineTo(
            :final x,
            :final y,
            :final vertices,
            :final relative,
            :final vertsRelative,
            :final vertsYRelative,
          ):
          // Align with path_builder / VsdxGeometry.polylineVertices so
          // Line.Rounding fillets PolylineTo outlines in SVG/PDF too.
          final vsx = vertsRelative ? w : 1.0;
          final vsy = vertsYRelative ? h : 1.0;
          final esx = relative ? w : 1.0;
          final esy = relative ? h : 1.0;
          if (!started) {
            pts.add(const Offset2D(0, 0));
            started = true;
          }
          for (final v in vertices) {
            pts.add(Offset2D(v.x * vsx, v.y * vsy));
          }
          pts.add(Offset2D(x * esx, y * esy));
        default:
          return null;
      }
    }
    if (pts.length < 2) return null;
    var closed = false;
    if (pts.length >= 3) {
      final a = pts.first, b = pts.last;
      if ((a.x - b.x).abs() < 1e-9 && (a.y - b.y).abs() < 1e-9) {
        closed = true;
        pts.removeLast();
      } else if (polylineLooksClosed(pts, noFill: geometry.noFill)) {
        closed = true;
      }
    }
    return (points: pts, closed: closed);
  }

  String _fillAttr(
    VsdxFill fill,
    VsdxTheme theme,
    String paintId,
    StringBuffer defs,
  ) {
    if (!fill.hasFill) return 'fill="none"';

    if (fill.hasGradient) {
      final g = fill.gradient!;
      final id = 'grad-$paintId';
      final stops = StringBuffer();
      for (final s in g.stops) {
        final c = _resolveColor(s.color, s.themeColorIndex, theme) ??
            const VsdxColor(0xFFFFFFFF);
        final op = _combinedOpacity(c, s.transparency);
        stops.write(
          '<stop offset="${_n(s.position.clamp(0.0, 1.0))}" '
          'stop-color="${_hex(c)}" stop-opacity="${_n(op)}"/>',
        );
      }
      // Match canvas: linear along angle; radial/rect/path → radial.
      if (g.type == VsdxGradientType.linear) {
        final dx = math.cos(g.angleRad);
        final dy = math.sin(g.angleRad);
        defs.write(
          '<linearGradient id="$id" gradientUnits="objectBoundingBox" '
          'x1="${_n(0.5 - dx * 0.5)}" y1="${_n(0.5 - dy * 0.5)}" '
          'x2="${_n(0.5 + dx * 0.5)}" y2="${_n(0.5 + dy * 0.5)}">'
          '$stops</linearGradient>',
        );
      } else {
        defs.write(
          '<radialGradient id="$id" gradientUnits="objectBoundingBox" '
          'cx="0.5" cy="0.5" r="0.6">$stops</radialGradient>',
        );
      }
      return 'fill="url(#$id)"';
    }

    final fg = _resolveColor(fill.foreground, fill.themeForegroundIndex, theme);
    final fgAlpha = _combinedOpacity(fg, fill.foregroundTransparency);
    final fgHex = fg == null ? '#ffffff' : _hex(fg);

    if (fill.pattern > 1) {
      final bg =
          _resolveColor(fill.background, fill.themeBackgroundIndex, theme);
      final bgAlpha =
          bg == null ? 0.0 : _combinedOpacity(bg, fill.backgroundTransparency);
      final bgHex = bg == null ? '#ffffff' : _hex(bg);
      final id = 'pat-$paintId';
      const tile = 0.12;
      defs.write(
        '<pattern id="$id" patternUnits="userSpaceOnUse" '
        'width="${_n(tile)}" height="${_n(tile)}">'
        '<rect width="${_n(tile)}" height="${_n(tile)}" '
        'fill="$bgHex" fill-opacity="${_n(bgAlpha)}"/>'
        '${_hatchPath(fill.pattern, tile, color: fgHex, opacity: fgAlpha)}'
        '</pattern>',
      );
      return 'fill="url(#$id)"';
    }

    return 'fill="$fgHex" fill-opacity="${_n(fgAlpha)}"';
  }

  /// SVG hatch tile approximating Visio FillPattern 2–16 (matches canvas
  /// [PatternFillBuilder] coverage).
  String _hatchPath(
    int pattern,
    double tile, {
    String color = '#000000',
    double opacity = 1,
  }) {
    final sw = tile * 0.08;
    final common =
        'stroke="$color" stroke-opacity="${_n(opacity)}" stroke-width="${_n(sw)}" '
        'fill="none"';
    final fillDot =
        'fill="$color" fill-opacity="${_n(opacity)}" stroke="none"';
    final t = _n(tile);
    final h = _n(tile / 2);
    final q = _n(tile / 4);
    final t34 = _n(tile * 0.75);
    return switch (pattern) {
      2 => '<line x1="0" y1="$h" x2="$t" y2="$h" $common/>',
      3 => '<line x1="$h" y1="0" x2="$h" y2="$t" $common/>',
      5 => '<line x1="0" y1="0" x2="$t" y2="$t" $common/>',
      6 => '<line x1="0" y1="$t" x2="$t" y2="0" $common/>'
          '<line x1="0" y1="0" x2="$t" y2="$t" $common/>',
      7 => '<line x1="0" y1="$h" x2="$t" y2="$h" $common/>'
          '<line x1="$h" y1="0" x2="$h" y2="$t" $common/>',
      8 => // dots
        '<circle cx="$q" cy="$q" r="${_n(tile * 0.08)}" $fillDot/>'
        '<circle cx="$t34" cy="$t34" r="${_n(tile * 0.08)}" $fillDot/>',
      9 => // dense dots
        () {
          final b = StringBuffer();
          for (var y = tile * 0.15; y < tile; y += tile * 0.25) {
            for (var x = tile * 0.15; x < tile; x += tile * 0.25) {
              b.write(
                '<circle cx="${_n(x)}" cy="${_n(y)}" '
                'r="${_n(tile * 0.05)}" $fillDot/>',
              );
            }
          }
          return b.toString();
        }(),
      10 => // brick
        '<line x1="0" y1="$h" x2="$t" y2="$h" $common/>'
        '<line x1="$h" y1="0" x2="$h" y2="$h" $common/>'
        '<line x1="0" y1="$h" x2="0" y2="$t" $common/>',
      11 => // shingles
        '<line x1="0" y1="0" x2="$h" y2="$h" $common/>'
        '<line x1="$h" y1="$h" x2="$t" y2="0" $common/>'
        '<line x1="0" y1="$h" x2="$t" y2="$h" $common/>',
      12 => // wide diagonal forward
        '<line x1="0" y1="$t" x2="$t" y2="0" $common/>'
        '<line x1="${_n(-tile * 0.25)}" y1="${_n(tile * 0.75)}" '
        'x2="${_n(tile * 0.75)}" y2="${_n(-tile * 0.25)}" $common/>',
      13 => // wide diagonal back
        '<line x1="0" y1="0" x2="$t" y2="$t" $common/>'
        '<line x1="${_n(-tile * 0.25)}" y1="${_n(tile * 0.25)}" '
        'x2="${_n(tile * 0.75)}" y2="${_n(tile * 1.25)}" $common/>',
      14 => // grid
        () {
          final b = StringBuffer();
          for (var i = 0.0; i <= tile + 1e-9; i += tile / 4) {
            final v = _n(i);
            b.write('<line x1="$v" y1="0" x2="$v" y2="$t" $common/>');
            b.write('<line x1="0" y1="$v" x2="$t" y2="$v" $common/>');
          }
          return b.toString();
        }(),
      15 => // wave horizontal
        '<path d="M 0 $h Q $q ${_n(tile * 0.25)} $h $h '
        'Q $t34 ${_n(tile * 0.75)} $t $h" $common/>',
      16 => // trellis
        '<line x1="0" y1="0" x2="$t" y2="$t" $common/>'
        '<line x1="$t" y1="0" x2="0" y2="$t" $common/>'
        '<line x1="0" y1="$h" x2="$t" y2="$h" $common/>'
        '<line x1="$h" y1="0" x2="$h" y2="$t" $common/>',
      _ => // 4 and unknowns: forward diagonal
        '<line x1="0" y1="$t" x2="$t" y2="0" $common/>',
    };
  }

  String _strokeAttr(
    VsdxLine line,
    VsdxTheme theme,
    String paintId,
    StringBuffer defs,
  ) {
    if (!line.hasLine) return 'stroke="none"';
    final c = _resolveColor(line.color, line.themeColorIndex, theme);
    final alpha = _combinedOpacity(c, line.transparency);
    final hex = c == null ? '#000000' : _hex(c);
    final dash = _dashAttr(line.pattern);
    // Match canvas [_flutterCap]: Visio LineCap → SVG stroke-linecap.
    final linecap = switch (line.cap) {
      LineCap.round => 'round',
      LineCap.square => 'square',
      LineCap.extended => 'butt',
    };
    // NB: no `fill` here — the caller always emits a `fill` attribute (a colour
    // or `fill="none"`) alongside this, so repeating it would produce an
    // invalid element with a duplicate `fill` attribute.
    //
    // The stroke width is in inches (Visio's internal unit) and is deliberately
    // left to scale with the page transform (`scale(px,-px)`), so a 0.01" line
    // renders as ~1px. We must NOT use `vector-effect="non-scaling-stroke"`
    // here: that would treat 0.01 as viewport pixels, collapsing stroke-only
    // shapes (connectors) to an invisible hairline.
    final weight = line.weightInches > 0 ? line.weightInches : 0.01;
    // Visio Rounding fillets corners; when we cannot rewrite the path, round
    // joins approximate the soft elbow look (canvas uses filletPolyline).
    final linejoin = line.roundingInches > 0 ? 'round' : 'miter';
    final markers = StringBuffer();
    if (line.hasBeginArrow) {
      final mid = 'arrow-start-$paintId';
      final mw = _arrowMarkerSize(line.beginArrowSizeInches);
      final body = _arrowMarkerBody(line.beginArrow, tipAtEnd: false);
      defs.write(
        '<marker id="$mid" viewBox="0 0 10 10" refX="0" refY="5" '
        'markerWidth="${_n(mw)}" markerHeight="${_n(mw)}" orient="auto">'
        '$body</marker>',
      );
      markers.write(' marker-start="url(#$mid)"');
    }
    if (line.hasEndArrow) {
      final mid = 'arrow-end-$paintId';
      final mw = _arrowMarkerSize(line.endArrowSizeInches);
      final body = _arrowMarkerBody(line.endArrow, tipAtEnd: true);
      defs.write(
        '<marker id="$mid" viewBox="0 0 10 10" refX="10" refY="5" '
        'markerWidth="${_n(mw)}" markerHeight="${_n(mw)}" '
        'orient="auto-start-reverse">'
        '$body</marker>',
      );
      markers.write(' marker-end="url(#$mid)"');
    }
    // Keep LineColorTrans as stroke-opacity even for gradients (canvas multiplies
    // line.transparency onto the stroke paint before applying the shader).
    var strokePaint = 'stroke="$hex" stroke-opacity="${_n(alpha)}"';
    if (line.hasGradient) {
      final g = line.gradient!;
      final id = 'lg-$paintId';
      final stops = StringBuffer();
      for (final s in g.stops) {
        final sc = _resolveColor(s.color, s.themeColorIndex, theme) ??
            const VsdxColor(0xFF000000);
        final op = _combinedOpacity(sc, s.transparency);
        stops.write(
          '<stop offset="${_n(s.position.clamp(0.0, 1.0))}" '
          'stop-color="${_hex(sc)}" stop-opacity="${_n(op)}"/>',
        );
      }
      final dx = math.cos(g.angleRad);
      final dy = math.sin(g.angleRad);
      defs.write(
        '<linearGradient id="$id" gradientUnits="objectBoundingBox" '
        'x1="${_n(0.5 - dx * 0.5)}" y1="${_n(0.5 - dy * 0.5)}" '
        'x2="${_n(0.5 + dx * 0.5)}" y2="${_n(0.5 + dy * 0.5)}">'
        '$stops</linearGradient>',
      );
      strokePaint = 'stroke="url(#$id)" stroke-opacity="${_n(alpha)}"';
    }
    return '$strokePaint '
        'stroke-width="${_n(weight)}" stroke-linecap="$linecap" '
        'stroke-linejoin="$linejoin"'
        '${dash.isEmpty ? '' : ' stroke-dasharray="$dash"'}'
        '$markers';
  }

  /// SVG marker path for common Visio BeginArrow/EndArrow ids (subset of
  /// canvas [arrow_library]). Tip points to the end (right) when [tipAtEnd].
  String _arrowMarkerBody(int arrowId, {required bool tipAtEnd}) {
    // Work in tip-at-right space, then mirror for start markers.
    final (d, filled) = switch (arrowId) {
      1 || 3 || 6 || 26 => ('M 0 1 L 10 5 L 0 9', false), // open triangle
      10 || 34 => (
          'M 5 5 m -4,0 a 4,4 0 1,0 8,0 a 4,4 0 1,0 -8,0',
          true,
        ), // filled circle
      14 => (
          'M 5 5 m -4,0 a 4,4 0 1,0 8,0 a 4,4 0 1,0 -8,0',
          false,
        ), // open circle
      11 => ('M 1 5 L 5 1 L 9 5 L 5 9 Z', false), // open diamond
      15 => ('M 1 1 H 9 V 9 H 1 Z', true), // filled square
      16 => ('M 1 1 H 9 V 9 H 1 Z', false), // open square
      7 || 8 || 12 => ('M 0 1 L 10 5 L 0 9 L 2 5 Z', true), // stealth
      _ => ('M 0 1 L 10 5 L 0 9 Z', true), // filled triangle (2/4/5/…)
    };
    final pathD = tipAtEnd ? d : _mirrorArrowD(d);
    if (filled) {
      return '<path d="$pathD" fill="context-stroke" stroke="none"/>';
    }
    return '<path d="$pathD" fill="none" stroke="context-stroke" '
        'stroke-width="1.2" stroke-linejoin="round"/>';
  }

  /// Rough mirror of simple marker paths about x=5 (for start arrows).
  String _mirrorArrowD(String d) {
    // Dedicated mirrors for the small set of templates above.
    return switch (d) {
      'M 0 1 L 10 5 L 0 9' => 'M 10 1 L 0 5 L 10 9',
      'M 0 1 L 10 5 L 0 9 Z' => 'M 10 1 L 0 5 L 10 9 Z',
      'M 0 1 L 10 5 L 0 9 L 2 5 Z' => 'M 10 1 L 0 5 L 10 9 L 8 5 Z',
      'M 1 5 L 5 1 L 9 5 L 5 9 Z' => 'M 9 5 L 5 1 L 1 5 L 5 9 Z',
      'M 1 1 H 9 V 9 H 1 Z' => d, // square is symmetric
      _ => d, // circles are symmetric
    };
  }

  /// Visio arrow size (inches) → SVG markerWidth; 0.125" maps to 6 (legacy).
  double _arrowMarkerSize(double sizeInches) {
    final s = sizeInches <= 0 ? 0.125 : sizeInches;
    return (s / 0.125 * 6.0).clamp(3.0, 18.0);
  }

  /// Combine Visio `*Trans` (0..1) with the colour's own ARGB alpha
  /// (libvisio / `#RRGGBBAA` colours carry opacity in the colour cell).
  double _combinedOpacity(VsdxColor? c, double transparency) {
    final colourA = c == null ? 1.0 : c.alpha / 255.0;
    return (colourA * (1 - transparency)).clamp(0.0, 1.0);
  }

  String _dashAttr(int linePattern) {
    if (linePattern <= 1) return '';
    return switch (linePattern) {
      2 => '0.10 0.05',
      3 => '0.02 0.04',
      4 => '0.12 0.05 0.02 0.05',
      5 => '0.12 0.05 0.02 0.05 0.02 0.05',
      9 => '0.20 0.05',
      _ => '0.08 0.04',
    };
  }

  void _writeImage(
    StringBuffer buf,
    VsdxShape shape, {
    required String indent,
  }) {
    final src = _images.findByPart(shape.imagePartName ?? '');
    if (!embedImages || src == null) {
      _writeImagePlaceholder(buf, shape, indent: indent);
      return;
    }
    String? mime;
    List<int>? bytes;
    if (src.isFlutterDecodable) {
      mime = src.mimeType.isEmpty ? 'image/png' : src.mimeType;
      bytes = src.bytes;
    } else {
      // EMF/WMF/OLE with an embedded DIB — same extract path the canvas uses.
      final raster = extractMetafileRaster(
        Uint8List.fromList(src.bytes),
        mimeType: src.mimeType,
      );
      if (raster != null) {
        mime = 'image/bmp';
        bytes = raster;
      } else {
        // Pure-vector metafile: emit SVG paths (no Flutter rasterizer).
        final drawing = parseMetafileDrawing(
          Uint8List.fromList(src.bytes),
          mimeType: src.mimeType,
          partName: src.partName,
        );
        if (drawing != null && !drawing.isEmpty) {
          _writeMetafileDrawing(buf, shape, drawing, indent: indent);
          return;
        }
      }
    }
    if (mime == null || bytes == null) {
      _writeImagePlaceholder(buf, shape, indent: indent);
      return;
    }
    final href = 'data:$mime;base64,${base64Encode(bytes)}';
    // SVG <image> with preserveAspectRatio="none" stretches to fit; Visio
    // already stores the picture at the shape's bounds.
    buf.writeln(
      '$indent<g transform="translate(0 ${_n(shape.height)}) scale(1 -1)">'
      '<image href="$href" x="0" y="0" '
      'width="${_n(shape.width)}" height="${_n(shape.height)}" '
      'preserveAspectRatio="none"/></g>',
    );
  }

  /// Replay a vector metafile into shape-local SVG (GDI Y-down → Y-up flip).
  void _writeMetafileDrawing(
    StringBuffer buf,
    VsdxShape shape,
    MetafileDrawing drawing, {
    required String indent,
  }) {
    final dw = drawing.width;
    final dh = drawing.height;
    if (dw <= 0 || dh <= 0) {
      _writeImagePlaceholder(buf, shape, indent: indent);
      return;
    }
    final sx = shape.width / dw;
    final sy = shape.height / dh;
    buf.writeln(
      '$indent<g transform="translate(0 ${_n(shape.height)}) '
      'scale(${_n(sx)} ${_n(-sy)}) '
      'translate(${_n(-drawing.minX)} ${_n(-drawing.minY)})">',
    );
    for (final op in drawing.ops) {
      if (op is MetafilePathOp) {
        _writeMetafilePathOp(buf, op, indent: '$indent  ');
      } else if (op is MetafileTextOp) {
        _writeMetafileTextOp(buf, op, indent: '$indent  ');
      }
    }
    buf.writeln('$indent</g>');
  }

  void _writeMetafilePathOp(
    StringBuffer buf,
    MetafilePathOp op, {
    required String indent,
  }) {
    if (op.points.isEmpty) return;
    final fill = op.fill ? _argbCss(op.fillArgb) : 'none';
    final stroke = op.stroke ? _argbCss(op.strokeArgb) : 'none';
    final sw = op.stroke ? ' stroke-width="${_n(math.max(op.strokeWidth, 0.5))}"' : '';
    if (op.isEllipse && op.points.length >= 2) {
      var minX = op.points.first.x, maxX = op.points.first.x;
      var minY = op.points.first.y, maxY = op.points.first.y;
      for (final p in op.points) {
        minX = math.min(minX, p.x);
        maxX = math.max(maxX, p.x);
        minY = math.min(minY, p.y);
        maxY = math.max(maxY, p.y);
      }
      final cx = (minX + maxX) / 2;
      final cy = (minY + maxY) / 2;
      final rx = (maxX - minX) / 2;
      final ry = (maxY - minY) / 2;
      buf.writeln(
        '$indent<ellipse cx="${_n(cx)}" cy="${_n(cy)}" '
        'rx="${_n(rx)}" ry="${_n(ry)}" fill="$fill" stroke="$stroke"$sw/>',
      );
      return;
    }
    final d = StringBuffer('M ${_n(op.points.first.x)} ${_n(op.points.first.y)}');
    for (var i = 1; i < op.points.length; i++) {
      d.write(' L ${_n(op.points[i].x)} ${_n(op.points[i].y)}');
    }
    if (op.closed) d.write(' Z');
    buf.writeln(
      '$indent<path d="$d" fill="$fill" stroke="$stroke"$sw/>',
    );
  }

  void _writeMetafileTextOp(
    StringBuffer buf,
    MetafileTextOp op, {
    required String indent,
  }) {
    if (op.text.isEmpty) return;
    final size = math.max(op.fontHeight.abs(), 1.0);
    final face = (op.face == null || op.face!.isEmpty)
        ? 'Arial'
        : _esc(op.face!);
    // Parent group has scale(sy,-sy); un-flip glyphs so text stays upright.
    buf.writeln(
      '$indent<g transform="translate(${_n(op.x)} ${_n(op.y)}) scale(1 -1)">'
      '<text x="0" y="0" fill="${_argbCss(op.argb)}" '
      'font-family="$face" font-size="${_n(size)}">'
      '${_esc(op.text)}</text></g>',
    );
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
        return Offset2D(
          route[i].x + dx * t,
          route[i].y + dy * t,
        );
      }
      remaining -= len;
    }
    return route.last;
  }

  /// `#RRGGBB` plus optional `fill-opacity`/`stroke` alpha via rgba when needed.
  String _argbCss(int argb) {
    final a = (argb >> 24) & 0xFF;
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    if (a >= 255) {
      return '#${r.toRadixString(16).padLeft(2, '0')}'
          '${g.toRadixString(16).padLeft(2, '0')}'
          '${b.toRadixString(16).padLeft(2, '0')}';
    }
    return 'rgba($r,$g,$b,${(a / 255.0).toStringAsFixed(3)})';
  }

  void _writeImagePlaceholder(
    StringBuffer buf,
    VsdxShape shape, {
    required String indent,
  }) {
    buf.writeln(
      '$indent<rect x="0" y="0" width="${_n(shape.width)}" '
      'height="${_n(shape.height)}" fill="#f2f2f2" '
      'stroke="#b0b0b0" stroke-width="0.01"/>',
    );
  }

  static final RegExp _autoShapeName = RegExp(r'^Sheet\.\d+$');

  /// Meaningful 2-D shape name used as a label when text/richText are empty
  /// (matches canvas [_paintRichText] name fallback).
  String? _meaningfulNameLabel(VsdxShape shape) {
    if (shape.is1D) return null;
    if (shape.name.isEmpty || _autoShapeName.hasMatch(shape.name)) return null;
    return shape.name;
  }

  void _writeText(
    StringBuffer buf,
    VsdxShape shape,
    VsdxTheme theme,
    VsdxPage page, {
    required String indent,
  }) {
    final block = shape.richText.textBlock;
    // Match libvisio: HideText suppresses the label entirely.
    if (block.hideText) return;
    final tw = block.widthInches ?? shape.width;
    final th = block.heightInches ?? shape.height;
    // 1-D edge labels without TxtPin: sit on the drawn route midpoint
    // (same as canvas [_paintRichText]). Always use page-space route + deep
    // inverse so nested connectors land correctly.
    late final double pinX;
    late final double pinY;
    if (shape.isGlueableConnector &&
        block.pinXInches == null &&
        block.pinYInches == null) {
      final route = page.drawnConnectorPagePolyline(shape);
      final mid = route.length >= 2
          ? _polylineMidpoint(route)
          : page.shapePinPage(shape.id);
      final local = page.pageToLocalDeep(shape.id, mid);
      pinX = local.x;
      pinY = local.y;
    } else {
      pinX = block.pinXInches ?? shape.width / 2;
      pinY = block.pinYInches ?? shape.height / 2;
    }
    final lpx = block.locPinXInches ?? tw / 2;
    final lpy = block.locPinYInches ?? th / 2;
    final ml = block.marginLeftInches;
    final mr = block.marginRightInches;
    final mt = block.marginTopInches;
    final mb = block.marginBottomInches;

    final fallback =
        shape.text?.isNotEmpty == true ? shape.text! : _meaningfulNameLabel(shape);
    final runs = shape.richText.runs.isNotEmpty
        ? shape.richText.runs
        : <VsdxTextRun>[VsdxTextRun(text: fallback ?? '')];
    if (runs.every((r) => r.text.isEmpty) && (fallback == null || fallback.isEmpty)) {
      return;
    }

    // Match canvas: rotate about TxtPin, then offset by −TxtLocPin so the
    // block's lower-left is the local origin (not the text centroid).
    final xf = StringBuffer(
      'translate(${_n(pinX)} ${_n(pinY)})',
    );
    if (block.angleRad != 0) {
      xf.write(' rotate(${_n(block.angleRad * 180 / math.pi)})');
    }
    xf.write(' translate(${_n(-lpx)} ${_n(-lpy)})');

    // TextBkgnd in block-local coords (lower-left origin, Y-up).
    if (block.backgroundColor != null) {
      final bgOp = _combinedOpacity(
        block.backgroundColor,
        block.backgroundTransparency,
      );
      buf.writeln(
        '$indent<g transform="$xf">'
        '<rect x="0" y="0" width="${_n(tw)}" height="${_n(th)}" '
        'fill="${_hex(block.backgroundColor!)}" '
        'fill-opacity="${_n(bgOp)}" stroke="none"/></g>',
      );
    }

    // Split into paragraphs (Visio `\n` / `<pp>`). Each keeps its own
    // HorzAlign / Ind* / Sp* / Bullet* (canvas [_paintParagraphBlock]).
    final paras = _splitSvgParagraphs(runs);
    final layouts = <({
      VsdxParaStyle style,
      List<(String text, VsdxTextRun run)> segs,
      double lineH,
      double yTop,
    })>[];
    var cursor = 0.0;
    for (final p in paras) {
      cursor += p.style.spaceBeforeInches;
      final lineH = _svgParaLineHeight(p.segs, p.style);
      layouts.add((style: p.style, segs: p.segs, lineH: lineH, yTop: cursor));
      cursor += lineH + p.style.spaceAfterInches;
    }
    final textH = math.max(cursor, 0.04);
    final yCenter = switch (block.verticalAlign) {
      VsdxVertAlign.top => th - mt - textH / 2,
      VsdxVertAlign.bottom => mb + textH / 2,
      VsdxVertAlign.middle => th / 2,
    };

    // Text glyphs: block-local → upright (scale 1,-1). One <text> per
    // paragraph so HorzAlign / indent can differ across lines.
    final textXf = StringBuffer('$xf');
    textXf.write(' translate(0 ${_n(yCenter)})');
    if (block.textDirection == 1) {
      textXf.write(' rotate(-90)');
    }
    textXf.write(' scale(1 -1)');
    buf.writeln('$indent<g transform="$textXf">');
    for (final layout in layouts) {
      final style = layout.style;
      final indentL = style.indentLeftInches;
      final indentF = style.indentFirstInches;
      final hasBullet = style.bullet != 0;
      final bulletGap = hasBullet
          ? math.max(style.textPosAfterBulletInches, layout.lineH * 0.6)
          : 0.0;
      final (anchor, xBody) = switch (style.horizontalAlign) {
        VsdxHorzAlign.left || VsdxHorzAlign.justify => (
            'start',
            ml + indentL + indentF + bulletGap,
          ),
        VsdxHorzAlign.right => ('end', tw - mr - style.indentRightInches),
        VsdxHorzAlign.center => ('middle', tw / 2),
      };
      // y relative to cluster centre (Y-down after scale).
      final yRel = layout.yTop + layout.lineH / 2 - textH / 2;
      final body = StringBuffer();
      if (hasBullet && style.horizontalAlign != VsdxHorzAlign.center) {
        final glyph = _svgBulletGlyph(style);
        final bFs = style.bulletFontSizeInches != null &&
                style.bulletFontSizeInches! > 0
            ? style.bulletFontSizeInches!
            : layout.lineH / 1.2;
        final bx = ml + indentL + indentF;
        body.write(
          '<tspan x="${_n(bx)}" text-anchor="start" '
          'font-size="${_n(bFs)}" '
          '${style.bulletFont != null ? 'font-family="${_esc(style.bulletFont!)}" ' : ''}'
          'fill="#222222">${_esc(glyph)}</tspan>',
        );
      }
      for (var si = 0; si < layout.segs.length; si++) {
        final (raw, run) = layout.segs[si];
        final text = _applyTextCase(raw, run.charStyle.textCase);
        final attrs = _charStyleSvgAttrs(run.charStyle, theme);
        if (si == 0) {
          body.write(
            '<tspan x="${_n(xBody)}" $attrs>${_esc(text)}</tspan>',
          );
        } else {
          body.write('<tspan $attrs>${_esc(text)}</tspan>');
        }
      }
      buf.writeln(
        '$indent  <text text-anchor="$anchor" dominant-baseline="middle" '
        'y="${_n(yRel)}">$body</text>',
      );
    }
    buf.writeln('$indent</g>');
  }

  List<({VsdxParaStyle style, List<(String text, VsdxTextRun run)> segs})>
      _splitSvgParagraphs(List<VsdxTextRun> runs) {
    final out =
        <({VsdxParaStyle style, List<(String text, VsdxTextRun run)> segs})>[];
    var segs = <(String, VsdxTextRun)>[];
    var style = VsdxParaStyle.defaults;
    void flush() {
      out.add((style: style, segs: segs));
      segs = <(String, VsdxTextRun)>[];
    }

    for (final run in runs) {
      final parts = run.text.split('\n');
      for (var i = 0; i < parts.length; i++) {
        if (i > 0) flush();
        style = run.paraStyle;
        segs.add((parts[i], run));
      }
    }
    if (segs.isNotEmpty || out.isEmpty) flush();
    return out;
  }

  double _svgParaLineHeight(
    List<(String, VsdxTextRun)> segs,
    VsdxParaStyle style,
  ) {
    var fs = 0.04;
    for (final (_, run) in segs) {
      fs = math.max(fs, run.charStyle.fontSizeInches);
    }
    if (style.lineSpacingAbsoluteInches > 1e-9) {
      return math.max(style.lineSpacingAbsoluteInches, fs);
    }
    final mult = style.lineSpacingSolid ? 1.0 : style.lineSpacing;
    return fs * 1.2 * (mult <= 0 ? 1.0 : mult);
  }

  String _svgBulletGlyph(VsdxParaStyle style) {
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

  String _applyTextCase(String text, VsdxTextCase c) => switch (c) {
        VsdxTextCase.allCaps => text.toUpperCase(),
        VsdxTextCase.initialCaps => text.isEmpty
            ? text
            : '${text[0].toUpperCase()}${text.substring(1)}',
        VsdxTextCase.normal => text,
      };

  String _charStyleSvgAttrs(VsdxCharStyle c, VsdxTheme theme) {
    final color = _resolveColor(c.color, c.themeColorIndex, theme) ??
        const VsdxColor(0xFF222222);
    final op = _combinedOpacity(color, c.transparency);
    var fs = math.max(c.fontSizeInches, 0.04);
    // FontScale is a width scale in Visio; approximate with font-size * scale
    // when ≠ 1 (SVG lacks a direct scaleX on tspan without a nested transform).
    if ((c.fontScale - 1.0).abs() > 1e-6) {
      fs *= c.fontScale.clamp(0.1, 4.0);
    }
    switch (c.position) {
      case VsdxTextPosition.superscript:
      case VsdxTextPosition.subscript:
        fs *= 0.7;
      case VsdxTextPosition.normal:
        break;
    }
    final family = c.fontFamily ?? 'sans-serif';
    final weight = c.style.bold ? 'bold' : 'normal';
    final italic = c.style.italic ? 'italic' : 'normal';
    final deco = <String>[
      if (c.underline || c.doubleUnderline) 'underline',
      if (c.strikethrough || c.doubleStrikethrough) 'line-through',
      if (c.overline) 'overline',
    ];
    final attrs = StringBuffer(
      'font-family="${_esc(family)}" font-size="${_n(fs)}" '
      'font-weight="$weight" font-style="$italic" '
      'fill="${_hex(color)}" fill-opacity="${_n(op)}"',
    );
    if (deco.isNotEmpty) {
      attrs.write(' text-decoration="${deco.join(' ')}"');
    }
    if (c.letterSpacingInches.abs() > 1e-9) {
      attrs.write(' letter-spacing="${_n(c.letterSpacingInches)}"');
    }
    switch (c.position) {
      case VsdxTextPosition.superscript:
        attrs.write(' baseline-shift="super"');
      case VsdxTextPosition.subscript:
        attrs.write(' baseline-shift="sub"');
      case VsdxTextPosition.normal:
        break;
    }
    return attrs.toString();
  }

  VsdxColor? _resolveColor(VsdxColor? raw, int? themeIdx, VsdxTheme theme) {
    if (raw != null) return raw;
    if (themeIdx == null) return null;
    return theme.resolve(themeIdx);
  }

  String _hex(VsdxColor c) {
    return '#${((c.red << 16) | (c.green << 8) | c.blue).toRadixString(16).padLeft(6, '0')}';
  }

  String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  String _n(double v) {
    if (v.isNaN || v.isInfinite) return '0';
    if (v == v.truncateToDouble()) return v.toStringAsFixed(0);
    return v
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}
