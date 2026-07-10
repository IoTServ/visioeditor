/// Parse one `visio/masters/masterN.xml` part into a [VsdxMaster].
///
/// Master files share their inner structure with page files
/// (`<MasterContents><Shapes><Shape>...`), so the existing [PageParser] is
/// reused without recursion: we don't pass it a [MasterRegistry] to keep
/// inheritance flat (Master-of-Master support is out-of-scope for the
/// first cut).
library;

import 'package:logging/logging.dart';
import 'package:xml/xml.dart';

import '../model/master.dart';
import 'page_parser.dart';

final _log = Logger('vsdx.parser.master');

class MasterParser {
  MasterParser({PageParser? shapes}) : _shapes = shapes ?? const PageParser();

  final PageParser _shapes;

  /// Returns the first top-level shape inside [masterDoc] wrapped as a
  /// [VsdxMaster]. If the document contains no shape, returns `null`
  /// (the caller skips that master).
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
    if (shapes.length > 1) {
      _log.fine(() =>
          'Master $id ($name) declared ${shapes.length} top-level shapes; '
          'using the first as the prototype');
    }
    return VsdxMaster(id: id, name: name, prototype: shapes.first);
  }
}
