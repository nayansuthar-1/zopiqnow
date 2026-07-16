import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/features/orders/domain/entities/vendor_order.dart';
import 'package:zopiq_vendor/features/orders/presentation/providers/orders_providers.dart';
import 'package:zopiq_vendor/features/orders/presentation/widgets/history_ticket.dart';

/// The finished orders, newest first.
///
/// Reads the same stream the queue does — an order in history is one the queue
/// let go — so nothing is fetched twice and history updates the instant an order
/// is delivered or cancelled on the Orders tab.
class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<VendorOrder>> orders = ref.watch(ordersProvider);
    final List<VendorOrder> history = ref.watch(orderHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: orders.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object _, StackTrace _) => _Message(
          icon: Icons.cloud_off_rounded,
          title: 'We\'ve lost the connection',
          body: 'Your past orders will be here once it\'s back.',
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(ordersProvider),
        ),
        data: (_) {
          if (history.isEmpty) {
            return const _Message(
              icon: Icons.history_rounded,
              title: 'No past orders yet',
              body: 'Delivered and cancelled orders show up here.',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.sm),
            itemCount: history.length,
            itemBuilder: (BuildContext context, int i) => RepaintBoundary(
              child: HistoryTicket(
                key: ValueKey<String>(history[i].id),
                order: history[i],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ZopiqSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 56, color: zc.textMuted),
            const SizedBox(height: ZopiqSpacing.lg),
            Text(title, style: t.titleMedium),
            const SizedBox(height: ZopiqSpacing.xs),
            Text(
              body,
              style: t.bodyMedium?.copyWith(color: zc.textMuted),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null) ...<Widget>[
              const SizedBox(height: ZopiqSpacing.xl),
              ZopiqButton(
                label: actionLabel!,
                expand: false,
                onPressed: onAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
