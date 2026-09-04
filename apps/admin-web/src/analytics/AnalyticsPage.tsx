import { useCallback, useEffect, useRef, useState } from 'react'
import type { KeyboardEvent } from 'react'
import { api } from '../lib/api'
import type { DailyOrders, PlatformStats, TopRestaurant } from '../lib/api'
import { PageHeader } from '../ui/AppShell'
import {
  Banner,
  Card,
  DataTable,
  PageBody,
  SegmentedControl,
  Skeleton,
  StatTile,
  Td,
  Th,
} from '../ui/primitives'
import { inr } from '../lib/money'

/// The platform's own numbers. The vendor app has had a restaurant's since
/// migration 0017; nobody has ever been able to ask how the whole thing is
/// doing, which is a strange thing to be unable to ask from the platform's own
/// console.
///
/// Everything is derived on every call — there is no rollup table and there
/// should not be one at this volume. 0062's argument about `restaurants.rating`
/// holds for a dashboard too: a figure somebody stores is a figure that can be
/// wrong, and the only tile here that cannot lie is one computed from the rows
/// underneath it every time it is drawn.
///
/// **The chart is drawn, not plotted.** An SVG polyline over `admin_daily_orders`
/// is about thirty lines; a charting library is a new dependency, and Rule 4
/// makes that an explicit request, not a convenience.

const RANGES = [7, 30, 90] as const

export function AnalyticsPage() {
  const [days, setDays] = useState<number>(30)
  const [stats, setStats] = useState<PlatformStats | null>(null)
  const [series, setSeries] = useState<DailyOrders[] | null>(null)
  const [top, setTop] = useState<TopRestaurant[] | null>(null)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async (d: number) => {
    try {
      const [s, series, t] = await Promise.all([
        api.platformStats(d),
        api.dailyOrders(d),
        api.topRestaurants(d, 10),
      ])
      setStats(s[0] ?? null)
      setSeries(series)
      setTop(t)
      setError(null)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }, [])

  useEffect(() => {
    void load(days)
  }, [load, days])

  return (
    <>
      <PageHeader
        title="Platform"
        subtitle={
          stats
            ? `${stats.live_orders} order${stats.live_orders === 1 ? '' : 's'} open right now · ${stats.riders_carrying} rider${stats.riders_carrying === 1 ? '' : 's'} on the road`
            : 'Everything, across every restaurant.'
        }
      />

      <PageBody className="space-y-6">
        {error && (
          <Banner tone="error" className="max-w-2xl" onDismiss={() => setError(null)}>
            {error}
          </Banner>
        )}

        <SegmentedControl
          label="Time range"
          value={String(days)}
          onChange={(v) => setDays(Number(v))}
          options={RANGES.map((d) => ({
            value: String(d),
            label: `Last ${d} days`,
          }))}
        />

        {stats === null ? (
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            {Array.from({ length: 8 }, (_, i) => (
              <Card key={i}>
                <Skeleton className="h-3 w-20" />
                <Skeleton className="mt-3 h-7 w-28" />
                <Skeleton className="mt-2 h-3 w-32" />
              </Card>
            ))}
          </div>
        ) : (
          <>
            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
              <StatTile
                label="Delivered"
                value={String(stats.orders_delivered)}
                sub={`of ${stats.orders_placed} placed`}
              />
              <StatTile
                label="GMV"
                value={inr(stats.gmv)}
                sub="delivered orders only"
              />
              <StatTile
                label="Commission"
                value={inr(stats.commission)}
                sub="on subtotal, never on tax or delivery"
              />
              <StatTile
                label="Average order"
                value={inr(stats.avg_order)}
                sub={`${stats.customers_ordering} customer${stats.customers_ordering === 1 ? '' : 's'} ordered`}
              />
            </div>

            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
              <StatTile
                label="Cancelled"
                value={String(stats.orders_cancelled)}
                sub={
                  stats.orders_placed > 0
                    ? `${Math.round((stats.orders_cancelled / stats.orders_placed) * 100)}% of orders placed`
                    : 'nothing placed'
                }
              />
              <StatTile
                label="Rejected by kitchens"
                value={String(stats.orders_rejected)}
                sub="includes the 5-minute auto-timeout"
              />
              <StatTile
                label="Discount given"
                value={inr(stats.discount_given)}
                sub="coupons, on delivered orders"
              />
              <StatTile
                label="Taking orders"
                value={`${stats.restaurants_live} kitchens`}
                sub={`${stats.riders_active} rider${stats.riders_active === 1 ? '' : 's'} on the roster`}
              />
            </div>

            {series && series.length > 1 && <Chart series={series} />}

            <section>
              <h2 className="text-base font-bold text-ink">
                Busiest restaurants
              </h2>
              <p className="mt-0.5 mb-3 text-sm text-ink-muted">
                By delivered value over the last {days} days.
              </p>
              {top === null || top.length === 0 ? (
                <p className="text-sm text-ink-muted">
                  Nothing delivered in this window.
                </p>
              ) : (
                <DataTable label="Orders by restaurant" minWidth={560}>
                  <thead>
                    <tr>
                      <Th>Restaurant</Th>
                      <Th align="right">Orders</Th>
                      <Th align="right">Delivered value</Th>
                      <Th align="right">Rating</Th>
                    </tr>
                  </thead>
                  <tbody>
                    {top.map((r) => (
                      <tr key={r.restaurant_id}>
                        <Td className="font-medium text-ink">{r.name}</Td>
                        <Td align="right" className="text-ink-muted">
                          {r.orders}
                        </Td>
                        <Td align="right" className="font-semibold text-ink">
                          {inr(r.gmv)}
                        </Td>
                        <Td align="right" className="text-ink-muted">
                          {r.rating.toFixed(1)} ★
                          <span className="ml-1">({r.rating_count})</span>
                        </Td>
                      </tr>
                    ))}
                  </tbody>
                </DataTable>
              )}
            </section>
          </>
        )}
      </PageBody>
    </>
  )
}

