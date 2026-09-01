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
- draw.io Electrical Capacitor 2 leftover keeps the curved plate stroke
  for LibreOffice. Official mxStencil `capacitors.xml` paints four
  `MoveTo` rails plus an `<arc>` (`<stroke/>`). leftover concatenated
  those pen-ups into one polyline, so a fake hairpin miter exceeded
  Draw's ODF default 4 and `bakeStrokeRibbonForLibvisio` filled one
  blob (`tokens.txt` LineColor → `svg:stroke`). Each subpath is now
  tested on its own; a second save keeps `RelCubBezTo` and LinePattern.
- draw.io Bootstrap Range input leftover keeps a trailing Character space
  for LibreOffice. Official Sidebar `mxCell('Example range ')` (and Tabs
  `Home `) ends with U+0020. leftover `readShapeText` /
  `trimXmlWhitespace` drops that so `collectText` (`tokens.txt`
  Character) lost the glyph. Capture now leftover-bakes U+00A0 like
  Chevron list / Use Case. A second save keeps the shift.
- draw.io Android Progress Scrubber leftover strokes the track with fill
  for LibreOffice. Official `mxShapeAndroidProgressScrubberPressed`
  does `setStrokeColor(STYLE_FILLCOLOR)` then strokes `0..dx`. Capture
  collapsed that hex to inherit `fill` so decoder `LineColor` copied
  inherit `FillForegnd` and `applyStencilStyle` washed the track the
  palette; leftover then dropped `LinePattern` on the mixed fill+stroke
  parent (`tokens.txt` LineColor → `svg:stroke`). Capture now
  leftover-bakes the fill hex. A second save keeps the cyan track over
  the gray rail.
- draw.io SysML Use Case leftover keeps a leading Character newline for
  LibreOffice. Official Sidebar `mxCell('\nextension points\np1, p2')`
  with `html=1` and `mxText.replaceLinefeeds` paints a leading `<br/>`
  under `UseCaseName`. leftover `readShapeText` / `trimXmlWhitespace`
  drops U+000A so `collectText` (`tokens.txt` Character) lost the blank
  first line. Capture now leftover-bakes U+00A0 like Chevron list. A
  second save keeps the shift.
- draw.io BPMN Service leftover fills gears with white for LibreOffice.
  Official `mxShapeBpmn2Task` case `service` does
  `setFillColor(STYLE_FILLCOLOR)` before `mxgraph.bpmn.service_task`.
  `Graph.replaceDefaultColor` maps defaultVertex `fillColor=default` to
  white before paint. Capture collapsed that to inherit `fill` after the
  inset `fill none` stroke so decoder inherit `FillForegnd`
  (`tokens.txt` → `svg:fill`) painted both cogs the palette. Capture now
  leftover-bakes `#ffffff` after fill none. A second save keeps the
  white gears.
- draw.io BPMN Send leftover strokes the envelope with white for
  LibreOffice. Official `mxShapeBpmn2Task` case `send` does
  `setStrokeColor(STYLE_FILLCOLOR)` then `setFillColor(STYLE_STROKECOLOR)`
  before `mxShapeBpmn2SendMarker`. `Graph.replaceDefaultColor` maps
  defaultVertex `fillColor=default` to white before paint. Capture left
  the keyword so decoder inherit `LineColor` (`tokens.txt` → `svg:stroke`)
  painted the outline the palette. Capture now leftover-bakes `#ffffff`.
  A second save keeps the white envelope and V-fold.
- draw.io Infographic Circular Callout leftover fills inner disks with
  white for LibreOffice. Official
  `mxShapeInfographicCircularCallout2.paintVertexShape` fills the body
  with `STYLE_STROKECOLOR` then `setFillColor(STYLE_FILLCOLOR)` for the
  evenodd holes. `Graph.replaceDefaultColor` maps defaultVertex
  `fillColor=default` to white before paint. Capture left the keyword
  so decoder inherit `FillForegnd` (`tokens.txt` → `svg:fill`) painted
  the inner disks the palette. Capture now leftover-bakes `#ffffff`
  after a hex sibling. A second save keeps the white holes.
- draw.io mxSwimlane startSize=0 leftover has no origin Line cap for
  LibreOffice. Official `paintSwimlane` still strokes the header as
  `move(0,start)/line(0,0)/line(w,0)/line(w,start)` when sidebar
  Container uses `startSize=0`. SVG butt cap hides those zero
  segments; leftover `Line` is a `tokens.txt` cap Draw paints as
  `svg:stroke`. Capture now skips coincident `lineTo` and drops
  degenerate subpaths (`mxShapeAws3dLambda` origin rings after
  `close()`). A second save keeps the top edge and body U without the
  cap.
- draw.io SysML Activity Final leftover fills the inner disk with stroke
  for LibreOffice. Official `mxShapeSysMLActivityFinal.paintVertexShape`
  does `setFillColor(STYLE_STROKECOLOR)` after the outer
  `fillAndStroke`. `Graph.replaceDefaultColor` maps defaultVertex
  `strokeColor=default` to `shapeForegroundColor` before paint. Capture
  left the keyword so decoder inherit `FillForegnd` (`tokens.txt` →
  `svg:fill`) painted the inner disk the outer palette. Capture now
  leftover-bakes the resolved stroke hex. A second save keeps the
  bullseye.
- draw.io AWS 3D Elastic MapReduce leftover has no origin Line cap for
  LibreOffice. Official `mxAws3dElasticMapReduce.foreground` leaves
  `moveTo(0,0)/lineTo(0,0)/arcTo(0,0)` after fill(); mxSvgCanvas2D
  `begin()` discards that unpainted path. Capture closed it so decoder
  concatenation (Crossbar) glued a `tokens.txt` Line onto the ridge
  stroke Draw paints as `svg:stroke`. Capture now drops degenerate
  open paths. A second save keeps the isometric ridges without the cap.
- draw.io SysML Sequence Diagram leftover has no trailing Character
  newline for LibreOffice. Official sidebar is html=1
  `<p><b>sd</b> Interaction1</p>`; parseHtmlLabel fused `</p>`'s `\n`
  onto the roman run (`tokens.txt` Character is collectText). Our SVG
  painted a second paragraph while mxText foreignObject has none after
  the last block. Capture now strips trailing `\n` from the last run.
  A second save keeps `sd` bold and one line.
- draw.io SysML Required Interface leftover keeps floating stems for
  LibreOffice. Official `insertEdge` pins the card as source with
  `exitX=0` and template-local `targetPoint (0,0)/(0,60)`. Capture
  extra-walked the unparented edge from the card so those points sat
  on the card origin, collapsing `sysMLReqInt` / `sysMLProvInt` into a
  degenerate `Line` Draw paints as `svg:stroke`. Capture now leftover-
  bakes Graph.view parent coordinates. A second save keeps both stems.
- draw.io UML Lollipop leftover keeps the oval at the junction for
  LibreOffice. Official `createVertexTemplateFromData` edges use
  `target="id"` plus `perimeter=centerPerimeter`; capture used the
  relative Geometry box so `endArrow=oval` sat on the right edge and a
  slash `Line` `(40,5)→(0,0)` reached Draw (`tokens.txt` Line is
  `svg:stroke`). Capture now leftover-bakes Graph.view terminals. A
  second save keeps the circle and both stems.
- draw.io Crossbar leftover keeps both dimension ticks for LibreOffice.
  Official `CrossbarShape.redrawPath` strokes the left tick, right tick
  and midline, then `mxActor.fillAndStroke`. Capture emits a `<path>`
  per `end()`; decode used to keep only the last Line (`tokens.txt`
  Line is `svg:stroke`). Adjacent `<path>` subpaths now concatenate
  before fill/stroke. A second save keeps the I-beam.
- Atlassian Comment leftover keeps the unhighlighted mention sentence
  for LibreOffice. Mixed Character Highlight leftover-bakes FillForegnd
  plates because `readCharIX` skips Highlight, then used `HideText` on
  the whole source (`tokens.txt` HideText). Official html=1 is
  `You've mentioned… @Jesse Byler …Confluence`; fodg kept only the chip
  plates. Unhighlighted remainder now stays on the source; plates are
  fill-only. All-highlighted mixed markers still hide the source.
- draw.io SysML Abstract Definition leftover no longer keeps a trailing
  Character newline for LibreOffice. Official sidebar is html=1
  `<p>…Name…</p>`; `parseHtmlLabel` treated `</p>` as a leftover `\n`
  run (`tokens.txt` Character is collectText). Our SVG painted a second
  paragraph while mxText foreignObject has none after the last block.
  Capture now drops a standalone trailing `\n`. A second save keeps a
  single Name paragraph.
- VSDX parse now keeps a leading Character U+00A0 for LibreOffice.
  Dart `String.trim` treats NBSP as whitespace, so Infographic Chevron
  list leftover `shape.text` dropped the sidebar `&nbsp;- Lorem` indent
  while later lines after `\n` survived (`tokens.txt` Character is
  collectText; libvisio does not strip U+00A0). `readShapeText` now
  trims XML 1.0 whitespace only. A second save keeps the indent.
- draw.io Mockup Alphanumeric leftover no longer keeps a zero-length
  Line for LibreOffice. Official sidebar sets `linkText=` empty;
  `mxShapeMockupAlphanumeric` then `getSizeForString('')` is width 0
  so move/line land on one point. Draw paints that `tokens.txt` Line
  as an `svg:stroke` cap on TxtPin. The visible underline is cell
  `fontStyle=4` / Char Style 0x4. Capture now drops the degenerate
  stroke. A second save keeps the alphabet and Char underline.
- draw.io Floorplan kitchen chairs now follow `direction` in LibreOffice.
  Official `mxShape.paint` calls `updateTransform` (`getShapeRotation`
  plus north/west/south) before `stencil.drawShape`. NestedStencil
  skipped that rotate, so Kitchen table `direction=north/west/south`
  chairs stayed the default 40×52 silhouette (`tokens.txt` has no
  direction; leftover is collectGeometry). Capture now leftover-bakes
  the rotated paths. A second save keeps them.
- draw.io Mockup Color Picker now keeps `indicatorColor` white in
  LibreOffice. Official `mxMockupForms.js` fills `chosenColor` then
  `indicatorColor=#ffffff`. Catalog capture collapsed that white to
  inherit `fill` after the hex sibling, so leftover extra-inherit fill
  washed to palette `#DAE8FC` (`tokens.txt` FillForegnd is `svg:fill`;
  `applyStencilStyle` isRoot:false keeps child white). Capture now
  leftover-bakes the explicit style white. A second save keeps it.
- draw.io STYLE_ROTATION now leftover-bakes Visio Angle for LibreOffice.
  Official sidebar Vertical Ruler and SysML Activity Partition set
  `rotation=-90`. NestedStencil never called `updateTransform`, so
  leftover geometry stayed unrotated, while JS painters canvas-rotated
  a 350×30 path past the XForm (`tokens.txt` Angle is `draw:rotate`).
  Capture now paints local geometry and leftover-bakes `Angle`. A
  second save keeps it.
- draw.io UML 2.5 Constraint now keeps `<<keyword>>` in LibreOffice.
  Official sidebar authors the stereotype as html=0 raw `<<keyword>>`.
  Catalog `cellLabel` stripped `<[^>]+>` so leftover Character was `>`
  (`tokens.txt` Character is collectText). Capture now leftover-bakes
  the chevrons instead of treating `<keyword>` as HTML. A second save
  keeps them.
- draw.io Mockup Pagination now keeps `<< Prev` chevrons in LibreOffice.
  Official sidebar text is `html=1` `<< Prev 1 2 3 4 5 6 7 8 9 10 Next >>`.
  Catalog HTML capture skipped stray `<` that are not tags, so leftover
  Character lost the chevrons (`tokens.txt` Character is collectText).
  Capture now leftover-bakes them with `fontStyle=4` underline. A second
  save keeps them.
- draw.io Mockup Horizontal Ruler now keeps unit ticks in LibreOffice.
  Official `mxMockupMisc.js` `ruler2` reads `graph.getLabel(cell)` for
  the scale (`dx=100` → `"2"` / `"3"` at 350px). Catalog capture stubbed
  `getLabel` as empty and omitted the template cell, so leftover
  Character had only the `"1"` label (`tokens.txt` Character is
  collectText). Capture now leftover-bakes the ticks at `fontColor`
  `#999999`. A second save keeps them.
- draw.io AWS4b `productIcon` now keeps the brand square in LibreOffice.
  Official `mxAWS4.js` fills `strokeColor` white then inherit
  `fillColor` for the top square. Catalog decode attached that square
  to the parent, so the white hex child painted over it (`tokens.txt`
  FillForegnd is `svg:fill`; group children paint after the parent).
  Decode now leftover-bakes a later inherit fill as a sibling after a
  hex fill. A no-fill group still runs `applyStencilStyle` on children
  so AWS Cloud inherit puffs keep palette FillForegnd. A second save
  keeps the `#232F3E` square above white.
- draw.io Cisco Safe `compositeIcon` now stays opaque in LibreOffice.
  Official `mxCiscoSafe.js` paints 50% `bgDotColor` dots then
  `setAlpha(parseFloat(omitted opacity))` (`NaN`). Catalog capture
  skipped NaN, so leftover FillForegndTrans stayed 50% on the
  `resIcon` (`tokens.txt` FillForegndTrans is `draw:opacity`). Capture
  now treats non-finite alpha as createState 1. A second save keeps
  the opaque glyph.
- draw.io mxText html `&nbsp;` now stays native in LibreOffice. Official
  C4 Data Container (and Microservice / Message Bus siblings) use
  `[%c4Type%:&nbsp;%c4Technology%]`. Catalog capture collapsed NBSP
  with JS `\s` into U+0020, so leftover Character wrapped after the
  colon (`tokens.txt` has no keep-together; U+00A0 is the native glue).
  Capture now leftover-bakes U+00A0. A second save keeps it.
- draw.io mxText html CSS `background-color` now stays native in
  LibreOffice. Official Atlassian Nested discussion chips (`AUTHOR`,
  `@Matthew Wu`) use `background-color: rgb(244, 245, 247)`. Catalog
  capture dropped that, so leftover Char.Highlight stayed empty
  (`readCharIX` skips Highlight; mixed leftover bakes FillForegnd
  plates Draw paints). Capture now leftover-bakes the chip hex. A
  second save keeps the plates.
- draw.io mxText html CSS `font-size` keywords now stay native in
  LibreOffice. Official SAP Text Elements use
  `font-size: x-small` (Chromium 10px at medium 16px). Catalog capture
  dropped the keyword, so leftover Char.Size stayed defaultVertex 12
  (`tokens.txt` Size is `fo:font-size`). Capture now leftover-bakes
  the keyword table. A second save keeps it.
- draw.io mxText html CSS `line-height` now stays native in
  LibreOffice. Official SAP Authenticate (and Authorize / Protocol
  siblings) use `<p style="line-height: 114%">`. Catalog capture
  dropped that, so leftover Paragraph `SpLine` stayed the default
  single (`tokens.txt` SpLine is `fo:line-height`). Capture now
  leftover-bakes the 1.14× multiplier (`SpLine` −1.14). A second
  save keeps it.
- draw.io mxText html `fontColor=default` now stays black in
  LibreOffice after a colored `<font>`. Official `default.xml`
  `defaultVertex` uses the keyword `default` (`mxConstants.DEFAULT_FONTCOLOR`
  `#000000`). Catalog capture leftover-baked `fontcolor="default"` on the
  next html run, so Infographic Roadmap body Char.Color rode Label's
  `#10739E` (`tokens.txt` Color is `fo:color`). Capture now resolves
  `default` to hex and leftover-bakes `#000000`. A second save keeps
  both colours.
- draw.io `mxDoubleEllipse.getLabelBounds` now stays native in
  LibreOffice. Official `mxDoubleEllipse.js` insets the label by
  `STYLE_MARGIN` (ER Multivalue Attribute `margin=3` on a 100×40 cell).
  Catalog capture only painted the inner ellipse, so leftover TxtWidth
  stayed the outer box and Draw's `collectTextBlock` overlapped the
  ring (`tokens.txt` TxtWidth is `svg:width`). Capture now leftover-bakes
  the 94×34 inset. A second save keeps TxtHeight.
- draw.io mxText html table cell `vertical-align` now stays native in
  LibreOffice. Official `mxText` html=1 paints General HTML Table 4 as
  a foreignObject whose `<th>`/`<td>` use the html.spec UA
  `vertical-align: middle`; named style `text` only sets the outer box
  to top. Catalog capture copied that outer top onto every leftover
  cell, so Title sat at VerticalAlign 0 (`tokens.txt` VerticalAlign is
  `draw:textarea-vertical-align`). Capture now leftover-bakes middle
  on table cells and keeps caption `<div>` rows on the mxText valign.
  A second save keeps both.
