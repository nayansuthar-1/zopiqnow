import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/providers/bottom_nav_provider.dart';
import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/cart/domain/entities/cart_bill.dart';
import 'package:zopiqnow/features/cart/domain/entities/delivery_surcharge.dart';
import 'package:zopiqnow/features/cart/presentation/providers/cart_providers.dart';
import 'package:zopiqnow/features/checkout/presentation/providers/checkout_providers.dart';
import 'package:zopiqnow/features/cart/presentation/widgets/add_to_cart_control.dart';
import 'package:zopiqnow/features/cart/presentation/widgets/bill_summary.dart';
import 'package:zopiqnow/features/home/domain/entities/restaurant.dart';
import 'package:zopiqnow/features/home/presentation/providers/home_providers.dart';
import 'package:zopiqnow/features/home/presentation/widgets/restaurant_image.dart'
    show GradientImagePlaceholder;

/// The cart page: presents items in cart, order total, bill breakdown, and checkout hand-off.
class CartPage extends ConsumerWidget {
  const CartPage({required this.onBrowse, required this.onCheckout, super.key});

  final VoidCallback onBrowse;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Cart cart = ref.watch(cartProvider);
    // Priced once here and handed down, rather than each half of the screen
    // calling `CartBill.of` again: the surcharge arrives asynchronously, and two
    // independent reads of it are two chances for the bill card and the pay bar
    // to show different totals for a frame.
    final CartBill bill = CartBill.of(
      cart,
      surcharge: ref.watch(deliverySurchargeProvider).value ?? DeliverySurcharge.none,
    );
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    // **A canvas, not a surface.** The page and every card on it were both
    // `colorScheme.surface` — white sections on a white page — so the borders
    // and shadows were the only thing separating them and the screen read as
    // one undivided sheet of white with lines drawn on it. On the grey
    // container the sections separate themselves, which is what lets the
    // shadows come down and the whole thing stop looking like a form.
    final Color canvas = Theme.of(context).colorScheme.surfaceContainer;

    return Scaffold(
      backgroundColor: canvas,
      appBar: AppBar(
        // The cart is a shell *branch root*, so its own Navigator has nothing
        // to pop and `AppBar` draws no leading at all. That was survivable
        // while the shell's pills were on screen underneath; now that the cart
        // hides them to give the checkout bar the bottom of the screen, this
        // arrow is the only way off a non-empty cart.
        leading: BackButton(onPressed: onBrowse),
        title: Text(
          'Your cart',
          style: t.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            fontSize: 20,
            color: isDark ? Colors.white : const Color(0xFF1E1E1E),
          ),
        ),
        centerTitle: false,
        backgroundColor: canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: <Widget>[
          if (cart.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFE53935),
                  backgroundColor: const Color(0xFFE53935).withValues(alpha: 0.08),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                label: const Text(
                  'Clear',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                ),
                onPressed: () => _confirmClear(context, ref),
              ),
            ),
        ],
      ),
      body: NotificationListener<UserScrollNotification>(
        onNotification: (UserScrollNotification notification) {
          if (notification.metrics.axis == Axis.vertical) {
            if (notification.direction == ScrollDirection.reverse && notification.metrics.pixels > 40) {
              if (ref.read(bottomNavVisibilityProvider)) {
                ref.read(bottomNavVisibilityProvider.notifier).state = false;
              }
            } else if (notification.direction == ScrollDirection.forward || notification.metrics.pixels <= 40) {
              if (!ref.read(bottomNavVisibilityProvider)) {
                ref.read(bottomNavVisibilityProvider.notifier).state = true;
              }
            }
          }
          return false;
        },
        child: cart.isEmpty
            ? _EmptyCart(onBrowse: onBrowse)
            : _CartBody(cart: cart, bill: bill),
      ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : _CheckoutBar(
              bill: bill,
              itemCount: cart.itemCount,
              onCheckout: onCheckout,
            ),
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Empty your cart?',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: const Text('Everything in it will be removed.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep it', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Empty cart', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (confirmed ?? false) ref.read(cartProvider.notifier).clear();
  }
}

class _CartBody extends StatelessWidget {
  const _CartBody({required this.cart, required this.bill});

  final Cart cart;
  final CartBill bill;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        ZopiqReveal(child: _RestaurantHeader(cart: cart)),
        const SizedBox(height: 14),
        ZopiqReveal(
          index: 1,
          child: _ItemsCard(cart: cart),
        ),
        const SizedBox(height: 10),
        ZopiqReveal(index: 2, child: _AddMoreItems(cart: cart)),
        const SizedBox(height: 14),
        ZopiqReveal(index: 3, child: BillSummary(bill: bill)),
      ],
    );
  }
}

