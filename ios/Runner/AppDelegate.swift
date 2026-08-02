import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Cold-start open from Files / "Open in…" before the scene is connected.
    if let url = launchOptions?[.url] as? URL {
      FileOpenBridge.shared.open([url])
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    FileOpenBridge.shared.open([url])
    let flutterHandled = super.application(app, open: url, options: options)
    return url.isFileURL || flutterHandled
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "visioeditor/files",
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
    channel.setMethodCallHandler { (call, result) in
      if call.method == "ready" {
        FileOpenBridge.shared.markReady()
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    FileOpenBridge.shared.attach(channel)
  }
}

/// Bridges iOS document opens (Files / "Open in…") to Dart via
/// `MethodChannel('visioeditor/files')`, mirroring the macOS bridge.
final class FileOpenBridge {
  static let shared = FileOpenBridge()
  private init() {}

  private var channel: FlutterMethodChannel?
  private var pending: [String] = []
  private var isReady = false

  func attach(_ channel: FlutterMethodChannel) {
    self.channel = channel
  }

  func markReady() {
    isReady = true
    flush()
  }

  func open(_ urls: [URL]) {
    let paths = urls.compactMap { Self.sandboxReadablePath(for: $0) }
    guard !paths.isEmpty else { return }
    pending.append(contentsOf: paths)
    flush()
  }

  private func flush() {
    guard isReady, let channel = channel, !pending.isEmpty else { return }
    let paths = pending
    pending.removeAll()
    channel.invokeMethod("openFiles", arguments: paths)
  }

  /// Copy into Caches so Dart can read after the security scope ends.
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
      return url.path
    }
  }
}
