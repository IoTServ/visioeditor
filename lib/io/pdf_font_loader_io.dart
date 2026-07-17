import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

pw.Font? _cached;

/// Load a Unicode-capable TTF/OTF for PDF text (CJK etc.).
///
/// Prefers common desktop system fonts so SVG→PDF export does not fall back
/// to Helvetica, which cannot encode non-Latin characters.
Future<pw.Font?> loadPdfUnicodeFont() async {
  if (_cached != null) return _cached;
  for (final path in _candidates()) {
    final file = File(path);
    if (!file.existsSync()) continue;
    try {
      final bytes = file.readAsBytesSync();
      // TTC collections are not supported by [pw.Font.ttf].
      if (path.toLowerCase().endsWith('.ttc')) continue;
      _cached = pw.Font.ttf(ByteData.sublistView(bytes));
      return _cached;
    } catch (_) {
      // Try the next candidate.
    }
  }
  return null;
}

List<String> _candidates() {
  if (Platform.isMacOS) {
    return const <String>[
      '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
      '/Library/Fonts/Arial Unicode.ttf',
      '/System/Library/Fonts/Supplemental/Arial.ttf',
      '/Library/Fonts/Arial.ttf',
    ];
  }
  if (Platform.isWindows) {
    final windir = Platform.environment['WINDIR'] ?? r'C:\Windows';
    return <String>[
      '$windir\\Fonts\\msyh.ttf',
      '$windir\\Fonts\\msyhbd.ttf',
      '$windir\\Fonts\\simhei.ttf',
      '$windir\\Fonts\\arialuni.ttf',
      '$windir\\Fonts\\arial.ttf',
    ];
  }
  if (Platform.isLinux) {
    return const <String>[
      '/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.otf',
      '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.otf',
      '/usr/share/fonts/truetype/noto/NotoSansSC-Regular.otf',
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
      '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf',
    ];
  }
  return const <String>[];
}
