/// Live-preview bridge (L1 + L2) between an AI Agent / the `vsdxtool` CLI /
/// MCP server and the **running** editor.
///
/// * **L1** — watches the active document's file on disk and auto-reloads it
///   (unless the user has unsaved edits), so `vsdxtool patch out.vsdx` is
///   reflected in the app within ~1s.
/// * **L2** — a loopback (127.0.0.1) WebSocket control channel. A handshake
///   file (`~/.visioeditor/agent-bridge.json`, `0600`) publishes the random
///   port + one-time token; clients call `open` / `reload` / `applyOps` /
///   `select` / `snapshot` / `getState` / `save` and receive change events.
///   `applyOps` edits the in-memory model (instant repaint, no disk write);
///   `select` updates the editor selection so the user can see what the Agent
///   is targeting.
///
/// Disabled by default; toggled from the app's "Agent live preview" menu item.
/// See `docs/MCP_SKILL_PLAN.md` (M2).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:vsdx/agent.dart';
import 'package:vsdx/vsdx.dart';

import '../editor/editor_workspace.dart';
import '../io/image_export.dart';

/// Controls the loopback WebSocket server + file watcher.
class AgentBridge {
  AgentBridge({required this.workspace, required this.openPath});

  /// The app's open-document workspace (source of the active controller).
  final EditorWorkspace workspace;

  /// Reuse the app's existing "open a file into a new tab" pipeline.
  final Future<void> Function(String path) openPath;

  HttpServer? _server;
  final Set<WebSocket> _clients = <WebSocket>{};
  Timer? _watchTimer;
  final Map<String, DateTime> _mtimes = <String, DateTime>{};
  String _token = '';

  /// Human-readable status for the UI (null when stopped).
  final ValueNotifier<String?> status = ValueNotifier<String?>(null);

  bool get isRunning => _server != null;
  int? get port => _server?.port;
  String get token => _token;

  /// The handshake file an Agent / CLI reads to discover the port + token.
  static String handshakePath() {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return '$home/.visioeditor/agent-bridge.json';
  }

