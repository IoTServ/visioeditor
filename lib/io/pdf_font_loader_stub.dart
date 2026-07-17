import 'package:pdf/widgets.dart' as pw;

/// Web / non-IO platforms: no system font probe.
Future<pw.Font?> loadPdfUnicodeFont() async => null;
