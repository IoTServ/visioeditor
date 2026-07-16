#!/usr/bin/env python3
"""Generate / improve tool/stencil_maps/<lang>.json for EditorL10n shape names.

Strategy:
  1. Start from an existing sibling map when helpful (ca←es, fil/ms←id, bg←ru).
  2. Apply multi-word phrase replacements, then single-word replacements.
  3. Keep English for acronyms / proper tokens (UML leftovers like X, And).

Run: python3 tool/gen_stencil_maps.py
Then: python3 tool/finish_editor_l10n.py
"""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAPS_DART = ROOT / "lib/l10n/editor_l10n_maps.dart"
OUT_DIR = Path(__file__).with_name("stencil_maps")

# Languages that previously had no stencil maps (plus gap-fill targets).
TARGET_LANGS = [
    "sv", "cs", "da", "ca", "fil", "sw", "ro", "el", "hu", "ms", "fi", "nb",
    "sk", "bn", "fa", "bg", "hr",
]


def load_en_names() -> list[str]:
    text = MAPS_DART.read_text()
    m = re.search(
        r"const Map<String, String> _en = <String, String>\{(.*?)\n\};",
        text,
        re.S,
    )
    if not m:
        raise SystemExit("cannot parse _en")
    en = {
        a.replace("\\'", "'"): b.replace("\\'", "'")
        for a, b in (
            x.groups()
            for x in re.finditer(
                r"'((?:\\'|[^'])*)':\s*'((?:\\'|[^'])*)'", m.group(1)
            )
        )
    }
    return sorted(v for k, v in en.items() if k.startswith("st_"))


def load_map(lang: str) -> dict[str, str]:
    p = OUT_DIR / f"{lang}.json"
    if p.exists():
        return json.loads(p.read_text())
    return {}


def title_preserve(src: str, repl: str) -> str:
    if src.isupper():
        return repl.upper()
    if src[:1].isupper():
        return repl[:1].upper() + repl[1:]
    return repl


def apply_lexicon(
    name: str,
    phrases: dict[str, str],
    words: dict[str, str],
) -> str:
    """Replace longest phrases first, then whole words (case-insensitive).

    Phrase/word matches are bounded so short keys like \"Or\" / \"And\" cannot
    corrupt longer translations (e.g. Suorakulmio).
    """
    # Exact phrase hit — return immediately (no further mangling).
    for eng, loc in phrases.items():
        if eng.lower() == name.lower():
            return loc

    out = name
    for eng, loc in sorted(phrases.items(), key=lambda kv: -len(kv[0])):
        if not eng:
            continue
        pat = re.compile(
            rf"(?<![A-Za-zÀ-ÖØ-öø-ÿ]){re.escape(eng)}(?![A-Za-zÀ-ÖØ-öø-ÿ])",
            re.I,
        )

        def _sub(m: re.Match[str], loc: str = loc) -> str:
            return title_preserve(m.group(0), loc)

        out = pat.sub(_sub, out)

    original_tokens = {w.lower() for w in re.findall(r"[A-Za-z]+", name)}

    def word_sub(m: re.Match[str]) -> str:
        w = m.group(0)
        key = w.lower()
        # Only rewrite tokens that existed in the English source name.
        if key in original_tokens and key in words:
            return title_preserve(w, words[key])
        return w

    out = re.sub(r"[A-Za-z]+", word_sub, out)
    out = re.sub(r"\s+", " ", out).strip()
    return out


def translate_all(
    names: list[str],
    phrases: dict[str, str],
    words: dict[str, str],
    base: dict[str, str] | None = None,
) -> dict[str, str]:
    out: dict[str, str] = {}
    for n in names:
        seed = (base or {}).get(n, n)
        # If seed already localized and differs from English, keep unless still English words we can improve
        if seed != n:
            out[n] = seed
            continue
        out[n] = apply_lexicon(n, phrases, words)
    return out


# --- Lexicons -----------------------------------------------------------------

# Shared geometry / UI words reused across Germanic langs with per-lang overrides.
COMMON_PHRASES = {
    "Rounded Rectangle": None,  # filled per lang
}

