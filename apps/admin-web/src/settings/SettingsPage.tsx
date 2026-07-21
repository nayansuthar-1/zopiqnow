import { useCallback, useEffect, useState } from 'react'
import { api } from '../lib/api'
import type { AdminRow } from '../lib/api'
import { useSession } from '../auth/session'
import { PageHeader } from '../ui/AppShell'
import { Button, ConfirmDialog, Field } from '../ui/primitives'

/// Who else can run the platform.
///
/// This is a short list with long consequences: everyone on it can create a
/// restaurant, publish it, read every licence number and bank account on the
/// platform, and add more people to this list. There is no lesser admin role and
/// deliberately so — a half-privileged admin who can see bank details but not edit
/// them is a distinction that sounds useful and protects nothing.

export function SettingsPage() {
  const { email: mine } = useSession()
  const [admins, setAdmins] = useState<AdminRow[] | null>(null)
  const [email, setEmail] = useState('')
  const [name, setName] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [removing, setRemoving] = useState<AdminRow | null>(null)

  const load = useCallback(async () => {
    try {
      setAdmins(await api.listAdmins())
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

  return (
    <>
      <PageHeader
        title="Settings"
        subtitle="Who can sign in to this console."
      />

      <div className="max-w-2xl p-6">
        {error && (
          <p className="mb-4 rounded-[8px] bg-non-veg-soft px-4 py-3 text-sm text-non-veg">
            {error}
          </p>
        )}

        <div className="rounded-[12px] border border-line bg-white p-6">
          <h2 className="text-base font-bold text-ink">Platform admins</h2>
          <p className="mt-1 text-sm text-ink-muted">
            Everyone here can create and publish restaurants, and can see every
            licence and bank account on the platform.
          </p>

          {admins === null ? (
            <p className="mt-5 text-sm text-ink-muted">Loading…</p>
          ) : (
            <div className="mt-5 divide-y divide-line rounded-[8px] border border-line">
              {admins.map((a) => {
                const isMe = a.email === mine
                return (
                  <div key={a.email} className="flex flex-wrap items-center gap-3 px-4 py-3">
                    <div className="min-w-0 flex-1">
                      <p className="text-sm font-medium text-ink">
                        {a.name}
                        {isMe && <span className="ml-2 text-ink-muted">you</span>}
                      </p>
                      <p className="truncate text-sm text-ink-muted">{a.email}</p>
                    </div>
                    <button
                      type="button"
                      disabled={busy || isMe}
                      onClick={() => setRemoving(a)}
                      className="text-sm font-medium text-ink-muted hover:text-non-veg disabled:opacity-40 disabled:hover:text-ink-muted"
                      // Not just disabled — the reason, because a greyed-out
                      // button with no explanation reads as a bug.
                      title={isMe ? 'You cannot remove yourself.' : undefined}
                    >
                      Remove
                    </button>
                  </div>
                )
              })}
            </div>
          )}

          <form
            className="mt-5 grid gap-3 sm:grid-cols-[1fr_1fr_auto] sm:items-end"
            onSubmit={(e) => {
              e.preventDefault()
              void run(async () => {
                await api.addAdmin(email, name)
                setEmail('')
                setName('')
              })
            }}
          >
            <Field
              label="Name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Priya Shah"
            />
            <Field
              label="Email"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="priya@siteonlab.com"
            />
            <Button type="submit" variant="secondary" disabled={busy}>
              Add admin
            </Button>
          </form>
          <p className="mt-3 text-sm text-ink-muted">
            They sign in with a code sent to that address — there is no password to
            set, and no account to create first.
          </p>
        </div>
      </div>

      {removing && (
        <ConfirmDialog
          title={`Remove ${removing.name}?`}
          body={`${removing.email} will lose access to this console immediately. Restaurants they onboarded are unaffected.`}
          confirmLabel="Remove"
          busy={busy}
          onCancel={() => setRemoving(null)}
          onConfirm={() =>
            void run(() => api.removeAdmin(removing.email)).then(
              (ok) => ok && setRemoving(null),
            )
          }
        />
      )}
    </>
  )
}
