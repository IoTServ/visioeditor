part of 'stencils.dart';

/// A compressed draw.io XML stencil library generated from the vendored
/// draw.io source baseline. Names stay outside the compressed payload so the
/// complete catalog can be searched without inflating all 203 XML documents.
class _DrawioXmlLibraryRecord {
  const _DrawioXmlLibraryRecord({
    required this.sourcePath,
    required this.groupName,
    required this.shapeNames,
    required this.encodedXml,
  });

  final String sourcePath;
  final String groupName;
  final List<String> shapeNames;
  final String encodedXml;
}

final List<StencilGroup> kDrawioXmlStencilGroups = _drawioXmlLibraryRecords
    .map((record) => _DrawioXmlLibrary(record).toStencilGroup())
    .toList(growable: false);

/// draw.io shapes implemented by JavaScript Canvas painters rather than XML.
/// Their default sidebar styles are captured into the same native geometry
/// representation at generation time, so no JavaScript runs in the editor.
final List<StencilGroup> kDrawioJsStencilGroups = _drawioJsLibraryRecords
    .map((record) => _DrawioXmlLibrary(record).toStencilGroup())
    .toList(growable: false);

class _DrawioXmlLibrary {
  _DrawioXmlLibrary(this.record);

  final _DrawioXmlLibraryRecord record;
  List<XmlElement>? _shapes;
  String? _shapesPackage;
  Map<String, XmlElement>? _stencilByName;
  Map<String, VsdxColor>? _libraryStyleKeyDefaults;

  StencilGroup toStencilGroup() => StencilGroup(
        record.groupName,
        <Stencil>[
          for (var index = 0; index < record.shapeNames.length; index++)
            Stencil(
              record.shapeNames[index],
              (id, cx, cy) => build(index, id, cx, cy),
            ),
        ],
      );

  VsdxShape build(int index, int id, double cx, double cy) {
    final shapes = _shapes ??= _decodeShapes();
    if (index < 0 || index >= shapes.length) {
      throw RangeError.index(index, shapes, 'index');
    }
    // Catalog decode has no cell style. mxStencil.getColorValue then
    // uses the node's `default`; Networks2 hub LED is
    // `color="neutralFill"` with no default, while global server (and
    // Sidebar-Network2.js `sn`) share `neutralFill=#9DA6A8`.
    return _DrawioXmlShapeDecoder(
      shapes[index],
      libraryStyleKeyDefaults: _libraryStyleKeyDefaults ??=
          _mxUniqueStencilStyleKeyDefaults(shapes),
      stencilByName: _stencilByName ??=
          _mxStencilRegistry(shapes, _shapesPackage),
    ).build(id, cx, cy);
  }

  List<XmlElement> _decodeShapes() {
    final compressed = base64Decode(record.encodedXml);
    final xmlBytes = GZipDecoder().decodeBytes(compressed);
    final document = XmlDocument.parse(utf8.decode(xmlBytes));
    _shapesPackage = document.rootElement.getAttribute('name');
    final shapes = document.rootElement.findElements('shape').toList();
    if (shapes.length != record.shapeNames.length) {
      throw StateError(
        '${record.sourcePath}: generated ${record.shapeNames.length} names '
        'but decoded ${shapes.length} shapes',
      );
    }
    return shapes;
  }
}

/// Decode one mxStencil `<shape>` the catalog decoder uses.
VsdxShape decodeDrawioMxStencilXml(
  String xml, {
  int id = 1,
  double cx = 3,
  double cy = 3,
  String? shapeName,
}) {
  final document = XmlDocument.parse(xml);
  final root = document.rootElement;
  final shapes = root.name.local == 'shape'
      ? <XmlElement>[root]
      : root.findElements('shape').toList();
  if (shapes.isEmpty) {
    throw StateError('draw.io stencil XML produced no <shape>');
  }
  final registry = _mxStencilRegistry(
    shapes,
    root.name.local == 'shapes' ? root.getAttribute('name') : null,
  );
  final shape = shapeName == null
      ? shapes.first
      : registry[shapeName] ??
          registry[shapeName.toLowerCase()] ??
          registry[shapeName.replaceAll(' ', '_').toLowerCase()];
  if (shape == null) {
    throw StateError('draw.io stencil XML has no shape "$shapeName"');
  }
  return _DrawioXmlShapeDecoder(
    shape,
    stencilByName: registry,
  ).build(id, cx, cy);
}

/// mxStencilRegistry.getStencil keys NestedStencil uses: raw name,
/// lowercase, spaces→underscores, and `shapes@name` prefix.
Map<String, XmlElement> _mxStencilRegistry(
  Iterable<XmlElement> shapes,
  String? packageName,
) {
  final map = <String, XmlElement>{};
  final prefix = (packageName ?? '').trim().toLowerCase();
  void put(String key, XmlElement element) {
    if (key.isEmpty) return;
    map.putIfAbsent(key, () => element);
  }

  for (final shape in shapes) {
    final name = (shape.getAttribute('name') ?? '').trim();
    if (name.isEmpty) continue;
    final slug = name.replaceAll(' ', '_').toLowerCase();
    put(name, shape);
    put(name.toLowerCase(), shape);
    put(slug, shape);
    if (prefix.isNotEmpty) {
      put('$prefix.$slug', shape);
      put('$prefix.${name.toLowerCase()}', shape);
    }
  }
  return map;
}

/// mxAbstractCanvas2D.createState / mxConstants.DEFAULT_FONTSIZE.
/// defaultVertex still pins cell labels at 12 via applyTextStyle.
const double _kMxDefaultFontSize = 11;

/// mxConstants.DEFAULT_FONTFAMILY first face (`Arial,Helvetica`).
/// defaultVertex still pins cell labels at Helvetica via applyTextStyle.
const String _kMxDefaultFontFamily = 'Arial';

/// mxAbstractCanvas2D.createState `fontColor: '#000000'`.
const VsdxColor _kMxDefaultFontColor = VsdxColor.black;

/// Visio Char.Size UI floor is 0.5pt. The old 0.04in (~2.88pt) clamp
/// flattened mxText `font-size:14px` / `9px` on wide composites
/// (Salesforce Header 930px) after catalog scale `1.5 / max(w,h)`, so
/// collectCharIX `fo:font-size` matched. 0.5pt still rejects empty Size.
const double _kMxMinCharSizeInches = 0.5 / 72.0;

/// mxAbstractCanvas2D.createState `dashPattern: '3 3'`.
const List<double> _kMxDefaultDashPattern = <double>[3, 3];

/// mxAbstractCanvas2D.save/restore paint. Path geometry stays live.
class _MxPaintState {
  const _MxPaintState({
    required this.fontSize,
    required this.fontStyle,
    required this.fontFamily,
    required this.fontColor,
    required this.fontBackground,
    this.fontBorder,
    required this.fillColor,
    required this.fillOverride,
    required this.fillIsNone,
    required this.strokeColor,
    required this.strokeIsNone,
    required this.overallAlpha,
    required this.fillAlpha,
    required this.strokeAlpha,
    required this.strokeWidth,
    required this.strokeWidthFixed,
    required this.dashed,
    required this.dashPattern,
    required this.lineCap,
    required this.lineJoin,
    required this.miterLimit,
    required this.shadow,
    required this.sketchEnabled,
    required this.sketchFill,
    required this.sketchGap,
    required this.sketchAngle,
    required this.sketchWeight,
    required this.sketchJiggle,
  });

  final double fontSize;
  final int fontStyle;
  final String? fontFamily;
  final VsdxColor? fontColor;
  final VsdxColor? fontBackground;
  final VsdxColor? fontBorder;
  final VsdxColor? fillColor;
  final VsdxFill? fillOverride;
  final bool fillIsNone;
  final VsdxColor? strokeColor;
  final bool strokeIsNone;
  final double overallAlpha;
  final double fillAlpha;
  final double strokeAlpha;
  final double? strokeWidth;
  final bool strokeWidthFixed;
  final bool dashed;
  final List<double>? dashPattern;
  final LineCap? lineCap;
  final VsdxLineJoin? lineJoin;
  final double? miterLimit;
  final VsdxShadow? shadow;
  final bool sketchEnabled;
  final String? sketchFill;
  final double? sketchGap;
  final double? sketchAngle;
  final double? sketchWeight;
  final double? sketchJiggle;
}

class _DrawioXmlShapeDecoder {
  _DrawioXmlShapeDecoder(
    this.element, {
    Map<String, VsdxColor> libraryStyleKeyDefaults = const {},
    Map<String, XmlElement> stencilByName = const {},
    int includeDepth = 0,
  })  : _libraryStyleKeyDefaults = libraryStyleKeyDefaults,
        _stencilByName = stencilByName,
        _includeDepth = includeDepth,
        // mxStencil.drawShape: numeric / omitted (default "1") shape
        // @strokewidth * minScale. inherit stays null so
        // applyStencilStyle can still pin the palette LineWeight
        // (collectLine).
        _strokeWidth = _mxShapeAttrStrokeWidth(element);

  final XmlElement element;
  final Map<String, VsdxColor> _libraryStyleKeyDefaults;
  final Map<String, XmlElement> _stencilByName;
  final int _includeDepth;
  late final Map<String, VsdxColor> _shapeStyleKeyDefaults =
      _mxStencilStyleKeyDefaults(element);

  late final double sourceWidth = _number(element, 'w', fallback: 100);
  late final double sourceHeight = _number(element, 'h', fallback: 100);
  late final double targetWidth;
  late final double targetHeight;
  late final double scaleX;
  late final double scaleY;
  double _originX = 0;
  double _originY = 0;
  // leftover inches per official canvas pixel. Catalog leftover maps
  // one stencil unit (native cell pixel) to scaleX inches. Overlay
  // include-shape keeps this root scale: `<strokewidth fixed="1">`
  // is width×1 canvas pixel, not nested minScale.
  double _canvasScale = 1;

  final List<VsdxGeometry> _geometries = <VsdxGeometry>[];
  final List<_DrawioStencilLabel> _labels = <_DrawioStencilLabel>[];
  final List<_DrawioColoredPart> _coloredParts = <_DrawioColoredPart>[];
  List<VsdxPathCommand>? _pending;
  double _fontSize = _kMxDefaultFontSize;
  int _fontStyle = 0;
  String? _fontFamily = _kMxDefaultFontFamily;
  VsdxColor? _fontColor = _kMxDefaultFontColor;
  VsdxColor? _fontBackground;
  VsdxColor? _fontBorder;
  VsdxColor? _fillColor;
  VsdxFill? _fillOverride;
  VsdxColor? _strokeColor;
  late final VsdxColor? _styleFill =
      _mxGraphPaintColor(element.getAttribute('fill'));
  late final VsdxColor? _styleStroke =
      _mxGraphPaintColor(element.getAttribute('stroke'));
  bool _fillIsNone = false;
  bool _strokeIsNone = false;
  double _overallAlpha = 1;
  double _fillAlpha = 1;
  double _strokeAlpha = 1;
  double? _strokeWidth;
  bool _strokeWidthFixed = false;
  double? _parentStrokeWeightInches;
  bool _capturedParentStrokeColor = false;
  VsdxColor? _parentStrokeColor;
  double? _parentFillTransparency;
  double? _parentStrokeTransparency;
  bool _dashed = false;
  bool _solidPaintBeforeDash = false;
  bool _parentDashed = false;
  List<double>? _parentDashPattern;
  List<double>? _dashPattern;
  // mxAbstractCanvas2D.createState: lineCap 'flat' (SVG butt) and
  // lineJoin 'miter'. Do not change VsdxLine.defaultLine — that is
  // the Visio factory round cap. libvisio `_lineProperties` case 0
  // emits round cap+join; LineCap 1 is svg:stroke-linecap=butt /
  // stroke-linejoin=miter. An explicit miter join on a round cap
  // is leftover-flattened to LineCap 1 so Draw miters (GMDL mail
  // flap). Join stays null-as-round only when XML sets linejoin=round.
  LineCap? _lineCap = LineCap.extended;
  VsdxLineJoin? _lineJoin = VsdxLineJoin.miter;
  // mxAbstractCanvas2D.createState miterLimit: 10. Visio / ODF default
  // 4; `_lineProperties` never emits svg:stroke-miterlimit, so leftover
  // bakes a spike ribbon when the elbow ratio exceeds 4 (AWS 2 EMR).
  double? _miterLimit = 10;
  bool _capturedParentLineStyle = false;
  LineCap? _parentStrokeCap;
  VsdxLineJoin? _parentStrokeJoin;
  double? _parentMiterLimit;
  VsdxShadow? _shadow;
  VsdxShadow? _parentShadow;
  final List<_MxPaintState> _saveStack = <_MxPaintState>[];
  // mxStencil.drawNode canvas.image may run more than once (host plus
  // include-shape). leftover used a single slot and dropped earlier
  // ForeignData; Draw collectForeignDataType only saw the last PNG.
  final List<_DrawioRaster> _rasters = <_DrawioRaster>[];
  bool _sketchEnabled = false;
  String? _sketchFill;
  double? _sketchGap;
  double? _sketchAngle;
  double? _sketchWeight;
  double? _sketchJiggle;
  // First inherit `_finish` freezes sketch for the parent XForm.
  // include-shape nested `<sketch>` stays on later paints (shared
  // canvas) and on that tile's colored parts — not on host fills that
  // already painted.
  bool _capturedParentSketch = false;
  _DrawioSketchState _parentSketch = const _DrawioSketchState();
  double _penX = 0;
  double _penY = 0;
  double _subX = 0;
  double _subY = 0;
  bool _hasSub = false;

  void _initCatalogMetrics() {
    final safeWidth =
        sourceWidth.isFinite && sourceWidth > 0 ? sourceWidth : 100.0;
    final safeHeight =
        sourceHeight.isFinite && sourceHeight > 0 ? sourceHeight : 100.0;
    // mxStencil.computeAspect uses one scale (or min(sx,sy) when
    // aspect=fixed). Catalog leftover fits the long side to 1.5".
    // Independent 0.25" floors used to make scaleY≫scaleX on eh=0
    // rails (h=1) and 800×20 Range inputs, so leftover CubBezTo /
    // collectEllipse / thumbs were needles or fat bars in Draw.
    final scale = 1.5 / math.max(safeWidth, safeHeight);
    targetWidth = safeWidth * scale;
    targetHeight = safeHeight * scale;
    scaleX = targetWidth / safeWidth;
    scaleY = targetHeight / safeHeight;
    _originX = 0;
    _originY = 0;
    _canvasScale = scaleX.abs();
  }

  void _initOverlayMetrics({
    required double originX,
    required double originY,
    required double overlayScaleX,
    required double overlayScaleY,
    required double canvasScale,
  }) {
    _originX = originX;
    _originY = originY;
    scaleX = overlayScaleX;
    scaleY = overlayScaleY;
    targetWidth = sourceWidth * overlayScaleX.abs();
    targetHeight = sourceHeight * overlayScaleY.abs();
    _canvasScale = canvasScale;
  }

  void _paintSections() {
    for (final sectionName in const <String>['background', 'foreground']) {
      final section = element.getElement(sectionName);
      if (section == null) continue;
      // mxStencil.drawShape: background keeps the canvas shadow;
      // foreground disableShadow calls setShadow(false) after the first
      // fill/stroke. leftover bakes that as ShdwPattern 0 on later
      // siblings so Draw collectFillAndShadow does not offset glyphs.
      // JS Canvas captures flatten paintBackground+paintForeground into
      // one `<foreground>` and already emit `<shadow enabled="0"/>`;
      // only real mxStencil XML with a background section uses this on
      // the host. include-shape nested.drawShape always passes true for
      // nested foreground (`drawChildren(fgNode, true)`), even when the
      // tile has no `<background>`.
      final disableShadow = sectionName == 'foreground' &&
          (_includeDepth > 0 || element.getElement('background') != null);
      for (final child in section.childElements) {
        _consume(child, disableShadow: disableShadow);
      }
    }
    if (_pending != null && _pending!.isNotEmpty) {
      // fillColor=none / strokeColor=none painters still emit a contour
      // (Bootstrap "Button, link") that libvisio needs as a hit box.
      _finish(fill: false, stroke: false);
    }
  }

