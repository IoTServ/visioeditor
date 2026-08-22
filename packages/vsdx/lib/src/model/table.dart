/// Draw.io-style HTML table helpers.
///
/// A **table** (`User.veTable`) is a structural container whose direct
/// **cell** children (`User.veCell` + `veRow` / `veCol`) tile a grid.
/// Optional `veColWidths` / `veRowHeights` store relative sizes; `veRowSpan` /
/// `veColSpan` + `veCovered` implement merge (master keeps text, covered cells
/// stay in the model but are hidden). LibreOffice never reads `veCovered`, so
/// a save also writes Geometry `NoShow` / hollow fill via `veCoveredHidden`.
library;

import '../utils/color.dart';
import 'fill.dart';
import 'geometry.dart';
import 'line.dart';
import 'page.dart';
import 'rich_text.dart';
import 'shape.dart';
import 'shape_kind.dart';
import 'user_property.dart';

/// Pure helpers for assembling and editing grid tables.
abstract final class TableOps {
  TableOps._();

  static const String userTable = 'veTable';
  static const String userCell = 'veCell';
  static const String userRow = 'veRow';
  static const String userCol = 'veCol';
  static const String userRows = 'veRows';
  static const String userCols = 'veCols';
  static const String userColWidths = 'veColWidths';
  static const String userRowHeights = 'veRowHeights';
  static const String userRowSpan = 'veRowSpan';
  static const String userColSpan = 'veColSpan';
  static const String userCovered = 'veCovered';

  static const double minFraction = 0.05;

  static const VsdxFill _cellFill = VsdxFill(foreground: VsdxColor.white);
  static const VsdxLine _cellLine = VsdxLine(color: VsdxColor.black);
  static const VsdxFill _tableFill = VsdxFill(
    pattern: 1,
    foreground: VsdxColor(0xFFF8F8F8),
  );

  static bool isTable(VsdxShape s) {
    for (final c in s.userCells) {
      if (c.name == userTable && c.value == '1') return true;
    }
    return false;
  }

  static bool isCell(VsdxShape s) {
    for (final c in s.userCells) {
      if (c.name == userCell && c.value == '1') return true;
    }
    return false;
  }

  static bool isCovered(VsdxShape s) {
    for (final c in s.userCells) {
      if (c.name == userCovered && c.value == '1') return true;
    }
    return false;
  }

  static int? cellRow(VsdxShape s) {
    for (final c in s.userCells) {
      if (c.name == userRow) return int.tryParse(c.value ?? '');
    }
    return null;
  }

  static int? cellCol(VsdxShape s) {
    for (final c in s.userCells) {
      if (c.name == userCol) return int.tryParse(c.value ?? '');
    }
    return null;
  }

  static int rowSpan(VsdxShape s) {
    for (final c in s.userCells) {
      if (c.name == userRowSpan) {
        return (int.tryParse(c.value ?? '') ?? 1).clamp(1, 999);
      }
    }
    return 1;
  }

  static int colSpan(VsdxShape s) {
    for (final c in s.userCells) {
      if (c.name == userColSpan) {
        return (int.tryParse(c.value ?? '') ?? 1).clamp(1, 999);
      }
    }
    return 1;
  }

  static bool isMerged(VsdxShape s) =>
      isCell(s) && !isCovered(s) && (rowSpan(s) > 1 || colSpan(s) > 1);

  static List<VsdxUserCell> tableUserCells({
    required int rows,
    required int cols,
    List<double>? colFractions,
    List<double>? rowFractions,
    List<VsdxUserCell>? preserve,
  }) {
    final out = <VsdxUserCell>[
      const VsdxUserCell(name: userTable, value: '1'),
      VsdxUserCell(name: userRows, value: '$rows'),
      VsdxUserCell(name: userCols, value: '$cols'),
    ];
    if (colFractions != null) {
      out.add(VsdxUserCell(
        name: userColWidths,
        value: _encodeFractions(colFractions),
      ));
    }
    if (rowFractions != null) {
      out.add(VsdxUserCell(
        name: userRowHeights,
        value: _encodeFractions(rowFractions),
      ));
    }
    return _mergeMeta(preserve, out, ownedKeys: _tableMetaKeys);
  }

