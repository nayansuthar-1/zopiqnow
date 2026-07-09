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
    super.key,
  });

  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final double width;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final Color surface = Theme.of(context).colorScheme.surface;

    return SizedBox(
      width: width,
      height: 38,
      child: quantity == 0
          ? _AddButton(zc: zc, surface: surface, onAdd: onAdd)
          : _Stepper(
              zc: zc,
              quantity: quantity,
              onIncrement: onIncrement,
              onDecrement: onDecrement,
            ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.zc, required this.surface, required this.onAdd});

  final ZopiqColors zc;
  final Color surface;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: surface,
      borderRadius: ZopiqRadii.rSm,
      child: InkWell(
        borderRadius: ZopiqRadii.rSm,
        onTap: () {
          HapticFeedback.selectionClick();
          onAdd();
        },
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: ZopiqRadii.rSm,
            border: Border.all(color: zc.divider),
            boxShadow: <BoxShadow>[
              BoxShadow(color: zc.cardShadow, blurRadius: 6, offset: const Offset(0, 2)),
            ],
          ),
          child: Center(
            child: Text(
              'ADD',
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: zc.primary),
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
    return DecoratedBox(
      decoration: BoxDecoration(color: zc.primary, borderRadius: ZopiqRadii.rSm),
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
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: Colors.white),
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
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: ZopiqSpacing.sm),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}
