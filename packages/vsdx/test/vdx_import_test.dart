import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:charset/charset.dart' as charset;
import 'package:cp949_codec/cp949_codec.dart' as korean;
import 'package:enough_convert/enough_convert.dart' as enough;
import 'package:test/test.dart';
import 'package:vsdx/src/parser/rich_text_parser.dart';
import 'package:vsdx/vsdx.dart';
import 'package:xml/xml.dart';

Uint8List _fixture() =>
    File('test/fixtures/vdx_all_types.vdx').readAsBytesSync();

Uint8List _unresolvedConnectorFixture() => Uint8List.fromList(utf8.encode('''
<?xml version="1.0" encoding="UTF-8"?>
<VisioDocument xmlns="http://schemas.microsoft.com/visio/2003/core">
  <Masters>
    <Master ID="2" NameU="Dynamic connector">
      <PageSheet><PageProps><PageWidth>3</PageWidth><PageHeight>3</PageHeight><PageScale>1</PageScale><DrawingScale>1</DrawingScale></PageProps></PageSheet>
      <Shapes><Shape ID="5" Type="Shape">
        <XForm>
          <PinX F="GUARD((BeginX+EndX)/2)">1.5</PinX><PinY F="GUARD((BeginY+EndY)/2)">1.5</PinY>
          <Width F="GUARD(EndX-BeginX)">1</Width><Height F="GUARD(EndY-BeginY)">-1</Height>
          <LocPinX F="GUARD(Width*0.5)">0.5</LocPinX><LocPinY F="GUARD(Height*0.5)">-0.5</LocPinY>
          <Angle F="GUARD(0DA)">0</Angle>
        </XForm>
        <XForm1D><BeginX>1</BeginX><BeginY>2</BeginY><EndX>2</EndX><EndY>1</EndY></XForm1D>
        <Misc><ObjType>2</ObjType></Misc>
        <Geom IX="0"><NoFill>1</NoFill><MoveTo IX="1"><X>0</X><Y>0</Y></MoveTo><LineTo IX="2"><X>0</X><Y>-1</Y></LineTo><LineTo IX="3"><X>1</X><Y>-1</Y></LineTo></Geom>
      </Shape></Shapes>
    </Master>
  </Masters>
  <Pages><Page ID="0" NameU="Page-1">
    <PageSheet><PageProps><PageWidth>8</PageWidth><PageHeight>4</PageHeight></PageProps></PageSheet>
    <Shapes><Shape ID="1" Type="Shape" Master="2">
      <XForm><PinX>0</PinX><PinY>0</PinY></XForm>
      <XForm1D>
        <BeginX F="_WALKGLUE(BegTrigger,EndTrigger,WalkPreference)">0</BeginX>
        <BeginY F="_WALKGLUE(BegTrigger,EndTrigger,WalkPreference)">0</BeginY>
        <EndX F="_WALKGLUE(EndTrigger,BegTrigger,WalkPreference)">0</EndX>
        <EndY F="_WALKGLUE(EndTrigger,BegTrigger,WalkPreference)">0</EndY>
      </XForm1D>
      <Geom IX="0"><MoveTo IX="1"><X>1</X><Y>3</Y></MoveTo><LineTo IX="2"><X>5</X><Y>3</Y></LineTo></Geom>
    </Shape></Shapes>
  </Page></Pages>
</VisioDocument>
'''));

Uint8List _utf32(
  String value, {
  required bool littleEndian,
  required bool bom,
}) {
  final out = BytesBuilder(copy: false);
  if (bom) {
    out.add(littleEndian
        ? const <int>[0xFF, 0xFE, 0, 0]
        : const <int>[0, 0, 0xFE, 0xFF]);
  }
  for (final rune in value.runes) {
    final data = ByteData(4)
      ..setUint32(
        0,
        rune,
        littleEndian ? Endian.little : Endian.big,
      );
    out.add(data.buffer.asUint8List());
  }
  return out.takeBytes();
}

List<VsdxShape> _allShapes(VsdxDocument document) {
  final out = <VsdxShape>[];
  void visit(VsdxShape shape) {
    out.add(shape);
    for (final child in shape.children) {
      visit(child);
    }
  }

  for (final page in document.pages) {
    for (final shape in page.shapes) {
      visit(shape);
    }
  }
  return out;
}

Set<Type> _commandTypes(VsdxShape shape) => <Type>{
      for (final geometry in shape.geometries)
        for (final command in geometry.commands) command.runtimeType,
    };

