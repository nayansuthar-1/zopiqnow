import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

/// The iconic "ADD" control that expands into a −/quantity/+ stepper once the
/// item is in the cart. Presentation-only: quantity and callbacks are supplied
/// by the caller, so it works identically on the menu and in the cart.
///
/// **The ADD half carries no brand colour at all.** It was a pill with a tinted
/// orange fill, an orange border, orange text and an orange glow — four
/// statements of one colour on a 36pt control, repeated down a hundred-dish
/// menu until the brand colour stopped meaning anything. It is now the card's
/// own surface, a hairline in the divider colour, and the word in the page's
/// text colour: white-on-grey in light mode, and the dark surface with a light
/// word in dark. Orange survives in exactly one place — the stepper, below,
/// which is the state worth colouring.
///
/// **And there is no `+`.** A superscript plus beside the word put a glyph on a
/// different baseline from the letters next to it, which is the kind of detail
/// that reads as a rendering fault rather than as typography. "ADD" already says
/// what the button does.
class AddToCartControl extends StatelessWidget {
  const AddToCartControl({
    required this.quantity,
    required this.onAdd,
    required this.onIncrement,
    required this.onDecrement,
    this.width = 72,
    this.enabled = true,
    super.key,
  });

  /// The corner radius both states share. Small enough to read as a rectangle,
  /// large enough not to look like an unstyled box — and named because the
  /// button, the stepper and both of their ink splashes have to agree, which is
  /// four places one number used to be written into.
  static const double radius = 8;

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
            border: Border.all(color: zc.divider),
          ),
          // The word alone, centred, with nothing beside it to push it off
          // centre. No Row and no icon — a single centred Text is why the button
          // can now be 72pt instead of 104 without looking cramped.
          child: Center(
            child: Text(
              'ADD',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: zc.textStrong,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 0.3,
              ),
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
      radius: 18,
      // 6, not 8. The control narrowed to 72 with ADD, and both states share one
      // width — at the old padding the two 16pt icons and the count needed 76
      // and overflowed by four points the moment a dish went into the cart.
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Icon(icon, color: Colors.white, size: 15),
      ),
    );
  }
}

