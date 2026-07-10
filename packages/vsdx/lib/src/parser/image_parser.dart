/// Walk every relationship of type `/image` reachable from the document
/// part, slurp the bytes, and build an [ImageRegistry].
///
/// The parser is intentionally cheap: it doesn't decode the bytes (Flutter
/// does that lazily at paint time) and it doesn't try to follow EMF/WMF
/// references (those fall through to the placeholder).
library;

import 'package:logging/logging.dart';

import '../model/image.dart';
import 'package_reader.dart';
import 'relationships.dart';

final _log = Logger('vsdx.parser.image');

class ImageParser {
  ImageParser(this._package)
      : _resolver = RelationshipResolver(_package);

  final VsdxPackage _package;
  final RelationshipResolver _resolver;

  /// Walk all parts reachable from [documentPartName] and collect every
  /// `/image` relationship target. Returns the populated registry.
  ImageRegistry parseImages({required String documentPartName}) {
    final out = <String, VsdxImage>{};
    for (final part in _resolver.walkParts(root: documentPartName)) {
      for (final rel in _package.readPartRelationships(part)) {
        if (!VsdxRelType.image.matches(rel.type)) continue;
        if (rel.targetMode == 'External') continue;
        final target =
            _package.resolveRelationshipTarget(part, rel.target);
        if (out.containsKey(target)) continue;
        final bytes = _package.readPartBytes(target);
        if (bytes == null) {
          _log.warning('Image part declared but missing: $target');
          continue;
        }
        final mime = _package.contentTypes.mimeFor(target) ?? '';
        out[target] = VsdxImage(
          partName: target,
          bytes: bytes,
          mimeType: mime,
        );
      }
    }
    return ImageRegistry(Map.unmodifiable(out));
  }
}
