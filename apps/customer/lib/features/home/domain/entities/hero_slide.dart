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
  final String title;

  /// The line under it. May be empty — a slide is allowed to be one line.
  final String subtitle;

  /// What the button says, e.g. "Order now".
  final String ctaLabel;

  /// Cloudinary-hosted artwork. Never empty: the table requires it.
  final String imageUrl;

  /// An optional looping animation to play over [imageUrl] (migration 0054).
  ///
  /// This is a *still image URL* despite what it holds — Cloudinary delivers
  /// the admin's uploaded MP4 as an animated WebP, which Flutter's own [Image]
  /// decodes and loops with no video player involved. Nothing on the device
  /// knows a video was ever uploaded.
  ///
  /// Null is the ordinary case. [imageUrl] is what shows when it is null, while
  /// it downloads, if it fails, and whenever the phone has asked for reduced
  /// motion — so a slide never depends on this arriving.
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
