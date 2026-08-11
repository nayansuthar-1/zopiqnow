import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/app/router.dart';
import 'package:zopiqnow/core/dialler.dart';
import 'package:zopiqnow/features/cart/domain/entities/cart.dart';
import 'package:zopiqnow/features/cart/presentation/providers/cart_providers.dart';
import 'package:zopiqnow/features/checkout/domain/entities/customer_order.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_issue.dart';
import 'package:zopiqnow/features/checkout/domain/entities/payment_method.dart';
import 'package:zopiqnow/features/checkout/presentation/providers/checkout_providers.dart';
import 'package:zopiqnow/features/checkout/presentation/providers/orders_providers.dart';
import 'package:zopiqnow/features/checkout/presentation/widgets/cancel_order_sheet.dart';
import 'package:zopiqnow/features/checkout/presentation/widgets/order_card.dart';
import 'package:zopiqnow/features/checkout/presentation/widgets/order_issue_section.dart';
import 'package:zopiqnow/features/checkout/presentation/widgets/order_refund_section.dart';
import 'package:zopiqnow/features/checkout/presentation/widgets/order_review_section.dart';
import 'package:zopiqnow/features/checkout/presentation/widgets/order_tracking_card.dart';
import 'package:zopiqnow/features/checkout/presentation/widgets/report_issue_sheet.dart';
import 'package:zopiqnow/features/home/presentation/widgets/restaurant_image.dart'
    show GradientImagePlaceholder;

/// One order in full: clean Zomato/Swiggy flat receipt layout (zero cards, flat dividers).
class OrderDetailPage extends ConsumerWidget {
  const OrderDetailPage({required this.orderId, super.key});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<CustomerOrder?> order = ref.watch(
      orderByIdProvider(orderId),
    );

    return order.when(
      // An app bar even here: both the other two branches have one, and a
      // tracking screen that never finishes loading is otherwise a screen with
      // no back button on a platform with no system Back.
      loading: () => Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.surface,
          elevation: 0,
        ),
        body: const Center(child: ZopiqLoader()),
      ),
      error: (Object _, StackTrace _) => _OrderMessage(
        title: 'We couldn\'t load this order',
        body: 'Check your connection and try again.',
        actionLabel: 'Retry',
        onAction: () => ref.invalidate(orderByIdProvider(orderId)),
      ),
      data: (CustomerOrder? data) => data == null
          ? _OrderMessage(
              title: 'Order not found',
              body: 'It may belong to another account.',
              actionLabel: 'Your orders',
              onAction: () => context.goNamed(Routes.orders),
            )
          : _OrderBody(order: data),
    );
  }
}

class _OrderBody extends ConsumerStatefulWidget {
  const _OrderBody({required this.order});

  final CustomerOrder order;

  @override
  ConsumerState<_OrderBody> createState() => _OrderBodyState();
}

class _OrderBodyState extends ConsumerState<_OrderBody> {
  bool _isReordering = false;

