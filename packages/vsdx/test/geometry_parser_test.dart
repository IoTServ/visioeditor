import 'dart:io';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';
import 'package:vsdx/src/parser/geometry_parser.dart';
import 'package:xml/xml.dart';

/// Geometry row-type coverage, aligned with libvisio's `VSDXMLParserBase`.
///
/// Every `<Row>` inside a `<Section N="Geometry">` must map to exactly one
/// [VsdxPathCommand]; a row type the parser doesn't recognise is silently
/// dropped, which is exactly the class of bug these tests guard against.
void main() {
  const gp = GeometryParser();

  VsdxGeometry parseGeom(String rows) {
    final shape =
        XmlDocument.parse('<Shape><Section N="Geometry" IX="0">$rows</Section>'
                '</Shape>')
            .rootElement;
    return gp.parse(shape).single;
  }

  group('cubic Bézier rows (CubBezTo / RelCubBezTo)', () {
    test('absolute CubBezTo: A/B=ctrl1, C/D=ctrl2, X/Y=end (inches)', () {
      final g = parseGeom(
        '<Row IX="1" T="MoveTo"><Cell N="X" V="0"/><Cell N="Y" V="0"/></Row>'
        '<Row IX="2" T="CubBezTo">'
        '<Cell N="X" V="2"/><Cell N="Y" V="1"/>'
        '<Cell N="A" V="0.5"/><Cell N="B" V="0.25"/>'
        '<Cell N="C" V="1.5"/><Cell N="D" V="0.75"/></Row>',
      );
      expect(g.commands, hasLength(2));
      final c = g.commands[1] as CubBezTo;
      expect(c.x1, 0.5);
      expect(c.y1, 0.25);
      expect(c.x2, 1.5);
      expect(c.y2, 0.75);
      expect(c.x, 2);
      expect(c.y, 1);
    });

    test('RelCubBezTo keeps raw fractions of width/height', () {
      // The exact row workflow.vsdx uses on its rounded shapes.
      final g = parseGeom(
        '<Row IX="3" T="RelCubBezTo">'
        '<Cell N="X" V="1"/><Cell N="Y" V="0.5"/>'
        '<Cell N="A" V="0.901503"/><Cell N="B" V="0"/>'
        '<Cell N="C" V="1"/><Cell N="D" V="0.223858"/></Row>',
      );
      final c = g.commands.single as RelCubBezTo;
      expect(c.fx, 1);
      expect(c.fy, 0.5);
      expect(c.fx1, closeTo(0.901503, 1e-9));
      expect(c.fy1, 0);
      expect(c.fx2, 1);
      expect(c.fy2, closeTo(0.223858, 1e-9));
    });

    test('scalePathCommand scales CubBezTo but leaves RelCubBezTo (fractions) '
        'untouched', () {
      final scaled = scalePathCommand(
        const CubBezTo(x: 2, y: 1, x1: 0.5, y1: 0.25, x2: 1.5, y2: 0.75),
        2,
        3,
      ) as CubBezTo;
      expect(scaled.x, 4);
      expect(scaled.y, 3);
      expect(scaled.x1, 1.0);
      expect(scaled.y1, 0.75);
      expect(scaled.x2, 3.0);
      expect(scaled.y2, 2.25);

      const rel =
          RelCubBezTo(fx: 1, fy: 0.5, fx1: 0.9, fy1: 0, fx2: 1, fy2: 0.2);
      expect(identical(scalePathCommand(rel, 2, 3), rel), isTrue);
    });

    test('scalePathCommand updates EllipticalArcTo eccentricity under non-uniform scale',
        () {
      final scaled = scalePathCommand(
        const EllipticalArcTo(
          x: 2,
          y: 1,
          controlX: 1,
          controlY: 0.5,
          angle: 0,
          eccentricity: 1,
        ),
        2,
        1,
      ) as EllipticalArcTo;
      expect(scaled.x, 4);
      expect(scaled.y, 1);
      expect(scaled.eccentricity, closeTo(2, 1e-9));
      expect(scaled.angle, closeTo(0, 1e-9));
    });
  });

  group('quadratic Bézier rows (QuadBezTo / RelQuadBezTo)', () {
    test('absolute QuadBezTo: A/B=control, X/Y=end (inches)', () {
      final g = parseGeom(
        '<Row IX="1" T="QuadBezTo">'
        '<Cell N="X" V="2"/><Cell N="Y" V="0"/>'
        '<Cell N="A" V="1"/><Cell N="B" V="1.5"/></Row>',
      );
      final c = g.commands.single as QuadBezTo;
      expect(c.x1, 1);
      expect(c.y1, 1.5);
      expect(c.x, 2);
      expect(c.y, 0);
    });

    test('RelQuadBezTo keeps raw fractions of width/height', () {
      final g = parseGeom(
        '<Row IX="1" T="RelQuadBezTo">'
        '<Cell N="X" V="1"/><Cell N="Y" V="0.5"/>'
        '<Cell N="A" V="0.75"/><Cell N="B" V="0.25"/></Row>',
      );
      final c = g.commands.single as RelQuadBezTo;
      expect(c.fx, 1);
      expect(c.fy, 0.5);
      expect(c.fx1, 0.75);
      expect(c.fy1, 0.25);
    });
  });

  group('relative elliptical arc row (RelEllipticalArcTo)', () {
    test('X/Y/A/B are fractions, C=angle (rad), D=eccentricity absolute', () {
      final g = parseGeom(
        '<Row IX="1" T="RelEllipticalArcTo">'
        '<Cell N="X" V="1"/><Cell N="Y" V="0.5"/>'
        '<Cell N="A" V="0.5"/><Cell N="B" V="1"/>'
        '<Cell N="C" V="0"/><Cell N="D" V="1.5"/></Row>',
      );
      final c = g.commands.single as RelEllipticalArcTo;
      expect(c.fx, 1);
      expect(c.fy, 0.5);
      expect(c.fcx, 0.5);
      expect(c.fcy, 1);
      expect(c.angle, 0);
      expect(c.eccentricity, 1.5);
    });

    test('absolute EllipticalArcTo is still parsed as EllipticalArcTo', () {
      final g = parseGeom(
        '<Row IX="1" T="EllipticalArcTo">'
        '<Cell N="X" V="2" U="IN"/><Cell N="Y" V="0" U="IN"/>'
        '<Cell N="A" V="1" U="IN"/><Cell N="B" V="0.5" U="IN"/>'
        '<Cell N="C" V="0"/><Cell N="D" V="1"/></Row>',
      );
      final c = g.commands.single as EllipticalArcTo;
      expect(c.x, 2);
      expect(c.controlX, 1);
      expect(c.controlY, 0.5);
    });
  });

  group('other common geometry rows still map 1:1', () {
    test('MoveTo / LineTo / ArcTo / Ellipse / NURBSTo each yield one command',
        () {
      final g = parseGeom(
        '<Row IX="1" T="MoveTo"><Cell N="X" V="0"/><Cell N="Y" V="0"/></Row>'
        '<Row IX="2" T="LineTo"><Cell N="X" V="1"/><Cell N="Y" V="0"/></Row>'
        '<Row IX="3" T="ArcTo"><Cell N="X" V="2"/><Cell N="Y" V="0"/>'
        '<Cell N="A" V="0.2"/></Row>'
        '<Row IX="4" T="Ellipse"><Cell N="X" V="1"/><Cell N="Y" V="1"/>'
        '<Cell N="A" V="2"/><Cell N="B" V="1"/><Cell N="C" V="1"/>'
        '<Cell N="D" V="2"/></Row>'
        '<Row IX="5" T="NURBSTo"><Cell N="X" V="3"/><Cell N="Y" V="0"/>'
        '<Cell N="E" V="NURBS(1, 3, 0, 0, 1, 1, 0, 1)"/></Row>',
      );
      expect(g.commands.map((c) => c.runtimeType).toList(), <Type>[
        MoveTo,
        LineTo,
        ArcTo,
        EllipseCmd,
        NurbsTo,
      ]);
    });

    test('section-level NoFill / NoLine / NoShow flags are read', () {
      final g = parseGeom(
        '<Cell N="NoFill" V="1"/><Cell N="NoLine" V="0"/>'
        '<Cell N="NoShow" V="1"/>'
        '<Row IX="1" T="MoveTo"><Cell N="X" V="0"/><Cell N="Y" V="0"/></Row>',
      );
      expect(g.noFill, isTrue);
      expect(g.noLine, isFalse);
      expect(g.noShow, isTrue);
    });

    test('section-level NoSnap / NoQuickDrag flags are read', () {
      final g = parseGeom(
        '<Cell N="NoSnap" V="1"/><Cell N="NoQuickDrag" V="1"/>'
        '<Row IX="1" T="MoveTo"><Cell N="X" V="0"/><Cell N="Y" V="0"/></Row>',
      );
      expect(g.noSnap, isTrue);
      expect(g.noQuickDrag, isTrue);
    });

    test('RelPolylineTo / RelNURBSTo / RelInfiniteLine keep relative flag', () {
      final g = parseGeom(
        '<Row IX="1" T="RelMoveTo"><Cell N="X" V="0"/><Cell N="Y" V="0"/></Row>'
        '<Row IX="2" T="RelPolylineTo"><Cell N="X" V="1"/><Cell N="Y" V="0"/>'
        '<Cell N="A" V="POLYLINE(1, 1, 0.5, 0.5)"/></Row>'
        '<Row IX="3" T="RelNURBSTo"><Cell N="X" V="1"/><Cell N="Y" V="1"/>'
        '<Cell N="E" V="NURBS(1, 3, 0, 0, 0.5, 0.5, 0, 1)"/></Row>'
        '<Row IX="4" T="RelInfiniteLine"><Cell N="X" V="0"/><Cell N="Y" V="0.5"/>'
        '<Cell N="A" V="1"/><Cell N="B" V="0.5"/></Row>',
      );
      final poly = g.commands.whereType<PolylineTo>().single;
      expect(poly.relative, isTrue);
        expect(poly.vertices.first.x, 0.5);
      final nurbs = g.commands.whereType<NurbsTo>().single;
      expect(nurbs.relative, isTrue);
      final inf = g.commands.whereType<InfiniteLineCmd>().single;
      expect(inf.relative, isTrue);
    });
  });

  group('master geometry inheritance (libvisio per-IX merge + Del)', () {
    test('Del row records a deletion, not a spurious LineTo(0,0)', () {
      final g = parseGeom(
        '<Row IX="2" T="LineTo"><Cell N="X" V="3"/><Cell N="Y" V="1"/></Row>'
        '<Row IX="3" T="LineTo" Del="1"/>',
      );
      // Only the real row becomes a command; the Del row is a deletion marker.
      expect(g.commands, hasLength(1));
      expect(g.commands.single, isA<LineTo>());
      expect(g.deletedRowIndices, contains(3));
      expect(g.rowIndices, <int>[2]);
    });

    test('instance overrides master row by IX and Del removes inherited row',
        () {
      final master = <VsdxGeometry>[
        gp
            .parse(XmlDocument.parse(
                    '<Shape><Section N="Geometry" IX="0">'
                    '<Cell N="NoFill" V="1"/>'
                    '<Row IX="1" T="MoveTo"><Cell N="X" V="0"/><Cell N="Y" V="0"/></Row>'
                    '<Row IX="2" T="LineTo"><Cell N="X" V="0"/><Cell N="Y" V="9"/></Row>'
                    '<Row IX="3" T="LineTo"><Cell N="X" V="9"/><Cell N="Y" V="9"/></Row>'
                    '</Section></Shape>')
                .rootElement)
            .single,
      ];
      final instance = <VsdxGeometry>[
        gp
            .parse(XmlDocument.parse(
                    '<Shape><Section N="Geometry" IX="0">'
                    '<Row IX="2" T="LineTo"><Cell N="X" V="3"/><Cell N="Y" V="1"/></Row>'
                    '<Row IX="3" T="LineTo" Del="1"/>'
                    '</Section></Shape>')
                .rootElement)
            .single,
      ];
      final merged = GeometryParser.mergeInherited(master, instance).single;
      // IX=1 inherited MoveTo(0,0), IX=2 overridden LineTo(3,1), IX=3 deleted.
      expect(merged.commands, hasLength(2));
      expect(merged.commands[0], isA<MoveTo>());
      final lt = merged.commands[1] as LineTo;
      expect(lt.x, closeTo(3, 1e-9));
      expect(lt.y, closeTo(1, 1e-9));
      // Section flag inherited from master (instance didn't declare it).
      expect(merged.noFill, isTrue);
    });

    test('test9 line shape merges master geometry (real fixture)', () {
      const parser = DocumentParser();
      final doc = parser.parse(
          File('test/fixtures/test9_rect_and_line.vsdx').readAsBytesSync());
      final shape = doc.pages.first.findShapeById(3)!;
      final geom = shape.geometries.single;
      // MoveTo(0,0) inherited from master + overridden LineTo(3.543, 0.787);
      // the Del'd IX=3 must NOT appear (no spurious LineTo(0,0)).
      expect(geom.commands, hasLength(2));
      expect(geom.commands[0], isA<MoveTo>());
      final lt = geom.commands[1] as LineTo;
      expect(lt.x, closeTo(3.543307, 1e-4));
      expect(lt.y, closeTo(0.787401, 1e-4));
    });
  });
}
