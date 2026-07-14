import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiqnow/features/favourites/domain/repositories/favourites_repository.dart';
import 'package:zopiqnow/features/favourites/presentation/providers/favourites_providers.dart';
import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';

/// The heart. Sits on a restaurant's photo, and is the cheapest interaction in
/// the app — so it fills instantly and asks the network afterwards.
class FavouriteButton extends ConsumerWidget {
  const FavouriteButton({required this.restaurant, super.key});

  final Restaurant restaurant;

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    // A favourite belongs to an account. A signed-out tap is not an error and it
    // is certainly not a no-op — it is someone telling us they want this saved,
    // so it opens the login and comes back to where they were. `go`, not `push`,
    // and `?from=`: the same rule the guard follows, for the same reason.
    if (ref.read(authControllerProvider) is! AuthSignedIn) {
      final String here = GoRouterState.of(context).uri.toString();
      context.goNamed(
        Routes.login,
        queryParameters: <String, String>{'from': here},
      );
      return;
    }

    // Fired, never awaited. The platform channel behind it does not complete
    // under the test binding, so awaiting it hangs every widget test that taps a
    // heart — and even on a device, a buzz is a side effect, not a step the save
    // is waiting on.
    unawaited(HapticFeedback.lightImpact());

    try {
      await ref.read(favouritesProvider.notifier).toggle(restaurant);
    } on FavouritesFailure catch (failure) {
      // The heart has already snapped back — the controller restored it. All
      // that is left is to say why, rather than let the UI quietly disagree with
      // the server.
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(failure.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final bool isFavourite = ref.watch(isFavouriteProvider(restaurant.id));

    return Semantics(
      button: true,
      label: isFavourite
          ? 'Remove ${restaurant.name} from favourites'
          : 'Save ${restaurant.name} to favourites',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _toggle(context, ref),
        child: Container(
          padding: const EdgeInsets.all(ZopiqSpacing.sm),
          decoration: BoxDecoration(
            // The photo underneath is arbitrary, so the heart carries its own
            // background — a red heart on a red curry is invisible.
            color: Colors.white.withValues(alpha: 0.92),
            shape: BoxShape.circle,
            boxShadow: <BoxShadow>[
              BoxShadow(color: zc.cardShadow, blurRadius: 8),
            ],
          ),
          // The pop is the whole reward for the tap: the icon scales in rather
          // than swapping. Scale only — a heart that reflowed the card it sits
          // on would be a very expensive heart.
          child: AnimatedSwitcher(
            duration: ZopiqDurations.fast,
            transitionBuilder: (Widget child, Animation<double> animation) =>
                ScaleTransition(scale: animation, child: child),
            child: Icon(
              isFavourite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              // Keyed so the switcher treats filled and outline as *different*
              // children — without it, it would cross-fade an icon into itself
              // and nothing would animate.
              key: ValueKey<bool>(isFavourite),
              size: 20,
              color: isFavourite ? zc.nonVeg : zc.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
