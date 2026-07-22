import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_rider/features/auth/domain/entities/rider.dart';
import 'package:zopiq_rider/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_rider/features/jobs/domain/entities/job.dart';
import 'package:zopiq_rider/features/jobs/presentation/providers/jobs_providers.dart';
import 'package:zopiq_rider/features/jobs/presentation/widgets/pickup_sheet.dart';

/// The whole app, very nearly.
///
/// A rider with nothing in hand sees the board and only the board — no tabs, no
/// chrome, exactly as in 8b-2. The moment they are carrying something the screen
/// grows a choice, because stacked deliveries made the old rule untenable.
///
/// That old rule was: the board is *replaced*, never pushed aside, since a board
/// of other people's jobs under a job in hand is an invitation to do the wrong
/// one. The instinct still holds — which is why the run is what opens, and the
/// board is a deliberate second tap rather than something sitting underneath.
/// But a rider batching three orders from one street has to be able to reach the
/// board while holding the first, and hiding it made that impossible.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  /// Only ever true by an explicit tap. A rider who finishes their last job
  /// falls back to the board because the run is empty, not because of this.
  bool _wantBoard = false;

  @override
  Widget build(BuildContext context) {
    final Rider? rider = ref.watch(riderProvider);
    final List<Job> run = ref.watch(activeJobsProvider);
    final bool showBoard = run.isEmpty || _wantBoard;

    return Scaffold(
      // Sign-out moved to Profile when the shell arrived: an unlabelled icon in
      // the corner of the busiest screen is one mis-tap from ending a shift.
      appBar: AppBar(
        title: Text(showBoard ? 'Available jobs' : 'Your run'),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // No switch at all until there is something to switch between. A
            // free rider's screen is exactly what it always was.
            if (run.isNotEmpty)
              _RunBoardSwitch(
                runCount: run.length,
                showingBoard: showBoard,
                onChanged: (bool board) => setState(() => _wantBoard = board),
              ),
            Expanded(
              child: RefreshIndicator(
                color: context.zc.primary,
                onRefresh: () async {
                  ref
                    ..invalidate(boardProvider)
                    ..invalidate(myJobsProvider);
                  await Future<void>.delayed(const Duration(milliseconds: 400));
                },
                child: showBoard
                    ? _BoardBody(riderName: rider?.name ?? '')
                    : _RunBody(run: run),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two segments, and the run's count on it because that is the number a rider
/// glancing at their phone actually wants.
class _RunBoardSwitch extends StatelessWidget {
  const _RunBoardSwitch({
    required this.runCount,
    required this.showingBoard,
    required this.onChanged,
  });

  final int runCount;
  final bool showingBoard;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.sm,
        ZopiqSpacing.pageGutter,
        0,
      ),
      child: SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: <ButtonSegment<bool>>[
          ButtonSegment<bool>(
            value: false,
            label: Text(runCount == 1 ? 'Your run · 1' : 'Your run · $runCount'),
          ),
          const ButtonSegment<bool>(value: true, label: Text('Board')),
        ],
        selected: <bool>{showingBoard},
        onSelectionChanged: (Set<bool> s) => onChanged(s.first),
      ),
    );
  }
}

/// The jobs in hand, in the order [activeJobsProvider] put them.
class _RunBody extends StatelessWidget {
  const _RunBody({required this.run});

  final List<Job> run;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(ZopiqSpacing.pageGutter),
      itemCount: run.length,
      // Keyed by order id: without it, finishing the second of three jobs would
      // hand the third's state to the card that used to be the second's.
      itemBuilder: (BuildContext context, int i) =>
          _RunJobCard(key: ValueKey<String>(run[i].orderId), job: run[i]),
    );
  }
}

/// What is going begging.
///
/// Stateful only so the board can re-ask on a timer. The widget's life is
/// exactly the right life for that: this is built when the rider has no job, so
/// polling starts when there is a board to poll and stops the moment they take
/// something — no separate "should I be running" flag to get out of step.
class _BoardBody extends ConsumerStatefulWidget {
  const _BoardBody({required this.riderName});

  final String riderName;

  @override
  ConsumerState<_BoardBody> createState() => _BoardBodyState();
}