  VsdxShape build(int id, double cx, double cy) {
    _initCatalogMetrics();
    _paintSections();

    if (_geometries.isEmpty && _rasters.isNotEmpty) {
      // Picture frame matches VsdxShapeFactory.picture: NoFill/NoLine so
      // only the ForeignData bitmap shows. LibreOffice still needs the box
      // for hit-testing.
      _geometries.add(VsdxGeometry(
        noFill: true,
        noLine: true,
        commands: <VsdxPathCommand>[
          const MoveTo(0, 0),
          LineTo(targetWidth, 0),
          LineTo(targetWidth, targetHeight),
          LineTo(0, targetHeight),
          const LineTo(0, 0),
        ],
      ));
    }
    final sourceName = element.getAttribute('name')?.trim();
    if (_geometries.isEmpty &&
        _labels.isEmpty &&
        _coloredParts.isEmpty &&
        _rasters.isEmpty) {
      throw StateError(
        'draw.io stencil ${sourceName ?? id} produced no geometry',
      );
    }
    if (_geometries.isEmpty) {
      // Text-only mxGraph painters (some JS captures) still need a hit box
      // libvisio can attach Text children to. Hex fillcolor children are the
      // same: the parent is a group locPin box, not a filled evenodd path.
      _geometries.add(VsdxGeometry(
        noFill: true,
        noLine: true,
        commands: <VsdxPathCommand>[
          const MoveTo(0, 0),
          LineTo(targetWidth, 0),
          LineTo(targetWidth, targetHeight),
          LineTo(0, targetHeight),
          const LineTo(0, 0),
        ],
      ));
    }
    final inheritFill = _geometries.any((geometry) => !geometry.noFill);
    final inheritLine = _geometries.any((geometry) => !geometry.noLine);
    // Picture-only leftover matches VsdxShapeFactory.picture: NoFill/NoLine
    // so collectFillAndShadow does not wash a frame over ForeignData.
    // mxStencil.drawNode still paints later fill/stroke after `<image>`,
    // so leftover must keep inherit FillPattern / LinePattern when the
    // stencil also has a contour (`_rasters` used to force NoLine).
    final pictureFrameOnly =
        _rasters.isNotEmpty && !inheritFill && !inheritLine;
    var nextId = id + 1;
    final children = <VsdxShape>[];
    for (final part in _coloredParts) {
      children.add(_coloredShape(
        id: nextId++,
        part: part,
        shadow: part.shadow.enabled ? part.shadow : VsdxShadow.disabled,
      ));
    }
    for (final label in _labels) {
      children.add(_labelShape(id: nextId++, label: label));
    }
    // One unflipped bitmap stays on the host (IBM Floating IP Img*).
    // flipH/flipV and a second canvas.image become ForeignData children:
    // leftover FlipX on the host would applyXForm-mirror Geometry, and
    // a single slot dropped earlier PNGs (`tokens.txt` FlipX / ImgWidth).
    final hostRasterEntry =
        (_rasters.length == 1 && !_rasters.first.flipH && !_rasters.first.flipV)
            ? _rasters.first
            : null;
    for (final raster in _rasters) {
      if (identical(raster, hostRasterEntry)) continue;
      final box = _rasterLeftoverBox(raster);
      if (box == null) continue;
      children.add(
        _rasterPictureShape(id: nextId++, raster: raster, box: box),
      );
    }
    // Use Sheet.N like factory / chart stencils. The catalog keeps the
    // human-readable stencil title for the palette; putting it on shape.name
    // would paint as a label fallback when text is empty. Authored mxGraph
    // <text> glyphs (IEC AND, calendar days, …) become children so
    // LibreOffice's libvisio text collector still paints them. Hex
    // fillcolor / strokecolor contours are children too: libvisio
    // collectGeometry concatenates every NoFill=0 section of one shape
    // into one evenodd path, so a black radio dot on a grey disk would
    // otherwise punch a hole.
    // mxStencil <alpha> is canvas.setAlpha. restore() pops it, so capture
    // FillForegndTrans at the inherit fill like _parentStrokeWeightInches.
    // collectFillAndShadow → _fillAndShadowProperties pattern==1 emits
    // draw:opacity = 1 − FillForegndTrans (Networks2 hub shadow 0.25).
    final parentFillTrans = _parentFillTransparency ?? 0.0;
    final parentFill = pictureFrameOnly || (!inheritFill && children.isNotEmpty)
        ? const VsdxFill(pattern: 0)
        : (_styleFill != null
            ? VsdxFill(
                pattern: 1,
                foreground: _styleFill,
                foregroundTransparency: parentFillTrans,
              )
            : VsdxFill(foregroundTransparency: parentFillTrans));
    // restore() / later sibling linecap leak onto collectLine otherwise.
    // Capture at the inherit `_finish` like LineWeight / LineColorTrans.
    final savedCap = _lineCap;
    final savedJoin = _lineJoin;
    final savedMiter = _miterLimit;
    if (inheritLine && _capturedParentLineStyle) {
      _lineCap = _parentStrokeCap;
      _lineJoin = _parentStrokeJoin;
      _miterLimit = _parentMiterLimit;
    }
    // collectLine is shape-level. A later `<strokecolor>` (Filled Edge /
    // Pipe inner fillColor band) must not leak onto the inherit rail
    // Draw strokes via tokens.txt LineColor → svg:stroke.
    final savedStrokeColor = _strokeColor;
    if (inheritLine && _capturedParentStrokeColor) {
      _strokeColor = _parentStrokeColor;
    }
    var parentLine = pictureFrameOnly || (!inheritLine && children.isNotEmpty)
        ? const VsdxLine(pattern: 0)
        : _paintLine(stroke: true);
    if (inheritLine && _capturedParentStrokeColor) {
      _strokeColor = savedStrokeColor;
    }
    if (inheritLine && _capturedParentLineStyle) {
      _lineCap = savedCap;
      _lineJoin = savedJoin;
      _miterLimit = savedMiter;
    }
    if (inheritLine && _styleStroke != null && parentLine.hasLine) {
      parentLine = parentLine.withSolidColor(_styleStroke!);
    }
    if (inheritLine && _parentStrokeWeightInches != null) {
      // restore() re-emits the pre-save strokewidth (often 1) after the
      // contour. collectLine is shape-level, so keep leftover inches
      // captured when parent Geometry was painted (including
      // `<strokewidth fixed="1">` canvas-pixel width).
      parentLine = parentLine.copyWith(
        weightInches: math.max(0.001, _parentStrokeWeightInches!),
      );
    }
    if (inheritLine && _parentDashed) {
      // Arrowheads call setDashed(false) after the rail. collectLine is
      // shape-level, so keep the dash that was in force when parent
      // Geometry was painted.
      parentLine = _lineWithDash(parentLine, _parentDashPattern);
    } else if (inheritLine && _solidPaintBeforeDash) {
      // Later <dashpattern> belongs on siblings.
      parentLine = parentLine.copyWith(
        pattern: parentLine.pattern == 0 ? 0 : 1,
        customDashPattern: null,
        fixedDash: false,
      );
    }
    if (inheritLine &&
        parentLine.hasLine &&
        (_parentStrokeTransparency ?? 0) > 1e-9) {
      // restore() pops <alpha> after inherit fillstroke. LineColorTrans
      // is not a token (`xmlStringToColour` zeros Colour.a); leftover
      // bakes a FillForegndTrans ribbon. Capture Trans at _finish so
      // that bake can run (Cortana / vNIC 0.4–0.5 silhouettes).
      parentLine = parentLine.copyWith(
        transparency: _parentStrokeTransparency,
      );
    }
    final hostBox =
        hostRasterEntry == null ? null : _rasterLeftoverBox(hostRasterEntry);
    final hostPart = hostRasterEntry?.part;
    return _withSketchUserCells(
      _withLineUserCells(VsdxShape(
        id: id,
        name: 'Sheet.$id',
        pinX: cx,
        pinY: cy,
        width: targetWidth,
        height: targetHeight,
        angleRad: _stencilCellRotationRad(),
        geometries: List<VsdxGeometry>.unmodifiable(_geometries),
        connectionPoints: _connectionPoints(),
        children: children,
        shapeKind:
            children.isEmpty ? VsdxShapeKind.normal : VsdxShapeKind.group,
        fill: parentFill,
        line: parentLine,
        shadow: inheritFill
            ? (_parentShadow ?? VsdxShadow.disabled)
            : VsdxShadow.disabled,
        imagePartName: hostPart,
        foreignType: hostPart == null
            ? null
            : VsdxImage.foreignTypeFor(
                mimeType: hostRasterEntry?.mime ?? '',
                partName: hostPart,
              ),
        foreignCompressionType: hostPart == null
            ? null
            : VsdxImage.compressionTypeFor(
                mimeType: hostRasterEntry?.mime ?? '',
                partName: hostPart,
              ),
        imgOffsetXInches: hostBox?.offsetX ?? 0,
        imgOffsetYInches: hostBox?.offsetY ?? 0,
        imgWidthInches: hostBox?.width,
        imgHeightInches: hostBox?.height,
        // Cell STYLE_FLIPH/V is `cellfliph` / `cellflipv`. Image
        // `flipH`/`flipV` leftover-bakes FlipX on a ForeignData child
        // (`draw:mirror-*`). Do not OR the two onto the host — leftover
        // XForm FlipX is what collectXFormData / applyXForm mirrors.
        flipX: _stencilCellFlipH,
        flipY: _stencilCellFlipV,
        richText: _stencilLabelRichText(),
      )),
      _parentSketch,
    );
  }

  void _consume(XmlElement node, {bool disableShadow = false}) {
    switch (node.name.local) {
      case 'path':
        _resetPen();
        _setPending(_decodePath(node));
        break;
      case 'rect':
        _resetPen();
        _setPending(_decodeRect(node));
        break;
      case 'roundrect':
        _resetPen();
        _setPending(_decodeRoundRect(node));
        break;
      case 'ellipse':
        _resetPen();
        _setPending(_decodeEllipse(node));
        break;
      case 'move':
      case 'line':
      case 'curve':
      case 'quad':
      case 'arc':
      case 'close':
        // mxStencil.drawNode treats these as canvas path ops even outside
        // <path> (Cisco Truck's cab crease). NestedStencil.drawNode in the
        // JS capture already did; the Dart decoder used to drop them.
        _appendImplicitPathNode(node);
        break;
      case 'dashed':
        // mxStencil.drawNode: setDashed(dashed == '1'). Omitted / "true"
        // stay solid like official (NestedStencil uses === '1').
        _dashed = node.getAttribute('dashed') == '1';
        break;
      case 'dashpattern':
        // mxStencil.drawNode / stencils.xsd use `pattern`. Cisco Guard /
        // ISDN Switch write `dash="8 8"` / `dash="12 4"` instead; official
        // getAttribute('pattern') is null and createState `3 3` would
        // paint. Honour `dash` so leftover MoveTo gaps match the XML.
        _dashPattern = _parseMxDashPattern(
          node.getAttribute('pattern') ?? node.getAttribute('dash'),
        );
        // `pattern="none"` is an empty list: mxStencil.js still
        // setDashPattern(Number('none')*minScale → NaN). createDashPattern
        // then writes stroke-dasharray="NaN", which SVG paints solid.
        // Do not fall through to createState `3 3` (AWS 4 work package).
        break;
      case 'linecap':
        _lineCap = _mxLineCap(node.getAttribute('cap'));
        break;
      case 'linejoin':
        // mxStencil.drawNode always setLineJoin(join). XSD is miter /
        // round / bevel; Arrow / Decider still write linecap tokens
        // `flat` / `square`. mxSvgCanvas2D then sets stroke-linejoin
        // to that string; SVG drops the invalid value and uses the
        // CSS initial `miter`. VsdxLineJoin.parse maps those to null
        // and would wipe createState miter (or a prior round) so a
        // later round cap leftover-joins from LineCap.
        final join = _mxLineJoin(node.getAttribute('join'));
        if (join != null) _lineJoin = join;
        break;
      case 'miterlimit':
        final limit = _number(node, 'limit', fallback: 10);
        if (limit >= 1) _miterLimit = limit;
        break;
      case 'shadow':
        _applyMxShadow(node);
        break;
      case 'fill':
        _finish(fill: true, stroke: false);
        if (disableShadow) _shadow = null;
        break;
      case 'stroke':
        _finish(fill: false, stroke: true);
        if (disableShadow) _shadow = null;
        break;
      case 'fillstroke':
        _finish(fill: true, stroke: true);
        if (disableShadow) _shadow = null;
        break;
      case 'fillstrokecolor':
        // IBM Cloud `ibm-watson--discovery` writes
        // `<fillstrokecolor color="currentColor"/>` after stroking the
        // 32×32 frame. Official `mxStencil.drawNode` has no case (falls
        // through), so draw.io never paints here. Treating the tag as
        // fillstroke filled that pending rect; leftover then kept a
        // solid FillForegnd plate that Draw painted over the glyph.
        // Hex `color` still sets fill and stroke like fillcolor+strokecolor
        // without painting. `currentColor` / omitted stays inherit.
        _applyMxFillStrokeColor(node);
        break;
      case 'fontsize':
        final size = _number(node, 'size', fallback: _fontSize);
        if (size > 0) _fontSize = size;
        break;
      case 'fontstyle':
        // mxXmlCanvas2D compressed setFontStyle, including 0 so a
        // FONT_ITALIC title does not stick on the next collectCharIX
        // sibling (fo:font-style).
        _fontStyle = _number(node, 'style').round();
        break;
      case 'fontfamily':
        _fontFamily = _mxFontFamily(node.getAttribute('family'));
        break;
      case 'fillcolor':
        _applyMxFill(
          node.getAttribute('color'),
          fallback: node.getAttribute('default'),
        );
        break;
      case 'fillgradient':
        _applyMxFillGradient(node);
        break;
      case 'alpha':
        _overallAlpha = _alphaValue(node);
        break;
      case 'fillalpha':
        _fillAlpha = _alphaValue(node);
        break;
      case 'strokealpha':
        _strokeAlpha = _alphaValue(node);
        break;
      case 'sketch':
        _sketchEnabled = node.getAttribute('enabled') != '0';
        final fill = node.getAttribute('fill');
        if (fill != null && fill.isNotEmpty) _sketchFill = fill;
        final gap = double.tryParse(node.getAttribute('gap') ?? '');
        if (gap != null && gap.isFinite) _sketchGap = gap;
        final angle = double.tryParse(node.getAttribute('angle') ?? '');
        if (angle != null && angle.isFinite) _sketchAngle = angle;
        final weight = double.tryParse(node.getAttribute('weight') ?? '');
        if (weight != null && weight.isFinite) _sketchWeight = weight;
        final jiggle = double.tryParse(node.getAttribute('jiggle') ?? '');
        if (jiggle != null && jiggle.isFinite) _sketchJiggle = jiggle;
        break;
      case 'strokecolor':
        _applyMxStroke(
          node.getAttribute('color'),
          fallback: node.getAttribute('default'),
        );
        break;
      case 'fontcolor':
        _applyMxFont(
          node.getAttribute('color'),
          fallback: node.getAttribute('default'),
        );
        break;
      case 'fontbackgroundcolor':
        _applyMxFontBackground(
          node.getAttribute('color'),
          fallback: node.getAttribute('default'),
        );
        break;
      case 'fontbordercolor':
        // mxText.configureCanvas / mxXmlCanvas2D setFontBorderColor.
        // Visio has no label-border cell; leftover bakes a NoFill sibling
        // Draw collectLine strokes (`tokens.txt` has no label border).
        _applyMxFontBorder(
          node.getAttribute('color'),
          fallback: node.getAttribute('default'),
        );
        break;
      case 'strokewidth':
        // mxStencil.drawNode: width * (fixed=="1" ? 1 : minScale).
        final width = _number(node, 'width');
        if (width > 0) {
          _strokeWidth = width;
          _strokeWidthFixed = node.getAttribute('fixed') == '1';
        }
        break;
      case 'text':
        final runs = _decodeTextRuns(node);
        if (runs.isNotEmpty) {
          _labels.add(_DrawioStencilLabel(
            text: runs.map((run) => run.text).join(),
            x: _number(node, 'x'),
            y: _number(node, 'y'),
            boxWidth: _number(node, 'w'),
            boxHeight: _number(node, 'h'),
            spacingLeft: _number(node, 'spacing-left'),
            spacingRight: _number(node, 'spacing-right'),
            spacingTop: _number(node, 'spacing-top'),
            spacingBottom: _number(node, 'spacing-bottom'),
            align: node.getAttribute('align') ?? 'left',
            valign: node.getAttribute('valign') ?? 'top',
            vertical: node.getAttribute('vertical') == '1',
            wrap: node.getAttribute('wrap') == '1',
            rotationDegrees: _number(node, 'rotation'),
            // mxStencil.drawNode: align-shape="0" ignores shape.rotation
            // when setting canvas.text rotation (still subtracts `rotation=`).
            alignShape: node.getAttribute('align-shape') != '0',
            // mxXmlCanvas2D.text rotation is STYLE_ROTATION; decoder
            // negates into TxtAngle that LibreOffice librevenge:rotate
            // paints (Y-up). STYLE_HORIZONTAL stays `vertical`.
            fontSize: runs.first.fontSize,
            fontStyle: runs.first.fontStyle,
            fontFamily: runs.first.fontFamily,
            color: runs.first.color,
            background: _fontBackground,
            border: _fontBorder,
            // mxText.apply STYLE_TEXT_OPACITY percent, times canvas
            // setAlpha (`<alpha>`). ColorTrans is not a token; a save
            // bakes RGB that collectCharIX maps to fo:color.
            textOpacity: runs.first.textOpacity,
            runs: runs,
          ));
        }
        break;
      case 'image':
        _consumeRaster(node);
        break;
      case 'include-shape':
        _consumeIncludeShape(node);
        break;
      case 'save':
        // mxStencil.drawNode canvas.save(). Android Contextual Action Bar
        // dashes a check, restores, then strokes solid icons. Skipping
        // this leaked dashpattern onto collectLine LinePattern 0xfe.
        _saveStack.add(_snapshotPaint());
        break;
      case 'restore':
        // mxStencil.drawNode canvas.restore(). Empty stack is a no-op
        // like mxAbstractCanvas2D.
        if (_saveStack.isNotEmpty) _restorePaint(_saveStack.removeLast());
        break;
      case 'labelBounds':
        // Parsed on the shape root into TxtPin / TxtWidth for
        // collectTextBlock. Not a paint node.
        break;
      // Hex fillcolor / strokecolor / fontcolor are consumed above so
      // Draw can paint them as sibling shapes (one FillForegnd each).
      // `fillgradient` bakes FillPattern 25–34 so libvisio's two-stop
      // linear (`_fillAndShadowProperties`) keeps AWS brand ramps;
      // `applyStencilStyle.withSolidForeground` would otherwise beige them.
      // `alpha` / `fillalpha` / `strokealpha` become FillForegndTrans /
      // LineColorTrans that `_fillAndShadowProperties` maps to draw:opacity.
      // Inherit fill (Networks2 hub shadow) and inherit stroke
      // (Cortana fillstroke) capture that Trans on the parent at
      // _finish; hex fillcolor already bakes a sibling.
      // `fillstrokecolor` is not fillstroke: official drawNode skips
      // it, so IBM watson's pending 32×32 frame stays stroke-only.
      // `linecap` / `linejoin` / `miterlimit` / `dashpattern` follow
      // mxStencil.drawNode onto collectLine LineCap / LinePattern (custom
      // arrays bake to a MoveTo ribbon because libvisio treats 0xfe as solid).
      // `dashpattern pattern="none"` is NaN in official drawNode, so SVG
      // stroke-dasharray is invalid and Draw must stay solid (AWS 4
      // work package), not createState `3 3`. Cisco `dash="8 8"` (no
      // `pattern`) is the authored array leftover bakes to MoveTo gaps.
      // `shadow` follows mxShape.configureCanvas setShadow onto ShdwPattern
      // that `_fillAndShadowProperties` maps to ODF draw:shadow (hard
      // translate like mxSvgCanvas2D.createShadow, not ShadowBlur).
      // `fontfamily` follows mxStencil.drawNode setFontFamily onto Char.Font
      // that collectCharIX maps to style:font-name.
      // `fontbackgroundcolor` follows mxText.configureCanvas onto TextBkgnd
      // that collectTextBlock maps to fo:background-color.
      // `fontbordercolor` follows mxText.configureCanvas /
      // mxXmlCanvas2D setFontBorderColor onto User.veLabelBorderColor;
      // leftover bakes a locked NoFill sibling Draw collectLine paints
      // (`tokens.txt` has no label border).
      // `text` `textopacity` follows mxText.apply STYLE_TEXT_OPACITY onto
      // Char.transparency, multiplied by canvas setAlpha (`<alpha>` /
      // mxSvgCanvas2D.text `opacity=state.alpha`). fillalpha/strokealpha
      // stay dedicated FillForegndTrans / LineColorTrans. ColorTrans is
      // not a token, so a save bakes RGB that collectCharIX maps to
      // fo:color (xmlStringToColour zeros alpha).
      // `text` `run` children follow mxText html=1 <b>/<font> onto extra
      // Character rows collectCharIX maps to fo:font-weight / fo:color /
      // fo:font-size, and html `<ul><li>` onto collectParaIX Bullet /
      // TextPosAfterBullet (leftover bakes U+2022 because Draw never
      // paints text:bullet-char). `<ol><li>` prefixes "1. " in the
      // Character text (tokens.txt has no decimal list).
      // `labelBounds` follows draw.io mxStencil.getLabelBounds (boundedLbl)
      // onto TxtPin / TxtWidth / TxtHeight that collectTextBlock maps
      // below the stacked Multi-Document sheet.
      // `path rounded="1"` follows mxStencil.drawNode addPoints (move/line
      // only) onto QuadBezTo leftover RelQuadBezTo (`tokens.txt` has no
      // LineJoin; Draw round-joins from LineCap). Other path children
      // fall through to regular MoveTo/LineTo/CubBezTo like official.
      // `text` align-shape="0" follows drawNode onto TxtAngle that
      // counters collectXFormData Angle so Draw keeps the glyph upright.
      // STYLE_FLIPH xor STYLE_FLIPV (one axis) adds Angle instead;
      // leftover FlipX/Y comes from `cellfliph` / `cellflipv`.
      // `image` x/y/w/h follow mxStencil.drawNode onto ImgOffset /
      // ImgWidth that collectForeignDataType maps to svg:x / svg:width.
      // Nested include-shape copies leftover inches (`w*sx, h*sy`) so
      // variable aspect does not keep the nested source square.
      // A later canvas.image (host or another include-shape) leftover
      // appends a ForeignData child so Draw keeps every PNG.
      // `image` flipH/flipV leftover-bakes FlipX on a ForeignData child
      // (`draw:mirror-*`); host FlipX stays `cellfliph` so applyXForm
      // does not mirror later Geometry.
      // `include-shape` follows drawNode stencil.drawShape into the
      // include box (NestedStencil already does). leftover merges
      // nested Geometry in that box so Draw collectGeometry paints it.
      // Nested `<text>` is remapped into host stencil space so TxtPin /
      // Char size follow nested minScale (not the catalog 1.5" scale).
      // Nested `strokewidth="inherit"` follows drawShape (host cell
      // STYLE_STROKEWIDTH, default 1 canvas pixel, not nested minScale).
      // After include-shape the official canvas keeps nested
      // setStrokeWidth / setFontSize; leftover converts those leftover
      // inches back into host stencil units so a later host stroke
      // collectLine matches NestedStencil.
      // Nested save/restore shares canvas.states; leftover seeds a
      // converted copy so nested restore can pop a host save. Unequal
      // counts reset to the entry snapshot (`drawShape` assigns
      // `canvas.states = stack`) so leftover never copies nested
      // leftover saves onto the host (`tokens.txt` LineColor).
      // Later `<strokewidth>` / nested setStrokeWidth leftover-bakes a
      // LineWeight sibling because collectLine is shape-level
      // (`tokens.txt` LineWeight).
      // Nested `aspect="fixed"` follows computeAspect min(sx,sy) +
      // centre so Salesforce icons are not anamorphic XForms.
      // Host `celldirection` north/south follows computeAspect inverse
      // (sx/sy swap + delta) so include-shape tiles match NestedStencil.
      // foreground fill/stroke disableShadow follows drawNode
      // setShadow(false) onto later siblings (tokens.txt ShdwPattern).
      // `fill` / `stroke` / cell keys (fillColor, strokeColor, fontColor)
      // stay on the parent so applyStencilStyle can still recolor the body.
      // Other style keys (fillColor2, …) bake `default` like
      // mxStencil.getColorValue when the catalog has no cell style.
      // A later node, or a unique default on a sibling stencil in the
      // same library (Networks2 `neutralFill`), fills in a missing
      // `default` the way Sidebar-Network2.js `sn` does.
      default:
        break;
    }
  }

