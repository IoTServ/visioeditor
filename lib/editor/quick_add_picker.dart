import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/editor_l10n.dart';
import '../render/path_builder.dart';
import 'stencils.dart';

/// Stencils offered in the hover-arrow quick-add menu (EdrawMax / draw.io).
///
/// Everyday General + Flowchart shapes; skips bulky composites (tables,
/// containers, free text) that are awkward as one-click neighbours.
List<Stencil> quickAddStencils() {
  const skip = <String>{
    'Text',
    'Table',
    'Table 2×2',
    'List',
    'Container',
    'Horizontal Container',
  };
  final seen = <String>{};
  final out = <Stencil>[];
  for (final g in kStencilGroups) {
    if (g.name != 'General' && g.name != 'Flowchart') continue;
    for (final s in g.stencils) {
      if (skip.contains(s.name) || !seen.add(s.name)) continue;
      out.add(s);
      if (out.length >= 35) return out;
    }
  }
  return out;
}

/// Floating shape grid anchored near a hover-connect arrow.
///
/// Choosing a stencil calls [onSelect]; [onDuplicate] clones the source shape
/// (Shift-click / "same shape" shortcut). Tap outside dismisses via [onDismiss].
class QuickAddPicker extends StatelessWidget {
  const QuickAddPicker({
    required this.anchorGlobal,
    required this.onSelect,
    required this.onDuplicate,
    required this.onDismiss,
    super.key,
  });

  /// Screen position of the directional arrow that opened the menu.
  final Offset anchorGlobal;
  final ValueChanged<Stencil> onSelect;
  final VoidCallback onDuplicate;
  final VoidCallback onDismiss;

  static const double _panelWidth = 292;
  static const double _cell = 44;
  static const int _cols = 6;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scheme = Theme.of(context).colorScheme;
    final el = EditorL10n.of(context);
    final stencils = quickAddStencils();

    // Prefer opening beside the arrow; clamp so the panel stays on-screen.
    final panelWidth = math.min(_panelWidth, media.size.width - 16);
    var left = anchorGlobal.dx + 18;
    var top = anchorGlobal.dy - 40;
    final maxLeft = media.size.width - panelWidth - 8;
    final estimatedH =
        48.0 + ((stencils.length + _cols - 1) ~/ _cols) * (_cell + 4) + 16;
    final maxTop = media.size.height - estimatedH - 8;
    if (left > maxLeft) left = anchorGlobal.dx - panelWidth - 18;
    left = left.clamp(8.0, math.max(8.0, maxLeft));
    top = top.clamp(8.0, math.max(8.0, maxTop));

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: const ColoredBox(color: Color(0x00000000)),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          child: Material(
            elevation: 10,
            borderRadius: BorderRadius.circular(10),
            color: scheme.surface,
            shadowColor: Colors.black54,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: panelWidth),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InkWell(
                      onTap: onDuplicate,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.copy_outlined,
                                size: 16, color: scheme.primary),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                el.duplicate,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Divider(height: 1, color: scheme.outlineVariant),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final s in stencils)
                          _QuickAddCell(
                            stencil: s,
                            size: _cell,
                            onTap: () => onSelect(s),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _QuickAddCell extends StatefulWidget {
  const _QuickAddCell({
    required this.stencil,
    required this.size,
    required this.onTap,
  });

  final Stencil stencil;
  final double size;
  final VoidCallback onTap;

  @override
  State<_QuickAddCell> createState() => _QuickAddCellState();
}

class _QuickAddCellState extends State<_QuickAddCell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final el = EditorL10n.of(context);
    return Tooltip(
      message: el.stencil(widget.stencil.name),
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: _hover
                  ? scheme.primaryContainer.withValues(alpha: 0.55)
                  : scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _hover ? scheme.primary : scheme.outlineVariant,
              ),
            ),
            child: CustomPaint(
              painter: _WireframeThumbPainter(widget.stencil),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact wireframe thumbnail (EdrawMax-style outline grid, no fill noise).
class _WireframeThumbPainter extends CustomPainter {
  _WireframeThumbPainter(this.stencil);

  final Stencil stencil;

  static final Map<Stencil, _Geom> _cache = <Stencil, _Geom>{};

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final geom = _cache.putIfAbsent(stencil, () {
      final shape = stencil.build(0, 0, 0);
      final w = shape.width;
      final h = shape.height;
      final paths = <Path>[];
      if (w > 0 && h > 0) {
        for (final g in shape.geometries) {
          if (g.noShow) continue;
          // Outline even fill-only geometries so wireframe thumbs stay visible.
          if (g.noLine && g.noFill) continue;
          // Skip invisible text-box frames (no fill & no line on the shape).
          if (!shape.fill.hasFill && !shape.line.hasLine) continue;
          paths.add(buildPath(g, widthInches: w, heightInches: h));
        }
      }
      final label = shape.text?.trim();
      return _Geom(
        w,
        h,
        paths,
        label: (label != null && label.isNotEmpty) ? label : null,
      );
    });
    final w = geom.width;
    final h = geom.height;
    if (w > 0 && h > 0 && geom.paths.isNotEmpty) {
      const pad = 7.0;
      final s =
          math.min((size.width - 2 * pad) / w, (size.height - 2 * pad) / h);
      if (s <= 0) return;
      final dx = (size.width - w * s) / 2;
      final dy = (size.height - h * s) / 2;
      canvas
        ..save()
        ..translate(dx, size.height - dy)
        ..scale(s, -s);
      final stroke = Paint()
        ..color = const Color(0xFF5A6A7A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.15 / s
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      for (final p in geom.paths) {
        canvas.drawPath(p, stroke);
      }
      canvas.restore();
      return;
    }
    final label = geom.label;
    if (label == null) return;
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xFF5A6A7A),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1.05,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: math.max(8.0, size.width - 4));
    tp.paint(
      canvas,
      Offset(
        (size.width - tp.width) / 2,
        (size.height - tp.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _WireframeThumbPainter old) =>
      old.stencil != stencil;
}

class _Geom {
  _Geom(this.width, this.height, this.paths, {this.label});
  final double width;
  final double height;
  final List<Path> paths;
  final String? label;
}

/// Inserts [QuickAddPicker] into the nearest [Overlay] and returns a disposer.
///
/// [onClosed] runs once when the picker is dismissed for any reason (select,
/// duplicate, outside tap, or the returned disposer).
VoidCallback showQuickAddPicker({
  required BuildContext context,
  required Offset anchorGlobal,
  required ValueChanged<Stencil> onSelect,
  required VoidCallback onDuplicate,
  VoidCallback? onClosed,
}) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  var closed = false;
  void dismiss() {
    if (closed) return;
    closed = true;
    if (entry.mounted) entry.remove();
    onClosed?.call();
  }

  entry = OverlayEntry(
    builder: (ctx) => QuickAddPicker(
      anchorGlobal: anchorGlobal,
      onSelect: (s) {
        dismiss();
        onSelect(s);
      },
      onDuplicate: () {
        dismiss();
        onDuplicate();
      },
      onDismiss: dismiss,
    ),
  );
  overlay.insert(entry);
  return dismiss;
}
