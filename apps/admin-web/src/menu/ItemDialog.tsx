import { useState } from 'react'
import type { MenuItemRow } from '../lib/api'
import { Banner, Button, Field, Modal, Toggle } from '../ui/primitives'
import { PhotoField } from '../ui/PhotoField'

/// Add or edit one dish. The same dialog for both, because they are the same
/// fields — the only difference is whether an id goes back with them.
///
/// This dialog says nothing about a dish's option groups. It used to edit sizes
/// (0106) and no longer does, which means it must not send groups at all: the
/// write RPC replaces every group a dish has, so a dialog that sent an empty
/// list would delete the vendor's add-ons on the first save.

export function ItemDialog({
  item,
  categories,
  defaultCategory,
  busy,
  onSave,
  onCancel,
}: {
  item: MenuItemRow | null
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
  const [isVeg, setIsVeg] = useState(item?.is_veg ?? false)
  const [isBestseller, setIsBestseller] = useState(item?.is_bestseller ?? false)
  const [isAvailable, setIsAvailable] = useState(item?.is_available ?? true)
  const [imageUrl, setImageUrl] = useState(item?.image_url ?? '')

  const [error, setError] = useState<string | null>(null)
  /// Owned by the photo field now, mirrored here so Save cannot land while a
  /// photo is still on its way up.
  const [uploading, setUploading] = useState(false)

  const creatingSection = category === '__new__'
  const finalCategory = creatingSection ? newCategory.trim() : category

  function submit() {
    if (!name.trim()) return setError('The dish needs a name.')
    if (!finalCategory) return setError('Every dish belongs to a section. Pick one.')
    const value = Number(price)
    if (!Number.isFinite(value) || value <= 0) {
      return setError('A dish has to cost more than zero.')
    }

    onSave({
      ...(item ? { id: item.id } : {}),
      name: name.trim(),
      description: description.trim(),
      price: Math.round(value),
      category: finalCategory,
      is_veg: isVeg,
      is_bestseller: isBestseller,
      is_available: isAvailable,
      image_url: imageUrl,
    })
  }

  return (
    <Modal
      size="lg"
      busy={busy || uploading}
      onClose={onCancel}
      title={item ? 'Edit dish' : 'Add dish'}
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
            placeholder="Chicken Biryani"
          />

          <label className="block">
            <span className="mb-1.5 block text-sm font-medium text-ink">Description</span>
            <textarea
              rows={2}
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Long-grain rice, slow-cooked with saffron"
              className="w-full rounded-[8px] border border-line bg-white px-3 py-2 text-sm text-ink outline-none placeholder:text-ink-muted focus:border-brand"
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
              placeholder="320"
            />
            <label className="block">
              <span className="mb-1.5 block text-sm font-medium text-ink">Section</span>
              <select
                value={category}
                onChange={(e) => setCategory(e.target.value)}
                className="h-11 w-full rounded-[8px] border border-line bg-white px-3 text-sm outline-none focus:border-brand"
              >
                {categories.map((c) => (
                  <option key={c} value={c}>
                    {c}
                  </option>
                ))}
                <option value="__new__">+ New section…</option>
              </select>
            </label>
          </div>

          {creatingSection && (
            <Field
              label="New section name"
              autoFocus
              value={newCategory}
              onChange={(e) => setNewCategory(e.target.value)}
              placeholder="Desserts"
              hint="It joins the end of the menu. Drag the section header to move it."
            />
          )}

          <div className="grid gap-3 sm:grid-cols-2">
            <Toggle label="Vegetarian" checked={isVeg} onChange={setIsVeg} />
            <Toggle label="Bestseller" checked={isBestseller} onChange={setIsBestseller} />
          </div>
          <Toggle
            label="Available"
            hint="Switch off to hide it from customers without deleting it."
            checked={isAvailable}
            onChange={setIsAvailable}
          />

          <PhotoField
            label="Photo"
            value={imageUrl}
            onChange={setImageUrl}
            // 118 × 96, the art box in `menu_item_tile.dart`. Cropping to the
            // tile's own shape is what stops a tall photo of a thali arriving
            // as a centre-cut of rice.
            aspect={118 / 96}
            previewClassName="h-16 w-20"
            onRemove={() => setImageUrl('')}
            onBusyChange={setUploading}
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
            {item ? 'Save dish' : 'Add dish'}
          </Button>
        </div>
      </form>
    </Modal>
  )
}
