import FirebaseCore
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
    // The missing-key branch matters, and *not* calling this is the wrong way
    // to handle it. `provideAPIKey("")` throws, so an empty key cannot be passed
    // through — but skipping the call entirely only moves the crash: the SDK
    // raises an uncaught `NSException` from `+[GMSServices
    // checkServicePreconditions]` the first time a map view is built, which on
    // the order screen killed the app outright.
    //
    // Handing it a placeholder initialises the SDK, so the map view constructs
    // and then fails authorisation the way Android's does — a dead tile on one
    // screen instead of a dead app. A fresh clone with no Secrets.xcconfig must
    // still run, and now it does past the first map.
    let key = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String
    GMSServices.provideAPIKey(
      (key?.isEmpty ?? true) ? "MISSING_GMS_API_KEY" : key!
    )

    // **Firebase first, and the order is the whole point.**
    //
    // Dart calls `Firebase.initializeApp()` too, from `PushService.start()`, and
    // that is far too late for APNs. `start()` runs after `runApp` and after
    // `await supabaseReady` — a network round trip — while the APNs token comes
    // back a few hundred milliseconds after the registration below. The
    // messaging plugin catches that callback and hands the token to
    // `FIRMessaging`, but with no configured `FIRApp` to hand it to, it is
    // dropped. **iOS never re-delivers it**, so `getAPNSToken()` then returns
    // null for the entire life of the process, FCM can never mint a token, and
    // the device registers nothing — which is precisely how 25 Android tokens
    // came to sit beside zero iOS ones.
    //
    // Configuring here closes that window: the default app exists before
    // anything can answer. Dart's call is then a no-op that adopts this app
    // rather than a second configuration, which is the documented FlutterFire
    // arrangement and why it is safe to do both.
    FirebaseApp.configure()

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
