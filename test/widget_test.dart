import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/main.dart';

void main() {
  testWidgets('shows the empty state with an open action', (tester) async {
    await tester.pumpWidget(const VisioEditorApp());
    await tester.pumpAndSettle();

    expect(find.text('Editor for Visio Diagrams'), findsWidgets);
    expect(find.text('Open Visio drawing'), findsOneWidget);
    expect(find.byIcon(Icons.folder_open_outlined), findsWidgets);
  });
}
