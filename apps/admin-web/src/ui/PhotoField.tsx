import { useState } from 'react'
import { Button, Field } from './primitives'
import { ImageAdjuster } from './ImageAdjuster'
import { parseAsset } from '../lib/cloudinary'
import { UploadFailure, uploadPhoto, uploadPhotoByUrl } from '../lib/uploads'

/// One photo, three ways to get it, and a way to frame it once it is there.
///
/// Shared by the restaurant's cover and the menu item's picture because those two
/// screens had the same twenty lines of upload markup with different words around
/// them — and because the adjuster and the paste-a-link path would otherwise have
/// had to be written twice and drift apart once.

export function PhotoField({
  label,
  value,
  onChange,
  /// Width ÷ height of the frame the app draws this in — what the adjuster
  /// crops to. A cover is a wide card; a dish is a square tile.
  aspect,
  hint,
  /// The preview's own shape in the console, which is not always the app's: a
  /// square dish preview at 96px is easier to scan in a list than a wide one.
  previewClassName = 'h-24 w-36',
  onRemove,
  onBusyChange,
}: {
  label: string
  value: string
  onChange: (url: string) => void
  aspect: number
  hint?: string
  previewClassName?: string
  /// Offered only where having no photo is a real answer. A dish without one
  /// renders a tile with no art; a restaurant cover is required before
  /// publishing, so that screen does not offer it.
  onRemove?: () => void
  /// Raised while an upload or a fetch is in flight, so the form around this can
  /// refuse to save. Without it a Save pressed mid-upload writes the *old*
  /// `image_url` and the photo the admin just picked is silently discarded.
  onBusyChange?: (busy: boolean) => void
}) {
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [linking, setLinking] = useState(false)
  const [link, setLink] = useState('')
  const [adjusting, setAdjusting] = useState(false)

  /// Null for a photo we did not put in Cloudinary — an `image_url` from before
  /// this console, or one typed straight into the database. The adjuster is not
  /// offered for those rather than offered and then failing: we cannot crop an
  /// image on somebody else's host.
  const asset = parseAsset(value)

  async function run(work: () => Promise<string>) {
    setBusy(true)
    onBusyChange?.(true)
    setError(null)
    try {
      onChange(await work())
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

  return (
    <div>
      <span className="mb-1.5 block text-sm font-medium text-ink">{label}</span>

      <div className="flex items-start gap-4">
        <div
          className={`${previewClassName} shrink-0 overflow-hidden rounded-[8px] border border-line bg-canvas`}
        >
          {value ? (
            <img src={value} alt="" className="h-full w-full object-cover" />
          ) : (
            <div className="flex h-full items-center justify-center text-xs text-ink-muted">
              No photo
            </div>
          )}
        </div>

        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <label
              className={`inline-flex h-10 items-center rounded-[8px] border border-line bg-white px-4 text-sm font-semibold text-ink hover:bg-canvas ${
                busy ? 'pointer-events-none opacity-60' : 'cursor-pointer'
              }`}
            >
              {busy ? 'Working…' : value ? 'Replace' : 'Upload'}
              <input
                type="file"
                accept="image/*"
                className="hidden"
                disabled={busy}
                onChange={(e) => {
                  const file = e.target.files?.[0]
                  // Cleared so picking the same file twice still fires a change.
                  e.target.value = ''
                  if (file) void run(() => uploadPhoto(file))
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

            {value && (
              <Button
                variant="secondary"
                disabled={busy || !asset}
                onClick={() => setAdjusting(true)}
              >
                Adjust
              </Button>
            )}

            {value && onRemove && (
              <button
                type="button"
                disabled={busy}
                onClick={onRemove}
                className="text-sm font-medium text-ink-muted hover:text-non-veg"
              >
                Remove
              </button>
            )}
          </div>

          {linking && (
            <div className="mt-3 flex items-end gap-2">
              <div className="min-w-0 flex-1">
                <Field
                  label="Image link"
                  value={link}
                  onChange={(e) => setLink(e.target.value)}
                  // Enter in a single-line input submits the surrounding form,
                  // and this field is inside a wizard step's form — so pressing
                  // it after pasting a URL would save the step and move on
                  // instead of fetching the photo. Fetch is what Enter means
                  // here.
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

          {value && !asset && (
            <p className="mt-1.5 text-sm text-ink-muted">
              This photo is hosted somewhere else, so it cannot be adjusted. Upload
              it or fetch it with a link and the frame becomes editable.
            </p>
          )}

          {hint && <p className="mt-1.5 text-sm text-ink-muted">{hint}</p>}

          {error && <p className="mt-1.5 text-sm text-non-veg">{error}</p>}
        </div>
      </div>

      {adjusting && asset && (
        <ImageAdjuster
          asset={asset}
          aspect={aspect}
          title={`Adjust ${label.toLowerCase()}`}
          onCancel={() => setAdjusting(false)}
          onDone={(url) => {
            onChange(url)
            setAdjusting(false)
          }}
        />
      )}
    </div>
  )
}
