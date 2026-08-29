#!/usr/bin/env node
// Captures draw.io's JavaScript Canvas shapes as XML stencil geometry.
// Used by generate_drawio_js_stencils.py; generated Dart is runtime-independent.

const fs = require('fs');
const path = require('path');
const vm = require('vm');
const zlib = require('zlib');

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
    .replaceAll('"', '&quot;')
    .replaceAll('\n', '&#10;');
}

function number(value) {
  return Number.isFinite(Number(value)) ? String(Number(value)) : '0';
}

class CanvasRecorder {
  constructor() {
    this.tx = 0;
    this.ty = 0;
    this.rotTheta = 0;
    this.rotFlipH = false;
    this.rotFlipV = false;
    this.rotCx = 0;
    this.rotCy = 0;
    this.stack = [];
    this.operations = [];
    this.pathOpen = false;
    this.externalAsset = false;
    this.state = {fillColor: '#ffffff', strokeColor: '#000000', fontSize: 12, fontStyle: 0};
  }

  save() {
    this.stack.push({
      tx: this.tx, ty: this.ty, state: {...this.state},
      rotTheta: this.rotTheta, rotFlipH: this.rotFlipH, rotFlipV: this.rotFlipV,
      rotCx: this.rotCx, rotCy: this.rotCy,
    });
  }

  restore() {
    const saved = this.stack.pop();
    if (saved) {
      this.tx = saved.tx;
      this.ty = saved.ty;
      this.state = saved.state;
      this.rotTheta = saved.rotTheta;
      this.rotFlipH = saved.rotFlipH;
      this.rotFlipV = saved.rotFlipV;
      this.rotCx = saved.rotCx;
      this.rotCy = saved.rotCy;
    }
  }

  translate(x, y) { this.tx += Number(x) || 0; this.ty += Number(y) || 0; }
  scale() {}
  rotate(theta, flipH, flipV, cx, cy) {
    this.rotTheta = Number(theta) || 0;
    this.rotFlipH = !!flipH;
    this.rotFlipV = !!flipV;
    this.rotCx = Number(cx) || 0;
    this.rotCy = Number(cy) || 0;
  }
  isRotated() {
    return this.rotTheta !== 0 || this.rotFlipH || this.rotFlipV;
  }
  map(px, py) {
    let x = (Number(px) || 0) + this.tx;
    let y = (Number(py) || 0) + this.ty;
    if (!this.isRotated()) return {x, y};
    let theta = this.rotTheta;
    const cx = this.rotCx;
    const cy = this.rotCy;
    if (this.rotFlipH && this.rotFlipV) theta += 180;
    else if (this.rotFlipH !== this.rotFlipV) {
      if (this.rotFlipH) x = 2 * cx - x;
      if (this.rotFlipV) y = 2 * cy - y;
    }
    if (this.rotFlipH ? !this.rotFlipV : this.rotFlipV) theta = -theta;
    if (theta !== 0) {
      const rad = theta * Math.PI / 180;
      const cos = Math.cos(rad);
      const sin = Math.sin(rad);
      const dx = x - cx;
      const dy = y - cy;
      x = cx + dx * cos - dy * sin;
      y = cy + dx * sin + dy * cos;
    }
    return {x, y};
  }
  begin() { this.finishPath(); this.operations.push('<path>'); this.pathOpen = true; }
  end() { this.finishPath(); }
  moveTo(x, y) { const p = this.map(x, y); this.command('move', {x: p.x, y: p.y}); }
  lineTo(x, y) { const p = this.map(x, y); this.command('line', {x: p.x, y: p.y}); }
  curveTo(x1, y1, x2, y2, x3, y3) {
    const p1 = this.map(x1, y1);
    const p2 = this.map(x2, y2);
    const p3 = this.map(x3, y3);
    this.command('curve', {x1: p1.x, y1: p1.y, x2: p2.x, y2: p2.y, x3: p3.x, y3: p3.y});
  }
  quadTo(x1, y1, x2, y2) {
    const p1 = this.map(x1, y1);
    const p2 = this.map(x2, y2);
    this.command('quad', {x1: p1.x, y1: p1.y, x2: p2.x, y2: p2.y});
  }
  arcTo(rx, ry, rotation, largeArc, sweep, x, y) {
    const p = this.map(x, y);
    this.command('arc', {
      rx, ry, 'x-axis-rotation': (Number(rotation) || 0) + this.rotTheta,
      'large-arc-flag': largeArc, 'sweep-flag': sweep, x: p.x, y: p.y,
    });
  }
  close() { this.operations.push('<close/>'); }
  poly(points) {
    if (!points || points.length < 2) return;
    this.begin();
    this.moveTo(points[0][0], points[0][1]);
    for (let i = 1; i < points.length; i++) this.lineTo(points[i][0], points[i][1]);
    this.close();
  }
  rect(x, y, w, h) {
    this.finishPath();
    if (Math.abs(Number(w) || 0) < 1e-9 && Math.abs(Number(h) || 0) < 1e-9) return;
    if (this.isRotated()) {
      this.poly([[x, y], [x + w, y], [x + w, y + h], [x, y + h]]);
      return;
    }
    const p = this.map(x, y);
    this.operations.push(`<rect x="${number(p.x)}" y="${number(p.y)}" w="${number(w)}" h="${number(h)}"/>`);
  }
  roundrect(x, y, w, h, rx, ry) {
    this.finishPath();
    if (Math.abs(Number(w) || 0) < 1e-9 && Math.abs(Number(h) || 0) < 1e-9) return;
    if (this.isRotated()) {
      this.poly([[x, y], [x + w, y], [x + w, y + h], [x, y + h]]);
      return;
    }
    const p = this.map(x, y);
    const arc = Math.min(100, 100 * Math.max(Number(rx) || 0, Number(ry) || 0) /
      Math.max(1e-9, Math.min(Math.abs(Number(w) || 0), Math.abs(Number(h) || 0))));
    this.operations.push(`<roundrect x="${number(p.x)}" y="${number(p.y)}" w="${number(w)}" h="${number(h)}" arcsize="${number(arc)}"/>`);
  }
  ellipse(x, y, w, h) {
    this.finishPath();
    if (Math.abs(Number(w) || 0) < 1e-9 && Math.abs(Number(h) || 0) < 1e-9) return;
    if (this.isRotated()) {
      const rx = w / 2;
      const ry = h / 2;
      const cx = x + rx;
      const cy = y + ry;
      const k = 0.5522847498;
      this.begin();
      this.moveTo(cx + rx, cy);
      this.curveTo(cx + rx, cy + k * ry, cx + k * rx, cy + ry, cx, cy + ry);
      this.curveTo(cx - k * rx, cy + ry, cx - rx, cy + k * ry, cx - rx, cy);
      this.curveTo(cx - rx, cy - k * ry, cx - k * rx, cy - ry, cx, cy - ry);
      this.curveTo(cx + k * rx, cy - ry, cx + rx, cy - k * ry, cx + rx, cy);
      this.close();
      return;
    }
    const p = this.map(x, y);
    this.operations.push(`<ellipse x="${number(p.x)}" y="${number(p.y)}" w="${number(w)}" h="${number(h)}"/>`);
  }
  fill() { this.finishPath(); this.operations.push('<fill/>'); }
  stroke() { this.finishPath(); this.operations.push('<stroke/>'); }
  fillAndStroke() { this.finishPath(); this.operations.push('<fillstroke/>'); }
  // Raster images stay out of the vector capture. Nested mxStencil painters
  // also call image(); dropping the whole parent would hide Kubernetes / AWS
  // product icons that still have vector geometry.
  image() {}
  setFillStyle() {}
  setStrokeAlpha() {}
  setFontBackgroundColor() {}
  setFontBorderColor() {}
  setShadowColor() {}
  setShadowAlpha() {}
  setShadowOffset() {}
  setTitle() {}
  setLink() {}
  text(x, y, w, h, str, align, valign, wrap, format, overflow, clip, rotation) {
    this.finishPath();
    const s = String(str ?? '');
    if (!s) return;
    const horiz = String(align ?? '').toLowerCase();
    const vert = String(valign ?? '').toLowerCase();
    const fontSize = Number(this.state.fontSize);
    if (Number.isFinite(fontSize) && fontSize > 0) {
      this.operations.push(`<fontsize size="${number(fontSize)}"/>`);
    }
    const fontStyle = Number(this.state.fontStyle);
    if (Number.isFinite(fontStyle) && fontStyle !== 0) {
      this.operations.push(`<fontstyle style="${number(fontStyle)}"/>`);
    }
    const p = this.map(x, y);
    const rot = (Number(rotation) || 0) + this.rotTheta;
    const attrs = [
      `x="${number(p.x)}"`,
      `y="${number(p.y)}"`,
      `str="${xmlEscape(s)}"`,
      `align="${horiz.includes('center') ? 'center' : horiz.includes('right') ? 'right' : 'left'}"`,
      `valign="${vert.includes('middle') ? 'middle' : vert.includes('bottom') ? 'bottom' : 'top'}"`,
    ];
    if (Number.isFinite(rot) && rot !== 0) attrs.push(`rotation="${number(rot)}"`);
    this.operations.push(`<text ${attrs.join(' ')}/>`);
  }

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
  setDashPattern() {}
  setFontColor() {}
  setFontFamily() {}
  setFontSize(value) { this.state.fontSize = value; }
  setFontStyle(value) { this.state.fontStyle = value; }

