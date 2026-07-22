/// Client for the app's live-preview bridge (see `lib/agent_bridge/`).
///
/// Discovers the running editor via a handshake file, opens the loopback
/// WebSocket, and does request/response calls (`open` / `reload` / `applyOps` /
/// `snapshot` / `getState` / `save`). Used by the MCP server's "live" tools.
///
/// Handshake locations (first hit wins):
/// * `~/.visioeditor/agent-bridge.json` — Linux / Windows / unsandboxed macOS
/// * `~/Library/Containers/<bundle>/Data/.visioeditor/agent-bridge.json` —
///   sandboxed macOS app (no temporary-exception entitlement required; the
///   CLI runs unsandboxed and can read the container path)
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Bundle IDs whose App Sandbox containers may hold the handshake file.
const List<String> kAgentBridgeMacContainerBundleIds = <String>[
  'cloud.iothub.visioeditor',
  'cloud.iothub.visioeditor.debug',
];

/// Process home for publishing the handshake (`AgentBridge` in the app).
///
/// Under macOS App Sandbox this is the container Data directory — that is
/// intentional so we do not need a home-relative temporary exception.
String agentBridgeHomeDirectory() {
  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'];
  if (home == null || home.isEmpty) return Directory.systemTemp.path;
  return home;
}

/// Real user home as seen by an unsandboxed CLI / MCP client.
String agentBridgeClientHomeDirectory() {
  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'];
  if (home == null || home.isEmpty) return Directory.systemTemp.path;
  // Defensive: if a client somehow runs sandboxed, climb out of the container.
  const marker = '/Library/Containers/';
  final idx = home.indexOf(marker);
  if (idx > 0) return home.substring(0, idx);
  return home;
}

class BridgeClient {
  BridgeClient._(this._socket, this._stream);

  final WebSocket _socket;
  final Stream<Map<String, dynamic>> _stream;
  int _id = 0;

  /// Path where **this process** should publish the handshake (app side).
  static String handshakePath() {
    return '${agentBridgeHomeDirectory()}/.visioeditor/agent-bridge.json';
  }

  /// Candidate paths a CLI / MCP client should probe (macOS sandbox-aware).
  static List<String> handshakeSearchPaths() {
    final home = agentBridgeClientHomeDirectory();
    final paths = <String>[
      '$home/.visioeditor/agent-bridge.json',
    ];
    if (Platform.isMacOS) {
      for (final id in kAgentBridgeMacContainerBundleIds) {
        paths.add(
          '$home/Library/Containers/$id/Data/.visioeditor/agent-bridge.json',
        );
      }
    }
    return paths;
  }

  /// First existing handshake file, or `null`.
  static String? findHandshakePath() {
    for (final path in handshakeSearchPaths()) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  /// `true` if a handshake file exists (the app *may* be running with the
  /// bridge enabled).
  static bool get available => findHandshakePath() != null;

  /// Connect to the running app. Throws a helpful [StateError] if the bridge
  /// isn't enabled.
  static Future<BridgeClient> connect({String? handshakeFile}) async {
    final path = handshakeFile ?? findHandshakePath();
    if (path == null) {
      throw StateError(
          'Agent live preview is not running. Open the editor and enable '
          '"Agent live preview" from the More (⋯) menu, then retry.');
    }
    final f = File(path);
    if (!f.existsSync()) {
      throw StateError(
          'Agent live preview is not running. Open the editor and enable '
          '"Agent live preview" from the More (⋯) menu, then retry.');
    }
    final hs = (jsonDecode(await f.readAsString()) as Map).cast<String, dynamic>();
    final port = hs['port'];
    final token = hs['token'];
    final socket =
        await WebSocket.connect('ws://127.0.0.1:$port/?token=$token');
    final stream = socket
        .map((d) => (jsonDecode(d as String) as Map).cast<String, dynamic>())
        .asBroadcastStream();
    return BridgeClient._(socket, stream);
  }

  /// Send [method] with [params] and await the matching reply.
  Future<Map<String, dynamic>> call(String method,
      [Map<String, dynamic>? params]) async {
    final id = ++_id;
    _socket.add(jsonEncode(<String, dynamic>{
      'id': id,
      'method': method,
      'params': params ?? const <String, dynamic>{},
    }));
    final reply = await _stream
        .firstWhere((m) => m['id'] == id)
        .timeout(const Duration(seconds: 30));
    if (reply['ok'] == true) {
      final r = reply['result'];
      if (r is Map) return r.cast<String, dynamic>();
      return <String, dynamic>{'result': r};
    }
    throw StateError('bridge error: ${reply['error']}');
  }

  Future<void> close() => _socket.close();
}
