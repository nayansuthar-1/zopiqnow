import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiq_vendor/features/auth/domain/entities/vendor.dart';
import 'package:zopiq_vendor/features/staff/domain/entities/staff_member.dart';

/// The owner's window onto who else may sign in to this kitchen.
///
/// Every call here is an RPC, including the read — and that is the difference
/// from every other feature in this app. `restaurant_staff` has no select policy
/// at all (0009: a readable table would let anyone enumerate which address runs
/// which restaurant), so there is nothing to `select` from. The four functions
/// in 0024 answer narrow questions about the caller's own roster and refuse
/// anyone who is not its owner.
abstract interface class StaffDataSource {
  /// The roster, owners first. Throws [StaffWriteFailure] for a non-owner.
  Future<List<StaffMember>> fetch();

  Future<void> add({required String email, required StaffRole role});

  Future<void> setRole({required String email, required StaffRole role});

  Future<void> remove(String email);
}

/// A call the database refused — a rule in 0024 (`P0001`: not the owner, already
/// on another team, acting on yourself) or an outage.
class StaffWriteFailure implements Exception {
  const StaffWriteFailure([
    this.message = 'We couldn\'t update your team. Please try again.',
  ]);

  final String message;
}

class StaffSupabaseDataSource implements StaffDataSource {
  const StaffSupabaseDataSource();

  SupabaseClient get _db => Supabase.instance.client;

  static const String _businessRuleErrorCode = 'P0001';

  @override
  Future<List<StaffMember>> fetch() async {
    final List<dynamic> rows = await _guard<List<dynamic>>(
      () => _db.rpc<List<dynamic>>('list_restaurant_staff'),
    );
    return rows
        .cast<Map<String, dynamic>>()
        .map(StaffMember.fromJson)
        .toList(growable: false);
  }

  @override
  Future<void> add({required String email, required StaffRole role}) =>
      _guard<void>(
        () => _db.rpc<void>(
          'add_restaurant_staff',
          params: <String, dynamic>{'p_email': email, 'p_role': role.name},
        ),
      );

  @override
  Future<void> setRole({required String email, required StaffRole role}) =>
      _guard<void>(
        () => _db.rpc<void>(
          'set_staff_role',
          params: <String, dynamic>{'p_email': email, 'p_role': role.name},
        ),
      );

  @override
  Future<void> remove(String email) => _guard<void>(
    () => _db.rpc<void>(
      'remove_restaurant_staff',
      params: <String, dynamic>{'p_email': email},
    ),
  );

  /// Every refusal in 0024 is raised as `P0001` with a sentence already written
  /// for a human — "cook@paradise.in is already on another restaurant's team."
  /// Passing it through beats inventing a vaguer one here.
  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PostgrestException catch (e) {
      if (e.code == _businessRuleErrorCode) throw StaffWriteFailure(e.message);
      throw const StaffWriteFailure();
    }
  }
}
