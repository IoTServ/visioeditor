import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  const codec = DrawioCodec();

  test('imports uncompressed draw.io vertices, styles, and glued edge', () {
    final bytes = Uint8List.fromList(utf8.encode('''
<mxfile compressed="false">
  <diagram id="p1" name="Flow">
    <mxGraphModel pageWidth="960" pageHeight="720">
      <root>
        <mxCell id="0"/><mxCell id="1" parent="0"/>
        <mxCell id="a" value="Start" style="ellipse;fillColor=#dae8fc;strokeColor=#6c8ebf;" vertex="1" parent="1">
          <mxGeometry x="96" y="96" width="192" height="96" as="geometry"/>
        </mxCell>
        <mxCell id="b" value="Finish" style="rounded=1;fillColor=#d5e8d4;strokeColor=#82b366;" vertex="1" parent="1">
          <mxGeometry x="576" y="384" width="192" height="96" as="geometry"/>
        </mxCell>
        <mxCell id="edge" value="Next" style="edgeStyle=orthogonalEdgeStyle;rounded=1;endArrow=classic;" edge="1" parent="1" source="a" target="b">
          <mxGeometry relative="1" as="geometry"><Array as="points"><mxPoint x="384" y="144"/></Array></mxGeometry>
        </mxCell>
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
'''));

    final document = codec.decode(bytes);
    final page = document.pages.single;
    expect(page.name, 'Flow');
    expect(page.widthInches, 10);
    expect(page.heightInches, 7.5);
    expect(page.shapes, hasLength(3));
    expect(page.shapes.first.text, 'Start');
    expect(page.shapes.first.pinX, 2);
    expect(page.shapes.first.pinY, 6);
    expect(page.shapes.first.fill.foreground, const VsdxColor(0xffdae8fc));

    final edge = page.shapes.singleWhere((shape) => shape.is1D);
    expect(edge.text, 'Next');
    expect(edge.rounded, isTrue);
    expect(edge.waypoints, hasLength(1));
    expect(edge.line.endArrow, isNot(0));
    expect(page.connects, hasLength(2));
  });

  test('imports the compressed draw.io page representation', () {
    const model =
        '''<mxGraphModel pageWidth="480" pageHeight="480"><root><mxCell id="0"/><mxCell id="1" parent="0"/><mxCell id="box" value="Compressed" vertex="1" parent="1"><mxGeometry x="96" y="96" width="96" height="48" as="geometry"/></mxCell></root></mxGraphModel>''';
    final compressed =
        Deflate(utf8.encode(Uri.encodeComponent(model))).getBytes();
    final source =
        '<mxfile><diagram name="Packed">${base64.encode(compressed)}</diagram></mxfile>';

    final document = codec.decode(Uint8List.fromList(utf8.encode(source)));
    expect(document.pages.single.name, 'Packed');
    expect(document.pages.single.shapes.single.text, 'Compressed');
  });

  test('exports editable uncompressed XML and round-trips model geometry', () {
    final page = VsdxPage(
      id: 7,
      name: 'Main',
      widthInches: 8,
      heightInches: 6,
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 11,
          pinX: 2,
          pinY: 3,
          width: 2,
          height: 1,
          fill: const VsdxFill(foreground: VsdxColor(0xffffcc00)),
        ).copyWith(text: 'Editable'),
        VsdxShapeFactory.line(
          id: 12,
          ax: 3,
          ay: 3,
          bx: 6,
          by: 3,
          line: const VsdxLine(endArrow: 4),
        ).copyWith(straightRoute: true),
      ],
      connects: const <VsdxConnect>[
        VsdxConnect(
          fromSheetId: 12,
          fromCell: 'BeginX',
          fromPart: 9,
          toSheetId: 11,
          toCell: 'PinX',
          toPart: 3,
        ),
      ],
    );

    final bytes = codec.encode(VsdxDocument(pages: <VsdxPage>[page]));
    final xml = utf8.decode(bytes);
    expect(xml, contains('compressed="false"'));
    expect(xml, contains('source="v11"'));

    final reopened = codec.decode(bytes).pages.single;
    expect(reopened.name, 'Main');
    expect(
        reopened.shapes.singleWhere((shape) => !shape.is1D).text, 'Editable');
    expect(reopened.shapes.singleWhere((shape) => !shape.is1D).pinX,
        closeTo(2, 0.001));
    expect(reopened.shapes.singleWhere((shape) => shape.is1D).straightRoute,
        isTrue);
  });
}
