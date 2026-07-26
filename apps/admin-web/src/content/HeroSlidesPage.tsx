import { useCallback, useEffect, useState } from 'react'
import { api, slideStateOf } from '../lib/api'
import type { HeroSlideRow, SlideState } from '../lib/api'
import { uploadPhoto, UploadFailure } from '../lib/uploads'
import { PageHeader } from '../ui/AppShell'
import { Button, ConfirmDialog, Field } from '../ui/primitives'

/// The customer home hero.
///
/// Until migration 0053 these six slides were a `const` list in
/// `home_hero_carousel.dart`: changing "60% OFF" to "50% OFF" meant a code
/// change, a build and a store review. Now it is a row, and this is the screen
/// that writes it.
///
/// Zero slides is a valid and safe state, not an empty screen to be apologised
/// for. The app keeps its own composed artwork as the empty state, so nothing
/// regresses while there is no campaign — which is what makes it fine to have
/// shipped this before any content existed.

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

// ---------------------------------------------------------------------------
// The phone's real metrics, read off `home_app_bar.dart`.
// ---------------------------------------------------------------------------
// The preview is worth nothing if it is approximately the right shape. These are
// the numbers the customer app actually computes, at a 393pt-wide phone — the
// common Android logical width, and the one where `promoHeight` sits at the
// bottom of its clamp:
//
//   promoHeight  = clamp(width * 0.58, 238, 262)          → 238
//   headerInset  = statusBarInset + _headerBody + 8       → 44 + 106 + 8 = 158
//   headline     = clamp(width * 0.108, 30, 44)           → 42.4
//
// Everything below is one of those divided by `SCALE`, so the crop on screen is
// the crop on the phone.
const PHONE_WIDTH = 393
const STATUS_INSET = 44
const HEADER_INSET = STATUS_INSET + 106 + 8
const PROMO_HEIGHT = 238
const HERO_HEIGHT = HEADER_INSET + PROMO_HEIGHT
const HEADLINE_SIZE = PHONE_WIDTH * 0.108

const PREVIEW_WIDTH = 264
const SCALE = PREVIEW_WIDTH / PHONE_WIDTH
const px = (dp: number) => `${dp * SCALE}px`

function StatePill({ state }: { state: SlideState }) {
  return (
    <span
      className={`inline-block whitespace-nowrap rounded-full px-2.5 py-1 text-xs font-semibold ${stateStyles[state]}`}
    >
      {stateLabels[state]}
    </span>
  )
}

/// The slide as the customer sees it, at the phone's real aspect ratio and with
/// the app's own chrome drawn over it.
///
/// The chrome is the whole point. The location row and the search pill *float on
/// the artwork* — they are not a bar above it — so the top 40% of every upload is
/// underneath them. An admin who cannot see that will centre a face there and
/// ship a headline across somebody's nose.
function SlidePreview({
  imageUrl,
  title,
  subtitle,
  ctaLabel,
  hasTarget,
}: {
  imageUrl: string
  title: string
  subtitle: string
  ctaLabel: string
  hasTarget: boolean
}) {
  return (
    <div>
      <div
        className="relative overflow-hidden rounded-[12px] bg-canvas"
        style={{ width: `${PREVIEW_WIDTH}px`, height: px(HERO_HEIGHT) }}
      >
        {imageUrl ? (
          <img src={imageUrl} alt="" className="h-full w-full object-cover" />
        ) : (
          // The app's fallback, so an empty preview is still honest about what a
          // slide with no artwork would look like — which is why the RPC refuses
          // to save one.
          <div className="h-full w-full bg-gradient-to-br from-brand to-brand-deep" />
        )}

        {/* The scrim the app draws under its copy. */}
        <div
          className="absolute inset-0"
          style={{
            background:
              'linear-gradient(to bottom, rgba(0,0,0,0.2) 35%, rgba(0,0,0,0.6))',
          }}
        />

        {/* Location row. */}
        <div
          className="absolute left-0 right-0 flex items-center text-white/90"
          style={{
            top: px(STATUS_INSET + 16),
            height: px(44),
            paddingLeft: px(16),
            paddingRight: px(16),
            fontSize: px(13),
          }}
        >
          <span className="truncate">◉ Delivering to · Home ▾</span>
        </div>

        {/* Search pill. */}
        <div
          className="absolute flex items-center rounded-[6px] bg-white text-ink-muted"
          style={{
            top: px(STATUS_INSET + 16 + 44 + 10),
            left: px(16),
            right: px(16),
            height: px(44),
            paddingLeft: px(12),
            fontSize: px(13),
          }}
        >
          Search "Biryani"
        </div>

        {/* The copy, bottom-aligned in the promo area exactly as the app does. */}
        <div
          className="absolute left-0 right-0 flex flex-col items-center text-center"
          style={{
            top: px(HEADER_INSET),
            bottom: px(16),
            paddingLeft: px(16),
            paddingRight: px(16),
            justifyContent: 'flex-end',
          }}
        >
          <span
            className="w-full font-extrabold leading-none text-white"
            style={{
              fontSize: px(HEADLINE_SIZE),
              // Two lines and then it clips, same as the app's `maxLines: 2`.
              display: '-webkit-box',
              WebkitLineClamp: 2,
              WebkitBoxOrient: 'vertical',
              overflow: 'hidden',
              textShadow: '0 1px 2px rgba(0,0,0,0.4)',
            }}
          >
            {title || 'Your headline'}
          </span>
          {subtitle && (
            <span
              className="mt-1 w-full text-white/90"
              style={{ fontSize: px(14) }}
            >
              {subtitle}
            </span>
          )}
          <span
            className="mt-3 inline-flex items-center rounded-full bg-white font-semibold text-brand-deep"
            style={{
              fontSize: px(14),
              paddingLeft: px(24),
              paddingRight: px(24),
              paddingTop: px(12),
              paddingBottom: px(12),
            }}
          >
            {ctaLabel || 'Order now'} {hasTarget ? '→' : '↓'}
          </span>
        </div>
      </div>
      <p className="mt-2 max-w-[264px] text-xs text-ink-muted">
        A 393pt phone, to scale. The location row and search pill float on the
        artwork — keep faces and text out of the top third.
      </p>
    </div>
  )
}

