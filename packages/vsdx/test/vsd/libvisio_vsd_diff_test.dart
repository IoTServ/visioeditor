import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

import '../support/libvisio_oracle.dart';

void main() {
  final oracle = LibvisioOracle.tryLoad();
  final skipReason = oracle == null
      ? 'libvisio shim not built — run packages/vsdx/native/build.sh'
      : null;

  test('Visio binary versions 1–4 follow libvisio VSD5 dispatch', () {
    final source = File(
      '../../third_party/libvisio/src/test/data/Visio5PlanWithDimensions.vsd',
    );
    if (!source.existsSync()) {
      markTestSkipped('libvisio VSD5 fixture is unavailable');
      return;
    }
    final baseline = source.readAsBytesSync();
    for (var version = 1; version <= 4; version++) {
      final bytes = _withLegacyVisioVersion(baseline, version);
      final reference = oracle!.svgPages(bytes);
      expect(reference, isNotNull, reason: 'libvisio version $version parse');

      final document = const VsdDocumentParser().parse(bytes);
      expect(document.pages, hasLength(reference!.length));
      final synthesized = synthesizeVsdx(document);
      final rendered = oracle.svgPages(synthesized);
      expect(rendered, isNotNull, reason: 'version $version VSDX reopen');
      expect(rendered, hasLength(reference.length));
      expect(
        _svgTextCharacters(rendered!),
        isNotEmpty,
        reason: 'version $version text must survive VSD → VSDX',
      );
    }
  }, skip: skipReason);

  for (final fixture in _fixtures()) {
    test('${fixture.uri.pathSegments.last} page structure matches libvisio',
        () {
      final bytes = fixture.readAsBytesSync();
      final reference = oracle!.svgPages(bytes);
      if (reference == null) {
        markTestSkipped('libvisio does not parse ${fixture.path}');
        return;
      }

      final doc = const VsdDocumentParser().parse(bytes);
      expect(doc.pages.length, reference.length,
          reason: '${fixture.path} page count');
      for (var i = 0; i < reference.length; i++) {
        final size = _svgSizeInches(reference[i]);
        if (size == null) continue;
        expect(doc.pages[i].widthInches, closeTo(size.$1, 0.02),
            reason: '${fixture.path} page $i width');
        expect(doc.pages[i].heightInches, closeTo(size.$2, 0.02),
            reason: '${fixture.path} page $i height');
      }

      final referenceFontSizes = reference
          .expand(_svgVisibleFontSizesPt)
          .map(_roundHalfPoint)
          .toSet();
      if (referenceFontSizes.isNotEmpty) {
        final modelFontSizes = _allShapes(doc)
            .where((shape) => !shape.richText.textBlock.hideText)
            .expand((shape) => shape.richText.runs)
            .where((run) => run.text.trim().isNotEmpty)
            .map((run) => _roundHalfPoint(run.charStyle.fontSizeInches * 72))
            .toSet();
        expect(modelFontSizes, referenceFontSizes,
            reason: '${fixture.path} visible text font sizes');
      }

      if (fixture.uri.pathSegments.last == 'dwg.vsd') {
        final shadows =
            _allShapes(doc).where((shape) => shape.shadow.enabled).toList();
        expect(shadows, isNotEmpty,
            reason: 'VSD FillAndShadow records must reach the model');
        for (final shape in shadows) {
          expect(shape.shadow.pattern, 1);
          expect(shape.shadow.transparency, closeTo(199 / 255, 1e-9));
          expect(shape.shadow.offsetXInches, closeTo(0.0048, 1e-9));
          expect(shape.shadow.offsetYInches, closeTo(-0.0274, 1e-9));
          expect(shape.shadow.blurInches, 0,
              reason: 'binary Visio shadows are unblurred');
        }

        final reopened = const DocumentParser().parse(synthesizeVsdx(doc));
        final reopenedById = <int, VsdxShape>{
          for (final shape in _allShapes(reopened)) shape.id: shape,
        };
        for (final shape in shadows) {
          final after = reopenedById[shape.id];
          expect(after, isNotNull);
          expect(after!.shadow.enabled, isTrue);
          expect(after.shadow.pattern, shape.shadow.pattern);
          expect(after.shadow.transparency,
              closeTo(shape.shadow.transparency, 1e-9));
          expect(after.shadow.offsetXInches,
              closeTo(shape.shadow.offsetXInches, 1e-9));
          expect(after.shadow.offsetYInches,
              closeTo(shape.shadow.offsetYInches, 1e-9));
          expect(after.shadow.blurInches, shape.shadow.blurInches);
        }
      }
      if (fixture.uri.pathSegments.last == 'tdf76829-datetime-format.vsd') {
        final transparentFills = _allShapes(doc)
            .where((shape) => shape.fill.foregroundTransparency > 0.99)
            .toList();
        expect(transparentFills, isNotEmpty,
            reason: 'binary alpha is transparency, not opacity');
        for (final shape in transparentFills) {
          expect(shape.fill.foreground?.alpha, 255,
              reason: 'fill transparency must not be applied twice');
        }
      }
      if (fixture.uri.pathSegments.last == 'Visio6PlanWithDimensions.vsd') {
        final referenceWidths = reference
            .expand(_svgStrokeWidthsPt)
            .map(_round6)
            .toSet();
        final modelWidths = _allShapes(doc)
            .where((shape) =>
                shape.line.pattern != 0 &&
                (shape.geometries.isEmpty ||
                    shape.geometries.any((geometry) => !geometry.noLine)))
            .map((shape) => _round6(shape.line.weightInches * 72))
            .toSet();
        expect(modelWidths, referenceWidths,
            reason: 'page drawing scale must apply to VSD line widths');

        final referenceFontSizes =
            reference.expand(_svgFontSizesPt).map(_round6).toSet();
        final modelFontSizes = _allShapes(doc)
            .where((shape) => !shape.richText.textBlock.hideText)
            .expand((shape) => shape.richText.runs)
            .where((run) => run.text.trim().isNotEmpty)
            .map((run) => _round6(run.charStyle.fontSizeInches * 72))
            .toSet();
        expect(modelFontSizes, referenceFontSizes,
            reason: 'page drawing scale must not alter VSD font sizes');
      }
      if (const <String>{
        'tdf154379-DrawingUnits-type.vsd',
        'tdf76829-datetime-format.vsd',
      }.contains(fixture.uri.pathSegments.last)) {
        final backgrounds = doc.pages.where((page) => page.isBackgroundPage);
        expect(backgrounds, hasLength(1));
        expect(doc.pages.first.backgroundPageId, backgrounds.single.id,
            reason: 'foreground must retain its binary backgroundPageID');

        final reopened = const DocumentParser().parse(synthesizeVsdx(doc));
        final reopenedBackgrounds =
            reopened.pages.where((page) => page.isBackgroundPage);
        expect(reopenedBackgrounds, hasLength(1));
        expect(reopened.pages.first.backgroundPageId,
            reopenedBackgrounds.single.id,
            reason: 'VSD → VSDX must preserve the underlay relationship');
      }
      if (fixture.uri.pathSegments.last == 'bitmaps.vsd') {
        final images = _allShapes(doc)
            .where((shape) => shape.imagePartName != null)
            .toList();
        expect(images, isNotEmpty);
        for (final shape in images) {
          expect(shape.imgWidthInches, isNotNull,
              reason: 'ForeignData width must not be discarded');
          expect(shape.imgHeightInches, isNotNull,
              reason: 'ForeignData height must not be discarded');
          expect(shape.imgWidthInches!, greaterThan(0));
          expect(shape.imgHeightInches!, greaterThan(0));
        }

        final reopened = const DocumentParser().parse(synthesizeVsdx(doc));
        final reopenedById = <int, VsdxShape>{
          for (final shape in _allShapes(reopened)) shape.id: shape,
        };
        for (final shape in images) {
          final after = reopenedById[shape.id];
          expect(after, isNotNull);
          expect(
              after!.imgOffsetXInches, closeTo(shape.imgOffsetXInches, 1e-9));
          expect(after.imgOffsetYInches, closeTo(shape.imgOffsetYInches, 1e-9));
          expect(after.imgWidthInches, closeTo(shape.imgWidthInches!, 1e-9));
          expect(after.imgHeightInches, closeTo(shape.imgHeightInches!, 1e-9));
        }
      }

      // VSD has no binary writer; synthesis is its editable round-trip path.
      // Layer rows and page-local LayerMem values must survive that conversion
      // without being invented from stencil masters.
      final synthesized = synthesizeVsdx(doc);
      final reopened = const DocumentParser().parse(synthesized);
      final rendered = oracle.svgPages(synthesized);
      expect(rendered, isNotNull,
          reason: 'libvisio must accept the synthesized VSDX');
      expect(rendered, hasLength(reference.length));
      if (const <String>{
        'Visio5TextFieldsWithUnits.vsd',
        'Visio6TextFieldsWithUnits.vsd',
        'Visio11TextFieldsWithUnits.vsd',
      }.contains(fixture.uri.pathSegments.last)) {
        expect(
          _svgTextCharacters(rendered!),
          _modelTextCharacters(doc),
          reason:
              '${fixture.path} synthesized VSDX must restore every label '
              'even when direct legacy VSD import in libvisio omits fields',
        );
      }
      expect(reopened.pages, hasLength(doc.pages.length));
      for (var pageIndex = 0; pageIndex < doc.pages.length; pageIndex++) {
        final beforePage = doc.pages[pageIndex];
        final afterPage = reopened.pages[pageIndex];
        expect(afterPage.name, beforePage.name,
            reason: '${fixture.path} page $pageIndex name after synthesis');
        expect(afterPage.widthInches, closeTo(beforePage.widthInches, 1e-8),
            reason: '${fixture.path} page $pageIndex width after synthesis');
        expect(afterPage.heightInches, closeTo(beforePage.heightInches, 1e-8),
            reason: '${fixture.path} page $pageIndex height after synthesis');
        expect(afterPage.backgroundColor, beforePage.backgroundColor,
            reason:
                '${fixture.path} page $pageIndex background after synthesis');
        expect(afterPage.isBackgroundPage, beforePage.isBackgroundPage,
            reason:
                '${fixture.path} page $pageIndex background flag after synthesis');
        expect(afterPage.backgroundPageId, beforePage.backgroundPageId,
            reason:
                '${fixture.path} page $pageIndex background link after synthesis');
        expect(afterPage.pageSheet, beforePage.pageSheet,
            reason:
                '${fixture.path} page $pageIndex PageSheet after synthesis');
        if (beforePage.viewScale != null) {
          expect(afterPage.viewScale, closeTo(beforePage.viewScale!, 1e-8),
              reason:
                  '${fixture.path} page $pageIndex ViewScale after synthesis');
        }
        if (beforePage.viewCenterX != null) {
          expect(afterPage.viewCenterX,
              closeTo(beforePage.viewCenterX!, 1e-8),
              reason:
                  '${fixture.path} page $pageIndex ViewCenterX after synthesis');
        }
        if (beforePage.viewCenterY != null) {
          expect(afterPage.viewCenterY,
              closeTo(beforePage.viewCenterY!, 1e-8),
              reason:
                  '${fixture.path} page $pageIndex ViewCenterY after synthesis');
        }
        expect(_connectSignatures(afterPage.connects),
            _connectSignatures(beforePage.connects),
            reason: '${fixture.path} page $pageIndex connects after synthesis');
        expect(afterPage.layers, beforePage.layers,
            reason: '${fixture.path} page $pageIndex layers after synthesis');
        final afterById = <int, VsdxShape>{
          for (final shape in _allPageShapes(afterPage)) shape.id: shape,
        };
        for (final shape in _allPageShapes(beforePage)) {
          expect(
            afterById[shape.id]?.layerMemberIds,
            shape.layerMemberIds,
            reason:
                '${fixture.path} page $pageIndex shape ${shape.id} LayerMem',
          );
        }
        final beforePaths = _shapePaths(beforePage);
        final afterPaths = _shapePaths(afterPage);
        expect(afterPaths.keys, beforePaths.keys,
            reason: '${fixture.path} page $pageIndex shape hierarchy');
        for (final entry in beforePaths.entries) {
          _expectSynthesizedShape(
            entry.value,
            afterPaths[entry.key]!,
            reason: '${fixture.path} page $pageIndex ${entry.key}',
          );
        }
      }
    }, skip: skipReason);
  }
}

