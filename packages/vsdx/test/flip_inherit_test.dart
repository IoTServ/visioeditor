import 'package:test/test.dart';
import 'package:vsdx/src/model/master.dart';
import 'package:vsdx/src/parser/page_parser.dart';
import 'package:vsdx/vsdx.dart';
import 'package:xml/xml.dart';

void main() {
  test('FlipX F=Inh inherits Master flip (not cached V=0)', () {
    final master = VsdxMaster(
      id: 1,
      name: 'Flipped',
      prototype: VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 0,
        pinY: 0,
        width: 1,
        height: 1,
      ).copyWith(flipX: true),
    );
    final parser = PageParser(
      masters: MasterRegistry({1: master}),
    );
    final doc = XmlDocument.parse(
      '<PageContents xmlns="http://schemas.microsoft.com/office/visio/2012/main">'
      '<Shapes>'
      '<Shape ID="5" Type="Shape" Master="1">'
      '<Cell N="PinX" V="2"/>'
      '<Cell N="PinY" V="2"/>'
      '<Cell N="Width" V="1"/>'
      '<Cell N="Height" V="1"/>'
      '<Cell N="FlipX" V="0" F="Inh"/>'
      '</Shape>'
      '</Shapes>'
      '</PageContents>',
    );
    final shapes = parser.parseShapes(doc, partName: '/visio/pages/page1.xml');
    expect(shapes, hasLength(1));
    expect(shapes.first.flipX, isTrue);
  });

  test('LockMoveX F=Inh inherits Master lock (not cached V=0)', () {
    final master = VsdxMaster(
      id: 2,
      name: 'Locked',
      prototype: VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 0,
        pinY: 0,
        width: 1,
        height: 1,
      ).copyWith(locked: true),
    );
    final parser = PageParser(
      masters: MasterRegistry({2: master}),
    );
    final doc = XmlDocument.parse(
      '<PageContents xmlns="http://schemas.microsoft.com/office/visio/2012/main">'
      '<Shapes>'
      '<Shape ID="6" Type="Shape" Master="2">'
      '<Cell N="PinX" V="2"/>'
      '<Cell N="PinY" V="2"/>'
      '<Cell N="Width" V="1"/>'
      '<Cell N="Height" V="1"/>'
      '<Cell N="LockMoveX" V="0" F="Inh"/>'
      '</Shape>'
      '</Shapes>'
      '</PageContents>',
    );
    final shapes = parser.parseShapes(doc, partName: '/visio/pages/page1.xml');
    expect(shapes, hasLength(1));
    expect(shapes.first.locked, isTrue);
  });
}