/// Adding and editing are the same form, because a slide is the same ten fields
/// either way. The only thing the form cannot do is publish: that switch lives
/// in the list, so saving a corrected typo can never also put a slide on screen.
function SlideForm({
  editing,
  busy,
  onSubmit,
  onCancel,
}: {
  editing: HeroSlideRow | null
  busy: boolean
  onSubmit: (slide: Record<string, unknown>) => void
  onCancel: () => void
}) {
  const [title, setTitle] = useState(editing?.title ?? '')
  const [subtitle, setSubtitle] = useState(editing?.subtitle ?? '')
  const [ctaLabel, setCtaLabel] = useState(editing?.cta_label ?? 'Order now')
  const [ctaTarget, setCtaTarget] = useState(editing?.cta_target ?? '')
  const [imageUrl, setImageUrl] = useState(editing?.image_url ?? '')
  const [sortOrder, setSortOrder] = useState(String(editing?.sort_order ?? 0))
  const [startsAt, setStartsAt] = useState(toLocalInput(editing?.starts_at))
  const [endsAt, setEndsAt] = useState(toLocalInput(editing?.ends_at))

  const [uploading, setUploading] = useState(false)
  const [uploadError, setUploadError] = useState<string | null>(null)

  async function pickArt(file: File) {
    setUploading(true)
    setUploadError(null)
    try {
      setImageUrl(await uploadPhoto(file))
    } catch (e) {
      setUploadError(
        e instanceof UploadFailure ? e.message : 'That image could not be uploaded.',
      )
    } finally {
      setUploading(false)
    }
  }

  return (
    <form
      className="mt-5 rounded-[8px] border border-line p-4"
      onSubmit={(e) => {
        e.preventDefault()
        onSubmit({
          id: editing?.id ?? null,
          title,
          subtitle,
          cta_label: ctaLabel,
          cta_target: ctaTarget,
          image_url: imageUrl,
          sort_order: Number(sortOrder) || 0,
          // Sent as ISO, because the browser's `datetime-local` value carries no
          // zone and Postgres would read a bare timestamp as UTC — an admin in
          // IST scheduling 9am would publish at 2:30pm.
          starts_at: fromLocalInput(startsAt),
          ends_at: fromLocalInput(endsAt),
        })
      }}
    >
      <div className="flex flex-wrap gap-6">
        <div className="min-w-72 flex-1 space-y-4">
          <Field
            label="Headline"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="FLAT ₹150 OFF"
            hint="Two lines at most, and short ones. It is set at 42pt on the phone."
          />
          <Field
            label="Sub-line (optional)"
            value={subtitle}
            onChange={(e) => setSubtitle(e.target.value)}
            placeholder="On orders above ₹399"
          />

          <div className="grid gap-4 sm:grid-cols-2">
            <Field
              label="Button text"
              value={ctaLabel}
              onChange={(e) => setCtaLabel(e.target.value)}
              placeholder="Order now"
            />
            <Field
              label="Position"
              type="number"
              min={0}
              value={sortOrder}
              onChange={(e) => setSortOrder(e.target.value)}
              hint="Lowest first."
            />
          </div>

          <Field
            label="Where the button goes (optional)"
            value={ctaTarget}
            onChange={(e) => setCtaTarget(e.target.value)}
            placeholder="/restaurant/r3"
            // The database owns this list and refuses anything else, including a
            // restaurant that is not published. Stating it here saves a round
            // trip; it does not replace the check.
            hint="Leave empty and the button scrolls the customer to the restaurant list — the way it works today. Otherwise: /restaurant/<id>, /gifts, /orders or /favourites."
          />

          <div className="grid gap-4 sm:grid-cols-2">
            <Field
              label="Starts"
              type="datetime-local"
              value={startsAt}
              onChange={(e) => setStartsAt(e.target.value)}
              hint="Blank means now."
            />
            <Field
              label="Ends (optional)"
              type="datetime-local"
              value={endsAt}
              onChange={(e) => setEndsAt(e.target.value)}
              hint="Blank means it runs until switched off."
            />
          </div>

          <div>
            <span className="mb-1.5 block text-sm font-medium text-ink">
              Artwork
            </span>
            <label className="inline-flex h-10 cursor-pointer items-center rounded-[8px] border border-line bg-white px-4 text-sm font-semibold text-ink hover:bg-canvas">
              {uploading ? 'Uploading…' : imageUrl ? 'Replace image' : 'Upload image'}
              <input
                type="file"
                accept="image/*"
                className="hidden"
                disabled={uploading}
                onChange={(e) => {
                  const file = e.target.files?.[0]
                  // Cleared so picking the same file twice still fires a change.
                  e.target.value = ''
                  if (file) void pickArt(file)
                }}
              />
            </label>
            <p className="mt-1.5 text-sm text-ink-muted">
              Roughly square, and at least 800px wide. Uploaded to Cloudinary —
              the database will not accept art from anywhere else.
            </p>
            {uploadError && (
              <p className="mt-1.5 text-sm text-non-veg">{uploadError}</p>
            )}
          </div>
        </div>

        <SlidePreview
          imageUrl={imageUrl}
          title={title}
          subtitle={subtitle}
          ctaLabel={ctaLabel}
          hasTarget={ctaTarget.trim() !== ''}
        />
      </div>

      <div className="mt-4 flex gap-2">
        <Button type="submit" loading={busy}>
          {editing ? 'Save changes' : 'Create slide'}
        </Button>
        <Button type="button" variant="ghost" onClick={onCancel} disabled={busy}>
          Cancel
        </Button>
      </div>
      {!editing && (
        <p className="mt-2 text-sm text-ink-muted">
          Created switched off. Publish it from the list when you have looked at
          the preview.
        </p>
      )}
    </form>
  )
}

