import 'package:test/test.dart';
import 'package:vsdx/agent.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  group('style presets', () {
    test('listStylePresets exposes built-ins', () {
      expect(listStylePresets(), containsAll(<String>['default', 'corporate', 'dark']));
    });

    test('applyStylePreset fills role colours and maps database→cylinder', () {
      final raw = DiagramSpec(
        style: 'corporate',
        nodes: <NodeSpec>[
          NodeSpec(id: 'api', text: 'API', role: 'service'),
          NodeSpec(id: 'db', text: 'DB', role: 'database'),
          NodeSpec(id: 'custom', text: 'X', fill: '#112233', line: '#445566'),
        ],
        edges: <EdgeSpec>[EdgeSpec(from: 'api', to: 'db')],
      );
      final styled = applyStylePreset(raw, 'corporate');
      final api = styled.nodes.firstWhere((n) => n.id == 'api');
      final db = styled.nodes.firstWhere((n) => n.id == 'db');
      final custom = styled.nodes.firstWhere((n) => n.id == 'custom');
      expect(api.fill, '#E3F2FD');
      expect(api.line, '#1565C0');
      expect(db.stencil, 'cylinder');
      expect(db.fill, '#E8F5E9');
      expect(custom.fill, '#112233'); // explicit wins
      expect(styled.style, isNull); // already applied
    });

    test('DiagramSpec.build applies style from JSON', () {
      final bytes = DiagramSpec.parse('''
{
  "style": "dark",
  "nodes": [
    {"id": "a", "text": "A", "role": "service"},
    {"id": "b", "text": "B", "role": "database"}
  ],
  "edges": [{"from": "a", "to": "b"}]
}
''').build();
      final doc = const DocumentParser().parse(bytes);
      final nodes = doc.pages.single.shapes.where(
        (s) => !s.is1D && s.name != kLibvisioPageColorShapeName,
      );
      expect(nodes, hasLength(2));
      expect(
        doc.pages.single.shapes.first.name,
        kLibvisioPageColorShapeName,
        reason: 'dark preset PageColor is not a token; Draw paints a plate',
      );
      expect(validateDocument(doc).where((i) => i.severity == 'error'), isEmpty);
      // Dark primary fill on the service node.
      final fills = nodes
          .map((s) => s.fill.foreground?.value)
          .whereType<int>()
          .toSet();
      expect(fills, contains(0xFF004870));
    });

    test('unknown style throws', () {
      expect(
        () => applyStylePreset(DiagramSpec(nodes: <NodeSpec>[]), 'neon'),
        throwsArgumentError,
      );
    });
  });
}
