// Generates original starter .vsdx templates for the empty-state picker.
//
// Content is authored from scratch with package:vsdx (generic diagram types
// only — not derived from third-party template packs).
//
// Run from the project root:
//   dart run tool/gen_example_templates.dart
//
// Output: assets/examples/*.vsdx
import 'dart:io';
import 'dart:typed_data';

import 'package:vsdx/vsdx.dart';

const String kOutDir = 'assets/examples';

/// Landscape letter page (Visio inches, Y-up).
const double kPageW = 11.0;
const double kPageH = 8.5;

final _writer = const VsdxWriter();
final _parser = DocumentParser();

void main() {
  Directory(kOutDir).createSync(recursive: true);
  final built = <String, Uint8List>{
    'Process Flow.vsdx': _processFlow(),
    'Org Chart.vsdx': _orgChart(),
    'Project Roadmap.vsdx': _projectRoadmap(),
    'SWOT Matrix.vsdx': _swotMatrix(),
    'System Architecture.vsdx': _systemArchitecture(),
    'Mind Map.vsdx': _mindMap(),
    'Timeline.vsdx': _timeline(),
    'Kanban Board.vsdx': _kanbanBoard(),
    'Fishbone.vsdx': _fishbone(),
    'Cycle Process.vsdx': _cycleProcess(),
    'Venn Diagram.vsdx': _vennDiagram(),
    'Sales Funnel.vsdx': _salesFunnel(),
    'User Journey.vsdx': _userJourney(),
    'Network Topology.vsdx': _networkTopology(),
    'Meeting Agenda.vsdx': _meetingAgenda(),
    'OKR Cascade.vsdx': _okrCascade(),
    // Wave 2 — richer catalog
    'Swimlane Process.vsdx': _swimlaneProcess(),
    'Decision Tree.vsdx': _decisionTree(),
    'Value Stream.vsdx': _valueStream(),
    'RACI Matrix.vsdx': _raciMatrix(),
    'Capability Pyramid.vsdx': _capabilityPyramid(),
    'SIPOC.vsdx': _sipoc(),
    'Eisenhower Matrix.vsdx': _eisenhowerMatrix(),
    'PESTLE.vsdx': _pestle(),
    'Business Model Canvas.vsdx': _businessModelCanvas(),
    'Balanced Scorecard.vsdx': _balancedScorecard(),
    'Stakeholder Map.vsdx': _stakeholderMap(),
    'Porter Five Forces.vsdx': _porterFiveForces(),
    'Wireflow.vsdx': _wireflow(),
    'MoSCoW Priorities.vsdx': _moscowPriorities(),
    'Persona Map.vsdx': _personaMap(),
    'Lesson Plan.vsdx': _lessonPlan(),
    'Concept Map.vsdx': _conceptMap(),
    'Cloud Architecture.vsdx': _cloudArchitecture(),
    'Data Model.vsdx': _dataModel(),
    'CI CD Pipeline.vsdx': _ciCdPipeline(),
  };
  for (final e in built.entries) {
    final path = '$kOutDir/${e.key}';
    File(path).writeAsBytesSync(e.value);
    stdout.writeln('wrote $path (${e.value.length} bytes)');
  }
}

// --- palette (original, not from any commercial pack) ----------------------

const _ink = VsdxColor(0xFF1F2937);
const _line = VsdxLine(color: _ink, weightInches: 0.012);
const _arrow = VsdxLine(color: _ink, weightInches: 0.012, endArrow: 4);

VsdxFill _fill(int argb) => VsdxFill(foreground: VsdxColor(argb));

VsdxCharStyle _labelStyle({double pt = 11, bool bold = false}) => VsdxCharStyle(
      fontSizeInches: pt / 72.0,
      color: _ink,
      style: bold ? VsdxFontStyle.boldStyle : VsdxFontStyle.regular,
    );

VsdxShape _withLabel(VsdxShape s, String text, {double pt = 11, bool bold = false}) {
  final style = _labelStyle(pt: pt, bold: bold);
  return s.copyWith(
    text: text,
    richText: VsdxRichText(runs: <VsdxTextRun>[
      VsdxTextRun(text: text, charStyle: style),
    ]),
  );
}

VsdxShape _box({
  required int id,
  required double cx,
  required double cy,
  required double w,
  required double h,
  required int fillArgb,
  required String label,
  bool rounded = true,
  double pt = 11,
  bool bold = false,
}) {
  final base = rounded
      ? VsdxShapeFactory.roundedRectangle(
          id: id,
          pinX: cx,
          pinY: cy,
          width: w,
          height: h,
          fill: _fill(fillArgb),
          line: _line,
        )
      : VsdxShapeFactory.rectangle(
          id: id,
          pinX: cx,
          pinY: cy,
          width: w,
          height: h,
          fill: _fill(fillArgb),
          line: _line,
        );
  return _withLabel(base, label, pt: pt, bold: bold);
}

VsdxShape _diamond({
  required int id,
  required double cx,
  required double cy,
  required double w,
  required double h,
  required int fillArgb,
  required String label,
}) {
  const unit = <Offset2D>[
    Offset2D(0.5, 1),
    Offset2D(1, 0.5),
    Offset2D(0.5, 0),
    Offset2D(0, 0.5),
  ];
  return _withLabel(
    VsdxShapeFactory.polygon(
      id: id,
      pinX: cx,
      pinY: cy,
      width: w,
      height: h,
      unit: unit,
      fill: _fill(fillArgb),
      line: _line,
    ),
    label,
  );
}

VsdxShape _ellipse({
  required int id,
  required double cx,
  required double cy,
  required double w,
  required double h,
  required int fillArgb,
  required String label,
  double pt = 11,
  bool bold = false,
}) {
  return _withLabel(
    VsdxShapeFactory.ellipse(
      id: id,
      pinX: cx,
      pinY: cy,
      width: w,
      height: h,
      fill: _fill(fillArgb),
      line: _line,
    ),
    label,
    pt: pt,
    bold: bold,
  );
}

VsdxShape _title(int id, double cx, double cy, String text) {
  return _withLabel(
    VsdxShapeFactory.textBox(
      id: id,
      pinX: cx,
      pinY: cy,
      width: 6.5,
      height: 0.45,
      text: text,
    ),
    text,
    pt: 18,
    bold: true,
  );
}

({VsdxShape connector, List<VsdxConnect> connects}) _link(
  int id,
  VsdxShape a,
  VsdxShape b,
) {
  final connector = VsdxShapeFactory.line(
    id: id,
    ax: a.pinX,
    ay: a.pinY,
    bx: b.pinX,
    by: b.pinY,
    line: _arrow,
  ).copyWith(
    formulas: <String, String>{
      'BegTrigger': '_XFTRIGGER(Sheet.${a.id}!EventXFMod)',
      'EndTrigger': '_XFTRIGGER(Sheet.${b.id}!EventXFMod)',
      'PinX': '(BeginX+EndX)*0.5',
      'PinY': '(BeginY+EndY)*0.5',
      'Width': 'EndX-BeginX',
      'Height': 'EndY-BeginY',
      'LocPinX': '(EndX-BeginX)/2',
      'LocPinY': '(EndY-BeginY)/2',
    },
    connectorProps: const VsdxConnectorProps(
      glueType: 2,
      conFixedCode: 3,
      dynFeedback: 2,
      noLiveDynamics: true,
      conLineRouteExt: 1,
      shapeRouteStyle: 16,
      begTrigger: '2',
      endTrigger: '2',
    ),
  );
  final connects = <VsdxConnect>[
    VsdxConnect(
      fromSheetId: id,
      fromCell: 'BeginX',
      fromPart: 9,
      toSheetId: a.id,
      toCell: 'PinX',
      toPart: 3,
    ),
    VsdxConnect(
      fromSheetId: id,
      fromCell: 'EndX',
      fromPart: 12,
      toSheetId: b.id,
      toCell: 'PinX',
      toPart: 3,
    ),
  ];
  return (connector: connector, connects: connects);
}

