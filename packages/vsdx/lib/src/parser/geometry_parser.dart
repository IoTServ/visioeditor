/// Parses every `<Section N="Geometry">` block of a shape into one
/// [VsdxGeometry] per section.
///
/// Covered row types (aligned with libvisio / MS-VSDX):
///
///  | Row `T=`            | Command              |
///  |---------------------|----------------------|
///  | `MoveTo` / `LineTo` | [MoveTo] / [LineTo]  |
///  | `RelMoveTo` / `RelLineTo` | [RelMoveTo] / [RelLineTo] |
///  | `CubBezTo` / `RelCubBezTo` | [CubBezTo] / [RelCubBezTo] |
///  | `QuadBezTo` / `RelQuadBezTo` | [QuadBezTo] / [RelQuadBezTo] |
///  | `ArcTo` / `RelArcTo` | [ArcTo] / [RelArcTo] |
///  | `EllipticalArcTo` / `RelEllipticalArcTo` | … |
///  | `Ellipse`           | [EllipseCmd]         |
///  | `PolylineTo` / `RelPolylineTo` | [PolylineTo] |
///  | `InfiniteLine` / `RelInfiniteLine` | [InfiniteLineCmd] |
///  | `SplineStart` / `SplineKnot` (+ Rel*) | … |
///  | `NURBSTo` / `RelNURBSTo` | [NurbsTo]        |
library;

import 'package:logging/logging.dart';
import 'package:xml/xml.dart';

import '../model/geometry.dart';
import 'cell_helpers.dart';

final _log = Logger('vsdx.parser.geometry');

class GeometryParser {
  const GeometryParser();

  /// Returns one [VsdxGeometry] per `Geometry` section found directly under
  /// [shape] (no recursion into sub-shapes).
  List<VsdxGeometry> parse(XmlElement shape) {
    final out = <VsdxGeometry>[];
    for (final el in shape.childElements) {
      if (el.name.local != 'Section') continue;
      if (el.getAttribute('N') != 'Geometry') continue;
      out.add(_readSection(el));
    }
    return out;
  }

  VsdxGeometry _readSection(XmlElement section) {
    final commands = <VsdxPathCommand>[];
    final commandFormulas = <Map<String, String>>[];
    final rowIndices = <int>[];
    final deletedRowIndices = <int>{};
    final definedFlagCells = <String>{};
    final ix = int.tryParse(section.getAttribute('IX') ?? '') ?? 0;
    final sectionDeleted = section.getAttribute('Del') == '1';
    var noFill = false;
    var noLine = false;
    var noShow = false;
    var noSnap = false;
    var noQuickDrag = false;

    for (final child in section.childElements) {
      switch (child.name.local) {
        case 'Cell':
          final n = child.getAttribute('N');
          final v = child.getAttribute('V');
          final f = (child.getAttribute('F') ?? '').trim().toUpperCase();
          // F=Inh means "use master" — do not treat as a local override.
          final inherits = f == 'INH' || f.startsWith('INH(');
          switch (n) {
            case 'NoFill':
              // F=Inh → leave default false; master merge supplies the value.
              if (!inherits) {
                noFill = v == '1';
                definedFlagCells.add('NoFill');
              }
            case 'NoLine':
              if (!inherits) {
                noLine = v == '1';
                definedFlagCells.add('NoLine');
              }
            case 'NoShow':
              if (!inherits) {
                noShow = v == '1';
                definedFlagCells.add('NoShow');
              }
            case 'NoSnap':
              if (!inherits) {
                noSnap = v == '1';
                definedFlagCells.add('NoSnap');
              }
            case 'NoQuickDrag':
              if (!inherits) {
                noQuickDrag = v == '1';
                definedFlagCells.add('NoQuickDrag');
              }
          }
        case 'Row':
          final rowIx = int.tryParse(child.getAttribute('IX') ?? '');
          // A `Del="1"` row deletes the same-IX row inherited from the master
          // (MS-VSDX) — record it as a deletion rather than a spurious command.
          if (child.getAttribute('Del') == '1') {
            if (rowIx != null) deletedRowIndices.add(rowIx);
            continue;
          }
          final cmd = _readRow(child);
          if (cmd != null) {
            commands.add(cmd);
            commandFormulas.add(_readRowFormulas(child));
            rowIndices.add(rowIx ?? (rowIndices.isEmpty ? 1 : rowIndices.last + 1));
          }
      }
    }
    return VsdxGeometry(
      commands: List.unmodifiable(commands),
      commandFormulas: List.unmodifiable(commandFormulas),
      noFill: noFill,
      noLine: noLine,
      noShow: noShow,
      noSnap: noSnap,
      noQuickDrag: noQuickDrag,
      ix: ix,
      rowIndices: List.unmodifiable(rowIndices),
      deletedRowIndices: Set.unmodifiable(deletedRowIndices),
      definedFlagCells: Set.unmodifiable(definedFlagCells),
      deleted: sectionDeleted,
    );
  }

