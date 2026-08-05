import { useState } from 'react'
import { api } from '../../lib/api'
import type { RestaurantDetail } from '../../lib/api'
import { ChipsInput, Field, Toggle } from '../../ui/primitives'
import { PhotoField } from '../../ui/PhotoField'
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
  const [isVeg, setIsVeg] = useState(r?.is_veg ?? false)
  const [promo, setPromo] = useState(r?.promo_text ?? '')
  const [imageUrl, setImageUrl] = useState(r?.image_url ?? '')

  const [busy, setBusy] = useState(false)
  /// Save is blocked while a photo is uploading. It was not before, and that was
  /// a real hole rather than a tidy-up: saving mid-upload wrote the *old*
  /// `image_url`, so the photo the admin had just picked vanished with no error.
  const [uploading, setUploading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function save() {
    setBusy(true)
    setError(null)
    // No `price_for_two` and no `eta_minutes` (0101). Omitted rather than sent
    // as zero: the update RPC leaves a field it was not given alone, so a
    // restaurant onboarded before this keeps whatever it had instead of having
    // it quietly wiped by a form that no longer asks.
    const profile = {
      name,
      cuisines,
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
      busy={busy || uploading}
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

      {/* Cost for two and prep time used to sit here, and both are gone in
          0101. Prep time depends on what was ordered, and the kitchen answers
          it per order when it accepts — a single number invented during
          onboarding was a worse answer competing with a better one. Cost for
          two is a made-up average on any menu with both chai and thalis. The
          columns still exist; nobody is asked for them and nobody shows them. */}

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

      <PhotoField
        label="Cover photo"
        value={imageUrl}
        onChange={setImageUrl}
        // 16:10, which is what `restaurant_card.dart` draws it in. The adjuster
        // frames to the same shape, so what an admin lines up here is what a
        // customer sees rather than something the card crops again.
        aspect={16 / 10}
        hint="Required before publishing — and the first thing a customer sees."
        onBusyChange={setUploading}
      />
    </StepFrame>
  )
}
