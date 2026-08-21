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
  /// Prep time, back on this step in 0134. Held as a string because a number
  /// input that has been cleared is `''`, not 0, and the two must not be
  /// confused — the whole point of the migration is that 0 stops reaching the
  /// feed. Defaults to the column's own 30 on a new draft so a restaurant is
  /// never created without a usable number.
  const [eta, setEta] = useState(String(r?.eta_minutes ?? 30))

  const [busy, setBusy] = useState(false)
  /// Save is blocked while a photo is uploading. It was not before, and that was
  /// a real hole rather than a tidy-up: saving mid-upload wrote the *old*
  /// `image_url`, so the photo the admin had just picked vanished with no error.
  const [uploading, setUploading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function save() {
    // Checked here rather than left to the RPC so the admin gets the message
    // next to the field instead of a red bar at the top of the step. The RPC
    // refuses <= 0 as well, and the table's check constraint refuses it under
    // both of them (0134) — this is the courteous layer, not the safe one.
    const etaMinutes = Number(eta)
    if (!Number.isInteger(etaMinutes) || etaMinutes <= 0) {
      setError('Prep time has to be a whole number of minutes, above zero.')
      return
    }

    setBusy(true)
    setError(null)
    // Still no `price_for_two` — 0101 retired it and nothing shows it. Prep
    // time came back in 0134: it is the kitchen's share of the wait, the only
    // number the *feed* has, and with nobody able to fill it in four published
    // restaurants sat at zero and told customers their food arrived in no time.
    const profile = {
      name,
      cuisines,
      is_veg: isVeg,
      promo_text: promo,
      image_url: imageUrl,
      eta_minutes: etaMinutes,
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

      {/* Cost for two is still gone (0101) — a made-up average on any menu with
          both chai and thalis, and nothing displays it.

          Prep time came back in 0134. 0101 removed it because the kitchen
          answers it better per order when it accepts, which is true of the
          *order's* ETA and only that. The feed is read long before any order
          exists, and this column is the only number it has — so with nobody
          able to set it, four published restaurants read "0 min". The vendor
          can edit the same field from Edit profile in their own app. */}
      <Field
        label="Prep time (minutes)"
        required
        type="number"
        min={1}
        value={eta}
        onChange={(e) => setEta(e.target.value)}
        placeholder="30"
        hint="Cooking and packing only — not the ride. The customer's card adds travel time from this kitchen to their address on top of it."
      />


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
