import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/third_party_icons.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  test('icon catalog has multiple packs including Cupertino', () {
    final ids = kThirdPartyIconProviders.map((p) => p.id).toList();
    expect(ids, containsAll(['material', 'lucide', 'phosphor', 'cupertino']));
    expect(kThirdPartyIconByKey.length, greaterThan(200));
    expect(findThirdPartyIcon('cupertino', 'cloud'), isNotNull);
    expect(findThirdPartyIcon('lucide', 'unlock'), isNotNull);
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
}
