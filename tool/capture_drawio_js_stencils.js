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

// mxStylesheet.getCellStyle: a token without '=' is a named style from
// styles/default.xml (swimlane, ellipse, rhombus, triangle, line, …).
const namedStyles = {};

function parseStyle(source, base) {
  const style = base ? {...base} : {};
  for (const part of String(source || '').split(';')) {
    const token = part.trim();
    if (!token) continue;
    const split = token.indexOf('=');
    if (split >= 0) {
      const key = token.slice(0, split);
      let value = token.slice(split + 1);
      // ArchiMate Work Package concatenates `shape=mxgraph.archimate.` +
      // `rounded=1` without a semicolon, so mxGraph sees shape value
      // `mxgraph.archimate.rounded=1`. Split the extra key so the vertex
      // is a rounded rectangle LibreOffice can parse.
      if (key === 'shape') {
        const extra = value.lastIndexOf('=');
        if (extra > 0) {
          const tail = value.slice(0, extra);
          const extraVal = value.slice(extra + 1);
          const dot = tail.lastIndexOf('.');
          const extraKey = dot >= 0 ? tail.slice(dot + 1) : '';
          if (/^[A-Za-z]+$/.test(extraKey) && extraVal !== '') {
            style[extraKey] = extraVal;
            value = dot >= 0 ? tail.slice(0, dot) : tail;
          }
        }
      }
      style[key] = value;
    } else if (namedStyles[token]) {
      Object.assign(style, namedStyles[token]);
    }
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

function isNoneColor(value) {
  return value == null || String(value).toLowerCase() === 'none';
}

function stylePaintColor(value, fallback) {
  if (value == null || value === '') return fallback;
  if (String(value).toLowerCase() === 'default') return fallback;
  return isNoneColor(value) ? null : value;
}

class CanvasRecorder {
  constructor() {
    this.tx = 0;
    this.ty = 0;
    this.sx = 1;
    this.sy = 1;
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
      tx: this.tx, ty: this.ty, sx: this.sx, sy: this.sy, state: {...this.state},
      rotTheta: this.rotTheta, rotFlipH: this.rotFlipH, rotFlipV: this.rotFlipV,
      rotCx: this.rotCx, rotCy: this.rotCy,
    });
  }

  restore() {
    const saved = this.stack.pop();
    if (saved) {
      this.tx = saved.tx;
      this.ty = saved.ty;
      this.sx = saved.sx;
      this.sy = saved.sy;
      this.state = saved.state;
      this.rotTheta = saved.rotTheta;
      this.rotFlipH = saved.rotFlipH;
      this.rotFlipV = saved.rotFlipV;
      this.rotCx = saved.rotCx;
      this.rotCy = saved.rotCy;
    }
  }

  translate(x, y) {
    this.tx += (Number(x) || 0) * this.sx;
    this.ty += (Number(y) || 0) * this.sy;
  }
  scale(sx, sy) {
    const x = Number(sx);
    const y = sy == null ? x : Number(sy);
    if (!Number.isFinite(x) || !Number.isFinite(y)) return;
    this.sx *= x;
    this.sy *= y;
  }
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
    let x = (Number(px) || 0) * this.sx + this.tx;
    let y = (Number(py) || 0) * this.sy + this.ty;
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
      rx: (Number(rx) || 0) * Math.abs(this.sx),
      ry: (Number(ry) || 0) * Math.abs(this.sy),
      'x-axis-rotation': (Number(rotation) || 0) + this.rotTheta,
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
    this.operations.push(`<rect x="${number(p.x)}" y="${number(p.y)}" w="${number(w * this.sx)}" h="${number(h * this.sy)}"/>`);
  }
  roundrect(x, y, w, h, rx, ry) {
    this.finishPath();
    if (Math.abs(Number(w) || 0) < 1e-9 && Math.abs(Number(h) || 0) < 1e-9) return;
    if (this.isRotated()) {
      this.poly([[x, y], [x + w, y], [x + w, y + h], [x, y + h]]);
      return;
    }
    const p = this.map(x, y);
    const sw = w * this.sx;
    const sh = h * this.sy;
    const arc = Math.min(100, 100 * Math.max(Number(rx) || 0, Number(ry) || 0) *
      Math.max(Math.abs(this.sx), Math.abs(this.sy)) /
      Math.max(1e-9, Math.min(Math.abs(sw), Math.abs(sh))));
    this.operations.push(`<roundrect x="${number(p.x)}" y="${number(p.y)}" w="${number(sw)}" h="${number(sh)}" arcsize="${number(arc)}"/>`);
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
    this.operations.push(`<ellipse x="${number(p.x)}" y="${number(p.y)}" w="${number(w * this.sx)}" h="${number(h * this.sy)}"/>`);
  }
  fill() {
    this.finishPath();
    if (isNoneColor(this.state.fillColor)) return;
    this.operations.push('<fill/>');
  }
  stroke() {
    this.finishPath();
    if (isNoneColor(this.state.strokeColor)) return;
    this.operations.push('<stroke/>');
  }
  fillAndStroke() {
    this.finishPath();
    const noFill = isNoneColor(this.state.fillColor);
    const noStroke = isNoneColor(this.state.strokeColor);
    if (noFill && noStroke) return;
    if (noFill) this.operations.push('<stroke/>');
    else if (noStroke) this.operations.push('<fill/>');
    else this.operations.push('<fillstroke/>');
  }
  // SVG icons stay vector. Nested mxStencil painters also call image();
  // dropping the whole parent would hide Kubernetes / AWS product icons
  // that still have vector geometry. PNG/JPEG (IBM VPC Floating IP's
  // SVG-in-PNG, clipart) become <image src="data:…"> so the Dart decoder
  // can emit Visio ForeignData that LibreOffice's collectForeignData paints.
  image(x, y, w, h, src, aspect) {
    if (paintSvgImage(this, x, y, w, h, src, aspect !== false)) return;
    paintRaster(this, x, y, w, h, src);
  }
  raster(x, y, w, h, mime, b64) {
    this.finishPath();
    if (!(Number(w) > 0 && Number(h) > 0) || !b64) return;
    const p = this.map(x, y);
    this.operations.push(
      `<image x="${number(p.x)}" y="${number(p.y)}" w="${number(w * this.sx)}" h="${number(h * this.sy)}" src="${xmlEscape(`data:${mime};base64,${b64}`)}"/>`,
    );
  }
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
  setFillColor(value) {
    this.state.fillColor = isNoneColor(value) ? null : value;
  }
  setStrokeColor(value) {
    this.state.strokeColor = isNoneColor(value) ? null : value;
  }
  setStrokeWidth(value) { this.state.strokeWidth = value; }
  setDashed(value) {
    this.state.dashed = !!value;
    if (!this.state.dashed) return;
    this.finishPath();
    this.operations.push('<dashed dashed="1"/>');
  }
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

  x(value) { return (Number(value) || 0) * this.sx + this.tx; }
  y(value) { return (Number(value) || 0) * this.sy + this.ty; }
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
  const re = /([A-Za-z_:][\w:.-]*)\s*=\s*(?:"([^"]*)"|'([^']*)')/g;
  let match;
  while ((match = re.exec(source))) attrs[match[1]] = decodeXml(match[2] ?? match[3]);
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

function xmlLocalName(name) {
  const value = String(name || '');
  const colon = value.indexOf(':');
  return (colon >= 0 ? value.slice(colon + 1) : value).toLowerCase();
}

function looksLikeBase64(payload) {
  const compact = String(payload).replace(/\s+/g, '');
  return compact.length >= 8 && /^[A-Za-z0-9+/]+=*$/.test(compact);
}

