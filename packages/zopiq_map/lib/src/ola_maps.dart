import 'package:maplibre_gl/maplibre_gl.dart';

/// Ola's tile service, and how this app is allowed to talk to it.
///
/// **Why the map is Ola's and the renderer is MapLibre's.** Ola's mobile stack
/// *is* MapLibre — their styles are MapLibre Style Spec v8 documents and their
/// own Android SDK embeds MapLibre Native. Driving MapLibre directly is
/// therefore not a workaround for the absence of a Flutter SDK; it is the same
/// engine, without an unmaintained wrapper in the middle. (There is one on
/// pub.dev. It is Android-only, two years stale, and has three likes.)
///
/// **How the key travels.** Ola authenticates a tile request three ways: an
/// `api_key` query parameter, an OAuth bearer token, or an `X-API-Key` header.
/// This uses the header, and that choice is load-bearing rather than
/// stylistic — MapLibre derives dozens of URLs from a style document it fetched
/// itself (the TileJSON, every vector tile, `sprite.json`, `sprite@2x.png`,
/// a glyph range per font per 256 codepoints). A query parameter would have to
/// be threaded into all of them, and the sprite is where that comes apart:
/// MapLibre appends `.json` and `@2x.png` to the sprite URL, so a key parked in
/// a query string becomes `?api_key=KEY.json` and Ola answers 401. A header
/// applies to every request the renderer makes without any URL being rewritten.
///
/// Ola's key is additionally referer-restricted — a request with no `Origin` is
/// refused outright — so that header is sent too. It is worth being plain about
/// what that restriction is worth here: it is a browser control, and a native
/// app can send whatever `Origin` it likes. It is satisfied, not relied upon.
/// The key ships inside the APK because a vector map has to fetch its own
/// tiles, and no client-side arrangement changes that.
abstract final class OlaMaps {
  /// The `Origin` Ola's key is restricted to.
  static const String _origin = 'https://zopiqnow.app';

  static const String _styleBase = 'https://api.olamaps.io/tiles/v1/styles';

  /// Whether a key was supplied at build time. A map with no key would render
  /// as an empty grey rectangle with no explanation, so [ZopiqMapView] checks
  /// this and says what is wrong instead.
  static bool get isConfigured => _configured;
  static bool _configured = false;

  /// Installs the credentials MapLibre sends with every map request — style
  /// documents, TileJSON, vector tiles, sprites and glyphs alike.
  ///
  /// Call once, before the first map is built. It is a static on the platform
  /// channel, so it outlives any individual map and does not need repeating per
  /// screen.
  static Future<void> configure(String apiKey) async {
    if (apiKey.isEmpty) return;
    await setHttpHeaders(<String, String>{
      'Origin': _origin,
      'X-API-Key': apiKey,
    });
    _configured = true;
  }

  /// The layers a person can choose between.
  ///
  /// Ola publishes 45 styles; these are the three worth a place in a switcher.
  /// The rest are language variants of [map] and decorative themes that would
  /// make the control a menu of paint rather than a menu of information.
  ///
  /// There is no terrain option because Ola has no terrain tiles.
  static String urlFor(ZopiqMapLayer layer, {required bool dark}) =>
      switch (layer) {
        ZopiqMapLayer.map => dark
            ? '$_styleBase/default-dark-standard/style.json'
            : '$_styleBase/default-light-standard/style.json',
        ZopiqMapLayer.satellite =>
          '$_styleBase/default-dark-standard-satellite/style.json',
      };
}

/// What the map is showing underneath the route.
enum ZopiqMapLayer {
  /// Roads, names and landmarks, in the app's own light or dark theme.
  map,

  /// Aerial imagery with Ola's road and label layers still drawn over it —
  /// Google would call this "hybrid", and the distinction matters here.
  ///
  /// **Read this before widening its use.** Ola's imagery has a hard ceiling of
  /// zoom 14 (its TileJSON says so, and the tiles bear it out: a z14 tile of
  /// central Bengaluru is 146 KB of real detail, the z17 tile over the same
  /// ground is 5 KB of stretched pixels). Zoom past a neighbourhood and the
  /// photograph turns to mush.
  ///
  /// It is offered anyway, and honestly, because the imagery is not the only
  /// thing on this layer. Ola's style draws its full vector road and label set
  /// on top, and vector data is resolution-independent — so at the zoom a rider
  /// actually navigates at, the streets, the names and the route stay sharp and
  /// the photograph is a soft backdrop behind them. That is a real layer with a
  /// known limit, which is a different thing from a broken one.
  satellite;

  String get label => switch (this) {
    ZopiqMapLayer.map => 'Map',
    ZopiqMapLayer.satellite => 'Satellite',
  };
}
