import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  test('SVG combines multi NoFill=0 geometries with evenodd', () {
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 4,
      heightInches: 4,
      shapes: [
        VsdxShape(
          id: 1,
          name: 'Frame',
          pinX: 2,
          pinY: 2,
          width: 3,
          height: 3,
          fill: const VsdxFill(
            foreground: VsdxColor(0xFF000000),
            pattern: 1,
          ),
          line: const VsdxLine(pattern: 0),
          geometries: [
            VsdxGeometry(commands: const [
              MoveTo(0, 0),
              LineTo(3, 0),
              LineTo(3, 3),
              LineTo(0, 3),
              LineTo(0, 0),
            ]),
            VsdxGeometry(commands: const [
              MoveTo(0.5, 0.5),
              LineTo(2.5, 0.5),
              LineTo(2.5, 2.5),
              LineTo(0.5, 2.5),
              LineTo(0.5, 0.5),
            ]),
          ],
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg.contains('fill-rule="evenodd"'), isTrue);
    // One combined fill path, not two solid fills.
    expect('fill-rule="evenodd"'.allMatches(svg).length, 1);
  });

  test('SVG keeps separate fills when inner geom is NoFill', () {
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 4,
      heightInches: 4,
      shapes: [
        VsdxShapeFactory.doubleRectangle(
          id: 1,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1.5,
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    // doubleRectangle inner is NoFill — must NOT collapse to evenodd hole.
    expect(svg.contains('fill-rule="evenodd"'), isFalse);
  });

  test('BPMN terminate keeps a filled inner disk for LibreOffice', () {
    final shape = VsdxShapeFactory.bpmnTerminateEvent(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.8,
      height: 1.8,
    );
    expect(shape.geometries.where((g) => !g.noFill && !g.noShow).length, 1,
        reason: 'two filled ellipses evenodd into a ring in Draw');
    final svg = VsdxToSvgSerializer().serializePage(
      VsdxPage(
        id: 0,
        name: 'Page-1',
        widthInches: 4,
        heightInches: 4,
        shapes: [shape],
      ),
    );
    expect(svg.contains('fill-rule="evenodd"'), isFalse);

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.bpmnTerminateEvent(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 1.8,
          height: 1.8,
        ),
      ),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(leftover.geometries.where((g) => !g.noFill && !g.noShow).length, 1,
        reason: 'a second save must not restore two filled ellipses');
  });

  test('floorplan bed keeps a solid mattress for LibreOffice', () {
    final shape = VsdxShapeFactory.floorplanBed(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 2.4,
      height: 1.6,
    );
    expect(shape.geometries.where((g) => !g.noFill && !g.noShow).length, 1,
        reason: 'two filled rectangles evenodd into a pillow hole in Draw');
    final svg = VsdxToSvgSerializer().serializePage(
      VsdxPage(
        id: 0,
        name: 'Page-1',
        widthInches: 4,
        heightInches: 4,
        shapes: [shape],
      ),
    );
    expect(svg.contains('fill-rule="evenodd"'), isFalse);

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.floorplanBed(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 2.4,
          height: 1.6,
        ),
      ),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(leftover.geometries.where((g) => !g.noFill && !g.noShow).length, 1,
        reason: 'a second save must not restore two filled rectangles');
  });
}
