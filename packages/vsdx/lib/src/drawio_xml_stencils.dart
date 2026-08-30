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
    return _DrawioXmlShapeDecoder(shapes[index]).build(id, cx, cy);
  }

  List<XmlElement> _decodeShapes() {
    final compressed = base64Decode(record.encodedXml);
    final xmlBytes = GZipDecoder().decodeBytes(compressed);
    final document = XmlDocument.parse(utf8.decode(xmlBytes));
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

/// Visio Char.Size UI floor is 0.5pt. The old 0.04in (~2.88pt) clamp
/// flattened mxText `font-size:14px` / `9px` on wide composites
/// (Salesforce Header 930px) after catalog scale `1.5 / max(w,h)`, so
/// collectCharIX `fo:font-size` matched. 0.5pt still rejects empty Size.
const double _kMxMinCharSizeInches = 0.5 / 72.0;

class _DrawioXmlShapeDecoder {
  _DrawioXmlShapeDecoder(this.element);

  final XmlElement element;

  late final double sourceWidth = _number(element, 'w', fallback: 100);
  late final double sourceHeight = _number(element, 'h', fallback: 100);
  late final double targetWidth;
  late final double targetHeight;
  late final double scaleX;
  late final double scaleY;

  final List<VsdxGeometry> _geometries = <VsdxGeometry>[];
  final List<_DrawioStencilLabel> _labels = <_DrawioStencilLabel>[];
  final List<_DrawioColoredPart> _coloredParts = <_DrawioColoredPart>[];
  List<VsdxPathCommand>? _pending;
  double _fontSize = 12;
  int _fontStyle = 0;
  String? _fontFamily;
  VsdxColor? _fontColor;
  VsdxColor? _fontBackground;
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
  double? _parentStrokeWidth;
  bool _dashed = false;
  bool _solidPaintBeforeDash = false;
  bool _parentDashed = false;
  List<double>? _parentDashPattern;
  List<double>? _dashPattern;
  LineCap? _lineCap;
  VsdxLineJoin? _lineJoin;
  double? _miterLimit;
  VsdxShadow? _shadow;
  VsdxShadow? _parentShadow;
  String? _rasterPart;
  String? _rasterMime;
  bool _sketchEnabled = false;
  String? _sketchFill;
  double? _sketchGap;
  double? _sketchAngle;
  double? _sketchWeight;
  double? _sketchJiggle;
  double _penX = 0;
  double _penY = 0;
  double _subX = 0;
  double _subY = 0;
  bool _hasSub = false;

  VsdxShape build(int id, double cx, double cy) {
    final safeWidth =
        sourceWidth.isFinite && sourceWidth > 0 ? sourceWidth : 100.0;
    final safeHeight =
        sourceHeight.isFinite && sourceHeight > 0 ? sourceHeight : 100.0;
    final scale = 1.5 / math.max(safeWidth, safeHeight);
    targetWidth = math.max(0.25, safeWidth * scale);
    targetHeight = math.max(0.25, safeHeight * scale);
    scaleX = targetWidth / safeWidth;
    scaleY = targetHeight / safeHeight;

    for (final sectionName in const <String>['background', 'foreground']) {
      final section = element.getElement(sectionName);
      if (section == null) continue;
      for (final child in section.childElements) {
        _consume(child);
      }
    }
    if (_pending != null && _pending!.isNotEmpty) {
      // fillColor=none / strokeColor=none painters still emit a contour
      // (Bootstrap "Button, link") that libvisio needs as a hit box.
      _finish(fill: false, stroke: false);
    }

    if (_geometries.isEmpty && _rasterPart != null) {
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
        _rasterPart == null) {
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
    // Use Sheet.N like factory / chart stencils. The catalog keeps the
    // human-readable stencil title for the palette; putting it on shape.name
    // would paint as a label fallback when text is empty. Authored mxGraph
    // <text> glyphs (IEC AND, calendar days, …) become children so
    // LibreOffice's libvisio text collector still paints them. Hex
    // fillcolor / strokecolor contours are children too: libvisio
    // collectGeometry concatenates every NoFill=0 section of one shape
    // into one evenodd path, so a black radio dot on a grey disk would
    // otherwise punch a hole.
    final parentFill =
        _rasterPart != null || (!inheritFill && children.isNotEmpty)
            ? const VsdxFill(pattern: 0)
            : (_styleFill != null
                ? VsdxFill(pattern: 1, foreground: _styleFill)
                : VsdxFill.defaultFill);
    var parentLine =
        _rasterPart != null || (!inheritLine && children.isNotEmpty)
            ? const VsdxLine(pattern: 0)
            : _paintLine(stroke: true);
    if (inheritLine && _styleStroke != null && parentLine.hasLine) {
      parentLine = parentLine.withSolidColor(_styleStroke!);
    }
    if (inheritLine && _parentStrokeWidth != null) {
      // restore() re-emits the pre-save strokewidth (often 1) after the
      // contour. collectLine is shape-level, so keep the width that was
      // in force when parent Geometry was painted.
      final savedWidth = _strokeWidth;
      _strokeWidth = _parentStrokeWidth;
      parentLine = parentLine.copyWith(weightInches: _strokeWeightInches);
      _strokeWidth = savedWidth;
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
    return _withLineUserCells(VsdxShape(
      id: id,
      name: 'Sheet.$id',
      pinX: cx,
      pinY: cy,
      width: targetWidth,
      height: targetHeight,
      geometries: List<VsdxGeometry>.unmodifiable(_geometries),
      connectionPoints: _connectionPoints(),
      children: children,
      shapeKind: children.isEmpty ? VsdxShapeKind.normal : VsdxShapeKind.group,
      fill: parentFill,
      line: parentLine,
      shadow: inheritFill
          ? (_parentShadow ?? VsdxShadow.disabled)
          : VsdxShadow.disabled,
      imagePartName: _rasterPart,
      foreignType: _rasterPart == null
          ? null
          : VsdxImage.foreignTypeFor(
              mimeType: _rasterMime ?? '',
              partName: _rasterPart!,
            ),
      foreignCompressionType: _rasterPart == null
          ? null
          : VsdxImage.compressionTypeFor(
              mimeType: _rasterMime ?? '',
              partName: _rasterPart!,
            ),
    ));
  }

  void _consume(XmlElement node) {
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
        _dashed = node.getAttribute('dashed') != '0';
        break;
      case 'dashpattern':
        _dashPattern = _parseMxDashPattern(node.getAttribute('pattern'));
        break;
      case 'linecap':
        _lineCap = _mxLineCap(node.getAttribute('cap'));
        break;
      case 'linejoin':
        _lineJoin = VsdxLineJoin.parse(node.getAttribute('join'));
        break;
      case 'miterlimit':
        final limit = _number(node, 'limit', fallback: 4);
        if (limit >= 1) _miterLimit = limit;
        break;
      case 'shadow':
        _applyMxShadow(node);
        break;
      case 'fill':
        _finish(fill: true, stroke: false);
        break;
      case 'stroke':
        _finish(fill: false, stroke: true);
        break;
      case 'fillstroke':
      case 'fillstrokecolor':
        _finish(fill: true, stroke: true);
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
        _applyMxFill(node.getAttribute('color'));
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
        _applyMxStroke(node.getAttribute('color'));
        break;
      case 'fontcolor':
        _applyMxFont(node.getAttribute('color'));
        break;
      case 'fontbackgroundcolor':
        _applyMxFontBackground(node.getAttribute('color'));
        break;
      case 'strokewidth':
        final width = _number(node, 'width');
        if (width > 0) {
          _strokeWidth = width;
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
            // mxXmlCanvas2D.text rotation is STYLE_ROTATION; decoder
            // negates into TxtAngle that LibreOffice librevenge:rotate
            // paints (Y-up). STYLE_HORIZONTAL stays `vertical`.
            fontSize: runs.first.fontSize,
            fontStyle: runs.first.fontStyle,
            fontFamily: runs.first.fontFamily,
            color: runs.first.color,
            background: _fontBackground,
            // mxText.apply STYLE_TEXT_OPACITY percent. Char ColorTrans
            // is not a libvisio token; a save bakes it into Color RGB.
            textOpacity: runs.first.textOpacity,
            runs: runs,
          ));
        }
        break;
      case 'image':
        _consumeRaster(node);
        break;
      // save/restore and remaining paint attributes affect alpha or line
      // join. Hex fillcolor / strokecolor / fontcolor are consumed above so
      // Draw can paint them as sibling shapes (one FillForegnd each).
      // `fillgradient` bakes FillPattern 25–34 so libvisio's two-stop
      // linear (`_fillAndShadowProperties`) keeps AWS brand ramps;
      // `applyStencilStyle.withSolidForeground` would otherwise beige them.
      // `alpha` / `fillalpha` / `strokealpha` become FillForegndTrans /
      // LineColorTrans that `_fillAndShadowProperties` maps to draw:opacity.
      // `linecap` / `linejoin` / `miterlimit` / `dashpattern` follow
      // mxStencil.drawNode onto collectLine LineCap / LinePattern (custom
      // arrays bake to a MoveTo ribbon because libvisio treats 0xfe as solid).
      // `shadow` follows mxShape.configureCanvas setShadow onto ShdwPattern
      // that `_fillAndShadowProperties` maps to ODF draw:shadow (hard
      // translate like mxSvgCanvas2D.createShadow, not ShadowBlur).
      // `fontfamily` follows mxStencil.drawNode setFontFamily onto Char.Font
      // that collectCharIX maps to style:font-name.
      // `fontbackgroundcolor` follows mxText.configureCanvas onto TextBkgnd
      // that collectTextBlock maps to fo:background-color.
      // `text` `textopacity` follows mxText.apply STYLE_TEXT_OPACITY onto
      // Char.transparency; ColorTrans is not a token, so a save bakes RGB
      // that collectCharIX maps to fo:color (xmlStringToColour zeros alpha).
      // `text` `run` children follow mxText html=1 <b>/<font> onto extra
      // Character rows collectCharIX maps to fo:font-weight / fo:color /
      // fo:font-size.
      // `fill` / `stroke` keywords and style keys (fillColor2, …) stay on
      // the parent so applyStencilStyle can still recolor the body.
      default:
        break;
    }
  }

  void _consumeRaster(XmlElement node) {
    final src = node.getAttribute('src') ?? '';
    final parsed = _dataUriImage(src);
    if (parsed == null) return;
    _rasterMime = parsed.mime;
    _rasterPart = registerDrawioStencilImage(
      parsed.bytes,
      mimeType: parsed.mime,
    );
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
    _pending = commands;
  }

  void _appendImplicitPathNode(XmlElement node) {
    final commands = _pending ?? <VsdxPathCommand>[];
    _decodePathNode(node, commands);
    if (commands.isEmpty) return;
    _pending = commands;
  }

  void _applyMxFill(String? raw) {
    _fillOverride = null;
    final token = (raw ?? '').trim();
    final lower = token.toLowerCase();
    if (token.isEmpty || lower == 'fill' || lower == 'default') {
      _fillColor = null;
      _fillIsNone = false;
      return;
    }
    if (lower == 'none') {
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
    _fillColor = parsed;
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
      _applyMxFill(node.getAttribute('color1'));
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
      _applyMxFill(node.getAttribute('color1'));
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

  void _applyMxStroke(String? raw) {
    final token = (raw ?? '').trim();
    final lower = token.toLowerCase();
    if (token.isEmpty || lower == 'stroke' || lower == 'default') {
      _strokeColor = null;
      _strokeIsNone = false;
      return;
    }
    if (lower == 'none') {
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
    _strokeColor = parsed;
    _strokeIsNone = false;
  }

  void _applyMxFont(String? raw) {
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
    _fontColor = _mxGraphPaintColor(token);
  }

  void _applyMxFontBackground(String? raw) {
    final token = (raw ?? '').trim();
    final lower = token.toLowerCase();
    if (token.isEmpty || lower == 'default' || lower == 'none') {
      _fontBackground = null;
      return;
    }
    _fontBackground = _mxGraphPaintColor(token);
  }

  /// mxText html=1: `<run>` children are extra Character rows. A bare
  /// `str=` label stays a single collectCharIX run.
  List<_DrawioStencilLabelRun> _decodeTextRuns(XmlElement node) {
    final parentOpacity = _number(node, 'textopacity', fallback: 100);
    final runs = <_DrawioStencilLabelRun>[
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
            color: el.getAttribute('fontcolor') != null
                ? _mxGraphPaintColor(el.getAttribute('fontcolor'))
                : _fontColor,
            textOpacity: _number(
              el,
              'textopacity',
              fallback: parentOpacity,
            ),
            position:
                el.getAttribute('pos') == null ? 0 : _number(el, 'pos').round(),
            align: el.getAttribute('align'),
            marginLeft: _number(el, 'margin-left'),
            marginRight: _number(el, 'margin-right'),
            marginTop: _number(el, 'margin-top'),
            marginBottom: _number(el, 'margin-bottom'),
          ),
    ].where((run) => run.text.isNotEmpty).toList(growable: false);
    if (runs.isNotEmpty) return runs;
    final str = node.getAttribute('str') ?? '';
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
    // mxStencil.drawNode: width * (fixed ? 1 : minScale). The catalog
    // freezes the stencil at targetWidth×targetHeight, so both cases
    // scale with the same min(scaleX, scaleY) as MoveTo/LineTo.
    final scale = math.min(scaleX.abs(), scaleY.abs());
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
    final source = raw ?? _dashPattern;
    if (source == null || source.isEmpty) return null;
    final scale = math.min(scaleX.abs(), scaleY.abs());
    final values = <double>[
      for (final value in source)
        if (value > 0) value * scale / drawioDashUnitInches,
    ];
    return values.length >= 2 ? values : null;
  }

  VsdxLine _lineWithDash(VsdxLine line, List<double>? pattern) {
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
    final commands = _pending;
    _pending = null;
    if (commands == null || commands.isEmpty) return;
    final doFill = fill && !_fillIsNone;
    final doStroke = stroke && !_strokeIsNone;
    if (!doFill && !doStroke && (fill || stroke)) return;
    final bakeFill = doFill && _fillColor != null;
    final bakeStroke = doStroke && _strokeColor != null && !doFill;
    // libvisio collectLine is shape-level. A dash after a solid paint
    // (EIP Detour diagonal) must be a sibling. A shape that is dashed
    // from the first paint (Availability Zone, Dashed Wire) keeps
    // LinePattern on the parent so applyStencilStyle can still recolor it.
    final bakeDash = doStroke && _dashed && _solidPaintBeforeDash;
    if (bakeFill || bakeStroke || bakeDash) {
      _coloredParts.add(_DrawioColoredPart(
        commands: List<VsdxPathCommand>.unmodifiable(commands),
        fill: doFill && (bakeFill || bakeDash)
            ? _paintFill()
            : const VsdxFill(pattern: 0),
        line: _paintLine(stroke: doStroke),
        shadow: _shadow ?? VsdxShadow.disabled,
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
    if (doStroke && _dashed) {
      _parentDashed = true;
      _parentDashPattern ??= _dashPattern;
    }
    if (doStroke && _strokeWidth != null) {
      _parentStrokeWidth ??= _strokeWidth;
    }
    if (_shadow != null) _parentShadow ??= _shadow;
  }

  List<VsdxPathCommand> _decodePath(XmlElement path) {
    final commands = <VsdxPathCommand>[];
    for (final command in path.childElements) {
      _decodePathNode(command, commands);
    }
    return commands;
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
        final curves = _svgArcCurves(
          _penX,
          _penY,
          endX,
          endY,
          _number(command, 'rx').abs(),
          _number(command, 'ry').abs(),
          _number(command, 'x-axis-rotation') * math.pi / 180,
          _flag(command, 'large-arc-flag'),
          _flag(command, 'sweep-flag'),
        );
        if (curves.isEmpty) {
          commands.add(LineTo(_x(endX), _y(endY)));
        } else {
          for (final curve in curves) {
            commands.add(CubBezTo(
              x: _x(curve.endX),
              y: _y(curve.endY),
              x1: _x(curve.x1),
              y1: _y(curve.y1),
              x2: _x(curve.x2),
              y2: _y(curve.y2),
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
    final arcSize = _number(rect, 'arcsize', fallback: 15).clamp(0.0, 100.0);
    final radius = math.min(width, height) * arcSize / 100;
    final k = radius * 0.5522847498307936;
    return <VsdxPathCommand>[
      MoveTo(_x(left + radius), _y(top)),
      LineTo(_x(right - radius), _y(top)),
      CubBezTo(
        x: _x(right),
        y: _y(top + radius),
        x1: _x(right - radius + k),
        y1: _y(top),
        x2: _x(right),
        y2: _y(top + radius - k),
      ),
      LineTo(_x(right), _y(bottom - radius)),
      CubBezTo(
        x: _x(right - radius),
        y: _y(bottom),
        x1: _x(right),
        y1: _y(bottom - radius + k),
        x2: _x(right - radius + k),
        y2: _y(bottom),
      ),
      LineTo(_x(left + radius), _y(bottom)),
      CubBezTo(
        x: _x(left),
        y: _y(bottom - radius),
        x1: _x(left + radius - k),
        y1: _y(bottom),
        x2: _x(left),
        y2: _y(bottom - radius + k),
      ),
      LineTo(_x(left), _y(top + radius)),
      CubBezTo(
        x: _x(left + radius),
        y: _y(top),
        x1: _x(left),
        y1: _y(top + radius - k),
        x2: _x(left + radius - k),
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
    final cx = left + width / 2;
    final cy = top + height / 2;
    return <VsdxPathCommand>[
      EllipseCmd(
        cx: _x(cx),
        cy: _y(cy),
        aX: _x(left + width),
        aY: _y(cy),
        bX: _x(cx),
        bY: _y(top),
      ),
    ];
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

  VsdxShape _coloredShape({
    required int id,
    required _DrawioColoredPart part,
    VsdxShadow shadow = VsdxShadow.disabled,
  }) {
    final locX = targetWidth / 2;
    final locY = targetHeight / 2;
    return _withLineUserCells(VsdxShape(
      id: id,
      name: 'Sheet.$id',
      pinX: locX,
      pinY: locY,
      width: targetWidth,
      height: targetHeight,
      locPinXInches: locX,
      locPinYInches: locY,
      fill: part.fill,
      line: part.line,
      shadow: shadow,
      geometries: <VsdxGeometry>[
        VsdxGeometry(
          noFill: !part.fill.hasFill,
          noLine: !part.line.hasLine,
          commands: part.commands,
        ),
      ],
      richText: const VsdxRichText(
        runs: <VsdxTextRun>[],
        textBlock: VsdxTextBlock(hideText: true),
      ),
    ));
  }

  VsdxShape _withLineUserCells(VsdxShape shape) {
    var next = shape;
    final join = shape.line.join;
    if (join != null) next = next.withDrawioLineJoin(join);
    if (_miterLimit != null && (shape.line.miterLimit - 4.0).abs() > 1e-9) {
      next = next.withDrawioMiterLimit(shape.line.miterLimit);
    }
    final custom = shape.line.customDashPattern;
    if (custom != null && custom.isNotEmpty) {
      next = next.withDrawioDashPattern(custom, fixed: shape.line.fixedDash);
    }
    return _withSketchUserCells(next);
  }

  VsdxShape _withSketchUserCells(VsdxShape shape) {
    if (!_sketchEnabled) return shape;
    var next = shape.withSketchEffect(true);
    if (_sketchFill != null && _sketchFill!.isNotEmpty) {
      next = next.withSketchFillStyle(VsdxSketchFillStyle.parse(_sketchFill));
    }
    if (_sketchGap != null) next = next.withSketchHachureGap(_sketchGap!);
    if (_sketchAngle != null) {
      next = next.withSketchHachureAngle(_sketchAngle!);
    }
    if (_sketchWeight != null && _sketchWeight! > 0) {
      next = next.withSketchFillWeight(_sketchWeight!);
    }
    if (_sketchJiggle != null) next = next.withSketchJiggle(_sketchJiggle!);
    return next;
  }

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
              ),
              paraStyle: VsdxParaStyle(
                horizontalAlign: _mxHorzAlign(run.align ?? label.align),
                indentLeftInches: run.marginLeft * scale,
                indentRightInches: run.marginRight * scale,
                spaceBeforeInches: run.marginTop * scale,
                spaceAfterInches: run.marginBottom * scale,
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
    return shape;
  }

  double _x(double source) => source * scaleX;
  double _y(double source) => (sourceHeight - source) * scaleY;
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
    required this.fontSize,
    required this.fontStyle,
    this.fontFamily,
    this.color,
    this.background,
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
  final double fontSize;
  final int fontStyle;
  final String? fontFamily;
  final VsdxColor? color;
  final VsdxColor? background;
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
}

class _DrawioColoredPart {
  const _DrawioColoredPart({
    required this.commands,
    required this.fill,
    required this.line,
    this.shadow = VsdxShadow.disabled,
  });

  final List<VsdxPathCommand> commands;
  final VsdxFill fill;
  final VsdxLine line;
  final VsdxShadow shadow;
}

/// mxStencil.parseColor hex / rgb, including CSS `#RGB`. Style keys such as
/// `fillColor2` return null so the parent keeps an editable FillForegnd.
VsdxColor? _mxGraphPaintColor(String? raw) {
  if (raw == null) return null;
  final token = raw.trim();
  if (token.isEmpty) return null;
  if (token.startsWith('#') && token.length == 4) {
    final hex = token.substring(1);
    if (RegExp(r'^[0-9a-fA-F]{3}$').hasMatch(hex)) {
      return VsdxColor.tryParse(
        '#${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}',
      );
    }
  }
  if (!token.startsWith('#') && RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(token)) {
    return VsdxColor.tryParse('#$token');
  }
  return VsdxColor.tryParse(token);
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

/// mxStencil.drawNode dashpattern: skip `none` and non-positive lengths.
List<double>? _parseMxDashPattern(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty || text.toLowerCase() == 'none') return null;
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

/// Visio LineCap: 0 round, 1 extended/butt, 2 square. libvisio
/// `_lineProperties` maps those onto svg:stroke-linecap.
LineCap? _mxLineCap(String? raw) => switch ((raw ?? '').trim().toLowerCase()) {
      'round' => LineCap.round,
      'square' => LineCap.square,
      'butt' || 'flat' => LineCap.extended,
      _ => null,
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

double _number(XmlElement element, String name, {double fallback = 0}) {
  final value = double.tryParse(element.getAttribute(name) ?? '');
  return value?.isFinite == true ? value! : fallback;
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
