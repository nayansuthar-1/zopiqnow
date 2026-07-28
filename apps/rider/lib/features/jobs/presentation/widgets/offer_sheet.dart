import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_rider/core/widgets/rider_svg_icons.dart';
import 'package:zopiq_rider/features/jobs/domain/entities/job.dart';
import 'package:zopiq_rider/features/jobs/presentation/providers/jobs_providers.dart';

/// The job, offered. Forty-five seconds to say yes or no (0056).
///
/// **Why a sheet and not a card in the list.** An offer is not information, it
/// is a question with a deadline, and a question with a deadline that a rider
/// might scroll past is a question that will be missed. It takes the screen,
/// once, and leaves as soon as it is answered.
///
/// **Why the countdown is drawn from an absolute instant.** [DeliveryOffer]
/// carries `expires_at`, not "seconds left". A phone that was in a pocket for
/// thirty seconds opens this sheet showing fifteen, which is the truth — a timer
/// started at `initState` would show forty-five and then hand the rider a job
/// that was already gone.
///
/// **What happens when it runs out.** The sheet closes itself and says nothing.
/// It is not a failure, it is not the rider's fault, and there is nothing for
/// them to do about it — the dispatcher has already moved on to the next
/// partner. A toast reading "you missed a job" would be a scolding.
class OfferSheet extends ConsumerStatefulWidget {
  const OfferSheet({required this.offer, super.key});

  final DeliveryOffer offer;

  @override
  ConsumerState<OfferSheet> createState() => _OfferSheetState();
}

class _OfferSheetState extends ConsumerState<OfferSheet> {
  Timer? _tick;
  late Duration _left;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _left = widget.offer.remaining(DateTime.now());
    // Every second, and not faster: this drives a number and a ring, and a
    // rider glancing at it cannot read tenths.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final Duration left = widget.offer.remaining(DateTime.now());
      setState(() => _left = left);
      if (left == Duration.zero) _close();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _close() {
    _tick?.cancel();
    if (mounted && Navigator.canPop(context)) Navigator.pop(context);
  }

  Future<void> _accept() async {
    setState(() => _busy = true);
    final String? failure = await ref
        .read(jobsControllerProvider.notifier)
        .acceptOffer(widget.offer.orderId);
    if (!mounted) return;
    setState(() => _busy = false);
    _close();
    if (failure != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure)));
    }
  }

  Future<void> _decline() async {
    // Closed first, then recorded. The rider has decided; making them watch a
    // spinner to be told the platform agrees is thirty seconds of their shift.
    _close();
    await ref
        .read(jobsControllerProvider.notifier)
        .declineOffer(widget.offer.orderId);
  }

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final DeliveryOffer o = widget.offer;

    final int seconds = _left.inSeconds;
    final double window = o.window.inMilliseconds.toDouble();
    final double fraction = window <= 0
        ? 0
        : (_left.inMilliseconds / window).clamp(0.0, 1.0);
    // Amber under fifteen seconds, red under five. The ring is the only thing
    // on this sheet that changes, so it is the only thing that may shout.
    final Color urgency = seconds <= 5
        ? zc.nonVeg
        : seconds <= 15
        ? Colors.amber.shade700
        : zc.primary;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(ZopiqRadii.xl),
          ),
        ),
        padding: const EdgeInsets.all(ZopiqSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                _Countdown(
                  seconds: seconds,
                  fraction: fraction,
                  color: urgency,
                ),
                const SizedBox(width: ZopiqSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'New delivery for you',
                        style: t.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: ZopiqSpacing.xxs),
                      Text(
                        o.isReady
                            ? 'Packed and waiting at the counter'
                            : 'Still cooking — you have time to ride over',
                        style: t.bodySmall?.copyWith(color: zc.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: ZopiqSpacing.lg),

            // The fee, alone and large. It is the one number a rider decides on,
            // and B3's rule is that they see it *before* committing.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(ZopiqSpacing.md),
              decoration: BoxDecoration(
                color: zc.primary.withValues(alpha: 0.08),
                borderRadius: ZopiqRadii.rMd,
                border: Border.all(color: zc.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: <Widget>[
                  Text(
                    '₹${o.riderPay}',
                    style: t.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: zc.primary,
                    ),
                  ),
                  const SizedBox(width: ZopiqSpacing.sm),
                  Expanded(
                    child: Text(
                      o.routeKm == null
                          ? 'for this delivery'
                          : 'for ${_km(o.routeKm!)} km',
                      style: t.bodyMedium?.copyWith(color: zc.textMuted),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: ZopiqSpacing.md),

            _Leg(
              icon: RiderSvgType.restaurant,
              color: zc.primary,
              label: 'Pick up',
              value: o.restaurantName,
              // Null when the platform had no position for this rider — it says
              // nothing rather than inventing a distance.
              trailing: o.toPickupKm == null
                  ? null
                  : '${_km(o.toPickupKm!)} km away',
            ),
            const SizedBox(height: ZopiqSpacing.sm),
            _Leg(
              icon: RiderSvgType.navigationPin,
              color: zc.nonVeg,
              label: 'Drop at',
              value: o.deliverTo,
            ),

            if (o.isCash) ...<Widget>[
              const SizedBox(height: ZopiqSpacing.sm),
              _Leg(
                icon: RiderSvgType.cashCollect,
                color: Colors.amber.shade700,
                label: 'Collect',
                value: '₹${o.total} in cash',
              ),
            ],

            const SizedBox(height: ZopiqSpacing.lg),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _decline,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: zc.textMuted,
                      side: BorderSide(color: zc.divider),
                      padding: const EdgeInsets.symmetric(
                        vertical: ZopiqSpacing.md,
                      ),
                      shape: const RoundedRectangleBorder(
                        borderRadius: ZopiqRadii.rMd,
                      ),
                    ),
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: ZopiqSpacing.md),
                Expanded(
                  flex: 2,
                  child: ZopiqButton(
                    label: 'Accept',
                    variant: ZopiqButtonVariant.cta,
                    isLoading: _busy,
                    onPressed: _busy ? null : _accept,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 4.20 → "4.2", 5.00 → "5". The same trimming [Job.payExplained] does, and
  /// for the same reason: trailing zeros on a screen read at a kerb are noise.
  static String _km(double v) => v == v.roundToDouble()
      ? v.round().toString()
      : v.toStringAsFixed(1);
}

/// The seconds, in a ring that empties.
///
/// Fixed size, so a two-digit number becoming a one-digit one repaints and lays
/// nothing out — the same rule the tracking timeline follows.
class _Countdown extends StatelessWidget {
  const _Countdown({
    required this.seconds,
    required this.fraction,
    required this.color,
  });

  final int seconds;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: fraction,
              strokeWidth: 4,
              backgroundColor: context.zc.divider,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          Text(
            '$seconds',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: color,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// One end of the ride: an icon, what it is, and where.
class _Leg extends StatelessWidget {
  const _Leg({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.trailing,
  });

  final RiderSvgType icon;
  final Color color;
  final String label;
  final String value;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final ZopiqColors zc = context.zc;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(ZopiqSpacing.xs),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: ZopiqRadii.rSm,
          ),
          child: RiderSvgIcon(type: icon, size: 18, color: color),
        ),
        const SizedBox(width: ZopiqSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label.toUpperCase(),
                style: t.labelSmall?.copyWith(
                  color: zc.textMuted,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                value,
                style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        if (trailing != null) ...<Widget>[
          const SizedBox(width: ZopiqSpacing.sm),
          Text(
            trailing!,
            style: t.bodySmall?.copyWith(
              color: zc.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}
