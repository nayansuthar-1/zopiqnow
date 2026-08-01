import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

/// Entrance animation for vendor order tickets and menu items.
class VendorFadeSlide extends StatefulWidget {
  const VendorFadeSlide({
    required this.child,
    super.key,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 350),
    this.offsetY = 16.0,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offsetY;

  @override
  State<VendorFadeSlide> createState() => _VendorFadeSlideState();
}

class _VendorFadeSlideState extends State<VendorFadeSlide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  Timer? _startTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);

    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: Offset(0, widget.offsetY / 100),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      // Held so dispose can cancel it: an uncancelled delay outlives the tree
      // and leaves a pending timer behind.
      _startTimer = Timer(widget.delay, _controller.forward);
    }
  }

  @override
  void dispose() {
    _startTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// Step Progress timeline for kitchen order lifecycle (New Order → Cooking → Ready).
class VendorStatusTimeline extends StatelessWidget {
  const VendorStatusTimeline({
    required this.status,
    super.key,
  });

  final String status;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final Color surfaceColor = Theme.of(context).colorScheme.surface;
    final TextTheme t = Theme.of(context).textTheme;

    // Stages: 0: New Order, 1: Cooking / Preparing, 2: Ready for Pickup / Delivered
    int currentStage = 0;
    if (status == 'preparing' || status == 'accepted') {
      currentStage = 1;
    } else if (status == 'ready_for_pickup' || status == 'delivered' || status == 'completed') {
      currentStage = 2;
    }

    final List<_StageInfo> stages = <_StageInfo>[
      const _StageInfo(label: 'New Order', icon: Icons.receipt_long_rounded),
      const _StageInfo(label: 'Cooking', icon: Icons.soup_kitchen_rounded),
      const _StageInfo(label: 'Ready', icon: Icons.inventory_2_rounded),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.md,
        vertical: ZopiqSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: ZopiqRadii.rMd,
        border: Border.all(color: zc.divider.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: List<Widget>.generate(stages.length * 2 - 1, (int index) {
          if (index.isOdd) {
            final int step = index ~/ 2;
            final bool isPassed = currentStage > step;
            return Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 3,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: isPassed ? zc.primary : zc.divider,
                  borderRadius: ZopiqRadii.rPill,
                ),
              ),
            );
          }

          final int step = index ~/ 2;
          final bool isActive = currentStage == step;
          final bool isPassed = currentStage > step;
          final _StageInfo info = stages[step];

          final Color iconColor = isActive
              ? zc.primary
              : isPassed
              ? zc.veg
              : zc.textMuted;

          final Color bgColor = isActive
              ? zc.primary.withValues(alpha: 0.15)
              : isPassed
              ? zc.veg.withValues(alpha: 0.12)
              : zc.divider.withValues(alpha: 0.3);

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: bgColor,
                  shape: BoxShape.circle,
                  border: isActive
                      ? Border.all(color: zc.primary, width: 2)
                      : null,
                ),
                child: Icon(
                  isPassed ? Icons.check_rounded : info.icon,
                  size: 15,
                  color: iconColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                info.label,
                style: t.labelSmall?.copyWith(
                  color: isActive
                      ? zc.primary
                      : isPassed
                      ? zc.textStrong
                      : zc.textMuted,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                  fontSize: 10,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _StageInfo {
  const _StageInfo({required this.label, required this.icon});
  final String label;
  final IconData icon;
}
