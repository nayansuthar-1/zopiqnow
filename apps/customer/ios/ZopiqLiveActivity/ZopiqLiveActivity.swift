import ActivityKit
import SwiftUI
import WidgetKit

// The Live Activity — the iOS half of the live order card.
//
// This file belongs to the `ZopiqLiveActivity` widget-extension target, not to
// the app. It renders in a separate process that never runs Dart, so everything
// it draws must already be in the `ContentState` that
// `ZopiqLiveCardPlugin.show` handed to ActivityKit.
//
// `ZopiqLiveCardAttributes.swift` lives in the plugin
// (`packages/zopiq_live_card/ios/Classes/`) and is added to *this* target as
// well as the app's. Two copies of that type would compile and then silently
// fail to match at runtime; see the note in the file itself.
//
// **Why the bar needs no timer.** Android runs a foreground service redrawing
// every twenty seconds because a RemoteViews progress bar cannot animate itself.
// `ProgressView(timerInterval:)` can: give it two dates and it fills between
// them on its own, with the app asleep and nothing pushed. The same window the
// server has sent since 0055, honoured with less machinery.

@available(iOS 16.1, *)
struct ZopiqLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: ZopiqLiveCardAttributes.self) { context in
      // The Lock Screen and Notification Centre presentation.
      LockScreenCard(context: context)
        .activityBackgroundTint(Color.black.opacity(0.55))
        .activitySystemActionForegroundColor(.white)

    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          PhaseGlyph(phase: context.state.phase)
            .padding(.leading, 4)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Countdown(end: context.state.windowEnd)
            .padding(.trailing, 4)
        }
        DynamicIslandExpandedRegion(.center) {
          Text(context.state.title)
            .font(.headline)
            .lineLimit(1)
        }
        DynamicIslandExpandedRegion(.bottom) {
          TrackerBar(state: context.state)
        }
      } compactLeading: {
        PhaseGlyph(phase: context.state.phase)
      } compactTrailing: {
        Countdown(end: context.state.windowEnd)
          .frame(maxWidth: 44)
      } minimal: {
        PhaseGlyph(phase: context.state.phase)
      }
      // The tap target, for every presentation at once. The plugin's
      // `application(_:open:options:)` reads this back.
      .widgetURL(URL(string: "zopiq://order/\(context.attributes.orderId)"))
      .keylineTint(Color.zopiqOrange)
    }
  }
}

// MARK: - Lock Screen

@available(iOS 16.1, *)
private struct LockScreenCard: View {
  let context: ActivityViewContext<ZopiqLiveCardAttributes>

  var body: some View {
    HStack(spacing: 14) {
      VStack(alignment: .leading, spacing: 6) {
        Text(context.state.title)
          .font(.headline)
          .foregroundStyle(.white)
          .lineLimit(1)

        if let body = context.state.body, !body.isEmpty {
          Text(body)
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.75))
            .lineLimit(1)
        }

        TrackerBar(state: context.state)
      }

      PhaseGlyph(phase: context.state.phase)
        .font(.system(size: 34))
    }
    .padding(16)
  }
}

// MARK: - The bar

/// The segmented tracker, and the only part with real logic in it.
///
/// Two modes, and the choice mirrors the Android side exactly: when the server
/// sent a `progress` override the bar is static at that value, and otherwise it
/// sweeps the window on the device clock. The override is the seam for
/// distance-driven progress that B3 opened and neither platform has closed.
@available(iOS 16.1, *)
private struct TrackerBar: View {
  let state: ZopiqLiveCardAttributes.ContentState

  var body: some View {
    Group {
      if let progress = state.progress {
        ProgressView(value: Double(progress), total: 100)
      } else if state.windowEnd > state.windowStart {
        // Fills between two dates by itself, with nothing running.
        ProgressView(
          timerInterval: state.windowStart...state.windowEnd,
          countsDown: false,
          label: { EmptyView() },
          currentValueLabel: { EmptyView() }
        )
      } else {
        // A window that ends before it starts is a malformed payload. An
        // indeterminate bar is honest about knowing nothing; a full one would
        // claim the food had arrived.
        ProgressView()
      }
    }
    .progressViewStyle(.linear)
    .tint(Color.zopiqOrange)
  }
}

// MARK: - Small parts

@available(iOS 16.1, *)
private struct PhaseGlyph: View {
  let phase: String

  var body: some View {
    // SF Symbols rather than the PNGs Android uses. A RemoteViews layout cannot
    // draw a vector; SwiftUI can, and a symbol stays crisp at every one of the
    // Dynamic Island's sizes.
    Image(systemName: phase == "delivery" ? "bicycle" : "frying.pan")
      .foregroundStyle(Color.zopiqOrange)
  }
}

@available(iOS 16.1, *)
private struct Countdown: View {
  let end: Date

  var body: some View {
    // `.timer` re-renders itself once a minute without a push, which is the
    // second thing Android needs its foreground service for.
    Text(timerInterval: Date.now...max(end, Date.now), countsDown: true)
      .font(.caption.monospacedDigit())
      .foregroundStyle(.white.opacity(0.85))
      .multilineTextAlignment(.trailing)
  }
}

extension Color {
  /// The one brand token this target needs. It is written out rather than
  /// imported because a widget extension cannot depend on `zopiq_ui` — that is
  /// a Dart package, and nothing here runs Dart. #FC8019.
  static let zopiqOrange = Color(red: 252 / 255, green: 128 / 255, blue: 25 / 255)
}
