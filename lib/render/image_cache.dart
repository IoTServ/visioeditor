/// Decode `VsdxImage` bytes into [ui.Image] handles, with a per-document
/// cache keyed by part name.
///
/// `ui.instantiateImageCodec` is async; the painter wants sync access. So
/// we maintain a small cache: the first paint kicks off the decode and
/// triggers a repaint via the cache's [Listenable] when the image is
/// ready.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'package:vsdx/vsdx.dart';

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
      _decode(src, src.bytes);
      return null;
    }
    // EMF/WMF: try embedded DIB extraction for canvas paint; keep original
    // media bytes untouched for vsdx round-trip.
    final m = src.mimeType.toLowerCase();
    if (m.contains('emf') || src.partName.toLowerCase().endsWith('.emf')) {
      final bmp = extractEmfEmbeddedBitmap(Uint8List.fromList(src.bytes));
      if (bmp != null) {
        _pending.add(src.partName);
        _decode(src, bmp);
        return null;
      }
    }
    return null;
  }

  Future<void> _decode(VsdxImage src, List<int> bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(
        Uint8List.fromList(bytes),
      );
      final frame = await codec.getNextFrame();
      _ready[src.partName] = frame.image;
      _decodeEpoch++;
      notifyListeners();
    } catch (_) {
      // Decoding failure — leave the entry pending so we don't retry in
      // a hot loop; the renderer falls back to its placeholder.
    } finally {
      _pending.remove(src.partName);
    }
  }

  @override
  void dispose() {
    clear();
    super.dispose();
  }
}
