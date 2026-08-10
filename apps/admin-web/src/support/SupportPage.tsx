import { useCallback, useEffect, useMemo, useState } from 'react'
import { api, GIFT_STATUS_LABEL, ISSUE_LABEL, STATUS_LABEL } from '../lib/api'
import type {
  GiftOrderStatus,
  OrderPhotoRow,
  OrderStatus,
  SupportTicketRow,
} from '../lib/api'
import { PageHeader } from '../ui/AppShell'
import {
  Banner,
  Button,
  EmptyState,
  Field,
  Modal,
  Pill,
  SegmentedControl,
  TableSkeleton,
} from '../ui/primitives'

/// The complaint queue (migration 0095).
///
/// Before this existed, a customer whose order arrived wrong had no route into
/// the system at all — the app's "Support" button showed a snackbar promising a
/// call and then did nothing. This is the other end of the button that replaced
/// it.
///
/// Oldest first and open-only by default, which is the opposite of every other
/// list in this console. A history is read from the top; a worklist is worked
/// from the bottom, and the ticket that has waited longest is the one that has
/// waited longest.
///
/// It does not poll. A queue that reshuffled itself under a half-written reply
/// would lose the reply.

const PAGE_SIZE = 50

type Filter = 'open' | 'resolved' | 'all'

const filterOptions: { value: Filter; label: string }[] = [
  { value: 'open', label: 'Open' },
  { value: 'resolved', label: 'Closed' },
  { value: 'all', label: 'All' },
]

function when(iso: string) {
  return new Date(iso).toLocaleString('en-IN', {
    day: '2-digit',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  })
}

/// How long it has been sitting there, in the coarsest unit that is still true.
/// Support is triaging, not stopwatching: "3d" is the number that changes a
/// decision, and "3d 4h 12m" is the same number with noise on it.
function waited(iso: string) {
  const mins = Math.max(0, Math.round((Date.now() - new Date(iso).getTime()) / 60000))
  if (mins < 60) return `${mins}m`
  if (mins < 60 * 24) return `${Math.floor(mins / 60)}h`
  return `${Math.floor(mins / (60 * 24))}d`
}

/// The order's status in words. Two label maps, because the two kinds of order
/// have two sets of statuses (0114): a gift is `dispatched`, which is not a food
/// status at all, and reading it out of `STATUS_LABEL` would print nothing —
/// a blank where support needs to know the parcel has left.
function orderStatusLabel(tk: SupportTicketRow) {
  return tk.kind === 'gift'
    ? GIFT_STATUS_LABEL[tk.order_status as GiftOrderStatus]
    : STATUS_LABEL[tk.order_status as OrderStatus]
}