- draw.io mxStencil `labelBounds` now stays native in LibreOffice for
  JavaScript-captured flowchart stencils. Official `Shapes.js` reads
  `<labelBounds if="boundedLbl">` from `mxStencil` (flowchart.xml
  Multi-Document) via `getLabelMargins` / `getDirectedBounds`. Catalog
  capture returned a style ghost without that hook, so JS Multi-Document
  had no TxtWidth (`tokens.txt` has no labelBounds; `collectTextBlock`
  is `svg:width` / `fo:min-height`). Capture now leftover-bakes the
  inset. A second save keeps TxtHeight.
- draw.io mxText html table caption padding now stays native in
  LibreOffice. Official `mxText` html=1 paints UML Entity's leading
  `<div style="padding:2px">Tablename</div>` with CSS padding only;
  `cellpadding="2"` applies to `<td>`/`<th>`. Catalog capture stacked
  both onto the caption, so leftover LeftMargin was 4px (`tokens.txt`
  has no HTML-padding token; `collectTextBlock` is `fo:padding-left`).
  Capture now leftover-bakes the caption's 2px. A second save keeps
  TextBlock margins.
- draw.io `childLayout=stackLayout` fill now stays native in LibreOffice.
  Official `Graph.getLayout` sets `mxStackLayout.fill` so a vertical
  stack (General List `horizontalStack=0`) stretches each item to the
  swimlane width. Catalog capture only stacked x/y, so Item 1–3
  leftover-baked the Sidebar field's 80px in a 140px List
  (`tokens.txt` has no stackLayout; `collectXFormData` is `svg:width`).
  Capture now leftover-bakes the filled XForm. A second save keeps the
  full-width items.
- draw.io vertex-cells sibling `fillColor` now stays native in
  LibreOffice. Official Infographic Angled Entry paints two
  `mxgraph.infographic.parallelogram` cells (`#10739E` then `#B1DDF0`).
  Catalog capture overwrote the `<shape>` inherit fill on every
  `bindStyle`, so `fillPaintToken` always emitted `fill` and Draw
  painted both parallelograms the first cell's colour (`tokens.txt`
  FillForegnd is `svg:fill`). Capture now leftover-bakes the distinct
  hex FillForegnd. A second save keeps both siblings.
- draw.io `fillOpacity` inherit fills now stay native in LibreOffice.
  Official `mxShape.configureCanvas` sets fillAlpha from the 0–100
  style (Infographic Circular Dial (2) donut `fillOpacity=20`) before
  the opaque `partConcEllipse` value. Catalog capture forceHexed that
  alpha into a sibling, so the 65% arc occupied the parent and Draw
  painted the track on top (`tokens.txt` FillForegndTrans is
  `draw:opacity`). Capture now leftover-bakes FillForegndTrans on the
  inherit donut under the value. A second save keeps the order.
- draw.io `shape=table` grids now stay native in LibreOffice. Official
  `TableShape.paintForeground` strokes `Graph.getTableLines` (from
  `visitTableCells`) as the interior row/column rules. Catalog capture
  stubbed `getTableLines` to `[]` and never passed the cell tree, so
  General Table 1 leftover-baked only the outer PartialRectangle
  (`tokens.txt` has no table-grid token; `collectLine` is `svg:stroke`).
  Capture now leftover-bakes those polylines. A second save keeps the
  3×3 collectLine siblings.
- draw.io mxSwimlane `horizontal=0` titles now stay native in
  LibreOffice. Official `mxText.isPaintBoundsInverted` plus
  `mxCellRenderer.rotateLabelBounds` (-90°) maps
  `mxSwimlane.getLabelBounds`' startSize-tall strip onto the left
  title bar `paintVertexShape` fills. Catalog capture skipped that
  invert, so General Horizontal Container and BPMN Horizontal Swimlane
  leftover-baked the caption across the top (`tokens.txt` has no
  horizontal token; `collectXFormData` is `svg:x` / `svg:width`).
  Capture now leftover-bakes the left startSize Text child.
  A second save keeps TextDirection=1.
- draw.io mxText html `<hr>` empty compartments now stay native in
  LibreOffice. Official `mxText` overflow=fill html=1 is a foreignObject
  with CSS block flow, so UML Class 3/4's title `<p>` is content-sized,
  then `<hr>`, then an empty `height:2px` spacer. Catalog capture
  weighted only visible text, stretched the title, and leftover-baked
  the rule onto the cell bottom (`tokens.txt` has no hr token;
  `collectLine` is `svg:stroke`). Capture now sizes bands like HTML
  flow and gives leftover height to empty compartments. A second save
  keeps the rule under the title.
- draw.io Graph autosizeText now stays native in LibreOffice. Official
  `Graph.computeAutosizeTextFontSize` binary-searches 6–84px so General
  Autosize Title (`fontSize=25` in a 160×40 cell) and the wrapped Note
  paragraph fit the box. Catalog capture used the style token, so Draw
  overflowed (`tokens.txt` has no autosizeText; `collectCharIX` Size is
  `fo:font-size`). Capture now leftover-bakes the fitted size. A second
  save keeps Char.Size.
- draw.io mxText html entity stereotypes now stay native in LibreOffice.
  Official `mxText` html=1 paints SysML Package Diagram's
  `&lt;&lt;import&gt;&gt;` through the foreignObject UA as `<<import>>`.
  Catalog `cellLabel` decoded those entities before `parseHtmlLabel`, so
  the leftover Character was a lone `>` (`<import>` eaten as a tag), and
  walking `insertEdge` plus `insert()` painted the same connector three
  times (`tokens.txt` has no entity token; `collectText` only sees Char
  runs). Capture now keeps html=1 source for the HTML parser and parents
  each edge once. A second save keeps a single `<<import>>`.
- draw.io mxText html named entities now stay native in LibreOffice.
  Official `mxText` html=1 paints `&laquo;interface&raquo;` through the
  foreignObject UA as U+00AB / U+00BB. Catalog capture only decoded
  `nbsp` / numeric / `amp`/`lt`/`gt`/`quot`, so UML Interface and
  Component leftover Character still had the raw tokens (`tokens.txt`
  has no entity token; `collectText` shows them literally). Capture now
  freezes HTML Latin-1 named references (and `ndash` / `mdash` /
  `hellip` / `bull`) into Char runs. A second save keeps the
  guillemets.
- draw.io Curved Text now stays native in LibreOffice. Official
  `CurvedTextShape.paintForeground` paints an SVG `textPath` along
  `arcStartY` / `arcMidY` / `arcEndY` (`curveType=round`,
  `textLength=pathLen`). RecordingCanvas has no `root` / `getBaseUrl`,
  so capture fell back to one centred Character blob and ignored
  `noLabel=1`. `tokens.txt` has no text-on-path; capture now leftover-
  bakes each glyph as a `TxtAngle` Char sibling (`collectTextBlock`
  `librevenge:rotate`), matching SVG `<textPath>`. A second save keeps
  the arc.
- draw.io Graph placeholders now stay native in LibreOffice. Official
  `Graph.setAttributeForCell` wraps Sidebar Variable / Timestamp labels
  in a `UserObject` (`placeholders=1`, `name=Variable`) and
  `Graph.replacePlaceholders` / `getGlobalVariable` freeze `%name%` and
  `%date{ddd mmm dd yyyy HH:MM:ss}%` into Character text (`tokens.txt`
  has no placeholder token; `collectText` only sees Char runs). Catalog
  capture stubbed those Graph methods, so Draw showed the raw tokens.
  Capture now matches Graph.js and leftover keeps `Variable Text` plus
  the formatted timestamp. A second save keeps the frozen runs.
- draw.io mxText html table captions and `border="1"` now stay native in
  LibreOffice. Official `mxText` html=1 paints a leading `<div>` plus
  `<table>` (UML Entity `Tablename` / PK columns) and the HTML
  presentational `border` grid (General HTML Table 4) through the
  foreignObject UA. Catalog capture aborted table layout when any text
  sat outside `<table>`, mashed `PKuniqueId` into one Character blob,
  skipped `<th>`, and dropped the grid. Capture now pins the caption as
  a header row whose CSS `background` is `TextBkgnd` (`collectTextBlock`
  `fo:background-color`), parses `th` like `td`, and leftover-bakes the
  1px grid as `collectLine` siblings (`tokens.txt` has no table token).
  A second save keeps the bands and rules.
- draw.io mxText html `<ul>` / `<ol>` now stay native in LibreOffice.
  Official `mxText` html=1 paints list markers through the foreignObject
  UA stylesheet (`ul` disc, `ol` decimal, `padding-inline-start: 40px`).
  Catalog capture flattened General Unordered/Ordered List to three
  unmarked lines. Capture now records `Bullet` 1 / `TextPosAfterBullet`
  for discs that leftover bakes as U+2022 (`Draw` never paints
  `text:bullet-char`) and prefixes `"1. "` for decimals (`tokens.txt`
  has no numbered list). A second save keeps the markers.
- draw.io mxStencil omitted `<fontfamily>` / `<fontcolor>` now stay
  Arial / `#000000` in LibreOffice, matching `createState`
  `DEFAULT_FONTFAMILY` and `fontColor`. Catalog decode left Char.Font /
  Color null (platform face / theme). Electrical Flip-Flop D/Q glyphs
  omit those tags; leftover writes the cells `collectCharIX` maps to
  `style:font-name` / `fo:color`. Cell values still use defaultVertex
  Helvetica via `applyTextStyle`. A second save keeps Arial black.
- draw.io JS vertex-cells capture now emits `createState` between
  cells. One recording canvas used to leak the previous cell's
  `applyTextStyle` Helvetica/12, `dashed=1`, FillForegnd hex, and round
  cap onto the next NestedStencil (`bindStyle` zeroed tokens so the
  real setters became no-ops). Official `configureCanvas` always
  `setFillColor` / `setDashed`; NestedStencil and `bindStyle` now emit
  Arial / `#000000` / solid 1px so leftover collectCharIX / collectLine
  stay on this stencil. Cell values still use defaultVertex Helvetica
  via `applyTextStyle`. A second save keeps the reset.
- draw.io mxStencil omitted `<fontsize>` now stays 11px in LibreOffice,
  matching `mxAbstractCanvas2D.createState` /
  `mxConstants.DEFAULT_FONTSIZE`. Catalog decode and JS capture used 12
  (defaultVertex cell labels). Electrical Flip-Flop D/Q glyphs have no
  size tag; `configureCanvas` does not copy vertex `fontSize` onto the
  stencil canvas. leftover keeps Char.Size that `collectCharIX` maps to
  `fo:font-size`. Cell values still use defaultVertex 12 via
  `applyTextStyle`. A second save keeps 11.
- draw.io mxStencil `roundrect` `arcsize="0"` now stays 15% rounded in
  LibreOffice, matching official `drawNode`
  (`RECTANGLE_ROUNDING_FACTOR * 100`). Canvas `roundrect(r=0)` (Android
  `rrect;rSize=0`) is captured as `<rect>` so that chrome stays sharp.
  Nested XML stencils use 15 rather than 10. A second save keeps the cubics
  (`RelCubBezTo`; `tokens.txt` has no CubBezTo).
- draw.io JS Canvas `createState` `miterLimit` 10 now stays native in
  LibreOffice. Capture used CSS / ODF default 4, so `restore()` leaked
  `<miterlimit limit="4"/>` onto later fills (Atlassian Button checkmarks).
  SVG still applies CSS initial 4 when `stroke-miterlimit` is omitted.
  leftover would skip the spike at 4 because ODF default miterlimit is
  already 4; `_lineProperties` never emits `svg:stroke-miterlimit`, so
  miter 10 leftover-bakes the spike. A second save keeps 10.
- draw.io SVG multi-stop radial tessellation now keeps CSS named stop
  colours as sibling FillForegnd. i/8 interpolation skipped Azure
  Application Gateway Containers `silver` (`#C0C0C0`); discs at each
  stop offset keep `collectFillAndShadow` `draw:fill-color`.
- draw.io mxStencil `linejoin` `flat` / `square` now stay miter in
  LibreOffice. Official `drawNode` still `setLineJoin` those linecap
  tokens; `mxSvgCanvas2D` writes `stroke-linejoin="flat"` which SVG
  drops for the CSS initial `miter`. Catalog decode used
  `VsdxLineJoin.parse` null and wiped createState miter (AWS 3D
  Decider after `join="square"`). leftover `_lineProperties` maps
  join from LineCap, so a null join on a round cap would round the
  elbow. XSD miter / round / bevel are unchanged. A second save
  keeps veLineJoin miter.
- draw.io mxStencil `dashpattern dash=` now stays native in LibreOffice.
  Cisco Guard / ISDN Switch write `dash="8 8"` / `dash="12 4"` instead of
  the XSD `pattern` attribute official `drawNode` reads, so catalog decode
  used createState `3 3`. The decoder now takes `dash` as that alias.
  leftover still bakes custom `0xfe` into MoveTo gaps `_lineProperties`
  can stroke. A second save keeps the gaps.
- draw.io mxStencil `dashpattern="none"` now stays solid in LibreOffice.
  Official `drawNode` still `setDashPattern(Number("none")*minScale)` so
  the array is NaN; `createDashPattern` writes `stroke-dasharray="NaN"`
  and SVG paints a solid. Catalog decode treated `none` like a missing
  tag and used createState `3 3` (AWS 4 work package outline). A second
  save keeps the solid LinePattern; leftover no longer bakes MoveTo gaps.
- draw.io mxStencil `<image>` x/y/w/h now stays native in LibreOffice.
  IBM Floating IP is a mid-band PNG (`x≈0.61 y≈20.18 w≈58.78 h≈19.65`
  on a 60×60 cell). Catalog decode used to stretch that bitmap over the
  XForm. `collectForeignDataType` maps ImgOffset / ImgWidth / ImgHeight
  to `svg:x` / `svg:width` / `svg:height`. Inset is not crop overflow, so
  leftover keeps those cells instead of compositing a frame-sized PNG.
  A second save keeps the inset.
- draw.io mxStencil `<labelBounds>` now stays native in LibreOffice.
  Flowchart Multi-Document (`boundedLbl=1`) insets the cell with
  `x=0 y=10 w=78 h=47` on an 88×60.28 stencil. Catalog decode dropped
  that tag, so `collectTextBlock` used full Height and painted over the
  stacked top sheet. The decoder maps it to TxtPin / TxtWidth /
  TxtHeight. A second save keeps the inset.
- draw.io mxShape `dashed=1` without `dashpattern` leftover now stays
  native in LibreOffice. Official `mxAbstractCanvas2D.createState` uses
  `dashPattern: '3 3'`. Catalog decode already writes that as
  `veDashPattern`; `_lineProperties` treats custom `0xfe` as solid, so
  leftover bakes MoveTo gaps (IBM Dashed Connector, Availability Zone,
  UML Template signature). Tests that still expected tokens.txt
  LinePattern 2 now walk those gaps. A second save keeps the dashes.
- draw.io SVG `url(#gradient)` leftover now matches what libvisio can
  paint. SAP Logo tessellates navy→cyan FillForegnd slabs (no
  FillGradient token). Tunnel capture is FillPattern 30 north; Arc Data
  Services `axial-east` stays FillPattern 26 leftover. Azure Search lens
  is a white `EllipseCmd`, not FillPattern 40. Catalog tests follow that
  tessellation. A second save keeps the slabs and axial.
- draw.io Chen Weak Entity / Identifying Relationship extra inherit
  fills now stay native in LibreOffice. `collectGeometry` concatenates
  every NoFill=0 section into one evenodd path. A second concentric
  fillstroke on the parent would punch a hole; leftover already splits
  that inner contour to a sibling. Catalog tests now walk descendants.
  A second save keeps both contours. BPMN Choreography Task bands use
  the same sibling split. Crow's-foot leftover bakes a filled ribbon
  because default `miterLimit` 10 is not an ODF token.
- draw.io mockup Table cell rects now stay native in LibreOffice. JS
  capture emits those `rect()` corners as consecutive `<move>` without
  `<line>` (C4 Legend, ER Table 2). `collectGeometry` skips a
  MoveTo-only section, so Draw lost the grid. The decoder closes that
  polyline like a regular rect. Cell labels are unchanged. A second
  save keeps the LineTo rails.
- draw.io mxStencil omitted `strokewidth` now stays native in
  LibreOffice. Official `mxStencil.parseDescription` defaults a
  missing attribute to `"1"` and `drawShape` does `1 * minScale`
  (Cisco Keys, mockup Radio Button Off). Catalog decode treated omit like
  `inherit`, so Visio 0.01 in was pinned to the palette 0.012 that
  `collectLine` mapped to a hairline. Authored omit now freezes
  LineWeight. `inherit` still takes the palette. A second save keeps
  `1.5/12` in.
