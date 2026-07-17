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
