/// Import and export for diagrams.net / draw.io `.drawio` XML documents.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../model/connect.dart';
import '../model/document.dart';
import '../model/fill.dart';
import '../model/geometry.dart';
import '../model/line.dart';
import '../model/page.dart';
import '../model/shape.dart';
import '../model/shape_factory.dart';
import '../utils/color.dart';

/// Converts between draw.io's mxGraph XML and the editor's document model.
///
/// Imports both ordinary XML and the raw-deflate/base64 representation used by
/// diagrams.net. Exports deliberately use uncompressed XML: diagrams.net opens
/// it natively, while it remains diffable and recoverable by other tools.
class DrawioCodec {
  const DrawioCodec();

  static const double pixelsPerInch = 96;

  bool looksLikeDrawio(List<int> bytes) {
    final prefix = utf8.decode(
      bytes.take(math.min(bytes.length, 4096)).toList(growable: false),
      allowMalformed: true,
    );
    return RegExp(r'<\s*(?:mxfile|mxGraphModel)\b', caseSensitive: false)
        .hasMatch(prefix);
  }

  VsdxDocument decode(Uint8List bytes) {
    final source = utf8.decode(bytes, allowMalformed: false).trim();
    final xml = XmlDocument.parse(source);
    final root = xml.rootElement;
    final pages = <VsdxPage>[];

    if (root.name.local == 'mxGraphModel') {
      pages.add(_decodePage(root, id: 0, name: 'Page-1'));
    } else if (root.name.local == 'mxfile') {
      var pageId = 0;
      for (final diagram in root.childElements
          .where((element) => element.name.local == 'diagram')) {
        final model = _diagramModel(diagram);
        pages.add(_decodePage(
          model,
          id: pageId++,
          name: diagram.getAttribute('name') ?? 'Page-${pageId + 1}',
        ));
      }
    } else {
      throw const FormatException('Not a draw.io mxGraph document');
    }

    if (pages.isEmpty) {
      throw const FormatException('The draw.io document has no pages');
    }
    return VsdxDocument(
      pages: List<VsdxPage>.unmodifiable(pages),
      applicationName: 'diagrams.net',
    );
  }

  Uint8List encode(VsdxDocument document) {
    if (document.pages.isEmpty) {
      throw const FormatException('Cannot save a document with no pages');
    }
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element('mxfile', attributes: <String, String>{
      'host': 'app.diagrams.net',
      'agent': 'Visio Editor',
      'version': '24.7.17',
      'compressed': 'false',
      'pages': '${document.pages.length}',
    }, nest: () {
      for (var i = 0; i < document.pages.length; i++) {
        final page = document.pages[i];
        builder.element('diagram',
            attributes: <String, String>{
              'id': 'page-${page.id}',
              'name': page.name,
            },
            nest: () => _writePage(builder, page));
      }
    });
    return Uint8List.fromList(utf8.encode(builder.buildDocument().toXmlString(
          pretty: true,
          indent: '  ',
        )));
  }

  XmlElement _diagramModel(XmlElement diagram) {
    final embedded = diagram.childElements
        .where((element) => element.name.local == 'mxGraphModel')
        .firstOrNull;
    if (embedded != null) return embedded;

    final payload = diagram.innerText.trim();
    if (payload.isEmpty) {
      throw const FormatException('Empty draw.io page');
    }
    if (payload.startsWith('<')) {
      return XmlDocument.parse(payload).rootElement;
    }
    try {
      final compressed = base64.decode(payload.replaceAll(RegExp(r'\s+'), ''));
      final encodedXml = utf8.decode(Inflate(compressed).getBytes());
      final decodedXml = Uri.decodeComponent(encodedXml);
      return XmlDocument.parse(decodedXml).rootElement;
    } on Object catch (error) {
      throw FormatException('Invalid compressed draw.io page: $error');
    }
  }

