import 'dart:math' as math;

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

  test('filletPolylinePath chamfers corners as LineTo', () {
    const pts = <Offset2D>[
      Offset2D(0, 0),
      Offset2D(2, 0),
      Offset2D(2, 2),
    ];
    final path = filletPolylinePath(pts, 0.25, chamfer: true)!;
    expect(path.start, const Offset2D(0, 0));
    expect(path.segments, hasLength(3));
    expect(path.segments[0].end, const Offset2D(1.75, 0));
    expect(path.segments[0].control, isNull);
    expect(path.segments[1].control, isNull);
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

  test('bakePolylineRounding writes libvisio quadratic corner rows', () {
    const geometry = VsdxGeometry(
      commands: <VsdxPathCommand>[
        MoveTo(0, 0),
        LineTo(2, 0),
        LineTo(2, 1),
        LineTo(0, 1),
        LineTo(0, 0),
      ],
      rowIndices: <int>[1, 2, 3, 4, 5],
    );
    final baked = bakePolylineRounding(
      geometry,
      width: 2,
      height: 1,
      radius: 0.08,
    );

    expect(baked.commands, hasLength(9));
    expect(baked.commands.whereType<RelQuadBezTo>(), hasLength(4));
    expect(baked.rowIndices, isEmpty);
    expect((baked.commands.first as MoveTo).x, closeTo(0.08, 1e-9));
  });

  test('bakePolylineRounding chamfers bevel corners as LineTo', () {
    const geometry = VsdxGeometry(
      noFill: true,
      commands: <VsdxPathCommand>[
        MoveTo(0, 0),
        LineTo(2, 0),
        LineTo(2, 2),
      ],
    );
    final baked = bakePolylineRounding(
      geometry,
      width: 2,
      height: 2,
      radius: 0.25,
      chamfer: true,
    );
    expect(baked.commands.whereType<RelQuadBezTo>(), isEmpty);
    expect(baked.commands.whereType<LineTo>(), hasLength(3));
    expect((baked.commands[1] as LineTo).x, closeTo(1.75, 1e-9));
    expect((baked.commands[2] as LineTo).x, closeTo(2, 1e-9));
    expect((baked.commands[2] as LineTo).y, closeTo(0.25, 1e-9));
  });

  test('strokeMiterRatio is √2 at a 90° elbow', () {
    expect(
      strokeMiterRatio(
        const Offset2D(0, 0),
        const Offset2D(2, 0),
        const Offset2D(2, 2),
      ),
      closeTo(math.sqrt(2), 1e-9),
    );
  });

  test('bakePolylineRounding chamfers only corners above miterLimit', () {
    const geometry = VsdxGeometry(
      noFill: true,
      commands: <VsdxPathCommand>[
        MoveTo(0, 0),
        LineTo(2, 0),
        LineTo(2, 2),
      ],
    );
    final clipped = bakePolylineRounding(
      geometry,
      width: 2,
      height: 2,
      radius: 0.25,
      chamfer: true,
      miterLimit: 1,
    );
    expect(clipped.commands.whereType<RelQuadBezTo>(), isEmpty);
    expect(
      clipped.commands.whereType<LineTo>().any(
            (command) =>
                (command.x - 2).abs() < 1e-9 && (command.y - 0).abs() < 1e-9,
          ),
      isFalse,
      reason: '90° elbow ratio √2 exceeds miterLimit 1',
    );
    expect((clipped.commands[1] as LineTo).x, closeTo(1.75, 1e-9));
    expect((clipped.commands[2] as LineTo).x, closeTo(2, 1e-9));
    expect((clipped.commands[2] as LineTo).y, closeTo(0.25, 1e-9));

    final kept = bakePolylineRounding(
      geometry,
      width: 2,
      height: 2,
      radius: 0.25,
      chamfer: true,
      miterLimit: 2,
    );
    expect(
      kept.commands.whereType<LineTo>().any(
            (command) =>
                (command.x - 2).abs() < 1e-9 && (command.y - 0).abs() < 1e-9,
          ),
      isTrue,
      reason: '90° elbow ratio √2 is under miterLimit 2',
    );
  });

  test('polylineHasDrawClippedMiter ignores 90° elbows and flags hairpins', () {
    expect(
      polylineHasDrawClippedMiter(
        const <Offset2D>[
          Offset2D(0, 0),
          Offset2D(2, 0),
          Offset2D(2, 2),
        ],
        closed: false,
      ),
      isFalse,
    );
    expect(
      polylineHasDrawClippedMiter(
        const <Offset2D>[
          Offset2D(0.2, 1.0),
          Offset2D(2.5, 1.0),
          Offset2D(0.2, 1.45),
        ],
        closed: false,
      ),
      isTrue,
    );
  });

  test('polylineHasElbow flags a 90° turn and ignores a straight run', () {
    expect(
      polylineHasElbow(
        const <Offset2D>[
          Offset2D(0, 0),
          Offset2D(2, 0),
          Offset2D(2, 2),
        ],
        closed: false,
      ),
      isTrue,
    );
    expect(
      polylineHasElbow(
        const <Offset2D>[
          Offset2D(0, 0),
          Offset2D(1, 0),
          Offset2D(2, 0),
        ],
        closed: false,
      ),
      isFalse,
    );
  });

  test('bakePolylineRounding leaves already-curved geometry unchanged', () {
    const geometry = VsdxGeometry(commands: <VsdxPathCommand>[
      MoveTo(0, 0),
      QuadBezTo(x: 1, y: 1, x1: 1, y1: 0),
      LineTo(0, 1),
    ]);
    expect(
      bakePolylineRounding(
        geometry,
        width: 1,
        height: 1,
        radius: 0.08,
      ),
      same(geometry),
    );
  });
}
