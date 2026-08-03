import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  test('layerColorSource requires identical colours on every membership', () {
    final layers = <VsdxLayer>[
      const VsdxLayer(id: 0, name: 'A'),
      const VsdxLayer(
        id: 1,
        name: 'B',
        color: VsdxColor(0xFFFF0000),
        colorTrans: 0.25,
      ),
      const VsdxLayer(
        id: 2,
        name: 'C',
        color: VsdxColor(0xFF00FF00),
      ),
      const VsdxLayer(
        id: 3,
        name: 'D',
        color: VsdxColor(0xFFFF0000),
        colorTrans: 0.25,
      ),
      const VsdxLayer(
        id: 4,
        name: 'E',
        color: VsdxColor(0xFFFF0000),
        colorTrans: 0.5,
      ),
    ];
    expect(layerColorSource(layers, const <int>[]), isNull);
    expect(layerColorSource(layers, const <int>[0])?.color, isNull);
    expect(layerColorSource(layers, const <int>[99]), isNull);
    expect(layerColorSource(layers, const <int>[0, 1]), isNull);
    expect(layerColorSource(layers, const <int>[1, 2]), isNull);
    expect(layerColorSource(layers, const <int>[1, 4]), isNull);
    final hit = layerColorSource(layers, const <int>[1, 3]);
    expect(hit?.id, 1);
    expect(hit?.color?.value, 0xFFFF0000);
    expect(hit?.colorTrans, 0.25);
  });

  test('unknown layer membership remains visible and printable', () {
    const layers = <VsdxLayer>[
      VsdxLayer(id: 0, name: 'Hidden', visible: false, print: false),
    ];
    expect(
      layerMembershipEnabled(layers, const <int>[0], const <int>{}),
      isFalse,
    );
    expect(
      layerMembershipEnabled(layers, const <int>[0, 99], const <int>{}),
      isTrue,
    );
    expect(
      layerMembershipEnabled(layers, const <int>[99], const <int>{}),
      isTrue,
    );
  });

  test('layer consensus and memberships survive VSDX synthesis', () {
    const red = VsdxColor(0xFFCC0000);
    final writer = VsdxWriter();
    final empty = writer.emptyDocument();
    final parsed = const DocumentParser().parse(empty);
    final page = parsed.pages.single.copyWith(
      layers: const <VsdxLayer>[
        VsdxLayer(id: 0, name: 'Red A', color: red, colorTrans: 0.25),
        VsdxLayer(id: 1, name: 'Red B', color: red, colorTrans: 0.25),
        VsdxLayer(
          id: 2,
          name: 'Green',
          color: VsdxColor(0xFF00AA00),
          colorTrans: 0.25,
        ),
      ],
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 1,
          pinX: 2,
          pinY: 2,
          width: 1,
          height: 1,
          fill: const VsdxFill(foreground: VsdxColor(0xFF0000CC)),
        ).copyWith(layerMemberIds: const <int>[0, 1]),
        VsdxShapeFactory.rectangle(
          id: 2,
          pinX: 4,
          pinY: 2,
          width: 1,
          height: 1,
          fill: const VsdxFill(foreground: VsdxColor(0xFF0000CC)),
        ).copyWith(layerMemberIds: const <int>[0, 2]),
      ],
    );
    final saved = writer.write(
      originalBytes: empty,
      edited: parsed.replacePage(0, page),
    );
    final reopened = const DocumentParser().parse(saved).pages.single;

    expect(reopened.layers, page.layers);
    expect(reopened.shapes[0].layerMemberIds, const <int>[0, 1]);
    expect(reopened.shapes[1].layerMemberIds, const <int>[0, 2]);
    expect(
      layerColorSource(reopened.layers, reopened.shapes[0].layerMemberIds)
          ?.color,
      red,
    );
    expect(
      layerColorSource(reopened.layers, reopened.shapes[1].layerMemberIds),
      isNull,
    );
  });

  test('SVG Color-by-Layer overrides fill and stroke hex', () {
    final page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 8,
      heightInches: 11,
      layers: const <VsdxLayer>[
        VsdxLayer(
          id: 0,
          name: 'Red',
          color: VsdxColor(0xFFCC0000),
        ),
      ],
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 1,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1,
          fill: const VsdxFill(foreground: VsdxColor(0xFF00FF00)),
          line: const VsdxLine(color: VsdxColor(0xFF0000FF), weightInches: 0.02),
        ).copyWith(layerMemberIds: const <int>[0]),
      ],
    );
    final plain = VsdxToSvgSerializer().serializePage(page);
    expect(plain.toLowerCase(), contains('#00ff00'));
    expect(plain.toLowerCase(), contains('#0000ff'));

    final tinted =
        VsdxToSvgSerializer(colorByLayer: true).serializePage(page);
    expect(tinted.toLowerCase(), contains('#cc0000'));
    expect(tinted.toLowerCase().contains('#00ff00'), isFalse);
    expect(tinted.toLowerCase().contains('#0000ff'), isFalse);
  });

  test('SVG Color-by-Layer inherits a group layer tint into children', () {
    var page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 8,
      heightInches: 11,
      layers: const <VsdxLayer>[
        VsdxLayer(
          id: 0,
          name: 'Red',
          color: VsdxColor(0xFFCC0000),
        ),
      ],
      shapes: <VsdxShape>[
        VsdxShapeFactory.rectangle(
          id: 1,
          pinX: 2,
          pinY: 2,
          width: 1,
          height: 1,
          fill: const VsdxFill(foreground: VsdxColor(0xFF00FF00)),
        ),
        VsdxShapeFactory.rectangle(
          id: 2,
          pinX: 4,
          pinY: 2,
          width: 1,
          height: 1,
          fill: const VsdxFill(foreground: VsdxColor(0xFF0000FF)),
        ),
      ],
    );
    page = page.group(const <int>{1, 2}, groupId: 3);
    page = page.updateShapeById(
      3,
      (group) => group.copyWith(layerMemberIds: const <int>[0]),
    );

    final tinted =
        VsdxToSvgSerializer(colorByLayer: true).serializePage(page);
    expect(tinted.toLowerCase(), contains('#cc0000'));
    expect(tinted.toLowerCase().contains('#00ff00'), isFalse);
    expect(tinted.toLowerCase().contains('#0000ff'), isFalse);
  });
}
