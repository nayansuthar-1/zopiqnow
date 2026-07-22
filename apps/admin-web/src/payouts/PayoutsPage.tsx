import { useCallback, useEffect, useState } from 'react'
import { api } from '../lib/api'
import type { RiderPayoutRow } from '../lib/api'
import { PageHeader } from '../ui/AppShell'
import { Button, Field } from '../ui/primitives'

/// What the platform owes its riders, and the record that it paid.
///
/// The rollup (`run_rider_payout_batch`, migration 0045) runs every Monday at
/// 01:00 and turns last week's delivered jobs into one row per rider. Nothing on
/// this page creates a payout; it can only mark one as settled.
///
/// **This page does not move money.** No bank integration exists — an admin makes
/// the transfer in their banking app and comes back here with the reference. That
/// is why the reference is mandatory: the row is the only record tying a rider's
/// week to a line on a bank statement, and one without a UTR cannot be reconciled
/// by anybody, ever.

function period(start: string, end: string) {
  const a = new Date(start)
  const b = new Date(end)
  const m = (d: Date) => d.toLocaleDateString('en-IN', { month: 'short' })
  const left = a.getMonth() === b.getMonth() ? `${a.getDate()}` : `${a.getDate()} ${m(a)}`
  return `${left}–${b.getDate()} ${m(b)}`
}

export function PayoutsPage() {
  const [rows, setRows] = useState<RiderPayoutRow[] | null>(null)
  const [filter, setFilter] = useState<'pending' | 'paid' | 'all'>('pending')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [paying, setPaying] = useState<RiderPayoutRow | null>(null)
  const [reference, setReference] = useState('')

  const load = useCallback(async () => {
    try {
      setRows(await api.listRiderPayouts(filter === 'all' ? undefined : filter))
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }, [filter])

  useEffect(() => {
    void load()
  }, [load])

  async function markPaid() {
    if (!paying) return
    setBusy(true)
    setError(null)
    try {
      await api.markRiderPayoutPaid(paying.id, reference)
      setPaying(null)
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
    .reduce((sum, r) => sum + r.amount, 0)

  return (
    <>
      <PageHeader
        title="Rider payouts"
        subtitle={
          rows
            ? `${rows.length} shown · ₹${owed} still owed`
            : 'Rolled up every Monday for the week before.'
        }
      />

      <div className="p-6">
        {error && (
          <p className="mb-4 max-w-2xl rounded-[8px] bg-non-veg-soft px-4 py-3 text-sm text-non-veg">
            {error}
          </p>
        )}

        <div className="mb-4 flex gap-1">
          {(['pending', 'paid', 'all'] as const).map((f) => (
            <button
              key={f}
              type="button"
              onClick={() => setFilter(f)}
              className={`rounded-[8px] px-3 py-1.5 text-sm font-medium capitalize transition-colors ${
                filter === f
                  ? 'bg-brand-soft text-brand-deep'
                  : 'text-ink-muted hover:bg-canvas hover:text-ink'
              }`}
            >
              {f}
            </button>
          ))}
        </div>

        {rows === null ? (
          <p className="text-sm text-ink-muted">Loading…</p>
        ) : rows.length === 0 ? (
          <p className="text-sm text-ink-muted">
            {filter === 'pending'
              ? 'Nothing owed. Either every payout is settled, or no deliveries have been completed since the last run.'
              : 'Nothing here yet.'}
          </p>
        ) : (
          <div className="overflow-x-auto rounded-[12px] border border-line bg-white">
            <table className="w-full min-w-[760px] text-sm">
              <thead className="border-b border-line text-left text-ink-muted">
                <tr>
                  <th className="px-5 py-3 font-medium">Rider</th>
                  <th className="px-5 py-3 font-medium">Week</th>
                  <th className="px-5 py-3 text-right font-medium">Deliveries</th>
                  <th className="px-5 py-3 text-right font-medium">Amount</th>
                  <th className="px-5 py-3 font-medium">Status</th>
                  <th className="px-5 py-3" />
                </tr>
              </thead>
              <tbody className="divide-y divide-line">
                {rows.map((r) => (
                  <tr key={r.id}>
                    <td className="px-5 py-3">
                      <p className="font-medium text-ink">{r.partner_name}</p>
                      <p className="truncate text-ink-muted">{r.partner_email}</p>
                    </td>
                    <td className="px-5 py-3 text-ink-muted">
                      {period(r.period_start, r.period_end)}
                    </td>
                    <td className="px-5 py-3 text-right tabular-nums text-ink-muted">
                      {r.delivery_count}
                    </td>
                    <td className="px-5 py-3 text-right font-semibold tabular-nums text-ink">
                      ₹{r.amount}
                    </td>
                    <td className="px-5 py-3">
                      {r.status === 'paid' ? (
                        <span className="text-veg">Paid · {r.reference}</span>
                      ) : r.has_bank ? (
                        <span className="text-ink-muted">Pending</span>
                      ) : (
                        // The one thing that stops a transfer, said before
                        // somebody clicks and finds out.
                        <span className="text-warn">No bank details</span>
                      )}
                    </td>
                    <td className="px-5 py-3">
                      <div className="flex justify-end">
                        {r.status === 'pending' && (
                          <Button
                            variant="secondary"
                            className="h-9 px-3"
                            disabled={!r.has_bank}
                            onClick={() => {
                              setPaying(r)
                              setReference('')
                            }}
                          >
                            Mark paid
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

      {paying && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-ink/40 p-4">
          <div className="w-full max-w-md rounded-[12px] bg-white p-6">
            <h2 className="text-base font-bold text-ink">
              Mark ₹{paying.amount} to {paying.partner_name} as paid
            </h2>
            <p className="mt-1 text-sm text-ink-muted">
              This records the payment — it does not send it. Make the transfer
              first, then put the bank&rsquo;s reference here.
            </p>
            <div className="mt-5">
              <Field
                label="Bank reference (UTR)"
                value={reference}
                onChange={(e) => setReference(e.target.value)}
                placeholder="N123456789012345"
                hint="Without this the payment cannot be traced later."
              />
            </div>
            <div className="mt-5 flex justify-end gap-2">
              <Button
                variant="ghost"
                onClick={() => setPaying(null)}
                disabled={busy}
              >
                Cancel
              </Button>
              <Button
                onClick={() => void markPaid()}
                disabled={busy || reference.trim() === ''}
              >
                Mark paid
              </Button>
            </div>
          </div>
        </div>
      )}
    </>
  )
}
