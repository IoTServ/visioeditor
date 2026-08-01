import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:meta/meta.dart';

/// Native save-dialog behavior by platform.
///
/// Web is selected by the conditional export in [save_platform.dart]. Any
/// native operating-system value outside Flutter's supported deployment
/// platforms is treated as HarmonyOS for this application's platform forks.
enum NativeSavePlatform {
  android(pickerPersistsBytes: true),
  ios(pickerPersistsBytes: true),
  linux(pickerPersistsBytes: false),
  macos(pickerPersistsBytes: false),
  windows(pickerPersistsBytes: false),
  harmony(pickerPersistsBytes: true);

  const NativeSavePlatform({required this.pickerPersistsBytes});

  /// Mobile/Harmony pickers persist supplied bytes and do not return a stable
  /// dart:io path. Desktop pickers return a reusable path without writing it.
  final bool pickerPersistsBytes;

  bool get supportsDirectFileSave => !pickerPersistsBytes;
}

NativeSavePlatform nativeSavePlatformForOperatingSystem(
  String operatingSystem,
) {
  return switch (operatingSystem.trim().toLowerCase()) {
    'android' => NativeSavePlatform.android,
    'ios' => NativeSavePlatform.ios,
    'linux' => NativeSavePlatform.linux,
    'macos' => NativeSavePlatform.macos,
    'windows' => NativeSavePlatform.windows,
    _ => NativeSavePlatform.harmony,
  };
}

NativeSavePlatform get _nativeSavePlatform =>
    nativeSavePlatformForOperatingSystem(Platform.operatingSystem);

bool get supportsDirectFileSave => _nativeSavePlatform.supportsDirectFileSave;

Future<String?> saveBytesWithPicker({
  required Uint8List bytes,
  required String fileName,
  required String dialogTitle,
  required List<String> allowedExtensions,
  required String Function(String path) ensureExtension,
}) async {
  final platform = _nativeSavePlatform;
  // Popup menus / sheets on iPad must finish dismissing before another
  // UIViewController can present the UIDocumentPicker.
  if (platform == NativeSavePlatform.ios) {
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  return saveBytesWithPickerForPlatform(
    platform: platform,
    bytes: bytes,
    fileName: fileName,
    dialogTitle: dialogTitle,
    allowedExtensions: allowedExtensions,
    ensureExtension: ensureExtension,
  );
}

/// Platform-explicit core used by the runtime wrapper and the full platform
/// matrix regression tests.
@visibleForTesting
Future<String?> saveBytesWithPickerForPlatform({
  required NativeSavePlatform platform,
  required Uint8List bytes,
  required String fileName,
  required String dialogTitle,
  required List<String> allowedExtensions,
  required String Function(String path) ensureExtension,
}) async {
  final picked = await FilePicker.platform.saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: allowedExtensions,
    // Picker-backed platforms (Android/iOS/Harmony) persist these bytes. The
    // desktop adapters return a path instead; macOS explicitly throws if bytes
    // are supplied, so the application writes that path after the dialog.
    bytes: platform.pickerPersistsBytes ? bytes : null,
  );
  if (picked == null) return null;

  // UIDocumentPicker / Android SAF / Harmony picker already persisted [bytes].
  // Their returned location is not assumed to be a reusable dart:io path, so
  // do not append an extension or attempt a second write. The proposed
  // [fileName] already has the extension.
  if (!platform.supportsDirectFileSave) return picked;

  final path = ensureExtension(picked);
  await writeBytesToFile(path, bytes);
  return path;
}

/// Replace [path] through a same-directory temporary file. If the platform's
/// file grant only permits access to the selected file (rather than sibling
/// temporary files), fall back to a direct flushed write.
Future<void> writeBytesToFile(String path, Uint8List bytes) async {
  try {
    await _replaceBytesAtomically(path, bytes);
  } on FileSystemException {
    await File(path).writeAsBytes(bytes, flush: true);
  }
}

/// If installing the new file fails, the previous file is restored from its
/// backup before the exception reaches the direct-write fallback above.
Future<void> _replaceBytesAtomically(String path, Uint8List bytes) async {
  final target = File(path);
  final suffix = '${pid}_${DateTime.now().microsecondsSinceEpoch}';
  final temporary = File('$path.save_$suffix.tmp');
  File? backup;
  try {
    await temporary.writeAsBytes(bytes, flush: true);
    if (await target.exists()) {
      backup = File('$path.save_$suffix.bak');
      await target.rename(backup.path);
    }
    try {
      await temporary.rename(path);
    } catch (_) {
      if (backup != null && await backup.exists()) {
        await backup.rename(path);
      }
      rethrow;
    }
    if (backup != null && await backup.exists()) {
      try {
        await backup.delete();
      } on FileSystemException {
        // The new target is safely installed; stale backup cleanup should not
        // turn a successful save into an error.
      }
    }
  } finally {
    if (await temporary.exists()) await temporary.delete();
    if (backup != null && await backup.exists() && !await target.exists()) {
      await backup.rename(path);
    }
  }
}
