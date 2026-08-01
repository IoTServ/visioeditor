import 'package:flutter/widgets.dart';

import 'editor_l10n_maps.dart';

/// Editor UI strings (menus, tools, panels, context menu, stencils).
///
/// Tables live in [kEditorL10nTables] (all AppLocalizations languages).
/// Missing keys / locales fall back to English.
class EditorL10n {
  EditorL10n(this.locale);

  final Locale locale;

  static EditorL10n of(BuildContext context) =>
      EditorL10n(Localizations.localeOf(context));

  static Map<String, String> get _en =>
      kEditorL10nTables['en'] ?? const <String, String>{};

  // draw.io Trees.js labels, kept compact as [children, subtree, parent,
  // siblings]. A few upstream locales intentionally fall back to English.
  static const Map<String, List<String>> _treeLabels = {
    'en': ['Select Children', 'Select Subtree', 'Select Parent', 'Select Siblings'],
    'zh': ['选择子元素', '选择子树', '选择父元素', '选择同级元素'],
    'ja': ['子を選択', '子孫を選択', '親を選択', '兄弟を選択'],
    'ko': ['자식 선택', '자손 선택', '부모 선택', '형제 선택'],
    'es': ['Seleccionar Hijos', 'Seleccionar Descendientes', 'Seleccionar Padre', 'Seleccionar Hermanos'],
    'fr': ['Sélectionner les enfants', 'Sélectionner les descendants', 'Sélectionner le parent', 'Sélectionner les voisins'],
    'de': ['Kindknoten markieren', 'Untergeordnete Knoten markieren', 'Vaterknoten markieren', 'Geschwisterknoten markieren'],
    'pt': ['Selecionar Filhos', 'Selecionar Descendentes', 'Selecionar Pai', 'Selecionar Irmãos'],
    'ru': ['Выбрать дочерние', 'Выбрать потомков', 'Выбрать родительский', 'Выбрать родственные'],
    'it': ['Seleziona figli', 'Seleziona discendenti', 'Seleziona genitore', 'Seleziona fratelli'],
    'ar': ['اختر الأطفال', 'اختر الأحفاد', 'اختر الوالد', 'اختر الأشقاء'],
    'id': ['Pilih Anak', 'Pilih Keturunan', 'Pilih Induk', 'Pilih Saudara'],
    'hi': ['चाइल्ड चुनें', 'डिसेंडेंट चुनें', 'पैरेंट चुनें', 'सिबलिंग चुनें'],
    'nl': ['Selecteer kinderen', 'Selecteer afstammelingen', 'Selecteer ouder', 'Selecteer broers en zussen'],
    'tr': ['Alt Öğeleri Seç', 'Alt Öğelerin Tümünü Seç', 'Üst Öğeyi Seç', 'Kardeş Öğeleri Seç'],
    'pl': ['Wybierz elementy podrzędne', 'Wybierz potomków', 'Wybierz element nadrzędny', 'Wybierz elementy równorzędne'],
    'vi': ['Chọn phần tử con', 'Chọn tất cả phần tử con', 'Chọn phần tử cha', 'Chọn phần tử cùng cấp'],
    'th': ['เลือกรายการย่อย', 'เลือกรายการสืบทอด', 'เลือกรายการหลัก', 'เลือกรายการพี่น้อง'],
    'sv': ['Välj underordnade', 'Välj ättlingar', 'Välj överordnad', 'Välj på samma nivå'],
    'uk': ['Обрати дочірні елементи', 'Обрати нащадків', 'Обрати батьківський елемент', 'Обрати сусідні елементи'],
    'he': ['Select Children', 'Select Subtree', 'Select Parent', 'Select Siblings'],
    'cs': ['Vybrat potomky', 'Vybrat potomky', 'Vybrat rodiče', 'Vybrat sourozence'],
    'ro': ['Select Children', 'Select Subtree', 'Select Parent', 'Select Siblings'],
    'el': ['Επιλογή Θυγατρικών', 'Επιλογή Απογόνων', 'Επιλογή Γονέα', 'Επιλογή Ισότιμων'],
    'hu': ['Gyermekelemek kiválasztása', 'Leszármazott elemek kiválasztása', 'Szülőelem kiválasztása', 'Testvérelemek kiválasztása'],
    'da': ['Vælg underordnede', 'Vælg efterkommere', 'Vælg overordnet', 'Vælg søskende'],
    'ms': ['Pilih Anak', 'Pilih Keturunan', 'Pilih Induk', 'Pilih Adik-beradik'],
    'fi': ['Valitse alemman tason kohteet', 'Valitse alikohteet', 'Valitse ylätason kohde', 'Valitse rinnakkaiset kohteet'],
    'nb': ['Velg underordnede', 'Velg etterkommere', 'Velg overordnet', 'Velg søsken'],
    'sk': ['Vybrať potomkov', 'Vybrať všetkých potomkov', 'Vybrať rodiča', 'Vybrať súrodencov'],
    'bn': ['চাইল্ড নির্বাচন করুন', 'ডিসেন্ড্যান্ট নির্বাচন করুন', 'প্যারেন্ট নির্বাচন করুন', 'সিবলিং নির্বাচন করুন'],
    'fa': ['انتخاب فرزندان', 'انتخاب نوادگان', 'انتخاب والد', 'انتخاب هم‌سطح‌ها'],
    'bg': ['Избиране на дъщерни елементи', 'Избиране на наследници', 'Избиране на родителски елемент', 'Избиране на съседни елементи'],
    'hr': ['Odaberi podređene', 'Odaberi potomke', 'Odaberi nadređeni', 'Odaberi srodne'],
    'ca': ['Selecciona els fills', 'Selecciona els descendents', 'Selecciona el pare', 'Selecciona els germans'],
    'fil': ['Piliin ang mga Anak', 'Piliin ang mga Inapo', 'Piliin ang Magulang', 'Piliin ang mga Kapatid'],
    'sw': ['Chagua Watoto', 'Chagua Vizazi', 'Chagua Mzazi', 'Chagua Ndugu'],
  };