  Future<void> _handleReorder() async {
    final CustomerOrder order = widget.order;
    final Cart currentCart = ref.read(cartProvider);

    if (currentCart.isNotEmpty && currentCart.restaurantId != order.restaurantId) {
      final bool? replace = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('Start new cart?'),
          content: Text(
            'Your cart contains items from ${currentCart.restaurantName}. '
            'Reordering from ${order.restaurantName} will replace your current cart.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Start new cart'),
            ),
          ],
        ),
      );
      if (!(replace ?? false)) return;
    }

    setState(() => _isReordering = true);
    try {
      final ReorderOutcome outcome = await ref
          .read(reorderControllerProvider.notifier)
          .reorder(order);
      if (!mounted) return;

      if (outcome.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nothing from this order is available right now.'),
          ),
        );
        return;
      }
      if (outcome.unavailable > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${outcome.unavailable} item${outcome.unavailable == 1 ? '' : 's'} '
              'from this order ${outcome.unavailable == 1 ? 'is' : 'are'} no longer '
              'available. The rest is in your cart.',
            ),
          ),
        );
      }
      context.goNamed(Routes.cart);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('We couldn\'t load that menu. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isReordering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final CustomerOrder order = widget.order;
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isOpen = order.status.isOpen;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'Order Summary',
          style: t.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 19,
            color: isDark ? Colors.white : const Color(0xFF111111),
          ),
        ),
        centerTitle: false,
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        children: <Widget>[
          // 1. Restaurant Header Section (Flat)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: ZopiqNetworkImage(
                    url: order.restaurantImageUrl,
                    fallback: GradientImagePlaceholder(
                      seed: order.restaurantId,
                      icon: Icons.restaurant_rounded,
                      iconSize: 22,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      order.restaurantName,
                      style: t.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: isDark ? Colors.white : const Color(0xFF111111),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${order.id} · ${formatOrderTimestamp(order.placedAt)}',
                      style: t.bodySmall?.copyWith(
                        color: isDark ? Colors.white60 : const Color(0xFF777777),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isOpen)
                OrderStatusChip(status: order.status)
              // While the order is live, the kitchen is worth a call — "no
              // onions" went astray, the ETA has slipped. Absent once it ends,
              // and absent on any restaurant with no number on file (0027), so
              // the dialler never opens on nothing.
              else if (order.restaurantPhone case final String phone)
                IconButton(
                  icon: const Icon(Icons.call_rounded, size: 20),
                  color: zc.primary,
                  tooltip: 'Call ${order.restaurantName}',
                  style: IconButton.styleFrom(
                    backgroundColor: zc.primary.withValues(alpha: 0.10),
                  ),
                  onPressed: () async {
                    final bool ok = await dialNumber(phone);
                    if (!ok && context.mounted) {
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          const SnackBar(
                            content: Text('This phone can\'t dial.'),
                          ),
                        );
                    }
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(height: 1, thickness: 1, color: isDark ? Colors.white12 : const Color(0xFFEEEEEE)),
          const SizedBox(height: 16),

          // 1b. What happened to the money (0077).
          //
          // Above the status banner, not below the bill, because on a cancelled
          // order this *is* the news — the customer opened this screen to find
          // out where their ₹565 went, and burying the answer under the itemised
          // list is how that becomes a phone call. Renders nothing on the
          // overwhelming majority of orders, which have no refund.
          OrderRefundSection(orderId: order.id),
          OrderIssueSection(
            issues:
                ref.watch(orderIssuesProvider(order.id)).valueOrNull ??
                const <OrderIssue>[],
          ),

          // 2. Tracking Card or Status Banner
          if (isOpen) ...<Widget>[
            OrderTrackingCard(order: order),
            const SizedBox(height: 12),
            _CancelOrder(orderId: order.id, fetchedStatus: order.status),
            const SizedBox(height: 16),
            Divider(height: 1, thickness: 1, color: isDark ? Colors.white12 : const Color(0xFFEEEEEE)),
            const SizedBox(height: 16),
          ] else if (order.status == OrderStatus.delivered) ...<Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0C831F).withValues(alpha: isDark ? 0.2 : 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(Icons.verified_rounded, color: Color(0xFF0C831F), size: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Order delivered successfully',
                      style: t.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                        color: isDark ? Colors.white : const Color(0xFF1E1E1E),
                      ),
                    ),
                    Text(
                      'Handed to customer at doorstep',
                      style: t.bodySmall?.copyWith(
                        color: isDark ? Colors.white60 : const Color(0xFF777777),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(height: 1, thickness: 1, color: isDark ? Colors.white12 : const Color(0xFFEEEEEE)),
            const SizedBox(height: 16),

            // 2b. The rating. Renders nothing at all when there is neither a
            // prompt to make nor a rating already given, so a receipt opened
            // three weeks later is the receipt it always was.
            OrderReviewSection(orderId: order.id),
          ],

          // 3. Itemized Dishes List Section
          Text(
            'ITEMS ORDERED',
            style: t.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: 0.8,
              color: isDark ? Colors.white54 : const Color(0xFF888888),
            ),
          ),
          const SizedBox(height: 14),
          for (int i = 0; i < order.lines.length; i++) ...<Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.only(top: 3),
                  child: ZopiqVegIndicator(isVeg: true, size: 14),
                ),
                const SizedBox(width: 10),
                Text(
                  '${order.lines[i].quantity}x',
                  style: t.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: zc.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        order.lines[i].name,
                        style: t.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                          color: isDark ? Colors.white : const Color(0xFF1E1E1E),
                        ),
                      ),
                      if (order.lines[i].options.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          order.lines[i].optionsLabel,
                          style: t.bodySmall?.copyWith(
                            color: isDark ? Colors.white60 : const Color(0xFF777777),
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '₹${order.lines[i].lineTotal}',
                  style: t.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    color: isDark ? Colors.white : const Color(0xFF1E1E1E),
                  ),
                ),
              ],
            ),
            if (i < order.lines.length - 1) const SizedBox(height: 12),
          ],
          const SizedBox(height: 16),
          Divider(height: 1, thickness: 1, color: isDark ? Colors.white12 : const Color(0xFFEEEEEE)),
          const SizedBox(height: 16),

          // 4. Bill Details Breakdown (Zomato Flat Receipt)
          Text(
            'BILL BREAKDOWN',
            style: t.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: 0.8,
              color: isDark ? Colors.white54 : const Color(0xFF888888),
            ),
          ),
          const SizedBox(height: 12),
          _FlatBillRow(label: 'Item total', value: '₹${order.subtotal}'),
          const SizedBox(height: 8),
          _FlatBillRow(
            label: 'Delivery fee',
            value: order.deliveryFee == 0 ? 'FREE' : '₹${order.deliveryFee}',
            isGreen: order.deliveryFee == 0,
          ),
          // Only when charged. All three are 0 on every order to date (0078
          // models the fee stack, it does not switch it on), and a row of
          // zeroes is a question the customer should not have to ask.
          if (order.platformFee > 0) ...<Widget>[
            const SizedBox(height: 8),
            _FlatBillRow(label: 'Platform fee', value: '₹${order.platformFee}'),
          ],
          if (order.packagingFee > 0) ...<Widget>[
            const SizedBox(height: 8),
            _FlatBillRow(label: 'Packaging', value: '₹${order.packagingFee}'),
          ],
          if (order.surgeFee > 0) ...<Widget>[
            const SizedBox(height: 8),
            _FlatBillRow(label: 'Surge', value: '₹${order.surgeFee}'),
          ],
          const SizedBox(height: 8),
          _FlatBillRow(label: 'Taxes & restaurant charges', value: '₹${order.taxes}'),
          if (order.discount > 0) ...<Widget>[
            const SizedBox(height: 8),
            _FlatBillRow(
              label: order.couponCode == null ? 'Discount' : 'Discount (${order.couponCode})',
              value: '−₹${order.discount}',
              isGreen: true,
            ),
          ],
          const SizedBox(height: 12),
          Divider(height: 1, thickness: 1, color: isDark ? Colors.white12 : const Color(0xFFEEEEEE)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                isOpen ? 'To pay' : 'Grand Total Paid',
                style: t.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: isDark ? Colors.white : const Color(0xFF111111),
                ),
              ),
              Text(
                '₹${order.total}',
                style: t.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  color: isDark ? Colors.white : const Color(0xFF111111),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(height: 1, thickness: 1, color: isDark ? Colors.white12 : const Color(0xFFEEEEEE)),
          const SizedBox(height: 16),

          // 5. Delivery & Payment Details (Flat)
          Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: zc.primary.withValues(alpha: isDark ? 0.18 : 0.08),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    Icons.near_me_rounded,
                    size: 18,
                    color: zc.primary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      isOpen ? 'Delivering to' : 'Delivered to',
                      style: t.labelSmall?.copyWith(
                        color: isDark ? Colors.white54 : const Color(0xFF888888),
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      order.deliveryTo,
                      style: t.bodyMedium?.copyWith(
                        color: isDark ? Colors.white : const Color(0xFF1E1E1E),
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    // What the rider was told, frozen onto the order (0061).
                    // Shown here rather than only at checkout so the customer
                    // can check what they actually asked for before ringing to
                    // ask why nobody used the side gate.
                    if (order.deliveryNotes case final String note) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        note,
                        style: t.bodySmall?.copyWith(
                          color: isDark
                              ? Colors.white60
                              : const Color(0xFF777777),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withValues(alpha: isDark ? 0.18 : 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.account_balance_wallet_rounded,
                    size: 18,
                    color: Color(0xFF0284C7),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Payment Method',
                      style: t.labelSmall?.copyWith(
                        color: isDark ? Colors.white54 : const Color(0xFF888888),
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      order.paymentMethod == PaymentMethod.cod
                          ? 'Cash on delivery'
                          : 'Paid online · ${order.paymentId ?? order.id}',
                      style: t.bodyMedium?.copyWith(
                        color: isDark ? Colors.white : const Color(0xFF1E1E1E),
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 6. The document. Only on a delivered order, because that is when a
          // number is issued (0063) — offering it earlier would be offering a
          // screen that can only apologise.
          if (order.status == OrderStatus.delivered) ...<Widget>[
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? Colors.white : const Color(0xFF222222),
                  side: BorderSide(color: isDark ? Colors.white30 : const Color(0xFFCCCCCC)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.receipt_long_rounded, size: 18),
                onPressed: () => context.pushNamed(
                  Routes.invoice,
                  pathParameters: <String, String>{'id': order.id},
                ),
                label: const Text(
                  'Invoice',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // 7. Flat Action Buttons
          Row(
            children: <Widget>[
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark ? Colors.white : const Color(0xFF222222),
                      side: BorderSide(color: isDark ? Colors.white30 : const Color(0xFFCCCCCC)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    // This used to show a snackbar reading "Support team will
                    // connect with you shortly." and then do nothing at all —
                    // no ticket, no queue, nobody told. It now files a real
                    // complaint (0095).
                    onPressed: () => showReportIssueSheet(
                      context,
                      orderId: order.id,
                      submit: (IssueCategory category, String? body) async {
                        await ref
                            .read(orderRepositoryProvider)
                            .raiseIssue(
                              orderId: order.id,
                              category: category,
                              body: body,
                            );
                        // The receipt above reads this to show what was
                        // reported, so it is stale for no longer than it takes
                        // the sheet to pop.
                        ref.invalidate(orderIssuesProvider(order.id));
                      },
                    ),
                    child: const Text('Get help', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: zc.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _isReordering ? null : _handleReorder,
                    child: _isReordering
                        ? const ZopiqLoader(size: 18, strokeWidth: 2, color: Colors.white)
                        : const Text('Reorder', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// The one destructive thing a customer can do to a live order.
///
/// Three renderings, and which one shows is decided by the *live* status, not
/// the one the receipt was fetched with — a kitchen that accepts and starts
/// cooking while this screen is open must take the button away as it happens,
/// or the tap that follows is refused for a reason the customer can't see.
///
/// Once the window closes the button is replaced by a **sentence**, never a
/// greyed-out button: "you can't do this" with no reason attached is what makes
/// somebody phone the restaurant. The words are the same ones `cancel_my_order`
/// would have refused with (migration 0051), so the news reads identically
/// whether it arrives before the tap or after it.
class _CancelOrder extends ConsumerStatefulWidget {
  const _CancelOrder({required this.orderId, required this.fetchedStatus});

  final String orderId;

  /// What the receipt was loaded with — the fallback for a status stream that
  /// has not delivered its first event yet, or has dropped.
  final OrderStatus fetchedStatus;

  @override
  ConsumerState<_CancelOrder> createState() => _CancelOrderState();
}

class _CancelOrderState extends ConsumerState<_CancelOrder> {
  /// The order service's own words when it refused. Held on the screen rather
  /// than flashed in a snackbar: it is the answer to what the customer just
  /// asked, and it should still be there when they look back at it.
  String? _refusal;

  Future<void> _cancel() async {
    final String? reason = await showCancelOrderSheet(context, widget.orderId);
    // Dismissed. Not a cancellation of a cancellation — just nothing.
    if (reason == null || !mounted) return;

    setState(() => _refusal = null);
    final String? refusal = await ref
        .read(orderCancelControllerProvider.notifier)
        .cancel(widget.orderId, reason: reason.isEmpty ? null : reason);
    if (mounted && refusal != null) setState(() => _refusal = refusal);
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final OrderStatus status =
        ref.watch(orderStatusProvider(widget.orderId)).valueOrNull ??
        widget.fetchedStatus;
    final bool isBusy = ref.watch(orderCancelControllerProvider);

    if (status.cannotCancelBecause case final String reason) {
      return Text(
        // The refusal the service actually gave wins over the one derived from
        // the status: they agree in every ordinary case, and when they don't it
        // is because the order moved a half-second ago and the service is right.
        _refusal ?? reason,
        style: t.bodySmall?.copyWith(
          color: isDark ? Colors.white54 : const Color(0xFF888888),
          fontSize: 12.5,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (_refusal != null) ...<Widget>[
          Text(
            _refusal!,
            style: t.bodySmall?.copyWith(
              color: const Color(0xFFD32F2F),
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFD32F2F),
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: isBusy ? null : _cancel,
            child: Text(
              isBusy ? 'Cancelling…' : 'Cancel order',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _FlatBillRow extends StatelessWidget {
  const _FlatBillRow({required this.label, required this.value, this.isGreen = false});

  final String label;
  final String value;
  final bool isGreen;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(
          label,
          style: t.bodyMedium?.copyWith(
            color: isDark ? Colors.white70 : const Color(0xFF666666),
            fontSize: 13.5,
          ),
        ),
        Text(
          value,
          style: t.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
            color: isGreen
                ? const Color(0xFF0C831F)
                : (isDark ? Colors.white : const Color(0xFF222222)),
          ),
        ),
      ],
    );
  }
}

class _OrderLineRow extends StatelessWidget {
  const _OrderLineRow({required this.line});

  final OrderLine line;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Veg / Non-Veg Indicator
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(top: 6),
          decoration: BoxDecoration(
            color: zc.veg,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),

        // Quantity Pill Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: zc.primary.withValues(alpha: isDark ? 0.2 : 0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${line.quantity}x',
            style: t.labelSmall?.copyWith(
              color: zc.primary,
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
        ),
        const SizedBox(width: 10),

        // Name & Options
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                line.name,
                style: t.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: isDark ? Colors.white : const Color(0xFF1E1E1E),
                ),
              ),
              if (line.options.isNotEmpty) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  line.optionsLabel,
                  style: t.bodySmall?.copyWith(
                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),

        // Price
        Text(
          '₹${line.lineTotal}',
          style: t.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: isDark ? Colors.white : const Color(0xFF1E1E1E),
          ),
        ),
      ],
    );
  }
}

/// Detailed Bill Breakdown Card
class _BillDetailsCard extends StatelessWidget {
  const _BillDetailsCard({required this.order});

  final CustomerOrder order;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isOpen = order.status.isOpen;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E24) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE8ECEF),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Header Row
          Row(
            children: <Widget>[
              Icon(
                Icons.receipt_long_rounded,
                size: 18,
                color: zc.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'BILL DETAILS',
                style: t.labelLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 12.5,
                  letterSpacing: 0.6,
                  color: isDark ? Colors.white70 : const Color(0xFF475569),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFF1F5F9)),
          const SizedBox(height: 14),

          // Itemized rows
          _BillRow(label: 'Item total', amount: order.subtotal),
          const SizedBox(height: 8),
          _BillRow(
            label: 'Delivery fee',
            amount: order.deliveryFee,
            freeWhenZero: true,
          ),
          if (order.platformFee > 0) ...<Widget>[
            const SizedBox(height: 8),
            _BillRow(label: 'Platform fee', amount: order.platformFee),
          ],
          if (order.packagingFee > 0) ...<Widget>[
            const SizedBox(height: 8),
            _BillRow(label: 'Packaging', amount: order.packagingFee),
          ],
          if (order.surgeFee > 0) ...<Widget>[
            const SizedBox(height: 8),
            _BillRow(label: 'Surge', amount: order.surgeFee),
          ],
          const SizedBox(height: 8),
          _BillRow(label: 'Taxes & restaurant charges', amount: order.taxes),
          if (order.discount > 0) ...<Widget>[
            const SizedBox(height: 8),
            _BillRow(
              label: order.couponCode == null
                  ? 'Coupon discount'
                  : 'Coupon discount (${order.couponCode})',
              amount: -order.discount,
              highlight: true,
            ),
          ],

          const SizedBox(height: 14),
          Divider(height: 1, color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFE2E8F0)),
          const SizedBox(height: 14),

          // Total Paid Row
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      isOpen ? 'To pay' : 'Grand Total Paid',
                      style: t.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        fontSize: 15.5,
                        color: isDark ? Colors.white : const Color(0xFF1E1E1E),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      order.paymentMethod == PaymentMethod.cod
                          ? 'Cash on delivery'
                          : 'Paid via Online UPI',
                      style: t.bodySmall?.copyWith(
                        color: zc.veg,
                        fontWeight: FontWeight.w700,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '₹${order.total}',
                style: t.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  color: zc.primaryDeep,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Delivery Destination & Payment Details Card
class _DeliveryPaymentCard extends StatelessWidget {
  const _DeliveryPaymentCard({required this.order});

  final CustomerOrder order;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isOpen = order.status.isOpen;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E24) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE8ECEF),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Delivery Address Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: zc.primary.withValues(alpha: isDark ? 0.15 : 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.location_on_rounded,
                  size: 18,
                  color: zc.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      isOpen ? 'Delivering to' : 'Delivered to',
                      style: t.labelSmall?.copyWith(
                        color: isDark ? Colors.white60 : const Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      order.deliveryTo,
                      style: t.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: isDark ? Colors.white : const Color(0xFF1E1E1E),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFF1F5F9)),
          const SizedBox(height: 14),

          // Payment Details Row
          Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.payment_rounded,
                  size: 18,
                  color: isDark ? Colors.white70 : const Color(0xFF475569),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Payment Method',
                      style: t.labelSmall?.copyWith(
                        color: isDark ? Colors.white60 : const Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      order.paymentMethod == PaymentMethod.cod
                          ? 'Cash on delivery'
                          : 'Paid online · ${order.paymentId ?? order.id}',
                      style: t.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: isDark ? Colors.white : const Color(0xFF1E1E1E),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Dead end message state ("Order not found" / "Couldn't load")
class _OrderMessage extends StatelessWidget {
  const _OrderMessage({
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: zc.primary.withValues(alpha: isDark ? 0.15 : 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.receipt_long_outlined,
                  size: 36,
                  color: zc.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: t.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  color: isDark ? Colors.white : const Color(0xFF1E1E1E),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                body,
                style: t.bodyMedium?.copyWith(
                  color: isDark ? Colors.white60 : const Color(0xFF64748B),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 44,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: zc.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: onAction,
                  child: Text(
                    actionLabel,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Line row for bill items
class _BillRow extends StatelessWidget {
  const _BillRow({
    required this.label,
    required this.amount,
    this.highlight = false,
    this.freeWhenZero = false,
  });

  final String label;

  /// Negative for a discount, rendered as `-₹50`.
  final int amount;

  final bool highlight;
  final bool freeWhenZero;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color? color = highlight ? zc.veg : null;

    final String value = amount < 0
        ? '−₹${-amount}'
        : (freeWhenZero && amount == 0 ? 'FREE' : '₹$amount');

    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: t.bodyMedium?.copyWith(
              color: color ?? (isDark ? Colors.white70 : const Color(0xFF64748B)),
              fontWeight: highlight ? FontWeight.w800 : FontWeight.w500,
              fontSize: 13.5,
            ),
          ),
        ),
        Text(
          value,
          style: t.bodyMedium?.copyWith(
            color: color ?? (isDark ? Colors.white : const Color(0xFF1E1E1E)),
            fontWeight: highlight ? FontWeight.w900 : FontWeight.w700,
            fontSize: 13.5,
          ),
        ),
      ],
    );
  }
}

