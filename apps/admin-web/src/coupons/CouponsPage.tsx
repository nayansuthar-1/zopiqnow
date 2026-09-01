import { useCallback, useEffect, useState } from 'react'
import { api, couponStateOf } from '../lib/api'
import type { CouponRow, CouponState } from '../lib/api'
import { endOfDayLocal, toDateInput } from '../lib/dates'
import { PageHeader } from '../ui/AppShell'
import {
  Banner,
  Button,
  ConfirmDialog,
  EmptyState,
  Field,
  Modal,
  Pill,
  SegmentedControl,
  TableSkeleton,
} from '../ui/primitives'

/// Platform coupons — the `restaurant_id is null` ones that work at any
/// restaurant. They have existed since migration 0003 and have only ever been
/// put there by a seed file.
///
/// A restaurant's own offers are listed here too, and are read-only from this
/// side but for one lever: they can be switched **off**. That is the abuse case
/// ops actually has — a kitchen running a code it cannot afford — and stopping
/// short of switching one back *on* keeps 0064's rule intact, which is that an
/// offer belongs to whoever is paying for it.

const stateLabels: Record<CouponState, string> = {
  live: 'Live',
  off: 'Switched off',
  expired: 'Expired',
}

const stateTones: Record<CouponState, 'live' | 'neutral' | 'danger'> = {
  live: 'live',
  off: 'neutral',
  expired: 'danger',
}

/// What the code is worth, in the words the customer's cart uses.
function worth(c: CouponRow) {
  const off =
    c.flat_off !== null ? `₹${c.flat_off} off` : `${c.percent_off}% off up to ₹${c.max_off}`
  return c.min_subtotal > 0 ? `${off} over ₹${c.min_subtotal}` : off
}

type Draft = {
  code: string
  min_subtotal: string
  kind: 'flat' | 'percent'
  flat_off: string
  percent_off: string
  max_off: string
  valid_until: string
  /// Blank means "no limit" for the three numeric caps. `max_per_user` is the
  /// exception that is pre-filled: 1 is the answer a campaign wants almost
  /// always, and it is the one the database defaults to, so the form should not
  /// let it be set by accident either way.
  max_redemptions: string
  max_per_user: string
  budget: string
  first_order_only: boolean
  is_public: boolean
}

const blank: Draft = {
  code: '',
  min_subtotal: '0',
  kind: 'flat',
  flat_off: '',
  percent_off: '',
  max_off: '',
  valid_until: '',
  max_redemptions: '',
  max_per_user: '1',
  budget: '',
  first_order_only: false,
  is_public: true,
}

