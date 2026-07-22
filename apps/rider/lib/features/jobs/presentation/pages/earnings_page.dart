import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_rider/features/jobs/domain/entities/job.dart';
import 'package:zopiq_rider/features/jobs/presentation/providers/jobs_providers.dart';

/// What the work was worth.
///
/// Two numbers at the top because those are the two questions — today, and the
/// week — and under them the jobs themselves, each showing the sum that
/// produced its pay rather than only the result. A rider who can see "₹25 + 4.2
/// km × ₹5" can tell you it is wrong. A rider who can only see "₹46" can only
/// tell you it feels low, which is an argument nobody can win.
class EarningsPage extends ConsumerWidget {
  const EarningsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final EarningsSummary summary = ref.watch(earningsSummaryProvider);
    final List<Job> done = ref.watch(deliveredJobsProvider);
    final AsyncValue<List<EarningsDay>> days = ref.watch(earningsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Earnings')),
      body: SafeArea(
        child: RefreshIndicator(
          color: context.zc.primary,
          onRefresh: () async {
            ref
              ..invalidate(earningsProvider)
              ..invalidate(myJobsProvider);
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
                    _TotalsCard(summary: summary),
                    const SizedBox(height: ZopiqSpacing.lg),
                    Text(
                      'Completed jobs',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: ZopiqSpacing.sm),
                    if (done.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: ZopiqSpacing.xl,
                        ),
                        child: Text(
                          'Nothing delivered yet. Finished jobs show up here '
                          'with what each one paid.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: context.zc.textMuted),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      ...done.map((Job j) => _DoneJobCard(job: j)),
                  ],
                ),
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
    return ZopiqCard(
      child: Row(
        children: <Widget>[
          Expanded(
            child: _Total(
              label: 'Today',
              amount: summary.todayPay,
              jobs: summary.todayJobs,
              emphasis: true,
            ),
          ),
          Container(
            width: 1,
            height: 52,
            color: context.zc.divider,
            margin: const EdgeInsets.symmetric(horizontal: ZopiqSpacing.md),
          ),
          Expanded(
            child: _Total(
              label: 'Last 7 days',
              amount: summary.weekPay,
              jobs: summary.weekJobs,
              emphasis: false,
            ),
          ),
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({
    required this.label,
    required this.amount,
    required this.jobs,
    required this.emphasis,
  });

  final String label;
  final int amount;
  final int jobs;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: t.labelMedium?.copyWith(color: zc.textMuted)),
        const SizedBox(height: ZopiqSpacing.xs),
        Text(
          '₹$amount',
          style: t.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: emphasis ? zc.primary : zc.textStrong,
          ),
        ),
        Text(
          jobs == 1 ? '1 delivery' : '$jobs deliveries',
          style: t.bodySmall?.copyWith(color: zc.textMuted),
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
                    style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  '₹${job.riderPay}',
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
            // The arithmetic, in full. This is the line the screen exists for.
            Text(
              job.payExplained,
              style: t.bodySmall?.copyWith(color: zc.textMuted),
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
