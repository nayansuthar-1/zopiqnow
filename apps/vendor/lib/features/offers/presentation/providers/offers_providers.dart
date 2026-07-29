import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiq_vendor/features/auth/domain/entities/vendor.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_vendor/features/offers/data/offers_datasource.dart';
import 'package:zopiq_vendor/features/offers/domain/entities/vendor_offer.dart';

/// Data source binding. Overridden in tests, which have no Supabase instance.
final Provider<OffersDataSource> offersDataSourceProvider =
    Provider<OffersDataSource>((Ref ref) => const OffersSupabaseDataSource());

/// The kitchen's offers, active first.
///
/// Empty for anyone who is not the owner, rather than an error — the same shape
/// the staff roster uses, and for the same reason: 0064 refuses a non-owner's
/// writes, the More hub hides the row, and the honest state for "asked anyway"
/// is nothing to show. (The *read* is open to all staff; only the writes are
/// the owner's, so a cook who reaches this screen sees the list and no buttons.)
final FutureProvider<List<VendorOffer>> offersProvider =
    FutureProvider<List<VendorOffer>>((Ref ref) {
      final Vendor? vendor = ref.watch(vendorProvider);
      if (vendor == null) {
        return Future<List<VendorOffer>>.value(const <VendorOffer>[]);
      }
      return ref.watch(offersDataSourceProvider).fetch();
    });

/// Every write the Offers screen makes. Each returns null on success or a
/// sentence to show — the shape [StaffController] uses, for the same reason.
class OffersController extends Notifier<void> {
  @override
  void build() {}

  OffersDataSource get _ds => ref.read(offersDataSourceProvider);

  /// Returns the failure sentence, or null on success. The code the database
  /// settled on is not returned: the list refreshes and shows it, which is a
  /// better place to learn it than a snackbar.
  Future<String?> save({
    required String code,
    required int minSubtotal,
    int? flatOff,
    int? percentOff,
    int? maxOff,
    DateTime? validUntil,
  }) => _write(
    () => _ds.save(
      code: code,
      minSubtotal: minSubtotal,
      flatOff: flatOff,
      percentOff: percentOff,
      maxOff: maxOff,
      validUntil: validUntil,
    ),
    'We couldn\'t save that offer. Please try again.',
  );

  Future<String?> setActive({required String code, required bool isActive}) =>
      _write(
        () => _ds.setActive(code: code, isActive: isActive),
        'We couldn\'t change that offer. Please try again.',
      );

  Future<String?> _write(Future<void> Function() call, String fallback) async {
    try {
      await call();
      ref.invalidate(offersProvider);
      return null;
    } on OfferWriteFailure catch (e) {
      return e.message;
    } on Object {
      return fallback;
    }
  }
}

final NotifierProvider<OffersController, void> offersControllerProvider =
    NotifierProvider<OffersController, void>(OffersController.new);
