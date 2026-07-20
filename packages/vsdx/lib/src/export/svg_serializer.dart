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
import 'compound_stroke.dart';
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
    this.drawLineJumps = true,
    this.lineJumpRadiusInches = kDefaultLineJumpRadiusInches,
    this.bakeArrowMarkers = false,
    this.pdfCompat = false,
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

  /// UI / canvas toggle — when `false`, skip jump arcs even if the page
  /// `LineJumpCode` allows them (matches [VsdxPainter.drawLineJumps]).
  final bool drawLineJumps;

  /// Arc radius for connector line jumps (matches canvas
  /// [VsdxPainter.lineJumpRadiusInches]).
  final double lineJumpRadiusInches;

  /// When `true`, emit arrowheads as transformed `<path>` geometry instead of
  /// SVG `<marker>` (needed for PDF via `package:pdf`, which ignores markers).
  final bool bakeArrowMarkers;

  /// Approximate features that `package:pdf` SvgImage cannot render: no SVG
  /// filters/patterns/`textPath`/`dominant-baseline`. Implies [bakeArrowMarkers].
  final bool pdfCompat;

  bool get _bakeArrows => bakeArrowMarkers || pdfCompat;

  /// Current image registry, swapped in by [serializePage] / [serializeDocument].
  ImageRegistry _images = ImageRegistry.empty;

  /// Line-jump state for the page currently being serialised.
  bool _jumpsEnabled = false;
  List<List<Offset2D>> _jumpRoutes = const <List<Offset2D>>[];
  List<int?> _jumpCodes = const <int?>[];
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
      'xml:space="preserve" '
      'width="${_n(maxW)}" '
      'height="${_n(totalH)}" '
      'viewBox="0 0 ${_n(maxW)} ${_n(totalH)}">',
    );
    buf.writeln('  <title>${_esc(doc.title ?? 'Visio document')}</title>');
    var offsetY = 0.0;
    for (var i = 0; i < exportPages.length; i++) {
      final p = exportPages[i];
      // ids match Visio `#Page-N` / page-name hyperlinks (SVG fragment targets).
      final ids = _svgPageFragmentIds(p, index1: i + 1);
      buf.writeln(
        '  <g class="page page-${i + 1}"${ids.isEmpty ? '' : ' id="${_esc(ids.first)}"'} '
        'transform="translate(0,${_n(offsetY)})">',
      );
      for (var j = 1; j < ids.length; j++) {
        buf.writeln(
          '    <g id="${_esc(ids[j])}"></g>',
        );
      }
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
    final fragIds = _svgPageFragmentIds(page, index1: 1);
    buf.writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" '
      'version="1.1" '
      'xml:space="preserve" '
      'width="${_n(w)}" '
      'height="${_n(h)}" '
      'viewBox="0 0 ${_n(w)} ${_n(h)}"'
      '${fragIds.isEmpty ? '' : ' id="${_esc(fragIds.first)}"'}>',
    );
    for (var j = 1; j < fragIds.length; j++) {
      buf.writeln('  <g id="${_esc(fragIds[j])}"></g>');
    }
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

  /// Fragment ids for in-document hyperlinks (`#Page-2`, page name, …).
  List<String> _svgPageFragmentIds(VsdxPage page, {required int index1}) {
    final names = <String>{};
    void add(String? raw) {
      final t = raw?.trim();
      if (t == null || t.isEmpty) return;
      names.add(t.startsWith('#') ? t.substring(1) : t);
    }

    add(page.name);
    add('Page-$index1');
    return names.toList(growable: false);
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
    // UI toggle only — ConLineJumpCode Always can hop even when page is None.
    _jumpsEnabled = drawLineJumps;
    if (!_jumpsEnabled) {
      _jumpRoutes = const <List<Offset2D>>[];
      _jumpCodes = const <int?>[];
      _jumpZ = const <int, int>{};
      return;
    }
    final routes = <List<Offset2D>>[];
    final codes = <int?>[];
    final z = <int, int>{};
    void walk(List<VsdxShape> list) {
      for (final s in list) {
        if (s.isGlueableConnector) {
          final route = page.drawnConnectorPagePolyline(s);
          if (route.length >= 2) {
            z[s.id] = routes.length;
            routes.add(route);
            codes.add(s.connectorProps?.conLineJumpCode);
          }
        }
        if (!s.collapsed) walk(s.children);
      }
    }

    walk(page.shapes);
    _jumpRoutes = routes;
    _jumpCodes = codes;
    _jumpZ = z;
  }

  /// Shape-local stroke `d` with line jumps when this 1-D shape crosses
  /// connectors drawn beneath it. Returns `null` when jumps do not apply so
  /// authored / curved geometry from [_geometryToD] is kept.
  String? _connectorJumpD(VsdxPage page, VsdxShape shape) {
    if (!_jumpsEnabled || !shape.isGlueableConnector) return null;
    final sheet = page.pageSheet;
    final pageCode = sheet.lineJumpCode;
    final z = _jumpZ[shape.id];
    if (z == null) return null;
    if (!lineJumpShapeMayHop(
      k: z,
      routeCount: _jumpRoutes.length,
      pageJumpCode: pageCode,
      selfConCode: shape.connectorProps?.conLineJumpCode,
      peerConCodes: _jumpCodes,
    )) {
      return null;
    }
    final pageRoute = _jumpRoutes[z];
    final localRoute = <Offset2D>[
      for (final p in pageRoute) page.pageToLocalDeep(shape.id, p),
    ];
    if (localRoute.length < 2) return null;
    final peerIdx = lineJumpPeerIndices(
      k: z,
      routeCount: _jumpRoutes.length,
      pageJumpCode: pageCode,
      selfConCode: shape.connectorProps?.conLineJumpCode,
      peerConCodes: _jumpCodes,
    );
    if (peerIdx.isEmpty) return null;
    final unders = <List<Offset2D>>[
      for (final i in peerIdx)
        <Offset2D>[
          for (final p in _jumpRoutes[i]) page.pageToLocalDeep(shape.id, p),
        ],
    ];
    if (polylineCrossings(localRoute, unders).isEmpty) return null;
    final rx = resolveLineJumpRadius(
      uiRadius: lineJumpRadiusInches,
      lineToLineInches: sheet.lineToLineXInches,
      jumpFactor: sheet.lineJumpFactorX,
    );
    final ry = resolveLineJumpRadius(
      uiRadius: lineJumpRadiusInches,
      lineToLineInches: sheet.lineToLineYInches,
      jumpFactor: sheet.lineJumpFactorY,
    );
    return polylineWithJumpsSvg(
      localRoute,
      unders,
      rx,
      radiusY: ry,
      pageJumpCode: pageCode,
      style: shape.connectorProps?.conLineJumpStyle,
      pageStyle: sheet.lineJumpStyle,
      dirX: effectiveLineJumpDir(
        shape.connectorProps?.conLineJumpDirX,
        sheet.lineJumpDirX,
      ),
      dirY: effectiveLineJumpDir(
        shape.connectorProps?.conLineJumpDirY,
        sheet.lineJumpDirY,
      ),
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

    // Picture frames keep Geometry (fill/stroke/effects); paint it first so
    // the outer half of the stroke stays visible around the bitmap.
    var wroteGeom = false;
    var geomIndex = 0;
    // Canvas [_paintLineEndings] draws arrows once from the first strokeable
    // Geometry — do not attach markers/bake on every section.
    var arrowsAttached = false;
    final jumpD = _connectorJumpD(page, shape);
    for (final geom in shape.geometries) {
      if (geom.noShow) continue;
      final d = _geometryToD(
        geom,
        shape.width,
        shape.height,
        roundingInches: shape.line.roundingInches,
      );
      if (d.isEmpty) continue;
      // Match canvas: line jumps affect stroke only; fill keeps the raw
      // geometry. Do not break — later Geometry sections still paint.
      final strokeD = (jumpD != null && !geom.noLine) ? jumpD : null;
      wroteGeom = true;
      final attachArrows = !geom.noLine &&
          !arrowsAttached &&
          shape.line.hasLine &&
          (shape.line.hasBeginArrow || shape.line.hasEndArrow);
      _writePath(
        buf,
        shape,
        theme,
        d: d,
        strokeD: strokeD,
        noFill: geom.noFill,
        noLine: geom.noLine,
        attachArrows: attachArrows,
        // paintIdScope is page- (and underlay-) scoped so multi-page SVG
        // and shared BackPage composites do not collide defs ids.
        paintId: '$paintIdScope-${shape.id}-$geomIndex',
        indent: '$indent  ',
      );
      if (attachArrows) arrowsAttached = true;
      geomIndex++;
    }
    if (shape.hasImage) {
      _writeImage(buf, shape, indent: '$indent  ');
    } else if (!wroteGeom &&
        shape.isGlueableConnector &&
        shape.beginX != null &&
        shape.beginY != null &&
        shape.endX != null &&
        shape.endY != null) {
      // Canvas paints geometry-less 1-D connectors via orthogonal routing.
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
          attachArrows: shape.line.hasLine &&
              (shape.line.hasBeginArrow || shape.line.hasEndArrow),
          paintId: '$paintIdScope-${shape.id}-0',
          indent: '$indent  ',
        );
      }
    }

    // Match canvas name-fallback: 2-D shapes with a meaningful (non Sheet.N)
    // name paint that label when richText/text are empty.
    final hasLabel = !shape.richText.isEmpty ||
        (shape.text?.isNotEmpty ?? false) ||
        _meaningfulNameLabel(shape) != null;
    if (hasLabel) {
      _writeText(
        buf,
        shape,
        theme,
        page,
        paintIdScope: paintIdScope,
        indent: '$indent  ',
      );
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
    /// When set (line jumps), stroke uses this path; fill keeps [d].
    String? strokeD,
    required bool noFill,
    required bool noLine,
    bool attachArrows = true,
    required String paintId,
    required String indent,
  }) {
    final defs = StringBuffer();
    // Gradients use userSpaceOnUse with path bounds (canvas inches), not OBB.
    final linePad = math.max(
      0.01,
      shape.line.weightInches > 0 ? shape.line.weightInches : 0.01,
    );
    final fillBounds = _approxPathBoundsFromD(
      d,
      fallbackW: shape.width.abs() < 1e-9 ? 1.0 : shape.width.abs(),
      fallbackH: shape.height.abs() < 1e-9 ? 1.0 : shape.height.abs(),
      degeneratePad: linePad,
    );
    final fillAttr = !noFill
        ? _fillAttr(shape.fill, theme, paintId, defs, bounds: fillBounds)
        : 'fill="none"';
    // Line gradients follow the unjumped geometry (canvas path bounds).
    // Jump hops must not shift the gradient centre.
    final stroke = !noLine
        ? _strokeAttr(
            shape.line,
            theme,
            paintId,
            defs,
            bounds: fillBounds,
            includeMarkers: attachArrows && !_bakeArrows,
          )
        : (paint: 'stroke="none"', markers: '');
    final sD = strokeD ?? d;
    // Gap jumps insert mid-path `M` subpaths; SVG markers would repeat on
    // every subpath. Hang markers (and baked tips) on the continuous [d].
    final markerD = d;
    // SoftEdges only — shadow is painted separately (fill-only / stroke-only
    // like canvas [_drawShadow]). Markers stay outside soft blur.
    final softFilter = _softEdgesFilterAttr(
      shape,
      paintId,
      defs,
      bounds: fillBounds,
    );
    if (defs.isNotEmpty) {
      buf.writeln('$indent<defs>$defs</defs>');
    }
    _writeDropShadow(
      buf,
      shape,
      theme,
      d: d,
      noFill: noFill,
      noLine: noLine,
      paintId: paintId,
      indent: indent,
    );
    // Match canvas order: shadow → glow → reflection → body.
    // Soft outer glow (canvas strokes a blurred path before fill).
    final glow = shape.glow;
    if (glow.enabled && glow.sizeInches > 0) {
      // Match canvas [_drawGlow]: amber fallback + soft 0.6 alpha scale.
      final gc = _resolveColor(glow.color, glow.themeColorIndex, theme) ??
          const VsdxColor(0xFFFFC107);
      final ga = _combinedOpacity(gc, glow.transparency) * 0.6;
      if (ga > 0) {
        final sw = math.max(glow.sizeInches * 2, 0.02);
        if (pdfCompat) {
          // package:pdf ignores filters — approximate with a soft stroke.
          buf.writeln(
            '$indent<path d="$d" fill="none" stroke="${_hex(gc)}" '
            'stroke-width="${_n(sw)}" stroke-opacity="${_n(ga)}"/>',
          );
        } else {
          final gid = 'glow-$paintId';
          final pad = glow.sizeInches * 3;
          final region = _filterRegionAttr(fillBounds, pad);
          // Opacity lives only on feFlood — putting it on stroke as well would
          // square alpha vs canvas [_drawGlow] (which multiplies once).
          buf.writeln(
            '$indent<defs><filter id="$gid" $region>'
            '<feGaussianBlur stdDeviation="${_n(glow.sizeInches)}" '
            'result="blur"/>'
            '<feFlood flood-color="${_hex(gc)}" flood-opacity="${_n(ga)}" '
            'result="color"/>'
            '<feComposite in="color" in2="blur" operator="in" result="glow"/>'
            '<feMerge><feMergeNode in="glow"/></feMerge>'
            '</filter></defs>',
          );
          // Glow follows raw geometry (canvas); jumps apply only to the stroke.
          buf.writeln(
            '$indent<path d="$d" fill="none" stroke="${_hex(gc)}" '
            'stroke-width="${_n(sw)}" '
            'stroke-opacity="1" filter="url(#$gid)"/>',
          );
        }
      }
    }
    _writeReflection(
      buf,
      shape,
      theme,
      d: d,
      noFill: noFill,
      noLine: noLine,
      paintId: paintId,
      indent: indent,
    );
    final filter = softFilter == null ? '' : ' filter="$softFilter"';
    final compound = !noLine && shape.line.compoundType > 0;
    if (compound) {
      final weight =
          shape.line.weightInches > 0 ? shape.line.weightInches : 0.01;
      final linecap = switch (shape.line.cap) {
        LineCap.round => 'round',
        LineCap.square => 'square',
        LineCap.extended => 'butt',
      };
      final linejoin = shape.line.roundingInches > 0 ? 'round' : 'miter';
      // SoftEdges once on a wrapper — markers stay outside (canvas paints
      // arrows after soft/shadow/glow in _paintLineEndings).
      if (filter.isNotEmpty) {
        buf.writeln('$indent<g$filter>');
      }
      if (!noFill && fillAttr != 'fill="none"') {
        buf.writeln('$indent<path d="$d" $fillAttr stroke="none"/>');
      }
      final rails = compoundRails(shape.line.compoundType, weight);
      final sampled = samplePathD(sD);
      final usedRails = rails.isNotEmpty && sampled.points.length >= 2;
      if (usedRails) {
        // Parallel offset rails (matches canvas thick-thin / thin-thick).
        final strokePaint = stroke.paint;
        for (final rail in rails) {
          final off = offsetPolyline(
            sampled.points,
            rail.offset,
            closed: sampled.closed,
          );
          if (off.length < 2) continue;
          final od = polylineToPathD(off, closed: sampled.closed);
          // Replace stroke-width on the paint attrs with the rail width.
          final railPaint = strokePaint.replaceAll(
            RegExp(r'stroke-width="[^"]*"'),
            'stroke-width="${_n(rail.width)}"',
          );
          final withCap = railPaint.contains('stroke-linecap=')
              ? railPaint
              : '$railPaint stroke-linecap="$linecap" '
                  'stroke-linejoin="$linejoin"';
          buf.writeln(
            '$indent<path d="$od" fill="none" $withCap/>',
          );
        }
      } else {
        // Fallback: concentric mask gap (double-rail approximation).
        final gap = weight * 0.38;
        final mid = 'cmp-$paintId';
        buf.writeln(
          '$indent<defs><mask id="$mid" maskUnits="userSpaceOnUse">'
          '<path d="$sD" fill="none" stroke="white" '
          'stroke-width="${_n(weight)}" stroke-linecap="$linecap" '
          'stroke-linejoin="$linejoin"/>'
          '<path d="$sD" fill="none" stroke="black" '
          'stroke-width="${_n(gap)}" stroke-linecap="$linecap" '
          'stroke-linejoin="$linejoin"/>'
          '</mask></defs>',
        );
        buf.writeln(
          '$indent<path d="$sD" fill="none" ${stroke.paint} '
          'mask="url(#$mid)"/>',
        );
      }
      if (filter.isNotEmpty) {
        buf.writeln('$indent</g>');
      }
      if (stroke.markers.isNotEmpty) {
        buf.writeln(
          '$indent<path d="$markerD" fill="none" '
          '${_markerCarrierStroke(stroke.paint)}${stroke.markers}/>',
        );
      }
    } else if (strokeD != null && strokeD != d) {
      // Distinct fill vs jump stroke paths (canvas parity).
      if (filter.isNotEmpty) {
        buf.writeln('$indent<g$filter>');
      }
      if (!noFill && fillAttr != 'fill="none"') {
        buf.writeln('$indent<path d="$d" $fillAttr stroke="none"/>');
      }
      if (!noLine && stroke.paint != 'stroke="none"') {
        buf.writeln(
          '$indent<path d="$sD" fill="none" ${stroke.paint}/>',
        );
      }
      if (filter.isNotEmpty) {
        buf.writeln('$indent</g>');
      }
      if (stroke.markers.isNotEmpty) {
        buf.writeln(
          '$indent<path d="$markerD" fill="none" '
          '${_markerCarrierStroke(stroke.paint)}${stroke.markers}/>',
        );
      }
    } else {
      buf.writeln(
        '$indent<path d="$d" $fillAttr ${stroke.paint}$filter/>',
      );
      if (stroke.markers.isNotEmpty) {
        buf.writeln(
          '$indent<path d="$markerD" fill="none" '
          '${_markerCarrierStroke(stroke.paint)}${stroke.markers}/>',
        );
      }
    }
    if (_bakeArrows && attachArrows && !noLine && shape.line.hasLine) {
      _writeBakedArrows(
        buf,
        shape,
        theme,
        pathD: markerD,
        indent: indent,
      );
    }
  }

  /// Invisible stroke carrier for SVG `<marker>` — HTML keeps the *first*
  /// duplicate attribute, so a trailing `stroke-opacity="0"` after
  /// [stroke.paint]'s opacity would be ignored and the rail would double-draw.
  String _markerCarrierStroke(String paint) {
    if (RegExp(r'stroke-opacity="[^"]*"').hasMatch(paint)) {
      return paint.replaceAll(
        RegExp(r'stroke-opacity="[^"]*"'),
        'stroke-opacity="0"',
      );
    }
    return '$paint stroke-opacity="0"';
  }

  /// Tip colour for arrowheads: solid stroke, or gradient end-stop near the tip.
  ({String hex, double opacity}) _arrowTipPaint(
    VsdxLine line,
    VsdxTheme theme, {
    required bool atEnd,
    required String fallbackHex,
  }) {
    if (!line.hasGradient || line.gradient!.stops.isEmpty) {
      final c = _resolveColor(line.color, line.themeColorIndex, theme);
      final op = _combinedOpacity(c, line.transparency);
      return (hex: fallbackHex, opacity: op);
    }
    final stops = line.gradient!.stops;
    final s = atEnd ? stops.last : stops.first;
    final sc = _resolveColor(s.color, s.themeColorIndex, theme) ??
        const VsdxColor(0xFF000000);
    // LineColorTrans multiplies the whole stroke; stop transparency too.
    final op = (_combinedOpacity(sc, s.transparency) *
            (1.0 - line.transparency.clamp(0.0, 1.0)))
        .clamp(0.0, 1.0);
    return (hex: _hex(sc), opacity: op);
  }

  /// Geometry arrows for backends that ignore SVG `<marker>` (PDF).
  void _writeBakedArrows(
    StringBuffer buf,
    VsdxShape shape,
    VsdxTheme theme, {
    required String pathD,
    required String indent,
  }) {
    final line = shape.line;
    if (!line.hasBeginArrow && !line.hasEndArrow) return;
    final tips = _pathTipTangents(pathD);
    if (tips == null) return;
    final c = _resolveColor(line.color, line.themeColorIndex, theme);
    final hex = c == null ? '#000000' : _hex(c);
    final weight = line.weightInches > 0 ? line.weightInches : 0.01;
    void emit({
      required Offset2D tip,
      required Offset2D from,
      required int arrowId,
      required double sizeInches,
      required bool atEnd,
    }) {
      final dx = tip.x - from.x;
      final dy = tip.y - from.y;
      if (dx.abs() < 1e-12 && dy.abs() < 1e-12) return;
      final deg = math.atan2(dy, dx) * 180 / math.pi;
      final mw = _arrowMarkerSize(sizeInches, arrowId);
      final paint = _arrowTipPaint(line, theme, atEnd: atEnd, fallbackHex: hex);
      final body = _arrowMarkerBody(
        arrowId,
        tipAtEnd: true,
        lineWeightInches: weight,
        markerSizeInches: mw,
        colorHex: paint.hex,
        opacity: paint.opacity,
      );
      // Marker viewBox tip at (10,5); scale so 10 units → mw inches.
      buf.writeln(
        '$indent<g transform="translate(${_n(tip.x)} ${_n(tip.y)}) '
        'rotate(${_n(deg)}) scale(${_n(mw / 10)}) translate(-10 -5)">'
        '$body</g>',
      );
    }

    if (line.hasBeginArrow) {
      emit(
        tip: tips.begin,
        from: tips.beginFrom,
        arrowId: line.beginArrow,
        sizeInches: line.beginArrowSizeInches,
        atEnd: false,
      );
    }
    if (line.hasEndArrow) {
      emit(
        tip: tips.end,
        from: tips.endFrom,
        arrowId: line.endArrow,
        sizeInches: line.endArrowSizeInches,
        atEnd: true,
      );
    }
  }

  /// First/last vertices and their inward neighbours from an absolute-ish path.
  ({
    Offset2D begin,
    Offset2D beginFrom,
    Offset2D end,
    Offset2D endFrom,
  })? _pathTipTangents(String d) {
    final pts = <Offset2D>[];
    final tokens = RegExp(
      r'[A-Za-z]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?',
    ).allMatches(d).map((m) => m.group(0)!).toList();
    var cx = 0.0;
    var cy = 0.0;
    String? cmd;
    final nums = <double>[];
    void push(double x, double y) {
      final p = Offset2D(x, y);
      if (pts.isEmpty || pts.last.x != x || pts.last.y != y) pts.add(p);
      cx = x;
      cy = y;
    }

    void flush() {
      if (cmd == null) {
        nums.clear();
        return;
      }
      final rel = cmd == cmd!.toLowerCase();
      final op = cmd!.toUpperCase();
      switch (op) {
        case 'M':
        case 'L':
          for (var i = 0; i + 1 < nums.length; i += 2) {
            final x = rel ? cx + nums[i] : nums[i];
            final y = rel ? cy + nums[i + 1] : nums[i + 1];
            push(x, y);
          }
        case 'H':
          for (final v in nums) {
            push(rel ? cx + v : v, cy);
          }
        case 'V':
          for (final v in nums) {
            push(cx, rel ? cy + v : v);
          }
        case 'C':
          for (var i = 0; i + 5 < nums.length; i += 6) {
            // Near-end controls give tip tangents (canvas CubBezTo).
            final x1 = rel ? cx + nums[i] : nums[i];
            final y1 = rel ? cy + nums[i + 1] : nums[i + 1];
            final x2 = rel ? cx + nums[i + 2] : nums[i + 2];
            final y2 = rel ? cy + nums[i + 3] : nums[i + 3];
            final x = rel ? cx + nums[i + 4] : nums[i + 4];
            final y = rel ? cy + nums[i + 5] : nums[i + 5];
            push(x1, y1);
            push(x2, y2);
            push(x, y);
          }
        case 'Q':
          for (var i = 0; i + 3 < nums.length; i += 4) {
            final x1 = rel ? cx + nums[i] : nums[i];
            final y1 = rel ? cy + nums[i + 1] : nums[i + 1];
            final x = rel ? cx + nums[i + 2] : nums[i + 2];
            final y = rel ? cy + nums[i + 3] : nums[i + 3];
            push(x1, y1);
            push(x, y);
          }
        case 'A':
          for (var i = 0; i + 6 < nums.length; i += 7) {
            final rx = nums[i].abs();
            final ry = nums[i + 1].abs();
            final large = nums[i + 3].round() != 0;
            final sweep = nums[i + 4].round() != 0;
            final x = rel ? cx + nums[i + 5] : nums[i + 5];
            final y = rel ? cy + nums[i + 6] : nums[i + 6];
            // Near-end samples give tip tangents (canvas ArcTo steps: 8).
            for (final p in _sampleSvgArc(
              Offset2D(cx, cy),
              Offset2D(x, y),
              rx: rx,
              ry: ry,
              largeArc: large,
              sweep: sweep,
            )) {
              push(p.x, p.y);
            }
          }
        default:
          break;
      }
      nums.clear();
    }

    for (final t in tokens) {
      if (RegExp(r'^[A-Za-z]$').hasMatch(t)) {
        flush();
        cmd = t;
        if (t.toUpperCase() == 'Z') {
          cmd = null;
        }
      } else {
        final v = double.tryParse(t);
        if (v != null) nums.add(v);
      }
    }
    flush();
    if (pts.length < 2) return null;
    return (
      begin: pts.first,
      beginFrom: pts[1],
      end: pts.last,
      endFrom: pts[pts.length - 2],
    );
  }

  /// Canvas-matching drop shadow: blurred fill (2D) or stroke (1D / NoFill),
  /// drawn before the sharp shape — not feDropShadow on fill+stroke+markers.
  void _writeDropShadow(
    StringBuffer buf,
    VsdxShape shape,
    VsdxTheme theme, {
    required String d,
    required bool noFill,
    required bool noLine,
    required String paintId,
    required String indent,
  }) {
    final shadow = shape.shadow;
    if (!shadow.enabled) return;
    final base = _resolveColor(shadow.color, shadow.themeColorIndex, theme) ??
        const VsdxColor(0x99000000);
    final alpha = _combinedOpacity(base, shadow.transparency);
    if (alpha <= 0) return;
    // Foreign pictures still cast a filled silhouette shadow (match canvas:
    // NoFill + (NoLine or pattern-less stroke)).
    final imageSilhouette =
        shape.hasImage && noFill && (noLine || !shape.line.hasLine);
    final lineOnly =
        !imageSilhouette && (shape.is1D || noFill || !shape.fill.hasFill);
    if (lineOnly && noLine) return;
    // Match canvas: LinePattern=0 means no stroke, so no stroke-style shadow.
    if (lineOnly && !shape.line.hasLine) return;
    if (!lineOnly && noFill && !imageSilhouette) return;
    final hex = _hex(base);
    final dx = shadow.offsetXInches;
    final dy = shadow.offsetYInches;
    final blur = math.max(shadow.blurInches, 0.001);
    var filterAttr = '';
    if (!pdfCompat) {
      final sid = 'shadow-$paintId';
      final bounds = _approxPathBoundsFromD(
        d,
        fallbackW: shape.width.abs() < 1e-9 ? 1.0 : shape.width.abs(),
        fallbackH: shape.height.abs() < 1e-9 ? 1.0 : shape.height.abs(),
        degeneratePad: math.max(
          0.01,
          shape.line.weightInches > 0 ? shape.line.weightInches : 0.01,
        ),
      );
      final region = _filterRegionAttr(bounds, blur * 3);
      buf.writeln(
        '$indent<defs><filter id="$sid" $region>'
        '<feGaussianBlur stdDeviation="${_n(blur)}"/>'
        '</filter></defs>',
      );
      filterAttr = ' filter="url(#$sid)"';
    }
    if (lineOnly) {
      final weight =
          shape.line.weightInches > 0 ? shape.line.weightInches : 0.01;
      final linecap = switch (shape.line.cap) {
        LineCap.round => 'round',
        LineCap.square => 'square',
        LineCap.extended => 'butt',
      };
      final linejoin = shape.line.roundingInches > 0 ? 'round' : 'miter';
      final dash = _dashAttr(shape.line.pattern);
      // Shadow uses raw geometry (canvas); jump arcs are stroke-only.
      // Honour LinePattern like the main stroke / reflection.
      buf.writeln(
        '$indent<path d="$d" fill="none" stroke="$hex" '
        'stroke-opacity="${_n(alpha)}" stroke-width="${_n(weight)}" '
        'stroke-linecap="$linecap" stroke-linejoin="$linejoin"'
        '${dash.isEmpty ? '' : ' stroke-dasharray="$dash"'} '
        'transform="translate(${_n(dx)} ${_n(dy)})"$filterAttr/>',
      );
    } else {
      buf.writeln(
        '$indent<path d="$d" fill="$hex" fill-opacity="${_n(alpha)}" '
        'stroke="none" transform="translate(${_n(dx)} ${_n(dy)})"'
        '$filterAttr/>',
      );
    }
  }

  /// Filter region in shape-local inches (canvas inflate(blur×3) parity).
  /// Percent-based OBB regions clip soft blurs on short/flat shapes.
  String _filterRegionAttr(
    ({double minX, double minY, double width, double height}) bounds,
    double pad,
  ) {
    final p = math.max(pad, 0.01);
    return 'filterUnits="userSpaceOnUse" '
        'x="${_n(bounds.minX - p)}" y="${_n(bounds.minY - p)}" '
        'width="${_n(bounds.width + 2 * p)}" '
        'height="${_n(bounds.height + 2 * p)}"';
  }

  void _writeReflection(
    StringBuffer buf,
    VsdxShape shape,
    VsdxTheme theme, {
    required String d,
    required bool noFill,
    required bool noLine,
    required String paintId,
    required String indent,
  }) {
    final refl = shape.reflection;
    if (!refl.enabled || refl.sizeInches <= 0) return;
    final hasFill = !noFill && shape.fill.hasFill;
    final hasStroke = !noLine && shape.line.hasLine;
    // Foreign pictures mirror the real bitmap/metafile (canvas [_paintImage]).
    final imageMirror = shape.hasImage && !hasFill && !hasStroke;
    if (!hasFill && !hasStroke && !imageMirror) return;
    final alpha = (1 - refl.transparency).clamp(0.0, 1.0);
    if (alpha <= 0) return;
    // Approximate canvas reflection: mirror about path min-Y (visual bottom
    // in Y-up), clipped by ReflectionSize. Axis-aligned 1D lines have ~0 path
    // height — use stroke weight so ReflectionSize still yields a band.
    final weightH =
        shape.line.weightInches > 0 ? shape.line.weightInches : 0.01;
    final fallbackH =
        shape.height.abs() < 1e-9 ? weightH : shape.height.abs();
    final fallbackW =
        shape.width.abs() < 1e-9 ? weightH : shape.width.abs();
    final bounds = _approxPathBoundsFromD(
      d,
      fallbackW: fallbackW,
      fallbackH: fallbackH,
      degeneratePad: weightH,
    );
    final h = bounds.height;
    final bottomY = bounds.minY;
    final clipH = h * refl.sizeInches.clamp(0.01, 1.0);
    final clipX = bounds.minX - bounds.width;
    final clipW = bounds.width * 3;
    final dist = refl.distanceInches;
    final fid = 'refl-$paintId';
    final cid = 'refl-clip-$paintId';
    // Reuse the shape's gradient def (grad-$paintId) when present; otherwise
    // solid foreground × FillForegndTrans × ReflectionTransparency.
    late final String fillPaint;
    late final double fillOp;
    if (imageMirror) {
      // Content is written via [_writeForeignImageContent]; path fill unused.
      fillPaint = 'none';
      fillOp = 0;
    } else if (!hasFill) {
      fillPaint = 'none';
      fillOp = 0;
    } else if (shape.fill.hasGradient) {
      fillPaint = 'url(#grad-$paintId)';
      fillOp = alpha;
    } else if (shape.fill.pattern >= 2 &&
        shape.fill.pattern <= 16 &&
        !pdfCompat) {
      // Hatch defs emitted by [_fillAttr] as pat-$paintId — only when a real
      // <pattern> was created (not pdfCompat / pattern>16 solid fallback).
      fillPaint = 'url(#pat-$paintId)';
      fillOp = alpha;
    } else {
      // Solid (incl. pdfCompat hatch flatten and unsupported pattern ids).
      final c = _resolveColor(shape.fill.foreground,
              shape.fill.themeForegroundIndex, theme) ??
          const VsdxColor(0xFF888888);
      fillPaint = _hex(c);
      fillOp =
          _combinedOpacity(c, shape.fill.foregroundTransparency) * alpha;
    }
    // Stroke without arrow markers (canvas reflection draws the path stroke).
    var strokeAttrs = 'stroke="none"';
    if (hasStroke) {
      final line = shape.line;
      final c = _resolveColor(line.color, line.themeColorIndex, theme);
      final strokeAlpha = _combinedOpacity(c, line.transparency) * alpha;
      final hex = c == null ? '#000000' : _hex(c);
      final weight = line.weightInches > 0 ? line.weightInches : 0.01;
      final linecap = switch (line.cap) {
        LineCap.round => 'round',
        LineCap.square => 'square',
        LineCap.extended => 'butt',
      };
      final linejoin = line.roundingInches > 0 ? 'round' : 'miter';
      final dash = _dashAttr(line.pattern);
      final strokePaint = line.hasGradient
          ? 'stroke="url(#lg-$paintId)"'
          : 'stroke="$hex"';
      strokeAttrs = '$strokePaint stroke-opacity="${_n(strokeAlpha)}" '
          'stroke-width="${_n(weight)}" stroke-linecap="$linecap" '
          'stroke-linejoin="$linejoin"'
          '${dash.isEmpty ? '' : ' stroke-dasharray="$dash"'}';
    }
    // Fade mask matches canvas BlendMode.dstIn: opaque near the shape bottom,
    // transparent at the far edge of ReflectionSize.
    final fadeId = 'refl-fade-$paintId';
    final maskId = 'refl-mask-$paintId';
    final nearY = bottomY - dist;
    final farY = nearY - clipH;
    final clipY = bottomY - dist - clipH - refl.blurInches;
    if (pdfCompat) {
      // package:pdf ignores mask/filter — emit a simple faded mirror.
      buf.writeln(
        '$indent<g transform="translate(0 ${_n(-dist)}) '
        'translate(0 ${_n(bottomY)}) scale(1 -1) '
        'translate(0 ${_n(-bottomY)})">',
      );
      if (imageMirror) {
        final geomClip = 'refl-img-$paintId';
        buf.writeln(
          '$indent  <defs><clipPath id="$geomClip">'
          '<path d="$d"/></clipPath></defs>'
          '$indent  <g clip-path="url(#$geomClip)" '
          'opacity="${_n(alpha * 0.55)}">',
        );
        _writeForeignImageContent(
          buf,
          shape,
          indent: '$indent    ',
          toneIdSuffix: '-refl',
        );
        buf.writeln('$indent  </g>');
      } else {
        buf.writeln(
          '$indent  <path d="$d" fill="$fillPaint" '
          'fill-opacity="${_n(fillOp * 0.55)}" $strokeAttrs/>',
        );
      }
      buf.writeln('$indent</g>');
      return;
    }
    final blurPad = math.max(refl.blurInches, 0.001) * 3;
    final blurRegion = refl.blurInches > 0
        ? _filterRegionAttr(bounds, blurPad)
        : '';
    buf.writeln(
      '$indent<defs>'
      '<clipPath id="$cid">'
      // Include ReflectionDist like canvas so blur toward the body is not cut.
      '<rect x="${_n(clipX)}" y="${_n(clipY)}" '
      'width="${_n(clipW)}" '
      'height="${_n(clipH + refl.blurInches + dist)}"/>'
      '</clipPath>'
      '<linearGradient id="$fadeId" gradientUnits="userSpaceOnUse" '
      'x1="0" y1="${_n(nearY)}" x2="0" y2="${_n(farY)}">'
      '<stop offset="0" stop-color="#ffffff" stop-opacity="1"/>'
      '<stop offset="1" stop-color="#ffffff" stop-opacity="0"/>'
      '</linearGradient>'
      '<mask id="$maskId" maskUnits="userSpaceOnUse">'
      '<rect x="${_n(clipX)}" y="${_n(farY)}" '
      'width="${_n(clipW)}" height="${_n(clipH + refl.blurInches)}" '
      'fill="url(#$fadeId)"/>'
      '</mask>'
      '${refl.blurInches > 0 ? '<filter id="$fid" $blurRegion>'
          '<feGaussianBlur stdDeviation="${_n(math.max(refl.blurInches, 0.001))}"/>'
          '</filter>' : ''}'
      '</defs>',
    );
    final filter = refl.blurInches > 0 ? ' filter="url(#$fid)"' : '';
    // Mirror about path min-Y (canvas bounds.top), then shift by Distance.
    buf.writeln(
      '$indent<g clip-path="url(#$cid)" mask="url(#$maskId)" '
      'transform="translate(0 ${_n(-dist)}) translate(0 ${_n(bottomY)}) '
      'scale(1 -1) translate(0 ${_n(-bottomY)})">',
    );
    if (imageMirror) {
      final geomClip = 'refl-img-$paintId';
      buf.writeln(
        '$indent  <defs><clipPath id="$geomClip">'
        '<path d="$d"/></clipPath></defs>'
        '$indent  <g clip-path="url(#$geomClip)"$filter '
        'opacity="${_n(alpha)}">',
      );
      _writeForeignImageContent(
        buf,
        shape,
        indent: '$indent    ',
        toneIdSuffix: '-refl',
      );
      buf.writeln('$indent  </g>');
    } else {
      buf.writeln(
        '$indent  <path d="$d" fill="$fillPaint" fill-opacity="${_n(fillOp)}" '
        '$strokeAttrs$filter/>',
      );
    }
    buf.writeln('$indent</g>');
  }

  /// Axis-aligned bounds of path `d` in shape-local inches (for gradients).
  /// Tracks the current point so relative commands (`a`/`l`/…) expand correctly.
  ({double minX, double minY, double width, double height})
      _approxPathBoundsFromD(
    String d, {
    required double fallbackW,
    required double fallbackH,
    /// Half-extent for zero-area axes (line weight), matching canvas reflection.
    double? degeneratePad,
  }) {
    final tokens = RegExp(
      r'[A-Za-z]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?',
    ).allMatches(d).map((m) => m.group(0)!).toList();
    var minX = double.infinity;
    var maxX = double.negativeInfinity;
    var minY = double.infinity;
    var maxY = double.negativeInfinity;
    var cx = 0.0;
    var cy = 0.0;
    var subX = 0.0;
    var subY = 0.0;
    void consider(double x, double y) {
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }

    String? cmd;
    final nums = <double>[];
    void flush() {
      if (cmd == null) {
        nums.clear();
        return;
      }
      final rel = cmd == cmd!.toLowerCase();
      final op = cmd!.toUpperCase();
      switch (op) {
        case 'M':
        case 'L':
          for (var i = 0; i + 1 < nums.length; i += 2) {
            final x = rel ? cx + nums[i] : nums[i];
            final y = rel ? cy + nums[i + 1] : nums[i + 1];
            cx = x;
            cy = y;
            if (op == 'M' && i == 0) {
              subX = cx;
              subY = cy;
            }
            consider(cx, cy);
          }
        case 'H':
          for (final v in nums) {
            cx = rel ? cx + v : v;
            consider(cx, cy);
          }
        case 'V':
          for (final v in nums) {
            cy = rel ? cy + v : v;
            consider(cx, cy);
          }
        case 'C':
          for (var i = 0; i + 5 < nums.length; i += 6) {
            final x1 = rel ? cx + nums[i] : nums[i];
            final y1 = rel ? cy + nums[i + 1] : nums[i + 1];
            final x2 = rel ? cx + nums[i + 2] : nums[i + 2];
            final y2 = rel ? cy + nums[i + 3] : nums[i + 3];
            final x = rel ? cx + nums[i + 4] : nums[i + 4];
            final y = rel ? cy + nums[i + 5] : nums[i + 5];
            consider(x1, y1);
            consider(x2, y2);
            cx = x;
            cy = y;
            consider(cx, cy);
          }
        case 'Q':
          for (var i = 0; i + 3 < nums.length; i += 4) {
            final x1 = rel ? cx + nums[i] : nums[i];
            final y1 = rel ? cy + nums[i + 1] : nums[i + 1];
            final x = rel ? cx + nums[i + 2] : nums[i + 2];
            final y = rel ? cy + nums[i + 3] : nums[i + 3];
            consider(x1, y1);
            cx = x;
            cy = y;
            consider(cx, cy);
          }
        case 'A':
          for (var i = 0; i + 6 < nums.length; i += 7) {
            final rx = nums[i].abs();
            final ry = nums[i + 1].abs();
            final large = nums[i + 3].round() != 0;
            final sweep = nums[i + 4].round() != 0;
            final x = rel ? cx + nums[i + 5] : nums[i + 5];
            final y = rel ? cy + nums[i + 6] : nums[i + 6];
            consider(cx, cy);
            // Sample the arc (circular when rx≈ry) so minor arcs are not
            // inflated to a full-ellipse AABB via chord-mid ± radii.
            for (final p in _sampleSvgArc(
              Offset2D(cx, cy),
              Offset2D(x, y),
              rx: rx,
              ry: ry,
              largeArc: large,
              sweep: sweep,
            )) {
              consider(p.x, p.y);
            }
            cx = x;
            cy = y;
            consider(cx, cy);
          }
        case 'Z':
          cx = subX;
          cy = subY;
          consider(cx, cy);
        default:
          break;
      }
      nums.clear();
    }

    for (final t in tokens) {
      if (RegExp(r'^[A-Za-z]$').hasMatch(t)) {
        flush();
        cmd = t;
        if (t.toUpperCase() == 'Z') {
          flush();
          cmd = null;
        }
      } else {
        final v = double.tryParse(t);
        if (v != null) nums.add(v);
      }
    }
    flush();
    if (!minX.isFinite || !maxX.isFinite || !minY.isFinite || !maxY.isFinite) {
      return (minX: 0.0, minY: 0.0, width: fallbackW, height: fallbackH);
    }
    var w = maxX - minX;
    var h = maxY - minY;
    // Degenerate axes (horizontal/vertical strokes): inflate symmetrically
    // about the path centre. Prefer [degeneratePad] (line weight) like canvas
    // reflection; fall back to a small clamp so shape length is not reused.
    final pad = math.max(0.01, degeneratePad ?? 0.01);
    if (w < 1e-9) {
      final half = pad * 0.5;
      final cx = (minX + maxX) * 0.5;
      minX = cx - half;
      w = half * 2;
    }
    if (h < 1e-9) {
      final half = pad * 0.5;
      final cy = (minY + maxY) * 0.5;
      minY = cy - half;
      h = half * 2;
    }
    return (minX: minX, minY: minY, width: w, height: h);
  }

  /// Sample an SVG elliptical `A` arc — see [sampleSvgArc].
  static List<Offset2D> _sampleSvgArc(
    Offset2D start,
    Offset2D end, {
    required double rx,
    required double ry,
    required bool largeArc,
    required bool sweep,
    int steps = 8,
  }) =>
      sampleSvgArc(
        start,
        end,
        rx: rx,
        ry: ry,
        largeArc: largeArc,
        sweep: sweep,
        steps: steps,
      );

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

  /// SoftEdges blur only (shadow is [_writeDropShadow]). Skip 1D like canvas.
  String? _softEdgesFilterAttr(
    VsdxShape shape,
    String paintId,
    StringBuffer defs, {
    required ({double minX, double minY, double width, double height}) bounds,
  }) {
    // package:pdf ignores filters — SoftEdges would silently vanish.
    if (pdfCompat) return null;
    final soft =
        (!shape.is1D && shape.line.softEdgesInches > 0)
            ? shape.line.softEdgesInches
            : 0.0;
    if (soft <= 0) return null;
    final id = 'fx-$paintId';
    final region = _filterRegionAttr(bounds, soft * 3);
    defs.write(
      '<filter id="$id" $region>'
      '<feGaussianBlur in="SourceGraphic" '
      'stdDeviation="${_n(soft)}" result="soft"/>'
      '</filter>',
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
          // Sample like canvas / EllipticalArcTo so path bounds, reflection
          // axes, and PDF-baked arrow tangents use the true minor arc (not
          // chord-mid ± r which inflates like a full circle).
          if (bow == 0) {
            l(x, y);
          } else {
            for (final p in sampleArcByBow(
              start: Offset2D(cx, cy),
              end: Offset2D(x, y),
              bow: bow,
              steps: 8,
            )) {
              l(p.x, p.y);
            }
          }
        case RelArcTo(:final fx, :final fy, :final fbow):
          if (!started) m(0, 0);
          final x = fx * w;
          final y = fy * h;
          final bow = fbow * (w + h) / 2;
          if (bow == 0) {
            l(x, y);
          } else {
            for (final p in sampleArcByBow(
              start: Offset2D(cx, cy),
              end: Offset2D(x, y),
              bow: bow,
              steps: 8,
            )) {
              l(p.x, p.y);
            }
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
              // Absolute arcs so bounds / gradient sampling see real extents
              // (relative `a` endpoints were mis-read as absolute coords).
              m(cx - rx, cy);
              out
                ..write(
                  'A ${_n(rx)} ${_n(ry)} 0 1 0 ${_n(cx + rx)} ${_n(cy)} ',
                )
                ..write(
                  'A ${_n(rx)} ${_n(ry)} 0 1 0 ${_n(cx - rx)} ${_n(cy)} ',
                );
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
    StringBuffer defs, {
    required ({double minX, double minY, double width, double height}) bounds,
  }) {
    if (!fill.hasFill) return 'fill="none"';

    if (fill.hasGradient) {
      final g = fill.gradient!;
      final id = 'grad-$paintId';
      final fillAlpha = (1 - fill.foregroundTransparency.clamp(0.0, 1.0));
      final stops = StringBuffer();
      for (final s in g.stops) {
        final c = _resolveColor(s.color, s.themeColorIndex, theme) ??
            const VsdxColor(0xFFFFFFFF);
        final op = _combinedOpacity(c, s.transparency) * fillAlpha;
        stops.write(
          '<stop offset="${_n(s.position.clamp(0.0, 1.0))}" '
          'stop-color="${_hex(c)}" stop-opacity="${_n(op)}"/>',
        );
      }
      // Match canvas [_buildGradientShader]: userSpaceOnUse inches, not OBB
      // (OBB stretches angles on non-square shapes).
      final cx = bounds.minX + bounds.width / 2;
      final cy = bounds.minY + bounds.height / 2;
      final r = math.max(bounds.width, bounds.height) * 0.6;
      if (g.type == VsdxGradientType.linear) {
        final dx = math.cos(g.angleRad) * r;
        final dy = math.sin(g.angleRad) * r;
        defs.write(
          '<linearGradient id="$id" gradientUnits="userSpaceOnUse" '
          'x1="${_n(cx - dx)}" y1="${_n(cy - dy)}" '
          'x2="${_n(cx + dx)}" y2="${_n(cy + dy)}">'
          '$stops</linearGradient>',
        );
      } else {
        defs.write(
          '<radialGradient id="$id" gradientUnits="userSpaceOnUse" '
          'cx="${_n(cx)}" cy="${_n(cy)}" r="${_n(r)}">'
          '$stops</radialGradient>',
        );
      }
      return 'fill="url(#$id)"';
    }

    final fg = _resolveColor(fill.foreground, fill.themeForegroundIndex, theme);
    final fgAlpha = _combinedOpacity(fg, fill.foregroundTransparency);
    final fgHex = fg == null ? '#ffffff' : _hex(fg);

    // Canvas [PatternFillBuilder] only tiles ids 2–16; unknown ids fall
    // back to solid. Match that here (do not invent a hatch for pattern>16).
    if (fill.pattern >= 2 && fill.pattern <= 16) {
      // package:pdf only resolves url(#…) for gradients — hatch patterns
      // become hollow without this solid fallback.
      if (pdfCompat) {
        return 'fill="$fgHex" fill-opacity="${_n(fgAlpha)}"';
      }
      final bg =
          _resolveColor(fill.background, fill.themeBackgroundIndex, theme);
      final bgAlpha =
          bg == null ? 0.0 : _combinedOpacity(bg, fill.backgroundTransparency);
      final bgHex = bg == null ? '#ffffff' : _hex(bg);
      final id = 'pat-$paintId';
      // Match canvas PatternFillBuilder: 32px tile × scale 0.04 → 1.28".
      const tile = 1.28;
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
    // Canvas hatch stroke is 2px on a 32px tile at scale 0.04 → 0.08".
    final sw = 0.08;
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
      _ => // 4: forward diagonal (caller only passes 2–16)
        '<line x1="0" y1="$t" x2="$t" y2="0" $common/>',
    };
  }

  /// Stroke paint attrs and arrow `marker-*` attrs separately so compound-line
  /// masks can clip the rail without also clipping arrowheads.
  ({String paint, String markers}) _strokeAttr(
    VsdxLine line,
    VsdxTheme theme,
    String paintId,
    StringBuffer defs, {
    required ({double minX, double minY, double width, double height}) bounds,
    bool includeMarkers = true,
  }) {
    if (!line.hasLine) return (paint: 'stroke="none"', markers: '');
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
    // Keep LineColorTrans as stroke-opacity even for gradients (canvas applies
    // line.transparency once via the stroke paint / shader, not twice).
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
      // Match canvas / fill gradients in userSpaceOnUse (not OBB).
      final cx = bounds.minX + bounds.width / 2;
      final cy = bounds.minY + bounds.height / 2;
      final r = math.max(bounds.width, bounds.height) * 0.6;
      if (g.type == VsdxGradientType.linear) {
        final dx = math.cos(g.angleRad) * r;
        final dy = math.sin(g.angleRad) * r;
        defs.write(
          '<linearGradient id="$id" gradientUnits="userSpaceOnUse" '
          'x1="${_n(cx - dx)}" y1="${_n(cy - dy)}" '
          'x2="${_n(cx + dx)}" y2="${_n(cy + dy)}">'
          '$stops</linearGradient>',
        );
      } else {
        defs.write(
          '<radialGradient id="$id" gradientUnits="userSpaceOnUse" '
          'cx="${_n(cx)}" cy="${_n(cy)}" r="${_n(r)}">'
          '$stops</radialGradient>',
        );
      }
      strokePaint = 'stroke="url(#$id)" stroke-opacity="${_n(alpha)}"';
    }
    final markers = StringBuffer();
    // PDF backends ignore <marker>; callers bake geometry via [_bakeArrows].
    if (!_bakeArrows && includeMarkers) {
      // Prefer explicit tip colours over context-stroke: many viewers (and
      // PDF) ignore context-stroke, and gradient strokes would otherwise
      // leave arrowheads unpainted or wrong.
      if (line.hasBeginArrow) {
        final tip = _arrowTipPaint(line, theme, atEnd: false, fallbackHex: hex);
        final mid = 'arrow-start-$paintId';
        final mw = _arrowMarkerSize(
          line.beginArrowSizeInches,
          line.beginArrow,
        );
        final body = _arrowMarkerBody(
          line.beginArrow,
          tipAtEnd: false,
          lineWeightInches: weight,
          markerSizeInches: mw,
          colorHex: tip.hex,
          opacity: tip.opacity,
        );
        defs.write(
          '<marker id="$mid" markerUnits="userSpaceOnUse" overflow="visible" '
          'viewBox="0 0 10 10" refX="0" refY="5" '
          'markerWidth="${_n(mw)}" markerHeight="${_n(mw)}" orient="auto">'
          '$body</marker>',
        );
        markers.write(' marker-start="url(#$mid)"');
      }
      if (line.hasEndArrow) {
        final tip = _arrowTipPaint(line, theme, atEnd: true, fallbackHex: hex);
        final mid = 'arrow-end-$paintId';
        final mw = _arrowMarkerSize(line.endArrowSizeInches, line.endArrow);
        final body = _arrowMarkerBody(
          line.endArrow,
          tipAtEnd: true,
          lineWeightInches: weight,
          markerSizeInches: mw,
          colorHex: tip.hex,
          opacity: tip.opacity,
        );
        defs.write(
          '<marker id="$mid" markerUnits="userSpaceOnUse" overflow="visible" '
          'viewBox="0 0 10 10" refX="10" refY="5" '
          'markerWidth="${_n(mw)}" markerHeight="${_n(mw)}" '
          'orient="auto-start-reverse">'
          '$body</marker>',
        );
        markers.write(' marker-end="url(#$mid)"');
      }
    }
    final paint = '$strokePaint '
        'stroke-width="${_n(weight)}" stroke-linecap="$linecap" '
        'stroke-linejoin="$linejoin"'
        '${dash.isEmpty ? '' : ' stroke-dasharray="$dash"'}';
    return (paint: paint, markers: markers.toString());
  }

  /// SVG marker path for common Visio BeginArrow/EndArrow ids (subset of
  /// canvas [arrow_library]). Tip points to the end (right) when [tipAtEnd].
  String _arrowMarkerBody(
    int arrowId, {
    required bool tipAtEnd,
    double lineWeightInches = 0.01,
    double markerSizeInches = 0.125,
    String? colorHex,
    double opacity = 1.0,
  }) {
    // Work in tip-at-right space, then mirror for start markers.
    // filled / open choices mirror lib/render/arrow_library.dart.
    final (d, filled) = switch (arrowId) {
      3 => ('M 0 1 L 10 5 L 0 9', false), // open arrow (V stroke)
      1 => ('M 0 1 L 10 5 L 0 9 Z', false), // open triangle
      // Narrow triangles (canvas half-width 0.25).
      5 => ('M 0 2.5 L 10 5 L 0 7.5 Z', true),
      6 => ('M 0 2.5 L 10 5 L 0 7.5 Z', false),
      // Wide triangles (canvas reach 0.85, half-width 0.55).
      25 => ('M 1.5 -0.5 L 10 5 L 1.5 10.5 Z', true),
      26 => ('M 1.5 -0.5 L 10 5 L 1.5 10.5 Z', false),
      // Ball (10): canvas r=0.5 diameter≈size; circle-dot (13): r=0.4.
      10 => (
          'M 5 5 m -5,0 a 5,5 0 1,0 10,0 a 5,5 0 1,0 -10,0',
          true,
        ),
      13 => (
          'M 5 5 m -4,0 a 4,4 0 1,0 8,0 a 4,4 0 1,0 -8,0',
          true,
        ),
      14 => (
          'M 5 5 m -4,0 a 4,4 0 1,0 8,0 a 4,4 0 1,0 -8,0',
          false,
        ), // open circle
      34 => (
          'M 7.5 5 m -2,0 a 2,2 0 1,0 4,0 a 2,2 0 1,0 -4,0',
          false,
        ), // small open circle
      // Diamond tip at x=10 (canvas tip at origin); open diamond id 11.
      11 => ('M 0 5 L 5 1.5 L 10 5 L 5 8.5 Z', false),
      // Square right edge at tip (canvas Rect ends at x=0).
      15 => ('M 0 1 H 10 V 9 H 0 Z', true),
      16 => ('M 0 1 H 10 V 9 H 0 Z', false),
      7 || 12 => ('M 0 1 L 10 5 L 0 9 L 2 5 Z', true), // stealth
      // Filled chevron (31): canvas tip(0,0) wings(±0.5) notch(-0.4);
      // mapped into viewBox with reach 0.55 (overflow visible).
      31 => ('M 0 -4.091 L 10 5 L 0 14.091 L 2.727 5 Z', true),
      8 => ('M 0 1 L 10 5 L 0 9 L 2 5 Z', false), // open stealth
      9 => (
          'M 0 1 L 10 5 L 0 9 Z M -2 0.5 L 0 1 L 0 9 L -2 9.5 Z',
          true,
        ), // fletched
      17 => ('M 5 1 V 9', false), // single hash (backslash/one)
      18 => ('M 7 1 V 9 M 4.5 1 V 9', false), // double hash / exactly one
      19 => ('M 7 1 V 9', false), // crow's foot one
      20 => ('M 10 5 L 2 1 M 10 5 L 2 5 M 10 5 L 2 9', false), // crow's foot many
      21 => (
          'M 4 5 m -1.8,0 a 1.8,1.8 0 1,0 3.6,0 a 1.8,1.8 0 1,0 -3.6,0 '
          'M 7 1 V 9',
          false,
        ), // optional one
      22 => (
          'M 6 5 m -1.8,0 a 1.8,1.8 0 1,0 3.6,0 a 1.8,1.8 0 1,0 -3.6,0 '
          'M 4 5 L 0 1 M 4 5 L 0 5 M 4 5 L 0 9',
          false,
        ), // optional many
      23 => ('M 0 0.5 L 10 5 L 0 9.5 L 2.5 5 Z', true), // swept filled
      24 => ('M 0 0.5 L 10 5 L 0 9.5 L 2.5 5 Z', false), // swept open
      // Hatched triangle: canvas shadow (-0.3,-0.2)→(-0.7,0.2) → tip-end M 7 3 L 3 7.
      27 => ('M 0 1 L 10 5 L 0 9 Z M 7 3 L 3 7', false),
      28 => ('M 0 3.2 L 10 5 L 0 6.8 Z', true), // spear (filled thin)
      29 => ('M 4 1 L 10 5 L 4 9 Z M 0 1 L 6 5 L 0 9 Z', true), // double triangle
      30 => (
          'M 4 1 L 10 5 L 4 9 Z M 0 1 L 6 5 L 0 9 Z',
          false,
        ), // double open triangle
      32 => ('M 0 -4.091 L 10 5 L 0 14.091', false), // open chevron
      33 => ('M 10 5 L 2 1 M 10 5 L 0 5 M 10 5 L 2 9', false), // trident
      35 => ('M 0 2 L 10 5 L 0 8 L 2.5 5 Z', true), // long filled arrow
      _ => ('M 0 1 L 10 5 L 0 9 Z', true), // filled triangle (2/4/5/…)
    };
    final pathD = tipAtEnd ? d : _mirrorArrowD(d);
    final fillPaint = colorHex == null
        ? 'fill="context-stroke"'
        : 'fill="$colorHex" fill-opacity="${_n(opacity)}"';
    final strokePaint = colorHex == null
        ? 'stroke="context-stroke"'
        : 'stroke="$colorHex" stroke-opacity="${_n(opacity)}"';
    if (filled) {
      return '<path d="$pathD" $fillPaint stroke="none"/>';
    }
    // Match canvas: strokeWidth = lineWeight / sizeInches in local arrow
    // space. viewBox 0–10 maps to markerSizeInches → stroke in viewBox units.
    // No upper clamp — thick lines must keep proportional open-arrow strokes.
    final sw = markerSizeInches > 1e-9
        ? math.max(0.4, 10.0 * lineWeightInches / markerSizeInches)
        : 1.2;
    return '<path d="$pathD" fill="none" $strokePaint '
        'stroke-width="${_n(sw)}" stroke-linejoin="round"/>';
  }

  /// Rough mirror of simple marker paths about x=5 (for start arrows).
  String _mirrorArrowD(String d) {
    // Dedicated mirrors for the small set of templates above.
    return switch (d) {
      'M 0 1 L 10 5 L 0 9' => 'M 10 1 L 0 5 L 10 9',
      'M 0 1 L 10 5 L 0 9 Z' => 'M 10 1 L 0 5 L 10 9 Z',
      'M 0 2.5 L 10 5 L 0 7.5 Z' => 'M 10 2.5 L 0 5 L 10 7.5 Z',
      'M 1.5 -0.5 L 10 5 L 1.5 10.5 Z' => 'M 8.5 -0.5 L 0 5 L 8.5 10.5 Z',
      'M 0 1 L 10 5 L 0 9 L 2 5 Z' => 'M 10 1 L 0 5 L 10 9 L 8 5 Z',
      'M 0 -4.091 L 10 5 L 0 14.091 L 2.727 5 Z' =>
          'M 10 -4.091 L 0 5 L 10 14.091 L 7.273 5 Z',
      'M 0 -4.091 L 10 5 L 0 14.091' => 'M 10 -4.091 L 0 5 L 10 14.091',
      'M 0 5 L 5 1.5 L 10 5 L 5 8.5 Z' => 'M 10 5 L 5 1.5 L 0 5 L 5 8.5 Z',
      'M 0 1 H 10 V 9 H 0 Z' => d, // square tip-edge at both ends via orient
      'M 5 1 V 9' => d,
      'M 7 1 V 9' => 'M 3 1 V 9',
      'M 7 1 V 9 M 4.5 1 V 9' => 'M 3 1 V 9 M 5.5 1 V 9',
      'M 10 5 L 2 1 M 10 5 L 2 5 M 10 5 L 2 9' =>
        'M 0 5 L 8 1 M 0 5 L 8 5 M 0 5 L 8 9',
      'M 4 5 m -1.8,0 a 1.8,1.8 0 1,0 3.6,0 a 1.8,1.8 0 1,0 -3.6,0 M 7 1 V 9' =>
        'M 6 5 m -1.8,0 a 1.8,1.8 0 1,0 3.6,0 a 1.8,1.8 0 1,0 -3.6,0 M 3 1 V 9',
      'M 6 5 m -1.8,0 a 1.8,1.8 0 1,0 3.6,0 a 1.8,1.8 0 1,0 -3.6,0 '
          'M 4 5 L 0 1 M 4 5 L 0 5 M 4 5 L 0 9' =>
        'M 4 5 m -1.8,0 a 1.8,1.8 0 1,0 3.6,0 a 1.8,1.8 0 1,0 -3.6,0 '
            'M 6 5 L 10 1 M 6 5 L 10 5 M 6 5 L 10 9',
      'M 0 0.5 L 10 5 L 0 9.5 L 2.5 5 Z' => 'M 10 0.5 L 0 5 L 10 9.5 L 7.5 5 Z',
      'M 0 2 L 10 5 L 0 8 L 2.5 5 Z' => 'M 10 2 L 0 5 L 10 8 L 7.5 5 Z',
      'M 0 1 L 10 5 L 0 9 Z M -2 0.5 L 0 1 L 0 9 L -2 9.5 Z' =>
        'M 10 1 L 0 5 L 10 9 Z M 12 0.5 L 10 1 L 10 9 L 12 9.5 Z',
      'M 0 1 L 10 5 L 0 9 Z M 7 3 L 3 7' =>
        'M 10 1 L 0 5 L 10 9 Z M 3 3 L 7 7',
      'M 0 3.2 L 10 5 L 0 6.8 Z' => 'M 10 3.2 L 0 5 L 10 6.8 Z',
      'M 4 1 L 10 5 L 4 9 Z M 0 1 L 6 5 L 0 9 Z' =>
        'M 6 1 L 0 5 L 6 9 Z M 10 1 L 4 5 L 10 9 Z',
      'M 10 5 L 2 1 M 10 5 L 0 5 M 10 5 L 2 9' =>
        'M 0 5 L 8 1 M 0 5 L 10 5 M 0 5 L 8 9',
      'M 7.5 5 m -2,0 a 2,2 0 1,0 4,0 a 2,2 0 1,0 -4,0' => d,
      _ => d, // circles are symmetric
    };
  }

  /// Visio BeginArrowSize / EndArrowSize (inches) → SVG markerWidth under
  /// `markerUnits="userSpaceOnUse"`.
  ///
  /// Canvas draws `scale(sizeInches)` over a local path whose tip→base reach
  /// varies by id (spear ≈ 1.4, chevron ≈ 0.55). SVG templates span viewBox
  /// 0–10, so markerWidth = sizeInches × canvasReach matches visual length.
  double _arrowMarkerSize(double sizeInches, int arrowId) {
    final s = sizeInches <= 0 ? 0.125 : sizeInches;
    return (s * _arrowCanvasReach(arrowId)).clamp(0.02, 1.5);
  }

  /// Tip→base extent in canvas `arrow_library` local units (tip at origin).
  double _arrowCanvasReach(int arrowId) {
    return switch (arrowId) {
      9 => 1.2,
      15 || 16 || 25 || 26 => 0.85,
      23 || 24 => 1.1,
      28 => 1.4,
      29 || 30 => 1.2,
      31 || 32 => 0.55,
      33 => 0.85,
      35 => 1.5,
      _ => 1.0,
    };
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
    final resolved = _resolveForeignImage(shape);
    if (resolved == null) {
      _writeImagePlaceholder(buf, shape, indent: indent);
      return;
    }
    // Clip + SoftEdges wrap both bitmaps and vector metafiles (canvas does).
    final nest = _writeImageDecorationsOpen(buf, shape, indent: indent);
    _writeForeignImageContent(
      buf,
      shape,
      indent: '$indent  ',
      resolved: resolved,
    );
    _writeImageDecorationsClose(buf, indent: indent, geomClipped: nest);
  }

  /// Resolve Foreign media to a Flutter-decodable bitmap or vector metafile.
  ({String? mime, List<int>? bytes, MetafileDrawing? vectorDrawing})?
      _resolveForeignImage(VsdxShape shape) {
    final src = _images.findByPart(shape.imagePartName ?? '');
    if (!embedImages || src == null) return null;
    if (src.isFlutterDecodable) {
      return (
        mime: src.mimeType.isEmpty ? 'image/png' : src.mimeType,
        bytes: src.bytes,
        vectorDrawing: null,
      );
    }
    final raster = extractMetafileRaster(
      Uint8List.fromList(src.bytes),
      mimeType: src.mimeType,
    );
    if (raster != null) {
      return (mime: 'image/bmp', bytes: raster, vectorDrawing: null);
    }
    final drawing = parseMetafileDrawing(
      Uint8List.fromList(src.bytes),
      mimeType: src.mimeType,
      partName: src.partName,
    );
    if (drawing != null && !drawing.isEmpty) {
      return (mime: null, bytes: null, vectorDrawing: drawing);
    }
    return null;
  }

  /// Bitmap / metafile content without SoftEdges or box clip (body + reflection).
  void _writeForeignImageContent(
    StringBuffer buf,
    VsdxShape shape, {
    required String indent,
    String toneIdSuffix = '',
    ({String? mime, List<int>? bytes, MetafileDrawing? vectorDrawing})?
        resolved,
  }) {
    final media = resolved ?? _resolveForeignImage(shape);
    if (media == null) {
      _writeImagePlaceholder(buf, shape, indent: indent);
      return;
    }
    final toneAttr = _imageToneFilterAttr(
      shape,
      buf,
      indent: indent,
      idSuffix: toneIdSuffix,
    );
    if (media.vectorDrawing != null) {
      if (toneAttr.isNotEmpty) {
        buf.writeln('$indent<g$toneAttr>');
      }
      _writeMetafileDrawing(
        buf,
        shape,
        media.vectorDrawing!,
        indent: toneAttr.isNotEmpty ? '$indent  ' : indent,
      );
      if (toneAttr.isNotEmpty) {
        buf.writeln('$indent</g>');
      }
      return;
    }
    final mime = media.mime;
    final bytes = media.bytes;
    if (mime == null || bytes == null) {
      _writeImagePlaceholder(buf, shape, indent: indent);
      return;
    }
    final href = 'data:$mime;base64,${base64Encode(bytes)}';
    final ox = shape.imgOffsetXInches;
    final oy = shape.imgOffsetYInches;
    final iw = shape.effectiveImgWidth;
    final ih = shape.effectiveImgHeight;
    // Bitmap rows are Y-down — flip about the image rect centre (not the
    // shape centre) so ImgOffset* pan stays correct under FlipY.
    final uprightY = shape.flipY ? 1.0 : -1.0;
    final cx = ox + iw / 2;
    final cy = oy + ih / 2;
    final opacity = (1.0 - shape.imageTransparency).clamp(0.0, 1.0);
    final opacityAttr =
        opacity < 1.0 - 1e-9 ? ' opacity="${_n(opacity)}"' : '';
    buf.writeln(
      '$indent<g$toneAttr transform="translate(${_n(cx)} ${_n(cy)}) '
      'scale(1 ${_n(uprightY)}) '
      'translate(${_n(-cx)} ${_n(-cy)})">'
      '<image href="$href" x="${_n(ox)}" y="${_n(oy)}" '
      'width="${_n(iw)}" height="${_n(ih)}" '
      'preserveAspectRatio="none"$opacityAttr/></g>',
    );
  }

  /// Blur / Brightness / Contrast filter for Foreign images (skip in pdfCompat).
  String _imageToneFilterAttr(
    VsdxShape shape,
    StringBuffer buf, {
    required String indent,
    String idSuffix = '',
  }) {
    if (pdfCompat) return '';
    final blur = shape.imageBlur.clamp(0.0, 1.0);
    final bright = shape.imageBrightness.clamp(0.0, 1.0);
    final contrast = shape.imageContrast.clamp(0.0, 1.0);
    if (blur <= 1e-6 &&
        (bright - 0.5).abs() <= 1e-3 &&
        (contrast - 0.5).abs() <= 1e-3) {
      return '';
    }
    final id = 'img-tone-${shape.id}$idSuffix';
    final c = 1.0 + (contrast - 0.5) * 2.0;
    final b = (bright - 0.5) * 2.0;
    final t = (1.0 - c) * 0.5 + b;
    final sigma = 0.08 * blur;
    final parts = StringBuffer();
    if (blur > 1e-6) {
      parts.write(
        '<feGaussianBlur in="SourceGraphic" stdDeviation="${_n(sigma)}" '
        'result="blur"/>',
      );
    }
    final toneIn = blur > 1e-6 ? 'blur' : 'SourceGraphic';
    if ((bright - 0.5).abs() > 1e-3 || (contrast - 0.5).abs() > 1e-3) {
      parts.write(
        '<feColorMatrix in="$toneIn" type="matrix" values="'
        '${_n(c)} 0 0 0 ${_n(t)} '
        '0 ${_n(c)} 0 0 ${_n(t)} '
        '0 0 ${_n(c)} 0 ${_n(t)} '
        '0 0 0 1 0"/>',
      );
    } else {
      parts.write('<feMerge><feMergeNode in="blur"/></feMerge>');
    }
    buf.writeln('$indent<defs><filter id="$id">$parts</filter></defs>');
    return ' filter="url(#$id)"';
  }

  /// Open clipPath + SoftEdges groups for a Foreign image (bitmap or metafile).
  ///
  /// Nests geometry clip ∩ shape-box clip so ImgOffset overflow is cropped
  /// the same way as canvas (`clipPath` then `clipRect(bounds)`).
  /// Returns whether a geometry clip group was opened.
  bool _writeImageDecorationsOpen(
    StringBuffer buf,
    VsdxShape shape, {
    required String indent,
  }) {
    String? clipD;
    for (final geom in shape.geometries) {
      if (geom.noShow) continue;
      final d = _geometryToD(
        geom,
        shape.width,
        shape.height,
        roundingInches: shape.line.roundingInches,
      );
      if (d.isNotEmpty) {
        clipD = d;
        break;
      }
    }
    final boxId = 'img-box-${shape.id}';
    buf.writeln(
      '$indent<defs><clipPath id="$boxId">'
      '<rect x="0" y="0" width="${_n(shape.width)}" '
      'height="${_n(shape.height)}"/></clipPath></defs>',
    );
    buf.writeln('$indent<g clip-path="url(#$boxId)">');
    if (clipD != null) {
      final geomId = 'img-clip-${shape.id}';
      buf.writeln(
        '$indent  <defs><clipPath id="$geomId">'
        '<path d="$clipD"/></clipPath></defs>',
      );
      buf.writeln('$indent  <g clip-path="url(#$geomId)">');
    }
    final softDefs = StringBuffer();
    final softFilter = _softEdgesFilterAttr(
      shape,
      'img-${shape.id}',
      softDefs,
      bounds: (
        minX: 0,
        minY: 0,
        width: shape.width,
        height: shape.height,
      ),
    );
    if (softDefs.isNotEmpty) {
      buf.writeln('$indent  <defs>$softDefs</defs>');
    }
    final softAttr = softFilter == null ? '' : ' filter="$softFilter"';
    buf.writeln('$indent  <g$softAttr>');
    return clipD != null;
  }

  void _writeImageDecorationsClose(
    StringBuffer buf, {
    required String indent,
    required bool geomClipped,
  }) {
    buf.writeln('$indent  </g>'); // soft
    if (geomClipped) buf.writeln('$indent  </g>');
    buf.writeln('$indent</g>'); // box clip
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
    final ox = shape.imgOffsetXInches;
    final oy = shape.imgOffsetYInches;
    final iw = shape.effectiveImgWidth;
    final ih = shape.effectiveImgHeight;
    final sx = iw / dw;
    // GDI metafiles are Y-down; flip once into page Y-up — unless FlipY
    // already mirrored the parent XForm (same cancel-avoidance as bitmaps /
    // canvas [_paintImage]). Map into the ImgOffset*/ImgWidth/Height rect.
    final gdiFlipY = !shape.flipY;
    final sy = ih / dh * (gdiFlipY ? -1.0 : 1.0);
    final ty = gdiFlipY ? oy + ih : oy;
    final opacity = (1.0 - shape.imageTransparency).clamp(0.0, 1.0);
    final opacityAttr =
        opacity < 1.0 - 1e-9 ? ' opacity="${_n(opacity)}"' : '';
    buf.writeln(
      '$indent<g$opacityAttr transform="translate(${_n(ox)} ${_n(ty)}) '
      'scale(${_n(sx)} ${_n(sy)}) '
      'translate(${_n(-drawing.minX)} ${_n(-drawing.minY)})">',
    );
    for (final op in drawing.ops) {
      if (op is MetafilePathOp) {
        _writeMetafilePathOp(buf, op, indent: '$indent  ');
      } else if (op is MetafileTextOp) {
        _writeMetafileTextOp(
          buf,
          op,
          indent: '$indent  ',
          unflipGlyphs: gdiFlipY,
        );
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
    bool unflipGlyphs = true,
  }) {
    if (op.text.isEmpty) return;
    final size = math.max(op.fontHeight.abs(), 1.0);
    final face = (op.face == null || op.face!.isEmpty)
        ? 'Arial'
        : _esc(op.face!);
    // TA_CENTER = 6, TA_RIGHT = 2 (low bits) — match canvas [_paintText].
    final alignBits = op.align & 0x07;
    final anchor = switch (alignBits) {
      6 => 'middle',
      2 => 'end',
      _ => 'start',
    };
    // When the metafile group applies GDI→Y-up (scale … -sy), un-flip glyphs
    // so text stays upright. Skip when FlipY already cancelled that flip.
    final glyphXf = unflipGlyphs
        ? 'translate(${_n(op.x)} ${_n(op.y)}) scale(1 -1)'
        : 'translate(${_n(op.x)} ${_n(op.y)})';
    buf.writeln(
      '$indent<g transform="$glyphXf">'
      '<text x="0" y="0" text-anchor="$anchor" fill="${_argbCss(op.argb)}" '
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

  /// Centre a tight plate + glyphs on a connector midpoint (canvas loose edge).
  void _writeLooseEdgeLabel(
    StringBuffer buf, {
    required VsdxShape shape,
    required VsdxTheme theme,
    required VsdxPage page,
    required List<VsdxTextRun> runs,
    required double pinX,
    required double pinY,
    required double angleRad,
    required int textDirection,
    required VsdxColor? backgroundColor,
    required double backgroundTransparency,
    required String indent,
  }) {
    final paras = _splitSvgParagraphs(runs);
    final lines = <({
      List<(String text, VsdxTextRun run)> segs,
      double lineH,
      double width,
    })>[];
    var totalH = 0.0;
    var maxW = 0.0;
    for (final p in paras) {
      final lineH = _svgParaLineHeight(p.segs, p.style);
      // Natural width — no wrap into the connector's Width×Height box.
      var w = 0.0;
      for (final (raw, run) in p.segs) {
        w += _estSvgTextWidth(raw, run.charStyle);
      }
      lines.add((segs: p.segs, lineH: lineH, width: w));
      totalH += lineH;
      if (w > maxW) maxW = w;
    }
    if (lines.isEmpty) return;
    totalH = math.max(totalH, 0.04);
    maxW = math.max(maxW, 0.04);

    final plate = backgroundColor ?? page.backgroundColor ?? VsdxColor.white;
    final bgOp = backgroundColor != null
        ? _combinedOpacity(backgroundColor, backgroundTransparency)
        : 1.0;
    const pad = 0.03;
    final angle =
        angleRad != 0 ? ' rotate(${_n(angleRad * 180 / math.pi)})' : '';
    final dirRot = textDirection == 1 ? ' rotate(-90)' : '';
    buf.writeln(
      '$indent<g transform="translate(${_n(pinX)} ${_n(pinY)})$angle$dirRot">'
      '<rect x="${_n(-maxW / 2 - pad)}" y="${_n(-totalH / 2 - pad)}" '
      'width="${_n(maxW + 2 * pad)}" height="${_n(totalH + 2 * pad)}" '
      'rx="0.02" fill="${_hex(plate)}" '
      'fill-opacity="${_n(bgOp)}" stroke="none"/>'
      '<g transform="scale(1 -1)">',
    );
    var yTop = -totalH / 2;
    for (final line in lines) {
      var bodyFont = 0.14;
      for (final (_, run) in line.segs) {
        if (run.text.isNotEmpty && run.charStyle.fontSizeInches > 0) {
          bodyFont = run.charStyle.fontSizeInches;
          break;
        }
      }
      final yRel = yTop + line.lineH / 2;
      final yText = pdfCompat ? yRel + bodyFont * 0.35 : yRel;
      final baseline = pdfCompat ? '' : ' dominant-baseline="middle"';
      final body = StringBuffer();
      for (var si = 0; si < line.segs.length; si++) {
        final (raw, run) = line.segs[si];
        _writeStyledTspans(
          body,
          raw: raw,
          style: run.charStyle,
          theme: theme,
          xAttr: si == 0 ? 'x="0"' : null,
        );
      }
      buf.writeln(
        '$indent  <text xml:space="preserve" text-anchor="middle"$baseline '
        'y="${_n(yText)}">$body</text>',
      );
      yTop += line.lineH;
    }
    buf.writeln('$indent</g></g>');
  }

  void _writeText(
    StringBuffer buf,
    VsdxShape shape,
    VsdxTheme theme,
    VsdxPage page, {
    required String paintIdScope,
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

    // Loose edge labels (no TxtPin): canvas centres a tight plate + glyphs on
    // the route midpoint and returns — do not flow into Width×Height.
    final looseEdge = shape.isGlueableConnector &&
        block.pinXInches == null &&
        block.pinYInches == null;
    if (looseEdge) {
      _writeLooseEdgeLabel(
        buf,
        shape: shape,
        theme: theme,
        page: page,
        runs: runs,
        pinX: pinX,
        pinY: pinY,
        angleRad: block.angleRad,
        textDirection: block.textDirection,
        backgroundColor: block.backgroundColor,
        backgroundTransparency: block.backgroundTransparency,
        indent: indent,
      );
      return;
    }
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

    // CurvedText: canvas disables arc layout for every glueable connector.
    // package:pdf ignores <textPath> — fall through to rectangular layout.
    if (shape.curvedText && !shape.isGlueableConnector && !pdfCompat) {
      _writeCurvedText(
        buf,
        shape: shape,
        theme: theme,
        runs: runs,
        pinX: pinX,
        pinY: pinY,
        lpx: lpx,
        lpy: lpy,
        tw: tw,
        th: th,
        ml: ml,
        mr: mr,
        mt: mt,
        mb: mb,
        angleRad: block.angleRad,
        textDirection: block.textDirection,
        paintIdScope: paintIdScope,
        indent: indent,
      );
      return;
    }

    // Split into paragraphs (Visio `\n` / `<pp>`). Each keeps its own
    // HorzAlign / Ind* / Sp* / Bullet* (canvas [_paintParagraphBlock]).
    final paras = _splitSvgParagraphs(runs);
    // TextDirection=1: match canvas — rotate into a vertical band, then lay
    // out in the swapped width×height frame (margins remapped likewise).
    var layoutW = tw;
    var layoutH = th;
    var layoutMl = ml;
    var layoutMr = mr;
    var layoutMt = mt;
    var layoutMb = mb;
    final vertical = block.textDirection == 1;
    if (vertical) {
      layoutW = th;
      layoutH = tw;
      layoutMl = mt;
      layoutMr = mb;
      layoutMt = mr;
      layoutMb = ml;
    }
    final layouts = <({
      VsdxParaStyle style,
      List<(String text, VsdxTextRun run)> segs,
      double lineH,
      double yTop,
      bool showBullet,
      double textBandX,
    })>[];
    var cursor = 0.0;
    for (final p in paras) {
      cursor += p.style.spaceBeforeInches;
      final lineH = _svgParaLineHeight(p.segs, p.style);
      final indentL = p.style.indentLeftInches;
      final indentF = p.style.indentFirstInches;
      final hasBullet = p.style.bullet != 0;
      final bulletGap = hasBullet
          ? (p.style.textPosAfterBulletInches > 0
              ? p.style.textPosAfterBulletInches
              : 0.18)
          : 0.0;
      // IndFirst applies to the first line only (Visio); body lines use IndLeft.
      final bodyBandX = layoutMl + indentL + (hasBullet ? bulletGap : 0.0);
      final firstBandX =
          hasBullet ? bodyBandX : layoutMl + indentL + indentF;
      final availRest = math.max(
        0.04,
        layoutW - layoutMr - p.style.indentRightInches - bodyBandX,
      );
      final availFirst = math.max(
        0.04,
        layoutW - layoutMr - p.style.indentRightInches - firstBandX,
      );
      final wrapped = _wrapSvgSegs(
        p.segs,
        availRest,
        firstLineMaxWidth: availFirst,
      );
      for (var li = 0; li < wrapped.length; li++) {
        layouts.add((
          style: p.style,
          segs: wrapped[li],
          lineH: lineH,
          yTop: cursor,
          showBullet: hasBullet && li == 0,
          textBandX: li == 0 ? firstBandX : bodyBandX,
        ));
        cursor += lineH;
      }
      cursor += p.style.spaceAfterInches;
    }
    final textH = math.max(cursor, 0.04);
    final contentBand = layoutH - layoutMt - layoutMb;
    final yCenter = switch (block.verticalAlign) {
      VsdxVertAlign.top => layoutH - layoutMt - textH / 2,
      VsdxVertAlign.bottom => layoutMb + textH / 2,
      // Content-band centre; when taller than the band, clamp like canvas
      // (grow downward from the top margin).
      VsdxVertAlign.middle => textH > contentBand + 1e-9
          ? layoutH - layoutMt - textH / 2
          : layoutMb + contentBand / 2,
    };

    // Text glyphs: block-local → upright (scale 1,-1). One <text> per
    // wrapped line so HorzAlign / indent can differ across lines.
    final textXf = StringBuffer('$xf');
    if (vertical) {
      textXf.write(
        ' translate(${_n(tw / 2)} ${_n(th / 2)}) rotate(-90) '
        'translate(${_n(-th / 2)} ${_n(-tw / 2)})',
      );
    }
    textXf.write(' translate(0 ${_n(yCenter)})');
    textXf.write(' scale(1 -1)');
    buf.writeln('$indent<g transform="$textXf">');
    for (final layout in layouts) {
      final style = layout.style;
      final indentL = style.indentLeftInches;
      final indentF = style.indentFirstInches;
      final textBandX = layout.textBandX;
      final bandRight = layoutW - layoutMr - style.indentRightInches;
      final (anchor, xBody) = switch (style.horizontalAlign) {
        VsdxHorzAlign.left || VsdxHorzAlign.justify => (
            'start',
            textBandX,
          ),
        VsdxHorzAlign.right => (
            'end',
            bandRight,
          ),
        VsdxHorzAlign.center => (
            'middle',
            textBandX + (bandRight - textBandX) / 2,
          ),
      };
      // y relative to cluster centre (Y-down after scale).
      final yRel = layout.yTop + layout.lineH / 2 - textH / 2;
      // package:pdf ignores dominant-baseline — shift by font size (not SpLine
      // lineH) so absolute line spacing does not push glyphs off-band.
      var bodyFont = 0.14;
      for (final (_, run) in layout.segs) {
        if (run.text.isNotEmpty && run.charStyle.fontSizeInches > 0) {
          bodyFont = run.charStyle.fontSizeInches;
          break;
        }
      }
      final yText = pdfCompat ? yRel + bodyFont * 0.35 : yRel;
      final baseline =
          pdfCompat ? '' : ' dominant-baseline="middle"';

      if (layout.showBullet) {
        final glyph = _svgBulletGlyph(style);
        // Match canvas: BulletFontSize, else first non-empty run size.
        var bFs = bodyFont;
        if (style.bulletFontSizeInches != null &&
            style.bulletFontSizeInches! > 0) {
          bFs = style.bulletFontSizeInches!;
        }
        var bx = layoutMl + indentL + indentF;
        // Canvas: when the bullet overlaps the body band start, push it left.
        final bulletW = _estSvgTextWidth(
          glyph,
          VsdxCharStyle.defaults.copyWith(fontSizeInches: bFs),
        );
        if (bx > textBandX - bulletW) {
          bx = textBandX - bulletW - 0.04;
        }
        buf.writeln(
          '$indent  <text xml:space="preserve" text-anchor="start"$baseline '
          'y="${_n(yText)}">'
          '<tspan x="${_n(bx)}" font-size="${_n(bFs)}" '
          '${style.bulletFont != null ? 'font-family="${_esc(style.bulletFont!)}" ' : ''}'
          'fill="#222222">${_esc(glyph)}</tspan></text>',
        );
      }

      final body = StringBuffer();
      for (var si = 0; si < layout.segs.length; si++) {
        final (raw, run) = layout.segs[si];
        _writeStyledTspans(
          body,
          raw: raw,
          style: run.charStyle,
          theme: theme,
          xAttr: si == 0 ? 'x="${_n(xBody)}"' : null,
        );
      }
      // Approximate Visio Justify on the body band only (bullet is separate).
      var justifyAttr = '';
      if (style.horizontalAlign == VsdxHorzAlign.justify) {
        final bandW = math.max(0.04, bandRight - textBandX);
        var natural = 0.0;
        for (final (raw, run) in layout.segs) {
          natural += _estSvgTextWidth(raw, run.charStyle);
        }
        if (natural > 1e-6 && natural < bandW * 0.98) {
          justifyAttr =
              ' textLength="${_n(bandW)}" lengthAdjust="spacing"';
        }
      }
      // Preserve consecutive spaces (canvas TextPainter does; SVG defaults fold).
      buf.writeln(
        '$indent  <text xml:space="preserve" text-anchor="$anchor"$baseline'
        '$justifyAttr '
        'y="${_n(yText)}">$body</text>',
      );
    }
    buf.writeln('$indent</g>');
  }

  /// Greedy wrap of rich-text segments to [maxWidth] inches (canvas maxWidth).
  ///
  /// When [firstLineMaxWidth] is set (IndFirst), only the first wrapped line
  /// uses that narrower band; subsequent lines use [maxWidth].
  List<List<(String text, VsdxTextRun run)>> _wrapSvgSegs(
    List<(String text, VsdxTextRun run)> segs,
    double maxWidth, {
    double? firstLineMaxWidth,
  }) {
    if (segs.isEmpty) return [<(String, VsdxTextRun)>[]];
    final lines = <List<(String, VsdxTextRun)>>[];
    var cur = <(String, VsdxTextRun)>[];
    var curW = 0.0;
    var lineMax = firstLineMaxWidth ?? maxWidth;

    void flush() {
      if (cur.isEmpty) return;
      lines.add(cur);
      cur = <(String, VsdxTextRun)>[];
      curW = 0.0;
      lineMax = maxWidth;
    }

    void append(String unit, VsdxTextRun run, double uw) {
      // Merge with the previous piece when the run matches so a wrapped line
      // still emits contiguous text (tests / search / copy-paste).
      if (cur.isNotEmpty && identical(cur.last.$2, run)) {
        cur[cur.length - 1] = (cur.last.$1 + unit, run);
      } else {
        cur.add((unit, run));
      }
      curW += uw;
    }

    for (final (text, run) in segs) {
      for (final unit in _svgWrapUnits(text)) {
        final uw = _estSvgTextWidth(unit, run.charStyle);
        final isBlank = unit.trim().isEmpty;
        if (curW > 1e-9 && curW + uw > lineMax && !isBlank) {
          flush();
        }
        if (cur.isEmpty && isBlank) continue;
        if (uw > lineMax && unit.length > 1 && !isBlank) {
          // Hard-break oversized tokens (code units; good enough for Latin/CJK).
          for (var i = 0; i < unit.length; i++) {
            final ch = unit[i];
            final cw = _estSvgTextWidth(ch, run.charStyle);
            if (curW > 1e-9 && curW + cw > lineMax) flush();
            append(ch, run, cw);
          }
          continue;
        }
        append(unit, run, uw);
      }
    }
    flush();
    return lines.isEmpty ? [segs] : lines;
  }

  /// Split [text] into wrap units (whitespace runs and word runs).
  List<String> _svgWrapUnits(String text) {
    final out = <String>[];
    final buf = StringBuffer();
    bool? inSpace;
    void flush() {
      if (buf.isEmpty) return;
      out.add(buf.toString());
      buf.clear();
    }

    for (final r in text.runes) {
      final ch = String.fromCharCode(r);
      final sp = ch == ' ' || ch == '\t';
      if (inSpace != null && inSpace != sp) flush();
      inSpace = sp;
      buf.write(ch);
    }
    flush();
    return out;
  }

  /// Approximate advance width for SVG layout (no font metrics in pure Dart).
  /// Matches canvas: FontScale/letter-spacing tracking and 0.7× super/sub size.
  double _estSvgTextWidth(String text, VsdxCharStyle style) {
    var fs = math.max(style.fontSizeInches, 0.04);
    switch (style.position) {
      case VsdxTextPosition.superscript:
      case VsdxTextPosition.subscript:
        fs *= 0.7;
      case VsdxTextPosition.normal:
        break;
    }
    var w = 0.0;
    var n = 0;
    final smallCaps = style.style.smallCaps;
    for (final r in text.runes) {
      n++;
      // Match canvas / SVG synthetic small-caps (lowercase → 0.78× capitals).
      final chFs = smallCaps &&
              r >= 0x61 &&
              r <= 0x7a
          ? fs * 0.78
          : fs;
      if (r == 0x20 || r == 0x09) {
        w += chFs * 0.33;
      } else if (r >= 0x2E80) {
        w += chFs; // CJK / wide ideographs
      } else {
        w += chFs * 0.55;
      }
    }
    var tracking = style.letterSpacingInches;
    final scale = style.fontScale <= 0 ? 1.0 : style.fontScale.clamp(0.1, 4.0);
    if ((scale - 1.0).abs() > 1e-6) {
      tracking += fs * (scale - 1.0) * 0.15;
    }
    // Flutter letterSpacing applies between glyphs ≈ (n-1) gaps.
    if (n > 1 && tracking.abs() > 1e-12) {
      w += tracking * (n - 1);
    }
    return w;
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
      // Match canvas: absolute SpLine is the line advance in inches (may be
      // smaller than the font size).
      return style.lineSpacingAbsoluteInches;
    }
    // [lineSpacing] is already the Visio SpLine multiple (e.g. -1.2 → 1.2);
    // do not multiply by an extra 1.2 (that inflated relative spacing vs canvas).
    final mult = style.lineSpacingSolid ? 1.0 : style.lineSpacing;
    return fs * (mult <= 0 ? 1.0 : mult);
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

  /// Place glyphs along a quadratic arc (draw.io CurvedText / canvas path).
  void _writeCurvedText(
    StringBuffer buf, {
    required VsdxShape shape,
    required VsdxTheme theme,
    required List<VsdxTextRun> runs,
    required double pinX,
    required double pinY,
    required double lpx,
    required double lpy,
    required double tw,
    required double th,
    required double ml,
    required double mr,
    required double mt,
    required double mb,
    required double angleRad,
    required int textDirection,
    required String paintIdScope,
    required String indent,
  }) {
    final plain = _applyTextCase(
      runs.map((r) => r.text).join().replaceAll('\n', ' ').trim(),
      runs.isNotEmpty ? runs.first.charStyle.textCase : VsdxTextCase.normal,
    );
    if (plain.isEmpty) return;

    // Match canvas: TextDirection=1 rotates into a vertical band, then the
    // arc is laid out in the swapped width×height frame.
    var arcW = tw;
    var arcH = th;
    var arcMl = ml;
    var arcMr = mr;
    final vertical = textDirection == 1;
    if (vertical) {
      arcW = th;
      arcH = tw;
      arcMl = mt;
      arcMr = mb;
    }

    final midY = arcH * 0.58;
    final bulge = math.min(arcH * 0.32, arcH * 0.45);
    final x0 = arcMl;
    final x1 = arcW / 2;
    final x2 = arcW - arcMr;
    final y0 = midY;
    final y1 = midY - bulge;
    final y2 = midY;
    // Page/underlay-scoped — same as gradient/marker paint ids.
    final pathId = 'curved-$paintIdScope-${shape.id}';
    final style = runs.isNotEmpty ? runs.first.charStyle : VsdxCharStyle.defaults;
    final attrs = _charStyleSvgAttrs(style, theme);

    final xf = StringBuffer('translate(${_n(pinX)} ${_n(pinY)})');
    if (angleRad != 0) {
      xf.write(' rotate(${_n(angleRad * 180 / math.pi)})');
    }
    // Block lower-left → top-left + Y-down (same stack as rectangular text).
    xf.write(' translate(${_n(-lpx)} ${_n(-lpy)})');
    xf.write(' translate(0 ${_n(th)}) scale(1 -1)');
    if (vertical) {
      xf.write(
        ' translate(${_n(tw / 2)} ${_n(th / 2)}) rotate(-90) '
        'translate(${_n(-th / 2)} ${_n(-tw / 2)})',
      );
    }

    buf.writeln('$indent<g transform="$xf">');
    buf.writeln(
      '$indent  <path id="$pathId" fill="none" stroke="none" '
      'd="M ${_n(x0)} ${_n(y0)} Q ${_n(x1)} ${_n(y1)} ${_n(x2)} ${_n(y2)}"/>',
    );
    buf.writeln(
      '$indent  <text $attrs>'
      '<textPath href="#$pathId" startOffset="50%" '
      'text-anchor="middle" dominant-baseline="middle">'
      '${_esc(plain)}</textPath></text>',
    );
    buf.writeln('$indent</g>');
  }

  /// Emit one or more `<tspan>`s for a run. Small-caps are synthesised like
  /// canvas (lowercase → 0.78× capitals) — CSS `font-variant` is unreliable.
  void _writeStyledTspans(
    StringBuffer body, {
    required String raw,
    required VsdxCharStyle style,
    required VsdxTheme theme,
    String? xAttr,
  }) {
    final text = _applyTextCase(raw, style.textCase);
    final x = xAttr == null ? '' : '$xAttr ';
    if (!style.style.smallCaps || text.isEmpty) {
      final attrs =
          _charStyleSvgAttrs(style, theme, synthesizeSmallCaps: true);
      body.write('<tspan $x$attrs>${_esc(text)}</tspan>');
      return;
    }
    var fs = math.max(style.fontSizeInches, 0.04);
    switch (style.position) {
      case VsdxTextPosition.superscript:
      case VsdxTextPosition.subscript:
        fs *= 0.7;
      case VsdxTextPosition.normal:
        break;
    }
    final smallFs = fs * 0.78;
    final buf = StringBuffer();
    bool? bufLower;
    var first = true;
    void flush() {
      if (buf.isEmpty || bufLower == null) return;
      final chunk = buf.toString();
      buf.clear();
      final prefix = first ? x : '';
      first = false;
      final attrs = _charStyleSvgAttrs(
        style,
        theme,
        synthesizeSmallCaps: true,
        fontSizeOverride: bufLower! ? smallFs : null,
      );
      final glyph = bufLower! ? chunk.toUpperCase() : chunk;
      body.write('<tspan $prefix$attrs>${_esc(glyph)}</tspan>');
      bufLower = null;
    }

    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      final upper = ch.toUpperCase();
      final lower = ch.toLowerCase();
      final isLower = ch == lower && ch != upper;
      if (bufLower != null && bufLower != isLower) flush();
      bufLower = isLower;
      buf.write(ch);
    }
    flush();
  }

  String _applyTextCase(String text, VsdxTextCase c) => switch (c) {
        VsdxTextCase.allCaps => text.toUpperCase(),
        // Match canvas [_initialCaps]: uppercase the first letter of each word.
        VsdxTextCase.initialCaps => _initialCaps(text),
        VsdxTextCase.normal => text,
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

  String _charStyleSvgAttrs(
    VsdxCharStyle c,
    VsdxTheme theme, {
    bool synthesizeSmallCaps = false,
    double? fontSizeOverride,
  }) {
    final color = _resolveColor(c.color, c.themeColorIndex, theme) ??
        const VsdxColor(0xFF222222);
    final op = _combinedOpacity(color, c.transparency);
    var fs = math.max(c.fontSizeInches, 0.04);
    switch (c.position) {
      case VsdxTextPosition.superscript:
      case VsdxTextPosition.subscript:
        fs *= 0.7;
      case VsdxTextPosition.normal:
        break;
    }
    if (fontSizeOverride != null) fs = fontSizeOverride;
    // FontScale is a *width* scale in Visio — do not multiply font-size (that
    // also grows glyph height). Match canvas: approximate with letter-spacing.
    var letterSpacing = c.letterSpacingInches;
    if ((c.fontScale - 1.0).abs() > 1e-6) {
      letterSpacing += fs * (c.fontScale.clamp(0.1, 4.0) - 1.0) * 0.15;
    }
    // Match canvas fontFallback: Latin face then AsianFont for CJK glyphs.
    final family = _svgFontFamily(c.fontFamily, c.asianFont);
    final weight = c.style.bold ? 'bold' : 'normal';
    final italic = c.style.italic ? 'italic' : 'normal';
    final deco = <String>[
      if (c.underline || c.doubleUnderline) 'underline',
      if (c.strikethrough || c.doubleStrikethrough) 'line-through',
      if (c.overline) 'overline',
    ];
    final attrs = StringBuffer(
      'font-family="$family" font-size="${_n(fs)}" '
      'font-weight="$weight" font-style="$italic" '
      '${letterSpacing.abs() > 1e-9 ? 'letter-spacing="${_n(letterSpacing)}" ' : ''}'
      'fill="${_hex(color)}" fill-opacity="${_n(op)}"',
    );
    // Prefer synthetic small-caps tspans (canvas parity). Keep CSS variant
    // only for callers that have not synthesised (e.g. curved textPath).
    if (c.style.smallCaps && !synthesizeSmallCaps) {
      attrs.write(' font-variant="small-caps"');
    }
    if (deco.isNotEmpty) {
      attrs.write(' text-decoration="${deco.join(' ')}"');
      // Match canvas: when double-under meets single-strike (or reverse),
      // keep solid so one decoration is not promoted to double.
      final under = c.underline || c.doubleUnderline;
      final strike = c.strikethrough || c.doubleStrikethrough;
      final underDbl = c.doubleUnderline;
      final strikeDbl = c.doubleStrikethrough;
      final useDouble = under && strike && underDbl != strikeDbl
          ? false
          : (underDbl || strikeDbl);
      if (useDouble) {
        attrs.write(' style="text-decoration-style:double"');
      }
    }
    // letter-spacing already includes FontScale above — do not rewrite it
    // with the raw Character Letterspace cell.
    // package:pdf ignores baseline-shift — use canvas-matching dy offsets.
    final baseFs = math.max(c.fontSizeInches, 0.04);
    switch (c.position) {
      case VsdxTextPosition.superscript:
        if (pdfCompat) {
          attrs.write(' dy="${_n(-baseFs * 0.35)}"');
        } else {
          attrs.write(' baseline-shift="super"');
        }
      case VsdxTextPosition.subscript:
        if (pdfCompat) {
          attrs.write(' dy="${_n(baseFs * 0.2)}"');
        } else {
          attrs.write(' baseline-shift="sub"');
        }
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

  /// CSS font-family list: Latin face, then AsianFont (CJK), then sans-serif.
  String _svgFontFamily(String? latin, String? asian) {
    final parts = <String>[];
    void add(String? name) {
      if (name == null || name.isEmpty) return;
      final quoted = name.contains(RegExp(r'''[\s,"']'''))
          ? "'${_esc(name.replaceAll("'", ''))}'"
          : _esc(name);
      if (!parts.contains(quoted)) parts.add(quoted);
    }

    add(latin);
    add(asian);
    parts.add('sans-serif');
    return parts.join(', ');
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
