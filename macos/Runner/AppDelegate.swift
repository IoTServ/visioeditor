import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// Finder double-click, "Open With", and `open drawing.vsdx` deliver the
  /// document URLs here on modern macOS (10.13+). We still let Flutter plugins
  /// process any URLs they registered for (via `super`), then forward local
  /// file paths to the Dart side through the file-open bridge.
  override func application(_ application: NSApplication, open urls: [URL]) {
    super.application(application, open: urls)
    let paths = urls.filter { $0.isFileURL }.map { $0.path }
    if !paths.isEmpty {
      FileOpenBridge.shared.open(paths)
    }
  }
}

/// Bridges native "open document" events to the Flutter side over a
/// `FlutterMethodChannel`. Because a document open can arrive before the Dart
/// isolate has installed its handler (cold launch from Finder), paths are
/// buffered until Dart signals `ready`, then flushed.
final class FileOpenBridge {
  static let shared = FileOpenBridge()
  private init() {}

  private var channel: FlutterMethodChannel?
  private var pending: [String] = []
  private var isReady = false

  /// Wire up the channel created alongside the FlutterViewController.
  func attach(_ channel: FlutterMethodChannel) {
    self.channel = channel
  }

  /// Dart calls this (via the channel) once its handler is installed.
  func markReady() {
    isReady = true
    flush()
  }

  /// Queue document paths and deliver them when possible.
  func open(_ paths: [String]) {
    pending.append(contentsOf: paths)
    flush()
  }

  private func flush() {
    guard isReady, let channel = channel, !pending.isEmpty else { return }
    let paths = pending
    pending.removeAll()
    channel.invokeMethod("openFiles", arguments: paths)
  }
}
