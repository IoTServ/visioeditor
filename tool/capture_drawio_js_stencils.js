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
      // GMDL stepper addDataEntry omits ';' : `fontColor=#4d4d4dlfontSize=13`.
      // Split the glued key so collectCharIX Color is #4d4d4d and Size is 13.
      const glued = /^(#[0-9a-fA-F]{3,8})([A-Za-z][\w]*)=(.*)$/.exec(value);
      if (glued) {
        value = glued[1];
        let extraKey = glued[2];
        const stripped = extraKey.slice(1);
        if (!/^(fontSize|fontStyle|fontFamily|html|align|verticalAlign|spacingTop|spacingLeft|spacingRight|spacingBottom)$/.test(extraKey) &&
            /^(fontSize|fontStyle|fontFamily|html|align|verticalAlign|spacingTop|spacingLeft|spacingRight|spacingBottom)$/.test(stripped)) {
          extraKey = stripped;
        }
        style[extraKey] = glued[3];
      }
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
  return resolveStyleColorKeys(style);
}

// mxGraph style values may name another color key (`fillColor=strokeColor`
// on UML Initial / ArchiMate Junction / electrical diodes). LibreOffice
// collectFill only sees FillForegnd hex; the keyword is not a token.
const kStyleColorKeys = [
  'strokeColor', 'fillColor', 'fontColor',
  'gradientColor', 'labelBackgroundColor', 'labelBorderColor',
];

function defaultColorForStyleKey(key) {
  if (key === 'fillColor' || key === 'labelBackgroundColor') return '#ffffff';
  if (key === 'strokeColor' || key === 'fontColor' || key === 'labelBorderColor') {
    return '#000000';
  }
  return null;
}

function resolveStyleColorKeys(style) {
  const cache = Object.create(null);
  function lookup(key, stack) {
    if (Object.prototype.hasOwnProperty.call(cache, key)) return cache[key];
    if (stack.has(key)) {
      cache[key] = defaultColorForStyleKey(key);
      return cache[key];
    }
    stack.add(key);
    const raw = style[key];
    if (raw == null || raw === '') {
      cache[key] = defaultColorForStyleKey(key);
      return cache[key];
    }
    const token = String(raw).trim();
    if (token.toLowerCase() === 'default') {
      cache[key] = defaultColorForStyleKey(key);
      return cache[key];
    }
    if (kStyleColorKeys.indexOf(token) >= 0) {
      cache[key] = lookup(token, stack);
      return cache[key];
    }
    cache[key] = raw;
    return raw;
  }
  for (const key of kStyleColorKeys) {
    const token = style[key] == null ? '' : String(style[key]).trim();
    // fillColor=default / strokeColor=default must stay the keyword so
    // fillPaintToken can emit inherit (`fill`) rather than baking
    // #ffffff (AWS Cloud puff siblings). fontColor=default is
    // DEFAULT_FONTCOLOR #000000; leaving the keyword made html <run
    // fontcolor="default"> decode as null and Char.Color rode the
    // previous <font color> sibling (Roadmap Lorem after Label).
    if (kStyleColorKeys.indexOf(token) >= 0 ||
        (key === 'fontColor' && token.toLowerCase() === 'default')) {
      style[key] = lookup(key, new Set());
    }
  }
  return style;
}

// mxGraph CSS `inherit` takes the parent's computed color (HTML/SVG),
// not the defaultVertex `default` slot. LibreOffice collectCharIX /
// collectLine only see hex Color / LineColor; `inherit` is not a token.
const inheritStyleKeys = [
  'fontColor', 'fillColor', 'strokeColor', 'gradientColor',
  'labelBackgroundColor', 'labelBorderColor',
];

function isInheritToken(value) {
  return value != null && String(value).toLowerCase() === 'inherit';
}

