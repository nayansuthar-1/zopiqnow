import { useCallback, useEffect, useState } from 'react'
import { api } from '../lib/api'
import type { AdminAlertRow, RiderNoShowRow } from '../lib/api'
import { PageHeader } from '../ui/AppShell'
import {
  Banner,
  Button,
  Card,
  CardSkeleton,
  ConfirmDialog,
  EmptyState,
  Pill,
  SegmentedControl,
} from '../ui/primitives'

/// What the platform noticed while nobody was looking.
///
/// The first and so far only kind is `rider_no_shows` (migration 0130): a rider
/// who accepted deliveries and did not collect them, twice or more inside a
/// week. The sweep that raises it has already done the urgent part — the order
/// was taken back and given to another rider within ten minutes — so nothing on
/// this page is time-critical. What is left is the decision the system
/// deliberately does not make: whether this person should still be working.
///
/// **The suspend button here is the same `admin_set_rider_active` the Riders
/// page has**, and not a special one. Stopping somebody earning is one action
/// with one audit row (0092) however it is reached, and a second path to it
/// would be a second thing to remember to log.
///
/// Resolving is not deleting. An alert somebody dismissed, and who dismissed it,
/// is exactly what the rider's side of a later dispute is made of.

type Filter = 'open' | 'all'

export function AlertsPage() {
  const [rows, setRows] = useState<AdminAlertRow[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [note, setNote] = useState<string | null>(null)
  const [filter, setFilter] = useState<Filter>('open')
  const [busy, setBusy] = useState(false)

  // The alert whose incidents are expanded, and what they are.
  const [openDetail, setOpenDetail] = useState<string | null>(null)
  const [incidents, setIncidents] = useState<RiderNoShowRow[] | null>(null)

  const [suspending, setSuspending] = useState<AdminAlertRow | null>(null)

  const load = useCallback(async (f: Filter) => {
    try {
      setRows(await api.alerts(f === 'all'))
      setError(null)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }, [])

  useEffect(() => {
    void load(filter)
  }, [load, filter])

  const showIncidents = async (email: string) => {
    if (openDetail === email) {
      setOpenDetail(null)
      return
    }
    setOpenDetail(email)
    setIncidents(null)
    try {
      setIncidents(await api.riderNoShows(email))
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }

  const resolve = async (row: AdminAlertRow) => {
    setBusy(true)
    try {
      await api.resolveAlert(row.id)
      setNote('Alert cleared.')
      await load(filter)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  const suspend = async () => {
    if (!suspending?.subject) return
    setBusy(true)
    try {
      await api.setRiderActive(suspending.subject, false)
      // Suspended and then cleared, in that order: the alert asked a question
      // and it has now been answered, so leaving it open would put it back in
      // front of the next admin who has nothing left to decide.
      await api.resolveAlert(suspending.id)
      setNote(`${suspending.rider_name ?? suspending.subject} is suspended.`)
      setSuspending(null)
      await load(filter)
    } catch (e) {
      // The commonest refusal is a rider mid-delivery: the database will not
      // deactivate somebody carrying an order, and says which one.
      setError(e instanceof Error ? e.message : String(e))
      setSuspending(null)
    } finally {
      setBusy(false)
    }
  }

  const open = rows?.filter((r) => !r.resolved_at).length ?? 0

  return (
    <>
      <PageHeader
        title="Alerts"
        subtitle={
          rows === null
            ? 'Things the platform wants a person to look at.'
            : open === 0
              ? 'Nothing needs a decision right now.'
              : `${open} ${open === 1 ? 'alert needs' : 'alerts need'} a decision.`
        }
        action={
          <SegmentedControl<Filter>
            label="Which alerts"
            value={filter}
            onChange={setFilter}
            options={[
              { value: 'open', label: 'Open' },
              { value: 'all', label: 'Including cleared' },
            ]}
          />
        }
      />

      <div className="space-y-4 px-6 py-6">
        {error && (
          <Banner tone="error" onDismiss={() => setError(null)}>
            {error}
          </Banner>
        )}
        {note && (
          <Banner tone="success" onDismiss={() => setNote(null)}>
            {note}
          </Banner>
        )}

        {rows === null && <CardSkeleton rows={3} />}

        {rows !== null && rows.length === 0 && (
          <EmptyState
            title="All clear"
            body={
              filter === 'open'
                ? 'No rider has accepted orders without collecting them. This page fills itself when one does.'
                : 'Nothing has been raised yet.'
            }
          />
        )}

        {rows?.map((row) => (
          <Card key={row.id} className="p-5">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div className="min-w-0">
                <div className="flex flex-wrap items-center gap-2">
                  <h2 className="text-base font-bold text-ink">{row.title}</h2>
                  {row.resolved_at ? (
                    <Pill tone="neutral">Cleared</Pill>
                  ) : (
                    <Pill tone="warn">{row.no_show_count} in the last week</Pill>
                  )}
                  {row.rider_active === false && <Pill tone="danger">Suspended</Pill>}
                </div>
                {row.rider_phone && (
                  <p className="mt-1 text-sm text-ink-muted">
                    {row.subject} · {row.rider_phone}
                  </p>
                )}
              </div>
              <p className="shrink-0 text-xs text-ink-muted">
                {new Date(row.created_at).toLocaleString()}
              </p>
            </div>

            {/* The sentence the sweep wrote, and the same one the email carries.
                Rendered whole rather than reassembled here: two spellings of the
                same alert are one edit apart from disagreeing. */}
            <p className="mt-3 whitespace-pre-line text-sm text-ink">{row.body}</p>

            {openDetail === row.subject && (
              <div className="mt-4 rounded-[8px] bg-canvas p-4">
                {incidents === null ? (
                  <p className="text-sm text-ink-muted">Loading…</p>
                ) : (
                  <ul className="space-y-2">
                    {incidents.map((i) => (
                      <li key={i.order_id} className="text-sm text-ink-muted">
                        <span className="font-semibold text-ink">{i.order_id}</span>
                        {' — accepted '}
                        {new Date(i.accepted_at).toLocaleString()}
                        {i.ready_at &&
                          `, food ready ${new Date(i.ready_at).toLocaleTimeString()}`}
                        {', taken back '}
                        {new Date(i.released_at).toLocaleTimeString()}
                        {i.had_arrived && (
                          <span className="ml-2">
                            <Pill tone="neutral">Was at the restaurant</Pill>
                          </span>
                        )}
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            )}

            {!row.resolved_at && (
              <div className="mt-4 flex flex-wrap gap-2">
                {row.subject && (
                  <Button variant="secondary" onClick={() => void showIncidents(row.subject!)}>
                    {openDetail === row.subject ? 'Hide the orders' : 'See the orders'}
                  </Button>
                )}
                {row.subject && row.rider_active !== false && (
                  <Button variant="danger" onClick={() => setSuspending(row)}>
                    Suspend this rider
                  </Button>
                )}
                <Button variant="secondary" onClick={() => void resolve(row)} disabled={busy}>
                  Clear without suspending
                </Button>
              </div>
            )}

            {row.resolved_at && row.resolved_by && (
              <p className="mt-3 text-xs text-ink-muted">
                Cleared by {row.resolved_by} on{' '}
                {new Date(row.resolved_at).toLocaleString()}
              </p>
            )}
          </Card>
        ))}
      </div>

      {suspending && (
        <ConfirmDialog
          title={`Suspend ${suspending.rider_name ?? suspending.subject}?`}
          body={
            <>
              They stop being offered new deliveries immediately and keep every
              job they are already carrying. Their history and pay are untouched,
              and you can switch them back on from the Riders page at any time.
            </>
          }
          confirmLabel="Suspend"
          tone="danger"
          busy={busy}
          onConfirm={() => void suspend()}
          onCancel={() => setSuspending(null)}
        />
      )}
    </>
  )
}
