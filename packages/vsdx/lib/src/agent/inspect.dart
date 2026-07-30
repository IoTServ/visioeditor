/// Read-only diagnostics over a parsed document: [validateDocument] (a fast
/// structural lint) and [explainDocument] (reverse a `.vsdx` into a structured
/// Markdown description — the mirror of building one from a spec).
library;

import 'package:collection/collection.dart';
import 'package:vsdx/vsdx.dart';

/// A single validation finding.
class ValidationIssue {
  const ValidationIssue(this.severity, this.message);
  final String severity; // 'error' | 'warning'
  final String message;
  @override
  String toString() => '[$severity] $message';
}

/// Structural lint: duplicate ids, dangling connects, off-page shapes,
/// overlapping 2-D shapes. Cheap; safe to run before every export.
List<ValidationIssue> validateDocument(VsdxDocument doc) {
  final issues = <ValidationIssue>[];
  for (var pi = 0; pi < doc.pages.length; pi++) {
    final page = doc.pages[pi];
    final label = 'page ${pi + 1} "${page.name}"';

    // Duplicate shape ids anywhere in the tree (including group children).
    final seen = <int>{};
    for (final s in _flattenShapes(page.shapes)) {
      if (!seen.add(s.id)) {
        issues.add(ValidationIssue('error', '$label: duplicate shape id ${s.id}'));
      }
    }

    // Dangling BackPage (underlay id no longer in the document).
    final bgId = page.backgroundPageId;
    if (bgId != null && doc.pageById(bgId) == null) {
      issues.add(ValidationIssue(
        'error',
        '$label: backgroundPageId $bgId is missing',
      ));
    }

    // Dangling connects (reference a shape that no longer exists).
    for (final c in page.connects) {
      if (page.findShapeById(c.fromSheetId) == null) {
        issues.add(ValidationIssue('error',
            '$label: connect from missing shape ${c.fromSheetId}'));
      }
      if (page.findShapeById(c.toSheetId) == null) {
        issues.add(ValidationIssue('error',
            '$label: connect to missing shape ${c.toSheetId}'));
      }
    }

    // Off-page 2-D shapes (fully outside the page rect).
    for (final s in page.shapes) {
      if (s.is1D) continue;
      final left = s.pinX - s.width / 2;
      final right = s.pinX + s.width / 2;
      final bottom = s.pinY - s.height / 2;
      final top = s.pinY + s.height / 2;
      if (right < 0 ||
          top < 0 ||
          left > page.widthInches ||
          bottom > page.heightInches) {
        issues.add(ValidationIssue(
            'warning', '$label: shape ${s.id} is off-page'));
      }
    }

    // Overlapping 2-D shapes (bounding-box; ignores tiny slivers).
    final boxes = <VsdxShape>[for (final s in page.shapes) if (!s.is1D) s];
    for (var i = 0; i < boxes.length; i++) {
      for (var j = i + 1; j < boxes.length; j++) {
        if (_overlaps(boxes[i], boxes[j])) {
          issues.add(ValidationIssue('warning',
              '$label: shapes ${boxes[i].id} and ${boxes[j].id} overlap'));
        }
      }
    }
  }
  return issues;
}

bool _overlaps(VsdxShape a, VsdxShape b) {
  const pad = 0.02; // ignore touching edges / tiny slivers
  final ax0 = a.pinX - a.width / 2, ax1 = a.pinX + a.width / 2;
  final ay0 = a.pinY - a.height / 2, ay1 = a.pinY + a.height / 2;
  final bx0 = b.pinX - b.width / 2, bx1 = b.pinX + b.width / 2;
  final by0 = b.pinY - b.height / 2, by1 = b.pinY + b.height / 2;
  final ix = (ax1 < bx0 + pad || bx1 < ax0 + pad);
  final iy = (ay1 < by0 + pad || by1 < ay0 + pad);
  return !ix && !iy;
}

