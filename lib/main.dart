import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:vsdx/vsdx.dart';

import 'editor/canvas_camera.dart';
import 'editor/edit_data_dialog.dart';
import 'editor/edit_link_dialog.dart';
import 'editor/editor_controller.dart';
import 'editor/editor_workspace.dart';
import 'editor/layers_panel.dart';
import 'editor/outline_panel.dart';
import 'editor/page_canvas.dart';
import 'editor/ruler.dart';
import 'editor/stencils.dart';
import 'l10n/app_localizations.dart';
import 'render/arrow_library.dart';
import 'render/path_builder.dart';
import 'io/document_io.dart';
import 'io/image_export.dart';
import 'io/pdf_export.dart';
import 'io/recent_files.dart';
import 'settings/app_settings.dart';
import 'settings/settings_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  runApp(VisioEditorApp(settings: settings));
}

class VisioEditorApp extends StatelessWidget {
  const VisioEditorApp({required this.settings, super.key});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final seed = settings.seedColor;
        return MaterialApp(
          onGenerateTitle: (ctx) => AppLocalizations.of(ctx).appTitle,
          debugShowCheckedModeBanner: false,
          themeMode: settings.themeMode,
          theme: ThemeData(
            colorSchemeSeed: seed,
            useMaterial3: true,
            brightness: Brightness.light,
          ),
          darkTheme: ThemeData(
            colorSchemeSeed: seed,
            useMaterial3: true,
            brightness: Brightness.dark,
          ),
          locale: settings.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localeResolutionCallback: (device, supported) {
            final forced = settings.locale;
            if (forced != null) return forced;
            if (device == null) return supported.first;
            for (final l in supported) {
              if (l.languageCode == device.languageCode) return l;
            }
            return supported.first;
          },
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: EditorHomePage(settings: settings),
        );
      },
    );
  }
}

class EditorHomePage extends StatefulWidget {
  const EditorHomePage({required this.settings, super.key});

  final AppSettings settings;

  @override
  State<EditorHomePage> createState() => _EditorHomePageState();
}

class _EditorHomePageState extends State<EditorHomePage> {
  static const List<String> _examples = <String>[
    'workflow.vsdx',
    'test1.vsdx',
    'test3_house.vsdx',
    'test4_connectors.vsdx',
    'test10_nested_shapes.vsdx',
    'test11_rotate.vsdx',
    'test12_colors.vsdx',
  ];

  /// Channel over which macOS hands us documents opened from Finder
  /// (double-click / "Open With") or the `open` command.
  static const MethodChannel _fileChannel = MethodChannel('visioeditor/files');

  final EditorWorkspace _workspace = EditorWorkspace();
  final RecentFiles _recentFiles = RecentFiles();
  List<String> _recents = const <String>[];
  bool _dragging = false;
  bool _showStencils = false;
  bool _showFind = false;
  bool _findShowReplace = false;
  bool _showOutline = false;
  bool _showLayersPanel = false;
  bool _showRulers = true;
  final CanvasCamera _camera = CanvasCamera();

  /// Host of [PageCanvas]; used to map desktop file-drop global coords → page
  /// inches so images land under the cursor (drawio).
  final GlobalKey _canvasHostKey = GlobalKey();

  EditorController? get _c => _workspace.active;

  void _openFind({bool replace = false}) {
    if (_c == null || !_c!.hasDocument) return;
    setState(() {
      _showFind = true;
      if (replace) _findShowReplace = true;
    });
  }