  VsdxPage _decodePage(
    XmlElement model, {
    required int id,
    required String name,
  }) {
    final pageWidthPx = _number(model.getAttribute('pageWidth'), 850);
    final pageHeightPx = _number(model.getAttribute('pageHeight'), 1100);
    final width = math.max(pageWidthPx, 1) / pixelsPerInch;
    final height = math.max(pageHeightPx, 1) / pixelsPerInch;
    final cells = <String, XmlElement>{
      for (final cell in model.findAllElements('mxCell'))
        if ((cell.getAttribute('id') ?? '').isNotEmpty)
          cell.getAttribute('id')!: cell,
    };
    final ids = <String, int>{};
    var nextId = 1;
    for (final entry in cells.entries) {
      final cell = entry.value;
      if (cell.getAttribute('vertex') == '1' ||
          cell.getAttribute('edge') == '1') {
        ids[entry.key] = nextId++;
      }
    }

    final positions = <String, _Box>{};
    _Box positionFor(String cellId, [Set<String>? visiting]) {
      final cached = positions[cellId];
      if (cached != null) return cached;
      final cell = cells[cellId];
      if (cell == null) return const _Box(0, 0, 0, 0);
      final geometry = _geometry(cell);
      var x = _number(geometry?.getAttribute('x'), 0);
      var y = _number(geometry?.getAttribute('y'), 0);
      final w = _number(geometry?.getAttribute('width'), 80);
      final h = _number(geometry?.getAttribute('height'), 40);
      final parentId = cell.getAttribute('parent');
      final seen = visiting ?? <String>{};
      if (parentId != null &&
          parentId != '0' &&
          parentId != '1' &&
          seen.add(cellId)) {
        final parent = positionFor(parentId, seen);
        x += parent.x;
        y += parent.y;
      }
      return positions[cellId] = _Box(x, y, w, h);
    }

    final shapes = <VsdxShape>[];
    for (final entry in cells.entries) {
      final cell = entry.value;
      if (cell.getAttribute('vertex') != '1') continue;
      // mxGraph group cells are coordinate frames. Their children are emitted
      // as normal top-level shapes with the accumulated parent offset.
      final style = _style(cell.getAttribute('style'));
      final isGroup = style['group'] == '1' ||
          cells.values.any((candidate) =>
              candidate.getAttribute('parent') == entry.key &&
              candidate.getAttribute('vertex') == '1');
      if (isGroup && (cell.getAttribute('value') ?? '').isEmpty) continue;
      final box = positionFor(entry.key);
      final fill = _fill(style);
      final line = _line(style);
      final shapeId = ids[entry.key]!;
      final x = box.x / pixelsPerInch;
      final y = height - (box.y + box.height) / pixelsPerInch;
      final w = math.max(box.width / pixelsPerInch, 0.01);
      final h = math.max(box.height / pixelsPerInch, 0.01);
      final pinX = x + w / 2;
      final pinY = y + h / 2;
      final rawValue = cell.getAttribute('value') ?? '';
      final text = _plainText(rawValue);
      final shapeName = cell.getAttribute('id') ?? 'Shape-$shapeId';

      VsdxShape shape;
      if (style['shape'] == 'text' ||
          (style['strokeColor'] == 'none' && style['fillColor'] == 'none')) {
        shape = VsdxShapeFactory.textBox(
          id: shapeId,
          pinX: pinX,
          pinY: pinY,
          width: w,
          height: h,
          text: text,
          name: shapeName,
        );
      } else if (style.containsKey('ellipse')) {
        shape = VsdxShapeFactory.ellipse(
          id: shapeId,
          pinX: pinX,
          pinY: pinY,
          width: w,
          height: h,
          fill: fill,
          line: line,
          name: shapeName,
        );
      } else if (style.containsKey('rhombus')) {
        shape = VsdxShapeFactory.polygon(
          id: shapeId,
          pinX: pinX,
          pinY: pinY,
          width: w,
          height: h,
          unit: const <Offset2D>[
            Offset2D(0.5, 0),
            Offset2D(1, 0.5),
            Offset2D(0.5, 1),
            Offset2D(0, 0.5),
          ],
          fill: fill,
          line: line,
          name: shapeName,
        );
      } else {
        final rounded = style['rounded'] == '1';
        shape = rounded
            ? VsdxShapeFactory.roundedRectangle(
                id: shapeId,
                pinX: pinX,
                pinY: pinY,
                width: w,
                height: h,
                fill: fill,
                line: line,
                name: shapeName,
              )
            : VsdxShapeFactory.rectangle(
                id: shapeId,
                pinX: pinX,
                pinY: pinY,
                width: w,
                height: h,
                fill: fill,
                line: line,
                name: shapeName,
              );
      }
      shape = shape.copyWith(
        text: text.isEmpty ? null : text,
        angleRad: _number(style['rotation'], 0) * math.pi / 180,
        locked: cell.getAttribute('locked') == '1' || style['locked'] == '1',
      );
      shapes.add(shape);
    }

    final connects = <VsdxConnect>[];
    for (final entry in cells.entries) {
      final cell = entry.value;
      if (cell.getAttribute('edge') != '1') continue;
      final geometry = _geometry(cell);
      final sourceKey = cell.getAttribute('source');
      final targetKey = cell.getAttribute('target');
      final source = sourceKey == null ? null : ids[sourceKey];
      final target = targetKey == null ? null : ids[targetKey];
      final sourcePoint = _point(geometry, 'sourcePoint', height);
      final targetPoint = _point(geometry, 'targetPoint', height);
      final sourceShape = source == null
          ? null
          : shapes.where((shape) => shape.id == source).firstOrNull;
      final targetShape = target == null
          ? null
          : shapes.where((shape) => shape.id == target).firstOrNull;
      final begin = sourcePoint ??
          (sourceShape == null
              ? const Offset2D(0, 0)
              : Offset2D(sourceShape.pinX, sourceShape.pinY));
      final end = targetPoint ??
          (targetShape == null
              ? Offset2D(begin.x + 1, begin.y)
              : Offset2D(targetShape.pinX, targetShape.pinY));
      final style = _style(cell.getAttribute('style'));
      final edgeId = ids[entry.key]!;
      var edge = VsdxShapeFactory.line(
        id: edgeId,
        ax: begin.x,
        ay: begin.y,
        bx: end.x,
        by: end.y,
        line: _line(style, edge: true),
        name: entry.key,
      );
      final points = <Offset2D>[];
      if (geometry != null) {
        for (final array in geometry.childElements
            .where((element) => element.name.local == 'Array')) {
          if (array.getAttribute('as') != 'points') continue;
          for (final point in array.childElements
              .where((element) => element.name.local == 'mxPoint')) {
            points.add(_decodePoint(point, height));
          }
        }
      }
      edge = edge.copyWith(
        text: _plainText(cell.getAttribute('value') ?? '').nullIfEmpty,
        straightRoute:
            style['edgeStyle'] == 'none' || style['noEdgeStyle'] == '1',
        curved: style['curved'] == '1',
        rounded: style['rounded'] == '1',
        waypoints: points,
      );
      shapes.add(edge);
      if (source != null && sourceShape != null) {
        connects.add(VsdxConnect(
          fromSheetId: edgeId,
          fromCell: 'BeginX',
          fromPart: 9,
          toSheetId: source,
          toCell: 'PinX',
          toPart: 3,
        ));
      }
      if (target != null && targetShape != null) {
        connects.add(VsdxConnect(
          fromSheetId: edgeId,
          fromCell: 'EndX',
          fromPart: 12,
          toSheetId: target,
          toCell: 'PinX',
          toPart: 3,
        ));
      }
    }

    final page = VsdxPage(
      id: id,
      name: name,
      widthInches: width,
      heightInches: height,
      shapes: List<VsdxShape>.unmodifiable(shapes),
      connects: List<VsdxConnect>.unmodifiable(connects),
      backgroundColor: VsdxColor.tryParse(model.getAttribute('background')),
    );
    return page.rerouteConnectors();
  }