  String _treeLabel(int index) =>
      (_treeLabels[locale.languageCode] ?? _treeLabels['en']!)[index];

  String _t(String key) {
    final lang = locale.languageCode;
    return kEditorL10nTables[lang]?[key] ?? _en[key] ?? key;
  }

  // --- Common actions ---
  String get cancel => _t('cancel');
  String get ok => _t('ok');
  String get apply => _t('apply');
  String get close => _t('close');
  String get delete => _t('delete');
  String get rename => _t('rename');
  String get discard => _t('discard');
  String get none => _t('none');
  String get enabled => _t('enabled');
  String get untitled => _t('untitled');

  // --- AppBar / chrome ---
  String get undo => _t('undo');
  String get redo => _t('redo');
  String get outline => _t('outline');
  String get rulers => _t('rulers');
  String get toggleGrid => _t('toggleGrid');
  String get fitToWindow => _t('fitToWindow');
  String get fitToWindowShortcut => _t('fitToWindowShortcut');
  String get fitPageWidth => _t('fitPageWidth');
  String get presentationMode => _t('presentationMode');
  String get presentationModeShortcut => _t('presentationModeShortcut');
  String get exitPresentation => _t('exitPresentation');
  String get exitPresentationShortcut => _t('exitPresentationShortcut');
  String get layers => _t('layers');
  String get insertImage => _t('insertImage');
  String get hideOutline => _t('hideOutline');

  // --- More menu ---
  String get selectAll => _t('selectAll');
  String get selectAllShortcut => _t('selectAllShortcut');
  String get selectNone =>
      locale.languageCode == 'zh' ? '取消全选' : 'Select None';
  String get selectNoneShortcut => locale.languageCode == 'zh'
      ? '取消全选 (Cmd+Shift+A)'
      : 'Select None (Cmd+Shift+A)';
  String get selectEdges => _t('selectEdges');
  String get selectVertices => _t('selectVertices');
  String get selectChildren => _treeLabel(0);
  String get selectSubtree => _treeLabel(1);
  String get selectParent => _treeLabel(2);
  String get selectSiblings => _treeLabel(3);
  String get find => _t('find');
  String get findShortcut => _t('findShortcut');
  String get findReplace => _t('findReplace');
  String get findReplaceShortcut => _t('findReplaceShortcut');
  String get editData => _t('editData');
  String get editDataShortcut => _t('editDataShortcut');
  String get editLink => _t('editLink');
  String get editLinkShortcut => _t('editLinkShortcut');
  String get editTooltip =>
      locale.languageCode == 'zh' ? '编辑工具提示…' : 'Edit Tooltip…';
  String get tooltips => locale.languageCode == 'zh' ? '工具提示' : 'Tooltips';
  String get tooltipText =>
      locale.languageCode == 'zh' ? '工具提示文本' : 'Tooltip text';
  String get tooltipHint => locale.languageCode == 'zh'
      ? '指针停留在图形上时显示'
      : 'Shown when the pointer rests over the shape';
  String get openLink => _t('openLink');
  String get editConnectionPoints => _t('editConnectionPoints');
  String get doneEditingConnectionPoints => _t('doneEditingConnectionPoints');
  String get connectionArrows =>
      locale.languageCode == 'zh' ? '连接箭头' : 'Connection Arrows';
  String get connectionPoints =>
      locale.languageCode == 'zh' ? '连接点' : 'Connection Points';
  String get copyOnConnect =>
      locale.languageCode == 'zh' ? '连线时复制' : 'Copy on Connect';
  String get collapseExpand =>
      locale.languageCode == 'zh' ? '折叠/展开控件' : 'Collapse/Expand Controls';
  String get collapsible =>
      locale.languageCode == 'zh' ? '可折叠' : 'Collapsible';
  String get setAsDefaultStyle => locale.languageCode == 'zh'
      ? '设为默认样式'
      : 'Set as Default Style';
  String get clearDefaultStyle => locale.languageCode == 'zh'
      ? '清除默认样式'
      : 'Clear Default Style';
  String get lock => _t('lock');
  String get unlock => _t('unlock');
  String get lockShortcut => _t('lockShortcut');
  String get unlockShortcut => _t('unlockShortcut');
  String get zoomToSelection => _t('zoomToSelection');
  String get copyStyle => _t('copyStyle');
  String get copyStyleShortcut => _t('copyStyleShortcut');
  String get pasteStyle => _t('pasteStyle');
  String get pasteStyleShortcut => _t('pasteStyleShortcut');
  String get copyTextStyle => _t('copyTextStyle');
  String get copyTextStyleShortcut => _t('copyTextStyleShortcut');
  String get pasteTextStyle => _t('pasteTextStyle');
  String get pasteTextStyleShortcut => _t('pasteTextStyleShortcut');
  String get saveAs => _t('saveAs');
  String get exportSvg => _t('exportSvg');
  String get exportPng => _t('exportPng');
  String get exportPdf => _t('exportPdf');
  String get snapToGrid => _t('snapToGrid');
  String get snapSelectionToGrid => locale.languageCode == 'zh'
      ? '所选内容对齐网格'
      : 'Snap Selection to Grid';
  String get guides => locale.languageCode == 'zh' ? '参考线' : 'Guides';
  String get lineJumps => _t('lineJumps');
  String get closeTab => _t('closeTab');
  String get closeTabShortcut => _t('closeTabShortcut');
  String get closeOtherTabs => _t('closeOtherTabs');
  String get closeTabsToTheLeft => _t('closeTabsToTheLeft');
  String get closeTabsToTheRight => _t('closeTabsToTheRight');
  String get closeAllTabs => _t('closeAllTabs');
  String get tabReorderHint => _t('tabReorderHint');
  String get tabMenuTooltip => _t('tabMenuTooltip');

