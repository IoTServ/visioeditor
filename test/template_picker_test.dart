import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visioeditor/editor/page_canvas.dart';
import 'package:visioeditor/main.dart';
import 'package:visioeditor/settings/app_settings.dart';
import 'package:visioeditor/templates/diagram_templates.dart';
import 'package:visioeditor/templates/template_picker_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('catalog covers every category with blank first', () {
    expect(kDiagramTemplates.first.isBlank, isTrue);
    for (final cat in TemplateCategory.values) {
      expect(templatesFor(cat), isNotEmpty, reason: cat.name);
    }
    final assets = kDiagramTemplates
        .where((t) => t.assetName != null)
        .map((t) => t.assetName!)
        .toSet();
    expect(assets.length, greaterThanOrEqualTo(30));
  });

  testWidgets('empty state offers new from template and opens blank',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settings = await AppSettings.load();
    await tester.pumpWidget(VisioEditorApp(settings: settings));
    await tester.pumpAndSettle();

    expect(find.text('New from template'), findsWidgets);
    expect(find.byIcon(Icons.dashboard_customize_outlined), findsWidgets);

    await tester.tap(find.text('New from template').first);
    await tester.pumpAndSettle();
    expect(find.text('Blank drawing'), findsOneWidget);

    await tester.tap(find.text('Blank drawing'));
    await tester.pumpAndSettle();
    expect(find.byType(PageCanvas), findsOneWidget);
  });

  testWidgets('template picker filters by category', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    DiagramTemplate? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  picked = await showTemplatePickerDialog(context);
                },
                child: const Text('Open picker'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();

    expect(find.text('Blank drawing'), findsOneWidget);
    expect(find.text('Process flow'), findsNothing);

    await tester.tap(find.text('Flowcharts'));
    await tester.pumpAndSettle();
    expect(find.text('Process flow'), findsOneWidget);
    expect(find.text('Swimlane process'), findsOneWidget);

    await tester.tap(find.text('Strategy'));
    await tester.pumpAndSettle();
    expect(find.text('Business model canvas'), findsOneWidget);
    expect(find.text('Five forces'), findsOneWidget);

    await tester.tap(find.text('Education'));
    await tester.pumpAndSettle();
    expect(find.text('Lesson plan'), findsOneWidget);

    await tester.tap(find.text('Lesson plan'));
    await tester.pumpAndSettle();
    expect(picked?.id, 'lesson');
  });
}
