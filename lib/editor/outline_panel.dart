import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vsdx/vsdx.dart';

import '../render/vsdx_painter.dart';
import 'canvas_camera.dart';
import 'editor_controller.dart';

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
  /// canvas to centre there. Uses the same fit transform as [_OutlinePainter].
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
    return Material(
      elevation: 6,
      color: scheme.surface,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[controller, camera]),
        builder: (context, _) {
          final page = controller.currentPage;
          final doc = controller.document;
          if (page == null || doc == null) {
            return SizedBox(
              width: width,
              height: height,
              child: Center(
                child: Text(
                  'Outline',
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
                    painter: _OutlinePainter(
                      page: page,
                      theme: doc.theme,
                      images: doc.images,
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
                      tooltip: 'Hide outline',
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

class _OutlinePainter extends CustomPainter {
  _OutlinePainter({
    required this.page,
    required this.theme,
    required this.images,
    required this.camera,
    required this.pxPerInch,
    required this.frameColor,
  }) : super(repaint: camera);

  final VsdxPage page;
  final VsdxTheme theme;
  final ImageRegistry images;
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

    // Page thumbnail, drawn by the same painter used on the main canvas.
    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(s, s);
    VsdxPainter(
      page: page,
      theme: theme,
      images: images,
      pxPerInch: pxPerInch,
      backgroundColor: Colors.white,
    ).paint(canvas, Size(contentW, contentH));
    canvas.restore();

    // The part of the page currently on screen (clamped to the thumbnail).
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
  bool shouldRepaint(covariant _OutlinePainter old) =>
      !identical(old.page, page) || old.pxPerInch != pxPerInch;
}
