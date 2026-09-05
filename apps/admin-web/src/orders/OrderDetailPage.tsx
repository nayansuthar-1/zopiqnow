import { useCallback, useEffect, useState } from 'react'
import type { ReactNode } from 'react'
import { Link, useParams } from 'react-router-dom'
import { api, DELIVERY_LABEL, ISSUE_LABEL, STATUS_LABEL } from '../lib/api'
import type { OrderDetail, OrderStatus } from '../lib/api'
import { PageHeader } from '../ui/AppShell'
import {
  Banner,
  Card,
  CardSkeleton,
  DataTable,
  EmptyState,
  PageBody,
  Pill,
  Td,
  Th,
} from '../ui/primitives'
import { inr } from '../lib/money'

/// One order, on one page (migration 0154).
///
/// Before this screen, answering "what happened to ZPQ-1188?" meant four others:
/// the live board for an open order's own facts, All orders for a finished one's,
/// Support for the photographs, Refunds for the money — and after all four the
/// conversation between the rider and the customer was still on none of them.
///
/// **It is read-only, and that is the whole design.** Every lever that acts on an
/// order already exists somewhere with an audit row behind it: release and cancel
/// on the live board, delete on All orders, the refund ledger on Refunds. A
/// second Cancel button here would be a second path to one action, which is the
/// rule `AlertsPage` states and this page had no reason to break. What this
/// screen adds is not another way to act. It is the first way to *know*.
///
/// It does not poll. This is the screen somebody opens with a customer on the
/// phone and reads from top to bottom; a fifteen-second reshuffle underneath
/// that is worse than being a minute stale. The live board is one click away and
/// it is the screen that is meant to move.

// The same map the live board and All orders each keep. A third copy rather than
// a shared one, because extracting it means editing two screens this change has
// no other business in — worth doing, once, on purpose.
const statusTones: Record<
  OrderStatus,
  'live' | 'warn' | 'danger' | 'neutral' | 'brand'
> = {
  placed: 'warn',
  accepted: 'brand',
  preparing: 'brand',
  ready_for_pickup: 'brand',
  out_for_delivery: 'live',
  delivered: 'live',
  rejected: 'danger',
  cancelled: 'neutral',
}

function clock(iso: string) {
  return new Date(iso).toLocaleTimeString('en-IN', {
    hour: '2-digit',
    minute: '2-digit',
  })
}

function when(iso: string) {
  return new Date(iso).toLocaleString('en-IN', {
    day: '2-digit',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  })
}

/// The gap between two instants, in the words a person uses out loud. Both ends
/// are real recorded times — nothing here is estimated.
function gap(fromIso: string, toIso: string) {
  const ms = Date.parse(toIso) - Date.parse(fromIso)
  const mins = Math.round(ms / 60000)
  if (mins < 1) return `${Math.max(0, Math.round(ms / 1000))}s`
  if (mins < 60) return `${mins}m`
  return `${Math.floor(mins / 60)}h ${mins % 60}m`
}

/// One side of an audited change, as a word. `null` is the common case — a
/// column that was empty and now is not — and "null" is not what it should say.
function show(v: unknown): string {
  if (v === null || v === undefined || v === '') return 'nothing'
  return String(v)
}

// ---------------------------------------------------------------------------
// The journey
// ---------------------------------------------------------------------------

/// One thing that happened, at a time the database actually recorded.
///
/// **Every row here is a stored timestamp.** There is no status-transition log in
/// this schema — `orders.status` is updated in place — so a delivered order does
/// not remember the moment it was accepted, and this timeline does not pretend
/// otherwise. `ready_by` is the closest thing to an accept: it is written *when*
/// the kitchen accepts, as accept-time plus the prep minutes it chose, so it is
/// evidence that an accept happened and is labelled as the promise it is rather
/// than as the accept it is not.
type Event = {
  at: string
  label: string
  note?: string
  tone: 'brand' | 'live' | 'warn' | 'danger' | 'neutral'
}

