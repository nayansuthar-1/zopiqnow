/// The basemap's look: quiet, pale, and almost colourless.
///
/// **Why style the map at all.** Google's default basemap is a tourist map —
/// saturated green parks, yellow arterials, a hospital icon on every corner. On
/// a delivery screen that is all noise competing with the two things that
/// matter: the orange route and the pins at either end of it. Draining the
/// ground makes the route the brightest thing on screen without making the route
/// any brighter, which is the only way to win that fight on a phone in daylight.
///
/// This is the same call Zomato and Swiggy both make, and the reference the
/// design was taken from: a near-white land mass, white roads with a soft grey
/// casing, grey type, and no points of interest at all.
///
/// **One string, three apps, both platforms.** `google_maps_flutter` passes this
/// to the native SDK on Android and iOS alike, so the customer's tracking map,
/// the rider's navigation map and anything the vendor app grows later are all
/// styled by editing this file.
///
/// **What is deliberately kept.**
///   * Road geometry and road labels — a rider reads street names off this.
///   * Water, at a hair more contrast than the land, because a route that
///     crosses a river should look like it crosses a river.
///   * Transit *lines* are dropped but station labels are not, since they are
///     the landmarks people actually give directions by.
///
/// **What is dropped.** Every `poi` fill and icon, business labels, park green,
/// and the administrative colour wash. None of them help somebody find a gate.
library;

/// A Google Maps style JSON, ready for `GoogleMap(style: ...)`.
///
/// Kept as a raw string rather than built from a Dart structure: this is the
/// exact format Google's Styling Wizard emits and consumes, so it can be pasted
/// into the wizard to be edited and pasted back without a translation step in
/// the middle.
const String zopiqMapStyle = '''
[
  {
    "elementType": "geometry",
    "stylers": [{ "color": "#f5f5f5" }]
  },
  {
    "elementType": "labels.icon",
    "stylers": [{ "visibility": "off" }]
  },
  {
    "elementType": "labels.text.fill",
    "stylers": [{ "color": "#8a8a8a" }]
  },
  {
    "elementType": "labels.text.stroke",
    "stylers": [{ "color": "#f5f5f5" }]
  },
  {
    "featureType": "administrative",
    "elementType": "geometry",
    "stylers": [{ "visibility": "off" }]
  },
  {
    "featureType": "administrative.land_parcel",
    "stylers": [{ "visibility": "off" }]
  },
  {
    "featureType": "administrative.locality",
    "elementType": "labels.text.fill",
    "stylers": [{ "color": "#6b6b6b" }]
  },
  {
    "featureType": "administrative.neighborhood",
    "elementType": "labels.text.fill",
    "stylers": [{ "color": "#8a8a8a" }]
  },
  {
    "featureType": "poi",
    "stylers": [{ "visibility": "off" }]
  },
  {
    "featureType": "poi.park",
    "elementType": "geometry",
    "stylers": [{ "color": "#eceff0" }, { "visibility": "on" }]
  },
  {
    "featureType": "road",
    "elementType": "geometry",
    "stylers": [{ "color": "#ffffff" }]
  },
  {
    "featureType": "road",
    "elementType": "geometry.stroke",
    "stylers": [{ "color": "#e6e6e6" }]
  },
  {
    "featureType": "road",
    "elementType": "labels.text.fill",
    "stylers": [{ "color": "#9a9a9a" }]
  },
  {
    "featureType": "road.arterial",
    "elementType": "geometry",
    "stylers": [{ "color": "#ffffff" }]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry",
    "stylers": [{ "color": "#ffffff" }]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry.stroke",
    "stylers": [{ "color": "#dcdcdc" }]
  },
  {
    "featureType": "road.local",
    "elementType": "labels.text.fill",
    "stylers": [{ "color": "#a8a8a8" }]
  },
  {
    "featureType": "transit",
    "elementType": "geometry",
    "stylers": [{ "visibility": "off" }]
  },
  {
    "featureType": "transit.station",
    "elementType": "labels.text.fill",
    "stylers": [{ "color": "#8a8a8a" }]
  },
  {
    "featureType": "water",
    "elementType": "geometry",
    "stylers": [{ "color": "#dfe6e8" }]
  },
  {
    "featureType": "water",
    "elementType": "labels.text",
    "stylers": [{ "visibility": "off" }]
  }
]
''';
