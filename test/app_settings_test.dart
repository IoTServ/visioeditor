import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visioeditor/l10n/app_localizations.dart';
import 'package:visioeditor/settings/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('load defaults then persist theme, seed, and locale', () async {
    final s = await AppSettings.load();
    expect(s.themeMode, ThemeMode.system);
    expect(s.seedColorValue, AppSettings.defaultSeedColorValue);
    expect(s.locale, isNull);
    expect(s.localePreference, 'system');

    await s.setThemeMode(ThemeMode.dark);
    await s.setSeedColor(const Color(0xFFC62828));
    await s.setLocalePreference('zh');

    expect(s.themeMode, ThemeMode.dark);
    expect(s.seedColorValue, 0xFFC62828);
    expect(s.locale, const Locale('zh'));

    final again = await AppSettings.load();
    expect(again.themeMode, ThemeMode.dark);
    expect(again.seedColorValue, 0xFFC62828);
    expect(again.locale?.languageCode, 'zh');

    await again.resetToDefaults();
    expect(again.themeMode, ThemeMode.system);
    expect(again.seedColorValue, AppSettings.defaultSeedColorValue);
    expect(again.locale, isNull);
  });

  test('AppLocalizations tables cover en and zh', () {
    final en = AppLocalizations(const Locale('en'));
    final zh = AppLocalizations(const Locale('zh'));
    expect(en.settings, 'Settings');
    expect(zh.settings, '设置');
    expect(zh.themeModeDark, '深色');
  });

  testWidgets('AppLocalizations.of resolves via MaterialApp', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) {
            expect(AppLocalizations.of(context).settings, '设置');
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  });
}