  /// Merge master (inherited) geometry with an instance's geometry the way
  /// libvisio / MS-VSDX do: sections match by `IX`; within a matched section
  /// rows match by row `IX` (instance overrides master, `Del` removes the
  /// inherited row); section flag cells inherit from the master unless the
  /// instance explicitly declared them; a section-level `Del` drops the whole
  /// inherited section. Sections/rows unique to either side are kept.
  static List<VsdxGeometry> mergeInherited(
    List<VsdxGeometry> master,
    List<VsdxGeometry> instance,
  ) {
    final masterByIx = <int, VsdxGeometry>{};
    for (final g in master) {
      masterByIx[g.ix] = g;
    }
    final instanceIxs = <int>{for (final g in instance) g.ix};
    final out = <VsdxGeometry>[];

    for (final inst in instance) {
      final m = masterByIx[inst.ix];
      if (inst.deleted) continue; // whole inherited section removed
      if (m == null || m.rowIndices.length != m.commands.length) {
        out.add(_stripDeletedRows(inst));
        continue;
      }
      out.add(_mergeSection(m, inst));
    }
    // Master sections the instance never mentioned are inherited unchanged.
    for (final m in master) {
      if (!instanceIxs.contains(m.ix)) out.add(m);
    }
    out.sort((a, b) => a.ix.compareTo(b.ix));
    return List.unmodifiable(out);
  }

  static VsdxGeometry _stripDeletedRows(VsdxGeometry g) {
    if (g.deletedRowIndices.isEmpty) return g;
    // No master to delete from; deletions simply no-op (rows already absent).
    return g;
  }

  static VsdxGeometry _mergeSection(VsdxGeometry m, VsdxGeometry inst) {
    // rowIX -> (command, formulas), seeded from master then overridden.
    final rows = <int, ({VsdxPathCommand cmd, Map<String, String> f})>{};
    final masterIxs = m.rowIndices.toSet();
    for (var i = 0; i < m.commands.length; i++) {
      rows[m.rowIndices[i]] = (cmd: m.commands[i], f: m.formulasAt(i));
    }
    final instHasRowIx = inst.rowIndices.length == inst.commands.length;
    for (var i = 0; i < inst.commands.length; i++) {
      final rowIx = instHasRowIx ? inst.rowIndices[i] : (1000000 + i);
      final instCmd = inst.commands[i];
      final instF = inst.formulasAt(i);
      final masterRow = rows[rowIx];
      if (masterRow != null && instF.values.any(isInhFormula)) {
        // F=Inh cells keep master coordinates; real formulas still override.
        rows[rowIx] = (
          cmd: _blendInhCoords(masterRow.cmd, instCmd, instF),
          f: _mergeRowFormulas(masterRow.f, instF),
        );
      } else {
        rows[rowIx] = (cmd: instCmd, f: instF);
      }
    }
    for (final d in inst.deletedRowIndices) {
      rows.remove(d);
    }
    final ordered = rows.keys.toList()..sort();
    bool flag(String name, bool instVal, bool masterVal) =>
        inst.definedFlagCells.contains(name) ? instVal : masterVal;
    return VsdxGeometry(
      commands: List.unmodifiable([for (final k in ordered) rows[k]!.cmd]),
      commandFormulas:
          List.unmodifiable([for (final k in ordered) rows[k]!.f]),
      noFill: flag('NoFill', inst.noFill, m.noFill),
      noLine: flag('NoLine', inst.noLine, m.noLine),
      noShow: flag('NoShow', inst.noShow, m.noShow),
      noSnap: flag('NoSnap', inst.noSnap, m.noSnap),
      noQuickDrag: flag('NoQuickDrag', inst.noQuickDrag, m.noQuickDrag),
      ix: inst.ix,
      rowIndices: List.unmodifiable(ordered),
      deletedRowIndices: Set.unmodifiable(
          inst.deletedRowIndices.where(masterIxs.contains)),
      definedFlagCells: {...m.definedFlagCells, ...inst.definedFlagCells},
    );
  }

