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
- Page `PageColor` now survives a save into LibreOffice. The cell is not a
  token (`readPageSheetProperties` only stores size, scale, and
  `ShdwOffset*`), so a save prepends a locked full-page plate Draw can
  fill. Clearing the page colour drops that plate. Canvas and SVG already
  painted the sheet.
- Shape `Reflection*` now survives a save into LibreOffice. Those cells
  are not tokens, so a filled 2-D shape bakes a locked sibling plate
  (`FillForegndTrans` is collected) clipped by `ReflectionSize`, then
  `ReflectionSize` is written 0. Canvas and SVG already painted the
  mirror.
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
  an unfilled stroke bakes a `FillForegndTrans` ribbon, a filled NoLine
  shape bakes a `LineWeight` halo, and a filled shape that already paints
  a stroke bakes a locked sibling halo (`LibvisioGlow.{id}`) so the
  outline keeps CompoundType / dashes, then `GlowSize` is written 0.
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