  void _consumeRaster(XmlElement node) {
    final src = node.getAttribute('src') ?? '';
    final parsed = _dataUriImage(src);
    if (parsed == null) return;
    final boxW = _number(node, 'w');
    final boxH = _number(node, 'h');
    _rasters.add(_DrawioRaster(
      part: registerDrawioStencilImage(
        parsed.bytes,
        mimeType: parsed.mime,
      ),
      mime: parsed.mime,
      // mxStencil.drawNode image x/y/w/h. libvisio collectForeignDataType
      // maps ImgOffsetX/Y + ImgWidth/Height to svg:x/y/width/height.
      // A missing box stretches the PNG over the XForm (IBM Floating IP
      // is a mid-band icon on a 60×60 cell).
      left: _number(node, 'x'),
      top: _number(node, 'y'),
      boxW: boxW > 1e-9 ? boxW : null,
      boxH: boxH > 1e-9 ? boxH : null,
      flipH: node.getAttribute('flipH') == '1',
      flipV: node.getAttribute('flipV') == '1',
    ));
  }

  /// mxStencil.drawNode include-shape → nested stencil.drawShape in the
  /// include box. NestedStencil already does this at capture; leftover
  /// merges nested Geometry so Draw collectGeometry paints the inset.
  void _consumeIncludeShape(XmlElement node) {
    if (_includeDepth > 8) return;
    final nestedEl = _lookupStencil(node.getAttribute('name'));
    if (nestedEl == null || identical(nestedEl, element)) return;
    final x = _number(node, 'x');
    final y = _number(node, 'y');
    final w = _number(node, 'w');
    final h = _number(node, 'h');
    if (!(w > 1e-9) || !(h > 1e-9)) return;
    final nestedW = _number(nestedEl, 'w', fallback: 100);
    final nestedH = _number(nestedEl, 'h', fallback: 100);
    if (!(nestedW > 1e-9) || !(nestedH > 1e-9)) return;
    // Nested stencil.drawShape canvas.begin would drop an unpainted
    // host path. leftover keeps that contour Draw already collected.
    if (_pending != null && _pending!.isNotEmpty) {
      _finish(fill: false, stroke: false);
    }
    final nested = _DrawioXmlShapeDecoder(
      nestedEl,
      libraryStyleKeyDefaults: _libraryStyleKeyDefaults,
      stencilByName: _stencilByName,
      includeDepth: _includeDepth + 1,
    );
    final nestedStrokeWidth = nested._strokeWidth;
    final nestedStrokeWidthFixed = nested._strokeWidthFixed;
    nested._adoptPaint(this);
    // mxStencil.drawShape setStrokeWidth from the nested stencil attr,
    // not the host canvas width leftover copied above. inherit uses
    // the host cell STYLE_STROKEWIDTH (default 1) in canvas pixels —
    // NestedStencil does not multiply by nested minScale. leftover
    // used to restore null and bake Visio's 0.01" default, so Draw
    // collectLine missed 1×catalog-scale hairlines (weblogos inherit).
    if (nestedStrokeWidth == null) {
      nested._strokeWidth = 1;
      nested._strokeWidthFixed = true;
    } else {
      nested._strokeWidth = nestedStrokeWidth;
      nested._strokeWidthFixed = nestedStrokeWidthFixed;
    }
    // mxStencil.computeAspect in parent stencil / canvas pixels. Nested
    // drawShape uses the host STYLE_DIRECTION (include-shape passes the
    // host shape). leftover used to skip north/south inverse, so a
    // 10×20 tile in an 80×40 include stayed landscape; Draw
    // collectGeometry painted the unrotated box.
    var x0 = x;
    var y0 = y;
    var sx = w / nestedW;
    var sy = h / nestedH;
    final inverse = _stencilDirectionInverse;
    if (inverse) {
      sy = w / nestedH;
      sx = h / nestedW;
      final delta = (w - h) / 2;
      x0 += delta;
      y0 -= delta;
    }
    if ((nestedEl.getAttribute('aspect') ?? '').trim().toLowerCase() ==
        'fixed') {
      sy = math.min(sx, sy);
      sx = sy;
      if (inverse) {
        x0 += (h - nestedW * sx) / 2;
        y0 += (w - nestedH * sy) / 2;
      } else {
        x0 += (w - nestedW * sx) / 2;
        y0 += (h - nestedH * sy) / 2;
      }
    }
    nested._initOverlayMetrics(
      originX: _x(x0),
      originY: _y(y0 + nestedH * sy),
      overlayScaleX: sx * scaleX,
      overlayScaleY: sy * scaleY,
      canvasScale: _canvasScale,
    );
    // mxStencil.drawNode include-shape shares the canvas. Host
    // setDashPattern already multiplied by host minScale; nested
    // `_fixedDashPatternValues` would multiply again by nested
    // min(sx,sy). Fold leftover inches into nested stencil units
    // so Draw collectLine gaps match NestedStencil.
    nested._scaleAdoptedCanvasDashFrom(this);
    nested._scaleAdoptedCanvasFontFrom(this);
    // mxStencil.drawShape include-shape shares canvas.states. Nested
    // restore can pop a host save (current paint), but unequal
    // save/restore counts reset `canvas.states = stack` to the entry
    // snapshot — leftover keeps the host stack and only seeds a
    // converted copy so nested restore can reach those saves.
    nested._saveStack
      ..clear()
      ..addAll([
        for (final saved in _saveStack)
          nested._paintStateInUnitsOf(saved, from: this),
      ]);
    nested._paintSections();
    _geometries.addAll(nested._geometries);
    _coloredParts.addAll(nested._coloredParts);
    // Nested `_consume` stores text in nested stencil units. Geometry
    // already went through nested `_x`/`_y` (include overlay). Labels
    // used to wait for the host `_labelShape`, which multiplied by the
    // catalog 1.5" scale, so include-shape glyphs sat at the host origin
    // and Char size ignored nested minScale. Remap into host stencil
    // space so collectTextBlock / collectCharIX match NestedStencil.
    _labels.addAll([
      for (final label in nested._labels)
        nested._labelInParentStencilSpace(label, parent: this),
    ]);
    for (final nestedRaster in nested._rasters) {
      // Nested overlay already mapped geometry through leftover `_x`/`_y`.
      // Official canvas.image is `w*sx, h*sy` in those canvas pixels.
      // Convert nested leftover Img* back into host stencil units so
      // host leftover matches NestedStencil. Append — do not replace
      // a host image leftover already collected.
      final leftoverBox = nested._rasterLeftoverBox(nestedRaster);
      if (leftoverBox != null) {
        _rasters.add(_rasterFromLeftover(leftoverBox, nestedRaster));
      } else {
        _rasters.add(_DrawioRaster(
          part: nestedRaster.part,
          mime: nestedRaster.mime,
          left: x0 + (nestedRaster.left ?? 0) * sx,
          top: y0 + (nestedRaster.top ?? 0) * sy,
          boxW: nestedRaster.boxW == null ? null : nestedRaster.boxW! * sx,
          boxH: nestedRaster.boxH == null ? null : nestedRaster.boxH! * sy,
          flipH: nestedRaster.flipH,
          flipV: nestedRaster.flipV,
        ));
      }
    }
    // Official canvas is shared; nested setStrokeWidth / fillcolor stay.
    // leftover scale-dependent state is leftover inches on the nested
    // decoder — copy those into host stencil units, not nested XML units.
    _adoptNestedCanvas(nested);
  }

  XmlElement? _lookupStencil(String? raw) {
    final name = (raw ?? '').trim();
    if (name.isEmpty || _stencilByName.isEmpty) return null;
    return _stencilByName[name] ??
        _stencilByName[name.toLowerCase()] ??
        _stencilByName[name.replaceAll(' ', '_').toLowerCase()];
  }

  /// mxStencil.drawNode include-shape shares the canvas. Nested
  /// `setStrokeWidth(width * minScale)` / `setFontSize(size * minScale)`
  /// / `setDashPattern(part * minScale)` stay for later host paint.
  /// leftover `_strokeWidth` / `_fontSize` / `_dashPattern` are stencil
  /// units interpreted with the current decoder's scale, so copy nested
  /// leftover inches back into host units.
  void _adoptNestedCanvas(_DrawioXmlShapeDecoder nested) {
    final hostMin = math.min(scaleX.abs(), scaleY.abs());
    final nestedMin = math.min(nested.scaleX.abs(), nested.scaleY.abs());
    final hostDash = _dashPattern;
    _adoptPaint(nested);
    if (hostMin < 1e-12) return;
    // Nested drawShape always setStrokeWidth from the nested stencil.
    if (nested._strokeWidth != null) {
      _strokeWidth = nested._strokeWeightInches / hostMin;
      _strokeWidthFixed = false;
    }
    // NestedStencil last setFontSize / setDashPattern stay on the
    // shared canvas. leftover `_fontSize` / `_dashPattern` are stencil
    // units of the nested overlay — map leftover inches back to host.
    if (nestedMin > 1e-12) {
      _fontSize = nested._fontSize * nestedMin / hostMin;
    }
    final dashes = nested._dashPattern;
    if (dashes != null && dashes.isEmpty) {
      _dashPattern = const <double>[];
    } else if (dashes != null && dashes.isNotEmpty && nestedMin > 1e-12) {
      _dashPattern = [
        for (final value in dashes) value * nestedMin / hostMin,
      ];
    } else {
      _dashPattern = hostDash == null ? null : List<double>.of(hostDash);
    }
  }

  /// Map [source] leftover inches (from [from]'s stencil units) into this
  /// overlay's stencil units. include-shape nested restore pops host
  /// saves; `_strokeWidth` / `_fontSize` / `_dashPattern` are stencil
  /// units of the decoder that snapshotted them.
  _MxPaintState _paintStateInUnitsOf(
    _MxPaintState source, {
    required _DrawioXmlShapeDecoder from,
  }) {
    final fromMin = math.min(from.scaleX.abs(), from.scaleY.abs());
    final toMin = math.min(scaleX.abs(), scaleY.abs());
    final ratio = (fromMin < 1e-12 || toMin < 1e-12) ? 1.0 : fromMin / toMin;
    double? strokeWidth;
    final srcWidth = source.strokeWidth;
    if (srcWidth != null) {
      final fromScale =
          source.strokeWidthFixed ? from._canvasScale.abs() : fromMin;
      final inches =
          fromScale < 1e-12 ? srcWidth : math.max(0.001, srcWidth * fromScale);
      strokeWidth = toMin < 1e-12 ? inches : inches / toMin;
    }
    final dashes = source.dashPattern;
    return _MxPaintState(
      fontSize: source.fontSize * ratio,
      fontStyle: source.fontStyle,
      fontFamily: source.fontFamily,
      fontColor: source.fontColor,
      fontBackground: source.fontBackground,
      fontBorder: source.fontBorder,
      fillColor: source.fillColor,
      fillOverride: source.fillOverride,
      fillIsNone: source.fillIsNone,
      strokeColor: source.strokeColor,
      strokeIsNone: source.strokeIsNone,
      overallAlpha: source.overallAlpha,
      fillAlpha: source.fillAlpha,
      strokeAlpha: source.strokeAlpha,
      strokeWidth: strokeWidth,
      strokeWidthFixed: false,
      dashed: source.dashed,
      dashPattern: dashes == null
          ? null
          : dashes.isEmpty
              ? const <double>[]
              : [for (final value in dashes) value * ratio],
      lineCap: source.lineCap,
      lineJoin: source.lineJoin,
      miterLimit: source.miterLimit,
      shadow: source.shadow,
      sketchEnabled: source.sketchEnabled,
      sketchFill: source.sketchFill,
      sketchGap: source.sketchGap,
      sketchAngle: source.sketchAngle,
      sketchWeight: source.sketchWeight,
      sketchJiggle: source.sketchJiggle,
    );
  }

  /// Host `setDashPattern(n*hostMinScale)` leftover inches, expressed in
  /// this overlay's stencil units so `_fixedDashPatternValues` does not
  /// apply nested minScale a second time.
  /// Host `setDashPattern(n*hostMinScale)` leftover inches, expressed in
  /// this overlay's stencil units so `_fixedDashPatternValues` does not
  /// apply nested minScale a second time.
  void _scaleAdoptedCanvasDashFrom(_DrawioXmlShapeDecoder host) {
    if (!_dashed) return;
    if (_dashPattern != null && _dashPattern!.isEmpty) return;
    final hostMin = math.min(host.scaleX.abs(), host.scaleY.abs());
    final nestedMin = math.min(scaleX.abs(), scaleY.abs());
    if (nestedMin < 1e-12) return;
    final source = _dashPattern ?? _kMxDefaultDashPattern;
    _dashPattern = [
      for (final value in source) value * hostMin / nestedMin,
    ];
  }

  /// Host `setFontSize(size*hostMinScale)` leftover inches, expressed in
  /// this overlay's stencil units so `_labelInParentStencilSpace` does
  /// not apply nested minScale a second time.
  void _scaleAdoptedCanvasFontFrom(_DrawioXmlShapeDecoder host) {
    final hostMin = math.min(host.scaleX.abs(), host.scaleY.abs());
    final nestedMin = math.min(scaleX.abs(), scaleY.abs());
    if (nestedMin < 1e-12) return;
    _fontSize = _fontSize * hostMin / nestedMin;
  }

  void _adoptPaint(_DrawioXmlShapeDecoder other) {
    _fontSize = other._fontSize;
    _fontStyle = other._fontStyle;
    _fontFamily = other._fontFamily;
    _fontColor = other._fontColor;
    _fontBackground = other._fontBackground;
    _fontBorder = other._fontBorder;
    _fillColor = other._fillColor;
    _fillOverride = other._fillOverride;
    _fillIsNone = other._fillIsNone;
    _strokeColor = other._strokeColor;
    _strokeIsNone = other._strokeIsNone;
    _overallAlpha = other._overallAlpha;
    _fillAlpha = other._fillAlpha;
    _strokeAlpha = other._strokeAlpha;
    _strokeWidth = other._strokeWidth;
    _strokeWidthFixed = other._strokeWidthFixed;
    _dashed = other._dashed;
    _dashPattern = other._dashPattern == null
        ? null
        : List<double>.of(other._dashPattern!);
    _lineCap = other._lineCap;
    _lineJoin = other._lineJoin;
    _miterLimit = other._miterLimit;
    _shadow = other._shadow;
    _sketchEnabled = other._sketchEnabled;
    _sketchFill = other._sketchFill;
    _sketchGap = other._sketchGap;
    _sketchAngle = other._sketchAngle;
    _sketchWeight = other._sketchWeight;
    _sketchJiggle = other._sketchJiggle;
  }

