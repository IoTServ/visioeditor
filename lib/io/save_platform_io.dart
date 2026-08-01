import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

bool get supportsDirectFileSave => !Platform.isIOS && !Platform.isAndroid;

Future<String?> saveBytesWithPicker({
  required Uint8List bytes,
  required String fileName,
  required String dialogTitle,
  required List<String> allowedExtensions,
  required String Function(String path) ensureExtension,
}) async {
  // Popup menus / sheets on iPad must finish dismissing before another
  // UIViewController can present the UIDocumentPicker.
  if (Platform.isIOS) {
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  final picked = await FilePicker.platform.saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: allowedExtensions,
    // file_picker requires bytes on iOS/Android, but its macOS adapter throws
    // when bytes are supplied. Desktop pickers return a path and this adapter
    // persists the bytes after the dialog completes.
    bytes: supportsDirectFileSave ? null : bytes,
  );
  if (picked == null) return null;

  // UIDocumentPicker / Android SAF already persisted [bytes]. Their returned
  // location is not a reusable dart:io path, so do not append an extension or
  // attempt a second write. The proposed [fileName] already has the extension.
  if (!supportsDirectFileSave) return picked;

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