SV_PHRASES = {
    "Rounded Rectangle": "Rundad rektangel",
    "Acute Triangle": "Spetsig triangel",
    "Right Triangle": "Rätvinklig triangel",
    "Isosceles Triangle": "Likbent triangel",
    "Double Arrow": "Dubbelpil",
    "Bend Arrow": "Böjd pil",
    "Bend Double Arrow": "Böjd dubbelpil",
    "Arrow Down": "Pil ned",
    "Arrow Up": "Pil upp",
    "Arrow Left": "Pil vänster",
    "Arrow Right": "Pil höger",
    "Actor Lifeline": "Aktörs livlina",
    "Boundary Lifeline": "Gräns livlina",
    "Control Lifeline": "Kontroll livlina",
    "Entity Lifeline": "Entitets livlina",
    "Activation Bar": "Aktiveringsfält",
    "Associative Entity": "Associativ entitet",
    "Weak Key Attribute": "Svag nyckelattribut",
    "Multi-valued Attribute": "Flervärt attribut",
    "Identifying Relationship": "Identifierande relation",
    "Non-identifying Relationship": "Icke-identifierande relation",
    "Data Object": "Dataobjekt",
    "Data Store": "Datalager",
    "Data Storage": "Datalagring",
    "Business Rule Task": "Affärsregeluppgift",
    "Manual Task": "Manuell uppgift",
    "User Task": "Användaruppgift",
    "Service Task": "Tjänsteuppgift",
    "Script Task": "Skriptuppgift",
    "Send Task": "Sändningsuppgift",
    "Receive Task": "Mottagaruppgift",
    "Parallel Gateway": "Parallell gateway",
    "Exclusive Gateway": "Exklusiv gateway",
    "Inclusive Gateway": "Inklusiv gateway",
    "Event Gateway": "Händelsegateway",
    "Complex Gateway": "Komplex gateway",
    "Start Event": "Starthändelse",
    "End Event": "Sluthändelse",
    "Intermediate Event": "Mellanhändelse",
    "Message Start": "Meddelandestart",
    "Message Intermediate": "Meddelandemellan",
    "Timer Start": "Timerstart",
    "Timer Intermediate": "Timermellan",
    "Error Intermediate": "Fel mellan",
    "Cancel Intermediate": "Avbryt mellan",
    "Compensation Intermediate": "Kompensation mellan",
    "Signal Intermediate": "Signal mellan",
    "Link Intermediate": "Länk mellan",
    "Multiple Intermediate": "Multipel mellan",
    "Parallel Multiple Intermediate": "Parallell multipel mellan",
    "Escalation Intermediate": "Eskalering mellan",
    "Cloud Callout": "Molnbubbla",
    "Line Callout": "Linjebubbla",
    "Rectangular Callout": "Rektangulär bubbla",
    "Oval Callout": "Oval bubbla",
    "Callout Arrow": "Bubbelpil",
    "Callout Double Arrow": "Bubbel dubbelpil",
    "Callout Quad Arrow": "Bubbel fyrpil",
    "Curly Bracket": "Klammerparentes",
    "Double Bracket": "Dubbel parentes",
    "Horizontal Scroll": "Vågrät rullning",
    "Vertical Scroll": "Lodrät rullning",
    "Document": "Dokument",
    "Folder": "Mapp",
    "Process": "Process",
    "Predefined Process": "Fördefinierad process",
    "Internal Storage": "Intern lagring",
    "Manual Input": "Manuell inmatning",
    "Card": "Kort",
    "Punched Tape": "Hålad tejp",
    "Punched Card": "Hålkort",
    "Magnetic Disk": "Magnetskiva",
    "Direct Data": "Direkt data",
    "Stored Data": "Lagrad data",
    "Sequential Data": "Sekventiell data",
    "Display": "Skärm",
    "Delay": "Fördröjning",
    "Or": "Eller",
    "Summing Junction": "Summeringsknut",
    "Collate": "Sammanställ",
    "Sort": "Sortera",
    "Extract": "Extrahera",
    "Merge": "Sammanfoga",
    "Offline Storage": "Offlinelagring",
    "Online Storage": "Onlinelagring",
    "Paper Tape": "Pappersband",
    "Circle": "Cirkel",
    "Ellipse": "Ellips",
    "Rectangle": "Rektangel",
    "Square": "Kvadrat",
    "Diamond": "Romb",
    "Hexagon": "Hexagon",
    "Octagon": "Oktagon",
    "Pentagon": "Pentagon",
    "Trapezoid": "Trapets",
    "Parallelogram": "Parallellogram",
    "Cylinder": "Cylinder",
    "Cube": "Kub",
    "Cloud": "Moln",
    "Heart": "Hjärta",
    "Moon": "Måne",
    "Sun": "Sol",
    "Lightning": "Blixt",
    "Cross": "Kors",
    "Plus": "Plus",
    "Minus": "Minus",
    "X": "X",
    "Zigzag": "Sicksack",
    "Wave": "Våg",
    "Arc": "Båge",
    "Block Arc": "Blockbåge",
    "Donut": "Ring",
    "Pie": "Cirkelsektor",
    "Chord": "Korda",
    "Teardrop": "Tårdroppe",
    "Frame": "Ram",
    "L-Shape": "L-form",
    "U-Turn Arrow": "U-svängspil",
    "Circular Arrow": "Cirkulär pil",
    "Notched Right Arrow": "Urgröpt högerpil",
    "Striped Right Arrow": "Randig högerpil",
    "Quad Arrow": "Fyrpil",
    "Left Right Arrow": "Vänster-högerpil",
    "Up Down Arrow": "Upp-nedpil",
    "Left Up Arrow": "Vänster-uppil",
    "Bent Up Arrow": "Uppböjd pil",
    "Chevron": "Chevron",
    "Pentagon Arrow": "Pentagonpil",
    "Home Plate": "Hemplatta",
    "Plaque": "Plakett",
    "Bevel": "Fas",
    "Can": "Burk",
    "Cube Isometric": "Isometrisk kub",
    "Isometric Corner 1": "Isometriskt hörn 1",
    "Isometric Corner 2": "Isometriskt hörn 2",
    "Table": "Tabell",
    "Matrix": "Matris",
    "Container": "Behållare",
    "Pool": "Pool",
    "Lane": "Bana",
    "Annotation": "Anteckning",
    "Text Box": "Textruta",
    "Label": "Etikett",
    "Note": "Anteckning",
    "Sticky Note": "Klisterlapp",
    "Banner": "Banderoll",
    "Button": "Knapp",
    "Button (shaded)": "Knapp (skuggad)",
    "Smiley Face": "Smileygubbe",
    "No Smiling Face": "Ingen smileygubbe",
    "Sad Smiley": "Ledsen smiley",
    "Star": "Stjärna",
    "4 Point Star": "4-uddig stjärna",
    "6 Point Star": "6-uddig stjärna",
    "8 Point Star": "8-uddig stjärna",
    "Explosion 1": "Explosion 1",
    "Explosion 2": "Explosion 2",
    "Flowchart": "Flödesschema",
    "Terminator": "Avslut",
    "Decision": "Beslut",
    "Preparation": "Förberedelse",
    "Manual Operation": "Manuell åtgärd",
    "Connector": "Koppling",
    "Off-page Connector": "Sidkoppling",
    "Or Gate": "ELLER-grind",
    "And Gate": "OCH-grind",
    "Database": "Databas",
    "Class": "Klass",
    "Interface": "Gränssnitt",
    "Package": "Paket",
    "Component": "Komponent",
    "Node": "Nod",
    "Use Case": "Användningsfall",
    "Actor": "Aktör",
    "Lifeline": "Livlina",
    "Object": "Objekt",
    "State": "Tillstånd",
    "Initial State": "Initialtillstånd",
    "Final State": "Sluttillstånd",
    "Fork": "Förgrening",
    "Join": "Sammanslagning",
    "Synchronization": "Synkronisering",
    "Note Box": "Anteckningsruta",
    "Page": "Sida",
    "Title": "Titel",
    "Autosize Title": "Autosize-titel",
    "Grid": "Rutnät",
    "Diagonal Stripe": "Diagonal rand",
}
SV_WORDS = {
    "arrow": "pil", "rectangle": "rektangel", "ellipse": "ellips", "circle": "cirkel",
    "triangle": "triangel", "square": "kvadrat", "star": "stjärna", "cloud": "moln",
    "callout": "bubbla", "double": "dubbel", "vertical": "lodrät", "horizontal": "vågrät",
    "rounded": "rundad", "diagonal": "diagonal", "fill": "fyllning", "with": "med",
    "task": "uppgift", "gateway": "gateway", "event": "händelse", "start": "start",
    "end": "slut", "data": "data", "entity": "entitet", "attribute": "attribut",
    "lifeline": "livlina", "actor": "aktör", "message": "meddelande", "process": "process",
    "document": "dokument", "line": "linje", "left": "vänster", "right": "höger",
    "up": "upp", "down": "ned", "frame": "ram", "list": "lista", "manual": "manuell",
    "page": "sida", "table": "tabell", "container": "behållare", "lane": "bana",
    "pool": "pool", "key": "nyckel", "label": "etikett", "loop": "loop",
    "multiple": "multipel", "signal": "signal", "parallel": "parallell", "partial": "partiell",
    "grid": "rutnät", "cross": "kors", "bar": "fält", "object": "objekt",
    "storage": "lagring", "cylinder": "cylinder", "cube": "kub", "button": "knapp",
    "card": "kort", "note": "anteckning", "class": "klass", "interface": "gränssnitt",
    "package": "paket", "component": "komponent", "node": "nod", "state": "tillstånd",
    "decision": "beslut", "database": "databas", "folder": "mapp", "wave": "våg",
    "heart": "hjärta", "moon": "måne", "sun": "sol", "plus": "plus", "minus": "minus",
    "hexagon": "hexagon", "octagon": "oktagon", "pentagon": "pentagon", "diamond": "romb",
    "trapezoid": "trapets", "parallelogram": "parallellogram", "arc": "båge",
    "chord": "korda", "pie": "sektor", "donut": "ring", "bevel": "fas", "plaque": "plakett",
    "chevron": "chevron", "banner": "banderoll", "annotation": "anteckning",
    "connector": "koppling", "terminator": "avslut", "preparation": "förberedelse",
    "collate": "sammanställ", "sort": "sortera", "extract": "extrahera", "merge": "sammanfoga",
    "delay": "fördröjning", "display": "skärm", "or": "eller", "and": "och",
    "intermediate": "mellan", "compensation": "kompensation", "boundary": "gräns",
    "control": "kontroll", "rule": "regel", "business": "affärs", "user": "användar",
    "service": "tjänst", "script": "skript", "send": "sänd", "receive": "mottag",
    "exclusive": "exklusiv", "inclusive": "inklusiv", "complex": "komplex",
    "timer": "timer", "error": "fel", "cancel": "avbryt", "link": "länk",
    "escalation": "eskalering", "text": "text", "box": "ruta", "smiley": "smiley",
    "face": "ansikte", "point": "uddig", "isometric": "isometrisk", "corner": "hörn",
    "striped": "randig", "notched": "urgröpt", "circular": "cirkulär", "bent": "böjd",
    "home": "hem", "plate": "platta", "can": "burk", "matrix": "matris",
    "title": "titel", "autosize": "autosize", "explosion": "explosion",
    "flowchart": "flödesschema", "operation": "åtgärd", "input": "inmatning",
    "internal": "intern", "offline": "offline", "online": "online", "paper": "pappers",
    "tape": "band", "punched": "hålad", "magnetic": "magnet", "disk": "skiva",
    "direct": "direkt", "stored": "lagrad", "sequential": "sekventiell",
    "summing": "summerings", "junction": "knut", "gate": "grind",
    "use": "användnings", "case": "fall", "initial": "initial", "final": "slut",
    "fork": "förgrening", "join": "sammanslagning", "synchronization": "synkronisering",
    "sticky": "klister", "sad": "ledsen", "no": "ingen", "smiling": "leende",
    "predefined": "fördefinierad", "off": "av", "page": "sida", "shaded": "skuggad",
    "weak": "svag", "identifying": "identifierande", "non": "icke",
    "valued": "värt", "multi": "fler", "associative": "associativ",
    "activation": "aktiverings", "quad": "fyr", "curly": "klammer", "bracket": "parentes",
    "scroll": "rullning", "block": "block", "lightning": "blixt", "teardrop": "tårdroppe",
    "shape": "form", "turn": "sväng", "divider": "delare", "backbone": "ryggrad",
    "crossbar": "tvärstång", "relationship": "relation", "ref": "ref", "oval": "oval",
    "slender": "smal", "tailed": "svansad", "bang": "bang", "ad": "ad", "hoc": "hoc",
}


def clone_lex(phrases: dict[str, str], words: dict[str, str], **overrides: str) -> tuple[dict[str, str], dict[str, str]]:
    p = dict(phrases)
    w = dict(words)
    # overrides may target phrase or word keys
    for k, v in overrides.items():
        key = k.replace("_", " ")
        if key in p or " " in key or key[:1].isupper():
            p[key] = v
        else:
            w[k.lower()] = v
    return p, w


# Danish — close to Norwegian Bokmål with Danish spelling
DA_PHRASES = {
    **{k: v for k, v in SV_PHRASES.items()},  # start then override
}
# Override Swedish-specific → Danish
DA_OVERRIDES = {
    "Rounded Rectangle": "Afrundet rektangel",
    "Arrow Down": "Pil ned",
    "Arrow Up": "Pil op",
    "Arrow Left": "Pil venstre",
    "Arrow Right": "Pil højre",
    "Actor Lifeline": "Aktør livlinje",
    "Cloud": "Sky",
    "Cloud Callout": "Skyboble",
    "Circle": "Cirkel",
    "Document": "Dokument",
    "Folder": "Mappe",
    "Decision": "Beslutning",
    "Database": "Database",
    "Actor": "Aktør",
    "Class": "Klasse",
    "Table": "Tabel",
    "Grid": "Gitter",
    "Heart": "Hjerte",
    "Moon": "Måne",
    "Sun": "Sol",
    "Wave": "Bølge",
    "Star": "Stjerne",
    "4 Point Star": "4-takket stjerne",
    "6 Point Star": "6-takket stjerne",
    "8 Point Star": "8-takket stjerne",
    "Text Box": "Tekstboks",
    "Sticky Note": "Selvklæbende note",
    "User Task": "Brugeropgave",
    "Manual Task": "Manuel opgave",
    "Start Event": "Starthændelse",
    "End Event": "Sluthændelse",
    "Horizontal Scroll": "Vandret rulle",
    "Vertical Scroll": "Lodret rulle",
}
for k, v in DA_OVERRIDES.items():
    DA_PHRASES[k] = v
DA_WORDS = {
    **SV_WORDS,
    "arrow": "pil", "cloud": "sky", "folder": "mappe", "heart": "hjerte",
    "wave": "bølge", "star": "stjerne", "horizontal": "vandret", "vertical": "lodret",
    "rounded": "afrundet", "up": "op", "down": "ned", "left": "venstre", "right": "højre",
    "table": "tabel", "grid": "gitter", "user": "bruger", "manual": "manuel",
    "box": "boks", "note": "note", "decision": "beslutning", "actor": "aktør",
    "lifeline": "livlinje", "callout": "boble", "task": "opgave",
}

