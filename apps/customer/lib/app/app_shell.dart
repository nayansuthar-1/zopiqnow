import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/providers/bottom_nav_provider.dart';
import 'package:zopiqnow/features/cart/presentation/providers/cart_providers.dart';

/// The persistent bottom-navigation shell.
///
/// Backed by `StatefulShellRoute.indexedStack`, so each tab keeps its own
/// navigation stack *and* its scroll position: leaving Home half-scrolled and
/// coming back lands exactly where you left.
///
/// Only the tabs that exist are here. Account arrives with the feature behind it
/// (DEVELOPMENT_PLAN step 5) as one more [StatefulShellBranch]. A tab that
/// navigates to nothing reads as broken.
class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  /// The Cart branch's index. It sits after the four left-pill tabs
  /// (Delivery, Dining, Grocery, Gifts), and is reached from the separate Cart
  /// pill rather than the pill row.
  static const int cartBranchIndex = 4;

  @override
  Widget build(BuildContext context) {
    // The cart carries its own bottom bar — the total and "Proceed to
    // checkout" — so the pills are not drawn over it, and (because
    // `extendBody` hands their height to the body as padding) do not reserve
    // space under it either. That reserved band was the ~115pt of empty screen
    // below the checkout button whenever the pills happened to be in their
    // hidden state, which is how they arrive here from a scrolled Home.
    final bool onCart = navigationShell.currentIndex == cartBranchIndex;

    return Scaffold(
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: onCart
          ? null
          : _ShellNavBar(navigationShell: navigationShell),
    );
  }
}

class _ShellNavBar extends ConsumerWidget {
  const _ShellNavBar({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  /// The height of both pills. Named because the hide animation measures itself
  /// against it: [AnimatedSlide]'s offset is a multiple of the child's own size,
  /// not a distance in pixels.
  static const double _pillHeight = 57.0;

  /// The gap under the pills when the bar is showing.
  ///
  /// Android draws its system bar outside the Flutter view, so `padding.bottom`
  /// is 0 there and this is the whole margin — the value the design was tuned
  /// against. iOS always reserves 34 for the home indicator, and a `SafeArea`
  /// *plus* that margin used to stack into a 57pt gap that left the bar
  /// stranded mid-screen with cards showing underneath it. Taking the larger of
  /// the two keeps Android exactly as it was and clears the home indicator by a
  /// deliberate 8 rather than by accident.
  static double _bottomGap(double systemInset) =>
      systemInset + 8.0 > 23.0 ? systemInset + 8.0 : 23.0;

  void _onTap(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int itemCount = ref.watch(cartProvider.select((c) => c.itemCount));
    final bool isVisible = ref.watch(bottomNavVisibilityProvider);
    final ZopiqColors zc = context.zc;

    final int currentIndex = navigationShell.currentIndex;
    // The four pill tabs are indices 0–3; Cart is the one after them. When Cart
    // is the selected branch, the sliding indicator has no pill to sit under, so
    // it falls back to the first tab rather than sliding off the row.
    final int leftIndex =
        currentIndex < AppShell.cartBranchIndex ? currentIndex : 0;

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color glowColor = isDark ? Colors.black : Colors.white;

    final double bottomGap = _bottomGap(MediaQuery.paddingOf(context).bottom);
    // Far enough to clear the pill, the gap beneath it, and the shadow's blur,
    // which reaches past the pill's own box and would otherwise leave a soft
    // grey line resting on the bottom edge. The old constant 1.5 was 85pt
    // against the 114 it had to travel, which is why the bar stopped half-drawn
    // along the bottom of the screen instead of leaving it.
    final Offset hidden = Offset(
      0,
      (_pillHeight + bottomGap + 12.0) / _pillHeight,
    );

    return Stack(
      children: [
        // Glow Background sliding down
        Positioned(
          bottom: 0, left: 0, right: 0,
          height: 32.0, // Reduced glow height to match new bottom gap
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeInOutCubic,
            offset: isVisible ? Offset.zero : const Offset(0, 1.5),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    glowColor,
                    glowColor.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Foreground Pills
        SafeArea(
          // The bottom inset is spent by `bottomGap` instead, so that the pill
          // clears the home indicator once rather than twice. Horizontal insets
          // still apply, for a notch in landscape.
          top: false,
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              ZopiqSpacing.md,
              16.0,
              0, // No right padding, stick to edge
              bottomGap,
            ),
            child: Row(
              children: [
                Expanded(
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeInOutCubic,
                    offset: isVisible ? Offset.zero : hidden, // Slide clear of the bottom edge
                    child: Container(
                      height: _pillHeight,
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark 
                            ? Colors.black 
                            : Colors.white,
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x1A000000),
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final double tabWidth = constraints.maxWidth / 4;
                          return Stack(
                            children: [
                              // Sliding indicator
                              AnimatedPositioned(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeInOutCubic,
                                left: leftIndex * tabWidth,
                                top: 4,
                                bottom: 4,
                                width: tabWidth,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: zc.primaryDeep.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(28),
                                  ),
                                ),
                              ),
                              Row(
                                children: [
                                  _buildNavItem(
                                    context: context,
                                    index: 0,
                                    title: 'Delivery',
                                    icon: Icons.delivery_dining_outlined,
                                    activeIcon: Icons.delivery_dining,
                                    width: tabWidth,
                                    isSelected: currentIndex == 0,
                                    zc: zc,
                                  ),
                                  _buildNavItem(
                                    context: context,
                                    index: 1,
                                    title: 'Dining',
                                    icon: Icons.restaurant_outlined,
                                    activeIcon: Icons.restaurant,
                                    width: tabWidth,
                                    isSelected: currentIndex == 1,
                                    zc: zc,
                                  ),
                                  _buildNavItem(
                                    context: context,
                                    index: 2,
                                    title: 'Grocery',
                                    icon: Icons.local_grocery_store_outlined,
                                    activeIcon: Icons.local_grocery_store,
                                    width: tabWidth,
                                    isSelected: currentIndex == 2,
                                    zc: zc,
                                  ),
                                  _buildNavItem(
                                    context: context,
                                    index: 3,
                                    title: 'Gifts',
                                    icon: Icons.card_giftcard_outlined,
                                    activeIcon: Icons.card_giftcard,
                                    width: tabWidth,
                                    isSelected: currentIndex == 3,
                                    zc: zc,
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: ZopiqSpacing.sm),
                // Cart Pill
                AnimatedSlide(
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeInOutCubic,
                  offset: isVisible ? Offset.zero : const Offset(1.5, 0), // Slide right
                  child: GestureDetector(
                    onTap: () => _onTap(AppShell.cartBranchIndex),
                    child: Container(
                      height: _pillHeight,
                      padding: const EdgeInsets.symmetric(horizontal: ZopiqSpacing.lg),
                      decoration: BoxDecoration(
                        color: zc.primaryDeep,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(32),
                          bottomLeft: Radius.circular(32),
                        ),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x1A000000),
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (itemCount > 0) ...[
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '$itemCount',
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: zc.primaryDeep,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: ZopiqSpacing.sm),
                          ],
                          Text(
                            'Cart',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: ZopiqSpacing.xs),
                          const Icon(
                            Icons.shopping_cart_outlined,
                            color: Colors.white,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required int index,
    required String title,
    required IconData icon,
    required IconData activeIcon,
    required double width,
    required bool isSelected,
    required ZopiqColors zc,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _onTap(index),
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              color: isSelected ? zc.primaryDeep : zc.textMuted,
              size: 24,
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: isSelected ? zc.primaryDeep : zc.textMuted,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
