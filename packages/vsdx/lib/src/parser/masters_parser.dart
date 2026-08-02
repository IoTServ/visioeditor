/// Walks `visio/masters/masters.xml`, following each `<Rel r:id="..."/>` to
/// load every `masterN.xml`, and returns a [MasterRegistry].
///
/// The document layer holds onto the registry and threads it down to the
/// page parser so per-shape inheritance can resolve in O(1).
library;

import 'package:logging/logging.dart';
import 'package:xml/xml.dart';

import '../model/master.dart';
import '../model/stylesheet.dart';
import '../utils/color.dart';
import 'master_parser.dart';
import 'package_reader.dart';
import 'page_parser.dart';
import 'relationships.dart';
import 'rich_text_parser.dart';
import 'style_parser.dart';

final _log = Logger('vsdx.parser.masters');

class MastersParser {
  MastersParser(
    this._package, {
    MasterParser? masterParser,
    StyleSheetRegistry stylesheets = StyleSheetRegistry.empty,
    Map<int, VsdxColor> colorPalette = const <int, VsdxColor>{},
    Map<int, String> fontNames = const <int, String>{},
  })  : _resolver = RelationshipResolver(_package),
        _master = masterParser ??
            MasterParser(
              shapes: PageParser(
                style: StyleParser(colorPalette: colorPalette),
                richText: RichTextParser(
                  colorPalette: colorPalette,
                  fontNames: fontNames,
                ),
                stylesheets: stylesheets,
              ),
            );

  final VsdxPackage _package;
  final RelationshipResolver _resolver;
  final MasterParser _master;

  /// Builds the registry by walking from [documentPartName] → `masters.xml`
  /// → each `masterN.xml`. Returns [MasterRegistry.empty] when no masters
  /// relationship exists.
  MasterRegistry parseMasters({required String documentPartName}) {
    final mastersPart =
        _resolver.singleTargetOfType(documentPartName, VsdxRelType.masters);
    if (mastersPart == null) {
      _log.fine(() =>
          'No masters relationship from $documentPartName; nothing to load');
      return MasterRegistry.empty;
    }

    XmlDocument? indexXml;
    try {
      indexXml = _package.readPartXml(mastersPart);
    } catch (_) {
      _log.warning('masters.xml is malformed; ignoring masters: $mastersPart');
      return MasterRegistry.empty;
    }
    if (indexXml == null) {
      _log.warning('masters.xml declared but missing in archive: $mastersPart');
      return MasterRegistry.empty;
    }

    final byId = <int, VsdxMaster>{};
    for (final el in indexXml.rootElement.childElements) {
      if (el.name.local != 'Master') continue;
      final master = _readEntry(el, mastersPart: mastersPart);
      if (master != null) byId[master.id] = master;
    }
    return MasterRegistry(Map.unmodifiable(byId));
  }

  VsdxMaster? _readEntry(
    XmlElement el, {
    required String mastersPart,
  }) {
    final idStr = el.getAttribute('ID');
    final id = idStr == null ? null : int.tryParse(idStr);
    if (id == null) return null;
    final name = el.getAttribute('NameU') ??
        el.getAttribute('Name') ??
        'Master-$id';

    final relEl = _firstChildLocal(el, 'Rel');
    if (relEl == null) {
      _log.warning('Master $id ($name) has no <Rel> child; skipping');
      return null;
    }
    final rId = relEl.getAttribute('r:id') ??
        relEl.getAttribute('id') ??
        relEl.getAttribute('Id');
    if (rId == null) {
      _log.warning('Master $id ($name) <Rel> missing r:id attribute');
      return null;
    }
    final target = _resolver.followById(mastersPart, rId);
    if (target == null) {
      _log.warning('Master $id ($name) → $rId did not resolve');
      return null;
    }
    XmlDocument? doc;
    try {
      doc = _package.readPartXml(target);
    } catch (_) {
      _log.warning('Master part is malformed; skipping: $target');
      return null;
    }
    if (doc == null) {
      _log.warning('Master part missing: $target');
      return null;
    }
    try {
      return _master.parse(doc, id: id, name: name, partName: target);
    } catch (_) {
      _log.warning('Master $id ($name) could not be parsed; skipping');
      return null;
    }
  }

  static XmlElement? _firstChildLocal(XmlElement parent, String local) {
    for (final el in parent.childElements) {
      if (el.name.local == local) return el;
    }
    return null;
  }
}
