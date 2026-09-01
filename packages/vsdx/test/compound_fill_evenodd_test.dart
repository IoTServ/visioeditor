import 'package:test/test.dart';
import 'package:vsdx/stencils.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  test('SVG combines multi NoFill=0 geometries with evenodd', () {
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 4,
      heightInches: 4,
      shapes: [
        VsdxShape(
          id: 1,
          name: 'Frame',
          pinX: 2,
          pinY: 2,
          width: 3,
          height: 3,
          fill: const VsdxFill(
            foreground: VsdxColor(0xFF000000),
            pattern: 1,
          ),
          line: const VsdxLine(pattern: 0),
          geometries: [
            VsdxGeometry(commands: const [
              MoveTo(0, 0),
              LineTo(3, 0),
              LineTo(3, 3),
              LineTo(0, 3),
              LineTo(0, 0),
            ]),
            VsdxGeometry(commands: const [
              MoveTo(0.5, 0.5),
              LineTo(2.5, 0.5),
              LineTo(2.5, 2.5),
              LineTo(0.5, 2.5),
              LineTo(0.5, 0.5),
            ]),
          ],
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    expect(svg.contains('fill-rule="evenodd"'), isTrue);
    // One combined fill path, not two solid fills.
    expect('fill-rule="evenodd"'.allMatches(svg).length, 1);
  });

  test('SVG keeps separate fills when inner geom is NoFill', () {
    final page = VsdxPage(
      id: 0,
      name: 'Page-1',
      widthInches: 4,
      heightInches: 4,
      shapes: [
        VsdxShapeFactory.doubleRectangle(
          id: 1,
          pinX: 2,
          pinY: 2,
          width: 2,
          height: 1.5,
        ),
      ],
    );
    final svg = VsdxToSvgSerializer().serializePage(page);
    // doubleRectangle inner is NoFill — must NOT collapse to evenodd hole.
    expect(svg.contains('fill-rule="evenodd"'), isFalse);
  });

  test('BPMN terminate keeps a filled inner disk for LibreOffice', () {
    final shape = VsdxShapeFactory.bpmnTerminateEvent(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.8,
      height: 1.8,
    );
    expect(shape.geometries.where((g) => !g.noFill && !g.noShow).length, 1,
        reason: 'two filled ellipses evenodd into a ring in Draw');
    final svg = VsdxToSvgSerializer().serializePage(
      VsdxPage(
        id: 0,
        name: 'Page-1',
        widthInches: 4,
        heightInches: 4,
        shapes: [shape],
      ),
    );
    expect(svg.contains('fill-rule="evenodd"'), isFalse);

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.bpmnTerminateEvent(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 1.8,
          height: 1.8,
        ),
      ),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(leftover.geometries.where((g) => !g.noFill && !g.noShow).length, 1,
        reason: 'a second save must not restore two filled ellipses');
  });

  test('floorplan bed keeps a solid mattress for LibreOffice', () {
    final shape = VsdxShapeFactory.floorplanBed(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 2.4,
      height: 1.6,
    );
    expect(shape.geometries.where((g) => !g.noFill && !g.noShow).length, 1,
        reason: 'two filled rectangles evenodd into a pillow hole in Draw');
    final svg = VsdxToSvgSerializer().serializePage(
      VsdxPage(
        id: 0,
        name: 'Page-1',
        widthInches: 4,
        heightInches: 4,
        shapes: [shape],
      ),
    );
    expect(svg.contains('fill-rule="evenodd"'), isFalse);

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.floorplanBed(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 2.4,
          height: 1.6,
        ),
      ),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(leftover.geometries.where((g) => !g.noFill && !g.noShow).length, 1,
        reason: 'a second save must not restore two filled rectangles');
  });

  test('mockup radio keeps a filled centre disc for LibreOffice', () {
    final shape = VsdxShapeFactory.mockupRadio(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.8,
      height: 1.8,
    );
    expect(shape.geometries.where((g) => !g.noFill && !g.noShow).length, 1,
        reason: 'two filled ellipses evenodd into a ring in Draw');
    final svg = VsdxToSvgSerializer().serializePage(
      VsdxPage(
        id: 0,
        name: 'Page-1',
        widthInches: 4,
        heightInches: 4,
        shapes: [shape],
      ),
    );
    expect(svg.contains('fill-rule="evenodd"'), isFalse);

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.mockupRadio(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 1.8,
          height: 1.8,
        ),
      ),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(leftover.geometries.where((g) => !g.noFill && !g.noShow).length, 1,
        reason: 'a second save must not restore two filled ellipses');
  });

  test('mockup progress bar keeps a filled portion for LibreOffice', () {
    final shape = VsdxShapeFactory.mockupProgressBar(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 2.8,
      height: 0.5,
    );
    expect(shape.geometries.where((g) => !g.noFill && !g.noShow).length, 1,
        reason: 'two filled rectangles evenodd invert the track in Draw');
    final svg = VsdxToSvgSerializer().serializePage(
      VsdxPage(
        id: 0,
        name: 'Page-1',
        widthInches: 4,
        heightInches: 4,
        shapes: [shape],
      ),
    );
    expect(svg.contains('fill-rule="evenodd"'), isFalse);

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.mockupProgressBar(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 2.8,
          height: 0.5,
        ),
      ),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(leftover.geometries.where((g) => !g.noFill && !g.noShow).length, 1,
        reason: 'a second save must not restore two filled rectangles');
  });

  test('floorplan plant keeps a solid foliage disc for LibreOffice', () {
    final shape = VsdxShapeFactory.floorplanPlant(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.8,
      height: 1.8,
    );
    expect(shape.geometries.where((g) => !g.noFill && !g.noShow).length, 1,
        reason: 'two filled ellipses evenodd into a ring in Draw');
    final svg = VsdxToSvgSerializer().serializePage(
      VsdxPage(
        id: 0,
        name: 'Page-1',
        widthInches: 4,
        heightInches: 4,
        shapes: [shape],
      ),
    );
    expect(svg.contains('fill-rule="evenodd"'), isFalse);

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.floorplanPlant(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 1.8,
          height: 1.8,
        ),
      ),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(leftover.geometries.where((g) => !g.noFill && !g.noShow).length, 1,
        reason: 'a second save must not restore two filled ellipses');
  });

  test('mockup toggle keeps a solid track for LibreOffice', () {
    final shape = VsdxShapeFactory.mockupToggle(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 2.2,
      height: 1.0,
    );
    expect(shape.geometries.where((g) => !g.noFill && !g.noShow).length, 1,
        reason: 'filled track plus thumb evenodd into a hole in Draw');
    final svg = VsdxToSvgSerializer().serializePage(
      VsdxPage(
        id: 0,
        name: 'Page-1',
        widthInches: 4,
        heightInches: 4,
        shapes: [shape],
      ),
    );
    expect(svg.contains('fill-rule="evenodd"'), isFalse);

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.mockupToggle(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 2.2,
          height: 1.0,
        ),
      ),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(leftover.geometries.where((g) => !g.noFill && !g.noShow).length, 1,
        reason: 'a second save must not restore a filled thumb');
  });

  test('network hub keeps a solid disc for LibreOffice', () {
    final shape = VsdxShapeFactory.networkHub(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.8,
      height: 1.8,
    );
    expect(shape.geometries.where((g) => !g.noFill && !g.noShow).length, 1,
        reason: 'two filled ellipses evenodd into a ring in Draw');
    final svg = VsdxToSvgSerializer().serializePage(
      VsdxPage(
        id: 0,
        name: 'Page-1',
        widthInches: 4,
        heightInches: 4,
        shapes: [shape],
      ),
    );
    expect(svg.contains('fill-rule="evenodd"'), isFalse);

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.networkHub(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 1.8,
          height: 1.8,
        ),
      ),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(leftover.geometries.where((g) => !g.noFill && !g.noShow).length, 1,
        reason: 'a second save must not restore two filled ellipses');
  });

  test('network server keeps a solid chassis for LibreOffice', () {
    final shape = VsdxShapeFactory.networkServer(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.6,
      height: 2.0,
    );
    expect(shape.geometries.where((g) => !g.noFill && !g.noShow).length, 1,
        reason: 'filled LED evenodd into a hole in Draw');
    final svg = VsdxToSvgSerializer().serializePage(
      VsdxPage(
        id: 0,
        name: 'Page-1',
        widthInches: 4,
        heightInches: 4,
        shapes: [shape],
      ),
    );
    expect(svg.contains('fill-rule="evenodd"'), isFalse);

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.networkServer(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 1.6,
          height: 2.0,
        ),
      ),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(leftover.geometries.where((g) => !g.noFill && !g.noShow).length, 1,
        reason: 'a second save must not restore a filled LED');
  });

  test('network camera keeps a solid housing for LibreOffice', () {
    final shape = VsdxShapeFactory.networkSecurityCamera(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 2.0,
      height: 1.6,
    );
    expect(shape.geometries.where((g) => !g.noFill && !g.noShow).length, 1,
        reason: 'filled lens evenodd into a hole in Draw');
    final svg = VsdxToSvgSerializer().serializePage(
      VsdxPage(
        id: 0,
        name: 'Page-1',
        widthInches: 4,
        heightInches: 4,
        shapes: [shape],
      ),
    );
    expect(svg.contains('fill-rule="evenodd"'), isFalse);

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.networkSecurityCamera(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 2.0,
          height: 1.6,
        ),
      ),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(leftover.geometries.where((g) => !g.noFill && !g.noShow).length, 1,
        reason: 'a second save must not restore a filled lens');
  });

  test('EIP tiles keep a single fill for LibreOffice', () {
    int filled(VsdxShape s) =>
        s.geometries.where((g) => !g.noFill && !g.noShow).length;
    expect(
      filled(VsdxShapeFactory.eipAggregator(
        id: 1,
        pinX: 2,
        pinY: 2,
        width: 1.8,
        height: 1.1,
      )),
      1,
      reason: 'message squares evenodd into holes in Draw',
    );
    expect(
      filled(VsdxShapeFactory.eipMessageFilter(
        id: 2,
        pinX: 2,
        pinY: 2,
        width: 1.8,
        height: 1.1,
      )),
      1,
      reason: 'funnel evenodd into a flask hole in Draw',
    );
    expect(
      filled(VsdxShapeFactory.eipWireTap(
        id: 3,
        pinX: 2,
        pinY: 2,
        width: 1.8,
        height: 1.1,
      )),
      1,
    );
    expect(
      filled(VsdxShapeFactory.eipContentBasedRouter(
        id: 4,
        pinX: 2,
        pinY: 2,
        width: 1.8,
        height: 1.1,
      )),
      1,
    );
    expect(
      filled(VsdxShapeFactory.eipMessageChannel(
        id: 5,
        pinX: 2,
        pinY: 2,
        width: 1.8,
        height: 0.45,
      )),
      1,
      reason: 'channel pipe itself stays filled',
    );
    expect(
      filled(VsdxShapeFactory.eipChannelAdapter(
        id: 6,
        pinX: 2,
        pinY: 2,
        width: 0.7,
        height: 1.2,
      )),
      1,
      reason: 'adapter wedge is the outer body',
    );
    final svg = VsdxToSvgSerializer().serializePage(
      VsdxPage(
        id: 0,
        name: 'Page-1',
        widthInches: 4,
        heightInches: 4,
        shapes: [
          VsdxShapeFactory.eipAggregator(
            id: 1,
            pinX: 2,
            pinY: 2,
            width: 1.8,
            height: 1.1,
          ),
        ],
      ),
    );
    expect(svg.contains('fill-rule="evenodd"'), isFalse);

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.eipAggregator(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 1.8,
          height: 1.1,
        ),
      ),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(filled(leftover), 1,
        reason: 'a second save must not restore filled message squares');
    expect(
      filled(VsdxShapeFactory.eipCompetingConsumers(
        id: 7,
        pinX: 2,
        pinY: 2,
        width: 1.8,
        height: 1.1,
      )),
      1,
      reason: 'consumer chevrons evenodd into holes in Draw',
    );
    expect(
      filled(VsdxShapeFactory.eipMessageDispatcher(
        id: 8,
        pinX: 2,
        pinY: 2,
        width: 1.8,
        height: 1.1,
      )),
      1,
      reason: 'dispatcher diamonds evenodd into holes in Draw',
    );
  });

  test('radiation sign keeps a solid centre disc for LibreOffice', () {
    final shape = VsdxShapeFactory.signRadiation(
      id: 1,
      pinX: 2,
      pinY: 2,
      width: 1.8,
      height: 1.8,
    );
    expect(shape.geometries.where((g) => !g.noFill && !g.noShow).length, 1,
        reason: 'two filled ellipses evenodd into a ring in Draw');
    final svg = VsdxToSvgSerializer().serializePage(
      VsdxPage(
        id: 0,
        name: 'Page-1',
        widthInches: 4,
        heightInches: 4,
        shapes: [shape],
      ),
    );
    expect(svg.contains('fill-rule="evenodd"'), isFalse);

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.signRadiation(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 1.8,
          height: 1.8,
        ),
      ),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(leftover.geometries.where((g) => !g.noFill && !g.noShow).length, 1,
        reason: 'a second save must not restore two filled ellipses');
  });

  test('cloud icons stroke nested fills for LibreOffice', () {
    int filled(VsdxShape s) =>
        s.geometries.where((g) => !g.noFill && !g.noShow).length;
    expect(
      filled(VsdxShapeFactory.awsS3(
        id: 1,
        pinX: 2,
        pinY: 2,
        width: 1.8,
        height: 1.4,
      )),
      1,
      reason: 'S3 lid evenodd-punches the bucket in Draw',
    );
    expect(
      filled(VsdxShapeFactory.awsEks(
        id: 2,
        pinX: 2,
        pinY: 2,
        width: 1.8,
        height: 1.8,
      )),
      1,
      reason: 'EKS pod ellipses evenodd-punch the hub in Draw',
    );
    expect(
      filled(VsdxShapeFactory.awsEc2(
        id: 3,
        pinX: 2,
        pinY: 2,
        width: 1.8,
        height: 1.4,
      )),
      1,
      reason: 'isometric cube faces evenodd-punch the back-right join in Draw',
    );
    expect(
      filled(VsdxShapeFactory.azureFunctions(
        id: 4,
        pinX: 2,
        pinY: 2,
        width: 1.8,
        height: 1.4,
      )),
      1,
      reason: 'Functions bolt evenodd-punches the tile in Draw',
    );
    final svg = VsdxToSvgSerializer().serializePage(
      VsdxPage(
        id: 0,
        name: 'Page-1',
        widthInches: 4,
        heightInches: 4,
        shapes: [
          VsdxShapeFactory.awsS3(
            id: 1,
            pinX: 2,
            pinY: 2,
            width: 1.8,
            height: 1.4,
          ),
        ],
      ),
    );
    expect(svg.contains('fill-rule="evenodd"'), isFalse);

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.awsEks(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 1.8,
          height: 1.8,
        ),
      ),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(filled(leftover), 1,
        reason: 'a second save must not restore filled EKS pods');
  });

  test('first-aid and no-entry keep evenodd cut-outs for LibreOffice', () {
    int filled(VsdxShape s) =>
        s.geometries.where((g) => !g.noFill && !g.noShow).length;
    expect(
      filled(VsdxShapeFactory.signFirstAid(
        id: 1,
        pinX: 2,
        pinY: 2,
        width: 1.5,
        height: 1.5,
      )),
      2,
      reason: 'the white cross is an intentional evenodd hole',
    );
    expect(
      filled(VsdxShapeFactory.signNoEntry(
        id: 2,
        pinX: 2,
        pinY: 2,
        width: 1.5,
        height: 1.5,
      )),
      2,
      reason: 'the white bar is an intentional evenodd hole',
    );

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.signFirstAid(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 1.5,
          height: 1.5,
        ),
      ),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(filled(leftover), 2,
        reason: 'a second save must keep the first-aid evenodd hole');
  });

  test('overlapping accessories stroke so Draw does not evenodd-punch', () {
    int filled(VsdxShape s) =>
        s.geometries.where((g) => !g.noFill && !g.noShow).length;
    expect(
      filled(VsdxShapeFactory.umlModule(
        id: 1,
        pinX: 2,
        pinY: 2,
        width: 2.0,
        height: 1.6,
      )),
      3,
      reason: 'UML tabs now abut the body instead of overlapping it',
    );
    expect(
      filled(VsdxShapeFactory.networkPrinter(
        id: 2,
        pinX: 2,
        pinY: 2,
        width: 2.0,
        height: 1.6,
      )),
      2,
      reason: 'printer tray now shares the chassis edge',
    );
    expect(
      filled(VsdxShapeFactory.electricalNorGate(
        id: 3,
        pinX: 2,
        pinY: 2,
        width: 2.0,
        height: 1.4,
      )),
      1,
      reason: 'NOR bubble evenodd-punches the OR shield in Draw',
    );
    expect(
      filled(VsdxShapeFactory.azureKeyVault(
        id: 4,
        pinX: 2,
        pinY: 2,
        width: 1.8,
        height: 1.6,
      )),
      1,
      reason: 'lock shackle evenodd-punches the vault in Draw',
    );
    expect(
      filled(VsdxShapeFactory.ciscoAtmSwitch(
        id: 5,
        pinX: 2,
        pinY: 2,
        width: 1.8,
        height: 1.8,
      )),
      1,
      reason: 'port dots evenodd-punch the diamond in Draw',
    );
    expect(
      filled(VsdxShapeFactory.awsAthena(
        id: 6,
        pinX: 2,
        pinY: 2,
        width: 1.8,
        height: 1.4,
      )),
      1,
      reason: 'magnifier disk evenodd-punches the tablet in Draw',
    );
    expect(
      filled(VsdxShapeFactory.azureBlobStorage(
        id: 7,
        pinX: 2,
        pinY: 2,
        width: 1.8,
        height: 1.6,
      )),
      3,
      reason: 'stacked drums are similar-sized tiles, not nested glyphs',
    );
    expect(
      filled(VsdxShapeFactory.awsEc2(
        id: 8,
        pinX: 2,
        pinY: 2,
        width: 1.8,
        height: 1.4,
      )),
      1,
      reason: 'isometric cube faces evenodd-punch the back-right join in Draw',
    );
    expect(
      filled(VsdxShapeFactory.gcpComputeEngine(
        id: 81,
        pinX: 2,
        pinY: 2,
        width: 1.8,
        height: 1.4,
      )),
      1,
      reason: 'Compute Engine faces evenodd-punch the join; LED stays stroked',
    );
    expect(
      filled(VsdxShapeFactory.alibabaEcs(
        id: 82,
        pinX: 2,
        pinY: 2,
        width: 1.8,
        height: 1.4,
      )),
      1,
      reason: 'Alibaba ECS faces evenodd-punch the join in Draw',
    );
    expect(
      filled(VsdxShapeFactory.ibmPowerVs(
        id: 83,
        pinX: 2,
        pinY: 2,
        width: 1.8,
        height: 1.4,
      )),
      1,
      reason: 'Power VS faces evenodd-punch the join; badge stays stroked',
    );
    expect(
      filled(VsdxShapeFactory.oracleComputeInstance(
        id: 84,
        pinX: 2,
        pinY: 2,
        width: 1.8,
        height: 1.4,
      )),
      1,
      reason: 'Oracle compute faces evenodd-punch the join in Draw',
    );
    expect(
      filled(VsdxShapeFactory.awsCodePipeline(
        id: 9,
        pinX: 2,
        pinY: 2,
        width: 1.8,
        height: 1.4,
      )),
      3,
      reason: 'pipeline chevrons now share an edge instead of overlapping',
    );
    expect(
      filled(VsdxShapeFactory.gcpCloudTasks(
        id: 10,
        pinX: 2,
        pinY: 2,
        width: 1.8,
        height: 1.4,
      )),
      3,
      reason: 'stacked cards now share a gap instead of overlapping',
    );
    expect(
      filled(VsdxShapeFactory.alibabaRam(
        id: 11,
        pinX: 2,
        pinY: 2,
        width: 1.8,
        height: 1.4,
      )),
      2,
      reason: 'key shaft now shares the head edge',
    );
    expect(
      filled(VsdxShapeFactory.awsEcs(
        id: 12,
        pinX: 2,
        pinY: 2,
        width: 1.8,
        height: 1.8,
      )),
      3,
      reason: 'hex pods sit side by side, not nested',
    );

    final svg = VsdxToSvgSerializer().serializePage(
      VsdxPage(
        id: 0,
        name: 'Page-1',
        widthInches: 4,
        heightInches: 4,
        shapes: [
          VsdxShapeFactory.azureKeyVault(
            id: 1,
            pinX: 2,
            pinY: 2,
            width: 1.8,
            height: 1.6,
          ),
        ],
      ),
    );
    expect(svg.contains('fill-rule="evenodd"'), isFalse);

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(
        VsdxShapeFactory.azureKeyVault(
          id: id,
          pinX: 2,
          pinY: 2,
          width: 1.8,
          height: 1.6,
        ),
      ),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(filled(leftover), 1,
        reason: 'a second save must not restore a filled shackle');

    var cubeDoc = parser.parse(writer.emptyDocument());
    final cubeId = cubeDoc.pages.first.nextFreeShapeId();
    cubeDoc = cubeDoc.replacePage(
      0,
      cubeDoc.pages.first.addShape(
        VsdxShapeFactory.awsEc2(
          id: cubeId,
          pinX: 2,
          pinY: 2,
          width: 1.8,
          height: 1.4,
        ),
      ),
    );
    final cubeLeftover = parser
        .parse(writer.write(
            originalBytes: writer.emptyDocument(), edited: cubeDoc))
        .pages
        .first
        .findShapeById(cubeId)!;
    expect(filled(cubeLeftover), 1,
        reason: 'a second save must not restore filled cube faces');
  });

  test('nested fills in a secondary tile stroke for LibreOffice', () {
    int filled(VsdxShape s) =>
        s.geometries.where((g) => !g.noFill && !g.noShow).length;
    VsdxGeometry box(double x0, double y0, double x1, double y1) =>
        VsdxGeometry(commands: <VsdxPathCommand>[
          MoveTo(x0, y0),
          LineTo(x1, y0),
          LineTo(x1, y1),
          LineTo(x0, y1),
          LineTo(x0, y0),
        ]);
    // Two side-by-side bodies, each with a nested square. A largest-only
    // rewrite would stroke the left interior and miss the right one;
    // libvisio still concatenates both interiors into evenodd.
    final shape = VsdxShape(
      id: 1,
      name: 'Pair',
      pinX: 2,
      pinY: 2,
      width: 5,
      height: 2,
      geometries: <VsdxGeometry>[
        box(0, 0, 2, 2),
        box(0.4, 0.4, 1.6, 1.6),
        box(3, 0, 5, 2),
        box(3.4, 0.4, 4.6, 1.6),
      ],
    );
    final baked = strokeNestedFillsForLibvisio(
      shape.geometries,
      width: shape.width,
      height: shape.height,
    );
    expect(
      baked.where((g) => !g.noFill && !g.noShow).length,
      2,
      reason: 'each nested square evenodd-punches its own tile in Draw',
    );

    const writer = VsdxWriter();
    const parser = DocumentParser();
    var doc = parser.parse(writer.emptyDocument());
    final id = doc.pages.first.nextFreeShapeId();
    doc = doc.replacePage(
      0,
      doc.pages.first.addShape(shape.copyWith(id: id)),
    );
    final leftover = parser
        .parse(writer.write(originalBytes: writer.emptyDocument(), edited: doc))
        .pages
        .first
        .findShapeById(id)!;
    expect(filled(leftover), 2,
        reason: 'a second save must not restore the nested squares');
  });

  test(
      'overlapping draw.io fills become children so Draw does not evenodd them',
      () {
    int filledCount(VsdxShape shape) {
      var n = shape.geometries.where((g) => !g.noFill && !g.noShow).length;
      for (final child in shape.children) {
        n += filledCount(child);
      }
      return n;
    }

    bool remainingFillsOverlap(VsdxShape shape) {
      final filled = [
        for (final g in shape.geometries)
          if (!g.noFill && !g.noShow) g,
      ];
      for (var i = 0; i < filled.length; i++) {
        for (var j = i + 1; j < filled.length; j++) {
          final a = geometryLocalBounds(
            filled[i],
            width: shape.width,
            height: shape.height,
          );
          final b = geometryLocalBounds(
            filled[j],
            width: shape.width,
            height: shape.height,
          );
          if (a == null || b == null) continue;
          final x0 = a.minX > b.minX ? a.minX : b.minX;
          final x1 = a.maxX < b.maxX ? a.maxX : b.maxX;
          final y0 = a.minY > b.minY ? a.minY : b.minY;
          final y1 = a.maxY < b.maxY ? a.maxY : b.maxY;
          if (x1 <= x0 + 1e-9 || y1 <= y0 + 1e-9) continue;
          return true;
        }
      }
      return false;
    }

    final stencil = kStencils.firstWhere(
      (s) =>
          s.group == 'Draw.io / AWS / Content Delivery' &&
          s.name == 'CloudFront',
    );
    final shape = stencil.build(10, 3, 3);
    expect(remainingFillsOverlap(shape), isFalse,
        reason: 'libvisio concatenates sibling fills with evenodd');
    expect(shape.children, isNotEmpty);
    expect(filledCount(shape), greaterThan(2));
    bool anyOverlap(VsdxShape node) {
      if (remainingFillsOverlap(node) && !node.keepsLibvisioEvenoddHoles) {
        return true;
      }
      return node.children.any(anyOverlap);
    }

    expect(anyOverlap(shape), isFalse,
        reason: 'XML CloudFront already groups blobs; leftover ribbons must '
            'not re-merge them into one evenodd path');
    expect(
      VsdxShapeFactory.signFirstAid(
        id: 1,
        pinX: 2,
        pinY: 2,
        width: 1.5,
        height: 1.5,
      ).geometries.where((g) => !g.noFill && !g.noShow).length,
      2,
      reason: 'first-aid keeps its evenodd cut-out',
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
    expect(remainingFillsOverlap(leftover), isFalse);
    expect(filledCount(leftover), greaterThan(2),
        reason: 'a second save must keep the CloudFront blobs');
    expect(anyOverlap(leftover), isFalse,
        reason: 'leftover must not concatenate CloudFront blobs into evenodd');
  });
}