class _BoardBodyState extends ConsumerState<_BoardBody>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// A phone in a pocket is not a rider reading the board. Polling through it
  /// spends their battery on jobs nobody is looking at, and the first thing they
  /// see on unlocking is a fresh fetch anyway.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(boardProvider);
      _start();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _start() {
    _timer?.cancel();
    final Duration? every = ref.read(boardPollIntervalProvider);
    if (every == null) return;
    _timer = Timer.periodic(every, (_) {
      // `ref.invalidate` on a disposed ref throws; the guard is cheaper than
      // reasoning about whether cancel always wins the race with a pending tick.
      if (mounted) ref.invalidate(boardProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final String riderName = widget.riderName;
    final AsyncValue<List<JobOffer>> board = ref.watch(boardProvider);

    return board.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object _, StackTrace _) => const _Message(
        icon: Icons.cloud_off_rounded,
        title: 'We couldn\'t load jobs',
        body: 'Check your connection and pull to refresh.',
      ),
      data: (List<JobOffer> offers) {
        if (offers.isEmpty) {
          return _Message(
            icon: Icons.check_circle_outline_rounded,
            title: 'Nothing waiting',
            body: riderName.isEmpty
                ? 'New jobs will show up here.'
                : 'Nothing to pick up right now, $riderName. '
                      'Pull down to check again.',
          );
        }
        return ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.sm),
          itemCount: offers.length,
          itemBuilder: (BuildContext context, int i) =>
              _OfferCard(offer: offers[i]),
        );
      },
    );
  }
}

class _OfferCard extends ConsumerStatefulWidget {
  const _OfferCard({required this.offer});

  final JobOffer offer;

  @override
  ConsumerState<_OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends ConsumerState<_OfferCard> {
  bool _busy = false;

  Future<void> _claim() async {
    setState(() => _busy = true);
    final String? failure = await ref
        .read(jobsControllerProvider.notifier)
        .claim(widget.offer.orderId);
    if (!mounted) return;
    setState(() => _busy = false);
    // Losing the race is the common case in a busy hour, not an error worth a
    // dialog. The list behind this has already refreshed the job away.
    if (failure != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final JobOffer o = widget.offer;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.pageGutter,
        vertical: ZopiqSpacing.xs,
      ),
      child: ZopiqCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    o.restaurantName,
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (o.isReady)
                  _Pill(label: 'Packed', color: zc.veg)
                else
                  _Pill(label: 'Cooking', color: zc.textMuted),
              ],
            ),
            const SizedBox(height: ZopiqSpacing.sm),
            _Line(icon: Icons.location_on_rounded, text: o.deliverTo),
            const SizedBox(height: ZopiqSpacing.xs),
            _Line(
              icon: o.isCash
                  ? Icons.payments_outlined
                  : Icons.check_circle_outline_rounded,
              text: o.isCash
                  ? 'Collect ₹${o.total} in cash'
                  : 'Paid online · ₹${o.total}',
              emphasis: o.isCash,
            ),
            const SizedBox(height: ZopiqSpacing.md),
            ZopiqButton(
              label: 'Take this job',
              isLoading: _busy,
              onPressed: _busy ? null : _claim,
            ),
          ],
        ),
      ),
    );
  }
}

/// One job in the run, with its own buttons.
///
/// Each card owns its own `_busy` flag rather than the screen owning one. With a
/// single job that distinction did not exist; with three it is the difference
/// between "the job I tapped is working" and every button on the screen going
/// dead because one of them is.
class _RunJobCard extends ConsumerStatefulWidget {
  const _RunJobCard({super.key, required this.job});

  final Job job;

  @override
  ConsumerState<_RunJobCard> createState() => _RunJobCardState();
}

class _RunJobCardState extends ConsumerState<_RunJobCard> {
  bool _busy = false;

