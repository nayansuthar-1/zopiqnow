import { useCallback, useEffect, useState } from 'react'
import { api } from '../lib/api'
import type { RiderRow, Vehicle } from '../lib/api'
import { PageHeader } from '../ui/AppShell'
import { Button, ConfirmDialog, Field } from '../ui/primitives'

/// The delivery fleet.
///
/// Riders belong to Zopiqnow, not to a restaurant — there is no restaurant
/// picker on this screen and there is not meant to be. A rider carries orders
/// from any kitchen, which is why this page sits beside Restaurants rather than
/// inside one.
///
/// Until now the only way onto the fleet was a seed file. That was honest for the
/// first rider and untenable by the tenth.

const vehicles: Vehicle[] = ['bike', 'scooter', 'bicycle']

/// Adding and editing are the same four fields, so they are the same form. The
/// only difference is that an existing rider's email is fixed: it is the primary
/// key and the address they sign in with.
function RiderForm({
  editing,
  busy,
  onSubmit,
  onCancel,
}: {
  editing: RiderRow | null
  busy: boolean
  onSubmit: (r: {
    email: string
    name: string
    phone: string
    vehicle: Vehicle
  }) => void
  onCancel: () => void
}) {
  const [email, setEmail] = useState(editing?.email ?? '')
  const [name, setName] = useState(editing?.name ?? '')
  const [phone, setPhone] = useState(editing?.phone ?? '')
  const [vehicle, setVehicle] = useState<Vehicle>(editing?.vehicle ?? 'bike')

  return (
    <form
      className="mt-5 rounded-[8px] border border-line p-4"
      onSubmit={(e) => {
        e.preventDefault()
        onSubmit({ email, name, phone, vehicle })
      }}
    >
      <div className="grid gap-3 sm:grid-cols-2">
        <Field
          label="Name"
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="Ravi Kumar"
        />
        <Field
          label="Phone"
          value={phone}
          onChange={(e) => setPhone(e.target.value)}
          placeholder="9876500011"
          hint="The number a customer rings when their food is late."
        />
        {editing ? (
          <div>
            <span className="mb-1.5 block text-sm font-medium text-ink">Email</span>
            <p className="flex h-11 items-center rounded-[8px] border border-line bg-canvas px-3 text-sm text-ink-muted">
              {editing.email}
            </p>
            <span className="mt-1.5 block text-sm text-ink-muted">
              Can't be changed — it is how they sign in, and every delivery they
              have made hangs off it.
            </span>
          </div>
        ) : (
          <Field
            label="Email"
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="ravi@example.com"
            hint="They sign in to the rider app with a code sent here."
          />
        )}
        <label className="block">
          <span className="mb-1.5 block text-sm font-medium text-ink">Vehicle</span>
          <select
            className="h-11 w-full rounded-[8px] border border-line bg-white px-3 text-sm text-ink outline-none focus:border-brand"
            value={vehicle}
            onChange={(e) => setVehicle(e.target.value as Vehicle)}
          >
            {vehicles.map((v) => (
              <option key={v} value={v}>
                {v[0].toUpperCase() + v.slice(1)}
              </option>
            ))}
          </select>
        </label>
      </div>

      <div className="mt-4 flex gap-2">
        <Button type="submit" loading={busy}>
          {editing ? 'Save changes' : 'Add rider'}
        </Button>
        <Button type="button" variant="ghost" onClick={onCancel} disabled={busy}>
          Cancel
        </Button>
      </div>
    </form>
  )
}

