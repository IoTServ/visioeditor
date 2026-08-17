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
    // libvisio inserts Q (2,0) between the trimmed points (1.75,0) and
    // (2,0.25); the t=0.5 sample is therefore exactly (1.9375,0.0625).
    expect(out[4].x, closeTo(1.9375, 1e-9));
    expect(out[4].y, closeTo(0.0625, 1e-9));
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

  test('filletPolylinePath preserves libvisio quadratic corner controls', () {
    const pts = <Offset2D>[
      Offset2D(0, 0),
      Offset2D(2, 0),
      Offset2D(2, 2),
    ];
    final path = filletPolylinePath(pts, 0.25)!;
    expect(path.start, const Offset2D(0, 0));
    expect(path.segments, hasLength(3));
    expect(path.segments[0].end, const Offset2D(1.75, 0));
    expect(path.segments[0].control, isNull);
    expect(path.segments[1].control, const Offset2D(2, 0));
    expect(path.segments[1].end.x, closeTo(2, 1e-9));
    expect(path.segments[1].end.y, closeTo(0.25, 1e-9));
    expect(path.segments[2].end, const Offset2D(2, 2));
  });

  test('polylineLooksClosed treats filled open rings as closed', () {
    const pts = <Offset2D>[
      Offset2D(0, 0),
      Offset2D(2, 0),
      Offset2D(2, 2),
      Offset2D(0, 2),
    ];
    expect(polylineLooksClosed(pts, noFill: false), isTrue);
    expect(polylineLooksClosed(pts, noFill: true), isFalse);
    expect(
      polylineLooksClosed(
        const <Offset2D>[
          Offset2D(0, 0),
          Offset2D(2, 0),
          Offset2D(2, 2),
          Offset2D(0, 0),
        ],
        noFill: true,
      ),
      isTrue,
    );
  });
}
