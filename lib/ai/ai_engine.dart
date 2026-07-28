import 'dart:convert';
import 'dart:typed_data';

import 'package:vsdx/agent.dart';

import 'ai_http_transport.dart';

enum AiProvider { openAiCompatible, anthropic, gemini, ollama }

extension AiProviderInfo on AiProvider {
  String get label => switch (this) {
    AiProvider.openAiCompatible => 'OpenAI compatible',
    AiProvider.anthropic => 'Anthropic',
    AiProvider.gemini => 'Google Gemini',
    AiProvider.ollama => 'Ollama',
  };

  String get defaultEndpoint => switch (this) {
    AiProvider.openAiCompatible => 'https://api.openai.com/v1/chat/completions',
    AiProvider.anthropic => 'https://api.anthropic.com/v1/messages',
    AiProvider.gemini => 'https://generativelanguage.googleapis.com/v1beta',
    AiProvider.ollama => 'http://127.0.0.1:11434/api/chat',
  };

  String get defaultModel => switch (this) {
    AiProvider.openAiCompatible => 'gpt-4.1-mini',
    AiProvider.anthropic => 'claude-sonnet-4-20250514',
    AiProvider.gemini => 'gemini-2.5-flash',
    AiProvider.ollama => 'qwen3',
  };

  bool get requiresApiKey => this != AiProvider.ollama;
}

class AiEngineConfig {
  const AiEngineConfig({
    this.provider = AiProvider.openAiCompatible,
    this.endpoint = 'https://api.openai.com/v1/chat/completions',
    this.model = 'gpt-4.1-mini',
    this.apiKey = '',
  });

  factory AiEngineConfig.defaultsFor(AiProvider provider) => AiEngineConfig(
    provider: provider,
    endpoint: provider.defaultEndpoint,
    model: provider.defaultModel,
  );

  final AiProvider provider;
  final String endpoint;
  final String model;
  final String apiKey;

  bool get isReady {
    final uri = Uri.tryParse(endpoint.trim());
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty &&
        model.trim().isNotEmpty &&
        (!provider.requiresApiKey || apiKey.trim().isNotEmpty);
  }

  AiEngineConfig copyWith({
    AiProvider? provider,
    String? endpoint,
    String? model,
    String? apiKey,
  }) => AiEngineConfig(
    provider: provider ?? this.provider,
    endpoint: endpoint ?? this.endpoint,
    model: model ?? this.model,
    apiKey: apiKey ?? this.apiKey,
  );
}

class AiChatMessage {
  const AiChatMessage({required this.role, required this.content});

  final String role;
  final String content;
}

class AiDiagramDraft {
  const AiDiagramDraft({
    required this.spec,
    required this.format,
    required this.source,
  });

  final DiagramSpec spec;
  final String format;
  final String source;

  String get title {
    final value = spec.title?.trim();
    return value == null || value.isEmpty ? 'AI Diagram' : value;
  }

  Uint8List build() => spec.build();
}

class AiRequestException implements Exception {
  const AiRequestException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Provider-neutral conversation client for the built-in diagram assistant.
class AiChatService {
  AiChatService({AiHttpTransport? transport})
    : _transport = transport ?? IoAiHttpTransport();

  final AiHttpTransport _transport;

  static const String systemPrompt = '''
You are the diagram assistant built into Editor for Visio Diagrams.
Talk naturally and help the user clarify the process. Whenever the user asks
to create or revise a diagram, include ONE complete Diagram Spec v0 JSON object
inside a ```json fenced block. Keep a short human explanation outside the block.

Diagram Spec rules:
- Root fields: version=0, title, optional style (default/corporate/dark),
  layout {direction: TB or LR, spacing}, nodes, edges.
- Every node: unique string id, text, stencil. Useful flowchart stencils:
  terminator, process, decision, document, data, predefinedProcess, cylinder.
- Every edge: from and to node ids, optional label. Do not invent dangling ids.
- Omit x/y for automatic layered layout. Prefer concise labels.
- Return the FULL revised spec on later diagram revisions, not a patch.

Example:
{"version":0,"title":"Order flow","layout":{"direction":"TB","spacing":0.7},
"nodes":[{"id":"start","text":"Start","stencil":"terminator"},
{"id":"check","text":"In stock?","stencil":"decision"}],
"edges":[{"from":"start","to":"check"}]}
''';

