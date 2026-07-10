import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Channel used to hand OS "open document" events to the Dart side. Dart
    // invokes `ready` once it has registered its handler; native pushes
    // `openFiles` with a list of paths.
    let fileChannel = FlutterMethodChannel(
      name: "visioeditor/files",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    fileChannel.setMethodCallHandler { (call, result) in
      if call.method == "ready" {
        FileOpenBridge.shared.markReady()
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    FileOpenBridge.shared.attach(fileChannel)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
