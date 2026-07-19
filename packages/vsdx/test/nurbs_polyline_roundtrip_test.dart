import 'dart:math' as math;
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/src/parser/geometry_parser.dart';
import 'package:vsdx/vsdx.dart';
import 'package:xml/xml.dart';

void main() {
  const parser = DocumentParser();
  const writer = VsdxWriter();
  const gp = GeometryParser();

  Uint8List blankBytes() => writer.emptyDocument();

  VsdxGeometry parseGeom(String rows) {
    final shape = XmlDocument.parse(
      '<Shape><Section N="Geometry" IX="0">$rows</Section></Shape>',
    ).rootElement;
    return gp.parse(shape).single;
  }

  group('POLYLINE / NURBS writer flags', () {
    test('absolute PolylineTo writes POLYLINE(1,1,…)', () {
      final blank = blankBytes();
      final doc = parser.parse(blank);
      final id = doc.pages.first.nextFreeShapeId();
      final shape = VsdxShape(
        id: id,
        name: 'P',
        pinX: 2,
        pinY: 2,
        width: 2,
        height: 2,
        geometries: const <VsdxGeometry>[
          VsdxGeometry(
            commands: <VsdxPathCommand>[
              MoveTo(0, 0),
              PolylineTo(
                x: 2,
                y: 0,
                vertices: <Offset2D>[Offset2D(1, 1)],
              ),
            ],
          ),
        ],
      );
      final edited = doc.replacePage(0, doc.pages.first.addShape(shape));
      final out = writer.write(originalBytes: blank, edited: edited);
      final pageXml = VsdxPackage.open(out)
          .readPartXml('/visio/pages/page1.xml')!
          .toXmlString();
      expect(pageXml, contains('POLYLINE(1,1'));
      expect(pageXml, isNot(contains('POLYLINE(0,0,')));
    });

    test('relative PolylineTo writes POLYLINE(0,0,…)', () {
      final blank = blankBytes();
      final doc = parser.parse(blank);
      final id = doc.pages.first.nextFreeShapeId();
      final shape = VsdxShape(
        id: id,
        name: 'P',
        pinX: 2,
        pinY: 2,
        width: 2,
        height: 2,
        geometries: const <VsdxGeometry>[
          VsdxGeometry(
            commands: <VsdxPathCommand>[
              RelMoveTo(0, 0),
              PolylineTo(
                x: 1,
                y: 0,
                vertices: <Offset2D>[Offset2D(0.5, 0.5)],
                relative: true,
              ),
            ],
          ),
        ],
      );
      final edited = doc.replacePage(0, doc.pages.first.addShape(shape));
      final out = writer.write(originalBytes: blank, edited: edited);
      final pageXml = VsdxPackage.open(out)
          .readPartXml('/visio/pages/page1.xml')!
          .toXmlString();
      expect(pageXml, contains('POLYLINE(0,0'));
    });

    test('NURBSTo with formula xType=0 sets cpRelative', () {
      final g = parseGeom(
        '<Row IX="1" T="MoveTo"><Cell N="X" V="0"/><Cell N="Y" V="0"/></Row>'
        '<Row IX="2" T="NURBSTo">'
        '<Cell N="X" V="3"/><Cell N="Y" V="0"/>'
        '<Cell N="A" V="0"/><Cell N="B" V="1"/>'
        '<Cell N="C" V="0"/><Cell N="D" V="1"/>'
        '<Cell N="E" V="NURBS(1, 3, 0, 0, 0.5, 0.5, 0, 1)"/>'
        '</Row>',
      );
      final nurbs = g.commands.whereType<NurbsTo>().single;
      expect(nurbs.relative, isFalse);
      expect(nurbs.cpRelative, isTrue);
      expect(nurbs.x, closeTo(3, 1e-9));
      expect(nurbs.controlPoints.first.x, closeTo(0.5, 1e-9));
      // A/B/C/D assembled onto knot/weight vectors.
      expect(nurbs.weights.first, closeTo(1, 1e-9));
      expect(nurbs.weights.last, closeTo(1, 1e-9));
      expect(nurbs.knots.first, closeTo(0, 1e-9));
      expect(nurbs.knots.last, closeTo(1, 1e-9));
    });

    test('PolylineTo with POLYLINE(0,0,…) sets vertsRelative', () {
      final g = parseGeom(
        '<Row IX="1" T="MoveTo"><Cell N="X" V="0"/><Cell N="Y" V="0"/></Row>'
        '<Row IX="2" T="PolylineTo"><Cell N="X" V="2"/><Cell N="Y" V="0"/>'
        '<Cell N="A" V="POLYLINE(0, 0, 0.5, 0.5)"/></Row>',
      );
      final poly = g.commands.whereType<PolylineTo>().single;
      expect(poly.relative, isFalse);
      expect(poly.vertsRelative, isTrue);
      expect(poly.x, closeTo(2, 1e-9));
      expect(poly.vertices.first.x, closeTo(0.5, 1e-9));
    });

    test('NURBSTo writes xType/yType flags, not endpoint as flags', () {
      final blank = blankBytes();
      final doc = parser.parse(blank);
      final id = doc.pages.first.nextFreeShapeId();
      final shape = VsdxShape(
        id: id,
        name: 'N',
        pinX: 3,
        pinY: 3,
        width: 3,
        height: 2,
        geometries: <VsdxGeometry>[
          VsdxGeometry(
            commands: <VsdxPathCommand>[
              const MoveTo(0, 0),
              NurbsTo(
                x: 3,
                y: 0,
                controlPoints: const <Offset2D>[
                  Offset2D(1, 1),
                  Offset2D(2, 1),
                ],
                weights: const <double>[1, 1],
                knots: const <double>[0, 0, 0, 1, 1, 1],
                degree: 3,
              ),
            ],
          ),
        ],
      );
      final edited = doc.replacePage(0, doc.pages.first.addShape(shape));
      final out = writer.write(originalBytes: blank, edited: edited);
      final pageXml = VsdxPackage.open(out)
          .readPartXml('/visio/pages/page1.xml')!
          .toXmlString();
      // NURBS(knotLast, degree, xType, yType, …) — local inches → (1,1).
      expect(pageXml, contains('NURBS('));
      expect(pageXml, contains(',3,1,1,'));
      expect(pageXml, isNot(contains('NURBS(1,3,3,0,')));

      final round = parser.parse(out);
      final nurbs = round.pages.first.shapes.first.geometries.first.commands
          .whereType<NurbsTo>()
          .single;
      expect(nurbs.relative, isFalse);
      expect(nurbs.degree, 3);
      expect(nurbs.controlPoints, hasLength(2));
      expect(nurbs.controlPoints.first.x, closeTo(1, 1e-6));
    });
  });

  group('rotated EllipseCmd perimeter', () {
    test('conjugate-diameter sampling hits axis end-points', () {
      const cx = 1.0, cy = 1.0;
      final aX = cx + math.sqrt2 / 2;
      final aY = cy + math.sqrt2 / 2;
      final bX = cx - 0.3 * math.sqrt2 / 2;
      final bY = cy + 0.3 * math.sqrt2 / 2;
      final oval = VsdxShape(
        id: 1,
        name: 'E',
        pinX: 4,
        pinY: 4,
        width: 2,
        height: 2,
        geometries: <VsdxGeometry>[
          VsdxGeometry(
            commands: <VsdxPathCommand>[
              EllipseCmd(cx: cx, cy: cy, aX: aX, aY: aY, bX: bX, bY: bY),
            ],
          ),
        ],
      );
      final segs = ShapePerimeter.outlineSegments(oval);
      expect(segs, isNotEmpty);
      final tip = Offset2D(aX, aY);
      var minD = double.infinity;
      for (final (a, b) in segs) {
        for (final p in <Offset2D>[a, b]) {
          final d =
              (p.x - tip.x) * (p.x - tip.x) + (p.y - tip.y) * (p.y - tip.y);
          if (d < minD) minD = d;
        }
      }
      expect(minD, lessThan(1e-4));
    });

    test('rayIntersectLocal works for axis-aligned conjugate diameters', () {
      const cx = 1.0, cy = 1.0;
      final oval = VsdxShape(
        id: 1,
        name: 'E',
        pinX: 5,
        pinY: 5,
        width: 2,
        height: 2,
        locPinXInches: 1,
        locPinYInches: 1,
        geometries: const <VsdxGeometry>[
          VsdxGeometry(
            commands: <VsdxPathCommand>[
              EllipseCmd(
                cx: cx,
                cy: cy,
                aX: cx + 1,
                aY: cy,
                bX: cx,
                bY: cy + 0.5,
              ),
            ],
          ),
        ],
      );
      final page = VsdxPage(
        id: 0,
        name: 'P',
        widthInches: 10,
        heightInches: 10,
        shapes: <VsdxShape>[oval],
      );
      final hit = page.perimeterAttach(1, 10, 5);
      expect(hit.x, closeTo(6.0, 1e-5));
      expect(hit.y, closeTo(5.0, 1e-5));
    });
  });
}
