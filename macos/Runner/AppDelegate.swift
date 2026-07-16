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

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    // Ensure Launch Services sees this build's Info.plist (critical for Debug,
    // which lives under build/macos/... and shares document types with Release).
    LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
  }

  /// Finder double-click, "Open With", and `open drawing.vsdx` deliver the
  /// document URLs here on modern macOS (10.13+). We still let Flutter plugins
  /// process any URLs they registered for (via `super`), then forward local
  /// file paths to the Dart side through the file-open bridge.
  override func application(_ application: NSApplication, open urls: [URL]) {
    super.application(application, open: urls)
    FileOpenBridge.shared.open(urls)
  }
}

/// Bridges native "open document" events to the Flutter side over a
/// `FlutterMethodChannel`. Because a document open can arrive before the Dart
/// isolate has installed its handler (cold launch from Finder), paths are
/// buffered until Dart signals `ready`, then flushed.
///
/// Sandboxed apps receive security-scoped URLs from Launch Services; we copy
/// into the app caches directory so Dart can `File.readAsBytes` without
/// holding the scope open across the async channel hop.
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

  /// Queue document URLs (security-scoped copies) and deliver when possible.
  func open(_ urls: [URL]) {
    let paths = urls.compactMap { Self.sandboxReadablePath(for: $0) }
    guard !paths.isEmpty else { return }
    pending.append(contentsOf: paths)
    flush()
  }

  /// Legacy path-based entry (tests / callers that already have a path string).
  func open(paths: [String]) {
    pending.append(contentsOf: paths)
    flush()
  }

  private func flush() {
    guard isReady, let channel = channel, !pending.isEmpty else { return }
    let paths = pending
    pending.removeAll()
    channel.invokeMethod("openFiles", arguments: paths)
  }

  /// Copy a security-scoped file URL into Caches so Dart can read it.
  private static func sandboxReadablePath(for url: URL) -> String? {
    guard url.isFileURL else { return nil }
    let accessed = url.startAccessingSecurityScopedResource()
    defer {
      if accessed { url.stopAccessingSecurityScopedResource() }
    }

    let fm = FileManager.default
    guard let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else {
      return url.path
    }
    let destDir = caches.appendingPathComponent("opened-docs", isDirectory: true)
    do {
      try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
      let dest = destDir.appendingPathComponent(
        "\(UUID().uuidString)-\(url.lastPathComponent)")
      if fm.fileExists(atPath: dest.path) {
        try fm.removeItem(at: dest)
      }
      try fm.copyItem(at: url, to: dest)
      return dest.path
    } catch {
      // Non-scoped paths (already readable) or copy failures: fall back.
      return url.path
    }
  }
}
