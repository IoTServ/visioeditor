import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visioeditor/editor/page_canvas.dart';
import 'package:visioeditor/main.dart';
import 'package:visioeditor/settings/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pumpApp(WidgetTester tester) async {
    // Desktop-sized surface so the tool strip Column doesn't overflow.
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settings = await AppSettings.load();
    await tester.pumpWidget(VisioEditorApp(settings: settings));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the empty state with an open action', (tester) async {
    await pumpApp(tester);

    expect(find.text('Editor for Visio Diagrams'), findsWidgets);
    expect(find.text('Open Visio drawing'), findsOneWidget);
    expect(find.byIcon(Icons.folder_open_outlined), findsWidgets);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });

  testWidgets('settings page opens and switches dark mode + Chinese',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settings = await AppSettings.load();
    await tester.pumpWidget(VisioEditorApp(settings: settings));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);

    await tester.tap(find.byIcon(Icons.dark_mode_outlined));
    await tester.pumpAndSettle();
    expect(settings.themeMode, ThemeMode.dark);

    await tester.tap(find.text('简体中文'));
    await tester.pumpAndSettle();
    expect(settings.locale?.languageCode, 'zh');
    expect(find.text('设置'), findsWidgets);
  });

  testWidgets('double-click a shape edits its label in place and round-trips',
      (tester) async {
    await pumpApp(tester);

    // Start a blank drawing.
    await tester.tap(find.widgetWithText(FilledButton, 'New drawing'));
    await tester.pumpAndSettle();

    // The inline editor lives inside the canvas; scope finders to it so the
    // Arrange panel's numeric fields (also TextFields) don't interfere.
    final inlineEditor = find.descendant(
      of: find.byType(PageCanvas),
      matching: find.byType(TextField),
    );
    Finder inlineWithText(String t) => find.descendant(
          of: find.byType(PageCanvas),
          matching: find.widgetWithText(TextField, t),
        );

    // Draw a rectangle by picking the tool and clicking the canvas centre.
    await tester.tap(find.byIcon(Icons.crop_square));
    await tester.pumpAndSettle();
    await _tapCanvasAt(tester, _canvasCentre(tester));

    // No inline editor until we ask for one.
    expect(inlineEditor, findsNothing);

    // Double-click the shape → inline editor appears.
    await _doubleTapAt(tester, _canvasCentre(tester));
    expect(inlineEditor, findsOneWidget);

    // Type a label; clicking away on the empty canvas applies it.
    await tester.enterText(inlineEditor, 'Hello');
    await tester.pump();
    await _tapCanvasAt(
        tester, tester.getTopLeft(find.byType(PageCanvas)) + const Offset(6, 6));
    expect(inlineEditor, findsNothing);

    // Re-open: the editor is seeded from the model, proving the text was
    // written back through setShapeText.
    await _doubleTapAt(tester, _canvasCentre(tester));
    expect(inlineWithText('Hello'), findsOneWidget);

    // Escape cancels without applying the change.
    await tester.enterText(inlineEditor, 'Discarded');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(inlineEditor, findsNothing);

    await _doubleTapAt(tester, _canvasCentre(tester));
    expect(inlineWithText('Hello'), findsOneWidget);
    expect(inlineWithText('Discarded'), findsNothing);
  });

  testWidgets('right-click opens a context menu with edit actions',
      (tester) async {
    await pumpApp(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'New drawing'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.crop_square));
    await tester.pumpAndSettle();
    await _tapCanvasAt(tester, _canvasCentre(tester));

    // Right-click the shape → the context menu appears with selection actions.
    await tester.tapAt(_canvasCentre(tester), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Cut'), findsOneWidget);
    expect(find.text('Bring to Front'), findsOneWidget);
    expect(find.text('Copy Style'), findsOneWidget);

    // Selecting an item dismisses the menu.
    await tester.tap(find.text('Copy Style'));
    await tester.pumpAndSettle();
    expect(find.text('Cut'), findsNothing);

    // With a style on the clipboard, Paste Style is now offered.
    await tester.tapAt(_canvasCentre(tester), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Paste Style'), findsOneWidget);
  });
}

Offset _canvasCentre(WidgetTester tester) =>
    tester.getCenter(find.byType(PageCanvas));

/// A single tap on the canvas. The canvas [GestureDetector] also handles
/// double-taps, which defers `onTap` until the double-tap window closes; we
/// advance past it so the tap registers.
Future<void> _tapCanvasAt(WidgetTester tester, Offset pos) async {
  await tester.tapAt(pos);
  await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
  await tester.pumpAndSettle();
}

/// Emit two quick taps at [pos] within the double-tap window.
Future<void> _doubleTapAt(WidgetTester tester, Offset pos) async {
  await tester.tapAt(pos);
  await tester.pump(kDoubleTapMinTime);
  await tester.tapAt(pos);
  await tester.pumpAndSettle();
}
