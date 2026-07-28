import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visioeditor/ai/ai_chat_dialog.dart';
import 'package:visioeditor/ai/ai_engine.dart';
import 'package:visioeditor/ai/ai_http_transport.dart';
import 'package:visioeditor/main.dart';
import 'package:visioeditor/settings/app_settings.dart';

class _NoopTransport implements AiHttpTransport {
  @override
  Future<AiHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
  }) {
    throw UnimplementedError();
  }
}

class _FakeChatService extends AiChatService {
  _FakeChatService() : super(transport: _NoopTransport());

  List<AiChatMessage>? received;

  @override
  Future<String> complete(
    AiEngineConfig config,
    List<AiChatMessage> messages,
  ) async {
    received = messages;
    return '''
I prepared an approval flow.
```json
{"version":0,"title":"Leave approval","nodes":[
{"id":"request","text":"Submit request","stencil":"process"},
{"id":"review","text":"Approved?","stencil":"decision"}],
"edges":[{"from":"request","to":"review"}]}
```
''';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('chat sends history and creates diagram from assistant draft', (
    tester,
  ) async {
    final settings = await AppSettings.load();
    await settings.setAiEngine(
      const AiEngineConfig(
        endpoint: 'https://example.test/v1/chat/completions',
        model: 'test-model',
        apiKey: 'test-key',
      ),
    );
    final service = _FakeChatService();
    AiDiagramDraft? created;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiChatDialog(
            settings: settings,
            service: service,
            onCreateDiagram: (draft) async => created = draft,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('ai-chat-input')),
      'Create a leave approval flow',
    );
    await tester.tap(find.byKey(const Key('ai-chat-send')));
    await tester.pumpAndSettle();

    expect(service.received, hasLength(1));
    expect(service.received!.single.content, contains('leave approval'));
    expect(find.byKey(const Key('ai-create-diagram')), findsOneWidget);

    await tester.tap(find.byKey(const Key('ai-create-diagram')));
    await tester.pumpAndSettle();
    expect(created, isNotNull);
    expect(created!.title, 'Leave approval');
    expect(created!.spec.nodes, hasLength(2));
  });

  testWidgets('engine dialog switches provider defaults and persists config', (
    tester,
  ) async {
    final settings = await AppSettings.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showAiEngineDialog(context, settings: settings),
              child: const Text('Configure'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Configure'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-provider')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ollama').last);
    await tester.pumpAndSettle();

    final endpoint = tester.widget<TextField>(
      find.byKey(const Key('ai-endpoint')),
    );
    final model = tester.widget<TextField>(find.byKey(const Key('ai-model')));
    expect(endpoint.controller!.text, 'http://127.0.0.1:11434/api/chat');
    expect(model.controller!.text, 'qwen3');
    expect(find.byKey(const Key('ai-engine-save')), findsOneWidget);

    await tester.tap(find.byKey(const Key('ai-engine-save')));
    await tester.pumpAndSettle();
    expect(settings.aiEngine.provider, AiProvider.ollama);
    expect(settings.aiEngine.isReady, isTrue);
  });

  testWidgets('chat uses compact header without overflow on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = await AppSettings.load();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiChatDialog(
            settings: settings,
            service: _FakeChatService(),
            onCreateDiagram: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('ai-engine-button')), findsOneWidget);
    expect(find.byKey(const Key('ai-chat-input')), findsOneWidget);
  });

  testWidgets('empty home opens the built-in AI assistant', (tester) async {
    final settings = await AppSettings.load();
    await tester.pumpWidget(VisioEditorApp(settings: settings));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('empty-ai-chat')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ai-chat-input')), findsOneWidget);
    expect(find.byKey(const Key('ai-engine-button')), findsOneWidget);
  });

  testWidgets('settings exposes in-app documentation for prior Agent tools', (
    tester,
  ) async {
    final settings = await AppSettings.load();
    await settings.setLocalePreference('zh');
    await tester.pumpWidget(VisioEditorApp(settings: settings));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('AI 与 Agent'), findsOneWidget);
    final guide = find.text('AI 接入使用说明');
    await tester.ensureVisible(guide);
    await tester.pumpAndSettle();
    await tester.tap(guide);
    await tester.pumpAndSettle();

    expect(find.text('Agent 实时预览桥'), findsOneWidget);
    expect(find.text('MCP：让外部 AI 调用绘图工具'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('CLI 与 Agent Skill'), findsOneWidget);
  });
}