  x(value) { return (Number(value) || 0) + this.tx; }
  y(value) { return (Number(value) || 0) + this.ty; }
  command(name, attributes) {
    if (!this.pathOpen) {
      this.operations.push('<path>');
      this.pathOpen = true;
    }
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

function decodeXml(value) {
  return String(value)
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&#10;', '\n')
    .replaceAll('&amp;', '&');
}

function parseAttributes(source) {
  const attrs = {};
  const re = /([A-Za-z_:][\w:.-]*)\s*=\s*"([^"]*)"/g;
  let match;
  while ((match = re.exec(source))) attrs[match[1]] = decodeXml(match[2]);
  return attrs;
}

function parseXml(xml) {
  const cleaned = String(xml).replace(/<\?[\s\S]*?\?>/g, '').replace(/<!--[\s\S]*?-->/g, '');
  const root = {name: '#root', attrs: {}, children: []};
  const stack = [root];
  const re = /<(\/)?([A-Za-z_][\w:.-]*)([^>]*?)(\/)?>|([^<]+)/g;
  let match;
  while ((match = re.exec(cleaned))) {
    if (match[5] != null) continue;
    if (match[1]) {
      if (stack.length > 1) stack.pop();
      continue;
    }
    const node = {name: match[2], attrs: parseAttributes(match[3] || ''), children: []};
    stack[stack.length - 1].children.push(node);
    if (!match[4]) stack.push(node);
  }
  return root;
}

function attrNum(node, key, fallback = 0) {
  const value = Number(node.attrs[key]);
  return Number.isFinite(value) ? value : fallback;
}

const stencilMap = {};

class NestedStencil {
  constructor(desc) {
    this.w0 = Number(desc.attrs.w) || 100;
    this.h0 = Number(desc.attrs.h) || 100;
    this.aspect = desc.attrs.aspect || 'variable';
    this.bgNode = desc.children.find((child) => child.name === 'background');
    this.fgNode = desc.children.find((child) => child.name === 'foreground');
  }

  drawShape(canvas, shape, x, y, w, h) {
    if (!(w > 0) || !(h > 0)) return;
    let sx = w / this.w0;
    let sy = h / this.h0;
    let x0 = x;
    let y0 = y;
    if (this.aspect === 'fixed') {
      const scale = Math.min(sx, sy);
      sx = scale;
      sy = scale;
      x0 += (w - this.w0 * scale) / 2;
      y0 += (h - this.h0 * scale) / 2;
    }
    const aspect = {x: x0, y: y0, width: sx, height: sy};
    this.drawChildren(canvas, this.bgNode, aspect);
    this.drawChildren(canvas, this.fgNode, aspect);
  }

  drawChildren(canvas, node, aspect) {
    if (!node) return;
    for (const child of node.children) this.drawNode(canvas, child, aspect);
  }

