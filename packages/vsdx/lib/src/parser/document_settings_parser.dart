/// Parse the top-level `<DocumentSettings>` element of `visio/document.xml`.
///
/// Cells we care about today:
///
/// ```xml
/// <DocumentSettings>
///   <Cell N="PageColor" V="#F2F2F2"/>
///   <Cell N="GlueType" V="9"/>
///   <Cell N="SnapEnabled" V="1"/>
///   <Cell N="GridDensityX" V="4"/>
///   <Cell N="GridDensityY" V="4"/>
/// </DocumentSettings>
/// ```
library;

import 'package:xml/xml.dart';

import '../model/document_settings.dart';
import '../utils/color.dart';

class DocumentSettingsParser {
  const DocumentSettingsParser();

  VsdxDocumentSettings parse(XmlDocument? documentXml) {
    if (documentXml == null) return VsdxDocumentSettings.defaults;
    XmlElement? settings;
    for (final node in documentXml.rootElement.descendants) {
      if (node is XmlElement && node.name.local == 'DocumentSettings') {
        settings = node;
        break;
      }
    }
    if (settings == null) return VsdxDocumentSettings.defaults;

    final color = _cellString(settings, 'PageColor');
    return VsdxDocumentSettings(
      defaultPageBackgroundColor:
          color == null ? null : VsdxColor.tryParse(color),
      glueType: _cellInt(settings, 'GlueType') ?? 0,
      snapEnabled: (_cellInt(settings, 'SnapEnabled') ?? 1) != 0,
      gridDensityX: _cellInt(settings, 'GridDensityX') ?? 4,
      gridDensityY: _cellInt(settings, 'GridDensityY') ?? 4,
    );
  }

  String? _cellString(XmlElement parent, String name) {
    for (final el in parent.childElements) {
      if (el.name.local != 'Cell') continue;
      if (el.getAttribute('N') != name) continue;
      final v = el.getAttribute('V');
      if (v == null || v.isEmpty) return null;
      return v;
    }
    return null;
  }

  int? _cellInt(XmlElement parent, String name) {
    final s = _cellString(parent, name);
    if (s == null) return null;
    return int.tryParse(s) ?? double.tryParse(s)?.toInt();
  }
}
