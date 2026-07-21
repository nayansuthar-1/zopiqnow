import { useState } from 'react'
import type { MenuItemRow } from '../lib/api'
import { uploadPhoto, UploadFailure } from '../lib/uploads'
import { Button, Field, Toggle } from '../ui/primitives'

/// Add or edit one dish. The same dialog for both, because they are the same
/// fields — the only difference is whether an id goes back with them.

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

  const [uploading, setUploading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const creatingSection = category === '__new__'
  const finalCategory = creatingSection ? newCategory.trim() : category

  async function pickPhoto(file: File) {
    setUploading(true)
    setError(null)
    try {
      setImageUrl(await uploadPhoto(file))
    } catch (e) {
      setError(e instanceof UploadFailure ? e.message : 'That photo could not be uploaded.')
    } finally {
      setUploading(false)
    }
  }

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
    <div
      className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/40 p-6"
      onClick={onCancel}
    >
      <form
        className="w-full max-w-lg rounded-[12px] bg-white p-6"
        onClick={(e) => e.stopPropagation()}
        onSubmit={(e) => {
          e.preventDefault()
          submit()
        }}
      >
        <h2 className="text-base font-bold text-ink">
          {item ? 'Edit dish' : 'Add dish'}
        </h2>

        <div className="mt-5 space-y-4">
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

          <div>
            <span className="mb-1.5 block text-sm font-medium text-ink">Photo</span>
            <div className="flex items-center gap-3">
              <div className="h-16 w-20 shrink-0 overflow-hidden rounded-[8px] border border-line bg-canvas">
                {imageUrl ? (
                  <img src={imageUrl} alt="" className="h-full w-full object-cover" />
                ) : (
                  <div className="flex h-full items-center justify-center text-xs text-ink-muted">
                    None
                  </div>
                )}
              </div>
              <label className="inline-flex h-10 cursor-pointer items-center rounded-[8px] border border-line px-4 text-sm font-semibold text-ink hover:bg-canvas">
                {uploading ? 'Uploading…' : imageUrl ? 'Replace' : 'Upload'}
                <input
                  type="file"
                  accept="image/*"
                  className="hidden"
                  disabled={uploading}
                  onChange={(e) => {
                    const file = e.target.files?.[0]
                    e.target.value = ''
                    if (file) void pickPhoto(file)
                  }}
                />
              </label>
              {imageUrl && (
                <button
                  type="button"
                  onClick={() => setImageUrl('')}
                  className="text-sm font-medium text-ink-muted hover:text-non-veg"
                >
                  Remove
                </button>
              )}
            </div>
          </div>
        </div>

        {error && (
          <p className="mt-4 rounded-[8px] bg-non-veg-soft px-4 py-3 text-sm text-non-veg">
            {error}
          </p>
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
    </div>
  )
}
