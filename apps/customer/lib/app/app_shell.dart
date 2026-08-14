import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/providers/bottom_nav_provider.dart';
import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/features/cart/presentation/providers/cart_providers.dart';
import 'package:zopiqnow/features/home/presentation/providers/home_providers.dart';
import 'package:zopiqnow/features/checkout/domain/entities/customer_order.dart';
import 'package:zopiqnow/features/checkout/presentation/providers/orders_providers.dart';
import 'package:zopiqnow/features/location/presentation/pages/location_gate_page.dart';
import 'package:zopiqnow/features/location/presentation/widgets/location_off_sheet.dart';
import 'package:zopiqnow/features/location/presentation/widgets/location_prompt.dart';

/// The persistent bottom-navigation shell.
///
/// Backed by `StatefulShellRoute.indexedStack`, so each tab keeps its own
/// navigation stack *and* its scroll position: leaving Home half-scrolled and
/// coming back lands exactly where you left.
///
/// Only the tabs that exist are here. Account arrives with the feature behind it
/// (DEVELOPMENT_PLAN step 5) as one more [StatefulShellBranch]. A tab that
/// navigates to nothing reads as broken.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  /// The Cart branch's index. It sits after the left-pill tabs (Delivery,
  /// Gifts, Collection), and is reached from the separate Cart pill rather than
  /// the pill row.
  ///
  /// Was 4 while Dining and Grocery held branches 1 and 2 — both were
  /// `ComingSoonPage` and both are gone. Then 2, until Collection took that
  /// index. This constant, [_ShellNavBar._tabs] and the branch list in
  /// `router.dart` are the three places that have to agree; adding or removing a
  /// tab means editing all three.
  static const int cartBranchIndex = 3;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  StatefulNavigationShell get navigationShell => widget.navigationShell;

  @override
  void initState() {
    super.initState();
    // After the first frame: this runs while the shell is being built, and a
    // modal route pushed from inside a build is a crash.
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerLocation());
  }

  /// The location sheet, once per launch, when there is no location to be had.
  ///
  /// Skipped when the startup gate already ran this session
  /// ([locationGateProvider]). The gate only appears when no address is
  /// selected, and it asks the same question with the same buttons — following
  /// it with this sheet would be the app asking twice in a row and accepting
  /// "no" neither time. What is left is exactly the case in the design: somebody
  /// with a saved address who never granted the permission.
  Future<void> _offerLocation() async {
    if (!mounted) return;
    if (ref.read(locationSheetShownProvider)) return;
    if (ref.read(locationGateProvider)) return;

    if (!await isLocationOff(ref)) return;
    if (!mounted) return;

    ref.read(locationSheetShownProvider.notifier).state = true;
    await showLocationOffSheet(context, ref);
  }

  /// System Back, on the tab that is showing.
  ///
  /// Three steps before the app closes, each of which undoes the last thing the
  /// user did rather than the whole session:
  ///
  ///   1. Not on Delivery → go to Delivery. A tab switch is navigation, and Back
  ///      should undo it. Leaving from Gifts used to close the app outright.
  ///   2. On Delivery, scrolled → return the feed to the top.
  ///   3. At the top of Delivery → leave.
  ///
  /// This also settles *whether Flutter hears Back at all*. `PopScope` with
  /// `canPop: false` makes the framework tell the engine it handles Back, which
  /// registers the `OnBackInvokedCallback` the manifest opted into. Without a
  /// declared interest, a shell route with nothing above it to pop lets Android
  /// finish the activity — which is the app closing from the one screen that
  /// should be hardest to leave by accident.
  void _onBack() {
    if (navigationShell.currentIndex != 0) {
      navigationShell.goBranch(0);
      return;
    }

    final ScrollController scroll = ref.read(homeScrollControllerProvider);
    if (scroll.hasClients && scroll.offset > 0) {
      scroll.animateTo(
        0,
        duration: ZopiqDurations.slow,
        curve: ZopiqCurves.emphasized,
      );
      return;
    }

    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    // The cart carries its own bottom bar — the total and "Proceed to
    // checkout" — so the pills are not drawn over it, and (because
    // `extendBody` hands their height to the body as padding) do not reserve
    // space under it either. That reserved band was the ~115pt of empty screen
    // below the checkout button whenever the pills happened to be in their
    // hidden state, which is how they arrive here from a scrolled Home.
    final bool onCart =
        navigationShell.currentIndex == AppShell.cartBranchIndex;

    return PopScope(
      // Never pops on its own — there is nothing under the shell to pop *to*,
      // so a real pop is the app closing. `_onBack` decides when that is what
      // was meant.
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        _onBack();
      },
      child: Scaffold(
        extendBody: true,
        body: navigationShell,
        bottomNavigationBar: onCart
            ? null
            : _ShellNavBar(navigationShell: navigationShell),
      ),
    );
  }
}

/// One tab of the left pill: what it is called, how it is drawn, and the colour
/// it takes when it is the one showing.
class _NavTab {
  const _NavTab({
    required this.title,
    required this.icon,
    required this.activeIcon,
    required this.colour,
  });

