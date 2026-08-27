import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

import '../support/libvisio_oracle.dart';

Uint8List _encodedFixture(String name) {
  final encoded = File(
    'test/fixtures/vsd/external/$name',
  ).readAsStringSync();
  return base64.decode(encoded.replaceAll(RegExp(r'\s'), ''));
}

Uint8List _stencilFixture() =>
    _encodedFixture('Nortel-vpn-gateway-3050-front.vss.b64');

Uint8List _opcStencilFixture() =>
    File('test/fixtures/test_master.vsdx').readAsBytesSync();

void main() {
  test('legacy VSS exposes master pages and survives VSDX round-trip', () {
    final imported = parseVisio(
      _stencilFixture(),
      sourceName: 'Nortel-vpn-gateway-3050-front.vss',
    );

    expect(imported.importedFromVsd, isTrue);
    expect(imported.document.pages, hasLength(1));
    final page = imported.document.pages.single;
    expect(page.name, 'VG 3050');
    expect(page.widthInches, closeTo(1.725, 1e-9));
    expect(page.heightInches, closeTo(0.172, 1e-9));
    expect(page.shapes, hasLength(1));
    expect(page.shapes.single.imagePartName, isNotNull);

    final svg = VsdxToSvgSerializer().serializePage(
      page,
      images: imported.document.images,
    );
    expect(
        svg, anyOf(contains('<path'), contains('<image'), contains('<rect')));

    final reopened = const DocumentParser().parse(imported.originalBytes);
    expect(reopened.pages, hasLength(1));
    expect(reopened.pages.single.name, page.name);
    expect(reopened.pages.single.widthInches, closeTo(page.widthInches, 1e-9));
    expect(
      reopened.pages.single.heightInches,
      closeTo(page.heightInches, 1e-9),
    );
    expect(reopened.pages.single.shapes, hasLength(1));
    expect(reopened.pages.single.shapes.single.imagePartName, isNotNull);
    final reopenedSvg = VsdxToSvgSerializer().serializePage(
      reopened.pages.single,
      images: reopened.images,
    );
    expect(
      reopenedSvg,
      anyOf(contains('<path'), contains('<image'), contains('<rect')),
    );
  });

  test('OPC VSSX exposes every master page and survives VSDX round-trip', () {
    final imported = parseVisio(
      _opcStencilFixture(),
      sourceName: 'test_master.vssx',
    );

    expect(imported.importedFromVsd, isTrue);
    expect(imported.document.pages, hasLength(2));
    expect(
      imported.document.pages.map((page) => page.name),
      ['Test Master', 'Test Master 2'],
    );
    expect(imported.document.pages.first.widthInches, closeTo(8.2677, 1e-4));
    expect(imported.document.pages.first.heightInches, closeTo(11.6929, 1e-4));
    expect(imported.document.pages.every((page) => page.shapes.isNotEmpty),
        isTrue);

    final svg = VsdxToSvgSerializer().serializeDocument(imported.document);
    expect(svg, contains('<path'));

    final reopened = const DocumentParser().parse(imported.originalBytes);
    expect(reopened.pages, hasLength(2));
    expect(
      reopened.pages.map((page) => page.name),
      imported.document.pages.map((page) => page.name),
    );
    expect(reopened.pages.every((page) => page.shapes.isNotEmpty), isTrue);
    expect(
        VsdxToSvgSerializer().serializeDocument(reopened), contains('<path'));
  });

  final oracle = LibvisioOracle.tryLoad();
  test(
    'legacy VSS page structure matches libvisio parseStencils',
    () {
      final bytes = _stencilFixture();
      final reference = oracle!.stencilSvgPages(bytes);
      expect(reference, isNotNull);
      expect(reference, hasLength(1));
      expect(reference!.single, contains('width="1.7250in"'));
      expect(reference.single, contains('height="0.1720in"'));
      expect(reference.single, contains('image/emf'));

      final imported = parseVisio(bytes, sourceName: 'device.vss');
      final roundTrip = oracle.svgPages(imported.originalBytes);
      expect(roundTrip, isNotNull);
      expect(roundTrip, hasLength(reference.length));
      expect(roundTrip!.single, contains('width="1.7250in"'));
      expect(roundTrip.single, contains('height="0.1720in"'));
      expect(
        roundTrip.single.contains('image/emf') ||
            roundTrip.single.contains('image/png'),
        isTrue,
        reason: 'Draw cannot replay EnhMetaFile, so a save may rasterise '
            'the stencil preview to PNG while keeping the page size',
      );
    },
    skip: oracle == null
        ? 'libvisio shim not built — run packages/vsdx/native/build.sh'
        : null,
  );

  test(
    'OPC VSSX page structure matches libvisio parseStencils',
    () {
      final bytes = _opcStencilFixture();
      final reference = oracle!.stencilSvgPages(bytes);
      expect(reference, isNotNull);
      expect(reference, hasLength(2));
      expect(reference!.first, contains('width="8.2677in"'));
      expect(reference.last, contains('width="8.2677in"'));

      final imported = parseVisio(bytes, sourceName: 'sampler.vssx');
      final roundTrip = oracle.svgPages(imported.originalBytes);
      expect(roundTrip, isNotNull);
      expect(roundTrip, hasLength(reference.length));
      expect(roundTrip!.first, contains('width="8.2677in"'));
      expect(roundTrip.last, contains('width="8.2677in"'));
    },
    skip: oracle == null
        ? 'libvisio shim not built — run packages/vsdx/native/build.sh'
        : null,
  );
}
