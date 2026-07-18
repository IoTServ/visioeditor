import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:visioeditor/editor/shape_clipboard.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  EditorController ctrl() {
    final c = EditorController()
      ..newDocument(widthInches: 11, heightInches: 8.5);
    addTearDown(c.dispose);
    return c;
  }

  int rect(EditorController e, double x, double y) {
    e.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id, pinX: cx, pinY: cy, width: 1, height: 0.6),
        x,
        y);
    return e.singleSelectedId!;
  }

  void mockClipboard(void Function(String? stored) onStore) {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    String? stored;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        stored = (call.arguments as Map)['text'] as String?;
        onStore(stored);
        return null;
      }
      if (call.method == 'Clipboard.getData') {
        return stored == null ? null : <String, dynamic>{'text': stored};
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });
  }

  test('selectAll skips shapes on hidden layers', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.addLayer(name: 'Hide');
    final layerId = e.currentPage!.layers.last.id;
    e.setSelection([a]);
    e.assignSelectionToLayer(layerId);
    e.toggleLayerVisibility(layerId);
    e.selectAll();
    expect(e.selection.contains(a), isFalse);
    expect(e.selection.contains(b), isTrue);
  });

  test('pasteFromSystem keeps Connect glue from same-app copy', () async {
    mockClipboard((_) {});
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.createConnector(2, 4, 5, 4, beginTarget: a, endTarget: b);
    final conn = e.currentPage!.shapes.lastWhere((s) => s.is1D).id;
    e.setSelection([a, b, conn]);
    e.copySelection();
    await Future<void>.delayed(Duration.zero);
    final before = e.currentPage!.shapes.length;
    await e.pasteFromSystem();
    expect(e.currentPage!.shapes.length, before + 3);
    // New connectors should have glue to the pasted boxes.
    final pastedConnectors = e.currentPage!.shapes.where((s) => s.is1D).toList();
    expect(pastedConnectors, hasLength(2));
    expect(e.currentPage!.connects.length, greaterThanOrEqualTo(4));
  });

  test('ShapeClipboardCodec encode carries Connect rows', () {
    final shapes = <VsdxShape>[
      VsdxShapeFactory.rectangle(id: 1, pinX: 1, pinY: 1, width: 1, height: 1),
      VsdxShapeFactory.rectangle(id: 2, pinX: 3, pinY: 1, width: 1, height: 1),
      VsdxShapeFactory.line(id: 3, ax: 1, ay: 1, bx: 3, by: 1),
    ];
    const connects = <VsdxConnect>[
      VsdxConnect(
        fromSheetId: 3,
        fromCell: 'BeginX',
        fromPart: 9,
        toSheetId: 1,
        toCell: 'PinX',
        toPart: 3,
      ),
      VsdxConnect(
        fromSheetId: 3,
        fromCell: 'EndX',
        fromPart: 12,
        toSheetId: 2,
        toCell: 'PinX',
        toPart: 3,
      ),
    ];
    final envelope = ShapeClipboardCodec.encode(shapes, connects: connects);
    final payload = ShapeClipboardCodec.decodeEnvelope(envelope)!;
    expect(payload.shapes, hasLength(3));
    expect(payload.connects, hasLength(2));
  });

  test('copy group+child pastes one root only', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 4, 4);
    e.setSelection([a, b]);
    e.groupSelection();
    final g = e.singleSelectedId!;
    final child = e.currentPage!.findShapeById(g)!.children.first.id;
    e.setSelection([g, child]);
    e.copySelection();
    e.paste();
    final groups = e.currentPage!.shapes.where((s) => s.children.isNotEmpty);
    expect(groups, hasLength(2));
    // No extra top-level duplicate of the child.
    expect(e.currentPage!.shapes.where((s) => s.children.isEmpty), hasLength(0));
  });

  test('pasteAt centres rotated shape via AABB', () {
    final e = ctrl();
    final a = rect(e, 3, 4);
    e.setSelection([a]);
    e.rotateShape(a, 0.7);
    e.copySelection();
    e.pasteAt(cx: 6, cy: 3);
    final pasted = e.currentPage!.shapes.lastWhere((s) => s.id != a);
    final aabb = e.currentPage!.shapePageAabb(pasted.id)!;
    final cx = (aabb.left + aabb.right) / 2;
    final cy = (aabb.top + aabb.bottom) / 2;
    expect(cx, closeTo(6, 0.15));
    expect(cy, closeTo(3, 0.15));
  });

  test('discardAbandonedShape after bold collapses create history', () {
    final e = ctrl();
    e.setTool(EditorTool.text);
    e.createShapeByDrag(2, 4, 3.5, 4.5);
    final id = e.singleSelectedId!;
    e.toggleBold();
    e.discardAbandonedShape(id);
    expect(e.currentPage!.findShapeById(id), isNull);
    // Must not be able to undo the abandoned box back into existence.
    if (e.canUndo) e.undo();
    expect(e.currentPage!.findShapeById(id), isNull);
  });

  test('pictureShapeAt ignores hidden-layer pictures', () {
    final e = ctrl();
    e.insertImage(
      Uint8List.fromList([1, 2, 3, 4]),
      fileExtension: 'png',
      widthInches: 1,
      heightInches: 1,
      cx: 3,
      cy: 3,
    );
    final img = e.currentPage!.shapes.singleWhere((s) => s.hasImage).id;
    e.addLayer(name: 'Hide');
    final layerId = e.currentPage!.layers.last.id;
    e.setSelection([img]);
    e.assignSelectionToLayer(layerId);
    expect(e.pictureShapeAt(3, 3), img);
    e.toggleLayerVisibility(layerId);
    expect(e.pictureShapeAt(3, 3), isNull);
  });

  test('selectVertices skips hidden-layer shapes', () {
    final e = ctrl();
    final a = rect(e, 2, 4);
    final b = rect(e, 5, 4);
    e.addLayer(name: 'Hide');
    final layerId = e.currentPage!.layers.last.id;
    e.setSelection([a]);
    e.assignSelectionToLayer(layerId);
    e.toggleLayerVisibility(layerId);
    e.selectVertices();
    expect(e.selection.contains(a), isFalse);
    expect(e.selection.contains(b), isTrue);
  });
}
