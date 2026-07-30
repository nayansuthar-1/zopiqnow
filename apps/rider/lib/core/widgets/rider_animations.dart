import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

/// Entrance animation for cards and list items with subtle slide and fade.
class RiderFadeSlide extends StatefulWidget {
  const RiderFadeSlide({
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
  State<RiderFadeSlide> createState() => _RiderFadeSlideState();
}

class _RiderFadeSlideState extends State<RiderFadeSlide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

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
      Future<void>.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
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

/// Pulsing badge with glowing background aura for active indicators.
class RiderPulseBadge extends StatefulWidget {
  const RiderPulseBadge({
    required this.child,
    super.key,
    this.glowColor,
    this.enabled = true,
  });

  final Widget child;
  final Color? glowColor;
  final bool enabled;

  @override
  State<RiderPulseBadge> createState() => _RiderPulseBadgeState();
}

class _RiderPulseBadgeState extends State<RiderPulseBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// Whether the platform asks us not to animate (accessibility "reduce motion",
  /// and what `flutter_test` sets so a perpetual `repeat()` doesn't leave
  /// `pumpAndSettle` waiting forever). Resolved in [didChangeDependencies], which
  /// is the earliest place [MediaQuery] is safe to read.
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    // Not started here: whether it should run depends on MediaQuery, which
    // initState cannot read. [didChangeDependencies] decides.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncController();
  }

  @override
  void didUpdateWidget(covariant RiderPulseBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled != oldWidget.enabled) _syncController();
  }

  /// Run the pulse only when it is both wanted and allowed; otherwise sit still
  /// on frame zero. Idempotent, so the repeated calls from the lifecycle hooks
  /// above never stack.
  void _syncController() {
    if (widget.enabled && !_reduceMotion) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // No animation wanted, or none allowed: the child, plain. This is also the
    // path a reduce-motion user sees — the glow is decoration, not information.
    if (!widget.enabled || _reduceMotion) return widget.child;

    final Color glow = widget.glowColor ?? context.zc.primary;

    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        final double scale = 1.0 + (_controller.value * 0.08);
        final double alpha = 0.25 - (_controller.value * 0.15);

        return Transform.scale(
          scale: scale,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: ZopiqRadii.rPill,
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: glow.withValues(alpha: alpha),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: widget.child,
          ),
        );
      },
    );
  }
}

/// High quality PIN digit input field with glowing active boxes and haptic-like feel.
class RiderPinInput extends StatefulWidget {
  const RiderPinInput({
    required this.length,
    required this.onCompleted,
    super.key,
    this.controller,
    this.autofocus = true,
    this.errorText,
  });

  final int length;
  final ValueChanged<String> onCompleted;
  final TextEditingController? controller;
  final bool autofocus;
  final String? errorText;

  @override
  State<RiderPinInput> createState() => _RiderPinInputState();
}

class _RiderPinInputState extends State<RiderPinInput> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  String _value = '';

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _value = _controller.text;

    _controller.addListener(_handleTextChange);
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    }
  }

  /// Brings the keyboard back when the boxes are tapped.
  ///
  /// **Why this is not just `requestFocus`.** Dismissing the keyboard — with the
  /// back gesture, or the system bar — does not move focus. The hidden field is
  /// still the focused node, so `requestFocus` sees nothing to change and
  /// returns without asking the platform for anything, and the rider is left
  /// tapping boxes that are already "focused" with no keyboard in sight and no
  /// way to enter the code. Asking the text input channel directly is what
  /// actually reopens it in that state.
  void _openKeyboard() {
    if (_focusNode.hasFocus) {
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    } else {
      _focusNode.requestFocus();
    }
  }

  void _handleTextChange() {
    setState(() {
      _value = _controller.text;
    });
    if (_value.length == widget.length) {
      widget.onCompleted(_value);
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final Color surfaceColor = Theme.of(context).colorScheme.surface;
    final TextTheme t = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        GestureDetector(
          onTap: _openKeyboard,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            children: <Widget>[
              // Invisible textfield overlay
              Opacity(
                opacity: 0.01,
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(widget.length),
                  ],
                ),
              ),

              // Visual Pin Boxes
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List<Widget>.generate(widget.length, (int i) {
                  final bool isFilled = i < _value.length;
                  final bool isCurrent = i == _value.length;
                  final String char = isFilled ? _value[i] : '';

                  final Color borderColor = widget.errorText != null
                      ? zc.nonVeg
                      : isCurrent
                      ? zc.primary
                      : isFilled
                      ? zc.textStrong.withValues(alpha: 0.4)
                      : zc.divider;

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    width: widget.length == 6 ? 48 : 64,
                    height: widget.length == 6 ? 56 : 68,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? zc.primary.withValues(alpha: 0.06)
                          : surfaceColor,
                      borderRadius: ZopiqRadii.rMd,
                      border: Border.all(
                        color: borderColor,
                        width: isCurrent ? 2 : 1.5,
                      ),
                      boxShadow: isCurrent
                          ? <BoxShadow>[
                              BoxShadow(
                                color: zc.primary.withValues(alpha: 0.15),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      char,
                      style: t.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: zc.textStrong,
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
        if (widget.errorText != null) ...<Widget>[
          const SizedBox(height: ZopiqSpacing.xs),
          Text(
            widget.errorText!,
            style: t.bodySmall?.copyWith(color: zc.nonVeg),
          ),
        ],
      ],
    );
  }
}

/// Step Progress timeline for delivery status (Claimed -> Cooking -> Packed -> Bike -> Delivered).
class RiderStatusTimeline extends StatelessWidget {
  const RiderStatusTimeline({
    required this.isReadyToCollect,
    required this.isCarrying,
    super.key,
  });

  final bool isReadyToCollect;
  final bool isCarrying;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final Color surfaceColor = Theme.of(context).colorScheme.surface;
    final TextTheme t = Theme.of(context).textTheme;

    final int currentStage = isCarrying
        ? 2
        : isReadyToCollect
        ? 1
        : 0;

    final List<_StageInfo> stages = <_StageInfo>[
      const _StageInfo(label: 'Cooking', icon: Icons.restaurant_rounded),
      const _StageInfo(label: 'Packed', icon: Icons.inventory_2_rounded),
      const _StageInfo(label: 'On Bike', icon: Icons.two_wheeler_rounded),
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
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: bgColor,
                  shape: BoxShape.circle,
                  border: isActive
                      ? Border.all(color: zc.primary, width: 2)
                      : null,
                ),
                child: Icon(
                  isPassed ? Icons.check_rounded : info.icon,
                  size: 16,
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
