import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The pins, drawn at runtime rather than shipped as assets.
///
/// **Why not a PNG in `assets/`.** MapLibre, unlike Google's SDK, has no stock
/// marker: every symbol on the map is an image you registered yourself. That
/// leaves two ways to get one. An asset would mean a file per colour per
/// density — six PNGs to keep in step with the palette by hand, and a palette
/// change that silently doesn't apply. Drawing them here means the pin is the
/// same [ZopiqPalette] value as everything else in the app by construction, and
/// it is rasterised at the device's real pixel ratio, so it is crisp on a 3x
/// phone without a 3x file existing.
///
/// The cost is one canvas per distinct colour per launch, which [_cache] makes
/// literal: these are a few hundred bytes each and are never redrawn.
abstract final class MapMarkers {
  static final Map<String, Uint8List> _cache = <String, Uint8List>{};

  /// A teardrop, in [color], with a white keyline and a white centre.
  ///
  /// The keyline is not decoration — a flat-coloured pin on satellite imagery
  /// sits on a background of arbitrary colour, and without a light edge an
  /// orange pin over an orange rooftop disappears.
  static Future<Uint8List> pin({
    required Color color,
    required double pixelRatio,
  }) {
    return _draw(
      'pin-${color.toARGB32()}-$pixelRatio',
      width: 30,
      height: 40,
      pixelRatio: pixelRatio,
      paint: (ui.Canvas canvas, Size size) {
        const double stroke = 2;
        final double r = size.width / 2 - stroke;
        final double cx = size.width / 2;
        final double cy = r + stroke;

        final Path path = Path()
          ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r))
          ..moveTo(cx - r * 0.66, cy + r * 0.74)
          ..lineTo(cx, size.height - stroke)
          ..lineTo(cx + r * 0.66, cy + r * 0.74)
          ..close();

        canvas
          ..drawShadow(path, Colors.black.withValues(alpha: 0.4), 2, false)
          ..drawPath(path, Paint()..color = color)
          ..drawPath(
            path,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = stroke,
          )
          ..drawCircle(
            Offset(cx, cy),
            r * 0.36,
            Paint()..color = Colors.white,
          );
      },
    );
  }

  /// The rider: a disc rather than a teardrop.
  ///
  /// A teardrop points at a fixed address; this one is a moving vehicle, and
  /// giving it the same shape as the restaurant and the doorstep would say the
  /// three are the same kind of thing. Every navigation app makes the same
  /// distinction for the same reason.
  static Future<Uint8List> rider({
    required Color color,
    required double pixelRatio,
  }) {
    return _draw(
      'rider-${color.toARGB32()}-$pixelRatio',
      width: 26,
      height: 26,
      pixelRatio: pixelRatio,
      paint: (ui.Canvas canvas, Size size) {
        final Offset c = Offset(size.width / 2, size.height / 2);
        final double r = size.width / 2 - 2;

        canvas
          ..drawCircle(
            c,
            r,
            Paint()
              ..color = Colors.black.withValues(alpha: 0.28)
              ..maskFilter = const ui.MaskFilter.blur(BlurStyle.normal, 2),
          )
          ..drawCircle(c, r, Paint()..color = Colors.white)
          ..drawCircle(c, r - 3, Paint()..color = color);
      },
    );
  }

  /// Rasterises [paint] into a PNG at [pixelRatio], memoised under [key].
  static Future<Uint8List> _draw(
    String key, {
    required double width,
    required double height,
    required double pixelRatio,
    required void Function(ui.Canvas, Size) paint,
  }) async {
    final Uint8List? hit = _cache[key];
    if (hit != null) return hit;

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    canvas.scale(pixelRatio);
    paint(canvas, Size(width, height));

    final ui.Image image = await recorder.endRecording().toImage(
      (width * pixelRatio).ceil(),
      (height * pixelRatio).ceil(),
    );
    final ByteData? data = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    image.dispose();

    final Uint8List bytes = data!.buffer.asUint8List();
    _cache[key] = bytes;
    return bytes;
  }
}
