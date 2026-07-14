import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';

/// You proved you own that mailbox. It just isn't a restaurant.
///
/// The screen exists because this is not an error and must not be dressed as
/// one: a customer who downloads the partner app by mistake, or a cook whose
/// address ops has not added yet, has done nothing wrong. Telling them "sign-in
/// failed" would send them round the login screen forever trying to fix a
/// password that was never the problem.
class NotStaffPage extends ConsumerWidget {
  const NotStaffPage({required this.email, super.key});

  final String email;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(ZopiqSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.storefront_outlined, size: 56, color: zc.textMuted),
                const SizedBox(height: ZopiqSpacing.lg),
                Text('Not a partner account', style: t.titleMedium),
                const SizedBox(height: ZopiqSpacing.xs),
                Text(
                  '$email isn\'t registered to a restaurant on Zopiqnow.\n\n'
                  'If you run a restaurant with us, ask us to add this address. '
                  'If you\'re looking to order food, you want the Zopiqnow app.',
                  style: t.bodyMedium?.copyWith(color: zc.textMuted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: ZopiqSpacing.xl),
                ZopiqButton(
                  label: 'Try another email',
                  expand: false,
                  onPressed: () =>
                      ref.read(vendorAuthControllerProvider.notifier).signOut(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
