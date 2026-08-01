import Foundation

#if canImport(ActivityKit)
  import ActivityKit

  /// The contract between the app and the widget extension, and the one file
  /// that must be compiled into **both** targets.
  ///
  /// ActivityKit matches a running activity to its widget by this type, by name
  /// and by shape. If the two targets compile two different versions of it the
  /// failure is not a compile error — it is a Live Activity that starts and
  /// renders nothing, which is a much worse afternoon. In Xcode this file is
  /// added to the `ZopiqLiveActivity` target as well as the app's; see
  /// IOS_HANDOVER.md, which is explicit about the checkbox.
  ///
  /// **Why the window rather than a percentage.** The same reason Android's
  /// `LiveCardSpec` takes two instants: migration 0055 stopped sending a bar
  /// position and started sending `window_start` and `window_end`, so the device
  /// interpolates on its own clock. On Android a foreground service redraws
  /// every twenty seconds; on iOS nothing needs to redraw at all, because
  /// SwiftUI's `ProgressView(timerInterval:)` animates between two dates by
  /// itself. The same payload, and iOS happens to need less machinery to honour
  /// it.
  @available(iOS 16.1, *)
  public struct ZopiqLiveCardAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
      /// The headline — "Preparing your order", "Arriving in 12 min".
      public let title: String
      /// The line under it, when the server sent one.
      public let body: String?
      /// `prep` or `delivery`. Decides the artwork and the wording, exactly as
      /// it does on Android.
      public let phase: String
      /// The two instants the bar sweeps between. UTC.
      public let windowStart: Date
      public let windowEnd: Date
      /// 0-100 when the server overrode the clock, nil when the window governs.
      /// The seam for distance-driven progress, kept open for the same reason
      /// the Android side keeps it.
      public let progress: Int?

      public init(
        title: String,
        body: String?,
        phase: String,
        windowStart: Date,
        windowEnd: Date,
        progress: Int?
      ) {
        self.title = title
        self.body = body
        self.phase = phase
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.progress = progress
      }
    }

    /// The order this card belongs to. Static for the activity's whole life —
    /// it is what a tap resolves to, and what `cancel` matches on.
    public let orderId: String

    public init(orderId: String) {
      self.orderId = orderId
    }
  }
#endif
