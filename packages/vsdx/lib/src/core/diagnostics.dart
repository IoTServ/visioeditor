/// Centralised logging entry point.
///
/// Layers should obtain a child logger:
/// ```dart
/// final _log = Logger('vsdx.parser.geometry');
/// ```
/// The application configures the global level once in `main()` via
/// [configureVsdxLogging].
library;

import 'package:logging/logging.dart';

/// Configure the [Logger] root level and a default record printer.
///
/// Safe to call multiple times; the listener is only attached once.
void configureVsdxLogging({Level level = Level.INFO}) {
  Logger.root.level = level;
  if (_listenerAttached) return;
  _listenerAttached = true;
  Logger.root.onRecord.listen((record) {
    // Intentionally minimal: hosting apps can override with their own listener.
    // ignore: avoid_print
    print(
      '[${record.level.name}] ${record.loggerName}: ${record.message}'
      '${record.error != null ? '\n  error: ${record.error}' : ''}',
    );
  });
}

bool _listenerAttached = false;