export function HeroSlidesPage() {
  const [slides, setSlides] = useState<HeroSlideRow[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [adding, setAdding] = useState(false)
  const [editing, setEditing] = useState<HeroSlideRow | null>(null)
  const [deleting, setDeleting] = useState<HeroSlideRow | null>(null)

  const load = useCallback(async () => {
    try {
      setSlides(await api.listHeroSlides())
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

  const liveCount = (slides ?? []).filter((s) => slideStateOf(s) === 'live').length

  return (
    <>
      <PageHeader
        title="Home hero"
        subtitle="The carousel at the top of the customer app."
        action={
          !adding && !editing ? (
            <Button onClick={() => setAdding(true)}>Add slide</Button>
          ) : undefined
        }
      />

      <div className="max-w-5xl p-6">
        {error && (
          <p className="mb-4 rounded-[8px] bg-non-veg-soft px-4 py-3 text-sm text-non-veg">
            {error}
          </p>
        )}

        <div className="rounded-[12px] border border-line bg-white p-6">
          <h2 className="text-base font-bold text-ink">Campaign slides</h2>
          <p className="mt-1 text-sm text-ink-muted">
            {slides === null
              ? 'Loading…'
              : liveCount === 0
                ? 'Nothing live. The app is showing the artwork it ships with — which is a working home screen, not a blank one.'
                : `${liveCount} live of ${slides.length}, shown in position order.`}
          </p>

          {adding && (
            <SlideForm
              editing={null}
              busy={busy}
              onCancel={() => setAdding(false)}
              onSubmit={(slide) =>
                void run(() => api.upsertHeroSlide(slide)).then(
                  (ok) => ok && setAdding(false),
                )
              }
            />
          )}

          {editing && (
            <SlideForm
              editing={editing}
              busy={busy}
              onCancel={() => setEditing(null)}
              onSubmit={(slide) =>
                void run(() => api.upsertHeroSlide(slide)).then(
                  (ok) => ok && setEditing(null),
                )
              }
            />
          )}

          {slides !== null && slides.length === 0 && !adding && (
            <p className="mt-5 text-sm text-ink-muted">
              No slides yet. Add one — it stays switched off until you publish it.
            </p>
          )}

          {slides !== null && slides.length > 0 && (
            <div className="mt-5 divide-y divide-line rounded-[8px] border border-line">
              {slides.map((s) => {
                const state = slideStateOf(s)
                return (
                  <div key={s.id} className="flex flex-wrap items-center gap-3 px-4 py-3">
                    <img
                      src={s.image_url}
                      alt=""
                      className="h-12 w-12 shrink-0 rounded-[6px] border border-line object-cover"
                    />
                    <div className="min-w-0 flex-1">
                      <p className="flex items-center gap-2 text-sm font-medium text-ink">
                        <span className="tabular-nums text-ink-muted">
                          {s.sort_order}
                        </span>
                        <span className="truncate">{s.title}</span>
                        <StatePill state={state} />
                      </p>
                      <p className="truncate text-sm text-ink-muted">
                        {s.cta_label} →{' '}
                        {s.cta_target ?? 'the restaurant list (scrolls down)'} ·{' '}
                        {windowText(s)}
                      </p>
                    </div>

                    <button
                      type="button"
                      disabled={busy}
                      onClick={() => {
                        setAdding(false)
                        setEditing(s)
                      }}
                      className="text-sm font-medium text-ink-muted hover:text-ink disabled:opacity-40"
                    >
                      Edit
                    </button>

                    {s.is_active ? (
                      <button
                        type="button"
                        disabled={busy}
                        onClick={() =>
                          void run(() => api.setHeroSlideActive(s.id, false))
                        }
                        className="text-sm font-medium text-ink-muted hover:text-non-veg disabled:opacity-40"
                      >
                        Switch off
                      </button>
                    ) : (
                      <button
                        type="button"
                        disabled={busy}
                        onClick={() =>
                          void run(() => api.setHeroSlideActive(s.id, true))
                        }
                        className="text-sm font-medium text-brand hover:text-brand-deep disabled:opacity-40"
                      >
                        Publish
                      </button>
                    )}

                    <button
                      type="button"
                      disabled={busy}
                      onClick={() => setDeleting(s)}
                      className="text-sm font-medium text-ink-muted hover:text-non-veg disabled:opacity-40"
                    >
                      Delete
                    </button>
                  </div>
                )
              })}
            </div>
          )}
        </div>
      </div>

      {deleting && (
        <ConfirmDialog
          title={`Delete "${deleting.title}"?`}
          body="The slide and its schedule are erased. The uploaded image stays on Cloudinary. If this campaign might come back, switch it off instead — that is reversible and this is not."
          confirmLabel="Delete"
          busy={busy}
          onCancel={() => setDeleting(null)}
          onConfirm={() =>
            void run(() => api.deleteHeroSlide(deleting.id)).then(
              (ok) => ok && setDeleting(null),
            )
          }
        />
      )}
    </>
  )
}

/// The schedule in one phrase, in the admin's own timezone.
function windowText(s: HeroSlideRow): string {
  const start = new Date(s.starts_at)
  const started = start.getTime() <= Date.now()
  const from = started ? 'from ' : 'starts '
  const when = start.toLocaleString(undefined, {
    day: 'numeric',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  })
  if (!s.ends_at) return `${from}${when}`
  const end = new Date(s.ends_at).toLocaleString(undefined, {
    day: 'numeric',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  })
  return `${from}${when} until ${end}`
}

/// A timestamptz into the value a `datetime-local` input wants, in local time.
/// `toISOString` would be UTC and show an IST admin a time five and a half hours
/// off their own, which is how a campaign gets scheduled for the wrong evening.
function toLocalInput(iso: string | null | undefined): string {
  if (!iso) return ''
  const d = new Date(iso)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(
    d.getHours(),
  )}:${pad(d.getMinutes())}`
}

/// And back, as a zoned ISO string so the server stores the instant the admin
/// meant rather than the same digits read as UTC.
function fromLocalInput(value: string): string | null {
  if (!value) return null
  return new Date(value).toISOString()
}
