import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_ui/zopiq_ui.dart';

import 'package:zopiqnow/features/checkout/domain/entities/delivery_route.dart';
import 'package:zopiqnow/features/checkout/domain/entities/order_rider.dart';
import 'package:zopiqnow/features/checkout/presentation/providers/orders_providers.dart';

/// The rider, on the road, moving.
///
/// **Why this is painted and not a map widget.** Every real map needs tiles, and
/// tiles need a key in the app. Ours is Ola's, it is referer-restricted, and it
/// lives in Vault precisely so it never ships inside an APK (0046). Shipping it
/// to draw a background would undo that in one commit. A tile package would also
/// be a new dependency, which the version freeze does not allow without an
/// approved upgrade task.
///
/// So it draws what it can actually stand behind: the **real road**, decoded
/// from the `overview_polyline` Ola already returns and 0057 already stores, the
/// two ends of the ride, and the rider's live position along it. No street
/// names, no landmarks, no satellite — and no pretence of them. It answers the
/// question a customer opens this screen with ("how far away are they, and are
/// they moving?") and does not pretend to answer the one it cannot ("what street
/// is that?"), which is what a half-loaded tile map does.
///
/// **What it never does.** It does not draw a rider before there is one, it does
/// not keep drawing one whose position has gone stale (see
/// [RiderPosition.isStale]), and it does not interpolate a dot along the route
/// between fixes. A dot that keeps gliding after the rider's phone died is the
/// single most convincing lie a tracking screen can tell.
class LiveDeliveryMap extends ConsumerWidget {
  const LiveDeliveryMap({
    required this.route,
    required this.rider,
    super.key,
  });

  final DeliveryRoute route;

  /// Who is carrying it, or null while nobody is. Supplies the subscription key
  /// and the label under the dot — and its absence is what makes this a map of
  /// the ride ahead rather than of a ride in progress.
  final OrderRider? rider;

