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
  straight or orthogonal, with draggable waypoints); right-click a connector
  segment or waypoint to add, remove or clear routing points. Drop flowchart
  shapes from the stencil palette, or double-click blank canvas to open the
  common-shape picker. Drag from a shape's directional arrow to start a fixed
  connector; hold Alt/Option while dropping an endpoint inside a shape to add
  a custom fixed connection point, or Shift to force floating perimeter glue.
  Labelled connectors expose a yellow diamond handle for freely positioning
  their label and a circular handle for rotating the label independently
  (Shift snaps to 15° increments), both with one-step undo.
  Hold Ctrl/Cmd while dragging a directional arrow to clone the shape at any
  drop point and connect it. Alt+Shift+Arrow also clones/connects in any
  direction.
- **Create with AI** using the built-in multi-turn diagram assistant. Configure
  OpenAI-compatible, Anthropic, Gemini or local Ollama engines, discuss and
  revise a process, then open the validated Diagram Spec or Mermaid result as
  an editable `.vsdx` tab. The Settings guide also documents Agent live
  preview, MCP, CLI and Agent Skill workflows.
- **Edit** with select / move / resize (8 handles) / rotate, duplicate,
  copy-paste, delete, snapshot undo-redo, grid snapping and arrow-key nudging.
  Ctrl/Cmd-drag clones; Alt/Option temporarily disables snapping for precise
  shape, waypoint and ruler-guide edits (on connector endpoints it creates a
  custom fixed point when dropped inside a shape). Ctrl/Cmd+Shift+Arrow adjusts
  size and Alt+Shift+R clears connector waypoints. Cmd/Ctrl+Shift+Y fits
  selected shapes to their wrapped text. Shift-clicking the Format-panel trash
  button removes a shape together with its incident connectors; plain Delete
  keeps them as floating lines.
- **Arrange** with multi-select (Shift/Ctrl/Cmd-click, enclosed marquee, or
  Alt-marquee for intersecting items), Alt-click cycling through overlaps,
  Alt+Shift-click deselection,
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
  Shift-wheel scrolls horizontally. Right-button and middle-button dragging
  temporarily pans the canvas without changing tools or moving shapes, while a
  stationary right-click still opens the context menu. Alt+Shift-drag from
  blank canvas remotely moves the selection; adding Ctrl/Cmd displaces shapes
  across horizontal and vertical area cuts, while an Alt+Shift marquee
  subtracts intersecting shapes.
  Tab/Shift+Tab traverses expanded container children and Alt+Tab selects their
  parent. Plain groups select/drag as a unit first, then repeated clicks drill
  into their children; Alt-click bypasses the group hierarchy. Right-click
  a flow-tree vertex to select its immediate children, whole subtree, parent
  or siblings. Whole-subtree selection includes the root and traversed edges.
  These commands follow Begin→End connector direction, fall back
  to nested group/container relationships, and use draw.io's contextual
  Alt+Shift+X/T/P/S shortcuts. Right-click
  a selected child or use the Arrange panel to **Remove from Group**, or drag
  the child beyond its group bounds. Foldable containers support context-menu
  Collapse / Expand and draw.io's Ctrl/Cmd+Home / Ctrl/Cmd+End shortcuts,
  including one-step multi-selection edits. Right-click blank canvas to select
  all edges or all vertices. Enter starts editing the single selected label;
  Ctrl/Cmd+Enter duplicates the selection, promoting a selected table cell to
  its whole row while a selected table remains a whole-table duplicate. Styles,
  nested contents and internal connections are preserved. Delete/Backspace
  removes the selected cell's row, or a column when all its visible cells are
  selected, without leaving a broken cell grid. Ctrl/Cmd+Delete or Backspace
  also removes incident connectors; Shift+Delete or Backspace clears labels
  without deleting shapes.
  A shape's context menu can Select Connections, and Clear Anchors changes
  fixed-point glue on selected or incident connectors back to automatic
  perimeter attachment without disconnecting either terminal.
  Connection Arrows and Connection Points can be toggled independently from
  the More menu or with Alt+Shift+A/O. Turning arrows off removes the
  quick-add/quick-connect hit regions; turning points off disables blue-point
  display and fixed-point snapping while ordinary perimeter glue remains
  available.
  Copy on Connect can also be enabled from the More menu: dragging a connection
  to empty canvas then clones the source at the drop point and connects it in
  one undo step. Collapse/Expand Controls independently hides fold chevrons and
  disables their click and keyboard commands without altering the drawing's
  stored collapsed state.
  Turn / Reverse now uses Cmd/Ctrl+R for both 90° shape turns and semantic
  connector reversal. Copy Data / Paste Data transfers complete Shape Data
  metadata; context-menu paste preserves target labels, while the draw.io
  Alt+Shift+B/E shortcuts also transfer the source label.
  Edit Tooltip adds undoable, persistent custom hover text from the More or
  shape context menu; the Extras Tooltips switch can hide it without deleting
  it from the drawing.
  Copy as Text places a selected shape's plain label on the system clipboard.
  Open Link is available from the context menu, More menu and Format panel:
  internal page anchors navigate inside the drawing and safe external targets
  open through the platform.
  Copy Text Style / Paste Text Style transfer only label typography and layout,
  preserving target text, shape appearance and text-box position. Copy Text
  Style uses Alt+Shift+C; both actions are available in the Text panel and
  selection menus.
  F2 also edits a selected label; Home restores a centred 100% view and
  Cmd/Ctrl+J or Cmd/Ctrl+Shift+H fits the current page. With no selection,
  Enter intelligently toggles between those reset and fitted views.
  Cmd/Ctrl+Shift+G/O/L toggle the grid, Outline and Layers panels, while
  Cmd/Ctrl+Shift+K toggles the Shapes sidebar.
  Clicking the live zoom percentage opens draw.io's 25%–400% presets,
  whole-page fit, Fit Page Width, and a validated custom-percentage dialog.
  Cmd/Ctrl+0 opens the same dialog, while Cmd/Ctrl +/- zooms globally even
  after focus has moved into app chrome.
