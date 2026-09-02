import { useCallback, useEffect, useMemo, useState } from 'react'
import { api } from '../lib/api'
import type {
  UserDetail,
  UserOrder,
  UserRole,
  UserRow,
} from '../lib/api'
import { PageHeader } from '../ui/AppShell'
import {
  Banner,
  Button,
  Card,
  DataTable,
  EmptyState,
  Field,
  Modal,
  PageBody,
  Pill,
  SegmentedControl,
  TableSkeleton,
  Td,
  Th,
} from '../ui/primitives'
import { inr } from '../lib/money'

/// Everybody on the platform, and the power to shut one of them out.
///
/// There is no `users` table behind this and there should not be: a person is a
/// row in `auth.users`, and what they are allowed to do lives in three separate
/// tables keyed by email. So this screen is the one place the four populations
/// — customers, restaurant staff, riders, admins — are visible as one list, and
/// the role column is derived rather than stored.
///
/// Blocking is the only destructive thing here, and it is deliberately not a
/// toggle in the row. It asks for a reason, it says what will happen, and the
/// database keeps the answer forever (migration 0088). Two refusals are the
/// database's and not this screen's: you cannot block yourself, and you cannot
/// block another admin.

const roleTone: Record<UserRole, 'brand' | 'live' | 'warn' | 'neutral'> = {
  admin: 'brand',
  vendor: 'live',
  rider: 'warn',
  customer: 'neutral',
}

const roleLabel: Record<UserRole, string> = {
  admin: 'Admin',
  vendor: 'Restaurant',
  rider: 'Rider',
  customer: 'Customer',
}

type Filter = 'all' | UserRole | 'blocked'

function when(iso: string | null) {
  if (!iso) return 'never'
  return new Date(iso).toLocaleString('en-IN', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  })
}

/// The counts, side by side, so the shape of somebody's history reads at a
/// glance. A customer whose orders are mostly cancelled is the reason this
/// screen shows three numbers instead of one.
function Counts({ user }: { user: UserRow }) {
  if (user.total_orders === 0) {
    return <span className="text-ink-muted">No orders</span>
  }
  return (
    <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
      <span className="font-semibold text-ink">{user.total_orders} total</span>
      <span className="text-veg">{user.delivered_orders} delivered</span>
      {user.rejected_orders > 0 && (
        <span className="text-non-veg-ink">{user.rejected_orders} declined</span>
      )}
      {user.cancelled_orders > 0 && (
        <span className="text-warn">{user.cancelled_orders} cancelled</span>
      )}
    </div>
  )
}

