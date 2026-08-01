import 'dart:collection';
import 'dart:typed_data';

import '../editor/editor_controller.dart';
import 'document_io.dart';

typedef SaveLocationPicker =
    Future<String?> Function({
      required Uint8List bytes,
      required String suggestedName,
    });

typedef SaveBytesWriter = Future<void> Function(String path, Uint8List bytes);

class DocumentSaveResult {
  const DocumentSaveResult({
    required this.path,
    required this.bytes,
    required this.persistentPath,
  });

  /// User-facing picker result or directly written path.
  final String path;
  final Uint8List bytes;

  /// Reopenable local path, or `null` for browser/mobile document exports.
  final String? persistentPath;
}

final Set<EditorController> _activeSaves = HashSet<EditorController>.identity();

/// Save through the normal UI policy. Desktop documents overwrite their
/// reusable path; new documents, Save As, Web, and mobile use the picker.
/// Concurrent requests for the same controller are ignored.
Future<DocumentSaveResult?> saveEditorDocument(
  EditorController controller, {
  required bool saveAs,
  SaveLocationPicker? picker,
  SaveBytesWriter? writer,
  bool? directFileSave,
}) async {
  if (!_activeSaves.add(controller)) return null;
  try {
    final snapshot = controller.document;
    if (snapshot == null) return null;
    final bytes = controller.exportToBytes();
    final direct = directFileSave ?? supportsDirectFileSave;
    var path = !saveAs && direct ? controller.filePath : null;
    if (path != null && isLegacyVisioBinary(path)) path = null;

    if (path == null) {
      final choose = picker ?? pickSaveLocation;
      path = await choose(
        bytes: bytes,
        suggestedName: controller.fileName ?? 'drawing.vsdx',
      );
      if (path == null) return null;
    } else {
      await (writer ?? writeBytesToFile)(path, bytes);
    }

    final displayName = path.split(RegExp(r'[/\\]')).last;
    controller.markSaved(
      bytes,
      path: direct ? path : null,
      name: displayName,
      savedDocument: snapshot,
      clearPath: !direct,
    );
    return DocumentSaveResult(
      path: path,
      bytes: bytes,
      persistentPath: direct ? path : null,
    );
  } finally {
    _activeSaves.remove(controller);
  }
}

/// Save to an already-authorized local path (Agent bridge / automation). Uses
/// the same snapshot and concurrency guarantees as the interactive pipeline.
Future<DocumentSaveResult?> saveEditorDocumentToPath(
  EditorController controller,
  String path, {
  SaveBytesWriter? writer,
}) async {
  if (isLegacyVisioBinary(path)) {
    throw ArgumentError.value(path, 'path', 'cannot overwrite legacy .vsd');
  }
  if (!_activeSaves.add(controller)) return null;
  try {
    final snapshot = controller.document;
    if (snapshot == null) return null;
    final bytes = controller.exportToBytes();
    await (writer ?? writeBytesToFile)(path, bytes);
    controller.markSaved(bytes, path: path, savedDocument: snapshot);
    return DocumentSaveResult(path: path, bytes: bytes, persistentPath: path);
  } finally {
    _activeSaves.remove(controller);
  }
}
