import { useCallback, useEffect, useState } from 'react'
import { api } from '../lib/api'
import type {
  RestaurantBank,
  SettlementAdjustmentRow,
  SettlementRow,
} from '../lib/api'
import { PageHeader } from '../ui/AppShell'
import {
  Banner,
  Button,
  EmptyState,
  Field,
  Modal,
  SegmentedControl,
  TableSkeleton,
} from '../ui/primitives'

/// What the platform owes its restaurants, and the record that it paid.
///
/// `run_settlement_batch` (migration 0017) runs every Monday at 00:30 and turns
/// last week's delivered orders into one row per restaurant, claiming the orders
/// it summed so the same sale can never be settled twice. Nothing on this page
/// creates a settlement; it can only mark one as paid — or move it.
///
/// **This page does not move money** — the same as rider payouts, and for the
/// same reason. An admin makes the transfer in their banking app and comes back
/// with the reference, which is why the reference is mandatory: the row is the
/// only thing tying a restaurant's week to a line on a bank statement.
///
/// **A statement is on hold for three days after its week closes** (0079). Mark
/// paid refuses inside that window, and the whole point of the window is that
/// the figure can still change in it: a restaurant-funded refund approved during
/// the hold is charged to *this* statement rather than to the next one, and an
/// adjustment can be written against it. Once it is paid it is history.

function period(start: string, end: string) {
  const a = new Date(start)
  const b = new Date(end)
  const m = (d: Date) => d.toLocaleDateString('en-IN', { month: 'short' })
  const left = a.getMonth() === b.getMonth() ? `${a.getDate()}` : `${a.getDate()} ${m(a)}`
  return `${left}–${b.getDate()} ${m(b)}`
}

function day(iso: string) {
  return new Date(iso).toLocaleDateString('en-IN', {
    day: 'numeric',
    month: 'short',
  })
}

/// Signed, and rendered as such: an adjustment is the one figure on this page
/// that reads in both directions, so the sign carries the meaning.
function signed(n: number) {
  return `${n < 0 ? '−' : '+'}₹${Math.abs(n).toLocaleString('en-IN')}`
}

