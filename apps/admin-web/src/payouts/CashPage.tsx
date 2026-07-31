import { useCallback, useEffect, useState } from 'react'
import { api } from '../lib/api'
import type { RiderCashEntry, RiderCashRow } from '../lib/api'
import { PageHeader } from '../ui/AppShell'
import {
  Banner,
  Button,
  Field,
  Modal,
  TableSkeleton,
  TextArea,
} from '../ui/primitives'

/// Where the platform's cash actually is (migration 0076).
///
/// COD is a live payment method and until 0076 nothing recorded that a rider had
/// been handed the money. This screen is the other half of that fix: the balance
/// every rider is carrying, the action that clears it, and the ledger the number
/// came from.
///
/// **This page does not move money either.** Like rider payouts, it records
/// something that happened at a desk — a rider handed over notes and somebody
/// counted them. The reference is mandatory for the same reason a payout's UTR
/// is: a settlement nobody can trace is not a record of anything.
///
/// The balance shown is a sum over the ledger, computed on every read. There is
/// no stored balance to reconcile against, which is the point — the rows are the
/// truth and the total is derived from them.

function when(iso: string | null) {
  if (!iso) return '—'
  return new Date(iso).toLocaleDateString('en-IN', {
    day: 'numeric',
    month: 'short',
  })
}

function stamp(iso: string) {
  return new Date(iso).toLocaleString('en-IN', {
    day: 'numeric',
    month: 'short',
    hour: 'numeric',
    minute: '2-digit',
  })
}

const kindLabel: Record<RiderCashEntry['kind'], string> = {
  collected: 'Collected',
  deposited: 'Deposited',
  adjustment: 'Adjustment',
}

