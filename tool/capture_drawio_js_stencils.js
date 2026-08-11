#!/usr/bin/env node
// Captures draw.io's JavaScript Canvas shapes as XML stencil geometry.
// Used by generate_drawio_js_stencils.py; generated Dart is runtime-independent.

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const webapp = path.resolve(process.argv[2]);
const sidebarRoot = path.join(webapp, 'js/diagramly/sidebar');
const shapeRoot = path.join(webapp, 'shapes');

function parseStyle(source) {
  const style = {};
  for (const part of String(source || '').split(';')) {
    const split = part.indexOf('=');
    if (split >= 0) style[part.slice(0, split)] = part.slice(split + 1);
  }
  return style;
}

function xmlEscape(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

function number(value) {
  return Number.isFinite(Number(value)) ? String(Number(value)) : '0';
}

class CanvasRecorder {
  constructor() {
    this.tx = 0;
    this.ty = 0;
    this.stack = [];
    this.operations = [];
    this.pathOpen = false;
    this.externalAsset = false;
    this.state = {fillColor: '#ffffff', strokeColor: '#000000'};
  }

  save() {
    this.stack.push({tx: this.tx, ty: this.ty, state: {...this.state}});
  }

  restore() {
    const saved = this.stack.pop();
    if (saved) {
      this.tx = saved.tx;
      this.ty = saved.ty;
      this.state = saved.state;
    }
  }

  translate(x, y) { this.tx += Number(x) || 0; this.ty += Number(y) || 0; }
  begin() { this.finishPath(); this.operations.push('<path>'); this.pathOpen = true; }
  end() { this.finishPath(); }
  moveTo(x, y) { this.command('move', {x: this.x(x), y: this.y(y)}); }
  lineTo(x, y) { this.command('line', {x: this.x(x), y: this.y(y)}); }
  curveTo(x1, y1, x2, y2, x3, y3) {
    this.command('curve', {
      x1: this.x(x1), y1: this.y(y1), x2: this.x(x2), y2: this.y(y2),
      x3: this.x(x3), y3: this.y(y3),
    });
  }
  quadTo(x1, y1, x2, y2) {
    this.command('quad', {x1: this.x(x1), y1: this.y(y1), x2: this.x(x2), y2: this.y(y2)});
  }
  arcTo(rx, ry, rotation, largeArc, sweep, x, y) {
    this.command('arc', {
      rx, ry, 'x-axis-rotation': rotation, 'large-arc-flag': largeArc,
      'sweep-flag': sweep, x: this.x(x), y: this.y(y),
    });
  }
  close() { this.operations.push('<close/>'); }
  rect(x, y, w, h) {
    this.finishPath();
    this.operations.push(`<rect x="${number(this.x(x))}" y="${number(this.y(y))}" w="${number(w)}" h="${number(h)}"/>`);
  }
  roundrect(x, y, w, h, rx, ry) {
    this.finishPath();
    const arc = Math.min(100, 100 * Math.max(Number(rx) || 0, Number(ry) || 0) /
      Math.max(1e-9, Math.min(Math.abs(Number(w) || 0), Math.abs(Number(h) || 0))));
    this.operations.push(`<roundrect x="${number(this.x(x))}" y="${number(this.y(y))}" w="${number(w)}" h="${number(h)}" arcsize="${number(arc)}"/>`);
  }
  ellipse(x, y, w, h) {
    this.finishPath();
    this.operations.push(`<ellipse x="${number(this.x(x))}" y="${number(this.y(y))}" w="${number(w)}" h="${number(h)}"/>`);
  }
  fill() { this.finishPath(); this.operations.push('<fill/>'); }
  stroke() { this.finishPath(); this.operations.push('<stroke/>'); }
  fillAndStroke() { this.finishPath(); this.operations.push('<fillstroke/>'); }
  image() { this.externalAsset = true; }
  text() {}

  setAlpha(value) { this.state.alpha = value; }
  setFillAlpha(value) { this.state.fillAlpha = value; }
  setFillColor(value) { this.state.fillColor = value; }
  setStrokeColor(value) { this.state.strokeColor = value; }
  setStrokeWidth(value) { this.state.strokeWidth = value; }
  setDashed(value) { this.state.dashed = value; }
  setGradient() {}
  setLineCap() {}
  setLineJoin() {}
  setMiterLimit() {}
  setShadow() {}
  setFontColor() {}
  setFontFamily() {}
  setFontSize() {}
  setFontStyle() {}

  x(value) { return (Number(value) || 0) + this.tx; }
  y(value) { return (Number(value) || 0) + this.ty; }
  command(name, attributes) {
    const values = Object.entries(attributes)
      .map(([key, value]) => ` ${key}="${number(value)}"`).join('');
    this.operations.push(`<${name}${values}/>`);
  }
  finishPath() {
    if (this.pathOpen) {
      this.operations.push('</path>');
      this.pathOpen = false;
    }
  }
  finish() { this.finishPath(); }
}

function mxShape() { this.style = {}; }
mxShape.prototype.getTextRotation = function() { return 0; };
mxShape.prototype.isHtmlAllowed = function() { return false; };
mxShape.prototype.getShapeRotation = function() { return 0; };
mxShape.prototype.configureCanvas = function() {};
mxShape.prototype.updateTransform = function() {};
mxShape.prototype.getArcSize = function(w, h) { return Math.min(w, h) * 0.1; };

const baseNames = [
  'mxActor', 'mxArrow', 'mxArrowConnector', 'mxCylinder', 'mxDoubleEllipse',
  'mxEllipse', 'mxImageShape', 'mxLabel', 'mxRectangleShape', 'mxRhombus',
  'mxSwimlane',
];

function createBaseShape(name) {
  function BaseShape() { mxShape.call(this); }
  BaseShape.prototype = Object.create(mxShape.prototype);
  BaseShape.prototype.constructor = BaseShape;
  if (name === 'mxEllipse' || name === 'mxDoubleEllipse') {
    BaseShape.prototype.paintVertexShape = function(c, x, y, w, h) {
      c.ellipse(x, y, w, h); c.fillAndStroke();
    };
  } else if (name === 'mxRhombus') {
    BaseShape.prototype.paintVertexShape = function(c, x, y, w, h) {
      c.begin(); c.moveTo(x + w / 2, y); c.lineTo(x + w, y + h / 2);
      c.lineTo(x + w / 2, y + h); c.lineTo(x, y + h / 2); c.close();
      c.fillAndStroke();
    };
  } else if (name === 'mxRectangleShape' || name === 'mxLabel' || name === 'mxSwimlane') {
    BaseShape.prototype.paintVertexShape = function(c, x, y, w, h) {
      c.rect(x, y, w, h); c.fillAndStroke();
    };
  }
  return BaseShape;
}

const registry = {};
const constantProxy = new Proxy({}, {get: (_, key) => String(key)});
const shapeContext = {
  mxShape,
  mxUtils: {
    extend(child, parent) {
      child.prototype = Object.create(parent.prototype);
      child.prototype.constructor = child;
    },
    getValue(style, key, fallback) {
      return style && style[key] != null ? style[key] : fallback;
    },
    getNumber(style, key, fallback) {
      const value = style && style[key] != null ? Number(style[key]) : fallback;
      return Number.isFinite(value) ? value : fallback;
    },
    getColorValue(style, key, fallback) {
      return style && style[key] != null ? style[key] : fallback;
    },
    getSizeForString(value, fontSize) {
      const size = Number(fontSize) || 12;
      return {width: String(value || '').length * size * 0.6, height: size * 1.2};
    },
    clone(value) { return {...value}; },
  },
  mxCellRenderer: {
    defaultShapes: registry,
    registerShape(name, ctor) { registry[name] = ctor; },
  },
  mxConstants: constantProxy,
  mxPoint: function(x, y) { this.x = x; this.y = y; },
  mxRectangle: function(x, y, width, height) {
    this.x = x; this.y = y; this.width = width; this.height = height;
  },
  mxConnectionConstraint: function(point, perimeter, name, dx, dy) {
    this.point = point; this.perimeter = perimeter; this.name = name;
    this.dx = dx || 0; this.dy = dy || 0;
  },
  mxClient: {IS_FF: false, IS_SF: false},
  mxMarker: {addMarker() {}},
  mxStencilRegistry: {
    getStencil() {
      return {drawShape(canvas) { canvas.externalAsset = true; }};
    },
  },
  GRAPH_IMAGE_PATH: '',
  Graph: {handleFactory: {}, createHandle() { return {}; }},
  document: {createElement: () => ({style: {}})},
  window: {},
  console,
};
for (const name of baseNames) shapeContext[name] = createBaseShape(name);
vm.createContext(shapeContext);

function recursiveJs(root) {
  return fs.readdirSync(root, {recursive: true})
    .filter((name) => name.endsWith('.js')).sort();
}

const loadErrors = [];
for (const file of recursiveJs(shapeRoot)) {
  try {
    vm.runInContext(fs.readFileSync(path.join(shapeRoot, file), 'utf8'), shapeContext, {filename: file});
  } catch (error) {
    loadErrors.push({file, error: String(error)});
  }
}

function Geometry(x, y, width, height) {
  this.x = x; this.y = y; this.width = width; this.height = height;
  this.relative = false;
}
Geometry.prototype.setTerminalPoint = function() {};
Geometry.prototype.clone = function() { return Object.assign(new Geometry(), this); };
function Cell(value, geometry, style) {
  this.value = value; this.geometry = geometry; this.style = style;
  this.children = []; this.edges = [];
}
Cell.prototype.insert = function(cell) { this.children.push(cell); return cell; };
Cell.prototype.insertEdge = function(cell) { this.edges.push(cell); return cell; };
Cell.prototype.clone = function() { return Object.assign(new Cell(), this); };
Cell.prototype.setValue = function(value) { this.value = value; };
Cell.prototype.setAttribute = function() {};

function Sidebar() { this.palettes = []; }
Sidebar.prototype.setCurrentSearchEntryLibrary = function() {};
Sidebar.prototype.getTagsForStencil = function() { return []; };
Sidebar.prototype.addEntry = function(tags, factory) {
  const wrapped = function(content) { return factory(content); };
  wrapped.entry = {kind: 'factory', tags};
  return wrapped;
};
Sidebar.prototype.addDataEntry = function(tags, width, height, title, data) {
  const wrapped = function() { return wrapped.entry; };
  wrapped.entry = {kind: 'data', tags, width, height, title, data};
  return wrapped;
};
Sidebar.prototype.createVertexTemplateEntry = function(style, width, height, value, title) {
  const wrapped = function() { return wrapped.entry; };
  wrapped.entry = {kind: 'vertex', style, width, height, value, title};
  return wrapped;
};
Sidebar.prototype.createEdgeTemplateEntry = function(style, width, height, value, title) {
  const wrapped = function() { return wrapped.entry; };
  wrapped.entry = {kind: 'edge', style, width, height, value, title};
  return wrapped;
};
Sidebar.prototype.createVertexTemplateFromCells = function(cells, width, height, title) {
  return {kind: 'vertex-cells', cells, width, height, title};
};
Sidebar.prototype.createEdgeTemplateFromCells = function(cells, width, height, title) {
  return {kind: 'edge-cells', cells, width, height, title};
};
Sidebar.prototype.addPaletteFunctions = function(id, title, expanded, functions) {
  const entries = functions.map((fn) => {
    if (!fn) return null;
    if (fn.entry && fn.entry.kind === 'factory') {
      try { return fn({}); } catch (_) { return fn.entry; }
    }
    return fn.entry;
  }).filter(Boolean);
  this.palettes.push({id, title, entries});
};
Sidebar.prototype.addPalette = function(id, title, expanded, factory) {
  const entries = [];
  try { factory({appendChild(value) { if (value) entries.push(value); }}); } catch (_) {}
  this.palettes.push({id, title, entries});
};

const sidebarContext = {
  Sidebar,
  mxConstants: constantProxy,
  mxResources: {get: (key) => String(key)},
  mxUtils: {
    bind: (scope, fn) => fn.bind(scope),
    extend() {},
    createXmlDocument: () => ({createElement: (name) => ({name})}),
    htmlEntities: (value) => value,
  },
  mxCell: Cell,
  mxGeometry: Geometry,
  mxPoint: shapeContext.mxPoint,
  mxRectangle: shapeContext.mxRectangle,
  Graph: {createIcon: (name) => name, zapGremlins: (value) => value},
  urlParams: {},
  isLocalStorage: false,
  document: {createElement: () => ({style: {}, appendChild() {}})},
  window: {},
  console,
};
vm.createContext(sidebarContext);

const captured = [];
for (const file of fs.readdirSync(sidebarRoot).filter((name) => /^Sidebar-.*\.js$/.test(name)).sort()) {
  const before = new Set(Object.getOwnPropertyNames(Sidebar.prototype));
  try {
    vm.runInContext(fs.readFileSync(path.join(sidebarRoot, file), 'utf8'), sidebarContext, {filename: file});
  } catch (_) {
    continue;
  }
  const methods = Object.getOwnPropertyNames(Sidebar.prototype)
    .filter((name) => !before.has(name) && /^add.*Palette/.test(name));
  const sidebar = new Sidebar();
  sidebarContext.sb = sidebar;
  for (const method of methods) {
    try { sidebar[method](); } catch (_) {}
  }
  const palettes = new Map();
  for (const palette of sidebar.palettes) {
    const previous = palettes.get(palette.id);
    if (!previous || palette.entries.length > previous.entries.length) palettes.set(palette.id, palette);
  }
  captured.push({file, palettes: [...palettes.values()]});
}

const renderStats = {notVertex: 0, noStyle: 0, unregistered: 0, noPainter: 0, paintError: 0, noGeometry: 0};
const paintErrors = [];
const paintErrorCounts = {};
function paintRegistered(style, width, height, canvas, x = 0, y = 0) {
  const ctor = registry[style.shape];
  if (!ctor) return null;
  if (!ctor.prototype.paintVertexShape) return null;
  const shape = new ctor(null, style.fillColor || '#ffffff', style.strokeColor || '#000000', 1);
  shape.style = style;
  shape.state = {style};
  try {
    shape.paintVertexShape(canvas, x, y, width, height);
  } catch (error) {
    renderStats.paintError++;
    const errorKey = String(error);
    paintErrorCounts[errorKey] = (paintErrorCounts[errorKey] || 0) + 1;
    if (paintErrors.length < 30) paintErrors.push({shape: style.shape, error: String(error)});
    return false;
  }
  canvas.finish();
  return shape;
}

function renderEntry(entry) {
  const canvas = new CanvasRecorder();
  let width;
  let height;
  let shape = null;
  let style = null;
  if (entry.kind === 'vertex') {
    if (typeof entry.style !== 'string') { renderStats.noStyle++; return null; }
    style = parseStyle(entry.style);
    const ctor = registry[style.shape];
    if (!ctor) { renderStats.unregistered++; return null; }
    if (!ctor.prototype.paintVertexShape) { renderStats.noPainter++; return null; }
    width = Math.max(1, Number(entry.width) || 100);
    height = Math.max(1, Number(entry.height) || 100);
    shape = paintRegistered(style, width, height, canvas);
    if (!shape) return null;
  } else if (entry.kind === 'vertex-cells' && Array.isArray(entry.cells)) {
    width = Math.max(1, Number(entry.width) || 100);
    height = Math.max(1, Number(entry.height) || 100);
    let painted = false;
    const visit = (cell, parentX, parentY) => {
      if (!cell || !cell.geometry) return;
      const x = parentX + (Number(cell.geometry.x) || 0);
      const y = parentY + (Number(cell.geometry.y) || 0);
      const cellWidth = Math.max(1, Number(cell.geometry.width) || width);
      const cellHeight = Math.max(1, Number(cell.geometry.height) || height);
      const cellStyle = parseStyle(cell.style);
      const result = paintRegistered(cellStyle, cellWidth, cellHeight, canvas, x, y);
      if (result) painted = true;
      for (const child of cell.children || []) visit(child, x, y);
    };
    for (const cell of entry.cells) visit(cell, 0, 0);
    if (!painted) { renderStats.notVertex++; return null; }
  } else {
    renderStats.notVertex++;
    return null;
  }
  if (canvas.externalAsset) { renderStats.noGeometry++; return null; }
  if (!canvas.operations.some((operation) => /<(move|line|curve|quad|arc|rect|roundrect|ellipse)\b/.test(operation))) {
    renderStats.noGeometry++;
    return null;
  }
  let connections = '';
  if (shape && typeof shape.getConstraints === 'function') {
    try {
      const values = shape.getConstraints(style, width, height) || [];
      const items = values.filter((item) => item && item.point).map((item) => {
        const x = Number(item.point.x) + (Number(item.dx) || 0) / width;
        const y = Number(item.point.y) + (Number(item.dy) || 0) / height;
        return `<constraint x="${number(x)}" y="${number(y)}" perimeter="0"/>`;
      });
      if (items.length) connections = `<connections>${items.join('')}</connections>`;
    } catch (_) {}
  }
  return {width, height, body: connections + `<foreground>${canvas.operations.join('')}</foreground>`};
}

const libraries = [];
let sourceEntries = 0;
let renderedEntries = 0;
for (const family of captured) {
  const familyName = family.file.replace(/^Sidebar-/, '').replace(/\.js$/, '');
  for (const palette of family.palettes) {
    sourceEntries += palette.entries.length;
    const shapes = [];
    const names = new Map();
    for (const entry of palette.entries) {
      const rendered = renderEntry(entry);
      if (!rendered) continue;
      const base = String(entry.title || 'Unnamed Shape').trim() || 'Unnamed Shape';
      const count = (names.get(base) || 0) + 1;
      names.set(base, count);
      const name = count === 1 ? base : `${base} (${count})`;
      shapes.push(`<shape aspect="variable" h="${number(rendered.height)}" name="${xmlEscape(name)}" strokewidth="inherit" w="${number(rendered.width)}">${rendered.body}</shape>`);
      renderedEntries++;
    }
    if (shapes.length) {
      const title = String(palette.title || palette.id || familyName);
      libraries.push({
        sourcePath: `js/diagramly/sidebar/${family.file}#${palette.id}`,
        groupName: `Draw.io JS / ${familyName} / ${title}`,
        xml: `<shapes name="mxgraph.generated.${xmlEscape(familyName.toLowerCase())}">${shapes.join('')}</shapes>`,
      });
    }
  }
}

const result = {
  sourceVersion: 'draw.io 30.3.6',
  registeredShapes: Object.keys(registry).length,
  shapeLoadErrors: loadErrors,
  sourceEntries,
  renderedEntries,
  renderStats,
  paintErrors,
  paintErrorCounts,
  libraries,
};
if (process.argv.includes('--summary')) {
  process.stdout.write(JSON.stringify({
    ...result,
    libraries: libraries.map((library) => ({
      groupName: library.groupName,
      shapes: (library.xml.match(/<shape\b/g) || []).length,
    })),
  }, null, 2));
} else {
  process.stdout.write(JSON.stringify(result));
}
