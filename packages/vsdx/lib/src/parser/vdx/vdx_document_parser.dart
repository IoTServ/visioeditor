/// Visio 2003 XML (VDX / VSX / VTX) importer.
///
/// DiagramML stores the same ShapeSheet data as VSDX, but expands
/// `<Cell N="PinX" V="..."/>` into `<XForm><PinX>...</PinX></XForm>` and
/// `<Section N="Geometry"><Row T="MoveTo">...` into `<Geom><MoveTo>...`.
/// libvisio's VDXParser folds those elements back into its shared collectors;
/// this importer performs the equivalent normalisation and then reuses the
/// already hardened VSDX page/master/style parsers.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../../core/exceptions.dart';
import '../../model/document.dart';
import '../../model/drawing_scale.dart';
import '../../model/image.dart';
import '../../model/layer.dart';
import '../../model/master.dart';
import '../../model/page.dart';
import '../../model/shape.dart';
import '../../model/stylesheet.dart';
import '../../model/theme.dart';
import '../../utils/color.dart';
import '../cell_helpers.dart';
import '../connect_parser.dart';
import '../document_resources_parser.dart';
import '../document_settings_parser.dart';
import '../layer_parser.dart';
import '../master_parser.dart';
import '../page_parser.dart';
import '../pages_parser.dart';
import '../rich_text_parser.dart';
import '../style_parser.dart';
import '../stylesheet_parser.dart';

const _vdxNamespaces = <String>{
  'urn:schemas-microsoft-com:office:visio',
  'http://schemas.microsoft.com/visio/2003/core',
  'http://schemas.microsoft.com/visio/2006/core',
};

/// Cheap signature check used by the unified Visio entry point.
bool looksLikeVdx(Uint8List bytes) {
  if (bytes.isEmpty) return false;
  try {
    final head = _decodeXml(
        bytes.length > 8192 ? Uint8List.sublistView(bytes, 0, 8192) : bytes);
    return RegExp(r'<(?:[A-Za-z_][\w.-]*:)?VisioDocument\b')
            .hasMatch(head) &&
        (_vdxNamespaces.any(head.contains) || head.contains('xmlns='));
  } catch (_) {
    return false;
  }
}

class VdxDocumentParser {
  const VdxDocumentParser();

  VsdxDocument parse(Uint8List bytes, {bool extractStencils = false}) {
    late final XmlDocument source;
    try {
      source = XmlDocument.parse(_decodeXml(bytes));
    } catch (error) {
      throw VsdxParseException('Malformed Visio XML document: $error');
    }
    final root = source.rootElement;
    if (root.name.local != 'VisioDocument') {
      throw const VsdxFormatException(
        'Unsupported XML document: expected VisioDocument',
      );
    }
    final namespace = root.name.namespaceUri ?? root.getAttribute('xmlns');
    if (namespace != null &&
        namespace.isNotEmpty &&
        !_vdxNamespaces.contains(namespace)) {
      throw VsdxFormatException(
        'Unsupported Visio XML namespace: $namespace',
      );
    }

    final documentXml = _normaliseDocument(root);
    final baseResources = const DocumentResourcesParser().parse(documentXml);
    final resources = VsdxDocumentResources(
      colorPalette: baseResources.colorPalette,
      fontNames: _readFonts(root),
    );
    final settings = DocumentSettingsParser(
      colorPalette: resources.colorPalette,
    ).parse(documentXml);
    final stylesheets = StyleSheetParser(
      colorPalette: resources.colorPalette,
      fontNames: resources.fontNames,
    ).parse(
      documentXml,
      defaultTextStyleId: settings.defaultTextStyleId,
    );

    final media = _VdxMediaCollector();
    final masters = _readMasters(
      root,
      stylesheets: stylesheets,
      colors: resources.colorPalette,
      fonts: resources.fontNames,
      media: media,
    );
    final pages = extractStencils
        ? _stencilPages(masters)
        : _readPages(
            root,
            masters: masters,
            stylesheets: stylesheets,
            colors: resources.colorPalette,
            fonts: resources.fontNames,
            media: media,
          );
    final properties = _firstChild(root, 'DocumentProperties');

    return VsdxDocument(
      pages: pages,
      masters: masters,
      theme: VsdxTheme.empty,
      images: ImageRegistry(Map.unmodifiable(media.images)),
      settings: settings,
      title: _property(properties, 'Title'),
      creator: _property(properties, 'Creator'),
      subject: _property(properties, 'Subject'),
      keywords: _property(properties, 'Keywords'),
      description: _property(properties, 'Description'),
      lastModifiedBy: _property(properties, 'LastSavedBy'),
      created: _property(properties, 'TimeCreated'),
      modified: _property(properties, 'TimeSaved'),
      language: _property(properties, 'Language'),
      category: _property(properties, 'Category'),
      company: _property(properties, 'Company'),
      template: _basename(_property(properties, 'Template')),
      applicationName: 'Microsoft Visio',
    );
  }

