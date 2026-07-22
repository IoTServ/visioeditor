import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/l10n/app_localizations.dart';
import 'package:visioeditor/l10n/editor_l10n.dart';

void main() {
  test('EditorL10n covers en and zh for menus and stencils', () {
    final en = EditorL10n(const Locale('en'));
    final zh = EditorL10n(const Locale('zh'));
    expect(en.undo, 'Undo');
    expect(zh.undo, '撤销');
    expect(en.cut, 'Cut');
    expect(zh.cut, '剪切');
    expect(en.toolRectangle, 'Rectangle');
    expect(zh.toolRectangle, '矩形');
    expect(en.toolPan, 'Pan / zoom canvas');
    expect(zh.toolPan, '平移 / 缩放画布');
    expect(en.stencilGroup('Flowchart'), 'Flowchart');
    expect(zh.stencilGroup('Flowchart'), '流程图');
    expect(zh.stencil('Rounded Rectangle'), '圆角矩形');
    expect(zh.stencil('Unknown Shape XYZ'), 'Unknown Shape XYZ');
    expect(zh.stencilMatches('Rectangle', '矩形'), isTrue);
    expect(zh.stencilMatches('Rectangle', 'rect'), isTrue);
    expect(en.pageOf(2, 5), 'Page 2 of 5');
    expect(zh.pageOf(2, 5), '第 2 页，共 5 页');
  });

  test('all AppLocalizations languages translate core editor strings', () {
    final enUndo = EditorL10n(const Locale('en')).undo;
    final enCut = EditorL10n(const Locale('en')).cut;
    for (final locale in AppLocalizations.supportedLocales) {
      final el = EditorL10n(locale);
      if (locale.languageCode == 'en') {
        expect(el.undo, 'Undo');
        expect(el.cut, 'Cut');
      } else {
        expect(el.undo, isNot(enUndo), reason: '${locale.languageCode}.undo');
        expect(el.cut, isNot(enCut), reason: '${locale.languageCode}.cut');
      }
      expect(el.cancel, isNotEmpty);
      expect(el.layers, isNotEmpty);
      expect(el.pageOf(1, 2), contains('1'));
    }
  });

  test('unknown locale falls back to English', () {
    final xx = EditorL10n(const Locale('xx'));
    expect(xx.undo, 'Undo');
    expect(xx.stencilGroup('General'), 'General');
  });

  test('new arrange/text keys and stencil names for major locales', () {
    final zh = EditorL10n(const Locale('zh'));
    final ja = EditorL10n(const Locale('ja'));
    final de = EditorL10n(const Locale('de'));
    expect(zh.flipHorizontal, '水平翻转');
    expect(zh.justify, '两端对齐');
    expect(zh.openFileFailed('x'), contains('x'));
    expect(ja.stencil('Rounded Rectangle'), '角丸四角形');
    expect(de.stencil('Rectangle'), 'Rechteck');
    expect(ja.flipHorizontal, isNot('Flip horizontal'));
  });
}
