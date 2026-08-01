import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

enum VendorSvgType {
  storefront,
  liveOrders,
  chefMenu,
  historyClock,
  moreGrid,
  storeOnline,
  storeClosed,
  prepTimer,
  riderPickup,
  earningsChart,
  staffRoster,
  stockToggle,
  receiptDetail,
  verifiedCheck,
}

/// Native Canvas vector icons for the Zopiq Vendor Merchant experience.
class VendorSvgIcon extends StatelessWidget {
  const VendorSvgIcon({
    required this.type,
    super.key,
    this.size = 24.0,
    this.color,
    this.secondaryColor,
  });

  final VendorSvgType type;
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
      painter: _VendorSvgPainter(
        type: type,
        color: mainColor,
        secondaryColor: accentColor,
      ),
    );
  }
}

class _VendorSvgPainter extends CustomPainter {
  _VendorSvgPainter({
    required this.type,
    required this.color,
    required this.secondaryColor,
  });

  final VendorSvgType type;
  final Color color;
  final Color secondaryColor;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double scale = w / 24.0;

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
      case VendorSvgType.storefront:
        // Store Front Building
        final Path roof = Path()
          ..moveTo(3, 9)
          ..lineTo(12, 3)
          ..lineTo(21, 9);
        canvas.drawPath(roof, strokePaint);

        final RRect body = RRect.fromRectAndRadius(
          const Rect.fromLTWH(5, 9, 14, 12),
          const Radius.circular(1.5),
        );
        canvas.drawRRect(body, strokePaint);

        // Store Door
        final RRect door = RRect.fromRectAndRadius(
          const Rect.fromLTWH(10, 13, 4, 8),
          const Radius.circular(1),
        );
        canvas.drawRRect(door, fillPaint);
        break;

      case VendorSvgType.liveOrders:
        // Kitchen Order Ticket & Bell
        final RRect ticket = RRect.fromRectAndRadius(
          const Rect.fromLTWH(4, 3, 16, 18),
          const Radius.circular(2.5),
        );
        canvas.drawRRect(ticket, strokePaint);

        canvas.drawLine(const Offset(7, 7), const Offset(17, 7), strokePaint);
        canvas.drawLine(const Offset(7, 11), const Offset(17, 11), strokePaint);
        canvas.drawLine(const Offset(7, 15), const Offset(13, 15), strokePaint);
        canvas.drawCircle(const Offset(16, 15), 1.5, fillPaint);
        break;

      case VendorSvgType.chefMenu:
        // Chef Hat & Book
        final Path hat = Path()
          ..moveTo(6, 17)
          ..cubicTo(4, 14, 4, 10, 8, 9)
          ..cubicTo(9, 6, 15, 6, 16, 9)
          ..cubicTo(20, 10, 20, 14, 18, 17)
          ..close();
        canvas.drawPath(hat, strokePaint);

        final RRect band = RRect.fromRectAndRadius(
          const Rect.fromLTWH(6, 17, 12, 4),
          const Radius.circular(1),
        );
        canvas.drawRRect(band, fillPaint);
        break;

      case VendorSvgType.historyClock:
        // Clock History Archive
        canvas.drawCircle(const Offset(12, 12), 9, strokePaint);
        canvas.drawLine(const Offset(12, 12), const Offset(12, 7), strokePaint);
        canvas.drawLine(const Offset(12, 12), const Offset(16, 12), strokePaint);
        break;

      case VendorSvgType.moreGrid:
        // 4 Grid Dots
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(4, 4, 6.5, 6.5),
            const Radius.circular(2),
          ),
          fillPaint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(13.5, 4, 6.5, 6.5),
            const Radius.circular(2),
          ),
          fillPaint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(4, 13.5, 6.5, 6.5),
            const Radius.circular(2),
          ),
          fillPaint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(13.5, 13.5, 6.5, 6.5),
            const Radius.circular(2),
          ),
          fillPaint,
        );
        break;

      case VendorSvgType.storeOnline:
        // Signal Beacon Online
        canvas.drawCircle(const Offset(12, 12), 4, fillPaint);
        canvas.drawCircle(const Offset(12, 12), 8, strokePaint);
        canvas.drawCircle(const Offset(12, 12), 11, accentPaint);
        break;

      case VendorSvgType.storeClosed:
        // Closed Lock
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
        break;

      case VendorSvgType.prepTimer:
        // Cooking Pan & Timer
        final Path pan = Path()
          ..moveTo(3, 13)
          ..cubicTo(3, 18, 17, 18, 17, 13)
          ..close();
        canvas.drawPath(pan, strokePaint);
        canvas.drawLine(const Offset(17, 14), const Offset(22, 14), strokePaint);

        // Steam waves
        canvas.drawLine(const Offset(6, 7), const Offset(6, 10), strokePaint);
        canvas.drawLine(const Offset(10, 6), const Offset(10, 10), strokePaint);
        canvas.drawLine(const Offset(14, 7), const Offset(14, 10), strokePaint);
        break;

      case VendorSvgType.riderPickup:
        // Delivery Rider Helmet / Scooter
        canvas.drawCircle(const Offset(8, 17), 3, strokePaint);
        canvas.drawCircle(const Offset(18, 17), 3, strokePaint);
        canvas.drawLine(const Offset(8, 17), const Offset(18, 17), strokePaint);

        final RRect box = RRect.fromRectAndRadius(
          const Rect.fromLTWH(4, 7, 7, 7),
          const Radius.circular(1.5),
        );
        canvas.drawRRect(box, fillPaint);
        break;

      case VendorSvgType.earningsChart:
        // Revenue Bar Chart
        canvas.drawLine(const Offset(3, 20), const Offset(21, 20), strokePaint);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(5, 12, 3.5, 8),
            const Radius.circular(1),
          ),
          fillPaint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(10.25, 7, 3.5, 13),
            const Radius.circular(1),
          ),
          fillPaint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(15.5, 4, 3.5, 16),
            const Radius.circular(1),
          ),
          fillPaint,
        );
        break;

      case VendorSvgType.staffRoster:
        // Staff Members
        canvas.drawCircle(const Offset(8, 8), 3.5, strokePaint);
        canvas.drawCircle(const Offset(16, 8), 3.5, strokePaint);

        final Path bodyLeft = Path()
          ..moveTo(3, 19)
          ..cubicTo(3, 15, 6, 14, 8, 14)
          ..cubicTo(10, 14, 13, 15, 13, 19);
        canvas.drawPath(bodyLeft, strokePaint);

        final Path bodyRight = Path()
          ..moveTo(12, 19)
          ..cubicTo(12, 16, 14, 15, 16, 15)
          ..cubicTo(18, 15, 21, 16, 21, 19);
        canvas.drawPath(bodyRight, strokePaint);
        break;

      case VendorSvgType.stockToggle:
        // Stock Switch Toggle Pill
        final RRect bg = RRect.fromRectAndRadius(
          const Rect.fromLTWH(3, 7, 18, 10),
          const Radius.circular(5),
        );
        canvas.drawRRect(bg, strokePaint);
        canvas.drawCircle(const Offset(16, 12), 3.5, fillPaint);
        break;

      case VendorSvgType.receiptDetail:
        // Order Invoice Receipt
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
        break;

      case VendorSvgType.verifiedCheck:
        // Shield Check
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
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _VendorSvgPainter oldDelegate) {
    return oldDelegate.type != type ||
        oldDelegate.color != color ||
        oldDelegate.secondaryColor != secondaryColor;
  }
}
