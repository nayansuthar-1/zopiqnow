import { useCallback, useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { api } from '../lib/api'
import type { RestaurantRow, ReviewRow, ReviewSummary } from '../lib/api'
import { inr } from '../lib/money'
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
  Select,
  StatTile,
  TableSkeleton,
  Td,
  Th,
  Toggle,
} from '../ui/primitives'
import { useToast } from '../ui/toast'
import { useUrlPage, useUrlState } from '../ui/urlState'

/// What customers said, and the one lever the platform has over it.
///
/// `reviews` has existed since 0062 and until 0165 the console could see the
/// average and never the sentences — which meant the party a complaint about a
/// review is addressed to was the only party unable to read it.
///
/// **The summary is not decoration.** Four reviews across twelve kitchens is the
/// state of this feature, and a moderation queue that opened on a near-empty
/// list without saying so would read as a broken screen rather than as an
/// honest one. The arrival rate — reviews against delivered orders — is the
/// number that says whether the asking works at all.
///
/// **Removal is a delete.** Not a hidden flag: three readers already select
/// from that table, and the first one written without the flag puts the review
/// back in front of customers. Nothing is lost — the whole row is kept in the
/// audit trail (0164 reads it), along with the reason, which the database
/// refuses to accept as blank.

const PAGE_SIZE = 50

type Band = 'any' | 'low' | 'mid' | 'high'

const bandOptions: { value: Band; label: string }[] = [
  { value: 'any', label: 'Any rating' },
  { value: 'low', label: '1–2 ★' },
  { value: 'mid', label: '3 ★' },
  { value: 'high', label: '4–5 ★' },
]

const BAND_VALUES = bandOptions.map((o) => o.value)

/// The band as the two bounds the RPC takes. Kept here rather than in the
/// database so the wording on the buttons and the numbers behind them cannot
/// drift apart.
const bands: Record<Band, { min: number | null; max: number | null }> = {
  any: { min: null, max: null },
  low: { min: 1, max: 2 },
  mid: { min: 3, max: 3 },
  high: { min: 4, max: 5 },
}

function when(iso: string) {
  return new Date(iso).toLocaleString('en-IN', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
  })
}

/// Filled stars against the five that were on offer. The number is written out
/// beside them, because a row of shapes is not a figure anybody can compare and
/// a screen reader gets nothing from five glyphs.
function Stars({ value }: { value: number | null }) {
  if (value === null) {
    return <span className="text-ink-muted">not rated</span>
  }
  return (
    <span className="whitespace-nowrap text-ink">
      <span aria-hidden className="text-warn">
        {'★'.repeat(value)}
        <span className="text-line">{'★'.repeat(5 - value)}</span>
      </span>{' '}
      <span className="tabular-nums">{value}</span>
    </span>
  )
}

