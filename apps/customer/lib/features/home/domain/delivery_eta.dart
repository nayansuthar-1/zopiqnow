import 'package:flutter/foundation.dart';

/// How long the food actually takes to arrive: the kitchen's own minutes plus
/// the ride from that kitchen to this address.
///
/// The feed used to print `restaurants.eta_minutes` on its own, which made every
/// kitchen in town quote the same wait regardless of whether it was around the
/// corner or four kilometres out — and made a kitchen nobody had given a number
/// to quote "0 min". Migration 0134 put the kitchen's number back under human
/// control in both consoles; this is the other half, where that number stops
/// pretending to be the whole answer.
///
/// **Two parts, one of them measured.** The kitchen's share is a judgement call
/// somebody types in — cooking and packing, the thing only the cook can know.
/// The ride is derived from the distance the card already computes, so it moves
/// with the customer's address the way it does in real life.
@immutable
class DeliveryEta {
  const DeliveryEta._({required this.minutes, required this.includesTravel});

  /// The kitchen's own minutes, plus the ride when we can measure it.
  ///
  /// The point estimate rather than the range, because sorting and the "fast
  /// delivery" filter need one number and a band gives them two.
  final int minutes;

  /// Whether the ride is in [minutes], or only the kitchen's share is.
  ///
  /// False when nobody has placed this kitchen on the map, or the customer has
  /// no address selected — the same "unknown is not zero" rule the distance
  /// itself follows. It changes what [label] is willing to claim.
  final bool includesTravel;

  /// Minutes of riding per kilometre of straight-line distance.
  ///
  /// Three, which is 20 km/h as the crow flies — and since a road between two
  /// points is about a third longer than the line between them, that is a
  /// two-wheeler doing a shade over 25 km/h on the actual street. The right
  /// order of magnitude for Falna and Sadri, where nothing is far and nothing
  /// moves fast.
  static const double _minutesPerKm = 3;

  /// Fixed minutes between the food being ready and the rider being away with
  /// it: reaching the counter, finding the right bag, checking the order.
  /// Independent of distance, which is why it is not in the rate above.
  static const int _pickupMinutes = 4;

  /// The width of the band [label] shows.
  ///
  /// Five, not ten. Ten was the first guess and it read badly against real
  /// data: in Sadri nothing is more than two kilometres away, so the ride is
  /// one to six minutes and almost all of a ten-minute band was padding. A
  /// kitchen that had honestly said "30" was being shown as "35–45", which is a
  /// top end fifty per cent above the number its own cook chose.
  ///
  /// Five also makes the band exact rather than decorative: [lowMinutes] rounds
  /// *down* to a multiple of five, so [minutes] always falls inside
  /// `[low, low + 5)` instead of floating somewhere in a wider guess.
  static const int _spreadMinutes = 5;

  /// [prepMinutes] is `restaurants.eta_minutes`; [distanceKm] is null when we
  /// cannot measure the ride, and then so is the ride.
  factory DeliveryEta.from({
    required int prepMinutes,
    required double? distanceKm,
  }) {
    if (distanceKm == null) {
      return DeliveryEta._(minutes: prepMinutes, includesTravel: false);
    }
    return DeliveryEta._(
      minutes:
          prepMinutes +
          _pickupMinutes +
          (distanceKm * _minutesPerKm).round(),
      includesTravel: true,
    );
  }

  /// Bottom of the band, rounded down to the nearest five so the card reads
  /// "35–40" rather than "37–42". Never below five: an arrival in less time
  /// than that is not a figure anyone believes.
  int get lowMinutes {
    final int floored = (minutes ~/ 5) * 5;
    return floored < 5 ? 5 : floored;
  }

  int get highMinutes => lowMinutes + _spreadMinutes;

  /// What the customer reads: "35–40 min" once the ride is in it.
  ///
  /// **A single figure when it is not.** A band on the kitchen's number alone
  /// would be five minutes of spread invented out of nothing, which is
  /// precision we do not have — the spread here exists because the travel
  /// estimate is a straight line through an assumed speed, and with no distance
  /// there is no such estimate to be uncertain about.
  String get label =>
      includesTravel ? '$lowMinutes–$highMinutes min' : '$minutes min';
}
