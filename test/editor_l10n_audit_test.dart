import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/l10n/app_localizations.dart';
import 'package:visioeditor/l10n/editor_l10n.dart';
import 'package:visioeditor/l10n/editor_l10n_maps.dart';

/// Completeness / correctness guards for EditorL10n across all locales.
void main() {
  final en = kEditorL10nTables['en']!;
  final uiKeys = en.keys
      .where((k) => !k.startsWith('st_'))
      .toList(growable: false);

  test('EditorL10n tables cover every AppLocalizations locale', () {
    final codes = {
      for (final l in AppLocalizations.supportedLocales) l.languageCode,
    };
    expect(kEditorL10nTables.keys.toSet(), codes);
  });

  test('every locale has full UI key set and non-empty values', () {
    for (final lang in kEditorL10nTables.keys) {
      final table = kEditorL10nTables[lang]!;
      for (final key in uiKeys) {
        expect(table.containsKey(key), isTrue,
            reason: '$lang missing UI key $key');
        expect(table[key]!.trim(), isNotEmpty,
            reason: '$lang.$key is empty');
      }
    }
  });

  test('placeholders match English for every UI string', () {
    final ph = RegExp(r'\{[a-zA-Z_]+\}|#\{[a-zA-Z_]+\}');
    for (final lang in kEditorL10nTables.keys) {
      final table = kEditorL10nTables[lang]!;
      for (final key in uiKeys) {
        final enPh = ph.allMatches(en[key]!).map((m) => m.group(0)).toSet();
        final gotPh =
            ph.allMatches(table[key]!).map((m) => m.group(0)).toSet();
        expect(gotPh, enPh, reason: '$lang.$key placeholders');
      }
    }
  });

  test('core actions are localized (not English) for non-en locales', () {
    const core = <String>[
      'undo',
      'redo',
      'cut',
      'copy',
      'paste',
      'cancel',
      'layers',
      'newDrawing',
      'flipHorizontal',
      'justify',
      'strikethrough',
      'noResults',
    ];
    for (final lang in kEditorL10nTables.keys) {
      if (lang == 'en') continue;
      final table = kEditorL10nTables[lang]!;
      for (final key in core) {
        expect(table[key], isNot(en[key]),
            reason: '$lang.$key still English');
      }
    }
  });

  test('Portuguese is not Spanish (common false friends)', () {
    final pt = kEditorL10nTables['pt']!;
    expect(pt['ok'], isNot('Aceptar'));
    expect(pt['pasteStyle'], 'Colar estilo');
    expect(pt['pasteHere'], contains('Colar'));
    expect(pt['editLink'], contains('ligação'));
    expect(pt['layers'], 'Camadas');
    expect(pt['selectAll'], contains('Selecionar'));
    expect(pt['closeTab'], contains('Fechar'));
  });

  test('Nordic / Dutch UI is not German', () {
    final de = kEditorL10nTables['de']!;
    const langs = <String>['da', 'nb', 'sv', 'fi', 'nl'];
    const probes = <String>[
      'pasteStyle',
      'emptySubtitle',
      'closeTab',
      'lineJumps',
      'noLayersYet',
      'fitToWindowShortcut',
    ];
    for (final lang in langs) {
      final table = kEditorL10nTables[lang]!;
      for (final key in probes) {
        expect(table[key], isNot(de[key]),
            reason: '$lang.$key still matches German');
      }
      expect(table['pasteStyle']!.contains('einfügen'), isFalse,
          reason: '$lang.pasteStyle looks German');
      expect(table['emptySubtitle']!.startsWith('Erstellen'), isFalse,
          reason: '$lang.emptySubtitle looks German');
    }
    expect(kEditorL10nTables['da']!['pasteStyle'], 'Indsæt format');
    expect(kEditorL10nTables['nl']!['layers'], 'Lagen');
    expect(kEditorL10nTables['sv']!['undo'], 'Ångra');
    expect(kEditorL10nTables['fi']!['undo'], 'Kumoa');
    expect(kEditorL10nTables['nb']!['undo'], 'Angre');
  });

  test('Catalan is not Spanish for distinctive strings', () {
    final ca = kEditorL10nTables['ca']!;
    final es = kEditorL10nTables['es']!;
    expect(ca['ok'], 'Acceptar');
    expect(ca['ok'], isNot(es['ok']));
    expect(ca['untitled'], 'Sense títol');
    expect(ca['rulers'], 'Regles');
    expect(ca['paste'], 'Enganxa');
    expect(ca['paste'], isNot(es['paste']));
    expect(ca['closeTab'], contains('pestanya'));
    expect(ca['closeTab'], isNot(es['closeTab']));
    expect(ca['findReplace'], contains('reemplaça'));
  });

  test('Bengali UI is not Hindi (Devanagari)', () {
    final bn = kEditorL10nTables['bn']!;
    final hi = kEditorL10nTables['hi']!;
    // Exclude shared Indic danda punctuation.
    final deva = RegExp(r'[\u0900-\u0963\u0966-\u097F]');
    const probes = <String>[
      'strikethrough',
      'noResults',
      'arrowFilled',
      'defaultFont',
      'hideReplace',
      'jumpRadius',
    ];
    for (final key in probes) {
      expect(bn[key], isNot(hi[key]), reason: 'bn.$key matches Hindi');
      expect(deva.hasMatch(bn[key]!), isFalse,
          reason: 'bn.$key has Devanagari: ${bn[key]}');
    }
    expect(bn['strikethrough'], 'স্ট্রাইকথ্রু');
    expect(bn['noResults'], 'কোনো ফলাফল নেই');
  });

  test('Persian UI is not Arabic for NEW2 strings', () {
    final fa = kEditorL10nTables['fa']!;
    final ar = kEditorL10nTables['ar']!;
    const probes = <String>[
      'strikethrough',
      'noResults',
      'arrowFilled',
      'defaultFont',
      'hideReplace',
      'jumpRadius',
      'matchCaseOn',
    ];
    for (final key in probes) {
      expect(fa[key], isNot(ar[key]), reason: 'fa.$key matches Arabic');
    }
    expect(fa['strikethrough'], 'خط‌خورده');
    expect(fa['noResults'], 'نتیجه‌ای نیست');
  });

  test('Danish find uses native wording', () {
    final da = kEditorL10nTables['da']!;
    expect(da['find'], 'Søg…');
    expect(da['findReplace'], startsWith('Søg'));
  });

  test('no Cyrillic / CJK / Arabic / Hebrew / Devanagari script pollution', () {
    final cyr = RegExp(r'[\u0400-\u04FF]');
    final cjk = RegExp(r'[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]');
    final arab = RegExp(r'[\u0600-\u06FF]');
    final heb = RegExp(r'[\u0590-\u05FF]');
    // Exclude Indic danda U+0964/0965 — shared sentence punctuation (bn/hi/…).
    final deva = RegExp(r'[\u0900-\u0963\u0966-\u097F]');
    final beng = RegExp(r'[\u0980-\u09FF]');
    const cyrLangs = {'ru', 'uk', 'bg'};
    const cjkLangs = {'zh', 'ja', 'ko'};
    const arabLangs = {'ar', 'fa'};
    const hebLangs = {'he'};
    const devaLangs = {'hi'};
    const bengLangs = {'bn'};

    for (final entry in kEditorL10nTables.entries) {
      final lang = entry.key;
      for (final kv in entry.value.entries) {
        if (kv.key.startsWith('st_')) continue;
        final v = kv.value;
        if (!cyrLangs.contains(lang)) {
          expect(cyr.hasMatch(v), isFalse,
              reason: '$lang.${kv.key} has Cyrillic: $v');
        }
        if (!cjkLangs.contains(lang)) {
          expect(cjk.hasMatch(v), isFalse,
              reason: '$lang.${kv.key} has CJK: $v');
        }
        if (!arabLangs.contains(lang)) {
          expect(arab.hasMatch(v), isFalse,
              reason: '$lang.${kv.key} has Arabic: $v');
        }
        if (!hebLangs.contains(lang)) {
          expect(heb.hasMatch(v), isFalse,
              reason: '$lang.${kv.key} has Hebrew: $v');
        }
        if (!devaLangs.contains(lang)) {
          expect(deva.hasMatch(v), isFalse,
              reason: '$lang.${kv.key} has Devanagari: $v');
        }
        if (!bengLangs.contains(lang)) {
          expect(beng.hasMatch(v), isFalse,
              reason: '$lang.${kv.key} has Bengali: $v');
        }
      }
    }
  });

  test('every locale includes full stencil key set', () {
    final stKeys =
        en.keys.where((k) => k.startsWith('st_')).toList(growable: false);
    expect(stKeys, hasLength(604));
    for (final lang in kEditorL10nTables.keys) {
      final table = kEditorL10nTables[lang]!;
      for (final key in stKeys) {
        expect(table.containsKey(key), isTrue,
            reason: '$lang missing stencil key $key');
        expect(table[key]!.trim(), isNotEmpty,
            reason: '$lang.$key empty');
      }
    }
  });

  test('non-English locales localize a majority of stencil names', () {
    final stKeys =
        en.keys.where((k) => k.startsWith('st_')).toList(growable: false);
    for (final lang in kEditorL10nTables.keys) {
      if (lang == 'en') continue;
      final table = kEditorL10nTables[lang]!;
      final localized = stKeys.where((k) => table[k] != en[k]).length;
      expect(localized, greaterThanOrEqualTo(150),
          reason: '$lang only localized $localized/${stKeys.length} stencils');
    }
    // Spot-check formerly English leftovers
    expect(EditorL10n(const Locale('de')).stencil('Boundary'), 'Grenze');
    expect(EditorL10n(const Locale('fr')).stencil('Boundary'), 'Frontière');
    expect(EditorL10n(const Locale('ar')).stencil('Delay'), 'تأخير');
    expect(EditorL10n(const Locale('hi')).stencil('Step'), 'चरण');
    expect(EditorL10n(const Locale('id')).stencil('Pool'), 'Kolam');
    expect(EditorL10n(const Locale('th')).stencil('Cube'), 'ลูกบาศก์');
    expect(EditorL10n(const Locale('vi')).stencil('Flash'), 'Chớp');
    expect(EditorL10n(const Locale('tr')).stencil('Switch'), 'Anahtar');
  });

  test('major locales expose localized stencil names', () {
    final ja = EditorL10n(const Locale('ja'));
    final de = EditorL10n(const Locale('de'));
    final zh = EditorL10n(const Locale('zh'));
    expect(zh.stencil('Rounded Rectangle'), '圆角矩形');
    expect(ja.stencil('Rounded Rectangle'), '角丸四角形');
    expect(de.stencil('Rectangle'), 'Rechteck');
    expect(ja.stencilGroup('Flowchart'), isNot('Flowchart'));

    // Previously missing stencil maps
    expect(EditorL10n(const Locale('sv')).stencil('Rounded Rectangle'),
        'Rundad rektangel');
    expect(EditorL10n(const Locale('cs')).stencil('Circle'), 'Kruh');
    expect(EditorL10n(const Locale('da')).stencil('Cloud'), 'Sky');
    expect(EditorL10n(const Locale('ca')).stencil('Circle'), isNot('Circle'));
    expect(EditorL10n(const Locale('fil')).stencil('Cloud'), 'Ulap');
    expect(EditorL10n(const Locale('fi')).stencil('Rectangle'), 'Suorakulmio');
    expect(EditorL10n(const Locale('nb')).stencil('Star'), 'Stjerne');
    expect(EditorL10n(const Locale('bg')).stencil('Heart'), 'Сърце');
    expect(EditorL10n(const Locale('el')).stencil('Circle'), 'Κύκλος');
    expect(EditorL10n(const Locale('fa')).stencil('Moon'), 'ماه');
    expect(EditorL10n(const Locale('bn')).stencil('Sun'), 'সূর্য');
  });

  test('stencil names have no wrong-script pollution', () {
    final cyr = RegExp(r'[\u0400-\u04FF]');
    final cjk = RegExp(r'[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]');
    final arab = RegExp(r'[\u0600-\u06FF]');
    final heb = RegExp(r'[\u0590-\u05FF]');
    final greek = RegExp(r'[\u0370-\u03FF]');
    final bengali = RegExp(r'[\u0980-\u09FF]');
    const cyrLangs = {'ru', 'uk', 'bg'};
    const cjkLangs = {'zh', 'ja', 'ko'};
    const arabLangs = {'ar', 'fa'};
    const hebLangs = {'he'};
    const greekLangs = {'el'};
    const bengaliLangs = {'bn'};

    for (final entry in kEditorL10nTables.entries) {
      final lang = entry.key;
      for (final kv in entry.value.entries) {
        if (!kv.key.startsWith('st_')) continue;
        final v = kv.value;
        if (!cyrLangs.contains(lang)) {
          expect(cyr.hasMatch(v), isFalse,
              reason: '$lang.${kv.key} has Cyrillic: $v');
        }
        if (!cjkLangs.contains(lang)) {
          expect(cjk.hasMatch(v), isFalse,
              reason: '$lang.${kv.key} has CJK: $v');
        }
        if (!arabLangs.contains(lang)) {
          expect(arab.hasMatch(v), isFalse,
              reason: '$lang.${kv.key} has Arabic: $v');
        }
        if (!hebLangs.contains(lang)) {
          expect(heb.hasMatch(v), isFalse,
              reason: '$lang.${kv.key} has Hebrew: $v');
        }
        if (!greekLangs.contains(lang)) {
          expect(greek.hasMatch(v), isFalse,
              reason: '$lang.${kv.key} has Greek: $v');
        }
        if (!bengaliLangs.contains(lang)) {
          expect(bengali.hasMatch(v), isFalse,
              reason: '$lang.${kv.key} has Bengali: $v');
        }
      }
    }
  });

  test('API getters resolve for all locales without falling back to key', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final el = EditorL10n(locale);
      expect(el.undo, isNot('undo'));
      expect(el.flipHorizontal, isNot('flipHorizontal'));
      expect(el.strikethrough, isNot('strikethrough'));
      expect(el.openFileFailed('E'), contains('E'));
      expect(el.pageOf(2, 5), contains('2'));
      expect(el.arrowNumbered(9), contains('9'));
    }
  });
}
