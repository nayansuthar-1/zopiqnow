import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/cart/domain/entities/cart_bill.dart';

/// The itemised bill, drawn as a receipt.
///
/// It was a rounded rectangle with a heading on it — the same card as the three
/// above it, so the one thing on the screen that *is* a document read as one
/// more panel. A bill has a shape people already know: notched sides where it
/// tears, a perforated line above the total, and a torn bottom edge. Nothing
/// here is decoration for its own sake; the silhouette is what says "this is
/// the receipt" before a single number is read.
///
/// The free-delivery progress bar that used to live here is gone with migration
/// 0123 — there is no threshold to make progress towards.
class BillSummary extends StatelessWidget {
  const BillSummary({required this.bill, super.key});

  final CartBill bill;

  /// Coupon only. A waived delivery fee used to count towards this and no
  /// longer can — migration 0123 withdrew the threshold, so there is no waived
  /// fee to add and "you saved ₹40" would be a claim about nothing.
  int get _saved => bill.discount;

  /// The height of the band below the perforation.
  ///
  /// It is a *fixed* band, and that is what lets the notches and the dashed
  /// line agree with the content: the shape is painted by a clipper, which knows
  /// only the card's size, so the tear has to sit a known distance from an edge.
  /// Measured from the bottom, because everything above it — four to six bill
  /// rows — is what varies.
  ///
  /// Generous enough for the "To pay" row at large system font sizes, and taller
  /// by one strip when there is a saving to announce under it.
  double get _footerHeight => _saved > 0 ? 132 : 76;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color paper = isDark
        ? Theme.of(context).colorScheme.surfaceContainerHigh
        : Colors.white;

