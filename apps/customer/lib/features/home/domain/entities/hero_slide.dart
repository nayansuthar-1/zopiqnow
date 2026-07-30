import 'package:flutter/foundation.dart';

/// One admin-authored campaign slide in the Home hero carousel (migration 0053).
///
/// Everything a slide needs to draw itself arrives in the row — there is no
/// second fetch and nothing derived on the device. What is *not* here is any
/// notion of scheduling or activation: `starts_at`, `ends_at` and `is_active`
/// are enforced by the table's read policy, so a slide that reaches this class
/// is one a customer is allowed to see. The client does not filter.
@immutable
class HeroSlide {
  const HeroSlide({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.ctaLabel,
    required this.imageUrl,
    this.motionUrl,
    this.ctaTarget,
  });

  final String id;

  /// The headline, e.g. "FLAT ₹150 OFF".
  ///
  /// **May be empty** (migration 0067), and empty is a decision rather than a
  /// gap: a designed banner has the offer set into the artwork already, and a
  /// headline drawn over it would be the same words twice in two typefaces.
  final String title;

  /// The line under it. May be empty — a slide is allowed to be one line.
  /// The database refuses a sub-line with no [title] above it.
  final String subtitle;

  /// What the button says, e.g. "Order now".
  ///
  /// **Empty means the slide has no button** (migration 0067). The tap does not
  /// go away with it — the whole slide becomes the target instead, so a banner
  /// with its own painted-on button still opens [ctaTarget].
  final String ctaLabel;

  /// Cloudinary-hosted artwork. Never empty: the table requires it.
  final String imageUrl;

  /// An optional silent looping video to play over [imageUrl] (migration 0072).
  ///
  /// A Cloudinary `/video/upload/` URL ending `.mp4` — h.264, the admin's own
  /// resolution and frame rate to a 1080px width, no audio track, and the **whole
  /// clip**, which loops. Played by `video_player`, which streams it rather than
  /// waiting for the file, so length costs data while somebody watches rather than
  /// latency before anything appears.
  ///
  /// Until 0072 this held an *animated WebP* that `Image` decoded and looped, so
  /// that a moving hero cost no new dependency. That bought `w_720,fps_12`: WebP
  /// stores every frame as a separate still, so the compromise was both lower
  /// quality *and* about twice the bytes of the video that replaced it.
  ///
  /// Null is the ordinary case. [imageUrl] is what shows when it is null, while
  /// it buffers, if it fails to play at all, and whenever the phone has asked for
  /// reduced motion — so a slide never depends on this arriving.
  final String? motionUrl;

  /// Where the button goes — an in-app path the database has already validated
  /// against something that exists (`/restaurant/<id>`, `/gifts`, …).
  ///
  /// Null is the ordinary case, not a missing value: it means the button does
  /// what the hero's button has always done, which is scroll the feed down to
  /// the restaurant list.
  final String? ctaTarget;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is HeroSlide && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