  // --- Context menu ---
  String get cut => _t('cut');
  String get copy => _t('copy');
  String get copyAsText => _t('copyAsText');
  String get paste => _t('paste');
  String get pasteHere => _t('pasteHere');
  String get duplicate => _t('duplicate');
  String get addWaypoint =>
      locale.languageCode == 'zh' ? '添加路径点' : 'Add Waypoint';
  String get removeWaypoint =>
      locale.languageCode == 'zh' ? '移除路径点' : 'Remove Waypoint';
  String get clearWaypoints => _t('clearWaypoints');
  String get selectConnections =>
      locale.languageCode == 'zh' ? '选择关联连接线' : 'Select Connections';
  String get clearAnchors =>
      locale.languageCode == 'zh' ? '清除固定锚点' : 'Clear Anchors';
  String get bringToFront => _t('bringToFront');
  String get sendToBack => _t('sendToBack');
  String get bringForward => _t('bringForward');
  String get sendBackward => _t('sendBackward');
  String get bringForwardShortcut => _t('bringForwardShortcut');
  String get sendBackwardShortcut => _t('sendBackwardShortcut');
  String get group => _t('group');
  String get ungroup => _t('ungroup');
  String get removeFromGroup =>
      locale.languageCode == 'zh' ? '移出组合' : 'Remove from Group';
  String get collapseSelection =>
      locale.languageCode == 'zh' ? '折叠所选容器' : 'Collapse Selection';
  String get expandSelection =>
      locale.languageCode == 'zh' ? '展开所选容器' : 'Expand Selection';
  String get groupShortcut => _t('groupShortcut');
  String get ungroupShortcut => _t('ungroupShortcut');
  String get flipHorizontal => _t('flipHorizontal');
  String get flipVertical => _t('flipVertical');
  String get rotateLeft90 => _t('rotateLeft90');
  String get rotateRight90Shortcut => _t('rotateRight90Shortcut');
  String get rotateRight90 =>
      locale.languageCode == 'zh' ? '向右旋转 90°' : 'Rotate 90° right';
  String get turnSelection =>
      locale.languageCode == 'zh' ? '旋转 / 反向' : 'Turn / Reverse';
  String get centerHorizontally => _t('centerHorizontally');
  String get centerHorizontallyPage => _t('centerHorizontallyPage');
  String get centerVertically => _t('centerVertically');
  String get centerVerticallyPage => _t('centerVerticallyPage');
  String get justify => _t('justify');
  String get spaceBefore => _t('spaceBefore');
  String get spaceAfter => _t('spaceAfter');
  String get dropToOpen => _t('dropToOpen');
  String openFileFailed(String error) =>
      _t('openFileFailed').replaceAll('{error}', error);
  String openPathFailed(String path) =>
      _t('openPathFailed').replaceAll('{path}', path);
  String get vsdImportedSaveAsVsdx => _t('vsdImportedSaveAsVsdx');
  String openExampleFailed(String name) =>
      _t('openExampleFailed').replaceAll('{name}', name);
  String get insertImageFailed => _t('insertImageFailed');
  String replacedWith(String name) =>
      _t('replacedWith').replaceAll('{name}', name);
  String insertedNamed(String name) =>
      _t('insertedNamed').replaceAll('{name}', name);
  String get editText => _t('editText');
  String get replaceImage => _t('replaceImage');
  String get addLane => _t('addLane');
  String get removeLane => _t('removeLane');
  String get addRow => _t('addRow');
  String get addColumn => _t('addColumn');
  String get deleteRow => _t('deleteRow');
  String get deleteColumn => _t('deleteColumn');
  String get mergeCells => _t('mergeCells');
  String get unmergeCells => _t('unmergeCells');
  String get clearGuides => _t('clearGuides');

