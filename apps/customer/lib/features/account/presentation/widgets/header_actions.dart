import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiqnow/features/notifications/presentation/providers/notifications_providers.dart';

/// The bell and the face, as one pair, for every screen that wants a header.
///
/// Home had these two built into `home_app_bar.dart` as private widgets, which
/// was fine while Home was the only screen with a header — Gifts and Collection
/// then had no way to show them without a copy, and a copied avatar is how the
/// same person ends up with two different pictures on two tabs.
///
/// **They come in two liveries, because they sit on two kinds of background.**
/// Home's header floats over the hero carousel and the orange strip, so its
/// glyphs are white on translucent white. Gifts and Collection are ordinary
/// surfaces, where white-on-white is nothing at all — [onColour] picks between
/// the two, and it is a single flag rather than four colour parameters so a
/// caller cannot get half of it right.
class HeaderActions extends StatelessWidget {
  const HeaderActions({this.onColour = true, super.key});

  /// True on a coloured or photographic background (Home's hero); false on the
  /// page's own surface (Gifts, Collection).
  final bool onColour;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        HeaderBell(onColour: onColour),
        const SizedBox(width: ZopiqSpacing.sm),
        HeaderProfileButton(onColour: onColour),
      ],
    );
  }
}

/// Background and foreground for one header glyph, given the livery.
({Color background, Color foreground}) _livery(
  BuildContext context,
  bool onColour,
) {
  if (onColour) {
    return (
      background: ZopiqPalette.white.withValues(alpha: 0.22),
      foreground: ZopiqPalette.white,
    );
  }
  final ZopiqColors zc = context.zc;
  return (
    background: zc.textStrong.withValues(alpha: 0.06),
    foreground: zc.textStrong,
  );
}

/// The notifications bell, wearing its unread count.
class HeaderBell extends ConsumerWidget {
  const HeaderBell({this.onColour = true, super.key});

  final bool onColour;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int unread = ref.watch(unreadCountProvider);
    final ZopiqColors zc = context.zc;
    final ({Color background, Color foreground}) skin = _livery(
      context,
      onColour,
    );

    return InkResponse(
      onTap: () => context.pushNamed(Routes.notifications),
      radius: 24,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          CircleAvatar(
            radius: 18,
            backgroundColor: skin.background,
            child: Icon(
              // Filled while something is unread, outlined when nothing is —
              // the weight itself carries the state, so the badge is a count
              // rather than the only signal that there is anything to read.
              unread > 0 ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
              color: skin.foreground,
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
                  color: zc.nonVeg,
                  shape: BoxShape.circle,
                  border: Border.all(color: ZopiqPalette.white, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  unread > 9 ? '9+' : '$unread',
                  style: const TextStyle(
                    color: ZopiqPalette.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The customer's own face, when there is one.
///
/// Deliberately *not* `ProfileAvatar`, which is the right widget on the account
/// screen and the wrong one here: its no-photo fallback is a brand-tinted
/// initial, and on Home's orange header a pale orange disc on orange vanishes.
/// So the photo is shared and the fallback is not.
class HeaderProfileButton extends ConsumerWidget {
  const HeaderProfileButton({this.onColour = true, super.key});

  final bool onColour;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AuthState auth = ref.watch(authControllerProvider);
    final String? avatarUrl = auth is AuthSignedIn ? auth.user.avatarUrl : null;
    final ({Color background, Color foreground}) skin = _livery(
      context,
      onColour,
    );

    final Widget fallback = ColoredBox(
      color: skin.background,
      child: Icon(
        Icons.person_rounded,
        color: skin.foreground,
        size: 20,
      ),
    );

    return InkResponse(
      onTap: () => context.pushNamed(Routes.account),
      radius: 24,
      child: SizedBox(
        width: 36,
        height: 36,
        child: ClipOval(
          // A hairline so a photo of any brightness still reads as a distinct
          // control rather than as a rectangle of somebody's face bleeding into
          // whatever is behind it.
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: onColour
                    ? ZopiqPalette.white.withValues(alpha: 0.6)
                    : context.zc.divider,
                width: 1.5,
              ),
            ),
            // `ZopiqNetworkImage` already owns empty, loading and failed, so a
            // Cloudinary URL that 404s lands on the same glyph as no photo at
            // all rather than on a broken-image icon.
            child: ZopiqNetworkImage(url: avatarUrl ?? '', fallback: fallback),
          ),
        ),
      ),
    );
  }
}
