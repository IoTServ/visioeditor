# Editor for Visio Diagrams — v0.1.0 Release Notes

_A native, cross-platform Microsoft Visio (`.vsdx`) editor built with
Flutter / Dart. First release; **macOS desktop is the supported target**._

For the full, itemised change list see [`CHANGELOG.md`](./CHANGELOG.md); for the
roadmap and milestone status see [`PLAN.md`](./PLAN.md).

---

## Highlights

Unlike a read-only viewer, this editor round-trips real `.vsdx` files: it parses
the OPC/ZIP + XML into a strongly-typed, editable model and writes changes back
with a **load-preserve-patch** writer that only rewrites the cells you actually
edited — masters, themes, media and any unknown parts are copied back
byte-for-byte, so formulas and structure survive a save.

- **Open & render** `.vsdx` via file picker, drag & drop, Finder double-click /
  "Open With", or `open drawing.vsdx`. Multiple files open in their own tabs.
- **Create** rectangles, ellipses, lines and glued connectors (routable
  straight or orthogonal, with draggable waypoints); drop flowchart shapes from
  the stencil palette, or double-click blank canvas to open the common-shape
  picker. Alt+Shift+Arrow clones/connects in any direction.
- **Create with AI** using the built-in multi-turn diagram assistant. Configure
  OpenAI-compatible, Anthropic, Gemini or local Ollama engines, discuss and
  revise a process, then open the validated Diagram Spec or Mermaid result as
  an editable `.vsdx` tab. The Settings guide also documents Agent live
  preview, MCP, CLI and Agent Skill workflows.
- **Edit** with select / move / resize (8 handles) / rotate, duplicate,
  copy-paste, delete, snapshot undo-redo, grid snapping and arrow-key nudging.
  Ctrl/Cmd-drag clones; Alt/Option temporarily disables snapping for precise
  shape, connector and ruler-guide edits. Ctrl/Cmd+Shift+Arrow adjusts size and
  Alt+Shift+R clears connector waypoints. Cmd/Ctrl+Shift+Y fits selected shapes
  to their wrapped text. Shift-clicking the Format-panel trash button removes
  a shape together with its incident connectors; plain Delete keeps them as
  floating lines.
- **Arrange** with multi-select (Shift/Ctrl/Cmd-click, enclosed marquee, or
  Alt-marquee for intersecting items), Alt-click cycling through overlaps,
  align, distribute, same-size and copy/paste-size tools, two-shape position
  swapping, connector reversal,
  z-order (bring to front / send to back) and **group / ungroup**. Dragging
  shows **smart alignment guides** that snap to nearby shapes, equal spacing,
  connection points and the orange page centre; Guides can be toggled
  independently from the grid. Ctrl/Cmd-resizing a normal group changes only
  its outer frame; Shift-clicking a stencil replaces selected atomic shapes
  while preserving content, styling and connector glue.
- **drawio-style interactions**: a right-click context menu, copy / paste style,
  and matching keyboard shortcuts (Select All, Cut, To Front/Back, Group /
  Ungroup, keyboard zoom). Space-drag pans from anywhere; Alt-wheel zooms and
  Shift-wheel scrolls horizontally. Alt+Shift-drag from blank canvas remotely
  moves the selection; adding Ctrl/Cmd displaces shapes across horizontal and
  vertical area cuts, while an Alt+Shift marquee subtracts intersecting shapes.
  Tab/Shift+Tab traverses expanded container children and Alt+Tab selects their
  parent. Cmd/Ctrl+Shift+K toggles the Shapes sidebar.
- **Style & text** — fill / line colour, line weight, no-fill / no-line, line
  dash style, arrowheads, fill / line opacity, drop shadow, and text formatting
  (font family, size, bold / italic / underline, colour, horizontal + vertical
  alignment). Cmd/Ctrl+Shift+NumPad +/- adjusts the whole label by 1pt.
  Cmd/Ctrl+Shift+D remembers the selected shape or connector as the creation
  style; Cmd/Ctrl+Shift+R clears it when nothing is selected. Start typing with
  a shape or connector selected to replace its label; Enter saves and
  Shift/Alt+Enter adds a line break. Labels on 2-D shapes can be positioned
  outside any edge or centred, and displayed vertically.
- **Shape-library modifiers** — Shift-click replaces a compatible selection or
  inserts with the original white/black style; Shift-drag also ignores the
  custom default style. A plain drop on an atomic shape replaces it (or all
  compatible selected shapes) while preserving labels, styles and connector
  glue; the drop target is highlighted. Alt/Shift-drop disables replacement
  and container membership so shapes overlap. Clicking a palette shape while a
  connector with a free end is selected inserts and attaches it in one undo
  step. Alt-click places a shape beneath the lower-left of the current drawing,
  and Alt+Shift/Ctrl-click inserts and connects beside the selected shape.
- **Multi-page** documents: add / duplicate / delete / rename pages, and toggle
  layer visibility.
- **Save / Save As** with round-trip fidelity, plus **export** to SVG, PNG and
  multi-page PDF.
