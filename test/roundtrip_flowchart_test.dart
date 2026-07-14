import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:visioeditor/editor/stencils.dart';
import 'package:visioeditor/io/image_export.dart';
import 'package:vsdx/vsdx.dart';

// ---------------------------------------------------------------------------
// Round-trip harness: build a flowchart the way the app's stencils/tools do,
// export it with the writer, re-parse it, and diff the model + render both to
// PNG. Any field that drifts across save→reopen is a writer/parser bug.
// ---------------------------------------------------------------------------

const _writer = VsdxWriter();
const _parser = DocumentParser();

/// Render a page to PNG under the system temp dir for a visual before/after
/// comparison (best-effort — skipped when the page can't be rasterised).
Future<void> _render(VsdxDocument d, String name) async {
  final png = await renderPageToPng(d.pages.first,
      theme: d.theme, images: d.images, pxPerInch: 96);
  if (png != null) {
    File('${Directory.systemTemp.path}/rt_$name.png').writeAsBytesSync(png);
  }
}

VsdxFill _fill(int argb) => VsdxFill(foreground: VsdxColor(argb));
VsdxLine _line(int argb, {double w = 0.02, int pattern = 1}) =>
    VsdxLine(color: VsdxColor(argb), weightInches: w, pattern: pattern);

/// A varied "flowchart" page: every stencil family, fills + line colours,
/// labels, rotation/flip, and connectors carrying each arrow id.
VsdxPage _buildFlowchart() {
  var id = 1;
  int nid() => id++;
  final shapes = <VsdxShape>[];

  // 2-D shapes: one per geometry family, each a distinct fill + line colour and
  // a text label, laid out on a grid.
  final builders = <VsdxShape Function(int, double, double)>[
    (i, x, y) => VsdxShapeFactory.rectangle(
        id: i, pinX: x, pinY: y, width: 1.4, height: 0.8,
        fill: _fill(0xFFE53935), line: _line(0xFF7B1FA2)),
    (i, x, y) => VsdxShapeFactory.roundedRectangle(
        id: i, pinX: x, pinY: y, width: 1.4, height: 0.8,
        fill: _fill(0xFF43A047), line: _line(0xFF1B5E20)),
    (i, x, y) => VsdxShapeFactory.ellipse(
        id: i, pinX: x, pinY: y, width: 1.4, height: 0.8,
        fill: _fill(0xFF1E88E5), line: _line(0xFF0D47A1)),
    (i, x, y) => VsdxShapeFactory.polygon(
        id: i, pinX: x, pinY: y, width: 1.2, height: 1.0,
        unit: const [Offset2D(0.5, 1), Offset2D(1, 0.5), Offset2D(0.5, 0), Offset2D(0, 0.5)],
        fill: _fill(0xFFFDD835), line: _line(0xFFF57F17)),
    (i, x, y) => VsdxShapeFactory.document(
        id: i, pinX: x, pinY: y, width: 1.4, height: 1.0,
        fill: _fill(0xFF8E24AA), line: _line(0xFF4A148C)),
    (i, x, y) => VsdxShapeFactory.cube(
        id: i, pinX: x, pinY: y, width: 1.2, height: 1.2,
        fill: _fill(0xFF00ACC1), line: _line(0xFF006064)),
    (i, x, y) => VsdxShapeFactory.cylinder(
        id: i, pinX: x, pinY: y, width: 1.0, height: 1.3,
        fill: _fill(0xFFFB8C00), line: _line(0xFFE65100)),
    (i, x, y) => VsdxShapeFactory.cloud(
        id: i, pinX: x, pinY: y, width: 1.6, height: 1.1,
        fill: _fill(0xFF90A4AE), line: _line(0xFF37474F)),
    (i, x, y) => VsdxShapeFactory.heart(
        id: i, pinX: x, pinY: y, width: 1.2, height: 1.1,
        fill: _fill(0xFFEC407A), line: _line(0xFF880E4F)),
    (i, x, y) => VsdxShapeFactory.delay(
        id: i, pinX: x, pinY: y, width: 1.4, height: 0.8,
        fill: _fill(0xFF26A69A), line: _line(0xFF004D40)),
  ];
  const labels = [
    'Process', 'Terminator', 'Start', 'Decision', 'Doc',
    'Cube', 'DB', 'Cloud', 'Heart', 'Delay',
  ];
  for (var k = 0; k < builders.length; k++) {
    final col = k % 5, row = k ~/ 5;
    final x = 1.4 + col * 1.9;
    final y = 9.4 - row * 1.9;
    shapes.add(builders[k](nid(), x, y).copyWith(text: labels[k]));
  }

  // A rotated rectangle and a flipped diamond.
  shapes.add(VsdxShapeFactory.rectangle(
    id: nid(), pinX: 2.2, pinY: 5.2, width: 1.4, height: 0.7,
    fill: _fill(0xFFFFFFFF), line: _line(0xFF000000),
  ).copyWith(text: 'Rot30', angleRad: 30 * 3.1415926535 / 180));
  shapes.add(VsdxShapeFactory.polygon(
    id: nid(), pinX: 4.2, pinY: 5.2, width: 1.2, height: 1.0,
    unit: const [Offset2D(0.2, 1), Offset2D(1, 1), Offset2D(0.8, 0), Offset2D(0, 0)],
    fill: _fill(0xFFB2FF59), line: _line(0xFF33691E),
  ).copyWith(flipX: true));

  // Connectors: each carries a different begin/end arrow id + colour + dash.
  final arrows = <(int begin, int end, int argb, int pattern)>[
    (0, 4, 0xFF2196F3, 1), // filled triangle
    (0, 10, 0xFF8BC34A, 1), // ball (circle)
    (0, 12, 0xFF9C27B0, 1), // stealth
    (4, 4, 0xFFFF5722, 2), // double triangle, dashed
    (0, 11, 0xFF3F51B5, 1), // open diamond
    (0, 1, 0xFF009688, 3), // open, dotted
  ];
  for (var k = 0; k < arrows.length; k++) {
    final (begin, end, argb, pat) = arrows[k];
    final y = 4.2 - k * 0.55;
    shapes.add(VsdxShapeFactory.line(
      id: nid(), ax: 1.2, ay: y, bx: 4.6, by: y,
      line: VsdxLine(
        color: VsdxColor(argb),
        weightInches: 0.03,
        pattern: pat,
        beginArrow: begin,
        endArrow: end,
      ),
    ));
  }

  return VsdxPage(
    id: 0,
    name: 'Flow',
    widthInches: 11,
    heightInches: 8.5,
    shapes: shapes,
  );
}

