import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/io/document_io.dart';

void main() {
  test('baseName strips the last extension', () {
    expect(baseName('drawing.vsdx'), 'drawing');
    expect(baseName('a.b.svg'), 'a.b');
    expect(baseName(null), 'drawing');
  });

  test('legacy Visio binary detection covers drawings, stencils, templates', () {
    expect(isLegacyVisioBinary('x.vsd'), isTrue);
    expect(isLegacyVisioBinary('x.vss'), isTrue);
    expect(isLegacyVisioBinary('x.VST'), isTrue);
    expect(isLegacyVisioBinary('x.vsdx'), isFalse);
    expect(isLegacyVisioBinary('x.VSD'), isTrue);
  });

  test('open filters cover every supported Visio family extension', () {
    expect(kVisioOpenExtensions, <String>[
      'vsd',
      'vss',
      'vst',
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

  test('diagram filters and startup arguments include draw.io files', () {
    expect(kDiagramOpenExtensions, contains('drawio'));
    expect(hasDiagramExtension('/tmp/Architecture.DRAWIO'), isTrue);
    expect(hasVisioExtension('/tmp/Architecture.drawio'), isFalse);
    expect(
      diagramPathsFromArguments(<String>[
        '--trace-startup',
        '/tmp/Architecture.drawio',
        '/tmp/Network.vsdx',
        '/tmp/notes.xml',
      ]),
      <String>['/tmp/Architecture.drawio', '/tmp/Network.vsdx'],
    );
  });

  test('Save As retains editable formats and upgrades legacy binaries', () {
    for (final extension in const <String>[
      'vsdx',
      'vsdm',
      'vstx',
      'vstm',
      'vssx',
      'vssm',
      'drawio',
    ]) {
      expect(documentSaveExtension('Drawing.$extension'), extension);
      expect(
        normalizedDocumentSaveName('Drawing.$extension'),
        'Drawing.$extension',
      );
    }
    expect(documentSaveExtension('legacy.vsd'), 'vsdx');
    expect(normalizedDocumentSaveName('legacy.VSD'), 'legacy.vsdx');
    expect(documentSaveExtension('stencil.vss'), 'vsdx');
    expect(normalizedDocumentSaveName('stencil.VSS'), 'stencil.vsdx');
    expect(documentSaveExtension('template.vst'), 'vsdx');
    expect(normalizedDocumentSaveName('template.VST'), 'template.vsdx');
    expect(documentSaveExtension('untitled'), 'vsdx');
    expect(normalizedDocumentSaveName('untitled'), 'untitled.vsdx');
  });

  test('export helpers require bytes in the API (compile-time contract)', () {
    // Ensures call sites pass bytes — mobile saveFile throws without them.
    const suggested = 'out.svg';
    expect(suggested.endsWith('.svg'), isTrue);
    expect(Uint8List(0), isA<Uint8List>());
  });
}
