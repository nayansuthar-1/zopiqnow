import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/app/providers/locale_provider.dart';
import 'package:zopiqnow/app/providers/theme_mode_provider.dart';
import 'package:zopiqnow/core/l10n/app_language.dart';
import 'package:zopiqnow/core/l10n/strings.dart';
import 'package:zopiqnow/features/auth/domain/entities/auth_user.dart';
import 'package:zopiqnow/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiqnow/features/account/domain/contact.dart';
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
    final AppStrings l10n = context.l10n;
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.accountHelpSupport),
        content: Text(l10n.accountSupportBody(supportEmail)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AuthState auth = ref.watch(authControllerProvider);
    final AppStrings l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        // A signed-out customer who taps "Log in" here goes to
        // `/login?from=/account`, and the redirect `go`s back to `/account` on
        // success — which rebuilds the stack from the route tree and leaves
        // this screen as its only entry. `AppBar` then draws no leading at all
        // and the account is a dead end, at exactly the moment somebody has
        // just signed in. Same shape as `/orders`: pop when there is something
        // to pop, and otherwise go somewhere real.
        leading: BackButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.goNamed(Routes.home),
        ),
        title: Text(l10n.accountTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.lg),
        children: <Widget>[
          _ProfileCard(auth: auth),
          const SizedBox(height: ZopiqSpacing.lg),

          _SectionLabel(l10n.accountMyPreferences),
          const _SectionCard(
            children: <Widget>[
              _VegModeTile(),
              _AppearanceTile(),
              _LanguageTile(),
            ],
          ),

          const SizedBox(height: ZopiqSpacing.lg),
          _SectionLabel(l10n.accountFoodDelivery),
          _SectionCard(
            children: <Widget>[
              _AccountTile(
                icon: Icons.receipt_long_rounded,
                title: l10n.accountMyOrders,
                subtitle: l10n.accountMyOrdersSubtitle,
                onTap: () => context.pushNamed(Routes.orders),
              ),
              // Its own tile beside "My orders" rather than a filter inside it:
              // a gift is a different order with different states, and one list
              // mixing "Out for delivery" (a rider, minutes) with "On its way"
              // (a courier, days) would be one word doing two jobs.
              _AccountTile(
                icon: Icons.card_giftcard_rounded,
                title: l10n.accountGiftOrders,
                subtitle: l10n.accountGiftOrdersSubtitle,
                onTap: () => context.pushNamed(Routes.giftOrders),
              ),
              _AccountTile(
                icon: Icons.location_on_rounded,
                title: l10n.accountMyAddresses,
                subtitle: l10n.accountMyAddressesSubtitle,
                onTap: () => context.pushNamed(Routes.addresses),
              ),
              _AccountTile(
                icon: Icons.favorite_rounded,
                iconColor: context.zc.nonVeg,
                title: l10n.accountCollection,
                subtitle: l10n.accountCollectionSubtitle,
                // `go`, not `push`: Favourites is the Collection tab now, so
                // this switches to it rather than stacking a second copy on top
                // of Account and leaving a back arrow over a primary tab.
                onTap: () => context.goNamed(Routes.favourites),
              ),
            ],
          ),

          const SizedBox(height: ZopiqSpacing.lg),
          _SectionLabel(l10n.accountMore),
          _SectionCard(
            children: <Widget>[
              _AccountTile(
                icon: Icons.headset_mic_rounded,
                title: l10n.accountHelpSupport,
                subtitle: supportEmail,
                onTap: () => _showSupport(context),
              ),
              // One row, not two. There are twenty-one documents now, and the
              // two that used to sit here were never the only ones somebody
              // needed — the refund policy is the one a customer actually goes
              // looking for, and it had nowhere to be reached from.
              _AccountTile(
                icon: Icons.shield_outlined,
                title: l10n.accountLegal,
                onTap: () => context.pushNamed(Routes.legal),
              ),
              _AccountTile(
                icon: Icons.info_outline_rounded,
                title: l10n.accountLicenses,
                onTap: () => context.pushNamed(Routes.licenses),
              ),
              if (kDebugMode)
                _AccountTile(
                  icon: Icons.palette_outlined,
                  title: l10n.accountDesignSystem,
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
                  l10n.accountDeleteAccount,
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
    final AppStrings l10n = context.l10n;
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
                  Text(l10n.accountWelcome, style: t.titleMedium),
                  const SizedBox(height: ZopiqSpacing.xxs),
                  Text(
                    l10n.accountWelcomeSubtitle,
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
              child: Text(l10n.accountLogIn),
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
                      name ?? l10n.accountAddYourName,
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
      title: Text(context.l10n.accountVegMode, style: t.titleSmall),
      subtitle: Text(
        context.l10n.accountVegModeSubtitle,
        style: t.bodySmall?.copyWith(color: zc.textMuted),
      ),
      // Colours come from `switchTheme` rather than from here. This used to pass
      // `activeThumbColor: zc.veg`, which put a green thumb on a green track and
      // made the *on* state as shapeless as the off one was.
      trailing: Switch(value: isVeg, onChanged: set),
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
    final AppStrings l10n = context.l10n;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.pageGutter,
        vertical: ZopiqSpacing.xxs,
      ),
      horizontalTitleGap: 8,
      leading: const Icon(Icons.color_lens_rounded, size: 20),
      title: Text(l10n.accountAppearance, style: t.titleSmall),
      subtitle: Text(
        l10n.accountAppearanceSubtitle,
        style: t.bodySmall?.copyWith(color: zc.textMuted),
      ),
      trailing: DropdownButton<ThemeMode>(
        value: mode,
        underline: const SizedBox(),
        icon: Icon(Icons.expand_more_rounded, color: zc.textMuted),
        items: <DropdownMenuItem<ThemeMode>>[
          DropdownMenuItem<ThemeMode>(
            value: ThemeMode.light,
            child: Text(
              l10n.accountThemeLight,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          DropdownMenuItem<ThemeMode>(
            value: ThemeMode.dark,
            child: Text(
              l10n.accountThemeDark,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          DropdownMenuItem<ThemeMode>(
            value: ThemeMode.system,
            child: Text(
              l10n.accountThemeSystem,
              style: const TextStyle(fontSize: 14),
            ),
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

/// The language picker, sitting directly under Appearance.
///
/// Shaped exactly like [_AppearanceTile] on purpose — it is the same kind of
/// setting (a preference with a small closed list of values), and a customer
/// who has found one should recognise the other without reading it.
///
/// Each option is labelled in its **own** language rather than in the language
/// currently selected. An English-speaking user hunting for Hindi is looking
/// for "हिन्दी"; showing them the word "Hindi" in Latin script means the one
/// person who most needs the setting cannot spot it.
class _LanguageTile extends ConsumerWidget {
  const _LanguageTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLanguage language = ref.watch(appLanguageProvider);
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final AppStrings l10n = context.l10n;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.pageGutter,
        vertical: ZopiqSpacing.xxs,
      ),
      horizontalTitleGap: 8,
      leading: const Icon(Icons.translate_rounded, size: 20),
      title: Text(l10n.accountLanguage, style: t.titleSmall),
      subtitle: Text(
        l10n.accountLanguageSubtitle,
        style: t.bodySmall?.copyWith(color: zc.textMuted),
      ),
      trailing: DropdownButton<AppLanguage>(
        value: language,
        underline: const SizedBox(),
        icon: Icon(Icons.expand_more_rounded, color: zc.textMuted),
        items: <DropdownMenuItem<AppLanguage>>[
          for (final AppLanguage option in AppLanguage.values)
            DropdownMenuItem<AppLanguage>(
              value: option,
              child: Text(
                option.nativeName,
                style: const TextStyle(fontSize: 14),
              ),
            ),
        ],
        onChanged: (AppLanguage? chosen) {
          if (chosen != null) {
            ref.read(appLanguageProvider.notifier).set(chosen);
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
        label: Text(
          context.l10n.accountLogOut,
          style: TextStyle(color: zc.nonVeg),
        ),
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