List<String> _connectSignatures(List<VsdxConnect> connects) => <String>[
      for (final connect in connects)
        '${connect.fromSheetId}|${connect.fromCell}|${connect.fromPart}|'
            '${connect.toSheetId}|${connect.toCell}|${connect.toPart}',
    ];

Iterable<VsdxShape> _allShapes(VsdxDocument document) sync* {
  Iterable<VsdxShape> walk(VsdxShape shape) sync* {
    yield shape;
    for (final child in shape.children) {
      yield* walk(child);
    }
  }

  for (final page in document.pages) {
    for (final shape in page.shapes) {
      yield* walk(shape);
    }
  }
}

Iterable<VsdxShape> _allPageShapes(VsdxPage page) sync* {
  Iterable<VsdxShape> walk(VsdxShape shape) sync* {
    yield shape;
    for (final child in shape.children) {
      yield* walk(child);
    }
  }

  for (final shape in page.shapes) {
    yield* walk(shape);
  }
}

List<File> _fixtures() {
  final byName = <String, File>{};
  for (final directory in <Directory>[
    Directory('../../third_party/libvisio/src/test/data'),
    Directory('test/fixtures/vsd'),
  ]) {
    if (!directory.existsSync()) continue;
    for (final file in directory
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()) {
      if (file.path.toLowerCase().endsWith('.vsd')) {
        byName[file.uri.pathSegments.last] = file;
      }
    }
  }
  final sample = File('../../assets/examples/sample.vsd');
  if (sample.existsSync()) byName['sample.vsd'] = sample;
  final out = byName.values.toList()..sort((a, b) => a.path.compareTo(b.path));
  return out;
}

