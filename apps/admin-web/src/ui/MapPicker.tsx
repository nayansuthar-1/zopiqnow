import { useEffect, useRef, useState } from 'react'
import {
  DEFAULT_CENTRE,
  loadFailureMessage,
  loadMaps,
  type GMarker,
  type LatLngLiteral,
} from './maps'
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
/// **No new dependency, and no second loader.** The Maps script is injected by
/// hand rather than pulled in through `@react-google-maps/api` — this project
/// has a standing rule against adding packages without an approved upgrade task.
/// The key, that loader and the slice of the API this project declares for
/// itself all live in `ui/maps.ts`, because the operations map (0166) draws
/// through them too and two copies of the loader would each cache their own
/// script tag.

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
        setFailed(loadFailureMessage(e))
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
            className="h-[420px] w-full overflow-hidden rounded-field border border-line bg-canvas"
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
