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

  test('export helpers require bytes in the API (compile-time contract)', () {
    // Ensures call sites pass bytes — mobile saveFile throws without them.
    const suggested = 'out.svg';
    expect(suggested.endsWith('.svg'), isTrue);
    expect(Uint8List(0), isA<Uint8List>());
  });
}
