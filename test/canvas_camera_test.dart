import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/canvas_camera.dart';

void main() {
  test('visibleContentRect maps the view transform to a content-px rect', () {
    final cam = CanvasCamera()
      ..publish(
        scale: 2,
        offset: const Offset(-100, -40),
        viewport: const Size(400, 300),
        content: const Size(816, 1056),
      );
    final r = cam.visibleContentRect!;
    // left = -offset/scale = 100/2 = 50; width = viewport/scale = 400/2 = 200.
    expect(r.left, closeTo(50, 1e-9));
    expect(r.top, closeTo(20, 1e-9));
    expect(r.width, closeTo(200, 1e-9));
    expect(r.height, closeTo(150, 1e-9));
  });

  test('publish notifies only when the transform actually changes', () {
    final cam = CanvasCamera();
    var n = 0;
    cam.addListener(() => n++);
    cam.publish(
      scale: 1,
      offset: Offset.zero,
      viewport: const Size(10, 10),
      content: const Size(20, 20),
    );
    expect(n, 1);
    // Identical values → no extra notification.
    cam.publish(
      scale: 1,
      offset: Offset.zero,
      viewport: const Size(10, 10),
      content: const Size(20, 20),
    );
    expect(n, 1);
    cam.publish(
      scale: 2,
      offset: Offset.zero,
      viewport: const Size(10, 10),
      content: const Size(20, 20),
    );
    expect(n, 2);
  });

  test('visibleContentRect is null before the canvas has laid out', () {
    expect(CanvasCamera().visibleContentRect, isNull);
  });
}
