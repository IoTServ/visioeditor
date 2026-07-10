/// OPC ZIP reader — the foundation of all VSDX parsing.
///
/// Wraps `package:archive` so the rest of the codebase deals with a clean
/// "part map" abstraction: lookup by part name, get bytes / XML.
///
/// Implements just enough of OPC for VSDX (we don't need full ECMA-376
/// validation):
///  1. Open the ZIP.
///  2. Read `[Content_Types].xml` so we can answer "what is this part?".
///  3. Read the root `_rels/.rels` to locate `visio/document.xml`.
///
/// Subsequent relationship traversal lives in `relationships.dart` (M1-04).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../core/exceptions.dart';

final _posix = p.Context(style: p.Style.posix);

/// In-memory, read-only view of an OPC package.
class VsdxPackage {
  VsdxPackage._(this._archive, this.contentTypes, this.rootRelationships);

  final Archive _archive;
  final ContentTypes contentTypes;

  /// Parsed `/_rels/.rels` — relationships rooted at the package itself.
  final List<PackageRelationship> rootRelationships;

  /// Maximum entries we allow inside a single VSDX (defence in depth against
  /// zip bombs). Typical files have < 200 entries; legitimate large ones may
  /// reach a few thousand.
  static const int maxEntries = 20000;

  /// Maximum uncompressed bytes per individual entry (200 MiB).
  static const int maxEntryBytes = 200 * 1024 * 1024;

  /// Parse a `.vsdx` blob.
  ///
  /// Throws [VsdxPackageException] on structural errors.
  static VsdxPackage open(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: true);
    } catch (e, st) {
      Error.throwWithStackTrace(
        const VsdxPackageException('Failed to open ZIP archive'),
        st,
      );
    }

    if (archive.length > maxEntries) {
      throw VsdxPackageException(
        'ZIP contains $archive.length entries, refusing for safety',
      );
    }

    // Defence in depth: refuse zip-slip absolute / parent paths.
    for (final f in archive) {
      final n = f.name;
      if (n.startsWith('/') || n.contains('..')) {
        throw VsdxPackageException(
          'Refusing suspicious archive entry "$n"',
        );
      }
    }

    final ctEntry = archive.findFile('[Content_Types].xml');
    if (ctEntry == null) {
      throw const VsdxPackageException(
        'Missing [Content_Types].xml — not a valid OPC package',
      );
    }
    final contentTypes = ContentTypes.parse(_readXml(ctEntry));

    final rootRelsEntry = archive.findFile('_rels/.rels');
    if (rootRelsEntry == null) {
      throw const VsdxPackageException('Missing _rels/.rels');
    }
    final rootRels = _parseRelationships(_readXml(rootRelsEntry));

    return VsdxPackage._(archive, contentTypes, rootRels);
  }

  /// Locate the `visio/document.xml` part (or whichever the OPC root rels
  /// point at). Returns the absolute part name (always starts with `/`).
  String resolveDocumentPartName() {
    // The relationship type URI for the main Visio document is documented in
    // MS-VSDX §2.1, but we match the path suffix `/document` to remain
    // tolerant of namespace evolution across Visio versions.
    for (final r in rootRelationships) {
      if (r.type.endsWith('/document') || r.target.endsWith('document.xml')) {
        return _normalisePartName(r.target);
      }
    }
    throw const VsdxPackageException(
      'Root relationships do not reference a Visio document part',
    );
  }

  /// Raw bytes of an OPC part. Part names start with `/`.
  Uint8List? readPartBytes(String partName) {
    final entry = _archive.findFile(_stripLeadingSlash(partName));
    if (entry == null) return null;
    if (entry.size > maxEntryBytes) {
      throw VsdxPackageException(
        'Part "$partName" exceeds ${maxEntryBytes ~/ (1024 * 1024)} MiB safety limit',
        partName: partName,
      );
    }
    final data = entry.content;
    if (data is Uint8List) return data;
    return Uint8List.fromList(data as List<int>);
  }

  /// Parse a part as XML.
  XmlDocument? readPartXml(String partName) {
    final bytes = readPartBytes(partName);
    if (bytes == null) return null;
    try {
      return XmlDocument.parse(utf8.decode(bytes));
    } catch (e, st) {
      Error.throwWithStackTrace(
        VsdxPackageException(
          'Malformed XML in $partName',
          cause: e,
          partName: partName,
        ),
        st,
      );
    }
  }

  /// Iterate all part names in stable order. Useful for debugging / dumps.
  Iterable<String> get allPartNames sync* {
    for (final f in _archive) {
      yield '/${f.name}';
    }
  }

  /// Returns the relationships file for [partName] (the document side of a
  /// `_rels/<basename>.rels` pair). Returns an empty list if the side-car is
  /// absent, which is legitimate (an OPC part is not required to have one).
  List<PackageRelationship> readPartRelationships(String partName) {
    final cached = _relsCache[partName];
    if (cached != null) return cached;

    final dir = _posix.dirname(_stripLeadingSlash(partName));
    final base = _posix.basename(partName);
    final relsPath = dir.isEmpty
        ? '_rels/$base.rels'
        : '$dir/_rels/$base.rels';

    final entry = _archive.findFile(relsPath);
    if (entry == null) {
      return _relsCache[partName] = const <PackageRelationship>[];
    }
    final list = _parseRelationships(_readXml(entry));
    return _relsCache[partName] = List.unmodifiable(list);
  }

  /// Resolve an OPC `Target` string (as it appears inside a `<Relationship>`)
  /// against the part that hosts the relationship, returning an absolute part
  /// name (always starts with `/`).
  ///
  /// Rules:
  ///  * `Target="/foo/bar.xml"` → already absolute, normalised.
  ///  * `Target="foo/bar.xml"` (no leading `/`) → relative to `dirname(sourcePart)`.
  ///  * `Target="../foo.xml"` → `..` segments are resolved via posix normalisation.
  String resolveRelationshipTarget(String sourcePartName, String target) {
    if (target.startsWith('/')) return _normalisePartName(target);
    final sourceDir = _posix.dirname(_stripLeadingSlash(sourcePartName));
    final joined = sourceDir.isEmpty ? target : '$sourceDir/$target';
    return _normalisePartName(_posix.normalize(joined));
  }

  /// Convenience: follow a single relationship by `rId` from [sourcePartName].
  ///
  /// Returns `null` if no matching relationship exists. Throws
  /// [VsdxPackageException] when the target part is missing from the archive.
  String? followRelationship(String sourcePartName, String relationshipId) {
    final rels = readPartRelationships(sourcePartName);
    for (final r in rels) {
      if (r.id != relationshipId) continue;
      final abs = resolveRelationshipTarget(sourcePartName, r.target);
      if (_archive.findFile(_stripLeadingSlash(abs)) == null) {
        throw VsdxPackageException(
          'Relationship $relationshipId from $sourcePartName '
          'points to missing part $abs',
          partName: sourcePartName,
        );
      }
      return abs;
    }
    return null;
  }

  final Map<String, List<PackageRelationship>> _relsCache =
      <String, List<PackageRelationship>>{};

  static String _readXml(ArchiveFile f) {
    final content = f.content;
    final bytes = content is Uint8List
        ? content
        : Uint8List.fromList(content as List<int>);
    return utf8.decode(bytes);
  }

  static String _stripLeadingSlash(String s) =>
      s.startsWith('/') ? s.substring(1) : s;

  static String _normalisePartName(String s) =>
      s.startsWith('/') ? s : '/$s';
}