  /// Visio Image Properties are Y-up from the shape origin. mxStencil
  /// image y is top-down stencil space, same as `<rect>`.
  ({double offsetX, double offsetY, double width, double height})?
      _rasterLeftoverBox(_DrawioRaster raster) {
    final boxW = raster.boxW;
    final boxH = raster.boxH;
    if (boxW != null && boxH != null) {
      final width = boxW * scaleX.abs();
      final height = boxH * scaleY.abs();
      if (width <= 1e-9 || height <= 1e-9) return null;
      return (
        offsetX: _x(raster.left ?? 0),
        offsetY: _y((raster.top ?? 0) + boxH),
        width: width,
        height: height,
      );
    }
    if (targetWidth <= 1e-9 || targetHeight <= 1e-9) return null;
    return (
      offsetX: _x(0),
      offsetY: _y(sourceHeight),
      width: targetWidth,
      height: targetHeight,
    );
  }

  /// Inverse of [_rasterLeftoverBox]: leftover inches → this decoder's
  /// stencil units. include-shape copies nested overlay leftover.
  _DrawioRaster _rasterFromLeftover(
    ({double offsetX, double offsetY, double width, double height}) box,
    _DrawioRaster source,
  ) {
    final left = scaleX.abs() < 1e-12 ? 0.0 : (box.offsetX - _originX) / scaleX;
    final boxW = scaleX.abs() < 1e-12 ? box.width : box.width / scaleX.abs();
    final boxH = scaleY.abs() < 1e-12 ? box.height : box.height / scaleY.abs();
    final bottomSrc = scaleY.abs() < 1e-12
        ? sourceHeight
        : sourceHeight - (box.offsetY - _originY) / scaleY;
    return _DrawioRaster(
      part: source.part,
      mime: source.mime,
      left: left,
      top: bottomSrc - boxH,
      boxW: boxW,
      boxH: boxH,
      flipH: source.flipH,
      flipV: source.flipV,
    );
  }

  _MxPaintState _snapshotPaint() => _MxPaintState(
        fontSize: _fontSize,
        fontStyle: _fontStyle,
        fontFamily: _fontFamily,
        fontColor: _fontColor,
        fontBackground: _fontBackground,
        fontBorder: _fontBorder,
        fillColor: _fillColor,
        fillOverride: _fillOverride,
        fillIsNone: _fillIsNone,
        strokeColor: _strokeColor,
        strokeIsNone: _strokeIsNone,
        overallAlpha: _overallAlpha,
        fillAlpha: _fillAlpha,
        strokeAlpha: _strokeAlpha,
        strokeWidth: _strokeWidth,
        strokeWidthFixed: _strokeWidthFixed,
        dashed: _dashed,
        dashPattern: _dashPattern == null
            ? null
            : List<double>.unmodifiable(_dashPattern!),
        lineCap: _lineCap,
        lineJoin: _lineJoin,
        miterLimit: _miterLimit,
        shadow: _shadow,
        sketchEnabled: _sketchEnabled,
        sketchFill: _sketchFill,
        sketchGap: _sketchGap,
        sketchAngle: _sketchAngle,
        sketchWeight: _sketchWeight,
        sketchJiggle: _sketchJiggle,
      );

  void _restorePaint(_MxPaintState saved) {
    _fontSize = saved.fontSize;
    _fontStyle = saved.fontStyle;
    _fontFamily = saved.fontFamily;
    _fontColor = saved.fontColor;
    _fontBackground = saved.fontBackground;
    _fontBorder = saved.fontBorder;
    _fillColor = saved.fillColor;
    _fillOverride = saved.fillOverride;
    _fillIsNone = saved.fillIsNone;
    _strokeColor = saved.strokeColor;
    _strokeIsNone = saved.strokeIsNone;
    _overallAlpha = saved.overallAlpha;
    _fillAlpha = saved.fillAlpha;
    _strokeAlpha = saved.strokeAlpha;
    _strokeWidth = saved.strokeWidth;
    _strokeWidthFixed = saved.strokeWidthFixed;
    _dashed = saved.dashed;
    _dashPattern = saved.dashPattern == null
        ? null
        : List<double>.from(saved.dashPattern!);
    _lineCap = saved.lineCap;
    _lineJoin = saved.lineJoin;
    _miterLimit = saved.miterLimit;
    _shadow = saved.shadow;
    _sketchEnabled = saved.sketchEnabled;
    _sketchFill = saved.sketchFill;
    _sketchGap = saved.sketchGap;
    _sketchAngle = saved.sketchAngle;
    _sketchWeight = saved.sketchWeight;
    _sketchJiggle = saved.sketchJiggle;
  }

  void _resetPen() {
    _penX = 0;
    _penY = 0;
    _subX = 0;
    _subY = 0;
    _hasSub = false;
  }

  void _setPending(List<VsdxPathCommand> commands) {
    if (commands.isEmpty) return;
    // mxActor fillAndStroke paints every subpath opened since begin().
    // CrossbarShape.redrawPath calls end() between ticks; capture used
    // to emit three <path> nodes and this replace kept only the midline.
    // Adjacent path elements before fill/stroke are one Geometry.
    if (_pending == null || _pending!.isEmpty) {
      _pending = List<VsdxPathCommand>.of(commands);
      return;
    }
    _pending!.addAll(commands);
  }

  void _appendImplicitPathNode(XmlElement node) {
    final commands = _pending ?? <VsdxPathCommand>[];
    _decodePathNode(node, commands);
    if (commands.isEmpty) return;
    _pending = commands;
  }

  /// IBM Cloud `fillstrokecolor color`. Official drawNode skips the
  /// tag; a hex still pins both channels so a later fillstroke uses it.
  void _applyMxFillStrokeColor(XmlElement node) {
    final raw = (node.getAttribute('color') ?? '').trim();
    if (raw.isEmpty || raw.toLowerCase() == 'currentcolor') return;
    _applyMxFill(raw, fallback: node.getAttribute('default'));
    _applyMxStroke(raw, fallback: node.getAttribute('default'));
  }

  void _applyMxFill(String? raw, {String? fallback}) {
    _fillOverride = null;
    final token = (raw ?? '').trim();
    final lower = token.toLowerCase();
    if (token.isEmpty || lower == 'fill' || lower == 'default') {
      _fillColor = null;
      _fillIsNone = false;
      return;
    }
    if (lower == 'none' || lower == 'transparent') {
      _fillColor = null;
      _fillIsNone = true;
      return;
    }
    if (lower == 'stroke') {
      _fillColor = _strokeColor;
      _fillIsNone = _strokeIsNone;
      return;
    }
    final parsed = _mxGraphPaintColor(token);
    if (parsed != null) {
      _fillColor = parsed;
      _fillIsNone = false;
      return;
    }
    // mxStencil.getColorValue: missing style key uses `default`, then
    // a unique library default (Networks2 hub `neutralFill`).
    // Android Keyboard fillColor3=none must not inherit the palette fill.
    if (_styleKeyIsNone(token, fallback)) {
      _fillColor = null;
      _fillIsNone = true;
      return;
    }
    _fillColor = _styleKeyColor(token, fallback);
    _fillIsNone = false;
  }

  /// mxGraph south: fill at top, gradient at bottom. libvisio linear
  /// `draw:start-color=FillBkgnd`, `draw:end-color=FillForegnd`, and ODF
  /// `draw:angle` 0 is bottom→top (north), 180 top→bottom (south),
  /// 90 left→right (east), 270 right→left (west).
  void _applyMxFillGradient(XmlElement node) {
    final start = _mxGraphPaintColor(node.getAttribute('color1'));
    final end = _mxGraphPaintColor(node.getAttribute('color2'));
    if (start == null) {
      _applyMxFill(
        node.getAttribute('color1'),
        fallback: node.getAttribute('default'),
      );
      return;
    }
    final dir = (node.getAttribute('direction') ?? 'south').toLowerCase();
    final alpha1 = node.getAttribute('alpha1') == null
        ? 1.0
        : _number(node, 'alpha1', fallback: 1);
    final alpha2 = node.getAttribute('alpha2') == null
        ? 1.0
        : _number(node, 'alpha2', fallback: 1);
    _fillColor = start;
    _fillIsNone = false;
    final packedStops = _parseMxGradientStops(node.getAttribute('stops'));
    if (packedStops.length >= 2) {
      final pattern = _mxFillPatternForDirection(dir);
      final angleAttr = node.getAttribute('angle');
      final angleRad =
          double.tryParse(angleAttr ?? '') ?? _mxFillGradientAngleRad(dir);
      final radial = dir == 'radial';
      _fillOverride = VsdxFill(
        foreground: radial ? packedStops.first.color : packedStops.last.color,
        background: radial ? packedStops.last.color : packedStops.first.color,
        pattern: pattern,
        foregroundTransparency:
            (1 - (radial ? alpha1 : alpha2)).clamp(0.0, 1.0),
        backgroundTransparency:
            (1 - (radial ? alpha2 : alpha1)).clamp(0.0, 1.0),
        gradient: VsdxGradient(
          stops: packedStops,
          type: radial ? VsdxGradientType.radial : VsdxGradientType.linear,
          angleRad: angleRad,
        ),
      );
      return;
    }
    // Same RGB with different alphas is a fade Draw cannot store in
    // FillPattern 25–40 (`librevenge:*-opacity` is ignored). Keep the
    // two Trans cells so leftover bakes SoftEdges PNG.
    if (end == null || (start == end && (alpha1 - alpha2).abs() <= 1e-9)) {
      _applyMxFill(
        node.getAttribute('color1'),
        fallback: node.getAttribute('default'),
      );
      return;
    }
    // ODF axial (FillPattern 26 / 29): start-color=FillForegnd at the
    // centre, end-color=FillBkgnd at the edges. color1 is the peak.
    if (dir.startsWith('axial')) {
      final horiz = dir.contains('east') || dir.contains('west');
      _fillOverride = VsdxFill(
        foreground: start,
        background: end,
        pattern: horiz ? 26 : 29,
        foregroundTransparency: (1 - alpha1).clamp(0.0, 1.0),
        backgroundTransparency: (1 - alpha2).clamp(0.0, 1.0),
      );
      return;
    }
    final pattern = _mxFillPatternForDirection(dir);
    final radial = dir == 'radial';
    _fillOverride = VsdxFill(
      foreground: radial ? start : end,
      background: radial ? end : start,
      pattern: pattern,
      foregroundTransparency: (1 - (radial ? alpha1 : alpha2)).clamp(0.0, 1.0),
      backgroundTransparency: (1 - (radial ? alpha2 : alpha1)).clamp(0.0, 1.0),
    );
  }

  VsdxFill _paintFill() {
    final trans = _fillTransparency;
    if (_fillOverride != null) {
      final fill = _fillOverride!;
      if (trans <= 1e-9) return fill;
      return fill.copyWith(
        foregroundTransparency:
            (1 - (1 - fill.foregroundTransparency) * (1 - trans))
                .clamp(0.0, 1.0),
        backgroundTransparency:
            (1 - (1 - fill.backgroundTransparency) * (1 - trans))
                .clamp(0.0, 1.0),
      );
    }
    if (_fillColor != null) {
      return VsdxFill(
        foreground: _fillColor,
        pattern: 1,
        foregroundTransparency: trans,
      );
    }
    return VsdxFill.defaultFill;
  }

  double get _fillTransparency =>
      (1 - (_overallAlpha * _fillAlpha).clamp(0.0, 1.0)).clamp(0.0, 1.0);

  double get _strokeTransparency =>
      (1 - (_overallAlpha * _strokeAlpha).clamp(0.0, 1.0)).clamp(0.0, 1.0);

  double _alphaValue(XmlElement node) =>
      _number(node, 'alpha', fallback: 1).clamp(0.0, 1.0).toDouble();

  /// STYLE_TEXT_OPACITY percent × canvas setAlpha (`<alpha>`).
  double _opacityPercentWithCanvasAlpha(double percent) =>
      (percent * _overallAlpha.clamp(0.0, 1.0)).clamp(0.0, 100.0);

  void _applyMxStroke(String? raw, {String? fallback}) {
    final token = (raw ?? '').trim();
    final lower = token.toLowerCase();
    if (token.isEmpty || lower == 'stroke' || lower == 'default') {
      _strokeColor = null;
      _strokeIsNone = false;
      return;
    }
    if (lower == 'none' || lower == 'transparent') {
      _strokeColor = null;
      _strokeIsNone = true;
      return;
    }
    if (lower == 'fill') {
      _strokeColor = _fillColor;
      _strokeIsNone = _fillIsNone;
      return;
    }
    final parsed = _mxGraphPaintColor(token);
    if (parsed != null) {
      _strokeColor = parsed;
      _strokeIsNone = false;
      return;
    }
    if (_styleKeyIsNone(token, fallback)) {
      _strokeColor = null;
      _strokeIsNone = true;
      return;
    }
    _strokeColor = _styleKeyColor(token, fallback);
    _strokeIsNone = false;
  }

  void _applyMxFont(String? raw, {String? fallback}) {
    final token = (raw ?? '').trim();
    final lower = token.toLowerCase();
    if (token.isEmpty || lower == 'default' || lower == 'none') {
      _fontColor = null;
      return;
    }
    if (lower == 'fill') {
      _fontColor = _fillColor;
      return;
    }
    if (lower == 'stroke' || lower == 'font') {
      _fontColor = _strokeColor;
      return;
    }
    final parsed = _mxGraphPaintColor(token);
    if (parsed != null) {
      _fontColor = parsed;
      return;
    }
    if (_styleKeyIsNone(token, fallback)) {
      _fontColor = null;
      return;
    }
    _fontColor = _styleKeyColor(token, fallback);
  }

  void _applyMxFontBackground(String? raw, {String? fallback}) {
    final token = (raw ?? '').trim();
    final lower = token.toLowerCase();
    if (token.isEmpty || lower == 'default' || lower == 'none') {
      _fontBackground = null;
      return;
    }
    final parsed = _mxGraphPaintColor(token);
    if (parsed != null) {
      _fontBackground = parsed;
      return;
    }
    if (_styleKeyIsNone(token, fallback)) {
      _fontBackground = null;
      return;
    }
    _fontBackground = _styleKeyColor(token, fallback);
  }

  void _applyMxFontBorder(String? raw, {String? fallback}) {
    final token = (raw ?? '').trim();
    final lower = token.toLowerCase();
    if (token.isEmpty || lower == 'default' || lower == 'none') {
      _fontBorder = null;
      return;
    }
    final parsed = _mxGraphPaintColor(token);
    if (parsed != null) {
      _fontBorder = parsed;
      return;
    }
    if (_styleKeyIsNone(token, fallback)) {
      _fontBorder = null;
      return;
    }
    _fontBorder = _styleKeyColor(token, fallback);
  }

  /// mxStencil.getColorValue: cell style, then node `default`, then a
  /// `default` already seen on this shape, then a unique default from
  /// another stencil in the same XML library (Networks2 `neutralFill`).
  VsdxColor? _styleKeyColor(String token, String? fallback) {
    if (token.isEmpty || _mxIsCellStyleColorKey(token)) return null;
    return _mxGraphPaintColor(fallback) ??
        _shapeStyleKeyDefaults[token] ??
        _libraryStyleKeyDefaults[token];
  }

  bool _styleKeyIsNone(String token, String? fallback) {
    if (token.isEmpty || _mxIsCellStyleColorKey(token)) return false;
    return (fallback ?? '').trim().toLowerCase() == 'none';
  }

  /// mxText html `<run fontcolor>`. `default` is defaultVertex /
  /// mxConstants.DEFAULT_FONTCOLOR #000000, not an unknown token that
  /// `_mxGraphPaintColor` leaves null so `run.color ?? label.color`
  /// rides the previous sibling's hex (Roadmap Lorem after Label).
  /// Omitted attr still inherits the canvas `<fontcolor>` token.
  VsdxColor? _mxRunFontColor(String? raw) {
    if (raw == null) return _fontColor;
    final token = raw.trim();
    final lower = token.toLowerCase();
    if (token.isEmpty || lower == 'none') return _fontColor;
    if (lower == 'default' || lower == 'font') return _kMxDefaultFontColor;
    return _mxGraphPaintColor(token) ?? _fontColor;
  }

  /// mxText html=1: `<run>` children are extra Character rows. A bare
  /// `str=` label stays a single collectCharIX run.
  ///
  /// mxSvgCanvas2D.text sets `opacity=state.alpha`. leftover
  /// `textopacity` is STYLE_TEXT_OPACITY percent; canvas `<alpha>` must
  /// still multiply so include-shape nested glyphs keep host setAlpha
  /// (`tokens.txt` has no ColorTrans). fillalpha/strokealpha do not.
  List<_DrawioStencilLabelRun> _decodeTextRuns(XmlElement node) {
    final parentRaw = _number(node, 'textopacity', fallback: 100);
    final parentOpacity = _opacityPercentWithCanvasAlpha(parentRaw);
    final raw = <_DrawioStencilLabelRun>[
      for (final el in node.childElements)
        if (el.name.local == 'run')
          _DrawioStencilLabelRun(
            text: el.getAttribute('str') ?? '',
            fontSize: _number(el, 'fontsize', fallback: _fontSize),
            fontStyle: _number(
              el,
              'fontstyle',
              fallback: _fontStyle.toDouble(),
            ).round(),
            fontFamily:
                _mxFontFamily(el.getAttribute('fontfamily')) ?? _fontFamily,
            color: _mxRunFontColor(el.getAttribute('fontcolor')),
            textOpacity: _opacityPercentWithCanvasAlpha(
              el.getAttribute('textopacity') == null
                  ? parentRaw
                  : _number(el, 'textopacity'),
            ),
            position:
                el.getAttribute('pos') == null ? 0 : _number(el, 'pos').round(),
            align: el.getAttribute('align'),
            marginLeft: _number(el, 'margin-left'),
            marginRight: _number(el, 'margin-right'),
            marginTop: _number(el, 'margin-top'),
            marginBottom: _number(el, 'margin-bottom'),
            bullet: _number(el, 'bullet').round(),
            textPosAfterBullet: _number(el, 'text-pos-after-bullet'),
            lineHeight: _number(el, 'line-height', fallback: 1),
            highlight: _mxGraphPaintColor(el.getAttribute('highlight')),
          ),
    ].where((run) => run.text.isNotEmpty).toList(growable: false);
    if (raw.isNotEmpty) return _bakeDrawioLabelRuns(raw);
    final str = textForLibvisioWrite(node.getAttribute('str') ?? '');
    if (str.isEmpty) return const <_DrawioStencilLabelRun>[];
    return <_DrawioStencilLabelRun>[
      _DrawioStencilLabelRun(
        text: str,
        fontSize: _fontSize,
        fontStyle: _fontStyle,
        fontFamily: _fontFamily,
        color: _fontColor,
        textOpacity: parentOpacity,
      ),
    ];
  }