  Future<String> complete(
    AiEngineConfig config,
    List<AiChatMessage> messages,
  ) async {
    if (!config.isReady) {
      throw const AiRequestException(
        'Configure an endpoint, model, and API key before sending.',
      );
    }
    final request = _buildRequest(config, messages);
    final response = await _transport.post(
      request.uri,
      headers: request.headers,
      body: jsonEncode(request.body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiRequestException(_errorMessage(response));
    }
    try {
      final raw = jsonDecode(response.body);
      if (raw is! Map) throw const FormatException('response is not an object');
      final json = raw.cast<String, dynamic>();
      final text = _responseText(config.provider, json).trim();
      if (text.isEmpty) {
        throw const FormatException('response contains no assistant text');
      }
      return text;
    } catch (error) {
      if (error is AiRequestException) rethrow;
      throw AiRequestException('AI response could not be read: $error');
    }
  }

  static AiDiagramDraft? extractDiagram(String response) {
    final fences = RegExp(
      r'```([a-zA-Z0-9_-]*)\s*\n([\s\S]*?)```',
      multiLine: true,
    ).allMatches(response);
    for (final match in fences) {
      final language = (match.group(1) ?? '').toLowerCase();
      final source = (match.group(2) ?? '').trim();
      if (language == 'mermaid') {
        try {
          final spec = mermaidToSpec(source);
          if (spec.nodes.isNotEmpty) {
            return AiDiagramDraft(
              spec: spec,
              format: 'Mermaid',
              source: source,
            );
          }
        } catch (_) {
          // Try other fenced blocks.
        }
      } else if (language.isEmpty ||
          language == 'json' ||
          language == 'diagram' ||
          language == 'diagram-spec') {
        final draft = _jsonDraft(source);
        if (draft != null) return draft;
      }
    }

    final trimmed = response.trim();
    final direct = _jsonDraft(trimmed);
    if (direct != null) return direct;
    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start >= 0 && end > start) {
      return _jsonDraft(trimmed.substring(start, end + 1));
    }
    return null;
  }

  static AiDiagramDraft? _jsonDraft(String source) {
    try {
      final raw = jsonDecode(source);
      if (raw is! Map) return null;
      final json = raw.cast<String, dynamic>();
      if (json['nodes'] is! List) return null;
      final spec = DiagramSpec.fromJson(json);
      if (spec.nodes.isEmpty ||
          spec.nodes.length > 300 ||
          spec.edges.length > 600) {
        return null;
      }
      final ids = <String>{for (final node in spec.nodes) node.id};
      if (ids.length != spec.nodes.length ||
          ids.any((id) => id.trim().isEmpty || id == 'null') ||
          spec.edges.any(
            (edge) => !ids.contains(edge.from) || !ids.contains(edge.to),
          )) {
        return null;
      }
      return AiDiagramDraft(spec: spec, format: 'Diagram Spec', source: source);
    } catch (_) {
      return null;
    }
  }

