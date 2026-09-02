import { useCallback, useEffect, useState } from 'react'
import { api } from '../lib/api'
import type { RefundRow } from '../lib/api'
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
  TextArea,
} from '../ui/primitives'

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
/// **This page does not move money.** No gateway is wired in yet (PAY-001), so a
/// refund is settled the way a rider payout is: somebody makes the transfer and
/// comes back with the reference. When the gateway lands it writes the same
/// three columns from a webhook and the row will not know the difference.

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
            ? `${rows.length} shown · ₹${owed} still to send`
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

      <div className="p-6">
        {error && (
          <Banner
            tone="error"
            className="mb-4 max-w-2xl"
            onDismiss={() => setError(null)}
          >
            {error}
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
          <div className="overflow-x-auto rounded-card border border-line bg-white">
            <table className="w-full min-w-[900px] text-sm">
              <thead className="border-b border-line text-left text-ink-muted">
                <tr>
                  <th className="px-5 py-3 font-medium">Order</th>
                  <th className="px-5 py-3 font-medium">Why</th>
                  <th className="px-5 py-3 text-right font-medium">Amount</th>
                  <th className="px-5 py-3 font-medium">Funded by</th>
                  <th className="px-5 py-3 font-medium">Status</th>
                  <th className="px-5 py-3" />
                </tr>
              </thead>
              <tbody className="divide-y divide-line">
                {rows.map((r) => (
                  <tr key={r.id}>
                    <td className="px-5 py-3">
                      <p className="font-medium text-ink">{r.order_id}</p>
                      <p className="truncate text-ink-muted">
                        {r.restaurant_name} · {r.user_phone}
                      </p>
                    </td>
                    <td className="max-w-[260px] px-5 py-3 text-ink-muted">
                      <p className="truncate" title={r.reason}>
                        {r.reason}
                      </p>
                      <p className="text-xs">
                        {r.requested_by === 'system'
                          ? 'Automatic'
                          : `By ${r.requested_by}`}{' '}
                        · {stamp(r.created_at)}
                      </p>
                    </td>
                    <td className="px-5 py-3 text-right font-semibold tabular-nums text-ink">
                      ₹{r.amount}
                      {/* A partial has to say what it is a part of, or the
                          figure looks like a mis-keyed full refund. */}
                      {r.amount < r.order_total && (
                        <p className="text-xs font-normal text-ink-muted">
                          of ₹{r.order_total}
                        </p>
                      )}
                    </td>
                    <td className="px-5 py-3 text-ink-muted">
                      {r.funded_by === 'restaurant' ? 'Restaurant' : 'Platform'}
                      {r.settlement_id !== null && (
                        <p className="text-xs">
                          On settlement #{r.settlement_id}
                        </p>
                      )}
                    </td>
                    <td className="px-5 py-3">
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
                      {(r.status === 'requested' ||
                        r.status === 'approved') && (
                        <p className="mt-1 text-xs text-ink-muted">
                          Promised by {stamp(r.expected_by)}
                        </p>
                      )}
                    </td>
                    <td className="px-5 py-3">
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
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

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
          title={`Approve ₹${approving.amount} on ${approving.order_id}`}
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
          title={`Decline ₹${declining.amount} on ${declining.order_id}`}
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
          title={`Mark ₹${paying.amount} on ${paying.order_id} as sent`}
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