  void _writePage(XmlBuilder builder, VsdxPage page) {
    builder.element('mxGraphModel', attributes: <String, String>{
      'dx': _n(page.widthInches * pixelsPerInch),
      'dy': _n(page.heightInches * pixelsPerInch),
      'grid': '1',
      'gridSize': '10',
      'guides': '1',
      'tooltips': '1',
      'connect': '1',
      'arrows': '1',
      'fold': '1',
      'page': '1',
      'pageScale': '1',
      'pageWidth': _n(page.widthInches * pixelsPerInch),
      'pageHeight': _n(page.heightInches * pixelsPerInch),
      'math': '0',
      'shadow': '0',
    }, nest: () {
      builder.element('root', nest: () {
        builder
            .element('mxCell', attributes: const <String, String>{'id': '0'});
        builder.element('mxCell', attributes: const <String, String>{
          'id': '1',
          'parent': '0',
        });
        for (final shape in page.shapes.where((shape) => !shape.is1D)) {
          _writeVertex(builder, page, shape);
        }
        for (final shape in page.shapes.where((shape) => shape.is1D)) {
          _writeEdge(builder, page, shape);
        }
      });
    });
  }

  void _writeVertex(XmlBuilder builder, VsdxPage page, VsdxShape shape) {
    final x = (shape.pinX - shape.width / 2) * pixelsPerInch;
    final y =
        (page.heightInches - shape.pinY - shape.height / 2) * pixelsPerInch;
    builder.element('mxCell', attributes: <String, String>{
      'id': 'v${shape.id}',
      'value': shape.text ?? shape.richText.plainText,
      'style': _vertexStyle(shape),
      'vertex': '1',
      'parent': '1',
      if (shape.locked) 'locked': '1',
    }, nest: () {
      builder.element('mxGeometry', attributes: <String, String>{
        'x': _n(x),
        'y': _n(y),
        'width': _n(shape.width.abs() * pixelsPerInch),
        'height': _n(shape.height.abs() * pixelsPerInch),
        'as': 'geometry',
      });
    });
  }