/// Orders a day.
///
/// `admin_daily_orders` fills the quiet days in with zeroes rather than dropping
/// them, so the line has the shape of the week and not the shape of the days
/// that happened to have trade.
///
/// **Still drawn, not plotted.** A charting library is a new dependency and
/// Rule 4 makes that an explicit request, not a convenience — so this stays
/// hand-drawn SVG. What it stopped being is a *sketch*: the survey counted no
/// axes, no labels, no hover and no accessible text on the one chart in the
/// console, which left the shape as the only thing a reader could take from it.
///
/// **Sized in real pixels, not stretched.** It was an 800×180 viewBox with
/// `preserveAspectRatio="none"`, so every slope was distorted by whatever width
/// the window happened to be — a chart whose angles lie is worse than no chart.
/// A ResizeObserver gives the real width and the geometry is drawn at that size,
/// which also means the axis text is at its true size rather than scaled along
/// with the drawing.
///
/// **Two series, and only one of them is the point.** Delivered wears the brand
/// and carries the fill; placed is the ceiling above it in the neutral
/// `--color-field` grey, and the gap between them is the orders that fell
/// through. Emphasis rather than two competing hues — and grey against
/// `--color-brand-ink` separates at ΔE 15.4 for deuteranopia, well clear of the
/// 8 that matters. Both marks clear 3:1 against white, which `--color-brand`
/// does not (2.55:1) — and the delivered line used to be drawn in it.
///
/// The wash under the delivered line is `--color-brand-soft` at 1.06:1, which is
/// a fill and not a mark: what it means is readable from the axis, the crosshair
/// and the table underneath, none of which need it to be seen.
function Chart({ series }: { series: DailyOrders[] }) {
  const box = useRef<HTMLDivElement>(null)
  const [width, setWidth] = useState(0)
  /// Which day is being read, or null for none. Pointer and keyboard set the
  /// same value — a chart that answers a mouse and not an arrow key is a chart
  /// half the console cannot use.
  const [at, setAt] = useState<number | null>(null)

  useEffect(() => {
    const el = box.current
    if (!el) return
    const publish = () => setWidth(el.clientWidth)
    publish()
    const ro = new ResizeObserver(publish)
    ro.observe(el)
    return () => ro.disconnect()
  }, [])

  const H = 220
  // Room for the y labels on the left and the dates underneath. Nothing on the
  // right: the last point sits on the edge and its date is right-aligned to it.
  const L = 40
  const R = 12
  const T = 12
  const B = 28
  const plotW = Math.max(0, width - L - R)
  const plotH = H - T - B

  const peak = Math.max(1, ...series.map((d) => d.placed))
  // Clean gridline numbers, and an axis top that is a multiple of the step
  // rather than the peak itself — a top gridline reading 37 is a number nobody
  // asked for. Orders are whole, so the step is whole too.
  const step = niceStep(peak / 3)
  const top = Math.max(step, Math.ceil(peak / step) * step)

  const x = (i: number) =>
    series.length === 1 ? L : L + (i * plotW) / (series.length - 1)
  const y = (v: number) => T + plotH - (v / top) * plotH

  const path = (key: 'placed' | 'delivered') =>
    series.map((d, i) => `${i === 0 ? 'M' : 'L'}${x(i)} ${y(d[key])}`).join('')
  const wash = `${path('delivered')}L${x(series.length - 1)} ${T + plotH}L${L} ${T + plotH}Z`

  const gridlines: number[] = []
  for (let v = 0; v <= top; v += step) gridlines.push(v)

  const label = (iso: string) =>
    new Date(iso).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' })

  // Evenly spaced dates, both ends always included, and never more of them than
  // the width can hold — "12 Sep" is about 38px at 11px, so 90px a label leaves
  // real air between them. Five at most: past that they stop being landmarks.
  const dated = new Set<number>()
  const marks = Math.max(2, Math.min(5, series.length, Math.floor(plotW / 90)))
  for (let i = 0; i < marks; i++) {
    dated.add(Math.round((i * (series.length - 1)) / Math.max(1, marks - 1)))
  }

  const nearest = (clientX: number) => {
    const el = box.current
    if (!el || plotW === 0) return 0
    const px = clientX - el.getBoundingClientRect().left
    const i = Math.round(((px - L) / plotW) * (series.length - 1))
    return Math.min(series.length - 1, Math.max(0, i))
  }

  const onKey = (e: KeyboardEvent<SVGSVGElement>) => {
    const move = e.key === 'ArrowLeft' ? -1 : e.key === 'ArrowRight' ? 1 : 0
    if (move !== 0) {
      e.preventDefault()
      setAt((a) => Math.min(series.length - 1, Math.max(0, (a ?? 0) + move)))
    } else if (e.key === 'Home') {
      e.preventDefault()
      setAt(0)
    } else if (e.key === 'End') {
      e.preventDefault()
      setAt(series.length - 1)
    } else if (e.key === 'Escape') {
      setAt(null)
    }
  }

  const day = at === null ? null : series[at]

  return (
    <section>
      <h2 className="text-base font-bold text-ink">Orders a day</h2>
      <p className="mt-0.5 text-sm text-ink-muted">
        The gap between the two is what was placed and never delivered.
      </p>

      {/* A legend, because there are two series — identity never rests on
          colour-matching alone. Line keys rather than swatches: both marks are
          lines, so the key is the mark. */}
      <div className="mt-2 mb-3 flex flex-wrap gap-x-5 gap-y-1 text-xs text-ink-muted">
        <span className="flex items-center gap-2">
          <span className="h-0.5 w-4 rounded-full bg-brand-ink" aria-hidden="true" />
          Delivered
        </span>
        <span className="flex items-center gap-2">
          <span className="h-0.5 w-4 rounded-full bg-field" aria-hidden="true" />
          Placed
        </span>
      </div>

      <Card>
        <div ref={box} className="relative">
          {width > 0 && (
            <svg
              width={width}
              height={H}
              className="block touch-none"
              tabIndex={0}
              role="img"
              aria-label={`Orders a day, ${label(series[0].day)} to ${label(series[series.length - 1].day)}. Peak ${peak} placed in a day. Arrow keys read a day at a time; the figures are also in the table that follows.`}
              onPointerMove={(e) => setAt(nearest(e.clientX))}
              onPointerLeave={() => setAt(null)}
              onFocus={() => setAt((a) => a ?? series.length - 1)}
              onBlur={() => setAt(null)}
              onKeyDown={onKey}
            >
              {/* Hairline, solid, one step off the surface: a gridline is there
                  to be measured against, not to be looked at. */}
              {gridlines.map((v) => (
                <g key={v}>
                  <line
                    x1={L}
                    x2={width - R}
                    y1={y(v)}
                    y2={y(v)}
                    stroke="var(--color-line)"
                    strokeWidth="1"
                  />
                  <text
                    x={L - 8}
                    y={y(v) + 4}
                    textAnchor="end"
                    className="fill-ink-muted text-[11px] tabular-nums"
                  >
                    {v}
                  </text>
                </g>
              ))}

              <path d={wash} fill="var(--color-brand-soft)" />
              <path
                d={path('placed')}
                fill="none"
                stroke="var(--color-field)"
                strokeWidth="2"
                strokeLinejoin="round"
                strokeLinecap="round"
              />
              <path
                d={path('delivered')}
                fill="none"
                stroke="var(--color-brand-ink)"
                strokeWidth="2"
                strokeLinejoin="round"
                strokeLinecap="round"
              />

              {series.map((d, i) =>
                dated.has(i) ? (
                  <text
                    key={d.day}
                    x={x(i)}
                    y={H - 8}
                    textAnchor={
                      i === 0 ? 'start' : i === series.length - 1 ? 'end' : 'middle'
                    }
                    className="fill-ink-muted text-[11px]"
                  >
                    {label(d.day)}
                  </text>
                ) : null,
              )}

              {/* The crosshair finds the X, so a reader aims at a day rather than
                  at a 2px line. The dots carry a 2px ring in the surface colour
                  so they stay legible where the two series cross. */}
              {day && at !== null && (
                <g pointerEvents="none">
                  <line
                    x1={x(at)}
                    x2={x(at)}
                    y1={T}
                    y2={T + plotH}
                    stroke="var(--color-field)"
                    strokeWidth="1"
                  />
                  <circle
                    cx={x(at)}
                    cy={y(day.placed)}
                    r="4"
                    fill="var(--color-field)"
                    stroke="white"
                    strokeWidth="2"
                  />
                  <circle
                    cx={x(at)}
                    cy={y(day.delivered)}
                    r="4"
                    fill="var(--color-brand-ink)"
                    stroke="white"
                    strokeWidth="2"
                  />
                </g>
              )}
            </svg>
          )}

          {/* Values lead and series names follow: the reader already knows which
              series they want and is here for the number. */}
          {day && at !== null && (
            <div
              className="pointer-events-none absolute top-0 z-10 w-max rounded-field bg-white px-3 py-2 text-xs shadow-floating ring-1 ring-line"
              style={{
                left: Math.min(Math.max(x(at), 64), Math.max(64, width - 64)),
                transform: 'translateX(-50%)',
              }}
            >
              <p className="font-semibold text-ink">{label(day.day)}</p>
              <p className="mt-1 flex items-center gap-2 text-ink">
                <span className="h-0.5 w-3 rounded-full bg-brand-ink" aria-hidden="true" />
                <span className="font-semibold tabular-nums">{day.delivered}</span>
                <span className="text-ink-muted">delivered</span>
              </p>
              <p className="mt-0.5 flex items-center gap-2 text-ink">
                <span className="h-0.5 w-3 rounded-full bg-field" aria-hidden="true" />
                <span className="font-semibold tabular-nums">{day.placed}</span>
                <span className="text-ink-muted">placed</span>
              </p>
            </div>
          )}
        </div>
      </Card>

      {/* Nothing the drawing says lives only in the drawing. A chart is a shape;
          this is the shape's numbers, for a screen reader and for anybody who
          wants the figure rather than the trend. */}
      <table className="sr-only">
        <caption>Orders a day</caption>
        <thead>
          <tr>
            <th scope="col">Day</th>
            <th scope="col">Placed</th>
            <th scope="col">Delivered</th>
          </tr>
        </thead>
        <tbody>
          {series.map((d) => (
            <tr key={d.day}>
              <th scope="row">{label(d.day)}</th>
              <td>{d.placed}</td>
              <td>{d.delivered}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  )
}

/// A gridline step somebody would have chosen: 1, 2, 5, 10, 20, 50 and up.
/// Never below 1 — these are whole orders, and an axis marked every half order
/// is an axis about nothing.
function niceStep(raw: number) {
  const mag = Math.pow(10, Math.floor(Math.log10(Math.max(1, raw))))
  const step = [1, 2, 5, 10].map((m) => m * mag).find((s) => s >= raw) ?? 10 * mag
  return Math.max(1, Math.round(step))
}