  static List<VsdxUserCell> cellUserCells({
    required int row,
    required int col,
    int rowSpan = 1,
    int colSpan = 1,
    bool covered = false,
    List<VsdxUserCell>? preserve,
  }) {
    final out = <VsdxUserCell>[
      const VsdxUserCell(name: userCell, value: '1'),
      VsdxUserCell(name: userRow, value: '$row'),
      VsdxUserCell(name: userCol, value: '$col'),
    ];
    if (rowSpan > 1) {
      out.add(VsdxUserCell(name: userRowSpan, value: '$rowSpan'));
    }
    if (colSpan > 1) {
      out.add(VsdxUserCell(name: userColSpan, value: '$colSpan'));
    }
    if (covered) {
      out.add(const VsdxUserCell(name: userCovered, value: '1'));
    }
    return _mergeMeta(preserve, out, ownedKeys: _cellMetaKeys);
  }

  /// Keep non-table User rows (hyperlink helpers, agent tags, …) across layout.
  /// Always drop owned meta keys so cleared flags (e.g. veCovered) do not stick.
  static const Set<String> _tableMetaKeys = <String>{
    userTable,
    userRows,
    userCols,
    userColWidths,
    userRowHeights,
  };

  static const Set<String> _cellMetaKeys = <String>{
    userCell,
    userRow,
    userCol,
    userRowSpan,
    userColSpan,
    userCovered,
  };

  static List<VsdxUserCell> _mergeMeta(
    List<VsdxUserCell>? preserve,
    List<VsdxUserCell> meta, {
    required Set<String> ownedKeys,
  }) {
    if (preserve == null || preserve.isEmpty) return meta;
    return <VsdxUserCell>[
      for (final c in preserve)
        if (!ownedKeys.contains(c.name)) c,
      ...meta,
    ];
  }

  /// Direct cell children of [table], sorted by row then column.
  static List<VsdxShape> cellsOf(VsdxShape table) {
    final cells = <VsdxShape>[
      for (final c in table.children)
        if (isCell(c)) c,
    ];
    cells.sort((a, b) {
      final ar = cellRow(a) ?? 0;
      final br = cellRow(b) ?? 0;
      if (ar != br) return ar.compareTo(br);
      return (cellCol(a) ?? 0).compareTo(cellCol(b) ?? 0);
    });
    return cells;
  }

  static List<VsdxShape> nonCellChildren(VsdxShape table) => <VsdxShape>[
        for (final c in table.children)
          if (!isCell(c)) c,
      ];

  /// Infer (rows, cols) from stored veRows/veCols, else from cell markers.
  static ({int rows, int cols}) dimensions(VsdxShape table) {
    var rows = 0, cols = 0;
    for (final c in table.userCells) {
      if (c.name == userRows) rows = int.tryParse(c.value ?? '') ?? 0;
      if (c.name == userCols) cols = int.tryParse(c.value ?? '') ?? 0;
    }
    if (rows >= 1 && cols >= 1) return (rows: rows, cols: cols);
    var maxR = -1, maxC = -1;
    for (final c in cellsOf(table)) {
      final r = (cellRow(c) ?? 0) + rowSpan(c) - 1;
      final col = (cellCol(c) ?? 0) + colSpan(c) - 1;
      if (r > maxR) maxR = r;
      if (col > maxC) maxC = col;
    }
    return (
      rows: maxR >= 0 ? maxR + 1 : 1,
      cols: maxC >= 0 ? maxC + 1 : 1,
    );
  }

  /// Relative column widths (sum ≈ 1).
  static List<double> colFractions(VsdxShape table) {
    final n = dimensions(table).cols;
    return _fractionsOrEqual(table, userColWidths, n);
  }

  /// Relative row heights (sum ≈ 1).
  static List<double> rowFractions(VsdxShape table) {
    final n = dimensions(table).rows;
    return _fractionsOrEqual(table, userRowHeights, n);
  }

  /// Absolute column widths in inches.
  static List<double> colWidthsInches(VsdxShape table) {
    final w = table.width.abs();
    return <double>[for (final f in colFractions(table)) f * w];
  }

  /// Absolute row heights in inches (index 0 = top).
  static List<double> rowHeightsInches(VsdxShape table) {
    final h = table.height.abs();
    return <double>[for (final f in rowFractions(table)) f * h];
  }

  /// X positions of vertical dividers in table-local inches (0 … width),
  /// excluding outer edges — length = cols-1.
  static List<double> colDividerLocals(VsdxShape table) {
    final widths = colWidthsInches(table);
    final out = <double>[];
    var x = 0.0;
    for (var i = 0; i < widths.length - 1; i++) {
      x += widths[i];
      out.add(x);
    }
    return out;
  }

