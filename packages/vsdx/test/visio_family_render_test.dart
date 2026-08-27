/// Coverage for the whole Visio file-type matrix the editor advertises.
///
/// LibreOffice funnels every one of these extensions into the same
/// `libvisio::VisioDocument::isSupported` / `parse` pair (see
/// `writerperfect/source/draw/VisioImportFilter.cxx`), so a type either opens
/// through one of libvisio's three containers — OLE2 binary, OPC package,
/// DiagramML XML — or not at all. The suites elsewhere exercise `.vsdx`,
/// `.vsd` and `.vdx` in depth; the remaining nine extensions used to have no
/// end-to-end check at all, which is how a container regression could ship
/// while every existing test stayed green.
///
/// Each variant is taken through the full pipeline: detect → parse → render to
/// SVG → save → reopen, then handed to LibreOffice so the saved package is
/// proven to open in the reference consumer.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

import 'support/libvisio_oracle.dart';

/// `[Content_Types].xml` main part type per OPC extension, from MS-VSDX.
const _opcMainTypes = <String, String>{
  'vsdx': 'application/vnd.ms-visio.drawing.main+xml',
  'vsdm': 'application/vnd.ms-visio.drawing.macroEnabled.main+xml',
  'vstx': 'application/vnd.ms-visio.template.main+xml',
  'vstm': 'application/vnd.ms-visio.template.macroEnabled.main+xml',
  'vssx': 'application/vnd.ms-visio.stencil.main+xml',
  'vssm': 'application/vnd.ms-visio.stencil.macroEnabled.main+xml',
};

/// Extensions Visio uses for standalone stencils and templates. Opening one
/// promotes its masters to pages (libvisio's `parseStencils` entry point), so
/// the shape text of the source drawing is not expected to survive.
const _stencilExtensions = <String>{'vssx', 'vssm', 'vss', 'vsx'};

class _Variant {
  const _Variant(this.name, this.bytes, {this.expectText = true});

  final String name;
  final Uint8List bytes;

  /// Whether shape text from the source document must reach the model.
  final bool expectText;
}

void main() {
  final soffice = _resolveSoffice();
  final require = Platform.environment['REQUIRE_SOFFICE'] == '1';
  final oracle = LibvisioOracle.tryLoad();

  late List<_Variant> variants;

  setUpAll(() {
    final drawing = _read('test/fixtures/test4_connectors.vsdx');
    final binary = _read('test/fixtures/vsd/Visio11FormatLine.vsd');
    final stencil = Uint8List.fromList(
      base64.decode(
        File('test/fixtures/vsd/external/'
                'Nortel-vpn-gateway-3050-front.vss.b64')
            .readAsStringSync()
            .replaceAll(RegExp(r'\s'), ''),
      ),
    );
    final diagramMl = _read('test/fixtures/vdx_all_types.vdx');

    variants = <_Variant>[
      for (final entry in _opcMainTypes.entries)
        _Variant(
          'family.${entry.key}',
          _withMainContentType(drawing, entry.value),
          expectText: !_stencilExtensions.contains(entry.key),
        ),
      _Variant('family.vsd', binary),
      _Variant('family.vst', binary),
      _Variant('family.vss', stencil, expectText: false),
      _Variant('family.vdx', diagramMl),
      _Variant('family.vsx', diagramMl, expectText: false),
      _Variant('family.vtx', diagramMl),
      // libvisio falls back to the input itself when there is no
      // `VisioDocument` substream, so a bare record stream is a supported
      // binary document as far as LibreOffice is concerned.
      _Variant(
        'flat-record-stream.vsd',
        Uint8List.fromList(
          CompoundFile.open(binary).readStream('VisioDocument')!,
        ),
      ),
      // libvisio's `isXmlVisioDocument` only matches the root element name,
      // so DiagramML without any namespace declaration still opens.
      _Variant(
        'no-namespace.vdx',
        Uint8List.fromList(
          utf8.encode(
            utf8
                .decode(diagramMl)
                .replaceAll(RegExp(r'\sxmlns(:\w+)?="[^"]*"'), ''),
          ),
        ),
      ),
    ];
  });

  test('every Visio extension parses, renders and round-trips', () {
    for (final variant in variants) {
      final result = parseVisio(variant.bytes, sourceName: variant.name);
      final document = result.document;
      expect(document.pages, isNotEmpty, reason: '${variant.name} has no page');
      expect(
        _shapeCount(document),
        greaterThan(0),
        reason: '${variant.name} parsed no shape',
      );

      for (final page in document.pages) {
        final svg = VsdxToSvgSerializer().serializePage(
          page,
          theme: document.theme,
          images: document.images,
          underlayPage: document.backgroundFor(page),
        );
        expect(
          _drawableCount(svg),
          greaterThan(0),
          reason: '${variant.name} page "${page.name}" rendered nothing',
        );
      }

      if (variant.expectText) {
        expect(
          _visibleText(document),
          isNotEmpty,
          reason: '${variant.name} lost all shape text',
        );
      }

      final saved = const VsdxWriter().write(
        originalBytes: result.originalBytes,
        edited: document,
      );
      final reopened = const DocumentParser().parse(saved);
      expect(
        reopened.pages,
        hasLength(document.pages.length),
        reason: '${variant.name} round-trip changed the page count',
      );
      expect(
        _shapeCount(reopened),
        _shapeCount(document),
        reason: '${variant.name} round-trip changed the shape count',
      );
      expect(
        _visibleText(reopened),
        _visibleText(document),
        reason: '${variant.name} round-trip changed the visible text',
      );
    }
  });

  test('libvisio accepts every variant the editor accepts', () {
    if (oracle == null) {
      markTestSkipped('libvisio shim not built — run native/build.sh');
      return;
    }
    for (final variant in variants) {
      expect(
        oracle.svgPages(variant.bytes),
        isNotNull,
        reason: '${variant.name} must satisfy libvisio isSupported() so the '
            'editor and LibreOffice agree on which files open',
      );
    }
  });

  test('LibreOffice opens the saved package for every Visio extension',
      () async {
    if (soffice == null) {
      if (require) {
        fail('REQUIRE_SOFFICE=1 but LibreOffice soffice was not found');
      }
      markTestSkipped('LibreOffice soffice not installed');
      return;
    }

    final directory = await Directory.systemTemp.createTemp('vsdx_family_');
    final profile = Directory('${directory.path}/lo_profile')..createSync();
    try {
      final paths = <String>[];
      for (final variant in variants) {
        final result = parseVisio(variant.bytes, sourceName: variant.name);
        final saved = const VsdxWriter().write(
          originalBytes: result.originalBytes,
          edited: result.document,
        );
        final stem = _stem(variant.name);
        final file = File('${directory.path}/$stem.vsdx');
        await file.writeAsBytes(saved);
        paths.add(file.path);
      }

      final converted = await Process.run(
        soffice,
        <String>[
          '--headless',
          '--norestore',
          '--nofirststartwizard',
          '-env:UserInstallation=file://${profile.path}',
          '--convert-to',
          'pdf',
          '--outdir',
          directory.path,
          ...paths,
        ],
        workingDirectory: directory.path,
        environment: <String, String>{
          ...Platform.environment,
          'SAL_USE_VCLPLUGIN': 'svp',
        },
      );
      expect(
        converted.exitCode,
        0,
        reason: 'soffice stderr: ${converted.stderr}\n${converted.stdout}',
      );

      for (final variant in variants) {
        final pdf = File('${directory.path}/${_stem(variant.name)}.pdf');
        expect(
          pdf.existsSync(),
          isTrue,
          reason: 'LibreOffice produced no PDF for ${variant.name}',
        );
        expect(pdf.lengthSync(), greaterThan(100));
      }
    } finally {
      await directory.delete(recursive: true);
    }
  },
      timeout: const Timeout(Duration(minutes: 5)),
      skip: (!require && soffice == null)
          ? 'LibreOffice soffice not installed'
          : false);
}