Uint8List _write(String pageName, List<VsdxShape> shapes, List<VsdxConnect> connects) {
  final blank = _writer.emptyDocument(
    widthInches: kPageW,
    heightInches: kPageH,
  );
  var doc = _parser.parse(blank);
  // Glue rows alone keep Begin/End on pins; reroute snaps each end to the
  // target outline aimed at the opposite shape (same as the editor).
  final page = doc.pages.first
      .copyWith(
        name: pageName,
        shapes: shapes,
        connects: connects,
        pageSheet: doc.pages.first.pageSheet.copyWith(printPageOrientation: 2),
      )
      .rerouteConnectors();
  doc = doc
      .replacePage(0, page)
      .copyWith(title: pageName, creator: 'Editor for Visio Diagrams');
  return _writer.write(originalBytes: blank, edited: doc);
}

// --- templates -------------------------------------------------------------

Uint8List _processFlow() {
  // Generic intake → triage → decide → ship flow (original copy).
  final start = _ellipse(
    id: 1,
    cx: 1.4,
    cy: 4.4,
    w: 1.3,
    h: 0.85,
    fillArgb: 0xFFBBF7D0,
    label: 'Start',
    bold: true,
  );
  final intake = _box(
    id: 2,
    cx: 3.5,
    cy: 4.4,
    w: 1.7,
    h: 0.95,
    fillArgb: 0xFFBFDBFE,
    label: 'Capture\nrequest',
  );
  final decide = _diamond(
    id: 3,
    cx: 5.9,
    cy: 4.4,
    w: 1.7,
    h: 1.3,
    fillArgb: 0xFFFDE68A,
    label: 'Ready?',
  );
  final refine = _box(
    id: 4,
    cx: 5.9,
    cy: 2.2,
    w: 1.7,
    h: 0.95,
    fillArgb: 0xFFFED7AA,
    label: 'Clarify\ndetails',
  );
  final build = _box(
    id: 5,
    cx: 8.2,
    cy: 4.4,
    w: 1.7,
    h: 0.95,
    fillArgb: 0xFFBFDBFE,
    label: 'Build &\nreview',
  );
  final done = _ellipse(
    id: 6,
    cx: 10.1,
    cy: 4.4,
    w: 1.3,
    h: 0.85,
    fillArgb: 0xFFBBF7D0,
    label: 'Done',
    bold: true,
  );
  final title = _title(7, 5.5, 7.6, 'Process flow');
  final hint = _withLabel(
    VsdxShapeFactory.textBox(
      id: 8,
      pinX: 5.5,
      pinY: 7.1,
      width: 7,
      height: 0.35,
      text: 'Edit labels and reconnect steps to fit your team.',
    ),
    'Edit labels and reconnect steps to fit your team.',
    pt: 10,
  );

  final links = <({VsdxShape connector, List<VsdxConnect> connects})>[
    _link(20, start, intake),
    _link(21, intake, decide),
    _link(22, decide, refine),
    _link(23, refine, decide),
    _link(24, decide, build),
    _link(25, build, done),
  ];
  return _write(
    'Process Flow',
    <VsdxShape>[
      title,
      hint,
      start,
      intake,
      decide,
      refine,
      build,
      done,
      for (final l in links) l.connector,
    ],
    <VsdxConnect>[for (final l in links) ...l.connects],
  );
}

Uint8List _orgChart() {
  final title = _title(1, 5.5, 7.7, 'Organisation chart');
  final ceo = _box(
    id: 2,
    cx: 5.5,
    cy: 6.3,
    w: 2.0,
    h: 0.85,
    fillArgb: 0xFF93C5FD,
    label: 'Lead',
    bold: true,
  );
  final eng = _box(
    id: 3,
    cx: 2.4,
    cy: 4.4,
    w: 1.9,
    h: 0.85,
    fillArgb: 0xFFBFDBFE,
    label: 'Engineering',
  );
  final design = _box(
    id: 4,
    cx: 5.5,
    cy: 4.4,
    w: 1.9,
    h: 0.85,
    fillArgb: 0xFFBFDBFE,
    label: 'Design',
  );
  final ops = _box(
    id: 5,
    cx: 8.6,
    cy: 4.4,
    w: 1.9,
    h: 0.85,
    fillArgb: 0xFFBFDBFE,
    label: 'Operations',
  );
  final e1 = _box(
    id: 6,
    cx: 1.5,
    cy: 2.5,
    w: 1.5,
    h: 0.75,
    fillArgb: 0xFFE0E7FF,
    label: 'Dev A',
  );
  final e2 = _box(
    id: 7,
    cx: 3.3,
    cy: 2.5,
    w: 1.5,
    h: 0.75,
    fillArgb: 0xFFE0E7FF,
    label: 'Dev B',
  );
  final d1 = _box(
    id: 8,
    cx: 5.5,
    cy: 2.5,
    w: 1.5,
    h: 0.75,
    fillArgb: 0xFFE0E7FF,
    label: 'Designer',
  );
  final o1 = _box(
    id: 9,
    cx: 8.6,
    cy: 2.5,
    w: 1.5,
    h: 0.75,
    fillArgb: 0xFFE0E7FF,
    label: 'Support',
  );

  final links = <({VsdxShape connector, List<VsdxConnect> connects})>[
    _link(20, ceo, eng),
    _link(21, ceo, design),
    _link(22, ceo, ops),
    _link(23, eng, e1),
    _link(24, eng, e2),
    _link(25, design, d1),
    _link(26, ops, o1),
  ];
  return _write(
    'Org Chart',
    <VsdxShape>[
      title,
      ceo,
      eng,
      design,
      ops,
      e1,
      e2,
      d1,
      o1,
      for (final l in links) l.connector,
    ],
    <VsdxConnect>[for (final l in links) ...l.connects],
  );
}

Uint8List _projectRoadmap() {
  final title = _title(1, 5.5, 7.7, 'Project roadmap');
  final phases = <(String, int, double)>[
    ('Discover', 0xFFBFDBFE, 2.0),
    ('Design', 0xFFC4B5FD, 4.5),
    ('Build', 0xFFFDE68A, 7.0),
    ('Launch', 0xFFBBF7D0, 9.5),
  ];
  final shapes = <VsdxShape>[title];
  final connects = <VsdxConnect>[];
  VsdxShape? prev;
  var id = 2;
  for (final (name, color, x) in phases) {
    final phase = _box(
      id: id++,
      cx: x,
      cy: 5.2,
      w: 2.0,
      h: 1.1,
      fillArgb: color,
      label: name,
      bold: true,
      pt: 13,
    );
    shapes.add(phase);
    final note = _box(
      id: id++,
      cx: x,
      cy: 3.3,
      w: 2.0,
      h: 1.4,
      fillArgb: 0xFFF8FAFC,
      label: 'Goals\n• …\n• …',
      rounded: false,
      pt: 10,
    );
    shapes.add(note);
    if (prev != null) {
      final link = _link(id++, prev, phase);
      shapes.add(link.connector);
      connects.addAll(link.connects);
    }
    prev = phase;
  }
  shapes.add(_withLabel(
    VsdxShapeFactory.textBox(
      id: id,
      pinX: 5.5,
      pinY: 1.4,
      width: 8,
      height: 0.4,
      text: 'Rename phases and fill in goals for your next release.',
    ),
    'Rename phases and fill in goals for your next release.',
    pt: 10,
  ));
  return _write('Project Roadmap', shapes, connects);
}

