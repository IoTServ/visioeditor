import 'package:test/test.dart';
import 'package:vsdx/src/parser/layer_parser.dart';
import 'package:vsdx/src/parser/page_parser.dart';
import 'package:vsdx/vsdx.dart';
import 'package:xml/xml.dart';

void main() {
  test('LayerMember F=Inh keeps its cached value like libvisio', () {
    final el = XmlDocument.parse(
      '<Shape><Cell N="LayerMember" V="4" F="Inh"/></Shape>',
    ).rootElement;
    expect(LayerParser.parseLayerMembersOrNull(el), const <int>[4]);
  });

  test('LayerMember empty V without Inh is explicit clear', () {
    final el = XmlDocument.parse(
      '<Shape><Cell N="LayerMember" V=""/></Shape>',
    ).rootElement;
    expect(LayerParser.parseLayerMembersOrNull(el), isEmpty);
  });

  test('LayerMember parses semicolon ids', () {
    final el = XmlDocument.parse(
      '<Shape><Cell N="LayerMember" V="0;2;5"/></Shape>',
    ).rootElement;
    expect(LayerParser.parseLayerMembersOrNull(el), [0, 2, 5]);
  });

  test('malformed LayerMember clears the complete list like libvisio', () {
    for (final value in <String>['0,2', '0 2', '0;bad;2', '0;;2']) {
      final el = XmlDocument.parse(
        '<Shape><Cell N="LayerMember" V="$value"/></Shape>',
      ).rootElement;
      expect(
        LayerParser.parseLayerMembersOrNull(el),
        isEmpty,
        reason: value,
      );
    }
  });

  test('page instances do not inherit LayerMember from masters', () {
    final master = VsdxMaster(
      id: 1,
      name: 'Layered master',
      prototype: VsdxShapeFactory.rectangle(
        id: 10,
        pinX: 0,
        pinY: 0,
        width: 1,
        height: 1,
      ).copyWith(layerMemberIds: const <int>[4]),
    );
    final parser = PageParser(
      masters: MasterRegistry(<int, VsdxMaster>{1: master}),
    );
    final page = XmlDocument.parse(
      '<PageContents>'
      '<Shapes>'
      '<Shape ID="1" Master="1"/>'
      '<Shape ID="2" Master="1">'
      '<Cell N="LayerMember" V="4" F="Inh"/>'
      '</Shape>'
      '<Shape ID="3" Master="1">'
      '<Cell N="LayerMember" V="2"/>'
      '</Shape>'
      '</Shapes>'
      '</PageContents>',
    );

    final shapes = parser.parseShapes(page, partName: '/visio/pages/page1.xml');
    expect(shapes[0].layerMemberIds, isEmpty);
    expect(shapes[1].layerMemberIds, const <int>[4]);
    expect(shapes[2].layerMemberIds, const <int>[2]);
  });

  test('Layer Visible F=Inh uses default visible=true', () {
    const parser = LayerParser();
    final sheet = XmlDocument.parse('''
      <PageSheet>
        <Section N="Layer">
          <Row IX="0">
            <Cell N="Name" V="Default"/>
            <Cell N="Visible" V="0" F="Inh"/>
            <Cell N="Lock" V="1" F="Inh"/>
          </Row>
        </Section>
      </PageSheet>
    ''').rootElement;
    final layer = parser.parseLayers(sheet).single;
    expect(layer.visible, isTrue); // Inh → default 1
    expect(layer.locked, isFalse); // Inh → default 0
  });
}
