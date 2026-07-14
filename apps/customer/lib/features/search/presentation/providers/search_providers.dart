import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiqnow/core/storage/key_value_store.dart';
import 'package:zopiqnow/core/storage/storage_providers.dart';
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

/// Queries the user has *deliberately* run, most recent first.
///
/// Recorded by the UI on submit or on opening a result — not by the debounced
/// results provider, which would otherwise fill this list with every prefix the
/// user paused on ("b", "bir", "biryani").
///
/// Persisted through [KeyValueStore], so they survive a restart: a "recent"
/// search that forgets itself the moment the app is closed is a list of things
/// you did in the last five minutes, which you already remember. Local and not
/// account state — what this phone searched for is not a fact about the account,
/// and it is the same reasoning that keeps the selected address local.
///
/// Not the secure store: a search history is not a secret, and tokens are the
/// only thing that belongs in the Keystore.
final NotifierProvider<RecentSearchesNotifier, List<String>>
    recentSearchesProvider =
    NotifierProvider<RecentSearchesNotifier, List<String>>(
  RecentSearchesNotifier.new,
);

class RecentSearchesNotifier extends Notifier<List<String>> {
  static const int _max = 5;
  static const String _key = 'zopiq.search.recent';

  KeyValueStore get _store => ref.read(keyValueStoreProvider);

  @override
  List<String> build() {
    final String? raw = _store.getString(_key);
    if (raw == null) return const <String>[];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .cast<String>()
          .take(_max)
          .toList(growable: false);
    } on Object {
      // Written by an older build with a different shape. Forget the history
      // rather than take down the search screen over it — the same call the
      // address repository makes about a corrupt stored address.
      return const <String>[];
    }
  }

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
    _persist();
  }

  void clear() {
    state = const <String>[];
    _persist();
  }

  /// Fire-and-forget: the list is already the truth in memory, and the UI must
  /// not wait on a disk write to render what the user just typed. A failed write
  /// costs one forgotten history, not a broken screen.
  void _persist() => unawaited(_store.setString(_key, jsonEncode(state)));
}
