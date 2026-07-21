import { useState } from 'react'
import { api } from '../../lib/api'
import type { RestaurantDetail } from '../../lib/api'
import { Field } from '../../ui/primitives'
import { StepFrame } from './StepFrame'

/// Where the kitchen is and who to call about it. None of this reaches the
/// customer app today — it exists because a rider sent to collect an order has
/// been navigating to a restaurant *name*, and because a kitchen that goes quiet
/// mid-order needs a phone number attached to it.

export function AddressStep({
  id,
  detail,
  onSaved,
  onNext,
}: {
  id: string
  detail: RestaurantDetail | null
  onSaved: () => Promise<void>
  onNext: () => void
}) {
  const r = detail?.restaurant
  const [ownerName, setOwnerName] = useState(r?.owner_name ?? '')
  const [phone, setPhone] = useState(r?.contact_phone ?? '')
  const [addressLine, setAddressLine] = useState(r?.address_line ?? '')
  const [city, setCity] = useState(r?.city ?? '')
  const [state, setState] = useState(r?.state ?? '')
  const [pincode, setPincode] = useState(r?.pincode ?? '')
  const [latitude, setLatitude] = useState(r?.latitude != null ? String(r.latitude) : '')
  const [longitude, setLongitude] = useState(r?.longitude != null ? String(r.longitude) : '')

  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  /// Checked here so the admin gets a sentence instead of a constraint violation
  /// from `restaurants_pincode_is_indian`. The database still refuses bad values —
  /// this is the courtesy, that is the guard.
  function localProblem(): string | null {
    if (phone && !/^[6-9][0-9]{9}$/.test(phone)) {
      return 'An Indian mobile number is 10 digits starting 6–9.'
    }
    if (pincode && !/^[1-9][0-9]{5}$/.test(pincode)) {
      return 'A pincode is 6 digits and cannot start with 0.'
    }
    if ((latitude === '') !== (longitude === '')) {
      return 'Enter both latitude and longitude, or neither.'
    }
    return null
  }

  async function save() {
    const problem = localProblem()
    if (problem) {
      setError(problem)
      return
    }
    setBusy(true)
    setError(null)
    try {
      await api.updateRestaurant(id, {
        owner_name: ownerName,
        contact_phone: phone,
        address_line: addressLine,
        city,
        state,
        pincode,
        latitude: latitude === '' ? null : Number(latitude),
        longitude: longitude === '' ? null : Number(longitude),
      })
      await onSaved()
      onNext()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  return (
    <StepFrame
      title="Address and contact"
      description="Where a rider collects the order, and who to call when something goes wrong."
      error={error}
      busy={busy}
      onSave={() => void save()}
    >
      <div className="grid gap-5 sm:grid-cols-2">
        <Field
          label="Owner's name"
          value={ownerName}
          onChange={(e) => setOwnerName(e.target.value)}
          placeholder="Ramesh Patel"
        />
        <Field
          label="Contact phone"
          inputMode="numeric"
          maxLength={10}
          value={phone}
          onChange={(e) => setPhone(e.target.value.replace(/\D/g, ''))}
          placeholder="9876543210"
          hint="10 digits, no +91."
        />
      </div>

      <Field
        label="Address"
        value={addressLine}
        onChange={(e) => setAddressLine(e.target.value)}
        placeholder="Shop 4, Ashram Road, Navrangpura"
      />

      <div className="grid gap-5 sm:grid-cols-3">
        <Field label="City" value={city} onChange={(e) => setCity(e.target.value)} placeholder="Ahmedabad" />
        <Field label="State" value={state} onChange={(e) => setState(e.target.value)} placeholder="Gujarat" />
        <Field
          label="Pincode"
          inputMode="numeric"
          maxLength={6}
          value={pincode}
          onChange={(e) => setPincode(e.target.value.replace(/\D/g, ''))}
          placeholder="380009"
        />
      </div>

      <div className="grid gap-5 sm:grid-cols-2">
        <Field
          label="Latitude"
          value={latitude}
          onChange={(e) => setLatitude(e.target.value)}
          placeholder="23.0225"
        />
        <Field
          label="Longitude"
          value={longitude}
          onChange={(e) => setLongitude(e.target.value)}
          placeholder="72.5714"
        />
      </div>
      <p className="-mt-2 text-sm text-ink-muted">
        Optional for now. Right-click the kitchen in Google Maps and copy the pair it
        shows. The feed&apos;s &ldquo;2.1 km away&rdquo; is still a typed-in number for
        every restaurant — these coordinates are what will eventually replace it.
      </p>
    </StepFrame>
  )
}