/// The kitchen's own photo at the top of the cart.
///
/// The cart stores a restaurant's id and its name and nothing else, so this
/// header had no picture to draw and always fell back to the branded gradient
/// tile with a generic storefront glyph — while Home, the top-chains rail and
/// the menu header all showed the real thing. The same order looked like a
/// different restaurant depending on which screen you were on.
///
/// Resolved by id rather than carried in the cart: `restaurantByIdProvider`
/// already exists for the menu screen's cold deep link, it is `autoDispose` and
/// cached, and threading an image URL through the four add-to-cart paths would
/// have been churn in the order flow for one picture. A cart whose restaurant
/// cannot be fetched keeps exactly the placeholder it has today.
class _RestaurantAvatar extends ConsumerWidget {
  const _RestaurantAvatar({required this.restaurantId});

  final String? restaurantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Widget placeholder = GradientImagePlaceholder(
      seed: restaurantId ?? '',
      icon: Icons.storefront_rounded,
      iconSize: 22,
    );

    final String? id = restaurantId;
    if (id == null) return placeholder;

    // Placeholder while it loads and if it fails, so the tile never flashes
    // empty and a dead network is not a broken-looking cart.
    return ref
        .watch(restaurantByIdProvider(id))
        .maybeWhen(
          data: (Restaurant r) =>
              ZopiqNetworkImage(url: r.imageUrl, fallback: placeholder),
          orElse: () => placeholder,
        );
  }
}

/// Restaurant Store Card Header
class _RestaurantHeader extends StatelessWidget {
  const _RestaurantHeader({required this.cart});

  final Cart cart;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final int count = cart.itemCount;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E24) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFE8ECEF),
          width: 1.0,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: zc.primary.withValues(alpha: 0.2),
                  blurRadius: 6,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: _RestaurantAvatar(restaurantId: cart.restaurantId),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  cart.restaurantName ?? 'Your order',
                  style: t.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: isDark ? Colors.white : const Color(0xFF1E1E1E),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: zc.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$count item${count == 1 ? '' : 's'}',
                        style: t.labelSmall?.copyWith(
                          color: zc.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 10.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.verified_user_rounded,
                          size: 12,
                          color: zc.veg,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'Hygienic Packaging',
                          style: t.bodySmall?.copyWith(
                            color: zc.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Add more items" — back to the kitchen the cart belongs to.
///
/// The gap this fills was a real dead end: the only route off a non-empty cart
/// was the app-bar back arrow, which goes to Home rather than to the restaurant
/// being ordered from. So a customer who forgot a drink had to find that kitchen
/// again from the feed, and the one obvious-looking control on the screen was
/// "Clear". Every cart in this category has this row for that reason.
///
/// Pushed, so the menu arrives *over* the cart and system Back returns to it
/// with the order intact — going by branch would have swapped tabs and left the
/// cart behind a tab switch.
///
/// Silent when the cart somehow has no restaurant id. That should not happen —
/// a line cannot be added without one — but a row that navigates nowhere is the
/// thing this whole screen is trying to stop being.
class _AddMoreItems extends StatelessWidget {
  const _AddMoreItems({required this.cart});

  final Cart cart;

  @override
  Widget build(BuildContext context) {
    final String? id = cart.restaurantId;
    if (id == null) return const SizedBox.shrink();

    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isDark ? const Color(0xFF1E1E24) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.pushNamed(
          Routes.menu,
          pathParameters: <String, String>{'id': id},
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : const Color(0xFFE8ECEF),
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.add_rounded, size: 18, color: zc.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Add more items',
                  style: t.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: isDark ? Colors.white : const Color(0xFF1E1E1E),
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: zc.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Container for the list of cart items
class _ItemsCard extends StatelessWidget {
  const _ItemsCard({required this.cart});

  final Cart cart;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E24) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFE8ECEF),
          width: 1.0,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < cart.lines.length; i++) ...<Widget>[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Divider(
                  height: 1,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : const Color(0xFFE2E8F0),
                ),
              ),
            _CartLineTile(
              key: ValueKey<String>(cart.lines[i].lineId),
              line: cart.lines[i],
            ),
          ],
        ],
      ),
    );
  }
}

class _CartLineTile extends ConsumerWidget {
  const _CartLineTile({required this.line, super.key});