/// A compact, machine-readable listing of a page's shapes — the ids/labels an
/// Agent needs before editing (via `apply_ops` / the convenience tools).
///
/// Walks nested group children so members remain visible after Group. Each
/// entry may include `parentId` when the shape is nested.
List<Map<String, dynamic>> listShapes(VsdxDocument doc, {int pageIndex = 0}) {
  if (doc.pages.isEmpty) return const <Map<String, dynamic>>[];
  final page = doc.pages[pageIndex.clamp(0, doc.pages.length - 1)];
  double r(double v) => double.parse(v.toStringAsFixed(3));
  final out = <Map<String, dynamic>>[];

  void walk(Iterable<VsdxShape> shapes, int? parentId) {
    for (final s in shapes) {
      final pin = page.shapePinPage(s.id);
      out.add(<String, dynamic>{
        'id': s.id,
        'text': (s.text ?? s.richText.plainText).trim().replaceAll('\n', ' '),
        'connector': s.isGlueableConnector,
        if (s.isGlueableConnector) ..._connectorJson(page, s, r),
        if (s.isInk) 'ink': true,
        'group': s.children.isNotEmpty,
        if (VsdxPage.isDropContainer(s)) 'container': true,
        if (s.collapsible || s.shapeKind.isFoldable) ...<String, dynamic>{
          'foldable': s.collapsible,
          'collapsed': s.collapsed,
        },
        'x': r(pin.x),
        'y': r(pin.y),
        'w': r(s.width),
        'h': r(s.height),
        if (s.layerMemberIds.isNotEmpty) 'layerIds': s.layerMemberIds,
        if (s.userProperties.isNotEmpty)
          'data': <Map<String, dynamic>>[
            for (final property in s.userProperties)
              _userPropertyJson(property),
          ],
        if (s.hyperlinks.isNotEmpty)
          'links': <Map<String, dynamic>>[
            for (final link in s.hyperlinks) _hyperlinkJson(link),
          ],
        if (s.connectionPoints.isNotEmpty)
          'connectionPoints': _connectionPointsJson(page, s, r),
        if (parentId != null) 'parentId': parentId,
      });
      if (s.children.isNotEmpty) walk(s.children, s.id);
    }
  }

  walk(page.shapes, null);
  return out;
}

List<Map<String, dynamic>> _connectionPointsJson(
  VsdxPage page,
  VsdxShape shape,
  double Function(double) round,
) =>
    <Map<String, dynamic>>[
      for (var i = 0; i < shape.connectionPoints.length; i++)
        () {
          final point = shape.connectionPoints[i];
          final pagePoint = page.localToPageDeep(shape.id, point.offset);
          return <String, dynamic>{
            'index': i,
            'x': round(point.x),
            'y': round(point.y),
            'pageX': round(pagePoint.x),
            'pageY': round(pagePoint.y),
            'dirX': round(point.dirX),
            'dirY': round(point.dirY),
            'type': point.type,
            'autoGen': point.autoGen,
            if (point.prompt != null) 'prompt': point.prompt,
          };
        }(),
    ];

Map<String, dynamic> _connectorJson(
  VsdxPage page,
  VsdxShape connector,
  double Function(double) round,
) {
  final parentId = page.findParentId(connector.id);
  Offset2D toPage(double x, double y) => parentId == null
      ? Offset2D(x, y)
      : page.localToPageDeep(parentId, Offset2D(x, y));
  final beginPoint = toPage(
    connector.beginX ?? connector.pinX,
    connector.beginY ?? connector.pinY,
  );
  final endPoint = toPage(
    connector.endX ?? connector.pinX,
    connector.endY ?? connector.pinY,
  );
  final connects = page.connectIndex.forConnector(connector.id);
  final beginConnect = connects.where((connect) => connect.isBegin).firstOrNull;
  final endConnect = connects.where((connect) => connect.isEnd).firstOrNull;

  Map<String, dynamic> endpoint(
    Offset2D point,
    VsdxConnect? connect,
  ) =>
      <String, dynamic>{
        'x': round(point.x),
        'y': round(point.y),
        if (connect != null) 'targetId': connect.toSheetId,
        if (VsdxPage.fixedConnectionIndex(connect) case final index?)
          'connectionPoint': index,
      };

  return <String, dynamic>{
    'route': connector.curved
        ? 'curved'
        : connector.straightRoute
            ? 'straight'
            : 'orthogonal',
    'rounded': connector.rounded,
    'begin': endpoint(beginPoint, beginConnect),
    'end': endpoint(endPoint, endConnect),
    'waypoints': <Map<String, dynamic>>[
      for (final point in connector.waypoints)
        () {
          final pagePoint =
              parentId == null ? point : page.localToPageDeep(parentId, point);
          return <String, dynamic>{
            'x': round(pagePoint.x),
            'y': round(pagePoint.y),
          };
        }(),
    ],
  };
}

