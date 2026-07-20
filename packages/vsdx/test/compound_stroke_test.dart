import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  test('compoundRails distinguishes double / thick-thin / thin-thick', () {
    final d = compoundRails(1, 0.10);
    expect(d.length, 2);
    expect(d[0].width, closeTo(d[1].width, 1e-9));
    expect(d[0].offset, closeTo(-d[1].offset, 1e-9));

    final tt = compoundRails(2, 0.10);
    expect(tt.length, 2);
    expect(tt[0].width, closeTo(0.055, 1e-9));
    expect(tt[1].width, closeTo(0.025, 1e-9));
    expect(tt[0].width > tt[1].width, isTrue);

    final tn = compoundRails(3, 0.10);
    expect(tn[0].width, closeTo(0.025, 1e-9));
    expect(tn[1].width, closeTo(0.055, 1e-9));
  });

  test('offsetPolyline shifts an open segment along the left normal', () {
    final pts = <Offset2D>[
      const Offset2D(0, 0),
      const Offset2D(2, 0),
    ];
    final up = offsetPolyline(pts, 0.5);
    expect(up.length, 2);
    expect(up.first.y, closeTo(0.5, 1e-9));
    expect(up.last.y, closeTo(0.5, 1e-9));
  });

  test('samplePathD parses a simple line and closed rect', () {
    final line = samplePathD('M 1 2 L 4 2');
    expect(line.closed, isFalse);
    expect(line.points.length, 2);
    expect(line.points.first.x, closeTo(1, 1e-9));
    expect(line.points.last.x, closeTo(4, 1e-9));

    final rect = samplePathD('M 0 0 L 1 0 L 1 1 L 0 1 Z');
    expect(rect.closed, isTrue);
    expect(rect.points.length, greaterThanOrEqualTo(4));
  });

  test('VsdxFill.copyWith can clear theme background', () {
    const fill = VsdxFill(
      pattern: 2,
      themeForegroundIndex: ThemeSlot.accent1,
      themeBackgroundIndex: ThemeSlot.accent2,
    );
    final cleared = fill.copyWith(clearThemeBackgroundIndex: true);
    expect(cleared.themeBackgroundIndex, isNull);
    expect(cleared.themeForegroundIndex, ThemeSlot.accent1);
  });

  test('withSolidForeground clears FillBkgnd theme on solid fills', () {
    const hatch = VsdxFill(
      pattern: 1,
      themeBackgroundIndex: ThemeSlot.accent2,
    );
    final solid = hatch.withSolidForeground(const VsdxColor(0xFF123456));
    expect(solid.themeBackgroundIndex, isNull);
    expect(solid.themeForegroundIndex, isNull);
  });
}