  /// Keep master formulas for Inh cells; take instance formulas otherwise.
  static Map<String, String> _mergeRowFormulas(
    Map<String, String> master,
    Map<String, String> inst,
  ) {
    final out = <String, String>{...master};
    for (final e in inst.entries) {
      if (isInhFormula(e.value)) continue;
      out[e.key] = e.value;
    }
    return Map.unmodifiable(out);
  }

  /// For each cell marked `F=Inh` on the instance, take the master's coordinate.
  static VsdxPathCommand _blendInhCoords(
    VsdxPathCommand master,
    VsdxPathCommand inst,
    Map<String, String> instF,
  ) {
    double pick(String name, double masterVal, double instVal) =>
        isInhFormula(instF[name]) ? masterVal : instVal;

    if (master is MoveTo && inst is MoveTo) {
      return MoveTo(pick('X', master.x, inst.x), pick('Y', master.y, inst.y));
    }
    if (master is LineTo && inst is LineTo) {
      return LineTo(pick('X', master.x, inst.x), pick('Y', master.y, inst.y));
    }
    if (master is RelMoveTo && inst is RelMoveTo) {
      return RelMoveTo(
          pick('X', master.fx, inst.fx), pick('Y', master.fy, inst.fy));
    }
    if (master is RelLineTo && inst is RelLineTo) {
      return RelLineTo(
          pick('X', master.fx, inst.fx), pick('Y', master.fy, inst.fy));
    }
    if (master is ArcTo && inst is ArcTo) {
      return ArcTo(
        x: pick('X', master.x, inst.x),
        y: pick('Y', master.y, inst.y),
        bow: pick('A', master.bow, inst.bow),
      );
    }
    if (master is CubBezTo && inst is CubBezTo) {
      return CubBezTo(
        x: pick('X', master.x, inst.x),
        y: pick('Y', master.y, inst.y),
        x1: pick('A', master.x1, inst.x1),
        y1: pick('B', master.y1, inst.y1),
        x2: pick('C', master.x2, inst.x2),
        y2: pick('D', master.y2, inst.y2),
      );
    }
    if (master is QuadBezTo && inst is QuadBezTo) {
      return QuadBezTo(
        x: pick('X', master.x, inst.x),
        y: pick('Y', master.y, inst.y),
        x1: pick('A', master.x1, inst.x1),
        y1: pick('B', master.y1, inst.y1),
      );
    }
    if (master is EllipticalArcTo && inst is EllipticalArcTo) {
      return EllipticalArcTo(
        x: pick('X', master.x, inst.x),
        y: pick('Y', master.y, inst.y),
        controlX: pick('A', master.controlX, inst.controlX),
        controlY: pick('B', master.controlY, inst.controlY),
        angle: pick('C', master.angle, inst.angle),
        eccentricity: pick('D', master.eccentricity, inst.eccentricity),
      );
    }
    if (master is RelCubBezTo && inst is RelCubBezTo) {
      return RelCubBezTo(
        fx: pick('X', master.fx, inst.fx),
        fy: pick('Y', master.fy, inst.fy),
        fx1: pick('A', master.fx1, inst.fx1),
        fy1: pick('B', master.fy1, inst.fy1),
        fx2: pick('C', master.fx2, inst.fx2),
        fy2: pick('D', master.fy2, inst.fy2),
      );
    }
    if (master is RelQuadBezTo && inst is RelQuadBezTo) {
      return RelQuadBezTo(
        fx: pick('X', master.fx, inst.fx),
        fy: pick('Y', master.fy, inst.fy),
        fx1: pick('A', master.fx1, inst.fx1),
        fy1: pick('B', master.fy1, inst.fy1),
      );
    }
    if (master is RelArcTo && inst is RelArcTo) {
      return RelArcTo(
        fx: pick('X', master.fx, inst.fx),
        fy: pick('Y', master.fy, inst.fy),
        fbow: pick('A', master.fbow, inst.fbow),
      );
    }
    if (master is RelEllipticalArcTo && inst is RelEllipticalArcTo) {
      return RelEllipticalArcTo(
        fx: pick('X', master.fx, inst.fx),
        fy: pick('Y', master.fy, inst.fy),
        fcx: pick('A', master.fcx, inst.fcx),
        fcy: pick('B', master.fcy, inst.fcy),
        angle: pick('C', master.angle, inst.angle),
        eccentricity: pick('D', master.eccentricity, inst.eccentricity),
      );
    }
    if (master is EllipseCmd && inst is EllipseCmd) {
      return EllipseCmd(
        cx: pick('X', master.cx, inst.cx),
        cy: pick('Y', master.cy, inst.cy),
        aX: pick('A', master.aX, inst.aX),
        aY: pick('B', master.aY, inst.aY),
        bX: pick('C', master.bX, inst.bX),
        bY: pick('D', master.bY, inst.bY),
      );
    }
    if (master is InfiniteLineCmd &&
        inst is InfiniteLineCmd &&
        master.relative == inst.relative) {
      return InfiniteLineCmd(
        x: pick('X', master.x, inst.x),
        y: pick('Y', master.y, inst.y),
        a: pick('A', master.a, inst.a),
        b: pick('B', master.b, inst.b),
        relative: master.relative,
      );
    }
    if (master is PolylineTo &&
        inst is PolylineTo &&
        master.relative == inst.relative) {
      final useMasterVerts = isInhFormula(instF['A']);
      return PolylineTo(
        x: pick('X', master.x, inst.x),
        y: pick('Y', master.y, inst.y),
        vertices: useMasterVerts ? master.vertices : inst.vertices,
        relative: master.relative,
        vertsRelative:
            useMasterVerts ? master.vertsRelative : inst.vertsRelative,
        vertsYRelative:
            useMasterVerts ? master.vertsYRelative : inst.vertsYRelative,
      );
    }
    if (master is SplineStart &&
        inst is SplineStart &&
        master.relative == inst.relative) {
      return SplineStart(
        x: pick('X', master.x, inst.x),
        y: pick('Y', master.y, inst.y),
        a: pick('A', master.a, inst.a),
        b: pick('B', master.b, inst.b),
        c: pick('C', master.c, inst.c),
        degree: isInhFormula(instF['D']) ? master.degree : inst.degree,
        relative: master.relative,
      );
    }
    if (master is SplineKnot &&
        inst is SplineKnot &&
        master.relative == inst.relative) {
      return SplineKnot(
        x: pick('X', master.x, inst.x),
        y: pick('Y', master.y, inst.y),
        knot: pick('A', master.knot, inst.knot),
        relative: master.relative,
      );
    }
    if (master is NurbsTo &&
        inst is NurbsTo &&
        master.relative == inst.relative) {
      final useMasterCps = isInhFormula(instF['E']);
      return NurbsTo(
        x: pick('X', master.x, inst.x),
        y: pick('Y', master.y, inst.y),
        controlPoints:
            useMasterCps ? master.controlPoints : inst.controlPoints,
        weights: useMasterCps ? master.weights : inst.weights,
        knots: useMasterCps ? master.knots : inst.knots,
        degree: useMasterCps ? master.degree : inst.degree,
        relative: master.relative,
        cpRelative: useMasterCps ? master.cpRelative : inst.cpRelative,
        cpYRelative: useMasterCps ? master.cpYRelative : inst.cpYRelative,
      );
    }
    return inst;
  }

