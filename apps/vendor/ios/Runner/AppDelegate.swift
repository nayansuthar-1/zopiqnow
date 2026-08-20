import FirebaseCore
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

    // **Firebase first, and the order is the whole point.**
    //
    // Dart calls `Firebase.initializeApp()` too, from `PushService.start()`, and
    // that is far too late for APNs: the token comes back a few hundred
    // milliseconds after the registration below, the messaging plugin catches it
    // and hands it to `FIRMessaging`, and with no configured `FIRApp` to hand it
    // to it is dropped. **iOS never re-delivers it**, so `getAPNSToken()` returns
    // null for the life of the process and the device registers nothing.
    //
    // Configuring here closes that window. Dart's call then adopts this app
    // rather than configuring a second one, which is the documented FlutterFire
    // arrangement and why doing both is safe.
    FirebaseApp.configure()

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
