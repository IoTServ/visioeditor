/// Live-preview bridge (L1 + L2) between an AI Agent / the `vsdxtool` CLI /
/// MCP server and the **running** editor.
///
/// * **L1** — watches the active document's file on disk and auto-reloads it
///   (unless the user has unsaved edits), so `vsdxtool patch out.vsdx` is
///   reflected in the app within ~1s.
/// * **L2** — a loopback (127.0.0.1) WebSocket control channel. A handshake
///   file (`~/.visioeditor/agent-bridge.json`, or under the macOS App Sandbox
///   container; `0600`) publishes the random port + one-time token; clients
///   call `open` / `reload` / `applyOps` / `select` / `snapshot` / `getState` /
///   `save` and receive change events.
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
  Future<void> _requestQueue = Future<void>.value();
  bool _pollingActiveFile = false;
  String _token = '';

  /// Human-readable status for the UI (null when stopped).
  final ValueNotifier<String?> status = ValueNotifier<String?>(null);

  bool get isRunning => _server != null;
  int? get port => _server?.port;
  String get token => _token;

  /// The handshake file an Agent / CLI reads to discover the port + token.
  static String handshakePath() => BridgeClient.handshakePath();

  Future<void> start() async {
    if (_server != null) return;
    _token = _randomToken();
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handleRequest);
    await _writeHandshake();
    _watchTimer = Timer.periodic(
      const Duration(milliseconds: 800),
      (_) => unawaited(_pollActiveFile()),
    );
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
      (data) {
        // WebSocket preserves message order, but an async listen callback does
        // not: `open`/`save` can yield while a later `applyOps` runs. Serialize
        // every request globally so multiple clients also observe one coherent
        // editor timeline.
        _requestQueue = _requestQueue
            .then((_) => _onMessage(ws, data))
            .catchError((Object _, StackTrace _) {});
        unawaited(_requestQueue);
      },
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
          (req['params'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final result = await _dispatch(method, params);
      _reply(ws, <String, dynamic>{'id': id, 'ok': true, 'result': result});
      if (_server != null) {
        status.value =
            'Agent preview · $method · 127.0.0.1:${_server?.port ?? 0}';
      }
    } catch (e) {
      _reply(ws, <String, dynamic>{'id': id, 'ok': false, 'error': '$e'});
    }
  }

  void _reply(WebSocket ws, Map<String, dynamic> message) {
    if (ws.readyState != WebSocket.open) return;
    try {
      ws.add(jsonEncode(message));
    } catch (_) {
      // The peer may close between the readyState check and add. A dead peer
      // must not poison the global request queue for the remaining clients.
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
        if (doc.pages.isEmpty) {
          return <String, dynamic>{'page': 0, 'shapes': const <dynamic>[]};
        }
        final requested =
            (params['page'] as num?)?.toInt() ??
            workspace.active!.currentPageIndex;
        final page = requested.clamp(0, doc.pages.length - 1);
        return <String, dynamic>{
          'page': page,
          'shapes': listShapes(doc, pageIndex: page),
        };
      case 'select':
        return _select(params['ids']);
      case 'open':
        final path = params['path']?.toString();
        if (path == null) throw ArgumentError('open: missing path');
        final before = workspace.active;
        final beforeEpoch = before?.documentEpoch;
        await openPath(path);
        final opened = workspace.active;
        if (opened == null ||
            opened.document == null ||
            opened.error != null ||
            (identical(opened, before) &&
                opened.documentEpoch == beforeEpoch) ||
            opened.filePath == null ||
            File(opened.filePath!).absolute.path != File(path).absolute.path) {
          throw StateError('open failed: $path');
        }
        final f = File(path);
        if (f.existsSync()) _mtimes[path] = f.statSync().modified;
        return _state();
      case 'reload':
        await _reloadActive();
        return _state();
      case 'applyOps':
        final ops = (params['ops'] as List?) ?? const [];
        final page = (params['page'] as num?)?.toInt();
        return await _applyOps(ops, pageIndex: page);
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
    final requested = <int>[
      for (final v in (idsRaw as List?) ?? const <dynamic>[])
        if (v is num) v.toInt() else if (v is String) int.tryParse(v) ?? -1,
    ].where((id) => id >= 0).toList();
    // listShapes deliberately exposes nested group children, so select must
    // accept the same id universe rather than top-level page.shapes only.
    final selected = <int>[
      for (final id in requested)
        if (page.findShapeById(id) != null) id,
    ];
    final unknown = <int>[
      for (final id in requested)
        if (page.findShapeById(id) == null) id,
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

  Future<Map<String, dynamic>> _applyOps(
    List<dynamic> ops, {
    int? pageIndex,
  }) async {
    final c = workspace.active;
    final doc = c?.document;
    if (c == null || doc == null) {
      throw StateError('no active document');
    }
    if (doc.pages.isEmpty) {
      throw StateError('document has no pages');
    }
    final page = (pageIndex ?? c.currentPageIndex).clamp(
      0,
      doc.pages.length - 1,
    );
    // L3 co-editing: apply the ops to the LIVE in-memory model and commit as a
    // single undo step (via the editor's own history). The user's undo stack
    // and selection are preserved — the Agent edits alongside them, and any
    // change is one Cmd-Z away. No disk write; instant repaint.
    final opsList = <Map<String, dynamic>>[
      for (final o in ops) (o as Map).cast<String, dynamic>(),
    ];
    final result = applyOps(doc, opsList, pageIndex: page);
    final changed = !identical(result.document, doc);
    if (changed) {
      c.applyEdit(result.document);
      _emit('documentChanged', <String, dynamic>{
        'reason': 'applyOps',
        'page': page,
        'created': result.createdIds,
        if (result.log.isNotEmpty) 'log': result.log,
      });
    }
    return <String, dynamic>{
      ..._state(),
      'page': page,
      'changed': changed,
      'created': result.createdIds,
      if (result.log.isNotEmpty) 'log': result.log,
    };
  }

  Future<Map<String, dynamic>> _save() async {
    final c = workspace.active;
    if (c == null || c.document == null) {
      throw StateError('no active document');
    }
    final path = c.filePath;
    if (path == null) {
      throw StateError('document has no file path; use Save As');
    }
    final bytes = c.exportToBytes();
    await File(path).writeAsBytes(bytes, flush: true);
    c.markSaved(bytes, path: path);
    _bumpMtime(path);
    return <String, dynamic>{'saved': path, 'bytes': bytes.length};
  }

  Future<String> _snapshot(int pageArg) async {
    final c = workspace.active;
    final doc = c?.document;
    if (doc == null || doc.pages.isEmpty) {
      throw StateError('no active document');
    }
    final idx = (pageArg < 0 ? c!.currentPageIndex : pageArg).clamp(
      0,
      doc.pages.length - 1,
    );
    final page = doc.pages[idx];
    final png = await renderPageToPng(
      page,
      theme: doc.theme,
      images: doc.images,
      underlayPage: doc.backgroundFor(page),
      drawLineJumps: c!.showLineJumps,
      lineJumpRadiusInches: c.lineJumpRadiusInches,
      colorByLayer: c.colorByLayer,
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
    // openBytes reports parse errors on the controller instead of throwing and
    // clears its current model. Validate first so an explicit bridge reload
    // cannot destroy the open document when the on-disk file is partial/bad.
    parseVisio(bytes);
    await c.openBytes(bytes, path: path, name: c.fileName);
    if (c.error != null || c.document == null) {
      throw StateError('reload failed: ${c.error ?? path}');
    }
    _bumpMtime(path);
  }

  // --- L1 file watch ---------------------------------------------------------

  Future<void> _pollActiveFile() async {
    if (_pollingActiveFile) return;
    _pollingActiveFile = true;
    try {
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
      if (c.isDirty) {
        // Don't clobber unsaved edits; let the client decide.
        _mtimes[path] = mtime;
        _emit('fileChangedOnDisk', <String, dynamic>{
          'path': path,
          'dirty': true,
        });
        return;
      }

      final bytes = await f.readAsBytes();
      // Reading yields. The user may edit or switch tabs in the meantime; in
      // either case this poll no longer owns the active clean document.
      if (!identical(workspace.active, c) || c.filePath != path) return;
      final latestMtime = f.existsSync() ? f.statSync().modified : mtime;
      if (c.isDirty) {
        _mtimes[path] = latestMtime;
        _emit('fileChangedOnDisk', <String, dynamic>{
          'path': path,
          'dirty': true,
        });
        return;
      }
      if (latestMtime.isAfter(mtime)) {
        // The file changed again while it was being read. Leave the old mtime
        // in place and consume the stable latest version on the next poll.
        return;
      }

      // A partially-written/corrupt file must not clear a valid open canvas.
      parseVisio(bytes);
      await c.openBytes(bytes, path: path, name: c.fileName);
      if (c.error != null || c.document == null) {
        throw StateError('file-watch reload failed: ${c.error ?? path}');
      }
      _mtimes[path] = latestMtime;
      _emit('documentChanged', <String, dynamic>{
        'reason': 'fileWatch',
        'path': path,
      });
    } catch (e) {
      if (_server != null) {
        status.value = 'Agent preview · file watch error: $e';
      }
    } finally {
      _pollingActiveFile = false;
    }
  }

  void _bumpMtime(String? path) {
    if (path == null) return;
    final f = File(path);
    if (f.existsSync()) _mtimes[path] = f.statSync().modified;
  }

  void _emit(String event, Map<String, dynamic> data) {
    final msg = jsonEncode(<String, dynamic>{'event': event, 'data': data});
    for (final c in _clients.toList()) {
      if (c.readyState != WebSocket.open) {
        _clients.remove(c);
        continue;
      }
      try {
        c.add(msg);
      } catch (_) {
        // A client can disconnect while an edit is being committed. Event
        // delivery is best-effort and must never turn a successful mutation
        // into a protocol error for the requesting client.
        _clients.remove(c);
      }
    }
  }

  // --- Handshake -------------------------------------------------------------

  Future<void> _writeHandshake() async {
    final file = File(handshakePath());
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(<String, dynamic>{
        'port': _server!.port,
        'token': _token,
        'pid': pid,
        'startedAt': DateTime.now().toIso8601String(),
      }),
    );
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
      if (!await f.exists()) return;
      final contents = (jsonDecode(await f.readAsString()) as Map)
          .cast<String, dynamic>();
      // A second app instance may have replaced the shared handshake. Never
      // delete a file that advertises somebody else's token.
      if (contents['token'] == _token) await f.delete();
    } catch (_) {}
  }

  String _randomToken() {
    final r = Random.secure();
    return List<String>.generate(
      32,
      (_) => r.nextInt(16).toRadixString(16),
    ).join();
  }

  void dispose() {
    unawaited(stop().whenComplete(status.dispose));
  }
}
