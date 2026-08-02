/// High-level entry point: bytes → [VsdxDocument].
///
/// After M1 this parser walks the OPC graph all the way to per-page shapes
/// (id / pin / size / text). Geometry, styles, masters and themes are
/// scheduled for M2/M3 and will be filled in alongside richer model fields.
library;

import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:xml/xml.dart';

import '../core/exceptions.dart';
import '../model/document.dart';
import 'custom_properties_parser.dart';
import 'document_settings_parser.dart';
import 'image_parser.dart';
import 'masters_parser.dart';
import 'package_reader.dart';
import 'pages_parser.dart';
import 'relationships.dart';
import 'stylesheet_parser.dart';
import 'theme_parser.dart';

final _log = Logger('vsdx.parser.document');

class DocumentParser {
  const DocumentParser();

  /// Parse a `.vsdx` blob into a [VsdxDocument].
  ///
  /// Throws [VsdxException] subclasses on failure.
  VsdxDocument parse(Uint8List bytes) {
    final pkg = VsdxPackage.open(bytes);
    final resolver = RelationshipResolver(pkg);
    _log.fine(
      () => 'Opened OPC package with ${pkg.allPartNames.length} parts',
    );

    final documentPart = pkg.resolveDocumentPartName();
    _log.fine(() => 'Document part: $documentPart');

    final documentXml = pkg.readPartXml(documentPart);
    if (documentXml == null) {
      throw VsdxParseException(
        'Document part not found in archive',
        partName: documentPart,
      );
    }
    final settings = const DocumentSettingsParser().parse(documentXml);
    final stylesheets = const StyleSheetParser().parse(
      documentXml,
      defaultTextStyleId: settings.defaultTextStyleId,
    );
    _log.fine(() =>
        'StyleSheets defaultTextStyle=${stylesheets.defaultTextStyleId}');

    // Theme + Masters first — pages need both for full inheritance.
    final theme =
        ThemeParser(pkg).parseTheme(documentPartName: documentPart);
    _log.fine(() =>
        'Loaded theme (${theme.isEmpty ? 'empty' : '${theme.colors.length} slots'})');

    final masters = MastersParser(pkg, stylesheets: stylesheets)
        .parseMasters(documentPartName: documentPart);
    _log.fine(() => 'Loaded ${masters.length} master(s)');

    final images =
        ImageParser(pkg).parseImages(documentPartName: documentPart);
    _log.fine(() => 'Loaded ${images.length} image(s)');

    // PagesParser will mint its own PageParser instances per page so each
    // shape can resolve `<ForeignData r:id>` against the right rels map.
    final pages = PagesParser(pkg, masters: masters, stylesheets: stylesheets)
        .parsePages(documentPartName: documentPart);
    _log.fine(() => 'Parsed ${pages.length} page(s)');

    final coreProperties = _readOptionalPropertiesPart(
      pkg,
      resolver.rootTargetOfType(VsdxRelType.coreProperties) ??
          '/docProps/core.xml',
    );
    final extendedProperties = _readOptionalPropertiesPart(
      pkg,
      resolver.rootTargetOfType(VsdxRelType.extendedProperties) ??
          '/docProps/app.xml',
    );
    final customPropertiesPart =
        resolver.rootTargetOfType(VsdxRelType.customProperties) ??
            '/docProps/custom.xml';

    return VsdxDocument(
      pages: pages,
      masters: masters,
      theme: theme,
      images: images,
      settings: settings,
      title: _readProperty(coreProperties, 'title'),
      creator: _readProperty(coreProperties, 'creator'),
      subject: _readProperty(coreProperties, 'subject'),
      keywords: _readProperty(coreProperties, 'keywords'),
      description: _readProperty(coreProperties, 'description'),
      lastModifiedBy: _readProperty(coreProperties, 'lastModifiedBy'),
      created: _readProperty(coreProperties, 'created'),
      modified: _readProperty(coreProperties, 'modified'),
      language: _readProperty(coreProperties, 'language'),
      category: _readProperty(coreProperties, 'category'),
      company: _readProperty(extendedProperties, 'Company'),
      template: _basename(_readProperty(extendedProperties, 'Template')),
      applicationName: _readProperty(extendedProperties, 'Application'),
      customProperties: const CustomPropertiesParser().parse(
        pkg,
        partName: customPropertiesPart,
      ),
    );
  }

  XmlDocument? _readOptionalPropertiesPart(
    VsdxPackage pkg,
    String partName,
  ) {
    try {
      return pkg.readPartXml(partName);
    } catch (_) {
      // libvisio treats malformed optional metadata as non-fatal.
      return null;
    }
  }

  String? _readProperty(XmlDocument? document, String localName) {
    if (document == null) return null;
    for (final node in document.rootElement.descendants) {
      if (node is XmlElement && node.name.local == localName) {
        return node.innerText.trim();
      }
    }
    return null;
  }

  String? _basename(String? path) {
    if (path == null || path.isEmpty) return path;
    final parts = path.split(RegExp(r'[/\\]'));
    return parts.isEmpty ? path : parts.last;
  }
}
