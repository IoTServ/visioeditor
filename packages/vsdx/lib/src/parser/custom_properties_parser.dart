/// Parses OPC `docProps/custom.xml` into [VsdxCustomProperty] rows.
library;

import 'package:logging/logging.dart';
import 'package:xml/xml.dart';

import '../model/custom_property.dart';
import 'package_reader.dart';

final _log = Logger('vsdx.parser.custom_properties');

class CustomPropertiesParser {
  const CustomPropertiesParser();

  static const _vtNs =
      'http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes';

  List<VsdxCustomProperty> parse(
    VsdxPackage pkg, {
    String partName = '/docProps/custom.xml',
  }) {
    XmlDocument? doc;
    try {
      doc = pkg.readPartXml(partName);
    } catch (_) {
      // Optional metadata must not prevent an otherwise valid drawing from
      // opening (the same recovery policy used by libvisio).
      return const [];
    }
    if (doc == null) return const [];
    return parseDocument(doc);
  }

  List<VsdxCustomProperty> parseDocument(XmlDocument doc) {
    final root = doc.rootElement;
    if (root.name.local != 'Properties') {
      _log.warning('Unexpected custom.xml root: ${root.name.qualified}');
      return const [];
    }

    final out = <VsdxCustomProperty>[];
    for (final node in root.childElements) {
      if (node.name.local != 'property') continue;
      final name = node.getAttribute('name');
      if (name == null || name.isEmpty) continue;

      final pidRaw = node.getAttribute('pid');
      final pid = pidRaw == null ? null : int.tryParse(pidRaw);

      String? valueType;
      String value = '';
      for (final child in node.childElements) {
        if (child.name.namespaceUri == _vtNs ||
            child.name.prefix == 'vt' ||
            child.name.local.startsWith('vt')) {
          valueType = child.name.local;
          value = child.innerText.trim();
          break;
        }
        // Some producers omit the vt prefix but keep the namespace.
        if (child.name.local == 'lpwstr' ||
            child.name.local == 'i4' ||
            child.name.local == 'r8' ||
            child.name.local == 'bool' ||
            child.name.local == 'filetime' ||
            child.name.local == 'bstr') {
          valueType = child.name.local;
          value = child.innerText.trim();
          break;
        }
      }

      out.add(VsdxCustomProperty(
        name: name,
        value: value,
        valueType: valueType,
        propertyId: pid,
      ));
    }
    return out;
  }
}