// ---------------------------------------------------------------------------
// Deep comparison
// ---------------------------------------------------------------------------

const _tol = 5e-3;

bool _close(double a, double b, [double tol = _tol]) => (a - b).abs() <= tol;

List<double> _coords(VsdxPathCommand c) => switch (c) {
      MoveTo(:final x, :final y) => [x, y],
      LineTo(:final x, :final y) => [x, y],
      EllipticalArcTo(:final x, :final y, :final controlX, :final controlY) =>
        [x, y, controlX, controlY],
      EllipseCmd(:final cx, :final cy, :final aX, :final aY, :final bX, :final bY) =>
        [cx, cy, aX, aY, bX, bY],
      CubBezTo(:final x, :final y, :final x1, :final y1, :final x2, :final y2) =>
        [x, y, x1, y1, x2, y2],
      QuadBezTo(:final x, :final y, :final x1, :final y1) => [x, y, x1, y1],
      _ => const <double>[],
    };

void _diffShape(VsdxShape a, VsdxShape b, String path, List<String> out) {
  void num2(String f, double x, double y) {
    if (!_close(x, y)) out.add('$path.$f: $x -> $y');
  }

  num2('pinX', a.pinX, b.pinX);
  num2('pinY', a.pinY, b.pinY);
  num2('width', a.width, b.width);
  num2('height', a.height, b.height);
  num2('angleRad', a.angleRad, b.angleRad);
  if (a.flipX != b.flipX) out.add('$path.flipX: ${a.flipX} -> ${b.flipX}');
  if (a.flipY != b.flipY) out.add('$path.flipY: ${a.flipY} -> ${b.flipY}');
  if (a.is1D != b.is1D) out.add('$path.is1D: ${a.is1D} -> ${b.is1D}');
  if (a.locked != b.locked) out.add('$path.locked: ${a.locked} -> ${b.locked}');
  if (a.curved != b.curved) out.add('$path.curved: ${a.curved} -> ${b.curved}');
  if (a.rounded != b.rounded) {
    out.add('$path.rounded: ${a.rounded} -> ${b.rounded}');
  }
  if (a.straightRoute != b.straightRoute) {
    out.add('$path.straightRoute: ${a.straightRoute} -> ${b.straightRoute}');
  }
  if ((a.imagePartName == null) != (b.imagePartName == null)) {
    out.add('$path.image: ${a.imagePartName != null} -> ${b.imagePartName != null}');
  }

  // Connector bend points.
  final aw = a.waypoints, bw = b.waypoints;
  if (aw.length != bw.length) {
    out.add('$path.waypoints: ${aw.length} -> ${bw.length}');
  } else {
    for (var i = 0; i < aw.length; i++) {
      if (!_close(aw[i].x, bw[i].x) || !_close(aw[i].y, bw[i].y)) {
        out.add('$path.wp[$i]: (${aw[i].x},${aw[i].y}) -> (${bw[i].x},${bw[i].y})');
      }
    }
  }

  // Trailing whitespace is intentionally normalised on reopen (Visio appends a
  // trailing newline + empty tab marker to labels; the parser strips it to
  // match Visio/libvisio layout — see rich_text_parser._trimTrailingWhitespace),
  // so compare with trailing whitespace removed on both sides.
  String plain(VsdxShape s) =>
      (s.richText.runs.isNotEmpty ? s.richText.plainText : (s.text ?? ''))
          .replaceFirst(RegExp(r'\s+$'), '');
  final at = plain(a), bt = plain(b);
  if (at != bt) out.add('$path.text: "$at" -> "$bt"');

  // Fill
  if (a.fill.pattern != b.fill.pattern) {
    out.add('$path.fill.pattern: ${a.fill.pattern} -> ${b.fill.pattern}');
  }
  if (a.fill.foreground?.value != b.fill.foreground?.value) {
    out.add('$path.fill.fg: ${a.fill.foreground?.value.toRadixString(16)} '
        '-> ${b.fill.foreground?.value.toRadixString(16)}');
  }
  if (a.fill.background?.value != b.fill.background?.value) {
    out.add('$path.fill.bg: ${a.fill.background?.value.toRadixString(16)} '
        '-> ${b.fill.background?.value.toRadixString(16)}');
  }
  final ga = a.fill.gradient, gb = b.fill.gradient;
  if ((ga == null) != (gb == null)) {
    out.add('$path.fill.gradient: ${ga != null} -> ${gb != null}');
  } else if (ga != null && gb != null) {
    if (ga.stops.length != gb.stops.length) {
      out.add('$path.fill.gradient.stops: ${ga.stops.length} -> ${gb.stops.length}');
    } else {
      for (var i = 0; i < ga.stops.length; i++) {
        if (ga.stops[i].color?.value != gb.stops[i].color?.value ||
            !_close(ga.stops[i].position, gb.stops[i].position)) {
          out.add('$path.fill.gradient.stop[$i]: '
              '${ga.stops[i].color?.value.toRadixString(16)}@${ga.stops[i].position}'
              ' -> ${gb.stops[i].color?.value.toRadixString(16)}@${gb.stops[i].position}');
        }
      }
    }
  }

  // Line
  if (a.line.pattern != b.line.pattern) {
    out.add('$path.line.pattern: ${a.line.pattern} -> ${b.line.pattern}');
  }
  if (a.line.color?.value != b.line.color?.value) {
    out.add('$path.line.color: ${a.line.color?.value.toRadixString(16)} '
        '-> ${b.line.color?.value.toRadixString(16)}');
  }
  if (!_close(a.line.weightInches, b.line.weightInches)) {
    out.add('$path.line.weight: ${a.line.weightInches} -> ${b.line.weightInches}');
  }
  if (a.line.beginArrow != b.line.beginArrow) {
    out.add('$path.line.beginArrow: ${a.line.beginArrow} -> ${b.line.beginArrow}');
  }
  if (a.line.endArrow != b.line.endArrow) {
    out.add('$path.line.endArrow: ${a.line.endArrow} -> ${b.line.endArrow}');
  }
  num2('fill.trans', a.fill.foregroundTransparency, b.fill.foregroundTransparency);
  num2('line.trans', a.line.transparency, b.line.transparency);
  num2('line.beginArrowSize', a.line.beginArrowSizeInches, b.line.beginArrowSizeInches);
  num2('line.endArrowSize', a.line.endArrowSizeInches, b.line.endArrowSizeInches);
  num2('line.rounding', a.line.roundingInches, b.line.roundingInches);
  _diffRuns(a, b, path, out);

  // Geometry (drawn sections only).
  final ag = a.geometries.where((g) => !g.deleted).toList();
  final bg = b.geometries.where((g) => !g.deleted).toList();
  if (ag.length != bg.length) {
    out.add('$path.geom.count: ${ag.length} -> ${bg.length}');
  } else {
    for (var i = 0; i < ag.length; i++) {
      final ac = ag[i].commands, bc = bg[i].commands;
      if (ac.length != bc.length) {
        out.add('$path.geom[$i].cmds: ${ac.length} -> ${bc.length} '
            '(${ac.map((c) => c.runtimeType).toList()} vs '
            '${bc.map((c) => c.runtimeType).toList()})');
        continue;
      }
      for (var j = 0; j < ac.length; j++) {
        if (ac[j].runtimeType != bc[j].runtimeType) {
          out.add('$path.geom[$i][$j].type: ${ac[j].runtimeType} -> ${bc[j].runtimeType}');
          continue;
        }
        final xa = _coords(ac[j]), xb = _coords(bc[j]);
        for (var m = 0; m < xa.length && m < xb.length; m++) {
          if (!_close(xa[m], xb[m])) {
            out.add('$path.geom[$i][$j] ${ac[j].runtimeType}: $xa -> $xb');
            break;
          }
        }
      }
      if (ag[i].noFill != bg[i].noFill) {
        out.add('$path.geom[$i].noFill: ${ag[i].noFill} -> ${bg[i].noFill}');
      }
      if (ag[i].noLine != bg[i].noLine) {
        out.add('$path.geom[$i].noLine: ${ag[i].noLine} -> ${bg[i].noLine}');
      }
    }
  }

  // Shape data (custom properties).
  final ap = a.userProperties, bp = b.userProperties;
  if (ap.length != bp.length) {
    out.add('$path.props: ${ap.length} -> ${bp.length}');
  } else {
    for (var i = 0; i < ap.length; i++) {
      if (ap[i].name != bp[i].name ||
          ap[i].label != bp[i].label ||
          ap[i].value != bp[i].value ||
          ap[i].type != bp[i].type) {
        out.add('$path.prop[$i]: '
            '${ap[i].name}/${ap[i].label}=${ap[i].value}(t${ap[i].type}) -> '
            '${bp[i].name}/${bp[i].label}=${bp[i].value}(t${bp[i].type})');
      }
    }
  }

  // Hyperlinks.
  final ah = a.hyperlinks, bh = b.hyperlinks;
  if (ah.length != bh.length) {
    out.add('$path.links: ${ah.length} -> ${bh.length}');
  } else {
    for (var i = 0; i < ah.length; i++) {
      if (ah[i].address != bh[i].address ||
          ah[i].subAddress != bh[i].subAddress ||
          ah[i].description != bh[i].description) {
        out.add('$path.link[$i]: '
            '${ah[i].description}|${ah[i].address}|${ah[i].subAddress} -> '
            '${bh[i].description}|${bh[i].address}|${bh[i].subAddress}');
      }
    }
  }

  // Shadow.
  if (a.shadow.enabled != b.shadow.enabled) {
    out.add('$path.shadow: ${a.shadow.enabled} -> ${b.shadow.enabled}');
  }

  // Children (matched by index).
  if (a.children.length != b.children.length) {
    out.add('$path.children: ${a.children.length} -> ${b.children.length}');
  } else {
    for (var i = 0; i < a.children.length; i++) {
      _diffShape(a.children[i], b.children[i], '$path/${a.children[i].id}', out);
    }
  }
}

