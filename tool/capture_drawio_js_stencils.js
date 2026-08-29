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

function mxStencilColor(color, shape) {
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
    this.rotTheta = 0;
    this.rotFlipH = false;
    this.rotFlipV = false;
    this.rotCx = 0;
    this.rotCy = 0;
    this.stack = [];
    this.operations = [];
    this.pathOpen = false;
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
    this._strokeWidthToken = 1;
    this._dashedToken = null;
    this._dashToken = null;
    this._lineCapToken = null;
    this._lineJoinToken = null;
    this._miterToken = null;
    this._alphaToken = 1;
    this._fillAlphaToken = 1;
    this._strokeAlphaToken = 1;
    this._shadowToken = '0';
    this.state = {
      fillColor: '#ffffff',
      strokeColor: '#000000',
      fontSize: 12,
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
      miterLimit: 4,
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
      this._reemitPaint();
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
      this.operations.push(`<fontsize size="${number(fontSize)}"/>`);
    }
    const p = this.map(x, y);
    const rot = (Number(rotation) || 0) + this.rotTheta;
    const htmlOn = format === 'html' || /<[a-zA-Z][\s\S]*>/.test(s);
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
    this.styleFill = fill;
    this.styleStroke = stroke;
    this._fillToken = 'fill';
    this._strokeToken = 'stroke';
    this._fontToken = null;
    this._fontFamilyToken = null;
    this._fontStyleToken = 0;
    this._fontBgToken = 'none';
    this._fontBorderToken = 'none';
    this._strokeWidthToken = 1;
    this._alphaToken = 1;
    this._fillAlphaToken = 1;
    this._strokeAlphaToken = 1;
    this.state.shadow = false;
    this._shadowToken = '0';
  }

  _emitPaint(tag, token) {
    this.finishPath();
    this.operations.push(`<${tag} color="${xmlEscape(token)}"/>`);
  }

  _gradientToken() {
    return [
      'grad',
      cssColorKey(this.state.fillColor),
      cssColorKey(this.state.gradientColor),
      this.state.gradientDir || 'south',
      this.state.gradientAlpha1,
      this.state.gradientAlpha2,
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
    this.operations.push(`<fillgradient ${attrs.join(' ')}/>`);
  }

  _reemitPaint() {
    if (this.state.gradientColor && !isNoneColor(this.state.gradientColor)) {
      const token = this._gradientToken();
      if (token !== this._fillToken) {
        this._fillToken = token;
        this._emitFillGradient();
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
  }

  _effectiveFillOpacity() {
    const a = Number(this.state.alpha);
    const f = Number(this.state.fillAlpha);
    return (Number.isFinite(a) ? a : 1) * (Number.isFinite(f) ? f : 1);
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
  setFillColor(value) {
    this.state.fillColor = isNoneColor(value) ? null : value;
    this.state.gradientColor = null;
    this.state.gradientDir = null;
    this.state.gradientAlpha1 = 1;
    this.state.gradientAlpha2 = 1;
    const token = fillPaintToken(
      value,
      this.styleFill,
      this._effectiveFillOpacity() < 1 - 1e-9,
    );
    if (token === this._fillToken) return;
    this._fillToken = token;
    this._emitPaint('fillcolor', token);
  }
  setStrokeColor(value) {
    this.state.strokeColor = isNoneColor(value) ? null : value;
    const token = paintToken(value, this.styleFill, this.styleStroke);
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
    if (isNoneColor(color2) || cssColorKey(color1) === cssColorKey(color2)) {
      this.setFillColor(color1);
      return;
    }
    this.state.fillColor = color1;
    this.state.gradientColor = color2;
    this.state.gradientDir = direction || 'south';
    this.state.gradientAlpha1 = alpha1 == null ? 1 : Number(alpha1);
    this.state.gradientAlpha2 = alpha2 == null ? 1 : Number(alpha2);
    const token = this._gradientToken();
    if (token === this._fillToken) return;
    this._fillToken = token;
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
    this.strokewidth = desc.attrs.strokewidth || 'inherit';
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
    }     else if (name === 'fillstroke' || name === 'fillstrokecolor') canvas.fillAndStroke();
    else if (name === 'fill') canvas.fill();
    else if (name === 'stroke') canvas.stroke();
    else if (name === 'fillcolor') {
      canvas.setFillColor(mxStencilColor(node.attrs.color, shape));
    } else if (name === 'strokecolor') {
      canvas.setStrokeColor(mxStencilColor(node.attrs.color, shape));
    } else if (name === 'fontcolor') {
      canvas.setFontColor(mxStencilColor(node.attrs.color, shape));
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
      const value = node.attrs.pattern;
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
  if (c.setStrokeColor) c.setStrokeColor(this.stroke);
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
function xmlUserObject(name) {
  const attrs = Object.create(null);
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
  };
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

function paintRegistered(style, width, height, canvas, x = 0, y = 0, opts = {}) {
  const name = style && style.shape;
  const fill = stylePaintColor(style.fillColor, '#ffffff');
  const stroke = stylePaintColor(style.strokeColor, '#000000');
  if (typeof canvas.bindStyle === 'function') canvas.bindStyle(fill, stroke);
  let ctor = name ? registry[name] : null;
  if (!ctor && opts.allowStencil && name) {
    const stencil = stencilMap[String(name).toLowerCase()];
    if (stencil) {
      const ghost = {style, fill, stroke, direction: style.direction || null};
      if (style.dashed === '1') canvas.setDashed(true);
      if (style.dashPattern) canvas.setDashPattern(style.dashPattern);
      if (style.linecap) canvas.setLineCap(style.linecap);
      if (style.linejoin) canvas.setLineJoin(style.linejoin);
      if (style.miterlimit) canvas.setMiterLimit(style.miterlimit);
      if (style.shadow == 1) canvas.setShadow(true);
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

// Graph.replacePlaceholders: %c4Name% → cell.getAttribute('c4Name').
// LibreOffice collectText only sees the frozen Char runs.
function replaceCellPlaceholders(cell, str) {
  if (!cellHasPlaceholders(cell) || cell.getAttribute('placeholder') != null) {
    return str;
  }
  return String(str || '').replace(
    /%(date\{.*\}|[^%\{\}"'=;]+)%/g,
    (token, name) => {
      if (name === 'label' || name === 'tooltip') return token;
      const val = cell.getAttribute(name);
      return val != null ? val : token;
    },
  );
}

function cellLabel(value, keepHtml = false, cell = null) {
  let source = cellDisplaySource(value);
  if (cell) source = replaceCellPlaceholders(cell, source);
  if (!source) return '';
  if (keepHtml && /<[a-zA-Z][\s\S]*>/.test(source)) return source;
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

function decodeHtmlEntities(value) {
  return String(value ?? '')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&#10;/g, '\n')
    .replace(/&#x([0-9a-f]+);/gi, (_, hex) => String.fromCharCode(parseInt(hex, 16)))
    .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n)))
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

function htmlAlignToken(raw) {
  const v = String(raw || '').trim().toLowerCase();
  if (v === 'center' || v === 'middle') return 'center';
  if (v === 'right' || v === 'end') return 'right';
  if (v === 'justify') return 'justify';
  if (v === 'left' || v === 'start') return 'left';
  return null;
}

// mxText HTML/CSS on <p>/<span>/<font>: color, size, weight, italic,
// text-decoration, font-family, block text-align. collectCharIX maps
// Style 0x4 to underline; collectParaIX HorzAlign is fo:text-align.
function applyHtmlCss(next, attrs, tag) {
  const color = htmlAttr(attrs, 'color') || htmlStyleProp(attrs, 'color');
  if (color) next.fontColor = color;
  const sizeToken = htmlStyleProp(attrs, 'font-size') || htmlAttr(attrs, 'size');
  if (sizeToken) {
    const size = parseFloat(sizeToken);
    if (Number.isFinite(size) && size > 0) next.fontSize = size;
  }
  const weight = htmlStyleProp(attrs, 'font-weight');
  if (weight && /^(bold|[7-9]00)$/i.test(weight)) next.fontStyle |= 1;
  const italic = htmlStyleProp(attrs, 'font-style');
  if (italic && /italic/i.test(italic)) next.fontStyle |= 2;
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
    htmlApplyMargins(next, attrs);
    next.paraStart = true;
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
  const fallback = Number(canvas.state.fontSize) || 12;
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
    && (Number(a.marginLeft) || 0) === (Number(b.marginLeft) || 0);
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

function htmlRunAttrs(run) {
  const attrs = [`str="${xmlEscape(run.str)}"`];
  attrs.push(`fontstyle="${Number(run.fontStyle) || 0}"`);
  const size = Number(run.fontSize);
  if (Number.isFinite(size) && size > 0) attrs.push(`fontsize="${number(size)}"`);
  if (run.fontColor) attrs.push(`fontcolor="${xmlEscape(String(run.fontColor))}"`);
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
  return attrs.join(' ');
}

// mxText html=1: <b>/<i>/<font>/<sup>/<sub> and CSS text-decoration become
// Char Style / Color / Size / Pos that collectCharIX maps to fo:font-weight /
// fo:color / fo:font-size / style:text-underline-type / style:text-position.
function parseHtmlLabel(html, base) {
  const runs = [];
  const stack = [cloneHtmlStyle(base)];
  const current = () => stack[stack.length - 1];
  const pushRun = (text) => {
    if (!text) return;
    const style = current();
    const emit = cloneHtmlStyle(style);
    if (!style.paraStart) emit.marginTop = 0;
    if (text === '\n') {
      emit.marginTop = 0;
      emit.marginRight = 0;
      emit.marginBottom = 0;
      emit.marginLeft = 0;
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
      if (block && runs.length) {
        const mb = Number(current().marginBottom) || 0;
        if (Math.abs(mb) > 1e-9) runs[runs.length - 1].marginBottom = mb;
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
    applyHtmlCss(next, attrs, tag);
    stack.push(next);
  }
  return runs;
}

// mxText html=1 tables (P&ID TI/##, Electrical thermistor \temp\, Mockup
// Step Bar) are 100%×100% grids. Flattening them to one collectTextBlock
// box centred the caption on the glyph; LibreOffice must pin each cell
// like the HTML table. `height=0%` with text is a content band (browser
// min-content), not a zero-height skip.
function htmlHasVisibleText(html) {
  return !!cellLabel(html, false).trim();
}

function htmlTdFragment(attrs, inner) {
  const body = inner || '';
  const style = htmlAttr(attrs, 'style');
  if (style) return `<span style="${style}">${body}</span>`;
  return body;
}

function htmlTableRowSpecs(html) {
  const source = String(html || '');
  const tableMatch = /<table\b[^>]*>([\s\S]*)<\/table>/i.exec(source);
  if (!tableMatch) return null;
  const outside = source.replace(tableMatch[0], '');
  if (cellLabel(outside, false).trim()) return null;
  const rows = [];
  const trRe = /<tr\b([^>]*)>([\s\S]*?)<\/tr>/gi;
  let match;
  while ((match = trRe.exec(tableMatch[1]))) {
    const inner = match[2] || '';
    const tds = [];
    const tdRe = /<td\b([^>/]*)(?:\/>|>([\s\S]*?)<\/td>)/gi;
    let td;
    while ((td = tdRe.exec(inner))) {
      tds.push({attrs: td[1] || '', inner: td[2] || ''});
    }
    const trAttrs = match[1] || '';
    const cells = (tds.length ? tds : [{attrs: '', inner}]).map((cell) => ({
      widthToken: htmlAttr(cell.attrs, 'width') || htmlStyleProp(cell.attrs, 'width'),
      align: htmlAttr(cell.attrs, 'align') || htmlStyleProp(cell.attrs, 'text-align'),
      valign: htmlAttr(cell.attrs, 'valign') || htmlStyleProp(cell.attrs, 'vertical-align'),
      html: htmlTdFragment(cell.attrs, cell.inner),
    }));
    const firstAttrs = tds.length ? tds[0].attrs : '';
    const heightToken = htmlAttr(trAttrs, 'height')
      || htmlStyleProp(trAttrs, 'height')
      || htmlAttr(firstAttrs, 'height')
      || htmlStyleProp(firstAttrs, 'height');
    rows.push({heightToken, cells});
  }
  if (rows.length < 1) return null;
  const multiCol = rows.some((row) => row.cells.length > 1);
  if (!multiCol && rows.length < 2) return null;
  return rows;
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
  const fontSize = canvas && canvas.state ? canvas.state.fontSize : 12;
  const heights = rows.map((row) => htmlRowHeightPx(
    row.heightToken, h, htmlRowHasText(row), fontSize,
  ));
  const known = heights.reduce((sum, v) => sum + (v || 0), 0);
  const missing = heights.filter((v) => v == null).length;
  const auto = missing > 0 ? Math.max(0, h - known) / missing : 0;
  let top = y;
  let painted = false;
  for (let i = 0; i < rows.length; i++) {
    const rh = heights[i] == null ? auto : heights[i];
    const row = rows[i];
    if (rh > 0 && htmlRowHasText(row)) {
      const widths = htmlColWidths(row.cells, w);
      let left = x;
      for (let j = 0; j < row.cells.length; j++) {
        const cell = row.cells[j];
        const cw = widths[j];
        if (cw > 0 && htmlHasVisibleText(cell.html)) {
          canvas.text(
            left, top, cw, rh, cellLabel(cell.html, true),
            cell.align || defaultAlign,
            cell.valign || defaultValign || 'middle',
            undefined, 'html', undefined, undefined, rotation,
          );
          painted = true;
        }
        left += cw;
      }
    }
    top += rh;
  }
  return painted || rows.every((row) => !htmlRowHasText(row));
}

function isHtmlCellStyle(style) {
  return !!(style && (style.html == 1 || style.html === '1'));
}

function applyTextStyle(canvas, style) {
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
  const size = Number(style.fontSize);
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
  const spacing = parseInt(style.spacing != null ? style.spacing : 2, 10);
  const sp = Number.isFinite(spacing) ? spacing : 2;
  canvas.state.spacingLeft = (parseInt(style.spacingLeft, 10) || 0) + sp;
  canvas.state.spacingRight = (parseInt(style.spacingRight, 10) || 0) + sp;
  canvas.state.spacingTop = (parseInt(style.spacingTop, 10) || 0) + sp;
  canvas.state.spacingBottom = (parseInt(style.spacingBottom, 10) || 0) + sp;
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

function paintTemplateLabel(entry, style, width, height, canvas, shape) {
  const htmlOn = isHtmlCellStyle(style);
  const label = cellLabel(entry && entry.value, htmlOn);
  if (!label) return;
  applyTextStyle(canvas, style);
  const align = String((style && style.align) || 'center');
  const valign = String((style && style.verticalAlign) || 'middle');
  const box = mxVertexInnerLabelBox(shape, style, 0, 0, width, height);
  const rotation = mxVertexLabelRotation(style);
  if (htmlOn && paintHtmlTableLabel(
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
  const visit = (cell, parentX, parentY, parentW, parentH, inherited = {}) => {
    if (!cell) return;
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
          {fallbackRect: true, allowStencil: true},
        );
        if (result) painted = true;
      }
      const htmlOn = isHtmlCellStyle(cellStyle);
      const label = cellLabel(cell.value, htmlOn, cell);
      if (label) {
        applyTextStyle(canvas, cellStyle);
        const align = String(cellStyle.align || 'center');
        const valign = String(cellStyle.verticalAlign || 'middle');
        const box = mxVertexInnerLabelBox(
          result, cellStyle, x, y, cellWidth, cellHeight,
        );
        const rotation = mxVertexLabelRotation(cellStyle);
        if (!(htmlOn && paintHtmlTableLabel(
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
        if (!next.includes(edge)) next.push(edge);
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
    paintTemplateLabel(entry, style, width, height, canvas);
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
  return {
    width,
    height,
    body: connections + `<foreground>${canvas.operations.join('')}</foreground>`,
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
