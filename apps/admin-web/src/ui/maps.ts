/// The console's whole relationship with Google Maps: the key, the loader, and
/// the narrow slice of the API two screens touch.
///
/// Its own module and not a corner of `MapPicker.tsx`, for two reasons. A file
/// that exports a component *and* a constant loses fast refresh for both — that
/// is why `mapsKey.ts` existed before this. And the loader has to be shared:
/// its promise cache is the only thing stopping two screens from injecting two
/// copies of the Maps script into one page, and a second copy of the loader
/// would defeat the cache by having its own.
///
/// **No new dependency.** The script tag is injected by hand rather than pulled
/// in through `@react-google-maps/api`: this project has a standing rule against
/// adding packages without an approved upgrade task, and what is used here is a
/// map, some markers, a line and a bounds.

export const MAPS_KEY = import.meta.env.VITE_GOOGLE_MAPS_BROWSER_KEY as
  | string
  | undefined

/// Whether the console has a browser key at all. Without one the address step
/// offers no map button, and the operations map says plainly that it is missing
/// rather than drawing a grey box with a Google error across it.
export const mapsAvailable = Boolean(MAPS_KEY)

/// The slice of the Maps API this project uses, declared rather than pulled in
/// as `@types/google.maps` — same dependency rule, and a wrong guess here is a
/// type error rather than a runtime one.
export type LatLngLiteral = { lat: number; lng: number }

export type GLatLng = { lat(): number; lng(): number }

export type GMarker = {
  setPosition(p: LatLngLiteral): void
  addListener(event: string, handler: () => void): void
  getPosition(): GLatLng | null
  /// `setMap(null)` is how a marker is removed — there is no `remove()`, and a
  /// marker dropped without it stays on the map for the life of the page.
  setMap(map: GMap | null): void
}

export type GPolyline = {
  setMap(map: GMap | null): void
}

export type GBounds = {
  extend(p: LatLngLiteral): void
  isEmpty(): boolean
}

export type GMap = {
  addListener(event: string, handler: (e: { latLng: GLatLng | null }) => void): void
  setCenter(p: LatLngLiteral): void
  setZoom(z: number): void
  fitBounds(bounds: GBounds, padding?: number): void
}

export type MapsApi = {
  Map: new (el: HTMLElement, options: Record<string, unknown>) => GMap
  Marker: new (options: Record<string, unknown>) => GMarker
  Polyline: new (options: Record<string, unknown>) => GPolyline
  LatLngBounds: new () => GBounds
}

declare global {
  interface Window {
    google?: { maps?: MapsApi }
  }
}

/// Where a map opens when it has nothing of its own to show.
///
/// Sadri, which with Ranakpur and Falna is where Zopiqnow actually delivers. A
/// map that opens on the whole of India costs four zoom gestures before anybody
/// can see a street, every single time.
export const DEFAULT_CENTRE: LatLngLiteral = { lat: 25.1846, lng: 73.4419 }

/// Loads the Maps script once and resolves when `window.google.maps` exists.
///
/// Cached as a promise rather than a boolean so that two screens opened in one
/// session share the single in-flight load instead of racing to inject two
/// script tags.
let loader: Promise<MapsApi> | null = null

export function loadMaps(): Promise<MapsApi> {
  if (window.google?.maps) return Promise.resolve(window.google.maps)
  if (loader) return loader

  loader = new Promise<MapsApi>((resolve, reject) => {
    const script = document.createElement('script')
    script.src = `https://maps.googleapis.com/maps/api/js?key=${MAPS_KEY}&v=weekly`
    script.async = true
    script.onload = () => {
      const maps = window.google?.maps
      if (maps) resolve(maps)
      // A 200 that is not the API: the usual cause is a key that has the Maps
      // JavaScript API switched off in the Cloud console, which loads a script
      // whose only job is to log an error.
      else reject(new Error('maps-unavailable'))
    }
    script.onerror = () => reject(new Error('maps-unreachable'))
    document.head.appendChild(script)
  })
  // A failed load must not be cached, or the second attempt resolves the first
  // failure for ever.
  loader.catch(() => {
    loader = null
  })
  return loader
}

/// The same two sentences both screens say when the script does not come back.
export function loadFailureMessage(e: Error): string {
  return e.message === 'maps-unavailable'
    ? 'Google Maps loaded but refused the key. Check that the Maps JavaScript API is enabled for it, and that this domain is allowed.'
    : 'Google Maps could not be reached. Check the connection and try again.'
}
