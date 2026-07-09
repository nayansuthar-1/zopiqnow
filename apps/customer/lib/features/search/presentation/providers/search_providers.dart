import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';
import 'package:zopiqnow/features/home/presentation/providers/home_providers.dart';

/// What the user has typed, updated on every keystroke. Debouncing happens
/// downstream in [searchResultsProvider], not here — the field must stay
/// perfectly responsive regardless of how slow search is.
final NotifierProvider<SearchQueryNotifier, String> searchQueryProvider =
    NotifierProvider<SearchQueryNotifier, String>(SearchQueryNotifier.new);

class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;

  void clear() => state = '';
}

/// Delay between the last keystroke and the search actually running.
const Duration searchDebounce = Duration(milliseconds: 300);

/// Debounced search results.
///
/// Re-runs on every keystroke, but waits [searchDebounce] before touching the
/// repository. If the query changes during that wait, this provider is disposed
/// and rebuilt, so the in-flight call is abandoned before it is ever made —
/// typing "biryani" costs one search, not seven.
final AutoDisposeFutureProvider<List<Restaurant>> searchResultsProvider =
    FutureProvider.autoDispose<List<Restaurant>>((Ref ref) async {
  final String query = ref.watch(searchQueryProvider).trim();
  if (query.isEmpty) return const <Restaurant>[];

  bool cancelled = false;
  ref.onDispose(() => cancelled = true);

  await Future<void>.delayed(searchDebounce);
  if (cancelled) return const <Restaurant>[];

  return ref.watch(restaurantRepositoryProvider).searchRestaurants(query);
});

/// Queries the user has *deliberately* run this session, most recent first.
///
/// Recorded by the UI on submit or on opening a result — not by the debounced
/// results provider, which would otherwise fill this list with every prefix the
/// user paused on ("b", "bir", "biryani").
///
/// In memory only: these vanish on restart. `shared_preferences` landed with the
/// Step 5 storage layer, so persisting them is now a small wiring job through
/// `KeyValueStore` rather than a dependency decision.
final NotifierProvider<RecentSearchesNotifier, List<String>>
    recentSearchesProvider =
    NotifierProvider<RecentSearchesNotifier, List<String>>(
  RecentSearchesNotifier.new,
);

class RecentSearchesNotifier extends Notifier<List<String>> {
  static const int _max = 5;

  @override
  List<String> build() => const <String>[];

  /// Moves [query] to the front, de-duplicated case-insensitively.
  void record(String query) {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) return;

    final String lower = trimmed.toLowerCase();
    final List<String> next = <String>[
      trimmed,
      ...state.where((String s) => s.toLowerCase() != lower),
    ];
    state = next.take(_max).toList(growable: false);
  }

  void clear() => state = const <String>[];
}
