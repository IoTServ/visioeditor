/// Every geometry row type we parse has to paint, and a save has to emit a
/// row LibreOffice's libvisio importer still collects.
///
/// libvisio's VSDX token map has no CubBezTo / QuadBezTo / RelArcTo /
/// RelPolylineTo / RelInfiniteLine / RelSpline* / RelNURBSTo. Leaving those
/// `T=` values in the package makes Draw skip the curve. The writer rewrites
/// them to RelCubBezTo / RelQuadBezTo / ArcTo / PolylineTo / InfiniteLine /
/// Spline* / NURBSTo, which `VSDXMLParserBase::readGeometry` handles. A 1-D
/// CubBezTo whose Height is 0 cannot use Rel* (fy×Height = 0); a save
/// samples LineTo instead so Draw keeps the bow.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

import 'support/libvisio_oracle.dart';

void main() {
  const writer = VsdxWriter();
  const parser = DocumentParser();

  test('VDX CubBezTo / QuadBezTo / RelArcTo parse, paint, and save for LO', () {
    final bytes = _read('test/fixtures/vdx_all_types.vdx');
    final parsed = parseVisio(bytes, sourceName: 'vdx_all_types.vdx');
    final page = parsed.document.pages.single;
    final curves = page.findShapeById(2)!;
    expect(
      curves.geometries.expand((g) => g.commands).map((c) => c.runtimeType),
      containsAll(<Type>[CubBezTo, QuadBezTo, ArcTo]),
    );
    expect(
      page.findShapeById(7)!.geometries
          .expand((g) => g.commands)
          .whereType<RelArcTo>(),
      isNotEmpty,
    );

    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg, contains(' C '), reason: 'CubBezTo must emit a cubic');
    expect(svg, contains(' Q '), reason: 'QuadBezTo must emit a quadratic');

    final saved = writer.write(
      originalBytes: parsed.originalBytes,
      edited: parsed.document,
    );
    final xml = VsdxPackage.open(saved)
        .readPartXml('/visio/pages/page1.xml')!
        .toXmlString();
    expect(xml, isNot(contains('T="CubBezTo"')));
    expect(xml, isNot(contains('T="QuadBezTo"')));
    expect(xml, isNot(contains('T="RelArcTo"')));
    expect(xml, contains('T="RelCubBezTo"'));
    expect(xml, contains('T="RelQuadBezTo"'));
    expect(xml, contains('T="ArcTo"'));

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    final before = oracle.svgPages(bytes)?.join() ?? '';
    final afterPages = oracle.svgPages(saved);
    expect(afterPages, isNotNull);
    final after = afterPages!.join();
    // libvisio writes `C12.0` after a newline, not `C 12.0`. Spline rows
    // already emit cubics in the source; RelCubBezTo must add more.
    expect(
      RegExp(r'\nC').allMatches(after).length,
      greaterThan(RegExp(r'\nC').allMatches(before).length),
      reason: 'libvisio must collect the rewritten RelCubBezTo',
    );
    expect(
      RegExp(r'\nQ').allMatches(after).length,
      greaterThan(RegExp(r'\nQ').allMatches(before).length),
      reason: 'libvisio must collect the rewritten RelQuadBezTo',
    );
  });

  test('every VSDX-era row type paints and round-trips through libvisio', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final page = doc.pages.first;
    var nextId = page.nextFreeShapeId();
    var built = page;

    VsdxShape stroke(String name, List<VsdxPathCommand> commands) {
      final id = nextId++;
      return VsdxShape(
        id: id,
        name: name,
        pinX: 2,
        pinY: 2,
        width: 2,
        height: 1,
        geometries: <VsdxGeometry>[
          VsdxGeometry(noFill: true, commands: commands),
        ],
      );
    }

    for (final shape in <VsdxShape>[
      stroke('CubBezTo', const <VsdxPathCommand>[
        MoveTo(0, 0),
        CubBezTo(x: 2, y: 0, x1: 0.4, y1: 1, x2: 1.6, y2: 1),
      ]),
      stroke('QuadBezTo', const <VsdxPathCommand>[
        MoveTo(0, 0),
        QuadBezTo(x: 2, y: 0, x1: 1, y1: 1),
      ]),
      stroke('RelCubBezTo', const <VsdxPathCommand>[
        RelMoveTo(0, 0),
        RelCubBezTo(fx: 1, fy: 0, fx1: 0.2, fy1: 1, fx2: 0.8, fy2: 1),
      ]),
      stroke('RelQuadBezTo', const <VsdxPathCommand>[
        RelMoveTo(0, 0),
        RelQuadBezTo(fx: 1, fy: 0, fx1: 0.5, fy1: 1),
      ]),
      stroke('RelArcTo', const <VsdxPathCommand>[
        RelMoveTo(0, 0),
        RelArcTo(fx: 1, fy: 0, fbow: 0.2),
      ]),
      stroke('EllipticalArcTo', const <VsdxPathCommand>[
        MoveTo(0, 0),
        EllipticalArcTo(
          x: 2,
          y: 0,
          controlX: 1,
          controlY: 0.8,
          angle: 0,
          eccentricity: 1,
        ),
      ]),
      stroke('RelEllipticalArcTo', const <VsdxPathCommand>[
        RelMoveTo(0, 0),
        RelEllipticalArcTo(
          fx: 1,
          fy: 0,
          fcx: 0.5,
          fcy: 0.8,
          angle: 0,
          eccentricity: 1,
        ),
      ]),
      stroke('Ellipse', const <VsdxPathCommand>[
        EllipseCmd(cx: 1, cy: 0.5, aX: 2, aY: 0.5, bX: 1, bY: 1),
      ]),
      stroke('PolylineTo', const <VsdxPathCommand>[
        MoveTo(0, 0),
        PolylineTo(
          x: 2,
          y: 0,
          vertices: <Offset2D>[Offset2D(0.5, 0.8), Offset2D(1.5, 0.2)],
        ),
      ]),
      stroke('RelPolylineTo', const <VsdxPathCommand>[
        RelMoveTo(0, 0),
        PolylineTo(
          x: 1,
          y: 0,
          vertices: <Offset2D>[Offset2D(0.5, 0.8)],
          relative: true,
        ),
      ]),
      stroke('InfiniteLine', const <VsdxPathCommand>[
        InfiniteLineCmd(x: 0, y: 0.5, a: 2, b: 0.5),
      ]),
      stroke('RelInfiniteLine', const <VsdxPathCommand>[
        InfiniteLineCmd(x: 0, y: 0.5, a: 1, b: 0.5, relative: true),
      ]),
      stroke('Spline', const <VsdxPathCommand>[
        MoveTo(0, 0.2),
        SplineStart(x: 0.7, y: 0.9, a: 0.5, b: 0, c: 2, degree: 3),
        SplineKnot(x: 1.4, y: 0.2, knot: 1),
        SplineKnot(x: 2, y: 0.9, knot: 1.5),
      ]),
      stroke('RelSpline', const <VsdxPathCommand>[
        RelMoveTo(0, 0.2),
        SplineStart(
          x: 0.35,
          y: 0.9,
          a: 0.5,
          b: 0,
          c: 2,
          degree: 3,
          relative: true,
        ),
        SplineKnot(x: 0.7, y: 0.2, knot: 1, relative: true),
        SplineKnot(x: 1, y: 0.9, knot: 1.5, relative: true),
      ]),
      stroke('NURBSTo', <VsdxPathCommand>[
        const MoveTo(0, 0),
        NurbsTo(
          x: 2,
          y: 0,
          controlPoints: const <Offset2D>[Offset2D(0.7, 1), Offset2D(1.3, 1)],
          weights: const <double>[1, 1],
          knots: const <double>[0, 0, 0, 1, 1, 1],
          degree: 3,
        ),
      ]),
      stroke('RelNURBSTo', <VsdxPathCommand>[
        const RelMoveTo(0, 0),
        NurbsTo(
          x: 1,
          y: 0,
          controlPoints: const <Offset2D>[Offset2D(0.3, 1), Offset2D(0.7, 1)],
          weights: const <double>[1, 1],
          knots: const <double>[0, 0, 0, 1, 1, 1],
          degree: 3,
          relative: true,
          cpRelative: true,
        ),
      ]),
    ]) {
      built = built.addShape(shape);
    }

    doc = doc.replacePage(0, built);
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains(' C '), reason: 'cubic rows must paint');
    expect(svg, contains(' Q '), reason: 'quadratic rows must paint');
    expect(RegExp(r'\bL ').hasMatch(svg), isTrue,
        reason: 'polylines / sampled curves must paint');
    expect(RegExp(r'\bA ').hasMatch(svg) || svg.contains(' C '), isTrue);

    final saved = writer.write(originalBytes: blank, edited: doc);
    final xml = VsdxPackage.open(saved)
        .readPartXml('/visio/pages/page1.xml')!
        .toXmlString();
    for (final dropped in const <String>[
      'CubBezTo',
      'QuadBezTo',
      'RelArcTo',
      'RelPolylineTo',
      'RelInfiniteLine',
      'RelSplineStart',
      'RelSplineKnot',
      'RelNURBSTo',
    ]) {
      expect(xml, isNot(contains('T="$dropped"')),
          reason: 'libvisio drops $dropped; the writer must remap it');
    }
    for (final kept in const <String>[
      'RelCubBezTo',
      'RelQuadBezTo',
      'ArcTo',
      'PolylineTo',
      'InfiniteLine',
      'SplineStart',
      'NURBSTo',
      'Ellipse',
      'EllipticalArcTo',
      'RelEllipticalArcTo',
    ]) {
      expect(xml, contains('T="$kept"'),
          reason: '$kept is what libvisio collects');
    }

    final round = parser.parse(saved);
    final kinds = <Type>{
      for (final shape in round.pages.first.shapes)
        for (final g in shape.geometries)
          for (final c in g.commands) c.runtimeType,
    };
    expect(kinds, isNot(contains(CubBezTo)));
    expect(kinds, isNot(contains(QuadBezTo)));
    expect(kinds, isNot(contains(RelArcTo)));
    expect(kinds, containsAll(<Type>[
      RelCubBezTo,
      RelQuadBezTo,
      ArcTo,
      PolylineTo,
      InfiniteLineCmd,
      SplineStart,
      NurbsTo,
      EllipseCmd,
      EllipticalArcTo,
      RelEllipticalArcTo,
    ]));

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    final reference = oracle.svgPages(saved);
    expect(reference, isNotNull, reason: 'libvisio must open the saved package');
    final joined = reference!.join();
    expect(RegExp(r'\nC').hasMatch(joined), isTrue,
        reason: 'rewritten cubics reach libvisio');
    expect(RegExp(r'\nQ').hasMatch(joined), isTrue,
        reason: 'rewritten quads reach libvisio');
    expect(RegExp(r'\nA').hasMatch(joined) || RegExp(r'\nL').hasMatch(joined),
        isTrue);
  });

  test('Height=0 CubBezTo samples LineTo so Rel* cannot flatten the bow', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final page = doc.pages.first;
    final id = page.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      page.addShape(
        VsdxShape(
          id: id,
          name: 'Bez1D',
          pinX: 4.25,
          pinY: 5.5,
          locPinXInches: 1.5,
          locPinYInches: 0,
          width: 3,
          height: 0,
          is1D: true,
          beginX: 2.75,
          beginY: 5.5,
          endX: 5.75,
          endY: 5.5,
          objType: 2,
          fill: const VsdxFill(pattern: 0),
          line: const VsdxLine(color: VsdxColor(0xFFFF00FF), weightInches: 0.08),
          geometries: const <VsdxGeometry>[
            VsdxGeometry(
              noFill: true,
              commands: <VsdxPathCommand>[
                MoveTo(0, 0),
                CubBezTo(x: 3, y: 0, x1: 0.8, y1: 1.2, x2: 2.2, y2: 1.2),
              ],
            ),
          ],
        ),
      ),
    );
    final saved = writer.write(originalBytes: blank, edited: doc);
    final xml = VsdxPackage.open(saved)
        .readPartXml('/visio/pages/page1.xml')!
        .toXmlString();
    expect(xml, isNot(contains('T="CubBezTo"')));
    expect(xml, isNot(contains('T="RelCubBezTo"')),
        reason: 'RelCubBezTo would collapse fy*Height=0 to a chord');
    expect(xml, contains('T="LineTo"'));
    final source = parser.parse(saved).pages.first.findShapeById(id)!;
    final lines = source.geometries.single.commands.whereType<LineTo>();
    expect(lines.length, 12);
    expect(
      lines.map((c) => c.y).reduce((a, b) => a > b ? a : b),
      greaterThan(0.5),
    );
  });
}

Uint8List _read(String path) =>
    Uint8List.fromList(File(path).readAsBytesSync());
