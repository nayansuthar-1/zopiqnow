import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiqnow/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiqnow/features/notifications/data/notifications_datasource.dart';
import 'package:zopiqnow/features/notifications/domain/entities/customer_notification.dart';

/// Data source binding. Overridden in tests, which have no Supabase instance.
final Provider<CustomerNotificationsDataSource>
notificationsDataSourceProvider = Provider<CustomerNotificationsDataSource>(
  (Ref ref) => const CustomerNotificationsSupabaseDataSource(),
);

/// The inbox, live. Empty for a signed-out user — not an error, and not a stream
/// that throws: a provider that explodes during sign-out explodes during an
/// ordinary one.
final StreamProvider<List<CustomerNotification>> notificationsProvider =
    StreamProvider<List<CustomerNotification>>((Ref ref) {
      final AuthState auth = ref.watch(authControllerProvider);
      if (auth is! AuthSignedIn) {
        return Stream<List<CustomerNotification>>.value(
          const <CustomerNotification>[],
        );
      }
      return ref
          .watch(notificationsDataSourceProvider)
          .watch(auth.user.id);
    });

/// The unread tally the header bell wears. Derived off the one stream — no second
/// subscription — and 0 while it loads or errors, so the bell never shows a count
/// it cannot stand behind.
final Provider<int> unreadCountProvider = Provider<int>((Ref ref) {
  return ref
      .watch(notificationsProvider)
      .maybeWhen(
        data: (List<CustomerNotification> n) =>
            n.where((CustomerNotification x) => x.isUnread).length,
        orElse: () => 0,
      );
});
