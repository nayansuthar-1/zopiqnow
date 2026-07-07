import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';
import 'package:zopiqnow/features/home/domain/repositories/restaurant_repository.dart';
import 'package:zopiqnow/features/home/presentation/providers/home_providers.dart';
import 'package:zopiqnow/features/home/presentation/widgets/home_app_bar.dart';
import 'package:zopiqnow/features/home/presentation/widgets/home_status_views.dart';
import 'package:zopiqnow/features/home/presentation/widgets/restaurant_card.dart';
import 'package:zopiqnow/features/home/presentation/widgets/restaurant_list_skeleton.dart';

/// Customer Home — restaurant discovery. First real vertical slice: renders the
/// [nearbyRestaurantsProvider] async feed with shimmer / success / empty / error
/// states and pull-to-refresh, all on zopiq_ui.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  // TODO(location): source from the location feature once it exists.
  static const String _address = 'Banjara Hills, Hyderabad';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Restaurant>> feed = ref.watch(nearbyRestaurantsProvider);

    return Scaffold(
      appBar: HomeAppBar(
        address: _address,
        onTapLocation: () {},
        onTapSearch: () {},
        onTapProfile: () {},
        trailing: kDebugMode
            ? IconButton(
                tooltip: 'Design system',
                onPressed: () => context.push('/showcase'),
                icon: const Icon(Icons.palette_outlined),
              )
            : null,
      ),
      body: RefreshIndicator(
        color: context.zc.primary,
        onRefresh: () => ref.refresh(nearbyRestaurantsProvider.future),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            feed.when(
              loading: () => const SliverPadding(
                padding: EdgeInsets.all(ZopiqSpacing.lg),
                sliver: SliverToBoxAdapter(child: RestaurantListSkeleton()),
              ),
              error: (Object error, _) => SliverFillRemaining(
                hasScrollBody: false,
                child: HomeErrorView(
                  message: error is RestaurantLoadFailure
                      ? error.message
                      : 'Please check your connection and try again.',
                  onRetry: () => ref.invalidate(nearbyRestaurantsProvider),
                ),
              ),
              data: (List<Restaurant> restaurants) {
                if (restaurants.isEmpty) {
                  return const SliverFillRemaining(
                    hasScrollBody: false,
                    child: HomeEmptyView(),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.all(ZopiqSpacing.lg),
                  sliver: SliverList.separated(
                    itemCount: restaurants.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: ZopiqSpacing.lg),
                    itemBuilder: (BuildContext context, int i) => RestaurantCard(
                      restaurant: restaurants[i],
                      onTap: () {},
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
