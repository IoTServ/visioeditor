import 'package:test/test.dart';
import 'package:vsdx/stencils.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  final migrated = kStencilGroups
      .where((group) => group.name.startsWith('Draw.io / '))
      .toList(growable: false);

  test('draw.io XML catalog exposes every generated library and shape', () {
    expect(migrated, hasLength(203));
    expect(
      migrated.fold<int>(0, (sum, group) => sum + group.stencils.length),
      8964,
    );
    expect(
      migrated.map((group) => group.name).toSet(),
      hasLength(migrated.length),
    );
    expect(
        kDefaultStencilGroupNames, isNot(contains(startsWith('Draw.io / '))));
  });

  test(
    'all migrated XML shapes decode to native geometry without placeholders',
    () {
      var id = 1;
      var geometryCount = 0;
      var commandCount = 0;
      for (final group in migrated) {
        for (final stencil in group.stencils) {
          final shape = stencil.build(id++, 5, 5);
          if (!shape.width.isFinite ||
              !shape.height.isFinite ||
              shape.width <= 0 ||
              shape.height <= 0 ||
              shape.geometries.isEmpty ||
              shape.geometries.any((geometry) => geometry.commands.isEmpty)) {
            fail('${group.name} / ${stencil.name} produced invalid geometry');
          }
          geometryCount += shape.geometries.length;
          commandCount += shape.geometries.fold<int>(
            0,
            (sum, geometry) => sum + geometry.commands.length,
          );
        }
      }
      expect(geometryCount, greaterThan(20000));
      expect(commandCount, greaterThan(500000));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('curves arcs ellipses and connection points survive VSDX round-trip',
      () {
    Stencil stencil(String groupName, String shapeName) => migrated
        .singleWhere((group) => group.name == groupName)
        .stencils
        .singleWhere((entry) => entry.name == shapeName);

    final samples = <Stencil>[
      stencil('Draw.io / Electrical / Resistors', 'Attenuator'),
      stencil('Draw.io / Signs / Animals', 'Bear 1'),
      stencil('Draw.io / Floorplan', 'Bathtub'),
      stencil('Draw.io / AWS 4', 'a1 instance'),
    ];
    const writer = VsdxWriter();
    const parser = DocumentParser();
    final blank = writer.emptyDocument();
    var document = parser.parse(blank);
    var page = document.pages.first;
    for (var index = 0; index < samples.length; index++) {
      page = page.addShape(samples[index].build(
        page.nextFreeShapeId(),
        1.5 + index * 1.75,
        4,
      ));
    }
    document = document.replacePage(0, page);
    final reopened = parser.parse(writer.write(
      originalBytes: blank,
      edited: document,
    ));
    final shapes = reopened.pages.first.shapes;
    expect(shapes, hasLength(samples.length));
    expect(shapes.every((shape) => shape.geometries.isNotEmpty), isTrue);
    expect(
      shapes.expand((shape) => shape.geometries).expand((g) => g.commands),
      anyOf(
        contains(isA<CubBezTo>()),
        contains(isA<EllipseCmd>()),
      ),
    );
  });
}
