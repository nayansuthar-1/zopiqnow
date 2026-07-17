import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiq_vendor/features/auth/domain/entities/vendor.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_vendor/features/menu/data/vendor_menu_datasource.dart';
import 'package:zopiq_vendor/features/menu/domain/entities/vendor_dish.dart';

/// Data source binding. Overridden in tests, which have no Supabase instance.
final Provider<VendorMenuDataSource> vendorMenuDataSourceProvider =
    Provider<VendorMenuDataSource>(
      (Ref ref) => const VendorMenuSupabaseDataSource(),
    );

/// The signed-in restaurant's whole menu, grouped into sections.
///
/// A one-shot read, not a stream: unlike the order queue, nobody else changes a
/// restaurant's menu while its own kitchen is looking at it, so there is nothing
/// to subscribe to. It is re-fetched by [MenuController] after a dish is added,
/// edited or removed, and by pull-to-refresh.
final FutureProvider<List<VendorMenuSection>> menuProvider =
    FutureProvider<List<VendorMenuSection>>((Ref ref) {
      final Vendor? vendor = ref.watch(vendorProvider);
      if (vendor == null) {
        return Future<List<VendorMenuSection>>.value(
          const <VendorMenuSection>[],
        );
      }
      return ref
          .watch(vendorMenuDataSourceProvider)
          .fetchMenu(vendor.restaurantId);
    });

/// Every write the menu screen makes. Each method returns null on success, or a
/// sentence to show the vendor on failure — the same shape the order queue's
/// controller uses, and for the same reason: the caller decides where the words
/// go, the controller only decides what they are.
class MenuController extends Notifier<void> {
  @override
  void build() {}

  VendorMenuDataSource get _ds => ref.read(vendorMenuDataSourceProvider);

  /// Flip a dish on or off. Does *not* refresh the list: the caller flips its
  /// own switch first and this confirms it, so a re-fetch would only repaint the
  /// screen to the value it already shows. A failure comes back as a message,
  /// and the caller puts the switch back.
  Future<String?> setAvailability({
    required String dishId,
    required bool isAvailable,
  }) async {
    try {
      await _ds.setAvailability(dishId: dishId, isAvailable: isAvailable);
      return null;
    } on MenuWriteFailure catch (e) {
      return e.message;
    } on Object {
      return 'We couldn\'t update that dish. Please try again.';
    }
  }

  /// Add a new dish or save edits to one. Refreshes the list, because a new dish
  /// has to appear and an edited one may have moved sections.
  Future<String?> save(VendorDish dish) async {
    final String? restaurantId = ref.read(vendorProvider)?.restaurantId;
    if (restaurantId == null) return 'You\'re signed out.';
    try {
      await _ds.saveDish(dish, restaurantId: restaurantId);
      ref.invalidate(menuProvider);
      return null;
    } on MenuWriteFailure catch (e) {
      return e.message;
    } on Object {
      return 'We couldn\'t save that dish. Please try again.';
    }
  }

  /// Remove a dish. A dish on a past order cannot be erased — the receipt has to
  /// survive it — so that refusal comes back as its own sentence pointing the
  /// vendor at the availability switch instead.
  Future<String?> delete(String dishId) async {
    try {
      await _ds.deleteDish(dishId);
      ref.invalidate(menuProvider);
      return null;
    } on MenuItemInUseFailure {
      return 'This dish is on past orders, so it can\'t be deleted. '
          'Mark it unavailable to take it off the menu.';
    } on MenuWriteFailure catch (e) {
      return e.message;
    } on Object {
      return 'We couldn\'t remove that dish. Please try again.';
    }
  }

  /// Set the new section order. Refreshes, because the whole list re-sorts.
  Future<String?> reorderCategories(List<String> orderedTitles) async {
    final String? restaurantId = ref.read(vendorProvider)?.restaurantId;
    if (restaurantId == null) return 'You\'re signed out.';
    try {
      await _ds.reorderCategories(
        restaurantId: restaurantId,
        orderedTitles: orderedTitles,
      );
      ref.invalidate(menuProvider);
      return null;
    } on MenuWriteFailure catch (e) {
      return e.message;
    } on Object {
      return 'We couldn\'t save the new order. Please try again.';
    }
  }

  /// Rename a section across every dish in it. Refreshes, because the header —
  /// and, if it moved, the dish's position — changes.
  Future<String?> renameCategory({
    required String from,
    required String to,
  }) async {
    final String? restaurantId = ref.read(vendorProvider)?.restaurantId;
    if (restaurantId == null) return 'You\'re signed out.';
    try {
      await _ds.renameCategory(restaurantId: restaurantId, from: from, to: to);
      ref.invalidate(menuProvider);
      return null;
    } on MenuWriteFailure catch (e) {
      return e.message;
    } on Object {
      return 'We couldn\'t rename that section. Please try again.';
    }
  }

  /// Turn a whole section on or off. Refreshes so the section's new state shows.
  Future<String?> setCategoryAvailability({
    required String category,
    required bool isAvailable,
  }) async {
    final String? restaurantId = ref.read(vendorProvider)?.restaurantId;
    if (restaurantId == null) return 'You\'re signed out.';
    try {
      await _ds.setCategoryAvailability(
        restaurantId: restaurantId,
        category: category,
        isAvailable: isAvailable,
      );
      ref.invalidate(menuProvider);
      return null;
    } on MenuWriteFailure catch (e) {
      return e.message;
    } on Object {
      return 'We couldn\'t update that section. Please try again.';
    }
  }
}

final NotifierProvider<MenuController, void> menuControllerProvider =
    NotifierProvider<MenuController, void>(MenuController.new);
