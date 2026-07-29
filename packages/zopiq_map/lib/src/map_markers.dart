import 'dart:math' as math;
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
}

enum _PinShape { teardrop, disc }

/// A finished marker image, and the point on it that touches the coordinate.
///
/// The anchor travels with the bytes rather than living on [ZopiqPinKind]
/// because it is no longer a property of the *kind*: the same rider disc is
/// anchored differently depending on whether a label sits above it, and the
/// only code that can work that out is the code that decided how tall to make
/// the canvas.
@immutable
class MarkerBitmap {
  const MarkerBitmap({required this.bytes, required this.anchor});

  final Uint8List bytes;

  /// Where the image touches its coordinate, as the fraction of its own size
  /// the SDK expects. Get this wrong and every marker sits half a pin north of
  /// where it actually is.
  final Offset anchor;
}

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
/// It is also the only way the moving marker can carry a *heading* and a
/// *label*. See [forPin] for why both are baked into the image rather than
/// added on top of it.
///
/// The cost is one canvas per distinct marker per launch, which [_cache] makes
/// literal.
abstract final class MapMarkers {
  static final Map<String, MarkerBitmap> _cache = <String, MarkerBitmap>{};

  /// How many rasterised markers are kept.
  ///
  /// This cache used to hold one image per kind — three, for the life of the
  /// app. A marker that carries a bearing and a countdown is a different image
  /// every time either changes, so the same map is now several dozen images
  /// over one delivery and the cache would grow for as long as the app ran.
  ///
  /// Evicted least-recently-used rather than oldest-first, which matters: the
  /// restaurant and destination pins are drawn on every single load and are
  /// also the two oldest entries, so oldest-first would throw away exactly the
  /// images that never change and keep the ones that never repeat.
  static const int _maxCached = 96;

  /// Headings are rounded to this before they reach the cache key.
  ///
  /// A bearing is a `double`, so an un-rounded one is a fresh canvas on every
  /// single fix and a cache that only grows. Five degrees is under the noise on
  /// a phone's compass and far under what anyone can see in a chevron, so this
  /// costs nothing visible and bounds the cache at 72 rotations per kind.
  static const double _headingStep = 5;

  /// The marker for one pin, rasterised for a display of [pixelRatio].
  ///
  /// **Why [heading] and [label] are painted in rather than layered on.** The
  /// SDK can rotate a marker, but it rotates the whole image — a scooter turned
  /// to point south-west is a scooter lying on its side. And a label drawn as a
  /// Flutter widget over the map would have to be positioned from the marker's
  /// *screen* coordinate, which is an async round trip to the platform view on
  /// every frame of a moving pin. Baking both into one bitmap keeps the glyph
  /// upright, keeps the label glued to the pin for free, and costs one cached
  /// canvas.
  static Future<MarkerBitmap> forPin(
    ZopiqPinKind kind, {
    required double pixelRatio,
    double? heading,
    String? label,
  }) {
    final double? bearing = heading == null
        ? null
        : (heading / _headingStep).roundToDouble() * _headingStep;

    return _draw(
      'v2-${kind.name}-$bearing-$label-$pixelRatio',
      kind: kind,
      heading: bearing,
      label: label,
      pixelRatio: pixelRatio,
    );
  }

  /// Lays out the canvas, paints the body and any label into it, and works out
  /// where the whole thing is anchored.
  static Future<MarkerBitmap> _draw(
    String key, {
    required ZopiqPinKind kind,
    required double? heading,
    required String? label,
    required double pixelRatio,
  }) async {
    // Removed and reinserted rather than read in place: Dart maps iterate in
    // insertion order, so putting a hit back at the end is what makes
    // `_cache.keys.first` below the least *recently used* key rather than
    // merely the oldest.
    final MarkerBitmap? hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit;
      return hit;
    }

    // The body: the pin itself, without its label.
    final Size body = switch (kind.shape) {
      // Room around the disc for the heading chevron, so a marker that grows a
      // direction does not grow a clipped one.
      _PinShape.disc =>
        heading == null ? const Size(42, 42) : const Size(60, 60),
      _PinShape.teardrop => const Size(40, 52),
    };
    // A teardrop points at its place; a disc *is* its place.
    final double bodyAnchorY = switch (kind.shape) {
      _PinShape.teardrop => 1,
      _PinShape.disc => 0.5,
    };

    final TextPainter? pill = label == null ? null : _pillText(label);
    final double pillWidth = pill == null ? 0 : pill.width + _pillPadX * 2;
    final double pillHeight = pill == null ? 0 : pill.height + _pillPadY * 2;

