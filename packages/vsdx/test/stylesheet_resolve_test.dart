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
}
