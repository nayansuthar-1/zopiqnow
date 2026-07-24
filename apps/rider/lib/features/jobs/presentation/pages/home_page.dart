import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_rider/core/launcher.dart';
import 'package:zopiq_rider/core/widgets/rider_animations.dart';
import 'package:zopiq_rider/core/widgets/rider_svg_icons.dart';
import 'package:zopiq_rider/features/auth/domain/entities/rider.dart';
import 'package:zopiq_rider/features/auth/presentation/providers/auth_providers.dart';
import 'package:zopiq_rider/features/jobs/domain/entities/job.dart';
import 'package:zopiq_rider/features/jobs/presentation/providers/jobs_providers.dart';
import 'package:zopiq_rider/features/jobs/presentation/widgets/pickup_sheet.dart';
import 'package:zopiq_rider/features/notifications/presentation/widgets/notification_bell.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  bool _wantBoard = false;

  @override
  Widget build(BuildContext context) {
    final Rider? rider = ref.watch(riderProvider);
    final List<Job> run = ref.watch(activeJobsProvider);
    final bool showBoard = run.isEmpty || _wantBoard;
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 70,
        actions: const <Widget>[
          RiderNotificationBell(),
          SizedBox(width: ZopiqSpacing.xs),
        ],
        title: Row(
          children: <Widget>[
            CircleAvatar(
              radius: 20,
              backgroundColor: zc.primary.withValues(alpha: 0.15),
              child: Text(
                rider?.name.isNotEmpty ?? false
                    ? rider!.name[0].toUpperCase()
                    : 'R',
                style: t.titleMedium?.copyWith(
                  color: zc.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: ZopiqSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    rider?.name.isNotEmpty ?? false
                        ? 'Hi, ${rider!.name}'
                        : 'Delivery Partner',
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const _DutyToggle(),
                ],
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
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
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: showBoard
                      ? _BoardBody(
                          key: const ValueKey<String>('board_body'),
                          riderName: rider?.name ?? '',
                        )
                      : _RunBody(
                          key: const ValueKey<String>('run_body'),
                          run: run,
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

/// The line under the rider's name, which used to say `ON DUTY • Active Fleet`
/// no matter what was true. It is now the shift itself (0049), and tapping it
/// starts or ends one.
///
/// A tap rather than a `Switch`: this sits inside an app-bar title, and a switch
/// there is a target the size of a thumbnail beside a scrolling list. It is also
/// **not optimistic** — the database refuses to end a shift while the rider is
/// carrying anything, and a badge that flips to OFF and then back has already
/// told somebody they were finished for the day.
class _DutyToggle extends ConsumerStatefulWidget {
  const _DutyToggle();

  @override
  ConsumerState<_DutyToggle> createState() => _DutyToggleState();
}

class _DutyToggleState extends ConsumerState<_DutyToggle> {
  bool _busy = false;

  Future<void> _toggle(bool online) async {
    setState(() => _busy = true);
    final String? failure = await ref
        .read(jobsControllerProvider.notifier)
        .setOnline(online);
    if (!mounted) return;
    setState(() => _busy = false);
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

    // While the answer is still in flight, say nothing rather than guess. The
    // wrong guess here is the expensive one: "ON DUTY" over a rider the board is
    // quietly refusing.
    final bool? online = ref
        .watch(riderOnlineProvider)
        .maybeWhen(data: (bool v) => v, orElse: () => null);

    final Color color = online ?? false ? zc.veg : zc.textMuted;
    final String label = switch (online) {
      null => 'Checking your shift…',
      true => 'ON DUTY • Tap to go offline',
      false => 'OFF DUTY • Tap to go online',
    };

    return InkWell(
      onTap: (online == null || _busy) ? null : () => _toggle(!online),
      borderRadius: ZopiqRadii.rPill,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            RiderPulseBadge(
              glowColor: color,
              // Nothing pulses for a rider who is off shift. The animation is
              // the "we are looking for work for you" signal, and running it
              // while the board is empty by the rider's own choice is a lie
              // told with motion.
              enabled: online ?? false,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: t.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
    final ZopiqColors zc = context.zc;
    final Color surfaceColor = Theme.of(context).colorScheme.surface;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.xs,
        ZopiqSpacing.pageGutter,
        ZopiqSpacing.sm,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: ZopiqRadii.rPill,
          border: Border.all(color: zc.divider),
        ),
        child: SegmentedButton<bool>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            backgroundColor: Colors.transparent,
            selectedBackgroundColor: zc.primary,
            selectedForegroundColor: Colors.white,
            side: BorderSide.none,
            shape: RoundedRectangleBorder(borderRadius: ZopiqRadii.rPill),
          ),
          segments: <ButtonSegment<bool>>[
            ButtonSegment<bool>(
              value: false,
              label: Text(
                runCount == 1 ? 'Your Run (1 Active)' : 'Your Run ($runCount Active)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const ButtonSegment<bool>(
              value: true,
              label: Text(
                'Available Board',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
          selected: <bool>{showingBoard},
          onSelectionChanged: (Set<bool> s) => onChanged(s.first),
        ),
      ),
    );
  }
}

class _RunBody extends StatelessWidget {
  const _RunBody({super.key, required this.run});

  final List<Job> run;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(ZopiqSpacing.pageGutter),
      itemCount: run.length,
      itemBuilder: (BuildContext context, int i) => RiderFadeSlide(
        delay: Duration(milliseconds: i * 80),
        child: _RunJobCard(
          key: ValueKey<String>(run[i].orderId),
          job: run[i],
        ),
      ),
    );
  }
}

class _BoardBody extends ConsumerStatefulWidget {
  const _BoardBody({super.key, required this.riderName});

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
      if (mounted) ref.invalidate(boardProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final String riderName = widget.riderName;
    final AsyncValue<List<JobOffer>> board = ref.watch(boardProvider);

    return board.when(
      loading: () => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            CircularProgressIndicator(color: context.zc.primary),
            const SizedBox(height: ZopiqSpacing.md),
            Text(
              'Scanning live order board...',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.zc.textMuted,
                  ),
            ),
          ],
        ),
      ),
      error: (Object _, StackTrace _) => const _Message(
        icon: Icons.cloud_off_rounded,
        title: 'Connection Issue',
        body: 'We couldn\'t refresh available jobs. Pull down to try again.',
      ),
      data: (List<JobOffer> offers) {
        if (offers.isEmpty) {
          return _RadarEmptyState(riderName: riderName);
        }
        return ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: ZopiqSpacing.sm),
          itemCount: offers.length,
          itemBuilder: (BuildContext context, int i) => RiderFadeSlide(
            delay: Duration(milliseconds: i * 60),
            child: _OfferCard(offer: offers[i]),
          ),
        );
      },
    );
  }
}

