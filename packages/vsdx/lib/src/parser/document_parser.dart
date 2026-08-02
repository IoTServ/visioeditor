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

    return VsdxDocument(
      pages: pages,
      masters: masters,
      theme: theme,
      images: images,
      settings: settings,
      title: _readCoreProperty(pkg, 'title'),
      creator: _readCoreProperty(pkg, 'creator'),
      subject: _readCoreProperty(pkg, 'subject'),
      keywords: _readCoreProperty(pkg, 'keywords'),
      description: _readCoreProperty(pkg, 'description'),
      lastModifiedBy: _readCoreProperty(pkg, 'lastModifiedBy'),
      created: _readCoreProperty(pkg, 'created'),
      modified: _readCoreProperty(pkg, 'modified'),
      language: _readCoreProperty(pkg, 'language'),
      category: _readCoreProperty(pkg, 'category'),
      company: _readAppProperty(pkg, 'Company'),
      template: _basename(_readAppProperty(pkg, 'Template')),
      applicationName: _readAppProperty(pkg, 'Application'),
      customProperties: const CustomPropertiesParser().parse(pkg),
    );
  }

  String? _readCoreProperty(VsdxPackage pkg, String localName) {
    final doc = pkg.readPartXml('/docProps/core.xml');
    if (doc == null) return null;
    return _firstElementText(doc.rootElement, localName);
  }

  String? _readAppProperty(VsdxPackage pkg, String localName) {
    final doc = pkg.readPartXml('/docProps/app.xml');
    if (doc == null) return null;
    return _firstElementText(doc.rootElement, localName);
  }

  String? _firstElementText(XmlElement root, String localName) {
    for (final node in root.descendants) {
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
