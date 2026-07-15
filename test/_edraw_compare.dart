// Dev-only visual compat harness; print() is intentional diagnostic output.
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:visioeditor/io/image_export.dart';
import 'package:vsdx/vsdx.dart';

import '../packages/vsdx/test/support/libvisio_oracle.dart';

/// Load a system CJK face under the Visio/Edraw family names so headless
/// Flutter tests can paint Chinese labels (no Microsoft YaHei on macOS CI).
Future<void> _loadCjkTestFonts() async {
  const path = '/Library/Fonts/RODE Noto Sans CJK SC R.otf';
  final file = File(path);
  if (!file.existsSync()) return;
  final bytes = ByteData.sublistView(file.readAsBytesSync());
  for (final family in const [
    'Microsoft YaHei',
    'PingFang SC',
    'Hiragino Sans GB',
    'Heiti SC',
    'Noto Sans CJK SC',
  ]) {
    final loader = FontLoader(family)..addFont(Future.value(bytes));
    await loader.load();
  }
}

Future<void> _renderAndDump(
  String tag,
  Uint8List bytes,
  VsdxDocument doc,
  LibvisioOracle oracle,
) async {
  final png = await renderPageToPng(
    doc.pages.first,
    theme: doc.theme,
    images: doc.images,
    pxPerInch: 96,
  );
  expect(png, isNotNull);
  File('/tmp/edraw_${tag}_ours.png').writeAsBytesSync(png!);
  final ourSvg = VsdxToSvgSerializer().serializePage(
    doc.pages.first,
    theme: doc.theme,
    images: doc.images,
  );
  File('/tmp/edraw_${tag}_ours.svg').writeAsStringSync(ourSvg);
  final libPages = oracle.svgPages(bytes);
  expect(libPages, isNotNull);
  File('/tmp/edraw_${tag}_libvisio.svg').writeAsStringSync(libPages!.first);
  File('/tmp/edraw_${tag}_export.vsdx').writeAsBytesSync(bytes);
  print('$tag ours=${png.length} libvisio=${libPages.first.length}');
}

