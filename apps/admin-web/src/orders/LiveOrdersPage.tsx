import { useCallback, useEffect, useRef, useState } from 'react'
import type { ReactNode } from 'react'
import { api, DELIVERY_LABEL, STATUS_LABEL } from '../lib/api'
import type { AdminOrderRow, OrderStatus } from '../lib/api'
import { PageHeader } from '../ui/AppShell'
import { Button, Field } from '../ui/primitives'

/// The running floor. Every order that has not ended, oldest first, because the
/// order that has been open longest is the one somebody is about to ring about.
///
/// **It polls, and says so.** Every other live surface in this system is on
/// Realtime, which the console cannot use: `orders` grants an admin no read at
/// all — `admin_orders` is a `security definer` function, and a function cannot
/// be subscribed to. Adding an admin policy to `orders` would buy a socket at
/// the cost of the console's one structural guarantee, which is that it reaches
/// the database through named functions and nothing else. So: fifteen seconds,
/// a visible clock, and a refresh button for the impatient. An ops screen at a
/// desk can afford to be a quarter-minute behind; it cannot afford to be the
/// reason a table got a read policy.

const REFRESH_MS = 15_000

const statusStyles: Record<OrderStatus, string> = {
  placed: 'bg-warn-soft text-warn',
  accepted: 'bg-brand-soft text-brand-deep',
  preparing: 'bg-brand-soft text-brand-deep',
  ready_for_pickup: 'bg-brand-soft text-brand-deep',
  out_for_delivery: 'bg-veg-soft text-veg',
  delivered: 'bg-veg-soft text-veg',
  rejected: 'bg-non-veg-soft text-non-veg',
  cancelled: 'bg-canvas text-ink-muted',
}

function minutesSince(iso: string) {
  return Math.max(0, Math.round((Date.now() - Date.parse(iso)) / 60000))
}

function clock(iso: string) {
  return new Date(iso).toLocaleTimeString('en-IN', {
    hour: '2-digit',
    minute: '2-digit',
  })
}

/// The one line that says what is actually happening to this order right now.
/// Composed rather than looked up, because "on the shelf, offered to Ravi,
/// 22 seconds left" is three facts and no enum has a value for it.
function whereItIs(o: AdminOrderRow): string {
  if (o.rider_name && o.delivery_state) {
    return `${o.rider_name} — ${DELIVERY_LABEL[o.delivery_state]}`
  }
  if (o.offer_to) return `offered to ${o.offer_to}`
  if (o.status === 'placed') return 'waiting for the kitchen to accept'
  if (o.status === 'preparing' || o.status === 'ready_for_pickup') {
    return 'no rider yet'
  }
  return '—'
}