  /// Y positions of horizontal dividers from the **bottom** (Y-up local),
  /// excluding outer edges — length = rows-1. Index 0 is the divider below
  /// the top row.
  static List<double> rowDividerLocalsFromBottom(VsdxShape table) {
    final heights = rowHeightsInches(table);
    final h = table.height.abs();
    final out = <double>[];
    var fromTop = 0.0;
    for (var i = 0; i < heights.length - 1; i++) {
      fromTop += heights[i];
      out.add(h - fromTop);
    }
    return out;
  }

  static List<VsdxGeometry> _rectGeometry(double w, double h) => <VsdxGeometry>[
        VsdxGeometry(commands: <VsdxPathCommand>[
          const MoveTo(0, 0),
          LineTo(w, 0),
          LineTo(w, h),
          LineTo(0, h),
          const LineTo(0, 0),
        ]),
      ];

  /// One table cell (rectangle with centred label).
  static VsdxShape cell({
    required int id,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    required int row,
    required int col,
    int rowSpan = 1,
    int colSpan = 1,
    bool covered = false,
    String? text,
    String? name,
  }) {
    final w = width.abs();
    final h = height.abs();
    final label = text ?? '';
    final sizeInches = (h * 0.28).clamp(8.0 / 72.0, 14.0 / 72.0);
    return VsdxShape(
      id: id,
      name: name ?? 'Cell.$id',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      shapeKind: VsdxShapeKind.normal,
      text: label.isEmpty ? null : label,
      richText: label.isEmpty
          ? VsdxRichText.empty
          : VsdxRichText(runs: <VsdxTextRun>[
              VsdxTextRun(
                text: label,
                charStyle: VsdxCharStyle(fontSizeInches: sizeInches),
                paraStyle: const VsdxParaStyle(
                  horizontalAlign: VsdxHorzAlign.center,
                ),
              ),
            ]),
      geometries: _rectGeometry(w, h),
      fill: _cellFill,
      line: _cellLine,
      // Persist default glue points so save→reopen keeps Edraw-compatible
      // Connection rows (writer no longer invents them when empty).
      connectionPoints: VsdxPage.defaultConnectionPoints(w, h),
      userCells: cellUserCells(
        row: row,
        col: col,
        rowSpan: rowSpan,
        colSpan: colSpan,
        covered: covered,
      ),
    );
  }

  /// Evenly / fractionally tile cells. Row 0 is at the **top** (high Y).
  static VsdxShape layoutCells(VsdxShape table) {
    final cells = cellsOf(table);
    if (cells.isEmpty) return table;
    final dim = dimensions(table);
    final colF = colFractions(table);
    final rowF = rowFractions(table);
    final w = table.width.abs();
    final h = table.height.abs();
    final colW = <double>[for (final f in colF) f * w];
    final rowH = <double>[for (final f in rowF) f * h];
    final byKey = <String, VsdxShape>{
      for (final c in cells) '${cellRow(c)}_${cellCol(c)}': c,
    };
    final laidOut = <VsdxShape>[];
    for (var r = 0; r < dim.rows; r++) {
      for (var c = 0; c < dim.cols; c++) {
        final existing = byKey['${r}_$c'];
        if (existing == null) continue;
        if (isCovered(existing)) {
          // Park covered cells at the master origin with negligible size.
          laidOut.add(
            existing.copyWith(
              pinX: 0.01,
              pinY: 0.01,
              width: 0.01,
              height: 0.01,
              geometries: preserveGeometryFlags(
                _rectGeometry(0.01, 0.01),
                existing.geometries,
              ),
              userCells: cellUserCells(
                row: r,
                col: c,
                covered: true,
                preserve: existing.userCells,
              ),
            ),
          );
          continue;
        }
        final visible = existing.libvisioCoveredHidden
            ? existing.restoreLibvisioCoveredHidden()
            : existing;
        final rs = rowSpan(visible).clamp(1, dim.rows - r);
        final cs = colSpan(visible).clamp(1, dim.cols - c);
        var cellW = 0.0, cellH = 0.0;
        for (var i = 0; i < cs; i++) {
          cellW += colW[c + i];
        }
        for (var i = 0; i < rs; i++) {
          cellH += rowH[r + i];
        }
        var x0 = 0.0;
        for (var i = 0; i < c; i++) {
          x0 += colW[i];
        }
        var yTop = 0.0;
        for (var i = 0; i < r; i++) {
          yTop += rowH[i];
        }
        final pinX = x0 + cellW / 2;
        final pinY = h - yTop - cellH / 2;
        laidOut.add(
          _cellWithFrame(
            visible,
            pinX: pinX,
            pinY: pinY,
            width: cellW,
            height: cellH,
            row: r,
            col: c,
            rowSpan: rs,
            colSpan: cs,
          ),
        );
      }
    }
    return table.copyWith(
      children: <VsdxShape>[...nonCellChildren(table), ...laidOut],
      userCells: tableUserCells(
        rows: dim.rows,
        cols: dim.cols,
        colFractions: colF,
        rowFractions: rowF,
        preserve: table.userCells,
      ),
      shapeKind: VsdxShapeKind.container,
    );
  }

