import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:visioeditor/io/document_io.dart';
import 'package:visioeditor/io/document_save.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  EditorController controllerWithShape() {
    final controller = EditorController()..newDocument();
    addTearDown(controller.dispose);
    controller
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 3, 2);
    return controller;
  }

  void establishPath(EditorController controller, String path) {
    final snapshot = controller.document!;
    controller.markSaved(
      controller.exportToBytes(),
      path: path,
      savedDocument: snapshot,
    );
  }

  test(
    'regular desktop save overwrites its path with reopenable bytes',
    () async {
      final controller = controllerWithShape();
      const path = '/documents/diagram.vsdx';
      establishPath(controller, path);
      final id = controller.singleSelectedId!;
      controller.setShapeText(id, 'Saved label');
      Uint8List? written;

      final result = await saveEditorDocument(
        controller,
        saveAs: false,
        directFileSave: true,
        writer: (actualPath, bytes) async {
          expect(actualPath, path);
          written = bytes;
        },
        picker: ({required bytes, required suggestedName}) async {
          fail('an existing desktop path must not open Save As');
        },
      );

      expect(result?.persistentPath, path);
      expect(controller.filePath, path);
      expect(controller.isDirty, isFalse);
      final reopened = const DocumentParser().parse(written!);
      expect(reopened.pages.first.findShapeById(id)!.text, 'Saved label');
    },
  );

  test('Save As uses the picker and adopts its desktop path', () async {
    final controller = controllerWithShape();
    establishPath(controller, '/documents/original.vsdx');
    controller.setShapeText(controller.singleSelectedId!, 'Copy');
    Uint8List? pickedBytes;

    final result = await saveEditorDocument(
      controller,
      saveAs: true,
      directFileSave: true,
      picker: ({required bytes, required suggestedName}) async {
        expect(suggestedName, 'original.vsdx');
        pickedBytes = bytes;
        return '/documents/copy.vsdx';
      },
    );

    expect(result?.path, '/documents/copy.vsdx');
    expect(controller.filePath, '/documents/copy.vsdx');
    expect(controller.fileName, 'copy.vsdx');
    expect(controller.isDirty, isFalse);
    expect(() => const DocumentParser().parse(pickedBytes!), returnsNormally);
  });

  test('regular save never overwrites an imported legacy VSD', () async {
    final controller = controllerWithShape();
    establishPath(controller, '/documents/legacy.vsd');
    controller.setShapeText(controller.singleSelectedId!, 'Imported edit');

    final result = await saveEditorDocument(
      controller,
      saveAs: false,
      directFileSave: true,
      writer: (_, _) => fail('legacy VSD must not be overwritten'),
      picker: ({required bytes, required suggestedName}) async {
        expect(suggestedName, 'legacy.vsd');
        return '/documents/legacy.vsdx';
      },
    );

    expect(result?.path, '/documents/legacy.vsdx');
    expect(controller.filePath, '/documents/legacy.vsdx');
  });

  test(
    'Web/mobile saves always export and clear a non-reusable path',
    () async {
      final controller = controllerWithShape();
      establishPath(controller, '/temporary/provider-copy.vsdx');
      controller.setShapeText(controller.singleSelectedId!, 'Portable');
      var picks = 0;

      Future<String?> picker({
        required Uint8List bytes,
        required String suggestedName,
      }) async {
        picks++;
        expect(() => const DocumentParser().parse(bytes), returnsNormally);
        return 'portable.vsdx';
      }

      final first = await saveEditorDocument(
        controller,
        saveAs: false,
        directFileSave: false,
        picker: picker,
      );
      expect(first?.persistentPath, isNull);
      expect(controller.filePath, isNull);
      expect(controller.fileName, 'portable.vsdx');
      expect(controller.isDirty, isFalse);

      controller.setShapeText(controller.singleSelectedId!, 'Portable again');
      await saveEditorDocument(
        controller,
        saveAs: false,
        directFileSave: false,
        picker: picker,
      );
      expect(
        picks,
        2,
        reason: 'non-reusable destinations must export each save',
      );
    },
  );

  test('edits made while a disk save is pending remain dirty', () async {
    final controller = controllerWithShape();
    const path = '/documents/diagram.vsdx';
    establishPath(controller, path);
    final id = controller.singleSelectedId!;
    controller.setShapeText(id, 'Included');
    final writeStarted = Completer<void>();
    final allowWrite = Completer<void>();
    Uint8List? written;

    final saving = saveEditorDocument(
      controller,
      saveAs: false,
      directFileSave: true,
      writer: (_, bytes) async {
        written = bytes;
        writeStarted.complete();
        await allowWrite.future;
      },
    );
    await writeStarted.future;
    controller.setShapeText(id, 'Edited during save');
    allowWrite.complete();
    await saving;

    expect(controller.isDirty, isTrue);
    expect(
      controller.currentPage!.findShapeById(id)!.text,
      'Edited during save',
    );
    expect(
      const DocumentParser()
          .parse(written!)
          .pages
          .first
          .findShapeById(id)!
          .text,
      'Included',
    );
  });

  test(
    'cancel and duplicate requests do not mark unsaved work clean',
    () async {
      final controller = controllerWithShape();
      controller.setShapeText(controller.singleSelectedId!, 'Unsaved');
      final pickerStarted = Completer<void>();
      final finishPicker = Completer<String?>();

      final first = saveEditorDocument(
        controller,
        saveAs: true,
        directFileSave: true,
        picker: ({required bytes, required suggestedName}) {
          pickerStarted.complete();
          return finishPicker.future;
        },
      );
      await pickerStarted.future;
      final duplicate = await saveEditorDocument(
        controller,
        saveAs: true,
        directFileSave: true,
        picker: ({required bytes, required suggestedName}) async =>
            '/documents/duplicate.vsdx',
      );
      expect(duplicate, isNull);

      finishPicker.complete(null);
      expect(await first, isNull);
      expect(controller.isDirty, isTrue);
      expect(controller.filePath, isNull);
    },
  );

  test(
    'write failures preserve the dirty document and prior save state',
    () async {
      final controller = controllerWithShape();
      const path = '/documents/diagram.vsdx';
      establishPath(controller, path);
      final originalBytes = controller.originalBytes;
      controller.setShapeText(controller.singleSelectedId!, 'Still unsaved');

      await expectLater(
        saveEditorDocument(
          controller,
          saveAs: false,
          directFileSave: true,
          writer: (_, _) => throw const FileSystemException('disk full'),
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(controller.isDirty, isTrue);
      expect(controller.filePath, path);
      expect(controller.originalBytes, same(originalBytes));
    },
  );

  test('direct automation saves reject legacy VSD destinations', () async {
    final controller = controllerWithShape();

    await expectLater(
      saveEditorDocumentToPath(controller, '/documents/legacy.vsd'),
      throwsArgumentError,
    );
    expect(controller.isDirty, isTrue);
  });

  test(
    'desktop file writes replace existing bytes without temp debris',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'visio_save_test_',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final target = File('${directory.path}/drawing.vsdx');
      await target.writeAsBytes(<int>[1, 2, 3], flush: true);

      await writeBytesToFile(
        target.path,
        Uint8List.fromList(<int>[9, 8, 7, 6]),
      );

      expect(await target.readAsBytes(), <int>[9, 8, 7, 6]);
      expect(
        await directory
            .list()
            .where((entry) => entry.path != target.path)
            .toList(),
        isEmpty,
      );
    },
  );
}
