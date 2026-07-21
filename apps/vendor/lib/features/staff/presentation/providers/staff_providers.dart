import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiq_vendor/features/auth/domain/entities/vendor.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_vendor/features/staff/data/staff_datasource.dart';
import 'package:zopiq_vendor/features/staff/domain/entities/staff_member.dart';

/// Data source binding. Overridden in tests, which have no Supabase instance.
final Provider<StaffDataSource> staffDataSourceProvider =
    Provider<StaffDataSource>((Ref ref) => const StaffSupabaseDataSource());

/// The roster. A one-shot read like the menu's — nobody else edits a
/// restaurant's team while its owner is looking at it — refreshed by the
/// controller after every write.
///
/// Empty for anyone who is not the owner, rather than an error. The RPC would
/// refuse them, but the screen is never offered to them either (the More hub
/// hides the row), so the honest state for "asked anyway" is nothing to show.
final FutureProvider<List<StaffMember>> staffProvider =
    FutureProvider<List<StaffMember>>((Ref ref) {
      final Vendor? vendor = ref.watch(vendorProvider);
      if (vendor == null || !vendor.role.isOwner) {
        return Future<List<StaffMember>>.value(const <StaffMember>[]);
      }
      return ref.watch(staffDataSourceProvider).fetch();
    });

/// Every write the Staff screen makes. Each returns null on success or a
/// sentence to show — the shape [MenuController] uses, for the same reason.
///
/// The sentences on the failure paths are mostly the database's own: 0024 raises
/// its refusals already written for a human ("You can't remove yourself."), and
/// [StaffWriteFailure] carries them through unchanged.
class StaffController extends Notifier<void> {
  @override
  void build() {}

  StaffDataSource get _ds => ref.read(staffDataSourceProvider);

  Future<String?> add({required String email, required StaffRole role}) =>
      _write(
        () => _ds.add(email: email, role: role),
        'We couldn\'t add them. Please try again.',
      );

  Future<String?> setRole({required String email, required StaffRole role}) =>
      _write(
        () => _ds.setRole(email: email, role: role),
        'We couldn\'t change their role. Please try again.',
      );

  Future<String?> remove(String email) => _write(
    () => _ds.remove(email),
    'We couldn\'t remove them. Please try again.',
  );

  /// Refreshes the roster on success — every write here adds, removes or
  /// re-sorts a row (owners sort first), so the list always changes.
  Future<String?> _write(Future<void> Function() call, String fallback) async {
    try {
      await call();
      ref.invalidate(staffProvider);
      return null;
    } on StaffWriteFailure catch (e) {
      return e.message;
    } on Object {
      return fallback;
    }
  }
}

final NotifierProvider<StaffController, void> staffControllerProvider =
    NotifierProvider<StaffController, void>(StaffController.new);
