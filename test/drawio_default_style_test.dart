import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  EditorController controller() {
    final value = EditorController()..newDocument();
    addTearDown(value.dispose);
    return value;
  }

  int rectangle(EditorController value, double x, double y) {
    value.addShapeFromBuilderAt(
      (id, cx, cy) => VsdxShapeFactory.rectangle(
        id: id,
        pinX: cx,
        pinY: cy,
        width: 1.5,
        height: 1,
      ),
      x,
      y,
    );
    return value.singleSelectedId!;
  }

  int line(EditorController value, double y) {
    value
      ..setTool(EditorTool.line)
      ..createShapeByDrag(1, y, 4, y);
    return value.singleSelectedId!;
  }

  test('vertex and edge default styles stay independent and pinned', () {
    final value = controller();
    final source = rectangle(value, 2, 6);
    value
      ..setFillColor(const VsdxColor(0xFF22AA66))
      ..setLineColor(const VsdxColor(0xFF2255CC))
      ..setSelectionAsDefaultStyle()
      ..setFillColor(const VsdxColor(0xFFCC2222));

    final inheritedVertex = rectangle(value, 5, 6);
    final vertex = value.currentPage!.findShapeById(inheritedVertex)!;
    expect(vertex.fill.foreground, const VsdxColor(0xFF22AA66));
    expect(vertex.line.color, const VsdxColor(0xFF2255CC));

    final firstEdge = line(value, 4);
    expect(
      value.currentPage!.findShapeById(firstEdge)!.line.color,
      isNot(const VsdxColor(0xFF2255CC)),
    );
    value
      ..setLineColor(const VsdxColor(0xFFFF8800))
      ..setEndArrow(10)
      ..setSelectionAsDefaultStyle()
      ..setLineColor(const VsdxColor(0xFFAA00AA))
      ..setEndArrow(0);

    final inheritedEdge = line(value, 2);
    final edge = value.currentPage!.findShapeById(inheritedEdge)!;
    expect(edge.line.color, const VsdxColor(0xFFFF8800));
    expect(edge.line.endArrow, 10);

    final laterVertex = rectangle(value, 8, 6);
    expect(
      value.currentPage!.findShapeById(laterVertex)!.fill.foreground,
      const VsdxColor(0xFF22AA66),
    );
    expect(source, isNotNull);
  });

  test('explicit vertex default carries text and effects to new shapes', () {
    final value = controller();
    rectangle(value, 2, 5);
    value
      ..setShapeText(value.singleSelectedId!, 'Source')
      ..setBold(true)
      ..setShadow(true)
      ..setGlow(true)
      ..setSelectionAsDefaultStyle();

    final created = rectangle(value, 5, 5);
    value.setShapeText(created, 'New');
    final shape = value.currentPage!.findShapeById(created)!;
    expect(shape.shadow.enabled, isTrue);
    expect(shape.glow.enabled, isTrue);
    expect(shape.richText.runs.single.charStyle.style.bold, isTrue);
  });

  test('clear resets both defaults and resumes automatic style tracking', () {
    final value = controller();
    rectangle(value, 2, 6);
    value
      ..setFillColor(const VsdxColor(0xFF22AA66))
      ..setSelectionAsDefaultStyle();
    line(value, 4);
    value
      ..setLineColor(const VsdxColor(0xFFFF8800))
      ..setSelectionAsDefaultStyle()
      ..clearDefaultStyle();

    final resetVertex = rectangle(value, 5, 6);
    expect(
      value.currentPage!.findShapeById(resetVertex)!.fill.foreground,
      VsdxColor.white,
    );
    final resetEdge = line(value, 2);
    expect(
      value.currentPage!.findShapeById(resetEdge)!.line.color,
      VsdxColor.black,
    );

    value.setSelection([resetVertex]);
    value.setFillColor(const VsdxColor(0xFF6633CC));
    final tracked = rectangle(value, 8, 6);
    expect(
      value.currentPage!.findShapeById(tracked)!.fill.foreground,
      const VsdxColor(0xFF6633CC),
    );
  });
}
