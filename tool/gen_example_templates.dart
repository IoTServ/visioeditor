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
