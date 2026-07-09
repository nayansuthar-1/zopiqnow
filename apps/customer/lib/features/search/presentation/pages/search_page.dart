import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';
import 'package:zopiqnow/features/home/domain/repositories/restaurant_repository.dart';
import 'package:zopiqnow/features/home/presentation/widgets/restaurant_card.dart';
import 'package:zopiqnow/features/search/presentation/providers/search_providers.dart';

/// Restaurant search. Results reuse [RestaurantCard], so a restaurant looks the
/// same here as on Home.
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({required this.onOpenRestaurant, super.key});

  final void Function(Restaurant restaurant) onOpenRestaurant;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  late final TextEditingController _controller = TextEditingController(
    text: ref.read(searchQueryProvider),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String query) {
    if (query.trim().isEmpty) return;
    ref.read(recentSearchesProvider.notifier).record(query);
  }

  void _useRecent(String query) {
    _controller.text = query;
    ref.read(searchQueryProvider.notifier).set(query);
  }

  void _open(Restaurant restaurant) {
    // Opening a result means the query was a good one; worth remembering.
    ref.read(recentSearchesProvider.notifier).record(ref.read(searchQueryProvider));
    widget.onOpenRestaurant(restaurant);
  }

  @override
  Widget build(BuildContext context) {
    final String query = ref.watch(searchQueryProvider).trim();
    final AsyncValue<List<Restaurant>> results = ref.watch(searchResultsProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: ZopiqSpacing.pageGutter,
        title: _SearchField(
          controller: _controller,
          onChanged: ref.read(searchQueryProvider.notifier).set,
          onSubmitted: _submit,
          onClear: () {
            _controller.clear();
            ref.read(searchQueryProvider.notifier).clear();
          },
        ),
      ),
      body: query.isEmpty
          ? _RecentSearches(onTap: _useRecent)
          : results.when(
              // The debounce lives inside the provider, so this shimmer covers
              // both the wait and the fetch. To the user they are one thing.
              loading: () => const _SearchSkeleton(),
              error: (Object error, _) => _SearchError(
                message: error is RestaurantLoadFailure
                    ? error.message
                    : 'Please check your connection and try again.',
                onRetry: () => ref.invalidate(searchResultsProvider),
              ),
              data: (List<Restaurant> found) => found.isEmpty
                  ? _NoResults(query: query)
                  : _Results(restaurants: found, onTap: _open),
            ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;

    return TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      autofocus: true,
      textInputAction: TextInputAction.search,
      style: Theme.of(context).textTheme.bodyLarge,
      decoration: InputDecoration(
        hintText: 'Search for restaurants or cuisines',
        prefixIcon: Icon(Icons.search_rounded, color: zc.textMuted, size: 22),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (BuildContext context, TextEditingValue value, _) {
            if (value.text.isEmpty) return const SizedBox.shrink();
            return IconButton(
              icon: Icon(Icons.close_rounded, color: zc.textMuted, size: 20),
              onPressed: onClear,
            );
          },
        ),
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.restaurants, required this.onTap});

  final List<Restaurant> restaurants;
  final ValueChanged<Restaurant> onTap;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(ZopiqSpacing.lg),
      itemCount: restaurants.length,
      separatorBuilder: (_, _) => const SizedBox(height: ZopiqSpacing.lg),
      itemBuilder: (BuildContext context, int i) => RepaintBoundary(
        child: RestaurantCard(
          restaurant: restaurants[i],
          onTap: () => onTap(restaurants[i]),
          // Home's card owns the Hero tag for this restaurant; both screens are
          // mounted at once inside the shell. See RestaurantCard.heroic.
          heroic: false,
        ),
      ),
    );
  }
}

class _RecentSearches extends ConsumerWidget {
  const _RecentSearches({required this.onTap});

  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<String> recents = ref.watch(recentSearchesProvider);
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    if (recents.isEmpty) {
      return const _Centered(
        icon: Icons.search_rounded,
        title: 'What are you craving?',
        detail: 'Search by restaurant or cuisine — try "biryani".',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(ZopiqSpacing.lg),
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text('Recent searches', style: t.titleSmall),
            TextButton(
              onPressed: ref.read(recentSearchesProvider.notifier).clear,
              child: const Text('Clear'),
            ),
          ],
        ),
        for (final String query in recents)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.history_rounded, color: zc.textMuted),
            title: Text(query, style: t.bodyLarge),
            trailing: Icon(Icons.north_west_rounded, size: 18, color: zc.textMuted),
            onTap: () => onTap(query),
          ),
      ],
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return _Centered(
      icon: Icons.search_off_rounded,
      title: 'No results for "$query"',
      detail: 'Try a different dish, cuisine, or restaurant name.',
    );
  }
}

class _SearchError extends StatelessWidget {
  const _SearchError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

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
            Icon(Icons.wifi_off_rounded, size: 56, color: zc.textMuted),
            const SizedBox(height: ZopiqSpacing.lg),
            Text(
              message,
              style: t.bodyMedium?.copyWith(color: zc.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: ZopiqSpacing.xl),
            ZopiqButton(
              label: 'Try again',
              icon: Icons.refresh_rounded,
              expand: false,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchSkeleton extends StatelessWidget {
  const _SearchSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(ZopiqSpacing.lg),
      child: ZopiqShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ZopiqSkeletonBox(height: 180, borderRadius: ZopiqRadii.rLg),
            SizedBox(height: ZopiqSpacing.lg),
            ZopiqSkeletonBox(height: 180, borderRadius: ZopiqRadii.rLg),
          ],
        ),
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

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
              detail,
              style: t.bodyMedium?.copyWith(color: zc.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
