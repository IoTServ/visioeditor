import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

VsdxShape? _findByText(VsdxPage page, String needle) {
  VsdxShape? walk(VsdxShape s) {
    final t = s.text ?? '';
    if (t.contains(needle)) return s;
    for (final c in s.children) {
      final hit = walk(c);
      if (hit != null) return hit;
    }
    return null;
  }

  for (final s in page.shapes) {
    final hit = walk(s);
    if (hit != null) return hit;
  }
  return null;
}

/// Edraw often emits text labels with `FillPattern` / `LinePattern` cells but
/// **no** `<Section N="Geometry">`. Visio / libvisio / Edraw then paint text
/// only (no fill, no stroke). Regression for `人才招聘冰山模型.vsdx` labels
/// such as "70% 隐性".
void main() {
  const parser = DocumentParser();

  test('冰山模型 text labels have fill cells but empty geometry', () {
    final doc = parser.parse(_fixture('人才招聘冰山模型.vsdx'));
    final page = doc.pages.first;

    for (final label in const ['70% 隐性', '30% 显性', '专业知识', '基本技能']) {
      final shape = _findByText(page, label);
      expect(shape, isNotNull, reason: 'missing "$label"');
      expect(shape!.geometries, isEmpty,
          reason: '"$label" must stay geometry-less like Edraw');
      expect(shape.hasGeometry, isFalse);
      // Stale fill data is present in the sheet but must not imply a path.
      expect(shape.fill.pattern, greaterThan(0),
          reason: '"$label" still carries FillPattern in the VSDX');
      expect(shape.line.pattern, 0,
          reason: '"$label" LinePattern=0 (no stroke)');
    }
  });

  test('SVG export paints those labels as text without a synthetic rect', () {
    final doc = parser.parse(_fixture('人才招聘冰山模型.vsdx'));
    final svg = VsdxToSvgSerializer().serializePage(
      doc.pages.first,
      theme: doc.theme,
      images: doc.images,
    );
    expect(svg, contains('70% 隐性'));
    // FillForegnd on the geometry-less label must not leak into a path fill.
    expect(svg.contains('fill="#71717a"'), isFalse);
    expect(svg.contains('fill="#71717A"'), isFalse);
  });

  test('Edraw annotation Groups are structural but not foldable', () {
    // Groups 1004/1005/1009/1013 wrap (arrow + title + body). They must stay
    // `group` (containment) but must NOT be foldable — otherwise the painter
    // draws draw.io ▼ chevrons Edraw/libvisio never show.
    final doc = parser.parse(_fixture('人才招聘冰山模型.vsdx'));
    final page = doc.pages.first;
    final groups = <VsdxShape>[];
    void walk(VsdxShape s) {
      if (s.shapeKind == VsdxShapeKind.group) groups.add(s);
      for (final c in s.children) {
        walk(c);
      }
    }

    for (final s in page.shapes) {
      walk(s);
    }
    expect(groups, isNotEmpty);
    for (final g in groups) {
      expect(g.shapeKind.isStructural, isTrue);
      expect(g.shapeKind.isFoldable, isFalse,
          reason: 'group ${g.id} must not paint a collapse chevron');
    }
    expect(VsdxShapeKind.container.isFoldable, isTrue);
    expect(VsdxShapeKind.swimlane.isFoldable, isTrue);
  });
}
