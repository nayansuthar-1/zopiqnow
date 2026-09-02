import { useCallback, useEffect, useState } from 'react'
import { api } from '../lib/api'
import type { Audience, BroadcastRow } from '../lib/api'
import { PageHeader } from '../ui/AppShell'
import {
  Banner,
  Button,
  Card,
  CardSkeleton,
  EmptyState,
  Field,
  Modal,
  SegmentedControl,
  TextArea,
} from '../ui/primitives'

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
  const [reachError, setReachError] = useState<string | null>(null)
  const [attempt, setAttempt] = useState(0)
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
  //
  // `attempt` exists so "Try again" can re-run this. Send stays disabled while
  // the count is unknown — the confirmation is a sentence about that number —
  // but a swallowed failure left the page reading "Counting…" for ever, with a
  // dead Send button and nothing on screen admitting anything had gone wrong.
  useEffect(() => {
    let live = true
    setReach(null)
    setReachError(null)
    api
      .broadcastReach(audience)
      .then((n) => {
        if (live) setReach(n)
      })
      .catch((e: unknown) => {
        if (!live) return
        setReach(null)
        setReachError(e instanceof Error ? e.message : String(e))
      })
    return () => {
      live = false
    }
  }, [audience, attempt])

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
        <Card>
          {error && (
            <Banner tone="error" className="mb-4" onDismiss={() => setError(null)}>
              {error}
            </Banner>
          )}
          {note && (
            <Banner tone="success" className="mb-4" onDismiss={() => setNote(null)}>
              {note}
            </Banner>
          )}

          <span className="mb-1.5 block text-sm font-medium text-ink">To</span>
          <SegmentedControl
            label="Audience"
            value={audience}
            onChange={setAudience}
            options={audiences.map((a) => ({ value: a.value, label: a.label }))}
          />
          <p className="mt-2 text-sm text-ink-muted">
            {picked.who}{' '}
            {reachError !== null ? (
              <span className="text-non-veg-ink">
                Counting them failed, so there is no number to send to.
              </span>
            ) : reach === null ? (
              'Counting…'
            ) : (
              <span className="font-semibold text-ink">
                {reach} right now.
              </span>
            )}
          </p>

          {reachError !== null && (
            <div className="mt-2 flex flex-wrap items-center gap-3">
              <Button
                variant="secondary"
                size="sm"
                onClick={() => setAttempt((n) => n + 1)}
              >
                Try again
              </Button>
              <span className="text-xs text-ink-muted">{reachError}</span>
            </div>
          )}

          <div className="mt-5 space-y-4">
            <Field
              label="Title"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              maxLength={80}
              placeholder="Diwali hours"
              hint={`${title.length}/80 — this is the line on the lock screen.`}
            />

            <TextArea
              label="Message"
              value={body}
              maxLength={240}
              onChange={(e) => setBody(e.target.value)}
              placeholder="We're open until 1am this Sunday. Order late."
              hint={`${body.length}/240 — optional, but a title alone rarely says enough.`}
            />
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
        </Card>

        <div>
          <h2 className="text-base font-bold text-ink">Already sent</h2>
          <p className="mt-0.5 mb-3 max-w-xl text-sm text-ink-muted">
            There is no recall. This list is the record.
          </p>

          {sent === null ? (
            <CardSkeleton rows={2} />
          ) : sent.length === 0 ? (
            <EmptyState
              title="Nothing broadcast yet"
              body="Every message sent from this screen is listed here with its audience, its reach and who sent it."
            />
          ) : (
            <div className="space-y-2">
              {sent.map((b) => (
                <div
                  key={b.id}
                  className="rounded-card border border-line bg-white p-6"
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
        <Modal
          busy={busy}
          onClose={() => setConfirming(false)}
          title={`Send to ${reach} ${picked.label.toLowerCase()}?`}
          footer={
            <>
              <Button
                variant="secondary"
                onClick={() => setConfirming(false)}
                disabled={busy}
              >
                Not yet
              </Button>
              <Button onClick={() => void send()} loading={busy}>
                Send it
              </Button>
            </>
          }
        >
          <p className="text-sm text-ink-muted">
            {reach} phone{reach === 1 ? '' : 's'} will ring and{' '}
            {reach === 1 ? 'it' : 'they'} cannot be un-rung. Read it once more:
          </p>
          {/* The lock screen, near enough. Reading your own copy back in a
              different shape from the one you typed it in is how a typo gets
              caught — the same reason a proof is set, not re-read in the
              manuscript. */}
          <div className="mt-4 rounded-field bg-canvas px-4 py-3">
            <p className="font-semibold text-ink">{title}</p>
            {body && <p className="mt-0.5 text-sm text-ink-muted">{body}</p>}
          </div>
        </Modal>
      )}
    </>
  )
}
