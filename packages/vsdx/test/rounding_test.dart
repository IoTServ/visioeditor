import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  test('filletPolyline leaves short paths unchanged', () {
    final pts = <Offset2D>[
      const Offset2D(0, 0),
      const Offset2D(1, 0),
    ];
    expect(filletPolyline(pts, 0.1), same(pts));
    expect(filletPolyline(pts, 0), same(pts));
  });

  test('filletPolyline rounds a right-angle elbow', () {
    final pts = <Offset2D>[
      const Offset2D(0, 0),
      const Offset2D(2, 0),
      const Offset2D(2, 2),
    ];
    final out = filletPolyline(pts, 0.25);
    expect(out.length, greaterThan(pts.length));
    // First / last endpoints preserved.
    expect(out.first.x, closeTo(0, 1e-9));
    expect(out.first.y, closeTo(0, 1e-9));
    expect(out.last.x, closeTo(2, 1e-9));
    expect(out.last.y, closeTo(2, 1e-9));
    // Sharp corner (2,0) should be replaced — no sample exactly at the tip
    // once trimmed (samples lie on the fillet).
    expect(
      out.any((p) => (p.x - 2).abs() < 1e-9 && (p.y - 0).abs() < 1e-9),
      isFalse,
    );
  });

  test('filletPolyline closed square has no sharp corners', () {
    final pts = <Offset2D>[
      const Offset2D(0, 0),
      const Offset2D(2, 0),
      const Offset2D(2, 2),
      const Offset2D(0, 2),
    ];
    final out = filletPolyline(pts, 0.3, closed: true);
    expect(out.length, greaterThan(pts.length));
  });
}