/// Everything known about one person, plus every order they have placed.
function UserSheet({
  user,
  onClose,
  onBlockToggle,
}: {
  user: UserRow
  onClose: () => void
  onBlockToggle: (user: UserRow) => void
}) {
  const [detail, setDetail] = useState<UserDetail | null>(null)
  const [orders, setOrders] = useState<UserOrder[] | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let live = true
    Promise.all([api.getUser(user.user_id), api.userOrders(user.user_id)])
      .then(([d, o]) => {
        if (!live) return
        setDetail(d)
        setOrders(o)
      })
      .catch((e: unknown) => {
        if (live) setError(e instanceof Error ? e.message : String(e))
      })
    return () => {
      live = false
    }
  }, [user.user_id])

  return (
    <Modal
      title={user.name ?? user.email ?? 'This person'}
      onClose={onClose}
      size="lg"
      footer={
        <div className="flex items-center justify-between gap-3">
          <span className="text-xs text-ink-muted">
            Signed up {when(user.created_at)} · last seen{' '}
            {when(user.last_sign_in_at)}
          </span>
          <Button
            variant={user.is_blocked ? 'secondary' : 'danger'}
            onClick={() => onBlockToggle(user)}
          >
            {user.is_blocked ? 'Unblock' : 'Block this person'}
          </Button>
        </div>
      }
    >
      {error && (
        <Banner tone="error" onDismiss={() => setError(null)}>
          {error}
        </Banner>
      )}

      <div className="grid gap-3 sm:grid-cols-2">
        <Card>
          <p className="text-xs tracking-wide text-ink-muted uppercase">Who</p>
          <dl className="mt-2 space-y-1 text-sm">
            <div className="flex justify-between gap-4">
              <dt className="text-ink-muted">Role</dt>
              <dd>
                <Pill tone={roleTone[user.role]}>{roleLabel[user.role]}</Pill>
              </dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="text-ink-muted">Email</dt>
              <dd className="text-ink">{user.email ?? '—'}</dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="text-ink-muted">Phone</dt>
              <dd className="text-ink">{user.phone ?? '—'}</dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="text-ink-muted">Status</dt>
              <dd>
                {user.is_blocked ? (
                  <Pill tone="danger">Blocked</Pill>
                ) : (
                  <Pill tone="live">Active</Pill>
                )}
              </dd>
            </div>
          </dl>
        </Card>

        <Card>
          <p className="text-xs tracking-wide text-ink-muted uppercase">
            Orders
          </p>
          <p className="mt-2 text-2xl font-semibold text-ink">
            {user.total_orders}
          </p>
          <p className="mt-1 text-sm text-ink-muted">
            {user.delivered_orders} delivered · {user.rejected_orders} declined ·{' '}
            {user.cancelled_orders} cancelled
          </p>
          <p className="mt-2 text-sm text-ink">
            {inr(user.total_spend)} spent across delivered orders
          </p>
        </Card>
      </div>

      {detail && detail.restaurants.length > 0 && (
        <Card className="mt-3">
          <p className="text-xs tracking-wide text-ink-muted uppercase">
            Works at
          </p>
          <ul className="mt-2 space-y-1 text-sm text-ink">
            {detail.restaurants.map((r) => (
              <li key={r.restaurant_id}>
                {r.name ?? r.restaurant_id}{' '}
                <span className="text-ink-muted">· {r.role}</span>
              </li>
            ))}
          </ul>
        </Card>
      )}

      {detail && detail.addresses.length > 0 && (
        <Card className="mt-3">
          <p className="text-xs tracking-wide text-ink-muted uppercase">
            Saved addresses
          </p>
          <ul className="mt-2 space-y-2 text-sm">
            {detail.addresses.map((a) => (
              <li key={a.id}>
                <span className="font-medium text-ink">{a.label ?? 'Home'}</span>
                <span className="text-ink-muted">
                  {' '}
                  · {a.line1 ?? '—'}
                  {a.city ? `, ${a.city}` : ''}
                </span>
              </li>
            ))}
          </ul>
        </Card>
      )}

      {detail && detail.moderation.length > 0 && (
        <Card className="mt-3">
          <p className="text-xs tracking-wide text-ink-muted uppercase">
            Moderation history
          </p>
          <ul className="mt-2 space-y-2 text-sm">
            {detail.moderation.map((m) => (
              <li key={m.id}>
                <span
                  className={
                    m.action === 'block'
                      ? 'font-medium text-non-veg-ink'
                      : 'font-medium text-veg'
                  }
                >
                  {m.action === 'block' ? 'Blocked' : 'Unblocked'}
                </span>
                <span className="text-ink-muted">
                  {' '}
                  by {m.actor_email} · {when(m.created_at)}
                </span>
                {m.reason && <p className="text-ink-muted">“{m.reason}”</p>}
              </li>
            ))}
          </ul>
        </Card>
      )}

      <Card className="mt-3">
        <p className="text-xs tracking-wide text-ink-muted uppercase">
          Every order
        </p>
        {orders === null ? (
          <TableSkeleton rows={3} />
        ) : orders.length === 0 ? (
          <p className="mt-2 text-sm text-ink-muted">
            This person has never placed an order.
          </p>
        ) : (
          <ul className="mt-2 divide-y divide-line">
            {orders.map((o) => (
              <li key={o.id} className="py-3">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <span className="font-semibold text-ink">{o.id}</span>
                  <span className="text-ink">{inr(o.total)}</span>
                </div>
                <p className="text-xs text-ink-muted">
                  {o.restaurant_name ?? 'Unknown restaurant'} · {o.status} ·{' '}
                  {when(o.created_at)}
                  {o.payment_method ? ` · ${o.payment_method}` : ''}
                </p>
                {o.items.length > 0 && (
                  <p className="mt-1 text-xs text-ink-muted">
                    {o.items
                      .map((i) => `${i.quantity}× ${i.name}`)
                      .join(', ')}
                  </p>
                )}
                {o.delivery_to && (
                  <p className="text-xs text-ink-muted">To {o.delivery_to}</p>
                )}
              </li>
            ))}
          </ul>
        )}
      </Card>
    </Modal>
  )
}

