import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:visioeditor/editor/shape_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Copy as Text wins over an in-flight shape clipboard write', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final envelopeStarted = Completer<void>();
    final releaseEnvelope = Completer<void>();
    String? stored;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method != 'Clipboard.setData') return null;
      final text = (call.arguments as Map)['text'] as String?;
      if (text?.startsWith(ShapeClipboardCodec.prefix) ?? false) {
        if (!envelopeStarted.isCompleted) envelopeStarted.complete();
        await releaseEnvelope.future;
      }
      stored = text;
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    final controller = EditorController()..newDocument();
    addTearDown(controller.dispose);
    controller
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 3, 2);
    final shapeId = controller.singleSelectedId!;
    controller.setShapeText(shapeId, 'Plain label');

    controller.copySelection();
    await envelopeStarted.future;
    final copyText = controller.copySelectionAsText();
    releaseEnvelope.complete();

    expect(await copyText, isTrue);
    expect(stored, 'Plain label');
  });

  test('Copy as Text requires a valid selection', () async {
    final controller = EditorController()..newDocument();
    addTearDown(controller.dispose);

    expect(controller.canCopySelectionAsText, isFalse);
    expect(await controller.copySelectionAsText(), isFalse);
  });
}
