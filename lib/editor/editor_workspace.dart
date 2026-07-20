import 'package:flutter/foundation.dart';

import 'editor_controller.dart';

/// Holds every open document (each its own [EditorController]) and the active
/// tab. Re-broadcasts child-controller changes so the UI can listen to just
/// the workspace.
class EditorWorkspace extends ChangeNotifier {
  final List<EditorController> _docs = <EditorController>[];
  int _activeIndex = -1;

  List<EditorController> get docs => List<EditorController>.unmodifiable(_docs);
  int get activeIndex => _activeIndex;
  bool get hasDocs => _docs.isNotEmpty;

  EditorController? get active =>
      (_activeIndex >= 0 && _activeIndex < _docs.length)
          ? _docs[_activeIndex]
          : null;

  EditorController _add() {
    final c = EditorController()..addListener(notifyListeners);
    _docs.add(c);
    _activeIndex = _docs.length - 1;
    return c;
  }

  /// Open a new blank drawing in a new tab.
  void newDocument() {
    _add().newDocument();
    notifyListeners();
  }

  /// Open [bytes] in a new tab. The returned controller carries an `error`
  /// when parsing failed (the tab is still created so the caller can react).
  Future<EditorController> openBytes(
    Uint8List bytes, {
    String? path,
    String? name,
  }) async {
    final c = _add();
    await c.openBytes(bytes, path: path, name: name);
    notifyListeners();
    return c;
  }

  void setActive(int index) {
    if (index >= 0 && index < _docs.length && index != _activeIndex) {
      _activeIndex = index;
      notifyListeners();
    }
  }

  /// Reorder open tabs. [newIndex] is the destination index after removal
  /// (same contract as [ReorderableListView.onReorderItem] / page [movePage]).
  void moveAt(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= _docs.length ||
        newIndex < 0 ||
        newIndex >= _docs.length ||
        oldIndex == newIndex) {
      return;
    }
    final c = _docs.removeAt(oldIndex);
    _docs.insert(newIndex, c);
    if (_activeIndex == oldIndex) {
      _activeIndex = newIndex;
    } else if (oldIndex < _activeIndex && newIndex >= _activeIndex) {
      _activeIndex -= 1;
    } else if (oldIndex > _activeIndex && newIndex <= _activeIndex) {
      _activeIndex += 1;
    }
    notifyListeners();
  }

  void closeAt(int index) {
    if (index < 0 || index >= _docs.length) return;
    final c = _docs.removeAt(index);
    c.removeListener(notifyListeners);
    c.dispose();
    _activeIndex = _docs.isEmpty ? -1 : _activeIndex.clamp(0, _docs.length - 1);
    notifyListeners();
  }

  int indexOf(EditorController c) => _docs.indexOf(c);

  @override
  void dispose() {
    for (final c in _docs) {
      c.removeListener(notifyListeners);
      c.dispose();
    }
    _docs.clear();
    super.dispose();
  }
}