- **Style & text** — fill / line colour, line weight, no-fill / no-line, line
  dash style, arrowheads, fill / line opacity, drop shadow, and text formatting
  (font family, size, bold / italic / underline, colour, horizontal + vertical
  alignment). The Text panel also toggles superscript/subscript and removes
  character formatting without changing paragraph layout. While inline
  editing, Cmd/Ctrl+. toggles superscript and Cmd/Ctrl+, toggles subscript for
  the selected range. Cmd/Ctrl+Shift+NumPad +/- adjusts the whole label by 1pt.
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
  step. Dropping a palette shape on a free connector endpoint shows a blue
  target and attaches it directly. Dropping it on a shape's directional arrow
  inserts the new neighbour and wires it in that direction in one undo step;
  Alt-drop disables these automatic connections.
  Alt-click places a shape beneath the lower-left of the current drawing, and
  Alt+Shift/Ctrl-click inserts and connects beside the selected shape.
- **Multi-page** documents: add / duplicate / delete / rename pages, and toggle
  layer visibility. With no shape selected, Ctrl/Cmd+Arrow selects the
  previous/next/first/last page and Shift+Arrow reorders the active page;
  Ctrl/Cmd+Shift+PageUp/PageDown also moves between adjacent pages. With a
  selected 2-D shape, Ctrl/Cmd+Arrow resizes it by 1pt.
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
| Save / Save As | `Cmd+S` / `Cmd+Shift+S` |
| Undo / Redo | `Cmd+Z` / `Cmd+Shift+Z` |
| Duplicate / Copy / Paste | `Cmd+D` / `Cmd+C` / `Cmd+V` |
| Delete selection | `Delete` / `Backspace` |
| Delete selection with incident connectors | `Cmd/Ctrl+Delete` / `Cmd/Ctrl+Backspace` |
| Clear selected labels | `Shift+Delete` / `Shift+Backspace` |
| Delete with connected lines | Hold `Shift` and click the Format-panel trash button |
| Edit selected label | `Enter` / `F2` |
| Smart Fit (no selection) | `Enter` |
| Duplicate selection (table cell → row) | `Cmd/Ctrl+Enter` |
| Delete table row / complete column selection | `Delete` / `Backspace` |
| Increase / decrease whole-label text | `Cmd/Ctrl+Shift+NumPad +/-` / `Cmd/Ctrl+}` / `{` |
| Superscript / subscript while editing | `Cmd/Ctrl+.` / `Cmd/Ctrl+,` |
| Set / clear default creation style | `Cmd/Ctrl+Shift+D` / `Cmd/Ctrl+Shift+R` (clear with no selection) |
| Show / hide Shapes sidebar | `Cmd/Ctrl+Shift+K` |
| Reset view to centred 100% / fit current page | `Home` / `Cmd/Ctrl+J` or `Cmd/Ctrl+Shift+H` |
| Custom zoom / zoom in / zoom out | `Cmd/Ctrl+0` / `Cmd/Ctrl++` / `Cmd/Ctrl+-` |
| Toggle grid / Outline / Layers | `Cmd/Ctrl+Shift+G` / `Cmd/Ctrl+Shift+O` / `Cmd/Ctrl+Shift+L` |
| Select connectors / vertices | `Cmd/Ctrl+Shift+E` / `Cmd/Ctrl+Shift+I` |
| Select tree children / subtree / parent / siblings | `Alt+Shift+X` / `Alt+Shift+T` / `Alt+Shift+P` / `Alt+Shift+S` |
| Copy Text Style / Copy Size / Paste Size | `Alt+Shift+C` / `Alt+Shift+F` / `Alt+Shift+V` |
| Edit Link / Edit Connection Points | `Alt+Shift+L` / `Alt+Shift+Q` |
| Toggle Connection Arrows / Connection Points | `Alt+Shift+A` / `Alt+Shift+O` |
| Bring forward / send backward one layer | `Cmd/Ctrl+Alt+Shift+F` / `Cmd/Ctrl+Alt+Shift+B` |
| Select previous/next/first/last page (no shape selection) | `Cmd/Ctrl+Left` / `Right` / `Up` / `Down` |
| Reorder current page (no shape selection) | `Shift+Left` / `Right` / `Up` / `Down` |
| Previous / next page | `Cmd/Ctrl+Shift+PageUp` / `PageDown` |
| Cancel tool / clear selection | `Esc` |
| Nudge selection | Arrow keys (by the grid step) |
| Resize selection | `Cmd/Ctrl+Arrow` (1pt) / `Cmd/Ctrl+Shift+Arrow` (grid step) |
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
