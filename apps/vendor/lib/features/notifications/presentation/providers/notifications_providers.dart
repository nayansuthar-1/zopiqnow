import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiq_vendor/features/auth/domain/entities/vendor.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_vendor/features/notifications/data/notifications_datasource.dart';
import 'package:zopiq_vendor/features/notifications/domain/entities/vendor_notification.dart';

/// Data source binding. Overridden in tests, which have no Supabase instance.
final Provider<NotificationsDataSource> notificationsDataSourceProvider =
    Provider<NotificationsDataSource>(
      (Ref ref) => const NotificationsSupabaseDataSource(),
    );

/// The inbox, live. Empty when nobody is signed in — not an error, and not a
/// stream that throws: the same shape as [ordersProvider], for the same reason
/// (a provider that explodes during sign-out explodes during an ordinary one).
final StreamProvider<List<VendorNotification>> notificationsProvider =
    StreamProvider<List<VendorNotification>>((Ref ref) {
      final Vendor? vendor = ref.watch(vendorProvider);
      if (vendor == null) {
        return Stream<List<VendorNotification>>.value(
          const <VendorNotification>[],
        );
      }
      return ref
          .watch(notificationsDataSourceProvider)
          .watch(vendor.restaurantId);
    });

/// The unread tally the header bell wears. Derived off the one stream — no second
/// subscription — and 0 while it loads or errors, so the bell never shows a count
/// it cannot stand behind.
final Provider<int> unreadCountProvider = Provider<int>((Ref ref) {
  return ref
      .watch(notificationsProvider)
      .maybeWhen(
        data: (List<VendorNotification> n) =>
            n.where((VendorNotification x) => x.isUnread).length,
        orElse: () => 0,
      );
});