(double, double)? _svgSizeInches(String svg) {
  final match =
      RegExp(r'width="([0-9.]+)in"\s+height="([0-9.]+)in"').firstMatch(svg);
  if (match == null) return null;
  return (double.parse(match.group(1)!), double.parse(match.group(2)!));
}

Iterable<double> _svgStrokeWidthsPt(String svg) =>
    RegExp(r'stroke-width:\s*([0-9.]+)')
        .allMatches(svg)
        .map((match) => double.parse(match.group(1)!));

Iterable<double> _svgFontSizesPt(String svg) =>
    RegExp(r'font-size="([0-9.]+)"')
        .allMatches(svg)
        .map((match) => double.parse(match.group(1)!));

Iterable<double> _svgVisibleFontSizesPt(String svg) sync* {
  for (final match in RegExp(
    r'<(?:\w+:)?tspan\b([^>]*)>(.*?)</(?:\w+:)?tspan>',
    dotAll: true,
  ).allMatches(svg)) {
    if (_unescapeXml(match.group(2)!).trim().isEmpty) continue;
    final size =
        RegExp(r'font-size="([0-9.]+)"').firstMatch(match.group(1)!);
    if (size != null) yield double.parse(size.group(1)!);
  }
}

String _svgTextCharacters(Iterable<String> pages) {
  final out = StringBuffer();
  for (final page in pages) {
    for (final match in RegExp(
      r'<(?:\w+:)?tspan\b[^>]*>(.*?)</(?:\w+:)?tspan>',
      dotAll: true,
    ).allMatches(page)) {
      out.write(_unescapeXml(match.group(1)!));
    }
  }
  return _sortedNonWhitespace(out.toString());
}