  MasterRegistry _readMasters(
    XmlElement root, {
    required StyleSheetRegistry stylesheets,
    required Map<int, VsdxColor> colors,
    required Map<int, String> fonts,
    required _VdxMediaCollector media,
  }) {
    final byId = <int, VsdxMaster>{};
    final mastersElement = _firstChild(root, 'Masters');
    if (mastersElement == null) return MasterRegistry.empty;
    for (final element in mastersElement.childElements) {
      if (element.name.local != 'Master') continue;
      final id = int.tryParse(element.getAttribute('ID') ?? '');
      if (id == null) continue;
      final localMedia = media.fork();
      final contents = _normaliseContents(
        element,
        rootName: 'MasterContents',
        media: localMedia,
      );
      final pageSheet = _normalisePageSheet(
        _firstChild(element, 'PageSheet'),
      );
      final sheet = pageSheet == null
          ? VsdxPageSheet.defaults
          : readVsdxPageSheet(pageSheet);
      final width = pageSheet == null
          ? 0.0
          : (readLengthInches(pageSheet, 'PageWidth') ?? 0.0);
      final height = pageSheet == null
          ? 0.0
          : (readLengthInches(pageSheet, 'PageHeight') ?? 0.0);
      final registry = MasterRegistry(Map.unmodifiable(byId));
      final shapeParser = PageParser(
        masters: registry,
        stylesheets: stylesheets,
        imageRels: localMedia.relationships,
        style: StyleParser(colorPalette: colors),
        richText: RichTextParser(colorPalette: colors, fontNames: fonts),
      );
      final parsed = MasterParser(shapes: shapeParser).parse(
        contents,
        id: id,
        name: element.getAttribute('NameU') ??
            element.getAttribute('Name') ??
            'Master-$id',
        partName: 'VDX/Master-$id',
        pageWidthInches: width,
        pageHeightInches: height,
        pageSheet: sheet,
      );
      media.merge(localMedia);
      if (parsed != null) byId[id] = parsed;
    }
    return MasterRegistry(Map.unmodifiable(byId));
  }

  List<VsdxPage> _readPages(
    XmlElement root, {
    required MasterRegistry masters,
    required StyleSheetRegistry stylesheets,
    required Map<int, VsdxColor> colors,
    required Map<int, String> fonts,
    required _VdxMediaCollector media,
  }) {
    final pagesElement = _firstChild(root, 'Pages');
    if (pagesElement == null) return const <VsdxPage>[];
    final pageElements = pagesElement.childElements
        .where((element) => element.name.local == 'Page')
        .toList(growable: false);
    final pages = <VsdxPage>[];
    for (var pageIndex = 0; pageIndex < pageElements.length; pageIndex++) {
      final element = pageElements[pageIndex];
      final id = int.tryParse(element.getAttribute('ID') ?? '');
      if (id == null) continue;
      final name = element.getAttribute('Name') ??
          element.getAttribute('NameU') ??
          'Page-$id';
      final localMedia = media.fork();
      final contents = _normaliseContents(
        element,
        rootName: 'PageContents',
        media: localMedia,
      );
      final pageSheet = _normalisePageSheet(
        _firstChild(element, 'PageSheet'),
      );
      final sheet = pageSheet == null
          ? const VsdxPageSheet(
              shadowOffsetXInches: 0,
              shadowOffsetYInches: 0,
            )
          : readVsdxPageSheet(pageSheet);
      final drawingScale = visioDrawingScale(sheet);
      final width = (pageSheet == null
              ? 0.0
              : (readLengthInches(pageSheet, 'PageWidth') ?? 0.0)) *
          drawingScale;
      final height = (pageSheet == null
              ? 0.0
              : (readLengthInches(pageSheet, 'PageHeight') ?? 0.0)) *
          drawingScale;
      var parser = PageParser(
        masters: masters,
        stylesheets: stylesheets,
        imageRels: localMedia.relationships,
        style: StyleParser(colorPalette: colors),
        richText: RichTextParser(colorPalette: colors, fontNames: fonts),
      ).withFieldResolver(FieldResolver(
        pageName: name,
        pageIndex: pageIndex,
        totalPages: pageElements.length,
      ));
      parser = parser.withPageShadowOffsets(
        sheet.shadowOffsetXInches,
        sheet.shadowOffsetYInches,
      );
      final shapes = <VsdxShape>[];
      for (final shape in parser.parseShapes(
        contents,
        partName: 'VDX/Page-$id',
      )) {
        shapes.add(scaleVisioDrawingShape(shape, drawingScale));
      }
      final layers = pageSheet == null
          ? const <VsdxLayer>[]
          : LayerParser(colorPalette: colors).parseLayers(pageSheet);
      final pageColor =
          pageSheet == null ? null : _readPageColor(pageSheet, colors);
      media.merge(localMedia);
      pages.add(VsdxPage(
        id: id,
        name: name,
        widthInches: width,
        heightInches: height,
        shapes: List.unmodifiable(shapes),
        layers: layers,
        connects: const ConnectParser().parsePage(contents.rootElement),
        backgroundColor: pageColor,
        isBackgroundPage: _legacyBool(element.getAttribute('Background')),
        backgroundPageId: _nonNegativeInt(element.getAttribute('BackPage')),
        pageSheet: sheet,
        viewScale: double.tryParse(element.getAttribute('ViewScale') ?? ''),
        viewCenterX: double.tryParse(element.getAttribute('ViewCenterX') ?? ''),
        viewCenterY: double.tryParse(element.getAttribute('ViewCenterY') ?? ''),
      ));
    }
    return List.unmodifiable(pages);
  }