NB_PHRASES = dict(DA_PHRASES)
NB_OVERRIDES = {
    "Rounded Rectangle": "Avrundet rektangel",
    "Arrow Up": "Pil opp",
    "Cloud": "Sky",
    "Folder": "Mappe",
    "Heart": "Hjerte",
    "Wave": "Bølge",
    "Star": "Stjerne",
    "4 Point Star": "4-spiss stjerne",
    "6 Point Star": "6-spiss stjerne",
    "8 Point Star": "8-spiss stjerne",
    "Text Box": "Tekstboks",
    "Sticky Note": "Limlapp",
    "User Task": "Brukeroppgave",
    "Horizontal Scroll": "Vannrett rulling",
    "Vertical Scroll": "Loddrett rulling",
    "Decision": "Beslutning",
    "Table": "Tabell",
    "Grid": "Rutenett",
}
for k, v in NB_OVERRIDES.items():
    NB_PHRASES[k] = v
NB_WORDS = {
    **DA_WORDS,
    "rounded": "avrundet", "up": "opp", "horizontal": "vannrett", "vertical": "loddrett",
    "table": "tabell", "grid": "rutenett", "user": "bruker", "star": "stjerne",
    "wave": "bølge", "heart": "hjerte", "folder": "mappe", "cloud": "sky",
}

FI_PHRASES = {
    "Rounded Rectangle": "Pyöristetty suorakulmio",
    "Circle": "Ympyrä",
    "Ellipse": "Ellipsi",
    "Rectangle": "Suorakulmio",
    "Square": "Neliö",
    "Diamond": "Vinoneliö",
    "Triangle": "Kolmio",
    "Acute Triangle": "Teräväkulmainen kolmio",
    "Right Triangle": "Suorakulmainen kolmio",
    "Arrow Down": "Nuoli alas",
    "Arrow Up": "Nuoli ylös",
    "Arrow Left": "Nuoli vasemmalle",
    "Arrow Right": "Nuoli oikealle",
    "Double Arrow": "Kaksoisnuoli",
    "Cloud": "Pilvi",
    "Cloud Callout": "Pilvipuhekupla",
    "Document": "Asiakirja",
    "Folder": "Kansio",
    "Process": "Prosessi",
    "Decision": "Päätös",
    "Database": "Tietokanta",
    "Actor": "Toimija",
    "Class": "Luokka",
    "Table": "Taulukko",
    "Grid": "Ruudukko",
    "Heart": "Sydän",
    "Moon": "Kuu",
    "Sun": "Aurinko",
    "Star": "Tähti",
    "4 Point Star": "4-sakarainen tähti",
    "6 Point Star": "6-sakarainen tähti",
    "8 Point Star": "8-sakarainen tähti",
    "Text Box": "Tekstilaatikko",
    "Note": "Muistiinpano",
    "Sticky Note": "Tarralappu",
    "Button": "Painike",
    "Cylinder": "Sylinteri",
    "Cube": "Kuutio",
    "Hexagon": "Kuusikulmio",
    "Octagon": "Kahdeksankulmio",
    "Pentagon": "Viisikulmio",
    "Parallelogram": "Suunnikas",
    "Trapezoid": "Puolisuunnikas",
    "Wave": "Aalto",
    "Cross": "Risti",
    "Plus": "Plus",
    "Minus": "Miinus",
    "Donut": "Rengas",
    "Frame": "Kehys",
    "Container": "Säilö",
    "Pool": "Allas",
    "Lane": "Kaista",
    "Annotation": "Huomautus",
    "Connector": "Yhdistäjä",
    "Terminator": "Pääte",
    "Start Event": "Alkutapahtuma",
    "End Event": "Lopputapahtuma",
    "User Task": "Käyttäjätehtävä",
    "Manual Task": "Manuaalinen tehtävä",
    "Service Task": "Palvelutehtävä",
    "Data Object": "Dataobjekti",
    "Data Store": "Datavarasto",
    "Parallel Gateway": "Rinnakkainen yhdyskäytävä",
    "Exclusive Gateway": "Eksklusiivinen yhdyskäytävä",
    "Use Case": "Käyttötapaus",
    "Lifeline": "Elämänviiva",
    "Interface": "Rajapinta",
    "Package": "Paketti",
    "Component": "Komponentti",
    "State": "Tila",
    "Initial State": "Alkutila",
    "Final State": "Lopputila",
    "Banner": "Banneri",
    "Card": "Kortti",
    "Label": "Nimike",
    "Page": "Sivu",
    "Title": "Otsikko",
    "Display": "Näyttö",
    "Delay": "Viive",
    "Merge": "Yhdistä",
    "Sort": "Lajittele",
    "Extract": "Poimi",
    "Collate": "Koosta",
    "Or": "Tai",
    "And": "Ja",
    "Lightning": "Salama",
    "Teardrop": "Kyynel",
    "Arc": "Kaari",
    "Pie": "Piirakka",
    "Chord": "Jänne",
    "Bevel": "Viiste",
    "Plaque": "Kilpi",
    "Can": "Tölkki",
    "Matrix": "Matriisi",
    "Chevron": "Chevron",
    "Smiley Face": "Hymiö",
    "Preparation": "Valmistelu",
    "Manual Operation": "Manuaalinen toiminto",
    "Manual Input": "Manuaalinen syöttö",
    "Predefined Process": "Valmisprosessi",
    "Internal Storage": "Sisäinen tallennus",
    "Off-page Connector": "Sivun ulkopuolinen yhdistäjä",
    "Horizontal Scroll": "Vaakavieritys",
    "Vertical Scroll": "Pystyvieritys",
    "Callout Arrow": "Puhekuplanuoli",
    "Rectangular Callout": "Suorakulmainen puhekupla",
    "Oval Callout": "Soikea puhekupla",
    "Line Callout": "Viivapuhekupla",
    "Actor Lifeline": "Toimijan elämänviiva",
    "Activation Bar": "Aktivointipalkki",
    "Associative Entity": "Liitosentiteetti",
    "Weak Key Attribute": "Heikko avainattribuutti",
    "Business Rule Task": "Liiketoimintasääntötehtävä",
    "Script Task": "Skriptitehtävä",
    "Send Task": "Lähetystehtävä",
    "Receive Task": "Vastaanottotehtävä",
    "Inclusive Gateway": "Inklusiivinen yhdyskäytävä",
    "Event Gateway": "Tapahtumayhdyskäytävä",
    "Complex Gateway": "Monimutkainen yhdyskäytävä",
    "Message Start": "Viestialku",
    "Timer Start": "Ajastinalku",
    "Database": "Tietokanta",
    "Flowchart": "Vuokaavio",
    "Note Box": "Muistiinpanolaatikko",
    "Bang": "Bang",
    "Zigzag": "Siksak",
    "X": "X",
}
FI_WORDS = {
    "arrow": "nuoli", "rectangle": "suorakulmio", "ellipse": "ellipsi", "circle": "ympyrä",
    "triangle": "kolmio", "square": "neliö", "star": "tähti", "cloud": "pilvi",
    "callout": "puhekupla", "double": "kaksois", "vertical": "pysty", "horizontal": "vaaka",
    "rounded": "pyöristetty", "task": "tehtävä", "gateway": "yhdyskäytävä", "event": "tapahtuma",
    "data": "data", "entity": "entiteetti", "attribute": "attribuutti", "lifeline": "elämänviiva",
    "actor": "toimija", "message": "viesti", "process": "prosessi", "document": "asiakirja",
    "line": "viiva", "left": "vasen", "right": "oikea", "up": "ylös", "down": "alas",
    "frame": "kehys", "list": "luettelo", "manual": "manuaalinen", "page": "sivu",
    "table": "taulukko", "container": "säilö", "lane": "kaista", "pool": "allas",
    "key": "avain", "label": "nimike", "signal": "signaali", "parallel": "rinnakkainen",
    "grid": "ruudukko", "cross": "risti", "object": "objekti", "storage": "tallennus",
    "cylinder": "sylinteri", "cube": "kuutio", "button": "painike", "card": "kortti",
    "note": "muistiinpano", "class": "luokka", "interface": "rajapinta", "package": "paketti",
    "component": "komponentti", "node": "solmu", "state": "tila", "decision": "päätös",
    "database": "tietokanta", "folder": "kansio", "wave": "aalto", "heart": "sydän",
    "moon": "kuu", "sun": "aurinko", "hexagon": "kuusikulmio", "octagon": "kahdeksankulmio",
    "pentagon": "viisikulmio", "diamond": "vinoneliö", "arc": "kaari", "text": "teksti",
    "box": "laatikko", "user": "käyttäjä", "service": "palvelu", "script": "skripti",
    "send": "lähetys", "receive": "vastaanotto", "timer": "ajastin", "error": "virhe",
    "cancel": "peruuta", "link": "linkki", "start": "alku", "end": "loppu",
    "intermediate": "väli", "fill": "täyttö", "with": "jossa", "diagonal": "viisto",
    "or": "tai", "and": "ja", "plus": "plus", "minus": "miinus", "display": "näyttö",
    "delay": "viive", "merge": "yhdistä", "sort": "lajittele", "title": "otsikko",
    "annotation": "huomautus", "connector": "yhdistäjä", "terminator": "pääte",
}