  drawNode(canvas, node, aspect) {
    const name = node.name;
    const x0 = aspect.x;
    const y0 = aspect.y;
    const sx = aspect.width;
    const sy = aspect.height;
    const minScale = Math.min(sx, sy);
    const X = (key) => x0 + attrNum(node, key) * sx;
    const Y = (key) => y0 + attrNum(node, key) * sy;
    if (name === 'save') canvas.save();
    else if (name === 'restore') canvas.restore();
    else if (name === 'path') {
      canvas.begin();
      for (const child of node.children) this.drawNode(canvas, child, aspect);
    } else if (name === 'close') canvas.close();
    else if (name === 'move') canvas.moveTo(X('x'), Y('y'));
    else if (name === 'line') canvas.lineTo(X('x'), Y('y'));
    else if (name === 'quad') {
      canvas.quadTo(X('x1'), Y('y1'), X('x2'), Y('y2'));
    } else if (name === 'curve') {
      canvas.curveTo(X('x1'), Y('y1'), X('x2'), Y('y2'), X('x3'), Y('y3'));
    } else if (name === 'arc') {
      canvas.arcTo(
        attrNum(node, 'rx') * sx,
        attrNum(node, 'ry') * sy,
        attrNum(node, 'x-axis-rotation'),
        attrNum(node, 'large-arc-flag'),
        attrNum(node, 'sweep-flag'),
        X('x'),
        Y('y'),
      );
    } else if (name === 'rect') {
      canvas.rect(X('x'), Y('y'), attrNum(node, 'w') * sx, attrNum(node, 'h') * sy);
    } else if (name === 'roundrect') {
      const width = attrNum(node, 'w') * sx;
      const height = attrNum(node, 'h') * sy;
      let arcsize = attrNum(node, 'arcsize');
      if (arcsize === 0) arcsize = 10;
      const radius = Math.min(width, height) * arcsize / 100;
      canvas.roundrect(X('x'), Y('y'), width, height, radius, radius);
    } else if (name === 'ellipse') {
      canvas.ellipse(X('x'), Y('y'), attrNum(node, 'w') * sx, attrNum(node, 'h') * sy);
    } else if (name === 'text') {
      const str = node.attrs.str || '';
      if (!str) return;
      let rotation = node.attrs.vertical === '1' ? -90 : 0;
      rotation -= Number(node.attrs.rotation || 0);
      canvas.text(
        X('x'), Y('y'), 0, 0, str,
        node.attrs.align || 'left',
        node.attrs.valign || 'top',
        0, null, 0, 0, rotation,
      );
    } else if (name === 'include-shape') {
      const nested = stencilMap[String(node.attrs.name || '').toLowerCase()];
      if (nested) {
        nested.drawShape(
          canvas, null, X('x'), Y('y'),
          attrNum(node, 'w') * sx, attrNum(node, 'h') * sy,
        );
      }
    } else if (name === 'fillstroke' || name === 'fillstrokecolor') canvas.fillAndStroke();
    else if (name === 'fill') canvas.fill();
    else if (name === 'stroke') canvas.stroke();
    else if (name === 'fontsize') canvas.setFontSize(attrNum(node, 'size') * minScale);
    else if (name === 'fontstyle') canvas.setFontStyle(attrNum(node, 'style'));
  }
}

function registerShapes(shapesNode) {
  const pkg = String(shapesNode.attrs.name || '').toLowerCase();
  const prefix = pkg ? `${pkg}.` : '';
  for (const shape of shapesNode.children) {
    if (shape.name !== 'shape' || !shape.attrs.name) continue;
    const stencilName = String(shape.attrs.name).replace(/ /g, '_').toLowerCase();
    stencilMap[prefix + stencilName] = new NestedStencil(shape);
  }
}

function visitStencilNode(node) {
  if (node.name === 'shapes') registerShapes(node);
  for (const child of node.children || []) visitStencilNode(child);
}

const stencilRoot = path.join(webapp, 'stencils');
for (const file of fs.readdirSync(stencilRoot, {recursive: true}).filter((name) => String(name).endsWith('.xml')).sort()) {
  try {
    visitStencilNode(parseXml(fs.readFileSync(path.join(stencilRoot, file), 'utf8')));
  } catch (_) {}
}

function mxShape() {
  this.style = {};
  this.scale = 1;
  this.strokewidth = 1;
  this.direction = null;
  this.rotation = 0;
  this.flipH = false;
  this.flipV = false;
}
mxShape.prototype.getTextRotation = function() { return 0; };
mxShape.prototype.isHtmlAllowed = function() { return false; };
mxShape.prototype.getRotation = function() {
  return Number(this.rotation) || 0;
};
mxShape.prototype.getShapeRotation = function() {
  let rot = this.getRotation();
  if (this.direction === mxConstants.DIRECTION_NORTH) rot += 270;
  else if (this.direction === mxConstants.DIRECTION_WEST) rot += 180;
  else if (this.direction === mxConstants.DIRECTION_SOUTH) rot += 90;
  return rot;
};
mxShape.prototype.configureCanvas = function() {};
mxShape.prototype.updateTransform = function(c, x, y, w, h) {
  c.rotate(this.getShapeRotation(), this.flipH, this.flipV, x + w / 2, y + h / 2);
};
mxShape.prototype.getArcSize = function(w, h) { return Math.min(w, h) * 0.1; };
mxShape.prototype.paintBackground = function() {};
mxShape.prototype.paintForeground = function() {};
mxShape.prototype.paintVertexShape = function(c, x, y, w, h) {
  this.paintBackground(c, x, y, w, h);
  if (c && c.setShadow) c.setShadow(false);
  this.paintForeground(c, x, y, w, h);
};
mxShape.prototype.isHorizontal = function() { return true; };
mxShape.prototype.createMarker = function() { return null; };
mxShape.prototype.paintEdgeShape = function(c, pts) {
  if (!pts || pts.length < 2) return;
  c.begin();
  c.moveTo(pts[0].x, pts[0].y);
  for (let i = 1; i < pts.length; i++) c.lineTo(pts[i].x, pts[i].y);
  c.stroke();
};

const baseNames = [
  'mxActor', 'mxArrow', 'mxArrowConnector', 'mxCloud', 'mxConnector',
  'mxCylinder', 'mxDoubleEllipse', 'mxEllipse', 'mxHexagon', 'mxImageShape',
  'mxLabel', 'mxLine', 'mxPolyline', 'mxRectangleShape', 'mxRhombus',
  'mxSwimlane', 'mxTriangle',
];

