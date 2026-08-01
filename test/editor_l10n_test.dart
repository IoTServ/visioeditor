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
    expect(en.selectEdges, 'Select Edges');
    expect(zh.selectEdges, '选择连接线');
    expect(en.selectVertices, 'Select Vertices');
    expect(zh.selectVertices, '选择图形');
    expect(en.selectChildren, 'Select Children');
    expect(zh.selectChildren, '选择子元素');
    expect(en.selectSubtree, 'Select Subtree');
    expect(zh.selectSubtree, '选择子树');
    expect(en.selectParent, 'Select Parent');
    expect(zh.selectParent, '选择父元素');
    expect(en.selectSiblings, 'Select Siblings');
    expect(zh.selectSiblings, '选择同级元素');
    expect(en.connectionArrows, 'Connection Arrows');
    expect(zh.connectionArrows, '连接箭头');
    expect(en.connectionPoints, 'Connection Points');
    expect(zh.connectionPoints, '连接点');
    expect(en.copyOnConnect, 'Copy on Connect');
    expect(zh.copyOnConnect, '连线时复制');
    expect(en.collapseExpand, 'Collapse/Expand Controls');
    expect(zh.collapseExpand, '折叠/展开控件');
    expect(en.editTooltip, 'Edit Tooltip…');
    expect(zh.editTooltip, '编辑工具提示…');
    expect(en.tooltips, 'Tooltips');
    expect(zh.tooltips, '工具提示');
    expect(en.collapsible, 'Collapsible');
    expect(zh.collapsible, '可折叠');
    expect(en.setAsDefaultStyle, 'Set as Default Style');
    expect(zh.setAsDefaultStyle, '设为默认样式');
    expect(en.clearDefaultStyle, 'Clear Default Style');
    expect(zh.clearDefaultStyle, '清除默认样式');
    expect(en.wordWrap, 'Word Wrap');
    expect(zh.wordWrap, '自动换行');
    expect(en.constrainProportions, 'Constrain Proportions');
    expect(zh.constrainProportions, '限制比例');
    expect(en.selectNone, 'Select None');
    expect(zh.selectNone, '取消全选');
    expect(en.snapSelectionToGrid, 'Snap Selection to Grid');
    expect(zh.snapSelectionToGrid, '所选内容对齐网格');
    expect(en.distributeSpacingH, 'Distribute Horizontal Spacing');
    expect(zh.distributeSpacingH, '水平等间距分布');
    expect(en.distributeSpacingV, 'Distribute Vertical Spacing');
    expect(zh.distributeSpacingV, '垂直等间距分布');
    expect(en.toolRectangle, 'Rectangle');
    expect(zh.toolRectangle, '矩形');
    expect(en.toolPan, 'Pan / zoom canvas');
    expect(zh.toolPan, '平移 / 缩放画布');
    expect(en.fitPageWidth, 'Fit Page Width');
    expect(zh.fitPageWidth, '适应页面宽度');
    expect(en.copyAsText, 'Copy as Text');
    expect(zh.copyAsText, '复制为文本');
    expect(en.openLink, 'Open Link');
    expect(zh.openLink, '打开链接');
    expect(en.copyTextStyle, 'Copy Text Style');
    expect(zh.copyTextStyle, '复制文本样式');
    expect(en.pasteTextStyle, 'Paste Text Style');
    expect(zh.pasteTextStyle, '粘贴文本样式');
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
    expect(zh.labelPosition, '标签位置');
    expect(zh.verticalText, '竖排文字');
    expect(EditorL10n(const Locale('en')).labelPositionRight,
        'Position label right');
    expect(zh.openFileFailed('x'), contains('x'));
    expect(ja.stencil('Rounded Rectangle'), '角丸四角形');
    expect(de.stencil('Rectangle'), 'Rechteck');
    expect(ja.flipHorizontal, isNot('Flip horizontal'));
  });
}
