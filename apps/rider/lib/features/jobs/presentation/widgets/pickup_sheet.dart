import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiq_rider/core/widgets/rider_animations.dart';
import 'package:zopiq_rider/core/widgets/rider_svg_icons.dart';

/// Four digits, read aloud across a counter.
class PickupSheet extends StatelessWidget {
  const PickupSheet({required this.restaurantName, super.key});

  final String restaurantName;

  @override
  Widget build(BuildContext context) => _CodeSheet(
    title: 'Pickup Verification',
    subtitle: restaurantName,
    blurb:
        'Ask the staff at $restaurantName for the 4-digit code shown on their '
        'merchant tablet.',
    cta: 'Confirm Pickup & Load Bike',
    codeName: 'pickup',
  );
}

/// Its mirror at the other end of the ride (0049). The customer reads these four
/// digits off their own tracking screen — which is the whole point: a delivery
/// nobody was there to confirm used to be one tap by the rider alone.
class DeliverySheet extends StatelessWidget {
  const DeliverySheet({required this.deliverTo, this.cashToCollect, super.key});

  final String deliverTo;

  /// Set for a cash order. Asking for the code and the money in one breath is
  /// how a rider avoids walking away from a doorstep having done only one.
  final int? cashToCollect;

  @override
  Widget build(BuildContext context) => _CodeSheet(
    title: 'Delivery Verification',
    subtitle: deliverTo,
    blurb: cashToCollect == null
        ? 'Ask the customer for the 4-digit code on their Zopiqnow order screen.'
        : 'Collect ₹$cashToCollect in cash, then ask the customer for the '
              '4-digit code on their Zopiqnow order screen.',
    cta: 'Confirm Delivery',
    codeName: 'delivery',
  );
}

class _CodeSheet extends StatefulWidget {
  const _CodeSheet({
    required this.title,
    required this.subtitle,
    required this.blurb,
    required this.cta,
    required this.codeName,
  });

  final String title;
  final String subtitle;
  final String blurb;
  final String cta;
  final String codeName;

  @override
  State<_CodeSheet> createState() => _PickupSheetState();
}

class _PickupSheetState extends State<_CodeSheet> {
  final TextEditingController _code = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _submit([String? codeValue]) {
    final String code = codeValue ?? _code.text.trim();
    if (code.length != 4) {
      setState(() => _error = 'The ${widget.codeName} code must be 4 digits.');
      return;
    }
    Navigator.pop(context, code);
  }

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final Color surfaceColor = Theme.of(context).colorScheme.surface;
    final TextTheme t = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(ZopiqRadii.xl),
        ),
      ),
      padding: EdgeInsets.only(
        left: ZopiqSpacing.xl,
        right: ZopiqSpacing.xl,
        top: ZopiqSpacing.xl,
        bottom: MediaQuery.viewInsetsOf(context).bottom + ZopiqSpacing.xl,
      ),
      child: RiderFadeSlide(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Drag handle pill
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: zc.divider,
                  borderRadius: ZopiqRadii.rPill,
                ),
              ),
            ),
            const SizedBox(height: ZopiqSpacing.md),

            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(ZopiqSpacing.sm),
                  decoration: BoxDecoration(
                    color: zc.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: RiderSvgIcon(
                    type: RiderSvgType.pickupKey,
                    size: 24,
                    color: zc.primary,
                  ),
                ),
                const SizedBox(width: ZopiqSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        widget.title,
                        style: t.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        widget.subtitle,
                        style: t.bodySmall?.copyWith(
                          color: zc.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: ZopiqSpacing.md),
            Text(
              widget.blurb,
              style: t.bodyMedium?.copyWith(color: zc.textMuted),
            ),

            const SizedBox(height: ZopiqSpacing.xl),

            Center(
              child: RiderPinInput(
                length: 4,
                controller: _code,
                autofocus: true,
                errorText: _error,
                onCompleted: (String code) => _submit(code),
              ),
            ),

            const SizedBox(height: ZopiqSpacing.xl),

            ZopiqButton(
              label: widget.cta,
              variant: ZopiqButtonVariant.cta,
              onPressed: () => _submit(),
            ),
          ],
        ),
      ),
    );
  }
}