  List<_DrawioStencilLabelRun> _bakeDrawioLabelRuns(
    List<_DrawioStencilLabelRun> runs,
  ) {
    var atParagraphStart = true;
    final out = <_DrawioStencilLabelRun>[];
    for (final run in runs) {
      final text = textForLibvisioWrite(
        run.text,
        atParagraphStart: atParagraphStart,
      );
      atParagraphStart = text.endsWith('\n');
      out.add(
        text == run.text
            ? run
            : _DrawioStencilLabelRun(
                text: text,
                fontSize: run.fontSize,
                fontStyle: run.fontStyle,
                fontFamily: run.fontFamily,
                color: run.color,
                textOpacity: run.textOpacity,
                position: run.position,
                align: run.align,
                marginLeft: run.marginLeft,
                marginRight: run.marginRight,
                marginTop: run.marginTop,
                marginBottom: run.marginBottom,
                bullet: run.bullet,
                textPosAfterBullet: run.textPosAfterBullet,
                lineHeight: run.lineHeight,
                highlight: run.highlight,
              ),
      );
    }
    return List<_DrawioStencilLabelRun>.unmodifiable(out);
  }

  /// mxShape.configureCanvas setShadow + mxSvgCanvas2D.createShadow.
  /// dx/dy are mxGraph pixels (Y down). Visio ShapeShdwOffsetY is up;
  /// libvisio `_fillAndShadowProperties` emits ODF offset-y as −Y.
  void _applyMxShadow(XmlElement node) {
    if (node.getAttribute('enabled') == '0') {
      _shadow = null;
      return;
    }
    final dx = _number(node, 'dx', fallback: 2);
    final dy = _number(node, 'dy', fallback: 3);
    final alpha = node.getAttribute('alpha') == null
        ? 1.0
        : _number(node, 'alpha', fallback: 1).clamp(0.0, 1.0).toDouble();
    final color = _mxGraphPaintColor(node.getAttribute('color')) ??
        const VsdxColor(0xFF808080);
    var offsetX = dx * scaleX;
    var offsetY = -dy * scaleY;
    if (offsetX.abs() < 1e-9) offsetX = 0.02;
    if (offsetY.abs() < 1e-9) offsetY = -0.03;
    _shadow = VsdxShadow(
      enabled: true,
      pattern: 1,
      color: color,
      offsetXInches: offsetX,
      offsetYInches: offsetY,
      blurInches: 0,
      transparency: (1 - alpha).clamp(0.0, 1.0),
    );
  }

  double get _strokeWeightInches {
    final width = _strokeWidth;
    if (width == null) return VsdxLine.defaultLine.weightInches;
    // mxStencil.drawShape sets canvas width to attr * minScale before
    // drawNode; `<strokewidth width>` then does width * (fixed=="1" ? 1
    // : minScale) in canvas pixels. leftover inches per canvas pixel
    // is `_canvasScale` (catalog scaleX). Overlay include-shape keeps
    // that root scale while scaleX/scaleY become the nested aspect, so
    // fixed strokes stay hairlines when the include box is larger than
    // nested w0×h0.
    final scale =
        _strokeWidthFixed ? _canvasScale : math.min(scaleX.abs(), scaleY.abs());
    return math.max(0.001, width * scale);
  }

  VsdxLine _paintLine({required bool stroke}) {
    if (!stroke) return const VsdxLine(pattern: 0);
    var line = _strokeColor != null
        ? VsdxLine.defaultLine.withSolidColor(_strokeColor!)
        : VsdxLine.defaultLine;
    if (_strokeWidth != null) {
      line = line.copyWith(weightInches: _strokeWeightInches);
    }
    if (_strokeTransparency > 1e-9) {
      line = line.copyWith(transparency: _strokeTransparency);
    }
    if (_lineCap != null) {
      line = line.copyWith(cap: _lineCap);
    }
    if (_lineJoin != null) {
      line = line.copyWith(join: _lineJoin);
    }
    if (_miterLimit != null) {
      line = line.copyWith(miterLimit: _miterLimit);
    }
    if (_dashed) {
      line = _lineWithDash(line, _dashPattern);
    }
    return line;
  }

  List<double>? _fixedDashPatternValues([List<double>? raw]) {
    // mxAbstractCanvas2D.createState dashPattern is '3 3'. A dashed
    // stroke with no <dashpattern> (AWS 3D Dashed Edge, Cisco Metro
    // 1500) must not fall through to Visio LinePattern 2 (6×/3×
    // LineWeight) — libvisio `_lineProperties` case 2 would paint
    // weight-scaled dashes that look solid on a short rail.
    final source = raw ?? _dashPattern ?? _kMxDefaultDashPattern;
    if (source.isEmpty) return null;
    final scale = math.min(scaleX.abs(), scaleY.abs());
    final values = <double>[
      for (final value in source)
        if (value > 0) value * scale / drawioDashUnitInches,
    ];
    return values.length >= 2 ? values : null;
  }

  VsdxLine _lineWithDash(VsdxLine line, List<double>? pattern) {
    // Explicit `<dashpattern pattern="none"/>` (empty list) is solid.
    // Missing pattern stays mx createState `3 3`.
    if (pattern != null && pattern.isEmpty) {
      return line.copyWith(
        pattern: line.pattern == 0 ? 0 : 1,
        customDashPattern: null,
        fixedDash: false,
      );
    }
    final custom = _fixedDashPatternValues(pattern);
    if (custom != null) {
      return line.copyWith(
        pattern: 1,
        customDashPattern: custom,
        fixedDash: true,
      );
    }
    return line.copyWith(pattern: 2);
  }

  void _finish({required bool fill, required bool stroke}) {
    if (!_dashed) _solidPaintBeforeDash = true;
    var commands = _pending;
    _pending = null;
    if (commands == null || commands.isEmpty) return;
    commands = _closedPolylineFromMoveOnly(commands);
    if (commands.isEmpty) return;
    final doFill = fill && !_fillIsNone;
    final doStroke = stroke && !_strokeIsNone;
    if (!doFill && !doStroke && (fill || stroke)) return;
    // Nested drawShape already painted at nested minScale / fixed
    // canvas pixels. leftover cannot share host collectLine (include
    // box ≠ nested w0×h0), so bake LineWeight now.
    if (_includeDepth > 0 && (doFill || doStroke)) {
      final fill = doFill
          ? (_fillColor != null || _fillOverride != null
              ? _paintFill()
              : VsdxFill(
                  pattern: 1,
                  foreground: _styleFill,
                  foregroundTransparency: _fillTransparency,
                ))
          : const VsdxFill(pattern: 0);
      _coloredParts.add(_DrawioColoredPart(
        commands: List<VsdxPathCommand>.unmodifiable(commands),
        fill: fill,
        line: _paintLine(stroke: doStroke),
        shadow: _shadow ?? VsdxShadow.disabled,
        sketch: _currentSketch,
        // include-shape leftover already `_x`/`_y`'d vertices into the
        // include box. `_fillAndShadowProperties` interpolates
        // FillPattern 25–40 across the child's Width/Height, so a
        // nested fillgradient on a host-sized sibling is a corner of
        // a 1.5" wash. Fit only those gradient paints; solid/stroke
        // leftovers stay in host leftover inches (arc / roundrect tests).
        fitBox: fill.pattern >= 25 && fill.pattern <= 40,
      ));
      if (_shadow != null) _parentShadow ??= _shadow;
      return;
    }
    final bakeFill = doFill && _fillColor != null;
    final bakeStroke = doStroke && _strokeColor != null && !doFill;
    // libvisio collectLine is shape-level. A dash after a solid paint
    // (EIP Detour diagonal) must be a sibling. A shape that is dashed
    // from the first paint (Availability Zone, Dashed Wire) keeps
    // LinePattern on the parent so applyStencilStyle can still recolor it.
    final bakeDash = doStroke && _dashed && _solidPaintBeforeDash;
    // collectGeometry concatenates every NoFill=0 section into one
    // evenodd path (`_fillAndShadowProperties` svg:fill-rule=evenodd).
    // A second inherit-fill (AWS Cloud puffs, Citrix server blobs)
    // would punch overlaps. One compound path + one fill stays on the
    // parent so OpenAI swirl holes still punch.
    // Hex fillcolor siblings paint on top of the parent. AWS4b
    // productIcon fills white (strokeColor) then inherit fillColor
    // for the top square; attaching that square to the parent hid it
    // under the white child in Draw (group children paint after the
    // parent). A later inherit fill after a hex sibling stays a
    // sibling so paint order matches mxSvgCanvas2D.
    final extraInheritFill = doFill &&
        !bakeFill &&
        (_geometries.any((geometry) => !geometry.noFill) ||
            _coloredParts.any((part) => part.fill.hasFill));
    // collectLine is shape-level. A later inherit stroke whose cap /
    // join / miter differs from the first (Electronic Info Flow: save
    // linecap=round stroke, restore, linecap=butt fillstroke) must be a
    // sibling so `_lineProperties` can emit both butt and round.
    final bakeLineStyle = doStroke &&
        _capturedParentLineStyle &&
        (_lineCap != _parentStrokeCap ||
            _lineJoin != _parentStrokeJoin ||
            _miterLimit != _parentMiterLimit);
    // collectLine is shape-level. A later `<strokewidth>` (or include-shape
    // nested setStrokeWidth that stays on the shared canvas) must be a
    // sibling so `_lineProperties` can emit both LineWeights. leftover
    // used to concatenate onto the parent, so Draw stroked the later
    // rail with the first leftover inches (`tokens.txt` LineWeight).
    final bakeWeight = doStroke &&
        _parentStrokeWeightInches != null &&
        (_strokeWeightInches - _parentStrokeWeightInches!).abs() > 1e-6;
    final inheritFillSibling = extraInheritFill ||
        ((bakeLineStyle || bakeWeight) && doFill && !bakeFill);
    if (bakeFill ||
        bakeStroke ||
        bakeDash ||
        extraInheritFill ||
        bakeLineStyle ||
        bakeWeight) {
      final partFill = inheritFillSibling
          ? VsdxFill(
              pattern: 1,
              foreground: _styleFill,
              foregroundTransparency: _fillTransparency,
            )
          : doFill && (bakeFill || bakeDash)
              ? _paintFill()
              : const VsdxFill(pattern: 0);
      _coloredParts.add(_DrawioColoredPart(
        commands: List<VsdxPathCommand>.unmodifiable(commands),
        fill: partFill,
        line: _paintLine(stroke: doStroke),
        shadow: _shadow ?? VsdxShadow.disabled,
        sketch: _currentSketch,
        // Host leftover already `_x`/`_y`'d vertices. libvisio
        // `_fillAndShadowProperties` interpolates FillPattern 25–40
        // across the child's Width/Height. mxSvgCanvas2D
        // `createSvgGradient` omits gradientUnits (SVG default
        // objectBoundingBox), so a radial/rectangular wash fills the
        // current path, not the 1.5" host card. Fit every 25–40
        // leftover; JS SVG userSpaceOnUse offset discs still
        // tessellate at capture (FillPattern 1), not here.
        fitBox: partFill.pattern >= 25 && partFill.pattern <= 40,
      ));
      if (_shadow != null) _parentShadow ??= _shadow;
      return;
    }
    _geometries.add(VsdxGeometry(
      commands: List<VsdxPathCommand>.unmodifiable(commands),
      noFill: !doFill,
      noLine: !doStroke,
      ix: _geometries.length,
    ));
    if (doFill) {
      // restore() pops <alpha> after this fill. Parent FillForegndTrans
      // must be the value collectFillAndShadow saw, not 0.
      _parentFillTransparency ??= _fillTransparency;
    }
    if (doStroke) {
      _parentStrokeTransparency ??= _strokeTransparency;
    }
    if (doStroke && !_capturedParentLineStyle) {
      // First inherit stroke owns collectLine. Later `<linecap>` /
      // `<linejoin>` / `<miterlimit>` belong on hex / extra-inherit
      // siblings (Cisco Detector: inherit fillstroke then cap=butt).
      _capturedParentLineStyle = true;
      _parentStrokeCap = _lineCap;
      _parentStrokeJoin = _lineJoin;
      _parentMiterLimit = _miterLimit;
    }
    if (doStroke && !_capturedParentStrokeColor) {
      // Null means inherit LineColor (defaultEdge #000000). Capture
      // even then so a later hex inner band cannot wash the rail.
      _capturedParentStrokeColor = true;
      _parentStrokeColor = _strokeColor;
    }
    if (doStroke && _dashed) {
      _parentDashed = true;
      _parentDashPattern ??= _dashPattern ?? _kMxDefaultDashPattern;
    }
    if (doStroke && _strokeWidth != null) {
      _parentStrokeWeightInches ??= _strokeWeightInches;
    }
    if (_shadow != null) _parentShadow ??= _shadow;
    if (!_capturedParentSketch) {
      _capturedParentSketch = true;
      _parentSketch = _currentSketch;
    }
  }

  List<VsdxPathCommand> _decodePath(XmlElement path) {
    // mxStencil.drawNode: rounded="1" uses addPoints on move/line
    // subpaths. Any other child (close, curve, …) falls back.
    if (path.getAttribute('rounded') == '1') {
      final rounded = _decodeRoundedPath(path);
      if (rounded != null) return _closedPolylineFromMoveOnly(rounded);
    }
    final commands = <VsdxPathCommand>[];
    for (final command in path.childElements) {
      _decodePathNode(command, commands);
    }
    return _closedPolylineFromMoveOnly(commands);
  }

  /// Official `mxStencil.drawNode` rounded path → `mxShape.addPoints`.
  ///
  /// addPoints runs in canvas pixels: path vertices are already
  /// `x0 + x*sx`, and `arcSize` is the raw XML number (not minScale).
  /// leftover inches per canvas pixel is `_canvasScale` (include-shape
  /// keeps the host). Filleting in stencil space then `_x`/`_y` would
  /// scale the radius by nested sx/sy and stretch collectGeometry
  /// RelQuadBezTo when the include box is anamorphic.
  List<VsdxPathCommand>? _decodeRoundedPath(XmlElement path) {
    final segs = <List<({double x, double y})>>[];
    for (final child in path.childElements) {
      final name = child.name.local;
      if (name == 'move' || name == 'line') {
        if (name == 'move' || segs.isEmpty) {
          segs.add(<({double x, double y})>[]);
        }
        segs.last.add((x: _number(child, 'x'), y: _number(child, 'y')));
      } else {
        return null;
      }
    }
    if (segs.isEmpty) return null;
    var arcSize = _number(path, 'arcSize');
    if (arcSize <= 0) arcSize = _number(path, 'arcsize');
    final leftoverArc = arcSize * _canvasScale.abs();
    final commands = <VsdxPathCommand>[];
    for (final seg in segs) {
      if (seg.isEmpty) continue;
      var pts = List<({double x, double y})>.of(seg);
      var close = false;
      if (pts.length >= 2 &&
          pts.first.x == pts.last.x &&
          pts.first.y == pts.last.y) {
        pts = pts.sublist(0, pts.length - 1);
        close = true;
      }
      if (pts.isEmpty) continue;
      commands.addAll(
        _mxAddPoints(
          pts: [
            for (final point in pts) (x: _x(point.x), y: _y(point.y)),
          ],
          close: close,
          arcSize: leftoverArc,
        ),
      );
      _penX = pts.last.x;
      _penY = pts.last.y;
      _subX = pts.first.x;
      _subY = pts.first.y;
      _hasSub = true;
    }
    if (commands.isEmpty) return null;
    return commands;
  }

  /// Port of `mxShape.addPoints` with `rounded=true`, `initialMove=true`.
  /// [pts] and [arcSize] are leftover inches (canvas pixels × `_canvasScale`).
  List<VsdxPathCommand> _mxAddPoints({
    required List<({double x, double y})> pts,
    required bool close,
    required double arcSize,
  }) {
    if (pts.isEmpty) return const <VsdxPathCommand>[];
    var points = List<({double x, double y})>.of(pts);
    final pe = points.last;
    if (close) {
      final p0 = points.first;
      points.insert(0, (
        x: pe.x + (p0.x - pe.x) / 2,
        y: pe.y + (p0.y - pe.y) / 2,
      ));
    }
    var pt = points.first;
    var i = 1;
    final out = <VsdxPathCommand>[MoveTo(pt.x, pt.y)];
    final pixel = math.max(_canvasScale.abs(), 1e-12);
    while (i < (close ? points.length : points.length - 1)) {
      var tmp = points[_mxMod(i, points.length)];
      final dx0 = pt.x - tmp.x;
      final dy0 = pt.y - tmp.y;
      if (arcSize > 0 && (dx0 != 0 || dy0 != 0)) {
        var dist = math.sqrt(dx0 * dx0 + dy0 * dy0);
        final nx1 = dx0 * math.min(arcSize, dist / 2) / dist;
        final ny1 = dy0 * math.min(arcSize, dist / 2) / dist;
        out.add(LineTo(tmp.x + nx1, tmp.y + ny1));
        var next = points[_mxMod(i + 1, points.length)];
        while (i < points.length - 2 &&
            _mxCanvasRound(next.x - tmp.x) == 0 &&
            _mxCanvasRound(next.y - tmp.y) == 0) {
          next = points[_mxMod(i + 2, points.length)];
          i++;
        }
        final dx = next.x - tmp.x;
        final dy = next.y - tmp.y;
        dist = math.max(pixel, math.sqrt(dx * dx + dy * dy));
        final nx2 = dx * math.min(arcSize, dist / 2) / dist;
        final ny2 = dy * math.min(arcSize, dist / 2) / dist;
        final x2 = tmp.x + nx2;
        final y2 = tmp.y + ny2;
        out.add(QuadBezTo(x: x2, y: y2, x1: tmp.x, y1: tmp.y));
        tmp = (x: x2, y: y2);
      } else {
        out.add(LineTo(tmp.x, tmp.y));
      }
      pt = tmp;
      i++;
    }
    if (close) {
      final start = out.first;
      if (start is MoveTo) {
        out.add(LineTo(start.x, start.y));
      }
    } else {
      out.add(LineTo(pe.x, pe.y));
    }
    return out;
  }

