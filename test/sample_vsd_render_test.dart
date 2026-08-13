import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/io/image_export.dart';
import 'package:vsdx/vsdx.dart';

Future<({int black, int colored, int ink, int total})> _hist(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  final bd = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = bd!.buffer.asUint8List();
  var black = 0, colored = 0, ink = 0, opaque = 0;
  for (var i = 0; i + 3 < bytes.length; i += 4) {
    final r = bytes[i], g = bytes[i + 1], b = bytes[i + 2], a = bytes[i + 3];
    if (a < 10) continue;
    opaque++;
    if (r < 40 && g < 40 && b < 40) {
      black++;
    } else {
      colored++;
    }
    if (r < 230 || g < 230 || b < 230) ink++;
  }
  return (black: black, colored: colored, ink: ink, total: opaque);
}

Uint8List _withLegacyVisioVersion(Uint8List source, int version) {
  final bytes = Uint8List.fromList(source);
  const magic = 'Visio (TM) Drawing\r\n\x00';
  for (var i = 0; i + magic.length <= bytes.length; i++) {
    var match = true;
    for (var j = 0; j < magic.length; j++) {
      if (bytes[i + j] != magic.codeUnitAt(j)) {
        match = false;
        break;
      }
    }
    if (match) {
      bytes[i + 0x1a] = version;
      return bytes;
    }
  }
  throw StateError('VisioDocument header not found in CFB');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sample.vsd evenodd frame leaves map content visible', () async {
    final path = 'assets/examples/sample.vsd';
    if (!File(path).existsSync()) {
      // Optional local fixture — skip when not bundled.
      return;
    }
    final r = parseVisio(File(path).readAsBytesSync());
    final page = r.document.pages.first;
    final frame = page.shapes.firstWhere((s) => s.id == 33);
    expect(frame.geometries.length, 2);
    expect(frame.geometries.every((g) => !g.noFill), isTrue,
        reason: 'page matte uses two filled geoms + evenodd hole');

    final png = await renderPageToPng(
      page,
      theme: r.document.theme,
      images: r.document.images,
      pxPerInch: 72,
    );
    expect(png, isNotNull);
    final h = await _hist(png!);
    // Intentional black matte is ~44% of the page; solid-fill bug was >90%.
    expect(h.black / h.total, lessThan(0.55));
    expect(h.colored / h.total, greaterThan(0.40),
        reason: 'buildings / sky / frames must remain visible through the hole');

    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg.contains('fill-rule="evenodd"'), isTrue);
    expect(RegExp(r'fill-rule="evenodd"').allMatches(svg).length,
        greaterThanOrEqualTo(3));
  });

  test('legacy Visio versions 1–4 parse, paint, and reopen as VSDX', () async {
    final fixture = File(
      'third_party/libvisio/src/test/data/Visio5PlanWithDimensions.vsd',
    );
    if (!fixture.existsSync()) return;
    final source = fixture.readAsBytesSync();

    for (var version = 1; version <= 4; version++) {
      final imported = parseVisio(_withLegacyVisioVersion(source, version));
      final page = imported.document.pages.first;
      expect(page.shapes, isNotEmpty, reason: 'version $version model');

      final png = await renderPageToPng(
        page,
        theme: imported.document.theme,
        images: imported.document.images,
        pxPerInch: 72,
      );
      expect(png, isNotNull, reason: 'version $version Canvas output');
      expect(
        (await _hist(png!)).ink,
        greaterThan(1000),
        reason: 'version $version must paint visible geometry and text',
      );

      final reopened = const DocumentParser().parse(imported.originalBytes);
      expect(reopened.pages, hasLength(imported.document.pages.length));
      expect(
        reopened.pages.first.shapes.length,
        imported.document.pages.first.shapes.length,
        reason: 'version $version VSD → VSDX reopen',
      );
    }
  });
}
