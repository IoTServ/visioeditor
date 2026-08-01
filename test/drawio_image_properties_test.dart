import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:visioeditor/editor/page_canvas.dart';
import 'package:visioeditor/main.dart';
import 'package:visioeditor/settings/app_settings.dart';
import 'package:vsdx/vsdx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  EditorController controller() {
    final value = EditorController()..newDocument();
    addTearDown(value.dispose);
    return value;
  }

  int picture(EditorController value) {
    value.insertImage(
      Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47]),
      fileExtension: 'png',
      widthInches: 4,
      heightInches: 2,
    );
    return value.singleSelectedId!;
  }

  test('picture adjustments preview as one undo step and reset neutrally', () {
    final value = controller();
    final id = picture(value);

    value.beginTransaction();
    value.updateSelectedImage(opacity: 0.7, transient: true);
    value.updateSelectedImage(
      blur: 0.25,
      brightness: 0.8,
      contrast: 0.2,
      transient: true,
    );
    value.commitTransaction();

    var image = value.currentPage!.findShapeById(id)!;
    expect(image.imageTransparency, closeTo(0.3, 1e-9));
    expect(image.imageBlur, closeTo(0.25, 1e-9));
    expect(image.imageBrightness, closeTo(0.8, 1e-9));
    expect(image.imageContrast, closeTo(0.2, 1e-9));

    value.undo();
    image = value.currentPage!.findShapeById(id)!;
    expect(image.imageTransparency, 0);
    expect(image.imageBlur, 0);
    expect(image.imageBrightness, 0.5);
    expect(image.imageContrast, 0.5);

    value.redo();
    value.resetSelectedImageAdjustments();
    image = value.currentPage!.findShapeById(id)!;
    expect(image.imageTransparency, 0);
    expect(image.imageBlur, 0);
    expect(image.imageBrightness, 0.5);
    expect(image.imageContrast, 0.5);
  });

  test('crop zoom and pan cover the frame, scrub formulas, and undo', () {
    final value = controller();
    final id = picture(value);
    value.updateCurrentPage(
      (page) => page.updateShapeById(
        id,
        (shape) => shape.copyWith(
          formulas: <String, String>{
            ...shape.formulas,
            'ImgOffsetX': 'Width*0.1',
            'ImgOffsetY': 'Height*0.1',
            'ImgWidth': 'Width*1.2',
            'ImgHeight': 'Height*1.2',
          },
        ),
      ),
    );

    value.setSelectedImageCropZoom(2);
    var image = value.currentPage!.findShapeById(id)!;
    expect(image.effectiveImgWidth, closeTo(8, 1e-9));
    expect(image.effectiveImgHeight, closeTo(4, 1e-9));
    expect(image.imgOffsetXInches, closeTo(-2, 1e-9));
    expect(image.imgOffsetYInches, closeTo(-1, 1e-9));
    expect(
      image.formulas.keys,
      isNot(
        contains(anyOf('ImgOffsetX', 'ImgOffsetY', 'ImgWidth', 'ImgHeight')),
      ),
    );

    value.setSelectedImageCropPan(x: 1, y: -1);
    image = value.currentPage!.findShapeById(id)!;
    expect(image.imgOffsetXInches, closeTo(-4, 1e-9));
    expect(image.imgOffsetYInches, closeTo(0, 1e-9));
    expect(value.selectedImageCropPanX, closeTo(1, 1e-9));
    expect(value.selectedImageCropPanY, closeTo(-1, 1e-9));

    value.resetSelectedImageCrop();
    image = value.currentPage!.findShapeById(id)!;
    expect(image.effectiveImgWidth, closeTo(image.width, 1e-9));
    expect(image.effectiveImgHeight, closeTo(image.height, 1e-9));
    expect(image.imgOffsetXInches, 0);
    expect(image.imgOffsetYInches, 0);
    value.undo();
    expect(value.currentPage!.findShapeById(id)!.imgOffsetXInches, -4);

    value.updateCurrentPage(
      (page) => page.updateShapeById(
        id,
        (shape) => shape.copyWith(
          imgWidthInches: shape.width * 10,
          imgHeightInches: shape.height * 10,
        ),
      ),
    );
    expect(value.selectedImageCropZoom, 4); // inspector maximum
    value.setSelectedImageCropPan(x: 1);
    expect(
      value.currentPage!.findShapeById(id)!.effectiveImgWidth,
      image.width * 10,
    );
    value.resetSelectedImageCrop();
    image = value.currentPage!.findShapeById(id)!;
    expect(image.effectiveImgWidth, image.width);
    expect(image.effectiveImgHeight, image.height);
  });

  test('crop and picture adjustments survive VSDX save and reopen', () {
    final value = controller();
    final id = picture(value);
    value
      ..setSelectedImageCropZoom(1.75)
      ..setSelectedImageCropPan(x: 0.4, y: -0.2)
      ..updateSelectedImage(
        opacity: 0.65,
        blur: 0.15,
        brightness: 0.7,
        contrast: 0.35,
      );

    final reopened = const DocumentParser()
        .parse(value.exportToBytes())
        .pages
        .single
        .findShapeById(id)!;
    expect(reopened.effectiveImgWidth, closeTo(7, 1e-6));
    expect(reopened.effectiveImgHeight, closeTo(3.5, 1e-6));
    expect(reopened.imgOffsetXInches, closeTo(-2.1, 1e-6));
    expect(reopened.imgOffsetYInches, closeTo(-0.6, 1e-6));
    expect(reopened.imageTransparency, closeTo(0.35, 1e-6));
    expect(reopened.imageBlur, closeTo(0.15, 1e-6));
    expect(reopened.imageBrightness, closeTo(0.7, 1e-6));
    expect(reopened.imageContrast, closeTo(0.35, 1e-6));
  });

  test('locked pictures reject crop and adjustment commands', () {
    final value = controller();
    final id = picture(value);
    value.setSelectionLocked(true);
    final before = value.currentPage!.findShapeById(id)!;

    value
      ..setSelectedImageCropZoom(2)
      ..setSelectedImageCropPan(x: 1)
      ..updateSelectedImage(opacity: 0.2, blur: 0.8)
      ..resetSelectedImageCrop()
      ..resetSelectedImageAdjustments();

    final after = value.currentPage!.findShapeById(id)!;
    expect(after.imgWidthInches, before.imgWidthInches);
    expect(after.imgOffsetXInches, before.imgOffsetXInches);
    expect(after.imageTransparency, before.imageTransparency);
    expect(after.imageBlur, before.imageBlur);
  });

  testWidgets('Format exposes draw.io crop and image adjustment controls', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settings = await AppSettings.load();
    await tester.pumpWidget(VisioEditorApp(settings: settings));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'New drawing'));
    await tester.pumpAndSettle();

    final canvas = tester.widget<PageCanvas>(find.byType(PageCanvas));
    picture(canvas.controller);
    canvas.controller
      ..setSelectedImageCropZoom(2)
      ..updateSelectedImage(brightness: 0.75, contrast: 0.25);
    await tester.pumpAndSettle();
    expect(canvas.controller.canReplaceSelectedImage, isTrue);

    final scrollable = find.ancestor(
      of: find.text('Arrange'),
      matching: find.byWidgetPredicate((widget) => widget is Scrollable),
    );
    final state = tester.state<ScrollableState>(scrollable);
    Future<void> scrollTo(String label) async {
      for (var i = 0; i < 30 && find.text(label).evaluate().isEmpty; i++) {
        state.position.jumpTo(
          (state.position.pixels + 260).clamp(
            0,
            state.position.maxScrollExtent,
          ),
        );
        await tester.pumpAndSettle();
      }
      expect(find.text(label), findsOneWidget);
    }

    await scrollTo('Replace Image…');
    await scrollTo('Crop');
    expect(find.text('Zoom'), findsOneWidget);
    await scrollTo('Reset Crop');
    await tester.ensureVisible(find.text('Reset Crop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset Crop'));
    await tester.pumpAndSettle();
    expect(canvas.controller.selectedImageCropZoom, 1);
    await scrollTo('Brightness');
    expect(find.text('Contrast'), findsOneWidget);
    await scrollTo('Reset Image Adjustments');
    await tester.ensureVisible(find.text('Reset Image Adjustments'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset Image Adjustments'));
    await tester.pumpAndSettle();
    expect(canvas.controller.selectedImageBrightness, 0.5);
    expect(canvas.controller.selectedImageContrast, 0.5);
  });
}
