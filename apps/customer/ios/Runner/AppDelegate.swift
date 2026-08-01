import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // The Maps SDK, keyed before any map view is constructed.
    //
    // Android reads this key from a manifest meta-data element that Gradle
    // substitutes out of the gitignored `local.properties`. iOS has no such
    // mechanism, so the value travels `Flutter/Secrets.xcconfig` -> the
    // `GMSApiKey` entry in Info.plist -> here. Both platforms therefore keep the
    // key out of the repository and out of Dart.
    //
    // The empty-key branch matters. `provideAPIKey("")` throws, which would turn
    // a missing key into a launch crash — on Android the same omission renders
    // Google's "authorization failure" tile and the rest of the app keeps
    // working. Skipping the call reproduces that: the map fails, nothing else
    // does. A fresh clone with no Secrets.xcconfig must still run.
    if let key = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
       !key.isEmpty {
      GMSServices.provideAPIKey(key)
    }

    // APNs, which is what `firebase_messaging` sits on top of. Without this the
    // app never receives a device token, FCM has nothing to map its own token
    // onto, and every push is silently dropped — the iOS equivalent of posting
    // to a notification channel that does not exist.
    //
    // This only registers; it does not ask. The permission prompt is a separate
    // runtime call that `PushService.start` already makes, at the moment the
    // product wants to ask rather than at launch.
    application.registerForRemoteNotifications()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