  /// `mxShape.addPoints` skips overlapping vertices with
  /// `Math.round(canvasDx)==0`. leftover inches ÷ `_canvasScale` is that
  /// canvas delta.
  int _mxCanvasRound(double leftoverDelta) {
    final scale = _canvasScale.abs();
    if (scale < 1e-12) return leftoverDelta.round();
    return (leftoverDelta / scale).round();
  }

  void _decodePathNode(XmlElement command, List<VsdxPathCommand> commands) {
    switch (command.name.local) {
      case 'move':
        _penX = _number(command, 'x');
        _penY = _number(command, 'y');
        _subX = _penX;
        _subY = _penY;
        _hasSub = true;
        commands.add(MoveTo(_x(_penX), _y(_penY)));
        break;
      case 'line':
        _penX = _number(command, 'x');
        _penY = _number(command, 'y');
        commands.add(LineTo(_x(_penX), _y(_penY)));
        break;
      case 'curve':
        final x1 = _number(command, 'x1');
        final y1 = _number(command, 'y1');
        final x2 = _number(command, 'x2');
        final y2 = _number(command, 'y2');
        _penX = _number(command, 'x3');
        _penY = _number(command, 'y3');
        commands.add(CubBezTo(
          x: _x(_penX),
          y: _y(_penY),
          x1: _x(x1),
          y1: _y(y1),
          x2: _x(x2),
          y2: _y(y2),
        ));
        break;
      case 'quad':
        final x1 = _number(command, 'x1');
        final y1 = _number(command, 'y1');
        _penX = _number(command, 'x2');
        _penY = _number(command, 'y2');
        commands.add(QuadBezTo(
          x: _x(_penX),
          y: _y(_penY),
          x1: _x(x1),
          y1: _y(y1),
        ));
        break;
      case 'arc':
        final endX = _number(command, 'x');
        final endY = _number(command, 'y');
        // mxStencil.drawNode canvas.arcTo(rx*sx, ry*sy, φ, large, sweep,
        // x0+x*sx, y0+y*sy). leftover used to expand the SVG ellipse in
        // stencil space then `_x`/`_y` the cubics, which shears
        // x-axis-rotation when include-shape sx≠sy. Compute the ellipse
        // in leftover inches (canvas pixels × overlay scale) so
        // collectGeometry RelCubBezTo matches NestedStencil.
        final startLX = _x(_penX);
        final startLY = _y(_penY);
        final endLX = _x(endX);
        final endLY = _y(endY);
        final rxL = _number(command, 'rx').abs() * scaleX.abs();
        final ryL = _number(command, 'ry').abs() * scaleY.abs();
        // Canvas Y-down φ; leftover `_y` is Y-up.
        final rot = -_number(command, 'x-axis-rotation') * math.pi / 180;
        final curves = _svgArcCurves(
          startLX,
          startLY,
          endLX,
          endLY,
          rxL,
          ryL,
          rot,
          _flag(command, 'large-arc-flag'),
          _flag(command, 'sweep-flag'),
        );
        if (curves.isEmpty) {
          commands.add(LineTo(endLX, endLY));
        } else {
          for (final curve in curves) {
            commands.add(CubBezTo(
              x: curve.endX,
              y: curve.endY,
              x1: curve.x1,
              y1: curve.y1,
              x2: curve.x2,
              y2: curve.y2,
            ));
          }
        }
        _penX = endX;
        _penY = endY;
        break;
      case 'close':
        if (_hasSub && (_penX != _subX || _penY != _subY)) {
          commands.add(LineTo(_x(_subX), _y(_subY)));
        }
        _penX = _subX;
        _penY = _subY;
        break;
      case 'ellipse':
        commands.addAll(_decodeEllipse(command));
        break;
      default:
        break;
    }
  }

  List<VsdxPathCommand> _decodeRect(XmlElement rect) {
    final left = _number(rect, 'x');
    final top = _number(rect, 'y');
    final width = _number(rect, 'w');
    final height = _number(rect, 'h');
    // mxGraph emits <rect/> after restore as a 0×0 no-op. A fallback-0
    // rectangle would overwrite the pending contour and evenodd-noise the
    // tile in LibreOffice's concatenated fill path.
    if (width.abs() < 1e-9 && height.abs() < 1e-9) {
      return const <VsdxPathCommand>[];
    }
    final right = left + width;
    final bottom = top + height;
    return <VsdxPathCommand>[
      MoveTo(_x(left), _y(top)),
      LineTo(_x(right), _y(top)),
      LineTo(_x(right), _y(bottom)),
      LineTo(_x(left), _y(bottom)),
      LineTo(_x(left), _y(top)),
    ];
  }

  List<VsdxPathCommand> _decodeRoundRect(XmlElement rect) {
    final left = _number(rect, 'x');
    final top = _number(rect, 'y');
    final width = _number(rect, 'w').abs();
    final height = _number(rect, 'h').abs();
    if (width < 1e-9 && height < 1e-9) {
      return const <VsdxPathCommand>[];
    }
    final right = left + width;
    final bottom = top + height;
    // mxStencil.drawNode: Number(arcsize)==0 uses
    // RECTANGLE_ROUNDING_FACTOR * 100 (15). Omitted also defaults to 15.
    // Canvas roundrect(r=0) is captured as <rect>, not arcsize="0".
    var arcSize = _number(rect, 'arcsize', fallback: 15);
    if (arcSize <= 0) arcSize = 15;
    arcSize = arcSize.clamp(0.0, 100.0);
    // mxStencil.drawNode: r = min(w*factor, h*factor) in canvas pixels
    // (roundrect rx=ry). leftover `_x`/`_y` are independent, and
    // include-shape variable aspect makes scaleX≠scaleY, so a single
    // stencil-space radius would collectGeometry an ellipse. Axis
    // radii map that canvas circle into leftover inches.
    final factor = arcSize / 100;
    final rInches =
        factor * math.min(width * scaleX.abs(), height * scaleY.abs());
    final radiusX = scaleX.abs() < 1e-12 ? 0.0 : rInches / scaleX.abs();
    final radiusY = scaleY.abs() < 1e-12 ? 0.0 : rInches / scaleY.abs();
    const kappa = 0.5522847498307936;
    final kX = radiusX * kappa;
    final kY = radiusY * kappa;
    return <VsdxPathCommand>[
      MoveTo(_x(left + radiusX), _y(top)),
      LineTo(_x(right - radiusX), _y(top)),
      CubBezTo(
        x: _x(right),
        y: _y(top + radiusY),
        x1: _x(right - radiusX + kX),
        y1: _y(top),
        x2: _x(right),
        y2: _y(top + radiusY - kY),
      ),
      LineTo(_x(right), _y(bottom - radiusY)),
      CubBezTo(
        x: _x(right - radiusX),
        y: _y(bottom),
        x1: _x(right),
        y1: _y(bottom - radiusY + kY),
        x2: _x(right - radiusX + kX),
        y2: _y(bottom),
      ),
      LineTo(_x(left + radiusX), _y(bottom)),
      CubBezTo(
        x: _x(left),
        y: _y(bottom - radiusY),
        x1: _x(left + radiusX - kX),
        y1: _y(bottom),
        x2: _x(left),
        y2: _y(bottom - radiusY + kY),
      ),
      LineTo(_x(left), _y(top + radiusY)),
      CubBezTo(
        x: _x(left + radiusX),
        y: _y(top),
        x1: _x(left),
        y1: _y(top + radiusY - kY),
        x2: _x(left + radiusX - kX),
        y2: _y(top),
      ),
    ];
  }

  List<VsdxPathCommand> _decodeEllipse(XmlElement ellipse) {
    final left = _number(ellipse, 'x');
    final top = _number(ellipse, 'y');
    final width = _number(ellipse, 'w');
    final height = _number(ellipse, 'h');
    if (width.abs() < 1e-9 && height.abs() < 1e-9) {
      return const <VsdxPathCommand>[];
    }
    final cxSrc = left + width / 2;
    final cySrc = top + height / 2;
    final cx = _x(cxSrc);
    final cy = _y(cySrc);
    // mxStencil.drawNode canvas.ellipse(w*sx, h*sy). leftover A/B
    // vertices follow independent `_x`/`_y` so collectEllipse rx/ry
    // match the include box. A min(scaleX,scaleY) circle used to hide
    // that stretch (and was a no-op on catalog leftover, where scale
    // is already uniform from the long side).
    return <VsdxPathCommand>[
      EllipseCmd(
        cx: cx,
        cy: cy,
        aX: _x(left + width),
        aY: _y(cySrc),
        bX: _x(cxSrc),
        bY: _y(top),
      ),
    ];
  }

  /// draw.io `feat(shapes): conditional labelBounds for stencils via
  /// boundedLbl`. Sidebar Multi-Document sets `boundedLbl=1`. Catalog
  /// decode has no cell style, so apply the inset: libvisio
  /// collectTextBlock maps TxtWidth / TxtPinY below the stacked sheet.
  VsdxRichText _stencilLabelRichText() {
    final node = element.getElement('labelBounds');
    if (node == null) return VsdxRichText.empty;
    final boxW = _number(node, 'w');
    final boxH = _number(node, 'h');
    if (boxW <= 1e-9 || boxH <= 1e-9) return VsdxRichText.empty;
    final width = boxW * scaleX.abs();
    final height = boxH * scaleY.abs();
    if (width <= 1e-9 || height <= 1e-9) return VsdxRichText.empty;
    return VsdxRichText(
      runs: const <VsdxTextRun>[],
      textBlock: VsdxTextBlock(
        pinXInches: _x(_number(node, 'x') + boxW / 2),
        pinYInches: _y(_number(node, 'y') + boxH / 2),
        locPinXInches: width / 2,
        locPinYInches: height / 2,
        widthInches: width,
        heightInches: height,
        verticalAlign: VsdxVertAlign.middle,
      ),
    );
  }

  List<VsdxConnectionPoint> _connectionPoints() {
    final connections = element.getElement('connections');
    if (connections == null) return const <VsdxConnectionPoint>[];
    return <VsdxConnectionPoint>[
      for (final constraint in connections.findElements('constraint'))
        VsdxConnectionPoint(
          _number(constraint, 'x', fallback: 0.5) * targetWidth,
          (1 - _number(constraint, 'y', fallback: 0.5)) * targetHeight,
          prompt: constraint.getAttribute('name'),
        ),
    ];
  }

  /// ForeignData child whose FlipX is canvas.image flipH, not host
  /// STYLE_FLIPH. Img* fills the child XForm; collectForeignDataType
  /// maps that box to svg:x/width and transformFlips to draw:mirror-*.
  VsdxShape _rasterPictureShape({
    required int id,
    required _DrawioRaster raster,
    required ({
      double offsetX,
      double offsetY,
      double width,
      double height
    }) box,
  }) {
    final width = box.width;
    final height = box.height;
    return VsdxShape(
      id: id,
      name: 'Sheet.$id',
      pinX: box.offsetX + width / 2,
      pinY: box.offsetY + height / 2,
      width: width,
      height: height,
      locPinXInches: width / 2,
      locPinYInches: height / 2,
      flipX: raster.flipH,
      flipY: raster.flipV,
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
      geometries: <VsdxGeometry>[
        VsdxGeometry(
          noFill: true,
          noLine: true,
          commands: <VsdxPathCommand>[
            const MoveTo(0, 0),
            LineTo(width, 0),
            LineTo(width, height),
            LineTo(0, height),
            const LineTo(0, 0),
          ],
        ),
      ],
      imagePartName: raster.part,
      foreignType: VsdxImage.foreignTypeFor(
        mimeType: raster.mime ?? '',
        partName: raster.part,
      ),
      foreignCompressionType: VsdxImage.compressionTypeFor(
        mimeType: raster.mime ?? '',
        partName: raster.part,
      ),
      imgWidthInches: width,
      imgHeightInches: height,
      richText: const VsdxRichText(
        runs: <VsdxTextRun>[],
        textBlock: VsdxTextBlock(hideText: true),
      ),
    );
  }

  VsdxShape _coloredShape({
    required int id,
    required _DrawioColoredPart part,
    VsdxShadow shadow = VsdxShadow.disabled,
  }) {
    var pinX = targetWidth / 2;
    var pinY = targetHeight / 2;
    var width = targetWidth;
    var height = targetHeight;
    var commands = part.commands;
    if (part.fitBox) {
      final box = geometryLocalBounds(
        VsdxGeometry(commands: part.commands),
        width: targetWidth,
        height: targetHeight,
      );
      if (box != null) {
        final boxW = box.maxX - box.minX;
        final boxH = box.maxY - box.minY;
        if (boxW > 1e-4 && boxH > 1e-4) {
          width = boxW;
          height = boxH;
          pinX = box.minX + width / 2;
          pinY = box.minY + height / 2;
          commands = List<VsdxPathCommand>.unmodifiable([
            for (final command in part.commands)
              _translateLeftoverCommand(
                command,
                dx: -box.minX,
                dy: -box.minY,
              ),
          ]);
        }
      }
    }
    return _withSketchUserCells(
      _withLineUserCells(VsdxShape(
        id: id,
        name: 'Sheet.$id',
        pinX: pinX,
        pinY: pinY,
        width: width,
        height: height,
        locPinXInches: width / 2,
        locPinYInches: height / 2,
        fill: part.fill,
        line: part.line,
        shadow: shadow,
        geometries: <VsdxGeometry>[
          VsdxGeometry(
            noFill: !part.fill.hasFill,
            noLine: !part.line.hasLine,
            commands: commands,
          ),
        ],
        richText: const VsdxRichText(
          runs: <VsdxTextRun>[],
          textBlock: VsdxTextBlock(hideText: true),
        ),
      )),
      part.sketch,
    );
  }

  VsdxShape _withLineUserCells(VsdxShape shape) {
    var next = shape;
    final join = shape.line.join;
    if (join != null) next = next.withDrawioLineJoin(join);
    if ((shape.line.miterLimit - 4.0).abs() > 1e-9) {
      next = next.withDrawioMiterLimit(shape.line.miterLimit);
    }
    final custom = shape.line.customDashPattern;
    if (custom != null && custom.isNotEmpty) {
      next = next.withDrawioDashPattern(custom, fixed: shape.line.fixedDash);
    }
    return next;
  }

  /// mxSvgCanvas2D sketch is paint-local. leftover used decoder
  /// `_sketchEnabled` at `build()`, so include-shape nested `<sketch>`
  /// (shared canvas) hatched host fills that already painted.
  /// `User.veSketch*` is not a token; leftover write maps hachure onto
  /// FillPattern 2–24 (`draw:fill=hatch`).
  VsdxShape _withSketchUserCells(VsdxShape shape, _DrawioSketchState sketch) {
    if (!sketch.enabled) return shape;
    var next = shape.withSketchEffect(true);
    if (sketch.fill != null && sketch.fill!.isNotEmpty) {
      next = next.withSketchFillStyle(VsdxSketchFillStyle.parse(sketch.fill));
    }
    if (sketch.gap != null) next = next.withSketchHachureGap(sketch.gap!);
    if (sketch.angle != null) {
      next = next.withSketchHachureAngle(sketch.angle!);
    }
    if (sketch.weight != null && sketch.weight! > 0) {
      next = next.withSketchFillWeight(sketch.weight!);
    }
    if (sketch.jiggle != null) next = next.withSketchJiggle(sketch.jiggle!);
    return next;
  }

  _DrawioSketchState get _currentSketch => _DrawioSketchState(
        enabled: _sketchEnabled,
        fill: _sketchFill,
        gap: _sketchGap,
        angle: _sketchAngle,
        weight: _sketchWeight,
        jiggle: _sketchJiggle,
      );

