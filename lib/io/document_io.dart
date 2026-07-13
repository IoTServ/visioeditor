import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// A picked file's bytes plus where it came from.
class PickedDocument {
  const PickedDocument({required this.bytes, this.path, this.name});
  final Uint8List bytes;
  final String? path;
  final String? name;
}

/// Visio drawing extensions the editor can open.
const List<String> kVisioOpenExtensions = <String>[
  'vsdx',
  'vsdm',
  'vstx',
  'vstm',
  'vssx',
  'vssm',
];

/// Show the native open dialog and return the chosen file's bytes, or `null`
/// if the user cancelled.
Future<PickedDocument?> pickVisioFile() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: kVisioOpenExtensions,
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;
  final f = result.files.single;
  final bytes = f.bytes ??
      (f.path != null ? await File(f.path!).readAsBytes() : null);
  if (bytes == null) return null;
  return PickedDocument(bytes: bytes, path: f.path, name: f.name);
}

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

/// Prompt for a save location. Returns the chosen path (ensured to end in
/// `.vsdx`) or `null` if the user cancelled.
Future<String?> pickSaveLocation({String suggestedName = 'drawing.vsdx'}) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Save Visio drawing',
    fileName: suggestedName,
    type: FileType.custom,
    allowedExtensions: <String>['vsdx'],
  );
  if (path == null) return null;
  return path.toLowerCase().endsWith('.vsdx') ? path : '$path.vsdx';
}

Future<void> writeBytesToFile(String path, Uint8List bytes) async {
  await File(path).writeAsBytes(bytes, flush: true);
}

/// Prompt for an export location with a specific [ext] (e.g. `svg`, `png`).
Future<String?> pickExportLocation({
  required String ext,
  required String suggestedName,
}) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Export',
    fileName: suggestedName,
    type: FileType.custom,
    allowedExtensions: <String>[ext],
  );
  if (path == null) return null;
  return path.toLowerCase().endsWith('.$ext') ? path : '$path.$ext';
}

String baseName(String? fileName) {
  final n = fileName ?? 'drawing';
  return n.replaceAll(RegExp(r'\.[^.]*$'), '');
}
