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
  }

  /// Already-decoded entries, by part name.
  final Map<String, ui.Image> _ready = <String, ui.Image>{};

  /// Part names whose decode is in flight (avoids duplicate work).
  final Set<String> _pending = <String>{};

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
    if (src.isFlutterDecodable) {
      _pending.add(src.partName);
      _decodeRaster(src, src.bytes);
      return null;
    }
    _pending.add(src.partName);
    _decodeMetafile(src);
    return null;
  }

  Future<void> _decodeMetafile(VsdxImage src) async {
    try {
      // 1) Wrapped DIB inside EMF (or OLE→EMF).
      final raster = extractMetafileRaster(
        Uint8List.fromList(src.bytes),
        mimeType: src.mimeType,
      );
      if (raster != null) {
        await _decodeRaster(src, raster, clearPending: false);
        return;
      }
      // 2) Vector WMF / EMF / OLE presentation replay.
      final drawing = parseMetafileDrawing(
        Uint8List.fromList(src.bytes),
        mimeType: src.mimeType,
        partName: src.partName,
      );
      if (drawing == null || drawing.isEmpty) return;
      final image = await rasterizeMetafileDrawing(drawing);
      if (image == null) return;
      _ready[src.partName] = image;
      _decodeEpoch++;
      notifyListeners();
    } catch (_) {
      // Leave pending cleared in finally; painter keeps the placeholder.
    } finally {
      _pending.remove(src.partName);
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
      final frame = await codec.getNextFrame();
      _ready[src.partName] = frame.image;
      _decodeEpoch++;
      notifyListeners();
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