  void _closeFind() {
    setState(() {
      _showFind = false;
      _findShowReplace = false;
    });
    _c?.clearFind();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SettingsPage(settings: widget.settings),
      ),
    );
  }

  /// Open drawio's "Edit Data" (Cmd+M) for the single selected shape.
  Future<void> _editData() async {
    final c = _c;
    final id = c?.singleSelectedId;
    if (c == null || id == null) return;
    await showEditDataDialog(context, c, id);
  }

  /// Open drawio's "Edit Link" (Cmd+K) for the single selected shape.
  Future<void> _editLink() async {
    final c = _c;
    final id = c?.singleSelectedId;
    if (c == null || id == null) return;
    await showEditLinkDialog(context, c, id);
  }

  @override
  void initState() {
    super.initState();
    // Document edits are observed via [ListenableBuilder] below — do not
    // setState the whole Scaffold on every controller tick (that rebuilt the
    // shapes palette's ~300 thumbnails and made scrollbars/sliders lag).
    _recentFiles.load().then((r) {
      if (mounted) setState(() => _recents = r);
    });
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      _fileChannel.setMethodCallHandler(_onNativeMethod);
      // Tell the native side we're listening so it can flush any file that was
      // opened before the Dart isolate was ready (cold launch from Finder).
      unawaited(_fileChannel.invokeMethod<void>('ready').catchError((Object _) {}));
    }
  }

  /// Handle calls pushed from the native side (currently only `openFiles`).
  Future<dynamic> _onNativeMethod(MethodCall call) async {
    if (call.method == 'openFiles') {
      final args = call.arguments;
      if (args is List) {
        for (final p in args) {
          if (p is String && hasVisioExtension(p)) await _openPath(p);
        }
      }
    }
    return null;
  }

  @override
  void dispose() {
    _workspace.dispose();
    _camera.dispose();
    super.dispose();
  }

  Future<void> _addRecent(String? path) async {
    if (path == null) return;
    final r = await _recentFiles.add(path);
    if (mounted) setState(() => _recents = r);
  }

  /// Open bytes in a NEW tab; drops the tab and reports if parsing failed.
  Future<void> _openBytes(
    Uint8List bytes, {
    String? path,
    String? name,
  }) async {
    final c = await _workspace.openBytes(bytes, path: path, name: name);
    if (c.error != null) {
      _snack('Could not open file: ${c.error}');
      final i = _workspace.indexOf(c);
      if (i >= 0) _workspace.closeAt(i);
      return;
    }
    if (path != null) await _addRecent(path);
  }

  Future<void> _open() async {
    final picked = await pickVisioFile();
    if (picked == null) return;
    await _openBytes(picked.bytes, path: picked.path, name: picked.name);
  }

  Future<void> _openPath(String path) async {
    try {
      final picked = await readDroppedFile(path);
      await _openBytes(picked.bytes, path: picked.path, name: picked.name);
    } catch (e) {
      _snack('Could not open $path');
    }
  }

  Future<void> _openExample(String assetName) async {
    try {
      final data = await rootBundle.load('assets/examples/$assetName');
      await _openBytes(data.buffer.asUint8List(), name: assetName);
    } catch (e) {
      _snack('Could not open example $assetName');
    }
  }

  Future<void> _onDrop(DropDoneDetails details) async {
    setState(() => _dragging = false);
    final c = _c;
    final pagePt = _pageInchesFromGlobal(details.globalPosition);
    for (final f in details.files) {
      if (hasVisioExtension(f.path)) {
        final picked = await readDroppedFile(f.path);
        await _openBytes(picked.bytes, path: picked.path, name: picked.name);
        continue;
      }
      // Raster image → insert at the drop point (or replace a picture under
      // the cursor), matching drawio's drag-from-desktop behaviour.
      if (c != null && c.hasDocument && hasImageExtension(f.path)) {
        try {
          final bytes = await f.readAsBytes();
          await _embedImageBytes(
            c,
            bytes,
            fileExtension: extensionOfPath(f.path),
            name: f.name,
            pagePt: pagePt,
          );
        } catch (_) {
          _snack('Could not insert image');
        }
      }
    }
  }

  /// Map a screen position onto the active page (inches), or `null` when the
  /// canvas hasn't laid out / the point is outside the host.
  Offset? _pageInchesFromGlobal(Offset global) {
    final box =
        _canvasHostKey.currentContext?.findRenderObject() as RenderBox?;
    final page = _c?.currentPage;
    if (box == null || !box.hasSize || page == null) return null;
    final local = box.globalToLocal(global);
    final cam = _camera;
    if (cam.scale <= 0) return null;
    final content = (local - cam.offset) / cam.scale;
    const ppi = 96.0;
    return Offset(
      content.dx / ppi,
      page.heightInches - content.dy / ppi,
    );
  }

  /// Insert or replace a picture from [bytes] at optional [pagePt].
  Future<void> _embedImageBytes(
    EditorController c,
    Uint8List bytes, {
    required String fileExtension,
    String? name,
    Offset? pagePt,
    bool replaceSelected = false,
  }) async {
    if (bytes.isEmpty) return;
    final size = await _imageSizeInches(bytes);
    if (!mounted) return;
    final label = name ?? 'image';
    if (replaceSelected && c.canReplaceSelectedImage) {
      c.replaceImage(
        c.singleSelectedId!,
        bytes,
        fileExtension: fileExtension,
      );
      _snack('Replaced with $label');
      return;
    }
    // Drop onto an existing picture → replace its media (drawio).
    if (pagePt != null) {
      final hit = c.pictureShapeAt(pagePt.dx, pagePt.dy);
      if (hit != null) {
        c.replaceImage(hit, bytes, fileExtension: fileExtension);
        _snack('Replaced with $label');
        return;
      }
    }
    c.insertImage(
      bytes,
      fileExtension: fileExtension,
      widthInches: size.$1,
      heightInches: size.$2,
      cx: pagePt?.dx,
      cy: pagePt?.dy,
    );
    _snack('Inserted $label');
  }

  /// Pixel size → inches at 96 dpi; `(null, null)` when undecodable.
  Future<(double?, double?)> _imageSizeInches(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final w = frame.image.width / 96.0;
      final h = frame.image.height / 96.0;
      frame.image.dispose();
      return (w, h);
    } catch (_) {
      return (null, null);
    }
  }

  Future<bool> _confirmDiscard(EditorController c) async {
    if (!c.isDirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        content: Text('“${c.fileName ?? 'Untitled'}” has unsaved changes.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  void _newDoc() => _workspace.newDocument();

  Future<void> _closeTab(int index) async {
    if (index < 0 || index >= _workspace.docs.length) return;
    if (await _confirmDiscard(_workspace.docs[index])) {
      _workspace.closeAt(index);
    }
  }

  Future<void> _save() async {
    final c = _c;
    if (c == null || !c.hasDocument) return;
    var path = c.filePath;
    path ??= await pickSaveLocation(suggestedName: c.fileName ?? 'drawing.vsdx');
    if (path == null) return;
    try {
      final bytes = c.exportToBytes();
      await writeBytesToFile(path, bytes);
      c.markSaved(bytes, path: path);
      await _addRecent(path);
      _snack('Saved to $path');
    } catch (e) {
      _snack('Save failed: $e');
    }
  }

  Future<void> _saveAs() async {
    final c = _c;
    if (c == null || !c.hasDocument) return;
    final path =
        await pickSaveLocation(suggestedName: c.fileName ?? 'drawing.vsdx');
    if (path == null) return;
    try {
      final bytes = c.exportToBytes();
      await writeBytesToFile(path, bytes);
      c.markSaved(bytes, path: path);
      await _addRecent(path);
      _snack('Saved to $path');
    } catch (e) {
      _snack('Save failed: $e');
    }
  }

  Future<void> _exportSvg() async {
    final c = _c;
    final doc = c?.document;
    if (c == null || doc == null) return;
    final path = await pickExportLocation(
      ext: 'svg',
      suggestedName: '${baseName(c.fileName)}.svg',
    );
    if (path == null) return;
    try {
      final svg = VsdxToSvgSerializer(
        layerFilter: SvgLayerFilter.print,
      ).serializeDocument(doc);
      await writeBytesToFile(path, Uint8List.fromList(utf8.encode(svg)));
      _snack('Exported SVG to $path');
    } catch (e) {
      _snack('SVG export failed: $e');
    }
  }

  Future<void> _exportPng() async {
    final c = _c;
    final doc = c?.document;
    final page = c?.currentPage;
    if (c == null || doc == null || page == null) return;
    final path = await pickExportLocation(
      ext: 'png',
      suggestedName: '${baseName(c.fileName)}.png',
    );
    if (path == null) return;
    try {
      final bytes = await renderPageToPng(
        page,
        theme: doc.theme,
        images: doc.images,
        underlayPage: doc.backgroundFor(page),
      );
      if (bytes == null) {
        _snack('PNG export failed');
        return;
      }
      await writeBytesToFile(path, bytes);
      _snack('Exported PNG to $path');
    } catch (e) {
      _snack('PNG export failed: $e');
    }
  }

  /// Insert an embedded raster image (drawio's "Insert > Image"): pick a file,
  /// size the placement box from the image's pixel dimensions (96 dpi), and
  /// hand the bytes to the controller, which embeds and round-trips them.
  /// When [replaceSelected] is true and a picture is selected, replaces it.
  Future<void> _insertImage({bool replaceSelected = false}) async {
    final c = _c;
    if (c == null || !c.hasDocument) return;
    final PickedImage? picked = await pickImageFile();
    if (picked == null) return;
    await _embedImageBytes(
      c,
      picked.bytes,
      fileExtension: picked.extension,
      name: picked.name,
      replaceSelected: replaceSelected,
    );
  }

  Future<void> _renamePage(int index) async {
    final c = _c;
    final doc = c?.document;
    if (c == null || doc == null || index < 0 || index >= doc.pages.length) {
      return;
    }
    final textController =
        TextEditingController(text: doc.pages[index].name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename page'),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Page name'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, textController.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (result != null) c.renamePageAt(index, result);
    textController.dispose();
  }

  Future<void> _exportPdf() async {
    final c = _c;
    final doc = c?.document;
    if (c == null || doc == null) return;
    final path = await pickExportLocation(
      ext: 'pdf',
      suggestedName: '${baseName(c.fileName)}.pdf',
    );
    if (path == null) return;
    try {
      final bytes = await exportDocumentToPdf(doc);
      await writeBytesToFile(path, bytes);
      _snack('Exported PDF to $path');
    } catch (e) {
      _snack('PDF export failed: $e');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    // Resolve the active controller at invoke-time (not build-time) so shortcuts
    // stay correct across tab switches without rebuilding this subtree every
    // document edit.
    EditorController? c() => _c;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): _newDoc,
        const SingleActivator(LogicalKeyboardKey.keyO, meta: true): _open,
        const SingleActivator(LogicalKeyboardKey.keyW, meta: true): () {
          if (_workspace.hasDocs) _closeTab(_workspace.activeIndex);
        },
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
          if (c() != null && c()!.hasDocument) _save();
        },
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () {
          final cur = c();
          if (cur != null && cur.canUndo) cur.undo();
        },
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
            () {
          final cur = c();
          if (cur != null && cur.canRedo) cur.redo();
        },
        const SingleActivator(LogicalKeyboardKey.keyD, meta: true): () {
          final cur = c();
          if (cur != null && cur.hasSelection) cur.duplicateSelection();
        },
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true): () {
          final cur = c();
          if (cur != null && cur.hasSelection) cur.copySelection();
        },
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true): () {
          final cur = c();
          if (cur != null && cur.hasDocument) {
            // Always try the system clipboard first (cross-instance paste).
            unawaited(cur.pasteFromSystem());
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyX, meta: true): () {
          final cur = c();
          if (cur != null && cur.hasSelection) cur.cut();
        },
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true): () {
          final cur = c();
          if (cur != null && cur.hasDocument) cur.selectAll();
        },
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true, shift: true):
            () {
          final cur = c();
          if (cur != null) cur.clearSelection();
        },
        const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () {
          final cur = c();
          if (cur != null && cur.hasSelection) cur.toggleBold();
        },
        const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () {
          final cur = c();
          if (cur != null && cur.hasSelection) cur.toggleItalic();
        },
        const SingleActivator(LogicalKeyboardKey.keyU, meta: true): () {
          final cur = c();
          if (cur != null && cur.hasSelection) cur.toggleUnderline();
        },
        const SingleActivator(LogicalKeyboardKey.keyE, meta: true): () {
          final cur = c();
          if (cur != null && cur.hasDocument) cur.selectConnectors();
        },
        const SingleActivator(LogicalKeyboardKey.keyI, meta: true, shift: true):
            () {
          final cur = c();
          if (cur != null && cur.hasDocument) cur.selectVertices();
        },
        const SingleActivator(LogicalKeyboardKey.tab): () {
          final cur = c();
          if (cur != null && cur.hasDocument) cur.selectNextShape();
        },
        const SingleActivator(LogicalKeyboardKey.tab, shift: true): () {
          final cur = c();
          if (cur != null && cur.hasDocument) {
            cur.selectNextShape(reverse: true);
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true, shift: true):
            () {
          final cur = c();
          if (cur != null && cur.hasSelection) cur.bringSelectionToFront();
        },
        const SingleActivator(LogicalKeyboardKey.keyB, meta: true, shift: true):
            () {
          final cur = c();
          if (cur != null && cur.hasSelection) cur.sendSelectionToBack();
        },
        // draw.io: Cmd+] bring forward, Cmd+[ send backward
        const SingleActivator(LogicalKeyboardKey.bracketRight, meta: true): () {
          final cur = c();
          if (cur != null && cur.hasSelection) cur.bringSelectionForward();
        },
        const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true): () {
          final cur = c();
          if (cur != null && cur.hasSelection) cur.sendSelectionBackward();
        },
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true, alt: true):
            () {
          final cur = c();
          if (cur != null && cur.hasSelection) cur.copyStyle();
        },
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true, alt: true):
            () {
          final cur = c();
          if (cur != null && cur.hasStyleClipboard) cur.pasteStyle();
        },
        const SingleActivator(LogicalKeyboardKey.keyG, meta: true): () {
          final cur = c();
          if (cur != null && cur.canGroup) cur.groupSelection();
        },
        const SingleActivator(LogicalKeyboardKey.keyU, meta: true, shift: true):
            () {
          final cur = c();
          if (cur != null && cur.canUngroup) cur.ungroupSelection();
        },
        const SingleActivator(LogicalKeyboardKey.keyR, meta: true): () {
          final cur = c();
          if (cur != null && cur.hasSelection) cur.rotateSelection90();
        },
        const SingleActivator(LogicalKeyboardKey.keyR, meta: true, shift: true):
            () {
          final cur = c();
          if (cur != null && cur.hasSelection) {
            cur.rotateSelection90(clockwise: false);
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openFind,
        const SingleActivator(LogicalKeyboardKey.keyH, meta: true): () {
          _openFind(replace: true);
        },
        const SingleActivator(LogicalKeyboardKey.keyM, meta: true): () {
          if (c()?.singleSelectedId != null) _editData();
        },
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () {
          if (c()?.singleSelectedId != null) _editLink();
        },
        const SingleActivator(LogicalKeyboardKey.keyL, meta: true): () {
          final cur = c();
          if (cur != null && cur.hasSelection) cur.toggleLock();
        },
      },
      // Document edits rebuild the builder only; the shapes palette is [child]
      // so its scroll position / thumbnails are not rebuilt every drag tick.
      child: ListenableBuilder(
        listenable: _workspace,
        child: _showStencils
            ? _StencilPanel(
                key: const ValueKey<String>('stencil-panel'),
                workspace: _workspace,
              )
            : null,
        builder: (context, stencilChild) {
          final cur = _workspace.active;
          final l10n = AppLocalizations.of(context);
          return Scaffold(
            appBar: AppBar(
              title: Text(l10n.appTitle),
              actions: [
                if (cur != null) ...[
                  IconButton(
                    onPressed: cur.canUndo ? cur.undo : null,
                    icon: const Icon(Icons.undo),
                    tooltip: 'Undo',
                  ),
                  IconButton(
                    onPressed: cur.canRedo ? cur.redo : null,
                    icon: const Icon(Icons.redo),
                    tooltip: 'Redo',
                  ),
                  IconButton(
                    onPressed: () =>
                        setState(() => _showOutline = !_showOutline),
                    icon: const Icon(Icons.map_outlined),
                    isSelected: _showOutline,
                    tooltip: 'Outline',
                  ),
                  IconButton(
                    onPressed: () => setState(() => _showRulers = !_showRulers),
                    icon: const Icon(Icons.straighten),
                    isSelected: _showRulers,
                    tooltip: 'Rulers',
                  ),
                  IconButton(
                    onPressed: cur.toggleGrid,
                    icon: Icon(cur.showGrid ? Icons.grid_on : Icons.grid_off),
                    tooltip: 'Toggle grid',
                  ),
                  IconButton(
                    onPressed: cur.requestFitToWindow,
                    icon: const Icon(Icons.fit_screen_outlined),
                    tooltip: 'Fit to window (⇧⌘H)',
                  ),
                  IconButton(
                    onPressed: () =>
                        setState(() => _showLayersPanel = !_showLayersPanel),
                    icon: const Icon(Icons.layers_outlined),
                    isSelected: _showLayersPanel,
                    tooltip: 'Layers',
                  ),
                  IconButton(
                    onPressed: _insertImage,
                    icon: const Icon(Icons.image_outlined),
                    tooltip: 'Insert Image…',
                  ),
                  IconButton(
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined),
                    tooltip: l10n.save,
                  ),
                ],
                IconButton(
                  onPressed: _newDoc,
                  icon: const Icon(Icons.note_add_outlined),
                  tooltip: l10n.newDrawing,
                ),
                IconButton(
                  onPressed: _open,
                  icon: const Icon(Icons.folder_open_outlined),
                  tooltip: l10n.openDrawing,
                ),
                if (_recents.isNotEmpty)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.history),
                    tooltip: l10n.recentFiles,
                    onSelected: _openPath,
                    itemBuilder: (context) => [
                      for (final p in _recents)
                        PopupMenuItem<String>(
                          value: p,
                          child: Text(
                            p.split(RegExp(r'[/\\]')).last,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                IconButton(
                  onPressed: _openSettings,
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: l10n.settingsTooltip,
                ),
                if (cur != null)
                  PopupMenuButton<String>(
                    tooltip: l10n.more,
                    onSelected: (value) {
                      switch (value) {
                        case 'saveAs':
                          _saveAs();
                        case 'exportSvg':
                          _exportSvg();
                        case 'exportPng':
                          _exportPng();
                        case 'exportPdf':
                          _exportPdf();
                        case 'selectAll':
                          cur.selectAll();
                        case 'find':
                          _openFind();
                        case 'replace':
                          _openFind(replace: true);
                        case 'insertImage':
                          _insertImage();
                        case 'editData':
                          _editData();
                        case 'editLink':
                          _editLink();
                        case 'editConnPts':
                          if (cur.editingConnectionPoints) {
                            cur.endEditConnectionPoints();
                          } else {
                            cur.beginEditConnectionPoints();
                          }
                        case 'lock':
                          cur.toggleLock();
                        case 'zoomSel':
                          cur.revealSelection();
                        case 'copyStyle':
                          cur.copyStyle();
                        case 'pasteStyle':
                          cur.pasteStyle();
                        case 'snap':
                          cur.toggleSnap();
                        case 'lineJumps':
                          cur.toggleLineJumps();
                        case 'settings':
                          _openSettings();
                        case 'close':
                          _closeTab(_workspace.activeIndex);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem<String>(
                        value: 'selectAll',
                        child: Text('Select All (Cmd+A)'),
                      ),
                      const PopupMenuItem<String>(
                        value: 'find',
                        child: Text('Find… (Cmd+F)'),
                      ),
                      const PopupMenuItem<String>(
                        value: 'replace',
                        child: Text('Find and Replace… (Cmd+H)'),
                      ),
                      const PopupMenuItem<String>(
                        value: 'insertImage',
                        child: Text('Insert Image…'),
                      ),
                      PopupMenuItem<String>(
                        value: 'editData',
                        enabled: cur.singleSelectedId != null,
                        child: const Text('Edit Data… (Cmd+M)'),
                      ),
                      PopupMenuItem<String>(
                        value: 'editLink',
                        enabled: cur.singleSelectedId != null,
                        child: const Text('Edit Link… (Cmd+K)'),
                      ),
                      PopupMenuItem<String>(
                        value: 'editConnPts',
                        enabled: cur.editingConnectionPoints ||
                            cur.canEditConnectionPoints,
                        child: Text(cur.editingConnectionPoints
                            ? 'Done Editing Connection Points'
                            : 'Edit Connection Points…'),
                      ),
                      PopupMenuItem<String>(
                        value: 'lock',
                        enabled: cur.hasSelection,
                        child: Text(cur.selectionLocked
                            ? 'Unlock (Cmd+L)'
                            : 'Lock (Cmd+L)'),
                      ),
                      PopupMenuItem<String>(
                        value: 'zoomSel',
                        enabled: cur.hasSelection,
                        child: const Text('Zoom to Selection'),
                      ),
                      PopupMenuItem<String>(
                        value: 'copyStyle',
                        enabled: cur.hasSelection,
                        child: const Text('Copy Style (Cmd+Alt+C)'),
                      ),
                      PopupMenuItem<String>(
                        value: 'pasteStyle',
                        enabled: cur.hasStyleClipboard && cur.hasSelection,
                        child: const Text('Paste Style (Cmd+Alt+V)'),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem<String>(
                        value: 'saveAs',
                        child: Text('Save As…'),
                      ),
                      const PopupMenuItem<String>(
                        value: 'exportSvg',
                        child: Text('Export as SVG…'),
                      ),
                      const PopupMenuItem<String>(
                        value: 'exportPng',
                        child: Text('Export as PNG…'),
                      ),
                      const PopupMenuItem<String>(
                        value: 'exportPdf',
                        child: Text('Export as PDF…'),
                      ),
                      CheckedPopupMenuItem<String>(
                        value: 'snap',
                        checked: cur.snapToGrid,
                        child: const Text('Snap to grid'),
                      ),
                      CheckedPopupMenuItem<String>(
                        value: 'lineJumps',
                        checked: cur.showLineJumps,
                        child: const Text('Line jumps'),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem<String>(
                        value: 'settings',
                        child: Text(l10n.settings),
                      ),
                      const PopupMenuItem<String>(
                        value: 'close',
                        child: Text('Close tab (Cmd+W)'),
                      ),
                    ],
                  ),
              ],
              bottom: _workspace.hasDocs ? _tabBar() : null,
            ),
            body: DropTarget(
              onDragEntered: (_) => setState(() => _dragging = true),
              onDragExited: (_) => setState(() => _dragging = false),
              onDragDone: _onDrop,
              child: Stack(
                children: [
                  Positioned.fill(child: _buildBody(cur, stencilChild)),
                  if (_showFind && cur != null && cur.hasDocument)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: _FindBar(
                        controller: cur,
                        showReplace: _findShowReplace,
                        onToggleReplace: () {
                          setState(
                              () => _findShowReplace = !_findShowReplace);
                        },
                        onClose: _closeFind,
                      ),
                    ),
                  if (_dragging) Positioned.fill(child: _dropOverlay(context)),
                ],
              ),
            ),
            bottomNavigationBar: (cur != null && cur.hasDocument)
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [_pageTabs(cur), _statusBar(cur)],
                  )
                : null,
          );
        },
      ),
    );
  }

  Widget _statusBar(EditorController c) {
    final scheme = Theme.of(context).colorScheme;
    final page = c.currentPage;
    final selCount = c.selection.length;
    final style = TextStyle(fontSize: 11, color: scheme.onSurfaceVariant);
    return Material(
      color: scheme.surfaceContainerHighest,
      child: SizedBox(
        height: 24,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              if (page != null) ...[
                Icon(Icons.crop_free, size: 13, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text('${_trimNum(page.widthInches)} × '
                    '${_trimNum(page.heightInches)} in', style: style),
                const SizedBox(width: 16),
                Text('Page ${c.currentPageIndex + 1} of ${c.pageCount}',
                    style: style),
              ],
              const Spacer(),
              if (c.isDirty) ...[
                Text('Unsaved', style: style),
                const SizedBox(width: 12),
              ],
              Text(selCount == 0 ? 'No selection' : '$selCount selected',
                  style: style),
            ],
          ),
        ),
      ),
    );
  }

  /// Format an inch value without trailing zeros (e.g. 8.5, 11, 8.27).
  static String _trimNum(double v) {
    final r = (v * 100).round() / 100;
    return r == r.roundToDouble() ? r.toInt().toString() : '$r';
  }

  PreferredSizeWidget _tabBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(40),
      child: Container(
        height: 40,
        alignment: Alignment.centerLeft,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: _workspace.docs.length,
          itemBuilder: (context, i) {
            final doc = _workspace.docs[i];
            return _DocTab(
              label: doc.fileName ?? 'Untitled',
              dirty: doc.isDirty,
              active: i == _workspace.activeIndex,
              onTap: () => _workspace.setActive(i),
              onClose: () => _closeTab(i),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(EditorController? c, Widget? stencilChild) {
    if (c == null) {
      return _EmptyState(
        onOpen: _open,
        onNew: _newDoc,
        examples: _examples,
        onOpenExample: _openExample,
      );
    }
    if (c.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!c.hasDocument || c.currentPage == null) {
      return _EmptyState(
        onOpen: _open,
        onNew: _newDoc,
        examples: _examples,
        onOpenExample: _openExample,
      );
    }
    return Row(
      children: [
        _ToolStrip(
          controller: c,
          showStencils: _showStencils,
          onToggleStencils: () =>
              setState(() => _showStencils = !_showStencils),
        ),
        const VerticalDivider(width: 1),
        // [stencilChild] is the ListenableBuilder child — not rebuilt on edits.
        if (stencilChild != null) ...[
          stencilChild,
          const VerticalDivider(width: 1),
        ],
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                key: _canvasHostKey,
                // Key by controller so each open document gets its own canvas
                // state (view transform, caches). Without this the shared state
                // leaks across tabs / new files, so a freshly-created document —
                // whose first page reuses id 0 — keeps the previous document's
                // zoom & offset and shows up tiny in a corner instead of fitted.
                child: PageCanvas(
                  key: ObjectKey(c),
                  controller: c,
                  camera: _camera,
                ),
              ),
              if (_showRulers)
                Positioned.fill(
                  child: RulerOverlay(controller: c, camera: _camera),
                ),
              if (_showOutline)
                Positioned(
                  right: 16,
                  bottom: 64,
                  child: OutlinePanel(
                    controller: c,
                    camera: _camera,
                    onClose: () => setState(() => _showOutline = false),
                  ),
                ),
              if (_showLayersPanel)
                Positioned(
                  left: 16,
                  top: 16,
                  child: LayersPanel(
                    controller: c,
                    onClose: () => setState(() => _showLayersPanel = false),
                  ),
                ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        // drawio always keeps the Format panel docked: a shape inspector when
        // something is selected, otherwise the page/"Diagram" settings.
        if (c.hasSelection)
          _PropertyPanel(controller: c)
        else
          _PageFormatPanel(controller: c),
      ],
    );
  }

  Widget _dropOverlay(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: ColoredBox(
        color: scheme.primary.withValues(alpha: 0.10),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.primary, width: 2),
            ),
            child: Text(
              _c != null && _c!.hasDocument
                  ? 'Drop Visio file or image'
                  : 'Drop to open',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pageTabs(EditorController c) {
    return Material(
      elevation: 8,
      child: SizedBox(
        height: 46,
        child: Row(
          children: [
            Expanded(
              child: ReorderableListView.builder(
                scrollDirection: Axis.horizontal,
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: c.pageCount,
                onReorderItem: (oldIndex, newIndex) {
                  c.movePage(oldIndex, newIndex);
                },
                itemBuilder: (context, i) {
                  final page = c.document!.pages[i];
                  return ReorderableDragStartListener(
                    key: ValueKey<int>(page.id),
                    index: i,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 3, vertical: 7),
                      child: GestureDetector(
                        onDoubleTap: () => _renamePage(i),
                        child: ChoiceChip(
                          avatar: page.isBackgroundPage
                              ? const Icon(Icons.layers_outlined, size: 16)
                              : null,
                          label: Text(page.name),
                          selected: i == c.currentPageIndex,
                          onSelected: (_) => c.selectPage(i),
                          tooltip: page.isBackgroundPage
                              ? 'Background page · Drag to reorder · '
                                  'Double-click to rename'
                              : 'Drag to reorder · Double-click to rename',
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            IconButton(
              onPressed: c.addPage,
              icon: const Icon(Icons.add),
              tooltip: 'Add page',
            ),
            IconButton(
              onPressed: c.duplicateCurrentPage,
              icon: const Icon(Icons.copy_all_outlined),
              tooltip: 'Duplicate page',
            ),
            IconButton(
              onPressed: c.pageCount > 1 ? c.deleteCurrentPage : null,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete page',
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

/// A single open-file tab in the top tab bar.
class _DocTab extends StatelessWidget {
  const _DocTab({
    required this.label,
    required this.dirty,
    required this.active,
    required this.onTap,
    required this.onClose,
  });

  final String label;
  final bool dirty;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: Material(
        color: active ? scheme.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.only(left: 12, right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dirty)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(Icons.circle, size: 8, color: scheme.primary),
                  ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 16),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Close tab',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.onOpen,
    required this.onNew,
    required this.examples,
    required this.onOpenExample,
  });

  final VoidCallback onOpen;
  final VoidCallback onNew;
  final List<String> examples;
  final void Function(String assetName) onOpenExample;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.account_tree_outlined, size: 72, color: scheme.primary),
          const SizedBox(height: 20),
          const Text(
            'Editor for Visio Diagrams',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a new drawing, or drag & drop / open .vsdx files '
            '(each opens in its own tab).',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: onNew,
                icon: const Icon(Icons.note_add_outlined),
                label: const Text('New drawing'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Open Visio drawing'),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text('Or try a sample:',
              style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in examples)
                  ActionChip(
                    avatar: const Icon(Icons.description_outlined, size: 18),
                    label: Text(e.replaceAll('.vsdx', '')),
                    onPressed: () => onOpenExample(e),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Left-hand vertical tool palette.
class _ToolStrip extends StatelessWidget {
  const _ToolStrip({
    required this.controller,
    required this.showStencils,
    required this.onToggleStencils,
  });

  final EditorController controller;
  final bool showStencils;
  final VoidCallback onToggleStencils;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget tool(EditorTool t, IconData icon, String tip) {
      final active = controller.tool == t;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        child: Material(
          color: active ? cs.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: IconButton(
            onPressed: () => controller.setTool(t),
            icon: Icon(icon),
            tooltip: tip,
            color: active ? cs.onPrimaryContainer : null,
          ),
        ),
      );
    }

    return ColoredBox(
      color: cs.surface,
      child: SizedBox(
        width: 56,
        child: Column(
          children: [
            const SizedBox(height: 8),
            tool(EditorTool.select, Icons.near_me_outlined, 'Select / move'),
            tool(EditorTool.rectangle, Icons.crop_square, 'Rectangle'),
            tool(EditorTool.ellipse, Icons.circle_outlined, 'Ellipse'),
            tool(EditorTool.line, Icons.horizontal_rule, 'Line'),
            tool(EditorTool.connector, Icons.timeline, 'Connector (glue)'),
            tool(EditorTool.freehand, Icons.gesture, 'Freehand'),
            tool(EditorTool.text, Icons.text_fields, 'Text'),
            const Spacer(),
            const Divider(height: 1, indent: 10, endIndent: 10),
            // Unified shapes entry: the "more shapes" library toggle lives with
            // the drawing tools (drawio keeps the shapes sidebar on the left).
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
              child: Material(
                color:
                    showStencils ? cs.primaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                child: IconButton(
                  onPressed: onToggleStencils,
                  icon: const Icon(Icons.category_outlined),
                  tooltip: 'More shapes',
                  color: showStencils ? cs.onPrimaryContainer : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Left-hand shapes palette (drawio's shapes sidebar): a search box plus
/// collapsible groups of live-thumbnail stencils. Clicking drops a stencil at
/// the page centre; dragging drops it at the cursor.
///
/// Reads the active document from [workspace] at drop/click time so this panel
/// can stay mounted across document edits (see [ListenableBuilder.child]).
class _StencilPanel extends StatefulWidget {
  const _StencilPanel({super.key, required this.workspace});

  final EditorWorkspace workspace;

  @override
  State<_StencilPanel> createState() => _StencilPanelState();
}

class _StencilPanelState extends State<_StencilPanel> {
  /// Short windows need more width before specialised libraries open, so the
  /// palette doesn't bury the canvas under a long scroll of thumbnails.
  static const double _shortHeight = 700;
  static const double _heightPenalty = 200;

  final ScrollController _scroll = ScrollController();
  String _query = '';

  /// Names of collapsed groups. Seeded responsively from the window size in
  /// [didChangeDependencies]; once the user expands/collapses anything we stop
  /// re-seeding so their choice sticks across rebuilds and window resizes.
  Set<String> _collapsed = <String>{};
  bool _userAdjusted = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_userAdjusted) {
      _collapsed = _defaultCollapsed(MediaQuery.sizeOf(context));
    }
  }

  /// Groups that start collapsed for the given window [size]. Each library
  /// declares its own [StencilGroup.expandAtWidth] threshold so more groups
  /// open as the window grows (laptop → large desktop → ultra-wide).
  Set<String> _defaultCollapsed(Size size) {
    final room = size.width -
        (size.height < _shortHeight ? _heightPenalty : 0.0);
    return <String>{
      for (final g in kStencilGroups)
        if (room < g.expandAtWidth) g.name,
    };
  }

  void _toggleGroup(String name) => setState(() {
        _userAdjusted = true;
        if (!_collapsed.remove(name)) _collapsed.add(name);
      });

  void _setAllCollapsed(bool collapsed) => setState(() {
        _userAdjusted = true;
        _collapsed = collapsed
            ? <String>{for (final g in kStencilGroups) g.name}
            : <String>{};
      });

  void _dropStencil(Stencil s) {
    widget.workspace.active?.addShapeFromBuilder(s.build);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final q = _query.trim().toLowerCase();
    final searching = q.isNotEmpty;
    final groups = <({StencilGroup group, List<Stencil> matches})>[];
    for (final group in kStencilGroups) {
      final matches = searching
          ? group.stencils
              .where((s) => s.name.toLowerCase().contains(q))
              .toList()
          : group.stencils;
      if (matches.isEmpty) continue;
      groups.add((group: group, matches: matches));
    }
    return SizedBox(
      width: 184,
      child: ColoredBox(
        color: scheme.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: TextField(
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: 'Search shapes',
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                style: const TextStyle(fontSize: 13),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            if (!searching) _buildQuickBar(scheme),
            Expanded(
              // Explicit Scrollbar so the thumb tracks pointer drags on desktop
              // even when many libraries are expanded.
              child: Scrollbar(
                controller: _scroll,
                thumbVisibility: true,
                interactive: true,
                child: ListView.builder(
                  controller: _scroll,
                  primary: false,
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  itemCount: groups.length,
                  itemBuilder: (context, i) {
                    final entry = groups[i];
                    return _buildGroup(
                      scheme,
                      entry.group,
                      entry.matches,
                      searching,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A one-tap toolbar under the search box for opening or tidying the whole
  /// library by category (drawio's expand-all / collapse-all affordance), plus
  /// a category count so the palette is quick to scan.
  Widget _buildQuickBar(ColorScheme scheme) {
    final allExpanded = _collapsed.isEmpty;
    final allCollapsed =
        kStencilGroups.every((g) => _collapsed.contains(g.name));
    Widget btn(IconData icon, String tip, VoidCallback? onTap) => IconButton(
          icon: Icon(icon, size: 18),
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          onPressed: onTap,
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
      child: Row(
        children: [
          Text('${kStencilGroups.length} categories',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const Spacer(),
          btn(Icons.unfold_more, 'Expand all',
              allExpanded ? null : () => _setAllCollapsed(false)),
          btn(Icons.unfold_less, 'Collapse all',
              allCollapsed ? null : () => _setAllCollapsed(true)),
        ],
      ),
    );
  }

  Widget _buildGroup(ColorScheme scheme, StencilGroup group,
      List<Stencil> matches, bool searching) {
    final collapsed = !searching && _collapsed.contains(group.name);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: searching ? null : () => _toggleGroup(group.name),
          child: Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4, left: 2),
            child: Row(
              children: [
                Icon(collapsed ? Icons.chevron_right : Icons.expand_more,
                    size: 16),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(group.name,
                      style: text.labelLarge,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 6),
                Text('${matches.length}',
                    style: text.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
        if (!collapsed)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in matches) _draggableTile(scheme, s),
            ],
          ),
      ],
    );
  }

  Widget _draggableTile(ColorScheme scheme, Stencil s) {
    return Tooltip(
      message: s.name,
      // Drag a stencil onto the canvas to drop it at the cursor (drawio); a
      // plain click still drops it at the centre.
      child: RepaintBoundary(
        child: Draggable<Stencil>(
          data: s,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: Material(
            color: Colors.transparent,
            child:
                Opacity(opacity: 0.85, child: _tile(scheme, s, elevated: true)),
          ),
          childWhenDragging: Opacity(opacity: 0.4, child: _tile(scheme, s)),
          child: InkWell(
            onTap: () => _dropStencil(s),
            borderRadius: BorderRadius.circular(8),
            child: _tile(scheme, s),
          ),
        ),
      ),
    );
  }

  Widget _tile(ColorScheme scheme, Stencil s, {bool elevated = false}) {
    return Container(
      width: 72,
      height: 62,
      decoration: BoxDecoration(
        color: elevated
            ? scheme.surfaceContainerHighest
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 52,
            height: 32,
            child: CustomPaint(
              painter: _StencilThumbPainter(
                s,
                scheme.primaryContainer,
                scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Text(
              s.name,
              style: const TextStyle(fontSize: 8.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

/// Cached geometry for a stencil thumbnail (shape build is relatively expensive
/// when hundreds of tiles are in the palette).
class _ThumbGeom {
  _ThumbGeom(this.width, this.height, this.paths);

  final double width;
  final double height;
  final List<({Path path, bool fill, bool line})> paths;
}

/// Paints a stencil's real geometry into a thumbnail box. Builds the shape once
/// (pin irrelevant), then maps its shape-local coordinates (origin bottom-left,
/// Y-up, inches) into the box (origin top-left, Y-down) with a Y-flip so the
/// preview matches what drops on the canvas.
class _StencilThumbPainter extends CustomPainter {
  _StencilThumbPainter(this.stencil, this.fillColor, this.strokeColor);

  final Stencil stencil;
  final Color fillColor;
  final Color strokeColor;

  static final Map<Stencil, _ThumbGeom> _cache = <Stencil, _ThumbGeom>{};

  _ThumbGeom _geom() {
    final hit = _cache[stencil];
    if (hit != null) return hit;
    final shape = stencil.build(0, 0, 0);
    final w = shape.width;
    final h = shape.height;
    final paths = <({Path path, bool fill, bool line})>[];
    if (w > 0 && h > 0) {
      for (final g in shape.geometries) {
        if (g.noShow) continue;
        paths.add((
          path: buildPath(g, widthInches: w, heightInches: h),
          fill: !g.noFill,
          line: !g.noLine,
        ));
      }
    }
    return _cache[stencil] = _ThumbGeom(w, h, paths);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final geom = _geom();
    final w = geom.width;
    final h = geom.height;
    if (w <= 0 || h <= 0 || geom.paths.isEmpty) return;
    const pad = 5.0;
    final s = math.min(
      (size.width - 2 * pad) / w,
      (size.height - 2 * pad) / h,
    );
    if (s <= 0) return;
    final dx = (size.width - w * s) / 2;
    final dy = (size.height - h * s) / 2;
    canvas.save();
    canvas.translate(dx, size.height - dy);
    canvas.scale(s, -s);
    final fill = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    final line = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 / s
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    for (final p in geom.paths) {
      if (p.fill) canvas.drawPath(p.path, fill);
      if (p.line) canvas.drawPath(p.path, line);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _StencilThumbPainter old) =>
      old.stencil != stencil ||
      old.fillColor != fillColor ||
      old.strokeColor != strokeColor;
}

/// Right-hand inspector for the current selection (fill / line / delete).
class _PropertyPanel extends StatelessWidget {
  const _PropertyPanel({required this.controller});

  final EditorController controller;

  static const List<int> _swatches = <int>[
    0xFFFFFFFF,
    0xFF000000,
    0xFFE53935,
    0xFF43A047,
    0xFF1E88E5,
    0xFFFDD835,
    0xFFFB8C00,
    0xFF8E24AA,
  ];

  @override
  Widget build(BuildContext context) {
    final count = controller.selection.length;
    return SizedBox(
      width: 232,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '$count shape${count == 1 ? '' : 's'} selected',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            children: [
              _iconBtn(Icons.flip_to_front, 'Bring to front',
                  controller.bringSelectionToFront),
              _iconBtn(Icons.flip_to_back, 'Send to back',
                  controller.sendSelectionToBack),
              _iconBtn(Icons.arrow_upward, 'Bring forward (Cmd+])',
                  controller.bringSelectionForward),
              _iconBtn(Icons.arrow_downward, 'Send backward (Cmd+[)',
                  controller.sendSelectionBackward),
              IconButton(
                onPressed:
                    controller.canGroup ? controller.groupSelection : null,
                icon: const Icon(Icons.group_work_outlined),
                tooltip: 'Group (Cmd+G)',
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed:
                    controller.canUngroup ? controller.ungroupSelection : null,
                icon: const Icon(Icons.call_split),
                tooltip: 'Ungroup (Cmd+Shift+U)',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _section(context, 'Arrange'),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (!controller.selectionLocked) ...[
                _iconBtn(Icons.flip, 'Flip horizontal',
                    controller.flipHorizontal),
                Transform.rotate(
                  angle: math.pi / 2,
                  child: _iconBtn(
                      Icons.flip, 'Flip vertical', controller.flipVertical),
                ),
                _iconBtn(Icons.rotate_left, 'Rotate 90° left',
                    () => controller.rotateSelection90(clockwise: false)),
                _iconBtn(Icons.rotate_right, 'Rotate 90° right (Cmd+R)',
                    () => controller.rotateSelection90()),
              ],
              _iconBtn(
                controller.selectionLocked ? Icons.lock : Icons.lock_open,
                controller.selectionLocked ? 'Unlock (Cmd+L)' : 'Lock (Cmd+L)',
                controller.toggleLock,
              ),
            ],
          ),
          if (!controller.selectionLocked) _arrangeFields(controller),
          const SizedBox(height: 16),
          if (count >= 1) ...[
            _section(
              context,
              count == 1 ? 'Align to page' : 'Align',
            ),
            Wrap(
              children: [
                _iconBtn(
                    Icons.align_horizontal_left,
                    count == 1 ? 'Align left to page' : 'Align left',
                    controller.alignLeft),
                _iconBtn(
                    Icons.align_horizontal_center,
                    count == 1
                        ? 'Center horizontally on page'
                        : 'Center horizontally',
                    controller.alignCenterH),
                _iconBtn(
                    Icons.align_horizontal_right,
                    count == 1 ? 'Align right to page' : 'Align right',
                    controller.alignRight),
                _iconBtn(
                    Icons.align_vertical_top,
                    count == 1 ? 'Align top to page' : 'Align top',
                    controller.alignTop),
                _iconBtn(
                    Icons.align_vertical_center,
                    count == 1
                        ? 'Center vertically on page'
                        : 'Center vertically',
                    controller.alignMiddle),
                _iconBtn(
                    Icons.align_vertical_bottom,
                    count == 1 ? 'Align bottom to page' : 'Align bottom',
                    controller.alignBottom),
                if (count >= 3) ...[
                  _iconBtn(Icons.horizontal_distribute, 'Distribute horizontally',
                      controller.distributeHorizontally),
                  _iconBtn(Icons.vertical_distribute, 'Distribute vertically',
                      controller.distributeVertically),
                ],
                if (count >= 2) ...[
                  _iconBtn(Icons.width_normal, 'Same width',
                      controller.matchSelectionWidth),
                  _iconBtn(Icons.height, 'Same height',
                      controller.matchSelectionHeight),
                  _iconBtn(Icons.aspect_ratio, 'Same size',
                      controller.matchSelectionSize),
                ],
              ],
            ),
            const SizedBox(height: 16),
          ],
          _section(context, 'Fill'),
          _swatchRow(
            onColor: (v) => controller.setFillColor(VsdxColor(v)),
            onNone: controller.setNoFill,
          ),
          const SizedBox(height: 6),
          _themeSwatchRow(
            controller: controller,
            onSlot: controller.setFillThemeSlot,
            selectedSlot: controller.selectedFill?.foreground == null
                ? controller.selectedFill?.themeForegroundIndex
                : null,
          ),
          _fillPatternControls(controller),
          _OpacitySlider(
            label: 'Opacity',
            opacity: 1 - (controller.selectedFill?.foregroundTransparency ?? 0),
            onStart: controller.beginTransaction,
            onChanged: (v) => controller.setFillOpacity(v, transient: true),
            onEnd: controller.commitTransaction,
          ),
          _fillGradientControls(context, controller),
          _roundedControl(context, controller),
          const SizedBox(height: 16),
          _section(context, 'Line'),
          _swatchRow(
            onColor: (v) => controller.setLineColor(VsdxColor(v)),
            onNone: controller.setNoLine,
          ),
          const SizedBox(height: 6),
          _themeSwatchRow(
            controller: controller,
            onSlot: controller.setLineThemeSlot,
            selectedSlot: controller.selectedLine?.color == null
                ? controller.selectedLine?.themeColorIndex
                : null,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              for (final pt in <double>[0.5, 1, 2, 3])
                ActionChip(
                  label: Text('${pt == pt.roundToDouble() ? pt.toInt() : pt}pt'),
                  onPressed: () => controller.setLineWeight(pt / 72.0),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _dashDropdown(controller),
          const SizedBox(height: 8),
          _compoundTypeRow(controller),
          const SizedBox(height: 8),
          _arrowPickers(controller),
          _OpacitySlider(
            label: 'Opacity',
            opacity: 1 - (controller.selectedLine?.transparency ?? 0),
            onStart: controller.beginTransaction,
            onChanged: (v) => controller.setLineOpacity(v, transient: true),
            onEnd: controller.commitTransaction,
          ),
          _lineGradientControls(context, controller),
          if (controller.hasConnectorSelected) ...[
            const SizedBox(height: 16),
            _section(context, 'Connector'),
            Wrap(
              spacing: 8,
              children: [
                for (final s in ConnectorRouteStyle.values)
                  ChoiceChip(
                    label: Text(switch (s) {
                      ConnectorRouteStyle.straight => 'Straight',
                      ConnectorRouteStyle.orthogonal => 'Orthogonal',
                      ConnectorRouteStyle.curved => 'Curved',
                    }),
                    selected: controller.selectedConnectorRouteStyle == s,
                    onSelected: (_) => controller.setConnectorRouteStyle(s),
                  ),
              ],
            ),
            Row(
              children: [
                const Text('Rounded'),
                const Spacer(),
                Switch(
                  value: controller.selectedConnectorRounded,
                  // Rounded corners are moot for an already-smooth curved edge.
                  onChanged: controller.selectedConnectorRouteStyle ==
                          ConnectorRouteStyle.curved
                      ? null
                      : controller.setConnectorRounded,
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          _section(context, 'Shadow'),
          Row(
            children: [
              const Text('Enabled'),
              const Spacer(),
              Switch(
                value: controller.selectedHasShadow,
                onChanged: controller.setShadow,
              ),
            ],
          ),
          if (controller.selectedHasShadow)
            _shadowDetailControls(context, controller),
          const SizedBox(height: 8),
          _section(context, 'Glow'),
          Row(
            children: [
              const Text('Enabled'),
              const Spacer(),
              Switch(
                value: controller.selectedHasGlow,
                onChanged: controller.setGlow,
              ),
            ],
          ),
          if (controller.selectedHasGlow)
            _glowDetailControls(context, controller),
          const SizedBox(height: 8),
          _section(context, 'Reflection'),
          Row(
            children: [
              const Text('Enabled'),
              const Spacer(),
              Switch(
                value: controller.selectedHasReflection,
                onChanged: controller.setReflection,
              ),
            ],
          ),
          if (controller.selectedHasReflection)
            _reflectionDetailControls(context, controller),
          const SizedBox(height: 8),
          _section(context, 'Soft Edges'),
          Row(
            children: [
              const Text('Enabled'),
              const Spacer(),
              Switch(
                value: controller.selectedHasSoftEdges,
                onChanged: controller.setSoftEdges,
              ),
            ],
          ),
          if (controller.selectedHasSoftEdges)
            _RangeSlider(
              label: 'Size',
              value: controller.selectedSoftEdgesInches.clamp(0.01, 0.25),
              min: 0.01,
              max: 0.25,
              format: (v) => '${(v * 100).round() / 100}"',
              onStart: controller.beginTransaction,
              onChanged: (v) =>
                  controller.updateSoftEdges(v, transient: true),
              onEnd: controller.commitTransaction,
            ),
          if (controller.selectedCharStyle != null) ...[
            const SizedBox(height: 16),
            _section(context, 'Text'),
            _textControls(context),
          ],
          if (controller.canReplaceSelectedImage) ...[
            const SizedBox(height: 16),
            _imageSection(context),
          ],
          if (controller.singleSelectedId != null) ...[
            const SizedBox(height: 16),
            _dataSection(context),
            const SizedBox(height: 16),
            _linkSection(context),
          ],
          const Divider(height: 32),
          FilledButton.tonalIcon(
            onPressed: controller.deleteSelection,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(label, style: Theme.of(context).textTheme.labelLarge),
      );

  /// Picture shape: replace embedded media (drawio "Replace Image").
  Widget _imageSection(BuildContext context) {
    final id = controller.singleSelectedId;
    if (id == null || !controller.canReplaceSelectedImage) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(context, 'Image'),
        OutlinedButton.icon(
          onPressed: () async {
            final picked = await pickImageFile();
            if (picked == null) return;
            controller.replaceImage(
              id,
              picked.bytes,
              fileExtension: picked.extension,
            );
          },
          icon: const Icon(Icons.image_outlined, size: 18),
          label: const Text('Replace Image…'),
        ),
      ],
    );
  }

  /// Shape Data (drawio "Edit Data"): a compact read-out of the single
  /// selection's custom properties plus a button to open the editor (Cmd+M).
  Widget _dataSection(BuildContext context) {
    final id = controller.singleSelectedId;
    if (id == null) return const SizedBox.shrink();
    final props = controller.selectedProperties;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(context, 'Data'),
        if (props.isEmpty)
          Text(
            'No shape data',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          )
        else
          for (final p in props)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      p.displayLabel,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: Text(
                      p.displayValue,
                      style:
                          TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => showEditDataDialog(context, controller, id),
          icon: const Icon(Icons.data_object, size: 18),
          label: const Text('Edit Data…'),
        ),
      ],
    );
  }

  /// Hyperlink (drawio "Edit Link"): show the single selection's current link
  /// (if any) plus a button to open the editor (Cmd+K).
  Widget _linkSection(BuildContext context) {
    final id = controller.singleSelectedId;
    if (id == null) return const SizedBox.shrink();
    final link = controller.selectedLink;
    final target = link?.effectiveTarget;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(context, 'Link'),
        if (target == null || target.isEmpty)
          Text(
            'No link',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          )
        else
          Text(
            (link!.description?.isNotEmpty ?? false)
                ? '${link.description}  →  $target'
                : target,
            style: TextStyle(fontSize: 12, color: scheme.primary),
            overflow: TextOverflow.ellipsis,
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => showEditLinkDialog(context, controller, id),
          icon: const Icon(Icons.link, size: 18),
          label: const Text('Edit Link…'),
        ),
      ],
    );
  }

  /// Fill gradient type + two colour stops + linear angle (draw.io Format).
  Widget _fillGradientControls(
    BuildContext context,
    EditorController controller,
  ) {
    final fill = controller.selectedFill;
    if (fill == null) return const SizedBox.shrink();
    final g = fill.hasGradient ? fill.gradient : null;
    final type = g?.type;
    final stop0 = g != null && g.stops.isNotEmpty
        ? g.stops.first.color?.value
        : fill.foreground?.value;
    final stop1 = g != null && g.stops.length > 1
        ? g.stops[1].color?.value
        : 0xFFFFFFFF;
    final angleDeg = g == null ? 0 : (g.angleRad * 180 / math.pi).round() % 180;

    void apply({
      VsdxGradientType? newType,
      int? color0,
      int? color1,
      double? angleRad,
    }) {
      final t = newType ?? type ?? VsdxGradientType.linear;
      final c0 = VsdxColor(color0 ?? stop0 ?? 0xFF1E88E5);
      final c1 = VsdxColor(color1 ?? stop1 ?? 0xFFFFFFFF);
      controller.setFillGradient(
        VsdxGradient(
          type: t,
          angleRad: angleRad ?? g?.angleRad ?? 0,
          stops: <VsdxGradientStop>[
            VsdxGradientStop(position: 0, color: c0),
            VsdxGradientStop(position: 1, color: c1),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text('Gradient', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          children: [
            ChoiceChip(
              label: const Text('None'),
              selected: g == null,
              onSelected: (_) => controller.setFillGradient(null),
              visualDensity: VisualDensity.compact,
            ),
            ChoiceChip(
              label: const Text('Linear'),
              selected: type == VsdxGradientType.linear,
              onSelected: (_) => apply(newType: VsdxGradientType.linear),
              visualDensity: VisualDensity.compact,
            ),
            ChoiceChip(
              label: const Text('Radial'),
              selected: type == VsdxGradientType.radial,
              onSelected: (_) => apply(newType: VsdxGradientType.radial),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        if (g != null) ...[
          const SizedBox(height: 6),
          Text('Start', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final argb in _swatches)
                _SwatchButton(
                  color: Color(argb),
                  selected: stop0 == argb,
                  onTap: () => apply(color0: argb),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text('End', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final argb in _swatches)
                _SwatchButton(
                  color: Color(argb),
                  selected: stop1 == argb,
                  onTap: () => apply(color1: argb),
                ),
            ],
          ),
          if (type == VsdxGradientType.linear) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                for (final deg in const <int>[0, 45, 90, 135])
                  ChoiceChip(
                    label: Text('$deg°'),
                    selected: angleDeg == deg,
                    onSelected: (_) =>
                        apply(angleRad: deg * math.pi / 180),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
        ],
      ],
    );
  }

  /// Line gradient type + two colour stops + linear angle (draw.io Format).
  Widget _lineGradientControls(
    BuildContext context,
    EditorController controller,
  ) {
    final line = controller.selectedLine;
    if (line == null) return const SizedBox.shrink();
    final g = line.hasGradient ? line.gradient : null;
    final type = g?.type;
    final stop0 = g != null && g.stops.isNotEmpty
        ? g.stops.first.color?.value
        : line.color?.value;
    final stop1 = g != null && g.stops.length > 1
        ? g.stops[1].color?.value
        : 0xFFFFFFFF;
    final angleDeg = g == null ? 0 : (g.angleRad * 180 / math.pi).round() % 180;

    void apply({
      VsdxGradientType? newType,
      int? color0,
      int? color1,
      double? angleRad,
    }) {
      final t = newType ?? type ?? VsdxGradientType.linear;
      final c0 = VsdxColor(color0 ?? stop0 ?? 0xFF212121);
      final c1 = VsdxColor(color1 ?? stop1 ?? 0xFFFFFFFF);
      controller.setLineGradient(
        VsdxGradient(
          type: t,
          angleRad: angleRad ?? g?.angleRad ?? 0,
          stops: <VsdxGradientStop>[
            VsdxGradientStop(position: 0, color: c0),
            VsdxGradientStop(position: 1, color: c1),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text('Gradient', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          children: [
            ChoiceChip(
              label: const Text('None'),
              selected: g == null,
              onSelected: (_) => controller.setLineGradient(null),
              visualDensity: VisualDensity.compact,
            ),
            ChoiceChip(
              label: const Text('Linear'),
              selected: type == VsdxGradientType.linear,
              onSelected: (_) => apply(newType: VsdxGradientType.linear),
              visualDensity: VisualDensity.compact,
            ),
            ChoiceChip(
              label: const Text('Radial'),
              selected: type == VsdxGradientType.radial,
              onSelected: (_) => apply(newType: VsdxGradientType.radial),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        if (g != null) ...[
          const SizedBox(height: 6),
          Text('Start', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final argb in _swatches)
                _SwatchButton(
                  color: Color(argb),
                  selected: stop0 == argb,
                  onTap: () => apply(color0: argb),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text('End', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final argb in _swatches)
                _SwatchButton(
                  color: Color(argb),
                  selected: stop1 == argb,
                  onTap: () => apply(color1: argb),
                ),
            ],
          ),
          if (type == VsdxGradientType.linear) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                for (final deg in const <int>[0, 45, 90, 135])
                  ChoiceChip(
                    label: Text('$deg°'),
                    selected: angleDeg == deg,
                    onSelected: (_) =>
                        apply(angleRad: deg * math.pi / 180),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
        ],
      ],
    );
  }

  /// Shadow colour / offset / blur / opacity (draw.io Format → Shadow).
  Widget _shadowDetailControls(
    BuildContext context,
    EditorController controller,
  ) {
    final shadow = controller.selectedShadow;
    if (shadow == null || !shadow.enabled) return const SizedBox.shrink();
    final colorValue = shadow.color?.value ?? 0xFF000000;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        Text('Color', style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final argb in _swatches)
              _SwatchButton(
                color: Color(argb),
                selected: colorValue == argb,
                onTap: () =>
                    controller.updateShadow(color: VsdxColor(argb)),
              ),
          ],
        ),
        _RangeSlider(
          label: 'Offset X',
          value: shadow.offsetXInches,
          min: -0.25,
          max: 0.25,
          format: (v) => '${(v * 100).round() / 100}"',
          onStart: controller.beginTransaction,
          onChanged: (v) =>
              controller.updateShadow(offsetXInches: v, transient: true),
          onEnd: controller.commitTransaction,
        ),
        _RangeSlider(
          label: 'Offset Y',
          value: shadow.offsetYInches,
          min: -0.25,
          max: 0.25,
          format: (v) => '${(v * 100).round() / 100}"',
          onStart: controller.beginTransaction,
          onChanged: (v) =>
              controller.updateShadow(offsetYInches: v, transient: true),
          onEnd: controller.commitTransaction,
        ),
        _RangeSlider(
          label: 'Blur',
          value: shadow.blurInches,
          min: 0,
          max: 0.25,
          format: (v) => '${(v * 100).round() / 100}"',
          onStart: controller.beginTransaction,
          onChanged: (v) =>
              controller.updateShadow(blurInches: v, transient: true),
          onEnd: controller.commitTransaction,
        ),
        _OpacitySlider(
          label: 'Opacity',
          opacity: 1 - shadow.transparency,
          onStart: controller.beginTransaction,
          onChanged: (v) => controller.updateShadow(
            transparency: (1 - v).clamp(0.0, 1.0),
            transient: true,
          ),
          onEnd: controller.commitTransaction,
        ),
      ],
    );
  }

  /// Glow colour / size / opacity (draw.io Format → Glow).
  Widget _glowDetailControls(
    BuildContext context,
    EditorController controller,
  ) {
    final glow = controller.selectedGlow;
    if (glow == null || !glow.enabled) return const SizedBox.shrink();
    final colorValue = glow.color?.value ?? 0xFFFFC107;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        Text('Color', style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final argb in _swatches)
              _SwatchButton(
                color: Color(argb),
                selected: colorValue == argb,
                onTap: () => controller.updateGlow(color: VsdxColor(argb)),
              ),
          ],
        ),
        _RangeSlider(
          label: 'Size',
          value: glow.sizeInches,
          min: 0.01,
          max: 0.25,
          format: (v) => '${(v * 100).round() / 100}"',
          onStart: controller.beginTransaction,
          onChanged: (v) =>
              controller.updateGlow(sizeInches: v, transient: true),
          onEnd: controller.commitTransaction,
        ),
        _OpacitySlider(
          label: 'Opacity',
          opacity: 1 - glow.transparency,
          onStart: controller.beginTransaction,
          onChanged: (v) => controller.updateGlow(
            transparency: (1 - v).clamp(0.0, 1.0),
            transient: true,
          ),
          onEnd: controller.commitTransaction,
        ),
      ],
    );
  }

  /// Reflection size / distance / blur / opacity (draw.io Format → Reflection).
  Widget _reflectionDetailControls(
    BuildContext context,
    EditorController controller,
  ) {
    final refl = controller.selectedReflection;
    if (refl == null || !refl.enabled) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RangeSlider(
          label: 'Size',
          value: refl.sizeInches,
          min: 0.05,
          max: 1.0,
          format: (v) => '${(v * 100).round()}%',
          onStart: controller.beginTransaction,
          onChanged: (v) =>
              controller.updateReflection(sizeInches: v, transient: true),
          onEnd: controller.commitTransaction,
        ),
        _RangeSlider(
          label: 'Dist',
          value: refl.distanceInches,
          min: 0,
          max: 0.5,
          format: (v) => '${(v * 100).round() / 100}"',
          onStart: controller.beginTransaction,
          onChanged: (v) =>
              controller.updateReflection(distanceInches: v, transient: true),
          onEnd: controller.commitTransaction,
        ),
        _RangeSlider(
          label: 'Blur',
          value: refl.blurInches,
          min: 0,
          max: 0.2,
          format: (v) => '${(v * 100).round() / 100}"',
          onStart: controller.beginTransaction,
          onChanged: (v) =>
              controller.updateReflection(blurInches: v, transient: true),
          onEnd: controller.commitTransaction,
        ),
        _OpacitySlider(
          label: 'Opacity',
          opacity: 1 - refl.transparency,
          onStart: controller.beginTransaction,
          onChanged: (v) => controller.updateReflection(
            transparency: (1 - v).clamp(0.0, 1.0),
            transient: true,
          ),
          onEnd: controller.commitTransaction,
        ),
      ],
    );
  }

  /// Corner-radius slider for a single rectangular selection (drawio's
  /// "Rounded" + arc size). Hidden for non-rectangular / multi selections.
  Widget _roundedControl(BuildContext context, EditorController controller) {
    final radius = controller.selectedCornerRadius;
    final s = controller.singleSelected;
    if (radius == null || s == null) return const SizedBox.shrink();
    final maxR = math.min(s.width, s.height) / 2;
    if (maxR <= 0) return const SizedBox.shrink();
    return _CornersSlider(
      value: radius.clamp(0.0, maxR),
      max: maxR,
      onStart: controller.beginTransaction,
      onChanged: (x) => controller.setCornerRadius(x, transient: true),
      onEnd: controller.commitTransaction,
    );
  }

  /// Numeric position / size / angle fields for a single selection (drawio's
  /// Arrange tab). Hidden when zero or many shapes are selected.
  Widget _arrangeFields(EditorController controller) {
    final g = controller.selectedGeometry;
    if (g == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _NumField(
                  label: 'X',
                  value: g.x,
                  onSubmit: controller.setSelectedX,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumField(
                  label: 'Y',
                  value: g.y,
                  onSubmit: controller.setSelectedY,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _NumField(
                  label: 'W',
                  value: g.w,
                  onSubmit: controller.setSelectedWidth,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumField(
                  label: 'H',
                  value: g.h,
                  onSubmit: controller.setSelectedHeight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _NumField(
                  label: '∠°',
                  value: g.angleDeg,
                  onSubmit: controller.setSelectedAngleDegrees,
                ),
              ),
              const Spacer(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, String tip, VoidCallback onTap) => IconButton(
        onPressed: onTap,
        icon: Icon(icon),
        tooltip: tip,
        visualDensity: VisualDensity.compact,
      );

  Widget _textControls(BuildContext context) {
    final cs = controller.selectedCharStyle;
    if (cs == null) return const SizedBox.shrink();
    final curPt = (cs.fontSizeInches * 72).round();
    final sizes = <int>{8, 9, 10, 11, 12, 14, 16, 18, 24, 28, 36, 48, curPt}
        .toList()
      ..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            DropdownButton<int>(
              value: curPt,
              isDense: true,
              items: [
                for (final p in sizes)
                  DropdownMenuItem<int>(value: p, child: Text('$p pt')),
              ],
              onChanged: (p) {
                if (p != null) controller.setTextSizeInches(p / 72.0);
              },
            ),
            const Spacer(),
            IconButton(
              onPressed: () => controller.setBold(!cs.style.bold),
              isSelected: cs.style.bold,
              icon: const Icon(Icons.format_bold),
              tooltip: 'Bold',
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              onPressed: () => controller.setItalic(!cs.style.italic),
              isSelected: cs.style.italic,
              icon: const Icon(Icons.format_italic),
              tooltip: 'Italic',
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              onPressed: () => controller.setUnderline(!cs.underline),
              isSelected: cs.underline,
              icon: const Icon(Icons.format_underlined),
              tooltip: 'Underline',
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              onPressed: () =>
                  controller.setStrikethrough(!cs.strikethrough),
              isSelected: cs.strikethrough,
              icon: const Icon(Icons.format_strikethrough),
              tooltip: 'Strikethrough',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _fontDropdown(cs),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final argb in _swatches)
              _SwatchButton(
                color: Color(argb),
                onTap: () => controller.setTextColor(VsdxColor(argb)),
              ),
          ],
        ),
        const SizedBox(height: 6),
        _themeSwatchRow(
          controller: controller,
          onSlot: controller.setTextThemeSlot,
          selectedSlot: cs.color == null ? cs.themeColorIndex : null,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _iconBtn(Icons.format_align_left, 'Align left',
                () => controller.setTextAlign(VsdxHorzAlign.left)),
            _iconBtn(Icons.format_align_center, 'Align center',
                () => controller.setTextAlign(VsdxHorzAlign.center)),
            _iconBtn(Icons.format_align_right, 'Align right',
                () => controller.setTextAlign(VsdxHorzAlign.right)),
            _iconBtn(Icons.format_align_justify, 'Justify',
                () => controller.setTextAlign(VsdxHorzAlign.justify)),
          ],
        ),
        Row(
          children: [
            _vAlignBtn(Icons.vertical_align_top, 'Align top', VsdxVertAlign.top),
            _vAlignBtn(Icons.vertical_align_center, 'Align middle',
                VsdxVertAlign.middle),
            _vAlignBtn(Icons.vertical_align_bottom, 'Align bottom',
                VsdxVertAlign.bottom),
          ],
        ),
        const SizedBox(height: 8),
        Text('Line spacing', style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        Builder(
          builder: (context) {
            final spacing =
                controller.selectedParaStyle?.lineSpacing ?? 1.0;
            return Wrap(
              spacing: 4,
              children: [
                for (final m in const <double>[1.0, 1.15, 1.5, 2.0])
                  ChoiceChip(
                    label: Text(
                      m == m.roundToDouble()
                          ? '${m.toInt()}×'
                          : '$m×',
                      style: const TextStyle(fontSize: 11),
                    ),
                    selected: (spacing - m).abs() < 0.01,
                    onSelected: (_) => controller.setLineSpacing(m),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Text('Space before', style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        _paraSpaceChips(
          inches: controller.selectedParaStyle?.spaceBeforeInches ?? 0,
          onChanged: controller.setSpaceBeforeInches,
        ),
        const SizedBox(height: 6),
        Text('Space after', style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        _paraSpaceChips(
          inches: controller.selectedParaStyle?.spaceAfterInches ?? 0,
          onChanged: controller.setSpaceAfterInches,
        ),
      ],
    );
  }

  Widget _paraSpaceChips({
    required double inches,
    required ValueChanged<double> onChanged,
  }) {
    const pts = <int>[0, 6, 12, 18];
    final curPt = (inches * 72).round();
    return Wrap(
      spacing: 4,
      children: [
        for (final p in pts)
          ChoiceChip(
            label: Text('$p pt', style: const TextStyle(fontSize: 11)),
            selected: curPt == p,
            onSelected: (_) => onChanged(p / 72.0),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
      ],
    );
  }

  static const List<String> _fonts = <String>[
    'Arial',
    'Calibri',
    'Times New Roman',
    'Courier New',
    'Georgia',
    'Verdana',
    'Comic Sans MS',
  ];

  Widget _fontDropdown(VsdxCharStyle cs) {
    final current = cs.fontFamily;
    final items = <String>{..._fonts, ?current}.toList();
    return Row(
      children: [
        const Icon(Icons.font_download_outlined, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButton<String>(
            value: current != null && items.contains(current) ? current : null,
            isExpanded: true,
            isDense: true,
            hint: const Text('Default'),
            items: [
              for (final f in items)
                DropdownMenuItem<String>(
                  value: f,
                  child: Text(f, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (f) {
              if (f != null) controller.setFontFamily(f);
            },
          ),
        ),
      ],
    );
  }

  IconButton _vAlignBtn(IconData icon, String tip, VsdxVertAlign v) =>
      IconButton(
        onPressed: () => controller.setTextVerticalAlign(v),
        isSelected: controller.selectedVerticalAlign == v,
        icon: Icon(icon),
        tooltip: tip,
        visualDensity: VisualDensity.compact,
      );

  Widget _swatchRow({
    required void Function(int argb) onColor,
    required VoidCallback onNone,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final argb in _swatches)
          _SwatchButton(color: Color(argb), onTap: () => onColor(argb)),
        InkWell(
          onTap: onNone,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey),
            ),
            child: const Icon(Icons.block, size: 18),
          ),
        ),
      ],
    );
  }

  /// Theme accent strip — resolves against the document theme (Office defaults
  /// when empty) so picking a swatch binds the shape to that slot.
  Widget _themeSwatchRow({
    required EditorController controller,
    required void Function(int slot) onSlot,
    int? selectedSlot,
  }) {
    final theme = controller.documentTheme.isEmpty
        ? VsdxTheme.office
        : controller.documentTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Theme',
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final slot in VsdxTheme.accentSlots)
              if (theme.resolve(slot) case final c?)
                _SwatchButton(
                  color: Color(c.value),
                  selected: selectedSlot == slot,
                  onTap: () => onSlot(slot),
                ),
          ],
        ),
      ],
    );
  }

  static const Map<int, String> _dashPresets = <int, String>{
    1: 'Solid',
    2: 'Dashed',
    3: 'Dotted',
    4: 'Dash-dot',
  };

  Widget _dashDropdown(EditorController controller) {
    final pattern = controller.selectedLine?.pattern ?? 1;
    final value = _dashPresets.containsKey(pattern) ? pattern : 1;
    return Row(
      children: [
        const Icon(Icons.line_style, size: 18),
        const SizedBox(width: 8),
        DropdownButton<int>(
          value: value,
          isDense: true,
          items: [
            for (final e in _dashPresets.entries)
              DropdownMenuItem<int>(value: e.key, child: Text(e.value)),
          ],
          onChanged: (p) {
            if (p != null) controller.setLinePattern(p);
          },
        ),
      ],
    );
  }

  static const Map<int, String> _compoundTypes = <int, String>{
    0: 'Single',
    1: 'Double',
    2: 'Thick-thin',
    3: 'Thin-thick',
  };

  Widget _compoundTypeRow(EditorController controller) {
    final type = controller.selectedLine?.compoundType ?? 0;
    final value = _compoundTypes.containsKey(type) ? type : 0;
    return Row(
      children: [
        const Icon(Icons.line_weight, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButton<int>(
            value: value,
            isExpanded: true,
            isDense: true,
            items: [
              for (final e in _compoundTypes.entries)
                DropdownMenuItem<int>(value: e.key, child: Text(e.value)),
            ],
            onChanged: (t) {
              if (t != null) controller.setCompoundType(t);
            },
          ),
        ),
      ],
    );
  }

  /// Curated arrowhead types (Visio `BeginArrow`/`EndArrow` ids → labels),
  /// mirroring drawio's start/end arrow menus.
  static const Map<int, String> _arrowTypes = <int, String>{
    0: 'None',
    4: 'Filled',
    1: 'Open',
    3: 'Thin',
    7: 'Stealth',
    10: 'Circle',
    11: 'Open diamond',
    14: 'Circle (open)',
  };

  Widget _arrowPickers(EditorController controller) {
    final line = controller.selectedLine;
    final begin = line?.beginArrow ?? 0;
    final end = line?.endArrow ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(
                width: 40,
                child: Text('Start', style: TextStyle(fontSize: 12))),
            Expanded(
              child: _arrowDropdown(
                  begin, controller.setBeginArrow, flip: true),
            ),
          ],
        ),
        if (begin != 0) ...[
          const SizedBox(height: 4),
          _arrowSizeRow(
            line?.beginArrowSizeInches ?? 0.125,
            controller.setBeginArrowSize,
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            const SizedBox(
                width: 40,
                child: Text('End', style: TextStyle(fontSize: 12))),
            Expanded(
              child:
                  _arrowDropdown(end, controller.setEndArrow, flip: false),
            ),
          ],
        ),
        if (end != 0) ...[
          const SizedBox(height: 4),
          _arrowSizeRow(
            line?.endArrowSizeInches ?? 0.125,
            controller.setEndArrowSize,
          ),
        ],
      ],
    );
  }

  Widget _arrowSizeRow(double inches, ValueChanged<double> onChanged) {
    final buckets = EditorController.arrowSizeBuckets;
    var selected = 2;
    var best = double.infinity;
    for (var i = 0; i < buckets.length; i++) {
      final d = (buckets[i] - inches).abs();
      if (d < best) {
        best = d;
        selected = i;
      }
    }
    return Wrap(
      spacing: 4,
      children: [
        for (var i = 0; i < buckets.length; i++)
          ChoiceChip(
            label: Text('${i + 1}', style: const TextStyle(fontSize: 11)),
            selected: selected == i,
            onSelected: (_) => onChanged(buckets[i]),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
      ],
    );
  }

  /// Fill pattern chips: solid + common Visio hatches (draw.io Style → Fill).
  Widget _fillPatternControls(EditorController controller) {
    final pattern = controller.selectedFill?.pattern ?? 1;
    const labels = <int, String>{
      1: 'Solid',
      2: 'H',
      3: 'V',
      4: '/',
      5: '\\',
      6: 'X',
      7: '+',
      8: '·',
      9: '::',
      10: 'Brick',
      11: 'Shingle',
      14: 'Grid',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final e in labels.entries)
            ChoiceChip(
              label: Text(e.value, style: const TextStyle(fontSize: 11)),
              selected: pattern == e.key,
              onSelected: (_) => controller.setFillPattern(e.key),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
        ],
      ),
    );
  }

  Widget _arrowDropdown(
    int value,
    ValueChanged<int> onChanged, {
    required bool flip,
  }) {
    final ids = <int>{..._arrowTypes.keys, value}.toList()..sort();
    String label(int id) => _arrowTypes[id] ?? 'Arrow #$id';
    return DropdownButton<int>(
      value: value,
      isExpanded: true,
      isDense: true,
      items: [
        for (final id in ids)
          DropdownMenuItem<int>(
            value: id,
            child: Row(
              children: [
                SizedBox(
                  width: 38,
                  height: 14,
                  child: id == 0
                      ? const SizedBox.shrink()
                      : _ArrowPreview(arrowId: id, flip: flip),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label(id),
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

/// A named paper size (portrait width × height, inches).
class _Paper {
  const _Paper(this.name, this.width, this.height);
  final String name;
  final double width;
  final double height;
}

/// Right-hand Format panel shown when nothing is selected — drawio's "Diagram"
/// tab: grid / snap toggles, page background colour, and paper size (preset +
/// orientation + custom width/height). All changes round-trip via the writer.
class _PageFormatPanel extends StatelessWidget {
  const _PageFormatPanel({required this.controller});

  final EditorController controller;

  static const List<int> _backgrounds = <int>[
    0xFFFFFFFF,
    0xFFF5F5F5,
    0xFFFFF9C4,
    0xFFE3F2FD,
    0xFFE8F5E9,
    0xFFFCE4EC,
    0xFF37474F,
    0xFF000000,
  ];

  /// Common paper sizes as portrait (width, height) in inches.
  static const List<_Paper> _papers = <_Paper>[
    _Paper('Letter', 8.5, 11),
    _Paper('Legal', 8.5, 14),
    _Paper('Tabloid', 11, 17),
    _Paper('A3', 11.69, 16.54),
    _Paper('A4', 8.27, 11.69),
    _Paper('A5', 5.83, 8.27),
    _Paper('A6', 4.13, 5.83),
    _Paper('B4', 9.84, 13.9),
    _Paper('B5', 6.93, 9.84),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = controller.pageSize;
    if (size == null) return const SizedBox(width: 232);
    final w = size.width;
    final h = size.height;
    final landscape = controller.pageIsLandscape;
    final matched = _matchPaper(w, h);
    final bg = controller.pageBackgroundColor;

    return SizedBox(
      width: 232,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Diagram', style: theme.textTheme.titleSmall),
          const SizedBox(height: 16),
          Text('View', style: theme.textTheme.labelLarge),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Grid'),
            value: controller.showGrid,
            onChanged: (_) => controller.toggleGrid(),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Snap to grid'),
            value: controller.snapToGrid,
            onChanged: (_) => controller.toggleSnap(),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Line jumps'),
            value: controller.showLineJumps,
            onChanged: (_) => controller.toggleLineJumps(),
          ),
          if (controller.showLineJumps)
            _RangeSlider(
              label: 'Jump r',
              value: controller.lineJumpRadiusInches,
              min: 0.02,
              max: 0.2,
              format: (v) => '${(v * 100).round() / 100}"',
              onStart: () {},
              onChanged: controller.setLineJumpRadius,
              onEnd: () {},
            ),
          const SizedBox(height: 16),
          Text('Background', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final argb in _backgrounds)
                _SwatchButton(
                  color: Color(argb),
                  selected: bg?.value == argb,
                  onTap: () => controller.setBackgroundColor(VsdxColor(argb)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Background page'),
            subtitle: const Text('Use as underlay for other pages'),
            value: controller.currentPage?.isBackgroundPage ?? false,
            onChanged: controller.setPageIsBackground,
          ),
          if (!(controller.currentPage?.isBackgroundPage ?? false) &&
              controller.backgroundPageOptions.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Use background', style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            DropdownButton<int?>(
              value: controller.currentPage?.backgroundPageId,
              isExpanded: true,
              isDense: true,
              hint: const Text('None'),
              items: <DropdownMenuItem<int?>>[
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('None'),
                ),
                for (final p in controller.backgroundPageOptions)
                  DropdownMenuItem<int?>(
                    value: p.id,
                    child: Text(
                      p.isBackgroundPage ? p.name : '${p.name} (will mark bg)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: controller.setBackgroundPage,
            ),
          ],
          const SizedBox(height: 16),
          Text('Theme', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          DropdownButton<String>(
            value: _matchedBuiltinThemeName(controller.documentTheme),
            isExpanded: true,
            isDense: true,
            hint: Text(
              controller.documentTheme.isEmpty ? 'None (default)' : 'Custom',
            ),
            items: [
              for (final t in VsdxTheme.builtins)
                DropdownMenuItem<String>(
                  value: t.name,
                  child: Row(
                    children: [
                      for (final slot in const [
                        ThemeSlot.accent1,
                        ThemeSlot.accent2,
                        ThemeSlot.accent3,
                        ThemeSlot.accent4,
                      ])
                        if (t.theme.resolve(slot) case final c?)
                          Container(
                            width: 14,
                            height: 14,
                            margin: const EdgeInsets.only(right: 3),
                            decoration: BoxDecoration(
                              color: Color(c.value),
                              borderRadius: BorderRadius.circular(2),
                              border: Border.all(color: Colors.black26),
                            ),
                          ),
                      const SizedBox(width: 6),
                      Text(t.name),
                    ],
                  ),
                ),
            ],
            onChanged: (name) {
              if (name == null) return;
              final match = VsdxTheme.builtins.where((t) => t.name == name);
              if (match.isNotEmpty) {
                controller.setDocumentTheme(match.first.theme);
              }
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final slot in VsdxTheme.accentSlots)
                if ((controller.documentTheme.isEmpty
                        ? VsdxTheme.office
                        : controller.documentTheme)
                    .resolve(slot)
                    case final c?)
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Color(c.value),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: Colors.black26),
                    ),
                  ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Paper Size', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          DropdownButton<_Paper>(
            value: matched,
            isExpanded: true,
            isDense: true,
            hint: const Text('Custom'),
            items: [
              for (final p in _papers)
                DropdownMenuItem<_Paper>(
                  value: p,
                  child: Text(
                    '${p.name}   ${_dim(p.width)} × ${_dim(p.height)} in',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (p) {
              if (p == null) return;
              controller.setPageSize(
                landscape ? p.height : p.width,
                landscape ? p.width : p.height,
              );
            },
          ),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment<bool>(value: false, label: Text('Portrait')),
              ButtonSegment<bool>(value: true, label: Text('Landscape')),
            ],
            selected: <bool>{landscape},
            onSelectionChanged: (s) => controller.setPageLandscape(s.first),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _NumField(
                  label: 'W',
                  value: w,
                  onSubmit: (v) => controller.setPageSize(v, h),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumField(
                  label: 'H',
                  value: h,
                  onSubmit: (v) => controller.setPageSize(w, v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Name of a [VsdxTheme.builtins] entry that matches [theme], or `null`.
  String? _matchedBuiltinThemeName(VsdxTheme theme) {
    if (theme.isEmpty) return null;
    for (final t in VsdxTheme.builtins) {
      if (t.theme.colors.length != theme.colors.length) continue;
      final same = t.theme.colors.entries
          .every((e) => theme.colors[e.key]?.value == e.value.value);
      if (same) return t.name;
    }
    return null;
  }

  /// The preset matching (w, h) in either orientation, or `null` for a custom
  /// size.
  _Paper? _matchPaper(double w, double h) {
    final lo = math.min(w, h);
    final hi = math.max(w, h);
    for (final p in _papers) {
      if ((p.width - lo).abs() < 0.05 && (p.height - hi).abs() < 0.05) {
        return p;
      }
    }
    return null;
  }

  static String _dim(double v) {
    final r = (v * 100).round() / 100;
    return r == r.roundToDouble() ? r.toInt().toString() : '$r';
  }
}

/// Small preview of an arrowhead ([arrowId]) drawn at the end of a stub line.
/// When [flip] is set the head points left (used for the start arrow).
class _ArrowPreview extends StatelessWidget {
  const _ArrowPreview({required this.arrowId, this.flip = false});

  final int arrowId;
  final bool flip;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(38, 14),
      painter: _ArrowPreviewPainter(
        arrowId,
        Theme.of(context).colorScheme.onSurface,
        flip,
      ),
    );
  }
}

class _ArrowPreviewPainter extends CustomPainter {
  _ArrowPreviewPainter(this.id, this.color, this.flip);

  final int id;
  final Color color;
  final bool flip;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final line = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(2, y), Offset(size.width - 2, y), line);
    if (id == 0) return;
    final d = arrowDescriptor(id);
    if (d == null) return;
    const s = 9.0;
    final tipX = flip ? 2.0 : size.width - 2;
    canvas
      ..save()
      ..translate(tipX, y)
      ..scale(flip ? -s : s, s);
    final p = Paint()
      ..color = color
      ..style = d.filled ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = 1.2 / s;
    canvas
      ..drawPath(d.path, p)
      ..restore();
  }

  @override
  bool shouldRepaint(covariant _ArrowPreviewPainter old) =>
      old.id != id || old.color != color || old.flip != flip;
}

/// Corner-radius slider with a local drag value so the thumb tracks the cursor
/// while geometry rebuilds on the canvas.
class _CornersSlider extends StatefulWidget {
  const _CornersSlider({
    required this.value,
    required this.max,
    required this.onStart,
    required this.onChanged,
    required this.onEnd,
  });

  final double value;
  final double max;
  final VoidCallback onStart;
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;

  @override
  State<_CornersSlider> createState() => _CornersSliderState();
}

class _CornersSliderState extends State<_CornersSlider> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final maxR = widget.max;
    final v = (_drag ?? widget.value).clamp(0.0, maxR);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            const SizedBox(
                width: 48,
                child: Text('Corners', style: TextStyle(fontSize: 11))),
            Expanded(
              child: Slider(
                value: v,
                max: maxR,
                onChangeStart: (_) {
                  _drag = widget.value.clamp(0.0, maxR);
                  widget.onStart();
                },
                onChanged: (x) {
                  setState(() => _drag = x);
                  widget.onChanged(x);
                },
                onChangeEnd: (_) {
                  setState(() => _drag = null);
                  widget.onEnd();
                },
              ),
            ),
            SizedBox(
              width: 34,
              child: Text(
                '${(v * 100).round() / 100}"',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Compact numeric range slider with transactional live preview (one undo step).
class _RangeSlider extends StatefulWidget {
  const _RangeSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onStart,
    required this.onChanged,
    required this.onEnd,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String Function(double) format;
  final VoidCallback onStart;
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;

  @override
  State<_RangeSlider> createState() => _RangeSliderState();
}

class _RangeSliderState extends State<_RangeSlider> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final v = (_drag ?? widget.value).clamp(widget.min, widget.max);
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(widget.label, style: const TextStyle(fontSize: 11)),
        ),
        Expanded(
          child: Slider(
            value: v,
            min: widget.min,
            max: widget.max,
            onChangeStart: (_) {
              _drag = widget.value.clamp(widget.min, widget.max);
              widget.onStart();
            },
            onChanged: (x) {
              setState(() => _drag = x);
              widget.onChanged(x);
            },
            onChangeEnd: (_) {
              setState(() => _drag = null);
              widget.onEnd();
            },
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            widget.format(v),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }
}

/// Compact opacity slider (0–100%) with transactional live preview so the drag
/// records a single undo step.
///
/// Keeps a local drag value so the thumb stays under the cursor even when the
/// parent tree is busy painting the canvas.
class _OpacitySlider extends StatefulWidget {
  const _OpacitySlider({
    required this.label,
    required this.opacity,
    required this.onStart,
    required this.onChanged,
    required this.onEnd,
  });

  final String label;
  final double opacity;
  final VoidCallback onStart;
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;

  @override
  State<_OpacitySlider> createState() => _OpacitySliderState();
}

class _OpacitySliderState extends State<_OpacitySlider> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final v = (_drag ?? widget.opacity).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(widget.label, style: const TextStyle(fontSize: 11)),
        ),
        Expanded(
          child: Slider(
            value: v,
            onChangeStart: (_) {
              _drag = widget.opacity.clamp(0.0, 1.0);
              widget.onStart();
            },
            onChanged: (x) {
              setState(() => _drag = x);
              widget.onChanged(x);
            },
            onChangeEnd: (_) {
              setState(() => _drag = null);
              widget.onEnd();
            },
          ),
        ),
        SizedBox(
          width: 32,
          child: Text(
            '${(v * 100).round()}%',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }
}

/// A compact numeric text field for the Arrange panel. Reflects an external
/// [value] while idle, and commits the parsed number on Enter or focus loss.
class _NumField extends StatefulWidget {
  const _NumField({
    required this.label,
    required this.value,
    required this.onSubmit,
  });

  final String label;
  final double value;
  final ValueChanged<double> onSubmit;

  @override
  State<_NumField> createState() => _NumFieldState();
}

class _NumFieldState extends State<_NumField> {
  late final TextEditingController _c =
      TextEditingController(text: _fmt(widget.value));
  late final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(covariant _NumField old) {
    super.didUpdateWidget(old);
    // Refresh from the model unless the user is actively editing this field.
    if (!_focus.hasFocus && widget.value != old.value) {
      _c.text = _fmt(widget.value);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final v = double.tryParse(_c.text.trim());
    if (v != null && v != widget.value) {
      widget.onSubmit(v);
    } else {
      _c.text = _fmt(widget.value);
    }
  }

  static String _fmt(double v) {
    final r = (v * 100).roundToDouble() / 100;
    return r == r.roundToDouble() ? r.toInt().toString() : '$r';
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      focusNode: _focus,
      keyboardType: const TextInputType.numberWithOptions(
          signed: true, decimal: true),
      textAlign: TextAlign.right,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        prefixText: '${widget.label} ',
        prefixStyle: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: const OutlineInputBorder(),
      ),
      onSubmitted: (_) => _commit(),
    );
  }
}

/// Floating Find / Replace bar (draw.io Cmd+F / Cmd+H). Filters shapes by
/// text/name across all pages, cycles matches, and can replace labels.
class _FindBar extends StatefulWidget {
  const _FindBar({
    required this.controller,
    required this.showReplace,
    required this.onToggleReplace,
    required this.onClose,
  });

  final EditorController controller;
  final bool showReplace;
  final VoidCallback onToggleReplace;
  final VoidCallback onClose;

  @override
  State<_FindBar> createState() => _FindBarState();
}

class _FindBarState extends State<_FindBar> {
  final TextEditingController _text = TextEditingController();
  final TextEditingController _replace = TextEditingController();
  final FocusNode _focus = FocusNode();
  final FocusNode _replaceFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _text.text = widget.controller.findQuery;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.showReplace) {
        _replaceFocus.requestFocus();
      } else {
        _focus.requestFocus();
      }
    });
  }

  @override
  void didUpdateWidget(covariant _FindBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showReplace && !oldWidget.showReplace) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _replaceFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _replace.dispose();
    _focus.dispose();
    _replaceFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      color: scheme.surface,
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final count = widget.controller.findMatchCount;
          final ord = widget.controller.findCurrentOrdinal;
          final pageIdx = widget.controller.findCurrentPageIndex;
          final multiPage = widget.controller.pageCount > 1;
          final label = count == 0
              ? (widget.controller.findQuery.trim().isEmpty ? '' : 'No results')
              : (multiPage && pageIdx != null)
                  ? '$ord/$count · p${pageIdx + 1}'
                  : '$ord / $count';
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.search, size: 18),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 180,
                      child: CallbackShortcuts(
                        bindings: <ShortcutActivator, VoidCallback>{
                          const SingleActivator(LogicalKeyboardKey.escape):
                              widget.onClose,
                        },
                        child: TextField(
                          controller: _text,
                          focusNode: _focus,
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'Find shapes…',
                            border: InputBorder.none,
                          ),
                          onChanged: widget.controller.updateFind,
                          onSubmitted: (_) {
                            if (HardwareKeyboard.instance.isShiftPressed) {
                              widget.controller.findPrevious();
                            } else {
                              widget.controller.findNext();
                            }
                          },
                        ),
                      ),
                    ),
                    SizedBox(
                      width: multiPage ? 72 : 56,
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                    ),
                    IconButton(
                      onPressed: () => widget.controller.setFindMatchCase(
                        !widget.controller.findMatchCase,
                      ),
                      icon: Text(
                        'Aa',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: widget.controller.findMatchCase
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      tooltip: widget.controller.findMatchCase
                          ? 'Match case: on'
                          : 'Match case: off',
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      onPressed: () => widget.controller.setFindWholeWord(
                        !widget.controller.findWholeWord,
                      ),
                      icon: Text(
                        'W',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: widget.controller.findWholeWord
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      tooltip: widget.controller.findWholeWord
                          ? 'Whole word: on'
                          : 'Whole word: off',
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      onPressed:
                          count == 0 ? null : widget.controller.findPrevious,
                      icon: const Icon(Icons.keyboard_arrow_up),
                      tooltip: 'Previous (Shift+Enter)',
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      onPressed: count == 0 ? null : widget.controller.findNext,
                      icon: const Icon(Icons.keyboard_arrow_down),
                      tooltip: 'Next (Enter)',
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      onPressed: widget.onToggleReplace,
                      icon: Icon(
                        widget.showReplace
                            ? Icons.expand_less
                            : Icons.find_replace,
                        size: 18,
                      ),
                      tooltip: widget.showReplace
                          ? 'Hide replace'
                          : 'Show replace (Cmd+H)',
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Close (Esc)',
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                if (widget.showReplace) ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: 24),
                      SizedBox(
                        width: 180,
                        child: TextField(
                          controller: _replace,
                          focusNode: _replaceFocus,
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'Replace with…',
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => widget.controller
                              .replaceFind(_replace.text),
                        ),
                      ),
                      TextButton(
                        onPressed: count == 0
                            ? null
                            : () => widget.controller
                                .replaceFind(_replace.text),
                        child: const Text('Replace'),
                      ),
                      TextButton(
                        onPressed: widget.controller.findQuery.trim().isEmpty
                            ? null
                            : () => widget.controller
                                .replaceAllFind(_replace.text),
                        child: const Text('All'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SwatchButton extends StatelessWidget {
  const _SwatchButton({
    required this.color,
    required this.onTap,
    this.selected = false,
  });

  final Color color;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? scheme.primary : Colors.grey.shade500,
            width: selected ? 2 : 1,
          ),
        ),
      ),
    );
  }
}
