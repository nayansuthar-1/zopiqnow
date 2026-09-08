import { useCallback, useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { api } from '../lib/api'
import type { AuditActionRow, AuditFilterRow } from '../lib/api'
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
  SearchField,
  Select,
  TableSkeleton,
  Td,
  Th,
} from '../ui/primitives'
import { useUrlPage, useUrlState } from '../ui/urlState'

/// Who did what, from the append-only trail (0092, readable since 0164).
///
/// Everything an admin does that cannot be undone from inside the product has
/// been recorded since August — a publish, a forced publish, a cancelled order,
/// a refund pushed to Razorpay, a restaurant delisted, an admin added — and
/// until now the only way to read one was a psql session. This is the screen
/// that makes the trail worth having.
///
/// **Read-only, and deliberately without an export.** Every lever is elsewhere,
/// each with its own audit row behind it; a second way to act from here would
/// be a second path to the same action. And a button that hands somebody the
/// whole trail as a file turns an append-only record into a spreadsheet on a
/// laptop, which is the one thing this table was built not to be.
///
/// **The dropdowns are asked of the data, not hardcoded.** 0092 wired thirteen
/// audit triggers and there are twenty-three now; a list of tables written in
/// this file would be wrong the first time somebody adds the twenty-fourth.

const PAGE_SIZE = 50

/// Where a target lives, when it lives anywhere. A row the console has no
/// screen for — a menu item, a settlement line — simply is not a link, which is
/// a better answer than a link to a page that cannot show it.
///
/// The exception worth naming is a **deleted** row: the id is still real to
/// everyone who saw it, but the record it pointed at is gone, so linking would
/// send somebody to a page that can only fail. Orders are the one target where
/// that is not true — `admin_order_detail` answers a deleted id with the
/// sentence naming who deleted it and why (0154), which is exactly what the
/// person clicking wants to know.
function hrefFor(row: AuditActionRow): string | null {
  const id = row.target_id
  if (!id) return null
  if (row.target_type === 'orders') return `/orders/${id}`
  if (row.action === 'delete') return null

  switch (row.target_type) {
    case 'restaurants':
      return `/restaurants/${id}`
    case 'menu_items':
      return null
    case 'coupons':
      return '/coupons'
    case 'hero_slides':
      return '/hero'
    case 'refunds':
      return '/refunds'
    case 'settlements':
      return '/settlements'
    case 'rider_payouts':
      return '/payouts'
    case 'delivery_partners':
    case 'rider_legal':
      return '/riders'
    case 'restaurant_staff':
      return `/restaurants/${id}`
    case 'user_blocks':
      return '/users'
    case 'support_tickets':
      return '/support'
    case 'admin_alerts':
      return '/alerts'
    case 'gift_orders':
      return '/gift-orders'
    case 'platform_admins':
      return '/settings'
    case 'service_areas':
      return '/settings/areas'
    case 'dispatch_settings':
    case 'delivery_settings':
    case 'delivery_surcharge_settings':
      return '/settings/platform'
    default:
      return null
  }
}

const actionTones: Record<string, 'live' | 'warn' | 'danger' | 'brand'> = {
  insert: 'live',
  update: 'brand',
  delete: 'danger',
  publish_forced: 'warn',
}

function when(iso: string) {
  return new Date(iso).toLocaleString('en-IN', {
    day: '2-digit',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  })
}

/// A `YYYY-MM-DD` from a date input as the first instant of that day, locally.
/// `new Date('2026-09-08')` is UTC midnight, which in IST is the previous
/// evening — see `lib/dates.ts`, which exists because of exactly that.
function startOfDayLocal(value: string): Date {
  return new Date(`${value}T00:00:00`)
}

/// The "to" end of the window, as the RPC wants it: `created_at < p_to`, so the
/// day somebody named is included by handing over the midnight that ends it.
/// `endOfDayLocal` would be 23:59:59 and would drop the last second of the day
/// — a second nobody would ever notice missing, until the one time they did.
function endExclusive(value: string): Date {
  const d = startOfDayLocal(value)
  d.setDate(d.getDate() + 1)
  return d
}

