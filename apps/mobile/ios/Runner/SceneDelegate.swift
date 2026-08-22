import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    configureDeepLinkChannel()

    guard let url = connectionOptions.urlContexts.first?.url else {
      return
    }

    handleDeepLink(url, isInitial: true)
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    configureDeepLinkChannel()
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    configureDeepLinkChannel()

    let handled = URLContexts
      .map { $0.url }
      .contains { handleDeepLink($0, isInitial: false) }

    if !handled {
      super.scene(scene, openURLContexts: URLContexts)
    }
  }

  private func configureDeepLinkChannel() {
    guard
      let appDelegate = UIApplication.shared.delegate as? AppDelegate,
      let controller = window?.rootViewController as? FlutterViewController
    else {
      return
    }

    appDelegate.configureShareChannel(controller: controller)
    appDelegate.configurePhoneChannel(controller: controller)
    appDelegate.configureContactChannel(controller: controller)
    appDelegate.configureHomeWidgetChannel(controller: controller)

    appDelegate.deepLinkChannel = FlutterMethodChannel(
      name: "checky/deep_links",
      binaryMessenger: controller.binaryMessenger
    )

    appDelegate.deepLinkChannel?.setMethodCallHandler { [weak appDelegate] call, result in
      switch call.method {
      case "getInitialLink":
        result(appDelegate?.consumeDeepLink(preferred: appDelegate?.initialDeepLink))
        appDelegate?.initialDeepLink = nil
      case "getLatestLink":
        result(appDelegate?.consumeDeepLink(preferred: appDelegate?.latestDeepLink))
        appDelegate?.latestDeepLink = nil
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  @discardableResult
  private func handleDeepLink(_ url: URL, isInitial: Bool) -> Bool {
    guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
      return false
    }

    configureDeepLinkChannel()
    return appDelegate.handleDeepLink(url, isInitial: isInitial)
  }
}
