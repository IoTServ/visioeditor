import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  EditorController controller() {
    final value = EditorController()..newDocument();
    addTearDown(value.dispose);
    return value;
  }

  int connector(
    EditorController value, {
    double ax = 1,
    double ay = 2,
    double bx = 5,
    double by = 2,
  }) {
    value.createConnector(ax, ay, bx, by);
    final id = value.singleSelectedId!;
    value.setShapeText(id, 'Approval');
    return id;
  }

  test('Rotate with Edge preserves metadata, undo, and VSDX round-trip', () {
    final value = controller();
    final id = connector(value);
    value.updateCurrentPage(
      (page) => page.updateShapeById(
        id,
        (shape) => shape.copyWith(
          userCells: const <VsdxUserCell>[
            VsdxUserCell(name: 'foreignMeta', value: 'keep'),
          ],
        ),
      ),
    );

    expect(value.canSetAutoRotateLabel, isTrue);
    expect(value.selectedAutoRotateLabel, isFalse);
    value.setAutoRotateLabel(true);
    var changed = value.currentPage!.findShapeById(id)!;
    expect(changed.autoRotateLabel, isTrue);
    expect(
      changed.userCells.firstWhere((cell) => cell.name == 'foreignMeta').value,
      'keep',
    );

    value.undo();
    expect(value.currentPage!.findShapeById(id)!.autoRotateLabel, isFalse);
    value.redo();

    changed = const DocumentParser()
        .parse(value.exportToBytes())
        .pages
        .single
        .findShapeById(id)!;
    expect(changed.autoRotateLabel, isTrue);
    expect(
      changed.userCells.firstWhere((cell) => cell.name == 'foreignMeta').value,
      'keep',
    );
  });

  test(
    'effective angle follows the nearest route segment and stays upright',
    () {
      VsdxShape elbow({required bool reversed}) {
        final base = VsdxShapeFactory.line(
          id: 1,
          ax: reversed ? 5 : 1,
          ay: reversed ? 5 : 1,
          bx: reversed ? 1 : 5,
          by: reversed ? 1 : 5,
        );
        final x = base.width;
        final y = base.height;
        return base
            .copyWith(
              geometries: <VsdxGeometry>[
                VsdxGeometry(
                  noFill: true,
                  commands: <VsdxPathCommand>[
                    const MoveTo(0, 0),
                    LineTo(0, y),
                    LineTo(x, y),
                  ],
                ),
              ],
              richText: VsdxRichText(
                runs: const <VsdxTextRun>[VsdxTextRun(text: 'Edge')],
                textBlock: VsdxTextBlock(
                  pinXInches: 0.05 * x,
                  pinYInches: 0.75 * y,
                ),
              ),
            )
            .withAutoRotateLabel(true);
      }

      final forward = elbow(reversed: false);
      final forwardPage = VsdxPage(
        id: 0,
        name: 'Page-1',
        widthInches: 8.5,
        heightInches: 11,
        shapes: <VsdxShape>[forward],
      );
      expect(
        forwardPage.effectiveConnectorLabelAngle(forward),
        closeTo(math.pi / 2, 1e-9),
      );

      final reverse = elbow(reversed: true);
      final reversePage = VsdxPage(
        id: 0,
        name: 'Page-1',
        widthInches: 8.5,
        heightInches: 11,
        shapes: <VsdxShape>[reverse],
      );
      expect(
        reversePage.effectiveConnectorLabelAngle(reverse).abs(),
        closeTo(math.pi / 2, 1e-9),
      );

      final diagonal = VsdxShapeFactory.line(
        id: 2,
        ax: 5,
        ay: 5,
        bx: 1,
        by: 1,
      ).withAutoRotateLabel(true);
      final diagonalPage = VsdxPage(
        id: 0,
        name: 'Page-1',
        widthInches: 8.5,
        heightInches: 11,
        shapes: <VsdxShape>[diagonal],
      );
      expect(
        diagonalPage.effectiveConnectorLabelAngle(diagonal),
        closeTo(math.pi / 4, 1e-9),
      );
    },
  );

  test(
    'manual TxtAngle is preserved and rotation is blocked while automatic',
    () {
      final value = controller();
      final id = connector(value);
      value.rotateConnectorLabelToward(id, 4, 2);
      final manual = value.currentPage!
          .findShapeById(id)!
          .richText
          .textBlock
          .angleRad;
      expect(manual, closeTo(-math.pi / 2, 1e-9));

      value.setAutoRotateLabel(true);
      var shape = value.currentPage!.findShapeById(id)!;
      expect(
        value.currentPage!.effectiveConnectorLabelAngle(shape),
        closeTo(0, 1e-9),
      );
      value.rotateConnectorLabelToward(id, 3, 3);
      shape = value.currentPage!.findShapeById(id)!;
      expect(shape.richText.textBlock.angleRad, closeTo(manual, 1e-9));

      value.setAutoRotateLabel(false);
      shape = value.currentPage!.findShapeById(id)!;
      expect(
        value.currentPage!.effectiveConnectorLabelAngle(shape),
        closeTo(manual, 1e-9),
      );
    },
  );

  test('edge default and copied styles carry Rotate with Edge', () {
    final value = controller();
    final source = connector(value, ay: 2, by: 3);
    value
      ..setAutoRotateLabel(true)
      ..setSelectionAsDefaultStyle();

    final inherited = connector(value, ay: 4, by: 5);
    expect(
      value.currentPage!.findShapeById(inherited)!.autoRotateLabel,
      isTrue,
    );

    value
      ..clearDefaultStyle()
      ..setSelection([source])
      ..copyStyle();
    final target = connector(value, ay: 6, by: 7);
    expect(value.currentPage!.findShapeById(target)!.autoRotateLabel, isFalse);
    value.pasteStyle();
    expect(value.currentPage!.findShapeById(target)!.autoRotateLabel, isTrue);
  });

  test('SVG rotates a loose connector label with its route tangent', () {
    final value = controller();
    final id = connector(value, ax: 1, ay: 1, bx: 5, by: 5);
    value.setAutoRotateLabel(true);

    final shape = value.currentPage!.findShapeById(id)!;
    expect(shape.richText.textBlock.angleRad, 0);
    final svg = VsdxToSvgSerializer().serializePage(value.currentPage!);
    expect(svg, contains('rotate(45)'));
    expect(svg, contains('Approval'));
  });

  test('controller rejects vertices and locked connectors', () {
    final value = controller();
    value
      ..setTool(EditorTool.rectangle)
      ..createShapeByDrag(1, 1, 3, 2);
    final vertex = value.singleSelectedId!;
    expect(value.canSetAutoRotateLabel, isFalse);
    value.setAutoRotateLabel(true);
    expect(value.currentPage!.findShapeById(vertex)!.autoRotateLabel, isFalse);

    final edge = connector(value);
    value.updateCurrentPage(
      (page) =>
          page.updateShapeById(edge, (shape) => shape.copyWith(locked: true)),
    );
    expect(value.canSetAutoRotateLabel, isFalse);
    value.setAutoRotateLabel(true);
    expect(value.currentPage!.findShapeById(edge)!.autoRotateLabel, isFalse);
  });
}
