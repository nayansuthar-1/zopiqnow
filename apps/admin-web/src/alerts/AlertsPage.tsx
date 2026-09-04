import { useCallback, useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
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
  PageBody,
  Pill,
  SegmentedControl,
  Skeleton,
} from '../ui/primitives'
import { useToast } from '../ui/toast'

/// What the platform noticed while nobody was looking.
///
/// `rider_no_shows` (migration 0130) is a rider who accepted deliveries and did
/// not collect them, twice or more inside a week. The sweep that raises it has
/// already done the urgent part — the order was taken back and given to another
/// rider within ten minutes — so nothing about it is time-critical. What is left
/// is the decision the system deliberately does not make: whether this person
/// should still be working.
///
/// `refunds_stalled` (migration 0149) is money owed to customers that has
/// stopped moving: approved past the date they were promised, sitting with the
/// gateway unconfirmed, or refused outright. It is one standing alert rather
/// than one per refund, because the queue itself is the Refunds page and a
/// second copy of it here would be worked in one place and cleared in the other.
///
/// **Every action offered here belongs to another page.** Suspending is the same
/// `admin_set_rider_active` the Riders page calls, and the refunds button only
/// navigates. One action with one audit row (0092) however it is reached; a
/// second path to it would be a second thing to remember to log.
///
/// Resolving is not deleting. An alert somebody dismissed, and who dismissed it,
/// is exactly what the rider's side of a later dispute is made of. A
/// self-clearing kind offers no Clear button at all — the sweep that raised it
/// takes it down when the condition ends, and dismissing one by hand would only
/// mean a fresh copy fifteen minutes later.

type Filter = 'open' | 'all'

/// The kinds this page knows how to do something about. Anything else — a kind
/// added by a later migration and not taught here yet — still renders its title,
/// body and date, which is the whole alert; it just carries no buttons.
const RIDER_NO_SHOWS = 'rider_no_shows'
const REFUNDS_STALLED = 'refunds_stalled'

/// Pinned to `en-IN`, like every other date in the console. These five calls
/// passed no locale at all, so they rendered in whichever one the browser was
/// set to — an admin on a US-defaulted machine read `9/4/2026, 7:30 PM` on this
/// page and `04 Sep, 19:30` on the order the alert is about, which is the same
/// moment written two ways on two screens somebody reads in sequence.
function when(iso: string) {
  return new Date(iso).toLocaleString('en-IN', {
    day: '2-digit',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  })
}

function clock(iso: string) {
  return new Date(iso).toLocaleTimeString('en-IN', {
    hour: '2-digit',
    minute: '2-digit',
  })
}

export function AlertsPage() {
  const toast = useToast()
  const navigate = useNavigate()
  const [rows, setRows] = useState<AdminAlertRow[] | null>(null)
  const [error, setError] = useState<string | null>(null)
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
      toast('Alert cleared.')
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
      toast(`${suspending.rider_name ?? suspending.subject} is suspended.`)
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

      <PageBody className="space-y-4">
        {error && (
          <Banner tone="error" onDismiss={() => setError(null)}>
            {error}
          </Banner>
        )}

        {rows === null && <CardSkeleton rows={3} />}

        {rows !== null && rows.length === 0 && (
          <EmptyState
            title="All clear"
            body={
              filter === 'open'
                ? 'No rider is ghosting orders and no refund is stuck. This page fills itself when either changes.'
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
                    // `no_show_count` counts rider incidents and is 0 for every
                    // other kind, whose title already carries its own number.
                    row.kind === RIDER_NO_SHOWS && (
                      <Pill tone="warn">{row.no_show_count} in the last week</Pill>
                    )
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
                {when(row.created_at)}
              </p>
            </div>

            {/* The sentence the sweep wrote, and the same one the email carries.
                Rendered whole rather than reassembled here: two spellings of the
                same alert are one edit apart from disagreeing. */}
            <p className="mt-3 whitespace-pre-line text-sm text-ink">{row.body}</p>

            {openDetail === row.subject && (
              <div className="mt-4 rounded-field bg-canvas p-4">
                {incidents === null ? (
                  <div className="space-y-2">
                    <Skeleton className="h-4 w-72" />
                    <Skeleton className="h-4 w-56" />
                  </div>
                ) : (
                  <ul className="space-y-2">
                    {incidents.map((i) => (
                      <li key={i.order_id} className="text-sm text-ink-muted">
                        <span className="font-semibold text-ink">{i.order_id}</span>
                        {' — accepted '}
                        {when(i.accepted_at)}
                        {i.ready_at &&
                          `, food ready ${clock(i.ready_at)}`}
                        {', taken back '}
                        {clock(i.released_at)}
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
                {row.kind === RIDER_NO_SHOWS && row.subject && (
                  <>
                    <Button variant="secondary" onClick={() => void showIncidents(row.subject!)}>
                      {openDetail === row.subject ? 'Hide the orders' : 'See the orders'}
                    </Button>
                    {row.rider_active !== false && (
                      <Button variant="danger" onClick={() => setSuspending(row)}>
                        Suspend this rider
                      </Button>
                    )}
                    <Button variant="secondary" onClick={() => void resolve(row)} disabled={busy}>
                      Clear without suspending
                    </Button>
                  </>
                )}

                {/* Navigation and nothing else. Approving, declining and marking
                    a refund paid all live on the Refunds page, and this alert
                    exists to say that page needs opening — not to become it. */}
                {row.kind === REFUNDS_STALLED && (
                  <Button variant="secondary" onClick={() => navigate('/refunds')}>
                    Open the refunds queue
                  </Button>
                )}

                {row.kind !== RIDER_NO_SHOWS && row.kind !== REFUNDS_STALLED && (
                  <Button variant="secondary" onClick={() => void resolve(row)} disabled={busy}>
                    Clear this alert
                  </Button>
                )}
              </div>
            )}

            {row.resolved_at && row.resolved_by && (
              <p className="mt-3 text-xs text-ink-muted">
                Cleared by {row.resolved_by} on{' '}
                {when(row.resolved_at)}
              </p>
            )}
          </Card>
        ))}
      </PageBody>

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
