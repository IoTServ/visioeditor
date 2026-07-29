#!/usr/bin/env python3
"""Regenerate lib/l10n/editor_l10n_maps.dart for all AppLocalizations languages.

Sources (in priority order per language):
  0. Existing generated tables — offline baseline / missing-key fallback
  1. /tmp/all_banks.json — key→string UI banks (cache)
  2. /tmp/phrase_maps_v4.json — English-phrase→translation maps
  3. tool/editor_vocabs.json — compact vocabs expanded via from_vocab()
  4. tool/ui_banks/<lang>.json — curated UI banks (highest priority)

Stencil names: en + zh always; other langs from tool/stencil_maps +
/tmp/stencil_name_maps.json. Missing stencils fall back to English.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_editor_l10n import (  # noqa: E402
    LANGS,
    dart_map,
    extract_map,
    from_vocab,
    translate_stencils,
)
from stencil_maps_data import STENCIL_MAPS  # noqa: E402

MAPS = ROOT / "lib/l10n/editor_l10n_maps.dart"
VOCABS = Path(__file__).with_name("editor_vocabs.json")
UI_BANKS_DIR = Path(__file__).with_name("ui_banks")
BANKS_JSON = Path("/tmp/all_banks.json")
PHRASE_JSON = Path("/tmp/phrase_maps_v4.json")
STENCIL_JSON = Path("/tmp/stencil_name_maps.json")

# Small, explicit bank for UI keys added after the bulk translation pass.
# Keeping this here lets regeneration preserve full locale coverage even when
# cached phrase maps predate the new key.
COLOR_BY_LAYER = {
    "en": "Color by Layer",
    "zh": "按图层着色",
    "ja": "レイヤー別に色分け",
    "ko": "레이어별 색상",
    "es": "Color por capa",
    "fr": "Couleur par calque",
    "de": "Farbe nach Ebene",
    "pt": "Cor por camada",
    "ru": "Цвет по слою",
    "it": "Colore per livello",
    "ar": "اللون حسب الطبقة",
    "id": "Warna menurut lapisan",
    "hi": "परत के अनुसार रंग",
    "nl": "Kleur per laag",
    "tr": "Katmana göre renk",
    "pl": "Kolor według warstwy",
    "vi": "Tô màu theo lớp",
    "th": "สีตามเลเยอร์",
    "sv": "Färg efter lager",
    "uk": "Колір за шаром",
    "he": "צבע לפי שכבה",
    "cs": "Barva podle vrstvy",
    "ro": "Culoare după strat",
    "el": "Χρώμα ανά επίπεδο",
    "hu": "Szín rétegenként",
    "da": "Farve efter lag",
    "ms": "Warna mengikut lapisan",
    "fi": "Väri tason mukaan",
    "nb": "Farge etter lag",
    "sk": "Farba podľa vrstvy",
    "bn": "স্তর অনুযায়ী রঙ",
    "fa": "رنگ بر اساس لایه",
    "bg": "Цвят по слой",
    "hr": "Boja prema sloju",
    "ca": "Color per capa",
    "fil": "Kulay ayon sa layer",
    "sw": "Rangi kwa safu",
}

# Pan / zoom canvas tool (touch-friendly view mode).
TOOL_PAN = {
    "en": "Pan / zoom canvas",
    "zh": "平移 / 缩放画布",
    "ja": "キャンバスをパン / ズーム",
    "ko": "캔버스 이동 / 확대·축소",
    "es": "Desplazar / zoom del lienzo",
    "fr": "Panoramique / zoom du canevas",
    "de": "Zeichenfläche verschieben / zoomen",
    "pt": "Deslocar / zoom da tela",
    "ru": "Панорама / масштаб холста",
    "it": "Pan / zoom area di disegno",
    "ar": "تحريك / تكبير اللوحة",
    "id": "Geser / zum kanvas",
    "hi": "कैनवास पैन / ज़ूम",
    "nl": "Canvas verschuiven / zoomen",
    "tr": "Tuvali kaydır / yakınlaştır",
    "pl": "Przesuń / powiększ płótno",
    "vi": "Di chuyển / phóng to thu nhỏ canvas",
    "th": "เลื่อน / ซูมแคนวาส",
    "sv": "Panorera / zooma duken",
    "uk": "Панорама / масштаб полотна",
    "he": "הזזה / זום של הקנבס",
    "cs": "Posun / zoom plátna",
    "ro": "Panoramare / zoom pânză",
    "el": "Μετακίνηση / ζουμ καμβά",
    "hu": "Vászon mozgatása / nagyítása",
    "da": "Panorér / zoom lærred",
    "ms": "Pan / zum kanvas",
    "fi": "Siirrä / zoomaa kangasta",
    "nb": "Panorer / zoom lerret",
    "sk": "Posun / zoom plátna",
    "bn": "ক্যানভাস প্যান / জুম",
    "fa": "جابه‌جایی / بزرگ‌نمایی بوم",
    "bg": "Панорама / мащаб на платното",
    "hr": "Pomicanje / zumiranje platna",
    "ca": "Desplaçar / zoom del llenç",
    "fil": "I-pan / i-zoom ang canvas",
    "sw": "Sogeza / kukuza turubai",
}

SELECT_EDGES = {
    "en": "Select Edges",
    "zh": "选择连接线",
    "ja": "エッジを選択",
    "ko": "연결선 선택",
    "es": "Seleccionar conectores",
    "fr": "Sélectionner les connecteurs",
    "de": "Verbinder auswählen",
    "pt": "Selecionar conectores",
    "ru": "Выбрать соединители",
    "it": "Seleziona connettori",
    "ar": "تحديد الموصلات",
    "id": "Pilih konektor",
    "hi": "कनेक्टर चुनें",
    "nl": "Selecteer verbindingslijnen",
    "tr": "Bağlayıcıları seç",
    "pl": "Zaznacz łączniki",
    "vi": "Chọn đường nối",
    "th": "เลือกเส้นเชื่อม",
    "sv": "Markera kopplingar",
    "uk": "Вибрати з’єднувачі",
    "he": "בחר מחברים",
    "cs": "Vybrat spojnice",
    "ro": "Selectează conectorii",
    "el": "Επιλογή συνδέσμων",
    "hu": "Összekötők kijelölése",
    "da": "Vælg forbindelser",
    "ms": "Pilih penyambung",
    "fi": "Valitse yhdysviivat",
    "nb": "Velg koblinger",
    "sk": "Vybrať spojnice",
    "bn": "সংযোগকারী নির্বাচন করুন",
    "fa": "انتخاب اتصال‌دهنده‌ها",
    "bg": "Избери съединители",
    "hr": "Odaberi poveznice",
    "ca": "Selecciona connectors",
    "fil": "Piliin ang mga connector",
    "sw": "Chagua viunganishi",
}

SELECT_VERTICES = {
    "en": "Select Vertices",
    "zh": "选择图形",
    "ja": "頂点を選択",
    "ko": "도형 선택",
    "es": "Seleccionar vértices",
    "fr": "Sélectionner les sommets",
    "de": "Formen auswählen",
    "pt": "Selecionar vértices",
    "ru": "Выбрать вершины",
    "it": "Seleziona vertici",
    "ar": "تحديد الرؤوس",
    "id": "Pilih simpul",
    "hi": "शीर्ष चुनें",
    "nl": "Selecteer vormen",
    "tr": "Köşeleri seç",
    "pl": "Zaznacz wierzchołki",
    "vi": "Chọn đỉnh",
    "th": "เลือกจุดยอด",
    "sv": "Markera hörn",
    "uk": "Вибрати вершини",
    "he": "בחר קודקודים",
    "cs": "Vybrat vrcholy",
    "ro": "Selectează vârfurile",
    "el": "Επιλογή κορυφών",
    "hu": "Csúcsok kijelölése",
    "da": "Vælg knudepunkter",
    "ms": "Pilih bucu",
    "fi": "Valitse solmut",
    "nb": "Velg hjørner",
    "sk": "Vybrať vrcholy",
    "bn": "শীর্ষবিন্দু নির্বাচন করুন",
    "fa": "انتخاب رأس‌ها",
    "bg": "Избери върхове",
    "hr": "Odaberi vrhove",
    "ca": "Selecciona vèrtexs",
    "fil": "Piliin ang mga vertex",
    "sw": "Chagua vipeo",
}


def load_existing() -> dict[str, dict[str, str]]:
    """Load all generated tables as the offline regeneration baseline."""
    if MAPS.exists():
        text = MAPS.read_text()
        import re

        def grab(name: str) -> dict[str, str]:
            m = re.search(
                rf"const Map<String, String> {name} = <String, String>\{{(.*?)\n}};",
                text,
                re.S,
            )
            if not m:
                raise SystemExit(f"cannot find {name} in {MAPS}")
            body = m.group(1)
            body2 = re.sub(r"'([^']*)'\s*\n\s*'([^']*)'", r"'\1\2'", body)
            body2 = re.sub(r"'([^']*)'\s*\n\s*'([^']*)'", r"'\1\2'", body2)
            entry = re.compile(
                r"'((?:\\.|[^'])+)'\s*:\s*"
                r"(?:'((?:\\.|[^'])*)'|\"((?:\\.|[^\"])*)\")"
            )

            def unescape(value: str) -> str:
                return value.replace("\\'", "'").replace("\\\\", "\\")

            return {
                unescape(match.group(1)): unescape(
                    match.group(2)
                    if match.group(2) is not None
                    else match.group(3)
                )
                for match in entry.finditer(body2)
            }

        return {lang: grab(f"_{lang}") for lang in LANGS}

    # Fallback: legacy inline tables in editor_l10n.dart
    src = (ROOT / "lib/l10n/editor_l10n.dart").read_text()
    return {
        "en": extract_map(src, "_en"),
        "zh": extract_map(src, "_zh"),
    }


def phrase_to_bank(en_ui: dict[str, str], phrases: dict[str, str]) -> dict[str, str]:
    miss = [v for v in en_ui.values() if v not in phrases]
    if miss:
        raise ValueError(f"missing phrases: {miss[:8]}")
    return {k: phrases[v] for k, v in en_ui.items()}


def main() -> None:
    existing = load_existing()
    en_all = existing["en"]
    zh_all = existing["zh"]
    en_ui = {k: v for k, v in en_all.items() if not k.startswith("st_")}
    en_st = {k: v for k, v in en_all.items() if k.startswith("st_")}
    zh_ui = {k: zh_all[k] for k in en_ui if k in zh_all}
    en_ui.update(
        selectEdges=SELECT_EDGES["en"],
        selectVertices=SELECT_VERTICES["en"],
    )
    zh_ui.update(
        selectEdges=SELECT_EDGES["zh"],
        selectVertices=SELECT_VERTICES["zh"],
    )
    zh_st = {k: v for k, v in zh_all.items() if k.startswith("st_")}
    if len(zh_ui) != len(en_ui):
        raise SystemExit(f"zh UI incomplete: {len(zh_ui)} vs {len(en_ui)}")

    existing_banks: dict[str, dict[str, str]] = {
        lang: {k: v for k, v in table.items() if not k.startswith("st_")}
        for lang, table in existing.items()
    }
    banks: dict[str, dict[str, str]] = {"en": en_ui, "zh": zh_ui}

    if BANKS_JSON.exists():
        cached = json.loads(BANKS_JSON.read_text())
        for lang, bank in cached.items():
            if lang in ("en", "zh"):
                continue
            if all(k in bank for k in en_ui):
                banks[lang] = {k: bank[k] for k in en_ui}

    if PHRASE_JSON.exists():
        phrases = json.loads(PHRASE_JSON.read_text())
        for lang, pm in phrases.items():
            if lang in banks:
                continue
            banks[lang] = phrase_to_bank(en_ui, pm)

    vocabs = json.loads(VOCABS.read_text()) if VOCABS.exists() else {}
    for lang, vocab in vocabs.items():
        # Vocabs override phrase-map adaptations (higher quality).
        # Merge onto existing bank so NEW2 keys already present are kept
        # when from_vocab is incomplete.
        expanded = from_vocab(vocab)
        base = banks.get(lang, existing_banks.get(lang, {}))
        banks[lang] = {**base, **{k: v for k, v in expanded.items() if v is not None}}

    # Curated full UI banks (tool/ui_banks/<lang>.json) win over cache/vocabs.
    if UI_BANKS_DIR.is_dir():
        for path in sorted(UI_BANKS_DIR.glob("*.json")):
            lang = path.stem
            bank = json.loads(path.read_text())
            curated = {k: bank[k] for k in en_ui if k in bank}
            if curated:
                base = banks.get(lang, existing_banks.get(lang, {}))
                banks[lang] = {**base, **curated}
                print(f"ui_bank {lang}: {len(curated)} keys")

    for lang, bank in existing_banks.items():
        banks.setdefault(lang, bank)

    for lang, value in COLOR_BY_LAYER.items():
        if lang in banks:
            banks[lang]["colorByLayer"] = value

    for lang, value in TOOL_PAN.items():
        if lang in banks:
            banks[lang]["toolPan"] = value

    for lang, value in SELECT_EDGES.items():
        if lang in banks:
            banks[lang]["selectEdges"] = value

    for lang, value in SELECT_VERTICES.items():
        if lang in banks:
            banks[lang]["selectVertices"] = value

    missing = [l for l in LANGS if l not in banks]
    if missing:
        raise SystemExit(f"Missing UI banks for: {missing}")
    incomplete = {
        lang: [key for key in en_ui if key not in banks[lang]]
        for lang in LANGS
        if any(key not in banks[lang] for key in en_ui)
    }
    if incomplete:
        lang, keys = next(iter(incomplete.items()))
        raise SystemExit(f"{lang} UI incomplete: {keys[:8]}")

    for lang in LANGS:
        if lang == "en":
            continue
        if banks[lang]["undo"] == en_ui["undo"]:
            raise SystemExit(f"{lang}.undo still English")
        if banks[lang]["cut"] == en_ui["cut"]:
            raise SystemExit(f"{lang}.cut still English")

    name_maps: dict[str, dict[str, str]] = {}
    if STENCIL_JSON.exists():
        name_maps.update(json.loads(STENCIL_JSON.read_text()))
    # Prefer curated maps under tool/stencil_maps/
    name_maps.update(STENCIL_MAPS)
    # Always include zh from source tables
    name_maps["zh"] = {
        eng: zh_st[k] for k, eng in en_st.items() if k in zh_st
    }

    tables: dict[str, dict[str, str]] = {}
    for lang in LANGS:
        ui = banks[lang]
        st = translate_stencils(lang, en_st, zh_st, name_maps)
        tables[lang] = {**ui, **st}
        print(f"{lang}: {len(tables[lang])} (ui={len(ui)} st={len(st)})")

    BANKS_JSON.write_text(json.dumps(banks, ensure_ascii=False))

    parts = [
        "// GENERATED by tool/finish_editor_l10n.py — do not edit by hand.",
        "",
        "/// Editor string tables keyed by BCP-47 language code.",
        "const Map<String, Map<String, String>> kEditorL10nTables =",
        "    <String, Map<String, String>>{",
    ]
    for lang in LANGS:
        parts.append(f"  '{lang}': _{lang},")
    parts.append("};")
    parts.append("")
    for lang in LANGS:
        parts.append(dart_map(f"_{lang}", tables[lang]))
        parts.append("")
    MAPS.write_text("\n".join(parts))
    print("wrote", MAPS, MAPS.stat().st_size)


if __name__ == "__main__":
    main()
