import { useState } from 'react'
import { api } from '../../lib/api'
import type { RestaurantDetail } from '../../lib/api'
import { uploadPhoto, UploadFailure } from '../../lib/uploads'
import { ChipsInput, Field, Toggle } from '../../ui/primitives'
import { StepFrame } from './StepFrame'

/// Everything a customer sees on the restaurant card, and nothing else. Address,
/// licence, and bank are later steps because none of them reach the app.

const commonCuisines = [
  'North Indian', 'South Indian', 'Chinese', 'Biryani', 'Pizza',
  'Burgers', 'Rolls', 'Desserts', 'Beverages', 'Street Food',
]

export function StorefrontStep({
  detail,
  onCreated,
  onSaved,
  onNext,
}: {
  detail: RestaurantDetail | null
  onCreated: (id: string) => void
  onSaved: () => Promise<void>
  onNext: () => void
}) {
  const r = detail?.restaurant
  const [name, setName] = useState(r?.name ?? '')
  const [cuisines, setCuisines] = useState<string[]>(r?.cuisines ?? [])
  const [priceForTwo, setPriceForTwo] = useState(r ? String(r.price_for_two) : '')
  const [etaMinutes, setEtaMinutes] = useState(r ? String(r.eta_minutes) : '')
  const [isVeg, setIsVeg] = useState(r?.is_veg ?? false)
  const [promo, setPromo] = useState(r?.promo_text ?? '')
  const [imageUrl, setImageUrl] = useState(r?.image_url ?? '')

  const [busy, setBusy] = useState(false)
  const [uploading, setUploading] = useState(false)
  const [error, setError] = useState<string | null>(null)

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

  async function save() {
    setBusy(true)
    setError(null)
    const profile = {
      name,
      cuisines,
      price_for_two: Number(priceForTwo),
      eta_minutes: Number(etaMinutes),
      is_veg: isVeg,
      promo_text: promo,
      image_url: imageUrl,
    }
    try {
      if (!r) {
        onCreated(await api.createRestaurant(profile))
      } else {
        await api.updateRestaurant(r.id, profile)
        await onSaved()
        onNext()
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  return (
    <StepFrame
      title="Storefront"
      description={
        r
          ? 'What a customer sees on the restaurant card. Everything here is public once you publish.'
          : 'A name is all it takes to start. Everything else — here and in the later steps — can be filled in whenever, in any order.'
      }
      error={error}
      busy={busy}
      saveLabel={r ? 'Save and continue' : 'Create draft'}
      onSave={() => void save()}
    >
      <Field
        label="Restaurant name"
        required
        value={name}
        onChange={(e) => setName(e.target.value)}
        placeholder="Paradise Biryani"
      />

      <ChipsInput
        label="Cuisines"
        hint="Customers search these as well as the name. Add the ones people would type."
        values={cuisines}
        onChange={setCuisines}
        suggestions={commonCuisines}
      />

      <div className="grid gap-5 sm:grid-cols-2">
        {/* Neither is required to create the draft (migration 0044): a cost for
            two is a number you work out after the menu exists, and a prep time
            is a guess until the kitchen has run a service. Both are required to
            publish, because both are printed on the customer's card. */}
        <Field
          label="Cost for two (₹)"
          type="number"
          min={0}
          value={priceForTwo}
          onChange={(e) => setPriceForTwo(e.target.value)}
          placeholder="400"
          hint="An estimate shown on the card, not a charge. Needed before publishing."
        />
        <Field
          label="Prep time (minutes)"
          type="number"
          min={0}
          value={etaMinutes}
          onChange={(e) => setEtaMinutes(e.target.value)}
          placeholder="30"
          hint="Becomes the ETA on the customer's order. Needed before publishing."
        />
      </div>

      <Toggle
        label="Pure vegetarian"
        hint="Shows the veg badge and includes it in the veg-only filter."
        checked={isVeg}
        onChange={setIsVeg}
      />

      <Field
        label="Offer line (optional)"
        value={promo}
        onChange={(e) => setPromo(e.target.value)}
        placeholder="50% OFF up to ₹100"
        hint="Leave it empty for no badge. This is display text — it does not create a coupon."
      />

      <div>
        <span className="mb-1.5 block text-sm font-medium text-ink">Cover photo</span>
        <div className="flex items-center gap-4">
          <div className="h-24 w-36 shrink-0 overflow-hidden rounded-[8px] border border-line bg-canvas">
            {imageUrl ? (
              <img src={imageUrl} alt="" className="h-full w-full object-cover" />
            ) : (
              <div className="flex h-full items-center justify-center text-xs text-ink-muted">
                No photo
              </div>
            )}
          </div>
          <div>
            <label className="inline-flex h-10 cursor-pointer items-center rounded-[8px] border border-line bg-white px-4 text-sm font-semibold text-ink hover:bg-canvas">
              {uploading ? 'Uploading…' : imageUrl ? 'Replace photo' : 'Upload photo'}
              <input
                type="file"
                accept="image/*"
                className="hidden"
                disabled={uploading}
                onChange={(e) => {
                  const file = e.target.files?.[0]
                  // Cleared so picking the same file twice still fires a change.
                  e.target.value = ''
                  if (file) void pickPhoto(file)
                }}
              />
            </label>
            <p className="mt-1.5 text-sm text-ink-muted">
              Required before publishing. Wide crops look best.
            </p>
          </div>
        </div>
      </div>
    </StepFrame>
  )
}