  // --- Tools ---
  String get toolSelect => _t('toolSelect');
  String get toolPan => _t('toolPan');
  String get toolRectangle => _t('toolRectangle');
  String get toolEllipse => _t('toolEllipse');
  String get toolLine => _t('toolLine');
  String get toolConnector => _t('toolConnector');
  String get toolFreehand => _t('toolFreehand');
  String get toolText => _t('toolText');
  String get moreShapes => _t('moreShapes');
  String get searchShapes => _t('searchShapes');
  String get imageMaterials => _t('imageMaterials');
  String get searchImages => _t('searchImages');
  String get thirdPartyIcons => _t('thirdPartyIcons');
  String get searchIcons => _t('searchIcons');
  String get chartsLibrary => _t('chartsLibrary');
  String get searchCharts => _t('searchCharts');
  String get iconLicenseHint => _t('iconLicenseHint');
  String get addIconLabel => _t('addIconLabel');
  String categoriesCount(int n) =>
      _t('categoriesCount').replaceAll('{n}', '$n');
  String get expandAll => _t('expandAll');
  String get collapseAll => _t('collapseAll');

  // --- Pages / tabs ---
  String get addPage => _t('addPage');
  String get duplicatePage => _t('duplicatePage');
  String get deletePage => _t('deletePage');
  String get renamePage => _t('renamePage');
  String get pageNameHint => _t('pageNameHint');
  String get pageReorderHint => _t('pageReorderHint');
  String get backgroundPageReorderHint => _t('backgroundPageReorderHint');

  // --- Status / empty ---
  String pageOf(int current, int total) => _t('pageOf')
      .replaceAll('{current}', '$current')
      .replaceAll('{total}', '$total');
  String get unsaved => _t('unsaved');
  String get noSelection => _t('noSelection');
  String selectedCount(int n) =>
      _t('selectedCount').replaceAll('{n}', '$n');
  String get emptySubtitle => _t('emptySubtitle');
  String get newDrawing => _t('newDrawing');
  String get newFromTemplate => _t('newFromTemplate');
  String get chooseTemplateHint => _t('chooseTemplateHint');
  String get openVisioDrawing => _t('openVisioDrawing');
  String get orTrySample => _t('orTrySample');
  String get dropHint => _t('dropHint');
  String get browseTemplates => _t('browseTemplates');

  // --- Dialogs ---
  String get discardUnsavedTitle => _t('discardUnsavedTitle');
  String discardUnsavedBody(String name) =>
      _t('discardUnsavedBody').replaceAll('{name}', name);
  String savedTo(String path) => _t('savedTo').replaceAll('{path}', path);
  String saveFailed(String error) =>
      _t('saveFailed').replaceAll('{error}', error);
  String exportedSvg(String path) =>
      _t('exportedSvg').replaceAll('{path}', path);
  String exportedPng(String path) =>
      _t('exportedPng').replaceAll('{path}', path);
  String exportedPdf(String path) =>
      _t('exportedPdf').replaceAll('{path}', path);
  String svgExportFailed(String error) =>
      _t('svgExportFailed').replaceAll('{error}', error);
  String get pngExportFailed => _t('pngExportFailed');
  String pngExportFailedError(String error) =>
      _t('pngExportFailedError').replaceAll('{error}', error);
  String pdfExportFailed(String error) =>
      _t('pdfExportFailed').replaceAll('{error}', error);

