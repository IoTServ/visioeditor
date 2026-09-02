/// Default fill/stroke palettes for the stencil library (draw.io-like).
///
/// Applied when a [Stencil] is dropped or clicked into the canvas so new shapes
/// are not plain white/black. Explicit user memo styles in the editor still win.
library;

import 'model/shape.dart';
import 'model/line.dart';
import 'utils/color.dart';

/// A fill + stroke pair (hex `#RRGGBB` or `#AARRGGBB`).
class StencilColors {
  const StencilColors(this.fill, this.stroke);
  final String fill;
  final String stroke;
}

/// draw.io default palette slots.
const StencilColors kStencilPrimary = StencilColors('#DAE8FC', '#6C8EBF');
const StencilColors kStencilSuccess = StencilColors('#D5E8D4', '#82B366');
const StencilColors kStencilWarning = StencilColors('#FFF2CC', '#D6B656');
const StencilColors kStencilAccent = StencilColors('#FFE6CC', '#D79B00');
const StencilColors kStencilDanger = StencilColors('#F8CECC', '#B85450');
const StencilColors kStencilNeutral = StencilColors('#F5F5F5', '#666666');
const StencilColors kStencilSecondary = StencilColors('#E1D5E7', '#9673A6');
const StencilColors kStencilContainer = StencilColors('#F5F5F5', '#6C8EBF');
const StencilColors kStencilTeal = StencilColors('#D5F5F0', '#2E8B7A');
const StencilColors kStencilPink = StencilColors('#FCE4EC', '#C2185B');
const StencilColors kStencilSky = StencilColors('#E3F2FD', '#5B9BD5');

/// Soft brand-ish colours for cloud / vendor libraries.
const StencilColors kStencilAws = StencilColors('#FFF8E7', '#D9822B');
const StencilColors kStencilAzure = StencilColors('#E3F2FD', '#1565C0');
const StencilColors kStencilGcp = StencilColors('#E8F0FE', '#1A73E8');
const StencilColors kStencilCisco = StencilColors('#E0F7FA', '#049FD9');
const StencilColors kStencilAlibaba = StencilColors('#FFF3E0', '#FF6A00');
const StencilColors kStencilIbm = StencilColors('#EDF5FF', '#0F62FE');
const StencilColors kStencilOracle = StencilColors('#FCE8E6', '#C74634');

/// Group → default colours. Unknown groups fall back to [kStencilPrimary].
const Map<String, StencilColors> kStencilGroupColors = <String, StencilColors>{
  'General': kStencilPrimary,
  'Flowchart': kStencilPrimary,
  'Arrows': kStencilPrimary,
  'Basic': kStencilPrimary,
  'Containers': kStencilContainer,
  'UML': kStencilSecondary,
  'ER': kStencilSuccess,
  'BPMN': kStencilAccent,
  'Misc': kStencilNeutral,
  'Advanced': kStencilSecondary,
  'Network': StencilColors('#E6F2FF', '#3B7DD8'),
  'Mockup': StencilColors('#ECEFF1', '#546E7A'),
  'Electrical': StencilColors('#FFFDE7', '#F9A825'),
  'Signs': kStencilDanger,
  'Floorplan': StencilColors('#EFEBE9', '#6D4C41'),
  'EIP': StencilColors('#E8F5E9', '#43A047'),
  'Charts': kStencilSky,
  'AWS': kStencilAws,
  'Azure': kStencilAzure,
  'GCP': kStencilGcp,
  'Cisco': kStencilCisco,
  'Alibaba': kStencilAlibaba,
  'IBM': kStencilIbm,
  'Oracle': kStencilOracle,
};