/// Blocking asks for a reason before it asks for a confirmation.
///
/// The reason is optional to the database and required by the situation: the
/// ledger is read months later by somebody who was not in the room, and "no
/// reason given" is the entry that starts the argument.
function BlockDialog({
  user,
  busy,
  onConfirm,
  onCancel,
}: {
  user: UserRow
  busy: boolean
  onConfirm: (reason: string) => void
  onCancel: () => void
}) {
  const [reason, setReason] = useState('')
  const blocking = !user.is_blocked

  return (
    <Modal
      title={blocking ? 'Block this person?' : 'Let them back in?'}
      onClose={onCancel}
      busy={busy}
      size="sm"
      footer={
        <div className="flex justify-end gap-2">
          <Button variant="secondary" onClick={onCancel} disabled={busy}>
            Cancel
          </Button>
          <Button
            variant={blocking ? 'danger' : 'primary'}
            loading={busy}
            onClick={() => onConfirm(reason)}
          >
            {blocking ? 'Block' : 'Unblock'}
          </Button>
        </div>
      }
    >
      <p className="text-sm text-ink">
        {blocking ? (
          <>
            <span className="font-medium">
              {user.name ?? user.email ?? 'This person'}
            </span>{' '}
            will be signed out everywhere, will not be able to sign back in, and
            cannot place an order. Their past orders are untouched.
          </>
        ) : (
          <>
            <span className="font-medium">
              {user.name ?? user.email ?? 'This person'}
            </span>{' '}
            will be able to sign in and order again. The block stays in the
            record.
          </>
        )}
      </p>
      <Field
        label="Reason"
        className="mt-4"
        value={reason}
        onChange={(e) => setReason(e.target.value)}
        placeholder={
          blocking ? 'Repeated fake orders' : 'Appealed, evidence accepted'
        }
      />
      <p className="mt-2 text-xs text-ink-muted">
        Kept forever against this person, with your name on it.
      </p>
    </Modal>
  )
}