- draw.io mxStencil default `miterLimit: 10` now stays native in
  LibreOffice. Official `mxAbstractCanvas2D.createState` uses
  `miterLimit: 10`. Catalog decode left `_miterLimit` unset, so
  inherit / hex strokes without `<miterlimit>` (AWS 2 EMR) used Visio
  factory 4. `_lineProperties` never emits `svg:stroke-miterlimit`, so
  Draw bevelled ratio>4 elbows. The decoder now starts at 10; leftover
  bakes a filled stroke ribbon for those spikes. Explicit
  `<miterlimit>` is unchanged. A second save keeps the ribbon.
- draw.io mxStencil default `lineJoin: miter` now stays native in
  LibreOffice. Official `mxAbstractCanvas2D.createState` uses
  `lineJoin: 'miter'` independently of `lineCap`. Catalog decode left
  `_lineJoin` unset, so `linecap=round` without `<linejoin>` (GMDL mail
  flap) used Visio round join and `_lineProperties` case 0 painted
  `svg:stroke-linejoin=round`. The decoder now starts at miter; leftover
  flattens that round cap to LineCap 1 so Draw miters the elbow.
  Explicit `linejoin=round` is unchanged. A second save keeps the join.
- draw.io mxStencil default `dashPattern: 3 3` now stays native in
  LibreOffice. Official `mxAbstractCanvas2D.createState` uses `'3 3'`;
  `setDashed(true)` without `<dashpattern>` (AWS 3D Dashed Edge, Cisco
  Metro 1500) fell through to Visio `LinePattern` 2 (`6×`/`3×`
  LineWeight) that `_lineProperties` case 2 paints. Short rails looked
  solid. The decoder now freezes the 3 3 array as `veDashPattern`; leftover
  bakes MoveTo gaps because custom `0xfe` is solid in libvisio. Explicit
  `<dashpattern>` is unchanged. A second save keeps the gaps.
- draw.io mxStencil shape `strokewidth="2"` now stays native in LibreOffice.
  Official `mxStencil.drawShape` does `Number(strokewidth) * minScale`
  before `drawNode` (Networks Comm Link / Firewall). Catalog decode only
  read child `<strokewidth>` tags, so the numeric attribute stayed Visio
  0.01 in and `applyStencilStyle` pinned the palette 0.012 that
  `collectLine` mapped to a hairline `svg:stroke-width`. Authored
  widths freeze LineWeight. `inherit` / omitted still take the palette.
  A second save keeps 0.03 in.
- draw.io mxStencil default `<linecap>` now stays native in LibreOffice.
  Official `mxAbstractCanvas2D.createState` uses `lineCap: 'flat'` (SVG
  butt). Catalog decode left `_lineCap` unset, so inherit / hex strokes
  without a tag used Visio factory `LineCap` 0 and `_lineProperties`
  painted `svg:stroke-linecap=round` plus round joins (Android Progress
  Bar rails). The decoder now starts at `LineCap` 1 (`butt` / miter),
  captures cap / join / miter at the first inherit `_finish` so a later
  sibling `linecap` cannot leak onto `collectLine` (Cisco Detector), and
  splits a later inherit stroke whose cap differs (Electronic Info Flow
  `save` / round / `restore` / butt) into a sibling. A second save keeps
  LineCap 1.
- draw.io mxStencil inherit-stroke `<alpha>` now stays native in LibreOffice.
  Official `mxStencil.drawNode` `setAlpha` before inherit `fillstroke`
  (Cortana / vNIC `save` / `alpha="0.4"` / restore). Catalog decode
  captured FillForegndTrans on the parent but rebuilt Line after restore,
  so LineColorTrans stayed 0. `_lineProperties` reads `Colour.a` and
  `xmlStringToColour` zeros it, so leftover must bake a
  `FillForegndTrans` stroke ribbon. Capture Trans at `_finish` like
  LineWeight. A second save keeps the wash without a SoftEdges PNG.
- draw.io mxStencil inherit-fill `<alpha>` now stays native in LibreOffice.
  Official `mxStencil.drawNode` calls `canvas.setAlpha` before an inherit
  `fill` (Networks2 hub / antenna shadows `alpha="0.25"`). Catalog decode
  restored the paint stack before building the parent, so `FillForegndTrans`
  stayed 0 and `collectFillAndShadow` / `_fillAndShadowProperties`
  (`pattern==1`) painted an opaque palette silhouette instead of
  `draw:opacity` 25%. The inherit fill now captures Trans at `_finish`
  like LineWeight. A second save keeps it without a SoftEdges PNG.
- draw.io Networks2 XML `neutralFill` now stays native in LibreOffice.
  Official `mxStencil.getColorValue` reads the cell style then the node's
  `default`; Sidebar-Network2.js sets `neutralFill=#9DA6A8` and global
  server ships that `default`, but hub / server / mail server LEDs omit
  it. Catalog decode has no cell style, so the LED stayed inherit fill
  and `applyStencilStyle` washed it to the palette. Unique library
  defaults become sibling `FillForegnd`. A second save keeps the grey
  LED without a SoftEdges PNG.
- draw.io glued `fontColor=#4d4d4dlfontSize=13` now stays native in
  LibreOffice. GMDL stepper `addDataEntry` XML omits the `;` between
  `fontColor` and `fontSize`, so official `mxUtils.isValidColor` rejects
  the token and `collectCharIX` inherited black. The decoder keeps the
  `#RRGGBB` prefix as Char.Color (`fo:color`); capture `parseStyle`
  splits the glued `fontSize` for the next regen. A second save keeps
  “Ad unit details” / “Create an ad”.
- draw.io CSS named colours now stay native in LibreOffice. Official
  `mxUtils.isValidColor` / `color2hex` resolve canvas `fillStyle` names
  (`gray` `#808080`, `silver` `#C0C0C0`, `white`), but the decoder only
  parsed hex / `RGB()`. Azure Application Gateway Containers SVG
  `fill="gray"` / `silver` stayed inherit fill, and SAP Build Workzone
  `fillgradient color1=white` dropped the white stop. `collectFillAndShadow`
  then missed those `draw:fill-color` siblings. Named colours become
  sibling `FillForegnd` / `FillBkgnd`. A second save keeps them without
  a SoftEdges PNG.
- draw.io NestedStencil style-key `default` colours now stay native in
  LibreOffice. Sidebar Android Keyboard is `shape=mxgraph.android.keyboard`
  and capture inlines official `mxStencil.drawShape`, but
  `mxStencilColor` dropped the node's `default` so `fillColor2` stayed
  inherit fill. `applyStencilStyle` washed the keys `#DAE8FC` and
  `collectFillAndShadow` painted a palette-blue keyboard. Capture now
  follows `getColorValue` (and force-hex so `#fff` == cell fillColor
  does not collapse to the `fill` token). A second save keeps the
  chassis / keys / QWERTY.
- draw.io mxStencil style-key `default` colours now stay native in
  LibreOffice. Official `mxStencil.getColorValue` uses the node's
  `default` when the cell style has no `fillColor2` / `fillColor3`
  (Android Keyboard chassis `#000` / keys `#333` / `#999`, QWERTY
  `fontcolor` `#fff`; Contextual Action Bar 6×6 squares and speaker
  strokes `#fff`). The decoder treated those keys as inherit fill, so
  `applyStencilStyle` washed them `#DAE8FC` and `collectFillAndShadow`
  painted a palette-blue keyboard. Authored hex becomes sibling
  `FillForegnd` / `LineColor` / `Char.Color`; cell keys (`fillColor`)
  stay inherit. A second save keeps the colours without a SoftEdges PNG.
- draw.io mxStencil save/restore now keeps post-restore strokes solid in
  LibreOffice. Official `mxStencil.drawNode` calls `canvas.save` /
  `canvas.restore` (Android Contextual Action Bar dashes a check then
  restores before the speaker / hamburger; Keyboard isolates key fills
  before QWERTY `collectCharIX`). The decoder skipped those tags, so
  `dashpattern` leaked onto later `collectLine` siblings and leftover
  baked them as MoveTo gaps (`LinePattern` 0xfe is solid). Restore pops
  the paint stack like `mxAbstractCanvas2D`. A second save keeps the
  solid icons native.
- draw.io mxShape inherit-fill siblings now stay unions in LibreOffice.
  Official AWS Cloud, VPC NAT Gateway and Citrix server painters call
  `fill()` more than once with the cell fill colour, but the decoder
  stacked those contours as extra NoFill=0 Geometry. `collectGeometry`
  `_fillAndShadowProperties` `svg:fill-rule=evenodd` then punched
  overlaps as holes. Extra inherit fills become sibling shapes; a
  compound path with one fill (OpenAI swirl, Task Center donuts) stays
  one Geometry so evenodd still punches. A second save keeps the
  children.
- draw.io mxShape `setGradient` + fillAlpha now stays native in LibreOffice.
  Infographic Cylinder and iOS6 Alert Box / iPhone glass call official
  `mxAbstractCanvas2D.setGradient` then `setFillAlpha`, but capture emitted
  FillPattern 25–40 and `collectFillAndShadow` `_fillAndShadowProperties`
  always `remove(draw:opacity)`. A save would bake an opaque
  SoftEdges PNG over the body. Capture now tessellates those fills as
  `FillPattern` 1 + `FillForegndTrans` slabs. A second save keeps the wash.
- draw.io mxImageShape SVG far-field `stop-opacity` visors now stay native
  in LibreOffice. Azure Sphere's white highlight is `#fff`→`#fff` with
  `stop-opacity` 0.9→0.8 on a `userSpaceOnUse` vector at y≈-3114, so
  tessellation slabs miss the glyph and capture fell through to
  `FillGradient`. `collectFillAndShadow` FillPattern 25–40 drop
  `draw:opacity`, and a save would bake an opaque SoftEdges
  PNG over the cyan body. Capture now paints the contour once as
  `FillPattern` 1 + `FillForegndTrans` (and refuses FillGradient for
  alpha ramps). A second save keeps the visor.
- draw.io mxImageShape SVG `fill-rule="nonzero"` compound paths now stay
  native in LibreOffice. Official IBM VPC Bridge arrows, Cloud Services
  gears and VPN Policy document slots paint several filled subpaths
  under SVG's default nonzero rule (same-winding nested contours are a
  union), but capture emitted one Geometry so `collectGeometry`
  `_fillAndShadowProperties` `svg:fill-rule=evenodd` punched overlaps
  as holes. Capture now splits those subpaths into sibling fills;
  opposite-winding nested rings (Load Balancer Listener donut, OpenAI
  swirl, Task Center ticks) stay one Geometry so evenodd still punches.
  A second save keeps the children.
- draw.io mxText cell labels now keep Size / Color / TextBkgnd in LibreOffice.
  Official `mxText.configureCanvas` calls `setFontSize` / `setFontColor` /
  `setFontBackgroundColor` from the cell style, but capture painted
  template values with the canvas defaults, so an Electrical Ammeter
  (`fontSize=50`) and Bootstrap Alert (`fontColor=#004583`) used 12 pt
  black that `collectCharIX` still maps to `fo:font-size` / `fo:color`.
  Authored sizes and colours now freeze on the Text children; label
  plates become `TextBkgnd` that `collectTextBlock` maps to
  `fo:background-color`. A second save keeps the cells.
- draw.io mxText cell labels now keep the box and spacing in LibreOffice.
  Official `mxXmlCanvas2D.text` writes `w`/`h` and `mxText.apply` adds
  `spacing` to `spacingLeft`/`Right`/`Top`/`Bottom` (default 2, so
  Bootstrap Alert `spacingLeft=10` pads 12). Capture dropped the box,
  so Ammeter `A` pinned to the parent top-left in a tight glyph frame
  and `collectTextBlock` never saw `LeftMargin` → `fo:padding-*`. Cell
  values now fill the template; stencil glyphs that pass `w=h=0` stay
  tight. A second save keeps Pin / Width / LeftMargin.
- draw.io mxText wrap and vertical labels now stay native in LibreOffice.
  Official `mxXmlCanvas2D.text` writes `wrap` and `mxShape.getTextRotation`
  adds `verticalTextRotation` when `STYLE_HORIZONTAL != 1`, but capture
  dropped both, so a Cabinet panel (`horizontal=0`, value `25x40`) laid
  out horizontally and `whiteSpace=wrap` never reached `veWordWrap`.
  Cell boxes now set `TextDirection=1` (a save bakes `TxtAngle` because
  `_flushText` skips `style:writing-mode`) and `wrap` onto `veWordWrap`
  (`TxtWidth` bake when off). Stencil glyphs with `w=h=0` stay a tight
  `TxtAngle`. A second save keeps the baked rotation.
- draw.io `direction=north/south` now stays in the cell box for LibreOffice.
  Official `mxShape.paint` swaps width/height when `isPaintBoundsInverted`
  before `updateTransform` rotates, but capture rotated the original
  bounds, so a Cabinet 12.5×350 south rect became a 350-wide path that
  decoder `scaleX` exploded past the XForm `collectXFormData` maps to
  `svg:width`. Capture now inverts like `paint`; XML stencils still use
  `computeAspect`. A second save keeps the contour.
- draw.io mxGraph `labelPosition` / `verticalLabelPosition` now stay
  native in LibreOffice. Official `mxGraphView.updateVertexLabelOffset`
  shifts the mxText box by one cell (`left`/`right`/`top`/`bottom`),
  but capture always painted `canvas.text(x,y,w,h)` on the icon, so
  UML Port (`labelPosition=right`) and GCP Vertex AI
  (`verticalLabelPosition=bottom`) stacked the caption on the glyph
  that `collectXFormData` maps to `svg:x` / `svg:y`. Capture now
  offsets like the view; `align` / `verticalAlign` stay in-box.
  NestedStencil glyphs keep their own x/y. A second save keeps the
  outer Pin.
- draw.io mxGraph `rotation` now stays `TxtAngle` in LibreOffice.
  Official `mxShape.getTextRotation` returns `STYLE_ROTATION` (and
  adds `verticalTextRotation` only when `STYLE_HORIZONTAL != 1`), but
  capture stubbed it to 0 and painted `canvas.text` without the
  rotation argument, so a SysML Activity Partition (`rotation=-90`,
  value `Partition Name`) stayed upright while `updateTransform`
  baked the glyph. Cell labels now pass `STYLE_ROTATION` onto
  `TxtAngle` that libvisio maps to `librevenge:rotate`; vertical
  Cabinet panels still use `TextDirection=1` so they are not
  double-rotated. A second save keeps the angle.
- draw.io mxText `textOpacity` now stays native in LibreOffice.
  Official `mxText.apply` writes `STYLE_TEXT_OPACITY` onto
  `this.opacity` and `configureCanvas` calls `setAlpha(opacity/100)`,
  but capture dropped the key, so iOS Top bar `CARRIER` /
  `11:15AM` (`textOpacity=50`, `#cccccc`) and GMDL Label text
  (`textOpacity=80`) stayed fully opaque. Cell labels now map
  the percent onto Char `ColorTrans`; `readCharIX` never stores
  that cell and `xmlStringToColour` zeros `Colour.a`, so a save
  bakes the blend into `Color` that `collectCharIX` maps to
  `fo:color`. Stencil glyphs and omitted keys reset to 100.
  A second save keeps the faded RGB.
- draw.io mxGraph `fontColor=inherit` now stays native in LibreOffice.
  Official HTML/SVG labels take the parent's computed colour, but
  capture forwarded the `inherit` token, so iOS Button bar `Item 1`
  (`fontColor=inherit` under `fontColor=#666666`) became default
  black that `collectCharIX` maps to `fo:color`. Nested cells now
  freeze the parent hex (and the same for `fillColor` /
  `strokeColor` / `gradientColor`) before paint; omitted keys still
  use `defaultVertex`. A second save keeps Char Color.
- draw.io mxText `html=1` spans now stay native in LibreOffice.
  Official `mxText` paints `<b>` / `<font color>` / `font-size` as
  styled HTML, but capture stripped tags to one Char run, so a UML
  2.5 Classifier title (`<b>Classifier1</b>`) and GCP Expanded
  Product Card `Name` (`<font color="#000000">`) lost bold and
  the black that `collectCharIX` maps to `fo:font-weight` /
  `fo:color`. Cell labels now freeze extra Character rows; stencil
  glyphs without tags stay a single run. A second save keeps Style
  and Color per run.
- draw.io mxText html `<sup>` / `<sub>` now stays native in LibreOffice.
  Official `mxText` paints those tags as raised / lowered runs, but
  capture kept one baseline Char row, so Electrical Vdd (`V<sub>dd</sub>`)
  and GCP Zones `3<sup>rd</sup> Party` lost the Pos that
  `readCharIX` maps to `style:text-position`. Cell labels now freeze
  extra Character rows with Pos 1/2. A second save keeps superscript
  and subscript.
