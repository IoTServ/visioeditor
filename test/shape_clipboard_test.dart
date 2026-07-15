import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:visioeditor/editor/shape_clipboard.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ShapeClipboardCodec round-trips geometry + text', () {
    final shapes = <VsdxShape>[
      VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 2,
        pinY: 3,
        width: 1.5,
        height: 1,
      ).copyWith(text: 'Hello'),
      VsdxShapeFactory.ellipse(
        id: 2,
        pinX: 5,
        pinY: 4,
        width: 1,
        height: 1,
      ),
    ];
    final envelope = ShapeClipboardCodec.encode(shapes);
    expect(envelope, startsWith(ShapeClipboardCodec.prefix));
    final decoded = ShapeClipboardCodec.decode(envelope)!;
    expect(decoded, hasLength(2));
    expect(decoded[0].text, 'Hello');
    expect(decoded[0].width, closeTo(1.5, 1e-6));
    expect(decoded[1].geometries, isNotEmpty);
  });

  test('system clipboard paste restores shapes across sync', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // Fake clipboard channel so Clipboard.setData/getData work in tests.
    String? stored;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        stored = (call.arguments as Map)['text'] as String?;
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

    final src = EditorController()..newDocument();
    src
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 2, 2);
    final id = src.currentPage!.shapes.single.id;
    src.setSelection(<int>{id});
    src.copySelection();
    // Allow the fire-and-forget system write to complete.
    await Future<void>.delayed(Duration.zero);
    expect(stored, isNotNull);
    expect(stored!, startsWith(ShapeClipboardCodec.prefix));

    final dst = EditorController()..newDocument();
    expect(dst.currentPage!.shapes, isEmpty);
    await dst.pasteFromSystem(cx: 4, cy: 5);
    expect(dst.currentPage!.shapes, hasLength(1));
    final pasted = dst.currentPage!.shapes.single;
    expect(pasted.pinX, closeTo(4, 1e-6));
    expect(pasted.pinY, closeTo(5, 1e-6));
  });

  test('layer add / rename / assign / lock round-trip through controller', () {
    final c = EditorController()..newDocument();
    c
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 2, 2);
    final id = c.currentPage!.shapes.single.id;
    c.setSelection(<int>{id});

    c.addLayer(name: 'Foreground', assignSelection: true);
    expect(c.currentPage!.layers, hasLength(1));
    expect(c.currentPage!.layers.single.name, 'Foreground');
    expect(c.currentPage!.shapes.single.layerMemberIds, <int>[0]);

    c.renameLayer(0, 'Main');
    expect(c.currentPage!.layers.single.name, 'Main');

    c.toggleLayerLocked(0);
    expect(c.currentPage!.layers.single.locked, isTrue);
    expect(c.isOnLockedLayer(id), isTrue);

    // Locked layer blocks delete.
    c.deleteSelection();
    expect(c.currentPage!.shapes, hasLength(1));

    c.toggleLayerLocked(0);
    c.deleteSelection();
    expect(c.currentPage!.shapes, isEmpty);
  });
}