export function UsersPage() {
  const [users, setUsers] = useState<UserRow[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [filter, setFilter] = useState<Filter>('all')
  const [query, setQuery] = useState('')
  const [open, setOpen] = useState<UserRow | null>(null)
  const [confirming, setConfirming] = useState<UserRow | null>(null)
  const [busy, setBusy] = useState(false)

  const load = useCallback(() => {
    setError(null)
    api
      .listUsers()
      .then(setUsers)
      .catch((e: unknown) =>
        setError(e instanceof Error ? e.message : String(e)),
      )
  }, [])

  useEffect(load, [load])

  const rows = useMemo(() => {
    if (!users) return []
    const q = query.trim().toLowerCase()
    return users.filter((u) => {
      if (filter === 'blocked' ? !u.is_blocked : filter !== 'all' && u.role !== filter)
        return false
      if (!q) return true
      return (
        (u.email ?? '').toLowerCase().includes(q) ||
        (u.name ?? '').toLowerCase().includes(q) ||
        (u.phone ?? '').includes(q)
      )
    })
  }, [users, filter, query])

  async function applyBlock(reason: string) {
    if (!confirming) return
    const target = confirming
    setBusy(true)
    setError(null)
    try {
      await api.setUserBlocked(target.user_id, !target.is_blocked, reason)
      setNotice(
        target.is_blocked
          ? `${target.email ?? 'They'} can sign in again.`
          : `${target.email ?? 'They'} are blocked and signed out.`,
      )
      setConfirming(null)
      setOpen(null)
      load()
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  const blockedCount = users?.filter((u) => u.is_blocked).length ?? 0

  return (
    <>
      <PageHeader
        title="People"
        subtitle={
          users
            ? `${users.length} on the platform${
                blockedCount > 0 ? ` · ${blockedCount} blocked` : ''
              }`
            : undefined
        }
        action={
          <Button variant="secondary" onClick={load}>
            Refresh
          </Button>
        }
      />

      <PageBody>
        {error && (
          <Banner tone="error" onDismiss={() => setError(null)}>
            {error}
          </Banner>
        )}
        {notice && (
          <Banner tone="success" onDismiss={() => setNotice(null)}>
            {notice}
          </Banner>
        )}

        <div className="mb-4 flex flex-wrap items-center gap-3">
          <SegmentedControl<Filter>
            label="Filter people"
            value={filter}
            onChange={setFilter}
            options={[
              { value: 'all', label: 'Everyone' },
              { value: 'customer', label: 'Customers' },
              { value: 'vendor', label: 'Restaurants' },
              { value: 'rider', label: 'Riders' },
              { value: 'admin', label: 'Admins' },
              { value: 'blocked', label: 'Blocked' },
            ]}
          />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search name, email or phone"
            aria-label="Search people"
            className="min-w-[220px] flex-1 rounded-field border border-line px-3 py-1.5 text-sm"
          />
        </div>

        {users === null ? (
          <TableSkeleton rows={6} />
        ) : rows.length === 0 ? (
          <EmptyState
            title="Nobody here"
            body={
              query || filter !== 'all'
                ? 'No one matches that filter.'
                : 'Nobody has signed in yet.'
            }
          />
        ) : (
          <DataTable label="People" minWidth={900}>
            <thead>
              <tr>
                <Th>Person</Th>
                <Th>Role</Th>
                <Th>Orders</Th>
                <Th align="right">Spent</Th>
                <Th>Last seen</Th>
                <Th hideLabel>Actions</Th>
              </tr>
            </thead>
            <tbody>
              {rows.map((u) => (
                <tr key={u.user_id}>
                  <Td>
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="font-semibold text-ink">
                        {u.name ?? u.email ?? 'Unnamed'}
                      </span>
                      {u.is_blocked && <Pill tone="danger">Blocked</Pill>}
                    </div>
                    <p className="mt-1 text-xs text-ink-muted">
                      {u.email ?? '—'}
                      {u.phone ? ` · ${u.phone}` : ''}
                    </p>
                  </Td>
                  <Td>
                    <Pill tone={roleTone[u.role]}>{roleLabel[u.role]}</Pill>
                  </Td>
                  <Td className="text-xs">
                    <Counts user={u} />
                  </Td>
                  <Td align="right" className="text-ink">
                    {u.total_spend > 0 ? `${inr(u.total_spend)}` : '—'}
                  </Td>
                  <Td className="text-xs text-ink-muted">
                    {when(u.last_sign_in_at)}
                  </Td>
                  <Td align="right">
                    <Button variant="secondary" onClick={() => setOpen(u)}>
                      Open
                    </Button>
                  </Td>
                </tr>
              ))}
            </tbody>
          </DataTable>
        )}
      </PageBody>

      {open && (
        <UserSheet
          user={open}
          onClose={() => setOpen(null)}
          // The sheet closes as the confirmation opens. Both are `Modal`s, and
          // two of those on screen at once each register a key handler on
          // `document` and each run a focus trap: one Escape closed both, and
          // Tab landed wherever the second trap happened to run. `applyBlock`
          // closes the sheet on success anyway, so this only changes where
          // Cancel lands — the table rather than the sheet, which is refetched
          // whenever it is reopened.
          onBlockToggle={(u) => {
            setConfirming(u)
            setOpen(null)
          }}
        />
      )}

      {confirming && (
        <BlockDialog
          user={confirming}
          busy={busy}
          onConfirm={applyBlock}
          onCancel={() => setConfirming(null)}
        />
      )}
    </>
  )
}
