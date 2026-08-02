import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/core/widgets/vendor_svg_icons.dart';
import 'package:zopiq_vendor/features/orders/presentation/providers/new_order_alarm.dart';
import 'package:zopiq_vendor/features/orders/presentation/providers/orders_providers.dart';

/// The partner app's main rooms held in a modern vector navigation shell.
class VendorShell extends ConsumerWidget {
  const VendorShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final Color surfaceColor = Theme.of(context).colorScheme.surface;
    final int newCount = ref.watch(newOrderCountProvider);
    ref.watch(newOrderAlarmProvider.notifier);

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: surfaceColor,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: zc.textStrong.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          elevation: 0,
          backgroundColor: Colors.transparent,
          indicatorColor: zc.primary.withValues(alpha: 0.14),
          onDestinationSelected: (int index) => navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          ),
          destinations: <Widget>[
            NavigationDestination(
              icon: VendorSvgIcon(
                type: VendorSvgType.storefront,
                color: zc.textMuted,
              ),
              selectedIcon: VendorSvgIcon(
                type: VendorSvgType.storefront,
                color: zc.primary,
              ),
              label: 'Home',
            ),
            NavigationDestination(
              icon: newCount == 0
                  ? VendorSvgIcon(
                      type: VendorSvgType.liveOrders,
                      color: zc.textMuted,
                    )
                  : Badge(
                      label: Text('$newCount'),
                      backgroundColor: zc.primary,
                      child: VendorSvgIcon(
                        type: VendorSvgType.liveOrders,
                        color: zc.primary,
                      ),
                    ),
              selectedIcon: VendorSvgIcon(
                type: VendorSvgType.liveOrders,
                color: zc.primary,
              ),
              label: 'Orders',
            ),
            NavigationDestination(
              icon: VendorSvgIcon(
                type: VendorSvgType.chefMenu,
                color: zc.textMuted,
              ),
              selectedIcon: VendorSvgIcon(
                type: VendorSvgType.chefMenu,
                color: zc.primary,
              ),
              label: 'Menu',
            ),
            NavigationDestination(
              icon: VendorSvgIcon(
                type: VendorSvgType.historyClock,
                color: zc.textMuted,
              ),
              selectedIcon: VendorSvgIcon(
                type: VendorSvgType.historyClock,
                color: zc.primary,
              ),
              label: 'History',
            ),
            NavigationDestination(
              icon: VendorSvgIcon(
                type: VendorSvgType.moreGrid,
                color: zc.textMuted,
              ),
              selectedIcon: VendorSvgIcon(
                type: VendorSvgType.moreGrid,
                color: zc.primary,
              ),
              label: 'More',
            ),
          ],
        ),
      ),
    );
  }
}