function journey(d: OrderDetail): Event[] {
  const o = d.order
  const events: Event[] = [
    { at: o.created_at, label: 'Order placed', tone: 'brand',
      note: `${d.items.length} line${d.items.length === 1 ? '' : 's'} · ${inr(o.total)} · ${o.payment_method.toUpperCase()}` },
  ]

  // The promise, not the accept. See the type's comment.
  if (o.ready_by) {
    events.push({
      at: o.ready_by,
      label: 'Promised ready',
      note: 'set by the kitchen when it accepted',
      tone: 'neutral',
    })
  }
  if (o.ready_at) {
    events.push({
      at: o.ready_at,
      label: 'Kitchen marked it ready',
      note: o.ready_by
        ? Date.parse(o.ready_at) > Date.parse(o.ready_by)
          ? `${gap(o.ready_by, o.ready_at)} later than promised`
          : `${gap(o.ready_at, o.ready_by)} early`
        : undefined,
      tone: o.ready_by && Date.parse(o.ready_at) > Date.parse(o.ready_by) ? 'warn' : 'live',
    })
  }
  if (o.dispatch_started_at) {
    events.push({ at: o.dispatch_started_at, label: 'Looking for a rider', tone: 'brand' })
  }

  // Every ring, and what came of it. This is the answer to "why did nobody
  // come" — and on a healthy order it is one line.
  for (const f of d.offers) {
    events.push({
      at: f.offered_at,
      label: `Offered to ${f.rider_name ?? f.partner_email}`,
      note: f.ride_km !== null ? `${f.ride_km} km · ${inr(f.rider_pay ?? 0)}` : undefined,
      tone: 'neutral',
    })
    if (f.responded_at && f.state !== 'accepted') {
      events.push({
        at: f.responded_at,
        label: f.state === 'declined' ? 'Declined' : 'Offer expired',
        note: `${f.rider_name ?? f.partner_email} · rang for ${gap(f.offered_at, f.responded_at)}`,
        tone: 'warn',
      })
    }
  }

  const dl = d.delivery
  if (dl) {
    const rider = dl.rider_name ?? dl.partner_email
    events.push({ at: dl.claimed_at, label: `${rider} took the job`, tone: 'live',
      note: dl.distance_km !== null ? `${dl.distance_km} km · ${inr(dl.rider_pay ?? 0)} to the rider` : undefined })
    if (dl.arrived_at_restaurant_at) {
      events.push({ at: dl.arrived_at_restaurant_at, label: 'At the counter', tone: 'neutral',
        note: `${gap(dl.claimed_at, dl.arrived_at_restaurant_at)} from accepting` })
    }
    if (dl.picked_up_at) {
      events.push({ at: dl.picked_up_at, label: 'Picked up', tone: 'live',
        note: d.handover && d.handover.pickup_attempts > 1
          ? `after ${d.handover.pickup_attempts} tries at the code`
          : undefined })
    }
    if (dl.arrived_at_customer_at) {
      events.push({ at: dl.arrived_at_customer_at, label: 'At the door', tone: 'neutral' })
    }
    if (dl.delivered_at) {
      events.push({ at: dl.delivered_at, label: 'Delivered', tone: 'live',
        note: `${gap(o.created_at, dl.delivered_at)} from placing` })
    }
  }

  if (o.invoiced_at) {
    events.push({ at: o.invoiced_at, label: 'Invoice issued', note: o.invoice_no ?? undefined, tone: 'neutral' })
  }

  for (const r of d.refunds) {
    events.push({ at: r.created_at, label: `Refund raised — ${inr(r.amount)}`, tone: 'warn',
      note: `${r.reason} · by ${r.requested_by}` })
    if (r.approved_at) {
      events.push({ at: r.approved_at, label: 'Refund approved', tone: 'neutral',
        note: r.approved_by ? `by ${r.approved_by}` : undefined })
    }
    if (r.paid_at) {
      events.push({ at: r.paid_at, label: `Refund paid — ${inr(r.amount)}`, tone: 'live',
        note: r.gateway_refund_id ?? undefined })
    }
  }

  for (const t of d.tickets) {
    events.push({ at: t.created_at, label: `Complaint — ${ISSUE_LABEL[t.category] ?? t.category}`, tone: 'danger' })
    if (t.resolved_at) {
      events.push({ at: t.resolved_at, label: 'Complaint closed', tone: 'neutral',
        note: t.resolved_by ? `by ${t.resolved_by}` : undefined })
    }
  }

  if (d.review) {
    events.push({
      at: d.review.created_at,
      label: `Rated ${d.review.food_rating ?? '—'}/5 for the food, ${d.review.rider_rating ?? '—'}/5 for the ride`,
      note: d.review.comment ?? undefined,
      tone: 'brand',
    })
  }

  // What an admin did, from the append-only trail. An `update` arrives already
  // reduced to the fields that changed, so it reads as a sentence rather than as
  // two copies of a table row. An `insert` or a `delete` has no before/after
  // pair and the RPC passes its payload through whole — so those are named, not
  // spelled out, because "id: — → —" is what happens if you try.
  for (const a of d.admin_actions) {
    const changes = Object.entries(a.detail ?? {}).filter(
      ([, v]) => v !== null && typeof v === 'object' && 'from' in v && 'to' in v,
    )
    events.push({
      at: a.created_at,
      label: `${a.actor_email} — ${a.action} on ${a.target_type}`,
      note: changes.length
        ? changes
            .slice(0, 3)
            .map(([k, v]) => `${k}: ${show(v.from)} → ${show(v.to)}`)
            .join(', ')
        : undefined,
      tone: 'danger',
    })
  }

  return events.sort((a, b) => Date.parse(a.at) - Date.parse(b.at))
}

