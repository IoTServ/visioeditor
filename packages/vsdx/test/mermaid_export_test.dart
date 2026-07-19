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

    test('preserves LR direction from a wide layout', () {
      final mmd = documentToMermaid(
          build('flowchart LR\n A[One]-->B[Two]-->C[Three]'));
      expect(mmd, contains('flowchart LR'));
      expect(mmd, contains('["One"]'));
      expect(mmd, contains('["Three"]'));
    });

    test('emits grouped leaf shapes and keeps edges connected', () {
      var doc = build('flowchart TD\n A[Start]-->B[End]');
      var page = doc.pages.single;
      final nodes = page.shapes.where((s) => !s.is1D).toList();
      expect(nodes, hasLength(2));
      final gid = page.nextFreeShapeId();
      page = page.group(nodes.map((s) => s.id).toSet(), groupId: gid);
      doc = doc.replacePage(0, page);

      final mmd = documentToMermaid(doc);
      expect(mmd, contains('["Start"]'));
      expect(mmd, contains('["End"]'));
      expect(mmd, contains('-->'));
      // Group shell itself must not appear as a mermaid node id without label.
      expect(mmd, isNot(contains('n$gid[')));

      final listed = listShapes(doc);
      expect(listed.map((m) => m['text']), containsAll(<String>['Start', 'End']));
      expect(listed.any((m) => m['id'] == gid && m['group'] == true), isTrue);
      expect(
        listed.where((m) => m['text'] == 'Start').single['parentId'],
        gid,
      );
    });
  });
}
