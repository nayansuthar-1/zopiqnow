import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/core/formatting/formatters.dart';
import 'package:zopiq_vendor/core/widgets/vendor_message.dart';
import 'package:zopiq_vendor/core/widgets/vendor_skeleton.dart';
import 'package:zopiq_vendor/features/orders/domain/entities/vendor_order.dart';
import 'package:zopiq_vendor/features/orders/presentation/providers/history_providers.dart';
import 'package:zopiq_vendor/features/orders/presentation/widgets/history_ticket.dart';

/// The restaurant's book: finished orders, looked back over rather than watched.
///
/// A window (Today, last 7 days, a custom span) is chosen at the top and fetched
/// once; the outcome, payment and id-search chips below it refine that window in
/// place without another round trip. A summary sits above the list so the
/// day's shape — how many, how much — reads before a single ticket does.
class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<VendorOrder>> orders = ref.watch(
      historyOrdersProvider,
    );
    final List<VendorOrder> visible = ref.watch(filteredHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: Column(
        children: <Widget>[
          const _RangeChips(),
          const _SearchField(),
          const _RefineChips(),
          Divider(height: 1, color: context.zc.divider),
          Expanded(
            child: orders.when(
              loading: () => const VendorSkeletonList(),
              error: (Object _, StackTrace _) => VendorMessage(
                icon: Icons.cloud_off_rounded,
                title: 'We\'ve lost the connection',
                body: 'Your past orders will be here once it\'s back.',
                actionLabel: 'Retry',
                onAction: () => ref.invalidate(historyOrdersProvider),
              ),
              data: (_) => RefreshIndicator(
                onRefresh: () => ref.refresh(historyOrdersProvider.future),
                child: visible.isEmpty
                    ? _EmptyList(hasWindowOrders: orders.value?.isNotEmpty ?? false)
                    : _HistoryList(orders: visible),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Empty means one of two things, and they read differently: the window truly
/// had no finished orders, or the filters hid the ones it did. A [RefreshIndicator]
/// needs a scrollable child, so this is one.
class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.hasWindowOrders});

  final bool hasWindowOrders;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: <Widget>[
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.15),
        hasWindowOrders
            ? const VendorMessage(
                icon: Icons.filter_alt_off_rounded,
                title: 'Nothing matches these filters',
                body: 'Try a different outcome, payment or search.',
              )
            : const VendorMessage(
                icon: Icons.history_rounded,
                title: 'No orders in this period',
                body: 'Delivered and cancelled orders show up here.',
              ),
      ],
    );
  }
}

class _HistoryList extends ConsumerWidget {
  const _HistoryList({required this.orders});

  final List<VendorOrder> orders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: ZopiqSpacing.lg),
      // The summary is item 0, so it scrolls with the list rather than pinning
      // and stealing height from the tickets on a short screen.
      itemCount: orders.length + 1,
      itemBuilder: (BuildContext context, int i) {
        if (i == 0) return const _SummaryHeader();
        return RepaintBoundary(
          child: HistoryTicket(
            key: ValueKey<String>(orders[i - 1].id),
            order: orders[i - 1],
          ),
        );
      },
    );
  }
}