void _diffRuns(VsdxShape a, VsdxShape b, String path, List<String> out) {
  final ar = a.richText.runs, br = b.richText.runs;
  // A shape whose text lives only in the plain `.text` field (no explicit
  // runs) is normalised to a single default-styled run on reopen — that is
  // expected and its content is checked via the `.text` comparison above, so
  // only diff runs when the original actually carried styled runs.
  if (ar.isEmpty) return;
  if (ar.length != br.length) {
    out.add('$path.runs: ${ar.length} -> ${br.length}');
  } else {
    for (var i = 0; i < ar.length; i++) {
      final x = ar[i], y = br[i];
      final cx = x.charStyle, cy = y.charStyle;
      if (x.text != y.text) {
        out.add('$path.run[$i].text: "${x.text}" -> "${y.text}"');
      }
      if (!_close(cx.fontSizeInches, cy.fontSizeInches)) {
        out.add('$path.run[$i].size: ${cx.fontSizeInches} -> ${cy.fontSizeInches}');
      }
      if (cx.style.bold != cy.style.bold) {
        out.add('$path.run[$i].bold: ${cx.style.bold} -> ${cy.style.bold}');
      }
      if (cx.style.italic != cy.style.italic) {
        out.add('$path.run[$i].italic: ${cx.style.italic} -> ${cy.style.italic}');
      }
      if (cx.underline != cy.underline) {
        out.add('$path.run[$i].underline: ${cx.underline} -> ${cy.underline}');
      }
      if (cx.color?.value != cy.color?.value) {
        out.add('$path.run[$i].color: ${cx.color?.value.toRadixString(16)} '
            '-> ${cy.color?.value.toRadixString(16)}');
      }
      if (cx.fontFamily != cy.fontFamily) {
        out.add('$path.run[$i].font: ${cx.fontFamily} -> ${cy.fontFamily}');
      }
      if (x.paraStyle.horizontalAlign != y.paraStyle.horizontalAlign) {
        out.add('$path.run[$i].align: ${x.paraStyle.horizontalAlign} '
            '-> ${y.paraStyle.horizontalAlign}');
      }
    }
  }
  if (a.richText.textBlock.verticalAlign != b.richText.textBlock.verticalAlign) {
    out.add('$path.vAlign: ${a.richText.textBlock.verticalAlign} '
        '-> ${b.richText.textBlock.verticalAlign}');
  }
}

