import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  group('TableOps.assembleTable', () {
    test('builds a 3×3 grid with top-left cell at high Y', () {
      final table = TableOps.assembleTable(
        tableId: 10,
        pinX: 4,
        pinY: 4,
        width: 3,
        height: 3,
        rows: 3,
        cols: 3,
      );
      expect(TableOps.isTable(table), isTrue);
      expect(table.shapeKind, VsdxShapeKind.container);
      expect(table.connectionPoints, hasLength(5));
      final cells = TableOps.cellsOf(table);
      expect(cells, hasLength(9));
      expect(TableOps.dimensions(table).rows, 3);
      expect(TableOps.dimensions(table).cols, 3);

      final topLeft = cells.firstWhere(
        (c) => TableOps.cellRow(c) == 0 && TableOps.cellCol(c) == 0,
      );
      expect(topLeft.pinX, closeTo(0.5, 1e-9));
      expect(topLeft.pinY, closeTo(2.5, 1e-9));
    });
  });

  group('column / row resize', () {
    test('resizeColumnBoundary grows left column', () {
      var table = TableOps.assembleTable(
        tableId: 1,
        pinX: 0,
        pinY: 0,
        width: 4,
        height: 2,
        rows: 2,
        cols: 2,
      );
      expect(TableOps.colFractions(table), everyElement(closeTo(0.5, 1e-6)));
      table = TableOps.resizeColumnBoundary(table, 0, 1.0); // +1 inch
      final fracs = TableOps.colFractions(table);
      expect(fracs[0], closeTo(0.75, 1e-6));
      expect(fracs[1], closeTo(0.25, 1e-6));
      final left = TableOps.cellsOf(table).firstWhere(
        (c) => TableOps.cellRow(c) == 0 && TableOps.cellCol(c) == 0,
      );
      expect(left.width, closeTo(3.0, 1e-6));
    });

    test('resizeRowBoundary grows top row', () {
      var table = TableOps.assembleTable(
        tableId: 1,
        pinX: 0,
        pinY: 0,
        width: 2,
        height: 4,
        rows: 2,
        cols: 2,
      );
      table = TableOps.resizeRowBoundary(table, 0, 1.0);
      final fracs = TableOps.rowFractions(table);
      expect(fracs[0], closeTo(0.75, 1e-6));
      expect(fracs[1], closeTo(0.25, 1e-6));
    });
  });

  group('merge / unmerge', () {
    test('mergeCells spans and covers, unmerge restores', () {
      var table = TableOps.assembleTable(
        tableId: 1,
        pinX: 0,
        pinY: 0,
        width: 4,
        height: 4,
        rows: 2,
        cols: 2,
      );
      // Label a couple of cells so merge concatenates text.
      table = table.copyWith(
        children: <VsdxShape>[
          for (final c in TableOps.cellsOf(table))
            if (TableOps.cellRow(c) == 0 && TableOps.cellCol(c) == 0)
              c.copyWith(text: 'A', richText: const VsdxRichText(runs: [
                VsdxTextRun(text: 'A'),
              ]))
            else if (TableOps.cellRow(c) == 0 && TableOps.cellCol(c) == 1)
              c.copyWith(text: 'B', richText: const VsdxRichText(runs: [
                VsdxTextRun(text: 'B'),
              ]))
            else
              c,
        ],
      );
      table = TableOps.layoutCells(table);

      table = TableOps.mergeCells(
        table,
        row: 0,
        col: 0,
        rowSpan: 1,
        colSpan: 2,
      );
      final master = TableOps.cellsOf(table).firstWhere(
        (c) => TableOps.cellRow(c) == 0 && TableOps.cellCol(c) == 0,
      );
      expect(TableOps.colSpan(master), 2);
      expect(TableOps.isMerged(master), isTrue);
      expect(master.width, closeTo(4.0, 1e-6));
      expect(master.richText.plainText, contains('A'));
      expect(master.richText.plainText, contains('B'));
      final covered = TableOps.cellsOf(table).where(TableOps.isCovered);
      expect(covered, hasLength(1));

      table = TableOps.unmergeCells(table, row: 0, col: 0);
      expect(
        TableOps.cellsOf(table).where(TableOps.isCovered),
        isEmpty,
      );
      expect(
        TableOps.cellsOf(table)
            .every((c) => TableOps.colSpan(c) == 1 && TableOps.rowSpan(c) == 1),
        isTrue,
      );
    });
  });

  group('add / remove row and column', () {
    test('addRow and addColumn grow the grid', () {
      var table = TableOps.assembleTable(
        tableId: 1,
        pinX: 0,
        pinY: 0,
        width: 2,
        height: 2,
        rows: 2,
        cols: 2,
      );
      table = TableOps.addRow(table, startId: 100);
      expect(TableOps.dimensions(table).rows, 3);
      expect(TableOps.cellsOf(table), hasLength(6));

      table = TableOps.addColumn(table, startId: 200);
      expect(TableOps.dimensions(table).cols, 3);
      expect(TableOps.cellsOf(table), hasLength(9));
    });

    test('removeRow / removeColumn refuse to go below 1×1', () {
      var table = TableOps.assembleTable(
        tableId: 1,
        pinX: 0,
        pinY: 0,
        width: 2,
        height: 2,
        rows: 2,
        cols: 2,
      );
      table = TableOps.removeRow(table, 0);
      expect(TableOps.dimensions(table).rows, 1);
      table = TableOps.removeColumn(table, 1);
      expect(TableOps.dimensions(table).cols, 1);
      final same = TableOps.removeRow(table, 0);
      expect(TableOps.dimensions(same).rows, 1);
    });
  });
}