function createBaseShape(name) {
  function BaseShape() { mxShape.call(this); }
  BaseShape.prototype = Object.create(mxShape.prototype);
  BaseShape.prototype.constructor = BaseShape;
  if (name === 'mxEllipse' || name === 'mxDoubleEllipse' || name === 'mxCloud') {
    BaseShape.prototype.paintVertexShape = function(c, x, y, w, h) {
      c.ellipse(x, y, w, h); c.fillAndStroke();
    };
  } else if (name === 'mxTriangle') {
    BaseShape.prototype.paintVertexShape = function(c, x, y, w, h) {
      c.translate(x, y);
      c.begin();
      c.moveTo(0, 0);
      c.lineTo(w, 0.5 * h);
      c.lineTo(0, h);
      c.close();
      c.fillAndStroke();
    };
  } else if (name === 'mxHexagon') {
    BaseShape.prototype.paintVertexShape = function(c, x, y, w, h) {
      c.translate(x, y);
      c.begin();
      c.moveTo(0.25 * w, 0);
      c.lineTo(0.75 * w, 0);
      c.lineTo(w, 0.5 * h);
      c.lineTo(0.75 * w, h);
      c.lineTo(0.25 * w, h);
      c.lineTo(0, 0.5 * h);
      c.close();
      c.fillAndStroke();
    };
  } else if (name === 'mxRhombus') {
    BaseShape.prototype.paintVertexShape = function(c, x, y, w, h) {
      c.begin();
      c.moveTo(x + w / 2, y);
      c.lineTo(x + w, y + h / 2);
      c.lineTo(x + w / 2, y + h);
      c.lineTo(x, y + h / 2);
      c.close();
      c.fillAndStroke();
    };
  } else if (name === 'mxActor') {
    BaseShape.prototype.paintVertexShape = function(c, x, y, w, h) {
      c.translate(x, y);
      const width = w / 3;
      c.begin();
      c.moveTo(0, h);
      c.curveTo(0, 3 * h / 5, 0, 2 * h / 5, w / 2, 2 * h / 5);
      c.curveTo(w / 2 - width, 2 * h / 5, w / 2 - width, 0, w / 2, 0);
      c.curveTo(w / 2 + width, 0, w / 2 + width, 2 * h / 5, w / 2, 2 * h / 5);
      c.curveTo(w, 2 * h / 5, w, 3 * h / 5, w, h);
      c.close();
      c.fillAndStroke();
    };
  } else if (name === 'mxCylinder') {
    BaseShape.prototype.paintVertexShape = function(c, x, y, w, h) {
      c.ellipse(x, y, w, h * 0.25); c.fillAndStroke();
      c.rect(x, y + h * 0.125, w, h * 0.75); c.fillAndStroke();
      c.ellipse(x, y + h * 0.75, w, h * 0.25); c.fillAndStroke();
    };
  } else if (
    name === 'mxRectangleShape' || name === 'mxLabel' || name === 'mxSwimlane' ||
    name === 'mxConnector' || name === 'mxLine' || name === 'mxPolyline' ||
    name === 'mxArrow' || name === 'mxArrowConnector' || name === 'mxImageShape'
  ) {
    BaseShape.prototype.paintVertexShape = function(c, x, y, w, h) {
      c.rect(x, y, w, h); c.fillAndStroke();
    };
  }
  return BaseShape;
}

function loadMxConstants(source) {
  const constants = {};
  const re = /^\s*([A-Z][A-Z0-9_]+):\s*(?:'([^']*)'|"([^"]*)"|(-?\d+(?:\.\d+)?))/gm;
  let match;
  while ((match = re.exec(source))) {
    constants[match[1]] = match[2] ?? match[3] ?? Number(match[4]);
  }
  return new Proxy(constants, {
    get(target, key) {
      return key in target ? target[key] : String(key);
    },
  });
}

const mxConstants = loadMxConstants(
  fs.readFileSync(path.join(webapp, 'mxgraph/src/util/mxConstants.js'), 'utf8'),
);

const registry = {};
function registerShape(name, ctor) { registry[name] = ctor; }
function getShape(name) { return name != null ? registry[name] : null; }
const mxCellRenderer = {
  defaultShapes: registry,
  registerShape,
  getShape,
};
mxCellRenderer.prototype = mxCellRenderer;

const mxUtilsBase = {
  extend(child, parent) {
    child.prototype = Object.create((parent || mxShape).prototype);
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
  parseColorList(value) {
    return String(value || '').split(/[\s,]+/).filter(Boolean);
  },
  clone(value) { return {...value}; },
  bind(scope, fn) { return fn.bind(scope); },
  isNode() { return false; },
  indexOf(arr, item) { return arr.indexOf(item); },
};
const mxUtils = new Proxy(mxUtilsBase, {
  get(target, prop) {
    if (prop in target) return target[prop];
    return () => null;
  },
});

const shapeContext = {
  mxShape,
  mxUtils,
  mxCellRenderer,
  mxConstants,
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
    addStencil(name, stencil) { stencilMap[String(name).toLowerCase()] = stencil; },
    getStencil(name) {
      if (name == null || name === '') return null;
      return stencilMap[String(name).toLowerCase()] || null;
    },
  },
  GRAPH_IMAGE_PATH: '',
  Graph: Object.assign(function Graph() {}, {
    handleFactory: {},
    createHandle() { return {}; },
    createSvgImage() { return {src: ''}; },
    prototype: {
      getPreferredSizeForCell() { return null; },
      getTableLines() { return []; },
      paintTableCellLines() {},
      isTableRow() { return false; },
      isTable() { return false; },
      isTableCell() { return false; },
      getCellGeometry() { return null; },
    },
  }),
  document: {createElement: () => ({style: {}, getElementsByTagName: () => []})},
  window: {},
  console,
  mxEvent: {addListener() {}, removeListener() {}, consume() {}, addGestureListeners() {}},
  mxPerimeter: new Proxy({}, {get: () => function() { return null; }}),
  mxEdgeStyle: new Proxy({}, {get: () => function() {}}),
  mxStyleRegistry: {putValue() {}, getValue() { return null; }},
  mxResources: {get: (key) => String(key)},
  mxObjectIdentity: {get: (obj) => String(obj)},
  mxGraph: function() {},
  mxHandle: function() {},
  mxSvgCanvas2D: function() {},
  mxText: function() {},
  mxCellEditor: function() {},
  mxEdgeHandler: function() {},
  mxElbowEdgeHandler: function() {},
  mxVertexHandler: function() {},
};
for (const name of baseNames) shapeContext[name] = createBaseShape(name);
const RectShape = shapeContext.mxRectangleShape;
const EllipseShape = shapeContext.mxEllipse;
const RhombusShape = shapeContext.mxRhombus;
registerShape(mxConstants.SHAPE_RECTANGLE, RectShape);
registerShape(mxConstants.SHAPE_ELLIPSE, EllipseShape);
registerShape(mxConstants.SHAPE_DOUBLE_ELLIPSE, shapeContext.mxDoubleEllipse);
registerShape(mxConstants.SHAPE_RHOMBUS, RhombusShape);
registerShape(mxConstants.SHAPE_IMAGE, RectShape);
registerShape(mxConstants.SHAPE_LABEL, RectShape);
registerShape(mxConstants.SHAPE_ACTOR, shapeContext.mxActor);
registerShape(mxConstants.SHAPE_CYLINDER, shapeContext.mxCylinder);
registerShape(mxConstants.SHAPE_SWIMLANE, shapeContext.mxSwimlane);
registerShape(mxConstants.SHAPE_TRIANGLE, shapeContext.mxTriangle);
registerShape(mxConstants.SHAPE_HEXAGON, shapeContext.mxHexagon);
registerShape(mxConstants.SHAPE_CLOUD, shapeContext.mxCloud);
registerShape(mxConstants.SHAPE_LINE, shapeContext.mxLine);
registerShape('rect', RectShape);
registerShape('image', RectShape);
registerShape('cylinder', shapeContext.mxCylinder);
vm.createContext(shapeContext);

