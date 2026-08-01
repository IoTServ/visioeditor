// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:typed_data';

bool get supportsDirectFileSave => false;

Future<String?> saveBytesWithPicker({
  required Uint8List bytes,
  required String fileName,
  required String dialogTitle,
  required List<String> allowedExtensions,
  required String Function(String path) ensureExtension,
}) async {
  // file_picker 8.x does not implement saveFile on Web. Use a browser download
  // so Save, Save As, and every export remain functional in the web build.
  final name = ensureExtension(fileName);
  final blob = html.Blob(<Object>[bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  try {
    html.AnchorElement(href: url)
      ..download = name
      ..click();
    // Let the browser consume the synthetic click before releasing its Blob.
    await Future<void>.delayed(Duration.zero);
  } finally {
    html.Url.revokeObjectUrl(url);
  }
  return name;
}

Future<void> writeBytesToFile(String path, Uint8List bytes) {
  throw UnsupportedError('Direct file writes are unavailable on Web');
}