  /// Collect per-cell `F=` on a Geometry row (`Scratch.X1`, `Width*0.5`, …).
  static Map<String, String> _readRowFormulas(XmlElement row) {
    final out = <String, String>{};
    for (final child in row.childElements) {
      if (child.name.local != 'Cell') continue;
      final n = child.getAttribute('N');
      final f = child.getAttribute('F');
      if (n == null || n.isEmpty) continue;
      if (f == null || f.isEmpty || f == 'No Formula') continue;
      out[n] = f;
    }
    return Map.unmodifiable(out);
  }

  VsdxPathCommand? _readRow(XmlElement row) {
    final t = row.getAttribute('T');
    switch (t) {
      case 'MoveTo':
        return MoveTo(
          readLengthInches(row, 'X') ?? 0,
          readLengthInches(row, 'Y') ?? 0,
        );
      case 'LineTo':
        return LineTo(
          readLengthInches(row, 'X') ?? 0,
          readLengthInches(row, 'Y') ?? 0,
        );
      case 'RelMoveTo':
        return RelMoveTo(
          _rawDouble(row, 'X') ?? 0,
          _rawDouble(row, 'Y') ?? 0,
        );
      case 'RelLineTo':
        return RelLineTo(
          _rawDouble(row, 'X') ?? 0,
          _rawDouble(row, 'Y') ?? 0,
        );
      case 'CubBezTo':
        // Absolute cubic Bézier: A/B = control 1, C/D = control 2, X/Y = end,
        // all in shape-local inches.
        return CubBezTo(
          x: readLengthInches(row, 'X') ?? 0,
          y: readLengthInches(row, 'Y') ?? 0,
          x1: readLengthInches(row, 'A') ?? 0,
          y1: readLengthInches(row, 'B') ?? 0,
          x2: readLengthInches(row, 'C') ?? 0,
          y2: readLengthInches(row, 'D') ?? 0,
        );
      case 'RelCubBezTo':
        // Relative cubic Bézier: every coordinate is a fraction of the shape's
        // width (X/A/C) or height (Y/B/D), so read the raw V without unit
        // normalisation (like RelMoveTo / RelLineTo).
        return RelCubBezTo(
          fx: _rawDouble(row, 'X') ?? 0,
          fy: _rawDouble(row, 'Y') ?? 0,
          fx1: _rawDouble(row, 'A') ?? 0,
          fy1: _rawDouble(row, 'B') ?? 0,
          fx2: _rawDouble(row, 'C') ?? 0,
          fy2: _rawDouble(row, 'D') ?? 0,
        );
      case 'QuadBezTo':
        // Absolute quadratic Bézier: A/B = control point, X/Y = end (inches).
        return QuadBezTo(
          x: readLengthInches(row, 'X') ?? 0,
          y: readLengthInches(row, 'Y') ?? 0,
          x1: readLengthInches(row, 'A') ?? 0,
          y1: readLengthInches(row, 'B') ?? 0,
        );
      case 'RelQuadBezTo':
        // Relative quadratic Bézier: X/A are fractions of width, Y/B of height.
        return RelQuadBezTo(
          fx: _rawDouble(row, 'X') ?? 0,
          fy: _rawDouble(row, 'Y') ?? 0,
          fx1: _rawDouble(row, 'A') ?? 0,
          fy1: _rawDouble(row, 'B') ?? 0,
        );
      case 'ArcTo':
        return ArcTo(
          x: readLengthInches(row, 'X') ?? 0,
          y: readLengthInches(row, 'Y') ?? 0,
          bow: readLengthInches(row, 'A') ?? 0,
        );
      case 'RelArcTo':
        // X/Y/A are fractions of Width/Height (same convention as RelMoveTo).
        return RelArcTo(
          fx: _rawDouble(row, 'X') ?? 0,
          fy: _rawDouble(row, 'Y') ?? 0,
          fbow: _rawDouble(row, 'A') ?? 0,
        );
      case 'EllipticalArcTo':
        return EllipticalArcTo(
          x: readLengthInches(row, 'X') ?? 0,
          y: readLengthInches(row, 'Y') ?? 0,
          controlX: readLengthInches(row, 'A') ?? 0,
          controlY: readLengthInches(row, 'B') ?? 0,
          angle: readAngleRadians(row, 'C') ?? 0,
          eccentricity: _rawDouble(row, 'D') ?? 1,
        );
      case 'RelEllipticalArcTo':
        // X/Y (end) and A/B (on-arc control point) are fractions of the
        // shape's width/height; C (angle, radians) and D (eccentricity) are
        // absolute, so read them verbatim.
        return RelEllipticalArcTo(
          fx: _rawDouble(row, 'X') ?? 0,
          fy: _rawDouble(row, 'Y') ?? 0,
          fcx: _rawDouble(row, 'A') ?? 0,
          fcy: _rawDouble(row, 'B') ?? 0,
          angle: readAngleRadians(row, 'C') ?? 0,
          eccentricity: _rawDouble(row, 'D') ?? 1,
        );
      case 'Ellipse':
        return EllipseCmd(
          cx: readLengthInches(row, 'X') ?? 0,
          cy: readLengthInches(row, 'Y') ?? 0,
          aX: readLengthInches(row, 'A') ?? 0,
          aY: readLengthInches(row, 'B') ?? 0,
          bX: readLengthInches(row, 'C') ?? 0,
          bY: readLengthInches(row, 'D') ?? 0,
        );
      case 'PolylineTo':
        final poly = _parsePolylineFull(_cellValue(row, 'A'));
        // Formula flags scale interior verts per axis; X/Y stay local inches
        // (libvisio collectPolylineTo).
        return PolylineTo(
          x: readLengthInches(row, 'X') ?? 0,
          y: readLengthInches(row, 'Y') ?? 0,
          vertices: poly.vertices,
          vertsRelative: poly.xType == 0,
          vertsYRelative: poly.yType == 0,
        );
      case 'RelPolylineTo':
        final poly = _parsePolylineFull(_cellValue(row, 'A'));
        // Rel* only makes the X/Y endpoint fractional; POLYLINE xType/yType
        // still control whether interior verts are % or local inches.
        return PolylineTo(
          x: _rawDouble(row, 'X') ?? 0,
          y: _rawDouble(row, 'Y') ?? 0,
          vertices: poly.vertices,
          relative: true,
          vertsRelative: poly.xType == 0,
          vertsYRelative: poly.yType == 0,
        );
      case 'InfiniteLine':
        return InfiniteLineCmd(
          x: readLengthInches(row, 'X') ?? 0,
          y: readLengthInches(row, 'Y') ?? 0,
          a: readLengthInches(row, 'A') ?? 0,
          b: readLengthInches(row, 'B') ?? 0,
        );
      case 'RelInfiniteLine':
        return InfiniteLineCmd(
          x: _rawDouble(row, 'X') ?? 0,
          y: _rawDouble(row, 'Y') ?? 0,
          a: _rawDouble(row, 'A') ?? 0,
          b: _rawDouble(row, 'B') ?? 0,
          relative: true,
        );
      case 'SplineStart':
        return SplineStart(
          x: readLengthInches(row, 'X') ?? 0,
          y: readLengthInches(row, 'Y') ?? 0,
          a: _rawDouble(row, 'A') ?? 0,
          b: _rawDouble(row, 'B') ?? 4,
          c: _rawDouble(row, 'C') ?? 1,
          degree: (_rawDouble(row, 'D') ?? 3).toInt(),
        );
      case 'RelSplineStart':
        return SplineStart(
          x: _rawDouble(row, 'X') ?? 0,
          y: _rawDouble(row, 'Y') ?? 0,
          a: _rawDouble(row, 'A') ?? 0,
          b: _rawDouble(row, 'B') ?? 4,
          c: _rawDouble(row, 'C') ?? 1,
          degree: (_rawDouble(row, 'D') ?? 3).toInt(),
          relative: true,
        );
      case 'SplineKnot':
        return SplineKnot(
          x: readLengthInches(row, 'X') ?? 0,
          y: readLengthInches(row, 'Y') ?? 0,
          knot: _rawDouble(row, 'A') ?? 0,
        );
      case 'RelSplineKnot':
        return SplineKnot(
          x: _rawDouble(row, 'X') ?? 0,
          y: _rawDouble(row, 'Y') ?? 0,
          knot: _rawDouble(row, 'A') ?? 0,
          relative: true,
        );
      case 'NURBSTo':
        return _nurbsFromRow(row, relativeRow: false);
      case 'RelNURBSTo':
        return _nurbsFromRow(row, relativeRow: true);
      default:
        // Drop silently-but-noisily for now; the path will fall back to its
        // bounding box.
        _log.fine(() => 'Unsupported Geometry row type: $t');
        return null;
    }
  }

