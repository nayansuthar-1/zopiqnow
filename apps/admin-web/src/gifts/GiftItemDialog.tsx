import { useState } from 'react'
import { GIFT_GST_SLABS } from '../lib/api'
import type { GiftItemRow } from '../lib/api'
import { GIFT_THUMB_WIDTH, deliveryUrl, parseAsset } from '../lib/cloudinary'
import { Banner, Button, Field, Modal, Toggle } from '../ui/primitives'
import { GalleryField } from '../ui/GalleryField'

/// Add or edit one gift. The same dialog for both — the fields are identical and
/// the only difference is whether an id goes back with them.
///
/// Shorter than `ItemDialog` because a gift knows less than a dish: no veg mark,
/// no bestseller flag, no prep time, no serving window, no strike-through price.
/// Those are all restaurant concepts and none of them means anything for a
/// handmade wall plate.

/// The card photo, derived from the gallery's first entry rather than asked for.
///
/// A `w_600` rendition of the same Cloudinary asset — the pair the seeded rows
/// already store, and the pair `admin_upsert_gift_item` verifies before it
/// writes. Sending nothing would still work: the RPC falls back to the gallery
/// entry itself. Sending this is what keeps the Gifts grid from downloading
/// fifteen 1200px images to draw fifteen thumbnails.
function coverOf(gallery: string[]): string {
  const first = gallery[0]
  if (!first) return ''
  const asset = parseAsset(first)
  return asset ? deliveryUrl(asset, GIFT_THUMB_WIDTH) : first
}

export function GiftItemDialog({
  item,
  categories,
  defaultCategory,
  busy,
  onSave,
  onCancel,
}: {
  item: GiftItemRow | null
  categories: string[]
  defaultCategory: string
  busy: boolean
  onSave: (payload: Record<string, unknown>) => void
  onCancel: () => void
}) {
  const [name, setName] = useState(item?.name ?? '')
  const [description, setDescription] = useState(item?.description ?? '')
  const [price, setPrice] = useState(item ? String(item.price) : '')
  const [category, setCategory] = useState(item?.category ?? defaultCategory)
  const [newCategory, setNewCategory] = useState('')
  const [isAvailable, setIsAvailable] = useState(item?.is_available ?? true)
  const [gstRateBps, setGstRateBps] = useState(String(item?.gst_rate_bps ?? 1800))
  /// `image_urls` and not `image_url`: the gallery is the field, and the card
  /// photo is computed from it on the way out. An older row seeded before 0023
  /// could have a thumbnail and an empty array, so it falls back to the one
  /// photo it has rather than opening as an empty gallery.
  const [gallery, setGallery] = useState<string[]>(
    item?.image_urls?.length ? item.image_urls : item?.image_url ? [item.image_url] : [],
  )

  const [error, setError] = useState<string | null>(null)
  const [uploading, setUploading] = useState(false)

  const creatingShelf = category === '__new__'
  const finalCategory = creatingShelf ? newCategory.trim() : category

  function submit() {
    if (!name.trim()) return setError('The gift needs a name.')
    if (!finalCategory) return setError('Every gift sits on a shelf. Pick one.')
    const value = Number(price)
    if (!Number.isFinite(value) || value <= 0) {
      return setError('A gift has to cost more than zero.')
    }

    onSave({
      ...(item ? { id: item.id } : {}),
      name: name.trim(),
      description: description.trim(),
      price: String(Math.round(value)),
      category: finalCategory,
      is_available: isAvailable,
      gst_rate_bps: gstRateBps,
      image_urls: gallery,
      image_url: coverOf(gallery),
    })
  }

  const gst = Number(gstRateBps)
  const rupees = Number(price)
  /// What the customer pays, shown while the price is typed. Gift prices are
  /// GST-*exclusive* like food (0096) — which is not what anybody assumes when
  /// they type 999 into a box labelled Price, and the difference is ₹180 on a
  /// ₹999 item. Stating it here is cheaper than an admin discovering it on a
  /// receipt. Not the real quote — `gift_bag_quote` rounds once per slab across
  /// the whole bag — but exact for a single unit, which is what this shows.
  const withTax =
    Number.isFinite(rupees) && rupees > 0 && Number.isFinite(gst)
      ? Math.round(rupees + (rupees * gst) / 10000)
      : null

  return (
    <Modal
      size="lg"
      busy={busy || uploading}
      onClose={onCancel}
      title={item ? 'Edit gift' : 'Add gift'}
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
            placeholder="Kamdhenu Cow Lippan Wall Plate"
          />

          <label className="block">
            <span className="mb-1.5 block text-sm font-medium text-ink">
              Description
            </span>
            <textarea
              rows={3}
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Hand-painted lippan art with inset mirror work, on a seasoned MDF base."
              className="w-full rounded-field border border-field bg-white px-3 py-2 text-sm text-ink outline-none placeholder:text-ink-muted focus:border-brand-ink"
            />
          </label>

          <div className="grid gap-4 sm:grid-cols-2">
            <Field
              label="Price (₹)"
              type="number"
              min={1}
              required
              value={price}
              onChange={(e) => setPrice(e.target.value)}
              placeholder="999"
              hint={
                withTax
                  ? `Before tax. The customer pays about ₹${withTax}.`
                  : 'Before tax, like every price on the platform.'
              }
            />
            <label className="block">
              <span className="mb-1.5 block text-sm font-medium text-ink">Shelf</span>
              <select
                value={category}
                onChange={(e) => setCategory(e.target.value)}
                className="h-11 w-full rounded-field border border-field bg-white px-3 text-sm outline-none focus:border-brand-ink"
              >
                {categories.map((c) => (
                  <option key={c} value={c}>
                    {c}
                  </option>
                ))}
                <option value="__new__">+ New shelf…</option>
              </select>
            </label>
          </div>

          {creatingShelf && (
            <Field
              label="New shelf name"
              autoFocus
              value={newCategory}
              onChange={(e) => setNewCategory(e.target.value)}
              placeholder="Wall Mirrors"
              hint="It joins the end of the shop. Move it with the arrows on its header."
            />
          )}

          <label className="block">
            <span className="mb-1.5 block text-sm font-medium text-ink">GST</span>
            <select
              value={gstRateBps}
              onChange={(e) => setGstRateBps(e.target.value)}
              className="h-11 w-full rounded-field border border-field bg-white px-3 text-sm outline-none focus:border-brand-ink"
            >
              {GIFT_GST_SLABS.map((s) => (
                <option key={s.value} value={String(s.value)}>
                  {s.label}
                </option>
              ))}
            </select>
            <p className="mt-1.5 text-sm text-ink-muted">
              18% unless somebody says otherwise. Handicrafts are often 12% — check
              the HSN before changing it, because this is what the receipt states.
            </p>
          </label>

          <Toggle
            label="Available"
            hint="Switch off to hide it from customers without deleting it."
            checked={isAvailable}
            onChange={setIsAvailable}
          />

          <GalleryField
            label="Photos"
            value={gallery}
            onChange={setGallery}
            onBusyChange={setUploading}
            hint="The first one is the card on the Gifts grid; the rest are the gallery a customer swipes. A gift with no photo shows a plain gradient."
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
            {item ? 'Save gift' : 'Add gift'}
          </Button>
        </div>
      </form>
    </Modal>
  )
}
