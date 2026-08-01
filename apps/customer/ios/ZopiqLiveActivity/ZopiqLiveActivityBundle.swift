import SwiftUI
import WidgetKit

/// The extension's entry point.
///
/// One widget in the bundle today. A home-screen widget would be added here
/// beside it — the bundle is the list of everything this extension provides,
/// not a wrapper around a single thing.
@main
struct ZopiqLiveActivityBundle: WidgetBundle {
  var body: some Widget {
    // Guarded because the extension itself deploys to iOS 14 alongside the app,
    // while Live Activities begin at 16.1. On an older phone the bundle is
    // simply empty and the extension does nothing, which is the correct
    // behaviour and not a failure.
    if #available(iOS 16.1, *) {
      ZopiqLiveActivity()
    }
  }
}