- draw.io mxText CSS `text-decoration` now stays native in LibreOffice.
  Official `mxText` paints HTML `text-decoration:underline` on `<p>` /
  `<span>`, but capture treated block tags as newlines only, so a
  SysML Instance Specification (`instance1 / property1: Type2`) lost
  the Style 0x4 that `readCharIX` maps to `style:text-underline-type`.
  Cell labels now freeze that Char bit (and `line-through` as
  Strikethru). A second save keeps underline.
- draw.io mxText html tables now stay native in LibreOffice.
  Official `mxText` paints `<table>` rows as stacked HTML boxes
  (`overflow=fill`, `height=45%` / `height=25`), but capture joined
  every cell into one centred Char run, so Electrical thermistor
  `\temp\` sat on the heater and P&ID Indicator `TI` / `##` sat in
  the stem that `collectXFormData` maps to `svg:y`. Cell labels now
  freeze one Text child per row. A second save keeps the band pins.
- draw.io Graph XML `label` placeholders now stay native in LibreOffice.
  Official `Graph.convertValueToString` reads the XML user-object
  `label` and `replacePlaceholders` substitutes `%c4Name%`, but capture
  stringified the node as `[object Object]`, so a C4 Person lost
  `Person name` that `collectText` maps to `text:p`. Cell labels now
  freeze the substituted HTML; string values stay unchanged. A second
  save keeps the name.
- draw.io mxText html multi-column tables now stay native in LibreOffice.
  Official `mxText` with `overflow=fill` paints `<td width="25%">`
  columns (`height=0%` is a content band), but capture joined every
  cell into one centred Char run, so Mockup Step Bar `Layer 1`–`Layer 4`
  sat on the dots that `collectXFormData` maps to `svg:x`. Cell labels
  now freeze one Text child per td (`textColor2` on Layer 3 stays
  Char Color). A second save keeps the column pins.
- draw.io JS Canvas style fill/stroke now stay native in LibreOffice.
  Official `mxShape.configureCanvas` paints `fillColor=#083F75`, but
  capture left a `fill` inherit token and `applyStencilStyle` washed a
  C4 Person into defaultFill `#DAE8FC` that `collectFill` maps to
  `svg:fill`. Captured `<shape fill>` / `stroke` now seed FillForegnd /
  LineColor; palette wash skips authored hex. A second save keeps the
  navy.
- draw.io mxText html `font-family` now stays native in LibreOffice.
  Official `mxText` paints CSS `font-family` / `<font face>` as the
  HTML face, but capture dropped those properties, so a Bootstrap
  Alert body (`"open sans", arial, sans-serif`) and SAP Diagram Title
  (`font-family: arial`) kept the canvas Helvetica that `collectCharIX`
  maps to `style:font-name`. Cell labels now freeze Char.Font (CSS
  stack until a Visio face; `"open sans", arial` → Arial). A second
  save keeps the face.
- draw.io mxText html `border-bottom` dotted now stays native in LibreOffice.
  Official `mxText` paints CSS `border-bottom: 1px dotted` under the
  glyph, but capture dropped the border, so an ER Weak Key Attribute
  looked like a plain Attribute while Key Attribute (`fontStyle=4`)
  kept the solid Style 0x4 that `collectCharIX` maps to
  `style:text-underline-type`. Cell labels now freeze a dashed Line
  sibling (`1 2` → `veDashPattern`) that `collectLine` maps to
  `draw:dots`; Char underline stays off. A second save keeps the dots.
- draw.io mxText html `text-align` now stays native in LibreOffice.
  Official `mxText` paints CSS `text-align` on block `<p>` as HTML
  alignment, but capture used only the cell `align`, so a SysML
  Stereotype Property Compartment (`property1 = value` is
  `text-align:left` under a centered title) and Namespace Compartment
  (`align=left` cell with a centered `<p>`) lost the HorzAlign that
  `collectParaIX` maps to `fo:text-align`. Cell labels now freeze Para
  alignment per HTML block; inline `span` `text-align` still inherits
  the cell. A second save keeps left and center on the same shape.
- draw.io mxText html `margin` now stays native in LibreOffice.
  Official `mxText` paints CSS `margin` on block `<p>` as HTML padding
  inside the cell, but capture dropped those properties, so a SysML
  Abstract Definition (`margin:13px` around `Name`) and Stereotype
  Property Compartment (`margin-left:8px` on `property1 = value`) lost
  the IndLeft / SpBefore that `collectParaIX` maps to `fo:margin-left`
  / `fo:margin-top`. Cell labels now freeze those Para cells (only the
  first run in a block keeps `margin-top`). A second save keeps the
  inset.
- draw.io mxText html `<font size>` now stays native in LibreOffice.
  Official `mxText` paints the HTML size 1–7 presentational hint
  (Chromium `xx-small`…`xxx-large` at 10/13/16/18/24/32/48px), but
  capture `parseFloat`'d `size="1"` as 1px, so an SAP Interface and
  Infographic Roadmap body (`<font size="1">Lorem…`) hit the 0.04in
  Char.Size floor that `collectCharIX` maps to `fo:font-size`. Cell
  labels now freeze those px. CSS `font-size: 11px` stays a length.
  A second save keeps Size.
- draw.io mxText html `<hr>` now stays native in LibreOffice.
  Official `mxText` paints HTML rules as a full-width line in the
  overflow=fill box, but capture folded `<hr>` into a newline, so a
  SysML Stereotype Property Compartment lost the separator between
  `Block1` and `property1 = value` that `collectLine` maps to
  `svg:stroke`. Cell labels now freeze a Line sibling and split the
  title / body into stacked Text boxes (Bootstrap Alert `border-color`
  stays LineColor). A second save keeps the rule.
- draw.io mxText html table `cellpadding` now stays native in LibreOffice.
  Official `mxText` paints `<table cellpadding="4">` as HTML cell padding
  (and browsers still parse a last `<tr>` without `</tr>`), but capture
  required a closing tag and dropped the attribute, so a P&ID Discrete
  Instrument stacked `TI` / `##` in one box without the LeftMargin that
  `collectTextBlock` maps to `fo:padding-left`. Cell labels now freeze
  one Text child per row and add cellpadding onto mxText spacing. A
  second save keeps the bands and padding.
- draw.io mxText html table cell CSS padding now stays native in LibreOffice.
  Official `mxText` paints `<td style="padding-left:11%">` as HTML cell
  padding (percentages of the containing-block width), but capture only
  applied table `cellpadding`, so a P&ID Centrifugal Compressor - Turbine
  Driven `T` sat on the 2px mxText spacing without the LeftMargin that
  `collectTextBlock` maps to `fo:padding-left`. Cell labels now freeze td
  padding on top of cellpadding. A second save keeps the inset.
- draw.io mxText html CSS `font-size` em now stays native in LibreOffice.
  Official `mxText` paints `font-size:2em` as twice the parent size, but
  capture `parseFloat`'d `2em` as 2px, so Lean Mapping Signal Kanban `S`
  and Production/Withdrawal Kanban hit the 0.04in Char.Size floor that
  `collectCharIX` maps to `fo:font-size`. Table `font-size:1.5em` (Orders
  `IN`) now inherits onto the cell runs. CSS `font-size: 11px` stays a
  length. A second save keeps Size.
- draw.io mxText html `text-wrap: nowrap` now stays native in LibreOffice.
  Official `mxText` paints CSS `text-wrap: nowrap` (SAP Diagram Title)
  as a non-wrapping HTML span, but capture kept cell `whiteSpace=wrap`,
  so the long description wrapped inside the 500px box. `collectTextBlock`
  has no wrap token (`veWordWrap` is a User row LibreOffice never
  collects); omitting wrap lets a save expand TxtWidth (`svg:width`) so
  Draw keeps each `<br>` line unwrapped. A second save keeps the wide
  text frame.
- draw.io mxGraph `fillColor=strokeColor` now stays native in LibreOffice.
  Official `mxShape.apply` copies `fillColor=strokeColor` onto the fill
  (UML Initial, ArchiMate Junction, electrical diodes), but capture left
  the keyword, so `_mxGraphPaintColor` missed it and `applyStencilStyle`
  washed a white factory fill into palette `#DAE8FC` that `collectFill`
  maps to `svg:fill`. Cell styles now freeze the referenced hex. A second
  save keeps FillForegnd.
- draw.io mxText html font-size now stays native on wide composites in
  LibreOffice. Official `mxText` paints Salesforce Header `14px` / `9px`
  at catalog scale `1.5/930`, but the decoder clamped Char.Size to
  0.04in (~2.88pt), so title and body hit the same `fo:font-size`
  collectCharIX emits. The floor is Visio's 0.5pt so 14px vs 9px stay
  distinct. A second save keeps Size.
- draw.io mxText html UA `<p>`/`<h3>` margin now stays native in
  LibreOffice. Official `mxText` html=1 keeps the browser block margins
  (Salesforce Header `spacingTop=-20` cancels `<h3>` 1em), but capture
  only read CSS `margin`, so title and body stacked with no SpBefore
  that `collectParaIX` maps to `fo:margin-top`. Adjacent blocks collapse
  like CSS. SysML `margin:0px` still zeroes the UA slot. A second save
  keeps Para spacing.
- draw.io mxText html UA `<h1>`–`<h6>` size/weight now stay native in
  LibreOffice. Official `mxText` html=1 keeps the browser heading
  defaults (h3 1.17em bold), but capture only applied UA margins, so a
  bare heading would miss Char Size / Style.bold that `collectCharIX`
  maps to `fo:font-size` / `fo:font-weight`. CSS `font-weight:normal`
  (Salesforce Header inner `<font>`) still clears the UA bold; inner
  `font-size:14px` still wins. SysML `margin:0px` is unchanged. A
  second save keeps Size and Style.
- draw.io mxImageShape SVG `<style>` class fills now stay native in
  LibreOffice. Official GCP icons (Vertex AI `.st0{fill:#b5cbf9}` /
  `.st1` / `.st2`) paint through `mxImageShape`, but capture skipped
  `<style>` and defaulted class-only paths to black, so
  `collectFillAndShadow` never saw those FillForegnd hexes. Capture now
  applies the stylesheet (and `fill-opacity`) before presentation
  attributes. A second save keeps the three blues.
- draw.io mxImageShape SVG `url(#gradient)` now stays native in
  LibreOffice. Official SAP Logo (`fill="url(#b)"` linearGradient
  `#00b8f1`→`#1e5fbb`, plus `transform=matrix`) paints through
  `mxImageShape`, but capture skipped paint servers and left the
  diamond on inherit FillForegnd that `applyStencilStyle` washed to
  the palette. Capture now freezes two-stop FillPattern 25–40 that
  libvisio `_fillAndShadowProperties` maps to ODF `draw:style=linear`,
  applies SVG translate/scale/matrix, and hex-locks `#ffffff`
  letters. A second save keeps the ramp.
- draw.io `mxgraph.sap.icon` (SAP Foundational) now stays native in
  LibreOffice. Official `mxSAPIconShape.foreground` paints
  `GRAPH_IMAGE_PATH + '/lib/sap/' + SAPIcon + '.svg'` (Init.js
  `GRAPH_IMAGE_PATH='img'`), but capture stubbed that global to `''`,
  so `c.image` opened `/lib/sap/Name.svg` and LibreOffice only saw
  the grey ellipse. Capture now uses `img`, appends `.svg` on Generic
  Icons `image=` stems, and applies Adobe `gradientTransform`
  (PKI `translate(0 12.4) scale(1 -1)` so FillPattern 28 south
  matches the flipped Y). A second save keeps the two-stop ramps.
- draw.io mxImageShape SVG `stroke-width` now stays native in
  LibreOffice. Official SAP Analytics Cloud Embedded Edition paints a
  `fill="none"` crescent with `stroke-width="1.875"`, but capture
  never copied that presentation attribute, so `collectLine` only saw
  the 0.01 in LineWeight default and Draw drew a hairline. Capture now
  scales `stroke-width` / `stroke-linecap` / `stroke-linejoin` with
  the SVG `map()` scale into the same stencil units as MoveTo.
  A second save keeps LineWeight.
- draw.io mxImageShape SVG `<text>` now stays native in
  LibreOffice. Official Cumulus DDos Server paints `DDos` through
  `<text>/<tspan>` (y is baseline, `font-size` on the tspan), but
  capture skipped those elements and dropped text nodes from
  `parseXml`, so `collectCharIX` never saw the glyph — only the
  sidebar IP label. Capture now keeps character data, scales
  `font-size` with the SVG `map()` transform, and freezes
  `fo:font-size` / `fo:color` / `style:font-name`. A second save keeps
  the run.
- draw.io mxImageShape SVG `<textPath>` now stays native in
  LibreOffice. Official IBM Key Management paints `KEY MGMT` along
  path `#A` (`startOffset="67%"`), but capture returned false on any
  `textPath`, so `collectCharIX` never saw the glyph. Capture now
  flattens the guide, pins each letter as a Char sibling, and writes
  `TxtAngle` that libvisio collectTextBlock maps to
  `librevenge:rotate`. `MyriadPro-Bold` becomes Arial plus Style bold.
  A second save keeps the run.
- draw.io mxImageShape SVG white strokes now stay native in
  LibreOffice. Official IBM Key Management's shaft is
  `stroke="#fff"` with `fill="none"`, but `paintToken` collapsed that
  hex onto the `fill` keyword (default fillColor is white). After
  `fillcolor=none`, the decoder copied none onto the stroke and
  dropped the LineWeight sibling `collectLine` maps to
  `svg:stroke-width`. SVG presentation strokes now force hex like
  fills. A second save keeps the tick.
- draw.io mxImageShape SVG `stroke-dasharray` now stays native in
  LibreOffice. Official Active Directory Database Partition 2 paints a
  white `stroke-dasharray="8,8"` slash, but capture never copied that
  presentation attribute, so `collectLine` only saw solid LinePattern 1.
  Capture now scales the array with the SVG `map()` transform into
  `veDashPattern`. libvisio treats custom pattern `0xfe` as solid, so
  a save bakes MoveTo gaps. `stroke-dasharray:none` stays undashed.
  A second save keeps the ticks.
- draw.io mxImageShape SVG `fill-opacity` now stays native in
  LibreOffice. Official Azure Power BI and Dynamics Field Service paint
  black shadow blobs at `fill-opacity="0.2"` / `.18`, but capture never
  copied those presentation attributes, so `collectFillAndShadow` only
  saw opaque FillForegnd and Draw drew a solid black overlay. Capture
  now forwards `fill-opacity` / `stroke-opacity` into `fillalpha` that
  becomes FillForegndTrans (`draw:opacity`). A second save keeps the
  fade.
- draw.io mxImageShape SVG `transform="matrix(a b c d e f)"` now stays
  native in LibreOffice. Official MSCAE Event Grid Topics and IBM
  Microservices Application rotate circles with off-diagonal `b`/`c`
  (`matrix(.707 -.707 .707 .707)` / `matrix(.02 -1 1 .02)`), but
  capture only applied `translate(e,f)` plus `scale(a,d)`, so
  `collectGeometry` saw a 0.707× / 0.02× ellipse and Draw dropped or
  misplaced the glyph. Capture now composes the 2×3 affine into `map()`
  and emits the rotated contour. Axis-aligned `matrix(sx,0,0,sy,tx,ty)`
  still uses translate+scale. A second save keeps the dots.
- draw.io mxImageShape SVG `clip-path` now stays native in LibreOffice.
  Official Azure2 Globe meridians, Cosmos DB clouds, MFA shield highlights
  and Power BI Embedded bars paint inside `clip-path` circles/stairs, but
  capture skipped `<clipPath>` so `collectGeometry` saw the unclipped
  overflow LibreOffice Draw would paint. Capture now intersects fill
  contours in `map()` space; viewBox-sized rect clips stay identity so
  ellipses are not tessellated. A second save keeps the clipped polygons.
- draw.io mxImageShape SVG `mask` now stays native in LibreOffice.
  Official SAP Build letterform and Dynamics Core HR rounded plate paint
  fills under `maskUnits="userSpaceOnUse"`, but capture skipped `<mask>`
  so `collectGeometry` saw overflowing blobs (SAP Build to x=-6) that
  Draw would paint outside the glyph. Capture now intersects those fills
  like `clip-path`. Default `objectBoundingBox` masks stay unmapped.
  A second save keeps the masked polygons.