void main() {
  group('DiagramML VDX/VSX/VTX import', () {
    test('normalises every libvisio drawing component into the shared model',
        () {
      final source = _fixture();
      expect(looksLikeVdx(source), isTrue);
      final rawPolyline = const VdxDocumentParser()
          .parse(source)
          .pages
          .single
          .findShapeById(7)!;
      expect(_commandTypes(rawPolyline), contains(PolylineTo),
          reason: 'the DiagramML row type must be parsed before compatibility '
              'normalisation');

      final result = parseVisio(source, sourceName: 'coverage.vdx');
      expect(result.importedFromVsd, isTrue);
      expect(result.document.title, 'DiagramML parser coverage');
      expect(result.document.creator, 'visioeditor tests');
      expect(result.document.pages, hasLength(1));
      expect(result.document.masters.length, 1);
      expect(result.document.images.length, 2);

      final page = result.document.pages.single;
      expect(page.name, 'Coverage');
      expect(page.widthInches, 10);
      expect(page.heightInches, 7);
      expect(page.layers, hasLength(2));
      expect(page.layers.first.visible, isTrue);
      expect(page.layers.last.visible, isFalse);
      expect(page.connects, hasLength(2));

      final shapes = _allShapes(result.document);
      expect(shapes, hasLength(10));
      final masterInstance = page.findShapeById(1)!;
      expect(masterInstance.geometries.single.commands, hasLength(9));
      expect(
        masterInstance.geometries.single.commands.whereType<RelQuadBezTo>(),
        hasLength(4),
        reason: 'legacy Rounding must be explicit for libvisio VSDX reopen',
      );
      expect(masterInstance.fill.foreground, const VsdxColor(0xFFFFFFFF));
      expect(masterInstance.fill.foregroundTransparency, closeTo(0.15, 1e-9));
      expect(masterInstance.line.color, const VsdxColor(0xFF2F5597));
      expect(masterInstance.richText.plainText,
          contains('All rich text retained'));
      expect(
          masterInstance.richText.plainText, contains('Second line and tab'));
      expect(masterInstance.richText.runs.length, greaterThanOrEqualTo(2));
      expect(masterInstance.richText.tabSets, hasLength(1));
      expect(
        masterInstance.richText.runs.map((run) => run.charStyle.color),
        everyElement(const VsdxColor(0xFF2F5597)),
        reason: 'libvisio materialises VDX layer colour on text and stroke',
      );
      expect(
        masterInstance.richText.runs
            .where((run) => !run.charStyle.style.bold)
            .map((run) => run.text)
            .join(),
        'All rich text retained\nSeco',
        reason: 'libvisio applies cp character counts in numeric IX order',
      );
      expect(
        masterInstance.richText.runs
            .where((run) => run.charStyle.style.bold)
            .map((run) => run.text)
            .join(),
        'nd line and tab:\tvalue',
      );

      final curves = page.findShapeById(2)!;
      expect(curves.fields, hasLength(1));
      expect(curves.fields.single.value, 'Cached field text');
      expect(curves.actions, hasLength(1));
      expect(curves.actions.single.name, 'OpenCoverage');
      expect(curves.actions.single.ix, 7);
      expect(curves.actions.single.menu, 'Open coverage docs');
      expect(curves.actions.single.actionFormula,
          'HYPERLINK("https://example.test/vdx-action")');
      expect(curves.actions.single.checked, isTrue);
      expect(curves.actions.single.sortKey, '700');
      expect(curves.hyperlinks, hasLength(1));
      expect(curves.hyperlinks.single.id, 5);
      expect(curves.hyperlinks.single.description, 'Coverage documentation');
      expect(curves.hyperlinks.single.address, 'https://example.test/vdx-link');
      expect(curves.hyperlinks.single.newWindow, isTrue);
      expect(curves.hyperlinks.single.isDefault, isTrue);
      expect(curves.hyperlinks.single.sortKey, '500');
      expect(
        curves.richText.plainText,
        'Bezier, arcs, ellipse: Cached field text',
      );
      expect(
        _commandTypes(curves),
        containsAll(<Type>[
          ArcTo,
          CubBezTo,
          QuadBezTo,
          EllipseCmd,
          EllipticalArcTo,
        ]),
      );
      final group = page.findShapeById(3)!;
      expect(
          group.children.map((shape) => shape.id), orderedEquals(<int>[4, 5]));
      expect(
        group.children
            .map((shape) => shape.richText.runs.single.charStyle.style.bold),
        everyElement(isTrue),
        reason: 'the final VDX stylesheet Character row is the default',
      );
      expect(page.findShapeById(6)!.is1D, isTrue);
      expect(page.findShapeById(6)!.line.endArrow, 4);
      final inheritedStyle = page.findShapeById(7)!;
      expect(inheritedStyle.line.cap, LineCap.square);
      expect(inheritedStyle.line.beginArrow, 4);
      expect(inheritedStyle.line.endArrow, 13);
      expect(inheritedStyle.line.roundingInches, closeTo(0.08, 1e-9));
      expect(inheritedStyle.fill.foregroundTransparency, closeTo(0.15, 1e-9));
      expect(inheritedStyle.fill.backgroundTransparency, closeTo(0.35, 1e-9));
      expect(inheritedStyle.shadow.enabled, isTrue);
      expect(inheritedStyle.shadow.color, const VsdxColor(0xFF44546A));
      expect(inheritedStyle.shadow.offsetXInches, closeTo(0.2, 1e-9));
      expect(inheritedStyle.shadow.offsetYInches, closeTo(-0.15, 1e-9));
      expect(inheritedStyle.shadow.blurInches, 0,
          reason: 'classic VDX shadows are hard-edged like libvisio');
      expect(inheritedStyle.richText.textBlock.marginLeftInches,
          closeTo(0.05, 1e-9));
      expect(inheritedStyle.richText.textBlock.defaultTabStopInches,
          closeTo(0.4, 1e-9));
      expect(
        _commandTypes(inheritedStyle),
        containsAll(<Type>[
          RelMoveTo,
          RelLineTo,
          RelCubBezTo,
          RelQuadBezTo,
          RelArcTo,
          RelEllipticalArcTo,
        ]),
      );
      expect(_commandTypes(inheritedStyle), isNot(contains(PolylineTo)),
          reason: 'legacy Rounding is baked for libvisio VSDX reopen');
      final advancedGeometry = page.findShapeById(10)!;
      expect(
        _commandTypes(advancedGeometry),
        containsAll(<Type>[
          InfiniteLineCmd,
          SplineStart,
          SplineKnot,
          NurbsTo,
        ]),
      );
      final image = page.findShapeById(8)!;
      expect(image.hasImage, isTrue);
      expect(
          result.document.images.findByPart(image.imagePartName!), isNotNull);
      final dibImageShape = page.findShapeById(9)!;
      expect(dibImageShape.hasImage, isTrue);
      final dibImage =
          result.document.images.findByPart(dibImageShape.imagePartName!)!;
      expect(dibImage.mimeType, 'image/bmp');
      expect(dibImage.partName, endsWith('.bmp'));
      expect(dibImage.bytes, hasLength(58));
      expect(dibImage.bytes.sublist(0, 2), orderedEquals(<int>[0x42, 0x4D]));
      expect(dibImage.bytes.sublist(10, 14), orderedEquals(<int>[54, 0, 0, 0]));
      final svg = VsdxToSvgSerializer().serializePage(
        page,
        images: result.document.images,
      );
      expect(svg, contains('data:image/bmp;base64,Qk0'));
      expect(svg, contains('href="https://example.test/vdx-link"'));
      expect(
        RegExp(
          r'fill="#44546a" fill-opacity="0\.85" stroke="none" '
          r'transform="translate\(0\.187 -0\.166\)"',
        ).allMatches(svg).length,
        2,
        reason: 'group rotation must not rotate libvisio page-space shadows',
      );
      expect(
        RegExp(r'marker-end="url\(#arrow-end-p0-7-[012]\)"').allMatches(svg),
        hasLength(2),
        reason: 'RelArcTo closes Geometry 0; the polyline and elliptical '
            'arc sections stay open',
      );
      expect(
        RegExp(r'marker-end="url\(#arrow-end-p0-10-[012]\)"').allMatches(svg),
        hasLength(3),
        reason: 'InfiniteLine receives its page-clipped line ending',
      );
      final ellipseCarrier = RegExp(
        r'<path d="([^"]+)"[^>]*marker-end="url\(#arrow-end-p0-2-1\)"',
      ).firstMatch(svg)!.group(1)!;
      expect(
        RegExp(r'\bM ').allMatches(ellipseCarrier),
        hasLength(1),
        reason: 'closed Ellipse is skipped while its following open arc marks',
      );
    });

    test('VDX import synthesises an editable VSDX without losing visible data',
        () {
      final imported = parseVisio(_fixture(), sourceName: 'coverage.vdx');
      final reopened = parseVisio(
        imported.originalBytes,
        sourceName: 'coverage.vsdx',
      ).document;
      final resaved = const DocumentParser().parse(
        const VsdxWriter().write(
          originalBytes: imported.originalBytes,
          edited: imported.document,
        ),
      );

      expect(reopened.pages, hasLength(1));
      expect(reopened.masters.length, imported.document.masters.length);
      final reopenedMaster = reopened.masters.find(1)!;
      expect(reopenedMaster.name, 'Master Rectangle');
      expect(reopenedMaster.prototype.id, 100);
      expect(reopenedMaster.prototype.geometries.single.commands, hasLength(9));
      expect(
        reopenedMaster.prototype.geometries.single.commands
            .whereType<RelQuadBezTo>(),
        hasLength(4),
      );
      expect(_allShapes(reopened), hasLength(10));
      expect(reopened.images.length, 2);
      expect(
        resaved.pages.single
            .findShapeById(4)!
            .geometries
            .single
            .commands
            .whereType<RelQuadBezTo>(),
        hasLength(4),
        reason: 'the normal editor save path must retain baked VDX rounding',
      );
      final allText = _allShapes(reopened)
          .map((shape) => shape.richText.plainText)
          .join('\n');
      for (final expected in const <String>[
        'All rich text retained',
        'Second line and tab',
        'Bezier, arcs, ellipse',
        'Cached field text',
        'Grouped child A',
        'Grouped child B',
        '1-D connector',
        'Relative and polyline rows',
        'Spline, NURBS, infinite line',
      ]) {
        expect(allText, contains(expected));
      }
      expect(reopened.pages.single.findShapeById(8)!.hasImage, isTrue);
      expect(
        reopened.pages.single.findShapeById(8)!.geometries,
        everyElement(isA<VsdxGeometry>().having(
          (geometry) => geometry.noShow,
          'NoShow',
          isTrue,
        )),
        reason: 'a synthetic Foreign hit frame must not acquire inherited '
            'fill, line, or shadow after reopen',
      );
      final reopenedDibShape = reopened.pages.single.findShapeById(9)!;
      expect(reopenedDibShape.hasImage, isTrue);
      expect(reopenedDibShape.geometries.single.noShow, isTrue);
      final reopenedDib =
          reopened.images.findByPart(reopenedDibShape.imagePartName!)!;
      expect(reopenedDib.mimeType, 'image/bmp');
      expect(reopenedDib.bytes.sublist(0, 2), orderedEquals(<int>[0x42, 0x4D]));
      final reopenedSvg = VsdxToSvgSerializer().serializePage(
        reopened.pages.single,
        images: reopened.images,
      );
      expect(reopenedSvg, contains('data:image/bmp;base64,Qk0'));
      expect(
        RegExp(
          r'fill="#44546a" fill-opacity="0\.85" stroke="none" '
          r'transform="translate\(0\.187 -0\.166\)"',
        ).allMatches(reopenedSvg).length,
        2,
        reason: 'round-trip must retain page-space shadows in the group',
      );
      final package = VsdxPackage.open(imported.originalBytes);
      expect(
        package.allPartNames,
        containsAll(<String>[
          '/visio/masters/masters.xml',
          '/visio/masters/_rels/masters.xml.rels',
          '/visio/masters/master1.xml',
        ]),
      );
      final relationships = RelationshipResolver(package);
      final documentPart = package.resolveDocumentPartName();
      final mastersPart = relationships.singleTargetOfType(
        documentPart,
        VsdxRelType.masters,
      );
      expect(mastersPart, '/visio/masters/masters.xml');
      expect(
        relationships.targetsOfType(mastersPart!, VsdxRelType.master),
        <String>['/visio/masters/master1.xml'],
      );
      final pageXml = package.readPartXml('/visio/pages/page1.xml')!;
      final masterInstanceXml =
          pageXml.descendants.whereType<XmlElement>().singleWhere(
                (element) =>
                    element.name.local == 'Shape' &&
                    element.getAttribute('ID') == '1',
              );
      expect(masterInstanceXml.getAttribute('Master'), '1');
      final groupedChildXml =
          pageXml.descendants.whereType<XmlElement>().singleWhere(
                (element) =>
                    element.name.local == 'Shape' &&
                    element.getAttribute('ID') == '4',
              );
      String? groupedChildCell(String name) => groupedChildXml.childElements
          .where((element) =>
              element.name.local == 'Cell' && element.getAttribute('N') == name)
          .firstOrNull
          ?.getAttribute('V');
      expect(groupedChildCell('ShdwForegnd'), '#44546A');
      expect(groupedChildCell('ShapeShdwOffsetX'), '0.2');
      expect(groupedChildCell('ShapeShdwOffsetY'), '-0.15');
      expect(groupedChildCell('ShdwForegndTrans'), '0');
      final picture = pageXml.descendants.whereType<XmlElement>().singleWhere(
          (element) =>
              element.name.local == 'Shape' &&
              element.getAttribute('ID') == '9');
      final foreignData = picture.childElements
          .singleWhere((element) => element.name.local == 'ForeignData');
      expect(foreignData.getAttribute('ForeignType'), 'Bitmap');
      expect(foreignData.getAttribute('CompressionType'), isNull,
          reason: 'the VSDX media part already contains a complete BMP header');
      final childNames =
          picture.childElements.map((element) => element.name.local).toList();
      expect(childNames.last, 'ForeignData');
      expect(childNames.lastIndexOf('Section'),
          lessThan(childNames.indexOf('ForeignData')));
      expect(
        _commandTypes(reopened.pages.single.findShapeById(2)!),
        containsAll(<Type>[
          RelCubBezTo,
          RelQuadBezTo,
          ArcTo,
          EllipseCmd,
          EllipticalArcTo,
        ]),
        reason: 'CubBezTo/QuadBezTo become Rel* so libvisio can collect them',
      );
      expect(
        _commandTypes(reopened.pages.single.findShapeById(2)!),
        isNot(contains(CubBezTo)),
      );
      expect(
        _commandTypes(reopened.pages.single.findShapeById(7)!),
        containsAll(<Type>[RelQuadBezTo, RelEllipticalArcTo, ArcTo]),
        reason: 'RelArcTo is written as ArcTo for LibreOffice',
      );
      expect(
        _commandTypes(reopened.pages.single.findShapeById(10)!),
        containsAll(<Type>[
          InfiniteLineCmd,
          SplineStart,
          SplineKnot,
          NurbsTo,
        ]),
      );
      final inheritedStyle = reopened.pages.single.findShapeById(7)!;
      final sourceStyle = imported.document.pages.single.findShapeById(7)!;
      expect(inheritedStyle.line.cap, LineCap.square);
      expect(inheritedStyle.line.beginArrow, 4);
      expect(inheritedStyle.line.endArrow, 13);
      expect(inheritedStyle.line.roundingInches, closeTo(0, 1e-9),
          reason: 'Rounding is baked into RelQuadBezTo; the cell is 0 so '
              'Visio does not fillet twice');
      expect(inheritedStyle.fill.foregroundTransparency, closeTo(0.15, 1e-9));
      expect(inheritedStyle.shadow.enabled, isTrue);
      expect(
        inheritedStyle.shadow.color,
        shadowForLibvisioWrite(sourceStyle.shadow).color,
      );
      expect(inheritedStyle.shadow.offsetXInches, closeTo(0.2, 1e-9));
      expect(inheritedStyle.shadow.blurInches, 0,
          reason: 'VDX round-trip must preserve a hard classic shadow');
      expect(inheritedStyle.richText.textBlock.defaultTabStopInches,
          closeTo(0.4, 1e-9));
      final reopenedMasterInstance = reopened.pages.single.findShapeById(1)!;
      expect(
        reopenedMasterInstance.richText.runs.map((run) => run.charStyle.color),
        everyElement(const VsdxColor(0xFF2F5597)),
      );
      expect(
        reopenedMasterInstance.richText.runs
            .where((run) => !run.charStyle.style.bold)
            .map((run) => run.text)
            .join(),
        'All rich text retained\nSeco',
        reason: 'synthesised VSDX retains libvisio VDX character bands',
      );
      expect(
        reopenedMasterInstance.richText.runs
            .where((run) => run.charStyle.style.bold)
            .map((run) => run.text)
            .join(),
        'nd line and tab:\tvalue',
      );
      final reopenedCurves = reopened.pages.single.findShapeById(2)!;
      expect(reopenedCurves.actions.single.ix, 7);
      expect(reopenedCurves.actions.single.name, 'OpenCoverage');
      expect(reopenedCurves.actions.single.actionFormula,
          'HYPERLINK("https://example.test/vdx-action")');
      expect(reopenedCurves.hyperlinks.single.id, 5);
      expect(reopenedCurves.hyperlinks.single.address,
          'https://example.test/vdx-link');
      expect(reopenedSvg, contains('href="https://example.test/vdx-link"'));
      expect(
        RegExp(r'marker-end="url\(#arrow-end-p0-7-[012]\)"')
            .allMatches(reopenedSvg),
        hasLength(2),
        reason: 'RelArcTo closes Geometry 0; the other two sections stay open',
      );
      expect(
        RegExp(r'marker-end="url\(#arrow-end-p0-10-[012]\)"')
            .allMatches(reopenedSvg),
        hasLength(3),
        reason: 'InfiniteLine ending survives VDX to VSDX round-trip',
      );
      final reopenedEllipseCarrier = RegExp(
        r'<path d="([^"]+)"[^>]*marker-end="url\(#arrow-end-p0-2-1\)"',
      ).firstMatch(reopenedSvg)!.group(1)!;
      expect(
        RegExp(r'\bM ').allMatches(reopenedEllipseCarrier),
        hasLength(1),
        reason: 'closed/open marker semantics survive VDX to VSDX round-trip',
      );

      final curvesXml = pageXml.descendants.whereType<XmlElement>().singleWhere(
          (element) =>
              element.name.local == 'Shape' &&
              element.getAttribute('ID') == '2');
      final rowKeys = <String>{
        for (final row in curvesXml.descendants.whereType<XmlElement>())
          if (row.name.local == 'Row')
            '${row.parentElement?.getAttribute('N')}:${row.getAttribute('IX')}',
      };
      expect(rowKeys, containsAll(<String>['Actions:7', 'Hyperlink:5']));
    });

    test('retains the master frame for unresolved WALKGLUE connectors', () {
      final imported = parseVisio(
        _unresolvedConnectorFixture(),
        sourceName: 'walkglue.vdx',
      );

      void expectConnector(VsdxDocument document) {
        final connector = document.pages.single.findShapeById(1)!;
        expect(connector.is1D, isTrue);
        expect(connector.width, 1);
        expect(connector.height, -1);
        expect(connector.locPinXInches, 0.5);
        expect(connector.locPinYInches, -0.5);
        expect(connector.angleRad, 0);
        for (final name in const <String>[
          'Width',
          'Height',
          'LocPinX',
          'LocPinY',
          'Angle',
        ]) {
          expect(connector.formulas, isNot(contains(name)));
        }
        for (final name in const <String>['BeginX', 'BeginY', 'EndX', 'EndY']) {
          expect(connector.formulas[name], contains('_WALKGLUE'));
        }
        expect(connector.geometries.single.commands, hasLength(3));
      }

      expectConnector(imported.document);
      expectConnector(const DocumentParser().parse(imported.originalBytes));

      final pageXml = VsdxPackage.open(imported.originalBytes)
          .readPartXml('/visio/pages/page1.xml')!;
      final connectorXml =
          pageXml.descendants.whereType<XmlElement>().singleWhere(
                (element) =>
                    element.name.local == 'Shape' &&
                    element.getAttribute('ID') == '1',
              );
      final cells = <String, XmlElement>{
        for (final cell in connectorXml.childElements
            .where((element) => element.name.local == 'Cell'))
          cell.getAttribute('N')!: cell,
      };
      expect(cells['Width']!.getAttribute('V'), '1');
      expect(cells['Height']!.getAttribute('V'), '-1');
      expect(cells['LocPinX']!.getAttribute('V'), '0.5');
      expect(cells['LocPinY']!.getAttribute('V'), '-0.5');
      expect(cells['Angle']!.getAttribute('V'), '0');
      for (final name in const <String>[
        'Width',
        'Height',
        'LocPinX',
        'LocPinY',
        'Angle',
      ]) {
        expect(cells[name]!.getAttribute('F'), isNull);
      }
      expect(cells['BeginX']!.getAttribute('F'), contains('_WALKGLUE'));
    });

    test('remaps DiagramML master zero to a positive VSDX master id', () {
      final source = utf8
          .decode(_fixture())
          .replaceFirst('<Master ID="1"', '<Master ID="0"')
          .replaceFirst(' Master="1"', ' Master="0"');

      final imported = parseVisio(
        Uint8List.fromList(utf8.encode(source)),
        sourceName: 'master-zero.vdx',
      );
      expect(imported.document.masters.find(0), isNotNull);

      final reopened = parseVisio(
        imported.originalBytes,
        sourceName: 'master-zero.vsdx',
      ).document;
      expect(reopened.masters.find(0), isNull);
      expect(reopened.masters.find(1), isNotNull);
      expect(reopened.pages.single.findShapeById(1)!.masterId, 1);

      final package = VsdxPackage.open(imported.originalBytes);
      final mastersXml = package.readPartXml('/visio/masters/masters.xml')!;
      final emittedIds = mastersXml.rootElement.childElements
          .where((element) => element.name.local == 'Master')
          .map((element) => int.parse(element.getAttribute('ID')!));
      expect(emittedIds, everyElement(greaterThan(0)));
    });

    test('synthesised master parts retain embedded image relationships', () {
      final imported = parseVisio(_fixture(), sourceName: 'master-image.vdx');
      final document = imported.document;
      final master = document.masters.find(1)!;
      final image = document.images.all.first;
      final imageMaster = VsdxMaster(
        id: master.id,
        name: master.name,
        prototype: master.prototype.copyWith(
          imagePartName: image.partName,
          foreignType: image.foreignType,
          foreignCompressionType: image.compressionType,
        ),
        additionalPrototypes: master.additionalPrototypes,
        pageWidthInches: master.pageWidthInches,
        pageHeightInches: master.pageHeightInches,
        pageSheet: master.pageSheet,
      );

      final bytes = synthesizeVsdx(document.copyWith(
        masters: MasterRegistry(<int, VsdxMaster>{1: imageMaster}),
      ));
      final package = VsdxPackage.open(bytes);
      final relationships = RelationshipResolver(package);
      expect(
        relationships.targetsOfType(
          '/visio/masters/master1.xml',
          VsdxRelType.image,
        ),
        <String>[image.partName],
      );
      expect(package.readPartBytes(image.partName), isNotNull);

      final reopened = const DocumentParser().parse(bytes);
      final reopenedImageMaster = reopened.masters.find(1)!;
      expect(reopenedImageMaster.prototype.imagePartName, image.partName);
      expect(reopened.images.findByPart(image.partName), isNotNull);
    });

    test('VSX extracts masters as pages; VTX imports drawing pages', () {
      final source = _fixture();
      final stencil = parseVisio(source, sourceName: 'coverage.vsx');
      expect(stencil.document.pages, hasLength(1));
      expect(stencil.document.pages.single.name, 'Master Rectangle');
      expect(stencil.document.pages.single.shapes, hasLength(1));
      expect(
        stencil.document.pages.single.shapes.single.richText.plainText,
        'Master fallback text',
      );
      expect(
        const DocumentParser().parse(stencil.originalBytes).pages,
        hasLength(1),
      );

      final template = parseVisio(source, sourceName: 'coverage.vtx');
      expect(template.document.pages.single.name, 'Coverage');
      expect(_allShapes(template.document), hasLength(10));
    });

    test('uses V caches for whitespace-only leaves and sniffs bitmap payloads',
        () {
      final xml = utf8
          .decode(_fixture())
          .replaceFirst(
            '<PinX>2</PinX>',
            '<PinX V="2">\n  </PinX>',
          )
          .replaceFirst(
            ' ForeignType="Bitmap" CompressionType="PNG"',
            ' ForeignType="Bitmap"',
          );
      final result = parseVisio(
        Uint8List.fromList(utf8.encode(xml)),
        sourceName: 'third-party.vdx',
      );

      expect(result.document.pages.single.findShapeById(1)!.pinX, 2);
      final imageShape = result.document.pages.single.findShapeById(8)!;
      final image = result.document.images.findByPart(
        imageShape.imagePartName!,
      )!;
      expect(image.mimeType, 'image/png');
      expect(image.bytes.sublist(0, 4), <int>[0x89, 0x50, 0x4E, 0x47]);
    });

    test('renders empty fld markers from DiagramML Field.Value caches', () {
      final imported = parseVisio(
        _fixture(),
        sourceName: 'field-cache.vdx',
      );
      final shape = imported.document.pages.single.findShapeById(2)!;

      expect(shape.fields, hasLength(1));
      expect(shape.fields.single.value, 'Cached field text');
      expect(
        shape.richText.plainText,
        'Bezier, arcs, ellipse: Cached field text',
      );
      expect(shape.richText.runs.single.fieldSpans, hasLength(1));
      expect(
        VsdxToSvgSerializer().serializePage(
          imported.document.pages.single,
          images: imported.document.images,
        ),
        contains('Bezier, arcs, ellipse: Cached field text'),
      );

      final reopened = const DocumentParser().parse(imported.originalBytes);
      final reopenedShape = reopened.pages.single.findShapeById(2)!;
      expect(reopenedShape.fields.single.value, 'Cached field text');
      expect(
        reopenedShape.richText.plainText,
        'Bezier, arcs, ellipse: Cached field text',
      );
      expect(reopenedShape.richText.runs.single.fieldSpans, hasLength(1));
    });

    test('libvisio keeps one character for an unused first cp row', () {
      final shape = XmlDocument.parse('''
<Shape>
  <Section N="Character">
    <Row IX="0"><Cell N="Style" V="1"/></Row>
    <Row IX="1"><Cell N="Style" V="0"/></Row>
  </Section>
  <Text><cp IX="1"/>AB</Text>
</Shape>
''').rootElement;
      final richText = const RichTextParser(
        useDiagramMlCharacterCounts: true,
      ).parse(shape);

      expect(richText.runs.map((run) => run.text), <String>['A', 'B']);
      expect(richText.runs.first.charStyle.style.bold, isTrue);
      expect(richText.runs.last.charStyle.style.bold, isFalse);
    });

    test('accepts UTF-16/32 DiagramML and rejects unrelated XML', () {
      final xml = utf8.decode(_fixture());
      final units = xml.codeUnits;
      final utf16le = BytesBuilder(copy: false)..add(const <int>[0xFF, 0xFE]);
      for (final unit in units) {
        utf16le.add(<int>[unit & 0xFF, unit >> 8]);
      }
      final bytes = utf16le.takeBytes();
      expect(looksLikeVdx(bytes), isTrue);
      expect(
        parseVisio(bytes, sourceName: 'utf16.vdx').document.pages,
        hasLength(1),
      );

      for (final littleEndian in const <bool>[true, false]) {
        for (final bom in const <bool>[true, false]) {
          final declaration = littleEndian ? 'UTF-32LE' : 'UTF-32BE';
          final utf32 = _utf32(
            xml.replaceFirst('encoding="UTF-8"', 'encoding="$declaration"'),
            littleEndian: littleEndian,
            bom: bom,
          );
          expect(looksLikeVdx(utf32), isTrue, reason: '$declaration bom=$bom');
          expect(
            parseVisio(utf32, sourceName: 'utf32.vdx').document.pages,
            hasLength(1),
            reason: '$declaration bom=$bom',
          );
        }
      }

      final unrelated = Uint8List.fromList(utf8.encode('<root/>'));
      expect(looksLikeVdx(unrelated), isFalse);
      expect(() => parseVisio(unrelated), throwsA(isA<VsdxFormatException>()));
    });

    test('opens DiagramML with a foreign or absent namespace, like libvisio',
        () {
      // libvisio's `isXmlVisioDocument` reads forward to the first element and
      // compares only its name, so LibreOffice opens DiagramML whatever the
      // namespace says. Demanding a known Visio namespace made third-party and
      // namespace-stripped files unopenable here while they opened there.
      final xml = utf8.decode(_fixture());
      final expected = const VdxDocumentParser().parse(_fixture());

      for (final variant in <String, String>{
        'no namespace': xml.replaceAll(RegExp(r'\sxmlns(:\w+)?="[^"]*"'), ''),
        'foreign namespace': xml.replaceFirst(
          'http://schemas.microsoft.com/visio/2003/core',
          'http://example.invalid/visio/9999/core',
        ),
        'leading comment': xml.replaceFirst(
          '<VisioDocument',
          '<!-- exported by a third party tool --><VisioDocument',
        ),
      }.entries) {
        final bytes = Uint8List.fromList(utf8.encode(variant.value));
        expect(looksLikeVdx(bytes), isTrue, reason: variant.key);
        final document =
            parseVisio(bytes, sourceName: 'variant.vdx').document;
        expect(document.pages, hasLength(expected.pages.length),
            reason: variant.key);
        expect(
          document.pages.single.shapes.length,
          expected.pages.single.shapes.length,
          reason: variant.key,
        );
      }

      // A comment mentioning the root element is not a Visio document.
      final commentOnly = Uint8List.fromList(
        utf8.encode('<?xml version="1.0"?><!-- <VisioDocument> --><other/>'),
      );
      expect(looksLikeVdx(commentOnly), isFalse);
    });

    test('honours declared single- and multi-byte XML encodings end to end',
        () {
      final source = utf8.decode(_fixture());
      final cases = <({String declaration, Encoding codec, String text})>[
        (
          declaration: 'windows-1252',
          codec: charset.windows1252,
          text: 'Résumé “VDX” — €',
        ),
        (
          declaration: 'Shift_JIS',
          codec: charset.shiftJis,
          text: '日本語のVDX往復',
        ),
        (
          declaration: 'GBK',
          codec: charset.gbk,
          text: '简体中文VDX往返',
        ),
        (
          declaration: 'Big5',
          codec: const enough.Big5Codec(),
          text: '繁體中文VDX往返',
        ),
        (
          declaration: 'EUC-KR',
          codec: const korean.CP949Codec(allowInvalid: true),
          text: '한국어 VDX 왕복',
        ),
      ];

      for (final testCase in cases) {
        final xml = source
            .replaceFirst(
                'encoding="UTF-8"', 'encoding="${testCase.declaration}"')
            .replaceFirst(
              'DiagramML parser coverage',
              testCase.text,
            )
            .replaceFirst(
              'Spline, NURBS, infinite line',
              testCase.text,
            );
        final bytes = Uint8List.fromList(testCase.codec.encode(xml));
        expect(looksLikeVdx(bytes), isTrue, reason: testCase.declaration);

        final imported = parseVisio(
          bytes,
          sourceName: 'encoded-${testCase.declaration}.vdx',
        );
        expect(imported.document.title, testCase.text);
        expect(
          imported.document.pages.single.findShapeById(10)!.richText.plainText,
          testCase.text,
        );
        expect(
          VsdxToSvgSerializer().serializePage(
            imported.document.pages.single,
            images: imported.document.images,
          ),
          contains(testCase.text),
        );

        final reopened = const DocumentParser().parse(imported.originalBytes);
        expect(reopened.title, testCase.text);
        expect(
          reopened.pages.single.findShapeById(10)!.richText.plainText,
          testCase.text,
        );
      }
    });
  });
}