function resolveInheritedStyle(style, inherited) {
  const next = {...style};
  const chain = {...inherited};
  for (const key of inheritStyleKeys) {
    if (isInheritToken(next[key])) next[key] = inherited[key];
    if (next[key] != null && !isInheritToken(next[key])) chain[key] = next[key];
  }
  return {style: next, inherited: chain};
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

function cssColorKey(value) {
  if (isNoneColor(value)) return 'none';
  return String(value).trim().toLowerCase();
}

function paintToken(value, styleFill, styleStroke) {
  if (isNoneColor(value)) return 'none';
  const key = cssColorKey(value);
  if (styleFill != null && key === cssColorKey(styleFill)) return 'fill';
  if (styleStroke != null && key === cssColorKey(styleStroke)) return 'stroke';
  return String(value);
}

// Fill must not collapse to 'stroke'. AWS resourceIcon does
// setFillColor(strokeColor) for the white glyph; that token became
// inherit FillForegnd and applyStencilStyle painted it as the palette.
function fillPaintToken(value, styleFill, forceHex) {
  if (isNoneColor(value)) return 'none';
  const key = cssColorKey(value);
  if (!forceHex && styleFill != null && key === cssColorKey(styleFill)) return 'fill';
  return String(value);
}

const kMxCellStyleColorKeys = new Set([
  'fillColor', 'strokeColor', 'fontColor', 'gradientColor',
  'labelBackgroundColor', 'labelBorderColor',
]);

function mxStencilColorIsStyleKey(color) {
  if (color == null) return false;
  const token = String(color).trim();
  if (!token || token.charAt(0) === '#') return false;
  const lower = token.toLowerCase();
  if (lower === 'none' || lower === 'fill' || lower === 'stroke' ||
      lower === 'font' || lower === 'default' || lower === 'inherit') {
    return false;
  }
  if (/^[0-9a-fA-F]{3,8}$/.test(token)) return false;
  return true;
}

// fillColor2 is not on the cell; force hex so #fff == style fillColor
// does not collapse to the `fill` token (Keyboard fillColor4 keys).
function mxStencilForceHex(color) {
  return mxStencilColorIsStyleKey(color) && !kMxCellStyleColorKeys.has(color);
}

function mxStencilColor(color, shape, fallback) {
  if (color == null || color === '') return color;
  if (color === 'none') return null;
  if (color === 'fill') return shape ? shape.fill : null;
  if (color === 'stroke') return shape ? shape.stroke : null;
  if (color === 'font') {
    return (shape && shape.style && shape.style.fontColor) || '#000000';
  }
  if (shape && shape.style && Object.prototype.hasOwnProperty.call(shape.style, color)) {
    return stylePaintColor(shape.style[color], color);
  }
  // mxStencil.getColorValue: missing style key uses the node's `default`.
  if (mxStencilForceHex(color) && fallback != null && String(fallback).trim() !== '') {
    const def = String(fallback).trim();
    if (def.toLowerCase() === 'none') return null;
    return def;
  }
  return color;
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
    // SVG matrix(a,b,c,d,e,f) with off-diagonal b/c (Event Grid 45°, IBM
    // Microservices ~90°). map() applies this before sx/tx; axis-aligned
    // matrix still uses translate+scale so ellipse w/h keep sx.
    this.affine = [1, 0, 0, 1, 0, 0];
    this.rotTheta = 0;
    this.rotFlipH = false;
    this.rotFlipV = false;
    this.rotCx = 0;
    this.rotCy = 0;
    // SVG clip-path rings in map() space. libvisio has no clip token, so
    // capture intersects fill contours (Globe meridians, Cosmos clouds).
    this.clipRings = null;
    this.viewBox = null;
    this.blurSigma = 0;
    this.stack = [];
    this.operations = [];
    this.pathOpen = false;
    this._liveRings = [];
    this._liveRing = [];
    this.externalAsset = false;
    this.styleFill = '#ffffff';
    this.styleStroke = '#000000';
    this._fillToken = 'fill';
    this._strokeToken = 'stroke';
    this._fontToken = null;
    this._fontFamilyToken = null;
    this._fontStyleToken = 0;
    this._fontBgToken = 'none';
    this._fontBorderToken = 'none';
    // text() emits <fontsize>; bindStyle compares this to createState 11.
    this._fontSizeToken = 11;
    this._strokeWidthToken = 1;
    this._dashedToken = null;
    this._dashToken = null;
    this._lineCapToken = null;
    this._lineJoinToken = null;
    // mxAbstractCanvas2D.createState miterLimit is 10. CSS / ODF default 4.
    // Leaving this null made restore() emit <miterlimit limit="4"/> onto
    // later canvas fills (Atlassian buttons after a text save).
    this._miterToken = 10;
    this._alphaToken = 1;
    this._fillAlphaToken = 1;
    this._strokeAlphaToken = 1;
    this._shadowToken = '0';
    this.state = {
      fillColor: '#ffffff',
      strokeColor: '#000000',
      // mxAbstractCanvas2D.createState / mxConstants.DEFAULT_FONTSIZE.
      // defaultVertex still pins cell labels at 12 via applyTextStyle.
      fontSize: 11,
      fontStyle: 0,
      fontFamily: null,
      fontColor: null,
      fontBackgroundColor: null,
      fontBorderColor: null,
      // mxText.apply STYLE_TEXT_OPACITY (percent). Default 100.
      textOpacity: 100,
      strokeWidth: 1,
      gradientColor: null,
      gradientDir: null,
      gradientAlpha1: 1,
      gradientAlpha2: 1,
      alpha: 1,
      fillAlpha: 1,
      strokeAlpha: 1,
      dashed: false,
      dashPattern: '',
      lineCap: null,
      lineJoin: null,
      miterLimit: 10,
      // mxConstants SHADOW_* — mxSvgCanvas2D.createShadow clones + translate.
      shadow: false,
      shadowColor: '#808080',
      shadowAlpha: 1,
      shadowDx: 2,
      shadowDy: 3,
      spacingLeft: 0,
      spacingRight: 0,
      spacingTop: 0,
      spacingBottom: 0,
      // mxText: STYLE_HORIZONTAL != 1 → verticalTextRotation. wrap from
      // whiteSpace=wrap. NestedStencil passes wrap=0 and must not inherit.
      verticalText: false,
      wrap: false,
    };
  }

  save() {
    this.stack.push({
      tx: this.tx, ty: this.ty, sx: this.sx, sy: this.sy, state: {...this.state},
      affine: this.affine.slice(),
      rotTheta: this.rotTheta, rotFlipH: this.rotFlipH, rotFlipV: this.rotFlipV,
      rotCx: this.rotCx, rotCy: this.rotCy,
      clipRings: this.clipRings,
      viewBox: this.viewBox,
      blurSigma: this.blurSigma,
    });
  }

  restore() {
    const saved = this.stack.pop();
    if (saved) {
      this.tx = saved.tx;
      this.ty = saved.ty;
      this.sx = saved.sx;
      this.sy = saved.sy;
      this.affine = saved.affine;
      this.state = saved.state;
      this.rotTheta = saved.rotTheta;
      this.rotFlipH = saved.rotFlipH;
      this.rotFlipV = saved.rotFlipV;
      this.rotCx = saved.rotCx;
      this.rotCy = saved.rotCy;
      this.clipRings = saved.clipRings;
      this.viewBox = saved.viewBox;
      this.blurSigma = saved.blurSigma;
      this._reemitPaint();
      this._reemitShadow();
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
  composeAffine(a, b, c, d, e, f) {
    svgTransformMultiply(
      this.affine,
      Number(a) || 0, Number(b) || 0, Number(c) || 0,
      Number(d) || 0, Number(e) || 0, Number(f) || 0,
    );
  }
  affineScaleX() {
    return Math.hypot(this.affine[0], this.affine[1]) || 1;
  }
  affineScaleY() {
    return Math.hypot(this.affine[2], this.affine[3]) || 1;
  }
  hasSkewAffine() {
    return Math.abs(this.affine[1]) > 1e-8 || Math.abs(this.affine[2]) > 1e-8;
  }
  isRotated() {
    return this.rotTheta !== 0 || this.rotFlipH || this.rotFlipV
      || this.hasSkewAffine();
  }
  map(px, py) {
    let x = Number(px) || 0;
    let y = Number(py) || 0;
    const m = this.affine;
    if (m[0] !== 1 || m[1] || m[2] || m[3] !== 1 || m[4] || m[5]) {
      const nx = m[0] * x + m[2] * y + m[4];
      const ny = m[1] * x + m[3] * y + m[5];
      x = nx;
      y = ny;
    }
    x = x * this.sx + this.tx;
    y = y * this.sy + this.ty;
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
  begin() {
    this.finishPath();
    this._liveRings = [];
    this._liveRing = [];
    this.operations.push('<path>');
    this.pathOpen = true;
  }
  end() { this.finishPath(); }
  _flushLiveRing() {
    if (this._liveRing && this._liveRing.length >= 3) {
      this._liveRings.push(this._liveRing);
    }
    this._liveRing = [];
  }
  _liveLast() {
    if (this._liveRing && this._liveRing.length) {
      return this._liveRing[this._liveRing.length - 1];
    }
    const rings = this._liveRings;
    if (rings.length && rings[rings.length - 1].length) {
      const ring = rings[rings.length - 1];
      return ring[ring.length - 1];
    }
    return {x: 0, y: 0};
  }
  _appendLiveCubic(p1, p2, p3, steps) {
    const p0 = this._liveLast();
    const n = steps || 8;
    for (let i = 1; i <= n; i++) {
      const t = i / n;
      const u = 1 - t;
      this._liveRing.push({
        x: u * u * u * p0.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * p3.x,
        y: u * u * u * p0.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * p3.y,
      });
    }
  }
  _appendLiveQuad(p1, p2, steps) {
    const p0 = this._liveLast();
    const n = steps || 8;
    for (let i = 1; i <= n; i++) {
      const t = i / n;
      const u = 1 - t;
      this._liveRing.push({
        x: u * u * p0.x + 2 * u * t * p1.x + t * t * p2.x,
        y: u * u * p0.y + 2 * u * t * p1.y + t * t * p2.y,
      });
    }
  }
  _setLiveMappedRect(x, y, w, h) {
    this._liveRings = [[
      {x, y},
      {x: x + w, y},
      {x: x + w, y: y + h},
      {x, y: y + h},
    ]];
    this._liveRing = [];
  }
  _setLiveMappedEllipse(x, y, w, h) {
    const rx = w / 2;
    const ry = h / 2;
    const cx = x + rx;
    const cy = y + ry;
    const ring = [];
    const n = 48;
    for (let i = 0; i < n; i++) {
      const a = i * 2 * Math.PI / n;
      ring.push({x: cx + rx * Math.cos(a), y: cy + ry * Math.sin(a)});
    }
    this._liveRings = [ring];
    this._liveRing = [];
  }
  moveTo(x, y) {
    this._flushLiveRing();
    const p = this.map(x, y);
    this._liveRing = [p];
    this.command('move', {x: p.x, y: p.y});
  }
  lineTo(x, y) {
    const p = this.map(x, y);
    this._liveRing.push(p);
    this.command('line', {x: p.x, y: p.y});
  }
  curveTo(x1, y1, x2, y2, x3, y3) {
    const p1 = this.map(x1, y1);
    const p2 = this.map(x2, y2);
    const p3 = this.map(x3, y3);
    this._appendLiveCubic(p1, p2, p3);
    this.command('curve', {x1: p1.x, y1: p1.y, x2: p2.x, y2: p2.y, x3: p3.x, y3: p3.y});
  }
  quadTo(x1, y1, x2, y2) {
    const p1 = this.map(x1, y1);
    const p2 = this.map(x2, y2);
    this._appendLiveQuad(p1, p2);
    this.command('quad', {x1: p1.x, y1: p1.y, x2: p2.x, y2: p2.y});
  }
  arcTo(rx, ry, rotation, largeArc, sweep, x, y) {
    const p0 = this._liveLast();
    const p = this.map(x, y);
    const mrx = (Number(rx) || 0) * Math.abs(this.sx) * this.affineScaleX();
    const mry = (Number(ry) || 0) * Math.abs(this.sy) * this.affineScaleY();
    const rot = (Number(rotation) || 0) + this.rotTheta;
    const pts = [];
    svgArcSample(pts, p0.x, p0.y, mrx, mry, rot, largeArc, sweep, p.x, p.y, 24);
    for (const pt of pts) this._liveRing.push(pt);
    this.command('arc', {
      rx: mrx,
      ry: mry,
      'x-axis-rotation': rot,
      'large-arc-flag': largeArc, 'sweep-flag': sweep, x: p.x, y: p.y,
    });
  }
  close() {
    this._flushLiveRing();
    this.operations.push('<close/>');
  }
  // Clip intersection already ran in map() space; do not map again.
  // Several rings in one <path> become one Geometry so collectGeometry
  // evenodd punches holes (Azure OpenAI swirl, Task Center donuts).
  emitMappedRings(rings) {
    const list = (rings || []).filter((ring) => ring && ring.length >= 3);
    if (!list.length) return false;
    this.begin();
    for (const ring of list) {
      this.command('move', {x: ring[0].x, y: ring[0].y});
      for (let i = 1; i < ring.length; i++) {
        this.command('line', {x: ring[i].x, y: ring[i].y});
      }
      this.close();
    }
    return true;
  }
  emitMappedRing(ring) {
    return this.emitMappedRings([ring]);
  }
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
    const sw = w * this.sx;
    const sh = h * this.sy;
    this._setLiveMappedRect(p.x, p.y, sw, sh);
    this.operations.push(`<rect x="${number(p.x)}" y="${number(p.y)}" w="${number(sw)}" h="${number(sh)}"/>`);
  }
  roundrect(x, y, w, h, rx, ry) {
    this.finishPath();
    if (Math.abs(Number(w) || 0) < 1e-9 && Math.abs(Number(h) || 0) < 1e-9) return;
    const aw = Math.abs(Number(w) || 0);
    const ah = Math.abs(Number(h) || 0);
    let radX = Math.abs(Number(rx) || 0);
    let radY = Math.abs(Number(ry) || 0);
    if (radX > 0 && !(radY > 0)) radY = radX;
    if (radY > 0 && !(radX > 0)) radX = radY;
    // Canvas roundrect(r=0) is a sharp rect (Android rrect rSize=0).
    // mxStencil.drawNode treats XML arcsize="0" as RECTANGLE_ROUNDING_FACTOR
    // * 100 (15), so do not emit <roundrect arcsize="0"/> here.
    if (!(radX > 1e-9) && !(radY > 1e-9)) {
      this.rect(x, y, w, h);
      return;
    }
    if (radX > aw / 2) radX = aw / 2;
    if (radY > ah / 2) radY = ah / 2;
    // rotate() / off-diagonal matrix cannot keep an axis-aligned
    // <roundrect> token. A sharp 4-point poly dropped Azure Search's
    // 45° capsule handle (rx≈h/2) that collectGeometry would paint.
    // Tessellate cubics through map() like ellipse().
    if (this.isRotated() || this._gradientNeedsAlphaBands()) {
      if (!(radX > 1e-9 || radY > 1e-9)) {
        this.poly([[x, y], [x + w, y], [x + w, y + h], [x, y + h]]);
        return;
      }
      this._roundRectPath(x, y, w, h, radX, radY);
      return;
    }
    const p = this.map(x, y);
    const sw = w * this.sx;
    const sh = h * this.sy;
    const arc = Math.min(100, 100 * Math.max(radX, radY) *
      Math.max(Math.abs(this.sx), Math.abs(this.sy)) /
      Math.max(1e-9, Math.min(Math.abs(sw), Math.abs(sh))));
    this.operations.push(`<roundrect x="${number(p.x)}" y="${number(p.y)}" w="${number(sw)}" h="${number(sh)}" arcsize="${number(arc)}"/>`);
    this._setLiveMappedRect(p.x, p.y, sw, sh);
  }
  // SVG rounded-rect corners as cubic quarters (k=0.55228), same as
  // ellipse() under rotate. Lines of zero length are fine when rx=w/2.
  _roundRectPath(x, y, w, h, rx, ry) {
    const x0 = Number(x) || 0;
    const y0 = Number(y) || 0;
    const x1 = x0 + (Number(w) || 0);
    const y1 = y0 + (Number(h) || 0);
    const left = Math.min(x0, x1);
    const right = Math.max(x0, x1);
    const top = Math.min(y0, y1);
    const bottom = Math.max(y0, y1);
    const k = 0.5522847498307936;
    this.begin();
    this.moveTo(left + rx, top);
    this.lineTo(right - rx, top);
    this.curveTo(
      right - rx + k * rx, top,
      right, top + ry - k * ry,
      right, top + ry,
    );
    this.lineTo(right, bottom - ry);
    this.curveTo(
      right, bottom - ry + k * ry,
      right - rx + k * rx, bottom,
      right - rx, bottom,
    );
    this.lineTo(left + rx, bottom);
    this.curveTo(
      left + rx - k * rx, bottom,
      left, bottom - ry + k * ry,
      left, bottom - ry,
    );
    this.lineTo(left, top + ry);
    this.curveTo(
      left, top + ry - k * ry,
      left + rx - k * rx, top,
      left + rx, top,
    );
    this.close();
  }
  ellipse(x, y, w, h) {
    this.finishPath();
    if (Math.abs(Number(w) || 0) < 1e-9 && Math.abs(Number(h) || 0) < 1e-9) return;
    if (this.isRotated() || this._gradientNeedsAlphaBands()) {
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
    const sw = w * this.sx;
    const sh = h * this.sy;
    this._setLiveMappedEllipse(p.x, p.y, sw, sh);
    this.operations.push(`<ellipse x="${number(p.x)}" y="${number(p.y)}" w="${number(sw)}" h="${number(sh)}"/>`);
  }
  fill() {
    if (this._paintMxGradientAlphaBands(false)) return;
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
    if (this._paintMxGradientAlphaBands(true)) return;
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
  setFillStyle(value) {
    // mxShape.configureCanvas: STYLE_FILL_STYLE after setFillColor.
    this.state.fillStyle = value == null || value === '' ? null : String(value);
  }
  // Graph wraps the canvas with mxRoughCanvas2D when sketch=1. Capture
  // records the style so leftover can map onto FillPattern 2–24
  // (_fillAndShadowProperties draw:fill=hatch) and jiggle stroke plates.
  setSketch(opts) {
    const o = opts || {};
    const attrs = ['enabled="1"'];
    const fill = o.fill != null && o.fill !== '' ? String(o.fill) : this.state.fillStyle;
    if (fill) attrs.push(`fill="${xmlEscape(fill)}"`);
    const gap = Number(o.gap);
    if (Number.isFinite(gap) && gap > 0) attrs.push(`gap="${number(gap)}"`);
    const angle = Number(o.angle);
    if (Number.isFinite(angle)) attrs.push(`angle="${number(angle)}"`);
    const weight = Number(o.weight);
    if (Number.isFinite(weight) && weight > 0) attrs.push(`weight="${number(weight)}"`);
    const jiggle = Number(o.jiggle);
    if (Number.isFinite(jiggle) && jiggle > 0) attrs.push(`jiggle="${number(jiggle)}"`);
    this.operations.push(`<sketch ${attrs.join(' ')}/>`);
  }
  // mxText.configureCanvas / mxXmlCanvas2D: fontbackgroundcolor / fontbordercolor.
  // LibreOffice collectTextBlock maps TextBkgnd onto fo:background-color.
  setFontBackgroundColor(value) {
    const none = isNoneColor(value);
    this.state.fontBackgroundColor = none ? null : value;
    const token = none ? 'none' : String(value);
    if (token === this._fontBgToken) return;
    this._fontBgToken = token;
    this._emitPaint('fontbackgroundcolor', token);
  }
  setFontBorderColor(value) {
    const none = isNoneColor(value);
    this.state.fontBorderColor = none ? null : value;
    const token = none ? 'none' : String(value);
    if (token === this._fontBorderToken) return;
    this._fontBorderToken = token;
    this._emitPaint('fontbordercolor', token);
  }
  setTitle() {}
  setLink() {}
  text(x, y, w, h, str, align, valign, wrap, format, overflow, clip, rotation) {
    this.finishPath();
    let s = String(str ?? '');
    if (!s) return;
    const horiz = String(align ?? '').toLowerCase();
    const vert = String(valign ?? '').toLowerCase();
    const fontSize = Number(this.state.fontSize);
    if (Number.isFinite(fontSize) && fontSize > 0) {
      this._fontSizeToken = fontSize;
      this.operations.push(`<fontsize size="${number(fontSize)}"/>`);
    }
    const p = this.map(x, y);
    const rot = (Number(rotation) || 0) + this.rotTheta;
    const htmlOn = format === 'html' || /<[a-zA-Z][\s\S]*>/.test(s);
    // CSS text-wrap/white-space nowrap on html=1 (SAP Diagram Title)
    // must win over cell whiteSpace=wrap. collectTextBlock has no wrap
    // token; veWordWrap bake expands TxtWidth when wrap stays off.
    const htmlNowrap = htmlOn && htmlHasNowrap(s);
    const cellAlign = horiz.includes('center')
      ? 'center'
      : horiz.includes('right')
        ? 'right'
        : 'left';
    const htmlRuns = htmlOn
      ? parseHtmlLabel(s, {
          fontStyle: Number(this.state.fontStyle) || 0,
          fontColor: this.state.fontColor,
          fontSize: this.state.fontSize,
          fontFamily: this.state.fontFamily,
          textOpacity: this.state.textOpacity,
          align: cellAlign,
        })
      : null;
    if (htmlRuns && htmlRuns.length) {
      s = htmlRuns.map((run) => run.str).join('');
    }
    if (!s) return;
    const attrs = [
      `x="${number(p.x)}"`,
      `y="${number(p.y)}"`,
      `str="${xmlEscape(s)}"`,
      `align="${cellAlign}"`,
      `valign="${vert.includes('middle') ? 'middle' : vert.includes('bottom') ? 'bottom' : 'top'}"`,
    ];
    // mxXmlCanvas2D.text: w/h is the cell box. Stencil glyphs pass 0.
    // LibreOffice collectTextBlock paints fo:padding on that frame.
    const bw = Number(w) * this.sx;
    const bh = Number(h) * this.sy;
    if (bw > 0 && bh > 0) {
      attrs.push(`w="${number(bw)}"`, `h="${number(bh)}"`);
      const sl = Number(this.state.spacingLeft);
      const sr = Number(this.state.spacingRight);
      const st = Number(this.state.spacingTop);
      const sb = Number(this.state.spacingBottom);
      if (Number.isFinite(sl) && sl !== 0) attrs.push(`spacing-left="${number(sl)}"`);
      if (Number.isFinite(sr) && sr !== 0) attrs.push(`spacing-right="${number(sr)}"`);
      if (Number.isFinite(st) && st !== 0) attrs.push(`spacing-top="${number(st)}"`);
      if (Number.isFinite(sb) && sb !== 0) attrs.push(`spacing-bottom="${number(sb)}"`);
      // mxXmlCanvas2D.text wrap. mxText default is false; whiteSpace=wrap
      // is the cell flag collectTextBlock cannot see — veWordWrap bake
      // expands TxtWidth when this stays off.
      let wrapOn = !!this.state.wrap;
      if (wrap === true || wrap === 1 || wrap === '1') wrapOn = true;
      else if (wrap === false || wrap === 0 || wrap === '0') wrapOn = false;
      if (htmlNowrap) wrapOn = false;
      if (wrapOn) attrs.push('wrap="1"');
    }
    if (this.state.verticalText) attrs.push('vertical="1"');
    if (Number.isFinite(rot) && rot !== 0) attrs.push(`rotation="${number(rot)}"`);
    // mxText.configureCanvas setAlpha(this.opacity/100) from
    // STYLE_TEXT_OPACITY. Put it on the text node so decoder Char
    // ColorTrans does not ride the geometry <alpha> token (FillForegndTrans).
    // Reset after emit so NestedStencil glyphs do not inherit the last cell.
    const textOpacity = Number(this.state.textOpacity);
    if (Number.isFinite(textOpacity) && Math.abs(textOpacity - 100) > 1e-6) {
      attrs.push(`textopacity="${number(textOpacity)}"`);
    }
    this.state.textOpacity = 100;
    // mxText html=1 paints <b>/<font> as separate collectCharIX rows.
    // One str= run would drop Classifier1 bold and GCP Name's black.
    if (htmlRuns && htmlLabelRunsDiffer(htmlRuns, {
      fontStyle: Number(this.state.fontStyle) || 0,
      fontColor: this.state.fontColor,
      fontSize: this.state.fontSize,
      fontFamily: this.state.fontFamily,
      textOpacity: this.state.textOpacity,
      align: cellAlign,
    })) {
      const inner = htmlRuns.map((run) => `<run ${htmlRunAttrs(run)}/>`).join('');
      this.operations.push(`<text ${attrs.join(' ')}>${inner}</text>`);
    } else {
      this.operations.push(`<text ${attrs.join(' ')}/>`);
    }
    // CSS border-bottom dotted/dashed is not Char Style 0x4 (that is a
    // solid underline collectCharIX maps to style:text-underline-type).
    // Freeze a collectLine sibling so ER Weak Key stays distinct from
    // Key Attribute fontStyle=4.
    if (htmlRuns && htmlRuns.length) {
      paintHtmlBorderBottom(
        this, x, y, w, h, horiz, vert, htmlRuns,
      );
    }
  }

  bindStyle(fill, stroke) {
    // styleFill / styleStroke are the <shape fill/stroke> inherit colours
    // pinned from entryPaintColors. Vertex-cells siblings with a different
    // fillColor (Infographic Angled Entry #B1DDF0 vs first-cell #10739E)
    // must leftover-bake hex FillForegnd; overwriting styleFill here made
    // fillPaintToken always emit `fill`, so Draw painted every parallelogram
    // the first cell's colour. tokens.txt FillForegnd is svg:fill.
    this.state.shadow = false;
    this._shadowToken = '0';
    // One recording canvas paints every cell of a vertex-cells template.
    // mxShape.paint / configureCanvas starts from createState. Zeroing
    // _fillToken / _fontFamilyToken first made the real setters no-ops,
    // so the previous cell's applyTextStyle Helvetica/12, dashed=1,
    // FillForegnd hex, or round cap leaked onto the next NestedStencil
    // (omitted <fontfamily>, solid rails). Emit the createState values
    // libvisio collectCharIX / collectLine actually see.
    if (this._fontSizeToken !== 11) {
      this.finishPath();
      this.operations.push('<fontsize size="11"/>');
      this._fontSizeToken = 11;
    }
    this.state.fontSize = 11;
    if (this._fontStyleToken !== 0) this.setFontStyle(0);
    else this.state.fontStyle = 0;
    if (this._fontFamilyToken !== 'Arial') this.setFontFamily('Arial');
    else this.state.fontFamily = 'Arial';
    if (this._fontToken !== '#000000') this.setFontColor('#000000');
    else this.state.fontColor = '#000000';
    if (this._fontBgToken !== 'none') this.setFontBackgroundColor(null);
    else this.state.fontBackgroundColor = null;
    if (this._fontBorderToken !== 'none') this.setFontBorderColor(null);
    else this.state.fontBorderColor = null;
    this.state.textOpacity = 100;
    this.state.verticalText = false;
    this.state.wrap = false;
    this.state.spacingLeft = 0;
    this.state.spacingRight = 0;
    this.state.spacingTop = 0;
    this.state.spacingBottom = 0;
    this.state.gradientColor = null;
    this.state.fixDash = false;
    // Do not freeze _fillToken to 'fill' before setFillColor: a previous
    // hex FillForegnd would then skip the inherit token and stick.
    this.setFillColor(isNoneColor(fill) ? null : fill);
    this.setStrokeColor(isNoneColor(stroke) ? null : stroke);
    if (this._dashedToken === true) this.setDashed(false);
    else this.state.dashed = false;
    if (this._dashToken && this._dashToken !== '3 3') {
      this.setDashPattern('3 3');
    }
    if (this._lineCapToken && this._lineCapToken !== 'flat') {
      this.setLineCap('flat');
    }
    if (this._lineJoinToken && this._lineJoinToken !== 'miter') {
      this.setLineJoin('miter');
    }
    if (this._miterToken !== 10) this.setMiterLimit(10);
    else this.state.miterLimit = 10;
    if (this._strokeWidthToken !== 1) this.setStrokeWidth(1);
    else this.state.strokeWidth = 1;
    if (this._alphaToken !== 1) this.setAlpha(1);
    else this.state.alpha = 1;
    if (this._fillAlphaToken !== 1) this.setFillAlpha(1);
    else this.state.fillAlpha = 1;
    if (this._strokeAlphaToken !== 1) this.setStrokeAlpha(1);
    else this.state.strokeAlpha = 1;
  }

  _emitPaint(tag, token) {
    this.finishPath();
    this.operations.push(`<${tag} color="${xmlEscape(token)}"/>`);
  }

  _gradientToken() {
    const packed = this.state.gradientStopsPacked || '';
    return [
      'grad',
      cssColorKey(this.state.fillColor),
      cssColorKey(this.state.gradientColor),
      this.state.gradientDir || 'south',
      this.state.gradientAlpha1,
      this.state.gradientAlpha2,
      packed,
      this.state.gradientAngle,
    ].join('|');
  }

  _emitFillGradient() {
    this.finishPath();
    const dir = this.state.gradientDir || 'south';
    const attrs = [
      `color1="${xmlEscape(this.state.fillColor)}"`,
      `color2="${xmlEscape(this.state.gradientColor)}"`,
      `direction="${xmlEscape(dir)}"`,
    ];
    const a1 = Number(this.state.gradientAlpha1);
    const a2 = Number(this.state.gradientAlpha2);
    if (Number.isFinite(a1) && a1 !== 1) attrs.push(`alpha1="${number(a1)}"`);
    if (Number.isFinite(a2) && a2 !== 1) attrs.push(`alpha2="${number(a2)}"`);
    const packed = this.state.gradientStopsPacked;
    if (packed) attrs.push(`stops="${xmlEscape(packed)}"`);
    const angle = Number(this.state.gradientAngle);
    if (Number.isFinite(angle) && packed) {
      attrs.push(`angle="${number(angle)}"`);
    }
    this.operations.push(`<fillgradient ${attrs.join(' ')}/>`);
  }

  _reemitPaint() {
    if (this.state.gradientColor && !isNoneColor(this.state.gradientColor)) {
      const token = this._gradientToken();
      if (token !== this._fillToken) {
        this._fillToken = token;
        if (!this._gradientNeedsAlphaBands()) this._emitFillGradient();
      }
    } else {
      const fillToken = fillPaintToken(
        this.state.fillColor,
        this.styleFill,
        this._effectiveFillOpacity() < 1 - 1e-9,
      );
      if (fillToken !== this._fillToken) {
        this._fillToken = fillToken;
        this._emitPaint('fillcolor', fillToken);
      }
    }
    const strokeToken = paintToken(this.state.strokeColor, this.styleFill, this.styleStroke);
    if (strokeToken !== this._strokeToken) {
      this._strokeToken = strokeToken;
      this._emitPaint('strokecolor', strokeToken);
    }
    const fontToken = this.state.fontColor == null ? null : String(this.state.fontColor);
    if (fontToken !== this._fontToken && fontToken != null) {
      this._fontToken = fontToken;
      this._emitPaint('fontcolor', fontToken);
    }
    const ff = this.state.fontFamily == null ? null : String(this.state.fontFamily);
    if (ff !== this._fontFamilyToken) {
      this._fontFamilyToken = ff;
      this.finishPath();
      this.operations.push(`<fontfamily family="${xmlEscape(ff || '')}"/>`);
    }
    this._reemitFontStyle();
    this._reemitFontPlate();
    const sw = Number(this.state.strokeWidth);
    if (Number.isFinite(sw) && sw !== this._strokeWidthToken) {
      this._strokeWidthToken = sw;
      this.finishPath();
      this.operations.push(`<strokewidth width="${number(sw)}"/>`);
    }
    this._reemitAlpha();
    this._reemitLineStyle();
    this._reemitShadow();
  }

  // mxXmlCanvas2D.setFontStyle is compressed: emit when the token
  // changes, including 0. text() used to write fontstyle only when
  // != 0, so SysML Block `fontStyle=2` titles leaked italic onto
  // `{x > y}` that collectCharIX maps to fo:font-style.
  _reemitFontStyle() {
    const n = Number(this.state.fontStyle);
    const style = Number.isFinite(n) ? n : 0;
    if (style === this._fontStyleToken) return;
    this._fontStyleToken = style;
    this.finishPath();
    this.operations.push(`<fontstyle style="${number(style)}"/>`);
  }

  _reemitFontPlate() {
    const bg = this.state.fontBackgroundColor == null
      ? 'none'
      : String(this.state.fontBackgroundColor);
    if (bg !== this._fontBgToken) {
      this._fontBgToken = bg;
      this._emitPaint('fontbackgroundcolor', bg);
    }
    const border = this.state.fontBorderColor == null
      ? 'none'
      : String(this.state.fontBorderColor);
    if (border !== this._fontBorderToken) {
      this._fontBorderToken = border;
      this._emitPaint('fontbordercolor', border);
    }
  }

  _reemitLineStyle() {
    const cap = this.state.lineCap || null;
    if (cap && cap !== this._lineCapToken) {
      this._lineCapToken = cap;
      this.finishPath();
      this.operations.push(`<linecap cap="${xmlEscape(cap)}"/>`);
    }
    const join = this.state.lineJoin || null;
    if (join && join !== this._lineJoinToken) {
      this._lineJoinToken = join;
      this.finishPath();
      this.operations.push(`<linejoin join="${xmlEscape(join)}"/>`);
    }
    const miter = Number(this.state.miterLimit);
    if (Number.isFinite(miter) && miter !== this._miterToken) {
      this._miterToken = miter;
      this.finishPath();
      this.operations.push(`<miterlimit limit="${number(miter)}"/>`);
    }
    const dashed = !!this.state.dashed;
    if (this._dashedToken !== dashed && (this._dashedToken != null || dashed)) {
      this._dashedToken = dashed;
      this.finishPath();
      this.operations.push(`<dashed dashed="${dashed ? '1' : '0'}"/>`);
    }
    const rawDash = String(this.state.dashPattern || '').trim();
    const dashToken = !rawDash || rawDash.toLowerCase() === 'none' ? 'none' : rawDash;
    if (dashToken !== this._dashToken &&
        (this._dashToken != null || dashToken !== 'none')) {
      this._dashToken = dashToken;
      this.finishPath();
      this.operations.push(`<dashpattern pattern="${xmlEscape(dashToken)}"/>`);
    }
  }

  _effectiveFillOpacity() {
    const a = Number(this.state.alpha);
    const f = Number(this.state.fillAlpha);
    return (Number.isFinite(a) ? a : 1) * (Number.isFinite(f) ? f : 1);
  }

  _gradientNeedsAlphaBands() {
    if (!this.state.gradientColor || isNoneColor(this.state.gradientColor)) {
      return false;
    }
    if (this._effectiveFillOpacity() < 1 - 1e-9) return true;
    const a1 = this.state.gradientAlpha1 == null ? 1 : Number(this.state.gradientAlpha1);
    const a2 = this.state.gradientAlpha2 == null ? 1 : Number(this.state.gradientAlpha2);
    return (Number.isFinite(a1) && a1 < 1 - 1e-9) ||
      (Number.isFinite(a2) && a2 < 1 - 1e-9);
  }

  _discardPendingShape() {
    this.finishPath();
    if (this.pathOpen) {
      const idx = this.operations.lastIndexOf('<path>');
      if (idx >= 0) this.operations.length = idx;
      this.pathOpen = false;
      return;
    }
    const last = this.operations[this.operations.length - 1];
    if (last && /^<(rect|ellipse|roundrect)\b/.test(last)) {
      this.operations.pop();
      return;
    }
    const idx = this.operations.lastIndexOf('<path>');
    const end = this.operations.lastIndexOf('</path>');
    if (idx >= 0 && end > idx && end === this.operations.length - 1) {
      this.operations.length = idx;
    }
  }

  _paintMxGradientAlphaBands(strokeToo) {
    if (!this._gradientNeedsAlphaBands()) return false;
    this._flushLiveRing();
    const rings = (this._liveRings || []).filter((ring) => ring && ring.length >= 3);
    if (!rings.length) return false;
    this._discardPendingShape();
    const color1 = this.state.fillColor;
    const color2 = this.state.gradientColor;
    const a1 = this.state.gradientAlpha1 == null ? 1 : Number(this.state.gradientAlpha1);
    const a2 = this.state.gradientAlpha2 == null ? 1 : Number(this.state.gradientAlpha2);
    const inheritOp = this._effectiveFillOpacity();
    const dir = this.state.gradientDir || 'south';
    const stops = [
      {color: color1, offset: 0, alpha: Number.isFinite(a1) ? a1 : 1},
      {color: color2, offset: 1, alpha: Number.isFinite(a2) ? a2 : 1},
    ];
    const box = mxRingsAabb(rings);
    const span = Math.max(box.maxx - box.minx, box.maxy - box.miny, 1) * 8;
    const saved = {
      fillColor: this.state.fillColor,
      gradientColor: this.state.gradientColor,
      gradientDir: this.state.gradientDir,
      gradientAlpha1: this.state.gradientAlpha1,
      gradientAlpha2: this.state.gradientAlpha2,
      fillAlpha: this.state.fillAlpha,
      fillToken: this._fillToken,
      fillAlphaToken: this._fillAlphaToken,
    };
    const bands = 8;
    const radial = dir === 'radial';
    let painted = false;
    const emitBand = (fillRings, t) => {
      const alpha = inheritOp * svgStopsAlphaAt(stops, t);
      if (!(alpha > 1e-9)) return 0;
      if (!this.emitMappedRings(fillRings)) return 0;
      this.setFillColor(svgStopsColorAt(stops, t), true);
      this.setFillAlpha(alpha);
      this.operations.push('<fill/>');
      return 1;
    };
    if (radial) {
      if (emitBand(rings, 0.5)) painted = true;
    } else {
      const v = mxMappedGradientVector(box, dir);
      for (let i = 0; i < bands; i++) {
        const t0 = i / bands;
        const t1 = (i + 1) / bands;
        const slab = mxGradientSlabRing(v, t0, t1, span);
        if (!slab) continue;
        const band = [];
        for (const ring of rings) {
          for (const hit of svgIntersectPolygons(ring, slab)) band.push(hit);
        }
        if (emitBand(band, (t0 + t1) / 2)) painted = true;
      }
      if (!painted && emitBand(rings, 0.5)) painted = true;
    }
    this.state.fillColor = saved.fillColor;
    this.state.gradientColor = saved.gradientColor;
    this.state.gradientDir = saved.gradientDir;
    this.state.gradientAlpha1 = saved.gradientAlpha1;
    this.state.gradientAlpha2 = saved.gradientAlpha2;
    this.state.fillAlpha = saved.fillAlpha;
    this._fillToken = saved.fillToken;
    this._emitAlpha('fillalpha', saved.fillAlpha);
    this._fillAlphaToken = saved.fillAlpha;
    if (strokeToo && !isNoneColor(this.state.strokeColor)) {
      this.emitMappedRings(rings);
      this.operations.push('<stroke/>');
    }
    return painted || inheritOp < 1e-9;
  }

  _emitAlpha(tag, value) {
    this.finishPath();
    this.operations.push(`<${tag} alpha="${number(value)}"/>`);
  }

  _reemitAlpha() {
    const a = Number(this.state.alpha);
    const fa = Number(this.state.fillAlpha);
    const sa = Number(this.state.strokeAlpha);
    const alpha = Number.isFinite(a) ? a : 1;
    const fillAlpha = Number.isFinite(fa) ? fa : 1;
    const strokeAlpha = Number.isFinite(sa) ? sa : 1;
    if (alpha !== this._alphaToken) {
      this._alphaToken = alpha;
      this._emitAlpha('alpha', alpha);
    }
    if (fillAlpha !== this._fillAlphaToken) {
      this._fillAlphaToken = fillAlpha;
      this._emitAlpha('fillalpha', fillAlpha);
    }
    if (strokeAlpha !== this._strokeAlphaToken) {
      this._strokeAlphaToken = strokeAlpha;
      this._emitAlpha('strokealpha', strokeAlpha);
    }
  }

  _setAlphaChannel(which, value) {
    const n = Number(value);
    if (!Number.isFinite(n)) return;
    const clamped = Math.max(0, Math.min(1, n));
    if (which === 'alpha') this.state.alpha = clamped;
    else if (which === 'fillalpha') this.state.fillAlpha = clamped;
    else this.state.strokeAlpha = clamped;
    const tokenKey = which === 'alpha' ? '_alphaToken'
      : which === 'fillalpha' ? '_fillAlphaToken' : '_strokeAlphaToken';
    if (this[tokenKey] === clamped) return;
    this[tokenKey] = clamped;
    this._emitAlpha(which, clamped);
  }

  setAlpha(value) { this._setAlphaChannel('alpha', value); }
  setFillAlpha(value) { this._setAlphaChannel('fillalpha', value); }
  setStrokeAlpha(value) { this._setAlphaChannel('strokealpha', value); }
  setFillColor(value, forceHex) {
    this.state.fillColor = isNoneColor(value) ? null : value;
    this.state.gradientColor = null;
    this.state.gradientDir = null;
    this.state.gradientAlpha1 = 1;
    this.state.gradientAlpha2 = 1;
    this.state.gradientStopsPacked = null;
    this.state.gradientAngle = null;
    // Semi-transparent inherit fill must stay FillForegnd + FillForegndTrans
    // on one shape. forceHex on fillAlpha<1 split Circular Dial (2)'s
    // fillOpacity=20 donut into a sibling, so the 65% arc occupied the
    // parent and Draw painted the track on top of the value.
    const matchesInherit = !isNoneColor(value) &&
      this.styleFill != null &&
      cssColorKey(value) === cssColorKey(this.styleFill);
    const token = fillPaintToken(
      value,
      this.styleFill,
      forceHex === true ||
        (!matchesInherit && this._effectiveFillOpacity() < 1 - 1e-9),
    );
    if (token === this._fillToken) return;
    this._fillToken = token;
    this._emitPaint('fillcolor', token);
  }
  // SVG presentation strokes pass forceHex so IBM Key Mgmt's white
  // shaft (`#fff` == default fillColor) does not collapse to the
  // `fill` token. After fillcolor=none that token became none and
  // collectLine never saw the LineWeight sibling.
  setStrokeColor(value, forceHex) {
    this.state.strokeColor = isNoneColor(value) ? null : value;
    const token = (forceHex === true && !isNoneColor(value))
      ? String(value)
      : paintToken(value, this.styleFill, this.styleStroke);
    if (token === this._strokeToken) return;
    this._strokeToken = token;
    this._emitPaint('strokecolor', token);
  }
  setStrokeWidth(value) {
    const n = Number(value);
    if (!Number.isFinite(n) || n < 0) return;
    this.state.strokeWidth = n;
    if (this._strokeWidthToken === n) return;
    this._strokeWidthToken = n;
    this.finishPath();
    this.operations.push(`<strokewidth width="${number(n)}"/>`);
  }
  setDashed(value, fixDash) {
    const dashed = !!value;
    this.state.dashed = dashed;
    this.state.fixDash = fixDash === true || fixDash === 1 || fixDash === '1';
    if (this._dashedToken === dashed) return;
    this._dashedToken = dashed;
    this.finishPath();
    this.operations.push(`<dashed dashed="${dashed ? '1' : '0'}"/>`);
  }
  // mxStencil.drawNode dashpattern: Number(part) * minScale, then
  // setDashPattern. libvisio collectLine is shape-level LinePattern;
  // custom arrays become User.veDashPattern / a MoveTo ribbon.
  setDashPattern(value) {
    const text = String(value ?? '').trim();
    this.state.dashPattern = text;
    if (text === this._dashToken) return;
    this._dashToken = text;
    this.finishPath();
    this.operations.push(`<dashpattern pattern="${xmlEscape(text)}"/>`);
  }
  setLineCap(value) {
    const cap = String(value ?? '').trim().toLowerCase();
    if (!cap) return;
    this.state.lineCap = cap;
    if (cap === this._lineCapToken) return;
    this._lineCapToken = cap;
    this.finishPath();
    this.operations.push(`<linecap cap="${xmlEscape(cap)}"/>`);
  }
  setLineJoin(value) {
    const join = String(value ?? '').trim().toLowerCase();
    if (!join) return;
    this.state.lineJoin = join;
    if (join === this._lineJoinToken) return;
    this._lineJoinToken = join;
    this.finishPath();
    this.operations.push(`<linejoin join="${xmlEscape(join)}"/>`);
  }
  setMiterLimit(value) {
    const n = Number(value);
    if (!Number.isFinite(n) || n < 1) return;
    this.state.miterLimit = n;
    if (this._miterToken === n) return;
    this._miterToken = n;
    this.finishPath();
    this.operations.push(`<miterlimit limit="${number(n)}"/>`);
  }
  // mxShape.configureCanvas / mxSvgCanvas2D.createShadow: a translated
  // grey silhouette. LibreOffice only calls VisioDocument::parse, so
  // emit ShdwPattern cells libvisio `_fillAndShadowProperties` maps to
  // ODF draw:shadow. setShadow(false) before paintForeground matches
  // official paintVertexShape (decorations stay unshadowed).
  _shadowPayload() {
    const on = !!this.state.shadow;
    if (!on) return '0';
    return [
      '1',
      number(this.state.shadowDx),
      number(this.state.shadowDy),
      cssColorKey(this.state.shadowColor) || '#808080',
      number(this.state.shadowAlpha),
    ].join('|');
  }

  _emitShadow(enabled) {
    this.finishPath();
    if (!enabled) {
      this.operations.push('<shadow enabled="0"/>');
      return;
    }
    const dx = Number(this.state.shadowDx);
    const dy = Number(this.state.shadowDy);
    const alpha = Number(this.state.shadowAlpha);
    const color = this.state.shadowColor || '#808080';
    const attrs = ['enabled="1"'];
    if (Number.isFinite(dx)) attrs.push(`dx="${number(dx)}"`);
    if (Number.isFinite(dy)) attrs.push(`dy="${number(dy)}"`);
    if (color && !isNoneColor(color)) attrs.push(`color="${xmlEscape(color)}"`);
    if (Number.isFinite(alpha) && alpha !== 1) attrs.push(`alpha="${number(alpha)}"`);
    this.operations.push(`<shadow ${attrs.join(' ')}/>`);
  }

  _reemitShadow() {
    const token = this._shadowPayload();
    if (token === this._shadowToken) return;
    this._shadowToken = token;
    this._emitShadow(!!this.state.shadow);
  }

  setShadow(enabled) {
    const on = enabled === true || enabled === 1 || enabled === '1';
    this.state.shadow = on;
    const token = this._shadowPayload();
    if (token === this._shadowToken) return;
    this._shadowToken = token;
    this._emitShadow(on);
  }

  setShadowColor(value) {
    this.state.shadowColor = isNoneColor(value) ? '#808080' : value;
    if (this.state.shadow) this._reemitShadow();
  }

  setShadowAlpha(value) {
    const n = Number(value);
    if (!Number.isFinite(n)) return;
    this.state.shadowAlpha = Math.max(0, Math.min(1, n));
    if (this.state.shadow) this._reemitShadow();
  }

  setShadowOffset(dx, dy) {
    const x = Number(dx);
    const y = Number(dy);
    if (Number.isFinite(x)) this.state.shadowDx = x;
    if (Number.isFinite(y)) this.state.shadowDy = y;
    if (this.state.shadow) this._reemitShadow();
  }

  // mxAbstractCanvas2D.setGradient: fillColor=c1, gradientColor=c2.
  // Official configureCanvas calls this when STYLE_GRADIENTCOLOR is set.
  // Emit actual hex so the Dart decoder can bake FillPattern 25–34
  // siblings; paintToken('fill') would let applyStencilStyle wash AWS
  // brand ramps into kStencilAws beige.
  setGradient(color1, color2, x, y, w, h, direction, alpha1, alpha2) {
    if (isNoneColor(color1)) {
      this.setFillColor(null);
      return;
    }
    const a1 = alpha1 == null ? 1 : Number(alpha1);
    const a2 = alpha2 == null ? 1 : Number(alpha2);
    const same = cssColorKey(color1) === cssColorKey(color2);
    if (isNoneColor(color2) || (same && Math.abs(a1 - a2) < 1e-9)) {
      this.setFillColor(color1);
      return;
    }
    this.state.fillColor = color1;
    this.state.gradientColor = color2;
    this.state.gradientDir = direction || 'south';
    this.state.gradientAlpha1 = alpha1 == null ? 1 : Number(alpha1);
    this.state.gradientAlpha2 = alpha2 == null ? 1 : Number(alpha2);
    this.state.gradientStopsPacked = null;
    this.state.gradientAngle = null;
    const token = this._gradientToken();
    if (token === this._fillToken) return;
    this._fillToken = token;
    // FillPattern 25–40 drop draw:opacity. Infographic Cylinder and
    // iOS6 Alert Box setGradient + fillAlpha; leftover would bake an
    // opaque SoftEdges PNG. Tessellate at fill().
    if (this._gradientNeedsAlphaBands()) return;
    this._emitFillGradient();
  }
  // SVG linear/radial that FillPattern 25–40 cannot paint: a middle
  // stop off the first→last lerp, inset Positions, an off-slot angle,
  // or a radial with more than two unique colours. Decoder keeps
  // FillGradient rows; leftover bakes SoftEdges PNG.
  setFillGradientStops(stops, direction, angleRad) {
    if (!stops || stops.length < 2) return;
    const first = stops[0];
    const last = stops[stops.length - 1];
    if (isNoneColor(first.color)) {
      this.setFillColor(null);
      return;
    }
    this.state.fillColor = first.color;
    this.state.gradientColor = last.color;
    this.state.gradientDir = direction || 'south';
    this.state.gradientAlpha1 = first.alpha == null ? 1 : Number(first.alpha);
    this.state.gradientAlpha2 = last.alpha == null ? 1 : Number(last.alpha);
    this.state.gradientStopsPacked = svgPackGradientStops(stops);
    this.state.gradientAngle = Number(angleRad);
    const token = this._gradientToken();
    if (token === this._fillToken) return;
    this._fillToken = token;
    if (this._gradientNeedsAlphaBands()) return;
    this._emitFillGradient();
  }
  setFontColor(value) {
    this.state.fontColor = isNoneColor(value) ? null : value;
    const token = isNoneColor(value) ? 'none' : String(value);
    if (token === this._fontToken) return;
    this._fontToken = token;
    this._emitPaint('fontcolor', token);
  }
  // mxStencil.drawNode fontfamily → setFontFamily(family).
  // LibreOffice collectCharIX maps Char.Font onto style:font-name.
  setFontFamily(value) {
    const family = value == null ? '' : String(value);
    this.state.fontFamily = family;
    if (family === this._fontFamilyToken) return;
    this._fontFamilyToken = family;
    this.finishPath();
    this.operations.push(`<fontfamily family="${xmlEscape(family)}"/>`);
  }
  setFontSize(value) { this.state.fontSize = value; }
  setFontStyle(value) {
    const n = Number(value);
    this.state.fontStyle = Number.isFinite(n) ? n : 0;
    this._reemitFontStyle();
  }

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
    this._flushLiveRing();
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
    if (match[5] != null) {
      const raw = match[5];
      if (/\S/.test(raw)) {
        stack[stack.length - 1].children.push({
          name: '#text',
          attrs: {},
          children: [],
          text: decodeXml(raw),
        });
      }
      continue;
    }
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

// Sidebar-SAP concatenates `image=img/lib/sap/` + the file stem; the
// files on disk are `Name.svg`. Official mxImageShape still calls
// c.image() with that stem, and the browser resolves it; capture must
// try the missing extension or paintSvgImage returns false and LibreOffice
// only sees the empty mxImageShape box.
function resolveWebappFile(rel, extensions) {
  const file = path.join(webapp, rel);
  if (fs.existsSync(file)) return file;
  if (path.extname(rel)) return null;
  for (const ext of extensions) {
    const candidate = `${file}${ext}`;
    if (fs.existsSync(candidate)) return candidate;
  }
  return null;
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
  const rel = raw.replace(/^\.\//, '').split('?')[0].replace(/^\/+/, '');
  const file = /\.(png|jpe?g|gif|webp|bmp)$/i.test(rel)
    ? resolveWebappFile(rel, [])
    : (rel.startsWith('img/') && !path.extname(rel)
      ? resolveWebappFile(rel, ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'])
      : null);
  if (!file) return null;
  const ext = path.extname(file).toLowerCase();
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
  const rel = raw.replace(/^\.\//, '').split('?')[0].replace(/^\/+/, '');
  if (!/\.svg$/i.test(rel) && !rel.startsWith('img/')) return null;
  const file = resolveWebappFile(rel, ['.svg']);
  if (!file) return null;
  const text = fs.readFileSync(file, 'utf8');
  return text.includes('<svg') ? text : null;
}

// SVG <style> class / id rules (GCP Vertex AI `.st0{fill:#b5cbf9}`).
// parseXml drops text nodes, so read the raw XML. Presentation attributes
// still win over the stylesheet, matching SVG.
function parseSvgCssDeclarations(body) {
  const style = {};
  for (const part of String(body || '').split(';')) {
    const split = part.indexOf(':');
    if (split < 0) continue;
    const key = part.slice(0, split).trim().toLowerCase();
    const val = part.slice(split + 1).trim();
    if (key && val) style[key] = val;
  }
  return style;
}

function parseSvgStyleSheet(xml) {
  const classes = {};
  const ids = {};
  const re = /<style\b[^>]*>([\s\S]*?)<\/style>/gi;
  let match;
  while ((match = re.exec(String(xml || '')))) {
    let css = match[1]
      .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1')
      .replace(/<!--[\s\S]*?-->/g, '')
      .replace(/\/\*[\s\S]*?\*\//g, '');
    css = decodeXml(css);
    const ruleRe = /([^{}]+)\{([^{}]*)\}/g;
    let rule;
    while ((rule = ruleRe.exec(css))) {
      const decls = parseSvgCssDeclarations(rule[2]);
      if (!Object.keys(decls).length) continue;
      for (const sel of rule[1].split(',')) {
        const token = sel.trim();
        const cls = /^\.([A-Za-z_][\w-]*)/.exec(token);
        const id = /^#([A-Za-z_][\w-]*)/.exec(token);
        if (cls) {
          classes[cls[1]] = {...(classes[cls[1]] || {}), ...decls};
        } else if (id) {
          ids[id[1]] = {...(ids[id[1]] || {}), ...decls};
        }
      }
    }
  }
  return {classes, ids};
}

function svgCssForNode(node, css) {
  if (!css) return {};
  const style = {};
  const classAttr = String(node.attrs.class || '');
  for (const name of classAttr.split(/\s+/)) {
    if (!name) continue;
    Object.assign(style, css.classes[name]);
  }
  const id = node.attrs.id;
  if (id && css.ids[id]) Object.assign(style, css.ids[id]);
  return style;
}

function svgCssAlpha(raw) {
  if (raw == null || raw === '') return null;
  const token = String(raw).trim();
  if (/%$/.test(token)) {
    const n = parseFloat(token);
    return Number.isFinite(n) ? Math.max(0, Math.min(1, n / 100)) : null;
  }
  const n = parseFloat(token);
  return Number.isFinite(n) ? Math.max(0, Math.min(1, n)) : null;
}

function svgPresentation(node, inherited, css) {
  const style = {...inherited, ...svgCssForNode(node, css)};
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
  if (node.attrs['fill-opacity'] != null) {
    style['fill-opacity'] = node.attrs['fill-opacity'];
  }
  if (node.attrs['stroke-opacity'] != null) {
    style['stroke-opacity'] = node.attrs['stroke-opacity'];
  }
  if (node.attrs['stop-color'] != null) style['stop-color'] = node.attrs['stop-color'];
  if (node.attrs['stop-opacity'] != null) {
    style['stop-opacity'] = node.attrs['stop-opacity'];
  }
  if (node.attrs['stroke-width'] != null) {
    style['stroke-width'] = node.attrs['stroke-width'];
  }
  if (node.attrs['stroke-linecap'] != null) {
    style['stroke-linecap'] = node.attrs['stroke-linecap'];
  }
  if (node.attrs['stroke-linejoin'] != null) {
    style['stroke-linejoin'] = node.attrs['stroke-linejoin'];
  }
  if (node.attrs['stroke-miterlimit'] != null) {
    style['stroke-miterlimit'] = node.attrs['stroke-miterlimit'];
  }
  if (node.attrs['stroke-dasharray'] != null) {
    style['stroke-dasharray'] = node.attrs['stroke-dasharray'];
  }
  if (node.attrs['fill-rule'] != null) style['fill-rule'] = node.attrs['fill-rule'];
  if (node.attrs['font-size'] != null) style['font-size'] = node.attrs['font-size'];
  if (node.attrs['font-family'] != null) {
    style['font-family'] = node.attrs['font-family'];
  }
  if (node.attrs['font-weight'] != null) {
    style['font-weight'] = node.attrs['font-weight'];
  }
  if (node.attrs['font-style'] != null) {
    style['font-style'] = node.attrs['font-style'];
  }
  return style;
}

function canvasMinScale(canvas) {
  const asx = canvas.affineScaleX ? canvas.affineScaleX() : 1;
  const asy = canvas.affineScaleY ? canvas.affineScaleY() : 1;
  const sx = Math.abs(Number(canvas.sx) || 1) * asx;
  const sy = Math.abs(Number(canvas.sy) || 1) * asy;
  const scale = Math.min(sx, sy);
  return scale > 0 ? scale : 1;
}

// SVG stroke-width is in user units; path x/y already go through map()*sx.
// Emit LineWeight in the same stencil space so collectLine svg:stroke-width
// matches the scaled contour (SAP Analytics Cloud Embedded Edition 1.875).
function applySvgStrokeStyle(canvas, style) {
  const width = svgLength(style['stroke-width'], NaN);
  if (Number.isFinite(width) && width >= 0) {
    canvas.setStrokeWidth(width * canvasMinScale(canvas));
  }
  const cap = style['stroke-linecap'];
  if (cap) canvas.setLineCap(String(cap).trim().toLowerCase());
  const join = style['stroke-linejoin'];
  if (join) canvas.setLineJoin(String(join).trim().toLowerCase());
  // SVG CSS initial stroke-miterlimit is 4. Canvas createState is 10.
  const rawMiter = style['stroke-miterlimit'];
  const miter = rawMiter == null || String(rawMiter).trim() === ''
      ? 4
      : svgLength(rawMiter, NaN);
  if (Number.isFinite(miter) && miter >= 1) canvas.setMiterLimit(miter);
  applySvgDash(canvas, style);
}

// SVG stroke-dasharray is in user units (AD Database Partition 2 `8,8`).
// Scale with map() like LineWeight so collectLine veDashPattern / the
// MoveTo ribbon libvisio_write bakes (custom LinePattern 0xfe is solid)
// matches the contour. "none" must not force dashed=true.
function applySvgDash(canvas, style) {
  const raw = style['stroke-dasharray'];
  if (raw == null || raw === '') return;
  const token = String(raw).trim().toLowerCase();
  if (token === 'none' || token === 'solid') {
    canvas.setDashed(false);
    canvas.setDashPattern('none');
    return;
  }
  const scale = canvasMinScale(canvas);
  const pat = [];
  for (const part of String(raw).split(/[\s,]+/)) {
    if (!part) continue;
    const n = svgLength(part, NaN);
    if (Number.isFinite(n) && n > 0) pat.push(n * scale);
  }
  if (!pat.length) {
    canvas.setDashed(false);
    canvas.setDashPattern('none');
    return;
  }
  if (pat.length === 1) pat.push(pat[0]);
  canvas.setDashed(true);
  canvas.setDashPattern(pat.join(' '));
}

function svgPaintIsNone(value) {
  if (value == null || value === '') return false;
  const v = String(value).trim().toLowerCase();
  return v === 'none' || v === 'transparent';
}

function svgPaintUrlId(value) {
  const match = /url\(\s*['"]?#([^'")\s]+)['"]?\s*\)/i.exec(String(value || ''));
  return match ? decodeXml(match[1]) : null;
}

function svgLength(raw, fallback) {
  if (raw == null || raw === '') return fallback;
  const n = parseFloat(raw);
  return Number.isFinite(n) ? n : fallback;
}

function svgParseRgb(value) {
  const hex = htmlCssColorToHex(value);
  if (!hex || hex.length < 7) return null;
  return [
    parseInt(hex.slice(1, 3), 16),
    parseInt(hex.slice(3, 5), 16),
    parseInt(hex.slice(5, 7), 16),
  ];
}

function svgColorChannelDelta(a, b) {
  const ca = svgParseRgb(a);
  const cb = svgParseRgb(b);
  if (!ca || !cb) return 255;
  return Math.max(
    Math.abs(ca[0] - cb[0]),
    Math.abs(ca[1] - cb[1]),
    Math.abs(ca[2] - cb[2]),
  );
}

function svgStopUnitOffset(stop, index, count) {
  const off = Number(stop.offset);
  if (!Number.isFinite(off)) return count <= 1 ? 0 : index / (count - 1);
  return off;
}

// Three-stop linear whose ends match is ODF axial (FillPattern 26 / 29):
// centre = FillForegnd, edges = FillBkgnd. First/last two-stop linear
// dropped Active Directory Cell Phone / Tunnel's light #bde1fd / #bee4ff
// peak (ends #3940b4≈#2d31af). Peak must sit near 0.5 so Draw's axial
// layout matches; off-centre ramps stay first/last.
function svgAxialPeakStop(stops) {
  if (!stops || stops.length < 3) return null;
  const first = stops[0];
  const last = stops[stops.length - 1];
  if (svgColorChannelDelta(first.color, last.color) > 40) return null;
  const n = stops.length;
  let maxOff = 0;
  const units = stops.map((stop, i) => {
    const u = svgStopUnitOffset(stop, i, n);
    if (u > maxOff) maxOff = u;
    return u;
  });
  const scale = maxOff > 1 + 1e-9 ? maxOff : 1;
  let peak = null;
  let bestDelta = 0;
  let peakPos = 0.5;
  for (let i = 1; i < n - 1; i++) {
    const d = svgColorChannelDelta(stops[i].color, first.color);
    if (d > bestDelta) {
      bestDelta = d;
      peak = stops[i];
      peakPos = units[i] / scale;
    }
  }
  if (!peak || bestDelta < 48) return null;
  if (Math.abs(peakPos - 0.5) > 0.12) return null;
  return peak;
}

function svgAxialDirection(node) {
  // ODF axial (FillPattern 26 / 29) only has east–west and north–south.
  // Snap by dominant axis so a 10° Cell Phone ramp stays 26, not 31–34.
  const v = svgGradientVector(node);
  if (Math.abs(v.dx) >= Math.abs(v.dy)) return 'axial-east';
  return 'axial-north';
}

function svgGradientVector(node) {
  let x1 = svgLength(node.attrs.x1, 0);
  let y1 = svgLength(node.attrs.y1, 0);
  let x2 = svgLength(node.attrs.x2, 1);
  let y2 = svgLength(node.attrs.y2, 0);
  // Adobe SAP PKI: gradientTransform="translate(0 12.4) scale(1 -1)"
  // flips Y so north/south invert before FillPattern 25–40.
  const tf = node.attrs.gradientTransform;
  if (tf) {
    const p1 = svgTransformPoint(tf, x1, y1);
    const p2 = svgTransformPoint(tf, x2, y2);
    x1 = p1.x;
    y1 = p1.y;
    x2 = p2.x;
    y2 = p2.y;
  }
  return {x1, y1, x2, y2, dx: x2 - x1, dy: y2 - y1};
}

function svgGradientDirection(node) {
  if (xmlLocalName(node.name) === 'radialgradient') return 'radial';
  // libvisio FillPattern 25–34 is eight ODF draw:angle slots, not four.
  // Axis-only snap painted Globe's 45° matrix and SAP PKI's Y-flipped
  // diamond as east/south (27 / 28) while Draw can emit 34 / 32.
  const v = svgGradientVector(node);
  const angleRad = Math.atan2(-v.dy, v.dx);
  const drawDeg = ((90 - angleRad * 180 / Math.PI) % 360 + 360) % 360;
  const slots = [
    [0, 'north'],
    [45, 'northeast'],
    [90, 'east'],
    [135, 'southeast'],
    [180, 'south'],
    [225, 'southwest'],
    [270, 'west'],
    [315, 'northwest'],
  ];
  let best = 'south';
  let bestDelta = 360;
  for (const [deg, name] of slots) {
    let d = Math.abs(drawDeg - deg);
    if (d > 180) d = 360 - d;
    if (d < bestDelta) {
      bestDelta = d;
      best = name;
    }
  }
  return best;
}

// Visio FillGradientAngle is CCW from +X (Y-up). SVG +y is down = south.
function svgGradientAngleRad(node) {
  const v = svgGradientVector(node);
  return Math.atan2(-v.dy, v.dx);
}

function svgStopsUnitScale(stops) {
  const n = stops.length;
  let maxOff = 0;
  const units = stops.map((stop, i) => {
    const u = svgStopUnitOffset(stop, i, n);
    if (u > maxOff) maxOff = u;
    return u;
  });
  return {units, scale: maxOff > 1 + 1e-9 ? maxOff : 1};
}

// FillPattern 25–34 always run 0→1. Inset two-stops (Jira Logo 0.18→1)
// snap while SVG keeps Position.
function svgStopsFitClassicSpan(stops) {
  if (!stops || stops.length < 2) return true;
  const {units, scale} = svgStopsUnitScale(stops);
  return units[0] / scale <= 0.05 &&
    units[units.length - 1] / scale >= 0.95;
}

// `_fillAndShadowProperties` only emits eight ODF angles. A 15° two-stop
// (Power BI Embedded ~22° off 135°) would snap to FillPattern 32.
function svgLinearAngleFitsClassic(node) {
  const v = svgGradientVector(node);
  if (Math.abs(v.dx) < 1e-12 && Math.abs(v.dy) < 1e-12) return true;
  const angleRad = Math.atan2(-v.dy, v.dx);
  const drawDeg = ((90 - angleRad * 180 / Math.PI) % 360 + 360) % 360;
  const slots = [0, 45, 90, 135, 180, 225, 270, 315];
  let best = 360;
  for (const s of slots) {
    let d = Math.abs(drawDeg - s);
    if (d > 180) d = 360 - d;
    if (d < best) best = d;
  }
  return best <= 5;
}

function svgOpaqueUniqueColorCount(stops) {
  const keys = new Set();
  for (const stop of stops || []) {
    const a = stop.alpha == null ? 1 : Number(stop.alpha);
    if (a <= 1e-9) continue;
    const rgb = svgParseRgb(stop.color);
    if (!rgb) continue;
    keys.add((rgb[0] << 16) | (rgb[1] << 8) | rgb[2]);
  }
  return keys.size;
}

function svgStopsHaveAlphaRamp(stops) {
  if (!stops || stops.length < 2) return false;
  for (const stop of stops) {
    const a = stop.alpha == null ? 1 : Number(stop.alpha);
    if (Math.abs(a - 1) > 1e-9) return true;
  }
  return false;
}

function svgElementFillAlpha(style) {
  const op = svgCssAlpha(style && style.opacity);
  const fillOp = svgCssAlpha(style && style['fill-opacity']);
  return (op == null ? 1 : op) * (fillOp == null ? 1 : fillOp);
}

// FillPattern 25–40 drop draw:opacity (`_fillAndShadowProperties`
// remove). A full-box two-stop with element opacity (Intune Software
// Updates 0.9 wash) would paint opaque over the plate. Tessellate as
// FillPattern 1 + FillForegndTrans. stop-opacity ramps already do this
// (Translator Text).
function svgFillNeedsAlphaBands(stops, style) {
  if (!stops || stops.length < 2) return false;
  if (svgStopsHaveAlphaRamp(stops)) return true;
  return svgElementFillAlpha(style) < 1 - 1e-9;
}

function svgLinearNeedsFillGradient(node, stops) {
  if (xmlLocalName(node.name) !== 'lineargradient') return false;
  if (!stops || stops.length < 2) return false;
  // stop-opacity ramps tessellate as FillPattern 1 + FillForegndTrans
  // (paintSvgAlphaRampFill). Leftover SoftEdges PNG composites onto
  // opaque white and would hide siblings under the fade.
  if (svgStopsDivergeFromLerp(stops)) return true;
  if (!svgStopsFitClassicSpan(stops)) return true;
  if (!svgLinearAngleFitsClassic(node)) return true;
  return false;
}

// FillPattern 25–34 and leftover FillGradient both interpolate 0→1
// across the XForm (the SVG viewBox). A short / inset userSpaceOnUse
// vector (SAP Analytics Cloud wedge B) only covers part of that box,
// so Draw would wash the glyph with the wrong slice. Off-slot angles
// (Power BI Embedded ~22°) and leftover mid-stops still bake a
// SoftEdges PNG that composites onto opaque white and hides sibling
// bars; tessellate those as FillForegnd slabs too. On-slot full-box
// two-stops (SAP Logo south) stay native 25–40.
function svgLinearNeedsLocalBands(node, viewBox, stops) {
  if (xmlLocalName(node.name) !== 'lineargradient') return false;
  if (stops && svgLinearNeedsFillGradient(node, stops)) return true;
  if (!viewBox || !(viewBox.w > 0) || !(viewBox.h > 0)) return false;
  const v = svgGradientVector(node);
  const len = Math.hypot(v.dx, v.dy);
  if (!(len > 1e-12)) return false;
  const corners = [
    {x: viewBox.x, y: viewBox.y},
    {x: viewBox.x + viewBox.w, y: viewBox.y},
    {x: viewBox.x, y: viewBox.y + viewBox.h},
    {x: viewBox.x + viewBox.w, y: viewBox.y + viewBox.h},
  ];
  const ux = v.dx / len;
  const uy = v.dy / len;
  let sMin = Infinity;
  let sMax = -Infinity;
  for (const p of corners) {
    const s = (p.x - v.x1) * ux + (p.y - v.y1) * uy;
    if (s < sMin) sMin = s;
    if (s > sMax) sMax = s;
  }
  const boxSpan = sMax - sMin;
  if (!(boxSpan > 1e-12)) return false;
  if (len / boxSpan < 0.55) return true;
  if (sMin < -1e-9 && (-sMin) / boxSpan > 0.25) return true;
  return false;
}

// FillPattern 40 only stores FillForegnd / FillBkgnd at the disc centre
// and edge. Azure Applied AI's three unique stops and Cosmos DB's
// offset=".183" two-stop cannot survive that collapse; capture
// tessellates them (svgRadialNeedsEllipseBands) so this leftover
// path is the fallback when the glyph has no drawable rings.
function svgRadialNeedsFillGradient(node, stops) {
  if (xmlLocalName(node.name) !== 'radialgradient') return false;
  if (!stops || stops.length < 2) return false;
  if (svgOpaqueUniqueColorCount(stops) > 2) return true;
  if (!svgStopsFitClassicSpan(stops)) return true;
  return false;
}

// FillPattern 40 / ODF radial is a circle in the XForm box.
// userSpaceOnUse gradientTransform with unequal column lengths
// (SAP Build Apps blob E aspect≈1.85) is an ellipse Draw would
// clip to a disc. Task Center tick A (≈1.21) stays a disc.
function svgRadialEllipseMetrics(node) {
  const m = svgTransformMatrix(node.attrs && node.attrs.gradientTransform);
  const sx = Math.hypot(m[0], m[1]);
  const sy = Math.hypot(m[2], m[3]);
  if (!(sx > 1e-12 && sy > 1e-12)) return {aspect: 1, skew: 0};
  return {
    aspect: Math.max(sx, sy) / Math.min(sx, sy),
    skew: Math.abs((m[0] * m[2] + m[1] * m[3]) / (sx * sy)),
  };
}

function svgRadialIsElliptical(node) {
  if (xmlLocalName(node.name) !== 'radialgradient') return false;
  const {aspect, skew} = svgRadialEllipseMetrics(node);
  return aspect > 1.35 || skew > 0.2;
}

function svgRadialDiscUserSpace(node) {
  const cx = svgLength(node.attrs.cx, 0.5);
  const cy = svgLength(node.attrs.cy, 0.5);
  const r = svgLength(node.attrs.r, 0.5);
  const tf = node.attrs && node.attrs.gradientTransform;
  const c = tf ? svgTransformPoint(tf, cx, cy) : {x: cx, y: cy};
  const e = tf ? svgTransformPoint(tf, cx + r, cy) : {x: cx + r, y: cy};
  return {cx: c.x, cy: c.y, r: Math.hypot(e.x - c.x, e.y - c.y)};
}

// FillPattern 40 is a circle at the child XForm centre, and capture
// sizes every mxImageShape child to the full icon box. A corner key
// (User Subscriptions gold) or an r=2 disc on an 18 box (Open Supply
// Chain cyan) therefore samples the edge stop. Build Apps blob D is
// a slightly offset disc larger than the box — keep native 40.
function svgRadialNeedsLocalBands(node, viewBox) {
  if (xmlLocalName(node.name) !== 'radialgradient') return false;
  if (svgRadialIsElliptical(node)) return false;
  if (!viewBox || !(viewBox.w > 0) || !(viewBox.h > 0)) return false;
  const disc = svgRadialDiscUserSpace(node);
  const boxCx = viewBox.x + viewBox.w / 2;
  const boxCy = viewBox.y + viewBox.h / 2;
  const boxR = Math.min(viewBox.w, viewBox.h) / 2;
  if (!(boxR > 1e-12)) return false;
  const off = Math.hypot(disc.cx - boxCx, disc.cy - boxCy) / boxR;
  const relR = disc.r / boxR;
  return off > 0.55 || relR < 0.55;
}

// Two-stop 0→1 ellipses cannot use FillPattern 40 (a circle) or
// leftover FillGradient (canvas radial is still a circle). Offset /
// undersized circular userSpaceOnUse discs have the same problem
// because the child XForm is the viewBox. Inset Positions (Cosmos DB
// 0.183) leftover a SoftEdges PNG on that full-box XForm whose
// opaque white covers sibling glyphs. Three unique colours (Azure
// Applied AI #9cebff→#50e6ff→#32bedd, plus the four-stop highlight
// radials) have the same leftover: FillPattern 40 drops the middle
// stop and the SoftEdges PNG is a circle on the icon box. Tessellate
// concentric discs in gradient space (`svgStopsColorAt` keeps the
// extra stops; `gradientTransform` keeps the ellipse). Compound
// evenodd holes (Azure OpenAI swirl / Task Center donuts) stay one
// Geometry so collectGeometry svg:fill-rule=evenodd still punches.
function svgRadialNeedsEllipseBands(node, stops, viewBox) {
  if (!stops || stops.length < 2) return false;
  if (svgStopsHaveAlphaRamp(stops)) return false;
  if (svgOpaqueUniqueColorCount(stops) > 2) return true;
  if (svgRadialIsElliptical(node)) return true;
  if (svgRadialNeedsLocalBands(node, viewBox)) return true;
  return !svgStopsFitClassicSpan(stops);
}

function svgHexFromRgb(rgb) {
  const h = (n) => Math.max(0, Math.min(255, n | 0)).toString(16).padStart(2, '0');
  return `#${h(rgb[0])}${h(rgb[1])}${h(rgb[2])}`;
}

function svgStopsColorAt(stops, t) {
  const {units, scale} = svgStopsUnitScale(stops);
  const u = Math.max(0, Math.min(1, Number(t) || 0));
  if (!stops || !stops.length) return '#000000';
  let i = 0;
  while (i + 1 < stops.length && units[i + 1] / scale < u - 1e-12) i++;
  if (i + 1 >= stops.length) return stops[stops.length - 1].color;
  const u0 = units[i] / scale;
  const u1 = units[i + 1] / scale;
  const a = svgParseRgb(stops[i].color);
  const b = svgParseRgb(stops[i + 1].color);
  if (!a || !b) return stops[i].color;
  const tt = Math.abs(u1 - u0) < 1e-12 ? 0 : (u - u0) / (u1 - u0);
  return svgHexFromRgb([
    Math.round(a[0] + (b[0] - a[0]) * tt),
    Math.round(a[1] + (b[1] - a[1]) * tt),
    Math.round(a[2] + (b[2] - a[2]) * tt),
  ]);
}

function svgStopAlpha(stop) {
  const a = stop && stop.alpha == null ? 1 : Number(stop && stop.alpha);
  return Number.isFinite(a) ? a : 1;
}

function svgStopsAlphaAt(stops, t) {
  const {units, scale} = svgStopsUnitScale(stops);
  const u = Math.max(0, Math.min(1, Number(t) || 0));
  if (!stops || !stops.length) return 1;
  let i = 0;
  while (i + 1 < stops.length && units[i + 1] / scale < u - 1e-12) i++;
  if (i + 1 >= stops.length) return svgStopAlpha(stops[stops.length - 1]);
  const u0 = units[i] / scale;
  const u1 = units[i + 1] / scale;
  const tt = Math.abs(u1 - u0) < 1e-12 ? 0 : (u - u0) / (u1 - u0);
  return svgStopAlpha(stops[i]) +
      (svgStopAlpha(stops[i + 1]) - svgStopAlpha(stops[i])) * tt;
}

function svgRingsSpan(rings) {
  let minx = Infinity;
  let miny = Infinity;
  let maxx = -Infinity;
  let maxy = -Infinity;
  for (const ring of rings || []) {
    for (const p of ring || []) {
      if (p.x < minx) minx = p.x;
      if (p.y < miny) miny = p.y;
      if (p.x > maxx) maxx = p.x;
      if (p.y > maxy) maxy = p.y;
    }
  }
  if (!(maxx > minx) && !(maxy > miny)) return 1;
  return Math.max(maxx - minx, maxy - miny, 1) * 8;
}

function svgGradientT(node, x, y) {
  const v = svgGradientVector(node);
  const len2 = v.dx * v.dx + v.dy * v.dy;
  if (len2 < 1e-18) return 0;
  return ((x - v.x1) * v.dx + (y - v.y1) * v.dy) / len2;
}

function svgRingsGradientTRange(node, rings) {
  let tMin = Infinity;
  let tMax = -Infinity;
  for (const ring of rings || []) {
    for (const p of ring || []) {
      const t = svgGradientT(node, p.x, p.y);
      if (t < tMin) tMin = t;
      if (t > tMax) tMax = t;
    }
  }
  if (!(tMax > tMin)) return {tMin: 0, tMax: 1};
  return {tMin, tMax};
}

function svgGradientSlabRing(node, t0, t1, span) {
  const v = svgGradientVector(node);
  const len = Math.hypot(v.dx, v.dy);
  if (!(len > 1e-12)) return null;
  const ux = v.dx / len;
  const uy = v.dy / len;
  const px = -uy * span;
  const py = ux * span;
  const a0 = t0 * len;
  const a1 = t1 * len;
  return [
    {x: v.x1 + ux * a0 + px, y: v.y1 + uy * a0 + py},
    {x: v.x1 + ux * a1 + px, y: v.y1 + uy * a1 + py},
    {x: v.x1 + ux * a1 - px, y: v.y1 + uy * a1 - py},
    {x: v.x1 + ux * a0 - px, y: v.y1 + uy * a0 - py},
  ];
}

function svgRadialDiscRing(gradNode, t, steps) {
  const cx = svgLength(gradNode.attrs.cx, 0.5);
  const cy = svgLength(gradNode.attrs.cy, 0.5);
  const r = svgLength(gradNode.attrs.r, 0.5) * Math.max(Number(t) || 0, 1e-6);
  const ring = svgCircleRing(cx, cy, r, steps || 48);
  const tf = gradNode.attrs && gradNode.attrs.gradientTransform;
  return tf ? svgMapRing(ring, tf) : ring;
}

function svgSplitEvenoddRings(rings) {
  if (!rings.length) return {outers: [], holes: []};
  let best = 0;
  let bestAbs = 0;
  for (let i = 0; i < rings.length; i++) {
    const a = Math.abs(svgPolyArea(rings[i]));
    if (a > bestAbs) {
      bestAbs = a;
      best = i;
    }
  }
  return {
    outers: [rings[best]],
    holes: rings.filter((_, i) => i !== best),
  };
}

// Middle stop far from first→last lerp cannot use FillPattern 25–34
// (Windows Server (2) LED #f2580a→#fea15f→#a11a00). SAP Logo's six
// cyan–navy stops stay on the lerp so they keep native 25–40.
function svgStopsDivergeFromLerp(stops) {
  if (!stops || stops.length < 3) return false;
  if (svgAxialPeakStop(stops)) return false;
  const first = svgParseRgb(stops[0].color);
  const last = svgParseRgb(stops[stops.length - 1].color);
  if (!first || !last) return false;
  const {units, scale} = svgStopsUnitScale(stops);
  for (let i = 1; i < stops.length - 1; i++) {
    const rgb = svgParseRgb(stops[i].color);
    if (!rgb) continue;
    const t = units[i] / scale;
    const d = Math.max(
      Math.abs(rgb[0] - Math.round(first[0] + (last[0] - first[0]) * t)),
      Math.abs(rgb[1] - Math.round(first[1] + (last[1] - first[1]) * t)),
      Math.abs(rgb[2] - Math.round(first[2] + (last[2] - first[2]) * t)),
    );
    if (d > 40) return true;
  }
  return false;
}

function svgPackGradientStops(stops) {
  const {units, scale} = svgStopsUnitScale(stops);
  return stops.map((stop, i) => {
    const pos = units[i] / scale;
    const alpha = stop.alpha == null || stop.alpha === 1
      ? ''
      : `/${number(stop.alpha)}`;
    return `${stop.color}@${number(pos)}${alpha}`;
  }).join(',');
}

function svgStopColor(node, css) {
  const style = svgPresentation(node, {}, css);
  const raw = style['stop-color'] || node.attrs['stop-color'];
  if (raw == null || raw === '' || /^currentcolor$/i.test(raw)) {
    // SVG default stop-color is black. Dataverse paint2_linear / Azure A
    // highlight stripes only set stop-opacity; skipping them dropped the
    // FillForegndTrans wash collectFillAndShadow maps to draw:opacity.
    return '#000000';
  }
  if (/^none$/i.test(String(raw).trim())) return '#000000';
  return htmlCssColorToHex(raw) || (/^url\(/i.test(raw) ? '#000000' : String(raw).trim());
}

function svgCollectStops(node, css) {
  const stops = [];
  const walk = (n) => {
    if (xmlLocalName(n.name) === 'stop') {
      const color = svgStopColor(n, css);
      const style = svgPresentation(n, {}, css);
      const off = parseFloat(n.attrs.offset);
      const alpha = svgCssAlpha(style['stop-opacity'] || n.attrs['stop-opacity']);
      stops.push({
        offset: Number.isFinite(off) ? off : (stops.length === 0 ? 0 : 1),
        color,
        alpha: alpha == null ? 1 : alpha,
      });
      return;
    }
    for (const child of n.children || []) walk(child);
  };
  walk(node);
  stops.sort((a, b) => a.offset - b.offset);
  return stops;
}

function resolveSvgGradientNode(root, id) {
  const seen = new Set();
  let node = findSvgById(root, id);
  while (node) {
    const name = xmlLocalName(node.name);
    if (name !== 'lineargradient' && name !== 'radialgradient') return node;
    const href = node.attrs.href || node.attrs['xlink:href'];
    if (!href) return node;
    const next = String(href).replace(/^#/, '');
    if (!next || seen.has(next)) return node;
    seen.add(next);
    const parent = findSvgById(root, next);
    if (!parent) return node;
    const hasStops = (node.children || []).some(
      (child) => xmlLocalName(child.name) === 'stop',
    );
    node = {
      name: node.name,
      attrs: {...parent.attrs, ...node.attrs},
      children: hasStops ? node.children : parent.children,
    };
  }
  return node;
}

// SVG fill="url(#id)" / stop-color class (SAP Logo #b, data-URI .st0).
// libvisio has no gradient token beyond FillPattern 25–40 two-stops.
// Matching-end three-stops become FillPattern 26 / 29 (ODF axial).
function applySvgPaintServer(canvas, value, root, css, channel) {
  const id = svgPaintUrlId(value);
  if (!id || !root) return false;
  const node = resolveSvgGradientNode(root, id);
  if (!node) return false;
  const name = xmlLocalName(node.name);
  if (name !== 'lineargradient' && name !== 'radialgradient') return false;
  const stops = svgCollectStops(node, css);
  if (!stops.length) return false;
  const first = stops[0];
  const last = stops[stops.length - 1];
  if (channel === 'stroke') {
    canvas.setStrokeColor(first.color, true);
    return true;
  }
  if (stops.length === 1) {
    canvas.setFillColor(first.color, true);
    return true;
  }
  const peak = svgAxialPeakStop(stops);
  if (peak) {
    const axialDir = svgAxialDirection(node);
    if (axialDir) {
      canvas.setGradient(
        peak.color, first.color, 0, 0, 1, 1,
        axialDir, peak.alpha, first.alpha,
      );
      return true;
    }
  }
  if (svgStopsHaveAlphaRamp(stops)) {
    // FillPattern 25–40 drop draw:opacity. Azure Sphere's visor
    // white→white stop-opacity 0.9→0.8 sits on a userSpaceOnUse vector
    // thousands of units off the viewBox, so tessellation slabs miss
    // the glyph; leftover FillGradient bakes an opaque SoftEdges PNG
    // over the cyan body. Sample the first stop as FillForegndTrans.
    canvas.setFillColor(first.color, true);
    const alpha = first.alpha == null ? 1 : Number(first.alpha);
    if (Number.isFinite(alpha) && alpha < 1 - 1e-9) {
      canvas.setFillAlpha(alpha);
    }
    return true;
  }
  if (svgLinearNeedsFillGradient(node, stops) ||
      svgRadialNeedsFillGradient(node, stops)) {
    canvas.setFillGradientStops(
      stops, svgGradientDirection(node), svgGradientAngleRad(node),
    );
    return true;
  }
  if (cssColorKey(first.color) === cssColorKey(last.color) &&
      !svgStopsHaveAlphaRamp(stops)) {
    canvas.setFillColor(first.color, true);
    return true;
  }
  canvas.setGradient(
    first.color, last.color, 0, 0, 1, 1,
    svgGradientDirection(node), first.alpha, last.alpha,
  );
  return true;
}

function applySvgPaint(canvas, style, kind, root, css) {
  canvas.save();
  const op = svgCssAlpha(style.opacity);
  if (op != null) canvas.setAlpha(op);
  const fillOp = svgCssAlpha(style['fill-opacity']);
  if (fillOp != null) canvas.setFillAlpha(fillOp);
  const strokeOp = svgCssAlpha(style['stroke-opacity']);
  if (strokeOp != null) canvas.setStrokeAlpha(strokeOp);
  if (kind === 'fill' || kind === 'fillstroke') {
    if (svgPaintIsNone(style.fill)) {
      canvas.setFillColor(null);
    } else if (style.fill != null && style.fill !== '') {
      const fill = String(style.fill).trim();
      if (/^currentcolor$/i.test(fill)) {
        // inherit the canvas fill
      } else if (!applySvgPaintServer(canvas, fill, root, css, 'fill')) {
        canvas.setFillColor(htmlCssColorToHex(fill) || fill, true);
      }
    }
  } else {
    canvas.setFillColor(null);
  }
  if (kind === 'stroke' || kind === 'fillstroke') {
    if (svgPaintIsNone(style.stroke)) canvas.setStrokeColor(null);
    else if (style.stroke != null && style.stroke !== '') {
      const stroke = String(style.stroke).trim();
      if (/^currentcolor$/i.test(stroke)) {
        // inherit
      } else if (!applySvgPaintServer(canvas, stroke, root, css, 'stroke')) {
        canvas.setStrokeColor(htmlCssColorToHex(stroke) || stroke, true);
      }
      applySvgStrokeStyle(canvas, style);
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

// SVG transform="matrix(sx,0,0,sy,tx,ty)" (SAP Logo polyline),
// gradientTransform="translate(0 12.4) scale(1 -1)" (Adobe SAP PKI),
// and skewX(-19.425) (Azure Cognitive Services Decisions parallelogram).
function parseSvgTransformList(raw) {
  const ops = [];
  const re = /(matrix|translate|scale|rotate|skewX|skewY)\s*\(([^)]*)\)/gi;
  let match;
  while ((match = re.exec(String(raw || '')))) {
    ops.push({kind: match[1].toLowerCase(), nums: parseSvgNumbers(match[2])});
  }
  return ops;
}

function svgTransformMultiply(m, a, b, c, d, e, f) {
  const na = m[0] * a + m[2] * b;
  const nb = m[1] * a + m[3] * b;
  const nc = m[0] * c + m[2] * d;
  const nd = m[1] * c + m[3] * d;
  const ne = m[0] * e + m[2] * f + m[4];
  const nf = m[1] * e + m[3] * f + m[5];
  m[0] = na;
  m[1] = nb;
  m[2] = nc;
  m[3] = nd;
  m[4] = ne;
  m[5] = nf;
}

function svgTransformMatrix(raw) {
  const m = [1, 0, 0, 1, 0, 0];
  for (const op of parseSvgTransformList(raw)) {
    const n = op.nums;
    if (op.kind === 'translate') {
      svgTransformMultiply(m, 1, 0, 0, 1, n[0] || 0, n[1] || 0);
    } else if (op.kind === 'scale') {
      const sx = n[0] == null ? 1 : n[0];
      svgTransformMultiply(m, sx, 0, 0, n.length > 1 ? n[1] : sx, 0, 0);
    } else if (op.kind === 'rotate') {
      const rad = (n[0] || 0) * Math.PI / 180;
      const cos = Math.cos(rad);
      const sin = Math.sin(rad);
      const cx = n[1] || 0;
      const cy = n[2] || 0;
      if (cx || cy) svgTransformMultiply(m, 1, 0, 0, 1, cx, cy);
      svgTransformMultiply(m, cos, sin, -sin, cos, 0, 0);
      if (cx || cy) svgTransformMultiply(m, 1, 0, 0, 1, -cx, -cy);
    } else if (op.kind === 'skewx') {
      svgTransformMultiply(m, 1, 0, Math.tan((n[0] || 0) * Math.PI / 180), 1, 0, 0);
    } else if (op.kind === 'skewy') {
      svgTransformMultiply(m, 1, Math.tan((n[0] || 0) * Math.PI / 180), 0, 1, 0, 0);
    } else if (op.kind === 'matrix' && n.length >= 6) {
      svgTransformMultiply(m, n[0], n[1], n[2], n[3], n[4], n[5]);
    }
  }
  return m;
}

function svgTransformPoint(raw, x, y) {
  const m = svgTransformMatrix(raw);
  return {x: m[0] * x + m[2] * y + m[4], y: m[1] * x + m[3] * y + m[5]};
}

function svgComposeTransformRaw(a, b) {
  const left = String(a || '').trim();
  const right = String(b || '').trim();
  if (!left) return right;
  if (!right) return left;
  return `${left} ${right}`;
}

function svgMapRing(ring, raw) {
  if (!raw) return ring;
  return ring.map((p) => svgTransformPoint(raw, p.x, p.y));
}

function svgPolyArea(ring) {
  let area = 0;
  for (let i = 0, n = ring.length; i < n; i++) {
    const a = ring[i];
    const b = ring[(i + 1) % n];
    area += a.x * b.y - b.x * a.y;
  }
  return area / 2;
}

function svgCloseRing(pts) {
  if (!pts || pts.length < 3) return [];
  const out = pts.slice();
  const first = out[0];
  const last = out[out.length - 1];
  if (Math.abs(first.x - last.x) < 1e-9 && Math.abs(first.y - last.y) < 1e-9) {
    out.pop();
  }
  return out.length >= 3 ? out : [];
}

function svgEnsureCcw(ring) {
  return svgPolyArea(ring) < 0 ? ring.slice().reverse() : ring;
}

function svgRingAabb(ring) {
  let minx = Infinity;
  let miny = Infinity;
  let maxx = -Infinity;
  let maxy = -Infinity;
  for (const p of ring) {
    if (p.x < minx) minx = p.x;
    if (p.x > maxx) maxx = p.x;
    if (p.y < miny) miny = p.y;
    if (p.y > maxy) maxy = p.y;
  }
  return {minx, miny, maxx, maxy};
}

function mxRingsAabb(rings) {
  let minx = Infinity;
  let miny = Infinity;
  let maxx = -Infinity;
  let maxy = -Infinity;
  for (const ring of rings || []) {
    for (const p of ring || []) {
      if (p.x < minx) minx = p.x;
      if (p.y < miny) miny = p.y;
      if (p.x > maxx) maxx = p.x;
      if (p.y > maxy) maxy = p.y;
    }
  }
  return {minx, miny, maxx, maxy};
}

function mxDirUnit(dir) {
  switch (String(dir || 'south').toLowerCase()) {
    case 'east': return {dx: 1, dy: 0};
    case 'west': return {dx: -1, dy: 0};
    case 'north': return {dx: 0, dy: 1};
    case 'south': return {dx: 0, dy: -1};
    case 'northeast': return {dx: 1, dy: 1};
    case 'northwest': return {dx: -1, dy: 1};
    case 'southeast': return {dx: 1, dy: -1};
    case 'southwest': return {dx: -1, dy: -1};
    default: return {dx: 0, dy: -1};
  }
}

function mxMappedGradientVector(box, dir) {
  const u = mxDirUnit(dir);
  const dx = box.maxx - box.minx;
  const dy = box.maxy - box.miny;
  const cx = (box.minx + box.maxx) / 2;
  const cy = (box.miny + box.maxy) / 2;
  return {
    x1: cx - 0.5 * dx * u.dx,
    y1: cy - 0.5 * dy * u.dy,
    dx: dx * u.dx,
    dy: dy * u.dy,
  };
}

function mxGradientSlabRing(v, t0, t1, span) {
  const len = Math.hypot(v.dx, v.dy);
  if (!(len > 1e-12)) return null;
  const ux = v.dx / len;
  const uy = v.dy / len;
  const px = -uy * span;
  const py = ux * span;
  const a0 = t0 * len;
  const a1 = t1 * len;
  return [
    {x: v.x1 + ux * a0 + px, y: v.y1 + uy * a0 + py},
    {x: v.x1 + ux * a1 + px, y: v.y1 + uy * a1 + py},
    {x: v.x1 + ux * a1 - px, y: v.y1 + uy * a1 - py},
    {x: v.x1 + ux * a0 - px, y: v.y1 + uy * a0 - py},
  ];
}

function svgIsAabbRect(ring) {
  if (ring.length !== 4) return false;
  const box = svgRingAabb(ring);
  if (!(box.maxx > box.minx && box.maxy > box.miny)) return false;
  return ring.every((p) =>
    (Math.abs(p.x - box.minx) < 1e-6 || Math.abs(p.x - box.maxx) < 1e-6) &&
    (Math.abs(p.y - box.miny) < 1e-6 || Math.abs(p.y - box.maxy) < 1e-6)
  );
}

function svgClipCoversViewBox(rings, viewBox) {
  if (!viewBox || rings.length !== 1 || !svgIsAabbRect(rings[0])) return false;
  const box = svgRingAabb(rings[0]);
  const eps = Math.max(viewBox.w, viewBox.h) * 0.02 + 1e-6;
  return box.minx <= viewBox.x + eps && box.miny <= viewBox.y + eps &&
    box.maxx >= viewBox.x + viewBox.w - eps &&
    box.maxy >= viewBox.y + viewBox.h - eps;
}

function svgIsConvexRing(ring) {
  const n = ring.length;
  if (n < 3) return false;
  let sign = 0;
  for (let i = 0; i < n; i++) {
    const p = ring[i];
    const q = ring[(i + 1) % n];
    const r = ring[(i + 2) % n];
    const cross = (q.x - p.x) * (r.y - q.y) - (q.y - p.y) * (r.x - q.x);
    if (Math.abs(cross) < 1e-12) continue;
    const s = cross > 0 ? 1 : -1;
    if (!sign) sign = s;
    else if (s !== sign) return false;
  }
  return true;
}

function svgInsideEdge(p, a, b) {
  return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x) >= -1e-12;
}

function svgEdgeIntersect(s, e, a, b) {
  const dx = e.x - s.x;
  const dy = e.y - s.y;
  const ex = b.x - a.x;
  const ey = b.y - a.y;
  const den = dx * ey - dy * ex;
  if (Math.abs(den) < 1e-18) return {x: e.x, y: e.y};
  const t = ((a.x - s.x) * ey - (a.y - s.y) * ex) / den;
  return {x: s.x + t * dx, y: s.y + t * dy};
}

function svgSutherlandHodgman(subject, clip) {
  let output = subject;
  for (let i = 0, n = clip.length; i < n; i++) {
    const a = clip[i];
    const b = clip[(i + 1) % n];
    const input = output;
    output = [];
    if (!input.length) break;
    let prev = input[input.length - 1];
    for (const cur of input) {
      const curIn = svgInsideEdge(cur, a, b);
      const prevIn = svgInsideEdge(prev, a, b);
      if (curIn) {
        if (!prevIn) output.push(svgEdgeIntersect(prev, cur, a, b));
        output.push(cur);
      } else if (prevIn) {
        output.push(svgEdgeIntersect(prev, cur, a, b));
      }
      prev = cur;
    }
  }
  const ring = svgCloseRing(output);
  return Math.abs(svgPolyArea(ring)) > 1e-10 ? ring : [];
}

function svgPointInTriangle(p, a, b, c) {
  const s1 = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);
  const s2 = (c.x - b.x) * (p.y - b.y) - (c.y - b.y) * (p.x - b.x);
  const s3 = (a.x - c.x) * (p.y - c.y) - (a.y - c.y) * (p.x - c.x);
  const hasNeg = s1 < -1e-12 || s2 < -1e-12 || s3 < -1e-12;
  const hasPos = s1 > 1e-12 || s2 > 1e-12 || s3 > 1e-12;
  return !(hasNeg && hasPos);
}

function svgEarClip(ring) {
  const verts = svgEnsureCcw(svgCloseRing(ring)).map((p) => ({x: p.x, y: p.y}));
  if (verts.length < 3) return [];
  if (verts.length === 3 || svgIsConvexRing(verts)) return [verts];
  const rest = verts;
  const tris = [];
  let guard = 0;
  while (rest.length > 3 && guard++ < 8000) {
    let clipped = false;
    for (let i = 0; i < rest.length; i++) {
      const prev = rest[(i + rest.length - 1) % rest.length];
      const curr = rest[i];
      const next = rest[(i + 1) % rest.length];
      const cross = (curr.x - prev.x) * (next.y - prev.y) -
        (curr.y - prev.y) * (next.x - prev.x);
      if (cross <= 1e-12) continue;
      let inside = false;
      for (let j = 0; j < rest.length; j++) {
        if (j === i || j === (i + 1) % rest.length ||
            j === (i + rest.length - 1) % rest.length) {
          continue;
        }
        if (svgPointInTriangle(rest[j], prev, curr, next)) {
          inside = true;
          break;
        }
      }
      if (inside) continue;
      tris.push([prev, curr, next]);
      rest.splice(i, 1);
      clipped = true;
      break;
    }
    if (!clipped) break;
  }
  if (rest.length >= 3 && Math.abs(svgPolyArea(rest)) > 1e-12) {
    tris.push(rest.slice());
  }
  return tris.filter((tri) => tri.length >= 3 && Math.abs(svgPolyArea(tri)) > 1e-12);
}

function svgPtKey(p) {
  return `${p.x.toFixed(7)},${p.y.toFixed(7)}`;
}

function svgMergeSimpleRings(rings) {
  if (rings.length <= 1) return rings;
  const undirected = (a, b) => {
    const ka = svgPtKey(a);
    const kb = svgPtKey(b);
    return ka < kb ? `${ka}|${kb}` : `${kb}|${ka}`;
  };
  const edgeCount = new Map();
  for (const ring of rings) {
    for (let i = 0, n = ring.length; i < n; i++) {
      const k = undirected(ring[i], ring[(i + 1) % n]);
      edgeCount.set(k, (edgeCount.get(k) || 0) + 1);
    }
  }
  const next = new Map();
  const addDir = (a, b) => {
    if (edgeCount.get(undirected(a, b)) !== 1) return;
    const sk = svgPtKey(a);
    if (!next.has(sk)) next.set(sk, []);
    next.get(sk).push(b);
  };
  for (const ring of rings) {
    for (let i = 0, n = ring.length; i < n; i++) {
      addDir(ring[i], ring[(i + 1) % n]);
    }
  }
  const used = new Set();
  const out = [];
  for (const startKey of next.keys()) {
    if (used.has(startKey)) continue;
    const ring = [];
    let curKey = startKey;
    let guard = 0;
    while (curKey && !used.has(curKey) && guard++ < 8000) {
      used.add(curKey);
      const parts = curKey.split(',');
      ring.push({x: Number(parts[0]), y: Number(parts[1])});
      const opts = (next.get(curKey) || []).filter((p) => !used.has(svgPtKey(p)));
      if (!opts.length) {
        const back = (next.get(curKey) || [])[0];
        if (back && svgPtKey(back) === startKey) {
          ring.push(back);
        }
        break;
      }
      curKey = svgPtKey(opts[0]);
    }
    const closed = svgCloseRing(ring);
    if (closed.length >= 3 && Math.abs(svgPolyArea(closed)) > 1e-10) {
      out.push(closed);
    }
  }
  return out.length ? out : rings;
}

function svgIntersectPolygons(subject, clip) {
  const subj = svgEnsureCcw(svgCloseRing(subject));
  const ccw = svgEnsureCcw(svgCloseRing(clip));
  if (subj.length < 3 || ccw.length < 3) return [];
  const pieces = svgIsConvexRing(ccw) ? [ccw] : svgEarClip(ccw);
  const hits = [];
  for (const piece of pieces) {
    const hit = svgSutherlandHodgman(subj, svgEnsureCcw(piece));
    if (hit.length >= 3) hits.push(hit);
  }
  return svgMergeSimpleRings(hits);
}

function svgClipMappedToRings(subject, clipRings) {
  let clipSpan = 0;
  for (const clip of clipRings) {
    const box = svgRingAabb(clip);
    clipSpan = Math.max(
      clipSpan, box.maxx - box.minx, box.maxy - box.miny,
    );
  }
  const minSpan = clipSpan * 0.004;
  const out = [];
  for (const clip of clipRings) {
    for (const piece of svgIntersectPolygons(subject, clip)) {
      const box = svgRingAabb(piece);
      const w = box.maxx - box.minx;
      const h = box.maxy - box.miny;
      if (Math.abs(svgPolyArea(piece)) < 1e-8) continue;
      if (minSpan > 0 && Math.min(w, h) < minSpan) continue;
      out.push(piece);
    }
  }
  return out;
}

function svgCircleRing(cx, cy, r, steps) {
  const n = steps || 64;
  const ring = [];
  for (let i = 0; i < n; i++) {
    const t = (2 * Math.PI * i) / n;
    ring.push({x: cx + r * Math.cos(t), y: cy + r * Math.sin(t)});
  }
  return ring;
}

function svgEllipseRing(cx, cy, rx, ry, steps) {
  const n = steps || 64;
  const ring = [];
  for (let i = 0; i < n; i++) {
    const t = (2 * Math.PI * i) / n;
    ring.push({x: cx + rx * Math.cos(t), y: cy + ry * Math.sin(t)});
  }
  return ring;
}

function svgRectRing(x, y, w, h, rx, ry) {
  const radx = Math.min(Math.abs(rx) || 0, Math.abs(w) / 2);
  const rady = Math.min(Math.abs(ry) || 0, Math.abs(h) / 2);
  if (!(radx > 0 || rady > 0)) {
    return [{x, y}, {x: x + w, y}, {x: x + w, y: y + h}, {x, y: y + h}];
  }
  const ring = [];
  const corner = (cx, cy, start, sweep) => {
    const n = 8;
    for (let i = 0; i <= n; i++) {
      const t = start + (sweep * i) / n;
      ring.push({x: cx + radx * Math.cos(t), y: cy + rady * Math.sin(t)});
    }
  };
  corner(x + radx, y + rady, Math.PI, Math.PI / 2);
  corner(x + w - radx, y + rady, -Math.PI / 2, Math.PI / 2);
  corner(x + w - radx, y + h - rady, 0, Math.PI / 2);
  corner(x + radx, y + h - rady, Math.PI / 2, Math.PI / 2);
  return svgCloseRing(ring);
}

function svgArcSample(pts, x0, y0, rx, ry, phiDeg, large, sweep, x1, y1, steps) {
  rx = Math.abs(rx);
  ry = Math.abs(ry);
  if (!(rx > 0 && ry > 0)) {
    svgPathAddPoint(pts, x1, y1);
    return;
  }
  const phi = (Number(phiDeg) || 0) * Math.PI / 180;
  const cos = Math.cos(phi);
  const sin = Math.sin(phi);
  const dx = (x0 - x1) / 2;
  const dy = (y0 - y1) / 2;
  const x1p = cos * dx + sin * dy;
  const y1p = -sin * dx + cos * dy;
  let rx2 = rx * rx;
  let ry2 = ry * ry;
  const lam = (x1p * x1p) / rx2 + (y1p * y1p) / ry2;
  if (lam > 1) {
    const s = Math.sqrt(lam);
    rx *= s;
    ry *= s;
    rx2 = rx * rx;
    ry2 = ry * ry;
  }
  const sign = Number(large) !== Number(sweep) ? 1 : -1;
  const num = rx2 * ry2 - rx2 * y1p * y1p - ry2 * x1p * x1p;
  const den = rx2 * y1p * y1p + ry2 * x1p * x1p;
  const coef = sign * Math.sqrt(Math.max(0, den ? num / den : 0));
  const cxp = coef * (rx * y1p) / ry;
  const cyp = -coef * (ry * x1p) / rx;
  const cx = cos * cxp - sin * cyp + (x0 + x1) / 2;
  const cy = sin * cxp + cos * cyp + (y0 + y1) / 2;
  const vecAng = (ux, uy, vx, vy) => {
    const u = Math.hypot(ux, uy);
    const v = Math.hypot(vx, vy);
    if (!(u > 0 && v > 0)) return 0;
    let ang = Math.acos(Math.max(-1, Math.min(1, (ux * vx + uy * vy) / (u * v))));
    if (ux * vy - uy * vx < 0) ang = -ang;
    return ang;
  };
  const theta1 = vecAng(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry);
  let dtheta = vecAng(
    (x1p - cxp) / rx, (y1p - cyp) / ry,
    (-x1p - cxp) / rx, (-y1p - cyp) / ry,
  );
  if (!sweep && dtheta > 0) dtheta -= 2 * Math.PI;
  if (sweep && dtheta < 0) dtheta += 2 * Math.PI;
  const n = Math.max(steps || 16, Math.ceil(Math.abs(dtheta) / (Math.PI / 16)));
  for (let i = 1; i <= n; i++) {
    const t = theta1 + dtheta * i / n;
    svgPathAddPoint(
      pts,
      cx + rx * Math.cos(t) * cos - ry * Math.sin(t) * sin,
      cy + rx * Math.cos(t) * sin + ry * Math.sin(t) * cos,
    );
  }
}

function svgPathTrace(d) {
  const tokens = [];
  const re = /([MmLlHhVvCcSsQqTtAaZz])|([+-]?(?:\d*\.\d+|\d+)(?:[eE][+-]?\d+)?)/g;
  let match;
  while ((match = re.exec(String(d || '')))) {
    if (match[1]) tokens.push(match[1]);
    else tokens.push(Number(match[2]));
  }
  const polylines = [];
  let current = [];
  const flush = (closed) => {
    if (current.length >= 2) {
      polylines.push({pts: current.slice(), closed: !!closed});
    }
    current = [];
  };
  if (!tokens.length) return [];
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
  const steps = 16;
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
      svgPathAddPoint(current, sx, sy);
      flush(true);
      x = sx;
      y = sy;
      continue;
    }
    if (up === 'M') {
      if (current.length) flush(false);
      x = rel ? x + take() : take();
      y = rel ? y + take() : take();
      svgPathAddPoint(current, x, y);
      sx = x;
      sy = y;
      lastCmd = rel ? 'l' : 'L';
      continue;
    }
    if (up === 'L') {
      x = rel ? x + take() : take();
      y = rel ? y + take() : take();
      svgPathAddPoint(current, x, y);
    } else if (up === 'H') {
      x = rel ? x + take() : take();
      svgPathAddPoint(current, x, y);
    } else if (up === 'V') {
      y = rel ? y + take() : take();
      svgPathAddPoint(current, x, y);
    } else if (up === 'C') {
      const x1 = rel ? x + take() : take();
      const y1 = rel ? y + take() : take();
      const x2 = rel ? x + take() : take();
      const y2 = rel ? y + take() : take();
      const nx = rel ? x + take() : take();
      const ny = rel ? y + take() : take();
      svgCubicSample(current, {x, y}, {x: x1, y: y1}, {x: x2, y: y2}, {x: nx, y: ny}, steps);
      c2x = x2;
      c2y = y2;
      x = nx;
      y = ny;
    } else if (up === 'S') {
      const x2 = rel ? x + take() : take();
      const y2 = rel ? y + take() : take();
      const nx = rel ? x + take() : take();
      const ny = rel ? y + take() : take();
      const prevUp = String(prevCmd).toUpperCase();
      const x1 = prevUp === 'C' || prevUp === 'S' ? 2 * x - c2x : x;
      const y1 = prevUp === 'C' || prevUp === 'S' ? 2 * y - c2y : y;
      svgCubicSample(current, {x, y}, {x: x1, y: y1}, {x: x2, y: y2}, {x: nx, y: ny}, steps);
      c2x = x2;
      c2y = y2;
      x = nx;
      y = ny;
    } else if (up === 'Q') {
      const x1 = rel ? x + take() : take();
      const y1 = rel ? y + take() : take();
      const nx = rel ? x + take() : take();
      const ny = rel ? y + take() : take();
      svgQuadSample(current, {x, y}, {x: x1, y: y1}, {x: nx, y: ny}, steps);
      q1x = x1;
      q1y = y1;
      x = nx;
      y = ny;
    } else if (up === 'T') {
      const prevUp = String(prevCmd).toUpperCase();
      const x1 = prevUp === 'Q' || prevUp === 'T' ? 2 * x - q1x : x;
      const y1 = prevUp === 'Q' || prevUp === 'T' ? 2 * y - q1y : y;
      const nx = rel ? x + take() : take();
      const ny = rel ? y + take() : take();
      svgQuadSample(current, {x, y}, {x: x1, y: y1}, {x: nx, y: ny}, steps);
      q1x = x1;
      q1y = y1;
      x = nx;
      y = ny;
    } else if (up === 'A') {
      const rx = take();
      const ry = take();
      const rot = take();
      const large = take();
      const sweep = take();
      const nx = rel ? x + take() : take();
      const ny = rel ? y + take() : take();
      svgArcSample(current, x, y, rx, ry, rot, large, sweep, nx, ny, 24);
      x = nx;
      y = ny;
    } else {
      break;
    }
  }
  if (current.length) flush(false);
  return polylines;
}

function svgPathToRings(d) {
  const rings = [];
  for (const poly of svgPathTrace(d)) {
    const ring = svgCloseRing(poly.pts);
    if (ring.length >= 3) rings.push(ring);
  }
  return rings;
}

function svgOffsetPoly(pts, dist, closed) {
  const n = pts.length;
  const out = [];
  for (let i = 0; i < n; i++) {
    const prev = pts[closed ? (i + n - 1) % n : Math.max(0, i - 1)];
    const next = pts[closed ? (i + 1) % n : Math.min(n - 1, i + 1)];
    const dx = next.x - prev.x;
    const dy = next.y - prev.y;
    const len = Math.hypot(dx, dy);
    if (!(len > 1e-12)) {
      out.push({x: pts[i].x, y: pts[i].y});
      continue;
    }
    out.push({
      x: pts[i].x + (-dy / len) * dist,
      y: pts[i].y + (dx / len) * dist,
    });
  }
  return out;
}

function svgSemicircle(center, from, to, radius) {
  const a0 = Math.atan2(from.y - center.y, from.x - center.x);
  let a1 = Math.atan2(to.y - center.y, to.x - center.x);
  let d = a1 - a0;
  while (d <= -Math.PI) d += 2 * Math.PI;
  while (d > Math.PI) d -= 2 * Math.PI;
  const sweep = d >= 0 ? Math.PI : -Math.PI;
  const pts = [];
  const steps = 8;
  for (let i = 1; i < steps; i++) {
    const t = a0 + sweep * i / steps;
    pts.push({
      x: center.x + radius * Math.cos(t),
      y: center.y + radius * Math.sin(t),
    });
  }
  return pts;
}

// libvisio collectLine does not read LineGradient. Expand a gradient
// stroke into a filled ribbon so collectFillAndShadow FillPattern 25–40
// paints the SAP Analytics Cloud crescent / Task Center ticks.
function svgStrokeRibbon(pts, width, closed, cap) {
  const radius = width / 2;
  if (!(radius > 0) || !pts || pts.length < 2) return [];
  const left = svgOffsetPoly(pts, radius, closed);
  const right = svgOffsetPoly(pts, -radius, closed);
  const round = /^round$/i.test(String(cap || ''));
  const ring = [];
  for (const p of left) ring.push(p);
  if (!closed && round) {
    const end = pts[pts.length - 1];
    for (const p of svgSemicircle(end, left[left.length - 1], right[right.length - 1], radius)) {
      ring.push(p);
    }
  }
  for (let i = right.length - 1; i >= 0; i--) ring.push(right[i]);
  if (!closed && round) {
    const start = pts[0];
    for (const p of svgSemicircle(start, right[0], left[0], radius)) {
      ring.push(p);
    }
  }
  return svgCloseRing(ring);
}

function svgShapeStrokeRibbons(name, node, width, cap) {
  const out = [];
  if (name === 'path') {
    for (const poly of svgPathTrace(node.attrs.d)) {
      const ring = svgStrokeRibbon(poly.pts, width, poly.closed, cap);
      if (ring.length >= 3) out.push(ring);
    }
    return out;
  }
  if (name === 'line') {
    const ring = svgStrokeRibbon(
      [
        {x: Number(node.attrs.x1) || 0, y: Number(node.attrs.y1) || 0},
        {x: Number(node.attrs.x2) || 0, y: Number(node.attrs.y2) || 0},
      ],
      width, false, cap,
    );
    if (ring.length >= 3) out.push(ring);
    return out;
  }
  for (const center of svgDrawableRings(name, node)) {
    const ring = svgStrokeRibbon(center, width, true, cap);
    if (ring.length >= 3) out.push(ring);
  }
  return out;
}

function svgPaintIsTwoStopUrl(value, root, css) {
  const id = svgPaintUrlId(value);
  if (!id || !root) return false;
  const node = resolveSvgGradientNode(root, id);
  if (!node) return false;
  const stops = svgCollectStops(node, css);
  if (stops.length < 2) return false;
  return cssColorKey(stops[0].color) !== cssColorKey(stops[stops.length - 1].color);
}

function paintSvgGradientStroke(canvas, name, node, style, kind, root, css) {
  if (kind !== 'stroke') return false;
  if (!svgPaintIsTwoStopUrl(style.stroke, root, css)) return false;
  const width = svgLength(style['stroke-width'], 1);
  if (!(width > 0)) return false;
  const ribbons = svgShapeStrokeRibbons(
    name, node, width, style['stroke-linecap'],
  );
  if (!ribbons.length) return false;
  const fillStyle = {
    ...style,
    fill: style.stroke,
    stroke: 'none',
    'fill-opacity': style['stroke-opacity'] || style['fill-opacity'],
  };
  const id = svgPaintUrlId(style.stroke);
  const gradNode = id && root ? resolveSvgGradientNode(root, id) : null;
  const stops = gradNode ? svgCollectStops(gradNode, css) : null;
  // collectLine has no LineGradient. FillPattern 25–34 on the ribbon
  // still 0→1s the child XForm (the icon box). A short check stroke
  // (SAP Secure Login #B) or an off-slot ribbon must tessellate like
  // fill slabs. Full-box on-slot crescent url(#A) and Task Center
  // radial ticks stay 25–40.
  if (gradNode &&
      stops &&
      stops.length >= 2 &&
      !svgStopsHaveAlphaRamp(stops) &&
      xmlLocalName(gradNode.name) === 'lineargradient' &&
      svgLinearNeedsLocalBands(gradNode, canvas.viewBox, stops)) {
    const mapped = [];
    for (const ring of ribbons) {
      const shapeMapped = ring.map((p) => canvas.map(p.x, p.y));
      if (canvas.clipRings && canvas.clipRings.length) {
        for (const piece of svgClipMappedToRings(shapeMapped, canvas.clipRings)) {
          mapped.push(piece);
        }
      } else {
        mapped.push(shapeMapped);
      }
    }
    if (!mapped.length) return false;
    const emitBand = (fillRings, t) => {
      if (!canvas.emitMappedRings(fillRings)) return 0;
      applySvgPaint(
        canvas,
        {...fillStyle, fill: svgStopsColorAt(stops, t)},
        'fill',
        root,
        css,
      );
      return 1;
    };
    const clipToRibbon = (clipRing) => {
      const band = [];
      for (const outer of mapped) {
        for (const hit of svgIntersectPolygons(clipRing, outer)) band.push(hit);
      }
      return band;
    };
    let painted = false;
    const bands = 8;
    const span = svgRingsSpan(ribbons);
    const {tMin, tMax} = svgRingsGradientTRange(gradNode, ribbons);
    const spanT = Math.max(tMax - tMin, 1e-6);
    for (let i = 0; i < bands; i++) {
      const t0 = tMin + spanT * i / bands;
      const t1 = tMin + spanT * (i + 1) / bands;
      const slab = svgGradientSlabRing(gradNode, t0, t1, span);
      if (!slab) continue;
      const slabMapped = slab.map((p) => canvas.map(p.x, p.y));
      const sampleT = Math.max(0, Math.min(1, (t0 + t1) / 2));
      if (emitBand(clipToRibbon(slabMapped), sampleT)) painted = true;
    }
    return painted;
  }
  let painted = false;
  for (const ring of ribbons) {
    if (canvas.clipRings && canvas.clipRings.length) {
      const mapped = ring.map((p) => canvas.map(p.x, p.y));
      const pieces = svgClipMappedToRings(mapped, canvas.clipRings);
      for (const piece of pieces) {
        if (!canvas.emitMappedRing(piece)) continue;
        applySvgPaint(canvas, fillStyle, 'fill', root, css);
        painted = true;
      }
      continue;
    }
    canvas.begin();
    canvas.moveTo(ring[0].x, ring[0].y);
    for (let i = 1; i < ring.length; i++) canvas.lineTo(ring[i].x, ring[i].y);
    canvas.close();
    applySvgPaint(canvas, fillStyle, 'fill', root, css);
    painted = true;
  }
  return painted;
}

function svgDrawableRings(name, node) {
  if (name === 'path') return svgPathToRings(node.attrs.d);
  if (name === 'circle') {
    const r = Number(node.attrs.r) || 0;
    if (!(r > 0)) return [];
    return [svgCircleRing(Number(node.attrs.cx) || 0, Number(node.attrs.cy) || 0, r)];
  }
  if (name === 'ellipse') {
    const rx = Number(node.attrs.rx) || 0;
    const ry = Number(node.attrs.ry) || 0;
    if (!(rx > 0 && ry > 0)) return [];
    return [svgEllipseRing(
      Number(node.attrs.cx) || 0, Number(node.attrs.cy) || 0, rx, ry,
    )];
  }
  if (name === 'rect') {
    const w = Number(node.attrs.width) || 0;
    const h = Number(node.attrs.height) || 0;
    if (!(w > 0 && h > 0)) return [];
    return [svgRectRing(
      Number(node.attrs.x) || 0, Number(node.attrs.y) || 0, w, h,
      Number(node.attrs.rx) || 0, Number(node.attrs.ry) || Number(node.attrs.rx) || 0,
    )];
  }
  if (name === 'polygon' || name === 'polyline') {
    const nums = parseSvgNumbers(node.attrs.points);
    const ring = [];
    for (let i = 0; i + 1 < nums.length; i += 2) {
      ring.push({x: nums[i], y: nums[i + 1]});
    }
    return name === 'polygon' || ring.length >= 3 ? [svgCloseRing(ring)].filter((r) => r.length >= 3) : [];
  }
  if (name === 'line') {
    return [];
  }
  return [];
}

function svgClipPathRings(clipNode, root) {
  const rings = [];
  const seen = new Set();
  const walk = (node, tf) => {
    const name = xmlLocalName(node.name);
    if (name === '#text' || svgSkip.has(name)) return;
    const local = svgComposeTransformRaw(tf, node.attrs && node.attrs.transform);
    if (name === 'g' || name === 'svg' || name === 'symbol' || name === 'a') {
      for (const child of node.children || []) walk(child, local);
      return;
    }
    if (name === 'use') {
      const href = node.attrs.href || node.attrs['xlink:href'] || '';
      const id = String(href).replace(/^#/, '');
      if (!id || !root || seen.has(id)) return;
      const target = findSvgById(root, id);
      if (!target || target === node) return;
      seen.add(id);
      const ox = Number(node.attrs.x) || 0;
      const oy = Number(node.attrs.y) || 0;
      let useTf = local;
      if (xmlLocalName(target.name) === 'symbol') {
        const vb = parseSvgNumbers(target.attrs.viewBox);
        const vx = vb.length >= 4 ? vb[0] : 0;
        const vy = vb.length >= 4 ? vb[1] : 0;
        const vw = vb.length >= 4 ? vb[2] : 0;
        const vh = vb.length >= 4 ? vb[3] : 0;
        const w = Number(node.attrs.width) || vw;
        const h = Number(node.attrs.height) || vh;
        if (vw > 0 && vh > 0 && w > 0 && h > 0) {
          useTf = svgComposeTransformRaw(
            useTf,
            `translate(${ox} ${oy}) scale(${w / vw} ${h / vh}) translate(${-vx} ${-vy})`,
          );
        } else if (ox || oy) {
          useTf = svgComposeTransformRaw(useTf, `translate(${ox} ${oy})`);
        }
      } else if (ox || oy) {
        useTf = svgComposeTransformRaw(useTf, `translate(${ox} ${oy})`);
      }
      walk(target, useTf);
      seen.delete(id);
      return;
    }
    for (const ring of svgDrawableRings(name, node)) {
      const mapped = svgCloseRing(svgMapRing(ring, local));
      if (mapped.length >= 3) rings.push(mapped);
    }
  };
  const clipTf = clipNode.attrs && clipNode.attrs.transform;
  for (const child of clipNode.children || []) walk(child, clipTf);
  return rings;
}

function svgOwnCssUrl(node, css, prop) {
  let fromStyle = '';
  for (const part of String(node.attrs.style || '').split(';')) {
    const token = part.trim();
    const split = token.indexOf(':');
    if (split < 0) continue;
    if (token.slice(0, split).trim().toLowerCase() === prop) {
      fromStyle = token.slice(split + 1).trim();
    }
  }
  const fromCss = svgCssForNode(node, css)[prop];
  return String(node.attrs[prop] || fromStyle || fromCss || '').trim();
}

// SVG clip-path / luminance mask have no libvisio token. Intersect fill
// contours in map() space (Globe meridians, SAP Build letter). ViewBox
// rect clips are identity so ellipses stay ellipses. Mask content follows
// maskContentUnits (default userSpaceOnUse); maskUnits only sizes the
// region so a missing maskUnits is not a skip (Allied Telesis VOIP / Secure Building).
function applySvgClipLike(canvas, raw, expectedName, unitsKey, root) {
  if (!raw || /^none$/i.test(raw)) return false;
  const id = svgPaintUrlId(raw);
  if (!id || !root) return false;
  const clipNode = findSvgById(root, id);
  if (!clipNode || xmlLocalName(clipNode.name) !== expectedName) return false;
  const units = String(clipNode.attrs[unitsKey] || '').toLowerCase();
  if (units === 'objectboundingbox') return false;
  const userRings = svgClipPathRings(clipNode, root);
  if (!userRings.length) return false;
  if (!canvas.clipRings && svgClipCoversViewBox(userRings, canvas.viewBox)) {
    return false;
  }
  const mapped = userRings.map((ring) => ring.map((p) => canvas.map(p.x, p.y)));
  canvas.save();
  if (canvas.clipRings && canvas.clipRings.length) {
    const next = [];
    for (const prev of canvas.clipRings) {
      for (const ring of mapped) {
        for (const piece of svgIntersectPolygons(prev, ring)) next.push(piece);
      }
    }
    canvas.clipRings = next;
  } else {
    canvas.clipRings = mapped;
  }
  return true;
}

function applySvgClipPath(canvas, node, root, css) {
  return applySvgClipLike(
    canvas, svgOwnCssUrl(node, css, 'clip-path'), 'clippath', 'clipPathUnits',
    root,
  );
}

function applySvgMask(canvas, node, root, css) {
  return applySvgClipLike(
    canvas, svgOwnCssUrl(node, css, 'mask'), 'mask', 'maskContentUnits', root,
  );
}

// SVG feOffset + SourceGraphic blend is a drop shadow. libvisio has no
// filter token; `_fillAndShadowProperties` maps ShdwPattern to ODF
// draw:shadow (SAP Build Work Zone / Product Insights). Blur-only
// feGaussianBlur is tessellated separately — Draw cannot gaussian-blur
// a native cell.
function svgFilterDropShadow(filterNode) {
  let dx = 0;
  let dy = 0;
  let best = 0;
  let hasOffset = false;
  let alpha = 0.4;
  const walk = (n) => {
    const name = xmlLocalName(n && n.name);
    if (name === 'feoffset') {
      const odx = Number(n.attrs.dx) || 0;
      const ody = Number(n.attrs.dy) || 0;
      const mag = odx * odx + ody * ody;
      if (mag >= best) {
        dx = odx;
        dy = ody;
        best = mag;
      }
      hasOffset = true;
    } else if (name === 'fecolormatrix') {
      const vals = parseSvgNumbers(n.attrs.values);
      if (vals.length >= 20) {
        const aScale = vals[18];
        if (aScale > 0 && aScale <= 1) alpha = aScale;
      }
    }
    for (const child of (n && n.children) || []) walk(child);
  };
  walk(filterNode);
  if (!hasOffset || best < 1e-18) return null;
  return {dx, dy, alpha, color: '#000000'};
}

// Blur-only feGaussianBlur (Dynamics365 Talent Attract / Copilot Studio
// inner glows) has no feOffset, so svgFilterDropShadow returns null.
// SoftEdgesSize is not a token and leftover SoftEdges PNG composites
// onto opaque white over the sibling plate. Expand the contour by
// stdDeviation and paint FillPattern 1 + FillForegndTrans rings
// collectFillAndShadow maps to draw:opacity. Tiny σ (<0.5 user units)
// stays a single hard fill.
function svgFilterForegroundBlur(filterNode) {
  let sigma = 0;
  let hasOffset = false;
  const walk = (n) => {
    const name = xmlLocalName(n && n.name);
    if (name === 'feoffset') {
      const dx = Number(n.attrs.dx) || 0;
      const dy = Number(n.attrs.dy) || 0;
      if (dx * dx + dy * dy > 1e-8) hasOffset = true;
    } else if (name === 'fegaussianblur') {
      const parts = String(n.attrs.stdDeviation || '0').trim().split(/[\s,]+/);
      const sx = Math.abs(Number(parts[0]) || 0);
      const sy = parts.length > 1 ? Math.abs(Number(parts[1]) || sx) : sx;
      sigma = Math.max(sigma, (sx + sy) / 2);
    }
    for (const child of (n && n.children) || []) walk(child);
  };
  walk(filterNode);
  if (hasOffset || !(sigma > 0.5)) return 0;
  return sigma;
}

function svgOutsetRing(ring, dist) {
  const ccw = svgEnsureCcw(svgCloseRing(ring));
  if (ccw.length < 3) return [];
  if (!(dist > 1e-6)) return ccw;
  // svgOffsetPoly(+dist) follows the left-of-tangent convention used by
  // stroke ribbons. Positive-area (math CCW) rings therefore inset;
  // negate so a blur halo grows the filled contour.
  return svgCloseRing(svgOffsetPoly(ccw, -dist, true));
}

function applySvgFilter(canvas, node, root, css) {
  const raw = svgOwnCssUrl(node, css, 'filter');
  if (!raw || /^none$/i.test(raw)) return false;
  const id = svgPaintUrlId(raw);
  if (!id || !root) return false;
  const filterNode = findSvgById(root, id);
  if (!filterNode || xmlLocalName(filterNode.name) !== 'filter') return false;
  const shadow = svgFilterDropShadow(filterNode);
  if (shadow) {
    const origin = canvas.map(0, 0);
    const tip = canvas.map(shadow.dx, shadow.dy);
    canvas.setShadowColor(shadow.color);
    canvas.setShadowAlpha(shadow.alpha);
    canvas.setShadowOffset(tip.x - origin.x, tip.y - origin.y);
    canvas.setShadow(true);
    return 'shadow';
  }
  const sigma = svgFilterForegroundBlur(filterNode);
  if (sigma > 0) {
    canvas.blurSigma = sigma;
    return 'blur';
  }
  return false;
}

function paintSvgBlurHaloFill(canvas, name, node, style, kind, root, css) {
  const sigma = canvas.blurSigma;
  if (!(sigma > 0.5)) return false;
  if (kind !== 'fill' && kind !== 'fillstroke') return false;
  const fill = style.fill == null ? '#000' : style.fill;
  if (svgPaintUrlId(fill) || svgPaintIsNone(fill)) return false;
  const rings = svgDrawableRings(name, node);
  if (!rings.length) return false;
  const baseOp = svgCssAlpha(style['fill-opacity']);
  const inheritOp = (baseOp == null ? 1 : baseOp) *
      (svgCssAlpha(style.opacity) == null ? 1 : svgCssAlpha(style.opacity));
  const bands = [
    {t: 1.6, a: inheritOp * 0.1},
    {t: 1.0, a: inheritOp * 0.22},
    {t: 0.45, a: inheritOp * 0.45},
    {t: 0, a: inheritOp},
  ];
  let painted = false;
  for (const band of bands) {
    const mapped = [];
    for (const ring of rings) {
      const expanded = svgOutsetRing(ring, band.t * sigma);
      if (expanded.length < 3) continue;
      const shapeMapped = expanded.map((p) => canvas.map(p.x, p.y));
      if (canvas.clipRings && canvas.clipRings.length) {
        for (const piece of svgClipMappedToRings(shapeMapped, canvas.clipRings)) {
          mapped.push(piece);
        }
      } else {
        mapped.push(shapeMapped);
      }
    }
    if (!canvas.emitMappedRings(mapped)) continue;
    applySvgPaint(
      canvas,
      {
        ...style,
        fill,
        stroke: 'none',
        opacity: '1',
        'fill-opacity': String(Math.max(0, Math.min(1, band.a))),
      },
      'fill',
      root,
      css,
    );
    painted = true;
  }
  if (!painted) return false;
  if (kind === 'fillstroke' && !svgPaintIsNone(style.stroke)) {
    if (name === 'path') paintSvgPath(canvas, node.attrs.d);
    else if (name === 'circle') {
      const cx = Number(node.attrs.cx) || 0;
      const cy = Number(node.attrs.cy) || 0;
      const r = Number(node.attrs.r) || 0;
      if (r > 0) canvas.ellipse(cx - r, cy - r, r * 2, r * 2);
    }
    applySvgPaint(canvas, {...style, fill: 'none'}, 'stroke', root, css);
  }
  return true;
}

// SVG stop-opacity and element opacity cannot use FillPattern 25–40
// (Draw ignores librevenge:*-opacity / drops draw:opacity) or leftover
// SoftEdges PNG (Foreign images composite onto opaque white). Tessellate
// non-overlapping slabs / annuli as FillPattern 1 + FillForegndTrans
// so collectFillAndShadow emits draw:opacity (Azure Translator Text
// white→0.3 highlights; Intune Software Updates 0.9 wash over #0078d4).
function paintSvgAlphaRampFill(canvas, name, node, style, kind, root, css) {
  if (kind !== 'fill' && kind !== 'fillstroke') return false;
  const fill = style.fill == null ? '#000' : style.fill;
  const id = svgPaintUrlId(fill);
  if (!id || !root) return false;
  const gradNode = resolveSvgGradientNode(root, id);
  if (!gradNode) return false;
  const stops = svgCollectStops(gradNode, css);
  if (!svgFillNeedsAlphaBands(stops, style)) return false;
  const rings = svgDrawableRings(name, node);
  if (!rings.length) return false;
  const mapped = [];
  for (const ring of rings) {
    const shapeMapped = ring.map((p) => canvas.map(p.x, p.y));
    if (canvas.clipRings && canvas.clipRings.length) {
      for (const piece of svgClipMappedToRings(shapeMapped, canvas.clipRings)) {
        mapped.push(piece);
      }
    } else {
      mapped.push(shapeMapped);
    }
  }
  if (!mapped.length) return false;
  const {outers, holes} = svgSplitEvenoddRings(mapped);
  const baseOp = svgCssAlpha(style['fill-opacity']);
  const inheritOp = baseOp == null ? 1 : baseOp;
  const emitBand = (fillRings, t) => {
    if (!canvas.emitMappedRings(fillRings)) return 0;
    const alpha = Math.max(0, Math.min(1, inheritOp * svgStopsAlphaAt(stops, t)));
    applySvgPaint(
      canvas,
      {
        ...style,
        fill: svgStopsColorAt(stops, t),
        stroke: 'none',
        'fill-opacity': String(alpha),
      },
      'fill',
      root,
      css,
    );
    return 1;
  };
  const clipToGlyph = (clipRing) => {
    const band = [];
    for (const outer of outers) {
      for (const hit of svgIntersectPolygons(clipRing, outer)) band.push(hit);
    }
    if (!band.length) return band;
    for (const hole of holes) {
      for (const hit of svgIntersectPolygons(clipRing, hole)) band.push(hit);
    }
    return band;
  };
  let painted = false;
  const bands = 8;
  if (xmlLocalName(gradNode.name) === 'radialgradient') {
    const disc1 = svgRadialDiscRing(gradNode, 1).map((p) => canvas.map(p.x, p.y));
    const outside = mapped.slice();
    for (const hit of clipToGlyph(disc1)) outside.push(hit);
    if (emitBand(outside, 1)) painted = true;
    for (let i = bands - 1; i >= 0; i--) {
      const tLo = i / bands;
      const tHi = (i + 1) / bands;
      const discHi = svgRadialDiscRing(gradNode, tHi).map((p) => canvas.map(p.x, p.y));
      const band = clipToGlyph(discHi);
      if (tLo > 1e-6) {
        const discLo = svgRadialDiscRing(gradNode, tLo).map((p) => canvas.map(p.x, p.y));
        for (const hit of clipToGlyph(discLo)) band.push(hit);
      }
      if (emitBand(band, (tLo + tHi) / 2)) painted = true;
    }
  } else {
    const span = svgRingsSpan(rings);
    const {tMin, tMax} = svgRingsGradientTRange(gradNode, rings);
    const spanT = Math.max(tMax - tMin, 1e-6);
    for (let i = 0; i < bands; i++) {
      const t0 = tMin + spanT * i / bands;
      const t1 = tMin + spanT * (i + 1) / bands;
      const slab = svgGradientSlabRing(gradNode, t0, t1, span);
      if (!slab) continue;
      const slabMapped = slab.map((p) => canvas.map(p.x, p.y));
      const sampleT = Math.max(0, Math.min(1, (t0 + t1) / 2));
      if (emitBand(clipToGlyph(slabMapped), sampleT)) painted = true;
    }
  }
  if (!painted) {
    // Azure Sphere visor: userSpaceOnUse x1/y1 sit at y≈-3114, so every
    // glyph sample shares one t and svgGradientSlabRing misses the path.
    // Paint the contour once at that t (svgStopsAlphaAt clamps).
    let sampleT = 0.5;
    if (xmlLocalName(gradNode.name) !== 'radialgradient') {
      const {tMin, tMax} = svgRingsGradientTRange(gradNode, rings);
      sampleT = (tMin + tMax) / 2;
    }
    if (emitBand(mapped, sampleT)) painted = true;
  }
  if (kind === 'fillstroke' && !svgPaintIsNone(style.stroke)) {
    if (canvas.clipRings && canvas.clipRings.length) {
      paintSvgClippedStrokeRibbons(canvas, name, node, style, root, css);
    }
  }
  return painted;
}

// FillPattern 25–34 / leftover FillGradient interpolate 0→1 on the
// XForm. Short userSpaceOnUse vectors (SAP Analytics Cloud #B) and
// off-slot long bars (Power BI Embedded ~22°) need solid FillForegnd
// slabs along the authored axis so Draw keeps the wedge colours
// without a white SoftEdges PNG over siblings. Full-box on-slot
// ramps (SAP Logo, crescent stroke A) stay native 25–40.
function paintSvgLocalLinearFill(canvas, name, node, style, kind, root, css) {
  if (kind !== 'fill' && kind !== 'fillstroke') return false;
  const fill = style.fill == null ? '#000' : style.fill;
  const id = svgPaintUrlId(fill);
  if (!id || !root) return false;
  const gradNode = resolveSvgGradientNode(root, id);
  if (!gradNode) return false;
  const stops = svgCollectStops(gradNode, css);
  if (!stops || stops.length < 2) return false;
  if (svgStopsHaveAlphaRamp(stops)) return false;
  if (!svgLinearNeedsLocalBands(gradNode, canvas.viewBox, stops)) return false;
  const rings = svgDrawableRings(name, node);
  if (!rings.length) return false;
  const mapped = [];
  for (const ring of rings) {
    const shapeMapped = ring.map((p) => canvas.map(p.x, p.y));
    if (canvas.clipRings && canvas.clipRings.length) {
      for (const piece of svgClipMappedToRings(shapeMapped, canvas.clipRings)) {
        mapped.push(piece);
      }
    } else {
      mapped.push(shapeMapped);
    }
  }
  if (!mapped.length) return false;
  const {outers, holes} = svgSplitEvenoddRings(mapped);
  const emitBand = (fillRings, t) => {
    if (!canvas.emitMappedRings(fillRings)) return 0;
    applySvgPaint(
      canvas,
      {...style, fill: svgStopsColorAt(stops, t), stroke: 'none'},
      'fill',
      root,
      css,
    );
    return 1;
  };
  const clipToGlyph = (clipRing) => {
    const band = [];
    for (const outer of outers) {
      for (const hit of svgIntersectPolygons(clipRing, outer)) band.push(hit);
    }
    if (!band.length) return band;
    for (const hole of holes) {
      for (const hit of svgIntersectPolygons(clipRing, hole)) band.push(hit);
    }
    return band;
  };
  let painted = false;
  const bands = 8;
  const span = svgRingsSpan(rings);
  const {tMin, tMax} = svgRingsGradientTRange(gradNode, rings);
  const spanT = Math.max(tMax - tMin, 1e-6);
  for (let i = 0; i < bands; i++) {
    const t0 = tMin + spanT * i / bands;
    const t1 = tMin + spanT * (i + 1) / bands;
    const slab = svgGradientSlabRing(gradNode, t0, t1, span);
    if (!slab) continue;
    const slabMapped = slab.map((p) => canvas.map(p.x, p.y));
    const sampleT = Math.max(0, Math.min(1, (t0 + t1) / 2));
    if (emitBand(clipToGlyph(slabMapped), sampleT)) painted = true;
  }
  if (kind === 'fillstroke' && !svgPaintIsNone(style.stroke)) {
    if (canvas.clipRings && canvas.clipRings.length) {
      paintSvgClippedStrokeRibbons(canvas, name, node, style, root, css);
    }
  }
  return painted;
}

// FillPattern 40 is a circle at the XForm centre. Tessellate an
// elliptical, offset/undersized, inset-stop, or >2-colour
// userSpaceOnUse radial as concentric solid discs clipped to the
// glyph so collectFillAndShadow sees FillForegnd siblings Draw can
// paint (SAP Build Apps / Work Zone blobs; Open Supply Chain corner
// discs; Cosmos DB offset=".183"; Azure Applied AI three-stop
// ellipse). Compound evenodd holes stay one Geometry (Azure OpenAI
// swirl, Task Center donuts).
function paintSvgEllipticalRadialFill(canvas, name, node, style, kind, root, css) {
  if (kind !== 'fill' && kind !== 'fillstroke') return false;
  const fill = style.fill == null ? '#000' : style.fill;
  const id = svgPaintUrlId(fill);
  if (!id || !root) return false;
  const gradNode = resolveSvgGradientNode(root, id);
  if (!gradNode) return false;
  const stops = svgCollectStops(gradNode, css);
  if (!svgRadialNeedsEllipseBands(gradNode, stops, canvas.viewBox)) return false;
  const rings = svgDrawableRings(name, node);
  if (!rings.length) return false;
  const mapped = [];
  for (const ring of rings) {
    const shapeMapped = ring.map((p) => canvas.map(p.x, p.y));
    if (canvas.clipRings && canvas.clipRings.length) {
      for (const piece of svgClipMappedToRings(shapeMapped, canvas.clipRings)) {
        mapped.push(piece);
      }
    } else {
      mapped.push(shapeMapped);
    }
  }
  if (!mapped.length) return false;
  const {outers, holes} = svgSplitEvenoddRings(mapped);
  const emitSolid = (fillRings, color) => {
    if (!canvas.emitMappedRings(fillRings)) return 0;
    applySvgPaint(
      canvas, {...style, fill: color, stroke: 'none'}, 'fill', root, css,
    );
    return 1;
  };
  const emitDisc = (t, color) => {
    const discMapped = svgRadialDiscRing(gradNode, t).map((p) => canvas.map(p.x, p.y));
    const band = [];
    for (const outer of outers) {
      for (const hit of svgIntersectPolygons(discMapped, outer)) band.push(hit);
    }
    if (!band.length) return 0;
    for (const hole of holes) {
      for (const hit of svgIntersectPolygons(discMapped, hole)) band.push(hit);
    }
    return emitSolid(band, color);
  };
  let painted = false;
  if (emitSolid(mapped, svgStopsColorAt(stops, 1))) painted = true;
  const bands = 8;
  for (let i = bands - 1; i >= 1; i--) {
    const t = i / bands;
    if (emitDisc(t, svgStopsColorAt(stops, t))) painted = true;
  }
  // i/8 interpolation never lands on CSS named stops (Azure Application
  // Gateway Containers `silver` at offset 0.402). Emit those discs so
  // FillForegnd stays #C0C0C0 / #808080 that collectFillAndShadow paints.
  for (let s = stops.length - 1; s >= 0; s--) {
    const t = Number(stops[s].offset);
    if (!Number.isFinite(t) || t <= 1e-6 || t >= 1 - 1e-6) continue;
    if (emitDisc(t, stops[s].color)) painted = true;
  }
  if (kind === 'fillstroke' && !svgPaintIsNone(style.stroke)) {
    if (canvas.clipRings && canvas.clipRings.length) {
      paintSvgClippedStrokeRibbons(canvas, name, node, style, root, css);
    }
  }
  return painted;
}

function paintSvgClippedStrokeRibbons(canvas, name, node, style, root, css) {
  const width = svgLength(style['stroke-width'], 1);
  if (!(width > 0)) return false;
  const ribbons = svgShapeStrokeRibbons(
    name, node, width, style['stroke-linecap'],
  );
  if (!ribbons.length) return false;
  const fillStyle = {
    ...style,
    fill: style.stroke,
    stroke: 'none',
    'fill-opacity': style['stroke-opacity'] || style['fill-opacity'],
  };
  let painted = false;
  for (const ring of ribbons) {
    const mapped = ring.map((p) => canvas.map(p.x, p.y));
    const pieces = svgClipMappedToRings(mapped, canvas.clipRings);
    for (const piece of pieces) {
      if (!canvas.emitMappedRing(piece)) continue;
      applySvgPaint(canvas, fillStyle, 'fill', root, css);
      painted = true;
    }
  }
  return painted;
}

function paintSvgClippedShape(canvas, name, node, style, kind, root, css) {
  // Open stroke paths have no fill ring. Intersecting the path chord would
  // drop Allied Telesis VOIP handset strokes; expand to a ribbon like gradient strokes
  // so collectFillAndShadow sees a polygon LibreOffice can paint.
  if (kind === 'stroke') {
    return paintSvgClippedStrokeRibbons(canvas, name, node, style, root, css);
  }
  const rings = svgDrawableRings(name, node);
  if (!rings.length) return false;
  let painted = false;
  const fillStyle = {...style, fill: style.fill == null ? '#000' : style.fill};
  for (const userRing of rings) {
    const mapped = userRing.map((p) => canvas.map(p.x, p.y));
    const pieces = svgClipMappedToRings(mapped, canvas.clipRings);
    for (const piece of pieces) {
      if (!canvas.emitMappedRing(piece)) continue;
      applySvgPaint(canvas, fillStyle, kind, root, css);
      painted = true;
    }
  }
  return painted;
}

// Canvas map() is translate+scale+rotate. Off-diagonal SVG matrix(a,b,c,d,e,f)
// (MSCAE Event Grid Topics 45°, IBM Microservices ~90°) is composeAffine so
// collectGeometry sees the rotated contour; scale(a,d) alone shrinks the glyph.
function applySvgTransform(canvas, raw) {
  const ops = parseSvgTransformList(raw);
  if (!ops.length) return false;
  canvas.save();
  for (const op of ops) {
    const n = op.nums;
    if (op.kind === 'translate') {
      canvas.translate(n[0] || 0, n[1] || 0);
    } else if (op.kind === 'scale') {
      const sx = n[0] == null ? 1 : n[0];
      canvas.scale(sx, n.length > 1 ? n[1] : sx);
    } else if (op.kind === 'rotate') {
      // SVG rotate(a,cx,cy) is translate·rotate·translate in user space.
      // canvas.rotate() pivots after map() scale, so Search's
      // rotate(-45,4.49,13.71) handle collapsed under the lens. Compose
      // the same matrix svgTransformPoint uses (clip / gradient).
      const rad = (n[0] || 0) * Math.PI / 180;
      const cos = Math.cos(rad);
      const sin = Math.sin(rad);
      const cx = n[1] || 0;
      const cy = n[2] || 0;
      if (cx || cy) canvas.composeAffine(1, 0, 0, 1, cx, cy);
      canvas.composeAffine(cos, sin, -sin, cos, 0, 0);
      if (cx || cy) canvas.composeAffine(1, 0, 0, 1, -cx, -cy);
    } else if (op.kind === 'skewx') {
      const tan = Math.tan((n[0] || 0) * Math.PI / 180);
      canvas.composeAffine(1, 0, tan, 1, 0, 0);
    } else if (op.kind === 'skewy') {
      const tan = Math.tan((n[0] || 0) * Math.PI / 180);
      canvas.composeAffine(1, tan, 0, 1, 0, 0);
    } else if (op.kind === 'matrix' && n.length >= 6) {
      if (Math.abs(n[1]) < 1e-8 && Math.abs(n[2]) < 1e-8) {
        canvas.translate(n[4], n[5]);
        canvas.scale(n[0], n[3]);
      } else {
        canvas.composeAffine(n[0], n[1], n[2], n[3], n[4], n[5]);
      }
    }
  }
  return true;
}

function svgPathTokens(d) {
  const tokens = [];
  const re = /([MmLlHhVvCcSsQqTtAaZz])|([+-]?(?:\d*\.\d+|\d+)(?:[eE][+-]?\d+)?)/g;
  let match;
  while ((match = re.exec(String(d || '')))) {
    if (match[1]) tokens.push(match[1]);
    else tokens.push(Number(match[2]));
  }
  return tokens;
}

function svgPathCommandList(d) {
  const tokens = svgPathTokens(d);
  if (!tokens.length) return [];
  const commands = [];
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
      commands.push({kind: 'close'});
      x = sx;
      y = sy;
      continue;
    }
    if (up === 'M') {
      x = rel ? x + take() : take();
      y = rel ? y + take() : take();
      commands.push({kind: 'move', x, y});
      sx = x;
      sy = y;
      lastCmd = rel ? 'l' : 'L';
      continue;
    }
    if (up === 'L') {
      x = rel ? x + take() : take();
      y = rel ? y + take() : take();
      commands.push({kind: 'line', x, y});
    } else if (up === 'H') {
      x = rel ? x + take() : take();
      commands.push({kind: 'line', x, y});
    } else if (up === 'V') {
      y = rel ? y + take() : take();
      commands.push({kind: 'line', x, y});
    } else if (up === 'C') {
      const x1 = rel ? x + take() : take();
      const y1 = rel ? y + take() : take();
      const x2 = rel ? x + take() : take();
      const y2 = rel ? y + take() : take();
      x = rel ? x + take() : take();
      y = rel ? y + take() : take();
      commands.push({kind: 'curve', x1, y1, x2, y2, x, y});
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
      commands.push({kind: 'curve', x1, y1, x2, y2, x: nx, y: ny});
      c2x = x2;
      c2y = y2;
      x = nx;
      y = ny;
    } else if (up === 'Q') {
      const x1 = rel ? x + take() : take();
      const y1 = rel ? y + take() : take();
      x = rel ? x + take() : take();
      y = rel ? y + take() : take();
      commands.push({kind: 'quad', x1, y1, x, y});
      q1x = x1;
      q1y = y1;
    } else if (up === 'T') {
      const prevUp = String(prevCmd).toUpperCase();
      const x1 = prevUp === 'Q' || prevUp === 'T' ? 2 * x - q1x : x;
      const y1 = prevUp === 'Q' || prevUp === 'T' ? 2 * y - q1y : y;
      x = rel ? x + take() : take();
      y = rel ? y + take() : take();
      commands.push({kind: 'quad', x1, y1, x, y});
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
      commands.push({kind: 'arc', rx, ry, rot, large, sweep, x, y});
    } else {
      break;
    }
  }
  return commands;
}

function svgOpsToRing(ops) {
  const pts = [];
  let x = 0;
  let y = 0;
  let sx = 0;
  let sy = 0;
  for (const op of ops) {
    if (op.kind === 'move') {
      x = op.x;
      y = op.y;
      sx = x;
      sy = y;
      svgPathAddPoint(pts, x, y);
    } else if (op.kind === 'line') {
      x = op.x;
      y = op.y;
      svgPathAddPoint(pts, x, y);
    } else if (op.kind === 'curve') {
      svgCubicSample(
        pts, {x, y}, {x: op.x1, y: op.y1}, {x: op.x2, y: op.y2}, {x: op.x, y: op.y}, 16,
      );
      x = op.x;
      y = op.y;
    } else if (op.kind === 'quad') {
      svgQuadSample(pts, {x, y}, {x: op.x1, y: op.y1}, {x: op.x, y: op.y}, 16);
      x = op.x;
      y = op.y;
    } else if (op.kind === 'arc') {
      svgArcSample(pts, x, y, op.rx, op.ry, op.rot, op.large, op.sweep, op.x, op.y, 24);
      x = op.x;
      y = op.y;
    } else if (op.kind === 'close') {
      svgPathAddPoint(pts, sx, sy);
      x = sx;
      y = sy;
    }
  }
  return svgCloseRing(pts);
}

function svgPathSubpaths(d) {
  const commands = svgPathCommandList(d);
  const subpaths = [];
  let current = [];
  const flush = () => {
    if (!current.length) return;
    subpaths.push({ops: current, ring: svgOpsToRing(current)});
    current = [];
  };
  for (const op of commands) {
    if (op.kind === 'move' && current.length) flush();
    current.push(op);
  }
  flush();
  return subpaths;
}

function paintSvgPathCommands(canvas, commands) {
  if (!commands || !commands.length) return false;
  canvas.begin();
  for (const op of commands) {
    if (op.kind === 'move') canvas.moveTo(op.x, op.y);
    else if (op.kind === 'line') canvas.lineTo(op.x, op.y);
    else if (op.kind === 'curve') {
      canvas.curveTo(op.x1, op.y1, op.x2, op.y2, op.x, op.y);
    } else if (op.kind === 'quad') canvas.quadTo(op.x1, op.y1, op.x, op.y);
    else if (op.kind === 'arc') {
      canvas.arcTo(op.rx, op.ry, op.rot, op.large, op.sweep, op.x, op.y);
    } else if (op.kind === 'close') canvas.close();
  }
  return true;
}

function paintSvgPath(canvas, d) {
  return paintSvgPathCommands(canvas, svgPathCommandList(d));
}

function svgFillRuleIsEvenodd(style) {
  return /^evenodd$/i.test(String((style && style['fill-rule']) || ''));
}

function svgRingCentroid(ring) {
  let x = 0;
  let y = 0;
  for (const p of ring) {
    x += p.x;
    y += p.y;
  }
  return {x: x / ring.length, y: y / ring.length};
}

function svgRingContainsPoint(ring, p) {
  let inside = false;
  for (let i = 0, n = ring.length, j = n - 1; i < n; j = i++) {
    const a = ring[i];
    const b = ring[j];
    if ((a.y > p.y) !== (b.y > p.y) &&
        p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x) {
      inside = !inside;
    }
  }
  return inside;
}

// libvisio collectGeometry always concatenates NoFill=0 contours with
// svg:fill-rule=evenodd. SVG default (and IBM VPC VPN Policy's explicit
// fill-rule="nonzero") fills same-winding nested subpaths as a union.
// Opposite-winding nested rings are holes in both rules, so they stay
// one Geometry (Load Balancer Listener donut). Root evenodd (SAP HANA,
// OpenAI swirl) keeps the authored compound path.
function svgNonzeroHolesTogether(a, b) {
  if (!a || !b || a.length < 3 || b.length < 3) return false;
  const areaA = svgPolyArea(a);
  const areaB = svgPolyArea(b);
  if (!(areaA * areaB < 0)) return false;
  const inner = Math.abs(areaA) < Math.abs(areaB) ? a : b;
  const outer = inner === a ? b : a;
  return svgRingContainsPoint(outer, svgRingCentroid(inner));
}

function svgGroupNonzeroSubpaths(subpaths) {
  const n = subpaths.length;
  const parent = subpaths.map((_, i) => i);
  const find = (i) => (parent[i] === i ? i : (parent[i] = find(parent[i])));
  const union = (a, b) => {
    parent[find(a)] = find(b);
  };
  for (let i = 0; i < n; i++) {
    for (let j = i + 1; j < n; j++) {
      if (svgNonzeroHolesTogether(subpaths[i].ring, subpaths[j].ring)) {
        union(i, j);
      }
    }
  }
  const groups = [];
  const index = new Map();
  for (let i = 0; i < n; i++) {
    const p = find(i);
    if (!index.has(p)) {
      index.set(p, groups.length);
      groups.push([]);
    }
    groups[index.get(p)].push(subpaths[i]);
  }
  return groups;
}

function paintSvgNonzeroCompoundFill(canvas, d, style, kind, root, css) {
  if (kind !== 'fill' && kind !== 'fillstroke') return false;
  if (svgFillRuleIsEvenodd(style)) return false;
  const subpaths = svgPathSubpaths(d);
  if (subpaths.length < 2) return false;
  const groups = svgGroupNonzeroSubpaths(subpaths);
  if (groups.length < 2) return false;
  const fillStyle = {...style, stroke: 'none'};
  let painted = false;
  for (const group of groups) {
    const ops = [];
    for (const sub of group) {
      for (const op of sub.ops) ops.push(op);
    }
    if (!paintSvgPathCommands(canvas, ops)) continue;
    applySvgPaint(canvas, fillStyle, 'fill', root, css);
    painted = true;
  }
  if (painted && kind === 'fillstroke' && !svgPaintIsNone(style.stroke)) {
    if (paintSvgPath(canvas, d)) {
      applySvgPaint(canvas, {...style, fill: 'none'}, 'stroke', root, css);
    }
  }
  return painted;
}

function svgPathAddPoint(pts, x, y) {
  const last = pts.length ? pts[pts.length - 1] : null;
  if (last && Math.abs(last.x - x) < 1e-9 && Math.abs(last.y - y) < 1e-9) return;
  pts.push({x, y});
}

function svgCubicSample(pts, p0, p1, p2, p3, steps) {
  for (let i = 1; i <= steps; i++) {
    const t = i / steps;
    const u = 1 - t;
    svgPathAddPoint(
      pts,
      u * u * u * p0.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * p3.x,
      u * u * u * p0.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * p3.y,
    );
  }
}

function svgQuadSample(pts, p0, p1, p2, steps) {
  for (let i = 1; i <= steps; i++) {
    const t = i / steps;
    const u = 1 - t;
    svgPathAddPoint(
      pts,
      u * u * p0.x + 2 * u * t * p1.x + t * t * p2.x,
      u * u * p0.y + 2 * u * t * p1.y + t * t * p2.y,
    );
  }
}

// Flatten SVG path `d` into a polyline so textPath startOffset can pin
// Char cells. IBM Key Mgmt's guide is cubics around the badge.
function svgPathPolyline(d) {
  const tokens = [];
  const re = /([MmLlHhVvCcSsQqTtAaZz])|([+-]?(?:\d*\.\d+|\d+)(?:[eE][+-]?\d+)?)/g;
  let match;
  while ((match = re.exec(String(d || '')))) {
    if (match[1]) tokens.push(match[1]);
    else tokens.push(Number(match[2]));
  }
  const pts = [];
  if (!tokens.length) return {segs: [], total: 0};
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
  const steps = 24;
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
      svgPathAddPoint(pts, sx, sy);
      x = sx;
      y = sy;
      continue;
    }
    if (up === 'M') {
      x = rel ? x + take() : take();
      y = rel ? y + take() : take();
      svgPathAddPoint(pts, x, y);
      sx = x;
      sy = y;
      lastCmd = rel ? 'l' : 'L';
      continue;
    }
    if (up === 'L') {
      x = rel ? x + take() : take();
      y = rel ? y + take() : take();
      svgPathAddPoint(pts, x, y);
    } else if (up === 'H') {
      x = rel ? x + take() : take();
      svgPathAddPoint(pts, x, y);
    } else if (up === 'V') {
      y = rel ? y + take() : take();
      svgPathAddPoint(pts, x, y);
    } else if (up === 'C') {
      const x1 = rel ? x + take() : take();
      const y1 = rel ? y + take() : take();
      const x2 = rel ? x + take() : take();
      const y2 = rel ? y + take() : take();
      const nx = rel ? x + take() : take();
      const ny = rel ? y + take() : take();
      svgCubicSample(pts, {x, y}, {x: x1, y: y1}, {x: x2, y: y2}, {x: nx, y: ny}, steps);
      c2x = x2;
      c2y = y2;
      x = nx;
      y = ny;
    } else if (up === 'S') {
      const x2 = rel ? x + take() : take();
      const y2 = rel ? y + take() : take();
      const nx = rel ? x + take() : take();
      const ny = rel ? y + take() : take();
      const prevUp = String(prevCmd).toUpperCase();
      const x1 = prevUp === 'C' || prevUp === 'S' ? 2 * x - c2x : x;
      const y1 = prevUp === 'C' || prevUp === 'S' ? 2 * y - c2y : y;
      svgCubicSample(pts, {x, y}, {x: x1, y: y1}, {x: x2, y: y2}, {x: nx, y: ny}, steps);
      c2x = x2;
      c2y = y2;
      x = nx;
      y = ny;
    } else if (up === 'Q') {
      const x1 = rel ? x + take() : take();
      const y1 = rel ? y + take() : take();
      const nx = rel ? x + take() : take();
      const ny = rel ? y + take() : take();
      svgQuadSample(pts, {x, y}, {x: x1, y: y1}, {x: nx, y: ny}, steps);
      q1x = x1;
      q1y = y1;
      x = nx;
      y = ny;
    } else if (up === 'T') {
      const prevUp = String(prevCmd).toUpperCase();
      const x1 = prevUp === 'Q' || prevUp === 'T' ? 2 * x - q1x : x;
      const y1 = prevUp === 'Q' || prevUp === 'T' ? 2 * y - q1y : y;
      const nx = rel ? x + take() : take();
      const ny = rel ? y + take() : take();
      svgQuadSample(pts, {x, y}, {x: x1, y: y1}, {x: nx, y: ny}, steps);
      q1x = x1;
      q1y = y1;
      x = nx;
      y = ny;
    } else if (up === 'A') {
      const rx = take();
      const ry = take();
      const rot = take();
      const large = take();
      const sweep = take();
      const nx = rel ? x + take() : take();
      const ny = rel ? y + take() : take();
      svgArcSample(pts, x, y, rx, ry, rot, large, sweep, nx, ny, 16);
      x = nx;
      y = ny;
    } else {
      break;
    }
  }
  const segs = [];
  let total = 0;
  for (let n = 1; n < pts.length; n++) {
    const dx = pts[n].x - pts[n - 1].x;
    const dy = pts[n].y - pts[n - 1].y;
    const len = Math.hypot(dx, dy);
    if (!(len > 0)) continue;
    segs.push({
      x0: pts[n - 1].x, y0: pts[n - 1].y,
      x1: pts[n].x, y1: pts[n].y,
      len, acc: total,
    });
    total += len;
  }
  return {segs, total};
}

function svgPathAt(poly, dist) {
  if (!poly.segs.length || !(poly.total > 0)) return null;
  let d = dist;
  if (d < 0) d = 0;
  if (d > poly.total) d = poly.total;
  for (let i = 0; i < poly.segs.length; i++) {
    const s = poly.segs[i];
    if (d > s.acc + s.len && i < poly.segs.length - 1) continue;
    const u = s.len > 0 ? (d - s.acc) / s.len : 0;
    return {
      x: s.x0 + (s.x1 - s.x0) * u,
      y: s.y0 + (s.y1 - s.y0) * u,
      angle: Math.atan2(s.y1 - s.y0, s.x1 - s.x0) * 180 / Math.PI,
    };
  }
  return null;
}

function svgStartOffset(raw, total) {
  const s = String(raw == null ? '0' : raw).trim();
  if (!s) return 0;
  if (/%$/.test(s)) {
    const n = parseFloat(s);
    return Number.isFinite(n) ? (n / 100) * total : 0;
  }
  return svgLength(s, 0);
}

const svgSkip = new Set([
  'defs', 'title', 'desc', 'metadata', 'namedview', 'rdf', 'work', 'clippath',
  'mask', 'filter', 'lineargradient', 'radialgradient', 'stop', 'style',
  'script', 'marker',
]);

function svgTextContent(node) {
  const parts = [];
  const walk = (n) => {
    if (n && n.name === '#text' && n.text) parts.push(String(n.text));
    for (const child of (n && n.children) || []) walk(child);
  };
  walk(node);
  return parts.join('');
}

function svgFontFamily(raw) {
  const mapped = htmlFontFamily(raw);
  if (mapped) return mapped;
  const first = String(raw || '').split(',')[0].trim().replace(/^["']+|["']+$/g, '');
  if (!first) return null;
  if (/^arial/i.test(first)) return 'Arial';
  if (/^helvetica/i.test(first)) return 'Helvetica';
  // PostScript "MyriadPro-Bold" is not a Visio/libvisio face.
  // collectCharIX style:font-name needs Arial; bold is a Style bit.
  if (/^myriad/i.test(first)) return 'Arial';
  if (/bold|italic|regular|medium|light/i.test(first) && !/\s/.test(first)) {
    return 'Arial';
  }
  return first;
}

function svgFontStyleBits(style, family) {
  let bits = 0;
  const weight = String((style && style['font-weight']) || '').trim().toLowerCase();
  const fs = String((style && style['font-style']) || '').trim().toLowerCase();
  const name = String(family || (style && style['font-family']) || '');
  if (weight === 'bold' || weight === 'bolder' || parseInt(weight, 10) >= 700) {
    bits |= 1;
  }
  if (/bold/i.test(name.replace(/[\s_-]+/g, ''))) bits |= 1;
  if (fs === 'italic' || fs === 'oblique') bits |= 2;
  if (/italic/i.test(name)) bits |= 2;
  return bits;
}

function paintSvgTextRun(canvas, raw, st, x, y, rotation) {
  const str = String(raw || '').replace(/\s+/g, ' ');
  if (!str.trim()) return false;
  const size = svgLength(st['font-size'], NaN);
  if (Number.isFinite(size) && size > 0 && canvas.setFontSize) {
    canvas.setFontSize(size * canvasMinScale(canvas));
  }
  const family = svgFontFamily(st['font-family'] || '');
  if (family && canvas.setFontFamily) canvas.setFontFamily(family);
  if (canvas.setFontStyle) {
    canvas.setFontStyle(svgFontStyleBits(st, st['font-family'] || family));
  }
  const fill = st.fill;
  if (fill && !svgPaintIsNone(fill) && canvas.setFontColor) {
    if (!/^currentcolor$/i.test(fill) && !/^url\(/i.test(fill)) {
      canvas.setFontColor(htmlCssColorToHex(fill) || fill);
    }
  }
  // SVG y is baseline. Pass a box whose bottom sits on y so
  // collectTextBlock svg:height is wide enough that Draw does not wrap
  // "DDos" (pdftotext was splitting DDo/s on a zero-size glyph pin).
  const fs = Number(canvas.state.fontSize) || 11;
  const rot = Number(rotation) || 0;
  if (rot) {
    // canvas.text multiplies w/h by map() scale. Use SVG user units so
    // each textPath glyph stays a letter-sized frame (IBM KEY MGMT).
    const scale = canvasMinScale(canvas);
    const userFs = scale > 0 ? fs / scale : fs;
    const bw = Math.max(userFs * 0.9, str.length * userFs * 0.62);
    const bh = userFs * 1.2;
    const rad = rot * Math.PI / 180;
    const cx = x + Math.sin(rad) * (bh / 2);
    const cy = y - Math.cos(rad) * (bh / 2);
    canvas.text(
      cx - bw / 2, cy - bh / 2, bw, bh, str, 'center', 'middle',
      false, null, null, null, rot,
    );
  } else {
    const bw = Math.max(fs * 1.2, str.length * fs * 0.75);
    const bh = fs * 1.4;
    canvas.text(x, y - bh, bw, bh, str, 'left', 'bottom');
  }
  return true;
}

function svgGlyphAdvance(ch, fs) {
  if (ch === ' ') return fs * 0.33;
  return fs * 0.55;
}

// SVG <textPath> (IBM Key Management `KEY MGMT`). Visio has no native
// text-along-path cell; each glyph becomes a Char sibling with TxtAngle
// that libvisio collectTextBlock maps to librevenge:rotate.
function paintSvgTextPath(canvas, node, inherited, css, root) {
  const href = node.attrs.href || node.attrs['xlink:href'] || '';
  const id = String(href).replace(/^#/, '');
  const target = id ? findSvgById(root, id) : null;
  const d = target && target.attrs ? target.attrs.d : node.attrs.d;
  const poly = svgPathPolyline(d);
  if (!(poly.total > 0)) return false;
  const base = svgPresentation(node, inherited, css);
  const chunks = [];
  const spans = (node.children || []).filter(
    (child) => xmlLocalName(child.name) === 'tspan',
  );
  if (spans.length) {
    for (const span of spans) {
      chunks.push({
        text: svgTextContent(span),
        style: svgPresentation(span, base, css),
      });
    }
  } else {
    chunks.push({text: svgTextContent(node), style: base});
  }
  const chars = [];
  for (const chunk of chunks) {
    const compact = String(chunk.text || '').replace(/\s+/g, ' ');
    const fs = svgLength(
      chunk.style['font-size'], Number(canvas.state.fontSize) || 11,
    );
    for (const ch of Array.from(compact)) {
      chars.push({ch, style: chunk.style, fs, adv: svgGlyphAdvance(ch, fs)});
    }
  }
  if (!chars.some((c) => c.ch.trim())) return false;
  let offset = svgStartOffset(node.attrs.startOffset, poly.total);
  const anchor = String(base['text-anchor'] || node.attrs['text-anchor'] || 'start')
    .trim().toLowerCase();
  const measured = chars.reduce((sum, c) => sum + c.adv, 0);
  if (anchor === 'middle') offset -= measured / 2;
  else if (anchor === 'end') offset -= measured;
  let painted = false;
  for (const glyph of chars) {
    if (glyph.ch === ' ') {
      offset += glyph.adv;
      continue;
    }
    const at = svgPathAt(poly, offset + glyph.adv / 2);
    if (!at) break;
    if (paintSvgTextRun(canvas, glyph.ch, glyph.style, at.x, at.y, at.angle)) {
      painted = true;
    }
    offset += glyph.adv;
  }
  return painted;
}

function svgCollectTextPaths(node, into) {
  if (!node) return into;
  if (xmlLocalName(node.name) === 'textpath') into.push(node);
  for (const child of node.children || []) svgCollectTextPaths(child, into);
  return into;
}

// SVG <text>/<tspan> (Cumulus DDos Server). y is baseline; mxXmlCanvas2D
// valign=bottom puts that point at the box bottom so collectCharIX Size
// / fo:color match the glyph. textPath (IBM Key Mgmt) is flattened onto
// rotated Char cells — Visio/libvisio have no native text-along-path.
function paintSvgText(canvas, node, inherited, css, root) {
  const paths = svgCollectTextPaths(node, []);
  if (paths.length) {
    const style = svgPresentation(node, inherited, css);
    let painted = false;
    for (const tp of paths) {
      if (paintSvgTextPath(canvas, tp, style, css, root)) painted = true;
    }
    return painted;
  }
  const style = svgPresentation(node, inherited, css);
  const x0 = svgLength(node.attrs.x, 0);
  const y0 = svgLength(node.attrs.y, 0);
  const kids = node.children || [];
  const spans = kids.filter((child) => xmlLocalName(child.name) === 'tspan');
  if (!spans.length) return paintSvgTextRun(canvas, svgTextContent(node), style, x0, y0);
  let painted = false;
  for (const child of kids) {
    if (child.name === '#text') {
      if (paintSvgTextRun(canvas, child.text, style, x0, y0)) painted = true;
      continue;
    }
    if (xmlLocalName(child.name) !== 'tspan') continue;
    const st = svgPresentation(child, style, css);
    const x = child.attrs.x != null ? svgLength(child.attrs.x, x0) : x0;
    const y = child.attrs.y != null ? svgLength(child.attrs.y, y0) : y0;
    if (paintSvgTextRun(canvas, svgTextContent(child), st, x, y)) painted = true;
  }
  return painted;
}

function findSvgById(node, id) {
  if (!node || !id) return null;
  if (node.attrs && node.attrs.id === id) return node;
  for (const child of node.children || []) {
    const found = findSvgById(child, id);
    if (found) return found;
  }
  return null;
}

// SVG `<symbol>` is a template (IBM Live Collaboration / File Sync / Networking
// keep it outside <defs>). It must not paint as a child of <svg> — Draw would
// collectGeometry the untransformed circle at the viewBox origin. <use>
// maps symbol viewBox into x/y/width/height like a nested <svg>.
function paintSvgSymbol(canvas, symbol, inherited, root, css, useNode) {
  const vb = parseSvgNumbers(symbol.attrs.viewBox);
  const vx = vb.length >= 4 ? vb[0] : 0;
  const vy = vb.length >= 4 ? vb[1] : 0;
  const vw = vb.length >= 4 ? vb[2] : 0;
  const vh = vb.length >= 4 ? vb[3] : 0;
  const w = Number(useNode.attrs.width) || vw;
  const h = Number(useNode.attrs.height) || vh;
  const x = Number(useNode.attrs.x) || 0;
  const y = Number(useNode.attrs.y) || 0;
  const mapped = vw > 0 && vh > 0 && w > 0 && h > 0;
  if (mapped) {
    canvas.translate(x, y);
    canvas.scale(w / vw, h / vh);
    canvas.translate(-vx, -vy);
  } else {
    if (x || y) canvas.translate(x, y);
  }
  let painted = false;
  for (const child of symbol.children || []) {
    if (paintSvgNode(canvas, child, inherited, root, css)) painted = true;
  }
  return painted;
}

function paintSvgNode(canvas, node, inherited, root, css) {
  const name = xmlLocalName(node.name);
  if (name === '#text' || svgSkip.has(name)) return false;
  const transformed = applySvgTransform(
    canvas, node.attrs && node.attrs.transform,
  );
  try {
    const style = svgPresentation(node, inherited, css);
    const clipApplied = applySvgClipPath(canvas, node, root, css);
    const maskApplied = applySvgMask(canvas, node, root, css);
    const filterApplied = applySvgFilter(canvas, node, root, css);
    try {
      let painted = false;
      if (name === 'text' || name === 'tspan') {
        return paintSvgText(canvas, node, inherited, css, root);
      }
      if (name === 'use') {
        const href = node.attrs.href || node.attrs['xlink:href'] || '';
        const id = String(href).replace(/^#/, '');
        const target = findSvgById(root, id);
        if (!target || target === node) return false;
        canvas.save();
        if (xmlLocalName(target.name) === 'symbol') {
          painted = paintSvgSymbol(canvas, target, style, root, css, node);
        } else {
          const ox = Number(node.attrs.x) || 0;
          const oy = Number(node.attrs.y) || 0;
          if (ox || oy) canvas.translate(ox, oy);
          painted = paintSvgNode(canvas, target, style, root, css);
        }
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
      if (name === 'symbol') return false;
      if (name === 'g' || name === 'svg' || name === 'a') {
        for (const child of node.children || []) {
          if (paintSvgNode(canvas, child, style, root, css)) painted = true;
        }
        return painted;
      }
      const kind = svgDrawKind(style, name === 'path' || name === 'circle' ||
        name === 'ellipse' || name === 'rect' || name === 'polygon' ? '#000' : 'none');
      if (!kind) return false;
      if (paintSvgAlphaRampFill(canvas, name, node, style, kind, root, css)) {
        return true;
      }
      if (paintSvgLocalLinearFill(canvas, name, node, style, kind, root, css)) {
        return true;
      }
      if (paintSvgEllipticalRadialFill(canvas, name, node, style, kind, root, css)) {
        return true;
      }
      if (paintSvgGradientStroke(canvas, name, node, style, kind, root, css)) {
        return true;
      }
      if (paintSvgBlurHaloFill(canvas, name, node, style, kind, root, css)) {
        return true;
      }
      if (canvas.clipRings && canvas.clipRings.length) {
        return paintSvgClippedShape(canvas, name, node, style, kind, root, css);
      }
      if (name === 'path') {
        if (paintSvgNonzeroCompoundFill(
          canvas, node.attrs.d, style, kind, root, css,
        )) {
          return true;
        }
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
        const ry = Number(node.attrs.ry) || 0;
        if (!(w > 0 && h > 0)) return false;
        const radX = rx > 0 ? rx : ry;
        const radY = ry > 0 ? ry : radX;
        if (radX > 0 || radY > 0) canvas.roundrect(x, y, w, h, radX, radY);
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
      applySvgPaint(
        canvas,
        {...style, fill: style.fill == null ? '#000' : style.fill},
        kind, root, css,
      );
      return true;
    } finally {
      if (filterApplied === 'shadow') canvas.setShadow(false);
      else if (filterApplied === 'blur') canvas.blurSigma = 0;
      if (maskApplied) canvas.restore();
      if (clipApplied) canvas.restore();
    }
  } finally {
    if (transformed) canvas.restore();
  }
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
  canvas.viewBox = {x: vx, y: vy, w: vw, h: vh};
  canvas.translate(dx, dy);
  canvas.scale(dw / vw, dh / vh);
  canvas.translate(-vx, -vy);
  const painted = paintSvgNode(
    canvas, root, {}, root, parseSvgStyleSheet(xml),
  );
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
    this.strokewidth = desc.attrs.strokewidth || 'inherit';
    this.bgNode = desc.children.find((child) => child.name === 'background');
    this.fgNode = desc.children.find((child) => child.name === 'foreground');
    // mxStencil labelBounds / Shapes.js getLabelMargins. flowchart.xml
    // Multi-Document has <labelBounds if="boundedLbl">. Capture used to
    // return a style ghost without getLabelBounds, so JS catalog TxtWidth
    // filled the stacked sheets. tokens.txt has no labelBounds; leftover
    // collectTextBlock is TxtWidth / TxtPinY.
    this.labelBounds = [];
    for (const child of desc.children || []) {
      if (child.name !== 'labelBounds') continue;
      this.labelBounds.push({
        condition: child.attrs.if || null,
        x: Number(child.attrs.x) || 0,
        y: Number(child.attrs.y) || 0,
        w: Number(child.attrs.w) || this.w0,
        h: Number(child.attrs.h) || this.h0,
      });
    }
  }

  pickLabelBounds(style) {
    for (const lb of this.labelBounds) {
      if (lb.condition == null || lb.condition === '' ||
          mxUtils.getValue(style, lb.condition, '0') == '1') {
        return lb;
      }
    }
    return null;
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
    // mxStencil.drawShape: inherit → STYLE_STROKEWIDTH, else width * minScale.
    // LibreOffice only calls VisioDocument::parse, so the canvas width must
    // become LineWeight collectLine paints.
    const minScale = Math.min(aspect.width, aspect.height);
    let sw;
    if (String(this.strokewidth).toLowerCase() === 'inherit') {
      const styleSw = Number(shape && shape.style && shape.style.strokeWidth);
      sw = Number.isFinite(styleSw) && styleSw > 0 ? styleSw : 1;
    } else {
      sw = (Number(this.strokewidth) || 1) * minScale;
    }
    if (canvas.setStrokeWidth) canvas.setStrokeWidth(sw);
    // Official mxStencil.drawShape: background keeps the canvas shadow;
    // foreground disableShadow turns it off on the first fill/stroke.
    this.drawChildren(canvas, this.bgNode, aspect, shape, false);
    this.drawChildren(canvas, this.fgNode, aspect, shape, true);
  }

  drawChildren(canvas, node, aspect, shape, disableShadow) {
    if (!node) return;
    for (const child of node.children) {
      this.drawNode(canvas, child, aspect, shape, disableShadow);
    }
  }

  drawNode(canvas, node, aspect, shape, disableShadow) {
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
      for (const child of node.children) {
        this.drawNode(canvas, child, aspect, shape, disableShadow);
      }
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
      // mxStencil.drawNode: Number(arcsize)==0 uses
      // RECTANGLE_ROUNDING_FACTOR * 100 (15), not 10.
      if (arcsize === 0) arcsize = 15;
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
    }     else if (name === 'fillstroke' || name === 'fillstrokecolor') canvas.fillAndStroke();
    else if (name === 'fill') canvas.fill();
    else if (name === 'stroke') canvas.stroke();
    else if (name === 'fillcolor') {
      canvas.setFillColor(
        mxStencilColor(node.attrs.color, shape, node.attrs.default),
        mxStencilForceHex(node.attrs.color),
      );
    } else if (name === 'strokecolor') {
      canvas.setStrokeColor(
        mxStencilColor(node.attrs.color, shape, node.attrs.default),
        mxStencilForceHex(node.attrs.color),
      );
    } else if (name === 'fontcolor') {
      canvas.setFontColor(
        mxStencilColor(node.attrs.color, shape, node.attrs.default),
      );
    } else if (name === 'strokewidth') {
      // mxStencil.drawNode: width * (fixed==1 ? 1 : minScale).
      const s = node.attrs.fixed === '1' ? 1 : minScale;
      canvas.setStrokeWidth(attrNum(node, 'width') * s);
    } else if (name === 'alpha') {
      canvas.setAlpha(attrNum(node, 'alpha'));
    } else if (name === 'fillalpha') {
      // Official drawNode calls setAlpha for fillalpha/strokealpha.
      // Dedicated channels keep FillForegndTrans vs LineColorTrans
      // that libvisio _fillAndShadowProperties maps to draw:opacity.
      canvas.setFillAlpha(attrNum(node, 'alpha'));
    } else if (name === 'strokealpha') {
      canvas.setStrokeAlpha(attrNum(node, 'alpha'));
    } else if (name === 'dashed') canvas.setDashed(node.attrs.dashed === '1');
    else if (name === 'dashpattern') {
      // mxStencil.js ~897: split on spaces, scale by minScale, setDashPattern.
      // "none" is not a numeric array; do not force dashed=true.
      // mxStencil.drawNode reads `pattern`; Cisco still writes `dash=`.
      const value = node.attrs.pattern ?? node.attrs.dash;
      if (value == null) return;
      if (String(value).trim().toLowerCase() === 'none') {
        canvas.setDashPattern('none');
        return;
      }
      const pat = [];
      for (const part of String(value).split(/[\s,]+/)) {
        if (!part) continue;
        const n = Number(part);
        if (Number.isFinite(n) && n > 0) pat.push(n * minScale);
      }
      if (pat.length) canvas.setDashPattern(pat.join(' '));
    } else if (name === 'linecap') {
      if (node.attrs.cap) canvas.setLineCap(node.attrs.cap);
    } else if (name === 'linejoin') {
      if (node.attrs.join) canvas.setLineJoin(node.attrs.join);
    } else if (name === 'miterlimit') {
      canvas.setMiterLimit(attrNum(node, 'limit'));
    }
    else if (name === 'fontsize') canvas.setFontSize(attrNum(node, 'size') * minScale);
    else if (name === 'fontstyle') canvas.setFontStyle(attrNum(node, 'style'));
    else if (name === 'fontfamily') {
      // mxStencil.js: canvas.setFontFamily(node.getAttribute('family')).
      if (node.attrs.family != null) canvas.setFontFamily(node.attrs.family);
    }
    if (disableShadow &&
        (name === 'fillstroke' || name === 'fillstrokecolor' ||
         name === 'fill' || name === 'stroke')) {
      canvas.setShadow(false);
    }
  }
}

// Shapes.js mxShape.getLabelMargins wrapper: first matching labelBounds
// becomes left/top/right/bottom for getDirectedBounds. Capture must emit
// the same box as a shape-root <labelBounds> so decoder TxtWidth matches
// the XML flowchart catalog (collectTextBlock / fo:min-height).
function stencilGetLabelMargins(stencil, style, rect) {
  const lb = stencil && stencil.pickLabelBounds && stencil.pickLabelBounds(style);
  if (!lb || !rect) return null;
  const aspect = stencil.computeAspect(
    style, rect.x, rect.y, rect.width, rect.height,
    style && style.direction,
  );
  const x0 = aspect.x - rect.x + lb.x * aspect.width;
  const y0 = aspect.y - rect.y + lb.y * aspect.height;
  return new mxRectangle(
    x0, y0,
    rect.width - x0 - lb.w * aspect.width,
    rect.height - y0 - lb.h * aspect.height,
  );
}

function stencilLabelBoundsXml(shape, style, width, height) {
  const stencil = shape && shape.stencil;
  const lb = stencil && stencil.pickLabelBounds && stencil.pickLabelBounds(style);
  if (!lb || !(stencil.w0 > 0) || !(stencil.h0 > 0)) return '';
  const sx = width / stencil.w0;
  const sy = height / stencil.h0;
  const ifAttr = lb.condition ? ` if="${xmlEscape(String(lb.condition))}"` : '';
  return `<labelBounds${ifAttr} x="${number(lb.x * sx)}" y="${number(lb.y * sy)}" w="${number(lb.w * sx)}" h="${number(lb.h * sy)}"/>`;
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

function mxRectangle(x, y, width, height) {
  this.x = Number(x) || 0;
  this.y = Number(y) || 0;
  this.width = Number(width) || 0;
  this.height = Number(height) || 0;
}
mxRectangle.fromRectangle = function(rect) {
  return new mxRectangle(
    rect && rect.x, rect && rect.y, rect && rect.width, rect && rect.height,
  );
};
mxRectangle.prototype.clone = function() {
  return mxRectangle.fromRectangle(this);
};
mxRectangle.prototype.add = function(rect) {
  if (rect == null) return;
  const minX = Math.min(this.x, rect.x);
  const minY = Math.min(this.y, rect.y);
  const maxX = Math.max(this.x + this.width, rect.x + rect.width);
  const maxY = Math.max(this.y + this.height, rect.y + rect.height);
  this.x = minX;
  this.y = minY;
  this.width = maxX - minX;
  this.height = maxY - minY;
};

function mxShape() {
  this.style = {};
  this.scale = 1;
  this.strokewidth = 1;
  this.direction = null;
  this.rotation = 0;
  this.flipH = false;
  this.flipV = false;
  this.gradient = null;
  this.gradientDirection = null;
  this.opacity = 100;
  this.fillOpacity = 100;
  this.strokeOpacity = 100;
}
mxShape.prototype.isHtmlAllowed = function() { return false; };
mxShape.prototype.apply = function(state) {
  this.state = state;
  if (!state || !state.style) return;
  this.style = state.style;
  this.fill = mxUtils.getValue(this.style, mxConstants.STYLE_FILLCOLOR, this.fill);
  this.gradient = mxUtils.getValue(this.style, mxConstants.STYLE_GRADIENTCOLOR, this.gradient);
  this.gradientDirection = mxUtils.getValue(
    this.style, mxConstants.STYLE_GRADIENT_DIRECTION, this.gradientDirection,
  );
  this.opacity = mxUtils.getValue(this.style, mxConstants.STYLE_OPACITY, this.opacity);
  this.fillOpacity = mxUtils.getValue(this.style, mxConstants.STYLE_FILL_OPACITY, this.fillOpacity);
  this.strokeOpacity = mxUtils.getValue(this.style, mxConstants.STYLE_STROKE_OPACITY, this.strokeOpacity);
  this.stroke = mxUtils.getValue(this.style, mxConstants.STYLE_STROKECOLOR, this.stroke);
  this.strokewidth = mxUtils.getNumber(this.style, mxConstants.STYLE_STROKEWIDTH, this.strokewidth);
  this.fillStyle = mxUtils.getValue(this.style, mxConstants.STYLE_FILL_STYLE, this.fillStyle);
  this.rotation = mxUtils.getValue(this.style, mxConstants.STYLE_ROTATION, this.rotation);
  this.direction = mxUtils.getValue(this.style, mxConstants.STYLE_DIRECTION, this.direction);
  this.flipH = mxUtils.getValue(this.style, mxConstants.STYLE_FLIPH, 0) == 1;
  this.flipV = mxUtils.getValue(this.style, mxConstants.STYLE_FLIPV, 0) == 1;
  if (this.fill == mxConstants.NONE) this.fill = null;
  if (this.gradient == mxConstants.NONE || isNoneColor(this.gradient)) this.gradient = null;
  if (this.stroke == mxConstants.NONE) this.stroke = null;
};
mxShape.prototype.getRotation = function() {
  return Number(this.rotation) || 0;
};
// mxShape.getTextRotation: STYLE_ROTATION plus verticalTextRotation when
// STYLE_HORIZONTAL != 1. Cell labels apply rotation via
// mxVertexLabelRotation; vertical stays a TextDirection bake.
mxShape.prototype.getTextRotation = function() {
  let rot = this.getRotation();
  if (this.style != null &&
      mxUtils.getValue(this.style, mxConstants.STYLE_HORIZONTAL, 1) != 1) {
    rot += -90;
  }
  return rot;
};
mxShape.prototype.getShapeRotation = function() {
  let rot = this.getRotation();
  if (this.direction === mxConstants.DIRECTION_NORTH) rot += 270;
  else if (this.direction === mxConstants.DIRECTION_WEST) rot += 180;
  else if (this.direction === mxConstants.DIRECTION_SOUTH) rot += 90;
  return rot;
};
mxShape.prototype.isPaintBoundsInverted = function() {
  // mxShape.js ~1630: stencils invert via computeAspect, not this swap.
  return this.stencil == null &&
    (this.direction === mxConstants.DIRECTION_NORTH ||
     this.direction === mxConstants.DIRECTION_SOUTH);
};
// mxShape.js getLabelMargins / getLabelBounds. Shapes.js wraps this
// hook (note2 boundedLbl, folder tab, process2 rails). Must exist
// before loadJs(Shapes.js) so the wrapper can apply() the original.
mxShape.prototype.getLabelMargins = function(rect) {
  return null;
};
mxShape.prototype.getLabelBounds = function(rect) {
  const d = mxUtils.getValue(
    this.style, mxConstants.STYLE_DIRECTION, mxConstants.DIRECTION_EAST,
  );
  let bounds = rect;
  if (d != mxConstants.DIRECTION_SOUTH && d != mxConstants.DIRECTION_NORTH &&
      this.state != null && this.state.text != null &&
      this.state.text.isPaintBoundsInverted()) {
    bounds = bounds.clone();
    const tmp = bounds.width;
    bounds.width = bounds.height;
    bounds.height = tmp;
  }
  const m = this.getLabelMargins(bounds);
  if (m != null) {
    let flipH = mxUtils.getValue(this.style, mxConstants.STYLE_FLIPH, false) == '1';
    let flipV = mxUtils.getValue(this.style, mxConstants.STYLE_FLIPV, false) == '1';
    if (this.state != null && this.state.text != null &&
        this.state.text.isPaintBoundsInverted()) {
      const tmp = m.x;
      m.x = m.height;
      m.height = m.width;
      m.width = m.y;
      m.y = tmp;
      const swap = flipH;
      flipH = flipV;
      flipV = swap;
    }
    return mxUtils.getDirectedBounds(rect, m, this.style, flipH, flipV);
  }
  return rect;
};
mxShape.prototype.configureCanvas = function(c, x, y, w, h) {
  // mxShape.js ~1032: opacity / fillOpacity / strokeOpacity are 0–100.
  const opacity = Number(this.opacity);
  const fillOpacity = Number(this.fillOpacity);
  const strokeOpacity = Number(this.strokeOpacity);
  if (c.setAlpha && Number.isFinite(opacity)) c.setAlpha(opacity / 100);
  if (c.setFillAlpha && Number.isFinite(fillOpacity)) c.setFillAlpha(fillOpacity / 100);
  if (c.setStrokeAlpha && Number.isFinite(strokeOpacity)) c.setStrokeAlpha(strokeOpacity / 100);
  // mxShape.js ~1037: isShadow calls setShadow before dashes / fill.
  if (this.isShadow != null && c.setShadow) c.setShadow(this.isShadow);
  // mxShape.js ~1025–1082: dashPattern, linecap, linejoin, miterlimit.
  const dash = this.style != null ? this.style.dashPattern : null;
  const fixDash = this.style != null &&
    mxUtils.getValue(this.style, mxConstants.STYLE_FIX_DASH, false) == 1;
  if (this.isDashed && c.setDashed) c.setDashed(true, fixDash);
  if (dash != null && c.setDashPattern) {
    if (fixDash) {
      c.setDashPattern(dash);
    } else {
      const sw = Number(this.strokewidth) || 1;
      const pat = [];
      for (const part of String(dash).split(/[\s,]+/)) {
        if (!part) continue;
        const n = Number(part) * sw;
        if (Number.isFinite(n) && n > 0) pat.push(n);
      }
      if (pat.length) c.setDashPattern(pat.join(' '));
    }
  }
  if (this.style != null) {
    if (this.style.linecap != null && c.setLineCap) c.setLineCap(this.style.linecap);
    if (this.style.linejoin != null && c.setLineJoin) c.setLineJoin(this.style.linejoin);
    if (this.style.miterlimit != null && c.setMiterLimit) c.setMiterLimit(this.style.miterlimit);
  }
  // mxShape.js ~1054: fill + gradientColor calls setGradient, else setFillColor.
  if (this.fill != null && this.fill != mxConstants.NONE &&
      this.gradient && this.gradient != mxConstants.NONE &&
      !isNoneColor(this.gradient) && c.setGradient) {
    c.setGradient(
      this.fill, this.gradient, x, y, w, h,
      this.gradientDirection || mxConstants.DIRECTION_SOUTH,
    );
  } else if (c.setFillColor) {
    c.setFillColor(this.fill);
  }
  if (c.setFillStyle) c.setFillStyle(this.fillStyle);
  if (c.setStrokeColor) c.setStrokeColor(this.stroke);
  const sketchOn = this.style != null &&
    (this.style.sketch == 1 || this.style.sketch == '1');
  if (sketchOn && c.setSketch) {
    c.setSketch({
      fill: this.fillStyle || this.style.fillStyle,
      gap: this.style.hachureGap,
      angle: this.style.hachureAngle,
      weight: this.style.fillWeight,
      jiggle: this.style.jiggle,
    });
  }
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
  htmlEntities(s, newline) {
    let out = String(s ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
    if (newline !== false) out = out.replace(/\n/g, '&#xa;');
    return out;
  },
  // Graph.computeAutosizeTextFontSize / mxUtils.getSizeForString. HTML
  // <br> is a line; textWidth wraps like white-space:normal. Capture has
  // no DOM, so leftover Char.Size uses the same 0.6em × 1.2lh metric as
  // html border-bottom / list pad estimates.
  getSizeForString(value, fontSize, fontFamily, textWidth, fontStyle) {
    const size = Number(fontSize) || 11;
    const em = size * 0.6;
    const lineH = size * (Number(mxConstants.LINE_HEIGHT) || 1.2);
    const html = String(value || '');
    const plain = html.replace(/<br\s*\/?>/gi, '\n').replace(/<[^>]*>/g, '');
    const paras = plain.split('\n');
    const measure = (str) => String(str || '').length * em;
    const wrapW = textWidth != null && Number(textWidth) > 0 ? Number(textWidth) : null;
    if (wrapW == null) {
      let maxW = 0;
      for (const para of paras) maxW = Math.max(maxW, measure(para));
      return {width: maxW, height: Math.max(1, paras.length) * lineH};
    }
    let lines = 0;
    let maxW = 0;
    for (const para of paras) {
      if (!para.length) {
        lines += 1;
        continue;
      }
      const words = para.split(/[\s]+/).filter((word) => word.length);
      let cur = 0;
      for (const word of words) {
        const ww = measure(word);
        if (cur === 0) cur = ww;
        else if (cur + em + ww <= wrapW) cur += em + ww;
        else {
          lines += 1;
          maxW = Math.max(maxW, Math.min(wrapW, cur));
          cur = ww;
        }
      }
      lines += 1;
      maxW = Math.max(maxW, Math.min(wrapW, cur));
    }
    return {width: maxW, height: Math.max(1, lines) * lineH};
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
  // mxUtils.js getDirectedBounds: inset `m` (left/top in x/y, right/bottom
  // in width/height) then rotate for direction / flip.
  getDirectedBounds(rect, m, style, flipH, flipV) {
    const d = mxUtils.getValue(
      style, mxConstants.STYLE_DIRECTION, mxConstants.DIRECTION_EAST,
    );
    flipH = (flipH != null)
      ? flipH
      : mxUtils.getValue(style, mxConstants.STYLE_FLIPH, false);
    flipV = (flipV != null)
      ? flipV
      : mxUtils.getValue(style, mxConstants.STYLE_FLIPV, false);
    m.x = Math.round(Math.max(0, Math.min(rect.width, m.x)));
    m.y = Math.round(Math.max(0, Math.min(rect.height, m.y)));
    m.width = Math.round(Math.max(0, Math.min(rect.width, m.width)));
    m.height = Math.round(Math.max(0, Math.min(rect.height, m.height)));
    if ((flipV && (d == mxConstants.DIRECTION_SOUTH ||
         d == mxConstants.DIRECTION_NORTH)) ||
        (flipH && (d == mxConstants.DIRECTION_EAST ||
         d == mxConstants.DIRECTION_WEST))) {
      const tmp = m.x;
      m.x = m.width;
      m.width = tmp;
    }
    if ((flipH && (d == mxConstants.DIRECTION_SOUTH ||
         d == mxConstants.DIRECTION_NORTH)) ||
        (flipV && (d == mxConstants.DIRECTION_EAST ||
         d == mxConstants.DIRECTION_WEST))) {
      const tmp = m.y;
      m.y = m.height;
      m.height = tmp;
    }
    const m2 = mxRectangle.fromRectangle(m);
    if (d == mxConstants.DIRECTION_SOUTH) {
      m2.y = m.x;
      m2.x = m.height;
      m2.width = m.y;
      m2.height = m.width;
    } else if (d == mxConstants.DIRECTION_WEST) {
      m2.y = m.height;
      m2.x = m.width;
      m2.width = m.x;
      m2.height = m.y;
    } else if (d == mxConstants.DIRECTION_NORTH) {
      m2.y = m.width;
      m2.x = m.y;
      m2.width = m.height;
      m2.height = m.x;
    }
    return new mxRectangle(
      rect.x + m2.x, rect.y + m2.y,
      rect.width - m2.width - m2.x, rect.height - m2.height - m2.y,
    );
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
  mxRectangle,
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
  // Init.js: window.GRAPH_IMAGE_PATH || 'img'. mxSAPIconShape.foreground
  // calls c.image(GRAPH_IMAGE_PATH + '/lib/sap/' + SAPIcon + '.svg'); an
  // empty stub made that `/lib/sap/Name.svg` (absolute) so paintSvgImage
  // never opened img/lib/sap/Name.svg.
  GRAPH_IMAGE_PATH: 'img',
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
  window: {GRAPH_IMAGE_PATH: 'img'},
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
// Official mxDoubleEllipse.getLabelBounds insets STYLE_MARGIN (ER
// Multivalue Attribute margin=3). The capture stub only painted the
// inner ellipse, so leftover TxtWidth stayed the outer 100×40 cell
// and Draw's collectTextBlock overlapped the ring
// (tokens.txt VerticalAlign / TxtWidth → draw:textarea-vertical-align
// / svg:width).
loadOfficialCtor('mxDoubleEllipse.js', 'mxDoubleEllipse');
registerShape(
  mxConstants.SHAPE_DOUBLE_ELLIPSE,
  shapeContext.mxDoubleEllipse || shapeContext.mxEllipse,
);
registerShape(
  'doubleEllipse',
  shapeContext.mxDoubleEllipse || shapeContext.mxEllipse,
);
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
function xmlUserObject(name, initialAttrs) {
  const attrs = Object.create(null);
  if (initialAttrs) {
    for (const key of Object.keys(initialAttrs)) attrs[key] = initialAttrs[key];
  }
  return {
    name,
    nodeName: name,
    nodeType: 1,
    getAttribute(key) {
      return Object.prototype.hasOwnProperty.call(attrs, key) ? String(attrs[key]) : null;
    },
    setAttribute(key, value) {
      attrs[key] = value;
    },
    hasAttribute(key) {
      return Object.prototype.hasOwnProperty.call(attrs, key);
    },
    removeAttribute(key) {
      delete attrs[key];
    },
    // Graph.setAttributeForCell clones the UserObject before mutating.
    cloneNode() {
      return xmlUserObject(name, {...attrs});
    },
  };
}

// Graph.setAttributeForCell: wrap a string label in <UserObject label=…>
// then set placeholders / name / link. Sidebar Variable / Timestamp / Link
// call this; a stub left %name% and %date{…}% as Character text.
function graphSetAttributeForCell(cell, attributeName, attributeValue) {
  let value;
  if (cell.value != null && typeof cell.value === 'object' &&
      typeof cell.value.setAttribute === 'function') {
    value = typeof cell.value.cloneNode === 'function'
      ? cell.value.cloneNode(true)
      : cell.value;
  } else {
    value = xmlUserObject('UserObject');
    value.setAttribute('label', cell.value == null ? '' : String(cell.value));
  }
  if (attributeValue != null) value.setAttribute(attributeName, attributeValue);
  else if (typeof value.removeAttribute === 'function') {
    value.removeAttribute(attributeName);
  }
  cell.value = value;
}

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
Cell.prototype.getValue = function() { return this.value; };
// mxCell.setAttribute / getAttribute write the XML user object.
// C4 templates store label + %c4Name% placeholders there.
Cell.prototype.setAttribute = function(name, value) {
  const user = this.value;
  if (user != null && typeof user === 'object' && typeof user.setAttribute === 'function') {
    user.setAttribute(name, value);
  }
};
Cell.prototype.getAttribute = function(name, defaultValue) {
  const user = this.value;
  if (user != null && typeof user === 'object' && typeof user.getAttribute === 'function') {
    const val = user.getAttribute(name);
    return val != null ? val : defaultValue;
  }
  return defaultValue;
};
Cell.prototype.hasAttribute = function(name) {
  const user = this.value;
  return !!(user != null && typeof user === 'object' &&
    typeof user.hasAttribute === 'function' && user.hasAttribute(name));
};
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
  this.graph = {
    setAttributeForCell: graphSetAttributeForCell,
    // Graph.setLinkForCell → UserObject @link. libvisio has the Hyperlink
    // token but no collectHyperlink, so leftover freezes the visible
    // fontColor=#0000EE / fontStyle=4 label; the URL stays on the cell
    // for Graph.replacePlaceholders / convertValueToString.
    setLinkForCell(cell, link) {
      graphSetAttributeForCell(cell, 'link', link);
    },
  };
  this.editorUi = {
    editor: {
      graph: {
        appendFontSize(style) { return String(style || ''); },
        vertexFontSize: 12,
        edgeFontSize: 11,
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
    createXmlDocument: () => ({createElement: (name) => xmlUserObject(name)}),
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
     'Nurse_Woman', 'Nurse_Woman_Black', 'Nurse_Man_Green', 'Nurse_Man_Red',
     'Nurse_Woman_Green', 'Nurse_Woman_Red', 'Soldier', 'Soldier_Black',
     'Military_Officer',
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

// Official Graph.getTableLines / visitTableCells. TableShape.paintForeground
// strokes those polylines as the interior grid. Capture stubs returned []
// so General Table 1 (shape=table;childLayout=tableLayout;startSize=0)
// leftover-baked only the outer PartialRectangle. tokens.txt has no table
// grid token; collectLine is svg:stroke.
function captureVertexChildren(cell) {
  return (cell && cell.children || []).filter((child) =>
    child && child.vertex && child.geometry && !child.edge);
}

function captureGetTableLines(cell, horizontal, vertical) {
  const hl = [];
  const vl = [];
  if (!cell || !(horizontal || vertical)) return [];
  const rows = captureVertexChildren(cell);
  if (!rows.length) return [];
  let lastRow = null;
  for (let i = 0; i < rows.length; i++) {
    const cols = captureVertexChildren(rows[i]);
    let lastCol = null;
    const row = [];
    for (let j = 0; j < cols.length; j++) {
      const geo = cols[j].geometry;
      if (!geo) {
        row.push(null);
        continue;
      }
      const point = {
        x: (Number(geo.width) || 0) + (lastCol != null ? lastCol.point.x : 0),
        y: (Number(geo.height) || 0) +
          (lastRow != null && lastRow[0] != null ? lastRow[0].point.y : 0),
      };
      const iter = {point, row: i, col: j};
      if (horizontal && i < rows.length - 1) {
        if (hl[i] == null) hl[i] = [{x: 0, y: point.y}];
        hl[i].push(point);
      }
      if (vertical && j < cols.length - 1) {
        if (vl[j] == null) vl[j] = [{x: point.x, y: 0}];
        vl[j].push(point);
      }
      row.push(iter);
      lastCol = iter;
    }
    lastRow = row;
  }
  return hl.concat(vl);
}

function paintRegistered(style, width, height, canvas, x = 0, y = 0, opts = {}) {
  const name = style && style.shape;
  const fill = stylePaintColor(style.fillColor, '#ffffff');
  const stroke = stylePaintColor(style.strokeColor, '#000000');
  if (typeof canvas.bindStyle === 'function') canvas.bindStyle(fill, stroke);
  let ctor = name ? registry[name] : null;
  if (!ctor && opts.allowStencil && name) {
    const stencil = stencilMap[String(name).toLowerCase()];
    if (stencil) {
      const ghost = {style, fill, stroke, direction: style.direction || null, stencil};
      ghost.getLabelMargins = function(rect) {
        return stencilGetLabelMargins(this.stencil, this.style, rect);
      };
      ghost.getLabelBounds = mxShape.prototype.getLabelBounds;
      // mxShape.configureCanvas always setFillColor / setDashed from the
      // cell. NestedStencil used to skip those when the style omitted
      // dashed=1 / none fill, so the previous vertex-cells sibling leaked
      // collectLine dashes and FillForegnd onto this stencil.
      // Set fill/stroke first while fillAlpha is still 1 so inherit `fill`
      // stays one FillForegnd. setFillColor after fillOpacity<100 forceHexes
      // a sibling, and the next cell's fill() (Circular Dial 65% arc) then
      // occupied the parent — Draw painted the fillOpacity=20 donut on top.
      // tokens.txt FillForegndTrans is draw:opacity.
      canvas.setFillColor(isNoneColor(fill) ? null : fill);
      canvas.setStrokeColor(isNoneColor(stroke) ? null : stroke);
      const opacity = Number(style.opacity);
      const fillOpacity = Number(style.fillOpacity);
      const strokeOpacity = Number(style.strokeOpacity);
      if (Number.isFinite(opacity)) canvas.setAlpha(opacity / 100);
      if (Number.isFinite(fillOpacity)) canvas.setFillAlpha(fillOpacity / 100);
      if (Number.isFinite(strokeOpacity)) canvas.setStrokeAlpha(strokeOpacity / 100);
      canvas.setDashed(style.dashed === '1');
      if (style.dashPattern) canvas.setDashPattern(style.dashPattern);
      if (style.linecap) canvas.setLineCap(style.linecap);
      if (style.linejoin) canvas.setLineJoin(style.linejoin);
      if (style.miterlimit) canvas.setMiterLimit(style.miterlimit);
      if (style.shadow == 1) canvas.setShadow(true);
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
  shape.gradient = stylePaintColor(style.gradientColor, null);
  shape.gradientDirection = style.gradientDirection || mxConstants.DIRECTION_SOUTH;
  const opacity = Number(style.opacity);
  const fillOpacity = Number(style.fillOpacity);
  const strokeOpacity = Number(style.strokeOpacity);
  shape.opacity = Number.isFinite(opacity) ? opacity : 100;
  shape.fillOpacity = Number.isFinite(fillOpacity) ? fillOpacity : 100;
  shape.strokeOpacity = Number.isFinite(strokeOpacity) ? strokeOpacity : 100;
  shape.stroke = stroke;
  shape.strokewidth = Number(style.strokeWidth) || 1;
  shape.fillStyle = style.fillStyle || null;
  shape.isDashed = style.dashed == 1;
  shape.isShadow = style.shadow == 1;
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
    cell: opts.cell || null,
    style,
    view: {
      graph: {
        getLabel() { return ''; },
        isCellCollapsed() { return false; },
        isCellConnected() { return false; },
        isSwimlane() { return false; },
        getTableLines(tableCell, horizontal, vertical) {
          return captureGetTableLines(tableCell, horizontal, vertical);
        },
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
    // mxShape.paint: isPaintBoundsInverted swaps w/h, then updateTransform
    // rotates about that centre. LibreOffice collectGeometry has no
    // direction; rotating a 12.5×350 south rect without the swap bakes a
    // 350-wide path that decoder scaleX explodes past the cell XForm.
    let paintX = x;
    let paintY = y;
    let paintW = width;
    let paintH = height;
    if (typeof shape.isPaintBoundsInverted === 'function' &&
        shape.isPaintBoundsInverted()) {
      const t = (paintW - paintH) / 2;
      paintX += t;
      paintY -= t;
      const tmp = paintW;
      paintW = paintH;
      paintH = tmp;
    }
    if (typeof shape.updateTransform === 'function') {
      shape.updateTransform(canvas, paintX, paintY, paintW, paintH);
    }
    if (typeof shape.configureCanvas === 'function') {
      shape.configureCanvas(canvas, paintX, paintY, paintW, paintH);
    }
    // mxShape.paint: stencils set width in drawShape; JS constructors
    // call setStrokeWidth(this.strokewidth) before paintVertexShape.
    if (canvas.setStrokeWidth) canvas.setStrokeWidth(shape.strokewidth);
    shape.paintVertexShape(canvas, paintX, paintY, paintW, paintH);
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

function cellDisplaySource(value) {
  if (value == null) return '';
  if (typeof value === 'string' || typeof value === 'number') return String(value);
  // Graph.convertValueToString: XML user objects expose the label attribute,
  // not Object.prototype.toString ([object Object]).
  if (typeof value === 'object' && typeof value.getAttribute === 'function') {
    return value.getAttribute('label') || '';
  }
  return '';
}

function cellHasPlaceholders(cell) {
  const user = cell && cell.value;
  return !!(user && typeof user === 'object' &&
    typeof user.getAttribute === 'function' &&
    user.getAttribute('placeholders') == '1');
}

// Graph.formatDate (stevenlevithan mask). Timestamp is
// %date{ddd mmm dd yyyy HH:MM:ss}% via getGlobalVariable.
function formatDateMask(date, mask) {
  const dayNames = [
    'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat',
    'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
  ];
  const monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
    'September', 'October', 'November', 'December',
  ];
  const pad = (val, len) => {
    let out = String(val);
    const n = len || 2;
    while (out.length < n) out = `0${out}`;
    return out;
  };
  const d = date.getDate();
  const D = date.getDay();
  const m = date.getMonth();
  const y = date.getFullYear();
  const H = date.getHours();
  const M = date.getMinutes();
  const s = date.getSeconds();
  const flags = {
    d,
    dd: pad(d),
    ddd: dayNames[D],
    dddd: dayNames[D + 7],
    m: m + 1,
    mm: pad(m + 1),
    mmm: monthNames[m],
    mmmm: monthNames[m + 12],
    yy: String(y).slice(2),
    yyyy: y,
    h: H % 12 || 12,
    hh: pad(H % 12 || 12),
    H,
    HH: pad(H),
    M,
    MM: pad(M),
    s,
    ss: pad(s),
  };
  return String(mask).replace(
    /d{1,4}|m{1,4}|yy(?:yy)?|([HhMsTt])\1?|"[^"]*"|'[^']*'/g,
    (token) => (token in flags ? flags[token] : token.slice(1, token.length - 1)),
  );
}

function cellGlobalVariable(name) {
  const now = new Date();
  if (name === 'date') return now.toLocaleDateString();
  if (name === 'time') return now.toLocaleTimeString();
  if (name === 'timestamp') return now.toLocaleString();
  if (name.substring(0, 5) === 'date{') {
    return formatDateMask(now, name.substring(5, name.length - 1));
  }
  return null;
}

function cellAttributeWalk(cell, name) {
  let current = cell;
  while (current) {
    if (current.value != null && typeof current.value === 'object' &&
        typeof current.hasAttribute === 'function' && current.hasAttribute(name)) {
      const val = current.getAttribute(name);
      return val != null ? val : '';
    }
    current = current.parent;
  }
  return null;
}

// Graph.replacePlaceholders: %c4Name% → cell.getAttribute('c4Name');
// %date{mask}% → Graph.formatDate. LibreOffice collectText only sees
// the frozen Char runs (tokens.txt has no placeholder token).
function replaceCellPlaceholders(cell, str) {
  if (!cellHasPlaceholders(cell) || cell.getAttribute('placeholder') != null) {
    return str;
  }
  return String(str || '').replace(
    /%(date\{.*\}|[^%\{\}"'=;]+)%/g,
    (token, name) => {
      if (name === 'label' || name === 'tooltip') return token;
      let val = cellAttributeWalk(cell, name);
      if (val == null) val = cellGlobalVariable(name);
      return val != null ? val : token;
    },
  );
}

function cellLabel(value, keepHtml = false, cell = null) {
  let source = cellDisplaySource(value);
  if (cell) source = replaceCellPlaceholders(cell, source);
  if (!source) return '';
  // mxText html=1 feeds the foreignObject innerHTML. SysML Package Diagram
  // is `&lt;&lt;import&gt;&gt;` with no raw tags; decoding here turned
  // that into `<<import>>` which parseHtmlLabel ate as an <import> element
  // (tokens.txt has no entity token; leftover Character must be <<import>>).
  if (keepHtml) return source;
  const stripped = source
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/(p|div|tr|h[1-6]|li)>/gi, '\n')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/[^\S\n]+/g, ' ')
    .replace(/ *\n[ \n]*/g, '\n')
    .trim();
  return stripped;
}

// HTML named character references the foreignObject UA decodes.
// UML Interface is `&laquo;interface&raquo;` — leftover Character has
// no entity token, so collectText must see U+00AB / U+00BB.
const kHtmlNamedEntities = {
  nbsp: ' ', iexcl: '¡', cent: '¢', pound: '£', curren: '¤', yen: '¥',
  brvbar: '¦', sect: '§', uml: '¨', copy: '©', ordf: 'ª', laquo: '«',
  not: '¬', shy: '\u00AD', reg: '®', macr: '¯', deg: '°', plusmn: '±',
  sup2: '²', sup3: '³', acute: '´', micro: 'µ', para: '¶', middot: '·',
  cedil: '¸', sup1: '¹', ordm: 'º', raquo: '»', frac14: '¼', frac12: '½',
  frac34: '¾', iquest: '¿', times: '×', divide: '÷',
  ndash: '–', mdash: '—', hellip: '…', bull: '•', trade: '™',
  lsquo: '‘', rsquo: '’', ldquo: '“', rdquo: '”', apos: "'",
};

function decodeHtmlEntities(value) {
  let s = String(value ?? '');
  s = s.replace(/&#10;/g, '\n');
  s = s.replace(/&#x([0-9a-f]+);/gi, (_, hex) =>
    String.fromCharCode(parseInt(hex, 16)));
  s = s.replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n)));
  s = s.replace(/&([a-zA-Z][a-zA-Z0-9]+);/g, (token, name) => {
    const key = String(name).toLowerCase();
    if (key === 'amp' || key === 'lt' || key === 'gt' || key === 'quot') {
      return token;
    }
    return Object.prototype.hasOwnProperty.call(kHtmlNamedEntities, key)
      ? kHtmlNamedEntities[key]
      : token;
  });
  return s
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"');
}

function htmlAttr(attrs, name) {
  const re = new RegExp(
    `(?:^|\\s)${name}\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s>]+))`,
    'i',
  );
  const match = re.exec(attrs || '');
  return match ? (match[1] || match[2] || match[3]) : null;
}

function htmlStyleProp(attrs, prop) {
  // Decode first: `&quot;open sans&quot;` would otherwise split on the
  // entity's trailing semicolon and freeze Char.Font as `&quot`.
  const style = decodeHtmlEntities(htmlAttr(attrs, 'style') || '');
  const re = new RegExp(`(?:^|;)\\s*${prop}\\s*:\\s*([^;]+)`, 'i');
  const match = re.exec(style);
  return match ? match[1].trim() : null;
}

function htmlFontFamily(raw) {
  // Walk the CSS stack like the browser. Webfonts such as "open sans" are
  // not Visio/libvisio faces; skip them so `"open sans", arial, sans-serif`
  // freezes Char.Font Arial that collectCharIX maps to style:font-name.
  const named = {
    arial: 'Arial',
    helvetica: 'Helvetica',
    'times new roman': 'Times New Roman',
    times: 'Times New Roman',
    'courier new': 'Courier New',
    courier: 'Courier New',
    calibri: 'Calibri',
    verdana: 'Verdana',
    georgia: 'Georgia',
    tahoma: 'Tahoma',
    'comic sans ms': 'Comic Sans MS',
  };
  const generics = {
    'sans-serif': 'Arial',
    serif: 'Times New Roman',
    monospace: 'Courier New',
  };
  let fallback = null;
  for (const part of decodeHtmlEntities(raw).split(',')) {
    const name = part.trim().replace(/^["']+|["']+$/g, '');
    if (!name) continue;
    const key = name.toLowerCase();
    if (named[key]) return named[key];
    if (generics[key]) {
      fallback = fallback || generics[key];
      continue;
    }
  }
  return fallback;
}

function htmlHasNowrap(html) {
  const source = String(html || '');
  return /text-wrap\s*:\s*nowrap/i.test(source)
    || /white-space\s*:\s*nowrap/i.test(source);
}

function htmlAlignToken(raw) {
  const v = String(raw || '').trim().toLowerCase();
  if (v === 'center' || v === 'middle') return 'center';
  if (v === 'right' || v === 'end') return 'right';
  if (v === 'justify') return 'justify';
  if (v === 'left' || v === 'start') return 'left';
  return null;
}

// HTML UA list padding (css 2.1 appendix D / html.spec rendering).
// mxText html=1 paints <ul>/<ol> via foreignObject; leftover Bullet 1
// is U+2022 that collectParaIX maps to text:bullet-char, then
// libvisio_write bakes the glyph because Draw never paints that char.
const kHtmlListPadPx = 40;

// mxText HTML/CSS on <p>/<span>/<font>: color, size, weight, italic,
// text-decoration, font-family, block text-align. collectCharIX maps
// Style 0x4 to underline; collectParaIX HorzAlign is fo:text-align.
function applyHtmlCss(next, attrs, tag) {
  // Heading UA size/weight first so CSS font-size / font-weight:normal
  // (Salesforce Header) can clear them. Margins use the computed size.
  htmlUaHeadingDefaults(next, tag);
  const color = htmlAttr(attrs, 'color') || htmlStyleProp(attrs, 'color');
  if (color) next.fontColor = color;
  // CSS background-color on <font>/<b> (Atlassian Nested discussion
  // AUTHOR chip rgb(244,245,247)). Char.Highlight is skipped by
  // readCharIX; leftover still leftover-bakes it so
  // bakeMixedHighlightForLibvisioWrite can emit FillForegnd plates
  // Draw paints. `initial` / none / transparent clear the inherit.
  const bgRaw = htmlStyleProp(attrs, 'background-color')
    || htmlStyleProp(attrs, 'background');
  if (bgRaw) {
    const token = String(bgRaw).trim();
    if (/^(none|transparent|initial|unset)$/i.test(token)) {
      next.highlight = null;
    } else {
      const hex = htmlCssColorToHex(token);
      if (hex) next.highlight = hex;
    }
  }
  // CSS font-size is px (GCP 11px) or em (Lean Mapping 2em). HTML
  // size="1"–"7" is not px — Chromium maps it onto xx-small…xxx-large
  // (10/13/16/18/24/32/48) which collectCharIX Size maps to fo:font-size.
  // parseFloat("2em") used to freeze 2px and clamp to Visio's 0.04in floor.
  const cssSize = htmlStyleProp(attrs, 'font-size');
  if (cssSize) {
    const size = htmlCssFontSizePx(cssSize, next.fontSize);
    if (size != null && size > 0) next.fontSize = size;
  } else {
    const htmlSize = htmlAttr(attrs, 'size');
    if (htmlSize) {
      const mapped = htmlFontSizeAttrPx(htmlSize, next.fontSize);
      if (mapped != null) next.fontSize = mapped;
    }
  }
  const weight = htmlStyleProp(attrs, 'font-weight');
  if (weight) {
    if (/^(bold|bolder|[7-9]00)$/i.test(weight)) next.fontStyle |= 1;
    else if (/^(normal|lighter|[1-4]00)$/i.test(weight)) next.fontStyle &= ~1;
  }
  const italic = htmlStyleProp(attrs, 'font-style');
  if (italic) {
    if (/italic|oblique/i.test(italic)) next.fontStyle |= 2;
    else if (/^normal$/i.test(italic)) next.fontStyle &= ~2;
  }
  const deco = htmlStyleProp(attrs, 'text-decoration');
  if (deco) {
    if (/underline/i.test(deco)) next.fontStyle |= 4;
    if (/line-through/i.test(deco)) next.fontStyle |= 8;
  }
  const family = htmlStyleProp(attrs, 'font-family') || htmlAttr(attrs, 'face');
  if (family) {
    const mapped = htmlFontFamily(family);
    if (mapped) next.fontFamily = mapped;
  }
  const bb = htmlStyleProp(attrs, 'border-bottom')
    || htmlStyleProp(attrs, 'border-bottom-style');
  if (bb) {
    const kind = htmlBorderBottomKind(bb);
    if (kind === 'solid') next.fontStyle |= 4;
    else if (kind === 'dotted' || kind === 'dashed') next.borderBottom = kind;
  }
  // CSS text-align on inline span is ignored (Bootstrap Alert). Block
  // <p>/<div> (SysML compartments) map onto collectParaIX HorzAlign.
  if (tag === 'p' || tag === 'div' || tag === 'td' || tag === 'th' ||
      tag === 'li' || /^h[1-6]$/.test(tag || '')) {
    const ta = htmlAlignToken(
      htmlStyleProp(attrs, 'text-align') || htmlAttr(attrs, 'align'),
    );
    if (ta) next.align = ta;
  }
  // CSS margin on block <p> (SysML margin-top:4px / margin-left:8px /
  // Abstract Definition margin:13px). collectParaIX IndLeft / SpBefore
  // map to fo:margin-left / fo:margin-top. Inline tags inherit left/right
  // and only the first run in the block keeps margin-top.
  if (tag === 'p' || tag === 'div' || tag === 'li' || /^h[1-6]$/.test(tag || '')) {
    htmlUaBlockMargins(next, tag);
    htmlApplyMargins(next, attrs);
    next.paraStart = true;
  }
  // CSS line-height on <p> (SAP Authenticate 114%). collectParaIX
  // SpLine < 0 is a multiplier libvisio maps to fo:line-height PERCENT.
  const lh = htmlStyleProp(attrs, 'line-height');
  if (lh) {
    const parsed = htmlCssLineHeight(lh, next.fontSize);
    if (parsed != null) next.lineHeight = parsed;
  }
}

function htmlCssPx(raw) {
  const token = String(raw || '').trim();
  if (!token || token === 'auto' || token === 'inherit' || token === 'none') {
    return null;
  }
  const n = parseFloat(token);
  return Number.isFinite(n) ? n : null;
}

// CSS line-height: 114% / 1.14 / 1.14em → Visio SpLine multiplier
// (libvisio fo:line-height PERCENT). px becomes a multiplier of the
// element's computed font-size so leftover stays on the percent path.
function htmlCssLineHeight(raw, fontPx) {
  const token = String(raw || '').trim().toLowerCase();
  if (!token || token === 'normal' || token === 'inherit' ||
      token === 'initial' || token === 'unset') {
    return null;
  }
  if (/%$/.test(token)) {
    const n = parseFloat(token);
    return Number.isFinite(n) && n > 0 ? n / 100 : null;
  }
  if (/em$/i.test(token) && !/rem$/i.test(token)) {
    const n = parseFloat(token);
    return Number.isFinite(n) && n > 0 ? n : null;
  }
  if (/px$/i.test(token)) {
    const n = parseFloat(token);
    const base = Number(fontPx);
    return Number.isFinite(n) && n > 0 && Number.isFinite(base) && base > 0
      ? n / base
      : null;
  }
  if (/[a-z%]/i.test(token)) return null;
  const n = parseFloat(token);
  return Number.isFinite(n) && n > 0 ? n : null;
}

// CSS padding percentages are of the containing-block WIDTH on every
// side (CSS 2.1 8.4). parseFloat("11%") would freeze 11px.
function htmlCssLength(raw, percentOf) {
  const token = String(raw || '').trim();
  if (!token || token === 'auto' || token === 'inherit' || token === 'none') {
    return null;
  }
  if (/%$/.test(token)) {
    const n = parseFloat(token);
    return Number.isFinite(n) && percentOf != null ? percentOf * n / 100 : null;
  }
  return htmlCssPx(token);
}

// CSS font-size em/% is of the parent size (createState 11; cell labels
// get defaultVertex 12 from applyTextStyle first). rem is
// the HTML medium (16px). parseFloat("2em") must not freeze 2px.
// Chromium strict FontSize table at default medium 16px (WebKit
// StyleFontSizeFunctions). CSS `x-small` is 10px, not HTML size=2's 13px
// and not parseFloat NaN that left SAP Text Elements on defaultVertex 12.
const kCssAbsoluteFontSizePx = {
  'xx-small': 9,
  'x-small': 10,
  small: 13,
  medium: 16,
  large: 18,
  'x-large': 24,
  'xx-large': 32,
  'xxx-large': 48,
};

function htmlCssFontSizePx(raw, currentPx) {
  const token = String(raw || '').trim();
  if (!token || token === 'auto' || token === 'inherit' || token === 'none') {
    return null;
  }
  const keyword = kCssAbsoluteFontSizePx[token.toLowerCase()];
  if (keyword != null) return keyword;
  if (/^smaller$/i.test(token)) {
    const base = Number(currentPx);
    return Number.isFinite(base) && base > 0 ? base / 1.2 : null;
  }
  if (/^larger$/i.test(token)) {
    const base = Number(currentPx);
    return Number.isFinite(base) && base > 0 ? base * 1.2 : null;
  }
  if (/rem$/i.test(token)) {
    const n = parseFloat(token);
    return Number.isFinite(n) ? n * 16 : null;
  }
  if (/em$/i.test(token)) {
    const n = parseFloat(token);
    const base = Number(currentPx);
    return Number.isFinite(n) && Number.isFinite(base) && base > 0
      ? n * base
      : null;
  }
  if (/%$/.test(token)) {
    const n = parseFloat(token);
    const base = Number(currentPx);
    return Number.isFinite(n) && Number.isFinite(base) && base > 0
      ? n * base / 100
      : null;
  }
  return htmlCssPx(token);
}

// HTML <font size=N> presentational hint (html.spec.whatwg.org
// phrasing-content-3). Chromium HTMLFontElement maps 1–7 onto
// xx-small…xxx-large at a 16px medium.
const kHtmlFontSizePx = [0, 10, 13, 16, 18, 24, 32, 48];

function htmlFontSizeTablePx(index) {
  const i = Math.max(1, Math.min(7, Math.round(Number(index) || 0)));
  return kHtmlFontSizePx[i];
}

function htmlFontSizeIndexFromPx(px) {
  const n = Number(px);
  let best = 3;
  let dist = Infinity;
  for (let i = 1; i <= 7; i++) {
    const d = Math.abs(kHtmlFontSizePx[i] - n);
    if (d < dist) {
      dist = d;
      best = i;
    }
  }
  return best;
}

function htmlFontSizeAttrPx(raw, currentPx) {
  const token = String(raw || '').trim();
  if (!token) return null;
  const rel = /^([+-])(\d+)$/.exec(token);
  if (rel) {
    const delta = parseInt(rel[2], 10) * (rel[1] === '-' ? -1 : 1);
    return htmlFontSizeTablePx(htmlFontSizeIndexFromPx(currentPx) + delta);
  }
  const n = parseFloat(token);
  if (!Number.isFinite(n) || n < 1 || n > 7 || n !== Math.round(n)) return null;
  return htmlFontSizeTablePx(n);
}

// HTML UA heading / <p> (html.spec.whatwg.org rendering). mxText html=1
// foreignObject keeps them; SysML authors `margin:0px` to cancel. Bare
// Salesforce <h3> is 1.17em bold with 1em margin; inner
// `font-weight:normal; font-size:14px` clears the UA slot so collectCharIX
// Style.bold / Size stay native. Heading margin is 1em of the computed
// heading size (parent × sizeEm).
const kHtmlHeadingUa = {
  h1: {sizeEm: 2, marginEm: 0.67},
  h2: {sizeEm: 1.5, marginEm: 0.83},
  h3: {sizeEm: 1.17, marginEm: 1},
  h4: {sizeEm: 1, marginEm: 1.33},
  h5: {sizeEm: 0.83, marginEm: 1.67},
  h6: {sizeEm: 0.67, marginEm: 2.33},
};

function htmlUaHeadingDefaults(next, tag) {
  const heading = kHtmlHeadingUa[tag];
  if (!heading) return;
  const parentPx = Number(next.fontSize);
  const base = Number.isFinite(parentPx) && parentPx > 0 ? parentPx : 11;
  next.fontSize = base * heading.sizeEm;
  next.fontStyle |= 1;
}

function htmlUaBlockMargins(next, tag) {
  const sizePx = Number(next.fontSize);
  const base = Number.isFinite(sizePx) && sizePx > 0 ? sizePx : 11;
  const heading = kHtmlHeadingUa[tag];
  if (heading) {
    const m = base * heading.marginEm;
    next.marginTop = m;
    next.marginBottom = m;
    return;
  }
  if (tag === 'p') {
    next.marginTop = base;
    next.marginBottom = base;
  }
}

function htmlApplyMargins(next, attrs) {
  const box = String(htmlStyleProp(attrs, 'margin') || '').trim();
  if (box) {
    const parts = box.split(/\s+/).map(htmlCssPx);
    if (parts.length && parts.every((v) => v != null)) {
      if (parts.length === 1) {
        next.marginTop = next.marginRight = next.marginBottom = next.marginLeft = parts[0];
      } else if (parts.length === 2) {
        next.marginTop = next.marginBottom = parts[0];
        next.marginRight = next.marginLeft = parts[1];
      } else if (parts.length === 3) {
        next.marginTop = parts[0];
        next.marginRight = next.marginLeft = parts[1];
        next.marginBottom = parts[2];
      } else {
        next.marginTop = parts[0];
        next.marginRight = parts[1];
        next.marginBottom = parts[2];
        next.marginLeft = parts[3];
      }
    }
  }
  const mt = htmlCssPx(htmlStyleProp(attrs, 'margin-top'));
  if (mt != null) next.marginTop = mt;
  const mr = htmlCssPx(htmlStyleProp(attrs, 'margin-right'));
  if (mr != null) next.marginRight = mr;
  const mb = htmlCssPx(htmlStyleProp(attrs, 'margin-bottom'));
  if (mb != null) next.marginBottom = mb;
  const ml = htmlCssPx(htmlStyleProp(attrs, 'margin-left'));
  if (ml != null) next.marginLeft = ml;
}

function htmlBorderBottomKind(raw) {
  const token = String(raw || '');
  if (/none|0px/i.test(token)) return null;
  if (/dotted/i.test(token)) return 'dotted';
  if (/dashed/i.test(token)) return 'dashed';
  if (/solid/i.test(token)) return 'solid';
  return null;
}

// mxText HTML `border-bottom: 1px dotted` (ER Weak Key Attribute).
// Char Style 0x4 is always a solid underline in collectCharIX; paint a
// dashed Line sibling (LinePattern / veDashPattern) under the glyph box.
function paintHtmlBorderBottom(canvas, x, y, w, h, align, valign, runs) {
  const marked = (runs || []).filter((run) =>
    run.borderBottom === 'dotted' || run.borderBottom === 'dashed');
  if (!marked.length) return;
  const boxW = Number(w);
  const boxH = Number(h);
  if (!(boxW > 0 && boxH > 0)) return;
  const fallback = Number(canvas.state.fontSize) || 11;
  let textW = 0;
  let textH = 0;
  for (const run of marked) {
    const fs = Number(run.fontSize);
    const size = Number.isFinite(fs) && fs > 0 ? fs : fallback;
    const str = String(run.str || '');
    textW += str.length * size * 0.6;
    textH = Math.max(textH, size * 1.2);
  }
  if (textW < 1) return;
  const horiz = String(align || '').toLowerCase();
  const vert = String(valign || '').toLowerCase();
  let cx;
  if (horiz.includes('center')) cx = x + boxW / 2;
  else if (horiz.includes('right')) cx = x + boxW - textW / 2;
  else cx = x + textW / 2;
  let cy;
  if (vert.includes('middle')) cy = y + boxH / 2;
  else if (vert.includes('bottom')) cy = y + boxH - textH / 2;
  else cy = y + textH / 2;
  const color = marked[0].fontColor || canvas.state.fontColor || '#000000';
  canvas.setStrokeColor(color);
  canvas.setStrokeWidth(1);
  canvas.setDashed(true);
  canvas.setDashPattern(marked[0].borderBottom === 'dashed' ? '6 3' : '1 2');
  canvas.begin();
  canvas.moveTo(cx - textW / 2, cy + textH / 2);
  canvas.lineTo(cx + textW / 2, cy + textH / 2);
  canvas.stroke();
  canvas.setDashed(false);
  canvas.setDashPattern('none');
}

function cloneHtmlStyle(style) {
  return {
    fontStyle: Number(style.fontStyle) || 0,
    fontColor: style.fontColor,
    fontSize: style.fontSize,
    fontFamily: style.fontFamily,
    textOpacity: style.textOpacity,
    position: Number(style.position) || 0,
    borderBottom: style.borderBottom || null,
    align: style.align || null,
    marginTop: Number(style.marginTop) || 0,
    marginRight: Number(style.marginRight) || 0,
    marginBottom: Number(style.marginBottom) || 0,
    marginLeft: Number(style.marginLeft) || 0,
    paraStart: !!style.paraStart,
    // mxText html=1 <ul>/<ol>/<li>. Bullet 1 is Visio disc (U+2022);
    // ordered items prefix "1. " because tokens.txt has no decimal list.
    bullet: Number(style.bullet) || 0,
    listKind: style.listKind || null,
    listPad: Number(style.listPad) || 0,
    olIndex: Number(style.olIndex) || 0,
    olNeedPrefix: !!style.olNeedPrefix,
    textPosAfterBullet: Number(style.textPosAfterBullet) || 0,
    lineHeight: Number(style.lineHeight) || 1,
    highlight: style.highlight || null,
  };
}

function sameHtmlStyle(a, b) {
  return (Number(a.fontStyle) || 0) === (Number(b.fontStyle) || 0)
    && String(a.fontColor || '') === String(b.fontColor || '')
    && Number(a.fontSize) === Number(b.fontSize)
    && String(a.fontFamily || '') === String(b.fontFamily || '')
    && Number(a.textOpacity) === Number(b.textOpacity)
    && (Number(a.position) || 0) === (Number(b.position) || 0)
    && String(a.borderBottom || '') === String(b.borderBottom || '')
    && String(a.align || '') === String(b.align || '')
    && (Number(a.marginTop) || 0) === (Number(b.marginTop) || 0)
    && (Number(a.marginRight) || 0) === (Number(b.marginRight) || 0)
    && (Number(a.marginBottom) || 0) === (Number(b.marginBottom) || 0)
    && (Number(a.marginLeft) || 0) === (Number(b.marginLeft) || 0)
    && (Number(a.bullet) || 0) === (Number(b.bullet) || 0)
    && (Number(a.textPosAfterBullet) || 0) === (Number(b.textPosAfterBullet) || 0)
    && (Number(a.lineHeight) || 1) === (Number(b.lineHeight) || 1)
    && String(a.highlight || '') === String(b.highlight || '');
}

function htmlLabelRunsDiffer(runs, state) {
  if (!runs || runs.length === 0) return false;
  if (runs.length > 1) return true;
  return !sameHtmlStyle(runs[0], {
    fontStyle: Number(state.fontStyle) || 0,
    fontColor: state.fontColor,
    fontSize: state.fontSize,
    fontFamily: state.fontFamily,
    textOpacity: state.textOpacity,
    align: state.align,
  });
}

// defaultVertex fontColor=default is mxConstants.DEFAULT_FONTCOLOR
// #000000. Emitting the keyword made decoder _mxGraphPaintColor null
// and Char.Color inherited the previous html <font color> run.
function htmlRunFontColorHex(raw) {
  if (raw == null || raw === '') return null;
  const token = String(raw).trim();
  const lower = token.toLowerCase();
  if (lower === 'none') return null;
  if (lower === 'default' || lower === 'font') return '#000000';
  return htmlCssColorToHex(token) || token;
}

function htmlRunAttrs(run) {
  const attrs = [`str="${xmlEscape(run.str)}"`];
  attrs.push(`fontstyle="${Number(run.fontStyle) || 0}"`);
  const size = Number(run.fontSize);
  if (Number.isFinite(size) && size > 0) attrs.push(`fontsize="${number(size)}"`);
  const fontColor = htmlRunFontColorHex(run.fontColor);
  if (fontColor) attrs.push(`fontcolor="${xmlEscape(fontColor)}"`);
  if (run.fontFamily) attrs.push(`fontfamily="${xmlEscape(String(run.fontFamily))}"`);
  const opacity = Number(run.textOpacity);
  if (Number.isFinite(opacity) && Math.abs(opacity - 100) > 1e-6) {
    attrs.push(`textopacity="${number(opacity)}"`);
  }
  // mxText html <sup>/<sub> → Char.Pos that readCharIX maps to
  // style:text-position super/sub.
  const pos = Number(run.position) || 0;
  if (pos === 1 || pos === 2) attrs.push(`pos="${pos}"`);
  if (run.align) attrs.push(`align="${xmlEscape(String(run.align))}"`);
  const ml = Number(run.marginLeft) || 0;
  const mr = Number(run.marginRight) || 0;
  const mt = Number(run.marginTop) || 0;
  const mb = Number(run.marginBottom) || 0;
  if (Math.abs(ml) > 1e-9) attrs.push(`margin-left="${number(ml)}"`);
  if (Math.abs(mr) > 1e-9) attrs.push(`margin-right="${number(mr)}"`);
  if (Math.abs(mt) > 1e-9) attrs.push(`margin-top="${number(mt)}"`);
  if (Math.abs(mb) > 1e-9) attrs.push(`margin-bottom="${number(mb)}"`);
  const bullet = Number(run.bullet) || 0;
  if (bullet > 0) attrs.push(`bullet="${bullet}"`);
  const tab = Number(run.textPosAfterBullet) || 0;
  if (Math.abs(tab) > 1e-9) attrs.push(`text-pos-after-bullet="${number(tab)}"`);
  const lineHeight = Number(run.lineHeight) || 1;
  if (Math.abs(lineHeight - 1) > 1e-9) {
    attrs.push(`line-height="${number(lineHeight)}"`);
  }
  if (run.highlight) {
    const hex = htmlCssColorToHex(run.highlight) || String(run.highlight);
    attrs.push(`highlight="${xmlEscape(hex)}"`);
  }
  return attrs.join(' ');
}

// mxText html=1: <b>/<i>/<font>/<sup>/<sub> and CSS text-decoration become
// Char Style / Color / Size / Pos that collectCharIX maps to fo:font-weight /
// fo:color / fo:font-size / style:text-underline-type / style:text-position.
// <ul>/<ol>/<li> become collectParaIX Bullet / TextPosAfterBullet (disc)
// or a "1. " prefix (decimal; tokens.txt has no numbered list).
function parseHtmlLabel(html, base) {
  const runs = [];
  const stack = [cloneHtmlStyle(base)];
  let pendingBlockMarginAfter = 0;
  const current = () => stack[stack.length - 1];
  const pushRun = (text) => {
    if (!text) return;
    const style = current();
    // HTML ol ::marker is decimal. tokens.txt has no numbered list, so
    // prefix "1. " that leftover Draw collects as Character text.
    if (style.olNeedPrefix && Number(style.olIndex) > 0 && text !== '\n') {
      text = `${Number(style.olIndex)}. ${text}`;
      style.olNeedPrefix = false;
    }
    const emit = cloneHtmlStyle(style);
    emit.olNeedPrefix = false;
    if (!style.paraStart) emit.marginTop = 0;
    // SpAfter belongs on the last run of the block (or the leftover
    // pending after CSS collapse). Inner <font>/<b> clones would
    // otherwise put margin-bottom on every run.
    emit.marginBottom = 0;
    if (text === '\n') {
      emit.marginTop = 0;
      emit.marginBottom = 0;
      // Keep margin-left / bullet / TextPosAfterBullet so <ol>/<ul>
      // items stay one Character row (Visio breaks paragraphs at \n).
    }
    const last = runs[runs.length - 1];
    if (last && sameHtmlStyle(last, emit)) last.str += text;
    else runs.push({str: text, ...emit});
    for (const frame of stack) frame.paraStart = false;
  };
  const tokenRe = /<!--[\s\S]*?-->|<(\/)?([a-zA-Z][a-zA-Z0-9]*)([^>]*)>|([^<]+)/g;
  let match;
  while ((match = tokenRe.exec(html))) {
    if (match[0].startsWith('<!--')) continue;
    if (match[4]) {
      pushRun(decodeHtmlEntities(match[4]).replace(/[^\S\n]+/g, ' '));
      continue;
    }
    const tag = match[2].toLowerCase();
    const attrs = match[3] || '';
    const closing = !!match[1] || /\/\s*$/.test(attrs);
    const block = tag === 'p' || tag === 'div' || tag === 'tr' || tag === 'li' ||
      /^h[1-6]$/.test(tag);
    if (tag === 'br' || tag === 'hr') {
      pushRun('\n');
      continue;
    }
    if (match[1]) {
      // </p> still ends the line; styles were pushed on the open tag.
      // CSS adjoining vertical margins collapse; stash margin-bottom so
      // the next block's SpBefore is max(prev, next), not the sum
      // collectParaIX would stack into fo:margin-top + fo:margin-bottom.
      if (block && runs.length) {
        pendingBlockMarginAfter = Number(current().marginBottom) || 0;
        if (!String(runs[runs.length - 1].str).endsWith('\n')) {
          pushRun('\n');
        }
      }
      if (stack.length > 1) stack.pop();
      continue;
    }
    if (closing) continue;
    const next = cloneHtmlStyle(current());
    if (block && runs.length &&
        !String(runs[runs.length - 1].str).endsWith('\n')) {
      pushRun('\n');
    }
    if (tag === 'b' || tag === 'strong') next.fontStyle |= 1;
    else if (tag === 'i' || tag === 'em') next.fontStyle |= 2;
    else if (tag === 'u') next.fontStyle |= 4;
    else if (tag === 's' || tag === 'strike' || tag === 'del') next.fontStyle |= 8;
    else if (tag === 'sup') next.position = 1;
    else if (tag === 'sub') next.position = 2;
    // html.spec UA: ul disc / ol decimal, padding-inline-start 40px.
    // collectParaIX Bullet 1 is U+2022; leftover bakes that glyph because
    // Draw never paints text:bullet-char.
    else if (tag === 'ul') {
      next.listKind = 'ul';
      next.bullet = 1;
      next.listPad = (Number(next.listPad) || 0) + kHtmlListPadPx;
      next.olIndex = 0;
      next.olNeedPrefix = false;
    } else if (tag === 'ol') {
      next.listKind = 'ol';
      next.bullet = 0;
      next.listPad = (Number(next.listPad) || 0) + kHtmlListPadPx;
      next.olIndex = 0;
      next.olNeedPrefix = false;
    } else if (tag === 'li') {
      if (next.listKind === 'ol') {
        const parent = current();
        parent.olIndex = (Number(parent.olIndex) || 0) + 1;
        next.olIndex = parent.olIndex;
        next.olNeedPrefix = true;
        next.bullet = 0;
        next.marginLeft = (Number(next.marginLeft) || 0)
          + (Number(next.listPad) || kHtmlListPadPx);
      } else if (next.listKind === 'ul') {
        next.bullet = 1;
        next.textPosAfterBullet = Number(next.listPad) || kHtmlListPadPx;
        next.olNeedPrefix = false;
      }
    }
    applyHtmlCss(next, attrs, tag);
    if (block && pendingBlockMarginAfter) {
      next.marginTop = Math.max(
        Number(next.marginTop) || 0, pendingBlockMarginAfter,
      );
      pendingBlockMarginAfter = 0;
    }
    stack.push(next);
  }
  if (pendingBlockMarginAfter) {
    for (let i = runs.length - 1; i >= 0; i--) {
      if (String(runs[i].str) !== '\n') {
        runs[i].marginBottom = pendingBlockMarginAfter;
        break;
      }
    }
  }
  return runs;
}

// mxText html=1 tables (P&ID TI/##, Electrical thermistor \temp\, Mockup
// Step Bar, UML Entity header+table, General HTML Table 4) are 100%×100%
// grids. Flattening them to one collectTextBlock box centred the caption
// on the glyph; LibreOffice must pin each cell like the HTML table.
// A caption `<div>` before `<table>` (Entity Tablename) is a header
// row, not a reason to abort. `height=0%` with text is a content band
// (browser min-content), not a zero-height skip.
function htmlHasVisibleText(html) {
  return !!cellLabel(html, false).trim();
}

function htmlTdFragment(attrs, inner) {
  const body = inner || '';
  const style = htmlAttr(attrs, 'style');
  if (style) return `<span style="${style}">${body}</span>`;
  return body;
}

function htmlLeadingBlock(html) {
  const source = String(html || '').trim();
  const open = /^<([a-z][\w:-]*)\b([^>]*)>/i.exec(source);
  if (!open) return {attrs: '', html: source};
  return {attrs: open[2] || '', html: source};
}

function htmlTableCellSpec(cell, tag) {
  const attrs = cell.attrs || '';
  const kind = String(tag || 'td').toLowerCase();
  return {
    widthToken: htmlAttr(attrs, 'width') || htmlStyleProp(attrs, 'width'),
    align: htmlAlignToken(
      htmlAttr(attrs, 'align') || htmlStyleProp(attrs, 'text-align'),
    ) || (kind === 'th' ? 'center' : null),
    valign: htmlAttr(attrs, 'valign') || htmlStyleProp(attrs, 'vertical-align'),
    attrs,
    html: htmlTdFragment(attrs, cell.inner),
  };
}

function htmlBlockRowSpec(html) {
  const lead = htmlLeadingBlock(html);
  return {
    // Caption <div> before/after <table> (UML Entity Tablename) is not a
    // td. table cellpadding must not stack on its CSS padding.
    caption: true,
    heightToken: null,
    cells: [{
      widthToken: '100%',
      align: htmlAlignToken(
        htmlStyleProp(lead.attrs, 'text-align') || htmlAttr(lead.attrs, 'align'),
      ),
      valign: htmlAttr(lead.attrs, 'valign')
        || htmlStyleProp(lead.attrs, 'vertical-align'),
      attrs: lead.attrs,
      html: lead.html,
    }],
  };
}

function htmlTableRowSpecs(html) {
  const source = String(html || '');
  const tableMatch = /<table\b([^>]*)>([\s\S]*)<\/table>/i.exec(source);
  if (!tableMatch) return null;
  const before = source.slice(0, tableMatch.index);
  const after = source.slice(tableMatch.index + tableMatch[0].length);
  const rows = [];
  if (cellLabel(before, false).trim()) rows.push(htmlBlockRowSpec(before));
  // Browsers still parse a last <tr> without </tr> (P&ID discInst
  // `<tr><td>##</td></table>`). Requiring </tr> folded TI/## into one box.
  const trRe = /<tr\b([^>]*)>([\s\S]*?)(?:<\/tr\s*>|(?=<tr\b)|(?=<\/table)|$)/gi;
  let match;
  while ((match = trRe.exec(tableMatch[2]))) {
    const inner = match[2] || '';
    const tds = [];
    // html.spec: th is a cell. Title in General HTML Table 4 is <th>.
    const tdRe = /<(td|th)\b([^>/]*)(?:\/>|>([\s\S]*?)<\/(?:td|th)>)/gi;
    let td;
    while ((td = tdRe.exec(inner))) {
      tds.push({tag: td[1], attrs: td[2] || '', inner: td[3] || ''});
    }
    const trAttrs = match[1] || '';
    const cells = (tds.length ? tds : [{tag: 'td', attrs: '', inner}]).map(
      (cell) => htmlTableCellSpec(cell, cell.tag),
    );
    const firstAttrs = tds.length ? tds[0].attrs : '';
    const heightToken = htmlAttr(trAttrs, 'height')
      || htmlStyleProp(trAttrs, 'height')
      || htmlAttr(firstAttrs, 'height')
      || htmlStyleProp(firstAttrs, 'height');
    rows.push({heightToken, cells});
  }
  if (cellLabel(after, false).trim()) rows.push(htmlBlockRowSpec(after));
  if (rows.length < 1) return null;
  const multiCol = rows.some((row) => row.cells.length > 1);
  if (!multiCol && rows.length < 2) return null;
  return rows;
}

// HTML table cellpadding is a presentational hint for td padding.
// collectTextBlock LeftMargin maps that onto fo:padding-left, on top of
// mxText.style spacing already on canvas.state.
function htmlTableFontSizePx(html, currentPx) {
  const open = /<table\b([^>]*)>/i.exec(String(html || ''));
  if (!open) return null;
  return htmlCssFontSizePx(htmlStyleProp(open[1], 'font-size'), currentPx);
}

function htmlTablePaddingPx(html) {
  const open = /<table\b([^>]*)>/i.exec(String(html || ''));
  if (!open) return 0;
  const attr = htmlAttr(open[1], 'cellpadding');
  const n = htmlCssPx(attr);
  return n != null && n > 0 ? n : 0;
}

function htmlCssBackgroundHex(attrs) {
  const from = htmlStyleProp(attrs, 'background-color')
    || htmlStyleProp(attrs, 'background');
  if (!from || /^(none|transparent|initial|unset)$/i.test(String(from).trim())) {
    return null;
  }
  return htmlCssColorToHex(from);
}

// HTML table border presentational hint (html.spec tables). border="1"
// plus border-collapse:collapse is a 1px grid. libvisio has no table
// token; collectLine paints sibling Lines `_lineProperties` maps to
// svg:stroke (same leftover as mxText <hr>).
function htmlTableBorderPx(html) {
  const open = /<table\b([^>]*)>/i.exec(String(html || ''));
  if (!open) return 0;
  const attrs = open[1] || '';
  const attr = htmlCssPx(htmlAttr(attrs, 'border'));
  if (attr != null && attr > 0) return attr;
  const css = htmlStyleProp(attrs, 'border-width')
    || htmlStyleProp(attrs, 'border');
  if (!css || /none/i.test(css)) return 0;
  const n = htmlCssPx(css);
  return n != null && n > 0 ? n : 0;
}

function htmlTableBorderColor(html) {
  const open = /<table\b([^>]*)>/i.exec(String(html || ''));
  const attrs = open ? (open[1] || '') : '';
  const from = htmlStyleProp(attrs, 'border-color')
    || htmlStyleProp(attrs, 'border')
    || htmlStyleProp(attrs, 'color');
  return htmlCssColorToHex(from) || '#000000';
}

// HTML td CSS padding (P&ID compressor `padding-left:11%`). Table
// cellpadding is the presentational hint; a td longhand wins. Both
// land on collectTextBlock LeftMargin → fo:padding-left.
function htmlBoxPadding(attrs, boxW) {
  const out = {top: 0, right: 0, bottom: 0, left: 0};
  if (!attrs) return out;
  const box = String(htmlStyleProp(attrs, 'padding') || '').trim();
  if (box) {
    const parts = box.split(/\s+/).map((part) => htmlCssLength(part, boxW));
    if (parts.length && parts.every((v) => v != null)) {
      if (parts.length === 1) {
        out.top = out.right = out.bottom = out.left = parts[0];
      } else if (parts.length === 2) {
        out.top = out.bottom = parts[0];
        out.right = out.left = parts[1];
      } else if (parts.length === 3) {
        out.top = parts[0];
        out.right = out.left = parts[1];
        out.bottom = parts[2];
      } else {
        out.top = parts[0];
        out.right = parts[1];
        out.bottom = parts[2];
        out.left = parts[3];
      }
    }
  }
  const pt = htmlCssLength(htmlStyleProp(attrs, 'padding-top'), boxW);
  if (pt != null) out.top = pt;
  const pr = htmlCssLength(htmlStyleProp(attrs, 'padding-right'), boxW);
  if (pr != null) out.right = pr;
  const pb = htmlCssLength(htmlStyleProp(attrs, 'padding-bottom'), boxW);
  if (pb != null) out.bottom = pb;
  const pl = htmlCssLength(htmlStyleProp(attrs, 'padding-left'), boxW);
  if (pl != null) out.left = pl;
  return out;
}

function htmlRowHasText(row) {
  return (row.cells || []).some((cell) => htmlHasVisibleText(cell.html));
}

function htmlContentBandPx(fontSize) {
  const size = Number(fontSize);
  return Math.max(8, (Number.isFinite(size) && size > 0 ? size : 12) * 1.4);
}

function htmlRowHeightPx(token, boxH, hasText, fontSize) {
  if (token == null || token === '') return null;
  const t = String(token).trim();
  if (/%$/.test(t)) {
    const n = parseFloat(t);
    if (!Number.isFinite(n)) return null;
    // HTML 0% + content sizes to the line box; 100% eats the leftover.
    if (n <= 0) return hasText ? htmlContentBandPx(fontSize) : 0;
    if (n >= 100) return null;
    return boxH * n / 100;
  }
  const n = parseFloat(t);
  if (!Number.isFinite(n)) return null;
  if (n <= 0) return hasText ? htmlContentBandPx(fontSize) : 0;
  return n;
}

function htmlColWidthPx(token, boxW) {
  if (token == null || token === '') return null;
  const t = String(token).trim();
  if (/%$/.test(t)) {
    const n = parseFloat(t);
    return Number.isFinite(n) && n > 0 ? boxW * n / 100 : null;
  }
  const n = parseFloat(t);
  return Number.isFinite(n) && n > 0 ? n : null;
}

function htmlColWidths(cells, boxW) {
  const widths = cells.map((cell) => htmlColWidthPx(cell.widthToken, boxW));
  const known = widths.reduce((sum, v) => sum + (v || 0), 0);
  const missing = widths.filter((v) => v == null).length;
  const auto = missing > 0 ? Math.max(0, boxW - known) / missing : 0;
  return widths.map((v) => (v == null ? auto : v));
}

function paintHtmlTableLabel(
  canvas, x, y, w, h, html, defaultAlign, defaultValign, rotation,
) {
  const rows = htmlTableRowSpecs(html);
  if (!rows) return false;
  const baseSize = canvas && canvas.state ? canvas.state.fontSize : 11;
  const tableSize = htmlTableFontSizePx(html, baseSize);
  const fontSize = tableSize != null ? tableSize : baseSize;
  const heights = rows.map((row) => htmlRowHeightPx(
    row.heightToken, h, htmlRowHasText(row), fontSize,
  ));
  const known = heights.reduce((sum, v) => sum + (v || 0), 0);
  const missing = heights.filter((v) => v == null).length;
  const auto = missing > 0 ? Math.max(0, h - known) / missing : 0;
  const pad = htmlTablePaddingPx(html);
  const prevL = canvas.state.spacingLeft;
  const prevR = canvas.state.spacingRight;
  const prevT = canvas.state.spacingTop;
  const prevB = canvas.state.spacingBottom;
  const prevSize = canvas.state.fontSize;
  if (tableSize != null) canvas.state.fontSize = tableSize;
  const resolvedHeights = rows.map((row, i) => (
    heights[i] == null ? auto : heights[i]
  ));
  let top = y;
  let painted = false;
  for (let i = 0; i < rows.length; i++) {
    const rh = resolvedHeights[i];
    const row = rows[i];
    if (rh > 0 && htmlRowHasText(row)) {
      const widths = htmlColWidths(row.cells, w);
      let left = x;
      for (let j = 0; j < row.cells.length; j++) {
        const cell = row.cells[j];
        const cw = widths[j];
        if (cw > 0 && htmlHasVisibleText(cell.html)) {
          // html.spec cellpadding is td/th padding. A caption <div>
          // before the table (Entity Tablename padding:2px) is not a
          // cell; stacking cellpadding on CSS padding doubled
          // collectTextBlock LeftMargin (4px vs the UA 2px).
          const extra = htmlBoxPadding(cell.attrs, cw);
          const rowPad = row.caption ? 0 : pad;
          canvas.state.spacingLeft = (Number(prevL) || 0) + rowPad + extra.left;
          canvas.state.spacingRight = (Number(prevR) || 0) + rowPad + extra.right;
          canvas.state.spacingTop = (Number(prevT) || 0) + rowPad + extra.top;
          canvas.state.spacingBottom = (Number(prevB) || 0) + rowPad + extra.bottom;
          // CSS background on the header div (UML Entity Tablename
          // #e4e4e4) is collectTextBlock TextBkgnd → fo:background-color.
          const bg = htmlCssBackgroundHex(cell.attrs);
          const prevBg = canvas.state.fontBackgroundColor;
          if (bg) canvas.setFontBackgroundColor(bg);
          // html.spec td/th { vertical-align: middle }. Outer mxText
          // verticalAlign (named style `text` = top on General HTML
          // Table 4, or Entity's explicit top) applies to the
          // foreignObject, not each cell. A 100%×100% table fills that
          // box; leftover collectTextBlock VerticalAlign is
          // draw:textarea-vertical-align. Caption <div> rows are not
          // cells and keep the mxText valign.
          canvas.text(
            left, top, cw, rh, cellLabel(cell.html, true),
            cell.align || defaultAlign,
            cell.valign || (row.caption ? defaultValign : 'middle') || 'middle',
            undefined, 'html', undefined, undefined, rotation,
          );
          if (bg) canvas.setFontBackgroundColor(prevBg);
          painted = true;
        }
        left += cw;
      }
    }
    top += rh;
  }
  canvas.state.spacingLeft = prevL;
  canvas.state.spacingRight = prevR;
  canvas.state.spacingTop = prevT;
  canvas.state.spacingBottom = prevB;
  if (tableSize != null) canvas.state.fontSize = prevSize;
  paintHtmlTableBorders(canvas, x, y, w, h, html, rows, resolvedHeights);
  return painted || rows.every((row) => !htmlRowHasText(row));
}

// mxText html <hr> (SysML compartment rules, GCP product cards, Bootstrap
// Alert). libvisio has no hr token; collectLine paints a sibling Line
// that `_lineProperties` maps to svg:stroke. Splitting the label like
// overflow=fill table rows keeps title / body Txt pins apart.
// mxUtils.color2hex / canvas fillStyle. SVG fill="gray" must become
// #808080 so leftover FillForegnd is collectFillAndShadow solid, not
// inherit that applyStencilStyle washes.
const cssNamedColors = {
  aliceblue: '#f0f8ff', antiquewhite: '#faebd7', aqua: '#00ffff',
  aquamarine: '#7fffd4', azure: '#f0ffff', beige: '#f5f5dc',
  bisque: '#ffe4c4', black: '#000000', blanchedalmond: '#ffebcd',
  blue: '#0000ff', blueviolet: '#8a2be2', brown: '#a52a2a',
  burlywood: '#deb887', cadetblue: '#5f9ea0', chartreuse: '#7fff00',
  chocolate: '#d2691e', coral: '#ff7f50', cornflowerblue: '#6495ed',
  cornsilk: '#fff8dc', crimson: '#dc143c', cyan: '#00ffff',
  darkblue: '#00008b', darkcyan: '#008b8b', darkgoldenrod: '#b8860b',
  darkgray: '#a9a9a9', darkgreen: '#006400', darkgrey: '#a9a9a9',
  darkkhaki: '#bdb76b', darkmagenta: '#8b008b', darkolivegreen: '#556b2f',
  darkorange: '#ff8c00', darkorchid: '#9932cc', darkred: '#8b0000',
  darksalmon: '#e9967a', darkseagreen: '#8fbc8f', darkslateblue: '#483d8b',
  darkslategray: '#2f4f4f', darkslategrey: '#2f4f4f', darkturquoise: '#00ced1',
  darkviolet: '#9400d3', deeppink: '#ff1493', deepskyblue: '#00bfff',
  dimgray: '#696969', dimgrey: '#696969', dodgerblue: '#1e90ff',
  firebrick: '#b22222', floralwhite: '#fffaf0', forestgreen: '#228b22',
  fuchsia: '#ff00ff', gainsboro: '#dcdcdc', ghostwhite: '#f8f8ff',
  gold: '#ffd700', goldenrod: '#daa520', gray: '#808080',
  green: '#008000', greenyellow: '#adff2f', grey: '#808080',
  honeydew: '#f0fff0', hotpink: '#ff69b4', indianred: '#cd5c5c',
  indigo: '#4b0082', ivory: '#fffff0', khaki: '#f0e68c',
  lavender: '#e6e6fa', lavenderblush: '#fff0f5', lawngreen: '#7cfc00',
  lemonchiffon: '#fffacd', lightblue: '#add8e6', lightcoral: '#f08080',
  lightcyan: '#e0ffff', lightgoldenrodyellow: '#fafad2', lightgray: '#d3d3d3',
  lightgreen: '#90ee90', lightgrey: '#d3d3d3', lightpink: '#ffb6c1',
  lightsalmon: '#ffa07a', lightseagreen: '#20b2aa', lightskyblue: '#87cefa',
  lightslategray: '#778899', lightslategrey: '#778899', lightsteelblue: '#b0c4de',
  lightyellow: '#ffffe0', lime: '#00ff00', limegreen: '#32cd32',
  linen: '#faf0e6', magenta: '#ff00ff', maroon: '#800000',
  mediumaquamarine: '#66cdaa', mediumblue: '#0000cd', mediumorchid: '#ba55d3',
  mediumpurple: '#9370db', mediumseagreen: '#3cb371', mediumslateblue: '#7b68ee',
  mediumspringgreen: '#00fa9a', mediumturquoise: '#48d1cc', mediumvioletred: '#c71585',
  midnightblue: '#191970', mintcream: '#f5fffa', mistyrose: '#ffe4e1',
  moccasin: '#ffe4b5', navajowhite: '#ffdead', navy: '#000080',
  oldlace: '#fdf5e6', olive: '#808000', olivedrab: '#6b8e23',
  orange: '#ffa500', orangered: '#ff4500', orchid: '#da70d6',
  palegoldenrod: '#eee8aa', palegreen: '#98fb98', paleturquoise: '#afeeee',
  palevioletred: '#db7093', papayawhip: '#ffefd5', peachpuff: '#ffdab9',
  peru: '#cd853f', pink: '#ffc0cb', plum: '#dda0dd',
  powderblue: '#b0e0e6', purple: '#800080', rebeccapurple: '#663399',
  red: '#ff0000', rosybrown: '#bc8f8f', royalblue: '#4169e1',
  saddlebrown: '#8b4513', salmon: '#fa8072', sandybrown: '#f4a460',
  seagreen: '#2e8b57', seashell: '#fff5ee', sienna: '#a0522d',
  silver: '#c0c0c0', skyblue: '#87ceeb', slateblue: '#6a5acd',
  slategray: '#708090', slategrey: '#708090', snow: '#fffafa',
  springgreen: '#00ff7f', steelblue: '#4682b4', tan: '#d2b48c',
  teal: '#008080', thistle: '#d8bfd8', tomato: '#ff6347',
  turquoise: '#40e0d0', violet: '#ee82ee', wheat: '#f5deb3',
  white: '#ffffff', whitesmoke: '#f5f5f5', yellow: '#ffff00',
  yellowgreen: '#9acd32',
};

function htmlCssColorToHex(raw) {
  const token = String(raw || '').trim();
  const hex = /#([0-9a-f]{8}|[0-9a-f]{6}|[0-9a-f]{3})/i.exec(token);
  if (hex) {
    let h = hex[1];
    if (h.length === 3) h = `${h[0]}${h[0]}${h[1]}${h[1]}${h[2]}${h[2]}`;
    return `#${h.slice(0, 6)}`;
  }
  const rgb = /rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)/i.exec(token);
  if (rgb) {
    const to = (n) => Number(n).toString(16).padStart(2, '0');
    return `#${to(rgb[1])}${to(rgb[2])}${to(rgb[3])}`;
  }
  return cssNamedColors[token.toLowerCase()] || null;
}

function htmlHrColor(attrs) {
  const from = htmlStyleProp(attrs, 'border-color')
    || htmlStyleProp(attrs, 'border-top-color')
    || htmlStyleProp(attrs, 'color')
    || htmlStyleProp(attrs, 'background-color')
    || htmlStyleProp(attrs, 'border-top')
    || htmlStyleProp(attrs, 'border');
  return htmlCssColorToHex(from) || htmlCssColorToHex(attrs);
}

function htmlHrParts(html) {
  const source = String(html || '');
  const re = /<hr\b([^>]*)\/?>/gi;
  const parts = [];
  const rules = [];
  let last = 0;
  let match;
  while ((match = re.exec(source))) {
    parts.push(source.slice(last, match.index));
    rules.push(match[1] || '');
    last = re.lastIndex;
  }
  if (!rules.length) return null;
  parts.push(source.slice(last));
  return {parts, rules};
}

function htmlHrPartCssHeight(html) {
  const n = htmlCssPx(htmlStyleProp(htmlLeadingBlock(html).attrs, 'height'));
  return n != null && n > 0 ? n : 0;
}

function htmlHrPartMarginTop(html) {
  const attrs = htmlLeadingBlock(html).attrs;
  const mt = htmlCssPx(htmlStyleProp(attrs, 'margin-top'));
  if (mt != null) return Math.max(0, mt);
  const box = String(htmlStyleProp(attrs, 'margin') || '').trim();
  if (!box) return 0;
  const parts = box.split(/\s+/).map(htmlCssPx);
  return parts[0] != null ? Math.max(0, parts[0]) : 0;
}

// Official mxText overflow=fill html=1 is a foreignObject with CSS block
// flow: the title <p> is content-sized, <hr> follows, and UML Class 3/4's
// empty `<div style="height:2px">` is a 2px spacer. Weighting only visible
// text gave empty parts 0 and stretched the title, so the leftover
// collectLine sat on the bottom of the cell. tokens.txt has no hr token.
function htmlHrPartContentHeight(html, fontSize) {
  const fs = Number(fontSize) > 0 ? Number(fontSize) : 11;
  const cssH = htmlHrPartCssHeight(html);
  if (!htmlHasVisibleText(html)) return cssH;
  const text = cellLabel(html, false);
  const lines = Math.max(1, text.split('\n').filter((s) => s.trim()).length);
  return Math.max(cssH, lines * fs * 1.2 + htmlHrPartMarginTop(html));
}

function htmlHrBandHeights(parts, rules, h, fontSize) {
  const fs = Number(fontSize) > 0 ? Number(fontSize) : 11;
  const hrBand = Math.max(6, fs * 0.55);
  const ruleH = hrBand * rules.length;
  const heights = parts.map((html) => htmlHrPartContentHeight(html, fs));
  let contentSum = heights.reduce((sum, v) => sum + v, 0);
  const maxContent = Math.max(0, h - ruleH);
  if (contentSum > maxContent && contentSum > 0) {
    const scale = maxContent / contentSum;
    for (let i = 0; i < heights.length; i++) heights[i] *= scale;
    contentSum = maxContent;
  }
  const leftover = Math.max(0, maxContent - contentSum);
  if (leftover > 0) {
    let grown = false;
    for (let i = heights.length - 1; i >= 0; i--) {
      if (!htmlHasVisibleText(parts[i])) {
        heights[i] += leftover;
        grown = true;
        break;
      }
    }
    if (!grown && heights.length) heights[heights.length - 1] += leftover;
  }
  return {heights, hrBand};
}

function paintHtmlHrRule(canvas, x, y, w, bandH, attrs) {
  const prevColor = canvas.state.strokeColor;
  const prevWidth = canvas.state.strokeWidth;
  const prevDashed = canvas.state.dashed;
  const color = htmlHrColor(attrs)
    || canvas.state.fontColor
    || '#808080';
  const insetL = Number(canvas.state.spacingLeft) || 0;
  const insetR = Number(canvas.state.spacingRight) || 0;
  const left = x + insetL;
  const right = x + w - insetR;
  if (!(right - left > 1) || !(bandH > 0)) return;
  const cy = y + bandH / 2;
  // paintToken collapses #000000 onto inherit `stroke`. collectGeometry
  // then evenodd-merges the rule into the rect; force a hex so
  // bakeStroke makes a collectLine sibling like Weak Key's dash.
  const savedStyleStroke = canvas.styleStroke;
  canvas.styleStroke = null;
  canvas.setStrokeColor(color);
  canvas.setStrokeWidth(1);
  canvas.setDashed(false);
  canvas.begin();
  canvas.moveTo(left, cy);
  canvas.lineTo(right, cy);
  canvas.stroke();
  canvas.styleStroke = savedStyleStroke;
  canvas.setStrokeColor(prevColor);
  if (Number.isFinite(prevWidth) && prevWidth > 0) {
    canvas.setStrokeWidth(prevWidth);
  }
  canvas.setDashed(!!prevDashed);
}

function paintHtmlTableLine(canvas, x1, y1, x2, y2) {
  if (Math.abs(x2 - x1) < 1e-9 && Math.abs(y2 - y1) < 1e-9) return;
  canvas.begin();
  canvas.moveTo(x1, y1);
  canvas.lineTo(x2, y2);
  canvas.stroke();
}

function paintHtmlTableBorders(canvas, x, y, w, h, html, rows, heights) {
  const width = htmlTableBorderPx(html);
  if (!(width > 0) || !(w > 1) || !(h > 1) || !rows.length) return;
  const prevColor = canvas.state.strokeColor;
  const prevWidth = canvas.state.strokeWidth;
  const prevDashed = canvas.state.dashed;
  const color = htmlTableBorderColor(html);
  // paintToken collapses #000000 onto inherit `stroke`. HTML Table 4 is
  // strokeColor=none; force a hex so bakeStroke is a collectLine sibling
  // like <hr>.
  const savedStyleStroke = canvas.styleStroke;
  canvas.styleStroke = null;
  canvas.setStrokeColor(color);
  canvas.setStrokeWidth(width);
  canvas.setDashed(false);
  const right = x + w;
  const bottom = y + h;
  paintHtmlTableLine(canvas, x, y, right, y);
  paintHtmlTableLine(canvas, right, y, right, bottom);
  paintHtmlTableLine(canvas, right, bottom, x, bottom);
  paintHtmlTableLine(canvas, x, bottom, x, y);
  let top = y;
  for (let i = 0; i < rows.length; i++) {
    const rh = Number(heights[i]) || 0;
    if (i > 0 && rh >= 0) {
      paintHtmlTableLine(canvas, x, top, right, top);
    }
    if (rh > 0) {
      const cols = htmlColWidths(rows[i].cells, w);
      let left = x;
      for (let j = 0; j < cols.length - 1; j++) {
        left += cols[j];
        paintHtmlTableLine(canvas, left, top, left, top + rh);
      }
    }
    top += rh;
  }
  canvas.styleStroke = savedStyleStroke;
  canvas.setStrokeColor(prevColor);
  if (Number.isFinite(prevWidth) && prevWidth > 0) {
    canvas.setStrokeWidth(prevWidth);
  }
  canvas.setDashed(!!prevDashed);
}

function paintHtmlHrLabel(
  canvas, x, y, w, h, html, defaultAlign, defaultValign, rotation,
) {
  const spec = htmlHrParts(html);
  if (!spec) return false;
  const {parts, rules} = spec;
  if (!parts.some(htmlHasVisibleText)) return false;
  const fontSize = canvas && canvas.state ? canvas.state.fontSize : 11;
  const {heights, hrBand} = htmlHrBandHeights(parts, rules, h, fontSize);
  let top = y;
  let painted = false;
  for (let i = 0; i < parts.length; i++) {
    const rh = heights[i];
    if (rh > 0 && htmlHasVisibleText(parts[i])) {
      canvas.text(
        x, top, w, rh, parts[i], defaultAlign, 'top',
        undefined, 'html', undefined, undefined, rotation,
      );
      painted = true;
    }
    top += rh;
    if (i < rules.length) {
      paintHtmlHrRule(canvas, x, top, w, hrBand, rules[i]);
      top += hrBand;
    }
  }
  return painted;
}

function paintHtmlStructuredLabel(
  canvas, x, y, w, h, html, defaultAlign, defaultValign, rotation,
) {
  return paintHtmlTableLabel(
    canvas, x, y, w, h, html, defaultAlign, defaultValign, rotation,
  ) || paintHtmlHrLabel(
    canvas, x, y, w, h, html, defaultAlign, defaultValign, rotation,
  );
}

function isHtmlCellStyle(style) {
  return !!(style && (style.html == 1 || style.html === '1'));
}

// Graph.getAutosizeTextAvailableSpace: spacing 2 plus spacingLeft/Right
// defaults of 2. tokens.txt has no autosizeText; leftover freezes the
// fitted Char.Size collectCharIX maps to fo:font-size.
function getAutosizeTextAvailableSpace(style, w, h) {
  const spacing = parseFloat(mxUtils.getValue(style, mxConstants.STYLE_SPACING, 2));
  const sl = parseFloat(mxUtils.getValue(style, mxConstants.STYLE_SPACING_LEFT, 2));
  const sr = parseFloat(mxUtils.getValue(style, mxConstants.STYLE_SPACING_RIGHT, 2));
  const st = parseFloat(mxUtils.getValue(style, mxConstants.STYLE_SPACING_TOP, 2));
  const sb = parseFloat(mxUtils.getValue(style, mxConstants.STYLE_SPACING_BOTTOM, 2));
  let dx = 2 * (Number.isFinite(spacing) ? spacing : 2)
    + (Number.isFinite(sl) ? sl : 2)
    + (Number.isFinite(sr) ? sr : 2);
  let dy = 2 * (Number.isFinite(spacing) ? spacing : 2)
    + (Number.isFinite(st) ? st : 2)
    + (Number.isFinite(sb) ? sb : 2);
  if (style && style[mxConstants.STYLE_IMAGE] != null &&
      style[mxConstants.STYLE_SHAPE] == mxConstants.SHAPE_LABEL) {
    if (style[mxConstants.STYLE_VERTICAL_ALIGN] == mxConstants.ALIGN_MIDDLE) {
      dx += parseFloat(mxUtils.getValue(style, mxConstants.STYLE_IMAGE_WIDTH, 24));
    }
    if (style[mxConstants.STYLE_ALIGN] != mxConstants.ALIGN_CENTER) {
      dy += parseFloat(mxUtils.getValue(style, mxConstants.STYLE_IMAGE_HEIGHT, 24));
    }
  }
  const horizontal = mxUtils.getValue(style, mxConstants.STYLE_HORIZONTAL, true);
  const availW = (horizontal == 0 || horizontal === '0' || horizontal === false ? h : w) - dx;
  const availH = (horizontal == 0 || horizontal === '0' || horizontal === false ? w : h) - dy;
  if (!(availW > 0) || !(availH > 0)) return null;
  return {availW, availH};
}

function computeAutosizeTextFontSize(value, availW, availH, fontFamily, fontStyle, wrap) {
  let lo = 1;
  let hi = 84;
  const textW = wrap ? availW : null;
  let wordsValue = null;
  if (wrap) {
    const plainText = String(value || '').replace(/<br\s*\/?>/gi, '\n').replace(/<[^>]*>/g, '');
    const words = plainText.split(/[\s\n]+/).filter((word) => word.length);
    if (words.length) {
      wordsValue = words.map((word) => mxUtils.htmlEntities(word, false)).join('<br>');
    }
  }
  while (lo < hi) {
    const mid = Math.ceil((lo + hi) / 2);
    const size = mxUtils.getSizeForString(value, mid, fontFamily, textW, fontStyle);
    let fits = wrap ? (size.height <= availH) : (size.width <= availW && size.height <= availH);
    if (fits && wrap && wordsValue != null) {
      const wordsSize = mxUtils.getSizeForString(wordsValue, mid, fontFamily, null, fontStyle);
      if (wordsSize.width > availW) fits = false;
    }
    if (fits) lo = mid;
    else hi = mid - 1;
  }
  return Math.max(6, lo);
}

function fittedAutosizeTextFontSize(style, w, h, label) {
  if (!style || (style.autosizeText != 1 && style.autosizeText !== '1')) return null;
  const space = getAutosizeTextAvailableSpace(style, w, h);
  if (!space) return null;
  let value = String(label || '');
  if (!value) return null;
  if (!isHtmlCellStyle(style)) value = mxUtils.htmlEntities(value, false);
  value = value.replace(/\n/g, '<br>');
  const wrap = String(style.whiteSpace || '') === 'wrap';
  return computeAutosizeTextFontSize(
    value, space.availW, space.availH, style.fontFamily, style.fontStyle, wrap,
  );
}

function applyTextStyle(canvas, style, box) {
  if (!canvas || !style) return;
  // mxText.configureCanvas: cell labels are not paintVertexShape.
  // LibreOffice collectCharIX / collectTextBlock only see Char.Size /
  // Color / Font and TextBkgnd on the Text children we emit here.
  if (style.fontColor != null && canvas.setFontColor) {
    canvas.setFontColor(style.fontColor);
  }
  if (style.labelBackgroundColor != null && canvas.setFontBackgroundColor) {
    canvas.setFontBackgroundColor(style.labelBackgroundColor);
  }
  if (style.labelBorderColor != null && canvas.setFontBorderColor) {
    canvas.setFontBorderColor(style.labelBorderColor);
  }
  if (style.fontFamily != null && canvas.setFontFamily) {
    canvas.setFontFamily(style.fontFamily);
  }
  let size = Number(style.fontSize);
  if (box && box.w > 0 && box.h > 0 && box.label) {
    const fitted = fittedAutosizeTextFontSize(style, box.w, box.h, box.label);
    if (Number.isFinite(fitted) && fitted > 0) size = fitted;
  }
  if (Number.isFinite(size) && size > 0 && canvas.setFontSize) {
    canvas.setFontSize(size);
  }
  // mxText.configureCanvas always calls setFontStyle(this.fontStyle)
  // (default 0). Skipping omitted keys leaked the previous cell's
  // FONT_ITALIC / FONT_BOLD onto the next sibling.
  if (canvas.setFontStyle) {
    const fs = Number(style.fontStyle);
    canvas.setFontStyle(Number.isFinite(fs) ? fs : 0);
  }
  // mxText.apply: STYLE_TEXT_OPACITY defaults to 100 (overwriting
  // STYLE_OPACITY). Skipping omitted keys leaked the previous cell.
  const textOpacity = Number(style.textOpacity);
  canvas.state.textOpacity = Number.isFinite(textOpacity) ? textOpacity : 100;
  // mxText.apply: spacing + spacingLeft/Right/Top/Bottom. Default spacing
  // is 2 so an omitted key still pads like configureCanvas.
  // mxCellRenderer.rotateLabelBounds (legacySpacing=true) skips
  // getSpacing when overflow is fill/width, so the HTML table is the
  // full cell. collectTextBlock LeftMargin must not keep that 2px
  // LibreOffice would pad as fo:padding-left (P&ID compressor T,
  // Removable Spool RS, Lean Mapping Kanban).
  const overflow = String(style.overflow || 'visible');
  const skipSpacing = overflow === 'fill' || overflow === 'width' ||
    (overflow === 'block' && String(style.blockSpacing) !== '1');
  if (skipSpacing) {
    canvas.state.spacingLeft = 0;
    canvas.state.spacingRight = 0;
    canvas.state.spacingTop = 0;
    canvas.state.spacingBottom = 0;
  } else {
    const spacing = parseInt(style.spacing != null ? style.spacing : 2, 10);
    const sp = Number.isFinite(spacing) ? spacing : 2;
    canvas.state.spacingLeft = (parseInt(style.spacingLeft, 10) || 0) + sp;
    canvas.state.spacingRight = (parseInt(style.spacingRight, 10) || 0) + sp;
    canvas.state.spacingTop = (parseInt(style.spacingTop, 10) || 0) + sp;
    canvas.state.spacingBottom = (parseInt(style.spacingBottom, 10) || 0) + sp;
  }
  // mxShape.getTextRotation: STYLE_HORIZONTAL != 1 adds verticalTextRotation.
  // LibreOffice _flushText ignores TextDirection writing-mode; a save bakes
  // TextDirection=1 into TxtAngle that librevenge:rotate paints.
  const horiz = style.horizontal;
  canvas.state.verticalText = horiz == 0 || horiz === '0' || horiz === false;
  canvas.state.wrap = String(style.whiteSpace || '') === 'wrap';
}

// mxGraphView.updateVertexLabelOffset: STYLE_LABEL_POSITION left/right
// and STYLE_VERTICAL_LABEL_POSITION top/bottom shift the mxText box by
// one cell. LibreOffice collectXFormData pins that Text child; keeping
// the box on the icon (GCP Vertex AI, UML Port) stacked the caption on
// the glyph. NestedStencil glyphs pass their own x/y and skip this.
function mxVertexLabelBox(style, x, y, w, h) {
  let ox = Number(x) || 0;
  let oy = Number(y) || 0;
  const width = Number(w) || 0;
  const height = Number(h) || 0;
  const hpos = String((style && style.labelPosition) || 'center');
  const vpos = String((style && style.verticalLabelPosition) || 'middle');
  if (hpos === 'left') ox -= width;
  else if (hpos === 'right') ox += width;
  if (vpos === 'top') oy -= height;
  else if (vpos === 'bottom') oy += height;
  return {x: ox, y: oy, w: width, h: height};
}

// mxCellRenderer.getLabelBounds: shape.getLabelBounds only when the
// caption is still on the vertex (center/middle). note2 boundedLbl and
// folder tabs inset that box; LibreOffice collectTextBlock maps it to
// TxtWidth / TxtPinY so the fold / tab is not painted over.
function mxVertexInnerLabelBox(shape, style, x, y, w, h) {
  const hpos = String((style && style.labelPosition) || 'center');
  const vpos = String((style && style.verticalLabelPosition) || 'middle');
  if (shape && typeof shape.getLabelBounds === 'function' &&
      hpos === 'center' && vpos === 'middle') {
    try {
      const inner = shape.getLabelBounds(new mxRectangle(x, y, w, h));
      if (inner && Number.isFinite(inner.width) && inner.width > 0 &&
          Number.isFinite(inner.height) && inner.height > 0) {
        // mxText.isPaintBoundsInverted when STYLE_HORIZONTAL=0.
        // Official mxCellRenderer swaps w/h, mxSwimlane.getLabelBounds
        // shrinks that height to startSize, and rotateLabelBounds -90
        // maps the top strip onto the left title bar paintVertexShape
        // fills. Capture skipped the invert, so leftover Text sat on
        // the top of Horizontal Container. tokens.txt has no
        // horizontal token; collectXFormData pins the Text child.
        const inverted = style &&
          (style.horizontal == 0 || style.horizontal === '0' ||
           style.horizontal === false);
        if (inverted && inner.height + 1e-6 < h &&
            inner.width + 1e-6 >= w) {
          return {x: inner.x, y: y, w: inner.height, h: h};
        }
        return {x: inner.x, y: inner.y, w: inner.width, h: inner.height};
      }
    } catch (_) {}
  }
  return mxVertexLabelBox(style, x, y, w, h);
}

// mxShape.getTextRotation uses getRotation() (STYLE_ROTATION). Vertical
// text is a separate TextDirection bake; adding verticalTextRotation
// here would double-rotate Cabinet 25x40. LibreOffice collects TxtAngle
// as m_txtxform->angle → librevenge:rotate.
function mxVertexLabelRotation(style) {
  const rot = Number(style && style.rotation);
  return Number.isFinite(rot) ? rot : 0;
}

function isNoLabelStyle(style) {
  return !!(style && (style.noLabel == 1 || style.noLabel === '1' ||
    style.noLabel === true));
}

function isCurvedTextStyle(style) {
  return !!(style && String(style.shape) === 'curvedText');
}

// CurvedTextShape.paintForeground: SVG textPath + textLength=pathLen.
// RecordingCanvas has no root/getBaseUrl, so official falls back to a
// centred c.text blob. tokens.txt has no text-on-path; leftover each
// glyph as a TxtAngle Char like SVG <textPath> (IBM KEY MGMT).
function curvedTextControlPoints(x, y, w, h, style, fontSize) {
  const startY = Number(style && style.arcStartY);
  const midYOffset = Number(style && style.arcMidY);
  const endY = Number(style && style.arcEndY);
  const sy0 = Number.isFinite(startY) ? startY : 25;
  const midOff = Number.isFinite(midYOffset) ? midYOffset : -25;
  const ey = Number.isFinite(endY) ? endY : 25;
  const inset = (Number(fontSize) || 11) / 2;
  const chordMidY = (sy0 + ey) / 2;
  const defaultMid = 25;
  const maxMid = Math.max(defaultMid, Math.min(chordMidY, h - chordMidY));
  const midClamped = Math.max(-maxMid, Math.min(maxMid, midOff));
  const naturalMidY = chordMidY + midClamped;
  const curveTopY = Math.min(sy0, ey, naturalMidY);
  const curveBottomY = Math.max(sy0, ey, naturalMidY);
  const curveNaturalHeight = curveBottomY - curveTopY;
  const valign = String((style && style.verticalAlign) || 'middle');
  const padding = inset;
  let yOffset;
  if (valign === 'top') yOffset = padding - curveTopY;
  else if (valign === 'bottom') yOffset = (h - padding) - curveBottomY;
  else yOffset = (h - curveNaturalHeight) / 2 - curveTopY;
  return {
    x0: x + inset,
    y0: y + sy0 + yOffset,
    x1: x + w / 2,
    y1: y + naturalMidY + yOffset,
    x2: x + (w - inset),
    y2: y + ey + yOffset,
    curveType: String((style && style.curveType) || 'round'),
  };
}

function curvedTextPathD(pts) {
  const {x0, y0, x1, y1, x2, y2, curveType} = pts;
  if (curveType === 'round') {
    const chord = Math.hypot(x2 - x0, y2 - y0);
    const chordMidX = (x0 + x2) / 2;
    const chordMidY = (y0 + y2) / 2;
    const sag = Math.hypot(x1 - chordMidX, y1 - chordMidY);
    if (sag < 0.5) {
      return `M ${number(x0)} ${number(y0)} L ${number(x2)} ${number(y2)}`;
    }
    const halfChord = chord / 2;
    const radius = (halfChord * halfChord) / (2 * sag) + sag / 2;
    const cdx = x2 - x0;
    const cdy = y2 - y0;
    const pdx = x1 - x0;
    const pdy = y1 - y0;
    const cross = cdx * pdy - cdy * pdx;
    const sweep = cross > 0 ? 0 : 1;
    const largeArc = sag > halfChord ? 1 : 0;
    return `M ${number(x0)} ${number(y0)} A ${number(radius)} ${number(radius)} 0 ${largeArc} ${sweep} ${number(x2)} ${number(y2)}`;
  }
  return `M ${number(x0)} ${number(y0)} Q ${number(x1)} ${number(y1)} ${number(x2)} ${number(y2)}`;
}

function paintCurvedTextGlyph(canvas, ch, x, y, rotation) {
  const fs = Number(canvas.state.fontSize) || 11;
  const scale = canvasMinScale(canvas);
  const userFs = scale > 0 ? fs / scale : fs;
  const bw = Math.max(userFs * 0.9, userFs * 0.62);
  const bh = userFs * 1.2;
  const rot = Number(rotation) || 0;
  const rad = rot * Math.PI / 180;
  const cx = x + Math.sin(rad) * (bh / 2);
  const cy = y - Math.cos(rad) * (bh / 2);
  canvas.text(
    cx - bw / 2, cy - bh / 2, bw, bh, ch, 'center', 'middle',
    false, null, null, null, rot,
  );
  return true;
}

function paintCurvedTextLeftover(canvas, x, y, w, h, label, style) {
  const text = String(label || '');
  if (!text) return false;
  applyTextStyle(canvas, style, {w, h, label: text});
  const fontSize = Number(canvas.state.fontSize) || 11;
  const d = curvedTextPathD(
    curvedTextControlPoints(x, y, w, h, style, fontSize),
  );
  const poly = svgPathPolyline(d);
  if (!(poly.total > 0)) return false;
  const chars = Array.from(text);
  const advs = chars.map((ch) => svgGlyphAdvance(ch, fontSize));
  const measured = advs.reduce((sum, adv) => sum + adv, 0);
  // textPath textLength=pathLen lengthAdjust=spacing.
  const extra = chars.length > 1 ? (poly.total - measured) / (chars.length - 1) : 0;
  let cursor = 0;
  let painted = false;
  for (let i = 0; i < chars.length; i++) {
    const ch = chars[i];
    const adv = advs[i];
    if (ch.trim()) {
      const at = svgPathAt(poly, cursor + adv / 2);
      if (at) painted = paintCurvedTextGlyph(canvas, ch, at.x, at.y, at.angle) || painted;
    }
    cursor += adv + extra;
  }
  return painted;
}

function paintTemplateLabel(entry, style, width, height, canvas, shape) {
  const htmlOn = isHtmlCellStyle(style);
  const label = cellLabel(entry && entry.value, htmlOn);
  if (!label) return;
  if (isCurvedTextStyle(style) &&
      paintCurvedTextLeftover(canvas, 0, 0, width, height, label, style)) {
    return;
  }
  if (isNoLabelStyle(style)) return;
  applyTextStyle(canvas, style, {w: width, h: height, label});
  const align = String((style && style.align) || 'center');
  const valign = String((style && style.verticalAlign) || 'middle');
  const box = mxVertexInnerLabelBox(shape, style, 0, 0, width, height);
  const rotation = mxVertexLabelRotation(style);
  if (htmlOn && paintHtmlStructuredLabel(
    canvas, box.x, box.y, box.w, box.h, label, align, valign, rotation,
  )) {
    return;
  }
  canvas.text(
    box.x, box.y, box.w, box.h, label, align, valign,
    undefined, htmlOn ? 'html' : undefined, undefined, undefined,
    rotation,
  );
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
  if (style.dashPattern) canvas.setDashPattern(style.dashPattern);
  if (style.linecap) canvas.setLineCap(style.linecap);
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
      if (typeof canvas.bindStyle === 'function') {
        canvas.bindStyle(shape.fill, shape.stroke);
      }
      if (style.dashed === '1') canvas.setDashed(true);
      if (style.dashPattern) canvas.setDashPattern(style.dashPattern);
      if (canvas.setFillColor) canvas.setFillColor(shape.fill);
      if (canvas.setStrokeColor) canvas.setStrokeColor(shape.stroke);
      if (canvas.setStrokeWidth) canvas.setStrokeWidth(shape.strokewidth);
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
  if (!kids.length) return;
  const alreadyPlaced = kids.some((child) =>
    (Number(child.geometry.x) || 0) !== 0 || (Number(child.geometry.y) || 0) !== 0);
  const horizontal = style.horizontalStack === '1';
  const startSize = Math.max(0, Number(style.startSize) || 0);
  const parentW = Math.max(0, Number(cell.geometry && cell.geometry.width) || 0);
  const parentH = Math.max(0, Number(cell.geometry && cell.geometry.height) || 0);
  const marginLeft = Number(style.marginLeft) || 0;
  const marginRight = Number(style.marginRight) || 0;
  const marginTop = Number(style.marginTop) || 0;
  const marginBottom = Number(style.marginBottom) || 0;
  const border = Number(style.stackBorder) || 0;
  const spacing = Number(style.stackSpacing) || 0;
  const footer = Math.max(0, Number(style.footerSize) || 0);
  // Official Graph.getLayout: stackLayout.fill = !transparentParent.
  // Vertical stacks set geo.width = fillValue (List items 80→140).
  // tokens.txt has no stackLayout; leftover is collectXFormData svg:width.
  const swimlane = String(style.shape || '') === 'swimlane';
  const swimlaneHorz = style.horizontal != '0';
  let fillValue = horizontal
    ? parentH - marginTop - marginBottom
    : parentW - marginLeft - marginRight;
  fillValue -= 2 * border;
  let x0 = border + marginLeft;
  let y0 = border + marginTop;
  if (swimlane && startSize > 0) {
    const start = swimlaneHorz
      ? Math.min(startSize, parentH)
      : Math.min(startSize, parentW);
    if (horizontal === swimlaneHorz) fillValue -= start;
    if (swimlaneHorz) y0 += start;
    else x0 += start;
  }
  const footerHorz = !swimlane || swimlaneHorz;
  if (footer > 0 && horizontal === footerHorz) fillValue -= footer;
  fillValue = Math.max(0, fillValue);
  let x = x0;
  let y = y0;
  for (let i = 0; i < kids.length; i++) {
    const geo = kids[i].geometry;
    if (!alreadyPlaced) {
      geo.x = x;
      geo.y = y;
    }
    if (horizontal) {
      geo.height = fillValue;
      if (!alreadyPlaced) {
        x += Math.max(0, Number(geo.width) || 0) + spacing;
      }
    } else {
      geo.width = fillValue;
      if (!alreadyPlaced) {
        y += Math.max(0, Number(geo.height) || 0) + spacing;
      }
    }
  }
}

function paintCellTree(cells, canvas, width, height) {
  let painted = false;
  const seen = new Set();
  const visit = (cell, parentX, parentY, parentW, parentH, inherited = {}) => {
    if (!cell || seen.has(cell)) return;
    seen.add(cell);
    if (cell.geometry) {
      const isEdge = !!(cell.edge || (typeof cell.style === 'string' && /(?:^|;)edge=1(?:;|$)/.test(cell.style)));
      const parsed = parseStyle(
        cell.style,
        isEdge ? namedStyles.defaultEdge : namedStyles.defaultVertex,
      );
      const resolved = resolveInheritedStyle(parsed, inherited);
      const cellStyle = resolved.style;
      applyStackLayout(cell, cellStyle);
      const origin = cellOrigin(
        cell.geometry, parentX, parentY, parentW, parentH, isEdge,
      );
      const x = origin.x;
      const y = origin.y;
      const cellWidth = Math.max(1, Number(cell.geometry.width) || parentW);
      const cellHeight = Math.max(1, Number(cell.geometry.height) || parentH);
      let result = null;
      if (isEdge) {
        if (paintEdge(cellStyle, cellWidth, cellHeight, canvas, x, y, cell.geometry)) {
          painted = true;
        }
      } else {
        result = paintRegistered(
          cellStyle, cellWidth, cellHeight, canvas, x, y,
          {fallbackRect: true, allowStencil: true, cell},
        );
        if (result) painted = true;
      }
      const htmlOn = isHtmlCellStyle(cellStyle);
      const label = cellLabel(cell.value, htmlOn, cell);
      if (label && isCurvedTextStyle(cellStyle) &&
          paintCurvedTextLeftover(
            canvas, x, y, cellWidth, cellHeight, label, cellStyle,
          )) {
        painted = true;
      } else if (label && !isNoLabelStyle(cellStyle)) {
        applyTextStyle(canvas, cellStyle, {w: cellWidth, h: cellHeight, label});
        const align = String(cellStyle.align || 'center');
        const valign = String(cellStyle.verticalAlign || 'middle');
        const box = mxVertexInnerLabelBox(
          result, cellStyle, x, y, cellWidth, cellHeight,
        );
        const rotation = mxVertexLabelRotation(cellStyle);
        if (!(htmlOn && paintHtmlStructuredLabel(
          canvas, box.x, box.y, box.w, box.h, label, align, valign, rotation,
        ))) {
          canvas.text(
            box.x, box.y, box.w, box.h, label, align, valign,
            undefined, htmlOn ? 'html' : undefined, undefined, undefined,
            rotation,
          );
        }
        painted = true;
      }
      const next = [...(cell.children || [])];
      for (const edge of cell.edges || []) {
        // insert() already parents the edge (SysML Package Diagram). Walking
        // .edges again leftover-baked <<import>> three times at each end.
        if (!next.includes(edge) && !edge.parent && !seen.has(edge)) {
          next.push(edge);
        }
      }
      for (const child of next) visit(child, x, y, cellWidth, cellHeight, resolved.inherited);
    } else {
      for (const child of cell.children || []) {
        visit(child, parentX, parentY, parentW, parentH, inherited);
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

// Sidebar fillColor/strokeColor on the <shape> so inherit `fill` / `stroke`
// tokens decode to that hex. applyStencilStyle would otherwise wash C4
// Person #083F75 into kStencilPrimary #DAE8FC that collectFill maps to
// svg:fill. Extra fillcolor ops stay siblings (radio dots, AWS glyphs).
function cssHexAttr(value) {
  if (value == null || isNoneColor(value)) return '';
  const token = String(value).trim();
  if (!token || token.toLowerCase() === 'default' || token.toLowerCase() === 'inherit') {
    return '';
  }
  if (token[0] === '#') return token;
  if (/^[0-9a-fA-F]{6}$/.test(token)) return `#${token}`;
  return '';
}

function pinCanvasInheritColors(canvas, entry, style) {
  const colors = entryPaintColors(entry, style);
  if (colors.fill) canvas.styleFill = colors.fill;
  if (colors.stroke) canvas.styleStroke = colors.stroke;
  return colors;
}

function entryPaintColors(entry, style) {
  let fill = style && style.fillColor;
  let stroke = style && style.strokeColor;
  const cell = Array.isArray(entry.cells) && entry.cells[0];
  if (cell && (fill == null || stroke == null)) {
    const parsed = parseStyle(
      cell.style,
      cell.edge ? namedStyles.defaultEdge : namedStyles.defaultVertex,
    );
    if (fill == null) fill = parsed.fillColor;
    if (stroke == null) stroke = parsed.strokeColor;
  }
  return {
    fill: cssHexAttr(stylePaintColor(fill, null)),
    stroke: cssHexAttr(stylePaintColor(stroke, null)),
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
    pinCanvasInheritColors(canvas, entry, style);
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
    // createVertexTemplateEntry's 4th arg is the cell value (P&ID TI/##,
    // AWS group titles, Basic Button). paintVertexShape never draws it;
    // LibreOffice's text collector only sees Text children.
    paintTemplateLabel(entry, style, width, height, canvas, shape);
  } else if (entry.kind === 'data' && entry.data) {
    ({width, height} = entrySize(entry));
    pinCanvasInheritColors(canvas, entry, style);
    const xml = decompressDrawio(entry.data);
    if (!xml || !paintCellTree(cellsFromMxGraphXml(xml), canvas, width, height)) {
      missVertex('data', entry);
      return null;
    }
  } else if (entry.kind === 'vertex-cells' && Array.isArray(entry.cells)) {
    ({width, height} = entrySize(entry));
    pinCanvasInheritColors(canvas, entry, style);
    if (!paintCellTree(entry.cells, canvas, width, height)) {
      missVertex('vertex-cells', entry);
      return null;
    }
  } else if (entry.kind === 'edge') {
    if (typeof entry.style !== 'string') { renderStats.noStyle++; return null; }
    style = parseStyle(entry.style, namedStyles.defaultEdge);
    pinCanvasInheritColors(canvas, entry, style);
    ({width, height} = entrySize(entry));
    const geometry = new Geometry(0, 0, width, height);
    geometry.setTerminalPoint({x: 0, y: height}, true);
    geometry.setTerminalPoint({x: width, y: 0}, false);
    geometry.relative = true;
    paintEdge(style, width, height, canvas, 0, 0, geometry);
    paintTemplateLabel(entry, style, width, height, canvas);
  } else if (entry.kind === 'edge-cells' && Array.isArray(entry.cells)) {
    ({width, height} = entrySize(entry));
    pinCanvasInheritColors(canvas, entry, style);
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
  return {
    width,
    height,
    body: connections + stencilLabelBoundsXml(shape, style, width, height) +
      `<foreground>${canvas.operations.join('')}</foreground>`,
    ...entryPaintColors(entry, style),
  };
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
      const fillAttr = rendered.fill ? ` fill="${xmlEscape(rendered.fill)}"` : '';
      const strokeAttr = rendered.stroke ? ` stroke="${xmlEscape(rendered.stroke)}"` : '';
      shapes.push(`<shape aspect="variable" h="${number(rendered.height)}" name="${xmlEscape(name)}" strokewidth="inherit" w="${number(rendered.width)}"${fillAttr}${strokeAttr}>${rendered.body}</shape>`);
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