function loadRasterSource(src) {
  if (src == null || src === '') return null;
  const raw = String(src).trim();
  const data = /^data:(image\/[a-z0-9.+-]+)(;base64)?,([\s\S]+)$/i.exec(raw);
  if (data) {
    let mime = data[1].toLowerCase();
    if (mime === 'image/jpg') mime = 'image/jpeg';
    let payload = data[3].replace(/\s+/g, '');
    try {
      if (data[2] || looksLikeBase64(payload)) {
        Buffer.from(payload, 'base64');
        return {mime, base64: payload};
      }
      payload = Buffer.from(decodeURIComponent(data[3])).toString('base64');
      return {mime, base64: payload};
    } catch (_) {
      return null;
    }
  }
  const rel = raw.replace(/^\.\//, '').split('?')[0];
  if (!/\.(png|jpe?g|gif|webp|bmp)$/i.test(rel)) return null;
  const file = path.join(webapp, rel);
  if (!fs.existsSync(file)) return null;
  const ext = path.extname(rel).toLowerCase();
  const mime = ext === '.jpg' || ext === '.jpeg' ? 'image/jpeg'
    : ext === '.gif' ? 'image/gif'
    : ext === '.webp' ? 'image/webp'
    : ext === '.bmp' ? 'image/bmp'
    : 'image/png';
  return {mime, base64: fs.readFileSync(file).toString('base64')};
}

function paintRaster(canvas, x, y, w, h, src) {
  const rec = loadRasterSource(src);
  if (!rec) return false;
  canvas.raster(x, y, w, h, rec.mime, rec.base64);
  return true;
}

function loadSvgSource(src) {
  if (src == null || src === '') return null;
  const raw = String(src).trim();
  if (/^data:image\/svg\+xml/i.test(raw)) {
    const comma = raw.indexOf(',');
    if (comma < 0) return null;
    const header = raw.slice(0, comma);
    const payload = raw.slice(comma + 1);
    try {
      let text;
      const compact = payload.replace(/\s+/g, '');
      if (/;base64/i.test(header) || (looksLikeBase64(compact) && compact.startsWith('PHN2Zy'))) {
        text = Buffer.from(compact, 'base64').toString('utf8');
      } else {
        text = decodeURIComponent(compact);
        if (!text.includes('<svg') && looksLikeBase64(compact)) {
          text = Buffer.from(compact, 'base64').toString('utf8');
        }
      }
      return text.includes('<svg') ? text : null;
    } catch (_) {
      return null;
    }
  }
  if (/^data:/i.test(raw)) return null;
  const rel = raw.replace(/^\.\//, '').split('?')[0];
  if (!/\.svg$/i.test(rel) && !rel.startsWith('img/')) return null;
  const file = path.join(webapp, rel);
  if (!fs.existsSync(file)) return null;
  const text = fs.readFileSync(file, 'utf8');
  return text.includes('<svg') ? text : null;
}

function svgPresentation(node, inherited) {
  const style = {...inherited};
  for (const part of String(node.attrs.style || '').split(';')) {
    const token = part.trim();
    if (!token) continue;
    const split = token.indexOf(':');
    if (split < 0) continue;
    style[token.slice(0, split).trim()] = token.slice(split + 1).trim();
  }
  if (node.attrs.fill != null) style.fill = node.attrs.fill;
  if (node.attrs.stroke != null) style.stroke = node.attrs.stroke;
  if (node.attrs.opacity != null) style.opacity = node.attrs.opacity;
  return style;
}

function svgPaintIsNone(value) {
  if (value == null || value === '') return false;
  const v = String(value).trim().toLowerCase();
  return v === 'none' || v === 'transparent';
}

function applySvgPaint(canvas, style, kind) {
  canvas.save();
  if (kind === 'fill' || kind === 'fillstroke') {
    if (svgPaintIsNone(style.fill)) {
      canvas.setFillColor(null);
    } else if (style.fill != null && style.fill !== '') {
      const fill = String(style.fill).trim();
      if (!/^currentcolor$/i.test(fill) && !/^url\(/i.test(fill)) {
        canvas.setFillColor(fill);
      }
    }
  } else {
    canvas.setFillColor(null);
  }
  if (kind === 'stroke' || kind === 'fillstroke') {
    if (svgPaintIsNone(style.stroke)) canvas.setStrokeColor(null);
    else if (style.stroke != null && style.stroke !== '') {
      const stroke = String(style.stroke).trim();
      if (!/^currentcolor$/i.test(stroke) && !/^url\(/i.test(stroke)) {
        canvas.setStrokeColor(stroke);
      }
    }
  } else {
    canvas.setStrokeColor(null);
  }
  if (kind === 'fill') canvas.fill();
  else if (kind === 'stroke') canvas.stroke();
  else canvas.fillAndStroke();
  canvas.restore();
}

function svgDrawKind(style, defaultFill) {
  const fill = style.fill == null ? defaultFill : style.fill;
  const stroke = style.stroke;
  const fillNone = svgPaintIsNone(fill) || fill === '';
  const strokeNone = stroke == null || stroke === '' || svgPaintIsNone(stroke);
  if (fillNone && strokeNone) return null;
  if (fillNone) return 'stroke';
  if (strokeNone) return 'fill';
  return 'fillstroke';
}

function parseSvgNumbers(source) {
  const values = [];
  const re = /[+-]?(?:\d*\.\d+|\d+)(?:[eE][+-]?\d+)?/g;
  let match;
  while ((match = re.exec(String(source || '')))) values.push(Number(match[0]));
  return values;
}

function paintSvgPath(canvas, d) {
  const tokens = [];
  const re = /([MmLlHhVvCcSsQqTtAaZz])|([+-]?(?:\d*\.\d+|\d+)(?:[eE][+-]?\d+)?)/g;
  let match;
  while ((match = re.exec(String(d || '')))) {
    if (match[1]) tokens.push(match[1]);
    else tokens.push(Number(match[2]));
  }
  if (!tokens.length) return false;
  canvas.begin();
  let x = 0;
  let y = 0;
  let sx = 0;
  let sy = 0;
  let lastCmd = '';
  let c2x = 0;
  let c2y = 0;
  let q1x = 0;
  let q1y = 0;
  let i = 0;
  const take = () => Number(tokens[i++]) || 0;
  while (i < tokens.length) {
    let cmd = tokens[i];
    const prevCmd = lastCmd;
    if (typeof cmd === 'string') {
      i++;
      lastCmd = cmd;
    } else {
      cmd = lastCmd;
      if (!cmd) break;
    }
    const rel = cmd === cmd.toLowerCase();
    const up = cmd.toUpperCase();
    if (up === 'Z') {
      canvas.close();
      x = sx;
      y = sy;
      continue;
    }
    if (up === 'M') {
      x = rel ? x + take() : take();
      y = rel ? y + take() : take();
      canvas.moveTo(x, y);
      sx = x;
      sy = y;
      lastCmd = rel ? 'l' : 'L';
      continue;
    }
    if (up === 'L') {
      x = rel ? x + take() : take();
      y = rel ? y + take() : take();
      canvas.lineTo(x, y);
    } else if (up === 'H') {
      x = rel ? x + take() : take();
      canvas.lineTo(x, y);
    } else if (up === 'V') {
      y = rel ? y + take() : take();
      canvas.lineTo(x, y);
    } else if (up === 'C') {
      const x1 = rel ? x + take() : take();
      const y1 = rel ? y + take() : take();
      const x2 = rel ? x + take() : take();
      const y2 = rel ? y + take() : take();
      x = rel ? x + take() : take();
      y = rel ? y + take() : take();
      canvas.curveTo(x1, y1, x2, y2, x, y);
      c2x = x2;
      c2y = y2;
    } else if (up === 'S') {
      const x2 = rel ? x + take() : take();
      const y2 = rel ? y + take() : take();
      const nx = rel ? x + take() : take();
      const ny = rel ? y + take() : take();
      const prevUp = String(prevCmd).toUpperCase();
      const x1 = prevUp === 'C' || prevUp === 'S' ? 2 * x - c2x : x;
      const y1 = prevUp === 'C' || prevUp === 'S' ? 2 * y - c2y : y;
      canvas.curveTo(x1, y1, x2, y2, nx, ny);
      c2x = x2;
      c2y = y2;
      x = nx;
      y = ny;
    } else if (up === 'Q') {
      const x1 = rel ? x + take() : take();
      const y1 = rel ? y + take() : take();
      x = rel ? x + take() : take();
      y = rel ? y + take() : take();
      canvas.quadTo(x1, y1, x, y);
      q1x = x1;
      q1y = y1;
    } else if (up === 'T') {
      const prevUp = String(prevCmd).toUpperCase();
      const x1 = prevUp === 'Q' || prevUp === 'T' ? 2 * x - q1x : x;
      const y1 = prevUp === 'Q' || prevUp === 'T' ? 2 * y - q1y : y;
      x = rel ? x + take() : take();
      y = rel ? y + take() : take();
      canvas.quadTo(x1, y1, x, y);
      q1x = x1;
      q1y = y1;
    } else if (up === 'A') {
      const rx = take();
      const ry = take();
      const rot = take();
      const large = take();
      const sweep = take();
      x = rel ? x + take() : take();
      y = rel ? y + take() : take();
      canvas.arcTo(rx, ry, rot, large, sweep, x, y);
    } else {
      break;
    }
  }
  return true;
}

const svgSkip = new Set([
  'defs', 'title', 'desc', 'metadata', 'namedview', 'rdf', 'work', 'clippath',
  'filter', 'lineargradient', 'radialgradient', 'stop', 'style', 'script',
  'marker', 'text', 'tspan',
]);

function findSvgById(node, id) {
  if (!node || !id) return null;
  if (node.attrs && node.attrs.id === id) return node;
  for (const child of node.children || []) {
    const found = findSvgById(child, id);
    if (found) return found;
  }
  return null;
}

function paintSvgNode(canvas, node, inherited, root) {
  const name = xmlLocalName(node.name);
  if (svgSkip.has(name)) return false;
  const style = svgPresentation(node, inherited);
  let painted = false;
  if (name === 'use') {
    const href = node.attrs.href || node.attrs['xlink:href'] || '';
    const id = String(href).replace(/^#/, '');
    const target = findSvgById(root, id);
    if (!target || target === node) return false;
    canvas.save();
    const ox = Number(node.attrs.x) || 0;
    const oy = Number(node.attrs.y) || 0;
    if (ox || oy) canvas.translate(ox, oy);
    painted = paintSvgNode(canvas, target, style, root);
    canvas.restore();
    return painted;
  }
  if (name === 'image') {
    const href = node.attrs.href || node.attrs['xlink:href'] || '';
    const ix = Number(node.attrs.x) || 0;
    const iy = Number(node.attrs.y) || 0;
    const iw = Number(node.attrs.width) || 0;
    const ih = Number(node.attrs.height) || 0;
    if (!(iw > 0 && ih > 0)) return false;
    return paintRaster(canvas, ix, iy, iw, ih, href);
  }
  if (name === 'g' || name === 'svg' || name === 'a' || name === 'symbol') {
    for (const child of node.children || []) {
      if (paintSvgNode(canvas, child, style, root)) painted = true;
    }
    return painted;
  }
  const kind = svgDrawKind(style, name === 'path' || name === 'circle' ||
    name === 'ellipse' || name === 'rect' || name === 'polygon' ? '#000' : 'none');
  if (!kind) return false;
  if (name === 'path') {
    if (!paintSvgPath(canvas, node.attrs.d)) return false;
  } else if (name === 'circle') {
    const cx = Number(node.attrs.cx) || 0;
    const cy = Number(node.attrs.cy) || 0;
    const r = Number(node.attrs.r) || 0;
    if (!(r > 0)) return false;
    canvas.ellipse(cx - r, cy - r, r * 2, r * 2);
  } else if (name === 'ellipse') {
    const cx = Number(node.attrs.cx) || 0;
    const cy = Number(node.attrs.cy) || 0;
    const rx = Number(node.attrs.rx) || 0;
    const ry = Number(node.attrs.ry) || 0;
    if (!(rx > 0 && ry > 0)) return false;
    canvas.ellipse(cx - rx, cy - ry, rx * 2, ry * 2);
  } else if (name === 'rect') {
    const x = Number(node.attrs.x) || 0;
    const y = Number(node.attrs.y) || 0;
    const w = Number(node.attrs.width) || 0;
    const h = Number(node.attrs.height) || 0;
    const rx = Number(node.attrs.rx) || 0;
    if (!(w > 0 && h > 0)) return false;
    if (rx > 0) canvas.roundrect(x, y, w, h, rx, rx);
    else canvas.rect(x, y, w, h);
  } else if (name === 'polygon' || name === 'polyline') {
    const nums = parseSvgNumbers(node.attrs.points);
    if (nums.length < 4) return false;
    canvas.begin();
    canvas.moveTo(nums[0], nums[1]);
    for (let i = 2; i + 1 < nums.length; i += 2) canvas.lineTo(nums[i], nums[i + 1]);
    if (name === 'polygon') canvas.close();
  } else if (name === 'line') {
    canvas.begin();
    canvas.moveTo(Number(node.attrs.x1) || 0, Number(node.attrs.y1) || 0);
    canvas.lineTo(Number(node.attrs.x2) || 0, Number(node.attrs.y2) || 0);
  } else {
    return false;
  }
  applySvgPaint(canvas, {...style, fill: style.fill == null ? '#000' : style.fill}, kind);
  return true;
}

function findSvgRoot(node) {
  if (!node) return null;
  if (xmlLocalName(node.name) === 'svg') return node;
  for (const child of node.children || []) {
    const found = findSvgRoot(child);
    if (found) return found;
  }
  return null;
}

function paintSvgImage(canvas, x, y, w, h, src, preserveAspect) {
  const xml = loadSvgSource(src);
  if (!xml) return false;
  const root = findSvgRoot(parseXml(xml));
  if (!root) return false;
  const vb = parseSvgNumbers(root.attrs.viewBox);
  const vw = vb.length >= 4 ? vb[2] : (Number(root.attrs.width) || w || 1);
  const vh = vb.length >= 4 ? vb[3] : (Number(root.attrs.height) || h || 1);
  const vx = vb.length >= 4 ? vb[0] : 0;
  const vy = vb.length >= 4 ? vb[1] : 0;
  if (!(vw > 0 && vh > 0 && w > 0 && h > 0)) return false;
  let dw = w;
  let dh = h;
  let dx = x;
  let dy = y;
  if (preserveAspect) {
    const scale = Math.min(w / vw, h / vh);
    dw = vw * scale;
    dh = vh * scale;
    dx = x + (w - dw) / 2;
    dy = y + (h - dh) / 2;
  }
  canvas.save();
  canvas.translate(dx, dy);
  canvas.scale(dw / vw, dh / vh);
  canvas.translate(-vx, -vy);
  const painted = paintSvgNode(canvas, root, {}, root);
  canvas.restore();
  return painted;
}

function loadNamedStyles(xmlPath) {
  const parsed = parseXml(fs.readFileSync(xmlPath, 'utf8'));
  const sheet = parsed.children.find((node) => node.name === 'mxStylesheet') || parsed;
  const raw = {};
  for (const node of sheet.children) {
    if (node.name !== 'add' || !node.attrs.as) continue;
    const style = {};
    for (const child of node.children) {
      if (child.name === 'add' && child.attrs.as) {
        style[child.attrs.as] = child.attrs.value;
      }
    }
    raw[node.attrs.as] = {style, extend: node.attrs.extend};
  }
  const resolved = {};
  const resolving = new Set();
  function resolve(name) {
    if (resolved[name]) return resolved[name];
    const entry = raw[name];
    if (!entry) return {};
    if (resolving.has(name)) return {};
    resolving.add(name);
    const base = entry.extend ? resolve(entry.extend) : {};
    resolving.delete(name);
    resolved[name] = {...base, ...entry.style};
    return resolved[name];
  }
  for (const name of Object.keys(raw)) resolve(name);
  return resolved;
}

Object.assign(
  namedStyles,
  loadNamedStyles(path.join(webapp, 'styles/default.xml')),
);

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

  computeAspect(style, x, y, w, h, direction) {
    let x0 = x;
    let y0 = y;
    let sx = w / this.w0;
    let sy = h / this.h0;
    const inverse = direction === 'north' || direction === 'south';
    if (inverse) {
      sy = w / this.h0;
      sx = h / this.w0;
      const delta = (w - h) / 2;
      x0 += delta;
      y0 -= delta;
    }
    if (this.aspect === 'fixed') {
      sy = Math.min(sx, sy);
      sx = sy;
      if (inverse) {
        x0 += (h - this.w0 * sx) / 2;
        y0 += (w - this.h0 * sy) / 2;
      } else {
        x0 += (w - this.w0 * sx) / 2;
        y0 += (h - this.h0 * sy) / 2;
      }
    }
    return {x: x0, y: y0, width: sx, height: sy};
  }

  drawShape(canvas, shape, x, y, w, h) {
    if (!(w > 0) || !(h > 0)) return;
    const direction = shape && shape.style ? shape.style.direction : null;
    const aspect = this.computeAspect(shape && shape.style, x, y, w, h, direction);
    this.drawChildren(canvas, this.bgNode, aspect, shape);
    this.drawChildren(canvas, this.fgNode, aspect, shape);
  }

  drawChildren(canvas, node, aspect, shape) {
    if (!node) return;
    for (const child of node.children) this.drawNode(canvas, child, aspect, shape);
  }

  drawNode(canvas, node, aspect, shape) {
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
      for (const child of node.children) this.drawNode(canvas, child, aspect, shape);
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
          canvas, shape, X('x'), Y('y'),
          attrNum(node, 'w') * sx, attrNum(node, 'h') * sy,
        );
      }
    } else if (name === 'fillstroke' || name === 'fillstrokecolor') canvas.fillAndStroke();
    else if (name === 'fill') canvas.fill();
    else if (name === 'stroke') canvas.stroke();
    else if (name === 'fillcolor') {
      // mxStencil.parseColor: only 'none' / 'fill' / 'stroke' change
      // NoFill vs fill. Hex palette colours stay the project fill so
      // LibreOffice still paints FillForegnd.
      const color = node.attrs.color;
      if (color === 'none') canvas.setFillColor(null);
      else if (color === 'stroke' && shape) canvas.setFillColor(shape.stroke);
      else if (color === 'fill' && shape) canvas.setFillColor(shape.fill);
    } else if (name === 'strokecolor') {
      const color = node.attrs.color;
      if (color === 'none') canvas.setStrokeColor(null);
      else if (color === 'fill' && shape) canvas.setStrokeColor(shape.fill);
      else if (color === 'stroke' && shape) canvas.setStrokeColor(shape.stroke);
    } else if (name === 'dashed') canvas.setDashed(node.attrs.dashed === '1');
    else if (name === 'dashpattern') canvas.setDashed(true);
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

function mxPoint(x, y) {
  this.x = x;
  this.y = y;
}
mxPoint.prototype.clone = function() { return new mxPoint(this.x, this.y); };

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
mxShape.prototype.apply = function(state) {
  this.state = state;
  if (!state || !state.style) return;
  this.style = state.style;
  this.fill = mxUtils.getValue(this.style, mxConstants.STYLE_FILLCOLOR, this.fill);
  this.stroke = mxUtils.getValue(this.style, mxConstants.STYLE_STROKECOLOR, this.stroke);
  this.strokewidth = mxUtils.getNumber(this.style, mxConstants.STYLE_STROKEWIDTH, this.strokewidth);
  this.rotation = mxUtils.getValue(this.style, mxConstants.STYLE_ROTATION, this.rotation);
  this.direction = mxUtils.getValue(this.style, mxConstants.STYLE_DIRECTION, this.direction);
  this.flipH = mxUtils.getValue(this.style, mxConstants.STYLE_FLIPH, 0) == 1;
  this.flipV = mxUtils.getValue(this.style, mxConstants.STYLE_FLIPV, 0) == 1;
};
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
mxShape.prototype.configureCanvas = function(c, x, y, w, h) {
  if (c.setFillColor) c.setFillColor(this.fill);
  if (c.setStrokeColor) c.setStrokeColor(this.stroke);
  if (this.isDashed && c.setDashed) c.setDashed(true);
};
mxShape.prototype.addPoints = function(c, pts, rounded, arcSize, close, exclude, initialMove) {
  if (pts == null || pts.length === 0) return;
  initialMove = initialMove != null ? initialMove : true;
  const pe = pts[pts.length - 1];
  if (close && rounded) {
    pts = pts.slice();
    const p0 = pts[0];
    pts.splice(0, 0, new mxPoint(pe.x + (p0.x - pe.x) / 2, pe.y + (p0.y - pe.y) / 2));
  }
  let pt = pts[0];
  let i = 1;
  if (initialMove) c.moveTo(pt.x, pt.y);
  else c.lineTo(pt.x, pt.y);
  while (i < (close ? pts.length : pts.length - 1)) {
    let tmp = pts[mxUtils.mod(i, pts.length)];
    const dx = pt.x - tmp.x;
    const dy = pt.y - tmp.y;
    if (rounded && (dx !== 0 || dy !== 0) && (exclude == null || mxUtils.indexOf(exclude, i - 1) < 0)) {
      let dist = Math.sqrt(dx * dx + dy * dy);
      const nx1 = dx * Math.min(arcSize, dist / 2) / dist;
      const ny1 = dy * Math.min(arcSize, dist / 2) / dist;
      c.lineTo(tmp.x + nx1, tmp.y + ny1);
      let next = pts[mxUtils.mod(i + 1, pts.length)];
      while (i < pts.length - 2 && Math.round(next.x - tmp.x) === 0 && Math.round(next.y - tmp.y) === 0) {
        next = pts[mxUtils.mod(i + 2, pts.length)];
        i++;
      }
      const dx2 = next.x - tmp.x;
      const dy2 = next.y - tmp.y;
      dist = Math.max(1, Math.sqrt(dx2 * dx2 + dy2 * dy2));
      const nx2 = dx2 * Math.min(arcSize, dist / 2) / dist;
      const ny2 = dy2 * Math.min(arcSize, dist / 2) / dist;
      const x2 = tmp.x + nx2;
      const y2 = tmp.y + ny2;
      c.quadTo(tmp.x, tmp.y, x2, y2);
      tmp = new mxPoint(x2, y2);
    } else {
      c.lineTo(tmp.x, tmp.y);
    }
    pt = tmp;
    i++;
  }
  if (close) c.close();
  else c.lineTo(pe.x, pe.y);
};
mxShape.prototype.updateTransform = function(c, x, y, w, h) {
  c.rotate(this.getShapeRotation(), this.flipH, this.flipV, x + w / 2, y + h / 2);
};
mxShape.prototype.getArcSize = function(w, h) {
  if (mxUtils.getValue(this.style, mxConstants.STYLE_ABSOLUTE_ARCSIZE, 0) == '1') {
    return Math.min(w / 2, Math.min(h / 2, mxUtils.getValue(
      this.style, mxConstants.STYLE_ARCSIZE, mxConstants.LINE_ARCSIZE,
    ) / 2));
  }
  const f = mxUtils.getValue(
    this.style, mxConstants.STYLE_ARCSIZE, mxConstants.RECTANGLE_ROUNDING_FACTOR * 100,
  ) / 100;
  return Math.min(w * f, h * f);
};
mxShape.prototype.paintBackground = function() {};
mxShape.prototype.paintForeground = function() {};
mxShape.prototype.paintVertexShape = function(c, x, y, w, h) {
  this.paintBackground(c, x, y, w, h);
  if (c && c.setShadow) c.setShadow(false);
  this.paintForeground(c, x, y, w, h);
};
mxShape.prototype.isHorizontal = function() { return true; };
mxShape.prototype.paintGlassEffect = function() {};
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
  if (name === 'mxEllipse') {
    BaseShape.prototype.paintVertexShape = function(c, x, y, w, h) {
      c.ellipse(x, y, w, h); c.fillAndStroke();
    };
  } else if (name === 'mxDoubleEllipse') {
    BaseShape.prototype.paintBackground = function(c, x, y, w, h) {
      c.ellipse(x, y, w, h);
      c.fillAndStroke();
    };
    BaseShape.prototype.paintForeground = function(c, x, y, w, h) {
      if (this.outline) return;
      const margin = mxUtils.getValue(
        this.style, mxConstants.STYLE_MARGIN,
        Math.min(3 + this.strokewidth, Math.min(w / 5, h / 5)),
      );
      x += margin;
      y += margin;
      w -= 2 * margin;
      h -= 2 * margin;
      if (w > 0 && h > 0) c.ellipse(x, y, w, h);
      c.stroke();
    };
  } else if (name === 'mxCloud') {
    BaseShape.prototype.paintVertexShape = function(c, x, y, w, h) {
      c.translate(x, y);
      c.begin();
      this.redrawPath(c, x, y, w, h);
      c.fillAndStroke();
    };
    BaseShape.prototype.redrawPath = function(c, x, y, w, h) {
      c.moveTo(0.25 * w, 0.25 * h);
      c.curveTo(0.05 * w, 0.25 * h, 0, 0.5 * h, 0.16 * w, 0.55 * h);
      c.curveTo(0, 0.66 * h, 0.18 * w, 0.9 * h, 0.31 * w, 0.8 * h);
      c.curveTo(0.4 * w, h, 0.7 * w, h, 0.8 * w, 0.8 * h);
      c.curveTo(w, 0.8 * h, w, 0.6 * h, 0.875 * w, 0.5 * h);
      c.curveTo(w, 0.3 * h, 0.8 * w, 0.1 * h, 0.625 * w, 0.2 * h);
      c.curveTo(0.5 * w, 0.05 * h, 0.3 * w, 0.05 * h, 0.25 * w, 0.25 * h);
      c.close();
    };
  } else if (name === 'mxTriangle') {
    BaseShape.prototype.paintVertexShape = function(c, x, y, w, h) {
      c.translate(x, y);
      c.begin();
      this.redrawPath(c, x, y, w, h);
      c.fillAndStroke();
    };
    BaseShape.prototype.redrawPath = function(c, x, y, w, h) {
      const arcSize = mxUtils.getValue(this.style, mxConstants.STYLE_ARCSIZE, mxConstants.LINE_ARCSIZE) / 2;
      this.addPoints(c, [new mxPoint(0, 0), new mxPoint(w, 0.5 * h), new mxPoint(0, h)], this.isRounded, arcSize, true);
    };
  } else if (name === 'mxHexagon') {
    BaseShape.prototype.paintVertexShape = function(c, x, y, w, h) {
      c.translate(x, y);
      c.begin();
      this.redrawPath(c, x, y, w, h);
      c.fillAndStroke();
    };
    BaseShape.prototype.redrawPath = function(c, x, y, w, h) {
      const arcSize = mxUtils.getValue(this.style, mxConstants.STYLE_ARCSIZE, mxConstants.LINE_ARCSIZE) / 2;
      this.addPoints(c, [
        new mxPoint(0.25 * w, 0), new mxPoint(0.75 * w, 0), new mxPoint(w, 0.5 * h),
        new mxPoint(0.75 * w, h), new mxPoint(0.25 * w, h), new mxPoint(0, 0.5 * h),
      ], this.isRounded, arcSize, true);
    };
  } else if (name === 'mxRhombus') {
    BaseShape.prototype.paintVertexShape = function(c, x, y, w, h) {
      const hw = w / 2;
      const hh = h / 2;
      const arcSize = mxUtils.getValue(this.style, mxConstants.STYLE_ARCSIZE, mxConstants.LINE_ARCSIZE) / 2;
      c.begin();
      this.addPoints(c, [
        new mxPoint(x + hw, y), new mxPoint(x + w, y + hh),
        new mxPoint(x + hw, y + h), new mxPoint(x, y + hh),
      ], this.isRounded, arcSize, true);
      c.fillAndStroke();
    };
  } else if (name === 'mxActor') {
    BaseShape.prototype.paintVertexShape = function(c, x, y, w, h) {
      c.translate(x, y);
      c.begin();
      this.redrawPath(c, x, y, w, h);
      c.fillAndStroke();
    };
    BaseShape.prototype.redrawPath = function(c, x, y, w, h) {
      const width = w / 3;
      c.moveTo(0, h);
      c.curveTo(0, 3 * h / 5, 0, 2 * h / 5, w / 2, 2 * h / 5);
      c.curveTo(w / 2 - width, 2 * h / 5, w / 2 - width, 0, w / 2, 0);
      c.curveTo(w / 2 + width, 0, w / 2 + width, 2 * h / 5, w / 2, 2 * h / 5);
      c.curveTo(w, 2 * h / 5, w, 3 * h / 5, w, h);
      c.close();
    };
  } else if (name === 'mxCylinder') {
    BaseShape.prototype.maxHeight = 40;
    BaseShape.prototype.getCylinderSize = function(x, y, w, h) {
      return Math.min(this.maxHeight, Math.round(h / 5));
    };
    BaseShape.prototype.paintVertexShape = function(c, x, y, w, h) {
      c.translate(x, y);
      c.begin();
      this.redrawPath(c, x, y, w, h, false);
      c.fillAndStroke();
      if (!this.outline) {
        c.setShadow(false);
        c.begin();
        this.redrawPath(c, x, y, w, h, true);
        c.stroke();
      }
    };
    BaseShape.prototype.redrawPath = function(c, x, y, w, h, isForeground) {
      const dy = this.getCylinderSize(x, y, w, h);
      if ((isForeground && this.fill != null) || (!isForeground && this.fill == null)) {
        c.moveTo(0, dy);
        c.curveTo(0, 2 * dy, w, 2 * dy, w, dy);
        if (!isForeground) {
          c.stroke();
          c.begin();
        }
      }
      if (!isForeground) {
        c.moveTo(0, dy);
        c.curveTo(0, -dy / 3, w, -dy / 3, w, dy);
        c.lineTo(w, h - dy);
        c.curveTo(w, h + dy / 3, 0, h + dy / 3, 0, h - dy);
        c.close();
      }
    };
  } else if (name === 'mxLine') {
    BaseShape.prototype.paintVertexShape = function(c, x, y, w, h) {
      c.begin();
      const vertical = this.vertical ||
        (this.style && (this.style.vertical == 1 || this.style.vertical === '1'));
      if (vertical) {
        const mid = x + w / 2;
        c.moveTo(mid, y);
        c.lineTo(mid, y + h);
      } else {
        const mid = y + h / 2;
        c.moveTo(x, mid);
        c.lineTo(x + w, mid);
      }
      c.stroke();
    };
  } else if (name === 'mxRectangleShape') {
    BaseShape.prototype.paintBackground = function(c, x, y, w, h) {
      if (this.isRounded) {
        const r = this.getArcSize(w, h);
        c.roundrect(x, y, w, h, r, r);
      } else {
        c.rect(x, y, w, h);
      }
      c.fillAndStroke();
    };
    BaseShape.prototype.isRoundable = function() { return true; };
  } else if (
    name === 'mxLabel' ||
    name === 'mxConnector' || name === 'mxPolyline' ||
    name === 'mxImageShape'
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
  mod(n, m) { return ((n % m) + m) % m; },
  relativeCcw(x1, y1, x2, y2, px, py) {
    x2 -= x1;
    y2 -= y1;
    px -= x1;
    py -= y1;
    let ccw = px * y2 - py * x2;
    if (ccw === 0.0) {
      ccw = px * x2 + py * y2;
      if (ccw > 0.0) {
        px -= x2;
        py -= y2;
        ccw = px * x2 + py * y2;
        if (ccw < 0.0) ccw = 0.0;
      }
    }
    return ccw < 0.0 ? -1 : (ccw > 0.0 ? 1 : 0);
  },
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
  mxPoint,
  mxRectangle: function(x, y, width, height) {
    this.x = x; this.y = y; this.width = width; this.height = height;
  },
  mxConnectionConstraint: function(point, perimeter, name, dx, dy) {
    this.point = point; this.perimeter = perimeter; this.name = name;
    this.dx = dx || 0; this.dy = dy || 0;
  },
  mxClient: {IS_FF: false, IS_SF: false},
  // Real registry so Shapes.js / mxER.js `addMarker('ERmany', …)` stick.
  // A no-op stub discarded crow's-foot factories, and LibreOffice only
  // calls VisioDocument::parse, so Draw never saw those arrow heads.
  mxMarker: {
    markers: Object.create(null),
    addMarker(type, funct) { this.markers[type] = funct; },
    createMarker(canvas, shape, type, pe, unitX, unitY, size, source, sw, filled) {
      const funct = this.markers[type];
      return funct != null
        ? funct(canvas, shape, type, pe, unitX, unitY, size, source, sw, filled)
        : null;
    },
  },
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
registerShape(mxConstants.SHAPE_ARROW, shapeContext.mxArrow);
registerShape(mxConstants.SHAPE_ARROW_CONNECTOR, shapeContext.mxArrowConnector);
registerShape('rect', RectShape);
registerShape('image', shapeContext.mxImageShape || RectShape);
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
function loadOfficialCtor(relPath, ctorName) {
  const file = `mxgraph/src/shape/${relPath}`;
  try {
    vm.runInContext(
      fs.readFileSync(path.join(webapp, file), 'utf8') +
        `\nthis.${ctorName} = ${ctorName};`,
      shapeContext,
      {filename: file},
    );
  } catch (error) {
    loadErrors.push({file, error: String(error)});
  }
}
// Official edge arrows (filled block / thick connector) and swimlane title
// bar. Capture stubs used a polyline or a full rectangle, so Draw never saw
// those types through VisioDocument::parse.
loadOfficialCtor('mxImageShape.js', 'mxImageShape');
registerShape(mxConstants.SHAPE_IMAGE, shapeContext.mxImageShape || RectShape);
registerShape('image', shapeContext.mxImageShape || RectShape);
// Official mxLabel paints the style=image icon (UML Item 2, Misc Label).
// The capture stub mapped `label` to a rectangle, so those gears never
// reached VisioDocument::parse.
loadOfficialCtor('mxLabel.js', 'mxLabel');
registerShape(mxConstants.SHAPE_LABEL, shapeContext.mxLabel || RectShape);
registerShape('label', shapeContext.mxLabel || RectShape);
loadOfficialCtor('mxArrow.js', 'mxArrow');
loadOfficialCtor('mxArrowConnector.js', 'mxArrowConnector');
loadOfficialCtor('mxSwimlane.js', 'mxSwimlane');
loadJs('mxgraph/src/shape/mxMarker.js', path.join(webapp, 'mxgraph/src/shape/mxMarker.js'));
// Official mxConnector.paintEdgeShape calls mxMarker.createMarker after the
// stroke. The capture stub inherited mxShape's polyline, and defaultEdge is
// `shape=connector`, so ER crow's feet (and classic/block/oval markers)
// never reached VisioDocument::parse.
loadOfficialCtor('mxPolyline.js', 'mxPolyline');
loadOfficialCtor('mxConnector.js', 'mxConnector');
registerShape(mxConstants.SHAPE_ARROW, shapeContext.mxArrow);
registerShape(mxConstants.SHAPE_ARROW_CONNECTOR, shapeContext.mxArrowConnector);
registerShape(mxConstants.SHAPE_SWIMLANE, shapeContext.mxSwimlane);
registerShape(mxConstants.SHAPE_CONNECTOR, shapeContext.mxConnector);
registerShape('connector', shapeContext.mxConnector);
registerShape('polyline', shapeContext.mxPolyline);
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

function Sidebar() {
  this.palettes = [];
  this.initialDefaultVertexStyle = {};
  // Clipart Gear_128x128.png is raster; LibreOffice only sees vector
  // geometry from VisioDocument::parse. Use the same SVG gear Azure2
  // already vectorises via mxImageShape / mxLabel.paintImage.
  this.gearImage = 'img/lib/mscae/Gear.svg';
  this.graph = {setLinkForCell() {}, setAttributeForCell() {}};
  this.editorUi = {
    editor: {
      graph: {
        appendFontSize(style) { return String(style || ''); },
        vertexFontSize: 12,
        edgeFontSize: 12,
      },
    },
  };
}
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
Sidebar.prototype.defaultImageWidth = 80;
Sidebar.prototype.defaultImageHeight = 80;
// diagramly Sidebar.js init() calls addImagePalette with img/lib/clip_art.
// Those PNG templates never reached VisioDocument::parse. Skip missing files
// so they do not become noGeometry placeholders.
Sidebar.prototype.addImagePalette = function(id, title, prefix, postfix, items, titles) {
  const fns = [];
  for (let i = 0; i < items.length; i++) {
    const item = items[i];
    const rel = `${prefix}${item}${postfix}`;
    if (!fs.existsSync(path.join(webapp, rel))) {
      factoryErrors.push({id, error: `missing ${rel}`});
      continue;
    }
    const label = (titles && titles[i]) || String(item).replace(/[-_]/g, ' ');
    fns.push(this.createVertexTemplateEntry(
      `image;html=1;image=${rel}`,
      this.defaultImageWidth, this.defaultImageHeight, '', label,
    ));
  }
  this.addPaletteFunctions(id, title, false, fns);
};

function mxUtilsSetStyle(style, key, value) {
  if (style == null || key == null) return style;
  const parts = String(style).split(';').filter((part) => part !== '');
  const prefix = `${key}=`;
  let found = false;
  const next = [];
  for (const part of parts) {
    if (part === key || part.startsWith(prefix)) {
      found = true;
      if (value != null && String(value) !== '') next.push(`${key}=${value}`);
    } else next.push(part);
  }
  if (!found && value != null && String(value) !== '') next.push(`${key}=${value}`);
  return next.length ? `${next.join(';')};` : '';
}

function extractSidebarPrototype(source, names) {
  let out = '';
  for (const name of names) {
    const needle = `Sidebar.prototype.${name} = function`;
    const start = source.indexOf(needle);
    if (start < 0) throw new Error(`missing Sidebar.prototype.${name}`);
    let i = source.indexOf('{', start);
    let depth = 0;
    let quote = null;
    for (; i < source.length; i++) {
      const ch = source[i];
      if (quote) {
        if (ch === '\\') { i++; continue; }
        if (ch === quote) quote = null;
        continue;
      }
      if (ch === "'" || ch === '"' || ch === '`') { quote = ch; continue; }
      if (ch === '{') depth++;
      else if (ch === '}') {
        depth--;
        if (depth === 0) {
          i++;
          if (source[i] === ';') i++;
          out += `${source.slice(start, i)}\n`;
          break;
        }
      }
    }
  }
  return out;
}

const sidebarContext = {
  Sidebar,
  mxConstants,
  mxResources: {get: (key) => String(key)},
  mxUtils: {
    bind: (scope, fn) => fn.bind(scope),
    extend() {},
    setStyle: mxUtilsSetStyle,
    createXmlDocument: () => ({createElement: (name) => ({name})}),
    htmlEntities: (value) => value,
  },
  mxCell: Cell,
  mxGeometry: Geometry,
  mxPoint,
  mxRectangle: shapeContext.mxRectangle,
  Editor: {
    defaultTextStyle:
      'text;html=1;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;whiteSpace=wrap;',
  },
  Menus: {
    layoutContainerEdgeStyle: '',
    layoutContainers: new Proxy({}, {
      get: () => ({sidebarStyle: 'swimlane;startSize=20;', width: 240, height: 160}),
    }),
  },
  Graph: {createIcon: (name) => name, zapGremlins: (value) => value},
  urlParams: {},
  isLocalStorage: false,
  document: {createElement: () => ({style: {}, appendChild() {}})},
  window: {},
  console,
};
vm.createContext(sidebarContext);
vm.runInContext(
  extractSidebarPrototype(
    fs.readFileSync(path.join(webapp, 'js/grapheditor/Sidebar.js'), 'utf8'),
    ['addGeneralPalette', 'addMiscPalette', 'addAdvancedPalette', 'createAdvancedShapes', 'addUmlPalette'],
  ),
  sidebarContext,
  {filename: 'js/grapheditor/Sidebar.js'},
);

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

{
  const sidebar = new Sidebar();
  sidebarContext.sb = sidebar;
  try { sidebar.addGeneralPalette(true); } catch (error) {
    factoryErrors.push({id: 'general', error: String(error && error.stack || error)});
  }
  try { sidebar.addMiscPalette(false); } catch (error) {
    factoryErrors.push({id: 'misc', error: String(error && error.stack || error)});
  }
  try { sidebar.addAdvancedPalette(false); } catch (error) {
    factoryErrors.push({id: 'advanced', error: String(error && error.stack || error)});
  }
  captured.push({
    file: 'Sidebar-General.js',
    sourcePath: 'js/grapheditor/Sidebar.js',
    palettes: sidebar.palettes,
  });
}

{
  const sidebar = new Sidebar();
  sidebarContext.sb = sidebar;
  try { sidebar.addUmlPalette(false); } catch (error) {
    factoryErrors.push({id: 'uml', error: String(error && error.stack || error)});
  }
  captured.push({
    file: 'Sidebar-UML.js',
    sourcePath: 'js/grapheditor/Sidebar.js',
    palettes: sidebar.palettes,
  });
}

{
  // diagramly Sidebar.js init() addImagePalette palettes. grapheditor's
  // clipart prefix is stencils/clipart (only Gear); the real PNGs live under
  // img/lib/clip_art. mxImageShape paints them as ForeignData.
  const sidebar = new Sidebar();
  const imgDir = 'img';
  sidebar.addImagePalette('computer', 'Clipart / Computer', `${imgDir}/lib/clip_art/computers/`, '_128x128.png',
    ['Antivirus', 'Data_Filtering', 'Database', 'Database_Add', 'Database_Minus',
     'Database_Move_Stack', 'Database_Remove', 'Fujitsu_Tablet', 'Harddrive',
     'IBM_Tablet', 'iMac', 'iPad', 'Laptop', 'MacBook', 'Mainframe', 'Monitor',
     'Monitor_Tower', 'Monitor_Tower_Behind', 'Netbook', 'Network', 'Network_2',
     'Printer', 'Printer_Commercial', 'Secure_System', 'Server', 'Server_Rack',
     'Server_Rack_Empty', 'Server_Rack_Partial', 'Server_Tower', 'Software',
     'Stylus', 'Touch', 'USB_Hub', 'Virtual_Application', 'Virtual_Machine',
     'Virus', 'Workstation'],
    ['Antivirus', 'Data Filtering', 'Database', 'Database Add', 'Database Minus',
     'Database Move Stack', 'Database Remove', 'Fujitsu Tablet', 'Harddrive',
     'IBMTablet', 'iMac', 'iPad', 'Laptop', 'MacBook', 'Mainframe', 'Monitor',
     'Monitor Tower', 'Monitor Tower Behind', 'Netbook', 'Network', 'Network 2',
     'Printer', 'Printer Commercial', 'Secure System', 'Server', 'Server Rack',
     'Server Rack Empty', 'Server Rack Partial', 'Server Tower', 'Software',
     'Stylus', 'Touch', 'USB Hub', 'Virtual Application', 'Virtual Machine',
     'Virus', 'Workstation']);
  sidebar.addImagePalette('finance', 'Clipart / Finance', `${imgDir}/lib/clip_art/finance/`, '_128x128.png',
    ['Arrow_Down', 'Arrow_Up', 'Coins', 'Credit_Card', 'Dollar', 'Graph',
     'Pie_Chart', 'Piggy_Bank', 'Safe', 'Shopping_Cart', 'Stock_Down', 'Stock_Up'],
    ['Arrow_Down', 'Arrow Up', 'Coins', 'Credit Card', 'Dollar', 'Graph',
     'Pie Chart', 'Piggy Bank', 'Safe', 'Shopping Basket', 'Stock Down', 'Stock Up']);
  sidebar.addImagePalette('clipart', 'Clipart / Various', `${imgDir}/lib/clip_art/general/`, '_128x128.png',
    ['Battery_0', 'Battery_100', 'Battery_50', 'Battery_75', 'Battery_allstates',
     'Bluetooth', 'Earth_globe', 'Empty_Folder', 'Full_Folder', 'Gear', 'Keys',
     'Lock', 'Mouse_Pointer', 'Plug', 'Ships_Wheel', 'Star', 'Tire'],
    ['Battery 0%', 'Battery 100%', 'Battery 50%', 'Battery 75%', 'Battery',
     'Bluetooth', 'Globe', 'Empty Folder', 'Full Folder', 'Gear', 'Keys', 'Lock',
     'Mousepointer', 'Plug', 'Ships Wheel', 'Star', 'Tire']);
  sidebar.addImagePalette('networking', 'Clipart / Networking', `${imgDir}/lib/clip_art/networking/`, '_128x128.png',
    ['Bridge', 'Certificate', 'Certificate_Off', 'Cloud', 'Cloud_Computer',
     'Cloud_Computer_Private', 'Cloud_Rack', 'Cloud_Rack_Private', 'Cloud_Server',
     'Cloud_Server_Private', 'Cloud_Storage', 'Concentrator', 'Email',
     'Firewall_02', 'Firewall', 'Firewall-page1', 'Ip_Camera', 'Modem',
     'power_distribution_unit', 'Print_Server', 'Print_Server_Wireless',
     'Repeater', 'Router', 'Router_Icon', 'Switch', 'UPS', 'Wireless_Router',
     'Wireless_Router_N'],
    ['Bridge', 'Certificate', 'Certificate Off', 'Cloud', 'Cloud Computer',
     'Cloud Computer Private', 'Cloud Rack', 'Cloud Rack Private', 'Cloud Server',
     'Cloud Server Private', 'Cloud Storage', 'Concentrator', 'Email',
     'Firewall 1', 'Firewall 2', 'Firewall', 'Camera', 'Modem',
     'Power Distribution Unit', 'Print Server', 'Print Server Wireless',
     'Repeater', 'Router', 'Router Icon', 'Switch', 'UPS', 'Wireless Router',
     'Wireless Router N']);
  sidebar.addImagePalette('people', 'Clipart / People', `${imgDir}/lib/clip_art/people/`, '_128x128.png',
    ['Suit_Man', 'Suit_Man_Black', 'Suit_Man_Blue', 'Suit_Man_Green',
     'Suit_Man_Green_Black', 'Suit_Woman', 'Suit_Woman_Black', 'Suit_Woman_Blue',
     'Suit_Woman_Green', 'Suit_Woman_Green_Black', 'Construction_Worker_Man',
     'Construction_Worker_Man_Black', 'Construction_Worker_Woman',
     'Construction_Worker_Woman_Black', 'Doctor_Man', 'Doctor_Man_Black',
     'Doctor_Woman', 'Doctor_Woman_Black', 'Farmer_Man', 'Farmer_Man_Black',
     'Farmer_Woman', 'Farmer_Woman_Black', 'Nurse_Man', 'Nurse_Man_Black',
     'Nurse_Woman', 'Nurse_Woman_Black', 'Military_Officer',
     'Military_Officer_Black', 'Military_Officer_Woman',
     'Military_Officer_Woman_Black', 'Pilot_Man', 'Pilot_Man_Black',
     'Pilot_Woman', 'Pilot_Woman_Black', 'Scientist_Man', 'Scientist_Man_Black',
     'Scientist_Woman', 'Scientist_Woman_Black', 'Security_Man',
     'Security_Man_Black', 'Security_Woman', 'Security_Woman_Black', 'Tech_Man',
     'Tech_Man_Black', 'Telesales_Man', 'Telesales_Man_Black', 'Telesales_Woman',
     'Telesales_Woman_Black', 'Waiter', 'Waiter_Black', 'Waiter_Woman',
     'Waiter_Woman_Black', 'Worker_Black', 'Worker_Man', 'Worker_Woman',
     'Worker_Woman_Black']);
  sidebar.addImagePalette('telco', 'Clipart / Telecommunication',
    `${imgDir}/lib/clip_art/telecommunication/`, '_128x128.png',
    ['BlackBerry', 'Cellphone', 'HTC_smartphone', 'iPhone', 'Palm_Treo',
     'Signal_tower_off', 'Signal_tower_on'],
    ['BlackBerry', 'Cellphone', 'HTC smartphone', 'iPhone', 'Palm Treo',
     'Signaltower off', 'Signaltower on']);
  captured.push({
    file: 'Sidebar-Clipart.js',
    sourcePath: 'js/diagramly/sidebar/Sidebar.js',
    palettes: sidebar.palettes,
  });
}

const renderStats = {notVertex: 0, noStyle: 0, unregistered: 0, noPainter: 0, paintError: 0, noGeometry: 0};
const unregisteredShapes = {};
const noGeometryKinds = {};
const noGeometryEntries = [];
const noPainterEntries = [];
const paintErrors = [];
const paintErrorCounts = {};
function isGenericStyle(style) {
  // Raster pictures stay out of the vector catalog. SVG `image;` templates
  // (Azure2, SAP, GCP data-URI icons) are painted by mxImageShape so
  // LibreOffice's VisioDocument::parse still sees native geometry.
  return false;
}

function vertexPainter(style) {
  const name = style && style.shape;
  if (name && registry[name]) return registry[name];
  if (name == null || name === '' || name === 'rectangle' ||
      name === 'label' || name === 'rect') {
    return registry[mxConstants.SHAPE_RECTANGLE];
  }
  return null;
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
  const fill = stylePaintColor(style.fillColor, '#ffffff');
  const stroke = stylePaintColor(style.strokeColor, '#000000');
  let ctor = name ? registry[name] : null;
  if (!ctor && opts.allowStencil && name) {
    const stencil = stencilMap[String(name).toLowerCase()];
    if (stencil) {
      const ghost = {style, fill, stroke, direction: style.direction || null};
      if (style.dashed === '1') canvas.setDashed(true);
      if (isNoneColor(fill)) canvas.setFillColor(null);
      if (isNoneColor(stroke)) canvas.setStrokeColor(null);
      stencil.drawShape(canvas, ghost, x, y, width, height);
      canvas.finish();
      return ghost;
    }
  }
  if (!ctor && opts.fallbackRect) {
    ctor = registry[mxConstants.SHAPE_RECTANGLE];
  }
  if (!ctor) return null;
  if (typeof ctor.prototype.paintVertexShape !== 'function') return null;
  const shape = new ctor(null, fill, stroke, 1);
  shape.style = style;
  shape.fill = fill;
  shape.stroke = stroke;
  shape.strokewidth = Number(style.strokeWidth) || 1;
  shape.isDashed = style.dashed == 1;
  shape.isRounded = style.rounded == 1;
  shape.scale = 1;
  shape.bounds = {x, y, width, height};
  shape.direction = style.direction || null;
  shape.rotation = Number(style.rotation) || 0;
  shape.flipH = style.flipH == 1;
  shape.flipV = style.flipV == 1;
  shape.image = style.image || null;
  shape.preserveImageAspect = style.imageAspect != '0';
  shape.imageBackground = style.imageBackground || null;
  shape.imageBorder = style.imageBorder || null;
  shape.laneFill = mxUtils.getValue(
    style, mxConstants.STYLE_SWIMLANE_FILLCOLOR, mxConstants.NONE,
  );
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
        convertValueToString(cell) {
          if (cell == null) return '';
          return String(cell.value != null ? cell.value : '');
        },
        cellRenderer: mxCellRenderer,
        getModel() { return {getChildCount() { return 0; }, getChildAt() { return null; }}; },
      },
    },
  };
  canvas.save();
  try {
    if (typeof shape.updateTransform === 'function') {
      shape.updateTransform(canvas, x, y, width, height);
    }
    if (typeof shape.configureCanvas === 'function') {
      shape.configureCanvas(canvas, x, y, width, height);
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
  if (style.dashed === '1') canvas.setDashed(true);
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
  // defaultEdge is shape=connector. Fall back to official mxConnector so
  // mxMarker factories (ERoneToMany, classic, oval, …) paint.
  const ctor = (name && registry[name]) || shapeContext.mxConnector;
  if (ctor && typeof ctor.prototype.paintEdgeShape === 'function') {
    const shape = new ctor(null, style.fillColor || '#ffffff', style.strokeColor || '#000000', 1);
    shape.style = style;
    shape.fill = stylePaintColor(style.fillColor, '#ffffff');
    shape.stroke = stylePaintColor(style.strokeColor, '#000000');
    shape.strokewidth = Number(style.strokeWidth) || 1;
    shape.isDashed = style.dashed == 1;
    shape.isRounded = style.rounded == 1;
    shape.scale = 1;
    shape.bounds = {x, y, width, height};
    try {
      if (style.dashed === '1') canvas.setDashed(true);
      if (canvas.setFillColor) canvas.setFillColor(shape.fill);
      if (canvas.setStrokeColor) canvas.setStrokeColor(shape.stroke);
      // createMarker shortens the endpoint mxPoints in place.
      const paintPts = pts.map((pt) => new shapeContext.mxPoint(pt.x, pt.y));
      shape.paintEdgeShape(canvas, paintPts);
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
      const isEdge = !!(cell.edge || (typeof cell.style === 'string' && /(?:^|;)edge=1(?:;|$)/.test(cell.style)));
      const cellStyle = parseStyle(
        cell.style,
        isEdge ? namedStyles.defaultEdge : namedStyles.defaultVertex,
      );
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
    style = parseStyle(entry.style, namedStyles.defaultVertex);
    if (isGenericStyle(style)) {
      renderStats.unregistered++;
      const key = String(style.shape || '(none)');
      unregisteredShapes[key] = (unregisteredShapes[key] || 0) + 1;
      return null;
    }
    const ctor = vertexPainter(style);
    width = Math.max(1, Number(entry.width) || 100);
    height = Math.max(1, Number(entry.height) || 100);
    if (!style.shape) style = {...style, shape: mxConstants.SHAPE_RECTANGLE};
    if (ctor) {
      if (typeof ctor.prototype.paintVertexShape !== 'function') {
        renderStats.noPainter++;
        if (noPainterEntries.length < 20) {
          noPainterEntries.push({title: entry.title, shape: style.shape});
        }
        return null;
      }
      shape = paintRegistered(style, width, height, canvas);
    } else {
      // Sidebar templates often use shape=mxgraph.flowchart.terminator
      // (and office/aws XML stencils). LibreOffice only calls
      // VisioDocument::parse; NestedStencil.drawShape is the same path
      // paintCellTree already uses for composite cells.
      shape = paintRegistered(
        style, width, height, canvas, 0, 0,
        {allowStencil: true, fallbackRect: style.rounded == 1},
      );
      if (!shape) {
        renderStats.unregistered++;
        const key = String(style.shape || '(none)');
        unregisteredShapes[key] = (unregisteredShapes[key] || 0) + 1;
        return null;
      }
    }
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
    style = parseStyle(entry.style, namedStyles.defaultEdge);
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
  if (!canvas.operations.some((operation) => /<(move|line|curve|quad|arc|rect|roundrect|ellipse|text|image)\b/.test(operation))) {
    renderStats.noGeometry++;
    const image = style && style.image;
    const src = image == null ? '' : String(image);
    const mime = /^data:([^;,]+)/i.exec(src);
    const ext = /\.([a-z0-9]+)$/i.exec(src.split('?')[0]);
    const kind = mime ? mime[1] : (ext ? ext[1] : (src ? 'other' : `${entry.kind}:${style && style.shape || 'none'}`));
    noGeometryKinds[kind] = (noGeometryKinds[kind] || 0) + 1;
    if (noGeometryEntries.length < 40) {
      noGeometryEntries.push({
        title: entry.title,
        kind: entry.kind,
        shape: style && style.shape,
        imageKind: kind,
        image: src.slice(0, 120),
        ops: canvas.operations.slice(0, 8),
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
        sourcePath: `${family.sourcePath || `js/diagramly/sidebar/${family.file}`}#${palette.id}`,
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
  noGeometryKinds,
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