Uint8List _swotMatrix() {
  final title = _title(1, 5.5, 7.8, 'SWOT matrix');
  final cells = <(String, int, double, double)>[
    ('Strengths\n\n• …', 0xFFBBF7D0, 3.2, 5.3),
    ('Weaknesses\n\n• …', 0xFFFECACA, 7.8, 5.3),
    ('Opportunities\n\n• …', 0xFFBFDBFE, 3.2, 2.5),
    ('Threats\n\n• …', 0xFFFDE68A, 7.8, 2.5),
  ];
  final shapes = <VsdxShape>[
    title,
    _withLabel(
      VsdxShapeFactory.textBox(
        id: 2,
        pinX: 5.5,
        pinY: 7.2,
        width: 7,
        height: 0.35,
        text: 'Internal ↑  ·  External ↓   — replace bullets with your notes.',
      ),
      'Internal ↑  ·  External ↓   — replace bullets with your notes.',
      pt: 10,
    ),
  ];
  var id = 3;
  for (final (label, color, x, y) in cells) {
    shapes.add(_box(
      id: id++,
      cx: x,
      cy: y,
      w: 3.8,
      h: 2.2,
      fillArgb: color,
      label: label,
      pt: 12,
      bold: true,
    ));
  }
  return _write('SWOT Matrix', shapes, const <VsdxConnect>[]);
}

Uint8List _systemArchitecture() {
  final title = _title(1, 5.5, 7.7, 'System overview');
  final client = _box(
    id: 2,
    cx: 2.0,
    cy: 4.6,
    w: 1.8,
    h: 1.0,
    fillArgb: 0xFFBFDBFE,
    label: 'Clients',
    bold: true,
  );
  final gateway = _box(
    id: 3,
    cx: 4.5,
    cy: 4.6,
    w: 1.9,
    h: 1.0,
    fillArgb: 0xFFC4B5FD,
    label: 'API\ngateway',
  );
  final service = _box(
    id: 4,
    cx: 7.0,
    cy: 5.6,
    w: 1.9,
    h: 1.0,
    fillArgb: 0xFFFDE68A,
    label: 'App\nservice',
  );
  final worker = _box(
    id: 5,
    cx: 7.0,
    cy: 3.6,
    w: 1.9,
    h: 1.0,
    fillArgb: 0xFFFED7AA,
    label: 'Worker',
  );
  final db = _withLabel(
    VsdxShapeFactory.cylinder(
      id: 6,
      pinX: 9.5,
      pinY: 5.6,
      width: 1.5,
      height: 1.2,
      fill: _fill(0xFFBBF7D0),
      line: _line,
    ),
    'Database',
    bold: true,
  );
  final queue = _box(
    id: 7,
    cx: 9.5,
    cy: 3.6,
    w: 1.6,
    h: 0.9,
    fillArgb: 0xFFE0E7FF,
    label: 'Queue',
  );
  final links = <({VsdxShape connector, List<VsdxConnect> connects})>[
    _link(20, client, gateway),
    _link(21, gateway, service),
    _link(22, gateway, worker),
    _link(23, service, db),
    _link(24, worker, queue),
    _link(25, worker, db),
  ];
  return _write(
    'System Architecture',
    <VsdxShape>[
      title,
      client,
      gateway,
      service,
      worker,
      db,
      queue,
      for (final l in links) l.connector,
    ],
    <VsdxConnect>[for (final l in links) ...l.connects],
  );
}

Uint8List _mindMap() {
  final title = _title(1, 5.5, 7.7, 'Mind map');
  final hub = _ellipse(
    id: 2,
    cx: 5.5,
    cy: 4.4,
    w: 2.2,
    h: 1.2,
    fillArgb: 0xFF93C5FD,
    label: 'Idea',
    bold: true,
    pt: 14,
  );
  final branches = <(String, int, double, double)>[
    ('Goals', 0xFFBBF7D0, 2.0, 6.2),
    ('Risks', 0xFFFECACA, 9.0, 6.2),
    ('People', 0xFFFDE68A, 2.0, 2.6),
    ('Next\nsteps', 0xFFC4B5FD, 9.0, 2.6),
    ('Insights', 0xFFFED7AA, 5.5, 1.6),
  ];
  final shapes = <VsdxShape>[title, hub];
  final connects = <VsdxConnect>[];
  var id = 3;
  for (final (label, color, x, y) in branches) {
    final node = _box(
      id: id++,
      cx: x,
      cy: y,
      w: 1.7,
      h: 0.9,
      fillArgb: color,
      label: label,
    );
    shapes.add(node);
    final link = _link(id++, hub, node);
    shapes.add(link.connector);
    connects.addAll(link.connects);
  }
  return _write('Mind Map', shapes, connects);
}

Uint8List _timeline() {
  final title = _title(1, 5.5, 7.7, 'Project timeline');
  final rail = _box(
    id: 2,
    cx: 5.5,
    cy: 4.4,
    w: 9.2,
    h: 0.18,
    fillArgb: 0xFF94A3B8,
    label: '',
    rounded: false,
  );
  final milestones = <(String, String, int, double)>[
    ('Kickoff', 'Week 1', 0xFFBFDBFE, 1.6),
    ('Alpha', 'Week 4', 0xFFC4B5FD, 4.0),
    ('Beta', 'Week 8', 0xFFFDE68A, 6.5),
    ('GA', 'Week 12', 0xFFBBF7D0, 9.0),
  ];
  final shapes = <VsdxShape>[title, rail];
  var id = 3;
  for (final (name, whenLabel, color, x) in milestones) {
    shapes.add(_ellipse(
      id: id++,
      cx: x,
      cy: 4.4,
      w: 0.45,
      h: 0.45,
      fillArgb: color,
      label: '',
    ));
    shapes.add(_box(
      id: id++,
      cx: x,
      cy: 5.7,
      w: 1.8,
      h: 0.85,
      fillArgb: color,
      label: name,
      bold: true,
    ));
    shapes.add(_withLabel(
      VsdxShapeFactory.textBox(
        id: id++,
        pinX: x,
        pinY: 3.2,
        width: 1.6,
        height: 0.35,
        text: whenLabel,
      ),
      whenLabel,
      pt: 10,
    ));
  }
  return _write('Timeline', shapes, const <VsdxConnect>[]);
}

Uint8List _kanbanBoard() {
  final title = _title(1, 5.5, 7.7, 'Kanban board');
  final columns = <(String, int, double)>[
    ('Backlog', 0xFFE2E8F0, 2.0),
    ('Doing', 0xFFBFDBFE, 5.5),
    ('Done', 0xFFBBF7D0, 9.0),
  ];
  final cards = <(String, double, double)>[
    ('Story A', 2.0, 5.2),
    ('Story B', 2.0, 3.7),
    ('Story C', 5.5, 5.2),
    ('Story D', 9.0, 5.2),
  ];
  final shapes = <VsdxShape>[title];
  var id = 2;
  for (final (name, color, x) in columns) {
    shapes.add(_box(
      id: id++,
      cx: x,
      cy: 6.4,
      w: 2.8,
      h: 0.6,
      fillArgb: color,
      label: name,
      bold: true,
      pt: 12,
    ));
    shapes.add(_box(
      id: id++,
      cx: x,
      cy: 3.6,
      w: 2.8,
      h: 4.2,
      fillArgb: 0xFFF8FAFC,
      label: '',
      rounded: false,
    ));
  }
  for (final (name, x, y) in cards) {
    shapes.add(_box(
      id: id++,
      cx: x,
      cy: y,
      w: 2.3,
      h: 0.85,
      fillArgb: 0xFFFFFFFF,
      label: name,
      pt: 11,
    ));
  }
  return _write('Kanban Board', shapes, const <VsdxConnect>[]);
}

