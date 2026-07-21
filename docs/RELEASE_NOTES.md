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
  the stencil palette.
- **Edit** with select / move / resize (8 handles) / rotate, duplicate,
  copy-paste, delete, snapshot undo-redo, grid snapping and arrow-key nudging.
- **Arrange** with multi-select (shift-click + marquee), align, distribute,
  z-order (bring to front / send to back) and **group / ungroup**. Dragging
  shows **smart alignment guides** that snap to nearby shapes.
- **drawio-style interactions**: a right-click context menu, copy / paste style,
  and matching keyboard shortcuts (Select All, Cut, To Front/Back, Group /
  Ungroup, keyboard zoom).
- **Style & text** — fill / line colour, line weight, no-fill / no-line, line
  dash style, arrowheads, fill / line opacity, drop shadow, and text formatting
  (font family, size, bold / italic / underline, colour, horizontal + vertical
  alignment).
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