# Czech
CS_PHRASES = {
    "Rounded Rectangle": "Zaoblený obdélník",
    "Circle": "Kruh",
    "Ellipse": "Elipsa",
    "Rectangle": "Obdélník",
    "Square": "Čtverec",
    "Diamond": "Kosočtverec",
    "Triangle": "Trojúhelník",
    "Acute Triangle": "Ostrouhelný trojúhelník",
    "Right Triangle": "Pravoúhlý trojúhelník",
    "Arrow Down": "Šipka dolů",
    "Arrow Up": "Šipka nahoru",
    "Arrow Left": "Šipka doleva",
    "Arrow Right": "Šipka doprava",
    "Double Arrow": "Dvojitá šipka",
    "Cloud": "Mrak",
    "Cloud Callout": "Mraková bublina",
    "Document": "Dokument",
    "Folder": "Složka",
    "Process": "Proces",
    "Decision": "Rozhodnutí",
    "Database": "Databáze",
    "Actor": "Aktér",
    "Class": "Třída",
    "Table": "Tabulka",
    "Grid": "Mřížka",
    "Heart": "Srdce",
    "Moon": "Měsíc",
    "Sun": "Slunce",
    "Star": "Hvězda",
    "4 Point Star": "4cípá hvězda",
    "6 Point Star": "6cípá hvězda",
    "8 Point Star": "8cípá hvězda",
    "Text Box": "Textové pole",
    "Note": "Poznámka",
    "Sticky Note": "Lepící lísteček",
    "Button": "Tlačítko",
    "Cylinder": "Válec",
    "Cube": "Krychle",
    "Hexagon": "Šestiúhelník",
    "Octagon": "Osmiúhelník",
    "Pentagon": "Pětiúhelník",
    "Parallelogram": "Rovnoběžník",
    "Trapezoid": "Lichoběžník",
    "Wave": "Vlna",
    "Cross": "Kříž",
    "Donut": "Prstenec",
    "Frame": "Rám",
    "Container": "Kontejner",
    "Pool": "Bazén",
    "Lane": "Dráha",
    "Annotation": "Anotace",
    "Connector": "Spojka",
    "Terminator": "Ukončení",
    "Start Event": "Počáteční událost",
    "End Event": "Koncová událost",
    "User Task": "Uživatelský úkol",
    "Manual Task": "Ruční úkol",
    "Service Task": "Servisní úkol",
    "Data Object": "Datový objekt",
    "Data Store": "Datové úložiště",
    "Parallel Gateway": "Paralelní brána",
    "Exclusive Gateway": "Exkluzivní brána",
    "Use Case": "Případ užití",
    "Lifeline": "Čára života",
    "Interface": "Rozhraní",
    "Package": "Balíček",
    "Component": "Komponenta",
    "State": "Stav",
    "Initial State": "Počáteční stav",
    "Final State": "Koncový stav",
    "Banner": "Banner",
    "Card": "Karta",
    "Label": "Popisek",
    "Page": "Stránka",
    "Title": "Název",
    "Display": "Displej",
    "Delay": "Zpoždění",
    "Merge": "Sloučit",
    "Sort": "Seřadit",
    "Or": "Nebo",
    "And": "A",
    "Lightning": "Blesk",
    "Arc": "Oblouk",
    "Pie": "Výseč",
    "Horizontal Scroll": "Vodorovný svitek",
    "Vertical Scroll": "Svislý svitek",
    "Callout Arrow": "Šipka bubliny",
    "Rectangular Callout": "Obdélníková bublina",
    "Oval Callout": "Oválná bublina",
    "Actor Lifeline": "Čára života aktéra",
    "Activation Bar": "Aktivační pruh",
    "Flowchart": "Vývojový diagram",
    "Preparation": "Příprava",
    "Manual Operation": "Ruční operace",
    "Manual Input": "Ruční vstup",
    "Predefined Process": "Předdefinovaný proces",
    "Internal Storage": "Vnitřní úložiště",
    "Off-page Connector": "Mezistránková spojka",
    "Zigzag": "Cikcak",
    "X": "X",
}
CS_WORDS = {
    "arrow": "šipka", "rectangle": "obdélník", "ellipse": "elipsa", "circle": "kruh",
    "triangle": "trojúhelník", "square": "čtverec", "star": "hvězda", "cloud": "mrak",
    "callout": "bublina", "double": "dvojitá", "vertical": "svislý", "horizontal": "vodorovný",
    "rounded": "zaoblený", "task": "úkol", "gateway": "brána", "event": "událost",
    "data": "data", "entity": "entita", "attribute": "atribut", "lifeline": "čára života",
    "actor": "aktér", "message": "zpráva", "process": "proces", "document": "dokument",
    "line": "čára", "left": "vlevo", "right": "vpravo", "up": "nahoru", "down": "dolů",
    "frame": "rám", "manual": "ruční", "page": "stránka", "table": "tabulka",
    "container": "kontejner", "lane": "dráha", "pool": "bazén", "key": "klíč",
    "label": "popisek", "signal": "signál", "parallel": "paralelní", "grid": "mřížka",
    "cross": "kříž", "object": "objekt", "storage": "úložiště", "cylinder": "válec",
    "cube": "krychle", "button": "tlačítko", "card": "karta", "note": "poznámka",
    "class": "třída", "interface": "rozhraní", "package": "balíček", "component": "komponenta",
    "node": "uzel", "state": "stav", "decision": "rozhodnutí", "database": "databáze",
    "folder": "složka", "wave": "vlna", "heart": "srdce", "moon": "měsíc", "sun": "slunce",
    "text": "text", "box": "pole", "user": "uživatel", "service": "služba", "start": "start",
    "end": "konec", "or": "nebo", "and": "a", "display": "displej", "delay": "zpoždění",
    "merge": "sloučit", "sort": "seřadit", "title": "název", "annotation": "anotace",
    "connector": "spojka", "terminator": "ukončení", "fill": "výplň", "with": "s",
}

# Slovak from Czech-like with SK spelling
SK_PHRASES = {**CS_PHRASES}
SK_OVERRIDES = {
    "Rounded Rectangle": "Zaoblený obdĺžnik",
    "Rectangle": "Obdĺžnik",
    "Square": "Štvorec",
    "Diamond": "Kosoštvorec",
    "Triangle": "Trojuholník",
    "Acute Triangle": "Ostrouhelný trojuholník",
    "Right Triangle": "Pravouhlý trojuholník",
    "Arrow Down": "Šípka dole",
    "Arrow Up": "Šípka hore",
    "Arrow Left": "Šípka doľava",
    "Arrow Right": "Šípka doprava",
    "Double Arrow": "Dvojitá šípka",
    "Cloud": "Oblak",
    "Folder": "Priečinok",
    "Decision": "Rozhodnutie",
    "Class": "Trieda",
    "Table": "Tabuľka",
    "Grid": "Mriežka",
    "Heart": "Srdce",
    "Moon": "Mesiac",
    "Sun": "Slnko",
    "Star": "Hviezda",
    "4 Point Star": "4cípa hviezda",
    "6 Point Star": "6cípa hviezda",
    "8 Point Star": "8cípa hviezda",
    "Text Box": "Textové pole",
    "Note": "Poznámka",
    "Button": "Tlačidlo",
    "Cylinder": "Valec",
    "Cube": "Kocka",
    "Hexagon": "Šesťuholník",
    "Octagon": "Osemuholník",
    "Pentagon": "Päťuholník",
    "Wave": "Vlna",
    "Cross": "Kríž",
    "Frame": "Rám",
    "Lane": "Dráha",
    "Start Event": "Počiatočná udalosť",
    "End Event": "Koncová udalosť",
    "User Task": "Používateľská úloha",
    "Manual Task": "Ručná úloha",
    "Use Case": "Prípad použitia",
    "Package": "Balík",
    "State": "Stav",
    "Page": "Stránka",
    "Title": "Názov",
    "Or": "Alebo",
    "And": "A",
    "Horizontal Scroll": "Vodorovný zvitok",
    "Vertical Scroll": "Zvislý zvitok",
    "Flowchart": "Vývojový diagram",
    "Zigzag": "Cikcak",
}
for k, v in SK_OVERRIDES.items():
    SK_PHRASES[k] = v
SK_WORDS = {
    **CS_WORDS,
    "arrow": "šípka", "rectangle": "obdĺžnik", "square": "štvorec", "triangle": "trojuholník",
    "cloud": "oblak", "folder": "priečinok", "decision": "rozhodnutie", "class": "trieda",
    "table": "tabuľka", "grid": "mriežka", "star": "hviezda", "moon": "mesiac", "sun": "slnko",
    "button": "tlačidlo", "cube": "kocka", "cross": "kríž", "page": "stránka", "title": "názov",
    "user": "používateľ", "task": "úloha", "or": "alebo", "down": "dole", "up": "hore",
    "left": "doľava", "right": "doprava",
}

