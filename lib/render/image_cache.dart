/// Decode `VsdxImage` bytes into [ui.Image] handles, with a per-document
/// cache keyed by part name.
///
/// `ui.instantiateImageCodec` is async; the painter wants sync access. So
/// we maintain a small cache: the first paint kicks off the decode and
/// triggers a repaint via the cache's [Listenable] when the image is
/// ready.
///
/// EMF / WMF / OLE: try embedded-bitmap extraction first, then vector
/// metafile replay ([parseMetafileDrawing] → [rasterizeMetafileDrawing]).
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'package:vsdx/vsdx.dart';

import 'metafile_rasterizer.dart';

class VsdxImageCache extends ChangeNotifier {
  VsdxImageCache();

  /// Drop all entries (used when the viewer switches to a new document).
  void clear() {
    for (final img in _ready.values) {
      img.dispose();
    }
    _ready.clear();
    _pending.clear();
    for (final c in _waiters.values) {
      if (!c.isCompleted) c.complete();
    }
    _waiters.clear();
  }

  /// Already-decoded entries, by part name.
  final Map<String, ui.Image> _ready = <String, ui.Image>{};

  /// Part names whose decode is in flight (avoids duplicate work).
  final Set<String> _pending = <String>{};

  /// Completers awaited by [warmUp] / [decode] for in-flight part names.
  final Map<String, Completer<void>> _waiters = <String, Completer<void>>{};

  /// Monotonic counter bumped on every successful decode — lets the page
  /// picture cache know when to invalidate without comparing image handles.
  int _decodeEpoch = 0;
  int get decodeEpoch => _decodeEpoch;

  /// Synchronous getter for the painter. Returns the decoded image if
  /// available, otherwise kicks off the decode and returns `null`.
  ui.Image? lookup(VsdxImage src) {
    final cached = _ready[src.partName];
    if (cached != null) return cached;
    if (_pending.contains(src.partName)) return null;
    unawaited(decode(src));
    return null;
  }

  /// Awaitable decode used by PNG export / snapshots so embedded pictures
  /// are ready before the first (and only) paint pass.
  Future<ui.Image?> decode(VsdxImage src) async {
    final cached = _ready[src.partName];
    if (cached != null) return cached;
    final existing = _waiters[src.partName];
    if (existing != null) {
      await existing.future;
      return _ready[src.partName];
    }
    final waiter = Completer<void>();
    _waiters[src.partName] = waiter;
    _pending.add(src.partName);
    try {
      final raster = src.rasterForRendering();
      if (raster != null) {
        await _decodeRaster(src, raster.bytes, clearPending: false);
      } else {
        await _decodeMetafile(src, managePending: false);
      }
    } finally {
      _pending.remove(src.partName);
      _waiters.remove(src.partName);
      if (!waiter.isCompleted) waiter.complete();
    }
    return _ready[src.partName];
  }

  /// Decode every image in [images] (best-effort; failures leave placeholders).
  Future<void> warmUp(ImageRegistry images) async {
    if (images.all.isEmpty) return;
    await Future.wait(<Future<void>>[
      for (final src in images.all) decode(src),
    ]);
  }

  Future<void> _decodeMetafile(
    VsdxImage src, {
    bool managePending = true,
  }) async {
    if (managePending) _pending.add(src.partName);
    try {
      final metafileBytes = Uint8List.fromList(src.bytes);
      final drawing = parseMetafileDrawing(
        metafileBytes,
        mimeType: src.mimeType,
        partName: src.partName,
      );
      if (drawing != null && !drawing.isEmpty) {
        final image = await rasterizeMetafileDrawing(
          drawing,
          backgroundColor: isOleWorkbook(metafileBytes)
              ? const ui.Color(libreOfficeOleWorkbookBackgroundArgb)
              : const ui.Color(0x00000000),
        );
        if (image != null) {
          _ready[src.partName] = image;
          _decodeEpoch++;
          notifyListeners();
          return;
        }
      }
      // Last chance for malformed bitmap-wrapper metafiles whose display list
      // could not be reconstructed safely.
      final raster = extractMetafileRaster(
        metafileBytes,
        mimeType: src.mimeType,
      );
      if (raster != null) {
        await _decodeRaster(src, raster, clearPending: false);
        return;
      }
    } catch (_) {
      // Leave pending cleared in finally; painter keeps the placeholder.
    } finally {
      if (managePending) _pending.remove(src.partName);
    }
  }

  Future<void> _decodeRaster(
    VsdxImage src,
    List<int> bytes, {
    bool clearPending = true,
  }) async {
    try {
      final codec = await ui.instantiateImageCodec(
        Uint8List.fromList(bytes),
      );
      try {
        final frame = await codec.getNextFrame();
        _ready[src.partName] = frame.image;
        _decodeEpoch++;
        notifyListeners();
      } finally {
        codec.dispose();
      }
    } catch (_) {
      // Decoding failure — renderer falls back to its placeholder.
    } finally {
      if (clearPending) _pending.remove(src.partName);
    }
  }

  @override
  void dispose() {
    clear();
    super.dispose();
  }
}
