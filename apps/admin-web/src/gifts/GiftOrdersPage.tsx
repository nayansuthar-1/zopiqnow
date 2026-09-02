import { useCallback, useEffect, useMemo, useState } from 'react'
import { api, GIFT_STATUS_LABEL } from '../lib/api'
import type { GiftOrderLineRow, GiftOrderRow, GiftOrderStatus } from '../lib/api'
import { PageHeader } from '../ui/AppShell'
import {
  Banner,
  Button,
  DataTable,
  EmptyState,
  Field,
  Modal,
  PageBody,
  Pager,
  Pill,
  SegmentedControl,
  TableSkeleton,
  Td,
  Th,
} from '../ui/primitives'
import { inr } from '../lib/money'

/// The gift fulfilment queue (migration 0096).
///
/// A gift shop is not a restaurant: it has no owner, no staff row, no address
/// and no coordinates, so none of the food machinery reaches it. Zopiqnow packs
/// these and couriers them, which means **this page is the only thing that moves
/// a gift order along.** An order nobody works here is an order that never
/// leaves.
///
/// Oldest first and new-first by default, like the support queue and for the
/// same reason: a worklist is worked from the bottom.

const PAGE_SIZE = 50

type Filter = GiftOrderStatus | 'all'

const filterOptions: { value: Filter; label: string }[] = [
  { value: 'placed', label: 'New' },
  { value: 'accepted', label: 'Preparing' },
  { value: 'dispatched', label: 'With courier' },
  { value: 'delivered', label: 'Delivered' },
  { value: 'cancelled', label: 'Cancelled' },
  { value: 'all', label: 'All' },
]

const tones: Record<GiftOrderStatus, 'live' | 'warn' | 'danger' | 'neutral' | 'brand'> = {
  placed: 'warn',
  accepted: 'brand',
  dispatched: 'live',
  delivered: 'live',
  cancelled: 'neutral',
}

function when(iso: string) {
  return new Date(iso).toLocaleString('en-IN', {
    day: '2-digit',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  })
}

function waited(iso: string) {
  const mins = Math.max(0, Math.round((Date.now() - new Date(iso).getTime()) / 60000))
  if (mins < 60) return `${mins}m`
  if (mins < 60 * 24) return `${Math.floor(mins / 60)}h`
  return `${Math.floor(mins / (60 * 24))}d`
}

/// What each status can become. Mirrors `admin_set_gift_order_status` exactly —
/// the database is the wall, and offering a button it would refuse is offering
/// a call that fails.
const nextOf: Record<GiftOrderStatus, GiftOrderStatus[]> = {
  placed: ['accepted', 'cancelled'],
  accepted: ['dispatched', 'cancelled'],
  dispatched: ['delivered'],
  delivered: [],
  cancelled: [],
}