  List<VsdxPage> _stencilPages(MasterRegistry masters) {
    final pages = <VsdxPage>[];
    for (final master in masters.all) {
      final shapes = <VsdxShape>[
        master.prototype,
        ...master.additionalPrototypes,
      ];
      pages.add(VsdxPage(
        id: pages.length,
        name: master.name,
        widthInches: master.pageWidthInches > 0
            ? master.pageWidthInches
            : master.prototype.width,
        heightInches: master.pageHeightInches > 0
            ? master.pageHeightInches
            : master.prototype.height,
        shapes: List.unmodifiable(shapes),
        pageSheet: master.pageSheet,
      ));
    }
    return List.unmodifiable(pages);
  }
}

XmlDocument _normaliseDocument(XmlElement root) {
  final children = <XmlNode>[];
  for (final child in root.childElements) {
    switch (child.name.local) {
      case 'Colors':
        children.add(child.copy());
      case 'FaceNames':
        children.add(XmlElement(XmlName('FaceNames'), const [], <XmlNode>[
          for (final face in child.childElements)
            if (face.name.local == 'FaceName')
              XmlElement(XmlName('FaceName'), <XmlAttribute>[
                ..._copyAttributes(face),
                if (face.getAttribute('NameU') == null &&
                    face.getAttribute('Name') != null)
                  XmlAttribute(XmlName('NameU'), face.getAttribute('Name')!),
              ]),
        ]));
      case 'DocumentSettings':
        children.add(_normaliseDocumentSettings(child));
      case 'StyleSheets':
        children.add(XmlElement(XmlName('StyleSheets'), const [], <XmlNode>[
          for (final sheet in child.childElements)
            if (sheet.name.local == 'StyleSheet') _normaliseStyleSheet(sheet),
        ]));
    }
  }
  return _document(XmlElement(XmlName('VisioDocument'), const [], children));
}

XmlElement _normaliseDocumentSettings(XmlElement source) {
  final children = <XmlNode>[];
  for (final child in source.childElements) {
    if (child.childElements.isEmpty) {
      final name = switch (child.name.local) {
        'GlueSettings' => 'GlueType',
        'SnapSettings' => 'SnapEnabled',
        _ => child.name.local,
      };
      children.add(_cell(child, name: name));
    }
  }
  return XmlElement(
    XmlName('DocumentSettings'),
    _copyAttributes(source),
    children,
  );
}