  Future<void> _run(Future<String?> Function() write) async {
    setState(() => _busy = true);
    final String? failure = await write();
    if (!mounted) return;
    setState(() => _busy = false);
    if (failure != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure)));
    }
  }

  Future<void> _pickup() async {
    final String? otp = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PickupSheet(restaurantName: widget.job.restaurantName),
    );
    if (otp == null) return;
    await _run(
      () => ref
          .read(jobsControllerProvider.notifier)
          .confirmPickup(orderId: widget.job.orderId, otp: otp),
    );
  }

  Future<void> _deliver() async {
    final bool ok =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext c) => AlertDialog(
            title: const Text('Delivered?'),
            content: Text(
              widget.job.isCash
                  ? 'Make sure you have collected ₹${widget.job.total} in cash.'
                  : 'This ends the order.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Not yet'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Delivered'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    await _run(
      () => ref
          .read(jobsControllerProvider.notifier)
          .confirmDelivered(widget.job.orderId),
    );
  }

  Future<void> _abandon() async {
    final bool ok =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext c) => AlertDialog(
            title: const Text('Drop this job?'),
            content: const Text(
              'It goes back on the board for another partner.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Keep it'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, true),
                style: TextButton.styleFrom(foregroundColor: c.zc.nonVeg),
                child: const Text('Drop it'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    await _run(
      () => ref
          .read(jobsControllerProvider.notifier)
          .abandon(widget.job.orderId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final Job job = widget.job;

    return Padding(
      padding: const EdgeInsets.only(bottom: ZopiqSpacing.md),
      child: ZopiqCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    job.isCarrying ? 'Deliver to' : 'Collect from',
                    style: t.labelMedium?.copyWith(color: zc.textMuted),
                  ),
                ),
                // What this job is waiting on, in two words. With one job the
                // button said it; with three, a rider scanning the list needs
                // to see it without reading to the bottom of every card.
                _Pill(
                  label: job.isCarrying
                      ? 'On the bike'
                      : job.isReadyToCollect
                      ? 'Packed'
                      : 'Cooking',
                  color: job.isCarrying
                      ? zc.primary
                      : job.isReadyToCollect
                      ? zc.veg
                      : zc.textMuted,
                ),
              ],
            ),
            const SizedBox(height: ZopiqSpacing.xs),
            Text(
              job.isCarrying ? job.deliverTo : job.restaurantName,
              style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: ZopiqSpacing.md),
            Divider(height: 1, color: zc.divider),
            const SizedBox(height: ZopiqSpacing.md),
            _Line(icon: Icons.receipt_long_rounded, text: job.orderId),
            const SizedBox(height: ZopiqSpacing.xs),
            // The customer's number arrives only once the job is theirs — the
            // board never carries it.
            _Line(icon: Icons.phone_rounded, text: job.customerPhone),
            const SizedBox(height: ZopiqSpacing.xs),
            _Line(
              icon: job.isCash
                  ? Icons.payments_outlined
                  : Icons.check_circle_outline_rounded,
              text: job.isCash
                  ? 'Collect ₹${job.total} in cash'
                  : 'Paid online · ₹${job.total}',
              emphasis: job.isCash,
            ),
            const SizedBox(height: ZopiqSpacing.md),

            if (job.isCarrying)
              ZopiqButton(
                label: 'Mark delivered',
                variant: ZopiqButtonVariant.cta,
                isLoading: _busy,
                onPressed: _busy ? null : _deliver,
              )
            else ...<Widget>[
              // Until the kitchen says packed there is no code to type, because
              // there is nothing on the counter yet. Saying so is kinder than a
              // button that fails.
              ZopiqButton(
                label: job.isReadyToCollect
                    ? 'Enter pickup code'
                    : 'Not packed yet',
                variant: ZopiqButtonVariant.cta,
                isLoading: _busy,
                onPressed: (_busy || !job.isReadyToCollect) ? null : _pickup,
              ),
              const SizedBox(height: ZopiqSpacing.sm),
              ZopiqButton(
                label: 'Drop this job',
                variant: ZopiqButtonVariant.outline,
                onPressed: _busy ? null : _abandon,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text, this.emphasis = false});

  final IconData icon;
  final String text;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 18, color: emphasis ? zc.primary : zc.textMuted),
        const SizedBox(width: ZopiqSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: t.bodyMedium?.copyWith(
              color: emphasis ? zc.textStrong : zc.textMuted,
              fontWeight: emphasis ? FontWeight.w700 : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: ZopiqRadii.rPill,
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
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
    // A ListView, not a Column: pull-to-refresh needs something scrollable, and
    // "nothing waiting" is exactly the screen a rider pulls on most.
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
