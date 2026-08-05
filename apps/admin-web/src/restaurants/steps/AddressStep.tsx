import { useState } from 'react'
import { api } from '../../lib/api'
import type { RestaurantDetail } from '../../lib/api'
import { Button, Field } from '../../ui/primitives'
import { MapPicker, mapPickerAvailable } from '../../ui/MapPicker'
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
  const [picking, setPicking] = useState(false)

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

      {mapPickerAvailable ? (
        <div className="-mt-2">
          <Button variant="secondary" onClick={() => setPicking(true)}>
            {latitude && longitude ? 'Move the pin on the map' : 'Pick on the map'}
          </Button>
          <p className="mt-1.5 text-sm text-ink-muted">
            Required before publishing. Riders are paid by road distance from this
            point and each job is offered to the nearest one, so a digit typed wrong
            here is somebody&apos;s pay and somebody&apos;s dinner.
          </p>
        </div>
      ) : (
        <p className="-mt-2 text-sm text-ink-muted">
          Required before publishing. Right-click the kitchen in Google Maps and copy
          the pair it shows. <em>Set VITE_GOOGLE_MAPS_BROWSER_KEY to pick it on a map
          here instead of transcribing it.</em>
        </p>
      )}

      {picking && (
        <MapPicker
          initial={
            latitude && longitude
              ? { lat: Number(latitude), lng: Number(longitude) }
              : null
          }
          onCancel={() => setPicking(false)}
          onPick={(p) => {
            // Six decimals is about 11 cm — past the point where more digits
            // describe anything a rider could find, and it keeps the field
            // readable next to a hand-typed one.
            setLatitude(p.lat.toFixed(6))
            setLongitude(p.lng.toFixed(6))
            setPicking(false)
          }}
        />
      )}
    </StepFrame>
  )
}