XmlElement _normaliseStyleSheet(XmlElement source) {
  final children = <XmlNode>[];
  final rows = <String, List<XmlElement>>{};
  for (final child in source.childElements) {
    if (child.name.local == 'Section' || child.name.local == 'Cell') {
      children.add(child.copy());
      continue;
    }
    final sectionName = _rowSectionName(child.name.local);
    if (sectionName != null) {
      rows.putIfAbsent(sectionName, () => <XmlElement>[]).add(_row(child));
      continue;
    }
    if (child.childElements.isNotEmpty) {
      final cells = <XmlNode>[
        for (final leaf in child.childElements)
          if (leaf.childElements.isEmpty) _cell(leaf),
      ];
      if (cells.isNotEmpty) {
        children.add(XmlElement(
          XmlName('Section'),
          <XmlAttribute>[XmlAttribute(XmlName('N'), child.name.local)],
          cells,
        ));
      }
    }
  }
  for (final entry in rows.entries) {
    children.add(_section(entry.key, entry.value));
  }
  return XmlElement(
    XmlName('StyleSheet'),
    _copyAttributes(source),
    children,
  );
}

XmlDocument _normaliseContents(
  XmlElement source, {
  required String rootName,
  required _VdxMediaCollector media,
}) {
  final children = <XmlNode>[];
  final shapes = _firstChild(source, 'Shapes');
  if (shapes != null) children.add(_normaliseShapes(shapes, media));
  final connects = _firstChild(source, 'Connects');
  if (connects != null) children.add(connects.copy());
  return _document(XmlElement(XmlName(rootName), const [], children));
}

XmlElement _normaliseShapes(
  XmlElement source,
  _VdxMediaCollector media,
) =>
    XmlElement(XmlName('Shapes'), const [], <XmlNode>[
      for (final child in source.childElements)
        if (child.name.local == 'Shape') _normaliseShape(child, media),
    ]);

XmlElement _normaliseShape(XmlElement source, _VdxMediaCollector media) {
  final children = <XmlNode>[];
  final rows = <String, List<XmlElement>>{};
  for (final child in source.childElements) {
    switch (child.name.local) {
      case 'Shapes':
        children.add(_normaliseShapes(child, media));
      case 'Text':
        children.add(XmlElement(
          XmlName('Text'),
          _copyAttributes(child),
          <XmlNode>[for (final node in child.children) node.copy()],
        ));
      case 'ForeignData':
        children.add(media.foreignData(child));
      case 'Cell' || 'Section':
        children.add(child.copy());
      case 'Geom':
        children.add(_geometrySection(child));
      case 'Tabs':
        rows.putIfAbsent('Tabs', () => <XmlElement>[]).add(_tabsRow(child));
      default:
        final sectionName = _rowSectionName(child.name.local);
        if (sectionName != null) {
          rows.putIfAbsent(sectionName, () => <XmlElement>[]).add(_row(child));
        } else if (child.childElements.isEmpty) {
          children.add(_cell(child));
        } else {
          // XForm, Line, Fill, TextBlock, TextXForm, XForm1D, Misc,
          // Protection, Foreign, LayerMem, Event, etc. are property blocks.
          for (final leaf in child.childElements) {
            if (leaf.childElements.isEmpty) children.add(_cell(leaf));
          }
        }
    }
  }
  for (final entry in rows.entries) {
    children.add(_section(entry.key, entry.value));
  }
  return XmlElement(
    XmlName('Shape'),
    _copyAttributes(source),
    children,
  );
}

XmlElement? _normalisePageSheet(XmlElement? source) {
  if (source == null) return null;
  final children = <XmlNode>[];
  final layers = <XmlElement>[];
  for (final child in source.childElements) {
    switch (child.name.local) {
      case 'Cell' || 'Section':
        children.add(child.copy());
      case 'Layer':
        layers.add(_row(child));
      default:
        if (child.childElements.isEmpty) {
          children.add(_cell(child));
        } else {
          for (final leaf in child.childElements) {
            if (leaf.childElements.isEmpty) children.add(_cell(leaf));
          }
        }
    }
  }
  if (layers.isNotEmpty) children.add(_section('Layer', layers));
  return XmlElement(XmlName('PageSheet'), const [], children);
}

XmlElement _geometrySection(XmlElement source) {
  final children = <XmlNode>[];
  for (final child in source.childElements) {
    if (child.childElements.isEmpty) {
      children.add(_cell(child));
    } else {
      final attributes = <XmlAttribute>[
        ..._copySelectedAttributes(child, const <String>{'IX', 'Del', 'N'}),
        XmlAttribute(XmlName('T'), child.name.local),
      ];
      children.add(XmlElement(XmlName('Row'), attributes, <XmlNode>[
        for (final leaf in child.childElements)
          if (leaf.childElements.isEmpty) _cell(leaf),
      ]));
    }
  }
  return XmlElement(
    XmlName('Section'),
    <XmlAttribute>[
      XmlAttribute(XmlName('N'), 'Geometry'),
      ..._copySelectedAttributes(source, const <String>{'IX', 'Del'}),
    ],
    children,
  );
}

