import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Lightweight app strings for Settings + shell chrome (en / zh).
///
/// Editor Format panels remain English for now; expand this table as needed.
class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  static AppLocalizations of(BuildContext context) {
    final result = Localizations.of<AppLocalizations>(context, AppLocalizations);
    assert(result != null, 'No AppLocalizations found in context');
    return result!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static final Map<String, Map<String, String>> _tables =
      <String, Map<String, String>>{
    'en': _en,
    'zh': _zh,
  };

  String _t(String key) {
    final lang = locale.languageCode;
    return _tables[lang]?[key] ?? _tables['en']![key] ?? key;
  }

  // --- Shell ---
  String get appTitle => _t('appTitle');
  String get settings => _t('settings');
  String get settingsTooltip => _t('settingsTooltip');
  String get more => _t('more');
  String get newDrawing => _t('newDrawing');
  String get openDrawing => _t('openDrawing');
  String get save => _t('save');
  String get recentFiles => _t('recentFiles');

  // --- Settings page ---
  String get appearance => _t('appearance');
  String get themeMode => _t('themeMode');
  String get themeModeSystem => _t('themeModeSystem');
  String get themeModeLight => _t('themeModeLight');
  String get themeModeDark => _t('themeModeDark');
  String get themeColor => _t('themeColor');
  String get themeColorHint => _t('themeColorHint');
  String get language => _t('language');
  String get languageSystem => _t('languageSystem');
  String get languageEnglish => _t('languageEnglish');
  String get languageChinese => _t('languageChinese');
  String get languageHint => _t('languageHint');
  String get resetDefaults => _t('resetDefaults');
  String get resetDefaultsHint => _t('resetDefaultsHint');
  String get about => _t('about');
  String get aboutBody => _t('aboutBody');

  static const Map<String, String> _en = <String, String>{
    'appTitle': 'Editor for Visio Diagrams',
    'settings': 'Settings',
    'settingsTooltip': 'Settings',
    'more': 'More',
    'newDrawing': 'New drawing (Cmd+N)',
    'openDrawing': 'Open a Visio drawing (Cmd+O)',
    'save': 'Save (Cmd+S)',
    'recentFiles': 'Recent files',
    'appearance': 'Appearance',
    'themeMode': 'Theme',
    'themeModeSystem': 'System',
    'themeModeLight': 'Light',
    'themeModeDark': 'Dark',
    'themeColor': 'Accent colour',
    'themeColorHint': 'Used for buttons, selection, and the app chrome.',
    'language': 'Language',
    'languageSystem': 'System',
    'languageEnglish': 'English',
    'languageChinese': '简体中文',
    'languageHint': 'Applies to Settings and main chrome labels.',
    'resetDefaults': 'Reset to defaults',
    'resetDefaultsHint': 'Restore system theme, default accent, and system language.',
    'about': 'About',
    'aboutBody':
        'A native cross-platform editor for Microsoft Visio (.vsdx) diagrams.',
  };

  static const Map<String, String> _zh = <String, String>{
    'appTitle': 'Visio 图表编辑器',
    'settings': '设置',
    'settingsTooltip': '设置',
    'more': '更多',
    'newDrawing': '新建绘图 (Cmd+N)',
    'openDrawing': '打开 Visio 绘图 (Cmd+O)',
    'save': '保存 (Cmd+S)',
    'recentFiles': '最近文件',
    'appearance': '外观',
    'themeMode': '主题',
    'themeModeSystem': '跟随系统',
    'themeModeLight': '浅色',
    'themeModeDark': '深色',
    'themeColor': '主题色',
    'themeColorHint': '用于按钮、选中态和应用顶栏等界面强调色。',
    'language': '语言',
    'languageSystem': '跟随系统',
    'languageEnglish': 'English',
    'languageChinese': '简体中文',
    'languageHint': '目前作用于设置页与主界面标题等文案。',
    'resetDefaults': '恢复默认设置',
    'resetDefaultsHint': '恢复系统主题、默认主题色与系统语言。',
    'about': '关于',
    'aboutBody': '面向 Microsoft Visio（.vsdx）的跨平台原生图表编辑器。',
  };
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'en' || locale.languageCode == 'zh';

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(AppLocalizations(locale));
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
