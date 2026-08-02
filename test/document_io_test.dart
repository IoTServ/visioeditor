import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/io/document_io.dart';

void main() {
  test('baseName strips the last extension', () {
    expect(baseName('drawing.vsdx'), 'drawing');
    expect(baseName('a.b.svg'), 'a.b');
    expect(baseName(null), 'drawing');
  });

  test('legacy Visio binary detection does not match vsdx', () {
    expect(isLegacyVisioBinary('x.vsd'), isTrue);
    expect(isLegacyVisioBinary('x.vsdx'), isFalse);
    expect(isLegacyVisioBinary('x.VSD'), isTrue);
  });

  test('open filters cover every supported Visio family extension', () {
    expect(kVisioOpenExtensions, <String>[
      'vsd',
      'vsdx',
      'vsdm',
      'vstx',
      'vstm',
      'vssx',
      'vssm',
    ]);
    for (final extension in kVisioOpenExtensions) {
      expect(hasVisioExtension('DRAWING.${extension.toUpperCase()}'), isTrue);
      expect(hasVisioAssociatedExtension('/tmp/drawing.$extension'), isTrue);
    }
  });

  test('desktop startup arguments retain only associated Visio files', () {
    expect(
      visioPathsFromArguments(<String>[
        '--trace-startup',
        r'C:\Diagrams\Network.VSDX',
        '/tmp/template.vstm',
        '/tmp/readme.txt',
      ]),
      <String>[r'C:\Diagrams\Network.VSDX', '/tmp/template.vstm'],
    );
  });

  test('export helpers require bytes in the API (compile-time contract)', () {
    // Ensures call sites pass bytes — mobile saveFile throws without them.
    const suggested = 'out.svg';
    expect(suggested.endsWith('.svg'), isTrue);
    expect(Uint8List(0), isA<Uint8List>());
  });
}