String _modelTextCharacters(VsdxDocument document) {
  final out = StringBuffer();
  for (final shape in _allShapes(document)) {
    if (!shape.richText.textBlock.hideText) {
      out.write(shape.richText.plainText);
    }
  }
  return _sortedNonWhitespace(out.toString());
}

String _sortedNonWhitespace(String text) {
  final characters = text.replaceAll(RegExp(r'\s+'), '').split('')..sort();
  return characters.join();
}

Uint8List _withLegacyVisioVersion(Uint8List source, int version) {
  final bytes = Uint8List.fromList(source);
  const magic = 'Visio (TM) Drawing\r\n\x00';
  for (var i = 0; i + magic.length <= bytes.length; i++) {
    var match = true;
    for (var j = 0; j < magic.length; j++) {
      if (bytes[i + j] != magic.codeUnitAt(j)) {
        match = false;
        break;
      }
    }
    if (match) {
      bytes[i + 0x1a] = version;
      return bytes;
    }
  }
  throw StateError('VisioDocument header not found in CFB');
}

Map<String, VsdxShape> _shapePaths(VsdxPage page) {
  final out = <String, VsdxShape>{};
  void walk(VsdxShape shape, String parent) {
    final path = '$parent/${shape.id}';
    out[path] = shape;
    for (final child in shape.children) {
      walk(child, path);
    }
  }

  for (final shape in page.shapes) {
    walk(shape, 'shape');
  }
  return out;
}

