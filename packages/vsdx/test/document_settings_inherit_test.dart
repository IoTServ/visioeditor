import 'package:test/test.dart';
import 'package:vsdx/src/parser/document_settings_parser.dart';
import 'package:xml/xml.dart';

void main() {
  const parser = DocumentSettingsParser();

  test('DocumentSettings cell F=Inh uses defaults (ignores stale V)', () {
    final doc = XmlDocument.parse('''
      <VisioDocument>
        <DocumentSettings>
          <Cell N="PageColor" V="#FF0000" F="Inh"/>
          <Cell N="SnapEnabled" V="0" F="Inh"/>
          <Cell N="GlueType" V="9" F="Inh"/>
          <Cell N="GridDensityX" V="1" F="Inh"/>
        </DocumentSettings>
      </VisioDocument>
    ''');
    final s = parser.parse(doc);
    expect(s.defaultPageBackgroundColor, isNull);
    expect(s.snapEnabled, isTrue);
    expect(s.glueType, 0);
    expect(s.gridDensityX, 4);
  });

  test('DocumentSettings literal cells are honoured', () {
    final doc = XmlDocument.parse('''
      <VisioDocument>
        <DocumentSettings>
          <Cell N="PageColor" V="#00FF00"/>
          <Cell N="SnapEnabled" V="0"/>
          <Cell N="GlueType" V="2"/>
        </DocumentSettings>
      </VisioDocument>
    ''');
    final s = parser.parse(doc);
    expect(s.defaultPageBackgroundColor?.value, 0xFF00FF00);
    expect(s.snapEnabled, isFalse);
    expect(s.glueType, 2);
  });
}
