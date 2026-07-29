import { useCallback, useEffect, useState } from 'react'
import { api } from '../lib/api'
import type { Audience, BroadcastRow } from '../lib/api'
import { PageHeader } from '../ui/AppShell'
import { Button, Field } from '../ui/primitives'

/// One message to everybody in an audience.
///
/// There is no new delivery mechanism here. Migration 0047 built one path from a
/// `notifications` row to a phone, and a broadcast is that path walked many
/// times — one row per recipient, because an inbox belongs to a person and a
/// shared row would have no owner and no read receipt.
///
/// **This is the most public thing the console can do and it has no undo.** So
/// the reach is fetched and shown as a number *before* the send, the send needs
/// a second click against that number, and every one that goes out is listed
/// underneath with who sent it. The database refuses the same message twice
/// inside five minutes, which is the realistic accident — a double submit, or a
/// second admin who did not know about the first.

const audiences: { value: Audience; label: string; who: string }[] = [
  {
    value: 'customer',
    label: 'Customers',
    who: 'Everyone with the customer app installed and a device registered.',
  },
  {
    value: 'rider',
    label: 'Riders',
    who: 'Every active delivery partner. Deactivated riders are not sent to.',
  },
  {
    value: 'restaurant',
    label: 'Restaurants',
    who: 'Every live restaurant. The vendor tablet shows it in the inbox.',
  },
]

function when(iso: string) {
  return new Date(iso).toLocaleString('en-IN', {
    day: 'numeric',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  })
}

