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

    test('AWS group brand palette is the fallback', () {
      final colors =
          resolveStencilColors(name: 'Totally Unknown Aws Shape', group: 'AWS');
      expect(colors!.fill, equals(kStencilAws.fill));
      expect(colors.stroke, equals(kStencilAws.stroke));
    });

    test('text box stays unfilled', () {
      final s = kStencilGroups
          .firstWhere((g) => g.name == 'General')
          .stencils
          .firstWhere((s) => s.name == 'Text')
          .build(1, 0, 0);
      expect(s.fill.hasFill, isFalse);
      expect(s.line.hasLine, isFalse);
      // Thumbnail painters fall back to this label when fill/line are off.
      expect(s.text, 'Text');
    });

    test('every group stamps group name onto stencils', () {
      for (final g in kStencilGroups) {
        for (final s in g.stencils) {
          expect(s.group, g.name, reason: '${g.name}/${s.name}');
        }
      }
    });

    test('BPMN event and gateway overrides', () {
      final start = kStencilGroups
          .firstWhere((g) => g.name == 'BPMN')
          .stencils
          .firstWhere((s) => s.name == 'Start Event')
          .build(1, 0, 0);
      expect(start.fill.foreground?.value, 0xFFD5E8D4);
      expect(start.line.color?.value, 0xFF82B366);

      final end = kStencilGroups
          .firstWhere((g) => g.name == 'BPMN')
          .stencils
          .firstWhere((s) => s.name == 'End Event')
          .build(1, 0, 0);
      expect(end.fill.foreground?.value, 0xFFF8CECC);
      expect(end.line.color?.value, 0xFFB85450);

      final exclusive = kStencilGroups
          .firstWhere((g) => g.name == 'BPMN')
          .stencils
          .firstWhere((s) => s.name == 'Exclusive Gateway')
          .build(1, 0, 0);
      expect(exclusive.fill.foreground?.value, 0xFFFFF2CC);
      expect(exclusive.line.color?.value, 0xFFD6B656);
    });

    test('UML and ER diagram name overrides', () {
      final cls = kStencilGroups
          .firstWhere((g) => g.name == 'UML')
          .stencils
          .firstWhere((s) => s.name == 'Class')
          .build(1, 0, 0);
      expect(cls.fill.foreground?.value, 0xFFDAE8FC);

      final entity = kStencilGroups
          .firstWhere((g) => g.name == 'ER')
          .stencils
          .firstWhere((s) => s.name == 'Entity')
          .build(1, 0, 0);
      expect(entity.fill.foreground?.value, 0xFFD5E8D4);

      final weak = kStencilGroups
          .firstWhere((g) => g.name == 'ER')
          .stencils
          .firstWhere((s) => s.name == 'Weak Entity')
          .build(1, 0, 0);
      expect(weak.fill.foreground?.value, 0xFFFFF2CC);
    });

    test('network device overrides', () {
      final server = kStencilGroups
          .firstWhere((g) => g.name == 'Network')
          .stencils
          .firstWhere((s) => s.name == 'Server')
          .build(1, 0, 0);
      expect(server.fill.foreground?.value, 0xFFD5F5F0);
      expect(server.line.color?.value, 0xFF2E8B7A);

      final fw = kStencilGroups
          .firstWhere((g) => g.name == 'Network')
          .stencils
          .firstWhere((s) => s.name == 'Firewall')
          .build(1, 0, 0);
      expect(fw.fill.foreground?.value, 0xFFF8CECC);

      final lb = kStencilGroups
          .firstWhere((g) => g.name == 'Network')
          .stencils
          .firstWhere((s) => s.name == 'Load Balancer')
          .build(1, 0, 0);
      expect(lb.fill.foreground?.value, 0xFFFFF2CC);
    });

    test('name heuristics for cloud catalogue shapes', () {
      final rds = resolveStencilColors(name: 'RDS', group: 'AWS');
      expect(rds!.fill, equals(kStencilSuccess.fill));

      final fw = resolveStencilColors(name: 'Firewall Appliance', group: 'Network');
      expect(fw!.fill, equals(kStencilDanger.fill));

      final lb = resolveStencilColors(name: 'Application Load Balancer', group: 'Azure');
      expect(lb!.fill, equals(kStencilWarning.fill));

      final lambda = resolveStencilColors(name: 'Lambda', group: 'AWS');
      expect(lambda!.fill, equals(kStencilAccent.fill));
    });

    test('filled library shapes receive non-default colours', () {
      // White fill + black stroke is the factory default; styled stencils
      // should leave that behind (except intentionally unfilled shapes).
      const factoryFill = 0xFFFFFFFF;
      const factoryLine = 0xFF000000;
      var checked = 0;
      for (final g in kStencilGroups) {
        for (final stencil in g.stencils) {
          final s = stencil.build(1, 0, 0);
          if (!s.fill.hasFill || !s.line.hasLine || s.is1D) continue;
          checked++;
          final sameAsFactory = s.fill.foreground?.value == factoryFill &&
              s.line.color?.value == factoryLine;
          expect(
            sameAsFactory,
            isFalse,
            reason: '${g.name}/${stencil.name} still uses factory white/black',
          );
        }
      }
      expect(checked, greaterThan(100));
    });

    test('applyStencilStyle on 1D clears line themeColorIndex', () {
      final connector = VsdxShapeFactory.line(
        id: 1,
        ax: 0,
        ay: 0,
        bx: 2,
        by: 1,
        line: const VsdxLine(
          themeColorIndex: ThemeSlot.accent3,
          weightInches: 0.02,
        ),
      );
      final styled = applyStencilStyle(
        connector,
        colors: resolveStencilColors(name: 'Connector', group: 'General')!,
      );
      expect(styled.line.color, isNotNull);
      expect(styled.line.themeColorIndex, isNull);
    });
  });
}
