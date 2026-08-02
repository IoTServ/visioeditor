import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

Uint8List _rewritePackage(
  Uint8List input, {
  Map<String, String> replacements = const {},
  Map<String, Map<String, String>> substitutions = const {},
  Map<String, String> additions = const {},
}) {
  final source = ZipDecoder().decodeBytes(input);
  final output = Archive();
  for (final file in source) {
    final raw = file.content;
    var bytes = raw is Uint8List ? raw : Uint8List.fromList(raw as List<int>);
    final replacement = replacements[file.name];
    if (replacement != null) {
      bytes = Uint8List.fromList(utf8.encode(replacement));
    } else {
      final edits = substitutions[file.name];
      if (edits != null) {
        var text = utf8.decode(bytes);
        for (final edit in edits.entries) {
          text = text.replaceAll(edit.key, edit.value);
        }
        bytes = Uint8List.fromList(utf8.encode(text));
      }
    }
    output.addFile(ArchiveFile(file.name, bytes.length, bytes));
  }
  for (final addition in additions.entries) {
    final bytes = Uint8List.fromList(utf8.encode(addition.value));
    output.addFile(ArchiveFile(addition.key, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(output)!);
}

void main() {
  const writer = VsdxWriter();

  test('duplicate relationship types use the last row like libvisio', () {
    final bytes = _rewritePackage(
      writer.emptyDocument(),
      substitutions: const {
        'visio/_rels/document.xml.rels': {
          '<Relationship Id="rId1"':
              '<Relationship Id="broken" Type="http://schemas.microsoft.com/visio/2010/relationships/pages" Target="pages/missing.xml"/>'
                  '<Relationship Id="rId1"',
        },
      },
    );

    final doc = const DocumentParser().parse(bytes);
    expect(doc.pages, hasLength(1));
    expect(doc.pages.single.name, 'Page-1');
  });

  test('malformed theme and masters are non-fatal like libvisio', () {
    final bytes = _rewritePackage(
      writer.emptyDocument(),
      substitutions: const {
        'visio/_rels/document.xml.rels': {
          '</Relationships>':
              '<Relationship Id="theme" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/broken.xml"/>'
                  '<Relationship Id="masters" Type="http://schemas.microsoft.com/visio/2010/relationships/masters" Target="masters/broken.xml"/>'
                  '</Relationships>',
        },
      },
      additions: const {
        'visio/theme/broken.xml': '<broken',
        'visio/masters/broken.xml': '<broken',
      },
    );

    final doc = const DocumentParser().parse(bytes);
    expect(doc.pages, hasLength(1));
    expect(doc.theme.isEmpty, isTrue);
    expect(doc.masters.length, 0);
  });

  test('malformed page content keeps its page-index shell', () {
    final bytes = _rewritePackage(
      writer.emptyDocument(widthInches: 9, heightInches: 6),
      replacements: const {'visio/pages/page1.xml': '<broken'},
    );

    final doc = const DocumentParser().parse(bytes);
    expect(doc.pages, hasLength(1));
    expect(doc.pages.single.widthInches, 9);
    expect(doc.pages.single.heightInches, 6);
    expect(doc.pages.single.shapes, isEmpty);
  });

  test('malformed pages index degrades to an empty page list', () {
    final bytes = _rewritePackage(
      writer.emptyDocument(),
      replacements: const {'visio/pages/pages.xml': '<broken'},
    );

    final doc = const DocumentParser().parse(bytes);
    expect(doc.pages, isEmpty);
  });

  test('malformed and dangling child relationships are non-fatal', () {
    final malformedSidecar = _rewritePackage(
      writer.emptyDocument(),
      replacements: const {
        'visio/pages/_rels/pages.xml.rels': '<broken',
      },
    );
    final danglingTarget = _rewritePackage(
      writer.emptyDocument(),
      substitutions: const {
        'visio/pages/_rels/pages.xml.rels': {
          'Target="page1.xml"': 'Target="missing.xml"',
        },
      },
    );

    for (final bytes in [malformedSidecar, danglingTarget]) {
      final doc = const DocumentParser().parse(bytes);
      expect(doc.pages, hasLength(1));
      expect(doc.pages.single.shapes, isEmpty);
    }
  });
}