export function BroadcastPage() {
  const [audience, setAudience] = useState<Audience>('customer')
  const [title, setTitle] = useState('')
  const [body, setBody] = useState('')
  const [reach, setReach] = useState<number | null>(null)
  const [sent, setSent] = useState<BroadcastRow[] | null>(null)
  const [confirming, setConfirming] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [note, setNote] = useState<string | null>(null)

  const load = useCallback(async () => {
    try {
      setSent(await api.listBroadcasts())
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  // The number is fetched per audience rather than counted once, because it is
  // the thing the confirmation is *about*: "send to 1,240 customers" has to be
  // 1,240 as of now, not as of when the page loaded.
  useEffect(() => {
    let live = true
    setReach(null)
    api
      .broadcastReach(audience)
      .then((n) => {
        if (live) setReach(n)
      })
      .catch(() => {
        if (live) setReach(null)
      })
    return () => {
      live = false
    }
  }, [audience])

  async function send() {
    setBusy(true)
    setError(null)
    try {
      const n = await api.sendBroadcast(audience, title, body)
      setNote(`Sent to ${n} ${audience === 'restaurant' ? 'restaurants' : `${audience}s`}.`)
      setTitle('')
      setBody('')
      setConfirming(false)
      await load()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
      setConfirming(false)
    } finally {
      setBusy(false)
    }
  }

  const picked = audiences.find((a) => a.value === audience)!
  const ready = title.trim() !== '' && reach !== null && reach > 0

  return (
    <>
      <PageHeader
        title="Send a notification"
        subtitle="A push and an inbox entry, to everybody in one audience at once."
      />

      <div className="grid gap-6 p-6 lg:grid-cols-[minmax(0,26rem)_minmax(0,1fr)]">
        <div className="rounded-[12px] border border-line bg-white p-6">
          {error && (
            <p className="mb-4 rounded-[8px] bg-non-veg-soft px-4 py-3 text-sm text-non-veg">
              {error}
            </p>
          )}
          {note && (
            <p className="mb-4 rounded-[8px] bg-veg-soft px-4 py-3 text-sm text-veg">
              {note}
            </p>
          )}

          <span className="mb-1.5 block text-sm font-medium text-ink">To</span>
          <div className="flex gap-1">
            {audiences.map((a) => (
              <button
                key={a.value}
                type="button"
                onClick={() => setAudience(a.value)}
                className={`rounded-[8px] px-3 py-1.5 text-sm font-medium transition-colors ${
                  audience === a.value
                    ? 'bg-brand-soft text-brand-deep'
                    : 'text-ink-muted hover:bg-canvas hover:text-ink'
                }`}
              >
                {a.label}
              </button>
            ))}
          </div>
          <p className="mt-2 text-sm text-ink-muted">
            {picked.who}{' '}
            {reach === null ? (
              'Counting…'
            ) : (
              <span className="font-semibold text-ink">
                {reach} right now.
              </span>
            )}
          </p>

          <div className="mt-5 space-y-4">
            <Field
              label="Title"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              maxLength={80}
              placeholder="Diwali hours"
              hint={`${title.length}/80 — this is the line on the lock screen.`}
            />

            <label className="block">
              <span className="mb-1.5 block text-sm font-medium text-ink">
                Message
              </span>
              <textarea
                className="min-h-24 w-full rounded-[8px] border border-line bg-white px-3 py-2.5 text-sm text-ink outline-none placeholder:text-ink-muted focus:border-brand"
                value={body}
                maxLength={240}
                onChange={(e) => setBody(e.target.value)}
                placeholder="We're open until 1am this Sunday. Order late."
              />
              <span className="mt-1.5 block text-sm text-ink-muted">
                {body.length}/240 — optional, but a title alone rarely says
                enough.
              </span>
            </label>
          </div>

          <div className="mt-6">
            <Button
              className="w-full"
              disabled={!ready}
              onClick={() => setConfirming(true)}
            >
              {reach === 0 ? 'Nobody to send to' : 'Send'}
            </Button>
          </div>
        </div>

        <div>
          <h2 className="text-base font-bold text-ink">Already sent</h2>
          <p className="mt-0.5 mb-3 max-w-xl text-sm text-ink-muted">
            There is no recall. This list is the record.
          </p>

          {sent === null ? (
            <p className="text-sm text-ink-muted">Loading…</p>
          ) : sent.length === 0 ? (
            <p className="text-sm text-ink-muted">
              Nothing has been broadcast yet.
            </p>
          ) : (
            <div className="space-y-2">
              {sent.map((b) => (
                <div
                  key={b.id}
                  className="rounded-[12px] border border-line bg-white p-4"
                >
                  <div className="flex flex-wrap items-baseline justify-between gap-2">
                    <p className="font-semibold text-ink">{b.title}</p>
                    <p className="text-sm text-ink-muted">
                      {b.recipient_count}{' '}
                      {b.audience === 'restaurant'
                        ? 'restaurants'
                        : `${b.audience}s`}{' '}
                      · {when(b.created_at)}
                    </p>
                  </div>
                  {b.body && (
                    <p className="mt-1 text-sm text-ink-muted">{b.body}</p>
                  )}
                  <p className="mt-1 text-xs text-ink-muted">by {b.sent_by}</p>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      {confirming && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-ink/40 p-4">
          <div className="w-full max-w-md rounded-[12px] bg-white p-6">
            <h2 className="text-base font-bold text-ink">
              Send to {reach} {picked.label.toLowerCase()}?
            </h2>
            <p className="mt-2 text-sm text-ink-muted">
              {reach} phone{reach === 1 ? '' : 's'} will ring and {reach === 1 ? 'it' : 'they'} cannot be
              un-rung. Read it once more:
            </p>
            <div className="mt-4 rounded-[8px] bg-canvas px-4 py-3">
              <p className="font-semibold text-ink">{title}</p>
              {body && <p className="mt-0.5 text-sm text-ink-muted">{body}</p>}
            </div>
            <div className="mt-6 flex justify-end gap-2">
              <Button
                variant="ghost"
                onClick={() => setConfirming(false)}
                disabled={busy}
              >
                Not yet
              </Button>
              <Button onClick={() => void send()} loading={busy}>
                Send it
              </Button>
            </div>
          </div>
        </div>
      )}
    </>
  )
}