export function CouponsPage() {
  const [rows, setRows] = useState<CouponRow[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [draft, setDraft] = useState<Draft | null>(null)
  const [deleting, setDeleting] = useState<CouponRow | null>(null)

  const load = useCallback(async () => {
    try {
      setRows(await api.listCoupons())
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  async function save() {
    if (!draft) return
    setBusy(true)
    setError(null)
    try {
      await api.saveCoupon({
        code: draft.code,
        min_subtotal: Number(draft.min_subtotal || 0),
        // A percentage coupon sends no flat amount and a flat one sends no
        // percentage — the XOR the table has enforced since 0003. Sending both
        // and letting the server pick would make the form the second place the
        // rule lives.
        flat_off: draft.kind === 'flat' ? Number(draft.flat_off || 0) : null,
        percent_off: draft.kind === 'percent' ? Number(draft.percent_off || 0) : null,
        max_off: draft.kind === 'percent' ? Number(draft.max_off || 0) : null,
        // A date input hands back a bare "2026-09-30", which ECMAScript reads
        // as UTC midnight — half past five on the morning of the 30th, here.
        // The day an admin picks as the last day is a day the code still works
        // on, so it is that day's last second in the timezone it was picked in.
        valid_until: draft.valid_until
          ? endOfDayLocal(draft.valid_until).toISOString()
          : null,
        // Blank is a deliberate "no limit", not a zero — the RPC refuses 0 and
        // the column reads null as unbounded, so an empty field has to arrive
        // as null rather than as Number('') === 0.
        max_redemptions: draft.max_redemptions ? Number(draft.max_redemptions) : null,
        max_per_user: draft.max_per_user ? Number(draft.max_per_user) : null,
        budget: draft.budget ? Number(draft.budget) : null,
        first_order_only: draft.first_order_only,
        is_public: draft.is_public,
      })
      setDraft(null)
      await load()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  async function toggle(c: CouponRow) {
    setError(null)
    try {
      await api.setCouponActive(c.code, !c.is_active)
      await load()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }

  async function remove() {
    if (!deleting) return
    setBusy(true)
    setError(null)
    try {
      await api.deleteCoupon(deleting.code)
      setDeleting(null)
      await load()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
      setDeleting(null)
    } finally {
      setBusy(false)
    }
  }

  const platform = (rows ?? []).filter((c) => c.restaurant_id === null)
  const vendor = (rows ?? []).filter((c) => c.restaurant_id !== null)

  return (
    <>
      <PageHeader
        title="Coupons"
        subtitle={
          rows
            ? `${platform.length} platform code${platform.length === 1 ? '' : 's'} · ${vendor.length} run by restaurants`
            : 'Codes that work at any restaurant.'
        }
        action={<Button onClick={() => setDraft(blank)}>New coupon</Button>}
      />

      <div className="space-y-8 p-6">
        {error && (
          <Banner tone="error" className="max-w-2xl" onDismiss={() => setError(null)}>
            {error}
          </Banner>
        )}

        {rows === null ? (
          <TableSkeleton />
        ) : (
          <>
            <Table
              title="Platform codes"
              caption="Yours to write, edit and switch off. They apply at every restaurant, and the platform absorbs the discount."
              rows={platform}
              empty={{
                title: 'No platform coupon yet',
                body: 'A platform code works at every restaurant and the platform absorbs the discount. Add one to get started.',
              }}
              onEdit={(c) =>
                setDraft({
                  code: c.code,
                  min_subtotal: String(c.min_subtotal),
                  kind: c.flat_off !== null ? 'flat' : 'percent',
                  flat_off: c.flat_off === null ? '' : String(c.flat_off),
                  percent_off: c.percent_off === null ? '' : String(c.percent_off),
                  max_off: c.max_off === null ? '' : String(c.max_off),
                  // Read off the local calendar rather than sliced out of
                  // the ISO string: an instant in the small hours here is still
                  // the previous day in UTC, so slicing reloads a coupon as
                  // ending the day before the one it was given.
                  valid_until: c.valid_until
                    ? toDateInput(new Date(c.valid_until))
                    : '',
                  // Null is "no limit" in the column and blank is how the form
                  // says it, so the two map onto each other directly. Editing a
                  // coupon without these would silently reset every cap 0075
                  // added, because the save sends the whole draft.
                  max_redemptions:
                    c.max_redemptions === null ? '' : String(c.max_redemptions),
                  max_per_user:
                    c.max_per_user === null ? '' : String(c.max_per_user),
                  budget: c.budget === null ? '' : String(c.budget),
                  first_order_only: c.first_order_only,
                  is_public: c.is_public,
                })
              }
              onToggle={toggle}
              onDelete={setDeleting}
            />

            <Table
              title="Restaurant offers"
              caption="Run by the kitchens themselves (migration 0064). Here so an unexpected discount on an order has an explanation. They can be switched off from here and only switched back on by their owner."
              rows={vendor}
              empty={{
                title: 'No restaurant is running an offer',
                body: 'Kitchens create these themselves from their own Offers screen. Any that exist show up here.',
              }}
              onToggle={toggle}
            />
          </>
        )}
      </div>

      {draft && (
        <Modal
          busy={busy}
          onClose={() => setDraft(null)}
          title={
            rows?.some((c) => c.code === draft.code.toUpperCase())
              ? draft.code.toUpperCase()
              : 'New coupon'
          }
          footer={
            <>
              <Button
                variant="secondary"
                onClick={() => setDraft(null)}
                disabled={busy}
              >
                Cancel
              </Button>
              <Button onClick={() => void save()} loading={busy}>
                Save
              </Button>
            </>
          }
        >
          <div className="space-y-4">
              <Field
                label="Code"
                value={draft.code}
                onChange={(e) => setDraft({ ...draft, code: e.target.value })}
                placeholder="WELCOME50"
                hint="3–16 letters, numbers or hyphens. Upper-cased, and what a customer types at checkout."
              />

              <div>
                <span className="mb-1.5 block text-sm font-medium text-ink">
                  Discount
                </span>
                <SegmentedControl
                  label="Discount kind"
                  value={draft.kind}
                  onChange={(kind) => setDraft({ ...draft, kind })}
                  options={[
                    { value: 'flat', label: 'Flat amount' },
                    { value: 'percent', label: 'Percentage' },
                  ]}
                />
              </div>

              {draft.kind === 'flat' ? (
                <Field
                  label="Amount off (₹)"
                  type="number"
                  value={draft.flat_off}
                  onChange={(e) => setDraft({ ...draft, flat_off: e.target.value })}
                  placeholder="50"
                />
              ) : (
                <div className="grid grid-cols-2 gap-3">
                  <Field
                    label="Percent off"
                    type="number"
                    value={draft.percent_off}
                    onChange={(e) =>
                      setDraft({ ...draft, percent_off: e.target.value })
                    }
                    placeholder="20"
                  />
                  <Field
                    label="Capped at (₹)"
                    type="number"
                    value={draft.max_off}
                    onChange={(e) => setDraft({ ...draft, max_off: e.target.value })}
                    placeholder="120"
                    hint="A percentage with no cap is an open cheque."
                  />
                </div>
              )}

              <Field
                label="Minimum order (₹)"
                type="number"
                value={draft.min_subtotal}
                onChange={(e) =>
                  setDraft({ ...draft, min_subtotal: e.target.value })
                }
                hint="Checked against the subtotal, before tax and delivery."
              />

              <Field
                label="Runs until"
                type="date"
                value={draft.valid_until}
                onChange={(e) =>
                  setDraft({ ...draft, valid_until: e.target.value })
                }
                hint="The code works all of that day. Leave empty for no end date."
              />

              {/* The caps (0075). Grouped and separated from the pricing above,
                  because these are the questions about how far a campaign may
                  run rather than what it is worth — and because the whole
                  finding was that there was no answer to them at all. */}
              <div className="col-span-full mt-2 border-t border-line pt-4 text-xs font-medium tracking-wide text-ink-muted uppercase">
                Limits
              </div>

              <Field
                label="Per customer"
                type="number"
                value={draft.max_per_user}
                onChange={(e) =>
                  setDraft({ ...draft, max_per_user: e.target.value })
                }
                hint="How many times one person may use it. Empty means no limit."
              />

              <Field
                label="Total redemptions"
                type="number"
                value={draft.max_redemptions}
                onChange={(e) =>
                  setDraft({ ...draft, max_redemptions: e.target.value })
                }
                hint="Across everybody. Empty means no limit."
              />

              <Field
                label="Budget (₹)"
                type="number"
                value={draft.budget}
                onChange={(e) => setDraft({ ...draft, budget: e.target.value })}
                hint="Total discount this code may give away before it stops. Empty means no ceiling."
              />

              <label className="flex items-start gap-2 text-sm text-ink">
                <input
                  type="checkbox"
                  className="mt-1"
                  checked={draft.first_order_only}
                  onChange={(e) =>
                    setDraft({ ...draft, first_order_only: e.target.checked })
                  }
                />
                <span>
                  First order only
                  <span className="block text-xs text-ink-muted">
                    Refused for anyone who has ordered before.
                  </span>
                </span>
              </label>

              <label className="flex items-start gap-2 text-sm text-ink">
                <input
                  type="checkbox"
                  className="mt-1"
                  checked={draft.is_public}
                  onChange={(e) =>
                    setDraft({ ...draft, is_public: e.target.checked })
                  }
                />
                <span>
                  Listed publicly
                  <span className="block text-xs text-ink-muted">
                    Uncheck for a targeted or win-back code. It still works when
                    typed — it just stops being readable by everyone.
                  </span>
                </span>
              </label>
          </div>
        </Modal>
      )}

      {deleting && (
        <ConfirmDialog
          title={`Delete ${deleting.code}?`}
          body="This removes the code entirely. It only works for a code no order has ever carried — anything redeemed is part of somebody's bill and can only be switched off."
          confirmLabel="Delete"
          tone="danger"
          busy={busy}
          onConfirm={() => void remove()}
          onCancel={() => setDeleting(null)}
        />
      )}
    </>
  )
}

function Table({
  title,
  caption,
  rows,
  empty,
  onEdit,
  onToggle,
  onDelete,
}: {
  title: string
  caption: string
  rows: CouponRow[]
  empty: { title: string; body: string }
  onEdit?: (c: CouponRow) => void
  onToggle: (c: CouponRow) => void
  onDelete?: (c: CouponRow) => void
}) {
  return (
    <section>
      <h2 className="text-base font-bold text-ink">{title}</h2>
      <p className="mt-0.5 mb-3 max-w-2xl text-sm text-ink-muted">{caption}</p>

      {rows.length === 0 ? (
        <EmptyState title={empty.title} body={empty.body} />
      ) : (
        <div className="overflow-x-auto rounded-[12px] border border-line bg-white">
          <table className="w-full min-w-[820px] text-sm">
            <thead className="border-b border-line text-left text-ink-muted">
              <tr>
                <th className="px-5 py-3 font-medium">Code</th>
                <th className="px-5 py-3 font-medium">Worth</th>
                <th className="px-5 py-3 text-right font-medium">Redeemed</th>
                <th className="px-5 py-3 text-right font-medium">Given away</th>
                <th className="px-5 py-3 font-medium">Until</th>
                <th className="px-5 py-3 font-medium">Status</th>
                <th className="px-5 py-3" />
              </tr>
            </thead>
            <tbody className="divide-y divide-line">
              {rows.map((c) => {
                const state = couponStateOf(c)
                return (
                  <tr key={c.code}>
                    <td className="px-5 py-3">
                      <p className="font-semibold text-ink">{c.code}</p>
                      {c.restaurant_name && (
                        <p className="text-ink-muted">{c.restaurant_name}</p>
                      )}
                    </td>
                    <td className="px-5 py-3 text-ink-muted">{worth(c)}</td>
                    <td className="px-5 py-3 text-right tabular-nums text-ink-muted">
                      {c.redeemed}
                    </td>
                    <td className="px-5 py-3 text-right tabular-nums text-ink">
                      ₹{c.discount_given}
                    </td>
                    <td className="px-5 py-3 text-ink-muted">
                      {c.valid_until
                        ? new Date(c.valid_until).toLocaleDateString('en-IN', {
                            day: 'numeric',
                            month: 'short',
                          })
                        : 'no end date'}
                    </td>
                    <td className="px-5 py-3">
                      <Pill tone={stateTones[state]}>{stateLabels[state]}</Pill>
                    </td>
                    <td className="px-5 py-3">
                      <div className="flex justify-end gap-2">
                        {onEdit && (
                          <Button
                            variant="ghost"
                            size="sm"
                            onClick={() => onEdit(c)}
                          >
                            Edit
                          </Button>
                        )}
                        {/* A vendor's code shows only the one lever it has. */}
                        {(c.restaurant_id === null || c.is_active) && (
                          <Button
                            variant="secondary"
                            size="sm"
                            onClick={() => onToggle(c)}
                          >
                            {c.is_active ? 'Switch off' : 'Switch on'}
                          </Button>
                        )}
                        {onDelete && c.redeemed === 0 && (
                          <Button
                            variant="ghost"
                            size="sm"
                            onClick={() => onDelete(c)}
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
    </section>
  )
}