  // --- Format / Diagram panels ---
  String get panelArrange => _t('panelArrange');
  String get panelAlign => _t('panelAlign');
  String get panelAlignToPage => _t('panelAlignToPage');
  String get panelFill => _t('panelFill');
  String get panelLine => _t('panelLine');
  String get panelConnector => _t('panelConnector');
  String get panelShadow => _t('panelShadow');
  String get panelGlow => _t('panelGlow');
  String get panelReflection => _t('panelReflection');
  String get panelSoftEdges => _t('panelSoftEdges');
  String get panelText => _t('panelText');
  String get panelImage => _t('panelImage');
  String get panelData => _t('panelData');
  String get panelChart => _t('panelChart');
  String get panelIcon => _t('panelIcon');
  String get iconConfigHint => _t('iconConfigHint');
  String get iconProvider => _t('iconProvider');
  String get chartValues => _t('chartValues');
  String get chartValuesHint => _t('chartValuesHint');
  String get applyChart => _t('applyChart');
  String get chartSeries => _t('chartSeries');
  String get chartType => _t('chartType');
  String get chartItems => _t('chartItems');
  String get chartAddItem => _t('chartAddItem');
  String get chartRemoveItem => _t('chartRemoveItem');
  String get chartValue => _t('chartValue');
  String get chartItemLabel => _t('chartItemLabel');
  String get chartMoveUp => _t('chartMoveUp');
  String get chartMoveDown => _t('chartMoveDown');
  String get chartLevel => _t('chartLevel');
  String get chartConfigHint => _t('chartConfigHint');
  String get chartPasteValues => _t('chartPasteValues');
  String get chartPasteHint => _t('chartPasteHint');
  String get chartEqualize => _t('chartEqualize');
  String get chartSpecialtyCandlestickHint =>
      _t('chartSpecialtyCandlestickHint');
  String get chartSpecialtyHeatmapHint => _t('chartSpecialtyHeatmapHint');
  String get chartSpecialtyGanttHint => _t('chartSpecialtyGanttHint');
  String get chartSpecialtyBoxplotHint => _t('chartSpecialtyBoxplotHint');
  String get chartSpecialtySlopeHint => _t('chartSpecialtySlopeHint');
  String get chartSpecialtyCalendarHint => _t('chartSpecialtyCalendarHint');
  String get chartSpecialtyRangeBarHint => _t('chartSpecialtyRangeBarHint');
  String get chartSpecialtyDumbbellHint => _t('chartSpecialtyDumbbellHint');
  String get chartSpecialtyQuadrantHint => _t('chartSpecialtyQuadrantHint');
  String get chartSpecialtyTimelineHint => _t('chartSpecialtyTimelineHint');
  String get chartSpecialtyNestedDonutHint => _t('chartSpecialtyNestedDonutHint');
  String get chartSpecialtyKpiHint => _t('chartSpecialtyKpiHint');
  String get chartSpecialtyTableHint => _t('chartSpecialtyTableHint');
  String get chartSpecialtyVennHint => _t('chartSpecialtyVennHint');
  String get chartSpecialtyScorecardHint => _t('chartSpecialtyScorecardHint');
  String get chartSpecialtyRadialMultiHint => _t('chartSpecialtyRadialMultiHint');
  String get chartSpecialtySpanHint => _t('chartSpecialtySpanHint');
  String get chartSpecialtyRankingHint => _t('chartSpecialtyRankingHint');
  String get chartSpecialtyProcessHint => _t('chartSpecialtyProcessHint');
  String get chartSpecialtyArcGaugeHint => _t('chartSpecialtyArcGaugeHint');
  String get chartSpecialtyBulletGroupHint => _t('chartSpecialtyBulletGroupHint');
  String get chartSpecialtyLikertHint => _t('chartSpecialtyLikertHint');
  String get chartSpecialtyHeatStripHint => _t('chartSpecialtyHeatStripHint');
  String get chartSpecialtyDualCompareHint => _t('chartSpecialtyDualCompareHint');
  String get chartSpecialtyStatusBoardHint => _t('chartSpecialtyStatusBoardHint');
  String get chartSpecialtyProgressListHint => _t('chartSpecialtyProgressListHint');
  String get chartSpecialtyMilestoneHint => _t('chartSpecialtyMilestoneHint');
  String get chartSpecialtyBalanceBarHint => _t('chartSpecialtyBalanceBarHint');
  String get chartSpecialtyMeterClusterHint => _t('chartSpecialtyMeterClusterHint');
  String get chartSpecialtyPriorityMatrixHint => _t('chartSpecialtyPriorityMatrixHint');
  String get chartSpecialtyCycleFlowHint => _t('chartSpecialtyCycleFlowHint');
  String get chartSpecialtyCheckboxListHint => _t('chartSpecialtyCheckboxListHint');
  String get chartSpecialtyGapAnalysisHint => _t('chartSpecialtyGapAnalysisHint');
  String get chartSpecialtyStageFunnelHint => _t('chartSpecialtyStageFunnelHint');
  String get chartSpecialtyRhythmBarsHint => _t('chartSpecialtyRhythmBarsHint');
  String get chartSpecialtyVoteStackHint => _t('chartSpecialtyVoteStackHint');
  String get chartSpecialtyTrafficRowHint => _t('chartSpecialtyTrafficRowHint');
  String get chartSpecialtyStarRatingHint => _t('chartSpecialtyStarRatingHint');
  String get chartSpecialtyCompareCardsHint => _t('chartSpecialtyCompareCardsHint');
  String get chartSpecialtyPipelineHint => _t('chartSpecialtyPipelineHint');
  String get chartSpecialtyWinLossStripHint => _t('chartSpecialtyWinLossStripHint');
  String get chartSpecialtyQuotaBoardHint => _t('chartSpecialtyQuotaBoardHint');
  String get chartSpecialtyTickLadderHint => _t('chartSpecialtyTickLadderHint');
  String get chartWin => _t('chartWin');
  String get chartLoss => _t('chartLoss');
  String get chartQuadrant => _t('chartQuadrant');
  String get chartCells => _t('chartCells');
  String get chartSegment => _t('chartSegment');
  String get chartStatusOk => _t('chartStatusOk');
  String get chartStatusWarn => _t('chartStatusWarn');
  String get chartStatusBad => _t('chartStatusBad');
  String get chartVennSetA => _t('chartVennSetA');
  String get chartVennSetB => _t('chartVennSetB');
  String get chartVennOnlyA => _t('chartVennOnlyA');
  String get chartVennOnlyB => _t('chartVennOnlyB');
  String get chartVennBothLabel => _t('chartVennBothLabel');
  String get chartVennBothValue => _t('chartVennBothValue');
  String get chartRing => _t('chartRing');
  String get chartAddRing => _t('chartAddRing');
  String get chartStepName => _t('chartStepName');
  String get chartStepStatus => _t('chartStepStatus');
  String get chartStepDone => _t('chartStepDone');
  String get chartStepCurrent => _t('chartStepCurrent');
  String get chartStepTodo => _t('chartStepTodo');
  String get chartAddStep => _t('chartAddStep');
  String get chartTableHeader => _t('chartTableHeader');
  String get chartTableBorders => _t('chartTableBorders');
  String get chartTableZebra => _t('chartTableZebra');
  String get chartHeaderFill => _t('chartHeaderFill');
  String get chartBodyFill => _t('chartBodyFill');
  String get chartZebraFill => _t('chartZebraFill');
  String get chartCellText => _t('chartCellText');
  String get chartCandle => _t('chartCandle');
  String get chartOpen => _t('chartOpen');
  String get chartHigh => _t('chartHigh');
  String get chartLow => _t('chartLow');
  String get chartClose => _t('chartClose');
  String get chartAddCandle => _t('chartAddCandle');
  String get chartRows => _t('chartRows');
  String get chartCols => _t('chartCols');
  String get chartTaskName => _t('chartTaskName');
  String get chartStart => _t('chartStart');
  String get chartDuration => _t('chartDuration');
  String get chartAddTask => _t('chartAddTask');
  String get chartMin => _t('chartMin');
  String get chartQ1 => _t('chartQ1');
  String get chartMedian => _t('chartMedian');
  String get chartQ3 => _t('chartQ3');
  String get chartMax => _t('chartMax');
  String get chartBefore => _t('chartBefore');
  String get chartAfter => _t('chartAfter');
  String get chartWeeks => _t('chartWeeks');
  String get chartWeekdaysShort => _t('chartWeekdaysShort');
  String get chartStartValue => _t('chartStartValue');
  String get chartEndValue => _t('chartEndValue');
  String get chartAxisX => _t('chartAxisX');
  String get chartAxisY => _t('chartAxisY');
  String get chartEventName => _t('chartEventName');
  String get chartPosition => _t('chartPosition');
  String get chartAddEvent => _t('chartAddEvent');
  String get chartInnerSlices => _t('chartInnerSlices');
  String get chartInnerRing => _t('chartInnerRing');
  String get chartOuterRing => _t('chartOuterRing');
  String get chartKpiName => _t('chartKpiName');
  String get chartActual => _t('chartActual');
  String get chartTarget => _t('chartTarget');
  String get chartSeriesA => _t('chartSeriesA');
  String get chartSeriesB => _t('chartSeriesB');
  String chartDefaultItem(int n) =>
      _t('chartDefaultItem').replaceAll('{n}', '$n');
  String chartKindGroup(String english) {
    final key = 'cg_${english.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}';
    return kEditorL10nTables[locale.languageCode]?[key] ??
        _en[key] ??
        english;
  }
  String get panelLink => _t('panelLink');
  String get panelDiagram => _t('panelDiagram');
  String get panelView => _t('panelView');
  String get opacity => _t('opacity');
  String get size => _t('size');
  String get color => _t('color');
  String get rounded => _t('rounded');
  String get gradient => _t('gradient');
  String get linear => _t('linear');
  String get radial => _t('radial');
  String get start => _t('start');
  String get end => _t('end');
  String get blur => _t('blur');
  String get offsetX => _t('offsetX');
  String get offsetY => _t('offsetY');
  String get dist => _t('dist');
  String get solid => _t('solid');
  String get dashed => _t('dashed');
  String get dotted => _t('dotted');
  String get straight => _t('straight');
  String get orthogonal => _t('orthogonal');
  String get curved => _t('curved');
  String get bold => _t('bold');
  String get italic => _t('italic');
  String get underline => _t('underline');
  String get strikethrough => _t('strikethrough');
  String get dashDot => _t('dashDot');
  String get compoundSingle => _t('compoundSingle');
  String get compoundDouble => _t('compoundDouble');
  String get compoundThickThin => _t('compoundThickThin');
  String get compoundThinThick => _t('compoundThinThick');
  String get arrowFilled => _t('arrowFilled');
  String get arrowOpen => _t('arrowOpen');
  String get arrowThin => _t('arrowThin');
  String get arrowStealth => _t('arrowStealth');
  String get arrowCircle => _t('arrowCircle');
  String get arrowOpenDiamond => _t('arrowOpenDiamond');
  String get arrowCircleOpen => _t('arrowCircleOpen');
  String arrowNumbered(int id) =>
      _t('arrowNumbered').replaceAll('{id}', '$id');
  String get defaultFont => _t('defaultFont');
  String get noResults => _t('noResults');
  String get matchCaseOn => _t('matchCaseOn');
  String get matchCaseOff => _t('matchCaseOff');
  String get wholeWordOn => _t('wholeWordOn');
  String get wholeWordOff => _t('wholeWordOff');
  String get previousShortcut => _t('previousShortcut');
  String get nextShortcut => _t('nextShortcut');
  String get hideReplace => _t('hideReplace');
  String get showReplaceShortcut => _t('showReplaceShortcut');
  String get closeEsc => _t('closeEsc');
  String get backgroundPageHint => _t('backgroundPageHint');
  String get useBackground => _t('useBackground');
  String willMarkBackground(String name) =>
      _t('willMarkBackground').replaceAll('{name}', name);
  String get corners => _t('corners');
  String get jumpRadius => _t('jumpRadius');
  String get patternBrick => _t('patternBrick');
  String get patternShingle => _t('patternShingle');
  String get lineSpacing => _t('lineSpacing');
  String get curvedText => _t('curvedText');
  String get bulletList => _t('bulletList');
  String get superscript => locale.languageCode == 'zh'
      ? '上标 (Cmd/Ctrl+.)'
      : 'Superscript (Cmd/Ctrl+.)';
  String get subscript => locale.languageCode == 'zh'
      ? '下标 (Cmd/Ctrl+,)'
      : 'Subscript (Cmd/Ctrl+,)';
  String get clearTextFormatting =>
      locale.languageCode == 'zh' ? '清除文字格式' : 'Remove Formatting';
  String get noShapeData => _t('noShapeData');
  String get copyData =>
      locale.languageCode == 'zh' ? '复制形状数据' : 'Copy Data';
  String get pasteData =>
      locale.languageCode == 'zh' ? '粘贴形状数据' : 'Paste Data';
  String get noLink => _t('noLink');
  String get alignLeft => _t('alignLeft');
  String get alignRight => _t('alignRight');
  String get alignTop => _t('alignTop');
  String get alignBottom => _t('alignBottom');
  String get alignCenterH => _t('alignCenterH');
  String get alignCenterV => _t('alignCenterV');
  String get alignLeftPage => _t('alignLeftPage');
  String get alignRightPage => _t('alignRightPage');
  String get alignTopPage => _t('alignTopPage');
  String get alignBottomPage => _t('alignBottomPage');
  String get distributeH => _t('distributeH');
  String get distributeV => _t('distributeV');
  String get distributeSpacingH => locale.languageCode == 'zh'
      ? '水平等间距分布'
      : 'Distribute Horizontal Spacing';
  String get distributeSpacingV => locale.languageCode == 'zh'
      ? '垂直等间距分布'
      : 'Distribute Vertical Spacing';
  String get sameSize => _t('sameSize');
  String get sameWidth => _t('sameWidth');
  String get sameHeight => _t('sameHeight');
  String get swapShapes =>
      locale.languageCode == 'zh' ? '交换形状位置' : 'Swap Shapes';
  String get copySize =>
      locale.languageCode == 'zh' ? '复制尺寸' : 'Copy Size';
  String get pasteSize =>
      locale.languageCode == 'zh' ? '粘贴尺寸' : 'Paste Size';
  String get reverseConnector =>
      locale.languageCode == 'zh' ? '反向连接线' : 'Reverse Connector';
  String get autosize =>
      locale.languageCode == 'zh' ? '自动适配文本高度' : 'Autosize';
  String get autosizeShortcut =>
      locale.languageCode == 'zh'
          ? '自动适配文本高度 (Cmd/Ctrl+Shift+Y)'
          : 'Autosize (Cmd/Ctrl+Shift+Y)';
  String get stencilModifierShortcutHint =>
      locale.languageCode == 'zh'
          ? '拖到形状：替换 · 拖到方向箭头/连接线端点：接入\n'
              '点击时选中悬空连接线：接入\n'
              'Shift 点击/拖动：替换或原始样式 · Alt 点击：放到底部左侧\n'
              'Shift/Alt 拖动：重叠 · Alt+Shift/Ctrl 点击：插入并连接'
          : 'Drop on shape: replace · Drop on arrow/connector end: attach\n'
              'Click with free connector selected: attach\n'
              'Shift click/drag: replace or original style · Alt click: bottom-left\n'
              'Shift/Alt drag: overlap · Alt+Shift/Ctrl click: insert & connect';
  String get deleteWithConnectionsHint =>
      locale.languageCode == 'zh'
          ? '删除；按住 Shift 点击可同时删除相关连接线'
          : 'Delete; Shift+click to also delete connected lines';
  String get labelPosition =>
      locale.languageCode == 'zh' ? '标签位置' : 'Label Position';
  String get labelPositionLeft =>
      locale.languageCode == 'zh' ? '标签置于左侧' : 'Position label left';
  String get labelPositionTop =>
      locale.languageCode == 'zh' ? '标签置于上方' : 'Position label above';
  String get labelPositionCenter =>
      locale.languageCode == 'zh' ? '标签居中' : 'Center label';
  String get labelPositionBottom =>
      locale.languageCode == 'zh' ? '标签置于下方' : 'Position label below';
  String get labelPositionRight =>
      locale.languageCode == 'zh' ? '标签置于右侧' : 'Position label right';
  String get verticalText =>
      locale.languageCode == 'zh' ? '竖排文字' : 'Vertical Text';
  String get grid => _t('grid');
  String get background => _t('background');
  String get backgroundPage => _t('backgroundPage');
  String get theme => _t('theme');
  String get paperSize => _t('paperSize');
  String get portrait => _t('portrait');
  String get landscape => _t('landscape');
  String get noneDefault => _t('noneDefault');
  String get custom => _t('custom');
  String get zoomIn => _t('zoomIn');
  String get zoomOut => _t('zoomOut');

