import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/checkout/domain/entities/order_issue.dart';
import 'package:zopiqnow/features/checkout/presentation/widgets/order_issue_section.dart';
import 'package:zopiqnow/features/checkout/presentation/widgets/report_issue_sheet.dart';
import 'package:zopiqnow/features/gifts/domain/entities/gift_order.dart';
import 'package:zopiqnow/features/gifts/presentation/pages/gift_orders_page.dart'
    show GiftStatusPill;
import 'package:zopiqnow/features/gifts/presentation/providers/gift_providers.dart';

/// One gift order in full — where it is, who is carrying it, and what it cost.
///
/// This screen is the answer to "the customer should get proper acknowledgement
/// screens and infos". A gift has no rider on a map and no minute-by-minute ETA,
/// so what it *can* honestly show has to be shown well: which of four steps it
/// is on, the courier and tracking number once those exist, and a receipt whose
/// tax line is the server's number rather than a guess.
class GiftOrderDetailPage extends ConsumerWidget {
  const GiftOrderDetailPage({
    required this.orderId,
    required this.onBack,
    super.key,
  });

  final String orderId;
  final VoidCallback onBack;

  /// Files a complaint against this gift order (0114).
  ///
  /// The same sheet the food receipt opens, with the gift's own submit and the
  /// gift's own category list — no `rider`, because nobody rides a gift. The
  /// sheet prints the service's refusals itself, so there is nothing to catch
  /// here.
  Future<void> _report(BuildContext context, WidgetRef ref, String id) {
    return showReportIssueSheet(
      context,
      orderId: id,
      categories: IssueCategory.forGifts,
      hint: 'The frame arrived cracked at one corner.',
      submit: (IssueCategory category, String? body) async {
        await ref
            .read(giftOrderDataSourceProvider)
            .raiseIssue(orderId: id, category: category, body: body);
        ref.invalidate(giftOrderIssuesProvider(id));
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final GiftOrder? order = ref.watch(giftOrderByIdProvider(orderId));
    final AsyncValue<List<GiftOrder>> all = ref.watch(giftOrdersProvider);

    final Widget body;
    if (order == null) {
      body = all.isLoading
          ? const Center(child: ZopiqLoader())
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(ZopiqSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text('We couldn\'t find that order', style: t.titleMedium),
                    const SizedBox(height: ZopiqSpacing.xl),
                    ZopiqButton(
                      label: 'Your gift orders',
                      expand: false,
                      onPressed: onBack,
                    ),
                  ],
                ),
              ),
            );
    } else {
      body = ListView(
        padding: const EdgeInsets.all(ZopiqSpacing.pageGutter),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  order.shopName,
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              GiftStatusPill(status: order.status),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            order.id,
            style: t.bodySmall?.copyWith(color: zc.textMuted),
          ),
          const SizedBox(height: ZopiqSpacing.xl),

          if (order.status == GiftOrderStatus.cancelled)
            _Cancelled(reason: order.statusReason)
          else
            _Tracker(status: order.status),

          const SizedBox(height: ZopiqSpacing.xl),

          // The courier. The single most useful fact on this screen once it
          // exists, so it is a card rather than a line.
          if (order.courierName case final String courier) ...<Widget>[
            ZopiqCard(
              elevated: false,
              child: Padding(
                padding: const EdgeInsets.all(ZopiqSpacing.md),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.local_shipping_rounded, color: zc.primary),
                    const SizedBox(width: ZopiqSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            courier,
                            style: t.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            // Not every courier issues one, so this says which
                            // case it is rather than showing an empty field.
                            order.trackingRef == null
                                ? 'No tracking number for this one'
                                : 'Tracking ${order.trackingRef}',
                            style: t.bodySmall?.copyWith(color: zc.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: ZopiqSpacing.xl),
          ],

          Text(
            'SENDING TO',
            style: t.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: zc.textMuted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: ZopiqSpacing.xs),
          Text(order.deliveryTo, style: t.bodyMedium),
          const SizedBox(height: ZopiqSpacing.xl),

          Text(
            'RECEIPT',
            style: t.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: zc.textMuted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: ZopiqSpacing.sm),
          _Lines(orderId: order.id),
          const SizedBox(height: ZopiqSpacing.sm),
          Divider(color: zc.divider, height: 1),
          const SizedBox(height: ZopiqSpacing.sm),
          _Money(label: 'Subtotal', amount: order.subtotal),
          if (order.deliveryFee > 0)
            _Money(label: 'Delivery', amount: order.deliveryFee),
          _Money(label: 'GST', amount: order.taxes),
          const SizedBox(height: ZopiqSpacing.xs),
          _Money(label: 'Paid', amount: order.total, strong: true),

          // What they have already told us, if anything. Above the button for
          // the same reason the food receipt puts it above them: somebody who
          // has complained is looking for their complaint, not for the button
          // that raises another one.
          if (ref
              .watch(giftOrderIssuesProvider(order.id))
              .valueOrNull
              case final List<OrderIssue> issues
              when issues.isNotEmpty) ...<Widget>[
            const SizedBox(height: ZopiqSpacing.xl),
            OrderIssueSection(issues: issues),
          ],

          // **The only door, and it is always open.** A gift order is final once
          // it is placed (0116) — there is no cancel and no refund — so this is
          // the whole of a customer's recourse and it is offered on every gift
          // order, in every state, including a cancelled one. A screen that
          // refuses to hear "it never came" is the screen somebody phones about.
          const SizedBox(height: ZopiqSpacing.xxl),
          ZopiqButton(
            label: 'Report a problem',
            variant: ZopiqButtonVariant.outline,
            onPressed: () => _report(context, ref, order.id),
          ),
          const SizedBox(height: ZopiqSpacing.xl),
        ],
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        leading: BackButton(
          onPressed: () => Navigator.of(context).canPop()
              ? Navigator.of(context).pop()
              : onBack(),
        ),
        title: const Text('Gift order'),
        centerTitle: false,
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: body,
    );
  }
}