class _RadarEmptyState extends StatelessWidget {
  const _RadarEmptyState({required this.riderName});

  final String riderName;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: <Widget>[
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.12),
        Center(
          child: RiderPulseBadge(
            glowColor: zc.primary,
            enabled: true,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: zc.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
                border: Border.all(
                  color: zc.primary.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: Center(
                child: RiderSvgIcon(
                  type: RiderSvgType.radarScanner,
                  size: 48,
                  color: zc.primary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: ZopiqSpacing.xl),
        Text(
          'Scanning for New Orders',
          style: t.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: ZopiqSpacing.xs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: ZopiqSpacing.xl),
          child: Text(
            riderName.isEmpty
                ? 'Stay nearby partner hubs. New order assignments will pop up here in real-time.'
                : 'No unassigned orders right now, $riderName. Stay tuned — new jobs pop up automatically.',
            style: t.bodyMedium?.copyWith(color: zc.textMuted),
            textAlign: TextAlign.center,
          ),
        ),
      ],
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
                Container(
                  padding: const EdgeInsets.all(ZopiqSpacing.xs),
                  decoration: BoxDecoration(
                    color: zc.primary.withValues(alpha: 0.1),
                    borderRadius: ZopiqRadii.rSm,
                  ),
                  child: RiderSvgIcon(
                    type: RiderSvgType.restaurant,
                    size: 20,
                    color: zc.primary,
                  ),
                ),
                const SizedBox(width: ZopiqSpacing.sm),
                Expanded(
                  child: Text(
                    o.restaurantName,
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                _StatusBadge(
                  label: o.isReady ? 'Packed & Ready' : 'Cooking in Kitchen',
                  color: o.isReady ? zc.veg : zc.textMuted,
                  isReady: o.isReady,
                ),
              ],
            ),
            const SizedBox(height: ZopiqSpacing.md),

            // Target Delivery Location
            _SvgInfoRow(
              svgType: RiderSvgType.navigationPin,
              iconColor: zc.nonVeg,
              text: o.deliverTo,
              bold: true,
            ),
            const SizedBox(height: ZopiqSpacing.xs),

            // Cash or Online payment badge
            _SvgInfoRow(
              svgType: o.isCash
                  ? RiderSvgType.cashCollect
                  : RiderSvgType.verifiedShield,
              iconColor: o.isCash ? Colors.amber.shade700 : zc.veg,
              text: o.isCash
                  ? 'Collect Cash: ₹${o.total}'
                  : 'Prepaid Online • ₹${o.total}',
              emphasis: o.isCash,
            ),

            const SizedBox(height: ZopiqSpacing.lg),

            ZopiqButton(
              label: 'Claim & Accept Job',
              variant: ZopiqButtonVariant.cta,
              isLoading: _busy,
              onPressed: _busy ? null : _claim,
            ),
          ],
        ),
      ),
    );
  }
}

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

  Future<void> _navigate() async {
    final Job job = widget.job;
    final bool ok = await ref.read(launcherProvider).navigate(
          lat: job.targetLat,
          lng: job.targetLng,
          label: job.targetLabel,
        );
    if (!ok) _say('No maps app could open that address.');
  }

  Future<void> _call() async {
    final bool ok =
        await ref.read(launcherProvider).dial(widget.job.customerPhone);
    if (!ok) _say('This phone can\'t make calls.');
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickup() async {
    final String? otp = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PickupSheet(restaurantName: widget.job.restaurantName),
    );
    if (otp == null) return;
    await _run(
      () => ref
          .read(jobsControllerProvider.notifier)
          .confirmPickup(orderId: widget.job.orderId, otp: otp),
    );
  }

  Future<void> _arriveAtRestaurant() => _run(
    () => ref
        .read(jobsControllerProvider.notifier)
        .arriveAtRestaurant(widget.job.orderId),
  );

  Future<void> _arriveAtCustomer() => _run(
    () => ref
        .read(jobsControllerProvider.notifier)
        .arriveAtCustomer(widget.job.orderId),
  );

  /// No "are you sure?" any more — the customer's four digits *are* the
  /// confirmation, and asking twice would be asking a rider at a doorstep to
  /// read two screens.
  Future<void> _deliver() async {
    final String? otp = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DeliverySheet(
        deliverTo: widget.job.deliverTo,
        cashToCollect: widget.job.isCash ? widget.job.total : null,
      ),
    );
    if (otp == null) return;
    await _run(
      () => ref
          .read(jobsControllerProvider.notifier)
          .confirmDelivered(orderId: widget.job.orderId, otp: otp),
    );
  }

  Future<void> _abandon() async {
    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext c) => AlertDialog(
            title: const Text('Drop this Job?'),
            content: const Text(
              'This job will be returned to the active board for another partner rider.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Keep Job'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, true),
                style: TextButton.styleFrom(foregroundColor: c.zc.nonVeg),
                child: const Text('Drop Job'),
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
            // Timeline progress bar
            RiderStatusTimeline(
              isReadyToCollect: job.isReadyToCollect,
              isCarrying: job.isCarrying,
            ),
            const SizedBox(height: ZopiqSpacing.md),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        job.isCarrying ? 'DELIVER TO' : 'PICK UP FROM',
                        style: t.labelSmall?.copyWith(
                          color: zc.primary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        job.isCarrying ? job.deliverTo : job.restaurantName,
                        style: t.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ZopiqSpacing.sm,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: job.isCarrying
                        ? zc.primary.withValues(alpha: 0.12)
                        : job.isReadyToCollect
                        ? zc.veg.withValues(alpha: 0.12)
                        : zc.divider.withValues(alpha: 0.4),
                    borderRadius: ZopiqRadii.rPill,
                  ),
                  child: Text(
                    switch (job.step) {
                      JobStep.rideToRestaurant => job.isReadyToCollect
                          ? 'Ready'
                          : 'Cooking',
                      JobStep.collect => job.isReadyToCollect
                          ? 'At counter'
                          : 'Waiting',
                      JobStep.rideToCustomer => 'On Bike',
                      JobStep.handOver => 'At the door',
                      JobStep.done => 'Done',
                    },
                    style: t.labelSmall?.copyWith(
                      color: job.isCarrying
                          ? zc.primary
                          : job.isReadyToCollect
                          ? zc.veg
                          : zc.textMuted,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: ZopiqSpacing.md),
            Divider(height: 1, color: zc.divider.withValues(alpha: 0.5)),
            const SizedBox(height: ZopiqSpacing.md),

            // Order details grid
            _SvgInfoRow(
              svgType: RiderSvgType.receipt,
              iconColor: zc.textMuted,
              text: 'Order #${job.orderId.substring(0, job.orderId.length > 8 ? 8 : job.orderId.length).toUpperCase()}',
            ),
            if (job.customerPhone.isNotEmpty) ...<Widget>[
              const SizedBox(height: ZopiqSpacing.xs),
              _SvgInfoRow(
                svgType: RiderSvgType.phoneCall,
                iconColor: zc.textMuted,
                text: job.customerPhone,
              ),
            ],
            const SizedBox(height: ZopiqSpacing.xs),
            _SvgInfoRow(
              svgType: job.isCash
                  ? RiderSvgType.cashCollect
                  : RiderSvgType.verifiedShield,
              iconColor: job.isCash ? Colors.amber.shade700 : zc.veg,
              text: job.isCash
                  ? 'Collect Cash: ₹${job.total}'
                  : 'Paid Online • ₹${job.total}',
              emphasis: job.isCash,
            ),

            const SizedBox(height: ZopiqSpacing.lg),

            // Map and Call Action Buttons
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _navigate,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: ZopiqRadii.rMd,
                      ),
                    ),
                    icon: RiderSvgIcon(
                      type: RiderSvgType.navigationPin,
                      size: 18,
                      color: zc.primary,
                    ),
                    label: Text('Navigate', style: TextStyle(color: zc.primary)),
                  ),
                ),
                const SizedBox(width: ZopiqSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: job.customerPhone.isEmpty ? null : _call,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: ZopiqRadii.rMd,
                      ),
                    ),
                    icon: RiderSvgIcon(
                      type: RiderSvgType.phoneCall,
                      size: 18,
                      color: zc.primary,
                    ),
                    label: Text('Call Customer', style: TextStyle(color: zc.primary)),
                  ),
                ),
              ],
            ),

            const SizedBox(height: ZopiqSpacing.md),

            // The one thing to do next. Driven by `job.step`, which is derived
            // from the state Postgres is actually in — so the button on screen
            // is always the call the database will accept, and never the one it
            // is about to refuse.
            switch (job.step) {
              JobStep.rideToRestaurant => ZopiqButton(
                label: 'I\'ve Arrived at the Restaurant',
                variant: ZopiqButtonVariant.cta,
                isLoading: _busy,
                onPressed: _busy ? null : _arriveAtRestaurant,
              ),
              // Arriving early is the normal case, so this is the one button
              // that can sit disabled: the rider is at the counter watching the
              // kitchen, and "Order Still Cooking" is the honest label for it.
              JobStep.collect => ZopiqButton(
                label: job.isReadyToCollect
                    ? 'Enter Pickup Code'
                    : 'Order Still Cooking...',
                variant: ZopiqButtonVariant.cta,
                isLoading: _busy,
                onPressed: (_busy || !job.isReadyToCollect) ? null : _pickup,
              ),
              JobStep.rideToCustomer => ZopiqButton(
                label: 'I\'ve Arrived at the Customer',
                variant: ZopiqButtonVariant.cta,
                isLoading: _busy,
                onPressed: _busy ? null : _arriveAtCustomer,
              ),
              JobStep.handOver => ZopiqButton(
                label: 'Enter Delivery Code',
                variant: ZopiqButtonVariant.cta,
                isLoading: _busy,
                onPressed: _busy ? null : _deliver,
              ),
              JobStep.done => const SizedBox.shrink(),
            },

            // Dropping stays available right up to pickup and not after — once
            // the food is on the bike, walking away is a support conversation.
            if (job.state.isCollecting) ...<Widget>[
              const SizedBox(height: ZopiqSpacing.sm),
              Center(
                child: TextButton(
                  onPressed: _busy ? null : _abandon,
                  child: Text(
                    'Drop this job',
                    style: t.labelMedium?.copyWith(color: zc.nonVeg),
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

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.color,
    required this.isReady,
  });

  final String label;
  final Color color;
  final bool isReady;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: ZopiqRadii.rPill,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (isReady)
            RiderPulseBadge(
              glowColor: color,
              enabled: true,
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            )
          else
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }
}

class _SvgInfoRow extends StatelessWidget {
  const _SvgInfoRow({
    required this.svgType,
    required this.text,
    this.iconColor,
    this.bold = false,
    this.emphasis = false,
  });

  final RiderSvgType svgType;
  final String text;
  final Color? iconColor;
  final bool bold;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Row(
      children: <Widget>[
        RiderSvgIcon(
          type: svgType,
          size: 18,
          color: iconColor ?? zc.textMuted,
        ),
        const SizedBox(width: ZopiqSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: t.bodyMedium?.copyWith(
              color: emphasis ? zc.textStrong : zc.textMuted,
              fontWeight: bold || emphasis ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
  });

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