void _expectSynthesizedShape(
  VsdxShape before,
  VsdxShape after, {
  required String reason,
}) {
  void close(double? a, double? b, String field) {
    if (a == null || b == null) {
      expect(b, a, reason: '$reason $field');
    } else {
      expect(b, closeTo(a, 1e-8), reason: '$reason $field');
    }
  }

  close(before.pinX, after.pinX, 'PinX');
  close(before.pinY, after.pinY, 'PinY');
  close(before.width, after.width, 'Width');
  close(before.height, after.height, 'Height');
  close(before.locPinXInches, after.locPinXInches, 'LocPinX');
  close(before.locPinYInches, after.locPinYInches, 'LocPinY');
  close(before.angleRad, after.angleRad, 'Angle');
  close(before.beginX, after.beginX, 'BeginX');
  close(before.beginY, after.beginY, 'BeginY');
  close(before.endX, after.endX, 'EndX');
  close(before.endY, after.endY, 'EndY');
  expect(after.richText.plainText, _normalizeText(before.richText.plainText),
      reason: '$reason text');
  _expectRichText(before.richText, after.richText, reason: reason);
  expect(after.richText.tabSets, before.richText.tabSets,
      reason: '$reason tab sets');
  expect(after.fields, before.fields, reason: '$reason dynamic fields');
  expect(after.hyperlinks, before.hyperlinks, reason: '$reason hyperlinks');
  expect(after.userProperties, before.userProperties,
      reason: '$reason shape data');
  final synthesizedUserCells = after.userCells
      .where((cell) =>
          cell.name != VsdxShape.userVsdBeginArrowSize &&
          cell.name != VsdxShape.userVsdEndArrowSize)
      .toList();
  expect(synthesizedUserCells, before.userCells,
      reason: '$reason user cells');
  expect(after.controls, before.controls, reason: '$reason controls');
  expect(after.scratch, before.scratch, reason: '$reason scratch rows');
  expect(after.actions, before.actions, reason: '$reason actions');
  expect(after.connectionPoints, before.connectionPoints,
      reason: '$reason connection points');
  for (final formula in before.formulas.entries) {
    expect(after.formulas[formula.key], formula.value,
        reason: '$reason formula ${formula.key}');
  }
  expect(after.imagePartName, before.imagePartName,
      reason: '$reason image relationship');
  close(before.imgOffsetXInches, after.imgOffsetXInches, 'ImgOffsetX');
  close(before.imgOffsetYInches, after.imgOffsetYInches, 'ImgOffsetY');
  close(before.imgWidthInches, after.imgWidthInches, 'ImgWidth');
  close(before.imgHeightInches, after.imgHeightInches, 'ImgHeight');
  close(before.imageTransparency, after.imageTransparency, 'Transparency');
  close(before.imageBlur, after.imageBlur, 'Blur');
  close(before.imageBrightness, after.imageBrightness, 'Brightness');
  close(before.imageContrast, after.imageContrast, 'Contrast');
  expect(after.foreignType, before.foreignType, reason: '$reason ForeignType');
  if (before.foreignCompressionType != null) {
    expect(after.foreignCompressionType, before.foreignCompressionType,
        reason: '$reason CompressionType');
  }
  if (before.objType != null) {
    expect(after.objType, before.objType, reason: '$reason ObjType');
  }
  expect(after.resizeMode, before.resizeMode, reason: '$reason ResizeMode');
  expect(after.eventDblClick, before.eventDblClick,
      reason: '$reason EventDblClick');
  expect(after.noAlignBox, before.noAlignBox, reason: '$reason NoAlignBox');
  expect(after.shapeSplittable, before.shapeSplittable,
      reason: '$reason ShapeSplittable');
  expect(after.themeIndex, before.themeIndex, reason: '$reason ThemeIndex');
  expect(after.quickStyleFillMatrix, before.quickStyleFillMatrix,
      reason: '$reason QuickStyleFillMatrix');
  expect(after.quickStyleLineMatrix, before.quickStyleLineMatrix,
      reason: '$reason QuickStyleLineMatrix');
  expect(after.quickStyleEffectsMatrix, before.quickStyleEffectsMatrix,
      reason: '$reason QuickStyleEffectsMatrix');
  expect(after.quickStyleFontMatrix, before.quickStyleFontMatrix,
      reason: '$reason QuickStyleFontMatrix');
  expect(after.isTextEditTarget, before.isTextEditTarget,
      reason: '$reason IsTextEditTarget');
  expect(after.dontMoveChildren, before.dontMoveChildren,
      reason: '$reason DontMoveChildren');
  expect(after.selectMode, before.selectMode, reason: '$reason SelectMode');
  expect(after.displayMode, before.displayMode, reason: '$reason DisplayMode');
  expect(after.masterId, before.masterId, reason: '$reason Master');
  expect(after.masterShapeId, before.masterShapeId,
      reason: '$reason MasterShape');
  expect(after.lineStyleId, before.lineStyleId, reason: '$reason LineStyle');
  expect(after.fillStyleId, before.fillStyleId, reason: '$reason FillStyle');
  expect(after.textStyleId, before.textStyleId, reason: '$reason TextStyle');
  expect(after.fill.pattern, before.fill.pattern,
      reason: '$reason fill pattern');
  expect(after.fill.foreground, before.fill.foreground,
      reason: '$reason fill foreground');
  expect(after.fill.background, before.fill.background,
      reason: '$reason fill background');
  close(before.fill.foregroundTransparency,
      after.fill.foregroundTransparency, 'FillForegndTrans');
  close(before.fill.backgroundTransparency,
      after.fill.backgroundTransparency, 'FillBkgndTrans');
  final beforeGradient = before.fill.gradient;
  final afterGradient = after.fill.gradient;
  if (beforeGradient == null || afterGradient == null) {
    expect(afterGradient, beforeGradient, reason: '$reason fill gradient');
  } else {
    expect(afterGradient.type, beforeGradient.type,
        reason: '$reason fill gradient type');
    expect(afterGradient.dir, beforeGradient.dir,
        reason: '$reason fill gradient direction');
    close(beforeGradient.angleRad, afterGradient.angleRad,
        'FillGradientAngle');
    expect(afterGradient.stops.length, beforeGradient.stops.length,
        reason: '$reason fill gradient stops');
    for (var i = 0; i < beforeGradient.stops.length; i++) {
      final a = beforeGradient.stops[i];
      final b = afterGradient.stops[i];
      close(a.position, b.position, 'FillGradient[$i].Position');
      expect(b.color, a.color, reason: '$reason FillGradient[$i].Color');
      expect(b.themeColorIndex, a.themeColorIndex,
          reason: '$reason FillGradient[$i].ThemeColor');
      close(a.transparency, b.transparency,
          'FillGradient[$i].Transparency');
    }
  }
  expect(after.line.pattern, before.line.pattern,
      reason: '$reason line pattern');
  expect(after.line.color, before.line.color, reason: '$reason line color');
  close(before.line.weightInches, after.line.weightInches, 'LineWeight');
  close(before.line.transparency, after.line.transparency, 'LineColorTrans');
  expect(after.line.beginArrow, before.line.beginArrow,
      reason: '$reason begin arrow');
  expect(after.line.endArrow, before.line.endArrow,
      reason: '$reason end arrow');
  if (before.line.hasBeginArrow) {
    close(before.line.beginArrowSizeInches, after.line.beginArrowSizeInches,
        'BeginArrowSize');
  }
  if (before.line.hasEndArrow) {
    close(before.line.endArrowSizeInches, after.line.endArrowSizeInches,
        'EndArrowSize');
  }
  expect(after.shadow.enabled, before.shadow.enabled,
      reason: '$reason shadow enabled');
  expect(after.shadow.pattern, before.shadow.pattern,
      reason: '$reason shadow pattern');
  expect(after.shadow.color, before.shadow.color,
      reason: '$reason shadow color');
  expect(after.shadow.themeColorIndex, before.shadow.themeColorIndex,
      reason: '$reason shadow theme color');
  close(before.shadow.offsetXInches, after.shadow.offsetXInches,
      'ShadowOffsetX');
  close(before.shadow.offsetYInches, after.shadow.offsetYInches,
      'ShadowOffsetY');
  close(before.shadow.blurInches, after.shadow.blurInches, 'ShadowBlur');
  close(before.shadow.transparency, after.shadow.transparency,
      'ShadowTransparency');
  expect(after.geometries.length, before.geometries.length,
      reason: '$reason geometry sections');
  for (var i = 0; i < before.geometries.length; i++) {
    // libvisio's VSDX parser skips shape-level Rounding, so synthesis bakes
    // polyline fillets into RelQuadBezTo rows. Compare against that write.
    final a = bakePolylineRounding(
      before.geometries[i],
      width: before.width,
      height: before.height,
      radius: before.line.roundingInches,
    );
    final b = after.geometries[i];
    expect(b.ix, a.ix, reason: '$reason Geometry[$i] IX');
    expect(b.noFill, a.noFill, reason: '$reason Geometry[$i] NoFill');
    expect(b.noLine, a.noLine, reason: '$reason Geometry[$i] NoLine');
    expect(b.noShow, a.noShow, reason: '$reason Geometry[$i] NoShow');
    expect(b.commands.map((c) => c.runtimeType),
        a.commands.map((c) => c.runtimeType),
        reason: '$reason Geometry[$i] command topology');
    for (var commandIndex = 0;
        commandIndex < a.commands.length;
        commandIndex++) {
      expect(
        pathCommandsEqual(
          b.commands[commandIndex],
          a.commands[commandIndex],
        ),
        isTrue,
        reason: '$reason Geometry[$i] command $commandIndex values: '
            '${a.commands[commandIndex]} -> ${b.commands[commandIndex]}',
      );
    }
  }
}

