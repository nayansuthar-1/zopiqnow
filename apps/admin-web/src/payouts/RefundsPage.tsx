import { useCallback, useEffect, useState } from 'react'
import { api } from '../lib/api'
import type { RefundRow } from '../lib/api'
import { PageHeader } from '../ui/AppShell'
import {
  Banner,
  Button,
  DataTable,
  EmptyState,
  Field,
  Modal,
  PageBody,
  Pill,
  SegmentedControl,
  TableSkeleton,
  Td,
  TextArea,
  Th,
} from '../ui/primitives'
import { inr } from '../lib/money'

/// Money going back out (migration 0077).
///
/// Two kinds of row land here and they behave differently on purpose. A refund
/// raised by `system` is the full value of an order that ended without being
/// delivered — a customer cancelling, a kitchen declining, or the five-minute
/// accept timeout giving up on one. Those arrive already approved and cannot be
/// declined: the platform owes that money whether or not anybody at this desk
/// agrees, and a queue that has to be worked before a customer is refunded is
/// the queue nobody works. All this screen does with them is record that the
/// transfer went out.
///
/// A refund an admin raises is the other kind — the partial for a missing dish,
/// or the only way to refund a cash order that really was delivered. That one
/// waits for an approval, and both the issuing and the approving carry a name.
///
/// **This page moves money.** It said the opposite until 0158 — "no gateway is
/// wired in yet (PAY-001)" — and that had been untrue since 0138 put Razorpay
/// behind the queue. Of the four refunds on this platform against a real
/// capture, three paid themselves without anybody touching them.
///
/// So: a refund whose `payment_id` is a real Razorpay capture is sent
/// automatically, within five minutes of being approved, and **Send to Razorpay**
/// is the same trip taken now instead of on the next tick. What comes back is
/// Razorpay's own sentence, kept whole — "this payment was never captured" and
/// "the payment has been fully refunded already" need completely different
/// answers, and paraphrasing them into "failed" would throw away the only useful
/// thing in the reply.
///
/// The other kind still settles by hand. A cash order never had a gateway
/// payment, and neither did the nineteen `pay_mock_…` rows that predate payments
/// — no money was taken, so none goes back through Razorpay. Those wait for
/// **Mark sent**, which is a person recording a decision rather than a transfer
/// this page made.

function stamp(iso: string) {
  return new Date(iso).toLocaleDateString('en-IN', {
    day: 'numeric',
    month: 'short',
  })
}

const statusTone: Record<RefundRow['status'], 'live' | 'warn' | 'danger' | 'neutral'> = {
  requested: 'warn',
  approved: 'warn',
  processing: 'neutral',
  paid: 'live',
  failed: 'danger',
  declined: 'neutral',
}

const statusLabel: Record<RefundRow['status'], string> = {
  requested: 'Needs approval',
  approved: 'To send',
  processing: 'With gateway',
  paid: 'Paid',
  failed: 'Failed',
  declined: 'Declined',
}

/// How long to wait before asking Razorpay what it said.
///
/// pg_net dispatches the request only once the transaction that queued it has
/// committed, so the answer cannot exist when `pushRefund` returns. Two seconds
/// is comfortably longer than Razorpay takes to answer and short enough that the
/// admin who pressed the button is still looking at it.
const COLLECT_AFTER_MS = 2_000

type Filter = 'open' | 'paid' | 'all'

/// Open is four of the six statuses, and it is the question the header asks as
/// well as the one the tabs ask — so it is one predicate rather than the same
/// clause written out in both places.
const isOpen = (r: RefundRow) => r.status !== 'paid' && r.status !== 'declined'