  /// Parse `POLYLINE(xType, yType, x0, y0, …)` into vertices + flags.
  _PolylineArgs _parsePolylineFull(String? raw) {
    final nums = _extractFormulaArgs(raw, 'POLYLINE');
    if (nums.length < 4) return _PolylineArgs.empty;
    final xType = nums[0].toInt();
    final yType = nums[1].toInt();
    final out = <Offset2D>[];
    for (var i = 2; i + 1 < nums.length; i += 2) {
      out.add(Offset2D(nums[i], nums[i + 1]));
    }
    return _PolylineArgs(
      vertices: List.unmodifiable(out),
      xType: xType,
      yType: yType,
    );
  }

  /// Build [NurbsTo] from a Geometry row, assembling A/B/C/D with E like
  /// libvisio `collectNURBSTo`.
  NurbsTo _nurbsFromRow(XmlElement row, {required bool relativeRow}) {
    final parsed = _parseNurbsFull(_cellValue(row, 'E'));
    final relative = relativeRow;
    // RelNURBSTo: endpoint is fractional. NURBSTo: endpoint is local inches
    // even when the formula's CPs are percentage (libvisio scales only CPs).
    final x = relative
        ? (_rawDouble(row, 'X') ?? 0)
        : (readLengthInches(row, 'X') ?? 0);
    final y = relative
        ? (_rawDouble(row, 'Y') ?? 0)
        : (readLengthInches(row, 'Y') ?? 0);
    final knotFirst = _rawDouble(row, 'C');
    final knotSecondLast = _rawDouble(row, 'A');
    final weightFirst = _rawDouble(row, 'D');
    final weightLast = _rawDouble(row, 'B');
    final knots = <double>[
      if (knotFirst != null) knotFirst,
      ...parsed.knots,
      if (knotSecondLast != null) knotSecondLast,
      if (parsed.knotLast != null) parsed.knotLast!,
    ];
    final weights = <double>[
      if (weightFirst != null) weightFirst,
      ...parsed.weights,
      if (weightLast != null) weightLast,
    ];
    return NurbsTo(
      x: x,
      y: y,
      controlPoints: parsed.controlPoints,
      weights: List.unmodifiable(weights),
      knots: List.unmodifiable(knots),
      degree: parsed.degree,
      relative: relative,
      // RelNURBSTo endpoint is fractional; CP scaling follows formula flags only.
      cpRelative: parsed.xType == 0,
      cpYRelative: parsed.yType == 0,
    );
  }

