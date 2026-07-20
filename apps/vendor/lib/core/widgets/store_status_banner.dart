import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';
import 'package:zopiq_vendor/features/auth/domain/entities/vendor.dart';
import 'package:zopiq_vendor/features/auth/presentation/providers/auth_providers.dart';

/// The open/closed switch, on Home as well as the queue — an owner opening for
/// the day starts here, not on the worklist. Optimistic, like the queue's: the
/// switch flips first and the write confirms it, because a kitchen must never be
/// made to wait on a round trip to reopen.
class StoreStatusBanner extends ConsumerWidget {
  const StoreStatusBanner({required this.vendor, super.key});

  final Vendor vendor;

  Future<void> _toggle(BuildContext context, WidgetRef ref, bool open) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String? error = await ref
        .read(vendorAuthControllerProvider.notifier)
        .setAcceptingOrders(open);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool open = vendor.acceptingOrders;

    final Color bgColor = open
        ? zc.veg.withValues(alpha: 0.08)
        : zc.nonVeg.withValues(alpha: 0.06);
    final Color borderColor = open
        ? zc.veg.withValues(alpha: 0.20)
        : zc.nonVeg.withValues(alpha: 0.15);
    final Color accent = open ? zc.veg : zc.nonVeg;

    return AnimatedContainer(
      duration: ZopiqDurations.base,
      curve: ZopiqCurves.standard,
      padding: const EdgeInsets.all(ZopiqSpacing.lg),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: ZopiqRadii.rLg,
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        children: <Widget>[
          // Status icon
          AnimatedContainer(
            duration: ZopiqDurations.base,
            curve: ZopiqCurves.standard,
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              open ? Icons.storefront_rounded : Icons.no_meals_rounded,
              color: accent,
              size: 20,
            ),
          ),
          const SizedBox(width: ZopiqSpacing.md),

          // Text + status pill
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    _StatusPill(open: open, accent: accent),
                    const SizedBox(width: ZopiqSpacing.sm),
                    Flexible(
                      child: Text(
                        open ? 'Taking orders' : 'Orders paused',
                        style: t.titleSmall?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: ZopiqSpacing.xxs),
                Text(
                  open
                      ? 'Customers can order from you now.'
                      : 'You won\'t receive new orders until you reopen.',
                  style: t.bodySmall?.copyWith(
                    color: zc.textMuted,
                  ),
                ),
              ],
            ),
          ),

          Switch.adaptive(
            value: open,
            activeTrackColor: zc.veg,
            onChanged: (bool value) => _toggle(context, ref, value),
          ),
        ],
      ),
    );
  }
}

/// The small "LIVE" / "OFFLINE" pill with a breathing dot for the live state.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.open, required this.accent});

  final bool open;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: ZopiqDurations.base,
      curve: ZopiqCurves.standard,
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.sm,
        vertical: ZopiqSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.15),
        borderRadius: ZopiqRadii.rPill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (open) _BreathingDot(color: accent),
          if (open) const SizedBox(width: ZopiqSpacing.xs),
          Text(
            open ? 'LIVE' : 'OFFLINE',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: accent,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

/// A tiny dot that fades in and out, like a heartbeat — says "alive" without
/// saying "look at me". Only runs when the store is live; a static "OFFLINE"
/// pill has no reason to pulse.
class _BreathingDot extends StatefulWidget {
  const _BreathingDot({required this.color});

  final Color color;

  @override
  State<_BreathingDot> createState() => _BreathingDotState();
}

class _BreathingDotState extends State<_BreathingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: ZopiqDurations.breath,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Hold still when motion is reduced — the OS "reduce animations" setting, and
    // the same signal a widget test sets so a perpetual pulse never keeps
    // `pumpAndSettle` from ever settling.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return _dot(1.0);
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) =>
          _dot(0.35 + 0.65 * _controller.value),
    );
  }

  Widget _dot(double opacity) {
    return Opacity(
      opacity: opacity,
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
