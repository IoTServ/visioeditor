# Changelog

All notable changes to **Editor for Visio Diagrams** are documented here.
The format loosely follows [Keep a Changelog]; versions follow SemVer.

## [Unreleased] — v0.1 (core editor, macOS-first)

### Added
- **draw.io per-connector Line Jumps and Line Cap**: Format now offers Flat,
  Round and Square stroke caps plus None, Arc, Gap, Sharp and Line crossing
  styles with an independent jump size for each connector. Arc/Gap/Sharp map
  to native Visio `ConLineJump*` cells; draw.io's paired-Line rendering and
  per-edge size use preserved User rows with a native Sharp fallback. Canvas
  and SVG/PDF export agree, edits are undoable and lock-safe, and the complete
  line style participates in Copy/Paste Style and default edge styles.
- **draw.io label background and Text Spacing**: Format → Text now exposes a
  solid/transparent label background with opacity plus independent left,
  right, top and bottom text padding. Slider drags preview as one undo step,
  Reset Text Padding restores Visio defaults, and locked labels remain
  unchanged. These text-block styles survive `.vsdx` save/reopen and now join
  Copy/Paste Style and default creation styles without replacing the target
  label's position, size or angle.
- **draw.io picture Crop and Image controls**: a selected raster picture now
  exposes crop zoom and two-axis pan plus opacity, brightness, contrast and
  blur in Format → Image. Crop movement is constrained to keep the frame
  covered, slider gestures preview live as one undo step, Reset Crop and Reset
  Image Adjustments are independent, and locked pictures reject every edit.
  Literal crop values scrub inherited `Img*` formulas and all controls survive
  `.vsdx` save/reopen through the existing Image Properties cells.
- **draw.io Rotate with Edge**: labelled connectors now expose the persistent
  Text-panel auto-rotation switch. Labels follow the nearest drawn route
  segment, stay upright when an edge is reversed, and update immediately after
  rerouting on the canvas and in SVG/PDF export. The option hides/disables the
  manual rotate handle without overwriting `TxtAngle`, is undoable, survives
  `.vsdx` through `User.veAutoRotateLabel`, preserves unrelated User rows and
  participates in connector Copy/Paste Style and default creation styles.
- **draw.io Constrain Proportions**: the Arrange size section now exposes the
  persistent `aspect=fixed` switch for editable vertices. Width/height fields,
  keyboard sizing and all eight resize handles preserve the original ratio;
  Shift supplies the same temporary constraint on every handle. The state is
  undoable, round-trips through `User.veConstrainProportions`, preserves
  unrelated User rows and participates in vertex Copy/Paste Style and default
  creation styles.
- **draw.io Word Wrap**: the Format → Text panel can now enable or disable
  wrapping for selected vertex labels, while connector labels remain outside
  the option just as in draw.io. Disabled wrapping keeps explicit line breaks
  but lets each line use its natural width on the canvas and in SVG/PDF export.
  The state is undoable, survives `.vsdx` through `User.veWordWrap`, preserves
  unrelated User rows and participates in vertex Copy/Paste Style and default
  creation styles.
- **draw.io independent default creation styles**: vertices and connectors now
  maintain separate current styles, so a remembered connector stroke never leaks
  onto new vertices (or vice versa). **Set as Default Style** and **Clear Default
  Style** are available from Format, More and the shape context menu; the
  complete matching fill/line/text/effects bundle is copied to future shapes.
  `Cmd/Ctrl+Shift+D` pins the selected category, while `Cmd/Ctrl+Shift+R`
  unconditionally clears both categories and resumes automatic last-used-style
  tracking. Defaults remain session-only and do not dirty the document.
- **draw.io per-shape Collapsible style**: every editable 2-D selection now
  exposes a **Collapsible** check in More, Arrange and its context menu.
  Containers and swimlanes keep draw.io's enabled-by-default behaviour, while
  ordinary vertices may opt in. The explicit state round-trips through
  `User.veCollapsible`; disabling it on a folded shape safely expands the
  shape first and restores hidden-child glue as one undoable edit. This remains
  independent from the global **Collapse/Expand Controls** visibility switch.
- **draw.io single-cell Group / Ungroup containers**: Group on one editable
  vertex now promotes it in place to a drop container instead of doing
  nothing; Ungroup on an empty container restores an ordinary vertex without
  replacing its geometry or ID. The explicit state round-trips through
  `User.veContainer`, including a negative override for container-like names,
  and is available through the existing context menu, Arrange controls and
  `Cmd/Ctrl+G` / `Cmd/Ctrl+Shift+U` shortcuts.
- **draw.io centre vs spacing distribution**: horizontal and vertical
  **Distribute** now equalise shape centres exactly like draw.io, while the new
  **Distribute Horizontal/Vertical Spacing** commands equalise visible gaps
  between differently sized shapes. Both modes are available from More and
  Arrange, ignore connectors when checking availability, preserve the outer
  anchors, honour locked content, and remain single-step undoable edits.
- **draw.io one-shot grid alignment and Select None**: **Snap Selection to
  Grid** now immediately quantises selected vertex position/size and connector
  waypoints, skips locked content, and commits mixed selections as one undoable
  edit. It is available from More, the shape context menu and Arrange, and is
  deliberately separate from the persistent drag-snapping switch. **Select
  None** is now exposed in More with draw.io's `Cmd/Ctrl+Shift+A` shortcut.
- **draw.io custom shape tooltips**: **Edit Tooltip…** is now available from
  the More and shape context menus. Tooltip text is undoable, survives `.vsdx`
  saves through `User.veTooltip`, and appears in a delayed pointer-following
  canvas overlay. The Extras-style **Tooltips** switch hides or restores all
  custom hover text without modifying the document.
- **draw.io Smart Fit and global zoom keys**: with no selection, `Enter` now
  toggles between a centred 100% view and Fit Window. `Cmd/Ctrl+0` opens the
  existing validated custom-percentage dialog, matching draw.io rather than
  silently resetting the canvas, and `Cmd/Ctrl +/-` now works after focus moves
  to app chrome or side panels as well as directly on the canvas.
- **draw.io Extras controls and ordering chords**: the More menu now exposes
  **Copy on Connect** and **Collapse/Expand Controls**. Copy on Connect clones
  a connector's source at an empty drop point and wires the clone in the same
  undoable edit; disabling fold controls removes both their chevrons and
  command hit paths. `Cmd/Ctrl+Alt+Shift+F/B` now performs draw.io's exact
  one-layer Bring Forward / Send Backward actions.
- **draw.io connection-affordance controls**: **Connection Arrows** and
  **Connection Points** are now independent session toggles in the More menu,
  with draw.io's `Alt+Shift+A/O` shortcuts. Disabling arrows removes their
  drawing and hit regions; disabling points removes blue-point display,
  fixed-point source gestures and snapping while preserving ordinary perimeter
  glue and the explicit Edit Connection Points mode.
- **draw.io advanced shortcut parity**: the editor now follows the effective
  core and Trees-plugin key map for Save As, Fit Window, Select Edges, whole
  label font sizing, Copy / Paste Size, Edit Link, Edit Connection Points and
  Select Children / Subtree / Parent / Siblings. In particular, tree selection
  now uses `Alt+Shift+X/T/P/S`, while `Alt+Shift+C` remains Copy Text Style and
  `Alt+Shift+F/V` operates the size clipboard; Select Subtree includes its root
  and the traversed tree connectors.
- **draw.io relationship and page-keyboard parity**: Select Children /
  Subtree / Parent / Siblings now follows directed connector trees first
  and nested groups or containers as a fallback, with cycle and visibility
  protection, context-menu actions, and draw.io's contextual
  `Alt+Shift+X/T/P/S` shortcuts. With no shape selected, Ctrl/Cmd+Arrow
  navigates pages and Shift+Arrow reorders them; Ctrl/Cmd+Shift+PageUp/PageDown
  moves between pages directly. With a shape selected, Ctrl/Cmd+Arrow performs
  draw.io's 1pt size adjustment. Relationship labels are localized across all
  37 supported UI languages.
- **draw.io text-style clipboard parity**: **Copy Text Style** /
  **Paste Text Style** now transfer only label typography and layout—font,
  size, colour, emphasis, paragraph alignment, text margins, background,
  vertical alignment and direction—without touching label content, shape
  fill/line/effects or text-box geometry. The actions use draw.io's
  Copy action uses `Alt+Shift+C`; both actions appear in the Text panel, More
  menu and context menu, apply through group descendants while skipping locked
  parts, and are localized across all 37 supported UI languages.
- **draw.io link/text action parity**: **Copy as Text** places the first
  selected shape's plain label on the system clipboard and safely wins over an
  in-flight rich shape copy. **Open Link** is available from the context menu,
  compact More menu and Format panel; internal Visio page anchors switch pages
  in-app, while safe external URL/mail/phone/file schemes open through the
  platform. Both actions are localized across all 37 UI languages.
- **draw.io zoom menu parity**: the live canvas percentage now opens draw.io's
  25%–400% preset list, whole-page fit, **Fit Page Width**, and a validated
  custom-percentage dialog. Page-width fitting fills the horizontal viewport
  while preserving the current vertical reading position; it is also available
  from the compact toolbar and the blank-canvas context menu. The new label is
  localized across all 37 supported UI languages.
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
  right-button or middle-button drag also pans temporarily without changing
  tools or moving shapes. A stationary right-click still opens the context
  menu. Alt-wheel zooms and Shift-wheel scrolls horizontally. **Align**
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
- **Enter / duplicate-selection shortcuts** (draw.io): Enter starts inline
  label editing for one selected shape. Ctrl/Cmd+Enter duplicates the current
  selection; a selected table cell (or same-row cell selection) is promoted to
  its whole row, while a selected table duplicates as a table. Row copies
  preserve cell styles, labels, nested contents and row-internal connections.
  Every copy mints fresh IDs, selects the result and undoes in one step; text
  inputs retain their Enter keys.
