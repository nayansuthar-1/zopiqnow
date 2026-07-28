import 'package:flutter/material.dart';

import 'package:zopiq_ui/src/theme/zopiq_colors.dart';
import 'package:zopiq_ui/src/tokens/zopiq_palette.dart';

/// A pin on the map, in the app's own terms rather than the map provider's.
@immutable
class ZopiqMapMarker {
  const ZopiqMapMarker({
    required this.lat,
    required this.lng,
    required this.color,
  });

  final double lat;
  final double lng;
  final Color color;

  /// `lng,lat,rrggbb` — the shape `ola-static` parses.
  ///
  /// **Longitude first.** Every map API in this stack puts it that way and
  /// every human writes it the other, which is precisely why the conversion
  /// lives in one method instead of at each call site.
  ///
  /// Rounded to four decimals, about eleven metres. Positions arrive filtered
  /// to thirty metres of movement already (`RiderLocationReporter`), so this
  /// removes nothing real — what it removes is a fresh URL, and therefore a
  /// fresh download, for two fixes that would draw the identical picture.
  String get wire {
    final String hex = (color.toARGB32() & 0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0');
    return '${lng.toStringAsFixed(4)},${lat.toStringAsFixed(4)},$hex';
  }
}

/// A real map, with our route drawn on it.
///
/// **Why an image and not a map widget.** The map is Ola's, and the key that
/// opens it is referer-restricted — which is a browser control, so shipping the
/// key inside an APK would leave it unprotected in any sense that matters. It
/// stays on the server, and the `ola-static` Edge Function returns a finished
/// PNG with the road and the pins already drawn on it. Ola's own tiles are
/// vector (`.pbf`) and would need a renderer on the device: a large new
/// dependency, which the version freeze does not allow without an approved
/// upgrade task.
///
/// So this is a picture of a map rather than a map you can pinch. That is the
/// honest trade, and it is why every screen using this keeps a way to open the
/// rider's or customer's own maps app for the things a picture cannot do.
///
/// **Nothing is overlaid on it.** The road, both ends and the live rider are all
/// drawn by the same renderer in the same projection, so there is no second
/// coordinate system to keep in step with the first and no dot that can drift a
/// few pixels off the road it is supposed to be on.
///
/// **It does not blink.** `gaplessPlayback` holds the last good frame while the
/// next one loads, so a rider moving thirty metres redraws the map rather than
/// flashing a spinner through it every twenty seconds.
class ZopiqStaticMap extends StatelessWidget {
  const ZopiqStaticMap({
    required this.endpoint,
    required this.authToken,
    this.encodedPolyline,
    this.markers = const <ZopiqMapMarker>[],
    this.caption,
    super.key,
  });

  /// The `ola-static` function's URL. Passed in rather than built here so this
  /// package keeps knowing nothing about Supabase.
  final String endpoint;

  /// The caller's Supabase access token. The function is behind the platform's
  /// JWT check, so the map quota is only ever spent on a signed-in person.
  final String authToken;

  /// The route, as the encoded polyline Ola returned and 0046 stored. Null draws
  /// a map framed on the markers alone, which is the right picture for a job
  /// whose route has not come back yet.
  final String? encodedPolyline;

  final List<ZopiqMapMarker> markers;

  /// A line along the bottom, for the times the picture needs a word of
  /// explanation ("Waiting for Rahul's location").
  final Widget? caption;

  /// Ola renders up to 1024 a side. Asking for more spends the quota on pixels
  /// no phone can show.
  static const int _maxPixels = 1024;

  @override
  Widget build(BuildContext context) {
    if (encodedPolyline == null && markers.isEmpty) {
      return const SizedBox.shrink();
    }

    final ZopiqColors zc = context.zc;
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Physical pixels, not logical ones: a 3x phone given a 400-logical-pixel
        // map should be sent a 1200-pixel image or the road is a soft orange
        // smear. Clamped at both ends — an unbounded constraint (inside a
        // scrollable that has not measured yet) must not become a request for
        // an infinitely wide picture.
        final double ratio = MediaQuery.devicePixelRatioOf(context);
        final int width = _pixels(constraints.maxWidth, ratio, 600);
        final int height = _pixels(constraints.maxHeight, ratio, 400);

        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Image.network(
              _url(width: width, height: height, dark: dark),
              headers: <String, String>{'Authorization': 'Bearer $authToken'},
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (BuildContext context, Object _, StackTrace? _) =>
                  _Unavailable(zc: zc),
              loadingBuilder:
                  (BuildContext context, Widget child, ImageChunkEvent? p) =>
                      p == null ? child : _Loading(zc: zc),
            ),
            if (caption != null)
              Positioned(left: 0, right: 0, bottom: 0, child: caption!),
          ],
        );
      },
    );
  }

  static int _pixels(double logical, double ratio, int fallback) {
    if (!logical.isFinite || logical <= 0) return fallback;
    return (logical * ratio).round().clamp(64, _maxPixels);
  }

  String _url({
    required int width,
    required int height,
    required bool dark,
  }) {
    final Uri base = Uri.parse(endpoint);
    return base.replace(
      queryParameters: <String, dynamic>{
        ...base.queryParameters,
        'w': '$width',
        'h': '$height',
        'style': dark ? 'dark' : 'light',
        // The road in brand orange, and wide enough to read at a glance on a
        // phone strapped to a handlebar.
        'stroke': ZopiqPalette.primary
            .toARGB32()
            .toRadixString(16)
            .padLeft(8, '0')
            .substring(2),
        'width': '5',
        'path': ?encodedPolyline,
        if (markers.isNotEmpty)
          'm': markers.map((ZopiqMapMarker m) => m.wire).toList(),
      },
    ).toString();
  }
}

class _Loading extends StatelessWidget {
  const _Loading({required this.zc});

  final ZopiqColors zc;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: zc.divider.withValues(alpha: 0.35),
      child: Center(
        child: SizedBox(
          height: 22,
          width: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: zc.textMuted),
        ),
      ),
    );
  }
}

/// The map could not be fetched. Says so, rather than showing an empty grey box
/// that reads as "there is no route".
class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.zc});

  final ZopiqColors zc;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: zc.divider.withValues(alpha: 0.35),
      child: Center(
        child: Text(
          'Map unavailable',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: zc.textMuted),
        ),
      ),
    );
  }
}
