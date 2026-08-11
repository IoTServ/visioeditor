import 'stencils.dart';

/// A brand-neutral category node used by the shape-library browser.
class StencilLibraryNode {
  StencilLibraryNode({required this.label, required this.key});

  final String label;
  final String key;
  final List<StencilGroup> groups = <StencilGroup>[];
  final List<StencilLibraryNode> children = <StencilLibraryNode>[];

  Iterable<StencilGroup> get descendantGroups sync* {
    yield* groups;
    for (final child in children) {
      yield* child.descendantGroups;
    }
  }

  int get shapeCount => descendantGroups.fold<int>(
    0,
    (count, group) => count + group.stencils.length,
  );
}

/// Returns the user-facing category path for an internal library name.
///
/// Imported libraries retain their original identifiers for persistence and
/// round-trip compatibility, while the browser exposes only useful category
/// names. Dynamic-library implementation keys are also removed so equivalent
/// XML and dynamic categories can share one branch.
List<String> stencilLibraryPath(
  String rawName, {
  String Function(String name)? localizeBuiltIn,
}) {
  const xmlPrefix = 'Draw.io / ';
  const dynamicPrefix = 'Draw.io JS / ';

  List<String> parts;
  if (rawName.startsWith(dynamicPrefix)) {
    parts = rawName.substring(dynamicPrefix.length).split(' / ');
    if (parts.length > 1) parts.removeAt(0);
  } else if (rawName.startsWith(xmlPrefix)) {
    parts = rawName.substring(xmlPrefix.length).split(' / ');
  } else {
    return <String>[localizeBuiltIn?.call(rawName) ?? rawName];
  }

  final cleaned = parts
      .map(_cleanLibrarySegment)
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  return cleaned.isEmpty ? const <String>['Shapes'] : cleaned;
}

String stencilLibraryDisplayName(
  String rawName, {
  String Function(String name)? localizeBuiltIn,
}) => stencilLibraryPath(rawName, localizeBuiltIn: localizeBuiltIn).join(' / ');

/// Builds a merged, alphabetically sorted category tree.
List<StencilLibraryNode> buildStencilLibraryTree(
  Iterable<StencilGroup> groups, {
  String Function(String name)? localizeBuiltIn,
}) {
  final roots = <StencilLibraryNode>[];
  for (final group in groups) {
    final path = stencilLibraryPath(
      group.name,
      localizeBuiltIn: localizeBuiltIn,
    );
    var siblings = roots;
    StencilLibraryNode? node;
    final keyParts = <String>[];
    for (final segment in path) {
      final identity = segment.toLowerCase();
      keyParts.add(identity);
      node = null;
      for (final candidate in siblings) {
        if (candidate.label.toLowerCase() == identity) {
          node = candidate;
          break;
        }
      }
      if (node == null) {
        node = StencilLibraryNode(label: segment, key: keyParts.join('\u0000'));
        siblings.add(node);
      }
      siblings = node.children;
    }
    node!.groups.add(group);
  }

  void sortChildren(List<StencilLibraryNode> nodes) {
    nodes.sort(
      (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
    );
    for (final node in nodes) {
      sortChildren(node.children);
    }
  }

  sortChildren(roots);
  return List<StencilLibraryNode>.unmodifiable(roots);
}

String _cleanLibrarySegment(String value) {
  final trimmed = value.trim().replaceAll(RegExp(r'\s{2,}'), ' ');
  const aliases = <String, String>{
    'android': 'Android',
    'archimate21': 'ArchiMate 2.1',
    'archimate 3.2': 'ArchiMate 3.2',
    'arrows': 'Arrows',
    'basic': 'Basic',
    'bootstrap': 'Bootstrap',
    'cabinets': 'Cabinets',
    'floorplans': 'Floorplan',
    'flowchart': 'Flowchart',
    'uml 2.5': 'UML 2.5',
  };
  return aliases[trimmed.toLowerCase()] ?? trimmed;
}
