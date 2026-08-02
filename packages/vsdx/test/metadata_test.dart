import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

Uint8List _rewritePackage(
  Uint8List input, {
  Map<String, String> renamedParts = const {},
  Map<String, Map<String, String>> substitutionsByPart = const {},
  Map<String, String> replacementParts = const {},
  Map<String, String> additionalParts = const {},
}) {
  final source = ZipDecoder().decodeBytes(input);
  final output = Archive();
  for (final file in source) {
    final raw = file.content;
    var bytes = raw is Uint8List ? raw : Uint8List.fromList(raw as List<int>);
    final replacement = replacementParts[file.name];
    if (replacement != null) {
      bytes = Uint8List.fromList(utf8.encode(replacement));
    } else {
      final substitutions = substitutionsByPart[file.name];
      if (substitutions != null) {
        var text = utf8.decode(bytes);
        for (final entry in substitutions.entries) {
          text = text.replaceAll(entry.key, entry.value);
        }
        bytes = Uint8List.fromList(utf8.encode(text));
      }
    }
    final name = renamedParts[file.name] ?? file.name;
    output.addFile(ArchiveFile(name, bytes.length, bytes));
  }
  for (final entry in additionalParts.entries) {
    final bytes = Uint8List.fromList(utf8.encode(entry.value));
    output.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(output)!);
}

void main() {
  test('full libvisio metadata surface parses from a synthesized VSDX', () {
    const writer = VsdxWriter();
    final bytes = writer.emptyDocument(
      title: 'Title',
      creator: 'Creator',
      subject: 'Subject',
      keywords: 'one;two',
      description: 'Description',
      lastModifiedBy: 'Editor',
      created: '2026-01-02T03:04:05Z',
      modified: '2026-02-03T04:05:06Z',
      language: 'zh-CN',
      category: 'Diagram',
      company: 'Acme',
      template: r'C:\Templates\Flow.vstx',
    );
    final doc = const DocumentParser().parse(bytes);

    expect(doc.title, 'Title');
    expect(doc.creator, 'Creator');
    expect(doc.subject, 'Subject');
    expect(doc.keywords, 'one;two');
    expect(doc.description, 'Description');
    expect(doc.lastModifiedBy, 'Editor');
    expect(doc.created, '2026-01-02T03:04:05Z');
    expect(doc.modified, '2026-02-03T04:05:06Z');
    expect(doc.language, 'zh-CN');
    expect(doc.category, 'Diagram');
    expect(doc.company, 'Acme');
    expect(doc.template, 'Flow.vstx');
  });

  test('metadata and custom properties follow package-root relationships', () {
    const writer = VsdxWriter();
    final original = writer.emptyDocument(
      title: 'Moved metadata',
      creator: 'Relationship Author',
      company: 'Relationship Corp',
      template: r'C:\Templates\Moved.vstx',
    );
    final moved = _rewritePackage(
      original,
      renamedParts: const {
        'docProps/core.xml': 'metadata/core-data.xml',
        'docProps/app.xml': 'metadata/app-data.xml',
      },
      substitutionsByPart: const {
        '_rels/.rels': {
          'docProps/core.xml': 'metadata/core-data.xml',
          'docProps/app.xml': 'metadata/app-data.xml',
          '</Relationships>':
              '<Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/custom-properties" Target="metadata/custom-data.xml"/></Relationships>',
        },
        '[Content_Types].xml': {
          '/docProps/core.xml': '/metadata/core-data.xml',
          '/docProps/app.xml': '/metadata/app-data.xml',
          '</Types>':
              '<Override PartName="/metadata/custom-data.xml" ContentType="application/vnd.openxmlformats-officedocument.custom-properties+xml"/></Types>',
        },
      },
      additionalParts: const {
        'metadata/custom-data.xml': '<?xml version="1.0" encoding="UTF-8"?>'
            '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/custom-properties" '
            'xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">'
            '<property pid="2" name="Status"><vt:lpwstr>Ready</vt:lpwstr></property>'
            '</Properties>',
      },
    );

    final doc = const DocumentParser().parse(moved);
    expect(doc.title, 'Moved metadata');
    expect(doc.creator, 'Relationship Author');
    expect(doc.company, 'Relationship Corp');
    expect(doc.template, 'Moved.vstx');
    expect(doc.customProperties, hasLength(1));
    expect(doc.customProperties.single.name, 'Status');
    expect(doc.customProperties.single.value, 'Ready');
  });

  test('malformed optional metadata does not block drawing parsing', () {
    const writer = VsdxWriter();
    final damaged = _rewritePackage(
      writer.emptyDocument(title: 'Discarded', company: 'Discarded'),
      substitutionsByPart: const {
        '_rels/.rels': {
          '</Relationships>':
              '<Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/custom-properties" Target="docProps/custom.xml"/></Relationships>',
        },
      },
      replacementParts: const {
        'docProps/core.xml': '<broken',
        'docProps/app.xml': '<broken',
      },
      additionalParts: const {'docProps/custom.xml': '<broken'},
    );

    final doc = const DocumentParser().parse(damaged);
    expect(doc.pages, hasLength(1));
    expect(doc.title, isNull);
    expect(doc.company, isNull);
    expect(doc.applicationName, isNull);
    expect(doc.customProperties, isEmpty);
  });
}