  static const double _height = 190;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!route.isMappable) return const SizedBox.shrink();

    final ZopiqColors zc = context.zc;
    final String? key = rider?.carrierKey;

    final RiderPosition? position = key == null
        ? null
        : ref.watch(riderPositionProvider(key)).valueOrNull;

    // A fix older than two minutes is drawn as nothing rather than as a rider.
    final RiderPosition? live =
        position != null && !position.isStale(DateTime.now()) ? position : null;

    return ClipRRect(
      borderRadius: ZopiqRadii.rMd,
      child: SizedBox(
        height: _height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // The size the painter is given is the size it fits the route into,
            // so the whole ride is always on screen — there is no pan and no
            // zoom, deliberately. This is a glance, not a map to explore.
            CustomPaint(
              painter: _RoutePainter(
                route: route,
                rider: live?.point,
                heading: live?.heading,
                road: zc.primary,
                pinStart: zc.textMuted,
                pinEnd: zc.primary,
                surface: Theme.of(context).colorScheme.surface,
                grid: zc.divider,
              ),
            ),
            if (position != null && live == null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _Caption(
                  // Said plainly rather than hidden. The customer can see the
                  // dot is gone; not saying why is worse than saying this.
                  text: 'Live location paused — reconnecting',
                  color: zc.textMuted,
                ),
              )
            else if (live == null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _Caption(
                  text: rider == null
                      ? 'The route your order will take'
                      : 'Waiting for ${rider!.name}\'s location',
                  color: zc.textMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A one-line strip along the bottom of the map, for the times there is no dot.
class _Caption extends StatelessWidget {
  const _Caption({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZopiqSpacing.md,
        vertical: ZopiqSpacing.xs,
      ),
      color: Theme.of(
        context,
      ).colorScheme.surface.withValues(alpha: 0.85),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: color),
      ),
    );
  }
}

/// Everything on the map, in one pass.
///
/// The projection is deliberately naive — longitude scaled by `cos(lat)` and
/// then fitted to the box. At the scale of a food delivery (single-digit
/// kilometres) that is indistinguishable from Web Mercator, and it is twenty
/// lines instead of a dependency.
class _RoutePainter extends CustomPainter {
  const _RoutePainter({
    required this.route,
    required this.rider,
    required this.heading,
    required this.road,
    required this.pinStart,
    required this.pinEnd,
    required this.surface,
    required this.grid,
  });

  final DeliveryRoute route;
  final GeoPoint? rider;
  final double? heading;
  final Color road;
  final Color pinStart;
  final Color pinEnd;
  final Color surface;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final GeoPoint? destination = route.destination;
    if (destination == null) return;

    // Everything that has to be visible decides the frame. The rider is in it,
    // so a rider who has wandered off the quoted route does not sail off the
    // edge of the picture.
    final List<GeoPoint> framed = <GeoPoint>[
      destination,
      ?route.restaurant,
      ...route.path,
      ?rider,
    ];

    final ({double minLat, double maxLat, double minLng, double maxLng})
    bounds = boundsOf(framed);
    if (bounds.maxLat == bounds.minLat && bounds.maxLng == bounds.minLng) {
      return;
    }

    // Longitude compresses towards the poles. Without this, a route running
    // east-west is drawn longer than the same route running north-south.
    final double latScale = math.cos(
      ((bounds.minLat + bounds.maxLat) / 2) * math.pi / 180,
    );

    final double spanLat = bounds.maxLat - bounds.minLat;
    final double spanLng = (bounds.maxLng - bounds.minLng) * latScale;

    // One scale for both axes, so the road keeps its shape. Fitting each axis
    // independently would stretch a straight highway into a diagonal.
    final double scale = math.min(
      size.width / math.max(spanLng, 1e-9),
      size.height / math.max(spanLat, 1e-9),
    );
    final double offsetX = (size.width - spanLng * scale) / 2;
    final double offsetY = (size.height - spanLat * scale) / 2;

    Offset project(GeoPoint p) => Offset(
      offsetX + (p.lng - bounds.minLng) * latScale * scale,
      // Latitude grows north and canvas y grows down.
      offsetY + (bounds.maxLat - p.lat) * scale,
    );

    _paintBackdrop(canvas, size);

    // The road. Ola's shape when we have it; the straight line between the pins
    // when we do not — which is a sketch, and reads like one because it is
    // dashed rather than solid.
    final List<GeoPoint> path = route.path;
    if (path.length >= 2) {
      final Path line = Path()
        ..moveTo(project(path.first).dx, project(path.first).dy);
      for (final GeoPoint p in path.skip(1)) {
        final Offset o = project(p);
        line.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = road.withValues(alpha: 0.85),
      );
    } else if (route.restaurant != null) {
      _dashed(
        canvas,
        project(route.restaurant!),
        project(destination),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = road.withValues(alpha: 0.5),
      );
    }

    if (route.restaurant != null) {
      _pin(canvas, project(route.restaurant!), pinStart, filled: false);
    }
    _pin(canvas, project(destination), pinEnd, filled: true);

    if (rider != null) _rider(canvas, project(rider!));
  }

  /// A faint grid, so the map reads as a map and not as a line on a card. It
  /// carries no information and is drawn faint enough to say so.
  void _paintBackdrop(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = grid.withValues(alpha: 0.18),
    );

    final Paint hair = Paint()
      ..color = surface.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    const double step = 28;
    for (double x = step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), hair);
    }
    for (double y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), hair);
    }
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    const double dash = 7;
    const double gap = 5;
    final double total = (b - a).distance;
    if (total <= 0) return;
    final Offset step = (b - a) / total;
    for (double d = 0; d < total; d += dash + gap) {
      canvas.drawLine(
        a + step * d,
        a + step * math.min(d + dash, total),
        paint,
      );
    }
  }

  void _pin(Canvas canvas, Offset at, Color color, {required bool filled}) {
    canvas
      ..drawCircle(at, 9, Paint()..color = surface)
      ..drawCircle(
        at,
        7,
        Paint()
          ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = color,
      );
  }

  /// The rider: a white-ringed disc, with a nose in the direction of travel when
  /// the phone reported one. No arrow at all when it did not — a bearing of zero
  /// drawn as "due north" is a fact the platform does not have.
  void _rider(Canvas canvas, Offset at) {
    canvas
      ..drawCircle(at, 12, Paint()..color = road.withValues(alpha: 0.18))
      ..drawCircle(at, 8, Paint()..color = surface)
      ..drawCircle(at, 6, Paint()..color = road);

    final double? bearing = heading;
    if (bearing == null) return;

    // Screen angles run clockwise from east; a compass bearing runs clockwise
    // from north.
    final double radians = (bearing - 90) * math.pi / 180;
    final Offset nose =
        at + Offset(math.cos(radians), math.sin(radians)) * 13;
    canvas.drawCircle(nose, 3, Paint()..color = road);
  }

  @override
  bool shouldRepaint(_RoutePainter old) =>
      old.rider != rider ||
      old.heading != heading ||
      old.route != route ||
      old.road != road;
}