export function RidersPage() {
  const [riders, setRiders] = useState<RiderRow[] | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [adding, setAdding] = useState(false)
  const [editing, setEditing] = useState<RiderRow | null>(null)
  const [deactivating, setDeactivating] = useState<RiderRow | null>(null)
  const [banking, setBanking] = useState<RiderRow | null>(null)

  const load = useCallback(async () => {
    try {
      setRiders(await api.listRiders())
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  async function run(action: () => Promise<unknown>) {
    setBusy(true)
    setError(null)
    try {
      await action()
      await load()
      return true
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
      return false
    } finally {
      setBusy(false)
    }
  }

  const active = riders?.filter((r) => r.is_active) ?? []

  return (
    <>
      <PageHeader
        title="Riders"
        subtitle="The delivery fleet. A rider carries orders from any kitchen."
        action={
          !adding && !editing ? (
            <Button onClick={() => setAdding(true)}>Add rider</Button>
          ) : undefined
        }
      />

      <div className="max-w-3xl p-6">
        {error && (
          <p className="mb-4 rounded-[8px] bg-non-veg-soft px-4 py-3 text-sm text-non-veg">
            {error}
          </p>
        )}

        <div className="rounded-[12px] border border-line bg-white p-6">
          <h2 className="text-base font-bold text-ink">Delivery partners</h2>
          <p className="mt-1 text-sm text-ink-muted">
            {riders === null
              ? 'Loading…'
              : `${active.length} active of ${riders.length}. Only active riders are offered jobs.`}
          </p>

          {adding && (
            <RiderForm
              editing={null}
              busy={busy}
              onCancel={() => setAdding(false)}
              onSubmit={(r) =>
                void run(() =>
                  api.addRider(r.email, r.name, r.phone, r.vehicle),
                ).then((ok) => ok && setAdding(false))
              }
            />
          )}

          {editing && (
            <RiderForm
              editing={editing}
              busy={busy}
              onCancel={() => setEditing(null)}
              onSubmit={(r) =>
                void run(() =>
                  api.updateRider(editing.email, r.name, r.phone, r.vehicle),
                ).then((ok) => ok && setEditing(null))
              }
            />
          )}

          {riders !== null && riders.length === 0 && !adding && (
            <p className="mt-5 text-sm text-ink-muted">
              Nobody on the fleet yet. Restaurants can still deliver with their
              own staff — the vendor's own "Hand to rider" button is unaffected.
            </p>
          )}

          {riders !== null && riders.length > 0 && (
            <div className="mt-5 divide-y divide-line rounded-[8px] border border-line">
              {riders.map((r) => (
                <div key={r.email} className="flex flex-wrap items-center gap-3 px-4 py-3">
                  <div className="min-w-0 flex-1">
                    <p className="text-sm font-medium text-ink">
                      {r.name}
                      {!r.is_active && (
                        <span className="ml-2 rounded-full bg-canvas px-2 py-0.5 text-xs font-medium text-ink-muted">
                          inactive
                        </span>
                      )}
                      {r.live_order_id && (
                        <span className="ml-2 rounded-full bg-brand-soft px-2 py-0.5 text-xs font-medium text-brand-deep">
                          carrying {r.live_order_id}
                        </span>
                      )}
                    </p>
                    <p className="truncate text-sm text-ink-muted">
                      {r.email} · {r.phone} · {r.vehicle} · {r.delivered_count}{' '}
                      delivered
                    </p>
                  </div>

                  <button
                    type="button"
                    disabled={busy}
                    onClick={() => {
                      setAdding(false)
                      setEditing(r)
                    }}
                    className="text-sm font-medium text-ink-muted hover:text-ink disabled:opacity-40"
                  >
                    Edit
                  </button>

                  <button
                    type="button"
                    disabled={busy}
                    onClick={() => setBanking(r)}
                    className="text-sm font-medium text-ink-muted hover:text-ink disabled:opacity-40"
                  >
                    Bank
                  </button>

                  {r.is_active ? (
                    <button
                      type="button"
                      // Greyed out *and* explained. The database refuses this
                      // anyway — the point of doing it here too is that a
                      // disabled button with a reason beats an error after a
                      // click for something ops must never do by accident.
                      disabled={busy || r.live_order_id !== null}
                      onClick={() => setDeactivating(r)}
                      title={
                        r.live_order_id
                          ? `They are carrying ${r.live_order_id}. They must drop it in the rider app first.`
                          : undefined
                      }
                      className="text-sm font-medium text-ink-muted hover:text-non-veg disabled:opacity-40 disabled:hover:text-ink-muted"
                    >
                      Deactivate
                    </button>
                  ) : (
                    <button
                      type="button"
                      disabled={busy}
                      onClick={() =>
                        void run(() => api.setRiderActive(r.email, true))
                      }
                      className="text-sm font-medium text-brand hover:text-brand-deep disabled:opacity-40"
                    >
                      Reactivate
                    </button>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      {banking && (
        <BankDialog rider={banking} onClose={() => setBanking(null)} />
      )}

      {deactivating && (
        <ConfirmDialog
          title={`Deactivate ${deactivating.name}?`}
          body="They stop being offered new jobs immediately and cannot use the rider app. Their delivery history is kept, and you can switch them back on at any time."
          confirmLabel="Deactivate"
          busy={busy}
          onCancel={() => setDeactivating(null)}
          onConfirm={() =>
            void run(() => api.setRiderActive(deactivating.email, false)).then(
              (ok) => ok && setDeactivating(null),
            )
          }
        />
      )}
    </>
  )
}

/// Where a rider's pay is sent.
///
/// Entered here and never by the rider, which is the whole reason this dialog
/// exists rather than a screen in the rider app: a rider who can write their own
/// payout destination is the entire fraud surface of a payout system in one form
/// field. Same rule 0009 set for restaurant onboarding and 0040 reaffirmed for
/// this roster.
///
/// Saving a different account clears `verified` in the database — whoever checked
/// the old one against a document did not check this one.
function BankDialog({ rider, onClose }: { rider: RiderRow; onClose: () => void }) {
  const [holder, setHolder] = useState('')
  const [account, setAccount] = useState('')
  const [ifsc, setIfsc] = useState('')
  const [bank, setBank] = useState('')
  const [loaded, setLoaded] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let alive = true
    void api
      .getRiderBank(rider.email)
      .then((rows) => {
        if (!alive) return
        const b = rows[0]
        if (b) {
          setHolder(b.account_holder ?? '')
          setAccount(b.account_number ?? '')
          setIfsc(b.ifsc ?? '')
          setBank(b.bank_name ?? '')
        }
        setLoaded(true)
      })
      .catch((e: unknown) => {
        if (alive) setError(e instanceof Error ? e.message : String(e))
      })
    return () => {
      alive = false
    }
  }, [rider.email])

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-ink/40 p-4">
      <div className="w-full max-w-md rounded-[12px] bg-white p-6">
        <h2 className="text-base font-bold text-ink">Bank details · {rider.name}</h2>
        <p className="mt-1 text-sm text-ink-muted">
          Where their weekly payout is sent. The rider never sees or edits this.
        </p>

        {error && (
          <p className="mt-4 rounded-[8px] bg-non-veg-soft px-4 py-3 text-sm text-non-veg">
            {error}
          </p>
        )}

        {!loaded ? (
          <p className="mt-5 text-sm text-ink-muted">Loading…</p>
        ) : (
          <form
            className="mt-5 grid gap-4"
            onSubmit={(e) => {
              e.preventDefault()
              setBusy(true)
              setError(null)
              void api
                .setRiderBank(rider.email, {
                  account_holder: holder,
                  account_number: account,
                  ifsc,
                  bank_name: bank,
                })
                .then(onClose)
                .catch((err: unknown) =>
                  setError(err instanceof Error ? err.message : String(err)),
                )
                .finally(() => setBusy(false))
            }}
          >
            <Field
              label="Account holder"
              value={holder}
              onChange={(e) => setHolder(e.target.value)}
              placeholder="As printed on the passbook"
            />
            <Field
              label="Account number"
              value={account}
              onChange={(e) => setAccount(e.target.value)}
              placeholder="123456789012"
              hint="9 to 18 digits."
            />
            <Field
              label="IFSC"
              value={ifsc}
              onChange={(e) => setIfsc(e.target.value)}
              placeholder="SBIN0001234"
              // Upper-cased server-side, so a rider's handwriting copied in
              // lower case is not an error worth showing anybody.
              hint="Eleven characters. Case does not matter."
            />
            <Field
              label="Bank name"
              value={bank}
              onChange={(e) => setBank(e.target.value)}
              placeholder="State Bank of India"
            />
            <div className="flex justify-end gap-2">
              <Button type="button" variant="ghost" onClick={onClose} disabled={busy}>
                Cancel
              </Button>
              <Button type="submit" disabled={busy}>
                Save
              </Button>
            </div>
          </form>
        )}
      </div>
    </div>
  )
}