  VsdxShape _labelShape({
    required int id,
    required _DrawioStencilLabel label,
  }) {
    final scale = math.min(scaleX.abs(), scaleY.abs());
    final fontInches = math.max(_kMxMinCharSizeInches, label.fontSize * scale);
    // mxXmlCanvas2D.text w/h is the cell box. Stencil glyphs pass 0 and
    // keep a tight pin; cell values (Ammeter A, Bootstrap Alert) fill
    // the frame collectTextBlock maps to svg:width / fo:padding-*.
    // mxGraphView.updateVertexLabelOffset shifts that box by one cell
    // for labelPosition / verticalLabelPosition, so Pin can sit outside
    // the parent XForm collectXFormData maps to svg:x / svg:y.
    final hasBox = label.boxWidth > 0 && label.boxHeight > 0;
    final width = hasBox
        ? math.max(label.boxWidth * scaleX.abs(), fontInches * 0.5)
        : math.max(fontInches * 1.2, label.text.length * fontInches * 0.62);
    final height = hasBox
        ? math.max(label.boxHeight * scaleY.abs(), fontInches * 0.5)
        : fontInches * 1.4;
    late final double pinX;
    late final double pinY;
    if (hasBox) {
      pinX = _x(label.x + label.boxWidth / 2);
      pinY = _y(label.y + label.boxHeight / 2);
    } else {
      final x = _x(label.x);
      final y = _y(label.y);
      pinX = switch (label.align) {
        'left' => x + width / 2,
        'right' => x - width / 2,
        _ => x,
      };
      pinY = switch (label.valign) {
        'bottom' => y + height / 2,
        'middle' => y,
        _ => y - height / 2,
      };
    }
    final vert = switch (label.valign) {
      'bottom' => VsdxVertAlign.bottom,
      'middle' => VsdxVertAlign.middle,
      _ => VsdxVertAlign.top,
    };
    var angle = -label.rotationDegrees * math.pi / 180;
    // Cell boxes with STYLE_HORIZONTAL=0 use TextDirection=1 so canvas /
    // SVG rotate and libvisio_write can bake TxtAngle for Draw. Stencil
    // glyphs (w=h=0) keep the mxStencil vertical → TxtAngle shortcut.
    final boxedVertical = hasBox && label.vertical;
    if (label.vertical && !hasBox) angle -= math.pi / 2;
    // mxStencil.drawNode align-shape="0": ignore shape.rotation for
    // canvas.text except the STYLE_FLIPH/V xor (NestedStencil already
    // does). leftover TxtAngle counters collectXFormData Angle; a
    // single FlipX/Y adds that Angle instead of subtracting so Draw
    // librevenge:rotate stays screen-upright after applyXForm FlipX.
    if (!label.alignShape) {
      final dr = _stencilCellRotationRad();
      if (_stencilCellFlipH && _stencilCellFlipV) {
        angle -= dr;
      } else if (_stencilCellFlipH || _stencilCellFlipV) {
        angle += dr;
      } else {
        angle -= dr;
      }
    }
    var shape = VsdxShape(
      id: id,
      name: 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: width,
      height: height,
      locPinXInches: width / 2,
      locPinYInches: height / 2,
      text: label.text,
      richText: VsdxRichText(
        runs: <VsdxTextRun>[
          for (final run in label.runs)
            VsdxTextRun(
              text: run.text,
              charStyle: VsdxCharStyle(
                fontFamily: run.fontFamily ?? label.fontFamily,
                fontSizeInches: math.max(
                  _kMxMinCharSizeInches,
                  run.fontSize * scale,
                ),
                style: VsdxFontStyle(
                  bold: (run.fontStyle & 1) != 0,
                  italic: (run.fontStyle & 2) != 0,
                ),
                underline: (run.fontStyle & 4) != 0,
                strikethrough: (run.fontStyle & 8) != 0,
                color: run.color ?? label.color,
                transparency: ((100 - run.textOpacity) / 100).clamp(0.0, 1.0),
                position: switch (run.position) {
                  1 => VsdxTextPosition.superscript,
                  2 => VsdxTextPosition.subscript,
                  _ => VsdxTextPosition.normal,
                },
                highlight: run.highlight,
              ),
              paraStyle: VsdxParaStyle(
                horizontalAlign: _mxHorzAlign(run.align ?? label.align),
                indentLeftInches: run.marginLeft * scale,
                indentRightInches: run.marginRight * scale,
                spaceBeforeInches: run.marginTop * scale,
                spaceAfterInches: run.marginBottom * scale,
                lineSpacing: run.lineHeight > 0 ? run.lineHeight : 1.0,
                bullet: run.bullet,
                textPosAfterBulletInches: run.textPosAfterBullet * scale,
              ),
            ),
        ],
        textBlock: VsdxTextBlock(
          verticalAlign: vert,
          marginLeftInches: hasBox ? label.spacingLeft * scale : 0,
          marginRightInches: hasBox ? label.spacingRight * scale : 0,
          marginTopInches: hasBox ? label.spacingTop * scale : 0,
          marginBottomInches: hasBox ? label.spacingBottom * scale : 0,
          angleRad: angle,
          backgroundColor: label.background,
          textDirection: boxedVertical ? 1 : 0,
        ),
      ),
      geometries: <VsdxGeometry>[
        VsdxGeometry(
          noFill: true,
          noLine: true,
          commands: <VsdxPathCommand>[
            const MoveTo(0, 0),
            LineTo(width, 0),
            LineTo(width, height),
            LineTo(0, height),
            const LineTo(0, 0),
          ],
        ),
      ],
      fill: const VsdxFill(pattern: 0),
      line: const VsdxLine(pattern: 0),
    );
    // mxText.wrap default is false. veWordWrap is not a token; a save
    // expands TxtWidth so Draw does not wrap. Stencil glyphs stay default.
    if (hasBox && !label.wrap) {
      shape = shape.withWordWrap(false);
    }
    if (label.border != null) {
      shape = shape.withLabelBorderColor(label.border);
    }
    return shape;
  }

  double _x(double source) => _originX + source * scaleX;
  double _y(double source) => _originY + (sourceHeight - source) * scaleY;

  /// Map a nested-stencil-space label into [parent] stencil units so
  /// host `_labelShape` `_x`/`_y` / minScale match NestedStencil
  /// `canvas.text` / `setFontSize(size * minScale)` in the include box.
  _DrawioStencilLabel _labelInParentStencilSpace(
    _DrawioStencilLabel label, {
    required _DrawioXmlShapeDecoder parent,
  }) {
    final leftoverX = _x(label.x);
    final leftoverY = _y(label.y);
    final parentScaleX = parent.scaleX;
    final parentScaleY = parent.scaleY;
    final parentX = parentScaleX.abs() < 1e-12
        ? 0.0
        : (leftoverX - parent._originX) / parentScaleX;
    final parentY = parentScaleY.abs() < 1e-12
        ? 0.0
        : parent.sourceHeight - (leftoverY - parent._originY) / parentScaleY;
    final scaleXRatio =
        parentScaleX.abs() < 1e-12 ? 1.0 : scaleX.abs() / parentScaleX.abs();
    final scaleYRatio =
        parentScaleY.abs() < 1e-12 ? 1.0 : scaleY.abs() / parentScaleY.abs();
    final nestedMin = math.min(scaleX.abs(), scaleY.abs());
    final parentMin = math.min(parentScaleX.abs(), parentScaleY.abs());
    final fontRatio = parentMin < 1e-12 ? 1.0 : nestedMin / parentMin;
    return _DrawioStencilLabel(
      text: label.text,
      x: parentX,
      y: parentY,
      boxWidth: label.boxWidth * scaleXRatio,
      boxHeight: label.boxHeight * scaleYRatio,
      spacingLeft: label.spacingLeft * scaleXRatio,
      spacingRight: label.spacingRight * scaleXRatio,
      spacingTop: label.spacingTop * scaleYRatio,
      spacingBottom: label.spacingBottom * scaleYRatio,
      align: label.align,
      valign: label.valign,
      vertical: label.vertical,
      wrap: label.wrap,
      rotationDegrees: label.rotationDegrees,
      alignShape: label.alignShape,
      fontSize: label.fontSize * fontRatio,
      fontStyle: label.fontStyle,
      fontFamily: label.fontFamily,
      color: label.color,
      background: label.background,
      border: label.border,
      textOpacity: label.textOpacity,
      runs: [
        for (final run in label.runs)
          _DrawioStencilLabelRun(
            text: run.text,
            fontSize: run.fontSize * fontRatio,
            fontStyle: run.fontStyle,
            fontFamily: run.fontFamily,
            color: run.color,
            textOpacity: run.textOpacity,
            position: run.position,
            align: run.align,
            marginLeft: run.marginLeft * fontRatio,
            marginRight: run.marginRight * fontRatio,
            marginTop: run.marginTop * fontRatio,
            marginBottom: run.marginBottom * fontRatio,
            bullet: run.bullet,
            textPosAfterBullet: run.textPosAfterBullet * fontRatio,
            lineHeight: run.lineHeight,
            highlight: run.highlight,
          ),
      ],
    );
  }

  /// Capture `cellrotation` is mxGraph STYLE_ROTATION degrees. Visio
  /// Angle / libvisio collectXFormData is CCW radians (`draw:rotate`).
  double _stencilCellRotationRad() {
    final rotDeg = double.tryParse(element.getAttribute('cellrotation') ?? '');
    if (rotDeg == null || rotDeg.abs() < 1e-9) return 0;
    return -rotDeg * math.pi / 180;
  }

  /// Capture `cellfliph` / `cellflipv` is mxGraph STYLE_FLIPH / STYLE_FLIPV.
  /// Official drawNode align-shape="0" xors those with shape.rotation.
  bool get _stencilCellFlipH =>
      (element.getAttribute('cellfliph') ?? '').trim() == '1';

  bool get _stencilCellFlipV =>
      (element.getAttribute('cellflipv') ?? '').trim() == '1';

  /// mxStencil.computeAspect: STYLE_DIRECTION north/south swaps sx/sy.
  /// leftover XML uses `celldirection` / `direction=` the same way
  /// NestedStencil reads `shape.style.direction`.
  bool get _stencilDirectionInverse {
    final raw = (element.getAttribute('celldirection') ??
            element.getAttribute('direction') ??
            '')
        .trim()
        .toLowerCase();
    return raw == 'north' || raw == 'south';
  }
}

class _DrawioRaster {
  const _DrawioRaster({
    required this.part,
    this.mime,
    this.left,
    this.top,
    this.boxW,
    this.boxH,
    this.flipH = false,
    this.flipV = false,
  });

  final String part;
  final String? mime;
  final double? left;
  final double? top;
  final double? boxW;
  final double? boxH;
  final bool flipH;
  final bool flipV;
}

class _DrawioStencilLabel {
  const _DrawioStencilLabel({
    required this.text,
    required this.x,
    required this.y,
    this.boxWidth = 0,
    this.boxHeight = 0,
    this.spacingLeft = 0,
    this.spacingRight = 0,
    this.spacingTop = 0,
    this.spacingBottom = 0,
    required this.align,
    required this.valign,
    required this.vertical,
    this.wrap = false,
    required this.rotationDegrees,
    this.alignShape = true,
    required this.fontSize,
    required this.fontStyle,
    this.fontFamily,
    this.color,
    this.background,
    this.border,
    this.textOpacity = 100,
    required this.runs,
  });

  final String text;
  final double x;
  final double y;
  final double boxWidth;
  final double boxHeight;
  final double spacingLeft;
  final double spacingRight;
  final double spacingTop;
  final double spacingBottom;
  final String align;
  final String valign;
  final bool vertical;
  final bool wrap;
  final double rotationDegrees;
  final bool alignShape;
  final double fontSize;
  final int fontStyle;
  final String? fontFamily;
  final VsdxColor? color;
  final VsdxColor? background;
  final VsdxColor? border;
  final double textOpacity;
  final List<_DrawioStencilLabelRun> runs;
}

class _DrawioStencilLabelRun {
  const _DrawioStencilLabelRun({
    required this.text,
    required this.fontSize,
    required this.fontStyle,
    this.fontFamily,
    this.color,
    this.textOpacity = 100,
    this.position = 0,
    this.align,
    this.marginLeft = 0,
    this.marginRight = 0,
    this.marginTop = 0,
    this.marginBottom = 0,
    this.bullet = 0,
    this.textPosAfterBullet = 0,
    this.lineHeight = 1,
    this.highlight,
  });

  final String text;
  final double fontSize;
  final int fontStyle;
  final String? fontFamily;
  final VsdxColor? color;
  final double textOpacity;

  /// mxText html `<sup>`/`<sub>` → Char.Pos (1 super / 2 sub).
  final int position;

  /// CSS `text-align` on a block tag, else the mxText STYLE_ALIGN.
  /// collectParaIX HorzAlign maps this to fo:text-align.
  final String? align;

  /// CSS `margin-*` on a block tag, in mxGraph pixels. collectParaIX
  /// IndLeft / IndRight / SpBefore / SpAfter map to fo:margin-*.
  final double marginLeft;
  final double marginRight;
  final double marginTop;
  final double marginBottom;

  /// mxText html `<ul><li>` → Paragraph Bullet. collectParaIX maps 1 to
  /// U+2022 `text:bullet-char`; leftover bakes the glyph because Draw
  /// never paints that character.
  final int bullet;

  /// html.spec UA `padding-inline-start: 40px` on `<ul>`, in mxGraph
  /// pixels. collectParaIX TextPosAfterBullet is the leftover hanging
  /// indent Draw collects as fo:margin-left / fo:text-indent.
  final double textPosAfterBullet;

  /// CSS `line-height` on a block tag as a multiplier. collectParaIX
  /// SpLine < 0 (e.g. 114% → −1.14) maps to fo:line-height PERCENT.
  final double lineHeight;

  /// CSS `background-color` on an inline tag. Char.Highlight is skipped
  /// by libvisio `readCharIX`; leftover still leftover-bakes the hex so
  /// `bakeMixedHighlightForLibvisioWrite` can emit FillForegnd plates.
  final VsdxColor? highlight;
}

class _DrawioSketchState {
  const _DrawioSketchState({
    this.enabled = false,
    this.fill,
    this.gap,
    this.angle,
    this.weight,
    this.jiggle,
  });

  final bool enabled;
  final String? fill;
  final double? gap;
  final double? angle;
  final double? weight;
  final double? jiggle;
}

class _DrawioColoredPart {
  const _DrawioColoredPart({
    required this.commands,
    required this.fill,
    required this.line,
    this.shadow = VsdxShadow.disabled,
    this.sketch = const _DrawioSketchState(),
    this.fitBox = false,
  });

  final List<VsdxPathCommand> commands;
  final VsdxFill fill;
  final VsdxLine line;
  final VsdxShadow shadow;
  final _DrawioSketchState sketch;

  /// When true, [_DrawioXmlShapeDecoder._coloredShape] pins Width/Height
  /// to the path bbox so libvisio FillPattern 25–40 interpolates across
  /// the painted leftover, not the host card.
  final bool fitBox;
}

/// Shift leftover-inch vertices so a fitted child's local origin is the
/// path bbox min. Rel* rows stay as-is (the catalog decoder does not emit
/// them; they would already be fractions of the destination XForm).
VsdxPathCommand _translateLeftoverCommand(
  VsdxPathCommand command, {
  required double dx,
  required double dy,
}) {
  return switch (command) {
    MoveTo(:final x, :final y) => MoveTo(x + dx, y + dy),
    LineTo(:final x, :final y) => LineTo(x + dx, y + dy),
    CubBezTo(:final x, :final y, :final x1, :final y1, :final x2, :final y2) =>
      CubBezTo(
        x: x + dx,
        y: y + dy,
        x1: x1 + dx,
        y1: y1 + dy,
        x2: x2 + dx,
        y2: y2 + dy,
      ),
    QuadBezTo(:final x, :final y, :final x1, :final y1) => QuadBezTo(
        x: x + dx,
        y: y + dy,
        x1: x1 + dx,
        y1: y1 + dy,
      ),
    ArcTo(:final x, :final y, :final bow) =>
      ArcTo(x: x + dx, y: y + dy, bow: bow),
    EllipticalArcTo(
      :final x,
      :final y,
      :final controlX,
      :final controlY,
      :final angle,
      :final eccentricity,
    ) =>
      EllipticalArcTo(
        x: x + dx,
        y: y + dy,
        controlX: controlX + dx,
        controlY: controlY + dy,
        angle: angle,
        eccentricity: eccentricity,
      ),
    EllipseCmd(
      :final cx,
      :final cy,
      :final aX,
      :final aY,
      :final bX,
      :final bY,
    ) =>
      EllipseCmd(
        cx: cx + dx,
        cy: cy + dy,
        aX: aX + dx,
        aY: aY + dy,
        bX: bX + dx,
        bY: bY + dy,
      ),
    _ => command,
  };
}

/// mxStencil.parseColor hex / rgb / CSS named colour. Official
/// `mxUtils.isValidColor` / `color2hex` resolve names through canvas
/// `fillStyle`. Style keys such as `fillColor2` return null so callers
/// can apply the node's `default`. `transparent` is handled as none
/// by `_applyMxFill` / `_applyMxStroke`.
VsdxColor? _mxGraphPaintColor(String? raw) {
  if (raw == null) return null;
  final token = raw.trim();
  if (token.isEmpty) return null;
  // CSS / mxGraph `#RGB` / `#RRGGBB` / `#RRGGBBAA`, including a hex
  // prefix glued to the next style key. GMDL stepper addDataEntry
  // writes `fontColor=#4d4d4dlfontSize=13` (missing `;`); canvas
  // fillStyle rejects it and collectCharIX would inherit black.
  if (token.startsWith('#')) {
    final match = RegExp(
      r'^#([0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3})',
    ).matchAsPrefix(token);
    if (match != null) {
      var hex = match.group(1)!;
      if (hex.length == 3) {
        hex = '${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}';
      }
      return VsdxColor.tryParse('#$hex');
    }
  }
  if (!token.startsWith('#') && RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(token)) {
    return VsdxColor.tryParse('#$token');
  }
  final named = _mxCssNamedColors[token.toLowerCase()];
  if (named != null) return VsdxColor(named);
  return VsdxColor.tryParse(token);
}

