import { useState } from 'react'
import type { GiftShopRow } from '../lib/api'
import { GIFT_GALLERY_WIDTH, deliveryUrl, parseAsset } from '../lib/cloudinary'
import { Banner, Button, Field, Modal, Toggle } from '../ui/primitives'
import { PhotoField } from '../ui/PhotoField'

/// Add or edit a gift shop.
///
/// Four fields and a switch. A gift shop is deliberately leaner than a
/// restaurant (0022): no address, no coordinates, no hours, no owner, no bank
/// details — Zopiqnow packs and couriers every gift itself (0096), so none of
/// the things a restaurant needs in order to be *reached* apply here.
///
/// **`rating` is not on this form**, and that is the one omission worth stating.
/// Nothing on the platform computes a gift shop's rating yet, so the only way it
/// could get a value is an admin typing one — which is not a rating, it is
/// fabricated social proof sitting exactly where a customer reads other
/// people's opinion. The column stays null and the app shows "unrated". Same
/// argument 0108 made about dish ratings.

export function GiftShopDialog({
  shop,
  busy,
  onSave,
  onCancel,
}: {
  shop: GiftShopRow | null
  busy: boolean
  onSave: (payload: Record<string, unknown>) => void
  onCancel: () => void
}) {
  const [name, setName] = useState(shop?.name ?? '')
  const [tagline, setTagline] = useState(shop?.tagline ?? '')
  const [description, setDescription] = useState(shop?.description ?? '')
  const [imageUrl, setImageUrl] = useState(shop?.image_url ?? '')
  const [isActive, setIsActive] = useState(shop?.is_active ?? true)

  const [error, setError] = useState<string | null>(null)
  const [uploading, setUploading] = useState(false)

  function submit() {
    if (!name.trim()) return setError('The shop needs a name.')

    onSave({
      ...(shop ? { id: shop.id } : {}),
      name: name.trim(),
      tagline: tagline.trim(),
      description: description.trim(),
      image_url: imageUrl,
      is_active: isActive,
    })
  }

  return (
    <Modal
      busy={busy || uploading}
      onClose={onCancel}
      title={shop ? 'Edit shop' : 'Add shop'}
    >
      <form
        onSubmit={(e) => {
          e.preventDefault()
          submit()
        }}
      >
        <div className="space-y-4">
          <Field
            label="Name"
            required
            autoFocus
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Handmade Art Studio"
            hint={
              shop
                ? 'Renaming is safe — the shop keeps its id, and past orders keep pointing at it.'
                : 'The id is worked out from this, so pick the real name now if you know it.'
            }
          />

          <Field
            label="Tagline"
            value={tagline}
            onChange={(e) => setTagline(e.target.value)}
            placeholder="Hand-painted lippan and mirror work"
            hint="One line, shown under the name on the shop page."
          />

          <label className="block">
            <span className="mb-1.5 block text-sm font-medium text-ink">
              Description
            </span>
            <textarea
              rows={3}
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              className="w-full rounded-[8px] border border-line bg-white px-3 py-2 text-sm text-ink outline-none placeholder:text-ink-muted focus:border-brand"
            />
          </label>

          <Toggle
            label="Live"
            hint="Switched off, the shop and everything in it disappear from the app. Nothing is deleted."
            checked={isActive}
            onChange={setIsActive}
          />

          <PhotoField
            label="Cover"
            value={imageUrl}
            // Delivered at the gallery width rather than raw, for the same
            // reason the gift gallery is: a seller's original is around 8 MB.
            onChange={(url) => {
              const asset = parseAsset(url)
              setImageUrl(asset ? deliveryUrl(asset, GIFT_GALLERY_WIDTH) : url)
            }}
            // A wide banner across the top of the shop page.
            aspect={16 / 9}
            onRemove={() => setImageUrl('')}
            onBusyChange={setUploading}
            hint="Optional. Without one the app draws its branded gradient."
          />
        </div>

        {error && (
          <Banner tone="error" className="mt-4" onDismiss={() => setError(null)}>
            {error}
          </Banner>
        )}

        <div className="mt-6 flex justify-end gap-2">
          <Button type="button" variant="secondary" onClick={onCancel} disabled={busy}>
            Cancel
          </Button>
          <Button type="submit" loading={busy || uploading}>
            {shop ? 'Save shop' : 'Add shop'}
          </Button>
        </div>
      </form>
    </Modal>
  )
}