  void _writeEdge(XmlBuilder builder, VsdxPage page, VsdxShape shape) {
    final links = page.connectIndex.forConnector(shape.id);
    final source = links.where((connect) => connect.isBegin).firstOrNull;
    final target = links.where((connect) => connect.isEnd).firstOrNull;
    final route = page.drawnConnectorPagePolyline(shape);
    final begin = route.isEmpty
        ? Offset2D(shape.beginX ?? shape.pinX, shape.beginY ?? shape.pinY)
        : route.first;
    final end = route.isEmpty
        ? Offset2D(shape.endX ?? shape.pinX, shape.endY ?? shape.pinY)
        : route.last;
    builder.element('mxCell', attributes: <String, String>{
      'id': 'e${shape.id}',
      'value': shape.text ?? shape.richText.plainText,
      'style': _edgeStyle(shape),
      'edge': '1',
      'parent': '1',
      if (source != null) 'source': 'v${source.toSheetId}',
      if (target != null) 'target': 'v${target.toSheetId}',
    }, nest: () {
      builder.element('mxGeometry', attributes: const <String, String>{
        'relative': '1',
        'as': 'geometry',
      }, nest: () {
        if (source == null) _writePoint(builder, begin, page, 'sourcePoint');
        if (target == null) _writePoint(builder, end, page, 'targetPoint');
        final interior = shape.waypoints.isNotEmpty
            ? shape.waypoints
            : (route.length > 2
                ? route.sublist(1, route.length - 1)
                : const <Offset2D>[]);
        if (interior.isNotEmpty) {
          builder.element('Array',
              attributes: const <String, String>{'as': 'points'}, nest: () {
            for (final point in interior) {
              _writePoint(builder, point, page, null);
            }
          });
        }
      });
    });
  }

  void _writePoint(
      XmlBuilder builder, Offset2D point, VsdxPage page, String? as) {
    builder.element('mxPoint', attributes: <String, String>{
      'x': _n(point.x * pixelsPerInch),
      'y': _n((page.heightInches - point.y) * pixelsPerInch),
      if (as != null) 'as': as,
    });
  }

  XmlElement? _geometry(XmlElement cell) => cell.childElements
      .where((element) => element.name.local == 'mxGeometry')
      .firstOrNull;

  Offset2D? _point(XmlElement? geometry, String as, double pageHeight) {
    if (geometry == null) return null;
    final point = geometry.childElements
        .where((element) =>
            element.name.local == 'mxPoint' && element.getAttribute('as') == as)
        .firstOrNull;
    return point == null ? null : _decodePoint(point, pageHeight);
  }

  Offset2D _decodePoint(XmlElement point, double pageHeight) => Offset2D(
        _number(point.getAttribute('x'), 0) / pixelsPerInch,
        pageHeight - _number(point.getAttribute('y'), 0) / pixelsPerInch,
      );

  Map<String, String> _style(String? raw) {
    final result = <String, String>{};
    for (final token in (raw ?? '').split(';')) {
      if (token.isEmpty) continue;
      final equals = token.indexOf('=');
      if (equals < 0) {
        result[token] = '1';
      } else {
        result[token.substring(0, equals)] = token.substring(equals + 1);
      }
    }
    return result;
  }

  VsdxFill _fill(Map<String, String> style) {
    final raw = style['fillColor'];
    if (raw == 'none') return const VsdxFill(pattern: 0);
    final opacity = _number(style['fillOpacity'] ?? style['opacity'], 100);
    return VsdxFill(
      foreground: VsdxColor.tryParse(raw) ?? VsdxColor.white,
      foregroundTransparency: 1 - opacity.clamp(0, 100) / 100,
    );
  }