- **Table deletion shortcuts** (draw.io): Delete/Backspace on one cell or a
  same-row cell selection removes that row; selecting every visible cell in a
  column removes that column. Both edits preserve a valid table, clean up
  affected glue and undo in one step. Sparse/mixed cell selections, locked
  structures and the final remaining row/column are protected from raw child
  deletion.
- **Modified deletion shortcuts** (draw.io): Ctrl/Cmd+Delete or Backspace
  removes selected shapes together with their unlocked incident connectors;
  Shift+Delete or Backspace clears only the selected labels. Multi-selection
  edits undo in one step, and focused text fields retain their native word /
  selection deletion keys.
- **View and navigation shortcuts** (draw.io): F2 is an alternate label-edit
  key; Home restores a centred 100% view; Ctrl/Cmd+J fits the current page;
  Ctrl/Cmd+Shift+G toggles the grid, Ctrl/Cmd+Shift+O toggles Outline, and
  Ctrl/Cmd+Shift+L toggles Layers. Home/End remain native cursor-navigation
  keys while a text field owns focus.
- **Superscript / subscript / remove formatting** (draw.io): the Text panel
  exposes baseline-position toggles backed by Visio `Char.Pos`, plus a Remove
  Formatting action that preserves text and paragraph layout. During inline
  editing, Ctrl/Cmd+. toggles superscript and Ctrl/Cmd+, toggles subscript for
  the selected UTF-16 range; repeated use returns it to the normal baseline.
  Each operation is undoable and round-trips through `.vsdx`.
- **Select Connections / Clear Anchors** (draw.io): a selected shape's context
  menu can add its visible incident connectors to the selection. Clear Anchors
  resets fixed-point glue on selected connectors, or connectors incident to
  selected shapes, back to automatic perimeter attachment while keeping both
  terminals connected. Locked connectors are skipped and the batch undoes in
  one step.
- **Turn / Reverse and Shape Data clipboard** (draw.io): Cmd/Ctrl+R now turns
  ordinary shapes but semantically reverses connectors, including their
  terminals, route and arrowheads; mixed selections undo in one step. Copy Data
  / Paste Data preserve full Visio Property-row metadata, support batch paste
  while skipping locked shapes, and keep target labels from the context menu.
  The draw.io Alt+Shift+B/E shortcuts copy data and paste the source label too.
- **Bundled sample drawings** (from the BSD `vsdx` project) openable from the
  empty state; the full set is copied to `packages/vsdx/test/fixtures/`.
- **Keyboard**: Cmd+N/O/W/S/Z/Shift+Z/D/C/V/X/A, Cmd+Shift+F/B (to front/back),
  Cmd+G / Cmd+Shift+U (group / ungroup), Cmd+Home / Cmd+End (collapse / expand),
  Cmd+Alt+C/V (copy/paste style), Ctrl/Cmd+Delete (delete with connectors),
  Shift+Delete (clear labels),
  Cmd+R / Cmd+Shift+R (rotate 90°), Cmd+F (find), Delete, Esc, arrow keys to
  nudge the selection, Tab/Shift+Tab to traverse visible nested shapes,
  Alt+Tab to select the parent, F2/Enter to edit labels, Home to reset the
  view, Cmd+J to fit the page, Cmd+Shift+G/O/L to toggle grid/Outline/Layers,
  and canvas zoom (Cmd +/- , Home = 100%, Cmd+Shift+H = fit).
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
  canvas zoom control (click it for presets, page-fit commands, or custom zoom).

### Fixed
- FillGradient washes with more than two unique opaque colours on a
  compound even-odd fill now keep the hole in LibreOffice. libvisio
  concatenates every `NoFill=0` Geometry into one `svg:fill-rule=evenodd`
  path; the previous PNG bake classified the outer Width×Height box as a
  rectangle and filled the interior. A save samples every fillable ring
  and punches even-odd holes, then composites unpainted pixels onto
  opaque white so Draw does not fill the window with Blue 2. Two-colour
  washes stay 25–40 so Draw's own even-odd still punches the hole. A
  second save does not stack another plate.
- FillGradient washes with more than two unique opaque colours on
  EllipticalArcTo / RelEllipticalArcTo geometry now keep the painted
  silhouette in LibreOffice. The previous PNG bake walked only command
  endpoints, so a pie collapsed to a triangle and a rounded rectangle
  whose bbox filled the shape box baked as a sharp Width×Height plate,
  while canvas / SVG already sample those arcs. A save samples the path
  into the SoftEdges fill PNG and composites unpainted pixels onto
  opaque white so Draw does not fill the box with Blue 2. Two-colour
  washes stay 25–40. A second save does not stack another plate.
- InfiniteLine LineGradient washes with more than two unique opaque
  colours now keep the middle stops in LibreOffice. Perimeter sampling
  of InfiniteLine spans hundreds of inches, so the previous PNG bake
  scaled that ribbon down to one colour on the page. A save clips the
  stroke to the shape box before rasterizing. Two-colour washes stay
  25–40. A second save does not stack another plate.
- Arrowed 1-D LineGradient washes with more than two unique opaque
  colours now keep the middle stops and the markers in LibreOffice.
  The previous PNG bake skipped open arrowheads (`draw:marker-*`
  cannot follow a ribbon), so Draw still collapsed those connectors
  to FillPattern 25–40. A save rasterizes the stroke ribbon and baked
  arrow Geometry into the same plate and drops Begin/EndArrow.
  Two-colour arrowed washes stay a 25–40 ribbon plus Geometry markers.
- LineGradient washes with more than two unique opaque colours now
  keep the middle stops in LibreOffice. libvisio has no LineGradient
  token, so a save used to collapse those strokes to a filled ribbon
  whose classic FillPattern 25–40 only interpolates two colours, while
  canvas / SVG already sample every stop. A save bakes the same
  SoftEdges stroke PNG at sigma 0 (1-D as a 2-D ribbon plate) and
  drops the source line. Two-colour washes stay 25–40. A second save
  does not stack another plate.
- FillGradient washes with more than two unique opaque colours now
  keep the middle stops in LibreOffice. libvisio has no FillGradient
  token, so a save used to collapse those washes to classic
  FillPattern 25–40 (FillForegnd / FillBkgnd only) while canvas / SVG
  already sample every stop. A save bakes the same SoftEdges fill PNG
  at sigma 0 and drops the source fill. Two-colour washes stay 25–40.
  A second save does not stack another plate.
- Headerless DIB and ICO Foreign bitmaps now keep that picture in
  LibreOffice and on the canvas. libvisio only prepends a
  BITMAPFILEHEADER for CompressionType format 0; a missing type is
  format 255 → `image/bmp` with raw DIB / ICO bytes, so Draw dropped
  them while `decodeImage` also skipped headerless DIB. A save wraps
  the DIB the same way `_handleForeignData` does, re-encodes ICO / DIB
  as PNG `ForeignType=Bitmap`, and `rasterForRendering` exposes a BMP /
  PNG Flutter can paint. A complete `BM` file stays native.
- WebP rasters without a libvisio CompressionType now keep that picture
  in LibreOffice. `readForeignData` maps a missing CompressionType to
  format 255 → `image/bmp`, so Draw dropped WebP while canvas / SVG
  already decode it. A save re-encodes those as PNG `ForeignType=Bitmap`.
  A complete `BM` file stays native. A second save does not stack
  another PNG.
- Vector EMF / WMF hatch, pattern-brush and clip records now keep that
  drawing in LibreOffice. Draw still fills Blue 2 for `image/emf` /
  `image/wmf` instead of replaying those records, and a pure-vector PNG
  bake used to fill only the hatch background (white rooms on white
  paper) while canvas / SVG already paint `BS_HATCHED`, tiled DIB
  patterns and GDI clips. A save now rasters those brushes and clips
  into the same opaque PNG `ForeignType=Bitmap`. A second save does
  not stack another PNG.
- Vector EMF / WMF ExtTextOut labels now keep their glyphs in LibreOffice.
  Draw still fills Blue 2 for `image/emf` / `image/wmf` instead of
  replaying those records, and a pure-vector PNG bake used to fill only
  the opaque background while canvas / SVG already paint `ExtTextOut` /
  `TextOut`. A save now rasters those glyphs into the same opaque PNG
  `ForeignType=Bitmap`. A second save does not stack another PNG.
- Pure-vector EMF / WMF pictures now keep that drawing in LibreOffice.
  libvisio still emits `image/emf` / `image/wmf`, and Draw fills the
  default Blue 2 graphic style instead of replaying those records, while
  canvas / SVG already paint the vector display list. A save writes an
  opaque PNG `ForeignType=Bitmap` (a wrapped DIB still extracts first;
  otherwise the display list is replayed) so Draw cannot show Blue 2
  through unpainted pixels. A second save does not stack another PNG.
- Text-block `DefaultTabStop` now keeps its interval in LibreOffice.
  libvisio still emits `style:tab-stop-distance`, but Draw's
  drawing-text import ignores it and jumps 0.5" (ODF's default) while
  canvas / SVG already advance with `visioTabFieldStart`. A save writes
  explicit Tabs stops on that interval so Draw collects `style:tab-stops`.
  Authored off-grid stops stay so a 3" tab is not stolen by a 2" grid.
  A second save does not stack another grid.