Uint8List _fishbone() {
  final title = _title(1, 5.5, 7.7, 'Cause & effect');
  final spine = _box(
    id: 2,
    cx: 5.2,
    cy: 4.4,
    w: 7.5,
    h: 0.14,
    fillArgb: 0xFF64748B,
    label: '',
    rounded: false,
  );
  final head = _diamond(
    id: 3,
    cx: 9.8,
    cy: 4.4,
    w: 1.8,
    h: 1.2,
    fillArgb: 0xFFFECACA,
    label: 'Effect',
  );
  final bones = <(String, double, double)>[
    ('People', 2.4, 6.0),
    ('Process', 4.6, 6.0),
    ('Tools', 6.8, 6.0),
    ('Data', 2.4, 2.8),
    ('Policy', 4.6, 2.8),
    ('Env', 6.8, 2.8),
  ];
  final shapes = <VsdxShape>[title, spine, head];
  var id = 4;
  for (final (label, x, y) in bones) {
    shapes.add(_box(
      id: id++,
      cx: x,
      cy: y,
      w: 1.7,
      h: 0.75,
      fillArgb: y > 4.4 ? 0xFFBFDBFE : 0xFFFDE68A,
      label: label,
    ));
  }
  return _write('Fishbone', shapes, const <VsdxConnect>[]);
}

Uint8List _cycleProcess() {
  final title = _title(1, 5.5, 7.7, 'Improvement cycle');
  final steps = <(String, int, double, double)>[
    ('Plan', 0xFFBFDBFE, 5.5, 6.3),
    ('Do', 0xFFC4B5FD, 8.4, 4.4),
    ('Check', 0xFFFDE68A, 5.5, 2.5),
    ('Act', 0xFFBBF7D0, 2.6, 4.4),
  ];
  final shapes = <VsdxShape>[title];
  final connects = <VsdxConnect>[];
  final nodes = <VsdxShape>[];
  var id = 2;
  for (final (label, color, x, y) in steps) {
    final n = _ellipse(
      id: id++,
      cx: x,
      cy: y,
      w: 1.8,
      h: 1.1,
      fillArgb: color,
      label: label,
      bold: true,
      pt: 13,
    );
    nodes.add(n);
    shapes.add(n);
  }
  for (var i = 0; i < nodes.length; i++) {
    final link = _link(id++, nodes[i], nodes[(i + 1) % nodes.length]);
    shapes.add(link.connector);
    connects.addAll(link.connects);
  }
  return _write('Cycle Process', shapes, connects);
}

Uint8List _vennDiagram() {
  final title = _title(1, 5.5, 7.7, 'Venn overlap');
  final a = _ellipse(
    id: 2,
    cx: 4.3,
    cy: 4.3,
    w: 3.4,
    h: 3.4,
    fillArgb: 0x6693C5FD,
    label: 'Set A',
    bold: true,
    pt: 14,
  );
  final b = _ellipse(
    id: 3,
    cx: 6.7,
    cy: 4.3,
    w: 3.4,
    h: 3.4,
    fillArgb: 0x66F9A8D4,
    label: 'Set B',
    bold: true,
    pt: 14,
  );
  final mid = _withLabel(
    VsdxShapeFactory.textBox(
      id: 4,
      pinX: 5.5,
      pinY: 4.3,
      width: 1.4,
      height: 0.4,
      text: 'Shared',
    ),
    'Shared',
    pt: 11,
    bold: true,
  );
  return _write('Venn Diagram', <VsdxShape>[title, a, b, mid], const []);
}

Uint8List _salesFunnel() {
  final title = _title(1, 5.5, 7.7, 'Sales funnel');
  final stages = <(String, int, double, double)>[
    ('Awareness', 0xFF93C5FD, 5.5, 6.4),
    ('Interest', 0xFFBFDBFE, 5.5, 5.2),
    ('Decision', 0xFFC4B5FD, 5.5, 4.0),
    ('Purchase', 0xFFBBF7D0, 5.5, 2.8),
  ];
  final shapes = <VsdxShape>[title];
  var id = 2;
  var w = 7.2;
  for (final (label, color, x, y) in stages) {
    shapes.add(_box(
      id: id++,
      cx: x,
      cy: y,
      w: w,
      h: 0.85,
      fillArgb: color,
      label: label,
      bold: true,
      pt: 13,
    ));
    w -= 1.2;
  }
  return _write('Sales Funnel', shapes, const <VsdxConnect>[]);
}

Uint8List _userJourney() {
  final title = _title(1, 5.5, 7.7, 'User journey');
  final stages = <(String, String, int, double)>[
    ('Discover', '😊', 0xFFBFDBFE, 1.8),
    ('Sign up', '🙂', 0xFFC4B5FD, 4.0),
    ('First use', '😐', 0xFFFDE68A, 6.2),
    ('Habit', '😄', 0xFFBBF7D0, 8.4),
  ];
  final shapes = <VsdxShape>[title];
  final connects = <VsdxConnect>[];
  VsdxShape? prev;
  var id = 2;
  for (final (name, mood, color, x) in stages) {
    final card = _box(
      id: id++,
      cx: x,
      cy: 5.0,
      w: 1.9,
      h: 1.5,
      fillArgb: color,
      label: '$name\n$mood',
      bold: true,
    );
    shapes.add(card);
    shapes.add(_box(
      id: id++,
      cx: x,
      cy: 2.8,
      w: 1.9,
      h: 1.2,
      fillArgb: 0xFFF8FAFC,
      label: 'Touchpoints\n• …',
      pt: 10,
      rounded: false,
    ));
    if (prev != null) {
      final link = _link(id++, prev, card);
      shapes.add(link.connector);
      connects.addAll(link.connects);
    }
    prev = card;
  }
  return _write('User Journey', shapes, connects);
}

Uint8List _networkTopology() {
  final title = _title(1, 5.5, 7.7, 'Network topology');
  final core = _ellipse(
    id: 2,
    cx: 5.5,
    cy: 4.5,
    w: 1.6,
    h: 1.0,
    fillArgb: 0xFF93C5FD,
    label: 'Core',
    bold: true,
  );
  final nodes = <(String, int, double, double)>[
    ('Edge A', 0xFFBFDBFE, 2.2, 6.2),
    ('Edge B', 0xFFBFDBFE, 8.8, 6.2),
    ('Edge C', 0xFFBFDBFE, 2.2, 2.8),
    ('Edge D', 0xFFBFDBFE, 8.8, 2.8),
    ('Cloud', 0xFFE0E7FF, 5.5, 1.7),
  ];
  final shapes = <VsdxShape>[title, core];
  final connects = <VsdxConnect>[];
  var id = 3;
  for (final (label, color, x, y) in nodes) {
    final n = _box(
      id: id++,
      cx: x,
      cy: y,
      w: 1.7,
      h: 0.85,
      fillArgb: color,
      label: label,
    );
    shapes.add(n);
    final link = _link(id++, core, n);
    shapes.add(link.connector);
    connects.addAll(link.connects);
  }
  return _write('Network Topology', shapes, connects);
}