export function RefundsPage() {
  const [all, setAll] = useState<RefundRow[] | null>(null)
  const [filter, setFilter] = useState<Filter>('open')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const [paying, setPaying] = useState<RefundRow | null>(null)
  const [reference, setReference] = useState('')

  const [approving, setApproving] = useState<RefundRow | null>(null)
  const [funder, setFunder] = useState<RefundRow['funded_by']>('platform')

  const [declining, setDeclining] = useState<RefundRow | null>(null)
  const [declineReason, setDeclineReason] = useState('')

  // Which row's gateway trip is in flight, and what Razorpay said about it.
  // `said` is not an error and is not dismissed on a timer: "Razorpay refused
  // it: this payment was never captured" is the whole reason the button was
  // pressed, and it stays on screen until the next press.
  const [pushing, setPushing] = useState<number | null>(null)
  const [said, setSaid] = useState<string | null>(null)
  const [issuing, setIssuing] = useState(false)
  const [orderId, setOrderId] = useState('')
  const [amount, setAmount] = useState('')
  const [reason, setReason] = useState('')
  const [issueFunder, setIssueFunder] = useState<RefundRow['funded_by']>('platform')

  const load = useCallback(async () => {
    try {
      // One call and filtered below, unlike Payouts: "open" is four of the six
      // statuses and the RPC takes exactly one. The whole list is what is held,
      // so that what is owed does not change when the tab does.
      setAll(await api.listRefunds())
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  /// Send this refund to Razorpay, then come back for the answer.
  ///
  /// Two calls, because pg_net cannot deliver a request and its reply inside one
  /// transaction. The first fires and says so; the second reads what Razorpay
  /// returned and settles the row. If the answer has not landed yet the RPC says
  /// that too — nothing here retries on its own, because a second call to
  /// Razorpay for money that may already have moved is the one mistake this
  /// whole path exists to avoid.
  async function push(r: RefundRow) {
    setPushing(r.id)
    setError(null)
    setSaid(null)
    try {
      const first = await api.pushRefund(r.id)
      setSaid(first)
      await load()

      // Only when we have just fired one. A "Check again" has already returned
      // the settled answer, or has told us it is still in flight, and asking
      // twice in four seconds would say the same thing twice.
      if (first.startsWith('Sent to Razorpay')) {
        await new Promise((done) => setTimeout(done, COLLECT_AFTER_MS))
        setSaid(await api.pushRefund(r.id))
        await load()
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setPushing(null)
    }
  }

  async function run(action: () => Promise<unknown>, close: () => void) {
    setBusy(true)
    setError(null)
    try {
      await action()
      close()
      await load()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  const rows =
    all === null
      ? null
      : filter === 'all'
        ? all
        : filter === 'paid'
          ? all.filter((r) => !isOpen(r))
          : all.filter(isOpen)

  // From the unfiltered list. The header answers "how much is still to go out",
  // and that is the same figure whichever tab is showing. Summing the visible
  // rows had Closed stating that nothing was owed while Open, one click away,
  // was full of money.
  const owed = (all ?? []).filter(isOpen).reduce((sum, r) => sum + r.amount, 0)

  return (
    <>
      <PageHeader
        title="Refunds"
        subtitle={
          rows
            ? `${rows.length} shown · ${inr(owed)} still to send`
            : 'Raised automatically when an order ends without being delivered.'
        }
        action={
          <Button onClick={() => {
            setIssuing(true)
            setOrderId('')
            setAmount('')
            setReason('')
            setIssueFunder('platform')
          }}>
            Refund an order
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

        {/* Razorpay's own words, kept whole. A refusal is not an error on this
            screen — the trip was made and this is what came back — so it is a
            notice rather than a red banner, and it stays until the next push. */}
        {said && (
          <Banner
            tone={
              said.startsWith('Razorpay refused')
                ? 'warn'
                : said.startsWith('Razorpay paid')
                  ? 'success'
                  : 'info'
            }
            className="mb-4 max-w-2xl"
            onDismiss={() => setSaid(null)}
          >
            {said}
          </Banner>
        )}

        <div className="mb-4">
          <SegmentedControl
            label="Filter refunds"
            value={filter}
            onChange={setFilter}
            options={[
              { value: 'open', label: 'Open' },
              { value: 'paid', label: 'Closed' },
              { value: 'all', label: 'All' },
            ]}
          />
        </div>

        {rows === null ? (
          <TableSkeleton />
        ) : rows.length === 0 ? (
          <EmptyState
            title={filter === 'open' ? 'Nothing owed' : 'Nothing here yet'}
            body={
              filter === 'open'
                ? 'Every refund has been sent. New ones appear here the moment an order is cancelled, declined, or times out unaccepted.'
                : 'A refund is raised automatically when a prepaid order ends without being delivered, or by hand from this screen.'
            }
          />
        ) : (
          <DataTable label="Refunds" minWidth={900}>
            <thead>
              <tr>
                <Th>Order</Th>
                <Th>Why</Th>
                <Th align="right">Amount</Th>
                <Th>Funded by</Th>
                <Th>Status</Th>
                <Th hideLabel>Actions</Th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id}>
                  <Td>
                    <p className="font-medium text-ink">{r.order_id}</p>
                    <p className="truncate text-ink-muted">
                      {r.restaurant_name} · {r.user_phone}
                    </p>
                  </Td>
                  <Td className="max-w-[260px] text-ink-muted">
                    <p className="truncate" title={r.reason}>
                      {r.reason}
                    </p>
                    <p className="text-xs">
                      {r.requested_by === 'system'
                        ? 'Automatic'
                        : `By ${r.requested_by}`}{' '}
                      · {stamp(r.created_at)}
                    </p>
                  </Td>
                  <Td align="right" className="font-semibold text-ink">
                    {inr(r.amount)}
                    {/* A partial has to say what it is a part of, or the
                        figure looks like a mis-keyed full refund. */}
                    {r.amount < r.order_total && (
                      <p className="text-xs font-normal text-ink-muted">
                        of {inr(r.order_total)}
                      </p>
                    )}
                  </Td>
                  <Td className="text-ink-muted">
                    {r.funded_by === 'restaurant' ? 'Restaurant' : 'Platform'}
                    {r.settlement_id !== null && (
                      <p className="text-xs">
                        On settlement #{r.settlement_id}
                      </p>
                    )}
                  </Td>
                  <Td>
                    <Pill tone={statusTone[r.status]}>
                      {statusLabel[r.status]}
                    </Pill>
                    {r.status === 'paid' && r.gateway_refund_id && (
                      <p className="mt-1 text-xs text-ink-muted">
                        {r.gateway_refund_id}
                      </p>
                    )}
                    {(r.status === 'failed' || r.status === 'declined') &&
                      r.failure_reason && (
                        <p className="mt-1 text-xs text-ink-muted">
                          {r.failure_reason}
                        </p>
                      )}
                    {/* Otherwise these read as stuck. Nineteen rows on this
                        platform are waiting for a person and look exactly like
                        the ones the gateway is about to take. */}
                    {!r.gateway_backed &&
                      (r.status === 'approved' || r.status === 'requested') && (
                        <p className="mt-1 text-xs text-ink-muted">
                          No gateway payment — settle by hand
                        </p>
                      )}
                    {(r.status === 'requested' ||
                      r.status === 'approved') && (
                      <p className="mt-1 text-xs text-ink-muted">
                        Promised by {stamp(r.expected_by)}
                      </p>
                    )}
                  </Td>
                  <Td>
                    <div className="flex justify-end gap-2">
                      {(r.status === 'requested' || r.status === 'failed') && (
                        <Button
                          variant="secondary"
                          size="sm"
                          onClick={() => {
                            setApproving(r)
                            setFunder(r.funded_by)
                          }}
                        >
                          Approve
                        </Button>
                      )}
                      {/* Absent, not disabled, on an automatic refund: the
                          database refuses it and a button that always errors
                          is a button that teaches people to ignore errors. */}
                      {(r.status === 'requested' || r.status === 'failed') &&
                        r.requested_by !== 'system' && (
                          <Button
                            variant="secondary"
                            size="sm"
                            onClick={() => {
                              setDeclining(r)
                              setDeclineReason('')
                            }}
                          >
                            Decline
                          </Button>
                        )}
                      {/* The gateway trip, on the rows that have one to make.
                          `failed` is included on purpose: Razorpay refuses for
                          reasons that get fixed, and the alternative is an admin
                          re-approving a row just to make a button appear — which
                          is exactly what happened to refund 98 on this
                          database. */}
                      {r.gateway_backed &&
                        (r.status === 'approved' ||
                          r.status === 'processing' ||
                          r.status === 'failed') && (
                          <Button
                            variant="secondary"
                            size="sm"
                            loading={pushing === r.id}
                            disabled={pushing !== null}
                            onClick={() => void push(r)}
                          >
                            {r.status === 'processing'
                              ? 'Check again'
                              : 'Send to Razorpay'}
                          </Button>
                        )}
                      {(r.status === 'approved' ||
                        r.status === 'processing') && (
                        <Button
                          variant="secondary"
                          size="sm"
                          onClick={() => {
                            setPaying(r)
                            setReference('')
                          }}
                        >
                          Mark sent
                        </Button>
                      )}
                    </div>
                  </Td>
                </tr>
              ))}
            </tbody>
          </DataTable>
        )}
      </PageBody>

      {issuing && (
        <Modal
          busy={busy}
          onClose={() => setIssuing(false)}
          title="Refund an order"
          footer={
            <>
              <Button
                variant="secondary"
                onClick={() => setIssuing(false)}
                disabled={busy}
              >
                Cancel
              </Button>
              <Button
                loading={busy}
                disabled={
                  orderId.trim() === '' ||
                  reason.trim() === '' ||
                  !(Number(amount) > 0)
                }
                onClick={() =>
                  void run(
                    () =>
                      api.issueRefund(
                        orderId.trim(),
                        Number(amount),
                        reason.trim(),
                        issueFunder,
                      ),
                    () => setIssuing(false),
                  )
                }
              >
                Raise refund
              </Button>
            </>
          }
        >
          <p className="text-sm text-ink-muted">
            Raises the refund for approval. The database refuses an amount that
            would take this order past what the customer paid, counting
            everything already refunded on it.
          </p>
          <Field
            className="mt-5"
            label="Order"
            placeholder="ZPQ-1042"
            value={orderId}
            onChange={(e) => setOrderId(e.target.value)}
          />
          <Field
            className="mt-4"
            label="Amount (₹)"
            type="number"
            min={1}
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
          />
          <TextArea
            className="mt-4"
            label="Reason"
            hint="Shown to the customer word for word on their order."
            rows={2}
            value={reason}
            onChange={(e) => setReason(e.target.value)}
          />
          <div className="mt-4">
            <SegmentedControl
              label="Funded by"
              value={issueFunder}
              onChange={setIssueFunder}
              options={[
                { value: 'platform', label: 'Platform' },
                { value: 'restaurant', label: 'Restaurant' },
              ]}
            />
            <p className="mt-1.5 text-sm text-ink-muted">
              A restaurant-funded refund comes off that restaurant&rsquo;s next
              settlement.
            </p>
          </div>
        </Modal>
      )}

      {approving && (
        <Modal
          busy={busy}
          onClose={() => setApproving(null)}
          title={`Approve ${inr(approving.amount)} on ${approving.order_id}`}
          footer={
            <>
              <Button
                variant="secondary"
                onClick={() => setApproving(null)}
                disabled={busy}
              >
                Cancel
              </Button>
              <Button
                loading={busy}
                onClick={() =>
                  void run(
                    () => api.approveRefund(approving.id, funder),
                    () => setApproving(null),
                  )
                }
              >
                Approve
              </Button>
            </>
          }
        >
          <p className="text-sm text-ink-muted">
            Clears it to be sent. This is also the last chance to change who pays
            for it — once a settlement has absorbed the row, the figure has
            already been shown to the restaurant and the database refuses.
          </p>
          <div className="mt-5">
            <SegmentedControl
              label="Funded by"
              value={funder}
              onChange={setFunder}
              options={[
                { value: 'platform', label: 'Platform' },
                { value: 'restaurant', label: 'Restaurant' },
              ]}
            />
          </div>
        </Modal>
      )}

      {declining && (
        <Modal
          busy={busy}
          onClose={() => setDeclining(null)}
          title={`Decline ${inr(declining.amount)} on ${declining.order_id}`}
          footer={
            <>
              <Button
                variant="secondary"
                onClick={() => setDeclining(null)}
                disabled={busy}
              >
                Cancel
              </Button>
              <Button
                loading={busy}
                disabled={declineReason.trim() === ''}
                onClick={() =>
                  void run(
                    () => api.declineRefund(declining.id, declineReason.trim()),
                    () => setDeclining(null),
                  )
                }
              >
                Decline
              </Button>
            </>
          }
        >
          <p className="text-sm text-ink-muted">
            The customer is not shown a declined refund — as far as they are
            concerned it was never raised. The note is for whoever reads this row
            later.
          </p>
          <TextArea
            className="mt-5"
            label="Why"
            rows={2}
            value={declineReason}
            onChange={(e) => setDeclineReason(e.target.value)}
          />
        </Modal>
      )}

      {paying && (
        <Modal
          busy={busy}
          onClose={() => setPaying(null)}
          title={`Mark ${inr(paying.amount)} on ${paying.order_id} as sent`}
          footer={
            <>
              <Button
                variant="secondary"
                onClick={() => setPaying(null)}
                disabled={busy}
              >
                Cancel
              </Button>
              <Button
                loading={busy}
                disabled={reference.trim() === ''}
                onClick={() =>
                  void run(
                    () => api.markRefundPaid(paying.id, reference.trim()),
                    () => setPaying(null),
                  )
                }
              >
                Mark sent
              </Button>
            </>
          }
        >
          <p className="text-sm text-ink-muted">
            This records the refund — it does not send it. Make the transfer
            first, then put the reference here. The customer is told the money is
            on its way as soon as you do.
          </p>
          <Field
            className="mt-5"
            label="Reference (UTR or gateway refund id)"
            value={reference}
            onChange={(e) => setReference(e.target.value)}
          />
        </Modal>
      )}
    </>
  )
}