/// One value out of `detail`, as a line of text. Objects and arrays are printed
/// as JSON rather than as `[object Object]`; a null is said in words, because
/// "gst_rate_bps: nothing → 500" reads as a fact and an empty cell reads as a
/// bug. Long values are cut here and whole in the dialog — this is a column in
/// a table, and the four sentences behind a forced publish would otherwise make
/// one row as tall as the other nine put together.
function said(value: unknown): string {
  const text =
    value === null || value === undefined
      ? 'nothing'
      : typeof value === 'string'
        ? value === ''
          ? '(blank)'
          : value
        : typeof value === 'object'
          ? JSON.stringify(value)
          : String(value)
  return text.length > 120 ? `${text.slice(0, 120)}…` : text
}

/// An insert and a delete carry the whole row under one key. Which one, or null
/// if this detail is something else.
function wholeRow(detail: Record<string, unknown> | null): string | null {
  if (!detail) return null
  const keys = Object.keys(detail)
  if (keys.length !== 1) return null
  const only = keys[0]
  if (only !== 'created' && only !== 'deleted') return null
  return typeof detail[only] === 'object' && detail[only] !== null ? only : null
}

/// The detail as lines to print, whichever of the three shapes it has.
///
/// An **update** arrives from the database already reduced to `{column: {from,
/// to}}`, and reads as the change it was. A **named action** — `publish_forced`
/// is the one that exists today — writes its own object instead, and its keys
/// are not columns at all: the reason somebody gave, and the four checks they
/// went around. Those are the rows this screen exists for, so they are printed
/// as they were written rather than hidden behind a dialog.
function lines(
  detail: Record<string, unknown> | null,
): { label: string; value: string }[] {
  if (!detail) return []
  return Object.entries(detail).map(([label, v]) => {
    const pair = v as Record<string, unknown> | null
    const isPair =
      typeof v === 'object' && v !== null && ('from' in v || 'to' in v)
    return {
      label,
      value: isPair
        ? `${said(pair?.from ?? null)} → ${said(pair?.to ?? null)}`
        : said(v),
    }
  })
}