Uint8List _meetingAgenda() {
  final title = _title(1, 5.5, 7.7, 'Meeting agenda');
  final headerLight = _box(
    id: 2,
    cx: 5.5,
    cy: 6.3,
    w: 8.5,
    h: 0.7,
    fillArgb: 0xFF93C5FD,
    label: 'Weekly sync  ·  30 min',
    bold: true,
    pt: 13,
  );
  final rows = <(String, String, double)>[
    ('5 min', 'Wins & blockers', 5.2),
    ('10 min', 'Priorities this week', 4.2),
    ('10 min', 'Decisions needed', 3.2),
    ('5 min', 'Action items', 2.2),
  ];
  final shapes = <VsdxShape>[title, headerLight];
  var id = 3;
  for (final (time, topic, y) in rows) {
    shapes.add(_box(
      id: id++,
      cx: 2.2,
      cy: y,
      w: 1.6,
      h: 0.7,
      fillArgb: 0xFFE0E7FF,
      label: time,
      bold: true,
    ));
    shapes.add(_box(
      id: id++,
      cx: 6.4,
      cy: y,
      w: 6.4,
      h: 0.7,
      fillArgb: 0xFFF8FAFC,
      label: topic,
      rounded: false,
    ));
  }
  return _write('Meeting Agenda', shapes, const <VsdxConnect>[]);
}

Uint8List _okrCascade() {
  final title = _title(1, 5.5, 7.7, 'OKR cascade');
  final objective = _box(
    id: 2,
    cx: 5.5,
    cy: 6.2,
    w: 4.5,
    h: 0.95,
    fillArgb: 0xFF93C5FD,
    label: 'Objective',
    bold: true,
    pt: 14,
  );
  final krs = <(String, double)>[
    ('KR 1 — metric', 2.2),
    ('KR 2 — metric', 5.5),
    ('KR 3 — metric', 8.8),
  ];
  final shapes = <VsdxShape>[title, objective];
  final connects = <VsdxConnect>[];
  var id = 3;
  for (final (label, x) in krs) {
    final kr = _box(
      id: id++,
      cx: x,
      cy: 4.2,
      w: 2.6,
      h: 1.0,
      fillArgb: 0xFFBFDBFE,
      label: label,
    );
    shapes.add(kr);
    final link = _link(id++, objective, kr);
    shapes.add(link.connector);
    connects.addAll(link.connects);
    shapes.add(_box(
      id: id++,
      cx: x,
      cy: 2.4,
      w: 2.6,
      h: 1.1,
      fillArgb: 0xFFF8FAFC,
      label: 'Initiatives\n• …\n• …',
      pt: 10,
      rounded: false,
    ));
  }
  return _write('OKR Cascade', shapes, connects);
}

// --- wave 2 templates ------------------------------------------------------

Uint8List _swimlaneProcess() {
  final title = _title(1, 5.5, 7.85, 'Swimlane process');
  final lanes = <(String, int, int, double)>[
    ('Customer', 0xFFDBEAFE, 0xFF93C5FD, 6.05),
    ('Support', 0xFFE0E7FF, 0xFFA5B4FC, 4.35),
    ('Ops', 0xFFD1FAE5, 0xFF6EE7B7, 2.65),
  ];
  final shapes = <VsdxShape>[title];
  var id = 2;
  for (final (name, laneColor, labelColor, y) in lanes) {
    shapes.add(_box(
      id: id++,
      cx: 5.5,
      cy: y,
      w: 9.4,
      h: 1.45,
      fillArgb: laneColor,
      label: '',
      rounded: false,
    ));
    shapes.add(_box(
      id: id++,
      cx: 1.15,
      cy: y,
      w: 1.5,
      h: 1.2,
      fillArgb: labelColor,
      label: name,
      bold: true,
    ));
  }

  final steps = <(String, int, double, double)>[
    ('Request', 0xFFBFDBFE, 3.2, 6.05),
    ('Triage', 0xFFC4B5FD, 5.4, 4.35),
    ('Resolve', 0xFFBBF7D0, 7.6, 2.65),
    ('Confirm', 0xFFFDE68A, 9.6, 6.05),
  ];
  final connects = <VsdxConnect>[];
  VsdxShape? prev;
  for (final (label, color, x, y) in steps) {
    final s = _box(
      id: id++,
      cx: x,
      cy: y,
      w: 1.7,
      h: 0.8,
      fillArgb: color,
      label: label,
      bold: true,
    );
    shapes.add(s);
    if (prev != null) {
      final link = _link(id++, prev, s);
      shapes.add(link.connector);
      connects.addAll(link.connects);
    }
    prev = s;
  }
  return _write('Swimlane Process', shapes, connects);
}

Uint8List _decisionTree() {
  final title = _title(1, 5.5, 7.75, 'Decision tree');
  final root = _diamond(
    id: 2,
    cx: 5.5,
    cy: 6.2,
    w: 2.0,
    h: 1.2,
    fillArgb: 0xFFFDE68A,
    label: 'Signal?',
  );
  final yes = _box(
    id: 3,
    cx: 3.0,
    cy: 4.2,
    w: 1.8,
    h: 0.9,
    fillArgb: 0xFFBBF7D0,
    label: 'Yes path',
    bold: true,
  );
  final no = _box(
    id: 4,
    cx: 8.0,
    cy: 4.2,
    w: 1.8,
    h: 0.9,
    fillArgb: 0xFFFECACA,
    label: 'No path',
    bold: true,
  );
  final leafA = _ellipse(
    id: 5,
    cx: 2.0,
    cy: 2.2,
    w: 1.5,
    h: 0.8,
    fillArgb: 0xFFBFDBFE,
    label: 'Action A',
  );
  final leafB = _ellipse(
    id: 6,
    cx: 4.0,
    cy: 2.2,
    w: 1.5,
    h: 0.8,
    fillArgb: 0xFFC4B5FD,
    label: 'Action B',
  );
  final leafC = _ellipse(
    id: 7,
    cx: 8.0,
    cy: 2.2,
    w: 1.6,
    h: 0.8,
    fillArgb: 0xFFFED7AA,
    label: 'Escalate',
  );
  final links = <({VsdxShape connector, List<VsdxConnect> connects})>[
    _link(20, root, yes),
    _link(21, root, no),
    _link(22, yes, leafA),
    _link(23, yes, leafB),
    _link(24, no, leafC),
  ];
  return _write(
    'Decision Tree',
    <VsdxShape>[
      title,
      root,
      yes,
      no,
      leafA,
      leafB,
      leafC,
      ...links.map((l) => l.connector),
    ],
    links.expand((l) => l.connects).toList(),
  );
}

Uint8List _valueStream() {
  final title = _title(1, 5.5, 7.75, 'Value stream');
  final stages = <(String, int)>[
    ('Supplier', 0xFFE0E7FF),
    ('Intake', 0xFFBFDBFE),
    ('Process', 0xFFC4B5FD),
    ('Deliver', 0xFFBBF7D0),
    ('Customer', 0xFFFDE68A),
  ];
  final shapes = <VsdxShape>[title];
  final connects = <VsdxConnect>[];
  VsdxShape? prev;
  var id = 2;
  var x = 1.5;
  for (final (label, color) in stages) {
    final s = _box(
      id: id++,
      cx: x,
      cy: 5.0,
      w: 1.7,
      h: 1.1,
      fillArgb: color,
      label: label,
      bold: true,
    );
    shapes.add(s);
    shapes.add(_box(
      id: id++,
      cx: x,
      cy: 3.2,
      w: 1.7,
      h: 0.85,
      fillArgb: 0xFFF8FAFC,
      label: 'Lead time\n…',
      pt: 10,
      rounded: false,
    ));
    if (prev != null) {
      final link = _link(id++, prev, s);
      shapes.add(link.connector);
      connects.addAll(link.connects);
    }
    prev = s;
    x += 2.0;
  }
  return _write('Value Stream', shapes, connects);
}

