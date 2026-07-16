#!/usr/bin/env python3
"""Generate lib/l10n/editor_l10n_maps.dart from en/zh sources + UI translations."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EDITOR_L10N = ROOT / "lib/l10n/editor_l10n.dart"
OUT = ROOT / "lib/l10n/editor_l10n_maps.dart"

LANGS = [
    "en", "zh", "ja", "ko", "es", "fr", "de", "pt", "ru", "it", "ar", "id",
    "hi", "nl", "tr", "pl", "vi", "th", "sv", "uk", "he", "cs", "ro", "el",
    "hu", "da", "ms", "fi", "nb", "sk", "bn", "fa", "bg", "hr", "ca", "fil",
    "sw",
]

# Major languages also get stencil name translations (built from English names).
STENCIL_LANGS = {
    "zh", "ja", "ko", "es", "fr", "de", "pt", "ru", "it", "ar", "vi", "th",
    "id", "nl", "pl", "tr", "uk", "he", "hi",
}


def extract_map(text: str, name: str) -> dict[str, str]:
    m = re.search(
        rf"static const Map<String, String> {name} = <String, String>\{{(.*?)\n  \}};",
        text,
        re.S,
    )
    if not m:
        raise SystemExit(f"map {name} not found")
    body = m.group(1)
    body2 = re.sub(r"'([^']*)'\s*\n\s*'([^']*)'", r"'\1\2'", body)
    body2 = re.sub(r"'([^']*)'\s*\n\s*'([^']*)'", r"'\1\2'", body2)
    return {k: v for k, v in re.findall(r"'([^']+)':\s*'([^']*)'", body2)}


def dart_escape(s: str) -> str:
    return s.replace("\\", "\\\\").replace("'", "\\'")


def dart_map(name: str, data: dict[str, str]) -> str:
    lines = [f"const Map<String, String> {name} = <String, String>{{"]
    for k, v in data.items():
        lines.append(f"  '{dart_escape(k)}': '{dart_escape(v)}',")
    lines.append("};")
    return "\n".join(lines)


def shortcut(base: str, suffix: str) -> str:
    return f"{base} {suffix}" if suffix else base


def build_ui(lang: str, en: dict[str, str], zh: dict[str, str]) -> dict[str, str]:
    """Return full UI map (non-st_ keys) for lang."""
    if lang == "en":
        return {k: v for k, v in en.items() if not k.startswith("st_")}
    if lang == "zh":
        return {k: v for k, v in zh.items() if not k.startswith("st_")}

    # Word/phrase banks per language for composing UI strings.
    # Format: key -> translated string. Must cover all non-st_ keys in en.
    banks = _UI_BANKS
    if lang not in banks:
        raise SystemExit(f"missing UI bank for {lang}")
    bank = banks[lang]
    missing = [k for k in en if not k.startswith("st_") and k not in bank]
    if missing:
        raise SystemExit(f"{lang} missing keys: {missing[:20]} ({len(missing)} total)")
    return {k: bank[k] for k in en if not k.startswith("st_")}


def build_stencils(lang: str, en: dict[str, str], zh: dict[str, str]) -> dict[str, str]:
    if lang == "en":
        return {k: v for k, v in en.items() if k.startswith("st_")}
    if lang == "zh":
        return {k: v for k, v in zh.items() if k.startswith("st_")}
    if lang not in STENCIL_LANGS:
        return {}
    bank = _STENCIL_BANKS.get(lang)
    if not bank:
        # Derive from English display names via name-level map if available
        name_map = _STENCIL_NAME_MAPS.get(lang, {})
        out = {}
        for k, eng in en.items():
            if not k.startswith("st_"):
                continue
            out[k] = name_map.get(eng, eng)
        return out
    out = {}
    for k, eng in en.items():
        if k.startswith("st_"):
            out[k] = bank.get(k, eng)
    return out


# ---------------------------------------------------------------------------
# UI translation banks (complete for every non-English language)
# Generated carefully; placeholders {n}/{path}/{error}/{current}/{total}/{name}
# must be preserved.
# ---------------------------------------------------------------------------

def _ui(
    *,
    cancel, ok, apply, close, delete, rename, discard, none, enabled, untitled,
    undo, redo, outline, rulers, toggleGrid, fitToWindow, layers, insertImage,
    hideOutline, selectAll, find, findReplace, editData, editLink,
    editConnectionPoints, doneEditingConnectionPoints, lock, unlock,
    zoomToSelection, copyStyle, pasteStyle, saveAs, exportSvg, exportPng,
    exportPdf, snapToGrid, lineJumps, closeTab, cut, copy, paste, pasteHere,
    duplicate, clearWaypoints, bringToFront, sendToBack, bringForward,
    sendBackward, group, ungroup, editText, replaceImage, addLane, removeLane,
    addRow, addColumn, deleteRow, deleteColumn, mergeCells, unmergeCells,
    clearGuides, toolSelect, toolRectangle, toolEllipse, toolLine,
    toolConnector, toolFreehand, toolText, moreShapes, searchShapes,
    categoriesCount, expandAll, collapseAll, addPage, duplicatePage,
    deletePage, renamePage, pageNameHint, pageReorderHint,
    backgroundPageReorderHint, pageOf, unsaved, noSelection, selectedCount,
    emptySubtitle, newDrawing, openVisioDrawing, orTrySample, dropHint,
    discardUnsavedTitle, discardUnsavedBody, savedTo, saveFailed, exportedSvg,
    exportedPng, exportedPdf, svgExportFailed, pngExportFailed,
    pngExportFailedError, pdfExportFailed, panelArrange, panelAlign,
    panelAlignToPage, panelFill, panelLine, panelConnector, panelShadow,
    panelGlow, panelReflection, panelSoftEdges, panelText, panelImage,
    panelData, panelLink, panelDiagram, panelView, opacity, size, color,
    rounded, gradient, linear, radial, start, end, blur, offsetX, offsetY,
    dist, solid, dashed, dotted, straight, orthogonal, curved, bold, italic,
    underline, lineSpacing, noShapeData, noLink, alignLeft, alignRight,
    alignTop, alignBottom, alignCenterH, alignCenterV, alignLeftPage,
    alignRightPage, alignTopPage, alignBottomPage, distributeH, distributeV,
    sameSize, sameWidth, sameHeight, grid, background, backgroundPage, theme,
    paperSize, portrait, landscape, noneDefault, custom, zoomIn, zoomOut,
    findShapesHint, replaceWithHint, replace, replaceAll, previous, next,
    renameLayer, name, value, addProperty, remove, noLayersYet, visible,
    locked, print_, assignSelection, deleteLayer, addLayer,
    addLayerWithSelection, labelOptional, removeLink, link, noShapeDataHint,
    linkHint, sg_General, sg_Flowchart, sg_Arrows, sg_Basic, sg_Containers,
    sg_UML, sg_ER, sg_BPMN, sg_Misc, sg_Advanced,
) -> dict[str, str]:
    d = {
        "cancel": cancel, "ok": ok, "apply": apply, "close": close,
        "delete": delete, "rename": rename, "discard": discard, "none": none,
        "enabled": enabled, "untitled": untitled, "undo": undo, "redo": redo,
        "outline": outline, "rulers": rulers, "toggleGrid": toggleGrid,
        "fitToWindow": fitToWindow,
        "fitToWindowShortcut": shortcut(fitToWindow, "(⇧⌘H)"),
        "layers": layers, "insertImage": insertImage,
        "hideOutline": hideOutline, "selectAll": selectAll,
        "selectAllShortcut": shortcut(selectAll, "(Cmd+A)"),
        "find": find, "findShortcut": shortcut(find, "(Cmd+F)"),
        "findReplace": findReplace,
        "findReplaceShortcut": shortcut(findReplace, "(Cmd+H)"),
        "editData": editData, "editDataShortcut": shortcut(editData, "(Cmd+M)"),
        "editLink": editLink, "editLinkShortcut": shortcut(editLink, "(Cmd+K)"),
        "editConnectionPoints": editConnectionPoints,
        "doneEditingConnectionPoints": doneEditingConnectionPoints,
        "lock": lock, "unlock": unlock,
        "lockShortcut": shortcut(lock, "(Cmd+L)"),
        "unlockShortcut": shortcut(unlock, "(Cmd+L)"),
        "zoomToSelection": zoomToSelection, "copyStyle": copyStyle,
        "copyStyleShortcut": shortcut(copyStyle, "(Cmd+Alt+C)"),
        "pasteStyle": pasteStyle,
        "pasteStyleShortcut": shortcut(pasteStyle, "(Cmd+Alt+V)"),
        "saveAs": saveAs, "exportSvg": exportSvg, "exportPng": exportPng,
        "exportPdf": exportPdf, "snapToGrid": snapToGrid,
        "lineJumps": lineJumps, "closeTab": closeTab,
        "closeTabShortcut": shortcut(closeTab, "(Cmd+W)"),
        "cut": cut, "copy": copy, "paste": paste, "pasteHere": pasteHere,
        "duplicate": duplicate, "clearWaypoints": clearWaypoints,
        "bringToFront": bringToFront, "sendToBack": sendToBack,
        "bringForward": bringForward, "sendBackward": sendBackward,
        "bringForwardShortcut": shortcut(bringForward, "(Cmd+])"),
        "sendBackwardShortcut": shortcut(sendBackward, "(Cmd+[)"),
        "group": group, "ungroup": ungroup,
        "groupShortcut": shortcut(group, "(Cmd+G)"),
        "editText": editText, "replaceImage": replaceImage,
        "addLane": addLane, "removeLane": removeLane, "addRow": addRow,
        "addColumn": addColumn, "deleteRow": deleteRow,
        "deleteColumn": deleteColumn, "mergeCells": mergeCells,
        "unmergeCells": unmergeCells, "clearGuides": clearGuides,
        "toolSelect": toolSelect, "toolRectangle": toolRectangle,
        "toolEllipse": toolEllipse, "toolLine": toolLine,
        "toolConnector": toolConnector, "toolFreehand": toolFreehand,
        "toolText": toolText, "moreShapes": moreShapes,
        "searchShapes": searchShapes, "categoriesCount": categoriesCount,
        "expandAll": expandAll, "collapseAll": collapseAll,
        "addPage": addPage, "duplicatePage": duplicatePage,
        "deletePage": deletePage, "renamePage": renamePage,
        "pageNameHint": pageNameHint, "pageReorderHint": pageReorderHint,
        "backgroundPageReorderHint": backgroundPageReorderHint,
        "pageOf": pageOf, "unsaved": unsaved, "noSelection": noSelection,
        "selectedCount": selectedCount, "emptySubtitle": emptySubtitle,
        "newDrawing": newDrawing, "openVisioDrawing": openVisioDrawing,
        "orTrySample": orTrySample, "dropHint": dropHint,
        "discardUnsavedTitle": discardUnsavedTitle,
        "discardUnsavedBody": discardUnsavedBody, "savedTo": savedTo,
        "saveFailed": saveFailed, "exportedSvg": exportedSvg,
        "exportedPng": exportedPng, "exportedPdf": exportedPdf,
        "svgExportFailed": svgExportFailed, "pngExportFailed": pngExportFailed,
        "pngExportFailedError": pngExportFailedError,
        "pdfExportFailed": pdfExportFailed, "panelArrange": panelArrange,
        "panelAlign": panelAlign, "panelAlignToPage": panelAlignToPage,
        "panelFill": panelFill, "panelLine": panelLine,
        "panelConnector": panelConnector, "panelShadow": panelShadow,
        "panelGlow": panelGlow, "panelReflection": panelReflection,
        "panelSoftEdges": panelSoftEdges, "panelText": panelText,
        "panelImage": panelImage, "panelData": panelData,
        "panelLink": panelLink, "panelDiagram": panelDiagram,
        "panelView": panelView, "opacity": opacity, "size": size,
        "color": color, "rounded": rounded, "gradient": gradient,
        "linear": linear, "radial": radial, "start": start, "end": end,
        "blur": blur, "offsetX": offsetX, "offsetY": offsetY, "dist": dist,
        "solid": solid, "dashed": dashed, "dotted": dotted,
        "straight": straight, "orthogonal": orthogonal, "curved": curved,
        "bold": bold, "italic": italic, "underline": underline,
        "lineSpacing": lineSpacing, "noShapeData": noShapeData,
        "noLink": noLink, "alignLeft": alignLeft, "alignRight": alignRight,
        "alignTop": alignTop, "alignBottom": alignBottom,
        "alignCenterH": alignCenterH, "alignCenterV": alignCenterV,
        "alignLeftPage": alignLeftPage, "alignRightPage": alignRightPage,
        "alignTopPage": alignTopPage, "alignBottomPage": alignBottomPage,
        "distributeH": distributeH, "distributeV": distributeV,
        "sameSize": sameSize, "sameWidth": sameWidth, "sameHeight": sameHeight,
        "grid": grid, "background": background,
        "backgroundPage": backgroundPage, "theme": theme,
        "paperSize": paperSize, "portrait": portrait, "landscape": landscape,
        "noneDefault": noneDefault, "custom": custom, "zoomIn": zoomIn,
        "zoomOut": zoomOut, "findShapesHint": findShapesHint,
        "replaceWithHint": replaceWithHint, "replace": replace,
        "replaceAll": replaceAll, "previous": previous, "next": next,
        "renameLayer": renameLayer, "name": name, "value": value,
        "addProperty": addProperty, "remove": remove,
        "noLayersYet": noLayersYet, "visible": visible, "locked": locked,
        "print": print_, "assignSelection": assignSelection,
        "deleteLayer": deleteLayer, "addLayer": addLayer,
        "addLayerWithSelection": addLayerWithSelection,
        "labelOptional": labelOptional, "removeLink": removeLink,
        "link": link, "noShapeDataHint": noShapeDataHint, "linkHint": linkHint,
        "sg_General": sg_General, "sg_Flowchart": sg_Flowchart,
        "sg_Arrows": sg_Arrows, "sg_Basic": sg_Basic,
        "sg_Containers": sg_Containers, "sg_UML": sg_UML, "sg_ER": sg_ER,
        "sg_BPMN": sg_BPMN, "sg_Misc": sg_Misc, "sg_Advanced": sg_Advanced,
    }
    return d


# Import language banks from companion module to keep this file readable.
from editor_l10n_banks import UI_BANKS as _UI_BANKS  # type: ignore
from editor_l10n_banks import STENCIL_NAME_MAPS as _STENCIL_NAME_MAPS  # type: ignore

_STENCIL_BANKS: dict[str, dict[str, str]] = {}


def main() -> None:
    text = EDITOR_L10N.read_text()
    en = extract_map(text, "_en")
    zh = extract_map(text, "_zh")

    tables: dict[str, dict[str, str]] = {}
    for lang in LANGS:
        ui = build_ui(lang, en, zh)
        st = build_stencils(lang, en, zh)
        # Preserve insertion order: UI first then stencils
        merged = {**ui, **st}
        tables[lang] = merged
        print(f"{lang}: {len(merged)} keys (ui={len(ui)} st={len(st)})")

    parts = [
        "// GENERATED by tool/gen_editor_l10n.py — do not edit by hand.",
        "// ignore_for_file: prefer_single_quotes",
        "",
        "/// Editor UI string tables keyed by language code.",
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

    OUT.write_text("\n".join(parts))
    print("wrote", OUT, "bytes", OUT.stat().st_size)


if __name__ == "__main__":
    main()
