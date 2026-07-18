import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';

void main() {
  test('undo/redo addPage restores currentPageIndex', () {
    final c = EditorController()..newDocument();
    addTearDown(c.dispose);
    expect(c.currentPageIndex, 0);
    c.addPage();
    expect(c.pageCount, 2);
    expect(c.currentPageIndex, 1);
    c.undo();
    expect(c.pageCount, 1);
    expect(c.currentPageIndex, 0,
        reason: 'stale index=${c.currentPageIndex} after undo addPage');
    c.redo();
    expect(c.pageCount, 2);
    expect(c.currentPageIndex, 1);
  });

  test('undo deleteCurrentPage restores viewing the restored page', () {
    final c = EditorController()..newDocument();
    addTearDown(c.dispose);
    c.addPage();
    c.addPage();
    expect(c.pageCount, 3);
    expect(c.currentPageIndex, 2);
    c.deleteCurrentPage();
    expect(c.pageCount, 2);
    expect(c.currentPageIndex, 1);
    c.undo();
    expect(c.pageCount, 3);
    expect(c.currentPageIndex, 2,
        reason:
            'undo delete should reselect restored page, index=${c.currentPageIndex}');
  });
}
