import 'package:test/test.dart';
import 'package:vsdx/agent.dart';
import 'package:vsdx/stencils.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  test('chart stencils build groups with series children', () {
    expect(kChartStencils, isNotEmpty);
    for (final s in kChartStencils) {
      final shape = s.build(1, 4, 5);
      expect(shape.shapeKind, VsdxShapeKind.group, reason: s.name);
      expect(shape.children, isNotEmpty, reason: s.name);
      expect(shape.connectionPoints, isNotEmpty, reason: s.name);
    }
  });

  test('column chart round-trips through vsdx writer', () {
    const writer = VsdxWriter();
    const parser = DocumentParser();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final chart = ChartOps.columnChart(id: 10, pinX: 3, pinY: 4);
    doc = doc.replacePage(0, doc.pages.first.addShape(chart));
    final out = writer.write(originalBytes: blank, edited: doc);
    final after = parser.parse(out);
    final loaded = after.pages.first.findShapeById(10);
    expect(loaded, isNotNull);
    expect(loaded!.shapeKind, VsdxShapeKind.group);
    expect(loaded.children.length, chart.children.length);
    expect(loaded.connectionPoints, isNotEmpty);
    expect(validateDocument(after).where((i) => i.severity == 'error'), isEmpty);
  });

  test('pie and line charts round-trip', () {
    const writer = VsdxWriter();
    const parser = DocumentParser();
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    var page = doc.pages.first;
    page = page.addShape(ChartOps.pieChart(id: 20, pinX: 2, pinY: 2));
    page = page.addShape(ChartOps.lineChart(id: 40, pinX: 5, pinY: 2));
    doc = doc.replacePage(0, page);
    final out = writer.write(originalBytes: blank, edited: doc);
    final after = parser.parse(out).pages.first;
    expect(after.findShapeById(20)!.children, isNotEmpty);
    expect(after.findShapeById(40)!.children, isNotEmpty);
  });
}
