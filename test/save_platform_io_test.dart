import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/io/document_io.dart';
import 'package:visioeditor/io/save_platform_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('operating systems resolve to official platforms or Harmony', () {
    const official = <String, NativeSavePlatform>{
      'android': NativeSavePlatform.android,
      'ios': NativeSavePlatform.ios,
      'linux': NativeSavePlatform.linux,
      'macos': NativeSavePlatform.macos,
      'windows': NativeSavePlatform.windows,
    };
    for (final entry in official.entries) {
      expect(nativeSavePlatformForOperatingSystem(entry.key), entry.value);
      expect(
        nativeSavePlatformForOperatingSystem(entry.key.toUpperCase()),
        entry.value,
      );
    }
    for (final operatingSystem in const <String>[
      'ohos',
      'harmony',
      'harmonyos',
      'fuchsia',
      'vendor-platform',
      '',
    ]) {
      expect(
        nativeSavePlatformForOperatingSystem(operatingSystem),
        NativeSavePlatform.harmony,
      );
    }
  });

  test('every native platform follows its picker byte contract', () async {
    FilePicker? previousPicker;
    try {
      previousPicker = FilePicker.platform;
    } catch (_) {
      // Some test runners do not register a default platform implementation.
    }
    final directory = await Directory.systemTemp.createTemp(
      'visio_platform_matrix_test_',
    );
    addTearDown(() async {
      if (previousPicker != null) FilePicker.platform = previousPicker;
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    for (final platform in NativeSavePlatform.values) {
      final selectedPath = '${directory.path}/${platform.name}_diagram';
      final picker = _PersistingRecordingPicker(selectedPath);
      FilePicker.platform = picker;
      final bytes = Uint8List.fromList(<int>[
        platform.index,
        platform.index + 1,
      ]);

      final result = await saveBytesWithPickerForPlatform(
        platform: platform,
        bytes: bytes,
        fileName: 'diagram.vsdx',
        dialogTitle: 'Save',
        allowedExtensions: const <String>['vsdx'],
        ensureExtension: (path) => '$path.vsdx',
      );

      if (platform.pickerPersistsBytes) {
        expect(picker.receivedBytes, same(bytes), reason: platform.name);
        expect(result, selectedPath, reason: platform.name);
      } else {
        expect(picker.receivedBytes, isNull, reason: platform.name);
        expect(result, '$selectedPath.vsdx', reason: platform.name);
      }
      expect(await File(result!).readAsBytes(), bytes, reason: platform.name);
    }
  });

  test('file_picker rejects bytes in the macOS save dialog', () async {
    await expectLater(
      FilePickerMacOS().saveFile(bytes: Uint8List.fromList(<int>[1])),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('Save As picker retains every editable document extension', () async {
    FilePicker? previousPicker;
    try {
      previousPicker = FilePicker.platform;
    } catch (_) {
      // Some test runners do not register a default platform implementation.
    }
    final directory = await Directory.systemTemp.createTemp(
      'visio_save_family_test_',
    );
    addTearDown(() async {
      if (previousPicker != null) FilePicker.platform = previousPicker;
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    for (final extension in const <String>[
      'vsdx',
      'vsdm',
      'vstx',
      'vstm',
      'vssx',
      'vssm',
      'drawio',
    ]) {
      final picker = _PersistingRecordingPicker(
        '${directory.path}/saved_$extension',
      );
      FilePicker.platform = picker;
      final bytes = Uint8List.fromList(<int>[1, extension.length]);

      final result = await pickSaveLocation(
        bytes: bytes,
        suggestedName: 'diagram.$extension',
      );

      expect(picker.receivedFileName, 'diagram.$extension');
      expect(picker.receivedExtensions, <String>[extension]);
      expect(result, '${directory.path}/saved_$extension.$extension');
      expect(await File(result!).readAsBytes(), bytes);
    }
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

class _PersistingRecordingPicker extends FilePicker {
  _PersistingRecordingPicker(this.resultPath);

  final String resultPath;
  Uint8List? receivedBytes;
  String? receivedFileName;
  List<String>? receivedExtensions;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    receivedBytes = bytes;
    receivedFileName = fileName;
    receivedExtensions = allowedExtensions;
    if (bytes != null) {
      await File(resultPath).writeAsBytes(bytes, flush: true);
    }
    return resultPath;
  }
}