void _expectRichText(
  VsdxRichText before,
  VsdxRichText after, {
  required String reason,
}) {
  void close(double? a, double? b, String field) {
    if (a == null || b == null) {
      expect(b, a, reason: '$reason $field');
    } else {
      expect(b, closeTo(a, 1e-8), reason: '$reason $field');
    }
  }

  final a = before.textBlock;
  final b = after.textBlock;
  if (a.pinXInches != null) close(a.pinXInches, b.pinXInches, 'TxtPinX');
  if (a.pinYInches != null) close(a.pinYInches, b.pinYInches, 'TxtPinY');
  if (a.locPinXInches != null) {
    close(a.locPinXInches, b.locPinXInches, 'TxtLocPinX');
  }
  if (a.locPinYInches != null) {
    close(a.locPinYInches, b.locPinYInches, 'TxtLocPinY');
  }
  if (a.widthInches != null) close(a.widthInches, b.widthInches, 'TxtWidth');
  if (a.heightInches != null) {
    close(a.heightInches, b.heightInches, 'TxtHeight');
  }
  close(a.angleRad, b.angleRad, 'TxtAngle');
  expect(b.verticalAlign, a.verticalAlign,
      reason: '$reason VerticalAlign');
  close(a.marginLeftInches, b.marginLeftInches, 'LeftMargin');
  close(a.marginRightInches, b.marginRightInches, 'RightMargin');
  close(a.marginTopInches, b.marginTopInches, 'TopMargin');
  close(a.marginBottomInches, b.marginBottomInches, 'BottomMargin');
  expect(b.hideText, a.hideText, reason: '$reason HideText');
  expect(b.backgroundColor, a.backgroundColor,
      reason: '$reason TextBkgnd');
  close(a.backgroundTransparency, b.backgroundTransparency,
      'TextBkgndTrans');
  expect(b.textDirection, a.textDirection, reason: '$reason TextDirection');
  close(a.defaultTabStopInches, b.defaultTabStopInches, 'DefaultTabStop');

  expect(after.runs, hasLength(before.runs.length),
      reason: '$reason text run count');
  for (var i = 0; i < before.runs.length; i++) {
    final ar = before.runs[i];
    final br = after.runs[i];
    expect(br.text, _normalizeText(ar.text), reason: '$reason run $i text');
    expect(br.fieldSpans, ar.fieldSpans,
        reason: '$reason run $i field spans');
    expect(br.tabIndices, ar.tabIndices,
        reason: '$reason run $i tab indices');

    final ac = ar.charStyle;
    final bc = br.charStyle;
    expect(bc.fontFamily, ac.fontFamily,
        reason: '$reason run $i font family');
    close(ac.fontSizeInches, bc.fontSizeInches, 'run $i font size');
    expect(bc.style.bold, ac.style.bold, reason: '$reason run $i bold');
    expect(bc.style.italic, ac.style.italic, reason: '$reason run $i italic');
    expect(bc.style.smallCaps, ac.style.smallCaps,
        reason: '$reason run $i small caps');
    expect(bc.color, ac.color, reason: '$reason run $i color');
    expect(bc.themeColorIndex, ac.themeColorIndex,
        reason: '$reason run $i theme color');
    expect(bc.underline, ac.underline,
        reason: '$reason run $i underline');
    expect(bc.strikethrough, ac.strikethrough,
        reason: '$reason run $i strikethrough');
    expect(bc.doubleUnderline, ac.doubleUnderline,
        reason: '$reason run $i double underline');
    expect(bc.doubleStrikethrough, ac.doubleStrikethrough,
        reason: '$reason run $i double strikethrough');
    expect(bc.overline, ac.overline, reason: '$reason run $i overline');
    close(ac.transparency, bc.transparency, 'run $i transparency');
    close(ac.letterSpacingInches, bc.letterSpacingInches,
        'run $i letter spacing');
    expect(bc.position, ac.position, reason: '$reason run $i position');
    expect(bc.textCase, ac.textCase, reason: '$reason run $i case');
    close(ac.fontScale, bc.fontScale, 'run $i font scale');
    expect(bc.asianFont, ac.asianFont,
        reason: '$reason run $i AsianFont');
    expect(bc.complexScriptFont, ac.complexScriptFont,
        reason: '$reason run $i ComplexScriptFont');
    expect(bc.langId, ac.langId, reason: '$reason run $i LangID');
    close(ac.complexScriptSizeInches, bc.complexScriptSizeInches,
        'run $i ComplexScriptSize');

    final ap = ar.paraStyle;
    final bp = br.paraStyle;
    expect(bp.horizontalAlign, ap.horizontalAlign,
        reason: '$reason run $i HorzAlign');
    close(ap.indentFirstInches, bp.indentFirstInches, 'run $i IndFirst');
    close(ap.indentLeftInches, bp.indentLeftInches, 'run $i IndLeft');
    close(ap.indentRightInches, bp.indentRightInches, 'run $i IndRight');
    close(ap.spaceBeforeInches, bp.spaceBeforeInches, 'run $i SpBefore');
    close(ap.spaceAfterInches, bp.spaceAfterInches, 'run $i SpAfter');
    close(ap.lineSpacing, bp.lineSpacing, 'run $i SpLine');
    close(ap.lineSpacingAbsoluteInches, bp.lineSpacingAbsoluteInches,
        'run $i absolute SpLine');
    expect(bp.lineSpacingSolid, ap.lineSpacingSolid,
        reason: '$reason run $i solid SpLine');
    expect(bp.bullet, ap.bullet, reason: '$reason run $i Bullet');
    expect(_nullIfEmpty(bp.bulletStr), _nullIfEmpty(ap.bulletStr),
        reason: '$reason run $i BulletStr');
    expect(_nullIfEmpty(bp.bulletFont), _nullIfEmpty(ap.bulletFont),
        reason: '$reason run $i BulletFont');
    close(ap.bulletFontSizeInches, bp.bulletFontSizeInches,
        'run $i BulletFontSize');
    close(ap.textPosAfterBulletInches, bp.textPosAfterBulletInches,
        'run $i TextPosAfterBullet');
    expect(bp.flags, ap.flags, reason: '$reason run $i Flags');
  }
}

String? _nullIfEmpty(String? value) =>
    value == null || value.isEmpty ? null : value;

double _roundHalfPoint(double value) => (value * 2).round() / 2;

String _normalizeText(String value) =>
    value.replaceAll('\u2028', '\n').replaceAll('\u2029', '\n');

String _unescapeXml(String value) => value
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

double _round6(double value) => (value * 1000000).round() / 1000000;
