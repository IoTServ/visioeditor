/// Convenience extensions over `package:xml` tailored for VSDX traversal.
///
/// Visio uses default namespaces extensively; rather than juggling
/// `XmlName(namespace, ...)` calls everywhere we match by **local name**
/// (the part after `:`). All helpers return `null` instead of throwing for
/// the common "optional attribute / child" cases.
library;

import 'package:xml/xml.dart';

extension VsdxXmlElementExt on XmlElement {
  /// First descendant (any depth) with matching local name, or `null`.
  XmlElement? findFirst(String localName) {
    for (final node in descendants) {
      if (node is XmlElement && node.name.local == localName) return node;
    }
    return null;
  }

  /// All direct child elements with matching local name.
  Iterable<XmlElement> childrenNamed(String localName) =>
      childElements.where((e) => e.name.local == localName);

  /// Attribute value by local name, ignoring namespace; `null` if absent.
  String? attrLocal(String localName) {
    for (final a in attributes) {
      if (a.name.local == localName) return a.value;
    }
    return null;
  }
}

extension VsdxXmlIterableExt on Iterable<XmlElement> {
  /// First element whose local name equals [localName], else `null`.
  XmlElement? whereLocalFirst(String localName) {
    for (final e in this) {
      if (e.name.local == localName) return e;
    }
    return null;
  }
}
