import { useState } from 'react'
import { api } from '../../lib/api'
import type { RestaurantDetail } from '../../lib/api'
import { signedDocumentUrl, uploadDocument, UploadFailure } from '../../lib/uploads'
import { Field } from '../../ui/primitives'
import { StepFrame } from './StepFrame'

/// The papers. Nothing on this screen ever reaches a customer, a vendor, or the
/// three Flutter apps — `restaurant_legal` has no RLS policy for anyone (0028) and
/// the scans live in a private bucket (0034).

function DocumentField({
  label,
  hint,
  restaurantId,
  kind,
  path,
  onChange,
}: {
  label: string
  hint: string
  restaurantId: string
  kind: 'fssai' | 'pan'
  path: string | null
  onChange: (next: string | null) => void
}) {
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function upload(file: File) {
    setBusy(true)
    setError(null)
    try {
      onChange(await uploadDocument(restaurantId, kind, file))
    } catch (e) {
      setError(e instanceof UploadFailure ? e.message : 'That file could not be uploaded.')
    } finally {
      setBusy(false)
    }
  }

  async function open() {
    if (!path) return
    try {
      // A fresh link each time, good for five minutes. There is no permanent URL
      // for these files anywhere, which is the whole point of the private bucket.
      window.open(await signedDocumentUrl(path), '_blank', 'noopener')
    } catch {
      setError('That document could not be opened.')
    }
  }

  return (
    <div>
      <span className="mb-1.5 block text-sm font-medium text-ink">{label}</span>
      <div className="flex flex-wrap items-center gap-2">
        <label className="inline-flex h-10 cursor-pointer items-center rounded-[8px] border border-line bg-white px-4 text-sm font-semibold text-ink hover:bg-canvas">
          {busy ? 'Uploading…' : path ? 'Replace file' : 'Upload file'}
          <input
            type="file"
            accept="application/pdf,image/*"
            className="hidden"
            disabled={busy}
            onChange={(e) => {
              const file = e.target.files?.[0]
              e.target.value = ''
              if (file) void upload(file)
            }}
          />
        </label>
        {path && (
          <>
            <button
              type="button"
              onClick={() => void open()}
              className="text-sm font-semibold text-brand hover:text-brand-deep"
            >
              View
            </button>
            <button
              type="button"
              onClick={() => onChange(null)}
              className="text-sm font-medium text-ink-muted hover:text-non-veg"
            >
              Remove
            </button>
          </>
        )}
      </div>
      <p className="mt-1.5 text-sm text-ink-muted">{hint}</p>
      {error && <p className="mt-1.5 text-sm text-non-veg">{error}</p>}
    </div>
  )
}

export function LegalStep({
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
  const l = detail?.legal
  const [fssai, setFssai] = useState(l?.fssai_number ?? '')
  const [fssaiExpiry, setFssaiExpiry] = useState(l?.fssai_expiry ?? '')
  const [fssaiDoc, setFssaiDoc] = useState<string | null>(l?.fssai_doc_path ?? null)
  const [gst, setGst] = useState(l?.gst_number ?? '')
  const [pan, setPan] = useState(l?.pan_number ?? '')
  const [panDoc, setPanDoc] = useState<string | null>(l?.pan_doc_path ?? null)

  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const expired =
    fssaiExpiry !== '' && fssaiExpiry < new Date().toISOString().slice(0, 10)

  async function save() {
    setBusy(true)
    setError(null)
    try {
      await api.setLegal(id, {
        fssai_number: fssai,
        // An empty date string is no date, not the epoch.
        fssai_expiry: fssaiExpiry === '' ? null : fssaiExpiry,
        fssai_doc_path: fssaiDoc,
        gst_number: gst,
        pan_number: pan,
        pan_doc_path: panDoc,
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
      title="Licences and tax"
      description="Never shown to customers, and not visible to the restaurant either. Only Zopiqnow staff can see this."
      error={error}
      busy={busy}
      onSave={() => void save()}
    >
      <div className="grid gap-5 sm:grid-cols-2">
        <Field
          label="FSSAI licence number"
          inputMode="numeric"
          maxLength={14}
          value={fssai}
          onChange={(e) => setFssai(e.target.value.replace(/\D/g, ''))}
          placeholder="12345678901234"
          hint="14 digits."
        />
        <Field
          label="FSSAI expiry"
          type="date"
          value={fssaiExpiry}
          onChange={(e) => setFssaiExpiry(e.target.value)}
          error={expired ? 'This licence has already expired.' : undefined}
          hint={expired ? undefined : 'Publishing is blocked once this date passes.'}
        />
      </div>

      <DocumentField
        label="FSSAI certificate"
        hint="PDF or photo, up to 10 MB. Stored privately — links expire after five minutes."
        restaurantId={id}
        kind="fssai"
        path={fssaiDoc}
        onChange={setFssaiDoc}
      />

      <Field
        label="PAN"
        maxLength={10}
        value={pan}
        onChange={(e) => setPan(e.target.value.toUpperCase())}
        placeholder="ABCDE1234F"
        hint="Required before publishing."
      />

      <DocumentField
        label="PAN card"
        hint="PDF or photo, up to 10 MB."
        restaurantId={id}
        kind="pan"
        path={panDoc}
        onChange={setPanDoc}
      />

      <Field
        label="GST number (optional)"
        maxLength={15}
        value={gst}
        onChange={(e) => setGst(e.target.value.toUpperCase())}
        placeholder="24ABCDE1234F1Z5"
        hint="A small kitchen under the threshold legitimately has none. Leave it empty."
      />
    </StepFrame>
  )
}
