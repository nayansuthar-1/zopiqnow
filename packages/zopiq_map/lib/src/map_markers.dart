import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

/// What a pin is a picture of.
///
/// The kind carries the icon and the colour, so a caller says *what a thing is*
/// and never *what it should look like*. That is the whole reason the three are
/// told apart on the map: an orange dot and a green dot are two dots, but a
/// storefront, a person and a scooter are three different things at a glance,
/// in any colour, at any size, to someone who does not read English.
enum ZopiqPinKind {
  /// Where the food is cooked and collected.
  vendor(
    icon: Icons.storefront,
    colour: ZopiqPalette.primary,
    shape: _PinShape.teardrop,
  ),

  /// Where it is going, and who is waiting for it.
  customer(
    icon: Icons.person,
    colour: ZopiqPalette.veg,
    shape: _PinShape.teardrop,
  ),

  /// The delivery partner, in motion.
  ///
  /// A disc rather than a teardrop, because a teardrop points at a fixed address
  /// and this one is a vehicle that is somewhere different every few seconds.
  /// Every navigation app draws the moving thing differently from the fixed ones
  /// for the same reason.
  rider(
    icon: Icons.delivery_dining,
    colour: Color(0xFF1B6FE0),
    shape: _PinShape.disc,
  );

  const ZopiqPinKind({
    required this.icon,
    required this.colour,
    required this.shape,
  });

  /// A `const` [IconData], deliberately. Flutter's release builds tree-shake
  /// unused icon glyphs by finding constant `IconData` instances, so an icon
  /// assembled at runtime would compile, ship, and then draw an empty box in
  /// release. These are constants precisely so the shaker keeps their glyphs.
  final IconData icon;

  final Color colour;
  final _PinShape shape;

  /// Where the bitmap touches the coordinate it marks, as the fraction of its
  /// own size the SDKs expect.
  ///
  /// A teardrop points at its place, so it is pinned by its tip. A disc *is* its
  /// place, so it is pinned through its middle. Get this wrong and every marker
  /// sits half a pin north of where it actually is.
  Offset get anchor => switch (shape) {
    _PinShape.teardrop => const Offset(0.5, 1),
    _PinShape.disc => const Offset(0.5, 0.5),
  };
}

enum _PinShape { teardrop, disc }

/// The pins, drawn at runtime rather than shipped as assets.
///
/// **Why not PNGs in `assets/`.** Neither map SDK ships a marker you can put an
/// icon inside, so every symbol is an image somebody has to produce. An asset
/// would mean a file per kind per screen density — nine PNGs to keep in step
/// with the palette by hand, and a palette change that silently fails to reach
/// them. Drawing them here means the pin is the same [ZopiqPalette] value as
/// everything else in the app by construction, and it is rasterised at the
/// device's real pixel ratio, so it is crisp on a 3x phone without a 3x file
/// existing.
///
/// The cost is one canvas per kind per launch, which [_cache] makes literal.
abstract final class MapMarkers {
  static final Map<String, Uint8List> _cache = <String, Uint8List>{};

  /// The marker for [kind], rasterised for a display of [pixelRatio].
  static Future<Uint8List> forKind(
    ZopiqPinKind kind, {
    required double pixelRatio,
  }) {
    return switch (kind.shape) {
      _PinShape.teardrop => _teardrop(kind, pixelRatio),
      _PinShape.disc => _disc(kind, pixelRatio),
    };
  }

  /// A teardrop with the kind's icon in its head.
  ///
  /// The white keyline is not decoration. These sit on satellite imagery, whose
  /// colour is whatever the ground happens to be, and without a light edge an
  /// orange pin over an orange rooftop disappears.
  static Future<Uint8List> _teardrop(ZopiqPinKind kind, double dpr) {
    return _draw(
      'teardrop-${kind.name}-$dpr',
      width: 40,
      height: 52,
      pixelRatio: dpr,
      paint: (ui.Canvas canvas, Size size) {
        const double stroke = 2.5;
        final double r = size.width / 2 - stroke;
        final double cx = size.width / 2;
        final double cy = r + stroke;

        final Path path = Path()
          ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r))
          ..moveTo(cx - r * 0.62, cy + r * 0.78)
          ..lineTo(cx, size.height - stroke)
          ..lineTo(cx + r * 0.62, cy + r * 0.78)
          ..close();

        canvas
          ..drawShadow(path, Colors.black.withValues(alpha: 0.45), 2, false)
          ..drawPath(path, Paint()..color = kind.colour)
          ..drawPath(
            path,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = stroke,
          );

        _icon(canvas, kind.icon, Offset(cx, cy), r * 1.15, Colors.white);
      },
    );
  }

  /// A disc with the kind's icon in the middle — the moving marker.
  static Future<Uint8List> _disc(ZopiqPinKind kind, double dpr) {
    return _draw(
      'disc-${kind.name}-$dpr',
      width: 42,
      height: 42,
      pixelRatio: dpr,
      paint: (ui.Canvas canvas, Size size) {
        final Offset c = Offset(size.width / 2, size.height / 2);
        final double r = size.width / 2 - 3;

        canvas
          ..drawCircle(
            c,
            r,
            Paint()
              ..color = Colors.black.withValues(alpha: 0.3)
              ..maskFilter = const ui.MaskFilter.blur(BlurStyle.normal, 2.5),
          )
          // A white collar, so the disc reads as a marker rather than as a
          // coloured blob that happens to be on the map.
          ..drawCircle(c, r, Paint()..color = Colors.white)
          ..drawCircle(c, r - 3, Paint()..color = kind.colour);

        _icon(canvas, kind.icon, c, r * 1.25, Colors.white);
      },
    );
  }

  /// Paints one Material glyph centred on [centre].
  static void _icon(
    ui.Canvas canvas,
    IconData icon,
    Offset centre,
    double size,
    Color colour,
  ) {
    final TextPainter painter = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: colour,
        ),
      )
      ..layout();

    painter.paint(
      canvas,
      centre - Offset(painter.width / 2, painter.height / 2),
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
