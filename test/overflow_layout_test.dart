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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('home and editor layouts do not overflow at common sizes',
      (tester) async {
    final sizes = <Size>[
      const Size(1280, 800),
      const Size(1024, 700),
      const Size(900, 600),
      const Size(800, 500),
      const Size(1280, 480),
      const Size(480, 720),
      const Size(360, 640),
    ];

    for (final size in sizes) {
      await _withOverflowGuard(tester, () async {
        await tester.binding.setSurfaceSize(size);
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
    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Chinese settings theme chips do not overflow when narrow',
      (tester) async {
    await _withOverflowGuard(tester, () async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final settings = await AppSettings.load();
      await settings.setLocalePreference('zh');
      await tester.pumpWidget(VisioEditorApp(settings: settings));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      expect(find.byType(SegmentedButton<ThemeMode>), findsOneWidget);
    });
  });
}