XmlElement _row(XmlElement source) => XmlElement(
      XmlName('Row'),
      <XmlAttribute>[
        ..._copySelectedAttributes(
          source,
          const <String>{'IX', 'N', 'Del', 'T'},
        ),
        if (source.getAttribute('N') == null &&
            source.getAttribute('NameU') != null)
          XmlAttribute(XmlName('N'), source.getAttribute('NameU')!),
      ],
      <XmlNode>[
        for (final leaf in source.childElements)
          if (leaf.childElements.isEmpty) _cell(leaf),
      ],
    );

XmlElement _tabsRow(XmlElement source) {
  final children = <XmlNode>[];
  for (final tab in source.childElements) {
    if (tab.name.local != 'Tab') continue;
    final index = int.tryParse(tab.getAttribute('IX') ?? '') ?? 0;
    for (final leaf in tab.childElements) {
      if (leaf.childElements.isNotEmpty) continue;
      children.add(_cell(leaf, name: '${leaf.name.local}${index + 1}'));
    }
  }
  return XmlElement(
    XmlName('Row'),
    _copySelectedAttributes(source, const <String>{'IX', 'Del'}),
    children,
  );
}

XmlElement _section(String name, List<XmlElement> rows) => XmlElement(
      XmlName('Section'),
      <XmlAttribute>[XmlAttribute(XmlName('N'), name)],
      rows,
    );

String? _rowSectionName(String localName) => switch (localName) {
      'Char' => 'Character',
      'Para' => 'Paragraph',
      'Connection' => 'Connection',
      'Control' => 'Control',
      'Scratch' => 'Scratch',
      'Field' => 'Field',
      'Action' => 'Actions',
      'Prop' => 'Property',
      'User' => 'User',
      'Hyperlink' => 'Hyperlink',
      _ => null,
    };

XmlElement _cell(XmlElement source, {String? name}) {
  final value = _legacyValue(source);
  return XmlElement(XmlName('Cell'), <XmlAttribute>[
    XmlAttribute(XmlName('N'), name ?? source.name.local),
    if (value != null) XmlAttribute(XmlName('V'), value),
    if (source.getAttribute('F') case final formula?)
      XmlAttribute(XmlName('F'), formula),
    if (source.getAttribute('Unit') case final unit?)
      XmlAttribute(XmlName('U'), unit),
    ..._copySelectedAttributes(source, const <String>{'E'}),
  ]);
}

String? _legacyValue(XmlElement element) {
  final text = element.innerText;
  if (text.isNotEmpty) return text;
  final cached = element.getAttribute('V');
  if (cached == null || cached.toLowerCase() == 'null') return null;
  return cached;
}

Map<int, String> _readFonts(XmlElement root) {
  final out = <int, String>{};
  final faceNames = _firstChild(root, 'FaceNames');
  if (faceNames == null) return const <int, String>{};
  var fallback = 0;
  for (final face in faceNames.childElements) {
    if (face.name.local != 'FaceName') continue;
    final id = int.tryParse(face.getAttribute('ID') ?? '') ?? fallback;
    fallback++;
    final name = face.getAttribute('NameU') ?? face.getAttribute('Name');
    if (name != null && name.isNotEmpty) out[id] = name;
  }
  return Map.unmodifiable(out);
}

VsdxColor? _readPageColor(
  XmlElement pageSheet,
  Map<int, VsdxColor> palette,
) {
  final cell = findCell(pageSheet, 'PageColor');
  if (cell == null || isInhFormula(cell.getAttribute('F'))) return null;
  return VsdxColor.tryParse(cell.getAttribute('V'), palette: palette);
}

class _VdxMediaCollector {
  _VdxMediaCollector({int nextId = 1}) : _nextId = nextId;

  int _nextId;
  final Map<String, String> relationships = <String, String>{};
  final Map<String, VsdxImage> images = <String, VsdxImage>{};

  _VdxMediaCollector fork() => _VdxMediaCollector(nextId: _nextId);

  void merge(_VdxMediaCollector other) {
    _nextId = other._nextId;
    images.addAll(other.images);
  }

