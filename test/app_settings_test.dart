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
    expect(s.addIconLabel, isFalse);

    await s.setThemeMode(ThemeMode.dark);
    await s.setSeedColor(const Color(0xFFC62828));
    await s.setLocalePreference('zh');
    await s.setAddIconLabel(true);

    expect(s.themeMode, ThemeMode.dark);
    expect(s.seedColorValue, 0xFFC62828);
    expect(s.locale, const Locale('zh'));
    expect(s.addIconLabel, isTrue);

    final again = await AppSettings.load();
    expect(again.themeMode, ThemeMode.dark);
    expect(again.seedColorValue, 0xFFC62828);
    expect(again.locale?.languageCode, 'zh');
    expect(again.addIconLabel, isTrue);

    await again.resetToDefaults();
    expect(again.themeMode, ThemeMode.system);
    expect(again.seedColorValue, AppSettings.defaultSeedColorValue);
    expect(again.locale, isNull);
    expect(again.addIconLabel, isFalse);
  });

  test('AppLocalizations tables cover all supported locales', () {
    expect(AppLocalizations(const Locale('en')).settings, 'Settings');
    expect(AppLocalizations(const Locale('zh')).settings, '设置');
    expect(AppLocalizations(const Locale('zh')).themeModeDark, '深色');
    expect(AppLocalizations(const Locale('ja')).settings, '設定');
    expect(AppLocalizations(const Locale('ko')).settings, '설정');
    expect(AppLocalizations(const Locale('es')).settings, 'Ajustes');
    expect(AppLocalizations(const Locale('fr')).settings, 'Paramètres');
    expect(AppLocalizations(const Locale('de')).settings, 'Einstellungen');
    expect(AppLocalizations(const Locale('pt')).settings, 'Definições');
    expect(AppLocalizations(const Locale('ru')).settings, 'Настройки');
    expect(AppLocalizations(const Locale('it')).settings, 'Impostazioni');
    expect(AppLocalizations(const Locale('ar')).settings, 'الإعدادات');
    expect(AppLocalizations(const Locale('id')).settings, 'Pengaturan');
    expect(AppLocalizations(const Locale('hi')).settings, 'सेटिंग्स');
    expect(AppLocalizations(const Locale('nl')).settings, 'Instellingen');
    expect(AppLocalizations(const Locale('tr')).settings, 'Ayarlar');
    expect(AppLocalizations(const Locale('pl')).settings, 'Ustawienia');
    expect(AppLocalizations(const Locale('vi')).settings, 'Cài đặt');
    expect(AppLocalizations(const Locale('th')).settings, 'การตั้งค่า');
    expect(AppLocalizations(const Locale('sv')).settings, 'Inställningar');
    expect(AppLocalizations(const Locale('uk')).settings, 'Параметри');
    expect(AppLocalizations(const Locale('he')).settings, 'הגדרות');
    expect(AppLocalizations(const Locale('cs')).settings, 'Nastavení');
    expect(AppLocalizations(const Locale('ro')).settings, 'Setări');
    expect(AppLocalizations(const Locale('el')).settings, 'Ρυθμίσεις');
    expect(AppLocalizations(const Locale('hu')).settings, 'Beállítások');
    expect(AppLocalizations(const Locale('da')).settings, 'Indstillinger');
    expect(AppLocalizations(const Locale('ms')).settings, 'Tetapan');
    expect(AppLocalizations(const Locale('fi')).settings, 'Asetukset');
    expect(AppLocalizations(const Locale('nb')).settings, 'Innstillinger');
    expect(AppLocalizations(const Locale('sk')).settings, 'Nastavenia');
    expect(AppLocalizations(const Locale('bn')).settings, 'সেটিংস');
    expect(AppLocalizations(const Locale('fa')).settings, 'تنظیمات');
    expect(AppLocalizations(const Locale('bg')).settings, 'Настройки');
    expect(AppLocalizations(const Locale('hr')).settings, 'Postavke');
    expect(AppLocalizations(const Locale('ca')).settings, 'Configuració');
    expect(AppLocalizations(const Locale('fil')).settings, 'Mga Setting');
    expect(AppLocalizations(const Locale('sw')).settings, 'Mipangilio');
    expect(AppLocalizations.supportedLocales, hasLength(37));
    expect(
      AppLocalizations.languagePreferenceCodes,
      hasLength(AppLocalizations.supportedLocales.length + 1),
    );
    expect(AppLocalizations.languagePreferenceCodes.first, 'system');
    final en = AppLocalizations(const Locale('en'));
    expect(en.labelForLanguagePreference('system'), 'System');
    expect(en.labelForLanguagePreference('zh'), '简体中文');
    expect(en.labelForLanguagePreference('sw'), 'Kiswahili');

    // Every locale must resolve languageSearchHint (no English-key fallback).
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = AppLocalizations(locale);
      expect(l10n.languageSearchHint, isNot('languageSearchHint'),
          reason: '${locale.languageCode} missing languageSearchHint');
      expect(l10n.languageSearchHint.trim(), isNotEmpty);
    }
    expect(en.languageSearchHint, 'Search languages');
    expect(AppLocalizations(const Locale('zh')).languageSearchHint, '搜索语言');
    expect(AppLocalizations(const Locale('ja')).languageSearchHint, '言語を検索');
    expect(AppLocalizations(const Locale('de')).languageSearchHint, 'Sprachen suchen');
    expect(AppLocalizations(const Locale('sw')).languageSearchHint, 'Tafuta lugha');
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
