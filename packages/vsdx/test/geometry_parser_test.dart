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
  });
}