  // --- Find ---
  String get findShapesHint => _t('findShapesHint');
  String get replaceWithHint => _t('replaceWithHint');
  String get replace => _t('replace');
  String get replaceAll => _t('replaceAll');
  String get previous => _t('previous');
  String get next => _t('next');

  // --- Layers / data / link dialogs ---
  String get renameLayer => _t('renameLayer');
  String get name => _t('name');
  String get value => _t('value');
  String get addProperty => _t('addProperty');
  String get remove => _t('remove');
  String get noLayersYet => _t('noLayersYet');
  String get visible => _t('visible');
  String get locked => _t('locked');
  String get print => _t('print');
  String get colorByLayer => _t('colorByLayer');
  String get assignSelection => _t('assignSelection');
  String get deleteLayer => _t('deleteLayer');
  String get addLayer => _t('addLayer');
  String get addLayerWithSelection => _t('addLayerWithSelection');
  String get labelOptional => _t('labelOptional');
  String get removeLink => _t('removeLink');
  String get link => _t('link');
  String get noShapeDataHint => _t('noShapeDataHint');
  String get linkHint => _t('linkHint');

  /// Localized stencil group name; falls back to English [name].
  String stencilGroup(String name) {
    final key = 'sg_$name';
    return kEditorL10nTables[locale.languageCode]?[key] ?? _en[key] ?? name;
  }