  /// Build an [rows]×[cols] table. Cell ids are
  /// `[tableId+1 … tableId+rows*cols]` in row-major order.
  static VsdxShape assembleTable({
    required int tableId,
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    int rows = 3,
    int cols = 3,
    String? name,
  }) {
    final rCount = rows < 1 ? 1 : rows;
    final cCount = cols < 1 ? 1 : cols;
    final w = width.abs();
    final h = height.abs();
    final colF = List<double>.filled(cCount, 1.0 / cCount);
    final rowF = List<double>.filled(rCount, 1.0 / rCount);
    final cells = <VsdxShape>[];
    var nextId = tableId + 1;
    for (var r = 0; r < rCount; r++) {
      for (var c = 0; c < cCount; c++) {
        cells.add(
          cell(
            id: nextId++,
            pinX: 0,
            pinY: 0,
            width: 1,
            height: 1,
            row: r,
            col: c,
            text: '',
            name: 'R${r}C$c',
          ),
        );
      }
    }
    final table = VsdxShape(
      id: tableId,
      name: name ?? 'Table',
      pinX: pinX,
      pinY: pinY,
      width: w,
      height: h,
      shapeKind: VsdxShapeKind.container,
      text: name ?? 'Table',
      geometries: _rectGeometry(w, h),
      fill: _tableFill,
      line: _cellLine,
      // Match assemblePool: persist root glue so save→reopen keeps Connection
      // rows (writer no longer invents them when empty).
      connectionPoints: VsdxPage.defaultConnectionPoints(w, h),
      userCells: tableUserCells(
        rows: rCount,
        cols: cCount,
        colFractions: colF,
        rowFractions: rowF,
      ),
      children: cells,
    );
    return layoutCells(table);
  }

  /// Move the divider after column [afterCol] by [deltaInches] (page/local X).
  /// [afterCol] is 0 … cols-2.
  static VsdxShape resizeColumnBoundary(
    VsdxShape table,
    int afterCol,
    double deltaInches,
  ) {
    final dim = dimensions(table);
    if (afterCol < 0 || afterCol >= dim.cols - 1) return table;
    final w = table.width.abs();
    if (w <= 0) return table;
    final fracs = List<double>.of(colFractions(table));
    var d = deltaInches / w;
    final maxGrow = fracs[afterCol + 1] - minFraction;
    final maxShrink = fracs[afterCol] - minFraction;
    if (d > maxGrow) d = maxGrow;
    if (d < -maxShrink) d = -maxShrink;
    if (d.abs() < 1e-12) return table;
    fracs[afterCol] += d;
    fracs[afterCol + 1] -= d;
    return layoutCells(
      table.copyWith(
        userCells: tableUserCells(
          rows: dim.rows,
          cols: dim.cols,
          colFractions: _normalize(fracs),
          rowFractions: rowFractions(table),
          preserve: table.userCells,
        ),
      ),
    );
  }

