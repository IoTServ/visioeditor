import 'package:test/test.dart';
import 'package:vsdx/agent.dart';
import 'package:vsdx/stencils.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  test('the full catalog is wired (hundreds of shapes)', () {
    expect(kStencils.length, greaterThan(100));
  });

  group('resolveStencilShape', () {
    test('core stencils win and honour requested size', () {
      final s = resolveStencilShape(
          stencil: 'process', id: 1, cx: 3, cy: 4, w: 2.0, h: 1.0);
      expect(s.id, 1);
      expect(s.width, closeTo(2.0, 1e-6));
      expect(s.height, closeTo(1.0, 1e-6));
      expect(s.pinX, closeTo(3, 1e-6));
      expect(s.pinY, closeTo(4, 1e-6));
    });

    test('catalog shapes resolve by name (case/space-insensitive) + resize', () {
      for (final name in <String>['Cloud', 'Class', 'Cisco Router', 'cloudfront']) {
        final s = resolveStencilShape(
            stencil: name, id: 7, cx: 5, cy: 5, w: 2.2, h: 1.3);
        expect(s.geometries, isNotEmpty, reason: '$name has geometry');
        expect(s.width, closeTo(2.2, 1e-6), reason: '$name resized');
        expect(s.height, closeTo(1.3, 1e-6));
      }
    });

    test('explicit fill overrides a catalog shape default', () {
      final s = resolveStencilShape(
          stencil: 'Cloud', id: 2, cx: 1, cy: 1, w: 2, h: 1, fillHex: '#FF0000');
      expect(s.fill.foreground?.value, 0xFFFF0000);
    });

    test('fill none syncs Geometry NoFill for Edraw export', () {
      final s = resolveStencilShape(
        stencil: 'process',
        id: 4,
        cx: 1,
        cy: 1,
        w: 2,
        h: 1,
        fillHex: 'none',
        lineHex: 'none',
      );
      expect(s.fill.pattern, 0);
      expect(s.line.pattern, 0);
      expect(s.geometries, isNotEmpty);
      expect(s.geometries.every((g) => g.noFill), isTrue);
      expect(s.geometries.every((g) => g.noLine), isTrue);
    });

    test('unknown stencil falls back to a rectangle', () {
      final s = resolveStencilShape(
          stencil: 'totally-not-a-shape', id: 3, cx: 0, cy: 0, w: 1, h: 1);
      expect(s.geometries, isNotEmpty);
    });
  });

  group('searchStencils', () {
    test('finds catalog entries beyond the core set', () {
      final cloud = searchStencils('cloud', limit: 20).map((e) => e.name);
      expect(cloud, contains('Cloud'));
      final aws = searchStencils('aws', limit: 20);
      expect(aws, isNotEmpty);
    });

    test('core aliases still resolve', () {
      expect(canonicalStencil('database'), 'cylinder');
      expect(coreNameOrNull('nope'), isNull);
    });
  });

  test('a catalog stencil builds a valid round-trip .vsdx via a spec', () {
    final bytes = DiagramSpec.parse('''
      { "nodes": [
          { "id": "a", "stencil": "Cloud", "text": "Internet" },
          { "id": "b", "stencil": "Class", "text": "User" }
        ],
        "edges": [ { "from": "a", "to": "b" } ] }
    ''').build();
    final doc = const DocumentParser().parse(bytes);
    expect(doc.pages.single.shapes.where((s) => !s.is1D), hasLength(2));
    expect(validateDocument(doc).where((i) => i.severity == 'error'), isEmpty);
  });
}
