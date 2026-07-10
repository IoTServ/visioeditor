/// High-level relationship traversal helpers, layered on top of
/// [VsdxPackage]'s raw rels lookups.
///
/// Keeping this in its own file means the package reader stays a tight
/// "ZIP + Content_Types + rels parse" core, while traversal logic (which
/// will grow over M2/M3 as more part types come into play) lives here.
library;

import '../core/exceptions.dart';
import 'package_reader.dart';

/// Well-known relationship type suffixes used by Visio.
///
/// Microsoft sometimes bumps the namespace year in the URI (`2010` →
/// `2012`), so we match on the **trailing path segment** rather than the
/// full string.
enum VsdxRelType {
  document('/document'),
  pages('/pages'),
  page('/page'),
  masters('/masters'),
  master('/master'),
  theme('/theme'),
  windows('/windows'),
  image('/image'),
  hyperlink('/hyperlink'),
  customXml('/customXml'),
  coreProperties('/metadata/core-properties'),
  extendedProperties('/extended-properties');

  const VsdxRelType(this.suffix);
  final String suffix;

  bool matches(String typeUri) => typeUri.endsWith(suffix);
}

class RelationshipResolver {
  RelationshipResolver(this._package);

  final VsdxPackage _package;

  /// All relationships emanating from [sourcePartName], keyed by `rId`.
  Map<String, PackageRelationship> relsByIdOf(String sourcePartName) {
    final out = <String, PackageRelationship>{};
    for (final r in _package.readPartRelationships(sourcePartName)) {
      out[r.id] = r;
    }
    return out;
  }

  /// All targets reachable from [sourcePartName] whose relationship type
  /// matches [type]. Returned as absolute part names.
  List<String> targetsOfType(String sourcePartName, VsdxRelType type) {
    final out = <String>[];
    for (final r in _package.readPartRelationships(sourcePartName)) {
      if (!type.matches(r.type)) continue;
      out.add(_package.resolveRelationshipTarget(sourcePartName, r.target));
    }
    return out;
  }

  /// At-most-one variant of [targetsOfType] — surfaces the first match or
  /// `null`. Throws if there is more than one (used for the "there must be
  /// exactly one pages.xml" cases).
  String? singleTargetOfType(String sourcePartName, VsdxRelType type) {
    final matches = targetsOfType(sourcePartName, type);
    if (matches.isEmpty) return null;
    if (matches.length > 1) {
      throw VsdxPackageException(
        'Expected at most one ${type.name} relationship from '
        '$sourcePartName, found ${matches.length}',
        partName: sourcePartName,
      );
    }
    return matches.single;
  }

  /// Follow a single relationship by id; thin wrapper around
  /// [VsdxPackage.followRelationship] for symmetry with the other helpers.
  String? followById(String sourcePartName, String relationshipId) =>
      _package.followRelationship(sourcePartName, relationshipId);

  /// Walk every reachable part starting from [root] (default: the document
  /// part), yielding each part name **once** in DFS order. Cycle-safe.
  ///
  /// This is the building block tests use to verify "no dangling targets"
  /// and that the user-facing `flutter analyze`-style diagnostic for OPC
  /// integrity stays accurate.
  Iterable<String> walkParts({String? root}) sync* {
    final start = root ?? _package.resolveDocumentPartName();
    final stack = <String>[start];
    final seen = <String>{};
    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      if (!seen.add(current)) continue;
      yield current;
      for (final rel in _package.readPartRelationships(current)) {
        // Skip external links (Hyperlink to web pages etc).
        if (rel.targetMode == 'External') continue;
        final abs =
            _package.resolveRelationshipTarget(current, rel.target);
        stack.add(abs);
      }
    }
  }
}