export function ReviewsPage() {
  const toast = useToast()
  const [rows, setRows] = useState<ReviewRow[] | null>(null)
  const [summary, setSummary] = useState<ReviewSummary | null>(null)
  const [restaurants, setRestaurants] = useState<RestaurantRow[]>([])
  const [error, setError] = useState<string | null>(null)

  const [restaurantId, setRestaurantId] = useUrlState('restaurant', '')
  const [band, setBand] = useUrlState<Band>('rating', 'any', BAND_VALUES)
  const [withComment, setWithComment] = useUrlState('said', '')
  const [page, setPage] = useUrlPage()

  const [removing, setRemoving] = useState<ReviewRow | null>(null)
  const [reason, setReason] = useState('')
  const [busy, setBusy] = useState(false)

  const onlyWithComment = withComment === 'yes'

  const load = useCallback(async () => {
    try {
      setRows(
        await api.reviews({
          restaurantId: restaurantId === '' ? null : restaurantId,
          minRating: bands[band].min,
          maxRating: bands[band].max,
          withComment: onlyWithComment,
          limit: PAGE_SIZE,
          offset: page * PAGE_SIZE,
        }),
      )
      setError(null)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }, [restaurantId, band, onlyWithComment, page])

  // Its own call, and reloaded after a removal: taking a review down moves the
  // averages, and a summary left over from before the act would contradict the
  // sentence the database just returned.
  const loadSummary = useCallback(async () => {
    try {
      setSummary(await api.reviewSummary())
    } catch {
      setSummary(null)
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  useEffect(() => {
    void loadSummary()
    api
      .listRestaurants()
      .then(setRestaurants)
      .catch(() => setRestaurants([]))
  }, [loadSummary])

  const total = rows?.[0]?.total_count ?? 0
  const pages = Math.max(1, Math.ceil(total / PAGE_SIZE))
  const narrowed = restaurantId !== '' || band !== 'any' || onlyWithComment

  const subtitle = useMemo(() => {
    if (rows === null) return 'What customers said about the food and the ride.'
    if (total === 0) return narrowed ? 'Nothing matches these filters.' : 'Nobody has left one yet.'
    const start = page * PAGE_SIZE + 1
    const end = page * PAGE_SIZE + rows.length
    return `${start}–${end} of ${total} review${total === 1 ? '' : 's'}`
  }, [rows, total, page, narrowed])

  function reset() {
    setRestaurantId('')
    setBand('any')
    setWithComment('')
    setPage(0)
  }

  async function confirmRemove() {
    if (!removing) return
    setBusy(true)
    setError(null)
    try {
      const said = await api.deleteReview(removing.order_id, reason)
      toast(said)
      setRemoving(null)
      setReason('')
      await loadSummary()
      // The same trick All orders uses: reloading a page whose only row just
      // went takes the pager with it, Previous included.
      if (rows?.length === 1 && page > 0) setPage(page - 1)
      else await load()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  return (
    <>
      <PageHeader
        title="Reviews"
        subtitle={subtitle}
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

        {summary && (
          <div className="mb-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <StatTile
              label="Reviews"
              value={String(summary.reviews)}
              // The arrival rate, which is the number this feature is actually
              // judged by. A percentage of nothing is not a fact, so an empty
              // platform gets a sentence instead.
              sub={
                summary.reviewable_orders > 0
                  ? `${Math.round(
                      (summary.reviews / summary.reviewable_orders) * 100,
                    )}% of ${summary.reviewable_orders} delivered orders`
                  : 'no delivered order has been reviewable yet'
              }
            />
            <StatTile
              label="With a sentence"
              value={String(summary.with_comment)}
              sub={
                summary.reviews > 0
                  ? `${summary.reviews - summary.with_comment} left a rating and no words`
                  : undefined
              }
            />
            <StatTile
              label="Average, food"
              value={summary.avg_food === null ? '—' : summary.avg_food.toFixed(1)}
              sub={
                summary.restaurants_rated > 0
                  ? `across ${summary.restaurants_rated} restaurant${
                      summary.restaurants_rated === 1 ? '' : 's'
                    }`
                  : 'no restaurant is rated'
              }
            />
            <StatTile
              label="Average, rider"
              value={
                summary.avg_rider === null ? '—' : summary.avg_rider.toFixed(1)
              }
              sub={`${summary.rider_rated} of ${summary.reviews} rated the ride`}
            />
          </div>
        )}

        <div className="mb-5 flex flex-wrap items-center gap-x-6 gap-y-3">
          <SegmentedControl
            label="Rating"
            value={band}
            options={bandOptions}
            onChange={(next) => {
              setPage(0)
              setBand(next)
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
          <Toggle
            label="Only the ones with words"
            checked={onlyWithComment}
            onChange={(next) => {
              setPage(0)
              setWithComment(next ? 'yes' : '')
            }}
          />
          {narrowed && (
            <Button variant="ghost" onClick={reset}>
              Clear filters
            </Button>
          )}
        </div>

        {rows === null ? (
          <TableSkeleton rows={5} />
        ) : rows.length === 0 ? (
          <EmptyState
            title={narrowed ? 'No match' : 'No reviews yet'}
            body={
              narrowed
                ? 'Nothing matches these filters.'
                : 'A customer is asked for one after the order is delivered, and there is an hour to change it. Nobody has left one yet.'
            }
            action={
              narrowed ? (
                <Button variant="secondary" onClick={reset}>
                  Clear filters
                </Button>
              ) : undefined
            }
          />
        ) : (
          <>
            <DataTable label="Reviews" minWidth={960}>
              <thead>
                <tr>
                  <Th>Order</Th>
                  <Th>Restaurant</Th>
                  <Th>Food</Th>
                  <Th>Rider</Th>
                  <Th>What they said</Th>
                  <Th align="right" hideLabel>
                    Actions
                  </Th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.order_id}>
                    <Td>
                      <Link
                        to={`/orders/${r.order_id}`}
                        className="font-semibold text-ink underline decoration-line underline-offset-4 hover:decoration-brand-ink"
                      >
                        {r.order_id}
                      </Link>
                      <p className="mt-1 text-xs text-ink-muted">
                        {when(r.created_at)}
                        {r.order_total !== null && ` · ${inr(r.order_total)}`}
                      </p>
                      {/* The context this screen exists for: one star written
                          after a refund was refused is not a review of the
                          food. */}
                      {r.refund_status && (
                        <p className="mt-1">
                          <Pill tone="warn">refund {r.refund_status}</Pill>
                        </p>
                      )}
                    </Td>
                    <Td>
                      <p className="text-ink">{r.restaurant_name}</p>
                      <p className="mt-1 text-xs text-ink-muted">
                        {r.customer_name ?? 'no name'}
                        {r.customer_phone && ` · ${r.customer_phone}`}
                      </p>
                    </Td>
                    <Td>
                      <Stars value={r.food_rating} />
                    </Td>
                    <Td>
                      <Stars value={r.rider_rating} />
                      {r.rider_name && (
                        <p className="mt-1 text-xs text-ink-muted">
                          {r.rider_name}
                        </p>
                      )}
                    </Td>
                    <Td>
                      {r.comment ? (
                        <p className="max-w-sm wrap-break-word text-ink">
                          {r.comment}
                        </p>
                      ) : (
                        <span className="text-ink-muted">
                          a rating, no words
                        </span>
                      )}
                    </Td>
                    <Td align="right">
                      <Button
                        variant="ghost"
                        size="sm"
                        onClick={() => {
                          setRemoving(r)
                          setReason('')
                        }}
                      >
                        Remove
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

      {removing && (
        <Modal
          busy={busy}
          onClose={() => setRemoving(null)}
          title={`Remove the review on ${removing.order_id}?`}
          footer={
            <>
              <Button
                variant="secondary"
                onClick={() => setRemoving(null)}
                disabled={busy}
              >
                Leave it up
              </Button>
              <Button
                variant="danger"
                onClick={() => void confirmRemove()}
                loading={busy}
                disabled={reason.trim() === ''}
              >
                Remove it
              </Button>
            </>
          }
        >
          <p className="text-sm text-ink-muted">
            {removing.restaurant_name} · {removing.customer_name ?? 'no name'}
            {removing.customer_phone && ` · ${removing.customer_phone}`}
          </p>

          <div className="mt-4 rounded-field border border-line bg-canvas p-4">
            <div className="flex flex-wrap gap-x-6 gap-y-1">
              <span className="text-sm text-ink-muted">
                Food <Stars value={removing.food_rating} />
              </span>
              <span className="text-sm text-ink-muted">
                Rider <Stars value={removing.rider_rating} />
              </span>
            </div>
            <p className="mt-3 wrap-break-word text-sm text-ink">
              {removing.comment ?? 'A rating, with nothing written.'}
            </p>
          </div>

          <p className="mt-4 text-sm text-ink-muted">
            The row is destroyed and both ratings are recomputed without it —{' '}
            {removing.restaurant_name}&rsquo;s average, and{' '}
            {removing.rider_name ? `${removing.rider_name}'s` : 'the rider’s'}{' '}
            if the ride was rated. The review, and what you write below, are kept
            in the audit log.
          </p>

          <Field
            className="mt-4"
            label="Why"
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            placeholder="Names the rider and repeats a slur."
            hint="Required. It is the only account of why a customer’s words were taken down."
          />
        </Modal>
      )}
    </>
  )
}
