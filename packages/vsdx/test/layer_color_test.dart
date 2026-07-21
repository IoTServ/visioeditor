import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  test('layerColorSource picks first coloured membership', () {
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
    ];
    expect(layerColorSource(layers, const <int>[]), isNull);
    expect(layerColorSource(layers, const <int>[0])?.color, isNull);
    final hit = layerColorSource(layers, const <int>[0, 2, 1]);
    expect(hit?.id, 2);
    expect(hit?.color?.value, 0xFF00FF00);
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
}
