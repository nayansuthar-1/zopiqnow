import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_rider/app/router.dart';
import 'package:zopiq_rider/features/notifications/presentation/providers/notifications_providers.dart';

/// The bell in the Jobs app bar. A plain glyph on the surface, wearing a small
/// count when there is anything unread. Reads its own unread tally, so the app
/// bar need only place it.
class RiderNotificationBell extends ConsumerWidget {
  const RiderNotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final int unread = ref.watch(unreadCountProvider);

    return IconButton(
      tooltip: 'Notifications',
      onPressed: () => context.pushNamed(Routes.notifications),
      icon: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Icon(Icons.notifications_rounded, color: zc.textStrong),
          if (unread > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                decoration: BoxDecoration(
                  color: zc.primary,
                  borderRadius: ZopiqRadii.rPill,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  unread > 9 ? '9+' : '$unread',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