- Paragraph `HorzAlign=4` ("full") now keeps wrapped justification in
  LibreOffice. libvisio still emits illegal ODF `fo:text-align="full"`,
  so Draw's drawing-text import fell back to left while canvas / SVG
  already map that cell to justify. A save writes `HorzAlign=3`. A
  second save does not change that cell.
- Mixed Latin+CJK and Latin+Arabic Character runs now keep their
  script faces in LibreOffice. `readCharIX` still stores only `Font` /
  `Size`, so an Asian-only or complex-only run already rewrites those
  cells, but a mixed run used to keep Arial on 世界 / سلام while
  canvas / SVG already switch `AsianFont` / `ComplexScriptFont`. A save
  splits the run so each script collects its face and size. Combining
  marks stay on the preceding glyph. A second save does not split
  again.
- Paragraph `BulletFontSize` / `BulletFont` now keep their marker face
  in LibreOffice. Draw's drawing-text import still drops
  `text:bullet-char`, so a save already writes the glyph into the
  paragraph, but that import never sizes the marker from those cells
  while canvas / SVG already paint `effectiveBulletFontSizeInches`. A
  rectangular save whose marker Size or Font disagrees with the body
  splits the prefix onto its own Character run. Field spans stay on
  the body. Curved Text / Shape Inside keep a single run so outline
  plates still copy body Size. A second save does not stack another
  marker.
- Paragraph `SpLine=0` ("set solid") now keeps wrapped leading in
  LibreOffice. libvisio emits `fo:line-height="0%"` whenever that cell
  is ≤ 0, so Draw stacked every line on one baseline while canvas /
  SVG already treat 0 as 1× Size. A save writes the run Size as a
  positive SpLine so Draw takes the length branch. A second save does
  not change that absolute cell.
- Double strikethrough now keeps two bars in LibreOffice. libvisio
  emits `style:text-line-through-type="double"`, but Draw's drawing-text
  import paints a single strike while canvas / SVG already draw two
  bars. A save inserts U+0336 combining overlays, keeps `Strikethrough`
  so Draw still paints one bar, and clears DoubleStrikethrough. Field
  spans grow around those marks so `<fld>` stays on the cached Value.
  A second save does not stack another overlay.
- Theme-only hatch SoftEdges now keep the feathered strokes in
  LibreOffice. `SoftEdgesSize` is not a token; a save already bakes RGB
  hatch and theme-only FillBkgnd into a feathered PNG, but a theme-only
  FillForegnd used to skip so Draw painted a hard hatch while canvas
  already feathers `_colourOrTheme`. A save now resolves the slot
  (document theme, then Office) into that same PNG. A second save does
  not stack another plate.
- Opaque theme fills now keep their colour in LibreOffice. libvisio's
  `VSDFillStyle::override` applies explicit FillForegnd after the theme,
  so `THEMEVAL()` plus `V="0"` painted palette black, while canvas / SVG
  already resolve the QuickStyle slot. A save caches the resolved RGB in
  `V=` and keeps `F="THEMEVAL()"` so Draw paints Office accent colours
  and reopen still round-trips the slot. A second save does not stack
  another colour.
- Cropped pictures now keep that window in LibreOffice. Draw paints
  libvisio's `svg:width` from `ImgWidth` and does not clip to the Foreign
  box, so a save composites the Img* window into a frame-sized PNG and
  resets ImgOffset / ImgWidth / ImgHeight. Canvas / SVG already clip.
  Cropped SoftEdges still composite first so the halo sits on the visible
  window. A second save does not stack another PNG.
- OLE pictures that carry an OlePres WMF/EMF preview now keep that drawing
  in LibreOffice. Draw paints the default Blue 2 graphic style for
  `ForeignType=Object` / `object/ole`, so a save unwraps `\x02OlePres000`
  as `ForeignType=MetaFile` / `EnhMetaFile`. Canvas / SVG already replay
  that preview. A wrapped DIB still becomes PNG through the existing
  metafile bake. A second save does not stack another preview.
- EMF / WMF pictures that wrap a DIB now keep that bitmap in LibreOffice.
  Draw does not paint `ForeignType=EnhMetaFile` / `MetaFile`, so a save
  extracts the embedded DIB and writes PNG `ForeignType=Bitmap`. Canvas /
  SVG already show that raster. Pure-vector metafiles now bake through
  the same PNG path. A
  second save does not stack another PNG.
- Curved Text and Shape Inside lists now keep their bullet marker in
  LibreOffice. Draw's drawing-text import still drops
  `text:bullet-char`, so a rectangular save already writes the glyph
  into the paragraph, but an arc / outline used to skip that bake so
  Draw kept only the hanging inset while canvas / SVG also skipped
  the marker on the path. A save now prefixes the glyph without a
  hanging indent so the existing plates copy it, and canvas / SVG
  prefix the same string. A second save does not stack another marker.
- Shape Inside text that also carries `<fld>` spans now keeps the
  outline flow in LibreOffice. `tokens.txt` has no User rows, so a
  save already writes per-line plates, but a Field section used to
  skip that bake so Draw kept a rectangular field while canvas / SVG
  already wrap the cached Value along the contour. A save now copies
  those characters onto the plates and HideText on the source. A
  second save does not stack another plate.
- Character Overline and LangID RTL now keep their marks on `<fld>`
  runs in LibreOffice. `readCharIX` still skips `XML_OVERLINE` and
  never stores LangID, so a save already writes U+0305 / U+200F, but
  a field used to skip that bake so Draw dropped the line and laid
  digit fields out LTR while canvas / SVG already paint them. A save
  now inserts those marks and shifts the UTF-16 field starts so the
  cached Value stays on the same characters.
- Paragraph `Bullet` lists that also carry `<fld>` spans now keep their
  marker in LibreOffice. Draw's drawing-text import still drops
  `text:bullet-char`, so a save already writes the resolved glyph into
  the paragraph and folds `TextPosAfterBullet` into a hanging indent,
  but a field used to skip that bake so Draw kept only the inset while
  canvas / SVG already paint the glyph beside the field. A save now
  prefixes the glyph and shifts those UTF-16 field starts so the cached
  `Value` stays on the same characters. A second save does not stack
  another marker.
- Mixed Character Highlight now follows Curved Text and Shape Inside
  in LibreOffice. `readCharIX` still skips `XML_HIGHLIGHT`, so mixed
  markers already bake to FillForegnd plates on a rectangular label,
  but an arc / outline used to skip that bake and paint every glyph
  with the first run's style. Canvas / SVG now keep per-run markers
  on the path, and a save puts each run's Highlight on the existing
  Curved Text glyph plates and Shape Inside line plates so Draw
  keeps the magenta / lime bands.
- Curved Text now keeps Overline and LangID RTL marks on each glyph
  in LibreOffice. `readCharIX` still skips `XML_OVERLINE` and never
  stores LangID, so a save already inserts U+0305 / U+200F, but the
  arc bake used to treat those marks as their own plates so Draw
  parked orphan glyphs while canvas / SVG already attach them to the
  preceding letter. A save now clusters those marks onto the glyph.
- Tab fields no longer drop Curved Text, Shape Inside or LangID RTL
  in LibreOffice. `tokens.txt` has no User rows or LangID, so a save
  already bakes those effects, but a `\t` used to skip the whole
  shape so Draw kept a rectangular LTR run while canvas / SVG already
  treat the tab as a gap (arc / outline wrap) or keep the stop
  (LangID). A save now writes those tabs as spaces on the arc and
  outline plates, and still prefixes U+200F on tabbed digit runs.
- Vertical connector labels now keep Rotate with Edge in LibreOffice.
  `_flushText` never emits `style:writing-mode`, so a save already
  swaps 1-D `TextDirection=1` into a tall plate, but that step used
  to drop `User.veAutoRotateLabel` so Draw kept the bar upright while
  canvas / SVG already follow the route tangent. A save now leaves
  that User row through the swap, then writes the same `TxtAngle`
  Rotate with Edge already bakes.
- Paragraph `Bullet` lists now keep their marker in LibreOffice. The
  cells are tokens and libvisio resolves `text:bullet-char`, but Draw's
  drawing-text import keeps only the hanging inset, so a save writes
  the resolved glyph into the paragraph text, folds
  `TextPosAfterBullet` into `IndLeft` / `IndFirst`, and drops the
  Bullet cells so a second save does not stack another marker. Field
  spans shift past that prefix so `<fld>` stays on the cached Value.
- Mixed Character Highlight now wraps to `TxtWidth` in LibreOffice.
  `XML_HIGHLIGHT` is still an empty `readCharIX` case, so a save
  already bakes per-run plates for mixed colours, but a wrapped line
  used to stay one plate so Draw painted a single band while canvas /
  SVG already break at the text box. A save now wraps those plates
  with the same word/space units shape-inside uses. Tab fields stay
  on one line.
- Character Overline on tabbed runs now keeps the line in LibreOffice.
  `readCharIX` still skips `XML_OVERLINE`, so a save already inserts
  U+0305 combining marks, but tabbed runs used to stay native so Draw
  dropped the line while canvas / SVG already paint it past the tab
  field. A save now writes those marks around U+0009 and keeps
  `tabIndices` on the same stop. Field spans grow around those marks
  so `<fld>` stays on the cached Value.
- Word Wrap off on connector labels now keeps the run on one line in
  LibreOffice. `User.veWordWrap` is not a token, so a save already
  expands TxtWidth for a 2-D unwrapped label, but 1-D labels used to
  skip so Draw wrapped a narrow authored TxtWidth while canvas / SVG
  already overflow that box. A save now pins a missing TxtPin first,
  then expands that route plate to the unwrapped line. Vertical text
  and curved text stay native.
