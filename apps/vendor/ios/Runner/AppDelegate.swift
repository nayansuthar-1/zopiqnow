import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // No Maps SDK here, unlike the other two apps: a kitchen screen has no map
    // and should not carry the framework for one.

    // APNs, which `firebase_messaging` sits on top of. Without it the app never
    // gets a device token, FCM has nothing to map its own token onto, and a new
    // order lands in silence — which for this app is the whole product.
    //
    // Registering is not asking. The prompt is a separate runtime call the app
    // already makes.
    application.registerForRemoteNotifications()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