- draw.io mxImageShape SVG `stroke="url(#gradient)"` now stays native in
  LibreOffice. Official SAP Analytics Cloud Embedded Edition crescent and
  SAP Task Center ticks paint two-stop `stroke=url(#…)` (width 1.875 /
  round-cap arcs), but `collectLine` never reads LineGradient so Draw
  only saw a first-stop solid hairline. Capture now expands those strokes
  into filled ribbons and applies FillPattern 25–40 that
  `collectFillAndShadow` maps to ODF `draw:style=linear` / `radial`.
  A second save keeps the wash.
- draw.io mxImageShape SVG `filter` / `feOffset` now stays native in
  LibreOffice. Official SAP Build Work Zone Advanced Edition paints
  three radial blobs under `filter=url(#…)` `feOffset` + SourceGraphic
  blend, but capture skipped `<filter>` so Draw never collected
  `draw:shadow`. Capture now freezes those offsets as ShdwPattern 1 that
  `_fillAndShadowProperties` maps to ODF `draw:shadow`. Blur-only
  filters stay unmapped. A second save keeps the hard offset.
- draw.io mxImageShape SVG `mask` `<use>` now stays native in
  LibreOffice. Official Allied Telesis VOIP IP Phone handset ticks and
  Secure Building bushes paint under `mask` whose content is
  `<use href="#path">` (and VOIP strokes are `fill:none`), but capture
  skipped `<use>` inside clip/mask so `collectGeometry` never saw the
  intersected polygons Draw would paint. Capture now resolves those
  uses, maps mask content via `maskContentUnits` (default
  `userSpaceOnUse`), and expands clipped strokes into filled ribbons.
  A second save keeps the polygons.
- draw.io mxImageShape SVG rotated `roundrect` now stays native in
  LibreOffice. Official Azure Search handle (`rect rx` +
  `transform="rotate(-45,cx,cy)"`), Keys bits and CDN Profiles rails
  paint stadiums under `rotate()`, but capture's `roundrect()` flattened
  those to a 4-point poly when `isRotated()`, and `canvas.rotate` pivoted
  after `map()` scale so the handle sat under the lens. Capture now
  composes `rotate(a,cx,cy)` in user space like `svgTransformPoint` and
  emits cubic quarters through `map()` like rotated ellipses. Axis-
  aligned roundrects still use the `<roundrect>` token. A second
  save keeps the CubBezTo corners.
- draw.io mxImageShape SVG `<symbol>` / `<use>` now stays native in
  LibreOffice. Official IBM Live Collaboration, File Sync and Networking
  badges define the orange disk in a `<symbol viewBox>` referenced by
  `<use width height x y>`, but capture painted the template as an
  extra child of `<svg>` (circle at 0,0 overflowing the tile) and
  translated `use` x/y without mapping `viewBox`, so `collectGeometry`
  saw a second disk in the corner while the referenced disk sat off
  the glyph. Capture now skips template `<symbol>` nodes and maps
  `viewBox` into the use viewport. A second save keeps one disk.
- draw.io mxImageShape SVG three-stop axial `url(#gradient)` now stays
  native in LibreOffice. Official Active Directory Cell Phone (`url(#E)`
  `#3940b4`→`#bde1fd`→`#2d31af`) and Tunnel (`url(#B)`
  `#1574ff`→`#bee4ff`→`#1473ff`) paint a light peak between matching
  ends, but capture took only first/last so `collectFillAndShadow`
  FillPattern 27 / 30 was an almost-solid dark bar. Capture now maps
  those centred matching-end ramps to FillPattern 26 / 29 that
  `_fillAndShadowProperties` emits as ODF `draw:style=axial`
  (`start-color` at the centre). Two-stop compass ramps stay 25–34.
  A second save keeps the wash.
- draw.io mxImageShape SVG three-stop `url(#gradient)` whose middle is
  off the first→last lerp now keeps that stop in LibreOffice. Official
  Active Directory Windows Server (2) / Windows Router paint LED
  highlights (`#f2580a`→`#fea15f`→`#a11a00`), but capture took only
  first/last so `collectFillAndShadow` FillPattern 27 was an orange→red
  bar. Capture now writes FillGradient rows; leftover bakes SoftEdges
  PNG because 25–40 only store two colours. SAP Logo's on-lerp cyan
  ramp stays native 25–40. A second save keeps the plate.
- draw.io mxImageShape SVG diagonal `url(#gradient)` now stays native
  in LibreOffice. Official Azure Globe (`gradientTransform` 45° matrix)
  and SAP PKI Certificate Service (Y-flipped diamond) plus Analytics
  Cloud Embedded Edition's crescent stroke are 45° / 135° washes, but
  capture snapped `|dx|` vs `|dy|` to east / south so
  `_fillAndShadowProperties` emitted ODF `draw:angle` 90 / 180.
  Capture now maps the eight libvisio FillPattern 25–34 slots
  (31–34 are 225 / 135 / 315 / 45). `skewX` on Cognitive Services
  Decisions' parallelogram `gradientTransform` participates in that
  vector. Matching-end three-stop axials still use 26 / 29 on the
  dominant axis. A second save keeps the wash.
- draw.io mxImageShape SVG inset or off-slot `url(#gradient)` now keeps
  that wash in LibreOffice. Official Atlassian Jira (`offset=".18"`
  `#0052cc`→`#2684ff`) and Azure Power BI Embedded (~22° off ODF 135°)
  are two-stop linears, but FillPattern 25–34 always runs 0→1 on eight
  compass angles (`FillGradient` `Position` / `FillGradientAngle` are
  not tokens). Capture now writes FillGradient rows; leftover bakes
  SoftEdges PNG. SAP Logo's on-lerp south 0→1 cyan ramp stays native
  25–40. Globe's 45° fallback is still FillPattern 34; its 0.82 stop
  bakes. A second save keeps the plate.
- draw.io mxImageShape SVG radial `url(#gradient)` with more than two
  unique colours or inset Positions now keeps that wash in LibreOffice.
  Official Azure Applied AI (`#9cebff`→`#50e6ff`→`#32bedd`) and Cosmos
  DB (`offset=".183"`) are radials, but FillPattern 40 only stores
  FillForegnd / FillBkgnd across 0→1 (`FillGradient` `Position` is not
  a token). Capture now writes FillGradient rows; leftover bakes
  SoftEdges PNG. SAP Task Center's two-stop 0→1 ticks stay native 40.
  A second save keeps the plate.
- draw.io mxImageShape SVG elliptical `radialGradient` now stays native
  in LibreOffice. Official SAP Build Apps / Work Zone blobs paint
  two-stop `userSpaceOnUse` radials whose `gradientTransform` is an
  ellipse (aspect ≈1.85), but FillPattern 40 and leftover FillGradient
  are both circles in the XForm box that `_fillAndShadowProperties`
  maps to ODF `draw:style=radial`. Capture now tessellates those
  washes as concentric solid FillForegnd discs clipped to the glyph.
  Circular two-stop discs (SAP Task Center ticks, Build Apps blob D)
  stay native 40; Azure Applied AI's three unique colours still
  leftover PNG. A second save keeps the polygons.
- draw.io mxImageShape SVG elliptical radial evenodd holes now stay
  native in LibreOffice. Official Azure OpenAI (`rotate(45) scale(25,-34)`
  plus-cutout) and SAP Task Center donuts are two-stop ellipses on
  compound paths, but capture skipped `rings.length !== 1` so Draw's
  FillPattern 40 circle filled the hole. Capture now keeps outer and
  hole contours in one Geometry so `collectGeometry` `svg:fill-rule=evenodd`
  still punches, and tessellates `disc ∩ outer` / `disc ∩ hole` bands.
  Task Center ticks stay native 40. A second save keeps the polygons.
- draw.io mxImageShape SVG `stop-opacity` ramps now stay native in
  LibreOffice. Official Azure Translator Text paints white→white
  `stop-opacity="0.3"` highlights on the speech chevrons, but capture
  collapsed same-RGB `url(#gradient)` to solid FillForegnd, and leftover
  SoftEdges PNG composites onto opaque white that hides the `#0078d4`
  plate (`_fillAndShadowProperties` also drops `draw:opacity` on
  FillPattern 25–40). Capture now tessellates the fade as FillPattern 1
  + FillForegndTrans slabs `collectFillAndShadow` maps to
  `draw:opacity`. Opaque two-stop compass ramps stay native 25–40. A
  second save keeps the polygons.
- draw.io mxImageShape SVG short `userSpaceOnUse` linear washes now stay
  native in LibreOffice. Official SAP Analytics Cloud Embedded Edition
  `url(#B)` (`#00bbff`→`#008bff` from `(12.2,2)` to `(18.5,6.8)`) only
  covers ~30% of the viewBox, but FillPattern 25–34 and leftover
  FillGradient both interpolate 0→1 across the XForm
  (`_fillAndShadowProperties` `draw:style=linear`). Capture now
  tessellates that wedge as FillForegnd slabs. The full-box crescent
  stroke `url(#A)` stays FillPattern 32; SAP Logo's tall south ramp
  stays 28. Globe's 45° / 0.82 wash, Jira's inset chevron, the Windows
  Server LED mid-stop, and Cell Phone's axial peak use the same slabs
  (leftover FillGradient still 0→1s the XForm). A second save keeps
  the polygons.
- draw.io mxImageShape SVG offset / undersized circular `radialGradient`
  now stays native in LibreOffice. Official Open Supply Chain Platform
  paints four `userSpaceOnUse` discs (`r≈2.25` on an 18 box, plus the
  inner `r≈4.4` cyan), and User Subscriptions puts gold `#ffd70f`→`#fea11b`
  on a key whose centre is ~0.85 of the viewBox radius from the icon
  middle, but FillPattern 40 and leftover FillGradient both interpolate
  0→1 from the child XForm centre (`_fillAndShadowProperties`
  `svg:cx/cy=0.5`). Capture sizes every mxImageShape child to the full
  icon box, so those washes sampled the edge stop. Capture now
  tessellates them as concentric FillForegnd discs like the elliptical
  case. Near-centred discs larger than the box (SAP Build Apps blob D)
  stay native 40; Azure Applied AI's three unique colours still leftover
  PNG. A second save keeps the polygons.
- draw.io mxImageShape SVG short `userSpaceOnUse` gradient strokes now stay
  native in LibreOffice. Official SAP Secure Login Service for SAP GUI
  paints the check as `stroke=url(#B)` (`#1348ff`→`#06238d` from
  `(10.7,13.3)` to `(14.5,19.3)`), but `collectLine` has no LineGradient
  so capture filled the ribbon with FillPattern 32 / leftover FillGradient
  that `_fillAndShadowProperties` still interpolates 0→1 across the icon
  XForm. Capture now tessellates that ribbon as FillForegnd slabs like the
  short fill case. The diamond fill `url(#A)` and Analytics Cloud crescent
  `url(#A)` stay FillPattern 32; Task Center radial ticks stay 40. A
  second save keeps the polygons.
- draw.io mxImageShape SVG element `opacity` on opaque `url(#gradient)`
  now stays native in LibreOffice. Official Intune Software Updates paints
  a `#d2ebff`→`#f0fffd` screen at `opacity="0.9"` over `#0078d4`, but
  FillPattern 25–40 drop `draw:opacity` (`_fillAndShadowProperties`
  `styleProps.remove`) so Draw filled the wash solid and hid the plate.
  Capture now tessellates that overlay as FillPattern 1 + FillForegndTrans
  slabs like `stop-opacity` ramps. Opaque two-stop compass fills stay
  25–40. A second save keeps the polygons.
- draw.io mxImageShape SVG off-slot / inset-stop `url(#gradient)` now stays
  native in LibreOffice. Official Azure Power BI Embedded bars
  (`#e6ad10`→`#c87e0e` ~22° off ODF 135°), SAP PKI Certificate Service's
  Y-flipped diamond (~10° off 135°), and Cosmos DB's radial
  `offset=".183"` / `#5ea0ef` would leftover a SoftEdges PNG:
  `FillGradientAngle` / stop `Position` are not tokens, leftover still
  interpolates 0→1 across the child XForm, and Foreign images composite
  onto opaque white so the plate hid sibling bars / the lock / the cyan
  decorations. Capture now tessellates those washes as FillForegnd slabs
  / concentric discs like the short-vector and offset-radial cases. SAP
  Logo's on-slot south 0→1 cyan ramp stays 28; Analytics Cloud's crescent
  `url(#A)` stays FillPattern 32; Task Center two-stop ticks stay 40;
  Azure Applied AI's three unique colours still leftover PNG. A second
  save keeps the polygons.
- draw.io mxImageShape SVG multi-stop `radialGradient` now stays native
  in LibreOffice. Official Azure Applied AI paints `#9cebff`→`#50e6ff`→
  `#32bedd` with an elliptical `gradientTransform` plus three four-stop
  highlight discs, but FillPattern 40 only stores FillForegnd /
  FillBkgnd and leftover FillGradient is a circle on the child XForm
  (`_fillAndShadowProperties` `svg:cx/cy=0.5`) whose SoftEdges PNG
  composites onto opaque white over the navy sail. Capture now
  tessellates those washes as concentric FillForegnd discs like the
  two-stop ellipse case. Task Center two-stop ticks stay 40. A second
  save keeps the polygons.
- draw.io `sketch=1` / `fillStyle` now stays native in LibreOffice.
  Official General / misc Ellipse Sketch (`fillStyle=dots`), Diamond
  Sketch (`cross-hatch`) and Rectangle Sketch (`hachureAngle=45`) wrap
  the canvas with mxRoughCanvas2D, but capture left `setFillStyle` a
  stub, so leftover wrote solid FillPattern 1. `collectFillAndShadow`
  already maps FillPattern 2–24 to `draw:fill=hatch`. Capture now
  records the Sketch style and leftover maps it onto those hatches
  (plus jiggle stroke plates). A second save keeps the hatch.
- draw.io mxImageShape SVG blur-only `feGaussianBlur` now stays native
  in LibreOffice. Dynamics365 Talent Attract and Azure Copilot Studio
  paint black `g opacity` / `fill-opacity` discs through a filter that
  has `stdDeviation` but no `feOffset`. libvisio has no gaussian token,
  leftover SoftEdges PNG composites onto opaque white over the yellow
  plate, and `svgFilterDropShadow` skipped those filters so Draw saw a
  hard edge. Capture now outsets the contour as FillPattern 1 +
  FillForegndTrans rings (`collectFillAndShadow` `draw:opacity`). Tiny
  σ (`<0.5`) still stays a single fill. A second save keeps the rings.
- draw.io mxImageShape SVG default `stop-color` now stays native in
  LibreOffice. Dataverse `paint2_linear` (and Azure A highlights) only
  set `stop-opacity` on black stops — SVG defaults `stop-color` to
  black — but capture skipped those stops, so the 0.25 rotated wash
  never reached `collectFillAndShadow` `draw:opacity`. Capture now
  keeps the default black and tessellates the ramp as FillPattern 1 +
  FillForegndTrans. A second save keeps the wash.
- draw.io mxText `overflow=fill` now stays native in LibreOffice.
  Official `mxCellRenderer.rotateLabelBounds` (`legacySpacing`) skips
  mxText spacing on `overflow=fill`/`width` so a 100% HTML table is the
  full cell, but capture still wrote the default 2px as TextBlock
  LeftMargin that `collectTextBlock` maps to `fo:padding-left`. A P&ID
  Centrifugal Compressor `T` (`padding-left:11%`) and Removable Spool
  `RS` no longer sit on that extra inset. DiscInst without fill still
  keeps spacing 2 plus cellpadding. A second save keeps the padding.
- draw.io mxShape `getLabelBounds` now stays native in LibreOffice.
  Official `mxCellRenderer.getLabelBounds` insets the mxText box via
  `note2` `boundedLbl` / folder `tabHeight` / `process2` rails, but
  capture always painted `canvas.text` on the full cell, so a UML
  2.5 Comment (`Comment1 body`, `size=25`) sat under the dog-ear that
  `collectTextBlock` maps to `svg:height` / `svg:y`. Cell labels now
  shrink like `getLabelMargins`; `labelPosition` still shifts the
  whole box. A second save keeps the inset Txt pin.
- draw.io mxText `fontStyle` now stays native in LibreOffice.
  Official `mxText.configureCanvas` always calls `setFontStyle` and
  `mxXmlCanvas2D` emits the compressed token even when it returns to
  0, but capture only wrote `<fontstyle>` when the bits were non-zero,
  so a SysML Block `fontStyle=2` title (`constraints`) leaked italic
  onto `{x > y}` that `collectCharIX` maps to `fo:font-style`. Cell
  labels now reset like `configureCanvas`; stencil `fontstyle` nodes
  still stick until the next token. A second save keeps Char italic
  only on the titles.