/// CSS Color Module Level 4 named colours (opaque). `grey` aliases
/// match canvas `fillStyle`. Used so SVG `fill="gray"` / `silver` /
/// fillgradient `color1=white` become sibling FillForegnd that
/// `collectFillAndShadow` maps to `draw:fill-color`.
const Map<String, int> _mxCssNamedColors = <String, int>{
  'aliceblue': 0xFFF0F8FF,
  'antiquewhite': 0xFFFAEBD7,
  'aqua': 0xFF00FFFF,
  'aquamarine': 0xFF7FFFD4,
  'azure': 0xFFF0FFFF,
  'beige': 0xFFF5F5DC,
  'bisque': 0xFFFFE4C4,
  'black': 0xFF000000,
  'blanchedalmond': 0xFFFFEBCD,
  'blue': 0xFF0000FF,
  'blueviolet': 0xFF8A2BE2,
  'brown': 0xFFA52A2A,
  'burlywood': 0xFFDEB887,
  'cadetblue': 0xFF5F9EA0,
  'chartreuse': 0xFF7FFF00,
  'chocolate': 0xFFD2691E,
  'coral': 0xFFFF7F50,
  'cornflowerblue': 0xFF6495ED,
  'cornsilk': 0xFFFFF8DC,
  'crimson': 0xFFDC143C,
  'cyan': 0xFF00FFFF,
  'darkblue': 0xFF00008B,
  'darkcyan': 0xFF008B8B,
  'darkgoldenrod': 0xFFB8860B,
  'darkgray': 0xFFA9A9A9,
  'darkgreen': 0xFF006400,
  'darkgrey': 0xFFA9A9A9,
  'darkkhaki': 0xFFBDB76B,
  'darkmagenta': 0xFF8B008B,
  'darkolivegreen': 0xFF556B2F,
  'darkorange': 0xFFFF8C00,
  'darkorchid': 0xFF9932CC,
  'darkred': 0xFF8B0000,
  'darksalmon': 0xFFE9967A,
  'darkseagreen': 0xFF8FBC8F,
  'darkslateblue': 0xFF483D8B,
  'darkslategray': 0xFF2F4F4F,
  'darkslategrey': 0xFF2F4F4F,
  'darkturquoise': 0xFF00CED1,
  'darkviolet': 0xFF9400D3,
  'deeppink': 0xFFFF1493,
  'deepskyblue': 0xFF00BFFF,
  'dimgray': 0xFF696969,
  'dimgrey': 0xFF696969,
  'dodgerblue': 0xFF1E90FF,
  'firebrick': 0xFFB22222,
  'floralwhite': 0xFFFFFAF0,
  'forestgreen': 0xFF228B22,
  'fuchsia': 0xFFFF00FF,
  'gainsboro': 0xFFDCDCDC,
  'ghostwhite': 0xFFF8F8FF,
  'gold': 0xFFFFD700,
  'goldenrod': 0xFFDAA520,
  'gray': 0xFF808080,
  'green': 0xFF008000,
  'greenyellow': 0xFFADFF2F,
  'grey': 0xFF808080,
  'honeydew': 0xFFF0FFF0,
  'hotpink': 0xFFFF69B4,
  'indianred': 0xFFCD5C5C,
  'indigo': 0xFF4B0082,
  'ivory': 0xFFFFFFF0,
  'khaki': 0xFFF0E68C,
  'lavender': 0xFFE6E6FA,
  'lavenderblush': 0xFFFFF0F5,
  'lawngreen': 0xFF7CFC00,
  'lemonchiffon': 0xFFFFFACD,
  'lightblue': 0xFFADD8E6,
  'lightcoral': 0xFFF08080,
  'lightcyan': 0xFFE0FFFF,
  'lightgoldenrodyellow': 0xFFFAFAD2,
  'lightgray': 0xFFD3D3D3,
  'lightgreen': 0xFF90EE90,
  'lightgrey': 0xFFD3D3D3,
  'lightpink': 0xFFFFB6C1,
  'lightsalmon': 0xFFFFA07A,
  'lightseagreen': 0xFF20B2AA,
  'lightskyblue': 0xFF87CEFA,
  'lightslategray': 0xFF778899,
  'lightslategrey': 0xFF778899,
  'lightsteelblue': 0xFFB0C4DE,
  'lightyellow': 0xFFFFFFE0,
  'lime': 0xFF00FF00,
  'limegreen': 0xFF32CD32,
  'linen': 0xFFFAF0E6,
  'magenta': 0xFFFF00FF,
  'maroon': 0xFF800000,
  'mediumaquamarine': 0xFF66CDAA,
  'mediumblue': 0xFF0000CD,
  'mediumorchid': 0xFFBA55D3,
  'mediumpurple': 0xFF9370DB,
  'mediumseagreen': 0xFF3CB371,
  'mediumslateblue': 0xFF7B68EE,
  'mediumspringgreen': 0xFF00FA9A,
  'mediumturquoise': 0xFF48D1CC,
  'mediumvioletred': 0xFFC71585,
  'midnightblue': 0xFF191970,
  'mintcream': 0xFFF5FFFA,
  'mistyrose': 0xFFFFE4E1,
  'moccasin': 0xFFFFE4B5,
  'navajowhite': 0xFFFFDEAD,
  'navy': 0xFF000080,
  'oldlace': 0xFFFDF5E6,
  'olive': 0xFF808000,
  'olivedrab': 0xFF6B8E23,
  'orange': 0xFFFFA500,
  'orangered': 0xFFFF4500,
  'orchid': 0xFFDA70D6,
  'palegoldenrod': 0xFFEEE8AA,
  'palegreen': 0xFF98FB98,
  'paleturquoise': 0xFFAFEEEE,
  'palevioletred': 0xFFDB7093,
  'papayawhip': 0xFFFFEFD5,
  'peachpuff': 0xFFFFDAB9,
  'peru': 0xFFCD853F,
  'pink': 0xFFFFC0CB,
  'plum': 0xFFDDA0DD,
  'powderblue': 0xFFB0E0E6,
  'purple': 0xFF800080,
  'rebeccapurple': 0xFF663399,
  'red': 0xFFFF0000,
  'rosybrown': 0xFFBC8F8F,
  'royalblue': 0xFF4169E1,
  'saddlebrown': 0xFF8B4513,
  'salmon': 0xFFFA8072,
  'sandybrown': 0xFFF4A460,
  'seagreen': 0xFF2E8B57,
  'seashell': 0xFFFFF5EE,
  'sienna': 0xFFA0522D,
  'silver': 0xFFC0C0C0,
  'skyblue': 0xFF87CEEB,
  'slateblue': 0xFF6A5ACD,
  'slategray': 0xFF708090,
  'slategrey': 0xFF708090,
  'snow': 0xFFFFFAFA,
  'springgreen': 0xFF00FF7F,
  'steelblue': 0xFF4682B4,
  'tan': 0xFFD2B48C,
  'teal': 0xFF008080,
  'thistle': 0xFFD8BFD8,
  'tomato': 0xFFFF6347,
  'turquoise': 0xFF40E0D0,
  'violet': 0xFFEE82EE,
  'wheat': 0xFFF5DEB3,
  'white': 0xFFFFFFFF,
  'whitesmoke': 0xFFF5F5F5,
  'yellow': 0xFFFFFF00,
  'yellowgreen': 0xFF9ACD32,
};

/// Vertex style keys that exist on every cell. Catalog decode has no
/// style, so these stay inherit and `applyStencilStyle` recolors them.
bool _mxIsCellStyleColorKey(String token) =>
    token == 'fillColor' ||
    token == 'strokeColor' ||
    token == 'fontColor' ||
    token == 'gradientColor' ||
    token == 'labelBackgroundColor' ||
    token == 'labelBorderColor';

/// mxStencil.getColorValue node `default` values keyed by custom style
/// name (`neutralFill`, `fillColor2`). Cell keys stay inherit.
Map<String, VsdxColor> _mxStencilStyleKeyDefaults(XmlElement root) {
  final defaults = <String, VsdxColor>{};
  for (final node in root.descendants.whereType<XmlElement>()) {
    final name = node.name.local;
    if (name != 'fillcolor' &&
        name != 'strokecolor' &&
        name != 'fontcolor' &&
        name != 'fontbackgroundcolor') {
      continue;
    }
    final key = (node.getAttribute('color') ?? '').trim();
    if (key.isEmpty || _mxIsCellStyleColorKey(key)) continue;
    final color = _mxGraphPaintColor(node.getAttribute('default'));
    if (color == null) continue;
    defaults.putIfAbsent(key, () => color);
  }
  return defaults;
}

/// Library-wide unique `default` for a custom style key. Mixed hexes
/// (Cisco `fillColor2`) stay inherit so we do not pick a sibling's LED.
Map<String, VsdxColor> _mxUniqueStencilStyleKeyDefaults(
  Iterable<XmlElement> shapes,
) {
  final hexes = <String, Set<int>>{};
  for (final shape in shapes) {
    for (final entry in _mxStencilStyleKeyDefaults(shape).entries) {
      hexes.putIfAbsent(entry.key, () => {}).add(entry.value.value);
    }
  }
  return {
    for (final entry in hexes.entries)
      if (entry.value.length == 1) entry.key: VsdxColor(entry.value.single),
  };
}

/// mxText CSS `text-align` / STYLE_ALIGN → collectParaIX HorzAlign
/// (`fo:text-align`).
VsdxHorzAlign _mxHorzAlign(String? raw) => switch ((raw ?? '').toLowerCase()) {
      'center' => VsdxHorzAlign.center,
      'right' => VsdxHorzAlign.right,
      'justify' => VsdxHorzAlign.justify,
      _ => VsdxHorzAlign.left,
    };

/// mxStencil.drawNode fontfamily: strip CSS quotes, first family, map
/// generic CSS faces onto Visio/libvisio names collectCharIX emits as
/// style:font-name.
String? _mxFontFamily(String? raw) {
  var token = (raw ?? '').trim();
  if (token.isEmpty) return null;
  token = token.split(',').first.trim();
  if (token.length >= 2 &&
      ((token.startsWith("'") && token.endsWith("'")) ||
          (token.startsWith('"') && token.endsWith('"')))) {
    token = token.substring(1, token.length - 1).trim();
  }
  if (token.isEmpty) return null;
  return switch (token.toLowerCase()) {
    'sans-serif' || 'arial' => 'Arial',
    'serif' || 'times' || 'times new roman' => 'Times New Roman',
    'monospace' || 'courier' || 'courier new' => 'Courier New',
    'helvetica' => 'Helvetica',
    _ => token,
  };
}

/// mxStencil.drawNode dashpattern.
///
/// Official splits on spaces and `Number(part)*minScale`. `none` becomes
/// `NaN`; [mxSvgCanvas2D.createDashPattern] then sets `stroke-dasharray`
/// to that, which SVG paints solid. Return an empty list so [_lineWithDash]
/// does not substitute createState `3 3`. A missing tag leaves `null`.
/// Cisco Security Guard / ISDN Switch emit `dash=` instead of `pattern=`.
List<double>? _parseMxDashPattern(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return null;
  if (text.toLowerCase() == 'none') return const <double>[];
  final values = <double>[];
  for (final part in text.split(RegExp(r'[\s,]+'))) {
    if (part.isEmpty) continue;
    final value = double.tryParse(part);
    if (value == null || !value.isFinite || value <= 0) continue;
    values.add(value);
  }
  return values.length >= 2 ? values : null;
}

int _mxFillPatternForDirection(String dir) => switch (dir) {
      'north' => 30,
      'northeast' => 34,
      'east' => 27,
      'southeast' => 32,
      'south' => 28,
      'southwest' => 31,
      'west' => 25,
      'northwest' => 33,
      'radial' => 40,
      _ => 28,
    };

double _mxFillGradientAngleRad(String dir) => switch (dir) {
      'east' => 0,
      'northeast' => math.pi / 4,
      'north' => math.pi / 2,
      'northwest' => 3 * math.pi / 4,
      'west' => math.pi,
      'southwest' => -3 * math.pi / 4,
      'south' => -math.pi / 2,
      'southeast' => -math.pi / 4,
      _ => -math.pi / 2,
    };

/// `stops="#f2580a@0,#fea15f@0.413,#a11a00@1"` (optional `/alpha`).
List<VsdxGradientStop> _parseMxGradientStops(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return const <VsdxGradientStop>[];
  final out = <VsdxGradientStop>[];
  for (final part in text.split(',')) {
    final token = part.trim();
    if (token.isEmpty) continue;
    final slash = token.lastIndexOf('/');
    var colorPos = token;
    var alpha = 1.0;
    if (slash > 0) {
      final parsedAlpha = double.tryParse(token.substring(slash + 1));
      if (parsedAlpha != null && parsedAlpha.isFinite) {
        alpha = parsedAlpha.clamp(0.0, 1.0);
        colorPos = token.substring(0, slash);
      }
    }
    final at = colorPos.lastIndexOf('@');
    if (at <= 0) continue;
    final color = _mxGraphPaintColor(colorPos.substring(0, at));
    final pos = double.tryParse(colorPos.substring(at + 1));
    if (color == null || pos == null || !pos.isFinite) continue;
    out.add(
      VsdxGradientStop(
        position: pos.clamp(0.0, 1.0),
        color: color,
        transparency: (1 - alpha).clamp(0.0, 1.0),
      ),
    );
  }
  out.sort((a, b) => a.position.compareTo(b.position));
  return out;
}

/// mxStencil.parseDescription: `strokewidth` is inherit or a number
/// (default `"1"` when the attribute is omitted). drawShape uses
/// `Number(strokewidth) * minScale` when it is not inherit. Catalog
/// decode has no cell style, so inherit stays unset and
/// applyStencilStyle can still pin LineWeight (Cisco Detector).
/// Omitted (Cisco Keys, mockup Radio Button Off) must freeze 1×minScale so
/// collectLine does not keep the Visio 0.01 in hairline.
double? _mxShapeAttrStrokeWidth(XmlElement element) {
  final raw = (element.getAttribute('strokewidth') ?? '').trim();
  if (raw.toLowerCase() == 'inherit') return null;
  if (raw.isEmpty) return 1;
  final value = double.tryParse(raw);
  if (value == null || !value.isFinite || value <= 0) return null;
  return value;
}

/// Visio LineCap: 0 round, 1 extended/butt, 2 square. libvisio
/// `_lineProperties` maps those onto svg:stroke-linecap.
LineCap? _mxLineCap(String? raw) => switch ((raw ?? '').trim().toLowerCase()) {
      'round' => LineCap.round,
      'square' => LineCap.square,
      'butt' || 'flat' => LineCap.extended,
      _ => null,
    };

/// mxStencil.drawNode setLineJoin. Empty is a no-op like
/// mxAbstractCanvas2D (`if (value != null)`). Invalid SVG joins
/// (`flat` / `square` / `butt`) snap to the CSS initial `miter`.
VsdxLineJoin? _mxLineJoin(String? raw) =>
    switch ((raw ?? '').trim().toLowerCase()) {
      '' => null,
      'round' => VsdxLineJoin.round,
      'bevel' => VsdxLineJoin.bevel,
      'arcs' => VsdxLineJoin.arcs,
      'miter-clip' || 'miterclip' => VsdxLineJoin.miterClip,
      _ => VsdxLineJoin.miter,
    };

class _DrawioArcCurve {
  const _DrawioArcCurve({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.endX,
    required this.endY,
  });

  final double x1, y1, x2, y2, endX, endY;
}

List<_DrawioArcCurve> _svgArcCurves(
  double startX,
  double startY,
  double endX,
  double endY,
  double rx,
  double ry,
  double rotation,
  bool largeArc,
  bool sweep,
) {
  if (rx <= 1e-12 || ry <= 1e-12 || (startX == endX && startY == endY)) {
    return const <_DrawioArcCurve>[];
  }
  final cosPhi = math.cos(rotation);
  final sinPhi = math.sin(rotation);
  final dx = (startX - endX) / 2;
  final dy = (startY - endY) / 2;
  final xPrime = cosPhi * dx + sinPhi * dy;
  final yPrime = -sinPhi * dx + cosPhi * dy;
  var safeRx = rx.abs();
  var safeRy = ry.abs();
  final lambda =
      xPrime * xPrime / (safeRx * safeRx) + yPrime * yPrime / (safeRy * safeRy);
  if (lambda > 1) {
    final scale = math.sqrt(lambda);
    safeRx *= scale;
    safeRy *= scale;
  }
  final rx2 = safeRx * safeRx;
  final ry2 = safeRy * safeRy;
  final numerator = math.max(
    0.0,
    rx2 * ry2 - rx2 * yPrime * yPrime - ry2 * xPrime * xPrime,
  );
  final denominator = rx2 * yPrime * yPrime + ry2 * xPrime * xPrime;
  final sign = largeArc == sweep ? -1.0 : 1.0;
  final coefficient =
      denominator <= 1e-20 ? 0.0 : sign * math.sqrt(numerator / denominator);
  final centerPrimeX = coefficient * safeRx * yPrime / safeRy;
  final centerPrimeY = -coefficient * safeRy * xPrime / safeRx;
  final centerX =
      cosPhi * centerPrimeX - sinPhi * centerPrimeY + (startX + endX) / 2;
  final centerY =
      sinPhi * centerPrimeX + cosPhi * centerPrimeY + (startY + endY) / 2;

  double angle(double ux, double uy, double vx, double vy) =>
      math.atan2(ux * vy - uy * vx, ux * vx + uy * vy);

  final ux = (xPrime - centerPrimeX) / safeRx;
  final uy = (yPrime - centerPrimeY) / safeRy;
  final vx = (-xPrime - centerPrimeX) / safeRx;
  final vy = (-yPrime - centerPrimeY) / safeRy;
  var startAngle = angle(1, 0, ux, uy);
  var delta = angle(ux, uy, vx, vy);
  if (!sweep && delta > 0) delta -= 2 * math.pi;
  if (sweep && delta < 0) delta += 2 * math.pi;
  final segments = math.max(1, (delta.abs() / (math.pi / 2)).ceil());
  final step = delta / segments;
  final curves = <_DrawioArcCurve>[];

  ({double x, double y, double dx, double dy}) sample(double theta) {
    final cosTheta = math.cos(theta);
    final sinTheta = math.sin(theta);
    return (
      x: centerX + cosPhi * safeRx * cosTheta - sinPhi * safeRy * sinTheta,
      y: centerY + sinPhi * safeRx * cosTheta + cosPhi * safeRy * sinTheta,
      dx: -cosPhi * safeRx * sinTheta - sinPhi * safeRy * cosTheta,
      dy: -sinPhi * safeRx * sinTheta + cosPhi * safeRy * cosTheta,
    );
  }

  for (var index = 0; index < segments; index++) {
    final endAngle = startAngle + step;
    final from = sample(startAngle);
    final to = sample(endAngle);
    final alpha = 4 / 3 * math.tan(step / 4);
    curves.add(_DrawioArcCurve(
      x1: from.x + alpha * from.dx,
      y1: from.y + alpha * from.dy,
      x2: to.x - alpha * to.dx,
      y2: to.y - alpha * to.dy,
      endX: index == segments - 1 ? endX : to.x,
      endY: index == segments - 1 ? endY : to.y,
    ));
    startAngle = endAngle;
  }
  return curves;
}

int _mxMod(int n, int m) {
  if (m == 0) return 0;
  return ((n % m) + m) % m;
}

double _number(XmlElement element, String name, {double fallback = 0}) {
  final value = double.tryParse(element.getAttribute(name) ?? '');
  return value?.isFinite == true ? value! : fallback;
}

/// mxGraph `rect()` + stroke is four corners. Some JS captures (mockup
/// Table cells, C4 Legend) emit those as consecutive `<move>` without
/// `<line>`. libvisio `collectGeometry` skips a MoveTo-only section, so
/// Draw would miss the grid. Close the polyline like a regular rect.
List<VsdxPathCommand> _closedPolylineFromMoveOnly(
  List<VsdxPathCommand> commands,
) {
  if (commands.length < 3) return commands;
  if (commands.any((command) => command is! MoveTo)) return commands;
  final points = <MoveTo>[
    for (final command in commands) command as MoveTo,
  ];
  final out = <VsdxPathCommand>[MoveTo(points.first.x, points.first.y)];
  for (var i = 1; i < points.length; i++) {
    out.add(LineTo(points[i].x, points[i].y));
  }
  final first = points.first;
  final last = points.last;
  if ((first.x - last.x).abs() > 1e-9 || (first.y - last.y).abs() > 1e-9) {
    out.add(LineTo(first.x, first.y));
  }
  return out;
}

({Uint8List bytes, String mime})? _dataUriImage(String src) {
  final match = RegExp(
    r'^data:(image/[\w.+-]+)(;base64)?,([\s\S]+)$',
    caseSensitive: false,
  ).firstMatch(src.trim());
  if (match == null) return null;
  var mime = match.group(1)!.toLowerCase();
  if (mime == 'image/jpg') mime = 'image/jpeg';
  final payload = match.group(3)!.replaceAll(RegExp(r'\s+'), '');
  try {
    final bytes = Uint8List.fromList(base64Decode(payload));
    if (bytes.isEmpty) return null;
    return (bytes: bytes, mime: mime);
  } catch (_) {
    return null;
  }
}

bool _flag(XmlElement element, String name) =>
    element.getAttribute(name) == '1' ||
    element.getAttribute(name)?.toLowerCase() == 'true';