  XmlElement foreignData(XmlElement source) {
    Uint8List? bytes;
    try {
      final payload = source.innerText.replaceAll(RegExp(r'\s+'), '');
      if (payload.isNotEmpty) bytes = base64.decode(payload);
    } catch (_) {
      // Keep metadata even if the payload is malformed; one image must not
      // prevent the rest of the page from loading.
    }
    final children = <XmlNode>[];
    if (bytes != null && bytes.isNotEmpty) {
      final id = _nextId++;
      final type = source.getAttribute('ForeignType') ?? 'Bitmap';
      final compression = source.getAttribute('CompressionType');
      final format = _foreignFormat(type, compression);
      final partName = '/visio/media/vdxImage$id.${format.$1}';
      final relationshipId = 'vdxImage$id';
      relationships[relationshipId] = partName;
      images[partName] = VsdxImage(
        partName: partName,
        bytes: bytes,
        mimeType: format.$2,
      );
      children.add(XmlElement(
        XmlName('Rel'),
        <XmlAttribute>[XmlAttribute(XmlName('id'), relationshipId)],
      ));
    }
    return XmlElement(
      XmlName('ForeignData'),
      _copyAttributes(source),
      children,
    );
  }
}

(String, String) _foreignFormat(String type, String? compression) {
  switch (compression?.toUpperCase()) {
    case 'PNG':
      return ('png', 'image/png');
    case 'JPEG':
      return ('jpg', 'image/jpeg');
    case 'GIF':
      return ('gif', 'image/gif');
    case 'TIFF':
      return ('tiff', 'image/tiff');
  }
  switch (type.toLowerCase()) {
    case 'enhmetafile':
      return ('emf', 'image/x-emf');
    case 'metafile':
      return ('wmf', 'image/x-wmf');
    case 'object':
      return ('ole', 'object/ole');
    default:
      return ('bmp', 'image/bmp');
  }
}

XmlDocument _document(XmlElement root) => XmlDocument.parse(root.toXmlString());

XmlElement? _firstChild(XmlElement parent, String name) {
  for (final child in parent.childElements) {
    if (child.name.local == name) return child;
  }
  return null;
}

String? _property(XmlElement? properties, String name) {
  if (properties == null) return null;
  final element = _firstChild(properties, name);
  final value = element?.innerText.trim();
  return value == null || value.isEmpty ? null : value;
}

String? _basename(String? path) {
  if (path == null || path.isEmpty) return path;
  return path.split(RegExp(r'[/\\]')).last;
}

int? _nonNegativeInt(String? value) {
  final parsed = int.tryParse(value ?? '');
  return parsed == null || parsed < 0 ? null : parsed;
}

bool _legacyBool(String? value) => parseVisioBool(value) ?? false;

List<XmlAttribute> _copyAttributes(XmlElement source) => <XmlAttribute>[
      for (final attribute in source.attributes)
        XmlAttribute(
          XmlName(attribute.name.local, attribute.name.prefix),
          attribute.value,
        ),
    ];

List<XmlAttribute> _copySelectedAttributes(
  XmlElement source,
  Set<String> names,
) =>
    <XmlAttribute>[
      for (final attribute in source.attributes)
        if (names.contains(attribute.name.local))
          XmlAttribute(XmlName(attribute.name.local), attribute.value),
    ];

String _decodeXml(Uint8List bytes) {
  if (bytes.length >= 2) {
    if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return _decodeUtf16(bytes, littleEndian: true, offset: 2);
    }
    if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _decodeUtf16(bytes, littleEndian: false, offset: 2);
    }
  }
  final offset = bytes.length >= 3 &&
          bytes[0] == 0xEF &&
          bytes[1] == 0xBB &&
          bytes[2] == 0xBF
      ? 3
      : 0;
  // UTF-16 XML is occasionally emitted without a BOM. The leading `<` is a
  // reliable discriminator for both byte orders.
  if (bytes.length >= 4 && bytes[0] == 0x3C && bytes[1] == 0) {
    return _decodeUtf16(bytes, littleEndian: true);
  }
  if (bytes.length >= 4 && bytes[0] == 0 && bytes[1] == 0x3C) {
    return _decodeUtf16(bytes, littleEndian: false);
  }
  return utf8.decode(Uint8List.sublistView(bytes, offset));
}

String _decodeUtf16(
  Uint8List bytes, {
  required bool littleEndian,
  int offset = 0,
}) {
  final units = <int>[];
  for (var i = offset; i + 1 < bytes.length; i += 2) {
    units.add(littleEndian
        ? bytes[i] | (bytes[i + 1] << 8)
        : (bytes[i] << 8) | bytes[i + 1]);
  }
  return String.fromCharCodes(units);
}