function recursiveJs(root) {
  return fs.readdirSync(root, {recursive: true})
    .filter((name) => name.endsWith('.js')).sort();
}

const loadErrors = [];
function loadJs(file, source) {
  try {
    vm.runInContext(fs.readFileSync(source, 'utf8'), shapeContext, {filename: file});
  } catch (error) {
    loadErrors.push({file, error: String(error)});
  }
}
loadJs(
  'js/grapheditor/Shapes.js',
  path.join(webapp, 'js/grapheditor/Shapes.js'),
);
mxShape.prototype.getTitleSize = function() {
  return mxUtils.getNumber(this.style, mxConstants.STYLE_STARTSIZE, 0);
};
if (!registry['mxgraph.basic.rect']) registerShape('mxgraph.basic.rect', RectShape);
if (!registry.note) registerShape('note', RectShape);
if (!registry.folder) registerShape('folder', RectShape);
if (!registry.partialRectangle) registerShape('partialRectangle', RectShape);
if (!registry.cylinder) registerShape('cylinder', shapeContext.mxCylinder);
for (const file of recursiveJs(shapeRoot)) {
  loadJs(file, path.join(shapeRoot, file));
}

function Geometry(x, y, width, height) {
  this.x = x; this.y = y; this.width = width; this.height = height;
  this.relative = false;
  this.sourcePoint = null;
  this.targetPoint = null;
  this.offset = null;
  this.points = [];
}
Geometry.prototype.setTerminalPoint = function(point, isSource) {
  const pt = {
    x: Number(point && point.x) || 0,
    y: Number(point && point.y) || 0,
  };
  if (isSource) this.sourcePoint = pt;
  else this.targetPoint = pt;
};
Geometry.prototype.clone = function() { return Object.assign(new Geometry(), this); };
function Cell(value, geometry, style) {
  this.value = value; this.geometry = geometry; this.style = style;
  this.children = []; this.edges = [];
}
Cell.prototype.insert = function(cell) {
  cell.parent = this;
  this.children.push(cell);
  return cell;
};
Cell.prototype.insertEdge = function(cell) {
  this.edges.push(cell);
  return cell;
};
Cell.prototype.clone = function() {
  const copy = new Cell(
    this.value,
    this.geometry ? this.geometry.clone() : this.geometry,
    this.style,
  );
  copy.vertex = this.vertex;
  copy.edge = this.edge;
  copy.children = [];
  copy.edges = [];
  return copy;
};
Cell.prototype.setValue = function(value) { this.value = value; };
Cell.prototype.setAttribute = function() {};
Cell.prototype.setEdge = function(value) { this.edge = !!value; };
Cell.prototype.setVertex = function(value) { this.vertex = !!value; };
Cell.prototype.setConnectable = function() {};
Cell.prototype.setStyle = function(style) { this.style = style; };

const factoryErrors = [];
const notVertexKinds = {};
const notVertexSamples = [];

function Sidebar() { this.palettes = []; }
Sidebar.prototype.setCurrentSearchEntryLibrary = function() {};
Sidebar.prototype.getTagsForStencil = function() { return []; };
Sidebar.prototype.filterTags = function(tags) { return tags; };
Sidebar.prototype.cloneCell = function(cell, value) {
  if (!cell) return cell;
  const clone = cell.clone();
  if (value != null) clone.value = value;
  return clone;
};
Sidebar.prototype.addEntry = function(tags, factory) {
  const self = this;
  const wrapped = function(content) {
    try {
      return factory.call(self, content);
    } catch (error) {
      if (factoryErrors.length < 40) {
        factoryErrors.push({tags: String(tags || ''), error: String(error && error.stack || error)});
      }
      return wrapped.entry;
    }
  };
  wrapped.entry = {kind: 'factory', tags};
  return wrapped;
};
Sidebar.prototype.addDataEntry = function(tags, width, height, title, data) {
  const wrapped = function() { return wrapped.entry; };
  wrapped.entry = {kind: 'data', tags, width, height, title, data};
  return wrapped;
};
Sidebar.prototype.createVertexTemplate = function(style, width, height, value, title) {
  const cell = new Cell(value != null ? value : '', new Geometry(0, 0, width, height), style);
  cell.vertex = true;
  return this.createVertexTemplateFromCells([cell], width, height, title);
};
Sidebar.prototype.createEdgeTemplate = function(style, width, height, value, title) {
  const cell = new Cell(value != null ? value : '', new Geometry(0, 0, width, height), style);
  cell.geometry.setTerminalPoint({x: 0, y: height}, true);
  cell.geometry.setTerminalPoint({x: width, y: 0}, false);
  cell.geometry.relative = true;
  cell.edge = true;
  return this.createEdgeTemplateFromCells([cell], width, height, title);
};
Sidebar.prototype.createVertexTemplateFromData = function(data, width, height, title) {
  return {kind: 'data', width, height, title, data};
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
      try { return fn.call(this, {}) || fn.entry; } catch (error) {
        if (factoryErrors.length < 40) {
          factoryErrors.push({id, error: String(error && error.stack || error)});
        }
        return fn.entry;
      }
    }
    return fn.entry;
  }).filter(Boolean);
  this.palettes.push({id, title, entries});
};
Sidebar.prototype.addPalette = function(id, title, expanded, factory) {
  const entries = [];
  try { factory({appendChild(value) { if (value) entries.push(value); }}); } catch (error) {
    if (factoryErrors.length < 40) {
      factoryErrors.push({id, error: String(error && error.stack || error)});
    }
  }
  this.palettes.push({id, title, entries});
};

