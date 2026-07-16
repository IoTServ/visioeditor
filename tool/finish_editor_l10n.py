#!/usr/bin/env python3
"""Regenerate lib/l10n/editor_l10n_maps.dart for all AppLocalizations languages.

Sources (in priority order per language):
  1. /tmp/all_banks.json  — key→string UI banks (cache)
  2. /tmp/phrase_maps_v4.json — English-phrase→translation maps
  3. tool/editor_vocabs.json — compact vocabs expanded via from_vocab()
     (merged onto existing bank so incomplete vocabs keep prior NEW keys)
  4. tool/ui_banks/<lang>.json — curated full UI banks (highest priority)
  5. en/zh extracted from existing editor_l10n_maps.dart

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


def load_en_zh() -> tuple[dict[str, str], dict[str, str]]:
    """Load en/zh full tables (UI + stencils) from generated maps if present."""
    if MAPS.exists():
        text = MAPS.read_text()
        # Maps use top-level const _en / _zh
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
            return dict(re.findall(r"'([^']+)':\s*'([^']*)'", body2))

        return grab("_en"), grab("_zh")

    # Fallback: legacy inline tables in editor_l10n.dart
    src = (ROOT / "lib/l10n/editor_l10n.dart").read_text()
    return extract_map(src, "_en"), extract_map(src, "_zh")


def phrase_to_bank(en_ui: dict[str, str], phrases: dict[str, str]) -> dict[str, str]:
    miss = [v for v in en_ui.values() if v not in phrases]
    if miss:
        raise ValueError(f"missing phrases: {miss[:8]}")
    return {k: phrases[v] for k, v in en_ui.items()}


def main() -> None:
    en_all, zh_all = load_en_zh()
    en_ui = {k: v for k, v in en_all.items() if not k.startswith("st_")}
    en_st = {k: v for k, v in en_all.items() if k.startswith("st_")}
    zh_ui = {k: zh_all[k] for k in en_ui if k in zh_all}
    zh_st = {k: v for k, v in zh_all.items() if k.startswith("st_")}
    if len(zh_ui) != len(en_ui):
        raise SystemExit(f"zh UI incomplete: {len(zh_ui)} vs {len(en_ui)}")

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
        base = banks.get(lang, {})
        banks[lang] = {**base, **{k: v for k, v in expanded.items() if v is not None}}

    # Curated full UI banks (tool/ui_banks/<lang>.json) win over cache/vocabs.
    if UI_BANKS_DIR.is_dir():
        for path in sorted(UI_BANKS_DIR.glob("*.json")):
            lang = path.stem
            bank = json.loads(path.read_text())
            if all(k in bank for k in en_ui):
                banks[lang] = {k: bank[k] for k in en_ui}
                print(f"ui_bank {lang}: {len(en_ui)} keys")

    missing = [l for l in LANGS if l not in banks]
    if missing:
        raise SystemExit(f"Missing UI banks for: {missing}")

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