export function GiftOrdersPage() {
  const [rows, setRows] = useState<GiftOrderRow[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [note, setNote] = useState<string | null>(null)

  const [filter, setFilter] = useState<Filter>('placed')
  const [page, setPage] = useState(0)

  const [open, setOpen] = useState<GiftOrderRow | null>(null)
  const [lines, setLines] = useState<GiftOrderLineRow[] | null>(null)
  const [courier, setCourier] = useState('')
  const [tracking, setTracking] = useState('')
  const [reason, setReason] = useState('')
  const [busy, setBusy] = useState(false)

  const load = useCallback(async (opts: { filter: Filter; page: number }) => {
    try {
      const next = await api.giftOrders({
        status: opts.filter === 'all' ? null : opts.filter,
        limit: PAGE_SIZE,
        offset: opts.page * PAGE_SIZE,
      })
      setRows(next)
      setError(null)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }, [])

  useEffect(() => {
    void load({ filter, page })
  }, [load, filter, page])

  const total = rows?.[0]?.total_count ?? 0
  const pages = Math.max(1, Math.ceil(total / PAGE_SIZE))

  const subtitle = useMemo(() => {
    if (rows === null) return 'Gifts to pack and send.'
    if (total === 0) return filter === 'placed' ? 'Nothing waiting.' : 'Nothing here.'
    return `${total} order${total === 1 ? '' : 's'}`
  }, [rows, total, filter])

  async function openOrder(order: GiftOrderRow) {
    setOpen(order)
    setLines(null)
    setCourier(order.courier_name ?? '')
    setTracking(order.tracking_ref ?? '')
    setReason('')
    try {
      setLines(await api.giftOrderItems(order.id))
    } catch {
      // The lines are detail. A missing read must not stop somebody dispatching.
      setLines([])
    }
  }

  async function move(to: GiftOrderStatus) {
    if (!open) return
    setBusy(true)
    setError(null)
    try {
      await api.setGiftOrderStatus(open.id, to, {
        courier: courier.trim() || undefined,
        tracking: tracking.trim() || undefined,
        reason: reason.trim() || undefined,
      })
      setNote(`${open.id} is now ${GIFT_STATUS_LABEL[to].toLowerCase()}.`)
      setOpen(null)
      await load({ filter, page })
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  return (
    <>
      <PageHeader
        title="Gift orders"
        subtitle={subtitle}
        action={
          <SegmentedControl
            label="Show"
            options={filterOptions}
            value={filter}
            onChange={(v) => {
              setFilter(v)
              setPage(0)
            }}
          />
        }
      />

      <PageBody>
        {error && (
          <Banner tone="error" className="mb-4" onDismiss={() => setError(null)}>
            {error}
          </Banner>
        )}
        {note && (
          <Banner tone="success" className="mb-4" onDismiss={() => setNote(null)}>
            {note}
          </Banner>
        )}

        
          {rows === null ? (
            <TableSkeleton rows={6} />
          ) : rows.length === 0 ? (
            <EmptyState
              title="Nothing to send"
              body={
                filter === 'placed'
                  ? 'Every gift order has been picked up.'
                  : 'No gift orders match this filter.'
              }
            />
          ) : (
            <>
              <DataTable label="Gift orders" minWidth={720}>
                <thead>
                  <tr>
                    <Th>Waiting</Th>
                    <Th>Order</Th>
                    <Th>Shop</Th>
                    <Th>Sending to</Th>
                    <Th align="right">Value</Th>
                    <Th align="right" hideLabel>Actions</Th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((g) => (
                    <tr key={g.id}>
                      <Td>
                        <p className="font-semibold text-ink">
                          {g.status === 'delivered' || g.status === 'cancelled'
                            ? '—'
                            : waited(g.created_at)}
                        </p>
                        <p className="text-xs text-ink-muted">{when(g.created_at)}</p>
                      </Td>
                      <Td>
                        <p className="text-ink">{g.id}</p>
                        <Pill tone={tones[g.status]}>
                          {GIFT_STATUS_LABEL[g.status]}
                        </Pill>
                        {g.courier_name && (
                          <p className="mt-1 text-xs text-ink-muted">
                            {g.courier_name}
                            {g.tracking_ref ? ` · ${g.tracking_ref}` : ''}
                          </p>
                        )}
                      </Td>
                      <Td>
                        <p className="text-ink">{g.shop_name}</p>
                        <p className="text-xs text-ink-muted">
                          {g.item_count} item{g.item_count === 1 ? '' : 's'}
                        </p>
                      </Td>
                      <Td>
                        <p className="text-ink">{g.customer_phone}</p>
                        <p className="text-xs text-ink-muted">{g.delivery_to}</p>
                      </Td>
                      <Td align="right" className="font-semibold text-ink">
                        {inr(g.total)}
                      </Td>
                      <Td align="right">
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => void openOrder(g)}
                        >
                          {nextOf[g.status].length > 0 ? 'Work it' : 'View'}
                        </Button>
                      </Td>
                    </tr>
                  ))}
                </tbody>
              </DataTable>

              <Pager page={page} pages={pages} onChange={setPage} />
            </>
          )}
        
      </PageBody>

      {open && (
        <Modal
          busy={busy}
          onClose={() => setOpen(null)}
          title={`${open.id} — ${open.shop_name}`}
          footer={
            <>
              <Button variant="secondary" onClick={() => setOpen(null)} disabled={busy}>
                Close
              </Button>
              {nextOf[open.status].includes('cancelled') && (
                <Button
                  variant="danger"
                  onClick={() => void move('cancelled')}
                  loading={busy}
                >
                  Cancel order
                </Button>
              )}
              {open.status === 'placed' && (
                <Button variant="primary" onClick={() => void move('accepted')} loading={busy}>
                  Accept
                </Button>
              )}
              {open.status === 'accepted' && (
                <Button
                  variant="primary"
                  onClick={() => void move('dispatched')}
                  loading={busy}
                  // The database refuses this without a courier. Disabling it
                  // here puts the wall where the finger is.
                  disabled={courier.trim() === ''}
                >
                  Mark dispatched
                </Button>
              )}
              {open.status === 'dispatched' && (
                <Button variant="primary" onClick={() => void move('delivered')} loading={busy}>
                  Mark delivered
                </Button>
              )}
            </>
          }
        >
          <dl className="grid grid-cols-2 gap-3 text-sm">
            <div>
              <dt className="text-ink-muted">Customer</dt>
              <dd className="text-ink">{open.customer_phone}</dd>
            </div>
            <div>
              <dt className="text-ink-muted">Paid</dt>
              <dd className="text-ink">
                {inr(open.total)} · {open.payment_id ?? 'no reference'}
              </dd>
            </div>
            <div className="col-span-2">
              <dt className="text-ink-muted">Sending to</dt>
              <dd className="text-ink">{open.delivery_to}</dd>
            </div>
            {open.delivery_notes && (
              <div className="col-span-2">
                <dt className="text-ink-muted">Notes</dt>
                <dd className="text-ink">{open.delivery_notes}</dd>
              </div>
            )}
          </dl>

          <p className="mt-5 text-xs font-semibold uppercase tracking-wide text-ink-muted">
            What to pack
          </p>
          {lines === null ? (
            <p className="mt-1 text-sm text-ink-muted">Loading…</p>
          ) : (
            <ul className="mt-1 text-sm text-ink">
              {lines.map((l, i) => (
                <li key={i} className="flex justify-between py-0.5">
                  <span>
                    {l.quantity} × {l.name}
                  </span>
                  <span>{inr(l.line_total)}</span>
                </li>
              ))}
              <li className="mt-2 flex justify-between border-t border-line pt-2 font-semibold">
                <span>Subtotal + GST</span>
                <span>
                  {inr(open.subtotal)} + {inr(open.taxes)}
                </span>
              </li>
            </ul>
          )}

          {open.status === 'accepted' && (
            <>
              <Field
                className="mt-5"
                label="Courier"
                value={courier}
                onChange={(e) => setCourier(e.target.value)}
                placeholder="Blue Dart"
                hint="Shown to the customer on their order screen. Required — a parcel on its way with nobody named is a customer who cannot ask anyone anything."
              />
              <Field
                className="mt-4"
                label="Tracking number (optional)"
                value={tracking}
                onChange={(e) => setTracking(e.target.value)}
                placeholder="Leave empty if this courier issues none"
              />
            </>
          )}

          {nextOf[open.status].includes('cancelled') && (
            <Field
              className="mt-4"
              label="If cancelling, why"
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder="The shop is out of stock"
              hint="The customer reads this on their order screen."
            />
          )}
        </Modal>
      )}
    </>
  )
}
