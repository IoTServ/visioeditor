import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  test('resolveFill walks FillStyle parent chain like resolveLine', () {
    const parent = VsdxStyleSheet(
      id: 1,
      name: 'ParentFill',
      fill: VsdxFill(
        foreground: VsdxColor(0xFFE53935),
        pattern: 1,
      ),
    );
    const child = VsdxStyleSheet(
      id: 2,
      name: 'ChildFill',
      fillStyleId: 1,
      fill: VsdxFill(pattern: 2),
    );
    const registry = StyleSheetRegistry(<int, VsdxStyleSheet>{
      1: parent,
      2: child,
    });
    final fill = registry.resolveFill(2)!;
    expect(fill.pattern, 2);
    expect(fill.foreground?.value, 0xFFE53935);
  });

  test('resolveLine still resolves weight/colour', () {
    const sheet = VsdxStyleSheet(
      id: 3,
      name: 'LineSheet',
      line: VsdxLine(
        color: VsdxColor(0xFF1565C0),
        weightInches: 0.02,
        pattern: 2,
      ),
    );
    const registry = StyleSheetRegistry(<int, VsdxStyleSheet>{3: sheet});
    final line = registry.resolveLine(3)!;
    expect(line.color?.value, 0xFF1565C0);
    expect(line.weightInches, closeTo(0.02, 1e-9));
    expect(line.pattern, 2);
  });

  test('resolveLine skips F=Inh LineWeight and takes parent', () {
    const parent = VsdxStyleSheet(
      id: 10,
      name: 'ParentLine',
      line: VsdxLine(weightInches: 0.05, pattern: 1),
      lineDefinedCells: {'LineWeight', 'LinePattern'},
    );
    const child = VsdxStyleSheet(
      id: 11,
      name: 'ChildLine',
      lineStyleId: 10,
      // SoftEdges only — LineWeight Inh is not in defined cells.
      line: VsdxLine(softEdgesInches: 0.1, weightInches: 0.01),
      lineDefinedCells: {'SoftEdgesSize'},
    );
    const registry = StyleSheetRegistry(<int, VsdxStyleSheet>{
      10: parent,
      11: child,
    });
    final line = registry.resolveLine(11)!;
    expect(line.weightInches, closeTo(0.05, 1e-9));
    expect(line.softEdgesInches, closeTo(0.1, 1e-9));
  });

  test('resolveLine picks up Rounding from LineStyle chain', () {
    const sheet = VsdxStyleSheet(
      id: 12,
      name: 'RoundLine',
      line: VsdxLine(roundingInches: 0.125, weightInches: 0.01),
      lineDefinedCells: {'Rounding', 'LineWeight'},
    );
    const registry = StyleSheetRegistry(<int, VsdxStyleSheet>{12: sheet});
    final line = registry.resolveLine(12)!;
    expect(line.roundingInches, closeTo(0.125, 1e-9));
  });
}
