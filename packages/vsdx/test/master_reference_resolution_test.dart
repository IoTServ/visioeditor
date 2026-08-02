import 'package:test/test.dart';
import 'package:vsdx/src/parser/page_parser.dart';
import 'package:vsdx/vsdx.dart';
import 'package:xml/xml.dart';

VsdxMaster _master({
  required int id,
  required double prototypeWidth,
  required double childWidth,
}) {
  final child = VsdxShapeFactory.rectangle(
    id: 11,
    pinX: 0,
    pinY: 0,
    width: childWidth,
    height: childWidth + 1,
  );
  final prototype = VsdxShapeFactory.rectangle(
    id: id * 10,
    pinX: 0,
    pinY: 0,
    width: prototypeWidth,
    height: prototypeWidth + 1,
  ).copyWith(children: <VsdxShape>[child]);
  return VsdxMaster(id: id, name: 'Master $id', prototype: prototype);
}

void main() {
  test('MasterShape wins when Master and MasterShape are both present', () {
    final parser = PageParser(
      masters: MasterRegistry(<int, VsdxMaster>{
        1: _master(id: 1, prototypeWidth: 10, childWidth: 7),
        2: _master(id: 2, prototypeWidth: 20, childWidth: 9),
      }),
    );
    final document = XmlDocument.parse(
      '<PageContents xmlns="http://schemas.microsoft.com/office/visio/2012/main">'
      '<Shapes>'
      '<Shape ID="100" Master="2" MasterShape="11"/>'
      '</Shapes>'
      '</PageContents>',
    );

    final shape =
        parser.parseShapes(document, partName: '/visio/pages/page1.xml').single;
    expect(shape.width, 9);
    expect(shape.height, 10);
  });

  test('nested Master references stay in the parent master context', () {
    final parser = PageParser(
      masters: MasterRegistry(<int, VsdxMaster>{
        1: _master(id: 1, prototypeWidth: 10, childWidth: 7),
        2: _master(id: 2, prototypeWidth: 20, childWidth: 9),
      }),
    );
    final document = XmlDocument.parse(
      '<PageContents xmlns="http://schemas.microsoft.com/office/visio/2012/main">'
      '<Shapes>'
      '<Shape ID="200" Master="1">'
      '<Shapes><Shape ID="201" Master="2" MasterShape="11"/></Shapes>'
      '</Shape>'
      '</Shapes>'
      '</PageContents>',
    );

    final child = parser
        .parseShapes(document, partName: '/visio/pages/page1.xml')
        .single
        .children
        .single;
    expect(child.width, 7);
    expect(child.height, 8);
  });

  test('nested Master cannot introduce a master when parent has none', () {
    final parser = PageParser(
      masters: MasterRegistry(<int, VsdxMaster>{
        2: _master(id: 2, prototypeWidth: 20, childWidth: 9),
      }),
    );
    final document = XmlDocument.parse(
      '<PageContents xmlns="http://schemas.microsoft.com/office/visio/2012/main">'
      '<Shapes>'
      '<Shape ID="200"><Shapes>'
      '<Shape ID="201" Master="2" MasterShape="11"/>'
      '</Shapes></Shape>'
      '</Shapes>'
      '</PageContents>',
    );

    final child = parser
        .parseShapes(document, partName: '/visio/pages/page1.xml')
        .single
        .children
        .single;
    expect(child.width, 1);
    expect(child.height, 1);
  });

  test('Begin and End cells identify 1-D shapes without Type', () {
    const parser = PageParser();
    final document = XmlDocument.parse(
      '<PageContents xmlns="http://schemas.microsoft.com/office/visio/2012/main">'
      '<Shapes><Shape ID="1">'
      '<Cell N="BeginX" V="1"/><Cell N="BeginY" V="2"/>'
      '<Cell N="EndX" V="3"/><Cell N="EndY" V="4"/>'
      '</Shape></Shapes>'
      '</PageContents>',
    );

    final shape =
        parser.parseShapes(document, partName: '/visio/pages/page1.xml').single;
    expect(shape.is1D, isTrue);
    expect(shape.beginX, 1);
    expect(shape.endY, 4);
  });
}
