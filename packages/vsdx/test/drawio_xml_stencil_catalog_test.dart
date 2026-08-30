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

  Iterable<VsdxGeometry> descendantGeometries(VsdxShape shape) sync* {
    yield* shape.geometries;
    for (final child in shape.children) {
      yield* descendantGeometries(child);
    }
  }

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
    expect(dynamic, hasLength(482));
    expect(
      dynamic.fold<int>(0, (sum, group) => sum + group.stencils.length),
      13277,
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
          final geos = descendantGeometries(shape).toList(growable: false);
          if (!shape.width.isFinite ||
              !shape.height.isFinite ||
              shape.width <= 0 ||
              shape.height <= 0 ||
              geos.isEmpty ||
              geos.any((geometry) => geometry.commands.isEmpty)) {
            fail('${group.name} / ${stencil.name} produced invalid geometry');
          }
          geometryCount += geos.length;
          commandCount += geos.fold<int>(
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
          final geos = descendantGeometries(shape).toList(growable: false);
          if (!shape.width.isFinite ||
              !shape.height.isFinite ||
              shape.width <= 0 ||
              shape.height <= 0 ||
              geos.isEmpty ||
              geos.any((geometry) => geometry.commands.isEmpty)) {
            fail('${group.name} / ${stencil.name} produced invalid geometry');
          }
          geometryCount += geos.length;
          commandCount += geos.fold<int>(
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
      shapes
          .expand(descendantGeometries)
          .expand((geometry) => geometry.commands),
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
    expect(descendantGeometries(pod).length, greaterThan(2),
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
    expect(
      descendantGeometries(dialog).length,
      greaterThan(2),
      reason: 'addDataEntry mxGraphModel cells must become native geometry',
    );
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
    expect(descendantGeometries(leftover).length, greaterThan(2));
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

  test('mxStencil hex fillcolor stays sibling FillForegnd for LibreOffice', () {
    final radio = migrated
        .singleWhere(
            (group) => group.name == 'Draw.io / Mockup / Form Elements')
        .stencils
        .singleWhere((entry) => entry.name == 'Radio Button On')
        .build(80, 3, 3);
    expect(
      radio.children.any(
        (child) =>
            child.fill.hasFill &&
            child.fill.foreground == VsdxColor.black &&
            !child.isLibvisioFillSplitChild,
      ),
      isTrue,
      reason: 'the inner dot is fillcolor #000000; libvisio evenodd would '
          'punch it if it stayed on the parent',
    );
    expect(
      radio.children.any(
        (child) =>
            child.fill.hasFill &&
            child.fill.foreground == const VsdxColor(0xFFEEEEEF),
      ),
      isTrue,
      reason: 'the chrome stays #eeeeef, not the mockup palette wash',
    );

    final toggle = migrated
        .singleWhere((group) => group.name == 'Draw.io / Mockup / Controls')
        .stencils
        .singleWhere((entry) => entry.name == 'On-Off Button 4')
        .build(81, 3, 3);
    expect(
      toggle.children.any(
        (child) =>
            child.fill.hasFill &&
            child.fill.foreground == const VsdxColor(0xFF4342A9),
      ),
      isTrue,
      reason: 'the ON half is fillcolor #4342a9',
    );
    final onLabel = toggle.children.where((child) => child.text == 'ON');
    expect(onLabel, isNotEmpty);
    expect(
      onLabel.first.richText.runs.first.charStyle.color,
      VsdxColor.white,
      reason: 'fontcolor #ffffff must reach collectCharIX',
    );

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final radioId = doc.pages.first.nextFreeShapeId();
    var page = doc.pages.first.addShape(
      migrated
          .singleWhere(
            (group) => group.name == 'Draw.io / Mockup / Form Elements',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Radio Button On')
          .build(radioId, 3, 3),
    );
    final toggleId = page.nextFreeShapeId();
    page = page.addShape(
      migrated
          .singleWhere((group) => group.name == 'Draw.io / Mockup / Controls')
          .stencils
          .singleWhere((entry) => entry.name == 'On-Off Button 4')
          .build(toggleId, 5, 3),
    );
    doc = doc.replacePage(0, page);
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first;
    expect(
      leftover.findShapeById(radioId)!.children.any(
            (child) =>
                child.fill.hasFill && child.fill.foreground == VsdxColor.black,
          ),
      isTrue,
      reason: 'a second save must keep the radio dot FillForegnd',
    );
    expect(
      leftover
          .findShapeById(toggleId)!
          .children
          .where((child) => child.text == 'ON')
          .first
          .richText
          .runs
          .first
          .charStyle
          .color,
      VsdxColor.white,
      reason: 'a second save must keep the ON glyph Color',
    );
  });

  test('mxStencil strokewidth stays LineWeight for LibreOffice', () {
    final checkbox = migrated
        .singleWhere(
            (group) => group.name == 'Draw.io / Mockup / Form Elements')
        .stencils
        .singleWhere((entry) => entry.name == 'Checkbox On')
        .build(82, 3, 3);
    final tick = checkbox.children.where(
      (child) =>
          !child.fill.hasFill &&
          child.line.hasLine &&
          child.line.color == VsdxColor.black,
    );
    expect(tick, isNotEmpty, reason: 'the check is fillcolor none + stroke');
    expect(
      tick.first.line.weightInches,
      greaterThan(0.05),
      reason: 'strokewidth width=2 must reach collectLine LineWeight, '
          'not the 0.01 in palette default',
    );

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        migrated
            .singleWhere(
              (group) => group.name == 'Draw.io / Mockup / Form Elements',
            )
            .stencils
            .singleWhere((entry) => entry.name == 'Checkbox On')
            .build(id, 3, 3),
      ),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(
      leftover.children.any(
        (child) =>
            !child.fill.hasFill &&
            child.line.hasLine &&
            child.line.weightInches > 0.05,
      ),
      isTrue,
      reason: 'a second save must keep the check LineWeight',
    );
  });

  test('mxGraph setGradient stays FillPattern 25–34 for LibreOffice', () {
    const magenta = VsdxColor(0xFFBC1356);
    const pink = VsdxColor(0xFFF34482);
    const beige = VsdxColor(0xFFFFF8E7);

    bool isSumerianRamp(VsdxFill fill) {
      if (!fill.hasFill || fill.pattern < 25 || fill.pattern > 40) {
        return false;
      }
      if (fill.foreground == beige || fill.background == beige) return false;
      final colors = <VsdxColor?>{fill.foreground, fill.background};
      return colors.contains(magenta) && colors.contains(pink);
    }

    final sumerian = dynamic
        .singleWhere(
          (group) => group.name == 'Draw.io JS / AWS4 / AWS / AR & VR',
        )
        .stencils
        .singleWhere((entry) => entry.name == 'Sumerian')
        .build(83, 3, 3);
    expect(
      sumerian.children.any((child) => isSumerianRamp(child.fill)),
      isTrue,
      reason: 'mxShape.configureCanvas setGradient must become FillBkgnd/'
          'FillForegnd FillPattern 25–34; libvisio has no FillGradient token',
    );
    expect(
      sumerian.fill.hasFill,
      isFalse,
      reason:
          'the brand ramp is a sibling so applyStencilStyle cannot beige it',
    );
    expect(
      sumerian.children.any(
        (child) =>
            child.fill.hasFill &&
            child.fill.pattern == 1 &&
            child.fill.foreground == VsdxColor.white,
      ),
      isTrue,
      reason: 'resourceIcon paints the glyph with strokeColor #ffffff',
    );

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        dynamic
            .singleWhere(
              (group) => group.name == 'Draw.io JS / AWS4 / AWS / AR & VR',
            )
            .stencils
            .singleWhere((entry) => entry.name == 'Sumerian')
            .build(id, 3, 3),
      ),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(
      leftover.children.any((child) => isSumerianRamp(child.fill)),
      isTrue,
      reason: 'a second save must keep the Sumerian FillPattern ramp',
    );
  });

  test('mxStencil fillalpha stays FillForegndTrans for LibreOffice', () {
    final router = migrated
        .singleWhere((group) => group.name == 'Draw.io / Rack / Cisco')
        .stencils
        .singleWhere(
          (entry) =>
              entry.name == 'Cisco 1905 Serial Integrated Services Router',
        )
        .build(84, 3, 3);
    expect(
      router.children.any(
        (child) =>
            child.fill.hasFill &&
            child.fill.foreground == VsdxColor.black &&
            child.fill.foregroundTransparency > 0.7 &&
            child.fill.foregroundTransparency < 0.85,
      ),
      isTrue,
      reason: 'fillalpha 0.232 must reach collectFillAndShadow as '
          'FillForegndTrans, not an opaque black overlay',
    );

    final docs = migrated
        .singleWhere(
          (group) => group.name == 'Draw.io / Google Material Design',
        )
        .stencils
        .singleWhere((entry) => entry.name == 'docs')
        .build(85, 3, 3);
    expect(
      docs.children.any(
        (child) =>
            child.fill.hasFill &&
            child.fill.foreground == VsdxColor.white &&
            (child.fill.foregroundTransparency - 0.5).abs() < 0.02,
      ),
      isTrue,
      reason: 'gmdl docs fold uses alpha 0.5 on fillcolor #ffffff',
    );

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        migrated
            .singleWhere((group) => group.name == 'Draw.io / Rack / Cisco')
            .stencils
            .singleWhere(
              (entry) =>
                  entry.name == 'Cisco 1905 Serial Integrated Services Router',
            )
            .build(id, 3, 3),
      ),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(
      leftover.children.any(
        (child) =>
            child.fill.hasFill &&
            child.fill.foreground == VsdxColor.black &&
            child.fill.foregroundTransparency > 0.7,
      ),
      isTrue,
      reason: 'a second save must keep the rack overlay FillForegndTrans',
    );

    final disabled = dynamic
        .singleWhere(
          (group) => group.name == 'Draw.io JS / Gmdl / GMDL / Buttons',
        )
        .stencils
        .singleWhere((entry) => entry.name == 'Raised Button (Pressed) (2)')
        .build(86, 3, 3);
    expect(
      disabled.children.any(
        (child) =>
            child.fill.hasFill &&
            child.fill.foreground == VsdxColor.black &&
            (child.fill.foregroundTransparency - 0.88).abs() < 0.02,
      ),
      isTrue,
      reason: 'GMDL opacity=12 must become FillForegndTrans 0.88',
    );
  });

  test('mxStencil dashpattern stays customDashPattern for LibreOffice', () {
    bool hasFixedDash(VsdxShape shape) {
      final custom = shape.line.customDashPattern;
      if (shape.line.hasLine &&
          custom != null &&
          custom.length >= 2 &&
          shape.line.fixedDash) {
        return true;
      }
      return shape.children.any(hasFixedDash);
    }

    final detour = migrated
        .singleWhere((group) => group.name == 'Draw.io / Eip')
        .stencils
        .singleWhere((entry) => entry.name == 'Detour')
        .build(87, 3, 3);
    expect(
      hasFixedDash(detour),
      isTrue,
      reason: 'dashpattern 5 5 must reach collectLine as veDashPattern, '
          'not a solid sibling that shares the box LinePattern',
    );
    expect(
      detour.children.any(
        (child) =>
            !child.fill.hasFill &&
            child.line.hasLine &&
            child.line.customDashPattern != null,
      ),
      isTrue,
      reason: 'the diagonal is a sibling so collectLine can dash it '
          'without also dashing the solid box',
    );

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        migrated
            .singleWhere((group) => group.name == 'Draw.io / Eip')
            .stencils
            .singleWhere((entry) => entry.name == 'Detour')
            .build(id, 3, 3),
      ),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(
      leftover.children.any((child) {
        if (child.fill.hasFill || !child.line.hasLine) return false;
        final moves = child.geometries
            .expand((geometry) => geometry.commands)
            .whereType<MoveTo>()
            .length;
        return moves >= 2;
      }),
      isTrue,
      reason: 'a second save bakes veDashPattern into MoveTo gaps '
          'because libvisio treats custom LinePattern 0xfe as solid',
    );
  });

  test('mxStencil linecap stays LineCap for LibreOffice', () {
    bool hasCap(VsdxShape shape, LineCap cap) {
      if (shape.line.hasLine && shape.line.cap == cap) return true;
      return shape.children.any((child) => hasCap(child, cap));
    }

    final flow = migrated
        .singleWhere((group) => group.name == 'Draw.io / Lean Mapping')
        .stencils
        .singleWhere((entry) => entry.name == 'Electronic Info Flow')
        .build(88, 3, 3);
    expect(
      hasCap(flow, LineCap.extended),
      isTrue,
      reason: 'linecap=butt must become LineCap 1 that libvisio '
          '_lineProperties maps to svg:stroke-linecap=butt',
    );

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        migrated
            .singleWhere((group) => group.name == 'Draw.io / Lean Mapping')
            .stencils
            .singleWhere((entry) => entry.name == 'Electronic Info Flow')
            .build(id, 3, 3),
      ),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(
      hasCap(leftover, LineCap.extended),
      isTrue,
      reason: 'a second save must keep LineCap 1',
    );
  });

  test('mxGraph shadow=1 stays ShdwPattern for LibreOffice', () {
    bool hasHardShadow(VsdxShape shape) {
      final shadow = shape.shadow;
      if (shadow.enabled &&
          shadow.pattern == 1 &&
          shadow.blurInches.abs() < 1e-9 &&
          shadow.offsetXInches.abs() > 1e-6 &&
          shadow.offsetYInches.abs() > 1e-6) {
        return true;
      }
      return shape.children.any(hasHardShadow);
    }

    final card = dynamic
        .singleWhere(
          (group) => group.name == 'Draw.io JS / GCP2 / GCP / Service Cards',
        )
        .stencils
        .singleWhere((entry) => entry.name == 'Blank One Line')
        .build(89, 3, 3);
    expect(
      hasHardShadow(card),
      isTrue,
      reason: 'shadow=1 must become ShdwPattern 1 that libvisio '
          '_fillAndShadowProperties maps to draw:shadow',
    );

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        dynamic
            .singleWhere(
              (group) =>
                  group.name == 'Draw.io JS / GCP2 / GCP / Service Cards',
            )
            .stencils
            .singleWhere((entry) => entry.name == 'Blank One Line')
            .build(id, 3, 3),
      ),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(
      hasHardShadow(leftover),
      isTrue,
      reason: 'a second save must keep ShdwPattern 1',
    );
  });

  test('mxGraph style strokeWidth stays LineWeight for LibreOffice', () {
    double maxWeight(VsdxShape shape) {
      var weight = shape.line.hasLine ? shape.line.weightInches : 0.0;
      for (final child in shape.children) {
        final childWeight = maxWeight(child);
        if (childWeight > weight) weight = childWeight;
      }
      return weight;
    }

    final arc = dynamic
        .singleWhere(
          (group) => group.name == 'Draw.io JS / Infographic / Infographic',
        )
        .stencils
        .singleWhere((entry) => entry.name == 'Arc')
        .build(90, 3, 3);
    expect(
      maxWeight(arc),
      closeTo(0.09, 0.005),
      reason: 'strokeWidth=6 at 100px → 1.5 in is 0.09 in LineWeight, '
          'not the 0.01 in palette default or restore() width=1',
    );

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        dynamic
            .singleWhere(
              (group) => group.name == 'Draw.io JS / Infographic / Infographic',
            )
            .stencils
            .singleWhere((entry) => entry.name == 'Arc')
            .build(id, 3, 3),
      ),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(
      maxWeight(leftover),
      closeTo(0.09, 0.005),
      reason: 'a second save must keep the authored LineWeight',
    );
  });

  test('mxStencil fontfamily stays Char.Font for LibreOffice', () {
    String? glyphFont(VsdxShape shape, String text) {
      for (final child in shape.children) {
        if (child.text == text && child.richText.runs.isNotEmpty) {
          return child.richText.runs.first.charStyle.fontFamily;
        }
        final nested = glyphFont(child, text);
        if (nested != null) return nested;
      }
      return null;
    }

    final contact = migrated
        .singleWhere((group) => group.name == 'Draw.io / Cisco / Misc')
        .stencils
        .singleWhere((entry) => entry.name == 'Contact Center')
        .build(91, 3, 3);
    expect(
      glyphFont(contact, 'V'),
      'Helvetica',
      reason: "fontfamily family='Helvetica' must reach collectCharIX Font",
    );
    expect(
      glyphFont(contact, 'WWW'),
      'Helvetica',
      reason: 'the later WWW glyph keeps the same Char.Font',
    );

    final motor = dynamic
        .singleWhere(
          (group) =>
              group.name == 'Draw.io JS / PID / Process Engineering / Valves',
        )
        .stencils
        .singleWhere((entry) => entry.name == 'Gate Valve (Motor)')
        .build(92, 3, 3);
    expect(
      glyphFont(motor, 'M'),
      'Helvetica',
      reason: "PID setFontFamily('Helvetica') must reach collectCharIX Font",
    );

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        migrated
            .singleWhere((group) => group.name == 'Draw.io / Cisco / Misc')
            .stencils
            .singleWhere((entry) => entry.name == 'Contact Center')
            .build(id, 3, 3),
      ),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(
      glyphFont(leftover, 'V'),
      'Helvetica',
      reason: 'a second save must keep Char.Font Helvetica',
    );

    var motorDoc = parser.parse(writer.emptyDocument());
    final motorId = motorDoc.pages.first.nextFreeShapeId();
    motorDoc = motorDoc.replacePage(
      0,
      motorDoc.pages.first.addShape(
        dynamic
            .singleWhere(
              (group) =>
                  group.name ==
                  'Draw.io JS / PID / Process Engineering / Valves',
            )
            .stencils
            .singleWhere((entry) => entry.name == 'Gate Valve (Motor)')
            .build(motorId, 3, 3),
      ),
    );
    final leftoverMotor = parser
        .parse(
          writer.write(originalBytes: writer.emptyDocument(), edited: motorDoc),
        )
        .pages
        .first
        .findShapeById(motorId)!;
    expect(
      glyphFont(leftoverMotor, 'M'),
      'Helvetica',
      reason: 'a second save must keep the Motor M Char.Font',
    );
  });

  test('mxText style fontSize and fontColor stay Char cells for LibreOffice',
      () {
    VsdxTextRun? glyphRun(VsdxShape shape, String text) {
      for (final child in shape.children) {
        if (child.text == text && child.richText.runs.isNotEmpty) {
          return child.richText.runs.first;
        }
        final nested = glyphRun(child, text);
        if (nested != null) return nested;
      }
      return null;
    }

    final ammeter = dynamic
        .singleWhere(
          (group) =>
              group.name ==
              'Draw.io JS / Electrical / Electrical / Instruments',
        )
        .stencils
        .singleWhere((entry) => entry.name == 'Ammeter')
        .build(93, 3, 3);
    final ammeterRun = glyphRun(ammeter, 'A');
    expect(ammeterRun, isNotNull,
        reason: 'Ammeter cell value A is a Text child');
    expect(
      ammeterRun!.charStyle.fontSizeInches,
      closeTo(50 * 1.5 / 90, 0.02),
      reason: 'fontSize=50 at 90px → 1.5 in must reach collectCharIX Size, '
          'not the 12 pt canvas default',
    );

    final alert = dynamic
        .singleWhere(
          (group) => group.name == 'Draw.io JS / Bootstrap / bootstrap',
        )
        .stencils
        .singleWhere((entry) => entry.name == 'Alert')
        .build(94, 3, 3);
    final alertRun = glyphRun(alert, 'A simple primary alert!');
    expect(alertRun, isNotNull, reason: 'Bootstrap Alert keeps the cell value');
    expect(
      alertRun!.charStyle.color,
      VsdxColor.tryParse('#004583'),
      reason: 'fontColor=#004583 must reach collectCharIX Color',
    );

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        dynamic
            .singleWhere(
              (group) =>
                  group.name ==
                  'Draw.io JS / Electrical / Electrical / Instruments',
            )
            .stencils
            .singleWhere((entry) => entry.name == 'Ammeter')
            .build(id, 3, 3),
      ),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(
      glyphRun(leftover, 'A')!.charStyle.fontSizeInches,
      closeTo(50 * 1.5 / 90, 0.02),
      reason: 'a second save must keep Char.Size',
    );
  });

  test(
    'mxText fontStyle does not leak italic onto the next cell for LibreOffice',
    () {
      VsdxTextRun? glyphRun(VsdxShape shape, String text) {
        for (final child in shape.children) {
          if (child.text == text && child.richText.runs.isNotEmpty) {
            return child.richText.runs.first;
          }
          final nested = glyphRun(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      final block = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / Sysml / SysML / Blocks',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Block')
          .build(95, 3, 3);
      expect(
        glyphRun(block, 'Block1')!.charStyle.style.bold,
        isTrue,
        reason: 'fontStyle=1 Block1 must reach collectCharIX Style.bold',
      );
      expect(
        glyphRun(block, 'constraints')!.charStyle.style.italic,
        isTrue,
        reason: 'fontStyle=2 compartment titles map to fo:font-style italic',
      );
      expect(
        glyphRun(block, '{x > y}')!.charStyle.style.italic,
        isFalse,
        reason: 'the next cell omits fontStyle; mxText.configureCanvas '
            'resets to 0 so italic must not stick',
      );
      expect(
        glyphRun(block, 'operation1 (p1 : Type1) : Type2')!
            .charStyle
            .style
            .italic,
        isFalse,
      );

      final ribbon = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / Infographic / Infographic',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Ribbon')
          .build(96, 3, 3);
      expect(
        glyphRun(ribbon, 'Label')!.charStyle.style.bold,
        isTrue,
        reason: 'a lone fontStyle=1 label must stay bold',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc =
          doc.replacePage(0, doc.pages.first.addShape(block.copyWith(id: id)));
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        glyphRun(leftover, 'constraints')!.charStyle.style.italic,
        isTrue,
        reason: 'a second save must keep Char italic on the title',
      );
      expect(
        glyphRun(leftover, '{x > y}')!.charStyle.style.italic,
        isFalse,
        reason: 'a second save must keep the body roman',
      );
    },
  );

  test('mxText label box and spacing stay TextBlock cells for LibreOffice', () {
    VsdxShape? glyphShape(VsdxShape shape, String text) {
      for (final child in shape.children) {
        if (child.text == text) return child;
        final nested = glyphShape(child, text);
        if (nested != null) return nested;
      }
      return null;
    }

    final ammeter = dynamic
        .singleWhere(
          (group) =>
              group.name ==
              'Draw.io JS / Electrical / Electrical / Instruments',
        )
        .stencils
        .singleWhere((entry) => entry.name == 'Ammeter')
        .build(95, 3, 3);
    final ammeterGlyph = glyphShape(ammeter, 'A');
    expect(ammeterGlyph, isNotNull,
        reason: 'Ammeter cell value A is a Text child');
    expect(
      ammeterGlyph!.width,
      closeTo(ammeter.width, 0.02),
      reason:
          'mxXmlCanvas2D.text w/h fills the 90px cell, not a tight glyph box',
    );
    expect(
      ammeterGlyph.height,
      closeTo(ammeter.height, 0.02),
    );
    expect(
      ammeterGlyph.pinX,
      closeTo(ammeter.width / 2, 0.02),
      reason:
          'the label pin is the cell centre so collectTextBlock svg:x is centred',
    );
    expect(
      ammeterGlyph.pinY,
      closeTo(ammeter.height / 2, 0.02),
    );
    expect(
      ammeterGlyph.richText.textBlock.verticalAlign,
      VsdxVertAlign.middle,
    );

    final alert = dynamic
        .singleWhere(
          (group) => group.name == 'Draw.io JS / Bootstrap / bootstrap',
        )
        .stencils
        .singleWhere((entry) => entry.name == 'Alert')
        .build(96, 3, 3);
    final alertGlyph = glyphShape(alert, 'A simple primary alert!');
    expect(alertGlyph, isNotNull,
        reason: 'Bootstrap Alert keeps the cell value');
    expect(
      alertGlyph!.width,
      closeTo(alert.width, 0.02),
      reason: 'the 800px Alert plate is the TextBlock svg:width Draw pads',
    );
    // mxText.apply: spacingLeft=10 + default spacing 2. Same min(scale)
    // as Char.Size (1.5 in / 800 px).
    const alertScale = 1.5 / 800;
    expect(
      alertGlyph.richText.textBlock.marginLeftInches,
      closeTo(12 * alertScale, 0.002),
      reason:
          'spacingLeft=10 must reach collectTextBlock LeftMargin / fo:padding-left',
    );
    expect(
      alertGlyph.richText.textBlock.marginRightInches,
      closeTo(2 * alertScale, 0.002),
      reason: 'omitted spacingRight still gets the mxText default spacing of 2',
    );
    expect(
      alertGlyph.richText.runs.first.paraStyle.horizontalAlign,
      VsdxHorzAlign.left,
    );

    final andGate = migrated
        .singleWhere(
          (group) => group.name == 'Draw.io / Electrical / Iec Logic Gates',
        )
        .stencils
        .singleWhere((entry) => entry.name == 'AND')
        .build(97, 3, 3);
    final andGlyph = glyphShape(andGate, 'AND');
    expect(andGlyph, isNotNull, reason: 'IEC AND stencil glyph stays a child');
    expect(
      andGlyph!.width,
      lessThan(andGate.width * 0.8),
      reason:
          'NestedStencil text(w=0,h=0) must stay a tight glyph, not a cell box',
    );

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        dynamic
            .singleWhere(
              (group) => group.name == 'Draw.io JS / Bootstrap / bootstrap',
            )
            .stencils
            .singleWhere((entry) => entry.name == 'Alert')
            .build(id, 3, 3),
      ),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    final leftoverGlyph = glyphShape(leftover, 'A simple primary alert!')!;
    expect(
      leftoverGlyph.width,
      closeTo(alert.width, 0.02),
      reason: 'a second save must keep the Alert TextBlock width',
    );
    expect(
      leftoverGlyph.richText.textBlock.marginLeftInches,
      closeTo(12 * alertScale, 0.002),
      reason: 'a second save must keep LeftMargin',
    );
    expect(
      leftoverGlyph.pinX,
      closeTo(alert.width / 2, 0.02),
      reason: 'a second save must keep the cell-centre pin',
    );
  });

  test('mxText wrap and vertical stay TextDirection cells for LibreOffice', () {
    VsdxShape? glyphShape(VsdxShape shape, String text) {
      for (final child in shape.children) {
        if (child.text == text) return child;
        final nested = glyphShape(child, text);
        if (nested != null) return nested;
      }
      return null;
    }

    final alert = dynamic
        .singleWhere(
          (group) => group.name == 'Draw.io JS / Bootstrap / bootstrap',
        )
        .stencils
        .singleWhere((entry) => entry.name == 'Alert')
        .build(98, 3, 3);
    final alertGlyph = glyphShape(alert, 'A simple primary alert!')!;
    expect(
      alertGlyph.wordWrap,
      isTrue,
      reason: 'whiteSpace=wrap must keep wrapping in the cell box',
    );

    final ammeter = dynamic
        .singleWhere(
          (group) =>
              group.name ==
              'Draw.io JS / Electrical / Electrical / Instruments',
        )
        .stencils
        .singleWhere((entry) => entry.name == 'Ammeter')
        .build(99, 3, 3);
    expect(
      glyphShape(ammeter, 'A')!.wordWrap,
      isFalse,
      reason:
          'mxText wrap defaults false; veWordWrap=0 bakes TxtWidth for Draw',
    );

    final cabinet = dynamic
        .singleWhere(
          (group) => group.name == 'Draw.io JS / Cabinet / cabinets',
        )
        .stencils
        .singleWhere(
          (entry) => entry.name == 'Panel Wiring System 25x40mm (Vertical)',
        )
        .build(100, 3, 3);
    final verticalGlyph = glyphShape(cabinet, '25x40');
    expect(verticalGlyph, isNotNull, reason: 'the vertical panel keeps 25x40');
    expect(
      verticalGlyph!.richText.textBlock.textDirection,
      1,
      reason:
          'STYLE_HORIZONTAL=0 is TextDirection=1 that a save bakes to TxtAngle',
    );
    expect(
      verticalGlyph.richText.textBlock.angleRad.abs(),
      lessThan(0.01),
      reason:
          'in-memory vertical labels use TextDirection, not a pre-baked TxtAngle',
    );
    expect(
      verticalGlyph.wordWrap,
      isTrue,
      reason: 'the vertical panel also sets whiteSpace=wrap',
    );

    final flat = dynamic
        .singleWhere(
          (group) => group.name == 'Draw.io JS / Cabinet / cabinets',
        )
        .stencils
        .singleWhere((entry) => entry.name == 'Panel Wiring System 25x40mm')
        .build(101, 3, 3);
    expect(
      glyphShape(flat, '25x40')!.richText.textBlock.textDirection,
      0,
      reason: 'the horizontal panel must not inherit vertical from a sibling',
    );

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        dynamic
            .singleWhere(
              (group) => group.name == 'Draw.io JS / Cabinet / cabinets',
            )
            .stencils
            .singleWhere(
              (entry) => entry.name == 'Panel Wiring System 25x40mm (Vertical)',
            )
            .build(id, 3, 3),
      ),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    final leftoverGlyph = glyphShape(leftover, '25x40')!;
    expect(
      leftoverGlyph.richText.textBlock.textDirection,
      0,
      reason:
          'a save bakes TextDirection so canvas reopen does not rotate twice',
    );
    expect(
      leftoverGlyph.richText.textBlock.angleRad,
      closeTo(-3.141592653589793 / 2, 0.05),
      reason: 'libvisio _flushText paints librevenge:rotate from TxtAngle, '
          'not style:writing-mode',
    );
  });

  test(
    'mxGraph STYLE_ROTATION stays TxtAngle for LibreOffice',
    () {
      VsdxShape? glyphShape(VsdxShape shape, String text) {
        for (final child in shape.children) {
          if (child.text == text) return child;
          final nested = glyphShape(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      final partition = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / Sysml / SysML / Activities',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Activity Partition')
          .build(102, 3, 3);
      final partitionGlyph = glyphShape(partition, 'Partition Name');
      expect(partitionGlyph, isNotNull);
      expect(
        partitionGlyph!.richText.textBlock.angleRad,
        closeTo(3.141592653589793 / 2, 0.05),
        reason:
            'rotation=-90 must reach TxtAngle that librevenge:rotate paints',
      );
      expect(
        partitionGlyph.richText.textBlock.textDirection,
        0,
        reason: 'STYLE_ROTATION is TxtAngle, not TextDirection=1',
      );

      final button = dynamic
          .singleWhere((group) => group.name == 'Draw.io JS / Basic / basic')
          .stencils
          .singleWhere((entry) => entry.name == 'Button')
          .build(103, 3, 3);
      expect(
        glyphShape(button, 'Button')!.richText.textBlock.angleRad.abs(),
        lessThan(0.01),
        reason: 'unrotated cell labels stay TxtAngle 0',
      );

      final cabinet = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / Cabinet / cabinets',
          )
          .stencils
          .singleWhere(
            (entry) => entry.name == 'Panel Wiring System 25x40mm (Vertical)',
          )
          .build(104, 3, 3);
      expect(
        glyphShape(cabinet, '25x40')!.richText.textBlock.textDirection,
        1,
        reason: 'STYLE_HORIZONTAL=0 must not pick up STYLE_ROTATION',
      );
      expect(
        glyphShape(cabinet, '25x40')!.richText.textBlock.angleRad.abs(),
        lessThan(0.01),
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(
          dynamic
              .singleWhere(
                (group) =>
                    group.name == 'Draw.io JS / Sysml / SysML / Activities',
              )
              .stencils
              .singleWhere((entry) => entry.name == 'Activity Partition')
              .build(id, 3, 3),
        ),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        glyphShape(leftover, 'Partition Name')!.richText.textBlock.angleRad,
        closeTo(3.141592653589793 / 2, 0.05),
        reason: 'a second save must keep TxtAngle',
      );
    },
  );

  test(
    'mxText textOpacity bakes Char ColorTrans for LibreOffice',
    () {
      VsdxTextRun? glyphRun(VsdxShape shape, String text) {
        for (final child in shape.children) {
          if (child.text == text && child.richText.runs.isNotEmpty) {
            return child.richText.runs.first;
          }
          final nested = glyphRun(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      final topBar = dynamic
          .singleWhere((group) => group.name == 'Draw.io JS / Ios / iOS6')
          .stencils
          .singleWhere((entry) => entry.name == 'Top bar')
          .build(105, 3, 3);
      final carrier = glyphRun(topBar, 'CARRIER');
      expect(carrier, isNotNull);
      expect(
        carrier!.charStyle.transparency,
        closeTo(0.5, 1e-6),
        reason: 'textOpacity=50 is Char ColorTrans that collectCharIX cannot '
            'read; a save bakes it into fo:color',
      );
      expect(
        carrier.charStyle.color?.value,
        0xFFCCCCCC,
        reason: 'in-memory Color stays #cccccc until the ColorTrans bake',
      );
      final clock = glyphRun(topBar, '11:15AM');
      expect(clock, isNotNull);
      expect(clock!.charStyle.transparency, closeTo(0.5, 1e-6));

      final appBar = dynamic
          .singleWhere((group) => group.name == 'Draw.io JS / Ios / iOS6')
          .stencils
          .singleWhere((entry) => entry.name == 'App bar (portrait)')
          .build(106, 3, 3);
      expect(
        glyphRun(appBar, 'CARRIER')!.charStyle.transparency,
        closeTo(0, 1e-6),
        reason: 'omitted textOpacity must reset to 100 like mxText.apply',
      );

      VsdxTextRun? fadedLabel;
      for (final stencil in dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / Gmdl / GMDL / Text Fields',
          )
          .stencils) {
        final shape = stencil.build(107, 3, 3);
        final run = glyphRun(shape, 'Label text');
        if (run != null && run.charStyle.transparency > 0.05) {
          fadedLabel = run;
          break;
        }
      }
      expect(fadedLabel, isNotNull);
      expect(
        fadedLabel!.charStyle.transparency,
        closeTo(0.2, 1e-6),
        reason: 'GMDL textOpacity=80 is 20% ColorTrans',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(topBar.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      final leftoverCarrier = glyphRun(leftover, 'CARRIER')!;
      expect(
        leftoverCarrier.charStyle.transparency,
        closeTo(0, 1e-6),
        reason: 'ColorTrans is not a token; the bake writes 0',
      );
      expect(
        leftoverCarrier.charStyle.color?.value,
        colourForLibvisioAlpha(
          const VsdxColor(0xFFCCCCCC),
          0.5,
        ).value,
        reason: 'a second save must keep the RGB Draw paints as fo:color',
      );
    },
  );

  test(
    'mxGraph inherit colors freeze parent hex for LibreOffice',
    () {
      VsdxTextRun? glyphRun(VsdxShape shape, String text) {
        for (final child in shape.children) {
          if (child.text == text && child.richText.runs.isNotEmpty) {
            return child.richText.runs.first;
          }
          final nested = glyphRun(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      final bar = dynamic
          .singleWhere((group) => group.name == 'Draw.io JS / Ios / iOS6')
          .stencils
          .singleWhere((entry) => entry.name == 'Button bar')
          .build(108, 3, 3);
      expect(
        glyphRun(bar, 'Item 1')!.charStyle.color?.value,
        0xFF666666,
        reason: 'fontColor=inherit under #666666 must reach collectCharIX '
            'fo:color, not default black',
      );
      expect(
        glyphRun(bar, 'Item 2')!.charStyle.color?.value,
        0xFFFFFFFF,
        reason: 'explicit fontColor=#ffffff must not pick up inherit',
      );
      expect(
        glyphRun(bar, 'Item 3')!.charStyle.color?.value,
        0xFF666666,
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(bar.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        glyphRun(leftover, 'Item 1')!.charStyle.color?.value,
        0xFF666666,
        reason: 'a second save must keep the inherited Char Color',
      );
      expect(
        glyphRun(leftover, 'Item 2')!.charStyle.color?.value,
        0xFFFFFFFF,
      );
    },
  );

  test(
    'mxText html spans stay extra Char rows for LibreOffice',
    () {
      VsdxTextRun? runContaining(VsdxShape shape, String text) {
        for (final child in shape.children) {
          for (final run in child.richText.runs) {
            if (run.text.contains(text)) return run;
          }
          final nested = runContaining(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      VsdxTextRun? runExact(VsdxShape shape, String text) {
        for (final child in shape.children) {
          for (final run in child.richText.runs) {
            if (run.text.replaceAll('\n', '').trim() == text) return run;
          }
          final nested = runExact(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      final classifier = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / UML25 / uml 2.5',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Classifier')
          .build(109, 3, 3);
      expect(
        runContaining(classifier, 'Classifier1')!.charStyle.style.bold,
        isTrue,
        reason: 'html <b>Classifier1</b> must reach collectCharIX Style.bold',
      );
      expect(
        runContaining(classifier, 'keyword')!.charStyle.style.bold,
        isFalse,
        reason: 'stereotype text outside <b> stays roman',
      );
      expect(
        runContaining(classifier, '{abstract}')!.charStyle.style.bold,
        isFalse,
      );

      final card = dynamic
          .singleWhere(
            (group) =>
                group.name ==
                'Draw.io JS / GCP2 / GCP / Expanded Product Cards',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Compute Engine')
          .build(110, 3, 3);
      expect(
        runExact(card, 'Name')!.charStyle.color?.value,
        0xFF000000,
        reason: '<font color="#000000">Name</font> must not pick up #999999',
      );
      expect(
        runExact(card, 'Compute Engine')!.charStyle.color?.value,
        0xFF999999,
      );
      final attr = runExact(card, 'Attribute Name')!;
      final name = runExact(card, 'Name')!;
      expect(
        attr.charStyle.fontSizeInches,
        closeTo(name.charStyle.fontSizeInches * 11 / 12, 0.01),
        reason: 'font-size: 11px is Char.Size that collectCharIX maps to '
            'fo:font-size',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(classifier.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        runContaining(leftover, 'Classifier1')!.charStyle.style.bold,
        isTrue,
        reason: 'a second save must keep Char bold on Classifier1',
      );
      expect(
        runContaining(leftover, '{abstract}')!.charStyle.style.bold,
        isFalse,
      );
    },
  );

  test(
    'mxText html sup and sub stay Char Pos for LibreOffice',
    () {
      VsdxTextRun? runExact(VsdxShape shape, String text) {
        for (final child in shape.children) {
          for (final run in child.richText.runs) {
            if (run.text.replaceAll('\n', '').trim() == text) return run;
          }
          final nested = runExact(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      final vdd = dynamic
          .singleWhere(
            (group) =>
                group.name == 'Draw.io JS / Electrical / Electrical / Misc',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Vdd')
          .build(440, 3, 3);
      expect(
        runExact(vdd, 'V')!.charStyle.position,
        VsdxTextPosition.normal,
        reason: 'the V stays on the baseline',
      );
      expect(
        runExact(vdd, 'dd')!.charStyle.position,
        VsdxTextPosition.subscript,
        reason: 'html <sub>dd</sub> is Char.Pos 2 that readCharIX maps to '
            'style:text-position sub',
      );

      final zone = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / GCP2 / GCP / Zones',
          )
          .stencils
          .singleWhere(
            (entry) => entry.name == 'External Infrastructure 3rd party',
          )
          .build(441, 3, 3);
      expect(
        runExact(zone, 'rd')!.charStyle.position,
        VsdxTextPosition.superscript,
        reason: 'html <sup>rd</sup> is Char.Pos 1 that collectCharIX maps to '
            'style:text-position super',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(vdd.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        runExact(leftover, 'dd')!.charStyle.position,
        VsdxTextPosition.subscript,
        reason: 'a second save must keep Char.Pos subscript',
      );
      expect(
        runExact(leftover, 'V')!.charStyle.position,
        VsdxTextPosition.normal,
      );
    },
  );

  test(
    'mxText html text-decoration stays Char underline for LibreOffice',
    () {
      VsdxTextRun? runContaining(VsdxShape shape, String text) {
        for (final child in shape.children) {
          for (final run in child.richText.runs) {
            if (run.text.contains(text)) return run;
          }
          final nested = runContaining(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      final spec = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / Sysml / SysML / Blocks',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Instance Specification (4)')
          .build(442, 3, 3);
      expect(
        runContaining(spec, 'instance1 / property1: Type2')!
            .charStyle
            .underline,
        isTrue,
        reason: 'html text-decoration:underline on <p> is Char Style 0x4 that '
            'readCharIX maps to style:text-underline-type',
      );
      expect(
        runContaining(spec, 'property1 = 10')!.charStyle.underline,
        isFalse,
        reason: 'the slot values sit outside the underlined <p>',
      );
      expect(
        runContaining(spec, 'instance2 / property2: Type3')!
            .charStyle
            .underline,
        isTrue,
        reason: 'fontStyle=4 on the next cell is still Style 0x4',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(spec.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        runContaining(leftover, 'instance1 / property1: Type2')!
            .charStyle
            .underline,
        isTrue,
        reason: 'a second save must keep Char underline',
      );
      expect(
        runContaining(leftover, 'property1 = 10')!.charStyle.underline,
        isFalse,
      );
    },
  );

  test(
    'mxText html font-family stays Char.Font for LibreOffice',
    () {
      VsdxTextRun? runContaining(VsdxShape shape, String text) {
        for (final child in shape.children) {
          for (final run in child.richText.runs) {
            if (run.text.contains(text)) return run;
          }
          final nested = runContaining(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      final alert = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / Bootstrap / bootstrap',
          )
          .stencils
          .firstWhere(
            (entry) =>
                entry.name.startsWith('Alert') &&
                () {
                  final shape = entry.build(443, 3, 3);
                  return runContaining(shape, 'Title') != null &&
                      runContaining(shape, 'Lorem ipsum') != null;
                }(),
          )
          .build(443, 3, 3);
      expect(
        runContaining(alert, 'Title')!.charStyle.fontFamily,
        'Helvetica',
        reason: 'the <b>Title</b> sits outside the CSS font-family span and '
            'keeps defaultVertex Helvetica',
      );
      expect(
        runContaining(alert, 'Lorem ipsum')!.charStyle.fontFamily,
        'Arial',
        reason: 'html font-family "open sans", arial, sans-serif walks to '
            'Arial (Open Sans is not a Visio face) that collectCharIX maps '
            'to style:font-name',
      );

      final sapTitle = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / SAP / SAP / Essentials',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Diagram Title (2)')
          .build(444, 3, 3);
      expect(
        runContaining(sapTitle, 'Diagram Level L1')!.charStyle.fontFamily,
        'Arial',
        reason: 'html font-family: arial is Char.Font Arial',
      );
      expect(
        runContaining(sapTitle, 'Keep it short')!.charStyle.fontFamily,
        'Arial',
        reason: 'the description span keeps the same CSS face',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(alert.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        runContaining(leftover, 'Title')!.charStyle.fontFamily,
        'Helvetica',
        reason: 'a second save must keep Title on defaultVertex Helvetica',
      );
      expect(
        runContaining(leftover, 'Lorem ipsum')!.charStyle.fontFamily,
        'Arial',
        reason: 'a second save must keep Char.Font',
      );

      var sapDoc = parser.parse(writer.emptyDocument());
      final sapId = sapDoc.pages.first.nextFreeShapeId();
      sapDoc = sapDoc.replacePage(
        0,
        sapDoc.pages.first.addShape(sapTitle.copyWith(id: sapId)),
      );
      final sapLeftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: sapDoc),
          )
          .pages
          .first
          .findShapeById(sapId)!;
      expect(
        runContaining(sapLeftover, 'Diagram Level L1')!.charStyle.fontFamily,
        'Arial',
        reason: 'a second save must keep SAP Diagram Title as Arial',
      );
    },
  );

  test(
    'mxText html border-bottom dotted stays a dashed Line for LibreOffice',
    () {
      VsdxTextRun? runContaining(VsdxShape shape, String text) {
        for (final child in shape.children) {
          for (final run in child.richText.runs) {
            if (run.text.contains(text)) return run;
          }
          final nested = runContaining(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      bool hasDottedUnderline(VsdxShape shape) {
        bool isDashRibbon(VsdxShape child) {
          if ((child.text ?? '').trim().isNotEmpty) return false;
          if (!child.line.hasLine) return false;
          final cmds = [
            for (final geometry in child.geometries) ...geometry.commands,
          ];
          if (cmds.length < 2) return false;
          if (cmds.any((cmd) => cmd is! MoveTo && cmd is! LineTo)) {
            return false;
          }
          final dashed = child.line.pattern >= 2 ||
              (child.line.customDashPattern?.isNotEmpty ?? false) ||
              cmds.whereType<MoveTo>().length > 1;
          return dashed;
        }

        if (shape.children.any(isDashRibbon)) return true;
        return shape.children.any(hasDottedUnderline);
      }

      Stencil stencil(String name) => dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / ER / entityRelation',
          )
          .stencils
          .singleWhere((entry) => entry.name == name);

      final key = stencil('Key Attribute').build(445, 3, 3);
      final weak = stencil('Weak Key Attribute').build(446, 3, 3);
      expect(
        runContaining(key, 'Attribute')!.charStyle.underline,
        isTrue,
        reason: 'fontStyle=4 Key Attribute is Char Style 0x4 that '
            'collectCharIX maps to style:text-underline-type',
      );
      expect(
        hasDottedUnderline(key),
        isFalse,
        reason: 'the solid underline must not grow a dashed Line sibling',
      );
      expect(
        runContaining(weak, 'Attribute')!.charStyle.underline,
        isFalse,
        reason: 'CSS border-bottom dotted is not Char Style 0x4',
      );
      expect(
        hasDottedUnderline(weak),
        isTrue,
        reason: 'the dotted rule is a collectLine sibling (1 2 dash) so '
            'Draw paints dots instead of a solid underline',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(weak.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        runContaining(leftover, 'Attribute')!.charStyle.underline,
        isFalse,
        reason: 'a second save must not freeze a solid Char underline',
      );
      expect(
        hasDottedUnderline(leftover),
        isTrue,
        reason: 'a second save must keep the dotted Line',
      );
    },
  );

  test(
    'mxText html text-align stays Para HorzAlign for LibreOffice',
    () {
      VsdxTextRun? runContaining(VsdxShape shape, String text) {
        for (final child in shape.children) {
          for (final run in child.richText.runs) {
            if (run.text.contains(text)) return run;
          }
          final nested = runContaining(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      final compartment = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / Sysml / SysML / Blocks',
          )
          .stencils
          .singleWhere(
            (entry) => entry.name == 'Stereotype Property Compartment',
          )
          .build(447, 3, 3);
      expect(
        runContaining(compartment, 'Block1')!.paraStyle.horizontalAlign,
        VsdxHorzAlign.center,
        reason: 'html text-align:center on the title <p> is collectParaIX '
            'HorzAlign that libvisio maps to fo:text-align',
      );
      expect(
        runContaining(compartment, 'property1 = value')!
            .paraStyle
            .horizontalAlign,
        VsdxHorzAlign.left,
        reason: 'the next <p text-align:left> must not inherit the cell '
            'align=center',
      );

      final namespace = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / Sysml / SysML / Blocks',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Namespace Compartment')
          .build(448, 3, 3);
      expect(
        runContaining(namespace, 'Block1')!.paraStyle.horizontalAlign,
        VsdxHorzAlign.center,
        reason: 'cell align=left still yields centered HTML <p> titles',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(compartment.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        runContaining(leftover, 'Block1')!.paraStyle.horizontalAlign,
        VsdxHorzAlign.center,
        reason: 'a second save must keep HorzAlign center on Block1',
      );
      expect(
        runContaining(leftover, 'property1 = value')!.paraStyle.horizontalAlign,
        VsdxHorzAlign.left,
        reason: 'a second save must keep HorzAlign left on the property',
      );
    },
  );

  test(
    'mxText html margin stays Para indent for LibreOffice',
    () {
      VsdxTextRun? runContaining(VsdxShape shape, String text) {
        for (final child in shape.children) {
          for (final run in child.richText.runs) {
            if (run.text.contains(text)) return run;
          }
          final nested = runContaining(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      final blocks = dynamic.singleWhere(
        (group) => group.name == 'Draw.io JS / Sysml / SysML / Blocks',
      );
      final abstract = blocks.stencils
          .where((entry) => entry.name.startsWith('Abstract Definition'))
          .map((entry) => entry.build(449, 3, 3))
          .firstWhere(
            (shape) =>
                runContaining(shape, 'Name') != null &&
                runContaining(shape, 'abstract') == null,
          );
      // 80×40 cell, catalog scale 1.5 / max(w,h) = 1.5/80.
      const abstractScale = 1.5 / 80;
      expect(
        runContaining(abstract, 'Name')!.paraStyle.indentLeftInches,
        closeTo(13 * abstractScale, 0.01),
        reason: 'html margin:13px is collectParaIX IndLeft that libvisio '
            'maps to fo:margin-left',
      );
      expect(
        runContaining(abstract, 'Name')!.paraStyle.spaceBeforeInches,
        closeTo(13 * abstractScale, 0.01),
        reason: 'the same shorthand is SpBefore / fo:margin-top',
      );
      expect(
        runContaining(abstract, 'Name')!.paraStyle.indentRightInches,
        closeTo(13 * abstractScale, 0.01),
      );
      expect(
        runContaining(abstract, 'Name')!.paraStyle.spaceAfterInches,
        closeTo(13 * abstractScale, 0.01),
      );

      final compartment = blocks.stencils
          .singleWhere(
            (entry) => entry.name == 'Stereotype Property Compartment',
          )
          .build(450, 3, 3);
      const compartmentScale = 1.5 / 200;
      expect(
        runContaining(compartment, 'property1 = value')!
            .paraStyle
            .indentLeftInches,
        closeTo(8 * compartmentScale, 0.005),
        reason: 'html margin-left:8px on the property <p> is IndLeft',
      );
      expect(
        runContaining(compartment, 'Block1')!.paraStyle.indentLeftInches,
        closeTo(0, 0.005),
        reason: 'the title <p> zeroes margin then only sets margin-top',
      );
      expect(
        runContaining(compartment, '<<stereotype1>>')!
            .paraStyle
            .spaceBeforeInches,
        closeTo(4 * compartmentScale, 0.005),
        reason: 'html margin-top:4px on the first <p> is SpBefore',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(abstract.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        runContaining(leftover, 'Name')!.paraStyle.indentLeftInches,
        closeTo(13 * abstractScale, 0.01),
        reason: 'a second save must keep Para IndLeft',
      );
      expect(
        runContaining(leftover, 'Name')!.paraStyle.spaceBeforeInches,
        closeTo(13 * abstractScale, 0.01),
        reason: 'a second save must keep Para SpBefore',
      );
    },
  );

  test(
    'mxText html UA block margin stays Para spacing for LibreOffice',
    () {
      VsdxTextRun? runContaining(VsdxShape shape, String text) {
        for (final child in shape.children) {
          for (final run in child.richText.runs) {
            if (run.text.contains(text)) return run;
          }
          final nested = runContaining(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      final header = dynamic
          .singleWhere(
            (group) =>
                group.name ==
                'Draw.io JS / Salesforce / Salesforce / Components',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Header')
          .build(449, 3, 3);
      // 930×160 cell, catalog scale 1.5 / 930. defaultVertex fontSize 12.
      const headerScale = 1.5 / 930;
      const h3Margin = 12 * 1.17;
      const pMargin = 12.0;
      final title = runContaining(header, 'Diagram Title Goes Here')!;
      final body = runContaining(header, 'Lorem ipsum')!;
      expect(
        title.charStyle.style.bold,
        isFalse,
        reason: 'h3 UA bold is cleared by inner font-weight:normal so '
            'collectCharIX Style.bold stays off',
      );
      expect(
        title.paraStyle.spaceBeforeInches,
        closeTo(h3Margin * headerScale, 0.002),
        reason: 'html h3 UA 1em (of 1.17em) is collectParaIX SpBefore that '
            'libvisio maps to fo:margin-top',
      );
      expect(
        title.paraStyle.spaceAfterInches,
        closeTo(0, 0.002),
        reason: 'adjoining h3/p margins collapse; the gap is not summed',
      );
      expect(
        body.paraStyle.spaceBeforeInches,
        closeTo(h3Margin * headerScale, 0.002),
        reason: 'collapsed max(h3 1em, p 1em) lands on the body SpBefore',
      );
      expect(
        body.paraStyle.spaceAfterInches,
        closeTo(pMargin * headerScale, 0.002),
        reason: 'the trailing p UA margin-bottom is SpAfter / fo:margin-bottom',
      );

      final actor = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / Sysml / SysML / Blocks',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Actor (2)')
          .build(450, 3, 3);
      // 160×80 cell. Bare <p> with no CSS margin.
      const actorScale = 1.5 / 160;
      expect(
        runContaining(actor, '<<actor>>')!.paraStyle.spaceBeforeInches,
        closeTo(12 * actorScale, 0.01),
        reason: 'SysML Actor <p> keeps the 1em UA margin SysML elsewhere '
            'zeroes with margin:0px',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(header.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        runContaining(leftover, 'Diagram Title Goes Here')!
            .paraStyle
            .spaceBeforeInches,
        closeTo(h3Margin * headerScale, 0.002),
        reason: 'a second save must keep Para SpBefore from html h3 UA margin',
      );
      expect(
        runContaining(leftover, 'Lorem ipsum')!.paraStyle.spaceBeforeInches,
        closeTo(h3Margin * headerScale, 0.002),
      );
      expect(
        runContaining(leftover, 'Diagram Title Goes Here')!
            .charStyle
            .style
            .bold,
        isFalse,
        reason:
            'a second save must keep Style.bold off after font-weight:normal',
      );
    },
  );

  test(
    'mxText html font size attribute stays Char Size for LibreOffice',
    () {
      VsdxTextRun? runContaining(VsdxShape shape, String text) {
        for (final child in shape.children) {
          for (final run in child.richText.runs) {
            if (run.text.contains(text)) return run;
          }
          final nested = runContaining(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      final sap = dynamic.singleWhere(
        (group) =>
            group.name == 'Draw.io JS / SAP / SAP / Annotations and Interfaces',
      );
      final iface = sap.stencils
          .singleWhere((entry) => entry.name == 'Interface')
          .build(451, 3, 3);
      // 57×16 cell, catalog scale 1.5 / max(w,h) = 1.5/57.
      const ifaceScale = 1.5 / 57;
      expect(
        runContaining(iface, 'Interface')!.charStyle.fontSizeInches,
        closeTo(10 * ifaceScale, 0.01),
        reason: 'html size="1" is Chromium xx-small 10px, collectCharIX Size '
            'that libvisio maps to fo:font-size, not parseFloat 1px',
      );

      final roadmap = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / Infographic / Infographic',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Roadmap (vertical)')
          .build(452, 3, 3);
      final title = runContaining(roadmap, 'Label')!;
      final body = runContaining(roadmap, 'Lorem ipsum')!;
      expect(
        body.charStyle.fontSizeInches,
        closeTo(title.charStyle.fontSizeInches * 10 / 12, 0.01),
        reason: 'Roadmap body <font size="1"> is 10px under a 12px Label',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(iface.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        runContaining(leftover, 'Interface')!.charStyle.fontSizeInches,
        closeTo(10 * ifaceScale, 0.01),
        reason: 'a second save must keep Char Size from html size="1"',
      );
    },
  );

  test(
    'mxText html hr stays a Line sibling for LibreOffice',
    () {
      VsdxShape? glyphContaining(VsdxShape shape, String text) {
        for (final child in shape.children) {
          if ((child.text ?? '').contains(text)) return child;
          final nested = glyphContaining(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      bool geometryHasRule(Iterable<VsdxGeometry> geos, double minDx) {
        for (final geometry in geos) {
          if (!geometry.noFill || geometry.noLine) continue;
          final cmds = geometry.commands;
          for (var i = 1; i < cmds.length; i++) {
            final prev = cmds[i - 1];
            final cur = cmds[i];
            if (prev is! MoveTo || cur is! LineTo) continue;
            final dx = (cur.x - prev.x).abs();
            final dy = (cur.y - prev.y).abs();
            if (dx > minDx && dy < 0.05) return true;
          }
        }
        return false;
      }

      bool isHorizontalRule(VsdxShape child) {
        if ((child.text ?? '').trim().isNotEmpty) return false;
        if (!child.line.hasLine || child.fill.hasFill) return false;
        return geometryHasRule(child.geometries, child.width * 0.3);
      }

      bool hasHorizontalRule(VsdxShape shape) {
        if (geometryHasRule(shape.geometries, shape.width * 0.3)) return true;
        if (shape.children.any(isHorizontalRule)) return true;
        return shape.children.any(hasHorizontalRule);
      }

      VsdxShape? ruleOn(VsdxShape shape) {
        for (final child in shape.children) {
          if (isHorizontalRule(child)) return child;
          final nested = ruleOn(child);
          if (nested != null) return nested;
        }
        return null;
      }

      final compartment = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / Sysml / SysML / Blocks',
          )
          .stencils
          .singleWhere(
            (entry) => entry.name == 'Stereotype Property Compartment',
          )
          .build(453, 3, 3);
      final title = glyphContaining(compartment, 'Block1')!;
      final body = glyphContaining(compartment, 'property1 = value')!;
      expect(
        title.id,
        isNot(body.id),
        reason: 'html <hr> splits title and property into stacked Text '
            'children collectXFormData maps to svg:y',
      );
      expect(
        title.pinY,
        greaterThan(body.pinY),
        reason: 'the title band sits above the property (Visio Y-up)',
      );
      expect(
        hasHorizontalRule(compartment),
        isTrue,
        reason: 'the rule is a collectLine sibling so Draw paints svg:stroke',
      );

      final alert = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / Bootstrap / bootstrap',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Alert (9)')
          .build(454, 3, 3);
      final alertRule = ruleOn(alert);
      expect(
        alertRule,
        isNotNull,
        reason: 'Bootstrap Alert <hr style="border: 1px solid rgb(89,185,88)">',
      );
      expect(
        alertRule!.line.color,
        VsdxColor.tryParse('#59b958'),
        reason: 'hr border-color is LineColor that collectLine maps to '
            'svg:stroke',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(compartment.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        hasHorizontalRule(leftover),
        isTrue,
        reason: 'a second save must keep the collectLine sibling',
      );
      expect(
        glyphContaining(leftover, 'Block1')!.id,
        isNot(glyphContaining(leftover, 'property1 = value')!.id),
      );
    },
  );

  test(
    'mxText html tables stay row Text boxes for LibreOffice',
    () {
      VsdxShape? glyphContaining(VsdxShape shape, String text) {
        for (final child in shape.children) {
          if ((child.text ?? '').contains(text)) return child;
          final nested = glyphContaining(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      final thermistor = dynamic
          .singleWhere(
            (group) =>
                group.name == 'Draw.io JS / Electrical / Electrical / Misc',
          )
          .stencils
          .singleWhere(
            (entry) =>
                entry.name == 'Thermistor With Independent Integral Heater',
          )
          .build(443, 3, 3);
      final temp = glyphContaining(thermistor, 'temp')!;
      expect(
        temp.height,
        closeTo(thermistor.height * 0.45, 0.04),
        reason: 'tr height=45% is a Text child collectXFormData maps to '
            'svg:height, not the full heater box',
      );
      expect(
        temp.pinY,
        closeTo(thermistor.height * (1 - 0.45 / 2), 0.05),
        reason: 'the 45% band sits at the top (Visio Y-up) so \\temp\\ is '
            'not centred on the heater',
      );

      final indicator = dynamic
          .singleWhere(
            (group) =>
                group.name ==
                'Draw.io JS / PID / Process Engineering / Instruments',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Indicator (Instrument)')
          .build(444, 3, 3);
      final ti = glyphContaining(indicator, 'TI')!;
      final hash = glyphContaining(indicator, '##')!;
      expect(
        ti.height,
        closeTo(indicator.height * 0.25, 0.04),
        reason: 'td height=25 on a 100px indicator is the first band',
      );
      expect(
        ti.pinY,
        greaterThan(hash.pinY),
        reason: 'TI is the top row; ## is the next 25px band',
      );
      expect(identical(ti, hash), isFalse);

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(thermistor.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        glyphContaining(leftover, 'temp')!.height,
        closeTo(thermistor.height * 0.45, 0.04),
        reason: 'a second save must keep the 45% band',
      );
    },
  );

  test(
    'mxText html table cellpadding stays TextBlock padding for LibreOffice',
    () {
      VsdxShape? glyphContaining(VsdxShape shape, String text) {
        for (final child in shape.children) {
          if ((child.text ?? '').contains(text)) return child;
          final nested = glyphContaining(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      final instrument = dynamic
          .singleWhere(
            (group) =>
                group.name ==
                'Draw.io JS / PID / Process Engineering / Instruments',
          )
          .stencils
          .singleWhere(
            (entry) => entry.name == 'Discrete Instrument (control room)',
          )
          .build(455, 3, 3);
      final ti = glyphContaining(instrument, 'TI')!;
      final hash = glyphContaining(instrument, '##')!;
      expect(
        identical(ti, hash),
        isFalse,
        reason: 'an unclosed last <tr> is still two HTML rows, so TI and ## '
            'are stacked Text children collectXFormData maps to svg:y',
      );
      expect(
        ti.pinY,
        greaterThan(hash.pinY),
        reason: 'TI is the top row (Visio Y-up)',
      );
      expect(
        ti.height,
        closeTo(instrument.height / 2, 0.04),
        reason: 'two equal rows share the 50×50 overflow=fill box',
      );
      // mxText default spacing 2 plus cellpadding=4. Catalog scale 1.5/50.
      const instScale = 1.5 / 50;
      expect(
        ti.richText.textBlock.marginLeftInches,
        closeTo(6 * instScale, 0.01),
        reason: 'cellpadding=4 plus spacing 2 is collectTextBlock LeftMargin '
            'that libvisio maps to fo:padding-left',
      );
      expect(
        ti.richText.textBlock.marginTopInches,
        closeTo(6 * instScale, 0.01),
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(instrument.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        glyphContaining(leftover, 'TI')!.richText.textBlock.marginLeftInches,
        closeTo(6 * instScale, 0.01),
        reason: 'a second save must keep TextBlock LeftMargin',
      );
      expect(
        identical(
          glyphContaining(leftover, 'TI'),
          glyphContaining(leftover, '##'),
        ),
        isFalse,
      );
    },
  );

  test(
    'mxText html table cell CSS padding stays TextBlock padding for LibreOffice',
    () {
      VsdxShape? glyphContaining(VsdxShape shape, String text) {
        for (final child in shape.children) {
          if ((child.text ?? '').contains(text)) return child;
          final nested = glyphContaining(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      final compressor = dynamic
          .singleWhere(
            (group) =>
                group.name ==
                'Draw.io JS / PID / Process Engineering / Compressors',
          )
          .stencils
          .singleWhere(
            (entry) => entry.name == 'Centrifugal Compressor - Turbine Driven',
          )
          .build(456, 3, 3);
      final tee = glyphContaining(compressor, 'T')!;
      expect(
        tee.height,
        closeTo(compressor.height * 0.75, 0.04),
        reason: 'tr height=75% is the lower band collectXFormData maps to '
            'svg:height',
      );
      expect(
        tee.pinY,
        closeTo(compressor.height * 0.75 / 2, 0.04),
        reason: 'the 25% empty row keeps T off the turbine top (Visio Y-up)',
      );
      // overflow=fill skips mxText spacing 2; padding-left 11% of 100px.
      const compressorScale = 1.5 / 100;
      expect(
        tee.richText.textBlock.marginLeftInches,
        closeTo(11 * compressorScale, 0.01),
        reason: 'td padding-left:11% is collectTextBlock LeftMargin that '
            'libvisio maps to fo:padding-left; overflow=fill must not add '
            'the mxText default spacing of 2',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(compressor.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        glyphContaining(leftover, 'T')!.richText.textBlock.marginLeftInches,
        closeTo(11 * compressorScale, 0.01),
        reason: 'a second save must keep TextBlock LeftMargin',
      );
    },
  );

  test(
    'mxText html font-size em stays Char Size for LibreOffice',
    () {
      VsdxTextRun? runContaining(VsdxShape shape, String text) {
        for (final child in shape.children) {
          for (final run in child.richText.runs) {
            if (run.text.contains(text)) return run;
          }
          final nested = runContaining(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      final lean = dynamic.singleWhere(
        (group) =>
            group.name == 'Draw.io JS / LeanMapping / Value Stream Mapping',
      );
      final kanban = lean.stencils
          .singleWhere((entry) => entry.name == 'Signal Kanban')
          .build(457, 3, 3);
      // 100×90 cell, catalog scale 1.5 / 100. mxText default 12px × 2em.
      const kanbanScale = 1.5 / 100;
      expect(
        runContaining(kanban, 'S')!.charStyle.fontSizeInches,
        closeTo(24 * kanbanScale, 0.01),
        reason: 'font-size:2em is 24px, collectCharIX Size that libvisio '
            'maps to fo:font-size, not parseFloat 2px',
      );

      final orders = lean.stencils
          .singleWhere((entry) => entry.name == 'Orders')
          .build(458, 3, 3);
      expect(
        runContaining(orders, 'IN')!.charStyle.fontSizeInches,
        closeTo(18 * kanbanScale, 0.01),
        reason: 'table font-size:1.5em inherits onto IN as 18px',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(kanban.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        runContaining(leftover, 'S')!.charStyle.fontSizeInches,
        closeTo(24 * kanbanScale, 0.01),
        reason: 'a second save must keep Char Size from font-size:2em',
      );
    },
  );

  test(
    'mxText html font-size stays Char Size on wide composites for LibreOffice',
    () {
      VsdxTextRun? runContaining(VsdxShape shape, String text) {
        for (final child in shape.children) {
          for (final run in child.richText.runs) {
            if (run.text.contains(text)) return run;
          }
          final nested = runContaining(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      final header = dynamic
          .singleWhere(
            (group) =>
                group.name ==
                'Draw.io JS / Salesforce / Salesforce / Components',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Header')
          .build(458, 3, 3);
      // 930×160 cell, catalog scale 1.5 / 930.
      const headerScale = 1.5 / 930;
      final title = runContaining(header, 'Diagram Title Goes Here')!;
      final body = runContaining(header, 'Lorem ipsum')!;
      expect(
        title.charStyle.fontSizeInches,
        closeTo(14 * headerScale, 0.002),
        reason: 'html font-size:14px must reach collectCharIX Size, not the '
            'old 0.04in floor that matched the 9px body',
      );
      expect(
        body.charStyle.fontSizeInches,
        closeTo(9 * headerScale, 0.002),
        reason: 'html font-size:9px is a smaller fo:font-size than the title',
      );
      expect(
        title.charStyle.fontSizeInches,
        greaterThan(body.charStyle.fontSizeInches),
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(header.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        runContaining(leftover, 'Diagram Title Goes Here')!
            .charStyle
            .fontSizeInches,
        closeTo(14 * headerScale, 0.002),
        reason: 'a second save must keep Char Size from html 14px',
      );
      expect(
        runContaining(leftover, 'Lorem ipsum')!.charStyle.fontSizeInches,
        closeTo(9 * headerScale, 0.002),
      );
    },
  );

  test(
    'mxText html text-wrap nowrap stays unwrapped for LibreOffice',
    () {
      VsdxShape? glyphContaining(VsdxShape shape, String text) {
        for (final child in shape.children) {
          if ((child.text ?? '').contains(text)) return child;
          final nested = glyphContaining(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      final title = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / SAP / SAP / Essentials',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Diagram Title (2)')
          .build(459, 3, 3);
      final glyph = glyphContaining(title, 'Diagram Level L1')!;
      expect(
        glyph.wordWrap,
        isFalse,
        reason: 'html text-wrap:nowrap wins over whiteSpace=wrap so '
            'veWordWrap bake can expand TxtWidth Draw collects as svg:width',
      );
      expect(
        glyphContaining(title, 'Keep it short')!.wordWrap,
        isFalse,
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(title.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      final leftoverGlyph = glyphContaining(leftover, 'Diagram Level L1')!;
      expect(
        leftoverGlyph.richText.textBlock.widthInches,
        greaterThan(title.width + 0.2),
        reason: 'a second save must widen TxtWidth so LibreOffice does not '
            'wrap the nowrap description to the 500px cell',
      );
    },
  );

  test(
    'mxCell xml placeholder labels stay substituted Text for LibreOffice',
    () {
      String allText(VsdxShape shape) {
        final parts = <String>[
          if ((shape.text ?? '').isNotEmpty) shape.text!,
        ];
        for (final child in shape.children) {
          final nested = allText(child);
          if (nested.isNotEmpty) parts.add(nested);
        }
        return parts.join('\n');
      }

      VsdxTextRun? runContaining(VsdxShape shape, String text) {
        for (final run in shape.richText.runs) {
          if (run.text.contains(text)) return run;
        }
        for (final child in shape.children) {
          final nested = runContaining(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      final c4 = dynamic.singleWhere(
        (group) => group.name == 'Draw.io JS / C4 / C4',
      );
      final person = c4.stencils
          .singleWhere((entry) => entry.name == 'Person')
          .build(445, 3, 3);
      final personText = allText(person);
      expect(
        personText,
        isNot(contains('[object Object]')),
        reason: 'Graph.convertValueToString reads the XML label, not '
            'Object.prototype.toString',
      );
      expect(
        personText,
        contains('Person name'),
        reason: '%c4Name% is Graph.replacePlaceholders that collectText '
            'maps to text:p',
      );
      expect(personText, contains('[Person]'));
      expect(personText, contains('Description of person.'));
      expect(
        runContaining(person, 'Person name')!.charStyle.style.bold,
        isTrue,
        reason: 'html <b>%c4Name%</b> must reach collectCharIX Style.bold',
      );
      expect(
        runContaining(person, '[Person]')!.charStyle.style.bold,
        isFalse,
      );
      expect(
        runContaining(person, 'Description of person.')!.charStyle.color?.value,
        0xFFCCCCCC,
        reason: '<font color="#cccccc"> is Char Color collectCharIX maps '
            'to fo:color',
      );

      final data = c4.stencils
          .singleWhere((entry) => entry.name == 'Data Container')
          .build(446, 3, 3);
      final dataText = allText(data);
      expect(dataText, contains('Container name'));
      expect(dataText, contains('e.g. Oracle Database 12'));
      expect(
        dataText,
        contains('Description of storage type container role/responsibility.'),
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(person.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        allText(leftover),
        contains('Person name'),
        reason: 'a second save must keep the substituted C4 name',
      );
      expect(
        runContaining(leftover, 'Person name')!.charStyle.style.bold,
        isTrue,
      );
      expect(allText(leftover), isNot(contains('[object Object]')));
    },
  );

  test(
    'mxText html multi-column tables stay cell Text boxes for LibreOffice',
    () {
      String allText(VsdxShape shape) {
        final parts = <String>[
          if ((shape.text ?? '').isNotEmpty) shape.text!,
        ];
        for (final child in shape.children) {
          final nested = allText(child);
          if (nested.isNotEmpty) parts.add(nested);
        }
        return parts.join('\n');
      }

      VsdxShape? glyphContaining(VsdxShape shape, String text) {
        if ((shape.text ?? '').contains(text)) return shape;
        for (final child in shape.children) {
          final nested = glyphContaining(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      VsdxTextRun? runContaining(VsdxShape shape, String text) {
        for (final run in shape.richText.runs) {
          if (run.text.contains(text)) return run;
        }
        for (final child in shape.children) {
          final nested = runContaining(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      final nav = dynamic.singleWhere(
        (group) => group.name == 'Draw.io JS / Mockup / Mockup Navigation',
      );
      VsdxShape? bar;
      var id = 447;
      for (final entry in nav.stencils.where((e) => e.name == 'Step Bar')) {
        final shape = entry.build(id++, 3, 3);
        if (allText(shape).contains('Layer 1') &&
            allText(shape).contains('Layer 3')) {
          bar = shape;
          break;
        }
      }
      expect(bar, isNotNull, reason: 'Step Bar html table template');
      final layer1 = glyphContaining(bar!, 'Layer 1')!;
      final layer3 = glyphContaining(bar, 'Layer 3')!;
      expect(
        identical(layer1, layer3),
        isFalse,
        reason: 'td width=25% is a Text child collectXFormData maps to svg:x, '
            'not one concatenated Char run',
      );
      expect(
        allText(bar),
        isNot(contains('Layer 1Layer 2')),
      );
      expect(
        layer1.width,
        closeTo(bar.width * 0.25, 0.04),
        reason: 'four equal columns fill the 300px bar',
      );
      expect(
        layer1.height,
        lessThan(bar.height * 0.9),
        reason: 'tr height=0% with text is a content band at the top, not '
            'the full step-dot box',
      );
      expect(
        layer1.pinY,
        greaterThan(bar.height * 0.5),
        reason: 'the 0% content row sits at the top (Visio Y-up)',
      );
      expect(layer1.pinX, lessThan(layer3.pinX));
      expect(
        runContaining(bar, 'Layer 3')!.charStyle.color?.value,
        0xFF008CFF,
        reason: 'td style color:#008cff is textColor2 Char Color '
            'collectCharIX maps to fo:color',
      );
      expect(
        runContaining(bar, 'Layer 1')!.charStyle.color?.value,
        0xFF666666,
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final leftoverId = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(bar.copyWith(id: leftoverId)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(leftoverId)!;
      expect(
        glyphContaining(leftover, 'Layer 3')!.width,
        closeTo(bar.width * 0.25, 0.04),
        reason: 'a second save must keep the 25% column',
      );
      expect(
        runContaining(leftover, 'Layer 3')!.charStyle.color?.value,
        0xFF008CFF,
      );
    },
  );

  test(
    'mxGraph style fillColor stays FillForegnd for LibreOffice',
    () {
      bool hasForeground(VsdxShape shape, int argb) {
        if (shape.fill.hasFill && shape.fill.foreground?.value == argb) {
          return true;
        }
        return shape.children.any((child) => hasForeground(child, argb));
      }

      bool hasLine(VsdxShape shape, int argb) {
        if (shape.line.hasLine && shape.line.color?.value == argb) {
          return true;
        }
        return shape.children.any((child) => hasLine(child, argb));
      }

      final person = dynamic
          .singleWhere((group) => group.name == 'Draw.io JS / C4 / C4')
          .stencils
          .singleWhere((entry) => entry.name == 'Person')
          .build(448, 3, 3);
      expect(
        hasForeground(person, 0xFF083F75),
        isTrue,
        reason: 'fillColor=#083F75 must reach collectFill svg:fill, not '
            'defaultFill #DAE8FC after applyStencilStyle',
      );
      expect(
        hasLine(person, 0xFF06315C),
        isTrue,
        reason: 'strokeColor=#06315C must reach collectLine svg:stroke',
      );
      expect(hasForeground(person, 0xFFDAE8FC), isFalse);

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(person.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        hasForeground(leftover, 0xFF083F75),
        isTrue,
        reason: 'a second save must keep the C4 navy FillForegnd',
      );
    },
  );

  test(
    'mxGraph fillColor=strokeColor stays FillForegnd for LibreOffice',
    () {
      final initial = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / UML25 / uml 2.5',
          )
          .stencils
          .singleWhere(
            (entry) => entry.name == 'Initial preudostate / node',
          )
          .build(460, 3, 3);
      expect(
        initial.fill.hasFill,
        isTrue,
        reason: 'fillColor=strokeColor is a filled ellipse collectFill maps '
            'to svg:fill',
      );
      expect(
        initial.fill.foreground?.value,
        0xFF000000,
        reason: 'the keyword follows defaultVertex stroke (black), not '
            'palette #DAE8FC',
      );

      final junction = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / ArchiMate / archiMate21',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Junction')
          .build(461, 3, 3);
      expect(
        junction.fill.foreground?.value,
        0xFF000000,
        reason: 'ArchiMate Junction fillColor=strokeColor is the same disc',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(initial.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        leftover.fill.foreground?.value,
        0xFF000000,
        reason:
            'a second save must keep FillForegnd from fillColor=strokeColor',
      );
    },
  );

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

  test(
    'mxArrowConnector link and flexArrow stay native for LibreOffice',
    () {
      Stencil stencil(String groupName, String shapeName) => dynamic
          .singleWhere((group) => group.name == groupName)
          .stencils
          .singleWhere((entry) => entry.name == shapeName);

      final link = stencil(
        'Draw.io JS / BPMN / BPMN 2.0  General',
        'Conversation Link',
      ).build(53, 3, 3);
      expect(link.geometries.where((geometry) => !geometry.noFill), isEmpty);
      expect(
        link.geometries
            .expand((geometry) => geometry.commands)
            .whereType<MoveTo>()
            .length,
        greaterThanOrEqualTo(2),
        reason:
            'shape=link isOpenEnded paints two parallel rails, not a polyline',
      );

      final flex = stencil(
        'Draw.io JS / LeanMapping / Value Stream Mapping',
        'Shipments',
      ).build(54, 3, 3);
      expect(
        flex.geometries.where((geometry) => !geometry.noFill),
        hasLength(1),
        reason: 'flexArrow paintEdgeShape is one filled arrow body',
      );
      expect(
        flex.geometries
            .expand((geometry) => geometry.commands)
            .whereType<LineTo>()
            .length,
        greaterThanOrEqualTo(3),
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final linkId = doc.pages.first.nextFreeShapeId();
      var page = doc.pages.first.addShape(stencil(
        'Draw.io JS / BPMN / BPMN 2.0  General',
        'Conversation Link',
      ).build(linkId, 3, 3));
      final flexId = page.nextFreeShapeId();
      page = page.addShape(stencil(
        'Draw.io JS / LeanMapping / Value Stream Mapping',
        'Shipments',
      ).build(flexId, 5, 3));
      doc = doc.replacePage(0, page);
      final leftover = parser
          .parse(
              writer.write(originalBytes: writer.emptyDocument(), edited: doc))
          .pages
          .first;
      expect(
        leftover
            .findShapeById(linkId)!
            .geometries
            .expand((geometry) => geometry.commands)
            .whereType<MoveTo>()
            .length,
        greaterThanOrEqualTo(2),
      );
      expect(
        leftover
            .findShapeById(flexId)!
            .geometries
            .where((geometry) => !geometry.noFill),
        hasLength(1),
      );
    },
  );

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
      wire.geometries.where((g) => g.noFill && !g.noLine).isNotEmpty ||
          wire.children.any(
            (child) => child.geometries.any((g) => g.noFill && !g.noLine),
          ),
      isTrue,
      reason: 'shape=wire paintEdgeShape must stroke, not a filled rectangle',
    );
    expect(
      wire.line.pattern == 2 ||
          wire.children.any(
            (child) =>
                child.line.hasLine &&
                (child.line.pattern == 2 ||
                    (child.line.customDashPattern?.isNotEmpty ?? false)),
          ),
      isTrue,
      reason: 'Dashed Wire style dashed=1 is LinePattern 2 or veDashPattern',
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
      descendantGeometries(buttons).length,
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
      descendantGeometries(leftover.findShapeById(btnId)!).length,
      greaterThan(2),
    );
  });

  test('mxGraph direction=south stays inside the cell box for LibreOffice', () {
    ({double minX, double minY, double maxX, double maxY}) aabb(
      Iterable<VsdxGeometry> geometries,
    ) {
      var minX = double.infinity, minY = double.infinity;
      var maxX = -double.infinity, maxY = -double.infinity;
      void acc(double x, double y) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }

      for (final geometry in geometries) {
        for (final command in geometry.commands) {
          switch (command) {
            case MoveTo(:final x, :final y):
            case LineTo(:final x, :final y):
              acc(x, y);
            case CubBezTo(
                :final x,
                :final y,
                :final x1,
                :final y1,
                :final x2,
                :final y2
              ):
              acc(x, y);
              acc(x1, y1);
              acc(x2, y2);
            default:
              break;
          }
        }
      }
      return (minX: minX, minY: minY, maxX: maxX, maxY: maxY);
    }

    final cabinet = dynamic
        .singleWhere(
          (group) => group.name == 'Draw.io JS / Cabinet / cabinets',
        )
        .stencils
        .singleWhere(
          (entry) => entry.name == 'Panel Wiring System 25x40mm (Vertical)',
        )
        .build(102, 3, 3);
    expect(
      cabinet.width,
      lessThan(cabinet.height),
      reason: 'the south panel cell is 12.5×350, not a landscape bar',
    );
    final box = aabb(cabinet.geometries);
    expect(
      box.maxX - box.minX,
      closeTo(cabinet.width, 0.08),
      reason: 'isPaintBoundsInverted + rotate must keep collectGeometry '
          'inside svg:width, not a 350px path scaled by 1.5/12.5',
    );
    expect(
      box.maxY - box.minY,
      closeTo(cabinet.height, 0.08),
    );

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        dynamic
            .singleWhere(
              (group) => group.name == 'Draw.io JS / Cabinet / cabinets',
            )
            .stencils
            .singleWhere(
              (entry) => entry.name == 'Panel Wiring System 25x40mm (Vertical)',
            )
            .build(id, 3, 3),
      ),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    final leftoverBox = aabb(leftover.geometries);
    expect(
      leftoverBox.maxX - leftoverBox.minX,
      closeTo(leftover.width, 0.08),
      reason: 'a second save must keep the south contour in the cell box',
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
    for (final geometry in descendantGeometries(buttons)) {
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
      if (lines == 3 && w > h) {
        chevron = (w: w, h: h, lines: lines);
        break;
      }
    }
    expect(
      chevron,
      isNotNull,
      reason: 'shape=triangle;direction=south must bake a 3-point chevron '
          'pointing down in the cell (isPaintBoundsInverted), not a diamond',
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
      descendantGeometries(leftover).any((geometry) {
        return geometry.commands.whereType<LineTo>().length == 3;
      }),
      isTrue,
    );
  });

  test(
    'mxGraph dashed vertices clouds cylinders and double ellipses stay native for LibreOffice',
    () {
      Stencil stencil(String groupName, String shapeName) => dynamic
          .singleWhere((group) => group.name == groupName)
          .stencils
          .singleWhere((entry) => entry.name == shapeName);

      final signature = stencil(
        'Draw.io JS / UML25 / uml 2.5',
        'Template signature',
      ).build(90, 3, 3);
      expect(
        signature.line.pattern,
        2,
        reason:
            'mxShape.configureCanvas dashed=1 is LinePattern 2 in tokens.txt',
      );

      final cloud = stencil(
        'Draw.io JS / DFD / Data Flow Diagram',
        'Object',
      ).build(91, 3, 3);
      expect(
        cloud.geometries.expand((geometry) => geometry.commands).any(
              (command) => command is CubBezTo,
            ),
        isTrue,
        reason: 'shape=cloud must use mxCloud.redrawPath, not an ellipse',
      );

      final doubleEllipse = stencil(
        'Draw.io JS / ThreatModeling / Threat Modeling',
        'Multi-Process',
      ).build(92, 3, 3);
      expect(doubleEllipse.geometries, hasLength(2));
      expect(doubleEllipse.geometries.first.noFill, isFalse);
      expect(doubleEllipse.geometries.last.noFill, isTrue);

      final cylinder = stencil(
        'Draw.io JS / DFD / Data Flow Diagram',
        'Data Store (3)',
      ).build(93, 3, 3);
      expect(
        cylinder.geometries.where((geometry) => !geometry.noFill),
        hasLength(1),
        reason: 'mxCylinder is one filled body plus a lid stroke; stacked '
            'ellipses would evenodd-punch in collectGeometry',
      );
      expect(
        cylinder.geometries.expand((geometry) => geometry.commands).any(
              (command) => command is CubBezTo,
            ),
        isTrue,
      );

      final partial = stencil(
        'Draw.io JS / Basic / basic',
        'Partial Rectangle (2)',
      ).build(94, 3, 3);
      expect(
        partial.geometries.every((geometry) => geometry.noFill),
        isTrue,
        reason: 'fillColor=none must not leave a fill libvisio would paint',
      );
      expect(
        partial.geometries
            .expand((geometry) => geometry.commands)
            .whereType<MoveTo>()
            .length,
        greaterThan(1),
        reason: 'top=0;bottom=0 skips those sides with moveTo',
      );

      final parallelogram = stencil(
        'Draw.io JS / DFD / Data Flow Diagram',
        'Product / Result',
      ).build(95, 3, 3);
      expect(
        parallelogram.geometries
            .expand((geometry) => geometry.commands)
            .whereType<LineTo>()
            .length,
        4,
        reason: 'parallelogram redrawPath needs addPoints, not mxActor',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final cloudId = doc.pages.first.nextFreeShapeId();
      var page = doc.pages.first.addShape(stencil(
        'Draw.io JS / DFD / Data Flow Diagram',
        'Object',
      ).build(cloudId, 3, 3));
      final dashId = page.nextFreeShapeId();
      page = page.addShape(stencil(
        'Draw.io JS / UML25 / uml 2.5',
        'Template signature',
      ).build(dashId, 5, 3));
      final cylId = page.nextFreeShapeId();
      page = page.addShape(stencil(
        'Draw.io JS / DFD / Data Flow Diagram',
        'Data Store (3)',
      ).build(cylId, 7, 3));
      doc = doc.replacePage(0, page);
      final leftover = parser
          .parse(
              writer.write(originalBytes: writer.emptyDocument(), edited: doc))
          .pages
          .first;
      expect(
        leftover
            .findShapeById(cloudId)!
            .geometries
            .expand((geometry) => geometry.commands)
            .any((command) => command is CubBezTo || command is RelCubBezTo),
        isTrue,
      );
      expect(leftover.findShapeById(dashId)!.line.pattern, 2);
      expect(
        leftover
            .findShapeById(cylId)!
            .geometries
            .where((geometry) => !geometry.noFill),
        hasLength(1),
      );
    },
  );

  test(
    'mxRectangleShape subclasses keep paintForeground rails for LibreOffice',
    () {
      Stencil stencil(String groupName, String shapeName) => dynamic
          .singleWhere((group) => group.name == groupName)
          .stencils
          .singleWhere((entry) => entry.name == shapeName);

      final storage = stencil(
        'Draw.io JS / Flowchart / flowchart',
        'Internal Storage',
      ).build(96, 3, 3);
      expect(
        storage.geometries
            .where((geometry) => geometry.noFill && !geometry.noLine),
        hasLength(2),
        reason: 'internalStorage paintForeground must stroke the T-divider, '
            'not a bare rectangle',
      );

      final process = stencil(
        'Draw.io JS / Flowchart / flowchart',
        'Predefined Process',
      ).build(97, 3, 3);
      expect(
        process.geometries.any((geometry) {
          return geometry.noFill &&
              !geometry.noLine &&
              geometry.commands.whereType<MoveTo>().length >= 2 &&
              geometry.commands.whereType<LineTo>().length >= 2;
        }),
        isTrue,
        reason: 'process paintForeground must stroke the two inner rails',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final storageId = doc.pages.first.nextFreeShapeId();
      var page = doc.pages.first.addShape(stencil(
        'Draw.io JS / Flowchart / flowchart',
        'Internal Storage',
      ).build(storageId, 3, 3));
      final processId = page.nextFreeShapeId();
      page = page.addShape(stencil(
        'Draw.io JS / Flowchart / flowchart',
        'Predefined Process',
      ).build(processId, 5, 3));
      doc = doc.replacePage(0, page);
      final leftover = parser
          .parse(
              writer.write(originalBytes: writer.emptyDocument(), edited: doc))
          .pages
          .first;
      expect(
        leftover
            .findShapeById(storageId)!
            .geometries
            .where((geometry) => geometry.noFill && !geometry.noLine),
        hasLength(2),
      );
      expect(
        leftover
            .findShapeById(processId)!
            .geometries
            .any((geometry) => geometry.noFill && !geometry.noLine),
        isTrue,
      );
    },
  );

  test(
    'named styles and mxSwimlane title bars stay native for LibreOffice',
    () {
      Stencil stencil(String groupName, String shapeName) => dynamic
          .singleWhere((group) => group.name == groupName)
          .stencils
          .singleWhere((entry) => entry.name == shapeName);

      double spanX(VsdxGeometry geometry) {
        var min = double.infinity;
        var max = -double.infinity;
        for (final command in geometry.commands) {
          final x = switch (command) {
            MoveTo(:final x) => x,
            LineTo(:final x) => x,
            _ => null,
          };
          if (x == null) continue;
          if (x < min) min = x;
          if (x > max) max = x;
        }
        return max - min;
      }

      double spanY(VsdxGeometry geometry) {
        var min = double.infinity;
        var max = -double.infinity;
        for (final command in geometry.commands) {
          final y = switch (command) {
            MoveTo(:final y) => y,
            LineTo(:final y) => y,
            _ => null,
          };
          if (y == null) continue;
          if (y < min) min = y;
          if (y > max) max = y;
        }
        return max - min;
      }

      final vertical = stencil(
        'Draw.io JS / BPMN / BPMN 2.0  General',
        'Vertical Swimlane',
      ).build(98, 3, 3);
      expect(
        vertical.geometries.where((geometry) => !geometry.noFill),
        hasLength(1),
        reason: 'mxSwimlane fills the startSize title, not the whole box',
      );
      expect(
        vertical.geometries
            .where((geometry) => geometry.noFill && !geometry.noLine)
            .length,
        greaterThanOrEqualTo(2),
        reason: 'body + divider stay strokes so evenodd cannot punch the title',
      );
      expect(
        spanY(vertical.geometries.firstWhere((geometry) => !geometry.noFill)),
        lessThan(vertical.height * 0.2),
      );

      final horizontal = stencil(
        'Draw.io JS / BPMN / BPMN 2.0  General',
        'Horizontal Swimlane',
      ).build(99, 3, 3);
      expect(
        horizontal.geometries.where((geometry) => !geometry.noFill),
        hasLength(1),
      );
      expect(
        spanX(
          horizontal.geometries.firstWhere((geometry) => !geometry.noFill),
        ),
        lessThan(horizontal.width * 0.2),
      );

      final collection = stencil(
        'Draw.io JS / BPMN / BPMN 2.0  General',
        'Horizontal Lane (3)',
      ).build(100, 3, 3);
      expect(
        collection.geometries.last.commands.whereType<MoveTo>().length,
        3,
        reason: 'mxgraph.bpmn.swimlane paints collection ticks after the lane',
      );

      final icon = stencil(
        'Draw.io JS / UML25 / uml 2.5',
        'Icon',
      ).build(101, 3, 3);
      expect(
        icon.geometries.expand((geometry) => geometry.commands).any(
              (command) => command is EllipseCmd,
            ),
        isTrue,
        reason: 'naked ellipse; named style must not stay an unregistered rect',
      );

      final rhombus = stencil(
        'Draw.io JS / UML25 / uml 2.5',
        'Choice / Merge Node / Decision Node',
      ).build(102, 3, 3);
      expect(
        rhombus.geometries
            .expand((geometry) => geometry.commands)
            .whereType<LineTo>()
            .length,
        4,
        reason: 'naked rhombus; named style uses mxRhombus, not a rectangle',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final verticalId = doc.pages.first.nextFreeShapeId();
      var page = doc.pages.first.addShape(stencil(
        'Draw.io JS / BPMN / BPMN 2.0  General',
        'Vertical Swimlane',
      ).build(verticalId, 3, 3));
      final iconId = page.nextFreeShapeId();
      page = page.addShape(stencil(
        'Draw.io JS / UML25 / uml 2.5',
        'Icon',
      ).build(iconId, 5, 3));
      doc = doc.replacePage(0, page);
      final leftover = parser
          .parse(
              writer.write(originalBytes: writer.emptyDocument(), edited: doc))
          .pages
          .first;
      expect(
        leftover
            .findShapeById(verticalId)!
            .geometries
            .where((geometry) => !geometry.noFill),
        hasLength(1),
      );
      expect(
        leftover
            .findShapeById(iconId)!
            .geometries
            .expand((geometry) => geometry.commands)
            .any((command) => command is EllipseCmd),
        isTrue,
      );
    },
  );

  test(
    'mxRectangleShape default vertices stay native for LibreOffice',
    () {
      Stencil stencil(String groupName, String shapeName) => dynamic
          .singleWhere((group) => group.name == groupName)
          .stencils
          .singleWhere((entry) => entry.name == shapeName);

      final process = stencil(
        'Draw.io JS / Flowchart / flowchart',
        'Process',
      ).build(110, 3, 3);
      expect(
        process.geometries.where((geometry) => !geometry.noFill),
        hasLength(1),
        reason: 'rounded=1;absoluteArcSize=1 is mxRectangleShape roundrect',
      );
      expect(
        process.geometries
            .expand((geometry) => geometry.commands)
            .any((command) => command is CubBezTo),
        isTrue,
        reason: 'arcSize=14 must not collapse to a sharp four-line rect',
      );

      final zone = stencil(
        'Draw.io JS / AWS4 / AWS / Groups',
        'Availability Zone',
      ).build(111, 3, 3);
      expect(
        zone.geometries.every((geometry) => geometry.noFill),
        isTrue,
        reason: 'fillColor=none group box must not leave a fill plate',
      );
      expect(
        zone.line.pattern,
        2,
        reason: 'dashed=1 Availability Zone is LinePattern 2 in tokens.txt',
      );

      final security = stencil(
        'Draw.io JS / AWS4 / AWS / Groups',
        'Security group',
      ).build(112, 3, 3);
      expect(
        security.geometries.every((geometry) => geometry.noFill),
        isTrue,
      );
      expect(security.line.pattern, 1);

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final processId = doc.pages.first.nextFreeShapeId();
      var page = doc.pages.first.addShape(stencil(
        'Draw.io JS / Flowchart / flowchart',
        'Process',
      ).build(processId, 3, 3));
      final zoneId = page.nextFreeShapeId();
      page = page.addShape(stencil(
        'Draw.io JS / AWS4 / AWS / Groups',
        'Availability Zone',
      ).build(zoneId, 5, 3));
      doc = doc.replacePage(0, page);
      final leftover = parser
          .parse(
              writer.write(originalBytes: writer.emptyDocument(), edited: doc))
          .pages
          .first;
      expect(
        leftover
            .findShapeById(processId)!
            .geometries
            .expand((geometry) => geometry.commands)
            .any((command) => command is CubBezTo || command is RelCubBezTo),
        isTrue,
      );
      expect(
        leftover.findShapeById(zoneId)!.line.pattern,
        2,
      );
    },
  );

  test(
    'mxStencil flowchart vertices stay native for LibreOffice',
    () {
      Stencil stencil(String groupName, String shapeName) => dynamic
          .singleWhere((group) => group.name == groupName)
          .stencils
          .singleWhere((entry) => entry.name == shapeName);

      final terminator = stencil(
        'Draw.io JS / Flowchart / flowchart',
        'Terminator',
      ).build(120, 3, 3);
      expect(
        terminator.geometries.where((geometry) => !geometry.noFill),
        hasLength(1),
        reason: 'mxgraph.flowchart.terminator is one stadium fillstroke',
      );
      expect(
        terminator.geometries
            .expand((geometry) => geometry.commands)
            .any((command) => command is CubBezTo),
        isTrue,
        reason: 'end caps are SVG arcs, not a sharp rectangle',
      );

      final decision = stencil(
        'Draw.io JS / Flowchart / flowchart',
        'Decision',
      ).build(121, 3, 3);
      expect(
        decision.geometries.where((geometry) => !geometry.noFill),
        hasLength(1),
      );
      expect(
        decision.geometries
            .expand((geometry) => geometry.commands)
            .whereType<LineTo>()
            .length,
        4,
        reason: 'mxgraph.flowchart.decision is a diamond, not a rectangle',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final terminatorId = doc.pages.first.nextFreeShapeId();
      var page = doc.pages.first.addShape(stencil(
        'Draw.io JS / Flowchart / flowchart',
        'Terminator',
      ).build(terminatorId, 3, 3));
      final decisionId = page.nextFreeShapeId();
      page = page.addShape(stencil(
        'Draw.io JS / Flowchart / flowchart',
        'Decision',
      ).build(decisionId, 5, 3));
      doc = doc.replacePage(0, page);
      final leftover = parser
          .parse(
              writer.write(originalBytes: writer.emptyDocument(), edited: doc))
          .pages
          .first;
      expect(
        leftover
            .findShapeById(terminatorId)!
            .geometries
            .expand((geometry) => geometry.commands)
            .any((command) => command is CubBezTo || command is RelCubBezTo),
        isTrue,
      );
      expect(
        leftover
            .findShapeById(decisionId)!
            .geometries
            .expand((geometry) => geometry.commands)
            .whereType<LineTo>()
            .length,
        greaterThanOrEqualTo(4),
      );
    },
  );

  test(
    'mxImageShape SVG icons and ArchiMate rounded stay native for LibreOffice',
    () {
      Stencil stencil(String groupName, String shapeName) => dynamic
          .singleWhere((group) => group.name == groupName)
          .stencils
          .singleWhere((entry) => entry.name == shapeName);

      final bot = stencil(
        'Draw.io JS / Azure2 / Azure / AI and Machine Learning',
        'Bot Services',
      ).build(130, 3, 3);
      expect(
        descendantGeometries(bot).where((geometry) => !geometry.noFill),
        isNotEmpty,
        reason: 'Azure2 SVG image; must vectorise, not drop as a raster',
      );
      expect(
        descendantGeometries(bot).expand((geometry) => geometry.commands),
        anyOf(
          contains(isA<EllipseCmd>()),
          contains(isA<CubBezTo>()),
        ),
        reason: 'Bot Services badge is a circle plus glyph paths',
      );

      final bonsai = stencil(
        'Draw.io JS / Azure2 / Azure / AI and Machine Learning',
        'Bonsai',
      ).build(131, 3, 3);
      expect(
        descendantGeometries(bonsai).where((geometry) => !geometry.noFill),
        isNotEmpty,
        reason: 'Bonsai.svg <use href="#id"> must paint defs geometry',
      );

      final work = stencil(
        'Draw.io JS / ArchiMate / archiMate21',
        'Work Package',
      ).build(132, 3, 3);
      expect(
        work.geometries.where((geometry) => !geometry.noFill),
        hasLength(1),
        reason: 'shape=mxgraph.archimate.rounded=1 is a rounded rectangle',
      );
      expect(
        work.geometries
            .expand((geometry) => geometry.commands)
            .any((command) => command is CubBezTo),
        isTrue,
        reason: 'concatenated rounded=1 must not collapse to a sharp rect',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final botId = doc.pages.first.nextFreeShapeId();
      var page = doc.pages.first.addShape(stencil(
        'Draw.io JS / Azure2 / Azure / AI and Machine Learning',
        'Bot Services',
      ).build(botId, 3, 3));
      final workId = page.nextFreeShapeId();
      page = page.addShape(stencil(
        'Draw.io JS / ArchiMate / archiMate21',
        'Work Package',
      ).build(workId, 5, 3));
      doc = doc.replacePage(0, page);
      final leftover = parser
          .parse(
              writer.write(originalBytes: writer.emptyDocument(), edited: doc))
          .pages
          .first;
      expect(
        descendantGeometries(leftover.findShapeById(botId)!)
            .where((geometry) => !geometry.noFill),
        isNotEmpty,
      );
      expect(
        leftover
            .findShapeById(workId)!
            .geometries
            .expand((geometry) => geometry.commands)
            .any((command) => command is CubBezTo || command is RelCubBezTo),
        isTrue,
      );
    },
  );

  test(
    'mxImageShape SVG class fills stay FillForegnd for LibreOffice',
    () {
      VsdxShape? labelOf(VsdxShape shape, String text) {
        for (final child in shape.children) {
          if (child.text == text) return child;
          final nested = labelOf(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      Iterable<VsdxColor> descendantFills(VsdxShape shape) sync* {
        if (shape.fill.hasFill && shape.fill.foreground != null) {
          yield shape.fill.foreground!;
        }
        for (final child in shape.children) {
          yield* descendantFills(child);
        }
      }

      final vertex = dynamic
          .singleWhere(
            (group) =>
                group.name ==
                'Draw.io JS / GCP2 / GCP Icons / AI and Machine Learning',
          )
          .stencils
          .map((entry) => entry.build(133, 3, 3))
          .firstWhere(
            (shape) => labelOf(shape, 'Vertex AI') != null,
            orElse: () => throw StateError('Vertex AI icon missing'),
          );
      final fills = descendantFills(vertex).toSet();
      expect(
        fills,
        containsAll(<VsdxColor>[
          VsdxColor.tryParse('#B5CBF9')!,
          VsdxColor.tryParse('#769EF5')!,
          VsdxColor.tryParse('#5986F2')!,
        ]),
        reason: 'SVG .st0/.st1/.st2 fills must reach collectFill as '
            'FillForegnd, not the path default black',
      );
      expect(
        fills.contains(VsdxColor.black),
        isFalse,
        reason: 'class stylesheet fills must replace the #000 path default',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc =
          doc.replacePage(0, doc.pages.first.addShape(vertex.copyWith(id: id)));
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        descendantFills(leftover).toSet(),
        containsAll(<VsdxColor>[
          VsdxColor.tryParse('#B5CBF9')!,
          VsdxColor.tryParse('#769EF5')!,
          VsdxColor.tryParse('#5986F2')!,
        ]),
        reason: 'a second save must keep the SVG class FillForegnd hex',
      );
    },
  );

  test(
    'mxImageShape SVG url(#gradient) stays FillPattern 25–40 for LibreOffice',
    () {
      final cyan = VsdxColor.tryParse('#00B8F1')!;
      final navy = VsdxColor.tryParse('#1E5FBB')!;

      bool isSapLogoRamp(VsdxFill fill) {
        if (!fill.hasFill || fill.pattern < 25 || fill.pattern > 40) {
          return false;
        }
        final colors = <VsdxColor?>{fill.foreground, fill.background};
        return colors.contains(cyan) && colors.contains(navy);
      }

      Iterable<VsdxFill> descendantFills(VsdxShape shape) sync* {
        yield shape.fill;
        for (final child in shape.children) {
          yield* descendantFills(child);
        }
      }

      final sap = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / SAP / SAP / Brand Names',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'SAP')
          .build(134, 3, 3);
      expect(
        descendantFills(sap).any(isSapLogoRamp),
        isTrue,
        reason: 'SAP_Logo.svg fill=url(#b) must become FillPattern 25–40 '
            'that libvisio _fillAndShadowProperties maps to draw:style=linear',
      );
      expect(
        descendantFills(sap).any(
          (fill) =>
              fill.hasFill &&
              fill.pattern == 1 &&
              fill.foreground == VsdxColor.white,
        ),
        isTrue,
        reason: 'SAP wordmark fill=#ffffff must stay a sibling, not inherit '
            'the vertex palette',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(
          dynamic
              .singleWhere(
                (group) => group.name == 'Draw.io JS / SAP / SAP / Brand Names',
              )
              .stencils
              .singleWhere((entry) => entry.name == 'SAP')
              .build(id, 3, 3),
        ),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        descendantFills(leftover).any(isSapLogoRamp),
        isTrue,
        reason: 'a second save must keep the SAP Logo FillPattern ramp',
      );
    },
  );

  test(
    'mxgraph.sap.icon SVG stays FillPattern 25–40 for LibreOffice',
    () {
      final cyan = VsdxColor.tryParse('#0195FF')!;
      final navy = VsdxColor.tryParse('#1147E9')!;
      final lockCyan = VsdxColor.tryParse('#1348FF')!;
      final lockNavy = VsdxColor.tryParse('#06238D')!;

      bool hasRamp(VsdxFill fill, VsdxColor a, VsdxColor b) {
        if (!fill.hasFill || fill.pattern < 25 || fill.pattern > 40) {
          return false;
        }
        final colors = <VsdxColor?>{fill.foreground, fill.background};
        return colors.contains(a) && colors.contains(b);
      }

      Iterable<VsdxFill> descendantFills(VsdxShape shape) sync* {
        yield shape.fill;
        for (final child in shape.children) {
          yield* descendantFills(child);
        }
      }

      final pki = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / SAP / SAP / Foundational',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'SAP PKI Certificate Service')
          .build(135, 3, 3);
      expect(
        descendantGeometries(pki)
            .expand((geometry) => geometry.commands)
            .whereType<CubBezTo>()
            .length,
        greaterThanOrEqualTo(8),
        reason: 'mxgraph.sap.icon SAPIcon=SAP_PKI_Certificate_Service '
            'must vectorise img/lib/sap/*.svg, not only the grey ellipse',
      );
      expect(
        descendantFills(pki).any((fill) => hasRamp(fill, cyan, navy)),
        isTrue,
        reason: 'linear-gradient #0195ff→#1147e9 plus gradientTransform '
            'must become FillPattern 25–40 that libvisio maps to '
            'draw:style=linear',
      );
      expect(
        descendantFills(pki).any((fill) => hasRamp(fill, lockCyan, lockNavy)),
        isTrue,
        reason: 'the evenodd lock glyph uses the second linearGradient',
      );
      expect(
        descendantFills(pki).any(
          (fill) =>
              fill.hasFill &&
              fill.pattern >= 25 &&
              fill.pattern <= 40 &&
              fill.pattern == 28,
        ),
        isTrue,
        reason: 'Adobe Y-flip gradientTransform must map the ramp to south '
            '(FillPattern 28), not north (30)',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(pki.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        descendantFills(leftover).any((fill) => hasRamp(fill, cyan, navy)),
        isTrue,
        reason: 'a second save must keep the SAP PKI FillPattern ramp',
      );
    },
  );

  test(
    'mxImageShape SVG stroke-width stays LineWeight for LibreOffice',
    () {
      Iterable<VsdxShape> descendants(VsdxShape shape) sync* {
        yield shape;
        for (final child in shape.children) {
          yield* descendants(child);
        }
      }

      final cloud = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / SAP / SAP / Data Analytics',
          )
          .stencils
          .singleWhere(
            (entry) => entry.name == 'SAP Analytics Cloud Embedded Edition',
          )
          .build(136, 3, 3);
      final arc = descendants(cloud).where(
        (shape) =>
            !shape.fill.hasFill &&
            shape.line.hasLine &&
            shape.line.color == VsdxColor.tryParse('#0195FF'),
      );
      expect(arc, isNotEmpty, reason: 'the crescent is fill=none + stroke');
      expect(
        arc.first.line.weightInches,
        greaterThan(0.04),
        reason: 'SVG stroke-width=1.875 (scaled into the icon) must reach '
            'collectLine LineWeight, not the 0.01 in palette default',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(cloud.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        descendants(leftover).any(
          (shape) =>
              !shape.fill.hasFill &&
              shape.line.hasLine &&
              shape.line.weightInches > 0.04,
        ),
        isTrue,
        reason: 'a second save must keep the SVG stroke LineWeight',
      );
    },
  );

  test(
    'mxImageShape SVG text stays Char cells for LibreOffice',
    () {
      VsdxShape? labelOf(VsdxShape shape, String text) {
        for (final child in shape.children) {
          if (child.text == text) return child;
          final nested = labelOf(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      final ddos = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / Cumulus / Cumulus',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'DDos Server')
          .build(137, 3, 3);
      final glyph = labelOf(ddos, 'DDos');
      expect(
        glyph,
        isNotNull,
        reason: 'ddos_server.svg <tspan>DDos</tspan> must reach collectCharIX, '
            'not only the sidebar IP label',
      );
      expect(
        glyph!.richText.runs.first.charStyle.color,
        VsdxColor.white,
        reason: 'fill="#fff" must stay Char Color that collectCharIX maps '
            'to fo:color',
      );
      expect(
        glyph.richText.runs.first.charStyle.fontSizeInches,
        greaterThan(0.04),
        reason: 'tspan font-size=5.333 scaled into the icon must exceed '
            'Visio\'s 0.5pt Char.Size floor',
      );
      expect(labelOf(ddos, '192.168.0.32'), isNotNull);

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(ddos.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        labelOf(leftover, 'DDos'),
        isNotNull,
        reason: 'a second save must keep the SVG text glyph',
      );
    },
  );

  test(
    'mxImageShape SVG textPath stays rotated Char cells for LibreOffice',
    () {
      Iterable<VsdxShape> descendants(VsdxShape shape) sync* {
        yield shape;
        for (final child in shape.children) {
          yield* descendants(child);
        }
      }

      final keyMgmt = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / IBM / IBM / Blockchain',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Key Management')
          .build(138, 3, 3);
      final letters = descendants(keyMgmt)
          .where((shape) => (shape.text ?? '').trim().isNotEmpty)
          .toList(growable: false);
      expect(
        letters.map((shape) => shape.text).join(),
        'KEYMGMT',
        reason: 'key_management.svg <textPath>KEY MGMT</textPath> must reach '
            'collectCharIX as Char siblings, not be skipped',
      );
      expect(
        letters.every(
          (shape) =>
              shape.richText.runs.first.charStyle.color == VsdxColor.white &&
              shape.richText.runs.first.charStyle.style.bold &&
              shape.richText.runs.first.charStyle.fontSizeInches > 0.04 &&
              shape.richText.textBlock.angleRad.abs() > 0.2,
        ),
        isTrue,
        reason: 'fill="#fff" / MyriadPro-Bold / startOffset tangent become '
            'Char Color / Style / TxtAngle that collectCharIX and '
            'collectTextBlock map to fo:color / fo:font-weight / '
            'librevenge:rotate',
      );
      expect(
        descendants(keyMgmt).any(
          (shape) =>
              !shape.fill.hasFill &&
              shape.line.hasLine &&
              shape.line.color == VsdxColor.white &&
              shape.line.weightInches > 0.04,
        ),
        isTrue,
        reason: 'shaft stroke="#fff" must stay a collectLine sibling, not '
            'collapse to fillcolor=none',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(keyMgmt.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        descendants(leftover)
            .where((shape) => (shape.text ?? '').trim().isNotEmpty)
            .map((shape) => shape.text)
            .join(),
        'KEYMGMT',
        reason: 'a second save must keep the SVG textPath glyphs',
      );
      expect(
        descendants(leftover).any(
          (shape) =>
              !shape.fill.hasFill &&
              shape.line.hasLine &&
              shape.line.color == VsdxColor.white &&
              shape.line.weightInches > 0.04,
        ),
        isTrue,
        reason: 'a second save must keep the SVG white stroke LineWeight',
      );
    },
  );

  test(
    'grapheditor General Note Cube and Callout stay native for LibreOffice',
    () {
      Stencil stencil(String groupName, String shapeName) => dynamic
          .singleWhere((group) => group.name == groupName)
          .stencils
          .singleWhere((entry) => entry.name == shapeName);

      final note =
          stencil('Draw.io JS / General / general', 'Note').build(140, 3, 3);
      expect(
        descendantGeometries(note)
            .expand((geometry) => geometry.commands)
            .whereType<LineTo>()
            .length,
        greaterThanOrEqualTo(8),
        reason: 'shape=note is a dog-eared page, not a four-line rectangle',
      );

      final cube =
          stencil('Draw.io JS / General / general', 'Cube').build(141, 3, 3);
      expect(
        descendantGeometries(cube).length,
        greaterThanOrEqualTo(3),
        reason: 'shape=cube paints isometric faces, not a single rectangle',
      );

      final callout =
          stencil('Draw.io JS / General / general', 'Callout').build(142, 3, 3);
      expect(
        callout.geometries
            .expand((geometry) => geometry.commands)
            .whereType<LineTo>()
            .length,
        greaterThanOrEqualTo(6),
        reason: 'shape=callout is a speech bubble, not a rectangle',
      );

      final doubleEllipse = stencil(
        'Draw.io JS / General / advanced',
        'Double Ellipse',
      ).build(143, 3, 3);
      expect(
        doubleEllipse.geometries
            .expand((geometry) => geometry.commands)
            .whereType<EllipseCmd>()
            .length,
        2,
        reason: 'ellipse;shape=doubleEllipse is two ovals',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final noteId = doc.pages.first.nextFreeShapeId();
      var page = doc.pages.first.addShape(
        stencil('Draw.io JS / General / general', 'Note').build(noteId, 3, 3),
      );
      final cubeId = page.nextFreeShapeId();
      page = page.addShape(
        stencil('Draw.io JS / General / general', 'Cube').build(cubeId, 5, 3),
      );
      final calloutId = page.nextFreeShapeId();
      page = page.addShape(
        stencil('Draw.io JS / General / general', 'Callout')
            .build(calloutId, 7, 3),
      );
      doc = doc.replacePage(0, page);
      final leftover = parser
          .parse(
              writer.write(originalBytes: writer.emptyDocument(), edited: doc))
          .pages
          .first;
      expect(
        descendantGeometries(leftover.findShapeById(noteId)!)
            .expand((geometry) => geometry.commands)
            .whereType<LineTo>()
            .length,
        greaterThanOrEqualTo(8),
      );
      expect(
        leftover.findShapeById(cubeId)!.geometries,
        isNotEmpty,
      );
      expect(
        leftover
            .findShapeById(calloutId)!
            .geometries
            .expand((geometry) => geometry.commands)
            .whereType<LineTo>()
            .length,
        greaterThanOrEqualTo(6),
      );
    },
  );

  test(
    'grapheditor classic UML palettes stay native for LibreOffice',
    () {
      Stencil stencil(String groupName, String shapeName) => dynamic
          .singleWhere((group) => group.name == groupName)
          .stencils
          .singleWhere((entry) => entry.name == shapeName);

      const group = 'Draw.io JS / UML / uml';
      expect(
        dynamic.singleWhere((entry) => entry.name == group).stencils,
        hasLength(65),
        reason: 'addUmlPalette templates must reach VisioDocument::parse',
      );

      final umlClass = stencil(group, 'Class').build(200, 3, 3);
      expect(
        umlClass.geometries
            .expand((geometry) => geometry.commands)
            .whereType<LineTo>()
            .length,
        greaterThanOrEqualTo(8),
        reason:
            'UML Class is a swimlane plus stacked compartments, not a rectangle',
      );
      expect(
        umlClass.children
            .map((child) => child.text)
            .whereType<String>()
            .where((text) => text.isNotEmpty)
            .toList(),
        ['Classname', '+ field: type', '+ method(type): type'],
        reason: 'Class stacks name, field and method',
      );

      final useCase = stencil(group, 'Use Case').build(201, 3, 3);
      expect(
        useCase.geometries
            .expand((geometry) => geometry.commands)
            .whereType<EllipseCmd>()
            .length,
        1,
        reason: 'ellipse;shape=useCase is one oval',
      );

      final lifeline = stencil(group, 'Lifeline').build(202, 3, 4);
      expect(
        descendantGeometries(lifeline).length,
        greaterThanOrEqualTo(2),
        reason: 'shape=umlLifeline paints a header box and the dashed axis '
            '(the axis is a sibling so collectLine can dash it)',
      );
      expect(
        descendantGeometries(lifeline)
            .expand((geometry) => geometry.commands)
            .whereType<LineTo>()
            .length,
        greaterThanOrEqualTo(5),
      );

      final actorLifeline = stencil(group, 'Actor Lifeline').build(203, 3, 4);
      expect(
        actorLifeline.geometries
            .expand((geometry) => geometry.commands)
            .whereType<EllipseCmd>()
            .length,
        1,
        reason: 'participant=umlActor must paint the stick-figure head',
      );

      final package = stencil(group, 'Package').build(204, 3, 3);
      expect(
        package.geometries
            .expand((geometry) => geometry.commands)
            .whereType<LineTo>()
            .length,
        greaterThanOrEqualTo(6),
        reason: 'shape=folder is a tabbed package, not a rectangle',
      );

      final actor = stencil(group, 'Actor').build(205, 3, 3);
      expect(
        actor.geometries
            .expand((geometry) => geometry.commands)
            .whereType<EllipseCmd>()
            .length,
        1,
        reason: 'shape=umlActor is a stick figure with a head',
      );
      expect(
        actor.geometries
            .expand((geometry) => geometry.commands)
            .whereType<LineTo>()
            .length,
        greaterThanOrEqualTo(4),
      );

      final item2 = stencil(group, 'Item 2').build(206, 3, 3);
      expect(
        descendantGeometries(item2).where((geometry) => !geometry.noFill),
        isNotEmpty,
        reason: 'mxLabel.paintImage must vectorise the gear, not a hollow rect',
      );
      expect(
        descendantGeometries(item2)
            .expand((geometry) => geometry.commands)
            .whereType<LineTo>()
            .length,
        greaterThanOrEqualTo(20),
        reason: 'Item 2 is a named-style label with a gear icon',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final classId = doc.pages.first.nextFreeShapeId();
      var page = doc.pages.first
          .addShape(stencil(group, 'Class').build(classId, 3, 3));
      final useCaseId = page.nextFreeShapeId();
      page = page.addShape(stencil(group, 'Use Case').build(useCaseId, 5, 3));
      final lifelineId = page.nextFreeShapeId();
      page = page.addShape(stencil(group, 'Lifeline').build(lifelineId, 7, 3));
      final packageId = page.nextFreeShapeId();
      page = page.addShape(stencil(group, 'Package').build(packageId, 9, 3));
      final item2Id = page.nextFreeShapeId();
      page = page.addShape(stencil(group, 'Item 2').build(item2Id, 11, 3));
      doc = doc.replacePage(0, page);
      final leftover = parser
          .parse(
              writer.write(originalBytes: writer.emptyDocument(), edited: doc))
          .pages
          .first;

      final leftoverClass = leftover.findShapeById(classId)!;
      expect(
        leftoverClass.geometries
            .expand((geometry) => geometry.commands)
            .whereType<LineTo>()
            .length,
        greaterThanOrEqualTo(8),
      );
      expect(
        leftoverClass.children
            .map((child) => child.text)
            .whereType<String>()
            .where((text) => text.isNotEmpty)
            .toList(),
        ['Classname', '+ field: type', '+ method(type): type'],
        reason: 'libvisio keeps compartment labels on child shapes',
      );
      expect(
        leftover
            .findShapeById(useCaseId)!
            .geometries
            .expand((geometry) => geometry.commands)
            .whereType<EllipseCmd>(),
        isNotEmpty,
      );
      expect(
        descendantGeometries(leftover.findShapeById(lifelineId)!)
            .expand((geometry) => geometry.commands)
            .whereType<LineTo>()
            .length,
        greaterThanOrEqualTo(5),
      );
      expect(
        leftover
            .findShapeById(packageId)!
            .geometries
            .expand((geometry) => geometry.commands)
            .whereType<LineTo>()
            .length,
        greaterThanOrEqualTo(6),
      );
      expect(
        descendantGeometries(leftover.findShapeById(item2Id)!)
            .expand((geometry) => geometry.commands)
            .whereType<LineTo>()
            .length,
        greaterThanOrEqualTo(20),
      );
    },
  );

  test(
    'grapheditor ER palettes keep Chen vertices and crow\'s-foot markers for LibreOffice',
    () {
      Stencil stencil(String groupName, String shapeName) => dynamic
          .singleWhere((group) => group.name == groupName)
          .stencils
          .singleWhere((entry) => entry.name == shapeName);

      const group = 'Draw.io JS / ER / entityRelation';
      expect(
        dynamic.singleWhere((entry) => entry.name == group).stencils,
        hasLength(50),
        reason: 'addErPalette templates must reach VisioDocument::parse',
      );

      final weak = stencil(group, 'Weak Entity').build(300, 3, 3);
      expect(
        weak.geometries,
        hasLength(2),
        reason: 'Chen weak entity is a double rectangle, not a single box',
      );
      expect(
        weak.geometries
            .expand((geometry) => geometry.commands)
            .whereType<LineTo>()
            .length,
        greaterThanOrEqualTo(8),
      );

      final identifying =
          stencil(group, 'Identifying Relationship').build(301, 3, 3);
      expect(
        identifying.geometries,
        hasLength(2),
        reason: 'Identifying relationship is a double diamond',
      );

      final multivalue =
          stencil(group, 'Multivalue Attribute').build(302, 3, 3);
      expect(
        multivalue.geometries
            .expand((geometry) => geometry.commands)
            .whereType<EllipseCmd>()
            .length,
        2,
        reason: 'Multivalue attribute is a double ellipse',
      );

      final oneToMany = stencil(group, '1 to Many').build(303, 4, 1);
      expect(
        oneToMany.geometries.where((geometry) => !geometry.noFill),
        isEmpty,
        reason: 'ERoneToMany is a stroked crow\'s foot, not a filled triangle',
      );
      expect(
        oneToMany.geometries
            .expand((geometry) => geometry.commands)
            .whereType<MoveTo>()
            .length,
        greaterThanOrEqualTo(3),
        reason: 'crow\'s foot plus the perpendicular bar need extra moves',
      );

      final many = stencil(group, 'Many').build(304, 4, 1);
      expect(
        many.geometries
            .expand((geometry) => geometry.commands)
            .whereType<LineTo>()
            .length,
        greaterThanOrEqualTo(3),
        reason: 'ERmany is the crow\'s foot, not a single connector',
      );

      final zeroToMany = stencil(group, '0 to Many Optional').build(305, 4, 1);
      expect(
        zeroToMany.geometries
            .expand((geometry) => geometry.commands)
            .whereType<EllipseCmd>(),
        isNotEmpty,
        reason: 'ERzeroToMany paints the optional participation circle',
      );

      final writer = VsdxWriter();
      final parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final weakId = doc.pages.first.nextFreeShapeId();
      var page = doc.pages.first
          .addShape(stencil(group, 'Weak Entity').build(weakId, 3, 3));
      final identifyingId = page.nextFreeShapeId();
      page = page.addShape(
        stencil(group, 'Identifying Relationship').build(identifyingId, 5, 3),
      );
      final multiId = page.nextFreeShapeId();
      page = page.addShape(
        stencil(group, 'Multivalue Attribute').build(multiId, 7, 3),
      );
      final oneToManyId = page.nextFreeShapeId();
      page =
          page.addShape(stencil(group, '1 to Many').build(oneToManyId, 9, 3));
      final zeroId = page.nextFreeShapeId();
      page = page.addShape(
        stencil(group, '0 to Many Optional').build(zeroId, 11, 3),
      );
      doc = doc.replacePage(0, page);
      final leftover = parser
          .parse(
              writer.write(originalBytes: writer.emptyDocument(), edited: doc))
          .pages
          .first;

      expect(
        leftover.findShapeById(weakId)!.geometries,
        hasLength(2),
      );
      expect(
        leftover.findShapeById(identifyingId)!.geometries,
        hasLength(2),
      );
      expect(
        leftover
            .findShapeById(multiId)!
            .geometries
            .expand((geometry) => geometry.commands)
            .whereType<EllipseCmd>()
            .length,
        2,
      );
      expect(
        leftover
            .findShapeById(oneToManyId)!
            .geometries
            .expand((geometry) => geometry.commands)
            .whereType<MoveTo>()
            .length,
        greaterThanOrEqualTo(3),
      );
      expect(
        leftover
            .findShapeById(zeroId)!
            .geometries
            .expand((geometry) => geometry.commands)
            .whereType<EllipseCmd>(),
        isNotEmpty,
      );
    },
  );

  test(
    'IBM VPC Floating IP SVG-in-PNG stays ForeignData for LibreOffice',
    () {
      Stencil stencil(String groupName, String shapeName) => dynamic
          .singleWhere((group) => group.name == groupName)
          .stencils
          .singleWhere((entry) => entry.name == shapeName);

      const group = 'Draw.io JS / IBM / IBM / VPC';
      final floating = stencil(group, 'Floating IP').build(400, 3, 3);
      expect(floating.hasImage, isTrue);
      expect(floating.imagePartName, startsWith('/visio/media/drawio_'));
      expect(
        drawioStencilImageForPart(floating.imagePartName!),
        isNotNull,
        reason: 'decoder must register PNG bytes for collectForeignData',
      );
      expect(
        floating.fill.hasFill,
        isFalse,
        reason: 'only the bitmap should show, not a filled frame',
      );

      final writer = VsdxWriter();
      final parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(stencil(group, 'Floating IP').build(id, 3, 3)),
      );
      final leftover = parser.parse(
        writer.write(originalBytes: writer.emptyDocument(), edited: doc),
      );
      final leftoverShape = leftover.pages.first.findShapeById(id)!;
      expect(leftoverShape.hasImage, isTrue);
      expect(
        leftover.images.findByPart(leftoverShape.imagePartName!),
        isNotNull,
        reason: 'a second save must keep the PNG media part',
      );
    },
  );

  test(
    'diagramly clipart PNGs stay ForeignData for LibreOffice',
    () {
      Stencil stencil(String groupName, String shapeName) => dynamic
          .singleWhere((group) => group.name == groupName)
          .stencils
          .singleWhere((entry) => entry.name == shapeName);

      final clipart = dynamic
          .where((group) => group.name.startsWith('Draw.io JS / Clipart / '))
          .toList(growable: false);
      expect(clipart, hasLength(6));
      expect(
        clipart.fold<int>(0, (sum, group) => sum + group.stencils.length),
        163,
      );
      expect(
        clipart.every(
          (group) =>
              group.stencils.every((entry) => entry.build(1, 3, 3).hasImage),
        ),
        isTrue,
        reason: 'every clipart icon is a bitmap libvisio can ForeignData',
      );

      const samples = <(String, String)>[
        ('Draw.io JS / Clipart / Clipart / Various', 'Gear'),
        ('Draw.io JS / Clipart / Clipart / Various', 'Globe'),
        ('Draw.io JS / Clipart / Clipart / Computer', 'Laptop'),
        ('Draw.io JS / Clipart / Clipart / People', 'Suit Man'),
        ('Draw.io JS / Clipart / Clipart / People', 'Nurse Man Green'),
        ('Draw.io JS / Clipart / Clipart / People', 'Soldier'),
      ];
      for (final sample in samples) {
        final shape = stencil(sample.$1, sample.$2).build(400, 3, 3);
        expect(shape.hasImage, isTrue, reason: sample.$2);
        expect(
          shape.imagePartName,
          matches(RegExp(r'^/visio/media/drawio_[0-9a-f]{16}\.png$')),
          reason: 'OPC media names must not use signed hex',
        );
        expect(
          drawioStencilImageForPart(shape.imagePartName!),
          isNotNull,
          reason: '${sample.$2} decoder must register PNG bytes',
        );
        expect(
          shape.fill.hasFill,
          isFalse,
          reason:
              '${sample.$2} should show only the bitmap, not a filled frame',
        );
      }

      final writer = VsdxWriter();
      final parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      var id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(
          stencil('Draw.io JS / Clipart / Clipart / Various', 'Gear')
              .build(id, 3, 3),
        ),
      );
      final leftover = parser.parse(
        writer.write(originalBytes: writer.emptyDocument(), edited: doc),
      );
      final leftoverShape = leftover.pages.first.findShapeById(id)!;
      expect(leftoverShape.hasImage, isTrue);
      expect(
        leftover.images.findByPart(leftoverShape.imagePartName!),
        isNotNull,
        reason: 'a second save must keep the clipart PNG media part',
      );
    },
  );

  test(
    'sidebar vertex values stay Text children for LibreOffice',
    () {
      Stencil stencil(String groupName, String shapeName) => dynamic
          .singleWhere((group) => group.name == groupName)
          .stencils
          .singleWhere((entry) => entry.name == shapeName);

      final instrument = stencil(
        'Draw.io JS / PID / Process Engineering / Instruments',
        'Discrete Instrument (control room)',
      ).build(410, 3, 3);
      expect(
        instrument.children.map((child) => child.text ?? '').join(),
        contains('TI'),
        reason: 'P&ID HTML table value must reach collectText',
      );
      expect(
        instrument.children.map((child) => child.text ?? '').join(),
        contains('##'),
      );

      final button = stencil(
        'Draw.io JS / Basic / basic',
        'Button',
      ).build(411, 3, 3);
      expect(
        button.children.any((child) => child.text == 'Button'),
        isTrue,
      );

      final cloud = stencil(
        'Draw.io JS / AWS4 / AWS / Groups',
        'AWS Cloud',
      ).build(412, 3, 3);
      expect(
        cloud.children.any((child) => child.text == 'AWS Cloud'),
        isTrue,
      );

      final writer = VsdxWriter();
      final parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(stencil(
          'Draw.io JS / PID / Process Engineering / Instruments',
          'Discrete Instrument (control room)',
        ).build(id, 3, 3)),
      );
      final leftover = parser.parse(
        writer.write(originalBytes: writer.emptyDocument(), edited: doc),
      );
      final leftoverShape = leftover.pages.first.findShapeById(id)!;
      expect(
        leftoverShape.children.map((child) => child.text ?? '').join(),
        contains('TI'),
        reason: 'a second save must keep the instrument letters',
      );
    },
  );

  test(
    'mxGraph labelPosition and verticalLabelPosition stay outside the cell for LibreOffice',
    () {
      Stencil stencil(String groupName, String shapeName) => dynamic
          .singleWhere((group) => group.name == groupName)
          .stencils
          .singleWhere((entry) => entry.name == shapeName);

      VsdxShape? labelOf(VsdxShape shape, String text) {
        for (final child in shape.children) {
          if (child.text == text) return child;
          final nested = labelOf(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      final port = stencil(
        'Draw.io JS / UML25 / uml 2.5',
        'Port',
      ).build(420, 3, 3);
      final portLabel = labelOf(port, 'port1');
      expect(portLabel, isNotNull);
      expect(
        portLabel!.pinX,
        greaterThan(port.width),
        reason: 'labelPosition=right must pin collectXFormData to the right '
            'of the 30px cell, not on top of the square',
      );
      expect(
        (portLabel.pinY - port.height / 2).abs(),
        lessThan(0.05),
        reason:
            'verticalLabelPosition=middle keeps the caption on the cell midline',
      );

      final vertex = dynamic
          .singleWhere(
            (group) =>
                group.name ==
                'Draw.io JS / GCP2 / GCP Icons / AI and Machine Learning',
          )
          .stencils
          .map((entry) => entry.build(421, 3, 3))
          .firstWhere(
            (shape) => labelOf(shape, 'Vertex AI') != null,
            orElse: () => throw StateError('Vertex AI icon missing'),
          );
      final vertexLabel = labelOf(vertex, 'Vertex AI')!;
      expect(
        vertexLabel.pinY,
        lessThan(0),
        reason: 'verticalLabelPosition=bottom must pin the caption below the '
            'icon that collectXFormData maps to svg:y',
      );

      final button = stencil(
        'Draw.io JS / Basic / basic',
        'Button',
      ).build(422, 3, 3);
      final buttonLabel = labelOf(button, 'Button')!;
      expect(
        buttonLabel.pinX,
        closeTo(button.width / 2, 0.05),
        reason: 'in-cell labels stay on the locPin',
      );
      expect(
        buttonLabel.pinY,
        closeTo(button.height / 2, 0.05),
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      VsdxShape leftoverOf(VsdxShape Function(int id) build) {
        var doc = parser.parse(writer.emptyDocument());
        final id = doc.pages.first.nextFreeShapeId();
        doc = doc.replacePage(0, doc.pages.first.addShape(build(id)));
        return parser
            .parse(
              writer.write(originalBytes: writer.emptyDocument(), edited: doc),
            )
            .pages
            .first
            .findShapeById(id)!;
      }

      final leftoverPort = leftoverOf(
        (id) => stencil('Draw.io JS / UML25 / uml 2.5', 'Port').build(id, 3, 3),
      );
      expect(
        labelOf(leftoverPort, 'port1')!.pinX,
        greaterThan(leftoverPort.width),
        reason: 'a second save must keep Port to the right of the cell',
      );

      final leftoverVertex = leftoverOf((id) {
        return dynamic
            .singleWhere(
              (group) =>
                  group.name ==
                  'Draw.io JS / GCP2 / GCP Icons / AI and Machine Learning',
            )
            .stencils
            .map((entry) => entry.build(id, 3, 3))
            .firstWhere((shape) => labelOf(shape, 'Vertex AI') != null);
      });
      expect(
        labelOf(leftoverVertex, 'Vertex AI')!.pinY,
        lessThan(0),
        reason: 'a second save must keep Vertex AI below the icon',
      );
    },
  );

  test(
    'mxShape getLabelBounds insets note2 and folder Text for LibreOffice',
    () {
      Stencil stencil(String groupName, String shapeName) => dynamic
          .singleWhere((group) => group.name == groupName)
          .stencils
          .singleWhere((entry) => entry.name == shapeName);

      VsdxShape? labelOf(VsdxShape shape, String text) {
        for (final child in shape.children) {
          if (child.text == text) return child;
          final nested = labelOf(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      final comment = stencil(
        'Draw.io JS / UML25 / uml 2.5',
        'Comment',
      ).build(430, 3, 3);
      final body = labelOf(comment, 'Comment1 body');
      expect(body, isNotNull,
          reason: 'note2 cell value must reach collectText');
      expect(
        body!.width,
        closeTo(comment.width, 0.02),
        reason: 'boundedLbl only insets the dog-ear, not the width',
      );
      expect(
        body.height / comment.height,
        closeTo(10 / 60, 0.05),
        reason: 'NoteShape2.getLabelMargins size=25 is top and bottom on a '
            '60px cell, the TxtHeight collectTextBlock maps below the fold',
      );
      expect(
        body.pinY / comment.height,
        closeTo(0.5, 0.05),
        reason: 'the remaining 10px band is still centred on the locPin',
      );

      final packageShape = stencil(
        'Draw.io JS / UML25 / uml 2.5',
        'Package',
      ).build(431, 3, 3);
      final pkg = labelOf(packageShape, 'Package1');
      expect(pkg, isNotNull);
      expect(
        pkg!.height / packageShape.height,
        closeTo(50 / 80, 0.05),
        reason: 'folder tabHeight=30 is the top margin getLabelMargins returns',
      );
      expect(
        pkg.pinY / packageShape.height,
        closeTo(25 / 80, 0.05),
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(
          stencil('Draw.io JS / UML25 / uml 2.5', 'Comment').build(id, 3, 3),
        ),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      final leftoverBody = labelOf(leftover, 'Comment1 body')!;
      expect(
        leftoverBody.height / leftover.height,
        closeTo(10 / 60, 0.05),
        reason: 'a second save must keep the inset TxtHeight',
      );
      expect(
        leftoverBody.pinY / leftover.height,
        closeTo(0.5, 0.05),
      );
    },
  );
}
