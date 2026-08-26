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
    final ZopiqColors zc = context.zc;

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
          style: t.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        centerTitle: false,
        backgroundColor: canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: <Widget>[
          if (cart.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: ZopiqSpacing.md),
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  // The destructive colour the design system already owns,
                  // rather than a fourth hardcoded red.
                  foregroundColor: zc.nonVeg,
                  backgroundColor: zc.nonVeg.withValues(alpha: 0.08),
                  shape: const RoundedRectangleBorder(
                    borderRadius: ZopiqRadii.rPill,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: ZopiqSpacing.md,
                    vertical: ZopiqSpacing.xs,
                  ),
                ),
                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                label: Text(
                  'Clear',
                  style: t.labelMedium?.copyWith(fontWeight: FontWeight.w800),
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
        shape: const RoundedRectangleBorder(borderRadius: ZopiqRadii.rLg),
        title: const Text(
          'Empty your cart?',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: const Text('Everything in it will be removed.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              'Keep it',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: dialogContext.zc.nonVeg,
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(
                borderRadius: ZopiqRadii.rSm,
              ),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Empty cart',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
    if (confirmed ?? false) ref.read(cartProvider.notifier).clear();
  }
}

/// **Two surfaces, not four.**
///
/// This screen used to be a stack of four separately-floating cards — the
/// restaurant, the items, "Add more items", and the bill — each with its own
/// border, its own shadow and its own corner radius, on a grey canvas. Four
/// panels of roughly equal weight say nothing about what matters, and the
/// scroll reads as a pile of boxes rather than as an order.
///
/// It is now the order and the bill. The restaurant is the *header* of the
/// items card and "Add more items" is its last row, because all three are one
/// thing: what is being bought and from whom. The bill is the other thing, and
/// it is drawn as a receipt so the difference is visible before it is read.
class _CartBody extends StatelessWidget {
  const _CartBody({required this.cart, required this.bill});

  final Cart cart;
  final CartBill bill;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        ZopiqSpacing.lg,
        ZopiqSpacing.md,
        ZopiqSpacing.lg,
        ZopiqSpacing.xl,
      ),
      children: <Widget>[
        ZopiqReveal(child: _OrderCard(cart: cart)),
        const SizedBox(height: ZopiqSpacing.lg),
        ZopiqReveal(index: 1, child: BillSummary(bill: bill)),
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

/// The order: who is cooking it, what is in it, and the way back for the thing
/// that was forgotten — one card, because those are one subject.
///
/// The three floating panels this replaces are described on [_CartBody]. The
/// rows inside are separated by hairlines rather than by gaps between cards, so
/// the eye reads a list instead of counting boxes.
class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.cart});

  final Cart cart;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Theme.of(context).colorScheme.surfaceContainerHigh
            : Colors.white,
        borderRadius: ZopiqRadii.rXl,
        border: Border.all(color: zc.divider),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      // Clipped so the header row's ink splash stops at the corner instead of
      // painting a square over it.
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          _KitchenRow(cart: cart),
          _HairLine(color: zc.divider),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ZopiqSpacing.lg,
              vertical: ZopiqSpacing.xs,
            ),
            child: Column(
              children: <Widget>[
                for (int i = 0; i < cart.lines.length; i++) ...<Widget>[
                  if (i > 0) _HairLine(color: zc.divider),
                  _CartLineTile(
                    key: ValueKey<String>(cart.lines[i].lineId),
                    line: cart.lines[i],
                  ),
                ],
              ],
            ),
          ),
          // Both or neither: a rule drawn above a row that renders nothing
          // would be a line resting on the bottom edge of the card.
          if (cart.restaurantId != null) ...<Widget>[
            _HairLine(color: zc.divider),
            _AddMoreRow(restaurantId: cart.restaurantId!),
          ],
        ],
      ),
    );
  }
}