const sidebarContext = {
  Sidebar,
  mxConstants,
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
    .filter((name) => {
      if (before.has(name) || !/^add.*Palette/.test(name)) return false;
      // Sub-palettes such as addBPMN2ChoreographiesPalette(gn, r, sb)
      // close over the sb argument. Calling them with no args overwrites
      // the working palette that the zero-arg root method already added.
      return Sidebar.prototype[name].length === 0;
    });
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
const unregisteredShapes = {};
const noGeometryEntries = [];
const noPainterEntries = [];
const paintErrors = [];
const paintErrorCounts = {};
function isGenericStyle(style) {
  const name = style && style.shape;
  return name == null || name === '' || name === 'rectangle' ||
    name === 'label' || name === 'image' || name === 'rect';
}

function recordingCanvas() {
  const canvas = new CanvasRecorder();
  return new Proxy(canvas, {
    get(target, prop) {
      if (prop in target) {
        const value = target[prop];
        return typeof value === 'function' ? value.bind(target) : value;
      }
      if (typeof prop === 'string') return function() {};
      return undefined;
    },
  });
}

function paintRegistered(style, width, height, canvas, x = 0, y = 0, opts = {}) {
  const name = style && style.shape;
  let ctor = name ? registry[name] : null;
  if (!ctor && opts.allowStencil && name) {
    const stencil = stencilMap[String(name).toLowerCase()];
    if (stencil) {
      stencil.drawShape(canvas, null, x, y, width, height);
      canvas.finish();
      return {};
    }
  }
  if (!ctor && opts.fallbackRect) {
    ctor = registry[mxConstants.SHAPE_RECTANGLE];
  }
  if (!ctor) return null;
  if (typeof ctor.prototype.paintVertexShape !== 'function') return null;
  const shape = new ctor(null, style.fillColor || '#ffffff', style.strokeColor || '#000000', 1);
  shape.style = style;
  shape.scale = 1;
  shape.bounds = {x, y, width, height};
  shape.direction = style.direction || null;
  shape.rotation = Number(style.rotation) || 0;
  shape.flipH = style.flipH == 1;
  shape.flipV = style.flipV == 1;
  if (shape.direction === mxConstants.DIRECTION_NORTH ||
      shape.direction === mxConstants.DIRECTION_SOUTH) {
    const tmp = shape.flipH;
    shape.flipH = shape.flipV;
    shape.flipV = tmp;
  }
  shape.state = {
    style,
    view: {
      graph: {
        getLabel() { return ''; },
        isCellCollapsed() { return false; },
        isCellConnected() { return false; },
        isSwimlane() { return false; },
        getTableLines() { return []; },
        paintTableCellLines() {},
        isTableRow() { return false; },
        isTable() { return false; },
        isTableCell() { return false; },
        getCellGeometry() { return null; },
        getModel() { return {getChildCount() { return 0; }, getChildAt() { return null; }}; },
      },
    },
  };
  canvas.save();
  try {
    if (typeof shape.updateTransform === 'function') {
      shape.updateTransform(canvas, x, y, width, height);
    }
    shape.paintVertexShape(canvas, x, y, width, height);
  } catch (error) {
    canvas.restore();
    renderStats.paintError++;
    const errorKey = String(error);
    paintErrorCounts[errorKey] = (paintErrorCounts[errorKey] || 0) + 1;
    if (paintErrors.length < 30) paintErrors.push({shape: name, error: String(error)});
    if (opts.fallbackRect) {
      canvas.rect(x, y, width, height);
      canvas.fillAndStroke();
      canvas.finish();
      return {};
    }
    return false;
  }
  canvas.restore();
  canvas.finish();
  return shape;
}

function decompressDrawio(data) {
  try {
    const buf = Buffer.from(String(data).replace(/\s+/g, ''), 'base64');
    let raw;
    try {
      raw = zlib.inflateRawSync(buf);
    } catch (_) {
      raw = zlib.inflateSync(buf);
    }
    const latin1 = raw.toString('latin1');
    if (latin1.startsWith('%')) return decodeURIComponent(latin1);
    const utf8 = raw.toString('utf8');
    if (utf8.includes('<')) return utf8;
    return decodeURIComponent(latin1);
  } catch (_) {
    return null;
  }
}

function cellLabel(value) {
  const source = String(value ?? '');
  if (!source) return '';
  const stripped = source
    .replace(/<br\s*\/?>/gi, ' ')
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/\s+/g, ' ')
    .trim();
  return stripped;
}