// ---------------------------------------------------------------------------
// [Content_Types].xml
// ---------------------------------------------------------------------------

class ContentTypes {
  ContentTypes({
    required Map<String, String> defaults,
    required Map<String, String> overrides,
  })  : _defaults = defaults,
        _overrides = overrides;

  final Map<String, String> _defaults;   // extension -> mime
  final Map<String, String> _overrides;  // partName  -> mime

  /// Resolve the MIME type for a given absolute part name (leading `/`).
  String? mimeFor(String partName) {
    final ov = _overrides[partName];
    if (ov != null) return ov;
    final ext = p.extension(partName).replaceFirst('.', '').toLowerCase();
    return _defaults[ext];
  }

  static ContentTypes parse(String xml) {
    late final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xml);
    } catch (e, st) {
      Error.throwWithStackTrace(
        VsdxPackageException(
          'Malformed [Content_Types].xml',
          cause: e,
          partName: '/[Content_Types].xml',
        ),
        st,
      );
    }
    final defaults = <String, String>{};
    final overrides = <String, String>{};
    for (final el in doc.rootElement.childElements) {
      switch (el.name.local) {
        case 'Default':
          final ext = el.getAttribute('Extension')?.toLowerCase();
          final ct = el.getAttribute('ContentType');
          if (ext != null && ct != null) defaults[ext] = ct;
        case 'Override':
          final partName = el.getAttribute('PartName');
          final ct = el.getAttribute('ContentType');
          if (partName != null && ct != null) overrides[partName] = ct;
      }
    }
    return ContentTypes(defaults: defaults, overrides: overrides);
  }
}

// ---------------------------------------------------------------------------
// Relationships
// ---------------------------------------------------------------------------

class PackageRelationship {
  const PackageRelationship({
    required this.id,
    required this.type,
    required this.target,
    this.targetMode = 'Internal',
  });

  final String id;
  final String type;
  final String target;
  final String targetMode;

  @override
  String toString() => 'Rel($id $type → $target)';
}

List<PackageRelationship> _parseRelationships(String xml) {
  late final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xml);
  } catch (e, st) {
    Error.throwWithStackTrace(
      VsdxPackageException('Malformed .rels XML', cause: e),
      st,
    );
  }
  final out = <PackageRelationship>[];
  for (final el in doc.rootElement.childElements) {
    if (el.name.local != 'Relationship') continue;
    final id = el.getAttribute('Id');
    final type = el.getAttribute('Type');
    final target = el.getAttribute('Target');
    if (id == null || type == null || target == null) continue;
    out.add(PackageRelationship(
      id: id,
      type: type,
      target: target,
      targetMode: el.getAttribute('TargetMode') ?? 'Internal',
    ));
  }
  return out;
}