RO_PHRASES = {
    "Rounded Rectangle": "Dreptunghi rotunjit",
    "Circle": "Cerc",
    "Ellipse": "Elipsă",
    "Rectangle": "Dreptunghi",
    "Square": "Pătrat",
    "Diamond": "Romb",
    "Triangle": "Triunghi",
    "Arrow Down": "Săgeată jos",
    "Arrow Up": "Săgeată sus",
    "Arrow Left": "Săgeată stânga",
    "Arrow Right": "Săgeată dreapta",
    "Double Arrow": "Săgeată dublă",
    "Cloud": "Nor",
    "Document": "Document",
    "Folder": "Dosar",
    "Process": "Proces",
    "Decision": "Decizie",
    "Database": "Bază de date",
    "Actor": "Actor",
    "Class": "Clasă",
    "Table": "Tabel",
    "Grid": "Grilă",
    "Heart": "Inimă",
    "Moon": "Lună",
    "Sun": "Soare",
    "Star": "Stea",
    "4 Point Star": "Stea cu 4 colțuri",
    "6 Point Star": "Stea cu 6 colțuri",
    "8 Point Star": "Stea cu 8 colțuri",
    "Text Box": "Casă de text",
    "Note": "Notă",
    "Button": "Buton",
    "Cylinder": "Cilindru",
    "Cube": "Cub",
    "Wave": "Undă",
    "Cross": "Cruce",
    "Frame": "Cadru",
    "Container": "Container",
    "Pool": "Pool",
    "Lane": "Bandă",
    "Annotation": "Adnotare",
    "Connector": "Conector",
    "Terminator": "Terminator",
    "Start Event": "Eveniment de început",
    "End Event": "Eveniment de sfârșit",
    "User Task": "Sarcină utilizator",
    "Manual Task": "Sarcină manuală",
    "Data Object": "Obiect de date",
    "Use Case": "Caz de utilizare",
    "Lifeline": "Linia vieții",
    "Interface": "Interfață",
    "Package": "Pachet",
    "Component": "Componentă",
    "State": "Stare",
    "Page": "Pagină",
    "Title": "Titlu",
    "Or": "Sau",
    "And": "Și",
    "Flowchart": "Diagramă de flux",
    "Cloud Callout": "Balon nor",
    "Horizontal Scroll": "Derulare orizontală",
    "Vertical Scroll": "Derulare verticală",
    "Zigzag": "Zigzag",
    "X": "X",
}
RO_WORDS = {
    "arrow": "săgeată", "rectangle": "dreptunghi", "ellipse": "elipsă", "circle": "cerc",
    "triangle": "triunghi", "square": "pătrat", "star": "stea", "cloud": "nor",
    "callout": "balon", "double": "dublu", "vertical": "vertical", "horizontal": "orizontal",
    "rounded": "rotunjit", "task": "sarcină", "gateway": "poartă", "event": "eveniment",
    "data": "date", "entity": "entitate", "attribute": "atribut", "actor": "actor",
    "message": "mesaj", "process": "proces", "document": "document", "line": "linie",
    "left": "stânga", "right": "dreapta", "up": "sus", "down": "jos", "frame": "cadru",
    "page": "pagină", "table": "tabel", "container": "container", "lane": "bandă",
    "label": "etichetă", "class": "clasă", "interface": "interfață", "package": "pachet",
    "component": "componentă", "state": "stare", "decision": "decizie", "folder": "dosar",
    "wave": "undă", "heart": "inimă", "moon": "lună", "sun": "soare", "text": "text",
    "box": "casă", "user": "utilizator", "or": "sau", "and": "și", "title": "titlu",
    "annotation": "adnotare", "connector": "conector", "button": "buton", "note": "notă",
    "cross": "cruce", "cube": "cub", "cylinder": "cilindru", "grid": "grilă",
}

HU_PHRASES = {
    "Rounded Rectangle": "Lekerekített téglalap",
    "Circle": "Kör",
    "Ellipse": "Ellipszis",
    "Rectangle": "Téglalap",
    "Square": "Négyzet",
    "Diamond": "Rombusz",
    "Triangle": "Háromszög",
    "Arrow Down": "Nyíl le",
    "Arrow Up": "Nyíl fel",
    "Arrow Left": "Nyíl balra",
    "Arrow Right": "Nyíl jobbra",
    "Double Arrow": "Dupla nyíl",
    "Cloud": "Felhő",
    "Document": "Dokumentum",
    "Folder": "Mappa",
    "Process": "Folyamat",
    "Decision": "Döntés",
    "Database": "Adatbázis",
    "Actor": "Szereplő",
    "Class": "Osztály",
    "Table": "Táblázat",
    "Grid": "Rács",
    "Heart": "Szív",
    "Moon": "Hold",
    "Sun": "Nap",
    "Star": "Csillag",
    "4 Point Star": "4 ágú csillag",
    "6 Point Star": "6 ágú csillag",
    "8 Point Star": "8 ágú csillag",
    "Text Box": "Szövegdoboz",
    "Note": "Jegyzet",
    "Button": "Gomb",
    "Cylinder": "Henger",
    "Cube": "Kocka",
    "Wave": "Hullám",
    "Cross": "Kereszt",
    "Frame": "Keret",
    "Container": "Konténer",
    "Lane": "Sáv",
    "Annotation": "Jegyzet",
    "Connector": "Összekötő",
    "Terminator": "Lezáró",
    "Start Event": "Kezdő esemény",
    "End Event": "Záró esemény",
    "User Task": "Felhasználói feladat",
    "Manual Task": "Kézi feladat",
    "Data Object": "Adatobjektum",
    "Use Case": "Használati eset",
    "Lifeline": "Életvonal",
    "Interface": "Interfész",
    "Package": "Csomag",
    "Component": "Komponens",
    "State": "Állapot",
    "Page": "Oldal",
    "Title": "Cím",
    "Or": "Vagy",
    "And": "És",
    "Flowchart": "Folyamatábra",
    "Cloud Callout": "Felhőbuborék",
    "Horizontal Scroll": "Vízszintes tekercs",
    "Vertical Scroll": "Függőleges tekercs",
    "Zigzag": "Cikkcakk",
    "X": "X",
}
HU_WORDS = {
    "arrow": "nyíl", "rectangle": "téglalap", "ellipse": "ellipszis", "circle": "kör",
    "triangle": "háromszög", "square": "négyzet", "star": "csillag", "cloud": "felhő",
    "callout": "buborék", "double": "dupla", "vertical": "függőleges", "horizontal": "vízszintes",
    "rounded": "lekerekített", "task": "feladat", "gateway": "átjáró", "event": "esemény",
    "data": "adat", "actor": "szereplő", "process": "folyamat", "document": "dokumentum",
    "line": "vonal", "left": "balra", "right": "jobbra", "up": "fel", "down": "le",
    "frame": "keret", "page": "oldal", "table": "táblázat", "lane": "sáv",
    "class": "osztály", "package": "csomag", "state": "állapot", "decision": "döntés",
    "folder": "mappa", "wave": "hullám", "heart": "szív", "moon": "hold", "sun": "nap",
    "text": "szöveg", "box": "doboz", "user": "felhasználói", "or": "vagy", "and": "és",
    "title": "cím", "button": "gomb", "note": "jegyzet", "cross": "kereszt", "cube": "kocka",
    "grid": "rács", "connector": "összekötő",
}

EL_PHRASES = {
    "Rounded Rectangle": "Στρογγυλεμένο ορθογώνιο",
    "Circle": "Κύκλος",
    "Ellipse": "Έλλειψη",
    "Rectangle": "Ορθογώνιο",
    "Square": "Τετράγωνο",
    "Diamond": "Ρόμβος",
    "Triangle": "Τρίγωνο",
    "Arrow Down": "Βέλος κάτω",
    "Arrow Up": "Βέλος πάνω",
    "Arrow Left": "Βέλος αριστερά",
    "Arrow Right": "Βέλος δεξιά",
    "Double Arrow": "Διπλό βέλος",
    "Cloud": "Σύννεφο",
    "Document": "Έγγραφο",
    "Folder": "Φάκελος",
    "Process": "Διαδικασία",
    "Decision": "Απόφαση",
    "Database": "Βάση δεδομένων",
    "Actor": "Ηθοποιός",
    "Class": "Κλάση",
    "Table": "Πίνακας",
    "Grid": "Πλέγμα",
    "Heart": "Καρδιά",
    "Moon": "Φεγγάρι",
    "Sun": "Ήλιος",
    "Star": "Αστέρι",
    "4 Point Star": "Αστέρι 4 σημείων",
    "6 Point Star": "Αστέρι 6 σημείων",
    "8 Point Star": "Αστέρι 8 σημείων",
    "Text Box": "Πλαίσιο κειμένου",
    "Note": "Σημείωση",
    "Button": "Κουμπί",
    "Cylinder": "Κύλινδρος",
    "Cube": "Κύβος",
    "Wave": "Κύμα",
    "Cross": "Σταυρός",
    "Frame": "Πλαίσιο",
    "Container": "Κοντέινερ",
    "Lane": "Λωρίδα",
    "Annotation": "Σχόλιο",
    "Connector": "Σύνδεσμος",
    "Terminator": "Τερματισμός",
    "Start Event": "Γεγονός έναρξης",
    "End Event": "Γεγονός λήξης",
    "User Task": "Εργασία χρήστη",
    "Manual Task": "Χειροκίνητη εργασία",
    "Data Object": "Αντικείμενο δεδομένων",
    "Use Case": "Περίπτωση χρήσης",
    "Lifeline": "Γραμμή ζωής",
    "Interface": "Διεπαφή",
    "Package": "Πακέτο",
    "Component": "Συστατικό",
    "State": "Κατάσταση",
    "Page": "Σελίδα",
    "Title": "Τίτλος",
    "Or": "Ή",
    "And": "Και",
    "Flowchart": "Διάγραμμα ροής",
    "Cloud Callout": "Συννεφόφυσαλλο",
    "Zigzag": "Ζιγκζαγκ",
    "X": "X",
}
EL_WORDS = {
    "arrow": "βέλος", "rectangle": "ορθογώνιο", "ellipse": "έλλειψη", "circle": "κύκλος",
    "triangle": "τρίγωνο", "square": "τετράγωνο", "star": "αστέρι", "cloud": "σύννεφο",
    "callout": "φυσαλλίδα", "double": "διπλό", "vertical": "κατακόρυφο", "horizontal": "οριζόντιο",
    "rounded": "στρογγυλεμένο", "task": "εργασία", "event": "γεγονός", "data": "δεδομένα",
    "actor": "ηθοποιός", "process": "διαδικασία", "document": "έγγραφο", "line": "γραμμή",
    "left": "αριστερά", "right": "δεξιά", "up": "πάνω", "down": "κάτω", "page": "σελίδα",
    "table": "πίνακας", "class": "κλάση", "state": "κατάσταση", "decision": "απόφαση",
    "folder": "φάκελος", "wave": "κύμα", "heart": "καρδιά", "moon": "φεγγάρι", "sun": "ήλιος",
    "text": "κείμενο", "box": "πλαίσιο", "user": "χρήστη", "or": "ή", "and": "και",
    "title": "τίτλος", "button": "κουμπί", "note": "σημείωση", "cross": "σταυρός",
    "cube": "κύβος", "grid": "πλέγμα", "connector": "σύνδεσμος",
}

