import { useState } from 'react'
import { Button, Field } from './primitives'
import { GIFT_GALLERY_WIDTH, deliveryUrl, parseAsset } from '../lib/cloudinary'
import { UploadFailure, uploadPhoto, uploadPhotoByUrl } from '../lib/uploads'

/// Several photos of one thing, in an order somebody chose.
///
/// `PhotoField` is the single-photo version and stays that: a restaurant has one
/// cover and a dish has one picture. A handmade gift is bought on its detail —
/// the front, the side, the mirror work up close — which is why `image_urls`
/// has existed since 0023 and why the customer's detail sheet is a swipeable
/// PageView. Until 0118 nothing could write that array, so this field is the
/// first thing that ever has.
///
/// **Order is the feature, not a side effect.** The first entry is the card
/// photo on the Gifts grid, so "make this one first" is the most common thing an
/// admin will want to do here — it is a button on every tile rather than a drag
/// somebody has to discover.

/// Every added photo is stored as a `w_1200` rendition rather than the raw
/// upload. See [GIFT_GALLERY_WIDTH]. A photo we did not put in Cloudinary has no
/// asset to build a rendition from and is stored as given — the same honest
/// fallback `PhotoField` makes for its adjuster.
function delivered(url: string): string {
  const asset = parseAsset(url)
  return asset ? deliveryUrl(asset, GIFT_GALLERY_WIDTH) : url
}

export function GalleryField({
  label,
  value,
  onChange,
  hint,
  onBusyChange,
}: {
  label: string
  value: string[]
  onChange: (next: string[]) => void
  hint?: string
  /// Raised while an upload is in flight so the form around this can refuse to
  /// save. Without it a Save pressed mid-upload writes the gallery as it was and
  /// the photo the admin just picked is silently discarded.
  onBusyChange?: (busy: boolean) => void
}) {
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [linking, setLinking] = useState(false)
  const [link, setLink] = useState('')

  async function run(work: () => Promise<string>) {
    setBusy(true)
    onBusyChange?.(true)
    setError(null)
    try {
      const url = delivered(await work())
      // Appended, never inserted at the front. Uploading a photo should not
      // silently change which one the grid shows — "Make cover" is how that
      // happens, and it is one click away.
      onChange([...value, url])
      setLinking(false)
      setLink('')
    } catch (e) {
      setError(
        e instanceof UploadFailure ? e.message : 'That photo could not be added.',
      )
    } finally {
      setBusy(false)
      onBusyChange?.(false)
    }
  }

  function move(from: number, to: number) {
    if (to < 0 || to >= value.length) return
    const next = [...value]
    ;[next[from], next[to]] = [next[to], next[from]]
    onChange(next)
  }

  return (
    <div>
      <div className="mb-1.5 flex items-baseline justify-between gap-4">
        <span className="block text-sm font-medium text-ink">{label}</span>
        <span className="text-sm text-ink-muted">
          {value.length === 0
            ? 'None yet'
            : `${value.length} photo${value.length === 1 ? '' : 's'}`}
        </span>
      </div>

      {value.length > 0 && (
        <ul className="mb-3 grid grid-cols-2 gap-3 sm:grid-cols-4">
          {value.map((url, i) => (
            // The URL can repeat if somebody uploads the same file twice, so the
            // index is part of the key. Reordering re-renders the whole list
            // either way — there is no expensive subtree here to preserve.
            <li
              key={`${url}-${i}`}
              className="overflow-hidden rounded-field border border-line"
            >
              <div className="relative aspect-square bg-canvas">
                <img src={url} alt="" className="h-full w-full object-cover" />
                {i === 0 && (
                  <span className="absolute top-1.5 left-1.5 rounded-full bg-brand px-2 py-0.5 text-xs font-semibold text-ink">
                    Cover
                  </span>
                )}
              </div>
              <div className="flex items-center justify-between gap-1 px-1.5 py-1">
                <div className="flex">
                  <button
                    type="button"
                    disabled={busy || i === 0}
                    onClick={() => move(i, i - 1)}
                    aria-label={`Move photo ${i + 1} earlier`}
                    className="px-1 text-sm text-ink-muted hover:text-ink disabled:opacity-30"
                  >
                    ←
                  </button>
                  <button
                    type="button"
                    disabled={busy || i === value.length - 1}
                    onClick={() => move(i, i + 1)}
                    aria-label={`Move photo ${i + 1} later`}
                    className="px-1 text-sm text-ink-muted hover:text-ink disabled:opacity-30"
                  >
                    →
                  </button>
                </div>
                <div className="flex items-center gap-1.5">
                  {i !== 0 && (
                    <button
                      type="button"
                      disabled={busy}
                      onClick={() => move(i, 0)}
                      className="text-xs font-semibold text-brand-ink hover:text-ink"
                    >
                      Make cover
                    </button>
                  )}
                  <button
                    type="button"
                    disabled={busy}
                    onClick={() => onChange(value.filter((_, at) => at !== i))}
                    aria-label={`Remove photo ${i + 1}`}
                    className="text-xs font-medium text-ink-muted hover:text-non-veg-ink"
                  >
                    Remove
                  </button>
                </div>
              </div>
            </li>
          ))}
        </ul>
      )}

      <div className="flex flex-wrap items-center gap-2">
        <label
          className={`inline-flex h-10 items-center rounded-field border border-line bg-white px-4 text-sm font-semibold text-ink hover:bg-canvas ${
            busy ? 'pointer-events-none opacity-60' : 'cursor-pointer'
          }`}
        >
          {busy ? 'Working…' : 'Add photos'}
          <input
            type="file"
            accept="image/*"
            // The whole point of a gallery: a seller's folder is fifteen
            // photos, and adding them one at a time is fifteen dialogs.
            multiple
            className="hidden"
            disabled={busy}
            onChange={(e) => {
              const files = [...(e.target.files ?? [])]
              // Cleared so picking the same files twice still fires a change.
              e.target.value = ''
              // Sequential, because each upload appends to `value` and two in
              // flight would both read the same array and one would win.
              void (async () => {
                for (const file of files) await run(() => uploadPhoto(file))
              })()
            }}
          />
        </label>

        <Button
          variant="secondary"
          disabled={busy}
          onClick={() => {
            setLinking((open) => !open)
            setError(null)
          }}
        >
          Use a link
        </Button>
      </div>

      {linking && (
        <div className="mt-3 flex items-end gap-2">
          <div className="min-w-0 flex-1">
            <Field
              label="Image link"
              value={link}
              onChange={(e) => setLink(e.target.value)}
              // Enter in a single-line input submits the surrounding form, and
              // this field lives inside the item dialog's form — pressing it
              // after pasting would save the gift without the photo. Fetch is
              // what Enter means here.
              onKeyDown={(e) => {
                if (e.key !== 'Enter') return
                e.preventDefault()
                if (link.trim() && !busy) void run(() => uploadPhotoByUrl(link))
              }}
              placeholder="https://example.com/photo.jpg"
              hint="We fetch a copy and host it ourselves, so it keeps working if the original moves."
            />
          </div>
          <Button
            className="mb-1"
            loading={busy}
            disabled={!link.trim()}
            onClick={() => void run(() => uploadPhotoByUrl(link))}
          >
            Fetch
          </Button>
        </div>
      )}

      {hint && <p className="mt-1.5 text-sm text-ink-muted">{hint}</p>}
      {error && <p className="mt-1.5 text-sm text-non-veg-ink">{error}</p>}
    </div>
  )
}