  /// Move the divider below row [afterRow] (0 = below top row) by
  /// [deltaInches] in **page Y** (positive = up). Converts to growing the
  /// top-side row.
  static VsdxShape resizeRowBoundary(
    VsdxShape table,
    int afterRow,
    double deltaPageY,
  ) {
    final dim = dimensions(table);
    if (afterRow < 0 || afterRow >= dim.rows - 1) return table;
    final h = table.height.abs();
    if (h <= 0) return table;
    // Positive page-Y moves divider up → top row (afterRow) grows.
    final fracs = List<double>.of(rowFractions(table));
    var d = deltaPageY / h;
    final maxGrow = fracs[afterRow + 1] - minFraction;
    final maxShrink = fracs[afterRow] - minFraction;
    if (d > maxGrow) d = maxGrow;
    if (d < -maxShrink) d = -maxShrink;
    if (d.abs() < 1e-12) return table;
    fracs[afterRow] += d;
    fracs[afterRow + 1] -= d;
    return layoutCells(
      table.copyWith(
        userCells: tableUserCells(
          rows: dim.rows,
          cols: dim.cols,
          colFractions: colFractions(table),
          rowFractions: _normalize(fracs),
          preserve: table.userCells,
        ),
      ),
    );
  }

  /// Merge the rectangular block [row]..[row+rowSpan) × [col]..[col+colSpan).
  /// All cells in the range must exist; covered cells are not allowed as the
  /// anchor. Text from covered cells is appended to the master.
  static VsdxShape mergeCells(
    VsdxShape table, {
    required int row,
    required int col,
    required int rowSpan,
    required int colSpan,
  }) {
    final dim = dimensions(table);
    if (rowSpan < 2 && colSpan < 2) return table;
    if (row < 0 ||
        col < 0 ||
        row + rowSpan > dim.rows ||
        col + colSpan > dim.cols) {
      return table;
    }
    final byKey = <String, VsdxShape>{
      for (final c in cellsOf(table)) '${cellRow(c)}_${cellCol(c)}': c,
    };
    final master = byKey['${row}_$col'];
    if (master == null || isCovered(master)) return table;
    // Refuse if any cell in range is already a non-1×1 master or missing.
    for (var r = row; r < row + rowSpan; r++) {
      for (var c = col; c < col + colSpan; c++) {
        final cell = byKey['${r}_$c'];
        if (cell == null) return table;
        if (r == row && c == col) {
          if (TableOps.rowSpan(cell) != 1 || TableOps.colSpan(cell) != 1) {
            return table;
          }
        } else {
          if (isCovered(cell)) return table;
          if (TableOps.rowSpan(cell) != 1 || TableOps.colSpan(cell) != 1) {
            return table;
          }
        }
      }
    }
    // Concatenate rich runs (preserve bold/colour) with a single space between
    // non-empty cells. Covered cells are cleared so unmerge does not duplicate.
    final mergedRuns = <VsdxTextRun>[];
    void takeRuns(VsdxShape s) {
      final runs = s.richText.runs;
      if (runs.isNotEmpty) {
        final plain = s.richText.plainText.trim();
        if (plain.isEmpty) return;
        if (mergedRuns.isNotEmpty) {
          mergedRuns.add(const VsdxTextRun(text: ' '));
        }
        mergedRuns.addAll(runs);
        return;
      }
      final t = (s.text ?? '').trim();
      if (t.isEmpty) return;
      if (mergedRuns.isNotEmpty) {
        mergedRuns.add(const VsdxTextRun(text: ' '));
      }
      mergedRuns.add(VsdxTextRun(text: t));
    }

    takeRuns(master);
    final nextCells = <VsdxShape>[];
    for (final c in cellsOf(table)) {
      final r = cellRow(c)!;
      final cc = cellCol(c)!;
      final inBlock = r >= row &&
          r < row + rowSpan &&
          cc >= col &&
          cc < col + colSpan;
      if (!inBlock) {
        nextCells.add(c);
        continue;
      }
      if (r == row && cc == col) {
        nextCells.add(
          master.copyWith(
            userCells: cellUserCells(
              row: row,
              col: col,
              rowSpan: rowSpan,
              colSpan: colSpan,
              preserve: master.userCells,
            ),
          ),
        );
      } else {
        takeRuns(c);
        nextCells.add(
          c.copyWith(
            text: '',
            richText: VsdxRichText.empty,
            userCells: cellUserCells(
              row: r,
              col: cc,
              covered: true,
              preserve: c.userCells,
            ),
          ),
        );
      }
    }
    final idx = nextCells.indexWhere((c) => c.id == master.id);
    if (idx >= 0 && mergedRuns.isNotEmpty) {
      final m = nextCells[idx];
      final centered = <VsdxTextRun>[
        for (final r in mergedRuns)
          r.text.trim().isEmpty
              ? r
              : r.copyWith(
                  paraStyle: r.paraStyle.copyWith(
                    horizontalAlign: VsdxHorzAlign.center,
                  ),
                ),
      ];
      final combined = VsdxRichText(runs: centered).plainText;
      nextCells[idx] = m.copyWith(
        text: combined,
        richText: VsdxRichText(
          runs: centered,
          textBlock: m.richText.textBlock,
        ),
        userCells: cellUserCells(
          row: row,
          col: col,
          rowSpan: rowSpan,
          colSpan: colSpan,
          preserve: m.userCells,
        ),
      );
    }
    return layoutCells(
      table.copyWith(
        children: <VsdxShape>[...nonCellChildren(table), ...nextCells],
      ),
    );
  }