Uint8List _raciMatrix() {
  final title = _title(1, 5.5, 7.8, 'RACI matrix');
  final headers = <(String, int, double, double)>[
    ('Task', 0xFF93C5FD, 1.8, 2.2),
    ('PM', 0xFFBFDBFE, 4.0, 1.5),
    ('Design', 0xFFC4B5FD, 5.8, 1.5),
    ('Eng', 0xFFBBF7D0, 7.6, 1.5),
    ('QA', 0xFFFDE68A, 9.4, 1.5),
  ];
  final rows = <(String, List<String>, double)>[
    ('Scope', ['A', 'C', 'R', 'I'], 5.6),
    ('Build', ['C', 'I', 'A/R', 'C'], 4.4),
    ('Launch', ['A', 'C', 'R', 'R'], 3.2),
    ('Retro', ['A', 'R', 'C', 'C'], 2.0),
  ];
  final shapes = <VsdxShape>[title];
  var id = 2;
  for (final (h, color, x, w) in headers) {
    shapes.add(_box(
      id: id++,
      cx: x,
      cy: 6.7,
      w: w,
      h: 0.65,
      fillArgb: color,
      label: h,
      bold: true,
    ));
  }
  for (final (task, cells, y) in rows) {
    shapes.add(_box(
      id: id++,
      cx: 1.8,
      cy: y,
      w: 2.2,
      h: 0.85,
      fillArgb: 0xFFF1F5F9,
      label: task,
      bold: true,
      rounded: false,
    ));
    final xs = <double>[4.0, 5.8, 7.6, 9.4];
    for (var i = 0; i < cells.length; i++) {
      shapes.add(_box(
        id: id++,
        cx: xs[i],
        cy: y,
        w: 1.5,
        h: 0.85,
        fillArgb: 0xFFFFFFFF,
        label: cells[i],
        bold: true,
        rounded: false,
      ));
    }
  }
  return _write('RACI Matrix', shapes, const <VsdxConnect>[]);
}

Uint8List _capabilityPyramid() {
  final title = _title(1, 5.5, 7.75, 'Capability pyramid');
  final tiers = <(String, int, double, double)>[
    ('Vision', 0xFF93C5FD, 5.5, 6.4),
    ('Capabilities', 0xFFBFDBFE, 5.5, 5.0),
    ('Services', 0xFFC4B5FD, 5.5, 3.6),
    ('Platform & data', 0xFFBBF7D0, 5.5, 2.2),
  ];
  final shapes = <VsdxShape>[title];
  var id = 2;
  var w = 3.2;
  for (final (label, color, x, y) in tiers) {
    shapes.add(_box(
      id: id++,
      cx: x,
      cy: y,
      w: w,
      h: 1.0,
      fillArgb: color,
      label: label,
      bold: true,
      pt: 13,
    ));
    w += 1.5;
  }
  return _write('Capability Pyramid', shapes, const <VsdxConnect>[]);
}

Uint8List _sipoc() {
  final title = _title(1, 5.5, 7.75, 'SIPOC overview');
  final cols = <(String, String, int, double)>[
    ('Suppliers', 'Who provides\ninputs?', 0xFFE0E7FF, 1.5),
    ('Inputs', 'What goes\nin?', 0xFFBFDBFE, 3.5),
    ('Process', 'Core steps\n1 → 2 → 3', 0xFFC4B5FD, 5.5),
    ('Outputs', 'What comes\nout?', 0xFFBBF7D0, 7.5),
    ('Customers', 'Who receives\nvalue?', 0xFFFDE68A, 9.5),
  ];
  final shapes = <VsdxShape>[title];
  var id = 2;
  for (final (head, body, color, x) in cols) {
    shapes.add(_box(
      id: id++,
      cx: x,
      cy: 6.2,
      w: 1.8,
      h: 0.75,
      fillArgb: color,
      label: head,
      bold: true,
    ));
    shapes.add(_box(
      id: id++,
      cx: x,
      cy: 4.0,
      w: 1.8,
      h: 2.8,
      fillArgb: 0xFFF8FAFC,
      label: body,
      pt: 11,
      rounded: false,
    ));
  }
  return _write('SIPOC', shapes, const <VsdxConnect>[]);
}

Uint8List _eisenhowerMatrix() {
  final title = _title(1, 5.5, 7.8, 'Eisenhower matrix');
  final quads = <(String, String, int, double, double)>[
    ('Do now', 'Urgent + Important', 0xFFBBF7D0, 3.2, 5.2),
    ('Schedule', 'Not urgent + Important', 0xFFBFDBFE, 7.8, 5.2),
    ('Delegate', 'Urgent + Not important', 0xFFFDE68A, 3.2, 2.5),
    ('Eliminate', 'Neither', 0xFFFECACA, 7.8, 2.5),
  ];
  final shapes = <VsdxShape>[title];
  var id = 2;
  for (final (head, sub, color, x, y) in quads) {
    shapes.add(_box(
      id: id++,
      cx: x,
      cy: y,
      w: 4.0,
      h: 2.2,
      fillArgb: color,
      label: '$head\n$sub',
      bold: true,
      pt: 13,
    ));
  }
  return _write('Eisenhower Matrix', shapes, const <VsdxConnect>[]);
}

Uint8List _pestle() {
  final title = _title(1, 5.5, 7.75, 'PESTLE lens');
  final items = <(String, int, double, double)>[
    ('Political', 0xFF93C5FD, 2.2, 5.8),
    ('Economic', 0xFFBFDBFE, 5.5, 6.3),
    ('Social', 0xFFC4B5FD, 8.8, 5.8),
    ('Technological', 0xFFBBF7D0, 2.2, 3.2),
    ('Legal', 0xFFFDE68A, 5.5, 2.7),
    ('Environmental', 0xFFF9A8D4, 8.8, 3.2),
  ];
  final center = _ellipse(
    id: 2,
    cx: 5.5,
    cy: 4.5,
    w: 1.8,
    h: 1.1,
    fillArgb: 0xFFE0E7FF,
    label: 'Context',
    bold: true,
  );
  final shapes = <VsdxShape>[title, center];
  final connects = <VsdxConnect>[];
  var id = 3;
  for (final (label, color, x, y) in items) {
    final n = _box(
      id: id++,
      cx: x,
      cy: y,
      w: 2.2,
      h: 0.95,
      fillArgb: color,
      label: label,
      bold: true,
    );
    shapes.add(n);
    final link = _link(id++, center, n);
    shapes.add(link.connector);
    connects.addAll(link.connects);
  }
  return _write('PESTLE', shapes, connects);
}

Uint8List _businessModelCanvas() {
  final title = _title(1, 5.5, 7.85, 'Business model canvas');
  // Simplified BMC grid (9 blocks).
  final blocks = <(String, int, double, double, double, double)>[
    ('Key partners', 0xFFE0E7FF, 1.35, 5.55, 1.9, 3.0),
    ('Key activities', 0xFFBFDBFE, 3.35, 6.3, 1.9, 1.5),
    ('Key resources', 0xFFBFDBFE, 3.35, 4.5, 1.9, 1.5),
    ('Value propositions', 0xFFC4B5FD, 5.5, 5.55, 2.0, 3.0),
    ('Customer relationships', 0xFFBBF7D0, 7.65, 6.3, 1.9, 1.5),
    ('Channels', 0xFFBBF7D0, 7.65, 4.5, 1.9, 1.5),
    ('Customer segments', 0xFFFDE68A, 9.65, 5.55, 1.9, 3.0),
    ('Cost structure', 0xFFFECACA, 3.6, 2.55, 4.2, 1.2),
    ('Revenue streams', 0xFFF9A8D4, 8.0, 2.55, 4.2, 1.2),
  ];
  final shapes = <VsdxShape>[title];
  var id = 2;
  for (final (label, color, x, y, w, h) in blocks) {
    shapes.add(_box(
      id: id++,
      cx: x,
      cy: y,
      w: w,
      h: h,
      fillArgb: color,
      label: label,
      bold: true,
      pt: 10,
      rounded: false,
    ));
  }
  return _write('Business Model Canvas', shapes, const <VsdxConnect>[]);
}

