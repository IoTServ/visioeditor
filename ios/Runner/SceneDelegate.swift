import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  /// Cold launch when the scene is created with an inbound document URL.
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    let urls = connectionOptions.urlContexts.map(\.url)
    if !urls.isEmpty {
      FileOpenBridge.shared.open(urls)
    }
  }

  /// Warm launch / "Open in…" while the app is already running.
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    let urls = URLContexts.map(\.url)
    if !urls.isEmpty {
      FileOpenBridge.shared.open(urls)
    }
  }
}
