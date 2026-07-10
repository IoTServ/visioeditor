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
- **Connectors with glue**: connect two shapes; endpoints stay attached and
  auto-reroute when a shape moves / resizes / rotates; `<Connects>` round-trip.
- **Style**: fill colour, line colour, line weight, no-fill / no-line
  (property panel).
- **Text**: double-click a shape to edit its text (plain text).
- **Save / Save As** with round-trip fidelity; unsaved-changes indicator.
- **Export**: to SVG (pure-model `VsdxToSvgSerializer`) and PNG (rasterised via
  the on-screen painter).
- **Grid & snapping**: toggleable 0.25 in grid; create / resize snap to it.
- **Recent files** (persisted) and an **unsaved-changes guard** on close.
- **Multiple documents in tabs**: open several `.vsdx` files at once (top tab
  bar with dirty markers + close); drag-drop multiple files opens a tab each.
- **Multi-select**: Shift-click to toggle, rubber-band marquee to box-select
  (hold Space to pan); **align** (left/center/right/top/middle/bottom) and
  **distribute** (horizontal/vertical) from the inspector.
- **Bundled sample drawings** (from the BSD `vsdx` project) openable from the
  empty state; the full set is copied to `packages/vsdx/test/fixtures/`.
- **Keyboard**: Cmd+N/O/W/S/Z/Shift+Z/D/C/V, Delete, Esc.

### Deferred (post-v0.1)
- Advanced connector routing (elbow / avoidance); rich-text run editing.
- Other platforms (Windows / Linux / Android / iOS) and legacy `.vsd` import
  (via libvisio); `.vsdx` OS file association, app icon and packaging/signing.
- LibreOffice / Visio interop is currently covered by our own open→save→reopen
  round-trip tests; `soffice` headless cross-conversion is pending a local
  LibreOffice install.

### Tested
- Engine: 21 unit tests (parse; model edit / immutability / structural sharing;
  connector re-routing; writer round-trip incl. create / delete / fill /
  rotate / connects; blank-document emit; geometry-scaling resize; SVG).
- App: `flutter analyze` clean; widget smoke test; `flutter build macos` OK.

[Keep a Changelog]: https://keepachangelog.com/en/1.1.0/
