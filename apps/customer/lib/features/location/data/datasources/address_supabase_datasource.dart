import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiqnow/features/location/data/datasources/address_datasource.dart';
import 'package:zopiqnow/features/location/domain/entities/address.dart';

/// The address book, on Postgres.
///
/// Written by the client — unlike orders, which only `place_order` may write.
/// The difference is that nothing here costs anything: an address is the
/// customer's own text about where they live, so the only rule to enforce is
/// "it is yours", and the RLS policies on `addresses` enforce exactly that.
class AddressSupabaseDataSource implements AddressDataSource {
  const AddressSupabaseDataSource();

  SupabaseClient get _db => Supabase.instance.client;

  /// The columns, in the order the UI needs them. `user_id` is never sent: the
  /// insert policy takes it from the JWT via the column default's `auth.uid()`
  /// check, so naming it here would only be a chance to name it wrong.
  static const String _columns = 'id, label, line1, city, latitude, longitude';

  @override
  Future<List<Address>> fetchAddresses() async {
    // Signed out, RLS would return an empty list anyway. Saying so here saves a
    // round trip on every cold start for a user who has not signed in — which,
    // since browsing needs no account, is most of them.
    if (_db.auth.currentUser == null) return const <Address>[];

    final List<Map<String, dynamic>> rows = await _db
        .from('addresses')
        .select(_columns)
        .order('created_at', ascending: true);

    return rows.map(_addressFrom).toList(growable: false);
  }

  @override
  Future<Address> insertAddress({
    required String line1,
    required String city,
    required double latitude,
    required double longitude,
    String? label,
  }) async {
    final Map<String, dynamic> row = await _db
        .from('addresses')
        .insert(<String, dynamic>{
          // The owner. Not trusted from anywhere else: the `with check`
          // policy refuses a row whose user_id is not the caller's, so a bug
          // here is a failed insert rather than an address filed under someone
          // else's account.
          'user_id': _db.auth.currentUser!.id,
          'label': label,
          'line1': line1,
          'city': city,
          'latitude': latitude,
          'longitude': longitude,
        })
        .select(_columns)
        .single();

    return _addressFrom(row);
  }

  @override
  Future<Address> updateAddress(Address address) async {
    final Map<String, dynamic> row = await _db
        .from('addresses')
        .update(<String, dynamic>{
          'label': address.label,
          'line1': address.line1,
          'city': address.city,
          'latitude': address.latitude,
          'longitude': address.longitude,
        })
        // Not `.eq('user_id', …)` as well: the policy already restricts this to
        // the caller's rows, and a second copy of that rule here could only
        // drift from it.
        .eq('id', address.id)
        .select(_columns)
        .single();

    return _addressFrom(row);
  }

  @override
  Future<void> deleteAddress(String id) =>
      _db.from('addresses').delete().eq('id', id);

  static Address _addressFrom(Map<String, dynamic> row) => Address(
    id: row['id'] as String,
    label: row['label'] as String?,
    line1: row['line1'] as String,
    city: row['city'] as String,
    latitude: (row['latitude'] as num).toDouble(),
    longitude: (row['longitude'] as num).toDouble(),
  );
}
