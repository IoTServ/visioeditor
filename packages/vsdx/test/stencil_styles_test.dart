import 'package:test/test.dart';
import 'package:vsdx/stencils.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  group('stencil default styles', () {
    test('flowchart decision uses warning colours', () {
      final s = kStencilGroups
          .firstWhere((g) => g.name == 'Flowchart')
          .stencils
          .firstWhere((s) => s.name == 'Decision')
          .build(1, 0, 0);
      expect(s.fill.foreground?.value, 0xFFFFF2CC);
      expect(s.line.color?.value, 0xFFD6B656);
    });

    test('general rectangle uses primary colours', () {
      final s = kStencilGroups
          .firstWhere((g) => g.name == 'General')
          .stencils
          .firstWhere((s) => s.name == 'Rectangle')
          .build(1, 0, 0);
      expect(s.fill.foreground?.value, 0xFFDAE8FC);
      expect(s.line.color?.value, 0xFF6C8EBF);
      expect(s.line.weightInches, closeTo(0.012, 1e-9));
    });

    test('AWS group uses brand palette', () {
      final group = kStencilGroups.firstWhere((g) => g.name == 'AWS');
      final s = group.stencils.first.build(1, 0, 0);
      if (s.fill.hasFill) {
        expect(s.fill.foreground?.value, 0xFFFFF8E7);
        expect(s.line.color?.value, 0xFFD9822B);
      }
    });

    test('text box stays unfilled', () {
      final s = kStencilGroups
          .firstWhere((g) => g.name == 'General')
          .stencils
          .firstWhere((s) => s.name == 'Text')
          .build(1, 0, 0);
      expect(s.fill.hasFill, isFalse);
      expect(s.line.hasLine, isFalse);
    });

    test('every group stamps group name onto stencils', () {
      for (final g in kStencilGroups) {
        for (final s in g.stencils) {
          expect(s.group, g.name, reason: '${g.name}/${s.name}');
        }
      }
    });
  });
}