  /// Unmerge the master cell at [row],[col] (or any cell id that is merged).
  static VsdxShape unmergeCells(VsdxShape table, {required int row, required int col}) {
    final byKey = <String, VsdxShape>{
      for (final c in cellsOf(table)) '${cellRow(c)}_${cellCol(c)}': c,
    };
    final master = byKey['${row}_$col'];
    if (master == null || isCovered(master)) return table;
    final rs = rowSpan(master);
    final cs = colSpan(master);
    if (rs == 1 && cs == 1) return table;
    final nextCells = <VsdxShape>[];
    for (final c in cellsOf(table)) {
      final r = cellRow(c)!;
      final cc = cellCol(c)!;
      final inBlock =
          r >= row && r < row + rs && cc >= col && cc < col + cs;
      if (!inBlock) {
        nextCells.add(c);
        continue;
      }
      nextCells.add(
        c.copyWith(
          userCells: cellUserCells(
            row: r,
            col: cc,
            preserve: c.userCells,
          ),
        ),
      );
    }
    return layoutCells(
      table.copyWith(
        children: <VsdxShape>[...nonCellChildren(table), ...nextCells],
      ),
    );
  }

  /// Append a row at the bottom. New cell ids start at [startId].
  static VsdxShape addRow(VsdxShape table, {required int startId}) {
    final dim = dimensions(table);
    final newRow = dim.rows;
    final cells = List<VsdxShape>.of(cellsOf(table));
    var id = startId;
    for (var c = 0; c < dim.cols; c++) {
      cells.add(
        cell(
          id: id++,
          pinX: 0,
          pinY: 0,
          width: 1,
          height: 1,
          row: newRow,
          col: c,
        ),
      );
    }
    final rowF = List<double>.of(rowFractions(table));
    final share = 1.0 / (dim.rows + 1);
    for (var i = 0; i < rowF.length; i++) {
      rowF[i] *= dim.rows / (dim.rows + 1);
    }
    rowF.add(share);
    return layoutCells(
      table.copyWith(
        children: <VsdxShape>[...nonCellChildren(table), ...cells],
        userCells: tableUserCells(
          rows: dim.rows + 1,
          cols: dim.cols,
          colFractions: colFractions(table),
          rowFractions: _normalize(rowF),
          preserve: table.userCells,
        ),
      ),
    );
  }

  /// Duplicate [rowIndex] directly below itself.
  ///
  /// Cell styles, labels and nested contents are deep-cloned with fresh ids.
  /// [idMap] receives every source-to-clone mapping so page-level connection
  /// rows can be copied by the caller. A merge crossing the duplicated row is
  /// first expanded back to ordinary cells to keep the resulting grid valid.
  static VsdxShape duplicateRow(
    VsdxShape table,
    int rowIndex, {
    required int startId,
    Map<int, int>? idMap,
  }) {
    final dim = dimensions(table);
    if (rowIndex < 0 || rowIndex >= dim.rows) return table;
    final map = idMap ?? <int, int>{};
    final next = _unmergeIntersectingRows(table, rowIndex, rowIndex);
    final source = <VsdxShape>[
      for (final c in cellsOf(next))
        if (cellRow(c) == rowIndex) c,
    ];
    if (source.isEmpty) return table;

    final insertAt = rowIndex + 1;
    final kept = <VsdxShape>[];
    for (final c in cellsOf(next)) {
      final row = cellRow(c);
      if (row == null || row <= rowIndex) {
        kept.add(c);
        continue;
      }
      kept.add(
        c.copyWith(
          userCells: cellUserCells(
            row: row + 1,
            col: cellCol(c) ?? 0,
            rowSpan: rowSpan(c),
            colSpan: colSpan(c),
            covered: isCovered(c),
            preserve: c.userCells,
          ),
        ),
      );
    }

    var nextId = startId;
    final clones = <VsdxShape>[];
    for (final c in source) {
      final clone = c.withRemappedIds(() => nextId++, idMap: map);
      clones.add(
        clone.copyWith(
          userCells: cellUserCells(
            row: insertAt,
            col: cellCol(c) ?? 0,
            preserve: clone.userCells,
          ),
        ),
      );
    }
    // Cross-cell formulas can only be fully rewritten after all source ids
    // have been mapped.
    final rewrittenClones = <VsdxShape>[
      for (final c in clones) VsdxShape.rewriteSheetRefsInTree(c, map),
    ];
    final rowF = List<double>.of(rowFractions(next))
      ..insert(insertAt, rowFractions(next)[rowIndex]);
    return layoutCells(
      next.copyWith(
        children: <VsdxShape>[
          ...nonCellChildren(next),
          ...kept,
          ...rewrittenClones,
        ],
        userCells: tableUserCells(
          rows: dim.rows + 1,
          cols: dim.cols,
          colFractions: colFractions(next),
          rowFractions: _normalize(rowF),
          preserve: next.userCells,
        ),
      ),
    );
  }