  VsdxLine _line(Map<String, String> style, {bool edge = false}) {
    final raw = style['strokeColor'];
    final opacity = _number(style['strokeOpacity'] ?? style['opacity'], 100);
    return VsdxLine(
      color: VsdxColor.tryParse(raw) ?? VsdxColor.black,
      pattern: raw == 'none' ? 0 : (style['dashed'] == '1' ? 2 : 1),
      weightInches:
          math.max(_number(style['strokeWidth'], 1), 0.1) / pixelsPerInch,
      transparency: 1 - opacity.clamp(0, 100) / 100,
      beginArrow: edge ? _arrow(style['startArrow']) : 0,
      endArrow: edge ? _arrow(style['endArrow'], defaultArrow: 4) : 0,
      roundingInches: style['rounded'] == '1' ? 6 / pixelsPerInch : 0,
    );
  }

  int _arrow(String? value, {int defaultArrow = 0}) => switch (value) {
        null => defaultArrow,
        'none' => 0,
        'open' => 2,
        'oval' => 10,
        'diamond' || 'diamondThin' => 8,
        _ => 4,
      };

  String _vertexStyle(VsdxShape shape) {
    final parts = <String>[];
    if (_isEllipse(shape)) parts.add('ellipse');
    if (_isDiamond(shape)) parts.add('rhombus');
    if (shape.fill.pattern == 0) {
      parts.add('fillColor=none');
    } else {
      parts.add('fillColor=${_color(shape.fill.foreground, VsdxColor.white)}');
      if (shape.fill.foregroundTransparency > 0) {
        parts.add(
            'fillOpacity=${_n((1 - shape.fill.foregroundTransparency) * 100)}');
      }
    }
    parts.add(shape.line.pattern == 0
        ? 'strokeColor=none'
        : 'strokeColor=${_color(shape.line.color, VsdxColor.black)}');
    parts.add('strokeWidth=${_n(shape.line.weightInches * pixelsPerInch)}');
    if (shape.line.pattern > 1) parts.add('dashed=1');
    if (shape.angleRad.abs() > 1e-9) {
      parts.add('rotation=${_n(shape.angleRad * 180 / math.pi)}');
    }
    return '${parts.join(';')};';
  }

  String _edgeStyle(VsdxShape shape) {
    final parts = <String>[
      shape.straightRoute ? 'edgeStyle=none' : 'edgeStyle=orthogonalEdgeStyle',
      'rounded=${shape.rounded ? 1 : 0}',
      'curved=${shape.curved ? 1 : 0}',
      'html=1',
      shape.line.pattern == 0
          ? 'strokeColor=none'
          : 'strokeColor=${_color(shape.line.color, VsdxColor.black)}',
      'strokeWidth=${_n(shape.line.weightInches * pixelsPerInch)}',
      if (shape.line.pattern > 1) 'dashed=1',
      'startArrow=${_drawioArrow(shape.line.beginArrow)}',
      'endArrow=${_drawioArrow(shape.line.endArrow)}',
    ];
    return '${parts.join(';')};';
  }

  String _drawioArrow(int arrow) => switch (arrow) {
        0 => 'none',
        2 => 'open',
        8 => 'diamond',
        10 => 'oval',
        _ => 'classic',
      };

  bool _isEllipse(VsdxShape shape) => shape.geometries.any(
      (geometry) => geometry.commands.any((command) => command is EllipseCmd));

  bool _isDiamond(VsdxShape shape) {
    final commands =
        shape.geometries.expand((geometry) => geometry.commands).toList();
    if (commands.length < 5 || commands.first is! MoveTo) return false;
    final first = commands.first as MoveTo;
    return (first.x - shape.width / 2).abs() < 1e-6 && first.y.abs() < 1e-6;
  }

  String _color(VsdxColor? color, VsdxColor fallback) {
    final value = color ?? fallback;
    final rgb = (value.red << 16) | (value.green << 8) | value.blue;
    return '#${rgb.toRadixString(16).padLeft(6, '0')}';
  }

  String _plainText(String value) => value
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(?:div|p)>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .trim();

  double _number(String? raw, double fallback) =>
      double.tryParse(raw ?? '') ?? fallback;

  String _n(double value) {
    if (!value.isFinite) return '0';
    final rounded = value.roundToDouble();
    if ((value - rounded).abs() < 1e-9) return rounded.toInt().toString();
    return value
        .toStringAsFixed(4)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}

class _Box {
  const _Box(this.x, this.y, this.width, this.height);
  final double x;
  final double y;
  final double width;
  final double height;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
