import 'package:shared_preferences/shared_preferences.dart';

/// Persists the most-recently opened / saved file paths (most recent first).
class RecentFiles {
  static const String _key = 'recent_files';
  static const int _max = 10;

  Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? const <String>[];
  }

  Future<List<String>> add(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final list = (prefs.getStringList(_key) ?? <String>[])
        .where((e) => e != path)
        .toList()
      ..insert(0, path);
    if (list.length > _max) list.removeRange(_max, list.length);
    await prefs.setStringList(_key, list);
    return list;
  }
}
