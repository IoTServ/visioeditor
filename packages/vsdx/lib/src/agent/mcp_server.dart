/// A tiny, dependency-free **Model Context Protocol** server for stdio.
///
/// Implements just enough of the MCP spec for a tool server: the `initialize`
/// handshake, `tools/list`, `tools/call`, and `ping`, framed as
/// newline-delimited JSON-RPC 2.0 over stdin/stdout (the MCP stdio transport).
///
/// Tool errors are returned as a normal result with `isError: true` (per MCP),
/// so an Agent sees the message instead of a transport failure. Kept pure and
/// testable via [handle]; [serve] wires it to real stdio.
///
/// See `docs/MCP_SKILL_PLAN.md` (M3).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// One item of tool output (text or an inline image).
class McpContent {
  const McpContent._(this.type, {this.text, this.data, this.mimeType});

  factory McpContent.text(String text) => McpContent._('text', text: text);

  factory McpContent.image(String base64Data, {String mimeType = 'image/png'}) =>
      McpContent._('image', data: base64Data, mimeType: mimeType);

  final String type;
  final String? text;
  final String? data;
  final String? mimeType;

  Map<String, dynamic> toJson() => type == 'image'
      ? <String, dynamic>{'type': 'image', 'data': data, 'mimeType': mimeType}
      : <String, dynamic>{'type': 'text', 'text': text};
}

/// A registered tool: name, human description, JSON-Schema for its arguments,
/// and an async handler returning content items.
class McpTool {
  McpTool({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.handler,
  });

  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
  final Future<List<McpContent>> Function(Map<String, dynamic> args) handler;

  Map<String, dynamic> get definition => <String, dynamic>{
        'name': name,
        'description': description,
        'inputSchema': inputSchema,
      };
}

/// A minimal MCP stdio server.
class McpServer {
  McpServer({
    required this.name,
    required this.version,
    this.protocolVersion = '2024-11-05',
  });

  final String name;
  final String version;
  final String protocolVersion;
  final Map<String, McpTool> _tools = <String, McpTool>{};

  void addTool(McpTool tool) => _tools[tool.name] = tool;
  Iterable<McpTool> get tools => _tools.values;

  /// Handle one JSON-RPC request object. Returns the response object, or `null`
  /// for notifications (which must not be answered).
  Future<Map<String, dynamic>?> handle(Map<String, dynamic> req) async {
    final method = req['method'];
    final id = req['id'];
    final isNotification = !req.containsKey('id');

    switch (method) {
      case 'initialize':
        return _ok(id, <String, dynamic>{
          'protocolVersion': protocolVersion,
          'capabilities': <String, dynamic>{'tools': <String, dynamic>{}},
          'serverInfo': <String, dynamic>{'name': name, 'version': version},
        });
      case 'notifications/initialized':
      case 'notifications/cancelled':
        return null;
      case 'ping':
        return _ok(id, <String, dynamic>{});
      case 'tools/list':
        return _ok(id, <String, dynamic>{
          'tools': <dynamic>[for (final t in _tools.values) t.definition],
        });
      case 'tools/call':
        final params =
            (req['params'] as Map?)?.cast<String, dynamic>() ?? const {};
        return _callTool(id, params);
      default:
        if (isNotification) return null;
        return _err(id, -32601, 'Method not found: $method');
    }
  }

  Future<Map<String, dynamic>?> _callTool(
      Object? id, Map<String, dynamic> params) async {
    final toolName = params['name']?.toString();
    final args =
        (params['arguments'] as Map?)?.cast<String, dynamic>() ?? const {};
    final tool = toolName == null ? null : _tools[toolName];
    if (tool == null) {
      return _ok(id, <String, dynamic>{
        'content': <dynamic>[McpContent.text('Unknown tool: $toolName').toJson()],
        'isError': true,
      });
    }
    try {
      final content = await tool.handler(args);
      return _ok(id, <String, dynamic>{
        'content': <dynamic>[for (final c in content) c.toJson()],
        'isError': false,
      });
    } catch (e) {
      return _ok(id, <String, dynamic>{
        'content': <dynamic>[McpContent.text('Error: $e').toJson()],
        'isError': true,
      });
    }
  }

  Map<String, dynamic> _ok(Object? id, Map<String, dynamic> result) =>
      <String, dynamic>{'jsonrpc': '2.0', 'id': id, 'result': result};

  Map<String, dynamic> _err(Object? id, int code, String message) =>
      <String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'error': <String, dynamic>{'code': code, 'message': message},
      };

  /// Run the newline-delimited JSON-RPC loop over [input]/[output]
  /// (defaults to stdin/stdout). Completes when the input stream closes.
  Future<void> serve({Stream<String>? input, IOSink? output}) async {
    final lines = input ??
        stdin.transform(utf8.decoder).transform(const LineSplitter());
    final out = output ?? stdout;
    await for (final line in lines) {
      if (line.trim().isEmpty) continue;
      Map<String, dynamic> req;
      try {
        req = (jsonDecode(line) as Map).cast<String, dynamic>();
      } catch (_) {
        continue; // ignore malformed frames
      }
      final resp = await handle(req);
      if (resp != null) out.writeln(jsonEncode(resp));
    }
  }
}
