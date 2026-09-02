import { useCallback, useEffect, useMemo, useState } from 'react'
import { api, DELIVERY_LABEL, STATUS_LABEL } from '../lib/api'
import type {
  AllOrderRow,
  OrderPhotoRow,
  OrderStatus,
  RestaurantRow,
} from '../lib/api'
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
  SearchField,
  SegmentedControl,
  Select,
  Skeleton,
  TableSkeleton,
  Td,
  Th,
} from '../ui/primitives'
import { inr } from '../lib/money'

/// The whole order book — every order ever placed, not just the open ones.
///
/// The live board (`/`) answers "what is happening right now" and deliberately
/// shows nothing that has ended. This screen is the other question: what
/// happened. So the defaults are opposite — newest first, every status, and a
/// pager, because unlike the floor this list grows without bound.
///
/// It does not poll. A history does not change while you read it, and a
/// fifteen-second refresh that reshuffled the page under a delete confirmation
/// would be actively hostile.

const PAGE_SIZE = 50

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

type Range = 'all' | 'today' | '7d' | '30d'

const rangeOptions: { value: Range; label: string }[] = [
  { value: 'all', label: 'All time' },
  { value: 'today', label: 'Today' },
  { value: '7d', label: '7 days' },
  { value: '30d', label: '30 days' },
]

const statusOptions: { value: OrderStatus | 'any'; label: string }[] = [
  { value: 'any', label: 'Any status' },
  { value: 'placed', label: STATUS_LABEL.placed },
  { value: 'accepted', label: STATUS_LABEL.accepted },
  { value: 'preparing', label: STATUS_LABEL.preparing },
  { value: 'ready_for_pickup', label: STATUS_LABEL.ready_for_pickup },
  { value: 'out_for_delivery', label: STATUS_LABEL.out_for_delivery },
  { value: 'delivered', label: STATUS_LABEL.delivered },
  { value: 'cancelled', label: STATUS_LABEL.cancelled },
  { value: 'rejected', label: STATUS_LABEL.rejected },
]

/// A range as the start instant it means, in the browser's own timezone — the
/// console is used from one desk in one country, and `toISOString()` hands
/// Postgres a `timestamptz` it can compare without either side guessing.
function startOf(range: Range): string | null {
  if (range === 'all') return null
  const d = new Date()
  d.setHours(0, 0, 0, 0)
  if (range === '7d') d.setDate(d.getDate() - 6)
  if (range === '30d') d.setDate(d.getDate() - 29)
  return d.toISOString()
}

function when(iso: string) {
  return new Date(iso).toLocaleString('en-IN', {
    day: '2-digit',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  })
}

