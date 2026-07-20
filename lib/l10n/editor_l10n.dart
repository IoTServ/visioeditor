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
  String get find => _t('find');
  String get findShortcut => _t('findShortcut');
  String get findReplace => _t('findReplace');
  String get findReplaceShortcut => _t('findReplaceShortcut');
  String get editData => _t('editData');
  String get editDataShortcut => _t('editDataShortcut');
  String get editLink => _t('editLink');
  String get editLinkShortcut => _t('editLinkShortcut');
  String get editConnectionPoints => _t('editConnectionPoints');
  String get doneEditingConnectionPoints => _t('doneEditingConnectionPoints');
  String get lock => _t('lock');
  String get unlock => _t('unlock');
  String get lockShortcut => _t('lockShortcut');
  String get unlockShortcut => _t('unlockShortcut');
  String get zoomToSelection => _t('zoomToSelection');
  String get copyStyle => _t('copyStyle');
  String get copyStyleShortcut => _t('copyStyleShortcut');
  String get pasteStyle => _t('pasteStyle');
  String get pasteStyleShortcut => _t('pasteStyleShortcut');
  String get saveAs => _t('saveAs');
  String get exportSvg => _t('exportSvg');
  String get exportPng => _t('exportPng');
  String get exportPdf => _t('exportPdf');
  String get snapToGrid => _t('snapToGrid');
  String get lineJumps => _t('lineJumps');
  String get closeTab => _t('closeTab');
  String get closeTabShortcut => _t('closeTabShortcut');

  // --- Context menu ---
  String get cut => _t('cut');
  String get copy => _t('copy');
  String get paste => _t('paste');
  String get pasteHere => _t('pasteHere');
  String get duplicate => _t('duplicate');
  String get clearWaypoints => _t('clearWaypoints');
  String get bringToFront => _t('bringToFront');
  String get sendToBack => _t('sendToBack');
  String get bringForward => _t('bringForward');
  String get sendBackward => _t('sendBackward');
  String get bringForwardShortcut => _t('bringForwardShortcut');
  String get sendBackwardShortcut => _t('sendBackwardShortcut');
  String get group => _t('group');
  String get ungroup => _t('ungroup');
  String get groupShortcut => _t('groupShortcut');
  String get ungroupShortcut => _t('ungroupShortcut');
  String get flipHorizontal => _t('flipHorizontal');
  String get flipVertical => _t('flipVertical');
  String get rotateLeft90 => _t('rotateLeft90');
  String get rotateRight90Shortcut => _t('rotateRight90Shortcut');
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
  String get openVisioDrawing => _t('openVisioDrawing');
  String get orTrySample => _t('orTrySample');
  String get dropHint => _t('dropHint');

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
  String get noShapeData => _t('noShapeData');
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
  String get sameSize => _t('sameSize');
  String get sameWidth => _t('sameWidth');
  String get sameHeight => _t('sameHeight');
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