  /// Append a column on the right. New cell ids start at [startId].
  static VsdxShape addColumn(VsdxShape table, {required int startId}) {
    final dim = dimensions(table);
    final newCol = dim.cols;
    final cells = List<VsdxShape>.of(cellsOf(table));
    var id = startId;
    for (var r = 0; r < dim.rows; r++) {
      cells.add(
        cell(
          id: id++,
          pinX: 0,
          pinY: 0,
          width: 1,
          height: 1,
          row: r,
          col: newCol,
        ),
      );
    }
    final colF = List<double>.of(colFractions(table));
    final share = 1.0 / (dim.cols + 1);
    for (var i = 0; i < colF.length; i++) {
      colF[i] *= dim.cols / (dim.cols + 1);
    }
    colF.add(share);
    return layoutCells(
      table.copyWith(
        children: <VsdxShape>[...nonCellChildren(table), ...cells],
        userCells: tableUserCells(
          rows: dim.rows,
          cols: dim.cols + 1,
          colFractions: _normalize(colF),
          rowFractions: rowFractions(table),
          preserve: table.userCells,
        ),
      ),
    );
  }

  /// Remove [rowIndex] (0-based). Unmerges any block that intersects the row.
  static VsdxShape removeRow(VsdxShape table, int rowIndex) {
    final dim = dimensions(table);
    if (dim.rows <= 1) return table;
    if (rowIndex < 0 || rowIndex >= dim.rows) return table;
    var next = _unmergeIntersectingRows(table, rowIndex, rowIndex);
    final kept = <VsdxShape>[];
    for (final c in cellsOf(next)) {
      final r = cellRow(c);
      if (r == null || r == rowIndex) continue;
      final nr = r > rowIndex ? r - 1 : r;
      kept.add(
        c.copyWith(
          userCells: cellUserCells(
            row: nr,
            col: cellCol(c) ?? 0,
            rowSpan: rowSpan(c),
            colSpan: colSpan(c),
            covered: isCovered(c),
            preserve: c.userCells,
          ),
        ),
      );
    }
    final rowF = List<double>.of(rowFractions(next))..removeAt(rowIndex);
    return layoutCells(
      next.copyWith(
        children: <VsdxShape>[...nonCellChildren(next), ...kept],
        userCells: tableUserCells(
          rows: dim.rows - 1,
          cols: dim.cols,
          colFractions: colFractions(next),
          rowFractions: _normalize(rowF),
          preserve: next.userCells,
        ),
      ),
    );
  }

  /// Remove [colIndex] (0-based). Unmerges any block that intersects the col.
  static VsdxShape removeColumn(VsdxShape table, int colIndex) {
    final dim = dimensions(table);
    if (dim.cols <= 1) return table;
    if (colIndex < 0 || colIndex >= dim.cols) return table;
    var next = _unmergeIntersectingCols(table, colIndex, colIndex);
    final kept = <VsdxShape>[];
    for (final c in cellsOf(next)) {
      final col = cellCol(c);
      if (col == null || col == colIndex) continue;
      final nc = col > colIndex ? col - 1 : col;
      kept.add(
        c.copyWith(
          userCells: cellUserCells(
            row: cellRow(c) ?? 0,
            col: nc,
            rowSpan: rowSpan(c),
            colSpan: colSpan(c),
            covered: isCovered(c),
            preserve: c.userCells,
          ),
        ),
      );
    }
    final colF = List<double>.of(colFractions(next))..removeAt(colIndex);
    return layoutCells(
      next.copyWith(
        children: <VsdxShape>[...nonCellChildren(next), ...kept],
        userCells: tableUserCells(
          rows: dim.rows,
          cols: dim.cols - 1,
          colFractions: _normalize(colF),
          rowFractions: rowFractions(next),
          preserve: next.userCells,
        ),
      ),
    );
  }

