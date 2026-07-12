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
- **Editing**: select, move, resize (8 handles; geometry scales with the box;
  **Shift** locks the aspect ratio, **Alt** resizes from the centre),
  **rotate** (top handle), delete, snapshot-based undo / redo, duplicate,
  copy / paste (Cmd+C / Cmd+V), and **Alt-drag to duplicate** on the canvas.
  Dragging snaps to the grid (and to neighbours); **Esc cancels an in-progress
  drag**, reverting it.
- **Create shapes**: rectangle, ellipse, line (drag or click) with a dashed
  creation preview. New shapes **inherit the last-used fill / line style**
  (drawio's `currentVertexStyle`).
- **Text tool** (drawio's "Text"): drop a borderless, fill-less text box that
  drops straight into in-place editing; an untyped box is discarded on commit
  or cancel. It can still be given a background or border afterwards.
- **Rounded rectangles**: a "Rounded" stencil plus a **corner-radius slider**
  in the inspector that rounds (or squares) any rectangle; corners are stored
  as `EllipticalArcTo` arcs and round-trip through the writer.
- **Shapes palette**: a stencil panel of flowchart shapes (process, rounded,
  terminator, decision, data, triangle, hexagon, pentagon, arrow) — click to
  drop one.
- **Connectors with glue**: connect two shapes; endpoints attach to the target
  shapes' edges and auto-reroute when a shape moves / resizes / rotates;
  `<Connects>` round-trip. New connectors carry a **default end arrowhead**
  (they point at their target). Each connector can be routed **straight or
  orthogonal** (inspector) and reshaped with draggable **waypoints** (bend
  points: drag a segment midpoint to add one, drag it to move, double-click to
  remove); the routing choice and waypoints are kept across re-routes.
- **Edge labels**: double-click a connector to label it; the text is drawn
  centred on the route's midpoint (drawio-style) with a page-coloured backing
  for legibility, and the in-place editor opens right there.
- **Hover-to-connect** (drawio HoverIcons): hovering a shape in select mode
  shows directional connect arrows around it; drag one out to wire a new
  connector — dropping on another shape glues both ends, dropping on empty
  canvas leaves a loose end. The shape the connector would glue to is
  highlighted while wiring (also with the connector tool).
- **Style**: fill colour, line colour, line weight, no-fill / no-line, plus a
  drawio-style Format panel — **line dash** (solid / dashed / dotted / dash-dot),
  **arrowhead types** (selectable start / end heads with previews: filled, open,
  thin, stealth, diamond, circle …), **fill / line opacity** sliders, and a
  **drop shadow** toggle. All round-trip (`LinePattern` / `BeginArrow` /
  `EndArrow` / `FillForegndTrans` / `LineColorTrans` / `ShadowPattern`).
- **Arrange panel** (drawio-style): numeric **position / size** (X / Y / W / H,
  in inches, top-left anchored) and **rotation** (degrees) for a single
  selection; **flip horizontal / vertical**; **rotate 90°** either way
  (Cmd+R / Cmd+Shift+R); and one-step **bring forward / send backward** in
  addition to to-front / to-back. All round-trip (`PinX/PinY/Width/Height/Angle`,
  `FlipX/FlipY`, `<Shape>` reorder).
- **Find** (drawio Cmd+F): a floating search bar that filters shapes on the
  current page by text/name, shows a match counter, and cycles matches
  (Enter / Shift+Enter or the arrows), selecting and scrolling each into view.
  **Zoom to selection** fits the current selection to the window.
- **Text**: double-click a shape to edit its label **in place on the canvas**
  — an editor overlays the shape (positioned and scaled to its box); Enter
  inserts a newline, Cmd/Ctrl+Enter or clicking away applies, Esc cancels. The
  inspector formats the whole label — **font family**, size, bold / italic /
  **underline**, colour, and **horizontal + vertical alignment** (written back
  to the Character / Paragraph sections and the `VerticalAlign` cell).
- **Save / Save As** with round-trip fidelity; unsaved-changes indicator.
- **Export**: to SVG (pure-model `VsdxToSvgSerializer`), PNG and multi-page PDF
  (rasterised via the on-screen painter).
- **Pages**: add / duplicate / delete / rename pages from the page bar; all
  round-trip (the writer adds/removes the page part, relationship and
  content-type override, matching pages by id).
- **Layers**: a panel to toggle layer visibility; the change round-trips
  (Visible/Lock/Print patched on the PageSheet in pages.xml).
- **Grid & snapping**: toggleable 0.25 in grid; create / resize snap to it.
- **Recent files** (persisted) and an **unsaved-changes guard** on close.
- **Multiple documents in tabs**: open several `.vsdx` files at once (top tab
  bar with dirty markers + close); drag-drop multiple files opens a tab each.
- **Multi-select**: Shift-click to toggle, rubber-band marquee to box-select
  (hold Space to pan); **align** (left/center/right/top/middle/bottom),
  **distribute** (horizontal/vertical) and **z-order** (to front / back and one
  step forward / backward) from the inspector. Hold **Shift while dragging** to
  constrain the move to one axis.
- **Smart alignment guides** (drawio-style): dragging a shape snaps its edges
  and centre to nearby shapes and draws magenta guide lines to what it lined
  up with.
- **Right-click context menu**: cut / copy / paste / duplicate / delete, bring
  to front / send to back, group / ungroup, copy & paste style, edit text; on
  empty canvas, paste / select all / fit to window.
- **Copy / paste style** (drawio "Copy Style" / "Paste Style"): lift the fill,
  line and text formatting off one shape and apply it to others.
- **Group / ungroup** (drawio "Group" / "Ungroup"): combine the selected
  top-level shapes into a group (members become group-local, Visio's group
  coordinate convention) and ungroup back to page-absolute coordinates; both
  round-trip through the writer (which reparents the `<Shape>` subtree).
- **Bundled sample drawings** (from the BSD `vsdx` project) openable from the
  empty state; the full set is copied to `packages/vsdx/test/fixtures/`.
- **Keyboard**: Cmd+N/O/W/S/Z/Shift+Z/D/C/V/X/A, Cmd+Shift+F/B (to front/back),
  Cmd+G / Cmd+Shift+U (group / ungroup), Cmd+Alt+C/V (copy/paste style),
  Cmd+R / Cmd+Shift+R (rotate 90°), Cmd+F (find), Delete, Esc, arrow keys to
  nudge the selection, and canvas zoom (Cmd +/- , Cmd+0 = 100%,
  Cmd+Shift+H = fit).
- **macOS document integration**: the app declares the Visio drawing file
  types (`.vsdx` / `.vsdm` / `.vstx` / `.vstm` / `.vssx` / `.vssm`) so Finder
  offers "Open With → Editor for Visio Diagrams"; double-click, "Open With" and
  `open drawing.vsdx` launch the app and open the file in a new tab (native
  `application(_:open:)` → a `MethodChannel` that buffers cold-launch files
  until the Dart side is ready).
- **App icon**: a brand flow-diagram icon (blue rounded tile with two white
  nodes joined by an elbow connector) replacing the default Flutter logo,
  reproducibly rendered by `tool/gen_app_icon.dart`.
- **Status bar & zoom readout**: a bottom status strip (page size, current
  page, unsaved marker, selection count) and a live zoom percentage on the
  canvas zoom control (click it to fit-to-screen).

### Fixed
- The writer now regenerates a shape's `<Section N="Geometry">` when its
  geometry changed (resize scaling, connector re-routing), so edits survive a
  save/reopen instead of rendering with stale local geometry.
- The canvas no longer paints a shape's internal placeholder name (`Sheet.N`)
  or a connector's name as a label — only real text content shows.
- Removed a duplicate "Rounded" entry from the shapes palette.

### Deferred (post-v0.1)
- Obstacle-avoiding connector routing; per-run (selection-range) rich-text
  editing; vector (non-raster) PDF; custom / imported stencils.
- Other platforms (Windows / Linux / Android / iOS) and legacy `.vsd` import
  (via libvisio); `.vsdx` OS file association, app icon and packaging/signing.
- LibreOffice / Visio interop is currently covered by our own open→save→reopen
  round-trip tests; `soffice` headless cross-conversion is pending a local
  LibreOffice install.

### Tested
- Engine: 38 unit tests (parse; model edit / immutability / structural sharing;
  connector re-routing incl. elbow; **connector arc-length midpoint**; writer
  round-trip incl. create / delete / fill / rotate / flip / connects / layer
  visibility / resized geometry / text formatting / polygon stencil /
  **rounded-rect elliptical arcs** / **borderless text box** / z-order (to-back
  and one-step forward) / page rename / page add / page delete / group reparent /
  line style (dash·arrows·opacity) / font·underline·vertical-align·shadow;
  blank-document emit; geometry-scaling resize; SVG).
- App: `dart analyze` clean; unit tests for the alignment-snap math (5) and the
  controller (group/ungroup, group undo, line style, connector routing style,
  connector waypoints, text·shadow, copy/paste style, arrange
  flip·rotate·numeric geometry, one-step z-order, find, arrowhead types,
  cancel-transaction drag revert, default-style inheritance, corner radius,
  **text tool**, **default connector arrowhead**, **deleteShapeById**);
  widget tests (empty-state smoke test, in-place text-edit round-trip,
  right-click context menu); `flutter build macos` OK.

[Keep a Changelog]: https://keepachangelog.com/en/1.1.0/
