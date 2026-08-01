import Flutter
import UIKit

#if canImport(ActivityKit)
  import ActivityKit
#endif

/// The bridge, and the counterpart of `ZopiqLiveCardPlugin.java`. Same channel
/// name, same four methods, same arguments — so `zopiq_live_card.dart` needs no
/// branch of its own.
///
/// **What is genuinely different from Android.** Android draws a notification;
/// iOS runs a Live Activity, which is a separate process rendering a SwiftUI
/// view it owns. The consequences worth knowing:
///
///  * There is no integer notification id on iOS. Dart still passes one, because
///    Android needs it and one API is better than two, and this class keeps a
///    map from that id to the `Activity` it started. See `activities`.
///  * A Live Activity cannot be started while the app is suspended. Android's
///    card can be drawn from the FCM background isolate with the app killed;
///    iOS requires the process to be running and not suspended, which a
///    `content-available` push gives us for a few seconds. That is why
///    `send-notification` now sends an APNs block — without it iOS never wakes
///    at all and none of this runs. The stronger guarantee is a push-to-start
///    token, and it is deliberately not here yet; see IOS_HANDOVER.md.
///  * Nothing redraws the bar. Android runs a foreground service ticking every
///    twenty seconds; the SwiftUI view animates between two dates on its own.
public class ZopiqLiveCardPlugin: NSObject, FlutterPlugin {
  private static let channelName = "com.siteonlab.zopiq_live_card"

  /// The live activities this process started, keyed by the id Dart used.
  ///
  /// Static for the same reason `pendingLaunchOrderId` is static on Android: a
  /// second Flutter engine (the one `firebase_messaging` spins up for a
  /// background message) registers a second instance of this plugin, and both
  /// must see the same activities or a background tick would start a *new* card
  /// beside the one the app already has rather than updating it.
  private static var activities: [Int: Any] = [:]

  /// A tap that arrived before Dart was ready to hear about it. Drained once by
  /// `consumeLaunchOrderId`, exactly as on Android.
  private static var pendingLaunchOrderId: String?

  private var channel: FlutterMethodChannel?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName, binaryMessenger: registrar.messenger())
    let instance = ZopiqLiveCardPlugin()
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, on: channel)
    registrar.addApplicationDelegate(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "show":
      show(call.arguments as? [String: Any] ?? [:], result)
    case "cancel":
      cancel(call.arguments as? [String: Any] ?? [:], result)
    case "consumeLaunchOrderId":
      let pending = ZopiqLiveCardPlugin.pendingLaunchOrderId
      ZopiqLiveCardPlugin.pendingLaunchOrderId = nil
      result(pending)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // ------------------------------------------------------------------ show

  private func show(_ args: [String: Any], _ result: @escaping FlutterResult) {
    #if canImport(ActivityKit)
      guard #available(iOS 16.1, *) else {
        // Too old for a Live Activity. Not an error: the ordinary push
        // notification still arrives, which is precisely the fallback an
        // Android 13 phone gets when it cannot draw a promoted card.
        result(nil)
        return
      }
      guard ActivityAuthorizationInfo().areActivitiesEnabled else {
        // The user turned Live Activities off for this app in Settings. Their
        // call, and nothing to report.
        result(nil)
        return
      }

      let id = intArg(args, "id")
      let orderId = args["orderId"] as? String ?? ""
      guard !orderId.isEmpty else {
        result(nil)
        return
      }

      // Milliseconds since the epoch on the wire, as on Android — the standard
      // codec sizes a Dart int to whatever fits, so read a generic number
      // rather than casting to Int64 and waiting for the first small value.
      let state = ZopiqLiveCardAttributes.ContentState(
        title: args["title"] as? String ?? "Your order",
        body: args["body"] as? String,
        phase: args["phase"] as? String ?? "prep",
        windowStart: date(args, "windowStart"),
        windowEnd: date(args, "windowEnd"),
        // -1 is "no override" on the wire, because null would have to be
        // unboxed on the other side anyway. Same convention as Android.
        progress: { let p = intArg(args, "progress", -1); return p < 0 ? nil : p }()
      )

      // Reusing an id redraws in place, which is the whole contract of `show`.
      if let existing = ZopiqLiveCardPlugin.activities[id]
        as? Activity<ZopiqLiveCardAttributes>
      {
        Task {
          await existing.update(using: state)
          result(nil)
        }
        return
      }

      do {
        let activity = try Activity.request(
          attributes: ZopiqLiveCardAttributes(orderId: orderId),
          contentState: state
        )
        ZopiqLiveCardPlugin.activities[id] = activity
        result(nil)
      } catch {
        // The commonest cause is the app being suspended: ActivityKit refuses
        // to start an activity for a process that is not properly awake. A card
        // that failed to appear must never take the background isolate down
        // with it — the order is still fine, the lock screen is just emptier.
        NSLog("Live card not started: \(error.localizedDescription)")
        result(nil)
      }
    #else
      result(nil)
    #endif
  }

  // ---------------------------------------------------------------- cancel

  private func cancel(_ args: [String: Any], _ result: @escaping FlutterResult) {
    #if canImport(ActivityKit)
      guard #available(iOS 16.1, *) else {
        result(nil)
        return
      }
      let id = intArg(args, "id")
      guard
        let activity = ZopiqLiveCardPlugin.activities.removeValue(forKey: id)
          as? Activity<ZopiqLiveCardAttributes>
      else {
        // An id that never had a card. Safe, and says so — the Dart side calls
        // this speculatively on both phases every time an order ends.
        result(nil)
        return
      }
      Task {
        // `.immediate` because the order is over. The default leaves the card
        // on the lock screen for up to four hours, which for a delivered order
        // is not a grace period, it is litter.
        await activity.end(dismissalPolicy: .immediate)
        result(nil)
      }
    #else
      result(nil)
    #endif
  }

  // ------------------------------------------------------------------ taps

  /// A tap on the Live Activity opens the app on this URL. The widget builds it
  /// as `zopiq://order/<id>`; everything else on that scheme is ignored here so
  /// the app's other deep links keep working.
  public func application(
    _ application: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    guard url.scheme == "zopiq", url.host == "order" else { return false }
    let orderId = url.lastPathComponent
    guard !orderId.isEmpty, orderId != "/" else { return false }

    if let channel = channel {
      // The app is running and there is a live channel — hand it straight over
      // rather than parking it and waiting to be asked.
      channel.invokeMethod("onOrderTapped", arguments: orderId)
    } else {
      ZopiqLiveCardPlugin.pendingLaunchOrderId = orderId
    }
    // Never claim the URL: other plugins read the same one.
    return false
  }

  // ---------------------------------------------------- argument plumbing

  private func intArg(_ args: [String: Any], _ name: String, _ fallback: Int = 0) -> Int {
    (args[name] as? NSNumber)?.intValue ?? fallback
  }

  private func date(_ args: [String: Any], _ name: String) -> Date {
    let ms = (args[name] as? NSNumber)?.doubleValue ?? 0
    return Date(timeIntervalSince1970: ms / 1000)
  }
}
