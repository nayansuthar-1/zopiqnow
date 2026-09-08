import { useCallback, useEffect, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import { api, STATUS_LABEL } from '../lib/api'
import type { OpsMap, OpsMapOrder, OpsMapRider } from '../lib/api'
import { inr } from '../lib/money'
import { PageHeader } from '../ui/AppShell'
import {
  DEFAULT_CENTRE,
  loadFailureMessage,
  loadMaps,
  mapsAvailable,
  type GMap,
  type GMarker,
  type GPolyline,
} from '../ui/maps'
import {
  Banner,
  Button,
  Card,
  EmptyState,
  PageBody,
  Pill,
  SegmentedControl,
  Skeleton,
} from '../ui/primitives'
import { useUrlState } from '../ui/urlState'

/// The floor, seen from above (0166).
///
/// `rider_locations` has been written on every job since 0057 and nobody at the
/// platform has ever seen it drawn — the customer watches their own rider move,
/// while the party that decides whether to ring a kitchen or pull a job off a
/// rider has had a text table.
///
/// **The pins are the live board, not a second opinion of it.** The order layer
/// comes through `admin_orders` inside the database, so a red pin here is red
/// for exactly the reason the board gives (0155). Nothing about "live" or "in
/// trouble" is decided in this file.
///
/// **There are no idle riders on this map, by design.** A rider's position is
/// kept only while there is a job that justifies knowing it —
/// `purge_rider_locations` drops the rest within ten minutes — so the fleet
/// counts in the header say how many are online and standing by rather than
/// leaving an admin to wonder why the map looks empty.
///
/// **It polls.** The board has a doorbell since 0156, but that rings on orders
/// and deliveries; what moves on a map is a rider, every few seconds, and no
/// trigger fires for that. Fifteen seconds is the same rhythm the board fell
/// back to and is honest about being a poll.

const REFRESH_MS = 15000

/// The map's palette, as hex because a Google marker symbol takes a colour and
/// not a CSS variable. Each one is a token from `index.css` — brand for a
/// kitchen, non-veg red for an order in trouble, veg green for a rider on the
/// road — so the map reads as the same product as the screen around it.
const COLOURS = {
  kitchen: '#fc8019',
  drop: '#5f6470',
  breach: '#e43b4f',
  rider: '#267335',
  route: '#8e8e99',
}

function minutesSince(iso: string): number {
  return Math.max(0, Math.round((Date.now() - new Date(iso).getTime()) / 60000))
}

function ago(iso: string): string {
  const m = minutesSince(iso)
  if (m < 1) return 'just now'
  if (m < 60) return `${m} min ago`
  const h = Math.floor(m / 60)
  return `${h}h ${m % 60}m ago`
}

/// A dot, as the Maps API wants it: a symbol path of 0 is its built-in circle.
function dot(colour: string, scale: number) {
  return {
    path: 0,
    scale,
    fillColor: colour,
    fillOpacity: 1,
    strokeColor: '#ffffff',
    strokeWeight: 2,
  }
}

export function OpsMapPage() {
  const [town, setTown] = useUrlState('town', '')
  const [data, setData] = useState<OpsMap | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [mapError, setMapError] = useState<string | null>(null)
  const [selected, setSelected] = useState<string | null>(null)

  const host = useRef<HTMLDivElement>(null)
  const mapRef = useRef<GMap | null>(null)
  /// Everything currently drawn, so the next draw can take it off again. There
  /// is no "clear the map" call in the API — an overlay lives until something
  /// sets its map to null, and a redraw that forgets leaves fifteen seconds of
  /// stale pins under the fresh ones.
  const drawn = useRef<(GMarker | GPolyline)[]>([])

  const load = useCallback(async () => {
    try {
      setData(await api.opsMap(town === '' ? null : town))
      setError(null)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }, [town])

  useEffect(() => {
    void load()
    const timer = setInterval(() => void load(), REFRESH_MS)
    return () => clearInterval(timer)
  }, [load])

  // The map itself, built once. Rebuilding it on every refresh would throw away
  // the zoom and the pan the admin just made, fifteen seconds after they made
  // it.
  useEffect(() => {
    if (!mapsAvailable) return
    let cancelled = false

    void loadMaps().then(
      (maps) => {
        if (cancelled || !host.current) return
        mapRef.current = new maps.Map(host.current, {
          center: DEFAULT_CENTRE,
          zoom: 12,
          mapTypeControl: false,
          streetViewControl: false,
          fullscreenControl: true,
        })
        // A first paint as soon as the map exists, rather than at the next
        // refresh: the data is usually already here by now.
        setData((d) => (d ? { ...d } : d))
      },
      (e: Error) => {
        if (!cancelled) setMapError(loadFailureMessage(e))
      },
    )

    return () => {
      cancelled = true
    }
  }, [])

  // Draw. Runs on every payload, which is every fifteen seconds.
  useEffect(() => {
    const map = mapRef.current
    const maps = window.google?.maps
    if (!map || !maps || !data) return

    for (const o of drawn.current) o.setMap(null)
    drawn.current = []

    const bounds = new maps.LatLngBounds()
    let anything = false

    for (const o of data.orders) {
      const introuble = o.breaches.length > 0
      if (o.restaurant_lat !== null && o.restaurant_lng !== null) {
        const at = { lat: o.restaurant_lat, lng: o.restaurant_lng }
        const m = new maps.Marker({
          position: at,
          map,
          title: `${o.restaurant_name} · ${o.order_id}`,
          icon: dot(introuble ? COLOURS.breach : COLOURS.kitchen, 7),
        })
        m.addListener('click', () => setSelected(o.order_id))
        drawn.current.push(m)
        bounds.extend(at)
        anything = true
      }
      if (o.delivery_lat !== null && o.delivery_lng !== null) {
        const to = { lat: o.delivery_lat, lng: o.delivery_lng }
        const m = new maps.Marker({
          position: to,
          map,
          title: `${o.delivery_to} · ${o.order_id}`,
          icon: dot(introuble ? COLOURS.breach : COLOURS.drop, 5),
        })
        m.addListener('click', () => setSelected(o.order_id))
        drawn.current.push(m)
        bounds.extend(to)
        anything = true

        if (o.restaurant_lat !== null && o.restaurant_lng !== null) {
          // The journey as the crow flies, not as the road runs. The road is
          // known for some orders (`route_polyline`) and not others, and half a
          // map drawn one way and half the other would read as two kinds of
          // fact. A straight line says "these two points belong together",
          // which is all this line is claiming.
          drawn.current.push(
            new maps.Polyline({
              map,
              path: [
                { lat: o.restaurant_lat, lng: o.restaurant_lng },
                to,
              ],
              strokeColor: introuble ? COLOURS.breach : COLOURS.route,
              strokeOpacity: 0.45,
              strokeWeight: 2,
            }),
          )
        }
      }
    }

    for (const r of data.riders) {
      const at = { lat: r.lat, lng: r.lng }
      const m = new maps.Marker({
        position: at,
        map,
        title: `${r.name}${r.order_id ? ` · ${r.order_id}` : ''} · ${ago(r.updated_at)}`,
        icon: dot(COLOURS.rider, 6),
      })
      if (r.order_id) {
        const id = r.order_id
        m.addListener('click', () => setSelected(id))
      }
      drawn.current.push(m)
      bounds.extend(at)
      anything = true
    }

    if (anything) {
      map.fitBounds(bounds, 64)
    } else {
      // Nothing to frame. The chosen town, or where we deliver at all.
      const t = data.towns.find((x) => x.id === town)
      map.setCenter(
        t ? { lat: t.centre_lat, lng: t.centre_lng } : DEFAULT_CENTRE,
      )
      map.setZoom(t ? 13 : 11)
    }
  }, [data, town])

  const orders = data?.orders ?? []
  const riders = data?.riders ?? []
  const inTrouble = orders.filter((o) => o.breaches.length > 0).length
  const chosen = orders.find((o) => o.order_id === selected) ?? null

  const townOptions = [
    { value: '', label: 'Everywhere' },
    ...(data?.towns ?? []).map((t) => ({
      value: t.id,
      label: t.is_active ? t.name : `${t.name} (closed)`,
    })),
  ]

  return (
    <>
      <PageHeader
        title="Map"
        subtitle={
          data === null
            ? 'Where every live order and every rider carrying one is.'
            : `${orders.length} live order${orders.length === 1 ? '' : 's'}${
                inTrouble > 0 ? `, ${inTrouble} in trouble` : ''
              } · ${riders.length} rider${riders.length === 1 ? '' : 's'} out · refreshed ${ago(
                data.generated_at,
              )}`
        }
        action={
          <Button variant="secondary" onClick={() => void load()}>
            Refresh
          </Button>
        }
      />

      <PageBody>
        {error && (
          <Banner
            tone="error"
            className="mb-4 max-w-2xl"
            onDismiss={() => setError(null)}
          >
            {error}
          </Banner>
        )}

        {!mapsAvailable && (
          <Banner tone="warn" className="mb-4 max-w-2xl">
            There is no <code>VITE_GOOGLE_MAPS_BROWSER_KEY</code> in this build,
            so the basemap cannot load. Everything the map would draw is listed
            below.
          </Banner>
        )}
        {mapError && (
          <Banner tone="warn" className="mb-4 max-w-2xl">
            {mapError}
          </Banner>
        )}

        <div className="mb-4 flex flex-wrap items-center gap-x-6 gap-y-3">
          <SegmentedControl
            label="Town"
            value={town}
            options={townOptions}
            onChange={setTown}
          />
          <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-ink-muted">
            <Legend colour={COLOURS.kitchen} label="kitchen" />
            <Legend colour={COLOURS.drop} label="door" />
            <Legend colour={COLOURS.rider} label="rider" />
            <Legend colour={COLOURS.breach} label="in trouble" />
          </div>
        </div>

        <div className="grid gap-5 lg:grid-cols-[1fr_22rem]">
          <div>
            {mapsAvailable && !mapError ? (
              <div
                ref={host}
                className="h-[32rem] w-full overflow-hidden rounded-card border border-line bg-canvas"
              />
            ) : null}
            {data === null && <Skeleton className="mt-4 h-24 w-full" />}
          </div>

          <div className="space-y-4">
            {data && (
              <Card className="p-5">
                <p className="text-xs font-medium tracking-wide text-ink-muted uppercase">
                  The fleet
                </p>
                <p className="mt-2 text-sm text-ink">
                  {data.fleet.online} of {data.fleet.active} riders online,{' '}
                  {data.fleet.on_a_job} carrying something.
                </p>
                {/* The sentence that stops "no riders on the map" from reading
                    as a broken query. */}
                <p className="mt-2 text-sm text-ink-muted">
                  A rider is on the map only while they hold a job — where an
                  idle rider is standing is not kept.
                </p>
              </Card>
            )}

            {chosen ? (
              <OrderCard order={chosen} onClose={() => setSelected(null)} />
            ) : orders.length === 0 ? (
              <EmptyState
                title="Nothing live"
                body={
                  town === ''
                    ? 'No order is open anywhere on the platform. The map fills itself the moment one is placed.'
                    : 'No order is open in this town right now.'
                }
              />
            ) : (
              <div className="space-y-3">
                <p className="text-xs font-medium tracking-wide text-ink-muted uppercase">
                  Live orders
                </p>
                {orders.map((o) => (
                  <button
                    key={o.order_id}
                    type="button"
                    onClick={() => setSelected(o.order_id)}
                    className="block w-full rounded-card border border-line bg-white p-4 text-left hover:border-brand"
                  >
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="font-semibold text-ink">
                        {o.order_id}
                      </span>
                      <Pill tone={o.breaches.length > 0 ? 'danger' : 'neutral'}>
                        {STATUS_LABEL[o.status]}
                      </Pill>
                    </div>
                    <p className="mt-1 text-xs text-ink-muted">
                      {o.restaurant_name} → {o.delivery_to}
                    </p>
                    {o.breaches.length > 0 && (
                      <p className="mt-1 text-xs text-non-veg-ink">
                        {o.breaches.join(', ').replace(/_/g, ' ')}
                        {o.breach_since && ` · ${ago(o.breach_since)}`}
                      </p>
                    )}
                  </button>
                ))}
              </div>
            )}

            {riders.length > 0 && !chosen && (
              <div className="space-y-3">
                <p className="text-xs font-medium tracking-wide text-ink-muted uppercase">
                  Riders out
                </p>
                {riders.map((r) => (
                  <RiderRow key={r.email} rider={r} />
                ))}
              </div>
            )}
          </div>
        </div>
      </PageBody>
    </>
  )
}

function Legend({ colour, label }: { colour: string; label: string }) {
  return (
    <span className="flex items-center gap-1.5">
      <span
        aria-hidden
        className="inline-block h-2.5 w-2.5 rounded-full"
        style={{ backgroundColor: colour }}
      />
      {label}
    </span>
  )
}

/// The order behind a pin somebody clicked. Deliberately thin: everything about
/// an order already has a page (0154), and a second full account of it here
/// would be a second thing to keep true.
function OrderCard({
  order,
  onClose,
}: {
  order: OpsMapOrder
  onClose: () => void
}) {
  return (
    <Card className="p-5">
      <div className="flex items-start justify-between gap-3">
        <div>
          <Link
            to={`/orders/${order.order_id}`}
            className="font-semibold text-ink underline decoration-line underline-offset-4 hover:decoration-brand-ink"
          >
            {order.order_id}
          </Link>
          <p className="mt-1 text-sm text-ink-muted">
            {STATUS_LABEL[order.status]} · {inr(order.total)} ·{' '}
            {ago(order.placed_at)}
          </p>
        </div>
        <Button variant="ghost" size="sm" onClick={onClose}>
          Close
        </Button>
      </div>

      {order.breaches.length > 0 && (
        <p className="mt-3 text-sm text-non-veg-ink">
          {order.breaches.join(', ').replace(/_/g, ' ')}
          {order.breach_since && ` · since ${ago(order.breach_since)}`}
        </p>
      )}

      <dl className="mt-4 space-y-2 text-sm">
        <Row label="From" value={order.restaurant_name} />
        <Row label="To" value={order.delivery_to} />
        <Row label="Customer" value={order.customer_phone} />
        <Row
          label="Rider"
          value={
            order.rider_name
              ? `${order.rider_name}${
                  order.delivery_state
                    ? ` · ${order.delivery_state.replace(/_/g, ' ')}`
                    : ''
                }`
              : 'nobody yet'
          }
        />
      </dl>
    </Card>
  )
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex gap-3">
      <dt className="w-20 shrink-0 text-ink-muted">{label}</dt>
      <dd className="wrap-break-word text-ink">{value}</dd>
    </div>
  )
}

function RiderRow({ rider }: { rider: OpsMapRider }) {
  // A position that has stopped moving is the thing worth noticing here: the
  // rider app writes one every few seconds while a job is live, so a stale one
  // means a phone that has lost signal or an app that has been killed.
  const stale = minutesSince(rider.updated_at) >= 3
  return (
    <div className="rounded-card border border-line bg-white p-4">
      <div className="flex flex-wrap items-center gap-2">
        <span className="font-semibold text-ink">{rider.name}</span>
        {rider.delivery_state && (
          <Pill tone="live">{rider.delivery_state.replace(/_/g, ' ')}</Pill>
        )}
      </div>
      <p className="mt-1 text-xs text-ink-muted">
        {rider.order_id ? `${rider.order_id} · ` : ''}
        {rider.vehicle ?? 'no vehicle on file'}
        {rider.speed_kmh !== null && ` · ${rider.speed_kmh} km/h`}
      </p>
      <p className={`mt-1 text-xs ${stale ? 'text-warn' : 'text-ink-muted'}`}>
        last heard {ago(rider.updated_at)}
      </p>
    </div>
  )
}
