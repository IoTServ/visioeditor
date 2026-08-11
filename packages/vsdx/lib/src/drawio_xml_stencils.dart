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
  List<VsdxPathCommand>? _pending;

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

    final name = element.getAttribute('name')?.trim();
    if (_geometries.isEmpty) {
      throw StateError('draw.io stencil ${name ?? id} produced no geometry');
    }
    return VsdxShape(
      id: id,
      name: name?.isNotEmpty == true ? name! : 'Sheet.$id',
      pinX: cx,
      pinY: cy,
      width: targetWidth,
      height: targetHeight,
      geometries: List<VsdxGeometry>.unmodifiable(_geometries),
      connectionPoints: _connectionPoints(),
    );
  }

  void _consume(XmlElement node) {
    switch (node.name.local) {
      case 'path':
        _pending = _decodePath(node);
        break;
      case 'rect':
        _pending = _decodeRect(node);
        break;
      case 'roundrect':
        _pending = _decodeRoundRect(node);
        break;
      case 'ellipse':
        _pending = _decodeEllipse(node);
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
      // save/restore and paint attributes affect colour, alpha or line style,
      // not geometry. The native stencil palette applies an editable project
      // style after decoding, while retaining every source contour.
      default:
        break;
    }
  }

  void _finish({required bool fill, required bool stroke}) {
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
    var sourceX = 0.0;
    var sourceY = 0.0;
    var startX = 0.0;
    var startY = 0.0;
    var hasStart = false;

    for (final command in path.childElements) {
      switch (command.name.local) {
        case 'move':
          sourceX = _number(command, 'x');
          sourceY = _number(command, 'y');
          startX = sourceX;
          startY = sourceY;
          hasStart = true;
          commands.add(MoveTo(_x(sourceX), _y(sourceY)));
          break;
        case 'line':
          sourceX = _number(command, 'x');
          sourceY = _number(command, 'y');
          commands.add(LineTo(_x(sourceX), _y(sourceY)));
          break;
        case 'curve':
          final x1 = _number(command, 'x1');
          final y1 = _number(command, 'y1');
          final x2 = _number(command, 'x2');
          final y2 = _number(command, 'y2');
          sourceX = _number(command, 'x3');
          sourceY = _number(command, 'y3');
          commands.add(CubBezTo(
            x: _x(sourceX),
            y: _y(sourceY),
            x1: _x(x1),
            y1: _y(y1),
            x2: _x(x2),
            y2: _y(y2),
          ));
          break;
        case 'quad':
          final x1 = _number(command, 'x1');
          final y1 = _number(command, 'y1');
          sourceX = _number(command, 'x2');
          sourceY = _number(command, 'y2');
          commands.add(QuadBezTo(
            x: _x(sourceX),
            y: _y(sourceY),
            x1: _x(x1),
            y1: _y(y1),
          ));
          break;
        case 'arc':
          final endX = _number(command, 'x');
          final endY = _number(command, 'y');
          final curves = _svgArcCurves(
            sourceX,
            sourceY,
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
          sourceX = endX;
          sourceY = endY;
          break;
        case 'close':
          if (hasStart && (sourceX != startX || sourceY != startY)) {
            commands.add(LineTo(_x(startX), _y(startY)));
          }
          sourceX = startX;
          sourceY = startY;
          break;
        case 'ellipse':
          commands.addAll(_decodeEllipse(command));
          break;
        default:
          break;
      }
    }
    return commands;
  }

  List<VsdxPathCommand> _decodeRect(XmlElement rect) {
    final left = _number(rect, 'x');
    final top = _number(rect, 'y');
    final right = left + _number(rect, 'w');
    final bottom = top + _number(rect, 'h');
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

  double _x(double source) => source * scaleX;
  double _y(double source) => (sourceHeight - source) * scaleY;
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

bool _flag(XmlElement element, String name) =>
    element.getAttribute(name) == '1' ||
    element.getAttribute(name)?.toLowerCase() == 'true';