/// Exact-name overrides (highest priority after explicit [Stencil.colors]).
const Map<String, StencilColors> kStencilNameColors = <String, StencilColors>{
  // --- Flowchart ---
  'Decision': kStencilWarning,
  'Terminator': kStencilSuccess,
  'Start': kStencilSuccess,
  'Data': kStencilAccent,
  'Document': kStencilSecondary,
  'Multi-Document': kStencilSecondary,
  'Manual Input': kStencilAccent,
  'Manual Operation': kStencilAccent,
  'Preparation': kStencilSecondary,
  'Delay': kStencilWarning,
  'Display': kStencilPrimary,
  'Database': kStencilSuccess,
  'Direct Data': kStencilSuccess,
  'Stored Data': kStencilSuccess,
  'Sequential Data': kStencilSuccess,
  'Internal Storage': kStencilSuccess,
  'Tape': kStencilAccent,
  'Tape Data': kStencilAccent,
  'Merge': kStencilWarning,
  'Extract': kStencilWarning,
  'Collate': kStencilNeutral,
  'Sort': kStencilNeutral,
  'Or': kStencilNeutral,
  'And': kStencilNeutral,
  'Sum': kStencilNeutral,
  'Summing Junction': kStencilNeutral,
  'Loop Limit': kStencilWarning,
  'Off-Page Ref': kStencilNeutral,
  'Off Page Connector': kStencilNeutral,
  'On-Page Ref': kStencilNeutral,
  'Annotation': kStencilWarning,
  'Card': kStencilAccent,
  'Step': kStencilPrimary,
  'Transfer': kStencilPrimary,
  'Predefined Process': kStencilPrimary,
  'Parallel Mode': kStencilSecondary,
  'Process': kStencilPrimary,
  'Process Bar': kStencilPrimary,

  // --- General / Basic / Containers ---
  'Diamond': kStencilWarning,
  'Cylinder': kStencilSuccess,
  'Cylinder Stack': kStencilSuccess,
  'Cloud': kStencilSky,
  'Cloud Rectangle': kStencilSky,
  'Note': kStencilWarning,
  'Actor': kStencilNeutral,
  'User': kStencilNeutral,
  'Data Storage': kStencilSuccess,
  'Data Store': kStencilSuccess,
  'Container': kStencilContainer,
  'Horizontal Container': kStencilContainer,
  'List': kStencilContainer,
  'List Item': kStencilContainer,
  'Vertical List': kStencilContainer,
  'Table': kStencilContainer,
  'Table 2×2': kStencilContainer,
  'Callout': kStencilWarning,
  'Oval Callout': kStencilWarning,
  'Rectangular Callout': kStencilWarning,
  'Rounded Rectangular Callout': kStencilWarning,
  'Loud Callout': kStencilAccent,
  'Cloud Callout': kStencilSky,
  'Cube': kStencilTeal,
  'Isometric Cube': kStencilTeal,
  'Isometric Square': kStencilTeal,
  'Parallelepiped': kStencilTeal,
  'Layered Rectangle': kStencilContainer,
  'Double Rectangle': kStencilPrimary,
  'Double Rounded Rectangle': kStencilPrimary,
  'Double Ellipse': kStencilPrimary,
  'Double Square': kStencilPrimary,
  'Double Circle': kStencilPrimary,
  'Frame': kStencilNeutral,
  'Frame Corner': kStencilNeutral,
  'No Symbol': kStencilDanger,
  'Star': kStencilWarning,
  '4 Point Star': kStencilWarning,
  '6 Point Star': kStencilWarning,
  '8 Point Star': kStencilWarning,
  'Heart': kStencilPink,
  'Lightning': kStencilWarning,
  'Flash': kStencilWarning,
  'Sun': kStencilAccent,
  'Moon': kStencilSecondary,
  'Drop': kStencilSky,
  'Wave': kStencilSky,
  'Banner': kStencilAccent,
  'Pyramid': kStencilAccent,
  'Cone': kStencilAccent,
  'Pie': kStencilSecondary,
  'Donut': kStencilSecondary,
  'Smiley': kStencilSuccess,
  'Neutral Smiley': kStencilWarning,
  'Sad Smiley': kStencilDanger,
  'Tick': kStencilSuccess,
  'X': kStencilDanger,
  'Cross': kStencilDanger,
  'Plaque': kStencilSecondary,
  'Corner': kStencilNeutral,
  'Tee': kStencilNeutral,
  'Switch': kStencilWarning,

  // --- UML ---
  'Use Case': kStencilSuccess,
  'Class': kStencilPrimary,
  'Object': kStencilPrimary,
  'Block': kStencilPrimary,
  'Interface': kStencilSecondary,
  'Provided Interface': kStencilSuccess,
  'Required Interface': kStencilAccent,
  'Package': kStencilSecondary,
  'Module': kStencilSecondary,
  'Component': kStencilTeal,
  'Boundary': kStencilSky,
  'Control': kStencilAccent,
  'Entity': kStencilSuccess,
  'Node': kStencilTeal,
  'Lifeline': kStencilNeutral,
  'Actor Lifeline': kStencilNeutral,
  'Boundary Lifeline': kStencilSky,
  'Entity Lifeline': kStencilSuccess,
  'Control Lifeline': kStencilAccent,
  'Activation Bar': kStencilPrimary,
  'Destruction': kStencilDanger,
  'Fork / Join': kStencilWarning,
  'End': kStencilDanger,

  // --- ER ---
  'Entity (Rounded)': kStencilSuccess,
  'Weak Entity': kStencilWarning,
  'Attribute': kStencilSky,
  'Key Attribute': kStencilAccent,
  'Weak Key Attribute': kStencilWarning,
  'Multivalue Attribute': kStencilSecondary,
  'Derived Attribute': kStencilNeutral,
  'Relationship': kStencilPrimary,
  'Identifying Relationship': kStencilWarning,
  'Associative Entity': kStencilTeal,

  // --- BPMN ---
  'Task': kStencilPrimary,
  'User Task': kStencilPrimary,
  'Service Task': kStencilPrimary,
  'Script Task': kStencilSecondary,
  'Manual Task': kStencilAccent,
  'Business Rule Task': kStencilSecondary,
  'Gateway': kStencilWarning,
  'Exclusive Gateway': kStencilWarning,
  'Parallel Gateway': kStencilWarning,
  'Inclusive Gateway': kStencilWarning,
  'Complex Gateway': kStencilWarning,
  'Event-Based Gateway': kStencilWarning,
  'Start Event': kStencilSuccess,
  'Message Start': kStencilSuccess,
  'Timer Start': kStencilSuccess,
  'Intermediate Event': kStencilAccent,
  'Message Intermediate': kStencilAccent,
  'Timer Intermediate': kStencilAccent,
  'Cancel Intermediate': kStencilDanger,
  'Link Intermediate': kStencilSecondary,
  'Compensation Intermediate': kStencilDanger,
  'Multiple Intermediate': kStencilSecondary,
  'Rule Intermediate': kStencilSecondary,
  'End Event': kStencilDanger,
  'Terminate': kStencilDanger,
  'Compensation': kStencilDanger,
  'Loop Marker': kStencilSecondary,
  'Multiple Instances': kStencilSecondary,
  'Ad Hoc': kStencilAccent,
  'Data Object': kStencilSecondary,
  'Message': kStencilAccent,
  'Pool': kStencilContainer,
  'Horizontal Lane': kStencilContainer,
  'Vertical Lane': kStencilContainer,
  'Vertical Pool': kStencilContainer,
  'Conversation': kStencilSecondary,

  // --- Network ---
  'Server': kStencilTeal,
  'Router': kStencilPrimary,
  'Firewall': kStencilDanger,
  'Monitor': kStencilNeutral,
  'Laptop': kStencilPrimary,
  'Mobile': kStencilPrimary,
  'Printer': kStencilNeutral,
  'Wireless': kStencilSky,
  'Hub': kStencilAccent,
  'PC': kStencilPrimary,
  'Tablet': kStencilPrimary,
  'Phone': kStencilPrimary,
  'Modem': kStencilAccent,
  'Storage': kStencilSuccess,
  'Load Balancer': kStencilWarning,
  'Security Camera': kStencilDanger,

  // --- Mockup ---
  'Button': kStencilPrimary,
  'Checkbox': kStencilSuccess,
  'Radio Button': kStencilSuccess,
  'Text Field': kStencilNeutral,
  'Combo Box': kStencilNeutral,
  'Window': kStencilContainer,
  'Progress Bar': kStencilSuccess,
  'Slider': kStencilPrimary,
  'Tab Bar': kStencilSecondary,
  'Menu Bar': kStencilNeutral,
  'Toggle': kStencilTeal,
  'Search Box': kStencilSky,
  'Star Rating': kStencilWarning,
  'Help Icon': kStencilPrimary,
  'Information Icon': kStencilSky,
  'Loading Circle': kStencilAccent,
  'Horizontal Splitter': kStencilNeutral,
  'Dropdown Menu': kStencilNeutral,

  // --- Electrical ---
  'Resistor': kStencilAccent,
  'Capacitor': kStencilSky,
  'Inductor': kStencilSecondary,
  'Diode': kStencilPrimary,
  'LED': kStencilSuccess,
  'Ground': kStencilNeutral,
  'Battery': kStencilAccent,
  'Transformer': kStencilWarning,
  'AC Source': kStencilWarning,
  'DC Source': kStencilAccent,
  'Electrical Switch': kStencilPrimary,
  'Fuse': kStencilDanger,
  'Inverter': kStencilTeal,
  'Potentiometer': kStencilAccent,
  'Circuit Breaker': kStencilDanger,
  'Crystal': kStencilSecondary,
  'Lamp': kStencilWarning,
  'AND Gate': kStencilPrimary,
  'OR Gate': kStencilPrimary,
  'NAND Gate': kStencilSecondary,
  'NOR Gate': kStencilSecondary,
  'XOR Gate': kStencilAccent,
  'XNOR Gate': kStencilAccent,
  'Buffer': kStencilTeal,

  // --- Signs ---
  'Warning': kStencilWarning,
  'No Entry': kStencilDanger,
  'Mandatory': kStencilPrimary,
  'Exit': kStencilSuccess,
  'Radiation': kStencilWarning,
  'First Aid': kStencilSuccess,
  'High Voltage': kStencilWarning,
  'Fragile': kStencilAccent,
  'No Smoking': kStencilDanger,
  'Biohazard': kStencilDanger,
  'Pedestrian Crossing': kStencilPrimary,
  'Keep Dry': kStencilSky,
  'Slip Hazard': kStencilWarning,
  'Fire Extinguisher': kStencilDanger,

  // --- Floorplan ---
  'Wall': kStencilNeutral,
  'Door': kStencilAccent,
  'Double Door': kStencilAccent,
  'Sliding Door': kStencilAccent,
  'Window Opening': kStencilSky,
  'Chair': kStencilSecondary,
  'Desk': kStencilTeal,
  'Bed': kStencilPrimary,
  'Sofa': kStencilSecondary,
  'Sink': kStencilSky,
  'Toilet': kStencilSky,
  'Stairs': kStencilNeutral,
  'Elevator': kStencilPrimary,
  'Escalator': kStencilPrimary,
  'Plant': kStencilSuccess,
  'Refrigerator': kStencilSky,
  'Bathtub': kStencilSky,
  'Shower': kStencilSky,
  'Closet': kStencilNeutral,
  'Bookshelf': kStencilAccent,
  'Fireplace': kStencilDanger,
  'Kitchen Island': kStencilAccent,
  'Parking Space': kStencilPrimary,
  'TV Stand': kStencilNeutral,
  'File Cabinet': kStencilTeal,
  'Column': kStencilNeutral,
  'Copier': kStencilNeutral,

  // --- EIP ---
  'Message Channel': kStencilPrimary,
  'Dead Letter Channel': kStencilDanger,
  'Invalid Message Channel': kStencilDanger,
  'Datatype Channel': kStencilTeal,
  'Aggregator': kStencilSuccess,
  'Splitter': kStencilWarning,
  'Content Based Router': kStencilWarning,
  'Message Filter': kStencilAccent,
  'Message Translator': kStencilSecondary,
  'Content Enricher': kStencilSuccess,
  'Messaging Gateway': kStencilWarning,
  'Channel Adapter': kStencilPrimary,
  'Wire Tap': kStencilAccent,
  'Recipient List': kStencilSecondary,
  'Competing Consumers': kStencilAccent,
  'Event Driven Consumer': kStencilAccent,
  'Messaging Bridge': kStencilTeal,
  'Process Manager': kStencilPrimary,
  'Claim Check': kStencilSecondary,
  'Resequencer': kStencilWarning,
  'Composed Message Processor': kStencilPrimary,
  'Content Filter': kStencilAccent,
  'Control Bus': kStencilNeutral,
  'Detour': kStencilWarning,
  'Durable Subscriber': kStencilSuccess,
  'Dynamic Router': kStencilWarning,
  'Envelope Wrapper': kStencilSecondary,
  'Message Dispatcher': kStencilPrimary,
  'Message Store': kStencilSuccess,
  'Normalizer': kStencilTeal,
  'Polling Consumer': kStencilAccent,
  'Routing Slip': kStencilWarning,
  'Selective Consumer': kStencilAccent,
  'Service Activator': kStencilPrimary,
  'Smart Proxy': kStencilTeal,
  'Transactional Client': kStencilSuccess,
  'Channel Purger': kStencilDanger,
  'Test Message': kStencilNeutral,

  // --- Misc ---
  'Autosize Title': kStencilPrimary,
  'Unordered List': kStencilNeutral,
  'Ordered List': kStencilNeutral,
  'Label 1': kStencilAccent,
  'Label 2': kStencilSecondary,
  'Waypoint': kStencilPrimary,
  'Image': kStencilNeutral,
};