export function SettlementsPage() {
  const [rows, setRows] = useState<SettlementRow[] | null>(null)
  const [filter, setFilter] = useState<'pending' | 'paid' | 'all'>('pending')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [paying, setPaying] = useState<SettlementRow | null>(null)
  const [bank, setBank] = useState<RestaurantBank | null>(null)
  const [reference, setReference] = useState('')
  const [adjusting, setAdjusting] = useState<SettlementRow | null>(null)
  const [history, setHistory] = useState<SettlementAdjustmentRow[] | null>(null)
  const [amount, setAmount] = useState('')
  const [reason, setReason] = useState('')

  const load = useCallback(async () => {
    try {
      setRows(await api.listSettlements(filter === 'all' ? undefined : filter))
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }, [filter])

  useEffect(() => {
    void load()
  }, [load])

  // Fetched when the dialog opens and dropped when it closes. The account
  // number is only needed by whoever is actually making the transfer, and a
  // list read at a glance and over shoulders is not the place for it — which is
  // why `admin_get_restaurant` returns the last four and this returns the rest.
  async function beginPayment(s: SettlementRow) {
    setPaying(s)
    setReference('')
    setBank(null)
    try {
      const b = await api.getRestaurantBank(s.restaurant_id)
      setBank(b[0] ?? null)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }

  /// The history comes with the dialog, not with the table. Most statements
  /// have no adjustments and never will; fetching a row's worth of nothing for
  /// every line on the page to render a column that is almost always a dash is
  /// the wrong trade.
  async function beginAdjustment(s: SettlementRow) {
    setAdjusting(s)
    setAmount('')
    setReason('')
    setHistory(null)
    try {
      setHistory(await api.listSettlementAdjustments(s.id))
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }

  async function saveAdjustment() {
    if (!adjusting) return
    setBusy(true)
    setError(null)
    try {
      await api.adjustSettlement(adjusting.id, Number(amount), reason)
      setAdjusting(null)
      await load()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  async function markPaid() {
    if (!paying) return
    setBusy(true)
    setError(null)
    try {
      await api.markSettlementPaid(paying.id, reference)
      setPaying(null)
      setBank(null)
      setReference('')
      await load()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  const owed = (rows ?? [])
    .filter((r) => r.status === 'pending')
    .reduce((sum, r) => sum + r.net_payable, 0)

  return (
    <>
      <PageHeader
        title="Restaurant settlements"
        subtitle={
          rows
            ? `${rows.length} shown · ₹${owed.toLocaleString('en-IN')} still owed`
            : 'Rolled up every Monday for the week before.'
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
            label="Filter settlements"
            value={filter}
            onChange={setFilter}
            options={[
              { value: 'pending', label: 'Pending' },
              { value: 'paid', label: 'Paid' },
              { value: 'all', label: 'All' },
            ]}
          />
        </div>

        {rows === null ? (
          <TableSkeleton />
        ) : rows.length === 0 ? (
          <EmptyState
            title={filter === 'pending' ? 'Nothing owed' : 'Nothing here yet'}
            body={
              filter === 'pending'
                ? 'Either every settlement is paid, or no orders have been delivered since the last Monday run.'
                : 'Settlements are rolled up every Monday at 00:30 for the week before. Nothing has been rolled up yet.'
            }
          />
        ) : (
          <div className="overflow-x-auto rounded-card border border-line bg-white">
            <table className="w-full min-w-[980px] text-sm">
              <thead className="border-b border-line text-left text-ink-muted">
                <tr>
                  <th className="px-5 py-3 font-medium">Restaurant</th>
                  <th className="px-5 py-3 font-medium">Week</th>
                  <th className="px-5 py-3 text-right font-medium">Orders</th>
                  <th className="px-5 py-3 text-right font-medium">Sales</th>
                  <th className="px-5 py-3 text-right font-medium">Own offers</th>
                  <th className="px-5 py-3 text-right font-medium">Commission</th>
                  <th className="px-5 py-3 text-right font-medium">Refunds</th>
                  <th className="px-5 py-3 text-right font-medium">Adjustments</th>
                  <th className="px-5 py-3 text-right font-medium">Payable</th>
                  <th className="px-5 py-3 font-medium">Status</th>
                  <th className="px-5 py-3" />
                </tr>
              </thead>
              <tbody className="divide-y divide-line">
                {rows.map((s) => (
                  <tr key={s.id}>
                    <td className="px-5 py-3 font-medium text-ink">
                      {s.restaurant_name}
                    </td>
                    <td className="px-5 py-3 text-ink-muted">
                      {period(s.period_start, s.period_end)}
                    </td>
                    <td className="px-5 py-3 text-right tabular-nums text-ink-muted">
                      {s.order_count}
                    </td>
                    <td className="px-5 py-3 text-right tabular-nums text-ink-muted">
                      ₹{s.gross_sales.toLocaleString('en-IN')}
                    </td>
                    {/* A dash, not a zero. Most weeks have no restaurant-funded
                        offers, and a column of ₹0 is noise the eye has to skip
                        past to find the week that does. */}
                    <td className="px-5 py-3 text-right tabular-nums text-ink-muted">
                      {s.vendor_funded_discount > 0
                        ? `−₹${s.vendor_funded_discount.toLocaleString('en-IN')}`
                        : '—'}
                    </td>
                    <td className="px-5 py-3 text-right tabular-nums text-ink-muted">
                      −₹{s.commission.toLocaleString('en-IN')}
                    </td>
                    {/* Same dash rule, and the same reason (0077). Unlike the
                        other columns this one is not week-scoped: a refund
                        raised this week for a month-old order is charged here,
                        because the week it belongs to has already been paid. */}
                    <td className="px-5 py-3 text-right tabular-nums text-ink-muted">
                      {s.refunds > 0
                        ? `−₹${s.refunds.toLocaleString('en-IN')}`
                        : '—'}
                    </td>
                    {/* Signed, and the same dash rule as the two columns above
                        it. Most statements are never adjusted, and the ones
                        that are should stand out of the page rather than sit in
                        a column of zeroes. */}
                    <td className="px-5 py-3 text-right tabular-nums text-ink-muted">
                      {s.adjustments !== 0 ? signed(s.adjustments) : '—'}
                    </td>
                    <td className="px-5 py-3 text-right font-semibold tabular-nums text-ink">
                      ₹{s.net_payable.toLocaleString('en-IN')}
                    </td>
                    <td className="px-5 py-3">
                      {s.status === 'paid' ? (
                        <span className="text-veg">Paid · {s.reference}</span>
                      ) : s.on_hold ? (
                        // The hold is news, not an error: the figure can still
                        // move, and the date says how long it can move for.
                        <span className="text-ink-muted">
                          On hold until {day(s.hold_until)}
                        </span>
                      ) : s.has_bank ? (
                        <span className="text-ink-muted">Pending</span>
                      ) : (
                        // The one thing that stops a transfer, said before
                        // somebody clicks and finds out.
                        <span className="text-warn">No bank details</span>
                      )}
                    </td>
                    <td className="px-5 py-3">
                      <div className="flex justify-end gap-2">
                        {s.status === 'pending' && (
                          <>
                            <Button
                              variant="secondary"
                              size="sm"
                              onClick={() => void beginAdjustment(s)}
                            >
                              Adjust
                            </Button>
                            <Button
                              variant="secondary"
                              size="sm"
                              disabled={!s.has_bank || s.on_hold}
                              title={
                                s.on_hold
                                  ? `On hold until ${day(s.hold_until)} — a refund or an adjustment raised before then still lands on this statement.`
                                  : s.has_bank
                                    ? undefined
                                    : 'No account on file for this restaurant. Add it from the restaurant’s Bank step first.'
                              }
                              onClick={() => void beginPayment(s)}
                            >
                              Mark paid
                            </Button>
                          </>
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

      {adjusting && (
        <Modal
          busy={busy}
          onClose={() => setAdjusting(null)}
          title={`Adjust ${adjusting.restaurant_name}, ${period(adjusting.period_start, adjusting.period_end)}`}
          footer={
            <>
              <Button
                variant="secondary"
                onClick={() => setAdjusting(null)}
                disabled={busy}
              >
                Cancel
              </Button>
              <Button
                onClick={() => void saveAdjustment()}
                loading={busy}
                disabled={
                  reason.trim() === '' ||
                  amount.trim() === '' ||
                  Number.isNaN(Number(amount)) ||
                  Number(amount) === 0
                }
              >
                Save adjustment
              </Button>
            </>
          }
        >
          <p className="text-sm text-ink-muted">
            This moves what the restaurant is owed and records who moved it. The
            reason is shown to them on their statement, so write it for them
            rather than for us.
          </p>

          <div className="mt-4 rounded-field bg-canvas px-4 py-3 text-sm">
            <p className="text-ink-muted">
              Currently payable{' '}
              <span className="font-medium tabular-nums text-ink">
                ₹{adjusting.net_payable.toLocaleString('en-IN')}
              </span>
              {amount.trim() !== '' && !Number.isNaN(Number(amount)) && (
                <>
                  {' → '}
                  <span className="font-medium tabular-nums text-ink">
                    ₹
                    {(adjusting.net_payable + Number(amount)).toLocaleString(
                      'en-IN',
                    )}
                  </span>
                </>
              )}
            </p>
          </div>

          <Field
            className="mt-4"
            label="Amount"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            placeholder="-400"
            hint="Negative charges the restaurant, positive credits it. Whole rupees."
          />
          <Field
            className="mt-4"
            label="Reason"
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            placeholder="Agreed goodwill on ZPQ-1042"
          />

          {history !== null && history.length > 0 && (
            <div className="mt-5">
              <p className="mb-2 text-xs font-medium uppercase tracking-wide text-ink-muted">
                Already adjusted
              </p>
              <ul className="divide-y divide-line rounded-field border border-line">
                {history.map((a) => (
                  <li key={a.id} className="px-4 py-2 text-sm">
                    <div className="flex justify-between gap-3">
                      <span className="text-ink">{a.reason}</span>
                      <span className="shrink-0 tabular-nums text-ink">
                        {signed(a.amount)}
                      </span>
                    </div>
                    <p className="text-xs text-ink-muted">
                      {a.created_by} · {day(a.created_at)}
                    </p>
                  </li>
                ))}
              </ul>
            </div>
          )}
        </Modal>
      )}

      {paying && (
        <Modal
          busy={busy}
          onClose={() => {
            setPaying(null)
            setBank(null)
          }}
          title={`Mark ₹${paying.net_payable.toLocaleString('en-IN')} to ${paying.restaurant_name} as paid`}
          footer={
            <>
              <Button
                variant="secondary"
                onClick={() => {
                  setPaying(null)
                  setBank(null)
                }}
                disabled={busy}
              >
                Cancel
              </Button>
              <Button
                onClick={() => void markPaid()}
                loading={busy}
                disabled={reference.trim() === ''}
              >
                Mark paid
              </Button>
            </>
          }
        >
          <p className="text-sm text-ink-muted">
            This records the payment — it does not send it. Make the transfer
            first, then put the bank&rsquo;s reference here.
          </p>

          <div className="mt-4 rounded-field bg-canvas px-4 py-3 text-sm">
            {bank === null ? (
              <p className="text-ink-muted">Fetching account details…</p>
            ) : (
              <>
                <p className="font-medium text-ink">
                  {bank.account_holder ?? 'No account holder on file'}
                </p>
                <p className="text-ink-muted tabular-nums">
                  {bank.account_number} · {bank.ifsc}
                </p>
                <p className="text-ink-muted">
                  {bank.bank_name}
                  {!bank.verified && ' · not verified'}
                </p>
              </>
            )}
          </div>

          <Field
            className="mt-4"
            label="Bank reference (UTR)"
            value={reference}
            onChange={(e) => setReference(e.target.value)}
            placeholder="N123456789012345"
            hint="Without this the payment cannot be traced later."
          />
        </Modal>
      )}
    </>
  )
}
