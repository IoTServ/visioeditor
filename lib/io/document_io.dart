import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'save_platform.dart' as save_platform;

/// A picked file's bytes plus where it came from.
class PickedDocument {
  const PickedDocument({required this.bytes, this.path, this.name});
  final Uint8List bytes;
  final String? path;
  final String? name;
}

/// Visio drawing extensions the editor can open.
///
/// OPC formats (`.vsdx` …) round-trip in place. Legacy binary `.vsd` is
/// imported into the editable model and saved as `.vsdx`.
const List<String> kVisioOpenExtensions = <String>[
  'vsd',
  'vsdx',
  'vsdm',
  'vstx',
  'vstm',
  'vssx',
  'vssm',
];

/// Extensions registered with the OS for "Open With" / file association.
const List<String> kVisioAssociatedExtensions = <String>[
  ...kVisioOpenExtensions,
];

/// All editable drawing extensions accepted by the application.
const List<String> kDiagramOpenExtensions = <String>[
  ...kVisioOpenExtensions,
  'drawio',
];

/// Extensions registered for app launch / Open With handling.
const List<String> kDiagramAssociatedExtensions = <String>[
  ...kDiagramOpenExtensions,
];

const MethodChannel _androidFileChannel = MethodChannel('visioeditor/files');

/// Show the native open dialog and return the chosen file's bytes, or `null`
/// if the user cancelled.
Future<PickedDocument?> pickDiagramFile() async {
  // Android's file_picker adapter converts extensions through MimeTypeMap.
  // Visio types are absent on many Android versions, which makes a custom
  // filter fail before the system picker opens. The native bridge supplies
  // the canonical MIME types plus generic OPC fallbacks and returns a cached,
  // extension-preserving path.
  if (!kIsWeb && Platform.isAndroid) {
    final path = await _androidFileChannel.invokeMethod<String>('pickVisioFile');
    if (path == null || !hasDiagramExtension(path)) return null;
    return readDroppedFile(path);
  }
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: kDiagramOpenExtensions,
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;
  final f = result.files.single;
  final bytes = f.bytes ??
      (f.path != null ? await File(f.path!).readAsBytes() : null);
  if (bytes == null) return null;
  return PickedDocument(bytes: bytes, path: f.path, name: f.name);
}

/// Backwards-compatible Visio-named entry point used by older integrations.
Future<PickedDocument?> pickVisioFile() => pickDiagramFile();

/// Raster-image extensions the editor can embed via "Insert Image".
const List<String> kImageInsertExtensions = <String>[
  'png',
  'jpg',
  'jpeg',
  'gif',
  'bmp',
  'webp',
];

/// A picked image's bytes plus its (lower-case, dot-less) file extension.
class PickedImage {
  const PickedImage({required this.bytes, required this.extension, this.name});
  final Uint8List bytes;
  final String extension;
  final String? name;
}

/// Show the native open dialog filtered to raster images and return the chosen
/// file, or `null` if the user cancelled.
Future<PickedImage?> pickImageFile() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: kImageInsertExtensions,
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;
  final f = result.files.single;
  final bytes = f.bytes ??
      (f.path != null ? await File(f.path!).readAsBytes() : null);
  if (bytes == null) return null;
  final ext = (f.extension ?? _extensionOf(f.name)).toLowerCase();
  return PickedImage(bytes: bytes, extension: ext, name: f.name);
}

String _extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1);
}

/// Read a dropped file path into a [PickedDocument].
Future<PickedDocument> readDroppedFile(String path) async {
  final file = File(path);
  final bytes = await file.readAsBytes();
  final name = path.split(Platform.pathSeparator).last;
  return PickedDocument(bytes: bytes, path: path, name: name);
}

bool hasVisioExtension(String path) {
  final lower = path.toLowerCase();
  return kVisioOpenExtensions.any((e) => lower.endsWith('.$e'));
}

bool hasDiagramExtension(String path) {
  final lower = path.toLowerCase();
  return kDiagramOpenExtensions.any((e) => lower.endsWith('.$e'));
}

/// `true` when [path] matches an OS-associated Visio extension (OPC or `.vsd`).
bool hasVisioAssociatedExtension(String path) {
  final lower = path.toLowerCase();
  return kVisioAssociatedExtensions.any((e) => lower.endsWith('.$e'));
}

bool hasDiagramAssociatedExtension(String path) {
  final lower = path.toLowerCase();
  return kDiagramAssociatedExtensions.any((e) => lower.endsWith('.$e'));
}