/// Keyword heuristics for names not listed in [kStencilNameColors]
/// (esp. cloud vendor catalogues).
StencilColors? _heuristicColors(String name) {
  final n = name.toLowerCase();

  // Security / danger first (before generic "key").
  if (_any(n, const [
    'firewall',
    'waf',
    'security',
    'guard',
    'bastion',
    'armor',
    'vault',
    'kms',
    'secrets',
    'certificate',
    'iam',
    'cognito',
    'app id',
    'key protect',
    'destruction',
    'dead letter',
    'invalid message',
    'biohazard',
    'radiation',
    'no smoking',
    'no entry',
    'fire extinguisher',
    'high voltage',
    'fuse',
    'circuit breaker',
  ])) {
    return kStencilDanger;
  }

  // Data stores / databases.
  if (_any(n, const [
    'database',
    'dynamodb',
    'rds',
    'sql',
    'aurora',
    'cosmos',
    'bigquery',
    'bigtable',
    'spanner',
    'firestore',
    'cloudant',
    'db2',
    'polardb',
    'tablestore',
    'analyticdb',
    'hologres',
    'redshift',
    'synapse',
    'exadata',
    'mysql',
    'storage',
    's3',
    'blob',
    'oss',
    'efs',
    'nas',
    'block volume',
    'object storage',
    'file storage',
    'data store',
    'data object',
    'entity',
    'cache',
    'redis',
    'memorystore',
    'elasticache',
  ])) {
    return kStencilSuccess;
  }

  // Queues / async / gateways (warning).
  if (_any(n, const [
    'queue',
    'sqs',
    'sns',
    'mq',
    'rocketmq',
    'pubsub',
    'pub/sub',
    'event hub',
    'eventbridge',
    'event grid',
    'kinesis',
    'streaming',
    'gateway',
    'load balanc',
    'elb',
    'slb',
    'alb',
    'nlb',
    'router',
    'decision',
    'delay',
    'warning',
    'fragile',
    'slip',
  ])) {
    return kStencilWarning;
  }

  // Compute / functions (accent).
  if (_any(n, const [
    'lambda',
    'function',
    'fargate',
    'ec2',
    'ecs',
    'eks',
    'aks',
    'gke',
    'oke',
    'ack',
    'iks',
    'roks',
    'compute',
    'virtual machine',
    'app service',
    'app engine',
    'cloud run',
    'code engine',
    'manual',
    'message',
    'notification',
    'timer',
  ])) {
    return kStencilAccent;
  }

  // Network / connectivity (sky).
  if (_any(n, const [
    'vpc',
    'vnet',
    'virtual network',
    'vpn',
    'cdn',
    'cloudfront',
    'front door',
    'dns',
    'route 53',
    'direct connect',
    'direct link',
    'fastconnect',
    'transit',
    'wireless',
    'wifi',
    'modem',
    'switch',
    'hub',
    'bridge',
    'cloud',
  ])) {
    return kStencilSky;
  }

  // Packages / notes / documents (secondary).
  if (_any(n, const [
    'note',
    'document',
    'package',
    'module',
    'interface',
    'component',
    'class',
    'annotation',
    'script',
    'rule',
  ])) {
    return kStencilSecondary;
  }

  // Start / success / health.
  if (_any(n, const [
    'start',
    'first aid',
    'exit',
    'tick',
    'smiley',
    'progress',
    'checkbox',
  ])) {
    return kStencilSuccess;
  }

  // End / error / cross.
  if (_any(n, const [
    'end event',
    'terminate',
    'error',
    'cancel',
    'sad smiley',
  ])) {
    return kStencilDanger;
  }

  return null;
}