  final String title;
  final IconData icon;

  /// The filled twin of [icon]. The swap is most of what says "selected" now
  /// that nothing is painted behind it.
  final IconData activeIcon;

  /// Selected colour. Unselected is always the muted text colour, so an
  /// unselected row reads as one row rather than as three competing ones.
  final Color colour;
}

class _ShellNavBar extends ConsumerWidget {
  const _ShellNavBar({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  /// The height of both pills. Named because the hide animation measures itself
  /// against it: [AnimatedSlide]'s offset is a multiple of the child's own size,
  /// not a distance in pixels.
  static const double _pillHeight = 57.0;

  /// The tabs sharing the left pill, in branch order.
  ///
  /// **Each carries its own selected colour**, which is the point: a storefront
  /// tab, a gift shop and a saved list are three different errands, and the app
  /// says so with colour rather than by moving one orange block around. The old
  /// bar painted a brand-tinted rounded rectangle behind whichever tab was
  /// selected — a filled slab under a 57pt pill, which crowded the icon it was
  /// meant to be highlighting and made every tab look like Delivery. Now nothing
  /// is filled: the icon and its label take the colour and the background stays
  /// the pill's own.
  ///
  /// The list is the single source of the tab count, so adding a tab here and a
  /// branch in `router.dart` is the whole change — there is no separate `4`
  /// waiting to disagree with it.
  static const List<_NavTab> _tabs = <_NavTab>[
    _NavTab(
      title: 'Delivery',
      icon: Icons.delivery_dining_outlined,
      activeIcon: Icons.delivery_dining,
      colour: Color(0xFFFC8019),
    ),
    _NavTab(
      title: 'Gifts',
      icon: Icons.card_giftcard_outlined,
      activeIcon: Icons.card_giftcard,
      colour: Color(0xFF0C831F),
    ),
    _NavTab(
      title: 'Collection',
      icon: Icons.favorite_border_rounded,
      activeIcon: Icons.favorite_rounded,
      colour: Color(0xFFE8467C),
    ),
  ];

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

  void _onTap(WidgetRef ref, int index) {
    if (!ref.read(bottomNavVisibilityProvider)) {
      ref.read(bottomNavVisibilityProvider.notifier).state = true;
    }
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

    // An empty cart with an order already on its way: the pill has nothing to
    // offer as a cart and exactly one thing to offer as a shortcut. Both
    // conditions matter — a cart with items in it is a thing the customer is
    // part-way through, and burying it under a shortcut to something else would
    // lose work they have done.
    final CustomerOrder? liveOrder = itemCount == 0
        ? ref.watch(liveOrderProvider)
        : null;

    // The pill tabs are indices 0–2; Cart is the one after them, and while it is
    // the live branch no tab reads as selected — which is correct, because the
    // Cart pill beside them is the thing that is showing. The old fallback index
    // existed only to park the sliding indicator somewhere, and the indicator is
    // gone.
    final int currentIndex = navigationShell.currentIndex;

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
                          final double tabWidth =
                              constraints.maxWidth / _tabs.length;
                          // No Stack and no indicator any more — the row is the
                          // whole bar. `leftIndex` still decides which tab reads
                          // as selected while Cart is the live branch.
                          return Row(
                            children: <Widget>[
                              for (int i = 0; i < _tabs.length; i++)
                                _buildNavItem(
                                  context: context,
                                  ref: ref,
                                  index: i,
                                  tab: _tabs[i],
                                  width: tabWidth,
                                  isSelected: currentIndex == i,
                                  zc: zc,
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
                    // Pushed, not a branch switch: the order lives on the
                    // Orders stack rather than in a tab of its own, and a
                    // shortcut that swapped branches would strand the customer
                    // in a tab they never chose when they hit back.
                    onTap: liveOrder == null
                        ? () => _onTap(ref, AppShell.cartBranchIndex)
                        : () => context.pushNamed(
                            Routes.orderDetail,
                            pathParameters: <String, String>{
                              'id': liveOrder.id,
                            },
                          ),
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
                            liveOrder == null ? 'Cart' : 'My Order',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: ZopiqSpacing.xs),
                          Icon(
                            liveOrder == null
                                ? Icons.shopping_cart_outlined
                                : Icons.receipt_long_outlined,
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
    required WidgetRef ref,
    required int index,
    required _NavTab tab,
    required double width,
    required bool isSelected,
    required ZopiqColors zc,
  }) {
    // The tab's own colour when selected, the shared muted one when not. Nothing
    // is drawn behind either state.
    final Color colour = isSelected ? tab.colour : zc.textMuted;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _onTap(ref, index),
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            // The colour crossfades rather than snapping, which is the only
            // animation left in the row now that the sliding block is gone. 180ms
            // is short enough to feel like a tap response instead of a transition.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Icon(
                isSelected ? tab.activeIcon : tab.icon,
                // Keyed so the switcher sees the filled and outlined icons as
                // different children; without it the swap is silent and the
                // crossfade never runs.
                key: ValueKey<bool>(isSelected),
                color: colour,
                size: 24,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              tab.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colour,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
