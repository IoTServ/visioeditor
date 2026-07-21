import 'package:test/test.dart';
import 'package:vsdx/src/parser/page_parser.dart';
import 'package:vsdx/vsdx.dart';
import 'package:xml/xml.dart';

void main() {
  test('Hyperlink Address F=Inh inherits master URL', () {
    final master = VsdxMaster(
      id: 1,
      name: 'WithLink',
      prototype: VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 0,
        pinY: 0,
        width: 2,
        height: 1,
      ).copyWith(
        hyperlinks: const [
          VsdxHyperlink(
            id: 0,
            description: 'Docs',
            address: 'https://example.com/master',
            newWindow: true,
          ),
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
      '<Section N="Hyperlink">'
      '<Row IX="0">'
      '<Cell N="Description" V="Docs"/>'
      '<Cell N="Address" V="https://stale.example/" F="Inh"/>'
      '<Cell N="NewWindow" V="0" F="Inh"/>'
      '</Row>'
      '</Section>'
      '</Shape>'
      '</Shapes>'
      '</PageContents>',
    );
    final shapes = parser.parseShapes(doc, partName: '/visio/pages/page1.xml');
    expect(shapes.single.hyperlinks, hasLength(1));
    expect(shapes.single.hyperlinks.single.address, 'https://example.com/master');
    expect(shapes.single.hyperlinks.single.newWindow, isTrue);
  });

  test('Property Value F=Inh inherits master shape data', () {
    final master = VsdxMaster(
      id: 2,
      name: 'WithProp',
      prototype: VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 0,
        pinY: 0,
        width: 1,
        height: 1,
      ).copyWith(
        userProperties: const [
          VsdxUserProperty(
            name: 'Cost',
            label: 'Estimated cost',
            value: '42.5',
            valueFormula: 'Prop.Cost',
            type: 2,
          ),
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
      '<Section N="Property">'
      '<Row N="Cost" IX="1">'
      '<Cell N="Label" V="Estimated cost"/>'
      '<Cell N="Value" V="0" F="Inh"/>'
      '<Cell N="Type" V="0" F="Inh"/>'
      '</Row>'
      '</Section>'
      '</Shape>'
      '</Shapes>'
      '</PageContents>',
    );
    final shapes = parser.parseShapes(doc, partName: '/visio/pages/page1.xml');
    final prop = shapes.single.userProperties.single;
    expect(prop.value, '42.5');
    expect(prop.type, 2);
    expect(prop.valueFormula, 'Prop.Cost');
  });

  test('User cell Value F=Inh inherits master formula cell', () {
    final master = VsdxMaster(
      id: 3,
      name: 'WithUser',
      prototype: VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 0,
        pinY: 0,
        width: 1,
        height: 1,
      ).copyWith(
        userCells: const [
          VsdxUserCell(
            name: 'RowRoute',
            value: '1',
            valueFormula: '1',
            prompt: 'route',
          ),
        ],
      ),
    );
    final parser = PageParser(masters: MasterRegistry({3: master}));
    final doc = XmlDocument.parse(
      '<PageContents xmlns="http://schemas.microsoft.com/office/visio/2012/main">'
      '<Shapes>'
      '<Shape ID="7" Type="Shape" Master="3">'
      '<Cell N="PinX" V="2"/>'
      '<Cell N="PinY" V="2"/>'
      '<Cell N="Width" V="1"/>'
      '<Cell N="Height" V="1"/>'
      '<Section N="User">'
      '<Row N="RowRoute" IX="0">'
      '<Cell N="Value" V="0" F="Inh"/>'
      '<Cell N="Prompt" V="local"/>'
      '</Row>'
      '</Section>'
      '</Shape>'
      '</Shapes>'
      '</PageContents>',
    );
    final shapes = parser.parseShapes(doc, partName: '/visio/pages/page1.xml');
    final cell = shapes.single.userCells.single;
    expect(cell.value, '1');
    expect(cell.valueFormula, '1');
    expect(cell.prompt, 'local');
  });
}
