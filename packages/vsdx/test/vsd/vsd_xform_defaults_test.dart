import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';
import 'package:vsdx/src/parser/vsd/vsd_parser.dart';

void main() {
  test('binary VSD missing XFormData uses libvisio zero defaults', () {
    expect(vsdDefaultShapeXForm.pinX, 0);
    expect(vsdDefaultShapeXForm.pinY, 0);
    expect(vsdDefaultShapeXForm.width, 0);
    expect(vsdDefaultShapeXForm.height, 0);
    expect(vsdDefaultShapeXForm.locPinX, 0);
    expect(vsdDefaultShapeXForm.locPinY, 0);
  });

  test('unstyled Visio shapes use libvisio no-fill defaults', () {
    expect(libvisioShapeFillDefault.pattern, 0);
    expect(libvisioShapeFillDefault.foreground, isNull);
    expect(libvisioShapeFillDefault.background, isNull);
  });
}