const dotTones = {
  brand: 'bg-brand',
  live: 'bg-veg',
  warn: 'bg-warn',
  danger: 'bg-non-veg',
  neutral: 'bg-line',
} as const

function Journey({ events }: { events: Event[] }) {
  return (
    <ol className="space-y-0">
      {events.map((e, i) => (
        <li key={`${e.at}-${i}`} className="relative flex gap-4 pb-5 last:pb-0">
          {/* The rail, drawn behind the dots and stopped short on the last row so
              the line does not dangle past the final event. */}
          {i < events.length - 1 && (
            <span aria-hidden className="absolute top-3 bottom-0 left-1.25 w-px bg-line" />
          )}
          <span
            aria-hidden
            className={`relative mt-2 h-2.5 w-2.5 shrink-0 rounded-full ${dotTones[e.tone]}`}
          />
          <div className="min-w-0 flex-1">
            <p className="text-sm font-medium text-ink">{e.label}</p>
            {e.note && <p className="mt-0.5 text-sm text-ink-muted">{e.note}</p>}
          </div>
          <time
            dateTime={e.at}
            className="shrink-0 text-xs tabular-nums text-ink-muted"
            title={when(e.at)}
          >
            {clock(e.at)}
          </time>
        </li>
      ))}
    </ol>
  )
}

// ---------------------------------------------------------------------------
// Small shared bits
// ---------------------------------------------------------------------------

function Section({ title, aside, children }: { title: string; aside?: ReactNode; children: ReactNode }) {
  return (
    <Card>
      <div className="mb-4 flex items-baseline justify-between gap-3">
        <h2 className="text-sm font-semibold tracking-wide text-ink-muted uppercase">
          {title}
        </h2>
        {aside}
      </div>
      {children}
    </Card>
  )
}

/// A label and its value, stacked. Used everywhere a fact has a name.
function Fact({ label, value, tone }: { label: string; value: ReactNode; tone?: 'danger' }) {
  return (
    <div className="min-w-0">
      <p className="text-xs font-medium tracking-wide text-ink-muted uppercase">{label}</p>
      <p className={`mt-1 text-sm wrap-break-word ${tone === 'danger' ? 'font-semibold text-non-veg-ink' : 'text-ink'}`}>
        {value}
      </p>
    </div>
  )
}