HR_PHRASES = {
    "Rounded Rectangle": "Zaobljeni pravokutnik",
    "Circle": "Krug",
    "Ellipse": "Elipsa",
    "Rectangle": "Pravokutnik",
    "Square": "Kvadrat",
    "Diamond": "Romb",
    "Triangle": "Trokut",
    "Arrow Down": "Strelica dolje",
    "Arrow Up": "Strelica gore",
    "Arrow Left": "Strelica lijevo",
    "Arrow Right": "Strelica desno",
    "Double Arrow": "Dvostruka strelica",
    "Cloud": "Oblak",
    "Document": "Dokument",
    "Folder": "Mapa",
    "Process": "Proces",
    "Decision": "Odluka",
    "Database": "Baza podataka",
    "Actor": "Aktor",
    "Class": "Klasa",
    "Table": "Tablica",
    "Grid": "Mreža",
    "Heart": "Srce",
    "Moon": "Mjesec",
    "Sun": "Sunce",
    "Star": "Zvijezda",
    "4 Point Star": "Zvijezda s 4 kraka",
    "6 Point Star": "Zvijezda s 6 kraka",
    "8 Point Star": "Zvijezda s 8 kraka",
    "Text Box": "Tekstni okvir",
    "Note": "Bilješka",
    "Button": "Gumb",
    "Cylinder": "Cilindar",
    "Cube": "Kocka",
    "Wave": "Val",
    "Cross": "Križ",
    "Frame": "Okvir",
    "Container": "Spremnik",
    "Lane": "Traka",
    "Annotation": "Napomena",
    "Connector": "Spojnica",
    "Terminator": "Završetak",
    "Start Event": "Početni događaj",
    "End Event": "Završni događaj",
    "User Task": "Korisnički zadatak",
    "Manual Task": "Ručni zadatak",
    "Use Case": "Slučaj upotrebe",
    "Lifeline": "Linija života",
    "Interface": "Sučelje",
    "Package": "Paket",
    "Component": "Komponenta",
    "State": "Stanje",
    "Page": "Stranica",
    "Title": "Naslov",
    "Or": "Ili",
    "And": "I",
    "Flowchart": "Dijagram toka",
    "Zigzag": "Cikcak",
    "X": "X",
}
HR_WORDS = {
    "arrow": "strelica", "rectangle": "pravokutnik", "ellipse": "elipsa", "circle": "krug",
    "triangle": "trokut", "square": "kvadrat", "star": "zvijezda", "cloud": "oblak",
    "callout": "balončić", "double": "dvostruka", "vertical": "okomito", "horizontal": "vodoravno",
    "rounded": "zaobljeni", "task": "zadatak", "event": "događaj", "data": "podaci",
    "actor": "aktor", "process": "proces", "document": "dokument", "line": "linija",
    "left": "lijevo", "right": "desno", "up": "gore", "down": "dolje", "page": "stranica",
    "table": "tablica", "class": "klasa", "state": "stanje", "decision": "odluka",
    "folder": "mapa", "wave": "val", "heart": "srce", "moon": "mjesec", "sun": "sunce",
    "text": "tekst", "box": "okvir", "user": "korisnički", "or": "ili", "and": "i",
    "title": "naslov", "button": "gumb", "note": "bilješka", "cross": "križ", "cube": "kocka",
    "grid": "mreža", "connector": "spojnica",
}

SW_PHRASES = {
    "Rounded Rectangle": "Mstatili wenye pembe za mviringo",
    "Circle": "Duara",
    "Ellipse": "Duaraike",
    "Rectangle": "Mstatili",
    "Square": "Mraba",
    "Diamond": "Almasi",
    "Triangle": "Pembetatu",
    "Arrow Down": "Mshale chini",
    "Arrow Up": "Mshale juu",
    "Arrow Left": "Mshale kushoto",
    "Arrow Right": "Mshale kulia",
    "Double Arrow": "Mishale miwili",
    "Cloud": "Wingu",
    "Document": "Hati",
    "Folder": "Folda",
    "Process": "Mchakato",
    "Decision": "Uamuzi",
    "Database": "Hifadhidata",
    "Actor": "Mwigizaji",
    "Class": "Darasa",
    "Table": "Jedwali",
    "Grid": "Gridi",
    "Heart": "Moyo",
    "Moon": "Mwezi",
    "Sun": "Jua",
    "Star": "Nyota",
    "4 Point Star": "Nyota yenye pointi 4",
    "6 Point Star": "Nyota yenye pointi 6",
    "8 Point Star": "Nyota yenye pointi 8",
    "Text Box": "Kisanduku cha maandishi",
    "Note": "Dokezo",
    "Button": "Kitufe",
    "Cylinder": "Silinda",
    "Cube": "Mchemraba",
    "Wave": "Wimbi",
    "Cross": "Msalaba",
    "Frame": "Fremu",
    "Container": "Kontena",
    "Lane": "Njia",
    "Annotation": "Maelezo",
    "Connector": "Kiunganishi",
    "Terminator": "Kitamatisho",
    "Start Event": "Tukio la kuanza",
    "End Event": "Tukio la kumaliza",
    "User Task": "Kazi ya mtumiaji",
    "Manual Task": "Kazi ya mkono",
    "Use Case": "Kesi ya matumizi",
    "Page": "Ukurasa",
    "Title": "Kichwa",
    "Or": "Au",
    "And": "Na",
    "Flowchart": "Chati ya mtiririko",
    "Zigzag": "Zigzag",
    "X": "X",
}
SW_WORDS = {
    "arrow": "mshale", "rectangle": "mstatili", "circle": "duara", "triangle": "pembetatu",
    "square": "mraba", "star": "nyota", "cloud": "wingu", "double": "mbili",
    "task": "kazi", "event": "tukio", "data": "data", "process": "mchakato",
    "document": "hati", "line": "mstari", "left": "kushoto", "right": "kulia",
    "up": "juu", "down": "chini", "page": "ukurasa", "table": "jedwali",
    "class": "darasa", "decision": "uamuzi", "folder": "folda", "wave": "wimbi",
    "heart": "moyo", "moon": "mwezi", "sun": "jua", "text": "maandishi", "box": "kisanduku",
    "user": "mtumiaji", "or": "au", "and": "na", "title": "kichwa", "button": "kitufe",
    "note": "dokezo", "cross": "msalaba", "grid": "gridi", "connector": "kiunganishi",
}

BN_PHRASES = {
    "Rounded Rectangle": "গোলাকার আয়তক্ষেত্র",
    "Circle": "বৃত্ত",
    "Ellipse": "উপবৃত্ত",
    "Rectangle": "আয়তক্ষেত্র",
    "Square": "বর্গ",
    "Diamond": "হীরা",
    "Triangle": "ত্রিভুজ",
    "Arrow Down": "নিচের তীর",
    "Arrow Up": "উপরের তীর",
    "Arrow Left": "বাম তীর",
    "Arrow Right": "ডান তীর",
    "Double Arrow": "দ্বৈত তীর",
    "Cloud": "মেঘ",
    "Document": "নথি",
    "Folder": "ফোল্ডার",
    "Process": "প্রক্রিয়া",
    "Decision": "সিদ্ধান্ত",
    "Database": "ডেটাবেস",
    "Actor": "অভিনেতা",
    "Class": "শ্রেণি",
    "Table": "সারণি",
    "Grid": "গ্রিড",
    "Heart": "হৃদয়",
    "Moon": "চাঁদ",
    "Sun": "সূর্য",
    "Star": "তারা",
    "4 Point Star": "৪ কোণার তারা",
    "6 Point Star": "৬ কোণার তারা",
    "8 Point Star": "৮ কোণার তারা",
    "Text Box": "টেক্সট বক্স",
    "Note": "নোট",
    "Button": "বোতাম",
    "Cylinder": "সিলিন্ডার",
    "Cube": "ঘনক",
    "Wave": "তরঙ্গ",
    "Cross": "ক্রস",
    "Frame": "ফ্রেম",
    "Page": "পৃষ্ঠা",
    "Title": "শিরোনাম",
    "Or": "অথবা",
    "And": "এবং",
    "Flowchart": "ফ্লোচার্ট",
    "Start Event": "শুরুর ইভেন্ট",
    "End Event": "শেষ ইভেন্ট",
    "User Task": "ব্যবহারকারী কাজ",
    "Use Case": "ব্যবহার কেস",
    "Zigzag": "জিগজ্যাগ",
    "X": "X",
}
BN_WORDS = {
    "arrow": "তীর", "rectangle": "আয়তক্ষেত্র", "circle": "বৃত্ত", "triangle": "ত্রিভুজ",
    "square": "বর্গ", "star": "তারা", "cloud": "মেঘ", "document": "নথি", "folder": "ফোল্ডার",
    "process": "প্রক্রিয়া", "decision": "সিদ্ধান্ত", "table": "সারণি", "page": "পৃষ্ঠা",
    "left": "বাম", "right": "ডান", "up": "উপর", "down": "নিচ", "or": "অথবা", "and": "এবং",
    "text": "টেক্সট", "box": "বক্স", "button": "বোতাম", "note": "নোট", "heart": "হৃদয়",
    "moon": "চাঁদ", "sun": "সূর্য", "wave": "তরঙ্গ", "cross": "ক্রস", "title": "শিরোনাম",
}

