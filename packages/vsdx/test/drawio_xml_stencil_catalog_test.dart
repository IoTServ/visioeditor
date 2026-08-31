import 'dart:math' as math;

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
    final shapes = reopened.pages.first.shapes
        .where((shape) => !isLibvisioBakePlate(shape))
        .toList(growable: false);
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
    final shapes = reopened.pages.first.shapes
        .where((shape) => !isLibvisioBakePlate(shape))
        .toList(growable: false);
    expect(shapes, hasLength(samples.length));
    expect(
      shapes.every((shape) => shape.geometries.isNotEmpty),
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
    expect(
      descendantGeometries(bar).length,
      greaterThan(1),
      reason: 'vertex-cells mockups must paint built-in rectangles; '
          'fillColor2 defaults bake as sibling FillForegnd',
    );
    expect(bar.children, isNotEmpty);

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
    bool isCrease(VsdxPathCommand cmd) =>
        cmd is LineTo &&
        (cmd.x - x).abs() < 0.03 &&
        (cmd.y - y).abs() < 0.03;
    expect(
      descendantGeometries(truck).expand((g) => g.commands).any(isCrease),
      isTrue,
      reason: 'LibreOffice only sees Geometry; the cab crease is a '
          'foreground move/line outside <path>. Extra inherit fillstroke '
          'is a sibling so collectGeometry evenodd does not punch the cab',
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
      descendantGeometries(leftover).expand((g) => g.commands).any(isCrease),
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

  test('mxStencil shape strokewidth stays LineWeight for LibreOffice', () {
    // Networks Comm Link is w=30 h=100 strokewidth="2" with no child
    // <strokewidth>. mxStencil.drawShape does 2 * minScale; catalog
    // scale is 1.5 / 100 → LineWeight 0.03. Leaving _strokeWidth unset
    // used Visio 0.01 and applyStencilStyle pinned 0.012.
    const expected = 2 * (1.5 / 100);
    final link = migrated
        .singleWhere((group) => group.name == 'Draw.io / Networks')
        .stencils
        .singleWhere((entry) => entry.name == 'Comm Link')
        .build(83, 3, 3);
    expect(
      link.line.hasLine,
      isTrue,
      reason: 'inherit fillstroke stays on the parent',
    );
    expect(
      link.line.weightInches,
      closeTo(expected, 1e-6),
      reason: 'shape strokewidth="2" must reach collectLine LineWeight',
    );

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        migrated
            .singleWhere((group) => group.name == 'Draw.io / Networks')
            .stencils
            .singleWhere((entry) => entry.name == 'Comm Link')
            .build(id, 3, 3),
      ),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(
      leftover.line.weightInches,
      closeTo(expected, 1e-6),
      reason: 'a second save must keep LineWeight 0.03',
    );
  });

  test('mxStencil omitted strokewidth defaults to 1 for LibreOffice', () {
    double maxStrokedWeight(VsdxShape shape) {
      var weight = shape.line.hasLine ? shape.line.weightInches : 0.0;
      for (final child in shape.children) {
        final childWeight = maxStrokedWeight(child);
        if (childWeight > weight) weight = childWeight;
      }
      return weight;
    }

    // Radio Button Off omits shape @strokewidth (w=h=12) and has no
    // child <strokewidth>. Official parseDescription defaults to "1";
    // drawShape does 1 * minScale. Catalog scale is 1.5 / 12.
    const expected = 1.5 / 12;
    final radio = migrated
        .singleWhere(
          (group) => group.name == 'Draw.io / Mockup / Form Elements',
        )
        .stencils
        .singleWhere((entry) => entry.name == 'Radio Button Off')
        .build(84, 3, 3);
    expect(
      maxStrokedWeight(radio),
      closeTo(expected, 1e-6),
      reason: 'omitted strokewidth must freeze 1×minScale; leaving it '
          'unset used Visio 0.01 and applyStencilStyle pinned 0.012',
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
            .singleWhere((entry) => entry.name == 'Radio Button Off')
            .build(id, 3, 3),
      ),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(
      maxStrokedWeight(leftover),
      closeTo(expected, 1e-6),
      reason: 'a second save must keep LineWeight; it is a token',
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
      [disabled, ...disabled.children].any(
        (shape) =>
            shape.fill.hasFill &&
            shape.fill.foreground == VsdxColor.black &&
            (shape.fill.foregroundTransparency - 0.88).abs() < 0.02,
      ),
      isTrue,
      reason: 'GMDL opacity=12 must become FillForegndTrans 0.88',
    );
  });

  test('mxStencil inherit-fill alpha stays FillForegndTrans for LibreOffice',
      () {
    bool hasSoftEdges(VsdxShape shape) {
      if (isLibvisioSoftEdgesPlate(shape)) return true;
      return shape.children.any(hasSoftEdges);
    }

    final hubShadow = migrated
        .singleWhere((group) => group.name == 'Draw.io / Networks2')
        .stencils
        .singleWhere((entry) => entry.name == 'hub shadow')
        .build(88, 3, 3);
    expect(
      hubShadow.fill.hasFill &&
          (hubShadow.fill.foregroundTransparency - 0.75).abs() < 0.02,
      isTrue,
      reason: 'mxStencil <alpha alpha="0.25"/> then inherit fill; '
          'restore pops overallAlpha, so parent FillForegndTrans must '
          'be captured at _finish. collectFillAndShadow maps it to '
          'draw:opacity 25%',
    );

    final antenna = migrated
        .singleWhere((group) => group.name == 'Draw.io / Networks2')
        .stencils
        .singleWhere((entry) => entry.name == 'antenna shadow')
        .build(89, 3, 3);
    expect(
      antenna.fill.hasFill &&
          (antenna.fill.foregroundTransparency - 0.75).abs() < 0.02,
      isTrue,
      reason: 'every Networks2 * shadow uses the same 0.25 silhouette',
    );

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(hubShadow.copyWith(id: id)),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(
      leftover.fill.hasFill && leftover.fill.foregroundTransparency > 0.7,
      isTrue,
      reason: 'a second save must keep FillForegndTrans; it is a token',
    );
    expect(
      hasSoftEdges(leftover),
      isFalse,
      reason: 'solid inherit fill + FillForegndTrans must not bake a '
          'SoftEdges PNG',
    );
  });

  test(
    'mxStencil inherit-stroke alpha stays LineColorTrans for LibreOffice',
    () {
      bool hasSoftEdges(VsdxShape shape) {
        if (isLibvisioSoftEdgesPlate(shape)) return true;
        return shape.children.any(hasSoftEdges);
      }

      bool hasStrokeRibbon(VsdxShape shape) {
        if (isLibvisioStrokeRibbonPlate(shape)) return true;
        return shape.children.any(hasStrokeRibbon);
      }

      final cortana = migrated
          .singleWhere(
            (group) =>
                group.name ==
                'Draw.io / Microsoft Cloud and Enterprise / Other',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Cortana')
          .build(90, 3, 3);
      expect(
        cortana.fill.hasFill &&
            (cortana.fill.foregroundTransparency - 0.6).abs() < 0.02,
        isTrue,
        reason: 'save / alpha 0.4 / inherit fillstroke / restore; fill '
            'Trans is already captured on the parent',
      );
      expect(
        cortana.line.hasLine &&
            (cortana.line.transparency - 0.6).abs() < 0.02,
        isTrue,
        reason: 'the same fillstroke must capture LineColorTrans at '
            '_finish; restore pops overallAlpha before parent Line is '
            'built. leftover bakes a FillForegndTrans ribbon because '
            'xmlStringToColour zeros Colour.a',
      );

      final vnic = migrated
          .singleWhere((group) => group.name == 'Draw.io / Veeam / 2d')
          .stencils
          .singleWhere((entry) => entry.name == 'vNIC')
          .build(91, 3, 3);
      expect(
        vnic.line.hasLine && (vnic.line.transparency - 0.5).abs() < 0.02,
        isTrue,
        reason: 'vNIC inherit fillstroke under alpha 0.5',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(cortana.copyWith(id: id)),
      );
      final leftoverDoc = parser.parse(
        writer.write(originalBytes: writer.emptyDocument(), edited: doc),
      );
      final leftover = leftoverDoc.pages.first.findShapeById(id)!;
      expect(
        leftover.fill.hasFill && leftover.fill.foregroundTransparency > 0.5,
        isTrue,
        reason: 'a second save must keep FillForegndTrans on the body',
      );
      expect(
        leftover.line.transparency > 0.5 ||
            leftoverDoc.pages.first.shapes.any(hasStrokeRibbon),
        isTrue,
        reason: 'LineColorTrans is not a token; leftover bakes a page-'
            'level FillForegndTrans stroke ribbon',
      );
      expect(
        hasSoftEdges(leftover),
        isFalse,
        reason: 'solid fillstroke + Trans must not bake a SoftEdges PNG',
      );
    },
  );

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

  test('mxStencil default dashPattern is 3 3 for LibreOffice', () {
    bool hasFixedDefaultDash(VsdxShape shape, double expected) {
      final custom = shape.line.customDashPattern;
      if (shape.line.hasLine &&
          shape.line.fixedDash &&
          custom != null &&
          custom.length >= 2 &&
          (custom.first - expected).abs() < 0.05) {
        return true;
      }
      return shape.children
          .any((child) => hasFixedDefaultDash(child, expected));
    }

    bool hasBakedDashGaps(VsdxShape shape) {
      if (shape.line.hasLine) {
        final moves = shape.geometries
            .expand((geometry) => geometry.commands)
            .whereType<MoveTo>()
            .length;
        if (moves >= 2) return true;
      }
      return shape.children.any(hasBakedDashGaps);
    }

    // AWS 3D Dashed Edge: dashed=1, no dashpattern. Catalog scale is
    // 1.5/31.6; createState '3 3' → 3 * minScale / (1/96) CSS-px.
    const expected = 3 * (1.5 / 31.6) * 96;
    final edge = dynamic
        .singleWhere((group) => group.name == 'Draw.io JS / AWS3D / AWS 3D')
        .stencils
        .singleWhere((entry) => entry.name == 'Dashed Edge')
        .build(88, 3, 3);
    expect(
      hasFixedDefaultDash(edge, expected),
      isTrue,
      reason: 'dashed without dashpattern must use mx 3 3 as veDashPattern, '
          'not Visio LinePattern 2 (6× LineWeight)',
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
              (group) => group.name == 'Draw.io JS / AWS3D / AWS 3D',
            )
            .stencils
            .singleWhere((entry) => entry.name == 'Dashed Edge')
            .build(id, 3, 3),
      ),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(
      hasBakedDashGaps(leftover),
      isTrue,
      reason: 'a second save bakes veFixedDash 3 3 into MoveTo gaps',
    );
  });

  test(
    'mxStencil dashpattern none stays solid for LibreOffice',
    () {
      Iterable<VsdxShape> descendants(VsdxShape shape) sync* {
        yield shape;
        for (final child in shape.children) {
          yield* descendants(child);
        }
      }

      final pack = migrated
          .singleWhere((group) => group.name == 'Draw.io / AWS 4')
          .stencils
          .singleWhere((entry) => entry.name == 'work package')
          .build(89, 3, 3);
      final dashed = descendants(pack).where(
        (shape) =>
            shape.line.hasLine &&
            ((shape.line.customDashPattern != null &&
                    shape.line.customDashPattern!.length >= 2) ||
                shape.line.pattern == 2),
      );
      expect(
        dashed,
        isEmpty,
        reason: 'dashpattern none is Number(none)=NaN in mxStencil.drawNode; '
            'createDashPattern would set stroke-dasharray NaN (SVG solid), '
            'not createState 3 3',
      );
      expect(
        descendants(pack).any((shape) => shape.line.hasLine),
        isTrue,
        reason: 'the work-package outline and arrow still stroke',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(
          migrated
              .singleWhere((group) => group.name == 'Draw.io / AWS 4')
              .stencils
              .singleWhere((entry) => entry.name == 'work package')
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
        descendants(leftover).where((shape) {
          final custom = shape.line.customDashPattern;
          if (custom != null && custom.length >= 2) return true;
          if (!shape.line.hasLine) return false;
          return shape.geometries
                  .expand((geometry) => geometry.commands)
                  .whereType<MoveTo>()
                  .length >=
              2;
        }),
        isEmpty,
        reason: 'a second save must not bake 3 3 MoveTo gaps on a solid none',
      );
    },
  );

  test(
    'mxStencil dashpattern dash alias stays veDashPattern for LibreOffice',
    () {
      Iterable<VsdxShape> descendants(VsdxShape shape) sync* {
        yield shape;
        for (final child in shape.children) {
          yield* descendants(child);
        }
      }

      List<double>? firstCustomDash(VsdxShape shape) {
        for (final node in descendants(shape)) {
          final custom = node.line.customDashPattern;
          if (node.line.hasLine &&
              node.line.fixedDash &&
              custom != null &&
              custom.length >= 2) {
            return custom;
          }
        }
        return null;
      }

      bool hasBakedDashGaps(VsdxShape shape) {
        for (final node in descendants(shape)) {
          if (!node.line.hasLine) continue;
          final moves = node.geometries
              .expand((geometry) => geometry.commands)
              .whereType<MoveTo>()
              .length;
          if (moves >= 2) return true;
        }
        return false;
      }

      final guard = migrated
          .singleWhere((group) => group.name == 'Draw.io / Cisco / Security')
          .stencils
          .singleWhere((entry) => entry.name == 'Guard')
          .build(90, 3, 3);
      final guardDash = firstCustomDash(guard);
      expect(guardDash, isNotNull);
      final guardScale = 1.5 / 55.33;
      final expected8 = 8 * guardScale / drawioDashUnitInches;
      expect(
        guardDash!.first,
        closeTo(expected8, 0.05),
        reason: 'Cisco Guard dashpattern dash="8 8" (no pattern=) must not '
            'fall through to createState 3 3; leftover MoveTo gaps follow '
            'the authored 8 8 that collectLine cannot emit as 0xfe',
      );
      expect(guardDash[1], closeTo(expected8, 0.05));

      final isdn = migrated
          .singleWhere((group) => group.name == 'Draw.io / Cisco / Switches')
          .stencils
          .singleWhere((entry) => entry.name == 'ISDN Switch')
          .build(91, 3, 3);
      final isdnDash = firstCustomDash(isdn);
      expect(isdnDash, isNotNull);
      final isdnScale = 1.5 / 37;
      expect(
        isdnDash!.first,
        closeTo(12 * isdnScale / drawioDashUnitInches, 0.05),
        reason: 'ISDN Switch dash="12 4" is the authored on/off pair',
      );
      expect(
        isdnDash[1],
        closeTo(4 * isdnScale / drawioDashUnitInches, 0.05),
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
                (group) => group.name == 'Draw.io / Cisco / Security',
              )
              .stencils
              .singleWhere((entry) => entry.name == 'Guard')
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
        hasBakedDashGaps(leftover),
        isTrue,
        reason: 'a second save bakes dash="8 8" into MoveTo gaps because '
            'libvisio treats custom LinePattern 0xfe as solid',
      );
    },
  );

  test(
    'mxStencil save/restore keeps post-restore strokes solid for LibreOffice',
    () {
      bool isDashedStroke(VsdxShape shape) {
        if (shape.fill.hasFill || !shape.line.hasLine) return false;
        final custom = shape.line.customDashPattern;
        return (custom != null && custom.length >= 2) ||
            shape.line.pattern == 2;
      }

      final bar = migrated
          .singleWhere(
            (group) => group.name == 'Draw.io / Android / Android',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Contextual Action Bar')
          .build(41, 3, 3);
      expect(
        bar.children.where(isDashedStroke).length,
        3,
        reason: 'dashpattern 1 1 before restore is the check, divider and '
            '18×18 box; collectLine LinePattern 0xfe needs those siblings',
      );
      expect(
        bar.children.where((child) {
          if (child.fill.hasFill || !child.line.hasLine) return false;
          if (isDashedStroke(child)) return false;
          return child.line.color == VsdxColor.white;
        }).length,
        greaterThanOrEqualTo(3),
        reason: 'restore pops dashed=1; fillColor2 default #ffffff then '
            'bakes speaker / 15×10 / hamburger as solid LineColor siblings',
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
        leftover.children.any((child) {
          if (child.fill.hasFill || !child.line.hasLine) return false;
          final moves = child.geometries
              .expand((geometry) => geometry.commands)
              .whereType<MoveTo>()
              .length;
          return moves >= 2;
        }),
        isTrue,
        reason: 'a second save still bakes the pre-restore dash into MoveTo '
            'gaps because libvisio treats custom LinePattern 0xfe as solid',
      );
      expect(
        leftover.children.any((child) {
          if (child.fill.hasFill || !child.line.hasLine) return false;
          return child.line.pattern == 1 &&
              (child.line.customDashPattern == null ||
                  child.line.customDashPattern!.isEmpty) &&
              child.line.color == VsdxColor.white;
        }),
        isTrue,
        reason: 'post-restore fillColor2 icons stay native solid LinePattern 1',
      );

      final keyboard = migrated
          .singleWhere(
            (group) => group.name == 'Draw.io / Android / Android',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Keyboard')
          .build(42, 3, 3);
      expect(
        keyboard.children.map((child) => child.text).contains('Q'),
        isTrue,
        reason: 'restore must not drop the QWERTY collectCharIX labels',
      );
    },
  );

  test(
    'mxStencil style-key default colors stay FillForegnd for LibreOffice',
    () {
      const paletteBlue = VsdxColor(0xFFDAE8FC);
      const keyGrey = VsdxColor(0xFF333333);
      const keySilver = VsdxColor(0xFF999999);

      bool hasFill(VsdxShape shape, VsdxColor color) {
        if (shape.fill.hasFill && shape.fill.foreground == color) {
          return true;
        }
        return shape.children.any((child) => hasFill(child, color));
      }

      VsdxColor? glyphColor(VsdxShape shape, String text) {
        for (final child in shape.children) {
          if (child.text == text && child.richText.runs.isNotEmpty) {
            return child.richText.runs.first.charStyle.color;
          }
          final nested = glyphColor(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      final keyboard = migrated
          .singleWhere(
            (group) => group.name == 'Draw.io / Android / Android',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Keyboard')
          .build(43, 3, 3);
      expect(
        hasFill(keyboard, VsdxColor.black),
        isTrue,
        reason: 'fillColor2 default #000000 is the chassis; mxStencil.'
            'getColorValue uses default when the cell has no fillColor2',
      );
      expect(
        hasFill(keyboard, keyGrey),
        isTrue,
        reason: 'fillColor3 default #333333 is the modifier keys',
      );
      expect(
        hasFill(keyboard, keySilver),
        isTrue,
        reason: 'fillColor5 default #999999 is the letter keys',
      );
      expect(
        hasFill(keyboard, paletteBlue),
        isFalse,
        reason: 'applyStencilStyle must not wash authored fillColor2 hex '
            'to the Android palette #DAE8FC',
      );
      expect(
        glyphColor(keyboard, 'Q'),
        VsdxColor.white,
        reason: 'fontcolor fillColor4 default #ffffff is collectCharIX Color',
      );

      final bar = migrated
          .singleWhere(
            (group) => group.name == 'Draw.io / Android / Android',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Contextual Action Bar')
          .build(44, 3, 3);
      expect(
        hasFill(bar, VsdxColor.white),
        isTrue,
        reason: 'fillColor2 default #ffffff is the 6×6 icon squares',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(keyboard.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        hasFill(leftover, VsdxColor.black) &&
            hasFill(leftover, keyGrey) &&
            hasFill(leftover, keySilver),
        isTrue,
        reason: 'a second save must keep fillColor2/3/5 as FillForegnd',
      );
      bool hasSoftEdges(VsdxShape shape) {
        if (isLibvisioSoftEdgesPlate(shape)) return true;
        return shape.children.any(hasSoftEdges);
      }

      expect(
        hasSoftEdges(leftover),
        isFalse,
        reason: 'solid fillColor2 hex must not bake a SoftEdges PNG',
      );
      expect(
        glyphColor(leftover, 'Q'),
        VsdxColor.white,
        reason: 'a second save must keep QWERTY fo:color white',
      );
    },
  );

  test(
    'mxStencil NestedStencil default colors stay FillForegnd for LibreOffice',
    () {
      const paletteBlue = VsdxColor(0xFFDAE8FC);
      const keyGrey = VsdxColor(0xFF333333);
      const keySilver = VsdxColor(0xFF999999);

      bool hasFill(VsdxShape shape, VsdxColor color) {
        if (shape.fill.hasFill && shape.fill.foreground == color) {
          return true;
        }
        return shape.children.any((child) => hasFill(child, color));
      }

      VsdxColor? glyphColor(VsdxShape shape, String text) {
        for (final child in shape.children) {
          if (child.text == text && child.richText.runs.isNotEmpty) {
            return child.richText.runs.first.charStyle.color;
          }
          final nested = glyphColor(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      final keyboard = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / Android / android',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Keyboard')
          .build(45, 3, 3);
      expect(
        hasFill(keyboard, VsdxColor.black) &&
            hasFill(keyboard, keyGrey) &&
            hasFill(keyboard, keySilver),
        isTrue,
        reason: 'sidebar Android Keyboard is NestedStencil.drawShape; '
            'mxStencil.getColorValue uses default when the cell has no '
            'fillColor2, so capture must bake #000/#333/#999',
      );
      expect(
        hasFill(keyboard, paletteBlue),
        isFalse,
        reason: 'fillColor2 default #ffffff must forceHex so it does not '
            'collapse to the cell fill token and wash #DAE8FC',
      );
      expect(
        glyphColor(keyboard, 'Q'),
        VsdxColor.white,
        reason: 'fontcolor fillColor4 default #ffffff is collectCharIX Color',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(keyboard.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        hasFill(leftover, VsdxColor.black) &&
            hasFill(leftover, keyGrey) &&
            hasFill(leftover, keySilver),
        isTrue,
        reason: 'a second save must keep NestedStencil fillColor2 hex',
      );
      expect(
        glyphColor(leftover, 'Q'),
        VsdxColor.white,
        reason: 'a second save must keep sidebar QWERTY fo:color white',
      );
    },
  );

  test(
    'mxStencil library style-key defaults stay FillForegnd for LibreOffice',
    () {
      const ledGrey = VsdxColor(0xFF9DA6A8);

      bool hasFill(VsdxShape shape, VsdxColor color) {
        if (shape.fill.hasFill && shape.fill.foreground == color) {
          return true;
        }
        return shape.children.any((child) => hasFill(child, color));
      }

      bool hasSoftEdges(VsdxShape shape) {
        if (isLibvisioSoftEdgesPlate(shape)) return true;
        return shape.children.any(hasSoftEdges);
      }

      VsdxShape buildNamed(String name) => migrated
          .singleWhere((group) => group.name == 'Draw.io / Networks2')
          .stencils
          .singleWhere((entry) => entry.name == name)
          .build(46, 3, 3);

      final hub = buildNamed('hub');
      expect(
        hasFill(hub, ledGrey),
        isTrue,
        reason: 'hub LED is fillcolor color="neutralFill" with no node '
            'default; mxStencil.getColorValue uses the cell key, and '
            'Sidebar-Network2.js sn / global server default=#9DA6A8',
      );
      expect(
        hub.fill.foreground,
        isNot(ledGrey),
        reason: 'the chassis stays inherit fill for applyStencilStyle; '
            'only the LED sibling bakes #9DA6A8',
      );

      final server = buildNamed('server');
      expect(
        hasFill(server, ledGrey),
        isTrue,
        reason: 'server LED also omits default on neutralFill',
      );

      final global = buildNamed('global server');
      expect(
        hasFill(global, ledGrey),
        isTrue,
        reason: 'global server already has default="#9DA6A8" on the node',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(hub.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        hasFill(leftover, ledGrey),
        isTrue,
        reason: 'a second save must keep neutralFill as FillForegnd',
      );
      expect(
        hasSoftEdges(leftover),
        isFalse,
        reason: 'solid neutralFill hex must not bake a SoftEdges PNG',
      );
    },
  );

  test(
    'mxGraph CSS named colors stay FillForegnd for LibreOffice',
    () {
      const cssGray = VsdxColor(0xFF808080);
      const cssSilver = VsdxColor(0xFFC0C0C0);
      const cssWhite = VsdxColor.white;
      const wash = VsdxColor(0xFFEAECEE);

      bool hasFill(VsdxShape shape, VsdxColor color) {
        if (shape.fill.hasFill && shape.fill.foreground == color) {
          return true;
        }
        return shape.children.any((child) => hasFill(child, color));
      }

      bool hasSoftEdges(VsdxShape shape) {
        if (isLibvisioSoftEdgesPlate(shape)) return true;
        return shape.children.any(hasSoftEdges);
      }

      bool hasNamedGradient(VsdxShape shape) {
        final fill = shape.fill;
        if (fill.pattern == 32 &&
            fill.foreground == wash &&
            fill.background == cssWhite) {
          return true;
        }
        return shape.children.any(hasNamedGradient);
      }

      final gateways = dynamic
          .singleWhere(
            (group) =>
                group.name == 'Draw.io JS / Azure2 / Azure / Networking',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Application Gateway Containers')
          .build(46, 3, 3);
      expect(
        hasFill(gateways, cssGray),
        isTrue,
        reason: 'SVG fill="gray" is a canvas named colour; mxUtils.'
            'color2hex / parseColor keep it, so FillForegnd must be '
            '#808080 not inherit that applyStencilStyle washes',
      );
      expect(
        hasFill(gateways, cssSilver),
        isTrue,
        reason: 'SVG fill="silver" is CSS #C0C0C0; collectFillAndShadow '
            'maps sibling FillForegnd to draw:fill-color',
      );

      final sap = dynamic
          .singleWhere(
            (group) =>
                group.name == 'Draw.io JS / SAP / SAP / Build Workzone',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Unnamed Shape (7)')
          .build(47, 3, 3);
      expect(
        hasNamedGradient(sap),
        isTrue,
        reason: 'fillgradient color1=white is CSS white; southeast '
            'FillPattern 32 is FillBkgnd white / FillForegnd #EAECEE',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(gateways.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        hasFill(leftover, cssGray) && hasFill(leftover, cssSilver),
        isTrue,
        reason: 'a second save must keep CSS gray/silver FillForegnd',
      );
      expect(
        hasSoftEdges(leftover),
        isFalse,
        reason: 'solid named-colour fills must not bake a SoftEdges PNG',
      );

      var sapDoc = parser.parse(writer.emptyDocument());
      final sapId = sapDoc.pages.first.nextFreeShapeId();
      sapDoc = sapDoc.replacePage(
        0,
        sapDoc.pages.first.addShape(sap.copyWith(id: sapId)),
      );
      final sapLeftover = parser
          .parse(
            writer.write(
              originalBytes: writer.emptyDocument(),
              edited: sapDoc,
            ),
          )
          .pages
          .first
          .findShapeById(sapId)!;
      expect(
        hasNamedGradient(sapLeftover),
        isTrue,
        reason: 'a second save must keep color1=white as FillBkgnd',
      );
    },
  );

  test(
    'mxGraph glued fontColor hex stays Char.Color for LibreOffice',
    () {
      const labelGrey = VsdxColor(0xFF4D4D4D);

      VsdxColor? glyphColor(VsdxShape shape, String text) {
        for (final child in shape.children) {
          if (child.text == text && child.richText.runs.isNotEmpty) {
            return child.richText.runs.first.charStyle.color;
          }
          final nested = glyphColor(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      final stepper = dynamic
          .singleWhere(
            (group) =>
                group.name == 'Draw.io JS / Gmdl / GMDL / Steppers',
          )
          .stencils
          .singleWhere(
            (entry) => entry.name == 'Stepper with alternative label placing',
          )
          .build(48, 3, 3);
      expect(
        glyphColor(stepper, 'Ad unit details'),
        labelGrey,
        reason: 'GMDL addDataEntry writes fontColor=#4d4d4dlfontSize=13 '
            '(missing ;). mxUtils.isValidColor rejects it; the decoder '
            'must keep the #4d4d4d prefix so collectCharIX maps fo:color',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(stepper.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        glyphColor(leftover, 'Ad unit details'),
        labelGrey,
        reason: 'a second save must keep Char.Color #4d4d4d',
      );
    },
  );

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

  test('mxStencil default linecap is flat for LibreOffice', () {
    bool strokedCap(VsdxShape shape, LineCap cap) {
      if (shape.line.hasLine && shape.line.cap == cap) return true;
      return shape.children.any((child) => strokedCap(child, cap));
    }

    final bar = migrated
        .singleWhere(
          (group) => group.name == 'Draw.io / Android / Android',
        )
        .stencils
        .singleWhere((entry) => entry.name == 'Progress Bar')
        .build(90, 3, 3);
    expect(
      strokedCap(bar, LineCap.extended),
      isTrue,
      reason: 'Android Progress Bar has no <linecap>. '
          'mxAbstractCanvas2D.createState lineCap is flat; libvisio '
          '_lineProperties LineCap 1 maps to svg:stroke-linecap=butt',
    );
    expect(
      strokedCap(bar, LineCap.round),
      isFalse,
      reason: 'Visio factory LineCap 0 would make Draw round the open '
          'rail ends',
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
              (group) => group.name == 'Draw.io / Android / Android',
            )
            .stencils
            .singleWhere((entry) => entry.name == 'Progress Bar')
            .build(id, 3, 3),
      ),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(
      strokedCap(leftover, LineCap.extended),
      isTrue,
      reason: 'a second save must keep LineCap 1',
    );
    expect(
      strokedCap(leftover, LineCap.round),
      isFalse,
      reason: 'leftover must not fall back to Visio round caps',
    );
  });

  test('mxStencil inherit linecap does not leak later siblings', () {
    final detector = migrated
        .singleWhere((group) => group.name == 'Draw.io / Cisco / Misc')
        .stencils
        .singleWhere((entry) => entry.name == 'Detector')
        .build(91, 3, 3);
    expect(
      detector.line.hasLine,
      isTrue,
      reason: 'first fillstroke is inherit and stays on the parent',
    );
    expect(
      detector.line.cap,
      LineCap.extended,
      reason: 'mx default flat must stay on collectLine; later '
          'linecap=butt/round belongs on hex siblings',
    );
    expect(
      detector.line.join,
      VsdxLineJoin.round,
      reason: 'linejoin=round is set before the inherit fillstroke',
    );
    expect(
      detector.children.any(
        (child) => child.line.hasLine && child.line.cap == LineCap.extended,
      ),
      isTrue,
      reason: 'later linecap=butt hex fillstroke is a sibling',
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
            .singleWhere((entry) => entry.name == 'Detector')
            .build(id, 3, 3),
      ),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(
      leftover.line.cap,
      LineCap.extended,
      reason: 'a second save must keep parent LineCap 1',
    );
  });

  test('mxStencil default linejoin is miter for LibreOffice', () {
    bool hasRoundCapMiter(VsdxShape shape) {
      if (shape.line.hasLine &&
          shape.line.cap == LineCap.round &&
          shape.line.join == VsdxLineJoin.miter) {
        return true;
      }
      return shape.children.any(hasRoundCapMiter);
    }

    bool hasMiterJoin(VsdxShape shape) {
      if (shape.line.hasLine && shape.line.join == VsdxLineJoin.miter) {
        return true;
      }
      return shape.children.any(hasMiterJoin);
    }

    final mail = migrated
        .singleWhere(
          (group) => group.name == 'Draw.io / Google Material Design',
        )
        .stencils
        .singleWhere((entry) => entry.name == 'mail')
        .build(92, 3, 3);
    expect(
      hasRoundCapMiter(mail),
      isTrue,
      reason: 'GMDL mail flap is linecap=round with no linejoin. '
          'mxAbstractCanvas2D.createState lineJoin is miter; libvisio '
          '_lineProperties maps join from LineCap, so leftover flattens '
          'the round cap to LineCap 1 for Draw to miter the V',
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
              (group) => group.name == 'Draw.io / Google Material Design',
            )
            .stencils
            .singleWhere((entry) => entry.name == 'mail')
            .build(id, 3, 3),
      ),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(
      hasMiterJoin(leftover),
      isTrue,
      reason: 'a second save must keep veLineJoin miter (Draw reads join '
          'from flattened LineCap 1)',
    );
  });

  test('mxStencil linejoin flat and square stay miter for LibreOffice', () {
    Iterable<VsdxShape> descendants(VsdxShape shape) sync* {
      yield shape;
      for (final child in shape.children) {
        yield* descendants(child);
      }
    }

    bool hasStrokedJoin(VsdxShape shape, VsdxLineJoin? join) =>
        descendants(shape).any(
          (child) => child.line.hasLine && child.line.join == join,
        );

    final decider = dynamic
        .singleWhere((group) => group.name == 'Draw.io JS / AWS3D / AWS 3D')
        .stencils
        .singleWhere((entry) => entry.name == 'Decider')
        .build(94, 3, 3);
    expect(
      hasStrokedJoin(decider, null),
      isFalse,
      reason: 'join="square" is an invalid SVG stroke-linejoin. '
          'mxSvgCanvas2D still writes it; browsers drop it for miter. '
          'VsdxLineJoin.parse null would leave collectLine join unset',
    );
    expect(
      hasStrokedJoin(decider, VsdxLineJoin.miter),
      isTrue,
      reason: 'Decider strokes the inner tiles after linejoin=square',
    );
    expect(
      hasStrokedJoin(decider, VsdxLineJoin.round),
      isTrue,
      reason: 'the first fillstroke stays linejoin=round',
    );

    final arrow = dynamic
        .singleWhere((group) => group.name == 'Draw.io JS / General / general')
        .stencils
        .singleWhere((entry) => entry.name == 'Arrow')
        .build(95, 3, 3);
    expect(
      descendants(arrow)
          .where((shape) => shape.line.hasLine)
          .every((shape) => shape.line.join == VsdxLineJoin.round),
      isTrue,
      reason: 'Arrow join="flat" is after the only fillstroke; parent '
          'collectLine keeps the round join that was painted',
    );

    final works = migrated
        .singleWhere((group) => group.name == 'Draw.io / Cisco / Misc')
        .stencils
        .singleWhere((entry) => entry.name == 'Cisco Works')
        .build(96, 3, 3);
    expect(
      hasStrokedJoin(works, VsdxLineJoin.bevel),
      isTrue,
      reason: 'Cisco Works linejoin=bevel is an XSD join leftover chamfers',
    );

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(decider.copyWith(id: id)),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(
      hasStrokedJoin(leftover, null),
      isFalse,
      reason: 'a second save must keep veLineJoin miter on the square tiles',
    );
    expect(
      hasStrokedJoin(leftover, VsdxLineJoin.miter),
      isTrue,
      reason: '_lineProperties maps join from LineCap; leftover keeps '
          'explicit miter so a later round cap does not round the elbow',
    );
  });

  test('mxStencil default miterlimit is 10 for LibreOffice', () {
    bool hasMiter10(VsdxShape shape) {
      if (shape.line.hasLine &&
          (shape.line.miterLimit - 10.0).abs() < 1e-6) {
        return true;
      }
      return shape.children.any(hasMiter10);
    }

    bool needsFilledSpikeRibbon(VsdxShape shape) {
      if (shapeNeedsLibvisioFilledStrokeRibbonBake(shape)) return true;
      return shape.children.any(needsFilledSpikeRibbon);
    }

    bool hasStrokeRibbon(VsdxShape shape) {
      if (isLibvisioStrokeRibbonPlate(shape)) return true;
      return shape.children.any(hasStrokeRibbon);
    }

    final emr = migrated
        .singleWhere(
          (group) => group.name == 'Draw.io / AWS 2 / Analytics',
        )
        .stencils
        .singleWhere((entry) => entry.name == 'EMR')
        .build(93, 3, 3);
    expect(
      hasMiter10(emr),
      isTrue,
      reason: 'AWS 2 EMR has no <miterlimit>. '
          'mxAbstractCanvas2D.createState miterLimit is 10; Visio / ODF '
          'default 4. leftover bakes a filled stroke ribbon because '
          '_lineProperties never emits svg:stroke-miterlimit',
    );
    expect(
      needsFilledSpikeRibbon(emr),
      isTrue,
      reason: 'EMR has a fillstroke elbow whose miter ratio exceeds 4',
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
              (group) => group.name == 'Draw.io / AWS 2 / Analytics',
            )
            .stencils
            .singleWhere((entry) => entry.name == 'EMR')
            .build(id, 3, 3),
      ),
    );
    final leftoverDoc = parser.parse(
      writer.write(originalBytes: writer.emptyDocument(), edited: doc),
    );
    final leftover = leftoverDoc.pages.first.findShapeById(id)!;
    expect(
      hasStrokeRibbon(leftover) ||
          leftoverDoc.pages.first.shapes.any(hasStrokeRibbon),
      isTrue,
      reason: 'User.veMiterLimit is not a token; leftover must bake the '
          'spike as a LibvisioStrokeRibbon sibling so Draw does not bevel',
    );
    expect(
      hasMiter10(leftover),
      isTrue,
      reason: 'siblings without a spike keep veMiterLimit 10',
    );

    final second = parser.parse(
      writer.write(originalBytes: writer.emptyDocument(), edited: leftoverDoc),
    );
    expect(
      hasStrokeRibbon(second.pages.first.findShapeById(id)!) ||
          second.pages.first.shapes.any(hasStrokeRibbon),
      isTrue,
      reason: 'a second save must keep the baked miter spike ribbon',
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

      final authenticate = sap.stencils
          .singleWhere((entry) => entry.name == 'Authenticate')
          .build(453, 3, 3);
      expect(
        runContaining(authenticate, 'TEXT')!.paraStyle.lineSpacing,
        closeTo(1.14, 0.001),
        reason: 'SAP Authenticate <p style="line-height: 114%"> is '
            'collectParaIX SpLine −1.14 that libvisio maps to '
            'fo:line-height PERCENT',
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

      var authDoc = parser.parse(writer.emptyDocument());
      final authId = authDoc.pages.first.nextFreeShapeId();
      authDoc = authDoc.replacePage(
        0,
        authDoc.pages.first.addShape(authenticate.copyWith(id: authId)),
      );
      final authLeftover = parser
          .parse(
            writer.write(
              originalBytes: writer.emptyDocument(),
              edited: authDoc,
            ),
          )
          .pages
          .first
          .findShapeById(authId)!;
      expect(
        runContaining(authLeftover, 'TEXT')!.paraStyle.lineSpacing,
        closeTo(1.14, 0.001),
        reason: 'a second save must keep SAP Authenticate SpLine 114%',
      );
    },
  );

  test(
    'mxText html CSS font-size keyword stays Char Size for LibreOffice',
    () {
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

      final texts = dynamic.singleWhere(
        (group) => group.name == 'Draw.io JS / SAP / SAP / Text Elements',
      );
      VsdxShape? small;
      for (final entry in texts.stencils) {
        final shape = entry.build(455, 3, 3);
        if (runContaining(shape, 'Small descriptive Text') != null) {
          small = shape;
          break;
        }
      }
      expect(small, isNotNull);
      // 120×30 cell, catalog scale 1.5 / 120.
      const smallScale = 1.5 / 120;
      expect(
        runContaining(small!, 'Small descriptive Text')!
            .charStyle
            .fontSizeInches,
        closeTo(10 * smallScale, 0.01),
        reason: 'CSS font-size:x-small is Chromium 10px at medium 16px, '
            'collectCharIX Size that libvisio maps to fo:font-size, not '
            'defaultVertex 12',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(small.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        runContaining(leftover, 'Small descriptive Text')!
            .charStyle
            .fontSizeInches,
        closeTo(10 * smallScale, 0.01),
        reason: 'a second save must keep CSS x-small Char Size',
      );
    },
  );

  test(
    'mxText html CSS background-color stays Char Highlight for LibreOffice',
    () {
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

      bool hasHighlightPlate(VsdxShape shape, VsdxColor color) {
        if (isLibvisioHighlightPlate(shape) &&
            shape.fill.foreground == color) {
          return true;
        }
        for (final child in shape.children) {
          if (hasHighlightPlate(child, color)) return true;
        }
        return false;
      }

      final nested = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / Atlassian / Atlassian',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Nested discussion')
          .build(456, 3, 3);
      final chip = VsdxColor.tryParse('#F4F5F7')!;
      expect(
        runContaining(nested, 'AUTHOR')!.charStyle.highlight,
        chip,
        reason: 'CSS background-color:rgb(244,245,247) on AUTHOR is '
            'Char.Highlight leftover that bakeMixedHighlightForLibvisioWrite '
            'turns into FillForegnd plates; readCharIX skips Highlight',
      );
      expect(
        runContaining(nested, '@Matthew Wu')!.charStyle.highlight,
        chip,
        reason: 'the mention chip uses the same CSS background-color',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(nested.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        hasHighlightPlate(leftover, chip),
        isTrue,
        reason: 'a second save must keep the AUTHOR chip as FillForegnd '
            'plates Draw paints (readCharIX skips Highlight)',
      );
    },
  );

  test(
    'mxText html defaultVertex fontColor stays black after a colored font for LibreOffice',
    () {
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

      // Capture used to leftover-bake fontcolor="default" from
      // default.xml defaultVertex. _mxGraphPaintColor("default") is
      // null, so Char.Color rode the previous <font color="#10739E">
      // run. createState / DEFAULT_FONTCOLOR is #000000 that
      // collectCharIX maps to fo:color.
      final decoded = decodeDrawioMxStencilXml(
        '<shape name="R" w="200" h="70" strokewidth="inherit">'
        '<foreground>'
        '<text x="0" y="0" str="Label&#10;Lorem" align="center" '
        'valign="top" w="200" h="70">'
        '<run str="Label" fontstyle="1" fontsize="12" '
        'fontcolor="#10739E"/>'
        '<run str="Lorem" fontstyle="0" fontsize="10" '
        'fontcolor="default"/>'
        '</text>'
        '</foreground>'
        '</shape>',
        id: 453,
      );
      expect(
        runContaining(decoded, 'Label')!.charStyle.color?.value,
        VsdxColor(0xFF10739E).value,
      );
      expect(
        runContaining(decoded, 'Lorem')!.charStyle.color,
        VsdxColor.black,
        reason: 'html run fontcolor=default is DEFAULT_FONTCOLOR, not the '
            'previous sibling\'s #10739E',
      );

      final roadmap = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / Infographic / Infographic',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Roadmap (vertical)')
          .build(454, 3, 3);
      expect(
        runContaining(roadmap, 'Label')!.charStyle.color?.value,
        VsdxColor(0xFF10739E).value,
        reason: 'Roadmap <font color="#10739E"> Label stays teal',
      );
      expect(
        runContaining(roadmap, 'Lorem ipsum')!.charStyle.color,
        VsdxColor.black,
        reason: 'body <font size="1"> has no color; mxText uses '
            'defaultVertex #000000 after the teal title closes',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(roadmap.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        runContaining(leftover, 'Lorem ipsum')!.charStyle.color,
        VsdxColor.black,
        reason: 'a second save must keep Char Color black on the body',
      );
      expect(
        runContaining(leftover, 'Label')!.charStyle.color?.value,
        VsdxColor(0xFF10739E).value,
        reason: 'a second save must keep Label teal',
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

  test('IBM dashed connectors leftover-bake mx 3 3 for LibreOffice', () {
    final dashed = dynamic
        .singleWhere(
          (group) => group.name == 'Draw.io JS / IBM / IBM / Connectors',
        )
        .stencils
        .singleWhere((entry) => entry.name == 'Dashed Connector');
    final shape = dashed.build(51, 3, 3);
    final custom = shape.line.customDashPattern;
    expect(
      shape.line.pattern,
      1,
      reason: 'mxShape.configureCanvas dashed=1 with no dashpattern uses '
          'createState 3 3 as veDashPattern, not tokens.txt LinePattern 2',
    );
    expect(shape.line.fixedDash, isTrue);
    expect(custom, isNotNull);
    expect(custom!.length, greaterThanOrEqualTo(2));
    expect(
      (custom.first - custom[1]).abs(),
      lessThan(1e-6),
      reason: 'createState dashPattern is equal on/off 3 3',
    );
    expect(shape.geometries, isNotEmpty);

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(dashed.build(id, 3, 3)),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(
      leftover.geometries
          .expand((geometry) => geometry.commands)
          .whereType<MoveTo>()
          .length,
      greaterThanOrEqualTo(2),
      reason: 'libvisio _lineProperties treats 0xfe as solid; leftover bakes '
          'the 3 3 veDashPattern into MoveTo gaps Draw can stroke',
    );
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
      greaterThan(1),
      reason: 'the outer box stays native geometry',
    );
    expect(
      descendantGeometries(table)
          .where(
            (geometry) =>
                !geometry.noLine &&
                geometry.commands.whereType<LineTo>().length >= 3,
          )
          .length,
      greaterThan(2),
      reason: 'JS capture emits table cell rects as consecutive <move> '
          'without <line>; coalesce them so collectGeometry paints the '
          'grid LibreOffice would otherwise drop',
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
    expect(
      descendantGeometries(leftover.findShapeById(tableId)!)
          .where(
            (geometry) =>
                !geometry.noLine &&
                geometry.commands.whereType<LineTo>().length >= 3,
          )
          .length,
      greaterThan(2),
      reason: 'a second save must keep the coalesced cell LineTo rails',
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
      descendantGeometries(choreography).length,
      greaterThan(1),
      reason: 'zero-arg palette roots must keep working sb factories. '
          'Choreography bands are extra-inherit fill siblings so '
          'collectGeometry evenodd does not punch the header',
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
      final signatureDash = signature.line.customDashPattern;
      expect(
        signature.line.pattern,
        1,
        reason: 'mxShape.configureCanvas dashed=1 with no dashpattern uses '
            'createState 3 3 as veDashPattern, not tokens.txt LinePattern 2',
      );
      expect(signature.line.fixedDash, isTrue);
      expect(signatureDash, isNotNull);
      expect(signatureDash!.length, greaterThanOrEqualTo(2));

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
      expect(
        leftover
            .findShapeById(dashId)!
            .geometries
            .expand((geometry) => geometry.commands)
            .whereType<MoveTo>()
            .length,
        greaterThanOrEqualTo(2),
        reason: 'a second save bakes Template signature 3 3 into MoveTo gaps',
      );
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
      final zoneDash = zone.line.customDashPattern;
      expect(
        zone.line.pattern,
        1,
        reason: 'mxShape.configureCanvas dashed=1 with no dashpattern uses '
            'createState 3 3 as veDashPattern, not tokens.txt LinePattern 2',
      );
      expect(zone.line.fixedDash, isTrue);
      expect(zoneDash, isNotNull);
      expect(zoneDash!.length, greaterThanOrEqualTo(2));

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
        leftover
            .findShapeById(zoneId)!
            .geometries
            .expand((geometry) => geometry.commands)
            .whereType<MoveTo>()
            .length,
        greaterThanOrEqualTo(2),
        reason: 'a second save bakes Availability Zone 3 3 into MoveTo gaps',
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
    'mxImageShape SVG url(#gradient) tessellates FillForegnd for LibreOffice',
    () {
      bool isSapLogoBand(VsdxFill fill) {
        if (!fill.hasFill || fill.pattern != 1) return false;
        final color = fill.foreground;
        if (color == null) return false;
        // SAP_Logo.svg url(#b) tessellates navy #1E5FBB → cyan #05A7E6.
        // libvisio has no FillGradient token; leftover FillPattern 25–40
        // would 0→1 the XForm. Keep FillForegnd slabs.
        return color.red <= 0x1E &&
            color.green >= 0x5F &&
            color.green <= 0xA7 &&
            color.blue >= 0xBB;
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
        descendantFills(sap).where(isSapLogoBand).length,
        greaterThanOrEqualTo(4),
        reason: 'SAP_Logo.svg fill=url(#b) tessellates as FillPattern 1 '
            'navy→cyan slabs Draw can paint; FillPattern 25–40 would 0→1 '
            'the XForm',
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
        descendantFills(leftover).where(isSapLogoBand).length,
        greaterThanOrEqualTo(4),
        reason: 'a second save must keep the SAP Logo FillForegnd slabs',
      );
    },
  );

  test(
    'mxgraph.sap.icon SVG stays FillPattern 25–40 for LibreOffice',
    () {
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
            .whereType<LineTo>()
            .length,
        greaterThanOrEqualTo(8),
        reason: 'mxgraph.sap.icon SAPIcon=SAP_PKI_Certificate_Service '
            'must vectorise img/lib/sap/*.svg, not only the grey ellipse',
      );
      expect(
        descendantFills(pki).where((fill) {
          final color = fill.foreground;
          if (color == null ||
              fill.pattern != 1 ||
              fill.gradient != null) {
            return false;
          }
          return color.red < 40 &&
              color.green > 100 &&
              color.blue > 240;
        }).length,
        greaterThanOrEqualTo(4),
        reason: 'diamond url(#linear-gradient) is ~10° off ODF 135°; '
            'FillPattern 32 and leftover FillGradient would 0→1 the '
            'XForm / bake a white PNG. Tessellate #0195ff→#1147e9 as '
            'FillForegnd slabs',
      );
      expect(
        descendantFills(pki).where((fill) {
          final color = fill.foreground;
          if (color == null ||
              fill.pattern != 1 ||
              fill.gradient != null) {
            return false;
          }
          return color.red < 40 && color.green < 90 && color.blue > 120;
        }).length,
        greaterThanOrEqualTo(6),
        reason: 'lock url(#linear-gradient1) is a short userSpaceOnUse '
            'vector; FillPattern 32 would 0→1 the viewBox. Tessellate '
            '#1348ff→#06238d as FillForegnd slabs',
      );
      expect(
        descendantFills(pki).any((fill) => fill.pattern == 32),
        isFalse,
        reason: 'the ~10° diamond must not snap to FillPattern 32',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(pki.copyWith(id: id)),
      );
      Iterable<VsdxShape> descendants(VsdxShape shape) sync* {
        yield shape;
        for (final child in shape.children) {
          yield* descendants(child);
        }
      }

      final leftover = parser.parse(
        writer.write(originalBytes: writer.emptyDocument(), edited: doc),
      );
      expect(
        leftover.pages.first.shapes
            .expand(descendants)
            .where(isLibvisioSoftEdgesPlate),
        isEmpty,
        reason: 'PKI diamond slabs stay native; leftover must not bake a '
            'white SoftEdges PNG over the lock',
      );
    },
  );

  test(
    'mxImageShape SVG diagonal url(#gradient) stays FillPattern 31–34 for LibreOffice',
    () {
      Iterable<VsdxFill> descendantFills(VsdxShape shape) sync* {
        yield shape.fill;
        for (final child in shape.children) {
          yield* descendantFills(child);
        }
      }

      final globe = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / Azure2 / Azure / General',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Globe')
          .build(160, 3, 3);
      expect(
        descendantFills(globe).where((fill) {
          final color = fill.foreground;
          if (color == null ||
              fill.pattern != 1 ||
              fill.gradient != null) {
            return false;
          }
          return color.red < 110 &&
              color.green > 110 &&
              color.green < 180 &&
              color.blue > 200;
        }).length,
        greaterThanOrEqualTo(6),
        reason: 'Globe.svg matrix(0.707,0.707,…) 45° vector is short vs the '
            'viewBox; FillPattern 34 would 0→1 the XForm and drop the '
            '0.82 stop. Tessellate #0078d4→#5ea0ef as FillForegnd slabs',
      );

      final pki = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / SAP / SAP / Foundational',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'SAP PKI Certificate Service')
          .build(161, 3, 3);
      expect(
        descendantFills(pki).any((fill) => fill.pattern == 32),
        isFalse,
        reason: 'SAP_PKI_Certificate_Service.svg Y-flipped diamond is '
            '~10° off ODF 135° so leftover FillGradient would hide the '
            'lock; tessellate as FillForegnd slabs',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(globe.copyWith(id: id)),
      );
      Iterable<VsdxShape> descendants(VsdxShape shape) sync* {
        yield shape;
        for (final child in shape.children) {
          yield* descendants(child);
        }
      }

      final leftover = parser.parse(
        writer.write(originalBytes: writer.emptyDocument(), edited: doc),
      );
      expect(
        leftover.pages.first.shapes
            .expand(descendants)
            .where(isLibvisioSoftEdgesPlate),
        isEmpty,
        reason: 'Globe 45° / 0.82 wash stays native slabs; leftover must '
            'not bake a full-box FillGradient PNG',
      );
    },
  );

  test(
    'mxImageShape SVG stroke url(#gradient) stays FillPattern for LibreOffice',
    () {
      Iterable<VsdxShape> descendants(VsdxShape shape) sync* {
        yield shape;
        for (final child in shape.children) {
          yield* descendants(child);
        }
      }

      int lineCommands(VsdxShape shape) {
        var n = 0;
        for (final geometry in shape.geometries) {
          n += geometry.commands.whereType<LineTo>().length;
          n += geometry.commands.whereType<RelLineTo>().length;
        }
        return n;
      }

      bool isCrescent(VsdxShape shape) {
        return shape.fill.hasFill &&
            shape.fill.pattern == 32 &&
            shape.fill.foreground == VsdxColor.tryParse('#1147E9') &&
            shape.fill.background == VsdxColor.tryParse('#0195FF') &&
            !shape.line.hasLine &&
            lineCommands(shape) > 40;
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
      expect(
        descendants(cloud).any(isCrescent),
        isTrue,
        reason: 'stroke=url(#A) #0195ff→#1147e9 (x1,y1)→(x2,y2) southeast '
            'must become FillPattern 32 because collectLine does not read '
            'LineGradient; the 1.875 width is the ribbon '
            'collectFillAndShadow paints',
      );

      final ticks = dynamic
          .singleWhere(
            (group) =>
                group.name == 'Draw.io JS / SAP / SAP / App Dev Automation',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'SAP Task Center')
          .build(137, 3, 3);
      expect(
        descendants(ticks)
            .where(
              (shape) =>
                  shape.fill.pattern == 40 &&
                  shape.fill.foreground == VsdxColor.tryParse('#00BBFF') &&
                  lineCommands(shape) > 8,
            )
            .length,
        greaterThanOrEqualTo(4),
        reason: 'Task Center stroke=url(#A) ticks must be radial FillPattern '
            '40 ribbons, not a first-stop solid LineColor',
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
        descendants(leftover).any(isCrescent),
        isTrue,
        reason: 'a second save must keep the SVG gradient-stroke ribbon',
      );
    },
  );

  test(
    'mxImageShape SVG short userSpaceOnUse linear stays native for LibreOffice',
    () {
      Iterable<VsdxFill> descendantFills(VsdxShape shape) sync* {
        yield shape.fill;
        for (final child in shape.children) {
          yield* descendantFills(child);
        }
      }

      Iterable<VsdxShape> descendants(VsdxShape shape) sync* {
        yield shape;
        for (final child in shape.children) {
          yield* descendants(child);
        }
      }

      bool isCyanWedgeBand(VsdxFill fill) {
        final color = fill.foreground;
        if (color == null || fill.pattern != 1 || fill.gradient != null) {
          return false;
        }
        return color.red < 40 &&
            color.green > 120 &&
            color.green < 200 &&
            color.blue > 240;
      }

      final cloud = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / SAP / SAP / Data Analytics',
          )
          .stencils
          .singleWhere(
            (entry) => entry.name == 'SAP Analytics Cloud Embedded Edition',
          )
          .build(171, 3, 3);
      expect(
        descendantFills(cloud).where(isCyanWedgeBand).length,
        greaterThanOrEqualTo(6),
        reason: 'Embedded Edition url(#B) (12.2,2)→(18.5,6.8) must tessellate '
            'as FillForegnd slabs; FillPattern 32 interpolates 0→1 on the '
            'viewBox XForm so the corner wedge would miss #00bbff',
      );
      expect(
        descendantFills(cloud).any(
          (fill) =>
              fill.pattern == 32 &&
              fill.foreground == VsdxColor.tryParse('#1147E9') &&
              fill.background == VsdxColor.tryParse('#0195FF'),
        ),
        isTrue,
        reason: 'stroke url(#A) across the pie stays FillPattern 32',
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
        descendants(leftover).where(isLibvisioSoftEdgesPlate),
        isEmpty,
        reason: 'local slabs stay native; leftover must not bake a full-box '
            'FillGradient PNG',
      );
      expect(
        descendants(leftover)
            .where((shape) => isCyanWedgeBand(shape.fill))
            .length,
        greaterThanOrEqualTo(6),
        reason: 'a second save must keep the cyan wedge slabs',
      );
    },
  );

  test(
    'mxImageShape SVG short userSpaceOnUse gradient stroke stays native for LibreOffice',
    () {
      Iterable<VsdxFill> descendantFills(VsdxShape shape) sync* {
        yield shape.fill;
        for (final child in shape.children) {
          yield* descendantFills(child);
        }
      }

      Iterable<VsdxShape> descendants(VsdxShape shape) sync* {
        yield shape;
        for (final child in shape.children) {
          yield* descendants(child);
        }
      }

      bool isCheckStrokeBand(VsdxFill fill) {
        final color = fill.foreground;
        if (color == null || fill.pattern != 1 || fill.gradient != null) {
          return false;
        }
        return color.red < 30 &&
            color.green < 90 &&
            color.blue > 130;
      }

      int lineCommands(VsdxShape shape) {
        var n = 0;
        for (final geometry in shape.geometries) {
          n += geometry.commands.whereType<LineTo>().length;
          n += geometry.commands.whereType<RelLineTo>().length;
        }
        return n;
      }

      final login = dynamic
          .singleWhere(
            (group) =>
                group.name == 'Draw.io JS / SAP / SAP / Foundational',
          )
          .stencils
          .singleWhere(
            (entry) => entry.name == 'SAP Secure Login Service for SAP GUI',
          )
          .build(175, 3, 3);
      expect(
        descendantFills(login).where(isCheckStrokeBand).length,
        greaterThanOrEqualTo(6),
        reason: 'SAP_Secure_Login_Service_for_SAP_GUI.svg stroke url(#B) '
            '(10.7,13.3)→(14.5,19.3) must tessellate as FillForegnd slabs; '
            'collectLine has no LineGradient and FillPattern 32 0→1s the '
            'icon XForm',
      );
      expect(
        descendants(login).any(
          (shape) =>
              shape.fill.pattern == 32 &&
              shape.fill.foreground == VsdxColor.tryParse('#1147E9') &&
              shape.fill.background == VsdxColor.tryParse('#0195FF') &&
              shape.fill.gradient == null,
        ),
        isTrue,
        reason: 'diamond fill url(#A) across the viewBox stays FillPattern 32',
      );

      final cloud = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / SAP / SAP / Data Analytics',
          )
          .stencils
          .singleWhere(
            (entry) => entry.name == 'SAP Analytics Cloud Embedded Edition',
          )
          .build(176, 3, 3);
      expect(
        descendants(cloud).any(
          (shape) =>
              shape.fill.pattern == 32 &&
              shape.fill.foreground == VsdxColor.tryParse('#1147E9') &&
              shape.fill.background == VsdxColor.tryParse('#0195FF') &&
              !shape.line.hasLine &&
              lineCommands(shape) > 40,
        ),
        isTrue,
        reason: 'full-box crescent stroke url(#A) stays FillPattern 32',
      );

      final ticks = dynamic
          .singleWhere(
            (group) =>
                group.name == 'Draw.io JS / SAP / SAP / App Dev Automation',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'SAP Task Center')
          .build(177, 3, 3);
      expect(
        descendants(ticks).where(
          (shape) =>
              shape.fill.pattern == 40 &&
              shape.fill.foreground == VsdxColor.tryParse('#00BBFF'),
        ).length,
        greaterThanOrEqualTo(4),
        reason: 'Task Center radial stroke ticks stay native FillPattern 40',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(login.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        descendants(leftover).where(isLibvisioSoftEdgesPlate),
        isEmpty,
        reason: 'short stroke slabs stay native; leftover must not bake a '
            'full-box FillGradient PNG',
      );
      expect(
        descendants(leftover)
            .where((shape) => isCheckStrokeBand(shape.fill))
            .length,
        greaterThanOrEqualTo(6),
        reason: 'a second save must keep the check stroke slabs',
      );
    },
  );

  test(
    'mxImageShape SVG feOffset filter stays ShdwPattern for LibreOffice',
    () {
      Iterable<VsdxShape> descendants(VsdxShape shape) sync* {
        yield shape;
        for (final child in shape.children) {
          yield* descendants(child);
        }
      }

      bool isDropShadow(VsdxShape shape) {
        final shadow = shape.shadow;
        return shadow.enabled &&
            shadow.pattern == 1 &&
            shadow.blurInches.abs() < 1e-9 &&
            shadow.offsetXInches.abs() > 1e-4 &&
            shape.fill.hasFill;
      }

      final zone = dynamic
          .singleWhere(
            (group) =>
                group.name == 'Draw.io JS / SAP / SAP / App Dev Automation',
          )
          .stencils
          .singleWhere(
            (entry) => entry.name == 'SAP Build Work Zone - Advanced Edition',
          )
          .build(138, 3, 3);
      expect(
        descendants(zone).where(isDropShadow).length,
        greaterThanOrEqualTo(3),
        reason: 'feOffset dx/dy drop-shadows must become ShdwPattern 1 that '
            'collectFillAndShadow maps to draw:shadow; blur-only filters stay '
            'unmapped',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(zone.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        descendants(leftover).where(isDropShadow).length,
        greaterThanOrEqualTo(3),
        reason: 'a second save must keep the SVG feOffset ShdwPattern',
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
    'mxImageShape SVG stroke-dasharray stays veDashPattern for LibreOffice',
    () {
      Iterable<VsdxShape> descendants(VsdxShape shape) sync* {
        yield shape;
        for (final child in shape.children) {
          yield* descendants(child);
        }
      }

      bool hasFixedDash(VsdxShape shape) {
        final custom = shape.line.customDashPattern;
        return !shape.fill.hasFill &&
            shape.line.hasLine &&
            shape.line.color == VsdxColor.white &&
            custom != null &&
            custom.length >= 2 &&
            shape.line.fixedDash;
      }

      final partition = dynamic
          .singleWhere(
            (group) =>
                group.name == 'Draw.io JS / ActiveDirectory / Active Directory',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Database Partition 2')
          .build(139, 3, 3);
      expect(
        descendants(partition).any(hasFixedDash),
        isTrue,
        reason: 'database_partition_2.svg stroke-dasharray="8,8" must reach '
            'collectLine as veDashPattern, not a solid white slash',
      );

      final partition4 = dynamic
          .singleWhere(
            (group) =>
                group.name == 'Draw.io JS / ActiveDirectory / Active Directory',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Database Partition 4')
          .build(140, 3, 3);
      expect(
        descendants(partition4).where(hasFixedDash).length,
        2,
        reason: 'Partition 4 has two dashed slashes',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(partition.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        descendants(leftover).any((shape) {
          if (shape.fill.hasFill || !shape.line.hasLine) return false;
          if (shape.line.color != VsdxColor.white) return false;
          final moves = shape.geometries
              .expand((geometry) => geometry.commands)
              .whereType<MoveTo>()
              .length;
          return moves >= 2;
        }),
        isTrue,
        reason: 'a second save bakes veDashPattern into MoveTo gaps '
            'because libvisio treats custom LinePattern 0xfe as solid',
      );
    },
  );

  test(
    'mxImageShape SVG fill-opacity stays FillForegndTrans for LibreOffice',
    () {
      bool isFadedBlack(VsdxShape shape, double trans) {
        return shape.fill.hasFill &&
            shape.fill.pattern == 1 &&
            shape.fill.foreground == VsdxColor.black &&
            (shape.fill.foregroundTransparency - trans).abs() < 0.02;
      }

      final powerBi = dynamic
          .singleWhere(
            (group) =>
                group.name == 'Draw.io JS / Azure2 / Azure / Power Platform',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'PowerBI')
          .build(141, 3, 3);
      expect(
        powerBi.children.any((child) => isFadedBlack(child, 0.80)),
        isTrue,
        reason: 'PowerBI.svg fill-opacity="0.2" must reach collectFillAndShadow '
            'as FillForegndTrans 0.80, not an opaque black overlay',
      );
      expect(
        powerBi.children.any((child) => isFadedBlack(child, 0.82)),
        isTrue,
        reason: 'PowerBI.svg fill-opacity="0.18" must reach '
            'collectFillAndShadow as FillForegndTrans 0.82',
      );

      final fieldService = dynamic
          .singleWhere(
            (group) =>
                group.name == 'Draw.io JS / Dynamics365 / Dynamics365 / App',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Field Service')
          .build(142, 3, 3);
      expect(
        fieldService.children.any((child) => isFadedBlack(child, 0.80)),
        isTrue,
        reason: 'FieldService.svg fill="#000" fill-opacity=".2" must not stay '
            'opaque black',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(powerBi.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        leftover.children.any((child) => isFadedBlack(child, 0.80)),
        isTrue,
        reason: 'a second save must keep the Power BI shadow FillForegndTrans',
      );
    },
  );

  test(
    'mxImageShape SVG matrix(a,b,c,d) stays rotated geometry for LibreOffice',
    () {
      double geometrySpan(VsdxShape shape) {
        var minX = double.infinity, maxX = -double.infinity;
        var minY = double.infinity, maxY = -double.infinity;
        void point(double x, double y) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }

        for (final geometry in shape.geometries) {
          for (final command in geometry.commands) {
            switch (command) {
              case EllipseCmd(:final cx, :final cy, :final aX, :final aY,
                    :final bX, :final bY):
                point(cx, cy);
                point(aX, aY);
                point(bX, bY);
              case MoveTo(:final x, :final y):
                point(x, y);
              case LineTo(:final x, :final y):
                point(x, y);
              case CubBezTo(:final x, :final y, :final x1, :final y1,
                    :final x2, :final y2):
                point(x, y);
                point(x1, y1);
                point(x2, y2);
              case RelMoveTo(:final fx, :final fy):
                point(fx * shape.width, fy * shape.height);
              case RelLineTo(:final fx, :final fy):
                point(fx * shape.width, fy * shape.height);
              case RelCubBezTo(
                  :final fx,
                  :final fy,
                  :final fx1,
                  :final fy1,
                  :final fx2,
                  :final fy2
                ):
                point(fx * shape.width, fy * shape.height);
                point(fx1 * shape.width, fy1 * shape.height);
                point(fx2 * shape.width, fy2 * shape.height);
              default:
                break;
            }
          }
        }
        if (!minX.isFinite) return 0;
        final dx = (maxX - minX).clamp(0.0, 99.0);
        final dy = (maxY - minY).clamp(0.0, 99.0);
        return (dx < dy ? dx : dy).toDouble();
      }

      final topics = dynamic
          .singleWhere(
            (group) => group.name ==
                'Draw.io JS / MSCAE / CAE / Integration Service',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Event Grid Topics')
          .build(143, 3, 3);
      const lime = VsdxColor(0xFFB8D432);
      const cyan = VsdxColor(0xFF59B4D9);
      final limeDots = topics.children
          .where((child) => child.fill.foreground == lime)
          .toList();
      expect(
        limeDots.length,
        2,
        reason: 'Event_Grid_Topics.svg has two lime status dots',
      );
      for (final dot in limeDots) {
        expect(
          geometrySpan(dot),
          greaterThan(0.10),
          reason: 'matrix(.707 -.707 .707 .707) must not scale(0.707) the '
              'lime circle — collectGeometry would shrink the fill LibreOffice '
              'paints',
        );
      }
      expect(
        topics.children.any(
          (child) =>
              child.fill.foreground == cyan && geometrySpan(child) > 0.10,
        ),
        isTrue,
        reason: 'the cyan matrix() dot must keep r=3.9 in stencil units',
      );

      final micro = dynamic
          .singleWhere(
            (group) =>
                group.name == 'Draw.io JS / IBM / IBM / Miscellaneous',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Microservices Application')
          .build(144, 3, 3);
      expect(
        micro.children.any(
          (child) => !child.fill.hasFill && geometrySpan(child) > 0.7,
        ),
        isTrue,
        reason: 'matrix(.02 -.999 .999 .02) must not scale(0.02) the white '
            'circle into a pin LibreOffice would drop',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(topics.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        leftover.children
            .where((child) => child.fill.foreground == lime)
            .every((child) => geometrySpan(child) > 0.10),
        isTrue,
        reason: 'a second save must keep the Event Grid matrix() dots',
      );
    },
  );

  test(
    'mxImageShape SVG clip-path stays intersected geometry for LibreOffice',
    () {
      List<({double x, double y})> geometryPoints(VsdxShape shape) {
        final points = <({double x, double y})>[];
        void point(double x, double y) => points.add((x: x, y: y));
        for (final geometry in shape.geometries) {
          for (final command in geometry.commands) {
            switch (command) {
              case EllipseCmd(:final cx, :final cy, :final aX, :final aY,
                    :final bX, :final bY):
                point(cx, cy);
                point(aX, aY);
                point(bX, bY);
              case MoveTo(:final x, :final y):
                point(x, y);
              case LineTo(:final x, :final y):
                point(x, y);
              case CubBezTo(:final x, :final y):
                point(x, y);
              case RelMoveTo(:final fx, :final fy):
                point(fx * shape.width, fy * shape.height);
              case RelLineTo(:final fx, :final fy):
                point(fx * shape.width, fy * shape.height);
              case RelCubBezTo(:final fx, :final fy):
                point(fx * shape.width, fy * shape.height);
              default:
                break;
            }
          }
        }
        return points;
      }

      int lineCommands(VsdxShape shape) {
        var n = 0;
        for (final geometry in shape.geometries) {
          n += geometry.commands.whereType<LineTo>().length;
          n += geometry.commands.whereType<RelLineTo>().length;
        }
        return n;
      }

      final globe = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / Azure2 / Azure / General',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Globe')
          .build(145, 3, 3);
      const teal = VsdxColor(0xFF42E8CA);
      final diskPts = globe.children
          .where((child) {
            final color = child.fill.foreground;
            if (color == null || child.fill.pattern != 1) return false;
            return color.red < 110 &&
                color.green > 110 &&
                color.green < 180 &&
                color.blue > 200;
          })
          .expand(geometryPoints)
          .toList();
      expect(
        diskPts,
        isNotEmpty,
        reason: 'Globe.svg ocean url(#gradient) tessellates as azure slabs',
      );
      final cx =
          diskPts.map((p) => p.x).reduce((a, b) => a + b) / diskPts.length;
      final cy =
          diskPts.map((p) => p.y).reduce((a, b) => a + b) / diskPts.length;
      var radius = 0.0;
      for (final point in diskPts) {
        final dist = math.sqrt(
          math.pow(point.x - cx, 2) + math.pow(point.y - cy, 2),
        );
        if (dist > radius) radius = dist;
      }
      final meridians = globe.children
          .where((child) => child.fill.foreground == teal)
          .toList();
      expect(
        meridians,
        isNotEmpty,
        reason: 'Globe.svg clips teal meridians to the globe disk',
      );
      for (final child in meridians) {
        for (final point in geometryPoints(child)) {
          final dist = math.sqrt(
            math.pow(point.x - cx, 2) +
                math.pow(point.y - cy, 2),
          );
          expect(
            dist,
            lessThan(radius * 1.08),
            reason: 'clip-path circle must intersect meridians so '
                'collectGeometry does not paint teal outside the disk '
                'LibreOffice would show',
          );
        }
        expect(
          lineCommands(child),
          greaterThan(8),
          reason: 'clipped meridians become polygons, not overflowing paths',
        );
      }

      final cosmos = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / Azure2 / Azure / Databases',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Cosmos DB')
          .build(146, 3, 3);
      expect(
        cosmos.children
            .where((child) => child.fill.foreground == const VsdxColor(0xFFF2F2F2))
            .every((child) => lineCommands(child) > 8),
        isTrue,
        reason: 'Cosmos DB gray clouds are clip-path intersected with the '
            'blue globe so they cannot spill outside collectGeometry',
      );

      final embedded = dynamic
          .singleWhere(
            (group) =>
                group.name == 'Draw.io JS / Azure2 / Azure / Analytics',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Power BI Embedded')
          .build(147, 3, 3);
      expect(embedded.children.length, greaterThanOrEqualTo(18));
      expect(
        embedded.children.every((child) => lineCommands(child) >= 3),
        isTrue,
        reason: 'Power BI Embedded bars tessellate as clipped polygons, '
            'not unfilled leftover plates',
      );
      expect(
        embedded.children.any((child) => lineCommands(child) > 8),
        isTrue,
        reason: 'clip-path stairs must round at least one bar slab instead '
            'of leaving sharp overflowing rects',
      );

      final vuln = dynamic
          .singleWhere(
            (group) =>
                group.name == 'Draw.io JS / SAP / SAP / Foundational',
          )
          .stencils
          .singleWhere(
            (entry) => entry.name == 'Application Vulnerability Report',
          )
          .build(148, 3, 3);
      expect(
        vuln.children.length,
        greaterThanOrEqualTo(8),
        reason: 'viewBox-sized rect clip-path is identity so it must not '
            'drop the shield; off-slot url(#linear-gradient) tessellates '
            'as FillForegnd slabs',
      );

      final writer = VsdxWriter();
      final parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(globe.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        leftover.children
            .where((child) => child.fill.foreground == teal)
            .every((child) => lineCommands(child) > 8),
        isTrue,
        reason: 'a second save must keep Globe meridians as clipped polygons',
      );
    },
  );

  test(
    'mxImageShape SVG mask stays intersected geometry for LibreOffice',
    () {
      List<({double x, double y})> geometryPoints(VsdxShape shape) {
        final points = <({double x, double y})>[];
        void point(double x, double y) => points.add((x: x, y: y));
        for (final geometry in shape.geometries) {
          for (final command in geometry.commands) {
            switch (command) {
              case MoveTo(:final x, :final y):
                point(x, y);
              case LineTo(:final x, :final y):
                point(x, y);
              case CubBezTo(:final x, :final y):
                point(x, y);
              case RelMoveTo(:final fx, :final fy):
                point(fx * shape.width, fy * shape.height);
              case RelLineTo(:final fx, :final fy):
                point(fx * shape.width, fy * shape.height);
              case RelCubBezTo(:final fx, :final fy):
                point(fx * shape.width, fy * shape.height);
              default:
                break;
            }
          }
        }
        return points;
      }

      int lineCommands(VsdxShape shape) {
        var n = 0;
        for (final geometry in shape.geometries) {
          n += geometry.commands.whereType<LineTo>().length;
          n += geometry.commands.whereType<RelLineTo>().length;
        }
        return n;
      }

      bool insideParent(VsdxShape child, VsdxShape parent) {
        const pad = 0.03;
        return geometryPoints(child).every(
          (point) =>
              point.x >= -pad &&
              point.y >= -pad &&
              point.x <= parent.width + pad &&
              point.y <= parent.height + pad,
        );
      }

      final sapBuild = dynamic
          .singleWhere(
            (group) =>
                group.name == 'Draw.io JS / SAP / SAP / App Dev Automation',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'SAP Build')
          .build(149, 3, 3);
      final blobs = sapBuild.children
          .where((child) {
            final color = child.fill.foreground;
            if (color == null ||
                child.fill.pattern != 1 ||
                lineCommands(child) <= 8) {
              return false;
            }
            return color.blue > 200 && color.red < 40;
          })
          .toList();
      expect(
        blobs.length,
        greaterThanOrEqualTo(3),
        reason: 'SAP_Build.svg paints navy/azure/cyan fills under '
            'maskUnits=userSpaceOnUse; off-slot ramps tessellate as '
            'FillForegnd slabs',
      );
      for (final child in blobs) {
        expect(
          lineCommands(child),
          greaterThan(8),
          reason: 'mask letterform must intersect the overflowing gradient '
              'blobs so collectGeometry does not paint outside the glyph '
              'LibreOffice would show',
        );
        expect(
          insideParent(child, sapBuild),
          isTrue,
          reason: 'unmasked SAP Build blobs extend to x=-6 / y=-4 in SVG units',
        );
      }

      final coreHr = dynamic
          .singleWhere(
            (group) =>
                group.name == 'Draw.io JS / Dynamics365 / Dynamics365 / App',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Core HR')
          .build(150, 3, 3);
      expect(
        coreHr.children.every((child) => insideParent(child, coreHr)),
        isTrue,
        reason: 'CoreHR.svg mask-type=alpha rounded rect must clip the '
            'person silhouette that otherwise spills minY < 0',
      );

      final writer = VsdxWriter();
      final parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(sapBuild.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        leftover.children
            .where((child) {
              final color = child.fill.foreground;
              if (color == null || child.fill.pattern != 1) return false;
              return color.blue > 200 && color.red < 40;
            })
            .every((child) => lineCommands(child) > 8),
        isTrue,
        reason: 'a second save must keep SAP Build mask polygons',
      );
    },
  );

  test(
    'mxImageShape SVG mask use stays intersected geometry for LibreOffice',
    () {
      int lineCommands(VsdxShape shape) {
        var n = 0;
        for (final geometry in shape.geometries) {
          n += geometry.commands.whereType<LineTo>().length;
          n += geometry.commands.whereType<RelLineTo>().length;
        }
        return n;
      }

      final voip = dynamic
          .singleWhere(
            (group) =>
                group.name ==
                'Draw.io JS / AlliedTelesis / Allied Telesis / Computer and Terminals',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'VOIP IP Phone')
          .build(151, 3, 3);
      const grey = VsdxColor(0xFF626366);
      final clippedStrokes = voip.children
          .where(
            (child) =>
                child.fill.foreground == grey &&
                child.fill.hasFill &&
                lineCommands(child) > 6,
          )
          .toList();
      expect(
        clippedStrokes.length,
        greaterThan(20),
        reason: 'VOIP_IP_phone.svg masks reference <use href> paths and the '
            'handset strokes are fill:none; capture must resolve those uses '
            'and expand the strokes into clipped ribbons so collectGeometry '
            'sees polygons LibreOffice can paint',
      );

      final building = dynamic
          .singleWhere(
            (group) =>
                group.name ==
                'Draw.io JS / AlliedTelesis / Allied Telesis / Buildings',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Secure Building')
          .build(152, 3, 3);
      final bushes = building.children
          .where((child) {
            final color = child.fill.foreground;
            if (color == null ||
                child.fill.pattern != 1 ||
                lineCommands(child) <= 20) {
              return false;
            }
            final delta = (color.red - color.green).abs() +
                (color.green - color.blue).abs();
            return delta < 20 && color.red > 150 && color.red < 240;
          })
          .toList();
      expect(
        bushes,
        isNotEmpty,
        reason: 'Secure_Building.svg paints grey bushes under mask+<use>; '
            'skipping use left unclipped CubBez fills that Draw would '
            'paint outside the mask letter. Off-slot leftover ramps '
            'tessellate as FillForegnd slabs',
      );

      final writer = VsdxWriter();
      final parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(voip.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        leftover.children
            .where(
              (child) =>
                  child.fill.foreground == grey && child.fill.hasFill,
            )
            .where((child) => lineCommands(child) > 6)
            .length,
        greaterThan(20),
        reason: 'a second save must keep VOIP mask+use stroke ribbons',
      );
    },
  );

  test(
    'mxImageShape SVG rotated roundrect stays CubBezTo for LibreOffice',
    () {
      int cubics(VsdxShape shape) {
        var n = 0;
        for (final geometry in shape.geometries) {
          n += geometry.commands.whereType<CubBezTo>().length;
          n += geometry.commands.whereType<RelCubBezTo>().length;
        }
        return n;
      }

      int lines(VsdxShape shape) {
        var n = 0;
        for (final geometry in shape.geometries) {
          n += geometry.commands.whereType<LineTo>().length;
        }
        return n;
      }

      final search = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / Azure2 / Azure / General',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Search')
          .build(153, 3, 3);
      const handle = VsdxColor(0xFF198AB3);
      final handleKids = search.children
          .where(
            (child) =>
                child.fill.foreground == handle && child.fill.hasFill,
          )
          .toList();
      expect(handleKids, isNotEmpty);
      expect(
        cubics(handleKids.first),
        greaterThanOrEqualTo(4),
        reason: 'Search.svg handle is rect rx + rotate(-45); capture must '
            'tessellate cubic corners so collectGeometry sees a capsule, '
            'not a four-line diamond',
      );
      expect(
        lines(handleKids.first),
        greaterThanOrEqualTo(4),
        reason: 'the stadium still has four side segments between corners',
      );

      final keys = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / Azure2 / Azure / Security',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Keys')
          .build(154, 3, 3);
      expect(
        keys.children.any(
          (child) =>
              child.fill.foreground == VsdxColor.white &&
              child.fill.hasFill &&
              cubics(child) >= 4,
        ),
        isTrue,
        reason: 'Keys.svg white bits are rotated roundrects, not diamonds',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(search.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        leftover.children.any(
          (child) =>
              child.fill.foreground == handle && cubics(child) >= 4,
        ),
        isTrue,
        reason: 'a second save must keep Search handle CubBezTo corners',
      );

      final lens = search.children.where(
        (child) =>
            child.fill.pattern == 1 &&
            child.fill.foreground == VsdxColor.white &&
            child.geometries.any(
              (geometry) => geometry.commands.any((command) => command is EllipseCmd),
            ),
      );
      expect(
        lens,
        isNotEmpty,
        reason: 'Search.svg lens tessellates the radial as FillForegnd '
            'bands plus a white EllipseCmd; FillPattern 40 would 0→1 a '
            'circle that covers the handle',
      );
      final ellipse = lens.first.geometries.first.commands.whereType<EllipseCmd>().first;
      final cx = ellipse.cx;
      final cy = ellipse.cy;
      final rx = (ellipse.aX - cx).abs();
      final ry = (ellipse.bY - cy).abs();
      var outside = false;
      for (final geometry in handleKids.first.geometries) {
        for (final command in geometry.commands) {
          switch (command) {
            case MoveTo(:final x, :final y) || LineTo(:final x, :final y):
              if (rx > 0 &&
                  ry > 0 &&
                  ((x - cx) / rx) * ((x - cx) / rx) +
                          ((y - cy) / ry) * ((y - cy) / ry) >
                      1.05) {
                outside = true;
              }
            default:
              break;
          }
        }
      }
      expect(
        outside,
        isTrue,
        reason: 'Search.svg rotate(-45,cx,cy) must keep the handle outside '
            'the lens; pivoting after map() scale stacked it under the circle',
      );
    },
  );

  test(
    'mxImageShape SVG symbol use stays one disk for LibreOffice',
    () {
      const orange = VsdxColor(0xFFBF6328);

      List<VsdxShape> disks(VsdxShape shape) => shape.children
          .where(
            (child) =>
                child.fill.foreground == orange && child.fill.hasFill,
          )
          .toList();

      bool diskCentered(VsdxShape disk) {
        var minX = double.infinity, maxX = -double.infinity;
        var minY = double.infinity, maxY = -double.infinity;
        void point(double x, double y) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }

        for (final geometry in disk.geometries) {
          for (final command in geometry.commands) {
            switch (command) {
              case EllipseCmd(:final cx, :final cy, :final aX, :final aY,
                    :final bX, :final bY):
                point(cx, cy);
                point(aX, aY);
                point(bX, bY);
              case MoveTo(:final x, :final y):
              case LineTo(:final x, :final y):
                point(x, y);
              case CubBezTo(:final x, :final y):
                point(x, y);
              case RelMoveTo(:final fx, :final fy):
                point(fx * disk.width, fy * disk.height);
              case RelLineTo(:final fx, :final fy):
                point(fx * disk.width, fy * disk.height);
              case RelCubBezTo(:final fx, :final fy):
                point(fx * disk.width, fy * disk.height);
              default:
                break;
            }
          }
        }
        if (!minX.isFinite) return false;
        final midX = (minX + maxX) / 2;
        final midY = (minY + maxY) / 2;
        return midX > 0.4 &&
            midX < 1.1 &&
            midY > 0.4 &&
            midY < 1.1 &&
            minX > -0.05 &&
            maxX < disk.width + 0.05;
      }

      final live = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / IBM / IBM / Social',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Live Collaboration')
          .build(155, 3, 3);
      final liveDisks = disks(live);
      expect(
        liveDisks,
        hasLength(1),
        reason: 'live_collaboration.svg <symbol> must not paint as a second '
            'circle at the viewBox origin; only <use> maps the disk',
      );
      expect(
        diskCentered(liveDisks.first),
        isTrue,
        reason: 'use viewBox must place the orange disk on the badge, not '
            'translate(x,y) without mapping symbol viewBox',
      );

      final sync = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / IBM / IBM / Social',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'File Sync')
          .build(156, 3, 3);
      expect(disks(sync), hasLength(1));
      expect(diskCentered(disks(sync).first), isTrue);

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(live.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        disks(leftover),
        hasLength(1),
        reason: 'a second save must keep a single Live Collaboration disk',
      );
      expect(diskCentered(disks(leftover).first), isTrue);
    },
  );

  test(
    'mxImageShape SVG axial url(#gradient) stays FillPattern 26–30 for LibreOffice',
    () {
      final tunnelPeak = VsdxColor.tryParse('#B9DCFB')!;
      final tunnelEdge = VsdxColor.tryParse('#090A9E')!;

      bool isAxialWash(VsdxFill fill, VsdxColor peak, VsdxColor edge, int pattern) {
        if (!fill.hasFill || fill.pattern != pattern) return false;
        return fill.foreground == peak && fill.background == edge;
      }

      Iterable<VsdxFill> descendantFills(VsdxShape shape) sync* {
        yield shape.fill;
        for (final child in shape.children) {
          yield* descendantFills(child);
        }
      }

      Stencil ad(String name) => dynamic
          .singleWhere(
            (group) =>
                group.name == 'Draw.io JS / ActiveDirectory / Active Directory',
          )
          .stencils
          .singleWhere((entry) => entry.name == name);

      final phone = ad('Cell Phone').build(157, 3, 3);
      expect(
        descendantFills(phone).where((fill) {
          final color = fill.foreground;
          if (color == null ||
              fill.pattern != 1 ||
              fill.gradient != null) {
            return false;
          }
          return color.red > 160 &&
              color.red < 200 &&
              color.green > 200 &&
              color.blue > 240;
        }).length,
        greaterThanOrEqualTo(2),
        reason: 'cell_phone.svg url(#E) 0/#3940b4 .5/#bde1fd 1/#2d31af sits '
            'on a short userSpaceOnUse vector; FillPattern 26 would 0→1 '
            'the XForm. Tessellate the light peak as FillForegnd slabs',
      );

      final tunnel = ad('Tunnel').build(158, 3, 3);
      expect(
        descendantFills(tunnel).any(
          (fill) => isAxialWash(fill, tunnelEdge, tunnelPeak, 30),
        ),
        isTrue,
        reason: 'tunnel.svg capture is fillgradient north #B9DCFB→#090A9E; '
            'FillPattern 30 is ODF linear (draw:angle 0) with FillForegnd '
            'the south stop. A three-stop axial would be FillPattern 29; '
            'do not guess that from north',
      );

      final arc = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / Azure2 / Azure / Other',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Arc Data Services')
          .build(1581, 3, 3);
      final arcPeak = VsdxColor.tryParse('#0078D4')!;
      final arcEdge = VsdxColor.tryParse('#005BA1')!;
      expect(
        descendantFills(arc).any(
          (fill) => isAxialWash(fill, arcPeak, arcEdge, 26),
        ),
        isTrue,
        reason: 'Arc Data Services fillgradient axial-east is FillPattern 26 '
            'that libvisio _fillAndShadowProperties maps to draw:style=axial',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final phoneId = doc.pages.first.nextFreeShapeId();
      var page = doc.pages.first.addShape(ad('Cell Phone').build(phoneId, 3, 3));
      final tunnelId = page.nextFreeShapeId();
      page = page.addShape(ad('Tunnel').build(tunnelId, 3, 3));
      final arcId = page.nextFreeShapeId();
      page = page.addShape(
        dynamic
            .singleWhere(
              (group) => group.name == 'Draw.io JS / Azure2 / Azure / Other',
            )
            .stencils
            .singleWhere((entry) => entry.name == 'Arc Data Services')
            .build(arcId, 3, 3),
      );
      doc = doc.replacePage(0, page);
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first;
      expect(
        descendantFills(leftover.findShapeById(phoneId)!).where((fill) {
          final color = fill.foreground;
          if (color == null ||
              fill.pattern != 1 ||
              fill.gradient != null) {
            return false;
          }
          return color.red > 160 &&
              color.red < 200 &&
              color.green > 200 &&
              color.blue > 240;
        }).length,
        greaterThanOrEqualTo(2),
        reason: 'a second save must keep the Cell Phone light-peak slabs',
      );
      expect(
        descendantFills(leftover.findShapeById(tunnelId)!).any(
          (fill) => isAxialWash(fill, tunnelEdge, tunnelPeak, 30),
        ),
        isTrue,
        reason: 'a second save must keep Tunnel FillPattern 30',
      );
      expect(
        descendantFills(leftover.findShapeById(arcId)!).any(
          (fill) => isAxialWash(fill, arcPeak, arcEdge, 26),
        ),
        isTrue,
        reason: 'a second save must keep Arc Data Services FillPattern 26',
      );
    },
  );

  test(
    'mxImageShape SVG three-stop url(#gradient) bakes FillGradient for LibreOffice',
    () {
      bool isPeachLedBand(VsdxFill fill) {
        final color = fill.foreground;
        if (color == null || fill.pattern != 1 || fill.gradient != null) {
          return false;
        }
        return color.red > 240 &&
            color.green > 120 &&
            color.green < 180 &&
            color.blue > 50 &&
            color.blue < 120;
      }

      Iterable<VsdxFill> descendantFills(VsdxShape shape) sync* {
        yield shape.fill;
        for (final child in shape.children) {
          yield* descendantFills(child);
        }
      }

      final server = dynamic
          .singleWhere(
            (group) =>
                group.name == 'Draw.io JS / ActiveDirectory / Active Directory',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Windows Server (2)')
          .build(159, 3, 3);
      expect(
        descendantFills(server).where(isPeachLedBand).length,
        greaterThanOrEqualTo(2),
        reason: 'windows_server_2.svg url(#D) #f2580a→#fea15f→#a11a00 is a '
            'short LED vector; leftover FillGradient still 0→1s the XForm. '
            'Tessellate the peach mid-stop as FillForegnd slabs',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(server.copyWith(id: id)),
      );
      Iterable<VsdxShape> descendants(VsdxShape shape) sync* {
        yield shape;
        for (final child in shape.children) {
          yield* descendants(child);
        }
      }

      final leftover = parser.parse(
        writer.write(originalBytes: writer.emptyDocument(), edited: doc),
      );
      expect(
        leftover.pages.first.shapes
            .expand(descendants)
            .where(isLibvisioSoftEdgesPlate),
        isEmpty,
        reason: 'LED slabs stay native; leftover must not bake a full-box '
            'three-stop PNG',
      );
      expect(
        leftover.pages.first.shapes
            .expand(descendants)
            .where((shape) => isPeachLedBand(shape.fill))
            .length,
        greaterThanOrEqualTo(2),
        reason: 'a second save must keep the Windows Server LED slabs',
      );
    },
  );

  test(
    'mxImageShape SVG inset url(#gradient) bakes FillGradient for LibreOffice',
    () {
      bool isJiraChevronBand(VsdxFill fill) {
        final color = fill.foreground;
        if (color == null || fill.pattern != 1 || fill.gradient != null) {
          return false;
        }
        return color.red < 50 &&
            color.green > 70 &&
            color.green < 150 &&
            color.blue > 190;
      }

      Iterable<VsdxFill> descendantFills(VsdxShape shape) sync* {
        yield shape.fill;
        for (final child in shape.children) {
          yield* descendantFills(child);
        }
      }

      Iterable<VsdxShape> descendants(VsdxShape shape) sync* {
        yield shape;
        for (final child in shape.children) {
          yield* descendants(child);
        }
      }

      final jira = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / Atlassian / Atlassian',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Jira')
          .build(162, 3, 3);
      expect(
        descendantFills(jira).where(isJiraChevronBand).length,
        greaterThanOrEqualTo(6),
        reason: 'Jira_Logo.svg url(#A) offset 0.18/#0052cc→1/#2684ff sits '
            'on a short userSpaceOnUse vector; leftover FillGradient '
            'still 0→1s the XForm. Tessellate as FillForegnd slabs',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(jira.copyWith(id: id)),
      );
      final leftover = parser.parse(
        writer.write(originalBytes: writer.emptyDocument(), edited: doc),
      );
      expect(
        leftover.pages.first.shapes
            .expand(descendants)
            .where(isLibvisioSoftEdgesPlate),
        isEmpty,
        reason: 'Jira chevron slabs stay native; leftover must not bake a '
            'full-box FillGradient PNG',
      );

      final powerBi = dynamic
          .singleWhere(
            (group) =>
                group.name == 'Draw.io JS / Azure2 / Azure / Analytics',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Power BI Embedded')
          .build(163, 3, 3);
      doc = parser.parse(writer.emptyDocument());
      final powerId = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(powerBi.copyWith(id: powerId)),
      );
      final powerLeftover = parser.parse(
        writer.write(originalBytes: writer.emptyDocument(), edited: doc),
      );
      expect(
        powerLeftover.pages.first.shapes
            .expand(descendants)
            .where(isLibvisioSoftEdgesPlate),
        isEmpty,
        reason: 'Power_BI_Embedded.svg two-stop is ~22° off ODF 135°; '
            'leftover FillGradient still 0→1s the XForm and the SoftEdges '
            'PNG composites onto opaque white over the sibling bars. '
            'Tessellate as FillForegnd slabs',
      );
      expect(
        powerLeftover.pages.first.shapes.expand(descendants).where((shape) {
          final color = shape.fill.foreground;
          if (color == null ||
              shape.fill.pattern != 1 ||
              shape.fill.gradient != null) {
            return false;
          }
          return color.red > 180 &&
              color.green > 100 &&
              color.green < 200 &&
              color.blue < 40;
        }).length,
        greaterThanOrEqualTo(8),
        reason: 'a second save must keep the gold bar slabs',
      );
    },
  );

  test(
    'mxImageShape SVG multi-stop radial url(#gradient) stays native for LibreOffice',
    () {
      bool isAppliedMidBand(VsdxFill fill) {
        final color = fill.foreground;
        if (color == null || fill.pattern != 1 || fill.gradient != null) {
          return false;
        }
        return color.red > 45 &&
            color.red < 120 &&
            color.green > 200 &&
            color.blue > 230;
      }

      bool isInsetRadialBand(VsdxFill fill) {
        final color = fill.foreground;
        if (color == null || fill.pattern != 1 || fill.gradient != null) {
          return false;
        }
        return color.red < 110 &&
            color.green > 110 &&
            color.green < 180 &&
            color.blue > 200;
      }

      Iterable<VsdxFill> descendantFills(VsdxShape shape) sync* {
        yield shape.fill;
        for (final child in shape.children) {
          yield* descendantFills(child);
        }
      }

      Iterable<VsdxShape> descendants(VsdxShape shape) sync* {
        yield shape;
        for (final child in shape.children) {
          yield* descendants(child);
        }
      }

      final applied = dynamic
          .singleWhere(
            (group) => group.name ==
                'Draw.io JS / Azure2 / Azure / AI and Machine Learning',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Applied AI')
          .build(164, 3, 3);
      expect(
        descendantFills(applied).where(isAppliedMidBand).length,
        greaterThanOrEqualTo(4),
        reason: 'Azure_Applied_AI.svg radial #9cebff→#50e6ff→#32bedd must '
            'tessellate as FillForegnd discs; FillPattern 40 drops the '
            'middle stop and leftover SoftEdges PNG is a circle on the '
            'icon box that covers the navy sail',
      );
      expect(
        descendantFills(applied).any(
          (fill) =>
              fill.pattern == 40 &&
              fill.gradient != null &&
              fill.gradient!.stops.length >= 3,
        ),
        isFalse,
        reason: 'the three-stop blob must not leftover FillPattern 40',
      );

      final cosmos = dynamic
          .singleWhere(
            (group) =>
                group.name == 'Draw.io JS / Azure2 / Azure / Databases',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Cosmos DB')
          .build(165, 3, 3);
      expect(
        descendantFills(cosmos).where(isInsetRadialBand).length,
        greaterThanOrEqualTo(6),
        reason: 'Azure_Cosmos_DB.svg radial offset 0.183/#5ea0ef must '
            'tessellate as FillForegnd discs; FillPattern 40 always '
            'interpolates 0→1 and leftover SoftEdges PNG would cover '
            'the cyan decorations',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(applied.copyWith(id: id)),
      );
      final leftover = parser.parse(
        writer.write(originalBytes: writer.emptyDocument(), edited: doc),
      );
      expect(
        leftover.pages.first.shapes
            .expand(descendants)
            .where(isLibvisioSoftEdgesPlate),
        isEmpty,
        reason: 'Applied AI discs stay native; leftover must not bake a '
            'white SoftEdges PNG over the navy sail',
      );
      expect(
        leftover.pages.first.shapes
            .expand(descendants)
            .where((shape) => isAppliedMidBand(shape.fill))
            .length,
        greaterThanOrEqualTo(4),
        reason: 'a second save must keep the Applied AI FillForegnd discs',
      );

      doc = parser.parse(writer.emptyDocument());
      final cosmosId = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(cosmos.copyWith(id: cosmosId)),
      );
      final cosmosLeftover = parser.parse(
        writer.write(originalBytes: writer.emptyDocument(), edited: doc),
      );
      expect(
        cosmosLeftover.pages.first.shapes
            .expand(descendants)
            .where(isLibvisioSoftEdgesPlate),
        isEmpty,
        reason: 'Cosmos inset discs stay native; leftover must not bake a '
            'white SoftEdges PNG over the cyan decorations',
      );
      expect(
        cosmosLeftover.pages.first.shapes
            .expand(descendants)
            .where((shape) => isInsetRadialBand(shape.fill))
            .length,
        greaterThanOrEqualTo(6),
        reason: 'a second save must keep the Cosmos FillForegnd discs',
      );

      final ticks = dynamic
          .singleWhere(
            (group) =>
                group.name == 'Draw.io JS / SAP / SAP / App Dev Automation',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'SAP Task Center')
          .build(166, 3, 3);
      doc = parser.parse(writer.emptyDocument());
      final tickId = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(ticks.copyWith(id: tickId)),
      );
      final tickLeftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(tickId)!;
      expect(
        descendants(tickLeftover).where(
          (shape) =>
              shape.fill.pattern == 40 &&
              shape.fill.foreground == VsdxColor.tryParse('#00BBFF'),
        ).length,
        greaterThanOrEqualTo(4),
        reason: 'Task Center two-stop 0→1 radials stay native FillPattern 40',
      );
    },
  );

  test(
    'mxImageShape SVG elliptical radial url(#gradient) stays native for LibreOffice',
    () {
      Iterable<VsdxFill> descendantFills(VsdxShape shape) sync* {
        yield shape.fill;
        for (final child in shape.children) {
          yield* descendantFills(child);
        }
      }

      Iterable<VsdxShape> descendants(VsdxShape shape) sync* {
        yield shape;
        for (final child in shape.children) {
          yield* descendants(child);
        }
      }

      final navy = VsdxColor.tryParse('#1147E9')!;
      final disc = VsdxColor.tryParse('#1348FF')!;

      final apps = dynamic
          .singleWhere(
            (group) =>
                group.name == 'Draw.io JS / SAP / SAP / App Dev Automation',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'SAP Build Apps')
          .build(167, 3, 3);
      final bandColors = descendantFills(apps)
          .where(
            (fill) =>
                fill.pattern == 1 &&
                fill.gradient == null &&
                fill.foreground != null,
          )
          .map((fill) => fill.foreground!.value & 0x00FFFFFF)
          .toSet();
      expect(
        bandColors.length,
        greaterThanOrEqualTo(8),
        reason: 'SAP_Build_Apps.svg blob E/F gradientTransform ellipses '
            'must tessellate as solid FillForegnd discs; FillPattern 40 '
            'is a circle collectFillAndShadow maps to ODF radial',
      );
      expect(
        bandColors,
        contains(navy.value & 0x00FFFFFF),
        reason: 'the outer band must keep stop-color #1147e9',
      );
      expect(
        descendantFills(apps).any(
          (fill) => fill.pattern == 40 && fill.foreground == disc,
        ),
        isTrue,
        reason: 'near-circular blob D (aspect≈1.04) stays FillPattern 40',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(apps.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        descendants(leftover).where(isLibvisioSoftEdgesPlate),
        isEmpty,
        reason: 'concentric solid discs stay native; leftover must not '
            'bake a circular FillGradient PNG',
      );
      expect(
        descendants(leftover)
            .where((shape) => shape.fill.pattern == 1)
            .length,
        greaterThanOrEqualTo(8),
        reason: 'a second save must keep the tessellated FillForegnd discs',
      );
      expect(
        descendants(leftover).any(
          (shape) =>
              shape.fill.pattern == 40 && shape.fill.foreground == disc,
        ),
        isTrue,
        reason: 'a second save must keep circular blob D as FillPattern 40',
      );
    },
  );

  test(
    'mxImageShape SVG elliptical radial evenodd holes stay native for LibreOffice',
    () {
      Iterable<VsdxShape> descendants(VsdxShape shape) sync* {
        yield shape;
        for (final child in shape.children) {
          yield* descendants(child);
        }
      }

      int moveCount(VsdxShape shape) => shape.geometries
          .expand((geometry) => geometry.commands.whereType<MoveTo>())
          .length;

      final azure = VsdxColor.tryParse('#0078D4')!;
      final tick = VsdxColor.tryParse('#00BBFF')!;
      final donut = VsdxColor.tryParse('#1147E9')!;

      final openai = dynamic
          .singleWhere(
            (group) => group.name ==
                'Draw.io JS / Azure2 / Azure / AI and Machine Learning',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'OpenAI')
          .build(168, 3, 3);
      expect(
        descendants(openai).where((shape) => shape.fill.pattern == 1).length,
        greaterThanOrEqualTo(6),
        reason: 'Azure_OpenAI.svg rotate(45) scale(25,-34) must tessellate '
            'as solid discs; FillPattern 40 is a circle that would fill '
            'the plus cutout',
      );
      expect(
        descendants(openai).any(
          (shape) =>
              shape.fill.pattern == 1 && shape.fill.foreground == azure,
        ),
        isTrue,
        reason: 'the outer band must keep stop-color #0078d4',
      );
      expect(
        descendants(openai).any(
          (shape) => shape.fill.pattern == 1 && moveCount(shape) >= 2,
        ),
        isTrue,
        reason: 'the plus cutout must stay a second MoveTo so collectGeometry '
            'evenodd punches the swirl',
      );

      final ticks = dynamic
          .singleWhere(
            (group) =>
                group.name == 'Draw.io JS / SAP / SAP / App Dev Automation',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'SAP Task Center')
          .build(169, 3, 3);
      expect(
        descendants(ticks).where(
          (shape) =>
              shape.fill.pattern == 40 && shape.fill.foreground == tick,
        ).length,
        greaterThanOrEqualTo(4),
        reason: 'Task Center stroke ticks stay native FillPattern 40',
      );
      expect(
        descendants(ticks).any(
          (shape) =>
              shape.fill.pattern == 1 &&
              shape.fill.foreground == donut &&
              moveCount(shape) >= 2,
        ),
        isTrue,
        reason: 'Task Center donuts must tessellate with an evenodd hole',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(openai.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        descendants(leftover).where(isLibvisioSoftEdgesPlate),
        isEmpty,
        reason: 'evenodd solid discs stay native; leftover must not bake PNG',
      );
      expect(
        descendants(leftover).any(
          (shape) => shape.fill.pattern == 1 && moveCount(shape) >= 2,
        ),
        isTrue,
        reason: 'a second save must keep the plus cutout as evenodd MoveTos',
      );
    },
  );

  test(
    'mxImageShape SVG offset circular radial stays native for LibreOffice',
    () {
      Iterable<VsdxFill> descendantFills(VsdxShape shape) sync* {
        yield shape.fill;
        for (final child in shape.children) {
          yield* descendantFills(child);
        }
      }

      Iterable<VsdxShape> descendants(VsdxShape shape) sync* {
        yield shape;
        for (final child in shape.children) {
          yield* descendants(child);
        }
      }

      bool isCyanBlobBand(VsdxFill fill) {
        final color = fill.foreground;
        if (color == null || fill.pattern != 1 || fill.gradient != null) {
          return false;
        }
        return color.red > 140 &&
            color.red < 210 &&
            color.green > 220 &&
            color.blue > 240;
      }

      bool isGoldKeyBand(VsdxFill fill) {
        final color = fill.foreground;
        if (color == null || fill.pattern != 1 || fill.gradient != null) {
          return false;
        }
        return color.red > 240 &&
            color.green > 140 &&
            color.green < 230 &&
            color.blue < 50;
      }

      final cyan = VsdxColor.tryParse('#C3F1FF')!;
      final gold = VsdxColor.tryParse('#FFD70F')!;
      final disc = VsdxColor.tryParse('#1348FF')!;

      final oscp = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / Azure2 / Azure / Other',
          )
          .stencils
          .singleWhere(
            (entry) => entry.name == 'Open Supply Chain Platform',
          )
          .build(172, 3, 3);
      expect(
        descendantFills(oscp).where(isCyanBlobBand).length,
        greaterThanOrEqualTo(12),
        reason: 'Open_Supply_Chain_Platform.svg r=2.25 corner discs and '
            'the inner r=4.4 wash sit off the viewBox centre; FillPattern '
            '40 interpolates 0→1 from the icon XForm so the highlights '
            'would miss #c3f1ff',
      );
      expect(
        descendantFills(oscp).any(
          (fill) => fill.pattern == 40 && fill.foreground == cyan,
        ),
        isFalse,
        reason: 'offset circular cyan discs must not stay FillPattern 40',
      );
      expect(
        descendantFills(oscp).any(
          (fill) =>
              fill.pattern == 28 &&
              fill.foreground == VsdxColor.tryParse('#773ADC') &&
              fill.background == VsdxColor.tryParse('#A67AF4'),
        ),
        isTrue,
        reason: 'the full-box south linear plate stays FillPattern 28',
      );

      final keys = dynamic
          .singleWhere(
            (group) =>
                group.name == 'Draw.io JS / Azure2 / Azure / Azure Stack',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'User Subscriptions')
          .build(173, 3, 3);
      expect(
        descendantFills(keys).where(isGoldKeyBand).length,
        greaterThanOrEqualTo(6),
        reason: 'User_Subscriptions.svg gold radial (centre ~0.85 of the '
            'viewBox radius from the icon middle) must tessellate as '
            'FillForegnd discs; leftover FillGradient is still a circle '
            'on the XForm',
      );
      expect(
        descendantFills(keys).any(
          (fill) =>
              fill.pattern == 40 &&
              fill.foreground == gold &&
              fill.gradient != null,
        ),
        isFalse,
        reason: 'gold key must not leftover a full-box radial FillGradient',
      );

      final apps = dynamic
          .singleWhere(
            (group) =>
                group.name == 'Draw.io JS / SAP / SAP / App Dev Automation',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'SAP Build Apps')
          .build(174, 3, 3);
      expect(
        descendantFills(apps).any(
          (fill) => fill.pattern == 40 && fill.foreground == disc,
        ),
        isTrue,
        reason: 'near-circular blob D (aspect≈1.04, larger than the box) '
            'stays FillPattern 40',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(oscp.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        descendants(leftover).where(isLibvisioSoftEdgesPlate),
        isEmpty,
        reason: 'offset circular discs stay native; leftover must not bake '
            'a full-box FillGradient PNG',
      );
      expect(
        descendants(leftover)
            .where((shape) => isCyanBlobBand(shape.fill))
            .length,
        greaterThanOrEqualTo(12),
        reason: 'a second save must keep the cyan disc slabs',
      );
    },
  );

  test(
    'mxImageShape SVG stop-opacity ramps stay native for LibreOffice',
    () {
      Iterable<VsdxFill> descendantFills(VsdxShape shape) sync* {
        yield shape.fill;
        for (final child in shape.children) {
          yield* descendantFills(child);
        }
      }

      Iterable<VsdxShape> descendants(VsdxShape shape) sync* {
        yield shape;
        for (final child in shape.children) {
          yield* descendants(child);
        }
      }

      bool hasWhiteTranslucent(VsdxFill fill) =>
          fill.pattern == 1 &&
          fill.foreground == VsdxColor.white &&
          fill.gradient == null &&
          fill.foregroundTransparency > 0.05;

      final translator = dynamic
          .singleWhere(
            (group) => group.name ==
                'Draw.io JS / Azure2 / Azure / AI and Machine Learning',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Translator Text')
          .build(170, 3, 3);
      expect(
        descendantFills(translator).where(hasWhiteTranslucent).length,
        greaterThanOrEqualTo(8),
        reason: 'Translator_Text.svg white→white stop-opacity 0.3 must '
            'tessellate as FillPattern 1 + FillForegndTrans; FillPattern '
            '25–40 drop draw:opacity and leftover PNG is opaque white',
      );
      expect(
        descendantFills(translator).any(
          (fill) =>
              fill.pattern == 28 &&
              fill.foreground == VsdxColor.tryParse('#0078D4') &&
              fill.gradient == null,
        ),
        isTrue,
        reason: 'the opaque south #5ea0ef→#0078d4 plate stays FillPattern 28',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(translator.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        descendants(leftover).where(isLibvisioSoftEdgesPlate),
        isEmpty,
        reason: 'translucent FillForegnd slabs stay native; leftover must '
            'not bake an opaque-white SoftEdges PNG over the azure plate',
      );
      expect(
        descendants(leftover)
            .where((shape) => hasWhiteTranslucent(shape.fill))
            .length,
        greaterThanOrEqualTo(8),
        reason: 'a second save must keep the FillForegndTrans slabs',
      );
    },
  );

  test(
    'mxImageShape SVG far-field stop-opacity visors stay native for LibreOffice',
    () {
      Iterable<VsdxFill> descendantFills(VsdxShape shape) sync* {
        yield shape.fill;
        for (final child in shape.children) {
          yield* descendantFills(child);
        }
      }

      Iterable<VsdxShape> descendants(VsdxShape shape) sync* {
        yield shape;
        for (final child in shape.children) {
          yield* descendants(child);
        }
      }

      bool hasWhiteVisor(VsdxFill fill) =>
          fill.pattern == 1 &&
          fill.foreground == VsdxColor.white &&
          fill.gradient == null &&
          fill.foregroundTransparency > 0.05 &&
          fill.foregroundTransparency < 0.35;

      final sphere = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / Azure2 / Azure / Other',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Sphere')
          .build(179, 3, 3);
      expect(
        descendantFills(sphere).any((fill) => fill.gradient != null),
        isFalse,
        reason: 'Azure_Sphere.svg visor url(#a71b08ef) is white→white '
            'stop-opacity 0.9→0.8 on a userSpaceOnUse vector at y≈-3114; '
            'FillPattern 25–40 drop draw:opacity and leftover FillGradient '
            'bakes an opaque SoftEdges PNG over the cyan body',
      );
      expect(
        descendantFills(sphere).where(hasWhiteVisor).length,
        greaterThanOrEqualTo(1),
        reason: 'the visor must stay FillPattern 1 + FillForegndTrans '
            'so collectFillAndShadow emits draw:opacity',
      );
      expect(
        descendantFills(sphere).any(
          (fill) =>
              fill.pattern == 1 &&
              fill.foreground == VsdxColor.tryParse('#50E6FF') &&
              fill.foregroundTransparency < 0.02,
        ),
        isTrue,
        reason: 'the opaque #50e6ff shield stays FillPattern 1',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(sphere.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        descendants(leftover).where(isLibvisioSoftEdgesPlate),
        isEmpty,
        reason: 'far-field stop-opacity visors stay native; leftover must '
            'not bake an opaque-white SoftEdges PNG over the cyan body',
      );
      expect(
        descendants(leftover).where((shape) => hasWhiteVisor(shape.fill)),
        isNotEmpty,
        reason: 'a second save must keep the FillForegndTrans visor',
      );
    },
  );

  test(
    'mxShape setGradient fillAlpha stays FillForegndTrans for LibreOffice',
    () {
      Iterable<VsdxFill> descendantFills(VsdxShape shape) sync* {
        yield shape.fill;
        for (final child in shape.children) {
          yield* descendantFills(child);
        }
      }

      Iterable<VsdxShape> descendants(VsdxShape shape) sync* {
        yield shape;
        for (final child in shape.children) {
          yield* descendants(child);
        }
      }

      bool isTranslucentBand(VsdxFill fill) =>
          fill.pattern == 1 &&
          fill.gradient == null &&
          fill.foregroundTransparency > 0.05;

      final cylinder = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / Infographic / Infographic',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Cylinder')
          .build(180, 3, 3);
      expect(
        descendantFills(cylinder).any(
          (fill) =>
              fill.pattern >= 25 &&
              fill.pattern <= 40 &&
              fill.foregroundTransparency > 0.02,
        ),
        isFalse,
        reason: 'mxShape Infographic Cylinder setGradient + fillAlpha must '
            'tessellate as FillPattern 1 + FillForegndTrans; FillPattern '
            '25–40 drop draw:opacity so Draw would hide the cyan body',
      );
      expect(
        descendantFills(cylinder).where(isTranslucentBand),
        isNotEmpty,
        reason: 'the highlight wash must stay FillPattern 1 + FillForegndTrans',
      );

      final alert = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / Ios / iOS6',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Alert Box')
          .build(181, 3, 3);
      expect(
        descendantFills(alert).any(
          (fill) =>
              fill.pattern >= 25 &&
              fill.pattern <= 40 &&
              fill.foregroundTransparency > 0.02,
        ),
        isFalse,
        reason: 'iOS6 Alert Box glass setGradient + fillAlpha must tessellate',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(cylinder.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        descendants(leftover).where(isLibvisioSoftEdgesPlate),
        isEmpty,
        reason: 'mxShape translucent gradients stay native; a save '
            'must not bake an opaque SoftEdges PNG over the body',
      );
      expect(
        descendants(leftover).where((shape) => isTranslucentBand(shape.fill)),
        isNotEmpty,
        reason: 'a second save must keep the FillForegndTrans highlight',
      );
    },
  );

  test(
    'mxShape inherit-fill siblings stay unions for LibreOffice',
    () {
      Iterable<VsdxShape> descendants(VsdxShape shape) sync* {
        yield shape;
        for (final child in shape.children) {
          yield* descendants(child);
        }
      }

      int filledGeoms(VsdxShape shape) =>
          shape.geometries.where((g) => !g.noFill && !g.noShow).length;

      final cloud = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / AWS / AWS / General',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Cloud')
          .build(182, 3, 3);
      expect(
        descendants(cloud).where((shape) => filledGeoms(shape) >= 2),
        isEmpty,
        reason: 'AWS Cloud puffs are three inherit-fill contours; '
            'collectGeometry concatenates NoFill=0 into one evenodd path '
            'so overlaps punch. Extra inherit fills must be siblings',
      );
      expect(
        descendants(cloud)
            .where(
              (shape) =>
                  shape.fill.pattern == 1 &&
                  shape.fill.foreground == VsdxColor.tryParse('#E3F2FD') &&
                  filledGeoms(shape) == 1,
            )
            .length,
        greaterThanOrEqualTo(3),
        reason: 'each puff stays a filled sibling Draw paints independently',
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
        descendants(leftover).where((shape) => filledGeoms(shape) >= 2),
        isEmpty,
        reason: 'a second save must keep the puff siblings',
      );
    },
  );

  test(
    'mxImageShape SVG opaque url(#gradient) element opacity stays native for LibreOffice',
    () {
      Iterable<VsdxFill> descendantFills(VsdxShape shape) sync* {
        yield shape.fill;
        for (final child in shape.children) {
          yield* descendantFills(child);
        }
      }

      Iterable<VsdxShape> descendants(VsdxShape shape) sync* {
        yield shape;
        for (final child in shape.children) {
          yield* descendants(child);
        }
      }

      bool isTranslucentWash(VsdxFill fill) {
        final color = fill.foreground;
        if (color == null ||
            fill.pattern != 1 ||
            fill.gradient != null ||
            fill.foregroundTransparency < 0.05 ||
            fill.foregroundTransparency > 0.2) {
          return false;
        }
        return color.red > 180 &&
            color.green > 210 &&
            color.blue > 240;
      }

      final updates = dynamic
          .singleWhere(
            (group) =>
                group.name == 'Draw.io JS / Azure2 / Azure / Intune',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Software Updates')
          .build(178, 3, 3);
      expect(
        descendantFills(updates).where(isTranslucentWash).length,
        greaterThanOrEqualTo(6),
        reason: 'Software_Updates.svg inner rect opacity=0.9 url(#gradient) '
            '#d2ebff→#f0fffd must tessellate as FillPattern 1 + '
            'FillForegndTrans; FillPattern 25–40 drop draw:opacity so the '
            'wash would hide the #0078d4 plate',
      );
      expect(
        descendantFills(updates).any(
          (fill) =>
              fill.pattern == 1 &&
              fill.foreground == VsdxColor.tryParse('#0078D4') &&
              fill.foregroundTransparency < 0.02,
        ),
        isTrue,
        reason: 'the opaque #0078d4 screen stays FillPattern 1',
      );
      expect(
        descendantFills(updates).any(
          (fill) => fill.pattern >= 25 && fill.pattern <= 40,
        ),
        isFalse,
        reason: 'the 0.9 wash must not stay FillPattern 25–40',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(updates.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        descendants(leftover).where(isLibvisioSoftEdgesPlate),
        isEmpty,
        reason: 'translucent wash slabs stay native; leftover must not bake '
            'an opaque SoftEdges PNG over the azure plate',
      );
      expect(
        descendants(leftover)
            .where((shape) => isTranslucentWash(shape.fill))
            .length,
        greaterThanOrEqualTo(6),
        reason: 'a second save must keep the FillForegndTrans wash slabs',
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
        descendantGeometries(weak)
            .where((geometry) => !geometry.noFill && !geometry.noLine)
            .length,
        greaterThanOrEqualTo(2),
        reason: 'Chen weak entity is a double rectangle. A second inherit '
            'fillstroke stays a sibling so collectGeometry evenodd does '
            'not punch the inner box as a hole',
      );
      expect(
        descendantGeometries(weak)
            .expand((geometry) => geometry.commands)
            .whereType<LineTo>()
            .length,
        greaterThanOrEqualTo(8),
      );

      final identifying =
          stencil(group, 'Identifying Relationship').build(301, 3, 3);
      expect(
        descendantGeometries(identifying)
            .where((geometry) => !geometry.noFill && !geometry.noLine)
            .length,
        greaterThanOrEqualTo(2),
        reason: 'Identifying relationship is a double diamond; extra '
            'inherit fill stays a sibling for the same evenodd reason',
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
        descendantGeometries(leftover.findShapeById(weakId)!)
            .where((geometry) => !geometry.noFill && !geometry.noLine)
            .length,
        greaterThanOrEqualTo(2),
        reason: 'a second save must keep both Weak Entity contours',
      );
      expect(
        descendantGeometries(leftover.findShapeById(identifyingId)!)
            .where((geometry) => !geometry.noFill && !geometry.noLine)
            .length,
        greaterThanOrEqualTo(2),
        reason: 'a second save must keep both Identifying diamonds',
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
            .whereType<LineTo>()
            .length,
        greaterThanOrEqualTo(3),
        reason: 'mx default miterLimit 10 leftover bakes the crow\'s foot '
            'as a filled ribbon because _lineProperties never emits '
            'svg:stroke-miterlimit; Draw would otherwise bevel the toes',
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
      expect(
        floating.imgWidthInches! / floating.width,
        closeTo(58.775510204081634 / 60, 0.02),
        reason: 'mxStencil image w on a 60-wide cell is ImgWidth that '
            'collectForeignDataType maps to svg:width',
      );
      expect(
        floating.imgHeightInches! / floating.height,
        closeTo(19.647346938775513 / 60, 0.02),
        reason: 'the PNG is a mid-band icon, not a full XForm stretch',
      );
      expect(
        floating.imgOffsetYInches! / floating.height,
        closeTo((60 - 20.176326530612243 - 19.647346938775513) / 60, 0.03),
        reason: 'image y is stencil-top; ImgOffsetY is Visio Y-up',
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
      expect(
        leftoverShape.imgHeightInches! / leftoverShape.height,
        closeTo(19.647346938775513 / 60, 0.02),
        reason: 'inset ImgHeight is not crop overflow; leftover must keep it',
      );
    },
  );

  test(
    'mxImageShape SVG fill-rule=nonzero compounds stay unions for LibreOffice',
    () {
      Stencil stencil(String groupName, String shapeName) => dynamic
          .singleWhere((group) => group.name == groupName)
          .stencils
          .singleWhere((entry) => entry.name == shapeName);

      Iterable<VsdxShape> descendants(VsdxShape shape) sync* {
        yield shape;
        for (final child in shape.children) {
          yield* descendants(child);
        }
      }

      int moveCount(VsdxShape shape) => shape.geometries
          .expand((geometry) => geometry.commands.whereType<MoveTo>())
          .length;

      List<VsdxShape> leftoverOf(VsdxShape Function(int id) build) {
        final writer = VsdxWriter();
        final parser = DocumentParser();
        var doc = parser.parse(writer.emptyDocument());
        final id = doc.pages.first.nextFreeShapeId();
        doc = doc.replacePage(
          0,
          doc.pages.first.addShape(build(id)),
        );
        return descendants(
          parser
              .parse(
                writer.write(
                  originalBytes: writer.emptyDocument(),
                  edited: doc,
                ),
              )
              .pages
              .first
              .findShapeById(id)!,
        ).toList();
      }

      const vpc = 'Draw.io JS / IBM / IBM / VPC';
      final white = VsdxColor.tryParse('#FFFFFF')!;
      List<VsdxShape> whiteFills(VsdxShape shape) => descendants(shape)
          .where(
            (child) =>
                child.fill.pattern == 1 && child.fill.foreground == white,
          )
          .toList();

      final bridge = stencil(vpc, 'Bridge').build(401, 3, 3);
      final bridgeWhites = whiteFills(bridge);
      expect(
        bridgeWhites.length,
        2,
        reason: 'Bridge.svg fill-rule=nonzero arrows must be sibling fills; '
            'one Geometry would evenodd-punch the overlap',
      );
      expect(
        bridgeWhites.every((shape) => moveCount(shape) == 1),
        isTrue,
        reason: 'each arrow is its own contour',
      );

      final listener =
          stencil(vpc, 'Load Balancer Listener').build(402, 3, 3);
      expect(
        whiteFills(listener).any((shape) => moveCount(shape) >= 2),
        isTrue,
        reason: 'opposite-winding hub rings must stay one Geometry so '
            'collectGeometry evenodd still punches the donut',
      );

      final cloud = stencil(vpc, 'Cloud Services').build(403, 3, 3);
      expect(
        whiteFills(cloud).length,
        greaterThanOrEqualTo(3),
        reason: 'CloudServices.svg gears and play glyph are nonzero unions, '
            'not one evenodd path',
      );

      for (final leftover in [
        leftoverOf((id) => stencil(vpc, 'Bridge').build(id, 3, 3)),
        leftoverOf(
          (id) => stencil(vpc, 'Load Balancer Listener').build(id, 3, 3),
        ),
        leftoverOf((id) => stencil(vpc, 'Cloud Services').build(id, 3, 3)),
      ]) {
        expect(
          leftover.where(isLibvisioSoftEdgesPlate),
          isEmpty,
          reason: 'a second save must keep native FillForegnd, not a PNG',
        );
      }
    },
  );

  test(
    'mxShape sketch=1 fillStyle stays hatch for LibreOffice',
    () {
      Stencil stencil(String groupName, String shapeName) => dynamic
          .singleWhere((group) => group.name == groupName)
          .stencils
          .singleWhere((entry) => entry.name == shapeName);

      Iterable<VsdxShape> descendants(VsdxShape shape) sync* {
        yield shape;
        for (final child in shape.children) {
          yield* descendants(child);
        }
      }

      bool isHatch(VsdxFill fill) =>
          fill.pattern >= 2 && fill.pattern <= 24 && fill.gradient == null;

      const group = 'Draw.io JS / General / misc';
      final ellipse = stencil(group, 'Ellipse Sketch').build(410, 3, 3);
      expect(ellipse.sketchEffect, isTrue);
      expect(ellipse.sketchFillStyle, VsdxSketchFillStyle.dots);
      expect(ellipse.fill.pattern, 1,
          reason: 'capture keeps FillPattern 1; leftover maps dots to hatch');

      final diamond = stencil(group, 'Diamond Sketch').build(411, 3, 3);
      expect(diamond.sketchEffect, isTrue);
      expect(diamond.sketchFillStyle, VsdxSketchFillStyle.crossHatch);

      final rect = stencil(group, 'Rectangle Sketch').build(412, 3, 3);
      expect(rect.sketchEffect, isTrue);
      expect(rect.sketchFillStyle, VsdxSketchFillStyle.auto);
      expect(rect.sketchHachureAngleDegrees, closeTo(45, 0.01));
      expect(rect.sketchHachureGapPx, closeTo(8, 0.01));

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(ellipse.copyWith(id: id)),
      );
      final leftover = parser.parse(
        writer.write(originalBytes: writer.emptyDocument(), edited: doc),
      );
      final leftoverEllipse = leftover.pages.first.findShapeById(id)!;
      expect(
        isHatch(leftoverEllipse.fill),
        isTrue,
        reason: 'leftover must map sketch fillStyle=dots onto FillPattern '
            '2–24 that collectFillAndShadow emits as draw:fill=hatch',
      );
      expect(
        leftoverEllipse.sketchEffect,
        isFalse,
        reason: 'veSketch is frozen to 0 after the hatch bake',
      );
      expect(
        leftover.pages.first.shapes
            .expand(descendants)
            .where(isLibvisioSoftEdgesPlate),
        isEmpty,
        reason: 'sketch hatch stays native; leftover must not bake PNG',
      );
    },
  );

  test(
    'mxImageShape SVG blur-only feGaussianBlur stays FillForegndTrans for LibreOffice',
    () {
      Iterable<VsdxShape> descendants(VsdxShape shape) sync* {
        yield shape;
        for (final child in shape.children) {
          yield* descendants(child);
        }
      }

      bool isBlurHalo(VsdxShape shape) =>
          shape.fill.pattern == 1 &&
          shape.fill.foreground == VsdxColor.black &&
          shape.fill.gradient == null &&
          shape.fill.foregroundTransparency > 0.05;

      final attract = dynamic
          .singleWhere(
            (group) =>
                group.name == 'Draw.io JS / Dynamics365 / Dynamics365 / App',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Talent Attract')
          .build(413, 3, 3);
      expect(
        descendants(attract).where(isBlurHalo).length,
        greaterThanOrEqualTo(5),
        reason: 'TalentAttract.svg feGaussianBlur σ=4 (no feOffset) must '
            'outset as FillPattern 1 + FillForegndTrans rings; '
            'collectFillAndShadow maps those to draw:opacity',
      );
      expect(
        descendants(attract).any(
          (shape) => isBlurHalo(shape) && shape.fill.foregroundTransparency > 0.92,
        ),
        isTrue,
        reason: 'outer blur bands are more transparent than the g opacity=.16 core',
      );

      final copilot = dynamic
          .singleWhere(
            (group) => group.name ==
                'Draw.io JS / Azure2 / Azure / Power Platform',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Copilot Studio')
          .build(414, 3, 3);
      expect(
        descendants(copilot).where(isBlurHalo).length,
        greaterThanOrEqualTo(8),
        reason: 'CopilotStudio.svg two σ=4 black glows must each expand into '
            'FillForegndTrans bands; σ=0.4 stays a single hard fill',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(attract.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        descendants(leftover).where(isLibvisioSoftEdgesPlate),
        isEmpty,
        reason: 'blur halos stay native FillForegndTrans; leftover must not '
            'bake an opaque-white SoftEdges PNG over the yellow disc',
      );
      expect(
        descendants(leftover).where(isBlurHalo).length,
        greaterThanOrEqualTo(5),
        reason: 'a second save must keep the FillForegndTrans blur rings',
      );
    },
  );

  test(
    'mxImageShape SVG default stop-color stays FillForegndTrans for LibreOffice',
    () {
      Iterable<VsdxShape> descendants(VsdxShape shape) sync* {
        yield shape;
        for (final child in shape.children) {
          yield* descendants(child);
        }
      }

      bool isBlackWash(VsdxShape shape) =>
          shape.fill.pattern == 1 &&
          shape.fill.foreground == VsdxColor.black &&
          shape.fill.gradient == null &&
          shape.fill.foregroundTransparency > 0.05;

      final dataverse = dynamic
          .singleWhere(
            (group) => group.name ==
                'Draw.io JS / Azure2 / Azure / Power Platform',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Dataverse')
          .build(415, 3, 3);
      expect(
        descendants(dataverse).where(isBlackWash).length,
        greaterThanOrEqualTo(8),
        reason: 'Dataverse.svg paint2_linear stops omit stop-color (SVG '
            'default black) and only set stop-opacity; those must tessellate '
            'as FillPattern 1 + FillForegndTrans so collectFillAndShadow '
            'emits draw:opacity for the 0.25 highlight stripe',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(dataverse.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        descendants(leftover).where(isLibvisioSoftEdgesPlate),
        isEmpty,
        reason: 'default-black stop-opacity ramps stay native; leftover must '
            'not bake an opaque-white SoftEdges PNG over the green plate',
      );
      expect(
        descendants(leftover).where(isBlackWash).length,
        greaterThanOrEqualTo(8),
        reason: 'a second save must keep the FillForegndTrans highlight wash',
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

  test(
    'mxDoubleEllipse getLabelBounds insets Multivalue Attribute for LibreOffice',
    () {
      Stencil stencil(String groupName, String shapeName) => dynamic
          .singleWhere((group) => group.name == groupName)
          .stencils
          .singleWhere((entry) => entry.name == shapeName);

      VsdxShape? labelOf(VsdxShape shape, String text) {
        if ((shape.text ?? '') == text) return shape;
        for (final child in shape.children) {
          final nested = labelOf(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      const group = 'Draw.io JS / ER / entityRelation';
      final single = stencil(group, 'Attribute').build(433, 3, 3);
      final singleLabel = labelOf(single, 'Attribute')!;
      expect(
        singleLabel.width / single.width,
        closeTo(1.0, 0.02),
        reason: 'mxEllipse has no getLabelBounds; Char stays the cell',
      );

      final multi = stencil(group, 'Multivalue Attribute').build(434, 3, 3);
      final multiLabel = labelOf(multi, 'Attribute')!;
      expect(
        multiLabel.width / multi.width,
        closeTo(94 / 100, 0.02),
        reason: 'mxDoubleEllipse.getLabelBounds STYLE_MARGIN=3 on a 100px '
            'cell is TxtWidth collectTextBlock maps inside the inner ring',
      );
      expect(
        multiLabel.height / multi.height,
        closeTo(34 / 40, 0.02),
        reason: 'the same 3px inset on the 40px height',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(
          stencil(group, 'Multivalue Attribute').build(id, 3, 3),
        ),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      final leftoverLabel = labelOf(leftover, 'Attribute')!;
      expect(
        leftoverLabel.width / leftover.width,
        closeTo(94 / 100, 0.02),
        reason: 'a second save must keep the inset TxtWidth',
      );
      expect(
        leftoverLabel.height / leftover.height,
        closeTo(34 / 40, 0.02),
        reason: 'a second save must keep the inset TxtHeight',
      );
    },
  );

  test(
    'mxStencil labelBounds insets Multi-Document Text for LibreOffice',
    () {
      final multi = migrated
          .singleWhere((group) => group.name == 'Draw.io / Flowchart')
          .stencils
          .singleWhere((entry) => entry.name == 'Multi-Document')
          .build(432, 3, 3);
      final block = multi.richText.textBlock;
      expect(block.widthInches, isNotNull);
      expect(block.heightInches, isNotNull);
      expect(
        block.widthInches! / multi.width,
        closeTo(78 / 88, 0.02),
        reason: 'flowchart.xml labelBounds w=78 on an 88-wide stencil',
      );
      expect(
        block.heightInches! / multi.height,
        closeTo(47 / 60.28, 0.02),
        reason: 'labelBounds h=47 keeps collectTextBlock below the stacked '
            'sheet; full Height would paint over the top document',
      );
      expect(
        block.pinYInches! / multi.height,
        closeTo(1 - (10 + 47 / 2) / 60.28, 0.03),
        reason: 'labelBounds y=10 is stencil-top; TxtPinY is Visio Y-up',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(
          migrated
              .singleWhere((group) => group.name == 'Draw.io / Flowchart')
              .stencils
              .singleWhere((entry) => entry.name == 'Multi-Document')
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
        leftover.richText.textBlock.heightInches! / leftover.height,
        closeTo(47 / 60.28, 0.02),
        reason: 'a second save must keep the inset TxtHeight',
      );
    },
  );

  test(
    'mxAbstractCanvas2D createState fontSize 11 stays Char Size for LibreOffice',
    () {
      VsdxTextRun? runExact(VsdxShape shape, String text) {
        for (final run in shape.richText.runs) {
          if (run.text == text) return run;
        }
        for (final child in shape.children) {
          final nested = runExact(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      // mxStencil.drawNode does not setFontSize from defaultVertex. Omitted
      // <fontsize> uses createState DEFAULT_FONTSIZE 11, not 12.
      final omitted = decodeDrawioMxStencilXml(
        '<shape name="FF" w="100" h="80" strokewidth="inherit">'
        '<foreground>'
        '<rect x="20" y="0" w="60" h="80"/>'
        '<fillstroke/>'
        '<text align="center" str="D" valign="bottom" x="25" y="25"/>'
        '</foreground>'
        '</shape>',
        id: 444,
      );
      const omittedScale = 1.5 / 100;
      expect(
        runExact(omitted, 'D')!.charStyle.fontSizeInches,
        closeTo(11 * omittedScale, 0.0005),
        reason: 'createState fontSize is 11. collectCharIX Size must not use '
            'defaultVertex 12 when the stencil omits <fontsize>',
      );
      expect(
        runExact(omitted, 'D')!.charStyle.fontFamily,
        'Arial',
        reason: 'createState fontFamily is DEFAULT_FONTFAMILY Arial,Helvetica; '
            'collectCharIX Font maps the first face',
      );
      expect(
        runExact(omitted, 'D')!.charStyle.color,
        VsdxColor.black,
        reason: 'createState fontColor is #000000 that collectCharIX maps '
            'to fo:color',
      );

      final flipFlop = migrated
          .singleWhere(
            (group) => group.name == 'Draw.io / Electrical / Logic Gates',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'D Type Flip-Flop')
          .build(445, 3, 3);
      expect(
        runExact(flipFlop, 'D')!.charStyle.fontSizeInches,
        closeTo(11 * omittedScale, 0.0005),
        reason: 'D Type Flip-Flop D/Q glyphs have no <fontsize>',
      );
      expect(runExact(flipFlop, 'D')!.charStyle.fontFamily, 'Arial');
      expect(runExact(flipFlop, 'D')!.charStyle.color, VsdxColor.black);
      expect(
        runExact(flipFlop, 'Q')!.charStyle.fontSizeInches,
        closeTo(11 * omittedScale, 0.0005),
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(flipFlop.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        runExact(leftover, 'D')!.charStyle.fontSizeInches,
        closeTo(11 * omittedScale, 0.0005),
        reason: 'a second save must keep createState 11 as Char.Size that '
            'collectCharIX maps to fo:font-size',
      );
      expect(
        runExact(leftover, 'D')!.charStyle.fontFamily,
        'Arial',
        reason: 'a second save must keep Char.Font Arial',
      );
      expect(
        runExact(leftover, 'D')!.charStyle.color,
        VsdxColor.black,
        reason: 'a second save must keep Char.Color #000000',
      );
    },
  );

  test(
    'vertex-cells bindStyle resets createState before NestedStencil glyphs',
    () {
      VsdxTextRun? runExact(VsdxShape shape, String text) {
        for (final run in shape.richText.runs) {
          if (run.text == text) return run;
        }
        for (final child in shape.children) {
          final nested = runExact(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      // Concatenated vertex-cells XML: previous applyTextStyle then the
      // bindStyle createState emit. Decoder walks one canvas; omitted
      // NestedStencil tags used to keep Helvetica / 12 / italic / red.
      final cells = decodeDrawioMxStencilXml(
        '<shape name="Cells" w="100" h="80" strokewidth="inherit">'
        '<foreground>'
        '<dashed dashed="1"/>'
        '<fontsize size="12"/>'
        '<fontfamily family="Helvetica"/>'
        '<fontstyle style="2"/>'
        '<fontcolor color="#ff0000"/>'
        '<rect x="0" y="0" w="40" h="20"/>'
        '<stroke/>'
        '<text align="center" str="Title" valign="middle" x="20" y="10"/>'
        '<dashed dashed="0"/>'
        '<fontsize size="11"/>'
        '<fontfamily family="Arial"/>'
        '<fontstyle style="0"/>'
        '<fontcolor color="#000000"/>'
        '<text align="center" str="D" valign="bottom" x="25" y="25"/>'
        '</foreground>'
        '</shape>',
        id: 446,
      );
      const scale = 1.5 / 100;
      expect(
        runExact(cells, 'Title')!.charStyle.fontFamily,
        'Helvetica',
      );
      expect(
        runExact(cells, 'Title')!.charStyle.fontSizeInches,
        closeTo(12 * scale, 0.0005),
      );
      expect(runExact(cells, 'Title')!.charStyle.style.italic, isTrue);
      expect(
        runExact(cells, 'Title')!.charStyle.color,
        const VsdxColor(0xFFFF0000),
      );
      expect(
        runExact(cells, 'D')!.charStyle.fontFamily,
        'Arial',
        reason: 'bindStyle createState DEFAULT_FONTFAMILY first face',
      );
      expect(
        runExact(cells, 'D')!.charStyle.fontSizeInches,
        closeTo(11 * scale, 0.0005),
        reason: 'bindStyle createState DEFAULT_FONTSIZE 11',
      );
      expect(
        runExact(cells, 'D')!.charStyle.style.italic,
        isFalse,
        reason: 'bindStyle createState fontStyle 0',
      );
      expect(
        runExact(cells, 'D')!.charStyle.color,
        VsdxColor.black,
        reason: 'bindStyle createState fontColor #000000',
      );

      final jsFlipFlop = dynamic
          .singleWhere(
            (group) =>
                group.name == 'Draw.io JS / Electrical / Electrical / Logic Gates',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'D Type Flip-Flop')
          .build(447, 3, 3);
      expect(
        runExact(jsFlipFlop, 'D')!.charStyle.fontFamily,
        'Arial',
        reason: 'JS NestedStencil D/Q omit fontfamily; bindStyle Arial',
      );
      expect(
        runExact(jsFlipFlop, 'D')!.charStyle.fontSizeInches,
        closeTo(11 * scale, 0.0005),
      );
      expect(runExact(jsFlipFlop, 'D')!.charStyle.color, VsdxColor.black);

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(jsFlipFlop.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(runExact(leftover, 'D')!.charStyle.fontFamily, 'Arial');
      expect(
        runExact(leftover, 'D')!.charStyle.fontSizeInches,
        closeTo(11 * scale, 0.0005),
      );
      expect(runExact(leftover, 'D')!.charStyle.color, VsdxColor.black);
    },
  );

  test(
    'mxStencil roundrect arcsize 0 uses 15 percent rounding for LibreOffice',
    () {
      final rounded = decodeDrawioMxStencilXml(
        '<shape name="Arc0" w="100" h="60" strokewidth="1">'
        '<foreground>'
        '<roundrect x="0" y="0" w="100" h="60" arcsize="0"/>'
        '<fillstroke/>'
        '</foreground>'
        '</shape>',
        id: 440,
      );
      final cmds = descendantGeometries(rounded)
          .expand((geometry) => geometry.commands)
          .toList(growable: false);
      expect(
        cmds.any((command) => command is CubBezTo),
        isTrue,
        reason: 'mxStencil.drawNode Number(arcsize)==0 uses '
            'RECTANGLE_ROUNDING_FACTOR * 100 (15), not a sharp rect. '
            'libvisio collectGeometry keeps those cubics',
      );

      final sharp = decodeDrawioMxStencilXml(
        '<shape name="Sharp" w="100" h="60" strokewidth="1">'
        '<foreground>'
        '<rect x="0" y="0" w="100" h="60"/>'
        '<fillstroke/>'
        '</foreground>'
        '</shape>',
        id: 441,
      );
      expect(
        descendantGeometries(sharp)
            .expand((geometry) => geometry.commands)
            .any((command) => command is CubBezTo),
        isFalse,
        reason: 'canvas roundrect(r=0) is captured as <rect>',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(rounded.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        descendantGeometries(leftover)
            .expand((geometry) => geometry.commands)
            .any((command) => command is CubBezTo || command is RelCubBezTo),
        isTrue,
        reason: 'a second save keeps the 15 percent cubics (RelCubBezTo; '
            'tokens.txt has no CubBezTo)',
      );
    },
  );

  test(
    'mxAbstractCanvas2D createState miterLimit 10 stays on JS canvas fills',
    () {
      bool leakedMiter4(VsdxShape shape) {
        if (shape.line.hasLine &&
            (shape.line.miterLimit - 4).abs() < 1e-6) {
          return true;
        }
        return shape.children.any(leakedMiter4);
      }

      final button = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / Atlassian / Atlassian',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Button (Link)')
          .build(442, 3, 3);
      expect(
        leakedMiter4(button),
        isFalse,
        reason: 'createState miterLimit is 10. restore() must not leak CSS '
            'default 4 onto later fills. leftover would skip the spike '
            'ribbon because ODF default miterlimit is already 4',
      );

      final menu = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / Android / android',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Menu bar')
          .build(443, 3, 3);
      expect(
        descendantGeometries(menu)
            .expand((geometry) => geometry.commands)
            .any((command) => command is CubBezTo || command is RelCubBezTo),
        isFalse,
        reason: 'Android rrect rSize=0 is canvas roundrect(r=0) → <rect>. '
            'drawNode arcsize=0 rounding must not fillet that chrome',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final buttonId = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(button.copyWith(id: buttonId)),
      );
      final menuId = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(menu.copyWith(id: menuId)),
      );
      final leftoverDoc = parser.parse(
        writer.write(originalBytes: writer.emptyDocument(), edited: doc),
      );
      final leftoverButton =
          leftoverDoc.pages.first.findShapeById(buttonId)!;
      final leftoverMenu = leftoverDoc.pages.first.findShapeById(menuId)!;
      expect(
        leakedMiter4(leftoverButton),
        isFalse,
        reason: 'a second save must not reintroduce CSS miter 4',
      );
      expect(
        descendantGeometries(leftoverMenu)
            .expand((geometry) => geometry.commands)
            .any((command) => command is CubBezTo || command is RelCubBezTo),
        isFalse,
        reason: 'a second save must keep Android rSize=0 chrome sharp',
      );
    },
  );

  test(
    'mxText html ul/ol leftover-bakes list markers for LibreOffice',
    () {
      VsdxShape? glyphContaining(VsdxShape shape, String text) {
        if ((shape.text ?? '').contains(text)) return shape;
        for (final child in shape.children) {
          final nested = glyphContaining(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      Stencil stencil(String groupName, String shapeName) => dynamic
          .singleWhere((group) => group.name == groupName)
          .stencils
          .singleWhere((entry) => entry.name == shapeName);

      const group = 'Draw.io JS / General / misc';
      final unordered = stencil(group, 'Unordered List').build(520, 3, 3);
      final disc = glyphContaining(unordered, 'Value 1')!;
      expect(
        disc.richText.runs.any((run) => run.paraStyle.bullet == 1),
        isTrue,
        reason: 'html.spec UA ul disc is collectParaIX Bullet 1 (U+2022)',
      );
      expect(
        disc.richText.runs.any(
          (run) => run.paraStyle.textPosAfterBulletInches > 0.05,
        ),
        isTrue,
        reason: 'UA padding-inline-start 40px is TextPosAfterBullet leftover '
            'hangs as fo:margin-left',
      );

      final ordered = stencil(group, 'Ordered List').build(521, 3, 3);
      final numbered = glyphContaining(ordered, 'Value 1')!;
      expect(
        numbered.text,
        contains('1. '),
        reason: 'html.spec UA ol decimal prefixes Character text; tokens.txt '
            'has no numbered list',
      );
      expect(numbered.text, contains('2. '));
      expect(
        numbered.richText.runs.every((run) => run.paraStyle.bullet == 0),
        isTrue,
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final unorderedId = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(unordered.copyWith(id: unorderedId)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(unorderedId)!;
      final leftoverDisc = glyphContaining(leftover, 'Value 1')!;
      expect(
        leftoverDisc.text,
        contains('\u2022'),
        reason: 'Draw never paints text:bullet-char; leftover bakes U+2022',
      );
      expect(
        leftoverDisc.richText.runs.every((run) => run.paraStyle.bullet == 0),
        isTrue,
        reason: 'Bullet cells drop after the glyph bake so a second save '
            'does not stack another marker',
      );
    },
  );

  test(
    'mxText html table caption and border leftover-bake for LibreOffice',
    () {
      VsdxShape? glyphContaining(VsdxShape shape, String text) {
        if ((shape.text ?? '').contains(text)) return shape;
        for (final child in shape.children) {
          final nested = glyphContaining(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      int linedGeometries(VsdxShape shape) => descendantGeometries(shape)
          .where((geometry) => !geometry.noLine && geometry.commands.isNotEmpty)
          .length;

      Stencil stencil(String groupName, String shapeName) => dynamic
          .singleWhere((group) => group.name == groupName)
          .stencils
          .singleWhere((entry) => entry.name == shapeName);

      final entity = stencil('Draw.io JS / UML / uml', 'Entity').build(
        522,
        3,
        3,
      );
      final header = glyphContaining(entity, 'Tablename')!;
      expect(
        glyphContaining(entity, 'uniqueId')!.id,
        isNot(header.id),
        reason: 'div+table is a header row plus cells, not one Character blob',
      );
      expect(
        glyphContaining(entity, 'PK')!.id,
        isNot(glyphContaining(entity, 'uniqueId')!.id),
        reason: 'td columns stay separate collectXFormData boxes',
      );
      expect(
        header.richText.textBlock.backgroundColor,
        const VsdxColor(0xFFE4E4E4),
        reason: 'CSS background #e4e4e4 is collectTextBlock TextBkgnd',
      );
      expect(
        header.richText.textBlock.verticalAlign,
        VsdxVertAlign.top,
        reason: 'caption <div> keeps mxText verticalAlign=top',
      );
      expect(
        glyphContaining(entity, 'uniqueId')!.richText.textBlock.verticalAlign,
        VsdxVertAlign.middle,
        reason: 'html.spec td vertical-align:middle is collectTextBlock '
            'VerticalAlign 1 (draw:textarea-vertical-align), not the '
            'outer top',
      );

      final htmlTable = stencil(
        'Draw.io JS / General / misc',
        'HTML Table 4',
      ).build(523, 3, 3);
      expect(
        glyphContaining(htmlTable, 'Title')!.id,
        isNot(glyphContaining(htmlTable, 'Section 1.1')!.id),
      );
      expect(
        glyphContaining(htmlTable, 'Title')!.richText.textBlock.verticalAlign,
        VsdxVertAlign.middle,
        reason: 'html.spec th vertical-align:middle; named style text=top '
            'must not leftover-bake VerticalAlign 0',
      );
      expect(
        glyphContaining(htmlTable, 'Section 1.1')!
            .richText
            .textBlock
            .verticalAlign,
        VsdxVertAlign.middle,
      );
      expect(
        linedGeometries(htmlTable),
        greaterThanOrEqualTo(4),
        reason: 'table border="1" leftover-bakes collectLine grid',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      VsdxShape leftoverOf(VsdxShape shape) {
        var doc = parser.parse(writer.emptyDocument());
        final id = doc.pages.first.nextFreeShapeId();
        doc = doc.replacePage(
          0,
          doc.pages.first.addShape(shape.copyWith(id: id)),
        );
        return parser
            .parse(
              writer.write(originalBytes: writer.emptyDocument(), edited: doc),
            )
            .pages
            .first
            .findShapeById(id)!;
      }

      final leftoverEntity = leftoverOf(entity);
      expect(
        glyphContaining(leftoverEntity, 'Tablename')!
            .richText
            .textBlock
            .backgroundColor,
        const VsdxColor(0xFFE4E4E4),
        reason: 'a second save must keep TextBkgnd #e4e4e4',
      );
      expect(
        glyphContaining(leftoverEntity, 'uniqueId')!.id,
        isNot(glyphContaining(leftoverEntity, 'Tablename')!.id),
      );
      expect(
        glyphContaining(leftoverEntity, 'Tablename')!
            .richText
            .textBlock
            .verticalAlign,
        VsdxVertAlign.top,
        reason: 'a second save must keep caption VerticalAlign 0',
      );
      expect(
        glyphContaining(leftoverEntity, 'uniqueId')!
            .richText
            .textBlock
            .verticalAlign,
        VsdxVertAlign.middle,
        reason: 'a second save must keep td VerticalAlign 1',
      );
      final leftoverTable = leftoverOf(htmlTable);
      expect(
        linedGeometries(leftoverTable),
        greaterThanOrEqualTo(4),
        reason: 'a second save must keep the collectLine grid',
      );
      expect(
        glyphContaining(leftoverTable, 'Title')!
            .richText
            .textBlock
            .verticalAlign,
        VsdxVertAlign.middle,
        reason: 'a second save must keep th VerticalAlign 1',
      );
    },
  );

  test(
    'mxCell Graph.replacePlaceholders leftover-bake for LibreOffice',
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

      Stencil stencil(String groupName, String shapeName) => dynamic
          .singleWhere((group) => group.name == groupName)
          .stencils
          .singleWhere((entry) => entry.name == shapeName);

      const writer = VsdxWriter();
      const parser = DocumentParser();
      VsdxShape leftoverOf(VsdxShape shape) {
        var doc = parser.parse(writer.emptyDocument());
        final id = doc.pages.first.nextFreeShapeId();
        doc = doc.replacePage(
          0,
          doc.pages.first.addShape(shape.copyWith(id: id)),
        );
        return parser
            .parse(
              writer.write(originalBytes: writer.emptyDocument(), edited: doc),
            )
            .pages
            .first
            .findShapeById(id)!;
      }

      final variable = stencil(
        'Draw.io JS / General / misc',
        'Variable',
      ).build(524, 3, 3);
      final variableText = allText(variable);
      expect(
        variableText,
        isNot(contains('%name%')),
        reason: 'Graph.setAttributeForCell name=Variable must freeze '
            '%name% before collectText',
      );
      expect(
        variableText,
        contains('Variable Text'),
        reason: 'Sidebar Variable is Graph.replacePlaceholders leftover',
      );

      final timestamp = stencil(
        'Draw.io JS / General / misc',
        'Timestamp',
      ).build(525, 3, 3);
      final timestampText = allText(timestamp);
      expect(
        timestampText,
        isNot(contains('%date{')),
        reason: 'Graph.getGlobalVariable date{mask} leftover-bakes '
            'formatDate into Character',
      );
      expect(
        timestampText,
        matches(
          RegExp(
            r'(Sun|Mon|Tue|Wed|Thu|Fri|Sat) '
            r'(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) '
            r'\d{2} \d{4} \d{2}:\d{2}:\d{2}',
          ),
        ),
        reason: 'ddd mmm dd yyyy HH:MM:ss is Graph.formatDate',
      );

      expect(allText(leftoverOf(variable)), contains('Variable Text'));
      expect(
        allText(leftoverOf(timestamp)),
        isNot(contains('%date{')),
        reason: 'a second save must keep the frozen timestamp',
      );
    },
  );

  test(
    'mxGraph CurvedTextShape leftover-bakes TxtAngle glyphs for LibreOffice',
    () {
      Iterable<VsdxShape> descendants(VsdxShape shape) sync* {
        yield shape;
        for (final child in shape.children) {
          yield* descendants(child);
        }
      }

      final curved = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / General / misc',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Curved Text')
          .build(526, 3, 3);
      final letters = descendants(curved)
          .where((shape) => (shape.text ?? '').trim().isNotEmpty)
          .toList(growable: false);
      expect(
        letters.map((shape) => shape.text).join(),
        'CurvedText',
        reason: 'CurvedTextShape SVG textPath leftover-bakes Char siblings; '
            'RecordingCanvas has no root so official c.text was one blob',
      );
      expect(letters, hasLength(10));
      expect(
        letters.every(
          (shape) => shape.richText.textBlock.angleRad.abs() > 0.05,
        ),
        isTrue,
        reason: 'path tangent is collectTextBlock TxtAngle → librevenge:rotate',
      );
      expect(
        letters.first.richText.textBlock.angleRad,
        greaterThan(0.5),
      );
      expect(
        letters.last.richText.textBlock.angleRad,
        lessThan(-0.5),
      );
      expect(
        letters[4].pinY,
        greaterThan(letters.first.pinY),
        reason: 'the round arc (arcMidY=-25) arches up in Visio Y',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(curved.copyWith(id: id)),
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
        'CurvedText',
        reason: 'a second save must keep the TxtAngle glyphs',
      );
    },
  );

  test(
    'mxText html named entities leftover-bake for LibreOffice',
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

      Stencil stencil(String name) => dynamic
          .singleWhere((group) => group.name == 'Draw.io JS / UML / uml')
          .stencils
          .singleWhere((entry) => entry.name == name);

      final iface = stencil('Interface').build(527, 3, 3);
      final ifaceText = allText(iface);
      expect(
        ifaceText,
        isNot(contains('&laquo;')),
        reason: 'html &laquo; must decode before collectText',
      );
      expect(
        ifaceText,
        contains('«interface»'),
        reason: 'foreignObject UA turns &laquo;/&raquo; into U+00AB/U+00BB',
      );
      expect(
        runContaining(iface, 'Name')!.charStyle.style.bold,
        isTrue,
      );

      final component = stencil('Component').build(528, 3, 3);
      expect(allText(component), contains('«Annotation»'));
      expect(
        runContaining(component, 'Component')!.charStyle.style.bold,
        isTrue,
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      VsdxShape leftoverOf(VsdxShape shape) {
        var doc = parser.parse(writer.emptyDocument());
        final id = doc.pages.first.nextFreeShapeId();
        doc = doc.replacePage(
          0,
          doc.pages.first.addShape(shape.copyWith(id: id)),
        );
        return parser
            .parse(
              writer.write(originalBytes: writer.emptyDocument(), edited: doc),
            )
            .pages
            .first
            .findShapeById(id)!;
      }

      expect(allText(leftoverOf(iface)), contains('«interface»'));
      expect(allText(leftoverOf(component)), contains('«Annotation»'));
    },
  );

  test(
    'mxText html entity stereotypes leftover-bake for LibreOffice',
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

      int countExact(VsdxShape shape, String text) {
        var n = (shape.text ?? '') == text ? 1 : 0;
        for (final child in shape.children) {
          n += countExact(child, text);
        }
        return n;
      }

      Stencil stencil(String groupName, String shapeName) => dynamic
          .singleWhere((group) => group.name == groupName)
          .stencils
          .singleWhere((entry) => entry.name == shapeName);

      final pkg = stencil(
        'Draw.io JS / Sysml / SysML / Model Elements',
        'Package Diagram',
      ).build(529, 3, 3);
      final pkgText = allText(pkg);
      expect(
        pkgText,
        contains('<<import>>'),
        reason: 'html=1 `&lt;&lt;import&gt;&gt;` is foreignObject text, not '
            'an <import> tag leftover as a lone >',
      );
      expect(
        countExact(pkg, '>'),
        0,
        reason: 'insertEdge plus insert() must not paint the same edge '
            'three times (one > per visit)',
      );
      expect(
        countExact(pkg, '<<import>>'),
        1,
        reason: 'Graph model parents the edge once; leftover Character '
            'must keep a single <<import>>',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(pkg.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(allText(leftover), contains('<<import>>'));
      expect(countExact(leftover, '>'), 0);
      expect(countExact(leftover, '<<import>>'), 1);
    },
  );

  test(
    'mxGraph autosizeText leftover-bakes fitted Char Size for LibreOffice',
    () {
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

      Stencil stencil(String name) => dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / General / misc',
          )
          .stencils
          .singleWhere((entry) => entry.name == name);

      // 160×40 cell, catalog scale 1.5/160. Unfitted fontSize=25 is 16.875pt.
      const titleScale = 1.5 / 160;
      final title = stencil('Autosize Title').build(530, 3, 3);
      final titlePt = runContaining(title, 'Autosize Title')!
          .charStyle
          .fontSizeInches *
          72;
      expect(
        titlePt,
        lessThan(25 * titleScale * 72 - 1),
        reason: 'Graph.computeAutosizeTextFontSize must shrink 25px in a '
            '40px-tall cell so leftover Char.Size is not the style token',
      );
      expect(
        titlePt,
        greaterThanOrEqualTo(6 * titleScale * 72 - 0.2),
        reason: 'autosizeText floor is 6px, collectCharIX Size maps to '
            'fo:font-size',
      );

      // 150×150 note, scale 1.5/150. Unfitted fontSize=20 is 14.4pt.
      const noteScale = 1.5 / 150;
      final note = stencil('note').build(531, 3, 3);
      final notePt = runContaining(
            note,
            'The size of the font in this note will change',
          )!
          .charStyle
          .fontSizeInches *
          72;
      expect(
        notePt,
        lessThan(20 * noteScale * 72 - 0.5),
        reason: 'whiteSpace=wrap autosizeText must fit the paragraph in the '
            'note box before collectCharIX',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      VsdxShape leftoverOf(VsdxShape shape) {
        var doc = parser.parse(writer.emptyDocument());
        final id = doc.pages.first.nextFreeShapeId();
        doc = doc.replacePage(
          0,
          doc.pages.first.addShape(shape.copyWith(id: id)),
        );
        return parser
            .parse(
              writer.write(originalBytes: writer.emptyDocument(), edited: doc),
            )
            .pages
            .first
            .findShapeById(id)!;
      }

      expect(
        runContaining(leftoverOf(title), 'Autosize Title')!
                .charStyle
                .fontSizeInches *
            72,
        closeTo(titlePt, 0.05),
        reason: 'a second save must keep the fitted Char.Size',
      );
      expect(
        runContaining(
              leftoverOf(note),
              'The size of the font in this note will change',
            )!
                .charStyle
                .fontSizeInches *
            72,
        closeTo(notePt, 0.05),
      );
    },
  );

  test(
    'mxText html hr empty compartments leftover-bake for LibreOffice',
    () {
      VsdxShape? glyphContaining(VsdxShape shape, String text) {
        for (final child in shape.children) {
          if ((child.text ?? '').contains(text)) return child;
          final nested = glyphContaining(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      List<double> ruleYs(VsdxShape shape) {
        final ys = <double>[];
        for (final geometry in shape.geometries) {
          if (!geometry.noFill || geometry.noLine) continue;
          final cmds = geometry.commands;
          for (var i = 1; i < cmds.length; i++) {
            final prev = cmds[i - 1];
            final cur = cmds[i];
            if (prev is! MoveTo || cur is! LineTo) continue;
            final dx = (cur.x - prev.x).abs();
            final dy = (cur.y - prev.y).abs();
            if (dx > shape.width * 0.3 && dy < 0.05) {
              ys.add((prev.y + cur.y) / 2);
            }
          }
        }
        for (final child in shape.children) {
          ys.addAll(ruleYs(child));
        }
        return ys;
      }

      Stencil stencil(String name) => dynamic
          .singleWhere((group) => group.name == 'Draw.io JS / UML / uml')
          .stencils
          .singleWhere((entry) => entry.name == name);

      // 140×60 cell, catalog scale 1.5/140. Official mxText overflow=fill
      // html=1 is CSS block flow: title content-sized, <hr>, empty 2px.
      final class3 = stencil('Class 3').build(532, 3, 3);
      final title3 = glyphContaining(class3, 'Class')!;
      final rules3 = ruleYs(class3);
      expect(
        title3.height,
        lessThan(class3.height * 0.45),
        reason: 'the empty height:2px compartment after <hr> must eat '
            'leftover overflow=fill space so the title is not stretched',
      );
      expect(
        title3.pinY,
        greaterThan(class3.height * 0.6),
        reason: 'Visio Y-up: content-sized title sits in the top band',
      );
      expect(
        rules3,
        isNotEmpty,
        reason: 'UML Class 3 <hr> is a collectLine sibling Draw paints',
      );
      expect(
        rules3.first,
        greaterThan(class3.height * 0.5),
        reason: 'the rule must sit under the title, not on the cell bottom',
      );

      final class4 = stencil('Class 4').build(533, 3, 3);
      final rules4 = ruleYs(class4)..sort();
      expect(
        rules4.length,
        2,
        reason: 'Class 4 has two <hr> around the 2px spacers',
      );
      expect(
        rules4.first,
        greaterThan(class4.height * 0.35),
        reason: 'both rules stay under the title, not stacked on the bottom',
      );
      expect(
        rules4.last - rules4.first,
        lessThan(class4.height * 0.25),
        reason: 'the 2px spacer between rules is a thin band, not half the cell',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(class3.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      final leftoverTitle = glyphContaining(leftover, 'Class')!;
      expect(
        leftoverTitle.height,
        lessThan(leftover.height * 0.45),
        reason: 'a second save must keep the content-sized title band',
      );
      expect(
        ruleYs(leftover).first,
        greaterThan(leftover.height * 0.5),
        reason: 'a second save must keep the collectLine under the title',
      );
    },
  );

  test(
    'mxSwimlane horizontal=0 title leftover-bakes left Text for LibreOffice',
    () {
      VsdxShape? glyphContaining(VsdxShape shape, String text) {
        for (final child in shape.children) {
          if ((child.text ?? '').contains(text)) return child;
          final nested = glyphContaining(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      final container = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / General / general',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Horizontal Container')
          .build(534, 3, 3);
      final title = glyphContaining(container, 'Horizontal Container')!;
      expect(
        title.width,
        lessThan(container.width * 0.2),
        reason: 'STYLE_HORIZONTAL=0 maps the startSize-tall getLabelBounds '
            'strip onto the left title bar mxSwimlane paints',
      );
      expect(
        title.height,
        closeTo(container.height, 0.02),
        reason: 'the leftover Text child fills the left startSize strip',
      );
      expect(
        title.pinX,
        lessThan(container.width * 0.2),
        reason: 'collectXFormData pins the title in the left bar, not the top',
      );
      expect(
        title.richText.textBlock.textDirection,
        1,
        reason: 'STYLE_HORIZONTAL=0 is TextDirection=1 that a save bakes to '
            'TxtAngle librevenge:rotate paints',
      );

      final vertical = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / General / general',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Container (2)')
          .build(535, 3, 3);
      final verticalTitle = glyphContaining(vertical, 'Vertical Container')!;
      expect(
        verticalTitle.height,
        lessThan(vertical.height * 0.2),
        reason: 'default horizontal swimlane keeps the top startSize band',
      );
      expect(
        verticalTitle.richText.textBlock.textDirection,
        0,
      );

      final lane = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / BPMN / BPMN 2.0  General',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Horizontal Swimlane')
          .build(536, 3, 3);
      final laneTitle = glyphContaining(lane, 'Lane')!;
      expect(
        laneTitle.width,
        lessThan(lane.width * 0.2),
        reason: 'BPMN horizontal=0 lanes share the left title leftover',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(container.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      final leftoverTitle = glyphContaining(leftover, 'Horizontal Container')!;
      expect(
        leftoverTitle.width,
        lessThan(leftover.width * 0.2),
        reason: 'a second save must keep the left title Text box',
      );
      expect(
        leftoverTitle.richText.textBlock.textDirection,
        0,
        reason: 'a save bakes TextDirection so canvas reopen does not '
            'rotate twice',
      );
      expect(
        leftoverTitle.richText.textBlock.angleRad,
        closeTo(-3.141592653589793 / 2, 0.05),
        reason: 'libvisio _flushText paints librevenge:rotate from TxtAngle',
      );
    },
  );

  test(
    'mxGraph getTableLines leftover-bakes table grid for LibreOffice',
    () {
      bool isAxisLine(VsdxShape shape, {required bool vertical}) {
        if ((shape.text ?? '').trim().isNotEmpty) return false;
        if (!shape.line.hasLine || shape.fill.hasFill) return false;
        for (final geometry in shape.geometries) {
          if (!geometry.noFill || geometry.noLine) continue;
          double? minA, maxA, minB, maxB;
          void acc(double along, double across) {
            minA = minA == null ? along : (along < minA! ? along : minA);
            maxA = maxA == null ? along : (along > maxA! ? along : maxA);
            minB = minB == null ? across : (across < minB! ? across : minB);
            maxB = maxB == null ? across : (across > maxB! ? across : maxB);
          }

          for (final cmd in geometry.commands) {
            final x = switch (cmd) {
              MoveTo(:final x) => x,
              LineTo(:final x) => x,
              _ => null,
            };
            final y = switch (cmd) {
              MoveTo(:final y) => y,
              LineTo(:final y) => y,
              _ => null,
            };
            if (x == null || y == null) continue;
            if (vertical) {
              acc(y, x);
            } else {
              acc(x, y);
            }
          }
          if (minA != null &&
              (maxA! - minA!) > shape.width * 0.5 &&
              (maxB! - minB!) < 0.05) {
            return true;
          }
        }
        return false;
      }

      final table = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / General / misc',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Table 1')
          .build(537, 3, 3);
      final rows = table.children.where((c) => isAxisLine(c, vertical: false));
      final cols = table.children.where((c) => isAxisLine(c, vertical: true));
      expect(
        rows.length,
        greaterThanOrEqualTo(2),
        reason: 'Graph.getTableLines rowLines are collectLine siblings '
            'Draw paints as svg:stroke',
      );
      expect(
        cols.length,
        greaterThanOrEqualTo(2),
        reason: 'columnLines must split the 3×3 Table 1, not only the '
            'outer PartialRectangle',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(table.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        leftover.children.where((c) => isAxisLine(c, vertical: false)).length,
        greaterThanOrEqualTo(2),
        reason: 'a second save must keep the row collectLine siblings',
      );
      expect(
        leftover.children.where((c) => isAxisLine(c, vertical: true)).length,
        greaterThanOrEqualTo(2),
        reason: 'a second save must keep the column collectLine siblings',
      );
    },
  );

  test(
    'vertex-cells fillColor leftover-bakes sibling FillForegnd for LibreOffice',
    () {
      Iterable<VsdxShape> descendants(VsdxShape shape) sync* {
        yield shape;
        for (final child in shape.children) {
          yield* descendants(child);
        }
      }

      bool hasFill(VsdxShape shape, String hex) {
        final want = VsdxColor.tryParse(hex);
        return want != null &&
            shape.fill.pattern == 1 &&
            shape.fill.foreground == want;
      }

      final entry = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / Infographic / Infographic',
          )
          .stencils
          .singleWhere((s) => s.name == 'Angled Entry')
          .build(1, 3, 3);
      expect(
        descendants(entry).where((s) => hasFill(s, '#10739E')),
        isNotEmpty,
        reason: 'Sidebar Angled Entry part1 fillColor leftover-bakes '
            'FillForegnd Draw maps to svg:fill',
      );
      expect(
        descendants(entry).where((s) => hasFill(s, '#B1DDF0')),
        isNotEmpty,
        reason: 'part2 fillColor=#B1DDF0 must not collapse to the first '
            'cell inherit fill token',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(entry.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        descendants(leftover).where((s) => hasFill(s, '#10739E')),
        isNotEmpty,
        reason: 'a second save must keep the navy parallelogram FillForegnd',
      );
      expect(
        descendants(leftover).where((s) => hasFill(s, '#B1DDF0')),
        isNotEmpty,
        reason: 'a second save must keep the light-blue parallelogram',
      );
    },
  );

  test(
    'mxShape fillOpacity leftover-bakes FillForegndTrans under the value for LibreOffice',
    () {
      final dial = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / Infographic / Infographic',
          )
          .stencils
          .singleWhere((s) => s.name == 'Circular Dial (2)')
          .build(1, 3, 3);
      expect(
        dial.fill.foregroundTransparency,
        closeTo(0.8, 0.02),
        reason: 'part1 donut fillOpacity=20 leftover-bakes FillForegndTrans '
            'Draw maps to draw:opacity, as the bottom track',
      );
      expect(
        dial.children.where(
          (child) =>
              child.fill.hasFill && child.fill.foregroundTransparency < 0.02,
        ),
        isNotEmpty,
        reason: 'part2 65% arc stays opaque on top of the track',
      );
      expect(
        (dial.text ?? '') +
            dial.children.map((c) => c.text ?? '').join(),
        contains('65%'),
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(dial.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        leftover.fill.foregroundTransparency,
        closeTo(0.8, 0.02),
        reason: 'a second save must keep the donut FillForegndTrans',
      );
      expect(
        leftover.children.where(
          (child) =>
              child.fill.hasFill && child.fill.foregroundTransparency < 0.02,
        ),
        isNotEmpty,
        reason: 'a second save must keep the opaque 65% arc sibling',
      );
    },
  );

  test(
    'mxStackLayout fill leftover-bakes full-width list items for LibreOffice',
    () {
      final list = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / General / general',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'List')
          .build(1, 3, 3);
      final items = list.children
          .where((child) => (child.text ?? '').startsWith('Item'))
          .toList();
      expect(items, hasLength(3));
      for (final item in items) {
        expect(
          item.width,
          closeTo(list.width, 0.05),
          reason: 'Graph.getLayout stackLayout.fill stretches vertical '
              'stack children to the swimlane width; leftover is '
              'collectXFormData svg:width',
        );
      }

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(list.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      final leftoverItems = leftover.children
          .where((child) => (child.text ?? '').startsWith('Item'))
          .toList();
      expect(leftoverItems, hasLength(3));
      for (final item in leftoverItems) {
        expect(
          item.width,
          closeTo(leftover.width, 0.05),
          reason: 'a second save must keep the filled stack XForm width',
        );
      }
    },
  );

  test(
    'mxText html caption padding leftover-bakes LeftMargin for LibreOffice',
    () {
      VsdxShape? glyphContaining(VsdxShape shape, String text) {
        if ((shape.text ?? '').contains(text)) return shape;
        for (final child in shape.children) {
          final nested = glyphContaining(child, text);
          if (nested != null) return nested;
        }
        return null;
      }

      final entity = dynamic
          .singleWhere((group) => group.name == 'Draw.io JS / UML / uml')
          .stencils
          .singleWhere((entry) => entry.name == 'Entity')
          .build(540, 3, 3);
      final header = glyphContaining(entity, 'Tablename')!;
      final pk = glyphContaining(entity, 'PK')!;
      // 180px Entity → 1.5". html.spec 2px is 0.0167in.
      expect(
        header.richText.textBlock.marginLeftInches,
        closeTo(pk.richText.textBlock.marginLeftInches, 0.005),
        reason: 'caption <div> padding:2px is not table cellpadding; '
            'stacking both doubled collectTextBlock LeftMargin that '
            'LibreOffice maps to fo:padding-left',
      );
      expect(
        header.richText.textBlock.marginLeftInches,
        closeTo(1.5 / 180 * 2, 0.003),
        reason: 'CSS padding:2px leftover-bakes LeftMargin only',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(entity.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      final leftoverHeader = glyphContaining(leftover, 'Tablename')!;
      expect(
        leftoverHeader.richText.textBlock.marginLeftInches,
        closeTo(1.5 / 180 * 2, 0.003),
        reason: 'a second save must keep caption LeftMargin at 2px',
      );
    },
  );

  test(
    'mxStencil labelBounds leftover-bakes JS Multi-Document Text for LibreOffice',
    () {
      final multi = dynamic
          .singleWhere(
            (group) => group.name == 'Draw.io JS / Flowchart / flowchart',
          )
          .stencils
          .singleWhere((entry) => entry.name == 'Multi-Document')
          .build(541, 3, 3);
      final block = multi.richText.textBlock;
      expect(block.widthInches, isNotNull);
      expect(block.heightInches, isNotNull);
      expect(
        block.widthInches! / multi.width,
        closeTo(78 / 88, 0.02),
        reason: 'flowchart.xml labelBounds w=78 on NestedStencil; JS capture '
            'must leftover-bake TxtWidth collectTextBlock maps below the '
            'stacked sheets',
      );
      expect(
        block.heightInches! / multi.height,
        closeTo(47 / 60.28, 0.02),
        reason: 'labelBounds h=47 keeps TxtHeight off the top document; '
            'full Height would paint over the stacked sheet in Draw',
      );
      expect(
        block.pinYInches! / multi.height,
        closeTo(1 - (10 + 47 / 2) / 60.28, 0.03),
        reason: 'labelBounds y=10 is stencil-top; TxtPinY is Visio Y-up',
      );

      const writer = VsdxWriter();
      const parser = DocumentParser();
      var doc = parser.parse(writer.emptyDocument());
      final id = doc.pages.first.nextFreeShapeId();
      doc = doc.replacePage(
        0,
        doc.pages.first.addShape(multi.copyWith(id: id)),
      );
      final leftover = parser
          .parse(
            writer.write(originalBytes: writer.emptyDocument(), edited: doc),
          )
          .pages
          .first
          .findShapeById(id)!;
      expect(
        leftover.richText.textBlock.heightInches! / leftover.height,
        closeTo(47 / 60.28, 0.02),
        reason: 'a second save must keep the inset TxtHeight',
      );
    },
  );
}