    return PhysicalShape(
      // A clipper rather than a `BoxDecoration`, and `PhysicalShape` rather than
      // a plain `ClipPath`, because the shadow has to follow the torn edge —
      // clipping a shadowed box just cuts the shadow off square and the notches
      // stop reading as holes.
      clipper: _ReceiptShape(footerHeight: _footerHeight),
      // `PhysicalShape` defaults to `Clip.none` — it would paint the silhouette
      // and then let the content spill past it.
      clipBehavior: Clip.antiAlias,
      color: paper,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.5 : 0.18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ZopiqSpacing.xl,
              ZopiqSpacing.xl,
              ZopiqSpacing.xl,
              ZopiqSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'BILL DETAILS',
                  textAlign: TextAlign.center,
                  style: t.labelMedium?.copyWith(
                    color: zc.textMuted,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: ZopiqSpacing.xl),

                _BillRow(label: 'Item total', value: '₹${bill.subtotal}'),
                // No FREE branch and no strikethrough. The fee is charged on
                // every order now, so a struck-through ₹40 beside the word FREE
                // would be advertising a discount that does not exist.
                _BillRow(label: 'Delivery fee', value: '₹${bill.deliveryFee}'),
                // Its own line rather than a bigger delivery fee, and captioned
                // with the reason. A customer who opens the bill at 8pm and
                // finds ₹60 where ₹40 was an hour ago is owed the sentence, not
                // left to work it out (migration 0129).
                if (!bill.surcharge.isEmpty)
                  _BillRow(
                    label: bill.surcharge.label!,
                    caption: bill.surcharge.reason,
                    value: '₹${bill.surcharge.total}',
                  ),
                _BillRow(label: 'Taxes', value: '₹${bill.taxes}'),
                if (bill.discount > 0)
                  _BillRow(
                    label: 'Coupon discount',
                    value: '-₹${bill.discount}',
                    valueColor: zc.veg,
                  ),
              ],
            ),
          ),

          // The perforation. Level with the notches by construction: both are
          // placed off [_footerHeight], and this sits directly on top of the
          // footer band.
          _Perforation(color: zc.divider),

          SizedBox(
            height: _footerHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                ZopiqSpacing.xl,
                ZopiqSpacing.lg,
                ZopiqSpacing.xl,
                // Clear of the scalloped edge, which bites upward into the card.
                ZopiqSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'TO PAY',
                          style: t.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      // What the bill would have been without the offer, struck
                      // through beside what it is. The saving is already stated
                      // in the strip below, but a number nobody has to read a
                      // strip to find is the number that makes an offer feel
                      // like one.
                      if (bill.discount > 0) ...<Widget>[
                        Text(
                          '₹${bill.total + bill.discount}',
                          style: t.bodyMedium?.copyWith(
                            color: zc.textMuted,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(width: ZopiqSpacing.sm),
                      ],
                      ZopiqAnimatedAmount(
                        amount: bill.total,
                        style: t.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  if (_saved > 0) ...<Widget>[
                    const SizedBox(height: ZopiqSpacing.md),
                    _SavingsStrip(saved: _saved),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The receipt silhouette: rounded at the top, bitten at the sides where it
/// tears, and torn along the bottom.
///
/// Everything is derived from the card's own size and [footerHeight], so the
/// shape stays in register with the content however many rows the bill has.
class _ReceiptShape extends CustomClipper<Path> {
  const _ReceiptShape({required this.footerHeight});

  /// Distance from the bottom edge to the tear line — where the two side
  /// notches are centred.
  final double footerHeight;

  /// Top corners.
  static const double _corner = 20;

  /// How deep the side notches bite in.
  static const double _notch = 11;

  /// The target width of one bottom scallop. The real width is this rounded to
  /// a whole number of scallops across the card, so the row always starts and
  /// ends flush with the edges instead of leaving a stub at one end.
  static const double _scallop = 18;

  @override
  Path getClip(Size size) {
    final double w = size.width;
    final double h = size.height;
    // Centre of the notches: the tear line sits on top of the footer band.
    // Floored clear of the top corner, so a card that is somehow shorter than
    // its own footer degrades to a plain receipt rather than to a self-crossing
    // path — a clipper is asked to draw at whatever size it is given, including
    // during a first layout pass.
    final double tearY = math.max(_corner + _notch, h - footerHeight);

    // A whole number of scallops, at least one, and never so many that a bite
    // would reach past the tear line on a very narrow card.
    final int count = math.max(1, (w / _scallop).round());
    final double step = w / count;
    final double bite = step / 2;
    final double bottom = h - bite;

    final Path p = Path()
      ..moveTo(_corner, 0)
      ..lineTo(w - _corner, 0)
      ..arcToPoint(
        Offset(w, _corner),
        radius: const Radius.circular(_corner),
      )
      // Right edge down to the tear, the notch, then on to the bottom.
      ..lineTo(w, tearY - _notch)
      ..arcToPoint(
        Offset(w, tearY + _notch),
        radius: const Radius.circular(_notch),
        clockwise: false,
      )
      ..lineTo(w, bottom);

    // The torn edge, right to left. `clockwise: false` on a right-to-left arc
    // bulges *upward* — a bite out of the paper rather than a bump hanging off
    // it, which is what a tear looks like.
    for (int i = 0; i < count; i++) {
      p.arcToPoint(
        Offset(w - step * (i + 1), bottom),
        radius: Radius.circular(bite),
        clockwise: false,
      );
    }

    // Left edge back up, through its own notch.
    p
      ..lineTo(0, tearY + _notch)
      ..arcToPoint(
        Offset(0, tearY - _notch),
        radius: const Radius.circular(_notch),
        clockwise: false,
      )
      ..lineTo(0, _corner)
      ..arcToPoint(
        const Offset(_corner, 0),
        radius: const Radius.circular(_corner),
      )
      ..close();

    return p;
  }

  @override
  bool shouldReclip(_ReceiptShape old) => old.footerHeight != footerHeight;
}

/// The dashed line across the tear, inset at both ends so it does not run into
/// the notches the clipper has taken out of the edges.
class _Perforation extends StatelessWidget {
  const _Perforation({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ZopiqSpacing.lg),
      child: SizedBox(
        height: 1,
        child: CustomPaint(painter: _DashPainter(color: color)),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  const _DashPainter({required this.color});

  final Color color;

  static const double _dash = 5;
  static const double _gap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;

    for (double x = 0; x < size.width; x += _dash + _gap) {
      canvas.drawLine(
        Offset(x, 0.5),
        Offset(math.min(x + _dash, size.width), 0.5),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

/// Green savings highlight strip at the base of the bill.
class _SavingsStrip extends StatelessWidget {
  const _SavingsStrip({required this.saved});

  final int saved;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.md,
        vertical: ZopiqSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: zc.veg.withValues(alpha: 0.12),
        borderRadius: ZopiqRadii.rSm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.savings_rounded, size: 16, color: zc.veg),
          const SizedBox(width: ZopiqSpacing.sm),
          Flexible(
            child: Text(
              'You saved ₹$saved on this order',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.bodySmall?.copyWith(
                color: zc.veg,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BillRow extends StatelessWidget {
  const _BillRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.caption,
  });

  final String label;
  final String value;
  final Color? valueColor;

  /// A quieter second line under [label], for a charge that has to explain
  /// itself. Null on every ordinary row.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final TextTheme t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: ZopiqSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: t.bodyMedium?.copyWith(color: zc.textMuted),
                ),
                if (caption != null)
                  Padding(
                    padding: const EdgeInsets.only(top: ZopiqSpacing.xxs),
                    child: Text(
                      caption!,
                      style: t.bodySmall?.copyWith(
                        color: zc.textMuted.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: ZopiqSpacing.md),
          Text(
            value,
            style: t.bodyMedium?.copyWith(
              color: valueColor ?? zc.textStrong,
              fontWeight: valueColor != null
                  ? FontWeight.w800
                  : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