/// Build → export → render (ours + libvisio) for Edraw compatibility review.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('export rich diagrams and compare ours vs libvisio', () async {
    await _loadCjkTestFonts();
    final oracle = LibvisioOracle.tryLoad();
    expect(oracle, isNotNull, reason: 'need libvisio for Edraw-proxy compare');

    // Place the flowchart around the page centre so ViewCenter opens on it.
    final c = EditorController()
      ..newDocument(widthInches: 8.5, heightInches: 11);
    addTearDown(c.dispose);

    c.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 0.9),
        4.25,
        7.5);
    final a = c.singleSelectedId!;
    c
      ..setFillColor(const VsdxColor(0xFF42A5F5))
      ..setLineColor(const VsdxColor(0xFF1565C0))
      ..setShapeText(a, '开始');

    c.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.polygon(
              id: id,
              pinX: cx,
              pinY: cy,
              width: 1.6,
              height: 1.0,
              unit: const [
                Offset2D(0.5, 1),
                Offset2D(1, 0.5),
                Offset2D(0.5, 0),
                Offset2D(0, 0.5),
              ],
            ),
        4.25,
        5.5);
    final b = c.singleSelectedId!;
    c
      ..setFillColor(const VsdxColor(0xFFFFCA28))
      ..setLineColor(const VsdxColor(0xFFF57F17))
      ..setShapeText(b, '判断');

    c.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.ellipse(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 0.9),
        4.25,
        3.5);
    final d = c.singleSelectedId!;
    c
      ..setFillColor(const VsdxColor(0xFF66BB6A))
      ..setLineColor(const VsdxColor(0xFF2E7D32))
      ..setShapeText(d, '结束');

    c.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 0.8),
        6.5,
        5.5);
    final side = c.singleSelectedId!;
    c
      ..setFillColor(const VsdxColor(0xFFEF5350))
      ..setLineColor(const VsdxColor(0xFFC62828))
      ..setShapeText(side, '分支');

    c.createConnector(4.25, 7.05, 4.25, 6.0, beginTarget: a, endTarget: b);
    c
      ..setEndArrow(4)
      ..setLineColor(const VsdxColor(0xFF37474F));
    c.createConnector(4.25, 5.0, 4.25, 3.95, beginTarget: b, endTarget: d);
    c
      ..setEndArrow(4)
      ..setLineColor(const VsdxColor(0xFF37474F));
    c.createConnector(5.05, 5.5, 5.8, 5.5, beginTarget: b, endTarget: side);
    c
      ..setEndArrow(12)
      ..setLineColor(const VsdxColor(0xFF6A1B9A));

    final flowBytes = c.exportToBytes();
    File('assets/examples/edraw_compat_demo.vsdx').writeAsBytesSync(flowBytes);
    await _renderAndDump('flow', Uint8List.fromList(flowBytes), c.document!, oracle!);

    // --- Demo B: style stress (dash, weight, round, bold, ball arrow) ---
    final c2 = EditorController()
      ..newDocument(widthInches: 8.5, heightInches: 11);
    addTearDown(c2.dispose);

    c2.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.roundedRectangle(
            id: id, pinX: cx, pinY: cy, width: 1.8, height: 0.9),
        3.0,
        9.0);
    final r1 = c2.singleSelectedId!;
    c2
      ..setFillColor(const VsdxColor(0xFF7E57C2))
      ..setLineColor(const VsdxColor(0xFF4527A0))
      ..setLineWeight(0.03)
      ..setShapeText(r1, '圆角粗边');

    c2.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id, pinX: cx, pinY: cy, width: 1.8, height: 0.9),
        5.5,
        9.0);
    final r2 = c2.singleSelectedId!;
    c2
      ..setFillColor(const VsdxColor(0xFFFF7043))
      ..setLineColor(const VsdxColor(0xFFBF360C))
      ..setLinePattern(2) // dashed
      ..setShapeText(r2, '虚线框');

    c2.createConnector(3.9, 9.0, 4.6, 9.0, beginTarget: r1, endTarget: r2);
    c2
      ..setEndArrow(10) // filled circle / ball
      ..setBeginArrow(4)
      ..setLineColor(const VsdxColor(0xFF00695C))
      ..setLineWeight(0.02);

    c2.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.ellipse(
            id: id, pinX: cx, pinY: cy, width: 1.5, height: 1.5),
        4.25,
        7.0);
    final circle = c2.singleSelectedId!;
    c2
      ..setFillColor(const VsdxColor(0xFF26A69A))
      ..setLineColor(const VsdxColor(0xFF004D40))
      ..setShapeText(circle, '粗体字');
    c2.setBold(true);

    final styleBytes = c2.exportToBytes();
    await _renderAndDump(
        'style', Uint8List.fromList(styleBytes), c2.document!, oracle);

    // --- Untitled333 re-save ---
    final u333 = File('assets/examples/Untitled333.vsdx').readAsBytesSync();
    final uParsed = const DocumentParser().parse(Uint8List.fromList(u333));
    final uFixed = const VsdxWriter().write(
      originalBytes: Uint8List.fromList(u333),
      edited: uParsed,
    );
    File('assets/examples/Untitled333_edraw_fixed.vsdx').writeAsBytesSync(uFixed);
    await _renderAndDump('u333', Uint8List.fromList(uFixed), uParsed, oracle);

    // Structural checks on flow export
    final pageXml = String.fromCharCodes(
      VsdxPackage.open(Uint8List.fromList(flowBytes))
          .readPartBytes('/visio/pages/page1.xml')!,
    );
    expect(pageXml.contains('N="NoFill" V="0"'), isTrue);
    expect(pageXml.contains('N="LocPinX"'), isTrue);
    expect(pageXml.contains('AsianFont'), isTrue);
    expect(pageXml.contains('N="TxtPinX"'), isTrue);
    expect(pageXml.contains('Microsoft YaHei'), isTrue);

    final styleXml = String.fromCharCodes(
      VsdxPackage.open(Uint8List.fromList(styleBytes))
          .readPartBytes('/visio/pages/page1.xml')!,
    );
    expect(styleXml.contains('N="EndArrow" V="10"'), isTrue);
    expect(styleXml.contains('N="LinePattern" V="2"'), isTrue);
    // Circle must not inherit connector arrowheads (memo-style fix).
    final styleDoc =
        const DocumentParser().parse(Uint8List.fromList(styleBytes));
    final boldCircle = styleDoc.pages.first.shapes
        .where((s) => !s.is1D && (s.text?.contains('粗体') ?? false))
        .single;
    expect(boldCircle.line.endArrow, 0);
    expect(boldCircle.line.beginArrow, 0);
    print('NoFill0=${RegExp(r'N="NoFill" V="0"').allMatches(pageXml).length}');
    print('style EndArrow10 + dash ok; circle has no arrows');
  });
}
