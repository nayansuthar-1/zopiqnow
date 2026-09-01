/// The browser key the Maps script is loaded with, and whether there is one.
///
/// Its own module so `MapPicker.tsx` exports nothing but its component: a file
/// that exports a component *and* a constant loses fast refresh for both.
export const MAPS_KEY = import.meta.env.VITE_GOOGLE_MAPS_BROWSER_KEY as
  | string
  | undefined

/// Whether the console has a browser key at all. The button is not offered
/// without one — an "open the map" that opens a grey box with a Google error
/// across it is worse than not offering it.
export const mapPickerAvailable = Boolean(MAPS_KEY)
