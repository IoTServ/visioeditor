import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  test('removeShapeById prunes Connect rows for the victim', () {
    final a = VsdxShapeFactory.rectangle(id: 1, pinX: 1, pinY: 1, width: 1, height: 1);
    final b = VsdxShapeFactory.rectangle(id: 2, pinX: 3, pinY: 1, width: 1, height: 1);
    final conn = VsdxShapeFactory.line(id: 3, ax: 1, ay: 1, bx: 3, by: 1);
    var page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 10,
      heightInches: 10,
      shapes: <VsdxShape>[a, b, conn],
      connects: const <VsdxConnect>[
        VsdxConnect(
          fromSheetId: 3,
          fromCell: 'BeginX',
          fromPart: 9,
          toSheetId: 1,
          toCell: 'PinX',
          toPart: 3,
        ),
        VsdxConnect(
          fromSheetId: 3,
          fromCell: 'EndX',
          fromPart: 12,
          toSheetId: 2,
          toCell: 'PinX',
          toPart: 3,
        ),
      ],
    );

    page = page.removeShapeById(3);
    expect(page.findShapeById(3), isNull);
    expect(page.connects, isEmpty);

    page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 10,
      heightInches: 10,
      shapes: <VsdxShape>[a, b, conn],
      connects: const <VsdxConnect>[
        VsdxConnect(
          fromSheetId: 3,
          fromCell: 'BeginX',
          fromPart: 9,
          toSheetId: 1,
          toCell: 'PinX',
          toPart: 3,
        ),
        VsdxConnect(
          fromSheetId: 3,
          fromCell: 'EndX',
          fromPart: 12,
          toSheetId: 2,
          toCell: 'PinX',
          toPart: 3,
        ),
      ],
    );
    page = page.removeShapeById(2);
    expect(page.connects, hasLength(1));
    expect(page.connects.single.toSheetId, 1);
  });

  test('removeShapeById clears Begin/End PAR formulas naming the victim', () {
    final a = VsdxShapeFactory.rectangle(
        id: 1, pinX: 1, pinY: 1, width: 1, height: 1);
    final b = VsdxShapeFactory.rectangle(
        id: 2, pinX: 3, pinY: 1, width: 1, height: 1);
    final conn = VsdxShapeFactory.line(id: 3, ax: 1, ay: 1, bx: 3, by: 1)
        .copyWith(
      formulas: const <String, String>{
        'BegTrigger': '_XFTRIGGER(Sheet.1!EventXFMod)',
        'EndTrigger': '_XFTRIGGER(Sheet.2!EventXFMod)',
        'BeginX': 'PAR(PNT(Sheet.1!Connections.X1,Sheet.1!Connections.Y1))',
        'EndX': 'PAR(PNT(Sheet.2!Connections.X1,Sheet.2!Connections.Y1))',
      },
    );
    var page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 10,
      heightInches: 10,
      shapes: <VsdxShape>[a, b, conn],
      connects: const <VsdxConnect>[
        VsdxConnect(
          fromSheetId: 3,
          fromCell: 'BeginX',
          fromPart: 9,
          toSheetId: 1,
          toCell: 'PinX',
          toPart: 3,
        ),
        VsdxConnect(
          fromSheetId: 3,
          fromCell: 'EndX',
          fromPart: 12,
          toSheetId: 2,
          toCell: 'PinX',
          toPart: 3,
        ),
      ],
    );
    page = page.removeShapeById(2);
    final after = page.findShapeById(3)!;
    expect(after.formulas.containsKey('EndTrigger'), isFalse);
    expect(after.formulas['EndX'] ?? '', isNot(contains('Sheet.2!')));
    expect(after.formulas['BegTrigger'], contains('Sheet.1!'));
    expect(after.formulas['BeginX'], contains('Sheet.1!'));
  });

  test('removeShapeById pruneConnects:false keeps Connect rows', () {
    final a = VsdxShapeFactory.rectangle(id: 1, pinX: 1, pinY: 1, width: 1, height: 1);
    final conn = VsdxShapeFactory.line(id: 3, ax: 1, ay: 1, bx: 3, by: 1);
    var page = VsdxPage(
      id: 0,
      name: 'P',
      widthInches: 10,
      heightInches: 10,
      shapes: <VsdxShape>[a, conn],
      connects: const <VsdxConnect>[
        VsdxConnect(
          fromSheetId: 3,
          fromCell: 'BeginX',
          fromPart: 9,
          toSheetId: 1,
          toCell: 'PinX',
          toPart: 3,
        ),
      ],
    );
    page = page.removeShapeById(1, pruneConnects: false);
    expect(page.connects, hasLength(1));
  });
}