- Connector Label Padding now keeps its inset in LibreOffice.
  `User.veLabelPadding` is not a token, so a save already folds 2-D
  padding into Margin cells, but 1-D labels used to skip so Draw
  dropped the inset while canvas / SVG already pad the route plate. A
  save now pins a missing TxtPin first, grows that tight frame by the
  pixel inset, and writes the same margins Draw collects as
  `fo:padding-*`.
- Connector Label Border now keeps its 1px frame in LibreOffice.
  `User.veLabelBorderColor` is not a token, so a save already bakes a
  locked NoFill sibling for 2-D text, but 1-D labels used to skip so
  Draw dropped the stroke while canvas / SVG already paint it around
  the route plate. A save now pins a missing TxtPin first, then places
  that same hairline on the tight frame. Authored TextBkgnd stays
  native.
- Vertical `TextDirection` on connector labels now stays vertical in
  LibreOffice. `_flushText` never emits `style:writing-mode`, so a save
  already folds 2-D `TextDirection=1` into `TxtAngle`, but 1-D labels
  used to skip so Draw laid the run out horizontally at the Begin–End
  centre while canvas / SVG already rotate −90° about the route
  midpoint. A save now pins a missing TxtPin to the route first, then
  swaps the tight plate so Draw's TextBkgnd stands at the elbow
  (adding `TxtAngle` −90° would lay that swapped box back down via
  `librevenge:rotate`). TextDirection=0. Rotate with Edge is dropped
  so reopen does not add a second tangent. Curved text and Shape
  Inside stay native.
- Word Wrap off with tab fields now keeps the stop on one line in
  LibreOffice. `User.veWordWrap` is not a token, so a save already
  expands TxtWidth for a plain unwrapped label, but a tab used to skip
  the bake so Draw wrapped the next field under the first while canvas
  / SVG already pin those fields with `visioTabFieldStart` (libvisio
  `_fillTabSet`). A save now measures that same stop into TxtWidth.
  Glueable 1-D labels, vertical text and curved text stay native.
- Mixed Character Highlight on connector labels now keeps each run
  marker in LibreOffice. `readCharIX` skips Highlight; a save already
  bakes 2-D mixed colours as locked FillForegnd siblings, but 1-D
  labels used to skip so Draw dropped every marker while canvas / SVG
  already paint them on the polyline. A save now pins a missing TxtPin
  to the route first, then places those same plates in that frame.
  Authored TextBkgnd stays native.
- Vertical `TextDirection` now stays vertical in LibreOffice. The cell
  is a token (`readTextBlockIX` stores it) but `_flushText` never emits
  `style:writing-mode`, so Draw laid the run out horizontally while
  canvas / SVG already rotate −90° about the text-block centre. A save
  now folds that rotation into `TxtAngle`, swaps TxtWidth/TxtHeight,
  remaps LocPin and margins, and writes TextDirection=0 so reopen does
  not rotate twice. Mixed Character Highlight plates follow TxtPin on
  that rotated frame. Glueable 1-D labels, curved text and Shape Inside
  stay native.
- Mixed Character Highlight with tab fields now keeps each run marker
  in LibreOffice. `readCharIX` skips Highlight; a save already bakes
  mixed colours and explicit newlines as locked FillForegnd siblings,
  but a tab used to skip the whole bake so Draw dropped every marker
  while canvas / SVG already pin those fields with `visioTabFieldStart`
  (libvisio `_fillTabSet`). A save now places each highlighted field
  at that same stop. Vertical text and 1-D labels stay native.
- Mixed Character Highlight with explicit newlines now keeps each run
  marker in LibreOffice. `readCharIX` skips Highlight; a save already
  bakes single-line mixed colours as locked FillForegnd siblings, but
  a newline used to skip the whole bake so Draw dropped every marker
  while canvas / SVG already wrap those plates. A save now stacks the
  same nowrap advance per line. Tabs, vertical text and 1-D labels
  stay native.
- Connector labels that have `TxtWidth` but no `TxtPin` now sit on the
  route in LibreOffice. Canvas / SVG already centre a tight plate on
  the polyline whenever `TxtPin` is missing. Draw constructs
  `m_txtxform` as soon as `TxtWidth` exists, and `XForm` defaults the
  pin to 0, so the label parked at the 1-D local origin (or the
  Begin–End box when both cells are missing). A save now writes the
  route midpoint into `TxtPin` and a tight `TxtWidth` so left-align
  cannot drift a box-width away. Authored `TxtPin` stays native.
- Theme-only FillForegndTrans now keeps the wash in LibreOffice.
  `FillForegndTrans` is a token, but `VSDXTheme::getThemeColour` only
  maps 0–8 and `VSDFillStyle::override` applies explicit FillForegnd
  after the theme, so THEMEVAL() plus `QuickStyleFillColor=9` painted
  faded black while canvas already multiplies `_colourOrTheme` by
  (1 − FillForegndTrans). A save now resolves the slot (document
  theme, then Office) into FillForegnd and keeps FillForegndTrans so
  Draw still composites over the page. Theme-only FillBkgndTrans
  freezes the same way. Opaque theme fills still keep THEMEVAL().
- Hatch SoftEdges whose FillBkgnd is theme-only now keeps the wash in
  LibreOffice. `SoftEdgesSize` is not a token; a save already bakes RGB
  hatch FG/BG into a feathered PNG, but a theme-only FillBkgnd used to
  skip so Draw painted a hard hatch (or a hollow plate) while canvas
  already samples `_colourOrTheme`. A save now resolves the slot
  (document theme, then Office) into that same PNG. Theme-only
  FillForegnd still stays native so audit theme cells survive.
- Theme-only LineColorTrans now freezes when a FillForegndTrans ribbon
  cannot bake. `LineColorTrans` is not a token; rectangles already
  become a sibling ribbon, but a geometry-less body used to leave
  THEMEVAL() so Draw painted the slot fully opaque. A save now
  resolves the slot (document theme, then Office) and premultiplies
  toward white the same way RGB LineColorTrans already does.
- Mixed Character Highlight now keeps each run marker in LibreOffice.
  `readCharIX` skips Highlight; a uniform marker already becomes
  TextBkgnd, but mixed colours cannot share that cell so Draw dropped
  every marker. A save now inserts locked FillForegnd siblings that
  carry each highlighted run (same nowrap advance as curved-text),
  hides the source label, and keeps the Highlight cells for Visio.
- Theme-only LineColorTrans ribbons now keep the theme wash in LibreOffice.
  `LineColorTrans` is not a token, so a save already bakes a FillForegndTrans
  sibling. Theme-only LineColor used to write a black FillForegnd fallback
  (writer emits hex whenever colour is set), so Draw painted grey while
  canvas already strokes `_colourOrTheme`. A save now resolves the slot
  (document theme, then Office) into that ribbon FillForegnd and keeps
  FillForegndTrans so Draw still composites over the body.
- Theme-only Glow halos that cannot become a Gaussian PNG (spline or
  multi-subpath bodies) now keep their colour in LibreOffice. `Glow*` is
  not a token, so the slot had to survive as `QuickStyleLineColor`, but
  `VSDXTheme::getThemeColour` only maps 0–8 onto dk1/lt1/accent1–6/bkgnd
  and `VSDLineStyle::override` applies the explicit `LineColor` after the
  theme — Draw painted an opaque black halo. A save now resolves the slot
  (document theme, then Office) and premultiplies the canvas
  `0.4 + 0.6 x GlowColorTrans` halo fade toward white, for both the
  Line-stealing path and the sibling plate.
- Theme-only hard-edged ShdwForegndTrans now keeps the fade in LibreOffice.
  `ShdwForegndTrans` is not a token and `xmlStringToColour` zeros alpha,
  so Draw painted THEMEVAL() `draw:shadow` fully opaque, while canvas
  already multiplies `_colourOrTheme` by (1 − ShdwForegndTrans). A save
  now resolves the slot (document theme, then Office) and premultiplies
  toward white the same way RGB shadows already do. Soft theme shadows
  still keep THEMEVAL() after the Gaussian PNG bake.
- Theme-only Character ColorTrans now keeps the fade in LibreOffice.
  `ColorTrans` is not a token (`readCharIX` has no case);
  `xmlStringToColour` also zeros alpha. A save used to leave THEMEVAL()
  Color so Draw painted the slot fully opaque, while canvas already
  multiplies `_colourOrTheme` by (1 − ColorTrans). A save now resolves
  the slot (document theme, then Office) and premultiplies toward white
  the same way RGB ColorTrans already does.
- Theme-only FillGradient / LineGradient stops now keep their wash in
  LibreOffice. Those sections are not tokens; a save used to skip
  theme-only stops so SoftEdges / Reflection PNGs stayed empty and an
  unfilled LineGradient ribbon baked black, while canvas
  `_buildGradientShader` already samples `_colourOrTheme`. A save now
  resolves each slot (document theme, then Office) into those PNG
  samples and into the ribbon FillForegnd / FillBkgnd Draw collects.
- Theme-only hard-edged shadows on an oblique page now keep the shear
  in LibreOffice. `ShdwType` / `ShdwObliqueAngle` / `ShdwScaleFactor`
  are not tokens; a save used to skip theme-only ShdwForegnd so Draw
  painted an unsheared `draw:shadow`, while canvas `_applyPageShadowXform`
  already shears `_colourOrTheme`. A save now resolves the slot
  (document theme, then Office) into the same sheared sibling RGB
  shadows use.
