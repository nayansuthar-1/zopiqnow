import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

enum RiderSvgType {
  deliveryBike,
  wallet,
  profile,
  restaurant,
  packedBox,
  navigationPin,
  cashCollect,
  phoneCall,
  pickupKey,
  radarScanner,
  verifiedShield,
  receipt,
}

/// High-performance SVG vector icons drawn with native Canvas paths.
class RiderSvgIcon extends StatelessWidget {
  const RiderSvgIcon({
    required this.type,
    super.key,
    this.size = 24.0,
    this.color,
    this.secondaryColor,
  });

  final RiderSvgType type;
  final double size;
  final Color? color;
  final Color? secondaryColor;

  @override
  Widget build(BuildContext context) {
    final ZopiqColors zc = context.zc;
    final Color mainColor = color ?? zc.primary;
    final Color accentColor = secondaryColor ?? mainColor.withValues(alpha: 0.3);

    return CustomPaint(
      size: Size(size, size),
      painter: _RiderSvgPainter(
        type: type,
        color: mainColor,
        secondaryColor: accentColor,
      ),
    );
  }
}

class _RiderSvgPainter extends CustomPainter {
  _RiderSvgPainter({
    required this.type,
    required this.color,
    required this.secondaryColor,
  });

  final RiderSvgType type;
  final Color color;
  final Color secondaryColor;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double scale = w / 24.0; // Normalized to 24x24 viewport

    canvas.save();
    canvas.scale(scale);

    final Paint fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final Paint strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Paint accentPaint = Paint()
      ..color = secondaryColor
      ..style = PaintingStyle.fill;