Map<String, dynamic> _userPropertyJson(VsdxUserProperty property) =>
    <String, dynamic>{
      'name': property.name,
      if (property.label != null) 'label': property.label,
      if (property.value != null) 'value': property.value,
      if (property.valueFormula != null) 'valueFormula': property.valueFormula,
      if (property.prompt != null) 'prompt': property.prompt,
      if (property.format != null) 'format': property.format,
      if (property.formatFormula != null)
        'formatFormula': property.formatFormula,
      'type': property.type,
      if (property.sortKey != null) 'sortKey': property.sortKey,
      if (property.invisible) 'invisible': true,
      if (property.verify) 'verify': true,
      if (property.ask) 'ask': true,
      if (property.dataLinked) 'dataLinked': true,
      if (property.langId != null) 'langId': property.langId,
      if (property.calendar != null) 'calendar': property.calendar,
    };

Map<String, dynamic> _hyperlinkJson(VsdxHyperlink link) => <String, dynamic>{
      'id': link.id,
      if (link.description != null) 'description': link.description,
      if (link.address != null) 'address': link.address,
      if (link.addressFormula != null) 'addressFormula': link.addressFormula,
      if (link.subAddress != null) 'subAddress': link.subAddress,
      if (link.effectiveTarget case final target?) 'target': target,
      if (link.extraInfo != null) 'extraInfo': link.extraInfo,
      if (link.frame != null) 'frame': link.frame,
      if (link.newWindow) 'newWindow': true,
      if (link.isDefault) 'default': true,
      if (link.invisible) 'invisible': true,
      if (link.sortKey != null) 'sortKey': link.sortKey,
    };

/// Machine-readable layer inventory for one page.
///
/// Layer ids are stable Visio row ids; [index] is the current display order.
/// [shapeIds] contains explicit memberships (including nested group members).
List<Map<String, dynamic>> listLayers(
  VsdxDocument doc, {
  int pageIndex = 0,
}) {
  if (doc.pages.isEmpty) return const <Map<String, dynamic>>[];
  final page = doc.pages[pageIndex.clamp(0, doc.pages.length - 1)];
  final allShapes = _flattenShapes(page.shapes).toList();

  return <Map<String, dynamic>>[
    for (var i = 0; i < page.layers.length; i++)
      () {
        final layer = page.layers[i];
        final ids = <int>[
          for (final shape in allShapes)
            if (shape.layerMemberIds.contains(layer.id)) shape.id,
        ];
        return <String, dynamic>{
          'index': i,
          'id': layer.id,
          'name': layer.name,
          'visible': layer.visible,
          'locked': layer.locked,
          'print': layer.print,
          'active': layer.active,
          'snap': layer.snap,
          'glue': layer.glue,
          'shapes': ids.length,
          'shapeIds': ids,
          if (layer.color case final color?) 'color': _colorHex(color),
          if (layer.colorTrans != 0) 'colorTransparency': layer.colorTrans,
          if (layer.nameUniv != null) 'nameUniv': layer.nameUniv,
          if (layer.status != 0) 'status': layer.status,
        };
      }(),
  ];
}