- Theme-only SoftEdges now keeps the feathered silhouette in
  LibreOffice. `SoftEdgesSize` is not a token; a save used to skip
  theme-only FillForegnd / LineColor so Draw painted a hard fill or
  stroke, while canvas `_fillColour` / `_colourOrTheme` already
  feathers the theme colour. A save now resolves the slot (document
  theme, then Office) into the same PNG plate RGB SoftEdges uses.
- Theme-only ShadowBlur now keeps the Gaussian silhouette in
  LibreOffice. `ShadowBlur` is not a token; a save used to skip
  theme-only ShdwForegnd so Draw painted a hard `draw:shadow`, while
  canvas `_drawShadow` already blurs `_colourOrTheme`. A save now
  resolves the slot (document theme, then Office) into the same PNG
  plate RGB shadows use.
- Theme-only unfilled-stroke Reflection now keeps the mirror in
  LibreOffice. `Reflection*` is not a token; a save used to skip
  theme-only LineColor so Draw dropped the band, while canvas
  `_drawReflection` already paints `_colourOrTheme`. A save now resolves
  the slot (document theme, then Office) into the same PNG band RGB
  strokes use.
- Theme-only Glow now keeps the Gaussian halo in LibreOffice. Glow* is
  not a token; a save used to emit a hard LineWeight / Fill ribbon so
  THEMEVAL() survived, while canvas `_drawGlow` already blurs the theme
  colour. A save now resolves the slot (document theme, then Office)
  into the same PNG plate RGB glow uses.
- Connector labels without `TxtPin` now sit on the route midpoint in
  LibreOffice. Draw used the 1-D XForm box (Begin–End centre) when
  `m_txtxform` was missing; canvas / SVG already pin a tight plate on
  the polyline. A save writes that midpoint into `TxtPin` / `TxtWidth`.
- Digit-only Arabic / Hebrew `LangID` runs now keep RTL layout in
  LibreOffice. Character `LangID` is not a token; Draw used to lay out
  `"123"` as LTR. A save prefixes U+200F when canvas / SVG already treat
  the run as RTL from LangID. Strong Arabic / Hebrew letters are left
  alone.
- draw.io merged table cells now stay hidden in LibreOffice.
  `User.veCovered` is not a token; Draw used to paint the 0.01" park
  rectangle. A save writes Geometry `NoShow`, `HideText`,
  `FillPattern=0` / `LinePattern=0` on those cells and stores
  `veCoveredHidden` so Unmerge can restore them.
- draw.io collapsed containers now hide their children in LibreOffice.
  `User.veCollapsed` is not a token; Draw used to paint every descendant.
  A save writes Geometry `NoShow`, `HideText`, `FillPattern=0` /
  `LinePattern=0`, and zero `ImgWidth` / `ImgHeight` on those children
  and stores `veCollapsedHidden` so Unfold can restore them.
- draw.io Flow Animation now keeps a dashed stroke in LibreOffice.
  `User.veFlowAnimation*` is not a token; Draw used to paint a solid
  route. A save flattens the same 8 CSS-px dash canvas / SVG synthesise
  into MoveTo/LineTo and writes `veFlowAnimation=0` so a reopen does
  not dash the segments twice.
- Arrowed custom / Flow dashes now keep a single head in LibreOffice.
  libvisio hangs `draw:marker-*` on every open subpath, so flattening
  dashes used to duplicate the arrow. A save bakes Begin/EndArrow as
  Geometry first, then the dashes, and clears the marker cells.
- Unfilled 1-D stroke Glow now keeps the Gaussian halo in LibreOffice.
  Canvas `_drawGlow` blurs a path stroke; a save used to emit a hard
  FillForegndTrans ribbon because Foreign cannot hang on a zero-height
  1-D XForm (`Glow*` is not a token). A 2-D PNG plate is sized to the
  glow ribbon. Theme-only 1-D now freezes that colour into the same PNG.
- Filled LineColorTrans / LineGradient with LinePattern 2–23 now keep dash
  gaps in LibreOffice. Draw used to skip the sibling ribbon (opaque dashes
  on the body). A save puts per-dash filled ribbons on the locked sibling
  whose FillForegndTrans Draw collects.
- Filled open-path LineColorTrans now keeps arrowheads in LibreOffice. A
  save used to skip the ribbon so Draw painted an opaque stroke. Arrow
  Geometry now rides the sibling (stroke colour), and the source drops
  Begin/EndArrow.
- Unfilled 1-D stroke Reflection now keeps the mirror in LibreOffice.
  Canvas inflates zero-area 1-D bounds by half LineWeight; a save used to
  skip `is1D` so Draw dropped the band (`Reflection*` is not a token). A
  2-D PNG plate is sized to the stroke ribbon.
- FlipX / FlipY Curved Text and Shape Inside now keep the upright arc /
  outline bands in LibreOffice. Canvas extra-mirrors text about TxtPin
  (`_textFlip*`) after the shape XForm; a save used to skip those leaves
  so Draw showed a rectangular label. Glyph / band plates now apply the
  same TxtPin mirror before the shape Flip.
- Sketch jiggle with open arrowheads now keeps both the two-pass stroke
  and the heads in LibreOffice. A save used to skip Sketch when
  Begin/EndArrow sat on an open path (two jiggle plates would duplicate
  markers). Jiggle plates drop the arrow cells; the source bakes filled
  arrow Geometry.
- Geometry-less Edraw labels no longer keep a stale `FillPattern=1` box.
  「专业知识」 on `人才招聘冰山模型.vsdx` is white text on a purple
  FillGradient header; omitting Geometry means Visio paints text only, but
  a save that kept FillPattern=1 let Edraw fill the text box and hide the
  glyphs. The header wash still bakes classic FillPattern 25–40 (libvisio
  has no FillGradient token). A save now writes FillPattern=0 on those
  text-only leaves.
- Omitted `FillPattern` with `FillGradientEnabled` now keeps the wash in
  the editor and in LibreOffice. Edraw chevrons (for example the large
  arrow under「数据治理组织每个模块都有责任人」) default to libvisio's
  `FillPattern=0`, so Draw stayed hollow and a companion LineGradient
  ribbon stole the body. A save writes classic FillPattern 25–40 plus
  FillForegnd/FillBkgnd from the stops.
- Closed 2-D arrow cells no longer block SoftEdges (or LineColorTrans
  ribbons) in LibreOffice. Draw / libvisio suppress markers on
  Z-closed subpaths, so a save used to keep a hard native stroke on a
  feathered fill. Open-path arrows still stay native so the crisp heads
  canvas paints after the feather are not lost inside the PNG.
- Filled CompoundType LineColorTrans / LineGradient now keep rails and
  wash in LibreOffice. Draw used to skip the sibling ribbon because
  CompoundType is not a token, then paint opaque parallel strokes.
  A save puts the same per-rail ribbons SoftEdges already uses onto
  the locked sibling whose FillForegndTrans Draw collects.
- LineGradient unfilled-stroke Reflections now keep the wash in LibreOffice.
  Draw used to show a solid LineColor ring because neither cell is a
  token. A save samples the resolved-RGB LineGradient into the same
  mirrored PNG band dashes and CompoundType rails already use.
- CompoundType unfilled-stroke Glow now keeps the halo in LibreOffice.
  Draw used to drop the effect because the bake skipped CompoundType
  (not a token). Canvas `_drawGlow` blurs the path, not the rails, so a
  save paints the same Gaussian PNG ring a solid stroke already uses.
- FlipY picture Reflections now keep the mirrored band in LibreOffice.
  Draw used to FlipY the PNG sibling twice (and show the original
  bottom nearest). A save FlipY's the bitmap before the mirror so the
  visual bottom is nearest, places the plate with the same FlipY-aware
  LocPin the filled / stroke mirrors use, and does not copy FlipY onto
  the PNG.
- Dashed and CompoundType unfilled-stroke Reflections now keep gaps and
  rails in LibreOffice. Draw used to show a solid mirrored ring (or drop
  the mirror for CompoundType, which is not a token). A save paints the
  same per-dash / per-rail ribbons SoftEdges already uses into the PNG
  band.
- FlipY unfilled-stroke Reflections now keep the mirrored band in
  LibreOffice. Draw used to drop the effect because copying FlipY onto
  the PNG would mirror the band twice. A save places the plate with the
  same FlipY-aware LocPin the filled mirror uses and flips the PNG so
  the fade still points away from the shape.
- Rounding SoftEdges now keep filleted corners in LibreOffice. Draw
  collects `Rounding` on native geometry, but a save used to drop the
  fill onto a sharp PNG box. The same fillet canvas / SVG / libvisio
  use is sampled into the padded PNG sibling.
- LineGradient SoftEdges now keep both the feather and the stroke wash
  in LibreOffice. Neither cell is a token, so Draw used to show a
  feathered fill (or a hard filled ribbon) with an opaque outline. A
  save samples the resolved-RGB LineGradient into the padded PNG
  sibling and drops fill and line.
- CompoundType 1–4 SoftEdges now keep both the feather and the thick/thin
  rails in LibreOffice. Neither cell is a token, so Draw used to show a
  feathered fill with a hard single stroke or hard parallel rails on top.
  A save paints the rails into the padded PNG sibling and drops fill and
  line.
- Gradient and hatch SoftEdges with a stroke now keep both the wash and
  the feathered outline in LibreOffice. Draw used to show a feathered
  fill PNG with a hard native stroke on top. A save paints the wash and
  the solid or dashed stroke into one padded PNG sibling and drops both.