Uint8List _balancedScorecard() {
  final title = _title(1, 5.5, 7.75, 'Balanced scorecard');
  final persps = <(String, String, int, double, double)>[
    ('Financial', 'Revenue · margin', 0xFF93C5FD, 3.2, 5.5),
    ('Customer', 'NPS · retention', 0xFFBFDBFE, 7.8, 5.5),
    ('Internal', 'Cycle time · quality', 0xFFC4B5FD, 3.2, 2.8),
    ('Learning', 'Skills · culture', 0xFFBBF7D0, 7.8, 2.8),
  ];
  final shapes = <VsdxShape>[title];
  var id = 2;
  for (final (head, metrics, color, x, y) in persps) {
    shapes.add(_box(
      id: id++,
      cx: x,
      cy: y,
      w: 4.0,
      h: 2.2,
      fillArgb: color,
      label: '$head\n$metrics',
      bold: true,
      pt: 13,
    ));
  }
  return _write('Balanced Scorecard', shapes, const <VsdxConnect>[]);
}

Uint8List _stakeholderMap() {
  final title = _title(1, 5.5, 7.75, 'Stakeholder map');
  final hub = _ellipse(
    id: 2,
    cx: 5.5,
    cy: 4.4,
    w: 1.7,
    h: 1.0,
    fillArgb: 0xFF93C5FD,
    label: 'Project',
    bold: true,
  );
  final nodes = <(String, int, double, double)>[
    ('Exec sponsor', 0xFFBFDBFE, 5.5, 6.5),
    ('Users', 0xFFBBF7D0, 2.2, 5.5),
    ('Partners', 0xFFC4B5FD, 8.8, 5.5),
    ('Ops', 0xFFFDE68A, 2.8, 2.6),
    ('Legal', 0xFFF9A8D4, 8.2, 2.6),
    ('Finance', 0xFFFED7AA, 5.5, 2.0),
  ];
  final shapes = <VsdxShape>[title, hub];
  final connects = <VsdxConnect>[];
  var id = 3;
  for (final (label, color, x, y) in nodes) {
    final n = _box(
      id: id++,
      cx: x,
      cy: y,
      w: 1.9,
      h: 0.85,
      fillArgb: color,
      label: label,
    );
    shapes.add(n);
    final link = _link(id++, hub, n);
    shapes.add(link.connector);
    connects.addAll(link.connects);
  }
  return _write('Stakeholder Map', shapes, connects);
}

Uint8List _porterFiveForces() {
  final title = _title(1, 5.5, 7.75, 'Five forces');
  final center = _box(
    id: 2,
    cx: 5.5,
    cy: 4.4,
    w: 2.4,
    h: 1.2,
    fillArgb: 0xFFE0E7FF,
    label: 'Rivalry',
    bold: true,
    pt: 13,
  );
  final forces = <(String, int, double, double)>[
    ('New entrants', 0xFFBFDBFE, 5.5, 6.5),
    ('Suppliers', 0xFFC4B5FD, 2.2, 4.4),
    ('Buyers', 0xFFBBF7D0, 8.8, 4.4),
    ('Substitutes', 0xFFFDE68A, 5.5, 2.3),
  ];
  final shapes = <VsdxShape>[title, center];
  final connects = <VsdxConnect>[];
  var id = 3;
  for (final (label, color, x, y) in forces) {
    final n = _box(
      id: id++,
      cx: x,
      cy: y,
      w: 2.2,
      h: 0.95,
      fillArgb: color,
      label: label,
      bold: true,
    );
    shapes.add(n);
    final link = _link(id++, center, n);
    shapes.add(link.connector);
    connects.addAll(link.connects);
  }
  return _write('Porter Five Forces', shapes, connects);
}

Uint8List _wireflow() {
  final title = _title(1, 5.5, 7.75, 'Wireflow');
  final screens = <(String, int, double)>[
    ('Home', 0xFFF1F5F9, 2.0),
    ('Browse', 0xFFE0E7FF, 4.5),
    ('Detail', 0xFFBFDBFE, 7.0),
    ('Checkout', 0xFFBBF7D0, 9.5),
  ];
  final shapes = <VsdxShape>[title];
  final connects = <VsdxConnect>[];
  VsdxShape? prev;
  var id = 2;
  for (final (label, color, x) in screens) {
    final frame = _box(
      id: id++,
      cx: x,
      cy: 4.6,
      w: 1.9,
      h: 3.2,
      fillArgb: color,
      label: '$label\n\n▢ ▢\n— —\n▢',
      bold: true,
      pt: 11,
      rounded: false,
    );
    shapes.add(frame);
    if (prev != null) {
      final link = _link(id++, prev, frame);
      shapes.add(link.connector);
      connects.addAll(link.connects);
    }
    prev = frame;
  }
  return _write('Wireflow', shapes, connects);
}

Uint8List _moscowPriorities() {
  final title = _title(1, 5.5, 7.75, 'MoSCoW priorities');
  final cols = <(String, int, double)>[
    ('Must', 0xFFFECACA, 2.0),
    ('Should', 0xFFFDE68A, 4.5),
    ('Could', 0xFFBFDBFE, 7.0),
    ("Won't", 0xFFE2E8F0, 9.5),
  ];
  final shapes = <VsdxShape>[title];
  var id = 2;
  for (final (head, color, x) in cols) {
    shapes.add(_box(
      id: id++,
      cx: x,
      cy: 6.3,
      w: 2.1,
      h: 0.75,
      fillArgb: color,
      label: head,
      bold: true,
      pt: 13,
    ));
    shapes.add(_box(
      id: id++,
      cx: x,
      cy: 3.8,
      w: 2.1,
      h: 3.4,
      fillArgb: 0xFFF8FAFC,
      label: '• …\n• …\n• …',
      pt: 12,
      rounded: false,
    ));
  }
  return _write('MoSCoW Priorities', shapes, const <VsdxConnect>[]);
}

Uint8List _personaMap() {
  final title = _title(1, 5.5, 7.75, 'Persona map');
  final header = _box(
    id: 2,
    cx: 5.5,
    cy: 6.35,
    w: 9.0,
    h: 0.9,
    fillArgb: 0xFFC4B5FD,
    label: 'Alex · Product-curious PM',
    bold: true,
    pt: 14,
  );
  final panels = <(String, String, int, double)>[
    ('Goals', 'Ship value\nweekly', 0xFFBFDBFE, 2.2),
    ('Frustrations', 'Context\nswitching', 0xFFFECACA, 5.5),
    ('Channels', 'Slack · email\ndocs', 0xFFBBF7D0, 8.8),
  ];
  final shapes = <VsdxShape>[title, header];
  var id = 3;
  for (final (head, body, color, x) in panels) {
    shapes.add(_box(
      id: id++,
      cx: x,
      cy: 4.7,
      w: 2.8,
      h: 0.7,
      fillArgb: color,
      label: head,
      bold: true,
    ));
    shapes.add(_box(
      id: id++,
      cx: x,
      cy: 3.0,
      w: 2.8,
      h: 2.0,
      fillArgb: 0xFFF8FAFC,
      label: body,
      pt: 12,
      rounded: false,
    ));
  }
  return _write('Persona Map', shapes, const <VsdxConnect>[]);
}

