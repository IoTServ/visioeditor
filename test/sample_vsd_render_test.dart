import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/io/image_export.dart';
import 'package:vsdx/vsdx.dart';

Future<({int black, int colored, int total})> _hist(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  final bd = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = bd!.buffer.asUint8List();
  var black = 0, colored = 0, opaque = 0;
  for (var i = 0; i + 3 < bytes.length; i += 4) {
    final r = bytes[i], g = bytes[i + 1], b = bytes[i + 2], a = bytes[i + 3];
    if (a < 10) continue;
    opaque++;
    if (r < 40 && g < 40 && b < 40) {
      black++;
    } else {
      colored++;
    }
  }
  return (black: black, colored: colored, total: opaque);
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
}