/// Machine-readable page-tab inventory for file and live Agent workflows.
///
/// Page ids are stable Visio ids (used by `backgroundPageId`); indices are the
/// current draw.io-style tab order and therefore may change after move/delete.
List<Map<String, dynamic>> listPages(VsdxDocument doc) {
  double r(double v) => double.parse(v.toStringAsFixed(3));

  return <Map<String, dynamic>>[
    for (var i = 0; i < doc.pages.length; i++)
      <String, dynamic>{
        'index': i,
        'id': doc.pages[i].id,
        'name': doc.pages[i].name,
        'width': r(doc.pages[i].widthInches),
        'height': r(doc.pages[i].heightInches),
        'shapes': listShapes(doc, pageIndex: i).length,
        'isBackground': doc.pages[i].isBackgroundPage,
        if (doc.pages[i].backgroundPageId != null)
          'backgroundPageId': doc.pages[i].backgroundPageId,
        if (doc.pages[i].backgroundColor case final color?)
          'background': _colorHex(color),
      },
  ];
}

String _colorHex(VsdxColor color) {
  String byte(int value) =>
      value.toRadixString(16).padLeft(2, '0').toUpperCase();
  final rgb = '${byte(color.red)}${byte(color.green)}${byte(color.blue)}';
  return color.alpha == 0xFF ? '#$rgb' : '#$rgb${byte(color.alpha)}';
}

/// Reverse a document into structured Markdown (components + relations),
/// suitable for a README / PR summary.
String explainDocument(VsdxDocument doc) {
  final b = StringBuffer();
  b.writeln('# ${doc.title ?? 'Visio drawing'}');
  b.writeln();
  for (var pi = 0; pi < doc.pages.length; pi++) {
    final page = doc.pages[pi];
    final all = <VsdxShape>[..._flattenShapes(page.shapes)];
    // Leaf 2-D shapes (skip group shells) + top-level connectors.
    final nodes = <VsdxShape>[
      for (final s in all)
        if (!s.is1D && s.children.isEmpty) s,
    ];
    final edges = <VsdxShape>[
      for (final s in all)
        if (s.isGlueableConnector) s,
    ];
    b.writeln('## Page ${pi + 1}: ${page.name}');
    b.writeln();
    b.writeln('- Size: ${page.widthInches.toStringAsFixed(2)} × '
        '${page.heightInches.toStringAsFixed(2)} in');
    b.writeln('- Shapes: ${nodes.length} · Connectors: ${edges.length}');
    b.writeln();

    if (nodes.isNotEmpty) {
      b.writeln('### Shapes');
      b.writeln();
      for (final s in nodes) {
        final text = _text(s);
        b.writeln('- `#${s.id}` ${text.isEmpty ? '(unlabeled)' : text}');
      }
      b.writeln();
    }

    final labeled = <String>[for (final s in nodes) if (_text(s).isNotEmpty) '${s.id}'];
    if (edges.isNotEmpty) {
      b.writeln('### Connections');
      b.writeln();
      final index = page.connectIndex;
      for (final e in edges) {
        final ends = index.forConnector(e.id);
        final from = ends.where((c) => c.isBegin).map((c) => c.toSheetId).firstOrNull;
        final to = ends.where((c) => c.isEnd).map((c) => c.toSheetId).firstOrNull;
        final label = _text(e);
        final arrow = label.isEmpty ? '—→' : '—$label→';
        b.writeln('- ${_ref(page, from)} $arrow ${_ref(page, to)}');
      }
      b.writeln();
    } else if (labeled.length > 1) {
      b.writeln('_No connectors._');
      b.writeln();
    }
  }
  return b.toString();
}

String _text(VsdxShape s) {
  final t = s.text ?? s.richText.plainText;
  return t.trim().replaceAll('\n', ' ');
}

Iterable<VsdxShape> _flattenShapes(Iterable<VsdxShape> roots) sync* {
  for (final s in roots) {
    yield s;
    if (s.children.isNotEmpty) yield* _flattenShapes(s.children);
  }
}

String _ref(VsdxPage page, int? id) {
  if (id == null) return '(free)';
  final s = page.findShapeById(id);
  final t = s == null ? '' : _text(s);
  return t.isEmpty ? '#$id' : '"$t"';
}