  final CartLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CartNotifier cart = ref.read(cartProvider.notifier);
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Dismissible(
      key: ValueKey<String>('dismiss-${line.lineId}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFE53935).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFE53935), size: 22),
      ),
      onDismissed: (_) {
        HapticFeedback.mediumImpact();
        final CartLine removed = line;
        final Cart before = ref.read(cartProvider);
        cart.removeLine(removed.lineId);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              content: Text('${removed.item.name} removed'),
              action: SnackBarAction(
                label: 'Undo',
                textColor: zc.primary,
                onPressed: () => cart.restoreLine(
                  removed,
                  restaurantId: before.restaurantId,
                  restaurantName: before.restaurantName,
                ),
              ),
            ),
          );
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          // Dish Image
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox.square(
              dimension: 52,
              child: ZopiqNetworkImage(
                url: line.item.imageUrl,
                fallback: GradientImagePlaceholder(
                  seed: line.item.id,
                  icon: Icons.restaurant_menu_rounded,
                  iconSize: 20,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Dish details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    ZopiqVegIndicator(isVeg: line.item.isVeg),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        line.item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: isDark ? Colors.white : const Color(0xFF1E1E1E),
                        ),
                      ),
                    ),
                  ],
                ),
                if (line.options.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: zc.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      line.optionsLabel,
                      style: t.bodySmall?.copyWith(
                        color: zc.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 3),
                Text(
                  '₹${line.unitPrice}',
                  style: t.bodySmall?.copyWith(
                    color: zc.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Stepper & Animated Total
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              AddToCartControl(
                quantity: line.quantity,
                onAdd: () => cart.increment(line.lineId),
                onIncrement: () => cart.increment(line.lineId),
                onDecrement: () => cart.decrement(line.lineId),
                // A shade wider than the 72 the menu rows use: this control is
                // always a stepper here (a cart line exists because quantity is
                // at least one), and three elements want a little more room than
                // the word ADD does.
                width: 84,
              ),
              const SizedBox(height: 6),
              ZopiqAnimatedAmount(
                amount: line.lineTotal,
                style: t.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  color: isDark ? Colors.white : const Color(0xFF1E1E1E),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Floating Checkout Bottom Bar
class _CheckoutBar extends StatelessWidget {
  const _CheckoutBar({
    required this.bill,
    required this.itemCount,
    required this.onCheckout,
  });

  final CartBill bill;
  final int itemCount;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Row(
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ZopiqAnimatedAmount(
                  amount: bill.total,
                  style: t.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    color: isDark ? Colors.white : const Color(0xFF1E1E1E),
                  ),
                ),
                Text(
                  'Total · $itemCount item${itemCount == 1 ? '' : 's'}',
                  style: t.labelSmall?.copyWith(
                    color: zc.textMuted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: SizedBox(
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: zc.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: onCheckout,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        'Proceed to checkout',
                        style: t.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart({required this.onBrowse});

  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final List<Map<String, String>> cravings = <Map<String, String>>[
      <String, String>{'emoji': '🍕', 'label': 'Biryani & Bowls'},
      <String, String>{'emoji': '🍔', 'label': 'Burgers & Fries'},
      <String, String>{'emoji': '☕', 'label': 'Coffee & Cafe'},
      <String, String>{'emoji': '🍰', 'label': 'Desserts & Sweets'},
    ];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - 32,
            ),
            child: Align(
              alignment: const Alignment(0, -0.25),
              child: ZopiqReveal(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // Sleek Icon Sphere
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: zc.primary.withValues(alpha: isDark ? 0.15 : 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Icon(
                          Icons.shopping_bag_outlined,
                          size: 40,
                          color: zc.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Title
                    Text(
                      'Your cart is empty',
                      style: t.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        color: isDark ? Colors.white : const Color(0xFF1E1E1E),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),

                    // Subtitle
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Text(
                        'Good food is always cooking. Go ahead, order some.',
                        style: t.bodyMedium?.copyWith(
                          color: isDark ? Colors.white60 : const Color(0xFF64748B),
                          fontSize: 14,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Craving Quick Chips Section
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Column(
                        children: <Widget>[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Icon(Icons.explore_rounded, size: 14, color: zc.primary),
                              const SizedBox(width: 6),
                              Text(
                                'WHAT ARE YOU CRAVING TODAY?',
                                style: t.labelSmall?.copyWith(
                                  color: zc.primary,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 10.5,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: cravings.map((Map<String, String> item) {
                              return InkWell(
                                onTap: onBrowse,
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.08)
                                        : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.1)
                                          : const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      Text(
                                        item['emoji']!,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        item['label']!,
                                        style: t.labelSmall?.copyWith(
                                          color: isDark
                                              ? Colors.white.withValues(alpha: 0.9)
                                              : const Color(0xFF334155),
                                          fontWeight: FontWeight.w700,
                                          fontSize: 11.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Primary CTA Button
                    SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: zc.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 28),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: onBrowse,
                        icon: const Icon(Icons.restaurant_rounded, size: 18),
                        label: Text(
                          'Browse restaurants',
                          style: t.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}



