import 'package:test/test.dart';
import 'package:vsdx/stencils.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  final migrated = kStencilGroups
      .where((group) => group.name.startsWith('Draw.io / '))
      .toList(growable: false);
  final dynamic = kStencilGroups
      .where((group) => group.name.startsWith('Draw.io JS / '))
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

  test('draw.io JavaScript Canvas catalog exposes captured native shapes', () {
    expect(dynamic, hasLength(63));
    expect(
      dynamic.fold<int>(0, (sum, group) => sum + group.stencils.length),
      959,
    );
    expect(
      dynamic.map((group) => group.name).toSet(),
      hasLength(dynamic.length),
    );
    expect(
      kDefaultStencilGroupNames,
      isNot(contains(startsWith('Draw.io JS / '))),
    );
  });

  test(
    'all captured JavaScript Canvas shapes decode without placeholders',
    () {
      var id = 1;
      var geometryCount = 0;
      var commandCount = 0;
      for (final group in dynamic) {
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
      expect(geometryCount, greaterThan(2000));
      expect(commandCount, greaterThan(20000));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

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

  test('JavaScript Canvas shapes survive VSDX round-trip', () {
    Stencil stencil(String groupName, String shapeName) => dynamic
        .singleWhere((group) => group.name == groupName)
        .stencils
        .singleWhere((entry) => entry.name == shapeName);

    final samples = <Stencil>[
      stencil('Draw.io JS / AWS3D / AWS 3D', 'AMI'),
      stencil(
        'Draw.io JS / ArchiMate3 / Archimate 3.2 / Generic',
        'Internal Active Structure Element',
      ),
      stencil('Draw.io JS / Sysml / SysML / Ports and Flows', 'Port'),
      stencil('Draw.io JS / UML25 / uml 2.5', 'Input Pin'),
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
    expect(reopened.pages.first.shapes, hasLength(samples.length));
    expect(
      reopened.pages.first.shapes.every((shape) => shape.geometries.isNotEmpty),
      isTrue,
    );
  });
}
