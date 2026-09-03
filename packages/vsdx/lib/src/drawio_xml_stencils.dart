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

/// html.spec UA `padding-inline-start` on `<ul>` / `<ol>`, mxGraph px.
const double _kMxHtmlListPadPx = 40;

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

/// mxConstants.SHADOWCOLOR / SHADOW_OPACITY / SHADOW_OFFSET_*.
const VsdxColor _kMxDefaultShadowColor = VsdxColor(0xFF808080);
const double _kMxDefaultShadowAlpha = 1;
const double _kMxDefaultShadowDx = 2;
const double _kMxDefaultShadowDy = 3;

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
    required this.fillFollowsStroke,
    required this.strokeFollowsFill,
    required this.fontFollowsStroke,
    required this.fontFollowsFill,
    required this.fontBgFollowsStroke,
    required this.fontBgFollowsFill,
    required this.fontBorderFollowsStroke,
    required this.fontBorderFollowsFill,
    required this.overallAlpha,
    required this.fillAlpha,
    required this.strokeAlpha,
    required this.strokeWidth,
    required this.strokeWidthFixed,
    required this.dashed,
    required this.fixDash,
    required this.dashPattern,
    required this.lineCap,
    required this.lineJoin,
    required this.miterLimit,
    required this.shadow,
    required this.shadowColor,
    required this.shadowAlpha,
    required this.shadowDx,
    required this.shadowDy,
    required this.sketchEnabled,
    required this.sketchFill,
    required this.sketchGap,
    required this.sketchAngle,
    required this.sketchWeight,
    required this.sketchJiggle,
    required this.canvasDx,
    required this.canvasDy,
    required this.canvasUserScale,
    required this.rotThetaDeg,
    required this.rotFlipH,
    required this.rotFlipV,
    required this.rotCxLeftover,
    required this.rotCyLeftover,
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
  final bool fillFollowsStroke;
  final bool strokeFollowsFill;
  final bool fontFollowsStroke;
  final bool fontFollowsFill;
  final bool fontBgFollowsStroke;
  final bool fontBgFollowsFill;
  final bool fontBorderFollowsStroke;
  final bool fontBorderFollowsFill;
  final double overallAlpha;
  final double fillAlpha;
  final double strokeAlpha;
  final double? strokeWidth;
  final bool strokeWidthFixed;
  final bool dashed;
  final bool fixDash;
  final List<double>? dashPattern;
  final LineCap? lineCap;
  final VsdxLineJoin? lineJoin;
  final double? miterLimit;
  final VsdxShadow? shadow;
  final VsdxColor shadowColor;
  final double shadowAlpha;
  final double shadowDx;
  final double shadowDy;
  final bool sketchEnabled;
  final String? sketchFill;
  final double? sketchGap;
  final double? sketchAngle;
  final double? sketchWeight;
  final double? sketchJiggle;
  // mxAbstractCanvas2D.createState dx/dy/scale. leftover bakes
  // addOp `(x + dx) * scale` into leftover inches because
  // collectGeometry has no canvas transform (tokens.txt PinX /
  // Width / Angle are shape-level).
  final double canvasDx;
  final double canvasDy;
  final double canvasUserScale;
  // mxXmlCanvas2D.rotate leftover inches. collectXFormData Angle is
  // shape-level, so leftover bakes mxSvgCanvas2D's SVG transform into
  // vertices (`tokens.txt` PinX / Angle).
  final double rotThetaDeg;
  final bool rotFlipH;
  final bool rotFlipV;
  final double rotCxLeftover;
  final double rotCyLeftover;
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
  // mxAbstractCanvas2D.createState: dx/dy 0, scale 1.
  // mxXmlCanvas2D `<translate>` / `<scale>` update these; leftover
  // `_x`/`_y` bake `(source + dx) * scale` so Draw collectGeometry
  // paints the transformed vertices (`tokens.txt` has no canvas).
  double _canvasDx = 0;
  double _canvasDy = 0;
  double _canvasUserScale = 1;
  // mxXmlCanvas2D `<rotate>` / mxSvgCanvas2D.rotate. leftover bakes the
  // SVG transform into leftover inches; Angle on the parent would spin
  // earlier unrotated Geometry too (`tokens.txt` Angle is shape-level).
  double _rotThetaDeg = 0;
  bool _rotFlipH = false;
  bool _rotFlipV = false;
  double _rotCxLeftover = 0;
  double _rotCyLeftover = 0;

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
  bool _fillFollowsStroke = false;
  bool _strokeFollowsFill = false;
  bool _fontFollowsStroke = false;
  bool _fontFollowsFill = false;
  bool _fontBgFollowsStroke = false;
  bool _fontBgFollowsFill = false;
  bool _fontBorderFollowsStroke = false;
  bool _fontBorderFollowsFill = false;
  bool _capturedParentFill = false;
  bool _parentFillFollowsStroke = false;
  bool _parentStrokeFollowsFill = false;
  double _overallAlpha = 1;
  double _fillAlpha = 1;
  double _strokeAlpha = 1;
  double? _strokeWidth;
  bool _strokeWidthFixed = false;
  double? _parentStrokeWeightInches;
  bool _capturedParentUserScale = false;
  double? _parentCanvasUserScale;
  bool _capturedParentStrokeColor = false;
  VsdxColor? _parentStrokeColor;
  double? _parentFillTransparency;
  double? _parentStrokeTransparency;
  bool _dashed = false;
  // mxAbstractCanvas2D.createState fixDash is false (dash × strokeWidth).
  // mxStencil.drawNode calls setDashed(dashed=='1') with no second
  // arg, so omitted `<dashed>` fixDash is relative. leftover used to
  // keep true (JS capture never emits the attr), so later
  // `<dashed dashed="1"/>` reused the first canvas-pixel MoveTo gaps
  // (`tokens.txt` has no fixDash).
  bool _fixDash = false;
  bool _solidPaintBeforeDash = false;
  bool _capturedParentDashState = false;
  bool _parentDashed = false;
  bool _parentFixDash = false;
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
  VsdxColor _shadowColor = _kMxDefaultShadowColor;
  double _shadowAlpha = _kMxDefaultShadowAlpha;
  double _shadowDx = _kMxDefaultShadowDx;
  double _shadowDy = _kMxDefaultShadowDy;
  VsdxShadow? _parentShadow;
  bool _capturedParentShadow = false;
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
    // One unflipped, unrotated bitmap stays on the host (IBM Floating
    // IP Img*). flipH/flipV, canvas.rotate Angle, a canvas xor Flip,
    // and a second canvas.image become ForeignData children: leftover
    // FlipX / Angle on the host would applyXForm-mirror Geometry, and
    // a single slot dropped earlier PNGs (`tokens.txt` FlipX / Angle /
    // ImgWidth). collectForeignDataType transformAngle uses the shape
    // Angle, not a separate image cell.
    final hostRasterEntry =
        (_rasters.length == 1 && _rasterStaysOnHost(_rasters.first))
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
    // NoFill=1 rails (fillcolor=none / omitted setFillColor(null))
    // must not inherit FillForegnd on the host. leftover used to keep
    // defaultFill when children were empty, so Draw painted palette
    // fill (`tokens.txt` FillForegnd → svg:fill).
    final parentFillTrans = _parentFillTransparency ?? 0.0;
    final parentFill = pictureFrameOnly || !inheritFill
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
    // NoLine=1 rails (strokecolor=none / omitted setStrokeColor(null))
    // must not inherit LineColor on the host. leftover used to keep
    // `_paintLine` when children were empty, so Draw painted palette
    // stroke (`tokens.txt` LineColor → svg:stroke).
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
    var parentLine = pictureFrameOnly || !inheritLine
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
      parentLine = _lineWithDash(
        parentLine,
        _parentDashPattern,
        fixDash: _parentFixDash,
      );
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
        _parentStrokeTransparency != null) {
      // restore() pops <alpha> after inherit fillstroke. A later
      // `<strokealpha>` (include-shape nested setStrokeAlpha) leaks
      // onto `_paintLine` at build. collectLine is shape-level, so keep
      // leftover Trans captured when parent Geometry was painted —
      // including 0, or leftover would ribbon the opaque first rail.
      // LineColorTrans is not a token (`xmlStringToColour` zeros
      // Colour.a); leftover bakes a FillForegndTrans ribbon (Cortana /
      // vNIC 0.4–0.5 silhouettes).
      parentLine = parentLine.copyWith(
        transparency: _parentStrokeTransparency,
      );
    }
    final hostBox =
        hostRasterEntry == null ? null : _rasterLeftoverBox(hostRasterEntry);
    final hostPart = hostRasterEntry?.part;
    final host = _withSketchUserCells(
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
        shadow: (inheritFill || inheritLine)
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
        // mxSvgCanvas2D.image opacity is `s.alpha * s.fillAlpha`.
        // leftover write bakes Transparency into PNG; Draw has no
        // Foreign graphic-style opacity.
        imageTransparency: hostRasterEntry?.leftoverTransparency ?? 0,
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
    return _withMxColorSourceUserCells(
      host,
      fillFromStroke: inheritFill &&
          _parentFillFollowsStroke &&
          parentFill.hasFill &&
          parentFill.foreground == null,
      strokeFromFill: inheritLine &&
          _parentStrokeFollowsFill &&
          parentLine.hasLine &&
          parentLine.color == null,
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
        // mxStencil.drawNode uses arcsize percent. mxXmlCanvas2D.roundrect
        // writes dx/dy canvas-pixel radii (`mxSvgCanvas2D` rx/ry).
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
      case 'begin':
        // mxXmlCanvas2D.begin / mxSvgCanvas2D.begin discards the
        // unpainted path (AWS EMR leftover after fill). leftover used
        // to concatenate onto the next fill/stroke, so Draw
        // collectGeometry evenodd-punched or stroked the dropped
        // contour (`tokens.txt` Line / FillForegnd).
        _pending = null;
        _resetPen();
        break;
      case 'translate':
        // mxXmlCanvas2D.translate. leftover used to ignore the node,
        // so later inherit fill extraInheritFill siblings sat on the
        // same Pin (`tokens.txt` PinX; collectGeometry has no canvas).
        _canvasDx += _number(node, 'dx');
        _canvasDy += _number(node, 'dy');
        if (_shadow != null) _rebuildEnabledShadow();
        break;
      case 'scale':
        // mxXmlCanvas2D.scale. mxAbstractCanvas2D.scale multiplies
        // state.scale (addOp / getStrokeWidth / createDashPattern),
        // including 0 so later vertices collapse and negative so
        // addOp mirrors. leftover `value < 0` skipped the multiply,
        // so Draw collectGeometry kept the unflipped leftover inches
        // (`tokens.txt` PinX / Width). LineWeight still uses abs
        // (`tokens.txt` LineWeight).
        _applyMxCanvasScale(_number(node, 'scale', fallback: 1));
        break;
      case 'rotate':
        // mxXmlCanvas2D.rotate. leftover used to ignore the node, so
        // later inherit fill extraInheritFill siblings sat unrotated
        // (`tokens.txt` PinX; collectGeometry has no canvas). Angle is
        // shape-level, so leftover bakes mxSvgCanvas2D's SVG transform
        // into leftover inches.
        _applyMxCanvasRotate(node);
        break;
      case 'dashed':
        // mxStencil.drawNode: setDashed(dashed == '1'). Omitted / "true"
        // stay solid like official (NestedStencil uses === '1').
        _dashed = node.getAttribute('dashed') == '1';
        // Official setDashed(value) leaves fixDash undefined/false.
        // mxSvgCanvas2D.createDashPattern is
        // `(fixDash ? 1 : strokeWidth) * scale`. leftover
        // `if (fixDash != null)` kept the previous canvas-pixel gaps,
        // so Draw leftover MoveTo reused the first leftover inches
        // (`tokens.txt` has no fixDash). Omitted / empty snaps to
        // relative like createState.
        _fixDash = node.getAttribute('fixDash') == '1';
        break;
      case 'dashpattern':
        // mxStencil.drawNode / stencils.xsd use `pattern`. Cisco Guard /
        // ISDN Switch write `dash="8 8"` / `dash="12 4"` instead; official
        // getAttribute('pattern') is null and createState `3 3` would
        // paint. Honour `dash` so leftover MoveTo gaps match the XML.
        // Official `if (value != null)` skips omitted attrs; NestedStencil
        // returns. leftover assigned null so `_lineWithDash` substituted
        // createState `3 3`, Draw leftover MoveTo reused the default
        // gaps instead of the previous authored array (`tokens.txt`
        // has no custom dash).
        final raw = node.getAttribute('pattern') ?? node.getAttribute('dash');
        if (raw == null) break;
        _dashPattern = _parseMxDashPattern(raw);
        // `pattern="none"` is an empty list: mxStencil.js still
        // setDashPattern(Number('none')*minScale → NaN). createDashPattern
        // then writes stroke-dasharray="NaN", which SVG paints solid.
        // Do not fall through to createState `3 3` (AWS 4 work package).
        break;
      case 'linecap':
        // mxXmlCanvas2D.setLineCap / mxStencil.drawNode always call
        // setLineCap(cap). Omitted/invalid is null; leftover assigned
        // that and `_paintLine` skipped copyWith, so Draw collectLine
        // used Visio factory LineCap 0 (`tokens.txt` LineCap →
        // svg:stroke-linecap=round and round join). mxSvgCanvas2D
        // skips the attribute when state.lineCap is null; SVG default
        // is butt (LineCap 1 / extended).
        _lineCap = _mxLineCap(node.getAttribute('cap')) ?? LineCap.extended;
        break;
      case 'linejoin':
        // mxStencil.drawNode always setLineJoin(join). Omitted/empty
        // is null; leftover treated that as a no-op so a later
        // `<linejoin/>` kept the previous round/bevel. mxSvgCanvas2D
        // skips stroke-linejoin when state.lineJoin is null; SVG
        // default is miter. XSD is miter / round / bevel; Arrow /
        // Decider still write linecap tokens `flat` / `square`.
        // mxSvgCanvas2D then sets stroke-linejoin to that string;
        // SVG drops the invalid value and uses the CSS initial
        // `miter`. `tokens.txt` has no LineJoin; leftover bakes
        // Rounding / RelQuadBezTo so Draw collectLine miters.
        _lineJoin =
            _mxLineJoin(node.getAttribute('join')) ?? VsdxLineJoin.miter;
        break;
      case 'miterlimit':
        final limit = _number(node, 'limit', fallback: 10);
        if (limit >= 1) _miterLimit = limit;
        break;
      case 'shadow':
        _applyMxShadow(node);
        break;
      case 'shadowcolor':
        // mxXmlCanvas2D.setShadowColor. leftover used to ignore the
        // node, so collectFillAndShadow reused ShdwForegnd
        // (`tokens.txt` ShdwForegnd → draw:shadow-color).
        _applyMxShadowColor(node.getAttribute('color'));
        break;
      case 'shadowalpha':
        // mxXmlCanvas2D.setShadowAlpha always writes alpha.
        // NestedStencil Number(null)=0. leftover tryParse skip snapped
        // to SHADOW_OPACITY 1, so Draw collectFillAndShadow painted an
        // opaque rail mxSvgCanvas2D.createShadow opacity 0 never painted
        // (`tokens.txt` has no ShdwForegndTrans; ShdwPattern →
        // draw:shadow). Invalid CSS opacity stays opaque 1.
        _applyMxShadowAlpha(node.getAttribute('alpha'));
        break;
      case 'shadowoffset':
        // mxXmlCanvas2D.setShadowOffset always writes dx/dy.
        // NestedStencil Number(null)=0. leftover tryParse skip kept
        // the previous leftover inches, so Draw collectFillAndShadow
        // reused ShapeShdwOffsetX (`tokens.txt` → draw:shadow-offset-x).
        _applyMxShadowOffset(
          node.getAttribute('dx'),
          node.getAttribute('dy'),
          snapOmittedToZero: true,
        );
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
        // mxXmlCanvas2D.setFontSize always writes size, including 0.
        // leftover `size > 0` kept the previous Char.Size, so Draw
        // collectCharIX painted later glyphs with the first leftover
        // inches (`tokens.txt` Size → fo:font-size). Visio's 0.5pt
        // floor rejects empty Size; leftover `_labelShape` already
        // clamps to `_kMxMinCharSizeInches`.
        // mxStencil.drawNode is Number(getAttribute('size'))*minScale;
        // omitted is Number(null)=0. leftover tryParse skip kept the
        // previous leftover inches, so Draw painted a 24pt glyph
        // mxSvgCanvas2D.text (`fontSize > 0`) never paints.
        final raw = node.getAttribute('size');
        final size = double.tryParse((raw ?? '').trim());
        _fontSize = (size != null && size.isFinite) ? size : 0;
        break;
      case 'fontstyle':
        // mxXmlCanvas2D compressed setFontStyle, including 0 so a
        // FONT_ITALIC title does not stick on the next collectCharIX
        // sibling (fo:font-style).
        _fontStyle = _number(node, 'style').round();
        break;
      case 'fontfamily':
        // mxXmlCanvas2D.setFontFamily is CSS font-family. leftover
        // first-token froze "open sans" so Draw collectCharIX missed
        // Arial (`tokens.txt` Font → style:font-name). Walk the stack
        // like NestedStencil htmlFontFamily; omitted family is a no-op.
        final raw = node.getAttribute('family');
        if (raw != null) {
          final mapped = _mxFontFamily(raw);
          if (mapped != null) _fontFamily = mapped;
        }
        break;
      case 'fillcolor':
        // mxXmlCanvas2D.setFillColor(null) writes color="none".
        // NestedStencil mxStencilColor(null) returns null; isNoneColor
        // clears fill. leftover empty token inherited FillForegnd so
        // Draw painted palette fill (`tokens.txt` FillForegnd → svg:fill).
        final fillColor = node.getAttribute('color');
        if (fillColor == null) {
          _fillOverride = null;
          _fillFollowsStroke = false;
          _fillColor = null;
          _fillIsNone = true;
        } else {
          _applyMxFill(
            fillColor,
            fallback: node.getAttribute('default'),
          );
        }
        break;
      case 'fillgradient':
      case 'gradient':
        // mxXmlCanvas2D.setGradient is `<gradient c1= c2=>`. NestedStencil
        // capture writes `<fillgradient color1=>`. Both leftover-bake
        // FillPattern 25–40 so Draw `_fillAndShadowProperties` keeps the
        // ramp (`tokens.txt` FillPattern → draw:fill=gradient).
        _applyMxFillGradient(node);
        break;
      case 'alpha':
        // mxStencil.drawNode setAlpha(getAttribute('alpha')). Omitted
        // is null; Number(null) is 0 and mxSvgCanvas2D fill-opacity
        // is alpha*fillAlpha → 0. leftover fallback 1 kept the rail
        // opaque so Draw collectFillAndShadow painted
        // draw:opacity=1 (`tokens.txt` FillForegndTrans).
        _overallAlpha = _alphaValue(node);
        break;
      case 'fillalpha':
        _fillAlpha = _alphaValue(node);
        break;
      case 'strokealpha':
        _strokeAlpha = _alphaValue(node);
        break;
      case 'sketch':
        // NestedStencil setSketch always writes enabled="1". leftover
        // `enabled != '0'` treated omitted as on, so Draw leftover-baked
        // FillPattern 2–24 hatch mxRoughCanvas2D never painted
        // (`tokens.txt` FillPattern → draw:fill=hatch). Same === '1'
        // as leftover `<shadow>` / NestedStencil setShadow.
        _sketchEnabled = node.getAttribute('enabled') == '1';
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
        // mxXmlCanvas2D.setStrokeColor(null) writes color="none".
        // NestedStencil mxStencilColor(null) returns null; isNoneColor
        // clears stroke. leftover empty token inherited LineColor so
        // Draw painted palette stroke (`tokens.txt` LineColor → svg:stroke).
        final strokeColor = node.getAttribute('color');
        if (strokeColor == null) {
          _strokeFollowsFill = false;
          _strokeColor = null;
          _strokeIsNone = true;
        } else {
          _applyMxStroke(
            strokeColor,
            fallback: node.getAttribute('default'),
          );
        }
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
        // mxXmlCanvas2D.setStrokeWidth always writes width, including
        // 0. leftover `width > 0` kept the previous leftover inches,
        // so Draw collectLine stroked the hairline with the thick
        // rail (`tokens.txt` LineWeight). Official
        // `getCurrentStrokeWidth` is max(minStrokeWidth=1, …).
        final raw = node.getAttribute('width');
        final width = double.tryParse(raw ?? '');
        if (width != null && width.isFinite) {
          _strokeWidth = width;
          _strokeWidthFixed = node.getAttribute('fixed') == '1';
        }
        break;
      case 'text':
        final runs = _decodeTextRuns(node);
        if (runs.isNotEmpty) {
          _labels.add(_snapshotLabelCanvas(_DrawioStencilLabel(
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
            // mxXmlCanvas2D.text dir vertical-* is SVG writing-mode.
            // mxStencil.drawNode uses vertical="1" instead.
            vertical: node.getAttribute('vertical') == '1' ||
                (node.getAttribute('dir') ?? '')
                    .toLowerCase()
                    .startsWith('vertical-'),
            wrap: node.getAttribute('wrap') == '1',
            // mxXmlCanvas2D.text always writes clip; mxStencil.drawNode
            // passes false. overflow fill|width|block also keep the cell
            // box (plainText / createCss). leftover wrap=0 otherwise
            // expands TxtWidth so Draw shows overflow (`tokens.txt`
            // has no veWordWrap).
            clip: node.getAttribute('clip') == '1',
            overflow: node.getAttribute('overflow'),
            // mxXmlCanvas2D.text dir=rtl. leftover Paragraph Flags so
            // `_fillParagraphProperties` swaps left↔end (`tokens.txt`
            // Flags). mxStencil.drawNode never passes dir.
            rtl: (node.getAttribute('dir') ?? '').toLowerCase() == 'rtl',
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
            fontFromStroke: _fontFollowsStroke,
            fontFromFill: _fontFollowsFill,
            fontBgFromStroke: _fontBgFollowsStroke,
            fontBgFromFill: _fontBgFollowsFill,
            fontBorderFromStroke: _fontBorderFollowsStroke,
            fontBorderFromFill: _fontBorderFollowsFill,
            runs: runs,
          )));
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
      // Omitted `<fillcolor/>` color is setFillColor(null) / none so
      // Draw does not inherit FillForegnd (`tokens.txt` → svg:fill).
      // Omitted `<strokecolor/>` color is setStrokeColor(null) / none so
      // Draw does not inherit LineColor (`tokens.txt` → svg:stroke).
      // `fillgradient` / mxXmlCanvas2D `<gradient c1= c2=>` bake
      // FillPattern 25–34 so libvisio's two-stop linear
      // (`_fillAndShadowProperties`) keeps AWS brand ramps;
      // `applyStencilStyle.withSolidForeground` would otherwise beige them.
      // `alpha` / `fillalpha` / `strokealpha` become FillForegndTrans /
      // LineColorTrans that `_fillAndShadowProperties` maps to draw:opacity.
      // Omitted alpha attr is Number(null)=0 so Draw does not paint
      // an opaque rail (`tokens.txt` FillForegndTrans).
      // Inherit fill (Networks2 hub shadow) and inherit stroke
      // (Cortana fillstroke) capture that Trans on the parent at
      // _finish; hex fillcolor already bakes a sibling.
      // `fillstrokecolor` is not fillstroke: official drawNode skips
      // it, so IBM watson's pending 32×32 frame stays stroke-only.
      // `linecap` / `linejoin` / `miterlimit` / `dashpattern` follow
      // mxStencil.drawNode onto collectLine LineCap / LinePattern (custom
      // arrays bake to a MoveTo ribbon because libvisio treats 0xfe as solid).
      // Omitted linecap cap snaps to LineCap 1 (SVG butt) so Draw does
      // not round (`tokens.txt` LineCap).
      // Omitted linejoin join snaps to miter (SVG default) so Draw
      // does not keep a prior round leftover (`tokens.txt` has no
      // LineJoin; leftover Rounding / RelQuadBezTo).
      // `dashpattern pattern="none"` is NaN in official drawNode, so SVG
      // stroke-dasharray is invalid and Draw must stay solid (AWS 4
      // work package), not createState `3 3`. Cisco `dash="8 8"` (no
      // `pattern`) is the authored array leftover bakes to MoveTo gaps.
      // Omitted `<dashpattern/>` is a no-op like official `if (value
      // != null)` so Draw leftover MoveTo keeps the previous array.
      // Omitted `<dashed>` fixDash snaps to createState false
      // (× LineWeight) so Draw leftover MoveTo does not keep a prior
      // canvas-pixel gap (`tokens.txt` has no fixDash).
      // `shadow` follows mxShape.configureCanvas / mxXmlCanvas2D
      // setShadow onto ShdwPattern that `_fillAndShadowProperties`
      // maps to ODF draw:shadow. Omitted enabled is off (`=== '1'`),
      // same as NestedStencil and leftover dashed.
      // `sketch` follows Graph mxRoughCanvas2D / NestedStencil
      // setSketch onto leftover FillPattern 2–24 hatch. Omitted
      // enabled is off (`=== '1'`), same as leftover shadow.
      // `shadowcolor` / `shadowalpha` / `shadowoffset` follow
      // mxXmlCanvas2D setShadowColor / setShadowAlpha / setShadowOffset
      // onto ShdwForegnd / ShapeShdwOffset* (`tokens.txt`). A later
      // inherit paint leftover-bakes a sibling because collectFillAndShadow
      // is shape-level. ShdwForegndTrans is not a token, so a save
      // premultiplies RGB.
      // Omitted `<shadowoffset/>` dx/dy is Number(null)=0 so Draw
      // does not reuse the previous leftover inches.
      // `fontfamily` follows mxStencil.drawNode / mxXmlCanvas2D
      // setFontFamily onto Char.Font that collectCharIX maps to
      // style:font-name. CSS stacks skip webfonts so `"open sans", arial`
      // freezes Arial (`tokens.txt` Font).
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
      // `text` format=html leftover-parses mxXmlCanvas2D `str` HTML
      // (`canvas.text(..., format)`). mxStencil.drawNode always
      // passes format=''; JS capture rewrites html=1 into `<run>`
      // children and never writes the attr. leftover used to treat
      // the markup as one collectText string, so Draw painted `<b>`
      // tags (`tokens.txt` Character is collectText; Style.bold is
      // collectCharIX). leftover now walks `<b>`/`<font>`/`<ul>`
      // like NestedStencil parseHtmlLabel.
      // `labelBounds` follows draw.io mxStencil.getLabelBounds (boundedLbl)
      // onto TxtPin / TxtWidth / TxtHeight that collectTextBlock maps
      // below the stacked Multi-Document sheet.
      // `path rounded="1"` follows mxStencil.drawNode addPoints (move/line
      // only) onto QuadBezTo leftover RelQuadBezTo (`tokens.txt` has no
      // LineJoin; Draw round-joins from LineCap). Other path children
      // fall through to regular MoveTo/LineTo/CubBezTo like official.
      // `roundrect` dx/dy follow mxXmlCanvas2D.roundrect onto leftover
      // CubBezTo. mxSvgCanvas2D.roundrect sets SVG rx/ry only when
      // dx/dy > 0; JS capture of r=0 writes `<rect>`. leftover used
      // to ignore dx/dy and default arcsize 15, so Draw
      // collectGeometry rounded a sharp canvas roundrect
      // (`tokens.txt` has CubBezTo as RelCubBezTo). leftover now
      // uses dx/dy when present (0 is a sharp rect) and keeps
      // arcsize for mxStencil XML.
      // `text` align-shape="0" follows drawNode onto TxtAngle that
      // counters collectXFormData Angle so Draw keeps the glyph upright.
      // STYLE_FLIPH xor STYLE_FLIPV (one axis) adds Angle instead;
      // leftover FlipX/Y comes from `cellfliph` / `cellflipv`.
      // `text` clip / overflow follow mxXmlCanvas2D.text onto leftover
      // TxtWidth. mxSvgCanvas2D.plainText clipPath / overflow fill|width
      // keep the cell box; wrap=0 leftover used to withWordWrap(false)
      // so a save expanded TxtWidth (`tokens.txt` has no veWordWrap;
      // collectTextBlock svg:width is TxtWidth). leftover now keeps the
      // box so Draw wraps inside the clip frame instead of overflowing.
      // `text` dir follows mxXmlCanvas2D.text onto leftover Paragraph
      // Flags / TextDirection. mxSvgCanvas2D.plainText sets SVG
      // `direction` / vertical-* writing-mode; leftover used to ignore
      // it, so Draw `_fillParagraphProperties` kept LTR fo:text-align
      // (`tokens.txt` Flags swaps left↔end when nonzero). leftover now
      // bakes Flags=1 for rtl and TextDirection=1 for vertical-*.
      // `image` x/y/w/h follow mxStencil.drawNode onto ImgOffset /
      // ImgWidth that collectForeignDataType maps to svg:x / svg:width.
      // Nested include-shape copies leftover inches (`w*sx, h*sy`) so
      // variable aspect does not keep the nested source square.
      // A later canvas.image (host or another include-shape) leftover
      // appends a ForeignData child so Draw keeps every PNG.
      // `image` flipH/flipV leftover-bakes FlipX on a ForeignData child
      // (`draw:mirror-*`); host FlipX stays `cellfliph` so applyXForm
      // does not mirror later Geometry.
      // `image` aspect follows mxXmlCanvas2D onto leftover Img*
      // (`mxSvgCanvas2D.image` preserveAspectRatio meet vs none).
      // mxStencil.drawNode always stretches (`aspect=false`); JS
      // capture omits the attr. leftover used to ignore it, so Draw
      // collectForeignDataType stretched every PNG (`tokens.txt` has
      // no image aspect; svg:width is ImgWidth with no clip). leftover
      // now letterboxes Img* for aspect="1".
      // `image` canvas alpha follows mxSvgCanvas2D.image
      // (`s.alpha * s.fillAlpha`) onto leftover Transparency. libvisio
      // `_flushCurrentForeignData` emits an empty graphic style
      // (`tokens.txt` has no Foreign opacity), so a save bakes that
      // into the PNG Draw paints. leftover snapshots at emit so a
      // later `<alpha>` / `<fillalpha>` cannot fade earlier bitmaps.
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
      // Later `<fontsize size="0"/>` leftover-bakes Visio's 0.5pt
      // Char.Size floor because leftover used to skip size<=0
      // (`tokens.txt` Size → collectCharIX fo:font-size).
      // Omitted `<fontsize/>` is Number(null)=0 the same way.
      // Nested save/restore shares canvas.states; leftover seeds a
      // converted copy so nested restore can pop a host save. Unequal
      // counts reset to the entry snapshot (`drawShape` assigns
      // `canvas.states = stack`) so leftover never copies nested
      // leftover saves onto the host (`tokens.txt` LineColor).
      // Later `<strokewidth>` / nested setStrokeWidth leftover-bakes a
      // LineWeight sibling because collectLine is shape-level
      // (`tokens.txt` LineWeight). `width="0"` follows
      // mxSvgCanvas2D.getCurrentStrokeWidth minStrokeWidth=1 canvas
      // pixel so Draw paints the hairline instead of the previous
      // thick leftover inches.
      // `translate` / `scale` follow mxXmlCanvas2D onto leftover
      // inches (`addOp` `(x + dx) * scale`). JS capture bakes those
      // into coordinates and never emits the nodes; official playback
      // still has them. leftover used to ignore them, so Draw
      // collectGeometry kept the untransformed Pin (`tokens.txt` PinX /
      // Width). include-shape bakes the host transform into the overlay
      // origin / minScale and resets nested dx/scale so nested
      // `_x`/`_y` do not apply them twice.
      // `rotate` follows mxXmlCanvas2D onto leftover inches
      // (`mxSvgCanvas2D.rotate` SVG transform). leftover used to ignore
      // it, so Draw collectGeometry kept the unrotated Pin (`tokens.txt`
      // PinX / Angle). include-shape copies leftover-inch rotation so
      // nested `_x`/`_y` apply the host transform once.
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
    var left = _number(node, 'x');
    var top = _number(node, 'y');
    var boxW = _number(node, 'w');
    var boxH = _number(node, 'h');
    // mxXmlCanvas2D.image always writes aspect (default true). Official
    // mxSvgCanvas2D.image uses preserveAspectRatio meet when aspect, and
    // "none" when false. mxStencil.drawNode always passes false (stretch);
    // JS capture omits the attr. libvisio collectForeignDataType maps
    // Img* to svg:width with no clip (`tokens.txt` has no image aspect),
    // so leftover letterboxes Img* for aspect="1" or Draw stretches the
    // PNG into the stencil box.
    if (_flag(node, 'aspect') && boxW > 1e-9 && boxH > 1e-9) {
      final size = _rasterPixelSize(parsed.bytes);
      if (size != null) {
        final meet = _mxSvgMeetBox(
          left: left,
          top: top,
          boxW: boxW,
          boxH: boxH,
          imageW: size.width,
          imageH: size.height,
        );
        left = meet.left;
        top = meet.top;
        boxW = meet.width;
        boxH = meet.height;
      }
    }
    _rasters.add(_snapshotRasterCanvas(_DrawioRaster(
      part: registerDrawioStencilImage(
        parsed.bytes,
        mimeType: parsed.mime,
      ),
      mime: parsed.mime,
      // mxStencil.drawNode image x/y/w/h. libvisio collectForeignDataType
      // maps ImgOffsetX/Y + ImgWidth/Height to svg:x/y/width/height.
      // A missing box stretches the PNG over the XForm (IBM Floating IP
      // is a mid-band icon on a 60×60 cell).
      left: left,
      top: top,
      boxW: boxW > 1e-9 ? boxW : null,
      boxH: boxH > 1e-9 ? boxH : null,
      flipH: node.getAttribute('flipH') == '1',
      flipV: node.getAttribute('flipV') == '1',
    )));
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
      originX: _leftoverUnrotated(x0, y0 + nestedH * sy).x,
      originY: _leftoverUnrotated(x0, y0 + nestedH * sy).y,
      overlayScaleX: sx * scaleX * _canvasUserScale,
      overlayScaleY: sy * scaleY * _canvasUserScale,
      canvasScale: _canvasScale * _canvasUserScale,
    );
    // Host leftover already applied canvas dx/scale. Nested overlay
    // minScale includes userScale so nested `_x`/`_y` stay identity.
    // leftover-inch rotation stays (shared canvas; Angle is shape-level).
    nested._canvasDx = 0;
    nested._canvasDy = 0;
    nested._canvasUserScale = 1;
    // mxStencil.drawNode include-shape shares the canvas. Host
    // setDashPattern already multiplied by host minScale; nested
    // `_fixedDashPatternValues` would multiply again by nested
    // min(sx,sy). Fold leftover inches into nested stencil units
    // so Draw collectLine gaps match NestedStencil.
    nested._scaleAdoptedCanvasDashFrom(this);
    nested._scaleAdoptedCanvasFontFrom(this);
    nested._scaleAdoptedCanvasShadowFrom(this);
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
    // Nested `_consume` snapshots leftover-inch Pin / TxtAngle / Img*
    // at emit (overlay origin is already host leftover inches). Host
    // `_labelShape` / `_rasterLeftoverBox` use that snapshot so a later
    // host `<rotate>` cannot drag nested glyphs. Remap only labels that
    // somehow missed the snapshot.
    _labels.addAll([
      for (final label in nested._labels)
        label.leftoverPinX != null
            ? label
            : nested._labelInParentStencilSpace(label, parent: this),
    ]);
    for (final nestedRaster in nested._rasters) {
      // Nested overlay already mapped geometry through leftover `_x`/`_y`.
      // Official canvas.image is `w*sx, h*sy` in those canvas pixels.
      // Emit-time leftover Img* / Angle is already host leftover inches.
      if (nestedRaster.leftoverWidth != null) {
        _rasters.add(nestedRaster);
        continue;
      }
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
          leftoverTransparency: nestedRaster.leftoverTransparency,
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
    final hostDx = _canvasDx;
    final hostDy = _canvasDy;
    final hostUser = _canvasUserScale;
    _adoptPaint(nested);
    // Nested overlay baked the host canvas into origin / minScale and
    // reset nested dx/scale. Keep the host transform for later paint.
    _canvasDx = hostDx;
    _canvasDy = hostDy;
    _canvasUserScale = hostUser;
    if (hostMin < 1e-12) return;
    final hostUnit = hostMin * hostUser;
    final nestedUnit = nestedMin * nested._canvasUserScale;
    // Nested drawShape always setStrokeWidth from the nested stencil.
    if (nested._strokeWidth != null && hostUnit > 1e-12) {
      _strokeWidth = nested._strokeWeightInches / hostUnit;
      _strokeWidthFixed = false;
    }
    // NestedStencil last setFontSize / setDashPattern stay on the
    // shared canvas. leftover `_fontSize` / `_dashPattern` are stencil
    // units of the nested overlay — map leftover inches back to host.
    if (nestedUnit > 1e-12 && hostUnit > 1e-12) {
      _fontSize = nested._fontSize * nestedUnit / hostUnit;
    }
    final dashes = nested._dashPattern;
    if (dashes != null && dashes.isEmpty) {
      _dashPattern = const <double>[];
    } else if (dashes != null &&
        dashes.isNotEmpty &&
        nestedUnit > 1e-12 &&
        hostUnit > 1e-12) {
      _dashPattern = [
        for (final value in dashes) value * nestedUnit / hostUnit,
      ];
    } else {
      _dashPattern = hostDash == null ? null : List<double>.of(hostDash);
    }
    final hostXUnit = scaleX.abs() * hostUser;
    final nestedXUnit = nested.scaleX.abs() * nested._canvasUserScale;
    if (nestedXUnit > 1e-12 && hostXUnit > 1e-12) {
      _shadowDx = nested._shadowDx * nestedXUnit / hostXUnit;
    }
    final hostYUnit = scaleY.abs() * hostUser;
    final nestedYUnit = nested.scaleY.abs() * nested._canvasUserScale;
    if (nestedYUnit > 1e-12 && hostYUnit > 1e-12) {
      _shadowDy = nested._shadowDy * nestedYUnit / hostYUnit;
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
    final destUser = from._canvasUserScale.abs() < 1e-12
        ? 1.0
        : source.canvasUserScale / from._canvasUserScale;
    final destDx = scaleX.abs() < 1e-12
        ? source.canvasDx
        : (source.canvasDx - from._canvasDx) * from.scaleX / scaleX;
    final destDy = scaleY.abs() < 1e-12
        ? source.canvasDy
        : (source.canvasDy - from._canvasDy) * from.scaleY / scaleY;
    final fromUnit = fromMin * source.canvasUserScale;
    final toUnit = toMin * destUser;
    final ratio =
        (fromUnit < 1e-12 || toUnit < 1e-12) ? 1.0 : fromUnit / toUnit;
    double? strokeWidth;
    final srcWidth = source.strokeWidth;
    if (srcWidth != null) {
      final fromScale =
          source.strokeWidthFixed ? from._canvasScale.abs() : fromMin;
      final inches = fromScale < 1e-12
          ? srcWidth
          : math.max(0.001, srcWidth * fromScale * source.canvasUserScale);
      strokeWidth = toUnit < 1e-12 ? inches : inches / toUnit;
    }
    final dashes = source.dashPattern;
    final fromXUnit = from.scaleX.abs() * source.canvasUserScale;
    final toXUnit = scaleX.abs() * destUser;
    final fromYUnit = from.scaleY.abs() * source.canvasUserScale;
    final toYUnit = scaleY.abs() * destUser;
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
      fillFollowsStroke: source.fillFollowsStroke,
      strokeFollowsFill: source.strokeFollowsFill,
      fontFollowsStroke: source.fontFollowsStroke,
      fontFollowsFill: source.fontFollowsFill,
      fontBgFollowsStroke: source.fontBgFollowsStroke,
      fontBgFollowsFill: source.fontBgFollowsFill,
      fontBorderFollowsStroke: source.fontBorderFollowsStroke,
      fontBorderFollowsFill: source.fontBorderFollowsFill,
      overallAlpha: source.overallAlpha,
      fillAlpha: source.fillAlpha,
      strokeAlpha: source.strokeAlpha,
      strokeWidth: strokeWidth,
      strokeWidthFixed: false,
      dashed: source.dashed,
      fixDash: source.fixDash,
      dashPattern: dashes == null
          ? null
          : dashes.isEmpty
              ? const <double>[]
              : [for (final value in dashes) value * ratio],
      lineCap: source.lineCap,
      lineJoin: source.lineJoin,
      miterLimit: source.miterLimit,
      shadow: source.shadow,
      shadowColor: source.shadowColor,
      shadowAlpha: source.shadowAlpha,
      shadowDx: fromXUnit < 1e-12 || toXUnit < 1e-12
          ? source.shadowDx
          : source.shadowDx * fromXUnit / toXUnit,
      shadowDy: fromYUnit < 1e-12 || toYUnit < 1e-12
          ? source.shadowDy
          : source.shadowDy * fromYUnit / toYUnit,
      sketchEnabled: source.sketchEnabled,
      sketchFill: source.sketchFill,
      sketchGap: source.sketchGap,
      sketchAngle: source.sketchAngle,
      sketchWeight: source.sketchWeight,
      sketchJiggle: source.sketchJiggle,
      canvasDx: destDx,
      canvasDy: destDy,
      canvasUserScale: destUser,
      // leftover-inch rotation is already in the host leftover space
      // nested overlay uses.
      rotThetaDeg: source.rotThetaDeg,
      rotFlipH: source.rotFlipH,
      rotFlipV: source.rotFlipV,
      rotCxLeftover: source.rotCxLeftover,
      rotCyLeftover: source.rotCyLeftover,
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
    final hostUnit = hostMin * host._canvasUserScale;
    final nestedUnit = nestedMin * _canvasUserScale;
    if (nestedUnit < 1e-12) return;
    _dashPattern = [
      for (final value in source) value * hostUnit / nestedUnit,
    ];
  }

  /// Host `setFontSize(size*hostMinScale)` leftover inches, expressed in
  /// this overlay's stencil units so `_labelInParentStencilSpace` does
  /// not apply nested minScale a second time.
  void _scaleAdoptedCanvasFontFrom(_DrawioXmlShapeDecoder host) {
    final hostMin = math.min(host.scaleX.abs(), host.scaleY.abs());
    final nestedMin = math.min(scaleX.abs(), scaleY.abs());
    if (nestedMin < 1e-12) return;
    final hostUnit = hostMin * host._canvasUserScale;
    final nestedUnit = nestedMin * _canvasUserScale;
    if (nestedUnit < 1e-12) return;
    _fontSize = _fontSize * hostUnit / nestedUnit;
  }

  /// Host `setShadowOffset` leftover inches, expressed in this overlay's
  /// stencil units so `_shadowFromCanvas` does not apply nested scale
  /// a second time.
  void _scaleAdoptedCanvasShadowFrom(_DrawioXmlShapeDecoder host) {
    final hostXUnit = host.scaleX.abs() * host._canvasUserScale;
    final nestedXUnit = scaleX.abs() * _canvasUserScale;
    if (nestedXUnit > 1e-12 && hostXUnit > 1e-12) {
      _shadowDx = _shadowDx * hostXUnit / nestedXUnit;
    }
    final hostYUnit = host.scaleY.abs() * host._canvasUserScale;
    final nestedYUnit = scaleY.abs() * _canvasUserScale;
    if (nestedYUnit > 1e-12 && hostYUnit > 1e-12) {
      _shadowDy = _shadowDy * hostYUnit / nestedYUnit;
    }
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
    _fillFollowsStroke = other._fillFollowsStroke;
    _strokeFollowsFill = other._strokeFollowsFill;
    _fontFollowsStroke = other._fontFollowsStroke;
    _fontFollowsFill = other._fontFollowsFill;
    _fontBgFollowsStroke = other._fontBgFollowsStroke;
    _fontBgFollowsFill = other._fontBgFollowsFill;
    _fontBorderFollowsStroke = other._fontBorderFollowsStroke;
    _fontBorderFollowsFill = other._fontBorderFollowsFill;
    _overallAlpha = other._overallAlpha;
    _fillAlpha = other._fillAlpha;
    _strokeAlpha = other._strokeAlpha;
    _strokeWidth = other._strokeWidth;
    _strokeWidthFixed = other._strokeWidthFixed;
    _dashed = other._dashed;
    _fixDash = other._fixDash;
    _dashPattern = other._dashPattern == null
        ? null
        : List<double>.of(other._dashPattern!);
    _lineCap = other._lineCap;
    _lineJoin = other._lineJoin;
    _miterLimit = other._miterLimit;
    _shadow = other._shadow;
    _shadowColor = other._shadowColor;
    _shadowAlpha = other._shadowAlpha;
    _shadowDx = other._shadowDx;
    _shadowDy = other._shadowDy;
    _sketchEnabled = other._sketchEnabled;
    _sketchFill = other._sketchFill;
    _sketchGap = other._sketchGap;
    _sketchAngle = other._sketchAngle;
    _sketchWeight = other._sketchWeight;
    _sketchJiggle = other._sketchJiggle;
    _canvasDx = other._canvasDx;
    _canvasDy = other._canvasDy;
    _canvasUserScale = other._canvasUserScale;
    _rotThetaDeg = other._rotThetaDeg;
    _rotFlipH = other._rotFlipH;
    _rotFlipV = other._rotFlipV;
    _rotCxLeftover = other._rotCxLeftover;
    _rotCyLeftover = other._rotCyLeftover;
  }

  /// Visio Image Properties are Y-up from the shape origin. mxStencil
  /// image y is top-down stencil space, same as `<rect>`.
  ///
  /// mxSvgCanvas2D.image puts `s.transform` (canvas.rotate) on the
  /// `<image>` group; collectForeignDataType transformAngle uses the
  /// shape Angle. leftover keeps w×h axis-aligned and rotates about
  /// the leftover centre so Draw librevenge:rotate stands the PNG up.
  /// Emit-time snapshot so a later `<rotate>` cannot drag earlier
  /// bitmaps (`tokens.txt` Angle / FlipX / ImgOffsetX).
  ({double offsetX, double offsetY, double width, double height})?
      _rasterLeftoverBox(_DrawioRaster raster) {
    if (raster.leftoverWidth != null && raster.leftoverHeight != null) {
      return (
        offsetX: raster.leftoverOffsetX ?? 0,
        offsetY: raster.leftoverOffsetY ?? 0,
        width: raster.leftoverWidth!,
        height: raster.leftoverHeight!,
      );
    }
    return _rasterLeftoverBoxAtEmit(raster);
  }

  ({double offsetX, double offsetY, double width, double height})?
      _rasterLeftoverBoxAtEmit(_DrawioRaster raster) {
    final boxW = raster.boxW;
    final boxH = raster.boxH;
    late final double width;
    late final double height;
    late final double left;
    late final double top;
    late final double srcW;
    late final double srcH;
    if (boxW != null && boxH != null) {
      width = boxW * scaleX.abs() * _canvasUserScale.abs();
      height = boxH * scaleY.abs() * _canvasUserScale.abs();
      left = raster.left ?? 0;
      top = raster.top ?? 0;
      srcW = boxW;
      srcH = boxH;
    } else {
      if (targetWidth <= 1e-9 || targetHeight <= 1e-9) return null;
      width = targetWidth;
      height = targetHeight;
      left = 0;
      top = 0;
      srcW = sourceWidth;
      srcH = sourceHeight;
    }
    if (width <= 1e-9 || height <= 1e-9) return null;
    final centre = _leftoverOf(left + srcW / 2, top + srcH / 2);
    return (
      offsetX: centre.x - width / 2,
      offsetY: centre.y - height / 2,
      width: width,
      height: height,
    );
  }

  _DrawioRaster _snapshotRasterCanvas(_DrawioRaster raster) {
    // mxSvgCanvas2D.image opacity is `s.alpha * s.fillAlpha`, not
    // strokeAlpha. leftover Transparency is the inverse so a save
    // bakes PNG alpha (`tokens.txt` has no Foreign opacity).
    final faded = raster.copyWith(leftoverTransparency: _fillTransparency);
    final box = _rasterLeftoverBoxAtEmit(faded);
    if (box == null) return faded;
    return faded.copyWith(
      leftoverOffsetX: box.offsetX,
      leftoverOffsetY: box.offsetY,
      leftoverWidth: box.width,
      leftoverHeight: box.height,
      leftoverAngleRad: _canvasLeftoverRotationRad,
      leftoverCanvasFlipX: _canvasXorFlipX,
      leftoverCanvasFlipY: _canvasXorFlipY,
    );
  }

  bool _rasterStaysOnHost(_DrawioRaster raster) =>
      !raster.flipH &&
      !raster.flipV &&
      raster.leftoverAngleRad.abs() <= 1e-12 &&
      !raster.leftoverCanvasFlipX &&
      !raster.leftoverCanvasFlipY;

  /// Inverse of [_rasterLeftoverBox]: leftover inches → this decoder's
  /// stencil units. include-shape copies nested overlay leftover.
  _DrawioRaster _rasterFromLeftover(
    ({double offsetX, double offsetY, double width, double height}) box,
    _DrawioRaster source,
  ) {
    final src = _sourceFromLeftover(box.offsetX, box.offsetY);
    final left = src.x;
    final xUnit = scaleX.abs() * _canvasUserScale.abs();
    final yUnit = scaleY.abs() * _canvasUserScale.abs();
    final boxW = xUnit < 1e-12 ? box.width : box.width / xUnit;
    final boxH = yUnit < 1e-12 ? box.height : box.height / yUnit;
    final bottomSrc = src.y;
    return _DrawioRaster(
      part: source.part,
      mime: source.mime,
      left: left,
      top: bottomSrc - boxH,
      boxW: boxW,
      boxH: boxH,
      flipH: source.flipH,
      flipV: source.flipV,
      leftoverOffsetX: source.leftoverOffsetX,
      leftoverOffsetY: source.leftoverOffsetY,
      leftoverWidth: source.leftoverWidth,
      leftoverHeight: source.leftoverHeight,
      leftoverAngleRad: source.leftoverAngleRad,
      leftoverCanvasFlipX: source.leftoverCanvasFlipX,
      leftoverCanvasFlipY: source.leftoverCanvasFlipY,
      leftoverTransparency: source.leftoverTransparency,
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
        fillFollowsStroke: _fillFollowsStroke,
        strokeFollowsFill: _strokeFollowsFill,
        fontFollowsStroke: _fontFollowsStroke,
        fontFollowsFill: _fontFollowsFill,
        fontBgFollowsStroke: _fontBgFollowsStroke,
        fontBgFollowsFill: _fontBgFollowsFill,
        fontBorderFollowsStroke: _fontBorderFollowsStroke,
        fontBorderFollowsFill: _fontBorderFollowsFill,
        overallAlpha: _overallAlpha,
        fillAlpha: _fillAlpha,
        strokeAlpha: _strokeAlpha,
        strokeWidth: _strokeWidth,
        strokeWidthFixed: _strokeWidthFixed,
        dashed: _dashed,
        fixDash: _fixDash,
        dashPattern: _dashPattern == null
            ? null
            : List<double>.unmodifiable(_dashPattern!),
        lineCap: _lineCap,
        lineJoin: _lineJoin,
        miterLimit: _miterLimit,
        shadow: _shadow,
        shadowColor: _shadowColor,
        shadowAlpha: _shadowAlpha,
        shadowDx: _shadowDx,
        shadowDy: _shadowDy,
        sketchEnabled: _sketchEnabled,
        sketchFill: _sketchFill,
        sketchGap: _sketchGap,
        sketchAngle: _sketchAngle,
        sketchWeight: _sketchWeight,
        sketchJiggle: _sketchJiggle,
        canvasDx: _canvasDx,
        canvasDy: _canvasDy,
        canvasUserScale: _canvasUserScale,
        rotThetaDeg: _rotThetaDeg,
        rotFlipH: _rotFlipH,
        rotFlipV: _rotFlipV,
        rotCxLeftover: _rotCxLeftover,
        rotCyLeftover: _rotCyLeftover,
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
    _fillFollowsStroke = saved.fillFollowsStroke;
    _strokeFollowsFill = saved.strokeFollowsFill;
    _fontFollowsStroke = saved.fontFollowsStroke;
    _fontFollowsFill = saved.fontFollowsFill;
    _fontBgFollowsStroke = saved.fontBgFollowsStroke;
    _fontBgFollowsFill = saved.fontBgFollowsFill;
    _fontBorderFollowsStroke = saved.fontBorderFollowsStroke;
    _fontBorderFollowsFill = saved.fontBorderFollowsFill;
    _overallAlpha = saved.overallAlpha;
    _fillAlpha = saved.fillAlpha;
    _strokeAlpha = saved.strokeAlpha;
    _strokeWidth = saved.strokeWidth;
    _strokeWidthFixed = saved.strokeWidthFixed;
    _dashed = saved.dashed;
    _fixDash = saved.fixDash;
    _dashPattern = saved.dashPattern == null
        ? null
        : List<double>.from(saved.dashPattern!);
    _lineCap = saved.lineCap;
    _lineJoin = saved.lineJoin;
    _miterLimit = saved.miterLimit;
    _shadow = saved.shadow;
    _shadowColor = saved.shadowColor;
    _shadowAlpha = saved.shadowAlpha;
    _shadowDx = saved.shadowDx;
    _shadowDy = saved.shadowDy;
    _sketchEnabled = saved.sketchEnabled;
    _sketchFill = saved.sketchFill;
    _sketchGap = saved.sketchGap;
    _sketchAngle = saved.sketchAngle;
    _sketchWeight = saved.sketchWeight;
    _sketchJiggle = saved.sketchJiggle;
    _canvasDx = saved.canvasDx;
    _canvasDy = saved.canvasDy;
    _canvasUserScale = saved.canvasUserScale;
    _rotThetaDeg = saved.rotThetaDeg;
    _rotFlipH = saved.rotFlipH;
    _rotFlipV = saved.rotFlipV;
    _rotCxLeftover = saved.rotCxLeftover;
    _rotCyLeftover = saved.rotCyLeftover;
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
    _fillFollowsStroke = false;
    final token = (raw ?? '').trim();
    final lower = token.toLowerCase();
    if (token.isEmpty ||
        lower == 'fill' ||
        lower == 'default' ||
        token == 'fillColor') {
      _fillColor = null;
      _fillIsNone = false;
      return;
    }
    if (lower == 'none' || lower == 'transparent') {
      _fillColor = null;
      _fillIsNone = true;
      return;
    }
    if (lower == 'stroke' || token == 'strokeColor') {
      // mxStencil.parseColor('stroke') is shape.stroke.
      // getColorValue('strokeColor') is STYLE_STROKECOLOR (iOS 7 Location
      // 22 / Controls2). Catalog leftover has no cell style, so inherit
      // LineColor stays null and a User row lets applyStencilStyle pin
      // palette stroke. A prior hex `<strokecolor>` is the shared-canvas
      // colour leftover bakes.
      _fillColor = _strokeColor;
      _fillIsNone = _strokeIsNone;
      _fillFollowsStroke = _strokeColor == null && !_strokeIsNone;
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
    final color1 = node.getAttribute('color1') ?? node.getAttribute('c1');
    final color2 = node.getAttribute('color2') ?? node.getAttribute('c2');
    final start = _mxGraphPaintColor(color1);
    final end = _mxGraphPaintColor(color2);
    if (start == null) {
      _applyMxFill(
        color1,
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
    _fillFollowsStroke = false;
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
        color1,
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

  double _alphaValue(XmlElement node) {
    // mxStencil.drawNode getAttribute('alpha') is null when omitted.
    // Number(null) / NestedStencil attrNum fallback is 0; leftover
    // `_number` fallback 1 kept FillForegndTrans 0 so Draw painted
    // an opaque rail mxSvgCanvas2D fill-opacity 0 never painted
    // (`tokens.txt` FillForegndTrans → draw:opacity). Invalid CSS
    // opacity is opaque 1 (NestedStencil _setAlphaChannel NaN).
    final raw = node.getAttribute('alpha');
    if (raw == null || raw.trim().isEmpty) return 0;
    final parsed = double.tryParse(raw.trim());
    if (parsed == null || !parsed.isFinite) return 1;
    return parsed.clamp(0.0, 1.0).toDouble();
  }

  /// STYLE_TEXT_OPACITY percent × canvas setAlpha (`<alpha>`).
  double _opacityPercentWithCanvasAlpha(double percent) =>
      (percent * _overallAlpha.clamp(0.0, 1.0)).clamp(0.0, 100.0);

  void _applyMxStroke(String? raw, {String? fallback}) {
    final token = (raw ?? '').trim();
    final lower = token.toLowerCase();
    _strokeFollowsFill = false;
    if (token.isEmpty ||
        lower == 'stroke' ||
        lower == 'default' ||
        token == 'strokeColor') {
      _strokeColor = null;
      _strokeIsNone = false;
      return;
    }
    if (lower == 'none' || lower == 'transparent') {
      _strokeColor = null;
      _strokeIsNone = true;
      return;
    }
    if (lower == 'fill' || token == 'fillColor') {
      // mxStencil.parseColor('fill') is shape.fill.
      // getColorValue('fillColor') is STYLE_FILLCOLOR (Cisco
      // strokecolor fillColor). Inherit FillForegnd stays null so
      // applyStencilStyle can pin palette fill onto collectLine
      // LineColor (`tokens.txt`).
      _strokeColor = _fillColor;
      _strokeIsNone = _fillIsNone;
      _strokeFollowsFill = _fillColor == null && !_fillIsNone;
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
    _fontFollowsStroke = false;
    _fontFollowsFill = false;
    if (token.isEmpty || lower == 'default' || lower == 'none') {
      _fontColor = lower == 'default' ? _kMxDefaultFontColor : null;
      return;
    }
    if (lower == 'font') {
      // mxStencil.parseColor('font') is STYLE_FONTCOLOR, default black.
      _fontColor = _kMxDefaultFontColor;
      return;
    }
    if (lower == 'fill' || token == 'fillColor') {
      _fontColor = _fillColor;
      _fontFollowsFill = _fillColor == null && !_fillIsNone;
      return;
    }
    if (lower == 'stroke' || token == 'strokeColor') {
      // parseColor('stroke') / getColorValue('strokeColor') is
      // shape.stroke / STYLE_STROKECOLOR (iOS 7 Calendar2).
      _fontColor = _strokeColor;
      _fontFollowsStroke = _strokeColor == null && !_strokeIsNone;
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
    _fontBgFollowsStroke = false;
    _fontBgFollowsFill = false;
    if (token.isEmpty || lower == 'default' || lower == 'none') {
      _fontBackground = null;
      return;
    }
    if (lower == 'font') {
      // mxStencil.parseColor('font') is STYLE_FONTCOLOR, default black.
      _fontBackground = _kMxDefaultFontColor;
      return;
    }
    if (lower == 'fill' || token == 'fillColor') {
      _fontBackground = _fillColor;
      _fontBgFollowsFill = _fillColor == null && !_fillIsNone;
      return;
    }
    if (lower == 'stroke' || token == 'strokeColor') {
      // parseColor('stroke') / getColorValue('strokeColor') is
      // shape.stroke / STYLE_STROKECOLOR. leftover inherit TextBkgnd
      // must follow palette LineColor (tokens.txt TextBkgnd).
      _fontBackground = _strokeColor;
      _fontBgFollowsStroke = _strokeColor == null && !_strokeIsNone;
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
    _fontBorderFollowsStroke = false;
    _fontBorderFollowsFill = false;
    if (token.isEmpty || lower == 'default' || lower == 'none') {
      _fontBorder = null;
      return;
    }
    if (lower == 'font') {
      _fontBorder = _kMxDefaultFontColor;
      return;
    }
    if (lower == 'fill' || token == 'fillColor') {
      _fontBorder = _fillColor;
      _fontBorderFollowsFill = _fillColor == null && !_fillIsNone;
      return;
    }
    if (lower == 'stroke' || token == 'strokeColor') {
      // parseColor('stroke') / getColorValue('strokeColor') is
      // shape.stroke / STYLE_STROKECOLOR. leftover inherit label
      // border must follow palette LineColor (tokens.txt has no
      // label border; leftover write bakes a NoFill sibling).
      _fontBorder = _strokeColor;
      _fontBorderFollowsStroke = _strokeColor == null && !_strokeIsNone;
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
  /// `str=` label stays a single collectCharIX run unless
  /// `format="html"` — mxXmlCanvas2D.text then stores markup in `str`.
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
    final str = node.getAttribute('str') ?? '';
    if ((node.getAttribute('format') ?? '').trim().toLowerCase() == 'html') {
      return _bakeDrawioLabelRuns(
        _parseMxHtmlLabel(str, textOpacity: parentOpacity),
      );
    }
    final baked = textForLibvisioWrite(str);
    if (baked.isEmpty) return const <_DrawioStencilLabelRun>[];
    return <_DrawioStencilLabelRun>[
      _DrawioStencilLabelRun(
        text: baked,
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

  /// mxXmlCanvas2D.text format='html' / NestedStencil parseHtmlLabel.
  /// `<b>`/`<font>`/`<ul>` become extra collectCharIX / collectParaIX
  /// rows. `tokens.txt` Character is collectText — leftover must not
  /// leave markup in `str`.
  List<_DrawioStencilLabelRun> _parseMxHtmlLabel(
    String html, {
    required double textOpacity,
  }) {
    final stack = <_MxHtmlStyle>[
      _MxHtmlStyle(
        fontStyle: _fontStyle,
        fontColor: _fontColor,
        fontSize: _fontSize,
        fontFamily: _fontFamily,
        textOpacity: textOpacity,
      ),
    ];
    final runs = <_DrawioStencilLabelRun>[];
    var pendingBlockMarginAfter = 0.0;
    _MxHtmlStyle current() => stack.last;

    void pushRun(String text) {
      if (text.isEmpty) return;
      final style = current();
      if (style.olNeedPrefix && style.olIndex > 0 && text != '\n') {
        text = '${style.olIndex}. $text';
        style.olNeedPrefix = false;
      }
      final emit = style.clone();
      emit.olNeedPrefix = false;
      if (!style.paraStart) emit.marginTop = 0;
      emit.marginBottom = 0;
      if (text == '\n') {
        emit.marginTop = 0;
        emit.marginBottom = 0;
      }
      if (runs.isNotEmpty && emit.samePaintAs(runs.last)) {
        final last = runs.removeLast();
        runs.add(last.withText('${last.text}$text'));
      } else {
        runs.add(emit.toRun(text));
      }
      for (final frame in stack) {
        frame.paraStart = false;
      }
    }

    final tokenRe = RegExp(
      r'<!--[\s\S]*?-->|(?<!<)<(/)?([a-zA-Z][a-zA-Z0-9]*)([^>]*)>|([^<]+|<)',
    );
    for (final match in tokenRe.allMatches(html)) {
      final token = match.group(0)!;
      if (token.startsWith('<!--')) continue;
      final textToken = match.group(4);
      if (textToken != null) {
        pushRun(
          _mxHtmlCollapseWhitespace(_mxHtmlDecodeEntities(textToken)),
        );
        continue;
      }
      final tag = match.group(2)!.toLowerCase();
      final attrs = match.group(3) ?? '';
      final closing =
          match.group(1) != null || RegExp(r'/\s*$').hasMatch(attrs);
      final block = tag == 'p' ||
          tag == 'div' ||
          tag == 'tr' ||
          tag == 'li' ||
          RegExp(r'^h[1-6]$').hasMatch(tag);
      if (tag == 'br' || tag == 'hr') {
        pushRun('\n');
        continue;
      }
      if (match.group(1) != null) {
        if (block && runs.isNotEmpty) {
          pendingBlockMarginAfter = current().marginBottom;
          if (!runs.last.text.endsWith('\n')) {
            pushRun('\n');
          }
        }
        if (stack.length > 1) stack.removeLast();
        continue;
      }
      if (closing) continue;
      final next = current().clone();
      if (block && runs.isNotEmpty && !runs.last.text.endsWith('\n')) {
        pushRun('\n');
      }
      if (tag == 'b' || tag == 'strong') {
        next.fontStyle |= 1;
      } else if (tag == 'i' || tag == 'em') {
        next.fontStyle |= 2;
      } else if (tag == 'u') {
        next.fontStyle |= 4;
      } else if (tag == 's' || tag == 'strike' || tag == 'del') {
        next.fontStyle |= 8;
      } else if (tag == 'sup') {
        next.position = 1;
      } else if (tag == 'sub') {
        next.position = 2;
      } else if (tag == 'ul') {
        next.listKind = 'ul';
        next.bullet = 1;
        next.listPad += _kMxHtmlListPadPx;
        next.olIndex = 0;
        next.olNeedPrefix = false;
      } else if (tag == 'ol') {
        next.listKind = 'ol';
        next.bullet = 0;
        next.listPad += _kMxHtmlListPadPx;
        next.olIndex = 0;
        next.olNeedPrefix = false;
      } else if (tag == 'li') {
        if (next.listKind == 'ol') {
          final parent = current();
          parent.olIndex += 1;
          next.olIndex = parent.olIndex;
          next.olNeedPrefix = true;
          next.bullet = 0;
          next.marginLeft +=
              next.listPad > 0 ? next.listPad : _kMxHtmlListPadPx;
        } else if (next.listKind == 'ul') {
          next.bullet = 1;
          next.textPosAfterBullet =
              next.listPad > 0 ? next.listPad : _kMxHtmlListPadPx;
          next.olNeedPrefix = false;
        }
      }
      _mxHtmlApplyCss(next, attrs, tag, resolveColor: _mxRunFontColor);
      if (block && pendingBlockMarginAfter != 0) {
        next.marginTop = math.max(next.marginTop, pendingBlockMarginAfter);
        pendingBlockMarginAfter = 0;
      }
      stack.add(next);
    }
    if (pendingBlockMarginAfter != 0) {
      for (var i = runs.length - 1; i >= 0; i--) {
        if (runs[i].text != '\n') {
          runs[i] = runs[i].withMargins(marginBottom: pendingBlockMarginAfter);
          break;
        }
      }
    }
    while (runs.isNotEmpty) {
      final last = runs.last;
      if (last.text == '\n') {
        runs.removeLast();
        continue;
      }
      if (last.text.endsWith('\n')) {
        final trimmed = last.text.replaceFirst(RegExp(r'\n+$'), '');
        if (trimmed.isEmpty) {
          runs.removeLast();
          continue;
        }
        runs[runs.length - 1] = last.withText(trimmed);
      }
      break;
    }
    return List<_DrawioStencilLabelRun>.unmodifiable(runs);
  }

  /// mxShape.configureCanvas setShadow + mxSvgCanvas2D.createShadow.
  /// dx/dy are mxGraph pixels (Y down). Visio ShapeShdwOffsetY is up;
  /// libvisio `_fillAndShadowProperties` emits ODF offset-y as −Y.
  void _applyMxShadow(XmlElement node) {
    // mxXmlCanvas2D.setShadow writes enabled 1 or 0. NestedStencil
    // setShadow is `enabled === true || === 1 || === '1'`. leftover
    // treated omitted as on, so Draw collectFillAndShadow offset a
    // rail mxSvgCanvas2D.createShadow never painted (`tokens.txt`
    // ShdwPattern → draw:shadow).
    if (node.getAttribute('enabled') != '1') {
      _shadow = null;
      return;
    }
    final colorAttr = node.getAttribute('color');
    if (colorAttr != null) _applyMxShadowColor(colorAttr, rebuild: false);
    final dxAttr = node.getAttribute('dx');
    final dyAttr = node.getAttribute('dy');
    if (dxAttr != null || dyAttr != null) {
      _applyMxShadowOffset(dxAttr, dyAttr, rebuild: false);
    }
    final alphaAttr = node.getAttribute('alpha');
    if (alphaAttr != null) _applyMxShadowAlpha(alphaAttr, rebuild: false);
    _shadow = _shadowFromCanvas();
  }

  void _applyMxShadowColor(String? raw, {bool rebuild = true}) {
    final token = (raw ?? '').trim();
    final lower = token.toLowerCase();
    if (token.isEmpty || lower == 'default' || lower == 'none') {
      _shadowColor = _kMxDefaultShadowColor;
    } else {
      _shadowColor = _mxGraphPaintColor(token) ?? _kMxDefaultShadowColor;
    }
    if (rebuild) _rebuildEnabledShadow();
  }

  void _applyMxShadowAlpha(String? raw, {bool rebuild = true}) {
    final token = (raw ?? '').trim();
    if (token.isEmpty) {
      // NestedStencil Number(null)=0; mxSvgCanvas2D.createShadow
      // opacity is then 0. leftover default 1 painted an opaque
      // collectFillAndShadow rail (`tokens.txt` has no
      // ShdwForegndTrans).
      _shadowAlpha = 0;
    } else {
      final parsed = double.tryParse(token);
      _shadowAlpha = (parsed == null || !parsed.isFinite)
          ? _kMxDefaultShadowAlpha
          : parsed.clamp(0.0, 1.0).toDouble();
    }
    if (rebuild) _rebuildEnabledShadow();
  }

  void _applyMxShadowOffset(
    String? dxRaw,
    String? dyRaw, {
    bool rebuild = true,
    bool snapOmittedToZero = false,
  }) {
    final dx = double.tryParse((dxRaw ?? '').trim());
    final dy = double.tryParse((dyRaw ?? '').trim());
    if (dx != null && dx.isFinite) {
      _shadowDx = dx;
    } else if (snapOmittedToZero && (dxRaw == null || dxRaw.trim().isEmpty)) {
      // NestedStencil Number(null)=0; Number('foo') is NaN keep.
      _shadowDx = 0;
    }
    if (dy != null && dy.isFinite) {
      _shadowDy = dy;
    } else if (snapOmittedToZero && (dyRaw == null || dyRaw.trim().isEmpty)) {
      _shadowDy = 0;
    }
    if (rebuild) _rebuildEnabledShadow();
  }

  void _rebuildEnabledShadow() {
    if (_shadow == null) return;
    _shadow = _shadowFromCanvas();
  }

  void _applyMxCanvasScale(double value) {
    // mxAbstractCanvas2D.scale is `state.scale *= value`. 0 collapses
    // addOp vertices; negative mirrors `(x+dx)*scale`. leftover
    // `value < 0` skipped the multiply, so Draw collectGeometry kept
    // the unflipped leftover inches (`tokens.txt` PinX / Width).
    // LineWeight / Char.Size / ImgWidth still use abs so
    // `max(0.001, negative)` does not hairline (`tokens.txt`
    // LineWeight / Size).
    if (!value.isFinite) return;
    _canvasUserScale *= value;
    if (_shadow != null) _rebuildEnabledShadow();
  }

  void _applyMxCanvasRotate(XmlElement node) {
    final theta = _number(node, 'theta');
    final flipH = node.getAttribute('flipH') == '1';
    final flipV = node.getAttribute('flipV') == '1';
    if (theta.abs() < 1e-12 && !flipH && !flipV) return;
    // mxSvgCanvas2D.rotate: cx += dx; cy += dy; cx *= scale. leftover
    // stores that centre in leftover inches so include-shape nested
    // overlay (already leftover inches) can reuse it.
    final centre = _leftoverUnrotated(
      _number(node, 'cx'),
      _number(node, 'cy'),
    );
    _rotThetaDeg = theta;
    _rotFlipH = flipH;
    _rotFlipV = flipV;
    _rotCxLeftover = centre.x;
    _rotCyLeftover = centre.y;
  }

  bool get _hasCanvasRotate =>
      _rotThetaDeg.abs() > 1e-9 || _rotFlipH || _rotFlipV;

  /// mxSvgCanvas2D.rotate effective theta, as Visio CCW radians.
  /// SVG +theta is clockwise Y-down; leftover TxtAngle / Angle are
  /// Y-up (`tokens.txt` TxtAngle / Angle → librevenge:rotate).
  /// `scale *= -1` is SVG scale(-1,-1) ≡ 180°; leftover Path vertices
  /// already *(userScale), but ForeignData / glyphs still need Angle
  /// so Draw transformAngle stands them up.
  double get _canvasLeftoverRotationRad {
    var rad = 0.0;
    if (_hasCanvasRotate) {
      var theta = _rotThetaDeg;
      if (_rotFlipH && _rotFlipV) theta += 180;
      if (_rotFlipH ? !_rotFlipV : _rotFlipV) theta = -theta;
      rad = -theta * math.pi / 180;
    }
    if (scaleX * _canvasUserScale < 0 && scaleY * _canvasUserScale < 0) {
      rad += math.pi;
    }
    return rad;
  }

  bool get _canvasXorFlipX => _rotFlipH && !_rotFlipV;
  bool get _canvasXorFlipY => _rotFlipV && !_rotFlipH;

  VsdxShadow _shadowFromCanvas() {
    // mxSvgCanvas2D.createShadow opacity is shadowAlpha. Number(null)=0
    // is invisible. `tokens.txt` has no ShdwForegndTrans, so leftover
    // turns ShdwPattern 0 instead of premultiplying RGB to white that
    // Draw still paints as draw:shadow (`tokens.txt` ShdwPattern).
    if (_shadowAlpha <= 1e-9) return VsdxShadow.disabled;
    var offsetX = _shadowDx * scaleX * _canvasUserScale;
    var offsetY = -_shadowDy * scaleY * _canvasUserScale;
    if (offsetX.abs() < 1e-9) offsetX = 0.02;
    if (offsetY.abs() < 1e-9) offsetY = -0.03;
    return VsdxShadow(
      enabled: true,
      pattern: 1,
      color: _shadowColor,
      offsetXInches: offsetX,
      offsetYInches: offsetY,
      blurInches: 0,
      transparency: (1 - _shadowAlpha).clamp(0.0, 1.0),
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
    // mxSvgCanvas2D.getCurrentStrokeWidth:
    // `max(minStrokeWidth=1, max(0.01, format(width * state.scale)))`.
    // leftover `width > 0` skipped 0, so Draw collectLine kept the
    // previous leftover inches (`tokens.txt` LineWeight). A zero
    // canvas width is one stencil pixel, same as width=1 after the
    // minStrokeWidth floor (state.scale is leftover `_canvasUserScale`).
    final scale = (_strokeWidthFixed
            ? _canvasScale
            : math.min(scaleX.abs(), scaleY.abs())) *
        _canvasUserScale.abs();
    final canvas = width <= 0 ? 1.0 : width;
    return math.max(0.001, canvas * scale);
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
    // mx createState lineCap is flat. VsdxLine.defaultLine is Visio
    // factory round; a null canvas cap must not leak LineCap 0 into
    // collectLine (`tokens.txt` LineCap → svg:stroke-linecap=round).
    line = line.copyWith(
      cap: _lineCap ?? LineCap.extended,
      join: _lineJoin ?? VsdxLineJoin.miter,
    );
    if (_miterLimit != null) {
      line = line.copyWith(miterLimit: _miterLimit);
    }
    if (_dashed) {
      line = _lineWithDash(line, _dashPattern);
    }
    return line;
  }

  List<double>? _fixedDashPatternValues([List<double>? raw, bool? fixDash]) {
    // mxAbstractCanvas2D.createState dashPattern is '3 3'. A dashed
    // stroke with no <dashpattern> (AWS 3D Dashed Edge, Cisco Metro
    // 1500) must not fall through to Visio LinePattern 2 (6×/3×
    // LineWeight) — libvisio `_lineProperties` case 2 would paint
    // weight-scaled dashes that look solid on a short rail.
    final source = raw ?? _dashPattern ?? _kMxDefaultDashPattern;
    if (source.isEmpty) return null;
    final scale = math.min(scaleX.abs(), scaleY.abs()) * _canvasUserScale.abs();
    // mxSvgCanvas2D.createDashPattern: `(fixDash ? 1 : strokeWidth)*scale`.
    // leftover tessellates those leftover inches (`tokens.txt` has no
    // fixDash). Omitted `<dashed>` fixDash is createState false so
    // later inherit stroke × LineWeight instead of the first
    // canvas-pixel gaps.
    final fixed = fixDash ?? _fixDash;
    final strokeMul = fixed ? 1.0 : math.max(_strokeWidth ?? 1.0, 1e-9);
    final values = <double>[
      for (final value in source)
        if (value > 0) value * scale * strokeMul / drawioDashUnitInches,
    ];
    return values.length >= 2 ? values : null;
  }

  VsdxLine _lineWithDash(
    VsdxLine line,
    List<double>? pattern, {
    bool? fixDash,
  }) {
    // Explicit `<dashpattern pattern="none"/>` (empty list) is solid.
    // Missing pattern stays mx createState `3 3`.
    if (pattern != null && pattern.isEmpty) {
      return line.copyWith(
        pattern: line.pattern == 0 ? 0 : 1,
        customDashPattern: null,
        fixedDash: false,
      );
    }
    final custom = _fixedDashPatternValues(pattern, fixDash);
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
        fillFromStroke:
            _fillFollowsStroke && fill.hasFill && fill.foreground == null,
        strokeFromFill: _strokeFollowsFill &&
            doStroke &&
            _strokeColor == null &&
            !_strokeIsNone,
      ));
      if (!_capturedParentShadow && _shadow != null) {
        _parentShadow ??= _shadow;
      }
      return;
    }
    // collectFill is shape-level. A later `<fillcolor color="stroke"/>`
    // / `color="strokeColor"` (or include-shape nested setFillColor)
    // must be a sibling so `_fillAndShadowProperties` can emit both
    // FillForegnd values. leftover used to concatenate onto the parent,
    // then applyStencilStyle washed both rails with palette fill
    // (`tokens.txt` FillForegnd → svg:fill). Hex fillcolor already
    // bakes because `_fillColor != null`. `strokeColor` is
    // getColorValue STYLE_STROKECOLOR (iOS 7 Location 22).
    final bakeFill = doFill &&
        (_fillColor != null ||
            (_capturedParentFill &&
                _fillFollowsStroke != _parentFillFollowsStroke));
    final bakeStroke = doStroke && _strokeColor != null && !doFill;
    // collectLine is shape-level. A later hex `<strokecolor>` on a
    // fillstroke (doFill blocks bakeStroke) must still be a sibling so
    // `_lineProperties` can emit both LineColors. leftover used to
    // concatenate onto the parent, then build() restored the first
    // inherit LineColor (`tokens.txt` LineColor → svg:stroke-color).
    // `strokecolor color="fill"` is the same freeze: inherit LineColor
    // vs inherit FillForegnd are different leftover colours.
    final bakeStrokeColor = doStroke &&
        _capturedParentStrokeColor &&
        (_strokeColor != _parentStrokeColor ||
            _strokeFollowsFill != _parentStrokeFollowsFill);
    // libvisio collectLine is shape-level. A dash after a solid paint
    // (EIP Detour diagonal) must be a sibling. A shape that is dashed
    // from the first paint (Availability Zone, Dashed Wire) keeps
    // LinePattern on the parent so applyStencilStyle can still recolor it.
    final bakeDash = doStroke && _dashed && _solidPaintBeforeDash;
    // The inverse: later `<dashed dashed="0"/>` or a later `<dashpattern>`
    // on an inherit stroke. leftover used to concatenate onto the parent,
    // so Draw `_lineProperties` (and leftover MoveTo gaps) dashed the
    // later rail with the first collectLine pattern (`tokens.txt` has
    // LinePattern but 0xfe custom arrays paint solid).
    final bakeDashState = doStroke &&
        _capturedParentDashState &&
        (_dashed != _parentDashed ||
            (_dashed &&
                (!_dashPatternsEqual(
                      _dashPattern ?? _kMxDefaultDashPattern,
                      _parentDashPattern,
                    ) ||
                    _fixDash != _parentFixDash)));
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
    // collectGeometry is shape-level. A later `<scale scale="-1"/>`
    // (or include-shape nested scale that stays on the shared canvas)
    // must be a sibling so Draw does not concatenate the mirrored rail
    // onto the first leftover inches (`tokens.txt` PinX / Width).
    // LineWeight uses abs so bakeWeight does not fire for ±1.
    final bakeUserScale = (doFill || doStroke) &&
        _capturedParentUserScale &&
        _parentCanvasUserScale != null &&
        (_canvasUserScale - _parentCanvasUserScale!).abs() > 1e-12;
    // collectLine is shape-level. A later `<strokealpha>` (or include-shape
    // nested setStrokeAlpha that stays on the shared canvas) must be a
    // sibling so leftover can ribbon only the faded rail. `tokens.txt`
    // has no LineColorTrans; `xmlStringToColour` zeros Colour.a, so
    // `_lineProperties` always emits svg:stroke-opacity=1. leftover used
    // to concatenate onto the parent, so the later opaque rail vanished
    // into the same FillForegndTrans ribbon.
    final bakeStrokeTrans = doStroke &&
        _parentStrokeTransparency != null &&
        (_strokeTransparency - _parentStrokeTransparency!).abs() > 1e-6;
    // collectFillAndShadow is shape-level. A later `<shadow>` (or
    // include-shape nested setShadow that stays on the shared canvas)
    // must be a sibling so `_fillAndShadowProperties` can emit both
    // ShdwPattern values. leftover used to concatenate onto the parent,
    // so Draw painted `draw:shadow` on the first rail too (`tokens.txt`
    // ShdwPattern / ShdwOffsetX / ShdwOffsetY).
    final bakeShadow = (doFill || doStroke) &&
        _capturedParentShadow &&
        !_shadowsEqual(_shadow, _parentShadow);
    // collectFillAndShadow is shape-level. A later `<sketch>` (or
    // include-shape nested setSketch that stays on the shared canvas)
    // must be a sibling so leftover can hatch only that rail.
    // `User.veSketch*` is not a token; leftover write maps hachure onto
    // FillPattern 2–24 (`draw:fill=hatch`). leftover used to concatenate
    // onto the parent, so Draw hatched the first rail too.
    final bakeSketch = (doFill || doStroke) &&
        _capturedParentSketch &&
        !_sketchesEqual(_currentSketch, _parentSketch);
    final inheritFillSibling = extraInheritFill ||
        ((bakeLineStyle ||
                bakeWeight ||
                bakeUserScale ||
                bakeDashState ||
                bakeStrokeTrans ||
                bakeShadow ||
                bakeSketch ||
                bakeStrokeColor) &&
            doFill &&
            !bakeFill);
    if (bakeFill ||
        bakeStroke ||
        bakeDash ||
        bakeDashState ||
        extraInheritFill ||
        bakeLineStyle ||
        bakeWeight ||
        bakeUserScale ||
        bakeStrokeTrans ||
        bakeShadow ||
        bakeSketch ||
        bakeStrokeColor) {
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
        fillFromStroke:
            _fillFollowsStroke && doFill && _fillColor == null && !_fillIsNone,
        strokeFromFill: _strokeFollowsFill &&
            doStroke &&
            _strokeColor == null &&
            !_strokeIsNone,
      ));
      if (!_capturedParentShadow && _shadow != null) {
        _parentShadow ??= _shadow;
      }
      return;
    }
    _geometries.add(VsdxGeometry(
      commands: List<VsdxPathCommand>.unmodifiable(commands),
      noFill: !doFill,
      noLine: !doStroke,
      ix: _geometries.length,
    ));
    if (doFill && !_capturedParentFill) {
      // First inherit fill owns collectFill. Later `<fillcolor color="stroke"/>`
      // (Networks2 antenna, PID Blank2) belongs on a sibling so Draw can
      // emit both FillForegnd values (`tokens.txt`).
      _capturedParentFill = true;
      _parentFillFollowsStroke = _fillFollowsStroke;
    }
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
      _parentStrokeFollowsFill = _strokeFollowsFill;
    }
    if (doStroke && !_capturedParentDashState) {
      // First inherit stroke owns collectLine dash. Later `<dashed>` /
      // `<dashpattern>` belong on siblings so Draw can emit both.
      _capturedParentDashState = true;
      _parentDashed = _dashed;
      _parentFixDash = _fixDash;
      if (_dashed) {
        _parentDashPattern = _dashPattern ?? _kMxDefaultDashPattern;
      }
    }
    if (doStroke && _strokeWidth != null) {
      _parentStrokeWeightInches ??= _strokeWeightInches;
    }
    if ((doFill || doStroke) && !_capturedParentUserScale) {
      _capturedParentUserScale = true;
      _parentCanvasUserScale = _canvasUserScale;
    }
    if (!_capturedParentShadow && (doFill || doStroke)) {
      // First inherit paint owns collectFillAndShadow. Later `<shadow>`
      // / `<shadowcolor>` / `<shadowoffset>` / `<shadowalpha>` belong
      // on siblings so Draw can emit both ShdwForegnd / ShdwOffset*
      // values (`tokens.txt`).
      _capturedParentShadow = true;
      _parentShadow = _shadow;
    }
    if (!_capturedParentSketch && (doFill || doStroke)) {
      // First inherit paint owns collectFill FillPattern. Later `<sketch>`
      // belongs on siblings so leftover can hatch only that rail.
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
            for (final point in pts)
              (x: _x(point.x, point.y), y: _y(point.x, point.y)),
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
        commands.add(MoveTo(_x(_penX, _penY), _y(_penX, _penY)));
        break;
      case 'line':
        _penX = _number(command, 'x');
        _penY = _number(command, 'y');
        commands.add(LineTo(_x(_penX, _penY), _y(_penX, _penY)));
        break;
      case 'curve':
        final x1 = _number(command, 'x1');
        final y1 = _number(command, 'y1');
        final x2 = _number(command, 'x2');
        final y2 = _number(command, 'y2');
        _penX = _number(command, 'x3');
        _penY = _number(command, 'y3');
        commands.add(CubBezTo(
          x: _x(_penX, _penY),
          y: _y(_penX, _penY),
          x1: _x(x1, y1),
          y1: _y(x1, y1),
          x2: _x(x2, y2),
          y2: _y(x2, y2),
        ));
        break;
      case 'quad':
        final x1 = _number(command, 'x1');
        final y1 = _number(command, 'y1');
        _penX = _number(command, 'x2');
        _penY = _number(command, 'y2');
        commands.add(QuadBezTo(
          x: _x(_penX, _penY),
          y: _y(_penX, _penY),
          x1: _x(x1, y1),
          y1: _y(x1, y1),
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
        final startLX = _x(_penX, _penY);
        final startLY = _y(_penX, _penY);
        final endLX = _x(endX, endY);
        final endLY = _y(endX, endY);
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
          commands.add(LineTo(_x(_subX, _subY), _y(_subX, _subY)));
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
      MoveTo(_x(left, top), _y(left, top)),
      LineTo(_x(right, top), _y(right, top)),
      LineTo(_x(right, bottom), _y(right, bottom)),
      LineTo(_x(left, bottom), _y(left, bottom)),
      LineTo(_x(left, top), _y(left, top)),
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
    final dxRaw = rect.getAttribute('dx');
    final dyRaw = rect.getAttribute('dy');
    if (dxRaw != null || dyRaw != null) {
      // mxXmlCanvas2D.roundrect. mxSvgCanvas2D.roundrect sets rx/ry
      // only when dx/dy > 0. leftover used to ignore the attrs and
      // default arcsize 15, so Draw collectGeometry rounded a sharp
      // canvas roundrect (`tokens.txt` CubBezTo → RelCubBezTo).
      var radiusX = double.tryParse(dxRaw ?? '') ?? 0.0;
      var radiusY = double.tryParse(dyRaw ?? '') ?? radiusX;
      if (!radiusX.isFinite) radiusX = 0;
      if (!radiusY.isFinite) radiusY = 0;
      if (!(radiusX > 0) && !(radiusY > 0)) {
        return _decodeRect(rect);
      }
      return _roundRectCubics(
        left: left,
        top: top,
        width: width,
        height: height,
        radiusX: radiusX.clamp(0.0, width / 2),
        radiusY: radiusY.clamp(0.0, height / 2),
      );
    }
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
    return _roundRectCubics(
      left: left,
      top: top,
      width: width,
      height: height,
      radiusX: radiusX,
      radiusY: radiusY,
    );
  }

  List<VsdxPathCommand> _roundRectCubics({
    required double left,
    required double top,
    required double width,
    required double height,
    required double radiusX,
    required double radiusY,
  }) {
    final right = left + width;
    final bottom = top + height;
    const kappa = 0.5522847498307936;
    final kX = radiusX * kappa;
    final kY = radiusY * kappa;
    return <VsdxPathCommand>[
      MoveTo(_x(left + radiusX, top), _y(left + radiusX, top)),
      LineTo(_x(right - radiusX, top), _y(right - radiusX, top)),
      CubBezTo(
        x: _x(right, top + radiusY),
        y: _y(right, top + radiusY),
        x1: _x(right - radiusX + kX, top),
        y1: _y(right - radiusX + kX, top),
        x2: _x(right, top + radiusY - kY),
        y2: _y(right, top + radiusY - kY),
      ),
      LineTo(_x(right, bottom - radiusY), _y(right, bottom - radiusY)),
      CubBezTo(
        x: _x(right - radiusX, bottom),
        y: _y(right - radiusX, bottom),
        x1: _x(right, bottom - radiusY + kY),
        y1: _y(right, bottom - radiusY + kY),
        x2: _x(right - radiusX + kX, bottom),
        y2: _y(right - radiusX + kX, bottom),
      ),
      LineTo(_x(left + radiusX, bottom), _y(left + radiusX, bottom)),
      CubBezTo(
        x: _x(left, bottom - radiusY),
        y: _y(left, bottom - radiusY),
        x1: _x(left + radiusX - kX, bottom),
        y1: _y(left + radiusX - kX, bottom),
        x2: _x(left, bottom - radiusY + kY),
        y2: _y(left, bottom - radiusY + kY),
      ),
      LineTo(_x(left, top + radiusY), _y(left, top + radiusY)),
      CubBezTo(
        x: _x(left + radiusX, top),
        y: _y(left + radiusX, top),
        x1: _x(left, top + radiusY - kY),
        y1: _y(left, top + radiusY - kY),
        x2: _x(left + radiusX - kX, top),
        y2: _y(left + radiusX - kX, top),
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
    final cx = _x(cxSrc, cySrc);
    final cy = _y(cxSrc, cySrc);
    // mxStencil.drawNode canvas.ellipse(w*sx, h*sy). leftover A/B
    // vertices follow independent `_x`/`_y` so collectEllipse rx/ry
    // match the include box. A min(scaleX,scaleY) circle used to hide
    // that stretch (and was a no-op on catalog leftover, where scale
    // is already uniform from the long side).
    return <VsdxPathCommand>[
      EllipseCmd(
        cx: cx,
        cy: cy,
        aX: _x(left + width, cySrc),
        aY: _y(left + width, cySrc),
        bX: _x(cxSrc, top),
        bY: _y(cxSrc, top),
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
        pinXInches:
            _x(_number(node, 'x') + boxW / 2, _number(node, 'y') + boxH / 2),
        pinYInches:
            _y(_number(node, 'x') + boxW / 2, _number(node, 'y') + boxH / 2),
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
      angleRad: raster.leftoverAngleRad,
      flipX: raster.flipH != raster.leftoverCanvasFlipX,
      flipY: raster.flipV != raster.leftoverCanvasFlipY,
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
      imageTransparency: raster.leftoverTransparency,
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
    return _withMxColorSourceUserCells(
      _withSketchUserCells(
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
      ),
      fillFromStroke: part.fillFromStroke,
      strokeFromFill: part.strokeFromFill,
    );
  }

  VsdxShape _withMxColorSourceUserCells(
    VsdxShape shape, {
    required bool fillFromStroke,
    required bool strokeFromFill,
    bool fontFromStroke = false,
    bool fontFromFill = false,
    bool fontBgFromStroke = false,
    bool fontBgFromFill = false,
    bool fontBorderFromStroke = false,
    bool fontBorderFromFill = false,
  }) {
    if (!fillFromStroke &&
        !strokeFromFill &&
        !fontFromStroke &&
        !fontFromFill &&
        !fontBgFromStroke &&
        !fontBgFromFill &&
        !fontBorderFromStroke &&
        !fontBorderFromFill) {
      return shape;
    }
    return shape.copyWith(
      userCells: <VsdxUserCell>[
        ...shape.userCells,
        if (fillFromStroke)
          const VsdxUserCell(name: VsdxShape.userMxFillFromStroke, value: '1'),
        if (strokeFromFill)
          const VsdxUserCell(name: VsdxShape.userMxStrokeFromFill, value: '1'),
        if (fontFromStroke)
          const VsdxUserCell(name: VsdxShape.userMxFontFromStroke, value: '1'),
        if (fontFromFill)
          const VsdxUserCell(name: VsdxShape.userMxFontFromFill, value: '1'),
        if (fontBgFromStroke)
          const VsdxUserCell(
            name: VsdxShape.userMxFontBgFromStroke,
            value: '1',
          ),
        if (fontBgFromFill)
          const VsdxUserCell(name: VsdxShape.userMxFontBgFromFill, value: '1'),
        if (fontBorderFromStroke)
          const VsdxUserCell(
            name: VsdxShape.userMxFontBorderFromStroke,
            value: '1',
          ),
        if (fontBorderFromFill)
          const VsdxUserCell(
            name: VsdxShape.userMxFontBorderFromFill,
            value: '1',
          ),
      ],
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

  /// mxSvgCanvas2D.text uses `state.rotation + text.rotation`. leftover
  /// snapshots leftover-inch Pin / TxtAngle at emit so a later
  /// `<rotate>` cannot drag earlier glyphs (`tokens.txt` TxtAngle).
  _DrawioStencilLabel _snapshotLabelCanvas(_DrawioStencilLabel label) {
    final scaleXAbs = scaleX.abs() * _canvasUserScale.abs();
    final scaleYAbs = scaleY.abs() * _canvasUserScale.abs();
    final layout = _labelLeftoverLayout(
      label,
      scaleXAbs: scaleXAbs,
      scaleYAbs: scaleYAbs,
    );
    return label.copyWith(
      leftoverPinX: layout.pinX,
      leftoverPinY: layout.pinY,
      leftoverAngleRad: layout.angle,
      leftoverScaleX: scaleXAbs,
      leftoverScaleY: scaleYAbs,
    );
  }

  ({double pinX, double pinY, double width, double height, double angle})
      _labelLeftoverLayout(
    _DrawioStencilLabel label, {
    required double scaleXAbs,
    required double scaleYAbs,
  }) {
    final scale = math.min(scaleXAbs, scaleYAbs);
    final fontInches = math.max(_kMxMinCharSizeInches, label.fontSize * scale);
    final hasBox = label.boxWidth > 0 && label.boxHeight > 0;
    final width = hasBox
        ? math.max(label.boxWidth * scaleXAbs, fontInches * 0.5)
        : math.max(fontInches * 1.2, label.text.length * fontInches * 0.62);
    final height = hasBox
        ? math.max(label.boxHeight * scaleYAbs, fontInches * 0.5)
        : fontInches * 1.4;
    late final double pinX;
    late final double pinY;
    if (hasBox) {
      pinX = _x(label.x + label.boxWidth / 2, label.y + label.boxHeight / 2);
      pinY = _y(label.x + label.boxWidth / 2, label.y + label.boxHeight / 2);
    } else {
      final x = _x(label.x, label.y);
      final y = _y(label.x, label.y);
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
    var angle = -label.rotationDegrees * math.pi / 180;
    if (label.vertical && !hasBox) angle -= math.pi / 2;
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
    angle += _canvasLeftoverRotationRad;
    return (
      pinX: pinX,
      pinY: pinY,
      width: width,
      height: height,
      angle: angle,
    );
  }

  VsdxShape _labelShape({
    required int id,
    required _DrawioStencilLabel label,
  }) {
    final scaleXAbs =
        label.leftoverScaleX ?? (scaleX.abs() * _canvasUserScale.abs());
    final scaleYAbs =
        label.leftoverScaleY ?? (scaleY.abs() * _canvasUserScale.abs());
    final scale = math.min(scaleXAbs, scaleYAbs);
    final fontInches = math.max(_kMxMinCharSizeInches, label.fontSize * scale);
    // mxXmlCanvas2D.text w/h is the cell box. Stencil glyphs pass 0 and
    // keep a tight pin; cell values (Ammeter A, Bootstrap Alert) fill
    // the frame collectTextBlock maps to svg:width / fo:padding-*.
    // mxGraphView.updateVertexLabelOffset shifts that box by one cell
    // for labelPosition / verticalLabelPosition, so Pin can sit outside
    // the parent XForm collectXFormData maps to svg:x / svg:y.
    final hasBox = label.boxWidth > 0 && label.boxHeight > 0;
    final width = hasBox
        ? math.max(label.boxWidth * scaleXAbs, fontInches * 0.5)
        : math.max(fontInches * 1.2, label.text.length * fontInches * 0.62);
    final height = hasBox
        ? math.max(label.boxHeight * scaleYAbs, fontInches * 0.5)
        : fontInches * 1.4;
    late final double pinX;
    late final double pinY;
    late final double angle;
    if (label.leftoverPinX != null && label.leftoverPinY != null) {
      pinX = label.leftoverPinX!;
      pinY = label.leftoverPinY!;
      angle = label.leftoverAngleRad;
    } else {
      final layout = _labelLeftoverLayout(
        label,
        scaleXAbs: scaleXAbs,
        scaleYAbs: scaleYAbs,
      );
      pinX = layout.pinX;
      pinY = layout.pinY;
      angle = layout.angle;
    }
    final vert = switch (label.valign) {
      'bottom' => VsdxVertAlign.bottom,
      'middle' => VsdxVertAlign.middle,
      _ => VsdxVertAlign.top,
    };
    // Cell boxes with STYLE_HORIZONTAL=0 use TextDirection=1 so canvas /
    // SVG rotate and libvisio_write can bake TxtAngle for Draw. Stencil
    // glyphs (w=h=0) keep the mxStencil vertical → TxtAngle shortcut.
    final boxedVertical = hasBox && label.vertical;
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
                flags: label.rtl ? 1 : 0,
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
    // mxXmlCanvas2D.text clip / overflow fill|width|block keep the cell
    // box (`mxSvgCanvas2D.plainText` clipPath); leftover must not expand
    // TxtWidth or Draw svg:width overflows the clip frame.
    if (hasBox && !label.wrap && !label.keepsTxtBox) {
      shape = shape.withWordWrap(false);
    }
    if (label.border != null) {
      shape = shape.withLabelBorderColor(label.border);
    }
    return _withMxColorSourceUserCells(
      shape,
      fillFromStroke: false,
      strokeFromFill: false,
      fontFromStroke: label.fontFromStroke && label.color == null,
      fontFromFill: label.fontFromFill && label.color == null,
      fontBgFromStroke: label.fontBgFromStroke && label.background == null,
      fontBgFromFill: label.fontBgFromFill && label.background == null,
      fontBorderFromStroke: label.fontBorderFromStroke && label.border == null,
      fontBorderFromFill: label.fontBorderFromFill && label.border == null,
    );
  }

  ({double x, double y}) _leftoverUnrotated(double sourceX, double sourceY) => (
        x: _originX + (sourceX + _canvasDx) * _canvasUserScale * scaleX,
        y: _originY +
            (sourceHeight - (sourceY + _canvasDy) * _canvasUserScale) * scaleY,
      );

  ({double x, double y}) _leftoverOf(double sourceX, double sourceY) {
    final p = _leftoverUnrotated(sourceX, sourceY);
    if (!_hasCanvasRotate) return p;
    return _mxSvgRotateLeftover(p.x, p.y);
  }

  /// mxSvgCanvas2D.rotate in leftover Y-up. SVG +theta is clockwise in
  /// Y-down, which is clockwise on the page → math −theta in Y-up.
  ({double x, double y}) _mxSvgRotateLeftover(double x, double y) {
    var theta = _rotThetaDeg;
    final cx = _rotCxLeftover;
    final cy = _rotCyLeftover;
    if (_rotFlipH && _rotFlipV) {
      theta += 180;
    } else if (_rotFlipH != _rotFlipV) {
      if (_rotFlipH) x = 2 * cx - x;
      if (_rotFlipV) y = 2 * cy - y;
    }
    if (_rotFlipH ? !_rotFlipV : _rotFlipV) {
      theta = -theta;
    }
    if (theta.abs() < 1e-12) return (x: x, y: y);
    final rad = -theta * math.pi / 180;
    final cos = math.cos(rad);
    final sin = math.sin(rad);
    final dx = x - cx;
    final dy = y - cy;
    return (x: cx + dx * cos - dy * sin, y: cy + dx * sin + dy * cos);
  }

  ({double x, double y}) _unrotateLeftover(double x, double y) {
    if (!_hasCanvasRotate) return (x: x, y: y);
    var theta = _rotThetaDeg;
    final cx = _rotCxLeftover;
    final cy = _rotCyLeftover;
    if (_rotFlipH ? !_rotFlipV : _rotFlipV) {
      theta = -theta;
    }
    if (_rotFlipH && _rotFlipV) {
      theta += 180;
    }
    if (theta.abs() > 1e-12) {
      final rad = theta * math.pi / 180;
      final cos = math.cos(rad);
      final sin = math.sin(rad);
      final dx = x - cx;
      final dy = y - cy;
      x = cx + dx * cos - dy * sin;
      y = cy + dx * sin + dy * cos;
    }
    if (_rotFlipH && !_rotFlipV) x = 2 * cx - x;
    if (_rotFlipV && !_rotFlipH) y = 2 * cy - y;
    return (x: x, y: y);
  }

  double _x(double sourceX, double sourceY) => _leftoverOf(sourceX, sourceY).x;
  double _y(double sourceX, double sourceY) => _leftoverOf(sourceX, sourceY).y;

  ({double x, double y}) _sourceFromLeftover(
      double leftoverX, double leftoverY) {
    final u = _unrotateLeftover(leftoverX, leftoverY);
    return (
      x: _sourceXFromUnrotatedLeftover(u.x),
      y: _sourceYFromUnrotatedLeftover(u.y),
    );
  }

  double _sourceXFromUnrotatedLeftover(double leftoverX) {
    final denom = scaleX * _canvasUserScale;
    if (denom.abs() < 1e-12) return 0;
    return (leftoverX - _originX) / denom - _canvasDx;
  }

  double _sourceYFromUnrotatedLeftover(double leftoverY) {
    if (scaleY.abs() < 1e-12 || _canvasUserScale.abs() < 1e-12) {
      return sourceHeight;
    }
    return (sourceHeight - (leftoverY - _originY) / scaleY) / _canvasUserScale -
        _canvasDy;
  }

  /// Map a nested-stencil-space label into [parent] stencil units so
  /// host `_labelShape` `_x`/`_y` / minScale match NestedStencil
  /// `canvas.text` / `setFontSize(size * minScale)` in the include box.
  /// Nested emit already snapshots leftover-inch Pin / TxtAngle; this
  /// remap is only for labels that missed that snapshot.
  _DrawioStencilLabel _labelInParentStencilSpace(
    _DrawioStencilLabel label, {
    required _DrawioXmlShapeDecoder parent,
  }) {
    final leftover = _leftoverOf(label.x, label.y);
    final parentSrc = parent._sourceFromLeftover(leftover.x, leftover.y);
    final parentX = parentSrc.x;
    final parentY = parentSrc.y;
    final parentScaleX = parent.scaleX;
    final parentScaleY = parent.scaleY;
    final scaleXRatio = parentScaleX.abs() < 1e-12
        ? 1.0
        : (scaleX.abs() * _canvasUserScale) /
            (parentScaleX.abs() * parent._canvasUserScale);
    final scaleYRatio = parentScaleY.abs() < 1e-12
        ? 1.0
        : (scaleY.abs() * _canvasUserScale) /
            (parentScaleY.abs() * parent._canvasUserScale);
    final nestedMin = math.min(scaleX.abs(), scaleY.abs()) * _canvasUserScale;
    final parentMin = math.min(parentScaleX.abs(), parentScaleY.abs()) *
        parent._canvasUserScale;
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
      clip: label.clip,
      overflow: label.overflow,
      rtl: label.rtl,
      rotationDegrees: label.rotationDegrees,
      alignShape: label.alignShape,
      fontSize: label.fontSize * fontRatio,
      fontStyle: label.fontStyle,
      fontFamily: label.fontFamily,
      color: label.color,
      background: label.background,
      border: label.border,
      textOpacity: label.textOpacity,
      fontFromStroke: label.fontFromStroke,
      fontFromFill: label.fontFromFill,
      fontBgFromStroke: label.fontBgFromStroke,
      fontBgFromFill: label.fontBgFromFill,
      fontBorderFromStroke: label.fontBorderFromStroke,
      fontBorderFromFill: label.fontBorderFromFill,
      leftoverPinX: label.leftoverPinX,
      leftoverPinY: label.leftoverPinY,
      leftoverAngleRad: label.leftoverAngleRad,
      leftoverScaleX: label.leftoverScaleX,
      leftoverScaleY: label.leftoverScaleY,
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
    this.leftoverOffsetX,
    this.leftoverOffsetY,
    this.leftoverWidth,
    this.leftoverHeight,
    this.leftoverAngleRad = 0,
    this.leftoverCanvasFlipX = false,
    this.leftoverCanvasFlipY = false,
    this.leftoverTransparency = 0,
  });

  final String part;
  final String? mime;
  final double? left;
  final double? top;
  final double? boxW;
  final double? boxH;
  final bool flipH;
  final bool flipV;
  final double? leftoverOffsetX;
  final double? leftoverOffsetY;
  final double? leftoverWidth;
  final double? leftoverHeight;
  final double leftoverAngleRad;
  final bool leftoverCanvasFlipX;
  final bool leftoverCanvasFlipY;
  final double leftoverTransparency;

  _DrawioRaster copyWith({
    double? leftoverOffsetX,
    double? leftoverOffsetY,
    double? leftoverWidth,
    double? leftoverHeight,
    double? leftoverAngleRad,
    bool? leftoverCanvasFlipX,
    bool? leftoverCanvasFlipY,
    double? leftoverTransparency,
  }) =>
      _DrawioRaster(
        part: part,
        mime: mime,
        left: left,
        top: top,
        boxW: boxW,
        boxH: boxH,
        flipH: flipH,
        flipV: flipV,
        leftoverOffsetX: leftoverOffsetX ?? this.leftoverOffsetX,
        leftoverOffsetY: leftoverOffsetY ?? this.leftoverOffsetY,
        leftoverWidth: leftoverWidth ?? this.leftoverWidth,
        leftoverHeight: leftoverHeight ?? this.leftoverHeight,
        leftoverAngleRad: leftoverAngleRad ?? this.leftoverAngleRad,
        leftoverCanvasFlipX: leftoverCanvasFlipX ?? this.leftoverCanvasFlipX,
        leftoverCanvasFlipY: leftoverCanvasFlipY ?? this.leftoverCanvasFlipY,
        leftoverTransparency: leftoverTransparency ?? this.leftoverTransparency,
      );
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
    this.clip = false,
    this.overflow,
    this.rtl = false,
    required this.rotationDegrees,
    this.alignShape = true,
    required this.fontSize,
    required this.fontStyle,
    this.fontFamily,
    this.color,
    this.background,
    this.border,
    this.textOpacity = 100,
    this.fontFromStroke = false,
    this.fontFromFill = false,
    this.fontBgFromStroke = false,
    this.fontBgFromFill = false,
    this.fontBorderFromStroke = false,
    this.fontBorderFromFill = false,
    this.leftoverPinX,
    this.leftoverPinY,
    this.leftoverAngleRad = 0,
    this.leftoverScaleX,
    this.leftoverScaleY,
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
  final bool clip;
  final String? overflow;
  final bool rtl;
  final double rotationDegrees;
  final bool alignShape;
  final double fontSize;
  final int fontStyle;
  final String? fontFamily;
  final VsdxColor? color;
  final VsdxColor? background;
  final VsdxColor? border;
  final double textOpacity;
  final bool fontFromStroke;
  final bool fontFromFill;
  final bool fontBgFromStroke;
  final bool fontBgFromFill;
  final bool fontBorderFromStroke;
  final bool fontBorderFromFill;
  final double? leftoverPinX;
  final double? leftoverPinY;
  final double leftoverAngleRad;
  final double? leftoverScaleX;
  final double? leftoverScaleY;
  final List<_DrawioStencilLabelRun> runs;

  /// mxSvgCanvas2D.plainText clipPath / overflow fill|width|block keep
  /// the cell box. leftover wrap=0 otherwise expands TxtWidth.
  bool get keepsTxtBox {
    if (clip) return true;
    final overflow = this.overflow?.toLowerCase();
    return overflow == 'fill' || overflow == 'width' || overflow == 'block';
  }

  _DrawioStencilLabel copyWith({
    double? leftoverPinX,
    double? leftoverPinY,
    double? leftoverAngleRad,
    double? leftoverScaleX,
    double? leftoverScaleY,
  }) =>
      _DrawioStencilLabel(
        text: text,
        x: x,
        y: y,
        boxWidth: boxWidth,
        boxHeight: boxHeight,
        spacingLeft: spacingLeft,
        spacingRight: spacingRight,
        spacingTop: spacingTop,
        spacingBottom: spacingBottom,
        align: align,
        valign: valign,
        vertical: vertical,
        wrap: wrap,
        clip: clip,
        overflow: overflow,
        rtl: rtl,
        rotationDegrees: rotationDegrees,
        alignShape: alignShape,
        fontSize: fontSize,
        fontStyle: fontStyle,
        fontFamily: fontFamily,
        color: color,
        background: background,
        border: border,
        textOpacity: textOpacity,
        fontFromStroke: fontFromStroke,
        fontFromFill: fontFromFill,
        fontBgFromStroke: fontBgFromStroke,
        fontBgFromFill: fontBgFromFill,
        fontBorderFromStroke: fontBorderFromStroke,
        fontBorderFromFill: fontBorderFromFill,
        leftoverPinX: leftoverPinX ?? this.leftoverPinX,
        leftoverPinY: leftoverPinY ?? this.leftoverPinY,
        leftoverAngleRad: leftoverAngleRad ?? this.leftoverAngleRad,
        leftoverScaleX: leftoverScaleX ?? this.leftoverScaleX,
        leftoverScaleY: leftoverScaleY ?? this.leftoverScaleY,
        runs: runs,
      );
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

  _DrawioStencilLabelRun withText(String text) => _DrawioStencilLabelRun(
        text: text,
        fontSize: fontSize,
        fontStyle: fontStyle,
        fontFamily: fontFamily,
        color: color,
        textOpacity: textOpacity,
        position: position,
        align: align,
        marginLeft: marginLeft,
        marginRight: marginRight,
        marginTop: marginTop,
        marginBottom: marginBottom,
        bullet: bullet,
        textPosAfterBullet: textPosAfterBullet,
        lineHeight: lineHeight,
        highlight: highlight,
      );

  _DrawioStencilLabelRun withMargins({double? marginBottom}) =>
      _DrawioStencilLabelRun(
        text: text,
        fontSize: fontSize,
        fontStyle: fontStyle,
        fontFamily: fontFamily,
        color: color,
        textOpacity: textOpacity,
        position: position,
        align: align,
        marginLeft: marginLeft,
        marginRight: marginRight,
        marginTop: marginTop,
        marginBottom: marginBottom ?? this.marginBottom,
        bullet: bullet,
        textPosAfterBullet: textPosAfterBullet,
        lineHeight: lineHeight,
        highlight: highlight,
      );
}

class _MxHtmlStyle {
  _MxHtmlStyle({
    this.fontStyle = 0,
    this.fontColor,
    this.fontSize = _kMxDefaultFontSize,
    this.fontFamily,
    this.textOpacity = 100,
    this.position = 0,
    this.align,
    this.marginTop = 0,
    this.marginRight = 0,
    this.marginBottom = 0,
    this.marginLeft = 0,
    this.paraStart = false,
    this.bullet = 0,
    this.listKind,
    this.listPad = 0,
    this.olIndex = 0,
    this.olNeedPrefix = false,
    this.textPosAfterBullet = 0,
    this.lineHeight = 1,
    this.highlight,
  });

  int fontStyle;
  VsdxColor? fontColor;
  double fontSize;
  String? fontFamily;
  double textOpacity;
  int position;
  String? align;
  double marginTop;
  double marginRight;
  double marginBottom;
  double marginLeft;
  bool paraStart;
  int bullet;
  String? listKind;
  double listPad;
  int olIndex;
  bool olNeedPrefix;
  double textPosAfterBullet;
  double lineHeight;
  VsdxColor? highlight;

  _MxHtmlStyle clone() => _MxHtmlStyle(
        fontStyle: fontStyle,
        fontColor: fontColor,
        fontSize: fontSize,
        fontFamily: fontFamily,
        textOpacity: textOpacity,
        position: position,
        align: align,
        marginTop: marginTop,
        marginRight: marginRight,
        marginBottom: marginBottom,
        marginLeft: marginLeft,
        paraStart: paraStart,
        bullet: bullet,
        listKind: listKind,
        listPad: listPad,
        olIndex: olIndex,
        olNeedPrefix: olNeedPrefix,
        textPosAfterBullet: textPosAfterBullet,
        lineHeight: lineHeight,
        highlight: highlight,
      );

  bool samePaintAs(_DrawioStencilLabelRun run) =>
      fontStyle == run.fontStyle &&
      fontColor?.value == run.color?.value &&
      fontSize == run.fontSize &&
      fontFamily == run.fontFamily &&
      textOpacity == run.textOpacity &&
      position == run.position &&
      align == run.align &&
      marginTop == run.marginTop &&
      marginRight == run.marginRight &&
      marginBottom == run.marginBottom &&
      marginLeft == run.marginLeft &&
      bullet == run.bullet &&
      textPosAfterBullet == run.textPosAfterBullet &&
      lineHeight == run.lineHeight &&
      highlight?.value == run.highlight?.value;

  _DrawioStencilLabelRun toRun(String text) => _DrawioStencilLabelRun(
        text: text,
        fontSize: fontSize,
        fontStyle: fontStyle,
        fontFamily: fontFamily,
        color: fontColor,
        textOpacity: textOpacity,
        position: position,
        align: align,
        marginLeft: marginLeft,
        marginRight: marginRight,
        marginTop: marginTop,
        marginBottom: marginBottom,
        bullet: bullet,
        textPosAfterBullet: textPosAfterBullet,
        lineHeight: lineHeight,
        highlight: highlight,
      );
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
    this.fillFromStroke = false,
    this.strokeFromFill = false,
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

  /// Inherit fill that mxStencil.parseColor maps to shape.stroke.
  final bool fillFromStroke;

  /// Inherit stroke that mxStencil.parseColor maps to shape.fill.
  final bool strokeFromFill;
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

/// mxXmlCanvas2D.setFontFamily / mxStencil.drawNode fontfamily.
/// CSS stacks walk like NestedStencil htmlFontFamily so webfonts
/// such as "open sans" do not freeze Char.Font; named and generic
/// faces map onto Visio/libvisio names collectCharIX emits as
/// style:font-name.
String? _mxFontFamily(String? raw) {
  var token = (raw ?? '').trim();
  if (token.isEmpty) return null;
  // mxXmlCanvas2D.setFontFamily handles CSS font-family stacks.
  // leftover first comma token froze webfonts such as "open sans"
  // so Draw collectCharIX missed Arial (`tokens.txt` Font). Walk
  // like NestedStencil htmlFontFamily / leftover HTML parser.
  final stacked = _mxHtmlCssFontFamily(token);
  if (stacked != null) return stacked;
  if (token.contains(',')) return null;
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

bool _sketchesEqual(_DrawioSketchState a, _DrawioSketchState b) {
  if (a.enabled != b.enabled) return false;
  if (!a.enabled) return true;
  bool same(double? left, double? right) {
    if (left == null && right == null) return true;
    if (left == null || right == null) return false;
    return (left - right).abs() < 1e-9;
  }

  return a.fill == b.fill &&
      same(a.gap, b.gap) &&
      same(a.angle, b.angle) &&
      same(a.weight, b.weight) &&
      same(a.jiggle, b.jiggle);
}

bool _shadowsEqual(VsdxShadow? a, VsdxShadow? b) {
  final left = a ?? VsdxShadow.disabled;
  final right = b ?? VsdxShadow.disabled;
  if (left.enabled != right.enabled) return false;
  if (!left.enabled) return true;
  return left.pattern == right.pattern &&
      (left.offsetXInches - right.offsetXInches).abs() < 1e-6 &&
      (left.offsetYInches - right.offsetYInches).abs() < 1e-6 &&
      (left.transparency - right.transparency).abs() < 1e-6 &&
      left.color == right.color;
}

bool _dashPatternsEqual(List<double>? a, List<double>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if ((a[i] - b[i]).abs() > 1e-9) return false;
  }
  return true;
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
  if (value == null || !value.isFinite) return null;
  // mxStencil.drawShape `Number(strokewidth) * minScale`. 0 still
  // calls setStrokeWidth(0); leftover used to treat it as inherit
  // so Draw collectLine pinned the palette LineWeight
  // (`tokens.txt` LineWeight). `_strokeWeightInches` floors 0 to
  // mxSvgCanvas2D.minStrokeWidth 1 canvas pixel.
  return value;
}

/// Visio LineCap: 0 round, 1 extended/butt, 2 square. libvisio
/// `_lineProperties` maps those onto svg:stroke-linecap. Empty /
/// unknown tokens are null so the caller can snap to createState
/// flat (LineCap 1); SVG default when state.lineCap is null is butt.
LineCap? _mxLineCap(String? raw) => switch ((raw ?? '').trim().toLowerCase()) {
      'round' => LineCap.round,
      'square' => LineCap.square,
      'butt' || 'flat' => LineCap.extended,
      _ => null,
    };

/// mxStencil.drawNode setLineJoin. Empty/omitted is null so the
/// caller snaps to SVG's CSS initial `miter` (same as createState).
/// Invalid SVG joins (`flat` / `square` / `butt`) also snap to miter.
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

/// PNG IHDR pixel size so leftover can letterbox `canvas.image` aspect.
({int width, int height})? _rasterPixelSize(Uint8List bytes) {
  if (bytes.length < 24) return null;
  if (bytes[0] != 0x89 ||
      bytes[1] != 0x50 ||
      bytes[2] != 0x4e ||
      bytes[3] != 0x47) {
    return null;
  }
  final width =
      (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
  final height =
      (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
  if (width <= 0 || height <= 0) return null;
  return (width: width, height: height);
}

/// mxSvgCanvas2D.image preserveAspectRatio xMidYMid meet inside the box.
({double left, double top, double width, double height}) _mxSvgMeetBox({
  required double left,
  required double top,
  required double boxW,
  required double boxH,
  required int imageW,
  required int imageH,
}) {
  final scale = math.min(boxW / imageW, boxH / imageH);
  final fittedW = imageW * scale;
  final fittedH = imageH * scale;
  return (
    left: left + (boxW - fittedW) / 2,
    top: top + (boxH - fittedH) / 2,
    width: fittedW,
    height: fittedH,
  );
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

/// NestedStencil parseHtmlLabel / html.spec named character references.
const Map<String, String> _kMxHtmlNamedEntities = <String, String>{
  'nbsp': '\u00A0',
  'iexcl': '¡',
  'cent': '¢',
  'pound': '£',
  'curren': '¤',
  'yen': '¥',
  'brvbar': '¦',
  'sect': '§',
  'uml': '¨',
  'copy': '©',
  'ordf': 'ª',
  'laquo': '«',
  'not': '¬',
  'shy': '\u00AD',
  'reg': '®',
  'macr': '¯',
  'deg': '°',
  'plusmn': '±',
  'sup2': '²',
  'sup3': '³',
  'acute': '´',
  'micro': 'µ',
  'para': '¶',
  'middot': '·',
  'cedil': '¸',
  'sup1': '¹',
  'ordm': 'º',
  'raquo': '»',
  'frac14': '¼',
  'frac12': '½',
  'frac34': '¾',
  'iquest': '¿',
  'times': '×',
  'divide': '÷',
  'ndash': '–',
  'mdash': '—',
  'hellip': '…',
  'bull': '•',
  'trade': '™',
  'lsquo': '‘',
  'rsquo': '’',
  'ldquo': '“',
  'rdquo': '”',
  'apos': "'",
};

String _mxHtmlDecodeEntities(String value) {
  var s = value.replaceAll('&#10;', '\n');
  s = s.replaceAllMapped(RegExp(r'&#x([0-9a-f]+);', caseSensitive: false), (
    match,
  ) {
    final code = int.tryParse(match.group(1)!, radix: 16);
    if (code == null) return match.group(0)!;
    return String.fromCharCode(code);
  });
  s = s.replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
    final code = int.tryParse(match.group(1)!);
    if (code == null) return match.group(0)!;
    return String.fromCharCode(code);
  });
  s = s.replaceAllMapped(RegExp(r'&([a-zA-Z][a-zA-Z0-9]+);'), (match) {
    final key = match.group(1)!.toLowerCase();
    if (key == 'amp' || key == 'lt' || key == 'gt' || key == 'quot') {
      return match.group(0)!;
    }
    return _kMxHtmlNamedEntities[key] ?? match.group(0)!;
  });
  return s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"');
}

String _mxHtmlCollapseWhitespace(String text) =>
    text.replaceAll(RegExp(r'[\t\f\v\r ]+'), ' ');

String? _mxHtmlAttr(String attrs, String name) {
  final match = RegExp(
    '(?:^|\\s)${RegExp.escape(name)}\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s>]+))',
    caseSensitive: false,
  ).firstMatch(attrs);
  if (match == null) return null;
  return match.group(1) ?? match.group(2) ?? match.group(3);
}

String? _mxHtmlStyleProp(String attrs, String prop) {
  final style = _mxHtmlDecodeEntities(_mxHtmlAttr(attrs, 'style') ?? '');
  final match = RegExp(
    '(?:^|;)\\s*${RegExp.escape(prop)}\\s*:\\s*([^;]+)',
    caseSensitive: false,
  ).firstMatch(style);
  if (match == null) return null;
  return match.group(1)!.trim();
}

String? _mxHtmlCssFontFamily(String raw) {
  const named = <String, String>{
    'arial': 'Arial',
    'helvetica': 'Helvetica',
    'times new roman': 'Times New Roman',
    'times': 'Times New Roman',
    'courier new': 'Courier New',
    'courier': 'Courier New',
    'calibri': 'Calibri',
    'verdana': 'Verdana',
    'georgia': 'Georgia',
    'tahoma': 'Tahoma',
    'comic sans ms': 'Comic Sans MS',
  };
  const generics = <String, String>{
    'sans-serif': 'Arial',
    'serif': 'Times New Roman',
    'monospace': 'Courier New',
  };
  String? fallback;
  for (final part in _mxHtmlDecodeEntities(raw).split(',')) {
    var name = part.trim();
    if (name.length >= 2 &&
        ((name.startsWith('"') && name.endsWith('"')) ||
            (name.startsWith("'") && name.endsWith("'")))) {
      name = name.substring(1, name.length - 1).trim();
    }
    if (name.isEmpty) continue;
    final key = name.toLowerCase();
    final mapped = named[key];
    if (mapped != null) return mapped;
    final generic = generics[key];
    if (generic != null) {
      fallback ??= generic;
    }
  }
  return fallback;
}

String? _mxHtmlAlignToken(String? raw) {
  final v = (raw ?? '').trim().toLowerCase();
  if (v == 'center' || v == 'middle') return 'center';
  if (v == 'right' || v == 'end') return 'right';
  if (v == 'justify') return 'justify';
  if (v == 'left' || v == 'start') return 'left';
  return null;
}

double? _mxHtmlCssPx(String? raw) {
  final token = (raw ?? '').trim();
  if (token.isEmpty ||
      token == 'auto' ||
      token == 'inherit' ||
      token == 'none') {
    return null;
  }
  return double.tryParse(
      RegExp(r'^-?[0-9]*\.?[0-9]+').stringMatch(token) ?? '');
}

const Map<String, double> _kMxCssAbsoluteFontSizePx = <String, double>{
  'xx-small': 9,
  'x-small': 10,
  'small': 13,
  'medium': 16,
  'large': 18,
  'x-large': 24,
  'xx-large': 32,
  'xxx-large': 48,
};

const List<double> _kMxHtmlFontSizePx = <double>[
  0,
  10,
  13,
  16,
  18,
  24,
  32,
  48,
];

double _mxHtmlFontSizeTablePx(int index) {
  final i = index.clamp(1, 7);
  return _kMxHtmlFontSizePx[i];
}

int _mxHtmlFontSizeIndexFromPx(double px) {
  var best = 3;
  var dist = double.infinity;
  for (var i = 1; i <= 7; i++) {
    final d = (_kMxHtmlFontSizePx[i] - px).abs();
    if (d < dist) {
      dist = d;
      best = i;
    }
  }
  return best;
}

double? _mxHtmlCssFontSizePx(String raw, double currentPx) {
  final token = raw.trim();
  if (token.isEmpty ||
      token == 'auto' ||
      token == 'inherit' ||
      token == 'none') {
    return null;
  }
  final keyword = _kMxCssAbsoluteFontSizePx[token.toLowerCase()];
  if (keyword != null) return keyword;
  if (RegExp(r'^smaller$', caseSensitive: false).hasMatch(token)) {
    return currentPx > 0 ? currentPx / 1.2 : null;
  }
  if (RegExp(r'^larger$', caseSensitive: false).hasMatch(token)) {
    return currentPx > 0 ? currentPx * 1.2 : null;
  }
  final lower = token.toLowerCase();
  if (lower.endsWith('rem')) {
    final n = double.tryParse(token.substring(0, token.length - 3));
    return n == null ? null : n * 16;
  }
  if (lower.endsWith('em')) {
    final n = double.tryParse(token.substring(0, token.length - 2));
    return n != null && currentPx > 0 ? n * currentPx : null;
  }
  if (token.endsWith('%')) {
    final n = double.tryParse(token.substring(0, token.length - 1));
    return n != null && currentPx > 0 ? n * currentPx / 100 : null;
  }
  return _mxHtmlCssPx(token);
}

double? _mxHtmlFontSizeAttrPx(String raw, double currentPx) {
  final token = raw.trim();
  if (token.isEmpty) return null;
  final rel = RegExp(r'^([+-])(\d+)$').firstMatch(token);
  if (rel != null) {
    final delta = int.parse(rel.group(2)!) * (rel.group(1) == '-' ? -1 : 1);
    return _mxHtmlFontSizeTablePx(
        _mxHtmlFontSizeIndexFromPx(currentPx) + delta);
  }
  final n = double.tryParse(token);
  if (n == null || n < 1 || n > 7 || n != n.roundToDouble()) return null;
  return _mxHtmlFontSizeTablePx(n.round());
}

double? _mxHtmlCssLineHeight(String raw, double fontPx) {
  final token = raw.trim().toLowerCase();
  if (token.isEmpty ||
      token == 'normal' ||
      token == 'inherit' ||
      token == 'initial' ||
      token == 'unset') {
    return null;
  }
  if (token.endsWith('%')) {
    final n = double.tryParse(token.substring(0, token.length - 1));
    return n != null && n > 0 ? n / 100 : null;
  }
  if (token.endsWith('em') && !token.endsWith('rem')) {
    final n = double.tryParse(token.substring(0, token.length - 2));
    return n != null && n > 0 ? n : null;
  }
  if (token.endsWith('px')) {
    final n = double.tryParse(token.substring(0, token.length - 2));
    return n != null && n > 0 && fontPx > 0 ? n / fontPx : null;
  }
  if (RegExp(r'[a-z%]').hasMatch(token)) return null;
  final n = double.tryParse(token);
  return n != null && n > 0 ? n : null;
}

const Map<String, ({double sizeEm, double marginEm})> _kMxHtmlHeadingUa =
    <String, ({double sizeEm, double marginEm})>{
  'h1': (sizeEm: 2, marginEm: 0.67),
  'h2': (sizeEm: 1.5, marginEm: 0.83),
  'h3': (sizeEm: 1.17, marginEm: 1),
  'h4': (sizeEm: 1, marginEm: 1.33),
  'h5': (sizeEm: 0.83, marginEm: 1.67),
  'h6': (sizeEm: 0.67, marginEm: 2.33),
};

void _mxHtmlUaHeadingDefaults(_MxHtmlStyle next, String tag) {
  final heading = _kMxHtmlHeadingUa[tag];
  if (heading == null) return;
  final base = next.fontSize > 0 ? next.fontSize : _kMxDefaultFontSize;
  next.fontSize = base * heading.sizeEm;
  next.fontStyle |= 1;
}

void _mxHtmlUaBlockMargins(_MxHtmlStyle next, String tag) {
  final base = next.fontSize > 0 ? next.fontSize : _kMxDefaultFontSize;
  final heading = _kMxHtmlHeadingUa[tag];
  if (heading != null) {
    final m = base * heading.marginEm;
    next.marginTop = m;
    next.marginBottom = m;
    return;
  }
  if (tag == 'p') {
    next.marginTop = base;
    next.marginBottom = base;
  }
}

void _mxHtmlApplyMargins(_MxHtmlStyle next, String attrs) {
  final box = (_mxHtmlStyleProp(attrs, 'margin') ?? '').trim();
  if (box.isNotEmpty) {
    final parts = [
      for (final token in box.split(RegExp(r'\s+'))) _mxHtmlCssPx(token),
    ];
    if (parts.isNotEmpty && parts.every((v) => v != null)) {
      final values = [for (final v in parts) v!];
      if (values.length == 1) {
        next.marginTop =
            next.marginRight = next.marginBottom = next.marginLeft = values[0];
      } else if (values.length == 2) {
        next.marginTop = next.marginBottom = values[0];
        next.marginRight = next.marginLeft = values[1];
      } else if (values.length == 3) {
        next.marginTop = values[0];
        next.marginRight = next.marginLeft = values[1];
        next.marginBottom = values[2];
      } else {
        next.marginTop = values[0];
        next.marginRight = values[1];
        next.marginBottom = values[2];
        next.marginLeft = values[3];
      }
    }
  }
  final mt = _mxHtmlCssPx(_mxHtmlStyleProp(attrs, 'margin-top'));
  if (mt != null) next.marginTop = mt;
  final mr = _mxHtmlCssPx(_mxHtmlStyleProp(attrs, 'margin-right'));
  if (mr != null) next.marginRight = mr;
  final mb = _mxHtmlCssPx(_mxHtmlStyleProp(attrs, 'margin-bottom'));
  if (mb != null) next.marginBottom = mb;
  final ml = _mxHtmlCssPx(_mxHtmlStyleProp(attrs, 'margin-left'));
  if (ml != null) next.marginLeft = ml;
}

void _mxHtmlApplyCss(
  _MxHtmlStyle next,
  String attrs,
  String tag, {
  required VsdxColor? Function(String? raw) resolveColor,
}) {
  _mxHtmlUaHeadingDefaults(next, tag);
  final color = _mxHtmlAttr(attrs, 'color') ?? _mxHtmlStyleProp(attrs, 'color');
  if (color != null) next.fontColor = resolveColor(color);
  final bgRaw = _mxHtmlStyleProp(attrs, 'background-color') ??
      _mxHtmlStyleProp(attrs, 'background');
  if (bgRaw != null) {
    final token = bgRaw.trim();
    if (RegExp(r'^(none|transparent|initial|unset)$', caseSensitive: false)
        .hasMatch(token)) {
      next.highlight = null;
    } else {
      next.highlight = _mxGraphPaintColor(token);
    }
  }
  final cssSize = _mxHtmlStyleProp(attrs, 'font-size');
  if (cssSize != null) {
    final size = _mxHtmlCssFontSizePx(cssSize, next.fontSize);
    if (size != null && size > 0) next.fontSize = size;
  } else {
    final htmlSize = _mxHtmlAttr(attrs, 'size');
    if (htmlSize != null) {
      final mapped = _mxHtmlFontSizeAttrPx(htmlSize, next.fontSize);
      if (mapped != null) next.fontSize = mapped;
    }
  }
  final weight = _mxHtmlStyleProp(attrs, 'font-weight');
  if (weight != null) {
    if (RegExp(r'^(bold|bolder|[7-9]00)$', caseSensitive: false)
        .hasMatch(weight)) {
      next.fontStyle |= 1;
    } else if (RegExp(r'^(normal|lighter|[1-4]00)$', caseSensitive: false)
        .hasMatch(weight)) {
      next.fontStyle &= ~1;
    }
  }
  final italic = _mxHtmlStyleProp(attrs, 'font-style');
  if (italic != null) {
    if (RegExp('italic|oblique', caseSensitive: false).hasMatch(italic)) {
      next.fontStyle |= 2;
    } else if (RegExp(r'^normal$', caseSensitive: false).hasMatch(italic)) {
      next.fontStyle &= ~2;
    }
  }
  final deco = _mxHtmlStyleProp(attrs, 'text-decoration');
  if (deco != null) {
    if (RegExp('underline', caseSensitive: false).hasMatch(deco)) {
      next.fontStyle |= 4;
    }
    if (RegExp('line-through', caseSensitive: false).hasMatch(deco)) {
      next.fontStyle |= 8;
    }
  }
  final family =
      _mxHtmlStyleProp(attrs, 'font-family') ?? _mxHtmlAttr(attrs, 'face');
  if (family != null) {
    final mapped = _mxHtmlCssFontFamily(family);
    if (mapped != null) next.fontFamily = mapped;
  }
  final bb = _mxHtmlStyleProp(attrs, 'border-bottom') ??
      _mxHtmlStyleProp(attrs, 'border-bottom-style');
  if (bb != null && RegExp('solid', caseSensitive: false).hasMatch(bb)) {
    next.fontStyle |= 4;
  }
  if (tag == 'p' ||
      tag == 'div' ||
      tag == 'td' ||
      tag == 'th' ||
      tag == 'li' ||
      RegExp(r'^h[1-6]$').hasMatch(tag)) {
    final ta = _mxHtmlAlignToken(
      _mxHtmlStyleProp(attrs, 'text-align') ?? _mxHtmlAttr(attrs, 'align'),
    );
    if (ta != null) next.align = ta;
  }
  if (tag == 'p' ||
      tag == 'div' ||
      tag == 'li' ||
      RegExp(r'^h[1-6]$').hasMatch(tag)) {
    _mxHtmlUaBlockMargins(next, tag);
    _mxHtmlApplyMargins(next, attrs);
    next.paraStart = true;
  }
  final lh = _mxHtmlStyleProp(attrs, 'line-height');
  if (lh != null) {
    final parsed = _mxHtmlCssLineHeight(lh, next.fontSize);
    if (parsed != null) next.lineHeight = parsed;
  }
}

bool _flag(XmlElement element, String name) =>
    element.getAttribute(name) == '1' ||
    element.getAttribute(name)?.toLowerCase() == 'true';
