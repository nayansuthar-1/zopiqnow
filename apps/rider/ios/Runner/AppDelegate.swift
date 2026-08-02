import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // The Maps SDK, keyed before any map view is constructed. The key arrives
    // `Flutter/Secrets.xcconfig` (gitignored) -> `GMSApiKey` in Info.plist ->
    // here, which is this platform's version of Gradle substituting it out of
    // `local.properties`. It is restricted to this app's own bundle id and is
    // not the customer app's key.
    //
    // A placeholder rather than skipping the call on an empty key:
    // `provideAPIKey("")` throws, but leaving the SDK uninitialised only defers
    // the crash to the first map view, which on the job map is the whole screen.
    // See the customer app's AppDelegate for the longer note.
    let key = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String
    GMSServices.provideAPIKey(
      (key?.isEmpty ?? true) ? "MISSING_GMS_API_KEY" : key!
    )

    // APNs, which `firebase_messaging` sits on top of. Without it the app never
    // gets a device token, FCM has nothing to map its own token onto, and a
    // new-job push is dropped in silence.
    //
    // Registering is not asking. The prompt is a separate runtime call that
    // `PushService.start` already makes.
    application.registerForRemoteNotifications()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
