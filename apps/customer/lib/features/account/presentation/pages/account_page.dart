import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/app/providers/theme_mode_provider.dart';
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
          _ProfileCard(auth: auth),
          const SizedBox(height: ZopiqSpacing.lg),

          const _SectionLabel('My Preferences'),
          _SectionCard(
            children: <Widget>[
              const _VegModeTile(),
              const _AppearanceTile(),
              _AccountTile(
                icon: Icons.account_balance_wallet_rounded,
                title: 'Payment Methods',
                subtitle: 'Cards, UPI, Wallets, Netbanking, Pay on delivery',
                onTap: () => _comingSoon(context, 'Payment Methods'),
              ),
            ],
          ),

          const SizedBox(height: ZopiqSpacing.lg),
          const _SectionLabel('Food Delivery'),
          _SectionCard(
            children: <Widget>[
              _AccountTile(
                icon: Icons.receipt_long_rounded,
                title: 'My orders',
                subtitle: 'Track and reorder past orders',
                onTap: () => context.pushNamed(Routes.orders),
              ),
              _AccountTile(
                icon: Icons.location_on_rounded,
                title: 'My addresses',
                subtitle: 'Manage your delivery addresses',
                onTap: () => context.pushNamed(Routes.addresses),
              ),
              _AccountTile(
                icon: Icons.favorite_rounded,
                iconColor: context.zc.nonVeg,
                title: 'Your collection',
                subtitle: 'Restaurants you saved',
                onTap: () => context.pushNamed(Routes.favourites),
              ),
              _AccountTile(
                icon: Icons.star_rounded,
                title: 'See Recommendation',
                comingSoon: true,
                onTap: () => _comingSoon(context, 'See Recommendation'),
              ),
            ],
          ),

          const SizedBox(height: ZopiqSpacing.lg),
          const _SectionLabel('More'),
          _SectionCard(
            children: <Widget>[
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
            ],
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

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.auth});

  final AuthState auth;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final ZopiqColors zc = context.zc;
    final bool signedIn = auth is AuthSignedIn;

    if (!signedIn) {
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
              child: Column(
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
            TextButton(
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

    final String name = 'Zopiq user';

    return Container(
      margin: ZopiqSpacing.pagePadding,
      height: 160,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: ZopiqRadii.rLg,
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
        border: Border.all(color: zc.divider),
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: <Widget>[
            Expanded(
              child: Center(
                child: CircleAvatar(
                  radius: 36,
                  backgroundColor: zc.primary.withValues(alpha: 0.12),
                  child: Icon(Icons.person_rounded, color: zc.primary, size: 40),
                ),
              ),
            ),
            Center(
              child: Container(
                width: 80,
                height: 1,
                color: zc.divider,
              ),
            ),
            InkWell(
              onTap: () => context.pushNamed(Routes.profile),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ZopiqSpacing.md,
                  vertical: ZopiqSpacing.md,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Text(name, style: t.titleLarge),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Icon(Icons.chevron_right_rounded, color: zc.textMuted, size: 28),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VegModeTile extends StatefulWidget {
  const _VegModeTile();

  @override
  State<_VegModeTile> createState() => _VegModeTileState();
}

class _VegModeTileState extends State<_VegModeTile> {
  bool _isVeg = false;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return ListTile(
      onTap: () => setState(() => _isVeg = !_isVeg),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.pageGutter,
        vertical: ZopiqSpacing.xxs,
      ),
      horizontalTitleGap: 8,
      leading: Icon(Icons.eco_rounded, color: zc.veg, size: 20),
      title: Text('100% Veg Mode', style: t.titleSmall),
      subtitle: Text(
        'Show only vegetarian options',
        style: t.bodySmall?.copyWith(color: zc.textMuted),
      ),
      trailing: Switch(
        value: _isVeg,
        onChanged: (bool v) => setState(() => _isVeg = v),
        activeColor: zc.veg,
      ),
    );
  }
}

class _AppearanceTile extends ConsumerWidget {
  const _AppearanceTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeMode mode = ref.watch(themeModeProvider);
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.pageGutter,
        vertical: ZopiqSpacing.xxs,
      ),
      horizontalTitleGap: 8,
      leading: const Icon(Icons.color_lens_rounded, size: 20),
      title: Text('Appearance', style: t.titleSmall),
      subtitle: Text(
        'Light, Dark, or System',
        style: t.bodySmall?.copyWith(color: zc.textMuted),
      ),
      trailing: DropdownButton<ThemeMode>(
        value: mode,
        underline: const SizedBox(),
        icon: Icon(Icons.expand_more_rounded, color: zc.textMuted),
        items: const <DropdownMenuItem<ThemeMode>>[
          DropdownMenuItem<ThemeMode>(
            value: ThemeMode.light,
            child: Text('Light', style: TextStyle(fontSize: 14)),
          ),
          DropdownMenuItem<ThemeMode>(
            value: ThemeMode.dark,
            child: Text('Dark', style: TextStyle(fontSize: 14)),
          ),
          DropdownMenuItem<ThemeMode>(
            value: ThemeMode.system,
            child: Text('System', style: TextStyle(fontSize: 14)),
          ),
        ],
        onChanged: (ThemeMode? newMode) {
          if (newMode != null) {
            ref.read(themeModeProvider.notifier).set(newMode);
          }
        },
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
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool comingSoon;
  final VoidCallback onTap;
  final Color? iconColor;

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
      horizontalTitleGap: 8,
      leading: Icon(icon, size: 20, color: iconColor),
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: ZopiqSpacing.pageGutter),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: ZopiqRadii.rLg,
        border: Border.all(color: context.zc.divider),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: children,
      ),
    );
  }
}
