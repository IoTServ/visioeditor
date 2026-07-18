import 'package:test/test.dart';
import 'package:vsdx/agent.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  group('mermaidToSpec', () {
    test('parses direction, shapes, and labelled edges', () {
      final spec = mermaidToSpec('''
flowchart TD
  A([Start]) --> B[Validate]
  B --> C{OK?}
  C -->|yes| D[(Order DB)]
  C -->|no| B
''');
      expect(spec.direction, 'TB');
      final byId = {for (final n in spec.nodes) n.id: n};
      expect(byId['A']!.stencil, 'terminator');
      expect(byId['A']!.text, 'Start');
      expect(byId['B']!.stencil, 'process');
      expect(byId['C']!.stencil, 'diamond');
      expect(byId['D']!.stencil, 'cylinder');
      expect(byId['D']!.text, 'Order DB');
      expect(spec.edges, hasLength(4));
      final yes = spec.edges.firstWhere((e) => e.from == 'C' && e.to == 'D');
      expect(yes.label, 'yes');
    });

    test('LR header maps to LR; graph keyword works', () {
      final spec = mermaidToSpec('graph LR\n  A-->B-->C');
      expect(spec.direction, 'LR');
      expect(spec.nodes.map((n) => n.id), containsAll(<String>['A', 'B', 'C']));
      expect(spec.edges, hasLength(2)); // chain A->B->C
    });

    test('inline label form (A -- text --> B)', () {
      final spec = mermaidToSpec('flowchart TD\n  A -- go --> B');
      expect(spec.edges.single.label, 'go');
      expect(spec.edges.single.from, 'A');
      expect(spec.edges.single.to, 'B');
    });

    test('various shapes map correctly', () {
      final spec = mermaidToSpec('''
flowchart TD
  a[rect]
  b(round)
  c{dia}
  d{{hex}}
  e[/para/]
  f((circ))
''');
      final byId = {for (final n in spec.nodes) n.id: n};
      expect(byId['a']!.stencil, 'process');
      expect(byId['b']!.stencil, 'rounded');
      expect(byId['c']!.stencil, 'diamond');
      expect(byId['d']!.stencil, 'hexagon');
      expect(byId['e']!.stencil, 'data');
      expect(byId['f']!.stencil, 'ellipse');
    });

    test('comments and non-modelled directives are ignored', () {
      final spec = mermaidToSpec('''
flowchart TD
  %% this is a comment
  A --> B
  classDef big fill:#f00
  class A big
''');
      expect(spec.nodes.map((n) => n.id), <String>['A', 'B']);
      expect(spec.edges, hasLength(1));
    });

    test('builds a valid, round-trip .vsdx', () {
      final bytes = mermaidToSpec('flowchart LR\n A[One]-->B[Two]-->C[Three]').build();
      final doc = const DocumentParser().parse(bytes);
      final page = doc.pages.single;
      expect(page.shapes.where((s) => !s.is1D), hasLength(3));
      expect(page.shapes.where((s) => s.is1D), hasLength(2));
      expect(validateDocument(doc).where((i) => i.severity == 'error'), isEmpty);
    });
  });
}
