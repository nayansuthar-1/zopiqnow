import { useCallback, useEffect, useState } from 'react'
import { api } from '../lib/api'
import type { DailyOrders, PlatformStats, TopRestaurant } from '../lib/api'
import { PageHeader } from '../ui/AppShell'
import {
  Banner,
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
              <div key={i} className="rounded-card border border-line bg-white p-6">
                <Skeleton className="h-3 w-20" />
                <Skeleton className="mt-3 h-7 w-28" />
                <Skeleton className="mt-2 h-3 w-32" />
              </div>
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

/// Delivered orders per day. `admin_daily_orders` fills the quiet days in with
/// zeroes rather than dropping them, so the line has the shape of the week and
/// not the shape of the days that happened to have trade.
function Chart({ series }: { series: DailyOrders[] }) {
  const W = 800
  const H = 180
  const PAD = 8

  const peak = Math.max(1, ...series.map((d) => d.placed))
  const x = (i: number) => PAD + (i * (W - PAD * 2)) / (series.length - 1)
  const y = (v: number) => H - PAD - (v / peak) * (H - PAD * 2)

  const line = series.map((d, i) => `${x(i)},${y(d.delivered)}`).join(' ')
  const area = `${PAD},${H - PAD} ${series
    .map((d, i) => `${x(i)},${y(d.placed)}`)
    .join(' ')} ${W - PAD},${H - PAD}`

  const first = series[0]
  const last = series[series.length - 1]
  const label = (iso: string) =>
    new Date(iso).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' })

  return (
    <section>
      <h2 className="text-base font-bold text-ink">Orders a day</h2>
      <p className="mt-0.5 mb-3 text-sm text-ink-muted">
        Placed in the tint, delivered on the line. Peak {peak} in a day.
      </p>
      <div className="rounded-card border border-line bg-white p-5">
        <svg
          viewBox={`0 0 ${W} ${H}`}
          className="h-44 w-full"
          preserveAspectRatio="none"
          role="img"
          aria-label={`Orders per day from ${label(first.day)} to ${label(last.day)}`}
        >
          <polygon points={area} fill="var(--color-brand-soft)" />
          <polyline
            points={line}
            fill="none"
            stroke="var(--color-brand)"
            strokeWidth="2"
            vectorEffect="non-scaling-stroke"
            strokeLinejoin="round"
          />
        </svg>
        <div className="mt-2 flex justify-between text-xs text-ink-muted">
          <span>{label(first.day)}</span>
          <span>{label(last.day)}</span>
        </div>
      </div>
    </section>
  )
}
