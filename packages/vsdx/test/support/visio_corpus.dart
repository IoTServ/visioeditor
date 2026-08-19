/// Every Visio file the differential suites can reach.
///
/// The bundled fixtures are always present; the upstream libvisio corpus only
/// when the optional `third_party` clone exists (see `third_party/README.md`),
/// so a checkout without it still runs a meaningful subset instead of failing.
library;

import 'dart:io';

const _searchDirectories = <String>[
  'test/fixtures',
  'test/fixtures/vsd',
  'test/fixtures/vsd/external',
  '../../third_party/libvisio/src/test/data',
];

const _visioExtensions = <String>{
  '.vsd', '.vss', '.vst', // binary
  '.vdx', '.vsx', '.vtx', // DiagramML
  '.vsdx', '.vsdm', '.vstx', '.vstm', '.vssx', '.vssm', // OPC
};

List<File> collectVisioCorpus() {
  final out = <File>[];
  for (final path in _searchDirectories) {
    final directory = Directory(path);
    if (!directory.existsSync()) continue;
    for (final entity in directory.listSync()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final dot = name.lastIndexOf('.');
      if (dot < 0) continue;
      if (!_visioExtensions.contains(name.substring(dot).toLowerCase())) {
        continue;
      }
      out.add(entity);
    }
  }
  out.sort((a, b) => a.path.compareTo(b.path));
  return out;
}

/// `parent/name`, enough to tell the bundled and upstream copies apart.
String corpusLabel(File file) {
  final segments = file.uri.pathSegments;
  final parent = segments.length > 1 ? segments[segments.length - 2] : '';
  return '$parent/${segments.last}';
}