function Line({ label, value, strong }: { label: string; value: string; strong?: boolean }) {
  return (
    <div className={`flex justify-between gap-4 ${strong ? 'border-t border-line pt-2 font-semibold text-ink' : 'text-ink'}`}>
      <span className="text-sm">{label}</span>
      <span className="text-sm tabular-nums">{value}</span>
    </div>
  )
}

// ---------------------------------------------------------------------------

export function OrderDetailPage() {
  const { id = '' } = useParams()
  const [detail, setDetail] = useState<OrderDetail | null>(null)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async () => {
    setError(null)
    // Cleared before the request, not after it. This runs again when the id in
    // the path changes, and leaving the previous order on screen would show one
    // order's sections under another order's number.
    setDetail(null)
    try {
      setDetail(await api.orderDetail(id))
    } catch (e) {
      setDetail(null)
      setError(e instanceof Error ? e.message : String(e))
    }
  }, [id])

  useEffect(() => {
    void load()
  }, [load])

  if (error) {
    return (
      <>
        <PageHeader title={id.toUpperCase()} subtitle="Order" />
        <PageBody>
          {/* The RPC's own sentence, unaltered — for a deleted order it names the
              admin who removed it and why, which is the answer somebody looking
              up an id from a customer's inbox actually needs. */}
          <Banner tone="error" className="max-w-2xl">
            {error}
          </Banner>
          <p className="mt-4 text-sm text-ink-muted">
            <Link to="/orders" className="font-medium text-brand-ink underline">
              Back to all orders
            </Link>
          </p>
        </PageBody>
      </>
    )
  }

  if (!detail) {
    return (
      <>
        <PageHeader title={id.toUpperCase()} subtitle="Order" />
        <PageBody>
          <CardSkeleton rows={6} />
        </PageBody>
      </>
    )
  }

  const o = detail.order
  const paidBy = o.payment_method.toUpperCase()
  // The one fact on this page that is worth shouting about: money the kitchen
  // cooked against and nobody proved (0085). Cash orders have no intent and are
  // not a gap.
  const unverified =
    o.payment_method !== 'cash' && (!detail.payment || !detail.payment.verified_at)

  return (
    <>
      <PageHeader
        title={o.id}
        subtitle={`${o.restaurant_name} · ${when(o.created_at)}`}
        action={
          <div className="flex items-center gap-3">
            <Pill tone={statusTones[o.status]}>{STATUS_LABEL[o.status]}</Pill>
            <span className="text-lg font-bold tabular-nums text-ink">{inr(o.total)}</span>
          </div>
        }
      />

      <PageBody className="space-y-6">
        {o.status_reason && (
          <Banner tone="warn" className="max-w-3xl">
            {STATUS_LABEL[o.status]}: {o.status_reason}
          </Banner>
        )}

        {unverified && (
          <Banner tone="error" className="max-w-3xl">
            This {paidBy} order has no verified payment behind it. The kitchen
            cooked against money nobody proved (migration 0085).
          </Banner>
        )}

        <div className="grid gap-6 lg:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]">
          {/* Left: what happened, and what was bought. */}
          <div className="space-y-6">
            <Section
              title="What happened"
              aside={
                <span className="text-xs text-ink-muted">
                  every row is a recorded time
                </span>
              }
            >
              <Journey events={journey(detail)} />
            </Section>

            <Section title={`The order — ${detail.items.length} line${detail.items.length === 1 ? '' : 's'}`}>
              <DataTable label="Order items" minWidth={420}>
                <thead>
                  <tr>
                    <Th>Item</Th>
                    <Th align="right">Qty</Th>
                    <Th align="right">Unit</Th>
                    <Th align="right">Line</Th>
                  </tr>
                </thead>
                <tbody>
                  {detail.items.map((it, i) => (
                    <tr key={`${it.menu_item_id}-${i}`}>
                      <Td>
                        <span className="font-medium text-ink">{it.name}</span>
                        {it.options.length > 0 && (
                          <span className="mt-0.5 block text-xs text-ink-muted">
                            {it.options
                              .map((op) =>
                                op.price_delta ? `${op.name} (+${inr(op.price_delta)})` : op.name,
                              )
                              .join(' · ')}
                          </span>
                        )}
                        {it.gst_rate_bps !== null && (
                          <span className="mt-0.5 block text-xs text-ink-muted">
                            GST {it.gst_rate_bps / 100}%
                            {it.hsn_code ? ` · HSN ${it.hsn_code}` : ''}
                          </span>
                        )}
                      </Td>
                      <Td align="right">{it.quantity}</Td>
                      <Td align="right">{inr(it.unit_price)}</Td>
                      <Td align="right">{inr(it.line_total)}</Td>
                    </tr>
                  ))}
                </tbody>
              </DataTable>

              {/* The arithmetic the customer saw, in the order they saw it. The
                  fees are gross — tax-inclusive — so `tax_on_fees` is *inside*
                  them and is stated rather than added, which is the one place
                  this table could quietly disagree with the total. */}
              <div className="mt-5 space-y-2">
                <Line label="Items" value={inr(o.subtotal)} />
                {o.discount > 0 && (
                  <Line
                    label={`Discount${o.coupon_code ? ` · ${o.coupon_code}` : ''}${o.discount_funded_by ? ` (${o.discount_funded_by})` : ''}`}
                    value={`−${inr(o.discount)}`}
                  />
                )}
                <Line label="Delivery" value={inr(o.delivery_fee)} />
                {o.surge_fee > 0 && <Line label="Surge (night or rain)" value={inr(o.surge_fee)} />}
                {o.platform_fee > 0 && <Line label="Platform fee" value={inr(o.platform_fee)} />}
                {o.packaging_fee > 0 && <Line label="Packaging" value={inr(o.packaging_fee)} />}
                <Line label="Tax on items" value={inr(o.taxes)} />
                <Line label={`Total — paid by ${paidBy}`} value={inr(o.total)} strong />
                <p className="pt-1 text-xs text-ink-muted">
                  Of which tax: CGST {inr(o.cgst)} · SGST {inr(o.sgst)}
                  {o.igst > 0 && <> · IGST {inr(o.igst)}</>} — {inr(o.tax_on_fees)} of
                  that sits inside the fees above rather than on top of them.
                </p>
              </div>
            </Section>

            <Section
              title="What was said"
              aside={
                <span className="text-xs text-ink-muted">
                  {detail.messages.length} message{detail.messages.length === 1 ? '' : 's'}
                </span>
              }
            >
              {detail.messages.length === 0 ? (
                <EmptyState
                  title="Nothing was said"
                  body="Neither side sent a message on this order."
                />
              ) : (
                <ul className="space-y-3">
                  {detail.messages.map((m, i) => (
                    <li key={i} className="flex gap-3">
                      <span className="w-20 shrink-0 text-xs font-medium text-ink-muted capitalize">
                        {m.sender}
                      </span>
                      <p className="min-w-0 flex-1 text-sm text-ink">{m.body}</p>
                      <time dateTime={m.created_at} className="shrink-0 text-xs tabular-nums text-ink-muted">
                        {clock(m.created_at)}
                      </time>
                    </li>
                  ))}
                </ul>
              )}
            </Section>
          </div>

          {/* Right: who and what it cost. */}
          <div className="space-y-6">
            <Section title="Customer">
              {detail.customer ? (
                <div className="grid gap-4 sm:grid-cols-2">
                  <Fact label="Name" value={detail.customer.name ?? '—'} />
                  <Fact label="Phone" value={detail.customer.phone ?? o.user_phone} />
                  <Fact label="Email" value={detail.customer.email ?? '—'} />
                  <Fact
                    label="Orders before this"
                    value={
                      detail.customer.orders_before === 0
                        ? 'none — first order'
                        : String(detail.customer.orders_before)
                    }
                  />
                  {detail.customer.is_blocked && (
                    <Fact label="Moderation" value="Blocked" tone="danger" />
                  )}
                  <div className="sm:col-span-2">
                    <Fact label="Delivering to" value={o.delivery_to} />
                  </div>
                  {o.delivery_notes && (
                    <div className="sm:col-span-2">
                      <Fact label="Note for the rider" value={o.delivery_notes} />
                    </div>
                  )}
                </div>
              ) : (
                <p className="text-sm text-ink-muted">
                  This order's customer no longer has an account.
                </p>
              )}
            </Section>

            <Section title="Restaurant">
              <div className="grid gap-4 sm:grid-cols-2">
                <Fact
                  label="Name"
                  value={
                    <Link
                      to={`/restaurants/${o.restaurant_id}`}
                      className="font-medium text-brand-ink underline"
                    >
                      {o.restaurant_name}
                    </Link>
                  }
                />
                <Fact label="Phone" value={detail.restaurant?.phone ?? '—'} />
                <Fact label="Owner" value={detail.restaurant?.owner_name ?? '—'} />
                <Fact
                  label="Now"
                  value={
                    !detail.restaurant
                      ? '—'
                      : !detail.restaurant.is_active
                        ? 'Delisted'
                        : detail.restaurant.accepting_orders
                          ? 'Open'
                          : 'Paused'
                  }
                />
                <div className="sm:col-span-2">
                  <Fact
                    label="Address"
                    value={[detail.restaurant?.address_line, detail.restaurant?.city]
                      .filter(Boolean)
                      .join(', ') || '—'}
                  />
                </div>
              </div>
            </Section>

            <Section title="Delivery">
              {detail.delivery ? (
                <div className="grid gap-4 sm:grid-cols-2">
                  <Fact label="Rider" value={detail.delivery.rider_name ?? detail.delivery.partner_email} />
                  <Fact label="Phone" value={detail.delivery.rider_phone ?? '—'} />
                  <Fact
                    label="State"
                    value={<Pill tone="brand">{DELIVERY_LABEL[detail.delivery.state]}</Pill>}
                  />
                  <Fact
                    label="Engagement"
                    value={detail.delivery.rider_engagement?.replace('_', ' ') ?? '—'}
                  />
                  <Fact
                    label="Ride"
                    value={detail.delivery.distance_km !== null ? `${detail.delivery.distance_km} km` : '—'}
                  />
                  <Fact
                    label="Rider paid"
                    value={
                      detail.delivery.rider_pay !== null
                        ? `${inr(detail.delivery.rider_pay)}${detail.delivery.payout_id ? ` · payout #${detail.delivery.payout_id}` : ' · not yet in a payout'}`
                        : '—'
                    }
                  />
                </div>
              ) : (
                <p className="text-sm text-ink-muted">
                  {detail.offers.length > 0
                    ? `Offered to ${detail.offers.length} rider${detail.offers.length === 1 ? '' : 's'}; none is carrying it.`
                    : 'No rider has been offered this order.'}
                </p>
              )}

              {/* Attempts, never the codes. An admin who could read the pickup
                  code could close a handover that never happened. */}
              {detail.handover &&
                (detail.handover.pickup_attempts > 0 || detail.handover.delivery_attempts > 0) && (
                  <p className="mt-4 border-t border-line pt-4 text-sm text-ink-muted">
                    Handover codes were mistyped — {detail.handover.pickup_attempts} at pickup,{' '}
                    {detail.handover.delivery_attempts} at the door.
                  </p>
                )}
            </Section>

            <Section title="Payment">
              {detail.payment ? (
                <div className="grid gap-4 sm:grid-cols-2">
                  <Fact label="Method" value={paidBy} />
                  <Fact label="Instrument" value={detail.payment.instrument ?? '—'} />
                  <Fact
                    label="Verified"
                    value={detail.payment.verified_at ? when(detail.payment.verified_at) : 'never'}
                    tone={detail.payment.verified_at ? undefined : 'danger'}
                  />
                  <Fact label="Gateway status" value={detail.payment.status} />
                  <div className="sm:col-span-2">
                    <Fact label="Razorpay payment" value={detail.payment.razorpay_payment_id ?? '—'} />
                  </div>
                </div>
              ) : (
                <p className="text-sm text-ink-muted">
                  {o.payment_method === 'cash'
                    ? 'Cash on delivery — the rider collected it, and it settles through Rider cash.'
                    : 'No payment intent was ever recorded against this order.'}
                </p>
              )}
            </Section>

            {detail.refunds.length > 0 && (
              <Section title="Refunds">
                <ul className="space-y-4">
                  {detail.refunds.map((r) => (
                    <li key={r.id} className="border-b border-line pb-4 last:border-b-0 last:pb-0">
                      <div className="flex items-baseline justify-between gap-3">
                        <span className="font-semibold tabular-nums text-ink">{inr(r.amount)}</span>
                        <Pill tone={r.status === 'paid' ? 'live' : r.status === 'failed' ? 'danger' : 'warn'}>
                          {r.status}
                        </Pill>
                      </div>
                      <p className="mt-1 text-sm text-ink-muted">{r.reason}</p>
                      <p className="mt-1 text-xs text-ink-muted">
                        Funded by {r.funded_by} · promised by {r.expected_by}
                        {r.failure_reason ? ` · refused: ${r.failure_reason}` : ''}
                      </p>
                    </li>
                  ))}
                </ul>
                <p className="mt-4 text-xs text-ink-muted">
                  <Link to="/refunds" className="font-medium text-brand-ink underline">
                    Work these on Refunds
                  </Link>{' '}
                  — this page only reads.
                </p>
              </Section>
            )}

            {(detail.photos.cooked || detail.photos.packed || detail.photos.delivery) && (
              <Section title="Photographs">
                <div className="grid grid-cols-3 gap-3">
                  {(
                    [
                      ['Cooked', detail.photos.cooked],
                      ['Packed', detail.photos.packed],
                      ['Handover', detail.photos.delivery],
                    ] as const
                  ).map(([label, url]) => (
                    <figure key={label}>
                      {url ? (
                        <a href={url} target="_blank" rel="noreferrer">
                          <img
                            src={url}
                            alt={`${label} — order ${o.id}`}
                            loading="lazy"
                            className="aspect-square w-full rounded-field border border-line object-cover"
                          />
                        </a>
                      ) : (
                        <div className="flex aspect-square w-full items-center justify-center rounded-field border border-dashed border-line text-xs text-ink-muted">
                          none
                        </div>
                      )}
                      <figcaption className="mt-1 text-xs text-ink-muted">{label}</figcaption>
                    </figure>
                  ))}
                </div>
              </Section>
            )}

            {detail.tickets.length > 0 && (
              <Section title="Complaints">
                <ul className="space-y-4">
                  {detail.tickets.map((t) => (
                    <li key={t.id} className="border-b border-line pb-4 last:border-b-0 last:pb-0">
                      <div className="flex items-baseline justify-between gap-3">
                        <span className="font-medium text-ink">
                          {ISSUE_LABEL[t.category] ?? t.category}
                        </span>
                        <Pill tone={t.status === 'open' ? 'warn' : 'neutral'}>{t.status}</Pill>
                      </div>
                      {t.body && <p className="mt-1 text-sm text-ink-muted">{t.body}</p>}
                      {t.admin_note && (
                        <p className="mt-1 text-sm text-ink">
                          Answer: {t.admin_note}
                          {t.resolved_by ? ` — ${t.resolved_by}` : ''}
                        </p>
                      )}
                    </li>
                  ))}
                </ul>
              </Section>
            )}
          </div>
        </div>
      </PageBody>
    </>
  )
}