  /// Parse `NURBS(knotLast, degree, xType, yType, x1, y1, knot1, weight1, …)`.
  ///
  /// Returns interior CPs / per-CP knots & weights from E only; callers
  /// prepend/append A/B/C/D (libvisio). Args 2–3 are flags, not the endpoint.
  _NurbsArgs _parseNurbsFull(String? raw) {
    final nums = _extractFormulaArgs(raw, 'NURBS');
    if (nums.length < 4) return _NurbsArgs.empty;
    final knotLast = nums[0];
    final degree = nums[1].toInt().clamp(1, 7);
    final xType = nums[2].toInt();
    final yType = nums[3].toInt();
    final points = <Offset2D>[];
    final weights = <double>[];
    final knots = <double>[];
    for (var i = 4; i + 3 < nums.length; i += 4) {
      points.add(Offset2D(nums[i], nums[i + 1]));
      knots.add(nums[i + 2]);
      weights.add(nums[i + 3]);
    }
    return _NurbsArgs(
      controlPoints: List.unmodifiable(points),
      weights: List.unmodifiable(weights),
      knots: List.unmodifiable(knots),
      degree: degree,
      xType: xType,
      yType: yType,
      knotLast: knotLast,
    );
  }

  /// Generic `FN(arg1, arg2, ...)` numeric argument extractor. Whitespace
  /// inside the parens is ignored; non-numeric tokens contribute `0`.
  List<double> _extractFormulaArgs(String? raw, String fn) {
    if (raw == null) return const <double>[];
    final s = raw.trim();
    final upper = s.toUpperCase();
    if (!upper.startsWith(fn.toUpperCase())) {
      // Fallback: comma-separated bare numbers (some files omit the
      // `NURBS(`/`POLYLINE(` wrapper after Visio's auto-rewrite).
      return _parseCsvNumbers(s);
    }
    final open = s.indexOf('(');
    final close = s.lastIndexOf(')');
    if (open < 0 || close <= open) return const <double>[];
    return _parseCsvNumbers(s.substring(open + 1, close));
  }

