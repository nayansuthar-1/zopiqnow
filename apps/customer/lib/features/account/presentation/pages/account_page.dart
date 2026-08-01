import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/app/providers/theme_mode_provider.dart';
import 'package:zopiqnow/features/auth/domain/entities/auth_user.dart';
import 'package:zopiqnow/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiqnow/features/account/domain/legal_documents.dart';
import 'package:zopiqnow/features/account/presentation/providers/veg_mode_provider.dart';
import 'package:zopiqnow/features/account/presentation/widgets/profile_avatar.dart';

/// The customer Account screen, opened from the Home profile button.
///
/// Laid out like Zomato's account: an identity header, then grouped rows for
/// orders, saved data, and the legal and support routes.
///
/// **Every row on this screen goes somewhere.** It used to carry five that
/// raised a "coming soon" snackbar — Payment Methods, See Recommendation,
/// Offers, Help & support, Settings — which is an app telling a new customer,
/// on their first look around, that most of it is not finished. A row that has
/// nothing behind it is removed until it does; that is cheaper than a row that
/// apologises, and it reads as a smaller app rather than an abandoned one.
class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});

  /// Support, for now, is an email address — and saying so plainly beats a
  /// "coming soon". A real ticket queue is a separate piece of work; until it
  /// exists, a customer with a problem needs somewhere to send it, and the Play
  /// listing needs the same address to be reachable from inside the app.
  void _showSupport(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Help & support'),
        content: const Text(
          'Email us and a person will answer.\n\n$supportEmail\n\n'
          'If it is about an order, send the order number — it is on the order '
          'in My orders.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
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
          const _SectionCard(
            children: <Widget>[
              _VegModeTile(),
              _AppearanceTile(),
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
            ],
          ),

          const SizedBox(height: ZopiqSpacing.lg),
          const _SectionLabel('More'),
          _SectionCard(
            children: <Widget>[
              _AccountTile(
                icon: Icons.headset_mic_rounded,
                title: 'Help & support',
                subtitle: supportEmail,
                onTap: () => _showSupport(context),
              ),
              _AccountTile(
                icon: Icons.shield_outlined,
                title: 'Privacy policy',
                onTap: () => context.pushNamed(
                  Routes.legal,
                  pathParameters: const <String, String>{'doc': 'privacy'},
                ),
              ),
              _AccountTile(
                icon: Icons.description_outlined,
                title: 'Terms of service',
                onTap: () => context.pushNamed(
                  Routes.legal,
                  pathParameters: const <String, String>{'doc': 'terms'},
                ),
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
            // Below sign-out, and reachable in two taps from the app's main
            // menu — Play requires the route to be findable, and burying it
            // three levels down under "Settings" is how apps fail that check.
            // It is a plain text link rather than a button because it is not an
            // action anybody should be one mis-tap away from.
            const SizedBox(height: ZopiqSpacing.md),
            Center(
              child: TextButton(
                onPressed: () => context.pushNamed(Routes.deleteAccount),
                child: Text(
                  'Delete account',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.zc.textMuted,
                    decoration: TextDecoration.underline,
                    decorationColor: context.zc.textMuted,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: ZopiqSpacing.xl),
        ],
      ),
    );
  }
}

class _ProfileCard extends ConsumerWidget {
  const _ProfileCard({required this.auth});

  final AuthState auth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    final AuthUser user = (auth as AuthSignedIn).user;
    // Null when they have never set a name and no provider gave us one. The row
    // then invites them to add one instead of asserting they are 'Zopiq user',
    // which is what it used to do — and which meant the screen looked filled in
    // when nothing had been filled in.
    final String? name = user.fullName?.trim().isEmpty ?? true
        ? null
        : user.fullName!.trim();

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
                child: ProfileAvatar(
                  url: user.avatarUrl,
                  initial: user.initial,
                  radius: 36,
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
                    Text(
                      name ?? 'Add your name',
                      style: name == null
                          ? t.titleLarge?.copyWith(color: zc.textMuted)
                          : t.titleLarge,
                    ),
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

class _VegModeTile extends ConsumerWidget {
  const _VegModeTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool isVeg = ref.watch(vegModeProvider);

    void set(bool v) => ref.read(vegModeProvider.notifier).set(v);

    return ListTile(
      onTap: () => set(!isVeg),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.pageGutter,
        vertical: ZopiqSpacing.xxs,
      ),
      horizontalTitleGap: 8,
      leading: Icon(Icons.eco_rounded, color: zc.veg, size: 20),
      title: Text('100% Veg Mode', style: t.titleSmall),
      subtitle: Text(
        'Show only vegetarian restaurants',
        style: t.bodySmall?.copyWith(color: zc.textMuted),
      ),
      trailing: Switch(
        value: isVeg,
        onChanged: set,
        activeThumbColor: zc.veg,
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
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
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
      trailing: Icon(Icons.chevron_right_rounded, color: zc.textMuted),
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
      // The rows in here are `ListTile`s, and a ListTile paints its background
      // and its tap ripple onto the nearest `Material` ancestor. Without this
      // one, that ancestor is somewhere above the decorated Container — so the
      // ripple was being painted *behind* an opaque white box and never seen.
      //
      // Flutter asserts on exactly this arrangement, which is why 11 tests
      // across four files were failing: every one of them mounts a screen that
      // reaches this card. Transparency, so the Container's own colour, border
      // and shadow still show through unchanged.
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: children,
        ),
      ),
    );
  }
}
