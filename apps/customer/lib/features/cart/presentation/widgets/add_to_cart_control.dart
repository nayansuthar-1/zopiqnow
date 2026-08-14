import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

/// The iconic "ADD" control that expands into a −/quantity/+ stepper once the
/// item is in the cart. Presentation-only: quantity and callbacks are supplied
/// by the caller, so it works identically on the menu and in the cart.
///
/// **The shape is a rounded rectangle, not a pill, and the fill is the card's
/// own surface rather than orange.** It used to be a 20pt pill with a tinted
/// orange fill, an orange border and an orange glow — three statements of the
/// same colour stacked on one 36pt control, repeated down a hundred-dish menu
/// until the brand colour stopped meaning anything. Now the border and the word
/// carry it and the button sits *on* the card instead of glowing off it, which
/// is the shape Zomato and Swiggy both settled on for the same reason.
class AddToCartControl extends StatelessWidget {
  const AddToCartControl({
    required this.quantity,
    required this.onAdd,
    required this.onIncrement,
    required this.onDecrement,
    this.width = 88,
    this.enabled = true,
    super.key,
  });

  /// The corner radius both states share. Small enough to read as a rectangle,
  /// large enough not to look like an unstyled box — and named because the
  /// button, the stepper and both of their ink splashes have to agree, which is
  /// four places one number used to be written into.
  static const double radius = 9;

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
    const BorderRadius shape = BorderRadius.all(
      Radius.circular(AddToCartControl.radius),
    );

    return Material(
      // The card's own surface, not a tint of the brand. On a white card this is
      // white; in dark mode it is the elevated surface — either way the button
      // reads as a raised control rather than as a coloured patch.
      color: surface,
      borderRadius: shape,
      child: InkWell(
        borderRadius: shape,
        onTap: () {
          HapticFeedback.selectionClick();
          onAdd();
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: shape,
            border: Border.all(color: zc.primary.withValues(alpha: 0.55)),
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'ADD',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: zc.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(width: 1),
                // Superscript, not a leading icon at label size. It says the
                // button adds *another* one without competing with the word for
                // the eye, which is the detail that makes the Zomato control
                // read as small rather than as cramped.
                Transform.translate(
                  offset: const Offset(0, -4),
                  child: Icon(
                    Icons.add_rounded,
                    size: 10,
                    color: zc.primary,
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
    return DecoratedBox(
      // Solid brand here and only here. Once a dish is in the cart the control
      // *is* the state, so it earns the fill the ADD button no longer takes —
      // and one filled control per row still reads as an accent, where two did
      // not. Same radius as ADD, so the swap between them does not change shape.
      decoration: BoxDecoration(
        color: zc.primary,
        borderRadius: const BorderRadius.all(
          Radius.circular(AddToCartControl.radius),
        ),
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