- Filled shapes with dashed SoftEdges now keep both the feather and the
  dash gaps in LibreOffice. Draw used to show a feathered fill with hard
  LinePattern dashes on top. A save paints the fill and per-dash ribbons
  into one padded PNG sibling and drops fill and line.
- Unfilled dashed SoftEdges now keep both the feather and the gaps in
  LibreOffice. `SoftEdgesSize` is not a token, so Draw used to paint hard
  LinePattern dashes (or a solid ring if the stroke were baked whole). A
  save paints per-dash ribbons into the locked PNG sibling and drops the
  source line.
- Round-capped strokes with an explicit miter join now keep sharp elbows
  in LibreOffice. `_lineProperties` maps join from LineCap only, so Draw
  used to round every corner while canvas / SVG honoured `User.veLineJoin`.
  A save flattens LineCap to extended when the path actually turns;
  straight edges keep the round endpoints.
- Filled 2-D `LineColorTrans` now composites over the body fill in
  LibreOffice. Draw has no stroke alpha token, so a save used to
  premultiply toward white and paint an opaque gray outline on coloured
  fills. A locked sibling ribbon carries FillForegndTrans (and a long
  `veMiterLimit` spike on sharp elbows) and the source line is dropped.
- `User.veMiterLimit` above LibreOffice's default 4 now keeps the long
  canvas spike after a save into Draw. `_lineProperties` never emits
  `svg:stroke-miterlimit`, so Draw used to bevel every elbow whose ratio
  exceeds 4. A save expands an unfilled solid polyline to a filled ribbon
  whose outline uses that limit, then drops the User row. Limits below 4
  still chamfer; straight edges and limits at 4 stay native.
- `User.veMiterLimit` tighter than LibreOffice's default 4 now survives a
  save into Draw. `_lineProperties` never emits `svg:stroke-miterlimit`, so
  Draw used to keep a long miter while this editor already clipped the same
  elbow. A save chamfers those corners as LineTo (the same cut bevel join
  already uses) and drops the User row. Limits at or above 4 stay native.
- Built-in `LinePattern` 2–23 now keep their gaps when a save bakes a
  LineColorTrans / LineGradient ribbon for LibreOffice. The ribbon is a
  filled silhouette, so Draw used to show a solid transparent band while
  this editor already dashed the stroke. A save flattens those ids to
  MoveTo/LineTo first — the same path custom `User.veDashPattern` already
  uses — then ribbons each dash. Opaque dashed strokes stay native.
- Geometry `SoftEdgesSize` with a classic `FillPattern` 2–24 hatch now
  survives a save into LibreOffice. SoftEdgesSize is not a token, so Draw
  used to show a hard hatch while this editor already feathered the same
  libvisio strokes. A save paints those strokes into the locked PNG sibling,
  writes SoftEdgesSize 0 and drops the source fill so Draw shows the plate.
  Theme-only hatch colours stay native.
- Geometry `SoftEdgesSize` with a resolved-RGB fill gradient now survives a
  save into LibreOffice. `tokens.txt` has no SoftEdgesSize and no
  FillGradient, so Draw used to show a hard classic 25–40 wash (or a solid)
  while this editor already feathered the true stops. A save paints that
  wash into the locked PNG sibling canvas already uses, writes SoftEdgesSize
  0 and drops the source fill so Draw shows the plate. Theme-only stops
  stay native.
- draw.io custom `User.veDashPattern` now survives a save into LibreOffice.
  `_lineProperties` only dashes ids 2–23, so arrays that are not those ids
  (and every `veFixedDash` CSS-px sequence) used to snap to a neighbour and
  look wrong in Draw. A save bakes the effective dash/gap lengths as
  MoveTo/LineTo subpaths, writes LinePattern 1, and drops the User rows so
  this editor does not dash the geometry a second time. Canvas and SVG
  already painted the custom array.
- Cropped picture `Reflection*` now survives a save into LibreOffice. Those
  cells are not tokens; ImgOffset / ImgWidth / ImgHeight *are* collected, so
  mirroring the raw Foreign bitmap used to reflect pixels the crop hides.
  A save composites the visible window into the frame the same way canvas
  and SVG already do, then bakes that clipped bitmap into the locked PNG
  sibling. Uncropped pictures keep the previous whole-bitmap path.
- Cropped picture `SoftEdgesSize` now survives a save into LibreOffice.
  `tokens.txt` has no SoftEdgesSize; ImgOffset / ImgWidth / ImgHeight *are*
  collected, so feathering the raw bitmap used to put the halo on hidden
  pixels. A save composites the visible window into the Foreign frame,
  feathers that box the same way canvas and SVG already do, writes
  SoftEdgesSize 0 and fills Img* so Draw does not crop the halo off.
- Visio `CompoundType` 4 (triple) now has a translation in every shipped
  locale. The Format control was localised only in English and Chinese, so
  the other 35 locales fell back to the raw `compoundTriple` key.
- Round-trip checks now treat the render-only siblings a save adds for Draw
  (`LibvisioPageColor`, the Gaussian shadow / glow / reflection PNGs, …) as
  write-time artifacts rather than model drift, and compare effect cells
  against what the writer actually emits. The new public
  `isLibvisioBakePlate` and `shadowCellsForLibvisioWrite` expose that
  contract — the latter mirrors `reflectionForLibvisioWrite` by reporting
  the `ShdwPattern` / `ShadowBlur` zeroing a Gaussian PNG bake performs.
- Page `PageColor` now survives a save into LibreOffice. The cell is not a
  token (`readPageSheetProperties` only stores size, scale, and
  `ShdwOffset*`), so a save prepends a locked full-page plate Draw can
  fill. Clearing the page colour drops that plate. Canvas and SVG already
  painted the sheet.
- Shape `Reflection*` now survives a save into LibreOffice. Those cells
  are not tokens, so a filled 2-D shape bakes a locked sibling plate
  (`FillForegndTrans` is collected) clipped by `ReflectionSize`, an
  unfilled 2-D stroke bakes a locked PNG band of the mirrored stroke
  (filling the mirror would paint an interior Draw leaves empty), and a
  Foreign picture bakes a locked Gaussian PNG sibling of the same mirrored
  bitmap canvas and SVG already paint, then `ReflectionSize` is written 0.
  Theme-only stroke colours and FlipY keep the native cells.
- Paragraph `Bullet` 1–7 now paint the same default glyphs LibreOffice’s
  libvisio importer emits (`VSDContentCollector::_bulletFromParaFormat`).
  Types 5 and 6 were a black diamond and an en-dash; they are now U+2756
  and U+27A2 so canvas, SVG, and Draw agree when `BulletStr` is empty.
  Every classic `FillPattern` 2–40, `LinePattern` 2–23 and bullet 1–7 is
  in the style-parity SVG check; soffice opens a seven-style list.
- Visio `CompoundType` 4 (triple) is selectable in Format and no longer
  clamped to thin-thick. Canvas, SVG and the LibreOffice rail bake already
  knew type 4; the editor control did not.
- `ConLineJump*` hops and Image Properties (Transparency / Brightness /
  Contrast / Blur) now survive a save into LibreOffice. libvisio has no
  collector for those cells, so a save bakes hops as `ArcTo` / `MoveTo` /
  `LineTo` (then `ConLineJumpCode=1`) and bakes picture tone into a PNG
  with the cells reset. Unchanged packages stay byte-identical.
- Marker ids whose libvisio `_linePropertiesMarkerPath` is still a TODO stub
  (26, 31–34, 36–38, 40, 43–45) now bake as Geometry on save so LibreOffice
  Draw does not reuse a sibling silhouette. Canvas and SVG paint the
  documented Visio variants (three-bar CF, circle+bars/diamond, unfilled
  double triangle, double open arrow) instead of those stubs.
- Picture `SoftEdgesSize` now survives a save into LibreOffice on uncropped
  2-D Foreign bitmaps. The cell is not a token, so a save feathers PNG
  alpha with the same SourceAlpha blur canvas and SVG use, then writes
  SoftEdgesSize 0. Cropped pictures keep the cell so ImgOffset still
  frames the original pixels. Geometry-only SoftEdges cannot be a raster.
- Character `Letterspace` now survives a save into LibreOffice. The cell is
  not a token, but `FontScale` is collected as `style:text-scale`. A save
  folds tracking into FontScale with the same 0.55×Size mean Latin advance
  canvas and SVG already use, then writes Letterspace 0. Draw sees glyph
  width scaling; reopen here still paints as tracking.
- Character `Overline` and `Glow*` now survive a save into LibreOffice.
  libvisio's `readCharIX` has an empty `Overline` case, so a save inserts
  combining U+0305 marks and clears the cell. Glow cells are not tokens:
  an unfilled 1-D stroke bakes a `FillForegndTrans` ribbon, an unfilled
  2-D stroke with resolved RGB bakes a locked Gaussian PNG ring, and a
  filled 2-D (NoLine or already stroked) bakes a locked Gaussian PNG sibling
  (`LibvisioGlow.{id}`) when RGB is resolved so Draw shows the same blur
  canvas already paints. A Foreign picture bakes the
  same Gaussian PNG ring around the image frame. Theme-only glow
  resolves the slot into that PNG so Draw keeps the blur. Then `GlowSize` is
  written 0.
- draw.io Sketch now survives a save into LibreOffice. `User.veSketch*`
  rows are not tokens, so a save maps hachure / cross-hatch / dots onto
  classic `FillPattern` 2–24 (`draw:fill=hatch`, holes stay transparent)
  and bakes the two jiggle strokes as locked siblings
  (`LibvisioSketch.{0,1}.{id}`), then writes `veSketch=0`. Canvas and SVG
  already painted the rough.js treatment. Arrowed strokes keep native
  Sketch so Draw does not hang extra markers.
