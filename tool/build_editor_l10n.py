#!/usr/bin/env python3
"""Build editor_l10n_maps.dart for all AppLocalizations languages."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "lib/l10n/editor_l10n.dart"
OUT = ROOT / "lib/l10n/editor_l10n_maps.dart"
BANKS_JSON = Path("/tmp/all_banks.json")

LANGS = [
    "en", "zh", "ja", "ko", "es", "fr", "de", "pt", "ru", "it", "ar", "id",
    "hi", "nl", "tr", "pl", "vi", "th", "sv", "uk", "he", "cs", "ro", "el",
    "hu", "da", "ms", "fi", "nb", "sk", "bn", "fa", "bg", "hr", "ca", "fil",
    "sw",
]

STENCIL_FULL = {
    "zh", "ja", "ko", "es", "fr", "de", "pt", "ru", "it", "ar", "vi", "th",
    "id", "nl", "pl", "tr", "uk", "he", "hi",
    # Generated / adapted via tool/gen_stencil_maps.py
    "sv", "cs", "da", "ca", "fil", "sw", "ro", "el", "hu", "ms", "fi", "nb",
    "sk", "bn", "fa", "bg", "hr",
}


def extract_map(text: str, name: str) -> dict[str, str]:
    m = re.search(
        rf"static const Map<String, String> {name} = <String, String>\{{(.*?)\n  \}};",
        text,
        re.S,
    )
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
            match.group(2) if match.group(2) is not None else match.group(3)
        )
        for match in entry.finditer(body2)
    }


def dart_esc(s: str) -> str:
    return s.replace("\\", "\\\\").replace("'", "\\'")


def dart_map(var: str, data: dict[str, str]) -> str:
    lines = [f"const Map<String, String> {var} = <String, String>{{"]
    for k, v in data.items():
        lines.append(f"  '{dart_esc(k)}': '{dart_esc(v)}',")
    lines.append("};")
    return "\n".join(lines)


def sc(action: str, keys: str) -> str:
    return f"{action} ({keys})"


# Vocabulary-driven builder for languages not hand-authored in all_banks.json
def from_vocab(v: dict[str, str]) -> dict[str, str]:
    g = v.get
    ell = "…"
    return {
        "cancel": g("cancel"),
        "ok": g("ok"),
        "apply": g("apply"),
        "close": g("close"),
        "delete": g("delete"),
        "rename": g("rename"),
        "discard": g("discard"),
        "none": g("none"),
        "enabled": g("enabled"),
        "untitled": g("untitled"),
        "undo": g("undo"),
        "redo": g("redo"),
        "outline": g("outline"),
        "rulers": g("rulers"),
        "toggleGrid": g("toggleGrid"),
        "fitToWindow": g("fitToWindow"),
        "fitToWindowShortcut": sc(g("fitToWindow"), "⇧⌘H"),
        "layers": g("layers"),
        "insertImage": g("insertImage") + ell,
        "hideOutline": g("hideOutline"),
        "selectAll": g("selectAll"),
        "selectAllShortcut": sc(g("selectAll"), "Cmd+A"),
        "find": g("find") + ell,
        "findShortcut": sc(g("find") + ell, "Cmd+F"),
        "findReplace": g("findReplace") + ell,
        "findReplaceShortcut": sc(g("findReplace") + ell, "Cmd+H"),
        "editData": g("editData") + ell,
        "editDataShortcut": sc(g("editData") + ell, "Cmd+M"),
        "editLink": g("editLink") + ell,
        "editLinkShortcut": sc(g("editLink") + ell, "Cmd+K"),
        "editConnectionPoints": g("editConnectionPoints") + ell,
        "doneEditingConnectionPoints": g("doneEditingConnectionPoints"),
        "lock": g("lock"),
        "unlock": g("unlock"),
        "lockShortcut": sc(g("lock"), "Cmd+L"),
        "unlockShortcut": sc(g("unlock"), "Cmd+L"),
        "zoomToSelection": g("zoomToSelection"),
        "copyStyle": g("copyStyle"),
        "copyStyleShortcut": sc(g("copyStyle"), "Cmd+Alt+C"),
        "pasteStyle": g("pasteStyle"),
        "pasteStyleShortcut": sc(g("pasteStyle"), "Cmd+Alt+V"),
        "saveAs": g("saveAs") + ell,
        "exportSvg": g("exportSvg") + ell,
        "exportPng": g("exportPng") + ell,
        "exportPdf": g("exportPdf") + ell,
        "snapToGrid": g("snapToGrid"),
        "lineJumps": g("lineJumps"),
        "closeTab": g("closeTab"),
        "closeTabShortcut": sc(g("closeTab"), "Cmd+W"),
        "cut": g("cut"),
        "copy": g("copy"),
        "paste": g("paste"),
        "pasteHere": g("pasteHere"),
        "duplicate": g("duplicate"),
        "clearWaypoints": g("clearWaypoints"),
        "bringToFront": g("bringToFront"),
        "sendToBack": g("sendToBack"),
        "bringForward": g("bringForward"),
        "sendBackward": g("sendBackward"),
        "bringForwardShortcut": sc(g("bringForward"), "Cmd+]"),
        "sendBackwardShortcut": sc(g("sendBackward"), "Cmd+["),
        "group": g("group"),
        "ungroup": g("ungroup"),
        "groupShortcut": sc(g("group"), "Cmd+G"),
        "editText": g("editText") + ell,
        "replaceImage": g("replaceImage") + ell,
        "addLane": g("addLane"),
        "removeLane": g("removeLane"),
        "addRow": g("addRow"),
        "addColumn": g("addColumn"),
        "deleteRow": g("deleteRow"),
        "deleteColumn": g("deleteColumn"),
        "mergeCells": g("mergeCells"),
        "unmergeCells": g("unmergeCells"),
        "clearGuides": g("clearGuides"),
        "toolSelect": g("toolSelect"),
        "toolRectangle": g("rectangle"),
        "toolEllipse": g("ellipse"),
        "toolLine": g("line"),
        "toolConnector": g("toolConnector"),
        "toolFreehand": g("toolFreehand"),
        "toolText": g("text"),
        "moreShapes": g("moreShapes"),
        "searchShapes": g("searchShapes"),
        "categoriesCount": g("categoriesCount"),
        "expandAll": g("expandAll"),
        "collapseAll": g("collapseAll"),
        "addPage": g("addPage"),
        "duplicatePage": g("duplicatePage"),
        "deletePage": g("deletePage"),
        "renamePage": g("renamePage"),
        "pageNameHint": g("pageNameHint"),
        "pageReorderHint": g("pageReorderHint"),
        "backgroundPageReorderHint": g("backgroundPageReorderHint"),
        "pageOf": g("pageOf"),
        "unsaved": g("unsaved"),
        "noSelection": g("noSelection"),
        "selectedCount": g("selectedCount"),
        "emptySubtitle": g("emptySubtitle"),
        "newDrawing": g("newDrawing"),
        "openVisioDrawing": g("openVisioDrawing"),
        "orTrySample": g("orTrySample"),
        "dropHint": g("dropHint"),
        "discardUnsavedTitle": g("discardUnsavedTitle"),
        "discardUnsavedBody": g("discardUnsavedBody"),
        "savedTo": g("savedTo"),
        "saveFailed": g("saveFailed"),
        "exportedSvg": g("exportedSvg"),
        "exportedPng": g("exportedPng"),
        "exportedPdf": g("exportedPdf"),
        "svgExportFailed": g("svgExportFailed"),
        "pngExportFailed": g("pngExportFailed"),
        "pngExportFailedError": g("pngExportFailedError"),
        "pdfExportFailed": g("pdfExportFailed"),
        "panelArrange": g("panelArrange"),
        "panelAlign": g("panelAlign"),
        "panelAlignToPage": g("panelAlignToPage"),
        "panelFill": g("panelFill"),
        "panelLine": g("line"),
        "panelConnector": g("connector"),
        "panelShadow": g("panelShadow"),
        "panelGlow": g("panelGlow"),
        "panelReflection": g("panelReflection"),
        "panelSoftEdges": g("panelSoftEdges"),
        "panelText": g("text"),
        "panelImage": g("image"),
        "panelData": g("data"),
        "panelLink": g("link"),
        "panelDiagram": g("panelDiagram"),
        "panelView": g("panelView"),
        "opacity": g("opacity"),
        "size": g("size"),
        "color": g("color"),
        "rounded": g("rounded"),
        "gradient": g("gradient"),
        "linear": g("linear"),
        "radial": g("radial"),
        "start": g("start"),
        "end": g("end"),
        "blur": g("blur"),
        "offsetX": g("offsetX"),
        "offsetY": g("offsetY"),
        "dist": g("dist"),
        "solid": g("solid"),
        "dashed": g("dashed"),
        "dotted": g("dotted"),
        "straight": g("straight"),
        "orthogonal": g("orthogonal"),
        "curved": g("curved"),
        "bold": g("bold"),
        "italic": g("italic"),
        "underline": g("underline"),
        "lineSpacing": g("lineSpacing"),
        "noShapeData": g("noShapeData"),
        "noLink": g("noLink"),
        "alignLeft": g("alignLeft"),
        "alignRight": g("alignRight"),
        "alignTop": g("alignTop"),
        "alignBottom": g("alignBottom"),
        "alignCenterH": g("alignCenterH"),
        "alignCenterV": g("alignCenterV"),
        "alignLeftPage": g("alignLeftPage"),
        "alignRightPage": g("alignRightPage"),
        "alignTopPage": g("alignTopPage"),
        "alignBottomPage": g("alignBottomPage"),
        "distributeH": g("distributeH"),
        "distributeV": g("distributeV"),
        "sameSize": g("sameSize"),
        "sameWidth": g("sameWidth"),
        "sameHeight": g("sameHeight"),
        "grid": g("grid"),
        "background": g("background"),
        "backgroundPage": g("backgroundPage"),
        "theme": g("theme"),
        "paperSize": g("paperSize"),
        "portrait": g("portrait"),
        "landscape": g("landscape"),
        "noneDefault": g("noneDefault"),
        "custom": g("custom"),
        "zoomIn": g("zoomIn"),
        "zoomOut": g("zoomOut"),
        "findShapesHint": g("findShapesHint") + ell,
        "replaceWithHint": g("replaceWithHint") + ell,
        "replace": g("replace"),
        "replaceAll": g("replaceAll"),
        "previous": g("previous"),
        "next": g("next"),
        "renameLayer": g("renameLayer"),
        "name": g("name"),
        "value": g("value"),
        "addProperty": g("addProperty"),
        "remove": g("remove"),
        "noLayersYet": g("noLayersYet"),
        "visible": g("visible"),
        "locked": g("locked"),
        "print": g("print"),
        "assignSelection": g("assignSelection"),
        "deleteLayer": g("deleteLayer"),
        "addLayer": g("addLayer"),
        "addLayerWithSelection": g("addLayerWithSelection"),
        "labelOptional": g("labelOptional"),
        "removeLink": g("removeLink"),
        "link": g("link"),
        "noShapeDataHint": g("noShapeDataHint"),
        "linkHint": g("linkHint"),
        "sg_General": g("sg_General"),
        "sg_Flowchart": g("sg_Flowchart"),
        "sg_Arrows": g("sg_Arrows"),
        "sg_Basic": g("sg_Basic"),
        "sg_Containers": g("sg_Containers"),
        "sg_UML": "UML",
        "sg_ER": "ER",
        "sg_BPMN": "BPMN",
        "sg_Misc": g("sg_Misc"),
        "sg_Advanced": g("sg_Advanced"),
        # NEW2 keys (may be absent in compact vocabs — caller merges)
        "ungroupShortcut": g("ungroupShortcut"),
        "flipHorizontal": g("flipHorizontal"),
        "flipVertical": g("flipVertical"),
        "rotateLeft90": g("rotateLeft90"),
        "rotateRight90Shortcut": g("rotateRight90Shortcut"),
        "centerHorizontally": g("centerHorizontally"),
        "centerHorizontallyPage": g("centerHorizontallyPage"),
        "centerVertically": g("centerVertically"),
        "centerVerticallyPage": g("centerVerticallyPage"),
        "justify": g("justify"),
        "spaceBefore": g("spaceBefore"),
        "spaceAfter": g("spaceAfter"),
        "dropToOpen": g("dropToOpen"),
        "openFileFailed": g("openFileFailed"),
        "openPathFailed": g("openPathFailed"),
        "openExampleFailed": g("openExampleFailed"),
        "insertImageFailed": g("insertImageFailed"),
        "replacedWith": g("replacedWith"),
        "insertedNamed": g("insertedNamed"),
        "strikethrough": g("strikethrough"),
        "dashDot": g("dashDot"),
        "compoundSingle": g("compoundSingle"),
        "compoundDouble": g("compoundDouble"),
        "compoundThickThin": g("compoundThickThin"),
        "compoundThinThick": g("compoundThinThick"),
        "arrowFilled": g("arrowFilled"),
        "arrowOpen": g("arrowOpen"),
        "arrowThin": g("arrowThin"),
        "arrowStealth": g("arrowStealth"),
        "arrowCircle": g("arrowCircle"),
        "arrowOpenDiamond": g("arrowOpenDiamond"),
        "arrowCircleOpen": g("arrowCircleOpen"),
        "arrowNumbered": g("arrowNumbered"),
        "defaultFont": g("defaultFont"),
        "noResults": g("noResults"),
        "matchCaseOn": g("matchCaseOn"),
        "matchCaseOff": g("matchCaseOff"),
        "wholeWordOn": g("wholeWordOn"),
        "wholeWordOff": g("wholeWordOff"),
        "previousShortcut": g("previousShortcut"),
        "nextShortcut": g("nextShortcut"),
        "hideReplace": g("hideReplace"),
        "showReplaceShortcut": g("showReplaceShortcut"),
        "closeEsc": g("closeEsc"),
        "backgroundPageHint": g("backgroundPageHint"),
        "useBackground": g("useBackground"),
        "willMarkBackground": g("willMarkBackground"),
        "corners": g("corners"),
        "jumpRadius": g("jumpRadius"),
        "patternBrick": g("patternBrick"),
        "patternShingle": g("patternShingle"),
    }


# Compact vocabularies for remaining languages (keys used by from_vocab).
VOCABS: dict[str, dict[str, str]] = {
    "pt": {
        "cancel": "Cancelar", "ok": "OK", "apply": "Aplicar", "close": "Fechar",
        "delete": "Eliminar", "rename": "Mudar o nome", "discard": "Descartar",
        "none": "Nenhum", "enabled": "Ativado", "untitled": "Sem título",
        "undo": "Anular", "redo": "Refazer", "outline": "Esquema", "rulers": "Réguas",
        "toggleGrid": "Mostrar/ocultar grelha", "fitToWindow": "Ajustar à janela",
        "layers": "Camadas", "insertImage": "Inserir imagem", "hideOutline": "Ocultar esquema",
        "selectAll": "Selecionar tudo", "find": "Localizar", "findReplace": "Localizar e substituir",
        "editData": "Editar dados", "editLink": "Editar ligação",
        "editConnectionPoints": "Editar pontos de ligação",
        "doneEditingConnectionPoints": "Concluir edição dos pontos de ligação",
        "lock": "Bloquear", "unlock": "Desbloquear", "zoomToSelection": "Zoom para a seleção",
        "copyStyle": "Copiar estilo", "pasteStyle": "Colar estilo", "saveAs": "Guardar como",
        "exportSvg": "Exportar como SVG", "exportPng": "Exportar como PNG", "exportPdf": "Exportar como PDF",
        "snapToGrid": "Ajustar à grelha", "lineJumps": "Saltos de linha", "closeTab": "Fechar separador",
        "cut": "Cortar", "copy": "Copiar", "paste": "Colar", "pasteHere": "Colar aqui",
        "duplicate": "Duplicar", "clearWaypoints": "Limpar pontos de passagem",
        "bringToFront": "Trazer para a frente", "sendToBack": "Enviar para trás",
        "bringForward": "Avançar", "sendBackward": "Recuar", "group": "Agrupar", "ungroup": "Desagrupar",
        "editText": "Editar texto", "replaceImage": "Substituir imagem", "addLane": "Adicionar faixa",
        "removeLane": "Remover faixa", "addRow": "Adicionar linha", "addColumn": "Adicionar coluna",
        "deleteRow": "Eliminar linha", "deleteColumn": "Eliminar coluna", "mergeCells": "Unir células",
        "unmergeCells": "Separar células", "clearGuides": "Limpar guias",
        "toolSelect": "Selecionar / mover", "rectangle": "Retângulo", "ellipse": "Elipse", "line": "Linha",
        "toolConnector": "Conector (colar)", "toolFreehand": "Mão livre", "text": "Texto",
        "moreShapes": "Mais formas", "searchShapes": "Pesquisar formas",
        "categoriesCount": "{n} categorias", "expandAll": "Expandir tudo", "collapseAll": "Fechar tudo",
        "addPage": "Adicionar página", "duplicatePage": "Duplicar página", "deletePage": "Eliminar página",
        "renamePage": "Mudar o nome da página", "pageNameHint": "Nome da página",
        "pageReorderHint": "Arrastar para reordenar · Duplo clique para mudar o nome",
        "backgroundPageReorderHint": "Página de fundo · Arrastar para reordenar · Duplo clique para mudar o nome",
        "pageOf": "Página {current} de {total}", "unsaved": "Não guardado", "noSelection": "Nenhuma seleção",
        "selectedCount": "{n} selecionados",
        "emptySubtitle": "Crie um novo desenho ou arraste e largue / abra ficheiros .vsdx (cada um abre no próprio separador).",
        "newDrawing": "Novo desenho", "openVisioDrawing": "Abrir desenho Visio", "orTrySample": "Ou experimente um exemplo:",
        "dropHint": "Largue um ficheiro Visio ou uma imagem", "discardUnsavedTitle": "Descartar alterações não guardadas?",
        "discardUnsavedBody": "“{name}” tem alterações não guardadas.", "savedTo": "Guardado em {path}",
        "saveFailed": "Falha ao guardar: {error}", "exportedSvg": "SVG exportado para {path}",
        "exportedPng": "PNG exportado para {path}", "exportedPdf": "PDF exportado para {path}",
        "svgExportFailed": "Falha na exportação SVG: {error}", "pngExportFailed": "Falha na exportação PNG",
        "pngExportFailedError": "Falha na exportação PNG: {error}", "pdfExportFailed": "Falha na exportação PDF: {error}",
        "panelArrange": "Organizar", "panelAlign": "Alinhar", "panelAlignToPage": "Alinhar à página",
        "panelFill": "Preenchimento", "connector": "Conector", "panelShadow": "Sombra", "panelGlow": "Brilho",
        "panelReflection": "Reflexo", "panelSoftEdges": "Limites suaves", "image": "Imagem", "data": "Dados",
        "link": "Ligação", "panelDiagram": "Diagrama", "panelView": "Ver", "opacity": "Opacidade",
        "size": "Tamanho", "color": "Cor", "rounded": "Arredondado", "gradient": "Gradiente",
        "linear": "Linear", "radial": "Radial", "start": "Início", "end": "Fim", "blur": "Desfoque",
        "offsetX": "Deslocamento X", "offsetY": "Deslocamento Y", "dist": "Dist.", "solid": "Contínua",
        "dashed": "Tracejada", "dotted": "Pontilhada", "straight": "Reta", "orthogonal": "Ortogonal",
        "curved": "Curva", "bold": "Negrito", "italic": "Itálico", "underline": "Sublinhado",
        "lineSpacing": "Espaçamento entre linhas", "noShapeData": "Sem dados da forma", "noLink": "Sem ligação",
        "alignLeft": "Alinhar à esquerda", "alignRight": "Alinhar à direita", "alignTop": "Alinhar ao topo",
        "alignBottom": "Alinhar à base", "alignCenterH": "Centrar horizontalmente", "alignCenterV": "Centrar verticalmente",
        "alignLeftPage": "Esquerda da página", "alignRightPage": "Direita da página", "alignTopPage": "Topo da página",
        "alignBottomPage": "Base da página", "distributeH": "Distribuir horizontalmente",
        "distributeV": "Distribuir verticalmente", "sameSize": "Mesmo tamanho", "sameWidth": "Mesma largura",
        "sameHeight": "Mesma altura", "grid": "Grelha", "background": "Fundo", "backgroundPage": "Página de fundo",
        "theme": "Tema", "paperSize": "Tamanho do papel", "portrait": "Vertical", "landscape": "Horizontal",
        "noneDefault": "Nenhum (predefinição)", "custom": "Personalizado", "zoomIn": "Aumentar zoom",
        "zoomOut": "Diminuir zoom", "findShapesHint": "Localizar formas", "replaceWithHint": "Substituir por",
        "replace": "Substituir", "replaceAll": "Tudo", "previous": "Anterior", "next": "Seguinte",
        "renameLayer": "Mudar o nome da camada", "name": "Nome", "value": "Valor",
        "addProperty": "Adicionar propriedade", "remove": "Remover",
        "noLayersYet": "Ainda não há camadas. Adicione uma para organizar formas (visibilidade / bloqueio / impressão).",
        "visible": "Visível", "locked": "Bloqueada", "print": "Imprimir", "assignSelection": "Atribuir sel.",
        "deleteLayer": "Eliminar camada", "addLayer": "Adicionar camada",
        "addLayerWithSelection": "Adicionar camada (com seleção)", "labelOptional": "Etiqueta (opcional)",
        "removeLink": "Remover ligação", "noShapeDataHint": "Sem dados da forma. Adicione uma propriedade para começar.",
        "linkHint": "https://example.com  ou  #Page-2",
        "sg_General": "Geral", "sg_Flowchart": "Fluxograma", "sg_Arrows": "Setas", "sg_Basic": "Básico",
        "sg_Containers": "Contentores", "sg_Misc": "Diversos", "sg_Advanced": "Avançado",
    },
}

# Import extended vocabs from companion if present
_ext = Path(__file__).with_name("editor_vocabs.json")
if _ext.exists():
    VOCABS.update(json.loads(_ext.read_text()))


def translate_stencils(lang: str, en_st: dict[str, str], zh_st: dict[str, str], name_maps: dict) -> dict[str, str]:
    if lang == "en":
        return dict(en_st)
    if lang == "zh":
        return dict(zh_st)
    nm = name_maps.get(lang) or {}
    if not nm:
        # Missing stencil maps fall back to English via EditorL10n.
        return {}
    return {k: nm.get(eng, eng) for k, eng in en_st.items()}


def main() -> None:
    src = SRC.read_text()
    en_all = extract_map(src, "_en")
    zh_all = extract_map(src, "_zh")
    en_ui = {k: v for k, v in en_all.items() if not k.startswith("st_")}
    en_st = {k: v for k, v in en_all.items() if k.startswith("st_")}
    zh_st = {k: v for k, v in zh_all.items() if k.startswith("st_")}

    banks = json.loads(BANKS_JSON.read_text()) if BANKS_JSON.exists() else {}
    # Ensure en/zh from source of truth
    banks["en"] = en_ui
    banks["zh"] = {k: zh_all[k] for k in en_ui}

    name_maps_path = Path("/tmp/stencil_name_maps.json")
    name_maps = json.loads(name_maps_path.read_text()) if name_maps_path.exists() else {}

    # Fill missing langs from vocab
    for lang in LANGS:
        if lang in banks:
            continue
        if lang not in VOCABS:
            raise SystemExit(f"Missing vocab/bank for {lang}")
        banks[lang] = from_vocab(VOCABS[lang])
        # validate
        miss = [k for k in en_ui if k not in banks[lang]]
        if miss:
            raise SystemExit(f"{lang} missing {len(miss)}: {miss[:10]}")

    tables: dict[str, dict[str, str]] = {}
    for lang in LANGS:
        ui = banks[lang]
        st = translate_stencils(lang, en_st, zh_st, name_maps)
        tables[lang] = {**ui, **st}
        print(f"{lang}: {len(tables[lang])} (ui={len(ui)} st={len(st)})")

    parts = [
        "// GENERATED by tool/build_editor_l10n.py — do not edit by hand.",
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
    OUT.write_text("\n".join(parts))
    print("wrote", OUT, OUT.stat().st_size)


if __name__ == "__main__":
    main()