FA_PHRASES = {
    "Rounded Rectangle": "مستطیل گرد",
    "Circle": "دایره",
    "Ellipse": "بیضی",
    "Rectangle": "مستطیل",
    "Square": "مربع",
    "Diamond": "لوزی",
    "Triangle": "مثلث",
    "Arrow Down": "پیکان پایین",
    "Arrow Up": "پیکان بالا",
    "Arrow Left": "پیکان چپ",
    "Arrow Right": "پیکان راست",
    "Double Arrow": "پیکان دوتایی",
    "Cloud": "ابر",
    "Document": "سند",
    "Folder": "پوشه",
    "Process": "فرآیند",
    "Decision": "تصمیم",
    "Database": "پایگاه داده",
    "Actor": "بازیگر",
    "Class": "کلاس",
    "Table": "جدول",
    "Grid": "شبکه",
    "Heart": "قلب",
    "Moon": "ماه",
    "Sun": "خورشید",
    "Star": "ستاره",
    "4 Point Star": "ستاره ۴ پر",
    "6 Point Star": "ستاره ۶ پر",
    "8 Point Star": "ستاره ۸ پر",
    "Text Box": "کادر متن",
    "Note": "یادداشت",
    "Button": "دکمه",
    "Cylinder": "استوانه",
    "Cube": "مکعب",
    "Wave": "موج",
    "Cross": "ضربدر",
    "Frame": "قاب",
    "Page": "صفحه",
    "Title": "عنوان",
    "Or": "یا",
    "And": "و",
    "Flowchart": "نمودار جریان",
    "Start Event": "رویداد شروع",
    "End Event": "رویداد پایان",
    "User Task": "وظیفه کاربر",
    "Use Case": "مورد کاربرد",
    "Lifeline": "خط زندگی",
    "Zigzag": "زیگزاگ",
    "X": "X",
}
FA_WORDS = {
    "arrow": "پیکان", "rectangle": "مستطیل", "circle": "دایره", "triangle": "مثلث",
    "square": "مربع", "star": "ستاره", "cloud": "ابر", "document": "سند", "folder": "پوشه",
    "process": "فرآیند", "decision": "تصمیم", "table": "جدول", "page": "صفحه",
    "left": "چپ", "right": "راست", "up": "بالا", "down": "پایین", "or": "یا", "and": "و",
    "text": "متن", "box": "کادر", "button": "دکمه", "note": "یادداشت", "heart": "قلب",
    "moon": "ماه", "sun": "خورشید", "wave": "موج", "title": "عنوان", "task": "وظیفه",
    "event": "رویداد", "user": "کاربر", "class": "کلاس", "state": "حالت",
}

# Catalan adaptations applied on top of Spanish map
CA_FROM_ES = {
    "Rectángulo": "Rectangle",
    "rectángulo": "rectangle",
    "Redondeado": "Arrodonit",
    "redondeado": "arrodonit",
    "Círculo": "Cercle",
    "Elipse": "El·lipse",
    "Cuadrado": "Quadrat",
    "Triángulo": "Triangle",
    "Flecha": "Fletxa",
    "abajo": "avall",
    "arriba": "amunt",
    "izquierda": "esquerra",
    "derecha": "dreta",
    "Doble": "Doble",
    "Nube": "Núvol",
    "Documento": "Document",
    "Carpeta": "Carpeta",
    "Proceso": "Procés",
    "Decisión": "Decisió",
    "Base de datos": "Base de dades",
    "Clase": "Classe",
    "Tabla": "Taula",
    "Cuadrícula": "Quadrícula",
    "Corazón": "Cor",
    "Luna": "Lluna",
    "Sol": "Sol",
    "Estrella": "Estrella",
    "Cuadro de texto": "Quadre de text",
    "Nota": "Nota",
    "Botón": "Botó",
    "Cilindro": "Cilindre",
    "Cubo": "Cub",
    "Onda": "Ona",
    "Cruz": "Creu",
    "Marco": "Marc",
    "Contenedor": "Contenidor",
    "Carril": "Carril",
    "Anotación": "Anotació",
    "Conector": "Connector",
    "Terminador": "Terminador",
    "Evento de inicio": "Esdeveniment d'inici",
    "Evento final": "Esdeveniment final",
    "Tarea de usuario": "Tasca d'usuari",
    "Tarea manual": "Tasca manual",
    "Caso de uso": "Cas d'ús",
    "Línea de vida": "Línia de vida",
    "Interfaz": "Interfície",
    "Paquete": "Paquet",
    "Componente": "Component",
    "Estado": "Estat",
    "Página": "Pàgina",
    "Título": "Títol",
    "O": "O",
    "Y": "I",
    "Diagrama de flujo": "Diagrama de flux",
}


def adapt_map(base: dict[str, str], replacements: dict[str, str]) -> dict[str, str]:
    out: dict[str, str] = {}
    for eng, loc in base.items():
        s = loc
        for a, b in sorted(replacements.items(), key=lambda kv: -len(kv[0])):
            if len(a) <= 2:
                # Avoid corrupting longer words (e.g. Spanish "Y" / "O").
                s = re.sub(
                    rf"(?<!\w){re.escape(a)}(?!\w)",
                    b,
                    s,
                )
            else:
                s = s.replace(a, b)
        out[eng] = s
    return out


FIL_FROM_ID = {
    "Persegi panjang": "Parihaba",
    "persegi panjang": "parihaba",
    "Rounded": "May bilog na sulok",
    "Lingkaran": "Bilog",
    "Elips": "Ellipse",
    "Persegi": "Parisukat",
    "Segitiga": "Tatsulok",
    "Panah": "Arrow",
    "bawah": "pababa",
    "atas": "pataas",
    "kiri": "pakaliwa",
    "kanan": "pakanan",
    "Awan": "Ulap",
    "Dokumen": "Dokumento",
    "Folder": "Folder",
    "Proses": "Proseso",
    "Keputusan": "Desisyon",
    "Basis data": "Database",
    "Aktor": "Aktor",
    "Kelas": "Klase",
    "Tabel": "Talahanayan",
    "Kisi": "Grid",
    "Hati": "Puso",
    "Bulan": "Buwan",
    "Matahari": "Araw",
    "Bintang": "Bituin",
    "Kotak teks": "Text box",
    "Catatan": "Tala",
    "Tombol": "Button",
    "Silinder": "Silindro",
    "Kubus": "Kubo",
    "Gelombang": "Alon",
    "Salib": "Krus",
    "Bingkai": "Frame",
    "Kontainer": "Container",
    "Jalur": "Lane",
    "Anotasi": "Anotasyon",
    "Konektor": "Konektor",
    "Terminator": "Terminator",
    "Halaman": "Pahina",
    "Judul": "Pamagat",
    "Atau": "O",
    "Dan": "At",
    "Bagan alir": "Flowchart",
}

MS_FROM_ID = {
    # Malay is close to Indonesian; tweak a few forms
    "Persegi panjang bulat": "Segi empat tepat bulat",
    "Dasar data": "Pangkalan data",
    "Basis data": "Pangkalan data",
}


def improve_existing(names: list[str], lang: str, phrases: dict[str, str], words: dict[str, str]) -> dict[str, str]:
    """Fill English leftovers in an existing map."""
    base = load_map(lang)
    out: dict[str, str] = {}
    for n in names:
        cur = base.get(n, n)
        if cur == n:
            out[n] = apply_lexicon(n, phrases, words)
        else:
            out[n] = cur
    return out