/// A full-bleed hairline between rows of the order card.
class _HairLine extends StatelessWidget {
  const _HairLine({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Divider(height: 1, color: color);
}

/// Which kitchen this order is with, and a way back to its menu.
///
/// The whole row is the tap target, not a separate button: the customer who
/// wants the restaurant wants the restaurant, and a chevron on a card people
/// already read as a heading is the shape every app in this category uses.
class _KitchenRow extends StatelessWidget {
  const _KitchenRow({required this.cart});

  final Cart cart;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final String? id = cart.restaurantId;
    final int count = cart.itemCount;

    return InkWell(
      // Silent when the cart somehow has no restaurant id. That should not
      // happen — a line cannot be added without one — but a row that navigates
      // nowhere is the thing this whole screen is trying to stop being.
      onTap: id == null
          ? null
          : () => context.pushNamed(
              Routes.menu,
              pathParameters: <String, String>{'id': id},
            ),
      child: Padding(
        padding: const EdgeInsets.all(ZopiqSpacing.lg),
        child: Row(
          children: <Widget>[
            ClipRRect(
              borderRadius: ZopiqRadii.rMd,
              child: SizedBox.square(
                dimension: 44,
                child: _RestaurantAvatar(restaurantId: id),
              ),
            ),
            const SizedBox(width: ZopiqSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    cart.restaurantName ?? 'Your order',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: ZopiqSpacing.xxs),
                  Text(
                    '$count item${count == 1 ? '' : 's'} in this order',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall?.copyWith(color: zc.textMuted),
                  ),
                ],
              ),
            ),
            if (id != null)
              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: zc.textMuted,
              ),
          ],
        ),
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
class _AddMoreRow extends StatelessWidget {
  const _AddMoreRow({required this.restaurantId});

  final String restaurantId;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return InkWell(
      onTap: () => context.pushNamed(
        Routes.menu,
        pathParameters: <String, String>{'id': restaurantId},
      ),
      child: Padding(
        padding: const EdgeInsets.all(ZopiqSpacing.lg),
        child: Row(
          children: <Widget>[
            Icon(Icons.add_rounded, size: 20, color: zc.primary),
            const SizedBox(width: ZopiqSpacing.md),
            Expanded(
              child: Text(
                'Add more items',
                style: t.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: zc.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line of the order: the dish, what it costs, and the stepper that changes
/// how much of it there is. Swipe left to remove, with an undo.
class _CartLineTile extends ConsumerWidget {
  const _CartLineTile({required this.line, super.key});

  final CartLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CartNotifier cart = ref.read(cartProvider.notifier);
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Dismissible(
      key: ValueKey<String>('dismiss-${line.lineId}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: ZopiqSpacing.lg),
        decoration: BoxDecoration(
          color: zc.nonVeg.withValues(alpha: 0.12),
          borderRadius: ZopiqRadii.rMd,
        ),
        child: Icon(
          Icons.delete_outline_rounded,
          color: zc.nonVeg,
          size: 22,
        ),
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
              shape: const RoundedRectangleBorder(
                borderRadius: ZopiqRadii.rMd,
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.md),
        child: Row(
          children: <Widget>[
            ClipRRect(
              borderRadius: ZopiqRadii.rMd,
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
            const SizedBox(width: ZopiqSpacing.md),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      ZopiqVegIndicator(isVeg: line.item.isVeg),
                      const SizedBox(width: ZopiqSpacing.sm),
                      Expanded(
                        child: Text(
                          line.item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (line.options.isNotEmpty) ...<Widget>[
                    const SizedBox(height: ZopiqSpacing.xxs),
                    Text(
                      line.optionsLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall?.copyWith(color: zc.textMuted),
                    ),
                  ],
                  const SizedBox(height: ZopiqSpacing.xxs),
                  Text(
                    '₹${line.unitPrice}',
                    style: t.bodySmall?.copyWith(
                      color: zc.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: ZopiqSpacing.sm),

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
                const SizedBox(height: ZopiqSpacing.sm),
                ZopiqAnimatedAmount(
                  amount: line.lineTotal,
                  style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The total and the way out of the cart, docked at the bottom.
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
        minimum: const EdgeInsets.fromLTRB(
          ZopiqSpacing.lg,
          ZopiqSpacing.md,
          ZopiqSpacing.lg,
          ZopiqSpacing.lg,
        ),
        child: Row(
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ZopiqAnimatedAmount(
                  amount: bill.total,
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                Text(
                  'Total · $itemCount item${itemCount == 1 ? '' : 's'}',
                  style: t.labelSmall?.copyWith(
                    color: zc.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(width: ZopiqSpacing.lg),
            Expanded(
              child: SizedBox(
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: zc.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: const RoundedRectangleBorder(
                      borderRadius: ZopiqRadii.rMd,
                    ),
                  ),
                  onPressed: onCheckout,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          'Proceed to checkout',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: ZopiqSpacing.sm),
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



