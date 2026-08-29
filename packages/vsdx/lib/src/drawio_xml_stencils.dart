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
  List<VsdxPathCommand>? _pending;
  double _fontSize = 12;
  int _fontStyle = 0;
  bool _dashed = false;
  bool _solidPaintBeforeDash = false;
  String? _rasterPart;
  String? _rasterMime;
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
    if (_geometries.isEmpty && _labels.isEmpty) {
      throw StateError(
        'draw.io stencil ${sourceName ?? id} produced no geometry',
      );
    }
    if (_geometries.isEmpty) {
      // Text-only mxGraph painters (some JS captures) still need a hit box
      // libvisio can attach Text children to.
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
    final children = <VsdxShape>[
      for (var i = 0; i < _labels.length; i++)
        _labelShape(id: id + 1 + i, label: _labels[i]),
    ];
    // Use Sheet.N like factory / chart stencils. The catalog keeps the
    // human-readable stencil title for the palette; putting it on shape.name
    // would paint as a label fallback when text is empty. Authored mxGraph
    // <text> glyphs (IEC AND, calendar days, …) become children so
    // LibreOffice's libvisio text collector still paints them.
    return VsdxShape(
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
      fill: _rasterPart != null
          ? const VsdxFill(pattern: 0)
          : VsdxFill.defaultFill,
      line: _rasterPart != null
          ? const VsdxLine(pattern: 0)
          : (_dashed && !_solidPaintBeforeDash
              ? const VsdxLine(pattern: 2)
              : VsdxLine.defaultLine),
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
    );
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
        _dashed = true;
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
        _fontStyle = _number(node, 'style').round();
        break;
      case 'text':
        final str = node.getAttribute('str') ?? '';
        if (str.isNotEmpty) {
          _labels.add(_DrawioStencilLabel(
            text: str,
            x: _number(node, 'x'),
            y: _number(node, 'y'),
            align: node.getAttribute('align') ?? 'left',
            valign: node.getAttribute('valign') ?? 'top',
            vertical: node.getAttribute('vertical') == '1',
            rotationDegrees: _number(node, 'rotation'),
            fontSize: _fontSize,
            fontStyle: _fontStyle,
          ));
        }
        break;
      case 'image':
        _consumeRaster(node);
        break;
      // save/restore and remaining paint attributes affect colour, alpha or
      // line style, not geometry. The native stencil palette applies an
      // editable project style after decoding, while retaining every source
      // contour. Authored <text> is kept as a child so Draw paints it.
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

  void _finish({required bool fill, required bool stroke}) {
    if (!_dashed) _solidPaintBeforeDash = true;
    final commands = _pending;
    _pending = null;
    if (commands == null || commands.isEmpty) return;
    _geometries.add(VsdxGeometry(
      commands: List<VsdxPathCommand>.unmodifiable(commands),
      noFill: !fill,
      noLine: !stroke,
      ix: _geometries.length,
    ));
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

  VsdxShape _labelShape({
    required int id,
    required _DrawioStencilLabel label,
  }) {
    final fontInches =
        math.max(0.04, label.fontSize * math.min(scaleX, scaleY));
    final width =
        math.max(fontInches * 1.2, label.text.length * fontInches * 0.62);
    final height = fontInches * 1.4;
    final x = _x(label.x);
    final y = _y(label.y);
    final pinX = switch (label.align) {
      'left' => x + width / 2,
      'right' => x - width / 2,
      _ => x,
    };
    final pinY = switch (label.valign) {
      'bottom' => y + height / 2,
      'middle' => y,
      _ => y - height / 2,
    };
    final horz = switch (label.align) {
      'center' => VsdxHorzAlign.center,
      'right' => VsdxHorzAlign.right,
      _ => VsdxHorzAlign.left,
    };
    final vert = switch (label.valign) {
      'bottom' => VsdxVertAlign.bottom,
      'middle' => VsdxVertAlign.middle,
      _ => VsdxVertAlign.top,
    };
    var angle = -label.rotationDegrees * math.pi / 180;
    if (label.vertical) angle -= math.pi / 2;
    return VsdxShape(
      id: id,
      name: 'Sheet.$id',
      pinX: pinX,
      pinY: pinY,
      width: width,
      height: height,
      text: label.text,
      richText: VsdxRichText(
        runs: <VsdxTextRun>[
          VsdxTextRun(
            text: label.text,
            charStyle: VsdxCharStyle(
              fontSizeInches: fontInches,
              style: VsdxFontStyle(
                bold: (label.fontStyle & 1) != 0,
                italic: (label.fontStyle & 2) != 0,
              ),
              underline: (label.fontStyle & 4) != 0,
            ),
            paraStyle: VsdxParaStyle(horizontalAlign: horz),
          ),
        ],
        textBlock: VsdxTextBlock(
          verticalAlign: vert,
          marginLeftInches: 0,
          marginRightInches: 0,
          marginTopInches: 0,
          marginBottomInches: 0,
          angleRad: angle,
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
  }

  double _x(double source) => source * scaleX;
  double _y(double source) => (sourceHeight - source) * scaleY;
}

class _DrawioStencilLabel {
  const _DrawioStencilLabel({
    required this.text,
    required this.x,
    required this.y,
    required this.align,
    required this.valign,
    required this.vertical,
    required this.rotationDegrees,
    required this.fontSize,
    required this.fontStyle,
  });

  final String text;
  final double x;
  final double y;
  final String align;
  final String valign;
  final bool vertical;
  final double rotationDegrees;
  final double fontSize;
  final int fontStyle;
}

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
