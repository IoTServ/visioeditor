import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:visioeditor/editor/third_party_icons.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  test('icon catalog has multiple packs including Cupertino', () {
    final ids = kThirdPartyIconProviders.map((p) => p.id).toList();
    expect(ids, containsAll(['material', 'lucide', 'phosphor', 'cupertino']));
    expect(kThirdPartyIconByKey.length, greaterThan(800));
    expect(findThirdPartyIcon('cupertino', 'cloud'), isNotNull);
    expect(findThirdPartyIcon('lucide', 'unlock'), isNotNull);
    expect(findThirdPartyIcon('lucide', 'kanban'), isNotNull);
    expect(findThirdPartyIcon('material', 'view_kanban'), isNotNull);
  });

  test('IconOps meta round-trips on a picture shape', () {
    final shape = VsdxShapeFactory.picture(
      id: 1,
      pinX: 1,
      pinY: 1,
      width: 0.75,
      height: 0.75,
      imagePartName: 'media/image1.png',
    ).copyWith(
      userCells: IconOps.meta(
        providerId: 'material',
        iconId: 'cloud',
        colorArgb: 0xFFE53935,
      ),
    );
    expect(IconOps.isIcon(shape), isTrue);
    expect(IconOps.providerId(shape), 'material');
    expect(IconOps.iconId(shape), 'cloud');
    expect(IconOps.colorArgb(shape), 0xFFE53935);
    expect(IconOps.formatColor(0xFFE53935), '#E53935');
    expect(IconOps.resolve(shape)?.name, 'Cloud');
  });

  test('findProviderIdForIcon resolves catalog instances', () {
    final entry = findThirdPartyIcon('phosphor', 'cloud')!;
    expect(findProviderIdForIcon(entry), 'phosphor');
  });

  test('setIconCaptionBelow places text under the picture', () {
    final c = EditorController();
    c.newDocument();
    final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
    c.insertImage(
      bytes,
      fileExtension: 'png',
      widthInches: 0.75,
      heightInches: 0.75,
      userCells: IconOps.meta(
        providerId: 'material',
        iconId: 'cloud',
        colorArgb: IconOps.defaultColorArgb,
      ),
    );
    final id = c.singleSelectedId!;
    // Stale Height* formulas must not revive after caption placement.
    c.updateCurrentPage(
      (p) => p.updateShapeById(
        id,
        (s) => s.copyWith(
          formulas: <String, String>{
            ...s.formulas,
            'TxtPinX': 'Width*0.5',
            'TxtPinY': 'Height*0.5',
            'TxtWidth': 'Width*1',
            'TxtHeight': 'Height*1',
          },
        ),
      ),
    );
    c.setIconCaptionBelow(id, 'Cloud');
    final shape = c.currentPage!.findShapeById(id)!;
    expect(shape.text, 'Cloud');
    expect(shape.richText.plainText, 'Cloud');
    final block = shape.richText.textBlock;
    expect(block.pinYInches, lessThan(0));
    expect(block.pinXInches, closeTo(shape.width / 2, 1e-6));
    expect(shape.formulas.containsKey('TxtPinY'), isFalse);
    expect(shape.formulas.containsKey('TxtHeight'), isFalse);
    // Resize must keep the caption below (absolute pin, no Height* revive).
    final grown = shape.resizeTo(
      pinX: shape.pinX,
      pinY: shape.pinY,
      width: 1.5,
      height: 1.5,
    );
    expect(grown.richText.textBlock.pinYInches, lessThan(0));
    // Shape name stays auto so the painter won't overlay a name fallback.
    expect(shape.name, matches(RegExp(r'^Sheet\.\d+$')));
  });
}
