/// Parse a page's `<Connects>` block into a list of [VsdxConnect].
///
/// The element shape (MS-VSDX §"Connects"):
///
/// ```xml
/// <Connects>
///   <Connect FromSheet="1" FromCell="EndX" FromPart="12"
///            ToSheet="2"   ToCell="PinX"   ToPart="3"/>
/// </Connects>
/// ```
library;

import 'package:xml/xml.dart';

import '../model/connect.dart';

class ConnectParser {
  const ConnectParser();

  /// Returns one [VsdxConnect] per `<Connect>` child of [pageRoot]'s
  /// `<Connects>` element. Returns an empty list when no connects exist.
  List<VsdxConnect> parsePage(XmlElement pageRoot) {
    XmlElement? connects;
    for (final el in pageRoot.childElements) {
      if (el.name.local == 'Connects') {
        connects = el;
        break;
      }
    }
    if (connects == null) return const <VsdxConnect>[];

    final out = <VsdxConnect>[];
    for (final el in connects.childElements) {
      if (el.name.local != 'Connect') continue;
      final fromSheet = int.tryParse(el.getAttribute('FromSheet') ?? '');
      final toSheet = int.tryParse(el.getAttribute('ToSheet') ?? '');
      if (fromSheet == null || toSheet == null) continue;
      out.add(VsdxConnect(
        fromSheetId: fromSheet,
        fromCell: el.getAttribute('FromCell') ?? '',
        fromPart: int.tryParse(el.getAttribute('FromPart') ?? ''),
        toSheetId: toSheet,
        toCell: el.getAttribute('ToCell') ?? '',
        toPart: int.tryParse(el.getAttribute('ToPart') ?? ''),
      ));
    }
    return List.unmodifiable(out);
  }
}
