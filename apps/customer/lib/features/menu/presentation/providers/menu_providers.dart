import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiqnow/features/menu/data/datasources/menu_mock_datasource.dart';
import 'package:zopiqnow/features/menu/data/repositories/menu_repository_impl.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_category.dart';
import 'package:zopiqnow/features/menu/domain/entities/menu_item.dart';
import 'package:zopiqnow/features/menu/domain/repositories/menu_repository.dart';

final Provider<MenuMockDataSource> menuDataSourceProvider =
    Provider<MenuMockDataSource>((Ref ref) => const MenuMockDataSource());

final Provider<MenuRepository> menuRepositoryProvider =
    Provider<MenuRepository>(
      (Ref ref) => MenuRepositoryImpl(ref.watch(menuDataSourceProvider)),
    );

/// Menu for a given restaurant id, as an [AsyncValue] (loading/data/error).
final AutoDisposeFutureProviderFamily<List<MenuCategory>, String> menuProvider =
    FutureProvider.autoDispose.family<List<MenuCategory>, String>(
      (Ref ref, String restaurantId) =>
          ref.watch(menuRepositoryProvider).getMenu(restaurantId),
    );

/// The menu screen's "Veg only" switch.
final NotifierProvider<VegOnlyNotifier, bool> vegOnlyProvider =
    NotifierProvider<VegOnlyNotifier, bool>(VegOnlyNotifier.new);

class VegOnlyNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

/// The menu with "Veg only" applied, dropping categories that end up empty so
/// the screen never renders a heading over nothing.
final AutoDisposeFutureProviderFamily<List<MenuCategory>, String>
filteredMenuProvider = FutureProvider.autoDispose
    .family<List<MenuCategory>, String>((Ref ref, String restaurantId) async {
      final List<MenuCategory> menu = await ref.watch(
        menuProvider(restaurantId).future,
      );
      if (!ref.watch(vegOnlyProvider)) return menu;

      final List<MenuCategory> result = <MenuCategory>[];
      for (final MenuCategory c in menu) {
        final List<MenuItem> veg = c.items
            .where((MenuItem i) => i.isVeg)
            .toList(growable: false);
        if (veg.isNotEmpty) {
          result.add(MenuCategory(title: c.title, items: veg));
        }
      }
      return result;
    });