  /// Localized stencil shape name; falls back to English [name].
  String stencil(String name) {
    final key = 'st_${_stencilKey(name)}';
    return kEditorL10nTables[locale.languageCode]?[key] ?? _en[key] ?? name;
  }

  /// True if [englishName] or its translation matches [query] (lowercase).
  bool stencilMatches(String englishName, String query) {
    if (query.isEmpty) return true;
    if (englishName.toLowerCase().contains(query)) return true;
    return stencil(englishName).toLowerCase().contains(query);
  }

  /// Localized image-material group name; falls back to English [name].
  String imageMaterialGroup(String name) {
    final key = 'ig_$name';
    return kEditorL10nTables[locale.languageCode]?[key] ?? _en[key] ?? name;
  }

  /// Localized image-material name; falls back to English [name].
  String imageMaterial(String name) {
    final key = 'im_${_stencilKey(name)}';
    return kEditorL10nTables[locale.languageCode]?[key] ?? _en[key] ?? name;
  }

  /// True if [englishName] or its translation matches [query] (lowercase).
  bool imageMaterialMatches(String englishName, String query) {
    if (query.isEmpty) return true;
    if (englishName.toLowerCase().contains(query)) return true;
    return imageMaterial(englishName).toLowerCase().contains(query);
  }

  static String _stencilKey(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
}
