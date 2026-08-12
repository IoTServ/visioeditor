import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/io/document_io.dart';

const _mimeByExtension = <String, String>{
  'vsd': 'application/vnd.visio',
  'vsdx': 'application/vnd.ms-visio.drawing',
  'vsdm': 'application/vnd.ms-visio.drawing.macroEnabled.12',
  'vstx': 'application/vnd.ms-visio.template',
  'vstm': 'application/vnd.ms-visio.template.macroEnabled.12',
  'vssx': 'application/vnd.ms-visio.stencil',
  'vssm': 'application/vnd.ms-visio.stencil.macroEnabled.12',
};

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('platform association declarations cover every open extension', () {
    expect(_mimeByExtension.keys, orderedEquals(kVisioOpenExtensions));

    final android = _read('android/app/src/main/AndroidManifest.xml');
    final ios = _read('ios/Runner/Info.plist');
    final macos = _read('macos/Runner/Info.plist');
    final linuxMime = _read('linux/packaging/visioeditor-mime.xml');
    final linuxDesktop = _read('linux/packaging/visioeditor.desktop');
    final windows = _read('windows/packaging/visioeditor-file-association.reg');

    for (final entry in _mimeByExtension.entries) {
      expect(android, contains('android:pathPattern=".*\\\\.${entry.key}"'));
      expect(android.toLowerCase(), contains(entry.value.toLowerCase()));
      expect(ios, contains('<string>${entry.key}</string>'));
      expect(ios.toLowerCase(), contains(entry.value.toLowerCase()));
      expect(macos, contains('<string>${entry.key}</string>'));
      expect(macos.toLowerCase(), contains(entry.value.toLowerCase()));
      expect(linuxMime, contains('glob pattern="*.${entry.key}"'));
      expect(linuxMime.toLowerCase(), contains(entry.value.toLowerCase()));
      expect(linuxDesktop.toLowerCase(), contains(entry.value.toLowerCase()));
      expect(windows, contains('Classes\\.${entry.key}]'));
      expect(windows.toLowerCase(), contains(entry.value.toLowerCase()));
    }
  });

  test('platform association declarations include draw.io', () {
    final android = _read('android/app/src/main/AndroidManifest.xml');
    final ios = _read('ios/Runner/Info.plist');
    final macos = _read('macos/Runner/Info.plist');
    final linuxMime = _read('linux/packaging/visioeditor-mime.xml');
    final linuxDesktop = _read('linux/packaging/visioeditor.desktop');
    final windows = _read('windows/packaging/visioeditor-file-association.reg');

    for (final declaration in <String>[
      android,
      ios,
      macos,
      linuxMime,
      linuxDesktop,
      windows,
    ]) {
      final lower = declaration.toLowerCase();
      expect(lower.contains('drawio') || lower.contains('draw.io'), isTrue);
    }
    expect(android, contains('android:pathPattern=".*\\\\.drawio"'));
    expect(linuxMime, contains('glob pattern="*.drawio"'));
    expect(windows, contains('Classes\\.drawio]'));
    expect(android, contains('application/vnd.jgraph.mxfile'));
    expect(linuxDesktop, contains('application/vnd.jgraph.mxfile'));
    expect(ios, contains('<string>com.jgraph.drawio</string>'));
    expect(macos, contains('<string>com.jgraph.drawio</string>'));
    expect(ios, contains('<key>UTExportedTypeDeclarations</key>'));
    expect(macos, contains('<key>UTExportedTypeDeclarations</key>'));
  });

  test('associated platform runners deliver opened files to Dart', () {
    final android = _read(
      'android/app/src/main/kotlin/cloud/iothub/visioeditor/MainActivity.kt',
    );
    final ios = _read('ios/Runner/AppDelegate.swift');
    final macos = _read('macos/Runner/AppDelegate.swift');
    final linux = _read('linux/runner/my_application.cc');
    final windows = _read('windows/runner/main.cpp');

    expect(android, contains('Intent.ACTION_VIEW'));
    expect(android, contains('Intent.ACTION_OPEN_DOCUMENT'));
    expect(android, contains('"pickVisioFile" -> startVisioPicker(result)'));
    expect(android, contains('openInputStream(uri)'));
    expect(android, contains('channel.invokeMethod("openFiles", paths)'));
    expect(
      ios,
      contains('channel.invokeMethod("openFiles", arguments: paths)'),
    );
    expect(
      macos,
      contains('channel.invokeMethod("openFiles", arguments: paths)'),
    );
    expect(linux, contains('fl_dart_project_set_dart_entrypoint_arguments'));
    expect(windows, contains('project.set_dart_entrypoint_arguments'));
  });

  test('Windows MSIX Store identity matches Partner Center', () {
    final pubspec = _read('pubspec.yaml');
    final identity = _read('store/microsoft-store/product-identity.txt');
    final runnerRc = _read('windows/runner/Runner.rc');
    final mainCpp = _read('windows/runner/main.cpp');

    expect(pubspec, contains('msix_config:'));
    expect(pubspec, contains('display_name: Flowcharts Editor'));
    expect(
      pubspec,
      contains('identity_name: 38916OpenIoTHubCloud.FlowchartsEditor'),
    );
    expect(
      pubspec,
      contains('publisher: CN=5F64CEA2-463E-41A3-AE89-6979242A61DF'),
    );
    expect(pubspec, contains('publisher_display_name: OpenIoTHub Cloud'));
    expect(pubspec, contains('store: true'));
    expect(pubspec, contains('.vsdx'));
    expect(pubspec, contains('.vsd'));
    expect(pubspec, contains('.drawio'));

    expect(
      identity,
      contains('38916OpenIoTHubCloud.FlowchartsEditor_n13avf7sg128e'),
    );
    expect(identity, contains('Store ID=9P358XB93V5L'));

    expect(runnerRc, contains('Flowcharts Editor'));
    expect(mainCpp, contains('Flowcharts Editor'));
  });
}
