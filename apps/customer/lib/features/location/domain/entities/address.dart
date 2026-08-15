/// A delivery address. `label` is the saved-address tag (Home/Work); a
/// GPS-derived address has none until the user saves it.
class Address {
  const Address({
    required this.id,
    required this.line1,
    required this.city,
    required this.latitude,
    required this.longitude,
    this.label,
    this.deliveryNotes,
    this.serviceAreaId,
  });

  final String id;

  /// Street / locality — the line the header shows.
  final String line1;
  final String city;
  final double latitude;
  final double longitude;
  final String? label;

  /// What to tell the rider about this door — "gate 2, blue building", "ring
  /// twice, the bell is faint" (0061). Saved with the address so it is typed
  /// once, and *copied* onto each order rather than read back from here: an
  /// order must still say what the rider was told after the note is rewritten.
  final String? deliveryNotes;

  /// Which town this address orders from — `sadri`, `falna` (migration 0126).
  ///
  /// Resolved by `delivery_area_check` and written into the *local* selection
  /// snapshot when the address is picked, which is why rows read back from the
  /// address book carry null: the column does not exist on `addresses`, and this
  /// is a fact about where we deliver rather than about the door.
  ///
  /// Null means **not known**, never "no town". It is null on a legacy snapshot,
  /// and null when the resolve failed — both cases fall back to asking the
  /// server again rather than to showing an empty catalogue.
  final String? serviceAreaId;

  /// What the Home header renders: `Banjara Hills, Hyderabad`. A reverse-geocode
  /// can come back with no city, so never render a dangling comma.
  String get shortDisplay => city.isEmpty ? line1 : '$line1, $city';

  /// The same door, with the town it orders from filled in.
  Address withServiceArea(String? areaId) => Address(
    id: id,
    line1: line1,
    city: city,
    latitude: latitude,
    longitude: longitude,
    label: label,
    deliveryNotes: deliveryNotes,
    serviceAreaId: areaId,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'line1': line1,
    'city': city,
    'latitude': latitude,
    'longitude': longitude,
    'label': label,
    'delivery_notes': deliveryNotes,
    'service_area_id': serviceAreaId,
  };

  static Address fromJson(Map<String, dynamic> json) => Address(
    id: json['id']! as String,
    line1: json['line1']! as String,
    city: json['city']! as String,
    latitude: (json['latitude']! as num).toDouble(),
    longitude: (json['longitude']! as num).toDouble(),
    label: json['label'] as String?,
    deliveryNotes: json['delivery_notes'] as String?,
    // Absent from anything an older build wrote, which reads as "not known".
    serviceAreaId: json['service_area_id'] as String?,
  );
}
