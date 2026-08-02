import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

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
}