  static _AiRequest _buildRequest(
    AiEngineConfig config,
    List<AiChatMessage> messages,
  ) {
    final endpoint = _endpoint(config);
    final key = config.apiKey.trim();
    switch (config.provider) {
      case AiProvider.openAiCompatible:
        return _AiRequest(
          endpoint,
          <String, String>{
            'content-type': 'application/json',
            if (key.isNotEmpty) 'authorization': 'Bearer $key',
          },
          <String, dynamic>{
            'model': config.model.trim(),
            'stream': false,
            'messages': <Map<String, String>>[
              const <String, String>{'role': 'system', 'content': systemPrompt},
              for (final message in messages)
                <String, String>{
                  'role': message.role,
                  'content': message.content,
                },
            ],
          },
        );
      case AiProvider.anthropic:
        return _AiRequest(
          endpoint,
          <String, String>{
            'content-type': 'application/json',
            'x-api-key': key,
            'anthropic-version': '2023-06-01',
          },
          <String, dynamic>{
            'model': config.model.trim(),
            'max_tokens': 4096,
            'system': systemPrompt,
            'messages': <Map<String, String>>[
              for (final message in messages)
                <String, String>{
                  'role': message.role,
                  'content': message.content,
                },
            ],
          },
        );
      case AiProvider.gemini:
        return _AiRequest(
          endpoint,
          <String, String>{
            'content-type': 'application/json',
            'x-goog-api-key': key,
          },
          <String, dynamic>{
            'systemInstruction': <String, dynamic>{
              'parts': <Map<String, String>>[
                const <String, String>{'text': systemPrompt},
              ],
            },
            'contents': <Map<String, dynamic>>[
              for (final message in messages)
                <String, dynamic>{
                  'role': message.role == 'assistant' ? 'model' : 'user',
                  'parts': <Map<String, String>>[
                    <String, String>{'text': message.content},
                  ],
                },
            ],
            'generationConfig': const <String, dynamic>{
              'maxOutputTokens': 4096,
            },
          },
        );
      case AiProvider.ollama:
        return _AiRequest(
          endpoint,
          const <String, String>{'content-type': 'application/json'},
          <String, dynamic>{
            'model': config.model.trim(),
            'stream': false,
            'messages': <Map<String, String>>[
              const <String, String>{'role': 'system', 'content': systemPrompt},
              for (final message in messages)
                <String, String>{
                  'role': message.role,
                  'content': message.content,
                },
            ],
          },
        );
    }
  }

  static Uri _endpoint(AiEngineConfig config) {
    final base = Uri.parse(config.endpoint.trim());
    String append(String suffix) {
      final path = base.path.replaceFirst(RegExp(r'/+$'), '');
      return '$path/$suffix';
    }

    switch (config.provider) {
      case AiProvider.openAiCompatible:
        return base.path.endsWith('/chat/completions')
            ? base
            : base.replace(path: append('chat/completions'));
      case AiProvider.anthropic:
        return base.path.endsWith('/messages')
            ? base
            : base.replace(path: append('messages'));
      case AiProvider.gemini:
        if (base.path.endsWith(':generateContent')) return base;
        return base.replace(
          path: append('models/${config.model.trim()}:generateContent'),
        );
      case AiProvider.ollama:
        return base.path.endsWith('/chat')
            ? base
            : base.replace(path: append('chat'));
    }
  }

  static String _responseText(AiProvider provider, Map<String, dynamic> json) {
    switch (provider) {
      case AiProvider.openAiCompatible:
        final choices = json['choices'] as List?;
        final first = choices?.isNotEmpty == true ? choices!.first : null;
        return (((first as Map?)?['message'] as Map?)?['content'] ?? '')
            .toString();
      case AiProvider.anthropic:
        final content = json['content'] as List? ?? const [];
        return <String>[
          for (final part in content)
            if (part is Map && part['type'] == 'text') '${part['text'] ?? ''}',
        ].join();
      case AiProvider.gemini:
        final candidates = json['candidates'] as List?;
        final first = candidates?.isNotEmpty == true
            ? candidates!.first as Map?
            : null;
        final parts =
            (first?['content'] as Map?)?['parts'] as List? ?? const [];
        return <String>[
          for (final part in parts)
            if (part is Map && part['text'] != null) '${part['text']}',
        ].join();
      case AiProvider.ollama:
        return (((json['message'] as Map?)?['content']) ?? '').toString();
    }
  }

  static String _errorMessage(AiHttpResponse response) {
    var detail = response.body.trim();
    try {
      final raw = jsonDecode(detail);
      if (raw is Map) {
        final error = raw['error'];
        if (error is Map && error['message'] != null) {
          detail = '${error['message']}';
        } else if (error != null) {
          detail = '$error';
        } else if (raw['message'] != null) {
          detail = '${raw['message']}';
        }
      }
    } catch (_) {
      // Preserve the response body.
    }
    if (detail.length > 300) detail = '${detail.substring(0, 300)}…';
    return 'AI request failed (${response.statusCode})'
        '${detail.isEmpty ? '' : ': $detail'}';
  }
}

class _AiRequest {
  const _AiRequest(this.uri, this.headers, this.body);

  final Uri uri;
  final Map<String, String> headers;
  final Map<String, dynamic> body;
}
