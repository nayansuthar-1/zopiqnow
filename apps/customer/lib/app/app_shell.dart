import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/cart/presentation/providers/cart_providers.dart';

/// The persistent bottom-navigation shell.
///
/// Backed by `StatefulShellRoute.indexedStack`, so each tab keeps its own
/// navigation stack *and* its scroll position: leaving Home half-scrolled and
/// coming back lands exactly where you left.
///
/// Only the tabs that exist are here. Search and Account arrive with the
/// features behind them (DEVELOPMENT_PLAN steps 4 and 5) — each is one more
/// [StatefulShellBranch]. A tab that navigates to nothing reads as broken.
class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: _ShellNavBar(navigationShell: navigationShell),
    );
  }
}

class _ShellNavBar extends ConsumerWidget {
  const _ShellNavBar({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _onTap(int index) {
    // `initialLocation: true` when re-tapping the active tab pops it back to
    // its root — the standard "tap Home again to go home" affordance.
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int itemCount = ref.watch(cartProvider.select((c) => c.itemCount));
    final ZopiqColors zc = context.zc;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: zc.divider)),
      ),
      child: BottomNavigationBar(
        currentIndex: navigationShell.currentIndex,
        onTap: _onTap,
        items: <BottomNavigationBarItem>[
          const BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: _CartIcon(count: itemCount, icon: Icons.shopping_bag_outlined),
            activeIcon: _CartIcon(count: itemCount, icon: Icons.shopping_bag_rounded),
            label: 'Cart',
          ),
        ],
      ),
    );
  }
}

/// Cart glyph with a live item-count badge.
class _CartIcon extends StatelessWidget {
  const _CartIcon({required this.count, required this.icon});

  final int count;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return Icon(icon);

    return Badge.count(
      count: count,
      backgroundColor: context.zc.primaryDeep,
      child: Icon(icon),
    );
  }
}
