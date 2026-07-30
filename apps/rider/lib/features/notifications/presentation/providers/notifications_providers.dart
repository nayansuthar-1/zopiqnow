import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiq_rider/features/auth/domain/entities/rider.dart';
import 'package:zopiq_rider/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_rider/features/notifications/data/notifications_datasource.dart';
import 'package:zopiq_rider/features/notifications/domain/entities/rider_notification.dart';

/// Data source binding. Overridden in tests, which have no Supabase instance.
final Provider<RiderNotificationsDataSource> notificationsDataSourceProvider =
    Provider<RiderNotificationsDataSource>(
      (Ref ref) => const RiderNotificationsSupabaseDataSource(),
    );

/// The inbox, live. Empty when nobody is signed in — not an error, and not a
/// stream that throws: a provider that explodes during sign-out explodes during
/// an ordinary one.
final StreamProvider<List<RiderNotification>> notificationsProvider =
    StreamProvider<List<RiderNotification>>((Ref ref) {
      final Rider? rider = ref.watch(riderProvider);
      if (rider == null) {
        return Stream<List<RiderNotification>>.value(
          const <RiderNotification>[],
        );
      }
      return ref.watch(notificationsDataSourceProvider).watch(rider.email);
    });

/// The unread tally the header bell wears. Derived off the one stream — no second
/// subscription — and 0 while it loads or errors, so the bell never shows a count
/// it cannot stand behind.
final Provider<int> unreadCountProvider = Provider<int>((Ref ref) {
  return ref
      .watch(notificationsProvider)
      .maybeWhen(
        data: (List<RiderNotification> n) =>
            n.where((RiderNotification x) => x.isUnread).length,
        orElse: () => 0,
      );
});