    switch (type) {
      case RiderSvgType.deliveryBike:
        // Delivery Scooter & Box
        // Wheels
        canvas.drawCircle(const Offset(6, 18), 3, strokePaint);
        canvas.drawCircle(const Offset(18, 18), 3, strokePaint);

        // Frame
        final Path frame = Path()
          ..moveTo(6, 18)
          ..lineTo(9, 14)
          ..lineTo(14, 14)
          ..lineTo(17, 9)
          ..lineTo(20, 9);
        canvas.drawPath(frame, strokePaint);

        // Handlebars
        canvas.drawLine(const Offset(17, 9), const Offset(15, 6), strokePaint);

        // Delivery Box on Back
        final RRect boxRRect = RRect.fromRectAndRadius(
          const Rect.fromLTWH(3, 7, 7, 7),
          const Radius.circular(1.5),
        );
        canvas.drawRRect(boxRRect, fillPaint);
        break;

      case RiderSvgType.wallet:
        // Money Wallet Vector
        final RRect walletBody = RRect.fromRectAndRadius(
          const Rect.fromLTWH(2, 6, 20, 14),
          const Radius.circular(3),
        );
        canvas.drawRRect(walletBody, strokePaint);

        // Top cash flap
        final Path flap = Path()
          ..moveTo(5, 6)
          ..cubicTo(5, 3, 19, 3, 19, 6);
        canvas.drawPath(flap, strokePaint);

        // Clasp button
        final RRect clasp = RRect.fromRectAndRadius(
          const Rect.fromLTWH(14, 11, 7, 4),
          const Radius.circular(2),
        );
        canvas.drawRRect(clasp, fillPaint);
        canvas.drawCircle(const Offset(16.5, 13), 1, Paint()..color = Colors.white);
        break;

      case RiderSvgType.profile:
        // Rider Helmet/Profile Avatar
        canvas.drawCircle(const Offset(12, 8), 4.5, strokePaint);
        final Path body = Path()
          ..moveTo(4, 21)
          ..cubicTo(4, 15, 8, 14, 12, 14)
          ..cubicTo(16, 14, 20, 15, 20, 21);
        canvas.drawPath(body, strokePaint);

        // Visor line
        canvas.drawLine(const Offset(9.5, 7.5), const Offset(14.5, 7.5), strokePaint);
        break;

      case RiderSvgType.restaurant:
        // Chef Hat / Cooking Pot
        final RRect pot = RRect.fromRectAndRadius(
          const Rect.fromLTWH(4, 10, 16, 10),
          const Radius.circular(3),
        );
        canvas.drawRRect(pot, strokePaint);

        // Pot handles
        canvas.drawLine(const Offset(2, 12), const Offset(4, 12), strokePaint);
        canvas.drawLine(const Offset(20, 12), const Offset(22, 12), strokePaint);

        // Steam waves
        final Path steam = Path()
          ..moveTo(8, 7)
          ..cubicTo(8, 5, 9, 4, 9, 3)
          ..moveTo(12, 7)
          ..cubicTo(12, 5, 13, 4, 13, 3)
          ..moveTo(16, 7)
          ..cubicTo(16, 5, 17, 4, 17, 3);
        canvas.drawPath(steam, strokePaint);
        break;

      case RiderSvgType.packedBox:
        // Packed Takeaway Parcel
        final RRect box = RRect.fromRectAndRadius(
          const Rect.fromLTWH(3, 7, 18, 14),
          const Radius.circular(2.5),
        );
        canvas.drawRRect(box, strokePaint);

        // Packing Tape lines
        canvas.drawLine(const Offset(12, 7), const Offset(12, 21), strokePaint);
        canvas.drawLine(const Offset(3, 14), const Offset(21, 14), strokePaint);

        // Top handles / bow ribbon
        final Path ribbon = Path()
          ..moveTo(9, 7)
          ..cubicTo(9, 4, 12, 4, 12, 7)
          ..cubicTo(12, 4, 15, 4, 15, 7);
        canvas.drawPath(ribbon, strokePaint);
        break;

      case RiderSvgType.navigationPin:
        // Map Location Pin
        final Path pin = Path()
          ..moveTo(12, 2)
          ..cubicTo(6.5, 2, 4, 6.5, 4, 11)
          ..cubicTo(4, 16.5, 12, 22, 12, 22)
          ..cubicTo(12, 22, 20, 16.5, 20, 11)
          ..cubicTo(20, 6.5, 17.5, 2, 12, 2)
          ..close();
        canvas.drawPath(pin, strokePaint);
        canvas.drawCircle(const Offset(12, 10), 3, fillPaint);
        break;

      case RiderSvgType.cashCollect:
        // Currency / Banknote Stack
        final RRect note1 = RRect.fromRectAndRadius(
          const Rect.fromLTWH(2, 6, 20, 12),
          const Radius.circular(2),
        );
        canvas.drawRRect(note1, strokePaint);
        canvas.drawCircle(const Offset(12, 12), 3, strokePaint);
        canvas.drawLine(const Offset(5, 9), const Offset(5, 15), strokePaint);
        canvas.drawLine(const Offset(19, 9), const Offset(19, 15), strokePaint);
        break;

      case RiderSvgType.phoneCall:
        // Phone Handset
        final Path phone = Path()
          ..moveTo(6.5, 3.5)
          ..lineTo(9, 6)
          ..lineTo(7.5, 8.5)
          ..cubicTo(9, 11.5, 12.5, 15, 15.5, 16.5)
          ..lineTo(18, 15)
          ..lineTo(20.5, 17.5)
          ..cubicTo(20.5, 17.5, 19, 21, 15, 21)
          ..cubicTo(9, 21, 3, 15, 3, 9)
          ..cubicTo(3, 5, 6.5, 3.5, 6.5, 3.5)
          ..close();
        canvas.drawPath(phone, strokePaint);
        break;

      case RiderSvgType.pickupKey:
        // Digital OTP Pin Lock
        final RRect lock = RRect.fromRectAndRadius(
          const Rect.fromLTWH(5, 10, 14, 11),
          const Radius.circular(3),
        );
        canvas.drawRRect(lock, strokePaint);

        final Path shackle = Path()
          ..moveTo(8, 10)
          ..lineTo(8, 7)
          ..cubicTo(8, 4.5, 16, 4.5, 16, 7)
          ..lineTo(16, 10);
        canvas.drawPath(shackle, strokePaint);

        // Keyhole
        canvas.drawCircle(const Offset(12, 14.5), 1.5, fillPaint);
        canvas.drawLine(const Offset(12, 14.5), const Offset(12, 17.5), strokePaint);
        break;

      case RiderSvgType.radarScanner:
        // Radar Waves
        canvas.drawCircle(const Offset(12, 12), 10, strokePaint);
        canvas.drawCircle(const Offset(12, 12), 6, accentPaint);
        canvas.drawCircle(const Offset(12, 12), 2.5, fillPaint);

        // Sweeping radar line
        canvas.drawLine(
          const Offset(12, 12),
          Offset(12 + 10 * math.cos(-math.pi / 4), 12 + 10 * math.sin(-math.pi / 4)),
          strokePaint,
        );
        break;

      case RiderSvgType.verifiedShield:
        // Shield with Checkmark
        final Path shield = Path()
          ..moveTo(12, 3)
          ..lineTo(4, 6)
          ..lineTo(4, 12)
          ..cubicTo(4, 17, 12, 21, 12, 21)
          ..cubicTo(12, 21, 20, 17, 20, 12)
          ..lineTo(20, 6)
          ..close();
        canvas.drawPath(shield, strokePaint);

        final Path check = Path()
          ..moveTo(8.5, 11.5)
          ..lineTo(11, 14)
          ..lineTo(15.5, 9.5);
        canvas.drawPath(check, strokePaint);
        break;

      case RiderSvgType.receipt:
        // Order Invoice / Receipt
        final Path receipt = Path()
          ..moveTo(5, 3)
          ..lineTo(19, 3)
          ..lineTo(19, 21)
          ..lineTo(16.5, 19.5)
          ..lineTo(14, 21)
          ..lineTo(11.5, 19.5)
          ..lineTo(9, 21)
          ..lineTo(6.5, 19.5)
          ..lineTo(5, 21)
          ..close();
        canvas.drawPath(receipt, strokePaint);

        canvas.drawLine(const Offset(8, 7), const Offset(16, 7), strokePaint);
        canvas.drawLine(const Offset(8, 11), const Offset(16, 11), strokePaint);
        canvas.drawLine(const Offset(8, 15), const Offset(13, 15), strokePaint);
        break;
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RiderSvgPainter oldDelegate) {
    return oldDelegate.type != type ||
        oldDelegate.color != color ||
        oldDelegate.secondaryColor != secondaryColor;
  }
}
