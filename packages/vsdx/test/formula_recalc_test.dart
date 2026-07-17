import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  group('evaluateFormula locals', () {
    test('resolves Width/Height and arithmetic', () {
      final locals = <String, double>{'Width': 4, 'Height': 2};
      expect(evaluateFormula('Width/2', locals: locals), closeTo(2, 1e-9));
      expect(evaluateFormula('Height*0.5', locals: locals), closeTo(1, 1e-9));
      expect(
        evaluateFormula('MIN(Width/2,Height/2)', locals: locals),
        closeTo(1, 1e-9),
      );
      expect(
        evaluateFormula('GUARD(Width*0.5)', locals: locals),
        closeTo(2, 1e-9),
      );
    });

    test('resolves Begin/End midpoint', () {
      final locals = <String, double>{
        'BeginX': 1,
        'EndX': 5,
        'BeginY': 2,
        'EndY': 6,
      };
      expect(
        evaluateFormula('(BeginX+EndX)/2', locals: locals),
        closeTo(3, 1e-9),
      );
      expect(
        evaluateFormula('(BeginY+EndY)/2', locals: locals),
        closeTo(4, 1e-9),
      );
    });

    test('returns null for cross-sheet / SETATREF / unbound names', () {
      expect(evaluateFormula('Sheet.5!PinX'), isNull);
      expect(evaluateFormula('SETATREF(Controls.TextPosition)'), isNull);
      expect(evaluateFormula('Width/2'), isNull);
      expect(
        evaluateFormula('Scratch.X1', locals: {'Width': 2}),
        isNull,
      );
      expect(
        evaluateFormula('Scratch.X1', locals: {'Scratch.X1': 1.25}),
        closeTo(1.25, 1e-9),
      );
    });

    test('SETATREF recalc peels via cellLookup', () {
      expect(
        evaluateFormula(
          'SETATREF(User.Size)*0.25',
          cellLookup: (ref) =>
              ref.toUpperCase() == 'USER.SIZE' ? 5.0 : null,
        ),
        closeTo(1.25, 1e-9),
      );
      expect(
        evaluateFormula(
          'SETATREF(User.Size,SETATREFEVAL(SETATREFEXPR()/0.25),TRUE)',
          cellLookup: (ref) =>
              ref.toUpperCase() == 'USER.SIZE' ? 5.0 : null,
        ),
        closeTo(0, 1e-9), // ignore_eval
      );
    });

    test('computeSetAtRefRedirect evaluates SETATREFEVAL', () {
      final r = computeSetAtRefRedirect(
        'SETATREF(User.Size,SETATREFEVAL(SETATREFEXPR()/0.25))',
        1.25,
      );
      expect(r, isNotNull);
      expect(r!.reference, 'User.Size');
      expect(r.value, closeTo(5, 1e-9));

      final offset = computeSetAtRefRedirect(
        'SETATREF(User.DeltaX,SETATREFEVAL(SETATREFEXPR()-PinX))',
        10,
        locals: {'PinX': 3},
      );
      expect(offset!.reference, 'User.DeltaX');
      expect(offset.value, closeTo(7, 1e-9));

      final plain = computeSetAtRefRedirect(
        'SETATREF(Controls.TextPosition)',
        1.5,
      );
      expect(plain!.reference, 'Controls.TextPosition');
      expect(plain.value, closeTo(1.5, 1e-9));
    });

    test('computeSetAtRefRedirect follows SETATREF chains', () {
      final formulas = <String, String>{
        'User.Mid': 'SETATREF(User.Final)',
        'User.Final': 'GUARD(1)',
      };
      final r = computeSetAtRefRedirect(
        'SETATREF(User.Mid,SETATREFEVAL(SETATREFEXPR()/2))',
        10,
        formulaOfRef: (ref) => formulas[ref],
      );
      expect(r!.reference, 'User.Final');
      expect(r.value, closeTo(5, 1e-9));
    });

    test('composite SETATREF+arith evaluates on recalc', () {
      expect(
        evaluateFormula(
          'SETATREF(User.DeltaX)+Width*0.5',
          locals: {'Width': 4},
          cellLookup: (ref) =>
              ref.toUpperCase() == 'USER.DELTAX' ? 1.0 : null,
        ),
        closeTo(3, 1e-9),
      );
    });

    test('resolves Sheet.n! via sheetLookup', () {
      expect(
        evaluateFormula(
          'Sheet.5!PinX+Width/2',
          locals: {'Width': 4},
          sheetLookup: (id, cell) {
            expect(id, 5);
            expect(cell.toUpperCase(), 'PINX');
            return 10;
          },
        ),
        closeTo(12, 1e-9),
      );
      expect(
        evaluateFormula(
          'Sheet.5!Height*0.5',
          sheetLookup: (id, cell) => id == 5 && cell.toUpperCase() == 'HEIGHT'
              ? 6.0
              : null,
        ),
        closeTo(3, 1e-9),
      );
      expect(
        evaluateFormula(
          'Sheet.5!PinX',
          sheetLookup: (id, cell) => null,
        ),
        isNull,
      );
    });

    test('referencedSheetIds / formulaReferencesAnySheet', () {
      expect(referencedSheetIds('Sheet.3!Height*0.5'), {3});
      expect(
        referencedSheetIds('Sheet.1!PinX+Sheet.2!Width'),
        {1, 2},
      );
      expect(formulaReferencesAnySheet('Sheet.3!PinY', {3, 9}), isTrue);
      expect(formulaReferencesAnySheet('Sheet.3!PinY', {1}), isFalse);
    });

    test('parseSetAtRefControl extracts Controls targets', () {
      expect(parseSetAtRefControl('SETATREF(Controls.TextPosition)'),
          (name: 'TextPosition', cell: null));
      expect(parseSetAtRefControl('SETATREF(Controls.TextPosition.Y)'),
          (name: 'TextPosition', cell: 'Y'));
      expect(parseSetAtRefControl('Width*0.5'), isNull);
      expect(parseSetAtRefControl('SETATREF(Sheet.5!PinX)'), isNull);
    });
  });

  group('VsdxShape.recalculateLocalFormulas', () {
    test('updates connection-point cache V after resize', () {
      final box = VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 2,
        pinY: 2,
        width: 2,
        height: 1,
      ).copyWith(
        connectionPoints: VsdxPage.defaultConnectionPoints(2, 1),
      );
      expect(box.connectionPoints[1].x, closeTo(2, 1e-9)); // right
      expect(box.connectionPoints[1].xFormula, 'Width*1');

      final grown = box.resizeTo(pinX: 3, pinY: 2.5, width: 4, height: 3);
      expect(grown.connectionPoints[0].x, closeTo(2, 1e-9)); // top mid
      expect(grown.connectionPoints[0].y, closeTo(3, 1e-9));
      expect(grown.connectionPoints[1].x, closeTo(4, 1e-9)); // right
      expect(grown.connectionPoints[1].y, closeTo(1.5, 1e-9));
      expect(grown.connectionPoints[2].y, closeTo(0, 1e-9)); // bottom
      expect(grown.connectionPoints[3].x, closeTo(0, 1e-9)); // left
      expect(grown.connectionPoints[4].x, closeTo(2, 1e-9)); // centre
      expect(grown.connectionPoints[4].y, closeTo(1.5, 1e-9));
      // Formulas preserved.
      expect(grown.connectionPoints[1].xFormula, 'Width*1');
      expect(grown.connectionPoints[1].yFormula, 'Height*0.5');
    });

    test('updates LocPin from Width/Height formulas', () {
      final box = VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 2,
        pinY: 2,
        width: 2,
        height: 2,
      ).copyWith(
        locPinXInches: 1,
        locPinYInches: 1,
        formulas: const <String, String>{
          'LocPinX': 'Width*0.5',
          'LocPinY': 'Height*0.5',
        },
      );
      final grown = box.resizeTo(pinX: 3, pinY: 3, width: 6, height: 4);
      expect(grown.locPinXInches, closeTo(3, 1e-9));
      expect(grown.locPinYInches, closeTo(2, 1e-9));
      expect(grown.formulas['LocPinX'], 'Width*0.5');
    });

    test('updates Scratch and User numeric formulas', () {
      final box = VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 2,
        pinY: 2,
        width: 2,
        height: 4,
      ).copyWith(
        scratch: const <VsdxScratchRow>[
          VsdxScratchRow(
            ix: 0,
            x: 1,
            xFormula: 'MIN(Height/2,Width/2)',
          ),
        ],
        userCells: const <VsdxUserCell>[
          VsdxUserCell(name: 'HalfW', value: '1', valueFormula: 'Width/2'),
        ],
      );
      final grown = box.resizeTo(pinX: 2, pinY: 2, width: 8, height: 4);
      expect(grown.scratch.single.x, closeTo(2, 1e-9)); // MIN(2,4)=2
      expect(grown.scratch.single.xFormula, 'MIN(Height/2,Width/2)');
      expect(grown.userCells.single.value, '4');
      expect(grown.userCells.single.valueFormula, 'Width/2');
    });

    test('leaves SETATREF / cross-sheet formulas untouched', () {
      final box = VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 2,
        pinY: 2,
        width: 2,
        height: 2,
      ).copyWith(
        connectionPoints: const <VsdxConnectionPoint>[
          VsdxConnectionPoint(
            0.5,
            0.5,
            xFormula: 'SETATREF(Controls.Row_1.X)',
            yFormula: 'Sheet.3!Height*0.5',
          ),
        ],
        controls: const <VsdxControlRow>[
          VsdxControlRow(
            name: 'Row_1',
            x: 0.5,
            y: 0.5,
            xFormula: 'SETATREF(Controls.Row_1.X)',
          ),
        ],
      );
      final grown = box.resizeTo(pinX: 2, pinY: 2, width: 6, height: 6);
      expect(grown.connectionPoints.single.x, closeTo(0.5, 1e-9));
      expect(grown.connectionPoints.single.y, closeTo(0.5, 1e-9));
      expect(
        grown.connectionPoints.single.xFormula,
        'SETATREF(Controls.Row_1.X)',
      );
      expect(grown.controls.single.x, closeTo(0.5, 1e-9));
      expect(grown.controls.single.xFormula, 'SETATREF(Controls.Row_1.X)');
    });

    test('recalculates Geometry Width* and Scratch.X1 after resize', () {
      final box = VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 2,
        pinY: 2,
        width: 2,
        height: 2,
      ).copyWith(
        scratch: const <VsdxScratchRow>[
          VsdxScratchRow(
            ix: 1,
            x: 1,
            xFormula: 'Width*0.5',
          ),
        ],
        geometries: <VsdxGeometry>[
          VsdxGeometry(
            commands: const <VsdxPathCommand>[
              MoveTo(0, 0),
              LineTo(1, 0),
              LineTo(1, 2),
              LineTo(0, 2),
              LineTo(0, 0),
            ],
            commandFormulas: const <Map<String, String>>[
              {'X': 'Width*0', 'Y': 'Height*0'},
              {'X': 'Scratch.X1', 'Y': 'Height*0'},
              {'X': 'Scratch.X1', 'Y': 'Height*1'},
              {'X': 'Width*0', 'Y': 'Height*1'},
              {'X': 'Width*0', 'Y': 'Height*0'},
            ],
          ),
        ],
      );

      final grown = box.resizeTo(pinX: 3, pinY: 3, width: 6, height: 4);
      expect(grown.scratch.single.x, closeTo(3, 1e-9));
      expect(grown.scratch.single.xFormula, 'Width*0.5');
      final cmds = grown.geometries.single.commands;
      expect(cmds[0], isA<MoveTo>());
      expect((cmds[0] as MoveTo).x, closeTo(0, 1e-9));
      expect((cmds[0] as MoveTo).y, closeTo(0, 1e-9));
      expect((cmds[1] as LineTo).x, closeTo(3, 1e-9)); // Scratch.X1
      expect((cmds[1] as LineTo).y, closeTo(0, 1e-9));
      expect((cmds[2] as LineTo).x, closeTo(3, 1e-9));
      expect((cmds[2] as LineTo).y, closeTo(4, 1e-9));
      expect(grown.geometries.single.formulasAt(1)['X'], 'Scratch.X1');
    });

    test('SETATREF(Controls.*) syncs TxtPin from control after resize', () {
      final box = VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 2,
        pinY: 2,
        width: 2,
        height: 2,
      ).copyWith(
        formulas: const <String, String>{
          'TxtPinX': 'SETATREF(Controls.TextPosition)',
          'TxtPinY': 'SETATREF(Controls.TextPosition.Y)',
        },
        controls: const <VsdxControlRow>[
          VsdxControlRow(
            name: 'TextPosition',
            x: 1,
            y: 1,
            xFormula: 'Width*0.5',
            yFormula: 'Height*0.25',
          ),
        ],
        richText: const VsdxRichText(
          runs: <VsdxTextRun>[VsdxTextRun(text: 'Label')],
          textBlock: VsdxTextBlock(pinXInches: 1, pinYInches: 1),
        ),
      );

      final grown = box.resizeTo(pinX: 3, pinY: 3, width: 4, height: 4);
      expect(grown.controls.single.x, closeTo(2, 1e-9));
      expect(grown.controls.single.y, closeTo(1, 1e-9));
      expect(grown.richText.textBlock.pinXInches, closeTo(2, 1e-9));
      expect(grown.richText.textBlock.pinYInches, closeTo(1, 1e-9));
      expect(grown.formulas['TxtPinX'], 'SETATREF(Controls.TextPosition)');
    });

    test('pushSetAtRefToControls writes TxtPin into the bound control', () {
      final box = VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 2,
        pinY: 2,
        width: 2,
        height: 2,
      ).copyWith(
        formulas: const <String, String>{
          'TxtPinX': 'SETATREF(Controls.TextPosition)',
          'TxtPinY': 'SETATREF(Controls.TextPosition.Y)',
        },
        controls: const <VsdxControlRow>[
          VsdxControlRow(name: 'TextPosition', x: 0.5, y: 0.5),
        ],
        richText: const VsdxRichText(
          runs: <VsdxTextRun>[VsdxTextRun(text: 'Label')],
          textBlock: VsdxTextBlock(pinXInches: 1.25, pinYInches: 0.75),
        ),
      );
      final pushed = box.pushSetAtRefToControls();
      expect(pushed.controls.single.x, closeTo(1.25, 1e-9));
      expect(pushed.controls.single.y, closeTo(0.75, 1e-9));
    });

    test('SETATREFEVAL redirect writes transformed User cell', () {
      final box = VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 2,
        pinY: 2,
        width: 2,
        height: 2,
      ).copyWith(
        formulas: const <String, String>{
          'TxtPinX':
              'SETATREF(User.DeltaX,SETATREFEVAL(SETATREFEXPR()-1))',
        },
        userCells: const <VsdxUserCell>[
          VsdxUserCell(name: 'DeltaX', value: '0'),
        ],
        richText: const VsdxRichText(
          runs: <VsdxTextRun>[VsdxTextRun(text: 'Label')],
          textBlock: VsdxTextBlock(pinXInches: 3),
        ),
      );
      final pushed = box.pushSetAtRefToControls();
      expect(pushed.userCells.single.value, '2'); // 3 - 1
      expect(
        pushed.formulas['TxtPinX'],
        'SETATREF(User.DeltaX,SETATREFEVAL(SETATREFEXPR()-1))',
      );
    });

    test('SETATREF(User.*) syncs TxtPin on recalc', () {
      final box = VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 2,
        pinY: 2,
        width: 2,
        height: 2,
      ).copyWith(
        formulas: const <String, String>{
          'TxtPinX': 'SETATREF(User.AnchorX)',
        },
        userCells: const <VsdxUserCell>[
          VsdxUserCell(name: 'AnchorX', value: '1.75'),
        ],
        richText: const VsdxRichText(
          runs: <VsdxTextRun>[VsdxTextRun(text: 'Label')],
          textBlock: VsdxTextBlock(pinXInches: 0.5),
        ),
      );
      final synced = box.syncSetAtRefFromControls();
      expect(synced.richText.textBlock.pinXInches, closeTo(1.75, 1e-9));
    });

    test('composite SETATREF+Width syncs TxtPin', () {
      final box = VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 2,
        pinY: 2,
        width: 4,
        height: 2,
      ).copyWith(
        formulas: const <String, String>{
          'TxtPinX': 'SETATREF(User.DeltaX)+Width*0.5',
        },
        userCells: const <VsdxUserCell>[
          VsdxUserCell(name: 'DeltaX', value: '1'),
        ],
        richText: const VsdxRichText(
          runs: <VsdxTextRun>[VsdxTextRun(text: 'Label')],
          textBlock: VsdxTextBlock(pinXInches: 0),
        ),
      );
      final synced = box.syncSetAtRefFromControls();
      expect(synced.richText.textBlock.pinXInches, closeTo(3, 1e-9)); // 1+2
    });

    test('SETATREF chain push writes the leaf User cell', () {
      final box = VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 2,
        pinY: 2,
        width: 2,
        height: 2,
      ).copyWith(
        formulas: const <String, String>{
          'TxtPinX': 'SETATREF(User.Mid)',
        },
        userCells: const <VsdxUserCell>[
          VsdxUserCell(
            name: 'Mid',
            value: '0',
            valueFormula: 'SETATREF(User.Final)',
          ),
          VsdxUserCell(name: 'Final', value: '0'),
        ],
        richText: const VsdxRichText(
          runs: <VsdxTextRun>[VsdxTextRun(text: 'Label')],
          textBlock: VsdxTextBlock(pinXInches: 2.5),
        ),
      );
      final pushed = box.pushSetAtRefToControls();
      expect(
        pushed.userCells.firstWhere((c) => c.name == 'Final').value,
        '2.5',
      );
      // Intermediate Mid cache is left alone; Final is the chain leaf.
      expect(
        pushed.userCells.firstWhere((c) => c.name == 'Mid').value,
        '0',
      );
    });
  });

  group('VsdxPage.recalculateFormulas Sheet.n!', () {
    test('updates dependent Connection Y when referenced shape grows', () {
      final anchor = VsdxShapeFactory.rectangle(
        id: 1,
        pinX: 2,
        pinY: 2,
        width: 2,
        height: 2,
      );
      final follower = VsdxShapeFactory.rectangle(
        id: 2,
        pinX: 6,
        pinY: 2,
        width: 2,
        height: 2,
      ).copyWith(
        connectionPoints: const <VsdxConnectionPoint>[
          VsdxConnectionPoint(
            1,
            1,
            xFormula: 'Width*0.5',
            yFormula: 'Sheet.1!Height*0.5',
          ),
        ],
      );
      var page = VsdxPage(
        id: 0,
        name: 'P',
        widthInches: 11,
        heightInches: 8.5,
        shapes: <VsdxShape>[anchor, follower],
      );

      page = page
          .updateShapeById(
            1,
            (s) => s.resizeTo(pinX: 2, pinY: 3, width: 2, height: 4),
          )
          .recalculateFormulas(changedShapeIds: <int>{1});

      final dep = page.findShapeById(2)!;
      expect(dep.connectionPoints.single.x, closeTo(1, 1e-9)); // Width*0.5
      expect(dep.connectionPoints.single.y, closeTo(2, 1e-9)); // Sheet.1!Height*0.5
      expect(dep.connectionPoints.single.yFormula, 'Sheet.1!Height*0.5');
    });

    test('full-page pass resolves PinX of another sheet', () {
      final a = VsdxShapeFactory.rectangle(
        id: 10,
        pinX: 3,
        pinY: 1,
        width: 2,
        height: 1,
      );
      final b = VsdxShapeFactory.rectangle(
        id: 20,
        pinX: 1,
        pinY: 1,
        width: 2,
        height: 2,
      ).copyWith(
        locPinXInches: 1,
        formulas: const <String, String>{
          'LocPinX': 'Sheet.10!PinX*0.5',
        },
      );
      final page = VsdxPage(
        id: 0,
        name: 'P',
        widthInches: 11,
        heightInches: 8.5,
        shapes: <VsdxShape>[a, b],
      ).recalculateFormulas();

      expect(page.findShapeById(20)!.locPinXInches, closeTo(1.5, 1e-9));
    });
  });
}
