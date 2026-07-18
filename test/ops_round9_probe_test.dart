import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/edit_link_dialog.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  EditorController ctrl() {
    final c = EditorController()
      ..newDocument(widthInches: 11, heightInches: 8.5);
    addTearDown(c.dispose);
    return c;
  }

  int rect(EditorController e, double x, double y,
      {double w = 1, double h = 0.6}) {
    e.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id, pinX: cx, pinY: cy, width: w, height: h),
        x,
        y);
    return e.singleSelectedId!;
  }

  test('bringForward reorders siblings inside a group', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 4, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    e.setSelection([a]);
    e.bringSelectionForward();
    final kids = e.currentPage!.findShapeById(g)!.children.map((s) => s.id);
    expect(kids.toList(), [b, a]);
  });

  test('sendToBack reorders siblings inside a group', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 4, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    e.setSelection([b]);
    e.sendSelectionToBack();
    final kids = e.currentPage!.findShapeById(g)!.children.map((s) => s.id);
    expect(kids.toList(), [b, a]);
  });

  test('addLayer assignSelection assigns nested selected child', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 4, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    e.setSelection([a]);
    e.addLayer(name: 'Nested', assignSelection: true);
    final layerId = e.currentPage!.layers.last.id;
    expect(e.currentPage!.findShapeById(a)!.layerMemberIds, contains(layerId));
  });

  test('deleteLayer clears nested membership', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 4, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    e.setSelection([a]);
    e.addLayer(name: 'L');
    final layerId = e.currentPage!.layers.last.id;
    e.assignSelectionToLayer(layerId);
    expect(e.currentPage!.findShapeById(a)!.layerMemberIds, contains(layerId));
    e.deleteLayer(layerId);
    expect(e.currentPage!.findShapeById(a)!.layerMemberIds, isEmpty);
  });

  test('mergeEditedPrimaryLink keeps secondary rows', () {
    final existing = [
      const VsdxHyperlink(id: 0, address: 'https://a.example', isDefault: true),
      const VsdxHyperlink(id: 1, address: 'https://b.example', isDefault: false),
    ];
    final merged = mergeEditedPrimaryLink(
      existing: existing,
      editedPrimary: const VsdxHyperlink(
        id: 0,
        address: 'https://c.example',
        isDefault: true,
      ),
    );
    expect(merged, hasLength(2));
    expect(merged.any((h) => h.address == 'https://b.example'), isTrue);
    expect(merged.any((h) => h.address == 'https://c.example'), isTrue);
    final removed = mergeEditedPrimaryLink(
      existing: existing,
      editedPrimary: null,
    );
    expect(removed, hasLength(1));
    expect(removed.single.address, 'https://b.example');
  });

  test('setShapeText no-op when locked', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.setShapeText(a, 'hello');
    e.setSelectionLocked(true);
    e.setShapeText(a, 'world');
    expect(e.currentPage!.findShapeById(a)!.richText.plainText, 'hello');
  });

  test('duplicateSelection undo restores selection after page switch paste', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    e.copySelection();
    e.addPage();
    e.paste();
    final pasted = e.singleSelectedId!;
    e.undo();
    expect(e.currentPageIndex, 1);
    expect(e.currentPage!.findShapeById(pasted), isNull);
    expect(e.selection, isEmpty); // was empty on new page before paste
    e.selectPage(0);
    expect(e.currentPage!.findShapeById(a), isNotNull);
  });
}
