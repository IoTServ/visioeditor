# Changelog

All notable changes to **Editor for Visio Diagrams** are documented here.
The format loosely follows [Keep a Changelog]; versions follow SemVer.

## [Unreleased] — v0.1 (core editor, macOS-first)

### Added
- **Built-in AI diagram chat**: configure an OpenAI-compatible, Anthropic,
  Gemini or Ollama endpoint, model and API key; discuss and revise a process in
  a multi-turn conversation; validate Diagram Spec or Mermaid returned by the
  model; and open the generated editable `.vsdx` in a new tab. Settings now
  include an in-app guide for chat, Agent live preview, MCP, CLI and the Agent
  Skill. macOS builds have outbound-network entitlement for configured engines.
- **Legacy `.vsd` import (pure Dart)**: MS-CFB + VSD5/VSD6/VSD11 record parser →
  `VsdxDocument` (stencil/master inheritance, ForeignData bitmaps with DIB→BMP,
  InfiniteLine/Spline/NURBS/ShapeData, TextField expand with date/numeric formats,
  unit conversion (`convertNumber`), angle Degrees/Radians/DMS, currency via
  `0x60` custom format blocks, multi-run CharIX/ParaIX by charCount, TabsData
  (`0x88`/`0x96`/`0x97`/`0xb5`), Gantt Number→date heuristic / `0x70` format
  blocks, Name2/NameIDX page & shape names (ANSI on VSD5/6), TextXForm,
  FontFace/FontIX (incl. Case/Pos/Strike/FontScale), TextBlock, ParaIX,
  StyleSheet text parent chain, Layer/LayerMem, EMF/WMF media import,
  ShapeList z-order, string field StrUpper/StrLower), Multidimensional area
  fields via trailing typed result (beyond libvisio), OLE `object/ole` media
  import, EMF embedded-bitmap canvas paint, Name→field-table (not shape
  display name), VSD5 TextField format-from-text-stream, CharList/ParaList/
  FieldList/TabsDataList trailer reorder (libvisio setElementsOrder),
  DrawingUnits/PageUnits → page drawingScaleUnit + stencil FieldList format
  inheritance, OLE SummaryInformation title/creator → core.xml, transparent
  TextBkgnd override, MsoDateShort zero-pad, Edraw-safe default FillForegnd
  when FillPattern≠0, preserve signed 1D Width/Height (End−Begin), FeetAndInches
  formats 10/13/14 + fraction 15–18 (beyond libvisio TODO), NameIDX → shape/layer
  display names, Connection Points 0x99/0xba → vsdx Connection section, Control
  0xaa/0xa2 → Control section, Custom Props 0xb6 → Property (Shape Data) with
  master Label/Prompt merge, Scratch 0x9e / User 0xb4 / ActId 0xa9 → Scratch /
  User / Actions sections, Protection 0xa0 → locked, Group 0xbe → SelectMode /
  DisplayMode / DontMoveChildren, Hyperlink 0xc4 → Hyperlink section (UTF-16
  `0x60` cells; POI `visio_with_embeded.vsd`), ConnectList 0x72 empty-list
  safe-skip, Event 0x84 → EventDblClick/EventDrop formulas (OPENTEXTWIN /
  RUNADDONW), synthesised
  .vsdx
  baseline for edit / Save As. Algorithm reference: libvisio (no FFI).
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
  copy / paste (Cmd+C / Cmd+V), and **Ctrl/Cmd-drag to duplicate** on the canvas.
  Dragging snaps to the grid, nearby edges/centres, connection points, equal
  spacing and the orange page centre; **Alt/Option temporarily bypasses all
  snapping** for shapes, connector points and ruler guides. Arrow keys nudge;
  **Ctrl/Cmd+Shift+Arrow** adjusts width/height, and **Alt+Shift+R** clears
  connector waypoints. **Esc cancels an in-progress drag**, reverting it.
