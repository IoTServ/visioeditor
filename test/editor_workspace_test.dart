import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_workspace.dart';

void main() {
  test('moveAt reorders docs and keeps active selection', () {
    final ws = EditorWorkspace();
    ws.newDocument();
    ws.newDocument();
    ws.newDocument();
    expect(ws.docs.length, 3);
    expect(ws.activeIndex, 2);

    final a = ws.docs[0];
    final b = ws.docs[1];
    final c = ws.docs[2];

    // Move last tab to front.
    ws.moveAt(2, 0);
    expect(ws.docs, [c, a, b]);
    expect(ws.activeIndex, 0);

    // Move middle to end.
    ws.moveAt(1, 2);
    expect(ws.docs, [c, b, a]);
    expect(ws.activeIndex, 0);
  });

  test('moveAt adjusts active when a tab slides across it', () {
    final ws = EditorWorkspace();
    ws.newDocument();
    ws.newDocument();
    ws.newDocument();
    ws.setActive(1);
    final a = ws.docs[0];
    final b = ws.docs[1];
    final c = ws.docs[2];

    ws.moveAt(0, 2); // a to end
    expect(ws.docs, [b, c, a]);
    expect(ws.activeIndex, 0); // was 1, left neighbor removed → 0
  });

  test('closeAt disposes and clamps active index', () {
    final ws = EditorWorkspace();
    ws.newDocument();
    ws.newDocument();
    expect(ws.activeIndex, 1);
    ws.closeAt(1);
    expect(ws.docs.length, 1);
    expect(ws.activeIndex, 0);
    ws.closeAt(0);
    expect(ws.hasDocs, isFalse);
    expect(ws.activeIndex, -1);
  });
}