- draw.io Glass now survives a save into LibreOffice. `User.veGlass` is
  not a token, so a save inserts a locked white top-light sibling
  (`LibvisioGlass.{id}`) whose `FillForegndTrans` Draw collects, then
  writes `veGlass=0`. Canvas and SVG already painted the glossy wave.
- draw.io Shape Opacity now survives a save into LibreOffice.
  `User.veOpacity` is not a token, so a save folds the fade into
  `FillForegndTrans` (and line / image / text transparency) which
  libvisio maps to `draw:opacity`, then drops the User row. Canvas and
  SVG already composited the cell as one layer.
- draw.io Label Border now survives a save into LibreOffice.
  `User.veLabelBorderColor` is not a token, so a save inserts a locked
  NoFill sibling (`LibvisioLabelBorder.{id}`) whose `LineColor` Draw
  collects, then drops the User row. Canvas and SVG already stroked the
  text frame. Glueable connector labels keep the User row — their loose
  plate depends on layout.
- draw.io Label Padding now survives a save into LibreOffice.
  `User.veLabelPadding` is not a token, so a save adds the pixel inset
  into `LeftMargin` / `RightMargin` / `TopMargin` / `BottomMargin`
  (`fo:padding-*`) which libvisio collects, then drops the User row.
  Canvas and SVG already padded tight plates and text-flow bands.
  Glueable connector labels keep the User row — their loose plate
  depends on layout.
- draw.io Word Wrap off now survives a save into LibreOffice.
  `User.veWordWrap` is not a token, so a save expands `TxtWidth` to the
  unwrapped line plus margins (`svg:width` Draw wraps against) and
  drops the User row. Left-aligned overflow keeps the original left
  edge; centered overflow grows equally. Canvas and SVG already skipped
  wrapping. Glueable connector labels, vertical text, curved text and
  tabbed labels keep the User row.
- Geometry `SoftEdgesSize` now survives a save into LibreOffice on filled
  2-D vectors. The cell is not a token, so a save bakes a locked Foreign
  sibling (`LibvisioSoftEdges.{id}`) whose PNG alpha uses the same
  SourceAlpha feather canvas and SVG already paint, then writes
  SoftEdgesSize 0 and drops the source fill so Draw shows the plate.
  Pictures still feather in place. 1-D, hatches, gradients and theme-only
  fills keep the cell. Unfilled 2-D strokes now bake the same way: a save
  rasters the stroke ring (padded for LineWeight and the blur halo),
  writes SoftEdgesSize 0 and drops the source line so Draw shows the plate.
  Filled 2-D shapes that also paint a solid stroke bake fill and stroke
  into one padded plate and drop both, so Draw does not keep a hard outline.
  Dashes, compound rails and arrows stay native.
- `ShadowBlur` now survives a save into LibreOffice on filled 2-D vectors
  and Foreign pictures. The cell is not a token; libvisio only emits a
  hard `draw:shadow`. A save bakes a locked Foreign sibling
  (`LibvisioShadow.{id}`) whose PNG is the same Gaussian silhouette canvas
  and SVG already paint, then writes ShdwPattern 0 and ShadowBlur 0 so
  Draw does not add a second hard copy. Theme-only shadow colours, 1-D
  and unrecognised geometry keep the native cells.
- PageSheet `ShdwType` / `ShdwObliqueAngle` / `ShdwScaleFactor` now survive a
  save into LibreOffice. Those cells are not in `tokens.txt` at all —
  `readPageSheetProperties` collects only `ShdwOffset*` — so Draw painted a
  plain offset copy of every shadow on an oblique page. A hard-edged shadow
  now bakes the same scaled, sheared silhouette canvas and SVG already paint
  into a locked NoLine sibling (`LibvisioPageShadow.{id}`) whose
  `FillForegndTrans` Draw collects, then writes `ShdwPattern` 0 so Draw adds
  no second unsheared copy. A blurred shadow on the same page bakes a
  Gaussian PNG sibling (`LibvisioShadow.{id}`) whose inner box is the
  sheared silhouette's AABB, so Draw keeps both the blur and the
  page shear. 1-D, groups and theme-only shadow colours keep the native
  cells.
- draw.io Curved Text now survives a save into LibreOffice. `User.veCurvedText`
  is not a token, so a save places locked per-glyph siblings
  (`LibvisioCurved.{i}.{id}`) along the same quadratic arc canvas and SVG
  already paint, writes `HideText=1` on the source and drops the User row.
  Glueable connector labels, flipped shapes, vertical text and tabbed
  labels keep the User row.
- draw.io Shape Inside now survives a save into LibreOffice.
  `User.veShapeInside` is not a token, so a save places locked per-line
  siblings (`LibvisioShapeInside.{i}.{id}`) in the same outline bands
  canvas and SVG already paint, writes `HideText=1` on the source and
  drops the User row. Glueable connector labels, flipped shapes, vertical
  text, curved text and tabbed labels keep the User row.
- draw.io Rotate with Edge now survives a save into LibreOffice.
  `User.veAutoRotateLabel` is not a token, so a save writes the same upright
  route tangent canvas and SVG already paint into `TxtAngle` (which
  libvisio collects) and drops the User row. Vertices stay native.
- `BeginArrowSize` / `EndArrowSize` now survive a save into LibreOffice on
  plain strokes, not only on compound / gradient / transparent connectors.
  libvisio sizes markers from LineWeight (`_linePropertiesMarkerScale *
  (0.1/(w²+1)+2.54*w)`); `tokens.txt` has no arrow-size cell. A non-default
  size bucket that disagrees with that formula bakes the marker as Geometry
  at the authored size. Untouched Visio bucket 2 (`0.125"`) keeps native
  `BeginArrow` / `EndArrow`, including ids whose Draw scale is 0.7 / 1.2.
  Open arrow ids become filled ribbons of the original weight so they keep
  their silhouette after a CompoundType rail rewrite. `TextBkgndTrans` and
  layer `ColorTrans` have no VSDX collector case (`xmlStringToColour` also
  zeros alpha), so a save premultiplies those into RGB toward white and
  writes Trans=0.
- Shape-level `Rounding` is now written as 0 after the RelQuadBezTo bake so
  Visio does not fillet already-rounded corners a second time. Bevel joins
  with a round `LineCap` bake LineTo chamfers and flatten the cap to
  extended: `_lineProperties` derives join from LineCap only, so Draw used
  to round those elbows. Character `ColorTrans`, filled 2-D `LineColorTrans`,
  and `ShdwForegndTrans` premultiply into RGB toward white (`xmlStringToColour`
  always stores Colour.a = 0, and none of those cells are tokens). Unfilled
  strokes still use a `FillForegndTrans` ribbon. Theme-bound colours with no
  resolved RGB keep THEMEVAL().
- Unfilled `CompoundType` 2–4 (thick-thin / thin-thick / triple) now bake
  each rail as a filled ribbon of that rail's own width so LibreOffice keeps
  the contrast. libvisio has no CompoundType token and LineWeight is
  shape-level, so the previous parallel *strokes* all used the thinnest
  rail and Draw painted equal hairlines. Filled 2-D and dashed unfilled
  strokes still use those equal-width strokes so the body Fill and
  LinePattern 2–23 stay intact. 1-D type 3/4 is in the soffice cross-check.
- `CompoundType` 3 (thin-thick) and 4 (triple) now have the same LibreOffice
  rail-bake coverage as types 1–2. libvisio has no CompoundType token, so a
  save still emits parallel Geometry rails and zeros the cell. Arrowed 1-D
  compound / gradient / trans bakes now use the filled marker polygons
  `VSDContentCollector::_linePropertiesMarkerPath` defines for more
  BeginArrow/EndArrow ids (6, 10, 12, 15, 17–18, 20–21, 38, 42), instead of
  collapsing them to the default triangle. Newly created transparent 1-D
  connectors round-trip as a `FillForegndTrans` ribbon plus Geometry arrows,
  matching Draw (`tokens.txt` has no LineColorTrans / BeginArrowSize).
- Character `Highlight` now also writes `TextBkgnd` when the text block has
  no fill of its own. libvisio's `readCharIX` skips the Highlight cell, but
  `VSDContentCollector` paints `TextBkgnd` as span `fo:background-color`, so
  Draw used to drop the marker colour on save. Canvas and SVG still paint
  the tighter highlight halo and ignore a TextBkgnd that only exists as that
  stand-in, so a save/reopen here does not double-fill.