def main() -> None:
    names = load_en_names()
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    builders: dict[str, dict[str, str]] = {}

    builders["sv"] = translate_all(names, SV_PHRASES, SV_WORDS)
    builders["da"] = translate_all(names, DA_PHRASES, DA_WORDS)
    builders["nb"] = translate_all(names, NB_PHRASES, NB_WORDS)
    builders["fi"] = translate_all(names, FI_PHRASES, FI_WORDS)
    builders["cs"] = translate_all(names, CS_PHRASES, CS_WORDS)
    builders["sk"] = translate_all(names, SK_PHRASES, SK_WORDS)
    builders["ro"] = translate_all(names, RO_PHRASES, RO_WORDS)
    builders["hu"] = translate_all(names, HU_PHRASES, HU_WORDS)
    builders["el"] = translate_all(names, EL_PHRASES, EL_WORDS)
    builders["hr"] = translate_all(names, HR_PHRASES, HR_WORDS)
    builders["sw"] = translate_all(names, SW_PHRASES, SW_WORDS)
    builders["bn"] = translate_all(names, BN_PHRASES, BN_WORDS)
    builders["fa"] = translate_all(names, FA_PHRASES, FA_WORDS)

    es = load_map("es")
    if es:
        builders["ca"] = adapt_map(
            {n: es.get(n, n) for n in names}, CA_FROM_ES
        )
        # fill any remaining English via Catalan-ish lexicon from Spanish leftovers
        ca_words = {
            "arrow": "fletxa", "rectangle": "rectangle", "circle": "cercle",
            "triangle": "triangle", "square": "quadrat", "star": "estrella",
            "cloud": "núvol", "document": "document", "folder": "carpeta",
            "left": "esquerra", "right": "dreta", "up": "amunt", "down": "avall",
            "double": "doble", "rounded": "arrodonit", "page": "pàgina",
            "table": "taula", "button": "botó", "note": "nota", "heart": "cor",
            "moon": "lluna", "sun": "sol", "wave": "ona", "cross": "creu",
            "title": "títol", "or": "o", "and": "i", "text": "text", "box": "quadre",
        }
        for n in names:
            if builders["ca"][n] == n:
                builders["ca"][n] = apply_lexicon(n, {}, ca_words)


    id_map = load_map("id")
    if id_map:
        builders["fil"] = adapt_map({n: id_map.get(n, n) for n in names}, FIL_FROM_ID)
        builders["ms"] = adapt_map({n: id_map.get(n, n) for n in names}, MS_FROM_ID)
        fil_words = {
            "arrow": "arrow", "circle": "bilog", "square": "parisukat",
            "triangle": "tatsulok", "star": "bituin", "cloud": "ulap",
            "heart": "puso", "moon": "buwan", "sun": "araw", "wave": "alon",
            "document": "dokumento", "folder": "folder", "page": "pahina",
            "title": "pamagat", "or": "o", "and": "at", "left": "kaliwa",
            "right": "kanan", "up": "taas", "down": "baba", "table": "talahanayan",
            "button": "button", "note": "tala", "cross": "krus", "decision": "desisyon",
            "process": "proseso", "class": "klase", "rounded": "bilog ang sulok",
            "rectangle": "parihaba", "double": "doble",
        }
        ms_words = {
            "arrow": "anak panah", "circle": "bulatan", "square": "segi empat sama",
            "triangle": "segi tiga", "star": "bintang", "cloud": "awan",
            "document": "dokumen", "folder": "folder", "page": "halaman",
            "title": "tajuk", "or": "atau", "and": "dan", "left": "kiri",
            "right": "kanan", "up": "atas", "down": "bawah", "table": "jadual",
            "button": "butang", "note": "nota", "decision": "keputusan",
            "process": "proses", "class": "kelas", "rounded": "bulat",
            "rectangle": "segi empat tepat", "heart": "hati", "moon": "bulan",
            "sun": "matahari", "wave": "ombak",
        }
        for n in names:
            if builders["fil"].get(n, n) == n:
                builders["fil"][n] = apply_lexicon(n, {}, fil_words)
            if builders["ms"].get(n, n) == n:
                builders["ms"][n] = apply_lexicon(n, {}, ms_words)
    else:
        builders["fil"] = translate_all(names, {}, {
            "arrow": "arrow", "circle": "bilog", "rectangle": "parihaba",
            "square": "parisukat", "triangle": "tatsulok", "star": "bituin",
        })
        builders["ms"] = translate_all(names, {}, {
            "arrow": "anak panah", "circle": "bulatan", "rectangle": "segi empat tepat",
            "square": "segi empat sama", "triangle": "segi tiga", "star": "bintang",
        })

    ru = load_map("ru")
    if ru:
        # Bulgarian: start from Russian and apply common RU→BG spelling tweaks
        bg_repl = {
            "Прямоугольник": "Правоъгълник",
            "прямоугольник": "правоъгълник",
            "Скруглённый": "Заоблен",
            "Круг": "Кръг",
            "Эллипс": "Елипса",
            "Квадрат": "Квадрат",
            "Треугольник": "Триъгълник",
            "Стрелка": "Стрелка",
            "вниз": "надолу",
            "вверх": "нагоре",
            "влево": "наляво",
            "вправо": "надясно",
            "Облако": "Облак",
            "Документ": "Документ",
            "Папка": "Папка",
            "Процесс": "Процес",
            "Решение": "Решение",
            "База данных": "База данни",
            "Актёр": "Актьор",
            "Класс": "Клас",
            "Таблица": "Таблица",
            "Сетка": "Мрежа",
            "Сердце": "Сърце",
            "Луна": "Луна",
            "Солнце": "Слънце",
            "Звезда": "Звезда",
            "Текстовое поле": "Текстово поле",
            "Кнопка": "Бутон",
            "Цилиндр": "Цилиндър",
            "Куб": "Куб",
            "Волна": "Вълна",
            "Крест": "Кръст",
            "Рамка": "Рамка",
            "Контейнер": "Контейнер",
            "Аннотация": "Анотация",
            "Соединитель": "Съединител",
            "Страница": "Страница",
            "Заголовок": "Заглавие",
            "Или": "Или",
            "И": "И",
            "Блок-схема": "Блок-схема",
        }
        builders["bg"] = adapt_map({n: ru.get(n, n) for n in names}, bg_repl)
        bg_words = {
            "arrow": "стрелка", "rectangle": "правоъгълник", "circle": "кръг",
            "triangle": "триъгълник", "square": "квадрат", "star": "звезда",
            "cloud": "облак", "left": "наляво", "right": "надясно",
            "up": "нагоре", "down": "надолу", "page": "страница", "table": "таблица",
            "button": "бутон", "heart": "сърце", "moon": "луна", "sun": "слънце",
            "wave": "вълна", "cross": "кръст", "title": "заглавие", "or": "или", "and": "и",
            "document": "документ", "folder": "папка", "decision": "решение",
            "process": "процес", "class": "клас", "rounded": "заоблен",
        }
        for n in names:
            if builders["bg"][n] == n:
                builders["bg"][n] = apply_lexicon(n, {}, bg_words)
    else:
        builders["bg"] = translate_all(names, {}, {
            "arrow": "стрелка", "circle": "кръг", "rectangle": "правоъгълник",
            "square": "квадрат", "triangle": "триъгълник", "star": "звезда",
        })

    # Also improve sparse existing maps (fill English leftovers)
    improve_langs = {
        "nl": (
            {
                "Rounded Rectangle": "Afgeronde rechthoek",
                "Arrow Down": "Pijl omlaag",
                "Arrow Up": "Pijl omhoog",
                "Arrow Left": "Pijl links",
                "Arrow Right": "Pijl rechts",
                "Cloud": "Wolk",
                "Document": "Document",
                "Folder": "Map",
                "Decision": "Beslissing",
                "Heart": "Hart",
                "Moon": "Maan",
                "Sun": "Zon",
                "Star": "Ster",
                "Wave": "Golf",
                "Cross": "Kruis",
                "Table": "Tabel",
                "Grid": "Raster",
                "Button": "Knop",
                "Note": "Notitie",
                "Page": "Pagina",
                "Title": "Titel",
                "Or": "Of",
                "And": "En",
                "Zigzag": "Zigzag",
            },
            {
                "arrow": "pijl", "rectangle": "rechthoek", "circle": "cirkel",
                "triangle": "driehoek", "square": "vierkant", "star": "ster",
                "cloud": "wolk", "left": "links", "right": "rechts", "up": "omhoog",
                "down": "omlaag", "heart": "hart", "moon": "maan", "sun": "zon",
                "wave": "golf", "cross": "kruis", "table": "tabel", "grid": "raster",
                "button": "knop", "note": "notitie", "page": "pagina", "title": "titel",
                "or": "of", "and": "en", "folder": "map", "decision": "beslissing",
                "rounded": "afgeronde", "double": "dubbele", "callout": "callout",
                "document": "document", "process": "proces", "class": "klasse",
            },
        ),
        "fr": (
            {
                "Arrow Down": "Flèche bas",
                "Arrow Up": "Flèche haut",
                "Arrow Left": "Flèche gauche",
                "Arrow Right": "Flèche droite",
                "Heart": "Cœur",
                "Moon": "Lune",
                "Sun": "Soleil",
                "Star": "Étoile",
                "Wave": "Vague",
                "Cross": "Croix",
                "Or": "Ou",
                "And": "Et",
            },
            {
                "arrow": "flèche", "rectangle": "rectangle", "circle": "cercle",
                "triangle": "triangle", "square": "carré", "star": "étoile",
                "cloud": "nuage", "left": "gauche", "right": "droite", "up": "haut",
                "down": "bas", "heart": "cœur", "moon": "lune", "sun": "soleil",
                "wave": "vague", "cross": "croix", "or": "ou", "and": "et",
                "rounded": "arrondi", "double": "double", "folder": "dossier",
                "document": "document", "button": "bouton", "note": "note",
                "page": "page", "title": "titre", "table": "tableau",
            },
        ),
        "de": (
            {
                "Arrow Down": "Pfeil unten",
                "Arrow Up": "Pfeil oben",
                "Arrow Left": "Pfeil links",
                "Arrow Right": "Pfeil rechts",
                "Heart": "Herz",
                "Moon": "Mond",
                "Sun": "Sonne",
                "Star": "Stern",
                "Wave": "Welle",
                "Cross": "Kreuz",
                "Or": "Oder",
                "And": "Und",
            },
            {
                "arrow": "pfeil", "rectangle": "rechteck", "circle": "kreis",
                "triangle": "dreieck", "square": "quadrat", "star": "stern",
                "cloud": "wolke", "left": "links", "right": "rechts", "up": "oben",
                "down": "unten", "heart": "herz", "moon": "mond", "sun": "sonne",
                "wave": "welle", "cross": "kreuz", "or": "oder", "and": "und",
                "rounded": "abgerundetes", "double": "doppel", "folder": "ordner",
                "document": "dokument", "button": "schaltfläche", "note": "notiz",
                "page": "seite", "title": "titel", "table": "tabelle",
            },
        ),
    }
    for lang, (phrases, words) in improve_langs.items():
        builders[lang] = improve_existing(names, lang, phrases, words)

    for lang, data in sorted(builders.items()):
        # ensure every English name is present
        full = {n: data.get(n, n) for n in names}
        path = OUT_DIR / f"{lang}.json"
        path.write_text(json.dumps(full, ensure_ascii=False, indent=0) + "\n")
        localized = sum(1 for n in names if full[n] != n)
        print(f"{lang}: {localized}/{len(names)} localized → {path.name}")


if __name__ == "__main__":
    main()
