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

import 'package:logging/logging.dart';

import '../model/dash_pattern.dart';
import '../model/document.dart';
import '../model/effects.dart';
import '../model/elliptical_arc.dart';
import '../model/fill.dart';
import '../model/geometry.dart';
import '../model/image.dart';
import '../model/layer.dart';
import '../model/line.dart';
import '../model/nurbs.dart';
import '../model/page.dart';
import '../model/spline.dart';
import '../model/rich_text.dart';
import '../model/rounding.dart';
import '../model/shape.dart';
import '../model/shape_inside.dart';
import '../model/sketch_style.dart';
import '../model/table.dart';
import '../model/theme.dart';
import '../parser/metafile.dart';
import '../utils/color.dart';
import '../utils/gradient_math.dart';
import 'compound_stroke.dart';
import 'line_jumps.dart';

final _log = Logger('vsdx.export.svg');

typedef _InfiniteLineResolver = List<Offset2D>? Function(
  Offset2D p,
  Offset2D q,
);

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
    this.colorByLayer = false,
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

  /// Jump arc radius in page inches (matches canvas).
  final double lineJumpRadiusInches;

  /// Bake arrow markers into path geometry (PDF-friendly).
  final bool bakeArrowMarkers;

  /// Approximate filters for package:pdf SVG subset.
  final bool pdfCompat;

  /// Visio Color-by-Layer: paint with [VsdxLayer.color] when the shape is
  /// a member of a coloured layer (matches [VsdxPainter.colorByLayer]).
  final bool colorByLayer;

  bool get _bakeArrows => bakeArrowMarkers || pdfCompat;

  /// Current image registry, swapped in by [serializePage] / [serializeDocument].
  ImageRegistry _images = ImageRegistry.empty;

  /// Line-jump state for the page currently being serialised.
  bool _jumpsEnabled = false;
  List<List<Offset2D>> _jumpRoutes = const <List<Offset2D>>[];
  List<int?> _jumpCodes = const <int?>[];
  Map<int, int> _jumpZ = const <int, int>{};

  /// Active Color-by-Layer tint while writing a shape subtree.
  VsdxColor? _layerTint;
  double _layerTintTrans = 0;
  bool _textFlipX = false;
  bool _textFlipY = false;
  int _variationColorIndex = 0;
  int _variationStyleIndex = 0;

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
    _textFlipX = false;
    _textFlipY = false;
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
      _variationColorIndex = underlay.pageSheet.variationColorIndex ?? 0;
      _variationStyleIndex = underlay.pageSheet.variationStyleIndex ?? 0;
      // Jump state is per painted page — prepare underlay routes before drawing
      // so bare shape ids do not collide with the foreground sheet.
      _prepareLineJumpsSafely(underlay);
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
        _writeShapeSafely(
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
    _variationColorIndex = page.pageSheet.variationColorIndex ?? 0;
    _variationStyleIndex = page.pageSheet.variationStyleIndex ?? 0;
    _prepareLineJumpsSafely(page);
    final layers = _layerIds(page);
    final paintScope = 'p${page.id}';
    for (final shape in page.shapes) {
      _writeShapeSafely(
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

  void _prepareLineJumpsSafely(VsdxPage page) {
    try {
      _prepareLineJumps(page);
    } catch (error, stackTrace) {
      // Jump routing is decorative. Preserve ordinary shape output if one
      // malformed connector cannot be converted into a page-space polyline.
      _log.warning(
        'Connector route preparation failed for SVG page ${page.id}',
        error,
        stackTrace,
      );
      _jumpsEnabled = false;
      _jumpRoutes = const <List<Offset2D>>[];
      _jumpCodes = const <int?>[];
      _jumpZ = const <int, int>{};
    }
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
    final customRadius = shape.drawioLineJumpSizeInches;
    final rx = customRadius ??
        resolveLineJumpRadius(
          uiRadius: lineJumpRadiusInches,
          lineToLineInches: sheet.lineToLineXInches,
          jumpFactor: sheet.lineJumpFactorX,
        );
    final ry = customRadius ??
        resolveLineJumpRadius(
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
      customStyle: shape.drawioLineJumpStyle,
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
        !layerMembershipEnabled(
          page.layers,
          shape.layerMemberIds,
          visibleLayers,
        )) {
      return;
    }
    final prevTint = _layerTint;
    final prevTrans = _layerTintTrans;
    final prevTextFlipX = _textFlipX;
    final prevTextFlipY = _textFlipY;
    _textFlipX = _textFlipX != shape.flipX;
    _textFlipY = _textFlipY != shape.flipY;
    if (colorByLayer) {
      final src = layerColorSource(page.layers, shape.layerMemberIds);
      if (src?.color != null) {
        _layerTint = src!.color;
        _layerTintTrans = src.colorTrans.clamp(0.0, 1.0);
      } else if (shape.layerMemberIds.isNotEmpty) {
        // Explicit uncoloured membership resets an ancestor group's tint;
        // children without membership inherit it.
        _layerTint = null;
        _layerTintTrans = 0;
      }
    } else {
      _layerTint = null;
      _layerTintTrans = 0;
    }
    try {
      _writeShapeBody(
        buf,
        shape,
        theme,
        page,
        visibleLayers,
        paintIdScope: paintIdScope,
        indent: indent,
      );
    } finally {
      _layerTint = prevTint;
      _layerTintTrans = prevTrans;
      _textFlipX = prevTextFlipX;
      _textFlipY = prevTextFlipY;
    }
  }

  void _writeShapeSafely(
    StringBuffer buf,
    VsdxShape shape,
    VsdxTheme theme,
    VsdxPage page,
    Set<int>? visibleLayers, {
    required String paintIdScope,
    required String indent,
  }) {
    // Serialize into a temporary buffer so a failure cannot leave the final
    // SVG with an unterminated <g>, <a>, filter, or clipping element.
    final shapeBuffer = StringBuffer();
    try {
      _writeShape(
        shapeBuffer,
        shape,
        theme,
        page,
        visibleLayers,
        paintIdScope: paintIdScope,
        indent: indent,
      );
      buf.write(shapeBuffer);
    } catch (error, stackTrace) {
      _log.warning(
        'Skipping shape ${shape.id} after an SVG serialization failure',
        error,
        stackTrace,
      );
    }
  }

  void _writeShapeBody(
    StringBuffer buf,
    VsdxShape shape,
    VsdxTheme theme,
    VsdxPage page,
    Set<int>? visibleLayers, {
    required String paintIdScope,
    required String indent,
  }) {
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
    final opacity = shape.shapeOpacity;
    final opacityAttr = opacity < 1.0 - 1e-9 ? ' opacity="${_n(opacity)}"' : '';
    buf.writeln(
      '$indent<g transform="${transforms.join(' ')}"$opacityAttr>',
    );

    // Picture frames keep Geometry (fill/stroke/effects); paint it first so
    // the outer half of the stroke stays visible around the bitmap.
    var wroteGeom = false;
    var geomIndex = 0;
    // Canvas [_paintLineEndings] draws arrows once from the first strokeable
    // Geometry — do not attach markers/bake on every section.
    var arrowsAttached = false;
    final jumpD = _connectorJumpD(page, shape);
    // Match canvas / libvisio: ≥2 NoFill=0 sections → one evenodd fill path.
    final fillParts = <String>[];
    if (shape.fill.hasFill) {
      for (final geom in shape.geometries) {
        if (geom.noShow || geom.noFill) continue;
        final part = _geometryToD(
          geom,
          shape.width,
          shape.height,
          roundingInches: shape.line.roundingInches,
          infiniteLineResolver: (p, q) =>
              _infiniteLineEndpoints(page, shape, p, q),
        );
        if (part.isNotEmpty) fillParts.add(part);
      }
    }
    final compoundFill = fillParts.length >= 2;
    if (compoundFill) {
      wroteGeom = true;
      _writePath(
        buf,
        shape,
        theme,
        page,
        d: fillParts.join(' '),
        noFill: false,
        noLine: true,
        fillRule: 'evenodd',
        attachArrows: false,
        paintId: '$paintIdScope-${shape.id}-fill',
        indent: '$indent  ',
      );
      geomIndex++;
    }
    for (final geom in shape.geometries) {
      if (geom.noShow) continue;
      final d = _geometryToD(
        geom,
        shape.width,
        shape.height,
        roundingInches: shape.line.roundingInches,
        infiniteLineResolver: (p, q) =>
            _infiniteLineEndpoints(page, shape, p, q),
      );
      if (d.isEmpty) continue;
      // Compound fill already emitted; skip fill-only sections with no stroke.
      final skipFill = compoundFill && !geom.noFill;
      if (skipFill && (geom.noLine || !shape.line.hasLine)) continue;
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
        page,
        d: d,
        strokeD: strokeD,
        noFill: skipFill || geom.noFill,
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
    if (shape.glassEffect &&
        shape.supportsGlassEffect &&
        fillParts.isNotEmpty) {
      _writeGlassHighlight(
        buf,
        shape,
        theme,
        clipD: fillParts.join(' '),
        paintId: '$paintIdScope-${shape.id}-glass',
        indent: '$indent  ',
      );
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
      final d = jumpD ??
          () {
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
          page,
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
        _writeShapeSafely(
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

  void _writeGlassHighlight(
    StringBuffer buf,
    VsdxShape shape,
    VsdxTheme theme, {
    required String clipD,
    required String paintId,
    required String indent,
  }) {
    final fillColor = _resolveFillColor(shape, theme);
    final alpha = _combinedOpacity(
      fillColor,
      shape.fill.foregroundTransparency,
    );
    if (alpha <= 0) return;
    final w = shape.width;
    final h = shape.height;
    final sw = math.max(0.0, shape.line.weightInches / 2);
    final clipId = 'clip-$paintId';
    final gradientId = 'gradient-$paintId';
    final highlightD = 'M ${_n(-sw)} ${_n(h + sw)} '
        'L ${_n(-sw)} ${_n(h * 0.6)} '
        'Q ${_n(w * 0.5)} ${_n(h * 0.3)} '
        '${_n(w + sw)} ${_n(h * 0.6)} '
        'L ${_n(w + sw)} ${_n(h + sw)} Z';
    buf.writeln(
      '$indent<defs>'
      '<clipPath id="$clipId"><path d="$clipD" fill-rule="evenodd"/>'
      '</clipPath>'
      '<linearGradient id="$gradientId" gradientUnits="userSpaceOnUse" '
      'x1="0" y1="${_n(h)}" x2="0" y2="${_n(h * 0.4)}">'
      '<stop offset="0" stop-color="#ffffff" '
      'stop-opacity="${_n(0.9 * alpha)}"/>'
      '<stop offset="1" stop-color="#ffffff" '
      'stop-opacity="${_n(0.1 * alpha)}"/>'
      '</linearGradient>'
      '</defs>',
    );
    buf.writeln(
      '$indent<path d="$highlightD" clip-path="url(#$clipId)" '
      'fill="url(#$gradientId)" stroke="none"/>',
    );
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

  String _flowStrokePaint(
    VsdxShape shape,
    String paint, {
    required String paintId,
    required StringBuffer defs,
  }) {
    if (paint == 'stroke="none"' ||
        !shape.flowAnimation ||
        !shape.supportsFlowAnimation) {
      return paint;
    }
    final match = RegExp(r'stroke-dasharray="([^"]+)"').firstMatch(paint);
    final dash = match?.group(1) ?? '${_n(8 / pxPerInch)} ${_n(8 / pxPerInch)}';
    final values = match == null
        ? <double>[8 / pxPerInch, 8 / pxPerInch]
        : dash
            .split(RegExp(r'[ ,]+'))
            .map(double.tryParse)
            .whereType<double>()
            .toList(growable: false);
    var cycle = values.fold<double>(0, (sum, value) => sum + value);
    if (values.length.isOdd) cycle *= 2;
    var result = paint;
    if (match == null) result += ' stroke-dasharray="$dash"';
    if (pdfCompat || cycle <= 0) return result;
    final id = 'flow-$paintId';
    final duration = math.max(
      1,
      (shape.flowAnimationDurationMs * cycle * pxPerInch / 16).round(),
    );
    defs.write(
      '<style>@keyframes $id { to { stroke-dashoffset: 0; } }</style>',
    );
    return '$result stroke-dashoffset="${_n(cycle)}" '
        'style="animation: $id ${duration}ms '
        '${shape.flowAnimationTiming.cssValue} infinite '
        '${shape.flowAnimationDirection.cssValue}"';
  }

  void _writePath(
    StringBuffer buf,
    VsdxShape shape,
    VsdxTheme theme,
    VsdxPage page, {
    required String d,

    /// When set (line jumps), stroke uses this path; fill keeps [d].
    String? strokeD,
    required bool noFill,
    required bool noLine,

    /// Visio compound fill (libvisio `svg:fill-rule=evenodd`).
    String? fillRule,
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
    final fillRuleAttr =
        (!noFill && fillRule != null) ? ' fill-rule="$fillRule"' : '';
    final sketchPatternFill = !noFill && shape.usesSketchPatternFill;
    final fillAttr = !noFill && !sketchPatternFill
        ? '${_fillAttr(shape, theme, paintId, defs, bounds: fillBounds)}$fillRuleAttr'
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
    final bodyStrokePaint = _flowStrokePaint(
      shape,
      stroke.paint,
      paintId: paintId,
      defs: defs,
    );
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
      noFill: noFill,
      noLine: noLine,
    );
    if (defs.isNotEmpty) {
      buf.writeln('$indent<defs>$defs</defs>');
    }
    _writeDropShadow(
      buf,
      shape,
      theme,
      page,
      d: d,
      noFill: noFill,
      noLine: noLine,
      paintId: paintId,
      indent: indent,
    );
    // Match canvas order: shadow → glow → reflection → body.
    // Soft outer glow (canvas strokes a blurred path before fill).
    final glow = shape.glow;
    final glowHollow = (noFill || !shape.fill.hasFill) &&
        (noLine || !shape.line.hasLine) &&
        !shape.hasImage;
    if (glow.enabled && glow.sizeInches > 0 && !glowHollow) {
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
          // Stroke half-width ≈ size; Gaussian extent ≈ 3×sigma(=size) → ~4×.
          final pad = glow.sizeInches * 4;
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
    if (sketchPatternFill) {
      _writeSketchPatternFill(
        buf,
        shape,
        theme,
        d: d,
        bounds: fillBounds,
        paintId: paintId,
        fillRule: fillRule,
        filter: filter,
        indent: indent,
      );
    }
    final compound = !noLine && shape.line.compoundType > 0;
    if (compound) {
      final weight =
          shape.line.weightInches > 0 ? shape.line.weightInches : 0.01;
      final linecap = switch (shape.line.cap) {
        LineCap.round => 'round',
        LineCap.square => 'square',
        LineCap.extended => 'butt',
      };
      final linejoin = _svgLineJoin(shape.line);
      final miterAttr = _svgMiterLimitAttr(shape.line);
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
        final strokePaint = bodyStrokePaint;
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
                  'stroke-linejoin="$linejoin"$miterAttr';
          _writeBodyStroke(
            buf,
            shape,
            d: od,
            strokePaint: withCap,
            indent: indent,
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
          'stroke-linejoin="$linejoin"$miterAttr/>'
          '<path d="$sD" fill="none" stroke="black" '
          'stroke-width="${_n(gap)}" stroke-linecap="$linecap" '
          'stroke-linejoin="$linejoin"$miterAttr/>'
          '</mask></defs>',
        );
        _writeBodyStroke(
          buf,
          shape,
          d: sD,
          strokePaint: bodyStrokePaint,
          extraAttrs: 'mask="url(#$mid)"',
          indent: indent,
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
        _writeBodyStroke(
          buf,
          shape,
          d: sD,
          strokePaint: bodyStrokePaint,
          indent: indent,
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
      if (shape.sketchEffect && !noLine && stroke.paint != 'stroke="none"') {
        if (!noFill && fillAttr != 'fill="none"') {
          buf.writeln('$indent<path d="$d" $fillAttr stroke="none"$filter/>');
        }
        _writeBodyStroke(
          buf,
          shape,
          d: d,
          strokePaint: bodyStrokePaint,
          extraAttrs: filter.trim(),
          indent: indent,
        );
      } else {
        buf.writeln(
          '$indent<path d="$d" $fillAttr $bodyStrokePaint$filter/>',
        );
      }
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

  void _writeSketchPatternFill(
    StringBuffer buf,
    VsdxShape shape,
    VsdxTheme theme, {
    required String d,
    required ({double minX, double minY, double width, double height}) bounds,
    required String paintId,
    required String? fillRule,
    required String filter,
    required String indent,
  }) {
    final color =
        _resolveFillColor(shape, theme) ?? const VsdxColor(0xFFFFFFFF);
    final opacity = _combinedOpacity(
      color,
      shape.fill.foregroundTransparency,
    );
    if (opacity <= 0) return;
    final clipId = 'sketch-fill-$paintId';
    final rule =
        fillRule == null ? '' : ' fill-rule="$fillRule" clip-rule="$fillRule"';
    buf.writeln(
      '$indent<defs><clipPath id="$clipId">'
      '<path d="$d"$rule/></clipPath></defs>',
    );
    buf.writeln(
      '$indent<g data-ve-sketch-fill="${shape.effectiveSketchFillStyle.drawioValue}" '
      'clip-path="url(#$clipId)"$filter>',
    );
    final gap = shape.sketchHachureGapPx / pxPerInch;
    final weight = math.max(shape.sketchFillWeightPx / pxPerInch, 0.0025);
    final style = shape.effectiveSketchFillStyle;
    if (style == VsdxSketchFillStyle.dots) {
      final dots = drawioSketchFillDots(
        minX: bounds.minX,
        minY: bounds.minY,
        width: bounds.width,
        height: bounds.height,
        gap: gap,
      );
      final radius = math.max(weight * 0.65, 0.6 / pxPerInch);
      for (final dot in dots) {
        buf.writeln(
          '$indent  <circle cx="${_n(dot.x)}" cy="${_n(dot.y)}" '
          'r="${_n(radius)}" fill="${_hex(color)}" '
          'fill-opacity="${_n(opacity)}"/>',
        );
      }
    } else {
      final segments = drawioSketchHachureSegments(
        minX: bounds.minX,
        minY: bounds.minY,
        width: bounds.width,
        height: bounds.height,
        gap: gap,
        angleDegrees: shape.sketchHachureAngleDegrees,
        crossHatch: style == VsdxSketchFillStyle.crossHatch,
      );
      final path = StringBuffer();
      for (final segment in segments) {
        path.write(
          'M ${_n(segment.start.x)} ${_n(segment.start.y)} '
          'L ${_n(segment.end.x)} ${_n(segment.end.y)} ',
        );
      }
      buf.writeln(
        '$indent  <path d="${path.toString().trim()}" fill="none" '
        'stroke="${_hex(color)}" stroke-opacity="${_n(opacity)}" '
        'stroke-width="${_n(weight)}" stroke-linecap="round"/>',
      );
    }
    buf.writeln('$indent</g>');
  }

  /// Emits a normal stroke or draw.io's two stable rough.js-like passes.
  /// Each pass has independent opacity so their overlap reads as ink while
  /// Canvas, SVG and PDF share the same authored pixel jiggle.
  void _writeBodyStroke(
    StringBuffer buf,
    VsdxShape shape, {
    required String d,
    required String strokePaint,
    required String indent,
    String extraAttrs = '',
  }) {
    final extra = extraAttrs.trim().isEmpty ? '' : ' ${extraAttrs.trim()}';
    if (!shape.sketchEffect) {
      buf.writeln(
        '$indent<path d="$d" fill="none" $strokePaint$extra/>',
      );
      return;
    }
    final offsets = drawioSketchStrokeOffsets(
      shape.id,
      shape.sketchJiggle,
      pxPerInch: pxPerInch,
    );
    buf.writeln('$indent<g data-ve-sketch="1">');
    for (final offset in offsets) {
      buf.writeln(
        '$indent  <path d="$d" fill="none" $strokePaint opacity="0.68" '
        'transform="translate(${_n(offset.x)} ${_n(offset.y)})"$extra/>',
      );
    }
    buf.writeln('$indent</g>');
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
      final refX = _isCenteredMarker(arrowId) ? 5 : 10;
      // Marker viewBox is 10 units wide; centred markers anchor at x=5.
      buf.writeln(
        '$indent<g transform="translate(${_n(tip.x)} ${_n(tip.y)}) '
        'rotate(${_n(deg)}) scale(${_n(mw / 10)}) '
        'translate(-$refX -5)">'
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
      final current = cmd;
      final rel = current == current.toLowerCase();
      final op = current.toUpperCase();
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
    VsdxTheme theme,
    VsdxPage page, {
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
    final xform = _pageShadowTransform(page, shape, dx, dy);
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
      // Include shadow translate in the filter region. The same <path> carries
      // transform="translate(dx,dy)" + filter — a blur-only pad clips when
      // |offset| exceeds ~3×blur (canvas has no equivalent clip).
      final region = _filterRegionAttr(
        bounds,
        blur * 3 + math.max(dx.abs(), dy.abs()),
      );
      buf.writeln(
        '$indent<defs><filter id="$sid" $region>'
        '<feGaussianBlur stdDeviation="${_n(blur)}"/>'
        '</filter></defs>',
      );
      filterAttr = ' filter="url(#$sid)"';
    }
    if (lineOnly) {
      // Match body / canvas: CompoundType rails + LinePattern dash.
      _writeCompoundOrPlainStroke(
        buf,
        d: d,
        line: shape.line,
        strokePaint: 'stroke="$hex"',
        strokeOpacity: alpha,
        indent: indent,
        extraAttrs: ' transform="$xform"$filterAttr',
      );
    } else {
      buf.writeln(
        '$indent<path d="$d" fill="$hex" fill-opacity="${_n(alpha)}" '
        'stroke="none" transform="$xform"'
        '$filterAttr/>',
      );
    }
  }

  /// Compose offset + optional page oblique/scale about LocPin (canvas parity).
  String _pageShadowTransform(
    VsdxPage page,
    VsdxShape shape,
    double dx,
    double dy,
  ) {
    final parts = <String>['translate(${_n(dx)} ${_n(dy)})'];
    final sheet = page.pageSheet;
    final scale = sheet.shadowScaleFactor;
    final oblique = sheet.shadowObliqueAngle;
    if (sheet.shadowType != 0 ||
        oblique.abs() > 1e-9 ||
        (scale - 1.0).abs() > 1e-9) {
      final cx = shape.effectiveLocPinX;
      final cy = shape.effectiveLocPinY;
      parts.add('translate(${_n(cx)} ${_n(cy)})');
      if ((scale - 1.0).abs() > 1e-9) {
        parts.add('scale(${_n(scale)})');
      }
      if (oblique.abs() > 1e-9) {
        final k = math.tan(oblique);
        parts.add('matrix(1 0 ${_n(k)} 1 0 0)');
      }
      parts.add('translate(${_n(-cx)} ${_n(-cy)})');
    }
    return parts.join(' ');
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
    final fallbackH = shape.height.abs() < 1e-9 ? weightH : shape.height.abs();
    final fallbackW = shape.width.abs() < 1e-9 ? weightH : shape.width.abs();
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
        shape.fill.pattern <= 24 &&
        !pdfCompat) {
      // Hatch defs emitted by [_fillAttr] as pat-$paintId — only when a real
      // <pattern> was created (not pdfCompat / unsupported solid fallback).
      fillPaint = 'url(#pat-$paintId)';
      fillOp = alpha;
    } else {
      // Solid (incl. pdfCompat hatch flatten and unsupported pattern ids).
      final c = _resolveFillColor(shape, theme) ?? const VsdxColor(0xFF888888);
      fillPaint = _hex(c);
      fillOp = _combinedOpacity(c, shape.fill.foregroundTransparency) * alpha;
    }
    // Stroke without arrow markers (canvas reflection draws the path stroke).
    // Compound rails are emitted separately via [_writeCompoundOrPlainStroke].
    String? reflStrokePaint;
    var reflStrokeAlpha = 0.0;
    if (hasStroke) {
      final line = shape.line;
      final c = _resolveColor(line.color, line.themeColorIndex, theme);
      // Gradient strokes ignore LineColor.a (same as [_strokeAttr]); solid
      // strokes still combine colour AA with LineColorTrans.
      reflStrokeAlpha = (line.hasGradient
              ? (1 - line.transparency.clamp(0.0, 1.0))
              : _combinedOpacity(c, line.transparency)) *
          alpha;
      final hex = c == null ? '#000000' : _hex(c);
      reflStrokePaint =
          line.hasGradient ? 'stroke="url(#lg-$paintId)"' : 'stroke="$hex"';
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
        if (fillPaint != 'none' && fillOp > 0) {
          buf.writeln(
            '$indent  <path d="$d" fill="$fillPaint" '
            'fill-opacity="${_n(fillOp * 0.55)}" stroke="none"/>',
          );
        }
        if (reflStrokePaint != null) {
          _writeCompoundOrPlainStroke(
            buf,
            d: d,
            line: shape.line,
            strokePaint: reflStrokePaint,
            strokeOpacity: reflStrokeAlpha * 0.55,
            indent: '$indent  ',
          );
        }
      }
      buf.writeln('$indent</g>');
      return;
    }
    final blurPad = math.max(refl.blurInches, 0.001) * 3;
    final blurRegion =
        refl.blurInches > 0 ? _filterRegionAttr(bounds, blurPad) : '';
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
      if (fillPaint != 'none' && fillOp > 0) {
        buf.writeln(
          '$indent  <path d="$d" fill="$fillPaint" '
          'fill-opacity="${_n(fillOp)}" stroke="none"$filter/>',
        );
      }
      if (reflStrokePaint != null) {
        _writeCompoundOrPlainStroke(
          buf,
          d: d,
          line: shape.line,
          strokePaint: reflStrokePaint,
          strokeOpacity: reflStrokeAlpha,
          indent: '$indent  ',
          extraAttrs: filter,
        );
      }
    }
    buf.writeln('$indent</g>');
  }

  /// Emit one plain stroke or CompoundType parallel rails for [d].
  void _writeCompoundOrPlainStroke(
    StringBuffer buf, {
    required String d,
    required VsdxLine line,
    required String strokePaint,
    required double strokeOpacity,
    required String indent,
    String extraAttrs = '',
  }) {
    final weight = line.weightInches > 0 ? line.weightInches : 0.01;
    final linecap = switch (line.cap) {
      LineCap.round => 'round',
      LineCap.square => 'square',
      LineCap.extended => 'butt',
    };
    final linejoin = _svgLineJoin(line);
    final miterAttr = _svgMiterLimitAttr(line);
    final dash = _dashAttr(line);
    final dashAttr = dash.isEmpty ? '' : ' stroke-dasharray="$dash"';
    final rails = compoundRails(line.compoundType, weight);
    final sampled = samplePathD(d);
    if (rails.isNotEmpty && sampled.points.length >= 2) {
      for (final rail in rails) {
        final off = offsetPolyline(
          sampled.points,
          rail.offset,
          closed: sampled.closed,
        );
        if (off.length < 2) continue;
        final od = polylineToPathD(off, closed: sampled.closed);
        buf.writeln(
          '$indent<path d="$od" fill="none" $strokePaint '
          'stroke-opacity="${_n(strokeOpacity)}" '
          'stroke-width="${_n(rail.width)}" stroke-linecap="$linecap" '
          'stroke-linejoin="$linejoin"$miterAttr$dashAttr$extraAttrs/>',
        );
      }
      return;
    }
    buf.writeln(
      '$indent<path d="$d" fill="none" $strokePaint '
      'stroke-opacity="${_n(strokeOpacity)}" '
      'stroke-width="${_n(weight)}" stroke-linecap="$linecap" '
      'stroke-linejoin="$linejoin"$miterAttr$dashAttr$extraAttrs/>',
    );
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
      final current = cmd;
      final rel = current == current.toLowerCase();
      final op = current.toUpperCase();
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

  /// SoftEdges blur only (shadow is [_writeDropShadow]). Skip 1D like canvas.
  String? _softEdgesFilterAttr(
    VsdxShape shape,
    String paintId,
    StringBuffer defs, {
    required ({double minX, double minY, double width, double height}) bounds,
    bool noFill = false,
    bool noLine = false,
  }) {
    // package:pdf ignores filters — SoftEdges would silently vanish.
    if (pdfCompat) return null;
    // Match glow / canvas: geom or shape hollow (non-image) has nothing to feather.
    final softHollow = (noFill || !shape.fill.hasFill) &&
        (noLine || !shape.line.hasLine) &&
        !shape.hasImage;
    final soft = (!shape.is1D && !softHollow && shape.line.softEdgesInches > 0)
        ? shape.line.softEdgesInches
        : 0.0;
    if (soft <= 0) return null;
    final id = 'fx-$paintId';
    final region = _filterRegionAttr(bounds, _softEdgesPad(shape.line, soft));
    // Feather edges only: blur SourceAlpha, then mask SourceGraphic so
    // interiors (and Foreign bitmap detail) stay sharp — matches Visio SoftEdges.
    defs.write(
      '<filter id="$id" $region>'
      '<feGaussianBlur in="SourceAlpha" '
      'stdDeviation="${_n(soft)}" result="softAlpha"/>'
      '<feComposite in="SourceGraphic" in2="softAlpha" operator="in"/>'
      '</filter>',
    );
    return 'url(#$id)';
  }

  /// Soft-edge filter / saveLayer pad: blur extent plus half-weight (and
  /// compound rail extent) so thick strokes are not clipped after feathering.
  double _softEdgesPad(VsdxLine line, double soft) {
    final weight = line.weightInches > 0 ? line.weightInches : 0.01;
    var extent = weight / 2;
    for (final r in compoundRails(line.compoundType, weight)) {
      extent = math.max(extent, r.offset.abs() + r.width / 2);
    }
    return soft * 3 + extent;
  }

  String _geometryToD(
    VsdxGeometry g,
    double w,
    double h, {
    double roundingInches = 0,
    _InfiniteLineResolver? infiniteLineResolver,
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
          final out = StringBuffer(
              'M ${_n(filleted.first.x)} ${_n(filleted.first.y)} ');
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
          final degenerate = visioDegenerateEllipsePath(
            EllipseCmd(
              cx: cx,
              cy: cy,
              aX: aX,
              aY: aY,
              bX: bX,
              bY: bY,
            ),
          );
          if (degenerate != null) {
            if (degenerate.isNotEmpty) {
              m(degenerate.first.x, degenerate.first.y);
              for (final point in degenerate.skip(1)) {
                l(point.x, point.y);
              }
              out.write('Z ');
            }
            continue;
          }
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
        case InfiniteLineCmd(
            :final x,
            :final y,
            :final a,
            :final b,
            :final relative
          ):
          final sx = relative ? w : 1.0;
          final sy = relative ? h : 1.0;
          final px = x * sx, py = y * sy, qx = a * sx, qy = b * sy;
          final clipped = infiniteLineResolver?.call(
            Offset2D(px, py),
            Offset2D(qx, qy),
          );
          if (clipped != null && clipped.length >= 2) {
            m(clipped.first.x, clipped.first.y);
            l(clipped.last.x, clipped.last.y);
            continue;
          }
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

  List<Offset2D>? _infiniteLineEndpoints(
    VsdxPage page,
    VsdxShape shape,
    Offset2D p,
    Offset2D q,
  ) {
    final pageP = page.localToPageDeep(shape.id, p);
    final pageQ = page.localToPageDeep(shape.id, q);
    final clipped = clipInfiniteLineToPage(
      pageP,
      pageQ,
      pageWidth: page.widthInches,
      pageHeight: page.heightInches,
    );
    if (clipped == null) return null;
    return <Offset2D>[
      for (final endpoint in clipped)
        page.pageToLocalDeep(shape.id, endpoint),
    ];
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
    VsdxShape shape,
    VsdxTheme theme,
    String paintId,
    StringBuffer defs, {
    required ({double minX, double minY, double width, double height}) bounds,
  }) {
    final fill = shape.fill;
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
        // Radial / rectangular / path: match canvas radial disc + FillGradientDir.
        final origin = radialGradientOrigin(
          dir: g.dir,
          minX: bounds.minX,
          minY: bounds.minY,
          width: bounds.width,
          height: bounds.height,
        );
        defs.write(
          '<radialGradient id="$id" gradientUnits="userSpaceOnUse" '
          'cx="${_n(origin.x)}" cy="${_n(origin.y)}" r="${_n(r)}">'
          '$stops</radialGradient>',
        );
      }
      return 'fill="url(#$id)"';
    }

    final fg = _resolveFillColor(shape, theme);
    final fgAlpha = _combinedOpacity(fg, fill.foregroundTransparency);
    final fgHex = fg == null ? '#ffffff' : _hex(fg);

    final hatchSpec = libvisioHatchSpec(fill.pattern);
    if (hatchSpec != null) {
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
      final isDiagonal = hatchSpec.angleDegrees == 45 ||
          hatchSpec.angleDegrees == 315;
      final tile = hatchSpec.distanceInches *
          (isDiagonal ? math.sqrt2 : 1);
      if (hatchSpec.style == VsdxHatchStyle.triple) {
        final axisId = '$id-axis';
        final axisTile = hatchSpec.distanceInches;
        defs.write(
          '<pattern id="$axisId" patternUnits="userSpaceOnUse" '
          'width="${_n(axisTile)}" height="${_n(axisTile)}">'
          '<rect width="${_n(axisTile)}" height="${_n(axisTile)}" '
          'fill="$bgHex" fill-opacity="${_n(bgAlpha)}"/>'
          '${_hatchPath(fill.pattern, axisTile, color: fgHex, opacity: fgAlpha, axisOnly: true)}'
          '</pattern>',
        );
        final diagonalTile = hatchSpec.distanceInches * math.sqrt2;
        defs.write(
          '<pattern id="$id" patternUnits="userSpaceOnUse" '
          'width="${_n(diagonalTile)}" height="${_n(diagonalTile)}">'
          '<rect width="${_n(diagonalTile)}" height="${_n(diagonalTile)}" '
          'fill="url(#$axisId)"/>'
          '${_hatchPath(fill.pattern, diagonalTile, color: fgHex, opacity: fgAlpha, diagonalOnly: true)}'
          '</pattern>',
        );
        return 'fill="url(#$id)"';
      }
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

  /// SVG hatch tile for Visio FillPattern 2–24, matching libvisio's hatch
  /// style, angle and spacing and the canvas [PatternFillBuilder].
  String _hatchPath(
    int pattern,
    double tile, {
    String color = '#000000',
    double opacity = 1,
    bool axisOnly = false,
    bool diagonalOnly = false,
  }) {
    final spec = libvisioHatchSpec(pattern);
    if (spec == null) return '';
    // LibreOffice renders axis-aligned ODF hatch strokes as a one-device-pixel
    // hairline at 96 dpi. Sloped hairlines retain that footprint with roughly
    // half coverage after anti-aliasing.
    const axisWidth = 0.01;
    const diagonalWidth = 0.01;
    final base = 'stroke="$color" stroke-opacity="${_n(opacity)}" fill="none"';
    final diagonalBase =
        'stroke="$color" stroke-opacity="${_n(opacity * 0.5)}" fill="none"';
    final axis = '$base stroke-width="${_n(axisWidth)}"';
    final diagonal =
        '$diagonalBase stroke-width="${_n(diagonalWidth)}"';
    final t = _n(tile);
    final h = _n(tile / 2);
    final horizontal = '<line x1="0" y1="$h" x2="$t" y2="$h" $axis/>';
    final vertical = '<line x1="$h" y1="0" x2="$h" y2="$t" $axis/>';
    // The page-to-SVG transform flips Visio's upward Y axis. Define the
    // diagonals in local coordinates so their rendered angles still match
    // libvisio's 45-degree (rising) and 315-degree (falling) hatches.
    final rising =
        '<line x1="0" y1="0" x2="$t" y2="$t" $diagonal/>';
    final falling =
        '<line x1="0" y1="$t" x2="$t" y2="0" $diagonal/>';
    if (spec.style == VsdxHatchStyle.triple) {
      final axes = diagonalOnly ? '' : '$horizontal$vertical';
      final diagonals = axisOnly ? '' : '$rising$falling';
      return '$axes$diagonals';
    }
    if (spec.style == VsdxHatchStyle.double) {
      return spec.angleDegrees == 45
          ? '$rising$falling'
          : '$horizontal$vertical';
    }
    return switch (spec.angleDegrees) {
      45 => rising,
      90 => vertical,
      315 => falling,
      _ => horizontal,
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
    final dash = _dashAttr(line);
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
    final linejoin = _svgLineJoin(line);
    final miterAttr = _svgMiterLimitAttr(line);
    // Keep LineColorTrans as stroke-opacity even for gradients (canvas bakes
    // line.transparency into the shader and forces paint alpha=1). Do NOT fold
    // LineColor.a into stroke-opacity when a gradient paints the stroke — the
    // LineColor cell is unused for colour and its AA would make SVG more
    // transparent than canvas.
    final lineTransAlpha = (1 - line.transparency.clamp(0.0, 1.0));
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
        // Radial / rectangular / path: match canvas radial disc + LineGradientDir.
        final origin = radialGradientOrigin(
          dir: g.dir,
          minX: bounds.minX,
          minY: bounds.minY,
          width: bounds.width,
          height: bounds.height,
        );
        defs.write(
          '<radialGradient id="$id" gradientUnits="userSpaceOnUse" '
          'cx="${_n(origin.x)}" cy="${_n(origin.y)}" r="${_n(r)}">'
          '$stops</radialGradient>',
        );
      }
      strokePaint = 'stroke="url(#$id)" stroke-opacity="${_n(lineTransAlpha)}"';
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
        final refX = _isCenteredMarker(line.beginArrow) ? 5 : 0;
        defs.write(
          '<marker id="$mid" markerUnits="userSpaceOnUse" overflow="visible" '
          'viewBox="0 0 10 10" refX="$refX" refY="5" '
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
        final refX = _isCenteredMarker(line.endArrow) ? 5 : 10;
        defs.write(
          '<marker id="$mid" markerUnits="userSpaceOnUse" overflow="visible" '
          'viewBox="0 0 10 10" refX="$refX" refY="5" '
          'markerWidth="${_n(mw)}" markerHeight="${_n(mw)}" '
          'orient="auto-start-reverse">'
          '$body</marker>',
        );
        markers.write(' marker-end="url(#$mid)"');
      }
    }
    final paint = '$strokePaint '
        'stroke-width="${_strokeN(weight)}" stroke-linecap="$linecap" '
        'stroke-linejoin="$linejoin"$miterAttr'
        '${dash.isEmpty ? '' : ' stroke-dasharray="$dash"'}';
    return (paint: paint, markers: markers.toString());
  }

  String _svgLineJoin(VsdxLine line) {
    final join = line.effectiveJoin;
    if (!pdfCompat) return join.svgName;
    return switch (join) {
      VsdxLineJoin.arcs => 'round',
      VsdxLineJoin.miterClip => 'miter',
      _ => join.svgName,
    };
  }

  /// libvisio emits `draw:marker-*-center=true` only for these marker ids.
  bool _isCenteredMarker(int arrowId) =>
      arrowId == 9 ||
      arrowId == 10 ||
      arrowId == 11 ||
      arrowId == 20 ||
      arrowId == 21;

  String _svgMiterLimitAttr(VsdxLine line) {
    final join = line.effectiveJoin;
    if (join != VsdxLineJoin.miter && join != VsdxLineJoin.miterClip) {
      return '';
    }
    if (line.join == null && (line.miterLimit - 4.0).abs() < 1e-9) {
      return '';
    }
    return ' stroke-miterlimit="${_n(line.miterLimit.clamp(1.0, 100.0))}"';
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
    // Work in tip-at-right space, then mirror for start markers. The id
    // mapping follows libvisio VSDContentCollector marker paths and mirrors
    // lib/render/arrow_library.dart.
    final (d, filled) = switch (arrowId) {
      1 => ('M 0 1 L 10 5 L 0 9 Z', false), // open short arrowhead
      2 => ('M 0 2.5 L 10 5 L 0 7.5 Z', true),
      3 => ('M 0 1 L 10 5 L 0 9', false), // short line arrow
      4 => ('M 0 1 L 10 5 L 0 9 Z', true),
      5 => ('M 0 1 L 10 5 L 0 9 L 3 5 Z', true), // concave
      6 => ('M 0 1 L 10 5 L 0 9 Q 7 5 0 1 Z', true), // convex
      7 => ('M 0 -4.091 L 10 5 L 0 14.091', false),
      8 => ('M 0 0.5 L 10 5 L 0 9.5 L 2.5 5 Z', true),
      9 => ('M 0 1 L 10 9 M 5 1 V 9', false), // centred line
      10 => (
          'M 5 5 m -5,0 a 5,5 0 1,0 10,0 a 5,5 0 1,0 -10,0',
          true,
        ),
      11 => ('M 0 1 H 10 V 9 H 0 Z', true), // centred filled square
      12 => ('M 0 0.5 L 10 5 L 0 9.5 L 2.5 5 Z', false),
      13 => ('M 0 3.2 L 10 5 L 0 6.8 Z', true),
      14 => ('M 1.5 -0.5 L 10 5 L 1.5 10.5 Z', false),
      15 => ('M 0 2.5 L 10 5 L 0 7.5 Z', false),
      16 => ('M 0 1 L 10 5 L 0 9 Z', false),
      17 => ('M 0 1 L 10 5 L 0 9 L 3 5 Z', false),
      18 => ('M 0 0.5 L 10 5 L 0 9.5 L 2.5 5 Z', false),
      19 => ('M 0 -4.091 L 10 5 L 0 14.091', false),
      20 || 31 || 32 || 33 || 41 => (
          'M 5 5 m -4,0 a 4,4 0 1,0 8,0 a 4,4 0 1,0 -8,0',
          false,
        ),
      21 => ('M 0 1 H 10 V 9 H 0 Z', false),
      22 => ('M 0 5 L 5 1.5 L 10 5 L 5 8.5 Z', false),
      23 => ('M 0 9 L 10 1 M 5 0 V 10', false), // oblique single line
      24 => ('M 7 1 V 9', false),
      25 => ('M 7 1 V 9 M 4.5 1 V 9', false),
      26 => ('M 7 1 V 9 M 4.5 1 V 9', false),
      27 => (
          'M 10 5 L 2 1 M 10 5 L 2 5 M 10 5 L 2 9',
          false
        ),
      28 => (
          'M 10 5 L 3 1 M 10 5 L 3 5 M 10 5 L 3 9 M 1 1 V 9',
          false,
        ),
      29 => (
          'M 6 5 m -1.8,0 a 1.8,1.8 0 1,0 3.6,0 a 1.8,1.8 0 1,0 -3.6,0 '
              'M 4 5 L 0 1 M 4 5 L 0 5 M 4 5 L 0 9',
          false,
        ),
      30 => (
          'M 4 5 m -1.8,0 a 1.8,1.8 0 1,0 3.6,0 a 1.8,1.8 0 1,0 -3.6,0 '
              'M 7 1 V 9',
          false,
        ),
      34 => (
          'M 5 5 m -4,0 a 4,4 0 1,0 8,0 a 4,4 0 1,0 -8,0',
          false,
        ),
      35 || 36 || 37 => (
          'M 4.2 5 m -3.4,0 a 3.4,3.4 0 1,0 6.8,0 a 3.4,3.4 0 1,0 -6.8,0 '
              'M 9.2 0 V 10 H 10 V 0 Z',
          true,
        ),
      38 => (
          'M 5 5 m -4,0 a 4,4 0 1,0 8,0 a 4,4 0 1,0 -8,0',
          true,
        ),
      39 => (
          'M 4 1 L 10 5 L 4 9 Z M 0 1 L 6 5 L 0 9 Z',
          true
        ),
      40 => (
          'M 4 1 L 10 5 L 4 9 Z M 0 1 L 6 5 L 0 9 Z',
          true,
        ),
      42 => (
          'M 5 5 m -5,0 a 5,5 0 1,0 10,0 a 5,5 0 1,0 -10,0',
          true,
        ),
      43 => ('M 0 1 L 10 5 L 0 9', false),
      44 || 45 => ('M 0 1 L 10 5 L 0 9', false),
      _ => ('M 0 1 L 10 5 L 0 9 Z', true),
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
        'stroke-width="${_n(sw)}" stroke-linejoin="round" '
        'stroke-linecap="round"/>';
  }

  /// Rough mirror of simple marker paths about x=5 (for start arrows).
  String _mirrorArrowD(String d) {
    // Dedicated mirrors for the small set of templates above.
    return switch (d) {
      'M 0 1 L 10 5 L 0 9' => 'M 10 1 L 0 5 L 10 9',
      'M 0 1 L 10 5 L 0 9 Z' => 'M 10 1 L 0 5 L 10 9 Z',
      'M 0 1 L 10 5 L 0 9 L 3 5 Z' =>
        'M 10 1 L 0 5 L 10 9 L 7 5 Z',
      'M 0 1 L 10 5 L 0 9 Q 7 5 0 1 Z' =>
        'M 10 1 L 0 5 L 10 9 Q 3 5 10 1 Z',
      'M 0 1 L 10 9 M 5 1 V 9' => 'M 10 1 L 0 9 M 5 1 V 9',
      'M 0 2.5 L 10 5 L 0 7.5 Z' => 'M 10 2.5 L 0 5 L 10 7.5 Z',
      'M 1.5 -0.5 L 10 5 L 1.5 10.5 Z' => 'M 8.5 -0.5 L 0 5 L 8.5 10.5 Z',
      'M 0 1 L 10 5 L 0 9 L 2 5 Z' => 'M 10 1 L 0 5 L 10 9 L 8 5 Z',
      'M 0 -4.091 L 10 5 L 0 14.091 L 2.727 5 Z' =>
        'M 10 -4.091 L 0 5 L 10 14.091 L 7.273 5 Z',
      'M 0 -4.091 L 10 5 L 0 14.091' => 'M 10 -4.091 L 0 5 L 10 14.091',
      'M 0 5 L 5 1.5 L 10 5 L 5 8.5 Z' => 'M 10 5 L 5 1.5 L 0 5 L 5 8.5 Z',
      'M 0 1 H 10 V 9 H 0 Z' => d, // square tip-edge at both ends via orient
      'M 5 1 V 9' => d,
      'M 0 9 L 10 1 M 5 0 V 10' => 'M 10 9 L 0 1 M 5 0 V 10',
      'M 7 1 V 9' => 'M 3 1 V 9',
      'M 7 1 V 9 M 4.5 1 V 9' => 'M 3 1 V 9 M 5.5 1 V 9',
      'M 10 5 L 2 1 M 10 5 L 2 5 M 10 5 L 2 9' =>
        'M 0 5 L 8 1 M 0 5 L 8 5 M 0 5 L 8 9',
      'M 10 5 L 3 1 M 10 5 L 3 5 M 10 5 L 3 9 M 1 1 V 9' =>
        'M 0 5 L 7 1 M 0 5 L 7 5 M 0 5 L 7 9 M 9 1 V 9',
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
      'M 0 1 L 10 5 L 0 9 Z M 7 3 L 3 7' => 'M 10 1 L 0 5 L 10 9 Z M 3 3 L 7 7',
      'M 0 3.2 L 10 5 L 0 6.8 Z' => 'M 10 3.2 L 0 5 L 10 6.8 Z',
      'M 4 1 L 10 5 L 4 9 Z M 0 1 L 6 5 L 0 9 Z' =>
        'M 6 1 L 0 5 L 6 9 Z M 10 1 L 4 5 L 10 9 Z',
      'M 10 5 L 2 1 M 10 5 L 0 5 M 10 5 L 2 9' =>
        'M 0 5 L 8 1 M 0 5 L 10 5 M 0 5 L 8 9',
      'M 4.2 5 m -3.4,0 a 3.4,3.4 0 1,0 6.8,0 a 3.4,3.4 0 1,0 -6.8,0 '
            'M 9.2 0 V 10 H 10 V 0 Z' =>
        'M 5.8 5 m -3.4,0 a 3.4,3.4 0 1,0 6.8,0 a 3.4,3.4 0 1,0 -6.8,0 '
            'M 0.8 0 V 10 H 0 V 0 Z',
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
      10 || 11 => 0.7,
      12 || 14 || 15 || 16 || 17 || 18 || 22 => 1.2,
      13 => 1.4,
      7 || 19 => 0.55,
      25 || 26 => 0.85,
      28 || 29 || 30 => 1.1,
      39 || 40 => 1.2,
      _ => 1.0,
    };
  }

  /// Combine Visio `*Trans` (0..1) with the colour's own ARGB alpha
  /// (libvisio / `#RRGGBBAA` colours carry opacity in the colour cell).
  double _combinedOpacity(VsdxColor? c, double transparency) {
    var t = transparency;
    if (_layerTint != null) {
      t = 1 - (1 - t) * (1 - _layerTintTrans);
    }
    final colourA = c == null ? 1.0 : c.alpha / 255.0;
    return (colourA * (1 - t)).clamp(0.0, 1.0);
  }

  String _dashAttr(VsdxLine line) {
    return effectiveDashArrayAttr(
      line,
      // A classic VSD hairline can be 0.00025in wide and its dash cells can
      // be equally small. Coordinate precision is intentionally compact, but
      // rounding paint dimensions to three decimals changes these positive
      // values into SVG zeroes and invokes renderer-specific hairline rules.
      format: _strokeN,
    );
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
    // Shape-box clipping + SoftEdges wrap both bitmaps and vector metafiles.
    _writeImageDecorationsOpen(buf, shape, indent: indent);
    _writeForeignImageContent(
      buf,
      shape,
      indent: '$indent  ',
      resolved: resolved,
    );
    _writeImageDecorationsClose(buf, indent: indent);
  }

  /// Resolve Foreign media to a Flutter-decodable bitmap or vector metafile.
  ({String? mime, List<int>? bytes, MetafileDrawing? vectorDrawing})?
      _resolveForeignImage(VsdxShape shape) {
    final src = _images.findByPart(shape.imagePartName ?? '');
    if (!embedImages || src == null) return null;
    final bitmap = src.rasterForRendering();
    if (bitmap != null) {
      return (
        mime: bitmap.mimeType,
        bytes: bitmap.bytes,
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
    ({
      String? mime,
      List<int>? bytes,
      MetafileDrawing? vectorDrawing
    })? resolved,
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
    // Bitmap rows are Y-down — always normalise them about the image rect
    // centre. Shape/group FlipY remains in the outer XForm and must mirror the
    // already-upright bitmap, matching libvisio's draw:mirror-vertical.
    final cx = ox + iw / 2;
    final cy = oy + ih / 2;
    final opacity = (1.0 - shape.imageTransparency).clamp(0.0, 1.0);
    final opacityAttr = opacity < 1.0 - 1e-9 ? ' opacity="${_n(opacity)}"' : '';
    buf.writeln(
      '$indent<g$toneAttr transform="translate(${_n(cx)} ${_n(cy)}) '
      'scale(1 -1) '
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
    // Match canvas imgRect.inflate(0.08*blur*3) — default OBB ±10% clips
    // soft blur on small Foreign pictures.
    final ox = shape.imgOffsetXInches;
    final oy = shape.imgOffsetYInches;
    final iw = shape.effectiveImgWidth;
    final ih = shape.effectiveImgHeight;
    final pad = math.max(0.08 * blur * 3, 0.01);
    final region = _filterRegionAttr(
      (minX: ox, minY: oy, width: iw, height: ih),
      pad,
    );
    buf.writeln(
      '$indent<defs><filter id="$id" $region>$parts</filter></defs>',
    );
    return ' filter="url(#$id)"';
  }

  /// Open shape-box clip + SoftEdges groups for a Foreign image.
  ///
  /// libvisio outputs Geometry paths and the ForeignData GraphicObject as
  /// siblings. Only the Foreign frame clips ImgOffset overflow; arbitrary
  /// Geometry must not crop the image.
  void _writeImageDecorationsOpen(
    StringBuffer buf,
    VsdxShape shape, {
    required String indent,
  }) {
    final boxId = 'img-box-${shape.id}';
    // SoftEdges blur extends past the image box — pad the clip so the feather
    // is not cut off (same pad as geometry SoftEdges / [_softEdgesPad]).
    final softIn = shape.line.softEdgesInches;
    final softPad = softIn > 1e-9 ? _softEdgesPad(shape.line, softIn) : 0.0;
    buf.writeln(
      '$indent<defs><clipPath id="$boxId">'
      '<rect x="${_n(-softPad)}" y="${_n(-softPad)}" '
      'width="${_n(shape.width + 2 * softPad)}" '
      'height="${_n(shape.height + 2 * softPad)}"/></clipPath></defs>',
    );
    buf.writeln('$indent<g clip-path="url(#$boxId)">');
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
  }

  void _writeImageDecorationsClose(
    StringBuffer buf, {
    required String indent,
  }) {
    buf.writeln('$indent  </g>'); // soft
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
    // GDI metafiles are Y-down. Always normalise into shape-local Y-up, then
    // let the outer shape/group XForms apply FlipY exactly once.
    final sy = -ih / dh;
    final ty = oy + ih;
    final opacity = (1.0 - shape.imageTransparency).clamp(0.0, 1.0);
    final opacityAttr = opacity < 1.0 - 1e-9 ? ' opacity="${_n(opacity)}"' : '';
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
          unflipGlyphs: true,
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
    final sw =
        op.stroke ? ' stroke-width="${_n(math.max(op.strokeWidth, 0.5))}"' : '';
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
    final d =
        StringBuffer('M ${_n(op.points.first.x)} ${_n(op.points.first.y)}');
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
    final face =
        (op.face == null || op.face!.isEmpty) ? 'Arial' : _esc(op.face!);
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
    final border = shape.labelBorderColor;
    final borderPaint = border == null
        ? 'stroke="none"'
        : 'stroke="${_hex(border)}" stroke-width="${_n(1 / pxPerInch)}"';
    final padding = shape.labelPadding;
    final padTop = (padding.isZero ? 3.0 : padding.top) / pxPerInch;
    final padRight = (padding.isZero ? 3.0 : padding.right) / pxPerInch;
    final padBottom = (padding.isZero ? 3.0 : padding.bottom) / pxPerInch;
    final padLeft = (padding.isZero ? 3.0 : padding.left) / pxPerInch;
    final angle =
        angleRad != 0 ? ' rotate(${_n(angleRad * 180 / math.pi)})' : '';
    final dirRot = textDirection == 1 ? ' rotate(-90)' : '';
    final mirror = _textFlipX || _textFlipY
        ? ' scale(${_textFlipX ? -1 : 1} ${_textFlipY ? -1 : 1})'
        : '';
    buf.writeln(
      '$indent<g transform="translate(${_n(pinX)} ${_n(pinY)})$angle$mirror$dirRot">'
      '<rect x="${_n(-maxW / 2 - padLeft)}" y="${_n(-totalH / 2 - padTop)}" '
      'width="${_n(maxW + padLeft + padRight)}" height="${_n(totalH + padTop + padBottom)}" '
      'rx="0.02" fill="${_hex(plate)}" '
      'fill-opacity="${_n(bgOp)}" $borderPaint/>'
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
    var labelAngle = shape.isGlueableConnector
        ? page.effectiveConnectorLabelAngle(shape)
        : block.angleRad;
    if (shape.isGlueableConnector && shape.autoRotateLabel && _textFlipX) {
      labelAngle += math.pi;
    }
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

    final fallback = shape.text?.isNotEmpty == true
        ? shape.text!
        : _meaningfulNameLabel(shape);
    final runs = shape.richText.runs.isNotEmpty
        ? shape.richText.runs
        : <VsdxTextRun>[VsdxTextRun(text: fallback ?? '')];
    final hasTabs = runs.any((run) => run.text.contains('\t'));
    if (runs.every((r) => r.text.isEmpty) &&
        (fallback == null || fallback.isEmpty)) {
      return;
    }

    // Match canvas: rotate about TxtPin, then offset by −TxtLocPin so the
    // block's lower-left is the local origin (not the text centroid).
    final xf = StringBuffer(
      'translate(${_n(pinX)} ${_n(pinY)})',
    );
    if (labelAngle != 0) {
      xf.write(' rotate(${_n(labelAngle * 180 / math.pi)})');
    }
    if (_textFlipX || _textFlipY) {
      xf.write(' scale(${_textFlipX ? -1 : 1} ${_textFlipY ? -1 : 1})');
    }
    xf.write(' translate(${_n(-lpx)} ${_n(-lpy)})');

    // Loose edge labels (no TxtPin): canvas centres a tight plate + glyphs on
    // the route midpoint and returns — do not flow into Width×Height.
    final looseEdge = shape.isGlueableConnector &&
        block.pinXInches == null &&
        block.pinYInches == null;
    if (looseEdge && !hasTabs) {
      _writeLooseEdgeLabel(
        buf,
        shape: shape,
        theme: theme,
        page: page,
        runs: runs,
        pinX: pinX,
        pinY: pinY,
        angleRad: labelAngle,
        textDirection: block.textDirection,
        backgroundColor: block.backgroundColor,
        backgroundTransparency: block.backgroundTransparency,
        indent: indent,
      );
      return;
    }
    final labelBorder = shape.labelBorderColor;
    // libvisio applies TextBkgnd to the text span, not the complete
    // TxtWidth × TxtHeight frame. Approximate the span bounds with the same
    // layout estimator used for draw.io's padded label plate.
    final tightLabelPlate = block.backgroundColor != null ||
        (!shape.labelPadding.isZero && labelBorder != null);
    if (!tightLabelPlate &&
        (block.backgroundColor != null || labelBorder != null)) {
      final bgOp = block.backgroundColor == null
          ? 0.0
          : _combinedOpacity(
              block.backgroundColor,
              block.backgroundTransparency,
            );
      final fill = block.backgroundColor == null
          ? 'fill="none"'
          : 'fill="${_hex(block.backgroundColor!)}" '
              'fill-opacity="${_n(bgOp)}"';
      final stroke = labelBorder == null
          ? 'stroke="none"'
          : 'stroke="${_hex(labelBorder)}" '
              'stroke-width="${_n(1 / pxPerInch)}"';
      buf.writeln(
        '$indent<g transform="$xf">'
        '<rect x="0" y="0" width="${_n(tw)}" height="${_n(th)}" '
        '$fill $stroke/></g>',
      );
    }

    if (tightLabelPlate) {
      _writeTightLabelPlate(
        buf,
        shape: shape,
        runs: runs,
        transform: xf.toString(),
        width: tw,
        height: th,
        marginLeft: ml,
        marginRight: mr,
        marginTop: mt,
        marginBottom: mb,
        verticalAlign: block.verticalAlign,
        textDirection: block.textDirection,
        backgroundColor: block.backgroundColor,
        backgroundTransparency: block.backgroundTransparency,
        borderColor: labelBorder,
        tabSets: shape.richText.tabSets,
        defaultTabStopInches: block.defaultTabStopInches,
        indent: indent,
      );
    }

    // CurvedText: canvas disables arc layout for every glueable connector.
    // package:pdf ignores <textPath> — fall through to rectangular layout.
    if (shape.curvedText &&
        !shape.isGlueableConnector &&
        !hasTabs &&
        !pdfCompat) {
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
        angleRad: labelAngle,
        textDirection: block.textDirection,
        paintIdScope: paintIdScope,
        indent: indent,
      );
      return;
    }

    final shapeInsideDefaultBlock =
        (block.widthInches == null || (tw - shape.width).abs() < 1e-6) &&
            (block.heightInches == null || (th - shape.height).abs() < 1e-6) &&
            (block.pinXInches == null ||
                (block.pinXInches! - shape.width / 2).abs() < 1e-6) &&
            (block.pinYInches == null ||
                (block.pinYInches! - shape.height / 2).abs() < 1e-6);
    if (shape.shapeInside &&
        shape.supportsShapeInside &&
        shape.wordWrap &&
        !shape.is1D &&
        !hasTabs &&
        block.textDirection != 1 &&
        shapeInsideDefaultBlock) {
      _writeShapeInsideText(
        buf,
        shape: shape,
        theme: theme,
        runs: runs,
        transform: xf.toString(),
        width: tw,
        height: th,
        marginLeft: ml,
        marginRight: mr,
        marginTop: mt,
        marginBottom: mb,
        verticalAlign: block.verticalAlign,
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
      final firstBandX = hasBullet ? bodyBandX : layoutMl + indentL + indentF;
      final availRest = math.max(
        0.04,
        layoutW - layoutMr - p.style.indentRightInches - bodyBandX,
      );
      final availFirst = math.max(
        0.04,
        layoutW - layoutMr - p.style.indentRightInches - firstBandX,
      );
      final paragraphHasTabs = p.segs.any((seg) => seg.$1.contains('\t'));
      final wrapped = shape.wordWrap && !paragraphHasTabs
          ? _wrapSvgSegs(
              p.segs,
              availRest,
              firstLineMaxWidth: availFirst,
            )
          : <List<(String text, VsdxTextRun run)>>[p.segs];
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
      final horizontalAlign = style.effectiveHorizontalAlign;
      final indentL = style.indentLeftInches;
      final indentF = style.indentFirstInches;
      final textBandX = layout.textBandX;
      final bandRight = layoutW - layoutMr - style.indentRightInches;
      final tabbed = layout.segs.any((seg) => seg.$1.contains('\t'));
      var (anchor, xBody) = switch (horizontalAlign) {
        VsdxHorzAlign.left ||
        VsdxHorzAlign.justify ||
        VsdxHorzAlign.full => (
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
      if (tabbed) {
        anchor = 'start';
        final tabWidth = _writeSvgTabbedTspans(
          layout.segs,
          theme: theme,
          tabSets: shape.richText.tabSets,
          defaultTabStopInches: block.defaultTabStopInches,
          originX: 0,
        ).width;
        xBody = switch (horizontalAlign) {
          VsdxHorzAlign.right => bandRight - tabWidth,
          VsdxHorzAlign.center =>
            textBandX + (bandRight - textBandX - tabWidth) / 2,
          _ => textBandX,
        };
      }
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
      final baseline = pdfCompat ? '' : ' dominant-baseline="middle"';

      if (layout.showBullet) {
        final glyph = _svgBulletGlyph(style);
        // Match libvisio: positive BulletFontSize is absolute, negative is a
        // percentage of the first run, and zero/absent inherits that run.
        final bFs = style.effectiveBulletFontSizeInches(bodyFont);
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
          'fill="#000000" fill-opacity="0.87">${_esc(glyph)}</tspan></text>',
        );
      }

      final body = StringBuffer();
      if (tabbed) {
        body.write(
          _writeSvgTabbedTspans(
            layout.segs,
            theme: theme,
            tabSets: shape.richText.tabSets,
            defaultTabStopInches: block.defaultTabStopInches,
            originX: xBody,
          ).body,
        );
      } else {
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
      }
      // Approximate Visio Justify on the body band only (bullet is separate).
      var justifyAttr = '';
      if (!tabbed &&
          (horizontalAlign == VsdxHorzAlign.justify ||
              horizontalAlign == VsdxHorzAlign.full)) {
        final bandW = math.max(0.04, bandRight - textBandX);
        var natural = 0.0;
        for (final (raw, run) in layout.segs) {
          natural += _estSvgTextWidth(raw, run.charStyle);
        }
        if (natural > 1e-6 && natural < bandW * 0.98) {
          justifyAttr = ' textLength="${_n(bandW)}" lengthAdjust="spacing"';
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

  /// SVG/PDF draw.io label box: the text block positions glyphs, while this
  /// plate hugs their bounds and expands by CSS-style pixel padding.
  void _writeTightLabelPlate(
    StringBuffer buf, {
    required VsdxShape shape,
    required List<VsdxTextRun> runs,
    required String transform,
    required double width,
    required double height,
    required double marginLeft,
    required double marginRight,
    required double marginTop,
    required double marginBottom,
    required VsdxVertAlign verticalAlign,
    required int textDirection,
    required VsdxColor? backgroundColor,
    required double backgroundTransparency,
    required VsdxColor? borderColor,
    required List<VsdxTabSet> tabSets,
    required double defaultTabStopInches,
    required String indent,
  }) {
    var layoutW = width;
    var layoutH = height;
    var ml = marginLeft;
    var mr = marginRight;
    var mt = marginTop;
    var mb = marginBottom;
    final vertical = textDirection == 1;
    if (vertical) {
      layoutW = height;
      layoutH = width;
      ml = marginTop;
      mr = marginBottom;
      mt = marginRight;
      mb = marginLeft;
    }

    var cursor = 0.0;
    var minX = double.infinity;
    var maxX = double.negativeInfinity;
    for (final p in _splitSvgParagraphs(runs)) {
      final horizontalAlign = p.style.effectiveHorizontalAlign;
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
      final restX = ml + indentL + (hasBullet ? bulletGap : 0.0);
      final firstX = hasBullet ? restX : ml + indentL + indentF;
      final bandRight = layoutW - mr - p.style.indentRightInches;
      final paragraphHasTabs = p.segs.any((seg) => seg.$1.contains('\t'));
      final wrapped = shape.wordWrap && !paragraphHasTabs
          ? _wrapSvgSegs(
              p.segs,
              math.max(0.04, bandRight - restX),
              firstLineMaxWidth: math.max(0.04, bandRight - firstX),
            )
          : <List<(String text, VsdxTextRun run)>>[p.segs];
      for (var i = 0; i < wrapped.length; i++) {
        final xBand = i == 0 ? firstX : restX;
        final lineHasTabs = wrapped[i].any((seg) => seg.$1.contains('\t'));
        var natural = lineHasTabs
            ? _writeSvgTabbedTspans(
                wrapped[i],
                theme: VsdxTheme.empty,
                tabSets: tabSets,
                defaultTabStopInches: defaultTabStopInches,
                originX: 0,
              ).width
            : 0.0;
        if (!lineHasTabs) {
          for (final (raw, run) in wrapped[i]) {
            natural += _estSvgTextWidth(raw, run.charStyle);
          }
        }
        final (x0, x1) = switch (horizontalAlign) {
          VsdxHorzAlign.right => (bandRight - natural, bandRight),
          VsdxHorzAlign.center => (
              xBand + (bandRight - xBand - natural) / 2,
              xBand + (bandRight - xBand + natural) / 2,
            ),
          VsdxHorzAlign.justify || VsdxHorzAlign.full => (xBand, bandRight),
          _ => (xBand, xBand + natural),
        };
        minX = math.min(minX, x0);
        maxX = math.max(maxX, x1);
        cursor += lineH;
      }
      cursor += p.style.spaceAfterInches;
    }
    if (!minX.isFinite || !maxX.isFinite) return;
    final textH = math.max(cursor, 0.04);
    final contentBand = layoutH - mt - mb;
    final yCenter = switch (verticalAlign) {
      VsdxVertAlign.top => layoutH - mt - textH / 2,
      VsdxVertAlign.bottom => mb + textH / 2,
      VsdxVertAlign.middle => textH > contentBand + 1e-9
          ? layoutH - mt - textH / 2
          : mb + contentBand / 2,
    };
    final padding = shape.labelPadding;
    final pt = padding.top / pxPerInch;
    final pr = padding.right / pxPerInch;
    final pb = padding.bottom / pxPerInch;
    final pl = padding.left / pxPerInch;
    final fill = backgroundColor == null
        ? 'fill="none"'
        : 'fill="${_hex(backgroundColor)}" '
            'fill-opacity="${_n(_combinedOpacity(backgroundColor, backgroundTransparency))}"';
    final stroke = borderColor == null
        ? 'stroke="none"'
        : 'stroke="${_hex(borderColor)}" stroke-width="${_n(1 / pxPerInch)}"';
    final xf = StringBuffer(transform);
    if (vertical) {
      xf.write(
        ' translate(${_n(width / 2)} ${_n(height / 2)}) rotate(-90) '
        'translate(${_n(-height / 2)} ${_n(-width / 2)})',
      );
    }
    buf.writeln(
      '$indent<g transform="$xf"><rect '
      'x="${_n(minX - pl)}" y="${_n(yCenter - textH / 2 - pb)}" '
      'width="${_n(maxX - minX + pl + pr)}" '
      'height="${_n(textH + pt + pb)}" $fill $stroke/></g>',
    );
  }

  /// SVG/PDF counterpart of the canvas outline-aware line layout.
  void _writeShapeInsideText(
    StringBuffer buf, {
    required VsdxShape shape,
    required VsdxTheme theme,
    required List<VsdxTextRun> runs,
    required String transform,
    required double width,
    required double height,
    required double marginLeft,
    required double marginRight,
    required double marginTop,
    required double marginBottom,
    required VsdxVertAlign verticalAlign,
    required String indent,
  }) {
    final paragraphs = _splitSvgParagraphs(runs);
    final padding = shape.shapeInsidePaddingPx / pxPerInch;
    var top = marginTop;
    var textHeight = 0.0;
    var layouts = <({
      VsdxParaStyle style,
      List<(String text, VsdxTextRun run)> segs,
      double lineHeight,
      double yTop,
      double left,
      double right,
    })>[];

    ({double left, double right}) bandFor(double y0, double y1) {
      final band = shape.shapeInsideBand(y0 / height, y1 / height);
      final left = math.max(marginLeft, (band?.left ?? 0) * width + padding);
      final right = math.min(
        width - marginRight,
        (band?.right ?? 1) * width - padding,
      );
      return (left: left, right: math.max(left + 0.01, right));
    }

    for (var pass = 0; pass < 3; pass++) {
      layouts = [];
      var cursor = 0.0;
      for (final paragraph in paragraphs) {
        cursor += paragraph.style.spaceBeforeInches;
        final lineHeight = _svgParaLineHeight(
          paragraph.segs,
          paragraph.style,
        );
        final paragraphTop = cursor;
        final wrapped = _wrapSvgSegs(
          paragraph.segs,
          math.max(0.01, width - marginLeft - marginRight),
          maxWidthForLine: (index) {
            final band = bandFor(
              top + paragraphTop + index * lineHeight,
              top + paragraphTop + (index + 1) * lineHeight,
            );
            return band.right - band.left;
          },
        );
        for (var index = 0; index < wrapped.length; index++) {
          final band = bandFor(
            top + cursor,
            top + cursor + lineHeight,
          );
          layouts.add((
            style: paragraph.style,
            segs: wrapped[index],
            lineHeight: lineHeight,
            yTop: cursor,
            left: band.left,
            right: band.right,
          ));
          cursor += lineHeight;
        }
        cursor += paragraph.style.spaceAfterInches;
      }
      textHeight = math.max(cursor, 0.04);
      top = switch (verticalAlign) {
        VsdxVertAlign.top => marginTop,
        VsdxVertAlign.bottom => height - marginBottom - textHeight,
        VsdxVertAlign.middle =>
          marginTop + (height - marginTop - marginBottom - textHeight) / 2,
      };
      if (verticalAlign == VsdxVertAlign.middle && top < marginTop) {
        top = marginTop;
      }
    }

    buf.writeln(
      '$indent<g transform="$transform translate(0 ${_n(height)}) scale(1 -1)">',
    );
    for (final layout in layouts) {
      final widthAvailable = layout.right - layout.left;
      final (anchor, x) = switch (layout.style.effectiveHorizontalAlign) {
        VsdxHorzAlign.right => ('end', layout.right),
        VsdxHorzAlign.center => ('middle', layout.left + widthAvailable / 2),
        _ => ('start', layout.left),
      };
      var fontSize = 0.14;
      for (final (_, run) in layout.segs) {
        if (run.text.isNotEmpty && run.charStyle.fontSizeInches > 0) {
          fontSize = run.charStyle.fontSizeInches;
          break;
        }
      }
      final middle = top + layout.yTop + layout.lineHeight / 2;
      final y = pdfCompat ? middle + fontSize * 0.35 : middle;
      final baseline = pdfCompat ? '' : ' dominant-baseline="middle"';
      final body = StringBuffer();
      for (var i = 0; i < layout.segs.length; i++) {
        final (raw, run) = layout.segs[i];
        _writeStyledTspans(
          body,
          raw: raw,
          style: run.charStyle,
          theme: theme,
          xAttr: i == 0 ? 'x="${_n(x)}"' : null,
        );
      }
      buf.writeln(
        '$indent  <text xml:space="preserve" text-anchor="$anchor"$baseline '
        'y="${_n(y)}">$body</text>',
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
    double Function(int lineIndex)? maxWidthForLine,
  }) {
    if (segs.isEmpty) return [<(String, VsdxTextRun)>[]];
    final lines = <List<(String, VsdxTextRun)>>[];
    var cur = <(String, VsdxTextRun)>[];
    var curW = 0.0;
    double widthForLine(int index) => index == 0 && firstLineMaxWidth != null
        ? firstLineMaxWidth
        : (maxWidthForLine?.call(index) ?? maxWidth);
    var lineMax = widthForLine(0);

    void flush() {
      if (cur.isEmpty) return;
      lines.add(cur);
      cur = <(String, VsdxTextRun)>[];
      curW = 0.0;
      lineMax = widthForLine(lines.length);
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
  /// Matches canvas: locale-specific complex-script size, FontScale/tracking,
  /// and 0.7× super/sub size.
  double _estSvgTextWidth(String text, VsdxCharStyle style) {
    double positionedSize(double inches) {
      var size = math.max(inches, 0.04);
      if (style.position != VsdxTextPosition.normal) size *= 0.7;
      return size;
    }

    final fs = positionedSize(style.fontSizeInches);
    final complexFs = style.complexScriptSizeInches == null
        ? fs
        : positionedSize(style.complexScriptSizeInches!);
    final runes = text.runes.toList(growable: false);
    var w = 0.0;
    final smallCaps = style.style.smallCaps;
    final scale = style.fontScale <= 0 ? 1.0 : style.fontScale.clamp(0.1, 4.0);
    for (var i = 0; i < runes.length; i++) {
      final r = runes[i];
      final runeFs = isVisioComplexScriptRune(r) ? complexFs : fs;
      // Match canvas / SVG synthetic small-caps (lowercase → 0.78× capitals).
      final chFs =
          smallCaps && r >= 0x61 && r <= 0x7a ? runeFs * 0.78 : runeFs;
      if (r >= 0x2E80) {
        w += chFs; // CJK / wide ideographs
      } else {
        // SVG export cannot query the installed font. A uniform 0.55 em
        // over-counts narrow glyphs enough to wrap valid Visio labels that
        // LibreOffice and Canvas keep on one line.
        final measuredRune = smallCaps && r >= 0x61 && r <= 0x7a
            ? r - 0x20
            : r;
        w += chFs * _latinAdvanceFactor(measuredRune);
      }
      if (i + 1 < runes.length) {
        // Flutter applies tracking between glyphs. Complex-script tspans use
        // their own size, so their FontScale contribution must do the same.
        w += style.letterSpacingInches + runeFs * (scale - 1.0) * 0.55;
      }
    }
    return w;
  }

  /// Neutral Helvetica/Arial glyph advances used only for SVG line breaking.
  double _latinAdvanceFactor(int rune) {
    if (rune >= 0x30 && rune <= 0x39) return 0.556;
    return switch (rune) {
      0x20 || 0x09 || 0x21 || 0x2c || 0x2e || 0x2f || 0x3a || 0x3b ||
      0x5c =>
        0.278,
      0x22 => 0.355,
      0x23 || 0x24 || 0x3f || 0x4c || 0x5f => 0.556,
      0x25 => 0.889,
      0x26 => 0.667,
      0x27 => 0.191,
      0x28 || 0x29 || 0x2d || 0x5b || 0x5d || 0x60 || 0x7b || 0x7d =>
        0.333,
      0x2a => 0.389,
      0x2b || 0x3c || 0x3d || 0x3e || 0x7e => 0.584,
      0x40 => 1.015,
      0x41 || 0x42 || 0x45 || 0x4b || 0x50 || 0x53 || 0x56 || 0x58 ||
      0x59 =>
        0.667,
      0x43 || 0x44 || 0x48 || 0x4e || 0x52 || 0x55 => 0.722,
      0x46 || 0x54 || 0x5a => 0.611,
      0x47 || 0x4f || 0x51 => 0.778,
      0x49 => 0.278,
      0x4a => 0.500,
      0x4d => 0.833,
      0x57 => 0.944,
      0x5e => 0.469,
      0x61 || 0x62 || 0x64 || 0x65 || 0x67 || 0x68 || 0x6e || 0x6f ||
      0x70 || 0x71 || 0x75 =>
        0.556,
      0x63 || 0x6b || 0x73 || 0x76 || 0x78 || 0x79 || 0x7a => 0.500,
      0x66 || 0x74 => 0.278,
      0x69 || 0x6a || 0x6c => 0.222,
      0x6d => 0.833,
      0x72 => 0.333,
      0x77 => 0.722,
      0x7c => 0.260,
      _ => 0.55,
    };
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
      var tabOffset = 0;
      for (var i = 0; i < parts.length; i++) {
        if (i > 0) flush();
        style = run.paraStyle;
        final tabCount = '\t'.allMatches(parts[i]).length;
        segs.add((
          parts[i],
          run.copyWith(
            text: parts[i],
            tabIndices:
                run.tabIndices.skip(tabOffset).take(tabCount).toList(),
          ),
        ));
        tabOffset += tabCount;
      }
    }
    if (segs.isNotEmpty || out.isEmpty) flush();
    // Match libvisio: a terminal newline closes the visible paragraph but
    // does not create another empty layout row.
    if (runs.isNotEmpty &&
        runs.last.text.endsWith('\n') &&
        out.length > 1 &&
        out.last.segs.every((seg) => seg.$1.isEmpty)) {
      out.removeLast();
    }
    return out;
  }

  ({String body, double width}) _writeSvgTabbedTspans(
    List<(String text, VsdxTextRun run)> segs, {
    required VsdxTheme theme,
    required List<VsdxTabSet> tabSets,
    required double defaultTabStopInches,
    required double originX,
  }) {
    final tokens = <({String text, VsdxTextRun run, int? tabSetIx})>[];
    for (final (raw, run) in segs) {
      var start = 0;
      var tab = 0;
      for (var i = 0; i < raw.length; i++) {
        if (raw.codeUnitAt(i) != 0x09) continue;
        if (i > start) {
          tokens.add((text: raw.substring(start, i), run: run, tabSetIx: null));
        }
        tokens.add((
          text: '',
          run: run,
          tabSetIx: tab < run.tabIndices.length ? run.tabIndices[tab] : 0,
        ));
        tab++;
        start = i + 1;
      }
      if (start < raw.length) {
        tokens.add((text: raw.substring(start), run: run, tabSetIx: null));
      }
    }

    final body = StringBuffer();
    var x = 0.0;
    var maxX = 0.0;
    var forceX = true;
    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      if (token.tabSetIx case final tabSetIx?) {
        var following = 0.0;
        var decimalPrefix = 0.0;
        var sawDecimal = false;
        for (var j = i + 1; j < tokens.length; j++) {
          final next = tokens[j];
          if (next.tabSetIx != null) break;
          following += _estSvgTextWidth(next.text, next.run.charStyle);
          if (!sawDecimal) {
            final dot = next.text.indexOf('.');
            if (dot < 0) {
              decimalPrefix +=
                  _estSvgTextWidth(next.text, next.run.charStyle);
            } else {
              decimalPrefix += _estSvgTextWidth(
                next.text.substring(0, dot),
                next.run.charStyle,
              );
              sawDecimal = true;
            }
          }
        }
        x = visioTabFieldStart(
          tabSets: tabSets,
          tabSetIx: tabSetIx,
          currentPosition: x,
          followingWidth: following,
          decimalPrefixWidth: decimalPrefix,
          defaultTabStop: defaultTabStopInches,
        );
        maxX = math.max(maxX, x);
        forceX = true;
        continue;
      }
      _writeStyledTspans(
        body,
        raw: token.text,
        style: token.run.charStyle,
        theme: theme,
        xAttr: forceX ? 'x="${_n(originX + x)}"' : null,
      );
      x += _estSvgTextWidth(token.text, token.run.charStyle);
      maxX = math.max(maxX, x);
      forceX = false;
    }
    return (body: body.toString(), width: maxX);
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
    final style =
        runs.isNotEmpty ? runs.first.charStyle : VsdxCharStyle.defaults;
    final attrs = _charStyleSvgAttrs(style, theme);

    final xf = StringBuffer('translate(${_n(pinX)} ${_n(pinY)})');
    if (angleRad != 0) {
      xf.write(' rotate(${_n(angleRad * 180 / math.pi)})');
    }
    if (_textFlipX || _textFlipY) {
      xf.write(' scale(${_textFlipX ? -1 : 1} ${_textFlipY ? -1 : 1})');
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
    bool applyComplexScript = true,
  }) {
    if (applyComplexScript &&
        raw.runes.any(isVisioComplexScriptRune) &&
        ((style.complexScriptFont?.isNotEmpty ?? false) ||
            style.complexScriptSizeInches != null)) {
      final chunks = <({String text, bool complex})>[];
      final chunk = StringBuffer();
      bool? complex;
      void flush() {
        if (chunk.isEmpty || complex == null) return;
        chunks.add((text: chunk.toString(), complex: complex));
        chunk.clear();
      }

      for (final rune in raw.runes) {
        final next = isVisioComplexScriptRune(rune);
        if (complex != null && complex != next) flush();
        complex = next;
        chunk.writeCharCode(rune);
      }
      flush();
      var first = true;
      for (final part in chunks) {
        final partStyle = part.complex
            ? style.copyWith(
                fontFamily: style.complexScriptFont ?? style.fontFamily,
                fontSizeInches:
                    style.complexScriptSizeInches ?? style.fontSizeInches,
              )
            : style;
        _writeStyledTspans(
          body,
          raw: part.text,
          style: partStyle,
          theme: theme,
          xAttr: first ? xAttr : null,
          applyComplexScript: false,
        );
        first = false;
      }
      return;
    }
    final text = _applyTextCase(raw, style.textCase);
    final x = xAttr == null ? '' : '$xAttr ';
    if (!style.style.smallCaps || text.isEmpty) {
      final attrs = _charStyleSvgAttrs(style, theme, synthesizeSmallCaps: true);
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
    // libvisio's VSDCharStyle baseline is opaque black.
    final color =
        _resolveColor(c.color, c.themeColorIndex, theme) ?? VsdxColor.black;
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
    // also grows glyph height). Approximate with letter-spacing using the same
    // mean Latin advance (0.55×size) used by [_estSvgTextWidth].
    var letterSpacing = c.letterSpacingInches;
    final fontScale = c.fontScale <= 0 ? 1.0 : c.fontScale.clamp(0.1, 4.0);
    if ((fontScale - 1.0).abs() > 1e-6) {
      letterSpacing += fs * (fontScale - 1.0) * 0.55;
    }
    // Match canvas fontFallback: Latin face then AsianFont for CJK glyphs.
    final family = _svgFontFamily(
      c.fontFamily ?? 'Arial',
      c.asianFont,
      c.complexScriptFont,
    );
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
    if (_layerTint != null) return _layerTint;
    if (themeIdx != null) {
      final themed = theme.resolve(
        themeIdx,
        variationIndex: _variationColorIndex,
      );
      if (themed != null) return themed;
    }
    return raw;
  }

  VsdxColor? _resolveFillColor(VsdxShape shape, VsdxTheme theme) {
    if (_layerTint != null) return _layerTint;
    final themeIdx = shape.fill.themeForegroundIndex;
    if (themeIdx != null) {
      final themed = theme.resolveFill(
        themeIdx,
        variationColorIndex: _variationColorIndex,
        variationStyleIndex: _variationStyleIndex,
        fillMatrix: shape.quickStyleFillMatrix,
      );
      if (themed != null) return themed;
    }
    return shape.fill.foreground;
  }

  /// CSS font-family list: Latin, Asian, complex-script, then sans-serif.
  String _svgFontFamily(String? latin, String? asian, [String? complex]) {
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
    add(complex);
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

  String _strokeN(double v) {
    if (v.isNaN || v.isInfinite) return '0';
    if (v == v.truncateToDouble()) return v.toStringAsFixed(0);
    return v
        .toStringAsFixed(6)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}