/// Visio file paths supplied by desktop runners at process startup.
///
/// Windows passes shell association paths as command-line arguments and the
/// Linux desktop entry uses `%f`. Ignore Flutter/tooling flags and unrelated
/// arguments rather than attempting to read them as documents.
List<String> visioPathsFromArguments(Iterable<String> arguments) =>
    arguments.where(hasVisioAssociatedExtension).toList(growable: false);

/// Editable diagram paths supplied by desktop runners at startup.
List<String> diagramPathsFromArguments(Iterable<String> arguments) =>
    arguments.where(hasDiagramAssociatedExtension).toList(growable: false);

/// Legacy Visio 2003–2010 binary drawing (OLE2). Importable; Save As `.vsdx`.
bool isLegacyVisioBinary(String path) {
  final lower = path.toLowerCase();
  // Exact `.vsd` only — do not match `.vsdx` / `.vsdm`.
  return lower.endsWith('.vsd') &&
      !lower.endsWith('.vsdx') &&
      !lower.endsWith('.vsdm');
}

/// `true` when [path] looks like a raster image the editor can embed.
bool hasImageExtension(String path) {
  final lower = path.toLowerCase();
  return kImageInsertExtensions.any((e) => lower.endsWith('.$e'));
}

/// Lower-case, dot-less file extension of [path], or `''`.
String extensionOfPath(String path) {
  final name = path.split(RegExp(r'[/\\]')).last;
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

/// Whether a returned picker path can be reopened and overwritten directly.
/// Browser downloads, UIDocumentPicker, and Android SAF destinations cannot.
bool get supportsDirectFileSave => save_platform.supportsDirectFileSave;

/// Prompt for a save location and persist [bytes] as `.vsdx` or `.drawio`.
///
/// Returns the chosen path, or `null` if cancelled.
///
/// On iOS/Android, [FilePicker.saveFile] **requires** [bytes] and writes them
/// itself (UIDocumentPicker export / SAF). On desktop it only returns a path,
/// so this helper writes the file afterwards.
Future<String?> pickSaveLocation({
  required Uint8List bytes,
  String suggestedName = 'drawing.vsdx',
}) async {
  var suggested = suggestedName;
  final isDrawio = suggested.toLowerCase().endsWith('.drawio');
  if (isDrawio) {
    return _saveBytesWithPicker(
      bytes: bytes,
      fileName: suggested,
      dialogTitle: 'Save draw.io drawing (.drawio)',
      allowedExtensions: const <String>['drawio'],
      ensureExtension: (path) =>
          path.toLowerCase().endsWith('.drawio') ? path : '$path.drawio',
    );
  }
  if (isLegacyVisioBinary(suggested)) {
    suggested = suggested.replaceFirst(
      RegExp(r'\.vsd$', caseSensitive: false),
      '.vsdx',
    );
  } else if (!suggested.toLowerCase().endsWith('.vsdx')) {
    suggested = '$suggested.vsdx';
  }
  return _saveBytesWithPicker(
    bytes: bytes,
    fileName: suggested,
    dialogTitle: 'Save Visio drawing (.vsdx)',
    allowedExtensions: const <String>['vsdx'],
    ensureExtension: (path) =>
        path.toLowerCase().endsWith('.vsdx') ? path : '$path.vsdx',
  );
}

Future<void> writeBytesToFile(String path, Uint8List bytes) =>
    save_platform.writeBytesToFile(path, bytes);

/// Prompt for an export location and persist [bytes] with extension [ext].
///
/// Returns the chosen path, or `null` if cancelled. See [pickSaveLocation] for
/// why [bytes] must be supplied on iOS/Android.
Future<String?> pickExportLocation({
  required String ext,
  required String suggestedName,
  required Uint8List bytes,
}) {
  return _saveBytesWithPicker(
    bytes: bytes,
    fileName: suggestedName,
    dialogTitle: 'Export',
    allowedExtensions: <String>[ext],
    ensureExtension: (path) =>
        path.toLowerCase().endsWith('.$ext') ? path : '$path.$ext',
  );
}

/// Shared save/export dialog, implemented per platform.
Future<String?> _saveBytesWithPicker({
  required Uint8List bytes,
  required String fileName,
  required String dialogTitle,
  required List<String> allowedExtensions,
  required String Function(String path) ensureExtension,
}) async {
  return save_platform.saveBytesWithPicker(
    bytes: bytes,
    dialogTitle: dialogTitle,
    fileName: fileName,
    allowedExtensions: allowedExtensions,
    ensureExtension: ensureExtension,
  );
}

String baseName(String? fileName) {
  final n = fileName ?? 'drawing';
  return n.replaceAll(RegExp(r'\.[^.]*$'), '');
}
