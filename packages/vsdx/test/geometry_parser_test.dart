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

    test('scalePathCommand updates RelEllipticalArcTo angle/ecc only', () {
      final scaled = scalePathCommand(
        const RelEllipticalArcTo(
          fx: 1,
          fy: 0.5,
          fcx: 0.5,
          fcy: 1,
          angle: 0,
          eccentricity: 1,
        ),
        2,
        1,
      ) as RelEllipticalArcTo;
      expect(scaled.fx, 1);
      expect(scaled.fy, 0.5);
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

    test('NURBSTo preserves authored degree above renderer cap', () {
      final g = parseGeom(
        '<Row IX="1" T="NURBSTo"><Cell N="X" V="9"/>'
        '<Cell N="Y" V="0"/>'
        '<Cell N="E" V="NURBS(1, 9, 1, 1, 1, 1, 0, 1)"/></Row>',
      );

      expect(g.commands.whereType<NurbsTo>().single.degree, 9);
    });

    test('POLYLINE and NURBS prefer libvisio evaluated V caches over F', () {
      final g = parseGeom(
        '<Row IX="1" T="PolylineTo"><Cell N="X" V="4"/>'
        '<Cell N="Y" V="0"/><Cell N="A" '
        'V="POLYLINE(1,1,1,1,3,1)" '
        'F="GUARD(POLYLINE(0,0,9,9))"/></Row>'
        '<Row IX="2" T="NURBSTo"><Cell N="X" V="4"/>'
        '<Cell N="Y" V="0"/><Cell N="E" '
        'V="NURBS(1,2,1,1,1,1,0,1,3,1,1,1)" '
        'F="GUARD(NURBS(9,8,0,0,9,9,9,9))"/></Row>',
      );

      final polyline = g.commands.whereType<PolylineTo>().single;
      expect(
        polyline.vertices,
        const <Offset2D>[Offset2D(1, 1), Offset2D(3, 1)],
      );
      expect(polyline.vertsRelative, isFalse);
      expect(polyline.vertsYRelative, isFalse);

      final nurbs = g.commands.whereType<NurbsTo>().single;
      expect(nurbs.degree, 2);
      expect(
        nurbs.controlPoints,
        const <Offset2D>[Offset2D(1, 1), Offset2D(3, 1)],
      );
      expect(nurbs.cpRelative, isFalse);
      expect(nurbs.cpYRelative, isFalse);
    });

    test('formula payload remains a fallback for empty V caches', () {
      final g = parseGeom(
        '<Row IX="1" T="PolylineTo"><Cell N="X" V="2"/>'
        '<Cell N="Y" V="0"/><Cell N="A" V="" '
        'F="POLYLINE(1,1,1,1)"/></Row>',
      );

      expect(
        g.commands.whereType<PolylineTo>().single.vertices,
        const <Offset2D>[Offset2D(1, 1)],
      );
    });

    test('NoFill F=Inh ignores stale V= (default false without master)', () {
      final g = parseGeom(
        '<Cell N="NoFill" V="1" F="Inh"/>'
        '<Cell N="NoLine" V="1" F="Inh"/>'
        '<Cell N="NoShow" V="1" F="Inh"/>'
        '<Row IX="1" T="MoveTo"><Cell N="X" V="0"/><Cell N="Y" V="0"/></Row>',
      );
      expect(g.noFill, isFalse);
      expect(g.noLine, isFalse);
      expect(g.noShow, isFalse);
      expect(g.definedFlagCells.contains('NoFill'), isFalse);
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
      // POLYLINE(1,1,…) → local-inch verts even on a Rel* row.
      expect(poly.vertsRelative, isFalse);
      expect(poly.vertsYRelative, isFalse);
      expect(poly.vertices.first.x, 0.5);
      final nurbs = g.commands.whereType<NurbsTo>().single;
      expect(nurbs.relative, isTrue);
      expect(nurbs.cpRelative, isTrue); // NURBS(…,0,0,…)
      expect(nurbs.cpYRelative, isTrue);
      final inf = g.commands.whereType<InfiniteLineCmd>().single;
      expect(inf.relative, isTrue);
    });

    test('RelPolylineTo honors POLYLINE(0,0,…) percent verts', () {
      final g = parseGeom(
        '<Row IX="1" T="RelMoveTo"><Cell N="X" V="0"/><Cell N="Y" V="0"/></Row>'
        '<Row IX="2" T="RelPolylineTo"><Cell N="X" V="1"/><Cell N="Y" V="0"/>'
        '<Cell N="A" V="POLYLINE(0, 0, 0.5, 0.5)"/></Row>',
      );
      final poly = g.commands.whereType<PolylineTo>().single;
      expect(poly.relative, isTrue);
      expect(poly.vertsRelative, isTrue);
      expect(poly.vertsYRelative, isTrue);
      final verts = g.polylineVertices(widthInches: 4, heightInches: 2)!;
      expect(verts[1].x, closeTo(2.0, 1e-9));
      expect(verts[1].y, closeTo(1.0, 1e-9));
    });

    test('RelPolylineTo with POLYLINE(1,1,…) keeps local-inch verts', () {
      final g = parseGeom(
        '<Row IX="1" T="RelMoveTo"><Cell N="X" V="0"/><Cell N="Y" V="0"/></Row>'
        '<Row IX="2" T="RelPolylineTo"><Cell N="X" V="1"/><Cell N="Y" V="0"/>'
        '<Cell N="A" V="POLYLINE(1, 1, 0.5, 0.5)"/></Row>',
      );
      final poly = g.commands.whereType<PolylineTo>().single;
      expect(poly.vertsRelative, isFalse);
      final verts = g.polylineVertices(widthInches: 4, heightInches: 2)!;
      // Must NOT scale 0.5 by Width (that would be 2.0).
      expect(verts[1].x, closeTo(0.5, 1e-9));
      expect(verts[1].y, closeTo(0.5, 1e-9));
      // Rel* endpoint still scales.
      expect(verts.last.x, closeTo(4.0, 1e-9));
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

    test('NoShow F=Inh does not override master NoShow=1', () {
      final master = <VsdxGeometry>[
        gp
            .parse(XmlDocument.parse(
                    '<Shape><Section N="Geometry" IX="0">'
                    '<Cell N="NoShow" V="1"/>'
                    '<Row IX="1" T="MoveTo"><Cell N="X" V="0"/><Cell N="Y" V="0"/></Row>'
                    '<Row IX="2" T="LineTo"><Cell N="X" V="1"/><Cell N="Y" V="0"/></Row>'
                    '</Section></Shape>')
                .rootElement)
            .single,
      ];
      final instance = <VsdxGeometry>[
        gp
            .parse(XmlDocument.parse(
                    '<Shape><Section N="Geometry" IX="0">'
                    '<Cell N="NoShow" V="0" F="Inh"/>'
                    '<Row IX="1" T="MoveTo"><Cell N="X" V="0"/><Cell N="Y" V="0"/></Row>'
                    '<Row IX="2" T="LineTo"><Cell N="X" V="2"/><Cell N="Y" V="0"/></Row>'
                    '</Section></Shape>')
                .rootElement)
            .single,
      ];
      final merged = GeometryParser.mergeInherited(master, instance).single;
      expect(merged.noShow, isTrue);
    });

    test('LineTo Y F=Inh keeps master Y while local X overrides', () {
      final master = <VsdxGeometry>[
        gp
            .parse(XmlDocument.parse(
                    '<Shape><Section N="Geometry" IX="0">'
                    '<Row IX="1" T="MoveTo"><Cell N="X" V="0"/><Cell N="Y" V="0"/></Row>'
                    '<Row IX="2" T="LineTo"><Cell N="X" V="1"/><Cell N="Y" V="0.5"/></Row>'
                    '</Section></Shape>')
                .rootElement)
            .single,
      ];
      final instance = <VsdxGeometry>[
        gp
            .parse(XmlDocument.parse(
                    '<Shape><Section N="Geometry" IX="0">'
                    '<Row IX="1" T="MoveTo"><Cell N="X" V="0"/><Cell N="Y" V="0"/></Row>'
                    '<Row IX="2" T="LineTo">'
                    '<Cell N="X" V="3"/>'
                    '<Cell N="Y" V="0" F="Inh"/>'
                    '</Row>'
                    '</Section></Shape>')
                .rootElement)
            .single,
      ];
      final merged = GeometryParser.mergeInherited(master, instance).single;
      final lt = merged.commands[1] as LineTo;
      expect(lt.x, closeTo(3, 1e-9));
      expect(lt.y, closeTo(0.5, 1e-9));
    });

    test('RelCubBezTo F=Inh cells keep master control points', () {
      final master = <VsdxGeometry>[
        gp
            .parse(XmlDocument.parse(
                    '<Shape><Section N="Geometry" IX="0">'
                    '<Row IX="1" T="RelMoveTo"><Cell N="X" V="0"/><Cell N="Y" V="0"/></Row>'
                    '<Row IX="2" T="RelCubBezTo">'
                    '<Cell N="X" V="1"/><Cell N="Y" V="1"/>'
                    '<Cell N="A" V="0.2"/><Cell N="B" V="0.3"/>'
                    '<Cell N="C" V="0.4"/><Cell N="D" V="0.5"/>'
                    '</Row>'
                    '</Section></Shape>')
                .rootElement)
            .single,
      ];
      final instance = <VsdxGeometry>[
        gp
            .parse(XmlDocument.parse(
                    '<Shape><Section N="Geometry" IX="0">'
                    '<Row IX="1" T="RelMoveTo"><Cell N="X" V="0"/><Cell N="Y" V="0"/></Row>'
                    '<Row IX="2" T="RelCubBezTo">'
                    '<Cell N="X" V="0.9"/>'
                    '<Cell N="Y" V="0" F="Inh"/>'
                    '<Cell N="A" V="0" F="Inh"/><Cell N="B" V="0" F="Inh"/>'
                    '<Cell N="C" V="0" F="Inh"/><Cell N="D" V="0" F="Inh"/>'
                    '</Row>'
                    '</Section></Shape>')
                .rootElement)
            .single,
      ];
      final merged = GeometryParser.mergeInherited(master, instance).single;
      final cub = merged.commands[1] as RelCubBezTo;
      expect(cub.fx, closeTo(0.9, 1e-9));
      expect(cub.fy, closeTo(1, 1e-9));
      expect(cub.fx1, closeTo(0.2, 1e-9));
      expect(cub.fy1, closeTo(0.3, 1e-9));
      expect(cub.fx2, closeTo(0.4, 1e-9));
      expect(cub.fy2, closeTo(0.5, 1e-9));
    });

    test('EllipseCmd F=Inh cells keep master axes', () {
      final master = <VsdxGeometry>[
        gp
            .parse(XmlDocument.parse(
                    '<Shape><Section N="Geometry" IX="0">'
                    '<Row IX="1" T="Ellipse">'
                    '<Cell N="X" V="1"/><Cell N="Y" V="2"/>'
                    '<Cell N="A" V="3"/><Cell N="B" V="2"/>'
                    '<Cell N="C" V="1"/><Cell N="D" V="4"/>'
                    '</Row>'
                    '</Section></Shape>')
                .rootElement)
            .single,
      ];
      final instance = <VsdxGeometry>[
        gp
            .parse(XmlDocument.parse(
                    '<Shape><Section N="Geometry" IX="0">'
                    '<Row IX="1" T="Ellipse">'
                    '<Cell N="X" V="1.5"/>'
                    '<Cell N="Y" V="0" F="Inh"/>'
                    '<Cell N="A" V="0" F="Inh"/><Cell N="B" V="0" F="Inh"/>'
                    '<Cell N="C" V="0" F="Inh"/><Cell N="D" V="0" F="Inh"/>'
                    '</Row>'
                    '</Section></Shape>')
                .rootElement)
            .single,
      ];
      final merged = GeometryParser.mergeInherited(master, instance).single;
      final el = merged.commands.single as EllipseCmd;
      expect(el.cx, closeTo(1.5, 1e-9));
      expect(el.cy, closeTo(2, 1e-9));
      expect(el.aX, closeTo(3, 1e-9));
      expect(el.aY, closeTo(2, 1e-9));
      expect(el.bX, closeTo(1, 1e-9));
      expect(el.bY, closeTo(4, 1e-9));
    });

    test('InfiniteLineCmd F=Inh cells keep master direction', () {
      final master = <VsdxGeometry>[
        gp
            .parse(XmlDocument.parse(
                    '<Shape><Section N="Geometry" IX="0">'
                    '<Row IX="1" T="InfiniteLine">'
                    '<Cell N="X" V="0"/><Cell N="Y" V="1"/>'
                    '<Cell N="A" V="2"/><Cell N="B" V="3"/>'
                    '</Row>'
                    '</Section></Shape>')
                .rootElement)
            .single,
      ];
      final instance = <VsdxGeometry>[
        gp
            .parse(XmlDocument.parse(
                    '<Shape><Section N="Geometry" IX="0">'
                    '<Row IX="1" T="InfiniteLine">'
                    '<Cell N="X" V="0.25"/>'
                    '<Cell N="Y" V="0" F="Inh"/>'
                    '<Cell N="A" V="0" F="Inh"/><Cell N="B" V="0" F="Inh"/>'
                    '</Row>'
                    '</Section></Shape>')
                .rootElement)
            .single,
      ];
      final merged = GeometryParser.mergeInherited(master, instance).single;
      final line = merged.commands.single as InfiniteLineCmd;
      expect(line.x, closeTo(0.25, 1e-9));
      expect(line.y, closeTo(1, 1e-9));
      expect(line.a, closeTo(2, 1e-9));
      expect(line.b, closeTo(3, 1e-9));
      expect(line.relative, isFalse);
    });

    test('PolylineTo A F=Inh keeps master vertices', () {
      final master = <VsdxGeometry>[
        gp
            .parse(XmlDocument.parse(
                    '<Shape><Section N="Geometry" IX="0">'
                    '<Row IX="1" T="MoveTo"><Cell N="X" V="0"/><Cell N="Y" V="0"/></Row>'
                    '<Row IX="2" T="PolylineTo">'
                    '<Cell N="X" V="2"/><Cell N="Y" V="0"/>'
                    '<Cell N="A" V="" F="POLYLINE(1,1,0.5,0.5,1.5,0.5)"/>'
                    '</Row>'
                    '</Section></Shape>')
                .rootElement)
            .single,
      ];
      final instance = <VsdxGeometry>[
        gp
            .parse(XmlDocument.parse(
                    '<Shape><Section N="Geometry" IX="0">'
                    '<Row IX="1" T="MoveTo"><Cell N="X" V="0"/><Cell N="Y" V="0"/></Row>'
                    '<Row IX="2" T="PolylineTo">'
                    '<Cell N="X" V="3"/>'
                    '<Cell N="Y" V="0" F="Inh"/>'
                    '<Cell N="A" V="" F="Inh"/>'
                    '</Row>'
                    '</Section></Shape>')
                .rootElement)
            .single,
      ];
      final merged = GeometryParser.mergeInherited(master, instance).single;
      final poly = merged.commands[1] as PolylineTo;
      expect(poly.x, closeTo(3, 1e-9));
      expect(poly.y, closeTo(0, 1e-9));
      expect(poly.vertices, hasLength(2));
      expect(poly.vertices[0].x, closeTo(0.5, 1e-9));
      expect(poly.vertices[1].x, closeTo(1.5, 1e-9));
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

    test('root master instance keeps resized F=Inh geometry cache', () {
      final fixture = File(
        '../../third_party/libvisio/src/test/data/testfile3.vsdx',
      );
      expect(fixture.existsSync(), isTrue);
      final doc = const DocumentParser().parse(fixture.readAsBytesSync());
      final shape = doc.pages.first.findShapeById(1)!;
      final commands = shape.geometries.single.commands;

      expect(commands, hasLength(5));
      final move = commands[0] as MoveTo;
      final line = commands[1] as LineTo;
      final rightArc = commands[2] as EllipticalArcTo;
      final leftArc = commands[4] as EllipticalArcTo;
      expect(move.x, closeTo(0.5905511811, 1e-9));
      expect(line.x, closeTo(2.3622047244, 1e-9));
      expect(rightArc.x, closeTo(2.3622047244, 1e-9));
      expect(rightArc.y, closeTo(1.1811023622, 1e-9));
      expect(rightArc.controlX, closeTo(shape.width, 1e-9));
      expect(rightArc.controlY, closeTo(shape.height / 2, 1e-9));
      expect(leftArc.controlX, closeTo(0, 1e-9));
      expect(leftArc.controlY, closeTo(shape.height / 2, 1e-9));
    });
  });

  group('syncGeometryNoLine hit-box restore', () {
    test('annotation keeps hit-box NoLine after hollow toggle', () {
      final shape = VsdxShapeFactory.annotation(
        id: 1,
        pinX: 1,
        pinY: 1,
        width: 1,
        height: 2,
      );
      expect(shape.geometries[0].hitBox, isTrue);
      expect(shape.geometries[0].noLine, isTrue);
      expect(shape.geometries[1].noLine, isFalse);

      final hollowed =
          syncGeometryNoLine(shape.geometries, hollow: true);
      expect(hollowed.every((g) => g.noLine), isTrue);
      expect(hollowed[0].hitBox, isTrue);

      final restored = syncGeometryNoLine(hollowed, hollow: false);
      expect(restored[0].noLine, isTrue);
      expect(restored[1].noLine, isFalse);
    });

    test('doubleRectangle restores stroke on both geoms', () {
      final shape = VsdxShapeFactory.doubleRectangle(
        id: 1,
        pinX: 1,
        pinY: 1,
        width: 2,
        height: 1.5,
      );
      final hollowed =
          syncGeometryNoLine(shape.geometries, hollow: true);
      final restored = syncGeometryNoLine(hollowed, hollow: false);
      expect(restored.every((g) => !g.noLine), isTrue);
    });
  });

  group('syncGeometryNoFill hit-box restore', () {
    test('annotation keeps all NoFill after fill restore', () {
      final shape = VsdxShapeFactory.annotation(
        id: 1,
        pinX: 1,
        pinY: 1,
        width: 1,
        height: 2,
      );
      expect(shape.geometries.every((g) => g.noFill), isTrue);
      final hollowed =
          syncGeometryNoFill(shape.geometries, hollow: true);
      final restored = syncGeometryNoFill(hollowed, hollow: false);
      expect(restored.every((g) => g.noFill), isTrue);
      expect(restored[0].hitBox, isTrue);
    });

    test('picture frame can restore fill on the silhouette geom', () {
      final shape = VsdxShapeFactory.picture(
        id: 1,
        pinX: 1,
        pinY: 1,
        width: 1,
        height: 1,
        imagePartName: '/visio/media/x.png',
      );
      expect(shape.geometries.single.hitBox, isFalse);
      final hollowed =
          syncGeometryNoFill(shape.geometries, hollow: true);
      final restored = syncGeometryNoFill(hollowed, hollow: false);
      // Single non-hit-box frame: restore allows a backing fill (border box).
      expect(restored.single.noFill, isFalse);
    });

    test('doubleRectangle restores outer fill only', () {
      final shape = VsdxShapeFactory.doubleRectangle(
        id: 1,
        pinX: 1,
        pinY: 1,
        width: 2,
        height: 1.5,
      );
      final hollowed =
          syncGeometryNoFill(shape.geometries, hollow: true);
      final restored = syncGeometryNoFill(hollowed, hollow: false);
      expect(restored[0].noFill, isFalse);
      expect(restored[1].noFill, isTrue);
    });
  });

  group('forLibvisioWrite', () {
    test('CubBezTo / QuadBezTo become Rel* fractions', () {
      final cubic = forLibvisioWrite(
        const CubBezTo(x: 2, y: 1, x1: 0.5, y1: 0.25, x2: 1.5, y2: 0.75),
        width: 2,
        height: 1,
      ) as RelCubBezTo;
      expect(cubic.fx, closeTo(1, 1e-9));
      expect(cubic.fy, closeTo(1, 1e-9));
      expect(cubic.fx1, closeTo(0.25, 1e-9));
      expect(cubic.fy1, closeTo(0.25, 1e-9));
      final quad = forLibvisioWrite(
        const QuadBezTo(x: 2, y: 1, x1: 1, y1: 0),
        width: 2,
        height: 1,
      ) as RelQuadBezTo;
      expect(quad.fx, closeTo(1, 1e-9));
      expect(quad.fy1, closeTo(0, 1e-9));
    });

    test('Height=0 CubBezTo / QuadBezTo become LineTo samples', () {
      expect(
        cubBezNeedsLibvisioPolylineBake(width: 3, height: 0),
        isTrue,
      );
      final cubic = commandsForLibvisioWrite(
        const <VsdxPathCommand>[
          MoveTo(0, 0),
          CubBezTo(x: 3, y: 0, x1: 0.8, y1: 1.2, x2: 2.2, y2: 1.2),
        ],
        width: 3,
        height: 0,
      );
      expect(cubic.first, isA<MoveTo>());
      expect(cubic.whereType<LineTo>().length, 12);
      expect(
        cubic.whereType<LineTo>().map((c) => c.y).reduce((a, b) => a > b ? a : b),
        greaterThan(0.5),
        reason: 'RelCubBezTo would have collapsed fy to 0',
      );
      final quad = commandsForLibvisioWrite(
        const <VsdxPathCommand>[
          MoveTo(0, 0),
          QuadBezTo(x: 3, y: 0, x1: 1.5, y1: 1.4),
        ],
        width: 3,
        height: 0,
      );
      expect(quad.whereType<LineTo>().length, 12);
      expect(
        quad.whereType<LineTo>().map((c) => c.y).reduce((a, b) => a > b ? a : b),
        greaterThan(0.5),
      );
    });

    test('Width=0 CubBezTo keeps local-inch X in LineTo', () {
      final cmds = commandsForLibvisioWrite(
        const <VsdxPathCommand>[
          MoveTo(0, 0),
          CubBezTo(x: 0, y: 2, x1: 1.2, y1: 0.4, x2: 1.2, y2: 1.6),
        ],
        width: 0,
        height: 2,
      );
      expect(cmds.whereType<LineTo>().length, 12);
      expect(
        cmds.whereType<LineTo>().map((c) => c.x).reduce((a, b) => a > b ? a : b),
        greaterThan(0.5),
      );
    });

    test('RelArcTo / RelPolylineTo / RelNURBSTo bake to absolute rows', () {
      final arc = forLibvisioWrite(
        const RelArcTo(fx: 1, fy: 0, fbow: 0.1),
        width: 3,
        height: 1,
      ) as ArcTo;
      expect(arc.x, closeTo(3, 1e-9));
      expect(arc.bow, closeTo(0.1 * (3 + 1) / 2, 1e-9));
      final poly = forLibvisioWrite(
        const PolylineTo(
          x: 1,
          y: 0,
          vertices: <Offset2D>[Offset2D(0.5, 0.5)],
          relative: true,
        ),
        width: 2,
        height: 2,
      ) as PolylineTo;
      expect(poly.relative, isFalse);
      expect(poly.x, closeTo(2, 1e-9));
      expect(commandNeedsLibvisioRewrite(const RelArcTo(fx: 1, fy: 0, fbow: 0.1)),
          isTrue);
      expect(commandNeedsLibvisioRewrite(const MoveTo(0, 0)), isFalse);
    });
  });
}
