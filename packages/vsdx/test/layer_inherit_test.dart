import 'package:test/test.dart';
import 'package:vsdx/src/parser/layer_parser.dart';
import 'package:xml/xml.dart';

void main() {
  test('LayerMember F=Inh is treated as absent (inherit)', () {
    final el = XmlDocument.parse(
      '<Shape><Cell N="LayerMember" V="" F="Inh"/></Shape>',
    ).rootElement;
    expect(LayerParser.parseLayerMembersOrNull(el), isNull);
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
}
