import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:visioeditor/ai/ai_engine.dart';
import 'package:visioeditor/ai/ai_http_transport.dart';
import 'package:vsdx/vsdx.dart';

class _FakeTransport implements AiHttpTransport {
  _FakeTransport(this.response);

  final AiHttpResponse response;
  Uri? uri;
  Map<String, String>? headers;
  String? body;

  @override
  Future<AiHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
  }) async {
    this.uri = uri;
    this.headers = headers;
    this.body = body;
    return response;
  }
}

void main() {
  test('engine readiness validates endpoint, model and provider key', () {
    expect(const AiEngineConfig(apiKey: 'key').isReady, isTrue);
    expect(
      const AiEngineConfig(endpoint: 'not a URL', apiKey: 'key').isReady,
      isFalse,
    );
    expect(const AiEngineConfig().isReady, isFalse);
    expect(
      const AiEngineConfig(
        provider: AiProvider.ollama,
        endpoint: 'http://127.0.0.1:11434/api/chat',
        model: 'qwen3',
      ).isReady,
      isTrue,
    );
  });

  test('OpenAI-compatible request carries history and parses text', () async {
    final transport = _FakeTransport(
      const AiHttpResponse(
        statusCode: 200,
        body:
            '{"choices":[{"message":{"role":"assistant","content":"Ready"}}]}',
      ),
    );
    final service = AiChatService(transport: transport);
    const config = AiEngineConfig(
      endpoint: 'https://gateway.example/v1?tenant=alpha',
      model: 'model-a',
      apiKey: 'key-a',
    );

    final result = await service.complete(config, const <AiChatMessage>[
      AiChatMessage(role: 'user', content: 'Create a flow'),
      AiChatMessage(role: 'assistant', content: 'Which direction?'),
      AiChatMessage(role: 'user', content: 'Left to right'),
    ]);

    expect(result, 'Ready');
    expect(
      transport.uri,
      Uri.parse('https://gateway.example/v1/chat/completions?tenant=alpha'),
    );
    expect(transport.headers!['authorization'], 'Bearer key-a');
    final body = (jsonDecode(transport.body!) as Map).cast<String, dynamic>();
    expect(body['model'], 'model-a');
    expect(body['stream'], isFalse);
    final messages = body['messages'] as List;
    expect((messages.first as Map)['role'], 'system');
    expect((messages.last as Map)['content'], 'Left to right');
  });

  test(
    'provider protocols use their native request and response envelopes',
    () async {
      final cases =
          <
            ({
              AiEngineConfig config,
              String response,
              String expected,
              String path,
            })
          >[
            (
              config: const AiEngineConfig(
                provider: AiProvider.anthropic,
                endpoint: 'https://api.anthropic.com/v1',
                model: 'claude-test',
                apiKey: 'ant-key',
              ),
              response: '{"content":[{"type":"text","text":"Claude reply"}]}',
              expected: 'Claude reply',
              path: '/v1/messages',
            ),
            (
              config: const AiEngineConfig(
                provider: AiProvider.gemini,
                endpoint: 'https://generativelanguage.googleapis.com/v1beta',
                model: 'gemini-test',
                apiKey: 'gem-key',
              ),
              response:
                  '{"candidates":[{"content":{"parts":[{"text":"Gemini reply"}]}}]}',
              expected: 'Gemini reply',
              path: '/v1beta/models/gemini-test:generateContent',
            ),
            (
              config: const AiEngineConfig(
                provider: AiProvider.ollama,
                endpoint: 'http://127.0.0.1:11434/api',
                model: 'qwen-test',
              ),
              response:
                  '{"message":{"role":"assistant","content":"Ollama reply"}}',
              expected: 'Ollama reply',
              path: '/api/chat',
            ),
          ];

      for (final item in cases) {
        final transport = _FakeTransport(
          AiHttpResponse(statusCode: 200, body: item.response),
        );
        final service = AiChatService(transport: transport);
        final result = await service.complete(
          item.config,
          const <AiChatMessage>[
            AiChatMessage(role: 'user', content: 'Draw it'),
          ],
        );
        expect(result, item.expected);
        expect(transport.uri!.path, item.path);
        final body = (jsonDecode(transport.body!) as Map)
            .cast<String, dynamic>();
        if (item.config.provider == AiProvider.anthropic) {
          expect(transport.headers!['anthropic-version'], '2023-06-01');
          expect(body['system'], contains('Diagram Spec'));
        } else if (item.config.provider == AiProvider.gemini) {
          expect(transport.headers!['x-goog-api-key'], 'gem-key');
          expect(body['systemInstruction'], isA<Map>());
        } else {
          expect(body['stream'], isFalse);
        }
      }
    },
  );

  test('extracts a validated Diagram Spec and builds editable vsdx', () {
    const response = '''
Here is the flow.
```json
{"version":0,"title":"Approval","layout":{"direction":"LR"},
"nodes":[
{"id":"start","text":"Start","stencil":"terminator"},
{"id":"approve","text":"Approved?","stencil":"decision"},
{"id":"done","text":"Done","stencil":"terminator"}],
"edges":[
{"from":"start","to":"approve"},
{"from":"approve","to":"done","label":"yes"}]}
```
''';

    final draft = AiChatService.extractDiagram(response);
    expect(draft, isNotNull);
    expect(draft!.title, 'Approval');
    expect(draft.format, 'Diagram Spec');
    final document = const DocumentParser().parse(draft.build());
    expect(document.pages.single.shapes, hasLength(5));
    expect(
      document.pages.single.shapes.where(
        (shape) => shape.richText.plainText == 'Approved?',
      ),
      hasLength(1),
    );
  });

  test('extracts Mermaid and rejects dangling Diagram Spec edges', () {
    final mermaid = AiChatService.extractDiagram('''
```mermaid
flowchart TB
  A([Start]) --> B{Ready?}
  B -->|yes| C[Ship]
```
''');
    expect(mermaid, isNotNull);
    expect(mermaid!.format, 'Mermaid');
    expect(mermaid.spec.nodes, hasLength(3));

    final invalid = AiChatService.extractDiagram(
      '{"nodes":[{"id":"a","text":"A"}],'
      '"edges":[{"from":"a","to":"missing"}]}',
    );
    expect(invalid, isNull);
  });

  test(
    'surfaces provider error message without exposing request key',
    () async {
      final transport = _FakeTransport(
        const AiHttpResponse(
          statusCode: 401,
          body: '{"error":{"message":"invalid credential"}}',
        ),
      );
      final service = AiChatService(transport: transport);

      await expectLater(
        service.complete(
          const AiEngineConfig(apiKey: 'do-not-print'),
          const <AiChatMessage>[AiChatMessage(role: 'user', content: 'Hello')],
        ),
        throwsA(
          isA<AiRequestException>()
              .having((error) => error.message, 'message', contains('401'))
              .having(
                (error) => error.message,
                'redaction',
                isNot(contains('do-not-print')),
              ),
        ),
      );
    },
  );
}
