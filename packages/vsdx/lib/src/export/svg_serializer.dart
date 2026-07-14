/// Pure-Dart `.vsdx` → SVG serializer (M7-01).
///
/// The serializer is intentionally Flutter-free so it can run on the
/// command line, in a server, or inside a Dart isolate. The output is a
/// self-contained `<svg>` document per page (or one merged document) — no
/// JavaScript, no external font references, just inline geometry and text.
///
/// Coordinate system: SVG's Y axis points *down*, just like Flutter's.
/// Visio's Y axis points up, so we apply a top-of-page flip per page.
library;

import 'dart:convert';
import 'dart:math' as math;

import '../model/document.dart';
import '../model/fill.dart';
import '../model/geometry.dart';
import '../model/image.dart';
import '../model/line.dart';
import '../model/page.dart';
import '../model/rich_text.dart';
import '../model/shape.dart';
import '../model/theme.dart';
import '../utils/color.dart';

class VsdxToSvgSerializer {
  VsdxToSvgSerializer({
    this.pxPerInch = 96.0,
    this.includeXmlHeader = true,
    this.embedImages = true,
  });

  final double pxPerInch;
  final bool includeXmlHeader;

  /// When `true` (default) the serializer emits `<image>` tags with
  /// `data:` URIs for every supported raster. Set to `false` to skip
  /// images entirely (e.g. for diff-friendly outputs).
  final bool embedImages;

  /// Current image registry, swapped in by [serializePage] / [serializeDocument].
  ImageRegistry _images = ImageRegistry.empty;