  Future<void> start() async {
    if (_server != null) return;
    _token = _randomToken();
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handleRequest);
    await _writeHandshake();
    _watchTimer =
        Timer.periodic(const Duration(milliseconds: 800), (_) => _pollActiveFile());
    status.value = 'Agent preview on · 127.0.0.1:${_server!.port}';
  }

  Future<void> stop() async {
    _watchTimer?.cancel();
    _watchTimer = null;
    for (final c in _clients.toList()) {
      await c.close();
    }
    _clients.clear();
    await _server?.close(force: true);
    _server = null;
    await _removeHandshake();
    status.value = null;
  }

  // --- HTTP / WebSocket ------------------------------------------------------

  Future<void> _handleRequest(HttpRequest req) async {
    if (req.uri.path == '/health') {
      req.response
        ..statusCode = HttpStatus.ok
        ..write('ok');
      await req.response.close();
      return;
    }
    if (!WebSocketTransformer.isUpgradeRequest(req)) {
      req.response.statusCode = HttpStatus.upgradeRequired;
      await req.response.close();
      return;
    }
    if (req.uri.queryParameters['token'] != _token) {
      req.response.statusCode = HttpStatus.forbidden;
      await req.response.close();
      return;
    }
    final ws = await WebSocketTransformer.upgrade(req);
    _clients.add(ws);
    ws.listen(
      (data) => _onMessage(ws, data),
      onDone: () => _clients.remove(ws),
      onError: (_) => _clients.remove(ws),
      cancelOnError: true,
    );
  }

  Future<void> _onMessage(WebSocket ws, dynamic data) async {
    Object? id;
    try {
      final req = (jsonDecode(data as String) as Map).cast<String, dynamic>();
      id = req['id'];
      final method = '${req['method']}';
      final params =
          (req['params'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
      final result = await _dispatch(method, params);
      ws.add(jsonEncode(<String, dynamic>{'id': id, 'ok': true, 'result': result}));
      status.value =
          'Agent preview · $method · 127.0.0.1:${_server?.port ?? 0}';
    } catch (e) {
      ws.add(jsonEncode(<String, dynamic>{'id': id, 'ok': false, 'error': '$e'}));
    }
  }

  Future<Object?> _dispatch(String method, Map<String, dynamic> params) async {
    switch (method) {
      case 'ping':
        return <String, dynamic>{'pong': true, 'engine': kVsdxEngineVersion};
      case 'getState':
        return _state();
      case 'listShapes':
        final doc = workspace.active?.document;
        if (doc == null) throw StateError('no active document');
        final page = (params['page'] as num?)?.toInt() ??
            workspace.active!.currentPageIndex;
        return <String, dynamic>{
          'page': page,
          'shapes': listShapes(doc, pageIndex: page),
        };
      case 'select':
        return _select(params['ids']);
      case 'open':
        final path = params['path']?.toString();
        if (path == null) throw ArgumentError('open: missing path');
        await openPath(path);
        final f = File(path);
        if (f.existsSync()) _mtimes[path] = f.statSync().modified;
        return _state();
      case 'reload':
        await _reloadActive();
        return _state();
      case 'applyOps':
        final ops = (params['ops'] as List?) ?? const [];
        return await _applyOps(ops);
      case 'save':
        return await _save();
      case 'snapshot':
        final page = (params['page'] as num?)?.toInt() ?? -1;
        return await _snapshot(page);
      default:
        throw ArgumentError('unknown method: $method');
    }
  }

  /// Set the editor selection to [idsRaw] (shape ids on the active page).
  /// Unknown / off-page ids are dropped. An empty list clears the selection.
  Map<String, dynamic> _select(Object? idsRaw) {
    final c = workspace.active;
    final doc = c?.document;
    if (c == null || doc == null) throw StateError('no active document');
    final page = doc.pages[c.currentPageIndex];
    final known = page.shapes.map((s) => s.id).toSet();
    final requested = <int>[
      for (final v in (idsRaw as List?) ?? const <dynamic>[])
        if (v is num) v.toInt() else if (v is String) int.tryParse(v) ?? -1,
    ].where((id) => id >= 0).toList();
    final selected = <int>[for (final id in requested) if (known.contains(id)) id];
    final unknown = <int>[
      for (final id in requested)
        if (!known.contains(id)) id,
    ];
    c.setSelection(selected);
    _emit('selectionChanged', <String, dynamic>{
      'selection': selected,
      if (unknown.isNotEmpty) 'unknown': unknown,
    });
    final state = _state();
    return <String, dynamic>{
      ...state,
      if (unknown.isNotEmpty) 'unknown': unknown,
    };
  }

  // --- Operations ------------------------------------------------------------

  Map<String, dynamic> _state() {
    final c = workspace.active;
    final doc = c?.document;
    return <String, dynamic>{
      'hasDocument': doc != null,
      'filePath': c?.filePath,
      'fileName': c?.fileName,
      'dirty': c?.isDirty ?? false,
      'currentPage': c?.currentPageIndex ?? 0,
      'selection': c?.selection.toList() ?? const <int>[],
      'openTabs': workspace.docs.length,
      'pages': doc == null
          ? const <dynamic>[]
          : <dynamic>[
              for (var i = 0; i < doc.pages.length; i++)
                <String, dynamic>{
                  'index': i,
                  'name': doc.pages[i].name,
                  'shapes': doc.pages[i].shapes.length,
                },
            ],
    };
  }

  Future<Map<String, dynamic>> _applyOps(List<dynamic> ops) async {
    final c = workspace.active;
    final doc = c?.document;
    if (c == null || doc == null) {
      throw StateError('no active document');
    }
    // L3 co-editing: apply the ops to the LIVE in-memory model and commit as a
    // single undo step (via the editor's own history). The user's undo stack
    // and selection are preserved — the Agent edits alongside them, and any
    // change is one Cmd-Z away. No disk write; instant repaint.
    final opsList = <Map<String, dynamic>>[
      for (final o in ops) (o as Map).cast<String, dynamic>(),
    ];
    final result = applyOps(doc, opsList, pageIndex: c.currentPageIndex);
    c.applyEdit(result.document);
    _emit('documentChanged', <String, dynamic>{
      'reason': 'applyOps',
      'created': result.createdIds,
      if (result.log.isNotEmpty) 'log': result.log,
    });
    return _state();
  }

  Future<Map<String, dynamic>> _save() async {
    final c = workspace.active;
    if (c == null || c.document == null) throw StateError('no active document');
    final path = c.filePath;
    if (path == null) throw StateError('document has no file path; use Save As');
    final bytes = c.exportToBytes();
    await File(path).writeAsBytes(bytes, flush: true);
    c.markSaved(bytes, path: path);
    _bumpMtime(path);
    return <String, dynamic>{'saved': path, 'bytes': bytes.length};
  }

  Future<String> _snapshot(int pageArg) async {
    final c = workspace.active;
    final doc = c?.document;
    if (doc == null || doc.pages.isEmpty) throw StateError('no active document');
    final idx = (pageArg < 0 ? c!.currentPageIndex : pageArg)
        .clamp(0, doc.pages.length - 1);
    final page = doc.pages[idx];
    final png = await renderPageToPng(
      page,
      theme: doc.theme,
      images: doc.images,
      underlayPage: doc.backgroundFor(page),
    );
    if (png == null) throw StateError('render failed');
    return base64Encode(png);
  }

  Future<void> _reloadActive() async {
    final c = workspace.active;
    final path = c?.filePath;
    if (c == null || path == null) throw StateError('no file-backed document');
    final f = File(path);
    if (!f.existsSync()) throw StateError('file not found: $path');
    final bytes = await f.readAsBytes();
    await c.openBytes(bytes, path: path, name: c.fileName);
    _bumpMtime(path);
  }

  // --- L1 file watch ---------------------------------------------------------

  Future<void> _pollActiveFile() async {
    final c = workspace.active;
    final path = c?.filePath;
    if (c == null || path == null) return;
    final f = File(path);
    if (!f.existsSync()) return;
    final mtime = f.statSync().modified;
    final last = _mtimes[path];
    if (last == null) {
      _mtimes[path] = mtime;
      return;
    }
    if (!mtime.isAfter(last)) return;
    _mtimes[path] = mtime;
    if (c.isDirty) {
      // Don't clobber unsaved edits; let the client decide.
      _emit('fileChangedOnDisk', <String, dynamic>{'path': path, 'dirty': true});
      return;
    }
    final bytes = await f.readAsBytes();
    await c.openBytes(bytes, path: path, name: c.fileName);
    _emit('documentChanged', <String, dynamic>{'reason': 'fileWatch', 'path': path});
  }

  void _bumpMtime(String? path) {
    if (path == null) return;
    final f = File(path);
    if (f.existsSync()) _mtimes[path] = f.statSync().modified;
  }

  void _emit(String event, Map<String, dynamic> data) {
    final msg = jsonEncode(<String, dynamic>{'event': event, 'data': data});
    for (final c in _clients) {
      c.add(msg);
    }
  }

  // --- Handshake -------------------------------------------------------------

  Future<void> _writeHandshake() async {
    final file = File(handshakePath());
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(<String, dynamic>{
      'port': _server!.port,
      'token': _token,
      'pid': pid,
      'startedAt': DateTime.now().toIso8601String(),
    }));
    // Best-effort tighten perms (POSIX only).
    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', <String>['600', file.path]);
      } catch (_) {}
    }
  }

  Future<void> _removeHandshake() async {
    try {
      final f = File(handshakePath());
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  String _randomToken() {
    final r = Random.secure();
    return List<String>.generate(
        32, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  void dispose() {
    unawaited(stop());
    status.dispose();
  }
}
