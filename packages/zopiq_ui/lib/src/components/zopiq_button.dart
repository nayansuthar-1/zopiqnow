import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:zopiq_ui/src/theme/zopiq_colors.dart';
import 'package:zopiq_ui/src/tokens/zopiq_radii.dart';
import 'package:zopiq_ui/src/tokens/zopiq_spacing.dart';

/// Visual weight of a [ZopiqButton].
enum ZopiqButtonVariant {
  /// Swiggy Orange — default primary action.
  primary,

  /// CTA Orange — strongest emphasis (checkout / "ADD").
  cta,

  /// Outlined — secondary action.
  outline,
}

/// The one button feature code should use. Wraps Material buttons with
/// consistent sizing, an integrated loading state, and haptics on tap
/// (Rule 2.6). Colors come entirely from tokens.
class ZopiqButton extends StatelessWidget {
  const ZopiqButton({
    required this.label,
    required this.onPressed,
    this.variant = ZopiqButtonVariant.primary,
    this.icon,
    this.isLoading = false,
    this.expand = true,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final ZopiqButtonVariant variant;
  final IconData? icon;
  final bool isLoading;

  /// Whether the button stretches to fill its parent's width.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final bool disabled = onPressed == null || isLoading;

    void handleTap() {
      HapticFeedback.selectionClick();
      onPressed?.call();
    }

    final Widget child = isLoading
        ? SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation<Color>(
                variant == ZopiqButtonVariant.outline
                    ? zc.primary
                    : Colors.white,
              ),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 20),
                const SizedBox(width: ZopiqSpacing.sm),
              ],
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
          );

    final Widget button = switch (variant) {
      ZopiqButtonVariant.primary => ElevatedButton(
        onPressed: disabled ? null : handleTap,
        child: child,
      ),
      ZopiqButtonVariant.cta => FilledButton(
        onPressed: disabled ? null : handleTap,
        child: child,
      ),
      ZopiqButtonVariant.outline => OutlinedButton(
        onPressed: disabled ? null : handleTap,
        child: child,
      ),
    };

    return SizedBox(
      width: expand ? double.infinity : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: disabled && !isLoading ? 0.5 : 1,
        child: ClipRRect(borderRadius: ZopiqRadii.rMd, child: button),
      ),
    );
  }
}
