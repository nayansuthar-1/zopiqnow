import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiq_vendor/features/notifications/domain/entities/vendor_notification.dart';

/// The kitchen's read/mark-read window onto its inbox.
///
/// The content is never written here — a trigger (0021) writes it. This reads
/// the list, live, and moves `read_at`; nothing more.
abstract interface class NotificationsDataSource {
  /// Every notification for this restaurant, live, newest first.
  Stream<List<VendorNotification>> watch(String restaurantId);

  /// Mark one seen. A no-op on one already read, or one at another restaurant.
  Future<void> markRead(int id);

  /// Mark the whole unread pile seen at once.
  Future<void> markAllRead();
}

class NotificationsSupabaseDataSource implements NotificationsDataSource {
  const NotificationsSupabaseDataSource();

  SupabaseClient get _db => Supabase.instance.client;

  @override
  Stream<List<VendorNotification>> watch(String restaurantId) {
    // The `.eq` is not the security boundary — the 0021 RLS policy is, and would
    // return nothing for a restaurant this user does not work at. It is here so
    // the socket carries one kitchen's inbox rather than every kitchen's.
    return _db
        .from('notifications')
        .stream(primaryKey: const <String>['id'])
        .eq('restaurant_id', restaurantId)
        .order('created_at', ascending: false)
        .map(
          (List<Map<String, dynamic>> rows) =>
              rows.map(VendorNotification.fromJson).toList(growable: false),
        );
  }

  @override
  Future<void> markRead(int id) async {
    await _db.rpc<void>(
      'mark_notification_read',
      params: <String, dynamic>{'p_id': id},
    );
  }

  @override
  Future<void> markAllRead() async {
    await _db.rpc<void>('mark_all_notifications_read');
  }
}