export function LiveOrdersPage() {
  const [rows, setRows] = useState<AdminOrderRow[] | null>(null)
  const [query, setQuery] = useState('')
  // The query the rows on screen actually answer, which is not the one being
  // typed. Without it the header would claim search results a keystroke before
  // they exist.
  const [applied, setApplied] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [fetchedAt, setFetchedAt] = useState<number | null>(null)
  const [tick, setTick] = useState(0)
  const [acting, setActing] = useState<{
    order: AdminOrderRow
    kind: 'release' | 'cancel'
  } | null>(null)
  const [reason, setReason] = useState('')
  const [busy, setBusy] = useState(false)
  const [note, setNote] = useState<string | null>(null)

  // Read inside the interval so the timer does not have to be torn down and
  // rebuilt every time the search box changes.
  const appliedRef = useRef('')
  appliedRef.current = applied

  const load = useCallback(async (q: string) => {
    try {
      const next = await api.orders(q === '' ? undefined : q)
      setRows(next)
      setApplied(q)
      setFetchedAt(Date.now())
      setError(null)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }, [])

  useEffect(() => {
    void load('')
  }, [load])

  useEffect(() => {
    const poll = setInterval(() => void load(appliedRef.current), REFRESH_MS)
    // A second, faster timer for nothing but the relative times on screen. The
    // deadline countdown has to move every second; the data does not.
    const paint = setInterval(() => setTick((t) => t + 1), 1000)
    return () => {
      clearInterval(poll)
      clearInterval(paint)
    }
  }, [load])

  async function act() {
    if (!acting) return
    setBusy(true)
    setError(null)
    try {
      if (acting.kind === 'release') {
        const who = await api.releaseDelivery(acting.order.order_id, reason)
        setNote(
          `${acting.order.order_id} is back on the shelf — released from ${who}. The dispatcher will offer it again within 20 seconds.`,
        )
      } else {
        await api.cancelOrder(acting.order.order_id, reason)
        setNote(`${acting.order.order_id} is cancelled. The customer has been told.`)
      }
      setActing(null)
      setReason('')
      await load(applied)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  const age = fetchedAt ? Math.round((Date.now() - fetchedAt) / 1000) : null
  const searching = applied !== ''

  return (
    <>
      <PageHeader
        title="Live orders"
        subtitle={
          rows === null
            ? 'Every order that has not ended yet.'
            : searching
              ? `${rows.length} order${rows.length === 1 ? '' : 's'} matching “${applied}”, any status`
              : `${rows.length} open · updated ${age === null || age < 2 ? 'just now' : `${age}s ago`}`
        }
        action={
          <Button variant="secondary" onClick={() => void load(applied)}>
            Refresh
          </Button>
        }
      />

      <div className="p-6">
        {error && (
          <p className="mb-4 max-w-2xl rounded-[8px] bg-non-veg-soft px-4 py-3 text-sm text-non-veg">
            {error}
          </p>
        )}
        {note && (
          <div className="mb-4 flex max-w-3xl items-start justify-between gap-4 rounded-[8px] bg-veg-soft px-4 py-3">
            <p className="text-sm text-veg">{note}</p>
            <button
              className="text-sm font-semibold text-veg"
              onClick={() => setNote(null)}
            >
              Dismiss
            </button>
          </div>
        )}

        <form
          className="mb-4 flex max-w-xl gap-2"
          onSubmit={(e) => {
            e.preventDefault()
            void load(query.trim())
          }}
        >
          <input
            className="h-11 flex-1 rounded-[8px] border border-line bg-white px-3 text-sm text-ink outline-none placeholder:text-ink-muted focus:border-brand"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Order id or phone number"
            aria-label="Find an order"
          />
          <Button type="submit" variant="secondary">
            Find
          </Button>
          {searching && (
            <Button
              type="button"
              variant="ghost"
              onClick={() => {
                setQuery('')
                void load('')
              }}
            >
              Back to live
            </Button>
          )}
        </form>

        {rows === null ? (
          <p className="text-sm text-ink-muted">Loading…</p>
        ) : rows.length === 0 ? (
          <p className="text-sm text-ink-muted">
            {searching
              ? 'No order with that id or phone number.'
              : 'Nothing open. Every order placed today has been delivered, cancelled or rejected.'}
          </p>
        ) : (
          <div className="space-y-3">
            {rows.map((o) => (
              <OrderCard
                key={o.order_id}
                order={o}
                tick={tick}
                onRelease={() => {
                  setActing({ order: o, kind: 'release' })
                  setReason('')
                }}
                onCancel={() => {
                  setActing({ order: o, kind: 'cancel' })
                  setReason('')
                }}
              />
            ))}
          </div>
        )}
      </div>

      {acting && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-ink/40 p-4">
          <div className="w-full max-w-md rounded-[12px] bg-white p-6">
            <h2 className="text-base font-bold text-ink">
              {acting.kind === 'release'
                ? `Take ${acting.order.order_id} off its rider?`
                : `Cancel ${acting.order.order_id}?`}
            </h2>
            <p className="mt-2 text-sm text-ink-muted">
              {acting.kind === 'release'
                ? `${acting.order.rider_name ?? 'The rider'} loses the job and is told why. The order goes back on the shelf and the dispatcher offers it to somebody else. They are never offered this order again.`
                : `The order ends here. ${acting.order.customer_phone} is shown your sentence, the kitchen is told, and any rider on it is released. There is no undo — a delivered order can only be refunded.`}
            </p>
            <div className="mt-5">
              <Field
                label="Why"
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                placeholder={
                  acting.kind === 'release'
                    ? 'Rider unreachable for 20 minutes'
                    : 'Restaurant closed unexpectedly'
                }
                hint="This is the only record of the decision, and the customer reads it."
              />
            </div>
            <div className="mt-5 flex justify-end gap-2">
              <Button
                variant="ghost"
                onClick={() => setActing(null)}
                disabled={busy}
              >
                Keep it
              </Button>
              <Button
                onClick={() => void act()}
                disabled={busy || reason.trim() === ''}
              >
                {acting.kind === 'release' ? 'Release' : 'Cancel the order'}
              </Button>
            </div>
          </div>
        </div>
      )}
    </>
  )
}

function OrderCard({
  order: o,
  tick,
  onRelease,
  onCancel,
}: {
  order: AdminOrderRow
  /// Not read. It exists so this component repaints once a second with its
  /// parent — every relative time below is computed from `Date.now()`, and
  /// without a changing prop React would happily leave a stale "4m ago" on
  /// screen for the whole fifteen-second poll.
  tick: number
  onRelease: () => void
  onCancel: () => void
}) {
  void tick

  const ended = ['delivered', 'cancelled', 'rejected'].includes(o.status)
  const awaitingAccept = o.status === 'placed'
  const secondsToDeadline = Math.round(
    (Date.parse(o.accept_deadline) - Date.now()) / 1000,
  )

  return (
    <div className="rounded-[12px] border border-line bg-white p-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <span className="font-semibold text-ink">{o.order_id}</span>
            <span
              className={`rounded-full px-2.5 py-1 text-xs font-semibold ${statusStyles[o.status]}`}
            >
              {STATUS_LABEL[o.status]}
            </span>
            {awaitingAccept && (
              // The kitchen's five minutes (0051). Counted against
              // `orders.accept_deadline`, the same column the vendor tablet
              // counts down and the sweeper expires on — one column, so the two
              // can never disagree.
              <span
                className={`text-xs font-semibold ${
                  secondsToDeadline <= 60 ? 'text-non-veg' : 'text-warn'
                }`}
              >
                {secondsToDeadline > 0
                  ? `auto-rejects in ${Math.floor(secondsToDeadline / 60)}:${String(
                      secondsToDeadline % 60,
                    ).padStart(2, '0')}`
                  : 'past its deadline'}
              </span>
            )}
          </div>
          <p className="mt-1 text-sm text-ink-muted">
            {o.restaurant_name} · placed {minutesSince(o.placed_at)}m ago at{' '}
            {clock(o.placed_at)} · ₹{o.total}{' '}
            {o.payment_method === 'upi' ? 'prepaid' : 'cash on delivery'}
            {o.coupon_code && ` · ${o.coupon_code}`}
          </p>
        </div>

        {!ended && (
          <div className="flex gap-2">
            {(o.rider_email || o.offer_to) && (
              <Button variant="secondary" className="h-9 px-3" onClick={onRelease}>
                Release rider
              </Button>
            )}
            <Button variant="secondary" className="h-9 px-3" onClick={onCancel}>
              Cancel order
            </Button>
          </div>
        )}
      </div>

      <dl className="mt-4 grid gap-3 text-sm sm:grid-cols-2 lg:grid-cols-4">
        <Cell label="Delivery">
          <p className="text-ink">{o.delivery_to}</p>
          <p className="text-ink-muted">
            {o.customer_phone}
            {o.route_km !== null && ` · ${o.route_km} km`}
          </p>
        </Cell>

        <Cell label="Rider">
          <p className="text-ink">{whereItIs(o)}</p>
          {o.rider_phone && <p className="text-ink-muted">{o.rider_phone}</p>}
          {o.offer_expires_at && (
            <p className="text-ink-muted">
              {Math.max(
                0,
                Math.round((Date.parse(o.offer_expires_at) - Date.now()) / 1000),
              )}
              s to answer
            </p>
          )}
        </Cell>

        <Cell label="Arriving">
          {o.eta_at ? (
            <>
              <p className="text-ink">{clock(o.eta_at)}</p>
              {/* The sentence 0057 refuses to move an ETA later without. If it
                  is here, it is the reason the number changed. */}
              {o.eta_reason && <p className="text-ink-muted">{o.eta_reason}</p>}
            </>
          ) : (
            <p className="text-ink-muted">not estimated yet</p>
          )}
        </Cell>

        <Cell label="Kitchen">
          {o.ready_by ? (
            <p className="text-ink">ready by {clock(o.ready_by)}</p>
          ) : (
            <p className="text-ink-muted">no prep time given</p>
          )}
          {o.status_reason && (
            <p className="text-warn">{o.status_reason}</p>
          )}
        </Cell>
      </dl>
    </div>
  )
}

function Cell({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div>
      <dt className="text-xs font-medium tracking-wide text-ink-muted uppercase">
        {label}
      </dt>
      <dd className="mt-1 space-y-0.5">{children}</dd>
    </div>
  )
}