function cellsFromMxGraphXml(xml) {
  const parsed = parseXml(xml);
  const nodes = [];
  function walk(node) {
    if (node.name === 'mxCell') nodes.push(node);
    for (const child of node.children || []) walk(child);
  }
  walk(parsed);
  const byId = {};
  for (const node of nodes) byId[node.attrs.id] = node;
  const converted = {};
  for (const node of nodes) {
    const geoNode = (node.children || []).find((child) => child.name === 'mxGeometry');
    const geometry = geoNode
      ? new Geometry(
          Number(geoNode.attrs.x) || 0,
          Number(geoNode.attrs.y) || 0,
          Number(geoNode.attrs.width) || 0,
          Number(geoNode.attrs.height) || 0,
        )
      : new Geometry(0, 0, 0, 0);
    if (geoNode) {
      geometry.relative = geoNode.attrs.relative === '1';
      for (const child of geoNode.children || []) {
        if (child.name === 'mxPoint') {
          const pt = {x: Number(child.attrs.x) || 0, y: Number(child.attrs.y) || 0};
          if (child.attrs.as === 'sourcePoint') geometry.sourcePoint = pt;
          else if (child.attrs.as === 'targetPoint') geometry.targetPoint = pt;
          else if (child.attrs.as === 'offset') geometry.offset = pt;
          else geometry.points.push(pt);
        } else if (child.name === 'Array') {
          for (const pt of child.children || []) {
            if (pt.name === 'mxPoint') {
              geometry.points.push({x: Number(pt.attrs.x) || 0, y: Number(pt.attrs.y) || 0});
            }
          }
        }
      }
    }
    let style = node.attrs.style || '';
    if (node.attrs.edge === '1' && !/(?:^|;)edge=/.test(style)) {
      style = `edge=1;${style}`;
    }
    const cell = new Cell(node.attrs.value, geometry, style);
    if (node.attrs.vertex === '1') cell.vertex = true;
    if (node.attrs.edge === '1') cell.edge = true;
    converted[node.attrs.id] = cell;
  }
  const tops = [];
  for (const node of nodes) {
    const isVertex = node.attrs.vertex === '1';
    const isEdge = node.attrs.edge === '1';
    if (!isVertex && !isEdge) continue;
    const cell = converted[node.attrs.id];
    const parent = byId[node.attrs.parent];
    if (parent && parent.attrs.vertex === '1' && converted[parent.attrs.id]) {
      converted[parent.attrs.id].children.push(cell);
    } else {
      tops.push(cell);
    }
  }
  return tops;
}

function mxPts(x, y) {
  return new shapeContext.mxPoint(x, y);
}

function edgePoints(style, width, height, x, y, geometry) {
  if (geometry && (geometry.sourcePoint || geometry.targetPoint ||
      (geometry.points && geometry.points.length))) {
    const pts = [];
    const start = geometry.sourcePoint || {x: 0, y: height / 2};
    pts.push(mxPts(x + start.x, y + start.y));
    for (const p of geometry.points || []) {
      pts.push(mxPts(x + p.x, y + p.y));
    }
    const end = geometry.targetPoint || {x: width, y: height / 2};
    pts.push(mxPts(x + end.x, y + end.y));
    return pts;
  }
  return [mxPts(x, y + height / 2), mxPts(x + width, y + height / 2)];
}

function paintArrowHead(canvas, type, fill, tipX, tipY, fromX, fromY) {
  if (!type || type === 'none') return;
  const dx = tipX - fromX;
  const dy = tipY - fromY;
  const len = Math.hypot(dx, dy) || 1;
  const ux = dx / len;
  const uy = dy / len;
  const size = 10;
  const bx = tipX - ux * size;
  const by = tipY - uy * size;
  const px = -uy * size * 0.5;
  const py = ux * size * 0.5;
  if (type === 'oval' || type === 'halfCircle') {
    canvas.ellipse(tipX - size * 0.4, tipY - size * 0.4, size * 0.8, size * 0.8);
    if (String(fill) === '0' || type === 'halfCircle') canvas.stroke();
    else canvas.fillAndStroke();
    return;
  }
  canvas.begin();
  canvas.moveTo(tipX, tipY);
  canvas.lineTo(bx + px, by + py);
  canvas.lineTo(bx - px, by - py);
  canvas.close();
  if (type === 'open' || String(fill) === '0') canvas.stroke();
  else canvas.fillAndStroke();
}

function paintConnectorLine(style, pts, canvas) {
  if (!pts || pts.length < 2) return;
  if (style.dashed === '1') canvas.operations.push('<dashed dashed="1"/>');
  canvas.begin();
  canvas.moveTo(pts[0].x, pts[0].y);
  for (let i = 1; i < pts.length; i++) canvas.lineTo(pts[i].x, pts[i].y);
  canvas.stroke();
  const start = pts[0];
  const startFrom = pts[1] || start;
  const end = pts[pts.length - 1];
  const endFrom = pts[pts.length - 2] || end;
  const startArrow = style.startArrow || 'none';
  const endArrow = style.endArrow == null ? 'classic' : style.endArrow;
  paintArrowHead(canvas, startArrow, style.startFill, start.x, start.y, startFrom.x, startFrom.y);
  paintArrowHead(canvas, endArrow, style.endFill, end.x, end.y, endFrom.x, endFrom.y);
  canvas.finish();
}

function paintEdge(style, width, height, canvas, x = 0, y = 0, geometry = null) {
  const pts = edgePoints(style, width, height, x, y, geometry);
  const name = style && style.shape;
  const ctor = name ? registry[name] : null;
  if (ctor && typeof ctor.prototype.paintEdgeShape === 'function') {
    const shape = new ctor(null, style.fillColor || '#ffffff', style.strokeColor || '#000000', 1);
    shape.style = style;
    shape.scale = 1;
    shape.bounds = {x, y, width, height};
    try {
      if (style.dashed === '1') canvas.operations.push('<dashed dashed="1"/>');
      shape.paintEdgeShape(canvas, pts);
      canvas.finish();
      return true;
    } catch (error) {
      renderStats.paintError++;
      const errorKey = String(error);
      paintErrorCounts[errorKey] = (paintErrorCounts[errorKey] || 0) + 1;
      if (paintErrors.length < 30) paintErrors.push({shape: name, error: String(error)});
    }
  }
  if (ctor && typeof ctor.prototype.paintVertexShape === 'function' && !isGenericStyle(style)) {
    const result = paintRegistered(style, width, height, canvas, x, y);
    return !!result;
  }
  paintConnectorLine(style, pts, canvas);
  return true;
}

function cellOrigin(geometry, parentX, parentY, parentW, parentH, isEdge) {
  const g = geometry || {};
  if (isEdge) {
    // Relative x/y on edges is the label offset, not the stroke origin.
    return {x: parentX, y: parentY};
  }
  if (g.relative) {
    const ox = g.offset ? Number(g.offset.x) || 0 : 0;
    const oy = g.offset ? Number(g.offset.y) || 0 : 0;
    return {
      x: parentX + (Number(g.x) || 0) * parentW + ox,
      y: parentY + (Number(g.y) || 0) * parentH + oy,
    };
  }
  return {
    x: parentX + (Number(g.x) || 0),
    y: parentY + (Number(g.y) || 0),
  };
}