- draw.io mxStencil `fontfamily` now stays native in LibreOffice.
  Official `mxStencil.drawNode` calls `setFontFamily(family)` and PID
  valves call `c.setFontFamily('Helvetica')`, but capture stubbed
  `setFontFamily` and the decoder ignored the XML node, so Cisco
  Contact Center `V`/`WWW` and Gate Valve (Motor) `M` used the
  StyleSheet Arial that `collectCharIX` maps to `style:font-name`.
  Quoted CSS families strip to a Visio face (`sans-serif` → Arial).
  A second save keeps `Char.Font`.
- draw.io style `strokeWidth` now stays native in LibreOffice.
  Official `mxShape.paint` calls `setStrokeWidth(this.strokewidth)` and
  `mxStencil.drawShape` inherits `STYLE_STROKEWIDTH` (or `width * minScale`),
  but capture never forwarded the style, so an Infographic Arc
  (`strokeWidth=6`) and Bootstrap Border spinner (`strokeWidth=4`) used
  the 0.01 in palette default that `collectLine` still paints as a
  hairline. Capture now emits the width; `restore()` then re-emits the
  pre-save `width=1`, so the decoder freezes `LineWeight` when parent
  Geometry is painted (same as dash). A second save keeps the weight.
- draw.io mxGraph `shadow=1` now stays native in LibreOffice.
  Official `mxShape.configureCanvas` calls `setShadow(this.isShadow)`
  and `mxSvgCanvas2D.createShadow` clones a translated grey silhouette,
  but capture stubbed `setShadow` so GCP2 Service Cards (`shadow=1`)
  dropped the drop-shadow that libvisio `_fillAndShadowProperties`
  maps to ODF `draw:shadow`. The flag now becomes `ShdwPattern` 1 with
  mxGraph's 2×3 px offset (Visio Y-up) and `#808080`; blur stays 0 so
  Draw keeps the hard edge instead of a Gaussian PNG bake. Foreground
  decorations still call `setShadow(false)` after the body. A second
  save keeps `ShdwPattern` 1.
- draw.io mxStencil `linecap` / `linejoin` / `miterlimit` / `dashpattern`
  now stay native in LibreOffice. `mxStencil.drawNode` calls
  `setLineCap` / `setLineJoin` / `setMiterLimit` / `setDashPattern`, but
  capture stubbed them and the Dart decoder treated every `dashpattern`
  as `dashed=1` without the array, so an EIP Detour diagonal stayed a
  solid stroke that shared the box `LinePattern` (`collectLine` is
  shape-level) and a Lean Mapping arrow used the default round cap.
  Numeric patterns now become `User.veDashPattern` siblings that bake
  to a MoveTo ribbon because libvisio treats custom pattern `0xfe` as
  solid; `linecap=butt` becomes `LineCap` 1 that `_lineProperties` maps
  to `svg:stroke-linecap=butt`. Disk clipart extras (Nurse Green/Red,
  Soldier) join the People palette as ForeignData. A second
  save keeps the dash array and the flat cap.
- draw.io mxGraph `setGradient` now stays native in LibreOffice.
  Official `mxShape.configureCanvas` calls `c.setGradient(fill,
  gradientColor, …, gradientDirection)` when `STYLE_GRADIENTCOLOR` is
  set, but capture stubbed it and the decoder never saw a two-stop
  wash, so AWS4 Sumerian (`fillColor=#BC1356;gradientColor=#F34482;
  gradientDirection=north`) used inherit FillForegnd that
  `applyStencilStyle` painted as `kStencilAws` beige. Capture now
  emits `fillgradient`; the decoder bakes sibling FillPattern 25–34
  (`FillBkgnd`→`FillForegnd`) that libvisio `_fillAndShadowProperties`
  collects. `setFillColor` no longer collapses a hex that happens to
  match `strokeColor` into inherit FillForegnd, so a Sumerian glyph
  and a Note dog-ear stay siblings `collectGeometry` can paint. A
  second save keeps the magenta/pink ramp.
- draw.io mxStencil `alpha` / `fillalpha` / `strokealpha` now stay
  native in LibreOffice. `mxStencil.drawNode` calls `setAlpha` /
  fill / stroke alpha, but capture dropped them and the Dart decoder
  ignored the nodes, so a Cisco rack overlay (`fillalpha` 0.232) and
  a GMDL `docs` fold (`alpha` 0.5) painted fully opaque. Those values
  now become `FillForegndTrans` / `LineColorTrans` that libvisio
  `_fillAndShadowProperties` maps to ODF `draw:opacity`. Sidebar
  `opacity=12` GMDL buttons emit the same cells. A second save keeps
  the wash.
- draw.io mxStencil `strokewidth` now stays native in LibreOffice.
  `mxStencil.drawNode` calls `setStrokeWidth(width * minScale)`, but
  capture dropped it and the Dart decoder ignored the node, so a
  Checkbox On tick used the 0.01 in palette LineWeight that
  `collectLine` still paints as a hairline. Authored widths now become
  sibling `LineWeight` libvisio collects. A second save keeps the tick.
- draw.io mxStencil hex `fillcolor` / `fontcolor` now stay native in
  LibreOffice. `mxStencil.parseColor` applies those nodes, but capture
  dropped hex and the Dart decoder ignored them, so a Radio Button On
  inner dot shared one evenodd `FillForegnd` with the chrome
  (`collectGeometry` + `svg:fill-rule=evenodd`) and On-Off ON stayed
  black. Hex fills/strokes now become sibling shapes libvisio paints
  independently; `fontcolor` reaches `collectCharIX`. `fill` / `stroke`
  keywords still use the parent so the palette can recolor the body.
  A second save keeps the dot, the purple half and the white letters.
- draw.io sidebar cell values now stay native in LibreOffice. Capture
  painted `paintVertexShape` but dropped `createVertexTemplateEntry`'s
  value, so P&ID `TI`/`##`, Basic Button and AWS group titles never
  reached libvisio `collectText`. Those labels now become Text children.
  A second save keeps the letters.
- draw.io clipart libraries now stay native in LibreOffice.
  `Sidebar.js` `init` calls `addImagePalette` for Computer, Finance, Various,
  Networking, People and Telecommunication under `img/lib/clip_art`, but
  capture never ran those non-zero-arg palettes, so Gear, Laptop and Suit
  never reached `VisioDocument::parse`. Those PNGs now become ForeignData
  media parts that libvisio `collectForeignData` paints. Media part names
  use unsigned 64-bit FNV so Dart's wrapping integers never put a minus in
  the ZIP. A second save keeps the bitmap.
- draw.io SVG-in-PNG icons now stay native in LibreOffice. Capture skipped
  SVG `<image href="data:image/png">` (IBM VPC Floating IP), so
  `VisioDocument::parse` never saw ForeignData. Those rasters now become
  media parts that libvisio `collectForeignData` paints. A second save keeps
  the bitmap.
- draw.io Entity Relation crow's-foot markers now stay native in LibreOffice.
  Capture stubbed `mxMarker.addMarker` and painted `shape=connector` as a
  polyline plus a generic triangle, so `ERoneToMany` / `ERzeroToMany` /
  `ERmany` never reached `VisioDocument::parse`. Official `mxPolyline` /
  `mxConnector` now call the same `mxMarker` factories `mxER.js` registers,
  including the optional participation circle. A second save keeps the
  double rectangle, double diamond, double ellipse and crow's foot.
- draw.io classic UML palettes now stay native in LibreOffice. Capture only
  loaded `Sidebar-*.js`, so Class, Lifeline, Use Case and Package in
  `grapheditor/Sidebar.js` `addUmlPalette` never reached
  `VisioDocument::parse`. Those templates now paint through the same Canvas
  path, including `umlLifeline` participant heads (`cellRenderer.getShape`
  plus `mxShape.apply`) and `mxLabel` gear icons (Item 2). SVG path fills are
  applied even when the label is `fillColor=none`. A second save keeps the
  stacked class, dashed lifeline, oval, folder and gear.
- draw.io General / Misc / Advanced palettes now stay native in LibreOffice.
  Capture only loaded `Sidebar-*.js`, so Note, Cube, Callout and Double
  Ellipse in `grapheditor/Sidebar.js` never reached `VisioDocument::parse`.
  Those official `addGeneralPalette` / `addMiscPalette` /
  `addAdvancedPalette` templates now paint through the same Canvas path.
  A second save keeps the dog-ear, isometric cube and double oval.
- draw.io SVG `image;` icons now stay native in LibreOffice. Capture skipped
  `shape=image` (Azure2, SAP, GCP data-URI), so Bot Services never reached
  `VisioDocument::parse`. `mxImageShape` now vectorises SVG files / data URIs
  (including `<use href>`), and ArchiMate Work Package's concatenated
  `shape=…rounded=1` is a rounded rectangle. A second save keeps the badge
  and roundrect.
- draw.io XML stencils used by JavaScript sidebars now stay native in
  LibreOffice. Capture only painted registered Canvas constructors, so
  Flowchart Terminator / Decision (`shape=mxgraph.flowchart.*`) never
  reached `VisioDocument::parse`. Vertex templates now use the same
  `mxStencil.drawShape` path composite cells already used. A second save
  keeps the stadium and diamond.
- draw.io default rectangles now stay native in LibreOffice. Capture treated
  empty `shape`, `rectangle`, `label` and `rect` as unregistered, so Flowchart
  Process and AWS Availability Zone never reached `VisioDocument::parse`.
  Those vertices now use official `mxRectangleShape.paintBackground` (rounded
  / dashed / `fillColor=none`). Nested stencil `fillcolor=none` /
  `strokecolor=none` also match `mxStencil.parseColor`. A second save keeps
  the roundrect and dashed hollow box.
- draw.io `link` and `flexArrow` connectors now stay native in LibreOffice.
  Capture inherited a polyline `paintEdgeShape`, so BPMN Conversation Link
  and Lean Mapping shipments never reached `VisioDocument::parse` as the
  open double-rail / filled thick arrow Draw paints. Capture now loads
  official `mxArrow` / `mxArrowConnector` (and `mxUtils.relativeCcw`)
  before sidebar factories. A second save keeps the rails and fill.
- draw.io named styles and swimlanes now stay native in LibreOffice. Capture
  dropped tokens without `=` (`swimlane;`, `ellipse;`, `rhombus;`) and
  painted `mxSwimlane` as a full rectangle, so BPMN lanes and UML ellipses
  never reached `VisioDocument::parse` as the title bar / oval Draw paints.
  Tokens now merge `styles/default.xml` like `mxStylesheet.getCellStyle`,
  and capture loads official `mxSwimlane.paintVertexShape` (startSize
  title, body, divider, collection ticks). A second save keeps the geometry.
- draw.io Internal Storage and Predefined Process now keep their inner
  rails in LibreOffice. Capture overrode `mxRectangleShape.paintVertexShape`
  with a sharp rectangle, so subclasses that only paint in `paintForeground`
  (T-dividers, process bars, plus) never reached `VisioDocument::parse`.
  Background now matches official rounded/sharp `paintBackground`, and a
  second save keeps the extra strokes.
- draw.io dashed vertices, clouds, cylinders and double ellipses now stay
  native in LibreOffice. Capture stubbed `configureCanvas` / `c.setDashed`,
  painted `shape=cloud` as an ellipse, stacked three overlapping cylinder
  fills, and drew actor subclasses as stick figures because `addPoints`
  was missing. LibreOffice only calls `VisioDocument::parse`, so Draw never
  saw those types. Style `dashed=1` is now LinePattern 2, `fillColor=none`
  drops the fill plate, `mxCylinder` is one body plus a lid stroke so
  evenodd cannot punch it, and parallelograms / steps use official
  `redrawPath`. A second save keeps the geometry.
- draw.io `triangle` / `hexagon` / `actor` now keep mxGraph direction in
  LibreOffice. Capture painted those primitives as diamonds or rectangles
  and stubbed `c.rotate` / `getShapeRotation`, so Bootstrap south chevrons
  and directed flowchart vertices never reached `VisioDocument::parse` as
  the contours Draw paints. Rotation is now baked into the path, matching
  `mxSvgCanvas2D.rotate` with y-down clockwise angles. A second save
  keeps the chevron.
- draw.io sidebar factories now keep terminals, relative offsets and
  cloned cells in LibreOffice. `addEntry` composites (UML interface
  lines, Property labels, Bootstrap button groups, BPMN choreographies)
  used `setTerminalPoint`, `mxGeometry.offset` and `sb.cloneCell`, which
  capture stubbed or never invoked, so Draw never saw those types through
  `VisioDocument::parse`. Edge templates with height 0 no longer inflate
  to a covering box, XML `as="offset"` and nested edges stay in the
  payload, `childLayout=stackLayout` is applied when every child sits at
  the origin, and only zero-arg palette roots run so `sb` stays bound.
  A second save keeps the geometry.
- draw.io table cells and electrical wires now stay in LibreOffice.
  `table` / `tableRow` painters call `getTitleSize` and `shape=wire`
  calls `createMarker`; capture had neither, so those types threw and
  Draw never saw them through `VisioDocument::parse`. The stubs match
  mxGraph (`startSize` title, polyline edge paint, empty table lines),
  dashed wires keep LinePattern 2, and a second save keeps the geometry.
- draw.io sidebar edges and mxStencil path ops now stay in LibreOffice.
  `createEdgeTemplateEntry` palettes (Arrows 2 wedge, IBM/ER connectors)
  were skipped as non-vertices, and Cisco Truck's cab crease is a
  `move`/`line` outside `<path>` that the decoder dropped. LibreOffice
  only calls `VisioDocument::parse`, so Draw never saw those types.
  Edges now paint via `paintEdgeShape` or a stroked polyline with baked
  heads, implicit path commands join the pending contour, and
  `<dashed>` becomes LinePattern 2. A second save keeps the geometry.
- draw.io compressed sidebar composites now capture native geometry
  for LibreOffice. `addDataEntry` palettes (mockup dialogs, UML
  activity partitions, GMDL sheets) store an mxGraphModel as
  inflateRaw+base64, and capture treated them as non-vertices.
  LibreOffice only calls `VisioDocument::parse`, so Draw never saw
  those types. The payload is inflated, cells are painted with the
  same JS/XML fallbacks, and cell labels become Text children. A
  second save keeps both.
- draw.io BPMN 2 tasks, SysML models and Android mockup bars now
  capture native geometry for LibreOffice. Capture loaded only
  `shapes/*.js` and had no `mxCellRenderer.getShape`, so
  `mxBpmnShape2.js` could not extend `mxgraph.basic.rect`, SysML
  `composite` had no `paintVertexShape`, and vertex-cell mockups
  that use built-in rectangles were dropped as empty. LibreOffice
  only calls `VisioDocument::parse`, so Draw never saw those types.
  Grapheditor `Shapes.js` now loads first, `getShape` is wired, and
  composite cells fall back to XML stencils or a rectangle. A second
  save keeps the geometry.
- Overlapping draw.io fills now stay solid in LibreOffice.
  Similar-sized blobs (CloudFront, duplicate AWS decorations) are
  still several `NoFill=0` Geometry rows after nested interiors are
  stroked, so libvisio `collectGeometry` / `_fillAndShadowProperties`
  (`svg:fill-rule=evenodd`) punched the intersections. Extra fills now
  move onto child shapes Draw paints separately. First-aid crosses and
  no-entry bars keep their evenodd cut-outs. Format fill/line still
  follow those children. A second save keeps the children.
- draw.io JavaScript Canvas shapes now keep `c.text` glyphs and nested
  mxStencil icons in LibreOffice. Capture used to ignore `canvas.text()`,
  treat `getStencil` as an external asset (dropping Kubernetes / Cisco /
  AWS product icons), and decode empty `<rect/>` as a 0×0 contour that
  overwrote the pending path. LibreOffice only calls
  `VisioDocument::parse`, so Draw never saw pin numbers or inlined icons.
  Nested XML stencils are now painted at capture time, authored strings
  stay on child shapes, and a second save keeps both.
- draw.io stencil `<text>` glyphs now stay visible in LibreOffice.
  mxGraph stencils (IEC AND/NAND labels, mockup calendars, instrument
  tags) paint those strings after a `fill` / `stroke`, but the decoder
  dropped every `<text>` node. LibreOffice only calls
  `VisioDocument::parse`, so Draw never saw the labels. Authored strings
  are now child shapes with `FillPattern=0` / `LinePattern=0`
  that libvisio still collects as Text. The palette title stays off the
  parent. A second save keeps the children.
- Isometric compute cubes now stay solid in LibreOffice.
  Three `NoFill=0` faces that share an L-junction became one evenodd
  path in libvisio `collectGeometry` / `_fillAndShadowProperties`
  (`svg:fill-rule=evenodd`), so Draw punched a diamond at the back-right
  join. EC2, GCP Compute Engine, Alibaba ECS, IBM Power VS and Oracle
  Compute Instance now use the same filled silhouette plus NoFill inner
  edges as the native Cube stencil. First-aid crosses and no-entry bars
  keep their evenodd cut-outs. A second save does not restore the extra
  fills.
