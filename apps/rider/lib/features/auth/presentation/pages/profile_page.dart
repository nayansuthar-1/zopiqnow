import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_rider/features/auth/domain/entities/rider.dart';
import 'package:zopiq_rider/features/auth/presentation/providers/auth_providers.dart';

/// Who the rider is, and the way out.
///
/// Sign-out lived in the jobs app bar until now, as an unlabelled icon one
/// mis-tap from a rider holding a helmet. Everything on this screen is
/// read-only: a rider's name, phone and vehicle are changed by an admin in the
/// console (migration 0040), never by the rider, because the roster is what ops
/// dispatches against.
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Rider? rider = ref.watch(riderProvider);
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(ZopiqSpacing.pageGutter),
          children: <Widget>[
            ZopiqCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    rider?.name.isNotEmpty ?? false
                        ? rider!.name
                        : 'Delivery partner',
                    style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: ZopiqSpacing.md),
                  Divider(height: 1, color: zc.divider),
                  const SizedBox(height: ZopiqSpacing.md),
                  _Row(
                    icon: Icons.alternate_email_rounded,
                    text: rider?.email ?? '',
                  ),
                  const SizedBox(height: ZopiqSpacing.sm),
                  _Row(icon: Icons.phone_rounded, text: rider?.phone ?? ''),
                ],
              ),
            ),
            const SizedBox(height: ZopiqSpacing.md),
            Text(
              'To change any of this, ask the Zopiqnow team.',
              style: t.bodySmall?.copyWith(color: zc.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: ZopiqSpacing.xl),
            ZopiqButton(
              label: 'Sign out',
              variant: ZopiqButtonVariant.outline,
              onPressed: () =>
                  ref.read(riderAuthControllerProvider.notifier).signOut(),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: zc.textMuted),
        const SizedBox(width: ZopiqSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: zc.textMuted),
          ),
        ),
      ],
    );
  }
}
