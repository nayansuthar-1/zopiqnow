import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_vendor/core/formatting/formatters.dart';
import 'package:zopiq_vendor/core/widgets/vendor_animations.dart';
import 'package:zopiq_vendor/core/widgets/vendor_message.dart';
import 'package:zopiq_vendor/core/widgets/vendor_skeleton.dart';
import 'package:zopiq_vendor/core/widgets/vendor_svg_icons.dart';
import 'package:zopiq_vendor/features/orders/domain/entities/vendor_order.dart';
import 'package:zopiq_vendor/features/orders/presentation/providers/history_providers.dart';
import 'package:zopiq_vendor/features/orders/presentation/widgets/history_ticket.dart';

/// The order history book with advanced date range and status filters.
class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<VendorOrder>> orders = ref.watch(
      historyOrdersProvider,
    );
    final List<VendorOrder> visible = ref.watch(filteredHistoryProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // ── 1. Custom Header ──
            const VendorFadeSlide(
              child: _Header(),
            ),

            // ── 2. Date Range Filter Bar ──
            const VendorFadeSlide(
              delay: Duration(milliseconds: 50),
              child: _RangeChips(),
            ),

            // ── 3. Search Field ──
            const VendorFadeSlide(
              delay: Duration(milliseconds: 80),
              child: _SearchField(),
            ),

            // ── 4. Outcome & Payment Refinement Filter Chips ──
            const VendorFadeSlide(
              delay: Duration(milliseconds: 100),
              child: _RefineChips(),
            ),
            
            Divider(height: 1, color: context.zc.divider.withValues(alpha: 0.5)),
            
            // ── 5. History List & Summary ──
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
                data: (_) => RefreshIndicator.adaptive(
                  color: context.zc.primary,
                  onRefresh: () => ref.refresh(historyOrdersProvider.future),
                  child: visible.isEmpty
                      ? _EmptyList(hasWindowOrders: orders.value?.isNotEmpty ?? false)
                      : VendorFadeSlide(
                          delay: const Duration(milliseconds: 120),
                          child: _HistoryList(orders: visible),
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

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.lg,
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.xs,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Order History',
                  style: t.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: zc.textStrong,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: ZopiqSpacing.xxs),
                Text(
                  'Review completed and cancelled orders',
                  style: t.bodyMedium?.copyWith(color: zc.textMuted),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(ZopiqSpacing.sm),
            decoration: BoxDecoration(
              color: zc.primary.withValues(alpha: 0.1),
              borderRadius: ZopiqRadii.rMd,
            ),
            child: VendorSvgIcon(
              type: VendorSvgType.historyClock,
              size: 24,
              color: zc.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyList extends ConsumerWidget {
  const _EmptyList({required this.hasWindowOrders});

  final bool hasWindowOrders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;

    return ListView(
      children: <Widget>[
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.12),
        if (hasWindowOrders) ...<Widget>[
          const VendorMessage(
            icon: Icons.filter_alt_off_rounded,
            title: 'Nothing matches these filters',
            body: 'Try a different outcome, payment or search.',
          ),
          const SizedBox(height: ZopiqSpacing.md),
          Center(
            child: OutlinedButton.icon(
              onPressed: () {
                final HistoryFilterController c = ref.read(historyFilterProvider.notifier);
                c.setOutcome(HistoryOutcome.all);
                c.setPayment(HistoryPayment.all);
                c.setQuery('');
              },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reset Filters'),
              style: OutlinedButton.styleFrom(
                foregroundColor: zc.primary,
                side: BorderSide(color: zc.primary.withValues(alpha: 0.5)),
              ),
            ),
          ),
        ] else ...<Widget>[
          const VendorMessage(
            icon: Icons.history_rounded,
            title: 'No orders in this period',
            body: 'Delivered and cancelled orders show up here.',
          ),
        ],
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
    final ZopiqColors zc = context.zc;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.md,
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.xs,
      ),
      child: ZopiqCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: <Widget>[
            Container(
              height: 3,
              decoration: BoxDecoration(
                color: zc.primary,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(ZopiqRadii.lg),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(ZopiqSpacing.md),
              child: Row(
                children: <Widget>[
                  _Stat(label: 'Orders', value: '${s.total}'),
                  const _StatDivider(),
                  _Stat(label: 'Delivered', value: '${s.delivered}', color: zc.veg),
                  const _StatDivider(),
                  _Stat(label: 'Cancelled', value: '${s.cancelled}', color: zc.nonVeg),
                  const _StatDivider(),
                  _Stat(label: 'Gross', value: formatRupees(s.gross), isMoney: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    this.color,
    this.isMoney = false,
  });

  final String label;
  final String value;
  final Color? color;
  final bool isMoney;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Expanded(
      child: Column(
        children: <Widget>[
          if (isMoney)
            ZopiqAnimatedAmount(
              amount: int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
              style: t.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: color ?? zc.textStrong,
              ),
            )
          else
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: color ?? zc.textStrong,
              ),
            ),
          const SizedBox(height: ZopiqSpacing.xxs),
          Text(
            label,
            style: t.bodySmall?.copyWith(
              color: zc.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
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
    color: context.zc.divider.withValues(alpha: 0.5),
  );
}

class _RangeChips extends ConsumerWidget {
  const _RangeChips();

  Future<void> _pickCustom(BuildContext context, WidgetRef ref) async {
    final DateTime now = DateTime.now();
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: context.zc.primary,
            ),
          ),
          child: child!,
        );
      },
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
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: ZopiqSpacing.pageGutter,
          vertical: ZopiqSpacing.xs,
        ),
        children: <Widget>[
          for (final HistoryRange r in HistoryRange.values)
            Padding(
              padding: const EdgeInsets.only(right: ZopiqSpacing.xs),
              child: _Chip(
                label: r.label,
                icon: r == HistoryRange.custom ? Icons.calendar_today_rounded : null,
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

class _RefineChips extends ConsumerWidget {
  const _RefineChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HistoryFilter f = ref.watch(historyFilterProvider);
    final HistoryFilterController c = ref.read(historyFilterProvider.notifier);
    final ZopiqColors zc = context.zc;

    final bool hasActiveFilters = f.outcome != HistoryOutcome.all ||
        f.payment != HistoryPayment.all ||
        f.query.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZopiqSpacing.pageGutter,
        0,
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.xs,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            // Status/Outcome Filter Segment
            for (final HistoryOutcome o in HistoryOutcome.values)
              Padding(
                padding: const EdgeInsets.only(right: ZopiqSpacing.xs),
                child: _Chip(
                  label: o.label,
                  icon: switch (o) {
                    HistoryOutcome.delivered => Icons.check_circle_outline_rounded,
                    HistoryOutcome.cancelled => Icons.cancel_outlined,
                    HistoryOutcome.rejected => Icons.block_rounded,
                    _ => null,
                  },
                  selectedColor: switch (o) {
                    HistoryOutcome.delivered => zc.veg,
                    HistoryOutcome.cancelled => zc.nonVeg,
                    HistoryOutcome.rejected => Colors.orange,
                    _ => zc.primary,
                  },
                  selected: o == f.outcome,
                  onSelected: () => c.setOutcome(o),
                ),
              ),
            
            Container(
              width: 1,
              height: 20,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              color: zc.divider,
            ),

            // Payment Filter Segment
            for (final HistoryPayment p in HistoryPayment.values)
              if (p != HistoryPayment.all)
                Padding(
                  padding: const EdgeInsets.only(left: ZopiqSpacing.xs),
                  child: _Chip(
                    label: p.label,
                    icon: p == HistoryPayment.cash ? Icons.payments_outlined : Icons.credit_card_rounded,
                    selected: p == f.payment,
                    onSelected: () => c.setPayment(
                      p == f.payment ? HistoryPayment.all : p,
                    ),
                  ),
                ),

            if (hasActiveFilters) ...<Widget>[
              const SizedBox(width: ZopiqSpacing.sm),
              GestureDetector(
                onTap: () {
                  c.setOutcome(HistoryOutcome.all);
                  c.setPayment(HistoryPayment.all);
                  c.setQuery('');
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: zc.nonVeg.withValues(alpha: 0.1),
                    borderRadius: ZopiqRadii.rPill,
                    border: Border.all(color: zc.nonVeg.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.close_rounded, size: 14, color: zc.nonVeg),
                      const SizedBox(width: 4),
                      Text(
                        'Reset Filters',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: zc.nonVeg,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

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
        ZopiqSpacing.xxs,
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.xs,
      ),
      child: TextField(
        controller: _controller,
        onChanged: _onChanged,
        textInputAction: TextInputAction.search,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search order ID',
          hintStyle: TextStyle(color: zc.textMuted, fontSize: 13),
          prefixIcon: Icon(Icons.search_rounded, color: zc.primary, size: 20),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    _controller.clear();
                    _debounce?.cancel();
                    ref.read(historyFilterProvider.notifier).setQuery('');
                    setState(() {});
                  },
                ),
          fillColor: zc.primary.withValues(alpha: 0.04),
          filled: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: ZopiqRadii.rPill,
            borderSide: BorderSide(color: zc.divider.withValues(alpha: 0.5)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: ZopiqRadii.rPill,
            borderSide: BorderSide(color: zc.divider.withValues(alpha: 0.5)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: ZopiqRadii.rPill,
            borderSide: BorderSide(color: zc.primary, width: 1.5),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
    this.selectedColor,
  });

  final String label;
  final bool selected;
  final VoidCallback? onSelected;
  final IconData? icon;
  final Color? selectedColor;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    final Color activeThemeColor = selectedColor ?? zc.primary;
    final Color fg = selected ? activeThemeColor : zc.textMuted;
    final Color bg = selected ? activeThemeColor.withValues(alpha: 0.12) : Colors.transparent;
    final Color border = selected ? activeThemeColor.withValues(alpha: 0.4) : zc.divider.withValues(alpha: 0.6);

    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: ZopiqRadii.rPill,
        side: BorderSide(color: border),
      ),
      child: InkWell(
        borderRadius: ZopiqRadii.rPill,
        onTap: onSelected,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 6,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: t.labelMedium?.copyWith(
                  color: fg,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