class _SummaryHeader extends ConsumerWidget {
  const _SummaryHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HistorySummary s = ref.watch(historySummaryProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.md,
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.xs,
      ),
      child: ZopiqCard(
        elevated: false,
        child: Row(
          children: <Widget>[
            _Stat(label: 'Orders', value: '${s.total}'),
            const _StatDivider(),
            _Stat(label: 'Delivered', value: '${s.delivered}'),
            const _StatDivider(),
            _Stat(label: 'Cancelled', value: '${s.cancelled}'),
            const _StatDivider(),
            _Stat(label: 'Gross', value: formatRupees(s.gross)),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: ZopiqSpacing.xxs),
          Text(
            label,
            style: t.bodySmall?.copyWith(color: zc.textMuted),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 28,
    color: context.zc.divider,
  );
}

/// The date window. A horizontal strip because five options do not earn a second
/// row, and "Custom" opens a range picker rather than carrying its own controls.
class _RangeChips extends ConsumerWidget {
  const _RangeChips();

  Future<void> _pickCustom(BuildContext context, WidgetRef ref) async {
    final DateTime now = DateTime.now();
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
    );
    if (picked != null) {
      ref
          .read(historyFilterProvider.notifier)
          .setCustomRange(picked.start, picked.end);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HistoryRange selected = ref.watch(
      historyFilterProvider.select((HistoryFilter f) => f.range),
    );

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: ZopiqSpacing.pageGutter,
          vertical: ZopiqSpacing.sm,
        ),
        children: <Widget>[
          for (final HistoryRange r in HistoryRange.values)
            Padding(
              padding: const EdgeInsets.only(right: ZopiqSpacing.sm),
              child: _Chip(
                label: r.label,
                selected: r == selected,
                onSelected: () {
                  if (r == HistoryRange.custom) {
                    _pickCustom(context, ref);
                  } else {
                    ref.read(historyFilterProvider.notifier).setRange(r);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// The outcome and payment refinements, on one wrapping row.
class _RefineChips extends ConsumerWidget {
  const _RefineChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HistoryFilter f = ref.watch(historyFilterProvider);
    final HistoryFilterController c = ref.read(historyFilterProvider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZopiqSpacing.pageGutter,
        0,
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.sm,
      ),
      child: Wrap(
        spacing: ZopiqSpacing.sm,
        runSpacing: ZopiqSpacing.xs,
        children: <Widget>[
          for (final HistoryOutcome o in HistoryOutcome.values)
            _Chip(
              label: o.label,
              selected: o == f.outcome,
              onSelected: () => c.setOutcome(o),
            ),
          const _Chip(
            label: '·',
            selected: false,
            onSelected: null,
            spacer: true,
          ),
          for (final HistoryPayment p in HistoryPayment.values)
            if (p != HistoryPayment.all)
              _Chip(
                label: p.label,
                selected: p == f.payment,
                onSelected: () => c.setPayment(
                  p == f.payment ? HistoryPayment.all : p,
                ),
              ),
        ],
      ),
    );
  }
}

/// Search by order id, debounced so a five-character ZPQ number is one filter
/// pass, not five.
class _SearchField extends ConsumerStatefulWidget {
  const _SearchField();

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(historyFilterProvider.notifier).setQuery(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZopiqSpacing.pageGutter,
        0,
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.sm,
      ),
      child: TextField(
        controller: _controller,
        onChanged: _onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search order ID',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    _controller.clear();
                    _debounce?.cancel();
                    ref.read(historyFilterProvider.notifier).setQuery('');
                    setState(() {});
                  },
                ),
          border: OutlineInputBorder(
            borderRadius: ZopiqRadii.rMd,
            borderSide: BorderSide(color: zc.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: ZopiqRadii.rMd,
            borderSide: BorderSide(color: zc.divider),
          ),
        ),
      ),
    );
  }
}

/// A selectable pill — the app's filter chip. Orange when chosen, hairline when
/// not. The `spacer` variant is an inert dot that visually splits the outcome
/// group from the payment group without a real control.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.spacer = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onSelected;
  final bool spacer;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    if (spacer) {
      return Center(
        child: Text(label, style: t.bodyMedium?.copyWith(color: zc.divider)),
      );
    }

    final Color fg = selected ? Colors.white : zc.textMuted;

    return Material(
      color: selected ? zc.primary : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: ZopiqRadii.rPill,
        side: BorderSide(color: selected ? zc.primary : zc.divider),
      ),
      child: InkWell(
        borderRadius: ZopiqRadii.rPill,
        onTap: onSelected,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ZopiqSpacing.md,
            vertical: ZopiqSpacing.xs,
          ),
          child: Text(
            label,
            style: t.labelLarge?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
