import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/features/notifications/presentation/providers/notifications_providers.dart';

/// The bell in the Home header. A white glyph on the brand hero (matching the
/// profile button beside it), wearing a small count when there is anything
/// unread. Reads its own unread tally, so the header need only place it.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int unread = ref.watch(unreadCountProvider);

    return InkResponse(
      onTap: () => context.pushNamed(Routes.notifications),
      radius: 24,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          CircleAvatar(
            radius: 18,
            backgroundColor: ZopiqPalette.white.withValues(alpha: 0.22),
            child: const Icon(
              Icons.notifications_rounded,
              color: ZopiqPalette.white,
              size: 20,
            ),
          ),
          if (unread > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                decoration: BoxDecoration(
                  color: ZopiqPalette.primary,
                  borderRadius: ZopiqRadii.rPill,
                  border: Border.all(color: ZopiqPalette.white, width: 1.5),
                ),
                child: Text(
                  unread > 9 ? '9+' : '$unread',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: ZopiqPalette.white,
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