export function CashPage() {
  const [rows, setRows] = useState<RiderCashRow[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  const [depositing, setDepositing] = useState<RiderCashRow | null>(null)
  const [amount, setAmount] = useState('')
  const [reference, setReference] = useState('')

  const [adjusting, setAdjusting] = useState<RiderCashRow | null>(null)
  const [delta, setDelta] = useState('')
  const [note, setNote] = useState('')

  const [viewing, setViewing] = useState<RiderCashRow | null>(null)
  const [entries, setEntries] = useState<RiderCashEntry[] | null>(null)

  const [editingCap, setEditingCap] = useState(false)
  const [cap, setCap] = useState('')

  const load = useCallback(async () => {
    try {
      setRows(await api.listRiderCash())
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  // The ledger is fetched when a rider is opened, not with the list. It is one
  // rider's history and the list is every rider's total; loading all of both to
  // show one of them is a page that gets slower every cash delivery.
  useEffect(() => {
    if (!viewing) {
      setEntries(null)
      return
    }
    let live = true
    void api
      .riderCashLedger(viewing.partner_email)
      .then((e) => live && setEntries(e))
      .catch((e) => setError(e instanceof Error ? e.message : String(e)))
    return () => {
      live = false
    }
  }, [viewing])

  async function run(action: () => Promise<void>, close: () => void) {
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

  const held = (rows ?? []).reduce((sum, r) => sum + r.outstanding, 0)
  const holders = (rows ?? []).filter((r) => r.outstanding > 0).length
  const limit = rows?.[0]?.cap ?? 0

  return (
    <>
      <PageHeader
        title="Rider cash"
        subtitle={
          rows
            ? `₹${held} held by ${holders} of ${rows.length} riders · limit ₹${limit}`
            : 'COD collected, deposited, and what is still out there.'
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

        {rows === null ? (
          <TableSkeleton />
        ) : (
          <>
            <div className="mb-4 flex items-center gap-3">
              <p className="text-sm text-ink-muted">
                A rider carrying ₹{limit} or more stops being offered cash
                orders until they hand it in.
              </p>
              <Button
                variant="ghost"
                size="sm"
                onClick={() => {
                  setCap(String(limit))
                  setEditingCap(true)
                }}
              >
                Change limit
              </Button>
            </div>

            <div className="overflow-x-auto rounded-[12px] border border-line bg-white">
              <table className="w-full min-w-[900px] text-sm">
                <thead className="border-b border-line text-left text-ink-muted">
                  <tr>
                    <th className="px-5 py-3 font-medium">Rider</th>
                    <th className="px-5 py-3 text-right font-medium">
                      Collected
                    </th>
                    <th className="px-5 py-3 text-right font-medium">
                      Deposited
                    </th>
                    <th className="px-5 py-3 text-right font-medium">
                      Adjustments
                    </th>
                    <th className="px-5 py-3 text-right font-medium">
                      In hand
                    </th>
                    <th className="px-5 py-3 font-medium">Last collection</th>
                    <th className="px-5 py-3" />
                  </tr>
                </thead>
                <tbody className="divide-y divide-line">
                  {rows.map((r) => (
                    <tr key={r.partner_email}>
                      <td className="px-5 py-3">
                        <p className="font-medium text-ink">
                          {r.partner_name}
                          {!r.is_active && (
                            <span className="ml-2 text-xs text-ink-muted">
                              inactive
                            </span>
                          )}
                        </p>
                        <p className="truncate text-ink-muted">
                          {r.partner_email}
                        </p>
                      </td>
                      <td className="px-5 py-3 text-right tabular-nums text-ink-muted">
                        ₹{r.collected_total}
                        <span className="ml-1 text-xs">
                          ({r.collections})
                        </span>
                      </td>
                      <td className="px-5 py-3 text-right tabular-nums text-ink-muted">
                        ₹{r.deposited_total}
                      </td>
                      <td className="px-5 py-3 text-right tabular-nums text-ink-muted">
                        {r.adjusted_total === 0
                          ? '—'
                          : `${r.adjusted_total > 0 ? '+' : '−'}₹${Math.abs(r.adjusted_total)}`}
                      </td>
                      <td
                        className={`px-5 py-3 text-right font-semibold tabular-nums ${
                          // At or past the limit this rider is no longer being
                          // offered cash work, which is an ops problem and not
                          // just a number.
                          r.outstanding >= r.cap
                            ? 'text-warn'
                            : r.outstanding > 0
                              ? 'text-ink'
                              : 'text-ink-muted'
                        }`}
                      >
                        ₹{r.outstanding}
                      </td>
                      <td className="px-5 py-3 text-ink-muted">
                        {when(r.last_collected_at)}
                      </td>
                      <td className="px-5 py-3">
                        <div className="flex justify-end gap-2">
                          <Button
                            variant="ghost"
                            size="sm"
                            onClick={() => setViewing(r)}
                          >
                            Ledger
                          </Button>
                          <Button
                            variant="secondary"
                            size="sm"
                            disabled={r.outstanding <= 0}
                            title={
                              r.outstanding > 0
                                ? undefined
                                : 'They are not holding anything.'
                            }
                            onClick={() => {
                              setDepositing(r)
                              setAmount(String(r.outstanding))
                              setReference('')
                            }}
                          >
                            Record deposit
                          </Button>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </>
        )}
      </div>

      {depositing && (
        <Modal
          busy={busy}
          onClose={() => setDepositing(null)}
          title={`Cash handed in by ${depositing.partner_name}`}
          footer={
            <>
              <Button
                variant="secondary"
                onClick={() => setDepositing(null)}
                disabled={busy}
              >
                Cancel
              </Button>
              <Button
                loading={busy}
                disabled={
                  Number(amount) <= 0 ||
                  Number(amount) > depositing.outstanding ||
                  reference.trim() === ''
                }
                onClick={() =>
                  void run(
                    () =>
                      api.recordCashDeposit(
                        depositing.partner_email,
                        Number(amount),
                        reference,
                      ),
                    () => setDepositing(null),
                  )
                }
              >
                Record deposit
              </Button>
            </>
          }
        >
          <p className="text-sm text-ink-muted">
            They are holding ₹{depositing.outstanding}. This records what came
            back — it does not transfer anything.
          </p>
          <Field
            className="mt-5"
            label="Amount (₹)"
            type="number"
            min={1}
            max={depositing.outstanding}
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            error={
              Number(amount) > depositing.outstanding
                ? `More than the ₹${depositing.outstanding} they are holding. Use an adjustment if this is a correction.`
                : undefined
            }
          />
          <Field
            className="mt-4"
            label="Reference"
            value={reference}
            onChange={(e) => setReference(e.target.value)}
            placeholder="Deposit slip, UTR, or who took it"
            hint="Without this the deposit cannot be traced later."
          />
          <div className="mt-5 border-t border-line pt-4">
            <button
              type="button"
              className="text-sm font-medium text-ink-muted underline underline-offset-2 hover:text-ink"
              onClick={() => {
                setAdjusting(depositing)
                setDelta('')
                setNote('')
                setDepositing(null)
              }}
            >
              No money came back — write it off instead
            </button>
          </div>
        </Modal>
      )}

      {adjusting && (
        <Modal
          busy={busy}
          onClose={() => setAdjusting(null)}
          title={`Adjust ${adjusting.partner_name}'s balance`}
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
                variant="danger"
                loading={busy}
                disabled={
                  Number(delta) === 0 ||
                  Number.isNaN(Number(delta)) ||
                  note.trim() === ''
                }
                onClick={() =>
                  void run(
                    () =>
                      api.adjustRiderCash(
                        adjusting.partner_email,
                        Number(delta),
                        note,
                      ),
                    () => setAdjusting(null),
                  )
                }
              >
                Adjust
              </Button>
            </>
          }
        >
          <p className="text-sm text-ink-muted">
            The only way a balance moves without money moving. They are holding
            ₹{adjusting.outstanding}; enter −{adjusting.outstanding} to clear it.
            The note is permanent and is the whole point of the action.
          </p>
          <Field
            className="mt-5"
            label="Change (₹, negative to reduce)"
            type="number"
            value={delta}
            onChange={(e) => setDelta(e.target.value)}
            placeholder={`-${adjusting.outstanding}`}
          />
          <TextArea
            className="mt-4"
            label="Why"
            value={note}
            onChange={(e) => setNote(e.target.value)}
            placeholder="Rider left the fleet without depositing; written off 31 Jul."
          />
        </Modal>
      )}

      {viewing && (
        <Modal
          size="lg"
          onClose={() => setViewing(null)}
          title={`${viewing.partner_name} · ₹${viewing.outstanding} in hand`}
          footer={
            <Button variant="secondary" onClick={() => setViewing(null)}>
              Close
            </Button>
          }
        >
          {entries === null ? (
            <TableSkeleton rows={3} />
          ) : entries.length === 0 ? (
            <p className="text-sm text-ink-muted">
              Nothing yet. Cash appears here when they deliver a COD order.
            </p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full min-w-[560px] text-sm">
                <thead className="border-b border-line text-left text-ink-muted">
                  <tr>
                    <th className="py-2 pr-4 font-medium">When</th>
                    <th className="py-2 pr-4 font-medium">What</th>
                    <th className="py-2 pr-4 text-right font-medium">Amount</th>
                    <th className="py-2 font-medium">Against</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-line">
                  {entries.map((e) => (
                    <tr key={e.id}>
                      <td className="py-2 pr-4 whitespace-nowrap text-ink-muted">
                        {stamp(e.created_at)}
                      </td>
                      <td className="py-2 pr-4 text-ink">{kindLabel[e.kind]}</td>
                      <td
                        className={`py-2 pr-4 text-right tabular-nums ${
                          e.amount > 0 ? 'text-ink' : 'text-veg'
                        }`}
                      >
                        {e.amount > 0 ? '+' : '−'}₹{Math.abs(e.amount)}
                      </td>
                      <td className="py-2 text-ink-muted">
                        {e.order_id ??
                          (e.payout_id ? `Payout #${e.payout_id}` : null) ??
                          e.reference ??
                          '—'}
                        {e.note && (
                          <p className="text-xs">{e.note}</p>
                        )}
                        {e.recorded_by && (
                          <p className="text-xs">by {e.recorded_by}</p>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Modal>
      )}

      {editingCap && (
        <Modal
          busy={busy}
          onClose={() => setEditingCap(false)}
          title="Cash limit"
          footer={
            <>
              <Button
                variant="secondary"
                onClick={() => setEditingCap(false)}
                disabled={busy}
              >
                Cancel
              </Button>
              <Button
                loading={busy}
                disabled={Number(cap) <= 0}
                onClick={() =>
                  void run(
                    () => api.setRiderCashCap(Number(cap)),
                    () => setEditingCap(false),
                  )
                }
              >
                Save
              </Button>
            </>
          }
        >
          <p className="text-sm text-ink-muted">
            Platform-wide, and it applies from the next claim — it does not
            change what anybody is already carrying.
          </p>
          <Field
            className="mt-5"
            label="Limit (₹)"
            type="number"
            min={1}
            value={cap}
            onChange={(e) => setCap(e.target.value)}
            hint="₹3,000 to ₹5,000 is the usual range."
          />
        </Modal>
      )}
    </>
  )
}