/// Four steps, and which one it is on. Not a progress bar with a percentage —
/// there is no clock behind a courier, and a bar that sat at 60% for two days
/// would be a worse lie than four honest dots.
class _Tracker extends StatelessWidget {
  const _Tracker({required this.status});

  final GiftOrderStatus status;

  static const List<({String label, String blurb})> _steps =
      <({String label, String blurb})>[
    (label: 'Order placed', blurb: 'We have your order'),
    (label: 'Being prepared', blurb: 'Our team is packing it'),
    (label: 'On its way', blurb: 'Handed to a courier'),
    (label: 'Delivered', blurb: 'It arrived'),
  ];

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final int at = status.step ?? 0;

    return Column(
      children: <Widget>[
        for (int i = 0; i < _steps.length; i++)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Column(
                children: <Widget>[
                  Icon(
                    i <= at
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 20,
                    color: i <= at ? zc.veg : zc.textMuted,
                  ),
                  if (i < _steps.length - 1)
                    Container(
                      width: 2,
                      height: 26,
                      color: i < at ? zc.veg : zc.divider,
                    ),
                ],
              ),
              const SizedBox(width: ZopiqSpacing.md),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: ZopiqSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _steps[i].label,
                        style: t.bodyLarge?.copyWith(
                          fontWeight: i == at
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: i <= at ? null : zc.textMuted,
                        ),
                      ),
                      Text(
                        _steps[i].blurb,
                        style: t.bodySmall?.copyWith(color: zc.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _Cancelled extends StatelessWidget {
  const _Cancelled({this.reason});

  final String? reason;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return ZopiqCard(
      elevated: false,
      child: Padding(
        padding: const EdgeInsets.all(ZopiqSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.cancel_rounded, color: zc.nonVeg),
            const SizedBox(width: ZopiqSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'This order was cancelled',
                    style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (reason case final String why) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(why, style: t.bodySmall?.copyWith(color: zc.textMuted)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Lines extends ConsumerWidget {
  const _Lines({required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme t = Theme.of(context).textTheme;
    final List<GiftOrderLine> lines =
        ref.watch(giftOrderLinesProvider(orderId)).valueOrNull ??
        const <GiftOrderLine>[];

    return Column(
      children: <Widget>[
        for (final GiftOrderLine l in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: ZopiqSpacing.xs),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text('${l.quantity} × ${l.name}', style: t.bodyMedium),
                ),
                Text('₹${l.lineTotal}', style: t.bodyMedium),
              ],
            ),
          ),
      ],
    );
  }
}

class _Money extends StatelessWidget {
  const _Money({required this.label, required this.amount, this.strong = false});

  final String label;
  final int amount;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final TextStyle? style = strong
        ? t.titleMedium?.copyWith(fontWeight: FontWeight.w800)
        : t.bodyMedium;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: style)),
          Text('₹$amount', style: style),
        ],
      ),
    );
  }
}