export function AllOrdersPage() {
  const [rows, setRows] = useState<AllOrderRow[] | null>(null)
  const [restaurants, setRestaurants] = useState<RestaurantRow[]>([])
  const [error, setError] = useState<string | null>(null)
  const [note, setNote] = useState<string | null>(null)

  // Filters. `query` is what is being typed; it only reaches the database when
  // the form is submitted, so a half-typed order id does not run four searches.
  const [query, setQuery] = useState('')
  const [applied, setApplied] = useState('')
  const [status, setStatus] = useState<OrderStatus | 'any'>('any')
  const [range, setRange] = useState<Range>('all')
  const [restaurantId, setRestaurantId] = useState<string>('')
  const [page, setPage] = useState(0)

  // The evidence viewer (0094). `photosFor` is the order whose modal is open;
  // `photos` is null while the one fetch is in flight.
  const [photosFor, setPhotosFor] = useState<AllOrderRow | null>(null)
  const [photos, setPhotos] = useState<OrderPhotoRow | null>(null)
  const [photosError, setPhotosError] = useState<string | null>(null)

  const [deleting, setDeleting] = useState<AllOrderRow | null>(null)
  const [reason, setReason] = useState('')
  const [confirmId, setConfirmId] = useState('')
  const [busy, setBusy] = useState(false)

  const load = useCallback(
    async (opts: {
      query: string
      status: OrderStatus | 'any'
      range: Range
      restaurantId: string
      page: number
    }) => {
      try {
        const next = await api.allOrders({
          query: opts.query,
          status: opts.status === 'any' ? null : opts.status,
          restaurantId: opts.restaurantId === '' ? null : opts.restaurantId,
          from: startOf(opts.range),
          limit: PAGE_SIZE,
          offset: opts.page * PAGE_SIZE,
        })
        setRows(next)
        setApplied(opts.query)
        setError(null)
      } catch (e) {
        setError(e instanceof Error ? e.message : String(e))
      }
    },
    [],
  )

  // One effect for every filter, so changing any of them is one round trip and
  // there is no order in which two of them can disagree about what is on screen.
  //
  // It depends on `applied` and never on `query`, which is the whole reason the
  // two exist separately: typing an order id must not fire a request per
  // keystroke, and submitting the form is what moves `query` into `applied`.
  useEffect(() => {
    void load({ query: applied, status, range, restaurantId, page })
  }, [load, applied, status, range, restaurantId, page])

  useEffect(() => {
    api
      .listRestaurants()
      .then(setRestaurants)
      // The dropdown is a convenience; the page works without it, so a failure
      // here must not take the order list down with it.
      .catch(() => setRestaurants([]))
  }, [])

  const total = rows?.[0]?.total_count ?? 0
  const pages = Math.max(1, Math.ceil(total / PAGE_SIZE))
  const filtered =
    applied !== '' || status !== 'any' || range !== 'all' || restaurantId !== ''

  const subtitle = useMemo(() => {
    if (rows === null) return 'Every order ever placed.'
    if (total === 0) return 'Nothing matches these filters.'
    const start = page * PAGE_SIZE + 1
    const end = page * PAGE_SIZE + rows.length
    return `${start}–${end} of ${total} order${total === 1 ? '' : 's'}`
  }, [rows, total, page])

  function resetFilters() {
    setQuery('')
    setApplied('')
    setStatus('any')
    setRange('all')
    setRestaurantId('')
    setPage(0)
  }

  /// Opens the evidence modal and fetches the three URLs. The modal goes up
  /// first, with a "Loading" line inside it — a support call is waiting on this
  /// and a button that does nothing for half a second reads as broken.
  async function openPhotos(order: AllOrderRow) {
    setPhotosFor(order)
    setPhotos(null)
    setPhotosError(null)
    try {
      const rows = await api.orderPhotos(order.order_id)
      setPhotos(rows[0] ?? null)
    } catch (e) {
      setPhotosError(e instanceof Error ? e.message : String(e))
    }
  }

  async function confirmDelete() {
    if (!deleting) return
    setBusy(true)
    setError(null)
    try {
      const said = await api.deleteOrder(deleting.order_id, reason)
      setNote(said)
      setDeleting(null)
      setReason('')
      setConfirmId('')
      // Reloading the same page after deleting its only row returns nothing,
      // and an empty page takes the pager with it — Previous included. Step
      // back instead and let the filter effect do the reload.
      if (rows?.length === 1 && page > 0) {
        setPage(page - 1)
      } else {
        await load({ query: applied, status, range, restaurantId, page })
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  return (
    <>
      <PageHeader
        title="All orders"
        subtitle={subtitle}
        action={
          <Button
            variant="secondary"
            onClick={() =>
              void load({ query: applied, status, range, restaurantId, page })
            }
          >
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
        {note && (
          <Banner
            tone="success"
            className="mb-4 max-w-3xl"
            onDismiss={() => setNote(null)}
          >
            {note}
          </Banner>
        )}

        <div className="mb-5 space-y-3">
          <SearchField
            label="Find an order"
            placeholder="Order id or phone number"
            value={query}
            onChange={setQuery}
            onSubmit={() => {
              setPage(0)
              setApplied(query.trim())
            }}
          />

          <div className="flex flex-wrap items-center gap-x-6 gap-y-3">
            <SegmentedControl
              label="Status"
              value={status}
              options={statusOptions}
              onChange={(next) => {
                setPage(0)
                setStatus(next)
              }}
            />
            <SegmentedControl
              label="When"
              value={range}
              options={rangeOptions}
              onChange={(next) => {
                setPage(0)
                setRange(next)
              }}
            />
            <Select
              label="Restaurant"
              hideLabel
              size="sm"
              value={restaurantId}
              onChange={(e) => {
                setPage(0)
                setRestaurantId(e.target.value)
              }}
            >
              <option value="">Every restaurant</option>
              {restaurants.map((r) => (
                <option key={r.id} value={r.id}>
                  {r.name}
                </option>
              ))}
            </Select>
            {filtered && (
              <Button variant="ghost" onClick={resetFilters}>
                Clear filters
              </Button>
            )}
          </div>
        </div>

        {rows === null ? (
          <TableSkeleton rows={6} />
        ) : rows.length === 0 ? (
          <EmptyState
            title={filtered ? 'No match' : 'No orders yet'}
            body={
              filtered
                ? 'Nothing matches these filters. Order ids look like ZPQ-1044; a phone number matches on its last digits, with or without +91.'
                : 'This fills itself the moment somebody orders.'
            }
            action={
              filtered ? (
                <Button variant="secondary" onClick={resetFilters}>
                  Clear filters
                </Button>
              ) : undefined
            }
          />
        ) : (
          <>
            <DataTable label="All orders" minWidth={900}>
              <thead>
                <tr>
                  <Th>Order</Th>
                  <Th>Restaurant</Th>
                  <Th>Customer</Th>
                  <Th>Rider</Th>
                  <Th align="right">Total</Th>
                  <Th align="right" hideLabel>
                    Actions
                  </Th>
                </tr>
              </thead>
              <tbody>
                {rows.map((o) => (
                  <tr key={o.order_id}>
                    <Td>
                        <div className="flex flex-wrap items-center gap-2">
                          <span className="font-semibold text-ink">
                            {o.order_id}
                          </span>
                          <Pill tone={statusTones[o.status]}>
                            {STATUS_LABEL[o.status]}
                          </Pill>
                        </div>
                        <p className="mt-1 text-xs text-ink-muted">
                          {when(o.placed_at)} · {o.item_count} item
                          {o.item_count === 1 ? '' : 's'}
                        </p>
                        {/* The invoice number is the fact that makes this row
                            irreversible, so it is on the row and not only in the
                            dialog that destroys it. */}
                        {o.invoice_no && (
                          <p className="mt-0.5 text-xs text-ink-muted">
                            {o.invoice_no}
                          </p>
                        )}
                        {o.status_reason && (
                          <p className="mt-0.5 text-xs text-warn">
                            {o.status_reason}
                          </p>
                        )}
                    </Td>
                    <Td className="text-ink">{o.restaurant_name}</Td>
                    <Td>
                      <p className="text-ink">{o.customer_phone}</p>
                      <p className="text-xs text-ink-muted">{o.delivery_to}</p>
                    </Td>
                    <Td>
                      {o.rider_name ? (
                          <>
                            <p className="text-ink">{o.rider_name}</p>
                            <p className="text-xs text-ink-muted">
                              {o.delivery_state
                                ? DELIVERY_LABEL[o.delivery_state]
                                : ''}
                            </p>
                          </>
                        ) : (
                        <span className="text-ink-muted">—</span>
                      )}
                    </Td>
                    <Td align="right">
                      <p className="font-semibold text-ink">{inr(o.total)}</p>
                        <p className="text-xs text-ink-muted">
                        {o.payment_method === 'upi' ? 'prepaid' : 'cash'}
                      </p>
                    </Td>
                    <Td align="right">
                      <Button
                        variant="ghost"
                        size="sm"
                        onClick={() => void openPhotos(o)}
                      >
                          Photos
                        </Button>
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => {
                            setDeleting(o)
                            setReason('')
                            setConfirmId('')
                          }}
                        >
                        Delete
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

      {photosFor && (
        <Modal
          // `lg`, because this is the viewer rather than a glance. Three
          // photographs in the default `md` land at about 120px square, and what
          // support is usually doing here is reading a receipt taped to a bag.
          // Support's own copy of these three stays small on purpose — there the
          // photographs sit beside a complaint being read, and the full size is
          // one click away in both.
          size="lg"
          onClose={() => setPhotosFor(null)}
          title={`Photos — ${photosFor.order_id}`}
          footer={
            <Button variant="secondary" onClick={() => setPhotosFor(null)}>
              Close
            </Button>
          }
        >
          {photosError ? (
            <Banner tone="warn">{photosError}</Banner>
          ) : !photos ? (
            <div className="grid grid-cols-3 gap-3">
              <Skeleton className="aspect-square w-full" />
              <Skeleton className="aspect-square w-full" />
              <Skeleton className="aspect-square w-full" />
            </div>
          ) : (
            <>
              <p className="text-sm text-ink-muted">
                Taken by the kitchen as the order was cooked and packed, and by
                the rider at the handover. A missing one means nobody took it —
                the apps ask for all three, but the database does not refuse an
                order without them.
              </p>
              <div className="mt-5 grid gap-5 sm:grid-cols-3">
                <PhotoPane label="Cooked" url={photos.cooked_photo_url} />
                <PhotoPane label="Packed" url={photos.packed_photo_url} />
                <PhotoPane label="Handover" url={photos.delivery_photo_url} />
              </div>
            </>
          )}
        </Modal>
      )}

      {deleting && (
        <Modal
          busy={busy}
          onClose={() => setDeleting(null)}
          title={`Delete ${deleting.order_id}?`}
          footer={
            <>
              <Button
                variant="secondary"
                onClick={() => setDeleting(null)}
                disabled={busy}
              >
                Keep it
              </Button>
              <Button
                variant="danger"
                onClick={() => void confirmDelete()}
                loading={busy}
                // Typing the id is not a permission check — the database refuses
                // nothing here. It is the pause between meaning to delete one
                // order and deleting the row your mouse happened to be over.
                //
                // The reason is the other half of that. `admin_delete_order`
                // stores a blank one as blank, and once the row and everything
                // hanging off it are gone, that log line is the only account of
                // an order that existed.
                disabled={
                  reason.trim() === '' ||
                  confirmId.trim().toUpperCase() !== deleting.order_id.toUpperCase()
                }
              >
                Delete for good
              </Button>
            </>
          }
        >
          <p className="text-sm text-ink-muted">
            The order row is destroyed, along with its {deleting.item_count} item
            {deleting.item_count === 1 ? '' : 's'}, its delivery record, the
            messages sent about it, and the customer&rsquo;s review of it. There
            is no undo.
          </p>

          {deleting.invoice_no && (
            <Banner tone="warn" className="mt-4">
              This order was delivered and carries tax invoice{' '}
              <strong>{deleting.invoice_no}</strong>. Deleting it destroys that
              document and leaves a permanent gap in {deleting.restaurant_name}
              &rsquo;s invoice series — the counter does not roll back. It will
              also reduce the rider and restaurant earnings this order was
              counted into.
            </Banner>
          )}

          <Field
            className="mt-5"
            label="Why"
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            placeholder="Test order from staging"
            hint="Kept in the deletion log with your email. It is the only record that will remain."
          />

          <Field
            className="mt-4"
            label={`Type ${deleting.order_id} to confirm`}
            value={confirmId}
            onChange={(e) => setConfirmId(e.target.value)}
            placeholder={deleting.order_id}
          />
        </Modal>
      )}
    </>
  )
}

/// One of the three photographs, or the honest absence of it.
///
/// The image is a plain `<img>` at the Cloudinary URL and a link to the full
/// size — support needs to zoom into a receipt taped to a bag, and a lightbox
/// this console would have to build is a worse version of the browser's own
/// image view.
function PhotoPane({ label, url }: { label: string; url: string | null }) {
  return (
    <div>
      <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-ink-muted">
        {label}
      </p>
      {url ? (
        <a href={url} target="_blank" rel="noreferrer">
          <img
            src={url}
            alt={`${label} photo`}
            loading="lazy"
            className="aspect-square w-full rounded-field border border-line object-cover"
          />
        </a>
      ) : (
        <div className="flex aspect-square w-full items-center justify-center rounded-field border border-dashed border-line">
          <span className="text-xs text-ink-muted">Not taken</span>
        </div>
      )}
    </div>
  )
}