  /// Serialize the entire document into a single multi-page SVG with each
  /// page wrapped in a `<g class="page-N">` translated downward. Use
  /// [serializePage] when only one page is needed.
  String serializeDocument(VsdxDocument doc) {
    _images = doc.images;
    final buf = StringBuffer();
    if (includeXmlHeader) buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    final totalH = doc.pages.fold<double>(
      0,
      (acc, p) => acc + p.heightInches * pxPerInch + 24,
    );
    final maxW = doc.pages.fold<double>(
      0,
      (acc, p) => math.max(acc, p.widthInches * pxPerInch),
    );
    buf.writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" '
      'version="1.1" '
      'width="${_n(maxW)}" '
      'height="${_n(totalH)}" '
      'viewBox="0 0 ${_n(maxW)} ${_n(totalH)}">',
    );
    buf.writeln('  <title>${_esc(doc.title ?? 'Visio document')}</title>');
    var offsetY = 0.0;
    for (var i = 0; i < doc.pages.length; i++) {
      final p = doc.pages[i];
      buf.writeln(
          '  <g class="page page-${i + 1}" transform="translate(0,${_n(offsetY)})">');
      _writePageBody(buf, p, doc.theme, indent: '    ');
      buf.writeln('  </g>');
      offsetY += p.heightInches * pxPerInch + 24;
    }
    buf.writeln('</svg>');
    return buf.toString();
  }

  /// Serialize a single page.
  String serializePage(
    VsdxPage page, {
    VsdxTheme theme = VsdxTheme.empty,
    ImageRegistry images = ImageRegistry.empty,
  }) {
    _images = images;
    final buf = StringBuffer();
    if (includeXmlHeader) buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    final w = page.widthInches * pxPerInch;
    final h = page.heightInches * pxPerInch;
    buf.writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" '
      'version="1.1" '
      'width="${_n(w)}" '
      'height="${_n(h)}" '
      'viewBox="0 0 ${_n(w)} ${_n(h)}">',
    );
    _writePageBody(buf, page, theme, indent: '  ');
    buf.writeln('</svg>');
    return buf.toString();
  }

  void _writePageBody(
    StringBuffer buf,
    VsdxPage page,
    VsdxTheme theme, {
    required String indent,
  }) {
    final h = page.heightInches * pxPerInch;
    // page background
    buf.writeln('$indent<rect x="0" y="0" '
        'width="${_n(page.widthInches * pxPerInch)}" '
        'height="${_n(h)}" fill="#ffffff"/>');
    // Visio→SVG: translate(0, height) then scale(px, -px)
    buf.writeln(
      '$indent<g transform="translate(0 ${_n(h)}) '
      'scale(${_n(pxPerInch)} ${_n(-pxPerInch)})">',
    );
    final visible = page.visibleLayerIds;
    for (final shape in page.shapes) {
      _writeShape(buf, shape, theme, page, visible, indent: '$indent  ');
    }
    buf.writeln('$indent</g>');
  }

  void _writeShape(
    StringBuffer buf,
    VsdxShape shape,
    VsdxTheme theme,
    VsdxPage page,
    Set<int> visibleLayers, {
    required String indent,
  }) {
    if (page.layers.isNotEmpty &&
        shape.layerMemberIds.isNotEmpty &&
        !shape.isOnAnyLayer(visibleLayers)) {
      return;
    }
    final transforms = <String>[];
    transforms.add('translate(${_n(shape.pinX)} ${_n(shape.pinY)})');
    if (shape.angleRad != 0) {
      transforms.add('rotate(${_n(shape.angleRad * 180 / math.pi)})');
    }
    if (shape.flipX || shape.flipY) {
      transforms.add(
        'scale(${shape.flipX ? -1 : 1} ${shape.flipY ? -1 : 1})',
      );
    }
    transforms.add(
      'translate(${_n(-shape.effectiveLocPinX)} '
      '${_n(-shape.effectiveLocPinY)})',
    );
    buf.writeln('$indent<g transform="${transforms.join(' ')}">');

    if (shape.hasImage) {
      _writeImage(buf, shape, indent: '$indent  ');
    } else {
      for (final geom in shape.geometries) {
        if (geom.noShow) continue;
        final d = _geometryToD(geom, shape.width, shape.height);
        if (d.isEmpty) continue;
        final fillAttr = !geom.noFill
            ? _fillAttr(shape.fill, theme)
            : 'fill="none"';
        final strokeAttr = !geom.noLine
            ? _strokeAttr(shape.line, theme)
            : 'stroke="none"';
        buf.writeln(
          '$indent  <path d="$d" $fillAttr $strokeAttr/>',
        );
      }
    }

    if (!shape.richText.isEmpty || (shape.text?.isNotEmpty ?? false)) {
      _writeText(buf, shape, theme, indent: '$indent  ');
    }

    for (final child in shape.children) {
      _writeShape(buf, child, theme, page, visibleLayers, indent: '$indent  ');
    }
    buf.writeln('$indent</g>');
  }

  String _geometryToD(VsdxGeometry g, double w, double h) {
    final out = StringBuffer();
    double cx = 0, cy = 0;
    var started = false;
    void m(double x, double y) {
      out.write('M ${_n(x)} ${_n(y)} ');
      cx = x;
      cy = y;
      started = true;
    }

    void l(double x, double y) {
      if (!started) m(0, 0);
      out.write('L ${_n(x)} ${_n(y)} ');
      cx = x;
      cy = y;
    }

    for (final cmd in g.commands) {
      switch (cmd) {
        case MoveTo(:final x, :final y):
          m(x, y);
        case RelMoveTo(:final fx, :final fy):
          m(fx * w, fy * h);
        case LineTo(:final x, :final y):
          l(x, y);
        case RelLineTo(:final fx, :final fy):
          l(fx * w, fy * h);
        case CubBezTo(
            :final x,
            :final y,
            :final x1,
            :final y1,
            :final x2,
            :final y2,
          ):
          if (!started) m(0, 0);
          out.write('C ${_n(x1)} ${_n(y1)} ${_n(x2)} ${_n(y2)} '
              '${_n(x)} ${_n(y)} ');
          cx = x;
          cy = y;
        case RelCubBezTo(
            :final fx,
            :final fy,
            :final fx1,
            :final fy1,
            :final fx2,
            :final fy2,
          ):
          if (!started) m(0, 0);
          out.write('C ${_n(fx1 * w)} ${_n(fy1 * h)} '
              '${_n(fx2 * w)} ${_n(fy2 * h)} ${_n(fx * w)} ${_n(fy * h)} ');
          cx = fx * w;
          cy = fy * h;
        case QuadBezTo(:final x, :final y, :final x1, :final y1):
          if (!started) m(0, 0);
          out.write('Q ${_n(x1)} ${_n(y1)} ${_n(x)} ${_n(y)} ');
          cx = x;
          cy = y;
        case RelQuadBezTo(:final fx, :final fy, :final fx1, :final fy1):
          if (!started) m(0, 0);
          out.write('Q ${_n(fx1 * w)} ${_n(fy1 * h)} '
              '${_n(fx * w)} ${_n(fy * h)} ');
          cx = fx * w;
          cy = fy * h;
        case ArcTo(:final x, :final y, :final bow):
          if (bow == 0) {
            l(x, y);
          } else {
            final dx = x - cx;
            final dy = y - cy;
            final chord = math.sqrt(dx * dx + dy * dy);
            final r = (chord * chord + 4 * bow * bow) / (8 * bow.abs());
            final large = (4 * bow.abs() > chord) ? 1 : 0;
            final sweep = bow < 0 ? 1 : 0;
            out.write(
                'A ${_n(r)} ${_n(r)} 0 $large $sweep ${_n(x)} ${_n(y)} ');
            cx = x;
            cy = y;
          }
        case RelArcTo(:final fx, :final fy, :final fbow):
          final x = fx * w;
          final y = fy * h;
          final bow = fbow * (w + h) / 2;
          if (bow == 0) {
            l(x, y);
          } else {
            final dx = x - cx;
            final dy = y - cy;
            final chord = math.sqrt(dx * dx + dy * dy);
            final r = (chord * chord + 4 * bow * bow) / (8 * bow.abs());
            final large = (4 * bow.abs() > chord) ? 1 : 0;
            final sweep = bow < 0 ? 1 : 0;
            out.write(
                'A ${_n(r)} ${_n(r)} 0 $large $sweep ${_n(x)} ${_n(y)} ');
            cx = x;
            cy = y;
          }
        case EllipticalArcTo(
            :final x,
            :final y,
            :final controlX,
            :final controlY,
          ):
          final bx = 2 * controlX - 0.5 * cx - 0.5 * x;
          final by = 2 * controlY - 0.5 * cy - 0.5 * y;
          out.write('Q ${_n(bx)} ${_n(by)} ${_n(x)} ${_n(y)} ');
          cx = x;
          cy = y;
        case RelEllipticalArcTo(
            :final fx,
            :final fy,
            :final fcx,
            :final fcy,
          ):
          final ex = fx * w;
          final ey = fy * h;
          final bx = 2 * (fcx * w) - 0.5 * cx - 0.5 * ex;
          final by = 2 * (fcy * h) - 0.5 * cy - 0.5 * ey;
          out.write('Q ${_n(bx)} ${_n(by)} ${_n(ex)} ${_n(ey)} ');
          cx = ex;
          cy = ey;
        case EllipseCmd(
            :final cx,
            :final cy,
            :final aX,
            :final aY,
            :final bX,
            :final bY,
          ):
          final rx = math.sqrt((aX - cx) * (aX - cx) + (aY - cy) * (aY - cy));
          final ry = math.sqrt((bX - cx) * (bX - cx) + (bY - cy) * (bY - cy));
          if (rx > 0 && ry > 0) {
            // SVG has no `ellipse` inside `d`; approximate with two arcs.
            out
              ..write('M ${_n(cx - rx)} ${_n(cy)} ')
              ..write('a ${_n(rx)} ${_n(ry)} 0 1 0 ${_n(rx * 2)} 0 ')
              ..write('a ${_n(rx)} ${_n(ry)} 0 1 0 ${_n(-rx * 2)} 0 ');
          }
        case PolylineTo(:final x, :final y, :final vertices, :final relative):
          final sx = relative ? w : 1.0;
          final sy = relative ? h : 1.0;
          for (final v in vertices) {
            l(v.x * sx, v.y * sy);
          }
          l(x * sx, y * sy);
        case InfiniteLineCmd(:final x, :final y, :final a, :final b, :final relative):
          final sx = relative ? w : 1.0;
          final sy = relative ? h : 1.0;
          final px = x * sx, py = y * sy, qx = a * sx, qy = b * sy;
          final dx = qx - px;
          final dy = qy - py;
          final len = math.sqrt(dx * dx + dy * dy);
          if (len == 0) continue;
          final ux = dx / len, uy = dy / len;
          final reach = 100 * math.sqrt(w * w + h * h);
          m(px - ux * reach, py - uy * reach);
          l(px + ux * reach, py + uy * reach);
        case SplineStart(:final x, :final y, :final relative):
          final px = relative ? x * w : x;
          final py = relative ? y * h : y;
          if (!started) {
            m(px, py);
          } else {
            l(px, py);
          }
        case SplineKnot(:final x, :final y, :final relative):
          l(relative ? x * w : x, relative ? y * h : y);
        case NurbsTo(
            :final x,
            :final y,
            :final controlPoints,
            :final relative,
          ):
          final sx = relative ? w : 1.0;
          final sy = relative ? h : 1.0;
          for (final p in controlPoints) {
            l(p.x * sx, p.y * sy);
          }
          l(x * sx, y * sy);
      }
    }
    return out.toString().trim();
  }

  String _fillAttr(VsdxFill fill, VsdxTheme theme) {
    if (!fill.hasFill) return 'fill="none"';
    final c = _resolveColor(fill.foreground, fill.themeForegroundIndex, theme);
    final alpha = (1 - fill.foregroundTransparency).clamp(0.0, 1.0);
    final hex = c == null ? '#ffffff' : _hex(c);
    return 'fill="$hex" fill-opacity="${_n(alpha)}"';
  }

  String _strokeAttr(VsdxLine line, VsdxTheme theme) {
    if (!line.hasLine) return 'stroke="none"';
    final c = _resolveColor(line.color, line.themeColorIndex, theme);
    final alpha = (1 - line.transparency).clamp(0.0, 1.0);
    final hex = c == null ? '#000000' : _hex(c);
    final dash = _dashAttr(line.pattern);
    // NB: no `fill` here — the caller always emits a `fill` attribute (a colour
    // or `fill="none"`) alongside this, so repeating it would produce an
    // invalid element with a duplicate `fill` attribute.
    //
    // The stroke width is in inches (Visio's internal unit) and is deliberately
    // left to scale with the page transform (`scale(px,-px)`), so a 0.01" line
    // renders as ~1px. We must NOT use `vector-effect="non-scaling-stroke"`
    // here: that would treat 0.01 as viewport pixels, collapsing stroke-only
    // shapes (connectors) to an invisible hairline.
    final weight = line.weightInches > 0 ? line.weightInches : 0.01;
    return 'stroke="$hex" stroke-opacity="${_n(alpha)}" '
        'stroke-width="${_n(weight)}" '
        '${dash.isEmpty ? '' : 'stroke-dasharray="$dash"'}';
  }

  String _dashAttr(int linePattern) {
    if (linePattern <= 1) return '';
    return switch (linePattern) {
      2 => '0.10 0.05',
      3 => '0.02 0.04',
      4 => '0.12 0.05 0.02 0.05',
      5 => '0.12 0.05 0.02 0.05 0.02 0.05',
      9 => '0.20 0.05',
      _ => '0.08 0.04',
    };
  }

  void _writeImage(
    StringBuffer buf,
    VsdxShape shape, {
    required String indent,
  }) {
    final src = _images.findByPart(shape.imagePartName ?? '');
    if (!embedImages || src == null || !src.isFlutterDecodable) {
      // Fall back to a placeholder rectangle.
      buf.writeln(
        '$indent<rect x="0" y="0" width="${_n(shape.width)}" '
        'height="${_n(shape.height)}" fill="#f2f2f2" '
        'stroke="#b0b0b0" stroke-width="0.01"/>',
      );
      return;
    }
    final href =
        'data:${src.mimeType.isEmpty ? "image/png" : src.mimeType};base64,'
        '${base64Encode(src.bytes)}';
    // SVG <image> with preserveAspectRatio="none" stretches to fit; Visio
    // already stores the picture at the shape's bounds.
    buf.writeln(
      '$indent<g transform="translate(0 ${_n(shape.height)}) scale(1 -1)">'
      '<image href="$href" x="0" y="0" '
      'width="${_n(shape.width)}" height="${_n(shape.height)}" '
      'preserveAspectRatio="none"/></g>',
    );
  }

  void _writeText(
    StringBuffer buf,
    VsdxShape shape,
    VsdxTheme theme, {
    required String indent,
  }) {
    final block = shape.richText.textBlock;
    // Match libvisio: HideText suppresses the label entirely.
    if (block.hideText) return;
    // The text block is pinned by its local pin (TxtLocPin); its centre — where
    // we anchor the middle-aligned label — is pin - locPin + size/2.
    final tw = block.widthInches ?? shape.width;
    final th = block.heightInches ?? shape.height;
    final lpx = block.locPinXInches ?? tw / 2;
    final lpy = block.locPinYInches ?? th / 2;
    final cx = (block.pinXInches ?? shape.width / 2) - lpx + tw / 2;
    final cy = (block.pinYInches ?? shape.height / 2) - lpy + th / 2;
    // libvisio emits fo:background-color when TextBkgnd is filled.
    if (block.backgroundColor != null) {
      final left = cx - tw / 2;
      final bottom = cy - th / 2;
      buf.writeln(
        '$indent<rect x="${_n(left)}" y="${_n(bottom)}" '
        'width="${_n(tw)}" height="${_n(th)}" '
        'fill="${_hex(block.backgroundColor!)}" stroke="none"/>',
      );
    }
    final run = shape.richText.runs.isNotEmpty
        ? shape.richText.runs.first
        : VsdxTextRun(text: shape.text ?? shape.name);
    final color =
        _resolveColor(run.charStyle.color, run.charStyle.themeColorIndex, theme) ??
            const VsdxColor(0xFF222222);
    final fs = math.max(run.charStyle.fontSizeInches, 0.04);
    final fontFamily = run.charStyle.fontFamily ?? 'sans-serif';
    final weight = run.charStyle.style.bold ? 'bold' : 'normal';
    final italic = run.charStyle.style.italic ? 'italic' : 'normal';
    final raw = shape.richText.isEmpty
        ? (shape.text ?? shape.name)
        : shape.richText.plainText;
    // SVG <text> ignores literal newlines, so lay out each line as its own
    // <tspan>, vertically centred about the text pin (matches Visio/the app).
    final lines = raw.split('\n');
    final lineHeight = fs * 1.2;
    final firstDy = -(lines.length - 1) / 2 * lineHeight;
    final tspans = StringBuffer();
    for (var i = 0; i < lines.length; i++) {
      tspans.write('<tspan x="0" y="${_n(firstDy + i * lineHeight)}">'
          '${_esc(lines[i])}</tspan>');
    }
    // Flip Y for the text so glyphs read upright.
    buf.writeln(
      '$indent<g transform="translate(${_n(cx)} ${_n(cy)}) scale(1 -1)">'
      '<text text-anchor="middle" dominant-baseline="middle" '
      'font-family="${_esc(fontFamily)}" font-size="${_n(fs)}" '
      'font-weight="$weight" font-style="$italic" '
      'fill="${_hex(color)}">$tspans</text></g>',
    );
  }

  VsdxColor? _resolveColor(VsdxColor? raw, int? themeIdx, VsdxTheme theme) {
    if (raw != null) return raw;
    if (themeIdx == null) return null;
    return theme.resolve(themeIdx);
  }

  String _hex(VsdxColor c) {
    return '#${((c.red << 16) | (c.green << 8) | c.blue).toRadixString(16).padLeft(6, '0')}';
  }

  String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  String _n(double v) {
    if (v.isNaN || v.isInfinite) return '0';
    if (v == v.truncateToDouble()) return v.toStringAsFixed(0);
    return v
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}