String _connectKey(VsdxConnect c) =>
    '${c.fromSheetId}.${c.fromCell}->${c.toSheetId}.${c.toCell}'
    '[${c.fromPart}/${c.toPart}]';

List<String> _diffPage(VsdxPage a, VsdxPage b) {
  final out = <String>[];
  if (!_close(a.widthInches, b.widthInches)) {
    out.add('page.width: ${a.widthInches} -> ${b.widthInches}');
  }
  if (!_close(a.heightInches, b.heightInches)) {
    out.add('page.height: ${a.heightInches} -> ${b.heightInches}');
  }
  if (a.backgroundColor?.value != b.backgroundColor?.value) {
    out.add('page.bg: ${a.backgroundColor?.value.toRadixString(16)} '
        '-> ${b.backgroundColor?.value.toRadixString(16)}');
  }

  // Glue / Connect entries (page-level).
  final ac = [...a.connects]..sort((x, y) => _connectKey(x).compareTo(_connectKey(y)));
  final bc = [...b.connects]..sort((x, y) => _connectKey(x).compareTo(_connectKey(y)));
  if (ac.length != bc.length) {
    out.add('page.connects: ${ac.length} -> ${bc.length}');
  } else {
    for (var i = 0; i < ac.length; i++) {
      if (_connectKey(ac[i]) != _connectKey(bc[i])) {
        out.add('page.connect[$i]: ${_connectKey(ac[i])} -> ${_connectKey(bc[i])}');
      }
    }
  }

  final bById = {for (final s in b.shapes) s.id: s};
  if (a.shapes.length != b.shapes.length) {
    out.add('page.shapeCount: ${a.shapes.length} -> ${b.shapes.length}');
  }
  for (final sa in a.shapes) {
    final sb = bById[sa.id];
    if (sb == null) {
      out.add('shape ${sa.id} (${sa.name}) MISSING after round-trip');
      continue;
    }
    _diffShape(sa, sb, 'shape ${sa.id}', out);
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('flowchart survives export → reopen with no model drift', () async {
    final blank = _writer.emptyDocument(widthInches: 11, heightInches: 8.5);
    final base = _parser.parse(blank);
    final page = _buildFlowchart();
    final edited = base.replacePage(0, page);

    final outBytes = _writer.write(originalBytes: blank, edited: edited);
    final reopened = _parser.parse(outBytes);

    final diffs = _diffPage(edited.pages.first, reopened.pages.first);

    // Render both for a visual before/after comparison.
    await _render(edited, 'before');
    await _render(reopened, 'after');

    if (diffs.isNotEmpty) {
      // ignore: avoid_print
      print('=== ROUND-TRIP DIFFS (${diffs.length}) ===\n${diffs.join('\n')}');
    }
    expect(diffs, isEmpty, reason: 'round-trip drift:\n${diffs.join('\n')}');
  });

  test('editor-built diagram (formatting, glued/curved edge, group) round-trips',
      () async {
    final c = EditorController()..newDocument(widthInches: 11, heightInches: 8.5);
    addTearDown(c.dispose);

    // A formatted rectangle (bold/italic/underline, coloured text, right/top
    // aligned, translucent fill).
    c.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id, pinX: cx, pinY: cy, width: 1.8, height: 1.0),
        2.5, 6.5);
    final id1 = c.singleSelectedId!;
    c.setFillColor(const VsdxColor(0xFFE3F2FD));
    c.setLineColor(const VsdxColor(0xFF1565C0));
    c.setShapeText(id1, 'Bold Italic');
    c
      ..setBold(true)
      ..setItalic(true)
      ..setUnderline(true)
      ..setTextColor(const VsdxColor(0xFFD32F2F))
      ..setTextSizeInches(18 / 72)
      ..setFontFamily('Arial')
      ..setTextAlign(VsdxHorzAlign.right)
      ..setTextVerticalAlign(VsdxVertAlign.top)
      ..setFillOpacity(0.5);

    // A target ellipse.
    c.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.ellipse(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 1.0),
        7.5, 6.5);
    final id2 = c.singleSelectedId!;
    c
      ..setFillColor(const VsdxColor(0xFFFFF3E0))
      ..setShapeText(id2, 'Target');

    // A glued, curved connector with a ball end.
    c.createConnector(3.4, 6.5, 6.7, 6.5, beginTarget: id1, endTarget: id2);
    c
      ..setLineArrows(begin: 0, end: 10)
      ..setLineColor(const VsdxColor(0xFF388E3C))
      ..setConnectorRouteStyle(ConnectorRouteStyle.curved);

    // Two shapes grouped together.
    c.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id, pinX: cx, pinY: cy, width: 1.0, height: 0.6),
        2.0, 3.0);
    final g1 = c.singleSelectedId!;
    c.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.ellipse(
            id: id, pinX: cx, pinY: cy, width: 1.0, height: 0.6),
        3.4, 3.0);
    final g2 = c.singleSelectedId!;
    c.setSelection(<int>[g1, g2]);
    c.groupSelection();

    final before = c.document!;
    final after = _parser.parse(c.exportToBytes());
    final diffs = _diffPage(before.pages.first, after.pages.first);

    await _render(before, 'ed_before');
    await _render(after, 'ed_after');

    if (diffs.isNotEmpty) {
      // ignore: avoid_print
      print('=== EDITOR ROUND-TRIP DIFFS (${diffs.length}) ===\n${diffs.join('\n')}');
    }
    expect(diffs, isEmpty, reason: 'editor round-trip drift:\n${diffs.join('\n')}');
  });

  test('a 3-page document round-trips every page', () {
    final c = EditorController()..newDocument(widthInches: 11, heightInches: 8.5);
    addTearDown(c.dispose);
    c.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 0.9),
        3, 6);
    c.setShapeText(c.singleSelectedId!, 'Page1');
    c.addPage();
    c.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.ellipse(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 0.9),
        4, 5);
    c.setFillColor(const VsdxColor(0xFF1E88E5));
    c.addPage();
    c.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.polygon(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.0,
            unit: const [Offset2D(0.5, 1), Offset2D(1, 0.5), Offset2D(0.5, 0), Offset2D(0, 0.5)]),
        5, 4);

    final before = c.document!;
    final after = _parser.parse(c.exportToBytes());
    expect(after.pages.length, before.pages.length);
    final diffs = <String>[];
    for (var i = 0; i < before.pages.length; i++) {
      diffs.addAll(
          _diffPage(before.pages[i], after.pages[i]).map((d) => 'page$i $d'));
    }
    expect(diffs, isEmpty, reason: 'multi-page drift:\n${diffs.join('\n')}');
  });

  test('rotation + flip combinations round-trip', () {
    final blank = _writer.emptyDocument(widthInches: 11, heightInches: 8.5);
    final base = _parser.parse(blank);
    var id = 1;
    const tri = [Offset2D(0.5, 1), Offset2D(1, 0), Offset2D(0, 0)];
    final shapes = <VsdxShape>[];
    for (final deg in <double>[0, 30, 45, 90, 135, 180, 270]) {
      shapes.add(VsdxShapeFactory.rectangle(
        id: id++, pinX: 1.5 + shapes.length * 1.3, pinY: 6,
        width: 1.0, height: 0.6,
        fill: _fill(0xFF90CAF9), line: _line(0xFF0D47A1),
      ).copyWith(angleRad: deg * 3.1415926535 / 180));
    }
    for (final flip in const [(true, false), (false, true), (true, true)]) {
      shapes.add(VsdxShapeFactory.polygon(
        id: id++, pinX: 1.5 + (shapes.length - 7) * 1.6, pinY: 3,
        width: 1.2, height: 1.0, unit: tri,
        fill: _fill(0xFFA5D6A7), line: _line(0xFF1B5E20),
      ).copyWith(flipX: flip.$1, flipY: flip.$2));
    }
    final edited = base.replacePage(0,
        VsdxPage(id: 0, name: 'Rot', widthInches: 11, heightInches: 8.5, shapes: shapes));
    final after = _parser.parse(_writer.write(originalBytes: blank, edited: edited));
    final diffs = _diffPage(edited.pages.first, after.pages.first);
    expect(diffs, isEmpty, reason: 'rotation/flip drift:\n${diffs.join('\n')}');
  });

  test('a linear gradient fill round-trips', () {
    final blank = _writer.emptyDocument();
    final base = _parser.parse(blank);
    const grad = VsdxGradient(
      stops: [
        VsdxGradientStop(position: 0, color: VsdxColor(0xFF6A11CB)),
        VsdxGradientStop(position: 1, color: VsdxColor(0xFF2575FC)),
      ],
      type: VsdxGradientType.linear,
    );
    final shape = VsdxShapeFactory.rectangle(
      id: 1, pinX: 4, pinY: 6, width: 2.0, height: 1.2,
      fill: const VsdxFill(foreground: VsdxColor(0xFF6A11CB), gradient: grad),
      line: _line(0xFF311B92),
    );
    final edited = base.replacePage(0,
        VsdxPage(id: 0, name: 'Grad', widthInches: 8.5, heightInches: 11, shapes: [shape]));
    final after = _parser.parse(_writer.write(originalBytes: blank, edited: edited));
    final diffs = _diffPage(edited.pages.first, after.pages.first);
    expect(diffs, isEmpty, reason: 'gradient drift:\n${diffs.join('\n')}');
  });

  test('waypointed connector + no-fill box + multiline text round-trip', () {
    final c = EditorController()..newDocument(widthInches: 11, heightInches: 8.5);
    addTearDown(c.dispose);

    c.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 0.8),
        2, 6);
    final a = c.singleSelectedId!;
    c.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 0.8),
        8, 3);
    final b = c.singleSelectedId!;

    // Connector with two bend points (an orthogonal dog-leg).
    c.createConnector(2.7, 6, 7.3, 3, beginTarget: a, endTarget: b);
    final conn = c.singleSelectedId!;
    c.setConnectorWaypoints(conn, const <Offset2D>[Offset2D(5, 6), Offset2D(5, 3)]);

    // A borderless-fill box carrying a two-line label.
    c.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id, pinX: cx, pinY: cy, width: 2.0, height: 1.2),
        5, 8);
    final nf = c.singleSelectedId!;
    c.setNoFill();
    c.setShapeText(nf, 'Line one\nLine two');

    final before = c.document!;
    final after = _parser.parse(c.exportToBytes());
    final diffs = _diffPage(before.pages.first, after.pages.first);
    expect(diffs, isEmpty, reason: 'waypoint/no-fill/text drift:\n${diffs.join('\n')}');
  });

  test('every built-in stencil round-trips its geometry', () {
    final blank = _writer.emptyDocument(widthInches: 40, heightInches: 40);
    final base = _parser.parse(blank);
    var id = 1;
    final shapes = <VsdxShape>[
      for (var k = 0; k < kStencils.length; k++)
        kStencils[k].build(id++, 1.5 + (k % 8) * 3.0, 38.0 - (k ~/ 8) * 3.0),
    ];
    final edited = base.replacePage(
        0, VsdxPage(id: 0, name: 'All', widthInches: 40, heightInches: 40, shapes: shapes));
    final after = _parser.parse(_writer.write(originalBytes: blank, edited: edited));

    final diffs = <String>[];
    final bById = {for (final s in after.pages.first.shapes) s.id: s};
    for (final sa in edited.pages.first.shapes) {
      final sb = bById[sa.id];
      final label = kStencils[sa.id - 1].name;
      if (sb == null) {
        diffs.add('"$label" (id ${sa.id}) missing');
        continue;
      }
      _diffShape(sa, sb, '"$label"', diffs);
    }
    if (diffs.isNotEmpty) {
      // ignore: avoid_print
      print('=== STENCIL DIFFS (${diffs.length}) ===\n${diffs.join('\n')}');
    }
    expect(diffs, isEmpty, reason: 'stencil drift:\n${diffs.join('\n')}');
  });

  test('special / unicode / whitespace text round-trips (XML escaping)', () {
    final blank = _writer.emptyDocument();
    final base = _parser.parse(blank);
    const texts = <String>[
      'A < B & C > D "quoted" \'apostrophe\'',
      '中文标签：流程 & 决策 <节点>',
      'emoji 🚀 ✅ ❤ tab\tend',
      'line1\nline2\nline3',
      '  leading and trailing spaces  ',
      r'special </Shape> <![CDATA[x]]> & % $ #',
    ];
    var id = 1;
    final shapes = <VsdxShape>[
      for (var k = 0; k < texts.length; k++)
        VsdxShapeFactory.rectangle(
          id: id++, pinX: 2 + (k % 3) * 2.4, pinY: 9 - (k ~/ 3) * 2.5,
          width: 2.2, height: 1.2,
        ).copyWith(text: texts[k]),
    ];
    final edited = base.replacePage(
        0, VsdxPage(id: 0, name: 'Txt', widthInches: 8.5, heightInches: 11, shapes: shapes));
    final after = _parser.parse(_writer.write(originalBytes: blank, edited: edited));

    final diffs = _diffPage(edited.pages.first, after.pages.first);
    if (diffs.isNotEmpty) {
      // ignore: avoid_print
      print('=== TEXT DIFFS (${diffs.length}) ===\n${diffs.join('\n')}');
    }
    expect(diffs, isEmpty, reason: 'text drift:\n${diffs.join('\n')}');
  });

  test('shape data + hyperlink + shadow + nested group round-trip', () {
    final c = EditorController()..newDocument(widthInches: 11, heightInches: 8.5);
    addTearDown(c.dispose);

    // A shape carrying custom properties, a hyperlink, and a drop shadow.
    c.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id, pinX: cx, pinY: cy, width: 1.8, height: 1.0),
        3, 6);
    final id1 = c.singleSelectedId!;
    c.setShapeText(id1, 'Server');
    c.setShapeProperties(id1, const <VsdxUserProperty>[
      VsdxUserProperty(name: 'Owner', label: 'Owner', value: 'Alice'),
      VsdxUserProperty(name: 'Zone', label: 'Zone', value: 'eu-west-1'),
      VsdxUserProperty(name: 'Notes', label: 'Notes', value: 'a & b < c > "d"'),
    ]);
    c.setShapeHyperlinks(id1, const <VsdxHyperlink>[
      VsdxHyperlink(
          id: 0,
          description: 'Docs',
          address: 'https://example.com/docs?a=1&b=2',
          subAddress: 'Page-2'),
    ]);
    c.setShadow(true);

    // Nested group: group A+B into an inner group, then group that with C.
    c.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id, pinX: cx, pinY: cy, width: 1.0, height: 0.6),
        6.0, 6.0);
    final a = c.singleSelectedId!;
    c.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.ellipse(
            id: id, pinX: cx, pinY: cy, width: 1.0, height: 0.6),
        7.5, 6.0);
    final b = c.singleSelectedId!;
    c.setSelection(<int>[a, b]);
    c.groupSelection();
    final inner = c.singleSelectedId!;
    c.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.polygon(
            id: id, pinX: cx, pinY: cy, width: 1.2, height: 1.0,
            unit: const [Offset2D(0.5, 1), Offset2D(1, 0.5), Offset2D(0.5, 0), Offset2D(0, 0.5)]),
        6.75, 4.0);
    final cc = c.singleSelectedId!;
    c.setSelection(<int>[inner, cc]);
    c.groupSelection();

    final before = c.document!;
    final after = _parser.parse(c.exportToBytes());
    final diffs = _diffPage(before.pages.first, after.pages.first);
    if (diffs.isNotEmpty) {
      // ignore: avoid_print
      print('=== DATA/LINK/GROUP DIFFS (${diffs.length}) ===\n${diffs.join('\n')}');
    }
    expect(diffs, isEmpty, reason: 'data/link/group drift:\n${diffs.join('\n')}');
  });

  test('an editing session (page bg/size, resize, opacity, duplicate, z-order) '
      'round-trips', () {
    final c = EditorController()..newDocument(widthInches: 8.5, heightInches: 11);
    addTearDown(c.dispose);

    // Page-level edits: background colour + switch to landscape.
    c.setBackgroundColor(const VsdxColor(0xFFE8F5E9));
    c.setPageSize(11, 8.5);

    // Add a shape, resize it, and make it translucent.
    c.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 0.8),
        3, 5);
    final id1 = c.singleSelectedId!;
    c.setFillColor(const VsdxColor(0xFF1E88E5));
    c.setLineColor(const VsdxColor(0xFF0D47A1));
    c.resizeShape(id1, pinX: 4, pinY: 6, width: 2.5, height: 1.5);
    c
      ..setFillOpacity(0.35)
      ..setLineOpacity(0.70);

    // Duplicate it, then add another shape and send it behind everything.
    c.selectOnly(id1);
    c.duplicateSelection();
    c.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.ellipse(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 1.0),
        7, 4);
    c.sendSelectionToBack();

    final before = c.document!;
    final after = _parser.parse(c.exportToBytes());
    expect(after.pages.first.shapes.length, before.pages.first.shapes.length,
        reason: 'shape count / z-order changed');
    // Shape order (z-order) must be preserved id-for-id.
    expect(after.pages.first.shapes.map((s) => s.id).toList(),
        before.pages.first.shapes.map((s) => s.id).toList(),
        reason: 'z-order drift');
    final diffs = _diffPage(before.pages.first, after.pages.first);
    if (diffs.isNotEmpty) {
      // ignore: avoid_print
      print('=== EDIT SESSION DIFFS (${diffs.length}) ===\n${diffs.join('\n')}');
    }
    expect(diffs, isEmpty, reason: 'edit-session drift:\n${diffs.join('\n')}');
  });

  test('hatch fill patterns, dash-dot lines, and rotate+flip combos round-trip',
      () {
    final blank = _writer.emptyDocument(widthInches: 11, heightInches: 8.5);
    final base = _parser.parse(blank);
    var id = 1;
    final shapes = <VsdxShape>[];

    // Hatch fills (pattern > 1) carry both a foreground and background colour.
    for (final pat in const <int>[2, 10, 25, 40]) {
      shapes.add(VsdxShapeFactory.rectangle(
        id: id, pinX: 1.4 + shapes.length * 1.8, pinY: 6.5,
        width: 1.4, height: 1.0,
        fill: VsdxFill(
          foreground: const VsdxColor(0xFF3949AB),
          background: const VsdxColor(0xFFFFFDE7),
          pattern: pat,
        ),
        line: _line(0xFF1A237E),
      ));
      id++;
    }

    // Dash / dot / dash-dot line patterns.
    for (final pat in const <int>[2, 3, 4]) {
      final y = 4.5 - (id - 5) * 0.5;
      shapes.add(VsdxShapeFactory.line(
        id: id++, ax: 1.2, ay: y, bx: 5.2, by: y,
        line: VsdxLine(color: const VsdxColor(0xFF00695C), weightInches: 0.03, pattern: pat, endArrow: 4),
      ));
    }

    // A polygon that is simultaneously rotated and flipped.
    shapes.add(VsdxShapeFactory.polygon(
      id: id++, pinX: 8.5, pinY: 4.5, width: 1.6, height: 1.2,
      unit: const [Offset2D(0, 0), Offset2D(1, 0), Offset2D(0.5, 1)],
      fill: _fill(0xFFFF7043), line: _line(0xFFBF360C),
    ).copyWith(angleRad: 40 * 3.1415926535 / 180, flipX: true));

    final edited = base.replacePage(
        0, VsdxPage(id: 0, name: 'Styles', widthInches: 11, heightInches: 8.5, shapes: shapes));
    final after = _parser.parse(_writer.write(originalBytes: blank, edited: edited));
    final diffs = _diffPage(edited.pages.first, after.pages.first);
    if (diffs.isNotEmpty) {
      // ignore: avoid_print
      print('=== STYLE EDGE DIFFS (${diffs.length}) ===\n${diffs.join('\n')}');
    }
    expect(diffs, isEmpty, reason: 'style-edge drift:\n${diffs.join('\n')}');
  });

  test('re-editing a reopened document round-trips (incremental patch path)',
      () async {
    // Draw + export.
    final c = EditorController()..newDocument(widthInches: 11, heightInches: 8.5);
    addTearDown(c.dispose);
    c.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 0.9),
        3, 6);
    final id1 = c.singleSelectedId!;
    c
      ..setFillColor(const VsdxColor(0xFFE53935))
      ..setLineColor(const VsdxColor(0xFF7B1FA2))
      ..setShapeText(id1, 'First');
    final bytes1 = c.exportToBytes();

    // Reopen it in a fresh editor (the app's open-file path)…
    final c2 = EditorController();
    addTearDown(c2.dispose);
    await c2.openBytes(bytes1);

    // …then keep editing: recolour + move the existing shape (writer patches an
    // existing sheet) and add a brand-new one (writer emits a new sheet).
    c2.selectOnly(id1);
    c2
      ..setFillColor(const VsdxColor(0xFF1E88E5))
      ..moveSelectionBy(1.0, -0.5);
    c2.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.ellipse(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 1.0),
        7, 4);
    c2.setShapeText(c2.singleSelectedId!, 'Second');

    final before = c2.document!;
    final after = _parser.parse(c2.exportToBytes());
    final diffs = _diffPage(before.pages.first, after.pages.first);
    if (diffs.isNotEmpty) {
      // ignore: avoid_print
      print('=== RE-EDIT DIFFS (${diffs.length}) ===\n${diffs.join('\n')}');
    }
    expect(diffs, isEmpty, reason: 're-edit drift:\n${diffs.join('\n')}');
  });

  test('locked shape + dual arrows + line weight + text colour round-trip', () {
    final c = EditorController()..newDocument(widthInches: 11, heightInches: 8.5);
    addTearDown(c.dispose);

    c.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id, pinX: cx, pinY: cy, width: 1.8, height: 1.0),
        3, 6);
    final box = c.singleSelectedId!;
    c
      ..setShapeText(box, 'Locked')
      ..setTextColor(const VsdxColor(0xFFC62828))
      ..setTextAlign(VsdxHorzAlign.right)
      ..setFillColor(const VsdxColor(0xFFFFF59D))
      ..setLineColor(const VsdxColor(0xFFF57F17))
      ..setLineWeight(0.04)
      ..setSelectionLocked(true);

    c.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 0.8),
        8, 3);
    final dest = c.singleSelectedId!;
    c.createConnector(3.9, 6, 7.3, 3, beginTarget: box, endTarget: dest);
    c
      ..setBeginArrow(10)
      ..setEndArrow(12)
      ..setLineWeight(0.03)
      ..setLineColor(const VsdxColor(0xFF1565C0));

    final before = c.document!;
    final after = _parser.parse(c.exportToBytes());
    final diffs = _diffPage(before.pages.first, after.pages.first);
    if (diffs.isNotEmpty) {
      // ignore: avoid_print
      print('=== LOCK/ARROW DIFFS (${diffs.length}) ===\n${diffs.join('\n')}');
    }
    expect(diffs, isEmpty, reason: 'lock/arrow drift:\n${diffs.join('\n')}');
  });

  test('glued rounded orthogonal connector + waypoints + connects round-trip',
      () {
    final c = EditorController()..newDocument(widthInches: 11, heightInches: 8.5);
    addTearDown(c.dispose);

    c.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 0.8),
        2, 7);
    final a = c.singleSelectedId!;
    c.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.polygon(
            id: id, pinX: cx, pinY: cy, width: 1.4, height: 1.0,
            unit: const [
              Offset2D(0.5, 1), Offset2D(1, 0.5),
              Offset2D(0.5, 0), Offset2D(0, 0.5),
            ]),
        8, 3);
    final b = c.singleSelectedId!;

    c.createConnector(2.7, 7, 7.3, 3, beginTarget: a, endTarget: b);
    final conn = c.singleSelectedId!;
    c
      ..setConnectorRouteStyle(ConnectorRouteStyle.orthogonal)
      ..setConnectorRounded(true)
      ..setConnectorWaypoints(conn, const <Offset2D>[
        Offset2D(5.0, 7.0),
        Offset2D(5.0, 3.0),
      ]);

    final before = c.document!;
    expect(before.pages.first.connects, isNotEmpty,
        reason: 'createConnector should emit Connect rows');
    final after = _parser.parse(c.exportToBytes());
    final diffs = _diffPage(before.pages.first, after.pages.first);
    if (diffs.isNotEmpty) {
      // ignore: avoid_print
      print('=== CONNECT/ROUTE DIFFS (${diffs.length}) ===\n${diffs.join('\n')}');
    }
    expect(diffs, isEmpty, reason: 'connect/route drift:\n${diffs.join('\n')}');
  });

  test('typed shape data + insertImage media part round-trip', () {
    final c = EditorController()..newDocument(widthInches: 11, heightInches: 8.5);
    addTearDown(c.dispose);

    c.addShapeFromBuilderAt(
        (id, cx, cy) => VsdxShapeFactory.rectangle(
            id: id, pinX: cx, pinY: cy, width: 1.6, height: 0.9),
        3, 6);
    final id1 = c.singleSelectedId!;
    c.setShapeProperties(id1, const <VsdxUserProperty>[
      VsdxUserProperty(name: 'Cost', label: 'Cost', value: '42.5', type: 2),
      VsdxUserProperty(name: 'Flag', label: 'Flag', value: 'TRUE', type: 3),
      VsdxUserProperty(
          name: 'Note', label: 'Note', value: 'hello & <world>', type: 0),
    ]);

    // Minimal 1×1 PNG (transparent).
    const pngB64 =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
    final png = Uri.parse('data:image/png;base64,$pngB64').data!.contentAsBytes();
    c.insertImage(png, fileExtension: 'png', widthInches: 1.0, heightInches: 1.0);

    final before = c.document!;
    expect(before.images.all, isNotEmpty);
    final imgBefore = before.pages.first.shapes
        .where((s) => s.hasImage)
        .toList();
    expect(imgBefore, isNotEmpty);

    final after = _parser.parse(c.exportToBytes());
    final diffs = _diffPage(before.pages.first, after.pages.first);
    if (diffs.isNotEmpty) {
      // ignore: avoid_print
      print('=== PROP/IMAGE DIFFS (${diffs.length}) ===\n${diffs.join('\n')}');
    }
    expect(diffs, isEmpty, reason: 'prop/image drift:\n${diffs.join('\n')}');
    expect(after.images.all.length, before.images.all.length);
    final imgAfter = after.pages.first.shapes.where((s) => s.hasImage).toList();
    expect(imgAfter.length, imgBefore.length);
    // Bytes of the media part must survive.
    final part = imgBefore.first.imagePartName!;
    final bytesA = before.images.findByPart(part)?.bytes;
    final bytesB = after.images.findByPart(
        imgAfter.first.imagePartName!)?.bytes;
    expect(bytesB, isNotNull);
    expect(bytesB!.length, bytesA!.length);
  });
}
