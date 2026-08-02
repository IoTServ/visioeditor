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

double _round6(double value) => (value * 1000000).round() / 1000000;
