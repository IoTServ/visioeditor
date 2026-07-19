import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vsdx/vsdx.dart';

import '../render/pattern_fill.dart';
import '../render/vsdx_painter.dart';
import 'canvas_camera.dart';
import 'editor_controller.dart';
import '../l10n/editor_l10n.dart';

/// drawio's "Outline" panel: a thumbnail of the whole current page with a
/// rectangle showing the part currently visible on the main canvas. Click or
/// drag inside it to re-centre the canvas there.
class OutlinePanel extends StatelessWidget {
  const OutlinePanel({
    required this.controller,
    required this.camera,
    this.onClose,
    this.pxPerInch = 96.0,
    this.width = 220,
    this.height = 165,
    super.key,
  });

  final EditorController controller;
  final CanvasCamera camera;
  final VoidCallback? onClose;
  final double pxPerInch;
  final double width;
  final double height;

  /// Map a tap/drag at [local] (panel px) to a page-inch point and ask the
  /// canvas to centre there. Uses the same fit transform as the page painter.
  void _navigate(Offset local, VsdxPage page) {
    final contentW = page.widthInches * pxPerInch;
    final contentH = page.heightInches * pxPerInch;
    if (contentW <= 0 || contentH <= 0) return;
    final s = math.min(width / contentW, height / contentH);
    if (s <= 0) return;
    final dx = (width - contentW * s) / 2;
    final dy = (height - contentH * s) / 2;
    final cx = (local.dx - dx) / s;
    final cy = (local.dy - dy) / s;
    final px = cx / pxPerInch;
    final py = page.heightInches - cy / pxPerInch;
    controller.revealPagePoint(px, py);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final el = EditorL10n.of(context);
    return Material(
      elevation: 6,
      color: scheme.surface,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: AnimatedBuilder(
        // Page content only — camera-driven viewport frame is a separate cheap
        // layer so window resize / pan / zoom does not re-rasterize the page.
        animation: controller,
        builder: (context, _) {
          final page = controller.currentPage;
          final doc = controller.document;
          if (page == null || doc == null) {
            return SizedBox(
              width: width,
              height: height,
              child: Center(
                child: Text(
                  el.outline,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            );
          }
          return SizedBox(
            width: width,
            height: height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _OutlinePagePainter(
                      page: page,
                      theme: doc.theme,
                      images: doc.images,
                      pxPerInch: pxPerInch,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _OutlineViewportPainter(
                      page: page,
                      camera: camera,
                      pxPerInch: pxPerInch,
                      frameColor: scheme.primary,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => _navigate(d.localPosition, page),
                    onPanUpdate: (d) => _navigate(d.localPosition, page),
                  ),
                ),
                if (onClose != null)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      tooltip: el.hideOutline,
                      visualDensity: VisualDensity.compact,
                      onPressed: onClose,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Full-page thumbnail. Independent of [CanvasCamera] so resize frames stay cheap.
class _OutlinePagePainter extends CustomPainter {
  _OutlinePagePainter({
    required this.page,
    required this.theme,
    required this.images,
    required this.pxPerInch,
  });

  final VsdxPage page;
  final VsdxTheme theme;
  final ImageRegistry images;
  final double pxPerInch;

  @override
  void paint(Canvas canvas, Size size) {
    final contentW = page.widthInches * pxPerInch;
    final contentH = page.heightInches * pxPerInch;
    if (contentW <= 0 || contentH <= 0) return;
    final s = math.min(size.width / contentW, size.height / contentH);
    if (s <= 0) return;
    final dx = (size.width - contentW * s) / 2;
    final dy = (size.height - contentH * s) / 2;

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(s, s);
    VsdxPainter(
      page: page,
      theme: theme,
      images: images,
      patternBuilder: PatternFillBuilder.shared,
      pxPerInch: pxPerInch,
      backgroundColor: Colors.white,
    ).paint(canvas, Size(contentW, contentH));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _OutlinePagePainter old) =>
      !identical(old.page, page) ||
      !identical(old.theme, theme) ||
      !identical(old.images, images) ||
      old.pxPerInch != pxPerInch;
}

/// Visible-viewport rectangle only. Repaints when [camera] changes.
class _OutlineViewportPainter extends CustomPainter {
  _OutlineViewportPainter({
    required this.page,
    required this.camera,
    required this.pxPerInch,
    required this.frameColor,
  }) : super(repaint: camera);

  final VsdxPage page;
  final CanvasCamera camera;
  final double pxPerInch;
  final Color frameColor;

  @override
  void paint(Canvas canvas, Size size) {
    final contentW = page.widthInches * pxPerInch;
    final contentH = page.heightInches * pxPerInch;
    if (contentW <= 0 || contentH <= 0) return;
    final s = math.min(size.width / contentW, size.height / contentH);
    if (s <= 0) return;
    final dx = (size.width - contentW * s) / 2;
    final dy = (size.height - contentH * s) / 2;

    final vis = camera.visibleContentRect;
    if (vis == null) return;
    final clip = Rect.fromLTWH(dx, dy, contentW * s, contentH * s);
    final r = Rect.fromLTRB(
      dx + vis.left * s,
      dy + vis.top * s,
      dx + vis.right * s,
      dy + vis.bottom * s,
    ).intersect(clip);
    if (r.isEmpty) return;
    canvas
      ..drawRect(
        r,
        Paint()
          ..style = PaintingStyle.fill
          ..color = frameColor.withValues(alpha: 0.12),
      )
      ..drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = frameColor,
      );
  }

  @override
  bool shouldRepaint(covariant _OutlineViewportPainter old) =>
      !identical(old.page, page) ||
      old.pxPerInch != pxPerInch ||
      old.frameColor != frameColor;
}
