import 'dart:io';

import 'package:test/test.dart';
import 'package:vsdx/vsdx.dart';

import '../support/libvisio_oracle.dart';

void main() {
  final oracle = LibvisioOracle.tryLoad();
  final skipReason = oracle == null
      ? 'libvisio shim not built — run packages/vsdx/native/build.sh'
      : null;

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
      expect(reopened.pages, hasLength(doc.pages.length));
      for (var pageIndex = 0; pageIndex < doc.pages.length; pageIndex++) {
        final beforePage = doc.pages[pageIndex];
        final afterPage = reopened.pages[pageIndex];
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
  expect(after.fields, before.fields, reason: '$reason dynamic fields');
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
  expect(after.line.pattern, before.line.pattern,
      reason: '$reason line pattern');
  expect(after.line.color, before.line.color, reason: '$reason line color');
  close(before.line.weightInches, after.line.weightInches, 'LineWeight');
  close(before.line.transparency, after.line.transparency, 'LineColorTrans');
  expect(after.line.beginArrow, before.line.beginArrow,
      reason: '$reason begin arrow');
  expect(after.line.endArrow, before.line.endArrow,
      reason: '$reason end arrow');
  expect(after.geometries.length, before.geometries.length,
      reason: '$reason geometry sections');
  for (var i = 0; i < before.geometries.length; i++) {
    final a = before.geometries[i];
    final b = after.geometries[i];
    expect(b.ix, a.ix, reason: '$reason Geometry[$i] IX');
    expect(b.noFill, a.noFill, reason: '$reason Geometry[$i] NoFill');
    expect(b.noLine, a.noLine, reason: '$reason Geometry[$i] NoLine');
    expect(b.noShow, a.noShow, reason: '$reason Geometry[$i] NoShow');
    expect(b.commands.map((c) => c.runtimeType),
        a.commands.map((c) => c.runtimeType),
        reason: '$reason Geometry[$i] command topology');
  }
}

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
