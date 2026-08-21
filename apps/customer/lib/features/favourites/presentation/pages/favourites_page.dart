import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/features/account/presentation/widgets/header_actions.dart';
import 'package:zopiqnow/features/favourites/domain/repositories/favourites_repository.dart';
import 'package:zopiqnow/features/favourites/presentation/providers/favourites_providers.dart';
import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';
import 'package:zopiqnow/features/home/presentation/providers/home_providers.dart';
import 'package:zopiqnow/features/home/presentation/widgets/restaurant_card.dart';

/// The restaurants the customer saved.
///
/// Auth-guarded by the router, like `/orders` and `/addresses`: a favourite
/// belongs to an account, and there is no such thing as a signed-out user's
/// saved restaurants.
class FavouritesPage extends ConsumerWidget {
  const FavouritesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Restaurant>> favourites = ref.watch(favouritesProvider);
    final Map<String, List<String>> photos = ref.watch(cardPhotosProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        // A branch root, so there is never anything to pop — and the two ways
        // in both arrive by `go`: the tab itself, and Account's Collection row.
        // The arrow is therefore always the fallback, and Delivery is what it
        // falls back to: the tab a customer came from, and the only one that is
        // always there.
        leading: BackButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.goNamed(Routes.home),
        ),
        title: const Text('Collection'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        // The same bell and face the other two tabs carry, in the on-surface
        // livery.
        actions: const <Widget>[
          HeaderActions(onColour: false),
          SizedBox(width: ZopiqSpacing.pageGutter),
        ],
      ),
      body: favourites.when(
        loading: () => const Center(child: ZopiqLoader()),
        error: (Object error, StackTrace _) => _Message(
          icon: Icons.cloud_off_rounded,
          title: error is FavouritesFailure
              ? error.message
              : 'We couldn\'t load your favourites',
          body: 'Check your connection and try again.',
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(favouritesProvider),
        ),
        data: (List<Restaurant> saved) {
          if (saved.isEmpty) {
            return _Message(
              icon: Icons.favorite_border_rounded,
              title: 'No favourites yet',
              body: 'Tap the heart on any restaurant and it will show up here.',
              actionLabel: 'Browse restaurants',
              onAction: () => context.goNamed(Routes.home),
            );
          }

          return RefreshIndicator.adaptive(
            onRefresh: () async => ref.refresh(favouritesProvider.future),
            child: ListView.builder(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.sm),
              itemCount: saved.length,
              itemBuilder: (BuildContext context, int i) => RepaintBoundary(
                // The same card the feed uses — a favourite *is* a restaurant,
                // and a second card that drifted from the first is how a heart
                // ends up meaning two different things on two screens.
                child: RestaurantCard(
                  restaurant: saved[i],
                  photos: photos[saved[i].id] ?? const <String>[],
                  // Home is still mounted underneath (the shell's IndexedStack
                  // keeps it alive), so a restaurant showing in both would
                  // register two Heroes under one tag and crash the next route
                  // transition. Search opts out for exactly this reason; so does
                  // this screen. It loses the image flight, not the navigation.
                  heroic: false,
                  onTap: () => context.pushNamed(
                    Routes.menu,
                    pathParameters: <String, String>{'id': saved[i].id},
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ZopiqSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 56, color: zc.textMuted),
            const SizedBox(height: ZopiqSpacing.lg),
            Text(title, style: t.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: ZopiqSpacing.xs),
            Text(
              body,
              style: t.bodyMedium?.copyWith(color: zc.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: ZopiqSpacing.xl),
            ZopiqButton(
              label: actionLabel,
              expand: false,
              onPressed: onAction,
            ),
          ],
        ),
      ),
    );
  }
}
