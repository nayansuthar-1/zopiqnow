import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiqnow/features/notifications/domain/entities/customer_notification.dart';

/// The customer's read/mark-read window onto their inbox.
///
/// The content is never written here — a trigger (0047) writes it. This reads
/// the list, live, and moves `read_at`; nothing more.
abstract interface class CustomerNotificationsDataSource {
  /// Every notification for this signed-in user, live, newest first.
  Stream<List<CustomerNotification>> watch(String userId);

  /// Mark one seen. A no-op on one already read, or one that isn't theirs.
  Future<void> markRead(int id);

  /// Mark the whole unread pile seen at once.
  Future<void> markAllRead();

  /// Removes the caller's own notifications, returning how many went.
  ///
  /// Ids belonging to anybody else are skipped rather than raising (migration
  /// 0124), so a selection holding a row that has already gone still succeeds
  /// for the rest of it.
  Future<int> deleteMany(List<int> ids);
}

class CustomerNotificationsSupabaseDataSource
    implements CustomerNotificationsDataSource {
  const CustomerNotificationsSupabaseDataSource();

  SupabaseClient get _db => Supabase.instance.client;

  @override
  Stream<List<CustomerNotification>> watch(String userId) {
    // The `.eq` is not the security boundary — the 0047 RLS policy is, and would
    // return nothing for another user. It is here so the socket carries one
    // person's inbox rather than being asked to.
    return _db
        .from('notifications')
        .stream(primaryKey: const <String>['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .map(
          (List<Map<String, dynamic>> rows) => rows
              // `order_live` rows (0052) are transport, not correspondence:
              // they exist to move the progress bar on the lock-screen card and
              // there are up to eight per order. Filtered here rather than in
              // the query because a Realtime stream takes one filter and it is
              // already spent on the user id. They arrive already-read, so they
              // never reach the unread badge either way.
              .where((Map<String, dynamic> r) => r['kind'] != 'order_live')
              .map(CustomerNotification.fromJson)
              .toList(growable: false),
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

  @override
  Future<int> deleteMany(List<int> ids) async {
    if (ids.isEmpty) return 0;
    // One call for the whole selection, so it cannot half-delete: the RPC does
    // it in a single statement inside one transaction.
    final Object? deleted = await _db.rpc<Object?>(
      'delete_my_notifications',
      params: <String, dynamic>{'p_ids': ids},
    );
    return deleted is int ? deleted : 0;
  }
}
