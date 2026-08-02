/// Parse one `visio/masters/masterN.xml` part into a [VsdxMaster].
///
/// Master files share their inner structure with page files
/// (`<MasterContents><Shapes><Shape>...`), so the existing [PageParser] is
/// reused without special-case shape logic. [MastersParser] supplies the
/// registry of previously parsed masters so source-order master inheritance
/// matches libvisio.
library;

import 'package:logging/logging.dart';
import 'package:xml/xml.dart';

import '../model/master.dart';
import 'page_parser.dart';

final _log = Logger('vsdx.parser.master');

class MasterParser {
  MasterParser({PageParser? shapes}) : _shapes = shapes ?? const PageParser();

  final PageParser _shapes;

  /// Returns the top-level shapes inside [masterDoc] wrapped as a [VsdxMaster].
  /// The first remains the implicit prototype, while later shapes stay
  /// addressable through `MasterShape`, matching libvisio's stencil map. If
  /// the document contains no shape, returns `null` (the caller skips it).
  VsdxMaster? parse(
    XmlDocument masterDoc, {
    required int id,
    required String name,
    required String partName,
  }) {
    final shapes = _shapes.parseShapes(masterDoc, partName: partName);
    if (shapes.isEmpty) {
      _log.warning('Master $id ($name) at $partName has no shapes');
      return null;
    }
    return VsdxMaster(
      id: id,
      name: name,
      prototype: shapes.first,
      additionalPrototypes: List.unmodifiable(shapes.skip(1)),
    );
  }
}
