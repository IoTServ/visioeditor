# Changelog

All notable changes to **Editor for Visio Diagrams** are documented here.
The format loosely follows [Keep a Changelog]; versions follow SemVer.

## [Unreleased] — v0.1 (core editor, macOS-first)

### Added
- **Pure-Dart `.vsdx` engine** (`packages/vsdx`): OPC/XML reader → strongly-typed
  editable model → round-trip writer. Recovered and adapted from the MIT viewer
  stack (`visiovsdxviewer@0fcaf66^`).
- **Round-trip writer** (`load-preserve-patch`): patches only edited cells in
  `pageN.xml`, emits newly-created `<Shape>`s, removes deleted ones, and copies
  every other part (masters / theme / media / unknown) byte-for-byte, so
  formulas and structure survive a save.
- **Editor app (macOS)**: open `.vsdx` via file picker or drag & drop,
  multi-page tabs, pan / zoom canvas rendering through the recovered painter.
- **New drawing**: create a blank `.vsdx` from scratch (`emptyDocument`
  emit-from-scratch), Cmd+N / toolbar / empty-state button.
- **Editing**: select, move, resize (8 handles; geometry scales with the box),
  **rotate** (top handle), delete, snapshot-based undo / redo, duplicate,
  copy / paste (Cmd+C / Cmd+V).
- **Create shapes**: rectangle, ellipse, line (drag or click) with a dashed
  creation preview.
- **Shapes palette**: a stencil panel of flowchart shapes (process, terminator,
  decision, data, triangle, hexagon, pentagon, arrow) — click to drop one.
- **Connectors with glue**: connect two shapes; endpoints stay attached and
  auto-reroute (orthogonal elbow path) when a shape moves / resizes / rotates;
  `<Connects>` round-trip.
- **Style**: fill colour, line colour, line weight, no-fill / no-line
  (property panel).
- **Text**: double-click a shape to edit its text (plain text); the inspector
  formats the whole label — font size, bold / italic, colour and alignment
  (written back to the Character / Paragraph sections).
- **Save / Save As** with round-trip fidelity; unsaved-changes indicator.
- **Export**: to SVG (pure-model `VsdxToSvgSerializer`), PNG and multi-page PDF
  (rasterised via the on-screen painter).
- **Layers**: a panel to toggle layer visibility; the change round-trips
  (Visible/Lock/Print patched on the PageSheet in pages.xml).
- **Grid & snapping**: toggleable 0.25 in grid; create / resize snap to it.
- **Recent files** (persisted) and an **unsaved-changes guard** on close.
- **Multiple documents in tabs**: open several `.vsdx` files at once (top tab
  bar with dirty markers + close); drag-drop multiple files opens a tab each.
- **Multi-select**: Shift-click to toggle, rubber-band marquee to box-select
  (hold Space to pan); **align** (left/center/right/top/middle/bottom),
  **distribute** (horizontal/vertical) and **z-order** (bring to front / send
  to back) from the inspector.
- **Bundled sample drawings** (from the BSD `vsdx` project) openable from the
  empty state; the full set is copied to `packages/vsdx/test/fixtures/`.
- **Keyboard**: Cmd+N/O/W/S/Z/Shift+Z/D/C/V, Delete, Esc, and arrow keys to
  nudge the selection (by the grid step).

### Fixed
- The writer now regenerates a shape's `<Section N="Geometry">` when its
  geometry changed (resize scaling, connector re-routing), so edits survive a
  save/reopen instead of rendering with stale local geometry.

### Deferred (post-v0.1)
- Obstacle-avoiding connector routing; per-run (selection-range) rich-text
  editing; vector (non-raster) PDF; custom / imported stencils.
- Other platforms (Windows / Linux / Android / iOS) and legacy `.vsd` import
  (via libvisio); `.vsdx` OS file association, app icon and packaging/signing.
- LibreOffice / Visio interop is currently covered by our own open→save→reopen
  round-trip tests; `soffice` headless cross-conversion is pending a local
  LibreOffice install.

### Tested
- Engine: 26 unit tests (parse; model edit / immutability / structural sharing;
  connector re-routing incl. elbow; writer round-trip incl. create / delete /
  fill / rotate / connects / layer visibility / resized geometry / text
  formatting / polygon stencil / z-order; blank-document emit;
  geometry-scaling resize; SVG).
- App: `flutter analyze` clean; widget smoke test; `flutter build macos` OK.

[Keep a Changelog]: https://keepachangelog.com/en/1.1.0/