    final double width = math.max(body.width, pillWidth);
    final double height = pill == null
        ? body.height
        : pillHeight + _pillGap + body.height;
    final double bodyTop = height - body.height;

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    canvas.scale(pixelRatio);

    if (pill != null) {
      _pill(
        canvas,
        pill,
        Rect.fromLTWH((width - pillWidth) / 2, 0, pillWidth, pillHeight),
      );
    }

    canvas.save();
    canvas.translate((width - body.width) / 2, bodyTop);
    switch (kind.shape) {
      case _PinShape.teardrop:
        _teardrop(canvas, body, kind);
      case _PinShape.disc:
        _disc(canvas, body, kind, heading);
    }
    canvas.restore();

    final ui.Image image = await recorder.endRecording().toImage(
      (width * pixelRatio).ceil(),
      (height * pixelRatio).ceil(),
    );
    final ByteData? data = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    image.dispose();

    final MarkerBitmap marker = MarkerBitmap(
      bytes: data!.buffer.asUint8List(),
      // Horizontally centred; vertically wherever the body's own anchor landed
      // once the label pushed it down the canvas.
      anchor: Offset(0.5, (bodyTop + bodyAnchorY * body.height) / height),
    );
    _cache[key] = marker;
    if (_cache.length > _maxCached) _cache.remove(_cache.keys.first);
    return marker;
  }

  /// A teardrop with the kind's icon in its head.
  ///
  /// The white keyline is not decoration. These sit on satellite imagery, whose
  /// colour is whatever the ground happens to be, and without a light edge an
  /// orange pin over an orange rooftop disappears.
  static void _teardrop(ui.Canvas canvas, Size size, ZopiqPinKind kind) {
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
  }

  /// A disc with the kind's icon in the middle — the moving marker — and, when
  /// the phone reported one, a chevron outside it pointing the way the rider is
  /// travelling.
  ///
  /// The chevron rotates; the glyph does not. That is the whole point of
  /// painting the rotation here instead of asking the SDK for it.
  static void _disc(
    ui.Canvas canvas,
    Size size,
    ZopiqPinKind kind,
    double? heading,
  ) {
    final Offset c = Offset(size.width / 2, size.height / 2);
    const double r = 18;

    if (heading != null) _chevron(canvas, c, r, heading, kind.colour);

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
  }

  /// The direction of travel, as a triangle sitting just off the disc.
  ///
  /// Drawn before the disc so its base tucks under the white collar and the two
  /// read as one marker rather than as a pin with a shape next to it.
  static void _chevron(
    ui.Canvas canvas,
    Offset centre,
    double r,
    double heading,
    Color colour,
  ) {
    canvas
      ..save()
      ..translate(centre.dx, centre.dy)
      // Bearings are degrees clockwise from north; the canvas measures from the
      // x-axis and turns the same way, so pointing the triangle at -y and
      // turning by the bearing lands it exactly where the rider is facing.
      ..rotate(heading * math.pi / 180);

    final Path path = Path()
      ..moveTo(0, -(r + 11))
      ..lineTo(-7, -(r - 1))
      ..lineTo(7, -(r - 1))
      ..close();

    canvas
      // Stroked first and filled over, which leaves half the stroke showing as
      // a keyline — the same trick the teardrop uses to survive satellite.
      ..drawPath(
        path,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeJoin = StrokeJoin.round,
      )
      ..drawPath(path, Paint()..color = colour)
      ..restore();
  }

  static const double _pillPadX = 7;
  static const double _pillPadY = 3.5;

  /// The gap between the label and the pin it belongs to.
  static const double _pillGap = 4;

  static TextPainter _pillText(String label) => TextPainter(
    textDirection: TextDirection.ltr,
    text: TextSpan(
      text: label,
      style: const TextStyle(
        color: ZopiqPalette.textDark,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        height: 1.1,
      ),
    ),
  )..layout();

  /// A small white capsule above the pin — the "06 min" callout.
  static void _pill(ui.Canvas canvas, TextPainter text, Rect rect) {
    final RRect body = RRect.fromRectAndRadius(
      rect,
      Radius.circular(rect.height / 2),
    );

    canvas
      ..drawShadow(
        Path()..addRRect(body),
        Colors.black.withValues(alpha: 0.4),
        2,
        false,
      )
      ..drawRRect(body, Paint()..color = Colors.white);

    text.paint(canvas, Offset(rect.left + _pillPadX, rect.top + _pillPadY));
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
}