  List<double> _parseCsvNumbers(String s) {
    final out = <double>[];
    for (final tok in s.split(',')) {
      final v = double.tryParse(tok.trim());
      if (v != null) out.add(v);
    }
    return out;
  }

  String? _cellValue(XmlElement row, String name) {
    for (final el in row.childElements) {
      if (el.name.local == 'Cell' && el.getAttribute('N') == name) {
        return el.getAttribute('F') ?? el.getAttribute('V');
      }
    }
    return null;
  }

  /// Read the literal numeric `V=` without any unit normalisation — useful
  /// for `RelXxxTo` where the value is a pure fraction (0..1).
  double? _rawDouble(XmlElement row, String name) {
    for (final el in row.childElements) {
      if (el.name.local == 'Cell' && el.getAttribute('N') == name) {
        return double.tryParse(el.getAttribute('V') ?? '');
      }
    }
    return null;
  }
}

class _PolylineArgs {
  const _PolylineArgs({
    required this.vertices,
    required this.xType,
    required this.yType,
  });

  static const _PolylineArgs empty = _PolylineArgs(
    vertices: <Offset2D>[],
    xType: 1,
    yType: 1,
  );

  final List<Offset2D> vertices;
  final int xType;
  final int yType;
}

class _NurbsArgs {
  const _NurbsArgs({
    required this.controlPoints,
    required this.weights,
    required this.knots,
    required this.degree,
    this.xType = 1,
    this.yType = 1,
    this.knotLast,
  });

  static const _NurbsArgs empty = _NurbsArgs(
    controlPoints: <Offset2D>[],
    weights: <double>[],
    knots: <double>[],
    degree: 3,
  );

  final List<Offset2D> controlPoints;
  final List<double> weights;
  final List<double> knots;
  final int degree;
  final int xType;
  final int yType;
  final double? knotLast;
}
