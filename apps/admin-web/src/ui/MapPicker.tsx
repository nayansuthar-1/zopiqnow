import { useEffect, useRef, useState } from 'react'
import { Button, Modal } from './primitives'

/// Drop a pin on the kitchen instead of typing two numbers.
///
/// **Why this matters more than it looks.** `latitude`/`longitude` are not
/// decoration: dispatch offers a job to the nearest rider by distance from these
/// coordinates (0099), the rider is *paid* on the road distance measured from
/// them (0046), and the customer's arrival time is computed against them (0057).
/// A transposed pair or a digit dropped from a hand-typed number puts a kitchen
/// in the sea, and every one of those three goes quietly wrong rather than
/// failing. The step's own hint used to be "right-click in Google Maps and copy
/// the pair it shows", which is exactly the manual transcription this removes.
///
/// **No new dependency.** The Maps JavaScript API is loaded by injecting its
/// script tag, once per page, rather than through `@react-google-maps/api` —
/// this project has a standing rule against adding packages without an approved
/// upgrade task, and the whole of what is used here is a map, a marker and two
/// listeners.

/// The narrow slice of the Maps API this file touches, declared rather than
/// pulled in as `@types/google.maps` — for the same reason as above, and because
/// a wrong guess here is a type error rather than a runtime one.
type LatLngLiteral = { lat: number; lng: number }

type GLatLng = { lat(): number; lng(): number }
type GMarker = {
  setPosition(p: LatLngLiteral): void
  addListener(event: string, handler: () => void): void
  getPosition(): GLatLng | null
}
type GMap = {
  addListener(event: string, handler: (e: { latLng: GLatLng | null }) => void): void
  setCenter(p: LatLngLiteral): void
  setZoom(z: number): void
}
type MapsApi = {
  Map: new (el: HTMLElement, options: Record<string, unknown>) => GMap
  Marker: new (options: Record<string, unknown>) => GMarker
}

declare global {
  interface Window {
    google?: { maps?: MapsApi }
  }
}

const KEY = import.meta.env.VITE_GOOGLE_MAPS_BROWSER_KEY as string | undefined

/// Where the map opens when the restaurant has no coordinates yet.
///
/// Sadri, which with Ranakpur is where Zopiqnow actually delivers today. A map
/// that opens on the whole of India costs the admin four zoom gestures before
/// they can see a street, every single time.
const DEFAULT_CENTRE: LatLngLiteral = { lat: 25.1846, lng: 73.4419 }

/// Whether the console has a browser key at all. The button is not offered
/// without one — an "open the map" that opens a grey box with a Google error
/// across it is worse than not offering it.
export const mapPickerAvailable = Boolean(KEY)

/// Loads the Maps script once and resolves when `window.google.maps` exists.
///
/// Cached as a promise rather than a boolean so that two pickers opened in one
/// session share the single in-flight load instead of racing to inject two
/// script tags.
let loader: Promise<MapsApi> | null = null

function loadMaps(): Promise<MapsApi> {
  if (window.google?.maps) return Promise.resolve(window.google.maps)
  if (loader) return loader

  loader = new Promise<MapsApi>((resolve, reject) => {
    const script = document.createElement('script')
    script.src = `https://maps.googleapis.com/maps/api/js?key=${KEY}&v=weekly`
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

export function MapPicker({
  /// Where the pin starts, or null for a restaurant with no coordinates yet.
  initial,
  onCancel,
  onPick,
}: {
  initial: LatLngLiteral | null
  onCancel: () => void
  onPick: (p: LatLngLiteral) => void
}) {
  const host = useRef<HTMLDivElement>(null)
  const [pin, setPin] = useState<LatLngLiteral | null>(initial)
  const [failed, setFailed] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false

    void loadMaps().then(
      (maps) => {
        if (cancelled || !host.current) return

        const centre = initial ?? DEFAULT_CENTRE
        const map = new maps.Map(host.current, {
          center: centre,
          // Close enough to tell one shopfront from the next when we know where
          // we are; wider when we are guessing at a town.
          zoom: initial ? 18 : 14,
          mapTypeControl: true,
          streetViewControl: false,
          fullscreenControl: false,
        })

        // Dragging needs something to drag, so the pin exists from the start
        // *only* when the restaurant already has coordinates. With none, the
        // map opens bare: a pin drawn on the default centre would sit there
        // looking placed while "Use this location" stayed dead, because nobody
        // had chosen anything — and the one thing worse than no pin is a pin
        // that means nothing and is one click from becoming a kitchen's
        // official location.
        let marker: GMarker | null = null

        function place(p: LatLngLiteral) {
          if (marker) {
            marker.setPosition(p)
          } else {
            marker = new maps.Marker({ position: p, map, draggable: true })
            marker.addListener('dragend', () => {
              const q = marker?.getPosition()
              if (q) setPin({ lat: q.lat(), lng: q.lng() })
            })
          }
          setPin(p)
        }

        if (initial) place(initial)

        // Two ways to place it, because both are things people try: drag the
        // pin, or click where it should be.
        map.addListener('click', (e) => {
          if (e.latLng) place({ lat: e.latLng.lat(), lng: e.latLng.lng() })
        })
      },
      (e: Error) => {
        if (cancelled) return
        setFailed(
          e.message === 'maps-unavailable'
            ? 'Google Maps loaded but refused the key. Check that the Maps JavaScript API is enabled for it, and that this domain is allowed.'
            : 'Google Maps could not be reached. Check the connection and try again.',
        )
      },
    )

    return () => {
      cancelled = true
    }
    // Deliberately once: re-running this would build a second map over the
    // first. `initial` is only ever read to place the opening view.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return (
    <Modal
      title="Pick the kitchen on the map"
      size="lg"
      onClose={onCancel}
      footer={
        <>
          <Button variant="secondary" onClick={onCancel}>
            Cancel
          </Button>
          <Button disabled={!pin} onClick={() => pin && onPick(pin)}>
            Use this location
          </Button>
        </>
      }
    >
      {failed ? (
        <p className="text-sm text-ink-muted">{failed}</p>
      ) : (
        <div className="space-y-3">
          <div
            ref={host}
            className="h-[420px] w-full overflow-hidden rounded-[8px] border border-line bg-canvas"
          />
          <p className="text-sm text-ink-muted">
            {pin
              ? `Pin at ${pin.lat.toFixed(6)}, ${pin.lng.toFixed(6)} — drag it or click the map to move it.`
              : 'Click the map, or drag the pin, to mark the kitchen door.'}
          </p>
          <p className="text-sm text-ink-muted">
            Riders are paid by road distance from this point and dispatch offers each
            job to the nearest one, so put it on the kitchen rather than on the
            street or the mall it is inside.
          </p>
        </div>
      )}
    </Modal>
  )
}
