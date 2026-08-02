/// Parses the document-scoped colour and font lookup tables used by Visio
/// cells. libvisio initialises its classic colour palette first, then applies
/// `<ColorEntry>` overrides, while `<FaceName>` indices follow document order.
library;

import 'package:xml/xml.dart';

import '../utils/color.dart';

class VsdxDocumentResources {
  const VsdxDocumentResources({
    this.colorPalette = const <int, VsdxColor>{},
    this.fontNames = const <int, String>{},
  });

  final Map<int, VsdxColor> colorPalette;
  final Map<int, String> fontNames;
}

class DocumentResourcesParser {
  const DocumentResourcesParser();

  VsdxDocumentResources parse(XmlDocument document) {
    final colors = <int, VsdxColor>{};
    final fonts = <int, String>{};

    for (final container in document.rootElement.childElements) {
      if (container.name.local == 'Colors') {
        for (final entry in container.childElements) {
          if (entry.name.local != 'ColorEntry') continue;
          final index = int.tryParse(entry.getAttribute('IX') ?? '');
          final color = VsdxColor.tryParse(entry.getAttribute('RGB'));
          if (index != null && color != null) colors[index] = color;
        }
      } else if (container.name.local == 'FaceNames') {
        var index = 0;
        for (final entry in container.childElements) {
          if (entry.name.local != 'FaceName') continue;
          final name = entry.getAttribute('NameU');
          if (name != null && name.isNotEmpty) fonts[index] = name;
          // libvisio advances the index even when NameU is absent.
          index++;
        }
      }
    }

    return VsdxDocumentResources(
      colorPalette: Map.unmodifiable(colors),
      fontNames: Map.unmodifiable(fonts),
    );
  }
}
