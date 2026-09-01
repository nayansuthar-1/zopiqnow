import { useCallback, useEffect, useState } from 'react'
import { api, slideStateOf } from '../lib/api'
import type { OrderAdRow, SlideState } from '../lib/api'
import { PageHeader } from '../ui/AppShell'
import { PhotoField } from '../ui/PhotoField'
import {
  Banner,
  Button,
  ConfirmDialog,
  EmptyState,
  Field,
  Modal,
  Toggle,
} from '../ui/primitives'

/// Ads beside the order tracking map (migration 0125).
///
/// An order in flight is the longest a customer looks at one screen, and this is
/// what we put in its corner. Ours, not a network's: two images and a button,
/// uploaded here and drawn by the app — there is no SDK in the customer binary
/// and nothing here calls an exchange.
///
/// **Zero ads is the normal, safe state.** The puck simply does not appear and
/// the map is a map, exactly as it was before this existed. So an empty screen
/// here is not something to apologise for.

const stateLabels: Record<SlideState, string> = {
  live: 'Live',
  off: 'Off',
  scheduled: 'Scheduled',
  expired: 'Expired',
}

const stateStyles: Record<SlideState, string> = {
  live: 'bg-veg-soft text-veg',
  off: 'bg-canvas text-ink-muted',
  scheduled: 'bg-warn-soft text-warn',
  expired: 'bg-non-veg-soft text-non-veg',
}