- **Advanced draw.io drag gestures**: **Alt+Shift-drag from blank canvas**
  moves the current selection remotely; **Alt+Ctrl/Cmd+Shift-drag** opens or
  closes an area along independent horizontal and vertical cuts, with orange
  reference lines; and **Alt+Shift-marquee from a shape** subtracts intersecting
  items from the selection. Remotely moved connectors detach from stationary
  targets but keep glue to targets moved with them. Each model-changing drag is
  one undoable edit.
- **Create shapes**: rectangle, ellipse, line (drag or click) with a dashed
  creation preview. Double-click blank canvas to choose a common shape at that
  point. A shape's directional arrow can be dragged to create a fixed connector;
  **Ctrl/Cmd-dragging the arrow** clones the source at the drop point and
  connects it. **Alt+Shift+Arrow** clones and connects the selected shape, or
  connects an existing neighbour. New shapes **inherit the last-used fill /
  line style** (drawio's `currentVertexStyle`).
- **Connector waypoints**: drag segment midpoint handles to add routing points,
  drag existing points to move them, double-click or right-click a point to
  remove it, and right-click any connector segment to add a point at that
  position. Clear Waypoints and `Alt+Shift+R` restore the automatic route.
- **Connector drop modifiers**: hold **Alt/Option** while dropping a new or
  existing connector endpoint inside a shape to append a custom fixed
  connection point at that exact position; hold **Shift** to force floating
  whole-shape/perimeter glue even when an existing blue point is nearby. Custom
  point creation, glue and undo are atomic, and locked targets fall back to
  floating glue without being mutated.
- **Movable connector labels**: a selected labelled connector now exposes the
  draw.io-style yellow diamond handle. Drag it to place the label anywhere on
  the page; the standard VSDX TextXForm is updated, nested connectors use the
  correct coordinate space, and the whole drag is one undo step. A circular
  grab handle rotates the label independently through standard VSDX
  `TxtAngle`; hold Shift for 15° increments.
- **Text tool** (drawio's "Text"): drop a borderless, fill-less text box that
  drops straight into in-place editing; an untyped box is discarded on commit
  or cancel. It can still be given a background or border afterwards.
- **Rounded rectangles**: a "Rounded" stencil plus a **corner-radius slider**
  in the inspector that rounds (or squares) any rectangle; corners are stored
  as `EllipticalArcTo` arcs and round-trip through the writer.
- **Shapes palette** (drawio's shapes sidebar): a searchable panel with
  collapsible **General / Flowchart / Arrows / UML** groups covering ~60 stencils
  (rectangle, rounded, text, ellipse, square, circle, diamond, parallelogram,
  triangle, right triangle, pentagon, hexagon, octagon, trapezoid, cross, star,
  cylinder, cube, document, card, callout, step, cloud, **lightning, heart**;
  process, decision, terminator, data, predefined process, internal storage,
  manual input, manual operation, preparation, delay, off-page reference,
  **display, merge, collate, or, summing junction, sort, loop limit**;
  right/left/up/down/double arrows; UML actor, use case, class, package, note,
  node; **parallelepiped, rounded rectangular callout, list / vertical list,
  image placeholder, open-sided partial rectangles**).
- **Network shapes** (drawio `mxgraph.networks`): a new **Network** library with
  server, router, firewall, monitor, laptop, mobile, printer, wireless, switch,
  hub, PC (plus cloud / database / user), drawn as clean geometry that
  round-trips to `.vsdx`.
- **Mockup / Electrical / Signs** libraries (drawio mockup, electrical, signs):
  UI wireframes (checkbox, radio, text field, combo, window, progress, slider,
  tabs, menu, toggle, search, rating, icons, loading, splitter, dropdown),
  circuit symbols (resistor, capacitor, inductor, diode, LED, ground, battery,
  transformer, AC/DC source, switch, fuse, inverter, potentiometer, breaker,
  crystal, lamp, IEEE AND/OR/NAND/NOR/XOR/XNOR gates, buffer), and safety
  glyphs (warning, no entry, mandatory, exit, radiation, first aid, high
  voltage, fragile, no smoking, biohazard, pedestrian, keep dry, slip hazard,
  fire extinguisher).
- **Floorplan** library (drawio floorplan): wall, door, double/sliding door,
  window opening, table, chair, desk, bed, sofa, sink, toilet, bathtub, shower,
  closet, bookshelf, fireplace, kitchen island, parking space, TV stand, file
  cabinet, column, stairs, escalator, elevator, plant, refrigerator, copier —
  top-down furniture and openings that round-trip to `.vsdx`.
- **EIP** library (drawio `mxgraph.eip`): Enterprise Integration Patterns —
  message / dead-letter / datatype / invalid-message channels, aggregator,
  splitter, content-based / dynamic routers, message / content filters,
  translator, content enricher, claim check, resequencer, composed message
  processor, normalizer, envelope wrapper, routing slip, messaging gateway,
  channel adapter / purger, wire tap, recipient list, competing / event-driven /
  polling / selective consumers, message dispatcher / store, messaging bridge,
  process manager, control bus, detour, durable subscriber, smart proxy,
  transactional client, service activator, test message (plus reused Message).
- **AWS** library (drawio `mxgraph.aws4` geometric starters): EC2, S3, Lambda,
  VPC, RDS, DynamoDB, SQS, SNS, CloudFront, API Gateway, IAM, ELB, ECS, EKS,
  Step Functions, CloudWatch, Kinesis, ElastiCache, Redshift, EventBridge,
  Cognito, Route 53, EFS, Aurora, Fargate, ECR, Glue, Athena, EMR, SageMaker,
  CloudTrail, Secrets Manager, CodePipeline, CodeBuild, WAF, Transit Gateway,
  Direct Connect, OpenSearch — clean architecture glyphs that round-trip to
  `.vsdx` (not brand-mark replicas).
- **Azure** library (drawio azure / azure2 geometric starters): Virtual Machine,
  App Service, Azure Functions, Blob Storage, SQL Database, Cosmos DB, AKS,
  Virtual Network, Application Gateway, Azure AD, Key Vault, Service Bus,
  Event Hubs, Azure Monitor, Container Instances, Container Registry, Redis
  Cache, Front Door, API Management, Logic Apps, Data Factory, Synapse
  Analytics, IoT Hub, Event Grid, Azure Firewall, Bastion, Azure DNS, Azure
  DevOps — clean architecture glyphs that round-trip to `.vsdx` (not
  brand-mark replicas).
- **GCP** library (drawio gcp2 geometric starters): Compute Engine, App Engine,
  Cloud Functions, Cloud Storage, Cloud SQL, BigQuery, GKE, VPC Network,
  Cloud Load Balancing, Cloud IAM, Pub/Sub, Cloud Spanner, Cloud Run,
  Cloud Monitoring, Bigtable, Dataflow, Dataproc, Cloud Composer, Cloud Armor,
  Cloud CDN, Memorystore, Cloud Build, Artifact Registry, Cloud Scheduler,
  Cloud Tasks, Firestore, Secret Manager, Vertex AI — clean architecture
  glyphs that round-trip to `.vsdx` (not brand-mark replicas).
- **Cisco** library (geometric network-gear starters): Cisco Router, Cisco
  Switch, ASA Firewall, Access Point, Nexus Switch, Catalyst Switch, IP Phone,
  Call Manager, Layer 3 Switch, WAN Router, Voice Gateway, UCS, Fabric
  Interconnect, Content Engine, Wireless Controller, PIX Firewall, ATM Switch,
  Workgroup Switch, Content Switch, VPN Concentrator, Wireless Bridge, Meraki
  AP, Cisco ISE, DNA Center, Telepresence, Expressway, Core Switch, Branch
  Router — clean architecture glyphs that round-trip to `.vsdx` (not
  brand-mark replicas; names avoid Network-group collisions).
- **Alibaba** library (Alibaba Cloud geometric starters): Alibaba ECS, OSS,
  SLB, ACK, Function Compute, PolarDB, TableStore, MaxCompute, RocketMQ, RAM,
  CEN, SLS, NAS, AnalyticDB, CDN, Aliyun WAF, DataWorks, Hologres, Flink, MSE,
  ASM, ACR, EIP, NAT Gateway, KMS, ARMS, Lindorm, DTS — clean architecture
  glyphs that round-trip to `.vsdx` (not brand-mark replicas).
- **IBM** library (IBM Cloud geometric starters): IBM VPC, Cloud Object
  Storage, IKS, ROKS, Db2, Cloudant, Event Streams, IBM MQ, watsonx, Code
  Engine, API Connect, App ID, Key Protect, Direct Link, Activity Tracker,
  Log Analysis, Schematics, Satellite, Power VS, Bare Metal, Block Storage,
  File Storage, CIS, Internet Services, Aspera, Certificate Manager,
  Toolchain, Security Advisor — clean architecture glyphs that round-trip
  to `.vsdx` (not brand-mark replicas).
- **Oracle** library (OCI geometric starters): Compute Instance, Autonomous
  Database, Object Storage, Block Volume, OKE, Oracle Functions, VCN, Oracle
  Load Balancer, Streaming, Oracle Vault, Exadata, MySQL HeatWave, GoldenGate,
  Analytics Cloud, OCI API Gateway, Service Connector, OCI Notifications,
  OCI Events, Data Science, Data Flow, Data Catalog, FastConnect, OCI File
  Storage, OCI Bastion, Network Load Balancer, Cloud Guard, Resource Manager,
  DevOps — clean architecture glyphs that round-trip to `.vsdx` (not
  brand-mark replicas).
- **Network** also includes tablet, phone, modem, storage, load balancer, and
  security camera.
  Each tile is a **live geometry thumbnail** (not an icon), so the preview
  matches what drops on the canvas. Click to drop at the centre, or **drag it
  onto the canvas** to drop at the cursor. Every stencil is built from
  polygon / ellipse / rounded-rect / elliptical-arc geometry (incl. multi-path
  shapes with `NoFill` inner edges) so it round-trips through the writer
  losslessly. The palette toggle ("More shapes") lives in the **left tool
  strip**, unifying every shape entry point on the left.
- **Insert Image** (drawio "Insert > Image"): embed a raster image
  (PNG / JPEG / GIF / BMP / WEBP) as a picture shape — sized from its pixel
  dimensions and fitted to the page — from the toolbar or the ⋯ menu. The
  picture renders on the canvas immediately (a decode cache was wired up, so
  existing embedded images now show for real instead of a placeholder) and
  round-trips: the writer embeds the media part, adds the page image
  relationship (creating the page's rels part when needed), registers the
  content-type, and emits a Visio `Type="Foreign"` shape with `<ForeignData>`.
- **Connectors with glue**: connect two shapes; endpoints attach to the target
  shapes' edges and auto-reroute when a shape moves / resizes / rotates;
  `<Connects>` round-trip. New connectors carry a **default end arrowhead**
  (they point at their target). Each connector can be routed **straight,
  orthogonal, or curved** (inspector; drawio's Curved edges smooth the route
  through a Catmull-Rom spline that is baked into the geometry, so the curve
  round-trips as ordinary `MoveTo`/`LineTo` rows), its corners optionally
  **rounded** (drawio's "Rounded" edge option — an inspector toggle that fillets
  each right-angle bend with a small quadratic-Bezier arc, baked into the
  geometry the same way so it round-trips and survives re-routes; moot for a
  curved edge, which is already smooth), and reshaped with draggable
  **waypoints** (bend points: drag a segment midpoint to add one, drag it to
  move, double-click to remove); the routing choice and waypoints are kept
  across re-routes. A selected connector shows green **endpoint handles**:
  drag one onto another shape to reconnect that end (re-glue), or onto empty
  canvas to detach it to a floating point; **Clear Waypoints** (right-click)
  resets the route. A shape's **fixed connection points** show (drawio's blue
  crosses — edge midpoints and centre) while wiring or dragging an endpoint onto
  it **and now simply while hovering it** in select mode, so the attach points
  are visible before you drag. Snapping to one pins that end there so it tracks
  the shape under move / resize / rotate; **both ends** glue to a specific point
  — dragging a connector out of a hover arrow glues its **begin** end to that
  side's point too (not just the whole shape). Points round-trip to Visio's
  `<Section N="Connection">` (the connect's `ToPart` selects the point).
- **Edge labels**: double-click a connector to label it; the text is drawn
  centred on the route's midpoint (drawio-style) with a page-coloured backing
  for legibility, and the in-place editor opens right there.
- **Curved Text** (drawio-style arc labels): toggle in the text inspector to
  paint a 2-D shape's label along a quadratic arc inside its text block.
  Stored as `User.veCurvedText` so it survives save → reopen.
- **Bullets / paragraph indents**: Visio `Bullet` / `BulletStr` /
  `IndLeft` / `IndFirst` / `TextPosAfterBullet` are painted (hanging indent)
  and can be toggled from the text inspector; values round-trip.
- **Local ShapeSheet recalc** (first slices): after resize, Connection /
  LocPin / Scratch / Controls / User cells whose `F=` only references local
  Width/Height/Pin*/Begin*/End* (and Geometry rows that reference those or
  `Scratch.Xn`) are re-evaluated so glue points and parametric paths stay
  consistent. Cross-shape `Sheet.n!Cell` refs (PinX/Y, Width/Height, Angle,
  LocPin*, Begin*/End*) are resolved on page-level `recalculateFormulas`
  after move / resize / rotate / align. Local `SETATREF` / `SETATREFEXPR` /
  `SETATREFEVAL` support input redirect into Controls / User / Prop (including
  redirect chains up to 10 hops) and recalc transparency via cell lookup;
  composite formulas such as `SETATREF(…)+Width*0.5` evaluate on sync.
  Unresolved theme / unknown cells keep their prior `V`.
  `SETATREF(Controls.…)` / `SETATREF(User.…)` on `TxtPinX`/`TxtPinY` syncs
  the text-block pin with the bound target.
- **Hover-to-connect** (drawio HoverIcons): hovering a shape in select mode
  shows directional connect arrows around it; drag one out to wire a new
  connector — dropping on another shape glues both ends, dropping on empty
  canvas leaves a loose end. The shape the connector would glue to is
  highlighted while wiring (also with the connector tool).
- **Line jumps** (drawio's "Line jumps"): where a connector crosses another it
  **arcs over** the lower one (a small semicircle at each crossing with a
  lower-z connector) instead of forming an ambiguous "+" junction. Pure
  render-only overlay — it never touches the geometry or the round-trip; toggle
  it from the ⋯ menu (on by default).
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
  addition to to-front / to-back. It also matches draw.io's **Swap Shapes**,
  **Copy Size / Paste Size**, and connector **Reverse** commands; reversing an
  edge swaps its glue targets, fixed connection points, waypoints, trigger
  formulas and arrowheads as one undoable edit. **Autosize**
  (Cmd/Ctrl+Shift+Y) fits selected atomic shapes to their wrapped text while
  preserving width and top-left position. Ctrl/Cmd-resizing a normal group
  changes only its outer boundary, leaving children untouched. All round-trip
  (`PinX/PinY/Width/Height/Angle`, `FlipX/FlipY`, `<Shape>` reorder, `<Connect>`
  rows and 1-D endpoint cells).
- **Replace Shape** (draw.io-style): Shift-click any stencil while one or more
  atomic shapes are selected to replace their geometry in a single undo step,
  preserving each shape's size, position, rotation, label, style, data, links
  and connector glue.
- **Label editing** (draw.io-style): select a shape or connector and start
  typing to replace its label immediately. Enter saves the inline edit;
  Shift+Enter or Alt+Enter inserts a line break. The Text panel can position a
  2-D shape's label to its left, top, centre, bottom or right, and toggle
  vertical text. Label placement round-trips through Visio `TxtPin*`,
  `TxtLocPin*`, `TxtWidth` / `TxtHeight` and `TextDirection` cells.
- **Lock / unlock** (drawio Lock/Unlock, Cmd+L): lock the selection so it can
  still be selected but not moved, resized, rotated, deleted or text-edited; a
  locked shape's selection box turns red and its resize / rotation handles are
  hidden. Reachable from Cmd+L, the right-click menu, the ⋯ menu, or the
  Arrange section. Round-trips to Visio's protection cells (`LockMoveX` /
  `LockMoveY` / `LockWidth` / `LockHeight` / `LockAspect` / `LockRotate` /
  `LockDelete` / `LockTextEdit`; `LockMoveX` is the bit read back on parse).
- **Find** (drawio Cmd+F): a floating search bar that filters shapes on the
  current page by text/name, shows a match counter, and cycles matches
  (Enter / Shift+Enter or the arrows), selecting and scrolling each into view.
  **Zoom to selection** fits the current selection to the window.
- **Outline panel** (drawio's third panel, alongside Shapes and Format): a
  bottom-right thumbnail of the whole page with a rectangle marking the part
  currently on screen; click or drag inside it to re-centre the canvas there.
  Toggle it from the toolbar.
- **Rulers** (drawio-style): inch rulers along the top and left edges that
  track pan / zoom (nice-number tick spacing that stays readable at any zoom)
  and highlight the current selection's extent. Toggle them from the toolbar.
- **Text**: double-click a shape to edit its label **in place on the canvas**
  — an editor overlays the shape (positioned and scaled to its box); Enter
  inserts a newline, Cmd/Ctrl+Enter or clicking away applies, Esc cancels. The
  inspector formats the whole label — **font family**, size, bold / italic /
  **underline**, colour, and **horizontal + vertical alignment** (written back
  to the Character / Paragraph sections and the `VerticalAlign` cell).
- **Save / Save As** with round-trip fidelity; unsaved-changes indicator.
  Save writes `.vsdx` only (legacy `.vsd` is import-only). Heals missing
  `docProps/core.xml` and ensures Character sections for local text so Edraw
  opens exports with correct font size.
- **Canvas metafile paint**: WMF/EMF vector replay + OLE `OlePres` EMF preview
  (embedded DIB first, then GDI display-list rasterisation).
- **Text align fidelity**: SVG/PDF honour Paragraph `HorzAlign`; Process Flow
  example labels centred; inline editor preview shares TextField width so
  caret/selection hit the visible glyphs.
- **Export**: to SVG (pure-model `VsdxToSvgSerializer`), PNG and multi-page PDF
  (rasterised via the on-screen painter).
- **Pages**: add / duplicate / delete / rename pages from the page bar; all
  round-trip (the writer adds/removes the page part, relationship and
  content-type override, matching pages by id).
- **Layers**: a panel to toggle layer visibility; the change round-trips
  (Visible/Lock/Print patched on the PageSheet in pages.xml).
- **Grid & snapping**: toggleable 0.25 in grid; create / resize snap to it.
- **Page format panel** (drawio "Diagram" tab): when nothing is selected the
  right Format panel shows page settings — grid / snap toggles, a **background
  colour** palette, and **paper size** (Letter / Legal / Tabloid / A3–A6 /
  B4–B5 presets, Portrait / Landscape, or a custom width / height). Page size
  and background round-trip (PageSheet `PageWidth` / `PageHeight` / `PageColor`).
- **Edit Data** (drawio Cmd+M): edit a shape's **Shape Data** — its custom
  properties (Visio `<Section N="Property">`) — as name / value rows in a dialog
  (reachable from Cmd+M, the right-click menu, the ⋯ menu, or a **Data** section
  in the inspector). Properties round-trip: existing rows are patched in place
  (keeping any cells we don't model), new ones appended, removed ones dropped.
- **Edit Link** (drawio Cmd+K): set or clear a shape's **hyperlink** (Visio
  `<Section N="Hyperlink">`) via a dialog (reachable from Cmd+K, the right-click
  menu, the ⋯ menu, or a **Link** section in the inspector). A value starting
  with `#` is stored as an in-document anchor (e.g. `#Page-2`), everything else
  as an external address; an optional label is kept too. Links round-trip:
  existing rows are patched in place (keeping unmodelled cells), added / removed
  as needed, and the section is dropped when the link is cleared.
- **Recent files** (persisted) and an **unsaved-changes guard** on close.
- **Multiple documents in tabs**: open several `.vsdx` files at once (top tab
  bar with dirty markers + close); drag-drop multiple files opens a tab each.
- **Multi-select**: Shift/Ctrl/Cmd-click toggles items; Alt-click cycles through
  overlapping shapes. Marquee selects fully enclosed items, while Alt-marquee
  includes intersecting and nested items. Hold Space and drag anywhere to pan;
  Alt-wheel zooms and Shift-wheel scrolls horizontally. **Align**
  (left/center/right/top/middle/bottom),
  **distribute** (horizontal/vertical) and **z-order** (to front / back and one
  step forward / backward) from the inspector. Hold **Shift while dragging** to
  constrain the move to one axis.
- **Smart alignment guides** (drawio-style): dragging a shape snaps its edges
  and centre to nearby shapes, equal spacing, connection points and the page
  centre. Blue/purple guides show shape/spacing alignment and the page-centre
  guide is orange; the Diagram panel has an independent **Guides** toggle.
- **Right-click context menu**: cut / copy / paste / duplicate / delete, bring
  to front / send to back, group / ungroup, copy & paste style, edit text; on
  empty canvas, paste / **paste here** (at the cursor) / select all / fit to
  window, plus draw.io's **Select Edges** / **Select Vertices** commands for
  page-wide connector or shape styling.
- **Copy / paste style** (drawio "Copy Style" / "Paste Style"): lift the fill,
  line and text formatting off one shape and apply it to others.
- **Group / ungroup** (drawio "Group" / "Ungroup"): combine the selected
  top-level shapes into a group (members become group-local, Visio's group
  coordinate convention) and ungroup back to page-absolute coordinates; both
  round-trip through the writer (which reparents the `<Shape>` subtree).
  Plain groups use draw.io's root-first drill-down selection: the first
  click/drag targets the group, repeated clicks descend one level, sibling
  clicks stay inside, and Alt-click reaches the deepest child directly.
  A selected child can be promoted with **Remove from Group** in the Arrange
  panel or context menu, or by dragging it beyond the group bounds; page-space
  geometry is preserved and the whole edit is undoable. Structured tables,
  swimlanes and charts are protected from accidental dismantling.
  Foldable containers can also be collapsed or expanded from their context
  menu or with draw.io's Ctrl/Cmd+Home and Ctrl/Cmd+End shortcuts. Multi-selected
  hosts fold as one undo step, while locked hosts and locked layers are skipped.
- **Bundled sample drawings** (from the BSD `vsdx` project) openable from the
  empty state; the full set is copied to `packages/vsdx/test/fixtures/`.
- **Keyboard**: Cmd+N/O/W/S/Z/Shift+Z/D/C/V/X/A, Cmd+Shift+F/B (to front/back),
  Cmd+G / Cmd+Shift+U (group / ungroup), Cmd+Home / Cmd+End (collapse / expand),
  Cmd+Alt+C/V (copy/paste style),
  Cmd+R / Cmd+Shift+R (rotate 90°), Cmd+F (find), Delete, Esc, arrow keys to
  nudge the selection, Tab/Shift+Tab to traverse visible nested shapes,
  Alt+Tab to select the parent, and canvas zoom (Cmd +/- , Cmd+0 = 100%,
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
- Hover-connect arrows no longer vanish before the pointer reaches them: the
  hover is now kept alive across the whole halo around a shape (its box plus
  the arrow reach), removing the dead zone between the shape's edge and the
  arrow hit-circles.
- The writer now regenerates a shape's `<Section N="Geometry">` when its
  geometry changed (resize scaling, connector re-routing), so edits survive a
  save/reopen instead of rendering with stale local geometry.
- The canvas no longer paints a shape's internal placeholder name (`Sheet.N`)
  or a connector's name as a label — only real text content shows.
- Removed a duplicate "Rounded" entry from the shapes palette.

### Deferred (post-v0.1)
- Obstacle-avoiding connector routing; per-run (selection-range) rich-text
  editing; vector (non-raster) PDF; custom / imported stencils.
- Other platforms (Windows / Linux / Android / iOS); `.vsd` encrypted /
  masters deep inheritance / binary write-back; packaging/signing.
- LibreOffice / Visio interop is covered by open→save→reopen round-trip tests;
  CI installs LibreOffice and runs
  `packages/vsdx/test/libreoffice_crosscheck_test.dart` (`REQUIRE_SOFFICE=1`,
  soffice `--convert-to pdf`). Locally the same test skips when LibreOffice is
  not installed (set `SOFFICE` to override the binary path).

### Tested
- Engine: 54 unit tests (parse; model edit / immutability / structural sharing;
  connector re-routing incl. elbow; **connector arc-length midpoint**;
  **curved-connector spline sampling + geometry round-trip**; **rounded-corner
  fillet (endpoints exact, corner backed off) + rounded-connector geometry
  round-trip**; writer
  round-trip incl. create / delete / fill / rotate / flip / connects / layer
  visibility / resized geometry / text formatting / polygon stencil /
  **rounded-rect elliptical arcs** / **borderless text box** / z-order (to-back
  and one-step forward) / page rename / page add / page delete / **page size +
  background colour** / **shape data (custom properties)** / **hyperlink
  (create·edit·remove)** / group reparent / line style (dash·arrows·opacity) /
  font·underline·vertical-align·shadow / **lock·unlock (protection cells,
  round-trip + new-shape emit)** / **image insert (media part + page rels +
  ForeignData, on an existing page and a blank document)** / **connector
  endpoint reconnect + detach** / **fixed connection point (materialise +
  patch + routing)**; blank-document emit; geometry-scaling resize; SVG).
- App: `dart analyze` clean; unit tests for the alignment-snap math (5) and the
  controller (group/ungroup, group undo, line style, connector routing style,
  **connector three-way style incl. curved**, connector waypoints, text·shadow,
  copy/paste style, arrange flip·rotate·numeric geometry, one-step z-order,
  find, arrowhead types, cancel-transaction drag revert, default-style
  inheritance, corner radius, **connector rounded corners (toggle + survive
  reroute + undo)**, **text tool**, **default connector arrowhead**,
  **deleteShapeById**, **page setup size·orientation·background**,
  **shape data**, **hyperlink set·clear·undo**, **revealPagePoint**,
  **lock (locked shape resists move·rotate·delete + undo, mixed selection
  moves its free members)**, **image insert (embeds bytes + undo, fresh part
  name after undo, export/reopen round-trip)**, **connector endpoint
  reconnect / detach + undo, clear-waypoints + undo, fixed connection point
  (materialise + ToPart), stencil drop-at-point, paste-at-cursor**), the
  **Outline camera** (`visibleContentRect` mapping, change-only notify) and the
  **ruler tick math** (nice-step selection, origin-aligned ticks); widget tests
  (empty-state smoke test, in-place text-edit round-trip, right-click context
  menu); `flutter build macos` OK.

[Keep a Changelog]: https://keepachangelog.com/en/1.1.0/