export function AuditPage() {
  const [rows, setRows] = useState<AuditActionRow[] | null>(null)
  const [filters, setFilters] = useState<AuditFilterRow[]>([])
  const [error, setError] = useState<string | null>(null)
  const [showing, setShowing] = useState<AuditActionRow | null>(null)

  // In the address bar, like every other list since 0158's sibling change, so
  // "what did we do to Wing Orbit last week" is a link somebody can be sent.
  const [actor, setActor] = useUrlState('who', '')
  const [action, setAction] = useUrlState('did', '')
  // `on`, not `to`: the date window's far end is the `until` below, and two
  // query keys a letter apart on one screen is how a shared link comes back
  // filtered by something nobody meant.
  const [targetType, setTargetType] = useUrlState('on', '')
  const [applied, setApplied] = useUrlState('id', '')
  const [from, setFrom] = useUrlState('from', '')
  const [to, setTo] = useUrlState('until', '')
  const [page, setPage] = useUrlPage()

  // What is being typed, against what the database was actually asked. Only the
  // second belongs in the URL, and submitting the form is what moves one into
  // the other.
  const [query, setQuery] = useState(applied)
  useEffect(() => setQuery(applied), [applied])

  const load = useCallback(async () => {
    try {
      setRows(
        await api.auditActions({
          actor: actor || null,
          action: action || null,
          targetType: targetType || null,
          targetId: applied || null,
          from: from ? startOfDayLocal(from).toISOString() : null,
          to: to ? endExclusive(to).toISOString() : null,
          limit: PAGE_SIZE,
          offset: page * PAGE_SIZE,
        }),
      )
      setError(null)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }, [actor, action, targetType, applied, from, to, page])

  useEffect(() => {
    void load()
  }, [load])

  useEffect(() => {
    api
      .auditFilters()
      .then(setFilters)
      // The dropdowns are a convenience — every filter can also be typed into
      // the address bar — so a failure here must not take the trail down with
      // it.
      .catch(() => setFilters([]))
  }, [])

  const actors = filters.filter((f) => f.kind === 'actor')
  const actions = filters.filter((f) => f.kind === 'action')
  const targets = filters.filter((f) => f.kind === 'target')

  const total = rows?.[0]?.total_count ?? 0
  const pages = Math.max(1, Math.ceil(total / PAGE_SIZE))
  const narrowed =
    actor !== '' ||
    action !== '' ||
    targetType !== '' ||
    applied !== '' ||
    from !== '' ||
    to !== ''

  const subtitle = useMemo(() => {
    if (rows === null) return 'Everything an admin has done, oldest kept forever.'
    if (total === 0) return 'Nothing matches these filters.'
    const start = page * PAGE_SIZE + 1
    const end = page * PAGE_SIZE + rows.length
    return `${start}–${end} of ${total} action${total === 1 ? '' : 's'}`
  }, [rows, total, page])

  function reset() {
    setQuery('')
    setApplied('')
    setActor('')
    setAction('')
    setTargetType('')
    setFrom('')
    setTo('')
    setPage(0)
  }

  return (
    <>
      <PageHeader
        title="Audit log"
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

        <div className="mb-5 space-y-3">
          <SearchField
            label="Find everything done to one thing"
            placeholder="ZPQ-1044, a coupon code, an email, a row id"
            submitLabel="Find"
            value={query}
            onChange={setQuery}
            onSubmit={() => {
              setPage(0)
              setApplied(query.trim())
            }}
            onClear={
              applied !== ''
                ? () => {
                    setQuery('')
                    setApplied('')
                    setPage(0)
                  }
                : undefined
            }
          />
          {/* The one filter that is not a dropdown is also the one that has to
              match exactly — it is an id, not a search term, and half of one
              would find the wrong row rather than none. Said here, because a
              box that silently finds nothing reads as a broken box. */}
          <p className="text-xs text-ink-muted">
            Matched whole, not in part. Upper and lower case are the same.
          </p>

          <div className="flex flex-wrap items-end gap-x-4 gap-y-3">
            <Select
              label="Who"
              size="sm"
              value={actor}
              onChange={(e) => {
                setPage(0)
                setActor(e.target.value)
              }}
            >
              <option value="">Anybody</option>
              {actors.map((f) => (
                <option key={f.value} value={f.value}>
                  {f.value} ({f.uses})
                </option>
              ))}
            </Select>

            <Select
              label="Did"
              size="sm"
              value={action}
              onChange={(e) => {
                setPage(0)
                setAction(e.target.value)
              }}
            >
              <option value="">Anything</option>
              {actions.map((f) => (
                <option key={f.value} value={f.value}>
                  {f.value} ({f.uses})
                </option>
              ))}
            </Select>

            <Select
              label="To"
              size="sm"
              value={targetType}
              onChange={(e) => {
                setPage(0)
                setTargetType(e.target.value)
              }}
            >
              <option value="">Anything on the platform</option>
              {targets.map((f) => (
                <option key={f.value} value={f.value}>
                  {f.value} ({f.uses})
                </option>
              ))}
            </Select>

            <Field
              label="From"
              type="date"
              className="w-40"
              value={from}
              max={to || undefined}
              onChange={(e) => {
                setPage(0)
                setFrom(e.target.value)
              }}
            />
            <Field
              label="Until"
              type="date"
              className="w-40"
              value={to}
              min={from || undefined}
              onChange={(e) => {
                setPage(0)
                setTo(e.target.value)
              }}
            />

            {narrowed && (
              <Button variant="ghost" onClick={reset}>
                Clear filters
              </Button>
            )}
          </div>
        </div>

        {rows === null ? (
          <TableSkeleton rows={8} />
        ) : rows.length === 0 ? (
          <EmptyState
            title={narrowed ? 'No match' : 'Nothing recorded yet'}
            body={
              narrowed
                ? 'Nothing in the trail matches these filters. An id has to be typed whole — ZPQ-1044, not 1044.'
                : 'This fills itself the moment an admin changes anything.'
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
            <DataTable label="Audit log" minWidth={960}>
              <thead>
                <tr>
                  <Th>When</Th>
                  <Th>Who</Th>
                  <Th>What</Th>
                  <Th>Which row</Th>
                  <Th>What changed</Th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => {
                  const href = hrefFor(r)
                  const snapshot = wholeRow(r.detail)
                  const printed = lines(r.detail)
                  return (
                    <tr key={r.id}>
                      <Td className="whitespace-nowrap text-ink">
                        {when(r.created_at)}
                      </Td>
                      <Td>
                        {/* `system` is not a person: it is what the recorder
                            writes when there was no JWT, which means a
                            migration, a cron job or a trigger cascade. Worth
                            saying, because "who did this" answered with an
                            email nobody recognises is a different worry. */}
                        {r.actor_email === 'system' ? (
                          <span className="text-ink-muted">
                            system
                            <span className="block text-xs">
                              a job, not a person
                            </span>
                          </span>
                        ) : (
                          <span className="text-ink">{r.actor_email}</span>
                        )}
                      </Td>
                      <Td>
                        <Pill tone={actionTones[r.action] ?? 'neutral'}>
                          {r.action.replace(/_/g, ' ')}
                        </Pill>
                        <p className="mt-1 text-xs text-ink-muted">
                          {r.target_type}
                        </p>
                      </Td>
                      <Td>
                        {r.target_id === null ? (
                          <span className="text-ink-muted">—</span>
                        ) : href ? (
                          <Link
                            to={href}
                            className="font-medium text-ink underline decoration-line underline-offset-4 hover:decoration-brand-ink"
                          >
                            {r.target_id}
                          </Link>
                        ) : (
                          <span className="text-ink">{r.target_id}</span>
                        )}
                      </Td>
                      <Td>
                        {snapshot ? (
                          // The whole row, which belongs in a dialog rather than
                          // in a cell — a deleted order is forty columns, and
                          // this one is the only copy of it left.
                          <Button
                            variant="ghost"
                            size="sm"
                            onClick={() => setShowing(r)}
                          >
                            {snapshot === 'deleted'
                              ? 'The row as it was'
                              : 'The row as written'}
                          </Button>
                        ) : printed.length === 0 ? (
                          <span className="text-ink-muted">
                            nothing — the row was written back unchanged
                          </span>
                        ) : (
                          <>
                            <ul className="max-w-md space-y-0.5">
                              {printed.slice(0, 3).map((l) => (
                                <li key={l.label} className="wrap-break-word text-ink">
                                  <span className="text-ink-muted">
                                    {l.label}
                                  </span>{' '}
                                  {l.value}
                                </li>
                              ))}
                            </ul>
                            {printed.length > 3 && (
                              <Button
                                variant="ghost"
                                size="sm"
                                onClick={() => setShowing(r)}
                              >
                                {printed.length - 3} more
                              </Button>
                            )}
                          </>
                        )}
                      </Td>
                    </tr>
                  )
                })}
              </tbody>
            </DataTable>

            <Pager page={page} pages={pages} onChange={setPage} />
          </>
        )}
      </PageBody>

      {showing && (
        <Modal
          size="lg"
          onClose={() => setShowing(null)}
          title={`${showing.action.replace(/_/g, ' ')} · ${showing.target_type}${
            showing.target_id ? ` · ${showing.target_id}` : ''
          }`}
          footer={
            <Button variant="secondary" onClick={() => setShowing(null)}>
              Close
            </Button>
          }
        >
          <p className="text-sm text-ink-muted">
            {showing.actor_email} · {when(showing.created_at)}
          </p>
          {/* The stored detail, as stored. An update arrives already reduced to
              the columns that changed; an insert and a delete keep the whole
              row, and for a deleted order this snapshot is the only copy of it
              left anywhere on the platform. */}
          <pre className="mt-4 max-h-[60vh] overflow-auto rounded-field border border-line bg-canvas p-4 text-xs text-ink">
            {JSON.stringify(showing.detail, null, 2)}
          </pre>
        </Modal>
      )}
    </>
  )
}
