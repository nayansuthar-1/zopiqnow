import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zopiqnow/features/checkout/domain/entities/order_refund.dart';
import 'package:zopiqnow/features/checkout/presentation/providers/orders_providers.dart';

/// What happened to the money on an order that ended badly (migration 0077).
///
/// The audit's own claim about this section is that the sentence "Refund
/// initiated, in your account by 3 Aug" prevents more support contacts than any
/// other single string in a delivery app, and that is the whole design brief: an
/// amount, and a date. Not a progress bar, not a status the customer has to
/// interpret.
///
/// Renders nothing at all when there is no refund, which is almost every order —
/// including while the read is in flight, so a receipt does not jump. And there
/// is nothing to tap: a refund is not an action the customer takes.
class OrderRefundSection extends ConsumerWidget {
  const OrderRefundSection({required this.orderId, super.key});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<OrderRefund> refunds =
        ref.watch(orderRefundsProvider(orderId)).valueOrNull ??
        const <OrderRefund>[];
    if (refunds.isEmpty) return const SizedBox.shrink();

    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          refunds.length == 1 ? 'REFUND' : 'REFUNDS',
          style: t.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 12,
            letterSpacing: 0.8,
            color: isDark ? Colors.white54 : const Color(0xFF888888),
          ),
        ),
        const SizedBox(height: 12),
        for (final OrderRefund refund in refunds) ...<Widget>[
          _RefundRow(refund: refund),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 4),
        Divider(
          height: 1,
          thickness: 1,
          color: isDark ? Colors.white12 : const Color(0xFFEEEEEE),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _RefundRow extends StatelessWidget {
  const _RefundRow({required this.refund});

  final OrderRefund refund;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    // Green once it has actually gone, amber while somebody still has to send
    // it, and the palette's own error colour when the gateway refused. Three
    // states, because a refund only ever has three answers worth giving.
    final (Color tone, IconData icon) = switch (refund.status) {
      RefundStatus.paid => (const Color(0xFF0C831F), Icons.check_circle_rounded),
      RefundStatus.failed => (
        Theme.of(context).colorScheme.error,
        Icons.error_outline_rounded,
      ),
      _ => (const Color(0xFFB26A00), Icons.schedule_rounded),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: tone.withValues(alpha: isDark ? 0.2 : 0.1),
            shape: BoxShape.circle,
          ),
          child: Center(child: Icon(icon, color: tone, size: 20)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _headline(refund),
                style: t.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 14.5,
                  color: isDark ? Colors.white : const Color(0xFF1E1E1E),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _detail(refund),
                style: t.bodySmall?.copyWith(
                  color: isDark ? Colors.white70 : const Color(0xFF666666),
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _headline(OrderRefund refund) {
    final String amount = '₹${refund.amount}';
    return switch (refund.status) {
      RefundStatus.paid => '$amount refunded',
      RefundStatus.failed => '$amount refund held up',
      _ when refund.isPartial => '$amount refund on its way',
      _ => '$amount refund initiated',
    };
  }

  String _detail(OrderRefund refund) {
    switch (refund.status) {
      case RefundStatus.paid:
        final String on = refund.paidAt == null
            ? ''
            : ' on ${_shortDate(refund.paidAt!)}';
        return 'Sent back to your original payment method$on.';
      case RefundStatus.failed:
        // Deliberately does not say "contact us". The platform knows this
        // failed — a refund in this state is already on somebody's queue — and
        // asking the customer to chase it is how a bad day becomes a bad review.
        return 'Your bank turned this back. We\'re sorting it out and will send '
            'it again.';
      case RefundStatus.requested:
      case RefundStatus.approved:
      case RefundStatus.processing:
        final String why = refund.reason.isEmpty ? '' : '${refund.reason}. ';
        return '${why}In your account by ${_shortDate(refund.expectedBy)}.';
    }
  }
}

const List<String> _months = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _shortDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';