function applyStackLayout(cell, style) {
  if (!cell || style.childLayout !== 'stackLayout') return;
  const kids = (cell.children || []).filter((child) =>
    child && child.geometry && !child.edge && !child.geometry.relative);
  if (kids.length < 2) return;
  if (kids.some((child) =>
    (Number(child.geometry.x) || 0) !== 0 || (Number(child.geometry.y) || 0) !== 0)) {
    return;
  }
  const horizontal = style.horizontalStack === '1';
  const startSize = Math.max(0, Number(style.startSize) || 0);
  let x = horizontal ? startSize : 0;
  let y = horizontal ? 0 : startSize;
  for (const child of kids) {
    child.geometry.x = x;
    child.geometry.y = y;
    if (horizontal) x += Math.max(0, Number(child.geometry.width) || 0);
    else y += Math.max(0, Number(child.geometry.height) || 0);
  }
}

function paintCellTree(cells, canvas, width, height) {
  let painted = false;
  const visit = (cell, parentX, parentY, parentW, parentH) => {
    if (!cell) return;
    if (cell.geometry) {
      const cellStyle = parseStyle(cell.style);
      const isEdge = !!(cell.edge || cellStyle.edge === '1');
      applyStackLayout(cell, cellStyle);
      const origin = cellOrigin(
        cell.geometry, parentX, parentY, parentW, parentH, isEdge,
      );
      const x = origin.x;
      const y = origin.y;
      const cellWidth = Math.max(1, Number(cell.geometry.width) || parentW);
      const cellHeight = Math.max(1, Number(cell.geometry.height) || parentH);
      if (isEdge) {
        if (paintEdge(cellStyle, cellWidth, cellHeight, canvas, x, y, cell.geometry)) {
          painted = true;
        }
      } else {
        const result = paintRegistered(
          cellStyle, cellWidth, cellHeight, canvas, x, y,
          {fallbackRect: true, allowStencil: true},
        );
        if (result) painted = true;
      }
      const label = cellLabel(cell.value);
      if (label) {
        canvas.text(x, y, cellWidth, cellHeight, label, 'center', 'middle');
        painted = true;
      }
      const next = [...(cell.children || [])];
      for (const edge of cell.edges || []) {
        if (!next.includes(edge)) next.push(edge);
      }
      for (const child of next) visit(child, x, y, cellWidth, cellHeight);
    } else {
      for (const child of cell.children || []) {
        visit(child, parentX, parentY, parentW, parentH);
      }
    }
  };
  for (const cell of cells || []) visit(cell, 0, 0, width, height);
  return painted;
}

function entrySize(entry) {
  const width = Number(entry.width);
  const height = Number(entry.height);
  return {
    width: Number.isFinite(width) && width > 0 ? width : 100,
    height: Number.isFinite(height) && height > 0
      ? height
      : (height === 0 ? 1 : 100),
  };
}

function missVertex(kind, entry) {
  renderStats.notVertex++;
  const key = kind || 'unknown';
  notVertexKinds[key] = (notVertexKinds[key] || 0) + 1;
  if (notVertexSamples.length < 25) {
    notVertexSamples.push({
      kind: key,
      title: entry && entry.title,
      tags: entry && entry.tags,
    });
  }
}

function renderEntry(entry) {
  const canvas = recordingCanvas();
  let width;
  let height;
  let shape = null;
  let style = null;
  if (entry.kind === 'vertex') {
    if (typeof entry.style !== 'string') { renderStats.noStyle++; return null; }
    style = parseStyle(entry.style);
    if (isGenericStyle(style)) {
      renderStats.unregistered++;
      const key = String(style.shape || '(none)');
      unregisteredShapes[key] = (unregisteredShapes[key] || 0) + 1;
      return null;
    }
    const ctor = registry[style.shape];
    if (!ctor) {
      renderStats.unregistered++;
      const key = String(style.shape || '(none)');
      unregisteredShapes[key] = (unregisteredShapes[key] || 0) + 1;
      return null;
    }
    if (typeof ctor.prototype.paintVertexShape !== 'function') {
      renderStats.noPainter++;
      if (noPainterEntries.length < 20) {
        noPainterEntries.push({title: entry.title, shape: style.shape});
      }
      return null;
    }
    width = Math.max(1, Number(entry.width) || 100);
    height = Math.max(1, Number(entry.height) || 100);
    shape = paintRegistered(style, width, height, canvas);
    if (!shape) return null;
  } else if (entry.kind === 'data' && entry.data) {
    ({width, height} = entrySize(entry));
    const xml = decompressDrawio(entry.data);
    if (!xml || !paintCellTree(cellsFromMxGraphXml(xml), canvas, width, height)) {
      missVertex('data', entry);
      return null;
    }
  } else if (entry.kind === 'vertex-cells' && Array.isArray(entry.cells)) {
    ({width, height} = entrySize(entry));
    if (!paintCellTree(entry.cells, canvas, width, height)) {
      missVertex('vertex-cells', entry);
      return null;
    }
  } else if (entry.kind === 'edge') {
    if (typeof entry.style !== 'string') { renderStats.noStyle++; return null; }
    style = parseStyle(entry.style);
    ({width, height} = entrySize(entry));
    const geometry = new Geometry(0, 0, width, height);
    geometry.setTerminalPoint({x: 0, y: height}, true);
    geometry.setTerminalPoint({x: width, y: 0}, false);
    geometry.relative = true;
    paintEdge(style, width, height, canvas, 0, 0, geometry);
  } else if (entry.kind === 'edge-cells' && Array.isArray(entry.cells)) {
    ({width, height} = entrySize(entry));
    if (!paintCellTree(entry.cells, canvas, width, height)) {
      missVertex('edge-cells', entry);
      return null;
    }
  } else {
    missVertex(entry.kind || 'unknown', entry);
    return null;
  }
  if (!canvas.operations.some((operation) => /<(move|line|curve|quad|arc|rect|roundrect|ellipse|text)\b/.test(operation))) {
    renderStats.noGeometry++;
    if (noGeometryEntries.length < 40) {
      noGeometryEntries.push({
        title: entry.title,
        shape: style && style.shape,
        ops: canvas.operations.slice(0, 20),
      });
    }
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
      const base = String(entry.title || 'Unnamed Shape').replace(/\s+/g, ' ').trim() || 'Unnamed Shape';
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
  unregisteredShapes,
  noGeometryEntries,
  noPainterEntries,
  factoryErrors,
  notVertexKinds,
  notVertexSamples,
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
