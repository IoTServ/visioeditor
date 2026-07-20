import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visioeditor/main.dart';
import 'package:visioeditor/settings/app_settings.dart';

/// Fail the test if Flutter reports a layout overflow during [body].
Future<void> _withOverflowGuard(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  final overflows = <String>[];
  final old = FlutterError.onError;
  FlutterError.onError = (details) {
    final msg = details.exceptionAsString();
    if (msg.contains('OVERFLOWED') ||
        msg.contains('overflowed by') ||
        msg.contains('A RenderFlex overflowed')) {
      overflows.add(msg);
    }
    old?.call(details);
  };
  try {
    await body();
  } finally {
    FlutterError.onError = old;
  }
  expect(overflows, isEmpty, reason: overflows.join('\n---\n'));
}

Future<void> _setViewSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('home and editor layouts do not overflow at common sizes',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sizes = <Size>[
      const Size(1280, 800),
      const Size(1024, 700),
      const Size(900, 600),
      const Size(800, 500),
      const Size(1280, 480),
      const Size(480, 720),
      const Size(360, 640),
      const Size(390, 844),
      const Size(640, 360),
    ];

    for (final size in sizes) {
      await _withOverflowGuard(tester, () async {
        await _setViewSize(tester, size);
        final settings = await AppSettings.load();
        await tester.pumpWidget(VisioEditorApp(settings: settings));
        await tester.pumpAndSettle();

        expect(find.byType(MaterialApp), findsOneWidget);

        final newBtn = find.widgetWithText(FilledButton, 'New drawing');
        if (newBtn.evaluate().isNotEmpty) {
          await tester.tap(newBtn);
          await tester.pumpAndSettle();
        }

        // Settings is a direct AppBar action only on wide toolbars; on
        // narrow layouts it lives under the overflow "more" menu.
        final settingsIcon = find.byIcon(Icons.settings_outlined);
        if (settingsIcon.evaluate().isNotEmpty) {
          await tester.tap(settingsIcon);
          await tester.pumpAndSettle();
          final back = find.byType(BackButton);
          if (back.evaluate().isNotEmpty) {
            await tester.tap(back);
            await tester.pumpAndSettle();
          }
        }
      });
    }
  });

  testWidgets('compact phone editor keeps canvas usable and format sheet opens',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _withOverflowGuard(tester, () async {
      await _setViewSize(tester, const Size(360, 640));
      final settings = await AppSettings.load();
      await tester.pumpWidget(VisioEditorApp(settings: settings));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'New drawing'));
      await tester.pumpAndSettle();

      // Compact layout: format is a FAB, not a docked 232px panel.
      expect(find.byIcon(Icons.tune), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);

      // Canvas strip should be most of the width (tool strip ~56 only).
      final canvas = tester.getSize(find.byType(Scaffold).first);
      expect(canvas.width, greaterThanOrEqualTo(300));

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();
      expect(find.text('Diagram'), findsWidgets);

      // Dismiss sheet, then open shapes as an overlay (not a Row sibling).
      Navigator.of(tester.element(find.text('Diagram').first)).pop();
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.tune), findsOneWidget);

      await tester.tap(find.byIcon(Icons.category_outlined));
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });
  });

  testWidgets('Chinese settings theme chips do not overflow when narrow',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _withOverflowGuard(tester, () async {
      await _setViewSize(tester, const Size(360, 640));
      final settings = await AppSettings.load();
      await settings.setLocalePreference('zh');
      await tester.pumpWidget(VisioEditorApp(settings: settings));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      expect(find.byType(SegmentedButton<ThemeMode>), findsOneWidget);
    });
  });

  testWidgets('find and replace bar does not overflow on phone widths',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in const [Size(360, 640), Size(320, 568)]) {
      await _withOverflowGuard(tester, () async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await _setViewSize(tester, size);
        final settings = await AppSettings.load();
        await tester.pumpWidget(VisioEditorApp(settings: settings));
        await tester.pumpAndSettle();

        final newBtn = find.widgetWithText(FilledButton, 'New drawing');
        expect(newBtn, findsOneWidget);
        await tester.ensureVisible(newBtn);
        await tester.tap(newBtn);
        await tester.pumpAndSettle();

        await tester.tap(find.byType(PopupMenuButton<String>).first);
        await tester.pumpAndSettle();
        // Prefer replace mode so both find rows are exercised.
        final replaceMenu = find.text('Find and Replace… (Cmd+H)');
        await tester.ensureVisible(replaceMenu);
        await tester.tap(replaceMenu);
        await tester.pumpAndSettle();
        expect(find.text('Find shapes…'), findsOneWidget);
      });
    }
  });

  testWidgets('German paper orientation chips fit in format sheet',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _withOverflowGuard(tester, () async {
      await _setViewSize(tester, const Size(360, 640));
      final settings = await AppSettings.load();
      await settings.setLocalePreference('de');
      await tester.pumpWidget(VisioEditorApp(settings: settings));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Neue Zeichnung'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();

      // Paper orientation sits lower in the Diagram ListView — scroll to it.
      await tester.drag(find.byType(ListView).last, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.byType(SegmentedButton<bool>), findsOneWidget);
      expect(find.byIcon(Icons.stay_current_portrait), findsOneWidget);
      expect(find.byIcon(Icons.stay_current_landscape), findsOneWidget);
    });
  });

  testWidgets('layers panel long German label does not overflow', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _withOverflowGuard(tester, () async {
      await _setViewSize(tester, const Size(360, 640));
      final settings = await AppSettings.load();
      await settings.setLocalePreference('de');
      await tester.pumpWidget(VisioEditorApp(settings: settings));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Neue Zeichnung'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ebenen'));
      await tester.pumpAndSettle();
      expect(find.byType(OutlinedButton), findsWidgets);
    });
  });

  testWidgets('narrow page tab bar folds actions into a menu', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _withOverflowGuard(tester, () async {
      await _setViewSize(tester, const Size(360, 640));
      final settings = await AppSettings.load();
      await tester.pumpWidget(VisioEditorApp(settings: settings));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'New drawing'));
      await tester.pumpAndSettle();

      // Compact page chrome: no dedicated add/delete icons beside the chips.
      expect(find.byIcon(Icons.add), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.byType(PopupMenuButton<String>), findsWidgets);
    });
  });
}
