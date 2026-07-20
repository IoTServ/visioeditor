// Stacked style-property write→parse→write + SVG + identity template rewrite.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  final writer = const VsdxWriter();
  final parser = DocumentParser();

  test('stacked style props survive write→parse→write and SVG', () {
    final blank = writer.emptyDocument(widthInches: 11, heightInches: 8.5);
    var doc = parser.parse(blank);
    final fillGrad = VsdxGradient(
      type: VsdxGradientType.linear,
      angleRad: math.pi / 4,
      stops: const [
        VsdxGradientStop(position: 0, color: VsdxColor(0xFF1D4ED8)),
        VsdxGradientStop(position: 1, color: VsdxColor(0xFF93C5FD)),
      ],
    );
    final lineGrad = VsdxGradient(
      type: VsdxGradientType.linear,
      angleRad: math.pi / 2,
      stops: const [
        VsdxGradientStop(position: 0, color: VsdxColor(0xFFDC2626)),
        VsdxGradientStop(position: 1, color: VsdxColor(0xFFFDE68A)),
      ],
    );
    final shape = VsdxShapeFactory.roundedRectangle(
      id: 1,
      pinX: 3,
      pinY: 4,
      width: 2.5,
      height: 1.5,
      fill: VsdxFill(
        foreground: const VsdxColor(0xFF3B82F6),
        background: const VsdxColor(0xFF93C5FD),
        gradient: fillGrad,
      ),
      line: VsdxLine(
        color: const VsdxColor(0xFF111827),
        weightInches: 0.03,
        pattern: 2,
        beginArrow: 4,
        endArrow: 5,
        softEdgesInches: 0.04,
        compoundType: 1,
        gradient: lineGrad,
      ),
    ).copyWith(
      shadow: const VsdxShadow(
        enabled: true,
        pattern: 1,
        color: VsdxColor(0xFF000000),
        transparency: 0.4,
        offsetXInches: 0.12,
        offsetYInches: -0.08,
        blurInches: 0.06,
      ),
      glow: const VsdxGlow(
        enabled: true,
        sizeInches: 0.08,
        color: VsdxColor(0xFFF59E0B),
        transparency: 0.25,
      ),
      reflection: const VsdxReflection(
        enabled: true,
        sizeInches: 0.35,
        distanceInches: 0.05,
        blurInches: 0.02,
        transparency: 0.3,
      ),
      text: 'Stress',
      richText: VsdxRichText(runs: [
        VsdxTextRun(
          text: 'Stress',
          charStyle: const VsdxCharStyle(
            fontSizeInches: 14 / 72,
            color: VsdxColor(0xFFFFFFFF),
            style: VsdxFontStyle.boldStyle,
          ),
        ),
      ]),
    );

    doc = doc.replacePage(0, doc.pages.first.copyWith(shapes: [shape]));
    final bytes1 = writer.write(originalBytes: blank, edited: doc);
    final again = parser.parse(bytes1);
    final s1 = again.pages.first.shapes.first;

    expect(s1.fill?.hasGradient, isTrue);
    expect(s1.fill!.gradient!.angleRad, closeTo(math.pi / 4, 0.01));
    expect(s1.line.hasGradient, isTrue);
    expect(s1.line.pattern, 2);
    expect(s1.line.beginArrow, 4);
    expect(s1.line.endArrow, 5);
    expect(s1.line.softEdgesInches, closeTo(0.04, 1e-6));
    expect(s1.line.compoundType, 1);
    expect(s1.shadow?.enabled, isTrue);
    expect(s1.shadow!.offsetXInches, closeTo(0.12, 1e-6));
    expect(s1.glow?.enabled, isTrue);
    expect(s1.glow!.color?.value, 0xFFF59E0B);
    expect(s1.reflection?.enabled, isTrue);
    expect(s1.reflection!.distanceInches, closeTo(0.05, 1e-6));
    expect(s1.text, 'Stress');

    final s2 = s1.copyWith(
      glow: s1.glow!.copyWith(enabled: false),
      shadow: s1.shadow!.copyWith(enabled: false),
    );
    final bytes2 = writer.write(
      originalBytes: bytes1,
      edited: again.replacePage(0, again.pages.first.copyWith(shapes: [s2])),
    );
    final s3 = parser.parse(bytes2).pages.first.shapes.first;
    expect(s3.glow?.enabled ?? false, isFalse);
    expect(s3.shadow?.enabled ?? false, isFalse);
    expect(s3.fill?.hasGradient, isTrue);
    expect(s3.reflection?.enabled, isTrue);
    expect(s3.glow?.color?.value ?? 0xFFF59E0B, 0xFFF59E0B);

    final svg = VsdxToSvgSerializer().serializeDocument(parser.parse(bytes1));
    expect(svg, contains('linearGradient'));
    expect(
      svg.contains('feDropShadow') || svg.contains('feGaussianBlur'),
      isTrue,
    );
    expect(svg, contains('stroke-dasharray'));
  });

  test('bundled example templates reopen after identity rewrite', () {
    final dir = Directory('../../assets/examples');
    expect(dir.existsSync(), isTrue);
    var n = 0;
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.vsdx')) continue;
      final name = f.uri.pathSegments.last;
      if (name.contains('edraw') || name.startsWith('Untitled')) continue;
      final raw = Uint8List.fromList(f.readAsBytesSync());
      final d = parser.parse(raw);
      final out = writer.write(originalBytes: raw, edited: d);
      final d2 = parser.parse(out);
      expect(d2.pages.length, d.pages.length, reason: name);
      expect(d2.pages.first.shapes.length, d.pages.first.shapes.length,
          reason: name);
      // SVG export must not throw on starter templates.
      expect(
        () => VsdxToSvgSerializer().serializeDocument(d2),
        returnsNormally,
        reason: 'SVG $name',
      );
      n++;
    }
    expect(n, greaterThanOrEqualTo(20));
  });

  test('soft-edges disable keeps size for re-enable after save', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final id = doc.pages.first.nextFreeShapeId();
    final rect = VsdxShapeFactory.rectangle(
      id: id,
      pinX: 2,
      pinY: 2,
      width: 2,
      height: 1,
      line: const VsdxLine(softEdgesInches: 0.07),
    );
    doc = doc.replacePage(0, doc.pages.first.addShape(rect));
    final bytes1 = writer.write(originalBytes: blank, edited: doc);

    final mid = parser.parse(bytes1);
    final bytes2 = writer.write(
      originalBytes: bytes1,
      edited: mid.replacePage(
        0,
        mid.pages.first.updateShapeById(
          id,
          (s) => s.copyWith(line: s.line.copyWith(softEdgesInches: 0)),
        ),
      ),
    );
    final after = parser.parse(bytes2).pages.first.findShapeById(id)!;
    expect(after.line.softEdgesInches, 0);

    final reopened = parser.parse(bytes2);
    final bytes3 = writer.write(
      originalBytes: bytes2,
      edited: reopened.replacePage(
        0,
        reopened.pages.first.updateShapeById(
          id,
          (s) => s.copyWith(line: s.line.copyWith(softEdgesInches: 0.09)),
        ),
      ),
    );
    final finalS = parser.parse(bytes3).pages.first.findShapeById(id)!;
    expect(finalS.line.softEdgesInches, closeTo(0.09, 1e-6));
  });
}
