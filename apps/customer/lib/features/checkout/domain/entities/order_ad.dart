import 'package:flutter/foundation.dart';

/// One admin-authored ad shown beside the tracking map (migration 0125).
///
/// Ours, not a network's: two images uploaded in the console and drawn by the
/// app. Nothing here calls out to an ad server, and there is no SDK behind it —
/// which is the reason the customer binary can still claim no third-party
/// tracker.
///
/// Like [HeroSlide], this carries no notion of scheduling. `is_active`,
/// `starts_at` and `ends_at` are applied by the table's read policy, so an ad
/// that reaches this class is one the customer is allowed to see. The client
/// does not filter, because a client filter ships next week's campaign to every
/// phone a week early.
@immutable
class OrderAd {
  const OrderAd({
    required this.id,
    required this.logoUrl,
    required this.imageUrl,
    required this.headline,
    required this.ctaLabel,
    required this.ctaTarget,
  });

  final String id;

  /// The advertiser's mark, drawn in the round puck over the map's corner.
  final String logoUrl;

  /// The full-bleed artwork the puck opens.
  final String imageUrl;

  /// Drawn over the foot of the artwork. **Often empty**, and empty is a choice
  /// rather than a gap — a composed banner has its words set into the picture
  /// already.
  final String headline;

  /// What the button says. **Empty means there is no button**, and then the
  /// artwork is the whole of the ad.
  final String ctaLabel;

  /// Where the button goes. The string says which kind it is and the database
  /// refuses anything else (0125): `http…` leaves for the browser, `/…` is a
  /// route inside the app.
  final String ctaTarget;

  bool get hasCta => ctaLabel.isNotEmpty && ctaTarget.isNotEmpty;

  /// True when the button leaves Zopiq. Read off the target rather than a column
  /// so the two can never disagree.
  bool get opensExternally => ctaTarget.startsWith('http');
}
