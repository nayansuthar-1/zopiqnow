import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

/// The iconic "ADD" control that expands into a −/quantity/+ stepper once the
/// item is in the cart. Presentation-only: quantity and callbacks are supplied
/// by the caller, so it works identically on the menu and in the cart.
class AddToCartControl extends StatelessWidget {
  const AddToCartControl({
    required this.quantity,
    required this.onAdd,
    required this.onIncrement,
    required this.onDecrement,
    this.width = 104,
    this.enabled = true,
    super.key,
  });

  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final double width;

  /// Whether the control accepts taps. False when the restaurant has stopped
  /// taking orders.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final Color surface = Theme.of(context).colorScheme.surface;

    final Widget control = SizedBox(
      width: width,
      height: 36,
      child: quantity == 0
          ? _AddButton(zc: zc, surface: surface, onAdd: onAdd)
          : _Stepper(
              zc: zc,
              quantity: quantity,
              onIncrement: onIncrement,
              onDecrement: onDecrement,
            ),
    );

    if (enabled) return control;
    return Opacity(
      opacity: 0.4,
      child: IgnorePointer(child: control),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({
    required this.zc,
    required this.surface,
    required this.onAdd,
  });

  final ZopiqColors zc;
  final Color surface;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          HapticFeedback.selectionClick();
          onAdd();
        },
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? zc.primary.withValues(alpha: 0.15) : zc.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: zc.primary,
              width: 1.2,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: zc.primary.withValues(alpha: 0.15),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.add_rounded, size: 14, color: zc.primary),
                const SizedBox(width: 2),
                Text(
                  'ADD',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: zc.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.zc,
    required this.quantity,
    required this.onIncrement,
    required this.onDecrement,
  });

  final ZopiqColors zc;
  final int quantity;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: zc.primary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: zc.primary.withValues(alpha: 0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          _StepButton(
            icon: Icons.remove_rounded,
            onTap: () {
              HapticFeedback.selectionClick();
              onDecrement();
            },
          ),
          Text(
            '$quantity',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
          _StepButton(
            icon: Icons.add_rounded,
            onTap: () {
              HapticFeedback.selectionClick();
              onIncrement();
            },
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 20,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Icon(icon, color: Colors.white, size: 16),
      ),
    );
  }
}

