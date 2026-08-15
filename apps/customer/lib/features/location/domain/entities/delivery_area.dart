/// Whether we deliver to a point, and what to say about it.
///
/// **The sentences come from the database, not from here.** `delivery_area_check`
/// (migration 0098) returns the headline and the detail alongside the verdict,
/// for the same reason 0061 put the canned messages in Postgres: the towns we
/// serve will change, and the copy that names them should change with the row
/// rather than with a store release.
///
/// The verdict is advisory in the sense that a trigger on `orders` enforces the
/// same rule server-side. It is not advisory in the sense that matters to the
/// customer: every order is prepaid and the gateway runs *before* `place_order`,
/// so a refusal that arrives from the trigger arrives after the money. This is
/// what stops that happening, and the trigger is what catches the build that is
/// already on somebody's phone.
class DeliveryAreaVerdict {
  const DeliveryAreaVerdict({
    required this.serviceable,
    required this.headline,
    required this.detail,
    this.areaId,
  });

  final bool serviceable;

  /// Which town this point orders from — `sadri`, `falna` (migration 0126).
  /// Null when we do not deliver here, and null when the check failed open, so
  /// a caller must treat "no town" as "not known" rather than as a town.
  ///
  /// Ranakpur answers `sadri`: it has no kitchens of its own and shares Sadri's
  /// catalogue, which is a row in `service_areas` rather than a rule in here.
  final String? areaId;

  /// Four words for a button or a banner title — "We'll be there soon".
  final String headline;

  /// The sentence under it, which names the towns we are actually in.
  final String detail;
}
