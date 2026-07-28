import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ai/ai_engine.dart';

/// Persisted app preferences: locale, theme mode, and seed colour.
class AppSettings extends ChangeNotifier {
  AppSettings._({
    required this._themeMode,
    required this._seedColorValue,
    this._localeCode,
    required this._addIconLabel,
    required this._aiEngine,
  });

  static const String _kThemeMode = 'settings.theme_mode';
  static const String _kSeedColor = 'settings.seed_color';
  static const String _kLocale = 'settings.locale';
  static const String _kAddIconLabel = 'settings.add_icon_label';
  static const String _kAiProvider = 'settings.ai.provider';
  static const String _kAiEndpoint = 'settings.ai.endpoint';
  static const String _kAiModel = 'settings.ai.model';
  static const String _kAiApiKey = 'settings.ai.api_key';

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
  bool _addIconLabel;
  AiEngineConfig _aiEngine;

  ThemeMode get themeMode => _themeMode;
  Color get seedColor => Color(_seedColorValue);
  int get seedColorValue => _seedColorValue;

  /// When true, newly inserted third-party icons get a caption under the glyph.
  /// Defaults to false; remembered across sessions.
  bool get addIconLabel => _addIconLabel;
  AiEngineConfig get aiEngine => _aiEngine;

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
    // Default off — captions are optional; only true when the user opted in.
    final addIconLabel = prefs.getBool(_kAddIconLabel) ?? false;
    final providerName =
        prefs.getString(_kAiProvider) ?? AiProvider.openAiCompatible.name;
    final provider = AiProvider.values.firstWhere(
      (value) => value.name == providerName,
      orElse: () => AiProvider.openAiCompatible,
    );
    final defaults = AiEngineConfig.defaultsFor(provider);
    final aiEngine = defaults.copyWith(
      endpoint: prefs.getString(_kAiEndpoint) ?? defaults.endpoint,
      model: prefs.getString(_kAiModel) ?? defaults.model,
      apiKey: prefs.getString(_kAiApiKey) ?? '',
    );
    return AppSettings._(
      themeMode: mode,
      seedColorValue: seed,
      localeCode: localeCode,
      addIconLabel: addIconLabel,
      aiEngine: aiEngine,
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

  Future<void> setAddIconLabel(bool value) async {
    if (_addIconLabel == value) return;
    _addIconLabel = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAddIconLabel, value);
  }

  Future<void> setAiEngine(AiEngineConfig value) async {
    if (_aiEngine.provider == value.provider &&
        _aiEngine.endpoint == value.endpoint &&
        _aiEngine.model == value.model &&
        _aiEngine.apiKey == value.apiKey) {
      return;
    }
    _aiEngine = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await Future.wait(<Future<bool>>[
      prefs.setString(_kAiProvider, value.provider.name),
      prefs.setString(_kAiEndpoint, value.endpoint),
      prefs.setString(_kAiModel, value.model),
      prefs.setString(_kAiApiKey, value.apiKey),
    ]);
  }

  Future<void> resetToDefaults() async {
    _themeMode = ThemeMode.system;
    _seedColorValue = defaultSeedColorValue;
    _localeCode = null;
    _addIconLabel = false;
    _aiEngine = const AiEngineConfig();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeMode, ThemeMode.system.name);
    await prefs.setInt(_kSeedColor, defaultSeedColorValue);
    await prefs.setString(_kLocale, 'system');
    await prefs.setBool(_kAddIconLabel, false);
    await prefs.remove(_kAiProvider);
    await prefs.remove(_kAiEndpoint);
    await prefs.remove(_kAiModel);
    await prefs.remove(_kAiApiKey);
  }
}
