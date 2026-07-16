import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/features/orders/presentation/providers/orders_providers.dart';

/// The partner app's four rooms, held in a bottom-nav shell.
///
/// A plain [NavigationBar], not the customer app's pill nav: this is a worklist
/// on a kitchen tablet, and the standard control is the one nobody has to learn.
/// Backed by `StatefulShellRoute.indexedStack`, so each tab keeps its own scroll
/// position — a menu scrolled halfway stays there when the kitchen ducks to the
/// queue and back.
class VendorShell extends ConsumerWidget {
  const VendorShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    // The badge on Orders: the count that makes someone look up.
    final int newCount = ref.watch(newOrderCountProvider);

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (int index) => navigationShell.goBranch(
          index,
          // Tapping the current tab again returns it to its root, the standard
          // bottom-nav gesture.
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: <Widget>[
          NavigationDestination(
            icon: Badge(
              label: newCount == 0 ? null : Text('$newCount'),
              isLabelVisible: newCount > 0,
              backgroundColor: zc.primary,
              child: const Icon(Icons.receipt_long_outlined),
            ),
            selectedIcon: Badge(
              label: newCount == 0 ? null : Text('$newCount'),
              isLabelVisible: newCount > 0,
              backgroundColor: zc.primary,
              child: const Icon(Icons.receipt_long),
            ),
            label: 'Orders',
          ),
          const NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
          const NavigationDestination(
            icon: Icon(Icons.restaurant_menu_outlined),
            selectedIcon: Icon(Icons.restaurant_menu),
            label: 'Menu',
          ),
          const NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
