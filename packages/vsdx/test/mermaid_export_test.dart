import 'package:test/test.dart';
import 'package:vsdx/agent.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  group('documentToMermaid', () {
    VsdxDocument build(String mmd) =>
        const DocumentParser().parse(mermaidToSpec(mmd).build());

    test('emits a flowchart with nodes and edges', () {
      final mmd = documentToMermaid(build('flowchart TD\n A[Start]-->B[End]'));
      expect(mmd, contains('flowchart TD'));
      expect(mmd, contains('["Start"]'));
      expect(mmd, contains('["End"]'));
      expect(mmd, contains('-->'));
    });

    test('keeps edge labels', () {
      final mmd = documentToMermaid(
          build('flowchart TD\n A{OK?} -->|yes| B[Go]\n A -->|no| C[Stop]'));
      expect(mmd, contains('-->|yes|'));
      expect(mmd, contains('-->|no|'));
    });

    test('round-trips structure (mermaid -> vsdx -> mermaid -> spec)', () {
      final doc = build('flowchart TD\n A[One]-->B[Two]-->C[Three]');
      final mmd = documentToMermaid(doc);
      final spec2 = mermaidToSpec(mmd);
      expect(spec2.nodes, hasLength(3));
      expect(spec2.edges, hasLength(2));
      expect(spec2.nodes.map((n) => n.text), containsAll(<String>['One', 'Two', 'Three']));
    });

    test('fenced wraps in a mermaid code block', () {
      final mmd = documentToMermaid(build('flowchart TD\n A-->B'), fenced: true);
      expect(mmd.trimLeft(), startsWith('```mermaid'));
      expect(mmd.trimRight(), endsWith('```'));
    });
  });
}