- Character `Font` for an Asian-only run whose Visio face is a Latin UI font
  (Arial, Calibri, …) now writes the `AsianFont` (or Microsoft YaHei). Han,
  Hangul and Kana are included. Complex-script-only runs write
  `ComplexScriptFont` into `Font` and `ComplexScriptSize` into `Size`.
  libvisio's `readCharIX` has none of those tokens, so Draw used to load Arial at
  the Latin `Size` and tofu or shrink labels Visio rendered with the locale
  face. Mixed Latin+CJK runs keep `Font` / `Size` so Visio's Latin glyphs
  do not change. Unknown `FillPattern` ids above 40 snap to solid `1`
  (Draw's fallback for those ids is the *background* colour). Explicit
  round joins on a square/flat cap bake RelQuadBezTo fillets (half the
  line weight) so Draw does not miter them: `_lineProperties` derives
  join from LineCap only. Bevel joins bake LineTo chamfers; arcs joins
  bake the same fillets as round (matching canvas). The Rounding cell
  stays 0 so Visio does not fillet the already-baked corners a second time.
- Arrowed 1-D `CompoundType` / `LineGradient` / `LineColorTrans` strokes now
  bake Begin/EndArrow as filled Geometry before the rail or ribbon rewrite,
  then clear the arrow cells. libvisio hangs a marker on every open path and
  does not collect `BeginArrowSize`, so a double-line connector with arrows
  used to either skip the rails or duplicate arrowheads, and a gradient or
  transparent connector with arrows used to flatten to an opaque solid.
  Ordinary arrowed connectors (no compound / gradient / trans) still keep
  `BeginArrow` so Draw can use its built-in markers.
- Arrow-less 1-D / unfilled 2-D `LineColorTrans` strokes now bake a filled
  ribbon with `FillForegndTrans` when saved for LibreOffice. libvisio's
  VSDX token map has no LineColorTrans cell, and `xmlStringToColour`
  always stores Colour.a = 0, so Draw used to paint every VSDX stroke
  opaque. XForm1D / glue stay in place; connectors with arrows and filled
  2-D shapes still keep `LineColor`. Character `ColorTrans` is similarly
  alpha-stripped by libvisio but now paints (canvas + SVG) and round-trips.
- Arrow-less 1-D `LineGradient` strokes now bake the same filled ribbon as
  2-D when saved for LibreOffice. libvisio has no LineGradient token, so a
  connector without arrowheads used to reopen as a solid stroke in Draw;
  XForm1D / glue cells stay in place, matching the CompoundType rail bake.
  Connectors with arrows still keep `LineColor`. Visio `LineCap` 0/1/2
  (round / extended / square, the mapping `VSDContentCollector` uses) now
  round-trips through agent ops, SVG `stroke-linecap`, and the writer.
  Character `Overline` is skipped by libvisio `readCharIX` but now paints
  and round-trips alongside Highlight. `CompoundType` 2 (thick-thin) is
  included in the LibreOffice style bake coverage.
- Arrow-less 1-D `CompoundType` strokes and unfilled 2-D `LineGradient`
  strokes now survive a save into LibreOffice. libvisio hangs a marker on
  every open path, so connectors with arrows still skip the rail rewrite;
  a double-line without arrows bakes the same parallel Geometry rails as
  2-D. `tokens.txt` has no LineGradient cell, so an unfilled 2-D gradient
  stroke is expanded into a closed ribbon and written as classic FillPattern
  25–40. Character `Highlight` is skipped by libvisio `readCharIX` but now
  parses, paints (canvas + SVG), and round-trips in XML.
- DiagramML `CubBezTo` / `QuadBezTo` / `RelArcTo` (and the other VSDX-era
  Rel* rows libvisio's token map does not name) now parse and paint, and a
  save rewrites them to the RelCubBezTo / RelQuadBezTo / ArcTo / PolylineTo
  / InfiniteLine / Spline / NURBS rows LibreOffice actually collects. A
  VDX coverage drawing that used to lose its Béziers on import now round-
  trips through Draw.
- Modern `FillGradient` fills and shape-level `Rounding` now survive a save
  into LibreOffice. libvisio's VSDX parser has no FillGradient token and
  does not read Rounding on a shape (only on a stylesheet), so Draw used to
  flatten those to solid colour and sharp corners. A save now writes the
  nearest classic FillPattern 25–40 and bakes filleted RelQuadBezTo rows;
  classic FillPattern 25–40 also paint here even when the model has no stop
  section yet.
- `CompoundType` 1–4 and unknown `LinePattern` ids now survive a save into
  LibreOffice. libvisio's VSDX token map has no CompoundType cell, and its
  `_lineProperties` switch treats custom / 0xFE dashes as solid, so Draw
  used to stroke a single full-width line. A 2-D save now emits parallel
  Geometry rails (and zeros CompoundType so Visio does not restroke the
  original path) and snaps custom dash arrays onto the built-in 2–23 table.
  A LineGradient without LineColor also writes the first stop colour so
  Draw has a stroke to paint.
- Rendering is now checked per shape, not just per page. A page-level mean
  error cannot see a single geometry, fill or master that silently
  disappears: the average barely moves. The corpus now maps every shape
  through `localToPageDeep` — honouring signed Width/Height, Angle and
  ancestor flips — and compares ink presence in that rectangle between
  our painter and LibreOffice. Across 60 files there is no shape
  LibreOffice paints and we do not. Dropping every filled leaf on
  `color-boxes.vsdx` fails with one line per vanished shape.
- Saving is now verified against the reference consumer instead of against
  ourselves. Every fixture is parsed, saved, and read back by libvisio —
  page count, page size, rendered letters, drawing features and painted
  object count all have to survive — and LibreOffice renders the original
  and the saved package so the pixels can be diffed. Across 152 documents a
  save changes nothing libvisio reads, and the worst rendered difference is
  a mean absolute error of 0.0200. Only one fixture used to check that a
  saved file still looks right in LibreOffice.
- Drawing features are now diffed against libvisio per document. Its whole
  painting surface is `drawPath`, `drawGraphicObject` and a text stack, so
  every other type a Visio file carries — gradient, hatch or bitmap fill,
  dashes, line-end markers, drop shadow, text decoration — rides on the
  graphic style it sets. A feature that stops rendering everywhere barely
  moves a page's mean pixel error, so the existing corpus could not see it;
  the new check compares feature presence directly across 152 documents.
- DiagramML (`.vdx` / `.vsx` / `.vtx`) now opens whatever namespace the file
  declares, matching libvisio's `isXmlVisioDocument`, which LibreOffice reaches
  through `VisioDocument::isSupported` and which only ever compares the root
  element name. Files exported by third-party tools with a foreign namespace,
  and files whose namespace declarations were stripped, opened in LibreOffice
  but were rejected here. Detection now also reads forward to the first real
  element instead of scanning the header, so a comment mentioning
  `<VisioDocument>` no longer counts as a signature.
- A bare `VisioDocument` record stream — an OLE2 export, or a legacy file that
  was never wrapped — now imports like the compound file it came from.
  libvisio falls back to the input itself when there is no such substream, and
  it validates the version byte before dispatching, so both parsers now accept
  exactly the same binaries.
- Every Visio extension the editor advertises (`.vsdx` `.vsdm` `.vstx` `.vstm`
  `.vssx` `.vssm` `.vsd` `.vss` `.vst` `.vdx` `.vsx` `.vtx`) is now covered
  end to end — detect, parse, render, save, reopen — with the saved package
  handed to LibreOffice for confirmation. Only the three most common
  extensions had that coverage before.
- Embedded Excel chart and sheet OLE previews now detect their Workbook/Book
  streams and composite the transparent WMF/EMF presentation on LibreOffice's
  classic Blue 2 surface (`#729FCF`). Variable-length OLE presentation headers
  are scanned for validated WMF payloads, and the Apache POI
  `visio_with_embeded.vsd` fixture now has a 144-DPI pixel regression.
- EMF text replay now retains `EMR_SETTEXTJUSTIFICATION` through DC state and
  distributes the authored extra break width consistently in Canvas and
  SVG/PDF, while preserving the original media on `.vsdx` save/reopen.
- EMF region replay now renders `EMR_FRAMERGN` brush borders and
  `EMR_INVERTRGN` difference fills in Canvas and SVG/PDF, including compound
  rectangle unions and byte-identical `.vsdx` save/reopen.
- EMF bitmap replay now retains `EMR_SETSTRETCHBLTMODE` through DC state:
  BLACKONWHITE/WHITEONBLACK/COLORONCOLOR use nearest sampling, while HALFTONE
  stays filtered consistently in Canvas and SVG/PDF with byte-identical media.
- EMF geometric pens now retain `PS_ENDCAP_ROUND`, `PS_ENDCAP_SQUARE`, and
  `PS_ENDCAP_FLAT`, so open paths use matching Canvas and SVG/PDF end caps and
  keep the original media byte-identical across `.vsdx` save/reopen.
- EMF geometric pens now retain `PS_JOIN_ROUND`, `PS_JOIN_BEVEL`,
  `PS_JOIN_MITER`, and `EMR_SETMITERLIMIT` through DC state and render the
  same joins in Canvas and SVG/PDF while preserving byte-identical round-trip.
- EMF bitmap-pattern and hatch brushes now retain `EMR_SETBRUSHORGEX` phase
  through SaveDC/RestoreDC, keeping Canvas and SVG/PDF tile alignment stable
  while preserving the original media bytes across `.vsdx` save/reopen.
- EMF/OLE previews now retain compound `EMR_SELECTCLIPPATH` and
  `EMR_EXTSELECTCLIPRGN` intersection/difference clips in Canvas and SVG/PDF.
  Complex path and rectangle-union clips follow SaveDC/RestoreDC state, while
  malformed region payloads remain isolated across `.vsdx` round-trips.
- EMF/OLE previews now reconstruct and tile `EMR_CREATEMONOBRUSH` and
  `EMR_CREATEDIBPATTERNBRUSHPT` DIB brushes in Canvas and SVG/PDF output.
  Malformed bitmap offsets remain isolated, and the original media bytes stay
  unchanged across `.vsdx` save/reopen.
- EMF vector replay now preserves `EMR_SETROP2` state per path, matching
  LibreOffice's invert, xor, and no-op modes in Canvas and SVG output.
- EMF/OLE previews now replay `EMR_FILLRGN` and `EMR_PAINTRGN` rectangle
  regions with the referenced or current GDI brush (including stock and hatch
  brushes). Region unions reach both Canvas and SVG/PDF, malformed `RGNDATA`
  is isolated without dropping later records, and the original media remains
  byte-identical across `.vsdx` save/reopen.
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