- Nested glyphs on secondary tiles now stay solid in LibreOffice.
  libvisio `_fillAndShadowProperties` (`svg:fill-rule=evenodd`) concatenates
  every `NoFill=0` Geometry, so an interior that sits inside a *second*
  filled section (draw.io AWS/Veeam/infographic icons with several bodies)
  still punched a hole when baking only looked at the largest path. Nested
  and overlapping interiors are now stroked against every larger neighbour;
  isometric cube faces, chevrons and stacked drums stay filled. First-aid
  crosses and no-entry bars keep their evenodd cut-outs. A second save
  does not restore the extra fills.
- Pipeline chevrons, stacked cards and hex clusters now stay solid in
  LibreOffice. Adjacent `NoFill=0` tiles that overlapped even slightly
  became one evenodd path in libvisio `_fillAndShadowProperties` and
  punched the join in Draw. Those icons now share an edge (or a small
  gap) instead of overlapping; isometric cube faces stay filled. A
  second save keeps the spaced geometry.
- Overlapping stencil accessories now stay solid in LibreOffice.
  Lock shackles, inversion bubbles, switch port dots and magnifying-glass
  disks used `NoFill=0` that only partly overlapped the outer body, so
  libvisio `_fillAndShadowProperties` (`svg:fill-rule=evenodd`) punched
  the intersection as a hole in Draw. Nested-fill baking now strokes
  those smaller overlapping interiors as well as fully nested glyphs;
  isometric cube faces, chevrons and stacked database drums stay filled.
  UML module tabs and the printer output tray now share an edge with the
  body instead of overlapping it. Azure Blob stacked drums are spaced so
  their ellipse caps no longer evenodd-punch. A second save does not
  restore the extra fills. First-aid crosses and no-entry bars keep
  their evenodd cut-outs.
- Cloud architecture icons now keep a solid tile in LibreOffice.
  Nested inner glyphs (S3 lids, EKS pods, Azure VM screens, load-balancer
  nodes, …) used `NoFill=0` inside the outer body, so libvisio
  `_fillAndShadowProperties` (`svg:fill-rule=evenodd`) punched them as
  holes in Draw. A save and the stencil palette now stroke those nested
  interiors; isometric cube faces that sit side by side stay filled.
  First-aid crosses and no-entry bars keep their evenodd cut-outs. A
  second save does not restore the extra fills.
- EIP competing-consumer chevrons and dispatcher diamonds now stroke on
  a filled tile so Draw does not punch them as holes.
- EIP icons now keep a solid tile in LibreOffice.
  Message squares, arrows and inner glyphs used `NoFill=0` inside the
  outer box, so libvisio `_fillAndShadowProperties`
  (`svg:fill-rule=evenodd`) punched them as holes in Draw. Those details
  are now stroked on a filled tile; a second save does not restore the
  extra fills. Channel pipes, adapters and control-bus bodies stay
  filled.
- Network servers now keep a solid chassis in LibreOffice.
  A `NoFill=0` LED square inside the rack becomes one evenodd path in
  canvas, SVG and libvisio `_fillAndShadowProperties`
  (`svg:fill-rule=evenodd`), so Draw punched a window. The factory now
  fills the chassis and strokes the LED. A second save does not restore
  a filled LED.
- Network security cameras now keep a solid housing in LibreOffice.
  A `NoFill=0` lens ellipse inside the body becomes one evenodd path in
  canvas, SVG and libvisio `_fillAndShadowProperties`
  (`svg:fill-rule=evenodd`), so Draw punched an aperture. The factory
  now fills the housing and strokes the lens. A second save does not
  restore a filled lens.
- Network hubs now keep a solid disc in LibreOffice.
  Two `NoFill=0` ellipses become one evenodd path in canvas, SVG and
  libvisio `_fillAndShadowProperties` (`svg:fill-rule=evenodd`), so Draw
  punched the hub centre into a hole. The factory now fills the disc
  and strokes the inner circle. A second save does not restore two
  filled ellipses.
- Saving no longer deletes the original EMF / WMF / OLE media a LibreOffice
  bake replaced with a PNG. `documentForLibvisioWrite` still repoints the
  picture at a `ForeignType=Bitmap` preview so Draw does not fill Blue 2,
  but the writer records the source on `User.veLibvisioSourceImage` and
  keeps that part plus its page relationship. A second save and
  `images.findByPart` still replay the vector records; replaceImage and
  delete-picture still prune unused media. Canvas and SVG prefer the
  source when it is present. SVG keeps a multi-record BITBLT display list
  instead of flattening it to the wrapped DIB `rasterForRendering`
  would extract.
- Radiation signs now keep a solid centre disc in LibreOffice.
  Two `NoFill=0` ellipses become one evenodd path in canvas, SVG and
  libvisio `_fillAndShadowProperties` (`svg:fill-rule=evenodd`), so Draw
  punched the trefoil centre into a hole. The factory now fills the
  disc and strokes the inner circle. A second save does not restore two
  filled ellipses.
- Mockup toggles now keep a solid track in LibreOffice.
  A `NoFill=0` thumb inside a filled capsule becomes one evenodd path
  in canvas, SVG and libvisio `_fillAndShadowProperties`
  (`svg:fill-rule=evenodd`), so Draw punched a hole. The factory now
  fills the track and strokes the thumb. A second save does not restore
  a filled thumb.
- Floorplan plants now keep a solid foliage disc in LibreOffice.
  Two `NoFill=0` ellipses become one evenodd path in canvas, SVG and
  libvisio `_fillAndShadowProperties` (`svg:fill-rule=evenodd`), so Draw
  punched the pot into a hole. The factory now fills the foliage and
  strokes the inner disc. A second save does not restore two filled
  ellipses.
- Mockup progress bars now keep the filled portion in LibreOffice.
  Two `NoFill=0` rectangles become one evenodd path in canvas, SVG and
  libvisio `_fillAndShadowProperties` (`svg:fill-rule=evenodd`), so Draw
  punched the 55% overlap into an inverted empty track. The factory now
  strokes the full track and fills the progress. A second save does not
  restore two filled rectangles.
- Mockup radio buttons now keep the filled centre disc in LibreOffice.
  Two `NoFill=0` ellipses become one evenodd path in canvas, SVG and
  libvisio `_fillAndShadowProperties` (`svg:fill-rule=evenodd`), so Draw
  punched a ring. The factory now strokes the outer circle and fills
  the inner disc. A second save does not restore two filled ellipses.
- Floorplan beds now keep a solid mattress in LibreOffice.
  Two `NoFill=0` rectangles become one evenodd path in canvas, SVG and
  libvisio `_fillAndShadowProperties` (`svg:fill-rule=evenodd`), so Draw
  punched a pillow-shaped hole. The factory now fills the mattress and
  strokes the pillow. A second save does not restore two filled
  rectangles.
- BPMN terminate events now keep the filled inner disk in LibreOffice.
  Two `NoFill=0` ellipses become one evenodd path in canvas, SVG and
  libvisio `_fillAndShadowProperties` (`svg:fill-rule=evenodd`), so Draw
  punched a ring. The factory now strokes the outer circle and fills
  the inner disk. A second save does not restore two filled ellipses.
- Begin/EndArrow 35 now keeps the filled circle-plus-bar in LibreOffice.
  `_linePropertiesMarkerPath` case 35 starts at `m-106-318` inside default
  viewBox `0 0 20 30` and closes extra plus-arms, so Draw painted the
  same terminator circle as id 42 instead of canvas
  `_filledCircleWithBars(1)`. A save bakes that Geometry ribbon
  (Height=0 1-D would clip a filled polygon) and drops the native
  marker. Id 42 stays native. A second save does not restack.
- Begin/EndArrow 5 now keeps the filled stealth head in LibreOffice.
  `_linePropertiesMarkerPath` case 5 is `m10 0-10 20q10,-5 20,0z` inside
  viewBox `0 0 20 20`, so Draw painted a near-equilateral filled
  triangle (centerline solid like id 4) instead of canvas `_stealth`.
  A save bakes that Geometry ribbon (Height=0 1-D would clip a filled
  polygon) and drops the native marker. Id 4 stays native. A second
  save does not restack.
- Begin/EndArrow 17 now keeps the open stealth head in LibreOffice.
  `_linePropertiesMarkerPath` case 17 is the holed concave
  `m100 0-100 200q100-50 200 0z` inside viewBox `0 0 200 200`, so
  Draw stroked a hollow triangle with a quadratic base bar instead
  of canvas `_stealthOpen`. A save bakes that Geometry ribbon and
  drops the native marker. Id 16 stays native. A second save does
  not restack.
- Begin/EndArrow 6 now keeps the filled swept head in LibreOffice.
  `_linePropertiesMarkerPath` case 6 is `m10 0-10 20q10,5 20,0z` inside
  viewBox `0 0 20 20`, so Draw painted a fat filled triangle instead of
  canvas `_filledArrowSwept`. A save bakes that Geometry ribbon
  (Height=0 1-D would clip a filled polygon) and drops the native
  marker. Id 4 stays native. A second save does not restack.
- Begin/EndArrow 18 now keeps the open swept head in LibreOffice.
  `_linePropertiesMarkerPath` case 18 is the holed convex
  `m20 0-20 40q…z` inside viewBox `0 0 20 20`, so Draw clipped the
  quadratic bulge onto unfilled 16. Canvas / SVG already stroke 12's
  open sweep. A save bakes that Geometry ribbon and drops the native
  marker. Id 16 stays native. A second save does not restack.
- Begin/EndArrow 13 now keeps the filled spear in LibreOffice.
  `_linePropertiesMarkerPath` case 13 is `m10 0-10 30h20z` inside
  viewBox `0 0 20 30`, but Draw scales that taller box into the same
  marker slot as filled 4, so the long triangle collapsed. Canvas /
  SVG already fill a 1.4-reach spear. A save bakes that Geometry
  ribbon (Height=0 1-D would clip a filled polygon) and drops the
  native marker. Id 4 stays native. A second save does not restack.
- Begin/EndArrow 15 now keeps the open narrow triangle in LibreOffice.
  `_linePropertiesMarkerPath` case 15 is the holed sibling of 2's
  `m10 0-10 10h20z` triangle inside viewBox `0 0 20 10`, so Draw
  painted it almost as wide as unfilled 16. Canvas / SVG already
  stroke a narrow head. A save bakes that Geometry ribbon and drops
  the native marker. Id 16 stays native. A second save does not
  restack.
- Begin/EndArrow 2 now keeps the filled narrow triangle in LibreOffice.
  `_linePropertiesMarkerPath` case 2 is the same `m10 0-10 10h20z`
  triangle as unfilled 15 inside viewBox `0 0 20 10`, so Draw painted
  it almost as wide as filled 4. Canvas / SVG already fill a narrow
  head. A save bakes that Geometry ribbon (Height=0 1-D would clip a
  filled polygon) and drops the native marker. Id 4 stays native. A
  second save does not restack.
- Begin/EndArrow 14 now keeps the wide overflow triangle in LibreOffice.
  `_linePropertiesMarkerViewbox` case 14 is `110 200 200 300` while
  `_linePropertiesMarkerPath` starts at `m100 0`, so Draw painted the
  same holed triangle as id 16. Canvas / SVG already stroke a wide
  overflow head (`overflow=visible`). A save bakes that Geometry ribbon
  and drops the native marker. Id 16 stays native. A second save does
  not restack.
- Begin/EndArrow 30 now keeps optional-one in LibreOffice.
  `_linePropertiesMarkerPath` case 30 adds filled plus-arms around a
  holed circle, so Draw painted a circle-plus while canvas / SVG
  already stroke an open circle and a single hash. A save bakes that
  Geometry ribbon and drops the native marker. A second save does not
  restack.
- Begin/EndArrow 29 now keeps optional-many crow-foot in LibreOffice.
  `_linePropertiesMarkerPath` case 29 appends 27's filled triangle to a
  holed circle, so Draw painted a solid arrow while canvas / SVG
  already stroke an open circle plus three lines past the endpoint. A
  save bakes that Geometry ribbon and drops the native marker. A
  second save does not restack.
- Begin/EndArrow 28 now keeps crow-foot-plus-one in LibreOffice.
  `_linePropertiesMarkerPath` case 28 prepends a filled bar to 27's
  inverted triangle, so Draw painted a solid arrow while canvas / SVG
  already stroke three lines plus a “one” hash past the endpoint. A
  save bakes that Geometry ribbon and drops the native marker. A
  second save does not restack.
- Begin/EndArrow 27 now keeps the open crow-foot in LibreOffice.
  `_linePropertiesMarkerPath` case 27 is labelled Copied from LO but
  closes a filled inverted triangle, so Draw painted a solid arrow
  while canvas / SVG already stroke three lines past the endpoint. A
  save bakes that Geometry ribbon and drops the native marker. A
  second save does not restack.
- Begin/EndArrow 25 now keeps two Chen ER hashes in LibreOffice.
  `_linePropertiesMarkerPath` case 25 copies 24's plus and adds another
  along-line pair, so Draw painted a double plus while canvas / SVG
  already stroke two hashes. A save bakes that Geometry ribbon and
  drops the native marker. A second save does not restack.
- Begin/EndArrow 24 now keeps the Chen ER “one” hash in LibreOffice.
  `_linePropertiesMarkerPath` case 24 closes a perpendicular bar plus
  two bars along the carrier, so Draw painted a plus while canvas /
  SVG already stroke a single hash. A save bakes that Geometry ribbon
  and drops the native marker. Id 25 stays native. A second save does
  not restack.
- Begin/EndArrow 23 now keeps the open backslash tick in LibreOffice.
  `_linePropertiesMarkerPath` case 23 closes a filled parallelogram
  (`…z`) plus a stem, so Draw painted a solid blob while canvas / SVG
  already stroke an open oblique plus centred stem. A save bakes that
  Geometry ribbon and drops the native marker. A second save does not
  restack.
- Begin/EndArrow 9 now keeps the architectural dimension tick in
  LibreOffice. `_linePropertiesMarkerPath` case 9 closes a filled
  parallelogram (`…z`) inside viewBox `0 0 20 10` while the path runs
  to ~y=23, so Draw painted a short filled blob while canvas / SVG
  already stroke an open overflow tick (`overflow=visible`). A save
  bakes that Geometry ribbon and drops the native marker. A second
  save does not restack.
- Begin/EndArrow 8 now keeps the filled sweep in LibreOffice.
  `_linePropertiesMarkerPath` case 8 is labelled filled but the SVG
  path has no `z`, so Draw painted a smaller head while canvas / SVG
  already alias 8 to id 6's closed sweep. A save bakes that Geometry
  and drops the native marker. Factory 1-D Height=0 would clip a
  filled polygon to the XForm box, so the head expands to a
  LineWeight ribbon like open ids. Id 6 stays native. A second save
  does not restack.
- Begin/EndArrow 1, 3 and 12 now keep open heads in LibreOffice.
  `_linePropertiesMarkerPath` labels them Open but closes the SVG
  with `z` and no hole, so Draw filled a solid triangle while canvas
  / SVG already stroke a hollow short head, an open V, and a swept
  open head. A save bakes those Geometry ribbons and drops the native
  marker. Ids 16 / 18 stay native (they already cut a hole). A second
  save does not restack.
- Begin/EndArrow 19 now keeps an open chevron in LibreOffice.
  `_linePropertiesMarkerPath` case 19 is labelled complete Unfilled
  but emits the same quadratic as TODO Open 7, so Draw painted a
  hollow curve while canvas / SVG already stroke both ids as a V.
  A save bakes that Geometry ribbon and drops the native marker.
  A second save does not restack.
- Begin/EndArrow 7 now keeps an open chevron in LibreOffice.
  `_linePropertiesMarkerPath` case 7 is still `TODO Open` and emits
  id 19's unfilled quadratic, so Draw painted a hollow curved arrow
  while canvas / SVG already stroke a V. A save bakes that Geometry
  ribbon and drops the native marker. A second save does not restack.
