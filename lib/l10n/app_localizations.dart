import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Lightweight app strings for Settings + shell chrome.
///
/// Supported: en, zh, ja, ko, es, fr, de, pt, ru, it, ar, id, hi, nl, tr, pl,
/// vi, th, sv, uk, he, cs, ro, el, hu, da, ms, fi, nb, sk, bn, fa, bg, hr, ca,
/// fil, sw.
/// Editor UI strings live in editor_l10n.dart / editor_l10n_maps.dart.
class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
    Locale('ja'),
    Locale('ko'),
    Locale('es'),
    Locale('fr'),
    Locale('de'),
    Locale('pt'),
    Locale('ru'),
    Locale('it'),
    Locale('ar'),
    Locale('id'),
    Locale('hi'),
    Locale('nl'),
    Locale('tr'),
    Locale('pl'),
    Locale('vi'),
    Locale('th'),
    Locale('sv'),
    Locale('uk'),
    Locale('he'),
    Locale('cs'),
    Locale('ro'),
    Locale('el'),
    Locale('hu'),
    Locale('da'),
    Locale('ms'),
    Locale('fi'),
    Locale('nb'),
    Locale('sk'),
    Locale('bn'),
    Locale('fa'),
    Locale('bg'),
    Locale('hr'),
    Locale('ca'),
    Locale('fil'),
    Locale('sw'),
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
    'ja': _ja,
    'ko': _ko,
    'es': _es,
    'fr': _fr,
    'de': _de,
    'pt': _pt,
    'ru': _ru,
    'it': _it,
    'ar': _ar,
    'id': _id,
    'hi': _hi,
    'nl': _nl,
    'tr': _tr,
    'pl': _pl,
    'vi': _vi,
    'th': _th,
    'sv': _sv,
    'uk': _uk,
    'he': _he,
    'cs': _cs,
    'ro': _ro,
    'el': _el,
    'hu': _hu,
    'da': _da,
    'ms': _ms,
    'fi': _fi,
    'nb': _nb,
    'sk': _sk,
    'bn': _bn,
    'fa': _fa,
    'bg': _bg,
    'hr': _hr,
    'ca': _ca,
    'fil': _fil,
    'sw': _sw,
  };

  String _t(String key) {
    final lang = locale.languageCode;
    return _tables[lang]?[key] ?? _tables['en']![key] ?? key;
  }

  // --- Shell ---
  /// Windows Store product name is "Flowcharts Editor"; Android launcher
  /// name is "Visio Vsdx Editor"; other platforms keep the cross-platform
  /// "Editor for Visio Diagrams" brand.
  String get appTitle {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      return 'Flowcharts Editor';
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'Visio Vsdx Editor';
    }
    return _t('appTitle');
  }
  String get settings => _t('settings');
  String get settingsTooltip => _t('settingsTooltip');
  String get more => _t('more');
  String get newDrawing => _t('newDrawing');
  String get newFromTemplate => _t('newFromTemplate');
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
  String get languageJapanese => _t('languageJapanese');
  String get languageKorean => _t('languageKorean');
  String get languageSpanish => _t('languageSpanish');
  String get languageFrench => _t('languageFrench');
  String get languageGerman => _t('languageGerman');
  String get languagePortuguese => _t('languagePortuguese');
  String get languageRussian => _t('languageRussian');
  String get languageItalian => _t('languageItalian');
  String get languageArabic => _t('languageArabic');
  String get languageIndonesian => _t('languageIndonesian');
  String get languageHindi => _t('languageHindi');
  String get languageDutch => _t('languageDutch');
  String get languageTurkish => _t('languageTurkish');
  String get languagePolish => _t('languagePolish');
  String get languageVietnamese => _t('languageVietnamese');
  String get languageThai => _t('languageThai');
  String get languageSwedish => _t('languageSwedish');
  String get languageUkrainian => _t('languageUkrainian');
  String get languageHebrew => _t('languageHebrew');
  String get languageCzech => _t('languageCzech');
  String get languageRomanian => _t('languageRomanian');
  String get languageGreek => _t('languageGreek');
  String get languageHungarian => _t('languageHungarian');
  String get languageDanish => _t('languageDanish');
  String get languageMalay => _t('languageMalay');
  String get languageFinnish => _t('languageFinnish');
  String get languageNorwegian => _t('languageNorwegian');
  String get languageSlovak => _t('languageSlovak');
  String get languageBengali => _t('languageBengali');
  String get languagePersian => _t('languagePersian');
  String get languageBulgarian => _t('languageBulgarian');
  String get languageCroatian => _t('languageCroatian');
  String get languageCatalan => _t('languageCatalan');
  String get languageFilipino => _t('languageFilipino');
  String get languageSwahili => _t('languageSwahili');
  String get languageHint => _t('languageHint');
  String get languageSearchHint => _t('languageSearchHint');
  String get resetDefaults => _t('resetDefaults');
  String get resetDefaultsHint => _t('resetDefaultsHint');
  String get about => _t('about');
  String get aboutBody => _t('aboutBody');

  /// Preference codes for the language picker (`system` first).
  static List<String> get languagePreferenceCodes => <String>[
        'system',
        for (final locale in supportedLocales) locale.languageCode,
      ];

  /// Native / localized label for a settings language preference code.
  String labelForLanguagePreference(String code) {
    if (code == 'system' || code.isEmpty) return languageSystem;
    final key = _codeToLanguageNameKey[code];
    if (key == null) return code;
    return _languageNames[key] ?? code;
  }

  static const Map<String, String> _codeToLanguageNameKey = <String, String>{
    'en': 'languageEnglish',
    'zh': 'languageChinese',
    'ja': 'languageJapanese',
    'ko': 'languageKorean',
    'es': 'languageSpanish',
    'fr': 'languageFrench',
    'de': 'languageGerman',
    'pt': 'languagePortuguese',
    'ru': 'languageRussian',
    'it': 'languageItalian',
    'ar': 'languageArabic',
    'id': 'languageIndonesian',
    'hi': 'languageHindi',
    'nl': 'languageDutch',
    'tr': 'languageTurkish',
    'pl': 'languagePolish',
    'vi': 'languageVietnamese',
    'th': 'languageThai',
    'sv': 'languageSwedish',
    'uk': 'languageUkrainian',
    'he': 'languageHebrew',
    'cs': 'languageCzech',
    'ro': 'languageRomanian',
    'el': 'languageGreek',
    'hu': 'languageHungarian',
    'da': 'languageDanish',
    'ms': 'languageMalay',
    'fi': 'languageFinnish',
    'nb': 'languageNorwegian',
    'sk': 'languageSlovak',
    'bn': 'languageBengali',
    'fa': 'languagePersian',
    'bg': 'languageBulgarian',
    'hr': 'languageCroatian',
    'ca': 'languageCatalan',
    'fil': 'languageFilipino',
    'sw': 'languageSwahili',
  };

  /// Native display names shared across all locale tables.
  static const Map<String, String> _languageNames = <String, String>{
    'languageEnglish': 'English',
    'languageChinese': '简体中文',
    'languageJapanese': '日本語',
    'languageKorean': '한국어',
    'languageSpanish': 'Español',
    'languageFrench': 'Français',
    'languageGerman': 'Deutsch',
    'languagePortuguese': 'Português',
    'languageRussian': 'Русский',
    'languageItalian': 'Italiano',
    'languageArabic': 'العربية',
    'languageIndonesian': 'Bahasa Indonesia',
    'languageHindi': 'हिन्दी',
    'languageDutch': 'Nederlands',
    'languageTurkish': 'Türkçe',
    'languagePolish': 'Polski',
    'languageVietnamese': 'Tiếng Việt',
    'languageThai': 'ไทย',
    'languageSwedish': 'Svenska',
    'languageUkrainian': 'Українська',
    'languageHebrew': 'עברית',
    'languageCzech': 'Čeština',
    'languageRomanian': 'Română',
    'languageGreek': 'Ελληνικά',
    'languageHungarian': 'Magyar',
    'languageDanish': 'Dansk',
    'languageMalay': 'Bahasa Melayu',
    'languageFinnish': 'Suomi',
    'languageNorwegian': 'Norsk',
    'languageSlovak': 'Slovenčina',
    'languageBengali': 'বাংলা',
    'languagePersian': 'فارسی',
    'languageBulgarian': 'Български',
    'languageCroatian': 'Hrvatski',
    'languageCatalan': 'Català',
    'languageFilipino': 'Filipino',
    'languageSwahili': 'Kiswahili',
  };

  static const Map<String, String> _en = <String, String>{
    'appTitle': 'Editor for Visio Diagrams',
    'settings': 'Settings',
    'settingsTooltip': 'Settings',
    'more': 'More',
    'newDrawing': 'New drawing (Cmd+N)',
    'newFromTemplate': 'New from template',
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
    ..._languageNames,
    'languageHint': 'Applies to Settings and main chrome labels.',
    'languageSearchHint': 'Search languages',
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
    'newFromTemplate': '从模板新建',
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
    ..._languageNames,
    'languageHint': '目前作用于设置页与主界面标题等文案。',
    'languageSearchHint': '搜索语言',
    'resetDefaults': '恢复默认设置',
    'resetDefaultsHint': '恢复系统主题、默认主题色与系统语言。',
    'about': '关于',
    'aboutBody': '面向 Microsoft Visio（.vsdx）的跨平台原生图表编辑器。',
  };

  static const Map<String, String> _ja = <String, String>{
    'appTitle': 'Visio 図面エディター',
    'settings': '設定',
    'settingsTooltip': '設定',
    'more': 'その他',
    'newDrawing': '新規図面 (Cmd+N)',
    'newFromTemplate': 'テンプレートから新規',
    'openDrawing': 'Visio 図面を開く (Cmd+O)',
    'save': '保存 (Cmd+S)',
    'recentFiles': '最近使用したファイル',
    'appearance': '外観',
    'themeMode': 'テーマ',
    'themeModeSystem': 'システム',
    'themeModeLight': 'ライト',
    'themeModeDark': 'ダーク',
    'themeColor': 'アクセントカラー',
    'themeColorHint': 'ボタン、選択状態、アプリの枠組みなどに使用されます。',
    'language': '言語',
    'languageSystem': 'システム',
    ..._languageNames,
    'languageHint': '設定画面とメインの枠組みラベルに適用されます。',
    'languageSearchHint': '言語を検索',
    'resetDefaults': 'デフォルトに戻す',
    'resetDefaultsHint': 'システムテーマ、既定のアクセント、システム言語に戻します。',
    'about': 'このアプリについて',
    'aboutBody':
        'Microsoft Visio（.vsdx）図面向けのネイティブなクロスプラットフォーム エディターです。',
  };

  static const Map<String, String> _ko = <String, String>{
    'appTitle': 'Visio 다이어그램 편집기',
    'settings': '설정',
    'settingsTooltip': '설정',
    'more': '더보기',
    'newDrawing': '새 도면 (Cmd+N)',
    'newFromTemplate': '템플릿에서 새로 만들기',
    'openDrawing': 'Visio 도면 열기 (Cmd+O)',
    'save': '저장 (Cmd+S)',
    'recentFiles': '최근 파일',
    'appearance': '모양',
    'themeMode': '테마',
    'themeModeSystem': '시스템',
    'themeModeLight': '라이트',
    'themeModeDark': '다크',
    'themeColor': '강조 색상',
    'themeColorHint': '버튼, 선택 상태, 앱 크롬에 사용됩니다.',
    'language': '언어',
    'languageSystem': '시스템',
    ..._languageNames,
    'languageHint': '설정 및 메인 크롬 레이블에 적용됩니다.',
    'languageSearchHint': '언어 검색',
    'resetDefaults': '기본값으로 재설정',
    'resetDefaultsHint': '시스템 테마, 기본 강조 색상, 시스템 언어로 복원합니다.',
    'about': '정보',
    'aboutBody':
        'Microsoft Visio(.vsdx) 다이어그램용 네이티브 크로스 플랫폼 편집기입니다.',
  };

  static const Map<String, String> _es = <String, String>{
    'appTitle': 'Editor de diagramas Visio',
    'settings': 'Ajustes',
    'settingsTooltip': 'Ajustes',
    'more': 'Más',
    'newDrawing': 'Nuevo dibujo (Cmd+N)',
    'newFromTemplate': 'New from template',
    'openDrawing': 'Abrir un dibujo de Visio (Cmd+O)',
    'save': 'Guardar (Cmd+S)',
    'recentFiles': 'Archivos recientes',
    'appearance': 'Apariencia',
    'themeMode': 'Tema',
    'themeModeSystem': 'Sistema',
    'themeModeLight': 'Claro',
    'themeModeDark': 'Oscuro',
    'themeColor': 'Color de acento',
    'themeColorHint': 'Se usa en botones, selección y la interfaz principal.',
    'language': 'Idioma',
    'languageSystem': 'Sistema',
    ..._languageNames,
    'languageHint': 'Se aplica a Ajustes y a las etiquetas de la interfaz principal.',
    'languageSearchHint': 'Buscar idiomas',
    'resetDefaults': 'Restablecer valores predeterminados',
    'resetDefaultsHint':
        'Restaura el tema del sistema, el color de acento predeterminado y el idioma del sistema.',
    'about': 'Acerca de',
    'aboutBody':
        'Un editor nativo multiplataforma para diagramas de Microsoft Visio (.vsdx).',
  };

  static const Map<String, String> _fr = <String, String>{
    'appTitle': 'Éditeur de diagrammes Visio',
    'settings': 'Paramètres',
    'settingsTooltip': 'Paramètres',
    'more': 'Plus',
    'newDrawing': 'Nouveau dessin (Cmd+N)',
    'newFromTemplate': 'New from template',
    'openDrawing': 'Ouvrir un dessin Visio (Cmd+O)',
    'save': 'Enregistrer (Cmd+S)',
    'recentFiles': 'Fichiers récents',
    'appearance': 'Apparence',
    'themeMode': 'Thème',
    'themeModeSystem': 'Système',
    'themeModeLight': 'Clair',
    'themeModeDark': 'Sombre',
    'themeColor': 'Couleur d’accentuation',
    'themeColorHint':
        'Utilisée pour les boutons, la sélection et l’interface de l’application.',
    'language': 'Langue',
    'languageSystem': 'Système',
    ..._languageNames,
    'languageHint':
        'S’applique aux Paramètres et aux libellés de l’interface principale.',
    'languageSearchHint': 'Rechercher des langues',
    'resetDefaults': 'Réinitialiser les valeurs par défaut',
    'resetDefaultsHint':
        'Restaure le thème système, la couleur d’accentuation par défaut et la langue système.',
    'about': 'À propos',
    'aboutBody':
        'Un éditeur natif multiplateforme pour les diagrammes Microsoft Visio (.vsdx).',
  };

  static const Map<String, String> _de = <String, String>{
    'appTitle': 'Editor für Visio-Diagramme',
    'settings': 'Einstellungen',
    'settingsTooltip': 'Einstellungen',
    'more': 'Mehr',
    'newDrawing': 'Neue Zeichnung (Cmd+N)',
    'newFromTemplate': 'New from template',
    'openDrawing': 'Visio-Zeichnung öffnen (Cmd+O)',
    'save': 'Speichern (Cmd+S)',
    'recentFiles': 'Zuletzt verwendete Dateien',
    'appearance': 'Darstellung',
    'themeMode': 'Design',
    'themeModeSystem': 'System',
    'themeModeLight': 'Hell',
    'themeModeDark': 'Dunkel',
    'themeColor': 'Akzentfarbe',
    'themeColorHint':
        'Wird für Schaltflächen, Auswahl und die App-Oberfläche verwendet.',
    'language': 'Sprache',
    'languageSystem': 'System',
    ..._languageNames,
    'languageHint':
        'Gilt für Einstellungen und Beschriftungen der Hauptoberfläche.',
    'languageSearchHint': 'Sprachen suchen',
    'resetDefaults': 'Auf Standard zurücksetzen',
    'resetDefaultsHint':
        'Stellt Systemdesign, Standard-Akzentfarbe und Systemsprache wieder her.',
    'about': 'Info',
    'aboutBody':
        'Ein nativer plattformübergreifender Editor für Microsoft Visio (.vsdx)-Diagramme.',
  };

  static const Map<String, String> _pt = <String, String>{
    'appTitle': 'Editor de diagramas Visio',
    'settings': 'Definições',
    'settingsTooltip': 'Definições',
    'more': 'Mais',
    'newDrawing': 'Novo desenho (Cmd+N)',
    'newFromTemplate': 'New from template',
    'openDrawing': 'Abrir um desenho Visio (Cmd+O)',
    'save': 'Guardar (Cmd+S)',
    'recentFiles': 'Ficheiros recentes',
    'appearance': 'Aspeto',
    'themeMode': 'Tema',
    'themeModeSystem': 'Sistema',
    'themeModeLight': 'Claro',
    'themeModeDark': 'Escuro',
    'themeColor': 'Cor de destaque',
    'themeColorHint':
        'Usada em botões, seleção e na interface principal da aplicação.',
    'language': 'Idioma',
    'languageSystem': 'Sistema',
    ..._languageNames,
    'languageHint':
        'Aplica-se às Definições e aos rótulos da interface principal.',
    'languageSearchHint': 'Pesquisar idiomas',
    'resetDefaults': 'Repor predefinições',
    'resetDefaultsHint':
        'Restaura o tema do sistema, a cor de destaque predefinida e o idioma do sistema.',
    'about': 'Acerca de',
    'aboutBody':
        'Um editor nativo multiplataforma para diagramas Microsoft Visio (.vsdx).',
  };

  static const Map<String, String> _ru = <String, String>{
    'appTitle': 'Редактор диаграмм Visio',
    'settings': 'Настройки',
    'settingsTooltip': 'Настройки',
    'more': 'Ещё',
    'newDrawing': 'Новый чертёж (Cmd+N)',
    'newFromTemplate': 'New from template',
    'openDrawing': 'Открыть чертёж Visio (Cmd+O)',
    'save': 'Сохранить (Cmd+S)',
    'recentFiles': 'Недавние файлы',
    'appearance': 'Оформление',
    'themeMode': 'Тема',
    'themeModeSystem': 'Системная',
    'themeModeLight': 'Светлая',
    'themeModeDark': 'Тёмная',
    'themeColor': 'Цвет акцента',
    'themeColorHint':
        'Используется для кнопок, выделения и оформления приложения.',
    'language': 'Язык',
    'languageSystem': 'Системный',
    ..._languageNames,
    'languageHint':
        'Применяется к настройкам и подписям основного интерфейса.',
    'languageSearchHint': 'Поиск языков',
    'resetDefaults': 'Сбросить настройки',
    'resetDefaultsHint':
        'Восстанавливает системную тему, цвет акцента по умолчанию и системный язык.',
    'about': 'О программе',
    'aboutBody':
        'Нативный кроссплатформенный редактор диаграмм Microsoft Visio (.vsdx).',
  };

  static const Map<String, String> _it = <String, String>{
    'appTitle': 'Editor di diagrammi Visio',
    'settings': 'Impostazioni',
    'settingsTooltip': 'Impostazioni',
    'more': 'Altro',
    'newDrawing': 'Nuovo disegno (Cmd+N)',
    'newFromTemplate': 'New from template',
    'openDrawing': 'Apri un disegno Visio (Cmd+O)',
    'save': 'Salva (Cmd+S)',
    'recentFiles': 'File recenti',
    'appearance': 'Aspetto',
    'themeMode': 'Tema',
    'themeModeSystem': 'Sistema',
    'themeModeLight': 'Chiaro',
    'themeModeDark': 'Scuro',
    'themeColor': 'Colore di accento',
    'themeColorHint':
        'Usato per pulsanti, selezione e l’interfaccia dell’app.',
    'language': 'Lingua',
    'languageSystem': 'Sistema',
    ..._languageNames,
    'languageHint':
        'Si applica alle Impostazioni e alle etichette dell’interfaccia principale.',
    'languageSearchHint': 'Cerca lingue',
    'resetDefaults': 'Ripristina predefinite',
    'resetDefaultsHint':
        'Ripristina il tema di sistema, il colore di accento predefinito e la lingua di sistema.',
    'about': 'Informazioni',
    'aboutBody':
        'Un editor nativo multipiattaforma per diagrammi Microsoft Visio (.vsdx).',
  };

  static const Map<String, String> _ar = <String, String>{
    'appTitle': 'محرر مخططات Visio',
    'settings': 'الإعدادات',
    'settingsTooltip': 'الإعدادات',
    'more': 'المزيد',
    'newDrawing': 'رسم جديد (Cmd+N)',
    'newFromTemplate': 'New from template',
    'openDrawing': 'فتح رسم Visio (Cmd+O)',
    'save': 'حفظ (Cmd+S)',
    'recentFiles': 'الملفات الأخيرة',
    'appearance': 'المظهر',
    'themeMode': 'السمة',
    'themeModeSystem': 'النظام',
    'themeModeLight': 'فاتح',
    'themeModeDark': 'داكن',
    'themeColor': 'لون التمييز',
    'themeColorHint': 'يُستخدم للأزرار والتحديد وواجهة التطبيق.',
    'language': 'اللغة',
    'languageSystem': 'النظام',
    ..._languageNames,
    'languageHint': 'يُطبَّق على الإعدادات وتسميات الواجهة الرئيسية.',
    'languageSearchHint': 'البحث عن اللغات',
    'resetDefaults': 'استعادة الإعدادات الافتراضية',
    'resetDefaultsHint':
        'يستعيد سمة النظام ولون التمييز الافتراضي ولغة النظام.',
    'about': 'حول',
    'aboutBody':
        'محرر أصلي متعدد المنصات لمخططات Microsoft Visio ‏(.vsdx).',
  };

  static const Map<String, String> _id = <String, String>{
    'appTitle': 'Editor Diagram Visio',
    'settings': 'Pengaturan',
    'settingsTooltip': 'Pengaturan',
    'more': 'Lainnya',
    'newDrawing': 'Gambar baru (Cmd+N)',
    'newFromTemplate': 'New from template',
    'openDrawing': 'Buka gambar Visio (Cmd+O)',
    'save': 'Simpan (Cmd+S)',
    'recentFiles': 'File terbaru',
    'appearance': 'Tampilan',
    'themeMode': 'Tema',
    'themeModeSystem': 'Sistem',
    'themeModeLight': 'Terang',
    'themeModeDark': 'Gelap',
    'themeColor': 'Warna aksen',
    'themeColorHint':
        'Digunakan untuk tombol, pilihan, dan antarmuka aplikasi.',
    'language': 'Bahasa',
    'languageSystem': 'Sistem',
    ..._languageNames,
    'languageHint':
        'Berlaku untuk Pengaturan dan label antarmuka utama.',
    'languageSearchHint': 'Cari bahasa',
    'resetDefaults': 'Pulihkan ke default',
    'resetDefaultsHint':
        'Mengembalikan tema sistem, warna aksen default, dan bahasa sistem.',
    'about': 'Tentang',
    'aboutBody':
        'Editor asli lintas platform untuk diagram Microsoft Visio (.vsdx).',
  };

  static const Map<String, String> _hi = <String, String>{
    'appTitle': 'Visio आरेख संपादक',
    'settings': 'सेटिंग्स',
    'settingsTooltip': 'सेटिंग्स',
    'more': 'अधिक',
    'newDrawing': 'नया ड्राइंग (Cmd+N)',
    'newFromTemplate': 'New from template',
    'openDrawing': 'Visio ड्राइंग खोलें (Cmd+O)',
    'save': 'सहेजें (Cmd+S)',
    'recentFiles': 'हाल की फ़ाइलें',
    'appearance': 'दिखावट',
    'themeMode': 'थीम',
    'themeModeSystem': 'सिस्टम',
    'themeModeLight': 'हल्की',
    'themeModeDark': 'गहरी',
    'themeColor': 'एक्सेंट रंग',
    'themeColorHint': 'बटन, चयन और ऐप इंटरफ़ेस के लिए उपयोग होता है।',
    'language': 'भाषा',
    'languageSystem': 'सिस्टम',
    ..._languageNames,
    'languageHint': 'सेटिंग्स और मुख्य इंटरफ़ेस लेबल पर लागू होता है।',
    'languageSearchHint': 'भाषाएँ खोजें',
    'resetDefaults': 'डिफ़ॉल्ट पर रीसेट करें',
    'resetDefaultsHint':
        'सिस्टम थीम, डिफ़ॉल्ट एक्सेंट रंग और सिस्टम भाषा पुनर्स्थापित करता है।',
    'about': 'परिचय',
    'aboutBody':
        'Microsoft Visio (.vsdx) आरेखों के लिए एक नेटिव क्रॉस-प्लेटफ़ॉर्म संपादक।',
  };

  static const Map<String, String> _nl = <String, String>{
    'appTitle': 'Editor voor Visio-diagrammen',
    'settings': 'Instellingen',
    'settingsTooltip': 'Instellingen',
    'more': 'Meer',
    'newDrawing': 'Nieuwe tekening (Cmd+N)',
    'newFromTemplate': 'New from template',
    'openDrawing': 'Visio-tekening openen (Cmd+O)',
    'save': 'Opslaan (Cmd+S)',
    'recentFiles': 'Recente bestanden',
    'appearance': 'Weergave',
    'themeMode': 'Thema',
    'themeModeSystem': 'Systeem',
    'themeModeLight': 'Licht',
    'themeModeDark': 'Donker',
    'themeColor': 'Accentkleur',
    'themeColorHint':
        'Gebruikt voor knoppen, selectie en de app-interface.',
    'language': 'Taal',
    'languageSystem': 'Systeem',
    ..._languageNames,
    'languageHint':
        'Geldt voor Instellingen en labels van de hoofdinterface.',
    'languageSearchHint': 'Talen zoeken',
    'resetDefaults': 'Standaardwaarden herstellen',
    'resetDefaultsHint':
        'Herstelt systeemthema, standaard accentkleur en systeemtaal.',
    'about': 'Over',
    'aboutBody':
        'Een native platformonafhankelijke editor voor Microsoft Visio (.vsdx)-diagrammen.',
  };

  static const Map<String, String> _tr = <String, String>{
    'appTitle': 'Visio Diyagram Düzenleyici',
    'settings': 'Ayarlar',
    'settingsTooltip': 'Ayarlar',
    'more': 'Diğer',
    'newDrawing': 'Yeni çizim (Cmd+N)',
    'newFromTemplate': 'New from template',
    'openDrawing': 'Visio çizimi aç (Cmd+O)',
    'save': 'Kaydet (Cmd+S)',
    'recentFiles': 'Son dosyalar',
    'appearance': 'Görünüm',
    'themeMode': 'Tema',
    'themeModeSystem': 'Sistem',
    'themeModeLight': 'Açık',
    'themeModeDark': 'Koyu',
    'themeColor': 'Vurgu rengi',
    'themeColorHint':
        'Düğmeler, seçim ve uygulama arayüzü için kullanılır.',
    'language': 'Dil',
    'languageSystem': 'Sistem',
    ..._languageNames,
    'languageHint':
        'Ayarlar ve ana arayüz etiketleri için geçerlidir.',
    'languageSearchHint': 'Dil ara',
    'resetDefaults': 'Varsayılanlara sıfırla',
    'resetDefaultsHint':
        'Sistem temasını, varsayılan vurgu rengini ve sistem dilini geri yükler.',
    'about': 'Hakkında',
    'aboutBody':
        'Microsoft Visio (.vsdx) diyagramları için yerel, platformlar arası bir düzenleyici.',
  };

  static const Map<String, String> _pl = <String, String>{
    'appTitle': 'Edytor diagramów Visio',
    'settings': 'Ustawienia',
    'settingsTooltip': 'Ustawienia',
    'more': 'Więcej',
    'newDrawing': 'Nowy rysunek (Cmd+N)',
    'newFromTemplate': 'New from template',
    'openDrawing': 'Otwórz rysunek Visio (Cmd+O)',
    'save': 'Zapisz (Cmd+S)',
    'recentFiles': 'Ostatnie pliki',
    'appearance': 'Wygląd',
    'themeMode': 'Motyw',
    'themeModeSystem': 'Systemowy',
    'themeModeLight': 'Jasny',
    'themeModeDark': 'Ciemny',
    'themeColor': 'Kolor akcentu',
    'themeColorHint':
        'Używany do przycisków, zaznaczenia i interfejsu aplikacji.',
    'language': 'Język',
    'languageSystem': 'Systemowy',
    ..._languageNames,
    'languageHint':
        'Dotyczy Ustawień i etykiet głównego interfejsu.',
    'languageSearchHint': 'Szukaj języków',
    'resetDefaults': 'Przywróć domyślne',
    'resetDefaultsHint':
        'Przywraca motyw systemowy, domyślny kolor akcentu i język systemowy.',
    'about': 'Informacje',
    'aboutBody':
        'Natywny, wieloplatformowy edytor diagramów Microsoft Visio (.vsdx).',
  };

  static const Map<String, String> _vi = <String, String>{
    'appTitle': 'Trình chỉnh sửa sơ đồ Visio',
    'settings': 'Cài đặt',
    'settingsTooltip': 'Cài đặt',
    'more': 'Thêm',
    'newDrawing': 'Bản vẽ mới (Cmd+N)',
    'newFromTemplate': 'New from template',
    'openDrawing': 'Mở bản vẽ Visio (Cmd+O)',
    'save': 'Lưu (Cmd+S)',
    'recentFiles': 'Tệp gần đây',
    'appearance': 'Giao diện',
    'themeMode': 'Chủ đề',
    'themeModeSystem': 'Hệ thống',
    'themeModeLight': 'Sáng',
    'themeModeDark': 'Tối',
    'themeColor': 'Màu nhấn',
    'themeColorHint':
        'Dùng cho nút, vùng chọn và giao diện ứng dụng.',
    'language': 'Ngôn ngữ',
    'languageSystem': 'Hệ thống',
    ..._languageNames,
    'languageHint':
        'Áp dụng cho Cài đặt và nhãn giao diện chính.',
    'languageSearchHint': 'Tìm ngôn ngữ',
    'resetDefaults': 'Khôi phục mặc định',
    'resetDefaultsHint':
        'Khôi phục chủ đề hệ thống, màu nhấn mặc định và ngôn ngữ hệ thống.',
    'about': 'Giới thiệu',
    'aboutBody':
        'Trình chỉnh sửa gốc đa nền tảng cho sơ đồ Microsoft Visio (.vsdx).',
  };

  static const Map<String, String> _th = <String, String>{
    'appTitle': 'ตัวแก้ไขไดอะแกรม Visio',
    'settings': 'การตั้งค่า',
    'settingsTooltip': 'การตั้งค่า',
    'more': 'เพิ่มเติม',
    'newDrawing': 'ภาพวาดใหม่ (Cmd+N)',
    'newFromTemplate': 'New from template',
    'openDrawing': 'เปิดภาพวาด Visio (Cmd+O)',
    'save': 'บันทึก (Cmd+S)',
    'recentFiles': 'ไฟล์ล่าสุด',
    'appearance': 'ลักษณะ',
    'themeMode': 'ธีม',
    'themeModeSystem': 'ระบบ',
    'themeModeLight': 'สว่าง',
    'themeModeDark': 'มืด',
    'themeColor': 'สีเน้น',
    'themeColorHint': 'ใช้กับปุ่ม การเลือก และส่วนติดต่อแอป',
    'language': 'ภาษา',
    'languageSystem': 'ระบบ',
    ..._languageNames,
    'languageHint': 'ใช้กับการตั้งค่าและป้ายกำกับส่วนติดต่อหลัก',
    'languageSearchHint': 'ค้นหาภาษา',
    'resetDefaults': 'คืนค่าเริ่มต้น',
    'resetDefaultsHint':
        'คืนค่าธีมระบบ สีเน้นเริ่มต้น และภาษาระบบ',
    'about': 'เกี่ยวกับ',
    'aboutBody':
        'ตัวแก้ไขเนทีฟข้ามแพลตฟอร์มสำหรับไดอะแกรม Microsoft Visio (.vsdx)',
  };

  static const Map<String, String> _sv = <String, String>{
    'appTitle': 'Redigerare för Visio-diagram',
    'settings': 'Inställningar',
    'settingsTooltip': 'Inställningar',
    'more': 'Mer',
    'newDrawing': 'Ny ritning (Cmd+N)',
    'newFromTemplate': 'New from template',
    'openDrawing': 'Öppna en Visio-ritning (Cmd+O)',
    'save': 'Spara (Cmd+S)',
    'recentFiles': 'Senaste filer',
    'appearance': 'Utseende',
    'themeMode': 'Tema',
    'themeModeSystem': 'System',
    'themeModeLight': 'Ljust',
    'themeModeDark': 'Mörkt',
    'themeColor': 'Accentfärg',
    'themeColorHint':
        'Används för knappar, markering och appgränssnittet.',
    'language': 'Språk',
    'languageSystem': 'System',
    ..._languageNames,
    'languageHint':
        'Gäller Inställningar och etiketter i huvudgränssnittet.',
    'languageSearchHint': 'Sök språk',
    'resetDefaults': 'Återställ standardvärden',
    'resetDefaultsHint':
        'Återställer systemtema, standardaccentfärg och systemspråk.',
    'about': 'Om',
    'aboutBody':
        'En inbyggd plattformsoberoende redigerare för Microsoft Visio (.vsdx)-diagram.',
  };

  static const Map<String, String> _uk = <String, String>{
    'appTitle': 'Редактор діаграм Visio',
    'settings': 'Параметри',
    'settingsTooltip': 'Параметри',
    'more': 'Більше',
    'newDrawing': 'Новий креслення (Cmd+N)',
    'newFromTemplate': 'New from template',
    'openDrawing': 'Відкрити креслення Visio (Cmd+O)',
    'save': 'Зберегти (Cmd+S)',
    'recentFiles': 'Нещодавні файли',
    'appearance': 'Оформлення',
    'themeMode': 'Тема',
    'themeModeSystem': 'Системна',
    'themeModeLight': 'Світла',
    'themeModeDark': 'Темна',
    'themeColor': 'Колір акценту',
    'themeColorHint':
        'Використовується для кнопок, виділення та інтерфейсу програми.',
    'language': 'Мова',
    'languageSystem': 'Системна',
    ..._languageNames,
    'languageHint':
        'Застосовується до Параметрів і підписів головного інтерфейсу.',
    'languageSearchHint': 'Пошук мов',
    'resetDefaults': 'Скинути до стандартних',
    'resetDefaultsHint':
        'Відновлює системну тему, стандартний колір акценту та системну мову.',
    'about': 'Про програму',
    'aboutBody':
        'Нативний кросплатформний редактор діаграм Microsoft Visio (.vsdx).',
  };

  static const Map<String, String> _he = <String, String>{
    'appTitle': 'עורך דיאגרמות Visio',
    'settings': 'הגדרות',
    'settingsTooltip': 'הגדרות',
    'more': 'עוד',
    'newDrawing': 'שרטוט חדש (Cmd+N)',
    'newFromTemplate': 'New from template',
    'openDrawing': 'פתיחת שרטוט Visio (Cmd+O)',
    'save': 'שמירה (Cmd+S)',
    'recentFiles': 'קבצים אחרונים',
    'appearance': 'מראה',
    'themeMode': 'ערכת נושא',
    'themeModeSystem': 'מערכת',
    'themeModeLight': 'בהיר',
    'themeModeDark': 'כהה',
    'themeColor': 'צבע הדגשה',
    'themeColorHint': 'משמש ללחצנים, בחירה וממשק האפליקציה.',
    'language': 'שפה',
    'languageSystem': 'מערכת',
    ..._languageNames,
    'languageHint': 'חל על ההגדרות ותוויות הממשק הראשי.',
    'languageSearchHint': 'חיפוש שפות',
    'resetDefaults': 'איפוס לברירות מחדל',
    'resetDefaultsHint':
        'משחזר את ערכת הנושא של המערכת, צבע ההדגשה המוגדר כברירת מחדל ואת שפת המערכת.',
    'about': 'אודות',
    'aboutBody':
        'עורך מקורי חוצה-פלטפורמות לדיאגרמות Microsoft Visio ‏(.vsdx).',
  };

  static const Map<String, String> _cs = <String, String>{
    'appTitle': 'Editor diagramů Visio',
    'settings': 'Nastavení',
    'settingsTooltip': 'Nastavení',
    'more': 'Další',
    'newDrawing': 'Nový výkres (Cmd+N)',
    'newFromTemplate': 'New from template',
    'openDrawing': 'Otevřít výkres Visio (Cmd+O)',
    'save': 'Uložit (Cmd+S)',
    'recentFiles': 'Nedávné soubory',
    'appearance': 'Vzhled',
    'themeMode': 'Motiv',
    'themeModeSystem': 'Systémový',
    'themeModeLight': 'Světlý',
    'themeModeDark': 'Tmavý',
    'themeColor': 'Barva zvýraznění',
    'themeColorHint':
        'Používá se pro tlačítka, výběr a rozhraní aplikace.',
    'language': 'Jazyk',
    'languageSystem': 'Systémový',
    ..._languageNames,
    'languageHint':
        'Platí pro Nastavení a popisky hlavního rozhraní.',
    'languageSearchHint': 'Hledat jazyky',
    'resetDefaults': 'Obnovit výchozí',
    'resetDefaultsHint':
        'Obnoví systémový motiv, výchozí barvu zvýraznění a systémový jazyk.',
    'about': 'O aplikaci',
    'aboutBody':
        'Nativní multiplatformní editor diagramů Microsoft Visio (.vsdx).',
  };

  static const Map<String, String> _ro = <String, String>{
    'appTitle': 'Editor de diagrame Visio',
    'settings': 'Setări',
    'settingsTooltip': 'Setări',
    'more': 'Mai mult',
    'newDrawing': 'Desen nou (Cmd+N)',
    'newFromTemplate': 'New from template',
    'openDrawing': 'Deschide un desen Visio (Cmd+O)',
    'save': 'Salvează (Cmd+S)',
    'recentFiles': 'Fișiere recente',
    'appearance': 'Aspect',
    'themeMode': 'Temă',
    'themeModeSystem': 'Sistem',
    'themeModeLight': 'Deschis',
    'themeModeDark': 'Întunecat',
    'themeColor': 'Culoare de accent',
    'themeColorHint':
        'Folosită pentru butoane, selecție și interfața aplicației.',
    'language': 'Limbă',
    'languageSystem': 'Sistem',
    ..._languageNames,
    'languageHint':
        'Se aplică la Setări și etichetele interfeței principale.',
    'languageSearchHint': 'Caută limbi',
    'resetDefaults': 'Resetează la valorile implicite',
    'resetDefaultsHint':
        'Restaurează tema de sistem, culoarea de accent implicită și limba sistemului.',
    'about': 'Despre',
    'aboutBody':
        'Un editor nativ multiplatformă pentru diagrame Microsoft Visio (.vsdx).',
  };

  static const Map<String, String> _el = <String, String>{
    'appTitle': 'Επεξεργαστής διαγραμμάτων Visio',
    'settings': 'Ρυθμίσεις',
    'settingsTooltip': 'Ρυθμίσεις',
    'more': 'Περισσότερα',
    'newDrawing': 'Νέο σχέδιο (Cmd+N)',
    'newFromTemplate': 'New from template',
    'openDrawing': 'Άνοιγμα σχεδίου Visio (Cmd+O)',
    'save': 'Αποθήκευση (Cmd+S)',
    'recentFiles': 'Πρόσφατα αρχεία',
    'appearance': 'Εμφάνιση',
    'themeMode': 'Θέμα',
    'themeModeSystem': 'Σύστημα',
    'themeModeLight': 'Φωτεινό',
    'themeModeDark': 'Σκοτεινό',
    'themeColor': 'Χρώμα έμφασης',
    'themeColorHint':
        'Χρησιμοποιείται για κουμπιά, επιλογή και τη διεπαφή της εφαρμογής.',
    'language': 'Γλώσσα',
    'languageSystem': 'Σύστημα',
    ..._languageNames,
    'languageHint':
        'Ισχύει για τις Ρυθμίσεις και τις ετικέτες της κύριας διεπαφής.',
    'languageSearchHint': 'Αναζήτηση γλωσσών',
    'resetDefaults': 'Επαναφορά προεπιλογών',
    'resetDefaultsHint':
        'Επαναφέρει το θέμα συστήματος, το προεπιλεγμένο χρώμα έμφασης και τη γλώσσα συστήματος.',
    'about': 'Πληροφορίες',
    'aboutBody':
        'Ένας εγγενής επεξεργαστής πολλαπλών πλατφορμών για διαγράμματα Microsoft Visio (.vsdx).',
  };

  static const Map<String, String> _hu = <String, String>{
    'appTitle': 'Visio diagramszerkesztő',
    'settings': 'Beállítások',
    'settingsTooltip': 'Beállítások',
    'more': 'Több',
    'newDrawing': 'Új rajz (Cmd+N)',
    'newFromTemplate': 'New from template',
    'openDrawing': 'Visio-rajz megnyitása (Cmd+O)',
    'save': 'Mentés (Cmd+S)',
    'recentFiles': 'Legutóbbi fájlok',
    'appearance': 'Megjelenés',
    'themeMode': 'Téma',
    'themeModeSystem': 'Rendszer',
    'themeModeLight': 'Világos',
    'themeModeDark': 'Sötét',
    'themeColor': 'Kiemelőszín',
    'themeColorHint':
        'Gombokhoz, kijelöléshez és az alkalmazás felületéhez használatos.',
    'language': 'Nyelv',
    'languageSystem': 'Rendszer',
    ..._languageNames,
    'languageHint':
        'A Beállításokra és a fő felület címkéire vonatkozik.',
    'languageSearchHint': 'Nyelvek keresése',
    'resetDefaults': 'Alapértelmezések visszaállítása',
    'resetDefaultsHint':
        'Visszaállítja a rendszertémát, az alapértelmezett kiemelőszínt és a rendszer nyelvét.',
    'about': 'Névjegy',
    'aboutBody':
        'Natív, többplatformos szerkesztő Microsoft Visio (.vsdx) diagramokhoz.',
  };

  static const Map<String, String> _da = <String, String>{
    'appTitle': 'Editor til Visio-diagrammer',
    'settings': 'Indstillinger',
    'settingsTooltip': 'Indstillinger',
    'more': 'Mere',
    'newDrawing': 'Ny tegning (Cmd+N)',
    'newFromTemplate': 'New from template',
    'openDrawing': 'Åbn en Visio-tegning (Cmd+O)',
    'save': 'Gem (Cmd+S)',
    'recentFiles': 'Seneste filer',
    'appearance': 'Udseende',
    'themeMode': 'Tema',
    'themeModeSystem': 'System',
    'themeModeLight': 'Lyst',
    'themeModeDark': 'Mørkt',
    'themeColor': 'Accentfarve',
    'themeColorHint':
        'Bruges til knapper, markering og appens grænseflade.',
    'language': 'Sprog',
    'languageSystem': 'System',
    ..._languageNames,
    'languageHint':
        'Gælder for Indstillinger og etiketter i hovedgrænsefladen.',
    'languageSearchHint': 'Søg sprog',
    'resetDefaults': 'Nulstil til standard',
    'resetDefaultsHint':
        'Gendanner systemtema, standardaccentfarve og systemsprog.',
    'about': 'Om',
    'aboutBody':
        'En indbygget platformsuafhængig editor til Microsoft Visio (.vsdx)-diagrammer.',
  };

  static const Map<String, String> _ms = <String, String>{
    'appTitle': 'Editor Diagram Visio',
    'settings': 'Tetapan',
    'settingsTooltip': 'Tetapan',
    'more': 'Lagi',
    'newDrawing': 'Lukisan baharu (Cmd+N)',
    'newFromTemplate': 'New from template',
    'openDrawing': 'Buka lukisan Visio (Cmd+O)',
    'save': 'Simpan (Cmd+S)',
    'recentFiles': 'Fail terkini',
    'appearance': 'Penampilan',
    'themeMode': 'Tema',
    'themeModeSystem': 'Sistem',
    'themeModeLight': 'Cerah',
    'themeModeDark': 'Gelap',
    'themeColor': 'Warna aksen',
    'themeColorHint':
        'Digunakan untuk butang, pilihan dan antara muka aplikasi.',
    'language': 'Bahasa',
    'languageSystem': 'Sistem',
    ..._languageNames,
    'languageHint':
        'Digunakan untuk Tetapan dan label antara muka utama.',
    'languageSearchHint': 'Cari bahasa',
    'resetDefaults': 'Set semula kepada lalai',
    'resetDefaultsHint':
        'Memulihkan tema sistem, warna aksen lalai dan bahasa sistem.',
    'about': 'Perihal',
    'aboutBody':
        'Editor asli merentas platform untuk diagram Microsoft Visio (.vsdx).',
  };

  static const Map<String, String> _fi = <String, String>{
    'appTitle': 'Visio-kaavioiden muokkain',
    'settings': 'Asetukset',
    'settingsTooltip': 'Asetukset',
    'more': 'Lisää',
    'newDrawing': 'Uusi piirustus (Cmd+N)',
    'newFromTemplate': 'New from template',
    'openDrawing': 'Avaa Visio-piirustus (Cmd+O)',
    'save': 'Tallenna (Cmd+S)',
    'recentFiles': 'Viimeisimmät tiedostot',
    'appearance': 'Ulkoasu',
    'themeMode': 'Teema',
    'themeModeSystem': 'Järjestelmä',
    'themeModeLight': 'Vaalea',
    'themeModeDark': 'Tumma',
    'themeColor': 'Korostusväri',
    'themeColorHint':
        'Käytetään painikkeissa, valinnassa ja sovelluksen käyttöliittymässä.',
    'language': 'Kieli',
    'languageSystem': 'Järjestelmä',
    ..._languageNames,
    'languageHint':
        'Koskee Asetuksia ja pääkäyttöliittymän otsikoita.',
    'languageSearchHint': 'Hae kieliä',
    'resetDefaults': 'Palauta oletukset',
    'resetDefaultsHint':
        'Palauttaa järjestelmäteeman, oletuskorostusvärin ja järjestelmän kielen.',
    'about': 'Tietoja',
    'aboutBody':
        'Natiivi monialustainen muokkain Microsoft Visio (.vsdx) -kaavioille.',
  };

  static const Map<String, String> _nb = <String, String>{
    'appTitle': 'Redigeringsprogram for Visio-diagrammer',
    'settings': 'Innstillinger',
    'settingsTooltip': 'Innstillinger',
    'more': 'Mer',
    'newDrawing': 'Ny tegning (Cmd+N)',
    'newFromTemplate': 'New from template',
    'openDrawing': 'Åpne en Visio-tegning (Cmd+O)',
    'save': 'Lagre (Cmd+S)',
    'recentFiles': 'Nylige filer',
    'appearance': 'Utseende',
    'themeMode': 'Tema',
    'themeModeSystem': 'System',
    'themeModeLight': 'Lyst',
    'themeModeDark': 'Mørkt',
    'themeColor': 'Aksentfarge',
    'themeColorHint':
        'Brukes til knapper, markering og appgrensesnittet.',
    'language': 'Språk',
    'languageSystem': 'System',
    ..._languageNames,
    'languageHint':
        'Gjelder Innstillinger og etiketter i hovedgrensesnittet.',
    'languageSearchHint': 'Søk etter språk',
    'resetDefaults': 'Tilbakestill til standard',
    'resetDefaultsHint':
        'Gjenoppretter systemtema, standard aksentfarge og systemspråk.',
    'about': 'Om',
    'aboutBody':
        'En innebygd plattformuavhengig redigeringsapp for Microsoft Visio (.vsdx)-diagrammer.',
  };

  static const Map<String, String> _sk = <String, String>{
    'appTitle': 'Editor diagramov Visio',
    'settings': 'Nastavenia',
    'settingsTooltip': 'Nastavenia',
    'more': 'Viac',
    'newDrawing': 'Nový výkres (Cmd+N)',
    'newFromTemplate': 'New from template',
    'openDrawing': 'Otvoriť výkres Visio (Cmd+O)',
    'save': 'Uložiť (Cmd+S)',
    'recentFiles': 'Nedávne súbory',
    'appearance': 'Vzhľad',
    'themeMode': 'Motív',
    'themeModeSystem': 'Systémový',
    'themeModeLight': 'Svetlý',
    'themeModeDark': 'Tmavý',
    'themeColor': 'Farba zvýraznenia',
    'themeColorHint':
        'Používa sa pre tlačidlá, výber a rozhranie aplikácie.',
    'language': 'Jazyk',
    'languageSystem': 'Systémový',
    ..._languageNames,
    'languageHint':
        'Platí pre Nastavenia a popisky hlavného rozhrania.',
    'languageSearchHint': 'Hľadať jazyky',
    'resetDefaults': 'Obnoviť predvolené',
    'resetDefaultsHint':
        'Obnoví systémový motív, predvolenú farbu zvýraznenia a systémový jazyk.',
    'about': 'O aplikácii',
    'aboutBody':
        'Natívny multiplatformový editor diagramov Microsoft Visio (.vsdx).',
  };

  static const Map<String, String> _bn = <String, String>{
    'appTitle': 'Visio ডায়াগ্রাম সম্পাদক',
    'settings': 'সেটিংস',
    'settingsTooltip': 'সেটিংস',
    'more': 'আরও',
    'newDrawing': 'নতুন অঙ্কন (Cmd+N)',
    'newFromTemplate': 'New from template',
    'openDrawing': 'Visio অঙ্কন খুলুন (Cmd+O)',
    'save': 'সংরক্ষণ (Cmd+S)',
    'recentFiles': 'সাম্প্রতিক ফাইল',
    'appearance': 'চেহারা',
    'themeMode': 'থিম',
    'themeModeSystem': 'সিস্টেম',
    'themeModeLight': 'হালকা',
    'themeModeDark': 'গাঢ়',
    'themeColor': 'অ্যাকসেন্ট রঙ',
    'themeColorHint': 'বোতাম, নির্বাচন এবং অ্যাপ ইন্টারফেসের জন্য ব্যবহৃত।',
    'language': 'ভাষা',
    'languageSystem': 'সিস্টেম',
    ..._languageNames,
    'languageHint': 'সেটিংস এবং প্রধান ইন্টারফেস লেবেলে প্রযোজ্য।',
    'languageSearchHint': 'ভাষা খুঁজুন',
    'resetDefaults': 'ডিফল্টে রিসেট করুন',
    'resetDefaultsHint':
        'সিস্টেম থিম, ডিফল্ট অ্যাকসেন্ট রঙ এবং সিস্টেম ভাষা পুনরুদ্ধার করে।',
    'about': 'সম্পর্কে',
    'aboutBody':
        'Microsoft Visio (.vsdx) ডায়াগ্রামের জন্য একটি নেটিভ ক্রস-প্ল্যাটফর্ম সম্পাদক।',
  };

  static const Map<String, String> _fa = <String, String>{
    'appTitle': 'ویرایشگر نمودار Visio',
    'settings': 'تنظیمات',
    'settingsTooltip': 'تنظیمات',
    'more': 'بیشتر',
    'newDrawing': 'رسم جدید (Cmd+N)',
    'newFromTemplate': 'New from template',
    'openDrawing': 'باز کردن رسم Visio (Cmd+O)',
    'save': 'ذخیره (Cmd+S)',
    'recentFiles': 'فایل‌های اخیر',
    'appearance': 'ظاهر',
    'themeMode': 'پوسته',
    'themeModeSystem': 'سیستم',
    'themeModeLight': 'روشن',
    'themeModeDark': 'تیره',
    'themeColor': 'رنگ تأکید',
    'themeColorHint': 'برای دکمه‌ها، انتخاب و رابط برنامه استفاده می‌شود.',
    'language': 'زبان',
    'languageSystem': 'سیستم',
    ..._languageNames,
    'languageHint': 'روی تنظیمات و برچسب‌های رابط اصلی اعمال می‌شود.',
    'languageSearchHint': 'جستجوی زبان‌ها',
    'resetDefaults': 'بازنشانی به پیش‌فرض',
    'resetDefaultsHint':
        'پوسته سیستم، رنگ تأکید پیش‌فرض و زبان سیستم را بازمی‌گرداند.',
    'about': 'درباره',
    'aboutBody':
        'یک ویرایشگر بومی چندسکویی برای نمودارهای Microsoft Visio ‏(.vsdx).',
  };

  static const Map<String, String> _bg = <String, String>{
    'appTitle': 'Редактор на Visio диаграми',
    'settings': 'Настройки',
    'settingsTooltip': 'Настройки',
    'more': 'Още',
    'newDrawing': 'Нов чертеж (Cmd+N)',
    'newFromTemplate': 'New from template',
    'openDrawing': 'Отваряне на Visio чертеж (Cmd+O)',
    'save': 'Запазване (Cmd+S)',
    'recentFiles': 'Скорошни файлове',
    'appearance': 'Изглед',
    'themeMode': 'Тема',
    'themeModeSystem': 'Системна',
    'themeModeLight': 'Светла',
    'themeModeDark': 'Тъмна',
    'themeColor': 'Акцентен цвят',
    'themeColorHint':
        'Използва се за бутони, селекция и интерфейса на приложението.',
    'language': 'Език',
    'languageSystem': 'Системен',
    ..._languageNames,
    'languageHint':
        'Отнася се за Настройки и етикетите на основния интерфейс.',
    'languageSearchHint': 'Търсене на езици',
    'resetDefaults': 'Възстановяване на настройките по подразбиране',
    'resetDefaultsHint':
        'Възстановява системната тема, акцентия цвят по подразбиране и системния език.',
    'about': 'Относно',
    'aboutBody':
        'Нативен кросплатформен редактор за диаграми на Microsoft Visio (.vsdx).',
  };

  static const Map<String, String> _hr = <String, String>{
    'appTitle': 'Uređivač Visio dijagrama',
    'settings': 'Postavke',
    'settingsTooltip': 'Postavke',
    'more': 'Više',
    'newDrawing': 'Novi crtež (Cmd+N)',
    'newFromTemplate': 'New from template',
    'openDrawing': 'Otvori Visio crtež (Cmd+O)',
    'save': 'Spremi (Cmd+S)',
    'recentFiles': 'Nedavne datoteke',
    'appearance': 'Izgled',
    'themeMode': 'Tema',
    'themeModeSystem': 'Sustav',
    'themeModeLight': 'Svijetla',
    'themeModeDark': 'Tamna',
    'themeColor': 'Boja naglaska',
    'themeColorHint':
        'Koristi se za gumbe, odabir i sučelje aplikacije.',
    'language': 'Jezik',
    'languageSystem': 'Sustav',
    ..._languageNames,
    'languageHint':
        'Primjenjuje se na Postavke i oznake glavnog sučelja.',
    'languageSearchHint': 'Pretraži jezike',
    'resetDefaults': 'Vrati na zadano',
    'resetDefaultsHint':
        'Vraća sistemsku temu, zadanu boju naglaska i jezik sustava.',
    'about': 'O aplikaciji',
    'aboutBody':
        'Izvorni višeplatformski uređivač za Microsoft Visio (.vsdx) dijagrame.',
  };

  static const Map<String, String> _ca = <String, String>{
    'appTitle': 'Editor de diagrames Visio',
    'settings': 'Configuració',
    'settingsTooltip': 'Configuració',
    'more': 'Més',
    'newDrawing': 'Nou dibuix (Cmd+N)',
    'newFromTemplate': 'New from template',
    'openDrawing': 'Obre un dibuix de Visio (Cmd+O)',
    'save': 'Desa (Cmd+S)',
    'recentFiles': 'Fitxers recents',
    'appearance': 'Aparença',
    'themeMode': 'Tema',
    'themeModeSystem': 'Sistema',
    'themeModeLight': 'Clar',
    'themeModeDark': 'Fosc',
    'themeColor': 'Color d’accent',
    'themeColorHint':
        'S’utilitza per a botons, selecció i la interfície de l’aplicació.',
    'language': 'Idioma',
    'languageSystem': 'Sistema',
    ..._languageNames,
    'languageHint':
        'S’aplica a la Configuració i a les etiquetes de la interfície principal.',
    'languageSearchHint': 'Cerca idiomes',
    'resetDefaults': 'Restableix els valors predeterminats',
    'resetDefaultsHint':
        'Restaura el tema del sistema, el color d’accent predeterminat i l’idioma del sistema.',
    'about': 'Quant a',
    'aboutBody':
        'Un editor natiu multiplataforma per a diagrames de Microsoft Visio (.vsdx).',
  };

  static const Map<String, String> _fil = <String, String>{
    'appTitle': 'Editor ng Visio Diagram',
    'settings': 'Mga Setting',
    'settingsTooltip': 'Mga Setting',
    'more': 'Higit pa',
    'newDrawing': 'Bagong drawing (Cmd+N)',
    'newFromTemplate': 'New from template',
    'openDrawing': 'Magbukas ng Visio drawing (Cmd+O)',
    'save': 'I-save (Cmd+S)',
    'recentFiles': 'Mga kamakailang file',
    'appearance': 'Hitsura',
    'themeMode': 'Tema',
    'themeModeSystem': 'System',
    'themeModeLight': 'Maliwanag',
    'themeModeDark': 'Madilim',
    'themeColor': 'Kulay ng accent',
    'themeColorHint':
        'Ginagamit para sa mga button, pagpili, at interface ng app.',
    'language': 'Wika',
    'languageSystem': 'System',
    ..._languageNames,
    'languageHint':
        'Nalalapat sa Mga Setting at mga label ng pangunahing interface.',
    'languageSearchHint': 'Maghanap ng wika',
    'resetDefaults': 'Ibalik sa default',
    'resetDefaultsHint':
        'Ibinabalik ang system theme, default na accent color, at system language.',
    'about': 'Tungkol',
    'aboutBody':
        'Isang native na cross-platform editor para sa mga Microsoft Visio (.vsdx) diagram.',
  };

  static const Map<String, String> _sw = <String, String>{
    'appTitle': 'Kihariri cha michoro ya Visio',
    'settings': 'Mipangilio',
    'settingsTooltip': 'Mipangilio',
    'more': 'Zaidi',
    'newDrawing': 'Mchoro mpya (Cmd+N)',
    'newFromTemplate': 'New from template',
    'openDrawing': 'Fungua mchoro wa Visio (Cmd+O)',
    'save': 'Hifadhi (Cmd+S)',
    'recentFiles': 'Faili za hivi karibuni',
    'appearance': 'Muonekano',
    'themeMode': 'Mandhari',
    'themeModeSystem': 'Mfumo',
    'themeModeLight': 'Mwanga',
    'themeModeDark': 'Giza',
    'themeColor': 'Rangi ya mkazo',
    'themeColorHint':
        'Inatumika kwa vitufe, uteuzi na kiolesura cha programu.',
    'language': 'Lugha',
    'languageSystem': 'Mfumo',
    ..._languageNames,
    'languageHint':
        'Inatumika kwa Mipangilio na lebo za kiolesura kikuu.',
    'languageSearchHint': 'Tafuta lugha',
    'resetDefaults': 'Rejesha chaguo-msingi',
    'resetDefaultsHint':
        'Inarejesha mandhari ya mfumo, rangi ya mkazo chaguo-msingi na lugha ya mfumo.',
    'about': 'Kuhusu',
    'aboutBody':
        'Kihariri asili cha majukwaa mbalimbali kwa michoro ya Microsoft Visio (.vsdx).',
  };
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  static const Set<String> _supportedLanguageCodes = <String>{
    'en',
    'zh',
    'ja',
    'ko',
    'es',
    'fr',
    'de',
    'pt',
    'ru',
    'it',
    'ar',
    'id',
    'hi',
    'nl',
    'tr',
    'pl',
    'vi',
    'th',
    'sv',
    'uk',
    'he',
    'cs',
    'ro',
    'el',
    'hu',
    'da',
    'ms',
    'fi',
    'nb',
    'sk',
    'bn',
    'fa',
    'bg',
    'hr',
    'ca',
    'fil',
    'sw',
  };

  @override
  bool isSupported(Locale locale) =>
      _supportedLanguageCodes.contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(AppLocalizations(locale));
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
