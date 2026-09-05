import { useCallback, useEffect, useState } from 'react'
import { api } from '../lib/api'
import type { RiderPayoutRow } from '../lib/api'
import { PageHeader } from '../ui/AppShell'
import {
  Banner,
  Button,
  DataTable,
  EmptyState,
  Field,
  Modal,
  PageBody,
  SegmentedControl,
  TableSkeleton,
  Td,
  Th,
} from '../ui/primitives'
import { inr } from '../lib/money'
import { useUrlState } from '../ui/urlState'

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
  // In the address bar, so a run somebody is halfway through survives a refresh
  // and can be handed to whoever takes over paying it.
  const [filter, setFilter] = useUrlState<'pending' | 'paid' | 'all'>(
    'filter',
    'pending',
    ['pending', 'paid', 'all'],
  )
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
            ? `${rows.length} shown · ${inr(owed)} still owed`
            : 'Rolled up every Monday for the week before.'
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

        <div className="mb-4">
          <SegmentedControl
            label="Filter payouts"
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
                ? 'Either every payout is settled, or no deliveries have been completed since the last Monday run.'
                : 'Payouts are rolled up every Monday at 01:00 for the week before. Nothing has been rolled up yet.'
            }
          />
        ) : (
          <DataTable label="Rider payouts" minWidth={760}>
            <thead>
              <tr>
                <Th>Rider</Th>
                <Th>Week</Th>
                <Th align="right">Deliveries</Th>
                <Th align="right">Amount</Th>
                <Th>Status</Th>
                <Th hideLabel>Actions</Th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id}>
                  <Td>
                    <p className="font-medium text-ink">{r.partner_name}</p>
                    <p className="truncate text-ink-muted">{r.partner_email}</p>
                  </Td>
                  <Td className="text-ink-muted">
                    {period(r.period_start, r.period_end)}
                  </Td>
                  <Td align="right" className="text-ink-muted">
                    {r.delivery_count}
                  </Td>
                  <Td align="right" className="font-semibold text-ink">
                    {inr(r.amount)}
                    {/* A transfer smaller than the week's earnings has to say
                        why on the row, or the figure looks like an error
                        (migration 0076). */}
                    {r.cash_withheld > 0 && (
                      <p className="text-xs font-normal text-ink-muted">
                        {inr(r.gross_amount)} less {inr(r.cash_withheld)} cash
                      </p>
                    )}
                  </Td>
                  <Td>
                    {r.status === 'paid' ? (
                      <span className="text-veg">Paid · {r.reference}</span>
                    ) : r.has_bank ? (
                      <span className="text-ink-muted">Pending</span>
                    ) : (
                      // The one thing that stops a transfer, said before
                      // somebody clicks and finds out.
                      <span className="text-warn">No bank details</span>
                    )}
                  </Td>
                  <Td>
                    <div className="flex justify-end">
                      {r.status === 'pending' && (
                        <Button
                          variant="secondary"
                          size="sm"
                          disabled={!r.has_bank}
                          title={
                            r.has_bank
                              ? undefined
                              : 'No account on file for this rider. Add it from the Riders screen first.'
                          }
                          onClick={() => {
                            setPaying(r)
                            setReference('')
                          }}
                        >
                          Mark paid
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

      {paying && (
        <Modal
          busy={busy}
          onClose={() => setPaying(null)}
          title={`Mark ${inr(paying.amount)} to ${paying.partner_name} as paid`}
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
          <Field
            className="mt-5"
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