- Quality-of-life: recent files, unsaved-changes guard, a bottom status bar and
  a live zoom read-out, a brand app icon, and full keyboard shortcuts.

## Requirements

- **Flutter** stable (Dart `>= 3.12`) to build from source.
- **Runtime target:** macOS. Other desktop/mobile targets build from the same
  Flutter project but are not yet verified for this release.

## Install / run from source

```bash
flutter pub get
flutter run -d macos            # develop
flutter build macos             # release build → build/macos/Build/Products/
```

The produced app is named **"Editor for Visio Diagrams"** and registers the
Visio drawing file types (`.vsdx` / `.vsd` / `.vsdm` / `.vstx` / `.vstm` /
`.vssx` / `.vssm`) so Finder offers *Open With → Editor for Visio Diagrams*.
(Legacy `.vsd` opens via pure-Dart VSD5/VSD6/VSD11 import; Save As writes `.vsdx`.)

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| New / Open / Close tab | `Cmd+N` / `Cmd+O` / `Cmd+W` |
| Save | `Cmd+S` |
| Undo / Redo | `Cmd+Z` / `Cmd+Shift+Z` |
| Duplicate / Copy / Paste | `Cmd+D` / `Cmd+C` / `Cmd+V` |
| Delete selection | `Delete` / `Backspace` |
| Delete with connected lines | Hold `Shift` and click the Format-panel trash button |
| Increase / decrease whole-label text | `Cmd/Ctrl+Shift+NumPad +/-` |
| Set / clear default creation style | `Cmd/Ctrl+Shift+D` / `Cmd/Ctrl+Shift+R` (clear with no selection) |
| Show / hide Shapes sidebar | `Cmd/Ctrl+Shift+K` |
| Cancel tool / clear selection | `Esc` |
| Nudge selection | Arrow keys (by the grid step) |
| Pan / zoom canvas | Scroll to pan · `Cmd`/`Ctrl`+scroll to zoom · Space-drag to pan |

## Known limitations (deferred beyond v0.1)

- **No code signing / notarization.** The macOS build is unsigned; Gatekeeper
  will warn on first launch (right-click → Open). Signing requires an Apple
  Developer certificate and is planned for a later release.
- **macOS-first.** Windows / Linux / mobile are not yet verified; the OS file
  association is macOS-only.
- **Legacy `.vsd`** (Visio 5 / 2000–2010 binary): VSD5/VSD6/VSD11 import is supported
  (pure Dart: stencil inheritance, bitmaps, InfiniteLine/Spline/NURBS basics,
  TextField expand with date/numeric formats, unit/angle/currency formatting,
  multi-run CharIX/ParaIX, TabsData, Gantt Number date heuristic,
  CharIX Case/Pos/Strike/FontScale, EMF/WMF media import, ShapeList z-order,
  string field case formats, FontFace/FontIX, TextBlock, ParaIX, StyleSheet
  text chain, Layer, Multidimensional area, OLE media, EMF DIB paint,
  Name as field table, VSD5 TextField formats, CharList/ParaList/FieldList
  trailer reorder, DrawingUnits/PageUnits page default unit, OLE title metadata,
  Edraw-safe FillForegnd for solid fills, signed 1D Width/Height,
  FeetAndInches/fraction TextField formats, NameIDX shape/layer display names,
  Connection Points / Control handles / Shape Data / Scratch / User cells /
  Actions / Protection (locked) / Group behaviour / Hyperlink (`0xc4`) /
  Event (`0x84` OPENTEXTWIN / RUNADDONW) import;
  empty ConnectList (`0x72`) headers are skipped safely);
  Save As writes `.vsdx` only (legacy `.vsd` is import-only; no binary
  write-back). Encrypted files / masters deep edit remain deferred.
  EMF/WMF/OLE canvas paint uses embedded-DIB extraction plus vector
  metafile replay (WMF/EMF GDI records); exotic records may still fall
  back to a labelled placeholder.
- **Text editing applies to a whole shape label** (no per-character selection
  ranges yet); connectors route straight or orthogonal (with draggable
  waypoints) but not obstacle-avoiding; PDF export is SVG→PDF vector
  (with `pdfCompat` approximations for filters/patterns); formulas are
  preserved but not recomputed.
- Interop is proven by open → save → reopen round-trip tests and by CI
  LibreOffice `soffice --headless --convert-to pdf` on a writer `.vsdx`
  (`REQUIRE_SOFFICE=1` / job `libreoffice-crosscheck`; local runs skip when
  soffice is absent).

## Verification

- **Engine:** 30 pure-Dart unit tests (parse; model edit / immutability;
  connector re-routing; writer round-trips for create / delete / fill / rotate /
  connects / layers / geometry / text / stencils / z-order / page add-remove-
  rename; blank-document emit; SVG).
- **App:** `flutter analyze` clean; widget smoke test; `flutter build macos` OK.

---

_Licensed under the MIT License. See [`../LICENSE`](../LICENSE) and
[`../NOTICE`](../NOTICE) for attribution of recovered code, dependencies and
bundled sample drawings._