Uint8List _read(String path) =>
    Uint8List.fromList(File(path).readAsBytesSync());

String _stem(String name) => name.replaceAll('.', '_');

Uint8List _withMainContentType(Uint8List bytes, String contentType) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final output = Archive();
  for (final file in archive.files) {
    if (!file.isFile) continue;
    final content = file.name == '[Content_Types].xml'
        ? utf8.encode(
            utf8.decode(file.content as List<int>).replaceFirst(
                  'application/vnd.ms-visio.drawing.main+xml',
                  contentType,
                ),
          )
        : file.content as List<int>;
    output.addFile(ArchiveFile(file.name, content.length, content));
  }
  return Uint8List.fromList(ZipEncoder().encode(output)!);
}

int _drawableCount(String svg) => RegExp(
      r'<(path|rect|ellipse|circle|polygon|polyline|line|image|text)\b',
    ).allMatches(svg).length;

int _shapeCount(VsdxDocument document) {
  var total = 0;
  void walk(VsdxShape shape) {
    if (!isLibvisioBakePlate(shape)) total++;
    for (final child in shape.children) {
      walk(child);
    }
  }

  for (final page in document.pages) {
    for (final shape in page.shapes) {
      walk(shape);
    }
  }
  return total;
}

String _visibleText(VsdxDocument document) {
  final buffer = StringBuffer();
  void walk(VsdxShape shape) {
    if (!shape.richText.textBlock.hideText) {
      buffer.write(shape.richText.plainText.replaceAll(RegExp(r'\s+'), ''));
    }
    for (final child in shape.children) {
      walk(child);
    }
  }

  for (final page in document.pages) {
    for (final shape in page.shapes) {
      walk(shape);
    }
  }
  final characters = buffer.toString().split('')..sort();
  return characters.join();
}

String? _resolveSoffice() {
  final env = Platform.environment['SOFFICE'];
  if (env != null && env.isNotEmpty && File(env).existsSync()) return env;
  for (final name in <String>['soffice', 'libreoffice']) {
    final which = Process.runSync('which', <String>[name]);
    if (which.exitCode == 0) {
      final path = (which.stdout as String).trim();
      if (path.isNotEmpty) return path;
    }
  }
  const mac = '/Applications/LibreOffice.app/Contents/MacOS/soffice';
  if (File(mac).existsSync()) return mac;
  return null;
}
