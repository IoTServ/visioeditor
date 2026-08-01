import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/io/document_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('file_picker rejects bytes in the macOS save dialog', () async {
    await expectLater(
      FilePickerMacOS().saveFile(bytes: Uint8List.fromList(<int>[1])),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test(
    'desktop Save As and exports omit picker bytes then write paths',
    () async {
      FilePicker? previousPicker;
      try {
        previousPicker = FilePicker.platform;
      } catch (_) {
        // Some test runners do not register a default platform implementation.
      }

      final directory = await Directory.systemTemp.createTemp(
        'visio_picker_save_test_',
      );
      final selectedSavePath = '${directory.path}/diagram';
      final selectedExportPath = '${directory.path}/preview';
      final selectedPaths = <String>[selectedSavePath, selectedExportPath];
      final calls = <MethodCall>[];
      const channel = MethodChannel('miguelruivo.flutter.plugins.filepicker');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return selectedPaths.removeAt(0);
          });
      FilePicker.platform = FilePickerMacOS();
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        if (previousPicker != null) FilePicker.platform = previousPicker;
        if (await directory.exists()) await directory.delete(recursive: true);
      });

      final saveBytes = Uint8List.fromList(<int>[9, 8, 7]);
      final exportBytes = Uint8List.fromList(<int>[6, 5, 4]);
      final saveResult = await pickSaveLocation(
        bytes: saveBytes,
        suggestedName: 'diagram.vsdx',
      );
      final exportResult = await pickExportLocation(
        ext: 'pdf',
        suggestedName: 'preview.pdf',
        bytes: exportBytes,
      );

      expect(calls, hasLength(2));
      expect(calls.map((call) => call.method), everyElement('saveFile'));
      expect(
        calls.map(
          (call) =>
              (call.arguments as Map<dynamic, dynamic>).containsKey('bytes'),
        ),
        everyElement(isFalse),
      );
      expect(saveResult, '$selectedSavePath.vsdx');
      expect(exportResult, '$selectedExportPath.pdf');
      expect(await File(saveResult!).readAsBytes(), saveBytes);
      expect(await File(exportResult!).readAsBytes(), exportBytes);
    },
  );
}
