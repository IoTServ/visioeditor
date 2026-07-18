/// Client for the app's live-preview bridge (see `lib/agent_bridge/`).
///
/// Discovers the running editor via the handshake file
/// (`~/.visioeditor/agent-bridge.json`), opens the loopback WebSocket, and does
/// request/response calls (`open` / `reload` / `applyOps` / `snapshot` /
/// `getState` / `save`). Used by the MCP server's "live" tools.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class BridgeClient {
  BridgeClient._(this._socket, this._stream);

  final WebSocket _socket;
  final Stream<Map<String, dynamic>> _stream;
  int _id = 0;

  /// Location the app publishes its port + token to.
  static String handshakePath() {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return '$home/.visioeditor/agent-bridge.json';
  }

  /// `true` if a handshake file exists (the app *may* be running with the
  /// bridge enabled).
  static bool get available => File(handshakePath()).existsSync();

  /// Connect to the running app. Throws a helpful [StateError] if the bridge
  /// isn't enabled.
  static Future<BridgeClient> connect({String? handshakeFile}) async {
    final path = handshakeFile ?? handshakePath();
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
