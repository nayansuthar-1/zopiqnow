import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiq_vendor/features/menu/data/dish_options_datasource.dart';
import 'package:zopiq_vendor/features/menu/domain/entities/dish_options.dart';

/// Data source binding. Overridden in tests, which have no Supabase instance.
final Provider<DishOptionsDataSource> dishOptionsDataSourceProvider =
    Provider<DishOptionsDataSource>(
      (Ref ref) => const DishOptionsSupabaseDataSource(),
    );

/// The current groups for one dish, loaded on demand. `.family` keyed by dish id
/// so opening customisation for a dish reads exactly that dish's options.
final FutureProviderFamily<List<DishOptionGroup>, String> dishOptionsProvider =
    FutureProvider.family<List<DishOptionGroup>, String>(
      (Ref ref, String dishId) =>
          ref.watch(dishOptionsDataSourceProvider).fetch(dishId),
    );

/// The one write the customisation editor makes. Returns null on success, or a
/// sentence to show — the same shape the rest of the menu controllers use.
class DishOptionsController extends Notifier<void> {
  @override
  void build() {}

  Future<String?> save(String dishId, List<DishOptionGroup> groups) async {
    try {
      await ref.read(dishOptionsDataSourceProvider).save(dishId, groups);
      ref.invalidate(dishOptionsProvider(dishId));
      return null;
    } on Object {
      return 'We couldn\'t save the customisation. Please try again.';
    }
  }
}

final NotifierProvider<DishOptionsController, void> dishOptionsControllerProvider =
    NotifierProvider<DishOptionsController, void>(DishOptionsController.new);
