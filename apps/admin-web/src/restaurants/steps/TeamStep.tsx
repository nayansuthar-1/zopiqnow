import { useState } from 'react'
import { api } from '../../lib/api'
import type { RestaurantDetail } from '../../lib/api'
import { Button, Field } from '../../ui/primitives'
import { StepFrame } from './StepFrame'

/// The step that turns a database row into a business someone can run.
///
/// Access to the vendor app is granted to an **email address**, not to a user
/// account — the grant is made before the person has ever signed in, and what they
/// prove by receiving an OTP is that they control the address. That is why this
/// step asks for an email and nothing else: there is no password to set and no
/// account to create.
///
/// The first owner has to be added from here. `add_restaurant_staff` (0024) works
/// out which restaurant the caller belongs to from their own staff row, so a
/// restaurant with nobody on it has nobody who can give it anybody.

export function TeamStep({
  id,
  detail,
  onSaved,
  onNext,
}: {
  id: string
  detail: RestaurantDetail | null
  onSaved: () => Promise<void>
  onNext: () => void
}) {
  const staff = detail?.staff ?? []
  const [email, setEmail] = useState('')
  const [role, setRole] = useState<'owner' | 'staff'>('owner')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function run(action: () => Promise<void>) {
    setBusy(true)
    setError(null)
    try {
      await action()
      await onSaved()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  const hasOwner = staff.some((s) => s.role === 'owner')

  return (
    <StepFrame
      title="Team"
      description="Who can sign in to the Zopiqnow Partner app and run this kitchen."
      error={error}
      busy={busy}
      saveLabel="Continue"
      onSave={onNext}
    >
      {staff.length > 0 ? (
        <div className="divide-y divide-line rounded-[8px] border border-line">
          {staff.map((s) => (
            <div key={s.email} className="flex flex-wrap items-center gap-3 px-4 py-3">
              <span className="flex-1 text-sm text-ink">{s.email}</span>
              <select
                value={s.role}
                disabled={busy}
                onChange={(e) =>
                  void run(() =>
                    api.setStaffRole(id, s.email, e.target.value as 'owner' | 'staff'),
                  )
                }
                className="h-9 rounded-[8px] border border-line bg-white px-2 text-sm outline-none focus:border-brand"
              >
                <option value="owner">Owner</option>
                <option value="staff">Staff</option>
              </select>
              <button
                type="button"
                disabled={busy}
                onClick={() => void run(() => api.removeStaff(id, s.email))}
                className="text-sm font-medium text-ink-muted hover:text-non-veg"
              >
                Remove
              </button>
            </div>
          ))}
        </div>
      ) : (
        <p className="rounded-[8px] bg-canvas px-4 py-3 text-sm text-ink-muted">
          Nobody can run this kitchen yet. Add the owner&apos;s email below.
        </p>
      )}

      <div className="rounded-[8px] border border-line p-4">
        <div className="grid gap-3 sm:grid-cols-[1fr_auto_auto] sm:items-end">
          <Field
            label="Email address"
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="owner@restaurant.com"
          />
          <label className="block">
            <span className="mb-1.5 block text-sm font-medium text-ink">Role</span>
            <select
              value={role}
              onChange={(e) => setRole(e.target.value as 'owner' | 'staff')}
              className="h-11 rounded-[8px] border border-line bg-white px-3 text-sm outline-none focus:border-brand"
            >
              <option value="owner">Owner</option>
              <option value="staff">Staff</option>
            </select>
          </label>
          <Button
            type="button"
            variant="secondary"
            disabled={busy || !email.trim()}
            onClick={() =>
              void run(async () => {
                await api.addStaff(id, email, role)
                setEmail('')
              })
            }
          >
            Add
          </Button>
        </div>
        <p className="mt-3 text-sm text-ink-muted">
          An owner sees earnings and can manage their own team. Staff see the order
          queue and the menu, and not the money.
        </p>
      </div>

      {!hasOwner && (
        <p className="rounded-[8px] bg-warn-soft px-4 py-3 text-sm text-warn">
          Publishing is blocked until there is at least one owner.
        </p>
      )}
    </StepFrame>
  )
}
