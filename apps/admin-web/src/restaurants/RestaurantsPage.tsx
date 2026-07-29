import { useEffect, useMemo, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { api, statusOf } from '../lib/api'
import type { RestaurantRow, Status } from '../lib/api'
import { PageHeader } from '../ui/AppShell'
import { Banner, Button, ConfirmDialog, EmptyState, Pill, TableSkeleton } from '../ui/primitives'

const statusLabels: Record<Status, string> = {
  live: 'Live',
  paused: 'Paused by kitchen',
  draft: 'Draft',
  delisted: 'Delisted',
}

const statusTones: Record<Status, 'live' | 'warn' | 'neutral' | 'danger'> = {
  live: 'live',
  paused: 'warn',
  draft: 'neutral',
  delisted: 'danger',
}

function StatusPill({ status }: { status: Status }) {
  return <Pill tone={statusTones[status]}>{statusLabels[status]}</Pill>
}

export function RestaurantsPage() {
  const navigate = useNavigate()
  const [rows, setRows] = useState<RestaurantRow[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [query, setQuery] = useState('')
  const [filter, setFilter] = useState<Status | 'all'>('all')
  const [confirming, setConfirming] = useState<RestaurantRow | null>(null)
  const [deleting, setDeleting] = useState<RestaurantRow | null>(null)
  const [busy, setBusy] = useState(false)

  async function load() {
    setError(null)
    try {
      setRows(await api.listRestaurants())
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }

  useEffect(() => {
    void load()
  }, [])

  const visible = useMemo(() => {
    const q = query.trim().toLowerCase()
    return (rows ?? []).filter((r) => {
      if (filter !== 'all' && statusOf(r) !== filter) return false
      if (!q) return true
      return (
        r.name.toLowerCase().includes(q) ||
        (r.city ?? '').toLowerCase().includes(q) ||
        (r.owner_email ?? '').toLowerCase().includes(q)
      )
    })
  }, [rows, query, filter])

  async function unpublish(r: RestaurantRow) {
    setBusy(true)
    try {
      await api.unpublishRestaurant(r.id)
      setConfirming(null)
      await load()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
      setConfirming(null)
    } finally {
      setBusy(false)
    }
  }

  async function destroy(r: RestaurantRow) {
    setBusy(true)
    try {
      await api.deleteRestaurant(r.id)
      setDeleting(null)
      await load()
    } catch (e) {
      // The refusal is the useful part — "has 3 order(s) on record" — so it goes
      // to the page banner rather than vanishing with the dialog.
      setError(e instanceof Error ? e.message : String(e))
      setDeleting(null)
    } finally {
      setBusy(false)
    }
  }

  return (
    <>
      <PageHeader
        title="Restaurants"
        subtitle={
          rows
            ? `${rows.length} on the platform · ${rows.filter((r) => statusOf(r) === 'draft').length} unfinished`
            : undefined
        }
        action={
          <Button onClick={() => navigate('/restaurants/new')}>Add restaurant</Button>
        }
      />

      <div className="p-6">
        <div className="mb-4 flex flex-wrap items-center gap-3">
          <input
            className="h-10 w-full max-w-xs rounded-[8px] border border-line bg-white px-3 text-sm outline-none placeholder:text-ink-muted focus:border-brand"
            placeholder="Search name, city, or owner"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
          <div className="flex gap-1">
            {(['all', 'live', 'paused', 'draft', 'delisted'] as const).map((f) => (
              <button
                key={f}
                onClick={() => setFilter(f)}
                className={`rounded-full px-3 py-1.5 text-sm font-medium transition-colors ${
                  filter === f
                    ? 'bg-ink text-white'
                    : 'bg-white text-ink-muted hover:text-ink'
                }`}
              >
                {f === 'all' ? 'All' : statusLabels[f]}
              </button>
            ))}
          </div>
        </div>

        {error && (
          <Banner tone="error" className="mb-4">{error}</Banner>
        )}

        {rows === null ? (
          <TableSkeleton rows={5} />
        ) : visible.length === 0 ? (
          rows.length === 0 ? (
            <EmptyState
              title="No restaurants yet"
              body="Restaurants are onboarded here and nowhere else — there is no self-service signup. Add the first one."
              action={
                <Button onClick={() => navigate('/restaurants/new')}>
                  Add restaurant
                </Button>
              }
            />
          ) : (
            <EmptyState
              title="Nothing matches that"
              body="No restaurant matches this search and filter together. Try clearing one of them."
            />
          )
        ) : (
          <div className="overflow-x-auto rounded-[12px] border border-line bg-white">
            <table className="w-full min-w-[820px] text-left text-sm">
              <thead className="border-b border-line text-xs uppercase tracking-wide text-ink-muted">
                <tr>
                  <th className="px-5 py-3 font-semibold">Restaurant</th>
                  <th className="px-5 py-3 font-semibold">Status</th>
                  <th className="px-5 py-3 font-semibold">Owner</th>
                  <th className="px-5 py-3 text-right font-semibold">Dishes</th>
                  <th className="px-5 py-3" />
                </tr>
              </thead>
              <tbody>
                {visible.map((r) => {
                  const status = statusOf(r)
                  return (
                    <tr key={r.id} className="border-b border-line last:border-0">
                      <td className="px-5 py-3">
                        <Link
                          to={`/restaurants/${r.id}`}
                          className="font-semibold text-ink hover:text-brand-deep"
                        >
                          {r.name}
                        </Link>
                        <div className="text-xs text-ink-muted">
                          {r.city ?? 'No city yet'}
                        </div>
                      </td>
                      <td className="px-5 py-3">
                        <StatusPill status={status} />
                      </td>
                      <td className="px-5 py-3 text-ink-muted">
                        {r.owner_email ?? (
                          <span className="text-non-veg">No owner</span>
                        )}
                      </td>
                      <td
                        className={`px-5 py-3 text-right tabular-nums ${
                          r.menu_item_count === 0 ? 'text-non-veg' : 'text-ink-muted'
                        }`}
                      >
                        {r.menu_item_count}
                      </td>
                      <td className="px-5 py-3">
                        <div className="flex justify-end gap-2">
                          <Button
                            variant="secondary"
                            className="h-9 px-3"
                            onClick={() => navigate(`/restaurants/${r.id}`)}
                          >
                            Edit
                          </Button>
                          {r.is_active ? (
                            <Button
                              variant="ghost"
                              className="h-9 px-3"
                              onClick={() => setConfirming(r)}
                            >
                              Delist
                            </Button>
                          ) : (
                            // Offered on anything not live, and the RPC decides:
                            // a restaurant with orders is refused by name and
                            // count (0044). The list does not carry an order
                            // count, and adding one to grey out a button would
                            // be a query on every row to pre-empt a sentence the
                            // refusal already says better.
                            <Button
                              variant="ghost"
                              className="h-9 px-3"
                              onClick={() => setDeleting(r)}
                            >
                              Delete
                            </Button>
                          )}
                        </div>
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {confirming && (
        <ConfirmDialog
          title={`Delist ${confirming.name}?`}
          // Naming the consequence, and the non-consequence. "Delist" reads like
          // deletion to someone moving quickly, and the orders already in that
          // kitchen are the thing they would be afraid of losing.
          body="Customers will stop seeing this restaurant immediately. Orders already placed are unaffected — the kitchen can still see and finish them."
          confirmLabel="Delist"
          busy={busy}
          onCancel={() => setConfirming(null)}
          onConfirm={() => void unpublish(confirming)}
        />
      )}

      {deleting && (
        <ConfirmDialog
          title={`Delete ${deleting.name}?`}
          // The opposite warning to Delist's. There the fear was losing orders;
          // here the point is that this really does erase, and the one thing it
          // will not erase is a restaurant somebody has ordered from.
          body="This erases the restaurant and its menu, hours, licence, bank details and team. It cannot be undone. A restaurant that has taken even one order cannot be deleted at all — delist it instead."
          confirmLabel="Delete"
          busy={busy}
          onCancel={() => setDeleting(null)}
          onConfirm={() => void destroy(deleting)}
        />
      )}
    </>
  )
}
