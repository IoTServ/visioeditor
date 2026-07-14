import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/editor/editor_controller.dart';
import 'package:visioeditor/editor/page_canvas.dart';

/// The white page "sheet" is the only DecoratedBox that carries a drop shadow.
final Finder _pageSheet = find.byWidgetPredicate(
  (w) =>
      w is DecoratedBox &&
      w.decoration is BoxDecoration &&
      (w.decoration as BoxDecoration).boxShadow != null,
);

Future<void> _pumpCanvas(WidgetTester tester, Size viewport) async {
  final c = EditorController()..newDocument(); // blank 8.5 x 11 portrait page
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: viewport.width,
            height: viewport.height,
            child: PageCanvas(controller: c),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // The fit-to-window runs in a post-frame callback, then setState re-lays out.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  // Regression: the page sheet used to inherit the Stack's viewport-capped
  // (loose) constraints, so it was clamped to the canvas area before the view
  // transform scaled it. That squashed the page — visibly wrong in any window
  // where the page is larger than the canvas (i.e. most non-maximized windows).
  const pageAspect = 8.5 / 11.0;

  testWidgets('page keeps its aspect ratio when larger than the viewport',
      (tester) async {
    await _pumpCanvas(tester, const Size(320, 240));
    expect(_pageSheet, findsOneWidget);
    final r = tester.getRect(_pageSheet);
    expect(r.width / r.height, closeTo(pageAspect, 0.01));
    // And the fitted page must actually be smaller than the viewport it fits in.
    expect(r.width, lessThanOrEqualTo(320));
    expect(r.height, lessThanOrEqualTo(240));
  });

  testWidgets('page keeps its aspect ratio in a large viewport', (tester) async {
    await _pumpCanvas(tester, const Size(1200, 900));
    expect(_pageSheet, findsOneWidget);
    final r = tester.getRect(_pageSheet);
    expect(r.width / r.height, closeTo(pageAspect, 0.01));
  });
}
