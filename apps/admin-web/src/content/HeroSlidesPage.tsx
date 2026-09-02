import { useCallback, useEffect, useState } from 'react'
import { api, slideStateOf } from '../lib/api'
import type { HeroSlideRow, SlideState } from '../lib/api'
import {
  formatBytes,
  MOTION_TARGET_BYTES,
  uploadMotion,
  uploadPhoto,
  UploadFailure,
} from '../lib/uploads'
import { PageHeader } from '../ui/AppShell'
import {
  Banner,
  Button,
  ConfirmDialog,
  EmptyState,
  Field,
  Pill,
  Toggle,
} from '../ui/primitives'

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
  expired: 'bg-non-veg-soft text-non-veg-ink',
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
///
/// **Nothing here is a placeholder.** It used to print "Your headline" and
/// "Order now" into an empty slide, which was fine when both were compulsory and
/// became a lie the moment they were not: an admin turning the headline off saw
/// the words still sitting there and could not tell whether they had worked.
/// What this draws is what ships, including nothing.
function SlidePreview({
  imageUrl,
  motionUrl,
  title,
  subtitle,
  ctaLabel,
  hasTarget,
}: {
  imageUrl: string
  motionUrl: string
  title: string
  subtitle: string
  ctaLabel: string
  hasTarget: boolean
}) {
  const bare = !title && !subtitle && !ctaLabel
  return (
    <div>
      <div
        className="relative overflow-hidden rounded-card bg-canvas"
        style={{ width: `${PREVIEW_WIDTH}px`, height: px(HERO_HEIGHT) }}
      >
        {imageUrl ? (
          // `object-fill`, matching the app's `BoxFit.fill` since 0067. Not a
          // detail: `object-cover` here would quietly crop the preview the same
          // way the phone used to, and an admin would compose against a frame
          // the phone no longer draws.
          <img src={imageUrl} alt="" className="h-full w-full object-fill" />
        ) : (
          // The app's fallback, so an empty preview is still honest about what a
          // slide with no artwork would look like — which is why the RPC refuses
          // to save one.
          <div className="h-full w-full bg-gradient-to-br from-brand to-brand-deep" />
        )}

        {/* The loop over the still, in the same order the app stacks them. What
            the admin watches here is byte-for-byte the file the phone decodes, so
            "does it actually move, and does it look right?" is answered before
            anything is saved rather than on a device afterwards.

            A `<video>` since 0072 — it used to be an `<img>`, which worked only
            because the loop was an animated WebP. `key` is the URL so replacing a
            loop reloads the element: React would otherwise keep the same node and
            leave the previous clip playing under a new `src`.

            `muted` is what makes `autoPlay` legal — every browser blocks
            autoplay with sound — and `playsInline` stops iOS Safari taking the
            preview fullscreen. Deliberately no `controls`: the phone has none, so
            neither should the thing claiming to show what the phone does. */}
        {motionUrl && (
          <video
            key={motionUrl}
            src={motionUrl}
            autoPlay
            muted
            loop
            playsInline
            className="absolute inset-0 h-full w-full object-fill"
          />
        )}

        {/* The scrim the app draws under its copy — and only when there is copy
            to put a floor under. A slide that is nothing but artwork gets no
            scrim, because darkening the bottom half of a picture for the sake
            of text that is not there is exactly the thing this change exists to
            stop. The app makes the same test. */}
        {!bare && (
          <div
            className="absolute inset-0"
            style={{
              background:
                'linear-gradient(to bottom, rgba(0,0,0,0.2) 35%, rgba(0,0,0,0.6))',
            }}
          />
        )}

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
          {title && (
            <span
              className="w-full font-extrabold text-white"
              style={{
                fontSize: px(HEADLINE_SIZE),
                lineHeight: 1.05,
                // Two lines and then it clips, same as the app's `maxLines: 2`.
                display: '-webkit-box',
                WebkitLineClamp: 2,
                WebkitBoxOrient: 'vertical',
                overflow: 'hidden',
                textShadow: '0 1px 2px rgba(0,0,0,0.4)',
              }}
            >
              {title}
            </span>
          )}
          {subtitle && (
            <span
              className="w-full text-white/90"
              style={{ fontSize: px(14), marginTop: title ? px(4) : 0 }}
            >
              {subtitle}
            </span>
          )}
          {ctaLabel && (
            <span
              className="inline-flex items-center rounded-full bg-white font-semibold text-brand-ink"
              style={{
                fontSize: px(14),
                marginTop: title || subtitle ? px(16) : 0,
                paddingLeft: px(24),
                paddingRight: px(24),
                paddingTop: px(12),
                paddingBottom: px(12),
              }}
            >
              {ctaLabel} {hasTarget ? '→' : '↓'}
            </span>
          )}
        </div>
      </div>
      <p className="mt-2 max-w-[264px] text-xs text-ink-muted">
        A 393pt phone, to scale. The location row and search pill float on the
        artwork — keep faces and text out of the top third.
      </p>
      {bare && (
        <p className="mt-1.5 max-w-[264px] text-xs text-ink-muted">
          Artwork only. The whole slide is the tap target, so a destination below
          still works.
        </p>
      )}
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

  // Whether the slide *has* a headline and a button, held apart from what they
  // say. Two states and not one, so switching the headline off and back on
  // returns the words that were there rather than an empty box — an admin
  // comparing "with the headline" against "without it" should not have to retype
  // it each time they look.
  //
  // A new slide starts with both on, because that is the shape almost every
  // campaign has. An existing one starts with whatever it was saved as: the
  // empty string is the absence, exactly as the column means it.
  const [hasTitle, setHasTitle] = useState(
    editing ? editing.title !== '' : true,
  )
  const [hasCta, setHasCta] = useState(
    editing ? editing.cta_label !== '' : true,
  )

  // What actually reaches the database, and what the preview draws. Everything
  // below reads these rather than the raw fields, so there is one answer to
  // "does this slide have a headline" instead of two that can disagree.
  const liveTitle = hasTitle ? title : ''
  const liveSubtitle = hasTitle ? subtitle : ''
  const liveCta = hasCta ? ctaLabel : ''
  const [imageUrl, setImageUrl] = useState(editing?.image_url ?? '')
  const [motionUrl, setMotionUrl] = useState(editing?.motion_url ?? '')
  const [sortOrder, setSortOrder] = useState(String(editing?.sort_order ?? 0))
  const [startsAt, setStartsAt] = useState(toLocalInput(editing?.starts_at))
  const [endsAt, setEndsAt] = useState(toLocalInput(editing?.ends_at))

  const [uploading, setUploading] = useState(false)
  const [uploadError, setUploadError] = useState<string | null>(null)

  // Null for a loop that was already on the slide when this form opened. The
  // size is measured at the moment it is chosen, which is the moment it can
  // still be changed; re-measuring on every edit would mean downloading the
  // whole loop to open a form and fix a typo.
  const [motionBytes, setMotionBytes] = useState<number | null>(null)
  const [motionBusy, setMotionBusy] = useState(false)
  const [motionError, setMotionError] = useState<string | null>(null)

  /// Whether the artwork on this form was lifted out of the video rather than
  /// uploaded. Only ever true within the session that did it — an existing slide
  /// opens with this false, because by then the poster is simply the slide's
  /// artwork and there is nothing useful to say about where it came from.
  const [artFromVideo, setArtFromVideo] = useState(false)

  async function pickArt(file: File) {
    setUploading(true)
    setUploadError(null)
    try {
      setImageUrl(await uploadPhoto(file))
      // Real artwork now, whatever was there before.
      setArtFromVideo(false)
    } catch (e) {
      setUploadError(
        e instanceof UploadFailure ? e.message : 'That image could not be uploaded.',
      )
    } finally {
      setUploading(false)
    }
  }

  async function pickMotion(file: File) {
    setMotionBusy(true)
    setMotionError(null)
    try {
      const motion = await uploadMotion(file)
      setMotionUrl(motion.url)
      setMotionBytes(motion.bytes)
      // **A slide can be just a video, and this is the whole of how.** Artwork is
      // required of every slide (0053) and all the reasons still hold — the still
      // is the poster, the reduce-motion fallback, what shows while the video
      // buffers, and the only thing an older customer build can draw. So the rule
      // is not relaxed; the missing still is taken from the video's own first
      // frame, which is the one image certain to match it.
      //
      // Only when there is none. An admin who uploaded artwork *and* a video
      // chose that artwork deliberately, and silently replacing it with a video
      // frame would be the console overruling them.
      if (!imageUrl) {
        setImageUrl(motion.posterUrl)
        setArtFromVideo(true)
      }
    } catch (e) {
      setMotionError(
        e instanceof UploadFailure ? e.message : 'That video could not be uploaded.',
      )
    } finally {
      setMotionBusy(false)
    }
  }

  return (
    <form
      className="mt-5 rounded-field border border-line p-4"
      onSubmit={(e) => {
        e.preventDefault()
        onSubmit({
          id: editing?.id ?? null,
          title: liveTitle,
          subtitle: liveSubtitle,
          cta_label: liveCta,
          cta_target: ctaTarget,
          image_url: imageUrl,
          motion_url: motionUrl,
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
          {/* Two switches rather than "leave the box empty", because an empty
              box is ambiguous — it reads as something not filled in yet, and an
              admin who wanted no headline could never be sure they had got what
              they asked for. A switch that is off is a decision. */}
          <div className="space-y-4 rounded-field bg-canvas p-4">
            <Toggle
              label="Headline"
              checked={hasTitle}
              onChange={setHasTitle}
              hint="Off for artwork that already carries its own words — the app draws nothing over the picture, and no dark scrim under it."
            />
            {hasTitle && (
              <div className="space-y-4">
                <Field
                  label="Headline text"
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
                  hint="Needs a headline above it — the database refuses a sub-line on its own."
                />
              </div>
            )}
          </div>

          <div className="space-y-4 rounded-field bg-canvas p-4">
            <Toggle
              label="Button"
              checked={hasCta}
              onChange={setHasCta}
              hint="Off and the whole slide becomes tappable instead, so a banner with its own painted-on button still goes where you send it."
            />
            {hasCta && (
              <Field
                label="Button text"
                value={ctaLabel}
                onChange={(e) => setCtaLabel(e.target.value)}
                placeholder="Order now"
              />
            )}
            <Field
              label={hasCta ? 'Where the button goes (optional)' : 'Where the slide goes (optional)'}
              value={ctaTarget}
              onChange={(e) => setCtaTarget(e.target.value)}
              placeholder="/restaurant/r3"
              // The database owns this list and refuses anything else, including
              // a restaurant that is not published. Stating it here saves a
              // round trip; it does not replace the check.
              hint={`Leave empty and the tap scrolls the customer to the restaurant list — the way it works today. Otherwise: /restaurant/<id>, /gifts, /orders or /favourites.`}
            />
          </div>

          <Field
            label="Position"
            type="number"
            min={0}
            value={sortOrder}
            onChange={(e) => setSortOrder(e.target.value)}
            hint="Lowest first."
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
            <label className="inline-flex h-10 cursor-pointer items-center rounded-field border border-line bg-white px-4 text-sm font-semibold text-ink hover:bg-canvas">
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
              Square, and at least 800px wide. The app <strong>stretches</strong>{' '}
              the picture to fill the phone rather than cropping it, so nothing
              you put near an edge is ever cut off — but a picture that is not
              square arrives slightly squashed. The hero is 393 × 396 on a
              typical phone, so square is the shape that lands untouched.
            </p>
            <p className="mt-1 text-sm text-ink-muted">
              Uploaded to Cloudinary — the database will not accept art from
              anywhere else.
            </p>
            {artFromVideo && (
              <p className="mt-1.5 text-sm text-ink-muted">
                Taken from your video's first frame, so you don't have to upload a
                separate image. Every slide needs one: it is what shows while the
                video loads, if it can't play, and when the phone asks for reduced
                motion. <strong>Upload an image to use your own instead.</strong>
              </p>
            )}
            {uploadError && (
              <p className="mt-1.5 text-sm text-non-veg-ink">{uploadError}</p>
            )}
          </div>

          {/* The loop is an enhancement to a slide that already works. It is
              below the artwork and optional in the copy, because the still is
              what every failure path lands on — a slow network, a decode that
              fails, a phone asking for reduced motion. */}
          <div>
            <span className="mb-1.5 block text-sm font-medium text-ink">
              Motion loop (optional)
            </span>
            <div className="flex flex-wrap items-center gap-2">
              <label className="inline-flex h-10 cursor-pointer items-center rounded-field border border-line bg-white px-4 text-sm font-semibold text-ink hover:bg-canvas">
                {motionBusy
                  ? 'Transcoding…'
                  : motionUrl
                    ? 'Replace loop'
                    : 'Upload MP4'}
                <input
                  type="file"
                  accept="video/*"
                  className="hidden"
                  disabled={motionBusy}
                  onChange={(e) => {
                    const file = e.target.files?.[0]
                    e.target.value = ''
                    if (file) void pickMotion(file)
                  }}
                />
              </label>
              {motionUrl && !motionBusy && (
                <button
                  type="button"
                  onClick={() => {
                    setMotionUrl('')
                    setMotionBytes(null)
                    setMotionError(null)
                    // A poster only existed because of the video, so it goes with
                    // it — leaving it behind would turn "remove the loop" into a
                    // still-only slide showing one arbitrary video frame, which is
                    // not a thing anybody asked for. Artwork the admin uploaded
                    // themselves is untouched.
                    if (artFromVideo) {
                      setImageUrl('')
                      setArtFromVideo(false)
                    }
                  }}
                  className="text-sm font-medium text-ink-muted hover:text-non-veg-ink"
                >
                  Remove loop
                </button>
              )}
            </div>

            <p className="mt-1.5 text-sm text-ink-muted">
              Silent, and the <strong>whole clip</strong> plays on loop — at your
              clip's own resolution and frame rate, to a 1080px width. The phone
              plays the video itself, so what you see in the preview is what
              ships. Length is not capped; the delivered size below is, so a
              longer film simply costs more and tells you how much.
            </p>
            <p className="mt-1 text-sm text-ink-muted">
              A video on its own is enough — the artwork above fills itself in from
              the first frame if you haven't uploaded one.
            </p>

            {motionBusy && (
              <p className="mt-1.5 text-sm text-ink-muted">
                Uploading, transcoding and measuring the delivered loop. A long
                clip can take a minute or two — Cloudinary builds it once, and
                doing it now means no customer waits for it later.
              </p>
            )}

            {/* The number, because an admin who uploads a 40 MB clip should see
                what a customer downloads before the customer pays for it. Over
                the target it is amber and still saveable; over the hard cap the
                upload never got this far. */}
            {motionBytes !== null && (
              <p
                className={`mt-1.5 text-sm ${
                  motionBytes > MOTION_TARGET_BYTES ? 'text-warn' : 'text-veg'
                }`}
              >
                {motionBytes > MOTION_TARGET_BYTES
                  ? `${formatBytes(motionBytes)} on mobile data — over the ${formatBytes(MOTION_TARGET_BYTES)} target. A shorter or calmer clip would land under it.`
                  : `${formatBytes(motionBytes)} delivered — within the ${formatBytes(MOTION_TARGET_BYTES)} target.`}
              </p>
            )}
            {motionUrl && motionBytes === null && !motionBusy && (
              <p className="mt-1.5 text-sm text-ink-muted">
                This slide already has a loop — it is playing in the preview.
                Replace it to see a new size.
              </p>
            )}

            {motionError && (
              <p className="mt-1.5 text-sm text-non-veg-ink">{motionError}</p>
            )}
          </div>
        </div>

        <SlidePreview
          imageUrl={imageUrl}
          motionUrl={motionUrl}
          title={liveTitle}
          subtitle={liveSubtitle}
          ctaLabel={liveCta}
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
          <Banner tone="error" className="mb-4" onDismiss={() => setError(null)}>
            {error}
          </Banner>
        )}

        <div className="rounded-card border border-line bg-white p-6">
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
            <div className="mt-5">
              <EmptyState
                title="No slides yet"
                body="The app is showing the artwork it ships with, which is a working home screen. A slide you add here stays switched off until you publish it."
                action={<Button onClick={() => setAdding(true)}>Add slide</Button>}
              />
            </div>
          )}

          {slides !== null && slides.length > 0 && (
            <div className="mt-5 divide-y divide-line rounded-field border border-line">
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
                        <span className="text-ink-muted tabular-nums">
                          {s.sort_order}
                        </span>
                        {/* A slide can have no headline since 0067, and the row
                            has to be identifiable anyway. "Artwork only" is what
                            it is, not a missing value to be apologised for. */}
                        <span
                          className={`truncate ${s.title ? '' : 'text-ink-muted italic'}`}
                        >
                          {s.title || 'Artwork only'}
                        </span>
                        <StatePill state={state} />
                        {s.motion_url && <Pill>Loop</Pill>}
                      </p>
                      <p className="truncate text-sm text-ink-muted">
                        {s.cta_label
                          ? `${s.cta_label} → `
                          : 'whole slide taps → '}
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
                        className="text-sm font-medium text-ink-muted hover:text-non-veg-ink disabled:opacity-40"
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
                        className="text-sm font-medium text-brand-ink hover:text-ink disabled:opacity-40"
                      >
                        Publish
                      </button>
                    )}

                    <button
                      type="button"
                      disabled={busy}
                      onClick={() => setDeleting(s)}
                      className="text-sm font-medium text-ink-muted hover:text-non-veg-ink disabled:opacity-40"
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
          title={
            deleting.title
              ? `Delete "${deleting.title}"?`
              : `Delete the slide at position ${deleting.sort_order}?`
          }
          body="The slide and its schedule are erased. The uploaded image stays on Cloudinary. If this campaign might come back, switch it off instead — that is reversible and this is not."
          confirmLabel="Delete"
          tone="danger"
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
