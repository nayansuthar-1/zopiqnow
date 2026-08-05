import { useEffect, useState } from 'react'
import { api } from '../lib/api'
import type { MenuItemRow, OptionGroup } from '../lib/api'
import { Banner, Button, Field, Modal, Toggle } from '../ui/primitives'
import { PhotoField } from '../ui/PhotoField'

/// Add or edit one dish. The same dialog for both, because they are the same
/// fields — the only difference is whether an id goes back with them.

/// The size vocabulary, and the group's name in the database.
///
/// A size is not a new kind of thing (0048): it is an option group whose options
/// carry a price delta on top of the dish's own price. The group is found by
/// name, which is what lets this dialog edit *its* group and leave a vendor's
/// "Extra toppings" alone.
const SIZE_GROUP = 'Size'
const SIZE_NAMES = ['Small', 'Medium', 'Large', 'Extra Large'] as const

type SizeRow = { name: string; on: boolean; delta: string }

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
  /// [groups] is every option group the dish should end up with, or undefined
  /// when this dialog has nothing to say about them — a new dish whose options
  /// have never been read, or an edit where the read failed. Undefined means
  /// "leave them alone"; an array means "make them exactly this", because that
  /// is the RPC's contract.
  onSave: (payload: Record<string, unknown>, groups?: OptionGroup[]) => void
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

  // --- Sizes (migration 0106) ------------------------------------------------
  /// The four the platform offers, in the order a menu reads them. Fixed rather
  /// than free text so that "Large" means the same thing on every menu — a
  /// customer filtering or comparing across restaurants is the whole reason to
  /// have a vocabulary at all.
  const [sizes, setSizes] = useState<SizeRow[]>(() =>
    SIZE_NAMES.map((name) => ({ name, on: false, delta: '0' })),
  )
  /// Off means a customer may order the dish without answering — a `(0, 1)`
  /// group. On makes it `(1, 1)`. Optional is the default because that is what
  /// was asked for, and because turning an existing one-tap dish into a
  /// question is a change every customer feels.
  const [sizeRequired, setSizeRequired] = useState(false)
  /// Every group that is *not* sizes, carried through untouched. The write RPC
  /// replaces all of a dish's groups, so a dialog that sent only its own would
  /// silently delete the vendor's add-ons.
  const [otherGroups, setOtherGroups] = useState<OptionGroup[] | null>(null)
  /// Null until the read lands. Until then the dialog says nothing about groups
  /// at all rather than guessing there are none.
  const [optionsLoaded, setOptionsLoaded] = useState(!item)

  useEffect(() => {
    if (!item) return
    let cancelled = false
    api
      .menuItemOptions(item.id)
      .then((groups) => {
        if (cancelled) return
        const size = groups.find((g) => g.name === SIZE_GROUP)
        setOtherGroups(groups.filter((g) => g.name !== SIZE_GROUP))
        if (size) {
          setSizeRequired(size.min_select >= 1)
          setSizes(
            SIZE_NAMES.map((name) => {
              const found = size.options.find((o) => o.name === name)
              return {
                name,
                on: Boolean(found),
                delta: found ? String(found.price_delta) : '0',
              }
            }),
          )
        }
        setOptionsLoaded(true)
      })
      .catch(() => {
        // A failed read must not turn into a delete. Leaving this false is what
        // makes the save send no groups at all.
        if (!cancelled) setOptionsLoaded(false)
      })
    return () => {
      cancelled = true
    }
  }, [item])

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
    const chosen = sizes.filter((s) => s.on)
    if (chosen.length === 1) {
      return setError(
        'One size is not a choice. Add another, or switch sizes off entirely.',
      )
    }
    if (chosen.some((s) => !Number.isFinite(Number(s.delta)) || Number(s.delta) < 0)) {
      return setError(
        'A size adds to the dish price, so it cannot be negative. Set the dish price to the cheapest size and add from there.',
      )
    }

    onSave(
      {
        ...(item ? { id: item.id } : {}),
        name: name.trim(),
        description: description.trim(),
        price: Math.round(value),
        category: finalCategory,
        is_veg: isVeg,
        is_bestseller: isBestseller,
        is_available: isAvailable,
        image_url: imageUrl,
      },
      groupsToSave(),
    )
  }

  /// Every group the dish should end up with, or undefined to leave them alone.
  ///
  /// Undefined whenever the existing groups have not been read — a failed read
  /// followed by a save would otherwise delete groups this dialog never saw.
  function groupsToSave(): OptionGroup[] | undefined {
    if (!optionsLoaded) return undefined

    const chosen = sizes.filter((s) => s.on)
    const rest = otherGroups ?? []
    if (chosen.length === 0) return rest

    return [
      {
        name: SIZE_GROUP,
        // The pair *is* the behaviour: (1,1) must choose, (0,1) may choose.
        min_select: sizeRequired ? 1 : 0,
        max_select: 1,
        rank: 0,
        options: chosen.map((s, i) => ({
          name: s.name,
          price_delta: Math.round(Number(s.delta)),
          is_available: true,
          rank: i,
        })),
      },
      ...rest.map((g, i) => ({ ...g, rank: i + 1 })),
    ]
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

          <div className="rounded-[8px] border border-line p-4">
            <div className="flex items-baseline justify-between gap-4">
              <span className="text-sm font-medium text-ink">Sizes</span>
              <span className="text-sm text-ink-muted">
                Added to the dish price
              </span>
            </div>
            <p className="mt-1 text-sm text-ink-muted">
              Optional. Tick the sizes this dish comes in — the price above is the
              cheapest one, and each size adds to it.
            </p>

            <div className="mt-3 space-y-2">
              {sizes.map((s, i) => (
                <div key={s.name} className="flex items-center gap-3">
                  <label className="flex flex-1 items-center gap-2.5">
                    <input
                      type="checkbox"
                      checked={s.on}
                      onChange={(e) =>
                        setSizes((rows) =>
                          rows.map((r, j) =>
                            j === i ? { ...r, on: e.target.checked } : r,
                          ),
                        )
                      }
                      className="h-4 w-4 accent-brand"
                    />
                    <span className="text-sm text-ink">{s.name}</span>
                  </label>
                  <div className="flex items-center gap-1.5">
                    <span className="text-sm text-ink-muted">+₹</span>
                    <input
                      inputMode="numeric"
                      value={s.delta}
                      disabled={!s.on}
                      onChange={(e) =>
                        setSizes((rows) =>
                          rows.map((r, j) =>
                            j === i
                              ? { ...r, delta: e.target.value.replace(/[^\d]/g, '') }
                              : r,
                          ),
                        )
                      }
                      className="h-9 w-24 rounded-[8px] border border-line px-3 text-sm text-ink disabled:bg-canvas disabled:text-ink-muted"
                    />
                  </div>
                </div>
              ))}
            </div>

            {sizes.some((s) => s.on) && (
              <div className="mt-4 border-t border-line pt-3">
                <Toggle
                  label="Customers must choose a size"
                  hint="Off means they can order it without picking one, and pay the price above."
                  checked={sizeRequired}
                  onChange={setSizeRequired}
                />
              </div>
            )}

            {item && !optionsLoaded && (
              <p className="mt-3 text-sm text-ink-muted">
                This dish&apos;s existing options could not be read, so saving will
                leave them exactly as they are.
              </p>
            )}
          </div>

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
