/// Fill, line and Rounding types must paint here, and a save must emit the
/// cells / rows LibreOffice's libvisio importer still collects.
///
/// `VSDXParser` has no FillGradient token and no shape-level Rounding, so a
/// modern gradient with FillPattern=1, or a polyline with only a Rounding
/// cell, disappears in Draw. The writer rewrites those to classic FillPattern
/// 25–40 and baked RelQuadBezTo corners.
library;

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

import 'support/libvisio_oracle.dart';

void main() {
  const writer = VsdxWriter();
  const parser = DocumentParser();

  test('classic FillPattern 2–40 and modern FillGradient paint and save', () {
    final blank = writer.emptyDocument();
    var doc = parser.parse(blank);
    final page = doc.pages.first;
    var nextId = page.nextFreeShapeId();
    var built = page;

    VsdxShape box(String name, VsdxFill fill, {VsdxLine? line}) {
      return VsdxShapeFactory.rectangle(
        id: nextId++,
        pinX: 2,
        pinY: 4,
        width: 1.4,
        height: 0.7,
        name: name,
        fill: fill,
        line: line ?? const VsdxLine(color: VsdxColor.black, pattern: 0),
      );
    }

    for (final pattern in <int>[2, 8, 24, 25, 27, 35, 40]) {
      built = built.addShape(
        box(
          'Fill$pattern',
          VsdxFill(
            foreground: const VsdxColor(0xFFFF0000),
            background: const VsdxColor(0xFF0000FF),
            pattern: pattern,
          ),
        ),
      );
    }
    built = built.addShape(
      box(
        'FillGradient',
        const VsdxFill(
          foreground: VsdxColor(0xFFFF0000),
          background: VsdxColor(0xFF0000FF),
          pattern: 1,
          gradient: VsdxGradient(
            stops: [
              VsdxGradientStop(position: 0, color: VsdxColor(0xFFFF0000)),
              VsdxGradientStop(position: 1, color: VsdxColor(0xFF0000FF)),
            ],
          ),
        ),
      ),
    );
    built = built.addShape(
      box(
        'Rounding',
        const VsdxFill(foreground: VsdxColor(0xFFFFFF00), pattern: 1),
        line: const VsdxLine(
          color: VsdxColor.black,
          roundingInches: 0.15,
        ),
      ),
    );
    for (final pattern in <int>[2, 10, 23]) {
      built = built.addShape(
        VsdxShape(
          id: nextId++,
          name: 'Dash$pattern',
          pinX: 5,
          pinY: 4,
          width: 2,
          height: 0.2,
          geometries: const <VsdxGeometry>[
            VsdxGeometry(
              noFill: true,
              commands: <VsdxPathCommand>[MoveTo(0, 0.1), LineTo(2, 0.1)],
            ),
          ],
          line: VsdxLine(
            color: const VsdxColor(0xFF000000),
            pattern: pattern,
            beginArrow: pattern == 2 ? 4 : 0,
            endArrow: pattern == 2 ? 13 : 0,
          ),
        ),
      );
    }

    doc = doc.replacePage(0, built);
    final svg = VsdxToSvgSerializer().serializePage(doc.pages.first);
    expect(svg, contains('<pattern'), reason: 'hatch FillPattern 2–24');
    expect(svg, contains('linearGradient'), reason: 'linear classic / FillGradient');
    expect(svg, contains('radialGradient'), reason: 'FillPattern 35–40');
    expect(svg, contains('stroke-dasharray="'), reason: 'LinePattern 2–23');
    expect(svg, contains('<marker'), reason: 'BeginArrow / EndArrow');
    expect(RegExp(r'\bQ ').hasMatch(svg), isTrue, reason: 'Rounding fillets');

    final saved = writer.write(originalBytes: blank, edited: doc);
    final xml = VsdxPackage.open(saved)
        .readPartXml('/visio/pages/page1.xml')!
        .toXmlString();
    expect(xml, contains('T="RelQuadBezTo"'), reason: 'Rounding bakes for LO');
    expect(
      xml.contains('N="FillPattern" V="1"') &&
          xml.contains('N="FillGradientEnabled" V="1"'),
      isTrue,
    );
    // Modern FillGradient must also carry a classic id libvisio collects.
    expect(
      RegExp(r'N="FillPattern" V="(2[5-9]|3[0-9]|40)"').hasMatch(xml),
      isTrue,
      reason: 'FillGradient fallback must be FillPattern 25–40',
    );

    final oracle = LibvisioOracle.tryLoad();
    if (oracle == null) return;
    final after = oracle.svgPages(saved)?.join() ?? '';
    expect(after, isNotEmpty);
    expect(
      after.contains('linearGradient') || after.contains('radialGradient'),
      isTrue,
      reason: 'libvisio must paint classic / rewritten gradients',
    );
    expect(RegExp(r'\nQ').hasMatch(after), isTrue,
        reason: 'libvisio must collect baked Rounding corners');
    expect(
      after.contains('stroke-dasharray') || after.contains('draw:stroke'),
      isTrue,
    );
  });
}