/// `datetime-local` speaks 'YYYY-MM-DDTHH:mm' in local time and nothing else.
function toLocalInput(iso: string | null): string {
  if (!iso) return ''
  const d = new Date(iso)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(
    d.getHours(),
  )}:${pad(d.getMinutes())}`
}

export function OrderAdsPage() {
  const [ads, setAds] = useState<OrderAdRow[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [editing, setEditing] = useState<OrderAdRow | null>(null)
  const [adding, setAdding] = useState(false)
  const [deleting, setDeleting] = useState<OrderAdRow | null>(null)

  const load = useCallback(async () => {
    try {
      setAds(await api.listOrderAds())
      setError(null)
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

  const live = (ads ?? []).filter((a) => slideStateOf(a) === 'live').length

  return (
    <>
      <PageHeader
        title="Map ads"
        subtitle={
          ads === null
            ? 'Loading…'
            : ads.length === 0
              ? 'Nothing runs beside the tracking map. The corner stays empty until an ad is live.'
              : `${ads.length} ${ads.length === 1 ? 'ad' : 'ads'} · ${live} live`
        }
        action={<Button onClick={() => setAdding(true)}>New ad</Button>}
      />

      <div className="p-6">
        {error && (
          <Banner tone="error" className="mb-4" onDismiss={() => setError(null)}>
            {error}
          </Banner>
        )}

        {live > 1 && (
          <Banner tone="warn" className="mb-4">
            {live} ads are live at once. The app shows only the first by order, so
            the rest are invisible until it ends or is switched off.
          </Banner>
        )}

        {ads !== null && ads.length === 0 ? (
          <EmptyState
            title="No map ads yet"
            body="An ad needs a square logo for the round button on the map, and a tall image for the screen it opens."
            action={<Button onClick={() => setAdding(true)}>New ad</Button>}
          />
        ) : (
          <div className="space-y-3">
            {(ads ?? []).map((ad) => {
              const state = slideStateOf(ad)
              return (
                <div
                  key={ad.id}
                  className="flex flex-wrap items-center gap-4 rounded-[12px] border border-line bg-white p-4"
                >
                  <div className="h-14 w-14 shrink-0 overflow-hidden rounded-full border border-line bg-canvas">
                    {ad.logo_url && (
                      <img
                        src={ad.logo_url}
                        alt=""
                        className="h-full w-full object-cover"
                      />
                    )}
                  </div>

                  <div className="min-w-0 flex-1">
                    <p className="flex items-center gap-2 text-sm font-bold text-ink">
                      {ad.name}
                      <span
                        className={`rounded-full px-2 py-0.5 text-xs font-medium ${stateStyles[state]}`}
                      >
                        {stateLabels[state]}
                      </span>
                    </p>
                    <p className="mt-0.5 truncate text-sm text-ink-muted">
                      {ad.cta_target
                        ? `${ad.cta_label} → ${ad.cta_target}`
                        : 'No button — the artwork is the whole ad'}
                    </p>
                  </div>

                  {/* A view is one order that saw it; a click is every tap. Said
                      here so nobody reads clicks > views as a broken counter. */}
                  <div className="shrink-0 text-right">
                    <p className="text-sm tabular-nums text-ink">
                      {ad.views.toLocaleString('en-IN')} views
                    </p>
                    <p className="text-sm tabular-nums text-ink-muted">
                      {ad.clicks.toLocaleString('en-IN')} clicks
                    </p>
                  </div>

                  <div className="flex shrink-0 items-center gap-3">
                    <Toggle
                      label="Live"
                      checked={ad.is_active}
                      disabled={busy}
                      onChange={(next) =>
                        void run(() => api.setOrderAdActive(ad.id, next))
                      }
                    />
                    <button
                      type="button"
                      onClick={() => setEditing(ad)}
                      className="text-sm font-semibold text-brand hover:text-brand-deep"
                    >
                      Edit
                    </button>
                    <button
                      type="button"
                      onClick={() => setDeleting(ad)}
                      className="text-sm font-medium text-ink-muted hover:text-non-veg"
                    >
                      Delete
                    </button>
                  </div>
                </div>
              )
            })}
          </div>
        )}
      </div>

      {(adding || editing) && (
        <AdDialog
          ad={editing}
          busy={busy}
          onCancel={() => {
            setAdding(false)
            setEditing(null)
          }}
          onSave={(payload) =>
            void run(() => api.upsertOrderAd(payload)).then((ok) => {
              if (ok) {
                setAdding(false)
                setEditing(null)
              }
            })
          }
        />
      )}

      {deleting && (
        <ConfirmDialog
          title={`Delete ${deleting.name}?`}
          tone="danger"
          body={`Its ${deleting.views.toLocaleString('en-IN')} views and ${deleting.clicks.toLocaleString(
            'en-IN',
          )} clicks go with it, and cannot be recovered. To stop it running without losing the numbers, switch it off instead.`}
          confirmLabel="Delete"
          busy={busy}
          onCancel={() => setDeleting(null)}
          onConfirm={() =>
            void run(() => api.deleteOrderAd(deleting.id)).then(
              (ok) => ok && setDeleting(null),
            )
          }
        />
      )}
    </>
  )
}

function AdDialog({
  ad,
  busy,
  onSave,
  onCancel,
}: {
  ad: OrderAdRow | null
  busy: boolean
  onSave: (payload: Record<string, unknown>) => void
  onCancel: () => void
}) {
  const [name, setName] = useState(ad?.name ?? '')
  const [logoUrl, setLogoUrl] = useState(ad?.logo_url ?? '')
  const [imageUrl, setImageUrl] = useState(ad?.image_url ?? '')
  const [headline, setHeadline] = useState(ad?.headline ?? '')
  const [ctaLabel, setCtaLabel] = useState(ad?.cta_label ?? '')
  const [ctaTarget, setCtaTarget] = useState(ad?.cta_target ?? '')
  const [sortOrder, setSortOrder] = useState(String(ad?.sort_order ?? 0))
  const [isActive, setIsActive] = useState(ad?.is_active ?? false)
  const [startsAt, setStartsAt] = useState(toLocalInput(ad?.starts_at ?? null))
  const [endsAt, setEndsAt] = useState(toLocalInput(ad?.ends_at ?? null))
  const [error, setError] = useState<string | null>(null)
  /// Owned by the photo fields, mirrored here so Save cannot land while an
  /// upload is still on its way and write the previous URL.
  const [uploading, setUploading] = useState(false)

  function submit() {
    if (!name.trim()) return setError('Give the ad a name so you can find it.')
    if (!logoUrl) return setError('The round button on the map needs a logo.')
    if (!imageUrl) return setError('The ad needs its full-screen artwork.')

    // The two halves of a button. Enforced here as well as in the database,
    // because a constraint violation reads as a database error rather than as
    // the sentence below.
    const label = ctaLabel.trim()
    const target = ctaTarget.trim()
    if (Boolean(label) !== Boolean(target)) {
      return setError(
        label
          ? 'A button needs somewhere to go. Add a link, or clear the button text.'
          : 'A link needs a button to sit on. Add the button text, or clear the link.',
      )
    }
    if (target && !/^(https?:\/\/|\/)/.test(target)) {
      return setError(
        'A link is either a web address starting http, or a path inside the app starting with a slash — like /restaurant/abc.',
      )
    }
    if (endsAt && startsAt && new Date(endsAt) <= new Date(startsAt)) {
      return setError('The end has to come after the start.')
    }

    onSave({
      ...(ad ? { id: ad.id } : {}),
      name: name.trim(),
      logo_url: logoUrl,
      image_url: imageUrl,
      headline: headline.trim(),
      cta_label: label,
      cta_target: target,
      sort_order: Number(sortOrder) || 0,
      is_active: isActive,
      starts_at: startsAt ? new Date(startsAt).toISOString() : null,
      ends_at: endsAt ? new Date(endsAt).toISOString() : null,
    })
  }

  return (
    <Modal
      title={ad ? `Edit ${ad.name}` : 'New map ad'}
      size="lg"
      busy={busy}
      onClose={onCancel}
      footer={
        <>
          <Button variant="ghost" onClick={onCancel} disabled={busy}>
            Cancel
          </Button>
          <Button onClick={submit} loading={busy} disabled={uploading}>
            {uploading ? 'Uploading…' : 'Save'}
          </Button>
        </>
      }
    >
      {error && (
        <Banner tone="error" className="mb-4" onDismiss={() => setError(null)}>
          {error}
        </Banner>
      )}

      <div className="space-y-4">
        <Field
          label="Name"
          value={name}
          onChange={(e) => setName(e.target.value)}
          hint="Yours, not the customer's — it only shows on this screen."
          placeholder="Reliance Digital · August sale"
        />

        <div className="grid gap-4 sm:grid-cols-2">
          <PhotoField
            label="Logo"
            value={logoUrl}
            onChange={setLogoUrl}
            onBusyChange={setUploading}
            // Drawn inside a circle 56px across, so anything not square loses
            // its edges.
            aspect={1}
            previewClassName="h-24 w-24"
            hint="Square. Shown in the round button on the map."
          />
          <PhotoField
            label="Full-screen artwork"
            value={imageUrl}
            onChange={setImageUrl}
            onBusyChange={setUploading}
            // A phone screen. Shown whole rather than cropped, so the artwork
            // should already say everything it needs to.
            aspect={9 / 16}
            previewClassName="h-40 w-[90px]"
            hint="Tall, like a phone screen. Nothing is cropped."
          />
        </div>

        <Field
          label="Headline (optional)"
          value={headline}
          onChange={(e) => setHeadline(e.target.value)}
          hint="Drawn over the foot of the artwork. Leave empty when the words are already in the picture."
        />

        <div className="grid gap-4 sm:grid-cols-2">
          <Field
            label="Button text (optional)"
            value={ctaLabel}
            onChange={(e) => setCtaLabel(e.target.value)}
            placeholder="Visit Store"
          />
          <Field
            label="Button link"
            value={ctaTarget}
            onChange={(e) => setCtaTarget(e.target.value)}
            placeholder="https://… or /restaurant/abc"
            hint={
              ctaTarget.trim().startsWith('http')
                ? 'Leaves Zopiq and opens the phone’s browser.'
                : ctaTarget.trim().startsWith('/')
                  ? 'Opens inside the app.'
                  : 'A web address, or a path inside the app.'
            }
          />
        </div>

        <div className="grid gap-4 sm:grid-cols-3">
          <Field
            label="Starts"
            type="datetime-local"
            value={startsAt}
            onChange={(e) => setStartsAt(e.target.value)}
          />
          <Field
            label="Ends (optional)"
            type="datetime-local"
            value={endsAt}
            onChange={(e) => setEndsAt(e.target.value)}
            hint="Empty runs until switched off."
          />
          <Field
            label="Order"
            value={sortOrder}
            inputMode="numeric"
            onChange={(e) => setSortOrder(e.target.value)}
            hint="Lowest wins when more than one is live."
          />
        </div>

        <Toggle
          label="Live"
          hint="Off keeps everything and shows nothing. The schedule above still applies when this is on."
          checked={isActive}
          onChange={setIsActive}
        />
      </div>
    </Modal>
  )
}