export function SupportPage() {
  const [rows, setRows] = useState<SupportTicketRow[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [note, setNote] = useState<string | null>(null)

  const [filter, setFilter] = useState<Filter>('open')
  const [page, setPage] = useState(0)

  // The ticket being answered, and the reply being written.
  const [answering, setAnswering] = useState<SupportTicketRow | null>(null)
  const [reply, setReply] = useState('')
  const [busy, setBusy] = useState(false)

  // The order's three photographs (0094), fetched when a ticket is opened.
  // This is the whole reason the evidence exists: somebody says the food never
  // arrived, and there is a picture of it at their door.
  const [photos, setPhotos] = useState<OrderPhotoRow | null>(null)

  const load = useCallback(async (opts: { filter: Filter; page: number }) => {
    try {
      const next = await api.supportTickets({
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
    if (rows === null) return 'What customers said went wrong.'
    if (total === 0) return filter === 'open' ? 'Nothing waiting.' : 'Nothing here.'
    return `${total} ticket${total === 1 ? '' : 's'}`
  }, [rows, total, filter])

  async function open(ticket: SupportTicketRow) {
    setAnswering(ticket)
    setReply('')
    setPhotos(null)
    // A gift has no photographs to fetch: 0094's three are `orders` columns
    // written by a kitchen and a rider, and a gift is couriered with neither.
    // Asking anyway would spend a round trip to be told nothing.
    if (ticket.kind === 'gift') return
    try {
      const found = await api.orderPhotos(ticket.order_id)
      setPhotos(found[0] ?? null)
    } catch {
      // The photographs are context, not the point. A ticket must stay
      // answerable when the evidence read fails.
      setPhotos(null)
    }
  }

  async function confirmResolve() {
    if (!answering) return
    setBusy(true)
    setError(null)
    try {
      const said = await api.resolveTicket(answering.id, reply)
      setNote(said)
      setAnswering(null)
      setReply('')
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
        title="Support"
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

      {error && <Banner tone="error" className="mb-4">{error}</Banner>}
      {note && (
        <Banner tone="success" className="mb-4" onDismiss={() => setNote(null)}>
          {note}
        </Banner>
      )}

      <div className="rounded-xl border border-line bg-surface">
        {rows === null ? (
          <TableSkeleton rows={6} />
        ) : rows.length === 0 ? (
          <EmptyState
            title={filter === 'open' ? 'Nothing waiting' : 'Nothing here'}
            body={
              filter === 'open'
                ? 'Every complaint has been answered.'
                : 'No tickets match this filter.'
            }
          />
        ) : (
          <>
            <div className="overflow-x-auto">
              <table className="w-full text-left text-sm">
                <thead className="border-b border-line text-xs uppercase tracking-wide text-ink-muted">
                  <tr>
                    <th className="px-5 py-3">Waiting</th>
                    <th className="px-5 py-3">Problem</th>
                    <th className="px-5 py-3">Order</th>
                    <th className="px-5 py-3">Customer</th>
                    <th className="px-5 py-3 text-right">Value</th>
                    <th className="px-5 py-3 text-right" />
                  </tr>
                </thead>
                <tbody className="divide-y divide-line">
                  {rows.map((tk) => (
                    <tr key={tk.id}>
                      <td className="px-5 py-4 align-top">
                        <p className="font-semibold text-ink">
                          {tk.status === 'open' ? waited(tk.created_at) : '—'}
                        </p>
                        <p className="text-xs text-ink-muted">
                          {when(tk.created_at)}
                        </p>
                      </td>
                      <td className="px-5 py-4 align-top">
                        <Pill tone={tk.status === 'open' ? 'warn' : 'neutral'}>
                          {ISSUE_LABEL[tk.category]}
                        </Pill>
                        {tk.body && (
                          <p className="mt-1 max-w-md text-xs text-ink-muted">
                            {tk.body}
                          </p>
                        )}
                      </td>
                      <td className="px-5 py-4 align-top">
                        <p className="text-ink">
                          {tk.order_id}
                          {tk.kind === 'gift' && (
                            // Said out loud rather than left to be inferred from
                            // the id prefix. A gift complaint is answered
                            // differently — no kitchen to call, no rider to ask.
                            <span className="ml-2 align-middle">
                              <Pill tone="neutral">Gift</Pill>
                            </span>
                          )}
                        </p>
                        <p className="text-xs text-ink-muted">
                          {tk.seller_name} · {orderStatusLabel(tk)}
                        </p>
                      </td>
                      <td className="px-5 py-4 align-top text-ink">
                        {tk.customer_phone}
                      </td>
                      <td className="px-5 py-4 text-right align-top font-semibold text-ink">
                        ₹{tk.order_total}
                      </td>
                      <td className="px-5 py-4 text-right align-top">
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => void open(tk)}
                        >
                          {tk.status === 'open' ? 'Answer' : 'View'}
                        </Button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            {pages > 1 && (
              <div className="mt-4 flex items-center justify-between px-5 pb-5">
                <Button
                  variant="secondary"
                  disabled={page === 0}
                  onClick={() => setPage((p) => Math.max(0, p - 1))}
                >
                  Previous
                </Button>
                <span className="text-sm text-ink-muted">
                  Page {page + 1} of {pages}
                </span>
                <Button
                  variant="secondary"
                  disabled={page + 1 >= pages}
                  onClick={() => setPage((p) => p + 1)}
                >
                  Next
                </Button>
              </div>
            )}
          </>
        )}
      </div>

      {answering && (
        <Modal
          busy={busy}
          onClose={() => setAnswering(null)}
          title={`${ISSUE_LABEL[answering.category]} — ${answering.order_id}`}
          footer={
            <>
              <Button
                variant="secondary"
                onClick={() => setAnswering(null)}
                disabled={busy}
              >
                Close
              </Button>
              {answering.status === 'open' && (
                <Button
                  variant="primary"
                  onClick={() => void confirmResolve()}
                  loading={busy}
                >
                  Mark answered
                </Button>
              )}
            </>
          }
        >
          <dl className="grid grid-cols-2 gap-3 text-sm">
            <div>
              <dt className="text-ink-muted">Customer</dt>
              <dd className="text-ink">{answering.customer_phone}</dd>
            </div>
            <div>
              <dt className="text-ink-muted">
                {answering.kind === 'gift' ? 'Gift shop' : 'Restaurant'}
              </dt>
              <dd className="text-ink">{answering.seller_name}</dd>
            </div>
            <div>
              <dt className="text-ink-muted">Order</dt>
              <dd className="text-ink">
                {orderStatusLabel(answering)} · ₹{answering.order_total}
              </dd>
            </div>
            <div>
              <dt className="text-ink-muted">Reported</dt>
              <dd className="text-ink">{when(answering.created_at)}</dd>
            </div>
          </dl>

          {answering.body && (
            <p className="mt-4 rounded-lg border border-line bg-surface-2 p-3 text-sm text-ink">
              {answering.body}
            </p>
          )}

          {/* Food only. A gift is couriered by the Zopiqnow team with no kitchen
              and no rider, so 0094's three `orders` columns do not exist for it
              — and three empty frames would read as "the photographs are
              missing", which is a different and much worse thing to tell
              somebody triaging a complaint than "there are none". */}
          {answering.kind === 'food' && (
            <>
              <p className="mt-5 text-xs font-semibold uppercase tracking-wide text-ink-muted">
                The order&rsquo;s photographs
              </p>
              <div className="mt-2 grid grid-cols-3 gap-3">
                <Shot label="Cooked" url={photos?.cooked_photo_url ?? null} />
                <Shot label="Packed" url={photos?.packed_photo_url ?? null} />
                <Shot label="Handover" url={photos?.delivery_photo_url ?? null} />
              </div>
            </>
          )}

          {answering.status === 'open' ? (
            <Field
              className="mt-5"
              label="What to tell them"
              value={reply}
              onChange={(e) => setReply(e.target.value)}
              placeholder="We've refunded the missing biryani — it'll be back within 3 days."
              hint="The customer reads this on their own order screen. Write it to them, not about them. Answering does not move any money — issue a refund separately if one is owed."
            />
          ) : (
            answering.admin_note && (
              <div className="mt-5">
                <p className="text-xs font-semibold uppercase tracking-wide text-ink-muted">
                  Answered by {answering.resolved_by ?? 'somebody'}
                </p>
                <p className="mt-1 text-sm text-ink">{answering.admin_note}</p>
              </div>
            )
          )}
        </Modal>
      )}
    </>
  )
}

/// One photograph, or its honest absence. Small on purpose — this is a glance
/// while reading a complaint, and the full size is one click away.
function Shot({ label, url }: { label: string; url: string | null }) {
  return (
    <div>
      <p className="mb-1 text-xs text-ink-muted">{label}</p>
      {url ? (
        <a href={url} target="_blank" rel="noreferrer">
          <img
            src={url}
            alt={`${label} photo`}
            loading="lazy"
            className="aspect-square w-full rounded-lg border border-line object-cover"
          />
        </a>
      ) : (
        <div className="flex aspect-square w-full items-center justify-center rounded-lg border border-dashed border-line">
          <span className="text-xs text-ink-muted">None</span>
        </div>
      )}
    </div>
  )
}