  static VsdxShape _unmergeIntersectingRows(
    VsdxShape table,
    int r0,
    int r1,
  ) {
    var next = table;
    for (final c in List<VsdxShape>.of(cellsOf(next))) {
      if (isCovered(c) || !isMerged(c)) continue;
      final r = cellRow(c)!;
      final rs = rowSpan(c);
      if (r + rs - 1 < r0 || r > r1) continue;
      next = unmergeCells(next, row: r, col: cellCol(c)!);
    }
    return next;
  }

  static VsdxShape _unmergeIntersectingCols(
    VsdxShape table,
    int c0,
    int c1,
  ) {
    var next = table;
    for (final c in List<VsdxShape>.of(cellsOf(next))) {
      if (isCovered(c) || !isMerged(c)) continue;
      final col = cellCol(c)!;
      final cs = colSpan(c);
      if (col + cs - 1 < c0 || col > c1) continue;
      next = unmergeCells(next, row: cellRow(c)!, col: col);
    }
    return next;
  }

  static List<double> _fractionsOrEqual(
    VsdxShape table,
    String key,
    int n,
  ) {
    if (n < 1) return const <double>[1.0];
    for (final c in table.userCells) {
      if (c.name != key) continue;
      final parsed = _decodeFractions(c.value ?? '');
      if (parsed != null && parsed.length == n) {
        return _normalize(parsed);
      }
    }
    return List<double>.filled(n, 1.0 / n);
  }

  static String _encodeFractions(List<double> f) =>
      f.map((e) => e.toStringAsFixed(6)).join(',');

  static List<double>? _decodeFractions(String raw) {
    if (raw.trim().isEmpty) return null;
    final parts = raw.split(',');
    final out = <double>[];
    for (final p in parts) {
      final v = double.tryParse(p.trim());
      if (v == null || v <= 0) return null;
      out.add(v);
    }
    return out.isEmpty ? null : out;
  }

  static List<double> _normalize(List<double> f) {
    var sum = 0.0;
    for (final v in f) {
      sum += v;
    }
    if (sum <= 0) {
      return List<double>.filled(f.length, 1.0 / f.length);
    }
    return <double>[for (final v in f) v / sum];
  }

  /// Place a cell in its tiled frame and scale nested content with the cell.
  static VsdxShape _cellWithFrame(
    VsdxShape cell, {
    required double pinX,
    required double pinY,
    required double width,
    required double height,
    required int row,
    required int col,
    required int rowSpan,
    required int colSpan,
  }) {
    final oldW = cell.width.abs() <= 1e-12 ? width : cell.width.abs();
    final oldH = cell.height.abs() <= 1e-12 ? height : cell.height.abs();
    final sx = width / oldW;
    final sy = height / oldH;
    final oldOx = cell.effectiveLocPinX;
    final oldOy = cell.effectiveLocPinY;
    final framed = cell
        .copyWith(
          pinX: pinX,
          pinY: pinY,
          width: width,
          height: height,
          geometries: preserveGeometryFlags(
            _rectGeometry(width, height),
            cell.geometries,
          ),
          userCells: cellUserCells(
            row: row,
            col: col,
            rowSpan: rowSpan,
            colSpan: colSpan,
            preserve: cell.userCells,
          ),
        )
        // Refresh Width*/Height* Connection V values after the frame resize
        // (cells are born 1×1 then laid out to their tile size).
        .recalculateLocalFormulas();
    if (cell.children.isEmpty ||
        ((sx - 1).abs() < 1e-12 && (sy - 1).abs() < 1e-12)) {
      return framed;
    }
    return framed.copyWith(
      children: <VsdxShape>[
        for (final c in cell.children)
          VsdxPage.scaleChildInFrame(
            c,
            sx,
            sy,
            oldOx,
            oldOy,
            framed.effectiveLocPinX,
            framed.effectiveLocPinY,
          ),
      ],
    );
  }
}
