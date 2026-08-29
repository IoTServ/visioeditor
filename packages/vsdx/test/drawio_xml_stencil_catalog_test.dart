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
    expect(dynamic, hasLength(217));
    expect(
      dynamic.fold<int>(0, (sum, group) => sum + group.stencils.length),
      4960,
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

  test('draw.io library shapes use Sheet.N names without default labels', () {
    final autoName = RegExp(r'^Sheet\.\d+$');
    final samples = <Stencil>[
      migrated
          .singleWhere((group) => group.name == 'Draw.io / Signs / Animals')
          .stencils
          .singleWhere((entry) => entry.name == 'Bear 1'),
      migrated
          .singleWhere((group) => group.name == 'Draw.io / Floorplan')
          .stencils
          .singleWhere((entry) => entry.name == 'Bathtub'),
      dynamic
          .singleWhere((group) => group.name == 'Draw.io JS / AWS3D / AWS 3D')
          .stencils
          .singleWhere((entry) => entry.name == 'AMI'),
      dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / UML25 / uml 2.5',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Input Pin'),
    ];
    for (var index = 0; index < samples.length; index++) {
      final shape = samples[index].build(40 + index, 3, 3);
      expect(shape.name, matches(autoName), reason: samples[index].name);
      expect(shape.text, isNull, reason: samples[index].name);
      expect(shape.richText.isEmpty, isTrue, reason: samples[index].name);
    }
  });

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

  test('draw.io mxGraph text glyphs stay on children for LibreOffice', () {
    final stencil = migrated
        .singleWhere(
          (group) => group.name == 'Draw.io / Electrical / Iec Logic Gates',
        )
        .stencils
        .singleWhere((entry) => entry.name == 'AND');
    final shape = stencil.build(10, 3, 3);
    expect(shape.children, isNotEmpty, reason: 'IEC AND has an mxGraph <text>');
    expect(
      shape.children.any((child) => child.text == 'AND'),
      isTrue,
      reason: 'libvisio collects Text on child shapes, not skipped XML',
    );
    expect(shape.text, isNull,
        reason: 'the catalog title must not become the parent label');

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(stencil.build(id, 3, 3)),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(
      leftover.children.any((child) => child.text == 'AND'),
      isTrue,
      reason: 'a second save must keep the IEC AND glyph',
    );
  });

  test('empty mxGraph rects do not wipe the pending IEC NAND contour', () {
    final stencil = migrated
        .singleWhere(
          (group) => group.name == 'Draw.io / Electrical / Iec Logic Gates',
        )
        .stencils
        .singleWhere((entry) => entry.name == 'NAND');
    final shape = stencil.build(11, 3, 3);
    expect(shape.geometries, isNotEmpty);
    var collapsed = 0;
    for (final geometry in shape.geometries) {
      var minX = double.infinity, minY = double.infinity;
      var maxX = -double.infinity, maxY = -double.infinity;
      var hasPoint = false;
      for (final command in geometry.commands) {
        final x = switch (command) {
          MoveTo(:final x) => x,
          LineTo(:final x) => x,
          _ => null,
        };
        final y = switch (command) {
          MoveTo(:final y) => y,
          LineTo(:final y) => y,
          _ => null,
        };
        if (x == null || y == null) {
          hasPoint = true;
          minX = 0;
          maxX = 1;
          break;
        }
        hasPoint = true;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
      if (hasPoint && (maxX - minX) < 1e-9 && (maxY - minY) < 1e-9) {
        collapsed++;
      }
    }
    expect(collapsed, 0,
        reason:
            'a 0×0 <rect/> after restore must not become a degenerate fill');
  });

  test('JavaScript Canvas text and nested stencils stay in LibreOffice', () {
    Stencil stencil(String groupName, String shapeName) => dynamic
        .singleWhere((group) => group.name == groupName)
        .stencils
        .singleWhere((entry) => entry.name == shapeName);

    final icStencil = stencil(
      'Draw.io JS / Electrical / Electrical / Logic Gates',
      'Dual In-Line IC',
    );
    final ic = icStencil.build(20, 3, 3);
    expect(
      ic.children.any((child) => child.text == '1'),
      isTrue,
      reason: 'mxGraph c.text pin numbers must become child shapes',
    );

    final pod = stencil(
      'Draw.io JS / Kubernetes / Kubernetes',
      'API',
    ).build(21, 3, 3);
    expect(pod.geometries.length, greaterThan(2),
        reason: 'nested mxgraph.kubernetes.frame + icon must be inlined');

    final labeledStencil = stencil(
      'Draw.io JS / Kubernetes / Kubernetes',
      'API (2)',
    );
    final labeled = labeledStencil.build(22, 3, 3);
    expect(
      labeled.children.any((child) => child.text == 'api'),
      isTrue,
      reason: 'kubernetesLabel=1 paints c.text("api")',
    );

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final icId = doc.pages.first.nextFreeShapeId();
    var page = doc.pages.first.addShape(icStencil.build(icId, 2, 4));
    final apiId = page.nextFreeShapeId();
    page = page.addShape(labeledStencil.build(apiId, 5, 4));
    doc = doc.replacePage(0, page);
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first;
    expect(
      leftover.findShapeById(icId)!.children.any((child) => child.text == '1'),
      isTrue,
    );
    expect(
      leftover
          .findShapeById(apiId)!
          .children
          .any((child) => child.text == 'api'),
      isTrue,
    );
  });

  test('BPMN 2 tasks SysML models and Android bars capture native geometry',
      () {
    Stencil stencil(String groupName, String shapeName) => dynamic
        .singleWhere((group) => group.name == groupName)
        .stencils
        .singleWhere((entry) => entry.name == shapeName);

    final task = stencil(
      'Draw.io JS / BPMN / BPMN 2.0  Tasks',
      'User',
    ).build(30, 3, 3);
    expect(task.geometries.length, greaterThan(1),
        reason:
            'mxgraph.bpmn.task2 must load via getShape(mxgraph.basic.rect)');

    final model = stencil(
      'Draw.io JS / Sysml / SysML / Model Elements',
      'Model',
    ).build(31, 3, 3);
    expect(model.geometries, isNotEmpty,
        reason: 'mxgraph.sysml.composite paints folder via Shapes.js');

    final bar = stencil(
      'Draw.io JS / Android / android',
      'Split Action Bar',
    ).build(32, 3, 3);
    expect(bar.geometries.length, greaterThan(1),
        reason: 'vertex-cells mockups must paint built-in rectangles');

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final taskId = doc.pages.first.nextFreeShapeId();
    var page = doc.pages.first.addShape(stencil(
      'Draw.io JS / BPMN / BPMN 2.0  Tasks',
      'User',
    ).build(taskId, 2, 4));
    final modelId = page.nextFreeShapeId();
    page = page.addShape(stencil(
      'Draw.io JS / Sysml / SysML / Model Elements',
      'Model',
    ).build(modelId, 5, 4));
    doc = doc.replacePage(0, page);
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first;
    expect(leftover.findShapeById(taskId)!.geometries.length, greaterThan(1));
    expect(leftover.findShapeById(modelId)!.geometries, isNotEmpty);
  });

  test('compressed sidebar data entries capture composite geometry', () {
    Stencil stencil(String groupName, String shapeName) => dynamic
        .singleWhere((group) => group.name == groupName)
        .stencils
        .singleWhere((entry) => entry.name == shapeName);

    final dialog = stencil(
      'Draw.io JS / Mockup / Mockup Containers',
      'Dialog Box',
    ).build(40, 3, 3);
    expect(dialog.geometries.length, greaterThan(2),
        reason: 'addDataEntry mxGraphModel cells must become native geometry');
    expect(
      dialog.children.any((child) => (child.text ?? '').isNotEmpty),
      isTrue,
      reason: 'cell labels must become Text children for LibreOffice',
    );

    final partition = stencil(
      'Draw.io JS / UML25 / uml 2.5',
      'Activity Partition',
    ).build(41, 3, 3);
    expect(partition.geometries, isNotEmpty);

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(stencil(
        'Draw.io JS / Mockup / Mockup Containers',
        'Dialog Box',
      ).build(id, 3, 3)),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(leftover.geometries.length, greaterThan(2));
    expect(
      leftover.children.any((child) => (child.text ?? '').isNotEmpty),
      isTrue,
    );
  });

  test('Cisco Truck keeps mxStencil path ops issued outside path', () {
    final stencil = migrated
        .singleWhere((group) => group.name == 'Draw.io / Cisco / Misc')
        .stencils
        .singleWhere((entry) => entry.name == 'Truck');
    final truck = stencil.build(50, 3, 3);
    final scaleX = truck.width / 86.33;
    final scaleY = truck.height / 33;
    final x = 80.33 * scaleX;
    final y = (33 - 2) * scaleY;
    final hasCrease = truck.geometries.expand((g) => g.commands).any((cmd) {
      return cmd is LineTo &&
          (cmd.x - x).abs() < 0.03 &&
          (cmd.y - y).abs() < 0.03;
    });
    expect(
      hasCrease,
      isTrue,
      reason: 'LibreOffice only sees Geometry; the cab crease is a '
          'foreground move/line outside <path>',
    );

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(stencil.build(id, 3, 3)),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(
      leftover.geometries.expand((g) => g.commands).any((cmd) {
        return cmd is LineTo &&
            (cmd.x - x).abs() < 0.03 &&
            (cmd.y - y).abs() < 0.03;
      }),
      isTrue,
      reason: 'a second save must keep the Truck cab crease',
    );
  });

  test('IBM dashed connectors keep LinePattern 2 for LibreOffice', () {
    final dashed = dynamic
        .singleWhere(
          (group) => group.name == 'Draw.io JS / IBM / IBM / Connectors',
        )
        .stencils
        .singleWhere((entry) => entry.name == 'Dashed Connector');
    final shape = dashed.build(51, 3, 3);
    expect(
      shape.line.pattern,
      2,
      reason: 'a dashed-only edge template is LinePattern 2 in tokens.txt',
    );
    expect(shape.geometries, isNotEmpty);
  });

  test('sidebar edge templates capture native geometry for LibreOffice', () {
    final stencil = dynamic
        .singleWhere((group) => group.name == 'Draw.io JS / Arrows2 / arrows')
        .stencils
        .singleWhere((entry) => entry.name == 'Wedge Arrow');
    final wedge = stencil.build(52, 3, 3);
    expect(
      wedge.geometries,
      isNotEmpty,
      reason: 'createEdgeTemplateEntry wedgeArrow uses paintEdgeShape',
    );
    expect(
      wedge.geometries.any((g) => !g.noFill),
      isTrue,
      reason: 'wedge fill must stay a Geometry libvisio can paint',
    );

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(stencil.build(id, 3, 3)),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(leftover.geometries, isNotEmpty);
  });

  test('electrical wire and mockup tables capture native geometry', () {
    Stencil stencil(String groupName, String shapeName) => dynamic
        .singleWhere((group) => group.name == groupName)
        .stencils
        .singleWhere((entry) => entry.name == shapeName);

    final wire = stencil(
      'Draw.io JS / Electrical / Electrical / Transmission Paths',
      'Dashed Wire',
    ).build(60, 3, 3);
    expect(
      wire.geometries.where((g) => g.noFill && !g.noLine),
      isNotEmpty,
      reason: 'shape=wire paintEdgeShape must stroke, not a filled rectangle',
    );
    expect(
      wire.line.pattern,
      2,
      reason: 'Dashed Wire style dashed=1 is LinePattern 2 in tokens.txt',
    );

    final table = stencil(
      'Draw.io JS / Mockup / Mockup Text',
      'Table',
    ).build(61, 3, 3);
    expect(
      table.geometries.length,
      greaterThan(2),
      reason: 'table/tableRow need getTitleSize so cells stay native geometry',
    );
    expect(
      table.children.where((child) => (child.text ?? '').isNotEmpty).length,
      greaterThan(2),
      reason: 'header and body cell labels must stay Text for LibreOffice',
    );

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final wireId = doc.pages.first.nextFreeShapeId();
    var page = doc.pages.first.addShape(stencil(
      'Draw.io JS / Electrical / Electrical / Transmission Paths',
      'Dashed Wire',
    ).build(wireId, 2, 4));
    final tableId = page.nextFreeShapeId();
    page = page.addShape(stencil(
      'Draw.io JS / Mockup / Mockup Text',
      'Table',
    ).build(tableId, 5, 4));
    doc = doc.replacePage(0, page);
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first;
    expect(
      leftover.findShapeById(wireId)!.geometries,
      isNotEmpty,
    );
    expect(
      leftover.findShapeById(tableId)!.children.any(
            (child) => (child.text ?? '').isNotEmpty,
          ),
      isTrue,
    );
  });

  test('sidebar factories keep terminals offsets and clones for LibreOffice',
      () {
    Stencil stencil(String groupName, String shapeName) => dynamic
        .singleWhere((group) => group.name == groupName)
        .stencils
        .singleWhere((entry) => entry.name == shapeName);

    final generalization = stencil(
      'Draw.io JS / UML25 / uml 2.5',
      'Interface Generalization',
    ).build(70, 3, 3);
    expect(
      generalization.width / generalization.height,
      greaterThan(5),
      reason: 'h=0 edge templates must not inflate to a 100-tall covering box',
    );
    expect(
      generalization.geometries.where((g) => g.noFill && !g.noLine),
      isNotEmpty,
      reason: 'setTerminalPoint must stroke the UML interface line',
    );

    final property = stencil(
      'Draw.io JS / UML25 / uml 2.5',
      'Property',
    ).build(71, 3, 3);
    final caption = property.children.where((child) => child.text == '0..1');
    final field = property.children.where((child) => child.text == 'Property1');
    expect(caption, isNotEmpty, reason: 'parent multiplicity stays Text');
    expect(field, isNotEmpty, reason: 'relative offset label stays Text');
    expect(
      field.first.pinY,
      lessThan(caption.first.pinY),
      reason: 'mxGeometry relative+offset must place Property1 below 0..1',
    );

    final buttons = stencil(
      'Draw.io JS / Bootstrap / bootstrap',
      'Button group, vertical',
    ).build(72, 3, 3);
    expect(
      buttons.geometries.length,
      greaterThan(2),
      reason: 'sb.cloneCell stacked buttons must stay native geometry',
    );
    expect(
      buttons.children.where((child) => child.text == 'Button').length,
      greaterThan(2),
      reason: 'cloned button labels must stay Text for LibreOffice',
    );

    final choreography = stencil(
      'Draw.io JS / BPMN / BPMN 2.0  Choreographies',
      'Choreography Task',
    ).build(73, 3, 3);
    expect(
      choreography.geometries.length,
      greaterThan(1),
      reason: 'zero-arg palette roots must keep working sb factories',
    );

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final igId = doc.pages.first.nextFreeShapeId();
    var page = doc.pages.first.addShape(stencil(
      'Draw.io JS / UML25 / uml 2.5',
      'Interface Generalization',
    ).build(igId, 2, 4));
    final propId = page.nextFreeShapeId();
    page = page.addShape(stencil(
      'Draw.io JS / UML25 / uml 2.5',
      'Property',
    ).build(propId, 5, 4));
    final btnId = page.nextFreeShapeId();
    page = page.addShape(stencil(
      'Draw.io JS / Bootstrap / bootstrap',
      'Button group, vertical',
    ).build(btnId, 8, 4));
    doc = doc.replacePage(0, page);
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first;
    expect(
      leftover.findShapeById(igId)!.width /
          leftover.findShapeById(igId)!.height,
      greaterThan(5),
    );
    expect(
      leftover
          .findShapeById(propId)!
          .children
          .any((child) => child.text == 'Property1'),
      isTrue,
    );
    expect(
      leftover.findShapeById(btnId)!.geometries.length,
      greaterThan(2),
    );
  });

  test('mxGraph triangle direction south stays a chevron for LibreOffice', () {
    final buttons = dynamic
        .singleWhere(
          (group) => group.name == 'Draw.io JS / Bootstrap / bootstrap',
        )
        .stencils
        .singleWhere((entry) => entry.name == 'Button group, horizontal (4)')
        .build(80, 3, 3);
    ({double w, double h, int lines})? chevron;
    for (final geometry in buttons.geometries) {
      var minX = double.infinity, minY = double.infinity;
      var maxX = -double.infinity, maxY = -double.infinity;
      var lines = 0;
      for (final command in geometry.commands) {
        if (command is LineTo) lines++;
        final x = switch (command) {
          MoveTo(:final x) => x,
          LineTo(:final x) => x,
          _ => null,
        };
        final y = switch (command) {
          MoveTo(:final y) => y,
          LineTo(:final y) => y,
          _ => null,
        };
        if (x == null || y == null) continue;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
      final w = maxX - minX;
      final h = maxY - minY;
      if (lines == 3 && h > w) {
        chevron = (w: w, h: h, lines: lines);
        break;
      }
    }
    expect(
      chevron,
      isNotNull,
      reason: 'shape=triangle;direction=south must bake a 3-point chevron, '
          'not an unrotated diamond',
    );

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / Bootstrap / bootstrap',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Button group, horizontal (4)')
          .build(id, 3, 3)),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(
      leftover.geometries.any((geometry) {
        return geometry.commands.whereType<LineTo>().length == 3;
      }),
      isTrue,
    );
  });
}
