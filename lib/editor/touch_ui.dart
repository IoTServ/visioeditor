import 'touch_ui_stub.dart'
    if (dart.library.io) 'touch_ui_io.dart' as impl;

/// True on Android / iOS process hosts (false on web and desktop OS hosts).
///
/// Prefer this over [defaultTargetPlatform]: Flutter widget tests force the
/// latter to Android even when the test process runs on macOS/Windows/Linux.
bool get isNativeMobileOs => impl.isNativeMobileOs;
