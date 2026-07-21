import 'package:test/test.dart';
import 'package:vsdx/src/parser/page_parser.dart';
import 'package:vsdx/vsdx.dart';
import 'package:xml/xml.dart';

void main() {
  test('Scratch X F=Inh inherits master value and formula', () {
    final master = VsdxMaster(
      id: 1,
      name: 'WithScratch',
      prototype: VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 0,
        pinY: 0,
        width: 2,
        height: 1,
      ).copyWith(
        scratch: const [
          VsdxScratchRow(ix: 0, x: 1.5, y: 0.25, xFormula: 'Width*0.5'),
        ],
      ),
    );
    final parser = PageParser(masters: MasterRegistry({1: master}));
    final doc = XmlDocument.parse(
      '<PageContents xmlns="http://schemas.microsoft.com/office/visio/2012/main">'
      '<Shapes>'
      '<Shape ID="5" Type="Shape" Master="1">'
      '<Cell N="PinX" V="2"/>'
      '<Cell N="PinY" V="2"/>'
      '<Cell N="Width" V="2"/>'
      '<Cell N="Height" V="1"/>'
      '<Section N="Scratch">'
      '<Row IX="0">'
      '<Cell N="X" V="0" F="Inh"/>'
      '<Cell N="Y" V="0.8"/>'
      '</Row>'
      '</Section>'
      '</Shape>'
      '</Shapes>'
      '</PageContents>',
    );
    final shapes = parser.parseShapes(doc, partName: '/visio/pages/page1.xml');
    expect(shapes.single.scratch, hasLength(1));
    expect(shapes.single.scratch.single.x, closeTo(1.5, 1e-9));
    expect(shapes.single.scratch.single.y, closeTo(0.8, 1e-9));
    expect(shapes.single.scratch.single.xFormula, 'Width*0.5');
  });

  test('Actions Checked F=Inh inherits master flag', () {
    final master = VsdxMaster(
      id: 2,
      name: 'WithAction',
      prototype: VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 0,
        pinY: 0,
        width: 1,
        height: 1,
      ).copyWith(
        actions: const [
          VsdxActionRow(name: 'DoIt', ix: 0, menu: 'Do it', checked: true),
        ],
      ),
    );
    final parser = PageParser(masters: MasterRegistry({2: master}));
    final doc = XmlDocument.parse(
      '<PageContents xmlns="http://schemas.microsoft.com/office/visio/2012/main">'
      '<Shapes>'
      '<Shape ID="6" Type="Shape" Master="2">'
      '<Cell N="PinX" V="2"/>'
      '<Cell N="PinY" V="2"/>'
      '<Cell N="Width" V="1"/>'
      '<Cell N="Height" V="1"/>'
      '<Section N="Actions">'
      '<Row N="DoIt" IX="0">'
      '<Cell N="Menu" V="Do it"/>'
      '<Cell N="Checked" V="0" F="Inh"/>'
      '</Row>'
      '</Section>'
      '</Shape>'
      '</Shapes>'
      '</PageContents>',
    );
    final shapes = parser.parseShapes(doc, partName: '/visio/pages/page1.xml');
    expect(shapes.single.actions.single.checked, isTrue);
  });
}