Uint8List _lessonPlan() {
  final title = _title(1, 5.5, 7.75, 'Lesson plan');
  final header = _box(
    id: 2,
    cx: 5.5,
    cy: 6.4,
    w: 9.0,
    h: 0.75,
    fillArgb: 0xFF93C5FD,
    label: 'Topic  ·  45 min  ·  Level: intro',
    bold: true,
    pt: 13,
  );
  final blocks = <(String, String, int, double)>[
    ('Warm-up', '5 min · hook', 0xFFE0E7FF, 5.5),
    ('Teach', '15 min · concept', 0xFFBFDBFE, 4.4),
    ('Practice', '15 min · guided', 0xFFBBF7D0, 3.3),
    ('Reflect', '10 min · share', 0xFFFDE68A, 2.2),
  ];
  final shapes = <VsdxShape>[title, header];
  var id = 3;
  for (final (head, body, color, y) in blocks) {
    shapes.add(_box(
      id: id++,
      cx: 2.4,
      cy: y,
      w: 2.4,
      h: 0.8,
      fillArgb: color,
      label: head,
      bold: true,
    ));
    shapes.add(_box(
      id: id++,
      cx: 7.0,
      cy: y,
      w: 6.0,
      h: 0.8,
      fillArgb: 0xFFF8FAFC,
      label: body,
      rounded: false,
    ));
  }
  return _write('Lesson Plan', shapes, const <VsdxConnect>[]);
}

Uint8List _conceptMap() {
  final title = _title(1, 5.5, 7.75, 'Concept map');
  final hub = _ellipse(
    id: 2,
    cx: 5.5,
    cy: 4.5,
    w: 2.0,
    h: 1.1,
    fillArgb: 0xFFC4B5FD,
    label: 'Core idea',
    bold: true,
  );
  final nodes = <(String, int, double, double)>[
    ('Definition', 0xFFBFDBFE, 2.4, 6.3),
    ('Examples', 0xFFBBF7D0, 8.6, 6.3),
    ('Causes', 0xFFFDE68A, 2.4, 2.7),
    ('Effects', 0xFFF9A8D4, 8.6, 2.7),
    ('Related', 0xFFE0E7FF, 5.5, 1.8),
  ];
  final shapes = <VsdxShape>[title, hub];
  final connects = <VsdxConnect>[];
  var id = 3;
  for (final (label, color, x, y) in nodes) {
    final n = _box(
      id: id++,
      cx: x,
      cy: y,
      w: 1.9,
      h: 0.9,
      fillArgb: color,
      label: label,
    );
    shapes.add(n);
    final link = _link(id++, hub, n);
    shapes.add(link.connector);
    connects.addAll(link.connects);
  }
  return _write('Concept Map', shapes, connects);
}

Uint8List _cloudArchitecture() {
  final title = _title(1, 5.5, 7.75, 'Cloud architecture');
  final edge = _box(
    id: 2,
    cx: 2.0,
    cy: 5.0,
    w: 1.8,
    h: 1.0,
    fillArgb: 0xFFBFDBFE,
    label: 'Clients',
    bold: true,
  );
  final cdn = _box(
    id: 3,
    cx: 4.2,
    cy: 5.0,
    w: 1.8,
    h: 1.0,
    fillArgb: 0xFFE0E7FF,
    label: 'CDN / WAF',
  );
  final api = _box(
    id: 4,
    cx: 6.5,
    cy: 5.0,
    w: 1.9,
    h: 1.0,
    fillArgb: 0xFFC4B5FD,
    label: 'API gateway',
    bold: true,
  );
  final svcA = _box(
    id: 5,
    cx: 8.9,
    cy: 6.1,
    w: 1.8,
    h: 0.85,
    fillArgb: 0xFFBBF7D0,
    label: 'Service A',
  );
  final svcB = _box(
    id: 6,
    cx: 8.9,
    cy: 4.0,
    w: 1.8,
    h: 0.85,
    fillArgb: 0xFFBBF7D0,
    label: 'Service B',
  );
  final data = _box(
    id: 7,
    cx: 6.5,
    cy: 2.4,
    w: 2.2,
    h: 0.95,
    fillArgb: 0xFFFDE68A,
    label: 'Data store',
    bold: true,
  );
  final queue = _box(
    id: 8,
    cx: 4.0,
    cy: 2.4,
    w: 2.0,
    h: 0.95,
    fillArgb: 0xFFF9A8D4,
    label: 'Queue',
  );
  final links = <({VsdxShape connector, List<VsdxConnect> connects})>[
    _link(20, edge, cdn),
    _link(21, cdn, api),
    _link(22, api, svcA),
    _link(23, api, svcB),
    _link(24, svcA, data),
    _link(25, svcB, data),
    _link(26, svcB, queue),
  ];
  return _write(
    'Cloud Architecture',
    <VsdxShape>[
      title,
      edge,
      cdn,
      api,
      svcA,
      svcB,
      data,
      queue,
      ...links.map((l) => l.connector),
    ],
    links.expand((l) => l.connects).toList(),
  );
}

Uint8List _dataModel() {
  final title = _title(1, 5.5, 7.75, 'Data model');
  final entities = <(String, String, int, double, double)>[
    ('User', 'id\nemail\nname', 0xFFBFDBFE, 2.4, 5.2),
    ('Order', 'id\nuser_id\ntotal', 0xFFC4B5FD, 5.5, 5.2),
    ('Item', 'id\norder_id\nsku', 0xFFBBF7D0, 8.6, 5.2),
    ('Product', 'id\nname\nprice', 0xFFFDE68A, 8.6, 2.6),
  ];
  final shapes = <VsdxShape>[title];
  final connects = <VsdxConnect>[];
  final byName = <String, VsdxShape>{};
  var id = 2;
  for (final (name, fields, color, x, y) in entities) {
    final e = _box(
      id: id++,
      cx: x,
      cy: y,
      w: 2.2,
      h: 1.8,
      fillArgb: color,
      label: '$name\n—\n$fields',
      bold: true,
      pt: 11,
      rounded: false,
    );
    shapes.add(e);
    byName[name] = e;
  }
  for (final pair in <(String, String)>[
    ('User', 'Order'),
    ('Order', 'Item'),
    ('Item', 'Product'),
  ]) {
    final link = _link(id++, byName[pair.$1]!, byName[pair.$2]!);
    shapes.add(link.connector);
    connects.addAll(link.connects);
  }
  return _write('Data Model', shapes, connects);
}

Uint8List _ciCdPipeline() {
  final title = _title(1, 5.5, 7.75, 'CI / CD pipeline');
  final stages = <(String, int, double)>[
    ('Commit', 0xFFE0E7FF, 1.6),
    ('Build', 0xFFBFDBFE, 3.6),
    ('Test', 0xFFC4B5FD, 5.6),
    ('Stage', 0xFFBBF7D0, 7.6),
    ('Prod', 0xFFFDE68A, 9.6),
  ];
  final shapes = <VsdxShape>[title];
  final connects = <VsdxConnect>[];
  VsdxShape? prev;
  var id = 2;
  for (final (label, color, x) in stages) {
    final s = _ellipse(
      id: id++,
      cx: x,
      cy: 4.8,
      w: 1.6,
      h: 1.0,
      fillArgb: color,
      label: label,
      bold: true,
    );
    shapes.add(s);
    shapes.add(_box(
      id: id++,
      cx: x,
      cy: 2.9,
      w: 1.7,
      h: 1.1,
      fillArgb: 0xFFF8FAFC,
      label: 'checks\n& gates',
      pt: 10,
      rounded: false,
    ));
    if (prev != null) {
      final link = _link(id++, prev, s);
      shapes.add(link.connector);
      connects.addAll(link.connects);
    }
    prev = s;
  }
  return _write('CI CD Pipeline', shapes, connects);
}
