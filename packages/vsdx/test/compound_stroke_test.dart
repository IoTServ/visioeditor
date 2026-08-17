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

  test('compoundRails type 4 emits three rails (triple)', () {
    final t = compoundRails(4, 0.10);
    expect(t.length, 3);
    expect(t[1].offset, closeTo(0, 1e-9));
    expect(t[0].offset, greaterThan(0));
    expect(t[2].offset, lessThan(0));
    final sumW = t[0].width + t[1].width + t[2].width;
    expect(sumW, lessThan(0.10));
    expect(sumW, greaterThan(0.05));
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

  test('trimPolylineEnds preserves elbows and trims both endpoints', () {
    final trimmed = trimPolylineEnds(
      const <Offset2D>[
        Offset2D(0, 0),
        Offset2D(2, 0),
        Offset2D(2, 2),
      ],
      begin: 0.5,
      end: 0.75,
    );
    expect(trimmed, hasLength(3));
    expect(trimmed.first.x, closeTo(0.5, 1e-9));
    expect(trimmed[1], const Offset2D(2, 0));
    expect(trimmed.last.y, closeTo(1.25, 1e-9));
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

  test('samplePathD flattens circular A arcs off the chord', () {
    // Semicircle from (0,0) to (2,0) with r=1, sweep=0 → apex near (1,-1).
    final arc = samplePathD('M 0 0 A 1 1 0 0 0 2 0');
    expect(arc.points.length, greaterThan(3));
    final midY = arc.points.map((p) => p.y).reduce((a, b) => a < b ? a : b);
    expect(midY, lessThan(-0.5),
        reason: 'arc samples must leave the chord, not lerp along it');
  });
}
