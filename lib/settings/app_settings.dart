import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted app preferences: locale, theme mode, and seed colour.
class AppSettings extends ChangeNotifier {
  AppSettings._({
    required this._themeMode,
    required this._seedColorValue,
    this._localeCode,
  });

  static const String _kThemeMode = 'settings.theme_mode';
  static const String _kSeedColor = 'settings.seed_color';
  static const String _kLocale = 'settings.locale';

  static const int defaultSeedColorValue = 0xFF1F6FEB;

  /// Preset theme seed colours shown in Settings.
  static const List<int> seedPresets = <int>[
    0xFF1F6FEB, // GitHub blue (default)
    0xFF0B57D0, // Material blue
    0xFF006E1C, // green
    0xFF9C27B0, // purple
    0xFFC62828, // red
    0xFFEF6C00, // orange
    0xFF00838F, // teal
    0xFF5D4037, // brown
  ];

  ThemeMode _themeMode;
  int _seedColorValue;
  String? _localeCode; // null = follow system; else language code (en/zh/ja/…)

  ThemeMode get themeMode => _themeMode;
  Color get seedColor => Color(_seedColorValue);
  int get seedColorValue => _seedColorValue;

  /// Explicit app locale, or `null` to follow the OS.
  Locale? get locale {
    final code = _localeCode;
    if (code == null || code.isEmpty) return null;
    return Locale(code);
  }

  /// Preference key stored in prefs (`system` or a language code).
  String get localePreference => _localeCode ?? 'system';

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final modeName = prefs.getString(_kThemeMode) ?? ThemeMode.system.name;
    final mode = ThemeMode.values.firstWhere(
      (m) => m.name == modeName,
      orElse: () => ThemeMode.system,
    );
    final seed = prefs.getInt(_kSeedColor) ?? defaultSeedColorValue;
    final localeRaw = prefs.getString(_kLocale);
    final localeCode =
        (localeRaw == null || localeRaw.isEmpty || localeRaw == 'system')
            ? null
            : localeRaw;
    return AppSettings._(
      themeMode: mode,
      seedColorValue: seed,
      localeCode: localeCode,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeMode, mode.name);
  }

  Future<void> setSeedColor(Color color) async {
    final v = color.toARGB32();
    if (_seedColorValue == v) return;
    _seedColorValue = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSeedColor, v);
  }

  /// Pass `null` or `'system'` to follow the OS language.
  Future<void> setLocalePreference(String? code) async {
    final normalized =
        (code == null || code.isEmpty || code == 'system') ? null : code;
    if (_localeCode == normalized) return;
    _localeCode = normalized;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (normalized == null) {
      await prefs.setString(_kLocale, 'system');
    } else {
      await prefs.setString(_kLocale, normalized);
    }
  }

  Future<void> resetToDefaults() async {
    _themeMode = ThemeMode.system;
    _seedColorValue = defaultSeedColorValue;
    _localeCode = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeMode, ThemeMode.system.name);
    await prefs.setInt(_kSeedColor, defaultSeedColorValue);
    await prefs.setString(_kLocale, 'system');
  }
}