- Width=0 1-D LineGradient / LineColorTrans now keeps stroke thickness in
  LibreOffice. Factory `line` uses Width=ΔX, Height=ΔY, Angle=0, so a
  vertical connector has Width=0. Draw clips the 25–40 / FillForegndTrans
  ribbon to that XForm box and the wash collapsed to a hairline (solid
  LineWeight still drew). Canvas / SVG already paint the ribbon AABB.
  A save bakes that PNG. Horizontal Height=0 1-D (Visio's usual box)
  stays a ribbon. A second save does not restack.
- Rotated two-stop LineGradient now keeps its local wash in LibreOffice.
  An unfilled LineGradient becomes a FillPattern 25–40 ribbon, and
  Draw's `draw:angle` is page-space, so a 90° wide bar kept a vertical
  mag strip down the whole stroke while canvas / SVG already rotate
  the AABB wash. A save bakes that PNG. Axis-aligned unflipped two-stop
  LineGradient stays a 25–40 ribbon. A second save does not restack.
- Rotated hatch / classic 25–40 fills now keep their local wash in
  LibreOffice. `_fillAndShadowProperties` hatch `draw:rotation` and
  gradient `draw:angle` are page-space, so a 90° FillPattern 6 box
  kept horizontal lines and FillPattern 25 kept a vertical mag strip
  while canvas / SVG already rotate the wash. A save bakes that PNG.
  Axis-aligned unflipped 2–24 / 25–34 / 40 and solid FillPattern 1
  stay native. A second save does not restack.
- Hatch FillBkgndTrans now keeps opaque strokes in LibreOffice.
  `_fillAndShadowProperties` hatch-solid uses
  `draw:opacity = 1 - max(fg,bg)`, so a faded FillBkgnd with opaque
  hatch lines still faded the strokes (magenta became pink on white).
  Canvas / SVG only fade the gaps. A save freezes FillBkgnd toward
  white (and composites strokes over that gap) with Trans=0. Hollow
  (`FillBkgndTrans=1`) and fully opaque hatches stay native. A second
  save does not restack.
- FillGradient / LineGradient stop **positions** now keep their authored
  inset in LibreOffice. FillPattern 25–40 interpolates two colours across
  the whole box (axial 26 / 29 always peaks at the centre); `FillGradient`
  `Position` is not a token, so 0.25→0.75 and an off-centre three-stop
  peak snapped to 0→1 / 0.5 while canvas / SVG already paint the stops.
  A save bakes that PNG. Edge-to-edge 25–34 and centred 26 / 29 stay
  native. A second save does not restack.
- Off-axis linear FillGradient / LineGradient now keep their authored
  angle in LibreOffice. `_fillAndShadowProperties` only emits ODF axial
  at `draw:angle` 0 / 90 (FillPattern 29 / 26) and eight linear compass
  points (25 / 27 / 28 / 30–34); `FillGradientAngle` is not a token, so
  a 45° white–colour–white wash became a horizontal axial and a 15°
  two-stop ramp snapped to 0°. Canvas / SVG already paint the angle.
  A save bakes that PNG. On-compass 25–34 and axis-aligned 26 / 29 stay
  native. A second save does not restack.
- Path `FillGradientDir` 13 now fills concentric similar copies of the
  geometry, matching Visio. `_fillAndShadowProperties` has no ODF path
  style, so the classic fallback was FillPattern 40 (a circle) and
  canvas / SVG used the same radial disc — a wide box washed its short
  sides first. Sampling, SoftEdges PNG plates, canvas clip-fill and SVG
  stacked scaled `<path>`s now follow the outline (Chebyshev on a
  rectangle, similar ellipses on an ellipse). A save bakes that plate
  for LibreOffice. Centre radial 40 stays native. A second save does
  not restack.
- Three-stop linear FillGradient / LineGradient whose ends match
  (BG–FG–BG) now writes FillPattern 26 / 29 with the **middle** stop as
  FillForegnd, matching libvisio's ODF `draw:style=axial` (start-color
  at the centre). Using the first/last stops made a white–colour–white
  wash or stroke ribbon an all-white axial in Draw. Canvas / SVG already
  paint the three-stop linear. A three-stop linear whose ends differ
  still bakes a PNG.
- Centre rectangular FillPattern 35 / `FillGradientDir` 10 now keeps
  Visio Chebyshev isolines in LibreOffice. Canvas / SVG already hit
  t=1 on all four sides of a wide box; Draw's
  `getRectangularGradientAlpha` limo-stretches the long axis
  (`fAbsX = (fAbsX-1)*aspect+1`), so native ODF rectangular kept the
  start colour along that edge. A save bakes the Chebyshev PNG.
  Linear 25–34 and centre radial 40 stay native. A second save does
  not restack.
- FillGradientDir 8/9/11/12 rectangular fills now keep their MS-VSDX
  corner origin, matching Visio. `radialGradientOrigin` treated 8–12
  as centre (only FillPattern 35 / dir 10 is centre); dirs 1–7 now
  follow MS-VSDX 2.4.4.122 (classic 36–40 remap onto 7/6/2/1/3 so
  ODF 36 stays top-left). `_fillAndShadowProperties` still emits
  FillPattern 35 with `svg:cx/cy=0.5`, so a save bakes the Chebyshev
  plate for 8/9/11/12 (and radial edge dirs 4/5). Centre 40 stays
  native; centre 35 bakes as above. A second save does not restack.
- FillPattern 35 / rectangular FillGradient now paints concentric
  rectangles, matching Visio. `_fillAndShadowProperties` emits
  ODF `draw:style=rectangular` (`svg:cx/cy` at the box centre for id
  35); canvas / SVG used a radial disc (`ui.Gradient.radial` + clamp)
  so a wide box washed its short sides first. Sampling, SoftEdges PNG
  plates, canvas clip-fill and SVG stacked `<rect>` patterns now use
  Chebyshev isolines (mid-side and corner of a concentric rectangle
  share a colour). Draw then limo-stretches that metric, so a save
  bakes the plate (see above). Radial 36–40 and linear 25–34 stay
  discs / ramps.
- Corner radial LineGradient now strokes the full path in LibreOffice.
  Two-colour washes become a filled ribbon whose FillPattern 36–39
  `_fillAndShadowProperties` clips to an ODF circle (`svg:cx/cy` at a
  corner), so Draw kept only a disc of a long bar while canvas / SVG
  stroke the whole path with `ui.Gradient.radial` + clamp. A save bakes
  the same SoftEdges stroke PNG at sigma 0 (dirs 1/2/3/5/6/7; 1-D uses
  a 2-D plate). Linear two-colour LineGradient and centre radial 40 stay
  a 25–40 ribbon. Leftover Geometry is NoLine so a second save does not
  restack.
- Corner radial FillPattern 36–39 now fills the shape in LibreOffice.
  `_fillAndShadowProperties` emits ODF `draw:style=radial` with
  `svg:cx/cy` at a corner, so Draw paints a circle and leaves the rest
  of a wide box empty, while canvas / SVG fill the whole path with
  `ui.Gradient.radial` + clamp. A save bakes the same SoftEdges fill
  PNG at sigma 0 (modern radial/path dirs 1/2/3/5/6/7 too — 25–40
  would collapse 2/6 to centre 40). Linear 25–34 and centre 40 stay
  native. Leftover Geometry is NoFill so a second save does not
  restack.
- Character Letterspace now survives a save into LibreOffice as tracking,
  not glyph stretch. The cell is not a token, and FontScale is a true
  `style:text-scale` width scale, so folding extra advance into FontScale
  made Draw (and a reopen here) widen every letter. A save with positive
  tracking inserts U+00A0 Character runs whose FontScale is that gap
  over Arial's ~0.25 em NBSP (same Size as the body so line height
  stays put), zeros Letterspace, and keeps authored FontScale on the
  glyphs. Negative tracking still folds into FontScale — spacers cannot
  condense. A second save does not restack.
- Character FontScale now paints as a true glyph width scale, matching
  LibreOffice. libvisio's `readCharIX` collects `XML_FONTSCALE` as
  `scaleWidth` and `_fillCharacterProperties` emits `style:text-scale`
  (`RVNG_PERCENT`) without changing `fo:font-size`. Canvas and SVG used
  to approximate that with letter-spacing, so condensed/expanded runs
  kept their cap height but not their glyph width (identical ink at
  0.5× and 2×). SVG now wraps the line in `scale(sx,1)` about the
  HorzAlign anchor; canvas applies the same `canvas.scale` at paint
  after laying out unscaled glyphs. Letterspace stays tracking — Draw
  ignores that cell, so a save inserts NBSP spacers instead of folding
  it into FontScale. Tab fields that already sit at visual x use
  `textLength` / `spacingAndGlyphs`. A second save does not restack.
- 1-D CubBezTo / QuadBezTo bows now keep their curve in LibreOffice.
  `tokens.txt` has no CubBezTo / QuadBezTo, so a save used Rel* fractions.
  RelY × Height is 0 on a horizontal 1-D XForm, and Draw painted a chord
  while canvas / SVG already stroked the cubic in local inches. A save
  samples LineTo when Width or Height is degenerate. Non-degenerate 2-D
  CubBezTo still writes RelCubBezTo. A second save does not resample
  the polyline.
- Hatch FillForegndTrans now keeps faded strokes in LibreOffice.
  `_fillAndShadowProperties` maps FillPattern 2–24 to `draw:fill=hatch`:
  FillBkgndTrans=1 drops `draw:opacity` so lines stay hard, and a solid
  background emits one opacity from `max(fg,bg)` that fades the whole
  box. Canvas / SVG only fade the hatch lines. A save freezes those
  cells into FillForegnd / FillBkgnd (toward the hatch background, or
  white when the background is fully transparent) and writes Trans=0.
  Opaque hatches stay native. A second save does not restack.
- Geometry-less glueable connectors now keep their auto-route in
  LibreOffice. libvisio only emits a stroke when Geometry filled
  `m_currentFillGeometry`, so a Begin–End 1-D XForm with no rows stayed
  blank in Draw while canvas / SVG already painted
  `autoRoutedConnectorPolyline`. A save writes that same elbow as
  MoveTo/LineTo. Authored Geometry and master instances stay native. A
  second save does not restack another route.
- Sketch jiggle strokes now keep custom dashes, Flow Animation dashes,
  and LinePattern gaps on a later ribbon in LibreOffice.
  `_lineProperties` only dashes ids 2–23, leftover Geometry is already
  NoLine, and those flattens skipped every bake plate, so Draw snapped
  `veDashPattern` onto the nearest built-in, stroked Flow Animation
  solid, or filled a LineColorTrans ribbon without gaps. A save copies
  the dash / Flow rows onto each jiggle and runs the same MoveTo/LineTo
  flatten unfilled strokes already use. A second save does not restroke
  the already-dashed copies.
- Sketch jiggle strokes now keep high-miter spikes and round-cap
  miters in LibreOffice. `_lineProperties` maps join from LineCap
  only and never emits `svg:stroke-miterlimit`, leftover Geometry is
  already NoLine, and both the round-cap flatten and the filled
  ribbon skipped every bake plate, so Draw round-joined 90° elbows
  and bevelled ratio>4 spikes. A save runs those rewrites on each
  jiggle. Straight 1-D copies have no elbow and stay native. A
  second save does not stack another ribbon.
- Sketch jiggle strokes now keep SoftEdges in LibreOffice. SoftEdgesSize
  is not a token, leftover Geometry is already NoLine, and SoftEdges
  bake skipped every bake plate unless the jiggle carried a three-colour
  LineGradient, so Draw kept a hard stroke. A save bakes each jiggle
  into the same stroke PNG unfilled SoftEdges already use. Opaque
  Foreign PNGs sit under both leftovers. 1-D Sketch copies stay
  Height=0 and skip, matching canvas. A second save does not stack
  another plate.
- Sketch jiggle strokes now keep Glow and Reflection in LibreOffice.
  Glow* / Reflection* are not tokens, Sketch copies used to drop those
  cells, leftover Geometry is already NoLine, and Glow / Reflection
  bake skipped every bake plate, so the halo and mirror vanished. A
  save copies the live effect onto each jiggle and bakes the same
  stroke PNG unfilled paths already use, including 1-D copies whose
  Foreign plate is sized to the ribbon AABB. Opaque Foreign PNGs sit
  under both jiggle strokes so the second pass cannot cover the first.
  A second save does not stack another plate.
- Sketch jiggle strokes that carry a LineGradient with more than two
  unique opaque colours now keep those stops in LibreOffice. The two
  locked siblings used to copy the live wash, and SoftEdges skipped
  every bake plate, so FillPattern 25–40 dropped the middle colour.
  A save bakes each jiggle into the same stroke PNG unfilled washes
  already use. Two-colour Sketch strokes stay a filled ribbon. A
  second save does not stack another plate.
- LineGradient PNG hard shadows now follow page `ShdwObliqueAngle` in
  LibreOffice. `ShdwObliqueAngle` is not a token, and factory rectangles
  keep Geometry NoFill=0 even when unfilled, so the sheared silhouette
  used to be a solid parallelogram. A save shears the stroke ring
  about LocPin instead, including 1-D washes on a 2-D AABB plate.
- 1-D LineGradient washes with more than two unique opaque colours now
  keep a hard drop shadow in LibreOffice. SoftEdges already baked a
  2-D Foreign PNG of the stroke, but shadow bake skipped `XForm1D`.
  libvisio's `_flushCurrentForeignData` emits an empty graphic style,
  so Draw's `draw:shadow` never lands on that plate. A save bakes the
  stroke-ring silhouette on a 2-D plate sized to the ribbon AABB.
  Two-colour 1-D washes stay a filled ribbon. A second save does not
  stack another plate.
- Unfilled LineGradient washes with more than two unique opaque colours
  now keep a hard drop shadow in LibreOffice. SoftEdges used to drop
  the stroke onto a Foreign PNG while `ShdwPattern` stayed on the
  hollow leftover. libvisio's `_flushCurrentForeignData` emits an
  empty graphic style, so Draw's `draw:shadow` never lands on that
  plate. A save bakes the stroke-ring silhouette PNG ShadowBlur uses,
  at sigma 0. Two-colour washes stay a filled 25–40 ribbon plus
  native `draw:shadow`. A second save does not stack another plate.
- FillGradient / LineGradient washes with a fully transparent stop now
  keep that hole in LibreOffice. FillPattern 25–40 would skip the
  invisible colour and stretch the remaining opaque stops from the box
  edge. A save bakes the same SoftEdges PNG per-stop alpha already
  uses. Opaque two-colour washes stay 25–40. A second save does not
  stack another plate.
- Two-colour FillGradient / LineGradient washes with per-stop or cell
  transparency now keep that fade in LibreOffice. FillPattern 25–40
  drop `draw:opacity` and Draw ignores `librevenge:start-opacity` /
  `end-opacity`, so those washes used to paint fully opaque. A save
  bakes the same SoftEdges PNG three-colour washes already use.
  Opaque two-colour washes stay 25–40. A second save does not stack
  another plate.
- Foreign pictures with a hard drop shadow now keep that shadow in
  LibreOffice. libvisio's `_flushCurrentForeignData` emits an empty
  graphic style, so Draw's `draw:shadow` never lands on the bitmap —
  the same reason ShadowBlur already became a silhouette PNG. A save
  bakes that image-frame silhouette at sigma 0. A second save does
  not stack another plate.
- FillGradient washes with more than two unique opaque colours now keep
  a hard drop shadow in LibreOffice. SoftEdges used to drop the fill
  onto a Foreign PNG while `ShdwPattern` stayed on the hollow leftover.
  libvisio's `_flushCurrentForeignData` emits an empty graphic style, so
  Draw's `draw:shadow` never lands on that plate. A save bakes the same
  silhouette PNG ShadowBlur uses, at sigma 0. Two-colour washes stay
  native 25–40 plus `draw:shadow`. A second save does not stack another
  plate.
- FillGradient washes with more than two unique opaque colours now keep
  those stops in the Reflection mirror in LibreOffice. A filled 2-D
  sibling used to copy the live FillGradient, and `fillForLibvisioWrite`
  collapsed it to classic FillPattern 26/29 (FillForegnd / FillBkgnd
  only). A save flips, clips and fades the same SoftEdges fill PNG
  canvas already paints. Two-colour washes stay 25–40. A second save
  does not stack another plate.
- FillGradient washes with more than two unique opaque colours plus
  CompoundType 2–4 now keep the fill in LibreOffice. SoftEdges used to
  drop FillPattern while Geometry still said NoFill=0, so the unfilled
  thick-thin ribbon path filled that leftover body with LineColor and
  covered the PNG plate. A save marks those sections NoFill so Draw
  paints only the rails and the plate shows through. Two-colour washes
  stay 25–40. A second save does not stack another plate.
- FillGradient + LineGradient washes with more than two unique opaque
  colours on a compound even-odd fill now keep the hole in LibreOffice.
  A save that baked both into one SoftEdges PNG classified the outer
  Width×Height box as a rectangle and filled the interior, while
  libvisio concatenates every `NoFill=0` Geometry with
  `svg:fill-rule=evenodd`. The plate now even-odd-fills every fillable
  ring and strokes both paths. Two-colour washes stay 25–40. A second
  save does not stack another plate.
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
