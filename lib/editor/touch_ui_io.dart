import 'dart:io' show Platform;

/// Android / iOS process hosts (emulator and device).
bool get isNativeMobileOs => Platform.isAndroid || Platform.isIOS;