bool _any(String haystack, List<String> needles) {
  for (final n in needles) {
    if (haystack.contains(n)) return true;
  }
  return false;
}

VsdxColor? _parseHex(String? hex) {
  if (hex == null) return null;
  var h = hex.trim();
  if (h.isEmpty) return null;
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 3) {
    h = h.split('').map((c) => '$c$c').join();
  }
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : VsdxColor(v);
}

/// Resolve colours for a stencil by optional explicit pair, then name, then group.
StencilColors? resolveStencilColors({
  StencilColors? explicit,
  String? name,
  String? group,
}) {
  if (explicit != null) return explicit;
  if (name != null) {
    final byName = kStencilNameColors[name];
    if (byName != null) return byName;
    final heuristic = _heuristicColors(name);
    if (heuristic != null) return heuristic;
  }
  if (group != null) return kStencilGroupColors[group] ?? kStencilPrimary;
  return kStencilPrimary;
}

bool _userFlag(VsdxShape shape, String name) {
  for (final cell in shape.userCells) {
    if (cell.name == name) return cell.value == '1';
  }
  return false;
}

/// Apply fill/stroke to a freshly built shape. Skips text boxes (no fill & no
/// line). Preserves arrowheads and dash patterns on 1D / connector-like shapes.
/// Walks children so extra inherit-fill siblings (AWS Cloud puffs) receive
/// the palette; authored hex on nested glyphs stays.
VsdxShape applyStencilStyle(
  VsdxShape shape, {
  StencilColors? colors,
  double lineWeightInches = 0.012,
  bool isRoot = true,
}) {
  if (colors == null) return shape;

  // Text / invisible decoration: leave alone. A group hit-box with
  // leftover siblings still has no fill/line (AWS Cloud puffs after
  // hex highlights; AWS4b productIcon inherit square after the white
  // plate). Skip only when there are no children to recolor — otherwise
  // null-foreground inherit fills never get palette FillForegnd
  // (tokens.txt FillForegnd is svg:fill).
  if (!shape.is1D &&
      !shape.fill.hasFill &&
      !shape.line.hasLine &&
      shape.children.isEmpty) {
    return shape;
  }

  final fillColor = _parseHex(colors.fill);
  final lineColor = _parseHex(colors.stroke);

  var fill = shape.fill;
  var line = shape.line;

  if (shape.is1D) {
    if (lineColor != null && line.hasLine) {
      // Match 2-D: clear themeColorIndex so stencil solid colour sticks.
      line = line
          .withSolidColor(lineColor)
          .copyWith(weightInches: lineWeightInches);
    }
    return identical(line, shape.line) ? shape : shape.copyWith(line: line);
  }

  if (fill.hasFill) {
    if (_userFlag(shape, VsdxShape.userMxFillFromStroke) && lineColor != null) {
      // mxStencil.parseColor('stroke') is shape.stroke. leftover inherit
      // fillcolor=stroke must take the palette LineColor, not FillForegnd
      // (`tokens.txt` FillForegnd → svg:fill).
      fill = fill.withSolidForeground(lineColor);
    } else if (fillColor != null) {
      final fg = fill.foreground;
      // Factory white and unresolved theme slots take the palette. Authored
      // hex (C4 Person #083F75) must stay so collectFill does not wash it.
      // Child inherit-fill siblings have a null foreground; white child
      // highlights must not be washed (AWS white glyphs).
      if (fg == null || (isRoot && fg == VsdxColor.white)) {
        fill = fill.withSolidForeground(fillColor);
      }
    }
  }
  if (line.hasLine) {
    if (_userFlag(shape, VsdxShape.userMxStrokeFromFill) && fillColor != null) {
      line = line.withSolidColor(fillColor);
      if ((line.weightInches - VsdxLine.defaultLine.weightInches).abs() <
          1e-9) {
        line = line.copyWith(weightInches: lineWeightInches);
      }
    } else if (lineColor != null) {
      final c = line.color;
      if (c == null || (isRoot && c == VsdxColor.black)) {
        line = line.withSolidColor(lineColor);
        // mxStencil <strokewidth> already froze LineWeight in stencil
        // units. Overwriting it with the palette default would drop the
        // checkmark / IEC rail that libvisio collectLine collects.
        if ((line.weightInches - VsdxLine.defaultLine.weightInches).abs() <
            1e-9) {
          line = line.copyWith(weightInches: lineWeightInches);
        }
      }
    }
  }
  var next = shape;
  if (!identical(fill, shape.fill) || !identical(line, shape.line)) {
    next = shape.copyWith(fill: fill, line: line);
  }
  if (next.children.isEmpty) return next;
  final children = <VsdxShape>[
    for (final child in next.children)
      applyStencilStyle(
        child,
        colors: colors,
        lineWeightInches: lineWeightInches,
        isRoot: false,
      ),
  ];
  var childrenChanged = false;
  for (var i = 0; i < children.length; i++) {
    if (!identical(children[i], next.children[i])) {
      childrenChanged = true;
      break;
    }
  }
  return childrenChanged ? next.copyWith(children: children) : next;
}
