import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/features/auth/presentation/providers/auth_providers.dart';

/// The customer Account screen, opened from the Home profile button.
///
/// Laid out like Zomato's account: an identity header, then grouped rows for
/// orders, saved data, and support. The features behind Orders / Favourites /
/// Payments / Help are not built yet, so those rows are read-only — tapping one
/// says so rather than opening a dead screen. The rows that *do* have a
/// destination today (addresses, licenses, sign-out) are live. As each feature
/// lands, swap its row's `onTap` for the real route.
class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});

  void _comingSoon(BuildContext context, String label) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$label is coming soon')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AuthState auth = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.lg),
        children: <Widget>[
          _ProfileHeader(auth: auth),
          const SizedBox(height: ZopiqSpacing.lg),

          const _SectionLabel('Your orders & saved items'),
          _AccountTile(
            icon: Icons.receipt_long_rounded,
            title: 'Your orders',
            subtitle: 'Track and reorder past orders',
            // Guarded by the router: a signed-out tap lands on login and comes
            // back here afterwards, which is why this tile needs no auth check.
            onTap: () => context.pushNamed(Routes.orders),
          ),
          _AccountTile(
            icon: Icons.favorite_rounded,
            title: 'Favourites',
            comingSoon: true,
            onTap: () => _comingSoon(context, 'Favourites'),
          ),
          _AccountTile(
            icon: Icons.location_on_rounded,
            title: 'Address book',
            subtitle: 'Manage your delivery addresses',
            // The book, not the picker sheet. The sheet answers "where am I
            // ordering to right now"; this answers "what addresses do I have",
            // and until now the second question had no screen and no answer.
            onTap: () => context.pushNamed(Routes.addresses),
          ),
          _AccountTile(
            icon: Icons.account_balance_wallet_rounded,
            title: 'Payments & refunds',
            comingSoon: true,
            onTap: () => _comingSoon(context, 'Payments & refunds'),
          ),

          const SizedBox(height: ZopiqSpacing.lg),
          const _SectionLabel('More'),
          _AccountTile(
            icon: Icons.local_offer_rounded,
            title: 'Offers',
            comingSoon: true,
            onTap: () => _comingSoon(context, 'Offers'),
          ),
          _AccountTile(
            icon: Icons.headset_mic_rounded,
            title: 'Help & support',
            comingSoon: true,
            onTap: () => _comingSoon(context, 'Help & support'),
          ),
          _AccountTile(
            icon: Icons.settings_rounded,
            title: 'Settings',
            comingSoon: true,
            onTap: () => _comingSoon(context, 'Settings'),
          ),
          _AccountTile(
            icon: Icons.info_outline_rounded,
            title: 'Licenses & credits',
            onTap: () => context.pushNamed(Routes.licenses),
          ),
          if (kDebugMode)
            _AccountTile(
              icon: Icons.palette_outlined,
              title: 'Design system',
              onTap: () => context.pushNamed(Routes.showcase),
            ),

          if (auth is AuthSignedIn) ...<Widget>[
            const SizedBox(height: ZopiqSpacing.xl),
            _LogoutButton(
              onTap: () async {
                await ref.read(authControllerProvider.notifier).signOut();
                if (context.mounted) context.pop();
              },
            ),
          ],
          const SizedBox(height: ZopiqSpacing.xl),
        ],
      ),
    );
  }
}

/// Identity block. Signed in: avatar + phone. Signed out: a call to log in.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.auth});

  final AuthState auth;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final ZopiqColors zc = context.zc;
    final bool signedIn = auth is AuthSignedIn;

    return Padding(
      padding: ZopiqSpacing.pagePadding,
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 28,
            backgroundColor: zc.primary.withValues(alpha: 0.12),
            child: Icon(Icons.person_rounded, color: zc.primary, size: 30),
          ),
          const SizedBox(width: ZopiqSpacing.md),
          Expanded(
            child: signedIn
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Zopiq user', style: t.titleMedium),
                      const SizedBox(height: ZopiqSpacing.xxs),
                      Text(
                        (auth as AuthSignedIn).user.email,
                        style: t.bodyMedium?.copyWith(color: zc.textMuted),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Welcome to zopiqnow', style: t.titleMedium),
                      const SizedBox(height: ZopiqSpacing.xxs),
                      Text(
                        'Log in to track orders and save addresses',
                        style: t.bodySmall?.copyWith(color: zc.textMuted),
                      ),
                    ],
                  ),
          ),
          if (!signedIn)
            TextButton(
              // `go`, not `push` (SAD 7.10: no screen pushes a login route
              // imperatively). A pushed login flow sits above the router's
              // location, so the post-sign-in redirect moves the location out
              // from under it and leaves the OTP screen on screen, spinning.
              // `from` is what brings the user back here afterwards.
              onPressed: () => context.goNamed(
                Routes.login,
                queryParameters: const <String, String>{'from': '/account'},
              ),
              child: const Text('Log in'),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.sm,
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.xs,
      ),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: context.zc.textMuted,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.comingSoon = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool comingSoon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.pageGutter,
        vertical: ZopiqSpacing.xxs,
      ),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: zc.primary.withValues(alpha: 0.10),
          borderRadius: ZopiqRadii.rMd,
        ),
        child: Icon(icon, color: zc.primary, size: 22),
      ),
      title: Text(title, style: t.titleSmall),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: t.bodySmall?.copyWith(color: zc.textMuted),
            ),
      trailing: comingSoon
          ? Container(
              padding: const EdgeInsets.symmetric(
                horizontal: ZopiqSpacing.sm,
                vertical: ZopiqSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: zc.textMuted.withValues(alpha: 0.12),
                borderRadius: ZopiqRadii.rPill,
              ),
              child: Text(
                'Soon',
                style: t.labelSmall?.copyWith(color: zc.textMuted),
              ),
            )
          : Icon(Icons.chevron_right_rounded, color: zc.textMuted),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  const _LogoutButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;

    return Padding(
      padding: ZopiqSpacing.pagePadding,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(Icons.logout_rounded, color: zc.nonVeg),
        label: Text('Log out', style: TextStyle(color: zc.nonVeg)),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          side: BorderSide(color: zc.divider),
          shape: const RoundedRectangleBorder(
            borderRadius: ZopiqRadii.rMd,
          ),
        ),
      ),
    );
  }
}
