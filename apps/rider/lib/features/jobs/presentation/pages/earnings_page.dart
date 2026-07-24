import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_rider/core/widgets/rider_animations.dart';
import 'package:zopiq_rider/core/widgets/rider_svg_icons.dart';
import 'package:zopiq_rider/features/jobs/domain/entities/job.dart';
import 'package:zopiq_rider/features/jobs/presentation/providers/jobs_providers.dart';

/// What the work was worth.
class EarningsPage extends ConsumerWidget {
  const EarningsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final EarningsSummary summary = ref.watch(earningsSummaryProvider);
    final List<Job> done = ref.watch(deliveredJobsProvider);
    final AsyncValue<List<EarningsDay>> days = ref.watch(earningsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Partner Earnings'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: context.zc.primary,
          onRefresh: () async {
            ref
              ..invalidate(earningsProvider)
              ..invalidate(myJobsProvider)
              ..invalidate(payoutsProvider);
            await Future<void>.delayed(const Duration(milliseconds: 400));
          },
          child: days.hasError
              ? const _Message(
                  icon: Icons.cloud_off_rounded,
                  title: 'We couldn\'t load your earnings',
                  body: 'Check your connection and pull to refresh.',
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(ZopiqSpacing.pageGutter),
                  children: <Widget>[
                    RiderFadeSlide(child: _TotalsCard(summary: summary)),
                    const SizedBox(height: ZopiqSpacing.lg),
                    const _Payouts(),
                    Text(
                      'Completed Orders History',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: ZopiqSpacing.sm),
                    if (done.isEmpty)
                      RiderFadeSlide(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: ZopiqSpacing.xl,
                          ),
                          child: Column(
                            children: <Widget>[
                              RiderSvgIcon(
                                type: RiderSvgType.receipt,
                                size: 48,
                                color: context.zc.textMuted,
                              ),
                              const SizedBox(height: ZopiqSpacing.sm),
                              Text(
                                'No completed deliveries yet.',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Delivered jobs will appear here along with itemized pay breakdowns.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: context.zc.textMuted),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ...done.asMap().entries.map(
                            (MapEntry<int, Job> entry) => RiderFadeSlide(
                              delay: Duration(milliseconds: entry.key * 50),
                              child: _DoneJobCard(job: entry.value),
                            ),
                          ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _Payouts extends ConsumerWidget {
  const _Payouts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Payout> payouts = ref
        .watch(payoutsProvider)
        .maybeWhen(
          data: (List<Payout> p) => p,
          orElse: () => const <Payout>[],
        );
    if (payouts.isEmpty) return const SizedBox.shrink();

    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final int owed = payouts
        .where((Payout p) => !p.isPaid)
        .fold(0, (int sum, Payout p) => sum + p.amount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Weekly Payouts',
                style: t.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            if (owed > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: zc.primary.withValues(alpha: 0.12),
                  borderRadius: ZopiqRadii.rPill,
                ),
                child: Text(
                  '₹$owed Processing',
                  style: t.labelSmall?.copyWith(
                    color: zc.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: ZopiqSpacing.xs),
        Text(
          'Payouts are processed automatically every Monday.',
          style: t.bodySmall?.copyWith(color: zc.textMuted),
        ),
        const SizedBox(height: ZopiqSpacing.sm),
        ...payouts.map((Payout p) => _PayoutCard(payout: p)),
        const SizedBox(height: ZopiqSpacing.lg),
      ],
    );
  }
}

class _PayoutCard extends StatelessWidget {
  const _PayoutCard({required this.payout});

  final Payout payout;

  static const List<String> _months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String get _period {
    final DateTime a = payout.periodStart;
    final DateTime b = payout.periodEnd;
    final String left = a.month == b.month
        ? '${a.day}'
        : '${a.day} ${_months[a.month - 1]}';
    return '$left–${b.day} ${_months[b.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final Color surfaceColor = Theme.of(context).colorScheme.surface;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: ZopiqSpacing.sm),
      child: ZopiqCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    _period,
                    style: t.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                ZopiqAnimatedAmount(
                  amount: payout.amount,
                  style: t.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: payout.isPaid ? zc.textStrong : zc.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: ZopiqSpacing.xs),
            Row(
              children: <Widget>[
                RiderSvgIcon(
                  type: RiderSvgType.verifiedShield,
                  size: 16,
                  color: payout.isPaid ? zc.veg : zc.primary,
                ),
                const SizedBox(width: ZopiqSpacing.xs),
                Expanded(
                  child: Text(
                    payout.isPaid ? 'Transfer Completed' : 'Processing Payment',
                    style: t.bodySmall?.copyWith(
                      color: payout.isPaid ? zc.veg : zc.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  payout.deliveryCount == 1
                      ? '1 run'
                      : '${payout.deliveryCount} runs',
                  style: t.bodySmall?.copyWith(color: zc.textMuted),
                ),
              ],
            ),
            if (payout.reference != null) ...<Widget>[
              const SizedBox(height: ZopiqSpacing.xs),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: ZopiqRadii.rSm,
                  border: Border.all(color: zc.divider),
                ),
                child: Text(
                  'Bank Ref (UTR): ${payout.reference}',
                  style: t.labelSmall?.copyWith(
                    color: zc.textMuted,
                    letterSpacing: 0.5,
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

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.summary});

  final EarningsSummary summary;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;

    return Container(
      padding: const EdgeInsets.all(ZopiqSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            zc.primary,
            zc.primary.withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: ZopiqRadii.rLg,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: zc.primary.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _TotalBlock(
              label: 'TODAY\'S EARNINGS',
              amount: summary.todayPay,
              jobs: summary.todayJobs,
              isLight: true,
            ),
          ),
          Container(
            width: 1,
            height: 54,
            color: Colors.white.withValues(alpha: 0.25),
            margin: const EdgeInsets.symmetric(horizontal: ZopiqSpacing.md),
          ),
          Expanded(
            child: _TotalBlock(
              label: 'LAST 7 DAYS',
              amount: summary.weekPay,
              jobs: summary.weekJobs,
              isLight: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalBlock extends StatelessWidget {
  const _TotalBlock({
    required this.label,
    required this.amount,
    required this.jobs,
    required this.isLight,
  });

  final String label;
  final int amount;
  final int jobs;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final Color textColor = isLight ? Colors.white : Colors.black;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: t.labelSmall?.copyWith(
            color: textColor.withValues(alpha: 0.8),
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: ZopiqSpacing.xs),
        ZopiqAnimatedAmount(
          amount: amount,
          style: t.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: textColor,
          ),
        ),
        Text(
          jobs == 1 ? '1 delivery' : '$jobs deliveries',
          style: t.bodySmall?.copyWith(
            color: textColor.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }
}

class _DoneJobCard extends StatelessWidget {
  const _DoneJobCard({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final Color surfaceColor = Theme.of(context).colorScheme.surface;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: ZopiqSpacing.sm),
      child: ZopiqCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Text(
                    job.restaurantName,
                    style: t.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                ZopiqAnimatedAmount(
                  amount: job.riderPay,
                  style: t.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: zc.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: ZopiqSpacing.xs),
            Text(
              job.deliverTo,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: t.bodySmall?.copyWith(color: zc.textMuted),
            ),
            const SizedBox(height: ZopiqSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: ZopiqRadii.rSm,
                border: Border.all(color: zc.divider.withValues(alpha: 0.5)),
              ),
              child: Text(
                job.payExplained,
                style: t.labelSmall?.copyWith(
                  color: zc.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: <Widget>[
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.22),
        Icon(icon, size: 56, color: zc.textMuted),
        const SizedBox(height: ZopiqSpacing.lg),
        Text(title, style: t.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: ZopiqSpacing.xs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: ZopiqSpacing.xl),
          child: Text(
            body,
            style: t.bodyMedium?.copyWith(color: zc.textMuted),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
