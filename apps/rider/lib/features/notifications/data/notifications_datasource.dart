import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:zopiq_rider/features/notifications/domain/entities/rider_notification.dart';

/// The rider's read/mark-read window onto their inbox.
///
/// The content is never written here — a trigger (0047) writes it. This reads
/// the list, live, and moves `read_at`; nothing more.
abstract interface class RiderNotificationsDataSource {
  /// Every notification for this rider, live, newest first.
  Stream<List<RiderNotification>> watch(String partnerEmail);

  /// Mark one seen. A no-op on one already read, or one that isn't theirs.
  Future<void> markRead(int id);

  /// Mark the whole unread pile seen at once.
  Future<void> markAllRead();
}

class RiderNotificationsSupabaseDataSource
    implements RiderNotificationsDataSource {
  const RiderNotificationsSupabaseDataSource();

  SupabaseClient get _db => Supabase.instance.client;

  @override
  Stream<List<RiderNotification>> watch(String partnerEmail) {
    // The `.eq` is not the security boundary — the 0047 RLS policy is, and would
    // return nothing for another rider. It is here so the socket carries one
    // rider's inbox rather than being asked to.
    return _db
        .from('notifications')
        .stream(primaryKey: const <String>['id'])
        .eq('partner_email', partnerEmail)
        .order('created_at', ascending: false)
        .map(
          (List<Map<String, dynamic>> rows) =>
              rows.map(RiderNotification.fromJson).toList(growable: false),
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
